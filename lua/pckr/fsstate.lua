local a = require('pckr.async')
local util = require('pckr.util')
local log = require('pckr.log')
local config = require('pckr.config')

local fn = vim.fn
local uv = vim.loop

--- @class FSState
--- @field opt     table<string,string>
--- @field start   table<string,string>
--- @field missing table<string,string>
--- @field dirty   table<string,string>
--- @field extra   table<string,string>

local M = {}

--- @param dir string
--- @return 'git' | 'local' | 'unknown'
local function guess_dir_type(dir)
  local globdir = fn.glob(dir)
  --- @diagnostic disable-next-line:param-type-mismatch
  local dir_type = (uv.fs_lstat(globdir) or { type = 'noexist' }).type

  if dir_type == 'link' then
    return 'local'
  end

  if uv.fs_stat(globdir .. '/.git') then
    return 'git'
  end

  return 'unknown'
end

--- @return table<string,string>
--- @return table<string,string>
local function get_installed_plugins()
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
end

local function toboolean(x)
  return x and true
end

--- @param plugins table<string,Plugin>
--- @param opt_plugins table<string,string> Plugins installed in config.opt_dir
--- @param start_plugins table<string,string> Plugins installed in config.start_dir
--- @return table<string,string>
local function find_extra_plugins(plugins, opt_plugins, start_plugins)
  local extra = {} --- @type table<string,string>

  for cond, p in pairs({
    [true] = { plugins = opt_plugins, dir = config.opt_dir },
    [false] = { plugins = start_plugins, dir = config.start_dir },
  }) do
    for _, name in pairs(p.plugins) do
      if not plugins[name] or cond == toboolean(plugins[name].start) then
        extra[util.join_paths(p.dir, name)] = name
      end
    end
  end

  return extra
end

--- @param plugins table<string,Plugin>
--- @param opt_plugins table<string,string> Plugins installed in config.opt_dir
--- @param start_plugins table<string,string> Plugins installed in config.start_dir
--- @return table<string,string>
--- @return table<string,string>
local find_dirty_plugins = a.sync(function(plugins, opt_plugins, start_plugins)
  local dirty_plugins = {} --- @type table<string,string>
  local missing_plugins = {} --- @type table<string,string>

  for plugin_name, plugin in pairs(plugins) do
    local plugin_installed = false
    for _, name in pairs(plugin.start and start_plugins or opt_plugins) do
      if name == plugin_name then
        plugin_installed = true
        break
      end
    end

    if not plugin_installed then
      missing_plugins[plugin.install_path] = plugin_name
    else
      a.main()
      local guessed_type = guess_dir_type(plugin.install_path)
      if plugin.type ~= guessed_type then
        dirty_plugins[plugin.install_path] = plugin_name
      elseif guessed_type == 'git' then
        local remote = require('pckr.plugin_types.git').remote_url(plugin)
        if remote then
          -- Form a Github-style user/repo string
          local parts = vim.split(remote, '[:/]')
          local repo_name = parts[#parts - 1] .. '/' .. parts[#parts]
          repo_name = repo_name:gsub('%.git', '')

          -- Also need to test for "full URL" plugin names, but normalized to get rid of the
          -- protocol
          local normalized_remote = remote:gsub('https://', ''):gsub('ssh://git@', '')
          local normalized_plugin_url = plugin.url:gsub('https://', ''):gsub('ssh://git@', ''):gsub('\\', '/')
          if (normalized_remote ~= normalized_plugin_url) and (repo_name ~= normalized_plugin_url) then
            dirty_plugins[plugin.install_path] = plugin_name
          end
        end
      end
    end
  end

  return dirty_plugins, missing_plugins
end, 3)

--- @param plugins table<string,Plugin>
--- @return FSState
M.get_fs_state = a.sync(function(plugins)
  log.debug('Updating FS state')
  local opt, start = get_installed_plugins()
  local dirty, missing = find_dirty_plugins(plugins, opt, start)
  return {
    opt = opt,
    start = start,
    missing = missing,
    dirty = dirty,
    extra = find_extra_plugins(plugins, opt, start),
  }
end, 1)

return M
