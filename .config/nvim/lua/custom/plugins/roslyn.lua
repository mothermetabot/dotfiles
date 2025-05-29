return {
  'seblyng/roslyn.nvim',
  ft = 'cs',
  ---@module 'roslyn.config'
  ---@type RoslynNvimConfig
  opts = {
    filewatching = 'roslyn',
    config = {
      cmd = {
        'dotnet',
        'C:/Users/Sergio.Lopes/AppData/Local/nvim-data/csharp/Microsoft.CodeAnalysis.LanguageServer.dll',
        '--logLevel=Information',
        '--extensionLogDirectory=' .. vim.fs.dirname(vim.lsp.get_log_path()),
        '--stdio',
      },
    },
  },
}
