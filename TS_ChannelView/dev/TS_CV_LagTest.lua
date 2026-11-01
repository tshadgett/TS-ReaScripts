-- @noindex
-- dev tool, not released. Does a compare stay in time when one side has
-- latency? Builds, on two silent test tracks (fader at -inf, no master
-- send), a click into:
--   1) ChannelView's compare as built: [A -> B -> switch], A's output on
--      3/4 passing through B. A = 480 samples of latency, B = none. A probe
--      before the switch reports how far A's click arrives behind B's.
--   2) REAPER's parallel: [A] || [B] in containers, summed. One click of
--      1.0 per period when lined up, two of 0.5 when not.
-- Plays 3 s, writes dev/lag.txt, stops, and deletes the test tracks.

local script_dir = debug.getinfo(1, "S").source:match("@?(.*[\\/])") or ""
local cv_dir = script_dir:gsub("dev[\\/]$", "")
package.path = cv_dir .. "?.lua;" .. package.path

local T = require("TS_CV_FXTree")
local CMP = require("TS_CV_Compare")

local CLICK = "TS_CV_dev/TS_CV_LagClick.jsfx"
local LAT   = "TS_CV_dev/TS_CV_LagLatency.jsfx"
local PROBE = "TS_CV_dev/TS_CV_LagProbe.jsfx"
local PLAIN = "JS: Utility/volume"

local out = {}
local function say(s) out[#out + 1] = s end

local function add_track(name)
  local n = reaper.CountTracks(0)
  reaper.InsertTrackAtIndex(n, false)
  local tr = reaper.GetTrack(0, n)
  reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", name, true)
  reaper.SetMediaTrackInfo_Value(tr, "D_VOL", 0)
  reaper.SetMediaTrackInfo_Value(tr, "B_MAINSEND", 0)
  return tr
end

local function add(tr, name)
  local i = reaper.TrackFX_AddByName(tr, name, false, -1)
  if i and i >= 0 then reaper.TrackFX_Show(tr, i, 2) end
  return i
end

local function addr_of_guid(tr, guid)
  local found
  local function walk(nodes)
    for _, n in ipairs(nodes or {}) do
      if n.guid == guid then found = n.addr end
      if n.children then walk(n.children) end
    end
  end
  walk(T.collect(tr).tree)
  return found
end

say("REAPER " .. reaper.GetAppVersion())

-- 1) the compare as built
local t1 = add_track("Lag test 1 (compare)")
local probe1
do
  if add(t1, CLICK) < 0 then say("no click JSFX (Effects/TS_CV_dev)") end
  local a = add(t1, LAT)
  reaper.TrackFX_SetParam(t1, a, 0, 480)
  local fx = { addr = a, path_t = { a }, guid = reaper.TrackFX_GetFXGUID(t1, a), name = "JS: TS_CV Lag Latency (dev)" }
  local ok, why = CMP.start(t1, fx, PLAIN, false)
  say("compare built: " .. tostring(ok) .. (why and (" " .. why) or ""))
  if ok then
    -- the probe just before the switch: B on 1/2, A's pair on 3/4
    if T.add_into(t1, PROBE, { 1 }, 2) then
      local paddr = T.addr_of(t1, { 1, 2 })
      probe1 = reaper.TrackFX_GetFXGUID(t1, paddr)
      reaper.TrackFX_Show(t1, paddr, 2)
    else
      say("couldn't add the probe")
    end
  end
end

-- 2) REAPER's parallel, in containers
local t2 = add_track("Lag test 2 (parallel)")
local probe2
do
  add(t2, CLICK)
  local a = add(t2, LAT)
  reaper.TrackFX_SetParam(t2, a, 0, 480)
  T.wrap(t2, { 1 })
  add(t2, PLAIN)
  T.wrap(t2, { 2 })
  T.set_parallel(t2, T.addr_of(t2, { 2 }), 1)
  local p = add(t2, PROBE)
  probe2 = reaper.TrackFX_GetFXGUID(t2, p)
end

local start_pos = reaper.GetCursorPosition()
local t0 = reaper.time_precise()
reaper.OnPlayButton()

local function done()
  local a1 = probe1 and addr_of_guid(t1, probe1)
  if a1 then
    say(("1) compare: A's click %d samples behind B's (0 = in time), pairs seen %d"):format(
      reaper.TrackFX_GetParam(t1, a1, 0), reaper.TrackFX_GetParam(t1, a1, 1)))
  end
  local a2 = probe2 and addr_of_guid(t2, probe2)
  if a2 then
    say(("2) parallel: peak %.3f, clicks per period %d, gap %d samples (one click of 1.0 = in time)"):format(
      reaper.TrackFX_GetParam(t2, a2, 2), reaper.TrackFX_GetParam(t2, a2, 3), reaper.TrackFX_GetParam(t2, a2, 4)))
  end
  local f = io.open(script_dir .. "lag.txt", "w")
  if f then f:write(table.concat(out, "\n") .. "\n"); f:close() end
  reaper.OnStopButton()
  reaper.SetEditCurPos(start_pos, false, false)
  CMP.clear(t1)
  reaper.DeleteTrack(t2)
  reaper.DeleteTrack(t1)
end

local function wait()
  if reaper.time_precise() - t0 < 3 then reaper.defer(wait) else done() end
end
reaper.defer(wait)
