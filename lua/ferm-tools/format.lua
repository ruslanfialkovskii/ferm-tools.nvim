local M = {}

--- Tokenize a line into segments, preserving strings and comments verbatim.
--- Returns a list of { text = ..., preserve = bool }.
---@param line string
---@return table[] segments
local function tokenize_segments(line)
  local segments = {}
  local pos = 1
  local len = #line

  while pos <= len do
    local ch = line:sub(pos, pos)

    -- Comment: rest of line is preserved
    if ch == '#' then
      segments[#segments + 1] = { text = line:sub(pos), preserve = true }
      break
    end

    -- Single-quoted string
    if ch == "'" then
      local end_pos = line:find("'", pos + 1, true)
      if end_pos then
        segments[#segments + 1] = { text = line:sub(pos, end_pos), preserve = true }
        pos = end_pos + 1
        goto continue
      else
        segments[#segments + 1] = { text = line:sub(pos), preserve = true }
        break
      end
    end

    -- Double-quoted string
    if ch == '"' then
      local end_pos = pos + 1
      while end_pos <= len do
        if line:sub(end_pos, end_pos) == '\\' then
          end_pos = end_pos + 2
        elseif line:sub(end_pos, end_pos) == '"' then
          break
        else
          end_pos = end_pos + 1
        end
      end
      if end_pos <= len then
        segments[#segments + 1] = { text = line:sub(pos, end_pos), preserve = true }
        pos = end_pos + 1
      else
        segments[#segments + 1] = { text = line:sub(pos), preserve = true }
      end
      goto continue
    end

    -- Backtick command substitution
    if ch == '`' then
      local end_pos = line:find('`', pos + 1, true)
      if end_pos then
        segments[#segments + 1] = { text = line:sub(pos, end_pos), preserve = true }
        pos = end_pos + 1
        goto continue
      else
        segments[#segments + 1] = { text = line:sub(pos), preserve = true }
        break
      end
    end

    -- Whitespace run
    local ws = line:sub(pos):match('^%s+')
    if ws then
      segments[#segments + 1] = { text = ws, preserve = false, whitespace = true }
      pos = pos + #ws
      goto continue
    end

    -- Non-whitespace, non-string, non-comment token
    local tok = line:sub(pos):match('^[^%s#\'"` ]+')
    if tok then
      segments[#segments + 1] = { text = tok, preserve = false }
      pos = pos + #tok
      goto continue
    end

    -- Fallback: single char
    segments[#segments + 1] = { text = ch, preserve = false }
    pos = pos + 1

    ::continue::
  end

  return segments
end

--- Normalize spacing within a line: single space between tokens, preserve strings/comments.
---@param line string
---@return string
local function normalize_spacing(line)
  local stripped = line:match('^%s*(.-)%s*$')
  if stripped == '' then
    return ''
  end

  local segments = tokenize_segments(stripped)
  local parts = {}
  local last_was_space = true -- suppress leading space

  for _, seg in ipairs(segments) do
    if seg.whitespace then
      if not last_was_space then
        parts[#parts + 1] = ' '
        last_was_space = true
      end
    elseif seg.preserve then
      -- Preserved segments (strings, comments): add space before if needed
      if not last_was_space and #parts > 0 then
        parts[#parts + 1] = ' '
      end
      parts[#parts + 1] = seg.text
      last_was_space = false
    else
      if not last_was_space and #parts > 0 then
        parts[#parts + 1] = ' '
      end
      parts[#parts + 1] = seg.text
      last_was_space = false
    end
  end

  return table.concat(parts)
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

--- Count net brace depth change on a line.
--- Returns (open_delta, has_close_at_start).
---@param line string
---@return number delta
---@return boolean close_at_start
local function brace_info(line)
  local stripped = line:match('^%s*(.-)%s*$') or ''
  local close_at_start = stripped:sub(1, 1) == '}'

  local delta = 0
  local in_sq, in_dq, in_bt, in_comment = false, false, false, false
  for i = 1, #stripped do
    local c = stripped:sub(i, i)
    if in_comment then
      break
    elseif in_sq then
      if c == "'" then in_sq = false end
    elseif in_dq then
      if c == '\\' then
        -- skip next char (handled by loop advancing)
      elseif c == '"' then
        in_dq = false
      end
    elseif in_bt then
      if c == '`' then in_bt = false end
    elseif c == '#' then
      in_comment = true
    elseif c == "'" then
      in_sq = true
    elseif c == '"' then
      in_dq = true
    elseif c == '`' then
      in_bt = true
    elseif c == '{' then
      delta = delta + 1
    elseif c == '}' then
      delta = delta - 1
    end
  end

  return delta, close_at_start
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
  local prev_was_toplevel = false

  for _, line in ipairs(lines) do
    -- Trim trailing whitespace and normalize
    local stripped = line:match('^%s*(.-)%s*$') or ''

    -- Handle blank lines
    if stripped == '' then
      if not prev_was_blank then
        result[#result + 1] = ''
        prev_was_blank = true
      end
      -- Skip consecutive blanks
      prev_was_toplevel = false
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
    prev_was_toplevel = (depth == 0 and is_toplevel_block_start(stripped))

    ::continue::
  end

  -- Remove trailing blank lines
  while #result > 0 and result[#result] == '' do
    table.remove(result)
  end

  return result
end

--- Compute the brace depth at a given 0-indexed line in the buffer.
---@param bufnr number
---@param target_line number 0-indexed line number
---@return number depth
local function depth_at_line(bufnr, target_line)
  if target_line <= 0 then
    return 0
  end
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, target_line, false)
  local depth = 0
  for _, line in ipairs(lines) do
    local delta, _ = brace_info(line)
    depth = math.max(0, depth + delta)
  end
  return depth
end

--- Format the entire buffer.
---@param bufnr? number buffer number (default: current)
function M.buf(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local sw = vim.bo[bufnr].shiftwidth
  if sw == 0 then
    sw = vim.bo[bufnr].tabstop
  end
  local formatted = format_lines(lines, sw, 0)

  -- Ensure file ends with newline (final empty string)
  if #formatted > 0 and formatted[#formatted] ~= '' then
    formatted[#formatted + 1] = ''
  end

  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, formatted)
end

--- Format a range of lines in the buffer (1-indexed, inclusive).
---@param bufnr number
---@param start_line number 1-indexed start line
---@param end_line number 1-indexed end line
function M.range(bufnr, start_line, end_line)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(bufnr, start_line - 1, end_line, false)
  local sw = vim.bo[bufnr].shiftwidth
  if sw == 0 then
    sw = vim.bo[bufnr].tabstop
  end
  local start_depth = depth_at_line(bufnr, start_line - 1)
  local formatted = format_lines(lines, sw, start_depth)
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
