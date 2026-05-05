local project = require("viper.project")

local function uri(name)
    return "file:///tmp/" .. name .. ".vpr"
end

describe("viper.project", function()
    before_each(function()
        project.clear()
    end)

    -- ── setup ─────────────────────────────────────────────────────────────────

    describe("setup", function()
        it("maps imported files to their root", function()
            project.setup(uri("main"), { uri("a"), uri("b") })
            assert.equals(uri("main"), project.root_for(uri("a")))
            assert.equals(uri("main"), project.root_for(uri("b")))
        end)

        it("returns nil for the root itself", function()
            project.setup(uri("main"), { uri("a") })
            assert.is_nil(project.root_for(uri("main")))
        end)

        it("returns nil for unknown file", function()
            assert.is_nil(project.root_for(uri("unknown")))
        end)

        it("replaces stale mappings when root is re-established", function()
            -- first setup: main imports a and b
            project.setup(uri("main"), { uri("a"), uri("b") })
            -- second setup: main now only imports a (b was removed)
            project.setup(uri("main"), { uri("a") })
            assert.equals(uri("main"), project.root_for(uri("a")))
            assert.is_nil(project.root_for(uri("b")))
        end)

        it("handles a file imported by multiple projects (last writer wins)", function()
            project.setup(uri("root1"), { uri("shared") })
            project.setup(uri("root2"), { uri("shared") })
            -- shared is now owned by root2
            assert.equals(uri("root2"), project.root_for(uri("shared")))
        end)

        it("handles empty other_uris", function()
            assert.has_no.errors(function()
                project.setup(uri("main"), {})
            end)
            assert.is_nil(project.root_for(uri("main")))
        end)
    end)

    -- ── clear ─────────────────────────────────────────────────────────────────

    describe("clear", function()
        it("removes all mappings", function()
            project.setup(uri("main"), { uri("a") })
            project.clear()
            assert.is_nil(project.root_for(uri("a")))
        end)
    end)
end)
