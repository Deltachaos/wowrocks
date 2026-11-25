local dir = require("luarocks.dir")
local fs = require("luarocks.fs")
local files = require("wowrocks.util")

local toc = {}

toc.INTERFACE = "120100"
toc.TREE = "Libs/WoWRocks"
toc.XML_INCLUDE = "Libs/WoWRocks/WowRocks.xml"

local FLAVOR_SUFFIXES = {
   "_Mainline",
   "_Vanilla",
   "_Classic",
   "_TBC",
   "_BCC",
   "_Wrath",
   "_Cata",
   "_Mists",
}

local function has_flavor_suffix(stem)
   for _, suffix in ipairs(FLAVOR_SUFFIXES) do
      if stem:sub(-#suffix) == suffix then
         return true, stem:sub(1, #stem - #suffix)
      end
   end
   return false, stem
end

function toc.stem(filename)
   local stem = filename:gsub("%.toc$", "")
   local _, base = has_flavor_suffix(stem)
   return base
end

function toc.list()
   return files.list_files("%.toc$")
end

function toc.main_stem(dir_name, tocs)
   tocs = tocs or toc.list()
   if #tocs == 0 then
      return nil
   end
   local exact = dir_name .. ".toc"
   for _, name in ipairs(tocs) do
      if name == exact then
         return dir_name
      end
   end
   for _, name in ipairs(tocs) do
      if toc.stem(name) == dir_name then
         return dir_name
      end
   end
   for _, name in ipairs(tocs) do
      local stem = name:gsub("%.toc$", "")
      if not has_flavor_suffix(stem) then
         return stem
      end
   end
   return toc.stem(tocs[1])
end

function toc.parse(content)
   local info = {
      headers = {},
      files = {},
   }
   for line in (content or ""):gmatch("[^\r\n]+") do
      local key, value = line:match("^##%s*([^:]+):%s*(.-)%s*$")
      if key then
         info.headers[key:lower():gsub("%s+$", "")] = value
      else
         local file = toc.file_line(line)
         if file then
            info.files[#info.files + 1] = file
         end
      end
   end
   info.title = info.headers.title
   info.notes = info.headers.notes
   info.author = info.headers.author
   return info
end

function toc.parse_file(path)
   local data, err = files.read_file(path)
   if not data then
      return nil, err
   end
   return toc.parse(data)
end

function toc.file_line(line)
   line = line:match("^%s*(.-)%s*$") or ""
   if line == "" or line:match("^#") then
      return nil
   end
   local file = line:match("^([^%[]+)") or line
   file = file:gsub("%s+$", ""):gsub("\\", "/")
   if file == "" then
      return nil
   end
   return file
end

function toc.has_xml_include(content)
   local wanted = toc.XML_INCLUDE:lower()
   for line in (content or ""):gmatch("[^\r\n]+") do
      local file = toc.file_line(line)
      if file and file:lower() == wanted then
         return true
      end
   end
   return false
end

function toc.generate(opts)
   opts = opts or {}
   local title = opts.title or "Addon"
   local lines = {
      "## Interface: " .. toc.INTERFACE,
      "## Title: " .. title,
      "## Notes: " .. (opts.notes or title),
      "## Version: scm",
      "",
      toc.XML_INCLUDE,
   }
   for _, name in ipairs(opts.files or {}) do
      if toc.file_line(name) and name:gsub("\\", "/"):lower() ~= toc.XML_INCLUDE:lower() then
         lines[#lines + 1] = name
      end
   end
   return table.concat(lines, "\n") .. "\n"
end

function toc.list_addon_files()
   local names = {}
   for _, name in ipairs(fs.list_dir(".")) do
      if fs.is_file(name) and (name:match("%.lua$") or name:match("%.xml$")) then
         names[#names + 1] = name
      end
   end
   table.sort(names)
   return names
end

local function split_lines(content)
   local lines = {}
   local pos = 1
   while pos <= #content do
      local s, e = content:find("\r?\n", pos)
      if not s then
         lines[#lines + 1] = content:sub(pos)
         break
      end
      lines[#lines + 1] = content:sub(pos, s - 1)
      pos = e + 1
   end
   return lines, content:find("\r\n", 1, true) and "\r\n" or "\n", content:match("\r?\n$") ~= nil
end

function toc.insert_xml_include(content)
   if toc.has_xml_include(content) then
      return nil
   end
   local lines, nl, ended_with_nl = split_lines(content)
   local insert_at = #lines + 1
   for i, line in ipairs(lines) do
      if toc.file_line(line) then
         insert_at = i
         break
      end
   end
   table.insert(lines, insert_at, toc.XML_INCLUDE)
   local out = table.concat(lines, nl)
   if ended_with_nl or #content == 0 then
      out = out .. nl
   end
   return out
end

function toc.ensure_autoload(path)
   local data, err = files.read_file(path)
   if not data then
      return nil, err
   end
   local updated = toc.insert_xml_include(data)
   if not updated then
      return false
   end
   local ok, write_err = files.write_file(path, updated)
   if not ok then
      return nil, write_err
   end
   return true
end

function toc.ensure_all(optional)
   local tocs = toc.list()
   if #tocs == 0 then
      if optional then
         local util = require("luarocks.util")
         util.printout("WowRocks: skipping TOC autoload (no .toc file)")
         return true
      end
      return nil, "no .toc file in the current directory"
   end
   local util = require("luarocks.util")
   for _, name in ipairs(tocs) do
      local changed, err = toc.ensure_autoload(name)
      if changed == nil then
         return nil, err
      end
      if changed then
         util.printout("WowRocks: added " .. toc.XML_INCLUDE .. " to " .. name)
      end
   end
   return true
end

function toc.write(path, content)
   return files.write_file(path, content)
end

function toc.dir_name()
   return dir.base_name(fs.current_dir())
end

return toc
