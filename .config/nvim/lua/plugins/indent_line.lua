return {
  { -- Add indentation guides even on blank lines
    'lukas-reineke/indent-blankline.nvim',
    -- Enable `lukas-reineke/indent-blankline.nvim`
    -- See `:help ibl`
    main = 'ibl',
    opts = {},
    config = function()
      local highlight = {
        'Crayola',
        'Wisteria',
        'Sunglow',
        'Vanilla',
        'CelestialBlue',
        'PantoneOrange',
        'NaplesYellow',
        'JordyBlue',
        'Cerise',
        'RaspberryRose',
      }

      local hooks = require 'ibl.hooks'
      -- create the highlight groups in the highlight setup hook, so they are reset
      -- every time the colorscheme changes
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
        indent = { char = '┊', highlight = highlight }, -- Set the character for indentation guides
        scope = { enabled = false }, -- Disable scope highlighting
        exclude = { filetypes = { 'help', 'dashboard', 'packer', 'NvimTree' } }, -- Exclude certain filetypes
      }
    end,
  },
}
