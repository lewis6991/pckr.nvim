local a = require('pckr.async')
local log = require('pckr.log')

--- @class Pckr.PluginHandler.Local: Pckr.PluginHandler
local M = {}

M.installer = function(_plugin, _disp) end

--- @param plugin Pckr.Plugin
--- @param disp Pckr.Display
--- @return string?
M.updater = a.sync(function(plugin, disp)
  local gitdir = vim.fs.joinpath(plugin.install_path, '.git')
  if vim.uv.fs_stat(gitdir) then
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
