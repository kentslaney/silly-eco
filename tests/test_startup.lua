-- Test startup, default-off git log, and toggle behavior
package.path = package.path .. ";./lua/?.lua;./lua/?/init.lua"

local ra = require("review_anchor")
local splits = require("review_anchor.splits")

ra.start("README.md")

local current_win = vim.api.nvim_get_current_win()
local current_buf = vim.api.nvim_get_current_buf()
local buf_name = vim.api.nvim_buf_get_name(current_buf)

assert(buf_name:match("README%.md$"), "Target buffer must be README.md, got: " .. buf_name)

-- Default-off: git log split must NOT be open on startup
local windows = vim.api.nvim_tabpage_list_wins(0)
assert(#windows == 1, "Expected 1 window by default (git log split kept off by default), got: " .. #windows)

-- Verify editor has soft-wrap enabled
assert(vim.wo[current_win].wrap == true, "Editor window must have wrap enabled (soft-wrap)")
assert(vim.wo[current_win].linebreak == true, "Editor window must have linebreak enabled")
assert(vim.wo[current_win].breakindent == true, "Editor window must have breakindent enabled")

-- Test toggle git log (<leader>rl): opens git log split
splits.toggle_git_log(current_win)
windows = vim.api.nvim_tabpage_list_wins(0)
assert(#windows == 2, "Toggling git log must open the split, expected 2 windows, got: " .. #windows)
assert(splits.git_log_win and vim.api.nvim_win_is_valid(splits.git_log_win), "git log split window must be valid")

-- Verify git log command does not collapse entries to one line and uses --no-pager
local config = require("review_anchor.config")
assert(not config.options.git_log_cmd:match("%-%-oneline"), "git_log_cmd must not contain --oneline")
assert(config.options.git_log_cmd:match("%-%-graph"), "git_log_cmd must contain --graph")
assert(config.options.git_log_cmd:match("%-%-no%-pager"), "git_log_cmd must contain --no-pager")

-- Test toggle git log again: closes git log split
splits.toggle_git_log(current_win)
windows = vim.api.nvim_tabpage_list_wins(0)
assert(#windows == 1, "Toggling git log again must close the split, expected 1 window, got: " .. #windows)
assert(splits.git_log_win == nil, "git_log_win must be nil after toggle off")

-- Close all windows and test startup without plan file (defaults to inline instructions, git log off by default)
vim.cmd("only")
splits.git_log_win = nil
splits.git_log_buf = nil

ra.start("")

local inline = require("review_anchor.inline")
assert(inline.is_open(), "Starting without plan file must open inline instructions")

windows = vim.api.nvim_tabpage_list_wins(0)
assert(#windows == 1, "Must have 1 window (inline instructions) without git log split by default; got: " .. #windows)

local active_win = vim.api.nvim_get_current_win()
assert(active_win == inline.inline_win, "Focus must be in the inline instructions split")

-- Toggle git log with inline instructions open
splits.toggle_git_log(active_win)
windows = vim.api.nvim_tabpage_list_wins(0)
assert(#windows == 2, "Must have 2 windows when git log is toggled on; got: " .. #windows)

-- Toggle git log off again
splits.toggle_git_log(active_win)
windows = vim.api.nvim_tabpage_list_wins(0)
assert(#windows == 1, "Must have 1 window when git log is toggled off; got: " .. #windows)

print("✓ test_startup.lua passed")
