local fs = require("luarocks.fs")
local dir = require("luarocks.dir")
local persist = require("luarocks.persist")

local files = require("wowrocks.util")
local project = require("wowrocks.project")
local pkgmeta = require("wowrocks.pkgmeta")
local toc = require("wowrocks.toc")

describe("wowrocks.project", function()
   local tmp

   before_each(function()
      fs.make_dir("spec/tmp")
      tmp = fs.absolute_name(dir.path("spec/tmp", "proj-" .. tostring(math.random(1, 1e9))))
      fs.make_dir(tmp)
      assert(fs.change_dir(tmp))
   end)

   after_each(function()
      fs.pop_dir()
      if tmp and fs.exists(tmp) then
         fs.delete(tmp)
      end
   end)

   it("appends Libs/WoWRocks to .gitignore once", function()
      assert.is_true(project.ensure_gitignore())
      assert.is_false(project.ensure_gitignore())
      local data = files.read_file(".gitignore")
      assert.equal("Libs/WoWRocks\n", data)
   end)

   it("init_files creates toc, gitignore, scm-1 rockspec, hello spec, and .pkgmeta ignore", function()
      files.write_file("Hello.lua", "print('hi')\n")
      assert.is_true(project.init_files())
      local name = dir.base_name(tmp)
      assert.is_true(fs.is_file(".gitignore"))
      assert.is_true(fs.is_file(".pkgmeta"))
      local meta = assert(pkgmeta.load())
      assert.equal(name, meta["package-as"])
      assert.equal("spec", meta.ignore[1])
      assert.is_true(fs.is_file("spec/hello_spec.lua"))
      local hello = files.read_file("spec/hello_spec.lua")
      assert.matches('describe%("hello"', hello)
      assert.matches('it%("world"', hello)
      assert.matches("hello world", hello)
      assert.is_true(fs.is_file(name .. ".toc"))
      local rockspec = files.rock_name(name) .. "-scm-1.rockspec"
      assert.is_true(fs.is_file(rockspec))
      local toc_data = files.read_file(name .. ".toc")
      assert.matches("## Interface: 120100", toc_data)
      assert.matches("Hello.lua", toc_data)
      assert.matches("Libs/WoWRocks/WowRocks.xml", toc_data)
      local tbl = persist.load_into_table(rockspec)
      assert.equal("scm-1", tbl.version)
      assert.equal("file://.", tbl.source.url)
      local deps = table.concat(tbl.dependencies, "\n")
      assert.matches("lua >= 5.1", deps)
      assert.matches("libstdshim", deps)
      assert.matches("varpackage", deps)
      assert.equal("busted", tbl.test_dependencies[1])
      assert.equal("busted", tbl.test.type)
   end)

   it("ensure_scaffold keeps existing specs and adds spec to .pkgmeta ignore", function()
      files.write_file("Hello.lua", "--\n")
      files.write_file("spec/existing_spec.lua", 'describe("existing", function() end)\n')
      files.write_file(".pkgmeta", "package-as: Hello\nexternals:\n  Libs/Foo: https://example.com/foo.git\n")
      assert.is_true(project.ensure_scaffold())
      assert.is_false(fs.exists("spec/hello_spec.lua"))
      local meta = assert(pkgmeta.load())
      assert.equal("Hello", meta["package-as"])
      assert.equal("https://example.com/foo.git", meta.externals["Libs/Foo"])
      assert.equal("spec", meta.ignore[1])
   end)

   it("ensure_scaffold does not add default deps to an existing rockspec", function()
      files.write_file("Hello.lua", "--\n")
      files.write_file("hello-scm-1.rockspec", table.concat({
         'package = "hello"',
         'version = "scm-1"',
         "source = { url = \"file://.\" }",
         'description = { summary = "hello" }',
         'dependencies = { "lua >= 5.1" }',
         "build = { type = \"builtin\", modules = {} }",
         "",
      }, "\n"))
      assert.is_true(project.ensure_scaffold())
      local tbl = persist.load_into_table("hello-scm-1.rockspec")
      assert.equal("lua >= 5.1", tbl.dependencies[1])
      assert.equal(1, #tbl.dependencies)
      assert.is_true(fs.is_file(".gitignore"))
   end)

   it("init_files adds default deps to an existing rockspec", function()
      files.write_file("Hello.lua", "--\n")
      files.write_file("hello-scm-1.rockspec", table.concat({
         'package = "hello"',
         'version = "scm-1"',
         "source = { url = \"file://.\" }",
         'description = { summary = "hello" }',
         'dependencies = { "lua >= 5.1" }',
         "build = { type = \"builtin\", modules = {} }",
         "",
      }, "\n"))
      assert.is_true(project.init_files())
      local tbl = persist.load_into_table("hello-scm-1.rockspec")
      local deps = table.concat(tbl.dependencies, "\n")
      assert.matches("libstdshim", deps)
      assert.matches("varpackage", deps)
      assert.equal("busted", tbl.test_dependencies[1])
   end)

   it("require adds a dependency and replaces an existing constraint", function()
      files.write_file("Hello.lua", "--\n")
      assert.is_true(project.init_files())
      local path = assert(project.add_require("dkjson"))
      local tbl = persist.load_into_table(path)
      assert.matches("dkjson", table.concat(tbl.dependencies, "\n"))
      assert(project.add_require("dkjson >= 2.5"))
      tbl = persist.load_into_table(path)
      local json = 0
      for _, dep in ipairs(tbl.dependencies) do
         if dep:match("^dkjson") then
            json = json + 1
            assert.equal("dkjson >= 2.5", dep)
         end
      end
      assert.equal(1, json)
   end)

   it("require --test adds to test_dependencies", function()
      files.write_file("Hello.lua", "--\n")
      assert.is_true(project.init_files())
      local path = assert(project.add_require("luassert", { test = true }))
      local tbl = persist.load_into_table(path)
      local tests = table.concat(tbl.test_dependencies, "\n")
      assert.matches("luassert", tests)
      assert.is_nil(table.concat(tbl.dependencies, "\n"):match("luassert"))
   end)

   it("init_files derives title from an existing TOC and does not rewrite it", function()
      files.write_file("MyAddon.toc", "## Title: Fancy\n## Notes: Stuff\n## Author: Ada\nCore.lua\n")
      files.write_file("Core.lua", "--\n")
      assert.is_true(project.init_files())
      local toc_data = files.read_file("MyAddon.toc")
      assert.equal("## Title: Fancy\n## Notes: Stuff\n## Author: Ada\nCore.lua\n", toc_data)
      local rockspec = project.select_rockspec("MyAddon")
      local tbl = persist.load_into_table(rockspec)
      assert.equal("Fancy", tbl.description.summary)
      assert.equal("Ada", tbl.description.maintainer)
   end)

   it("ensure_dependency does not replace an existing constraint", function()
      local deps = { "lua >= 5.1", "libstdshim >= 0.1" }
      assert.is_false(project.ensure_dependency(deps, "libstdshim"))
      assert.equal("libstdshim >= 0.1", deps[2])
      assert.is_true(project.ensure_dependency(deps, "varpackage"))
      assert.equal("varpackage", deps[3])
   end)

   it("require of a URL writes an external dest under Libs/", function()
      local dest = assert(project.add_external("https://github.com/WoWUIDev/Ace3"))
      assert.equal("Libs/Ace3", dest)
      local pkg = files.read_file(".pkgmeta")
      assert.equal(
         "externals:\n  Libs/Ace3:\n    url: https://github.com/WoWUIDev/Ace3\n",
         pkg
      )
   end)

   it("require of a URL with --path uses the path basename as dest", function()
      local dest = assert(project.add_external("https://github.com/WoWUIDev/Ace3", {
         path = "SomeSubPath/LibStub",
      }))
      assert.equal("Libs/LibStub", dest)
      local data = assert(pkgmeta.load())
      assert.equal("https://github.com/WoWUIDev/Ace3", data.externals["Libs/LibStub"].url)
      assert.equal("SomeSubPath/LibStub", data.externals["Libs/LibStub"].path)
   end)

   it("require of a URL with --dir overrides the destination", function()
      local dest = assert(project.add_external("https://github.com/WoWUIDev/Ace3", {
         path = "SomeSubPath/LibStub",
         dir = "Vendor/Stub",
      }))
      assert.equal("Vendor/Stub", dest)
      local data = assert(pkgmeta.load())
      assert.equal("SomeSubPath/LibStub", data.externals["Vendor/Stub"].path)
   end)

   it("create scaffolds a directory with toc and lua boilerplate", function()
      assert.equal("MyAddon", project.create("MyAddon"))
      assert.is_true(fs.is_dir("MyAddon"))
      local lua = files.read_file("MyAddon/MyAddon.lua")
      assert.matches("local addonName, ns = %.%.%.", lua)
      assert.matches("local require = WoWRocks%.require", lua)
      assert.matches('CreateFrame%("Frame"%)', lua)
      assert.matches('RegisterEvent%("ADDON_LOADED"%)', lua)
      assert.matches("print%(addonName %.%. \" loaded!\"%)", lua)
      local toc_data = files.read_file("MyAddon/MyAddon.toc")
      assert.matches("## Title: MyAddon", toc_data)
      assert.matches("MyAddon%.lua", toc_data)
      local ok, err = project.create("MyAddon")
      assert.is_nil(ok)
      assert.matches("already exists", err)
   end)

   it("git_init creates a repository when git is available", function()
      local inited, err = project.git_init()
      if inited == false then
         return
      end
      assert.equal(true, inited, err)
      assert.is_true(fs.is_dir(".git") or fs.is_file(".git"))
   end)

   it("create rejects path separators", function()
      local ok, err = project.create("foo/bar")
      assert.is_nil(ok)
      assert.matches("single directory", err)
   end)

   it("main toc name prefers the directory name", function()
      files.write_file("Other.toc", "## Title: Other\n")
      files.write_file(dir.base_name(tmp) .. ".toc", "## Title: Mine\n")
      assert.equal(dir.base_name(tmp), toc.main_stem(dir.base_name(tmp)))
   end)
end)
