-- Test startup and splits
package.path = package.path .. ";./review-anchor/lua/?.lua;./review-anchor/lua/?/init.lua"

local ra = require("review_anchor")

ra.start("review-anchor/implementation_plan.md")

local current_win = vim.api.nvim_get_current_win()
local current_buf = vim.api.nvim_get_current_buf()
local buf_name = vim.api.nvim_buf_get_name(current_buf)

assert(buf_name:match("implementation_plan%.md$"), "Target buffer must be implementation_plan.md, got: " .. buf_name)

local windows = vim.api.nvim_tabpage_list_wins(0)
assert(#windows >= 2, "Expected at least 2 windows (normal buffer + git log split), got: " .. #windows)

-- Verify current window is the upper (normal) buffer window
assert(current_win == windows[1], "Active focus must be in upper normal window")

print("✓ test_startup.lua passed")
