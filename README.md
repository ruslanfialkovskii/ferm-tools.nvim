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
})
```

## Features

- **Syntax highlighting** — Lua-based highlighter using Neovim's extmarks API with treesitter highlight groups for universal colorscheme support
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

## Credits

Inspired by [cometsong/ferm.vim](https://github.com/cometsong/ferm.vim).

## License

MIT
