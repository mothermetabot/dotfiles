return {
  'mfussenegger/nvim-dap',
  dependencies = {
    'rcarriga/nvim-dap-ui',
    'nvim-neotest/nvim-nio',
    'williamboman/mason.nvim',
    'jay-babu/mason-nvim-dap.nvim',
    'leoluz/nvim-dap-go',
  },
  keys = {
    {
      '<leader>1',
      function()
        require('dap').continue()
      end,
      desc = 'Debug: Start/Continue',
    },
    {
      '<leader>0',
      function()
        require('dap').terminate()
      end,
      desc = 'Debug: Stop',
    },
    {
      '<leader>4',
      function()
        require('dap').step_into()
      end,
      desc = 'Debug: Step Into',
    },
    {
      '<leader>5',
      function()
        require('dap').step_over()
      end,
      desc = 'Debug: Step Over',
    },
    {
      '<leader>dou',
      function()
        require('dap').step_out()
      end,
      desc = 'Debug: Step Out',
    },
    {
      '<leader>9',
      function()
        require('dap').toggle_breakpoint()
      end,
      desc = 'Debug: Toggle Breakpoint',
    },
    {
      '<leader>8',
      function()
        require('dap').set_breakpoint(vim.fn.input 'Breakpoint condition: ')
      end,
      desc = 'Debug: Set Breakpoint',
    },
    {
      '<leader>dla',
      function()
        require('dapui').toggle()
      end,
      desc = 'Debug: See last session result.',
    },
  },
  config = function()
    local dap = require 'dap'
    local dapui = require 'dapui'
    local mason_registry = require 'mason-registry'
    local install_location = require 'mason-core.installer.InstallLocation'

    local is_windows = vim.loop.os_uname().sysname == 'Windows_NT'

    local function get_package(name)
      local ok, pkg = pcall(mason_registry.get_package, name)
      if not ok or not pkg:is_installed() then
        return nil
      end
      return pkg
    end

    local function get_package_install_path(name, pkg)
      if pkg and type(pkg.get_install_path) == 'function' then
        return pkg:get_install_path()
      end
      return install_location.global():package(name)
    end

    require('mason-nvim-dap').setup {
      automatic_installation = true,
      handlers = {},
      ensure_installed = {
        'codelldb',
        'python',
        'js',
        'coreclr',
      },
    }

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

    local function configure_rust_dap()
      local codelldb = get_package 'codelldb'
      if not codelldb then
        return
      end

      local extension_path = get_package_install_path('codelldb', codelldb) .. '/extension/'
      local codelldb_path = extension_path .. 'adapter/codelldb'
      local liblldb_path = extension_path .. 'lldb/lib/liblldb.so'

      if is_windows then
        codelldb_path = codelldb_path .. '.exe'
        liblldb_path = extension_path .. 'lldb/bin/liblldb.dll'
      elseif vim.loop.os_uname().sysname == 'Darwin' then
        liblldb_path = extension_path .. 'lldb/lib/liblldb.dylib'
      end

      local args = { '--port', '${port}' }
      if vim.loop.fs_stat(liblldb_path) then
        args = { '--liblldb', liblldb_path, '--port', '${port}' }
      end

      dap.adapters.codelldb = {
        type = 'server',
        port = '${port}',
        executable = {
          command = codelldb_path,
          args = args,
          detached = not is_windows,
        },
      }

      dap.configurations.rust = {
        {
          name = 'Launch Rust executable',
          type = 'codelldb',
          request = 'launch',
          program = function()
            local default_bin = vim.fn.getcwd() .. '/target/debug/'
            return vim.fn.input('Path to executable: ', default_bin, 'file')
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
    end

    local function configure_python_dap()
      local debugpy = get_package 'debugpy'
      local command = 'python'

      if debugpy then
        local debugpy_path = get_package_install_path('debugpy', debugpy)
        if is_windows then
          command = debugpy_path .. '/venv/Scripts/python.exe'
        else
          command = debugpy_path .. '/venv/bin/python'
        end
      end

      dap.adapters.python = {
        type = 'executable',
        command = command,
        args = { '-m', 'debugpy.adapter' },
      }

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
    end

    local function configure_typescript_dap()
      local js_debug = get_package 'js-debug-adapter'
      if not js_debug then
        return
      end

      local js_debug_server = get_package_install_path('js-debug-adapter', js_debug) .. '/js-debug/src/dapDebugServer.js'
      if not vim.loop.fs_stat(js_debug_server) then
        return
      end

      dap.adapters['pwa-node'] = {
        type = 'server',
        host = 'localhost',
        port = '${port}',
        executable = {
          command = 'node',
          args = { js_debug_server, '${port}' },
        },
      }

      local ts_js_configs = {
        {
          name = 'Launch current file (Node)',
          type = 'pwa-node',
          request = 'launch',
          program = '${file}',
          cwd = '${workspaceFolder}',
          sourceMaps = true,
          console = 'integratedTerminal',
        },
        {
          name = 'Launch via npm start',
          type = 'pwa-node',
          request = 'launch',
          cwd = '${workspaceFolder}',
          runtimeExecutable = 'npm',
          runtimeArgs = { 'run', 'start' },
          sourceMaps = true,
          console = 'integratedTerminal',
        },
        {
          name = 'Attach to process',
          type = 'pwa-node',
          request = 'attach',
          processId = require('dap.utils').pick_process,
          cwd = '${workspaceFolder}',
        },
      }

      dap.configurations.typescript = ts_js_configs
      dap.configurations.javascript = ts_js_configs
      dap.configurations.typescriptreact = ts_js_configs
      dap.configurations.javascriptreact = ts_js_configs
    end

    local function configure_csharp_dap()
      local netcoredbg = get_package 'netcoredbg'
      if not netcoredbg then
        return
      end

      local command = get_package_install_path('netcoredbg', netcoredbg) .. '/netcoredbg/netcoredbg'
      if is_windows then
        command = command .. '.exe'
      end

      dap.adapters.coreclr = {
        type = 'executable',
        command = command,
        args = { '--interpreter=vscode' },
      }

      local function pick_latest_file(paths)
        local latest_path = nil
        local latest_mtime = -1
        for _, path in ipairs(paths) do
          local stat = vim.loop.fs_stat(path)
          local mtime = stat and stat.mtime and stat.mtime.sec or -1
          if mtime > latest_mtime then
            latest_mtime = mtime
            latest_path = path
          end
        end
        return latest_path
      end

      local function infer_csharp_program()
        local cwd = vim.fn.getcwd()
        local csproj = vim.fs.find(function(name, _)
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

        local fallback_candidates = vim.fn.globpath(cwd, 'bin/Debug/**/*.dll', false, true)
        local fallback = pick_latest_file(fallback_candidates)
        if fallback then
          return fallback
        end

        local default_path = cwd .. '/bin/Debug/'
        return vim.fn.input('Path to dll or exe: ', default_path, 'file')
      end

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
    end

    local function configure_all_dap()
      configure_rust_dap()
      configure_python_dap()
      configure_typescript_dap()
      configure_csharp_dap()
    end

    configure_all_dap()

    if mason_registry.on then
      mason_registry:on('package:install:success', function(pkg)
        if pkg.name == 'codelldb' or pkg.name == 'debugpy' or pkg.name == 'js-debug-adapter' or pkg.name == 'netcoredbg' then
          configure_all_dap()
        end
      end)
    end

    require('dap-go').setup {
      delve = {
        detached = vim.fn.has 'win32' == 0,
      },
    }
  end,
}
