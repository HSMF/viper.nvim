local M = {}
local config = require("viper.config")

local state = {
  proc = nil,    -- vim.SystemObj
  port = nil,    -- number, set once server announces it
  callbacks = {}, -- queued callbacks waiting for port
}

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

  local stdout_buf = ""

  state.proc = vim.system(cmd, {
    stdout = function(err, data)
      if err or not data then return end
      stdout_buf = stdout_buf .. data
      -- server writes: <ViperServerPort:12345>
      local port_str = stdout_buf:match("<ViperServerPort:(%d+)>")
      if port_str and not state.port then
        state.port = tonumber(port_str)
        vim.schedule(flush_callbacks)
      end
    end,
    stderr = function(err, data)
      if data and #data > 0 then
        -- only log non-empty stderr
        vim.schedule(function()
          vim.notify("[viper] server: " .. data, vim.log.levels.WARN)
        end)
      end
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

--- Stop viperserver (called on VimLeavePre).
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
