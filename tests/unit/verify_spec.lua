local config  = require("viper.config")
local lsp     = require("viper.lsp")
local project = require("viper.project")
local verify  = require("viper.verify")

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
    vim.api.nvim_buf_set_name(bufnr, vim.fn.tempname() .. ".vpr")
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

-- ── Import-aware verification ──────────────────────────────────────────────────

local function fake_client(sent)
  return {
    notify = function(method, params) table.insert(sent, { method = method, params = params }) end,
    id = 888,
  }
end

local function with_fake_client(sent, fn)
  lsp.client_id = 888
  local orig = vim.lsp.get_client_by_id
  vim.lsp.get_client_by_id = function(id)
    return id == 888 and fake_client(sent) or orig(id)
  end
  fn()
  vim.lsp.get_client_by_id = orig
  lsp.client_id = nil
end

describe("viper.verify import-aware (verify_uri / verify redirect)", function()
  before_each(function()
    config.setup({ backend = "silicon", custom_args = "" })
    project.clear()
  end)

  -- ── content_for_uri ──────────────────────────────────────────────────────

  describe("_content_for_uri", function()
    it("returns buffer content when buffer is loaded", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_name(bufnr, vim.fn.tempname() .. ".vpr")
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "method bar()" })
      local uri = vim.uri_from_bufnr(bufnr)
      assert.matches("method bar", verify._content_for_uri(uri))
    end)

    it("reads from disk when buffer not loaded", function()
      local path = vim.fn.tempname() .. ".vpr"
      vim.fn.writefile({ "// disk content" }, path)
      local uri = vim.uri_from_fname(path)
      assert.matches("disk content", verify._content_for_uri(uri))
    end)

    it("returns nil when file does not exist and no buffer", function()
      local uri = vim.uri_from_fname("/nonexistent/path/x.vpr")
      assert.is_nil(verify._content_for_uri(uri))
    end)
  end)

  -- ── verify_uri ─────────────────────────────────────────────────────────────

  describe("verify_uri", function()
    it("sends Verify with the given URI directly", function()
      local path = vim.fn.tempname() .. ".vpr"
      vim.fn.writefile({ "method foo()" }, path)
      local uri = vim.uri_from_fname(path)

      local sent = {}
      with_fake_client(sent, function()
        verify.verify_uri(uri, true)
      end)

      assert.equals(1, #sent)
      assert.equals("Verify", sent[1].method)
      assert.equals(uri, sent[1].params.uri)
      assert.matches("method foo", sent[1].params.content)
    end)
  end)

  -- ── verify redirects to project root ──────────────────────────────────────

  describe("verify (import redirect)", function()
    it("verifies the root when buffer file is an imported dependency", function()
      -- Set up: root imports dep
      local root_path = vim.fn.tempname() .. ".vpr"
      local dep_path  = vim.fn.tempname() .. ".vpr"
      vim.fn.writefile({ "import \"dep.vpr\"" }, root_path)
      vim.fn.writefile({ "// dep" }, dep_path)

      local root_uri = vim.uri_from_fname(root_path)
      local dep_uri  = vim.uri_from_fname(dep_path)

      project.setup(root_uri, { dep_uri })

      -- Open dep in a buffer
      local dep_bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_name(dep_bufnr, dep_path)
      vim.api.nvim_buf_set_lines(dep_bufnr, 0, -1, false, { "// dep modified" })

      local sent = {}
      with_fake_client(sent, function()
        verify.verify(dep_bufnr, false)
      end)

      assert.equals(1, #sent)
      -- Must verify the ROOT, not the dep
      assert.equals(root_uri, sent[1].params.uri)
    end)

    it("verifies the buffer itself when not an imported file", function()
      local root_path = vim.fn.tempname() .. ".vpr"
      vim.fn.writefile({ "method main()" }, root_path)
      local root_uri = vim.uri_from_fname(root_path)

      -- root is not pinned to anything
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_name(bufnr, root_path)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "method main()" })

      local sent = {}
      with_fake_client(sent, function()
        verify.verify(bufnr, true)
      end)

      assert.equals(1, #sent)
      assert.equals(root_uri, sent[1].params.uri)
    end)
  end)

  -- ── SetupProject handler populates project map ─────────────────────────────

  describe("SetupProject handler via lsp._make_handlers", function()
    it("populates project.root_for after SetupProject", function()
      local lsp_mod = require("viper.lsp")
      local handlers = lsp_mod._make_handlers()

      local root_uri = "file:///tmp/root.vpr"
      local dep_uri  = "file:///tmp/dep.vpr"

      handlers["SetupProject"](nil, { projectUri = root_uri, otherUris = { dep_uri } })

      assert.equals(root_uri, project.root_for(dep_uri))
      assert.is_nil(project.root_for(root_uri))
    end)

    it("replaces old mappings on re-setup", function()
      local lsp_mod = require("viper.lsp")
      local handlers = lsp_mod._make_handlers()

      local root_uri  = "file:///tmp/root.vpr"
      local dep_a_uri = "file:///tmp/a.vpr"
      local dep_b_uri = "file:///tmp/b.vpr"

      handlers["SetupProject"](nil, { projectUri = root_uri, otherUris = { dep_a_uri, dep_b_uri } })
      handlers["SetupProject"](nil, { projectUri = root_uri, otherUris = { dep_a_uri } })

      assert.equals(root_uri, project.root_for(dep_a_uri))
      assert.is_nil(project.root_for(dep_b_uri))
    end)

    it("returns vim.NIL (valid RPC response)", function()
      local lsp_mod = require("viper.lsp")
      local handlers = lsp_mod._make_handlers()
      local result = handlers["SetupProject"](nil, { projectUri = "file:///x.vpr", otherUris = {} })
      assert.equals(vim.NIL, result)
    end)
  end)
end)
