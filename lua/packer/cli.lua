local log = require('packer.log')

local M = {}

--- @return string[]
local function command_complete()
  local actions = require('packer.actions')
  return vim.tbl_keys(actions)
end

-- Completion user plugins
-- Intended to provide completion for PackerUpdate/Sync/Install command
--- @param lead string
--- @return string[]
local function plugin_complete(lead, _)
  local plugins = require('packer.plugin').plugins
  local completion_list = vim.tbl_filter(
    --- @param name string
    --- @return boolean
    function(name)
      return vim.startswith(name, lead)
    end,
    vim.tbl_keys(plugins)
  )
  table.sort(completion_list)
  return completion_list
end

--- @param arglead string
--- @param line string
--- @return string[]
function M.complete(arglead, line)
  local words = vim.split(line, '%s+')
  local n = #words

  local matches = {}
  if n == 2 then
    matches = command_complete()
  elseif n > 2 then
    matches = plugin_complete(arglead)
  end
  return matches
end

--- @param args string[]
--- @return table<string,boolean> options
--- @return string[] plugins
local function process_args(args)
  local opts = {} --- @type table<string,boolean>
  local plugins = {} --- @type string[]

  for _, arg in ipairs(args)do
    if arg:match('%-%-*w+') then
      opts[arg] = true
    else
      plugins[#plugins+1] = arg
    end
  end

  return opts, plugins
end

function M.run(params)
  --- @type string
  local func = params.fargs[1]

  if not func then
    log.error('No subcommand provided')
  end

  local actions = require('packer.actions')

  --- @type function?
  local cmd_func = actions[func]
  if cmd_func then
    local args0 = vim.list_slice(params.fargs, 2)
    local kwargs, args = process_args(args0)
    cmd_func(args, kwargs)
    return
  end

  log.fmt_error('%s is not a valid function or action', func)
end

return M
