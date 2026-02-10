# ferm-tools.nvim

Neovim plugin for [ferm](http://ferm.foo-projects.org/) firewall configuration — syntax highlighting, indentation, and folding.

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
})
```

## Features

- **Syntax highlighting** — Lua-based highlighter using Neovim's extmarks API with treesitter highlight groups for universal colorscheme support
- **Linter** — inline diagnostics via `vim.diagnostic` that catch configuration errors before deploying firewall rules
- **Indentation** — automatic indent/dedent on `{` and `}`
- **Folding** — optional `foldmethod=expr` based on brace nesting
- **Filetype detection** — `*.ferm`, `ferm.conf`, `/etc/ferm/*`
- **Comment support** — `commentstring` set for `gc` commenting via comment plugins

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
