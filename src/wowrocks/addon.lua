local cfg = require("luarocks.core.cfg")
local dir = require("luarocks.dir")
local fs = require("luarocks.fs")
local path = require("luarocks.path")
local util = require("luarocks.util")
local install = require("luarocks.cmd.install")

local unpack = table.unpack or unpack

local toc = require("wowrocks.toc")
local project = require("wowrocks.project")
local externals = require("wowrocks.externals")

local addon = {}

addon.help_summary = "Manage a World of Warcraft addon project"
addon.help = [[
Install addon dependencies into Libs/WoWRocks, fetch .pkgmeta
externals, and keep TOC files pointing at WowRocks.xml.

`wowrocks addon install` is shorthand for:
  wowrocks install --only-deps --tree ./Libs/WoWRocks *.rockspec
then externals (unless --no-externals) and TOC autoload
(unless --no-autoload).
]]

local parser_cmd

local function add_skip_flags(cmd)
   cmd:flag("--no-externals", "Skip downloading .pkgmeta externals.")
   cmd:flag("--no-autoload", "Skip adding Libs/WoWRocks/WowRocks.xml to TOC files.")
   cmd:flag("--test", "Treat packages as test_dependencies, and install those too.")
end

function addon.add_to_parser(parser)
   local cmd = parser:command("addon", addon.help, util.see_also()):
   summary(addon.help_summary)
   cmd:command_target("addon_command")
   cmd:require_command(false)
   add_skip_flags(cmd)

   cmd:command("help", "Show help for addon commands.")

   cmd:command("install", [[
Scaffold the addon if needed, install every rockspec's dependencies
into ./Libs/WoWRocks, then fetch .pkgmeta externals and add
Libs/WoWRocks/WowRocks.xml to each TOC file.

Use --test to also install test_dependencies.

Equivalent to:
  wowrocks install --only-deps --tree ./Libs/WoWRocks *.rockspec
]])

   cmd:command("externals", "Download externals listed in .pkgmeta.")

   local require_cmd = cmd:command("require", [[
Scaffold the addon if needed, add a LuaRocks package to the rockspec
or a URL to .pkgmeta externals, then install.

Use --test to add a package to test_dependencies instead of dependencies.

A GitHub (or other) URL is recorded as an external, e.g.
  wowaddon require https://github.com/WoWUIDev/Ace3
writes:
  externals:
    Libs/Ace3:
      url: https://github.com/WoWUIDev/Ace3
]])
   require_cmd:argument("package", "Package name, dependency string, or repository URL.")
   require_cmd:option("--path", "Subdirectory inside the external repository to copy."):
   argname("<subdir>")
   require_cmd:option("--dir", "Destination directory for the external (default Libs/<name>)."):
   argname("<path>")

   local create_cmd = cmd:command("create", [[
Create a new addon directory in the current working directory with
<name>.toc and <name>.lua boilerplate, run git init if git is
available, then wowaddon require busted --test in that directory.
]])
   create_cmd:argument("name", "Addon folder and file name.")

   cmd:command("init", [[
Optional explicit scaffold: .gitignore, TOC, an scm-1 rockspec
(with libstdshim and varpackage), a hello-world busted spec, and a
.pkgmeta that ignores spec/, then run addon install.
install and require already do this when the project is missing files.
]])

   local test_cmd = cmd:command("test", [[
Run the addon test suite with the vendored busted:

  ./Libs/WoWRocks/bin/busted

If busted is missing, run wowaddon install --test first.
Use -- to pass flags through to busted.
]])
   test_cmd:argument("busted_args", "Arguments forwarded to busted."):
   args("*")

   parser_cmd = cmd
end

local function use_addon_tree(args)
   local root_dir = fs.absolute_name(toc.TREE)
   local ok, err = fs.make_dir(root_dir)
   if not ok then
      return nil, err
   end
   path.use_tree(root_dir)
   if (args.deps_mode or cfg.deps_mode) ~= "order" then
      table.insert(cfg.rocks_trees, 1, { name = "arg", root = root_dir })
   end
   cfg.variables.ROCKS_TREE = cfg.rocks_dir
   cfg.variables.SCRIPTS_DIR = cfg.deploy_bin_dir
   return root_dir
end

local function install_rockspecs(args)
   local rockspecs = project.list_rockspecs()
   if #rockspecs == 0 then
      return nil, "no rockspec in the current directory (run wowrocks addon init)"
   end
   local root_dir, err = use_addon_tree(args)
   if not root_dir then
      return nil, err
   end
   local lock
   lock, err = fs.lock_access(path.root_dir(cfg.root_dir), args.force_lock)
   if not lock then
      err = args.force_lock and
         ("failed to force the lock" .. (err and ": " .. err or "")) or
         ((err and err ~= "File exists") and err or "try --force-lock to overwrite the lock")
      return nil, "command 'addon install' requires exclusive write access to " .. root_dir .. " - " .. err
   end
   local result = { true }
   local call_ok, call_err = pcall(function()
      for _, rockspec in ipairs(rockspecs) do
         local iargs = {
            rock = rockspec,
            only_deps = true,
            no_doc = true,
            deps_mode = args.deps_mode,
            namespace = args.namespace,
            keep = args.keep,
            force = args.force,
            force_fast = args.force_fast,
            verify = args.verify,
            check_lua_versions = args.check_lua_versions,
            pin = args.pin,
         }
         local installed, install_err = install.command(iargs)
         if not installed then
            result = { nil, install_err }
            return
         end
         if args.test then
            local fetch = require("luarocks.fetch")
            local deps = require("luarocks.deps")
            local loaded, load_err = fetch.load_rockspec(rockspec)
            if not loaded then
               result = { nil, load_err }
               return
            end
            if loaded.test_dependencies and next(loaded.test_dependencies) then
               installed, install_err = deps.fulfill_dependencies(
                  loaded,
                  "test_dependencies",
                  deps.get_deps_mode(args),
                  args.verify
               )
               if not installed then
                  result = { nil, install_err }
                  return
               end
            end
         end
      end
   end)
   fs.unlock_access(lock)
   if not call_ok then
      return nil, tostring(call_err)
   end
   return result[1], result[2]
end

function addon.cmd_install(args)
   local ok, err = project.ensure_scaffold()
   if not ok then
      return nil, err
   end
   ok, err = install_rockspecs(args)
   if not ok then
      return nil, err
   end
   if not args.no_externals then
      ok, err = externals.fetch_all({ optional = true })
      if not ok then
         return nil, err
      end
   end
   if not args.no_autoload then
      ok, err = toc.ensure_all(true)
      if not ok then
         return nil, err
      end
   end
   return true
end

function addon.cmd_externals()
   return externals.fetch_all()
end

function addon.cmd_require(args)
   if not args.package or args.package == "" then
      return nil, "missing package name"
   end
   local ok, err = project.ensure_scaffold()
   if not ok then
      return nil, err
   end
   if project.is_url(args.package) then
      if args.test then
         return nil, "--test is only valid with a package name, not a URL"
      end
      local dest, spec_or_err = project.add_external(args.package, {
         path = args.path,
         dir = args.dir,
      })
      if not dest then
         return nil, spec_or_err
      end
      util.printout("WowRocks: added " .. dest .. " to .pkgmeta")
      return addon.cmd_install(args)
   end
   if args.path or args.dir then
      return nil, "--path and --dir are only valid with a URL"
   end
   local rockspec, list_name
   rockspec, list_name = project.add_require(args.package, { test = args.test })
   if not rockspec then
      return nil, list_name
   end
   util.printout("WowRocks: added " .. args.package .. " to " .. list_name .. " in " .. rockspec)
   return addon.cmd_install(args)
end

function addon.cmd_create(args)
   local name, err = project.create(args.name)
   if not name then
      return nil, err
   end
   local ok, chdir_err = fs.change_dir(name)
   if not ok then
      return nil, chdir_err
   end
   local result = { true }
   local call_ok, call_err = pcall(function()
      local inited, git_err = project.git_init()
      if inited == nil then
         result = { nil, git_err }
         return
      end
      if inited then
         util.printout("WowRocks: git init")
      end
      local require_ok, require_err = addon.cmd_require({
         package = "busted",
         test = true,
         no_externals = args.no_externals,
         no_autoload = args.no_autoload,
         deps_mode = args.deps_mode,
         namespace = args.namespace,
         keep = args.keep,
         force = args.force,
         force_fast = args.force_fast,
         verify = args.verify,
         check_lua_versions = args.check_lua_versions,
         pin = args.pin,
         force_lock = args.force_lock,
      })
      if not require_ok then
         result = { nil, require_err }
      end
   end)
   fs.pop_dir()
   if not call_ok then
      return nil, tostring(call_err)
   end
   return result[1], result[2]
end

function addon.busted_bin()
   local unix = dir.path(toc.TREE, "bin", "busted")
   if fs.is_file(unix) then
      return unix
   end
   local win = dir.path(toc.TREE, "bin", "busted.bat")
   if fs.is_file(win) then
      return win
   end
   return nil
end

function addon.cmd_test(args)
   local bin = addon.busted_bin()
   if not bin then
      return nil, dir.path(toc.TREE, "bin", "busted") .. " not found (run wowaddon install --test)"
   end
   local extra = args.busted_args or {}
   if not fs.execute(bin, unpack(extra)) then
      return nil, "tests failed"
   end
   return true
end

function addon.cmd_init(args)
   local ok, err = project.init_files()
   if not ok then
      return nil, err
   end
   return addon.cmd_install(args)
end

function addon.cmd_help()
   if parser_cmd then
      util.printout(parser_cmd:get_help())
   else
      util.printout(addon.help)
   end
   return true
end

function addon.command(args)
   local sub = args.addon_command
   if not sub or sub == "help" then
      return addon.cmd_help()
   end
   if sub == "install" then
      return addon.cmd_install(args)
   end
   if sub == "externals" then
      return addon.cmd_externals()
   end
   if sub == "require" then
      return addon.cmd_require(args)
   end
   if sub == "create" then
      return addon.cmd_create(args)
   end
   if sub == "init" then
      return addon.cmd_init(args)
   end
   if sub == "test" then
      return addon.cmd_test(args)
   end
   return nil, "unknown addon command: " .. tostring(sub)
end

function addon.needs_lock()
   return false
end

return addon
