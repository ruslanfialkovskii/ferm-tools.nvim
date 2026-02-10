# ferm-tools.nvim

Neovim plugin for [ferm](http://ferm.foo-projects.org/) firewall configuration — syntax highlighting, indentation, folding, linting, formatting, and completion.

## Requirements

- Neovim >= 0.9

## Installation

### lazy.nvim

```lua
{
  'ruslanfialkovskii/ferm-tools.nvim',
  ft = { 'ferm' },
  opts = {},
}
```

### Local development

```lua
{
  dir = '~/Documents/github/ferm-tools.nvim',
  ft = { 'ferm' },
  opts = {},
}
```

## Configuration

```lua
require('ferm-tools').setup({
  fold = false, -- enable foldexpr-based folding
  lint = {
    enable = true, -- enable inline diagnostics (linter)
    delay = 300,   -- debounce delay in ms before re-linting
  },
  format = {
    enable = true,  -- enable formatexpr (gq)
    on_save = false, -- auto-format on save
  },
  complete = {
    enable = true, -- enable omnifunc completion
  },
})
```

## Features

- **Syntax highlighting** — Lua-based highlighter using Neovim's extmarks API with treesitter highlight groups for universal colorscheme support
- **Linter** — inline diagnostics via `vim.diagnostic` that catch configuration errors before deploying firewall rules
- **Formatter** — normalize indentation, spacing, and blank lines in ferm configs
- **Completion** — context-aware keyword completion via omnifunc and nvim-cmp
- **Indentation** — automatic indent/dedent on `{` and `}`
- **Folding** — optional `foldmethod=expr` based on brace nesting
- **Filetype detection** — `*.ferm`, `ferm.conf`, `/etc/ferm/*`
- **Comment support** — `commentstring` set for `gc` commenting via comment plugins

### Formatter

The formatter normalizes ferm configuration files:

- Indentation using `shiftwidth` spaces per nesting level
- Trailing whitespace removal
- Single space between tokens (strings and comments preserved verbatim)
- Blank line between top-level blocks (domain/table sections)
- No multiple consecutive blank lines

**Usage:**

- `:FermFormat` — format the entire buffer
- `:FermFormat` with visual selection — format selected range
- `gq` — format via `formatexpr` (select lines, press `gq`)
- Format-on-save: `setup({ format = { on_save = true } })`

### Completion

Context-aware keyword completion for ferm syntax. Works via two mechanisms:

#### omnifunc (`<C-x><C-o>`)

Built-in, zero-dependency completion. Enabled by default, works without any plugins.

#### nvim-cmp source

If [nvim-cmp](https://github.com/hrsh7th/nvim-cmp) is installed, a `ferm` source is registered automatically. Add it to your cmp sources:

```lua
sources = {
  { name = 'ferm' },
  -- ...other sources
}
```

The source is inert on non-ferm buffers (`is_available()` checks filetype).

**Context-aware completions:**

| Context | Completions |
|---------|-------------|
| After `@` | Directives (`@def`, `@include`, ...) + built-in functions (`@eq`, `@resolve`, ...) |
| After `$` | Built-in variables (`$DOMAIN`, `$TABLE`, ...) + user-defined variables from buffer |
| After `&` | User-defined functions from buffer |
| After `domain` | `ip`, `ip6`, `arp`, `eb` |
| After `table` | `filter`, `nat`, `mangle`, `raw`, `security` |
| After `chain` | `INPUT`, `OUTPUT`, `FORWARD`, `PREROUTING`, `POSTROUTING` |
| After `policy` | `ACCEPT`, `DROP` |
| After `mod`/`module` | Module names (conntrack, state, limit, ...) |
| After `proto`/`protocol` | Protocol names (tcp, udp, icmp, ...) |
| After `ctstate` | Conntrack states (NEW, ESTABLISHED, RELATED, ...) |
| After `tcp-flags` | TCP flags (SYN, ACK, FIN, ...) |
| Default | All keywords: location, match, targets, module params |

### Highlighted token types

- Directives (`@def`, `@include`, `@if`, `@else`, `@hook`, ...)
- Built-in functions (`@eq`, `@ne`, `@resolve`, `@cat`, `@join`, ...)
- Location keywords (`domain`, `table`, `chain`, `policy`)
- Match keywords (`protocol`, `saddr`, `daddr`, `sport`, `dport`, `module`, ...)
- Targets (`ACCEPT`, `DROP`, `REJECT`, `LOG`, `DNAT`, `SNAT`, ...)
- Module names, parameters, protocols, conntrack states
- Variables (`$NAME`, `$DOMAIN`, `$TABLE`, ...)
- User functions (`&name`)
- Strings, backtick commands, comments, IPs, numbers

### Lint rules

The linter runs automatically on ferm buffers and reports diagnostics inline. It re-lints after each change (debounced).

| Rule | Severity | Description |
|------|----------|-------------|
| `unmatched-brace` | ERROR | Unmatched `{` or `}` |
| `undefined-variable` | WARN | `$VAR` used without `@def $VAR` |
| `unknown-directive` | ERROR | `@word` not in known directives or built-in functions |
| `invalid-table` | ERROR | Table name not in `{filter, nat, mangle, raw, security}` |
| `invalid-domain` | ERROR | Domain name not in `{ip, ip6, arp, eb}` |
| `unknown-module` | WARN | Module name after `mod`/`module` not recognized |
| `policy-on-custom-chain` | ERROR | `policy` used on a non-builtin chain |
| `invalid-policy-value` | ERROR | Policy value not `ACCEPT` or `DROP` |
| `invalid-ipv4` | ERROR | IPv4 octet > 255 or CIDR prefix > 32 |
| `invalid-ipv6-cidr` | ERROR | IPv6 CIDR prefix > 128 |
| `unmatched-paren` | ERROR | Unmatched `(` or `)` |
| `unclosed-string` | ERROR | Quote opened but never closed on the line |
| `unclosed-backtick` | ERROR | Backtick `` ` `` opened but never closed on the line |
| `invalid-port` | ERROR | Port number > 65535 |
| `duplicate-variable` | WARN | `@def $VAR` defined more than once |
| `missing-semicolon` | WARN | Target (e.g. `ACCEPT`) at end of line without `;` |

Diagnostics can be inspected programmatically with `:lua vim.print(vim.diagnostic.get(0))`.

## Credits

Inspired by [cometsong/ferm.vim](https://github.com/cometsong/ferm.vim).

## License

MIT
