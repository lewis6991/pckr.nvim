local api = vim.api

local log = require('pckr.log')
local awrap = require('pckr.async').wrap
local pckr_plugins = require('pckr.plugin').plugins_by_name

local ns = api.nvim_create_namespace('pckr.display')

local HEADER_LINES = 2

local TITLE = 'pckr.nvim'

local SYMBOLS = {
  item = '•',
  working = '⟳',
  error = '✗',
  done = '✓',
}

--- @class Pckr.Display.Item
--- @field status? 'running' | 'failed' | 'success' | 'done'
--- @field message? string
--- @field info? string[] Additional info that can be collapsed
--- @field expanded? boolean Whether info is being displayed
--- @field mark? integer Extmark used track the location of the item in the buffer
--- @field nameMark? integer Extmark used track the location of the item in the buffer

--- @class Pckr.Display.Callbacks
--- @field diff fun(plugin: Pckr.Plugin, commit: string, callback: function)

--- @class Pckr.Display
--- @field items table<string,Pckr.Display.Item?>
local Display = {}

function Display:check()
  return not self.running
end

--- Update a task as having successfully completed
--- @param name string
--- @param message string
--- @param info? string|string[]
function Display:task_succeeded(name, message, info)
  self:task_done(name, message, info, true)
end

--- Update a task as having unsuccessfully failed
--- @param name string
--- @param message string
--- @param info? string|string[]
function Display:task_failed(name, message, info)
  self:task_done(name, message, info, false)
end

--- @private
--- @return string?, [integer, integer]?
function Display:_get_cursor_task()
  local row = unpack(api.nvim_win_get_cursor(0)) - 1
  -- TODO(lewis6991): Another extmark bug(?):
  --       nvim_buf_get_extmarks(0, ns, row-1, row+1, {})
  -- does not return all the extmarks that the following would:
  --       nvim_buf_get_extmarks(0, ns, {row, 0}, {row,-1}, {})
  for _, e in ipairs(api.nvim_buf_get_extmarks(0, ns, 0, -1, { details = true })) do
    local id, srow, erow = e[1], e[2], assert(e[4]).end_row
    if row >= srow and row <= erow then
      for name, item in pairs(self.items) do
        if item.mark == id then
          return name, { srow + 1, 0 }
        end
      end
    end
  end

  print('no marks')
end

--- @param inner? boolean
--- @return vim.api.keyset.win_config
local function get_win_config(inner)
  local vpad = inner and 8 or 6
  local hpad = inner and 14 or 10
  local width = math.min(vim.o.columns - hpad * 2, 200)
  local height = math.min(vim.o.lines - vpad * 2, 70)
  return {
    relative = 'editor',
    style = 'minimal',
    width = width,
    border = inner and 'rounded' or nil,
    height = height,
    zindex = 40,
    row = (vim.o.lines - height) / 2,
    col = (vim.o.columns - width) / 2,
  }
end

--- @param inner? boolean
--- @return integer, integer
local function open_win(inner)
  local buf = api.nvim_create_buf(false, true)
  local win = api.nvim_open_win(buf, true, get_win_config(inner))

  api.nvim_create_autocmd('VimResized', {
    desc = 'Resize pckr display when Nvim is resized',
    group = api.nvim_create_augroup('pckr.display', {}),
    callback = function()
      if not api.nvim_win_is_valid(win) then
        return true
      end
      api.nvim_win_set_config(win, get_win_config(inner))
    end,
  })

  if inner then
    vim.wo[win].previewwindow = true
  end

  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].buflisted = false
  vim.bo[buf].swapfile = false
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].modifiable = false

  return buf, win
end

--- @param x string|string[]
--- @return string[]?
local function normalize_lines(x)
  if type(x) == 'string' then
    x = { x }
  end

  local r = {} --- @type string[]
  for _, l in ipairs(x) do
    for _, i in ipairs(vim.split(l, '\n\r?')) do
      r[#r + 1] = i
    end
  end

  return r
end

--- @param buf integer
--- @param l string|string[]
--- @param desc string
--- @param r fun()|string
local function keymap(buf, l, desc, r)
  if type(l) == 'string' then
    l = { l }
  end
  for _, k in ipairs(l) do
    vim.keymap.set('n', k, r, {
      desc = 'Pckr: ' .. desc,
      buffer = buf,
      nowait = true,
      silent = true,
    })
  end
end

--- Update the text of the display buffer
--- @param buf integer
--- @param srow integer
--- @param erow integer
--- @param text string|string[]
local function set_lines(buf, srow, erow, text)
  text = assert(normalize_lines(text))
  vim.bo[buf].modifiable = true
  api.nvim_buf_set_lines(buf, srow, erow, true, text)
  vim.bo[buf].modifiable = false
end

local COMMIT_PAT = [[[0-9a-f]\{7,9}]]
local COMMIT_SINGLE_PAT = string.format([[\<%s\>]], COMMIT_PAT)
local COMMIT_RANGE_PAT = string.format([[\<%s\.\.%s\>]], COMMIT_PAT, COMMIT_PAT)

--- @package
function Display:diff()
  if not next(self.items) then
    log.info('Operations are still running; plugin info is not ready yet')
    return
  end

  local task_name = self:_get_cursor_task()
  if not task_name then
    log.warn('No plugin selected!')
    return
  end

  local plugin = pckr_plugins[task_name]

  if not plugin then
    log.warn('Plugin not available!')
    return
  end

  local current_line = api.nvim_get_current_line()
  local commit = vim.fn.matchstr(current_line, COMMIT_RANGE_PAT)
  if commit == '' then
    commit = vim.fn.matchstr(current_line, COMMIT_SINGLE_PAT)
  end

  if commit == '' then
    log.warn('Unable to find the diff for this line')
    return
  end

  if self.callbacks then
    self.callbacks.diff(
      plugin,
      commit,
      vim.schedule_wrap(function(text, err)
        if err then
          log.fmt_warn('Unable to get diff! %s', err)
          return
        elseif not text then
          log.warn('No diff available')
          return
        end
        local buf = open_win(true)
        set_lines(buf, 0, -1, text)
        api.nvim_buf_set_name(buf, commit)
        keymap(buf, 'q', 'quit', '<cmd>close!<cr>')
        vim.bo[buf].filetype = 'git'
      end)
    )
  end
end

--- @param buf integer
--- @param mark_id integer
--- @return integer, integer
local function get_extmark_region(buf, mark_id)
  local info = api.nvim_buf_get_extmark_by_id(buf, ns, mark_id, { details = true })
  local srow, erow = info[1], assert(info[3]).end_row

  if not erow then
    return srow, srow
  end

  -- TODO(lewis6991): sometimes the end_row will be lower than start_row. Could
  -- be an extmark bug?
  if srow > erow then
    --- @type integer, integer
    srow, erow = erow, srow
  end

  return srow, erow + 1
end

--- @alias Pckr.TaskPos 'top' | 'bottom'

local MAX_COL = 10000

--- @param x string[]
--- @return string[]
local function pad(x)
  local r = {} --- @type string[]
  for i, s in ipairs(x) do
    r[i] = '   ' .. s
  end
  return r
end

--- @param status? 'running' | 'failed' | 'success' | 'done'
--- @return string
local function icon_for_status(status)
  if not status or status == 'done' then
    return SYMBOLS.item
  elseif status == 'running' then
    return SYMBOLS.working
  elseif status == 'failed' then
    return SYMBOLS.error
  else
    return SYMBOLS.done
  end
end

--- @private
--- @param buf integer
--- @param task string
--- @param item Pckr.Display.Item
--- @param static? boolean
--- @param top? boolean
local function render_task(buf, task, item, static, top)
  --- @type [string, string?][][]
  local lines = {
    {
      { (' %s '):format(icon_for_status(item.status)) },
      { ('%s: '):format(task), 'pckrPackageName' },
      item.message and { item.message } or nil,
    },
  }

  if item.info and item.expanded then
    for _, l in ipairs(pad(item.info)) do
      lines[#lines + 1] = { { l } }
    end
  end

  local pos --- @type Pckr.TaskPos?
  if top then
    pos = 'top'
  elseif not static then
    pos = (item.status == 'success' or item.status == 'failed') and 'top' or nil
  end

  -- If pos is given, task will be rendered at the top or bottom of the buffer.
  -- If not given then will use last position, if exists, else bottom.
  if pos or not item.mark then
    -- clear
    if item.mark then
      local old_srow, old_erow = get_extmark_region(buf, item.mark)
      api.nvim_buf_clear_namespace(buf, ns, old_srow, old_erow)
      set_lines(buf, old_srow, old_erow, {})
    end

    local new_row = pos == 'top' and HEADER_LINES or api.nvim_buf_line_count(buf)
    item.mark = api.nvim_buf_set_extmark(buf, ns, new_row, 0, {})
  end

  local srow, erow = get_extmark_region(buf, item.mark)

  local lines0 = {} --- @type string[]
  for _, l in ipairs(lines) do
    local line = {} --- @type string[]
    for _, e in ipairs(l) do
      line[#line + 1] = e[1]
    end
    lines0[#lines0 + 1] = table.concat(line)
  end

  set_lines(buf, srow, erow, lines0)

  -- Apply highlights
  for i, line in ipairs(lines) do
    local offset = 0
    for _, e in ipairs(line) do
      local txt, hl = e[1], e[2]
      local len = #txt

      if hl then
        local row = srow + i - 1
        api.nvim_buf_set_extmark(buf, ns, row, offset, {
          end_row = row,
          end_col = offset + len,
          hl_group = hl,
        })
      end

      offset = offset + len
    end
  end

  -- Apply mark for tracking the task region
  api.nvim_buf_set_extmark(buf, ns, srow, 0, {
    end_row = srow + #lines - 1,
    end_col = MAX_COL,
    strict = false,
    id = item.mark,
  })
end

--- @package
--- Toggle the display of detailed information for a plugin in the final results display
function Display:toggle_info()
  if not next(self.items) then
    log.info('Operations are still running; plugin info is not ready yet')
    return
  end

  local task_name, cursor_pos = self:_get_cursor_task()
  if not task_name or not cursor_pos then
    log.warn('No plugin selected!')
    return
  end

  local item = assert(self.items[task_name])
  item.expanded = not item.expanded
  render_task(self.buf, task_name, item, true)
  api.nvim_win_set_cursor(self.win, cursor_pos)
end

--- Utility function to prompt a user with a question in a floating window
--- @param headline string
--- @param body string[]
--- @param callback fun(boolean)
local function prompt_user(headline, body, callback)
  local buf = api.nvim_create_buf(false, true)
  local longest_line = 0
  for _, line in ipairs(body) do
    local line_length = string.len(line)
    if line_length > longest_line then
      longest_line = line_length
    end
  end

  local width = math.min(longest_line + 2, math.floor(0.9 * vim.o.columns))
  local height = #body + 3
  local x = (vim.o.columns - width) / 2.0
  local y = (vim.o.lines - height) / 2.0
  local pad_width = math.max(math.floor((width - string.len(headline)) / 2.0), 0)
  local lines = vim.list_extend({
    string.rep(' ', pad_width) .. headline .. string.rep(' ', pad_width),
    '',
  }, body)
  api.nvim_buf_set_lines(buf, 0, -1, true, lines)
  vim.bo[buf].modifiable = true

  local win = api.nvim_open_win(buf, false, {
    relative = 'editor',
    width = width,
    height = height,
    col = x,
    row = y,
    focusable = false,
    style = 'minimal',
    noautocmd = true,
  })

  local check = vim.uv.new_prepare()
  local prompted = false
  check:start(vim.schedule_wrap(function()
    if not api.nvim_win_is_valid(win) then
      return
    end
    check:stop()
    if not prompted then
      prompted = true
      local ans = string.lower(vim.fn.input('OK to remove? [y/N] ')) == 'y'
      api.nvim_win_close(win, true)
      callback(ans)
    end
  end))
end

--- Start displaying a new task
--- @param name string
--- @param message string
function Display:task_start(name, message)
  self.items[name] = self.items[name] or {}

  local item = self.items[name]
  item.status = 'running'
  item.message = message

  render_task(self.buf, name, item, nil, true)
end

--- @private
--- Decrement the count of active operations in the headline
function Display:_decrement_headline_count()
  local buf = api.nvim_win_get_buf(self.win)
  local headline = assert(api.nvim_buf_get_lines(buf, 0, 1, false)[1])
  local count_start, count_end = headline:find('%d+')
  if count_start then
    assert(count_end)
    local count = assert(tonumber(headline:sub(count_start, count_end)))
    local updated_headline = string.format(
      '%s%s%s',
      headline:sub(1, count_start - 1),
      count - 1,
      headline:sub(count_end + 1)
    )

    set_lines(self.buf, 0, HEADER_LINES - 1, updated_headline)
  end
end

--- Update a task as having passively completed
--- @param name string
--- @param message string
--- @param info? string|string[]
--- @param success? boolean
function Display:task_done(name, message, info, success)
  self.items[name] = self.items[name] or {}
  local item = self.items[name]

  if success == true then
    item.status = 'success'
    item.expanded = true
  elseif success == false then
    item.status = 'failed'
    item.expanded = true
  else
    item.status = 'done'
    item.expanded = false
  end

  item.message = message
  if info then
    item.info = normalize_lines(info)
  end

  render_task(self.buf, name, item)
  self:_decrement_headline_count()
end

--- @param f fun(p1: string, p2: string): boolean
function Display:task_sort(f)
  local names = vim.tbl_keys(self.items)
  table.sort(names, f)

  for i = #names, 1, -1 do
    local item = assert(self.items[names[i]])
    render_task(self.buf, names[i], item, nil, true)
  end
end

--- Update the status message of a task in progress
--- @param name string
--- @param message string
--- @param info? string[]
function Display:task_update(name, message, info)
  log.fmt_debug('%s: %s', name, message)
  self.items[name] = self.items[name] or {}
  local item = self.items[name]
  item.message = message

  if info then
    item.expanded = true
    item.info = info
  end

  render_task(self.buf, name, item)
end

--- Update the text of the headline message
--- @param message string
function Display:update_headline_message(message)
  --- @type string
  local headline = TITLE .. ' - ' .. message
  local width = api.nvim_win_get_width(self.win) - 2
  local pad_width = math.max(math.floor((width - string.len(headline)) / 2.0), 0)
  set_lines(self.buf, 0, HEADER_LINES - 1, string.rep(' ', pad_width) .. headline)
end

--- Display the final results of an operation
--- @param time number
function Display:finish(time)
  self.running = false
  self:update_headline_message(string.format('finished in %.3fs', time))

  for task_name in pairs(self.items) do
    local plugin = pckr_plugins[task_name]
    if not plugin then
      log.fmt_warn('%s is not in pckr_plugins', task_name)
    elseif plugin.breaking_commits and #plugin.breaking_commits > 0 then
      vim.cmd('syntax match pckrBreakingChange "' .. task_name .. '" containedin=pckrStatusSuccess')
      for _, commit_hash in ipairs(plugin.breaking_commits) do
        log.fmt_warn('Potential breaking change in commit %s of %s', commit_hash, task_name)
        vim.cmd('syntax match pckrBreakingChange "' .. commit_hash .. '" containedin=pckrHash')
      end
    end
  end
end

---@param str string
---@return string
local function look_back(str)
  return string.format([[\(%s\)\@%d<=]], str, #str)
end

local function do_syntax_cmds()
  for _, c in ipairs({
    'syntax clear',
    'syn match pckrWorking /^ ' .. SYMBOLS.working .. '/',
    'syn match pckrSuccess /^ ' .. SYMBOLS.done .. '/',
    'syn match pckrFail /^ ' .. SYMBOLS.error .. '/',
    'syn match pckrStatus /^+.*—\\zs\\s.*$/',
    'syn match pckrStatusSuccess /' .. look_back('^ ' .. SYMBOLS.done) .. '\\s.*$/',
    'syn match pckrStatusFail /' .. look_back('^ ' .. SYMBOLS.error) .. '\\s.*$/',
    'syn match pckrStatusCommit /^\\*.*—\\zs\\s.*$/',
    'syn match pckrHash /\\(\\s\\)[0-9a-f]\\{7,8}\\(\\s\\)/',
    'syn match pckrRelDate /([^)]*)$/',
    'syn match pckrProgress /\\[\\zs[\\=]*/',
    'syn match pckrOutput /\\(Output:\\)\\|\\(Commits:\\)\\|\\(Errors:\\)/',
    'syn match pckrUpdate /update available/',
    [[syn match pckrTimeHigh /\d\{3\}\.\d\+ms/]],
    [[syn match pckrTimeMedium /\d\{2\}\.\d\+ms/]],
    [[syn match pckrTimeLow /\d\.\d\+ms/]],
    [[syn match pckrTimeTrivial /0\.\d\+ms/]],
    [[syn match pckrPackageNotLoaded /(not loaded)$/]],
    [[syn match pckrString /\v(''|""|(['"]).{-}[^\\]\2)/]],
    [[syn match pckrBool /\<\(false\|true\)\>/]],
    -- [[syn match pckrPackageName /^\ • \zs[^ ]*/]],
  }) do
    vim.cmd(c)
  end
end

--- Initialize options, settings, and keymaps for display windows
--- @private
function Display:_setup_win()
  vim.bo[self.buf].filetype = 'pckr'
  api.nvim_buf_set_name(self.buf, '[pckr]')

  keymap(self.buf, 'q', 'quit', function()
    -- Close a display window and signal that any running operations should terminate
    self.running = false
    vim.fn.execute('q!', 'silent')
  end)

  keymap(self.buf, 'd', 'show the diff', function()
    self:diff()
  end)

  keymap(self.buf, { 'za', '<CR>' }, 'show more info', function()
    self:toggle_info()
  end)

  vim.wo[self.win][0].list = false
  vim.wo[self.win][0].wrap = false
  vim.wo[self.win][0].spell = false
  vim.wo[self.win][0].number = false
  vim.wo[self.win][0].relativenumber = false
  vim.wo[self.win][0].foldenable = false
  vim.wo[self.win][0].signcolumn = 'no'

  do_syntax_cmds()

  for _, c in ipairs({
    { 'pckrBool', 'Boolean' },
    { 'pckrBreakingChange', 'WarningMsg' },
    { 'pckrFail', 'ErrorMsg' },
    { 'pckrHash', 'Identifier' },
    { 'pckrOutput', 'Type' },
    { 'pckrUpdate', 'WarningMsg' },
    { 'pckrPackageName', 'Title' },
    { 'pckrPackageNotLoaded', 'Comment' },
    { 'pckrProgress', 'Boolean' },
    { 'pckrRelDate', 'Comment' },
    { 'pckrStatus', 'Type' },
    { 'pckrStatusCommit', 'Constant' },
    { 'pckrStatusFail', 'ErrorMsg' },
    { 'pckrStatusSuccess', 'Constant' },
    { 'pckrString', 'String' },
    { 'pckrSuccess', 'Question' },
    { 'pckrWorking', 'SpecialKey' },
  }) do
    api.nvim_set_hl(0, c[1], { link = c[2], default = true })
  end
end

--- @class Pckr.display
local M = {}

--- Utility function to prompt a user with a question in a floating window
--- @type fun(headline: string, body: string[]): boolean
M.ask_user = awrap(3, prompt_user)

local header_sym = '━'

--- Open a new display window
--- @param cbs? Pckr.Display.Callbacks
--- @return Pckr.Display
function M.open(cbs)
  local obj = setmetatable({}, { __index = Display })
  obj.callbacks = cbs
  obj.running = true
  obj.items = {} --- @type table<string,Pckr.Display.Item?>
  obj.buf, obj.win = open_win()
  obj:_setup_win()

  -- Make header
  local width = api.nvim_win_get_width(obj.win)
  local pad_width = math.floor((width - TITLE:len()) / 2.0)
  set_lines(obj.buf, 0, 1, {
    (' '):rep(pad_width) .. TITLE,
    ' ' .. header_sym:rep(width - 2),
  })

  return obj
end

return M
