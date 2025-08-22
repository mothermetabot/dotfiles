local colors = { 'catppuccin-mocha', 'vague', 'terafox', 'aquarium' }

math.randomseed(vim.loop.hrtime())

local function load_random_color()
  local scheme = colors[math.random(#colors)]
  local ok, err = pcall(vim.cmd.colorscheme, scheme)
  if not ok then
    vim.notify("Failed to load colorscheme: " .. scheme .. (err and (" ("..err..")") or ""), vim.log.levels.WARN)
  else
    vim.notify("Colorscheme: ".. scheme)
  end
end

vim.api.nvim_create_autocmd('User', {
  pattern = 'VeryLazy',
  once = true,
  callback = load_random_color,
})
vim.api.nvim_create_user_command('RndColor', load_random_color, {})

return {
  { 'frenzyexists/aquarium-vim', priority = 1000, lazy = false },
  { 'vague2k/vague.nvim',        priority = 1000, lazy = false },
  { 'EdenEast/nightfox.nvim',    priority = 1000, lazy = false },
  { 'catppuccin/nvim', name = 'catppuccin', priority = 1000, lazy = false },
}

