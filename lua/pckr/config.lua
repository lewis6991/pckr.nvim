local util = require('pckr.util')

local join_paths = util.join_paths

--- @class (exact) Pckr.Config.Display
--- @field non_interactive? boolean
--- @field prompt_border?   string
--- @field working_sym?     string
--- @field error_sym?       string
--- @field done_sym?        string
--- @field removed_sym?     string
--- @field moved_sym?       string
--- @field item_sym?        string
--- @field header_sym?      string
--- @field keybindings?     table<string,(string|string[])>

--- @class (exact) Pckr.Config.Git
--- @field cmd?                string
--- @field clone_timeout?      integer
--- @field default_url_format? string

--- @class (exact) Pckr.Config.Log
--- @field level Pckr.LogLevel

--- @class (exact) Pckr.Config.Lockfile
--- @field path string

--- @class (exact) Pckr.UserConfig
--- @field package_root? string
--- @field max_jobs?     integer
--- @field autoremove?   boolean
--- @field autoinstall?  boolean
--- @field display?      Pckr.Config.Display
--- @field git?          Pckr.Config.Git
--- @field log?          Pckr.Config.Log
--- @field lockfile?     Pckr.Config.Lockfile

--- @class (exact) Pckr.Config : Pckr.UserConfig
--- @field package_root string
--- @field autoremove   boolean
--- @field autoinstall  boolean
--- @field display      Pckr.Config.Display
--- @field git          Pckr.Config.Git
--- @field log          Pckr.Config.Log
--- @field lockfile     Pckr.Config.Lockfile
--- @field _start_dir   string
--- @field _opt_dir     string
--- @field _native_packadd boolean

--- @type Pckr.Config
local config = {
  package_root = join_paths(vim.fn.stdpath('data') --[[@as string]], 'site', 'pack'),
  _pack_dir = '',
  _start_dir = '',
  _opt_dir = '',
  max_jobs = nil,
  git = {
    cmd = 'git',
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
    path = join_paths(vim.fn.stdpath('config') --[[@as string]], 'pckr', 'lockfile.lua'),
  },
  autoremove = false,
  autoinstall = true,
  _native_packadd = false
}

--- @param _ table
--- @param user_config Pckr.UserConfig
--- @return Pckr.Config
local function set(_, user_config)
  if user_config then
    config = vim.tbl_deep_extend('force', config, user_config)
  end

  config.package_root = vim.fn.fnamemodify(config.package_root, ':p')
  config.package_root = config.package_root:gsub(util.get_separator() .. '$', '', 1)

  local pack_dir = join_paths(config.package_root, 'pckr')
  config._opt_dir = join_paths(pack_dir, 'opt')
  config._start_dir = join_paths(pack_dir, 'start')

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
