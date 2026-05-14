local M       = {}
local lsp     = require("viper.lsp")
local config  = require("viper.config")
local project = require("viper.project")

local state   = {}

local function set_ready(filename, error, time)
    local old_state = state[filename or ""]
    local opts = { kind = "progress", status = error == nil and "success" or "failed", percent = 100, source = "viper" }
    if old_state ~= nil then
        opts.id = old_state.id
    end
    local msg = "[viper] " .. filename
    if error ~= nil then
        msg = msg .. " " .. error
    else
        msg = msg .. " verified"
    end
    if time ~= nil then
        msg = msg .. (" (%.2fs)"):format(time)
    end
    vim.api.nvim_echo({ { msg } }, false, opts)
    state[filename or ""] = {
        kind = "ready",
        success = error == nil,
        error = error,
    }
end
local function set_progress(filename, progress, new_state)
    local old_state = state[filename or ""]
    local opts = { kind = "progress", status = "running", percent = progress > 0 and progress or 0, source = "viper" }
    if old_state ~= nil then
        opts.id = old_state.id
    end
    local ok, id = pcall(vim.api.nvim_echo, { { filename } }, false, opts)
    if not ok then
        vim.print(opts)
        vim.print(filename)
        return
    end


    state[filename or ""] = {
        kind = "running",
        progress = progress,
        id = id
    }
end

function M.get_state(filename)
    return state[filename]
end

-- VerificationState values (mirror ViperProtocol.ts)
local State   = {
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

local ns      = vim.api.nvim_create_namespace("viper_verify")

local function uri_to_bufnr(uri)
    if not uri then return nil end
    local ok, bufnr = pcall(vim.uri_to_bufnr, uri)
    return ok and bufnr or nil
end

local function clear_diagnostics(bufnr)
    if bufnr then vim.diagnostic.reset(ns, bufnr) end
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

    if new_state == State.ConstructingAst then
        if bufnr then clear_diagnostics(bufnr) end
        -- vim.notify(
        --     ("[viper] %s %s"):format(
        --         params.filename or "",
        --         state_label(new_state)
        --     ),
        --     vim.log.levels.INFO
        -- )
    elseif new_state == State.VerificationRunning or new_state == State.Starting then
        if bufnr then clear_diagnostics(bufnr) end
        local pct = params.progress and math.floor(params.progress) or 0
        -- vim.notify(
        --     ("[viper] %s %s%s"):format(
        --         params.filename or "",
        --         state_label(new_state),
        --         pct > 0 and (" " .. pct .. "%") or ""
        --     ),
        --     vim.log.levels.INFO
        -- )
        set_progress(params.filename, pct, new_state)
    elseif new_state == State.Ready then
        local success = params.success
        if success == Success.Success then
            vim.notify(
                ("[viper] %s verified ✓ (%.2fs)"):format(params.filename or "", params.time or 0),
                vim.log.levels.INFO
            )
            set_ready(params.filename, nil, params.time)
        elseif success == Success.VerificationFailed then
            vim.notify(("[viper] %s verification failed"):format(params.filename or ""), vim.log.levels.ERROR)
            set_ready(params.filename, "verification failed")
        elseif success == Success.ParsingFailed then
            vim.notify(("[viper] %s parse error"):format(params.filename or ""), vim.log.levels.ERROR)
            set_ready(params.filename, "parse error")
        elseif success == Success.TypecheckingFailed then
            vim.notify(("[viper] %s type error"):format(params.filename or ""), vim.log.levels.ERROR)
            set_ready(params.filename, "type error")
        elseif success == Success.Timeout then
            vim.notify(("[viper] %s timeout"):format(params.filename or ""), vim.log.levels.WARN)
            set_ready(params.filename, "timeout")
        elseif success == Success.Aborted then
            vim.notify("[viper] verification aborted", vim.log.levels.INFO)
            set_ready(params.filename, "aborted")
        elseif success == Success.Error then
            vim.notify(("[viper] internal error: %s"):format(params.error or ""), vim.log.levels.ERROR)
            set_ready(params.filename, ("internal error: %s"):format(params.error or ""))
        end
    elseif new_state == State.Stage then
        vim.notify(("[viper] stage: %s"):format(params.stage or ""), vim.log.levels.INFO)
    end
end

M._on_state_change = on_state_change

--- Return the content for a URI: use buffer if loaded, otherwise read from disk.
local function content_for_uri(uri)
    local ok, bufnr = pcall(vim.uri_to_bufnr, uri)
    if ok and vim.api.nvim_buf_is_loaded(bufnr) then
        return table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")
    end
    local path = vim.uri_to_fname(uri)
    local ok2, lines = pcall(vim.fn.readfile, path)
    if ok2 then return table.concat(lines, "\n") end
    return nil
end

M._content_for_uri = content_for_uri

--- Return the workspace root for a URI.
local function workspace_for_uri(uri)
    local path = vim.uri_to_fname(uri)
    return vim.fs.root(path, { ".git" }) or vim.fn.fnamemodify(path, ":h")
end

--- Send Verify notification for a URI (file may or may not be open in a buffer).
function M.verify_uri(uri, manually_triggered)
    local client = lsp.client()
    if not client then
        vim.notify("[viper] LSP client not ready yet", vim.log.levels.WARN)
        return
    end

    local content = content_for_uri(uri)
    if not content then
        vim.notify("[viper] cannot read content for " .. uri, vim.log.levels.WARN)
        return
    end

    local opts = config.options
    -- notify's first parameter is too restrictive
    ---@diagnostic disable-next-line: param-type-mismatch
    client:notify(lsp.Cmd.Verify, {
        uri               = uri,
        content           = content,
        manuallyTriggered = manually_triggered ~= false,
        workspace         = workspace_for_uri(uri),
        backend           = opts.backend,
        customArgs        = opts.custom_args,
    })
end

--- Send Verify notification for the given buffer.
--- If the buffer's file is an imported dependency, verifies its project root instead.
function M.verify(bufnr, manually_triggered)
    bufnr = bufnr or vim.api.nvim_get_current_buf()
    local uri = vim.uri_from_bufnr(bufnr)
    local root_uri = project.root_for(uri)
    M.verify_uri(root_uri or uri, manually_triggered)
end

--- Set up autocmds and the :Verify command for a viper buffer.
function M.setup_buffer(bufnr)
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

    vim.api.nvim_buf_create_user_command(bufnr, "Verify", function()
        M.verify(bufnr, true)
    end, { desc = "Verify current Viper file" })
end

return M
