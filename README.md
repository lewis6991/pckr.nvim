# pckr.nvim

Spiritual successor of https://github.com/wbthomason/packer.nvim

Main differences to packer.nvim:
- Heavily refactored
- Lockfile support
- No compilation

## Table of Contents
1. [Features](#features)
2. [Requirements](#requirements)
3. [Quickstart](#quickstart)
4. [Example](#example)
5. [Commands](#commands)
6. [Usage](#usage)
    1. [The setup and add functions](#the-setup-and-add-function)
    2. [Custom Initialization](#custom-initialization)
    3. [Specifying Plugins](#specifying-plugins)
    4. [Performing plugin management operations](#performing-plugin-management-operations)
7. [Debugging](#debugging)

## Features
- Declarative plugin specification
- Support for dependencies
- Extensible
- Post-install/update hooks
- Support for `git` tags, branches, revisions
- Support for local plugins
- Lockfile support

## Requirements
- **You need to be running Neovim v0.9 or newer**
- If you are on Windows 10, you need developer mode enabled in order to use local plugins (creating
  symbolic links requires admin privileges on Windows - credit to @TimUntersberger for this note)

## Quickstart

If you want to automatically install and set up `pckr.nvim` on any machine you clone your configuration to,
add the following snippet somewhere in your config **before** your first usage of `pckr`:

```lua
local function bootstrap_pckr()
  local pckr_path = vim.fn.stdpath("data") .. "/pckr/pckr.nvim"

  if not (vim.uv or vim.loop).fs_stat(pckr_path) then
    vim.fn.system({
      'git',
      'clone',
      "--filter=blob:none",
      'https://github.com/lewis6991/pckr.nvim',
      pckr_path
    })
  end

  vim.opt.rtp:prepend(pckr_path)
end

bootstrap_pckr()

require('pckr').add{
  -- My plugins here
  -- 'foo1/bar1.nvim';
  -- 'foo2/bar2.nvim';
}
```

## Example
```lua
-- This file can be loaded by calling `lua require('plugins')` from your init.vim

local cmd = require('pckr.loader.cmd')
local keys = require('pckr.loader.keys')

require('pckr').add{
  -- Simple plugins can be specified as strings
  '9mm/vim-closer';

  -- Lazy loading:
  -- Load on a specific command
  {'tpope/vim-dispatch',
    cond = {
      cmd('Dispatch'),
    }
  };

  -- Load on specific keymap
  {'tpope/vim-commentary', cond = keys('n', 'gc') },

  -- Load on specific commands
  -- Also run code after load (see the "config" key)
  { 'w0rp/ale',
    cond = cmd('ALEEnable'),
    config = function()
      vim.cmd[[ALEEnable]]
    end
  };

  -- Local plugins can be included
  '~/projects/personal/hover.nvim';

  -- Plugins can have post-install/update hooks
  {'iamcco/markdown-preview.nvim', run = 'cd app && yarn install', cond = cmd('MarkdownPreview')};

  -- Post-install/update hook with neovim command
  { 'nvim-treesitter/nvim-treesitter', run = ':TSUpdate' };

  -- Post-install/update hook with call of vimscript function with argument
  { 'glacambre/firenvim', run = function()
    vim.fn['firenvim#install'](0)
  end };

  -- Use specific branch, dependency and run lua file after load
  { 'glepnir/galaxyline.nvim',
    branch = 'main',
    requires = {'kyazdani42/nvim-web-devicons'},
    config = function()
      require'statusline'
    end
  };

  -- Run config *before* the plugin is loaded
  {'whatyouhide/vim-lengthmatters', config_pre = function()
    vim.g.lengthmatters_highlight_one_column = 1
    vim.g.lengthmatters_excluded = {'pckr'}
  end},
}
```

## Commands
`pckr` provides the following commands.

```vim
" Remove any disabled or unused plugins
:Pckr clean

" Install missing plugins
:Pckr install [plugin]+

" Update installed plugins
:Pckr update [plugin]+

" Upgrade pckr.nvim
:Pckr upgrade

" Clean, install, update and upgrade
:Pckr sync [plugin]+

" View status of plugins
:Pckr status

" Create a lockfile of plugins with their current commits
:Pckr lock

" Restore plugins using saved lockfile
:Pckr restore
```

## Usage

The following is a more in-depth explanation of `pckr`'s features and use.

### The `setup` and `add` functions
`pckr` provides`pckr.add(spec)`, which is used in the above examples
where `spec` is a table specifying a single or multiple plugins.

### Custom Initialization
`pckr.setup()` can be used to provide custom configuration (note that this is optional).
The default configuration values (and structure of the configuration table) are:

```lua
require('pckr').setup{
  package_root        = util.join_paths(vim.fn.stdpath('data'), 'site', 'pack'),
  max_jobs            = nil, -- Limit the number of simultaneous jobs. nil means no limit
  autoremove          = false, -- Remove unused plugins
  autoinstall         = true, -- Auto install plugins
  git = {
    cmd = 'git', -- The base command for git operations
    clone_timeout = 60, -- Timeout, in seconds, for git clones
    default_url_format = 'https://github.com/%s' -- Lua format string used for "aaa/bbb" style plugins
  },
  log = { level = 'warn' }, -- The default print log level. One of: "trace", "debug", "info", "warn", "error", "fatal".
  opt_dir = ...,
  start_dir = ...,
  lockfile = {
    path = util.join_paths(vim.fn.stdpath('config', 'pckr', 'lockfile.lua'))
  }
}
```

### Specifying plugins

`pckr` is based around declarative specification of plugins.

1. Absolute paths to a local plugin
2. Full URLs (treated as plugins managed with `git`)
3. `username/repo` paths (treated as Github `git` plugins)

Plugin specs can take two forms:

1. A list of plugin specifications (strings or tables)
2. A table specifying a single plugin. It must have a plugin location string as its first element,
   and may additionally have a number of optional keyword elements, shown below:
```lua
{
  'myusername/example',    -- The plugin location string

  -- The following keys are all optional

  -- Specifies a git branch to use
  branch: string?,

  -- Specifies a git tag to use. Supports '*' for "latest tag"
  tag: string?,

  -- Specifies a git commit to use
  commit: string?,

  -- Skip updating this plugin in updates/syncs. Still cleans.
  lock: boolean?,

  -- Post-update/install hook. See "update/install hooks".
  run: string|function,

  -- Specifies plugin dependencies. See "dependencies".
  requires: string|string[],

  -- Specifies code to run after this plugin is loaded. If string then require it.
  -- E.g:
  --   config = function() require('mod') end
  -- is equivalent to:
  --   config = 'mod'
  config: string|function,

  -- Specifies code to run before this plugin is loaded. If string then require it.
  config_pre: string|function,

  cond: function|function[],    -- Specifies custom loader
}
```

#### Update/install hooks

You may specify operations to be run after successful installs/updates of a plugin with the `run`
key. This key may either be a Lua function, which will be called with the `plugin` table for this
plugin (containing the information passed to the spec as well as output from the installation/update
commands, the installation path of the plugin, etc.), a string, or a table of functions and strings.

If an element of `run` is a string, then either:

1. If the first character of `run` is ":", it is treated as a Neovim command and executed.
2. Otherwise, `run` is treated as a shell command and run in the installation directory of the
   plugin via `$SHELL -c '<run>'`.

#### Dependencies

Plugins may specify dependencies via the `requires` key. This key can be a string or a list (table).

If `requires` is a string, it is treated as specifying a single plugin. If a plugin with the name
given in `requires` is already known in the managed set, nothing happens. Otherwise, the string is
treated as a plugin location string and the corresponding plugin is added to the managed set.

If `requires` is a list, it is treated as a list of plugin specifications following the format given
above.

Plugins specified in `requires` are removed when no active plugins require them.

> 🚧 **TODO**: explain that plugins can only be specified as a table once.

#### Custom loader

A custom loader for a plugin may be specified via `cond`.
This is a function which has a function as its first argument.
When this function argument is called, the plugin is loaded.

For example, the following plugin is lazy-loaded on the key mapping `ga`:

```lua
pckr.add{
  {"my/plugin", cond = function(load_plugin)
    vim.keymap.set('n', 'ga', function()
      vim.keymap.del('n', 'ga')
      load_plugin()
      vim.api.nvim_input('ga')
    end)
  end}
}

  -- equivalent to --

local keys = require('pckr.loader.keys')
pckr.add{
  {"my/plugin", cond = keys('n', 'ga') },
}
```

### Automatically find local plugins

This snippet can be used to automatically detect local plugins in a particular directory.

```lua
local local_plugin_dir = vim.env.HOME..'/projects/'

local function resolve(x)
  if type(x) == 'string' and x:sub(1, 1) ~= '/' then
    local name = vim.split(x, '/')[2]
    local loc_install = vim.fs.join_paths(local_plugin_dir, name)
    if name ~= '' and vim.fn.isdirectory(loc_install) == 1 then
      return loc_install
    end
  end
end

local function try_get_local(spec)
  if type(spec) == 'string' then
    return resolve(spec) or spec
  end

  if not spec or type(spec[1]) ~= 'string' then
    return spec
  end

  return resolve(spec[1]) or spec[1]
end

local function walk_spec(spec, field, fn)
  if type(spec[field]) == 'table' then
    for j in ipairs(spec[field]) do
      walk_spec(spec[field], j, fn)
    end
    walk_spec(spec[field], 'requires', fn)
  end
  spec[field] = fn(spec[field])
end

local init {
  'nvim-treesitter/nvim-treesitter'
  -- plugins spec
}

walk_spec({init}, 1, try_get_local)

require('pckr').add(init)
```

## Debugging
`pckr.nvim` logs to `stdpath(cache)/pckr.nvim.log`. Looking at this file is usually a good start
if something isn't working as expected.

