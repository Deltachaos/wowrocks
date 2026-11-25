local fs = require("luarocks.fs")
local dir = require("luarocks.dir")
local hook = require("wowrocks.hook")

local function write_file(path, contents)
   fs.make_dir(dir.dir_name(path))
   local fh = assert(io.open(path, "wb"))
   fh:write(contents)
   fh:close()
end

local function read_file(path)
   local fh = assert(io.open(path, "rb"))
   local data = fh:read("*a")
   fh:close()
   return data
end

describe("wowrocks.hook", function()
   local tree

   setup(function()
      fs.make_dir("spec/tmp")
   end)

   before_each(function()
      tree = fs.absolute_name(dir.path("spec/tmp", "hook-" .. tostring(math.random(1, 1e9))))
      fs.make_dir(dir.path(tree, "share/lua/5.1"))
   end)

   after_each(function()
      if tree and fs.exists(tree) then
         fs.delete(tree)
      end
   end)

   it("maps share/lua/5.1 to wow/lua/5.1", function()
      assert.equal("wow/lua/5.1", hook.wow_modules_path("share/lua/5.1"))
      assert.equal("wow/lua/5.4", hook.wow_modules_path("share\\lua\\5.4"))
      assert.equal("wow/lua/5.1", hook.wow_modules_path("/share/lua/5.1"))
   end)

   it("accepts the leading slash from LuaRocks 3.8 module paths", function()
      write_file(dir.path(tree, "share/lua/5.1/simple.lua"), "return 1\n")
      local ok, files = hook.refresh(tree, "/share/lua/5.1")
      assert.is_truthy(ok)
      assert.same({ "wow/lua/5.1/simple.lua" }, files)
      local blob = read_file(dir.path(tree, "wow/lua/5.1/simple.lua"))
      assert.matches('_G%.__wowrocks%["share/lua/5.1/simple.lua"%]', blob)
      local runtime = read_file(dir.path(tree, "WowRocks.lua"))
      assert.matches("share/lua/5%.1/varpackage%.lua", runtime)
   end)

   it("writes blobs and WowRocks.xml without LibStub", function()
      write_file(dir.path(tree, "share/lua/5.1/simple.lua"), "return { ok = true }\n")
      write_file(dir.path(tree, "share/lua/5.1/pkg/init.lua"), "return require 'child'\n")

      local ok, files = hook.refresh(tree, "share/lua/5.1")
      assert.is_truthy(ok)
      assert.same({
         "wow/lua/5.1/pkg/init.lua",
         "wow/lua/5.1/simple.lua",
      }, files)

      local original = read_file(dir.path(tree, "share/lua/5.1/simple.lua"))
      assert.equal("return { ok = true }\n", original)

      local blob = read_file(dir.path(tree, "wow/lua/5.1/simple.lua"))
      assert.matches('_G%.__wowrocks%["share/lua/5.1/simple.lua"%]', blob)
      assert.matches("return { ok = true }", blob)

      local sugar = read_file(dir.path(tree, "wow/lua/5.1/pkg/init.lua"))
      assert.matches("require 'child'", sugar)

      local xml = read_file(dir.path(tree, "WowRocks.xml"))
      assert.matches('file="wow\\lua\\5.1\\simple.lua"', xml)
      assert.matches('file="wow\\lua\\5.1\\pkg\\init.lua"', xml)
      assert.matches('file="WowRocks.lua"/>\n</Ui>\n', xml)
      assert.is_nil(xml:match("LibStub"))
      assert.is_nil(xml:match("meta"))

      local runtime = read_file(dir.path(tree, "WowRocks.lua"))
      assert.matches("share/lua/5%.1/varpackage%.lua", runtime)
      assert.matches("LibStdShim", runtime)
      assert.matches("WoWRocks%-1%.0", runtime)
   end)

   it("drops stale wow files after a refresh", function()
      write_file(dir.path(tree, "share/lua/5.1/keep.lua"), "return 1\n")
      write_file(dir.path(tree, "wow/lua/5.1/gone.lua"), "-- stale\n")
      hook.refresh(tree, "share/lua/5.1")
      assert.is_false(fs.exists(dir.path(tree, "wow/lua/5.1/gone.lua")))
      assert.is_true(fs.exists(dir.path(tree, "wow/lua/5.1/keep.lua")))
   end)
end)
