--[[
  TS_CV_FXIndex.lua -- REAPER's own plugin metadata: Developers, Categories
  and your FX Folders.

  These are exactly the three trees in REAPER's Add FX browser, and they
  are worth reading rather than reinventing. Parsing the developer out of
  a plugin's display name almost works and then doesn't: REAPER appends a
  channel-config suffix AFTER the vendor tag for multi-output instruments
  ("BM-COZY (UJAM) (32 out)"), so a naive "last parenthetical" rule fills
  the list with "32 out" and "4->8ch". REAPER has already done this
  properly and written the answer down.

  Two files, both in the resource path:

    reaper-fxtags.ini     [developer]  <plugin file> = <developer>
                          [category]   <plugin file> = <category>[|...]
    reaper-fxfolders.ini  [Folders]    Name<n> = <your folder's name>
                          [Folder<n>]  Item<m> = <full path to a plugin>

  Keys are plugin FILENAMES, sometimes with a "<hash" suffix for shell
  plugins, while folder items are full paths -- so everything is matched
  on a normalised basename. JS effects aren't tagged by REAPER at all;
  they fall back to the vendor parsed from their name, or to no developer.
--]]

local U = require("TS_CV_Util")

local IX = {}

local built    = false
local dev_of   = {}    -- norm key -> developer
local cats_of  = {}    -- norm key -> { category, ... }
local fold_of  = {}    -- norm key -> { [folder id] = true }
local folders  = {}    -- ordered { id, name }
local stats    = { tagged = 0, folders = 0, resolved = 0, total = 0 }

-- ---------------------------------------------------------------------

-- Plugin identifiers arrive in several shapes -- a bare filename, a full
-- path, sometimes a "vst3:" style prefix, sometimes a "<hash" shell
-- suffix. Reduce them all to one comparable key.
local function norm_key(s)
  s = tostring(s or "")
  s = s:gsub("^[%a][%w][%w]*:%s*", "")   -- "vst3:" but never a "C:" drive
  s = s:match("([^/\\]+)$") or s         -- basename
  s = s:gsub("<.*$", "")                 -- shell-plugin hash suffix
  s = s:lower():gsub("[%s_]+", "_")      -- spaces and underscores are the same
  return s
end
IX.norm_key = norm_key

local function read_lines(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local out = {}
  for line in f:lines() do out[#out + 1] = (line:gsub("\r$", "")) end
  f:close()
  return out
end

local function load_tags(res)
  local lines = read_lines(res .. "/reaper-fxtags.ini")
  if not lines then return end
  local section
  for _, line in ipairs(lines) do
    local sect = line:match("^%[(.-)%]%s*$")
    if sect then
      section = sect:lower()
    elseif section == "developer" or section == "category" then
      local k, v = line:match("^(.-)=(.*)$")
      if k and v and v ~= "" then
        local key = norm_key(k)
        if section == "developer" then
          dev_of[key] = U.trim(v)
          stats.tagged = stats.tagged + 1
        else
          local list = {}
          for c in v:gmatch("[^|]+") do
            c = U.trim(c)
            if c ~= "" then list[#list + 1] = c end
          end
          if #list > 0 then cats_of[key] = list end
        end
      end
    end
  end
end

local function load_folders(res)
  local lines = read_lines(res .. "/reaper-fxfolders.ini")
  if not lines then return end

  local names, section = {}, nil
  for _, line in ipairs(lines) do
    local sect = line:match("^%[(.-)%]%s*$")
    if sect then
      section = sect
    elseif section == "Folders" then
      local n, v = line:match("^Name(%d+)=(.*)$")
      if n then names[tonumber(n)] = U.trim(v) end
    else
      local fid = section and section:match("^Folder(%d+)$")
      if fid then
        local item = line:match("^Item%d+=(.*)$")
        if item and item ~= "" then
          local key = norm_key(item)
          fold_of[key] = fold_of[key] or {}
          fold_of[key][tonumber(fid)] = true
        end
      end
    end
  end

  for id, name in pairs(names) do
    -- Separator rows ("--------") are dividers in REAPER's own tree, not
    -- folders anyone wants to filter by.
    if name ~= "" and not name:match("^%-+$") then
      folders[#folders + 1] = { id = id, name = name }
    end
  end
  table.sort(folders, function(a, b) return a.id < b.id end)
  stats.folders = #folders
end

function IX.load()
  if built then return end
  built = true
  local res = reaper.GetResourcePath()
  load_tags(res)
  load_folders(res)
end

-- ---------------------------------------------------------------------

-- Attaches .dev / .cats / .folders to each entry and returns the filter
-- lists, with counts taken over what's actually installed.
function IX.build(list)
  IX.load()

  local dev_count, cat_count, fold_count = {}, {}, {}
  stats.resolved, stats.total = 0, #list

  for _, e in ipairs(list) do
    local key = norm_key(e.ident)
    -- REAPER's tag wins; the name-parsed vendor is the fallback, which is
    -- what covers JS effects since REAPER doesn't tag those.
    local d = dev_of[key] or (e.vendor ~= "" and e.vendor or nil)
    e.dev     = d
    e.cats    = cats_of[key]
    e.folders = fold_of[key]
    e.key     = key

    if dev_of[key] then stats.resolved = stats.resolved + 1 end
    if d then dev_count[d] = (dev_count[d] or 0) + 1 end
    for _, c in ipairs(e.cats or {}) do
      cat_count[c] = (cat_count[c] or 0) + 1
    end
    for fid in pairs(e.folders or {}) do
      fold_count[fid] = (fold_count[fid] or 0) + 1
    end
  end

  local devs = {}
  for name, n in pairs(dev_count) do devs[#devs + 1] = { name = name, count = n } end
  table.sort(devs, function(a, b) return a.name:lower() < b.name:lower() end)

  local cats = {}
  for name, n in pairs(cat_count) do cats[#cats + 1] = { name = name, count = n } end
  table.sort(cats, function(a, b) return a.name:lower() < b.name:lower() end)

  local folds = {}
  for _, f in ipairs(folders) do
    local n = fold_count[f.id] or 0
    if n > 0 then folds[#folds + 1] = { id = f.id, name = f.name, count = n } end
  end

  return devs, cats, folds
end

function IX.stats() return stats end

return IX
