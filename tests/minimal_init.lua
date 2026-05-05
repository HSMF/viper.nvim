-- Minimal Neovim init for running tests via plenary.
-- Usage:
--   nvim --headless -u tests/minimal_init.lua \
--     -c "lua require('plenary.test_harness').test_directory('tests/', {sequential=true})"
--
-- Or via make: `make test`

local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h")

-- Add this plugin to runtimepath
vim.opt.runtimepath:prepend(root)

-- Add plenary (expected at a standard lazy.nvim location; adjust if needed)
local plenary_path = vim.fn.stdpath("data") .. "/lazy/plenary.nvim"
if vim.fn.isdirectory(plenary_path) == 1 then
  vim.opt.runtimepath:append(plenary_path)
else
  -- fallback: assume plenary is already on rtp (e.g. added by test runner)
  vim.notify("plenary not found at " .. plenary_path .. "; must be on &rtp", vim.log.levels.WARN)
end

-- Silence vim.notify during tests (tests capture it themselves)
-- Leave enabled so test failures surface.
