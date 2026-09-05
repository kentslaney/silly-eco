local config = require("review_anchor.config")
local outline = require("review_anchor.outline")
local anchors = require("review_anchor.anchors")
local capture = require("review_anchor.capture")
local diff_p = require("review_anchor.diff_p")
local git = require("review_anchor.git")
local splits = require("review_anchor.splits")

local M = {}

--- Show keybinding cheatsheet.
function M.show_help()
  local help_lines = {
    "Review Anchor Keybindings (Org-mode & Review layer):",
    "",
    "  Outline & Navigation:",
    "    <Tab>         Cycle fold (current heading: folded -> children -> subtree)",
    "    <S-Tab>       Cycle global fold (all folded -> H1 -> H2 -> open all)",
    "    ]] / [[       Jump to next / previous section heading",
    "    <leader>rx    Toggle markdown checkbox item (- [ ] <-> - [x])",
    "",
    "  Review & Anchoring:",
    "    <leader>rc    Add review comment on current line (Normal) or selection (Visual)",
    "    <leader>c     Shorthand for comment capture",
    "    <leader>rq    Add Claude Code Q/A item (prompt snapshot)",
    "    <leader>rp    Set general model prompt / instruction notes",
    "    <leader>rd    Delete review anchor under cursor",
    "    <leader>re    Edit comment on current anchor",
    "",
    "  Git & Splits:",
    "    <leader>rg    Toggle 'git log --graph --all' split below",
    "    <leader>rP    Preview formatted Commit Message & Git Notes",
    "    <leader>ry    Copy formatted Commit Message to clipboard",
    "    <leader>rn    Copy Git Notes payload to clipboard",
    "    <leader>rC    Execute Git Commit and attach Git Notes to HEAD",
    "    <leader>rm    Configure AI model name (default: gemini 3.8 flash high)",
    "    <leader>rt    Toggle commit mode (detailed snapshot <-> model-only)",
    "    <leader>r?    Show this help cheatsheet",
  }
  vim.notify(table.concat(help_lines, "\n"), vim.log.levels.INFO, { title = "Review Anchor" })
end

--- Change model name interactively.
function M.prompt_model_name()
  vim.ui.input({
    prompt = "Enter Model Name: ",
    default = config.options.model_name,
  }, function(input)
    if input and vim.trim(input) ~= "" then
      config.options.model_name = vim.trim(input)
      vim.notify("Model set to: " .. config.options.model_name, vim.log.levels.INFO, { title = "Review Anchor" })
    end
  end)
end

--- Toggle commit mode (detailed vs model_only).
function M.toggle_commit_mode()
  if config.options.commit_mode == "detailed" then
    config.options.commit_mode = "model_only"
  else
    config.options.commit_mode = "detailed"
  end
  vim.notify("Commit mode set to: " .. config.options.commit_mode, vim.log.levels.INFO, { title = "Review Anchor" })
end

--- Attach review-anchor layer and keybindings to buffer.
---@param bufnr integer
function M.attach_buffer(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  outline.setup_buffer(bufnr)

  local map = function(mode, lhs, rhs, desc)
    vim.keymap.set(mode, lhs, rhs, { buffer = bufnr, silent = true, desc = "ReviewAnchor: " .. desc })
  end

  -- Outline motions & folding
  map("n", "<Tab>", outline.cycle_fold, "Cycle fold")
  map("n", "<S-Tab>", outline.cycle_global_fold, "Cycle global fold")
  map("n", "]]", outline.jump_next_heading, "Next heading")
  map("n", "[[", outline.jump_prev_heading, "Prev heading")
  map("n", "<leader>rx", outline.toggle_checkbox, "Toggle checkbox")
  map("n", "<C-c><C-c>", outline.toggle_checkbox, "Toggle checkbox")

  -- Normal mode comment capture
  local open_normal_comment = function()
    local cursor = vim.api.nvim_win_get_cursor(0)
    local line_0idx = cursor[1] - 1
    local line_text = vim.api.nvim_get_current_line()
    capture.open_comment_capture(bufnr, line_0idx, 0, #line_text, vim.trim(line_text))
  end
  map("n", "<leader>rc", open_normal_comment, "Add review comment")
  map("n", "<leader>c", open_normal_comment, "Add review comment")

  -- Visual mode comment capture (anchored to visual selection)
  local open_visual_comment = function()
    -- Get visual selection range
    vim.cmd('normal! "vy')
    local selected_text = vim.fn.getreg("v")
    local s_pos = vim.fn.getpos("'<")
    local e_pos = vim.fn.getpos("'>")
    local line_0idx = math.max(0, s_pos[2] - 1)
    local col_s = math.max(0, s_pos[3] - 1)
    local col_e = math.max(0, e_pos[3] - 1)

    capture.open_comment_capture(bufnr, line_0idx, col_s, col_e, vim.trim(selected_text))
  end
  map("v", "<leader>rc", open_visual_comment, "Add review comment to selection")
  map("v", "<leader>c", open_visual_comment, "Add review comment to selection")

  -- Claude Q/A and prompt capture
  map("n", "<leader>rq", function() capture.open_qa_capture(bufnr) end, "Add Claude Q/A")
  map("n", "<leader>rp", capture.open_prompt_capture, "Edit model prompt instructions")

  -- Anchor management
  map("n", "<leader>rd", function()
    local ok, id = anchors.delete_anchor_at_cursor(bufnr)
    if ok then
      vim.notify(string.format("Deleted [Ref %d]", id), vim.log.levels.INFO, { title = "Review Anchor" })
    else
      vim.notify("No anchor found on this line.", vim.log.levels.WARN, { title = "Review Anchor" })
    end
  end, "Delete anchor under cursor")

  map("n", "<leader>re", function()
    local a, _ = anchors.get_anchor_at_cursor(bufnr)
    if a then
      capture.open_comment_capture(bufnr, a.line_0indexed, a.col_start, a.col_end, a.selected_text)
    else
      open_normal_comment()
    end
  end, "Edit anchor comment")

  -- Git split & actions
  map("n", "<leader>rg", function() splits.toggle_git_log(vim.api.nvim_get_current_win()) end, "Toggle git log split")
  map("n", "<leader>rP", capture.open_preview_window, "Preview commit message and notes")
  map("n", "<leader>ry", git.copy_commit_message, "Copy commit message to clipboard")
  map("n", "<leader>rn", git.copy_git_notes, "Copy Git Notes to clipboard")
  map("n", "<leader>rC", function() git.execute_commit() end, "Execute commit & notes")
  map("n", "<leader>rm", M.prompt_model_name, "Set model name")
  map("n", "<leader>rt", M.toggle_commit_mode, "Toggle commit mode")
  map("n", "<leader>r?", M.show_help, "Show help cheatsheet")
  map("n", "<leader>rh", M.show_help, "Show help cheatsheet")
end

--- Setup review-anchor plugin.
---@param opts? table
function M.setup(opts)
  config.setup(opts)
  config.setup_highlights()
end

--- Start review session on target file.
--- Opens target file in upper window and git log --graph --all in bottom split.
---@param filepath? string
function M.start(filepath)
  M.setup()

  if filepath and filepath ~= "" and vim.fn.filereadable(filepath) == 1 then
    vim.cmd("edit " .. vim.fn.fnameescape(filepath))
  elseif filepath and filepath ~= "" then
    vim.cmd("edit " .. vim.fn.fnameescape(filepath))
  end

  local main_buf = vim.api.nvim_get_current_buf()
  local main_win = vim.api.nvim_get_current_win()

  -- Attach review-anchor layer
  M.attach_buffer(main_buf)

  -- Open git log --graph --all in split below
  splits.open_git_log(main_win)

  -- Ensure focus returns to main buffer window
  if vim.api.nvim_win_is_valid(main_win) then
    vim.api.nvim_set_current_win(main_win)
  end

  vim.notify("Review Anchor attached. Press <leader>r? for help.", vim.log.levels.INFO, { title = "Review Anchor" })
end

return M
