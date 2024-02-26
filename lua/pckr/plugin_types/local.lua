local a = require('pckr.async')
local log = require('pckr.log')
local util = require('pckr.util')

local uv = vim.loop

--- @class Pckr.PluginHandler.Local: Pckr.PluginHandler
local M = {}

--- @param plugin Pckr.Plugin
--- @param _disp Pckr.Display
M.installer = function(plugin, _disp)
  vim.loop.fs_symlink(plugin._dir, plugin.install_path)
end

--- @param plugin Pckr.Plugin
--- @param disp Pckr.Display
--- @return string?
M.updater = a.sync(function(plugin, disp)
  local gitdir = util.join_paths(plugin.install_path, '.git')
  if uv.fs_stat(gitdir) then
    return require('pckr.plugin_types.git').updater(plugin, disp, true)
  end
  -- Nothing to do
end)

M.revert_to = function(_, _)
  log.warn("Can't revert a local plugin!")
end

M.revert_last = function(_)
  log.warn("Can't revert a local plugin!")
end

M.diff = function(_, _, _)
  log.warn("Can't diff a local plugin!")
end

return M
