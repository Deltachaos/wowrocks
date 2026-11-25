local stringify = {}

function stringify.quote(value)
   return '"' .. value:gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\n", "\\n") .. '"'
end

function stringify.lua_long_string(source)
   local n = 0
   while true do
      local close = "]" .. string.rep("=", n) .. "]"
      if not source:find(close, 1, true) then
         local open = "[" .. string.rep("=", n) .. "["
         return open .. "\n" .. source .. close
      end
      n = n + 1
   end
end

function stringify.wrap(relpath, source)
   local key = relpath:gsub("\\", "/")
   return (
      "_G.__wowrocks = _G.__wowrocks or {}\n"
      .. "_G.__wowrocks[" .. stringify.quote(key) .. "] = "
      .. stringify.lua_long_string(source) .. "\n"
   )
end

return stringify
