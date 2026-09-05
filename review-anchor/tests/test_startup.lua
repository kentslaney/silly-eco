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

-- Verify editor has soft-wrap enabled
assert(vim.wo[current_win].wrap == true, "Editor window must have wrap enabled (soft-wrap)")
assert(vim.wo[current_win].linebreak == true, "Editor window must have linebreak enabled")
assert(vim.wo[current_win].breakindent == true, "Editor window must have breakindent enabled")

-- Verify git log command does not collapse entries to one line and uses --no-pager
local config = require("review_anchor.config")
assert(not config.options.git_log_cmd:match("%-%-oneline"), "git_log_cmd must not contain --oneline")
assert(config.options.git_log_cmd:match("%-%-graph"), "git_log_cmd must contain --graph")
assert(config.options.git_log_cmd:match("%-%-no%-pager"), "git_log_cmd must contain --no-pager")

-- Close all windows and test startup without plan file (defaults to inline instructions above git log)
vim.cmd("only")
local splits = require("review_anchor.splits")
splits.git_log_win = nil
splits.git_log_buf = nil

ra.start("")

local inline = require("review_anchor.inline")
assert(inline.is_open(), "Starting without plan file must open inline instructions split")
assert(splits.git_log_win and vim.api.nvim_win_is_valid(splits.git_log_win), "git log split must be open below")

local active_win = vim.api.nvim_get_current_win()
assert(active_win == inline.inline_win, "Focus must be in the inline instructions split")

local total_wins = vim.api.nvim_tabpage_list_wins(0)
assert(#total_wins == 2, "Must have exactly 2 windows (no blank split on top); got: " .. #total_wins)

print("✓ test_startup.lua passed")
