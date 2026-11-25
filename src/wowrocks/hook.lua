local dir = require("luarocks.dir")
local fs = require("luarocks.fs")
local path = require("luarocks.path")
local cfg = require("luarocks.core.cfg")
local util = require("luarocks.util")

local stringify = require("wowrocks.stringify")
local xml = require("wowrocks.xml")
local bootstrap = require("wowrocks.bootstrap")

local hook = {}

local function ensure_fs()
   if not fs.find then
      if not cfg.lua_version then
         cfg.init()
      end
      fs.init()
   end
end

-- LuaRocks 3.8 stores this as "/share/lua/<ver>" (leading slash so the
-- tree root can be concatenated). Later releases use "share/lua/<ver>".
local function normalize_modules_path(lua_modules_path)
   local normalized = lua_modules_path
   if type(normalized) ~= "string" or normalized == "" then
      normalized = "share/lua/" .. (cfg.lua_version or "5.1")
   end
   normalized = normalized:gsub("\\", "/"):gsub("^/+", ""):gsub("/+$", "")
   if normalized == "" then
      normalized = "share/lua/" .. (cfg.lua_version or "5.1")
   end
   return normalized
end

function hook.wow_modules_path(lua_modules_path)
   local normalized = normalize_modules_path(lua_modules_path)
   if normalized:match("^share/") then
      return (normalized:gsub("^share/", "wow/"))
   end
   return "wow/" .. normalized
end

local function read_file(filename)
   local fh, err = io.open(filename, "rb")
   if not fh then
      return nil, err
   end
   local data = fh:read("*a")
   fh:close()
   return data
end

local function write_file(filename, data)
   local fh, err = io.open(filename, "wb")
   if not fh then
      return nil, err
   end
   fh:write(data)
   fh:close()
   return true
end

local function list_lua_files(root)
   if not fs.exists(root) or not fs.is_dir(root) then
      return {}
   end
   local found = fs.find(root)
   local files = {}
   for _, rel in ipairs(found) do
      if rel:match("%.lua$") then
         local full = dir.path(root, rel)
         if fs.is_file(full) then
            files[#files + 1] = rel:gsub("\\", "/")
         end
      end
   end
   table.sort(files)
   return files
end

function hook.refresh(tree_root, lua_modules_path)
   ensure_fs()
   tree_root = fs.absolute_name(dir.normalize(tree_root))
   lua_modules_path = normalize_modules_path(lua_modules_path or cfg.lua_modules_path)

   local share_dir = dir.path(tree_root, lua_modules_path)
   local wow_rel = hook.wow_modules_path(lua_modules_path)
   local wow_dir = dir.path(tree_root, wow_rel)
   local wow_parent = dir.path(tree_root, "wow")

   if fs.exists(wow_parent) then
      fs.delete(wow_parent)
   end

   local lua_files = list_lua_files(share_dir)
   local xml_files = {}

   for _, rel in ipairs(lua_files) do
      local src_path = dir.path(share_dir, rel)
      local source, err = read_file(src_path)
      if not source then
         return nil, "could not read " .. src_path .. ": " .. tostring(err)
      end
      local dest_path = dir.path(wow_dir, rel)
      local dest_dir = dir.dir_name(dest_path)
      local ok, mkdir_err = fs.make_dir(dest_dir)
      if not ok then
         return nil, "could not create " .. dest_dir .. ": " .. tostring(mkdir_err)
      end
      local blob_key = (lua_modules_path .. "/" .. rel):gsub("//", "/")
      local wrapped = stringify.wrap(blob_key, source)
      ok, err = write_file(dest_path, wrapped)
      if not ok then
         return nil, "could not write " .. dest_path .. ": " .. tostring(err)
      end
      xml_files[#xml_files + 1] = (wow_rel .. "/" .. rel):gsub("//", "/")
   end

   local lua_path = dir.path(tree_root, bootstrap.FILENAME)
   local ok, err = write_file(lua_path, bootstrap.source(lua_modules_path))
   if not ok then
      return nil, "could not write " .. lua_path .. ": " .. tostring(err)
   end

   local xml_path = dir.path(tree_root, "WowRocks.xml")
   ok, err = write_file(xml_path, xml.generate(xml_files, bootstrap.FILENAME))
   if not ok then
      return nil, "could not write " .. xml_path .. ": " .. tostring(err)
   end

   util.printout("WowRocks: wrote " .. tostring(#lua_files) .. " sources under " .. wow_rel .. " and " .. bootstrap.FILENAME)
   return true, xml_files
end

function hook.after_tree_change()
   ensure_fs()
   local tree = path.root_dir(cfg.root_dir)
   if not tree then
      return nil, "WowRocks: no rocks tree configured"
   end
   return hook.refresh(tree, cfg.lua_modules_path)
end

return hook
