local util = require('pckr.util')
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

--- Get installed plugins in `dir`.
--- @param dir string Directory to search
--- @return table<string,string> plugins
local function get_dir_plugins(dir)
  local plugins = {} --- @type table<string,string>

  for name, ty in vim.fs.dir(dir) do
    if ty ~= 'file' then
      local path = util.join_paths(dir, name)
      if uv.fs_stat(path) then
        plugins[path] = name
      end
    end
  end

  return plugins
end

--- @param plugins table<string,Pckr.Plugin>
--- @return table<string,string>
function M.find_extra_plugins(plugins)
  local opt_plugins = get_dir_plugins(config._opt_dir)
  local start_plugins = get_dir_plugins(config._start_dir)

  local extra = {} --- @type table<string,string>

  for is_start, dplugins in pairs({
    [false] = opt_plugins,
    [true] = start_plugins,
  }) do
    for path, name in pairs(dplugins) do
      if not path_is_plugin(path, is_start, plugins) then
        extra[path] = name
      end
    end
  end

  return extra
end

--- @param plugins table<string,Pckr.Plugin>
--- @return string[]
function M.find_missing_plugins(plugins)
  local missing_plugins = {} --- @type string[]

  for plugin_name, plugin in pairs(plugins) do
    if not plugin.installed then
      missing_plugins[#missing_plugins + 1] = plugin_name
    end
  end

  return missing_plugins
end

return M
