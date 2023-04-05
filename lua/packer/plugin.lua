local util = require('packer.util')
local log = require('packer.log')
local config = require('packer.config')

--- @alias Loader fun(function)

--- @class UserSpec
--- @field [integer] string
--- @field branch     string
--- @field rev        string
--- @field tag        string
--- @field commit     string
--- @field start      boolean
--- @field cond       boolean|Loader|Loader[]
--- @field run        string|function|(string|function)[]
--- @field config_pre fun()
--- @field config     fun()
--- @field lock       boolean
--- @field requires   string|(string|UserSpec)[]

--- @class Plugin
--- @field branch       string
--- @field rev          string
--- @field tag          string
--- @field commit       string
--- @field install_path string
--- @field cond         boolean|Loader|Loader[]
--- @field run          (string|fun())[]
--- @field config_pre   fun()
--- @field config       fun()
--- @field requires     string[]
---
--- @field name         string
--- @field revs         {[1]: string, [2]: string}
--- @field required_by  string[]
---
--- @field type             PluginType
--- @field url              string
--- @field lock             boolean
--- @field breaking_commits string[]
---
--- Install as a 'start' plugin
--- @field start  boolean
--- @field loaded  boolean
---
--- Profiling
--- @field config_time       number
--- @field plugin_times      table<string,{[1]:number,[2]:number}>
--- @field plugin_load_time  number
--- @field plugin_exec_time  number
--- @field plugin_time       number
---
--- -- Built from a simple plugin spec (a string)
--- @field simple boolean
---
--- @field messages string[]
--- @field err? string[]

--- @alias PluginType
--- | 'git'
--- | 'local'
--- | 'unknown'

local M = {
  --- @type table<string,Plugin>
  plugins = {}
}

--- @param path string
--- @return string, PluginType
local function guess_plugin_type(path)
   if vim.fn.isdirectory(path) ~= 0 then
      return path, 'local'
   end

   if vim.startswith(path, 'git://') or
      vim.startswith(path, 'http') or
      path:match('@') then
      return path, 'git'
   end

   path = table.concat(vim.split(path, '\\', { plain = true }), '/')
   return config.git.default_url_format:format(path), 'git'
end

--- @param text string
--- @return string, string
local function get_plugin_name(text)
   local path = vim.fn.expand(text)
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

--- @param x string | UserSpec
--- @return UserSpec
local function normspec(x)
   return type(x) == "string" and { x } or x
end

--- @param x string | function | (string|function)[]
--- @return (string|function)[]
local function normrun(x)
   if type(x) == "function" or type(x) == "string" then
      return { x }
   end
   return x
end

--- The main logic for adding a plugin (and any dependencies) to the managed set
-- Can be invoked with (1) a single plugin spec as a string, (2) a single plugin spec table, or (3)
-- a list of plugin specs
--- @param spec0 string|UserSpec
--- @param required_by? Plugin
--- @return table<string,Plugin>
function M.process_spec(spec0, required_by)
   local spec = normspec(spec0)

   if #spec > 1 then
      local r = {}
      for _, s in ipairs(spec) do
         r = vim.tbl_extend('error', r, M.process_spec(s, required_by))
      end
      return r
   end

   local id = spec[1]
   spec[1] = nil

   if id == nil then
      log.warn('No plugin name provided!')
      log.debug('No plugin name provided for spec', spec)
      return {}
   end

   local name, path = get_plugin_name(id)

   if name == '' then
      log.fmt_warn('"%s" is an invalid plugin name!', id)
      return {}
   end

   local existing = M.plugins[name]
   local simple = type(spec0) == "string"

   if existing then
      if simple then
         log.debug('Ignoring simple plugin spec' .. name)
         return { [name] = existing }
      else
         if not existing.simple then
            log.fmt_warn('Plugin "%s" is specified more than once!', name)
            return { [name] = existing }
         end
      end

      log.debug('Overriding simple plugin spec: ' .. name)
   end

   local url, ptype = guess_plugin_type(path)

   local plugin = {
      name = name,
      branch = spec.branch,
      rev = spec.rev,
      tag = spec.tag,
      commit = spec.commit,
      start = spec.start,
      simple = simple,
      cond = spec.cond ~= true and spec.cond or nil,   -- must be function or 'false'
      run = normrun(spec.run),
      lock = spec.lock,
      url = remove_ending_git_url(url),
      type = ptype,
      config_pre = spec.config_pre,
      config = spec.config,
      revs = {},
   }

   if required_by then
      plugin.required_by = plugin.required_by or {}
      table.insert(plugin.required_by, required_by.name)
   end

   if existing and existing.required_by then
      plugin.required_by = plugin.required_by or {}
      vim.list_extend(plugin.required_by, existing.required_by)
   end

   M.plugins[name] = plugin

   plugin.install_path = util.join_paths(plugin.start and config.start_dir or config.opt_dir, name)

   if spec.requires then
      local sr = spec.requires
      local r = type(sr) == "string" and { sr } or sr

      plugin.requires = {}
      for _, s in ipairs(r) do
         vim.list_extend(plugin.requires, vim.tbl_keys(M.process_spec(s, plugin)))
      end
   end

   return { [name] = plugin }
end

return M
