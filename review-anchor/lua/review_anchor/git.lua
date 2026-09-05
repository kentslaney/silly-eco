local config = require("review_anchor.config")
local anchors_mod = require("review_anchor.anchors")

local M = {}

--- Slugify text for RFC 822 Review-Anchor header.
---@param text string
---@return string
function M.slugify(text)
  if not text or text == "" then
    return "root"
  end
  local slug = text:lower()
  slug = slug:gsub("[^%w%s-]", "")
  slug = slug:gsub("%s+", "-")
  slug = slug:gsub("^%-+", ""):gsub("%-+$", "")
  return "#" .. (slug ~= "" and slug or "root")
end

--- Format full Git commit message snapshot.
---@return string
function M.format_commit_message()
  local mode = config.options.commit_mode
  local model = config.options.model_name

  if mode == "model_only" then
    return model
  end

  local lines = { model, "" }

  local prompt = anchors_mod.get_prompt()
  if prompt ~= "" then
    table.insert(lines, prompt)
    table.insert(lines, "")
  end

  local qa_items = anchors_mod.get_all_qa()
  if #qa_items > 0 then
    table.insert(lines, "Claude Code Q/A Context:")
    for _, qa in ipairs(qa_items) do
      local q_text = vim.trim(qa.question:gsub("\n+", " "))
      local a_text = vim.trim(qa.answer:gsub("\n+", " "))
      table.insert(lines, string.format("- [Ref %d] %s -> %s", qa.id, q_text, a_text))
    end
    table.insert(lines, "")
  end

  local all_anchors = anchors_mod.get_all_anchors()
  local primary_doc = "implementation_plan.md"
  local primary_section = "root"

  if #all_anchors > 0 then
    primary_doc = all_anchors[1].file_path
    primary_section = all_anchors[1].section_name

    table.insert(lines, string.format("Reviewed %s:", primary_doc))
    table.insert(lines, "")

    for _, a in ipairs(all_anchors) do
      table.insert(lines, string.format('[Ref %d] Review on "%s":', a.id, a.section_name))
      if a.selected_text and a.selected_text ~= "" then
        table.insert(lines, string.format('> "%s"', a.selected_text))
      end
      table.insert(lines, "Review: " .. a.comment)
      table.insert(lines, "")
    end
  end

  -- RFC 822 Review Trailers
  local reviewer_name, reviewer_email = config.get_reviewer()
  local timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ")

  table.insert(lines, "Review-Doc: " .. primary_doc)
  table.insert(lines, "Review-Anchor: " .. M.slugify(primary_section))
  table.insert(lines, string.format("Reviewed-By: %s <%s>", reviewer_name, reviewer_email))
  table.insert(lines, "Review-Status: " .. config.options.review_status)
  table.insert(lines, "Reviewed-At: " .. timestamp)

  return table.concat(lines, "\n")
end

--- Format Git Notes diff -p payload.
---@return string
function M.format_git_notes()
  local all_anchors = anchors_mod.get_all_anchors()
  local qa_items = anchors_mod.get_all_qa()

  local lines = { "Review Anchors (diff -p context):", "" }

  for _, qa in ipairs(qa_items) do
    local q_text = vim.trim(qa.question:gsub("\n+", " "))
    local a_text = vim.trim(qa.answer:gsub("\n+", " "))
    table.insert(lines, string.format("[Ref %d] %s (Claude Q/A)", qa.id, qa.file_path))
    table.insert(lines, "Context: " .. qa.diff_context)
    table.insert(lines, string.format("- %s -> %s", q_text, a_text))
    table.insert(lines, "")
  end

  for _, a in ipairs(all_anchors) do
    local line_num = a.line_0indexed + 1
    table.insert(lines, string.format("[Ref %d] %s:L%d", a.id, a.file_path, line_num))
    table.insert(lines, "Context: " .. a.diff_context)
    table.insert(lines, "Hunk:")
    for _, hunk_line in ipairs(a.hunk or {}) do
      table.insert(lines, "  " .. hunk_line)
    end
    table.insert(lines, "")
  end

  return table.concat(lines, "\n")
end

--- Copy string to system clipboard (+ register and pbcopy fallback).
---@param text string
---@param label string
function M.copy_to_clipboard(text, label)
  vim.fn.setreg("+", text)
  vim.fn.setreg("*", text)

  -- macOS pbcopy fallback if setreg didn't propagate to system clipboard
  if vim.fn.has("mac") == 1 or vim.fn.executable("pbcopy") == 1 then
    local p = io.popen("pbcopy", "w")
    if p then
      p:write(text)
      p:close()
    end
  end

  vim.notify(label .. " copied to clipboard!", vim.log.levels.INFO, { title = "Review Anchor" })
end

--- Copy commit message to clipboard.
function M.copy_commit_message()
  local msg = M.format_commit_message()
  M.copy_to_clipboard(msg, "Commit message")
end

--- Copy Git Notes payload to clipboard.
function M.copy_git_notes()
  local notes = M.format_git_notes()
  M.copy_to_clipboard(notes, "Git Notes")
end

--- Execute git commit and attach Git Notes.
---@param on_complete? fun(success: boolean, message: string)
function M.execute_commit(on_complete)
  local commit_msg = M.format_commit_message()
  local notes_msg = M.format_git_notes()

  -- Write temporary commit message file
  local commit_file = vim.fn.tempname()
  local f = io.open(commit_file, "w")
  if not f then
    vim.notify("Failed to write temporary commit file", vim.log.levels.ERROR)
    if on_complete then on_complete(false, "Failed to write temp commit file") end
    return
  end
  f:write(commit_msg)
  f:close()

  local notes_file = vim.fn.tempname()
  local nf = io.open(notes_file, "w")
  if not nf then
    vim.notify("Failed to write temporary notes file", vim.log.levels.ERROR)
    if on_complete then on_complete(false, "Failed to write temp notes file") end
    return
  end
  nf:write(notes_msg)
  nf:close()

  -- Commit
  local cmd_commit = string.format("git commit -F %s 2>&1", vim.fn.shellescape(commit_file))
  local commit_output = vim.fn.system(cmd_commit)
  local commit_exit = vim.v.shell_error

  os.remove(commit_file)

  if commit_exit ~= 0 then
    os.remove(notes_file)
    vim.notify("Git commit failed:\n" .. commit_output, vim.log.levels.ERROR, { title = "Review Anchor" })
    if on_complete then on_complete(false, commit_output) end
    return
  end

  -- Add Git Notes
  local cmd_notes = string.format("git notes add -f -F %s HEAD 2>&1", vim.fn.shellescape(notes_file))
  local notes_output = vim.fn.system(cmd_notes)
  local notes_exit = vim.v.shell_error

  os.remove(notes_file)

  if notes_exit ~= 0 then
    vim.notify("Commit succeeded, but git notes failed:\n" .. notes_output, vim.log.levels.WARN, { title = "Review Anchor" })
    if on_complete then on_complete(false, notes_output) end
    return
  end

  local success_msg = "Git commit created & Git Notes attached to HEAD!"
  vim.notify(success_msg, vim.log.levels.INFO, { title = "Review Anchor" })
  if on_complete then on_complete(true, success_msg) end
end

return M
