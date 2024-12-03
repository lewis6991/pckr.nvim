local helpers = require('nvim-test.helpers')
local exec_lua = helpers.exec_lua
local eq = helpers.eq

describe('plugin spec formats', function()
  before_each(function()
    helpers.clear()

    -- Make pckr available
    exec_lua([[vim.opt.rtp:append('.')]])
  end)

  it('can process a simple string spec', function()
    eq(
      {
        ['gitsigns.nvim'] = {
          install_path = '/gitsigns.nvim',
          installed = false,
          name = 'gitsigns.nvim',
          revs = {},
          simple = true,
          type = 'git',
          url = 'https://github.com/lewis6991/gitsigns.nvim',
          _dep_only = false,
        },
      },
      exec_lua([[
        require('pckr.plugin').process_spec { 'lewis6991/gitsigns.nvim' }
        return require('pckr.plugin').plugins_by_name
    ]])
    )
  end)

  it('can process a simple table spec', function()
    exec_lua([[
      require('pckr.plugin').process_spec {
      }
    ]])
    eq(
      {
        ['gitsigns.nvim'] = {
          install_path = '/gitsigns.nvim',
          installed = false,
          name = 'gitsigns.nvim',
          revs = {},
          simple = false,
          tag = 'v0.7',
          type = 'git',
          url = 'https://github.com/lewis6991/gitsigns.nvim',
          _dep_only = false,
        },
      },
      exec_lua([[
        require('pckr.plugin').process_spec {
          { 'lewis6991/gitsigns.nvim', tag = "v0.7" }
        }
        return require('pckr.plugin').plugins_by_name
    ]])
    )
  end)

  it('sets dep_only correctly', function()
    local plugin1 = {
      install_path = '/plugin1',
      installed = false,
      name = 'plugin1',
      revs = {},
      simple = false,
      type = 'git',
      url = 'https://github.com/plugin1',
      requires = { 'plugin2' },
      _dep_only = false,
    }
    eq(
      {
        ['plugin1'] = plugin1,
        ['plugin2'] = {
          install_path = '/plugin2',
          installed = false,
          name = 'plugin2',
          revs = {},
          simple = true,
          required_by = { plugin1 },
          type = 'git',
          url = 'https://github.com/plugin2',
          _dep_only = true,
        },
      },
      exec_lua([[
        require('pckr.plugin').process_spec {
          {'plugin1', requires = 'plugin2'}
        }
        return require('pckr.plugin').plugins_by_name
    ]])
    )

    eq(
      {
        ['plugin1'] = plugin1,
        ['plugin2'] = {
          install_path = '/plugin2',
          installed = false,
          name = 'plugin2',
          revs = {},
          simple = true,
          required_by = { plugin1 },
          type = 'git',
          url = 'https://github.com/plugin2',
          _dep_only = false,
        },
      },
      exec_lua([[
        require('pckr.plugin').process_spec {
          {'plugin1', requires = 'plugin2'},
          'plugin2',
        }
        return require('pckr.plugin').plugins_by_name
    ]])
    )
  end)

  it('can setup', function()
    exec_lua([[
      require('pckr').setup{
        max_jobs = 30,
      }
    ]])
  end)

  it('can add plugins', function()
    exec_lua([[
      require('pckr').add{
        'lewis6991/gitsigns/nvim'
      }
    ]])
  end)
end)
