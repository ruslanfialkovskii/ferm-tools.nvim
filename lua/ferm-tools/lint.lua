local M = {}

local kw = require('ferm-tools.keywords')
local lexer = require('ferm-tools.lexer')
local ns = vim.api.nvim_create_namespace('ferm-tools-lint')
local severity = vim.diagnostic.severity

--- Build a diagnostic anchored at a token.
---@param tok table
---@param sev number vim.diagnostic.severity
---@param code string
---@param message string
---@return table diagnostic
local function diag(tok, sev, code, message)
  return {
    lnum = tok.lnum,
    col = tok.col,
    end_col = tok.end_col,
    severity = sev,
    message = message,
    source = 'ferm-tools',
    code = code,
  }
end

--- Collect variable and function definitions from tokens.
--- Function parameters are scoped to their definition body (up to the
--- terminating ';' or the end of the definition's brace block), not global.
---@param tokens table[]
---@return table defs { vars = set, funcs = set, dup_vars = list, param_scopes = list }
local function collect_definitions(tokens)
  local defs = { vars = {}, funcs = {}, dup_vars = {}, param_scopes = {} }
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
          -- Parameters: @def &func($param1, $param2) = <body>
          local scope = { params = {}, start_idx = i, end_idx = #tokens }
          local j = i + 2
          if tokens[j] and tokens[j].type == 'paren_open' then
            j = j + 1
            while tokens[j] and tokens[j].type ~= 'paren_close' do
              if tokens[j].type == 'variable' then
                scope.params[tokens[j].value] = true
              end
              j = j + 1
            end
          end
          -- Body ends at the first ';' at brace depth 0, or at the close of
          -- the definition's brace block
          local depth = 0
          for k = j, #tokens do
            local t = tokens[k]
            if t.type == 'brace_open' then
              depth = depth + 1
            elseif t.type == 'brace_close' then
              depth = depth - 1
              if depth <= 0 then
                scope.end_idx = k
                break
              end
            elseif t.type == 'semicolon' and depth == 0 then
              scope.end_idx = k
              break
            end
          end
          if next(scope.params) then
            defs.param_scopes[#defs.param_scopes + 1] = scope
          end
        end
      end
    end
  end
  return defs
end

--- Is tok a word token with the given value?
---@param tok table|nil
---@param value string
---@return boolean
local function is_word(tok, value)
  return tok ~= nil and tok.type == 'word' and tok.value == value
end

--- Is the variable at token index idx a function parameter in scope?
---@param defs table
---@param name string
---@param idx number token index
---@return boolean
local function param_in_scope(defs, name, idx)
  for _, scope in ipairs(defs.param_scopes) do
    if idx >= scope.start_idx and idx <= scope.end_idx and scope.params[name] then
      return true
    end
  end
  return false
end

--- Check brace and paren matching (Rules 1, 11) and unclosed strings/backticks (Rules 12, 13).
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
        diags[#diags + 1] = diag(tok, severity.ERROR, 'unmatched-brace', 'Unmatched closing brace')
      else
        table.remove(brace_stack)
      end
    elseif tok.type == 'paren_open' then
      paren_stack[#paren_stack + 1] = tok
    elseif tok.type == 'paren_close' then
      if #paren_stack == 0 then
        diags[#diags + 1] = diag(tok, severity.ERROR, 'unmatched-paren', 'Unmatched closing parenthesis')
      else
        table.remove(paren_stack)
      end
    elseif tok.type == 'unclosed_string' then
      diags[#diags + 1] = diag(tok, severity.ERROR, 'unclosed-string', 'Unclosed string')
    elseif tok.type == 'unclosed_backtick' then
      diags[#diags + 1] = diag(tok, severity.ERROR, 'unclosed-backtick', 'Unclosed backtick command substitution')
    end
  end

  for _, tok in ipairs(brace_stack) do
    diags[#diags + 1] = diag(tok, severity.ERROR, 'unmatched-brace', 'Unmatched opening brace')
  end

  for _, tok in ipairs(paren_stack) do
    diags[#diags + 1] = diag(tok, severity.ERROR, 'unmatched-paren', 'Unmatched opening parenthesis')
  end

  return diags
end

--- Check semantic rules (Rules 2–10)
---@param tokens table[]
---@param defs table
---@return table[] diagnostics
local function check_semantics(tokens, defs)
  local diags = {}

  -- Chain scope tracking for rule 7: chain names seen since the last brace
  -- are pushed with the brace that opens their block.
  local chain_stack = {}
  local pending_chain = nil

  for i, tok in ipairs(tokens) do
    -- Rule 2: undefined-variable
    if tok.type == 'variable' then
      -- Skip if this variable is being defined (preceded by @def)
      local prev = tokens[i - 1]
      local is_definition = prev and prev.type == 'directive' and prev.value == '@def'
      if not is_definition
        and not kw.builtin_vars[tok.value]
        and not defs.vars[tok.value]
        and not param_in_scope(defs, tok.value, i) then
        diags[#diags + 1] = diag(tok, severity.WARN, 'undefined-variable',
          string.format('Undefined variable: %s', tok.value))
      end
    end

    -- Rule 3: unknown-directive
    if tok.type == 'directive' and not kw.directives[tok.value] then
      diags[#diags + 1] = diag(tok, severity.ERROR, 'unknown-directive',
        string.format('Unknown directive: %s', tok.value))
    end

    -- Track chain scopes (false marks a block that is not a chain body)
    if tok.type == 'brace_open' then
      chain_stack[#chain_stack + 1] = pending_chain or false
      pending_chain = nil
    elseif tok.type == 'brace_close' then
      if #chain_stack > 0 then
        table.remove(chain_stack)
      end
    end

    -- Context-dependent rules: look at neighboring tokens
    if tok.type == 'word' then
      local prev = tokens[i - 1]

      if tok.value == 'chain' then
        -- Collect the chain name(s) that follow (single word or paren list)
        local names = {}
        local j = i + 1
        if tokens[j] and tokens[j].type == 'paren_open' then
          j = j + 1
          while tokens[j] and tokens[j].type ~= 'paren_close' do
            if tokens[j].type == 'word' then
              names[#names + 1] = tokens[j].value
            end
            j = j + 1
          end
        elseif tokens[j] and tokens[j].type == 'word' then
          names[#names + 1] = tokens[j].value
        end
        if #names > 0 then
          pending_chain = names
        end
      end

      -- Rule 4: invalid-table
      if is_word(prev, 'table') and not kw.tables_set[tok.value] then
        diags[#diags + 1] = diag(tok, severity.ERROR, 'invalid-table',
          string.format('Invalid table name: %s (expected: filter, nat, mangle, raw, security)', tok.value))
      end

      -- Rule 5: invalid-domain
      if is_word(prev, 'domain') and not kw.domains_set[tok.value] then
        diags[#diags + 1] = diag(tok, severity.ERROR, 'invalid-domain',
          string.format('Invalid domain: %s (expected: ip, ip6, arp, eb)', tok.value))
      end

      -- Rule 6: unknown-module
      if (is_word(prev, 'mod') or is_word(prev, 'module')) and not kw.module_names[tok.value] then
        diags[#diags + 1] = diag(tok, severity.WARN, 'unknown-module',
          string.format('Unknown module: %s', tok.value))
      end

      -- Rules 7/8 apply to the 'policy' location keyword; 'mod policy' is
      -- the iptables policy match module, not a policy statement.
      if tok.value == 'policy' and not (is_word(prev, 'mod') or is_word(prev, 'module')) then
        -- Rule 7: policy-on-custom-chain (nearest enclosing chain block)
        local chain_names = pending_chain
        if not chain_names then
          for s = #chain_stack, 1, -1 do
            if chain_stack[s] then
              chain_names = chain_stack[s]
              break
            end
          end
        end
        for _, name in ipairs(chain_names or {}) do
          if not kw.builtin_chains[name] then
            diags[#diags + 1] = diag(tok, severity.ERROR, 'policy-on-custom-chain',
              string.format('Cannot set policy on custom chain: %s', name))
            break
          end
        end

        -- Rule 8: invalid-policy-value
        local value_tok = tokens[i + 1]
        if value_tok and value_tok.type == 'word' and not kw.policy_values[value_tok.value] then
          diags[#diags + 1] = diag(value_tok, severity.ERROR, 'invalid-policy-value',
            string.format('Invalid policy value: %s (expected: ACCEPT or DROP)', value_tok.value))
        end
      end
    end

    -- Rule 9: invalid-ipv4
    if tok.type == 'ipv4' then
      local addr, cidr = tok.value:match('^(.+)/(%d+)$')
      if not addr then
        addr = tok.value
      end
      for octet_str in addr:gmatch('(%d+)') do
        if tonumber(octet_str) > 255 then
          diags[#diags + 1] = diag(tok, severity.ERROR, 'invalid-ipv4',
            string.format('Invalid IPv4 address: octet > 255 in %s', tok.value))
          break
        end
      end
      if cidr and tonumber(cidr) > 32 then
        diags[#diags + 1] = diag(tok, severity.ERROR, 'invalid-ipv4',
          string.format('Invalid IPv4 CIDR prefix: /%s (max 32)', cidr))
      end
    end

    -- Rule 10: invalid-ipv6-cidr
    if tok.type == 'ipv6' then
      local _, cidr = tok.value:match('^(.+)/(%d+)$')
      if cidr and tonumber(cidr) > 128 then
        diags[#diags + 1] = diag(tok, severity.ERROR, 'invalid-ipv6-cidr',
          string.format('Invalid IPv6 CIDR prefix: /%s (max 128)', cidr))
      end
    end

    -- Rule 14: invalid-port
    if tok.type == 'number' then
      local prev = tokens[i - 1]
      if prev and prev.type == 'word'
        and (prev.value == 'dport' or prev.value == 'sport'
          or prev.value == 'dports' or prev.value == 'sports')
        and tonumber(tok.value) > 65535 then
        diags[#diags + 1] = diag(tok, severity.ERROR, 'invalid-port',
          string.format('Invalid port number: %s (max 65535)', tok.value))
      end
    end
  end

  return diags
end

--- Check for missing semicolons (Rule 16).
--- Statements are token runs terminated by ';', '{', '}', or end of buffer.
--- A statement whose last token is a target (or a chain name after
--- jump/goto) must be terminated by ';'.
---@param tokens table[]
---@return table[] diagnostics
local function check_missing_semicolons(tokens)
  local diags = {}
  local stmt = {}

  local function check_stmt(terminator)
    local last = stmt[#stmt]
    local before_last = stmt[#stmt - 1]
    stmt = {}
    if terminator and terminator.type ~= 'brace_close' then
      -- Statement ended by ';' (fine) or '{' (block header, no ';' needed)
      return
    end
    if not last or last.type ~= 'word' then
      return
    end
    local is_target = kw.targets[last.value]
    local is_chain_jump = before_last and before_last.type == 'word'
      and kw.chain_commands[before_last.value]
    if is_target or is_chain_jump then
      diags[#diags + 1] = diag(last, severity.WARN, 'missing-semicolon',
        string.format('Missing semicolon after %s', last.value))
    end
  end

  for _, tok in ipairs(tokens) do
    if tok.type == 'semicolon' or tok.type == 'brace_open' or tok.type == 'brace_close' then
      check_stmt(tok)
    elseif tok.type ~= 'comment' then
      stmt[#stmt + 1] = tok
    end
  end
  check_stmt(nil)

  return diags
end

--- Run all lint checks on buffer
---@param bufnr number
local function lint_buf(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local tokens = lexer.tokenize(lines)
  local defs = collect_definitions(tokens)
  local diags = {}

  vim.list_extend(diags, check_structure(tokens))
  vim.list_extend(diags, check_semantics(tokens, defs))
  vim.list_extend(diags, check_missing_semicolons(tokens))

  -- Rule 15: duplicate-variable
  for _, tok in ipairs(defs.dup_vars) do
    diags[#diags + 1] = diag(tok, severity.WARN, 'duplicate-variable',
      string.format('Duplicate variable definition: %s', tok.value))
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
  local uv = vim.uv or vim.loop
  local timer = uv.new_timer()

  -- Initial lint
  lint_buf(bufnr)

  -- Attach for debounced updates
  vim.api.nvim_buf_attach(bufnr, false, {
    on_lines = function(_, buf)
      timer:stop()
      timer:start(delay, 0, vim.schedule_wrap(function()
        if vim.api.nvim_buf_is_valid(buf) then
          lint_buf(buf)
        end
      end))
    end,
    on_detach = function(_, buf)
      timer:stop()
      if not timer:is_closing() then
        timer:close()
      end
      vim.b[buf]._ferm_lint_attached = nil
      vim.diagnostic.reset(ns, buf)
    end,
  })
end

return M
