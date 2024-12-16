local fmt = string.format

local a = require('pckr.async')
local config = require('pckr.config')
local log = require('pckr.log')
local P = require('pckr.plugin')
local plugin_types = require('pckr.plugin_types')
local display = require('pckr.display')

--- @class Pckr.lockfile
local M = {}

-- TODO(lewis6991): copied from actions.tl - consolidate
--- @param tasks fun()[]
--- @param disp? Pckr.Display
--- @param kind? string
--- @return {[1]: string, [2]: string }[]
local function run_tasks(tasks, disp, kind)
  if #tasks == 0 then
    log.info('Nothing to do!')
    return {}
  end

  local function interrupt_check()
    if disp then
      return disp:check()
    end
  end

  local limit = config.max_jobs and config.max_jobs or #tasks

  if kind then
    log.fmt_debug('Running tasks: %s', kind)
  end
  if disp then
    disp:update_headline_message(string.format('%s %d / %d plugins', kind, #tasks, #tasks))
  end
  return a.join(limit, tasks, interrupt_check)
end

--- @param path string
--- @param info table<string,string>
local function update(path, info)
  local dir = assert(vim.fs.dirname(path))
  if vim.fn.isdirectory(dir) == 0 then
    vim.fn.mkdir(dir, 'p')
  end

  --- @type string[]
  local urls = vim.tbl_keys(info)
  table.sort(urls)

  local f = assert(io.open(path, 'w'))
  f:write('return {\n')
  for _, url in ipairs(urls) do
    local obj = { commit = info[url] }
    f:write(fmt('  [%q] = %s,', url, vim.inspect(obj, { newline = ' ', indent = '' })))
    f:write('\n')
  end
  f:write('}')
  f:close()
end

--- @async
function M.lock()
  local lock_tasks = {} --- @type fun()[]
  for _, plugin in pairs(P.plugins) do
    lock_tasks[#lock_tasks + 1] = a.sync(0, function()
      local plugin_type = plugin_types[plugin.type]
      if plugin_type.get_rev then
        return plugin.url, (plugin_type.get_rev(plugin))
      end
    end)
  end

  local info = run_tasks(lock_tasks) --[[@as {[1]:string,[2]:string}[] ]]
  local info1 = {} --- @type table<string,string>
  for _, i in ipairs(info) do
    if i[1] then
      info1[i[1]] = i[2]
    end
  end

  a.schedule()
  local lockfile = config.lockfile.path
  update(lockfile, info1)
  log.fmt_info('Lockfile created at %s', config.lockfile.path)
end

--- @param plugin Pckr.Plugin
--- @param disp Pckr.Display
--- @param commit? string
local restore_plugin = a.sync(3, function(plugin, disp, commit)
  disp:task_start(plugin.name, fmt('restoring to %s', commit))

  if plugin.type == 'local' then
    disp:task_done(plugin.name, 'local plugin')
    return
  end

  if not commit then
    disp:task_failed(plugin.name, 'could not find plugin in lockfile')
    return
  end

  local plugin_type = require('pckr.plugin_types')[plugin.type]

  local rev = plugin_type.get_rev(plugin)
  if commit == rev then
    disp:task_done(plugin.name, fmt('already at commit %s', commit))
    return
  end

  plugin.err = plugin_type.revert_to(plugin, commit)
  if plugin.err then
    disp:task_failed(plugin.name, fmt('failed to restore to commit %s', commit))
    return
  end

  disp:task_succeeded(plugin.name, fmt('restored to commit %s', commit))
end)

--- @class LockInfo
--- @field commit string

--- @async
function M.restore()
  local disp = assert(display.open({}))
  disp:update_headline_message('Restoring from lockfile')

  local lockfile = config.lockfile.path
  --- @type table<string,LockInfo>
  local lockinfo = assert(loadfile(lockfile))()

  local restore_tasks = {} --- @ type fun()[]
  for _, plugin in pairs(P.plugins) do
    local info = lockinfo[plugin.url] or {}
    restore_tasks[#restore_tasks + 1] = a.curry(restore_plugin, plugin, disp, info.commit)
  end

  run_tasks(restore_tasks, disp, 'restoring')
end

return M
