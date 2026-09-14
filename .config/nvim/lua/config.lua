return {
  opts = function()
    -- Disable built-in runtime plugins / providers we don't use. Must run
    -- before Nvim's post-init load-plugins phase, so it lives here in opts().
    -- netrw is replaced by oil; the rest are archive/tutor/remote scaffolding.
    vim.g.loaded_netrw = 1
    vim.g.loaded_netrwPlugin = 1
    vim.g.loaded_tar = 1
    vim.g.loaded_tarPlugin = 1
    vim.g.loaded_zip = 1
    vim.g.loaded_zipPlugin = 1
    vim.g.loaded_gzip = 1
    vim.g.loaded_tutor_mode_plugin = 1
    vim.g.loaded_2html_plugin = 1
    vim.g.loaded_python3_provider = 0
    vim.g.loaded_ruby_provider = 0
    vim.g.loaded_perl_provider = 0
    vim.g.loaded_node_provider = 0

    -- NOTE: 'clipboard=unnamedplus' is intentionally NOT set on Windows: every
    -- yank/delete/change would spawn win32yank.exe (~50ms). Use <leader>y/p
    -- (see keymaps) to talk to the system clipboard explicitly.

    -- Use PowerShell as :! and :terminal shell on Windows. On Linux the
    -- default $SHELL is already correct, and forcing powershell.exe there
    -- breaks every shell-out. dap_config.lua and plugins.lua already branch
    -- on has('win32'); this block used to be the one place that did not.
    if vim.fn.has 'win32' == 1 then
      vim.o.shell = 'powershell.exe'
      vim.opt.shellcmdflag = '-NoLogo -NoProfile -ExecutionPolicy RemoteSigned -Command'
      vim.opt.shellquote = ''
      vim.opt.shellxquote = ''
    end

    vim.o.ttimeoutlen = 0
    vim.o.timeoutlen = 280

    vim.g.mapleader = ' '
    vim.g.maplocalleader = ' '

    vim.g.have_nerd_font = true

    vim.o.number = true
    vim.o.relativenumber = true
    vim.opt.signcolumn = 'yes'

    vim.opt.undofile = true

    vim.opt.ignorecase = true
    vim.opt.smartcase = true

    vim.opt.list = true
    vim.opt.listchars = { tab = '» ', trail = '·', nbsp = '␣' }

    vim.opt.inccommand = 'split'
    vim.opt.cursorline = true

    vim.opt.scrolloff = 5
    vim.o.expandtab = true
    vim.o.tabstop = 2
    vim.o.shiftwidth = 2
    vim.opt.confirm = true

    vim.o.winborder = 'rounded'
  end,

  autocmd = function()
    -- Highlight when yanking (copying) text
    vim.api.nvim_create_autocmd('TextYankPost', {
      desc = 'Highlight when yanking (copying) text',
      group = vim.api.nvim_create_augroup('highlight-yank', { clear = true }),
      callback = function()
        vim.highlight.on_yank()
      end,
    })

    -- This command remaps Ex, Vex and Sex to Oil
    vim.api.nvim_create_user_command('O', 'Oil', { nargs = 0 })
    vim.api.nvim_create_user_command('Vo', 'vsplit ', { nargs = 0 })
    vim.api.nvim_create_user_command('Ho', 'Oil', { nargs = 0 })
    local function normalize_dos()
      vim.cmd 'edit ++ff=dos'
      vim.cmd 'write'
    end

    -- This command changes the cwd to the current buffer or path (oil)
    vim.api.nvim_create_user_command("D", function()
      local dir

      if vim.bo.filetype == "oil" then
        dir = require("oil").get_current_dir()
      else
        local file = vim.api.nvim_buf_get_name(0)

        if file == "" then
          vim.notify("Current buffer has no file path", vim.log.levels.WARN)
          return
        end

        dir = vim.fs.dirname(file)
      end

      if not dir then
        vim.notify("Could not determine directory", vim.log.levels.ERROR)
        return
      end

      vim.api.nvim_set_current_dir(dir)
      vim.notify("Working directory: " .. dir)
    end, {
      desc = "Set working directory to Oil or buffer directory",
    })

    vim.api.nvim_create_user_command('Normalize', normalize_dos, {})
    vim.api.nvim_create_user_command('N', normalize_dos, {})

    -- Oil is lazy-loaded; open it when Neovim is started on a directory.
    vim.api.nvim_create_autocmd('VimEnter', {
      callback = function()
        local arg = vim.fn.argv(0)
        if type(arg) == 'string' and arg ~= '' and vim.fn.isdirectory(arg) == 1 then
          vim.cmd('Oil ' .. vim.fn.fnameescape(arg))
        end
      end,
    })
  end,
  keymaps = function()
    vim.keymap.set('n', '<Esc>', '<cmd>nohlsearch<CR>')
    vim.keymap.set('n', '<leader>q', vim.diagnostic.setloclist, { desc = 'Open diagnostic [Q]uickfix list' })
    vim.keymap.set('n', '<leader>.', '<cmd>lua vim.lsp.buf.code_action()<CR>', { desc = 'Code Actions' })
    vim.keymap.set('t', '<Esc><Esc>', [[<C-\><C-n>]], { noremap = true, silent = true })
    vim.keymap.set('i', '<Up>', '<Nop>')
    vim.keymap.set('i', '<Down>', '<Nop>')
    vim.keymap.set('i', '<Left>', '<Nop>')
    vim.keymap.set('i', '<Right>', '<Nop>')
    vim.keymap.set('n', '<C-h>', '<C-w><C-h>', { desc = 'Move focus to the left window' })
    vim.keymap.set('n', '<C-l>', '<C-w><C-l>', { desc = 'Move focus to the right window' })
    vim.keymap.set('n', '<C-j>', '<C-w><C-j>', { desc = 'Move focus to the lower window' })
    vim.keymap.set('n', '<C-k>', '<C-w><C-k>', { desc = 'Move focus to the upper window' })

    vim.keymap.set({ 'n', 'v' }, '<leader>y', '"+y', { desc = 'Copy to system clipboard' })
    vim.keymap.set({ 'n', 'v' }, '<leader>p', '"+p', { desc = 'Paste from system clipboard' })

    -- Copying keymaps
    vim.keymap.set('n', '<localleader>yp', function() 
      vim.fn.setreg('+', vim.fn.expand('%:p:.')) 
    end, { desc = 'Copy file path' })

    vim.keymap.set('n', '<localleader>yd', function() 
      vim.fn.setreg('+', vim.fn.expand('%:h')) 
    end, { desc = 'Copy directory path' })

    vim.keymap.set('n', '<localleader>yf', function() 
      vim.fn.setreg('+', vim.fn.expand('%:t:r')) 
    end, { desc = 'Copy file name' })

    -- opens lazygit in a new terminal split
    local function open_lazygit()
      vim.cmd 'terminal lazygit'
      vim.cmd 'startinsert'
    end

    local function open_lazygit_vsplit()
      vim.cmd 'vsplit'
      vim.cmd 'terminal lazygit'
      vim.cmd 'startinsert'
    end

    vim.keymap.set('n', '<leader>gg', open_lazygit, { desc = 'Open lazygit' })
    vim.keymap.set('n', '<leader>gs', open_lazygit_vsplit, { desc = 'Open lazygit in vsplit' })

    -- When scrolling with L and H recenter the screen automatically
    vim.keymap.set('n', 'L', 'Lzz')
    vim.keymap.set('n', 'H', 'Hzz')
    vim.keymap.set('n', '<C-D>', '<C-D>zz')
    vim.keymap.set('n', '<C-U>', '<C-U>zz')

    -- Close all buffers except current one
    local function close_all_other_buffers()
      vim.cmd 'wa|%bd|e#'
    end

    vim.api.nvim_create_user_command('BD', close_all_other_buffers, { desc = 'Closes all buffers except the current one' })
  end,
}
