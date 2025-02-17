local helpers = require('nvim-test.helpers')
local exec_lua = helpers.exec_lua
local eq = helpers.eq
local uv = vim.uv or vim.loop

--- @param path string
local function wait_for_file(path)
  local i = 0
  while i < 100 and not uv.fs_stat(path) do
    i = i + 1
    helpers.sleep(10)
  end
  if i == 100 then
    error('timeout waiting for ' .. path, 2)
  end
end

--- @param path string
--- @param text string|string[]
local function write_file(path, text)
  local f = assert(io.open(path, 'w'))
  if type(text) == 'string' then
    text = { text }
  end

  for _, line in ipairs(text) do
    f:write(line)
    f:write('\n')
  end
  f:close()
end

describe('pckr actions', function()
  local tmpdir --- @type string

  setup(function()
    helpers.clear()

    tmpdir = uv.cwd() .. '/scratch/pckr'
    -- tmpdir = assert(uv.os_tmpdir()) .. '/pckr'
    helpers.fn.system({ 'rm', '-rf', tmpdir })
    helpers.fn.system({ 'mkdir', '-p', tmpdir })
  end)

  it('can install local plugins', function()
    -- Fixes #50 where 'run' was being called before plugin/* was loaded

    local foo_plugin_dir = tmpdir .. '/foo_plugin'

    helpers.fn.system({ 'mkdir', foo_plugin_dir })
    helpers.fn.system({ 'mkdir', foo_plugin_dir .. '/plugin' })

    write_file(foo_plugin_dir .. '/plugin/foo.lua', {
      '_G.loaded_plugin_foo = true',
    })

    local init_lua = tmpdir .. '/init.lua'
    write_file(
      init_lua,
      string.format(
        [[
      -- Make pckr available
      vim.opt.rtp:append('.')

      local pckr = require('pckr')
      pckr.setup({
        pack_dir = '%s'
      })
      pckr.add({
        {
          '%s',
          run = function()
            _G.did_run_pre = true
            assert(_G.loaded_plugin_foo)
            _G.did_run_post = true
          end,
        }
      })
    ]],
        tmpdir,
        foo_plugin_dir
      )
    )

    helpers.clear(init_lua)

    wait_for_file(tmpdir .. '/pack/pckr/opt/foo_plugin')

    local install_dir = tmpdir .. '/pack/pckr/opt/foo_plugin'

    eq('link', uv.fs_lstat(install_dir).type)
    eq('file', uv.fs_stat(install_dir .. '/plugin/foo.lua').type)

    eq(true, exec_lua([[return _G.did_run_pre]]))
    eq(true, exec_lua([[return _G.did_run_post]]))
  end)
end)
