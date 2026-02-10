local M = {}

local kw = require('ferm-tools.keywords')

--- LSP CompletionItemKind values
local kind = {
  Text = 1,
  Method = 2,
  Function = 3,
  Field = 4,
  Variable = 6,
  Class = 7,
  Module = 9,
  Property = 10,
  Unit = 11,
  Value = 12,
  Enum = 13,
  Keyword = 14,
  Constant = 21,
  TypeParameter = 25,
}

--- Convert a set-table (key=true) into a sorted list of keys.
---@param tbl table<string, boolean>
---@return string[]
local function sorted_keys(tbl)
  local keys = {}
  for k in pairs(tbl) do
    keys[#keys + 1] = k
  end
  table.sort(keys)
  return keys
end

--- Scan buffer for user-defined variables (@def $VAR ...).
---@param bufnr number
---@return string[]
local function scan_user_vars(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local vars = {}
  local seen = {}
  for _, line in ipairs(lines) do
    for var in line:gmatch('@def%s+(%$[A-Za-z_][A-Za-z0-9_]*)') do
      if not seen[var] then
        seen[var] = true
        vars[#vars + 1] = var
      end
    end
  end
  table.sort(vars)
  return vars
end

--- Scan buffer for user-defined functions (@def &FUNC ...).
---@param bufnr number
---@return string[]
local function scan_user_funcs(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local funcs = {}
  local seen = {}
  for _, line in ipairs(lines) do
    for func in line:gmatch('@def%s+(&[A-Za-z_][A-Za-z0-9_]*)') do
      if not seen[func] then
        seen[func] = true
        funcs[#funcs + 1] = func
      end
    end
  end
  table.sort(funcs)
  return funcs
end

--- Get the word before the cursor on the current line.
---@param line_text string
---@param col number 0-indexed cursor column
---@return string|nil prev_word the previous keyword before cursor
local function get_prev_word(line_text, col)
  -- Get text before cursor, strip trailing partial word
  local before = line_text:sub(1, col)
  -- Remove any partial word at cursor
  before = before:gsub('[%w_%-@$&]*$', '')
  -- Get last word
  local prev = before:match('([%w_%-]+)%s*$')
  return prev
end

--- Build completion items for a given context.
---@param bufnr number
---@param prefix string current prefix being typed
---@param prev_word string|nil previous word on the line
---@return table[] items { word, kind, menu, info? }
local function get_completions(bufnr, prefix, prev_word)
  local items = {}

  -- After @ → directives + builtin functions
  if prefix:sub(1, 1) == '@' then
    for _, key in ipairs(sorted_keys(kw.directives)) do
      items[#items + 1] = { word = key, kind = kind.Keyword, menu = '[directive]' }
    end
    for _, key in ipairs(sorted_keys(kw.builtin_functions)) do
      items[#items + 1] = { word = key, kind = kind.Function, menu = '[builtin fn]' }
    end
    return items
  end

  -- After $ → builtin vars + user-defined vars
  if prefix:sub(1, 1) == '$' then
    for _, key in ipairs(sorted_keys(kw.builtin_vars)) do
      items[#items + 1] = { word = key, kind = kind.Variable, menu = '[builtin var]' }
    end
    for _, var in ipairs(scan_user_vars(bufnr)) do
      if not kw.builtin_vars[var] then
        items[#items + 1] = { word = var, kind = kind.Variable, menu = '[user var]' }
      end
    end
    return items
  end

  -- After & → user-defined functions
  if prefix:sub(1, 1) == '&' then
    for _, func in ipairs(scan_user_funcs(bufnr)) do
      items[#items + 1] = { word = func, kind = kind.Function, menu = '[user fn]' }
    end
    return items
  end

  -- Context-specific completions based on previous word
  if prev_word then
    -- After domain → domain names
    if prev_word == 'domain' then
      for _, key in ipairs(sorted_keys(kw.domains_set)) do
        items[#items + 1] = { word = key, kind = kind.Enum, menu = '[domain]' }
      end
      return items
    end

    -- After table → table names
    if prev_word == 'table' then
      for _, key in ipairs(sorted_keys(kw.tables_set)) do
        items[#items + 1] = { word = key, kind = kind.Enum, menu = '[table]' }
      end
      return items
    end

    -- After chain → builtin chains
    if prev_word == 'chain' then
      for _, key in ipairs(sorted_keys(kw.builtin_chains)) do
        items[#items + 1] = { word = key, kind = kind.Constant, menu = '[chain]' }
      end
      return items
    end

    -- After policy → ACCEPT, DROP
    if prev_word == 'policy' then
      items[#items + 1] = { word = 'ACCEPT', kind = kind.Value, menu = '[policy]' }
      items[#items + 1] = { word = 'DROP', kind = kind.Value, menu = '[policy]' }
      return items
    end

    -- After mod/module → module names
    if prev_word == 'mod' or prev_word == 'module' then
      for _, key in ipairs(sorted_keys(kw.module_names)) do
        items[#items + 1] = { word = key, kind = kind.Module, menu = '[module]' }
      end
      return items
    end

    -- After proto/protocol → protocol names
    if prev_word == 'proto' or prev_word == 'protocol' then
      for _, key in ipairs(sorted_keys(kw.protocols)) do
        items[#items + 1] = { word = key, kind = kind.Enum, menu = '[protocol]' }
      end
      return items
    end

    -- After ctstate → conntrack states
    if prev_word == 'ctstate' or prev_word == 'ctstatus' then
      for _, key in ipairs(sorted_keys(kw.conntrack_states)) do
        items[#items + 1] = { word = key, kind = kind.Value, menu = '[state]' }
      end
      return items
    end

    -- After tcp-flags → tcp flags
    if prev_word == 'tcp-flags' then
      for _, key in ipairs(sorted_keys(kw.tcp_flags)) do
        items[#items + 1] = { word = key, kind = kind.Value, menu = '[flag]' }
      end
      return items
    end

    -- After a module param keyword → no specific values, fall through to default
    if kw.module_params[prev_word] then
      -- Module params expect user-specific values, no completions
      return items
    end
  end

  -- Default: all keywords
  for _, key in ipairs(sorted_keys(kw.location_keywords)) do
    items[#items + 1] = { word = key, kind = kind.Keyword, menu = '[location]' }
  end
  for _, key in ipairs(sorted_keys(kw.match_keywords)) do
    items[#items + 1] = { word = key, kind = kind.Keyword, menu = '[match]' }
  end
  for _, key in ipairs(sorted_keys(kw.targets)) do
    items[#items + 1] = { word = key, kind = kind.Constant, menu = '[target]' }
  end
  for _, key in ipairs(sorted_keys(kw.module_params)) do
    items[#items + 1] = { word = key, kind = kind.Property, menu = '[param]' }
  end

  return items
end

----------------------------------------------------------------------
-- omnifunc
----------------------------------------------------------------------

--- omnifunc implementation for ferm files.
--- Set via: vim.bo.omnifunc = "v:lua.require('ferm-tools.complete').omnifunc()"
---@param findstart number
---@param base string
---@return number|table
function M.omnifunc(findstart, base)
  local bufnr = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line = vim.api.nvim_buf_get_lines(bufnr, cursor[1] - 1, cursor[1], false)[1] or ''
  local col = cursor[2]

  if findstart == 1 then
    -- Find the start of the completion word
    local start = col
    while start > 0 do
      local c = line:sub(start, start)
      if c:match('[%w_%-@$&]') then
        start = start - 1
      else
        break
      end
    end
    return start
  end

  -- findstart == 0: return matches
  local start_col = col
  while start_col > 0 do
    local c = line:sub(start_col, start_col)
    if c:match('[%w_%-@$&]') then
      start_col = start_col - 1
    else
      break
    end
  end

  local prefix = base
  local prev_word = get_prev_word(line, start_col)
  local items = get_completions(bufnr, prefix, prev_word)

  local results = {}
  for _, item in ipairs(items) do
    if prefix == '' or item.word:sub(1, #prefix) == prefix or item.word:lower():sub(1, #prefix:lower()) == prefix:lower() then
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
    return vim.bo.filetype == 'ferm'
  end

  function source:get_trigger_characters()
    return { '@', '$', '&' }
  end

  function source:get_keyword_pattern()
    return [[\%(\$\|&\|@\)\?\h\w*]]
  end

  function source:complete(params, callback)
    local bufnr = vim.api.nvim_get_current_buf()
    local cursor = params.context.cursor
    local line = params.context.cursor_line
    local col = cursor.col

    -- Find prefix start
    local start = col
    while start > 0 do
      local c = line:sub(start, start)
      if c:match('[%w_%-@$&]') then
        start = start - 1
      else
        break
      end
    end

    local prefix = line:sub(start + 1, col)
    local prev_word = get_prev_word(line, start)
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
