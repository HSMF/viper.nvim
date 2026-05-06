-- Document highlight: highlight symbol under cursor via textDocument/documentHighlight
local bufnr = vim.api.nvim_get_current_buf()
local augroup = vim.api.nvim_create_augroup("ViperDocHighlight_" .. bufnr, { clear = true })

vim.api.nvim_create_autocmd("CursorHold", {
    group    = augroup,
    buffer   = bufnr,
    callback = function()
        local client = require("viper.lsp").client()
        if client and client:supports_method("textDocument/documentHighlight") then
            vim.lsp.buf.document_highlight()
        end
    end,
})

vim.api.nvim_create_autocmd({ "CursorMoved", "InsertEnter" }, {
    group    = augroup,
    buffer   = bufnr,
    callback = function()
        vim.lsp.buf.clear_references()
    end,
})
