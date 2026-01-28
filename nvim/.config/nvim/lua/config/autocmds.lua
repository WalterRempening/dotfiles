local autocmd = vim.api.nvim_create_autocmd
local augroup = vim.api.nvim_create_augroup

autocmd("TextYankPost", {
  group = augroup("highlight-yank", { clear = true }),
  callback = function()
    vim.hl.on_yank()
  end,
})

autocmd("BufReadPost", {
  group = augroup("restore-cursor", { clear = true }),
  callback = function()
    local mark = vim.api.nvim_buf_get_mark(0, '"')
    local lcount = vim.api.nvim_buf_line_count(0)
    if mark[1] > 0 and mark[1] <= lcount then
      pcall(vim.api.nvim_win_set_cursor, 0, mark)
    end
  end,
})

autocmd("FileType", {
  group = augroup("close-with-q", { clear = true }),
  pattern = { "help", "lspinfo", "qf", "checkhealth", "man" },
  callback = function(event)
    vim.bo[event.buf].buflisted = false
    vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = event.buf, silent = true })
  end,
})

autocmd("BufWritePre", {
  group = augroup("auto-create-dir", { clear = true }),
  callback = function(event)
    if event.match:match("^%w%w+:[\\/][\\/]") then
      return
    end
    local file = vim.uv.fs_realpath(event.match) or event.match
    vim.fn.mkdir(vim.fn.fnamemodify(file, ":p:h"), "p")
  end,
})

autocmd({ "BufRead", "BufNewFile" }, {
  group = augroup("jte-filetype", { clear = true }),
  pattern = { "*.jte", "*.kte" },
  callback = function()
    vim.bo.filetype = "jte"
    vim.bo.syntax = "html"
    vim.bo.commentstring = "<%-- %s -->"
  end,
})

autocmd("ColorScheme", {
  group = augroup("custom-highlights", { clear = true }),
  callback = function()
    vim.api.nvim_set_hl(0, "MoreMsg", { fg = "#7dcfff", bold = true })
  end,
})
vim.api.nvim_set_hl(0, "MoreMsg", { fg = "#7dcfff", bold = true })
