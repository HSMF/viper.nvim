local M = {}
local server = require("viper.server")
local config = require("viper.config")

-- client_id once started
M.client_id = nil

-- ViperProtocol command names (must match ViperServer's CommandProtocol.scala)
local Cmd = {
    -- server → client notifications
    StateChange            = "StateChange",
    Log                    = "Log",
    Hint                   = "Hint",
    VerificationNotStarted = "VerificationNotStarted",
    -- client → server notifications
    Verify                 = "Verify",
    -- requests (bidirectional)
    GetVersion             = "GetVersion",
    GetViperFileEndings    = "GetViperFileEndings",
    SetupProject           = "SetupProject",
    GetIdentifier          = "GetIdentifier",
    GetRange               = "GetRange",
}

M.Cmd = Cmd

-- Called by verify.lua to broadcast state changes
M.on_state_change = nil

local function handle_state_change(err, params)
    if err then return end
    if M.on_state_change then
        M.on_state_change(params)
    end
end

local function handle_hint(err, params)
    if err or not params then return end
    vim.notify("[viper] " .. (params.message or tostring(params)), vim.log.levels.INFO)
end

local function handle_log(err, params)
    if err or not params then return end
    -- Only surface errors/warnings; pure log noise stays silent
    if params.level and params.level >= 2 then
        vim.notify("[viper] " .. (params.msg or ""), vim.log.levels.WARN)
    end
end

local function handle_verification_not_started(err, params)
    if err then return end
    vim.notify("[viper] verification could not start" .. (params and params.uri and (" for " .. params.uri) or ""),
        vim.log.levels.WARN)
end

--- Build the handlers table for vim.lsp.start.
-- Exposed as M._make_handlers for unit tests.
local function make_handlers()
    return {
        [Cmd.StateChange]            = handle_state_change,
        [Cmd.Log]                    = handle_log,
        [Cmd.Hint]                   = handle_hint,
        [Cmd.VerificationNotStarted] = handle_verification_not_started,

        -- Server asks for the identifier at a position (for hover/goto).
        -- Returns vim.NIL (JSON null) when buffer unavailable — must not return
        -- plain nil or the RPC layer errors "neither result nor error sent".
        [Cmd.GetIdentifier]          = function(err, params, ctx)
            if err or not params then return vim.NIL end
            local bufnr = vim.uri_to_bufnr(ctx and ctx.uri or "")
            if not vim.api.nvim_buf_is_loaded(bufnr) then return vim.NIL end
            local line = vim.api.nvim_buf_get_lines(bufnr, params.line, params.line + 1, false)[1] or ""
            local col = params.character or 0
            local word = line:sub(1, col):match("[%w_]*$") .. line:sub(col + 1):match("^[%w_]*")
            return { identifier = word }
        end,

        -- Server asks for text in a range.
        [Cmd.GetRange]               = function(err, params, ctx)
            if err or not params then return vim.NIL end
            local bufnr = vim.uri_to_bufnr(ctx and ctx.uri or "")
            if not vim.api.nvim_buf_is_loaded(bufnr) then return vim.NIL end
            local lines = vim.api.nvim_buf_get_lines(
                bufnr,
                params.start.line,
                params["end"].line + 1,
                false
            )
            return { text = table.concat(lines, "\n") }
        end,

        -- Server asks which file endings are configured as Viper files.
        [Cmd.GetViperFileEndings]    = function()
            return { fileEndings = { ".vpr", ".sil" } }
        end,

        -- Server tells us which files are imported by a project root.
        -- Populate the project map so saves to imported files trigger root verification.
        [Cmd.SetupProject]           = function(err, params)
            if not err and params and params.projectUri then
                require("viper.project").setup(params.projectUri, params.otherUris or {})
            end
            return vim.NIL
        end,
    }
end

M._make_handlers = make_handlers

--- Perform GetVersion handshake; log incompatibility but don't abort.
local function version_handshake(client)
    client.request(Cmd.GetVersion, { clientVersion = "5.0.0" }, function(err, result)
        if err then
            vim.notify("[viper] GetVersion error: " .. vim.inspect(err), vim.log.levels.WARN)
            return
        end
        if result and result.error then
            vim.notify("[viper] viperserver version mismatch: " .. result.error, vim.log.levels.WARN)
        end
    end)
end

--- Attach LSP client to bufnr. Starts server if needed.
function M.attach(bufnr)
    -- If client already running, just attach to this buffer
    if M.client_id then
        local client = vim.lsp.get_client_by_id(M.client_id)
        if client then
            vim.lsp.buf_attach_client(bufnr, M.client_id)
            return
        end
        M.client_id = nil
    end

    server.ensure_started(function(port)
        if not port then
            vim.notify("[viper] viperserver failed to start", vim.log.levels.ERROR)
            return
        end

        local client_id = vim.lsp.start({
            name = "viperserver",
            cmd = vim.lsp.rpc.connect("127.0.0.1", port),
            filetypes = { "viper" },
            root_dir = vim.fs.root(bufnr, { ".git" }) or vim.fn.getcwd(),
            capabilities = vim.tbl_deep_extend(
                "force",
                vim.lsp.protocol.make_client_capabilities(),
                {
                    -- tell server we handle document highlights
                    textDocument = {
                        documentHighlight = { dynamicRegistration = false },
                    },
                }
            ),
            handlers = make_handlers(),
            on_attach = function(client, _bufnr)
                version_handshake(client)
            end,
        }, { bufnr = bufnr })

        M.client_id = client_id
    end)
end

--- Return active client, or nil.
function M.client()
    if not M.client_id then return nil end
    return vim.lsp.get_client_by_id(M.client_id)
end

return M
