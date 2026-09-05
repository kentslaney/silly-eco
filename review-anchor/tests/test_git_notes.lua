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

-- Add Claude Q/A
anchors.add_qa(
  "How should error correction handle camera tilt exceeding 45°?",
  "Reject frame with haptic guidance to re-orient.",
  "@@ ## User Review Required @@",
  "User Review Required",
  "implementation_plan.md"
)

-- Add review comment anchor
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
assert(commit_msg:match("%- %[Ref 1%] How should error correction handle camera tilt exceeding 45°%? %-> Reject frame with haptic guidance to re%-orient%."), "Must format Q/A as bullet point, question, right arrow, answer")
assert(commit_msg:match("%[Ref 2%] Review on \"User Review Required\":"), "Must have [Ref 2] for comment")
assert(commit_msg:match("Review: Approved%. Ensure 60mm"), "Must contain review text")
assert(commit_msg:match("Review%-Doc:"), "Must contain Review-Doc trailer")
assert(commit_msg:match("Review%-Anchor:"), "Must contain Review-Anchor trailer")
assert(commit_msg:match("Reviewed%-By: Kent Slaney <kent@slaney%.org>"), "Must contain Reviewed-By trailer")

-- Test 4: Git Notes diff -p formatting
local notes = git.format_git_notes()
assert(notes:match("Review Anchors %(diff %-p context%):"), "Notes header missing")
assert(notes:match("%[Ref 1%] implementation_plan%.md %(Claude Q/A%)"), "Ref 1 in notes missing")
assert(notes:match("%- How should error correction handle camera tilt exceeding 45°%? %-> Reject frame with haptic guidance to re%-orient%."), "Notes must format Q/A as bullet question -> answer")
assert(notes:match("%[Ref 2%]"), "Ref 2 in notes missing")
assert(notes:match("Context: @@ ## User Review Required @@"), "diff -p context header missing in notes")
assert(notes:match("Hunk:"), "Hunk missing in notes")

print("✓ test_git_notes.lua passed")
