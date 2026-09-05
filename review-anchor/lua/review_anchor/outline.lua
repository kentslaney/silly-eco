local M = {}

--- Calculate foldlevel for Markdown lines (org-mode style).
---@param lnum integer
---@return string
function M.foldexpr(lnum)
  local line = vim.fn.getline(lnum)
  local hashes = line:match("^(#+)%s+")
  if hashes then
    return ">" .. tostring(#hashes)
  end
  return "="
end

--- Clean foldtext showing heading and line count.
---@return string
function M.foldtext()
  local fs = vim.v.foldstart
  local fe = vim.v.foldend
  local line = vim.fn.getline(fs)
  local count = fe - fs + 1
  return string.format("▶ %s  ··· (%d lines)", line, count)
end

--- Cycle fold state for the current line / heading under cursor.
function M.cycle_fold()
  local line_num = vim.api.nvim_win_get_cursor(0)[1]
  local is_folded = vim.fn.foldclosed(line_num) ~= -1

  if is_folded then
    -- Open current fold
    vim.cmd("normal! zo")
  else
    local line_text = vim.api.nvim_get_current_line()
    if line_text:match("^#+%s+") then
      -- If on heading and open, close it
      vim.cmd("normal! zc")
    else
      -- Toggle fold at cursor
      vim.cmd("normal! za")
    end
  end
end

local global_fold_states = { 0, 1, 2, 99 }
local current_global_state_idx = 1

--- Cycle global fold levels across the entire buffer (all -> H1 -> H2 -> open all).
function M.cycle_global_fold()
  current_global_state_idx = (current_global_state_idx % #global_fold_states) + 1
  local target_level = global_fold_states[current_global_state_idx]

  vim.opt_local.foldlevel = target_level

  local desc = (target_level == 99) and "All Expanded" or string.format("Level %d", target_level)
  vim.notify("Global outline: " .. desc, vim.log.levels.INFO, { title = "Review Anchor" })
end

--- Jump to next heading.
function M.jump_next_heading()
  vim.fn.search("^#\\+\\s\\+", "W")
end

--- Jump to previous heading.
function M.jump_prev_heading()
  vim.fn.search("^#\\+\\s\\+", "bW")
end

--- Toggle markdown checkbox or add one.
function M.toggle_checkbox()
  local line_num = vim.api.nvim_win_get_cursor(0)[1]
  local line = vim.api.nvim_get_current_line()

  local new_line = nil
  if line:match("^%s*[%-%*]%s+%[[%s]%]%s*") then
    new_line = line:gsub("^(%s*[%-%*]%s+)%[[%s]%](%s*)", "%1[x]%2")
  elseif line:match("^%s*[%-%*]%s+%[[xX]%]%s*") then
    new_line = line:gsub("^(%s*[%-%*]%s+)%[[xX]%](%s*)", "%1[ ]%2")
  elseif line:match("^%s*[%-%*]%s+") then
    new_line = line:gsub("^(%s*[%-%*]%s+)", "%1[ ] ")
  else
    new_line = "- [ ] " .. line
  end

  if new_line then
    vim.api.nvim_set_current_line(new_line)
  end
end

--- Attach outline folding configuration to buffer.
---@param bufnr integer
function M.setup_buffer(bufnr)
  pcall(function()
    vim.wo[0].foldmethod = "expr"
    vim.wo[0].foldexpr = "v:lua.require'review_anchor.outline'.foldexpr(v:lnum)"
    vim.wo[0].foldtext = "v:lua.require'review_anchor.outline'.foldtext()"
    vim.wo[0].foldenable = true
    vim.wo[0].foldlevel = 99 -- start open so full content is visible initially
  end)
end

return M
