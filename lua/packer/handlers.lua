local M = {}

---@enum HandlerType
M.types = {
  'keys',
  'event',
  'ft',
  'cmd',
  'cond',
}

--- @alias HandlerLoader fun(plugins: Plugin[])))
--- @alias HandlerFun fun(plugins: table<string,Plugin>, HandlerLoader)

return setmetatable(M, {
  --- @param cond HandlerType
  --- @param t table<string,HandlerFun>
  --- @return HandlerFun
  __index = function(t, cond)
    if cond == 'keys' then
      t[cond] = require('packer.handlers.keys')
    elseif cond == 'event' then
      t[cond] = require('packer.handlers.event')
    elseif cond == 'ft' then
      t[cond] = require('packer.handlers.ft')
    elseif cond == 'cmd' then
      t[cond] = require('packer.handlers.cmd')
    elseif cond == 'cond' then
      t[cond] = require('packer.handlers.cond')
    end
    return t[cond]
  end,
})
