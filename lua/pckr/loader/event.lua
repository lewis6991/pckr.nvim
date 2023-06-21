--- @param events string[]
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
        -- TODO(lewis6991): should we re-issue the event? (#1163)
        -- vim.api.nvim_exec_autocmds(event, { modeline = false })
      end,
    })
  end
end
