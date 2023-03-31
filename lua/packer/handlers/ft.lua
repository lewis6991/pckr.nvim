local util = require('packer.util')

--- @param plugin_path string
--- @return string[]
local function detect_ftdetect(plugin_path)
   local source_paths = {} --- @type string[]
   for _, parts in ipairs({ { 'ftdetect' }, { 'after', 'ftdetect' } }) do
      parts[#parts + 1] = [[**/*.\(vim\|lua\)]]
      local path = util.join_paths(plugin_path, unpack(parts))
      local ok, files = pcall(vim.fn.glob, path, false, true)
      if not ok then
         --- @cast files string
         if string.find(files, 'E77') then
            source_paths[#source_paths + 1] = path
         else
            error(files)
         end
      elseif #files > 0 then
         --- @cast files string[]
         vim.list_extend(source_paths, files)
      end
   end

   return source_paths
end

--- @type table<string,Plugin[]>
local ft_plugins = {}

--- @param plugins table<string,Plugin>
--- @param loader fun(plugins: Plugin[])
return function(plugins, loader)
   local new_fts = {} --- @type string[]
   local ftdetect_paths = {} --- @type string[]
   for _, plugin in pairs(plugins) do
      if plugin.ft then
         for _, ft in ipairs(plugin.ft) do
            if not ft_plugins[ft] then
               ft_plugins[ft] = {}
               new_fts[#new_fts + 1] = ft
            end

            table.insert(ft_plugins[ft], plugin)
         end

         vim.list_extend(ftdetect_paths, detect_ftdetect(plugin.install_path))
      end
   end

   for _, ft in ipairs(new_fts) do
      vim.api.nvim_create_autocmd('FileType', {
         pattern = ft,
         once = true,
         callback = function()
            loader(ft_plugins[ft])
            for _, group in ipairs({ 'filetypeplugin', 'filetypeindent', 'syntaxset' }) do
               vim.api.nvim_exec_autocmds('FileType', { group = group, pattern = ft, modeline = false })
            end
         end,
      })
   end

   if #ftdetect_paths > 0 then
      vim.cmd('augroup filetypedetect')
      for _, path in ipairs(ftdetect_paths) do
         -- 'Sourcing ftdetect script at: ' path, result)
         vim.cmd.source(path)
      end
      vim.cmd('augroup END')
   end

end
