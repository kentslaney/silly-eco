local M = {}

M.defaults = {
  model_name = "gemini 3.8 flash high",
  commit_mode = "detailed", -- "detailed" or "model_only"
  git_log_cmd = "git log --graph --all --oneline --decorate --color=always",
  split_height_ratio = 0.35,
  min_split_height = 10,
  max_split_height = 20,
  review_status = "Approved",
  reviewer_name = nil,
  reviewer_email = nil,
  namespace_name = "review_anchor",
  gutter_sign_text = "★",
}

M.options = vim.deepcopy(M.defaults)

function M.setup_highlights()
  local set_hl = function(name, opts)
    local existing = vim.api.nvim_get_hl(0, { name = name })
    if vim.tbl_isempty(existing) then
      vim.api.nvim_set_hl(0, name, opts)
    end
  end

  set_hl("ReviewAnchorSign", { fg = "#f9e2af", bold = true })
  set_hl("ReviewAnchorVirtualText", { fg = "#9399b2", italic = true })
  set_hl("ReviewAnchorBadge", { fg = "#fab387", bold = true })
  set_hl("ReviewAnchorHunk", { fg = "#6c7086" })
  set_hl("ReviewAnchorHeader", { fg = "#89b4fa", bold = true })
  set_hl("ReviewAnchorBorder", { fg = "#b4befe" })
end

function M.get_reviewer()
  local name = M.options.reviewer_name
  local email = M.options.reviewer_email

  if not name or name == "" then
    local git_name = vim.fn.system("git config user.name"):gsub("%s+$", "")
    name = (git_name ~= "") and git_name or "Reviewer"
  end

  if not email or email == "" then
    local git_email = vim.fn.system("git config user.email"):gsub("%s+$", "")
    email = (git_email ~= "") and git_email or "reviewer@local"
  end

  return name, email
end

function M.setup(user_opts)
  M.options = vim.tbl_deep_extend("force", M.defaults, user_opts or {})
  M.setup_highlights()
end

return M
