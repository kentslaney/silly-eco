local anchors = require("review_anchor.anchors")
local git = require("review_anchor.git")
local config = require("review_anchor.config")

local M = {}

--- Helper to create a centered floating window.
---@param title string
---@param width_ratio? number
---@param height_ratio? number
---@return integer bufnr, integer winnr
local function create_floating_window(title, width_ratio, height_ratio)
  width_ratio = width_ratio or 0.75
  height_ratio = height_ratio or 0.60

  local total_w = vim.o.columns
  local total_h = vim.o.lines

  local width = math.max(40, math.floor(total_w * width_ratio))
  local height = math.max(10, math.floor(total_h * height_ratio))

  local row = math.floor((total_h - height) / 2)
  local col = math.floor((total_w - width) / 2)

  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.bo[bufnr].buftype = "nofile"
  vim.bo[bufnr].bufhidden = "wipe"
  vim.bo[bufnr].swapfile = false

  local winnr = vim.api.nvim_open_win(bufnr, true, {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = "rounded",
    title = " " .. title .. " ",
    title_pos = "center",
  })

  vim.wo[winnr].wrap = true
  vim.wo[winnr].cursorline = true

  return bufnr, winnr
end

--- Capture a review comment for a line or visual selection.
---@param bufnr integer
---@param line_0indexed integer
---@param col_start integer
---@param col_end integer
---@param selected_text string
function M.open_comment_capture(bufnr, line_0indexed, col_start, col_end, selected_text)
  local target_buf = bufnr
  local preview_title = string.format("Review Comment (Line %d)", line_0indexed + 1)
  local cbuf, cwin = create_floating_window(preview_title, 0.70, 0.45)

  local header = {
    "# Target: " .. (selected_text ~= "" and selected_text or "(empty line)"),
    "# Enter your review comment below.",
    "# Keymaps: <C-s> or <CR> in normal mode to Save | <Esc> or q to Cancel",
    "",
  }

  vim.api.nvim_buf_set_lines(cbuf, 0, -1, false, header)
  vim.api.nvim_win_set_cursor(cwin, { #header, 0 })
  vim.cmd("startinsert")

  local function save_comment()
    local all_lines = vim.api.nvim_buf_get_lines(cbuf, 0, -1, false)
    local comment_lines = {}
    for i = 4, #all_lines do
      table.insert(comment_lines, all_lines[i])
    end
    local comment = vim.trim(table.concat(comment_lines, "\n"))

    if comment == "" then
      vim.notify("Empty comment, cancelled.", vim.log.levels.WARN, { title = "Review Anchor" })
    else
      local anchor = anchors.add_anchor(target_buf, line_0indexed, col_start, col_end, comment, selected_text)
      vim.notify(string.format("Attached [Ref %d] to %s:L%d", anchor.id, anchor.file_path, line_0indexed + 1),
                 vim.log.levels.INFO, { title = "Review Anchor" })
    end

    if vim.api.nvim_win_is_valid(cwin) then
      vim.api.nvim_win_close(cwin, true)
    end
  end

  local function cancel()
    if vim.api.nvim_win_is_valid(cwin) then
      vim.api.nvim_win_close(cwin, true)
    end
  end

  vim.keymap.set("n", "<CR>", save_comment, { buffer = cbuf, nowait = true })
  vim.keymap.set("n", "<C-s>", save_comment, { buffer = cbuf, nowait = true })
  vim.keymap.set("i", "<C-s>", function()
    vim.cmd("stopinsert")
    save_comment()
  end, { buffer = cbuf, nowait = true })
  vim.keymap.set("n", "<Esc>", cancel, { buffer = cbuf, nowait = true })
  vim.keymap.set("n", "q", cancel, { buffer = cbuf, nowait = true })
end

--- Capture a Claude Code Q&A item (conversational prompt snapshot).
function M.open_qa_capture()
  local cbuf, cwin = create_floating_window("Claude Code Q/A Capture", 0.75, 0.45)

  local template = {
    "# Claude Code Q/A Prompt Context",
    "# Format: • Question → Answer",
    "# (Unicode • and → are inserted by default; you can also type -> or Q: / A:)",
    "# Save with <C-s> or <CR> in normal mode | <Esc>/q to Cancel",
    "",
    "• Question → Answer",
  }

  vim.api.nvim_buf_set_lines(cbuf, 0, -1, false, template)
  vim.api.nvim_win_set_cursor(cwin, { 6, 2 })
  vim.cmd("startinsert!")

  local function save_qa()
    local lines = vim.api.nvim_buf_get_lines(cbuf, 0, -1, false)
    local q_lines = {}
    local a_lines = {}
    local in_q = false
    local in_a = false

    for _, line in ipairs(lines) do
      if not line:match("^#") then
        -- Match Unicode arrow (→) or ASCII (->)
        local q_arrow, a_arrow = line:match("^[%s•%-%*]*%s*(.-)%s*→%s*(.-)$")
        if not q_arrow then
          q_arrow, a_arrow = line:match("^[%s•%-%*]*%s*(.-)%s*%->%s*(.-)$")
        end

        if q_arrow and a_arrow and q_arrow ~= "" and a_arrow ~= "" and q_arrow ~= "Question" then
          q_lines = { q_arrow }
          a_lines = { a_arrow }
          break
        elseif line:match("^Q:%s*") then
          in_q = true
          in_a = false
          table.insert(q_lines, line:gsub("^Q:%s*", ""))
        elseif line:match("^A:%s*") then
          in_q = false
          in_a = true
          table.insert(a_lines, line:gsub("^A:%s*", ""))
        elseif in_q then
          table.insert(q_lines, line)
        elseif in_a then
          table.insert(a_lines, line)
        end
      end
    end

    local q = vim.trim(table.concat(q_lines, "\n"))
    local a = vim.trim(table.concat(a_lines, "\n"))

    if q == "" or a == "" then
      vim.notify("Both Question and Answer are required.", vim.log.levels.WARN, { title = "Review Anchor" })
    else
      anchors.add_qa(q, a)
      local preview_msg = string.format("Added Claude Q/A: • %s → %s", q, a)
      vim.notify(preview_msg, vim.log.levels.INFO, { title = "Review Anchor" })
    end

    if vim.api.nvim_win_is_valid(cwin) then
      vim.api.nvim_win_close(cwin, true)
    end
  end

  local function cancel()
    if vim.api.nvim_win_is_valid(cwin) then
      vim.api.nvim_win_close(cwin, true)
    end
  end

  vim.keymap.set("n", "<CR>", save_qa, { buffer = cbuf, nowait = true })
  vim.keymap.set("n", "<C-s>", save_qa, { buffer = cbuf, nowait = true })
  vim.keymap.set("i", "<C-s>", function()
    vim.cmd("stopinsert")
    save_qa()
  end, { buffer = cbuf, nowait = true })
  vim.keymap.set("n", "<Esc>", cancel, { buffer = cbuf, nowait = true })
  vim.keymap.set("n", "q", cancel, { buffer = cbuf, nowait = true })
end

--- Capture General Model Prompt instructions.
function M.open_prompt_capture()
  local inline = require("review_anchor.inline")
  local had_inline_open = inline.is_open()
  local current_prompt = ""

  if had_inline_open then
    current_prompt = inline.get_content_raw()
    inline.close_split_temporary()
  else
    current_prompt = anchors.get_prompt()
  end

  local cbuf, cwin = create_floating_window("Model Prompt / Instructions", 0.70, 0.45)

  local header = {
    "# Enter model prompt / instructions below. Save with <C-s> or <CR> in normal mode | <Esc>/q to Cancel",
    "",
  }

  local body = (current_prompt ~= "") and vim.split(current_prompt, "\n") or { "" }
  for _, l in ipairs(body) do
    table.insert(header, l)
  end

  vim.api.nvim_buf_set_lines(cbuf, 0, -1, false, header)
  vim.api.nvim_win_set_cursor(cwin, { #header, 0 })
  vim.cmd("startinsert")

  local function save_prompt()
    local all_lines = vim.api.nvim_buf_get_lines(cbuf, 0, -1, false)
    local prompt_lines = {}
    for i = 3, #all_lines do
      table.insert(prompt_lines, all_lines[i])
    end
    local prompt = vim.trim(table.concat(prompt_lines, "\n"))

    anchors.set_prompt(prompt)
    vim.notify("Updated model prompt instructions.", vim.log.levels.INFO, { title = "Review Anchor" })

    if vim.api.nvim_win_is_valid(cwin) then
      vim.api.nvim_win_close(cwin, true)
    end

    if had_inline_open then
      inline.open_inline_instructions(prompt)
    end
  end

  local function cancel()
    if vim.api.nvim_win_is_valid(cwin) then
      vim.api.nvim_win_close(cwin, true)
    end

    if had_inline_open then
      inline.open_inline_instructions(current_prompt)
    end
  end

  vim.keymap.set("n", "<CR>", save_prompt, { buffer = cbuf, nowait = true })
  vim.keymap.set("n", "<C-s>", save_prompt, { buffer = cbuf, nowait = true })
  vim.keymap.set("i", "<C-s>", function()
    vim.cmd("stopinsert")
    save_prompt()
  end, { buffer = cbuf, nowait = true })
  vim.keymap.set("n", "<Esc>", cancel, { buffer = cbuf, nowait = true })
  vim.keymap.set("n", "q", cancel, { buffer = cbuf, nowait = true })
end

--- Preview formatted Commit Message and Git Notes side-by-side or stacked in a floating window.
function M.open_preview_window()
  local pbuf, pwin = create_floating_window("Commit & Git Notes Preview", 0.85, 0.75)

  local function render()
    local commit_msg = git.format_commit_message()
    local notes_msg = git.format_git_notes()
    local blank_tag = config.options.is_blank and " [blank: ON]" or " [blank: OFF]"

    local content = {
      "================================================================================",
      "  GIT COMMIT MESSAGE (Model Input Snapshot)" .. blank_tag,
      "================================================================================",
    }

    for _, l in ipairs(vim.split(commit_msg, "\n")) do
      table.insert(content, l)
    end

    table.insert(content, "")
    table.insert(content, "================================================================================")
    table.insert(content, "  GIT NOTES (refs/notes/commits - diff -p Context Anchors)")
    table.insert(content, "================================================================================")

    for _, l in ipairs(vim.split(notes_msg, "\n")) do
      table.insert(content, l)
    end

    table.insert(content, "")
    table.insert(content, "--------------------------------------------------------------------------------")
    table.insert(content, " Actions: [y] Copy Commit  [n] Copy Git Notes  [b] Toggle [blank]  [C] Commit  [q] Close")
    table.insert(content, "--------------------------------------------------------------------------------")

    vim.bo[pbuf].modifiable = true
    vim.api.nvim_buf_set_lines(pbuf, 0, -1, false, content)
    vim.bo[pbuf].modifiable = false
  end

  render()

  local function close()
    if vim.api.nvim_win_is_valid(pwin) then
      vim.api.nvim_win_close(pwin, true)
    end
  end

  vim.keymap.set("n", "q", close, { buffer = pbuf, nowait = true })
  vim.keymap.set("n", "<Esc>", close, { buffer = pbuf, nowait = true })
  vim.keymap.set("n", "y", function()
    git.copy_commit_message()
  end, { buffer = pbuf, nowait = true })
  vim.keymap.set("n", "n", function()
    git.copy_git_notes()
  end, { buffer = pbuf, nowait = true })
  vim.keymap.set("n", "b", function()
    config.options.is_blank = not config.options.is_blank
    render()
    local status = config.options.is_blank and "ENABLED ([blank] prepended)" or "DISABLED"
    vim.notify("New conversation toggle: " .. status, vim.log.levels.INFO, { title = "Review Anchor" })
  end, { buffer = pbuf, nowait = true })
  vim.keymap.set("n", "C", function()
    git.execute_commit(function(ok, _)
      if ok then close() end
    end)
  end, { buffer = pbuf, nowait = true })
end

return M
