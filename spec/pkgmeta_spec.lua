local pkgmeta = require("wowrocks.pkgmeta")

describe("wowrocks.pkgmeta", function()
   it("parses the packager externals example including URL shorthand", function()
      local data, err = pkgmeta.parse([[
package-as: Monkey

externals:
  Libs/LibStub:
    url: https://repos.wowace.com/wow/libstub/trunk
    tag: 1.0
  Libs/CallbackHandler-1.0:
    url: https://repos.wowace.com/wow/callbackhandler/trunk/CallbackHandler-1.0
    tag: latest
  Libs/LibMonkey-1.0: https://repos.curseforge.net/wow/libmonkey-1-0/trunk
  Libs/LibBanana-1.0:
    url: https://github.com/monkehdude/LibBanana-1.0.git
    path: LibBanana-1.0
    curse-slug: libbanana-1-0
  Libs/LibSuit-2.0:
    url: https://repos.curseforge.net/wow/libsuit-2-0
    type: hg
  Libs/LibCoconut-1.0: https://github.com/monkehdude/LibCoconut-1.0/releases/download/v1.2/LibCoconut-1.0-v1.2.zip

ignore:
  - Scripts
  - Modules/Debug.lua
  - "*.txt"

required-dependencies:
  - monkey-town
]])
      assert.is_nil(err)
      assert.equal("Monkey", data["package-as"])
      assert.equal("https://repos.wowace.com/wow/libstub/trunk", data.externals["Libs/LibStub"].url)
      assert.equal("1.0", data.externals["Libs/LibStub"].tag)
      assert.equal("latest", data.externals["Libs/CallbackHandler-1.0"].tag)
      assert.equal(
         "https://repos.curseforge.net/wow/libmonkey-1-0/trunk",
         data.externals["Libs/LibMonkey-1.0"]
      )
      assert.equal("LibBanana-1.0", data.externals["Libs/LibBanana-1.0"].path)
      assert.equal("hg", data.externals["Libs/LibSuit-2.0"].type)
      assert.equal(
         "https://github.com/monkehdude/LibCoconut-1.0/releases/download/v1.2/LibCoconut-1.0-v1.2.zip",
         data.externals["Libs/LibCoconut-1.0"]
      )
      assert.equal("Scripts", data.ignore[1])
      assert.equal("*.txt", data.ignore[3])
      assert.equal("monkey-town", data["required-dependencies"][1])
   end)

   it("rejects tabs", function()
      local data, err = pkgmeta.parse("package-as:\tMonkey\n")
      assert.is_nil(data)
      assert.matches("tabs", err)
   end)

   it("dumps externals with url and path", function()
      local yaml = pkgmeta.dump({
         externals = {
            ["Libs/LibStub"] = {
               url = "https://github.com/WoWUIDev/Ace3",
               path = "SomeSubPath/LibStub",
            },
         },
      })
      assert.equal(
         "externals:\n  Libs/LibStub:\n    url: https://github.com/WoWUIDev/Ace3\n    path: SomeSubPath/LibStub\n",
         yaml
      )
   end)

   it("strips comments and quoted hashes", function()
      local data = assert(pkgmeta.parse([[
# header
package-as: Monkey  # name
notes: "see #1"
]]))
      assert.equal("Monkey", data["package-as"])
      assert.equal("see #1", data.notes)
   end)
end)
