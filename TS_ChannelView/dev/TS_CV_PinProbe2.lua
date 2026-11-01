-- @noindex  (a development tool, not a package: never installed)
--[[
  TS_CV_PinProbe2.lua -- whether a plugin can be held at its channel
  layout (REAPER's channel_config) while the track's channel count goes
  up. For each plugin at the top of the selected track's chain that has a
  channel_config, it tries a few settings, reading back what REAPER keeps
  and how many pins the plugin has, then raises the track to 16 channels
  and reads its pins again; then puts it all back. Written to
  dev/pinprobe2.txt beside this script. Use the same test track.
--]]

local here = debug.getinfo(1, "S").source:match("@?(.*[\\/])") or ""
local tr = reaper.GetSelectedTrack(0, 0)
if not tr then reaper.MB("Select the test track first.", "Pin probe 2", 0) return end

local out = {}
local function say(s) out[#out + 1] = s end
local function cc(a)
  local ok, v = reaper.TrackFX_GetNamedConfigParm(tr, a, "channel_config")
  return ok and v or nil
end
local function pins(a)
  local _, nin, nout = reaper.TrackFX_GetIOSize(tr, a)
  local _, p0 = reaper.TrackFX_GetNamedConfigParm(tr, a, "in_pin_0")
  return ("in %d, out %d, first pin \"%s\""):format(nin or -1, nout or -1, p0 or "")
end

local nch0 = math.floor(reaper.GetMediaTrackInfo_Value(tr, "I_NCHAN"))
reaper.Undo_BeginBlock()
local tried = {}
for a = 0, reaper.TrackFX_GetCount(tr) - 1 do
  local orig = cc(a)
  if orig then
    local _, name = reaper.TrackFX_GetFXName(tr, a, "")
    say(("[%d] %s  channel_config \"%s\"  (%s)"):format(a, name, orig, pins(a)))
    for _, v in ipairs({ "2", "2 0", "2 -1", "4", "4 0", "0" }) do
      local okset = reaper.TrackFX_SetNamedConfigParm(tr, a, "channel_config", v)
      say(("   set \"%s\" -> %s, now \"%s\"  (%s)"):format(v, tostring(okset), tostring(cc(a)), pins(a)))
    end
    tried[#tried + 1] = { a = a, orig = orig }
  end
end
-- held at 2 channels, if REAPER took it: does it stay there at 16?
for _, t in ipairs(tried) do reaper.TrackFX_SetNamedConfigParm(tr, t.a, "channel_config", "2") end
say("")
say(("held at \"2\", track raised from %d to 16:"):format(nch0))
reaper.SetMediaTrackInfo_Value(tr, "I_NCHAN", 16)
for _, t in ipairs(tried) do say(("[%d] channel_config \"%s\"  (%s)"):format(t.a, tostring(cc(t.a)), pins(t.a))) end
-- and with the setting it started with
for _, t in ipairs(tried) do reaper.TrackFX_SetNamedConfigParm(tr, t.a, "channel_config", t.orig) end
say("")
say("its own setting again, track at 16:")
for _, t in ipairs(tried) do say(("[%d] channel_config \"%s\"  (%s)"):format(t.a, tostring(cc(t.a)), pins(t.a))) end
reaper.SetMediaTrackInfo_Value(tr, "I_NCHAN", nch0)
reaper.Undo_EndBlock("Pin probe 2", -1)

local f = io.open(here .. "pinprobe2.txt", "w")
if f then f:write(table.concat(out, "\n")); f:close() end
reaper.MB("Written to dev/pinprobe2.txt.\n\nCtrl+Z puts the track back as it was.", "Pin probe 2", 0)
