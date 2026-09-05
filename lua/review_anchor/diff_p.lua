local M = {}

--- Find the enclosing context header (like diff -p) for a given line in a buffer.
---@param bufnr integer
---@param line_1indexed integer
---@return string context_header, string raw_title
function M.find_enclosing_context(bufnr, line_1indexed)
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  local cur_line = math.min(line_1indexed, line_count)

  local ft = vim.bo[bufnr].filetype
  local fname = vim.api.nvim_buf_get_name(bufnr)
  local is_md = (ft == "markdown") or fname:match("%.md$") ~= nil

  for l = cur_line, 1, -1 do
    local text = vim.api.nvim_buf_get_lines(bufnr, l - 1, l, false)[1] or ""
    if is_md then
      local hashes, heading = text:match("^(#+)%s+(.*)$")
      if heading then
        local clean_heading = heading:gsub("^%s+", ""):gsub("%s+$", "")
        return string.format("@@ %s %s @@", hashes, clean_heading), clean_heading
      end
    else
      -- Code patterns: functions, classes, methods
      if text:match("^%s*function%s+[%w_.:]+")
         or text:match("^%s*local%s+function%s+[%w_.:]+")
         or text:match("^%s*def%s+[%w_]+")
         or text:match("^%s*func%s+[%w_]+")
         or text:match("^%s*class%s+[%w_]+")
         or text:match("^%s*struct%s+[%w_]+")
         or text:match("^%s*enum%s+[%w_]+")
         or text:match("^%s*impl%s+[%w_]+") then
        local clean_sig = text:gsub("^%s+", ""):gsub("%s*[{:]?%s*$", "")
        return string.format("@@ %s @@", clean_sig), clean_sig
      end
    end
  end

  return "@@ document root @@", "document root"
end

--- Extract surrounding hunk lines around a range.
---@param bufnr integer
---@param start_line_1indexed integer
---@param end_line_1indexed integer
---@param context_radius? integer
---@return string[] hunk_lines, integer hunk_start, integer hunk_end
function M.extract_hunk(bufnr, start_line_1indexed, end_line_1indexed, context_radius)
  context_radius = context_radius or 2
  local total_lines = vim.api.nvim_buf_line_count(bufnr)

  local s = math.max(1, start_line_1indexed - context_radius)
  local e = math.min(total_lines, end_line_1indexed + context_radius)

  local lines = vim.api.nvim_buf_get_lines(bufnr, s - 1, e, false)
  return lines, s, e
end

--- Get buffer path relative to git root.
---@param bufnr integer
---@return string
function M.get_relative_path(bufnr)
  local full_path = vim.api.nvim_buf_get_name(bufnr)
  if full_path == "" then
    return "scratch"
  end

  local git_root = vim.fn.system("git rev-parse --show-toplevel 2>/dev/null"):gsub("%s+$", "")
  if git_root ~= "" and full_path:sub(1, #git_root) == git_root then
    local rel = full_path:sub(#git_root + 2)
    return rel
  end

  return vim.fn.fnamemodify(full_path, ":.")
end

return M
