local wrap = {}

local TREE_COMMANDS = {
   "install",
   "make",
   "remove",
   "build",
   "purge",
}

local installed = false
local depth = 0

local unpack = table.unpack or unpack

local function pack(...)
   return { n = select("#", ...), ... }
end

local function wrap_command(mod)
   local original = mod.command
   if not original or mod._wowrocks_wrapped then
      return
   end
   mod._wowrocks_wrapped = true
   mod.command = function(...)
      depth = depth + 1
      local results = pack(original(...))
      depth = depth - 1
      if results[1] and depth == 0 then
         local hook = require("wowrocks.hook")
         local ok, err = hook.after_tree_change()
         if not ok then
            return nil, err
         end
      end
      return unpack(results, 1, results.n)
   end
end

function wrap.install()
   if installed then
      return
   end
   installed = true
   for _, name in ipairs(TREE_COMMANDS) do
      local ok, mod = pcall(require, "luarocks.cmd." .. name)
      if ok and type(mod) == "table" then
         wrap_command(mod)
      end
   end
end

return wrap
