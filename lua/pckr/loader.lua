local log = require('pckr.log')
local util = require('pckr.util')
local config = require('pckr.config')

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

local function source_runtime(...)
  local dir = util.join_paths(...)
  ---@type string[], string[]
  local vim_files, lua_files = {}, {}
  util.walk(dir, function(path, name, t)
    local ext = name:sub(-3)
    name = name:sub(1, -5)
    if (t == "file" or t == "link") then
      if ext == "lua" then
        lua_files[#lua_files + 1] = path
      elseif ext == "vim" then
        vim_files[#vim_files + 1] = path
      end
    end
  end)
  for _, path in ipairs(vim_files) do
    vim.cmd.source(path)
  end
  for _, path in ipairs(lua_files) do
    vim.cmd.source(path)
  end
end

--- This does the same as runtime.c:add_pack_dir_to_rtp()
--- - find first after
--- - insert `path` right before first after or at the end
--- - insert after dir right before first after or at the end
--- @param path string
local function add_to_rtp(path)
  local rtp = vim.api.nvim_get_runtime_file('', true)
  local idx_dir --- @type integer?

  for i, p in ipairs(rtp) do
    if util.is_windows then
      p = vim.fs.normalize(p)
    end
    if vim.endswith(p, '/after') then
      idx_dir = i
      break
    end
  end

  idx_dir = idx_dir or #rtp + 1

  table.insert(rtp, idx_dir, path)

  local after = path .. '/after'
  if vim.loop.fs_stat(after) then
    table.insert(rtp, idx_dir + 1, after)
  end

  vim.opt.rtp = rtp
end

--- Optimized version of :packadd that doesn't (double) scan 'packpath' since
--- the full paths are already known.
---
--- Implements nvim/runtime.c:load_pack_plugin()
---
--- Make sure plugin is added to 'runtimepath' first.
---@param plugin Pckr.Plugin
---@param force boolean
local function packadd(plugin, force)
  if config.native_packadd then
    vim.cmd.packadd({ plugin.name, bang = force })
    return
  end

  if vim.v.vim_did_enter ~= 1 and force then
    -- Do not sourcv
    return
  end

  local path = plugin.install_path

  source_runtime(path, "plugin")

  if (vim.g.did_load_filetypes or 0) > 0 then
    vim.cmd.augroup('filetypedetect')
    source_runtime(path, 'ftdetect')
    vim.cmd.augroup("END")
  end

  if vim.v.vim_did_enter == 1 then
    source_runtime(path, "after/plugin")
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

  log.fmt_debug('Loading %s', plugin.name)
  add_to_rtp(plugin.install_path)

  if plugin.requires then
    log.fmt_debug('Loading dependencies of %s', plugin.name)
    local all_plugins = require('pckr.plugin').plugins

    for _, name in ipairs(plugin.requires) do
      M.load_plugin(all_plugins[name])
    end
  end

  log.fmt_debug('Loading %s', plugin.name)
  packadd(plugin, config.native_loadplugins)
  apply_config(plugin, 'config')
end

--- @generic T
--- @param x T|T[]
--- @return T[]
local function ensurelist(x)
  return type(x) == 'table' and x or { x }
end

--- @return string[]
local function get_rtp()
  --- @diagnostic disable-next-line:undefined-field
  return vim.opt.rtp:get()
end

local function do_loadplugins()
  -- Load plugins from the original rtp, excluding after
  for _, path in ipairs(get_rtp()) do
    if not path:find('after/?$') then
      source_runtime(path, "plugin")
    end
  end

  for _, path in ipairs(get_rtp()) do
    if path:find('after/?$') then
      source_runtime(path, "plugin")
    end
  end
end

local function load_plugins()
  local plugins = require'pckr.plugin'.plugins

  -- Load pckr plugins
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

function M.setup()
  log.debug('LOADING PLUGINS')

  load_plugins()

  if not config.native_loadplugins then
    do_loadplugins()
  end
end

return M
