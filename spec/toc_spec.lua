local fs = require("luarocks.fs")
local dir = require("luarocks.dir")
local toc = require("wowrocks.toc")
local files = require("wowrocks.util")

describe("wowrocks.toc", function()
   local tmp

   before_each(function()
      fs.make_dir("spec/tmp")
      tmp = fs.absolute_name(dir.path("spec/tmp", "toc-" .. tostring(math.random(1, 1e9))))
      fs.make_dir(tmp)
   end)

   after_each(function()
      if tmp and fs.exists(tmp) then
         fs.delete(tmp)
      end
   end)

   it("generates Interface, Title, Notes, Version, and the WowRocks include", function()
      local out = toc.generate({
         title = "MyAddon",
         notes = "A test addon",
         files = { "MyAddon.lua", "Libs/WoWRocks/WowRocks.xml" },
      })
      assert.matches("## Interface: 120100", out)
      assert.matches("## Title: MyAddon", out)
      assert.matches("## Notes: A test addon", out)
      assert.matches("## Version: scm", out)
      assert.matches("Libs/WoWRocks/WowRocks.xml", out)
      local count = 0
      for _ in out:gmatch("Libs/WoWRocks/WowRocks%.xml") do
         count = count + 1
      end
      assert.equal(1, count)
      assert.matches("MyAddon.lua", out)
   end)

   it("inserts the XML include after the header as the first file", function()
      local path = dir.path(tmp, "MyAddon.toc")
      files.write_file(path, "## Interface: 120100\n## Title: MyAddon\n\nMyAddon.lua\n")
      assert.is_true(toc.ensure_autoload(path))
      local once = files.read_file(path)
      assert.equal(
         "## Interface: 120100\n## Title: MyAddon\n\nLibs/WoWRocks/WowRocks.xml\nMyAddon.lua\n",
         once
      )
      assert.is_false(toc.ensure_autoload(path))
      files.write_file(path, "## Title: Existing\nLibs\\WoWRocks\\WowRocks.xml\n")
      assert.is_false(toc.ensure_autoload(path))
   end)

   it("inserts after ## headers when there is no blank line", function()
      local out = toc.insert_xml_include("## Interface: 120100\nMyAddon.lua\n")
      assert.equal("## Interface: 120100\nLibs/WoWRocks/WowRocks.xml\nMyAddon.lua\n", out)
   end)

   it("strips flavor suffixes when deriving the stem", function()
      assert.equal("MyAddon", toc.stem("MyAddon_Mainline.toc"))
      assert.equal("MyAddon", toc.stem("MyAddon_Mists.toc"))
      assert.equal("MyAddon", toc.stem("MyAddon.toc"))
      assert.equal(
         "MyAddon",
         toc.main_stem("Other", { "MyAddon_Classic.toc", "MyAddon.toc" })
      )
      assert.equal("Other", toc.main_stem("Other", { "Other_Mainline.toc" }))
   end)
end)
