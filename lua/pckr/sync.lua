local fn = vim.fn
local fmt = string.format

local async = require('pckr.async')
local pckr_plugins = require('pckr.plugin').plugins_by_name
local config = require('pckr.config')
local log = require('pckr.log')
local util = require('pckr.util')

local display = require('pckr.display')

local M = {}

--- @return Pckr.Display
local function open_display()
  return display.open({
    diff = async.sync(2, function(plugin, commit, __cb)
      local plugin_type = require('pckr.plugin_types')[plugin.type]
      plugin_type.diff(plugin, commit)
    end),
    revert_last = function(plugin)
      local plugin_type = require('pckr.plugin_types')[plugin.type]
      plugin_type.revert_last(plugin)
    end,
  })
end

--- @param plugins table<string,Pckr.Plugin>
--- @return table<string,string>
local function find_extra_plugins(plugins)
  -- build a hashmap of all the plugins by their installation path
  local plugin_paths = {} --- @type table<string,Pckr.Plugin>
  for _, plugin in pairs(plugins) do
    local p = vim.uv.fs_realpath(plugin.install_path)
    if p then
      plugin_paths[p] = plugin
    end
  end

  local extra = {} --- @type table<string,string>

  for dir, dir_is_start in pairs({
    [config._opt_dir] = false,
    [config._start_dir] = true
  }) do
    for name, ty in vim.fs.dir(dir) do
      if ty ~= 'file' then
        local path = util.join_paths(dir, name)
        local real_path = vim.uv.fs_realpath(path)
        if not real_path then
          -- Broken link
          assert(ty == 'link')
          extra[path] = name
        else
          local plugin = plugin_paths[real_path]
          if not plugin or dir_is_start ~= (plugin.start or false) then
            extra[real_path] = name
          end
        end
      end
    end
  end

  return extra
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
  local results = async.join(limit, tasks, check)

  local results1 = {} --- @type table<string,Pckr.Result>
  for _, r in ipairs(results) do
    local name = r[1]
    if name then
      results1[name] = { err = r[2] }
    end
  end

  return results1
end

--- @alias Pckr.Task fun(plugin: Pckr.Plugin, disp: Pckr.Display, cb: fun()): string?, string?

--- @class Pckr.Result
--- @field err? string

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
      tasks[#tasks + 1] = async.curry(task, plugin, disp)
    end
  end

  return run_tasks(tasks, disp, kind)
end

--- @async
--- @param plugin Pckr.Plugin
--- @param disp Pckr.Display
--- @return string?
local function post_update_hook(plugin, disp)
  if plugin.run or plugin.start then
    async.schedule()
    local loader = require('pckr.loader')
    loader.load_plugin(plugin)
  end

  if not plugin.run then
    return
  end

  async.schedule()

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
end

--- @param plugin Pckr.Plugin
--- @param disp Pckr.Display
--- @return string, string?
local install_task = async.sync(2, function(plugin, disp)
  disp:task_start(plugin.name, 'installing...')

  local plugin_type = require('pckr.plugin_types')[plugin.type]

  local err = plugin_type.installer(plugin, disp)

  plugin.installed = vim.fn.isdirectory(plugin.install_path) ~= 0

  if not err then
    err = post_update_hook(plugin, disp)
  end

  disp.items = disp.items or {}

  async.schedule()

  if not err then
    disp:task_succeeded(plugin.name, 'installed')
    log.fmt_debug('Installed %s', plugin.name)
  else
    disp:task_failed(plugin.name, 'failed to install', err)
    log.fmt_debug('Failed to install %s: %s', plugin.name, vim.inspect(err))
  end

  return plugin.name, err
end)

--- @param plugin Pckr.Plugin
--- @param disp Pckr.Display
--- @param __cb? function
--- @return string?, string?
local update_task = async.sync(2, function(plugin, disp, __cb)
  disp:task_start(plugin.name, 'updating...')

  if plugin.lock then
    disp:task_succeeded(plugin.name, 'locked')
    return
  end

  local plugin_type = require('pckr.plugin_types')[plugin.type]

  plugin.err = plugin_type.updater(plugin, disp)

  async.schedule()

  if plugin.err then
    disp:task_failed(plugin.name, 'failed to update', plugin.err)
    log.fmt_debug('Failed to update %s: %s', plugin.name, plugin.err)
    return plugin.name, plugin.err
  end

  local revs = plugin.revs

  if revs[1] == revs[2] then
    disp:task_done(plugin.name, 'up-to-date')
    return plugin.name
  end

  log.fmt_debug('Updated %s', plugin.name)
  plugin.err = post_update_hook(plugin, disp)

  if plugin.err then
    disp:task_failed(plugin.name, 'failed to run post update hook', plugin.err)
    log.fmt_debug('Failed to run post update hook %s: %s', plugin.name, plugin.err)
    return plugin.name, plugin.err
  end

  async.schedule()

  local info = {} --- @type string[]
  local ncommits = 0
  if plugin.messages then
    info[#info+1] = 'Commits:'
    for _, m in ipairs(vim.split(plugin.messages, '\n')) do
      for _, line in ipairs(vim.split(m, '\n')) do
        info[#info+1] = '    ' .. line
        ncommits = ncommits + 1
      end
    end

    info[#info+1] = ''
  end

  disp:task_succeeded(plugin.name, fmt('updated: %d new commits', ncommits), info)

  return plugin.name
end)

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

--- @return Pckr.Plugin
local function get_pckr_spec()
  local source = debug.getinfo(1, 'S').short_src
  assert(source:match('/lua/pckr/sync.lua$'))
  local pckr_loc = source:gsub('/lua/pckr/sync.lua', '')

  return {
    name = 'pckr.nvim',
    install_path = pckr_loc,
    type = 'local',
    revs = {},
    _dir = pckr_loc,
  }
end

--- @async
--- Find and remove any plugins not currently configured for use
function M.clean()
  log.debug('Starting clean')

  local to_remove = find_extra_plugins(pckr_plugins)

  log.debug('extra plugins', to_remove)

  if not next(to_remove) then
    log.info('Already clean!')
    return
  end

  async.schedule()

  local lines = {} --- @type string[]
  for path, _ in pairs(to_remove) do
    lines[#lines + 1] = '  - ' .. path
  end

  if
    not config.autoremove
    and not display.ask_user('Removing the following directories. OK? (y/N)', lines)
  then
    log.warn('Cleaning cancelled!')
    return
  end

  for path in pairs(to_remove) do
    if vim.fn.delete(path, 'rf') == -1 then
      log.fmt_warn('Could not remove %s', path)
    end
  end
end

--- @async
--- @param op 'sync'|'install'|'update'|'upgrade'|'clean'
--- @param plugins? string[]
function M.sync(op, plugins)
  if not plugins or #plugins == 0 then
    plugins = vim.tbl_keys(pckr_plugins)
  end

  local clean = op == 'sync' or op == 'clean'
  local install = op == 'sync' or op == 'install'
  local update = op == 'sync' or op == 'update'
  local upgrade = op == 'sync' or op == 'upgrade'

  if clean then
    M.clean()
  end

  --- @type string[], string[]
  local to_install, to_update = {}, {}
  for _, plugin in pairs(pckr_plugins) do
    if plugin.installed then
      to_update[#to_update + 1] = plugin.name
    else
      to_install[#to_install + 1] = plugin.name
    end
  end

  async.schedule()

  local disp = open_display()

  local delta = util.measure(function()
    if install then
      log.debug('Gathering install tasks')
      local results = map_task(install_task, to_install, disp, 'installing')
      async.schedule()
      update_helptags(results)
    end

    if update then
      log.debug('Gathering update tasks')
      local results = map_task(update_task, to_update, disp, 'updating')
      async.schedule()
      update_helptags(results)
    end

    if upgrade then
      pckr_plugins['pckr.nvim'] = get_pckr_spec()
      local results = map_task(update_task, { 'pckr.nvim' }, disp, 'updating')
      async.schedule()
      update_helptags(results)
    end
  end)

  disp:finish(delta)
end

return M
