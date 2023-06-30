
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
