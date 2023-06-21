local pckr_config = require('pckr.config').log

local start_time = vim.loop.hrtime()

-- log.lua
--
-- Inspired by rxi/log.lua
-- Modified by tjdevries and can be found at github.com/tjdevries/vlog.nvim
--
-- This library is free software; you can redistribute it and/or modify it
-- under the terms of the MIT license. See LICENSE for details.
-- User configuration section

--- @alias LogLevel 'trace' | 'debug' | 'info' | 'warn' | 'error' | 'fatal'

--- @class LogConfig
--- @field active_levels_console table<integer,boolean>
--- @field active_levels_file    table<integer,boolean>
--- @field use_file              boolean
--- @field level                 LogLevel
--- @field level_file            LogLevel

--- @type LogConfig
local default_config = {
  -- Should write to a file
  use_file = true,

  -- Any messages above this level will be logged.
  level = 'debug',

  -- Which levels should be logged?

  active_levels_console = {
    [1] = true,
    [2] = true,
    [3] = true,
    [4] = true,
    [5] = true,
    [6] = true,
  },

  active_levels_file = {
    [1] = true,
    [2] = true,
    [3] = true,
    [4] = true,
    [5] = true,
    [6] = true,
  },

  level_file = 'trace',
}

--- @class LevelConfig
--- @field name LogLevel
--- @field hl string

--- @type LevelConfig[]
local MODES = {
  { name = 'trace', hl = 'Comment' },
  { name = 'debug', hl = 'Comment' },
  { name = 'info', hl = 'None' },
  { name = 'warn', hl = 'WarningMsg' },
  { name = 'error', hl = 'ErrorMsg' },
  { name = 'fatal', hl = 'ErrorMsg' },
}

-- Can limit the number of decimals displayed for floats
local FLOAT_PRECISION = 0.01

local level_ids = { trace = 1, debug = 2, info = 3, warn = 4, error = 5, fatal = 6 }

--- @param x number
--- @param increment number
--- @return number
local function round(x, increment)
  increment = increment or 1
  x = x / increment
  return (x > 0 and math.floor(x + 0.5) or math.ceil(x - 0.5)) * increment
end

--- @return string[]
local function stringify(...)
  local t = {} --- @type string[]
  for i = 1, select('#', ...) do
    local x = select(i, ...)

    if type(x) == 'number' then
      x = tostring(round(x, FLOAT_PRECISION))
    elseif type(x) ~= 'string' then
      x = vim.inspect(x)
    end

    t[#t + 1] = x
  end
  return t
end

local config = vim.deepcopy(default_config)

config.level = pckr_config.level

local min_active_level = level_ids[config.level]
if min_active_level then
  for i = min_active_level, 6 do
    config.active_levels_console[i] = true
  end
end

local cache_dir = vim.fn.stdpath('cache')

local outfile = string.format('%s/pckr.nvim.log', cache_dir)
vim.fn.mkdir(cache_dir, 'p')

--- @type table<LogLevel,integer>
local levels = {}

for i, v in ipairs(MODES) do
  levels[v.name] = i
end

---@param level_config LevelConfig
---@param message_maker fun(...): string
---@param ... any
local function log_at_level_console(level_config, message_maker, ...)
  local msg = message_maker(...)
  local info = debug.getinfo(4, 'Sl')
  vim.schedule(function()
    --- @type string
    local console_lineinfo = vim.fn.fnamemodify(info.short_src, ':t') .. ':' .. info.currentline
    local console_string = string.format(
      '[%-6s%s] %s: %s',
      level_config.name:upper(),
      os.date('%H:%M:%S'),
      console_lineinfo,
      msg
    )

    -- Heuristic to check for nvim-notify
    local is_fancy_notify = type(vim.notify) == 'table'
    vim.notify(
      string.format([[%s%s]], is_fancy_notify and '' or '[pckr.nvim', console_string),
      vim.log.levels[level_config.name:upper()],
      { title = 'pckr.nvim' }
    )
  end)
end

local HOME = vim.env.HOME

---@param level_config LevelConfig
---@param message_maker fun(...): string
---@param ... any
local function log_at_level_file(level_config, message_maker, ...)
  -- Output to log file
  local fp, err = io.open(outfile, 'a')
  if not fp then
    print(err)
    return
  end

  local info = debug.getinfo(4, 'Sl')
  local src = info.short_src:gsub(HOME, '~')
  --- @type string
  local lineinfo = src .. ':' .. info.currentline

  fp:write(
    string.format(
      '[%-6s%s %s] %s: %s\n',
      level_config.name:upper(),
      os.date('%H:%M:%S'),
      vim.loop.hrtime() - start_time,
      lineinfo,
      message_maker(...)
    )
  )

  fp:close()
end

---comment
---@param level integer
---@param level_config LevelConfig
---@param message_maker fun(...): string
---@param ... any
local function log_at_level(level, level_config, message_maker, ...)
  if
    level >= levels[config.level_file]
    and config.use_file
    and config.active_levels_file[level]
  then
    log_at_level_file(level_config, message_maker, ...)
  end
  if level >= levels[config.level] and config.active_levels_console[level] then
    log_at_level_console(level_config, message_maker, ...)
  end
end

--- @class Log
--- @field trace     fun(...: any)
--- @field debug     fun(...: any)
--- @field info      fun(...: any)
--- @field warn      fun(...: any)
--- @field error     fun(...: any)
--- @field fatal     fun(...: any)
--- @field fmt_trace fun(fmt: string, ...: any)
--- @field fmt_debug fun(fmt: string, ...: any)
--- @field fmt_info  fun(fmt: string, ...: any)
--- @field fmt_warn  fun(fmt: string, ...: any)
--- @field fmt_error fun(fmt: string, ...: any)
--- @field fmt_fatal fun(fmt: string, ...: any)
local log = {}

for i, x in ipairs(MODES) do
  --- @diagnostic disable-next-line:no-unknown
  log[x.name] = function(...)
    log_at_level(i, x, function(...)
      return table.concat(stringify(...), ' ')
    end, ...)
  end

  --- @diagnostic disable-next-line:no-unknown
  log['fmt_' .. x.name] = function(fmt, ...)
    log_at_level(i, x, function(...)
      return fmt:format(unpack(stringify(...)))
    end, ...)
  end
end

return log
