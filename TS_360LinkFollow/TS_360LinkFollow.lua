-- @description TS_360LinkFollow - SSL 360 Link follows track visibility (UF8 / UC1)
-- @author Tim Shadgett
-- @version 1.0.0
-- @about
--   Toggle action. While ON, any SSL 360 Link instance on a hidden track is set
--   offline, which unloads it so the track drops out of the SSL 360 Plug-in
--   Mixer and off the UF8. Show the track again and the instance comes back
--   online. A track counts as hidden when it is hidden in the mixer or in the
--   arrange view, including tracks inside a collapsed folder.
--
--   Only SSL 360 Link is touched -- matched by its VST3 ID, so the 360 Link Bus
--   Compressor and every other plugin are left alone. Instances you set offline
--   yourself stay offline. Run the action again to turn it OFF; everything it
--   took offline is brought back.

----------------------------------------------------------------------------
-- Settings
----------------------------------------------------------------------------
local IDENT              = "{5653543336304C73736C20333630206C" -- VST3 ID of SSL 360 Link
local HIDE_IF_TCP_HIDDEN = true    -- also treat tracks hidden in the arrange view as hidden
local INTERVAL           = 0.25    -- seconds between visibility checks
local EXTKEY             = "P_EXT:TS_360HIDE" -- per-track marker: "this script offlined it"

----------------------------------------------------------------------------
local r = reaper
local _, _, sec, cmd = r.get_action_context()
local last_check, last_sig = 0, nil

local function set_toggle(v)
  r.SetToggleCommandState(sec, cmd, v)
  r.RefreshToolbar2(sec, cmd)
end

-- Match by the plugin's identity, not its display name (survives renamed instances)
local function is_link(tr, fx)
  local ok, ident = r.TrackFX_GetNamedConfigParm(tr, fx, "fx_ident")
  if ok and ident ~= "" then
    return ident:find(IDENT, 1, true) ~= nil
  end
  local _, name = r.TrackFX_GetFXName(tr, fx, "")
  return name:find("SSL 360 Link (SSL)", 1, true) ~= nil
end

local function track_visible(tr)
  if not r.IsTrackVisible(tr, true) then return false end
  if HIDE_IF_TCP_HIDDEN and not r.IsTrackVisible(tr, false) then return false end
  return true
end

-- Cheap signature of track visibility; only do real work when it changes
local function visibility_signature()
  local t = {}
  for i = 0, r.CountTracks(0) - 1 do
    t[#t + 1] = track_visible(r.GetTrack(0, i)) and "1" or "0"
  end
  return table.concat(t)
end

local function ours(tr)
  local _, v = r.GetSetMediaTrackInfo_String(tr, EXTKEY, "", false)
  return v == "1"
end

local function mark(tr, on)
  r.GetSetMediaTrackInfo_String(tr, EXTKEY, on and "1" or "", true)
end

local function sync(force_online)
  r.PreventUIRefresh(1)
  for i = 0, r.CountTracks(0) - 1 do
    local tr      = r.GetTrack(0, i)
    local visible = force_online or track_visible(tr)
    local is_ours = ours(tr)
    local touched = false
    for fx = 0, r.TrackFX_GetCount(tr) - 1 do
      if is_link(tr, fx) then
        local offline = r.TrackFX_GetOffline(tr, fx)
        if not visible and not offline then
          r.TrackFX_SetOffline(tr, fx, true)
          touched = true
        elseif visible and offline and is_ours then
          r.TrackFX_SetOffline(tr, fx, false)
        end
      end
    end
    if not visible and touched then mark(tr, true)
    elseif visible and is_ours then mark(tr, false) end
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
      sync(false)
    end
  end
  r.defer(loop)
end

r.atexit(function()
  sync(true)       -- bring back everything this script offlined
  set_toggle(0)
end)

set_toggle(1)
loop()
