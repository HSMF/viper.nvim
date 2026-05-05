local M      = {}
local config = require("viper.config")
local server = require("viper.server")
local lsp    = require("viper.lsp")
local verify = require("viper.verify")

function M.setup(opts)
    config.setup(opts)

    local augroup = vim.api.nvim_create_augroup("ViperPlugin", { clear = true })

    vim.api.nvim_create_autocmd("FileType", {
        group    = augroup,
        pattern  = "viper",
        callback = function(ev)
            local bufnr = ev.buf
            lsp.attach(bufnr)
            verify.setup_buffer(bufnr)
        end,
    })

    vim.api.nvim_create_autocmd("VimLeavePre", {
        group    = augroup,
        callback = server.stop,
    })
end

return M
