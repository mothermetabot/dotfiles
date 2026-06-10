return {
  'seblyng/roslyn.nvim',
  dependencies = {
    'saghen/blink.cmp',
  },
  ---@module 'roslyn.config'
  ---@type RoslynNvimConfig
  opts = {
    -- "auto" | "roslyn" | "off"
    --
    -- - "auto": Does nothing for filewatching, leaving everything as default
    -- - "roslyn": Turns off neovim filewatching which will make roslyn do the filewatching
    -- - "off": Hack to turn off all filewatching. (Can be used if you notice performance issues)
    filewatching = 'auto',

    -- Optional function that takes an array of targets as the only argument. Return the target you
    -- want to use. If it returns `nil`, then it falls back to guessing the target like normal
    -- Example:
    --
    -- choose_target = function(target)
    --     return vim.iter(target):find(function(item)
    --         if string.match(item, "Foo.sln") then
    --             return item
    --         end
    --     end)
    -- end
    choose_target = nil,

    -- Optional function that takes the selected target as the only argument.
    -- Returns a boolean of whether it should be ignored to attach to or not
    --
    -- I am for example using this to disable a solution with a lot of .NET Framework code on mac
    -- Example:
    --
    -- ignore_target = function(target)
    --     return string.match(target, "Foo.sln") ~= nil
    -- end
    ignore_target = nil,

    -- Whether or not to look for solution files in the child of the (root).
    -- Set this to true if you have some projects that are not a child of the
    -- directory with the solution file
    broad_search = false,

    -- Whether or not to lock the solution target after the first attach.
    -- This will always attach to the target in `vim.g.roslyn_nvim_selected_solution`.
    -- NOTE: You can use `:Roslyn target` to change the target
    lock_target = false,

    -- If the plugin should silence notifications about initialization
    silent = false,
  },
  config = function(_, opts)
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

    local function find_git_root(bufnr)
      return vim.fs.root(bufnr, '.git')
    end

    local function find_upward_target(bufnr)
      local bufname = vim.api.nvim_buf_get_name(bufnr)
      if bufname == '' then
        return nil
      end

      local git_root = find_git_root(bufnr)
      local dir = vim.fs.dirname(bufname)

      while dir do
        local solutions = sorted_files_in_dir(dir, '%.sln[xf]?$')
        if #solutions > 0 then
          return {
            kind = 'solution',
            path = solutions[1],
          }
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
          return {
            kind = 'project',
            path = projects[1],
          }
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

    require('roslyn').setup(opts)

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

          if vim.fn.has 'nvim-0.12' == 0 then
            vim.api.nvim_create_autocmd('LspAttach', {
              callback = function(args)
                if vim.api.nvim_get_option_value('filetype', { buf = args.buf }) == 'razor' and args.data.client_id == client.id then
                  client.server_capabilities.semanticTokensProvider.full = nil
                end
              end,
            })
          end

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
  end,
}
