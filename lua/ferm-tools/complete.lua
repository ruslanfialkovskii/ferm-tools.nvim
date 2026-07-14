local M = {}

local kw = require('ferm-tools.keywords')
local lexer = require('ferm-tools.lexer')

--- LSP CompletionItemKind values (only the kinds this source emits)
local kind = {
  Function = 3,
  Variable = 6,
  Module = 9,
  Property = 10,
  Value = 12,
  Enum = 13,
  Keyword = 14,
  Constant = 21,
}

--- Convert a set-table (key=true) into a sorted list of keys.
---@param tbl table<string, boolean>
---@return string[]
local function sorted_keys(tbl)
  local keys = vim.tbl_keys(tbl)
  table.sort(keys)
  return keys
end

--- Static completion item lists, built once per context on first use.
--- Cached lists are shared: callers must not mutate them.
local item_cache = {}

--- Build (or fetch) the cached item list for a context.
---@param name string cache key
---@param specs table[] list of { set, kind, menu }
---@return table[] items
local function context_items(name, specs)
  local items = item_cache[name]
  if not items then
    items = {}
    for _, spec in ipairs(specs) do
      for _, key in ipairs(sorted_keys(spec[1])) do
        items[#items + 1] = { word = key, kind = spec[2], menu = spec[3] }
      end
    end
    item_cache[name] = items
  end
  return items
end

--- Scan buffer for user definitions (@def $VAR / @def &FUNC), comment- and
--- string-aware, cached per changedtick.
local def_cache = {}

---@param bufnr number
---@return table defs { vars = string[], funcs = string[] }
local function scan_defs(bufnr)
  local tick = vim.api.nvim_buf_get_changedtick(bufnr)
  local cached = def_cache[bufnr]
  if cached and cached.tick == tick then
    return cached
  end

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local tokens = lexer.tokenize(lines)
  local vars, funcs, seen = {}, {}, {}
  for i, tok in ipairs(tokens) do
    if tok.type == 'directive' and tok.value == '@def' then
      local next_tok = tokens[i + 1]
      if next_tok and not seen[next_tok.value] then
        if next_tok.type == 'variable' then
          seen[next_tok.value] = true
          vars[#vars + 1] = next_tok.value
        elseif next_tok.type == 'function' then
          seen[next_tok.value] = true
          funcs[#funcs + 1] = next_tok.value
        end
      end
    end
  end
  table.sort(vars)
  table.sort(funcs)

  cached = { tick = tick, vars = vars, funcs = funcs }
  def_cache[bufnr] = cached
  return cached
end

--- Find the 0-indexed start of the completion prefix before col.
---@param line string
---@param col number 0-indexed cursor column
---@return number start 0-indexed prefix start
local function find_prefix_start(line, col)
  local start = col
  while start > 0 and line:sub(start, start):match('[%w_%-@$&]') do
    start = start - 1
  end
  return start
end

--- Get the context word before the prefix on the current line.
--- Skips back over an open parenthesized value list, so 'proto (tcp u'
--- still resolves to 'proto'.
---@param line_text string
---@param col number 0-indexed prefix start
---@return string|nil prev_word
local function get_prev_word(line_text, col)
  local before = line_text:sub(1, col)
  -- Remove any partial word at cursor
  before = before:gsub('[%w_%-@$&]*$', '')
  -- Inside an unclosed paren list, the governing keyword precedes the '('
  local depth = 0
  for i = #before, 1, -1 do
    local c = before:sub(i, i)
    if c == ')' then
      depth = depth + 1
    elseif c == '(' then
      if depth == 0 then
        before = before:sub(1, i - 1)
        break
      end
      depth = depth - 1
    end
  end
  return before:match('([%w_%-]+)%s*$')
end

--- Build completion items for a given context.
---@param bufnr number
---@param prefix string current prefix being typed
---@param prev_word string|nil previous word on the line
---@return table[] items { word, kind, menu }
local function get_completions(bufnr, prefix, prev_word)
  local sigil = prefix:sub(1, 1)

  -- After @ → directives + builtin functions
  if sigil == '@' then
    return context_items('at', {
      { kw.directives, kind.Keyword, '[directive]' },
      { kw.builtin_functions, kind.Function, '[builtin fn]' },
    })
  end

  -- After $ → builtin vars + user-defined vars
  if sigil == '$' then
    local items = vim.list_extend({}, context_items('var', {
      { kw.builtin_vars, kind.Variable, '[builtin var]' },
    }))
    for _, var in ipairs(scan_defs(bufnr).vars) do
      if not kw.builtin_vars[var] then
        items[#items + 1] = { word = var, kind = kind.Variable, menu = '[user var]' }
      end
    end
    return items
  end

  -- After & → user-defined functions
  if sigil == '&' then
    local items = {}
    for _, func in ipairs(scan_defs(bufnr).funcs) do
      items[#items + 1] = { word = func, kind = kind.Function, menu = '[user fn]' }
    end
    return items
  end

  -- Context-specific completions based on previous word
  if prev_word then
    if prev_word == 'domain' then
      return context_items('domain', { { kw.domains_set, kind.Enum, '[domain]' } })
    end
    if prev_word == 'table' then
      return context_items('table', { { kw.tables_set, kind.Enum, '[table]' } })
    end
    if prev_word == 'chain' or kw.chain_commands[prev_word] then
      return context_items('chain', { { kw.builtin_chains, kind.Constant, '[chain]' } })
    end
    if prev_word == 'policy' then
      return context_items('policy', { { kw.policy_values, kind.Value, '[policy]' } })
    end
    if prev_word == 'mod' or prev_word == 'module' then
      return context_items('module', { { kw.module_names, kind.Module, '[module]' } })
    end
    if prev_word == 'proto' or prev_word == 'protocol' then
      return context_items('proto', { { kw.protocols, kind.Enum, '[protocol]' } })
    end
    if prev_word == 'ctstate' or prev_word == 'ctstatus' then
      return context_items('ctstate', { { kw.conntrack_states, kind.Value, '[state]' } })
    end
    if prev_word == 'tcp-flags' then
      return context_items('tcp-flags', { { kw.tcp_flags, kind.Value, '[flag]' } })
    end
    -- Module params expect user-specific values, no completions
    if kw.module_params[prev_word] then
      return {}
    end
  end

  -- Default: all keywords
  return context_items('default', {
    { kw.location_keywords, kind.Keyword, '[location]' },
    { kw.match_keywords, kind.Keyword, '[match]' },
    { kw.chain_commands, kind.Keyword, '[command]' },
    { kw.targets, kind.Constant, '[target]' },
    { kw.module_params, kind.Property, '[param]' },
  })
end

----------------------------------------------------------------------
-- omnifunc
----------------------------------------------------------------------

--- omnifunc implementation for ferm files.
--- Set via: vim.bo.omnifunc = "v:lua.require'ferm-tools.complete'.omnifunc"
---@param findstart number
---@param base string
---@return number|table
function M.omnifunc(findstart, base)
  local bufnr = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line = vim.api.nvim_buf_get_lines(bufnr, cursor[1] - 1, cursor[1], false)[1] or ''
  local col = cursor[2]

  if findstart == 1 then
    return find_prefix_start(line, col)
  end

  -- findstart == 0: return matches
  local start_col = find_prefix_start(line, col)
  local prefix = base
  local prefix_lower = prefix:lower()
  local plen = #prefix
  local prev_word = get_prev_word(line, start_col)
  local items = get_completions(bufnr, prefix, prev_word)

  local results = {}
  for _, item in ipairs(items) do
    if plen == 0 or item.word:lower():sub(1, plen) == prefix_lower then
      results[#results + 1] = {
        word = item.word,
        kind = item.menu,
        menu = '',
      }
    end
  end

  return results
end

----------------------------------------------------------------------
-- nvim-cmp source
----------------------------------------------------------------------

--- Create an nvim-cmp source.
---@return table source
function M.cmp_source()
  local source = {}

  function source:is_available()
    return vim.bo.filetype == 'ferm' and require('ferm-tools').config.complete.enable
  end

  function source:get_trigger_characters()
    return { '@', '$', '&' }
  end

  function source:get_keyword_pattern()
    return [[\%(\$\|&\|@\)\?\h\w*]]
  end

  function source:complete(params, callback)
    local bufnr = vim.api.nvim_get_current_buf()
    local before = params.context.cursor_before_line
    local start = find_prefix_start(before, #before)
    local prefix = before:sub(start + 1)
    local prev_word = get_prev_word(before, start)
    local completions = get_completions(bufnr, prefix, prev_word)

    local cmp_items = {}
    for _, item in ipairs(completions) do
      cmp_items[#cmp_items + 1] = {
        label = item.word,
        kind = item.kind,
        detail = item.menu,
      }
    end

    callback({ items = cmp_items, isIncomplete = false })
  end

  return source
end

return M
