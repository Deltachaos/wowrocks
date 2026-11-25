local fs = require("luarocks.fs")
local dir = require("luarocks.dir")
local cfg = require("luarocks.core.cfg")

local function quote(s)
   return "'" .. s:gsub("'", "'\\''") .. "'"
end

local function read_file(path)
   local fh = assert(io.open(path, "rb"))
   local data = fh:read("*a")
   fh:close()
   return data
end

describe("wowrocks CLI", function()
   local tree
   local root = fs.absolute_name(".")
   local bin = dir.path(root, "bin/wowrocks")
   local fixture = dir.path(root, "spec/fixtures/simple")
   local lua_modules = "share/lua/" .. cfg.lua_version

   before_each(function()
      fs.make_dir(dir.path(root, "spec/tmp"))
      tree = fs.absolute_name(dir.path(root, "spec/tmp", "cli-" .. tostring(math.random(1, 1e9))))
   end)

   after_each(function()
      if tree and fs.exists(tree) then
         fs.delete(tree)
      end
   end)

   it("make writes vanilla share/ and stringified wow/", function()
      local cmd = table.concat({
         "cd", quote(fixture),
         "&&", quote(bin),
         "make", "--tree", quote(tree),
         "simple-1.0-1.rockspec",
      }, " ")
      local ok = os.execute(cmd)
      if type(ok) == "number" then
         assert.equal(0, ok)
      else
         assert.is_truthy(ok)
      end

      local original = read_file(dir.path(tree, lua_modules, "simple.lua"))
      assert.matches("function M%.hello", original)
      assert.is_nil(original:match("_G%.__wowrocks"))

      local blob = read_file(dir.path(tree, "wow/lua/" .. cfg.lua_version, "simple.lua"))
      assert.matches('_G%.__wowrocks%["' .. lua_modules:gsub("%.", "%%.") .. '/simple.lua"%]', blob)
      assert.matches("function M%.hello", blob)

      local xml = read_file(dir.path(tree, "WowRocks.xml"))
      assert.matches('file="wow\\lua\\' .. cfg.lua_version:gsub("%.", "%%.") .. '\\simple.lua"', xml)
      assert.matches('file="WowRocks.lua"/>\n</Ui>\n', xml)
      assert.is_nil(xml:match("LibStub"))

      local runtime = read_file(dir.path(tree, "WowRocks.lua"))
      assert.matches("LibStdShim", runtime)
      assert.matches(lua_modules:gsub("%.", "%%.") .. "/varpackage%.lua", runtime)
   end)

   it("list does not create WowRocks.xml", function()
      local cmd = table.concat({
         quote(bin), "list", "--tree", quote(tree),
      }, " ")
      os.execute(cmd .. " >/dev/null 2>&1")
      assert.is_false(fs.exists(dir.path(tree, "WowRocks.xml")))
   end)
end)
