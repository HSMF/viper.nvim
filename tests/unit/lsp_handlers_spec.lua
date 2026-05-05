local lsp = require("viper.lsp")

-- Helper: create a named scratch buffer with given lines, return bufnr + URI.
-- Scratch buffers need a name so vim.uri_from_bufnr / vim.uri_to_bufnr
-- round-trips back to the same (loaded) buffer.
local function make_buf(lines)
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(bufnr, vim.fn.tempname() .. ".vpr")
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    local uri = vim.uri_from_bufnr(bufnr)
    return bufnr, uri
end

describe("viper.lsp protocol handlers", function()
    local handlers

    before_each(function()
        handlers = lsp._make_handlers()
    end)

    -- ── GetViperFileEndings ────────────────────────────────────────────────────

    describe("GetViperFileEndings", function()
        it("returns .vpr and .sil", function()
            local result = handlers["GetViperFileEndings"]()
            assert.same({ ".vpr", ".sil" }, result.fileEndings)
        end)
    end)

    -- ── GetIdentifier ──────────────────────────────────────────────────────────

    describe("GetIdentifier", function()
        it("extracts word at column inside identifier", function()
            local _, uri = make_buf({ "method foo(x: Int)" })
            local ctx = { uri = uri }
            -- cursor at col 3 (inside "method")
            local result = handlers["GetIdentifier"](nil, { line = 0, character = 3 }, ctx)
            assert.equals("method", result.identifier)
        end)

        it("extracts word when cursor is at the start of identifier", function()
            local _, uri = make_buf({ "  requires acc(this.f)" })
            local ctx = { uri = uri }
            -- col 2 = 'r' (start of "requires")
            local result = handlers["GetIdentifier"](nil, { line = 0, character = 2 }, ctx)
            assert.equals("requires", result.identifier)
        end)

        it("returns empty string for whitespace position", function()
            local _, uri = make_buf({ "foo  bar" })
            local ctx = { uri = uri }
            -- col 4 = first space between foo and bar
            local result = handlers["GetIdentifier"](nil, { line = 0, character = 4 }, ctx)
            assert.equals("", result.identifier)
        end)

        it("returns vim.NIL when err is set", function()
            local _, uri = make_buf({ "foo" })
            local result = handlers["GetIdentifier"]("some error", { line = 0, character = 0 }, { uri = uri })
            assert.equals(vim.NIL, result)
        end)
    end)

    -- ── GetRange ───────────────────────────────────────────────────────────────

    describe("GetRange", function()
        it("returns text for a single-line range", function()
            local _, uri = make_buf({ "line one", "line two", "line three" })
            local ctx = { uri = uri }
            local result = handlers["GetRange"](nil, {
                start = { line = 1, character = 0 },
                ["end"] = { line = 1, character = 0 },
            }, ctx)
            assert.equals("line two", result.text)
        end)

        it("returns newline-joined text for multi-line range", function()
            local _, uri = make_buf({ "aaa", "bbb", "ccc" })
            local ctx = { uri = uri }
            local result = handlers["GetRange"](nil, {
                start = { line = 0, character = 0 },
                ["end"] = { line = 1, character = 0 },
            }, ctx)
            assert.equals("aaa\nbbb", result.text)
        end)

        it("returns vim.NIL when err is set", function()
            local _, uri = make_buf({ "foo" })
            local result = handlers["GetRange"]("err", {
                start = { line = 0, character = 0 },
                ["end"] = { line = 0, character = 0 },
            }, { uri = uri })
            assert.equals(vim.NIL, result)
        end)
    end)

    -- ── Hint ──────────────────────────────────────────────────────────────────

    describe("Hint handler", function()
        it("calls vim.notify with INFO level", function()
            local captured = {}
            local orig = vim.notify
            vim.notify = function(msg, level) table.insert(captured, { msg = msg, level = level }) end

            handlers["Hint"](nil, { message = "Hello from ViperServer" })

            vim.notify = orig
            assert.equals(1, #captured)
            assert.matches("Hello from ViperServer", captured[1].msg)
            assert.equals(vim.log.levels.INFO, captured[1].level)
        end)

        it("is silent on error", function()
            local called = false
            local orig = vim.notify
            vim.notify = function() called = true end
            handlers["Hint"]("some error", nil)
            vim.notify = orig
            assert.is_false(called)
        end)
    end)

    -- ── Log ───────────────────────────────────────────────────────────────────

    describe("Log handler", function()
        it("surfaces level >= 2 as WARN", function()
            local captured = {}
            local orig = vim.notify
            vim.notify = function(msg, level) table.insert(captured, { msg = msg, level = level }) end

            handlers["Log"](nil, { level = 3, msg = "verbose info" })

            vim.notify = orig
            assert.equals(1, #captured)
            assert.equals(vim.log.levels.WARN, captured[1].level)
        end)

        it("does not surface level < 2", function()
            local called = false
            local orig = vim.notify
            vim.notify = function() called = true end
            handlers["Log"](nil, { level = 1, msg = "debug noise" })
            vim.notify = orig
            assert.is_false(called)
        end)
    end)

    -- ── VerificationNotStarted ────────────────────────────────────────────────

    describe("VerificationNotStarted handler", function()
        it("notifies WARN with uri when present", function()
            local captured = {}
            local orig = vim.notify
            vim.notify = function(msg, level) table.insert(captured, { msg = msg, level = level }) end

            handlers["VerificationNotStarted"](nil, { uri = "file:///tmp/foo.vpr" })

            vim.notify = orig
            assert.equals(1, #captured)
            assert.matches("foo.vpr", captured[1].msg)
            assert.equals(vim.log.levels.WARN, captured[1].level)
        end)
    end)

    -- ── StateChange routing ───────────────────────────────────────────────────

    describe("StateChange handler", function()
        it("routes to lsp.on_state_change when set", function()
            local received = nil
            lsp.on_state_change = function(params) received = params end

            handlers["StateChange"](nil, { newState = 6, success = 1 })

            lsp.on_state_change = nil
            assert.is_not_nil(received)
            assert.equals(6, received.newState)
        end)

        it("does nothing when on_state_change is nil", function()
            lsp.on_state_change = nil
            -- should not throw
            assert.has_no.errors(function()
                handlers["StateChange"](nil, { newState = 6 })
            end)
        end)
    end)
end)
