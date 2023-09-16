local util = require('pckr.util')

local join_paths = util.join_paths

--- @class Pckr.Config.Display
--- @field non_interactive boolean
--- @field prompt_border   string
--- @field working_sym     string
--- @field error_sym       string
--- @field done_sym        string
--- @field removed_sym     string
--- @field moved_sym       string
--- @field item_sym        string
--- @field header_sym      string
--- @field keybindings     table<string,(string|string[])>

--- @class Pckr.Config.Git
--- @field cmd                string
--- @field depth              integer
--- @field clone_timeout      integer
--- @field default_url_format string

--- @class Pckr.Config.Log
--- @field level Pckr.LogLevel

--- @class Pckr.Config.Lockfile
--- @field path string

--- @class (exact) Pckr.UserConfig
--- @field package_root? string
--- @field pack_dir?     string
--- @field max_jobs?     integer
--- @field start_dir?    string
--- @field opt_dir?      string
--- @field autoremove?   boolean
--- @field autoinstall?  boolean
--- @field display?      Pckr.Config.Display
--- @field git?          Pckr.Config.Git
--- @field log?          Pckr.Config.Log
--- @field lockfile?     Pckr.Config.Lockfile
--- @field native_packadd?     boolean
--- @field native_loadplugins? boolean Let pckr handle 'loadplugins'. Note: make
---                                   sure to populate rtp before calling pckr.

--- @class (exact) Pckr.Config : Pckr.UserConfig
--- @field package_root string
--- @field pack_dir     string
--- @field start_dir    string
--- @field opt_dir      string
--- @field autoremove   boolean
--- @field autoinstall  boolean
--- @field display      Pckr.Config.Display
--- @field git          Pckr.Config.Git
--- @field log          Pckr.Config.Log
--- @field lockfile     Pckr.Config.Lockfile
--- @field native_packadd     boolean
--- @field native_loadplugins boolean Let pckr handle 'loadplugins'. Note: make
---                                   sure to populate rtp before calling pckr.

--- @type Pckr.Config
local default_config = {
  package_root = join_paths(vim.fn.stdpath('data'), 'site', 'pack'),
  pack_dir = '',
  start_dir = '',
  opt_dir = '',
  max_jobs = nil,
  git = {
    cmd = 'git',
    depth = 1,
    clone_timeout = 60,
    default_url_format = 'https://github.com/%s.git',
  },
  display = {
    non_interactive = false,
    working_sym = '⟳',
    error_sym = '✗',
    done_sym = '✓',
    removed_sym = '-',
    moved_sym = '→',
    item_sym = '•',
    header_sym = '━',
    prompt_border = 'double',
    keybindings = {
      quit = 'q',
      toggle_info = { 'za', '<CR>' },
      diff = 'd',
      prompt_revert = 'r',
    },
  },
  log = { level = 'info' },
  lockfile = {
    path = util.join_paths(vim.fn.stdpath('config'), 'pckr', 'lockfile.lua'),
  },
  autoremove = false,
  autoinstall = true,
  native_packadd = false,
  native_loadplugins = false,
}

local config = vim.deepcopy(default_config)

--- @param _ table
--- @param user_config Pckr.Config
--- @return Pckr.Config
local function set(_, user_config)
  config = vim.tbl_deep_extend('force', config, user_config or {})
  config.package_root = vim.fn.fnamemodify(config.package_root, ':p')
  config.package_root = config.package_root:gsub(util.get_separator() .. '$', '', 1)
  config.pack_dir = join_paths(config.package_root, 'pckr')
  config.opt_dir = join_paths(config.pack_dir, 'opt')
  config.start_dir = join_paths(config.pack_dir, 'start')

  if #vim.api.nvim_list_uis() == 0 then
    config.display.non_interactive = true
  end

  return config
end

--- @type Pckr.Config
local M = setmetatable({}, {
  __index = function(_, k)
    return (config)[k]
  end,
  __call = set,
})

return M
