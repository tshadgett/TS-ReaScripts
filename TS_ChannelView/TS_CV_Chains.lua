-- @noindex
-- Not a package of its own: installed by TS_ChannelView.lua's @provides.
--[[
  TS_CV_Chains.lua -- loading a saved FX chain onto a track.

  The chains are REAPER's own: every .RfxChain file under the FXChains
  folder in the resource path, subfolders as submenus, the same files
  REAPER's "Add FX chain" browser shows. Picking one adds its plugins to
  the end of the track's chain, or, with "Replace the existing FX" ticked,
  in place of everything already there. Either way it is one undo step.

  The menu is opened from the header bar but drawn from the main window
  (CN.open only records the request, CN.draw opens and draws it), for the
  same reason the track menus are: a popup's id belongs to the place it
  is opened, and the menu bar is a place of its own.
--]]

local C = require("TS_CV_Config")

local CN = {}
local ImGui

function CN.attach(imgui) ImGui = imgui end

local POPUP_ID = "cn_chains"
local REPLACE_KEY = "chain_replace"

local st = { req = false, track = nil, tree = nil }

-- ---------------------------------------------------------------------
-- pure
-- ---------------------------------------------------------------------

function CN.is_chain(file)
  return type(file) == "string" and file:lower():match("%.rfxchain$") ~= nil
end

-- "Lead Vocal.RfxChain" -> "Lead Vocal"
function CN.chain_name(file)
  return (file:gsub("%.[Rr][Ff][Xx][Cc][Hh][Aa][Ii][Nn]$", ""))
end

-- ---------------------------------------------------------------------
-- the FXChains folder
-- ---------------------------------------------------------------------

function CN.dir()
  local root = reaper.GetResourcePath()
  local sep = root:find("\\", 1, true) and "\\" or "/"
  return root .. sep .. "FXChains", sep
end

local function sort_ci(list)
  table.sort(list, function(a, b) return a.name:lower() < b.name:lower() end)
end

-- The folder as a tree: { dirs = { { name, node }... },
-- files = { { name, path, rel }... } }, where rel is the path under the
-- FXChains folder. Re-read every call; call it when the menu opens.
function CN.list()
  local root, sep = CN.dir()
  local function scan(dir, rel, depth)
    local node = { dirs = {}, files = {} }
    if depth > 8 then return node end
    reaper.EnumerateFiles(dir, -1)             -- drop REAPER's listing cache
    reaper.EnumerateSubdirectories(dir, -1)
    local i = 0
    while true do
      local f = reaper.EnumerateFiles(dir, i)
      if not f then break end
      if CN.is_chain(f) then
        node.files[#node.files + 1] = { name = CN.chain_name(f),
          path = dir .. sep .. f, rel = rel .. f }
      end
      i = i + 1
    end
    i = 0
    while true do
      local d = reaper.EnumerateSubdirectories(dir, i)
      if not d then break end
      local sub = scan(dir .. sep .. d, rel .. d .. sep, depth + 1)
      if #sub.files > 0 or #sub.dirs > 0 then
        node.dirs[#node.dirs + 1] = { name = d, node = sub }
      end
      i = i + 1
    end
    sort_ci(node.files)
    sort_ci(node.dirs)
    return node
  end
  return scan(root, "", 0)
end

function CN.replace_on()
  return reaper.GetExtState(C.EXT_SECT, REPLACE_KEY) == "1"
end

local function set_replace(on)
  reaper.SetExtState(C.EXT_SECT, REPLACE_KEY, on and "1" or "0", true)
end

-- Adds the chain `f` (an entry from CN.list) to the end of the track's
-- FX, or in place of them when `replace`. TrackFX_AddByName takes an
-- .RfxChain directly; it's given the path under FXChains first, the way
-- REAPER names chains itself, then the full path. Returns true when
-- anything was added; when nothing could be, the track is left as it was.
function CN.load(track, f, replace)
  if not track or not f then return false end
  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)
  local before = reaper.TrackFX_GetCount(track)
  local kept = {}
  if replace then
    -- Added first and the old ones removed after, so a chain that fails
    -- to load doesn't cost the track its existing plugins.
    for i = 0, before - 1 do kept[#kept + 1] = reaper.TrackFX_GetFXGUID(track, i) end
  end
  local ok = false
  for _, name in ipairs({ f.rel, f.path }) do
    reaper.TrackFX_AddByName(track, name, false, -1)
    if reaper.TrackFX_GetCount(track) > before then ok = true break end
  end
  if ok and replace then
    for i = reaper.TrackFX_GetCount(track) - 1, 0, -1 do
      local g = reaper.TrackFX_GetFXGUID(track, i)
      for _, k in ipairs(kept) do
        if g == k then reaper.TrackFX_Delete(track, i) break end
      end
    end
  end
  reaper.PreventUIRefresh(-1)
  reaper.Undo_EndBlock((replace and "ChannelView: replace FX with chain "
                                 or "ChannelView: load FX chain ") .. f.name, -1)
  return ok
end

-- ---------------------------------------------------------------------
-- the menu
-- ---------------------------------------------------------------------

function CN.open(track)
  st.req, st.track = true, track
end

local function valid(track)
  return track ~= nil and reaper.ValidatePtr2(0, track, "MediaTrack*")
end

local function track_label(track)
  if track == reaper.GetMasterTrack(0) then return "MASTER" end
  local _, n = reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
  local num = math.floor(reaper.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER") or 0)
  if n == nil or n == "" then return "Track " .. num end
  return ("%d  %s"):format(num, n)
end

local function items(ctx, node, pick)
  for _, d in ipairs(node.dirs) do
    if ImGui.BeginMenu(ctx, d.name) then
      items(ctx, d.node, pick)
      ImGui.EndMenu(ctx)
    end
  end
  for i, f in ipairs(node.files) do
    if ImGui.MenuItem(ctx, f.name .. "##cn" .. i) then pick(f) end
  end
end

-- Draws the menu when it's open. Call once per frame from the main
-- window, outside any child and outside the menu bar. Returns true on
-- the frame a chain was loaded.
function CN.draw(ctx)
  if st.req then
    st.req = false
    st.tree = CN.list()                   -- once per opening, not per frame
    ImGui.OpenPopup(ctx, POPUP_ID)
  end
  if not ImGui.BeginPopup(ctx, POPUP_ID) then return false end

  local tr = st.track
  if not valid(tr) then
    ImGui.CloseCurrentPopup(ctx)
    ImGui.EndPopup(ctx)
    return false
  end

  ImGui.TextDisabled(ctx, "Load an FX chain onto " .. track_label(tr))
  local rep = CN.replace_on()
  local chg, v = ImGui.Checkbox(ctx, "Replace the existing FX", rep)
  if chg then set_replace(v) end
  ImGui.Separator(ctx)

  local loaded = false
  local tree = st.tree
  if not tree or (#tree.files == 0 and #tree.dirs == 0) then
    ImGui.TextDisabled(ctx, "No FX chains found in")
    ImGui.TextDisabled(ctx, (CN.dir()))
  else
    items(ctx, tree, function(f)
      if CN.load(tr, f, CN.replace_on()) then
        loaded = true
      else
        reaper.MB("Couldn't load the FX chain\n\n" .. f.path, "ChannelView", 0)
      end
    end)
  end

  ImGui.EndPopup(ctx)
  return loaded
end

return CN
