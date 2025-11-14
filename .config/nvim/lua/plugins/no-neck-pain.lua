-- vim.api.nvim_create_autocmd('User', {
--   pattern = 'VeryLazy',
--   once = true,
--   callback = function ()
--    vim.cmd 'NoNeckPain'
--   end,
-- })

return {
  'shortcuts/no-neck-pain.nvim',
  config = {
    width = 145,
    autocmds = {
      enableOnVimEnter = true,
    },
    mappings = {
      -- When `true`, creates all the mappings that are not set to `false`.
      ---@type boolean
      enabled = true,
      -- Sets a global mapping to Neovim, which allows you to toggle the plugin.
      -- When `false`, the mapping is not created.
      ---@type string
      toggle = '<Leader>mm',
      -- Sets a global mapping to Neovim, which allows you to toggle the left side buffer.
      -- When `false`, the mapping is not created.
      ---@type string
      toggleLeftSide = '<Leader>mh',
      -- Sets a global mapping to Neovim, which allows you to toggle the right side buffer.
      -- When `false`, the mapping is not created.
      ---@type string
      toggleRightSide = '<Leader>ml',
      -- Sets a global mapping to Neovim, which allows you to increase the width (+5) of the main window.
      -- When `false`, the mapping is not created.
      ---@type string | { mapping: string, value: number }
      widthUp = '<Leader>mk',
      -- Sets a global mapping to Neovim, which allows you to decrease the width (-5) of the main window.
      -- When `false`, the mapping is not created.
      ---@type string | { mapping: string, value: number }
      widthDown = '<Leader>mj',
      -- Sets a global mapping to Neovim, which allows you to toggle the scratchPad feature.
      -- When `false`, the mapping is not created.
      ---@type string
      scratchPad = '<Leader>ms',
    },
  },
}
