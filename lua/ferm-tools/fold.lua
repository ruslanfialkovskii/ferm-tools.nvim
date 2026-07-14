local M = {}

local lexer = require('ferm-tools.lexer')

function M.get()
  local delta = lexer.line_info(vim.fn.getline(vim.v.lnum)).delta

  if delta > 0 then
    return 'a' .. delta
  end
  if delta < 0 then
    return 's' .. -delta
  end
  return '='
end

return M
