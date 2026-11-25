local bootstrap = require("wowrocks.bootstrap")

local VARPACKAGE = [[
local function factory(opts)
   opts = opts or {}
   local get = opts.get or function() end
   local req = {
      package = { path = opts.path or "" },
      globals = opts.globals,
      native = opts.native,
   }
   setmetatable(req, {
      __call = function(self, name)
         local template = (self.package.path or ""):match("[^;]+") or ""
         local file = template:gsub("%?", (name:gsub("%.", "/")))
         local src = get(file)
         if type(src) ~= "string" then
            error("module '" .. name .. "' not found", 0)
         end
         local chunk, err = (loadstring or load)(src, "@" .. file)
         if not chunk then
            error(err, 0)
         end
         return chunk(name)
      end,
   })
   return req
end
return setmetatable({}, {
   __call = function(_, opts)
      return factory(opts)
   end,
})
]]

local function libstub()
   local LibStub = {
      libs = {},
      minors = {},
      minor = 2,
   }
   function LibStub:NewLibrary(major, minor)
      assert(type(major) == "string")
      minor = assert(tonumber(tostring(minor):match("%d+")))
      local old = self.minors[major]
      if old and old >= minor then
         return nil
      end
      self.minors[major] = minor
      self.libs[major] = self.libs[major] or {}
      return self.libs[major]
   end
   function LibStub:GetLibrary(major, silent)
      if not self.libs[major] then
         if silent then
            return nil
         end
         error("Library " .. major .. " was not loaded", 2)
      end
      return self.libs[major]
   end
   return setmetatable(LibStub, {
      __call = function(self, major, silent)
         return self:GetLibrary(major, silent)
      end,
   })
end

local function with_env(setup, fn)
   local saved = {
      WoWRocks = _G.WoWRocks,
      LibStub = _G.LibStub,
      __wowrocks = _G.__wowrocks,
      loaded = _G.package.loaded.varpackage,
   }
   _G.WoWRocks = nil
   _G.LibStub = nil
   _G.__wowrocks = nil
   _G.package.loaded.varpackage = nil
   local ok, err = pcall(function()
      setup()
      fn()
   end)
   _G.WoWRocks = saved.WoWRocks
   _G.LibStub = saved.LibStub
   _G.__wowrocks = saved.__wowrocks
   _G.package.loaded.varpackage = saved.loaded
   if not ok then
      error(err, 2)
   end
end

local function run(source)
   local chunk, err = (loadstring or load)(source, "@WowRocks.lua")
   assert.is_truthy(chunk, err)
   chunk()
end

describe("wowrocks.bootstrap", function()
   local modules = "share/lua/5.5"

   local function install_sources(extra)
      _G.__wowrocks = {
         [modules .. "/varpackage.lua"] = VARPACKAGE,
         [modules .. "/LibStdShim.lua"] = "return { from_stub = true }\n",
         [modules .. "/simple.lua"] = "return { ok = true }\n",
      }
      if extra then
         extra(_G.__wowrocks)
      end
   end

   it("names the varpackage blob for the installed lua path", function()
      local source = bootstrap.source(modules)
      assert.matches("share/lua/5%.5/varpackage%.lua", source)
      assert.matches("LibStdShim", source)
      assert.matches("native = false", source)
      assert.is_nil(source:match("libstdstub"))
   end)

   it("publishes require on _G.WoWRocks when LibStub is absent", function()
      with_env(function()
         install_sources()
      end, function()
         run(bootstrap.source(modules))
         assert.is_true(_G.WoWRocks.require.globals.from_stub)
         assert.is_false(_G.WoWRocks.require.native)
         assert.same({ ok = true }, _G.WoWRocks.require("simple"))
         assert.same({ ok = true }, _G.WoWRocks("simple"))
      end)
   end)

   it("registers WoWRocks-1.0 when LibStub is present", function()
      with_env(function()
         install_sources()
         _G.LibStub = libstub()
      end, function()
         run(bootstrap.source(modules))
         local lib = _G.LibStub("WoWRocks-1.0")
         assert.equal(lib, _G.WoWRocks)
         assert.same({ ok = true }, lib.require("simple"))
         assert.same({ ok = true }, _G.WoWRocks("simple"))
         assert.is_true(lib.require.globals.from_stub)
         local again = _G.LibStub:NewLibrary("WoWRocks-1.0", 1)
         assert.is_nil(again)
      end)
   end)

   it("keeps an empty shim table when LibStdShim is missing", function()
      with_env(function()
         install_sources(function(rocks)
            rocks[modules .. "/LibStdShim.lua"] = nil
         end)
      end, function()
         run(bootstrap.source(modules))
         assert.same({}, _G.WoWRocks.require.globals)
         assert.same({ ok = true }, _G.WoWRocks.require("simple"))
      end)
   end)

   it("leaves a non-empty library alone", function()
      with_env(function()
         _G.WoWRocks = { keep = true }
      end, function()
         run(bootstrap.source(modules))
         assert.is_true(_G.WoWRocks.keep)
         assert.is_nil(_G.WoWRocks.require)
      end)
   end)
end)
