vim.bo.commentstring = '# %s'
vim.bo.comments = 'b:#'
vim.opt_local.formatoptions:remove('t')
vim.opt_local.formatoptions:append('croql')
vim.bo.indentexpr = "v:lua.require('ferm-tools.indent').get()"
vim.bo.indentkeys = '0{,0},!^F,o,O'

local config = require('ferm-tools').config
if config.fold then
  vim.wo.foldmethod = 'expr'
  vim.wo.foldexpr = "v:lua.require('ferm-tools.fold').get()"
  vim.wo.foldlevel = 99
end

if config.format.enable then
  vim.bo.formatexpr = "v:lua.require('ferm-tools.format').formatexpr()"
end

if config.complete.enable then
  vim.bo.omnifunc = "v:lua.require('ferm-tools.complete').omnifunc()"
end
