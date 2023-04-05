local log = require('packer.log')
local util = require('packer.util')

--- @type fun()[]
local plugin_configs = {}

--- @param plugin Plugin
local function apply_config(plugin, pre)
  xpcall(function()
    --- @type fun()|string, string
    local c, sfx
    if pre then
      c, sfx = plugin.config_pre, '_pre'
    else
      c, sfx = plugin.config, ''
    end

    if c then
      log.fmt_debug('Running config%s for %s', sfx, plugin.name)
      local c0 --- @type fun()
      if type(c) == "function" then
        c0 = c
      else
        c0 = assert(loadstring(c, plugin.name .. '.config' .. sfx))
      end
      local delta = util.measure(c0)
      log.fmt_debug('config%s for %s took %fms', sfx, plugin.name, delta * 1000)
      plugin.config_time = delta * 1000
    end
  end, function(x)
      log.fmt_error('Error running config for %s: %s', plugin.name, x)
    end)
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
    if ftype == "directory" then
      walk(child, fn)
    end
    fn(child, name, ftype)
  end)
end

local function source_after(install_path)
  walk(util.join_paths(install_path, 'after', 'plugin'), function(path, _, t)
    local ext = path:sub(-4)
    if t == "file" and (ext == ".lua" or ext == ".vim") then
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

--- @param plugins Plugin[]
local function load_plugins(plugins)
  for _, plugin in ipairs(plugins) do
    M.load_plugin(plugin)
  end
end

--- @param plugin Plugin
function M.load_plugin(plugin)
  if plugin.loaded then
    log.fmt_debug('Already loaded %s', plugin.name)
    return
  end

  if vim.fn.isdirectory(plugin.install_path) == 0 then
    log.fmt_error('%s is not installed', plugin.name)
    return
  end

  log.fmt_debug('Running loader for %s', plugin.name)

  apply_config(plugin, true) -- spec.config_pre()

  -- Set the plugin as loaded before config is run in case something in the
  -- config tries to load this same plugin again
  plugin.loaded = true

  if plugin.requires then
    log.fmt_debug('Loading dependencies of %s', plugin.name)
    local all_plugins = require('packer.plugin').plugins
    local rplugins = vim.tbl_map(function(n)
      return all_plugins[n]
    end, plugin.requires)
    load_plugins(rplugins)
  end

  log.fmt_debug('Loading %s', plugin.name)
  if vim.v.vim_did_enter == 0 then
    if not plugin.start then
      vim.cmd.packadd({ plugin.name, bang = true })
    end

    plugin_configs[#plugin_configs + 1] = function()
      apply_config(plugin, false) -- spec.config()
    end
  else
    if not plugin.start then
      vim.cmd.packadd(plugin.name)
      source_after(plugin.install_path)
    end

    apply_config(plugin, false) -- spec.config()
  end
end

--- @param plugins table<string,Plugin>
function M.setup(plugins)
  local Handlers = require('packer.handlers')

  for _, plugin in pairs(plugins) do
    if not plugin.lazy then
      M.load_plugin(plugin)
    end
  end

  for _, cond in ipairs(Handlers.types) do
    Handlers[cond](plugins, load_plugins)
  end
end

function M.run_configs()
  for _, cfg in ipairs(plugin_configs) do
    cfg()
  end
  plugin_configs = {}
end

return M
