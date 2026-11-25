local fs = require("luarocks.fs")
local dir = require("luarocks.dir")
local files = require("wowrocks.util")

local function quote(s)
   return "'" .. s:gsub("'", "'\\''") .. "'"
end

local function run(cmd)
   local pipe = io.popen(cmd .. " 2>&1")
   local out = pipe:read("*a") or ""
   local ok, _, code = pipe:close()
   return out, ok, code
end

local function write_lua_only_rockspec(path, package_name)
   files.write_file(path, table.concat({
      'package = "' .. package_name .. '"',
      'version = "scm-1"',
      "source = { url = \"file://.\" }",
      'description = { summary = "fixture" }',
      'dependencies = { "lua >= 5.1" }',
      "build = {",
      '  type = "builtin",',
      "  modules = {},",
      "}",
      "",
   }, "\n"))
end

describe("wowrocks addon CLI", function()
   local root = fs.absolute_name(".")
   local wowrocks = dir.path(root, "bin/wowrocks")
   local wowaddon = dir.path(root, "bin/wowaddon")
   local tmp

   before_each(function()
      fs.make_dir(dir.path(root, "spec/tmp"))
      tmp = fs.absolute_name(dir.path(root, "spec/tmp", "addon-" .. tostring(math.random(1, 1e9))))
      fs.make_dir(tmp)
   end)

   after_each(function()
      if tmp and fs.exists(tmp) then
         fs.delete(tmp)
      end
   end)

   it("wowrocks addon help and wowaddon help print usage", function()
      local out = run(quote(wowrocks) .. " addon help")
      assert.matches("install", out)
      assert.matches("externals", out)
      assert.matches("require", out)
      assert.matches("init", out)
      assert.matches("create", out)
      assert.matches("test", out)
      out = run(quote(wowaddon) .. " help")
      assert.matches("install", out)
      assert.matches("WowRocks.xml", out)
      assert.matches("Libs/WoWRocks/bin/busted", out)
   end)

   it("addon install --no-externals vendors deps and adds the TOC include after the header", function()
      files.write_file(dir.path(tmp, "MyAddon.lua"), "print('ok')\n")
      files.write_file(dir.path(tmp, "MyAddon.toc"), "## Interface: 120100\nMyAddon.lua\n")
      write_lua_only_rockspec(dir.path(tmp, "myaddon-scm-1.rockspec"), "myaddon")
      local cmd = table.concat({
         "cd", quote(tmp),
         "&&", quote(wowrocks),
         "addon", "install", "--no-externals",
      }, " ")
      local out, ok, code = run(cmd)
      if type(code) == "number" then
         assert.equal(0, code, out)
      else
         assert.is_truthy(ok, out)
      end
      assert.is_true(fs.is_file(dir.path(tmp, "Libs/WoWRocks/WowRocks.xml")))
      assert.is_true(fs.is_file(dir.path(tmp, "Libs/WoWRocks/WowRocks.lua")))
      local toc = files.read_file(dir.path(tmp, "MyAddon.toc"))
      local count = 0
      for _ in toc:gmatch("Libs[/\\]WoWRocks[/\\]WowRocks%.xml") do
         count = count + 1
      end
      assert.equal(1, count)
      assert.matches("## Interface: 120100\nLibs/WoWRocks/WowRocks%.xml\nMyAddon.lua", toc)
   end)

   it("addon create writes a named folder, git inits, and requires busted --test", function()
      local cmd = table.concat({
         "cd", quote(tmp),
         "&&", quote(wowaddon),
         "create", "DemoAddon",
      }, " ")
      local out, ok, code = run(cmd)
      if type(code) == "number" then
         assert.equal(0, code, out)
      else
         assert.is_truthy(ok, out)
      end
      assert.is_true(fs.is_file(dir.path(tmp, "DemoAddon/DemoAddon.lua")))
      assert.is_true(fs.is_file(dir.path(tmp, "DemoAddon/DemoAddon.toc")))
      local lua = files.read_file(dir.path(tmp, "DemoAddon/DemoAddon.lua"))
      assert.matches("WoWRocks%.require", lua)
      local git_dir = dir.path(tmp, "DemoAddon/.git")
      if fs.is_tool_available("git", "git") then
         assert.is_true(fs.is_dir(git_dir) or fs.is_file(git_dir), out)
         assert.matches("git init", out)
      end
      assert.is_true(fs.is_file(dir.path(tmp, "DemoAddon/demoaddon-scm-1.rockspec")), out)
      local spec = files.read_file(dir.path(tmp, "DemoAddon/demoaddon-scm-1.rockspec"))
      assert.matches("test_dependencies", spec)
      assert.matches("busted", spec)
      assert.matches("added busted to test_dependencies", out)
      assert.is_true(fs.is_file(dir.path(tmp, "DemoAddon/spec/hello_spec.lua")), out)
      local hello = files.read_file(dir.path(tmp, "DemoAddon/spec/hello_spec.lua"))
      assert.matches("hello world", hello)
      local pkg = files.read_file(dir.path(tmp, "DemoAddon/.pkgmeta"))
      assert.matches("ignore:", pkg)
      assert.matches("- spec", pkg)
   end)

   it("addon test runs the vendored busted", function()
      local missing = table.concat({
         "cd", quote(tmp),
         "&&", quote(wowaddon),
         "test",
      }, " ")
      local out, ok, code = run(missing)
      if type(code) == "number" then
         assert.are_not.equal(0, code, out)
      else
         assert.is_falsy(ok, out)
      end
      assert.matches("busted not found", out)

      local bin = dir.path(tmp, "Libs/WoWRocks/bin/busted")
      files.write_file(bin, "#!/bin/sh\necho busted-ok \"$@\"\n")
      fs.set_permissions(bin, "exec", "all")
      local passing = table.concat({
         "cd", quote(tmp),
         "&&", quote(wowaddon),
         "test", "--", "spec/hello_spec.lua",
      }, " ")
      out, ok, code = run(passing)
      if type(code) == "number" then
         assert.equal(0, code, out)
      else
         assert.is_truthy(ok, out)
      end
      assert.matches("busted%-ok", out)
      assert.matches("spec/hello_spec%.lua", out)

      files.write_file(bin, "#!/bin/sh\nexit 1\n")
      fs.set_permissions(bin, "exec", "all")
      local failing = table.concat({
         "cd", quote(tmp),
         "&&", quote(wowaddon),
         "test",
      }, " ")
      out, ok, code = run(failing)
      if type(code) == "number" then
         assert.are_not.equal(0, code, out)
      else
         assert.is_falsy(ok, out)
      end
      assert.matches("tests failed", out)
   end)
end)
