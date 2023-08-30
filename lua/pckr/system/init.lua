if vim.system then
  return vim.system
end

return require('pckr.system.compat')
