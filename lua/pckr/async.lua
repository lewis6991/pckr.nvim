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
local function run(func, callback, ...)
  validate_callback(func, callback)

  local co = coroutine.create(func)

  local function step(...)
    local ret = { coroutine.resume(co, ...) }
    local stat = ret[1]

    if not stat then
      local err = ret[2] --[[@as string]]
      error(
        string.format('The coroutine failed with this message: %s\n%s', err, debug.traceback(co))
      )
    end

    if coroutine.status(co) == 'dead' then
      if callback then
        callback(unpack(ret, 2, table.maxn(ret)))
      end
      return
    end

    --- @type integer, fun(...: any): any
    local nargs, fn = ret[2], ret[3]

    assert(type(fn) == 'function', 'type error :: expected func')

    --- @type any[]
    local args = { unpack(ret, 4, table.maxn(ret)) }
    args[nargs] = step
    fn(unpack(args, 1, nargs))
  end

  step(...)
end

local M = {}

--- @param argc integer
--- @param func function
--- @param ... any
--- @return any ...
function M.wait(argc, func, ...)
  -- Always run the wrapped functions in xpcall and re-raise the error in the
  -- coroutine. This makes pcall work as normal.
  local function pfunc(...)
    local args = { ... } --- @type any[]
    local cb = args[argc]
    args[argc] = function(...)
      cb(true, ...)
    end
    xpcall(func, function(err)
      cb(false, err, debug.traceback())
    end, unpack(args, 1, argc))
  end

  local ret = { coroutine.yield(argc, pfunc, ...) }

  local ok = ret[1]
  if not ok then
    --- @type string, string
    local err, traceback = ret[2], ret[3]
    error(string.format('Wrapped function failed: %s\n%s', err, traceback))
  end

  return unpack(ret, 2, table.maxn(ret))
end

--- Creates an async function with a callback style function.
--- @param argc integer
--- @param func function
--- @return function
function M.wrap(argc, func)
  assert(type(argc) == 'number')
  assert(type(func) == 'function')
  return function(...)
    return M.wait(argc, func, ...)
  end
end

---Use this to create a function which executes in an async context but
---called from a non-async context. Inherently this cannot return anything
---since it is non-blocking
--- @generic F: function
--- @param nargs integer
--- @param func async F
--- @return F
function M.sync(nargs, func)
  return function(...)
    assert(not coroutine.running())
    local callback = select(nargs + 1, ...)
    run(func, callback, unpack({ ... }, 1, nargs))
  end
end

--- @generic R
--- @param n integer Mx number of jobs to run concurrently
--- @param thunks (fun(cb: function): R)[]
--- @param interrupt_check fun()?
--- @param callback fun(ret: R[][])
M.join = M.wrap(4, function(n, thunks, interrupt_check, callback)
  n = math.min(n, #thunks)

  local ret = {} --- @type any[][]

  if #thunks == 0 then
    callback(ret)
    return
  end

  local remaining = { unpack(thunks, n + 1) }
  local to_go = #thunks

  local function cb(...)
    ret[#ret + 1] = { ... }
    to_go = to_go - 1
    if to_go == 0 then
      callback(ret)
    elseif not interrupt_check or not interrupt_check() then
      if #remaining > 0 then
        local next_thunk = table.remove(remaining, 1)
        next_thunk(cb)
      end
    end
  end

  for i = 1, n do
    thunks[i](cb)
  end
end)

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
M.schedule = M.wrap(1, vim.schedule)

return M
