--- @param mode string
--- @param key string
--- @return fun(_: fun())
return function(mode, key)
  --- @param loader fun()
  return function(loader)
    -- TODO(lewis6991): detect is mapping already exists
    vim.keymap.set(mode, key, function()
      vim.keymap.del(mode, key)
      loader()
      if mode == 'n' then
        vim.api.nvim_input(key)
      else
        vim.api.nvim_feedkeys(key, mode, false)
      end
    end, {
      desc = 'pckr.nvim lazy load',
      silent = true,
    })
  end
end
