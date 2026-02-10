local M = {}

local ns = vim.api.nvim_create_namespace('ferm-tools')

local kw = require('ferm-tools.keywords')

--- Highlight a single line in the buffer
---@param bufnr number
---@param lnum number 0-indexed line number
---@param line string
local function highlight_line(bufnr, lnum, line)
  local pos = 1
  local len = #line
  local prev_token = nil

  while pos <= len do
    -- Skip whitespace
    local ws = line:sub(pos):match('^%s+')
    if ws then
      pos = pos + #ws
      if pos > len then break end
    end

    local tail = line:sub(pos)
    local ch = line:sub(pos, pos)

    -- Comment: # to end of line
    if ch == '#' then
      vim.api.nvim_buf_set_extmark(bufnr, ns, lnum, pos - 1, {
        end_col = len,
        hl_group = '@comment',
        priority = 100,
      })
      -- Check for TODO/FIXME/XXX/NOTE in comment
      local comment_text = line:sub(pos)
      for todo in comment_text:gmatch('()TODO') do
        vim.api.nvim_buf_set_extmark(bufnr, ns, lnum, pos - 1 + todo - 1, {
          end_col = pos - 1 + todo - 1 + 4,
          hl_group = '@comment.todo',
          priority = 110,
        })
      end
      for todo in comment_text:gmatch('()FIXME') do
        vim.api.nvim_buf_set_extmark(bufnr, ns, lnum, pos - 1 + todo - 1, {
          end_col = pos - 1 + todo - 1 + 5,
          hl_group = '@comment.todo',
          priority = 110,
        })
      end
      for todo in comment_text:gmatch('()XXX') do
        vim.api.nvim_buf_set_extmark(bufnr, ns, lnum, pos - 1 + todo - 1, {
          end_col = pos - 1 + todo - 1 + 3,
          hl_group = '@comment.todo',
          priority = 110,
        })
      end
      for todo in comment_text:gmatch('()NOTE') do
        vim.api.nvim_buf_set_extmark(bufnr, ns, lnum, pos - 1 + todo - 1, {
          end_col = pos - 1 + todo - 1 + 4,
          hl_group = '@comment.todo',
          priority = 110,
        })
      end
      break
    end

    -- Single-quoted string
    if ch == "'" then
      local end_pos = line:find("'", pos + 1, true)
      if end_pos then
        vim.api.nvim_buf_set_extmark(bufnr, ns, lnum, pos - 1, {
          end_col = end_pos,
          hl_group = '@string',
          priority = 100,
        })
        pos = end_pos + 1
        prev_token = 'string'
        goto continue
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
        vim.api.nvim_buf_set_extmark(bufnr, ns, lnum, pos - 1, {
          end_col = end_pos,
          hl_group = '@string',
          priority = 100,
        })
        pos = end_pos + 1
        prev_token = 'string'
        goto continue
      end
    end

    -- Backtick command substitution
    if ch == '`' then
      local end_pos = line:find('`', pos + 1, true)
      if end_pos then
        vim.api.nvim_buf_set_extmark(bufnr, ns, lnum, pos - 1, {
          end_col = end_pos,
          hl_group = '@string.special',
          priority = 100,
        })
        pos = end_pos + 1
        prev_token = 'backtick'
        goto continue
      end
    end

    -- Variable $NAME
    local var = tail:match('^%$[A-Za-z_][A-Za-z0-9_]*')
    if var then
      local hl = kw.builtin_vars[var] and '@constant.builtin' or '@variable'
      vim.api.nvim_buf_set_extmark(bufnr, ns, lnum, pos - 1, {
        end_col = pos - 1 + #var,
        hl_group = hl,
        priority = 100,
      })
      pos = pos + #var
      prev_token = 'variable'
      goto continue
    end

    -- User function &NAME
    local func = tail:match('^&[A-Za-z_][A-Za-z0-9_]*')
    if func then
      vim.api.nvim_buf_set_extmark(bufnr, ns, lnum, pos - 1, {
        end_col = pos - 1 + #func,
        hl_group = '@function.call',
        priority = 100,
      })
      pos = pos + #func
      prev_token = 'function'
      goto continue
    end

    -- Directive or built-in function (@keyword)
    local at_word = tail:match('^@[A-Za-z_][A-Za-z0-9_]*')
    if at_word then
      local hl
      if kw.directives[at_word] then
        hl = '@keyword.directive'
      elseif kw.builtin_functions[at_word] then
        hl = '@function.builtin'
      else
        hl = '@keyword.directive' -- unknown @ words default to directive
      end
      vim.api.nvim_buf_set_extmark(bufnr, ns, lnum, pos - 1, {
        end_col = pos - 1 + #at_word,
        hl_group = hl,
        priority = 100,
      })
      pos = pos + #at_word
      prev_token = 'directive'
      goto continue
    end

    -- IPv4 address (must check before plain number)
    local ipv4 = tail:match('^%d+%.%d+%.%d+%.%d+/%d+') or tail:match('^%d+%.%d+%.%d+%.%d+')
    if ipv4 then
      vim.api.nvim_buf_set_extmark(bufnr, ns, lnum, pos - 1, {
        end_col = pos - 1 + #ipv4,
        hl_group = '@number',
        priority = 100,
      })
      pos = pos + #ipv4
      prev_token = 'ip'
      goto continue
    end

    -- IPv6 address (simplified: starts with hex digits followed by colon)
    local ipv6 = tail:match('^[0-9a-fA-F:]+::[0-9a-fA-F:]*/%d+')
      or tail:match('^[0-9a-fA-F:]+::[0-9a-fA-F:]*')
      or tail:match('^[0-9a-fA-F]+:[0-9a-fA-F]+:[0-9a-fA-F:]+/%d+')
      or tail:match('^[0-9a-fA-F]+:[0-9a-fA-F]+:[0-9a-fA-F:]+')
    if ipv6 and ipv6:find(':') then
      -- Make sure it's a plausible IPv6 (at least 2 colons or ::)
      local _, colon_count = ipv6:gsub(':', ':')
      if colon_count >= 2 or ipv6:find('::') then
        vim.api.nvim_buf_set_extmark(bufnr, ns, lnum, pos - 1, {
          end_col = pos - 1 + #ipv6,
          hl_group = '@number',
          priority = 100,
        })
        pos = pos + #ipv6
        prev_token = 'ip'
        goto continue
      end
    end

    -- Hex number
    local hex = tail:match('^0x[0-9a-fA-F]+')
    if hex then
      vim.api.nvim_buf_set_extmark(bufnr, ns, lnum, pos - 1, {
        end_col = pos - 1 + #hex,
        hl_group = '@number',
        priority = 100,
      })
      pos = pos + #hex
      prev_token = 'number'
      goto continue
    end

    -- Word token (identifier-like, including hyphens for params like log-prefix)
    local word = tail:match('^[A-Za-z_][A-Za-z0-9_%-]*')
    if word then
      local hl = nil

      if prev_token == 'jump_goto' then
        -- After jump/goto, highlight chain name
        hl = '@label'
      elseif prev_token == 'module' then
        -- After mod/module keyword, highlight module name
        if kw.module_names[word] then
          hl = '@type'
        end
      elseif word == 'jump' or word == 'goto' or word == 'realgoto' then
        hl = '@function.macro'
        prev_token = 'jump_goto'
        vim.api.nvim_buf_set_extmark(bufnr, ns, lnum, pos - 1, {
          end_col = pos - 1 + #word,
          hl_group = hl,
          priority = 100,
        })
        pos = pos + #word
        goto continue
      elseif kw.location_keywords[word] then
        hl = '@keyword'
      elseif kw.match_keywords[word] then
        hl = '@keyword'
        if word == 'mod' or word == 'module' then
          prev_token = 'module'
          vim.api.nvim_buf_set_extmark(bufnr, ns, lnum, pos - 1, {
            end_col = pos - 1 + #word,
            hl_group = hl,
            priority = 100,
          })
          pos = pos + #word
          goto continue
        end
      elseif kw.targets[word] then
        hl = '@function.macro'
      elseif kw.builtin_chains[word] then
        hl = '@constant'
      elseif kw.conntrack_states[word] then
        hl = '@constant'
      elseif kw.tcp_flags[word] then
        hl = '@constant'
      elseif kw.tables_set[word] then
        hl = '@type'
      elseif kw.domains_set[word] then
        hl = '@type'
      elseif kw.protocols[word] then
        hl = '@type'
      elseif kw.module_params[word] then
        hl = '@property'
      end

      if hl then
        vim.api.nvim_buf_set_extmark(bufnr, ns, lnum, pos - 1, {
          end_col = pos - 1 + #word,
          hl_group = hl,
          priority = 100,
        })
      end

      pos = pos + #word
      if prev_token ~= 'module' and prev_token ~= 'jump_goto' then
        prev_token = 'word'
      end
      goto continue
    end

    -- Decimal number (after word check to avoid matching parts of identifiers)
    local num = tail:match('^%d+')
    if num then
      vim.api.nvim_buf_set_extmark(bufnr, ns, lnum, pos - 1, {
        end_col = pos - 1 + #num,
        hl_group = '@number',
        priority = 100,
      })
      pos = pos + #num
      prev_token = 'number'
      goto continue
    end

    -- Single-char tokens
    if ch == '!' then
      vim.api.nvim_buf_set_extmark(bufnr, ns, lnum, pos - 1, {
        end_col = pos,
        hl_group = '@operator',
        priority = 100,
      })
    elseif ch == ';' then
      vim.api.nvim_buf_set_extmark(bufnr, ns, lnum, pos - 1, {
        end_col = pos,
        hl_group = '@punctuation.delimiter',
        priority = 100,
      })
    elseif ch == '{' or ch == '}' then
      vim.api.nvim_buf_set_extmark(bufnr, ns, lnum, pos - 1, {
        end_col = pos,
        hl_group = '@punctuation.bracket',
        priority = 100,
      })
    elseif ch == '(' or ch == ')' then
      vim.api.nvim_buf_set_extmark(bufnr, ns, lnum, pos - 1, {
        end_col = pos,
        hl_group = '@punctuation.bracket',
        priority = 100,
      })
    end

    pos = pos + 1
    prev_token = nil

    ::continue::
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
        M.highlight_range(buf, first, last_new)
      end)
    end,
    on_detach = function(_, buf)
      vim.b[buf]._ferm_tools_attached = nil
    end,
  })
end

return M
