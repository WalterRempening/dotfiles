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

local function organize_imports_sync(bufnr, timeout_ms)
  bufnr = bufnr or 0
  local params = vim.lsp.util.make_range_params(0, "utf-8")
  params.context = { only = { "source.organizeImports" }, diagnostics = {} }
  local results = vim.lsp.buf_request_sync(bufnr, "textDocument/codeAction", params, timeout_ms or 1500)
  for client_id, res in pairs(results or {}) do
    local client = vim.lsp.get_client_by_id(client_id)
    local offset_encoding = (client and client.offset_encoding) or "utf-8"
    for _, action in ipairs(res.result or {}) do
      if action.edit then
        vim.lsp.util.apply_workspace_edit(action.edit, offset_encoding)
      elseif type(action.command) == "table" then
        client:exec_cmd(action.command)
      end
    end
  end
end

autocmd("BufWritePre", {
  group = augroup("organize-imports-on-save", { clear = true }),
  pattern = { "*.kt", "*.kts", "*.java" },
  callback = function(event)
    organize_imports_sync(event.buf)
  end,
})

autocmd("ColorScheme", {
  group = augroup("custom-highlights", { clear = true }),
  callback = function()
    vim.api.nvim_set_hl(0, "MoreMsg", { fg = "#7dcfff", bold = true })
  end,
})
vim.api.nvim_set_hl(0, "MoreMsg", { fg = "#7dcfff", bold = true })
