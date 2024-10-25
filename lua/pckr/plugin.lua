local util = require('pckr.util')
local log = require('pckr.log')
local config = require('pckr.config')

--- @alias Pckr.PluginLoader fun(function)

--- @class (exact) Pckr.UserSpec
--- @field [1]         string
--- @field branch?     string
--- @field rev?        string
--- @field tag?        string
--- @field commit?     string
--- @field start?      boolean
--- @field cond?       boolean|Pckr.PluginLoader|Pckr.PluginLoader[]
--- @field run?        fun()|string
--- @field config_pre? fun()|string
--- @field config?     fun()|string
--- @field lock?       boolean
--- @field requires?   string|Pckr.UserSpec|(string|Pckr.UserSpec)[]

--- @class (exact) Pckr.Plugin
--- @field branch?      string
--- @field rev?         string
--- @field tag?         string
--- @field commit?      string
--- @field install_path string
--- @field cond?         boolean|Pckr.PluginLoader|Pckr.PluginLoader[]
--- @field run?         fun()|string
--- @field config_pre?  fun()|string
--- @field config?      fun()|string
--- @field requires?    string[]
--- @field lock?        boolean
--- @field _dir?        string
---
--- @field name         string
--- @field revs         [string?, string?]
--- @field required_by? string[]
--- @field type              Pckr.PluginType
--- @field url               string
--- @field breaking_commits? string[]
---
--- Install as a 'start' plugin
--- @field start?     boolean
--- @field loaded?    boolean
--- @field _loaded_after_vim_enter?    boolean
--- @field installed? boolean
---
--- Profiling
--- @field files? table<string,{[1]:number,[2]:number}>
--- @field config_time?  number
--- @field load_time?  number Time spent loading plugin/ and after/plugin/
--- @field config_pre_time?  number
--- @field packadd_time?  number
--- @field total_time?   number
--- @field _profile? string
---
--- Built from a simple plugin spec (a string). Used for requires
--- @field simple boolean
---
--- @field messages? string
--- @field err? string

--- @alias Pckr.PluginType 'git' | 'local'

local M = {
  --- @type Pckr.Plugin[]
  plugins = {},

  --- @type table<string,Pckr.Plugin>
  plugins_by_name = {},
}

--- @param psuedo_path string
--- @return string, Pckr.PluginType
local function guess_plugin_type(psuedo_path)
  if
    vim.startswith(psuedo_path, 'git://')
    or vim.startswith(psuedo_path, 'http')
    or psuedo_path:match('@')
  then
    return psuedo_path, 'git'
  end

  if vim.fn.isdirectory(psuedo_path) ~= 0 then
    return psuedo_path, 'local'
  end

  psuedo_path = table.concat(vim.split(psuedo_path, '\\', { plain = true }), '/')
  return config.git.default_url_format:format(psuedo_path), 'git'
end

--- @param text string
--- @return string, string
local function get_plugin_name(text)
  local path = vim.fn.expand(text) --[[@as string]]
  local name_segments = vim.split(path, util.get_separator())
  local segment_idx = #name_segments
  local name = name_segments[segment_idx]
  while name == '' and segment_idx > 0 do
    name = name_segments[segment_idx]
    segment_idx = segment_idx - 1
  end
  return name, path
end

--- @param url string
--- @return string
local function remove_ending_git_url(url)
  return vim.endswith(url, '.git') and url:sub(1, -5) or url
end

--- @param x string|Pckr.UserSpec
--- @return boolean
local function is_simple(x)
  if type(x) == 'string' then
    return true
  end

  for k in
    pairs(x --[[@as table<any,any>]])
  do
    if type(k) ~= 'number' then
      return false
    end
  end

  return true
end

--- @param x string|Pckr.UserSpec
--- @return Pckr.UserSpec
local function normspec(x)
  if type(x) == 'string' then
    return { x }
  end
  return x
end

--- @param x string|Pckr.UserSpec|(string|Pckr.UserSpec)[]
--- @return boolean
local function spec_is_list(x)
  if type(x) == 'string' then
    return false
  end

  if #x > 1 then
    return true
  end

  if #x == 1 and type(x[1]) == 'string' and is_simple(x) then
    -- type(x) == Pckr.UserSpec
    return false
  end

  return true
end

--- @param spec0 string|Pckr.UserSpec
--- @param required_by? Pckr.Plugin
--- @return Pckr.Plugin?
local function process_spec_item(spec0, required_by)
  local spec = normspec(spec0)
  local id = spec[1]

  if not id then
    log.warn('No plugin name provided!')
    log.debug('No plugin name provided for spec', spec)
    return
  end

  local name, psuedo_path = get_plugin_name(id)

  if name == '' then
    log.fmt_warn('"%s" is an invalid plugin name!', id)
    return
  end

  local existing = M.plugins_by_name[name]
  local simple = is_simple(spec0)

  if existing then
    if simple then
      log.debug('Ignoring simple plugin spec' .. name)
      return existing
    else
      if not existing.simple then
        log.fmt_warn('Plugin "%s" is specified more than once!', name)
        return existing
      end
    end

    log.debug('Overriding simple plugin spec: ' .. name)
  end

  local url, plugin_type = guess_plugin_type(psuedo_path)

  local is_start = spec.start

  if plugin_type == 'local' and is_start then
    log.fmt_warn('Ignoring start=true with local plugin', name)
    is_start = false
  end

  local install_path_dir = is_start and config._start_dir or config._opt_dir
  local install_path = util.join_paths(install_path_dir, name)

  --- @type Pckr.Plugin
  local plugin = {
    name = name,
    branch = spec.branch,
    rev = spec.rev,
    tag = spec.tag,
    commit = spec.commit,
    start = is_start,
    simple = simple,
    cond = spec.cond ~= true and spec.cond or nil, -- must be function or 'false'
    run = spec.run,
    lock = spec.lock,
    url = remove_ending_git_url(url),
    install_path = install_path,
    installed = vim.fn.isdirectory(install_path) ~= 0,
    type = plugin_type,
    config_pre = spec.config_pre,
    config = spec.config,
    revs = {},
    required_by = required_by and { required_by.name } or nil,
    _dir = plugin_type == 'local' and psuedo_path or nil,
  }

  if existing and existing.required_by then
    plugin.required_by = plugin.required_by or {}
    vim.list_extend(plugin.required_by, existing.required_by)
  end

  M.plugins_by_name[name] = plugin
  M.plugins[#M.plugins + 1] = plugin

  local spec_requires = spec.requires
  if spec_requires then
    plugin.requires = {}
    for _, dep in ipairs(M.process_spec(spec_requires, plugin)) do
      plugin.requires[#plugin.requires + 1] = dep.name
    end
  end

  return plugin
end

--- The main logic for adding a plugin (and any dependencies) to the managed set
--- @param spec string|Pckr.UserSpec|(string|Pckr.UserSpec)[]
--- @param required_by? Pckr.Plugin
--- @return Pckr.Plugin[]
function M.process_spec(spec, required_by)
  local ret = {} --- @type Pckr.Plugin[]

  if spec_is_list(spec) then
    --- @cast spec (string|Pckr.UserSpec)[]
    for _, x in ipairs(spec) do
      ret[#ret + 1] = process_spec_item(x, required_by)
    end
  else
    --- @cast spec string|Pckr.UserSpec
    ret[#ret + 1] = process_spec_item(spec, required_by)
  end

  return ret
end

return M
