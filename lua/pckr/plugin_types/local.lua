local log = require('pckr.log')
local util = require('pckr.util')

local uv = vim.loop

--- @class Pckr.PluginHandler.Local: Pckr.PluginHandler
local M = {}

--- @param plugin Pckr.Plugin
--- @param _disp? Pckr.Display
M.installer = function(plugin, _disp)
  uv.fs_symlink(plugin._dir, plugin.install_path)
end

--- Recursively delete a directory
--- @param path string
local function rm(path)
  --- @diagnostic disable-next-line:param-type-mismatch
  local stat = uv.fs_lstat(path)
  if not stat then
    return
  end

  if stat.type == 'directory' then
    for f in vim.fs.dir(path) do
      rm(vim.fs.joinpath(path, f))
    end
    uv.fs_rmdir(path)
    return
  end

  uv.fs_unlink(path)
end

--- @async
--- @param plugin Pckr.Plugin
--- @param disp? Pckr.Display
--- @param opts? table<string,any>
--- @return string?
function M.updater(plugin, disp, opts)
  --- @diagnostic disable-next-line:param-type-mismatch
  local stat = uv.fs_lstat(plugin.install_path)
  if not stat then
    return
  end

  -- Only re-install plugin if the install path is different from the source
  -- of the local plugin
  if stat.type == 'directory' and plugin.install_path ~= plugin._dir then
    rm(plugin.install_path)
    M.installer(plugin, disp)
    if disp then
      disp:task_succeeded(plugin.name, 'linking plugin to local path')
    end
  end

  local gitdir = util.join_paths(plugin.install_path, '.git')
  if uv.fs_stat(gitdir) then
    -- Only ever fast forward local plugins
    opts = vim.deepcopy(opts or {})
    opts.ff_only = true
    return require('pckr.plugin_types.git').updater(plugin, disp, opts)
  end
end

function M.revert_to()
  log.warn("Can't revert a local plugin!")
end

function M.revert_last()
  log.warn("Can't revert a local plugin!")
end

function M.diff()
  log.warn("Can't diff a local plugin!")
end

return M
