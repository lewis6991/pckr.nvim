local api = vim.api

local log = require('packer.log')
local config = require('packer.config')
local plugin = require('packer.plugin')
local loader = require('packer.loader')

local did_setup = false

--- @param user_config? Config
local function setup(user_config)
  log.debug('setup')

  config(user_config)

  for _, dir in ipairs({ config.opt_dir, config.start_dir }) do
    if vim.fn.isdirectory(dir) == 0 then
      vim.fn.mkdir(dir, 'p')
    end
  end

  did_setup = true
end

local M = {}

local function load_plugins()
  log.debug('LOADING PLUGINS')
  loader.setup(plugin.plugins)
end

function M.add(spec)
  if not did_setup then
    setup()
  end

  log.debug('PROCESSING PLUGIN SPEC')
  plugin.process_spec(spec)

  local to_install = {}  --- @type string[]

  if config.autoinstall then
    for name, p in pairs(plugin.plugins) do
      if not p.installed then
        to_install[#to_install+1] = name
      end
    end
  end

  if #to_install > 0 then
    local cwin = api.nvim_get_current_win()
    require('packer.actions').install(to_install, nil, function()
      -- Run loader in initial window so window options set properly
      api.nvim_win_call(cwin, load_plugins)
    end)
  else
    load_plugins()
  end
end

-- This should be safe to call multiple times.
--- @param user_config Config
--- @param user_spec? UserSpec
function M.setup(user_config, user_spec)
  setup(user_config)

  if user_spec then
    M.add(user_spec)
  end
end

return M
