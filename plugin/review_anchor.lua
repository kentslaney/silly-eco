-- Review Anchor Neovim Plugin Entrypoint
-- Automatically registers commands when loaded by plugin managers (e.g. lazy.nvim, packer)

if vim.g.loaded_review_anchor then
  return
end
vim.g.loaded_review_anchor = 1

vim.api.nvim_create_user_command("Review", function(opts)
  local file = opts.args ~= "" and opts.args or nil
  require("review_anchor").start(file)
end, {
  nargs = "?",
  complete = "file",
  desc = "Start Review Anchor session (opens target file or inline instructions)",
})

vim.api.nvim_create_user_command("ReviewInit", function(opts)
  local cwd = opts.args ~= "" and opts.args or nil
  require("review_anchor.splash").open_init_splash({ cwd = cwd })
end, {
  nargs = "?",
  complete = "dir",
  desc = "Open Review Anchor repository initialization splash screen for cwd",
})

vim.api.nvim_create_user_command("ReviewLog", function()
  require("review_anchor.splits").toggle_git_log(vim.api.nvim_get_current_win())
end, {
  desc = "Toggle Review Anchor git log --graph split below",
})

vim.api.nvim_create_user_command("ReviewModelCommit", function()
  require("review_anchor.git").commit_model_only()
end, {
  desc = "Commit staged changes with just the configured AI model name",
})
