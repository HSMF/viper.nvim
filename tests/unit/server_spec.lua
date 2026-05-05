local server = require("viper.server")

describe("viper.server._parse_port", function()
    it("returns nil when no port announcement present", function()
        assert.is_nil(server._parse_port("starting up..."))
        assert.is_nil(server._parse_port(""))
        assert.is_nil(server._parse_port("ViperServerPort:abc"))
    end)

    it("extracts port from exact announcement", function()
        assert.equals(12345, server._parse_port("<ViperServerPort:12345>"))
    end)

    it("extracts port when announcement is embedded in larger output", function()
        local data = "INFO: loading\n<ViperServerPort:9876>\nready\n"
        assert.equals(9876, server._parse_port(data))
    end)

    it("returns a number, not a string", function()
        local port = server._parse_port("<ViperServerPort:1234>")
        assert.equals("number", type(port))
    end)

    it("handles multi-chunk accumulation by matching on concatenated buffer", function()
        -- Simulate two chunks that together form the announcement
        local chunk1 = "starting...<ViperServer"
        local chunk2 = "Port:8080>"
        local buf = chunk1
        assert.is_nil(server._parse_port(buf))
        buf = buf .. chunk2
        assert.equals(8080, server._parse_port(buf))
    end)
end)

describe("viper.server.ensure_started (callback queuing)", function()
    local orig_state

    before_each(function()
        -- snapshot original state and inject a clean test state
        orig_state = server._state
        -- Replace the module-level state table in place so server code sees it
        server._state.proc = nil
        server._state.port = nil
        server._state.callbacks = {}
    end)

    after_each(function()
        -- restore
        server._state.proc = nil
        server._state.port = nil
        server._state.callbacks = {}
    end)

    it("calls cb immediately when port already known", function()
        server._state.port = 9999
        local received = nil
        server.ensure_started(function(p) received = p end)
        assert.equals(9999, received)
    end)

    it("queues multiple callbacks when server is starting (proc set, port nil)", function()
        -- Simulate 'starting' state: proc is truthy, port is nil
        server._state.proc = true -- sentinel (non-nil)
        local calls = {}
        server.ensure_started(function(p) table.insert(calls, p) end)
        server.ensure_started(function(p) table.insert(calls, p) end)
        -- Neither should have fired yet
        assert.equals(0, #calls)
        -- Both should be queued
        assert.equals(2, #server._state.callbacks)
    end)
end)
