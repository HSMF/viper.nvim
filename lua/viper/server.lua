local M = {}
local config = require("viper.config")

local state = {
    ---@type vim.SystemObj|nil
    proc = nil,
    ---@type number|nil
    port = nil,
    ---@type table<function<number,number>>
    callbacks = {},
}

-- Exposed for testing only.
M._state = state

--- Extract viperserver port from a stdout chunk, or nil if not present yet.
function M._parse_port(data)
    local s = data:match("<ViperServerPort:(%d+)>")
    return s and tonumber(s) or nil
end

local function flush_callbacks()
    for _, cb in ipairs(state.callbacks) do
        cb(state.port)
    end
    state.callbacks = {}
end

--- Start viperserver if not already running, then call cb(port).
function M.ensure_started(cb)
    if state.port then
        cb(state.port)
        return
    end

    if state.proc then
        -- already starting, queue callback
        table.insert(state.callbacks, cb)
        return
    end

    table.insert(state.callbacks, cb)

    local opts = config.options
    local cmd = vim.list_extend(
        { opts.server_cmd, "--serverMode", "LSP", "--singleClient", "--logLevel", opts.log_level },
        opts.server_args
    )

    local extra_env = {}
    if opts.jvm_args and opts.jvm_args ~= "" then
        extra_env.JAVA_TOOL_OPTIONS = opts.jvm_args
    end

    local stdout_buf = ""

    state.proc = vim.system(cmd, {
        env = extra_env,
        stdout = function(err, data)
            if err or not data then return end
            stdout_buf = stdout_buf .. data
            local p = M._parse_port(stdout_buf)
            if p and not state.port then
                state.port = p
                vim.schedule(flush_callbacks)
            end
        end,
        stderr = function(err, data)
            if not data or #data == 0 then return end
            -- Suppress the JVM startup banner printed when JAVA_TOOL_OPTIONS is set.
            if data:match("^Picked up JAVA_TOOL_OPTIONS") then return end
            vim.schedule(function()
                vim.notify("[viper] server: " .. data, vim.log.levels.WARN)
            end)
        end,
    }, function(result)
        -- process exited
        state.proc = nil
        state.port = nil
        vim.schedule(function()
            if result.code ~= 0 then
                vim.notify(
                    ("[viper] viperserver exited with code %d"):format(result.code),
                    vim.log.levels.ERROR
                )
            end
        end)
    end)
end

--- Stop viperserver
function M.stop()
    if state.proc then
        state.proc:kill(15) -- SIGTERM
        state.proc = nil
        state.port = nil
    end
end

function M.port()
    return state.port
end

return M
