return {
	opts = function ()

	--Change windows shell to use bash
	vim.o.shell = 'bash'
	vim.o.shellcmdflag = '-s'

	vim.g.mapleader = ' '
	vim.g.maplocalleader = ' '

	-- Set to true if you have a Nerd Font installed and selected in the terminal
	vim.g.have_nerd_font = true

	-- Make line numbers default
	vim.opt.number = true
	-- You can also add relative line numbers, to help with jumping.
	--  Experiment for yourself to see if you like it!
	vim.opt.relativenumber = true

	-- Enable mouse mode, can be useful for resizing splits for example!
	vim.opt.mouse = 'a'

	-- Don't show the mode, since it's already in the status line
	vim.opt.showmode = false

	-- Sync clipboard between OS and Neovim.
	vim.schedule(function()
		vim.opt.clipboard = 'unnamedplus'
	end)

	-- Enable break indent
	vim.opt.breakindent = true

	-- Save undo history
	vim.opt.undofile = true

	-- Case-insensitive searching UNLESS \C or one or more capital letters in the search term
	vim.opt.ignorecase = true
	vim.opt.smartcase = true
	-- Keep signcolumn on by default
	vim.opt.signcolumn = 'yes'

	-- Decrease update time
	vim.opt.updatetime = 250

	-- Decrease mapped sequence wait time
	vim.opt.timeoutlen = 300

	-- Configure how new splits should be opened
	vim.opt.splitright = true
	vim.opt.splitbelow = true

	-- Sets how neovim will display certain whitespace characters in the editor.
	--  See `:help 'list'`
	--  and `:help 'listchars'`
	vim.opt.list = true
	vim.opt.listchars = { tab = '» ', trail = '·', nbsp = '␣' }

	-- Preview substitutions live, as you type!
	vim.opt.inccommand = 'split'

	-- Show which line your cursor is on
	vim.opt.cursorline = true

	-- Minimal number of screen lines to keep above and below the cursor.
	vim.opt.scrolloff = 5

	-- if performing an operation that would fail due to unsaved changes in the buffer (like `:q`),
	-- instead raise a dialog asking if you wish to save the current file(s)
	-- See `:help 'confirm'`
	vim.opt.confirm = true
end,

	autocmd = function ()
	-- [[ Basic Autocommands ]]
	--  See `:help lua-guide-autocommands`

	-- Highlight when yanking (copying) text
	vim.api.nvim_create_autocmd('TextYankPost', {
		desc = 'Highlight when yanking (copying) text',
		group = vim.api.nvim_create_augroup('highlight-yank', { clear = true }),
		callback = function()
			vim.highlight.on_yank()
		end,
	})
	end,

	keymaps = function ()
	-- Clear highlights on search when pressing <Esc> in normal mode
	vim.keymap.set('n', '<Esc>', '<cmd>nohlsearch<CR>')

	-- Diagnostic keymaps
	vim.keymap.set('n', '<leader>q', vim.diagnostic.setloclist, { desc = 'Open diagnostic [Q]uickfix list' })

	-- Exit terminal mode in the builtin terminal with a shortcut that is a bit easier
	vim.keymap.set('t', '<Esc>', '<C-\\><C-n>', { desc = 'Exit terminal mode' })

	-- Keybinds to make split navigation easier.
	--  Use CTRL+<hjkl> to switch between windows
	--
	--  See `:help wincmd` for a list of all window commands
	vim.keymap.set('n', '<C-h>', '<C-w><C-h>', { desc = 'Move focus to the left window' })
	vim.keymap.set('n', '<C-l>', '<C-w><C-l>', { desc = 'Move focus to the right window' })
	vim.keymap.set('n', '<C-j>', '<C-w><C-j>', { desc = 'Move focus to the lower window' })
	vim.keymap.set('n', '<C-k>', '<C-w><C-k>', { desc = 'Move focus to the upper window' })

	-- Add keymap for code actions
	vim.keymap.set('n', '<leader>.', '<cmd>lua vim.lsp.buf.code_action()<CR>', { desc = 'Code Actions' })

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
	end
}

