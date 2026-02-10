local M = {}

local ns = vim.api.nvim_create_namespace('ferm-tools')

-- Keyword sets for fast lookup
local directives = {
  ['@def'] = true, ['@include'] = true, ['@if'] = true, ['@else'] = true,
  ['@hook'] = true, ['@subchain'] = true, ['@gotosubchain'] = true, ['@preserve'] = true,
}

local builtin_functions = {
  ['@defined'] = true, ['@eq'] = true, ['@ne'] = true, ['@not'] = true,
  ['@resolve'] = true, ['@cat'] = true, ['@join'] = true, ['@substr'] = true,
  ['@length'] = true, ['@basename'] = true, ['@dirname'] = true, ['@glob'] = true,
  ['@ipfilter'] = true,
}

local location_keywords = {
  domain = true, table = true, chain = true, policy = true,
}

local match_keywords = {
  protocol = true, proto = true, interface = true, outerface = true,
  saddr = true, daddr = true, sport = true, dport = true,
  sports = true, dports = true, module = true, mod = true,
  fragment = true, syn = true,
  -- also used as match keywords
  ['if'] = true,
}

local module_names = {
  account = true, addrtype = true, ah = true, bpf = true, cgroup = true,
  cluster = true, comment = true, connbytes = true, connlabel = true,
  connlimit = true, connmark = true, conntrack = true, cpu = true,
  dccp = true, devgroup = true, dscp = true, dst = true, ecn = true,
  esp = true, eui64 = true, frag = true, fuzzy = true, geoip = true,
  hashlimit = true, hbh = true, helper = true, hl = true, icmp = true,
  iprange = true, ipv4options = true, ipv6header = true, ipvs = true,
  length = true, limit = true, mac = true, mark = true, mh = true,
  multiport = true, nth = true, nfacct = true, osf = true, owner = true,
  pkttype = true, physdev = true, policy = true, psd = true, quota = true,
  rateest = true, realm = true, recent = true, rpfilter = true, rt = true,
  sctp = true, set = true, socket = true, state = true, statistic = true,
  string = true, tcp = true, tcpmss = true, time = true, tos = true,
  ttl = true, u32 = true, udp = true, unclean = true,
}

local builtin_chains = {
  INPUT = true, OUTPUT = true, FORWARD = true, PREROUTING = true, POSTROUTING = true,
}

local tables_set = {
  filter = true, nat = true, mangle = true, raw = true, security = true,
}

local domains_set = {
  ip = true, ip6 = true, arp = true, eb = true,
}

local targets = {
  ACCEPT = true, DROP = true, REJECT = true, RETURN = true, NOP = true,
  LOG = true, ULOG = true, NFLOG = true,
  DNAT = true, SNAT = true, MASQUERADE = true, REDIRECT = true, NETMAP = true,
  MARK = true, CONNMARK = true, TCPMSS = true, TOS = true, DSCP = true,
  TTL = true, HL = true, CLASSIFY = true, IDLETIMER = true, LED = true,
  NFQUEUE = true, NOTRACK = true, RATEEST = true, SECMARK = true,
  CONNSECMARK = true, SET = true, CT = true, TPROXY = true, TRACE = true,
  BALANCE = true, CLUSTERIP = true, CONNMARK_RESTORE = true, CONNMARK_SAVE = true,
  ECN = true, HMARK = true, IPMARK = true, MIRROR = true, SAME = true,
  SYNPROXY = true, AUDIT = true, CHECKSUM = true, DNPT = true, SNPT = true,
  RAWDNAT = true, RAWSNAT = true,
}

local protocols = {
  tcp = true, udp = true, udplite = true, icmp = true, icmpv6 = true,
  esp = true, ah = true, gre = true, sctp = true, dccp = true, mh = true,
}

local conntrack_states = {
  NEW = true, ESTABLISHED = true, RELATED = true, INVALID = true, UNTRACKED = true,
}

local tcp_flags = {
  SYN = true, ACK = true, FIN = true, RST = true, URG = true, PSH = true, ALL = true, NONE = true,
}

local module_params = {
  -- conntrack
  ctstate = true, ctstatus = true, ctproto = true, ctorigsrc = true, ctorigdst = true,
  ctreplsrc = true, ctrepldst = true, ctorigsrcport = true, ctorigdstport = true,
  ctreplsrcport = true, ctrepldstport = true, ctdir = true, ctexpire = true,
  -- log
  ['log-prefix'] = true, ['log-level'] = true, ['log-ip-options'] = true,
  ['log-tcp-options'] = true, ['log-tcp-sequence'] = true, ['log-uid'] = true,
  -- reject
  ['reject-with'] = true,
  -- nat
  ['to-source'] = true, ['to-destination'] = true, ['to-ports'] = true,
  -- mark
  ['set-mark'] = true, ['set-xmark'] = true, ['save-mark'] = true, ['restore-mark'] = true,
  -- limit
  limit = true, ['limit-burst'] = true,
  -- icmp
  ['icmp-type'] = true, ['icmpv6-type'] = true,
  -- tcp flags
  ['tcp-flags'] = true,
  -- hashlimit
  ['hashlimit-upto'] = true, ['hashlimit-above'] = true, ['hashlimit-burst'] = true,
  ['hashlimit-name'] = true, ['hashlimit-mode'] = true,
  ['hashlimit-srcmask'] = true, ['hashlimit-dstmask'] = true,
  ['hashlimit-htable-size'] = true, ['hashlimit-htable-max'] = true,
  ['hashlimit-htable-expire'] = true, ['hashlimit-htable-gcinterval'] = true,
  -- recent
  ['name'] = true, ['rsource'] = true, ['rdest'] = true,
  ['seconds'] = true, ['hitcount'] = true, ['rttl'] = true,
  -- owner
  ['uid-owner'] = true, ['gid-owner'] = true,
  -- tos/dscp
  ['set-tos'] = true, ['set-dscp'] = true, ['set-dscp-class'] = true,
  -- misc
  ['match-set'] = true, ['to'] = true, ['clamp-mss-to-pmtu'] = true,
  ['set-mss'] = true,
  -- connlimit
  ['connlimit-above'] = true, ['connlimit-upto'] = true, ['connlimit-mask'] = true,
  -- iprange
  ['src-range'] = true, ['dst-range'] = true,
  -- length
  ['length'] = true,
  -- string
  ['algo'] = true, ['string'] = true,
  -- time
  ['timestart'] = true, ['timestop'] = true, ['days'] = true,
  -- ttl
  ['ttl-eq'] = true, ['ttl-gt'] = true, ['ttl-lt'] = true, ['ttl-set'] = true,
  -- hl
  ['hl-eq'] = true, ['hl-gt'] = true, ['hl-lt'] = true, ['hl-set'] = true,
  -- pkttype
  ['pkt-type'] = true,
  -- statistic
  ['mode'] = true, ['probability'] = true, ['every'] = true, ['packet'] = true,
  -- nfqueue
  ['queue-num'] = true, ['queue-balance'] = true,
  -- quota
  ['quota'] = true,
  -- comment
  ['comment'] = true,
}

local builtin_vars = {
  ['$DOMAIN'] = true, ['$TABLE'] = true, ['$CHAIN'] = true,
  ['$FILENAME'] = true, ['$FILEBNAME'] = true, ['$DIRNAME'] = true, ['$LINE'] = true,
}

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
    local ws = line:match('^%s+', pos)
    if ws then
      pos = pos + #ws
      if pos > len then break end
    end

    -- Comment: # to end of line
    if line:sub(pos, pos) == '#' then
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
    if line:sub(pos, pos) == "'" then
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
    if line:sub(pos, pos) == '"' then
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
    if line:sub(pos, pos) == '`' then
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
    local var = line:match('^%$[A-Za-z_][A-Za-z0-9_]*', pos)
    if var then
      local hl = builtin_vars[var] and '@constant.builtin' or '@variable'
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
    local func = line:match('^&[A-Za-z_][A-Za-z0-9_]*', pos)
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
    local at_word = line:match('^@[A-Za-z_][A-Za-z0-9_]*', pos)
    if at_word then
      local hl
      if directives[at_word] then
        hl = '@keyword.directive'
      elseif builtin_functions[at_word] then
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
    local ipv4 = line:match('^%d+%.%d+%.%d+%.%d+/%d+', pos) or line:match('^%d+%.%d+%.%d+%.%d+', pos)
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
    local ipv6 = line:match('^[0-9a-fA-F:]+::[0-9a-fA-F:]*/%d+', pos)
      or line:match('^[0-9a-fA-F:]+::[0-9a-fA-F:]*', pos)
      or line:match('^[0-9a-fA-F]+:[0-9a-fA-F]+:[0-9a-fA-F:]+/%d+', pos)
      or line:match('^[0-9a-fA-F]+:[0-9a-fA-F]+:[0-9a-fA-F:]+', pos)
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
    local hex = line:match('^0x[0-9a-fA-F]+', pos)
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
    local word = line:match('^[A-Za-z_][A-Za-z0-9_%-]*', pos)
    if word then
      local hl = nil

      if prev_token == 'jump_goto' then
        -- After jump/goto, highlight chain name
        hl = '@label'
      elseif prev_token == 'module' then
        -- After mod/module keyword, highlight module name
        if module_names[word] then
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
      elseif location_keywords[word] then
        hl = '@keyword'
      elseif match_keywords[word] then
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
      elseif targets[word] then
        hl = '@function.macro'
      elseif builtin_chains[word] then
        hl = '@constant'
      elseif conntrack_states[word] then
        hl = '@constant'
      elseif tcp_flags[word] then
        hl = '@constant'
      elseif tables_set[word] then
        hl = '@type'
      elseif domains_set[word] then
        hl = '@type'
      elseif protocols[word] then
        hl = '@type'
      elseif module_params[word] then
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
    local num = line:match('^%d+', pos)
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
    local ch = line:sub(pos, pos)

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
