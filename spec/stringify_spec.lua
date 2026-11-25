local stringify = require("wowrocks.stringify")

describe("wowrocks.stringify", function()
   it("registers the LuaRocks path as the blob key", function()
      local wrapped = stringify.wrap("share/lua/5.1/simple.lua", "return { ok = true }\n")
      assert.matches("_G%.__wowrocks = _G%.__wowrocks or {}", wrapped)
      assert.matches('_G%.__wowrocks%["share/lua/5.1/simple.lua"%]', wrapped)
      assert.matches("return { ok = true }", wrapped)
   end)

   it("keeps require sugar and file-scope return", function()
      local src = "local child = require 'child'\nreturn { child = child }\n"
      local wrapped = stringify.wrap("share/lua/5.1/sugar.lua", src)
      assert.matches("require 'child'", wrapped)
      assert.matches("return { child = child }", wrapped)
      assert.is_nil(wrapped:match("require require"))
   end)

   it("picks a long-string level that does not collide with the source", function()
      local src = "local x = [[hi]]\nlocal y = [=[ho]=]\nreturn x\n"
      local wrapped = stringify.wrap("share/lua/5.1/x.lua", src)
      assert.matches("%[%[%s*hi%s*%]%]", wrapped)
      assert.matches("%[=%[ho%]=%]", wrapped)
      assert.matches("%[==%[", wrapped)
      assert.matches("%]==%]", wrapped)
   end)
end)
