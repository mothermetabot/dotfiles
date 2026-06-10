-- nvim-dap setup without Mason. Debug adapters are discovered on $PATH (or via
-- an env var for js-debug); anything missing is reported once with an install
-- hint instead of being auto-installed.
--
-- Named dap_config (not "debug" / "dap") to avoid shadowing Lua's stdlib
-- `debug` module and the nvim-dap `dap` module in require().
--
-- Called from the nvim-dap spec's `config` in lua/plugins.lua.

local M = {}

local is_windows = vim.fn.has 'win32' == 1

local function exe(name)
  local p = vim.fn.exepath(name)
  return p ~= '' and p or nil
end

local function pick_latest_file(paths)
  local latest_path, latest_mtime = nil, -1
  for _, path in ipairs(paths) do
    local stat = vim.uv.fs_stat(path)
    local mtime = stat and stat.mtime and stat.mtime.sec or -1
    if mtime > latest_mtime then
      latest_mtime, latest_path = mtime, path
    end
  end
  return latest_path
end

local function infer_csharp_program()
  local cwd = vim.fn.getcwd()
  local csproj = vim.fs.find(function(name)
    return name:match '%.csproj$' ~= nil
  end, { path = cwd, upward = true, limit = 1 })[1]

  if csproj then
    local project_dir = vim.fs.dirname(csproj)
    local project_name = vim.fs.basename(csproj):gsub('%.csproj$', '')
    local candidates = vim.fn.globpath(project_dir, ('bin/Debug/**/%s.dll'):format(project_name), false, true)
    local best = pick_latest_file(candidates)
    if best then
      return best
    end
  end

  local fallback = pick_latest_file(vim.fn.globpath(cwd, 'bin/Debug/**/*.dll', false, true))
  if fallback then
    return fallback
  end
  return vim.fn.input('Path to dll or exe: ', cwd .. '/bin/Debug/', 'file')
end

-- Look for vscode-js-debug's dapDebugServer.js: $JS_DEBUG_PATH (dir or file).
local function find_js_debug()
  local env = vim.env.JS_DEBUG_PATH
  if env and env ~= '' then
    if env:match '%.js$' and vim.uv.fs_stat(env) then
      return env
    end
    local guess = vim.fs.joinpath(env, 'js-debug', 'src', 'dapDebugServer.js')
    if vim.uv.fs_stat(guess) then
      return guess
    end
  end
  return nil
end

local function setup_keymaps(dap, dapui)
  local map = function(lhs, fn, desc)
    vim.keymap.set('n', lhs, fn, { desc = 'Debug: ' .. desc })
  end
  map('<leader>1', dap.continue, 'Start/Continue')
  map('<leader>0', dap.terminate, 'Stop')
  map('<leader>4', dap.step_into, 'Step Into')
  map('<leader>5', dap.step_over, 'Step Over')
  map('<leader>dou', dap.step_out, 'Step Out')
  map('<leader>9', dap.toggle_breakpoint, 'Toggle Breakpoint')
  map('<leader>8', function()
    dap.set_breakpoint(vim.fn.input 'Breakpoint condition: ')
  end, 'Set Conditional Breakpoint')
  map('<leader>dla', dapui.toggle, 'Toggle DAP UI')
end

function M.setup()
  local dap = require 'dap'
  local dapui = require 'dapui'

  dapui.setup {
    icons = { expanded = 'v', collapsed = '>', current_frame = '*' },
    controls = {
      icons = {
        pause = '||',
        play = '>',
        step_into = '->',
        step_over = '=>',
        step_out = '<-',
        step_back = 'b',
        run_last = '>>',
        terminate = '[]',
        disconnect = 'o',
      },
    },
  }

  dap.listeners.after.event_initialized['dapui_config'] = dapui.open
  dap.listeners.before.event_terminated['dapui_config'] = dapui.close
  dap.listeners.before.event_exited['dapui_config'] = dapui.close

  setup_keymaps(dap, dapui)

  local missing = {}

  -- Rust via codelldb
  local codelldb = exe 'codelldb'
  if codelldb then
    dap.adapters.codelldb = {
      type = 'server',
      port = '${port}',
      executable = { command = codelldb, args = { '--port', '${port}' }, detached = not is_windows },
    }
    dap.configurations.rust = {
      {
        name = 'Launch Rust executable',
        type = 'codelldb',
        request = 'launch',
        program = function()
          return vim.fn.input('Path to executable: ', vim.fn.getcwd() .. '/target/debug/', 'file')
        end,
        cwd = '${workspaceFolder}',
        stopOnEntry = false,
      },
      {
        name = 'Attach to process',
        type = 'codelldb',
        request = 'attach',
        pid = require('dap.utils').pick_process,
        cwd = '${workspaceFolder}',
      },
    }
  else
    missing[#missing + 1] = 'codelldb (rust)  →  install CodeLLDB and add it to PATH'
  end

  -- Python via debugpy (run from the python on PATH)
  local python = exe 'python' or exe 'python3'
  if python then
    dap.adapters.python = { type = 'executable', command = python, args = { '-m', 'debugpy.adapter' } }
    dap.configurations.python = {
      {
        name = 'Launch file',
        type = 'python',
        request = 'launch',
        program = '${file}',
        cwd = '${workspaceFolder}',
        justMyCode = true,
      },
    }
  else
    missing[#missing + 1] = 'python/debugpy  →  install python, then `pip install debugpy`'
  end

  -- JS/TS via vscode-js-debug
  local js_server = find_js_debug()
  if js_server then
    dap.adapters['pwa-node'] = {
      type = 'server',
      host = 'localhost',
      port = '${port}',
      executable = { command = 'node', args = { js_server, '${port}' } },
    }
    local cfgs = {
      { name = 'Launch current file (Node)', type = 'pwa-node', request = 'launch', program = '${file}', cwd = '${workspaceFolder}', sourceMaps = true, console = 'integratedTerminal' },
      { name = 'Launch via npm start', type = 'pwa-node', request = 'launch', cwd = '${workspaceFolder}', runtimeExecutable = 'npm', runtimeArgs = { 'run', 'start' }, sourceMaps = true, console = 'integratedTerminal' },
      { name = 'Attach to process', type = 'pwa-node', request = 'attach', processId = require('dap.utils').pick_process, cwd = '${workspaceFolder}' },
    }
    for _, ft in ipairs { 'typescript', 'javascript', 'typescriptreact', 'javascriptreact' } do
      dap.configurations[ft] = cfgs
    end
  else
    missing[#missing + 1] = 'js-debug  →  get microsoft/vscode-js-debug and set $JS_DEBUG_PATH to its folder'
  end

  -- C# via netcoredbg
  local netcoredbg = exe 'netcoredbg'
  if netcoredbg then
    dap.adapters.coreclr = { type = 'executable', command = netcoredbg, args = { '--interpreter=vscode' } }
    dap.configurations.cs = {
      {
        type = 'coreclr',
        name = 'Launch .NET executable',
        request = 'launch',
        program = infer_csharp_program,
        cwd = '${workspaceFolder}',
        stopAtEntry = false,
      },
    }
  else
    missing[#missing + 1] = 'netcoredbg (c#)  →  install netcoredbg and add it to PATH'
  end

  -- Go via delve (dap-go wires the adapter; delve must be on PATH)
  pcall(function()
    require('dap-go').setup { delve = { detached = not is_windows } }
  end)
  if not exe 'dlv' then
    missing[#missing + 1] = 'delve/dlv (go)  →  `go install github.com/go-delve/delve/cmd/dlv@latest`'
  end

  if #missing > 0 then
    vim.notify('Debug adapters not found (install to enable):\n  • ' .. table.concat(missing, '\n  • '), vim.log.levels.WARN)
  end
end

return M
