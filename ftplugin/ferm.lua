vim.bo.commentstring = '# %s'
vim.bo.comments = 'b:#'
vim.opt_local.formatoptions:remove('t')
vim.opt_local.formatoptions:append('croql')
vim.bo.indentexpr = "v:lua.require('ferm-tools.indent').get()"
vim.bo.indentkeys = '0{,0},!^F,o,O'

local undo = {
  'setlocal commentstring< comments< formatoptions< indentexpr< indentkeys<',
}

local config = require('ferm-tools').config
if config.fold then
  -- Buffer-scoped window options: reset when another buffer enters the window
  vim.wo[0][0].foldmethod = 'expr'
  vim.wo[0][0].foldexpr = "v:lua.require('ferm-tools.fold').get()"
  vim.wo[0][0].foldlevel = 99
  undo[#undo + 1] = 'setlocal foldmethod< foldexpr< foldlevel<'
end

if config.format.enable then
  vim.bo.formatexpr = "v:lua.require('ferm-tools.format').formatexpr()"
  undo[#undo + 1] = 'setlocal formatexpr<'
end

if config.complete.enable then
  -- Function option: paren-less funcref form (unlike the expression options above)
  vim.bo.omnifunc = "v:lua.require'ferm-tools.complete'.omnifunc"
  undo[#undo + 1] = 'setlocal omnifunc<'
end

vim.b.undo_ftplugin = table.concat(undo, ' | ')
