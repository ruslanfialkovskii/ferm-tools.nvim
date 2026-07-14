if vim.g.loaded_ferm_tools_cmp then
  return
end
vim.g.loaded_ferm_tools_cmp = true

-- The source is registered unconditionally; is_available() gates it on
-- filetype and config.complete.enable, so setup() order doesn't matter.
local function try_register()
  local ok, cmp = pcall(require, 'cmp')
  if not ok then
    return false
  end
  cmp.register_source('ferm', require('ferm-tools.complete').cmp_source())
  return true
end

if not try_register() then
  -- nvim-cmp may itself be lazy-loaded (commonly on InsertEnter); retry then.
  vim.api.nvim_create_autocmd('InsertEnter', {
    group = vim.api.nvim_create_augroup('ferm_tools_cmp', { clear = true }),
    once = true,
    callback = function()
      -- Schedule so a lazy-loader triggered by the same event runs first
      vim.schedule(try_register)
    end,
  })
end
