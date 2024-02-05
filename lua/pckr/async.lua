local co = coroutine

local function validate_callback(func, callback)
  if callback and type(callback) ~= 'function' then
    local info = debug.getinfo(func, 'nS')
    error(
      string.format(
        'Callback is not a function for %s, got: %s',
        info.short_src .. ':' .. info.linedefined,
        vim.inspect(callback)
      )
    )
  end
end

--- Executes a future with a callback when it is done
--- @param func function
--- @param callback function?
--- @param ... any
local function execute(func, callback, ...)
  validate_callback(func, callback)

  local thread = co.create(func)

  local function step(...)
    local ret = { co.resume(thread, ...) }
    --- @type boolean, integer, function
    local stat, nargs, fn_or_ret = unpack(ret)

    if not stat then
      error(
        string.format(
          'The coroutine failed with this message: %s\n%s',
          nargs,
          debug.traceback(thread)
        )
      )
    end

    if co.status(thread) == 'dead' then
      if callback then
        callback(unpack(ret, 2))
      end
      return
    end

    local args = { select(4, unpack(ret)) }
    args[nargs] = step
    fn_or_ret(unpack(args, 1, nargs))
  end

  step(...)
end

local M = {}

--- Creates an async function with a callback style function.
--- @generic F: function
--- @param func F
--- @param argc integer
--- @return F
function M.wrap(func, argc)
  return function(...)
    if not co.running() or select('#', ...) == argc then
      return func(...)
    end
    return co.yield(argc, func, ...)
  end
end

---Use this to create a function which executes in an async context but
---called from a non-async context. Inherently this cannot return anything
---since it is non-blocking
--- @generic F: function
--- @param func async F
--- @param nargs? integer
--- @return F
function M.sync(func, nargs)
  nargs = nargs or 0
  return function(...)
    if co.running() then
      return func(...)
    end
    local callback = select(nargs + 1, ...)
    execute(func, callback, unpack({ ... }, 1, nargs))
  end
end

--- For functions that don't provide a callback as there last argument
--- @generic F: function
--- @param func F
--- @return F
function M.void(func)
  return function(...)
    if co.running() then
      return func(...)
    end
    execute(func, nil, ...)
  end
end

--- @generic R
--- @param n integer Mx number of jobs to run concurrently
--- @param interrupt_check fun()?
--- @param thunks (fun(cb: function): R)[]
--- @return {[1]: R}[]
function M.join(n, interrupt_check, thunks)
  return co.yield(1, function(finish)
    if #thunks == 0 then
      return finish()
    end

    local remaining = { select(n + 1, unpack(thunks)) }
    local to_go = #thunks

    local ret = {} --- @type any[][]

    local function cb(...)
      ret[#ret + 1] = { ... }
      to_go = to_go - 1
      if to_go == 0 then
        finish(ret)
      elseif not interrupt_check or not interrupt_check() then
        if #remaining > 0 then
          local next_task = table.remove(remaining)
          next_task(cb)
        end
      end
    end

    for i = 1, math.min(n, #thunks) do
      thunks[i](cb)
    end
  end, 1)
end

---Useful for partially applying arguments to an async function
--- @param fn function
--- @param ... any
--- @return function
function M.curry(fn, ...)
  --- @type integer, any[]
  local nargs, args = select('#', ...), { ... }

  return function(...)
    local other = { ... }
    for i = 1, select('#', ...) do
      args[nargs + i] = other[i]
    end
    return fn(unpack(args))
  end
end

---An async function that when called will yield to the Neovim scheduler to be
---able to call the API.
--- @type fun()
M.main = M.wrap(vim.schedule, 1)

return M
