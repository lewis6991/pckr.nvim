--- @param mode string
--- @param key string
--- @param rhs? string|fun()
--- @param opts? vim.api.keyset.keymap
--- @return fun(_: fun())
return function(mode, key, rhs, opts)
  opts = opts or {}

  if opts.desc == nil then
    opts.desc = 'pckr.nvim lazy load'
  end

  if opts.silent == nil then
    opts.silent = true
  end

  rhs = rhs or function()
    if mode == 'n' then
      vim.api.nvim_input(key)
    else
      vim.api.nvim_feedkeys(key, mode, false)
    end
  end

  --- @param loader fun()
  return function(loader)
    -- TODO(lewis6991): detect is mapping already exists
    -- TODO(Zhou-Yicheng): delete mapping if exists
    -- vim.keymap.del(mode, key)
    loader()
    vim.keymap.set(mode, key, rhs, opts)
  end
end
