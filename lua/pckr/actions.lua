local fn = vim.fn
local fmt = string.format

local a = require('pckr.async')
local config = require('pckr.config')
local log = require('pckr.log')
local util = require('pckr.util')
local fsstate = require('pckr.fsstate')

local display = require('pckr.display')

local pckr_plugins = require('pckr.plugin').plugins

local M = {}

--- @class Pckr.Result
--- @field err? string

--- @return Pckr.Display
local function open_display()
  return display.open({
    diff = function(plugin, commit, callback)
      local plugin_type = require('pckr.plugin_types')[plugin.type]
      plugin_type.diff(plugin, commit, callback)
    end,
    revert_last = function(plugin)
      local plugin_type = require('pckr.plugin_types')[plugin.type]
      plugin_type.revert_last(plugin)
    end,
  })
end

--- @param tasks (fun(): string, Pckr.Result?)[]
--- @param disp Pckr.Display?
--- @param kind string
--- @return table<string,Pckr.Result>
local function run_tasks(tasks, disp, kind)
  if #tasks == 0 then
    log.info('Nothing to do!')
    return {}
  end

  local function check()
    if disp then
      return disp:check()
    end
  end

  local limit = config.max_jobs and config.max_jobs or #tasks

  log.fmt_debug('Running tasks: %s', kind)
  if disp then
    disp:update_headline_message(string.format('%s %d / %d plugins', kind, #tasks, #tasks))
  end

  --- @type {[1]: string?, [2]: string?}[]
  local results = a.join(limit, check, tasks)

  local results1 = {} --- @type table<string,Pckr.Result>
  for _, r in ipairs(results) do
    local name = r[1]
    if name then
      results1[name] = { err = r[2] }
    end
  end

  return results1
end

--- @param task Pckr.Task
--- @param plugins string[]
--- @param disp? Pckr.Display
--- @param kind string
--- @return table<string, Pckr.Result>
local function map_task(task, plugins, disp, kind)
  local tasks = {} --- @type (fun(function))[]
  for _, v in ipairs(plugins) do
    local plugin = pckr_plugins[v]
    if not plugin then
      log.fmt_error('Unknown plugin: %s', v)
    else
      tasks[#tasks + 1] = a.curry(task, plugin, disp)
    end
  end

  return run_tasks(tasks, disp, kind)
end

--- @param dir string
--- @return boolean
local function helptags_stale(dir)
  local glob = fn.glob

  -- Adapted directly from minpac.vim
  local txts = glob(util.join_paths(dir, '*.txt'), true, true)
  vim.list_extend(txts, glob(util.join_paths(dir, '*.[a-z][a-z]x'), true, true))

  if #txts == 0 then
    return false
  end

  local tags = glob(util.join_paths(dir, 'tags'), true, true)
  vim.list_extend(tags, glob(util.join_paths(dir, 'tags-[a-z][a-z]'), true, true))

  if #tags == 0 then
    return true
  end

  ---@type integer
  local txt_newest = math.max(unpack(vim.tbl_map(fn.getftime, txts)))

  ---@type integer
  local tag_oldest = math.min(unpack(vim.tbl_map(fn.getftime, tags)))

  return txt_newest > tag_oldest
end

--- @param results table<string,Pckr.Result>
local function update_helptags(results)
  local paths = {} --- @type string[]
  for plugin_name, r in pairs(results) do
    if not r.err then
      paths[#paths + 1] = pckr_plugins[plugin_name].install_path
    end
  end

  for _, dir in ipairs(paths) do
    local doc_dir = util.join_paths(dir, 'doc')
    if helptags_stale(doc_dir) then
      log.fmt_debug('Updating helptags for %s', doc_dir)
      vim.cmd('silent! helptags ' .. fn.fnameescape(doc_dir))
    end
  end
end

--- @param plugin Pckr.Plugin
--- @param disp Pckr.Display
--- @return string?
local post_update_hook = a.sync(function(plugin, disp)
  if plugin.run or plugin.start then
    a.main()
    local loader = require('pckr.loader')
    loader.load_plugin(plugin)
  end

  if not plugin.run then
    return
  end

  a.main()

  local run_task = plugin.run

  if type(run_task) == 'function' then
    disp:task_update(plugin.name, 'running post update hook...')
    --- @type boolean, string?
    local ok, err = pcall(run_task, plugin, disp)
    if not ok then
      return 'Error running post update hook: ' .. err
    end
  elseif type(run_task) == 'string' then
    disp:task_update(plugin.name, string.format('running post update hook...("%s")', run_task))
    if vim.startswith(run_task, ':') then
      -- Run a vim command
      --- @type boolean, string?
      local ok, err = pcall(vim.cmd --[[@as function]], run_task:sub(2))
      if not ok then
        return 'Error running post update hook: ' .. err
      end
    else
      local jobs = require('pckr.jobs')
      local jr = jobs.run(run_task, { cwd = plugin.install_path })

      if jr.code ~= 0 then
        return string.format('Error running post update hook: %s', jr.stderr)
      end
    end
  end
end, 2)

--- @alias Pckr.Task fun(plugin: Pckr.Plugin, disp: Pckr.Display, cb: fun()): string?, string?

--- @param plugin Pckr.Plugin
--- @param disp Pckr.Display
--- @return string, string?
local install_task = a.sync(function(plugin, disp)
  disp:task_start(plugin.name, 'installing...')

  local plugin_type = require('pckr.plugin_types')[plugin.type]

  local err = plugin_type.installer(plugin, disp)

  plugin.installed = vim.fn.isdirectory(plugin.install_path) ~= 0

  if not err then
    err = post_update_hook(plugin, disp)
  end

  if not disp.items then
    disp.items = {}
  end

  if not err then
    disp:task_succeeded(plugin.name, 'installed')
    log.fmt_debug('Installed %s', plugin.name)
  else
    disp:task_failed(plugin.name, 'failed to install', err)
    log.fmt_debug('Failed to install %s: %s', plugin.name, vim.inspect(err))
  end

  return plugin.name, err
end, 2)

--- @param plugin Pckr.Plugin
--- @param disp Pckr.Display
--- @param __cb function
--- @return string?, string?
local update_task = a.sync(function(plugin, disp, __cb)
  disp:task_start(plugin.name, 'updating...')

  if plugin.lock then
    disp:task_succeeded(plugin.name, 'locked')
    return
  end

  local plugin_type = require('pckr.plugin_types')[plugin.type]
  local actual_update = false

  plugin.err = plugin_type.updater(plugin, disp)
  if not plugin.err and plugin.type == 'git' then
    local revs = plugin.revs
    actual_update = revs[1] ~= revs[2]
    if actual_update then
      log.fmt_debug('Updated %s', plugin.name)
      plugin.err = post_update_hook(plugin, disp)
    end
  end

  if plugin.err then
    disp:task_failed(plugin.name, 'failed to update', plugin.err)
    log.fmt_debug('Failed to update %s: %s', plugin.name, plugin.err)
  elseif actual_update then
    local info = {}
    local ncommits = 0
    if plugin.messages then
      table.insert(info, 'Commits:')
      for _, m in ipairs(vim.split(plugin.messages, '\n')) do
        for _, line in ipairs(vim.split(m, '\n')) do
          table.insert(info, '    ' .. line)
          ncommits = ncommits + 1
        end
      end

      table.insert(info, '')
    end
    -- msg = fmt('updated: %s...%s', revs[1], revs[2])
    local msg = fmt('updated: %d new commits', ncommits)
    disp:task_succeeded(plugin.name, msg, info)
  else
    disp:task_done(plugin.name, 'already up to date')
  end

  return plugin.name, plugin.err
end, 2)

--- Find and remove any plugins not currently configured for use
local do_clean = a.sync(function()
  log.debug('Starting clean')

  local to_remove = fsstate.find_extra_plugins(pckr_plugins)

  log.debug('extra plugins', to_remove)

  if not next(to_remove) then
    log.info('Already clean!')
    return
  end

  a.main()

  local lines = {} --- @type string[]
  for path, _ in pairs(to_remove) do
    lines[#lines + 1] = '  - ' .. path
  end

  if not config.autoremove
    and not display.ask_user('Removing the following directories. OK? (y/N)', lines)
  then
    log.warn('Cleaning cancelled!')
    return
  end

  for path in pairs(to_remove) do
    local result = vim.fn.delete(path, 'rf')
    if result == -1 then
      log.fmt_warn('Could not remove %s', path)
    end
  end
end, 0)

--- @param clean boolean
--- @param install boolean
--- @param update boolean
--- @param plugins? string[]
local function sync(clean, install, update, plugins)
  if not plugins or #plugins == 0 then
    plugins = vim.tbl_keys(pckr_plugins)
  end

  if clean then
    do_clean()
  end

  local missing = fsstate.find_missing_plugins(pckr_plugins)
  local missing_plugins, installed_plugins = util.partition(missing, plugins)

  a.main()

  local disp = open_display()

  local delta = util.measure(function()
    if install then
      log.debug('Gathering install tasks')
      local results = map_task(install_task, missing_plugins, disp, 'installing')
      a.main()
      update_helptags(results)
    end

    if update then
      log.debug('Gathering update tasks')
      local results = map_task(update_task, installed_plugins, disp, 'updating')
      a.main()
      update_helptags(results)
    end
  end)

  disp:finish(delta)
end

--- Install operation:
--- Installs missing plugins, then updates helptags
--- @param plugins? string[]
--- @param _opts table?
--- @param __cb function
M.install = a.sync(function(plugins, _opts, __cb)
  sync(false, true, false, plugins)
end, 2)

--- Update operation:
--- Takes an optional list of plugin names as an argument. If no list is given,
--- operates on all managed plugins then updates installed plugins and updates
--- helptags.
--- @param plugins? string[] List of plugin names to update.
--- @param _opts table?
--- @param __cb function
M.update = a.sync(function(plugins, _opts, __cb)
  sync(false, false, true, plugins)
end, 2)

--- Sync operation:
--- Takes an optional list of plugin names as an argument. If no list is given,
--- operates on all managed plugins. Installs missing plugins, then updates
--- installed plugins and updates helptags
--- @param plugins? string[]
--- @param _opts table?
--- @param __cb function
M.sync = a.sync(function(plugins, _opts, __cb)
  sync(true, true, true, plugins)
end, 2)

--- @param _ any
--- @param _opts table?
--- @param __cb function
M.status = a.sync(function(_, _opts, __cb)
  require('pckr.status').run()
end, 2)

--- Clean operation:
--- Finds plugins present in the `pckr` package but not in the managed set
--- @param _ any
--- @param _opts table?
--- @param __cb function
M.clean = a.sync(function(_, _opts, __cb)
  do_clean()
end, 2)

--- @param _ any
--- @param _opts table?
--- @param __cb function
M.lock = a.sync(function(_, _opts, __cb)
  require('pckr.lockfile').lock()
end, 2)

--- @param _ any
--- @param _opts table?
--- @param __cb function
M.restore = a.sync(function(_, _opts, __cb)
  require('pckr.lockfile').restore()
end, 2)

--- @param _ any
--- @param _opts table?
M.log = function(_, _opts)
  local messages = require('pckr.log').messages
  for _, m in ipairs(messages) do
    vim.api.nvim_echo({m}, false, {})
  end
end

return M
