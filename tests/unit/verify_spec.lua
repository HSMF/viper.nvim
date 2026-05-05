local config = require("viper.config")
local lsp    = require("viper.lsp")
local verify = require("viper.verify")

-- VerificationState / Success mirrors (must match verify.lua)
local State = { Ready = 6, VerificationRunning = 2, Starting = 1, Stage = 8, ConstructingAst = 9 }
local Success = {
  Success = 1, ParsingFailed = 2, TypecheckingFailed = 3,
  VerificationFailed = 4, Aborted = 5, Error = 6, Timeout = 7,
}

local function capture_notify(fn)
  local calls = {}
  local orig = vim.notify
  vim.notify = function(msg, level) table.insert(calls, { msg = msg, level = level }) end
  fn()
  vim.notify = orig
  return calls
end

describe("viper.verify._on_state_change", function()
  describe("Ready state", function()
    it("notifies INFO on Success", function()
      local calls = capture_notify(function()
        verify._on_state_change({ newState = State.Ready, success = Success.Success,
          filename = "foo.vpr", time = 1200 })
      end)
      assert.equals(1, #calls)
      assert.equals(vim.log.levels.INFO, calls[1].level)
      assert.matches("foo.vpr", calls[1].msg)
      assert.matches("verified", calls[1].msg)
    end)

    it("notifies WARN on VerificationFailed", function()
      local calls = capture_notify(function()
        verify._on_state_change({ newState = State.Ready, success = Success.VerificationFailed,
          filename = "foo.vpr" })
      end)
      assert.equals(1, #calls)
      assert.equals(vim.log.levels.WARN, calls[1].level)
    end)

    it("notifies ERROR on ParsingFailed", function()
      local calls = capture_notify(function()
        verify._on_state_change({ newState = State.Ready, success = Success.ParsingFailed,
          filename = "foo.vpr" })
      end)
      assert.equals(vim.log.levels.ERROR, calls[1].level)
    end)

    it("notifies ERROR on TypecheckingFailed", function()
      local calls = capture_notify(function()
        verify._on_state_change({ newState = State.Ready, success = Success.TypecheckingFailed,
          filename = "foo.vpr" })
      end)
      assert.equals(vim.log.levels.ERROR, calls[1].level)
    end)

    it("notifies WARN on Timeout", function()
      local calls = capture_notify(function()
        verify._on_state_change({ newState = State.Ready, success = Success.Timeout,
          filename = "foo.vpr" })
      end)
      assert.equals(vim.log.levels.WARN, calls[1].level)
    end)

    it("notifies INFO on Aborted", function()
      local calls = capture_notify(function()
        verify._on_state_change({ newState = State.Ready, success = Success.Aborted })
      end)
      assert.equals(vim.log.levels.INFO, calls[1].level)
    end)

    it("notifies ERROR on internal Error", function()
      local calls = capture_notify(function()
        verify._on_state_change({ newState = State.Ready, success = Success.Error,
          error = "NullPointerException" })
      end)
      assert.equals(vim.log.levels.ERROR, calls[1].level)
      assert.matches("NullPointerException", calls[1].msg)
    end)
  end)

  describe("Running / Starting states", function()
    it("notifies INFO when VerificationRunning", function()
      local calls = capture_notify(function()
        verify._on_state_change({ newState = State.VerificationRunning,
          filename = "foo.vpr", progress = 42 })
      end)
      assert.equals(1, #calls)
      assert.equals(vim.log.levels.INFO, calls[1].level)
      assert.matches("42%%", calls[1].msg)
    end)

    it("notifies INFO when Starting (no progress)", function()
      local calls = capture_notify(function()
        verify._on_state_change({ newState = State.Starting, filename = "foo.vpr" })
      end)
      assert.equals(vim.log.levels.INFO, calls[1].level)
    end)

    it("notifies INFO for Stage", function()
      local calls = capture_notify(function()
        verify._on_state_change({ newState = State.Stage, stage = "type-checking" })
      end)
      assert.equals(1, #calls)
      assert.equals(vim.log.levels.INFO, calls[1].level)
      assert.matches("type%-checking", calls[1].msg)
    end)
  end)
end)

describe("viper.verify.verify (Verify notification params)", function()
  before_each(function()
    config.setup({ backend = "carbon", custom_args = "--z3Exe z3" })
  end)

  it("sends correct params to LSP client", function()
    local sent = {}
    -- Inject a fake client
    lsp.client_id = 999
    local orig_get = vim.lsp.get_client_by_id
    vim.lsp.get_client_by_id = function(id)
      if id == 999 then
        return {
          notify = function(method, params)
            table.insert(sent, { method = method, params = params })
          end,
          id = 999,
        }
      end
      return orig_get(id)
    end

    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "method foo() { }" })

    verify.verify(bufnr, true)

    vim.lsp.get_client_by_id = orig_get
    lsp.client_id = nil

    assert.equals(1, #sent)
    local p = sent[1].params
    assert.equals("Verify", sent[1].method)
    assert.equals("carbon", p.backend)
    assert.equals("--z3Exe z3", p.customArgs)
    assert.is_true(p.manuallyTriggered)
    assert.matches("method foo", p.content)
    assert.is_string(p.uri)
    assert.is_string(p.workspace)
  end)

  it("warns when client not ready", function()
    lsp.client_id = nil
    local calls = capture_notify(function()
      verify.verify(vim.api.nvim_create_buf(false, true), true)
    end)
    assert.equals(1, #calls)
    assert.equals(vim.log.levels.WARN, calls[1].level)
  end)
end)

describe("viper.verify.setup_buffer", function()
  before_each(function()
    config.setup({ auto_verify = true })
    lsp.on_state_change = nil
  end)

  local function get_autocmds(bufnr, event)
    return vim.api.nvim_get_autocmds({ event = event, buffer = bufnr })
  end

  it("registers BufWritePost autocmd when auto_verify=true", function()
    local bufnr = vim.api.nvim_create_buf(false, true)
    verify.setup_buffer(bufnr)
    local aus = get_autocmds(bufnr, "BufWritePost")
    assert.is_true(#aus >= 1)
  end)

  it("does NOT register BufWritePost when auto_verify=false", function()
    config.setup({ auto_verify = false })
    local bufnr = vim.api.nvim_create_buf(false, true)
    verify.setup_buffer(bufnr)
    local aus = get_autocmds(bufnr, "BufWritePost")
    assert.equals(0, #aus)
  end)

  it("creates :Verify buffer command regardless of auto_verify", function()
    config.setup({ auto_verify = false })
    local bufnr = vim.api.nvim_create_buf(false, true)
    verify.setup_buffer(bufnr)
    local cmds = vim.api.nvim_buf_get_commands(bufnr, {})
    assert.is_not_nil(cmds["Verify"])
  end)

  it("wires lsp.on_state_change", function()
    local bufnr = vim.api.nvim_create_buf(false, true)
    verify.setup_buffer(bufnr)
    assert.is_function(lsp.on_state_change)
  end)
end)
