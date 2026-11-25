local fs = require("luarocks.fs")
local dir = require("luarocks.dir")

local files = require("wowrocks.util")
local pkgmeta = require("wowrocks.pkgmeta")
local externals = require("wowrocks.externals")

local function git(repo, ...)
   assert(fs.change_dir(repo))
   local ok = fs.execute("git", ...)
   fs.pop_dir()
   return ok
end

local function in_dir(path, fn)
   assert(fs.change_dir(path))
   local ok, err = pcall(fn)
   fs.pop_dir()
   if not ok then
      error(err)
   end
end

describe("wowrocks.externals", function()
   local tmp
   local origin

   before_each(function()
      origin = fs.current_dir()
      fs.make_dir("spec/tmp")
      tmp = fs.absolute_name(dir.path("spec/tmp", "ext-" .. tostring(math.random(1, 1e9))))
      fs.make_dir(tmp)
      assert(fs.change_dir(tmp))
   end)

   after_each(function()
      local guard = 0
      while origin and fs.current_dir() ~= origin and guard < 20 do
         if not fs.pop_dir() then
            break
         end
         guard = guard + 1
      end
      if tmp and fs.exists(tmp) then
         fs.delete(tmp)
      end
   end)

   it("guesses zip, svn, git, and explicit hg", function()
      assert.equal("zip", externals.guess_type({ url = "https://example.com/lib.zip" }))
      assert.equal("svn", externals.guess_type({ url = "https://repos.wowace.com/wow/libstub/trunk" }))
      assert.equal("svn", externals.guess_type({ url = "svn://example.com/repo" }))
      assert.equal("git", externals.guess_type({ url = "https://github.com/foo/bar.git" }))
      assert.equal("hg", externals.guess_type({ url = "https://example.com/repo", type = "hg" }))
   end)

   it("clones a local git repo into the external dest", function()
      local repo = dir.path(tmp, "upstream")
      fs.make_dir(repo)
      files.write_file(dir.path(repo, "Lib.lua"), "return 42\n")
      assert.is_truthy(git(repo, "init"))
      assert.is_truthy(git(repo, "config", "user.email", "test@test"))
      assert.is_truthy(git(repo, "config", "user.name", "test"))
      assert.is_truthy(git(repo, "add", "."))
      assert.is_truthy(git(repo, "commit", "-m", "init"))

      local addon = dir.path(tmp, "addon")
      fs.make_dir(addon)
      in_dir(addon, function()
         files.write_file(".pkgmeta", "externals:\n  Libs/Foo: " .. repo .. "\n")
         assert.is_true(externals.fetch_all())
         assert.equal("return 42\n", files.read_file("Libs/Foo/Lib.lua"))
      end)
   end)

   it("unpacks a zip archive, unwrapping a single top-level folder", function()
      fs.make_dir("LibFoo")
      files.write_file(dir.path("LibFoo", "hello.lua"), "return 'zip'\n")
      assert.is_truthy(fs.zip)
      assert.is_truthy(fs.zip("LibFoo.zip", "LibFoo"))
      local zipfile = fs.absolute_name("LibFoo.zip")

      local addon = dir.path(tmp, "addon")
      fs.make_dir(addon)
      in_dir(addon, function()
         assert.is_true(externals.fetch_one("Libs/Bar", zipfile))
         assert.equal("return 'zip'\n", files.read_file("Libs/Bar/hello.lua"))
      end)
   end)

   it("normalizes a shorthand URL and a table spec", function()
      local spec = assert(externals.normalize("Libs/Foo", "https://example.com/foo.git"))
      assert.equal("git", spec.type)
      spec = assert(externals.normalize("Libs/Foo", {
         url = "https://example.com/foo.zip",
         path = "src",
      }))
      assert.equal("zip", spec.type)
      assert.equal("src", spec.path)
   end)

   it("parses zip shorthand from pkgmeta", function()
      local data = assert(pkgmeta.parse("externals:\n  Libs/Foo: /tmp/foo.zip\n"))
      local spec = assert(externals.normalize("Libs/Foo", data.externals["Libs/Foo"]))
      assert.equal("zip", spec.type)
   end)
end)
