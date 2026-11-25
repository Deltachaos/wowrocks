local cli = {}

local DESCRIPTION = "LuaRocks drop-in that writes stringified WoW sources and WowRocks.xml"

function cli.commands()
   return {
      init = "luarocks.cmd.init",
      pack = "luarocks.cmd.pack",
      unpack = "luarocks.cmd.unpack",
      build = "luarocks.cmd.build",
      install = "luarocks.cmd.install",
      search = "luarocks.cmd.search",
      list = "luarocks.cmd.list",
      remove = "luarocks.cmd.remove",
      make = "luarocks.cmd.make",
      download = "luarocks.cmd.download",
      path = "luarocks.cmd.path",
      show = "luarocks.cmd.show",
      new_version = "luarocks.cmd.new_version",
      lint = "luarocks.cmd.lint",
      write_rockspec = "luarocks.cmd.write_rockspec",
      purge = "luarocks.cmd.purge",
      doc = "luarocks.cmd.doc",
      upload = "luarocks.cmd.upload",
      config = "luarocks.cmd.config",
      which = "luarocks.cmd.which",
      test = "luarocks.cmd.test",
      addon = "wowrocks.addon",
   }
end

function cli.run(...)
   local cmd = require("luarocks.cmd")
   require("wowrocks.wrap").install()
   cmd.run_command(DESCRIPTION, cli.commands(), "luarocks.cmd.external", ...)
end

return cli
