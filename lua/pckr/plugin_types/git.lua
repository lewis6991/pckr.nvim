local a = require('pckr.async')
local config = require('pckr.config')
local jobs = require('pckr.jobs')
local log = require('pckr.log')
local util = require('pckr.util')

local fmt = string.format
local uv = vim.loop

--- @class Pckr.PluginHandler.Git: Pckr.PluginHandler
local M = {}

--- @type string[]
local job_env = {}

do
  local blocked_env_vars = {
    GIT_DIR = true,
    GIT_INDEX_FILE = true,
    GIT_OBJECT_DIRECTORY = true,
    GIT_TERMINAL_PROMPT = true,
    GIT_WORK_TREE = true,
    GIT_COMMON_DIR = true,
  }

  for k, v in
    pairs(vim.fn.environ() --[[@as table<string,string>]])
  do
    if not blocked_env_vars[k] then
      job_env[#job_env + 1] = k .. '=' .. v
    end
  end

  job_env[#job_env + 1] = 'GIT_TERMINAL_PROMPT=0'
end

---@param tag string
---@return boolean
local function has_wildcard(tag)
  return tag and tag:match('*') ~= nil
end

local BREAK_TAG_PAT = '[[bB][rR][eE][aA][kK]!?:]'
local BREAKING_CHANGE_PAT = '[[bB][rR][eE][aA][kK][iI][nN][gG][ _][cC][hH][aA][nN][gG][eE]]'
local TYPE_EXCLAIM_PAT = '[[a-zA-Z]+!:]'
local TYPE_SCOPE_EXPLAIN_PAT = '[[a-zA-Z]+%([^)]+%)!:]'

---@param x string
---@return boolean
local function is_breaking(x)
  return x
    and (
        x:match(BREAKING_CHANGE_PAT)
        or x:match(BREAK_TAG_PAT)
        or x:match(TYPE_EXCLAIM_PAT)
        or x:match(TYPE_SCOPE_EXPLAIN_PAT)
      )
      ~= nil
end

---@param commit_bodies string
---@return string[]
local function get_breaking_commits(commit_bodies)
  local ret = {} --- @type string[]
  local commits = vim.gsplit(commit_bodies, '===COMMIT_START===', { plain = true })

  for commit in commits do
    local commit_parts = vim.split(commit, '===BODY_START===')
    local body = commit_parts[2]
    local lines = vim.split(commit_parts[1], '\n')
    if is_breaking(body) or is_breaking(lines[2]) then
      ret[#ret + 1] = lines[1]
    end
  end
  return ret
end

--- @param args string[]
--- @param opts? vim.SystemOpts
--- @return boolean, string
local function git_run(args, opts)
  opts = opts or {}
  opts.env = opts.env or job_env
  local obj = jobs.run({
    config.git.cmd,
    '-c',
    'advice.diverging=false',
    '-c',
    'advice.resolveConflict=false',
    unpack(args),
  }, opts)
  local ok = obj.code == 0 and obj.signal == 0
  if ok then
    return true, obj.stdout
  end
  return false, obj.stderr
end

--- @type {[1]: integer, [2]: integer, [3]: integer}
local git_version

--- @param version string
--- @return {[1]: integer, [2]: integer, [3]: integer}
local function parse_version(version)
  assert(version:match('%d+%.%d+%.%w+'), 'Invalid git version: ' .. version)
  local parts = vim.split(version, '%.')
  local ret = {} --- @type number[]
  ret[1] = tonumber(parts[1])
  ret[2] = tonumber(parts[2])

  if parts[3] == 'GIT' then
    ret[3] = 0
  else
    ret[3] = tonumber(parts[3])
  end

  return ret
end

local function set_version()
  if git_version then
    return
  end

  local vok, out = git_run({ '--version' })
  if vok then
    local line = out
    local ok, err = pcall(function()
      assert(vim.startswith(line, 'git version'), 'Unexpected output: ' .. line)
      local parts = vim.split(line, '%s+')
      git_version = parse_version(parts[3])
    end)
    if not ok then
      log.error(err)
      return
    end
  end
end

--- @param version {[1]: integer, [2]: integer, [3]: integer}
--- @return boolean
local function check_version(version)
  set_version()

  if not git_version then
    return false
  end

  if git_version[1] < version[1] then
    return false
  end

  if version[2] and git_version[2] < version[2] then
    return false
  end

  if version[3] and git_version[3] < version[3] then
    return false
  end

  return true
end

--- @param ... string
--- @return string?
local function head(...)
  local lines = util.file_lines(util.join_paths(...))
  if lines then
    return lines[1]
  end
end

local SHA_PAT = string.rep('%x', 40)

---@param dir string
---@param ref string
---@return string?
local function resolve_ref(dir, ref)
  if ref:match(SHA_PAT) then
    return ref
  end
  local ptr = ref:match('^ref: (.*)')
  if ptr then
    return head(dir, '.git', unpack(vim.split(ptr, '/')))
  end
end

---@param dir string
---@param what? string
---@return string?
local function get_head(dir, what)
  return resolve_ref(dir, assert(head(dir, '.git', what or 'HEAD')))
end

---@param dir string
---@return table<string,string>
local function packed_refs(dir)
  local refs = util.join_paths(dir, '.git', 'packed-refs')
  local lines = util.file_lines(refs)
  local ret = {} --- @type table<string,string>
  for _, line in ipairs(lines or {}) do
    local ref, name = line:match('^(.*) refs/(.*)$')
    if ref then
      ret[name] = ref
    end
  end
  return ret
end

---@param dir string
---@param ... string
---@return string
local function ref(dir, ...)
  local x = head(dir, '.git', 'refs', ...)
  if x then
    return x
  end
  local r = table.concat({ ... }, '/')
  return packed_refs(dir)[r]
end

---@param plugin Pckr.Plugin
---@return string
local function get_current_branch(plugin)
  -- first try local HEAD
  local remote_head = ref(plugin.install_path, 'remotes', 'origin', 'HEAD')
  if remote_head then
    local branch = remote_head:match('^ref: refs/remotes/origin/(.*)')
    if branch then
      return branch
    end
  end

  -- fallback to local HEAD
  local local_head = head(plugin.install_path, '.git', 'HEAD')

  if local_head then
    local branch = local_head:match('^ref: refs/heads/(.*)')
    if branch then
      return branch
    end
  end

  error('Could not get current branch for ' .. plugin.install_path)
end

---@param x string
---@return string[]
local function process_progress(x)
  -- Only consider text after the last \r
  local rlines = vim.split(x, '\r')
  local line --- @type string
  if rlines[#rlines] == '' then
    line = rlines[#rlines - 1]
  else
    line = rlines[#rlines]
  end

  local lines = vim.split(line, '\n', { plain = true })
  if lines[#lines] == '' then
    lines[#lines] = nil
  end
  return lines
end

---@param plugin Pckr.Plugin
---@return string?, string?
local function resolve_tag(plugin)
  local tag = plugin.tag
  local ok, out = git_run({
    'tag',
    '-l',
    tag,
    '--sort',
    '-version:refname',
  }, {
    cwd = plugin.install_path,
  })

  if ok then
    tag = vim.split(out[#out], '\n')[1]
    return tag
  end

  log.fmt_warn(
    'Wildcard expansion did not find any tag for plugin %s: defaulting to latest commit...',
    plugin.name
  )

  -- Wildcard is not found, then we bypass the tag
  return nil, out
end

--- @param path string
--- @param branch string
--- @return string?
local function resolve_branch(path, branch)
  local remote_target = ref(path, 'remotes', 'origin', branch)
  return remote_target or ref(path, 'heads', branch)
end

--- @param plugin Pckr.Plugin
--- @param update_task? fun(msg: string, info?: string[])
--- @return boolean, string
local function checkout(plugin, update_task)
  update_task = update_task or function() end

  update_task('fetching reference...')

  local commit, tag = plugin.commit, plugin.tag

  local target --- @type string?
  local checkout_args = {} --- @type string[]

  if commit then
    target = commit
  elseif tag then
    -- Resolve tag
    if has_wildcard(tag) then
      update_task(fmt('getting tag for wildcard %s...', tag))
      local tagerr
      tag, tagerr = resolve_tag(plugin)
      if not tag then
        return false, assert(tagerr)
      end
    end

    target = 'tags/' .. tag
  else
    local branch = plugin.branch or get_current_branch(plugin)
    vim.list_extend(checkout_args, { '-B', branch })
    target = resolve_branch(plugin.install_path, branch)
    if not target then
      return false, 'Could not find commit for branch ' .. branch
    end
  end

  assert(target, 'Could not determine target for ' .. plugin.install_path)

  update_task('checking out...')
  local cmd = vim.list_extend({ 'checkout', '--progress', target }, checkout_args)
  return git_run(cmd, {
    cwd = plugin.install_path,
    on_stderr = function(chunk)
      update_task('checking out... ', process_progress(chunk))
    end,
  })
end

--- @param plugin Pckr.Plugin
--- @return boolean, string
local function mark_breaking_changes(plugin)
  local ok, out = git_run({
    'log',
    '--color=never',
    '--no-show-signature',
    '--pretty=format:===COMMIT_START===%h%n%s===BODY_START===%b',
    'HEAD@{1}...HEAD',
  }, {
    cwd = plugin.install_path,
  })
  if ok then
    plugin.breaking_commits = get_breaking_commits(out)
  end
  return ok, out
end

--- @async
--- @param plugin Pckr.Plugin
--- @param update_task fun(msg: string, info?: string[])
--- @param timeout integer Timeout in ms
--- @return boolean, string
local function clone(plugin, update_task, timeout)
  update_task('cloning...')

  local clone_cmd = {
    'clone',
    '--no-checkout',
    '--progress',
  }

  -- partial clone support
  if check_version({ 2, 19, 0 }) then
    vim.list_extend(clone_cmd, {
      '--filter=blob:none',
    })
  end

  vim.list_extend(clone_cmd, { plugin.url, plugin.install_path })

  return git_run(clone_cmd, {
    timeout = timeout,
    on_stderr = function(chunk)
      update_task('cloning...', process_progress(chunk))
    end,
  })
end

--- @async
--- If `path` is a link, remove it if the destination does not exist.
--- @param path string
local function sanitize_path(path)
  assert(path)
  --- @diagnostic disable-next-line
  local lerr, stat = a.wrap(uv.fs_lstat, 2)(path)
  --- @diagnostic disable-next-line
  if lerr or stat.type ~= 'link' then
    -- path doesn't exist or isn't a link
    return
  end

  -- path is a link; check destination exists, otherwise delete
  local err = a.wrap(uv.fs_realpath, 2)(path)
  if not err then
    -- exists
    return
  end

  -- dead link; remove
  a.wrap(uv.fs_unlink, 2)(path)
end

--- @async
--- @param plugin Pckr.Plugin
--- @param disp? Pckr.Display
--- @return boolean?, string
local function install(plugin, disp)
  --- @param msg string
  --- @param info? string[]
  local function update_task(msg, info)
    if disp then
      vim.schedule(function()
        disp:task_update(plugin.name, msg, info)
      end)
    end
  end

  sanitize_path(plugin.install_path)

  local ok, out = clone(plugin, update_task, config.git.clone_timeout * 1000)
  if not ok then
    return nil, out
  end

  ok, out = checkout(plugin, update_task)
  if not ok then
    return nil, out
  end

  return true, out
end

--- @async
--- @param plugin Pckr.Plugin
--- @param disp? Pckr.Display
--- @return string?
function M.installer(plugin, disp)
  local ok, out = install(plugin, disp)

  if ok then
    plugin.messages = out
    return
  end

  plugin.err = out

  return out
end

--- @param plugin Pckr.Plugin
--- @param msg string
--- @param x any
local function log_err(plugin, msg, x)
  local x1 = type(x) == 'string' and x or table.concat(x, '\n')
  log.fmt_debug('%s: $s: %s', plugin.name, msg, x1)
end

--- @async
--- @param plugin Pckr.Plugin
--- @param disp? Pckr.Display
--- @param opts? table<string,any>
--- @return boolean, string?
local function update(plugin, disp, opts)
  --- @param msg string
  --- @param info? string[]
  local function update_task(msg, info)
    if disp then
      a.main()
      disp:task_update(plugin.name, msg, info)
    end
  end

  update_task('checking current commit...')
  plugin.revs[1] = get_head(plugin.install_path)

  do -- fetch updates
    update_task('fetching updates...')
    local ok, out = git_run({
      'fetch',
      '--tags',
      '--force',
      '--update-shallow',
      '--progress',
    }, {
      cwd = plugin.install_path,
      on_stderr = function(chunk)
        update_task('fetching updates...', process_progress(chunk))
      end,
    })
    if not ok then
      return false, out
    end
  end

  if not opts or not opts.check then -- pull updates
    update_task('pulling updates...')
    local ok, out --- @type boolean, string?

    if opts and opts.ff_only then
      ok, out = git_run({ 'merge', '--ff-only', '--progress' }, {
        cwd = plugin.install_path,
        on_stderr = function(chunk)
          update_task('fast forwarding...', process_progress(chunk))
        end,
      })
    else
      ok, out = checkout(plugin, update_task)
    end

    if not ok then
      log_err(plugin, 'failed update', out)
      return false, out
    end
  end

  if opts and opts.check then
    local ok, out = git_run({'rev-parse', '@{upstream}'}, { cwd = plugin.install_path })
    if not ok then
      log_err(plugin, 'failed rev-parse', out)
      return false, out
    end
    plugin.revs[2] = assert(out:gsub('%s', ''))
  else
    plugin.revs[2] = get_head(plugin.install_path)
  end

  if plugin.revs[1] == plugin.revs[2] then
    return true
  end

  update_task('getting commit messages...')
  local ok, out = git_run({
    'log',
    '--color=never',
    '--pretty=format:%h %s (%cr)',
    '--no-show-signature',
    fmt('%s...%s', plugin.revs[1], plugin.revs[2]),
  }, {
    cwd = plugin.install_path,
  })

  if not ok then
    log_err(plugin, 'failed getting commit messages', out)
    return false, out
  end

  update_task('checking for breaking changes...')
  local out2 --- @type string
  ok, out2 = mark_breaking_changes(plugin)
  if not ok then
    log_err(plugin, 'failed marking breaking changes', out2)
    return false, out2
  end

  return true, out
end

--- @async
--- @param plugin Pckr.Plugin
--- @param disp? Pckr.Display
--- @param opts? table<string,any>
--- @return string?
function M.updater(plugin, disp, opts)
  local ok, out = update(plugin, disp, opts)
  if not ok then
    plugin.err = out
    return out
  end
  plugin.messages = out
end

--- @async
--- @param plugin Pckr.Plugin
--- @return string?
function M.remote_url(plugin)
  local ok, out = git_run({ 'remote', 'get-url', 'origin' }, {
    cwd = plugin.install_path,
  })

  if ok then
    return out[1]
  end
end

--- @async
--- @param plugin Pckr.Plugin
--- @param commit string
--- @return string?, string?
function M.diff(plugin, commit)
  local ok, out = git_run({
    'show',
    '--no-color',
    '--pretty=medium',
    commit,
  }, {
    cwd = plugin.install_path,
  })

  if not ok then
    return nil, out
  end
  return out
end

--- @async
--- @param plugin Pckr.Plugin
--- @return string?
function M.revert_last(plugin)
  local ok, out = git_run({ 'reset', '--hard', 'HEAD@{1}' }, {
    cwd = plugin.install_path,
  })

  if not ok then
    log.fmt_error('Reverting update for %s failed!', plugin.name)
    return out
  end

  ok, out = checkout(plugin)
  if not ok then
    log.fmt_error('Reverting update for %s failed!', plugin.name)
    return out
  end

  log.fmt_info('Reverted update for %s', plugin.name)
end

--- @async
--- Reset the plugin to `commit`
--- @param plugin Pckr.Plugin
--- @param commit string
--- @return string?
function M.revert_to(plugin, commit)
  assert(type(commit) == 'string', fmt("commit: string expected but '%s' provided", type(commit)))
  log.fmt_debug("Reverting '%s' to commit '%s'", plugin.name, commit)
  local ok, out = git_run({ 'reset', '--hard', commit, '--' }, {
    cwd = plugin.install_path,
  })

  if not ok then
    return out
  end
end

--- @async
--- Returns HEAD's short hash
--- @param plugin Pckr.Plugin
--- @return string?
function M.get_rev(plugin)
  return get_head(plugin.install_path)
end

return M
