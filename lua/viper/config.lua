local M = {}

M.defaults = {
    -- command to start viperserver (must be on $PATH)
    server_cmd = "viperserver",
    -- extra args passed to viperserver
    server_args = {},
    -- JVM flags injected via JAVA_TOOL_OPTIONS before the server jar runs.
    -- The viperserver wrapper typically does not set -Xss/-Xmx; without a
    -- large stack (-Xss128m) Viper's recursive verifier hits StackOverflowError
    -- on any non-trivial file.
    jvm_args = "-Xss128m -Xmx2048m",
    -- log level: OFF ERROR INFO DEBUG TRACE ALL
    log_level = "INFO",
    -- backend: "silicon" or "carbon"
    backend = "silicon",
    -- auto-verify on save
    auto_verify = true,
    -- custom args forwarded to the verifier
    custom_args = "",
}

M.options = {}

function M.setup(opts)
    M.options = vim.tbl_deep_extend("force", M.defaults, opts or {})
end

return M
