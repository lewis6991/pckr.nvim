local util = {}

--- Partition seq using values in sub
--- @generic T
--- @param sub T[]
--- @param seq T[]
--- @return T[], T[]
function util.partition(sub, seq)
  local sub_vals = {}
  for _, val in ipairs(sub) do
    sub_vals[val] = true
  end

  local result = { {}, {} }
  for _, val in ipairs(seq) do
    if sub_vals[val] then
      table.insert(result[1], val)
    else
      table.insert(result[2], val)
    end
  end

  return unpack(result)
end

-- TODO(lewis6991): use vim.loop.os_uname().sysname
util.is_windows = jit and jit.os == 'Windows' or package.config:sub(1, 1) == '\\'

util.use_shellslash = util.is_windows and vim.o.shellslash and true

--- @return string
function util.get_separator()
  if util.is_windows and not util.use_shellslash then
    return '\\'
  end
  return '/'
end

--- @param path string
--- @return string
function util.strip_trailing_sep(path)
  local res = path:gsub(util.get_separator() .. '$', '', 1)
  return res
end

--- @param ... string
--- @return string
function util.join_paths(...)
  return table.concat({ ... }, util.get_separator())
end

--- @param f function
--- @return number
function util.measure(f)
  local start_time = vim.loop.hrtime()
  f()
  return (vim.loop.hrtime() - start_time) / 1e9
end

--- @param file string
--- @return string[]?
function util.file_lines(file)
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
    if fn(util.join_paths(path, name), name, t) == false then
      break
    end
  end
end

--- @param path string
--- @param fn fun(_: string, _: string, _: string): boolean?
function util.walk(path, fn)
  ls(path, function(child, name, ftype)
    if ftype == 'directory' then
      util.walk(child, fn)
    end
    fn(child, name, ftype)
  end)
end

return util
