local root = vim.fn.getcwd()
package.path = package.path .. ";./lua/?.lua;./lua/?/init.lua;" .. root .. "/lua/?.lua;" .. root .. "/lua/?/init.lua"

local splash = require("review_anchor.splash")
local config = require("review_anchor.config")

-- 1. Test splash screen window creation & UI rendering
local bufnr, winnr = splash.open_init_splash({ cwd = vim.fn.getcwd() })
assert(bufnr and vim.api.nvim_buf_is_valid(bufnr), "Splash buffer must be valid")
assert(winnr and vim.api.nvim_win_is_valid(winnr), "Splash window must be valid")

local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
local text = table.concat(lines, "\n")
assert(text:match("Review Anchor — Repository Setup & Initialization"), "Splash header must be rendered")
assert(text:match("Target Directory:"), "Target directory must be displayed")
assert(text:match("License Options:"), "License options must be listed")
assert(text:match("CC0 1%.0 Universal"), "CC0 option must be present")
assert(text:match("MIT License"), "MIT option must be present")

-- Test closing via keybinding 'q'
vim.cmd("normal q")
if splash.active_win ~= nil then
  splash.close()
end
assert(splash.active_win == nil, "Splash window must be closed after pressing 'q'")

-- 2. Test initialization of uninitialized directory via splash.execute_init_direct
local original_cwd = vim.fn.getcwd()
local test_dir = vim.fn.tempname()
vim.fn.mkdir(test_dir, "p")

splash.execute_init_direct({
  cwd = test_dir,
  remote_url = "https://github.com/testuser/testrepo.git",
  license = "MIT",
}, function(ok)
  assert(ok, "execute_init_direct must succeed")
end)

local is_git = vim.fn.system(string.format("git -C %s rev-parse --is-inside-work-tree", vim.fn.shellescape(test_dir))):gsub("%s+$", "")
assert(is_git == "true", "Test directory must be a git repository")

local origin_url = vim.fn.system(string.format("git -C %s remote get-url origin", vim.fn.shellescape(test_dir))):gsub("%s+$", "")
assert(origin_url == "https://github.com/testuser/testrepo.git", "Remote origin must be set correctly")

local lic_exists = vim.fn.filereadable(test_dir .. "/LICENSE") == 1
assert(lic_exists, "LICENSE file must exist in initialized repository")

local lic_content = io.open(test_dir .. "/LICENSE", "r"):read("*a")
assert(lic_content:match("MIT License"), "LICENSE must contain MIT License text")

local gitignore_exists = vim.fn.filereadable(test_dir .. "/.gitignore") == 1
assert(gitignore_exists, ".gitignore must exist in initialized repository")

local last_commit = vim.fn.system(string.format("git -C %s log -1 --pretty=format:%%s", vim.fn.shellescape(test_dir))):gsub("%s+$", "")
assert(last_commit == "Initial commit", "First commit message must be 'Initial commit'")

-- Cleanup test_dir
vim.fn.delete(test_dir, "rf")

-- 3. Test plugin/review_anchor.lua user commands
dofile("plugin/review_anchor.lua")
local commands = vim.api.nvim_get_commands({})
assert(commands.Review ~= nil, ":Review command must be registered")
assert(commands.ReviewInit ~= nil, ":ReviewInit command must be registered")
assert(commands.ReviewLog ~= nil, ":ReviewLog command must be registered")
assert(commands.ReviewModelCommit ~= nil, ":ReviewModelCommit command must be registered")

print("✓ test_splash.lua passed")
