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

-- Restore cwd and clean up
vim.cmd("cd " .. vim.fn.fnameescape(original_cwd))
vim.fn.delete(test_dir, "rf")

print("✓ test_git_notes.lua passed")
