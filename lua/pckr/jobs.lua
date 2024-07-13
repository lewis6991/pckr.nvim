-- Interface with Neovim job control and provide a simple job sequencing structure
local a = require('pckr.async')
local log = require('pckr.log')
local system = require('pckr.system')

local M = {}

--- Main exposed function for the jobs module. Takes a task and options and returns an async
-- function that will run the task with the given opts via vim.loop.spawn
--- @param task string|string[]
--- @param opts vim.SystemOpts
--- @param callback? fun(_: vim.SystemCompleted)
--- @type fun(task: string|string[], opts: vim.SystemOpts): vim.SystemCompleted
M.run = a.wrap(3, function(task, opts, callback)
  if type(task) == 'string' then
    local shell = os.getenv('SHELL') or vim.o.shell
    local minus_c = shell:find('cmd.exe$') and '/c' or '-c'
    task = { shell, minus_c, task }
  end

  log.fmt_trace('Running job: cmd = %s, cwd = %s', table.concat(task, ' '), opts.cwd)

  system(task, opts, function(obj)
    if callback then
      callback(obj)
    end
  end)
end)

return M
