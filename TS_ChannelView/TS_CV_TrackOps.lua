-- @noindex
-- Not a package of its own: installed by TS_ChannelView.lua's @provides.
--[[
  TS_CV_TrackOps.lua -- track-level operations behind the track menus.

  No drawing here: TS_CV_TrackMenu.lua is the UI, this is what it does.
  The parsing and folder arithmetic are pure functions over plain values
  so they can be checked offline; everything that touches REAPER is
  grouped at the bottom.

  FOLDERS. REAPER stores a folder tree as one number per track,
  I_FOLDERDEPTH, read in project order:

     1   this track opens a folder: the next track is one level deeper
     0   an ordinary track: the next track is at the same level
    -n   this track is the last one in n folders: the next track is n
         levels shallower

  So a track's level is the running sum of the depths of every track
  above it. Moving a contiguous block of tracks one level deeper or
  shallower, without disturbing anything after it, is two edits: the
  track just above the block, and the last track of the block. A folder
  parent always moves together with its children, so the block is the
  parent plus its whole subtree.

  I_FOLDERCOMPACT is the folder's state in REAPER's own track panel, and
  ChannelView shows the same three: 0 full (children as normal), 1 small
  (children drawn collapsed), 2 collapsed (children hidden). The folder
  button cycles them in that order, the way the track panel's own does.

  REORDERING goes through ReorderSelectedTracks, REAPER's own move, which
  keeps the folder structure consistent around the tracks it moves. What
  moves is the dragged track -- or the whole selection when the dragged
  track is part of it -- and every folder parent brings its children.

  TEMPLATES. A .RTrackTemplate file is plain track-chunk text, one
  <TRACK block per track it holds. The first track's PEAKCOL line is its
  colour, in the same native format as I_CUSTOMCOLOR: 0x1000000 set when
  a colour was actually chosen. Inserting one goes through
  Main_openProject, which is REAPER's own template import -- it creates
  fresh GUIDs, keeps a multi-track template's folders and internal sends
  intact, and places the tracks after the last touched track.

  CUSTOM COLOURS. REAPER's 16 custom colours (the row in its own colour
  dialog, and what SWS colour palettes load into) live in reaper.ini as
  one hex string, [REAPER] custcolors=: sixteen groups of four bytes,
  R G B and a pad byte, in that order. There is no ReaScript getter for
  them, so they are read from the config.
--]]

local TO = {}

-- ---------------------------------------------------------------------
-- folders (pure)
-- ---------------------------------------------------------------------

-- Level of every track, from the list of I_FOLDERDEPTH values in project
-- order. Level 1 is the first track of the list.
function TO.levels(depths)
  local out, lv = {}, 0
  for k = 1, #depths do
    out[k] = lv
    lv = lv + (depths[k] or 0)
  end
  return out
end

-- The last index of the block that starts at k: k itself for an ordinary
-- track, or the last track of its subtree for a folder parent. A folder
-- that never closes runs to the end of the list, which is how REAPER
-- treats it too.
function TO.block_end(depths, k)
  local d = depths[k] or 0
  if d <= 0 then return k end
  local base = TO.levels(depths)[k]
  local run = base + d
  for j = k + 1, #depths do
    run = run + (depths[j] or 0)
    if run <= base then return j end
  end
  return #depths
end

local function copy(t)
  local out = {}
  for i = 1, #t do out[i] = t[i] end
  return out
end

-- Can track k move one level deeper -- into the folder above it, or
-- becoming a child of the track above it? Returns the new depth list, or
-- nil and a short reason.
function TO.indent_plan(depths, k)
  if k <= 1 then
    return nil, "The first track has nothing above it to move into."
  end
  if (depths[k - 1] or 0) > 0 then
    return nil, "Already the first track in the folder above."
  end
  local b = TO.block_end(depths, k)
  local out = copy(depths)
  out[k - 1] = out[k - 1] + 1
  out[b] = out[b] - 1
  return out
end

-- Can track k move one level shallower, out of its folder? Only the last
-- block in a folder can: anything below it at the same level would
-- otherwise be pulled in underneath it. Returns the new depth list, or
-- nil and a short reason.
function TO.outdent_plan(depths, k)
  local lv = TO.levels(depths)
  if (lv[k] or 0) <= 0 then
    return nil, "Not inside a folder."
  end
  local b = TO.block_end(depths, k)
  if b < #depths and lv[b + 1] >= lv[k] then
    return nil, "Only the last track in a folder can move out of it."
  end
  local out = copy(depths)
  out[k - 1] = out[k - 1] - 1
  out[b] = out[b] + 1
  return out
end

-- How each track is shown given its ancestors' folder states. `depths`
-- and `compact` are parallel lists in project order. Returns three lists:
--   hidden[k]  true when an ancestor is collapsed (2)
--   folded[k]  true when an ancestor is small (1) and none is collapsed
--   by[k]      for a folded track, the indices of the small ancestors
function TO.folder_view(depths, compact)
  local hidden, folded, by = {}, {}, {}
  local stack = {}          -- one entry per open folder level: { mode, k }
  for k = 1, #depths do
    local h, f, who = false, false, nil
    for _, e in ipairs(stack) do
      if e.mode >= 2 then h = true
      elseif e.mode == 1 then
        f = true
        who = who or {}
        if who[#who] ~= e.k then who[#who + 1] = e.k end
      end
    end
    hidden[k] = h
    folded[k] = f and not h
    by[k]     = (f and not h) and who or nil

    local d = depths[k] or 0
    if d > 0 then
      local c = compact[k] or 0
      local mode = (c >= 2) and 2 or ((c >= 1) and 1 or 0)
      for _ = 1, d do stack[#stack + 1] = { mode = mode, k = k } end
    elseif d < 0 then
      for _ = 1, -d do table.remove(stack) end
    end
  end
  return hidden, folded, by
end

function TO.hidden_by_folders(depths, compact)
  return (TO.folder_view(depths, compact))
end

-- The indices that move when track k is dragged: k and, for a folder
-- parent, its whole subtree; or, when `selected` (a set of indices)
-- contains k, every selected track and their subtrees. Sorted.
function TO.move_set(depths, k, selected)
  local set = {}
  local starts = {}
  if selected and selected[k] then
    for i in pairs(selected) do starts[#starts + 1] = i end
  else
    starts[1] = k
  end
  for _, a in ipairs(starts) do
    for j = a, TO.block_end(depths, a) do set[j] = true end
  end
  local out = {}
  for i in pairs(set) do out[#out + 1] = i end
  table.sort(out)
  return out
end

-- Whether moving `idxs` (sorted, 1-based) to just before 1-based
-- position `before` (#depths + 1 = the end) changes anything. A drop
-- onto a moved track, or into the gap on either side of a contiguous
-- block, is not a move.
function TO.is_move(idxs, before)
  if #idxs == 0 then return false end
  for _, i in ipairs(idxs) do
    if i == before then return false end
  end
  local contiguous = (idxs[#idxs] - idxs[1] + 1) == #idxs
  if contiguous and before == idxs[#idxs] + 1 then return false end
  return true
end

-- ---------------------------------------------------------------------
-- colours (pure)
-- ---------------------------------------------------------------------

-- The custcolors hex string -> a list of { r, g, b }, up to 16. Anything
-- past the sixteenth group (REAPER appends a byte of its own) is ignored.
function TO.parse_custcolors(s)
  local out = {}
  s = s and s:match("^%s*(%x+)")
  if not s then return out end
  for i = 0, 15 do
    local g = s:sub(i * 8 + 1, i * 8 + 8)
    if #g < 8 then break end
    out[#out + 1] = { tonumber(g:sub(1, 2), 16),
                      tonumber(g:sub(3, 4), 16),
                      tonumber(g:sub(5, 6), 16) }
  end
  return out
end

-- The custcolors value out of a reaper.ini's text: the [REAPER] section
-- only, key matched case-insensitively.
function TO.custcolors_from_ini(text)
  if not text then return nil end
  local section = nil
  for line in (text .. "\n"):gmatch("([^\r\n]*)\r?\n") do
    local sec = line:match("^%s*%[(.-)%]%s*$")
    if sec then
      section = sec:upper()
    elseif section == "REAPER" then
      local k, v = line:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
      if k and k:lower() == "custcolors" then return v end
    end
  end
  return nil
end

-- The first track's colour in a track template, as a native colour
-- (0xRRGGBB or 0xBBGGRR depending on platform -- hand it to
-- reaper.ColorFromNative), or nil when that track has no colour set.
-- `head` only needs to be the start of the file: PEAKCOL sits in the
-- first few lines of the first <TRACK block.
function TO.template_colour(head)
  if not head then return nil end
  local v = head:match("^%s*PEAKCOL%s+(%-?%d+)")
         or head:match("\n%s*PEAKCOL%s+(%-?%d+)")
  v = tonumber(v)
  if not v then return nil end
  v = math.floor(v)
  if (v & 0x1000000) == 0 then return nil end
  return v & 0xffffff
end

-- "Drums/Kit 1.RTrackTemplate" -> "Kit 1". Case-insensitive on the
-- extension, since Windows file names are.
function TO.template_name(file)
  local base = file:match("([^\\/]+)$") or file
  return (base:gsub("%.[Rr][Tt][Rr][Aa][Cc][Kk][Tt][Ee][Mm][Pp][Ll][Aa][Tt][Ee]$", ""))
end

function TO.is_template(file)
  return file:lower():match("%.rtracktemplate$") ~= nil
end

-- ---------------------------------------------------------------------
-- REAPER side
-- ---------------------------------------------------------------------

-- Every track's depth and compact state, in project order.
local function folder_state()
  local depths, compact = {}, {}
  for i = 0, reaper.CountTracks(0) - 1 do
    local tr = reaper.GetTrack(0, i)
    depths[i + 1]  = math.floor(reaper.GetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH") or 0)
    compact[i + 1] = math.floor(reaper.GetMediaTrackInfo_Value(tr, "I_FOLDERCOMPACT") or 0)
  end
  return depths, compact
end
TO.folder_state = folder_state

-- 1-based position of a track in the project, or nil for the master.
local function index_of(track)
  local n = reaper.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER")
  n = n and math.floor(n) or 0
  if n <= 0 then return nil end
  return n
end

function TO.is_master(track)
  return track ~= nil and track == reaper.GetMasterTrack(0)
end

function TO.is_folder_parent(track)
  if not track or TO.is_master(track) then return false end
  return (reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH") or 0) > 0.5
end

-- 0 full, 1 small (children collapsed), 2 collapsed (children hidden).
function TO.folder_mode(track)
  local c = reaper.GetMediaTrackInfo_Value(track, "I_FOLDERCOMPACT") or 0
  if c >= 1.5 then return 2 end
  if c >= 0.5 then return 1 end
  return 0
end

TO.FOLDER_MODE_NAME = { [0] = "Full", [1] = "Collapsed", [2] = "Hidden" }

function TO.set_folder_mode(tracks, mode)
  reaper.Undo_BeginBlock()
  for _, tr in ipairs(tracks) do
    if TO.is_folder_parent(tr) then
      reaper.SetMediaTrackInfo_Value(tr, "I_FOLDERCOMPACT", mode)
    end
  end
  reaper.Undo_EndBlock("ChannelView: folder children " ..
    TO.FOLDER_MODE_NAME[mode]:lower(), -1)
  reaper.TrackList_AdjustWindows(false)
end

-- Full -> collapsed -> hidden -> full, the track panel's own order.
function TO.cycle_folder(track)
  if not TO.is_folder_parent(track) then return false end
  TO.set_folder_mode({ track }, (TO.folder_mode(track) + 1) % 3)
  return true
end

-- Whether indent/outdent is possible for a track, and why not if not:
-- returns plan (or nil), reason.
function TO.folder_plan(track, deeper)
  local k = track and index_of(track)
  if not k then return nil, "The master track has no folder level." end
  local depths = folder_state()
  if deeper then return TO.indent_plan(depths, k) end
  return TO.outdent_plan(depths, k)
end

function TO.move_level(track, deeper)
  local plan = TO.folder_plan(track, deeper)
  if not plan then return false end
  local depths = folder_state()
  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)
  for i = 1, #plan do
    if plan[i] ~= depths[i] then
      reaper.SetMediaTrackInfo_Value(reaper.GetTrack(0, i - 1), "I_FOLDERDEPTH", plan[i])
    end
  end
  reaper.PreventUIRefresh(-1)
  reaper.Undo_EndBlock(deeper and "ChannelView: move track into folder"
                               or "ChannelView: move track out of folder", -1)
  reaper.TrackList_AdjustWindows(false)
  return true
end

function TO.name(track)
  local _, nm = reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
  return nm or ""
end

function TO.rename(track, name)
  if not track or TO.is_master(track) then return false end
  reaper.Undo_BeginBlock()
  reaper.GetSetMediaTrackInfo_String(track, "P_NAME", name or "", true)
  reaper.Undo_EndBlock("ChannelView: rename track", -1)
  return true
end

function TO.has_spacer(track)
  return (reaper.GetMediaTrackInfo_Value(track, "I_SPACER") or 0) > 0.5
end

function TO.set_spacer(tracks, on)
  reaper.Undo_BeginBlock()
  for _, tr in ipairs(tracks) do
    if not TO.is_master(tr) then
      reaper.SetMediaTrackInfo_Value(tr, "I_SPACER", on and 1 or 0)
    end
  end
  reaper.Undo_EndBlock(on and "ChannelView: add track spacer"
                           or "ChannelView: remove track spacer", -1)
  reaper.TrackList_AdjustWindows(false)
end

-- rgb: 0xRRGGBB, or nil to clear back to the theme's default colour.
function TO.set_colour(tracks, rgb)
  local native = 0
  if rgb then
    native = reaper.ColorToNative((rgb >> 16) & 0xff, (rgb >> 8) & 0xff, rgb & 0xff)
             | 0x1000000
  end
  reaper.Undo_BeginBlock()
  for _, tr in ipairs(tracks) do
    reaper.SetMediaTrackInfo_Value(tr, "I_CUSTOMCOLOR", native)
  end
  reaper.Undo_EndBlock(rgb and "ChannelView: set track colour"
                            or "ChannelView: remove track colour", -1)
  reaper.UpdateArrange()
end

-- A track's colour as 0xRRGGBB, or nil when it has none.
function TO.colour_rgb(track)
  local v = reaper.GetMediaTrackInfo_Value(track, "I_CUSTOMCOLOR")
  v = v and math.floor(v) or 0
  if (v & 0x1000000) == 0 then return nil end
  local r, g, b = reaper.ColorFromNative(v & 0xffffff)
  return (r << 16) | (g << 8) | b
end

-- REAPER's 16 custom colours as { r, g, b } triples. The live config
-- value is preferred where REAPER exposes it; otherwise reaper.ini, which
-- is where REAPER keeps them between sessions.
function TO.custom_colours()
  local s = nil
  if reaper.get_config_var_string then
    local ok, v = reaper.get_config_var_string("custcolors")
    if ok and v and v:match("^%s*%x+") then s = v end
  end
  if not s and reaper.get_ini_file then
    local fh = io.open(reaper.get_ini_file(), "r")
    if fh then
      s = TO.custcolors_from_ini(fh:read("a"))
      fh:close()
    end
  end
  return TO.parse_custcolors(s)
end

-- Drags a track to just before 0-based position `before` (the track
-- count for the end). Returns true when something moved. The moved
-- tracks end up selected, as after a drag in REAPER's track panel.
function TO.move_tracks(track, before)
  local k = track and index_of(track)
  if not k then return false end
  local depths = folder_state()
  local selected = {}
  for i = 0, reaper.CountSelectedTracks(0) - 1 do
    local j = index_of(reaper.GetSelectedTrack(0, i))
    if j then selected[j] = true end
  end
  local idxs = TO.move_set(depths, k, selected)
  if not TO.is_move(idxs, before + 1) then return false end

  local tracks = {}
  for _, i in ipairs(idxs) do tracks[#tracks + 1] = reaper.GetTrack(0, i - 1) end
  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)
  reaper.Main_OnCommand(40297, 0)          -- Track: Unselect all tracks
  for _, tr in ipairs(tracks) do reaper.SetTrackSelected(tr, true) end
  reaper.ReorderSelectedTracks(before, 0)
  reaper.PreventUIRefresh(-1)
  reaper.Undo_EndBlock(#tracks == 1 and "ChannelView: move track"
                                     or "ChannelView: move tracks", -1)
  reaper.TrackList_AdjustWindows(false)
  return true
end

-- The track to insert after: the one given, unless it's the master or
-- missing, in which case the last track in the project (so a new track
-- lands at the end). nil when the project has no tracks at all.
local function anchor_for(track)
  if track and not TO.is_master(track) and reaper.ValidatePtr2(0, track, "MediaTrack*") then
    return track
  end
  local n = reaper.CountTracks(0)
  if n > 0 then return reaper.GetTrack(0, n - 1) end
  return nil
end

-- REAPER's own inserts (new track, track template) both land after the
-- last touched track, so the anchor is made the only selected track and
-- the last touched one first. 40914: Track: Set first selected track as
-- last touched track.
local function touch(anchor)
  if not anchor then return end
  reaper.SetOnlyTrackSelected(anchor)
  reaper.Main_OnCommand(40914, 0)
end

function TO.insert_new(after)
  local anchor = anchor_for(after)
  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)
  touch(anchor)
  reaper.Main_OnCommand(40001, 0)   -- Track: Insert new track
  reaper.PreventUIRefresh(-1)
  reaper.Undo_EndBlock("ChannelView: insert new track", -1)
  reaper.TrackList_AdjustWindows(false)
  return true
end

function TO.insert_template(path, after)
  if not path then return false end
  local anchor = anchor_for(after)
  reaper.PreventUIRefresh(1)
  touch(anchor)
  reaper.PreventUIRefresh(-1)
  reaper.Main_openProject(path)
  reaper.TrackList_AdjustWindows(false)
  return true
end

-- For the send/receive menus: a new track, or a template's tracks, at the
-- end of the project, WITHOUT touching the selection -- the panel is
-- routing from the track you're on and should stay on it. Both return
-- the new (first) track, or nil.

local function selection()
  local out = {}
  for i = 0, reaper.CountSelectedTracks2(0, true) - 1 do
    out[#out + 1] = reaper.GetSelectedTrack2(0, i, true)
  end
  return out
end

local function restore(sel)
  reaper.Main_OnCommand(40297, 0)          -- Track: Unselect all tracks
  for _, tr in ipairs(sel) do
    if reaper.ValidatePtr2(0, tr, "MediaTrack*") then
      reaper.SetTrackSelected(tr, true)
    end
  end
  if #sel > 0 then reaper.Main_OnCommand(40914, 0) end   -- first selected is last touched
end

function TO.new_track_at_end()
  local n = reaper.CountTracks(0)
  reaper.Undo_BeginBlock()
  reaper.InsertTrackAtIndex(n, true)
  reaper.Undo_EndBlock("ChannelView: insert new track", -1)
  reaper.TrackList_AdjustWindows(false)
  return reaper.GetTrack(0, n)
end

function TO.template_at_end(path)
  if not path then return nil end
  local before = {}
  for i = 0, reaper.CountTracks(0) - 1 do before[reaper.GetTrack(0, i)] = true end
  local sel = selection()
  reaper.PreventUIRefresh(1)
  TO.insert_template(path, nil)            -- nil: after the last track
  local first = nil
  for i = 0, reaper.CountTracks(0) - 1 do
    local tr = reaper.GetTrack(0, i)
    if not before[tr] then first = tr break end
  end
  restore(sel)
  reaper.PreventUIRefresh(-1)
  return first
end

-- The TrackTemplates folder, with the platform's separator.
function TO.templates_dir()
  local root = reaper.GetResourcePath()
  local sep = root:find("\\", 1, true) and "\\" or "/"
  return root .. sep .. "TrackTemplates", sep
end

-- Reads just the start of a template -- enough for PEAKCOL, without
-- pulling in the plugin state that follows it.
local colour_cache = {}
local function template_colour_at(path)
  local c = colour_cache[path]
  if c == nil then
    local fh = io.open(path, "rb")
    local head = fh and fh:read(4096)
    if fh then fh:close() end
    c = TO.template_colour(head) or false
    colour_cache[path] = c
  end
  return c or nil
end

local function sort_ci(list, key)
  table.sort(list, function(a, b) return a[key]:lower() < b[key]:lower() end)
end

-- The TrackTemplates folder as a tree:
--   { dirs = { { name, node }... }, files = { { name, path, colour }... } }
-- where colour is a native colour or nil. Re-read every call; call it
-- once when a menu opens, not every frame.
function TO.list_templates()
  local root, sep = TO.templates_dir()
  local function scan(dir, depth)
    local node = { dirs = {}, files = {} }
    if depth > 8 then return node end
    reaper.EnumerateFiles(dir, -1)          -- drop REAPER's listing cache
    reaper.EnumerateSubdirectories(dir, -1)
    local i = 0
    while true do
      local f = reaper.EnumerateFiles(dir, i)
      if not f then break end
      if TO.is_template(f) then
        local path = dir .. sep .. f
        node.files[#node.files + 1] = { name = TO.template_name(f), path = path,
                                        colour = template_colour_at(path) }
      end
      i = i + 1
    end
    i = 0
    while true do
      local d = reaper.EnumerateSubdirectories(dir, i)
      if not d then break end
      local sub = scan(dir .. sep .. d, depth + 1)
      if #sub.files > 0 or #sub.dirs > 0 then
        node.dirs[#node.dirs + 1] = { name = d, node = sub }
      end
      i = i + 1
    end
    sort_ci(node.files, "name")
    sort_ci(node.dirs, "name")
    return node
  end
  return scan(root, 0)
end

return TO
