local api = vim.api
local log = require('pckr.log')
local config = require('pckr.config')
local awrap = require('pckr.async').wrap
local pckr_plugins = require('pckr.plugin').plugins

local ns = api.nvim_create_namespace('pckr_display')

local HEADER_LINES = 2

local TITLE = 'pckr.nvim'

--- @alias Pckr.Display.Status
--- | 'running'
--- | 'failed'
--- | 'success'
--- | 'done'

--- @class Pckr.Display.Item
--- @field status Pckr.Display.Status
--- @field message string
--- @field info string[]? Additional info that can be collapsed
--- @field expanded boolean Whether info is being displayed
--- @field mark integer Extmark used track the location of the item in the buffer
--- @field nameMark integer Extmark used track the location of the item in the buffer

--- @class Pckr.Display.Callbacks
--- @field diff        fun(plugin: Pckr.Plugin, commit: string, callback: function)
--- @field revert_last fun(plugin: Pckr.Plugin)

--- @class Pckr.Display
--- @field interactive boolean
--- @field buf?        integer
--- @field win?        integer
--- @field items       table<string,Pckr.Display.Item>
--- @field running     boolean
--- @field callbacks?  Pckr.Display.Callbacks
local Display = {}

--- @param disp Pckr.Display
--- @return string?, {[1]:integer, [2]:integer}?
local function get_plugin(disp)
  local row = unpack(api.nvim_win_get_cursor(0)) - 1
  -- TODO(lewis6991): Another extmark bug(?):
  --       nvim_buf_get_extmarks(0, ns, row-1, row+1, {})
  -- does not return all the extmarks that the following would:
  --       nvim_buf_get_extmarks(0, ns, {row, 0}, {row,-1}, {})
  for _, e in ipairs(api.nvim_buf_get_extmarks(0, ns, 0, -1, { details = true })) do
    --- @type integer, integer, integer
    local id, srow, erow = e[1], e[2], e[4].end_row
    if row >= srow and row <= erow then
      for name, item in pairs(disp.items) do
        if item.mark == id then
          return name, { srow + 1, 0 }
        end
      end
    end
  end

  print('no marks')
end

--- @param inner? boolean
--- @return integer, integer
local function open_win(inner)
  local vpad = inner and 8 or 6
  local hpad = inner and 14 or 10
  local width = math.min(vim.o.columns - hpad * 2, 200)
  local height = math.min(vim.o.lines - vpad * 2, 70)
  local buf = api.nvim_create_buf(false, true)
  local win = api.nvim_open_win(buf, true, {
    relative = 'editor',
    style = 'minimal',
    width = width,
    border = inner and 'rounded' or nil,
    height = height,
    noautocmd = true,
    row = (vim.o.lines - height) / 2,
    col = (vim.o.columns - width) / 2,
  })

  if inner then
    vim.wo[win].previewwindow = true
  end
  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].buflisted = false
  vim.bo[buf].swapfile = false
  vim.bo[buf].bufhidden = 'wipe'

  if not vim.g.colors_name then
    -- default colorscheme; make NormalFloat palatable
    vim.wo[win].winhighlight = 'NormalFloat:Normal'
  end

  return buf, win
end

local COMMIT_PAT = [[[0-9a-f]\{7,9}]]
local COMMIT_SINGLE_PAT = string.format([[\<%s\>]], COMMIT_PAT)
local COMMIT_RANGE_PAT = string.format([[\<%s\.\.%s\>]], COMMIT_PAT, COMMIT_PAT)

--- @param disp Pckr.Display
local function diff(disp)
  if not disp.buf then
    return
  end

  if next(disp.items) == nil then
    log.info('Operations are still running; plugin info is not ready yet')
    return
  end

  local plugin_name = get_plugin(disp)
  if plugin_name == nil then
    log.warn('No plugin selected!')
    return
  end

  local plugin = pckr_plugins[plugin_name]

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

  disp.callbacks.diff(plugin, commit, function(lines, err)
    if err then
      log.warn('Unable to get diff!')
      return
    end
    vim.schedule(function()
      if not lines or #lines < 1 then
        log.warn('No diff available')
        return
      end
      local buf = open_win(true)
      api.nvim_buf_set_lines(buf, 0, -1, false, lines)
      api.nvim_buf_set_name(buf, commit)
      vim.keymap.set('n', 'q', '<cmd>close!<cr>', { buffer = buf, silent = true, nowait = true })
      vim.bo[buf].filetype = 'git'
    end)
  end)
end

--- Update the text of the display buffer
--- @param buf? integer
--- @param srow integer
--- @param erow integer
--- @param lines string[]
local function set_lines(buf, srow, erow, lines)
  if not buf then
    return
  end
  vim.bo[buf].modifiable = true
  api.nvim_buf_set_lines(buf, srow, erow, true, lines)
  vim.bo[buf].modifiable = false
end

--- @param self Pckr.Display
--- @param plugin string
--- @return integer?, integer?
local function get_task_region(self, plugin)
  local mark = self.items[plugin].mark

  if not mark then
    return
  end

  local info = api.nvim_buf_get_extmark_by_id(self.buf, ns, mark, { details = true })

  --- @type integer, integer?
  local srow, erow = info[1], info[3].end_row

  if not erow then
    return srow, srow
  end

  -- TODO(lewis6991): sometimes the end_row will be lower than start_row. Could
  -- be an extmark bug?
  if srow > erow then
    srow, erow = erow, srow
  end

  return srow, erow + 1
end

--- @param self Pckr.Display
--- @param plugin string
local function clear_task(self, plugin)
  if not self.buf then
    return
  end
  local srow, erow = assert(get_task_region(self, plugin))
  set_lines(self.buf, srow, erow, {})
  local item = self.items[plugin]
  api.nvim_buf_del_extmark(self.buf, ns, item.mark)
  item.mark = nil
  api.nvim_buf_del_extmark(self.buf, ns, item.nameMark)
  item.nameMark = nil
end

--- @alias Pckr.TaskPos 'top' | 'bottom'

local MAX_COL = 10000

--- @param self Pckr.Display
--- @param plugin string
--- @param message {[1]: string, [2]:string?}[][]
--- @param pos? Pckr.TaskPos
local function update_task_lines(self, plugin, message, pos)
  local item = self.items[plugin]

  -- If pos is given, task will be rendered at the top or bottom of the buffer.
  -- If not given then will use last position, if exists, else bottom.
  if pos ~= nil or not item.mark then
    if item.mark then
      clear_task(self, plugin)
    end

    local new_row = pos == 'top' and HEADER_LINES or api.nvim_buf_line_count(self.buf)
    item.mark = api.nvim_buf_set_extmark(self.buf, ns, new_row, 0, {})
  end

  local srow, erow = assert(get_task_region(self, plugin))

  local lines = {} --- @type string[]
  for _, l in ipairs(message) do
    local line = {} --- @type string[]
    for _, e in ipairs(l) do
      line[#line + 1] = e[1]
    end
    lines[#lines + 1] = table.concat(line)
  end

  set_lines(self.buf, srow, erow, lines)

  for i, l in ipairs(message) do
    local offset = 0
    for _, e in ipairs(l) do
      local len = #e[1]
      local row = srow + i - 1
      if e[2] then
        item.nameMark = api.nvim_buf_set_extmark(self.buf, ns, row, offset, {
          end_row = row,
          end_col = offset + len,
          hl_group = e[2],
          id = item.nameMark,
        })
      end

      offset = offset + len
    end
  end

  api.nvim_buf_set_extmark(self.buf, ns, srow, 0, {
    end_row = srow + #message - 1,
    end_col = MAX_COL,
    strict = false,
    id = item.mark,
  })
end

--- @param x string[]
--- @return string[]
local function pad(x)
  local r = {} --- @type string[]
  for i, s in ipairs(x) do
    r[i] = '   ' .. s
  end
  return r
end

--- @param self Pckr.Display
--- @param plugin string
--- @param static? boolean
--- @param top? boolean
local function render_task(self, plugin, static, top)
  local item = self.items[plugin]

  local icon --- @type string
  if not item.status or item.status == 'done' then
    icon = config.display.item_sym
  elseif item.status == 'running' then
    icon = config.display.working_sym
  elseif item.status == 'failed' then
    icon = config.display.error_sym
  else
    icon = config.display.done_sym
  end

  --- @type {[1]: string, [2]:string?}[][]
  local lines = {
    {
      { string.format(' %s ', icon) },
      { string.format('%s: ', plugin), 'pckrPackageName' },
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

  update_task_lines(self, plugin, lines, pos)
end

--- Toggle the display of detailed information for a plugin in the final results display
--- @param disp Pckr.Display
local function toggle_info(disp)
  if not disp.buf then
    return
  end

  if disp.items == nil or next(disp.items) == nil then
    log.info('Operations are still running; plugin info is not ready yet')
    return
  end

  local plugin_name, cursor_pos = get_plugin(disp)
  if plugin_name == nil or cursor_pos == nil then
    log.warn('No plugin selected!')
    return
  end

  local item = disp.items[plugin_name]
  item.expanded = not item.expanded
  render_task(disp, plugin_name, true)
  api.nvim_win_set_cursor(disp.win, cursor_pos)
end

--- Utility function to prompt a user with a question in a floating window
--- @param headline string
--- @param body string[]
--- @param callback fun(boolean)
local function prompt_user(headline, body, callback)
  if config.display.non_interactive then
    callback(true)
    return
  end

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
    border = config.display.prompt_border,
    noautocmd = true,
  })

  local check = vim.loop.new_prepare()
  assert(check)
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

--- Prompt a user to revert the latest update for a plugin
--- @param disp Pckr.Display
local function prompt_revert(disp)
  if not disp.buf then
    return
  end
  if next(disp.items) == nil then
    log.info('Operations are still running; plugin info is not ready yet')
    return
  end

  local plugin_name = get_plugin(disp)
  if plugin_name == nil then
    log.warn('No plugin selected!')
    return
  end

  local plugin = pckr_plugins[plugin_name]
  local actual_update = plugin.revs[1] ~= plugin.revs[2]
  if actual_update then
    prompt_user('Revert update for ' .. plugin_name .. '?', {
      'Do you want to revert '
        .. plugin_name
        .. ' from '
        .. plugin.revs[2]
        .. ' to '
        .. plugin.revs[1]
        .. '?',
    }, function(ans)
      if ans then
        disp.callbacks.revert_last(plugin)
      end
    end)
  else
    log.fmt_warn("%s wasn't updated; can't revert!", plugin_name)
  end
end

local in_headless = #api.nvim_list_uis() == 0

--- @type Pckr.Display
local display = setmetatable({}, { __index = Display })

display.interactive = not config.display.non_interactive and not in_headless

--- @class Keymap
--- @field action string
--- @field lhs string|string[]
--- @field rhs fun()

--- @type table<string,Keymap>
local keymaps = {
  quit = {
    action = 'quit',
    rhs = function()
      -- Close a display window and signal that any running operations should terminate
      display.running = false
      vim.fn.execute('q!', 'silent')
    end,
  },

  diff = {
    action = 'show the diff',
    rhs = function()
      diff(display)
    end,
  },

  toggle_info = {
    action = 'show more info',
    rhs = function()
      toggle_info(display)
    end,
  },

  prompt_revert = {
    action = 'revert an update',
    rhs = function()
      prompt_revert(display)
    end,
  },
}

function Display:check()
  return not self.running
end

--- Start displaying a new task
--- @param self Pckr.Display
--- @param plugin string
--- @param message string
Display.task_start = vim.schedule_wrap(function(self, plugin, message)
  if not self.buf then
    return
  end

  local item = self.items[plugin]
  item.status = 'running'
  item.message = message

  render_task(self, plugin, nil, true)
end)

--- Decrement the count of active operations in the headline
--- @param disp Pckr.Display
local function decrement_headline_count(disp)
  if not disp.buf then
    return
  end
  local headline = api.nvim_buf_get_lines(disp.buf, 0, 1, false)[1]
  local count_start, count_end = headline:find('%d+')
  if count_start then
    local count = tonumber(headline:sub(count_start, count_end))
    local updated_headline = string.format(
      '%s%s%s',
      headline:sub(1, count_start - 1),
      count - 1,
      headline:sub(count_end + 1)
    )

    set_lines(disp.buf, 0, HEADER_LINES - 1, { updated_headline })
  end
end

--- @param x string[]?
--- @return string[]?
local function normalize_lines(x)
  if not x then
    return
  end
  local r = {} --- @type string[]
  for _, l in ipairs(x) do
    for _, i in ipairs(vim.split(l, '\n\r?')) do
      r[#r + 1] = i
    end
  end
  return r
end

--- @param self Pckr.Display
--- @param plugin string
--- @param message string
--- @param info? string[]
--- @param success? boolean
local task_done = vim.schedule_wrap(function(self, plugin, message, info, success)
  if not self.buf then
    return
  end

  local item = self.items[plugin]

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
  item.info = normalize_lines(info)

  render_task(self, plugin)
  decrement_headline_count(self)
end)

--- @param f fun(p1: string, p2: string): boolean
function Display:task_sort(f)
  if not self.buf then
    return
  end

  local names = vim.tbl_keys(self.items)
  table.sort(names, f)

  for i = #names, 1, -1 do
    render_task(self, names[i], nil, true)
  end
end

--- Update a task as having passively completed
--- @param plugin string
--- @param message string
--- @param info? string[]
function Display:task_done(plugin, message, info)
  task_done(self, plugin, message, info, nil)
end

--- Update a task as having successfully completed
--- @param plugin string
--- @param message string
--- @param info? string[]
function Display:task_succeeded(plugin, message, info)
  task_done(self, plugin, message, info, true)
end

--- Update a task as having unsuccessfully failed
--- @param plugin string
--- @param message string
--- @param info? string[]
function Display:task_failed(plugin, message, info)
  task_done(self, plugin, message, info, false)
end

--- Update the status message of a task in progress
--- @param self Pckr.Display
--- @param plugin string
--- @param message string
--- @param info? string[]
Display.task_update = vim.schedule_wrap(function(self, plugin, message, info)
  log.fmt_debug('%s: %s', plugin, message)
  if not self.buf then
    return
  end

  local item = self.items[plugin]
  item.message = message

  if info then
    item.expanded = true
    item.info = info
  end

  render_task(self, plugin)
end)

--- Update the text of the headline message
--- @param self Pckr.Display
--- @param message string
Display.update_headline_message = vim.schedule_wrap(function(self, message)
  if not self.buf then
    return
  end
  --- @type string
  local headline = TITLE .. ' - ' .. message
  local width = api.nvim_win_get_width(self.win) - 2
  local pad_width = math.max(math.floor((width - string.len(headline)) / 2.0), 0)
  set_lines(self.buf, 0, HEADER_LINES - 1, { string.rep(' ', pad_width) .. headline })
end)

--- Display the final results of an operation
--- @param self Pckr.Display
--- @param time number
Display.finish = vim.schedule_wrap(function(self, time)
  if not self.buf then
    return
  end

  display.running = false
  self:update_headline_message(string.format('finished in %.3fs', time))

  for plugin_name, _ in pairs(self.items) do
    local plugin = pckr_plugins[plugin_name]
    if not plugin then
      log.fmt_warn('%s is not in pckr_plugins', plugin_name)
    elseif plugin.breaking_commits and #plugin.breaking_commits > 0 then
      vim.cmd(
        'syntax match pckrBreakingChange "' .. plugin_name .. '" containedin=pckrStatusSuccess'
      )
      for _, commit_hash in ipairs(plugin.breaking_commits) do
        log.fmt_warn('Potential breaking change in commit %s of %s', commit_hash, plugin_name)
        vim.cmd('syntax match pckrBreakingChange "' .. commit_hash .. '" containedin=pckrHash')
      end
    end
  end
end)

---@param str string
---@return string
local function look_back(str)
  return string.format([[\(%s\)\@%d<=]], str, #str)
end

-- TODO: Option for no colors
---@param working_sym string
---@param done_sym string
---@param error_sym string
local function do_syntax_cmds(working_sym, done_sym, error_sym)
  for _, c in ipairs({
    'syntax clear',
    'syn match pckrWorking /^ ' .. working_sym .. '/',
    'syn match pckrSuccess /^ ' .. done_sym .. '/',
    'syn match pckrFail /^ ' .. error_sym .. '/',
    'syn match pckrStatus /^+.*—\\zs\\s.*$/',
    'syn match pckrStatusSuccess /' .. look_back('^ ' .. done_sym) .. '\\s.*$/',
    'syn match pckrStatusFail /' .. look_back('^ ' .. error_sym) .. '\\s.*$/',
    'syn match pckrStatusCommit /^\\*.*—\\zs\\s.*$/',
    'syn match pckrHash /\\(\\s\\)[0-9a-f]\\{7,8}\\(\\s\\)/',
    'syn match pckrRelDate /([^)]*)$/',
    'syn match pckrProgress /\\[\\zs[\\=]*/',
    'syn match pckrOutput /\\(Output:\\)\\|\\(Commits:\\)\\|\\(Errors:\\)/',
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

local function set_config_keymaps()
  local dcfg = config.display
  for name, lhs in pairs(dcfg.keybindings or {}) do
    if keymaps[name] then
      keymaps[name].lhs = lhs
    end
  end
end

--- Utility to make the initial display buffer header
--- @param disp Pckr.Display
local function make_header(disp)
  local width = api.nvim_win_get_width(0)
  local pad_width = math.floor((width - TITLE:len()) / 2.0)
  set_lines(disp.buf, 0, 1, {
    (' '):rep(pad_width) .. TITLE,
    ' ' .. config.display.header_sym:rep(width - 2),
  })
end

--- Initialize options, settings, and keymaps for display windows
--- @param bufnr integer
--- @param winid integer
local function setup_display(bufnr, winid)
  vim.bo[bufnr].filetype = 'pckr'
  api.nvim_buf_set_name(bufnr, '[pckr]')
  set_config_keymaps()
  for _, m in pairs(keymaps) do
    local lhs = m.lhs
    if type(lhs) == 'string' then
      lhs = { lhs }
    end
    lhs = lhs
    for _, x in ipairs(lhs) do
      vim.keymap.set('n', x, m.rhs, {
        --- @type string
        desc = 'Pckr: ' .. m.action,
        buffer = bufnr,
        nowait = true,
        silent = true,
      })
    end
  end

  local function set_winlocal_option(option, value)
    api.nvim_set_option_value(option, value, { win = winid, scope = 'local' })
  end

  set_winlocal_option('list', false)
  set_winlocal_option('wrap', false)
  set_winlocal_option('spell', false)
  set_winlocal_option('number', false)
  set_winlocal_option('relativenumber', false)
  set_winlocal_option('foldenable', false)
  set_winlocal_option('signcolumn', 'no')

  do_syntax_cmds(config.display.working_sym, config.display.done_sym, config.display.error_sym)

  for _, c in ipairs({
    { 'pckrBool', 'Boolean' },
    { 'pckrBreakingChange', 'WarningMsg' },
    { 'pckrFail', 'ErrorMsg' },
    { 'pckrHash', 'Identifier' },
    { 'pckrOutput', 'Type' },
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

local M = {}

--- Utility function to prompt a user with a question in a floating window
--- @type fun(headline: string, body: string[]): boolean
M.ask_user = awrap(prompt_user, 3)

--- Open a new display window
--- @param cbs? Pckr.Display.Callbacks
--- @return Pckr.Display
function M.open(cbs)
  if display.interactive and not (display.win and api.nvim_win_is_valid(display.win)) then
    display.buf, display.win = open_win()
    setup_display(display.buf, display.win)
  end

  display.callbacks = cbs
  display.running = true

  display.items = setmetatable({}, {
    --- @param t table<string,Pckr.Display.Item>
    --- @param k string
    --- @return Pckr.Display.Item
    __index = function(t, k)
      t[k] = { expanded = false }
      return t[k]
    end,
  })

  set_lines(display.buf, 0, -1, {})
  make_header(display)

  return display
end

return M
