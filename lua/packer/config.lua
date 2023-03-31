local util = require('packer.util')

local join_paths = util.join_paths

--- @class Display
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

--- @class Git
--- @field cmd                string
--- @field depth              integer
--- @field clone_timeout      integer
--- @field default_url_format string

--- @alias LogLevel
--- | 'trace'
--- | 'debug'
--- | 'info'
--- | 'warn'
--- | 'error'
--- | 'fatal'

--- @class Log
--- @field level LogLevel

--- @class Lockfile
--- @field path string

--- @class Config
--- @field package_root string
--- @field pack_dir     string
--- @field max_jobs     integer?
--- @field start_dir    string
--- @field opt_dir      string
--- @field auto_clean   boolean
--- @field autoremove   boolean
--- @field display      Display
--- @field git          Git
--- @field log          Log
--- @field lockfile     Lockfile

--- @type Config
local default_config = {
   package_root = join_paths(vim.fn.stdpath('data'), 'site', 'pack'),
   max_jobs = nil,
   auto_clean = true,
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
      path = util.join_paths(vim.fn.stdpath('config'), 'packer', 'lockfile.lua'),
   },
   autoremove = false,
}

local config = vim.deepcopy(default_config)

--- @param user_config Config
--- @return Config
local function set(_, user_config)
   config = vim.tbl_deep_extend('force', config, user_config or {})
   config.package_root = vim.fn.fnamemodify(config.package_root, ':p')
   config.package_root = config.package_root:gsub(util.get_separator() .. '$', '', 1)
   config.pack_dir = join_paths(config.package_root, 'packer')
   config.opt_dir = join_paths(config.pack_dir, 'opt')
   config.start_dir = join_paths(config.pack_dir, 'start')

   if #vim.api.nvim_list_uis() == 0 then
      config.display.non_interactive = true
   end

   return config
end

--- @type Config
local M = {}

setmetatable(M, {
   __index = function(_, k)
      return (config)[k]
   end,
   __call = set,
})

return M
