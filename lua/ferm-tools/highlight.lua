local M = {}

local ns = vim.api.nvim_create_namespace('ferm-tools')

local kw = require('ferm-tools.keywords')
local lexer = require('ferm-tools.lexer')

--- Direct token type → highlight group mapping
local token_hl = {
  comment = '@comment',
  string = '@string',
  unclosed_string = '@string',
  backtick = '@string.special',
  unclosed_backtick = '@string.special',
  ['function'] = '@function.call',
  directive = '@keyword.directive',
  builtin_func = '@function.builtin',
  ipv4 = '@number',
  ipv6 = '@number',
  hex = '@number',
  number = '@number',
  operator = '@operator',
  semicolon = '@punctuation.delimiter',
  brace_open = '@punctuation.bracket',
  brace_close = '@punctuation.bracket',
  paren_open = '@punctuation.bracket',
  paren_close = '@punctuation.bracket',
}

local todo_words = { 'TODO', 'FIXME', 'XXX', 'NOTE' }

--- Highlight group for a word token, given line context.
---@param word string
---@param prev string|nil context state ('module', 'jump_goto', or nil)
---@return string|nil
local function word_hl(word, prev)
  if prev == 'jump_goto' then
    return '@label'
  end
  if prev == 'module' then
    return kw.module_names[word] and '@type' or nil
  end
  if kw.chain_commands[word] then
    return '@function.macro'
  end
  if kw.location_keywords[word] or kw.match_keywords[word] then
    return '@keyword'
  end
  if kw.targets[word] then
    return '@function.macro'
  end
  if kw.builtin_chains[word] or kw.conntrack_states[word] or kw.tcp_flags[word] then
    return '@constant'
  end
  if kw.tables_set[word] or kw.domains_set[word] or kw.protocols[word] then
    return '@type'
  end
  if kw.module_params[word] then
    return '@property'
  end
  return nil
end

--- Highlight a single line in the buffer
---@param bufnr number
---@param lnum number 0-indexed line number
---@param line string
local function highlight_line(bufnr, lnum, line)
  local state = nil

  for _, tok in ipairs(lexer.tokenize_line(lnum, line)) do
    local hl
    if tok.type == 'word' then
      hl = word_hl(tok.value, state)
      if state == 'module' or state == 'jump_goto' then
        -- The module/chain name consumed the context
        state = nil
      elseif tok.value == 'mod' or tok.value == 'module' then
        state = 'module'
      elseif kw.chain_commands[tok.value] then
        state = 'jump_goto'
      end
    elseif tok.type == 'variable' then
      hl = kw.builtin_vars[tok.value] and '@constant.builtin' or '@variable'
      state = nil
    else
      hl = token_hl[tok.type]
      state = nil
    end

    if hl then
      vim.api.nvim_buf_set_extmark(bufnr, ns, lnum, tok.col, {
        end_col = tok.end_col,
        hl_group = hl,
        priority = 100,
      })
    end

    -- TODO/FIXME/XXX/NOTE markers inside comments
    if tok.type == 'comment' then
      for _, word in ipairs(todo_words) do
        local init = 1
        while true do
          local s, e = tok.value:find(word, init, true)
          if not s then break end
          vim.api.nvim_buf_set_extmark(bufnr, ns, lnum, tok.col + s - 1, {
            end_col = tok.col + e,
            hl_group = '@comment.todo',
            priority = 110,
          })
          init = e + 1
        end
      end
    end
  end
end

--- Highlight a range of lines in the buffer
---@param bufnr number
---@param first number 0-indexed first line
---@param last number 0-indexed last line (exclusive)
function M.highlight_range(bufnr, first, last)
  local lines = vim.api.nvim_buf_get_lines(bufnr, first, last, false)
  -- Clear existing highlights in this range
  vim.api.nvim_buf_clear_namespace(bufnr, ns, first, last)
  for i, line in ipairs(lines) do
    highlight_line(bufnr, first + i - 1, line)
  end
end

--- Highlight the entire buffer
---@param bufnr number
function M.highlight_buf(bufnr)
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  M.highlight_range(bufnr, 0, line_count)
end

--- Attach the highlighter to a buffer
---@param bufnr number
function M.attach(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  -- Avoid double-attach
  if vim.b[bufnr]._ferm_tools_attached then
    return
  end
  vim.b[bufnr]._ferm_tools_attached = true

  -- Initial full highlight
  M.highlight_buf(bufnr)

  -- Attach for incremental updates
  vim.api.nvim_buf_attach(bufnr, false, {
    on_lines = function(_, buf, _, first, _last_old, last_new)
      -- Schedule to avoid issues during fast typing
      vim.schedule(function()
        if not vim.api.nvim_buf_is_valid(buf) then
          return
        end
        -- The buffer may have changed again before this runs; clamp the range
        local line_count = vim.api.nvim_buf_line_count(buf)
        local first_c = math.min(first, line_count)
        local last_c = math.min(last_new, line_count)
        if first_c < last_c then
          M.highlight_range(buf, first_c, last_c)
        end
      end)
    end,
    on_detach = function(_, buf)
      vim.b[buf]._ferm_tools_attached = nil
    end,
  })
end

return M
