local M = {}

local kw = require('ferm-tools.keywords')
local ns = vim.api.nvim_create_namespace('ferm-tools-lint')

--- Tokenize a single line into structured tokens
---@param lnum number 0-indexed line number
---@param line string
---@return table[] tokens
local function tokenize_line(lnum, line)
  local tokens = {}
  local pos = 1
  local len = #line

  while pos <= len do
    -- Skip whitespace
    local ws = line:sub(pos):match('^%s+')
    if ws then
      pos = pos + #ws
      if pos > len then break end
    end

    local tail = line:sub(pos)
    local ch = line:sub(pos, pos)

    -- Comment
    if ch == '#' then
      tokens[#tokens + 1] = {
        type = 'comment', value = line:sub(pos),
        lnum = lnum, col = pos - 1, end_col = len,
      }
      break
    end

    -- Single-quoted string
    if ch == "'" then
      local end_pos = line:find("'", pos + 1, true)
      if end_pos then
        tokens[#tokens + 1] = {
          type = 'string', value = line:sub(pos, end_pos),
          lnum = lnum, col = pos - 1, end_col = end_pos,
        }
        pos = end_pos + 1
        goto continue
      else
        tokens[#tokens + 1] = {
          type = 'unclosed_string', value = line:sub(pos),
          lnum = lnum, col = pos - 1, end_col = len,
        }
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
        tokens[#tokens + 1] = {
          type = 'string', value = line:sub(pos, end_pos),
          lnum = lnum, col = pos - 1, end_col = end_pos,
        }
        pos = end_pos + 1
        goto continue
      else
        tokens[#tokens + 1] = {
          type = 'unclosed_string', value = line:sub(pos),
          lnum = lnum, col = pos - 1, end_col = len,
        }
        break
      end
    end

    -- Backtick command substitution
    if ch == '`' then
      local end_pos = line:find('`', pos + 1, true)
      if end_pos then
        tokens[#tokens + 1] = {
          type = 'backtick', value = line:sub(pos, end_pos),
          lnum = lnum, col = pos - 1, end_col = end_pos,
        }
        pos = end_pos + 1
        goto continue
      else
        tokens[#tokens + 1] = {
          type = 'unclosed_backtick', value = line:sub(pos),
          lnum = lnum, col = pos - 1, end_col = len,
        }
        break
      end
    end

    -- Variable $NAME
    local var = tail:match('^%$[A-Za-z_][A-Za-z0-9_]*')
    if var then
      tokens[#tokens + 1] = {
        type = 'variable', value = var,
        lnum = lnum, col = pos - 1, end_col = pos - 1 + #var,
      }
      pos = pos + #var
      goto continue
    end

    -- User function &NAME
    local func = tail:match('^&[A-Za-z_][A-Za-z0-9_]*')
    if func then
      tokens[#tokens + 1] = {
        type = 'function', value = func,
        lnum = lnum, col = pos - 1, end_col = pos - 1 + #func,
      }
      pos = pos + #func
      goto continue
    end

    -- Directive or builtin function (@keyword)
    local at_word = tail:match('^@[A-Za-z_][A-Za-z0-9_]*')
    if at_word then
      local typ
      if kw.directives[at_word] then
        typ = 'directive'
      elseif kw.builtin_functions[at_word] then
        typ = 'builtin_func'
      else
        typ = 'directive' -- unknown @word, will be flagged by lint
      end
      tokens[#tokens + 1] = {
        type = typ, value = at_word,
        lnum = lnum, col = pos - 1, end_col = pos - 1 + #at_word,
      }
      pos = pos + #at_word
      goto continue
    end

    -- IPv4 address (must check before plain number)
    local ipv4 = tail:match('^%d+%.%d+%.%d+%.%d+/%d+') or tail:match('^%d+%.%d+%.%d+%.%d+')
    if ipv4 then
      tokens[#tokens + 1] = {
        type = 'ipv4', value = ipv4,
        lnum = lnum, col = pos - 1, end_col = pos - 1 + #ipv4,
      }
      pos = pos + #ipv4
      goto continue
    end

    -- IPv6 address
    local ipv6 = tail:match('^[0-9a-fA-F:]+::[0-9a-fA-F:]*/%d+')
      or tail:match('^[0-9a-fA-F:]+::[0-9a-fA-F:]*')
      or tail:match('^[0-9a-fA-F]+:[0-9a-fA-F]+:[0-9a-fA-F:]+/%d+')
      or tail:match('^[0-9a-fA-F]+:[0-9a-fA-F]+:[0-9a-fA-F:]+')
    if ipv6 and ipv6:find(':') then
      local _, colon_count = ipv6:gsub(':', ':')
      if colon_count >= 2 or ipv6:find('::') then
        tokens[#tokens + 1] = {
          type = 'ipv6', value = ipv6,
          lnum = lnum, col = pos - 1, end_col = pos - 1 + #ipv6,
        }
        pos = pos + #ipv6
        goto continue
      end
    end

    -- Hex number
    local hex = tail:match('^0x[0-9a-fA-F]+')
    if hex then
      tokens[#tokens + 1] = {
        type = 'hex', value = hex,
        lnum = lnum, col = pos - 1, end_col = pos - 1 + #hex,
      }
      pos = pos + #hex
      goto continue
    end

    -- Word token
    local word = tail:match('^[A-Za-z_][A-Za-z0-9_%-]*')
    if word then
      tokens[#tokens + 1] = {
        type = 'word', value = word,
        lnum = lnum, col = pos - 1, end_col = pos - 1 + #word,
      }
      pos = pos + #word
      goto continue
    end

    -- Decimal number
    local num = tail:match('^%d+')
    if num then
      tokens[#tokens + 1] = {
        type = 'number', value = num,
        lnum = lnum, col = pos - 1, end_col = pos - 1 + #num,
      }
      pos = pos + #num
      goto continue
    end

    -- Single-char tokens
    if ch == '!' then
      tokens[#tokens + 1] = {
        type = 'operator', value = ch,
        lnum = lnum, col = pos - 1, end_col = pos,
      }
    elseif ch == ';' then
      tokens[#tokens + 1] = {
        type = 'semicolon', value = ch,
        lnum = lnum, col = pos - 1, end_col = pos,
      }
    elseif ch == '{' then
      tokens[#tokens + 1] = {
        type = 'brace_open', value = ch,
        lnum = lnum, col = pos - 1, end_col = pos,
      }
    elseif ch == '}' then
      tokens[#tokens + 1] = {
        type = 'brace_close', value = ch,
        lnum = lnum, col = pos - 1, end_col = pos,
      }
    elseif ch == '(' then
      tokens[#tokens + 1] = {
        type = 'paren_open', value = ch,
        lnum = lnum, col = pos - 1, end_col = pos,
      }
    elseif ch == ')' then
      tokens[#tokens + 1] = {
        type = 'paren_close', value = ch,
        lnum = lnum, col = pos - 1, end_col = pos,
      }
    end

    pos = pos + 1
    ::continue::
  end

  return tokens
end

--- Tokenize all lines in the buffer
---@param lines string[]
---@return table[] tokens
local function tokenize(lines)
  local all = {}
  for i, line in ipairs(lines) do
    local line_tokens = tokenize_line(i - 1, line)
    for _, tok in ipairs(line_tokens) do
      all[#all + 1] = tok
    end
  end
  return all
end

--- Collect variable and function definitions from tokens
---@param tokens table[]
---@return table defs { vars = set, funcs = set, dup_vars = list }
local function collect_definitions(tokens)
  local defs = { vars = {}, funcs = {}, dup_vars = {} }
  for i, tok in ipairs(tokens) do
    if tok.type == 'directive' and tok.value == '@def' then
      local next_tok = tokens[i + 1]
      if next_tok then
        if next_tok.type == 'variable' then
          if defs.vars[next_tok.value] then
            defs.dup_vars[#defs.dup_vars + 1] = next_tok
          end
          defs.vars[next_tok.value] = true
        elseif next_tok.type == 'function' then
          defs.funcs[next_tok.value] = true
        end
      end
    end
  end
  return defs
end

--- Check brace and paren matching (Rules 1, 11)
---@param tokens table[]
---@return table[] diagnostics
local function check_structure(tokens)
  local diags = {}
  local brace_stack = {}
  local paren_stack = {}

  for _, tok in ipairs(tokens) do
    if tok.type == 'brace_open' then
      brace_stack[#brace_stack + 1] = tok
    elseif tok.type == 'brace_close' then
      if #brace_stack == 0 then
        diags[#diags + 1] = {
          lnum = tok.lnum,
          col = tok.col,
          end_col = tok.end_col,
          severity = vim.diagnostic.severity.ERROR,
          message = 'Unmatched closing brace',
          source = 'ferm-tools',
          code = 'unmatched-brace',
        }
      else
        table.remove(brace_stack)
      end
    elseif tok.type == 'paren_open' then
      paren_stack[#paren_stack + 1] = tok
    elseif tok.type == 'paren_close' then
      if #paren_stack == 0 then
        diags[#diags + 1] = {
          lnum = tok.lnum,
          col = tok.col,
          end_col = tok.end_col,
          severity = vim.diagnostic.severity.ERROR,
          message = 'Unmatched closing parenthesis',
          source = 'ferm-tools',
          code = 'unmatched-paren',
        }
      else
        table.remove(paren_stack)
      end
    end

    -- Rule 12: unclosed-string
    if tok.type == 'unclosed_string' then
      diags[#diags + 1] = {
        lnum = tok.lnum,
        col = tok.col,
        end_col = tok.end_col,
        severity = vim.diagnostic.severity.ERROR,
        message = 'Unclosed string',
        source = 'ferm-tools',
        code = 'unclosed-string',
      }
    end

    -- Rule 13: unclosed-backtick
    if tok.type == 'unclosed_backtick' then
      diags[#diags + 1] = {
        lnum = tok.lnum,
        col = tok.col,
        end_col = tok.end_col,
        severity = vim.diagnostic.severity.ERROR,
        message = 'Unclosed backtick command substitution',
        source = 'ferm-tools',
        code = 'unclosed-backtick',
      }
    end
  end

  for _, tok in ipairs(brace_stack) do
    diags[#diags + 1] = {
      lnum = tok.lnum,
      col = tok.col,
      end_col = tok.end_col,
      severity = vim.diagnostic.severity.ERROR,
      message = 'Unmatched opening brace',
      source = 'ferm-tools',
      code = 'unmatched-brace',
    }
  end

  for _, tok in ipairs(paren_stack) do
    diags[#diags + 1] = {
      lnum = tok.lnum,
      col = tok.col,
      end_col = tok.end_col,
      severity = vim.diagnostic.severity.ERROR,
      message = 'Unmatched opening parenthesis',
      source = 'ferm-tools',
      code = 'unmatched-paren',
    }
  end

  return diags
end

--- Check semantic rules (Rules 2–10)
---@param tokens table[]
---@param defs table
---@return table[] diagnostics
local function check_semantics(tokens, defs)
  local diags = {}

  for i, tok in ipairs(tokens) do
    -- Rule 2: undefined-variable
    if tok.type == 'variable' then
      -- Skip if this variable is being defined (preceded by @def)
      local prev = tokens[i - 1]
      local is_definition = prev and prev.type == 'directive' and prev.value == '@def'
      -- Skip if it's a function parameter (inside parens after &func definition)
      if not is_definition and not kw.builtin_vars[tok.value] and not defs.vars[tok.value] then
        diags[#diags + 1] = {
          lnum = tok.lnum,
          col = tok.col,
          end_col = tok.end_col,
          severity = vim.diagnostic.severity.WARN,
          message = string.format('Undefined variable: %s', tok.value),
          source = 'ferm-tools',
          code = 'undefined-variable',
        }
      end
    end

    -- Rule 3: unknown-directive
    if tok.type == 'directive' then
      if not kw.directives[tok.value] and not kw.builtin_functions[tok.value] then
        diags[#diags + 1] = {
          lnum = tok.lnum,
          col = tok.col,
          end_col = tok.end_col,
          severity = vim.diagnostic.severity.ERROR,
          message = string.format('Unknown directive: %s', tok.value),
          source = 'ferm-tools',
          code = 'unknown-directive',
        }
      end
    end

    -- Context-dependent rules: look at previous non-comment tokens
    if tok.type == 'word' then
      local prev = tokens[i - 1]

      -- Rule 4: invalid-table
      if prev and prev.type == 'word' and prev.value == 'table' then
        if not kw.tables_set[tok.value] then
          diags[#diags + 1] = {
            lnum = tok.lnum,
            col = tok.col,
            end_col = tok.end_col,
            severity = vim.diagnostic.severity.ERROR,
            message = string.format('Invalid table name: %s (expected: filter, nat, mangle, raw, security)', tok.value),
            source = 'ferm-tools',
            code = 'invalid-table',
          }
        end
      end

      -- Rule 5: invalid-domain
      if prev and prev.type == 'word' and prev.value == 'domain' then
        if not kw.domains_set[tok.value] then
          diags[#diags + 1] = {
            lnum = tok.lnum,
            col = tok.col,
            end_col = tok.end_col,
            severity = vim.diagnostic.severity.ERROR,
            message = string.format('Invalid domain: %s (expected: ip, ip6, arp, eb)', tok.value),
            source = 'ferm-tools',
            code = 'invalid-domain',
          }
        end
      end

      -- Rule 6: unknown-module
      if prev and prev.type == 'word' and (prev.value == 'mod' or prev.value == 'module') then
        if not kw.module_names[tok.value] then
          diags[#diags + 1] = {
            lnum = tok.lnum,
            col = tok.col,
            end_col = tok.end_col,
            severity = vim.diagnostic.severity.WARN,
            message = string.format('Unknown module: %s', tok.value),
            source = 'ferm-tools',
            code = 'unknown-module',
          }
        end
      end

      -- Rule 7: policy-on-custom-chain
      if tok.value == 'policy' then
        -- Walk backward to find the chain name
        local chain_name = nil
        for j = i - 1, 1, -1 do
          if tokens[j].type == 'word' and tokens[j].value == 'chain' then
            local next_after_chain = tokens[j + 1]
            if next_after_chain and next_after_chain.type == 'word' then
              chain_name = next_after_chain.value
            end
            break
          end
          -- Stop if we hit a brace (different scope)
          if tokens[j].type == 'brace_open' then
            -- Check the token before this brace for chain context
            for k = j - 1, 1, -1 do
              if tokens[k].type == 'word' and tokens[k].value == 'chain' then
                local next_after_chain = tokens[k + 1]
                if next_after_chain and next_after_chain.type == 'word' then
                  chain_name = next_after_chain.value
                end
                break
              end
              if tokens[k].type == 'brace_open' or tokens[k].type == 'brace_close' then
                break
              end
            end
            break
          end
        end
        if chain_name and not kw.builtin_chains[chain_name] then
          diags[#diags + 1] = {
            lnum = tok.lnum,
            col = tok.col,
            end_col = tok.end_col,
            severity = vim.diagnostic.severity.ERROR,
            message = string.format('Cannot set policy on custom chain: %s', chain_name),
            source = 'ferm-tools',
            code = 'policy-on-custom-chain',
          }
        end
      end

      -- Rule 8: invalid-policy-value
      if prev and prev.type == 'word' and prev.value == 'policy' then
        if tok.value ~= 'ACCEPT' and tok.value ~= 'DROP' then
          diags[#diags + 1] = {
            lnum = tok.lnum,
            col = tok.col,
            end_col = tok.end_col,
            severity = vim.diagnostic.severity.ERROR,
            message = string.format('Invalid policy value: %s (expected: ACCEPT or DROP)', tok.value),
            source = 'ferm-tools',
            code = 'invalid-policy-value',
          }
        end
      end
    end

    -- Rule 9: invalid-ipv4
    if tok.type == 'ipv4' then
      local addr, cidr = tok.value:match('^(.+)/(%d+)$')
      if not addr then
        addr = tok.value
      end
      -- Check octets
      local valid = true
      for octet_str in addr:gmatch('(%d+)') do
        local octet = tonumber(octet_str)
        if octet > 255 then
          valid = false
          break
        end
      end
      if not valid then
        diags[#diags + 1] = {
          lnum = tok.lnum,
          col = tok.col,
          end_col = tok.end_col,
          severity = vim.diagnostic.severity.ERROR,
          message = string.format('Invalid IPv4 address: octet > 255 in %s', tok.value),
          source = 'ferm-tools',
          code = 'invalid-ipv4',
        }
      end
      if cidr then
        local prefix = tonumber(cidr)
        if prefix > 32 then
          diags[#diags + 1] = {
            lnum = tok.lnum,
            col = tok.col,
            end_col = tok.end_col,
            severity = vim.diagnostic.severity.ERROR,
            message = string.format('Invalid IPv4 CIDR prefix: /%s (max 32)', cidr),
            source = 'ferm-tools',
            code = 'invalid-ipv4',
          }
        end
      end
    end

    -- Rule 10: invalid-ipv6-cidr
    if tok.type == 'ipv6' then
      local _, cidr = tok.value:match('^(.+)/(%d+)$')
      if cidr then
        local prefix = tonumber(cidr)
        if prefix > 128 then
          diags[#diags + 1] = {
            lnum = tok.lnum,
            col = tok.col,
            end_col = tok.end_col,
            severity = vim.diagnostic.severity.ERROR,
            message = string.format('Invalid IPv6 CIDR prefix: /%s (max 128)', cidr),
            source = 'ferm-tools',
            code = 'invalid-ipv6-cidr',
          }
        end
      end
    end

    -- Rule 14: invalid-port
    if tok.type == 'number' then
      local prev = tokens[i - 1]
      if prev and prev.type == 'word'
        and (prev.value == 'dport' or prev.value == 'sport'
          or prev.value == 'dports' or prev.value == 'sports') then
        local port = tonumber(tok.value)
        if port > 65535 then
          diags[#diags + 1] = {
            lnum = tok.lnum,
            col = tok.col,
            end_col = tok.end_col,
            severity = vim.diagnostic.severity.ERROR,
            message = string.format('Invalid port number: %s (max 65535)', tok.value),
            source = 'ferm-tools',
            code = 'invalid-port',
          }
        end
      end
    end
  end

  return diags
end

--- Check for missing semicolons (Rule 16)
--- A target at the end of a line (last non-comment token) without a trailing semicolon.
---@param tokens table[]
---@return table[] diagnostics
local function check_missing_semicolons(tokens)
  local diags = {}

  -- Group tokens by line
  local lines = {}
  for _, tok in ipairs(tokens) do
    if not lines[tok.lnum] then
      lines[tok.lnum] = {}
    end
    local line = lines[tok.lnum]
    line[#line + 1] = tok
  end

  for _, line_tokens in pairs(lines) do
    -- Find last non-comment token on this line
    local last = nil
    for j = #line_tokens, 1, -1 do
      if line_tokens[j].type ~= 'comment' then
        last = line_tokens[j]
        break
      end
    end
    if last and last.type == 'word' and kw.targets[last.value] then
      -- Check that the next token isn't a semicolon (could be on the same line)
      local has_semi = false
      for _, t in ipairs(line_tokens) do
        if t.type == 'semicolon' then
          has_semi = true
          break
        end
      end
      if not has_semi then
        diags[#diags + 1] = {
          lnum = last.lnum,
          col = last.col,
          end_col = last.end_col,
          severity = vim.diagnostic.severity.WARN,
          message = string.format('Missing semicolon after %s', last.value),
          source = 'ferm-tools',
          code = 'missing-semicolon',
        }
      end
    end
  end

  return diags
end

--- Run all lint checks on buffer
---@param bufnr number
local function lint_buf(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local tokens = tokenize(lines)
  local defs = collect_definitions(tokens)
  local diags = {}

  -- Structural checks (braces, parens, unclosed strings/backticks)
  local struct_diags = check_structure(tokens)
  for _, d in ipairs(struct_diags) do
    diags[#diags + 1] = d
  end

  -- Semantic checks
  local sem_diags = check_semantics(tokens, defs)
  for _, d in ipairs(sem_diags) do
    diags[#diags + 1] = d
  end

  -- Missing semicolons
  local semi_diags = check_missing_semicolons(tokens)
  for _, d in ipairs(semi_diags) do
    diags[#diags + 1] = d
  end

  -- Rule 15: duplicate-variable
  for _, tok in ipairs(defs.dup_vars) do
    diags[#diags + 1] = {
      lnum = tok.lnum,
      col = tok.col,
      end_col = tok.end_col,
      severity = vim.diagnostic.severity.WARN,
      message = string.format('Duplicate variable definition: %s', tok.value),
      source = 'ferm-tools',
      code = 'duplicate-variable',
    }
  end

  vim.diagnostic.set(ns, bufnr, diags)
end

--- Attach the linter to a buffer
---@param bufnr number
function M.attach(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  -- Avoid double-attach
  if vim.b[bufnr]._ferm_lint_attached then
    return
  end
  vim.b[bufnr]._ferm_lint_attached = true

  local config = require('ferm-tools').config
  local delay = (config.lint and config.lint.delay) or 300
  local timer = nil

  -- Initial lint
  lint_buf(bufnr)

  -- Attach for debounced updates
  vim.api.nvim_buf_attach(bufnr, false, {
    on_lines = function(_, buf)
      if timer then
        timer:stop()
      end
      timer = vim.defer_fn(function()
        if vim.api.nvim_buf_is_valid(buf) then
          lint_buf(buf)
        end
      end, delay)
    end,
    on_detach = function(_, buf)
      if timer then
        timer:stop()
      end
      vim.b[buf]._ferm_lint_attached = nil
      vim.diagnostic.reset(ns, buf)
    end,
  })
end

return M
