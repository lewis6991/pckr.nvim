if vim.g.loaded_pckr then
  return
end

vim.g.loaded_pckr = true

vim.api.nvim_create_user_command(
  'Pckr',
  function(args)
    return require('pckr.cli').run(args)
  end, {
    nargs = '*',
    complete = function(arglead, line)
      return require('pckr.cli').complete(arglead, line)
    end
  }
)
