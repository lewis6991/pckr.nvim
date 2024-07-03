--- @param events string|string[]
--- @param pattern string?
--- @return fun(_: fun())
return function(events, pattern)
  return function(loader)
    local done = false
    vim.api.nvim_create_autocmd(events, {
      pattern = pattern,
      once = true,
      desc = 'pckr.nvim lazy load',
      callback = function(ev)
        if done then
          return true
        end
        -- HACK: work-around for https://github.com/neovim/neovim/issues/25526
        done = true
        loader()
        vim.api.nvim_exec_autocmds(ev.event, {
          buffer = ev.buf,
          group = ev.group,
          modeline = false,
          data = ev.data,
        })
      end,
    })
  end
end
