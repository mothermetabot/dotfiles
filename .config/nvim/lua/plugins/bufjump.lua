return {
  'https://github.com/kwkarlwang/bufjump.nvim',
config = function()
        require("bufjump").setup({
            forward_key = "<leader>i",
            backward_key = "<leader>o",
            forward_same_buf_key = "<C-i>",
            backward_same_buf_key = "<C-o>",
            on_success = function()
                vim.cmd([[execute "normal! g`\"zz"]])
            end,
        })
    end,
}



