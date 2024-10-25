local async = require('pckr.async').sync

local M = {}

--- Install operation:
--- Installs missing plugins, then updates helptags
--- @param plugins? string[]
--- @param _opts table?
--- @param __cb? fun()
M.install = async(function(plugins, _opts, __cb)
  require('pckr.sync').sync('install', plugins)
end, 2)

--- Update operation:
--- Takes an optional list of plugin names as an argument. If no list is given,
--- operates on all managed plugins then updates installed plugins and updates
--- helptags.
--- @param plugins? string[] List of plugin names to update.
--- @param _opts table?
M.update = async(function(plugins, _opts)
  require('pckr.sync').sync('update', plugins)
end, 2)

--- Sync operation:
--- Takes an optional list of plugin names as an argument. If no list is given,
--- operates on all managed plugins. Installs missing plugins, then updates
--- installed plugins and updates helptags
--- @param plugins? string[]
--- @param _opts table?
M.sync = async(function(plugins, _opts)
  require('pckr.sync').sync('sync', plugins)
end, 2)

M.upgrade = async(function(_, _opts)
  require('pckr.sync').sync('upgrade')
end, 2)

--- @param _ any
--- @param _opts table?
M.status = async(function(_, _opts)
  require('pckr.status').run()
end, 2)

--- Clean operation:
--- Finds plugins present in the `pckr` package but not in the managed set
--- @param _ any
--- @param _opts table?
M.clean = async(function(_, _opts)
  require('pckr.sync').clean()
end, 2)

--- @param _ any
--- @param _opts table?
M.lock = async(function(_, _opts)
  require('pckr.lockfile').lock()
end, 2)

--- @param _ any
--- @param _opts table?
M.restore = async(function(_, _opts)
  require('pckr.lockfile').restore()
end, 2)

--- @param _ any
--- @param _opts table?
M.log = function(_, _opts)
  local messages = require('pckr.log').messages
  for _, m in ipairs(messages) do
    vim.api.nvim_echo({ m }, false, {})
  end
end

return M
