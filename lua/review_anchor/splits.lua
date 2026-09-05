local config = require("review_anchor.config")

local M = {}

M.git_log_win = nil
M.git_log_buf = nil

--- Open git log --graph --all in a horizontal split below the main buffer.
---@param main_win? integer
---@return integer git_buf, integer git_win
function M.open_git_log(main_win)
  main_win = main_win or vim.api.nvim_get_current_win()

  -- If already open and valid, just return
  if M.git_log_win and vim.api.nvim_win_is_valid(M.git_log_win) then
    return M.git_log_buf, M.git_log_win
  end

  local total_lines = vim.o.lines
  local height = math.floor(total_lines * config.options.split_height_ratio)
  height = math.max(config.options.min_split_height, math.min(config.options.max_split_height, height))

  -- Create horizontal split at bottom
  vim.cmd(string.format("botright %dsplit", height))
  local git_win = vim.api.nvim_get_current_win()

  -- Run terminal command
  local cmd = config.options.git_log_cmd or "git --no-pager log --graph --all"
  vim.cmd("terminal " .. cmd)
  local git_buf = vim.api.nvim_get_current_buf()

  M.git_log_win = git_win
  M.git_log_buf = git_buf

  -- Buffer options
  vim.bo[git_buf].bufhidden = "wipe"
  pcall(function()
    vim.api.nvim_win_set_option(git_win, "number", false)
    vim.api.nvim_win_set_option(git_win, "relativenumber", false)
    vim.api.nvim_win_set_option(git_win, "signcolumn", "no")
    vim.api.nvim_win_set_option(git_win, "wrap", false)
  end)

  -- Terminal keymaps
  local function close_split()
    if M.git_log_win and vim.api.nvim_win_is_valid(M.git_log_win) then
      vim.api.nvim_win_close(M.git_log_win, true)
      M.git_log_win = nil
      M.git_log_buf = nil
    end
    if main_win and vim.api.nvim_win_is_valid(main_win) then
      vim.api.nvim_set_current_win(main_win)
    end
  end

  vim.keymap.set("n", "q", close_split, { buffer = git_buf, nowait = true })
  vim.keymap.set("n", "<Esc>", close_split, { buffer = git_buf, nowait = true })

  -- Return focus to main buffer window
  if main_win and vim.api.nvim_win_is_valid(main_win) then
    vim.api.nvim_set_current_win(main_win)
  end

  return git_buf, git_win
end

--- Toggle the git log split below.
---@param main_win? integer
function M.toggle_git_log(main_win)
  if M.git_log_win and vim.api.nvim_win_is_valid(M.git_log_win) then
    vim.api.nvim_win_close(M.git_log_win, true)
    M.git_log_win = nil
    M.git_log_buf = nil
  else
    M.open_git_log(main_win)
  end
end

--- Refresh the git log split if it is currently open.
---@param main_win? integer
function M.refresh_git_log(main_win)
  if M.git_log_win and vim.api.nvim_win_is_valid(M.git_log_win) then
    vim.api.nvim_win_close(M.git_log_win, true)
    M.git_log_win = nil
    M.git_log_buf = nil
    M.open_git_log(main_win)
  end
end

return M
