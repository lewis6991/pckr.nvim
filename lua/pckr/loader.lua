local uv = vim.uv or vim.loop

local log = require('pckr.log')
local fmt_debug = log.fmt_debug

local util = require('pckr.util')
local measure = util.measure

local config = require('pckr.config')

local orig_loadfile = loadfile

local M = {
  --- @type table<string,{[1]:number,[2]:number}>
  path_times = {},
}

--- @param plugin Pckr.Plugin
--- @param field 'config'|'config_pre'
local function apply_config(plugin, field)
  local c = plugin[field] --- @type string|fun()?
  if not c then
    return
  end

  fmt_debug('Running %s for %s', field, plugin.name)

  local time_field = field == 'config' and 'config_time' or 'config_pre_time'

  --- @diagnostic disable-next-line:no-unknown
  plugin[time_field] = measure(function()
    local c_fun --- @type fun()
    if type(c) == 'string' then
      c_fun = function()
        require(c)
      end
    else
      c_fun = c
    end
    xpcall(c_fun, function(err)
      log.fmt_error('Error running %s for %s:\n\t%s', field, plugin.name, err)
    end)
  end)
end

_G.loadfile = function(path)
  local start1 = uv.hrtime()
  local chunk, err = orig_loadfile(path)
  local load_time = (uv.hrtime() - start1) / 1e6
  if not chunk then
    return nil, err
  end

  return function(...)
    local start2 = uv.hrtime()
    local r = { chunk(...) }
    local exec_time = (uv.hrtime() - start2) / 1e6
    M.path_times[path] = { load_time, exec_time }
    return unpack(r, 1, table.maxn(r))
  end
end

--- @param path string
--- @param fn fun(_: string, _: string, _: string): boolean?
local function walk(path, fn)
  local handle = uv.fs_scandir(path)
  while handle do
    local name, t = uv.fs_scandir_next(handle)
    if not name or not t then
      break
    end
    local child = util.join_paths(path, name)
    if t == 'directory' then
      M.walk(child, fn)
    end
    fn(child, name, t)
  end
end

--- @param ... string
local function source_runtime(...)
  local dir = util.join_paths(...)

  ---@type string[]?, string[]?
  local vim_files, lua_files

  measure('walk', function()
    walk(dir, function(path, name, t)
      if t == 'file' or t == 'link' then
        local ext = name:sub(-3)
        name = name:sub(1, -5)
        if ext == 'lua' then
          lua_files = lua_files or {}
          lua_files[#lua_files + 1] = path
        elseif ext == 'vim' then
          vim_files = vim_files or {}
          vim_files[#vim_files + 1] = path
        end
      end
    end)
  end)

  if vim_files then
    for _, path in ipairs(vim_files) do
      M.path_times[path] = { measure(function()
        vim.cmd.source(path)
      end), 0 }
    end
  end

  if lua_files then
    for _, path in ipairs(lua_files) do
      loadfile(path)()
    end
  end
end

--- This does the same as runtime.c:add_pack_dir_to_rtp()
--- - find first after
--- - insert `path` right before first after or at the end
--- - insert after dir right before first after or at the end
--- @param path string
local function add_to_rtp(path)
  local idx_dir --- @type integer?

  --- @type string[]
  --- @diagnostic disable-next-line:undefined-field
  local rtp = vim.opt.runtimepath:get()

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
  if uv.fs_stat(after) then
    table.insert(rtp, idx_dir + 1, after)
  end

  vim.opt.runtimepath = rtp
end

--- Optimized version of :packadd that doesn't (double) scan 'packpath' since
--- the full paths are already known.
---
--- Implements nvim/runtime.c:load_pack_plugin()
---
--- Make sure plugin is added to 'runtimepath' first.
--- @param plugin Pckr.Plugin
--- @param bang boolean
local function packadd(plugin, bang)
  if config._native_packadd then
    vim.cmd.packadd({ plugin.name, bang = bang })
    return
  end

  if vim.v.vim_did_enter == 0 and bang then
    -- Do not source. We've already added to rtp, so no need to do anything.
    return
  end

  local path = plugin.install_path

  source_runtime(path, 'plugin')

  if (vim.g.did_load_filetypes or 0) > 0 then
    vim.cmd.augroup('filetypedetect')
    source_runtime(path, 'ftdetect')
    vim.cmd.augroup('END')
  end

  if vim.v.vim_did_enter == 1 then
    source_runtime(path, 'after/plugin')
  end
end

--- @param plugin Pckr.Plugin
function M.load_plugin(plugin)
  local plugin_name = plugin.name

  if plugin.loaded then
    fmt_debug('Already loaded %s', plugin_name)
    return
  elseif not plugin.installed then
    log.fmt_warn('%s is not installed', plugin_name)
    return
  end

  fmt_debug('Running loader for %s', plugin_name)

  apply_config(plugin, 'config_pre')

  -- Set the plugin as loaded before config is run in case something in the
  -- config tries to load this same plugin again
  plugin.loaded = true
  plugin._loaded_after_vim_enter = vim.v.vim_did_enter == 1

  fmt_debug('Loading %s', plugin_name)
  measure('rtp', function()
    add_to_rtp(plugin.install_path)
  end)

  if plugin.requires then
    fmt_debug('Loading dependencies of %s', plugin_name)
    for _, name in ipairs(plugin.requires) do
      local all_plugins = require('pckr.plugin').plugins_by_name
      M.load_plugin(all_plugins[name])
    end
  end

  fmt_debug('Loading %s', plugin_name)
  measure('packadd', function()
    packadd(plugin, true)
  end)

  apply_config(plugin, 'config')
end

--- @generic T
--- @param x T|T[]
--- @return T[]
local function ensurelist(x)
  return type(x) == 'table' and x or { x }
end

-- A custom implementation of vim.go.loadplugins
local function do_loadplugins()
  --- @type string[]
  --- @diagnostic disable-next-line:undefined-field
  local rtp = vim.opt.runtimepath:get()

  -- Load plugins from rtp, excluding after
  for _, path in ipairs(rtp) do
    if not path:find('after/?$') then
      source_runtime(path, 'plugin')
    end
  end

  for _, path in ipairs(rtp) do
    if path:find('after/?$') then
      source_runtime(path, 'plugin')
    end
  end
end

function M.setup()
  log.debug('LOADING PLUGINS')

  measure('load', function()
    local plugins = require('pckr.plugin').plugins
    -- Load pckr plugins
    for _, plugin in pairs(plugins) do
      if not plugin.cond then
        -- Deps are loaded in load_plugin()
        if not plugin._dep_only then
          M.load_plugin(plugin)
        end
      else
        for _, cond in ipairs(ensurelist(plugin.cond)) do
          cond(function()
            measure('load_deferred', function()
              M.load_plugin(plugin)
            end)
          end)
        end
      end
    end
  end)

  if not config._native_loadplugins then
    measure('loadplugins', do_loadplugins)
  end

  measure('rtp', function()
    -- Normalize runtimepath. This will remove empty directories and expand
    -- opt/start
    vim.opt.runtimepath = vim.api.nvim_get_runtime_file('', true)
  end)
end

return M
