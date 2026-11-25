package = "simple"
version = "1.0-1"
source = { url = "file://." }
description = { summary = "fixture" }
dependencies = { "lua >= 5.1" }
build = {
  type = "builtin",
  modules = { simple = "simple.lua" },
}
