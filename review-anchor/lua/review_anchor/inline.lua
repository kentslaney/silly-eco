local config = require("review_anchor.config")
local anchors = require("review_anchor.anchors")
local git = require("review_anchor.git")
local splits = require("review_anchor.splits")

local M = {}

M.inline_win = nil
M.inline_buf = nil
M.inline_file = nil
M.was_saved = false
M.is_temporary_close = false

--- Check if the inline instructions split is currently open and valid.
---@return boolean
function M.is_open()
  return M.inline_win ~= nil and vim.api.nvim_win_is_valid(M.inline_win)
end

--- Get the current content from the inline instructions buffer or file.
---@return string
function M.get_content_raw()
  if not M.is_open() or not M.inline_buf or not vim.api.nvim_buf_is_valid(M.inline_buf) then
    return anchors.get_prompt()
  end

  local lines = vim.api.nvim_buf_get_lines(M.inline_buf, 0, -1, false)
  local prompt_lines = {}
  for _, l in ipairs(lines) do
    if not l:match("^#") then
      table.insert(prompt_lines, l)
    end
  end
  return vim.trim(table.concat(prompt_lines, "\n"))
end

--- Temporarily close the inline split without triggering cancel/commit (for floating window transfer).
function M.close_split_temporary()
  if M.is_open() then
    M.is_temporary_close = true
    vim.api.nvim_win_close(M.inline_win, true)
    M.inline_win = nil
    M.inline_buf = nil
  end
end

--- Open inline instructions split.
--- Opens in target_win if provided, or above git log graph if present, or below current window.
---@param initial_content? string
---@param target_win? integer
---@return integer bufnr, integer winnr
function M.open_inline_instructions(initial_content, target_win)
  -- If already open, focus and optionally update
  if M.is_open() then
    vim.api.nvim_set_current_win(M.inline_win)
    if initial_content and initial_content ~= "" and M.inline_buf and vim.api.nvim_buf_is_valid(M.inline_buf) then
      local lines = vim.split(initial_content, "\n")
      vim.api.nvim_buf_set_lines(M.inline_buf, 0, -1, false, lines)
    end
    return M.inline_buf, M.inline_win
  end

  if target_win and vim.api.nvim_win_is_valid(target_win) then
    vim.api.nvim_set_current_win(target_win)
  else
    -- Position split: above git log graph if open, otherwise below current window
    if splits.git_log_win and vim.api.nvim_win_is_valid(splits.git_log_win) then
      vim.api.nvim_set_current_win(splits.git_log_win)
      vim.cmd("aboveleft split")
      target_win = vim.api.nvim_get_current_win()
    else
      vim.cmd("belowright split")
      target_win = vim.api.nvim_get_current_win()
    end
  end

  -- Create temporary file for rebase-like file editing
  local temp_file = vim.fn.tempname() .. "_inline_instructions.md"
  local f = io.open(temp_file, "w")
  if not f then
    vim.notify("Failed to create temporary instructions file", vim.log.levels.ERROR, { title = "Review Anchor" })
    if vim.api.nvim_win_is_valid(target_win) then
      vim.api.nvim_win_close(target_win, true)
    end
    return 0, 0
  end

  local header_comments = {
    "# --- Review Anchor: Inline Instructions ---",
    "# Like with git rebase: save & quit (:wq / ZZ) to commit changes.",
    "# Quit without saving (:q! / ZQ) to cancel operation.",
    "# Lines starting with '#' will be ignored.",
    "",
  }

  local prompt_body = initial_content
  if not prompt_body or prompt_body == "" then
    local existing = anchors.get_prompt()
    prompt_body = (existing ~= "") and existing or ""
  end

  for _, l in ipairs(header_comments) do
    f:write(l .. "\n")
  end
  if prompt_body ~= "" then
    f:write(prompt_body .. "\n")
  end
  f:close()

  -- Edit temporary file
  vim.cmd("edit " .. vim.fn.fnameescape(temp_file))
  local buf = vim.api.nvim_get_current_buf()

  M.inline_win = target_win
  M.inline_buf = buf
  M.inline_file = temp_file
  M.was_saved = false
  M.is_temporary_close = false

  -- Window & buffer options
  vim.bo[buf].filetype = "markdown"
  vim.bo[buf].bufhidden = "wipe"
  vim.wo[target_win].wrap = true
  vim.wo[target_win].linebreak = true
  vim.wo[target_win].breakindent = true

  -- Position cursor at end of instructions
  local line_count = vim.api.nvim_buf_line_count(buf)
  pcall(vim.api.nvim_win_set_cursor, target_win, { line_count, 0 })

  -- Track saves
  vim.api.nvim_create_autocmd("BufWritePost", {
    buffer = buf,
    callback = function()
      M.was_saved = true
    end,
  })

  -- Handle buffer close (commit if saved, cancel if not saved)
  vim.api.nvim_create_autocmd("BufWinLeave", {
    buffer = buf,
    once = true,
    callback = function()
      if M.is_temporary_close then
        M.is_temporary_close = false
        return
      end

      local was_saved = M.was_saved
      local file_to_read = M.inline_file

      M.inline_win = nil
      M.inline_buf = nil
      M.inline_file = nil
      M.was_saved = false

      if was_saved and file_to_read then
        local rf = io.open(file_to_read, "r")
        local content_lines = {}
        if rf then
          for line in rf:lines() do
            if not line:match("^#") then
              table.insert(content_lines, line)
            end
          end
          rf:close()
        end

        local instruction_text = vim.trim(table.concat(content_lines, "\n"))
        pcall(os.remove, file_to_read)

        if instruction_text ~= "" then
          anchors.set_prompt(instruction_text)
          git.execute_commit(function(ok, msg)
            if ok then
              vim.notify("Inline instructions committed successfully!", vim.log.levels.INFO, { title = "Review Anchor" })
            else
              vim.notify("Commit failed:\n" .. tostring(msg), vim.log.levels.ERROR, { title = "Review Anchor" })
            end
          end)
        else
          vim.notify("Empty inline instructions; commit cancelled.", vim.log.levels.WARN, { title = "Review Anchor" })
        end
      else
        if file_to_read then
          pcall(os.remove, file_to_read)
        end
        vim.notify("Inline instructions cancelled (not saved).", vim.log.levels.INFO, { title = "Review Anchor" })
      end
    end,
  })

  -- Buffer-local keymaps for intuitive rebase/org actions
  local map_buf = function(lhs, rhs, desc)
    vim.keymap.set("n", lhs, rhs, { buffer = buf, silent = true, desc = "InlineInstructions: " .. desc })
  end

  map_buf("<C-s>", ":w<CR>", "Save instructions")
  map_buf("<C-c><C-c>", ":wq<CR>", "Save and commit")
  map_buf("<C-c><C-k>", ":q!<CR>", "Cancel and abort")

  return buf, target_win
end

return M
