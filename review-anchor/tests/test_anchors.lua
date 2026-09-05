-- Test anchors.lua
package.path = package.path .. ";./review-anchor/lua/?.lua;./review-anchor/lua/?/init.lua"

local anchors = require("review_anchor.anchors")

anchors.clear_all()

local buf = vim.api.nvim_create_buf(false, true)
vim.bo[buf].filetype = "markdown"
local lines = {
  "# Header",
  "Line 1 content",
  "Line 2 content",
  "Line 3 content",
}
vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

-- Test 1: Add anchor
local a1 = anchors.add_anchor(buf, 1, 0, 14, "First review comment", "Line 1 content")
assert(a1.id == 1, "Expected Ref ID 1, got: " .. tostring(a1.id))
assert(a1.comment == "First review comment")
assert(a1.line_0indexed == 1)

local all_anchors = anchors.get_all_anchors()
assert(#all_anchors == 1, "Expected 1 anchor")

-- Test 2: Add second anchor
local a2 = anchors.add_anchor(buf, 2, 0, 14, "Second review comment", "Line 2 content")
assert(a2.id == 2, "Expected Ref ID 2, got: " .. tostring(a2.id))
assert(#anchors.get_all_anchors() == 2)

-- Test 3: Delete anchor
local ok = anchors.delete_anchor(1)
assert(ok == true, "Expected anchor 1 deletion to succeed")
assert(#anchors.get_all_anchors() == 1)
assert(anchors.get_all_anchors()[1].id == 2)

-- Test 4: Extmark line tracking after inserting a line above
vim.api.nvim_buf_set_lines(buf, 0, 0, false, { "Inserted line at top" })
-- Before insert, a2 was at line 2. After insert, line 2 should have shifted to line 3!
anchors.sync_positions()
local updated_anchors = anchors.get_all_anchors()
assert(updated_anchors[1].line_0indexed == 3, "Expected extmark to track line shift to line 3, got: " .. tostring(updated_anchors[1].line_0indexed))

-- Test 5: Claude Q/A and prompt
anchors.add_qa("Question test?", "Answer test.", "@@ test @@", "Test Section")
assert(#anchors.get_all_qa() == 1)

anchors.set_prompt("Test prompt")
assert(anchors.get_prompt() == "Test prompt")

-- Test 6: Clear all
anchors.clear_all()
assert(#anchors.get_all_anchors() == 0)
assert(#anchors.get_all_qa() == 0)
assert(anchors.get_prompt() == "")

print("✓ test_anchors.lua passed")
