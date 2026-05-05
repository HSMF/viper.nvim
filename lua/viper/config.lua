local M = {}

M.defaults = {
  -- command to start viperserver (must be on $PATH)
  server_cmd = "viperserver",
  -- extra args passed to viperserver
  server_args = {},
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
