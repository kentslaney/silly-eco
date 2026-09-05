local root = vim.fn.getcwd()
package.path = package.path .. ";./lua/?.lua;./lua/?/init.lua;" .. root .. "/lua/?.lua;" .. root .. "/lua/?/init.lua"

local ra = require("review_anchor")
local license_mod = require("review_anchor.license")
local config = require("review_anchor.config")
local git = require("review_anchor.git")
local anchors = require("review_anchor.anchors")

-- 1. Test license generation
local temp_lic_file = vim.fn.tempname()
for _, lic_key in ipairs({ "CC0-1.0", "MIT", "GPL-3.0", "Apache-2.0", "BSD-3-Clause", "Unlicense" }) do
  local ok, msg = license_mod.write_license(lic_key, temp_lic_file, "Kent Slaney", "2026")
  assert(ok, "Failed to write license: " .. lic_key .. " error: " .. tostring(msg))
  local f = io.open(temp_lic_file, "r")
  assert(f, "License file must exist")
  local content = f:read("*a")
  f:close()
  assert(#content > 50, "License content must be non-empty for: " .. lic_key)
end
pcall(os.remove, temp_lic_file)

-- 2. Test repo init workflow in a clean uninitialized directory
local test_dir = vim.fn.tempname()
vim.fn.mkdir(test_dir, "p")
local orig_cwd = vim.fn.getcwd()
vim.cmd("cd " .. vim.fn.fnameescape(test_dir))

-- Set git user config globally for test
vim.fn.system("git config --global user.name 'Kent Slaney' && git config --global user.email 'kent@slaney.org'")

-- Verify initially not in git repo
local is_git = vim.fn.system("git rev-parse --is-inside-work-tree 2>/dev/null"):gsub("%s+$", "") == "true"
assert(not is_git, "Test directory should initially not be a git repo")

-- Call init_repo in headless mode
ra.init_repo({ headless = true, license = "CC0-1.0", remote_url = "git@github.com:example/repo.git" }, function()
  -- On complete
end)

-- Verify git repo is now initialized
local is_git_after = vim.fn.system("git rev-parse --is-inside-work-tree 2>/dev/null"):gsub("%s+$", "") == "true"
assert(is_git_after, "Git repo must be initialized")

-- Verify remote was added
local remote = vim.fn.system("git remote get-url origin 2>/dev/null"):gsub("%s+$", "")
assert(remote == "git@github.com:example/repo.git", "Remote origin must be set; got: " .. remote)

-- Verify LICENSE exists and initial commit was created
assert(vim.fn.filereadable("LICENSE") == 1, "LICENSE file must exist")
local init_commit = vim.fn.system("git log -1 --pretty=format:%s")
assert(init_commit:match("Initial commit"), "Initial commit must be created; got: " .. init_commit)

-- Verify .gitignore exists and is staged
assert(vim.fn.filereadable(".gitignore") == 1, ".gitignore must exist")
local st = vim.fn.system("git status --porcelain")
assert(st:match("A%s+%.gitignore"), ".gitignore must be staged (added) in git status; got: " .. st)

-- Verify omit_model_header is enabled for the first prompt
assert(config.options.omit_model_header == true, "omit_model_header must be true for first prompt")

-- 3. Test first prompt commit does NOT have model name on the first line
anchors.set_prompt("Add blank .gitignore and configure basic project files")
local first_msg = git.format_commit_message()
assert(not first_msg:match("gemini 3%.8 flash high"), "First prompt commit message must not contain model header")
assert(first_msg:match("^Add blank %.gitignore"), "Commit message must begin with prompt directly; got: " .. first_msg)

-- Execute the commit
git.execute_commit()

-- Verify commit in git log
local last_log = vim.fn.system("git log -1 --pretty=format:%B")
assert(last_log:match("^Add blank %.gitignore"), "Git log must show prompt without model name on first line; got: " .. last_log)
assert(not last_log:match("gemini 3%.8 flash high"), "Git commit must not contain model name")

-- Verify omit_model_header automatically resets to false for subsequent commits
assert(config.options.omit_model_header == false, "omit_model_header must be reset to false after first commit")

-- Cleanup
vim.cmd("cd " .. vim.fn.fnameescape(orig_cwd))
vim.fn.delete(test_dir, "rf")

print("✓ test_repo_init.lua passed")
