-- @noindex
-- Not a package of its own: installed by TS_ChannelView.lua's @provides.
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

-- ---------------------------------------------------------------------
-- editing your FX Folders
-- ---------------------------------------------------------------------
-- reaper-fxfolders.ini, as REAPER's Add FX browser writes it:
--   [Folder<id>]  Item<n>=<plugin>  Nb=<count>  Type<n>=<kind>
--   [Folders]     Id<pos>=<id>  Name<pos>=<name>  NbFolders=<count>
-- Kinds: 3 VST/VST3, 2 JS, 7 CLAP, 1 LV2, 5 AU (1000 an FX chain and
-- 1048576 a smart folder, which are left exactly as they are). Every
-- other section of the file is kept as it was, in place.

-- The plugin kind for an installed plugin's name ("VST3: ..."), or nil.
function IX.kind_of(name)
  name = tostring(name or "")
  if name:match("^VST3?i?:") then return 3 end
  if name:match("^JS:") then return 2 end
  if name:match("^CLAPi?:") then return 7 end
  if name:match("^LV2i?:") then return 1 end
  if name:match("^AUi?:") then return 5 end
  return nil
end

-- The file's text -> { lines (everything that isn't a folder section),
-- folders = { [id] = { items, types } }, order = { { id, name } } }.
function IX.parse_folders(text)
  local m = { lines = {}, folders = {}, order = {} }
  local section, fid
  local ids, names = {}, {}
  for line in ((text or "") .. "\n"):gmatch("(.-)\r?\n") do
    local sect = line:match("^%[(.-)%]%s*$")
    if sect then
      section = sect
      fid = tonumber(sect:match("^Folder(%d+)$"))
      if fid then m.folders[fid] = m.folders[fid] or { items = {}, types = {} } end
      if not fid and sect ~= "Folders" then m.lines[#m.lines + 1] = line end
    elseif fid then
      local n, v = line:match("^Item(%d+)=(.*)$")
      if n then m.folders[fid].items[tonumber(n) + 1] = v end
      n, v = line:match("^Type(%d+)=(.*)$")
      if n then m.folders[fid].types[tonumber(n) + 1] = v end
    elseif section == "Folders" then
      local n, v = line:match("^Id(%d+)=(%d+)$")
      if n then ids[tonumber(n)] = tonumber(v) end
      n, v = line:match("^Name(%d+)=(.*)$")
      if n then names[tonumber(n)] = v end
    else
      m.lines[#m.lines + 1] = line
    end
  end
  local pos = {}
  for p in pairs(ids) do pos[#pos + 1] = p end
  table.sort(pos)
  for _, p in ipairs(pos) do
    m.order[#m.order + 1] = { id = ids[p], name = names[p] or "" }
    m.folders[ids[p]] = m.folders[ids[p]] or { items = {}, types = {} }
  end
  -- drop trailing blank lines from what's kept; they're written back once
  while #m.lines > 0 and m.lines[#m.lines]:match("^%s*$") do m.lines[#m.lines] = nil end
  return m
end

-- The model back to the file's text.
function IX.write_folders(m)
  local out = {}
  for _, l in ipairs(m.lines) do out[#out + 1] = l end
  if #out > 0 then out[#out + 1] = "" end
  local ids = {}
  for id in pairs(m.folders) do ids[#ids + 1] = id end
  table.sort(ids)
  for _, id in ipairs(ids) do
    local f = m.folders[id]
    out[#out + 1] = "[Folder" .. id .. "]"
    for k = 1, #f.items do
      if f.items[k] then out[#out + 1] = "Item" .. (k - 1) .. "=" .. f.items[k] end
    end
    out[#out + 1] = "Nb=" .. #f.items
    for k = 1, #f.items do
      if f.types[k] then out[#out + 1] = "Type" .. (k - 1) .. "=" .. f.types[k] end
    end
    out[#out + 1] = ""
  end
  out[#out + 1] = "[Folders]"
  for p, e in ipairs(m.order) do out[#out + 1] = "Id" .. (p - 1) .. "=" .. e.id end
  for p, e in ipairs(m.order) do out[#out + 1] = "Name" .. (p - 1) .. "=" .. e.name end
  out[#out + 1] = "NbFolders=" .. #m.order
  out[#out + 1] = ""
  return table.concat(out, "\n")
end

-- Whether folder `id` holds the plugin `ident` (matched the way the
-- picker matches: on a normalised file name).
function IX.folder_has(m, id, ident)
  local f = m.folders[id]
  if not f then return false end
  local key = norm_key(ident)
  for _, it in ipairs(f.items) do
    if norm_key(it) == key then return true end
  end
  return false
end

function IX.folder_add(m, id, ident, kind)
  local f = m.folders[id]
  if not f or not kind or IX.folder_has(m, id, ident) then return false end
  f.items[#f.items + 1] = ident
  f.types[#f.items] = tostring(kind)
  return true
end

function IX.folder_remove(m, id, ident)
  local f = m.folders[id]
  if not f then return false end
  local key, done = norm_key(ident), false
  for k = #f.items, 1, -1 do
    if norm_key(f.items[k]) == key then
      table.remove(f.items, k); table.remove(f.types, k); done = true
    end
  end
  return done
end

-- A new, empty folder at the end of the list. Returns its id.
function IX.folder_new(m, name)
  local id = -1
  for k in pairs(m.folders) do if k > id then id = k end end
  id = id + 1
  m.folders[id] = { items = {}, types = {} }
  m.order[#m.order + 1] = { id = id, name = name }
  return id
end

-- Removes folder `id` (the plugins themselves are untouched, of course).
function IX.folder_delete(m, id)
  if not m.folders[id] then return false end
  m.folders[id] = nil
  for p = #m.order, 1, -1 do
    if m.order[p].id == id then table.remove(m.order, p) end
  end
  return true
end

-- Whether a folder list entry is one of REAPER's separator rows.
function IX.is_separator(e)
  return e.name == "" or e.name:match("^%-+$") ~= nil
end

-- Your folders as the menus list them: separators ("------") left out.
function IX.folder_list(m)
  local out = {}
  for _, e in ipairs(m.order) do
    if e.name ~= "" and not e.name:match("^%-+$") then out[#out + 1] = e end
  end
  return out
end

local function folders_path() return reaper.GetResourcePath() .. "/reaper-fxfolders.ini" end

-- The file as it is now (an empty model when there isn't one yet).
function IX.read_folders()
  local f = io.open(folders_path(), "rb")
  local text = f and f:read("a") or ""
  if f then f:close() end
  return IX.parse_folders(text), text
end

-- Writes the model back, keeping the file as it was before as
-- reaper-fxfolders.ini.bak, and has the picker read it again. REAPER's own
-- browser keeps its copy in memory: it may need a restart to show this,
-- and a folder edit there could write over it.
function IX.save_folders(m, before)
  local path = folders_path()
  if before and before ~= "" then
    local b = io.open(path .. ".bak", "wb")
    if b then b:write(before); b:close() end
  end
  local f = io.open(path, "wb")
  if not f then return false end
  f:write(IX.write_folders(m))
  f:close()
  IX.reset()
  return true
end

-- Forget what was read, so the next look reads the files afresh.
function IX.reset()
  built, dev_of, cats_of, fold_of, folders = false, {}, {}, {}, {}
  stats = { tagged = 0, folders = 0, resolved = 0, total = 0 }
end

-- The folders file's size, to notice it changing (ChannelView's window
-- writes it; the web bridge is another script with its own copy).
function IX.folders_stamp()
  local f = io.open(folders_path(), "rb")
  if not f then return 0 end
  local n = f:seek("end")
  f:close()
  return n or 0
end

return IX
