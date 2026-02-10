local M = {}

function M.get()
  local lnum = vim.v.lnum
  local line = vim.fn.getline(lnum):gsub('#.*$', '')

  if line:match('{%s*$') then
    return 'a1'
  end
  if line:match('^%s*}%s*$') then
    return 's1'
  end

  return '='
end

return M
