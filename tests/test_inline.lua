-- Test inline instructions split and coordination with prompt capture
package.path = package.path .. ";./lua/?.lua;./lua/?/init.lua"

local ra = require("review_anchor")
local inline = require("review_anchor.inline")
local splits = require("review_anchor.splits")
local capture = require("review_anchor.capture")
local anchors = require("review_anchor.anchors")
local config = require("review_anchor.config")
local git = require("review_anchor.git")

anchors.clear_all()
config.setup({
  model_name = "gemini 3.8 flash high",
  commit_mode = "detailed",
  reviewer_name = "Kent Slaney",
  reviewer_email = "kent@slaney.org",
})

-- 1. Test opening inline instructions when git log is open
local main_win = vim.api.nvim_get_current_win()
local gbuf, gwin = splits.open_git_log(main_win)
assert(splits.git_log_win and vim.api.nvim_win_is_valid(splits.git_log_win), "git log split must be open")

local ibuf, iwin = inline.open_inline_instructions("Add authentication feature")
assert(inline.is_open(), "inline instructions split must be open")
assert(vim.wo[iwin].wrap == true, "inline instructions split must have wrap enabled")
assert(vim.wo[iwin].linebreak == true, "inline instructions split must have linebreak enabled")
assert(vim.wo[iwin].breakindent == true, "inline instructions split must have breakindent enabled")

-- Verify content was populated
local raw_content = inline.get_content_raw()
assert(raw_content:match("Add authentication feature"), "Inline buffer must contain initial prompt text; got: " .. raw_content)

-- 2. Test coordination with model prompt capture floating window (<leader>rp)
-- Calling open_prompt_capture should take inline content and close inline split temporarily
capture.open_prompt_capture()

-- Check that inline split was temporarily closed while floating window is active
assert(not inline.is_open(), "inline split must be temporarily closed while prompt floating window is open")

-- Simulate editing in floating window and saving
local current_float_buf = vim.api.nvim_get_current_buf()
local float_lines = vim.api.nvim_buf_get_lines(current_float_buf, 0, -1, false)
table.insert(float_lines, "Updated from floating modal")
vim.api.nvim_buf_set_lines(current_float_buf, 0, -1, false, float_lines)

-- Close floating window by triggering <CR> (save)
vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<CR>", true, false, true), "x", false)

-- Inline split must be restored and updated!
assert(inline.is_open(), "inline split must be restored after closing floating modal")
local updated_raw = inline.get_content_raw()
assert(updated_raw:match("Updated from floating modal"), "Inline split must have updated content; got: " .. updated_raw)

-- 3. Test cancel semantics (closing without saving)
-- Simulating quitting without saving (:q!)
inline.was_saved = false
vim.api.nvim_win_close(inline.inline_win, true)
-- Should not have thrown error, and inline is now closed
assert(not inline.is_open(), "inline split should now be closed after abort")

-- 4. Test save & commit semantics (:wq)
-- Set up a temporary git repo to test commit execution
local test_dir = vim.fn.tempname()
vim.fn.mkdir(test_dir, "p")
local orig_cwd = vim.fn.getcwd()
vim.fn.system(string.format("git -C %s init && git -C %s config user.name 'Test' && git -C %s config user.email 'test@example.com'",
  vim.fn.shellescape(test_dir), vim.fn.shellescape(test_dir), vim.fn.shellescape(test_dir)))
vim.cmd("cd " .. vim.fn.fnameescape(test_dir))

-- Write dummy file to commit
local dummy = test_dir .. "/feature.txt"
local df = io.open(dummy, "w")
df:write("feature implementation\n")
df:close()

-- Open inline instructions and simulate save (:w then close)
local ibuf2, iwin2 = inline.open_inline_instructions("Implemented feature XYZ with tests")
-- Mark was_saved = true (simulating :w / BufWritePost)
inline.was_saved = true
-- Write content to inline file
local f = io.open(inline.inline_file, "w")
f:write("Implemented feature XYZ with tests\n")
f:close()

-- Close window (simulating :wq)
vim.api.nvim_win_close(iwin2, true)

-- Verify git commit was created with the instructions
local last_msg = vim.fn.system("git log -1 --pretty=format:%B")
assert(last_msg:match("Implemented feature XYZ with tests"), "Commit must contain inline instructions body; got: " .. last_msg)

vim.cmd("cd " .. vim.fn.fnameescape(orig_cwd))
vim.fn.delete(test_dir, "rf")

print("✓ test_inline.lua passed")
