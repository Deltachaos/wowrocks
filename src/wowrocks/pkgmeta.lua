local fs = require("luarocks.fs")
local files = require("wowrocks.util")

local pkgmeta = {}

local function rtrim(s)
   return s:match("^(.-)%s*$")
end

local function unquote_double(s)
   local out = {}
   local i = 2
   while i <= #s do
      local c = s:sub(i, i)
      if c == "\\" then
         local n = s:sub(i + 1, i + 1)
         if n == "n" then
            out[#out + 1] = "\n"
         elseif n == "t" then
            out[#out + 1] = "\t"
         elseif n == '"' then
            out[#out + 1] = '"'
         elseif n == "\\" then
            out[#out + 1] = "\\"
         else
            out[#out + 1] = n
         end
         i = i + 2
      elseif c == '"' then
         return table.concat(out), s:sub(i + 1)
      else
         out[#out + 1] = c
         i = i + 1
      end
   end
   return table.concat(out), ""
end

local function unquote_single(s)
   local out = {}
   local i = 2
   while i <= #s do
      local c = s:sub(i, i)
      if c == "'" then
         if s:sub(i + 1, i + 1) == "'" then
            out[#out + 1] = "'"
            i = i + 2
         else
            return table.concat(out), s:sub(i + 1)
         end
      else
         out[#out + 1] = c
         i = i + 1
      end
   end
   return table.concat(out), ""
end

local function parse_scalar(s)
   s = rtrim(s:match("^%s*(.*)$") or "")
   if s == "" then
      return ""
   end
   local first = s:sub(1, 1)
   if first == '"' then
      return (unquote_double(s))
   end
   if first == "'" then
      return (unquote_single(s))
   end
   local hash = s:find(" #", 1, true)
   if hash then
      s = rtrim(s:sub(1, hash - 1))
   end
   return s
end

local function split_kv(s)
   s = rtrim(s:match("^%s*(.*)$") or "")
   local first = s:sub(1, 1)
   if first == '"' or first == "'" then
      local key, rest
      if first == '"' then
         key, rest = unquote_double(s)
      else
         key, rest = unquote_single(s)
      end
      rest = rest:match("^%s*(.*)$") or rest
      if rest:sub(1, 1) ~= ":" then
         return nil
      end
      rest = rest:sub(2):match("^%s*(.*)$") or ""
      return key, rest
   end
   if s:match("^[%w][%w%.%-%_/]*://") then
      return nil
   end
   local key, rest = s:match("^([%w][%w%.%-%_/]*):%s*(.*)$")
   if not key then
      return nil
   end
   return key, rest
end

local function new_frame(indent, container, kind)
   return {
      indent = indent,
      container = container,
      kind = kind,
   }
end

function pkgmeta.parse(text)
   if type(text) ~= "string" then
      return nil, "pkgmeta text must be a string"
   end
   if text:find("\t", 1, true) then
      return nil, ".pkgmeta must use spaces, not tabs"
   end
   text = text:gsub("\r\n", "\n"):gsub("\r", "\n")
   if text:sub(-1) ~= "\n" then
      text = text .. "\n"
   end

   local root = {}
   local stack = { new_frame(-1, root, "map") }

   local function current()
      return stack[#stack]
   end

   local function pop_to(indent)
      while #stack > 1 and current().indent >= indent do
         stack[#stack] = nil
      end
   end

   local function set_kind(frame, kind)
      if frame.kind == "unknown" or frame.kind == kind then
         frame.kind = kind
         return true
      end
      if frame.kind == "map" and kind == "map" then
         return true
      end
      if frame.kind == "list" and kind == "list" then
         return true
      end
      return nil, "mixed map and list entries in .pkgmeta"
   end

   local function push_nested(indent, container, kind)
      stack[#stack + 1] = new_frame(indent, container, kind)
   end

   for line in text:gmatch("(.-)\n") do
      if not line:match("^%s*$") and not line:match("^%s*#") then
         local indent = #line:match("^ *")
         local trimmed = rtrim(line:sub(indent + 1))
         pop_to(indent)
         local parent = current()

         local list_body
         if trimmed:sub(1, 2) == "- " then
            list_body = trimmed:sub(3)
         elseif trimmed == "-" then
            list_body = ""
         end

         if list_body then
            local ok, err = set_kind(parent, "list")
            if not ok then
               return nil, err
            end
            local key, rest = split_kv(list_body)
            if key then
               local item = {}
               parent.container[#parent.container + 1] = item
               rest = rest or ""
               if parse_scalar(rest) == "" and not rest:match("^['\"]") then
                  local nested = {}
                  item[key] = nested
                  push_nested(indent, item, "map")
                  push_nested(indent, nested, "unknown")
               else
                  item[key] = parse_scalar(rest)
                  push_nested(indent, item, "map")
               end
            elseif parse_scalar(list_body) == "" then
               local nested = {}
               parent.container[#parent.container + 1] = nested
               push_nested(indent, nested, "unknown")
            else
               parent.container[#parent.container + 1] = parse_scalar(list_body)
            end
         else
            local key, rest = split_kv(trimmed)
            if not key then
               return nil, "invalid .pkgmeta line: " .. trimmed
            end
            local ok, err = set_kind(parent, "map")
            if not ok then
               return nil, err
            end
            rest = rest or ""
            if parse_scalar(rest) == "" and not rest:match("^['\"]") then
               local nested = {}
               parent.container[key] = nested
               push_nested(indent, nested, "unknown")
            else
               parent.container[key] = parse_scalar(rest)
            end
         end
      end
   end

   return root
end

function pkgmeta.load(path)
   path = path or ".pkgmeta"
   if not fs.exists(path) then
      return nil, "no .pkgmeta in the current directory"
   end
   local data, err = files.read_file(path)
   if not data then
      return nil, err
   end
   return pkgmeta.parse(data)
end

function pkgmeta.yaml_quote(value)
   value = tostring(value)
   if value == "" or value:match("^%s") or value:match("%s$")
      or value:find(" #", 1, true) or value:find(": ", 1, true)
      or value:match("^[%-%?:,%[%]{}&*!|>'\"%@`%%#]") then
      return '"' .. value:gsub("\\", "\\\\"):gsub('"', '\\"') .. '"'
   end
   return value
end

local ROOT_KEY_ORDER = {
   "package-as",
   "externals",
   "ignore",
   "plain-copy",
   "required-dependencies",
   "optional-dependencies",
   "embedded-libraries",
   "tools-used",
   "move-folders",
   "manual-changelog",
   "enable-nolib-creation",
   "enable-toc-creation",
}

local EXTERNAL_KEY_ORDER = {
   "url",
   "type",
   "tag",
   "branch",
   "commit",
   "path",
   "curse-slug",
}

local function ordered_keys(tbl, preferred)
   local seen = {}
   local keys = {}
   for _, key in ipairs(preferred or {}) do
      if tbl[key] ~= nil then
         keys[#keys + 1] = key
         seen[key] = true
      end
   end
   for _, key in ipairs(files.sorted_keys(tbl)) do
      if not seen[key] then
         keys[#keys + 1] = key
      end
   end
   return keys
end

local function is_list(tbl)
   local count = 0
   for key in pairs(tbl) do
      if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then
         return false
      end
      count = count + 1
   end
   return count == #tbl
end

local function emit(lines, value, indent, preferred)
   local pad = string.rep(" ", indent)
   if type(value) ~= "table" then
      return
   end
   if is_list(value) then
      for _, item in ipairs(value) do
         if type(item) ~= "table" then
            lines[#lines + 1] = pad .. "- " .. pkgmeta.yaml_quote(item)
         else
            lines[#lines + 1] = pad .. "-"
            emit(lines, item, indent + 2)
         end
      end
      return
   end
   for _, key in ipairs(ordered_keys(value, preferred)) do
      local child = value[key]
      local rendered = pkgmeta.yaml_quote(key)
      if type(child) ~= "table" then
         lines[#lines + 1] = pad .. rendered .. ": " .. pkgmeta.yaml_quote(child)
      elseif next(child) == nil then
         lines[#lines + 1] = pad .. rendered .. ":"
      else
         lines[#lines + 1] = pad .. rendered .. ":"
         local child_order = key == "externals" and nil or EXTERNAL_KEY_ORDER
         if key == "externals" then
            for _, dest in ipairs(files.sorted_keys(child)) do
               local spec = child[dest]
               lines[#lines + 1] = pad .. "  " .. pkgmeta.yaml_quote(dest) .. ":"
               if type(spec) ~= "table" then
                  lines[#lines] = pad .. "  " .. pkgmeta.yaml_quote(dest) .. ": " .. pkgmeta.yaml_quote(spec)
               else
                  emit(lines, spec, indent + 4, EXTERNAL_KEY_ORDER)
               end
            end
         else
            emit(lines, child, indent + 2, child_order)
         end
      end
   end
end

function pkgmeta.dump(tbl)
   local lines = {}
   emit(lines, tbl or {}, 0, ROOT_KEY_ORDER)
   if #lines == 0 then
      return ""
   end
   return table.concat(lines, "\n") .. "\n"
end

function pkgmeta.save(tbl, path)
   path = path or ".pkgmeta"
   return files.write_file(path, pkgmeta.dump(tbl))
end

function pkgmeta.add_external(dest, spec, path)
   path = path or ".pkgmeta"
   local meta = {}
   if fs.exists(path) then
      local loaded, err = pkgmeta.load(path)
      if not loaded then
         return nil, err
      end
      meta = loaded
   end
   meta.externals = meta.externals or {}
   local entry = meta.externals[dest]
   if type(entry) == "string" then
      entry = { url = entry }
   elseif type(entry) ~= "table" then
      entry = {}
   end
   entry.url = spec.url
   if spec.path and spec.path ~= "" then
      entry.path = spec.path
   end
   if spec.type then
      entry.type = spec.type
   end
   meta.externals[dest] = entry
   return pkgmeta.save(meta, path)
end

function pkgmeta.write_default(name, path)
   path = path or ".pkgmeta"
   return files.write_file(path, "package-as: " .. pkgmeta.yaml_quote(name) .. "\n")
end

return pkgmeta
