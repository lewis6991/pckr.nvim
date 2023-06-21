local log = require('pckr.log')
local util = require('pckr.util')

--- @type fun()[]
local plugin_configs = {}

--- @param name string
--- @return fun(err: string)
local function config_error_handler(name)
  --- @param err string
  return function(err)
    log.fmt_error('Error running config for %s:\n\t%s', name, err)
  end
end

--- @param plugin Pckr.Plugin
--- @param field 'config' | 'config_pre'
local function apply_config(plugin, field)
  local c = plugin[field] ---@type fun()?

  if not c then
    return
  end

  xpcall(function()
    log.fmt_debug('Running %s for %s', field, plugin.name)
    local delta = util.measure(c)
    log.fmt_debug('%s for %s took %fms', field, plugin.name, delta * 1000)
    plugin.config_time = delta * 1000
  end, config_error_handler(plugin.name))
end

--- @param path string
--- @param fn fun(_: string, _: string, _: string): boolean?
local function ls(path, fn)
  local handle = vim.loop.fs_scandir(path)
  while handle do
    local name, t = vim.loop.fs_scandir_next(handle)
    if not name or not t then
      break
    end
    if fn(util.join_paths(path, name), name, t) == false then
      break
    end
  end
end

--- @param path string
--- @param fn fun(_: string, _: string, _: string): boolean?
local function walk(path, fn)
  ls(path, function(child, name, ftype)
    if ftype == 'directory' then
      walk(child, fn)
    end
    fn(child, name, ftype)
  end)
end

local function source_after(install_path)
  walk(util.join_paths(install_path, 'after', 'plugin'), function(path, _, t)
    local ext = path:sub(-4)
    if t == 'file' and (ext == '.lua' or ext == '.vim') then
      log.fmt_debug('sourcing %s', path)
      vim.cmd.source({ path, mods = { silent = true } })
    end
  end)
end

local M = {}

local orig_loadfile = loadfile

--- @type table<string,{[1]:number,[2]:number}>
M.path_times = {}

_G.loadfile = function(path)
  local start1 = vim.loop.hrtime()
  local chunk, err = orig_loadfile(path)
  --- @type number
  local load_time = (vim.loop.hrtime() - start1) / 1000000
  if not chunk then
    return nil, err
  end

  return function(...)
    local start2 = vim.loop.hrtime()
    local r = { chunk(...) }
    --- @type number
    local exec_time = (vim.loop.hrtime() - start2) / 1000000
    M.path_times[path] = { load_time, exec_time }
    return unpack(r, 1, table.maxn(r))
  end
end

--- @param plugin Pckr.Plugin
function M.load_plugin(plugin)
  if plugin.loaded then
    log.fmt_debug('Already loaded %s', plugin.name)
    return
  end

  if not plugin.installed then
    log.fmt_warn('%s is not installed', plugin.name)
    return
  end

  log.fmt_debug('Running loader for %s', plugin.name)

  apply_config(plugin, 'config_pre')

  -- Set the plugin as loaded before config is run in case something in the
  -- config tries to load this same plugin again
  plugin.loaded = true

  if plugin.requires then
    log.fmt_debug('Loading dependencies of %s', plugin.name)
    local all_plugins = require('pckr.plugin').plugins

    for _, name in ipairs(plugin.requires) do
      M.load_plugin(all_plugins[name])
    end
  end

  log.fmt_debug('Loading %s', plugin.name)
  if vim.v.vim_did_enter == 0 then
    if not plugin.start then
      vim.cmd.packadd({ plugin.name, bang = true })
    end

    plugin_configs[#plugin_configs + 1] = function()
      apply_config(plugin, 'config')
    end
  else
    if not plugin.start then
      vim.cmd.packadd(plugin.name)
      source_after(plugin.install_path)
    end

    apply_config(plugin, 'config')
  end
end

--- @generic T
--- @param x T|T[]
--- @return T[]
local function ensurelist(x)
  return type(x) == 'table' and x or { x }
end

--- @param plugins table<string,Pckr.Plugin>
function M.setup(plugins)
  for _, plugin in pairs(plugins) do
    if not plugin.cond then
      M.load_plugin(plugin)
    else
      for _, cond in ipairs(ensurelist(plugin.cond)) do
        cond(function()
          M.load_plugin(plugin)
        end)
      end
    end
  end
end

function M.run_configs()
  for _, cfg in ipairs(plugin_configs) do
    cfg()
  end
  plugin_configs = {}
end

return M
