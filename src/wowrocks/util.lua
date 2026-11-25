local dir = require("luarocks.dir")
local fs = require("luarocks.fs")

local util = {}

function util.read_file(filename)
   local fh, err = io.open(filename, "rb")
   if not fh then
      return nil, err
   end
   local data = fh:read("*a")
   fh:close()
   return data
end

function util.write_file(filename, data)
   local parent = dir.dir_name(filename)
   if parent ~= "" then
      local ok, err = fs.make_dir(parent)
      if not ok then
         return nil, err
      end
   end
   local fh, err = io.open(filename, "wb")
   if not fh then
      return nil, err
   end
   fh:write(data)
   fh:close()
   return true
end

function util.list_files(pattern)
   local files = {}
   for _, name in ipairs(fs.list_dir(".")) do
      if name:match(pattern) and fs.is_file(name) then
         files[#files + 1] = name
      end
   end
   table.sort(files)
   return files
end

function util.dep_name(dep)
   local name = dep and dep:match("^%s*([a-zA-Z0-9][a-zA-Z0-9%.%-%_]*)")
   if not name then
      return nil
   end
   return name:lower()
end

function util.rock_name(name)
   local n = name:lower():gsub("%s+", "-"):gsub("[^a-z0-9%.%-%_]", "")
   if n == "" then
      n = "addon"
   end
   if not n:match("^[a-z0-9]") then
      n = "a" .. n
   end
   return n
end

function util.has_line(text, wanted)
   for line in (text or ""):gmatch("[^\r\n]+") do
      if line == wanted then
         return true
      end
   end
   return false
end

function util.append_line(filename, line)
   local data = ""
   if fs.exists(filename) then
      local existing, err = util.read_file(filename)
      if not existing then
         return nil, err
      end
      if util.has_line(existing, line) then
         return false
      end
      data = existing
      if #data > 0 and not data:match("\n$") then
         data = data .. "\n"
      end
   end
   return util.write_file(filename, data .. line .. "\n")
end

function util.sorted_keys(tbl)
   local keys = {}
   for key in pairs(tbl) do
      keys[#keys + 1] = key
   end
   table.sort(keys)
   return keys
end

return util
