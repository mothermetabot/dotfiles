return {
  opts = function()
    --Change windows shell to use bash
    vim.o.shell = 'bash'
    vim.o.shellcmdflag = '-s'

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
  end,

  keymaps = function()
    vim.keymap.set('n', '<Esc>', '<cmd>nohlsearch<CR>')
    vim.keymap.set('n', '<leader>q', vim.diagnostic.setloclist, { desc = 'Open diagnostic [Q]uickfix list' })
    vim.keymap.set('n', '<leader>.', '<cmd>lua vim.lsp.buf.code_action()<CR>', { desc = 'Code Actions' })
    vim.keymap.set('t', '<Esc>', '<C-\\><C-n>', { desc = 'Exit terminal mode' })

    vim.keymap.set('n', '<C-h>', '<C-w><C-h>', { desc = 'Move focus to the left window' })
    vim.keymap.set('n', '<C-l>', '<C-w><C-l>', { desc = 'Move focus to the right window' })
    vim.keymap.set('n', '<C-j>', '<C-w><C-j>', { desc = 'Move focus to the lower window' })
    vim.keymap.set('n', '<C-k>', '<C-w><C-k>', { desc = 'Move focus to the upper window' })

    vim.keymap.set('n', '<leader>y', '+y', {desc = 'Copy to system clipboard'})
    vim.keymap.set('v', '<leader>y', '+y', {desc = 'Copy to system clipboard'})
    vim.keymap.set('n', '<leader>p', '+p', {desc = 'Paste from system clipboard'})
    vim.keymap.set('v', '<leader>p', '+p', {desc = 'Paste from system clipboard'})

    local function open_last_term_or_new()
      -- Opens the last terminal buffer or creates a new one if it doesnt exist
      local buffers = vim.api.nvim_list_bufs()
      vim.print(buffers)

      for _, buf in ipairs(buffers) do
        if string.find(vim.api.nvim_buf_get_name(buf), 'term://') and vim.api.nvim_buf_is_valid(buf) then
          vim.cmd('buffer ' + buf)
        else
          vim.cmd 'term'
        end
      end
    end

    -- When scrolling with L and H recenter the screen automatically
    vim.keymap.set('n', 'L', 'Lzz')
    vim.keymap.set('n', 'H', 'Hzz')
    vim.keymap.set('n', '<C-D>', '<C-D>zz')
    vim.keymap.set('n', '<C-U>', '<C-U>zz')

    -- swap {} because it makes more sense on my keyboard
    vim.keymap.set('n', '{', '}')
    vim.keymap.set('n', '}', '{')
    vim.keymap.set('n', ')', '(')
    vim.keymap.set('n', '(', ')')
    vim.keymap.set('v', '{', '}')
    vim.keymap.set('v', '}', '{')
    vim.keymap.set('v', ')', '(')
    vim.keymap.set('v', '(', ')')

    vim.keymap.set('n', '<leader>t', open_last_term_or_new)
  end,
}
