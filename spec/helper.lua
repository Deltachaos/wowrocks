package.path = "src/?.lua;src/?/init.lua;" .. package.path

local cfg = require("luarocks.core.cfg")
if not cfg.lua_version then
   cfg.init()
end
local fs = require("luarocks.fs")
if not fs.find then
   fs.init()
end
