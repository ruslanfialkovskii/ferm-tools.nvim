if vim.g.loaded_ferm_tools then
  return
end
vim.g.loaded_ferm_tools = true

local group = vim.api.nvim_create_augroup('ferm_tools', { clear = true })

-- Attach highlighter when a ferm buffer is opened
vim.api.nvim_create_autocmd('FileType', {
  group = group,
  pattern = 'ferm',
  callback = function(ev)
    require('ferm-tools.highlight').attach(ev.buf)
    local config = require('ferm-tools').config
    if config.lint.enable then
      require('ferm-tools.lint').attach(ev.buf)
    end
  end,
})

-- :FermFormat command
vim.api.nvim_create_user_command('FermFormat', function(opts)
  local bufnr = vim.api.nvim_get_current_buf()
  if opts.range == 2 then
    require('ferm-tools.format').range(bufnr, opts.line1, opts.line2)
  else
    require('ferm-tools.format').buf(bufnr)
  end
end, { range = true, desc = 'Format ferm configuration' })

-- Format-on-save autocmd (created once, checks config dynamically)
vim.api.nvim_create_autocmd('BufWritePre', {
  group = group,
  pattern = '*',
  callback = function(ev)
    if vim.bo[ev.buf].filetype ~= 'ferm' then
      return
    end
    local config = require('ferm-tools').config
    if config.format.on_save then
      require('ferm-tools.format').buf(ev.buf)
    end
  end,
})
