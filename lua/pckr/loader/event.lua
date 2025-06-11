--- @param events string|string[]
--- @param pattern string?
--- @return fun(_: fun())
return function(events, pattern)
  return function(loader)
    vim.api.nvim_create_autocmd(events, {
      pattern = pattern,
      once = true,
      desc = 'pckr.nvim lazy load',
      callback = function()
        loader()
      end,
    })
  end
end
