--- @param mode string
--- @param key string
--- @param _rhs? string|fun()
--- @param _opts? table
--- @return fun(_: fun())
return function(mode, key, _rhs, _opts)
  if not _opts then
    _opts = {
      desc = 'pckr.nvim lazy load',
      silent = true,
    }
  end
  --- @param loader fun()
  return function(loader)
    -- TODO(lewis6991): detect is mapping already exists
    -- TODO(Zhou-Yicheng): delete mapping if exists
    -- vim.keymap.del(mode, key)
    loader()
    if _rhs then
      vim.keymap.set(mode, key, _rhs, _opts)
    else
      vim.keymap.set(mode, key, function()
        if mode == 'n' then
          vim.api.nvim_input(key)
        else
          vim.api.nvim_feedkeys(key, mode, false)
        end
      end, _opts)
    end
  end
end
