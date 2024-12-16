local async = require('pckr.async')

--- @class Pckr.actions
local M = {}

--- Install operation:
--- Installs missing plugins, then updates helptags
--- @param plugins? string[]
--- @param _opts table?
--- @param __cb? function
M.install = async.sync(2, function(plugins, _opts, __cb)
  require('pckr.sync').sync('install', plugins)
end)

--- Update operation:
--- Takes an optional list of plugin names as an argument. If no list is given,
--- operates on all managed plugins then updates installed plugins and updates
--- helptags.
--- @param plugins? string[] List of plugin names to update.
--- @param _opts table?
--- @param __cb? function
M.update = async.sync(2, function(plugins, _opts, __cb)
  require('pckr.sync').sync('update', plugins)
end)

--- Sync operation:
--- Takes an optional list of plugin names as an argument. If no list is given,
--- operates on all managed plugins. Installs missing plugins, then updates
--- installed plugins and updates helptags
--- @param plugins? string[]
--- @param _opts table?
--- @param __cb? function
M.sync = async.sync(2, function(plugins, _opts, __cb)
  require('pckr.sync').sync('sync', plugins)
end)

M.upgrade = async.sync(2, function(_, _opts, __cb)
  require('pckr.sync').sync('upgrade')
end)

--- @param _ any
--- @param _opts table?
--- @param __cb? function
M.status = async.sync(2, function(_, _opts, __cb)
  require('pckr.status').run()
end)

--- Clean operation:
--- Finds plugins present in the `pckr` package but not in the managed set
--- @param _ any
--- @param _opts table?
--- @param __cb? function
M.clean = async.sync(2, function(_, _opts, __cb)
  require('pckr.sync').clean()
end)

--- @param _ any
--- @param _opts table?
--- @param __cb? function
M.lock = async.sync(2, function(_, _opts, __cb)
  require('pckr.lockfile').lock()
end)

--- @param _ any
--- @param _opts table?
--- @param __cb? function
M.restore = async.sync(2, function(_, _opts, __cb)
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
