-- Headless regression tests. Run from the repo root:
--   nvim --clean --headless -l test/run.lua
-- Exits non-zero on failure.

local repo = vim.fn.fnamemodify(vim.fn.fnamemodify(arg[0], ':p'), ':h:h')
vim.opt.rtp:prepend(repo)
vim.opt.rtp:append(repo .. '/after')
vim.cmd('runtime! ftdetect/*.lua')
vim.cmd('runtime! plugin/ferm-tools.lua')
vim.cmd('filetype plugin indent on')
vim.o.completeopt = 'menu'

require('ferm-tools').setup({ fold = true })

local failed = 0
local function check(name, cond, detail)
  if cond then
    print('PASS: ' .. name)
  else
    failed = failed + 1
    print('FAIL: ' .. name .. (detail and (' -- ' .. tostring(detail)) or ''))
  end
end

local function new_buf(lines)
  local buf = vim.api.nvim_create_buf(false, false)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].shiftwidth = 2
  return buf
end

local function lint_diags(lines)
  local buf = new_buf(lines)
  require('ferm-tools.lint').attach(buf)
  return vim.diagnostic.get(buf)
end

local function fmt(lines)
  local buf = new_buf(lines)
  require('ferm-tools.format').buf(buf)
  return vim.api.nvim_buf_get_lines(buf, 0, -1, false)
end

----------------------------------------------------------------------
-- Formatter
----------------------------------------------------------------------

-- No infinite loop / crash on unclosed double-quoted string
local ok_crash, err_crash = pcall(fmt, { 'LOG log-prefix "unterminated;' })
check('format: no crash on unclosed string', ok_crash, err_crash)

-- Escaped \" inside strings does not corrupt brace depth
local out = fmt({
  'table filter {',
  [[chain INPUT LOG log-prefix "pre\"fix" {]],
  'ACCEPT;',
  '}',
  '}',
})
check('format: escaped quote depth', out[3] == '    ACCEPT;' and out[5] == '}',
  vim.inspect(out))

-- No spurious trailing blank line
out = fmt({ 'chain INPUT {', 'policy DROP;', '}' })
check('format: no trailing blank line', #out == 3 and out[3] == '}', vim.inspect(out))

-- Idempotence on the repo fixture, and formatted output lints clean
local unformatted = vim.fn.readfile(repo .. '/test/unformatted.ferm')
local once = fmt(unformatted)
local twice = fmt(once)
check('format: idempotent on unformatted.ferm', vim.deep_equal(once, twice))
check('format: unformatted.ferm output lints clean', #lint_diags(once) == 0,
  vim.inspect(lint_diags(once)))

-- Range formatting keeps blank lines and does not touch the rest
local buf = new_buf({ 'chain INPUT {', '   policy DROP;', '}', '', '' })
vim.api.nvim_set_current_buf(buf)
vim.cmd('2FermFormat')
local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
check(':N,FermFormat: only addressed line formatted',
  #lines == 5 and lines[2] == '  policy DROP;' and lines[1] == 'chain INPUT {',
  vim.inspect(lines))

-- gq on a blank line must not delete it
buf = new_buf({ 'chain INPUT {', '', '}' })
vim.api.nvim_set_current_buf(buf)
vim.bo[buf].filetype = 'ferm'
vim.cmd('2')
vim.cmd('normal! gqq')
lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
check('gq: blank line preserved', #lines == 3 and lines[2] == '', vim.inspect(lines))

-- 1-indexed column of a plain substring, or nil.
local function col(s, sub)
  return (s:find(sub, 1, true))
end

-- Multi-line paren lists indent one level and align trailing comments; a
-- comment-less item (e.g. a variable) still counts toward the column width.
out = fmt({
  '@def $NETS = (',
  '10.0.0.1 # a',
  '10.0.0.100 # b',
  '$OTHER',
  ');',
})
check('format: paren list indent + comment align',
  out[2] == '  10.0.0.1   # a' and out[3] == '  10.0.0.100 # b'
    and out[4] == '  $OTHER' and out[5] == ');',
  vim.inspect(out))
check('format: paren list idempotent', vim.deep_equal(out, fmt(out)), vim.inspect(out))

-- Rule runs align into columns; a rule without dport reserves the middle
-- column so the target and comment stay aligned.
-- A trailing column the shorter rule never reaches is NOT reserved: `daddr X
-- ACCEPT` stays compact instead of being stretched by a sibling's `dport`.
out = fmt({
  'chain OUTPUT {',
  'daddr 10.0.0.1 dport (80 443) ACCEPT; # web',
  'daddr 10.0.0.2 ACCEPT; # any',
  '}',
})
check('format: trailing unused column not reserved (short rule compact)',
  out[2] == '  daddr 10.0.0.1 dport (80 443) ACCEPT; # web'
    and out[3] == '  daddr 10.0.0.2 ACCEPT; # any',
  vim.inspect(out))
check('format: rule align idempotent', vim.deep_equal(out, fmt(out)), vim.inspect(out))

-- Alignment is positional, so each line keeps its own keyword order (daddr and
-- proto are not reordered into fixed keyword columns).
out = fmt({
  'interface eth0 daddr 10.0.0.1 proto tcp ACCEPT; # a',
  'interface eth0 proto tcp daddr 10.0.0.2 ACCEPT; # b',
})
check('format: align preserves keyword order',
  col(out[1], 'daddr') < col(out[1], 'proto')
    and col(out[2], 'proto') < col(out[2], 'daddr'),
  vim.inspect(out))

-- Balanced braces within a statement (Jinja/Ansible templating) do not stop a
-- line from being treated as an alignable rule.
out = fmt({
  'interface {{ x }} daddr 10.0.0.1 ACCEPT; # a',
  'interface {{ x }} daddr 10.0.0.100 ACCEPT; # b',
})
check('format: balanced braces still align',
  col(out[1], '#') ~= nil and col(out[1], '#') == col(out[2], '#')
    and out[1]:find('{{ x }}', 1, true) ~= nil,
  vim.inspect(out))

-- A paren list nested in a brace block uses combined brace+paren depth, and
-- the ") TARGET;" closer de-indents to the opener's level.
out = fmt({
  '@def &f($s) = {',
  'interface $s daddr (',
  '10.0.0.1 # a',
  '10.0.0.100 # b',
  ') ACCEPT;',
  '}',
})
check('format: nested paren depth + closer dedent',
  out[2] == '  interface $s daddr (' and out[3] == '    10.0.0.1   # a'
    and out[4] == '    10.0.0.100 # b' and out[5] == '  ) ACCEPT;' and out[6] == '}',
  vim.inspect(out))

-- Rules with different leading keywords are not a column group: each is left
-- with single-space normalization, not aligned to the other.
out = fmt({
  'chain OUTPUT {',
  'saddr 10.0.0.1 ACCEPT;',
  'daddr 10.0.0.2 dport 22 ACCEPT;',
  '}',
})
check('format: differing first keyword not grouped',
  out[2] == '  saddr 10.0.0.1 ACCEPT;'
    and out[3] == '  daddr 10.0.0.2 dport 22 ACCEPT;',
  vim.inspect(out))

-- Different targets still align comments (the target column is padded).
out = fmt({
  'chain OUTPUT {',
  'daddr 10.0.0.1 ACCEPT; # a',
  'daddr 10.0.0.100 DROP; # b',
  '}',
})
check('format: mixed targets keep comments aligned',
  col(out[2], '#') == col(out[3], '#') and col(out[2], 'ACCEPT;') == col(out[3], 'DROP;'),
  vim.inspect(out))

-- A keyword present in only some rules (dport) gets its own column, which the
-- other rules leave blank, so the following keyword and the target stay aligned
-- instead of shifting into the gap. Keyword order within each line is kept.
out = fmt({
  'saddr 10.0.0.1 {',
  "daddr 10.1.1.1 protocol tcp mod comment comment 'a' ACCEPT;",
  "daddr 10.1.1.2 protocol tcp dport 8050 mod comment comment 'b' ACCEPT;",
  '}',
})
check('format: optional middle keyword reserves its column',
  col(out[2], 'mod comment') == col(out[3], 'mod comment')
    and col(out[2], 'ACCEPT;') == col(out[3], 'ACCEPT;')
    and out[3]:find('dport 8050', 1, true) ~= nil,
  vim.inspect(out))
check('format: supersequence align idempotent', vim.deep_equal(out, fmt(out)), vim.inspect(out))

-- proto and protocol are synonyms: they share one alignment column, so the
-- following columns stay aligned even when the group mixes both spellings.
out = fmt({
  'chain OUTPUT {',
  'daddr 10.0.0.1 proto tcp dport 22 ACCEPT;',
  'daddr 10.0.0.2 protocol tcp ACCEPT;',
  '}',
})
check('format: proto/protocol share a column',
  col(out[2], 'proto') == col(out[3], 'proto')
    and out[3] == '  daddr 10.0.0.2 protocol tcp ACCEPT;',
  vim.inspect(out))

-- Within a column the keyword and its value align in separate sub-columns, so
-- proto/protocol (different lengths) line up and their values still align.
out = fmt({
  'chain OUTPUT {',
  'daddr 10.3.3.1 proto tcp dport 22 ACCEPT;',
  'daddr 10.3.3.2 protocol tcp ACCEPT;',
  'daddr 10.3.3.3 proto udp dport 22 ACCEPT;',
  'daddr 10.3.3.4 protocol icmp ACCEPT;',
  '}',
})
check('format: keyword and value align in separate sub-columns',
  out[2] == '  daddr 10.3.3.1 proto    tcp  dport 22 ACCEPT;'
    and out[3] == '  daddr 10.3.3.2 protocol tcp  ACCEPT;'
    and out[4] == '  daddr 10.3.3.3 proto    udp  dport 22 ACCEPT;'
    and out[5] == '  daddr 10.3.3.4 protocol icmp ACCEPT;',
  vim.inspect(out))

-- Mixed rule shapes in one group. A keyword used by only some rules (`mod`)
-- keeps its natural place after `dport` (look-ahead column insertion, not
-- wedged in early), so in the full rule proto < dport < mod. A daddr-only rule
-- stays compact; a `mod` rule reserves the empty proto/dport columns (they are
-- middle gaps) so its comment lines up with the full rules.
out = fmt({
  'saddr 10.0.0.1 {',
  'daddr 10.1.1.1 ACCEPT;',
  'daddr 10.1.1.2 proto tcp dport 22 ACCEPT;',
  "daddr 10.1.1.3 mod comment comment 'x' ACCEPT;",
  "daddr 10.1.1.4 proto tcp dport 80 mod comment comment 'y' ACCEPT;",
  '}',
})
check('format: look-ahead columns; short rule compact, mod aligned',
  col(out[5], 'proto') < col(out[5], 'dport') and col(out[5], 'dport') < col(out[5], 'mod')
    and out[2] == '  daddr 10.1.1.1 ACCEPT;'
    and out[3]:find('mod', 1, true) == nil
    and col(out[4], 'mod comment') == col(out[5], 'mod comment'),
  vim.inspect(out))
check('format: mixed shapes idempotent', vim.deep_equal(out, fmt(out)), vim.inspect(out))

-- Two different mod modules form separate columns (keyed by module name), so a
-- rule with only `mod comment` reserves the `mod multiport` column and its
-- comment still lines up with the fuller rules.
out = fmt({
  'saddr 10.0.0.1 {',
  "daddr 10.1.1.1 proto tcp mod multiport destination-ports (80 443) mod comment comment 'a' ACCEPT;",
  "daddr 10.1.1.2 proto tcp mod comment comment 'b' ACCEPT;",
  '}',
})
check('format: mod modules keyed separately (multiport vs comment)',
  out[3]:find('multiport', 1, true) == nil
    and col(out[2], 'mod comment') == col(out[3], 'mod comment')
    and col(out[2], 'ACCEPT;') == col(out[3], 'ACCEPT;'),
  vim.inspect(out))

----------------------------------------------------------------------
-- Linter
----------------------------------------------------------------------

check('lint: example.ferm clean',
  #lint_diags(vim.fn.readfile(repo .. '/test/example.ferm')) == 0)

local d = lint_diags({ 'chain VPN_IN {', 'mod policy dir in pol ipsec ACCEPT;', '}' })
check('lint: mod policy is not a policy statement', #d == 0, vim.inspect(d))

local d = lint_diags({ 'chain my_custom {', 'policy DROP;', '}' })
check('lint: policy on custom chain flagged', #d == 1 and d[1].code == 'policy-on-custom-chain',
  vim.inspect(d))

d = lint_diags({ 'chain MYCHAIN {', 'proto tcp {', 'dport ssh ACCEPT;', '}', 'policy DROP;', '}' })
check('lint: policy in nested block still finds chain',
  #d == 1 and d[1].code == 'policy-on-custom-chain', vim.inspect(d))

d = lint_diags({ 'chain (INPUT MYCHAIN) {', 'policy DROP;', '}' })
check('lint: paren chain list checked',
  #d == 1 and d[1].code == 'policy-on-custom-chain', vim.inspect(d))

check('lint: policy on builtin chain ok',
  #lint_diags({ 'chain INPUT {', 'policy DROP;', '}' }) == 0)

d = lint_diags({ 'chain INPUT {', 'policy REJECT;', '}' })
check('lint: invalid policy value', #d == 1 and d[1].code == 'invalid-policy-value',
  vim.inspect(d))

d = lint_diags({ '@def &F($x) = saddr $x ACCEPT;', 'saddr $x DROP;' })
check('lint: function params scoped to definition',
  #d == 1 and d[1].code == 'undefined-variable' and d[1].lnum == 1, vim.inspect(d))

d = lint_diags({ '@def &ALLOW = saddr $TYPO_VAR ACCEPT;' })
check('lint: body vars of paren-less def not globally defined',
  #d == 1 and d[1].code == 'undefined-variable', vim.inspect(d))

d = lint_diags({ 'proto icmp ACCEPT; proto tcp DROP' })
check('lint: missing semicolon on second statement of line',
  #d == 1 and d[1].code == 'missing-semicolon', vim.inspect(d))

check('lint: wrapped statement with final semicolon ok',
  #lint_diags({ 'proto tcp dport 22', 'ACCEPT', ';' }) == 0)

d = lint_diags({ 'saddr 10.0.0.1 jump mychain' })
check('lint: missing semicolon after jump',
  #d == 1 and d[1].code == 'missing-semicolon', vim.inspect(d))

check('lint: jump with semicolon ok',
  #lint_diags({ 'saddr 10.0.0.1 jump mychain;' }) == 0)

----------------------------------------------------------------------
-- Highlighter
----------------------------------------------------------------------

local hl_ns = vim.api.nvim_get_namespaces()['ferm-tools']

local function hl_at(bufnr, col)
  local marks = vim.api.nvim_buf_get_extmarks(bufnr, hl_ns, 0, -1, { details = true })
  for _, m in ipairs(marks) do
    if m[3] == col then
      return m[4].hl_group
    end
  end
  return nil
end

buf = new_buf({ 'mod conntrack ctstate NEW ACCEPT;' })
require('ferm-tools.highlight').attach(buf)
check('highlight: module context releases after name',
  hl_at(buf, 14) == '@property' and hl_at(buf, 22) == '@constant'
    and hl_at(buf, 26) == '@function.macro',
  string.format('%s %s %s', hl_at(buf, 14), hl_at(buf, 22), hl_at(buf, 26)))

buf = new_buf({ 'jump mychain proto tcp;' })
require('ferm-tools.highlight').attach(buf)
check('highlight: jump label limited to chain name',
  hl_at(buf, 0) == '@function.macro' and hl_at(buf, 5) == '@label'
    and hl_at(buf, 13) == '@keyword' and hl_at(buf, 19) == '@type',
  string.format('%s %s %s %s', hl_at(buf, 0), hl_at(buf, 5), hl_at(buf, 13), hl_at(buf, 19)))

----------------------------------------------------------------------
-- Indent and fold
----------------------------------------------------------------------

buf = new_buf({
  'chain INPUT mod comment comment "rule #1" {',
  'proto tcp ACCEPT;',
  '}',
})
vim.api.nvim_set_current_buf(buf)
vim.bo[buf].filetype = 'ferm'
vim.bo[buf].shiftwidth = 2
vim.cmd('2normal! ==')
vim.cmd('3normal! ==')
check('indent: string-aware brace detection',
  vim.fn.indent(2) == 2 and vim.fn.indent(3) == 0,
  string.format('%d %d', vim.fn.indent(2), vim.fn.indent(3)))

buf = new_buf({
  'chain INPUT {',
  '@if $cond {',
  'ACCEPT;',
  '} @else {',
  'DROP;',
  '}',
  '}',
})
vim.api.nvim_set_current_buf(buf)
vim.bo[buf].filetype = 'ferm'
vim.bo[buf].shiftwidth = 2
require('ferm-tools').setup({ fold = true })
for i = 2, 7 do
  vim.cmd(i .. 'normal! ==')
end
local indents = {}
for i = 1, 7 do
  indents[i] = vim.fn.indent(i)
end
check('indent: } @else { reopens block',
  vim.deep_equal(indents, { 0, 2, 4, 2, 4, 2, 0 }), vim.inspect(indents))

buf = new_buf({
  'chain LOGDROP LOG log-prefix "#firewall " {',
  'ACCEPT;',
  '@if $c {',
  'DROP;',
  '} @else {',
  'DROP;',
  '}',
  '}',
})
vim.api.nvim_set_current_buf(buf)
vim.bo[buf].filetype = 'ferm'
check('fold: string-aware, no phantom level on } @else {',
  vim.fn.foldlevel(1) == 1 and vim.fn.foldlevel(4) == 2
    and vim.fn.foldlevel(5) == 2 and vim.fn.foldlevel(6) == 2,
  string.format('%d %d %d %d',
    vim.fn.foldlevel(1), vim.fn.foldlevel(4), vim.fn.foldlevel(5), vim.fn.foldlevel(6)))

-- Fold options must not leak to other buffers in the same window
local ferm_file = vim.fn.tempname() .. '.ferm'
vim.fn.writefile({ 'chain INPUT {', 'policy DROP;', '}' }, ferm_file)
vim.cmd('edit ' .. ferm_file)
local in_ferm = vim.wo.foldmethod
vim.cmd('enew')
check('ftplugin: fold options do not leak across buffers',
  in_ferm == 'expr' and vim.wo.foldmethod ~= 'expr',
  string.format('%s then %s', in_ferm, vim.wo.foldmethod))

-- Indent tracks parens like braces: a multi-line paren list nested in a brace
-- block indents one level, and the ") TARGET;" closer de-indents.
buf = new_buf({
  '@def &f($s) = {',
  'interface $s daddr (',
  '10.0.0.1',
  '10.0.0.100',
  ') ACCEPT;',
  '}',
})
vim.api.nvim_set_current_buf(buf)
vim.bo[buf].filetype = 'ferm'
vim.bo[buf].shiftwidth = 2
for i = 2, 6 do
  vim.cmd(i .. 'normal! ==')
end
indents = {}
for i = 1, 6 do
  indents[i] = vim.fn.indent(i)
end
check('indent: multi-line paren list indents like a block',
  vim.deep_equal(indents, { 0, 2, 4, 4, 2, 0 }), vim.inspect(indents))

-- Fold treats a multi-line paren list as a foldable block.
buf = new_buf({ '@def $NETS = (', '10.0.0.1', '10.0.0.100', ');' })
vim.api.nvim_set_current_buf(buf)
vim.bo[buf].filetype = 'ferm'
require('ferm-tools').setup({ fold = true })
check('fold: multi-line paren list is foldable',
  vim.fn.foldlevel(1) == 1 and vim.fn.foldlevel(2) == 1 and vim.fn.foldlevel(3) == 1,
  string.format('%d %d %d', vim.fn.foldlevel(1), vim.fn.foldlevel(2), vim.fn.foldlevel(3)))

----------------------------------------------------------------------
-- Completion
----------------------------------------------------------------------

-- omnifunc end-to-end via <C-x><C-o>
vim.cmd('edit ' .. ferm_file)
check('ftplugin: omnifunc uses funcref form',
  vim.bo.omnifunc == "v:lua.require'ferm-tools.complete'.omnifunc", vim.bo.omnifunc)
vim.api.nvim_buf_set_lines(0, 0, -1, false, { '@d' })
vim.cmd('1')
vim.api.nvim_feedkeys(
  vim.api.nvim_replace_termcodes('A<C-x><C-o><Esc>', true, false, true), 'x', false)
check('omnifunc: completes @d to a directive',
  vim.fn.getline(1) == '@def', vim.fn.getline(1))
vim.cmd('bwipeout!')

-- nvim-cmp source unit tests
local src = require('ferm-tools.complete').cmp_source()

local function cmp_items(before_line)
  local result
  src:complete({ context = { cursor_before_line = before_line } }, function(r)
    result = r
  end)
  local labels = {}
  for _, item in ipairs(result.items) do
    labels[item.label] = true
  end
  return labels
end

buf = new_buf({
  '@def $DNS_SERVERS (1.1.1.1);',
  '# @def $OLD_NET 10.0.0.0/8',
})
vim.api.nvim_set_current_buf(buf)
vim.bo[buf].filetype = 'ferm'

local labels = cmp_items('@d')
check('cmp: @ prefix offers directives', labels['@def'] and not labels['chain'],
  vim.inspect(vim.tbl_keys(labels)))

labels = cmp_items('saddr $D')
check('cmp: $ offers builtin and user vars, skips commented defs',
  labels['$DOMAIN'] and labels['$DNS_SERVERS'] and not labels['$OLD_NET'],
  vim.inspect(vim.tbl_keys(labels)))

labels = cmp_items('proto (tcp u')
check('cmp: context survives paren lists', labels['udp'] and not labels['chain'],
  vim.inspect(vim.tbl_keys(labels)))

labels = cmp_items('jump I')
check('cmp: jump completes chain names', labels['INPUT'] ~= nil)

labels = cmp_items('pro')
check('cmp: default items include chain commands', labels['jump'] and labels['proto'])

check('cmp: available in ferm buffer', src:is_available())
require('ferm-tools').setup({ complete = { enable = false } })
check('cmp: respects complete.enable=false', not src:is_available())
require('ferm-tools').setup({ complete = { enable = true } })

-- Registration guard: sourcing after/plugin twice registers once
local register_count = 0
package.loaded['cmp'] = {
  register_source = function() register_count = register_count + 1 end,
}
dofile(repo .. '/after/plugin/cmp_ferm.lua')
dofile(repo .. '/after/plugin/cmp_ferm.lua')
check('cmp: no duplicate registration on re-source', register_count == 1,
  tostring(register_count))
package.loaded['cmp'] = nil

----------------------------------------------------------------------

if failed > 0 then
  print(string.format('%d test(s) FAILED', failed))
  vim.cmd('cquit!')
else
  print('All tests passed')
  vim.cmd('qall!')
end
