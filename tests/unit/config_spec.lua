local config = require("viper.config")

describe("viper.config", function()
  before_each(function()
    -- reset to clean slate each test
    config.options = {}
  end)

  it("populates all defaults when called with no args", function()
    config.setup()
    assert.equals("viperserver", config.options.server_cmd)
    assert.equals("silicon", config.options.backend)
    assert.equals("INFO", config.options.log_level)
    assert.is_true(config.options.auto_verify)
    assert.equals("", config.options.custom_args)
    assert.same({}, config.options.server_args)
  end)

  it("merges user options over defaults", function()
    config.setup({ backend = "carbon", auto_verify = false })
    assert.equals("carbon", config.options.backend)
    assert.is_false(config.options.auto_verify)
    -- untouched defaults preserved
    assert.equals("viperserver", config.options.server_cmd)
    assert.equals("INFO", config.options.log_level)
  end)

  it("accepts custom server_cmd", function()
    config.setup({ server_cmd = "/usr/local/bin/viperserver" })
    assert.equals("/usr/local/bin/viperserver", config.options.server_cmd)
  end)

  it("accepts extra server_args", function()
    config.setup({ server_args = { "--logFile", "/tmp/viper.log" } })
    assert.same({ "--logFile", "/tmp/viper.log" }, config.options.server_args)
  end)

  it("deep-merges nested tables rather than replacing them", function()
    -- server_args is a list; deep_extend replaces list values (expected behaviour)
    config.setup({ server_args = { "--foo" } })
    assert.same({ "--foo" }, config.options.server_args)
  end)
end)
