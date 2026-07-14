--- Shared ferm lexer used by highlight, lint, format, indent, and fold.
local M = {}

local kw = require('ferm-tools.keywords')

local single_char = {
  ['!'] = 'operator',
  [';'] = 'semicolon',
  ['{'] = 'brace_open',
  ['}'] = 'brace_close',
  ['('] = 'paren_open',
  [')'] = 'paren_close',
}

--- Tokenize a single line into structured tokens.
--- Token: { type, value, lnum, col, end_col } with 0-indexed, end-exclusive columns.
---@param lnum number 0-indexed line number
---@param line string
---@return table[] tokens
function M.tokenize_line(lnum, line)
  local tokens = {}
  local pos = 1
  local len = #line

  local function push(typ, value, end_col)
    tokens[#tokens + 1] = {
      type = typ, value = value,
      lnum = lnum, col = pos - 1, end_col = end_col,
    }
  end

  while pos <= len do
    -- Skip whitespace
    local ws = line:match('^%s+', pos)
    if ws then
      pos = pos + #ws
      if pos > len then break end
    end

    local ch = line:sub(pos, pos)

    -- Comment
    if ch == '#' then
      push('comment', line:sub(pos), len)
      break
    end

    -- Single-quoted string
    if ch == "'" then
      local end_pos = line:find("'", pos + 1, true)
      if end_pos then
        push('string', line:sub(pos, end_pos), end_pos)
        pos = end_pos + 1
      else
        push('unclosed_string', line:sub(pos), len)
        break
      end
      goto continue
    end

    -- Double-quoted string (backslash escapes)
    if ch == '"' then
      local end_pos = pos + 1
      while end_pos <= len do
        local c = line:sub(end_pos, end_pos)
        if c == '\\' then
          end_pos = end_pos + 2
        elseif c == '"' then
          break
        else
          end_pos = end_pos + 1
        end
      end
      if end_pos <= len then
        push('string', line:sub(pos, end_pos), end_pos)
        pos = end_pos + 1
      else
        push('unclosed_string', line:sub(pos), len)
        break
      end
      goto continue
    end

    -- Backtick command substitution
    if ch == '`' then
      local end_pos = line:find('`', pos + 1, true)
      if end_pos then
        push('backtick', line:sub(pos, end_pos), end_pos)
        pos = end_pos + 1
      else
        push('unclosed_backtick', line:sub(pos), len)
        break
      end
      goto continue
    end

    -- Variable $NAME
    local var = line:match('^%$[A-Za-z_][A-Za-z0-9_]*', pos)
    if var then
      push('variable', var, pos - 1 + #var)
      pos = pos + #var
      goto continue
    end

    -- User function &NAME
    local func = line:match('^&[A-Za-z_][A-Za-z0-9_]*', pos)
    if func then
      push('function', func, pos - 1 + #func)
      pos = pos + #func
      goto continue
    end

    -- Directive or builtin function (@keyword); unknown @words lex as
    -- directives and are flagged by the linter
    local at_word = line:match('^@[A-Za-z_][A-Za-z0-9_]*', pos)
    if at_word then
      local typ = kw.builtin_functions[at_word] and 'builtin_func' or 'directive'
      push(typ, at_word, pos - 1 + #at_word)
      pos = pos + #at_word
      goto continue
    end

    -- IPv4 address (must check before plain number)
    local ipv4 = line:match('^%d+%.%d+%.%d+%.%d+/%d+', pos) or line:match('^%d+%.%d+%.%d+%.%d+', pos)
    if ipv4 then
      push('ipv4', ipv4, pos - 1 + #ipv4)
      pos = pos + #ipv4
      goto continue
    end

    -- IPv6 address (heuristic: needs :: or at least 2 colons)
    local ipv6 = line:match('^[0-9a-fA-F:]+::[0-9a-fA-F:]*/%d+', pos)
      or line:match('^[0-9a-fA-F:]+::[0-9a-fA-F:]*', pos)
      or line:match('^[0-9a-fA-F]+:[0-9a-fA-F]+:[0-9a-fA-F:]+/%d+', pos)
      or line:match('^[0-9a-fA-F]+:[0-9a-fA-F]+:[0-9a-fA-F:]+', pos)
    if ipv6 and ipv6:find(':') then
      local _, colon_count = ipv6:gsub(':', ':')
      if colon_count >= 2 or ipv6:find('::', 1, true) then
        push('ipv6', ipv6, pos - 1 + #ipv6)
        pos = pos + #ipv6
        goto continue
      end
    end

    -- Hex number
    local hex = line:match('^0x[0-9a-fA-F]+', pos)
    if hex then
      push('hex', hex, pos - 1 + #hex)
      pos = pos + #hex
      goto continue
    end

    -- Word token (identifier-like, including hyphens for params like log-prefix)
    local word = line:match('^[A-Za-z_][A-Za-z0-9_%-]*', pos)
    if word then
      push('word', word, pos - 1 + #word)
      pos = pos + #word
      goto continue
    end

    -- Decimal number
    local num = line:match('^%d+', pos)
    if num then
      push('number', num, pos - 1 + #num)
      pos = pos + #num
      goto continue
    end

    -- Single-char tokens; other punctuation (=, comma, ...) is skipped
    local typ = single_char[ch]
    if typ then
      push(typ, ch, pos)
    end
    pos = pos + 1

    ::continue::
  end

  return tokens
end

--- Tokenize all lines of a buffer.
---@param lines string[]
---@return table[] tokens
function M.tokenize(lines)
  local all = {}
  for i, line in ipairs(lines) do
    local line_tokens = M.tokenize_line(i - 1, line)
    for _, tok in ipairs(line_tokens) do
      all[#all + 1] = tok
    end
  end
  return all
end

--- Structural summary of one line, for indent/fold/format.
---@param line string
---@return table info { delta, close_at_start, open_at_end }
function M.line_info(line)
  local delta = 0
  local first, last
  for _, tok in ipairs(M.tokenize_line(0, line)) do
    if tok.type == 'brace_open' then
      delta = delta + 1
    elseif tok.type == 'brace_close' then
      delta = delta - 1
    end
    if tok.type ~= 'comment' then
      first = first or tok
      last = tok
    end
  end
  return {
    delta = delta,
    close_at_start = first ~= nil and first.type == 'brace_close',
    open_at_end = last ~= nil and last.type == 'brace_open',
  }
end

return M
