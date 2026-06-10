-- Options, autocmds and keymaps.
local config = require 'config'
config.opts()
config.autocmd()
config.keymaps()

-- Plugins, managed by Neovim 0.12's built-in `vim.pack`.
-- The lazy-loading harness lives in lua/loader.lua; the plugin list (with a
-- per-plugin `enabled` flag) lives in lua/plugins.lua.
require('loader').setup(require 'plugins')

-- Local :Term command (not a plugin).
require('term').setup()

-- vim: ts=2 sts=2 sw=2 et
