local fmt = string.format

local a = require('packer.async')
local config = require('packer.config')
local log = require('packer.log')
local P = require('packer.plugin')
local plugin_types = require('packer.plugin_types')
local display = require('packer.display')

local M = {}

-- TODO(lewis6991): copied from actions.tl - consolidate
--- @param tasks fun()[]
--- @param disp? Display
--- @param kind? string
local function run_tasks(tasks, disp, kind)
  if #tasks == 0 then
    log.info('Nothing to do!')
    return
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
  return a.join(limit, interrupt_check, tasks)
end

--- @param path string
--- @param info table<string,string>
local function update(path, info)
  local dir = vim.fs.dirname(path)
  if vim.fn.isdirectory(dir) == 0 then
    vim.fn.mkdir(dir, 'p')
  end

  --- @type string[]
  local urls = vim.tbl_keys(info)
  table.sort(urls)

  local f = assert(io.open(path, "w"))
  f:write("return {\n")
  for _, url in ipairs(urls) do
    local obj = { commit = info[url] }
    f:write(fmt("  [%q] = %s,", url, vim.inspect(obj, { newline = ' ', indent = '' })))
    f:write('\n')
  end
  f:write("}")
  f:close()
end

M.lock = a.sync(function()
  local lock_tasks = {} --- @type fun()[]
  for _, plugin in pairs(P.plugins) do
    lock_tasks[#lock_tasks + 1] = a.sync(function()
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

  a.main()
  local lockfile = config.lockfile.path
  update(lockfile, info1)
  log.fmt_info('Lockfile created at %s', config.lockfile.path)
end)

--- @param plugin Plugin
--- @param disp Display
--- @param commit? string
local restore_plugin = a.sync(function(plugin, disp, commit)
  disp:task_start(plugin.name, fmt('restoring to %s', commit))

  if plugin.type == 'local' then
    disp:task_done(plugin.name, 'local plugin')
    return
  end

  if not commit then
    disp:task_failed(plugin.name, 'could not find plugin in lockfile')
    return
  end

  local plugin_type = require('packer.plugin_types')[plugin.type]

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
end, 3)

--- @class LockInfo
--- @field commit string

M.restore = a.sync(function()
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
end)

return M
