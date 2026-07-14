local M = {}

local lexer = require('ferm-tools.lexer')

--- Token types emitted verbatim by the formatter (inner spacing kept intact)
local preserve_types = {
  string = true,
  unclosed_string = true,
  backtick = true,
  unclosed_backtick = true,
  comment = true,
}

--- Normalize spacing within a line: single space between tokens, strings and
--- comments preserved verbatim. Punctuation not tokenized by the lexer
--- (e.g. '=', ',') is kept via the text between preserved tokens.
---@param line string
---@return string
local function normalize_spacing(line)
  local parts = {}

  local function add_plain(text)
    for piece in text:gmatch('%S+') do
      parts[#parts + 1] = piece
    end
  end

  local pos = 1
  for _, tok in ipairs(lexer.tokenize_line(0, line)) do
    if preserve_types[tok.type] then
      add_plain(line:sub(pos, tok.col))
      parts[#parts + 1] = tok.value
      pos = tok.end_col + 1
    end
  end
  add_plain(line:sub(pos))

  return table.concat(parts, ' ')
end

--- Determine if a line (after stripping) starts a top-level block.
--- Top-level blocks start with domain or table at depth 0.
---@param stripped string
---@return boolean
local function is_toplevel_block_start(stripped)
  return stripped:match('^domain%s') ~= nil
    or stripped:match('^domain%(') ~= nil
    or stripped:match('^table%s') ~= nil
end

--- Count net brace depth change on a line (string/comment aware).
---@param line string
---@return number delta
---@return boolean close_at_start
local function brace_info(line)
  local info = lexer.line_info(line)
  return info.delta, info.close_at_start
end

--- Format a range of lines.
---@param lines string[] lines to format
---@param indent_width number spaces per indent level
---@param start_depth number brace depth at the start of the range
---@return string[] formatted lines
local function format_lines(lines, indent_width, start_depth)
  local result = {}
  local depth = start_depth
  local prev_was_blank = false

  for _, line in ipairs(lines) do
    local stripped = vim.trim(line)

    -- Handle blank lines (collapse consecutive blanks)
    if stripped == '' then
      if not prev_was_blank then
        result[#result + 1] = ''
        prev_was_blank = true
      end
      goto continue
    end

    -- Get brace info for indent calculation
    local delta, close_at_start = brace_info(stripped)

    -- Adjust depth before indenting if line starts with }
    local line_depth = depth
    if close_at_start then
      line_depth = math.max(0, depth - 1)
    end

    -- Insert blank line before top-level blocks (if not already blank)
    if depth == 0 and is_toplevel_block_start(stripped) and #result > 0 and not prev_was_blank then
      result[#result + 1] = ''
    end

    -- Normalize spacing within the line
    local normalized = normalize_spacing(stripped)

    -- Apply indentation
    local indent = string.rep(' ', line_depth * indent_width)
    result[#result + 1] = indent .. normalized

    -- Update depth
    depth = math.max(0, depth + delta)
    prev_was_blank = false

    ::continue::
  end

  return result
end

--- Cached cumulative brace depths, keyed by buffer and invalidated by changedtick.
local depth_cache = {}

--- Compute the brace depth at the start of a given 0-indexed line.
---@param bufnr number
---@param target_line number 0-indexed line number
---@return number depth
local function depth_at_line(bufnr, target_line)
  if target_line <= 0 then
    return 0
  end
  local tick = vim.api.nvim_buf_get_changedtick(bufnr)
  local cached = depth_cache[bufnr]
  if not cached or cached.tick ~= tick then
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local depths = {}
    local depth = 0
    for i, line in ipairs(lines) do
      depths[i - 1] = depth
      local delta = brace_info(line)
      depth = math.max(0, depth + delta)
    end
    depths[#lines] = depth
    cached = { tick = tick, depths = depths }
    depth_cache[bufnr] = cached
  end
  return cached.depths[target_line] or 0
end

--- Resolve the indent width for a buffer.
---@param bufnr number
---@return number
local function indent_width(bufnr)
  local sw = vim.bo[bufnr].shiftwidth
  if sw == 0 then
    sw = vim.bo[bufnr].tabstop
  end
  return sw
end

--- Format the entire buffer.
---@param bufnr? number buffer number (default: current)
function M.buf(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local formatted = format_lines(lines, indent_width(bufnr), 0)

  -- Strip trailing blank lines; the buffer's final newline is implicit
  while #formatted > 0 and formatted[#formatted] == '' do
    table.remove(formatted)
  end

  local view
  if bufnr == vim.api.nvim_get_current_buf() then
    view = vim.fn.winsaveview()
  end
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, formatted)
  if view then
    vim.fn.winrestview(view)
  end
end

--- Format a range of lines in the buffer (1-indexed, inclusive).
--- Blank lines at the range boundaries are kept.
---@param bufnr number
---@param start_line number 1-indexed start line
---@param end_line number 1-indexed end line
function M.range(bufnr, start_line, end_line)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(bufnr, start_line - 1, end_line, false)
  local start_depth = depth_at_line(bufnr, start_line - 1)
  local formatted = format_lines(lines, indent_width(bufnr), start_depth)
  vim.api.nvim_buf_set_lines(bufnr, start_line - 1, end_line, false, formatted)
end

--- formatexpr function for use with gq.
--- Set via: vim.bo.formatexpr = "v:lua.require('ferm-tools.format').formatexpr()"
---@return number
function M.formatexpr()
  if vim.v.char ~= '' then
    -- Not formatting, let Vim handle insertions
    return 1
  end
  local start_line = vim.v.lnum
  local end_line = vim.v.lnum + vim.v.count - 1
  local bufnr = vim.api.nvim_get_current_buf()
  M.range(bufnr, start_line, end_line)
  return 0
end

return M
