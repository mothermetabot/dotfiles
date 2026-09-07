-- Single central plugin registry, consumed by lua/loader.lua.
--
-- Each row is one plugin. To DISABLE a plugin, set `enabled = false` — it won't
-- be installed, sourced, or wired. Nothing here loads at startup unless it has
-- NO trigger (event/ft/cmd/keys); those eager few are the colorscheme,
-- mini.nvim, and treesitter (which can't be lazy-loaded).
--
-- Trigger fields (see loader.lua for the full spec shape):
--   event = 'BufReadPre' | { ... }   ft = 'lua' | { ... }
--   cmd   = 'Oil' | { ... }          keys = { '<leader>x', { '<C-k>', mode = {'n','v'} } }

local READ = { 'BufReadPre', 'BufNewFile' }

-- Real code/text filetypes. Used to trigger plugins that should only run on
-- editable buffers, never on oil / special buffers (whose filetype isn't here).
local CODE_FT = {
  'lua', 'python', 'rust', 'c', 'cpp', 'cs', 'java', 'go', 'ruby', 'php',
  'javascript', 'javascriptreact', 'typescript', 'typescriptreact',
  'html', 'css', 'scss', 'json', 'jsonc', 'yaml', 'toml', 'xml', 'sql',
  'markdown', 'text', 'sh', 'bash', 'zsh', 'vim', 'dockerfile', 'make',
  'gitcommit', 'razor',
}

return {
  -----------------------------------------------------------------------------
  -- Colorscheme. Applied on VimEnter (just after first paint) rather than
  -- eagerly, to keep its highlight-group sourcing off the critical startup
  -- path. Trade-off is a brief flash of default colors on the very first frame.
  -----------------------------------------------------------------------------
  {
    src = 'rebelot/kanagawa.nvim',
    event = 'VimEnter',
    config = function()
      vim.cmd.colorscheme 'kanagawa'
    end,
  },

  -----------------------------------------------------------------------------
  -- Core editing (eager): mini.nvim modules. mini.pairs replaces nvim-autopairs
  -- and mini.icons replaces nvim-web-devicons.
  -----------------------------------------------------------------------------
  {
    src = 'echasnovski/mini.nvim',
    config = function()
      require('mini.ai').setup { n_lines = 500 }
      require('mini.surround').setup()
      require('mini.pairs').setup()

      require('mini.icons').setup()
      -- Let plugins that look for nvim-web-devicons use mini.icons instead.
      pcall(function()
        require('mini.icons').mock_nvim_web_devicons()
      end)

      local statusline = require 'mini.statusline'
      statusline.setup { use_icons = vim.g.have_nerd_font }
      ---@diagnostic disable-next-line: duplicate-set-field
      statusline.section_location = function()
        return '%2l:%-2v'
      end
    end,
  },
  -----------------------------------------------------------------------------
  -- Git diff viewer. No devicons dep: mini.icons (eager, above) already mocks
  -- nvim-web-devicons. `q` closes the whole view from any of its windows.
  -- Works from oil too: diffview only uses the buffer path as a repo
  -- indicator for buftype == "" buffers, so in oil it resolves from the cwd.
  -----------------------------------------------------------------------------
  {
    src = 'sindrets/diffview.nvim',
    cmd = {
      'DiffviewOpen',
      'DiffviewClose',
      'DiffviewToggleFiles',
      'DiffviewFileHistory',
    },
    keys = { '<leader>gd', '<leader>gD', '<leader>gh' },
    config = function()
      local close = { 'n', 'q', '<cmd>DiffviewClose<cr>', { desc = 'Close Diffview' } }
      local details = {
        'n',
        '<leader>rd',
        function()
          require('gg_pr').details()
        end,
        { desc = 'Review PR details' },
      }
      -- Visual: comment on the selection. Normal: on the cursor line in a
      -- diff pane, or on the whole file when in the file panel.
      local comment = {
        'x',
        '<leader>rc',
        function()
          require('gg_pr').comment()
        end,
        { desc = 'Review comment on selection' },
      }
      local comment_line = {
        'n',
        '<leader>rc',
        function()
          require('gg_pr').comment()
        end,
        { desc = 'Review comment on line/file' },
      }
      local page = {
        'n',
        '<leader>rp',
        function()
          require('gg_pr').page()
        end,
        { desc = 'Review PR conversation' },
      }
      local help = {
        'n',
        '<leader>rh',
        function()
          require('gg_pr').help()
        end,
        { desc = 'Review keys and commands' },
      }
      local thread = {
        'n',
        '<leader>rt',
        function()
          require('gg_pr').thread()
        end,
        { desc = 'Review comment thread under cursor' },
      }
      local vote = {
        'n',
        '<leader>rv',
        function()
          require('gg_pr').vote()
        end,
        { desc = 'Review vote on PR' },
      }
      local refresh = {
        'n',
        '<leader>rr',
        function()
          require('gg_pr').refresh()
        end,
        { desc = 'Review reload PR threads' },
      }
      require('diffview').setup {
        keymaps = {
          view = { close, details, comment, comment_line, thread, vote, refresh, page, help },
          file_panel = { close, details, comment_line, thread, vote, refresh, page, help },
          file_history_panel = { close },
        },
      }
      vim.keymap.set('n', '<leader>gd', '<cmd>DiffviewOpen<cr>', { desc = 'Git changes' })
      vim.keymap.set('n', '<leader>gD', '<cmd>DiffviewOpen --staged<cr>', { desc = 'Git staged changes' })
      vim.keymap.set('n', '<leader>gh', function()
        -- File history for real files; repo history from oil/special buffers.
        if vim.bo.buftype == '' and vim.api.nvim_buf_get_name(0) ~= '' then
          vim.cmd 'DiffviewFileHistory %'
        else
          vim.cmd 'DiffviewFileHistory'
        end
      end, { desc = 'Git file history' })
    end,
  },
  -----------------------------------------------------------------------------
  -- File explorer
  -----------------------------------------------------------------------------
  {
    src = 'stevearc/oil.nvim',
    cmd = 'Oil',
    config = function()
      require('oil').setup {
        columns = { 'icon', 'mtime' },
        view_options = {
          show_hidden = true,
          natural_order = 'fast',
          case_insensitive = false,
        },
      }
    end,
  },

  -----------------------------------------------------------------------------
  -- Fuzzy finder
  -----------------------------------------------------------------------------
  {
    src = 'nvim-telescope/telescope.nvim',
    keys = {
      '<leader>sk',
      '<leader>ss',
      '<leader>sw',
      '<leader>sp',
      '<leader>sd',
      '<leader>sb',
      '<leader>st',
      '<leader>saf',
      '<leader>sas',
      '<leader>sn',
      '<leader>/',
      '<leader>s/',
    },
    deps = {
      'nvim-lua/plenary.nvim',
      'nvim-telescope/telescope-ui-select.nvim',
      {
        src = 'nvim-telescope/telescope-fzf-native.nvim',
        build = function()
          if vim.fn.executable 'make' == 0 then
            vim.notify('telescope-fzf-native: `make` not found, skipping build (telescope uses its default sorter)', vim.log.levels.WARN)
            return
          end
          local dir = vim.fs.joinpath(vim.fn.stdpath 'data', 'site', 'pack', 'core', 'opt', 'telescope-fzf-native.nvim')
          vim.fn.system { 'make', '-C', dir }
        end,
      },
    },
    config = function()
      local telescope = require 'telescope'
      telescope.setup {
        extensions = {
          ['ui-select'] = { require('telescope.themes').get_dropdown() },
        },
        pickers = {
          find_files = { hidden = true },
        },
      }
      pcall(telescope.load_extension, 'fzf')
      pcall(telescope.load_extension, 'ui-select')

      local builtin = require 'telescope.builtin'
      vim.keymap.set('n', '<leader>sk', builtin.keymaps, { desc = '[S]earch [K]eymaps' })
      vim.keymap.set('n', '<leader>ss', builtin.find_files, { desc = '[S]earch [S]ources' })
      vim.keymap.set('n', '<leader>sw', builtin.grep_string, { desc = '[S]earch current [W]ord' })
      vim.keymap.set('n', '<leader>sp', builtin.live_grep, { desc = '[S]earch [P]attern using grep' })
      vim.keymap.set('n', '<leader>sd', builtin.diagnostics, { desc = '[S]earch [D]iagnostics' })
      vim.keymap.set('n', '<leader>sb', builtin.buffers, { desc = '[S]earch [B]uffers' })
      vim.keymap.set('n', '<leader>st', '<cmd>TodoTelescope<cr>', { desc = '[S]earch [T]odos' })

      vim.keymap.set('n', '<leader>saf', function()
        builtin.lsp_document_symbols { symbols = { 'function', 'method' } }
      end, { desc = '[ ] Find functions in buffer' })
      vim.keymap.set('n', '<leader>sas', function()
        builtin.lsp_document_symbols { symbols = { 'struct', 'interface' } }
      end, { desc = '[ ] Find structs in buffer' })

      vim.keymap.set('n', '<leader>/', function()
        builtin.current_buffer_fuzzy_find(require('telescope.themes').get_dropdown { winblend = 10, previewer = false })
      end, { desc = '[/] Fuzzily search in current buffer' })
      vim.keymap.set('n', '<leader>s/', function()
        builtin.live_grep { grep_open_files = true, prompt_title = 'Live Grep in Open Files' }
      end, { desc = '[S]earch [/] in Open Files' })
      vim.keymap.set('n', '<leader>sn', function()
        builtin.find_files { cwd = vim.fn.stdpath 'config' }
      end, { desc = '[S]earch [N]eovim files' })
    end,
  },

  -----------------------------------------------------------------------------
  -- Completion
  -----------------------------------------------------------------------------
  {
    src = 'saghen/blink.cmp',
    version = vim.version.range '1.*',
    event = 'InsertEnter',
    deps = {
      {
        src = 'L3MON4D3/LuaSnip',
        version = vim.version.range '2.*',
        build = function()
          if vim.fn.has 'win32' == 0 and vim.fn.executable 'make' == 1 then
            local dir = vim.fs.joinpath(vim.fn.stdpath 'data', 'site', 'pack', 'core', 'opt', 'LuaSnip')
            vim.fn.system { 'make', '-C', dir, 'install_jsregexp' }
          end
        end,
      },
      {
        src = 'folke/lazydev.nvim',
        config = function()
          require('lazydev').setup()
        end,
      },
    },
    config = function()
      require('blink.cmp').setup {
        keymap = { preset = 'default' },
        appearance = { nerd_font_variant = 'mono' },
        sources = {
          default = { 'lsp', 'path', 'snippets', 'lazydev' },
          providers = {
            lazydev = { module = 'lazydev.integrations.blink', score_offset = 100 },
          },
        },
        snippets = { preset = 'luasnip' },
        fuzzy = { implementation = 'lua' },
        signature = { enabled = true },
      }
    end,
  },

  -----------------------------------------------------------------------------
  -- LSP (native vim.lsp, no Mason) + formatting
  -----------------------------------------------------------------------------
  {
    -- No blink.cmp dep: lsp.lua pulls blink's capabilities via a plain
    -- require (packadd! keeps its lua/ on rtp), so the full completion stack
    -- (blink + LuaSnip + lazydev) stays deferred until InsertEnter.
    src = 'neovim/nvim-lspconfig',
    event = READ,
    config = function()
      require('lsp').setup()
    end,
  },
  {
    src = 'stevearc/conform.nvim',
    event = READ,
    keys = { '<leader>f' },
    config = function()
      require('conform').setup {
        formatters_by_ft = {
          lua = { 'stylua' },
          yaml = { 'prettier', lsp_format = 'fallback' },
          json = { 'prettier', lsp_format = 'fallback' },
          rust = { 'rustfmt', lsp_format = 'fallback' },
          python = { 'black' },
          ['*'] = { 'codespell' },
        },
        format_on_save = { lsp_format = 'fallback', timeout_ms = 500 },
        log_level = vim.log.levels.ERROR,
        notify_on_error = true,
        notify_no_formatters = true,
      }
      vim.keymap.set('n', '<leader>f', function()
        require('conform').format { async = true, lsp_format = 'fallback' }
      end, { desc = 'Format buffer' })
    end,
  },
  {
    src = 'seblyng/roslyn.nvim',
    ft = { 'cs', 'razor' },
    deps = { 'saghen/blink.cmp' },
    config = function()
      require('lsp_roslyn').setup()
    end,
  },

  -----------------------------------------------------------------------------
  -- Treesitter (main branch; eager — it doesn't support lazy-loading)
  -----------------------------------------------------------------------------
  {
    src = 'nvim-treesitter/nvim-treesitter',
    version = 'main',
    build = function()
      pcall(vim.cmd, 'TSUpdate')
    end,
    config = function()
      require('treesitter').setup()
    end,
  },

  -----------------------------------------------------------------------------
  -- Markdown preview (:MarkdownPreview) — loads on markdown buffers
  -----------------------------------------------------------------------------
  {
    src = 'iamcco/markdown-preview.nvim',
    ft = 'markdown',
    -- Downloads the prebuilt preview-server binary into app/bin. Doesn't use
    -- mkdp#util#install() (passes a bare "install.cmd ..." string to 'shell' =
    -- PowerShell, which can't resolve it) nor install.cmd itself (its
    -- Invoke-WebRequest dies in console-less processes yet still reports
    -- success, leaving app/bin empty).
    build = function()
      local root = vim.fs.joinpath(vim.fn.stdpath 'data', 'site', 'pack', 'core', 'opt', 'markdown-preview.nvim')
      local app = vim.fs.joinpath(root, 'app')
      -- Release tag lives in the ROOT package.json (0.0.10); app/package.json
      -- holds an unrelated stale version (0.0.1) with no matching release.
      local version = 'v' .. vim.json.decode(table.concat(vim.fn.readfile(vim.fs.joinpath(root, 'package.json')))).version
      if vim.fn.has 'win32' == 0 then
        local out = vim.system({ 'sh', vim.fs.joinpath(app, 'install.sh'), version }, { cwd = app }):wait()
        if out.code ~= 0 then
          vim.notify('markdown-preview: install.sh failed\n' .. (out.stderr or ''), vim.log.levels.ERROR)
        end
        return
      end
      local url = ('https://github.com/iamcco/markdown-preview.nvim/releases/download/%s/markdown-preview-win.zip'):format(version)
      local zip = vim.fs.joinpath(app, 'markdown-preview-win.zip')
      local bin = vim.fs.joinpath(app, 'bin')
      vim.fn.mkdir(bin, 'p')
      for _, cmd in ipairs {
        { 'curl.exe', '-fsSL', url, '-o', zip },
        { 'tar.exe', '-xf', zip, '-C', bin },
      } do
        local out = vim.system(cmd, { cwd = app }):wait()
        if out.code ~= 0 then
          vim.notify(('markdown-preview: install failed at `%s`\n%s'):format(cmd[1], out.stderr or ''), vim.log.levels.ERROR)
          return
        end
      end
      vim.fn.delete(zip)
      if vim.fn.executable(vim.fs.joinpath(bin, 'markdown-preview-win.exe')) ~= 1 then
        vim.notify('markdown-preview: server binary missing after install', vim.log.levels.ERROR)
      end
    end,
  },

  -----------------------------------------------------------------------------
  -- Git / editing UX
  -----------------------------------------------------------------------------
  {
    src = 'lewis6991/gitsigns.nvim',
    event = READ,
    config = function()
      require('gitsigns').setup {
        signs = {
          add = { text = '+' },
          change = { text = '~' },
          delete = { text = '_' },
          topdelete = { text = '‾' },
          changedelete = { text = '~' },
        },
      }
    end,
  },
  {
    src = 'folke/todo-comments.nvim',
    event = READ,
    deps = { 'nvim-lua/plenary.nvim' },
    config = function()
      require('todo-comments').setup { signs = true }
    end,
  },
  {
    src = 'lukas-reineke/indent-blankline.nvim',
    event = READ,
    config = function()
      local highlight = {
        'Crayola', 'Wisteria', 'Sunglow', 'JordyBlue','Vanilla', 'CelestialBlue',
        'PantoneOrange', 'NaplesYellow',  'Cerise', 'RaspberryRose',
      }
      local hooks = require 'ibl.hooks'
      hooks.register(hooks.type.HIGHLIGHT_SETUP, function()
        vim.api.nvim_set_hl(0, 'RaspberryRose', { fg = '#B8336A' })
        vim.api.nvim_set_hl(0, 'Sunglow', { fg = '#FFD166' })
        vim.api.nvim_set_hl(0, 'CelestialBlue', { fg = '#058ED9' })
        vim.api.nvim_set_hl(0, 'PantoneOrange', { fg = '#F75C03' })
        vim.api.nvim_set_hl(0, 'NaplesYellow', { fg = '#F9DB6D' })
        vim.api.nvim_set_hl(0, 'Vanilla', { fg = '#DBDFAC' })
        vim.api.nvim_set_hl(0, 'JordyBlue', { fg = '#9AC4F8' })
        vim.api.nvim_set_hl(0, 'Wisteria', { fg = '#BDADEA' })
        vim.api.nvim_set_hl(0, 'Cerise', { fg = '#F0386B' })
        vim.api.nvim_set_hl(0, 'Crayola', { fg = '#FF5376' })
      end)
      require('ibl').setup {
        indent = { char = '┊', highlight = highlight },
        scope = { enabled = false },
        exclude = { filetypes = { 'help', 'dashboard', 'packer', 'NvimTree' } },
      }
    end,
  },
  {
    src = 'jiaoshijie/undotree',
    keys = { '<leader>u' },
    cmd = 'Undotree',
    deps = { 'nvim-lua/plenary.nvim' },
    config = function()
      require('undotree').setup()
      vim.keymap.set('n', '<leader>u', function()
        require('undotree').toggle()
      end, { desc = 'Toggle undotree' })
    end,
  },
  {
    src = 'kwkarlwang/bufjump.nvim',
    keys = { '<leader>i', '<leader>o', '<C-i>', '<C-o>' },
    config = function()
      require('bufjump').setup {
        forward_key = '<leader>i',
        backward_key = '<leader>o',
        forward_same_buf_key = '<C-i>',
        backward_same_buf_key = '<C-o>',
        on_success = function()
          vim.cmd [[execute "normal! g`\"zz"]]
        end,
      }
    end,
  },

  -----------------------------------------------------------------------------
  -- Utilities
  -----------------------------------------------------------------------------
  {
    -- :StartupTime — averaged, interactive startup profiler. Lazy via cmd: the
    -- loader defers registration past Nvim's load-plugins phase, so this
    -- plugin/ file isn't sourced at startup. g:loaded_startuptime stays unset
    -- until the cmd-stub fires :packadd, which then defines the real command.
    src = 'dstein64/vim-startuptime',
    cmd = 'StartupTime',
  },

  -----------------------------------------------------------------------------
  -- Debugging (nvim-dap, no Mason)
  -----------------------------------------------------------------------------
  {
    src = 'mfussenegger/nvim-dap',
    keys = { '<leader>1', '<leader>0', '<leader>4', '<leader>5', '<leader>9', '<leader>8', '<leader>dou', '<leader>dla' },
    deps = {
      'rcarriga/nvim-dap-ui',
      'nvim-neotest/nvim-nio',
      'leoluz/nvim-dap-go',
    },
    config = function()
      require('dap_config').setup()
    end,
  },

  -----------------------------------------------------------------------------
  -- Disabled by default — flip enabled = true to use (loads lazily on trigger).
  -----------------------------------------------------------------------------
  -- Loads only on a code/text filetype (never oil / special buffers), then
  -- auto-centers. <leader>mm toggles it (also works before any file is opened).
  {
    src = 'shortcuts/no-neck-pain.nvim',
    enabled = true,
    ft = CODE_FT,
    keys = { '<leader>mm' },
    config = function()
      require('no-neck-pain').setup {
        width = 145,
        autocmds = { enableOnVimEnter = false },
        mappings = {
          enabled = true,
          toggle = '<Leader>mm',
          toggleLeftSide = '<Leader>mh',
          toggleRightSide = '<Leader>ml',
          widthUp = '<Leader>mk',
          widthDown = '<Leader>mj',
          scratchPad = '<Leader>ms',
        },
      }

      -- Auto-center on code/text buffers. The loader re-fires FileType for the
      -- buffer that triggered loading, so this also catches the first file.
      vim.api.nvim_create_autocmd('FileType', {
        pattern = CODE_FT,
        group = vim.api.nvim_create_augroup('user-nnp-autocenter', { clear = true }),
        callback = function()
          -- Deferred: enabling creates side windows and switches buffers,
          -- which must not happen inside the FileType autocmd chain — it
          -- corrupts the runtime ftplugin undo state (E31) and the resulting
          -- error aborts filetype detection for the triggering buffer.
          vim.schedule(function()
            local nnp = require 'no-neck-pain'
            if not (nnp.state and nnp.state.enabled) then
              nnp.enable()
            end
          end)
        end,
      })
    end,
  },
}
