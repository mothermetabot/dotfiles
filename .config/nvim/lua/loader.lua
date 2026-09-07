-- A tiny lazy-loading harness on top of Neovim 0.12's built-in `vim.pack`.
--
-- `vim.pack` only installs + sources plugins; it has no event/ft/cmd/keys
-- lazy-loading. This module adds that, while keeping startup empty: every
-- enabled plugin is installed with `load = false` (== `:packadd!`, i.e. put on
-- 'runtimepath' but DON'T source `plugin/`), then sourced on demand via
-- `:packadd` + its `config()` the first time a trigger fires.
--
-- Spec shape (see lua/plugins.lua):
--   {
--     src     = 'https://github.com/user/repo',  -- required (string spec == src)
--     name    = 'repo',                           -- optional, derived from src
--     version = 'main' | vim.version.range('1.*'),-- optional git ref / range
--     enabled = true,                             -- set false to disable entirely
--     -- triggers (omit all => load eagerly at startup):
--     event   = 'BufReadPre' | { 'BufReadPre', 'BufNewFile' },
--     ft      = 'lua' | { 'cs', 'razor' },
--     cmd     = 'Oil' | { 'Oil', 'TodoTelescope' },
--     keys    = { '<leader>ss', { '<C-k>', mode = { 'n', 'v' } } },
--     deps    = { 'user/dep', { src = '...', build = fn } }, -- sourced before config
--     config  = function() ... end,               -- runs once, after packadd
--     build   = function() ... end,               -- runs on install/update (PackChanged)
--   }

local M = {}

-- name -> spec, so PackChanged can find the spec that owns a build step
local registry = {}

local function name_of(spec)
  if spec.name then
    return spec.name
  end
  return (spec.src:gsub('%.git$', ''):match('([^/]+)$'))
end

-- Normalize a spec (or bare "user/repo" / url string) in place, recursively for deps.
local function normalize(spec)
  if type(spec) == 'string' then
    spec = { src = spec }
  end
  -- allow "user/repo" shorthand
  if not spec.src:match('://') then
    spec.src = 'https://github.com/' .. spec.src
  end
  spec.name = name_of(spec)
  spec.deps = spec.deps or {}
  for i, dep in ipairs(spec.deps) do
    spec.deps[i] = normalize(dep)
  end
  return spec
end

-- Source a plugin (and its deps) once, then run its config. Deps are resolved
-- through `registry` so a shared dependency (e.g. plenary, blink.cmp) maps to a
-- single canonical spec and is never sourced twice.
local function realize(spec)
  spec = registry[spec.name] or spec
  if spec._loaded then
    return
  end
  spec._loaded = true
  for _, dep in ipairs(spec.deps) do
    realize(dep)
  end
  local ok = pcall(vim.cmd.packadd, spec.name)
  if not ok then
    -- A trigger can fire before the deferred vim.pack.add has installed the
    -- plugin (e.g. `nvim new-plugin-trigger.md` on first run after adding a
    -- spec). Install it synchronously and retry.
    pcall(vim.pack.add, { { src = spec.src, name = spec.name, version = spec.version } }, { load = false, confirm = false })
    ok = pcall(vim.cmd.packadd, spec.name)
  end
  if not ok then
    -- Un-mark so another trigger (cmd/keys) can retry; report instead of
    -- failing silently — a consumed once-autocmd would otherwise leave the
    -- plugin unloadable for the rest of the session with no hint why.
    spec._loaded = false
    vim.notify(('[loader] %s: packadd failed — plugin missing from packpath and install failed'):format(spec.name), vim.log.levels.ERROR)
    return
  end
  if type(spec.config) == 'function' then
    local ok, err = pcall(spec.config)
    if not ok then
      vim.notify(('[loader] %s: config error\n%s'):format(spec.name, err), vim.log.levels.ERROR)
    end
  end
end

local function as_list(v)
  if v == nil then
    return {}
  end
  return type(v) == 'table' and v or { v }
end

-- Wire a single enabled spec to its trigger(s). No trigger => eager.
local function wire(spec)
  -- install_only: just keep it on 'runtimepath' (done by load=false), never
  -- source it. Used for e.g. alternate colorschemes that :colorscheme finds on
  -- rtp without needing their plugin/ files sourced.
  if spec.install_only then
    return
  end

  local lazy = spec.event or spec.ft or spec.cmd or spec.keys
  if not lazy then
    realize(spec)
    return
  end

  if spec.event then
    vim.api.nvim_create_autocmd(as_list(spec.event), {
      once = true,
      callback = function()
        realize(spec)
      end,
    })
  end

  if spec.ft then
    vim.api.nvim_create_autocmd('FileType', {
      pattern = as_list(spec.ft),
      once = true,
      callback = function(ev)
        realize(spec)
        -- Re-emit FileType so handlers the plugin just registered apply to
        -- the buffer that triggered the load. Deferred, NOT inline: re-running
        -- the chain nested inside the still-executing FileType chain makes the
        -- runtime ftplugin loader run its undo_ftplugin against stale state
        -- (E31), and that error aborts filetype detection for the buffer.
        -- The buffer-local flag dedupes re-emits when several specs trigger
        -- on the same FileType event.
        if vim.b[ev.buf]._loader_ft_refire then
          return
        end
        vim.b[ev.buf]._loader_ft_refire = true
        vim.schedule(function()
          if not vim.api.nvim_buf_is_valid(ev.buf) then
            return
          end
          vim.b[ev.buf]._loader_ft_refire = nil
          -- Skip if the filetype changed since scheduling (plugin UIs like
          -- diffview repurpose buffers between the event and this tick), and
          -- re-emit with the buffer as current: ftplugins read the CURRENT
          -- buffer's options, so firing from another window runs them
          -- against the wrong buffer (e.g. markdown.lua starting treesitter
          -- for a 'DiffviewFiles' panel).
          if vim.bo[ev.buf].filetype ~= ev.match then
            return
          end
          vim.api.nvim_buf_call(ev.buf, function()
            vim.api.nvim_exec_autocmds('FileType', { buffer = ev.buf, modeline = false })
          end)
        end)
      end,
    })
  end

  if spec.cmd then
    for _, cmd in ipairs(as_list(spec.cmd)) do
      vim.api.nvim_create_user_command(cmd, function(a)
        vim.api.nvim_del_user_command(cmd)
        realize(spec)
        local range = ''
        if a.range == 1 then
          range = tostring(a.line1)
        elseif a.range == 2 then
          range = a.line1 .. ',' .. a.line2
        end
        vim.cmd(('%s%s%s %s'):format(range, cmd, a.bang and '!' or '', a.args))
      end, { nargs = '*', bang = true, range = true })
    end
  end

  if spec.keys then
    for _, key in ipairs(spec.keys) do
      local lhs = type(key) == 'table' and key[1] or key
      local modes = as_list(type(key) == 'table' and (key.mode or 'n') or 'n')
      vim.keymap.set(modes, lhs, function()
        for _, m in ipairs(modes) do
          pcall(vim.keymap.del, m, lhs)
        end
        realize(spec)
        -- Replay the key so the mapping the plugin/config just set handles it.
        vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(lhs, true, false, true), 'm', false)
      end, { desc = 'lazy load: ' .. spec.name })
    end
  end
end

-- Entry point. `specs` is the ordered list returned by lua/plugins.lua.
function M.setup(specs)
  -- Run build steps on install/update. Registered before vim.pack.add so it
  -- also fires for first-time installs (incl. installs from the lockfile).
  vim.api.nvim_create_autocmd('PackChanged', {
    callback = function(ev)
      local sname = ev.data.spec and ev.data.spec.name
      local spec = sname and registry[sname]
      if spec and type(spec.build) == 'function' and (ev.data.kind == 'install' or ev.data.kind == 'update') then
        if not ev.data.active then
          pcall(vim.cmd.packadd, sname)
        end
        local ok, err = pcall(spec.build)
        if not ok then
          vim.notify(('[loader] %s: build error\n%s'):format(sname, err), vim.log.levels.ERROR)
        end
      end
    end,
  })

  local active = {}
  for _, spec in ipairs(specs) do
    if spec.enabled ~= false then
      active[#active + 1] = normalize(spec)
    end
  end

  -- Canonical registry: a top-level spec wins over a same-named dependency.
  for _, spec in ipairs(active) do
    registry[spec.name] = spec
  end

  local function is_eager(spec)
    return not (spec.event or spec.ft or spec.cmd or spec.keys or spec.install_only)
  end

  -- Flatten specs + their deps into install lists (deduped across both lists).
  local seen = {}
  local function collect(spec, list)
    spec = registry[spec.name] or spec
    registry[spec.name] = spec
    if not seen[spec.name] then
      seen[spec.name] = true
      list[#list + 1] = { src = spec.src, name = spec.name, version = spec.version }
    end
    for _, dep in ipairs(spec.deps) do
      collect(dep, list)
    end
  end

  -- Eager plugins (no trigger) are collected first so shared deps land in the
  -- eager list and get sourced at startup alongside their dependent.
  local eager_install, deferred_install = {}, {}
  for _, spec in ipairs(active) do
    if is_eager(spec) then
      collect(spec, eager_install)
    end
  end
  for _, spec in ipairs(active) do
    if not is_eager(spec) then
      collect(spec, deferred_install)
    end
  end

  -- Eager: install + add to 'runtimepath' now, then source via wire/realize.
  if #eager_install > 0 then
    pcall(vim.pack.add, eager_install, { load = false, confirm = false })
  end
  for _, spec in ipairs(active) do
    if is_eager(spec) then
      wire(spec)
    end
  end

  -- Lazy / install_only: register with vim.pack AFTER init.lua, so they miss
  -- Nvim's post-init "load rtp plugins" phase and their plugin/ files are NOT
  -- sourced at startup. They're put on 'runtimepath' (load = false), then
  -- sourced only when a trigger fires (realize -> :packadd). vim.schedule runs
  -- on the next loop tick — before any user-driven trigger can fire.
  for _, spec in ipairs(active) do
    if not is_eager(spec) then
      wire(spec)
    end
  end
  if #deferred_install > 0 then
    vim.schedule(function()
      pcall(vim.pack.add, deferred_install, { load = false, confirm = false })
    end)
  end
end

return M
