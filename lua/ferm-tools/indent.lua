local M = {}

function M.get()
  local lnum = vim.v.lnum
  local prev = vim.fn.prevnonblank(lnum - 1)
  if prev == 0 then return 0 end

  local prev_line = vim.fn.getline(prev):gsub('#.*$', '')
  local curr_line = vim.fn.getline(lnum):gsub('#.*$', '')
  local ind = vim.fn.indent(prev)

  if prev_line:match('{%s*$') then
    ind = ind + vim.fn.shiftwidth()
  end
  if curr_line:match('^%s*}') then
    ind = ind - vim.fn.shiftwidth()
  end

  return math.max(ind, 0)
end

return M
