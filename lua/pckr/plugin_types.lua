--- @class Pckr.PluginHandler
--- @field installer   fun(plugin: Pckr.Plugin, display: Pckr.Display): string?
--- @field updater     fun(plugin: Pckr.Plugin, display: Pckr.Display): string?
--- @field revert_last fun(plugin: Pckr.Plugin): string?
--- @field revert_to   fun(plugin: Pckr.Plugin, commit: string): string?
--- @field diff        fun(plugin: Pckr.Plugin, commit: string, callback: function)
--- @field get_rev     fun(plugin: Pckr.Plugin): string?

--- @type table<string,Pckr.PluginHandler>
local M = {}

return setmetatable(M, {
  --- @param t table<string,Pckr.PluginHandler>
  --- @param k string
  --- @return Pckr.PluginHandler?
  __index = function(t, k)
    t[k] = require('pckr.plugin_types.'..k)
    return t[k]
  end,
})
