local M = {}

local lexer = require('ferm-tools.lexer')

function M.get()
  local lnum = vim.v.lnum
  local prev = vim.fn.prevnonblank(lnum - 1)
  if prev == 0 then return 0 end

  local prev_info = lexer.line_info(vim.fn.getline(prev))
  local cur_info = lexer.line_info(vim.fn.getline(lnum))
  local sw = vim.fn.shiftwidth()
  local ind = vim.fn.indent(prev)

  -- Indent tracks braces and parens together, so multi-line paren lists
  -- (@def $x = ( ... ), daddr ( ... )) indent like brace blocks.
  -- A leading closer already de-indented the previous line itself; it doesn't
  -- reduce the indent of what follows ('} @else {' still opens a block).
  local prev_delta = prev_info.delta + prev_info.paren_delta
  if prev_info.first_closes then
    prev_delta = prev_delta + 1
  end
  if prev_delta > 0 then
    ind = ind + sw * prev_delta
  end
  if cur_info.first_closes then
    ind = ind - sw
  end

  return math.max(ind, 0)
end

return M
