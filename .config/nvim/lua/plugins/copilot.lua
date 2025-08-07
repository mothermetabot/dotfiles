return {
  'zbirenbaum/copilot.lua',
  event = 'VeryLazy',
  panel = {
    enabled = false,
  },
  suggestion = {
    enabled = false,
    auto_trigger = true,
    hide_during_completion = true,
    debounce = 75,
    trigger_on_accept = true,
    keymap = {
      accept = '<C-S-j>',
      accept_word = '<C-l>',
      accept_line = '<C-j>',
      dismiss = '<C-x>',
    },
  },
  filetypes = {
    yaml = false,
    markdown = false,
    help = false,
    gitcommit = false,
    gitrebase = false,
    hgcommit = false,
    svn = false,
    cvs = false,
    ['.'] = false,
  },
  workspace_folders = {},
  copilot_model = '',
  root_dir = function()
    return vim.fs.dirname(vim.fs.find('.git', { upward = true })[1])
  end,
  server = {
    type = 'nodejs', -- "nodejs" | "binary"
    custom_server_filepath = nil,
  },
}
