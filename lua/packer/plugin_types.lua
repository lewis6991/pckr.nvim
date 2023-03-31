--- @class PluginHandler
--- @field installer   fun(plugin: Plugin, display: Display): string[]?
--- @field updater     fun(plugin: Plugin, display: Display, opts: table): string[]?
--- @field revert_last fun(plugin: Plugin): string[]?
--- @field revert_to   fun(plugin: Plugin, commit: string): string[]?
--- @field diff        fun(plugin: Plugin, commit: string, callback: function): string[]?
--- @field get_rev     fun(plugin: Plugin): string, string

--- @type table<string,PluginHandler>
local plugin_types = {}

return setmetatable(plugin_types, {
  __index = function(_, k)
    if k == 'git' then
      return require('packer.plugin_types.git')
    elseif k == 'local' then
      return require('packer.plugin_types.local')
    end
  end,
})
