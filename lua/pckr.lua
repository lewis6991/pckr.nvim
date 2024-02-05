local api = vim.api

local log = require('pckr.log')
local config = require('pckr.config')
local plugin = require('pckr.plugin')
local loader = require('pckr.loader')

local did_setup = false

--- @param user_config? Pckr.UserConfig
local function setup(user_config)
  log.debug('setup')
  config(user_config)

  -- loaded manually in loader.lua
  vim.go.loadplugins = config._native_loadplugins

  if not config._native_packadd then
    -- We will handle loading of all plugins so minimise packpath
    vim.go.packpath = vim.env.VIMRUNTIME
  end

  for _, dir in ipairs({ config._opt_dir, config._start_dir }) do
    if vim.fn.isdirectory(dir) == 0 then
      vim.fn.mkdir(dir, 'p')
    end
  end

  did_setup = true
end

local M = {}

--- @param spec string|Pckr.UserSpec|(string|Pckr.UserSpec)[]
function M.add(spec)
  if not did_setup then
    setup()
  end

  log.debug('PROCESSING PLUGIN SPEC')
  plugin.process_spec(spec)

  local to_install = {} --- @type string[]

  if config.autoinstall then
    for name, p in pairs(plugin.plugins) do
      if not p.installed then
        to_install[#to_install + 1] = name
      end
    end
  end

  if #to_install > 0 then
    local cwin = api.nvim_get_current_win()
    require('pckr.actions').install(to_install, nil, function()
      -- Run loader in initial window so window options set properly
      api.nvim_win_call(cwin, loader.setup)
    end)
  else
    loader.setup()
  end
end

-- This should be safe to call multiple times.
--- @param user_config Pckr.UserConfig
--- @param user_spec? Pckr.UserSpec
function M.setup(user_config, user_spec)
  setup(user_config)

  if user_spec then
    M.add(user_spec)
  end
end

return M
