-- roslyn.nvim (C# / Razor) setup. Ported from the old lua/plugins/roslyn.lua;
-- only the plugin-manager wrapper was removed. Called from the roslyn.nvim spec
-- in lua/plugins.lua.

local M = {}

local function sorted_files_in_dir(dir, pattern)
  local matches = {}
  if not dir or vim.fn.isdirectory(dir) == 0 then
    return matches
  end
  for name, file_type in vim.fs.dir(dir) do
    if file_type == 'file' and name:match(pattern) then
      matches[#matches + 1] = vim.fs.normalize(vim.fs.joinpath(dir, name))
    end
  end
  table.sort(matches)
  return matches
end

local function find_upward_target(bufnr)
  local bufname = vim.api.nvim_buf_get_name(bufnr)
  if bufname == '' then
    return nil
  end

  local git_root = vim.fs.root(bufnr, '.git')

  local dir = vim.fs.dirname(bufname)
  while dir do
    local solutions = sorted_files_in_dir(dir, '%.sln[xf]?$')
    if #solutions > 0 then
      return { kind = 'solution', path = solutions[1] }
    end
    if git_root and vim.fs.normalize(dir) == vim.fs.normalize(git_root) then
      break
    end
    local parent = vim.fs.dirname(dir)
    if not parent or parent == dir then
      break
    end
    dir = parent
  end

  dir = vim.fs.dirname(bufname)
  while dir do
    local projects = sorted_files_in_dir(dir, '%.csproj$')
    if #projects > 0 then
      return { kind = 'project', path = projects[1] }
    end
    if git_root and vim.fs.normalize(dir) == vim.fs.normalize(git_root) then
      break
    end
    local parent = vim.fs.dirname(dir)
    if not parent or parent == dir then
      break
    end
    dir = parent
  end

  return nil
end

function M.setup()
  require('roslyn').setup {
    filewatching = 'auto',
    choose_target = nil,
    ignore_target = nil,
    broad_search = false,
    lock_target = false,
    silent = false,
  }

  vim.lsp.config('roslyn', {
    capabilities = require('blink.cmp').get_lsp_capabilities(),
    root_dir = function(bufnr, on_dir)
      local target = find_upward_target(bufnr)
      if target then
        on_dir(vim.fs.dirname(target.path))
      else
        on_dir(nil)
      end
    end,
    on_init = {
      function(client)
        client.server_capabilities.renameProvider = true

        local target = find_upward_target(vim.api.nvim_get_current_buf())
        if not target then
          return
        end
        if target.kind == 'solution' then
          require('roslyn.lsp.on_init').sln(client, target.path)
          return
        end
        require('roslyn.lsp.on_init').project(client, { target.path })
      end,
    },
  })
end

return M
