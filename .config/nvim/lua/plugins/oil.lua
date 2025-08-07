return {
  'stevearc/oil.nvim',
  ---@module 'oil'
  ---@type oil.SetupOpts
  opts = {
    columns = {
      'icon',
      'permissions',
      'size',
      'mtime',
    },
    view_options = {
      show_hidden = false,
      natural_order = 'fast',
      -- Sort file and directory names case insensitive
      case_insensitive = false,
    },
  },
  default_file_explorer = true,
  dependencies = { { 'echasnovski/mini.icons', opts = {} } },
  lazy = false,
}
