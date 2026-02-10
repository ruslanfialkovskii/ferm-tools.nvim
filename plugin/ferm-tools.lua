if vim.g.loaded_ferm_tools then
  return
end
vim.g.loaded_ferm_tools = true

-- Register ferm filetype
vim.filetype.add({
  extension = {
    ferm = 'ferm',
  },
  filename = {
    ['ferm.conf'] = 'ferm',
  },
  pattern = {
    ['.*/etc/ferm/.*'] = 'ferm',
    ['.*/etc/ferm%.conf'] = 'ferm',
  },
})

-- Attach highlighter when a ferm buffer is opened
vim.api.nvim_create_autocmd('FileType', {
  group = vim.api.nvim_create_augroup('ferm_tools', { clear = true }),
  pattern = 'ferm',
  callback = function(ev)
    require('ferm-tools.highlight').attach(ev.buf)
  end,
})
