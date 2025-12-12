return {
  'aaronik/treewalker.nvim',

  -- optional (see options below)
  -- The defaults:
  opts = {
    -- Whether to briefly highlight the node after jumping to it
    highlight = true,

    -- How long should above highlight last (in ms)
    highlight_duration = 250,

    -- The color of the above highlight. Must be a valid vim highlight group.
    -- (see :h highlight-group for options)
    highlight_group = 'CursorLine',

    -- Whether to create a visual selection after a movement to a node.
    -- If true, highlight is disabled and a visual selection is made in
    -- its place.
    select = false,

    -- Whether to use vim.notify to warn when there are missing parsers or incorrect options
    notifications = true,

    -- Whether the plugin adds movements to the jumplist -- true | false | 'left'
    --  true: All movements more than 1 line are added to the jumplist. This is the default,
    --        and is meant to cover most use cases. It's modeled on how { and } natively add
    --        to the jumplist.
    --  false: Treewalker does not add to the jumplist at all
    --  "left": Treewalker only adds :Treewalker Left to the jumplist. This seems the most
    --          likely jump to cause location confusion, so use this to minimize writes
    --          to the jumplist, while maintaining some ability to go back.
    jumplist = true,
  },

  config = function()
    vim.keymap.set({ 'n', 'v' }, '<C-k>', '<cmd>Treewalker Up<cr>', { silent = true })
    vim.keymap.set({ 'n', 'v' }, '<C-j>', '<cmd>Treewalker Down<cr>', { silent = true })
    vim.keymap.set({ 'n', 'v' }, '<leader>h', '<cmd>Treewalker Left<cr>', { silent = true })
    vim.keymap.set({ 'n', 'v' }, '<leader>l', '<cmd>Treewalker Right<cr>', { silent = true })
  end,
}
