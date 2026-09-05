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
  local model = config.get_model_name()
  local omit_model = config.options.omit_model_header

  if omit_model then
    local prompt = anchors_mod.get_prompt()
    if prompt ~= "" then
      return prompt
    else
      return "Initial instructions"
    end
  end

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
      table.insert(lines, string.format("• %s → %s", q_text, a_text))
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

    -- RFC 822 Review Trailers (only added when there are comments)
    local reviewer_name, reviewer_email = config.get_reviewer()
    local timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ")

    table.insert(lines, "Review-Doc: " .. primary_doc)
    table.insert(lines, "Review-Anchor: " .. M.slugify(primary_section))
    table.insert(lines, string.format("Reviewed-By: %s <%s>", reviewer_name, reviewer_email))
    table.insert(lines, "Review-Status: " .. config.options.review_status)
    table.insert(lines, "Reviewed-At: " .. timestamp)
  end

  while #lines > 0 and lines[#lines] == "" do
    table.remove(lines)
  end

  return table.concat(lines, "\n")
end

--- Format Git Notes diff -p payload.
---@return string
function M.format_git_notes()
  local all_anchors = anchors_mod.get_all_anchors()

  if #all_anchors == 0 then
    return ""
  end

  local lines = { "Review Anchors (diff -p context):", "" }

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

--- Commit changes with just the model name.
---@param on_complete? fun(success: boolean, message: string)
function M.commit_model_only(on_complete)
  -- Save all open modified buffers
  vim.cmd("silent! wall")

  -- Stage all changes before committing
  local add_output = vim.fn.system("git add -A 2>&1")
  local add_exit = vim.v.shell_error
  if add_exit ~= 0 then
    vim.notify("Git add failed:\n" .. add_output, vim.log.levels.ERROR, { title = "Review Anchor" })
    if on_complete then on_complete(false, add_output) end
    return
  end

  local model = config.get_model_name()
  local commit_file = vim.fn.tempname()
  local f = io.open(commit_file, "w")
  if not f then
    vim.notify("Failed to write temporary commit file", vim.log.levels.ERROR)
    if on_complete then on_complete(false, "Failed to write temp commit file") end
    return
  end
  f:write(model .. "\n")
  f:close()

  local cmd_commit = string.format("git commit -F %s 2>&1", vim.fn.shellescape(commit_file))
  local commit_output = vim.fn.system(cmd_commit)
  local commit_exit = vim.v.shell_error
  os.remove(commit_file)

  if commit_exit ~= 0 then
    vim.notify("Git commit failed:\n" .. commit_output, vim.log.levels.ERROR, { title = "Review Anchor" })
    if on_complete then on_complete(false, commit_output) end
    return
  end

  local msg = "Committed changes with model name: " .. model
  vim.notify(msg, vim.log.levels.INFO, { title = "Review Anchor" })
  pcall(function()
    require("review_anchor.splits").refresh_git_log()
  end)
  if on_complete then on_complete(true, msg) end
end

--- Execute git commit and attach Git Notes.
--- If instructions or review is committed without changes and HEAD is the current model name,
--- uses git's amend to add the instructions instead of making a new commit.
---@param on_complete? fun(success: boolean, message: string)
function M.execute_commit(on_complete)
  -- Save all open modified buffers
  vim.cmd("silent! wall")

  -- Stage all changes before committing
  local add_output = vim.fn.system("git add -A 2>&1")
  local add_exit = vim.v.shell_error
  if add_exit ~= 0 then
    vim.notify("Git add failed:\n" .. add_output, vim.log.levels.ERROR, { title = "Review Anchor" })
    if on_complete then on_complete(false, add_output) end
    return
  end

  -- Check if there are changes to commit in the working tree
  local status_after = vim.fn.system("git status --porcelain 2>/dev/null"):gsub("%s+$", "")
  local has_changes_to_commit = (status_after ~= "")

  -- Check if HEAD's subject or body is the current model name
  local head_subject = vim.fn.system("git log -1 --pretty=format:%s 2>/dev/null"):gsub("%s+$", "")
  local head_body = vim.fn.system("git log -1 --pretty=format:%B 2>/dev/null"):gsub("%s+$", "")
  local current_model = config.get_model_name()
  local clean_model = config.options.model_name:gsub("^%[blank%]%s*", "")

  local head_is_model = (
    head_subject == current_model or
    head_subject == clean_model or
    head_subject == "[blank] " .. clean_model or
    head_body == current_model or
    head_body == clean_model or
    head_body == "[blank] " .. clean_model
  )

  local should_amend = (not has_changes_to_commit) and head_is_model

  local commit_msg = M.format_commit_message()
  local notes_msg = M.format_git_notes()
  local all_anchors = anchors_mod.get_all_anchors()
  local has_comments = (#all_anchors > 0)

  -- Write temporary commit message file
  local commit_file = vim.fn.tempname()
  local f = io.open(commit_file, "w")
  if not f then
    vim.notify("Failed to write temporary commit file", vim.log.levels.ERROR)
    if on_complete then on_complete(false, "Failed to write temp commit file") end
    return
  end
  f:write(commit_msg .. "\n")
  f:close()

  -- Commit (or Amend if no file changes and HEAD is the model name)
  local cmd_commit = ""
  if should_amend then
    cmd_commit = string.format("git commit --amend -F %s 2>&1", vim.fn.shellescape(commit_file))
  else
    cmd_commit = string.format("git commit -F %s 2>&1", vim.fn.shellescape(commit_file))
  end

  local commit_output = vim.fn.system(cmd_commit)
  local commit_exit = vim.v.shell_error
  os.remove(commit_file)

  if commit_exit ~= 0 then
    vim.notify("Git commit failed:\n" .. commit_output, vim.log.levels.ERROR, { title = "Review Anchor" })
    if on_complete then on_complete(false, commit_output) end
    return
  end

  -- Only attach Git Notes if there are review comments
  if has_comments and notes_msg ~= "" then
    local notes_file = vim.fn.tempname()
    local nf = io.open(notes_file, "w")
    if nf then
      nf:write(notes_msg .. "\n")
      nf:close()
      local cmd_notes = string.format("git notes add -f -F %s HEAD 2>&1", vim.fn.shellescape(notes_file))
      local notes_output = vim.fn.system(cmd_notes)
      local notes_exit = vim.v.shell_error
      os.remove(notes_file)
      if notes_exit ~= 0 then
        vim.notify("Commit succeeded, but git notes failed:\n" .. notes_output, vim.log.levels.WARN, { title = "Review Anchor" })
      end
    end
  end

  local action_str = should_amend and "amended into HEAD" or "created"
  local notes_str = has_comments and " & Git Notes attached" or ""
  local success_msg = string.format("Git commit %s%s to HEAD!", action_str, notes_str)

  vim.notify(success_msg, vim.log.levels.INFO, { title = "Review Anchor" })
  config.options.omit_model_header = false
  pcall(function()
    require("review_anchor.splits").refresh_git_log()
  end)
  if on_complete then on_complete(true, success_msg) end
end

return M
