local M = {}

--- Partition seq using values in sub
--- @generic T
--- @param sub T[]
--- @param seq T[]
--- @return T[], T[]
function M.partition(sub, seq)
  --- @cast sub any[]
  --- @cast seq any[]

  local sub_vals = {} --- @type table<any,true>
  for _, val in ipairs(sub) do
    sub_vals[val] = true
  end

  local res1, res2 = {}, {}
  for _, val in ipairs(seq) do
    if sub_vals[val] then
      table.insert(res1, val)
    else
      table.insert(res2, val)
    end
  end

  return res1, res2
end

-- TODO(lewis6991): use vim.loop.os_uname().sysname
M.is_windows = jit and jit.os == 'Windows' or package.config:sub(1, 1) == '\\'

M.use_shellslash = M.is_windows and vim.o.shellslash and true

--- @return string
function M.get_separator()
  if M.is_windows and not M.use_shellslash then
    return '\\'
  end
  return '/'
end

--- @param ... string
--- @return string
function M.join_paths(...)
  return (table.concat({ ... }, '/'):gsub('//+', '/'))
end

--- @param f function
--- @return number
function M.measure(f)
  local start_time = vim.loop.hrtime()
  f()
  return (vim.loop.hrtime() - start_time) / 1e9
end

--- @param file string
--- @return string[]?
function M.file_lines(file)
  if not vim.loop.fs_stat(file) then
    return
  end
  local text = {} --- @type string[]
  for line in io.lines(file) do
    text[#text + 1] = line
  end
  return text
end

--- @param path string
--- @param fn fun(_: string, _: string, _: string): boolean?
local function ls(path, fn)
  local handle = vim.loop.fs_scandir(path)
  while handle do
    local name, t = vim.loop.fs_scandir_next(handle)
    if not name or not t then
      break
    end
    if fn(M.join_paths(path, name), name, t) == false then
      break
    end
  end
end

--- @param path string
--- @param fn fun(_: string, _: string, _: string): boolean?
function M.walk(path, fn)
  ls(path, function(child, name, ftype)
    if ftype == 'directory' then
      M.walk(child, fn)
    end
    fn(child, name, ftype)
  end)
end

return M
