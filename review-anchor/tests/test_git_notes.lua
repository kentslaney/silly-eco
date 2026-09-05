-- Test git.lua
package.path = package.path .. ";./review-anchor/lua/?.lua;./review-anchor/lua/?/init.lua"

local git = require("review_anchor.git")
local config = require("review_anchor.config")
local anchors = require("review_anchor.anchors")

anchors.clear_all()
config.setup({
  model_name = "gemini 3.8 flash high",
  commit_mode = "detailed",
  reviewer_name = "Kent Slaney",
  reviewer_email = "kent@slaney.org",
})

-- Test 1: Slugify
assert(git.slugify("User Review Required") == "#user-review-required")
assert(git.slugify("Component 1: TargetCore (Shared Multi-Platform)") == "#component-1-targetcore-shared-multi-platform")

-- Test 2: Model only mode
config.options.commit_mode = "model_only"
local msg_model_only = git.format_commit_message()
assert(msg_model_only == "gemini 3.8 flash high", "Expected 'gemini 3.8 flash high', got: " .. msg_model_only)

-- Test 3: Detailed mode with anchors & Q/A
config.options.commit_mode = "detailed"
anchors.set_prompt("Approved plan with operational transformation updates.")

-- Add Claude Q/A (prompt snapshot context, no doc ref)
anchors.add_qa(
  "How should error correction handle camera tilt exceeding 45°?",
  "Reject frame with haptic guidance to re-orient."
)

-- Add review comment anchor (gets [Ref 1])
local buf = vim.api.nvim_create_buf(false, true)
vim.bo[buf].filetype = "markdown"
vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
  "## User Review Required",
  "> The corner lines must be 60mm long.",
})
anchors.add_anchor(buf, 1, 0, 36, "Approved. Ensure 60mm is verified with physical ruler.", "> The corner lines must be 60mm long.")

local commit_msg = git.format_commit_message()
assert(commit_msg:match("^gemini 3%.8 flash high"), "Subject must match model name")
assert(commit_msg:match("Claude Code Q/A Context:"), "Must have Claude Code Q/A section")
assert(commit_msg:match("• How should error correction handle camera tilt exceeding 45°%? → Reject frame with haptic guidance to re%-orient%."), "Must format Q/A with unicode bullet and arrow")
assert(commit_msg:match("%[Ref 1%] Review on \"User Review Required\":"), "Document comment must get [Ref 1]")
assert(commit_msg:match("Review: Approved%. Ensure 60mm"), "Must contain review text")
assert(commit_msg:match("Review%-Doc:"), "Must contain Review-Doc trailer")
assert(commit_msg:match("Review%-Anchor:"), "Must contain Review-Anchor trailer")
assert(commit_msg:match("Reviewed%-By: Kent Slaney <kent@slaney%.org>"), "Must contain Reviewed-By trailer")

-- Test 4: Git Notes diff -p formatting (strictly for document anchors)
local notes = git.format_git_notes()
assert(notes:match("Review Anchors %(diff %-p context%):"), "Notes header missing")
assert(notes:match("%[Ref 1%]"), "Ref 1 in notes missing")
assert(notes:match("Context: @@ ## User Review Required @@"), "diff -p context header missing in notes")
assert(notes:match("Hunk:"), "Hunk missing in notes")
assert(not notes:match("Claude Q/A"), "Q/A should not be in Git Notes")

-- Test 5: [blank] New Conversation toggle
assert(config.options.is_blank == false, "Default is_blank must be false")
assert(config.get_model_name() == "gemini 3.8 flash high")

local ra = require("review_anchor")
ra.toggle_blank()
assert(config.options.is_blank == true, "is_blank must be true after toggle")
assert(config.get_model_name() == "[blank] gemini 3.8 flash high", "get_model_name must prepend [blank] ")

local blank_commit_msg = git.format_commit_message()
assert(blank_commit_msg:match("^%[blank%] gemini 3%.8 flash high"), "Commit message must begin with [blank] header")

config.options.commit_mode = "model_only"
assert(git.format_commit_message() == "[blank] gemini 3.8 flash high", "Model-only mode must include [blank] prefix")

ra.toggle_blank()
assert(config.options.is_blank == false, "is_blank must be false after second toggle")
assert(git.format_commit_message() == "gemini 3.8 flash high", "Model-only mode must return to clean model name")
config.options.commit_mode = "detailed"

-- Test 6: Commit execution stages changes (git add -A)
local test_dir = vim.fn.tempname()
vim.fn.mkdir(test_dir, "p")
local original_cwd = vim.fn.getcwd()

-- Initialize temporary git repo
vim.fn.system(string.format("git -C %s init && git -C %s config user.name 'Test' && git -C %s config user.email 'test@example.com'",
  vim.fn.shellescape(test_dir), vim.fn.shellescape(test_dir), vim.fn.shellescape(test_dir)))

-- Switch cwd to temp repo
vim.cmd("cd " .. vim.fn.fnameescape(test_dir))

-- Write an unstaged file
local unstaged_file = test_dir .. "/test_plan.md"
local uf = io.open(unstaged_file, "w")
uf:write("# Test Plan\nUnstaged content here\n")
uf:close()

-- Check git status shows untracked/unstaged file
local status_before = vim.fn.system("git status --porcelain")
assert(status_before:match("%?%? test_plan%.md"), "File should initially be untracked")

-- Execute commit
local commit_done = false
local commit_ok = false
git.execute_commit(function(ok, msg)
  commit_done = true
  commit_ok = ok
end)

assert(commit_done, "execute_commit callback must be invoked")
assert(commit_ok, "execute_commit must succeed and stage files")

-- Verify working tree is now clean (file was staged and committed)
local status_after = vim.fn.system("git status --porcelain")
assert(vim.trim(status_after) == "", "Working directory should be clean because git add -A was run; got: " .. status_after)

-- Verify git log contains commit and git notes attached
local last_commit = vim.fn.system("git log -1 --pretty=format:%B")
assert(last_commit:match("gemini 3%.8 flash high"), "Commit message must match model name")

local last_notes = vim.fn.system("git notes show HEAD")
assert(last_notes:match("Review Anchors %(diff %-p context%):"), "Git notes must be attached to HEAD")

-- Test 7: No review information/trailers or notes if there are no comments
anchors.clear_all()
anchors.set_prompt("Just a standalone instruction prompt")
local msg_no_comments = git.format_commit_message()
assert(not msg_no_comments:match("Review%-Doc:"), "Must NOT add Review-Doc trailer when there are no comments")
assert(not msg_no_comments:match("Review%-Anchor:"), "Must NOT add Review-Anchor trailer when there are no comments")
assert(not msg_no_comments:match("Reviewed%-By:"), "Must NOT add Reviewed-By trailer when there are no comments")
assert(git.format_git_notes() == "", "format_git_notes must be empty string when there are no comments")

-- Test 8: commit_model_only (<leader>rM)
local test_file2 = test_dir .. "/second_change.txt"
local tf2 = io.open(test_file2, "w")
tf2:write("second change code\n")
tf2:close()

git.commit_model_only(function(ok, msg)
  assert(ok, "commit_model_only must succeed")
end)

local model_commit_log = vim.trim(vim.fn.system("git log -1 --pretty=format:%B"))
assert(model_commit_log == "gemini 3.8 flash high", "Model-only commit body must be exactly the model name; got: " .. model_commit_log)

-- Test 9: Amend when instructions committed without changes and HEAD is model name
-- Working tree is now clean, and HEAD is 'gemini 3.8 flash high'
local status_clean = vim.trim(vim.fn.system("git status --porcelain"))
assert(status_clean == "", "Working directory must be clean before testing amend")

anchors.set_prompt("Added instructions amending previous commit")
local commit_count_before = tonumber(vim.trim(vim.fn.system("git rev-list --count HEAD")))

git.execute_commit(function(ok, msg)
  assert(ok, "execute_commit (amend) must succeed")
end)

local commit_count_after = tonumber(vim.trim(vim.fn.system("git rev-list --count HEAD")))
assert(commit_count_before == commit_count_after, string.format("Commit count must remain same (%d == %d) because git commit --amend was used", commit_count_before, commit_count_after))

local amended_log = vim.fn.system("git log -1 --pretty=format:%B")
assert(amended_log:match("Added instructions amending previous commit"), "Amended commit must contain instructions; got: " .. amended_log)

-- Restore cwd and clean up
vim.cmd("cd " .. vim.fn.fnameescape(original_cwd))
vim.fn.delete(test_dir, "rf")

print("✓ test_git_notes.lua passed")
