local dir = require("luarocks.dir")
local fs = require("luarocks.fs")
local util = require("luarocks.util")
local vers = require("luarocks.core.vers")

local files = require("wowrocks.util")
local pkgmeta = require("wowrocks.pkgmeta")

local externals = {}

local function require_tool(name)
   if not fs.is_tool_available(name, name) then
      return nil, name .. " is not available; install it to fetch " .. name .. " externals"
   end
   return true
end

local function run(tool, ...)
   local ok, err = require_tool(tool)
   if not ok then
      return nil, err
   end
   if not fs.execute(tool, ...) then
      local args = { ... }
      return nil, tool .. " " .. table.concat(args, " ") .. " failed"
   end
   return true
end

local function with_temp(name, fn)
   local tmp, err = fs.make_temp_dir(name)
   if not tmp then
      return nil, err
   end
   local ok, result_err = fn(tmp)
   fs.delete(tmp)
   if not ok then
      return nil, result_err
   end
   return true
end

local function unwrap_single_dir(root)
   local entries = {}
   for _, name in ipairs(fs.list_dir(root)) do
      if name ~= "." and name ~= ".." then
         entries[#entries + 1] = name
      end
   end
   if #entries == 1 then
      local only = dir.path(root, entries[1])
      if fs.is_dir(only) then
         return only
      end
   end
   return root
end

local function apply_path(root, subpath)
   if not subpath or subpath == "" then
      return root
   end
   local dest = dir.path(root, subpath)
   if not fs.exists(dest) then
      return nil, "external path not found: " .. subpath
   end
   return dest
end

local function replace_dest(src, dest)
   dest = fs.absolute_name(dest)
   if fs.exists(dest) then
      fs.delete(dest)
   end
   local parent = dir.dir_name(dest)
   if parent ~= "" then
      local ok, err = fs.make_dir(parent)
      if not ok then
         return nil, err
      end
   end
   if fs.is_file(src) then
      return fs.copy(src, dest)
   end
   local ok, err = fs.make_dir(dest)
   if not ok then
      return nil, err
   end
   return fs.copy_contents(src, dest)
end

function externals.guess_type(spec)
   if spec.type and spec.type ~= "" then
      return spec.type
   end
   local url = spec.url or ""
   if url:match("%.zip$") or url:match("%.zip%?") then
      return "zip"
   end
   if url:match("^svn://") or url:match("/trunk") or url:match("/trunk/") then
      return "svn"
   end
   return "git"
end

function externals.normalize(dest, value)
   local spec
   if type(value) == "string" then
      spec = { url = value }
   elseif type(value) == "table" then
      spec = {
         url = value.url,
         type = value.type,
         tag = value.tag,
         branch = value.branch,
         commit = value.commit,
         path = value.path,
      }
   else
      return nil, "invalid external for " .. dest
   end
   spec.dest = dest
   if not spec.url or spec.url == "" then
      return nil, "external " .. dest .. " is missing a url"
   end
   spec.type = externals.guess_type(spec)
   return spec
end

local function latest_git_tag(repo)
   local cmd = "git -C " .. fs.Q(repo) .. " tag --list"
   local out = util.popen_read(cmd, "*a")
   local tags = {}
   for tag in (out or ""):gmatch("[^\r\n]+") do
      if tag ~= "" then
         tags[#tags + 1] = tag
      end
   end
   if #tags == 0 then
      return nil, "no git tags"
   end
   table.sort(tags, function(a, b)
      return vers.compare_versions(a, b)
   end)
   return tags[1]
end

local function latest_hg_tag(repo)
   local cmd = "hg -R " .. fs.Q(repo) .. " tags -q"
   local out = util.popen_read(cmd, "*a")
   local tags = {}
   for tag in (out or ""):gmatch("[^\r\n]+") do
      if tag ~= "" and tag ~= "tip" then
         tags[#tags + 1] = tag
      end
   end
   if #tags == 0 then
      return nil, "no hg tags"
   end
   table.sort(tags, function(a, b)
      return vers.compare_versions(a, b)
   end)
   return tags[1]
end

local function git_checkout(repo, spec)
   local ref
   if spec.tag == "latest" then
      local err
      ref, err = latest_git_tag(repo)
      if not ref then
         return nil, err
      end
   elseif spec.tag then
      ref = spec.tag
   elseif spec.branch then
      ref = spec.branch
   elseif spec.commit then
      ref = spec.commit
   end
   if not ref then
      return true
   end
   return run("git", "-C", repo, "checkout", ref)
end

local function hg_update(repo, spec)
   local ref
   if spec.tag == "latest" then
      local err
      ref, err = latest_hg_tag(repo)
      if not ref then
         return nil, err
      end
   elseif spec.tag then
      ref = spec.tag
   elseif spec.branch then
      ref = spec.branch
   elseif spec.commit then
      ref = spec.commit
   end
   if not ref then
      return true
   end
   return run("hg", "-R", repo, "update", "-r", ref)
end

local function fetch_zip_archive(url, zipfile)
   if fs.is_file(url) then
      return fs.copy(url, zipfile)
   end
   local path = url:match("^file://(.*)$")
   if path then
      if not fs.is_file(path) then
         return nil, "file not found: " .. path
      end
      return fs.copy(path, zipfile)
   end
   local ok, err = fs.download(url, zipfile)
   if not ok then
      return nil, "download failed: " .. tostring(err)
   end
   return true
end

local function unzip_into(zipfile, dest_dir)
   local ok, err = fs.make_dir(dest_dir)
   if not ok then
      return nil, err
   end
   if fs.unzip then
      ok, err = fs.change_dir(dest_dir)
      if not ok then
         return nil, err
      end
      ok, err = fs.unzip(zipfile)
      fs.pop_dir()
      return ok, err
   end
   return run("unzip", "-o", zipfile, "-d", dest_dir)
end

local function fetch_zip(spec)
   return with_temp("wowrocks-zip", function(tmp)
      local zipfile = dir.path(tmp, "archive.zip")
      local unpack_dir = dir.path(tmp, "unpack")
      local ok, err = fetch_zip_archive(spec.url, zipfile)
      if not ok then
         return nil, err
      end
      ok, err = unzip_into(zipfile, unpack_dir)
      if not ok then
         return nil, err
      end
      local src = unwrap_single_dir(unpack_dir)
      src, err = apply_path(src, spec.path)
      if not src then
         return nil, err
      end
      return replace_dest(src, spec.dest)
   end)
end

local function fetch_git(spec)
   return with_temp("wowrocks-git", function(tmp)
      local checkout = dir.path(tmp, "src")
      local ok, err = run("git", "clone", spec.url, checkout)
      if not ok then
         return nil, err
      end
      ok, err = git_checkout(checkout, spec)
      if not ok then
         return nil, err
      end
      local src
      src, err = apply_path(checkout, spec.path)
      if not src then
         return nil, err
      end
      return replace_dest(src, spec.dest)
   end)
end

local function fetch_svn(spec)
   return with_temp("wowrocks-svn", function(tmp)
      local checkout = dir.path(tmp, "src")
      local ok, err
      if spec.tag and spec.tag ~= "latest" then
         ok, err = run("svn", "checkout", "-r", spec.tag, spec.url, checkout)
      else
         ok, err = run("svn", "checkout", spec.url, checkout)
      end
      if not ok then
         return nil, err
      end
      local src
      src, err = apply_path(checkout, spec.path)
      if not src then
         return nil, err
      end
      return replace_dest(src, spec.dest)
   end)
end

local function fetch_hg(spec)
   return with_temp("wowrocks-hg", function(tmp)
      local checkout = dir.path(tmp, "src")
      local ok, err = run("hg", "clone", spec.url, checkout)
      if not ok then
         return nil, err
      end
      ok, err = hg_update(checkout, spec)
      if not ok then
         return nil, err
      end
      local src
      src, err = apply_path(checkout, spec.path)
      if not src then
         return nil, err
      end
      return replace_dest(src, spec.dest)
   end)
end

function externals.fetch_one(dest, value)
   local spec, err = externals.normalize(dest, value)
   if not spec then
      return nil, err
   end
   util.printout("WowRocks: fetching " .. dest .. " (" .. spec.type .. ")")
   if spec.type == "zip" then
      return fetch_zip(spec)
   elseif spec.type == "svn" then
      return fetch_svn(spec)
   elseif spec.type == "hg" then
      return fetch_hg(spec)
   elseif spec.type == "git" then
      return fetch_git(spec)
   end
   return nil, "unsupported external type: " .. tostring(spec.type)
end

function externals.fetch_all(opts)
   opts = opts or {}
   if not fs.exists(".pkgmeta") then
      if opts.optional then
         util.printout("WowRocks: skipping externals (no .pkgmeta)")
         return true
      end
      return nil, "no .pkgmeta in the current directory"
   end
   local meta, err = pkgmeta.load()
   if not meta then
      return nil, err
   end
   local entries = meta.externals
   if type(entries) ~= "table" then
      util.printout("WowRocks: no externals in .pkgmeta")
      return true
   end
   for _, dest in ipairs(files.sorted_keys(entries)) do
      local ok, fetch_err = externals.fetch_one(dest, entries[dest])
      if not ok then
         return nil, fetch_err
      end
   end
   return true
end

return externals
