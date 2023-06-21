-- Interface with Neovim job control and provide a simple job sequencing structure
local a = require('pckr.async')
local log = require('pckr.log')

local M = {}

--- Main exposed function for the jobs module. Takes a task and options and returns an async
-- function that will run the task with the given opts via vim.loop.spawn
--- @param task string|string[]
--- @param opts SystemOpts
--- @param callback? fun(_: SystemCompleted)
--- @type fun(task: string|string[], opts: SystemOpts): SystemCompleted
M.run = a.wrap(function(task, opts, callback)
  if type(task) == 'string' then
    local shell = os.getenv('SHELL') or vim.o.shell
    local minus_c = shell:find('cmd.exe$') and '/c' or '-c'
    task = { shell, minus_c, task }
  end

  log.fmt_trace(
    'Running job: cmd = %s, cwd = %s',
    table.concat(task, ' '),
    opts.cwd
  )

  vim.system(task, opts, function(obj)
    if callback then
      callback(obj)
    end
  end)
end, 3)

return M
