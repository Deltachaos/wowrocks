local bootstrap = {}

bootstrap.FILENAME = "WowRocks.lua"

local function quote(value)
   return '"' .. tostring(value):gsub("\\", "\\\\"):gsub('"', '\\"') .. '"'
end

function bootstrap.source(lua_modules_path)
   lua_modules_path = (lua_modules_path or "share/lua/5.1"):gsub("\\", "/"):gsub("/+$", "")
   local key = lua_modules_path .. "/varpackage.lua"
   local search_path = lua_modules_path .. "/?.lua;" .. lua_modules_path .. "/?/init.lua"
   return table.concat({
      "local M = _G.WoWRocks or {}",
      "if _G.LibStub then",
      '   local lib = _G.LibStub:NewLibrary("WoWRocks-1.0", 1)',
      "   if not lib then",
      "      return",
      "   end",
      "   if lib ~= M then",
      "      for field, value in pairs(M) do",
      "         lib[field] = value",
      "      end",
      "      M = lib",
      "   end",
      "end",
      "",
      "if next(M) == nil then",
      "   local key = " .. quote(key),
      "   _G.package = _G.package or {}",
      "   _G.package.loaded = _G.package.loaded or {}",
      '   local varpackage = _G.package.loaded["varpackage"]',
      '   if type(varpackage) ~= "table" then',
      "      local rocks = _G.__wowrocks",
      "      local source = rocks and rocks[key]",
      '      if type(source) ~= "string" then',
      '         error("WoWRocks: " .. key .. " is not available", 0)',
      "      end",
      "      local loadchunk = loadstring or load",
      '      local chunk, err = loadchunk(source, "@" .. key)',
      "      if not chunk then",
      "         error(err, 0)",
      "      end",
      '      varpackage = chunk("varpackage")',
      '      if type(varpackage) ~= "table" and _G.LibStub then',
      '         varpackage = _G.LibStub("varpackage-1.0", true)',
      "      end",
      '      if type(varpackage) ~= "table" then',
      '         error("WoWRocks: varpackage did not return a module", 0)',
      "      end",
      '      _G.package.loaded["varpackage"] = varpackage',
      "   end",
      "",
      "   local search_path = " .. quote(search_path),
      "   local function getter(file)",
      "      local rocks = _G.__wowrocks",
      "      return rocks and rocks[file]",
      "   end",
      "",
      "   local tmprequire = varpackage({",
      "      get = getter,",
      "      path = search_path,",
      "      native = false,",
      "   })",
      '   local ok, loaded = pcall(tmprequire, "LibStdShim")',
      '   local LibStdShim = (ok and type(loaded) == "table" and loaded) or {}',
      "   local require = varpackage({",
      "      get = getter,",
      "      globals = LibStdShim,",
      "      path = search_path,",
      "      native = false,",
      "   })",
      "   M.require = require",
      "end",
      "",
      "setmetatable(M, {",
      "   __call = function(_, ...)",
      "      return M.require(...)",
      "   end,",
      "})",
      "WoWRocks = M",
      "",
   }, "\n")
end

return bootstrap
