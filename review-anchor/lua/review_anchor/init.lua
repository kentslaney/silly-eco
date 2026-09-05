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
    "    <leader>ri    Open inline instructions split (save :wq to commit, cancel :q!)",
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
    "    <leader>rM    Commit changes with just model name",
    "    <leader>rm    Configure AI model name (default: gemini 3.8 flash high)",
    "    <leader>rb    Toggle [blank] new conversation prefix",
    "    <leader>rt    Toggle commit mode (detailed snapshot <-> model-only)",
    "    <leader>r?    Show this help cheatsheet",
  }
  vim.notify(table.concat(help_lines, "\n"), vim.log.levels.INFO, { title = "Review Anchor" })
end

--- Toggle prepending '[blank] ' to model name (denoting a new conversation).
function M.toggle_blank()
  config.options.is_blank = not config.options.is_blank
  local status = config.options.is_blank and "ENABLED ([blank] prepended)" or "DISABLED"
  vim.notify(string.format("New conversation toggle: %s\nSubject: %s", status, config.get_model_name()),
             vim.log.levels.INFO, { title = "Review Anchor" })
end

--- Change model name interactively.
function M.prompt_model_name()
  local current_base = (config.options.model_name or ""):gsub("^%[blank%]%s*", "")
  vim.ui.input({
    prompt = "Enter Model Name: ",
    default = current_base,
  }, function(input)
    if input and vim.trim(input) ~= "" then
      local clean = vim.trim(input)
      if clean:match("^%[blank%]%s*") then
        config.options.is_blank = true
        clean = clean:gsub("^%[blank%]%s*", "")
      end
      config.options.model_name = clean
      vim.notify("Model set to: " .. config.get_model_name(), vim.log.levels.INFO, { title = "Review Anchor" })
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

  -- Ensure soft-wrapping is enabled for editor window(s) displaying this buffer
  local wins = vim.fn.win_findbuf(bufnr)
  for _, win in ipairs(wins) do
    pcall(function()
      vim.api.nvim_set_option_value("wrap", true, { win = win })
      vim.api.nvim_set_option_value("linebreak", true, { win = win })
      vim.api.nvim_set_option_value("breakindent", true, { win = win })
    end)
  end
  pcall(function()
    vim.wo.wrap = true
    vim.wo.linebreak = true
    vim.wo.breakindent = true
  end)

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

  -- Normal mode comment capture (strictly <leader>r prefix)
  local open_normal_comment = function()
    local cursor = vim.api.nvim_win_get_cursor(0)
    local line_0idx = cursor[1] - 1
    local line_text = vim.api.nvim_get_current_line()
    capture.open_comment_capture(bufnr, line_0idx, 0, #line_text, vim.trim(line_text))
  end
  map("n", "<leader>rc", open_normal_comment, "Add review comment")

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

  -- Inline instructions split
  map("n", "<leader>ri", function()
    local inline = require("review_anchor.inline")
    local ibuf, _ = inline.open_inline_instructions()
    if ibuf and ibuf > 0 then
      M.attach_buffer(ibuf)
    end
  end, "Open inline instructions split")

  -- Claude Q/A and prompt capture
  map("n", "<leader>rq", capture.open_qa_capture, "Add Claude Q/A")
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
  map("n", "<leader>rM", function() git.commit_model_only() end, "Commit changes with just model name")
  map("n", "<leader>rm", M.prompt_model_name, "Set model name")
  map("n", "<leader>rb", M.toggle_blank, "Toggle [blank] new conversation prefix")
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

--- Initialize uninitialized git repository matching GitHub behavior.
--- Prompts for remote source URL and license, runs git init, creates initial commit,
--- creates blank .gitignore, and opens git log and inline instruction splits.
---@param opts? table
---@param on_complete? fun()
function M.init_repo(opts, on_complete)
  local license_mod = require("review_anchor.license")
  opts = opts or {}

  local function do_init(remote_url, lic_key)
    vim.fn.system("git init -b main 2>/dev/null || git init")
    if remote_url and vim.trim(remote_url) ~= "" then
      vim.fn.system("git remote add origin " .. vim.fn.shellescape(vim.trim(remote_url)))
    end

    if lic_key and lic_key ~= "None" and license_mod.LICENSES[lic_key] then
      license_mod.write_license(lic_key, "LICENSE")
      vim.fn.system("git add LICENSE")
      vim.fn.system("git commit -m 'Initial commit'")
    else
      vim.fn.system("git commit --allow-empty -m 'Initial commit'")
    end

    -- Add blank .gitignore ready for the first prompt commit
    local gf = io.open(".gitignore", "a")
    if gf then gf:close() end
    vim.fn.system("git add .gitignore")

    config.options.omit_model_header = true

    if on_complete then
      on_complete()
    else
      M.start("", { first_prompt_no_model = true })
    end
  end

  if opts.headless or vim.fn.has("gui_running") == 0 and not vim.api.nvim_get_mode().mode:match("[ni]") then
    -- Headless default
    do_init(opts.remote_url or "", opts.license or "CC0-1.0")
    return
  end

  vim.ui.input({ prompt = "Enter remote repository URL (leave blank to skip): " }, function(remote_url)
    local license_items = { "CC0-1.0", "MIT", "GPL-3.0", "Apache-2.0", "BSD-3-Clause", "Unlicense", "None" }
    vim.ui.select(license_items, {
      prompt = "Select license for initial commit (matching GitHub):",
      format_item = function(item)
        local l = license_mod.LICENSES[item]
        return l and string.format("%s (%s)", item, l.name) or item
      end,
    }, function(choice)
      do_init(remote_url, choice or "CC0-1.0")
    end)
  end)
end

--- Start review session on target file or default to inline instructions above git log.
---@param filepath? string
---@param opts? table
function M.start(filepath, opts)
  M.setup(opts)
  opts = opts or {}

  if opts.first_prompt_no_model or opts.omit_model_header then
    config.options.omit_model_header = true
  end

  -- Check if repo is initialized
  local is_git = vim.fn.system("git rev-parse --is-inside-work-tree 2>/dev/null"):gsub("%s+$", "") == "true"
  if not is_git then
    M.init_repo(opts)
    return
  end

  -- Case A: Implementation plan file provided
  if filepath and filepath ~= "" and (vim.fn.filereadable(filepath) == 1 or filepath:match("%.md$")) then
    vim.cmd("edit " .. vim.fn.fnameescape(filepath))

    local main_buf = vim.api.nvim_get_current_buf()
    local main_win = vim.api.nvim_get_current_win()

    M.attach_buffer(main_buf)
    splits.open_git_log(main_win)

    if vim.api.nvim_win_is_valid(main_win) then
      pcall(function()
        vim.api.nvim_set_option_value("wrap", true, { win = main_win })
        vim.api.nvim_set_option_value("linebreak", true, { win = main_win })
        vim.api.nvim_set_option_value("breakindent", true, { win = main_win })
      end)
      vim.api.nvim_set_current_win(main_win)
    end
  else
    -- Case B: Run without an implementation plan file provided
    -- Default to just the inline instruction split above the git log (reusing top window so no blank split)
    local top_win = vim.api.nvim_get_current_win()
    splits.open_git_log(top_win)

    local inline = require("review_anchor.inline")
    local ibuf, iwin = inline.open_inline_instructions(nil, top_win)
    if ibuf and ibuf > 0 then
      M.attach_buffer(ibuf)
    end
    if iwin and vim.api.nvim_win_is_valid(iwin) then
      vim.api.nvim_set_current_win(iwin)
    end
  end

  vim.notify("Review Anchor attached. Press <leader>r? for help.", vim.log.levels.INFO, { title = "Review Anchor" })
end

return M
