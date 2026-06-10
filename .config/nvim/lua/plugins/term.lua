local M = {}

-- Store named terminal buffers: name -> bufnr
local terminals = {}

local function buf_is_valid(bufnr)
  return bufnr and vim.api.nvim_buf_is_valid(bufnr) and vim.bo[bufnr].buftype == 'terminal'
end

local function open_terminal(name)
  vim.cmd('terminal')
  local bufnr = vim.api.nvim_get_current_buf()
  if name then
    vim.api.nvim_buf_set_name(bufnr, name)
    terminals[name] = bufnr
  end
  vim.cmd('startinsert')
  return bufnr
end

function M.scratchpad()
  local name = 'scratchpad'
  local bufnr = terminals[name]
  if buf_is_valid(bufnr) then
    vim.cmd('buffer ' .. bufnr)
    vim.cmd('startinsert')
  else
    open_terminal(name)
  end
end

function M.split(direction, count)
  count = math.max(1, math.min(count, 6))
  local cmd = direction == 'vertical' and 'vsplit' or 'split'

  -- First terminal in current window
  open_terminal(nil)

  -- Remaining terminals in new splits
  for _ = 2, count do
    vim.cmd(cmd)
    open_terminal(nil)
  end
end

function M.new(name)
  open_terminal(name)
end

function M.setup()
  vim.api.nvim_create_user_command('Term', function(opts)
    local args = opts.fargs
    local subcmd = args[1]

    if subcmd == 'scratchpad' then
      M.scratchpad()
    elseif subcmd == 'split' then
      local direction = args[2] or 'vertical'
      local count = tonumber(args[3]) or 1
      M.split(direction, count)
    elseif subcmd == 'new' then
      M.new(args[2])
    else
      vim.notify('Term: unknown subcommand "' .. (subcmd or '') .. '"', vim.log.levels.ERROR)
    end
  end, {
    nargs = '+',
    complete = function(_, cmdline)
      local args = vim.split(cmdline, '%s+')
      if #args == 2 then
        return { 'scratchpad', 'split', 'new' }
      elseif #args == 3 and args[2] == 'split' then
        return { 'vertical', 'horizontal' }
      end
      return {}
    end,
  })
end

-- Wire it up as a lazy.nvim plugin spec (local plugin, no repo)
return {
  dir = '.',
  name = 'term',
  config = function()
    M.setup()
  end,
  lazy = false,
}
