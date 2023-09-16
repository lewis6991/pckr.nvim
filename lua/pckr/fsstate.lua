local a = require('pckr.async')
local util = require('pckr.util')
local log = require('pckr.log')
local config = require('pckr.config')

local uv = vim.loop

local M = {}

local function toboolean(x)
  return x and true or false
end

---@param path1 string
---@param path2 string
---@return boolean
local function cmp_paths(path1, path2)
  return uv.fs_realpath(path1) == uv.fs_realpath(path2)
end

--- @param path string
--- @param is_start boolean
--- @param plugins table<string,Pckr.Plugin>
--- @return boolean
local function path_is_plugin(path, is_start, plugins)
  for _, plugin in pairs(plugins) do
    if cmp_paths(path, plugin.install_path) and is_start == toboolean(plugin.start) then
      return true
    end
  end
  return false
end

--- Return plugins installed in config.opt_dir and config.start_dir
--- @return table<string,string> opt_plugins
--- @return table<string,string> start_plugins
local get_installed_plugins = a.sync(function()
  log.debug('Updating FS state')

  local opt_plugins = {} --- @type table<string,string>
  local start_plugins = {} --- @type table<string,string>

  for dir, tbl in pairs({
    [config.opt_dir] = opt_plugins,
    [config.start_dir] = start_plugins,
  }) do
    for name, ty in vim.fs.dir(dir) do
      if ty ~= 'file' then
        tbl[util.join_paths(dir, name)] = name
      end
    end
  end

  return opt_plugins, start_plugins
end, 1)

--- @param plugins table<string,Pckr.Plugin>
--- @return table<string,string>
function M.find_extra_plugins(plugins)
  local opt_plugins, start_plugins = get_installed_plugins()

  local extra = {} --- @type table<string,string>

  for dplugins, is_start in pairs({
    [opt_plugins] = false,
    [start_plugins] = true,
  }) do
    for path, name in pairs(dplugins) do
      if not path_is_plugin(path, is_start, plugins) then
        extra[path] = name
      end
    end
  end

  return extra
end

--- @param plugin Pckr.Plugin
--- @param opt_plugins table<string,string> Plugins installed in config.opt_dir
--- @param start_plugins table<string,string> Plugins installed in config.start_dir
--- @return boolean
local function plugin_installed(plugin, opt_plugins, start_plugins)
  for path in pairs(plugin.start and start_plugins or opt_plugins) do
    if cmp_paths(path, plugin.install_path) then
      return true
    end
  end
  return false
end

--- @param plugins table<string,Pckr.Plugin>
--- @return table<string,string>
function M.find_missing_plugins(plugins)
  local opt_plugins, start_plugins = get_installed_plugins()

  local missing_plugins = {} --- @type table<string,string>

  for plugin_name, plugin in pairs(plugins) do
    if not plugin_installed(plugin, opt_plugins, start_plugins) then
      missing_plugins[plugin.install_path] = plugin_name
    end
  end

  return missing_plugins
end

return M
