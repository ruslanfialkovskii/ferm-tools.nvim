local ok, cmp = pcall(require, 'cmp')
if ok then
  cmp.register_source('ferm', require('ferm-tools.complete').cmp_source())
end
