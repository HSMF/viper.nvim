local M = {}
local lsp = require("viper.lsp")
local config = require("viper.config")

-- VerificationState values (mirror ViperProtocol.ts)
local State = {
    Stopped                  = 0,
    Starting                 = 1,
    VerificationRunning      = 2,
    VerificationPrintingHelp = 3,
    VerificationReporting    = 4,
    PostProcessing           = 5,
    Ready                    = 6,
    Stopping                 = 7,
    Stage                    = 8,
    ConstructingAst          = 9,
}

-- Success codes
local Success = {
    None               = 0,
    Success            = 1,
    ParsingFailed      = 2,
    TypecheckingFailed = 3,
    VerificationFailed = 4,
    Aborted            = 5,
    Error              = 6,
    Timeout            = 7,
}

local ns = vim.api.nvim_create_namespace("viper_verify")

local function uri_to_bufnr(uri)
    if not uri then return nil end
    local ok, bufnr = pcall(vim.uri_to_bufnr, uri)
    return ok and bufnr or nil
end

--- Clear diagnostics for bufnr (or all viper bufs).
local function clear_diagnostics(bufnr)
    if bufnr then
        vim.diagnostic.reset(ns, bufnr)
    end
end

local function state_label(s)
    for k, v in pairs(State) do
        if v == s then return k end
    end
    return tostring(s)
end

--- Handle StateChange notification from viperserver.
local function on_state_change(params)
    local bufnr = uri_to_bufnr(params.uri)
    local new_state = params.newState

    if new_state == State.VerificationRunning or new_state == State.Starting or new_state == State.ConstructingAst then
        if bufnr then clear_diagnostics(bufnr) end
        local pct = params.progress and math.floor(params.progress) or 0
        vim.notify(
            ("[viper] %s %s%s"):format(
                params.filename or "",
                state_label(new_state),
                pct > 0 and (" " .. pct .. "%") or ""
            ),
            vim.log.levels.INFO
        )
    elseif new_state == State.Ready then
        local success = params.success
        if success == Success.Success then
            vim.notify(
                ("[viper] %s verified ✓ (%.2fs)"):format(params.filename or "", (params.time or 0) / 1000),
                vim.log.levels.INFO
            )
        elseif success == Success.VerificationFailed then
            vim.notify(
                ("[viper] %s verification failed"):format(params.filename or ""),
                vim.log.levels.WARN
            )
        elseif success == Success.ParsingFailed then
            vim.notify(("[viper] %s parse error"):format(params.filename or ""), vim.log.levels.ERROR)
        elseif success == Success.TypecheckingFailed then
            vim.notify(("[viper] %s type error"):format(params.filename or ""), vim.log.levels.ERROR)
        elseif success == Success.Timeout then
            vim.notify(("[viper] %s timeout"):format(params.filename or ""), vim.log.levels.WARN)
        elseif success == Success.Aborted then
            vim.notify("[viper] verification aborted", vim.log.levels.INFO)
        elseif success == Success.Error then
            vim.notify(
                ("[viper] internal error: %s"):format(params.error or ""),
                vim.log.levels.ERROR
            )
        end
    elseif new_state == State.Stage then
        vim.notify(
            ("[viper] stage: %s"):format(params.stage or ""),
            vim.log.levels.INFO
        )
    end
end

M._on_state_change = on_state_change

--- Send Verify notification for the given buffer.
function M.verify(bufnr, manually_triggered)
    bufnr = bufnr or vim.api.nvim_get_current_buf()
    local client = lsp.client()
    if not client then
        vim.notify("[viper] LSP client not ready yet", vim.log.levels.WARN)
        return
    end

    local uri = vim.uri_from_bufnr(bufnr)
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local content = table.concat(lines, "\n")
    local opts = config.options

    client.notify(lsp.Cmd.Verify, {
        uri               = uri,
        content           = content,
        manuallyTriggered = manually_triggered ~= false,
        workspace         = vim.fs.root(bufnr, { ".git" }) or vim.fn.getcwd(),
        backend           = opts.backend,
        customArgs        = opts.custom_args,
    })
end

--- Set up autocmds and the :Verify command for a viper buffer.
function M.setup_buffer(bufnr)
    -- Wire state-change handler through lsp module
    lsp.on_state_change = on_state_change

    local augroup = vim.api.nvim_create_augroup("ViperVerify_" .. bufnr, { clear = true })

    if config.options.auto_verify then
        vim.api.nvim_create_autocmd("BufWritePost", {
            group    = augroup,
            buffer   = bufnr,
            callback = function()
                M.verify(bufnr, false)
            end,
        })
    end

    -- :Verify always available regardless of auto_verify setting
    vim.api.nvim_buf_create_user_command(bufnr, "Verify", function()
        M.verify(bufnr, true)
    end, { desc = "Verify current Viper file" })
end

return M
