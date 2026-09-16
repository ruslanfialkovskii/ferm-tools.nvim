local M = {}

local lexer = require('ferm-tools.lexer')

function M.get()
  -- Fold on braces and parens together, matching indent and the formatter, so
  -- multi-line paren lists collapse like brace blocks.
  local info = lexer.line_info(vim.fn.getline(vim.v.lnum))
  local delta = info.delta + info.paren_delta

  if delta > 0 then
    return 'a' .. delta
  end
  if delta < 0 then
    return 's' .. -delta
  end
  return '='
end

return M
