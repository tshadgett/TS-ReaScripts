-- @description TS_360LinkFollow - SSL 360 Link follows track visibility (UF8 / UC1)
-- @author Tim Shadgett
-- @version 1.6.0
-- @changelog
--   Hidden tracks have SSL 360 Link removed; showing them inserts a fresh
--   instance in the same slot. (Taking it offline kept the plugin's saved
--   identity, which tracks made from the same template share, and SSL 360
--   ignored the copy that came back.)
--   360 Links are put back one at a time: SSL 360 drops connections when many
--   start at once. Each one is checked against SSL 360's log and replaced
--   again if its strip has not registered within a few seconds.
--   New: TS_360LinkFollow_Refresh replaces every 360 Link in the project the
--   same way -- for a session or template whose strips are missing.
-- @provides
--   [main] TS_360LinkFollow_Refresh.lua
--   [nomain] TS_360LinkFollow_Core.lua
-- @about
--   Toggle action. While ON, SSL 360 Link is removed from every hidden track, so
--   the track drops out of the SSL 360 Plug-in Mixer and off the UF8, and a
--   fresh instance is put back in the same FX slot when the track is shown. A
--   track counts as hidden when it is hidden in the mixer or in the arrange
--   view, including tracks inside a collapsed folder.
--
--   Why remove it rather than bypass or offline it: SSL 360 ignores bypass, and
--   an instance taken offline comes back with its saved identity -- which every
--   track made from the same template shares, so SSL 360 treats it as a
--   duplicate and ignores it. 360 Link's own state is just its A/B defaults and
--   360's solo/cut flags, so nothing is lost by starting fresh. (Automation
--   envelopes on 360 Link itself would be lost; it normally has none.)
--
--   SSL 360 also drops connections when many 360 Links start at once, and a
--   360 Link that misses its connection never retries. So they are put back
--   one at a time, and each one is checked in SSL 360's log
--   (%LOCALAPPDATA%\SSL\SSL360\LogFiles) and replaced again if its strip has not
--   registered. Showing a large folder takes a few seconds to fill in.
--
--   Only SSL 360 Link is touched -- matched by its VST3 ID, so the 360 Link Bus
--   Compressor and every other plugin are left alone. Run the action again to
--   turn it OFF; every hidden track gets its 360 Link back.
--
--   TS_360LinkFollow_Refresh replaces every 360 Link on visible tracks with a
--   fresh instance, the same way. Run it on a session whose strips are missing,
--   or on tracks made from a template before saving the template again.

----------------------------------------------------------------------------
-- Settings
----------------------------------------------------------------------------
local HIDE_IF_TCP_HIDDEN = true    -- also treat tracks hidden in the arrange view as hidden
local INTERVAL           = 0.1     -- seconds between visibility checks
local EXT_SLOTS          = "P_EXT:TS_360SLOTS"  -- FX slots this script removed 360 Link from
local EXT_PARK           = "P_EXT:TS_360PARK"   -- 1.1.0's record
local EXT_OFF            = "P_EXT:TS_360HIDE"   -- 1.0-1.4's record

----------------------------------------------------------------------------
local r = reaper
local here = ({ r.get_action_context() })[2]:match("^(.*[/\\])")
local Core = dofile(here .. "TS_360LinkFollow_Core.lua")
local _, _, sec, cmd = r.get_action_context()
local last_check, last_sig = 0, nil
local queue = Core.queue()

local function set_toggle(v)
  r.SetToggleCommandState(sec, cmd, v)
  r.RefreshToolbar2(sec, cmd)
end

local function track_visible(tr)
  if not r.IsTrackVisible(tr, true) then return false end
  if HIDE_IF_TCP_HIDDEN and not r.IsTrackVisible(tr, false) then return false end
  return true
end

local function visibility_signature()
  local t = {}
  for i = 0, r.CountTracks(0) - 1 do
    t[#t + 1] = track_visible(r.GetTrack(0, i)) and "1" or "0"
  end
  return table.concat(t)
end

local function get_ext(tr, key)
  local _, v = r.GetSetMediaTrackInfo_String(tr, key, "", false)
  return v
end

local function set_ext(tr, key, v)
  r.GetSetMediaTrackInfo_String(tr, key, v, true)
end

local function parked_slots(tr)
  local slots = {}
  for s in get_ext(tr, EXT_SLOTS):gmatch("%d+") do slots[#slots + 1] = tonumber(s) end
  return slots
end

-- Older versions' records become "removed, slots remembered"
local function migrate(tr)
  local slots = parked_slots(tr)
  local park = get_ext(tr, EXT_PARK)
  if park ~= "" then
    for line in park:gmatch("[^\n]+") do
      local s = line:match("^(%d+)")
      if s then slots[#slots + 1] = tonumber(s) end
    end
    set_ext(tr, EXT_PARK, "")
  end
  if get_ext(tr, EXT_OFF) == "1" then
    local off = {}
    for _, fx in ipairs(Core.link_slots(tr)) do
      if r.TrackFX_GetOffline(tr, fx) then off[#off + 1] = fx end
    end
    Core.delete_slots(tr, off)
    for _, s in ipairs(off) do slots[#slots + 1] = s end
    set_ext(tr, EXT_OFF, "")
  end
  if #slots > 0 then
    local t = {}
    for _, s in ipairs(slots) do t[#t + 1] = tostring(s) end
    set_ext(tr, EXT_SLOTS, table.concat(t, " "))
  end
end

local function hide(tr)
  queue:cancel(tr)
  local slots = Core.link_slots(tr)
  if #slots == 0 then return end
  local all = parked_slots(tr)
  for _, s in ipairs(slots) do all[#all + 1] = s end
  local t = {}
  for _, s in ipairs(all) do t[#t + 1] = tostring(s) end
  set_ext(tr, EXT_SLOTS, table.concat(t, " "))
  Core.delete_slots(tr, slots)
end

local function sync()
  r.PreventUIRefresh(1)
  for i = 0, r.CountTracks(0) - 1 do
    local tr = r.GetTrack(0, i)
    migrate(tr)
    if track_visible(tr) then
      local slots = parked_slots(tr)
      if #slots > 0 then queue:add(tr, slots) end
    else
      hide(tr)
    end
  end
  r.PreventUIRefresh(-1)
end

local function loop()
  local now = r.time_precise()
  if now - last_check >= INTERVAL then
    last_check = now
    local sig = visibility_signature()
    if sig ~= last_sig then
      last_sig = sig
      sync()
    end
  end
  r.PreventUIRefresh(1)
  queue:tick(track_visible, function(tr) set_ext(tr, EXT_SLOTS, "") end)
  r.PreventUIRefresh(-1)
  r.defer(loop)
end

r.atexit(function()
  -- no time to stagger here: put every remembered 360 Link back at once
  -- (run TS_360LinkFollow_Refresh afterwards if any strip is missing)
  r.PreventUIRefresh(1)
  for i = 0, r.CountTracks(0) - 1 do
    local tr = r.GetTrack(0, i)
    migrate(tr)
    local slots = parked_slots(tr)
    if #slots > 0 then
      Core.insert_fresh(tr, slots)
      set_ext(tr, EXT_SLOTS, "")
    end
  end
  r.PreventUIRefresh(-1)
  set_toggle(0)
end)

set_toggle(1)
loop()
