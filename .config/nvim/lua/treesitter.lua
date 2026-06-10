-- nvim-treesitter, MAIN branch (the old `master` was archived/read-only in 2026
-- and doesn't work on Nvim 0.12). The main branch is a slim rewrite that
-- compiles parsers locally, so it needs `tree-sitter` CLI (0.26.1+) and a C
-- compiler. If either is missing we log a clear warning and skip installing
-- extra parsers -- the parsers bundled with Nvim still highlight fine.
--
-- The plugin explicitly does not support lazy-loading, so its spec is eager;
-- the only startup cost here is registering one FileType autocmd. Parser
-- installation is deferred to after startup.
--
-- Called from the nvim-treesitter spec's `config` in lua/plugins.lua.

local M = {}

-- Parsers to install. The 7 parsers bundled with Nvim 0.12 are intentionally
-- omitted (c, lua, markdown, markdown_inline, query, vim, vimdoc).
local EXTRA = {
  'bash',
  'html',
  'css',
  'json',
  'yaml',
  'toml',
  'diff',
  'rust',
  'python',
  'c_sharp',
  'typescript',
  'javascript',
  'tsx',
}

local function have(exe)
  return vim.fn.executable(exe) == 1
end

local function check_toolchain()
  local has_cli = have 'tree-sitter'
  local has_cc = have 'cc' or have 'gcc' or have 'clang' or have 'zig' or have 'cl'
  if has_cli and has_cc then
    return true
  end
  vim.notify(
    'nvim-treesitter (main) compiles parsers locally and needs:\n'
      .. '  • tree-sitter CLI 0.26.1+  '
      .. (has_cli and '(found)' or '(MISSING — `cargo install tree-sitter-cli` or `scoop install tree-sitter`)')
      .. '\n  • a C compiler  '
      .. (has_cc and '(found)' or '(MISSING — install zig / clang / mingw / MSVC)')
      .. '\nBundled parsers still highlight; extra parsers skipped until tools are present.',
    vim.log.levels.WARN
  )
  return false
end

function M.setup()
  -- Start highlighting (and treesitter indent) for any buffer with a parser.
  vim.api.nvim_create_autocmd('FileType', {
    group = vim.api.nvim_create_augroup('user-treesitter', { clear = true }),
    callback = function(ev)
      if pcall(vim.treesitter.start) then
        vim.bo[ev.buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
      end
    end,
  })
  -- The autocmd above won't fire for the buffer that triggered this load.
  pcall(vim.treesitter.start)

  -- Install missing extra parsers after startup (install() is async itself,
  -- but the toolchain check + get_installed read are deferred anyway).
  vim.schedule(function()
    if not check_toolchain() then
      return
    end
    local ok, nts = pcall(require, 'nvim-treesitter')
    if not ok then
      return
    end

    local installed = {}
    pcall(function()
      for _, lang in ipairs(nts.get_installed()) do
        installed[lang] = true
      end
    end)

    local todo = {}
    for _, lang in ipairs(EXTRA) do
      if not installed[lang] then
        todo[#todo + 1] = lang
      end
    end

    if #todo > 0 then
      pcall(function()
        nts.install(todo)
      end)
    end
  end)
end

return M
