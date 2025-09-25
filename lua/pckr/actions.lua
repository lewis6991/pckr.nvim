local async = require('pckr.async')

--- @class Pckr.actions
local M = {}

--- Install operation:
--- Installs missing plugins, then updates helptags
--- @param plugins? string[]
--- @param _opts table?
M.install = async.sync(2, function(plugins, _opts)
  require('pckr.sync').sync('install', plugins)
end)

--- Update operation:
--- Takes an optional list of plugin names as an argument. If no list is given,
--- operates on all managed plugins then updates installed plugins and updates
--- helptags.
--- @param plugins? string[] List of plugin names to update.
--- @param _opts table?
M.update = async.sync(2, function(plugins, _opts)
  require('pckr.sync').sync('update', plugins)
end)

--- Sync operation:
--- Takes an optional list of plugin names as an argument. If no list is given,
--- operates on all managed plugins. Installs missing plugins, then updates
--- installed plugins and updates helptags
--- @param plugins? string[]
--- @param _opts table?
M.sync = async.sync(2, function(plugins, _opts)
  require('pckr.sync').sync('sync', plugins)
end)

M.upgrade = async.sync(2, function(_, _opts)
  require('pckr.sync').sync('upgrade')
end)

--- @param _ any
--- @param _opts table?
M.status = async.sync(2, function(_, _opts)
  require('pckr.status').run()
end)

--- Clean operation:
--- Finds plugins present in the `pckr` package but not in the managed set
--- @param _ any
--- @param _opts table?
M.clean = async.sync(2, function(_, _opts)
  require('pckr.sync').clean()
end)

--- Uninstall operation:
--- Remove specified plugins.
--- @param plugins? string[]
--- @param _opts table?
M.uninstall = async.sync(2, function(plugins, _opts)
  require('pckr.sync').clean(plugins or {})
end)

--- Uninstall operation:
--- Remove specified plugins.
--- @param plugins? string[]
--- @param _opts table?
M.reinstall = async.sync(2, function(plugins, _opts)
  require('pckr.sync').sync('reinstall', plugins)
end)

--- @param _ any
--- @param _opts table?
M.lock = async.sync(2, function(_, _opts)
  require('pckr.lockfile').lock()
end)

--- @param _ any
--- @param _opts table?
M.restore = async.sync(2, function(_, _opts)
  require('pckr.lockfile').restore()
end)

--- @param _ any
--- @param _opts table?
M.log = function(_, _opts)
  local messages = require('pckr.log').messages
  for _, m in ipairs(messages) do
    vim.api.nvim_echo({ m }, false, {})
  end
end

return M
