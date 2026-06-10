return {
  opts = function()
    --Change windows shell to use bash
    vim.o.shell = 'powershell.exe'
    vim.opt.shellcmdflag = '-NoLogo -NoProfile -ExecutionPolicy RemoteSigned -Command'
    vim.opt.shellquote = ''
    vim.opt.shellxquote = ''

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

    vim.api.nvim_create_user_command('Normalize', normalize_dos, {})
    vim.api.nvim_create_user_command('N', normalize_dos, {})
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

    vim.keymap.set('n', '<leader>y', '+y', { desc = 'Copy to system clipboard' })
    vim.keymap.set('v', '<leader>y', '+y', { desc = 'Copy to system clipboard' })
    vim.keymap.set('n', '<leader>p', '+p', { desc = 'Paste from system clipboard' })
    vim.keymap.set('v', '<leader>p', '+p', { desc = 'Paste from system clipboard' })

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
