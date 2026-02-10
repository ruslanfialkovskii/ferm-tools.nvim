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
