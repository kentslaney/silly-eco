-- Test diff_p.lua
package.path = package.path .. ";./lua/?.lua;./lua/?/init.lua"

local diff_p = require("review_anchor.diff_p")

-- Test 1: Markdown heading context extraction
local md_buf = vim.api.nvim_create_buf(false, true)
vim.bo[md_buf].filetype = "markdown"
local md_lines = {
  "# Project Title",
  "",
  "Introduction text.",
  "",
  "## User Review Required",
  "",
  "> [!IMPORTANT]",
  "> Critical requirement.",
  "",
  "### Component 1",
  "Details here.",
}
vim.api.nvim_buf_set_lines(md_buf, 0, -1, false, md_lines)

local ctx1, title1 = diff_p.find_enclosing_context(md_buf, 8) -- inside "## User Review Required"
assert(ctx1 == "@@ ## User Review Required @@", "Expected '@@ ## User Review Required @@', got: " .. tostring(ctx1))
assert(title1 == "User Review Required", "Expected 'User Review Required', got: " .. tostring(title1))

local ctx2, title2 = diff_p.find_enclosing_context(md_buf, 11) -- inside "### Component 1"
assert(ctx2 == "@@ ### Component 1 @@", "Expected '@@ ### Component 1 @@', got: " .. tostring(ctx2))
assert(title2 == "Component 1", "Expected 'Component 1', got: " .. tostring(title2))

-- Test 2: Hunk extraction
local hunk, s, e = diff_p.extract_hunk(md_buf, 7, 8, 1)
assert(#hunk >= 3, "Expected at least 3 lines in hunk, got: " .. #hunk)
assert(s <= 7 and e >= 8, "Hunk bounds incorrect")

-- Test 3: Code function context extraction
local code_buf = vim.api.nvim_create_buf(false, true)
vim.bo[code_buf].filetype = "lua"
local code_lines = {
  "local M = {}",
  "",
  "function M.compute_pose()",
  "  local x = 1",
  "  local y = 2",
  "  return x + y",
  "end",
}
vim.api.nvim_buf_set_lines(code_buf, 0, -1, false, code_lines)

local ctx_code, title_code = diff_p.find_enclosing_context(code_buf, 5)
assert(ctx_code == "@@ function M.compute_pose() @@", "Expected '@@ function M.compute_pose() @@', got: " .. tostring(ctx_code))

print("✓ test_diff_p.lua passed")
