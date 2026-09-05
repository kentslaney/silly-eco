local config = require("review_anchor.config")
local diff_p = require("review_anchor.diff_p")

local M = {}

local ns_id = vim.api.nvim_create_namespace(config.defaults.namespace_name)
local next_ref_id = 1
local anchors = {} -- list of anchor tables
local qa_items = {} -- list of claude QA tables
local general_prompt = ""

function M.get_namespace()
  return ns_id
end

--- Reset all anchors, QA items, and prompt.
function M.clear_all()
  for _, a in ipairs(anchors) do
    if vim.api.nvim_buf_is_valid(a.bufnr) and a.extmark_id then
      pcall(vim.api.nvim_buf_del_extmark, a.bufnr, ns_id, a.extmark_id)
    end
  end
  anchors = {}
  qa_items = {}
  general_prompt = ""
  next_ref_id = 1
end

--- Get next available Ref ID
function M.get_next_ref_id()
  local id = next_ref_id
  next_ref_id = next_ref_id + 1
  return id
end

--- Add a review comment anchor.
---@param bufnr integer
---@param line_0indexed integer
---@param col_start integer
---@param col_end integer
---@param comment string
---@param selected_text? string
---@return table anchor
function M.add_anchor(bufnr, line_0indexed, col_start, col_end, comment, selected_text)
  config.setup_highlights()
  local ref_id = M.get_next_ref_id()
  local line_1indexed = line_0indexed + 1

  local diff_context, section_name = diff_p.find_enclosing_context(bufnr, line_1indexed)
  local hunk_lines, hunk_s, hunk_e = diff_p.extract_hunk(bufnr, line_1indexed, line_1indexed, 2)
  local rel_path = diff_p.get_relative_path(bufnr)

  if not selected_text or selected_text == "" then
    local current_line_text = vim.api.nvim_buf_get_lines(bufnr, line_0indexed, line_0indexed + 1, false)[1] or ""
    selected_text = vim.trim(current_line_text)
  end

  local comment_preview = comment:gsub("\n", " ")
  if #comment_preview > 40 then
    comment_preview = comment_preview:sub(1, 37) .. "..."
  end

  local extmark_id = vim.api.nvim_buf_set_extmark(bufnr, ns_id, line_0indexed, col_start or 0, {
    sign_text = config.options.gutter_sign_text .. " ",
    sign_hl_group = "ReviewAnchorSign",
    virt_text = {
      { string.format(" [Ref %d: %s]", ref_id, comment_preview), "ReviewAnchorVirtualText" },
    },
    virt_text_pos = "eol",
    right_gravity = true,
  })

  local anchor = {
    id = ref_id,
    extmark_id = extmark_id,
    bufnr = bufnr,
    file_path = rel_path,
    line_0indexed = line_0indexed,
    col_start = col_start or 0,
    col_end = col_end or 0,
    selected_text = selected_text,
    comment = comment,
    diff_context = diff_context,
    section_name = section_name,
    hunk = hunk_lines,
    hunk_start = hunk_s,
    hunk_end = hunk_e,
    created_at = os.date("!%Y-%m-%dT%H:%M:%SZ"),
  }

  table.insert(anchors, anchor)
  return anchor
end

--- Sync line positions of anchors with live extmark positions.
function M.sync_positions()
  for _, a in ipairs(anchors) do
    if vim.api.nvim_buf_is_valid(a.bufnr) and a.extmark_id then
      local pos = vim.api.nvim_buf_get_extmark_by_id(a.bufnr, ns_id, a.extmark_id, {})
      if pos and #pos >= 2 then
        a.line_0indexed = pos[1]
        a.col_start = pos[2]
      end
    end
  end
end

--- Get all active review comment anchors.
---@return table[]
function M.get_all_anchors()
  M.sync_positions()
  return anchors
end

--- Find anchor at cursor position in window.
---@param bufnr integer
---@param winnr? integer
---@return table|nil anchor, integer|nil index
function M.get_anchor_at_cursor(bufnr, winnr)
  winnr = winnr or 0
  local cursor = vim.api.nvim_win_get_cursor(winnr)
  local cur_line_0indexed = cursor[1] - 1

  M.sync_positions()
  for idx, a in ipairs(anchors) do
    if a.bufnr == bufnr and a.line_0indexed == cur_line_0indexed then
      return a, idx
    end
  end
  return nil, nil
end

--- Delete anchor by ref ID.
---@param id integer
---@return boolean success
function M.delete_anchor(id)
  for idx, a in ipairs(anchors) do
    if a.id == id then
      if vim.api.nvim_buf_is_valid(a.bufnr) and a.extmark_id then
        pcall(vim.api.nvim_buf_del_extmark, a.bufnr, ns_id, a.extmark_id)
      end
      table.remove(anchors, idx)
      return true
    end
  end
  return false
end

--- Delete anchor under cursor.
---@param bufnr integer
---@param winnr? integer
---@return boolean success, integer|nil deleted_id
function M.delete_anchor_at_cursor(bufnr, winnr)
  local a, _ = M.get_anchor_at_cursor(bufnr, winnr)
  if a then
    local id = a.id
    M.delete_anchor(id)
    return true, id
  end
  return false, nil
end

--- Add a Claude Code Q&A item.
---@param question string
---@param answer string
---@param diff_context? string
---@param section_name? string
---@param file_path? string
---@return table qa_item
function M.add_qa(question, answer, diff_context, section_name, file_path)
  local ref_id = M.get_next_ref_id()
  local qa = {
    id = ref_id,
    question = vim.trim(question),
    answer = vim.trim(answer),
    diff_context = diff_context or "@@ Claude Code Q/A @@",
    section_name = section_name or "General Review",
    file_path = file_path or "implementation_plan.md",
    created_at = os.date("!%Y-%m-%dT%H:%M:%SZ"),
  }
  table.insert(qa_items, qa)
  return qa
end

--- Get all Claude Code Q&A items.
---@return table[]
function M.get_all_qa()
  return qa_items
end

--- Set general model prompt snapshot.
---@param prompt string
function M.set_prompt(prompt)
  general_prompt = vim.trim(prompt)
end

--- Get general model prompt snapshot.
---@return string
function M.get_prompt()
  return general_prompt
end

return M
