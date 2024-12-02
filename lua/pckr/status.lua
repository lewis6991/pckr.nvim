local fmt = string.format
local async = require('pckr.async')
local log = require('pckr.log')
local display = require('pckr.display')

local M = {}

---format a configuration value of unknown type into a string or list of strings
---@param key string
---@param value any
---@return string|string[]?
local function format_values(key, value)
  if type(value) == 'table' and not next(value) then
    return
  elseif type(value) == 'function' then
    local info = debug.getinfo(value, 'Sl')
    return fmt('"%s:%d"', info.source:sub(2), info.linedefined)
  elseif key == 'loaded' or key == 'installed' then
    return
  elseif vim.endswith(key, 'time') and type(value) == 'number' then
    return fmt('%.2fms', value)
  elseif key == 'err' or key == 'messages' then
    local r = {} --- @type string[]
    for _, v in ipairs(vim.split(value, '\n')) do
      r[#r + 1] = '  | '.. v
    end
    return r
  elseif key == 'url' then
    return vim.inspect(value)
  elseif key == 'files' then
    local t = {} --- @type [string,number,number][]
    for k, v in
      pairs(value --[[@as table<string,[number,number]>]])
    do
      t[#t + 1] = { k, unpack(v) }
    end

    table.sort(t, function(a, b)
      return a[2] + a[3] > b[2] + b[3]
    end)

    local r = {} --- @type string[]
    for _, v in ipairs(t) do
      r[#r + 1] = fmt("    '%s': %.2fms (%.2fms)", v[1], v[2] + v[3], v[2])
    end
    return r
  end

  return vim.inspect(value)
end

local plugin_keys_exclude = {
  full_name = true,
  total_time = true,
  name = true,
  simple = true,
  _dir = true,
}

--- @param plugin Pckr.Plugin
local function add_profile_data(plugin)
  plugin.files = {}

  plugin.load_time = 0

  local path_times = require('pckr.loader').path_times
  for p, d in pairs(path_times) do
    if vim.startswith(p, plugin.install_path .. '/') then
      p = p:gsub(vim.pesc(plugin.install_path .. '/'), '') --- @type string
      plugin.files[p] = d
      if
        not plugin._loaded_after_vim_enter and vim.startswith(p, 'plugin/')
        or vim.startswith(p, 'after/plugin/')
      then
        plugin.load_time = plugin.load_time + d[1] + d[2]
      end
    end
  end
end

--- @param task table<string,any>
--- @return string[]
local function get_task_status(task)
  local config_lines = {}
  for key, value in vim.spairs(task) do
    if not plugin_keys_exclude[key] then
      local key_s = key:gsub('_', ' ')
      local details = format_values(key, value)
      if type(details) == 'string' then
        -- insert a position one so that one line details appear above multiline ones
        table.insert(config_lines, 1, fmt('- %s: %s', key_s, details))
      elseif details then
        vim.list_extend(config_lines, { fmt('- %s: ', key_s), unpack(details) })
      end
    end
  end

  return config_lines
end

--- @param plugin Pckr.Plugin
--- @return string
local function get_load_state(plugin)
  if plugin.loaded then
    if plugin._loaded_after_vim_enter then
      return '(deferred)'
    end
    return ''
  elseif plugin.installed then
    return '(not loaded)'
  end
  return '(not installed)'
end

--- @param total_plugin_time number
--- @return string[]
local function pckr_info(total_plugin_time)
  local pckr_install_path = debug.getinfo(1, 'S').source:sub(2):gsub('/lua.*', '')
  local measure_times = require('pckr.util').measure_times

  return {
    fmt('- install_path: "%s"', pckr_install_path),
    '- profile:',
    fmt('  - spec time: %.2fms', measure_times.spec_time),
    fmt('  - load time (deferred): %.2fms', measure_times.load_deferred),
    fmt('  - load time: %.2fms', measure_times.load),
    fmt('    - rtp time: %.2fms', measure_times.rtp),
    fmt('    - walk time: %.2fms', measure_times.walk),
    fmt('    - packadd time: %.2fms', measure_times.packadd),
    fmt('  - loadplugins time: %.2fms', measure_times.loadplugins),
    fmt('  - plugin time: %.2fms', total_plugin_time),
  }
end

--- @async
--- @param plugin Pckr.Plugin
--- @return string?
local function get_update_state(plugin)
  if plugin.lock then
    return 'locked'
  end

  local plugin_type = require('pckr.plugin_types')[plugin.type]

  plugin.err = plugin_type.updater(plugin, nil, {check=true})

  async.main()

  if plugin.err then
    return 'failed to check for updates'
  end

  local revs = plugin.revs
  if revs[1] == revs[2] then
    return -- up-to-date
  end

  local lines = vim.split(plugin.messages or '', '\n')
  local ahead = #lines > 0 and vim.startswith(revs[1], lines[1]:match('[^ ]+'))

  local ncommits = #lines

  if ahead then
    return fmt('%d commits ahead', ncommits)
  end

  return fmt('update available: %d new commits', ncommits)
end

--- Creates a copy of a list-like table such that any nested tables are
--- "unrolled" and appended to the result.
--- @param t table List-like table
--- @return table # Flattened copy of the given list-like table
local function tbl_flatten(t)
  local result = {}
  --- @param t0 table<any,any>
  local function _tbl_flatten(t0)
    for i = 1, #t0 do
      local v = t0[i]
      if type(v) == 'table' then
        _tbl_flatten(v)
      elseif v then
        table.insert(result, v)
      end
    end
  end
  _tbl_flatten(t)
  return result
end

--- @async
function M.run()
  local plugins_by_name = require('pckr.plugin').plugins_by_name
  if not plugins_by_name then
    log.warn('pckr_plugins table is nil! Cannot run pckr.status()!')
    return
  end

  local disp = assert(display.open())

  disp:update_headline_message(fmt('Total plugins: %d', vim.tbl_count(plugins_by_name)))

  local total_plugin_time = 0

  for _, plugin in pairs(plugins_by_name) do
    add_profile_data(plugin)

    if plugin.loaded then
      plugin.total_time = plugin.load_time + (plugin.config_time or 0)
      total_plugin_time = total_plugin_time + plugin.total_time
    end
  end

  local measure_times = require('pckr.util').measure_times
  local pckr_time = measure_times.spec_time + measure_times.load + measure_times.loadplugins

  disp:task_done('pckr.nvim', fmt('(%.2fms)', pckr_time), pckr_info(total_plugin_time))

  for _, plugin in pairs(plugins_by_name) do
      if plugin.loaded and plugin.total_time then
        plugin._profile = fmt('(%.2fms)', plugin.total_time)
      end

      local state = table.concat(tbl_flatten({
        get_load_state(plugin),
        plugin._profile,
      }), ' ')

    disp:task_done(plugin.name, state, get_task_status(plugin))
  end

  disp:task_sort(function(a, b)
    if a == 'pckr.nvim' then
      return true
    elseif b == 'pckr.nvim' then
      return false
    end

    return (plugins_by_name[a].total_time or 0) > (plugins_by_name[b].total_time or 0)
  end)

  local tasks = {} --- @type (fun(function))[]
  for _, plugin in pairs(plugins_by_name) do
    tasks[#tasks + 1] = async.sync(0, function()
      local state = table.concat(tbl_flatten({
        get_load_state(plugin),
        plugin._profile,
        get_update_state(plugin),
      }), ' ')

      disp:task_done(plugin.name, state)
    end)
  end

  local config = require('pckr.config')
  local limit = config.max_jobs and config.max_jobs or #tasks

  disp:update_headline_message(fmt('Checking for updates %d / %d plugins', #tasks, #tasks))

  --- @type {[1]: string?, [2]: string?}[]
  async.join(limit, function()
    return disp:check()
  end, tasks)

  disp:update_headline_message(fmt('Total plugins: %d (%.2fms)', vim.tbl_count(plugins_by_name), pckr_time))
end

return M
