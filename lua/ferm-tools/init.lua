local M = {}

M.config = {
  fold = false,
  lint = {
    enable = true,
    delay = 300,
  },
  format = {
    enable = true,
    on_save = false,
  },
  complete = {
    enable = true,
  },
}

function M.setup(opts)
  M.config = vim.tbl_deep_extend('force', M.config, opts or {})
end

return M
