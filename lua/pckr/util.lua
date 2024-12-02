local uv = vim.uv or vim.loop

local M = {}

-- TODO(lewis6991): use vim.loop.os_uname().sysname
M.is_windows = jit and jit.os == 'Windows' or package.config:sub(1, 1) == '\\'

local use_shellslash = M.is_windows and vim.o.shellslash and true

--- @return string
function M.get_separator()
  if M.is_windows and not use_shellslash then
    return '\\'
  end
  return '/'
end

--- @param ... string
--- @return string
function M.join_paths(...)
  return (table.concat({ ... }, '/'):gsub('//+', '/'))
end

--- @type table<string, number>
M.measure_times = {}
setmetatable(M.measure_times, {
  __index = function()
    return 0
  end,
})

--- @param what? string|function
--- @param f? function
--- @return number
function M.measure(what, f)
  if type(what) == 'function' then
    f = what
    what = nil
  end

  assert(f)

  local start_time = uv.hrtime()
  f()
  local d = (uv.hrtime() - start_time) / 1e6

  if what then
    M.measure_times[what] = (M.measure_times[what] or 0) + d
  end

  return d
end

--- @param file string
--- @return string[]?
function M.file_lines(file)
  if not uv.fs_stat(file) then
    return
  end
  local text = {} --- @type string[]
  for line in io.lines(file) do
    text[#text + 1] = line
  end
  return text
end

return M
