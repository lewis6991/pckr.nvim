local helpers = require('nvim-test.helpers')
local exec_lua = helpers.exec_lua
local eq = helpers.eq

describe('plugin spec formats', function()
  before_each(function()
    helpers.clear()

    -- Make pckr available
    exec_lua[[vim.opt.rtp:append('.')]]
  end)

  it('can process a simple string spec', function()
    eq({
      ['gitsigns.nvim'] = {
        install_path = '/gitsigns.nvim',
        installed = false,
        name = 'gitsigns.nvim',
        revs = { },
        simple = true,
        type = 'git',
        url = 'https://github.com/lewis6991/gitsigns.nvim'
      } }, exec_lua[[
        return require('pckr.plugin').process_spec { 'lewis6991/gitsigns.nvim' }
    ]])
  end)

  it('can process a simple table spec', function()
    exec_lua[[
      require('pckr.plugin').process_spec {
      }
    ]]
    eq({
      ['gitsigns.nvim'] = {
        install_path = '/gitsigns.nvim',
        installed = false,
        name = 'gitsigns.nvim',
        revs = { },
        simple = false,
        tag = 'v0.7',
        type = 'git',
        url = 'https://github.com/lewis6991/gitsigns.nvim'
      } }, exec_lua[[
        return require('pckr.plugin').process_spec {
          { 'lewis6991/gitsigns.nvim', tag = "v0.7" }
        }
    ]])
  end)

  it('can setup', function()
    exec_lua[[
      require('pckr').setup{
        max_jobs = 30,
      }
    ]]
  end)

  it('can add plugins', function()
    exec_lua[[
      require('pckr').add{
        'lewis6991/gitsigns/nvim'
      }
    ]]
  end)

end)
