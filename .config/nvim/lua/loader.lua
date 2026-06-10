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
  pcall(vim.cmd.packadd, spec.name)
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
      callback = function()
        realize(spec)
        -- Re-emit FileType so handlers the plugin just registered apply to
        -- the buffer that triggered the load.
        vim.api.nvim_exec_autocmds('FileType', { buffer = 0, modeline = false })
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

  -- Flatten active specs + their deps into a single install list (deduped).
  local install, seen = {}, {}
  local function collect(spec)
    spec = registry[spec.name] or spec
    registry[spec.name] = spec
    if not seen[spec.name] then
      seen[spec.name] = true
      install[#install + 1] = { src = spec.src, name = spec.name, version = spec.version }
    end
    for _, dep in ipairs(spec.deps) do
      collect(dep)
    end
  end
  for _, spec in ipairs(active) do
    collect(spec)
  end

  -- Install anything missing (no-op + offline when already on disk), source
  -- nothing (load = false), and don't prompt on first bootstrap (confirm = false).
  pcall(vim.pack.add, install, { load = false, confirm = false })

  for _, spec in ipairs(active) do
    wire(spec)
  end
end

return M
