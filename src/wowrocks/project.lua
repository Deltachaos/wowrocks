local persist = require("luarocks.persist")
local type_rockspec = require("luarocks.type.rockspec")
local dir = require("luarocks.dir")
local fs = require("luarocks.fs")

local files = require("wowrocks.util")
local pkgmeta = require("wowrocks.pkgmeta")
local toc = require("wowrocks.toc")

local project = {}

local DEFAULT_DEPS = { "libstdshim", "varpackage" }
local DEFAULT_TEST_DEPS = { "busted" }

function project.list_rockspecs()
   return files.list_files("%.rockspec$")
end

function project.resolve_name()
   local meta = pkgmeta.load()
   if meta and meta["package-as"] and tostring(meta["package-as"]) ~= "" then
      return tostring(meta["package-as"])
   end
   local dir_name = toc.dir_name()
   local stem = toc.main_stem(dir_name)
   return stem or dir_name
end

function project.select_rockspec(addon_name)
   local found = project.list_rockspecs()
   if #found == 0 then
      return nil, "no rockspec in the current directory (run wowrocks addon init)"
   end
   if #found == 1 then
      return found[1]
   end
   local want = addon_name and files.rock_name(addon_name)
   local scm_match, scm_any
   for _, name in ipairs(found) do
      if name:match("%-scm%-1%.rockspec$") then
         local tbl = persist.load_into_table(name)
         if tbl and want and tbl.package and tbl.package:lower() == want then
            scm_match = name
            break
         end
         scm_any = scm_any or name
      end
   end
   return scm_match or scm_any or found[1]
end

function project.set_dependency(deps, spec)
   local name = files.dep_name(spec)
   if not name then
      return nil, "invalid dependency: " .. tostring(spec)
   end
   for i, existing in ipairs(deps) do
      if files.dep_name(existing) == name then
         deps[i] = spec
         return true
      end
   end
   deps[#deps + 1] = spec
   return true
end

function project.ensure_dependency(deps, spec)
   local name = files.dep_name(spec)
   if not name then
      return nil, "invalid dependency: " .. tostring(spec)
   end
   for _, existing in ipairs(deps) do
      if files.dep_name(existing) == name then
         return false
      end
   end
   deps[#deps + 1] = spec
   return true
end

function project.save_rockspec(path, tbl)
   return persist.save_from_table(path, tbl, type_rockspec.order)
end

function project.add_require(spec, opts)
   opts = opts or {}
   local path, err = project.select_rockspec(project.resolve_name())
   if not path then
      return nil, err
   end
   local tbl, load_err = persist.load_into_table(path)
   if not tbl then
      return nil, load_err
   end
   local list_name = opts.test and "test_dependencies" or "dependencies"
   if opts.test then
      tbl.rockspec_format = tbl.rockspec_format or "3.0"
   end
   tbl[list_name] = tbl[list_name] or {}
   local ok, dep_err = project.set_dependency(tbl[list_name], spec)
   if not ok then
      return nil, dep_err
   end
   ok, err = project.save_rockspec(path, tbl)
   if not ok then
      return nil, err
   end
   return path, list_name
end

function project.is_url(spec)
   if not spec or spec == "" then
      return false
   end
   return spec:match("^https?://")
      or spec:match("^git://")
      or spec:match("^svn://")
      or spec:match("^git@")
      or spec:match("%.git$")
      or spec:match("%.zip$")
end

function project.url_basename(url)
   local trimmed = url:gsub("%.git$", ""):gsub("/+$", "")
   trimmed = trimmed:gsub("^[a-zA-Z][a-zA-Z0-9+.-]*://", "")
   trimmed = trimmed:gsub("^[^@]+@", "")
   trimmed = trimmed:gsub("^[^/]+:", "")
   local parts = {}
   for part in trimmed:gmatch("[^/]+") do
      if part ~= "trunk" and part ~= "tags" and part ~= "branches" then
         parts[#parts + 1] = part
      end
   end
   local name = parts[#parts] or "external"
   name = name:gsub("%.git$", "")
   return name
end

local function basename(path)
   path = path:gsub("\\", "/"):gsub("/+$", "")
   return path:match("([^/]+)$") or path
end

function project.external_dest(url, opts)
   opts = opts or {}
   if opts.dir and opts.dir ~= "" then
      return opts.dir:gsub("\\", "/")
   end
   local name
   if opts.path and opts.path ~= "" then
      name = basename(opts.path)
   else
      name = project.url_basename(url)
   end
   return "Libs/" .. name
end

function project.add_external(url, opts)
   opts = opts or {}
   local dest = project.external_dest(url, opts)
   local spec = { url = url }
   if opts.path and opts.path ~= "" then
      spec.path = opts.path:gsub("\\", "/")
   end
   local ok, err = pkgmeta.add_external(dest, spec)
   if not ok then
      return nil, err
   end
   return dest, spec
end

function project.ensure_gitignore()
   return files.append_line(".gitignore", toc.TREE)
end

-- true if git init ran, false if git is missing, nil+err on failure
function project.git_init()
   if not fs.is_tool_available("git", "git") then
      return false
   end
   if not fs.execute("git", "init") then
      return nil, "git init failed"
   end
   return true
end

function project.new_rockspec(name, info)
   info = info or {}
   local package_name = files.rock_name(name)
   local description = {
      summary = info.title or name,
      detailed = info.notes or info.title or name,
   }
   if info.author and info.author ~= "" then
      description.maintainer = info.author
   end
   return {
      rockspec_format = "3.0",
      package = package_name,
      version = "scm-1",
      source = {
         url = "file://.",
      },
      description = description,
      dependencies = {
         "lua >= 5.1",
         "libstdshim",
         "varpackage",
      },
      build = {
         type = "builtin",
         modules = {},
      },
      test_dependencies = {
         "busted",
      },
      test = {
         type = "busted",
      },
   }
end

project.LUA_BOILERPLATE = table.concat({
   "local addonName, ns = ...",
   "local require = WoWRocks.require",
   "",
   'local frame = CreateFrame("Frame")',
   'frame:RegisterEvent("ADDON_LOADED")',
   'frame:SetScript("OnEvent", function(self, event, name)',
   "\tif name ~= addonName then",
   "\t\treturn",
   "\tend",
   '\tself:UnregisterEvent("ADDON_LOADED")',
   '\tprint(addonName .. " loaded!")',
   "end)",
   "",
}, "\n")

project.HELLO_SPEC = table.concat({
   'describe("hello", function()',
   '   it("world", function()',
   '      assert.equal("hello world", "hello world")',
   "   end)",
   "end)",
   "",
}, "\n")

project.TEST_IGNORE = "spec"

function project.has_specs()
   if not fs.is_dir("spec") then
      return false
   end
   for _, name in ipairs(fs.list_dir("spec")) do
      if name:match("_spec%.lua$") and fs.is_file(dir.path("spec", name)) then
         return true
      end
   end
   return false
end

function project.ensure_hello_spec()
   local dest = dir.path("spec", "hello_spec.lua")
   if fs.exists(dest) or project.has_specs() then
      return false
   end
   local ok, err = files.write_file(dest, project.HELLO_SPEC)
   if not ok then
      return nil, err
   end
   return true
end

local function ignore_has_spec(ignore)
   if type(ignore) == "string" then
      return ignore == project.TEST_IGNORE or ignore == project.TEST_IGNORE .. "/"
   end
   if type(ignore) ~= "table" then
      return false
   end
   for _, item in ipairs(ignore) do
      if item == project.TEST_IGNORE or item == project.TEST_IGNORE .. "/" then
         return true
      end
   end
   return false
end

function project.ensure_pkgmeta(name)
   local path = ".pkgmeta"
   local meta = {}
   if fs.exists(path) then
      local loaded, err = pkgmeta.load(path)
      if not loaded then
         return nil, err
      end
      meta = loaded
   elseif name and name ~= "" then
      meta["package-as"] = name
   end
   if ignore_has_spec(meta.ignore) then
      return false
   end
   local ignore = meta.ignore
   if type(ignore) == "string" then
      ignore = { ignore }
   elseif type(ignore) ~= "table" then
      ignore = {}
   end
   ignore[#ignore + 1] = project.TEST_IGNORE
   meta.ignore = ignore
   local ok, err = pkgmeta.save(meta, path)
   if not ok then
      return nil, err
   end
   return true
end

function project.validate_addon_name(name)
   if not name or name == "" then
      return nil, "missing addon name"
   end
   if name:match("[/\\]") or name == "." or name == ".." then
      return nil, "addon name must be a single directory name"
   end
   return name
end

function project.create(name)
   local util = require("luarocks.util")
   local ok_name, err = project.validate_addon_name(name)
   if not ok_name then
      return nil, err
   end
   name = ok_name
   if fs.exists(name) then
      return nil, "directory already exists: " .. name
   end
   local ok, mkdir_err = fs.make_dir(name)
   if not ok then
      return nil, mkdir_err
   end
   local lua_name = name .. ".lua"
   local toc_name = name .. ".toc"
   ok, err = files.write_file(dir.path(name, lua_name), project.LUA_BOILERPLATE)
   if not ok then
      return nil, err
   end
   util.printout("WowRocks: wrote " .. dir.path(name, lua_name))
   local toc_content = toc.generate({
      title = name,
      notes = name,
      files = { lua_name },
   })
   ok, err = toc.write(dir.path(name, toc_name), toc_content)
   if not ok then
      return nil, err
   end
   util.printout("WowRocks: wrote " .. dir.path(name, toc_name))
   return name
end

local function toc_info(name)
   local tocs = toc.list()
   local info = {
      title = name,
      notes = name,
   }
   if #tocs == 0 then
      return info, nil
   end
   local main = toc.main_stem(toc.dir_name(), tocs)
   local toc_file = main and (main .. ".toc") or tocs[1]
   if not fs.is_file(toc_file) then
      toc_file = tocs[1]
   end
   local parsed = toc.parse_file(toc_file)
   if parsed then
      info.title = parsed.title or name
      info.notes = parsed.notes or info.title
      info.author = parsed.author
   end
   return info, toc_file
end

function project.ensure_scaffold()
   local util = require("luarocks.util")
   local ok, err = project.ensure_gitignore()
   if ok == nil then
      return nil, err
   end
   if ok then
      util.printout("WowRocks: added " .. toc.TREE .. " to .gitignore")
   end

   local name = project.resolve_name()
   local info, toc_file = toc_info(name)
   if not toc_file then
      local content = toc.generate({
         title = name,
         notes = name,
         files = toc.list_addon_files(),
      })
      ok, err = toc.write(name .. ".toc", content)
      if not ok then
         return nil, err
      end
      util.printout("WowRocks: wrote " .. name .. ".toc")
   end

   if #project.list_rockspecs() == 0 then
      local filename = files.rock_name(name) .. "-scm-1.rockspec"
      local tbl = project.new_rockspec(name, info)
      ok, err = project.save_rockspec(filename, tbl)
      if not ok then
         return nil, err
      end
      util.printout("WowRocks: wrote " .. filename)
   end

   ok, err = project.ensure_hello_spec()
   if ok == nil then
      return nil, err
   end
   if ok then
      util.printout("WowRocks: wrote spec/hello_spec.lua")
   end

   ok, err = project.ensure_pkgmeta(name)
   if ok == nil then
      return nil, err
   end
   if ok then
      util.printout("WowRocks: wrote .pkgmeta")
   end

   return true
end

function project.init_files()
   local util = require("luarocks.util")
   local ok, err = project.ensure_scaffold()
   if not ok then
      return nil, err
   end

   local path = project.select_rockspec(project.resolve_name())
   if not path then
      return nil, "no rockspec in the current directory"
   end
   local tbl, load_err = persist.load_into_table(path)
   if not tbl then
      return nil, load_err
   end
   tbl.dependencies = tbl.dependencies or {}
   tbl.test_dependencies = tbl.test_dependencies or {}
   local changed = false
   for _, dep in ipairs(DEFAULT_DEPS) do
      if project.ensure_dependency(tbl.dependencies, dep) then
         changed = true
      end
   end
   for _, dep in ipairs(DEFAULT_TEST_DEPS) do
      if project.ensure_dependency(tbl.test_dependencies, dep) then
         tbl.rockspec_format = tbl.rockspec_format or "3.0"
         changed = true
      end
   end
   if changed then
      ok, err = project.save_rockspec(path, tbl)
      if not ok then
         return nil, err
      end
      util.printout("WowRocks: updated dependencies in " .. path)
   end

   return true
end

return project
