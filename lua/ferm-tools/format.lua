local M = {}

local lexer = require('ferm-tools.lexer')
local kw = require('ferm-tools.keywords')

--- Sentinel keys for the target and comment columns of a rule line. The \1
--- prefix cannot collide with a real ferm keyword.
local TARGET_KEY = '\1target'

--- Canonical column key for a keyword, folding synonyms (e.g. proto/protocol)
--- onto one alignment column. Only column identity is affected; cell text and
--- the keyword stored on the cell are untouched.
---@param key string
---@return string
local function canon_key(key)
  return kw.keyword_aliases[key] or key
end

--- Alignment column key for a rule cell. Like `canon_key`, but `mod`/`module`
--- cells are further split by their module name so that, e.g.,
--- `mod multiport ...` and `mod comment ...` occupy separate columns — a rule
--- with only one of them then reserves the correct column instead of colliding.
---@param cell table { key = string, text = string }
---@return string
local function column_key(cell)
  local key = canon_key(cell.key)
  if key == 'mod' or key == 'module' then
    local mod_name = cell.text:match('^%S+%s+(%S+)')
    if mod_name then
      return key .. ':' .. mod_name
    end
  end
  return key
end

--- Split a rule cell into its leading keyword and the rest (its value). Each is
--- aligned in its own sub-column, so when a column mixes keyword spellings of
--- different lengths (e.g. `proto`/`protocol`) the keywords line up and the
--- values still line up after them.
---@param text string
---@return string keyword
---@return string value the remainder after the keyword (may be empty)
local function split_cell(text)
  local kw, val = text:match('^(%S+)%s+(.*)$')
  if kw then
    return kw, val
  end
  return text, ''
end

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

--- Net structural depth change on a line (braces and parens together), plus
--- whether the line opens at a smaller indent because it starts with a closer.
---@param line string
---@return number delta combined brace+paren depth change
---@return boolean close_at_start line starts with a closing brace or paren
---@return number brace_delta net brace change only
---@return number paren_delta net paren change only
local function struct_info(line)
  local info = lexer.line_info(line)
  return info.delta + info.paren_delta, info.first_closes, info.delta, info.paren_delta
end

--- Split a normalized line into its statement text and trailing comment.
--- The comment is located via the lexer so a '#' inside a string is ignored.
---@param line string a spacing-normalized line (no leading indent)
---@return string value text before the comment (right-trimmed)
---@return string? comment the comment token including '#', or nil
local function split_comment(line)
  for _, tok in ipairs(lexer.tokenize_line(0, line)) do
    if tok.type == 'comment' then
      return (line:sub(1, tok.col):gsub('%s+$', '')), tok.value
    end
  end
  return line, nil
end

--- Parse a single-statement rule line into ordered keyword cells, so that a
--- run of similar rules can be laid out as aligned columns. Returns nil when
--- the line is not a plain, column-alignable rule (e.g. it opens a block, has
--- no target, spans a multi-line paren, or repeats a keyword).
---@param value string statement text without indent or trailing comment
---@return table[]? cells list of { key = string, text = string } in order
local function parse_rule(value)
  if value == '' or value:sub(-1) ~= ';' then
    return nil
  end

  local tokens = lexer.tokenize_line(0, value)
  if #tokens == 0 then
    return nil
  end

  -- Reject anything that isn't a single flat statement. Braces are allowed
  -- only if balanced within the line (e.g. Jinja `{{ ... }}`); a net change
  -- means the line opens or closes a ferm block and must not be column-aligned.
  local semicolons, first_word, brace_delta = 0, nil, 0
  for _, tok in ipairs(tokens) do
    if tok.type == 'brace_open' then
      brace_delta = brace_delta + 1
    elseif tok.type == 'brace_close' then
      brace_delta = brace_delta - 1
    elseif tok.type == 'semicolon' then
      semicolons = semicolons + 1
    end
    if first_word == nil and tok.type ~= 'comment' then
      first_word = tok
    end
  end
  if semicolons ~= 1 or brace_delta ~= 0 or not first_word or first_word.type ~= 'word'
    or not kw.match_keywords[first_word.value] then
    return nil
  end

  -- Column boundaries: each match keyword / chain command starts a cell; the
  -- first target token starts the (final) target cell and ends boundary
  -- scanning so multi-word targets stay in one cell. The keyword is kept on
  -- each cell; alignment keys columns by it (a repeated keyword just yields a
  -- second column of the same name).
  local boundaries, has_target = {}, false
  for _, tok in ipairs(tokens) do
    if tok.type == 'word' then
      local key
      if kw.targets[tok.value] then
        key, has_target = TARGET_KEY, true
      elseif kw.match_keywords[tok.value] or kw.chain_commands[tok.value] then
        key = tok.value
      end
      if key then
        boundaries[#boundaries + 1] = { col = tok.col, key = key }
        if key == TARGET_KEY then
          break
        end
      end
    end
  end
  if not has_target then
    return nil
  end

  local cells = {}
  for i, b in ipairs(boundaries) do
    local stop = boundaries[i + 1] and boundaries[i + 1].col or #value
    cells[#cells + 1] = { key = b.key, text = vim.trim(value:sub(b.col + 1, stop)) }
  end
  return cells
end

--- Align a run of paren-list item records: pad each item's value so trailing
--- comments line up one space past the widest value in the group.
---@param records table[] item records (all inside the same paren list)
local function align_paren_items(records)
  local width = 0
  for _, rec in ipairs(records) do
    width = math.max(width, #rec.value)
  end
  for _, rec in ipairs(records) do
    if rec.comment then
      rec.rendered = rec.value .. string.rep(' ', width - #rec.value + 1) .. rec.comment
    else
      rec.rendered = rec.value
    end
  end
end

--- Align a run of rule records into columns keyed by keyword. The column
--- layout is a common supersequence of every rule's leading-keyword order, so
--- a keyword present in only some rules (e.g. `dport`) gets its own column that
--- the others leave blank, keeping later keywords and the target aligned.
--- Keyword order within each line is preserved. The target is a final column.
---@param records table[] rule records (same indent, each with rec.cells)
local function align_rules(records)
  -- Build a common column layout as the shortest-ish supersequence of every
  -- rule's leading-keyword order. A keyword present in some rules but missing
  -- in others (e.g. `dport`) gets its own column, which the other rules leave
  -- blank; keyword order within each line is preserved (no reordering). This
  -- keeps later columns and comments aligned even when a middle match is
  -- absent. Cells are keyed by keyword; the target is a separate final column.
  local function find_from(cols, key, from)
    for j = from, #cols do
      if cols[j] == key then
        return j
      end
    end
  end

  local cols = {}
  for _, rec in ipairs(records) do
    local keys = {}
    for i = 1, #rec.cells - 1 do
      keys[i] = column_key(rec.cells[i])
    end

    local ptr, i = 1, 1
    while i <= #keys do
      local j = find_from(cols, keys[i], ptr)
      if j then
        ptr, i = j + 1, i + 1
      else
        -- keys[i] is new. Insert it (and any following new keys) right before
        -- the next key that DOES exist ahead, so it lands in its natural place
        -- (e.g. `dport` between `proto` and `mod`); if none follow, append.
        local m, anchor = i + 1, nil
        while m <= #keys do
          anchor = find_from(cols, keys[m], ptr)
          if anchor then
            break
          end
          m = m + 1
        end
        local insert_at = anchor or (#cols + 1)
        for r = m - 1, i, -1 do
          table.insert(cols, insert_at, keys[r])
        end
        ptr, i = insert_at + (m - i), m
      end
    end
  end

  -- Assign each leading cell to its column, then measure keyword and value
  -- widths per column.
  local kw_width, val_width, target_width = {}, {}, 0
  for c = 1, #cols do
    kw_width[c], val_width[c] = 0, 0
  end
  for _, rec in ipairs(records) do
    rec.slot = {}
    local ptr = 1
    for i = 1, #rec.cells - 1 do
      local key = column_key(rec.cells[i])
      for j = ptr, #cols do
        if cols[j] == key then
          local keyword, value = split_cell(rec.cells[i].text)
          rec.slot[j] = { kw = keyword, val = value }
          kw_width[j] = math.max(kw_width[j], #keyword)
          val_width[j] = math.max(val_width[j], #value)
          ptr = j + 1
          break
        end
      end
    end
    target_width = math.max(target_width, #rec.cells[#rec.cells].text)
  end

  --- Full rendered width of column c (keyword sub-column, then value if any).
  local function col_text(cell, c)
    local kw = (cell and cell.kw) or ''
    local text = kw .. string.rep(' ', kw_width[c] - #kw)
    if val_width[c] > 0 then
      local val = (cell and cell.val) or ''
      text = text .. ' ' .. val .. string.rep(' ', val_width[c] - #val)
    end
    return text
  end

  for _, rec in ipairs(records) do
    -- Render columns only up to this rule's last populated one. A *middle*
    -- column the rule skips is reserved (blank) so its own later keywords and
    -- comment stay aligned; *trailing* columns it never reaches are omitted, so
    -- a short rule (e.g. `daddr X ACCEPT`) stays compact instead of being
    -- stretched by richer sibling rules.
    local last = 0
    for c = 1, #cols do
      if rec.slot[c] then
        last = c
      end
    end

    local parts = {}
    for c = 1, last do
      parts[#parts + 1] = col_text(rec.slot[c], c)
    end

    local target = rec.cells[#rec.cells].text
    -- Pad the target only when a comment follows, so comments line up too.
    if rec.comment then
      target = target .. string.rep(' ', target_width - #target)
    end
    parts[#parts + 1] = target

    local rendered = table.concat(parts, ' ')
    if rec.comment then
      rendered = rendered .. ' ' .. rec.comment
    end
    rec.rendered = rendered
  end
end

--- Run the alignment passes over formatted records in place, grouping maximal
--- runs of same-context, same-indent lines.
---@param records table[]
local function align(records)
  local i = 1
  while i <= #records do
    local rec = records[i]
    if rec.kind == 'line' and (rec.paren_item or rec.cells) then
      local j = i
      while j + 1 <= #records do
        local nxt = records[j + 1]
        if nxt.kind ~= 'line' or nxt.indent ~= rec.indent then
          break
        end
        if rec.paren_item then
          if not nxt.paren_item then break end
        else
          -- Only align rules that share the same leading keyword (synonyms
          -- count as the same); otherwise their columns don't correspond.
          if not nxt.cells or canon_key(nxt.cells[1].key) ~= canon_key(rec.cells[1].key) then
            break
          end
        end
        j = j + 1
      end

      if j > i then
        local group = {}
        for k = i, j do
          group[#group + 1] = records[k]
        end
        if rec.paren_item then
          align_paren_items(group)
        else
          align_rules(group)
        end
      end
      i = j + 1
    else
      i = i + 1
    end
  end
end

--- Format a range of lines.
---@param lines string[] lines to format
---@param indent_width number spaces per indent level
---@param start_depth number combined brace+paren depth at the start of the range
---@return string[] formatted lines
local function format_lines(lines, indent_width, start_depth)
  local records = {}
  local depth = start_depth
  local paren_depth = 0
  local prev_was_blank = false

  for _, line in ipairs(lines) do
    local stripped = vim.trim(line)

    -- Handle blank lines (collapse consecutive blanks)
    if stripped == '' then
      if not prev_was_blank then
        records[#records + 1] = { kind = 'blank' }
        prev_was_blank = true
      end
      goto continue
    end

    -- Structural deltas for indent and context classification
    local delta, close_at_start, brace_delta, paren_delta = struct_info(stripped)

    -- Adjust depth before indenting if line starts with a closer
    local line_depth = depth
    if close_at_start then
      line_depth = math.max(0, depth - 1)
    end

    -- Insert blank line before top-level blocks (if not already blank)
    if depth == 0 and is_toplevel_block_start(stripped) and #records > 0 and not prev_was_blank then
      records[#records + 1] = { kind = 'blank' }
    end

    -- Normalize spacing, then split off any trailing comment
    local normalized = normalize_spacing(stripped)
    local value, comment = split_comment(normalized)

    -- A "paren item" is a content line strictly inside an open multi-line
    -- paren list; a "rule" is a flat single statement in a brace block.
    local paren_item = paren_depth >= 1 and paren_delta == 0 and brace_delta == 0 and not close_at_start
    local cells
    if not paren_item then
      cells = parse_rule(value)
    end

    records[#records + 1] = {
      kind = 'line',
      indent = line_depth,
      indent_str = string.rep(' ', line_depth * indent_width),
      value = value,
      comment = comment,
      normalized = normalized,
      paren_item = paren_item,
      cells = cells,
    }

    depth = math.max(0, depth + delta)
    paren_depth = math.max(0, paren_depth + paren_delta)
    prev_was_blank = false

    ::continue::
  end

  align(records)

  local result = {}
  for _, rec in ipairs(records) do
    if rec.kind == 'blank' then
      result[#result + 1] = ''
    else
      result[#result + 1] = rec.indent_str .. (rec.rendered or rec.normalized)
    end
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
      local delta = struct_info(line)
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
