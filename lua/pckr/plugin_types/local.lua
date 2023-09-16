local log = require('pckr.log')

--- @class Pckr.PluginHandler
local M = {}

M.installer = function(_plugin, _disp)
end

M.updater = function(_plugin, _disp)
  -- Do update local plugins
end

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
