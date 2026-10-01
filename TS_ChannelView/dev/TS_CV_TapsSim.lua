-- @noindex  (a development tool, not a package: never installed)
-- Offline check of TS_CV_Taps' routing against a pretend REAPER: which
-- channels it picks, which pins it changes, what it records, and that
-- taking it back out leaves every pin as it found it.
--
--   lua TS_CV_TapsSim.lua        (from this folder)

local HERE = debug.getinfo(1, "S").source:match("@?(.*[\\/])") or "./"
package.path = HERE .. "../?.lua;" .. package.path

local fails, checks = 0, 0
local function check(name, got, want)
  checks = checks + 1
  if got == want then print("ok   " .. name)
  else fails = fails + 1; print(("FAIL %s  got %s  want %s"):format(name, tostring(got), tostring(want))) end
end

-- ---------------------------------------------------------------- the pretend project
local function fx(name, guid, nin, nout, extra)
  local f = { name = name, guid = guid, nin = nin, nout = nout, pin_in = {}, pin_out = {}, params = {} }
  for p = 0, nin - 1 do f.pin_in[p] = { p < 32 and (1 << p) or 0, 0 } end
  for p = 0, nout - 1 do f.pin_out[p] = { p < 32 and (1 << p) or 0, 0 } end
  for k, v in pairs(extra or {}) do f[k] = v end
  return f
end

local track, project
local function reset()
  track = {
    nch = 4, ext = {},
    recv = { { dst = 2 } },          -- a sidechain receive on 3/4
    fx = {
      fx("JS: TS_TrackProbe", "{PRE}", 18, 2, { params = { [0] = 0 } }),
      fx("VST3: Pro-Q 3 (FabFilter)", "{EQ}", 2, 2, { gr = nil }),
      fx("VST3: LA-2A (UA)", "{C1}", 2, 2, { pdc = 64 }),
      fx("VST3: 1176 (UA)", "{C2}", 4, 2, { pdc = 0 }),
      fx("VST3: Pro-C 2 (FabFilter)", "{C3}", 2, 2, { gr = -3 }),
      fx("JS: TS_TrackProbe", "{POST}", 18, 2, { params = { [0] = 1 } }),
    },
  }
  project = { track }
end

local measure = { ["LA-2A"] = true, ["1176"] = true, ["Pro-C 2"] = true }

package.loaded["TS_CV_Mappings"] = {
  get = function(key) return { measure = measure[key] or nil } end,
  any_measure = function() return next(measure) ~= nil end,
}

local function F(addr) return track.fx[addr + 1] end
extstate = {}

reaper = {
  time_precise = function() return os.clock() end,
  CountTracks = function() return #project end,
  GetTrack = function(_, i) return project[i + 1] end,
  GetParentTrack = function() return nil end,
  TrackFX_GetCount = function(tr) return #tr.fx end,
  TrackFX_GetFXName = function(tr, a) local f = F(a); return f ~= nil, f and f.name or "" end,
  TrackFX_GetFXGUID = function(tr, a) local f = F(a); return f and f.guid end,
  TrackFX_GetNamedConfigParm = function(tr, a, k)
    local f = F(a)
    if not f then return false, "" end
    if k == "pdc" then return true, tostring(f.pdc or 0) end
    if k == "GainReduction_dB" then
      if f.gr then return true, tostring(f.gr) end
      return false, ""
    end
    return false, ""
  end,
  TrackFX_GetParam = function(tr, a, p) return F(a).params[p] or 0 end,
  TrackFX_SetParam = function(tr, a, p, v) F(a).params[p] = v; return true end,
  TrackFX_GetIOSize = function(tr, a) local f = F(a); return 0, f.nin, f.nout end,
  TrackFX_GetPinMappings = function(tr, a, out, pin)
    local m = (out == 1 and F(a).pin_out or F(a).pin_in)[pin] or { 0, 0 }
    return m[1], m[2]
  end,
  TrackFX_SetPinMappings = function(tr, a, out, pin, lo, hi)
    (out == 1 and F(a).pin_out or F(a).pin_in)[pin] = { lo, hi }
    return true
  end,
  GetTrackNumSends = function(tr, cat) return cat == -1 and #tr.recv or 0 end,
  GetTrackSendInfo_Value = function(tr, cat, i, k)
    if cat == -1 and k == "I_DSTCHAN" then return tr.recv[i + 1].dst end
    return -1
  end,
  GetSetMediaTrackInfo_String = function(tr, k, v, set)
    if set then tr.ext[k] = v; return true, v end
    return tr.ext[k] ~= nil, tr.ext[k] or ""
  end,
  GetMediaTrackInfo_Value = function(tr, k) if k == "I_NCHAN" then return tr.nch end return 0 end,
  SetMediaTrackInfo_Value = function(tr, k, v) if k == "I_NCHAN" then tr.nch = v end return true end,
  Undo_BeginBlock = function() end, Undo_EndBlock = function() end,
  PreventUIRefresh = function() end,
  gmem_attach = function() end, gmem_write = function() end,
  GetLastTouchedFX = function() return false end,
  GetMasterTrack = function() return nil end,
  GetExtState = function(sec, k) return (extstate[sec .. "/" .. k]) or "" end,
  SetExtState = function(sec, k, v) extstate[sec .. "/" .. k] = v end,
}

local TP = require("TS_CV_Taps")

local function outbits(a, pin) return F(a).pin_out[pin][1] end
local function inbits(a, pin) return F(a).pin_in[pin][1] end
local function b(...) local v = 0; for _, c in ipairs({ ... }) do v = v | (1 << (c - 1)) end; return v end

-- ---------------------------------------------------------------- laying
reset()
local before = {}
for a = 0, #track.fx - 1 do
  before[a] = { i = {}, o = {} }
  for p, m in pairs(F(a).pin_in) do before[a].i[p] = m[1] end
  for p, m in pairs(F(a).pin_out) do before[a].o[p] = m[1] end
end

check("first sync changes something", TP.sync(track), true)
-- Pro-C 2 reports its own GR, so only the LA-2A (addr 2) and the 1176 (addr 3).
check("two taps",                     F(5).params[TP.P_TAPN], 2)
check("latency of the first",         F(5).params[TP.P_LAG], 64)
check("latency of the second",        F(5).params[TP.P_LAG + 1], 0)
-- 1..4 taken (signal, sidechain receive on 3/4), so 5/6 7/8 9/10 11/12.
-- Every plugin from the pre probe up writes each "before" copy, so a
-- bypassed one can't silence it.
check("pre probe writes L to 5 and 9", outbits(0, 0), b(1, 5, 9))
check("EQ writes L to 5 and 9",       outbits(1, 0), b(1, 5, 9))
check("EQ writes R to 6 and 10",      outbits(1, 1), b(2, 6, 10))
check("LA-2A writes its after pair",  outbits(2, 0) & b(7), b(7))
check("LA-2A is the 1176's before",   outbits(2, 0) & b(9), b(9))
check("1176 writes its after pair",   outbits(3, 1), b(2, 12))
check("1176's sidechain pins alone",  inbits(3, 2) .. "," .. inbits(3, 3), b(3) .. "," .. b(4))
check("probe tap 1 before L = 5",     inbits(5, 2), b(5))
check("probe tap 1 after R = 8",      inbits(5, 5), b(8))
check("probe tap 2 before L = 9",     inbits(5, 6), b(9))
check("probe tap 2 after R = 12",     inbits(5, 9), b(12))
check("track grows to 12 channels",   track.nch, 12)
check("Pro-C 2 untouched",            outbits(4, 0) .. "," .. outbits(4, 1), b(1) .. "," .. b(2))
check("a record on the track",        (track.ext[TP.EXT_KEY] or ""):sub(1, 3), "v1|")
check("pre probe armed for the zero", F(0).params[TP.P_ARM], 1)
check("new routing generation",       F(5).params[TP.P_GEN], 1)

check("a second sync changes nothing", TP.sync(track), false)
TP.set_zero_on(false)
check("zero off: no re-route",        TP.sync(track), false)
check("  but the pre probe disarmed", F(0).params[TP.P_ARM], 0)
check("  generation unchanged",       F(5).params[TP.P_GEN], 1)
TP.set_zero_on(true)
TP.sync(track)
check("zero on again: armed",         F(0).params[TP.P_ARM], 1)
F(5).params[TP.P_CAL] = 1; F(5).params[TP.P_CAL + 1] = 3
TP.invalidate()
check("cal status, tap 1",            TP.cal_status(track, "{C1}"), 1)
check("cal status, tap 2",            TP.cal_status(track, "{C2}"), 3)
check("cal status, not tapped",       TP.cal_status(track, "{EQ}"), nil)

-- latency changes are picked up without re-routing
F(2).pdc = 128
check("latency change: no re-route",  TP.sync(track), false)
check("  but the probe is told",      F(5).params[TP.P_LAG], 128)

-- ---------------------------------------------------------------- lifting
measure["LA-2A"] = nil; measure["1176"] = nil; measure["Pro-C 2"] = nil
TP.invalidate()
check("unticked: routing comes out",  TP.sync(track), true)
check("tap count back to 0",          F(5).params[TP.P_TAPN], 0)
check("record gone",                  track.ext[TP.EXT_KEY], "")
local restored = true
for a = 0, #track.fx - 1 do
  for p, v in pairs(before[a].o) do
    if F(a).pin_out[p][1] ~= v then restored = false; print("  out pin differs", a, p) end
  end
  if a ~= 5 then
    for p, v in pairs(before[a].i) do
      if F(a).pin_in[p][1] ~= v then restored = false; print("  in pin differs", a, p) end
    end
  end
end
check("every plugin's pins as they were", restored, true)
check("pre probe disarmed",           F(0).params[TP.P_ARM], 0)

-- ---------------------------------------------------------------- a move re-routes
measure["LA-2A"] = true
TP.invalidate()
TP.sync(track)
check("one tap again",                F(5).params[TP.P_TAPN], 1)
check("EQ in front of the LA-2A",     outbits(1, 0), b(1, 5))
-- bypassing a writer changes nothing (REAPER just stops it writing)
F(1).enabled = false
check("a bypass doesn't re-route",    TP.sync(track), false)
-- swap EQ and LA-2A: only the pre probe is in front of the LA-2A now
track.fx[2], track.fx[3] = track.fx[3], track.fx[2]
check("a move re-routes",             TP.sync(track), true)
check("EQ no longer writes 5",        outbits(2, 0), b(1))
check("the pre probe still does",     outbits(0, 0), b(1, 5))

-- ---------------------------------------------------------------- outside the probes
reset()
measure = { ["LA-2A"] = true }
package.loaded["TS_CV_Mappings"].get = function(key) return { measure = measure[key] or nil } end
table.insert(track.fx, 1, fx("VST3: LA-2A (UA)", "{OUT}", 2, 2))   -- before the pre probe
TP.invalidate()
TP.sync(track)
check("only the one between the probes", F(6).params[TP.P_TAPN], 1)
check("status inside",                TP.status(track, "{C1}"), "ok")
check("status outside",               TP.status(track, "{OUT}"), "outside")

print(fails == 0 and ("\nALL PASS (" .. checks .. ")") or ("\n" .. fails .. " FAILURES"))
os.exit(fails == 0 and 0 or 1)
