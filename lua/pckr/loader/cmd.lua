--- @param cmd string
--- @return fun(_: fun())
return function(cmd)
  --- @param loader fun()
  return function(loader)
    vim.api.nvim_create_user_command(cmd, function(args)
      vim.api.nvim_del_user_command(cmd)
      loader()
      vim.cmd(
        string.format(
          '%s %s%s%s %s',
          args.mods or '',
          args.line1 == args.line2 and '' or args.line1 .. ',' .. args.line2,
          cmd,
          args.bang and '!' or '',
          args.args
        )
      )
    end, {
      bang = true,
      nargs = '*',
      range = true,
      complete = function(_arg_lead, cmd_line, _cursor_pos)
        vim.api.nvim_del_user_command(cmd)
        loader()
        return vim.fn.getcompletion(cmd_line, 'cmdline')
      end,
    })
  end
end
