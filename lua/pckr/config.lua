local util = require('pckr.util')

local joinpath = vim.fs.joinpath

--- @class (exact) Pckr.Config.Git
--- @field default_url_format string
---
--- @class (exact) Pckr.UserConfig.Git
--- @field default_url_format? string

--- @class (exact) Pckr.Config.Log
--- @field level Pckr.LogLevel
---
--- @class (exact) Pckr.UserConfig.Log
--- @field level? Pckr.LogLevel

--- @class (exact) Pckr.Config.Lockfile
--- @field path string

--- @class (exact) Pckr.UserConfig.Lockfile
--- @field path? string

--- @class (exact) Pckr.UserConfig
--- @field pack_dir?     string
--- @field package_root? string deprecated, use pack_dir
---
--- @field max_jobs?     integer
--- @field autoremove?   boolean
--- @field autoinstall?  boolean
--- @field git?          Pckr.UserConfig.Git
--- @field log?          Pckr.UserConfig.Log
--- @field lockfile?     Pckr.UserConfig.Lockfile

--- @class (exact) Pckr.Config : Pckr.UserConfig
--- @field pack_dir     string
--- @field autoremove   boolean
--- @field autoinstall  boolean
--- @field git          Pckr.Config.Git
--- @field log          Pckr.Config.Log
--- @field lockfile     Pckr.Config.Lockfile
--- @field _start_dir   string
--- @field _opt_dir     string
--- @field _native_packadd boolean
--- Let pckr handle 'loadplugins'. Note: make sure to populate rtp before
--- calling pckr.
--- @field _native_loadplugins boolean

--- @type Pckr.Config
local config = {
  pack_dir = joinpath(vim.fn.stdpath('data') --[[@as string]], 'site'),
  _pack_dir = '',
  _start_dir = '',
  _opt_dir = '',
  max_jobs = nil,
  git = {
    cmd = 'git',
    default_url_format = 'https://github.com/%s.git',
  },
  log = { level = 'info' },
  lockfile = {
    path = joinpath(vim.fn.stdpath('config') --[[@as string]], 'pckr', 'lockfile.lua'),
  },
  autoremove = false,
  autoinstall = true,
  _native_packadd = false,
  _native_loadplugins = false,
}

--- @param _ table
--- @param user_config Pckr.UserConfig
--- @return Pckr.Config
local function set(_, user_config)
  if user_config then
    config = vim.tbl_deep_extend('force', config, user_config)
    config.pack_dir = user_config.pack_dir or user_config.package_root or config.pack_dir
  end

  config.pack_dir = vim.fn.fnamemodify(config.pack_dir, ':p')
  config.pack_dir = config.pack_dir:gsub(util.get_separator() .. '$', '', 1)

  local pack_dir = joinpath(config.pack_dir, 'pack', 'pckr')
  config._opt_dir = joinpath(pack_dir, 'opt')
  config._start_dir = joinpath(pack_dir, 'start')

  return config
end

local M = setmetatable({}, {
  __index = function(_, k)
    return config[k]
  end,
  __call = set,
}) --[[@as Pckr.Config]]

return M
