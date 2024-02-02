--- @class Pckr.PluginHandler
--- @field installer   fun(plugin: Pckr.Plugin, display: Pckr.Display): string?
--- @field updater     fun(plugin: Pckr.Plugin, display: Pckr.Display): string?
--- @field revert_last fun(plugin: Pckr.Plugin): string?
--- @field revert_to   fun(plugin: Pckr.Plugin, commit: string): string?
--- @field diff        fun(plugin: Pckr.Plugin, commit: string, callback: function)
--- @field get_rev     fun(plugin: Pckr.Plugin): string?

--- @type table<string,Pckr.PluginHandler>
local plugin_types = {}

return setmetatable(plugin_types, {
  __index = function(_, k)
    if k == 'git' then
      return require('pckr.plugin_types.git')
    elseif k == 'local' then
      return require('pckr.plugin_types.local')
    end
  end,
})
