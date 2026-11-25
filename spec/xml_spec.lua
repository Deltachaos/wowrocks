local xml = require("wowrocks.xml")

describe("wowrocks.xml", function()
   it("lists only wow paths with backslashes", function()
      local out = xml.generate({
         "wow/lua/5.1/simple.lua",
         "wow/lua/5.1/pkg/init.lua",
      })
      assert.matches("<Ui ", out)
      assert.matches('file="wow\\lua\\5.1\\simple.lua"', out)
      assert.matches('file="wow\\lua\\5.1\\pkg\\init.lua"', out)
      assert.is_nil(out:match("LibStub"))
      assert.is_nil(out:match("meta\\lib.xml"))
      assert.is_nil(out:match("meta/lib.xml"))
   end)

   it("emits an empty Ui when there are no modules", function()
      local out = xml.generate({})
      assert.equal(
         xml.HEADER .. "\n</Ui>\n",
         out
      )
   end)

   it("lists a footer include after the modules", function()
      local out = xml.generate({
         "wow/lua/5.1/simple.lua",
      }, "WowRocks.lua")
      assert.matches('file="wow\\lua\\5.1\\simple.lua"', out)
      assert.matches('file="WowRocks.lua"/>\n</Ui>\n', out)
      local simple_at = out:find("simple.lua", 1, true)
      local footer_at = out:find("WowRocks.lua", 1, true)
      assert.is_true(simple_at < footer_at)
   end)
end)
