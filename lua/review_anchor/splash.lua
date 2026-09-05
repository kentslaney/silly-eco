local config = require("review_anchor.config")
local license_mod = require("review_anchor.license")

local M = {}

M.active_buf = nil
M.active_win = nil

local LICENSE_OPTIONS = {
  { key = "CC0-1.0", name = "CC0 1.0 Universal (Public Domain)" },
  { key = "MIT", name = "MIT License" },
  { key = "GPL-3.0", name = "GNU General Public License v3.0" },
  { key = "Apache-2.0", name = "Apache License 2.0" },
  { key = "BSD-3-Clause", name = "BSD 3-Clause License" },
  { key = "Unlicense", name = "The Unlicense" },
  { key = "None", name = "None (No license file)" },
}

--- Check git repository details for a given directory.
---@param cwd string
---@return table
local function inspect_directory(cwd)
  local is_git = vim.fn.system(string.format("git -C %s rev-parse --is-inside-work-tree 2>/dev/null", vim.fn.shellescape(cwd))):gsub("%s+$", "") == "true"
  local branch = ""
  local remote_url = ""
  local has_license = false

  if is_git then
    branch = vim.fn.system(string.format("git -C %s branch --show-current 2>/dev/null", vim.fn.shellescape(cwd))):gsub("%s+$", "")
    if branch == "" then branch = "HEAD" end
    local remote_out = vim.fn.system(string.format("git -C %s remote get-url origin 2>/dev/null", vim.fn.shellescape(cwd))):gsub("%s+$", "")
    if not remote_out:match("fatal:") then
      remote_url = remote_out
    end
  end

  local lic_candidates = { "LICENSE", "LICENSE.txt", "LICENSE.md", "UNLICENSE" }
  for _, f in ipairs(lic_candidates) do
    if vim.fn.filereadable(cwd .. "/" .. f) == 1 then
      has_license = true
      break
    end
  end

  return {
    is_git = is_git,
    branch = branch,
    remote_url = remote_url,
    has_license = has_license,
  }
end

--- Render splash screen contents into buffer.
---@param bufnr integer
---@param state table
local function render_splash(bufnr, state)
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then return end

  local lines = {
    "╭────────────────────────────────────────────────────────────────────╮",
    "│   Review Anchor — Repository Setup & Initialization                │",
    "╰────────────────────────────────────────────────────────────────────╯",
    "",
    string.format("  Target Directory:  %s", state.cwd),
  }

  if state.info.is_git then
    table.insert(lines, string.format("  Git Status:        ● Initialized (branch: %s)", state.info.branch))
  else
    table.insert(lines, "  Git Status:        ○ Not a Git repository (uninitialized)")
  end

  local remote_display = (state.remote_url ~= "") and state.remote_url or "(none configured)"
  table.insert(lines, string.format("  Remote URL:        %s", remote_display))
  table.insert(lines, string.format("  Selected License:  %s", state.license_key))
  table.insert(lines, "")
  table.insert(lines, "  License Options:")

  for i, lic in ipairs(LICENSE_OPTIONS) do
    local marker = (lic.key == state.license_key) and "(*)" or "( )"
    table.insert(lines, string.format("    [%d] %s %s", i, marker, lic.name))
  end

  table.insert(lines, "")
  table.insert(lines, "  Actions:")
  table.insert(lines, "    [r]       Set / Edit Remote Repository URL")
  table.insert(lines, "    [1-7]     Select License")
  table.insert(lines, "    [<CR>/i]  Initialize Repository (git init, license commit, .gitignore)")
  table.insert(lines, "    [q/<Esc>] Close / Cancel")

  vim.bo[bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.bo[bufnr].modifiable = false
end

--- Execute the repository initialization.
---@param state table
---@param on_complete? fun(ok: boolean)
local function execute_init(state, on_complete)
  local cwd = state.cwd
  local lic_key = state.license_key
  local remote_url = state.remote_url

  -- 1. git init
  vim.fn.system(string.format("git -C %s init -b main 2>/dev/null || git -C %s init", vim.fn.shellescape(cwd), vim.fn.shellescape(cwd)))

  -- 2. remote origin
  if remote_url and vim.trim(remote_url) ~= "" then
    local trimmed = vim.trim(remote_url)
    vim.fn.system(string.format("git -C %s remote remove origin 2>/dev/null", vim.fn.shellescape(cwd)))
    vim.fn.system(string.format("git -C %s remote add origin %s", vim.fn.shellescape(cwd), vim.fn.shellescape(trimmed)))
  end

  -- 3. license commit if needed
  if lic_key and lic_key ~= "None" and license_mod.LICENSES[lic_key] then
    local lic_path = cwd .. "/LICENSE"
    license_mod.write_license(lic_key, lic_path)
    vim.fn.system(string.format("git -C %s add %s", vim.fn.shellescape(cwd), vim.fn.shellescape(lic_path)))
    vim.fn.system(string.format("git -C %s commit -m 'Initial commit'", vim.fn.shellescape(cwd)))
  else
    -- Check if any commits exist
    local has_commits = vim.fn.system(string.format("git -C %s rev-parse --verify HEAD 2>/dev/null", vim.fn.shellescape(cwd))):gsub("%s+$", "") ~= ""
    if not has_commits then
      vim.fn.system(string.format("git -C %s commit --allow-empty -m 'Initial commit'", vim.fn.shellescape(cwd)))
    end
  end

  -- 4. Blank .gitignore
  local gitignore_path = cwd .. "/.gitignore"
  if vim.fn.filereadable(gitignore_path) == 0 then
    local gf = io.open(gitignore_path, "w")
    if gf then gf:close() end
  end
  vim.fn.system(string.format("git -C %s add %s", vim.fn.shellescape(cwd), vim.fn.shellescape(gitignore_path)))

  config.options.omit_model_header = true

  vim.notify("Repository initialized successfully in " .. cwd, vim.log.levels.INFO, { title = "Review Anchor" })

  if on_complete then
    on_complete(true)
  else
    pcall(function()
      require("review_anchor").start("", { first_prompt_no_model = true })
    end)
  end
end

--- Open the interactive repository initialization splash screen.
---@param opts? table { cwd?: string, on_complete?: fun(ok: boolean) }
---@return integer bufnr, integer winnr
function M.open_init_splash(opts)
  opts = opts or {}
  local cwd = opts.cwd or vim.fn.getcwd()

  -- If splash window is already open, focus it
  if M.active_win and vim.api.nvim_win_is_valid(M.active_win) then
    vim.api.nvim_set_current_win(M.active_win)
    return M.active_buf, M.active_win
  end

  local info = inspect_directory(cwd)
  local state = {
    cwd = cwd,
    info = info,
    remote_url = info.remote_url,
    license_key = "CC0-1.0",
    opts = opts,
  }

  local width = math.min(74, vim.o.columns - 4)
  local height = math.min(22, vim.o.lines - 4)
  local row = math.max(1, math.floor((vim.o.lines - height) / 2))
  local col = math.max(1, math.floor((vim.o.columns - width) / 2))

  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.bo[bufnr].buftype = "nofile"
  vim.bo[bufnr].bufhidden = "wipe"
  vim.bo[bufnr].swapfile = false
  vim.bo[bufnr].filetype = "review_anchor_splash"

  local winnr = vim.api.nvim_open_win(bufnr, true, {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = "rounded",
    title = " Review Anchor: Repository Setup ",
    title_pos = "center",
  })

  M.active_buf = bufnr
  M.active_win = winnr

  render_splash(bufnr, state)

  function M.close()
    if M.active_win and vim.api.nvim_win_is_valid(M.active_win) then
      vim.api.nvim_win_close(M.active_win, true)
    end
    M.active_win = nil
    M.active_buf = nil
  end

  local function close_splash()
    M.close()
  end

  -- Keybindings for splash buffer
  local function map(key, fn)
    vim.keymap.set("n", key, fn, { buffer = bufnr, nowait = true, silent = true })
  end

  map("q", close_splash)
  map("<Esc>", close_splash)

  map("r", function()
    vim.ui.input({
      prompt = "Enter Remote Repository URL: ",
      default = state.remote_url,
    }, function(val)
      if val ~= nil then
        state.remote_url = vim.trim(val)
        render_splash(bufnr, state)
      end
    end)
  end)

  for i, lic in ipairs(LICENSE_OPTIONS) do
    map(tostring(i), function()
      state.license_key = lic.key
      render_splash(bufnr, state)
    end)
  end

  local function do_submit()
    close_splash()
    execute_init(state, opts.on_complete)
  end

  map("<CR>", do_submit)
  map("i", do_submit)

  return bufnr, winnr
end

--- Headless or programmatic init helper (used by tests/scripts).
---@param opts? table
---@param on_complete? fun(ok: boolean)
function M.execute_init_direct(opts, on_complete)
  opts = opts or {}
  local cwd = opts.cwd or vim.fn.getcwd()
  local info = inspect_directory(cwd)
  local state = {
    cwd = cwd,
    info = info,
    remote_url = opts.remote_url or "",
    license_key = opts.license or "CC0-1.0",
    opts = opts,
  }
  execute_init(state, on_complete)
end

return M
