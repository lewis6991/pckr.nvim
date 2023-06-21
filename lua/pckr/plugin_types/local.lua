local a = require('pckr.async')
local log = require('pckr.log')
local util = require('pckr.util')

local uv = vim.loop

--- @class Pckr.PluginHandler
local M = {}

-- Due to #679, we know that fs_symlink requires admin privileges on Windows. This is a workaround,
-- as suggested by @nonsleepr.

--- @type `uv.fs_symlink`
local symlink_fn
if util.is_windows then
  symlink_fn = function(path, new_path, flags, callback)
    flags = flags or {}
    flags.junction = true
    return uv.fs_symlink(path, new_path, flags, callback)
  end
else
  symlink_fn = uv.fs_symlink
end

local symlink = a.wrap(symlink_fn, 4)
local unlink = a.wrap(uv.fs_unlink, 2)

M.installer = a.sync(function(plugin, disp)
  local from = uv.fs_realpath(util.strip_trailing_sep(plugin.url))
  local to = util.strip_trailing_sep(plugin.install_path)

  disp:task_update(plugin.name, 'making symlink...')
  local err, success = symlink(from, to, { dir = true })
  if not success then
    plugin.err = { err }
    return plugin.err
  end
end, 2)

local sleep = a.wrap(function(ms, cb)
  vim.defer_fn(cb, ms)
end, 2)

--- @param plugin Pckr.Plugin
--- @param disp Pckr.Display
--- @return string[]?
M.updater = a.sync(function(plugin, disp)
  local from = uv.fs_realpath(util.strip_trailing_sep(plugin.url))
  local to = util.strip_trailing_sep(plugin.install_path)

  -- Put some artificial delays here, just so the user can see task updates in
  -- display
  -- TODO(lewis6991): remove when things are more stable
  sleep(200)

  disp:task_update(plugin.name, 'checking symlink...')

  sleep(200)

  --- @diagnostic disable-next-line:param-type-mismatch
  local is_link = uv.fs_lstat(to).type == 'link'
  if not is_link then
    log.fmt_debug('%s: %s is not a link', plugin.name, to)
    return { to .. ' is not a link' }
  end

  if uv.fs_realpath(to) == from then
    return
  end

  disp:task_update(plugin.name, string.format('updating symlink from %s to %s', from, to))
  local err, success = unlink(to)
  if err then
    log.fmt_debug('%s: failed to unlink %s: %s', plugin.name, to, err)
    return { err }
  end
  assert(success)
  log.fmt_debug('%s: did unlink', plugin.name)
  local err2 = symlink(from, to, { dir = true })
  if err2 then
    log.fmt_debug('%s: failed to link from %s to %s: %s', plugin.name, from, to, err2)
    return { err2 }
  end
end, 1)

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
