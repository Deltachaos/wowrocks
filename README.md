<div align="center">

# wowrocks

The Lua package manager for World of Warcraft addons.

<img src="assets/logo.svg" alt="wowrocks logo" width="100%">

[![Lua](https://img.shields.io/badge/Lua-5.1%2B-2C2D72?style=flat-square&logo=lua&logoColor=white)](https://www.lua.org/)
[![LuaRocks](https://img.shields.io/badge/LuaRocks-3.x-6B4FBB?style=flat-square)](https://luarocks.org/)
[![License](https://img.shields.io/badge/license-MIT-blue?style=flat-square)](#license)

</div>

## What is wowrocks?

wowrocks is the Lua package manager for World of Warcraft addons. It is built on [LuaRocks](https://luarocks.org/), so rockspecs and dependency constraints are already familiar if you have used LuaRocks before.

Day to day you use `wowrocks addon`, or the same commands through the shorter `wowaddon` name. They create an addon project, add LuaRocks packages and repository externals, and install them into the addon. World of Warcraft ships without Lua's `require`. wowrocks fills that in for you, so libraries keep the same `require` calls they use everywhere else.

## Features

- **`wowrocks addon` and `wowaddon`.** Create a project, install dependencies, require a LuaRocks package or a git URL, and download `.pkgmeta` externals. `install` and `require` scaffold the project if you have not run `init`. Both names run the same commands.
- **Familiar to LuaRocks users.** Dependencies live in a rockspec, with the same version constraints LuaRocks already uses.
- **`require` that works in WoW.** Installed libraries load through ordinary `require` calls inside the addon.

## Installation

wowrocks needs a Lua interpreter and [LuaRocks](https://luarocks.org/) 3.x.

```bash
luarocks install wowrocks
```

## Quick Start

Create an addon folder, then add a dependency. `wowaddon` is the short form of `wowrocks addon`.

```bash
wowrocks addon create MyAddon
cd MyAddon
wowaddon require dkjson
wowaddon require https://github.com/WoWUIDev/Ace3
```

`create` writes a starter TOC and Lua file, runs `git init` when git is on PATH, then `wowaddon require busted --test` in the new directory. `require` and `install` scaffold the rest of the project if needed (gitignore, rockspec, TOC), then install. `init` does that scaffold explicitly. `require` adds a LuaRocks package to the rockspec, or records a repository URL as a `.pkgmeta` external, then installs it.

## Existing addons

From the addon directory, `init` wires wowrocks into a project you already have. It writes the missing scaffold files, vendors dependencies into `Libs/WoWRocks`, and adds `Libs/WoWRocks/WowRocks.xml` after the TOC header.

```bash
cd MyExistingAddon
wowaddon init
wowaddon require dkjson
wowaddon require https://github.com/WoWUIDev/Ace3
```

`install` and `require` also scaffold if those files are missing, so you can skip `init` and start with `wowaddon require`. In your Lua files, take `require` from WowRocks:

```lua
local require = WoWRocks.require
local json = require("dkjson")
```

## Documentation

This README is the project reference.

### Addon commands

```bash
wowrocks addon create MyAddon
wowrocks addon init
wowrocks addon install
wowrocks addon require dkjson
wowaddon require busted --test
wowaddon require https://github.com/WoWUIDev/Ace3
wowaddon require https://github.com/WoWUIDev/Ace3 --path SomeSubPath/LibStub
wowaddon require https://github.com/WoWUIDev/Ace3 --path SomeSubPath/LibStub --dir Vendor/LibStub
wowrocks addon externals
wowaddon test
wowaddon help
```

`wowrocks addon install` installs every rockspec's runtime dependencies into `Libs/WoWRocks`. `--test` also installs `test_dependencies`.

```bash
wowrocks install --only-deps --tree ./Libs/WoWRocks *.rockspec
```

It then downloads `.pkgmeta` externals (skipped when there is no `.pkgmeta`, or with `--no-externals`) and adds `Libs/WoWRocks/WowRocks.xml` after the TOC header as the first include when that line is missing (skipped when there is no TOC, or with `--no-autoload`).

`wowrocks addon create <name>` makes a `name/` directory with `name.toc` and a starter `name.lua`, runs `git init` when git is available, then `wowaddon require busted --test` in that directory.

`wowrocks addon install` and `wowaddon require` scaffold the project when files are missing: `.gitignore`, a TOC, an `scm-1` rockspec, `spec/hello_spec.lua`, and a `.pkgmeta` that ignores `spec` so tests stay out of packaged releases. `wowrocks addon init` is optional and does that scaffold explicitly, also ensuring `libstdshim` and `varpackage` on an existing rockspec, then runs `addon install`. Name and description are taken from files already in the project.

`wowaddon require` adds a LuaRocks package to the rockspec, or a URL to `.pkgmeta` `externals`. `--test` adds a package to `test_dependencies` instead. Generated rockspecs list `busted` as a test dependency. `wowrocks addon install --test` also installs those test dependencies.

`wowaddon test` runs `./Libs/WoWRocks/bin/busted`. Extra arguments after `--` are forwarded to busted. If busted is missing, run `wowaddon install --test` first.

The default destination for a URL is `Libs/<repo>`. `--path` copies a subdirectory and names the destination after that folder. `--dir` sets the destination path.

### Package replicas

After a command that changes installed modules (`install`, `make`, `remove`, `build`, `purge`), wowrocks refreshes a stringified replica of `share/lua/<ver>` and a `WowRocks.xml` include list in that tree. It also writes `WowRocks.lua` beside that XML and includes it last, so the addon can build `require` once the module sources are registered. `share/lua/<ver>` stays as LuaRocks wrote it. Read-only commands such as `show`, `list`, and `search` pass through unchanged.

```bash
wowrocks install dkjson --tree ./vendor
wowrocks make --tree ./vendor MyAddon-1.0-1.rockspec
wowrocks install --only-deps --tree ./vendor MyAddon-1.0-1.rockspec
wowrocks remove dkjson --tree ./vendor
```

```text
vendor/
  share/lua/5.1/          # LuaRocks, as installed
  lib/luarocks/...
  bin/
  wow/lua/5.1/...         # stringified replica
  WowRocks.lua            # require bootstrap, loaded last
  WowRocks.xml            # module includes, then WowRocks.lua
```

Each replica file stores the original source on `_G.__wowrocks`:

```lua
_G.__wowrocks = _G.__wowrocks or {}
_G.__wowrocks["share/lua/5.1/busted/init.lua"] = [=[
-- original source
]=]
```

## Contributing

Issues and pull requests are welcome. Please keep changes focused and covered by tests.

```bash
luarocks install busted
busted
```

## License

MIT License
