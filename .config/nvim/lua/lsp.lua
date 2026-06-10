-- Native LSP, no Mason.
--
-- Neovim 0.12 ships `vim.lsp.config` / `vim.lsp.enable`, and nvim-lspconfig (on
-- 'runtimepath') provides the per-server defaults under its `lsp/` directory.
-- We only add our overrides and ENABLE servers whose executable is actually on
-- PATH. Anything missing is reported once via `vim.notify` with an install hint
-- so it can be installed by hand -- nothing is auto-installed.
--
-- Called from the nvim-lspconfig spec's `config` in lua/plugins.lua.

local M = {}

-- Per-server overrides merged on top of nvim-lspconfig defaults. roslyn is
-- handled by roslyn.nvim, not here.
local servers = {
  lua_ls = {},
  rust_analyzer = {},
  ts_ls = {},
  pyright = {
    settings = {
      python = {
        venvPath = '.',
        venv = '.venv',
      },
    },
    root_dir = function(bufnr, on_dir)
      on_dir(vim.fs.root(bufnr, { 'pyproject.toml', 'pyrightconfig.json', '.git' }))
    end,
    -- Point pyright at the project's .venv interpreter (Windows layout).
    before_init = function(_, config)
      if config.root_dir then
        config.settings = config.settings or {}
        config.settings.python = config.settings.python or {}
        config.settings.python.pythonPath = config.root_dir .. '\\.venv\\Scripts\\python.exe'
      end
    end,
  },
}

-- Shown when a server's executable isn't found.
local install_hints = {
  lua_ls = 'scoop install lua-language-server',
  rust_analyzer = 'rustup component add rust-analyzer',
  pyright = 'npm i -g pyright',
  ts_ls = 'npm i -g typescript typescript-language-server',
}

local function setup_keymaps()
  vim.api.nvim_create_autocmd('LspAttach', {
    group = vim.api.nvim_create_augroup('user-lsp-attach', { clear = true }),
    callback = function(event)
      local map = function(keys, func, desc, mode)
        vim.keymap.set(mode or 'n', keys, func, { buffer = event.buf, desc = 'LSP: ' .. desc })
      end
      -- telescope.builtin is on 'runtimepath' (packadd!) so require works even
      -- before telescope is fully loaded; the picker loads it on first use.
      local tb = function(fn)
        return function()
          require('telescope.builtin')[fn]()
        end
      end

      map('grn', vim.lsp.buf.rename, '[R]e[n]ame')
      map('gra', vim.lsp.buf.code_action, '[G]oto Code [A]ction', { 'n', 'x' })
      map('grr', tb 'lsp_references', '[G]oto [R]eferences')
      map('gri', tb 'lsp_implementations', '[G]oto [I]mplementation')
      map('grd', tb 'lsp_definitions', '[G]oto [D]efinition')
      map('grD', vim.lsp.buf.declaration, '[G]oto [D]eclaration')
      map('gO', tb 'lsp_document_symbols', 'Open Document Symbols')
      map('gW', tb 'lsp_dynamic_workspace_symbols', 'Open Workspace Symbols')
      map('grt', tb 'lsp_type_definitions', '[G]oto [T]ype Definition')

      local client = vim.lsp.get_client_by_id(event.data.client_id)
      if client and client:supports_method(vim.lsp.protocol.Methods.textDocument_documentHighlight, event.buf) then
        local hl = vim.api.nvim_create_augroup('user-lsp-highlight', { clear = false })
        vim.api.nvim_create_autocmd({ 'CursorHold', 'CursorHoldI' }, {
          buffer = event.buf,
          group = hl,
          callback = vim.lsp.buf.document_highlight,
        })
        vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI' }, {
          buffer = event.buf,
          group = hl,
          callback = vim.lsp.buf.clear_references,
        })
        vim.api.nvim_create_autocmd('LspDetach', {
          group = vim.api.nvim_create_augroup('user-lsp-detach', { clear = true }),
          callback = function(e2)
            vim.lsp.buf.clear_references()
            vim.api.nvim_clear_autocmds { group = 'user-lsp-highlight', buffer = e2.buf }
          end,
        })
      end

      if client and client:supports_method(vim.lsp.protocol.Methods.textDocument_inlayHint, event.buf) then
        map('<leader>th', function()
          vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled { bufnr = event.buf })
        end, '[T]oggle Inlay [H]ints')
      end
    end,
  })
end

local function setup_diagnostics()
  vim.diagnostic.config {
    severity_sort = true,
    float = { border = 'rounded', source = 'if_many' },
    underline = { severity = vim.diagnostic.severity.ERROR },
    signs = vim.g.have_nerd_font and {
      text = {
        [vim.diagnostic.severity.ERROR] = '󰅚 ',
        [vim.diagnostic.severity.WARN] = '󰀪 ',
        [vim.diagnostic.severity.INFO] = '󰋽 ',
        [vim.diagnostic.severity.HINT] = '󰌶 ',
      },
    } or {},
    virtual_text = {
      source = 'if_many',
      spacing = 2,
      format = function(diagnostic)
        return diagnostic.message
      end,
    },
  }
end

function M.setup()
  setup_keymaps()
  setup_diagnostics()

  local capabilities = {}
  local ok, blink = pcall(require, 'blink.cmp')
  if ok then
    capabilities = blink.get_lsp_capabilities()
  end

  local missing = {}
  for name, opts in pairs(servers) do
    opts.capabilities = vim.tbl_deep_extend('force', {}, capabilities, opts.capabilities or {})
    vim.lsp.config(name, opts)

    -- Resolve the server command from the merged config (nvim-lspconfig default
    -- + our override) and only enable it if the binary exists.
    local cfg = vim.lsp.config[name]
    local cmd = cfg and cfg.cmd
    local exe = type(cmd) == 'table' and cmd[1] or nil

    if exe and vim.fn.executable(exe) == 0 then
      missing[#missing + 1] = ('  • %s (%s)  →  %s'):format(name, exe, install_hints[name] or 'install manually')
    else
      vim.lsp.enable(name)
    end
  end

  if #missing > 0 then
    vim.notify('LSP servers not on PATH (install, then restart):\n' .. table.concat(missing, '\n'), vim.log.levels.WARN)
  end
end

return M
