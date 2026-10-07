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
  meter_of = function(l) return (l and l.meter and l.meter.on) and l.meter or nil end,
}

-- Addresses as REAPER gives them: the top level 0, 1, 2...; anything in a
-- container a number of its own (here 0x2000000 + n, in chain order), so
-- moving things renumbers them, as it does in REAPER.
local amap
local function index()
  amap = {}
  local n = 0
  local function walk(list, top)
    for i, f in ipairs(list) do
      local a
      if top then a = i - 1 else n = n + 1; a = 0x2000000 + n end
      f.addr = a; amap[a] = f
      if f.kids then walk(f.kids, false) end
    end
  end
  walk(track.fx, true)
end
local function F(addr) index(); return amap[addr] end
extstate = {}

local projext = {}
reaper = {
  GetProjExtState = function(_, ns, k) return 0, projext[ns .. k] or "" end,
  SetProjExtState = function(_, ns, k, v) projext[ns .. k] = v end,
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
    if k == "parallel" then return true, tostring(f.par or 0) end
    if f.kids then
      if k == "container_count" then return true, tostring(#f.kids) end
      local j = k:match("^container_item%.(%d+)$")
      if j then
        local kid = f.kids[tonumber(j) + 1]
        index()
        if kid then return true, tostring(kid.addr) end
        return false, ""
      end
      if k == "container_nch" then return true, tostring(f.nch) end
      if k == "container_nch_in" then return true, tostring(f.nin) end
      if k == "container_nch_out" then return true, tostring(f.nout) end
    end
    if k == "GainReduction_dB" then
      if f.gr then return true, tostring(f.gr) end
      return false, ""
    end
    return false, ""
  end,
  -- A container given more pins: REAPER maps each new one to its own
  -- channel (pin k to k + 1), which TS_CV_Taps must clear.
  TrackFX_SetNamedConfigParm = function(tr, a, k, v)
    local f = F(a)
    if not (f and f.kids) then return false end
    v = tonumber(v)
    if k == "container_nch" then f.nch = v
    elseif k == "container_nch_in" or k == "container_nch_out" then
      local pins = (k == "container_nch_in") and f.pin_in or f.pin_out
      local was = (k == "container_nch_in") and f.nin or f.nout
      for p = was, v - 1 do pins[p] = { p < 32 and (1 << p) or 0, 0 } end
      if k == "container_nch_in" then f.nin = v else f.nout = v end
    else return false end
    return true
  end,
  TrackFX_GetParam = function(tr, a, p) return F(a).params[p] or 0 end,
  TrackFX_GetParamName = function(tr, a, p)
    local f = F(a)
    if f and f.name:find("TrackProbe") and p == 25 then return true, "Tap 1 input peak (dBFS)" end
    return true, ""
  end,
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

-- ---------------------------------------------------------------- levels
-- Pro-C 2 reports its own reduction, so it's only ever tapped for its
-- levels: a "levels only" tap, which the probe runs without a filterbank.
reset()
measure = { ["LA-2A"] = true }
local levels = { ["Pro-C 2"] = true, ["LA-2A"] = true }
package.loaded["TS_CV_Mappings"].get = function(key)
  return { measure = measure[key] or nil, levels = levels[key] or nil }
end
TP.invalidate()
TP.sync(track)
check("levels: two taps",              F(5).params[TP.P_TAPN], 2)
check("LA-2A both, Pro-C 2 levels only", track.ext[TP.EXT_KEY]:match("{C1},[^|]*,(%a+)") ..
      "/" .. track.ext[TP.EXT_KEY]:match("{C3},[^|]*,(%a+)"), "gl/l")
check("levels-only tap flagged",       F(5).params[TP.P_NOGR], 2)
check("Pro-C 2 is not 'tapped'",       TP.is_tapped(track, "{C3}"), false)
check("but it is metered",             TP.is_metered(track, "{C3}"), true)
check("LA-2A is both",                 TP.is_tapped(track, "{C1}") and TP.is_metered(track, "{C1}"), true)
check("no reading for a levels tap",   TP.reading(track, "{C3}"), nil)
F(5).params[TP.P_INPK + 1] = -12.5; F(5).params[TP.P_OUTRMS + 1] = -9
local lv = TP.levels(track, "{C3}")
check("levels read back",              lv and (lv.in_pk .. "/" .. lv.out_rms), "-12.5/-9")
check("a second sync changes nothing", TP.sync(track), false)
-- untick levels on the LA-2A: same plugins, but what the tap is for changed
levels["LA-2A"] = nil
TP.invalidate()
check("what changed: re-routed",       TP.sync(track), true)
check("LA-2A now reduction only",      track.ext[TP.EXT_KEY]:match("{C1},[^|]*,(%a+)"), "g")
-- an older record, without the field, still reads as reduction
local old = TP.parse_record("v1|TOP|{POST}|{X},{PRE},5,7,0")
check("old record: reduction",         old.taps[1].what, "g")
-- an older probe (no levels yet): nothing read from it as levels, and
-- nothing written to the parameter that is levels-only on a new one
local real = reaper.TrackFX_GetParamName
reaper.TrackFX_GetParamName = function() return true, "Bypass" end
TP.invalidate()
check("old probe: levels say so",      TP.levels(track, "{C3}") and TP.levels(track, "{C3}").old, true)
F(5).params[TP.P_NOGR] = 99
TP.sync(track)
check("old probe: param 24 untouched", F(5).params[TP.P_NOGR], 99)
reaper.TrackFX_GetParamName = real
TP.invalidate()
check("record round trip",             TP.format_record(TP.parse_record("v1|TOP|{P}|{A},{B},5,7,3,l")),
      "v1|TOP|{P}|{A},{B},5,7,3,l")
check("nogr mask",                     TP.nogr_mask({ { what = "g" }, { what = "l" }, { what = "gl" }, { what = "l" } }), 10)

-- ---------------------------------------------------------------- ReaEQ
-- An EQ has no reduction: Measure=1 on ReaEQ (an older layout could carry
-- it) is ignored, so its tap is for levels only.
reset()
track.fx[2] = fx("VST: ReaEQ (Cockos)", "{EQ}", 2, 2)
measure = { ["ReaEQ"] = true }
levels = { ["ReaEQ"] = true }
TP.invalidate()
TP.sync(track)
check("ReaEQ: one tap",                F(5).params[TP.P_TAPN], 1)
check("ReaEQ: levels only",            track.ext[TP.EXT_KEY]:match("{EQ},[^|]*,(%a+)"), "l")
check("ReaEQ: not 'tapped'",           TP.is_tapped(track, "{EQ}"), false)
levels = {}
TP.invalidate()
TP.sync(track)
check("ReaEQ: measure alone, no tap",  F(5).params[TP.P_TAPN], 0)

-- ---------------------------------------------------------------- the GR trace
-- A gain-reduction meter opened out into its trace needs the plugin's own
-- audio: a REPORTING plugin (Pro-C 2) is tapped for its levels while it's
-- open, and lifted when it closes. A MEASURED one is already tapped, and
-- opening its trace must not re-route it (a re-route forgets every zero).
do
  local St = require("TS_CV_State")
  reset()
  measure = { ["LA-2A"] = true }
  local meters = { ["Pro-C 2"] = true, ["LA-2A"] = true }
  package.loaded["TS_CV_Mappings"].get = function(key)
    return { measure = measure[key] or nil,
             meter = meters[key] and { on = true, range = 18 } or nil }
  end
  TP.invalidate(); St.clear_cache()
  TP.sync(track)
  check("trace: before, one tap",        F(5).params[TP.P_TAPN], 1)
  St.set_gr_open("{C3}", true)
  TP.invalidate()
  check("trace: opening a reporter re-routes", TP.sync(track), true)
  check("trace: it's tapped for levels", track.ext[TP.EXT_KEY]:match("{C3},[^|]*,(%a+)"), "l")
  check("trace: its tap index",          (TP.tap_index(track, "{C3}")), 2)
  local gen = F(5).params[TP.P_GEN]
  St.set_gr_open("{C1}", true)
  TP.invalidate()
  check("trace: a measured one, no re-route", TP.sync(track), false)
  check("  generation unchanged",        F(5).params[TP.P_GEN], gen)
  St.set_gr_open("{C3}", false)
  TP.invalidate()
  check("trace: closing lifts the tap",  TP.sync(track) and F(5).params[TP.P_TAPN], 1)
  meters["Pro-C 2"] = nil
  St.set_gr_open("{C3}", true)
  TP.invalidate()
  check("trace: no meter, no tap",       TP.sync(track), false)
  St.clear_cache()
end

-- ---------------------------------------------------------------- inside containers
-- PRE, EQ, K1[ X, K2[ LA-2A, Y ], W ], 1176, POST: the LA-2A two
-- containers down. The copies keep their numbers (5/6 before, 7/8 after)
-- all the way out, each container carrying them on its own pins.
local function container(guid, kids)
  local c = fx("Container", guid, 2, 2)
  c.kids, c.nch = kids, 2
  return c
end
local function setup_nested()
  reset()
  track.fx = {
    fx("JS: TS_TrackProbe", "{PRE}", 18, 2, { params = { [0] = 0 } }),
    fx("VST3: Pro-Q 3 (FabFilter)", "{EQ}", 2, 2),
    container("{K1}", {
      fx("VST3: Pro-Q 3 (FabFilter)", "{X}", 2, 2),
      container("{K2}", {
        fx("VST3: LA-2A (UA)", "{T}", 2, 2, { pdc = 32 }),
        fx("VST3: Pro-Q 3 (FabFilter)", "{Y}", 2, 2),
      }),
      fx("VST3: Pro-Q 3 (FabFilter)", "{W}", 2, 2),
    }),
    fx("VST3: 1176 (UA)", "{B}", 2, 2),
    fx("JS: TS_TrackProbe", "{POST}", 18, 2, { params = { [0] = 1 } }),
  }
end
local function G(guid)
  index()
  for a, f in pairs(amap) do if f.guid == guid then return a end end
end
local function snapshot()
  index()
  local s = {}
  for _, f in pairs(amap) do
    local t = {}
    for p, m in pairs(f.pin_in) do t["i" .. p] = m[1] end
    for p, m in pairs(f.pin_out) do t["o" .. p] = m[1] end
    s[f.guid] = t
  end
  return s
end
local function same_pins(was, skip)
  local now, ok = snapshot(), true
  for g, t in pairs(was) do
    for k, v in pairs(t) do
      if not (skip and skip[g] and k:sub(1, 1) == "i") and (now[g][k] or 0) ~= v then
        ok = false; print("  pin differs", g, k, now[g][k], v)
      end
    end
  end
  return ok
end

setup_nested()
measure = { ["LA-2A"] = true }
levels = {}
package.loaded["TS_CV_Mappings"].get = function(key)
  return { measure = measure[key] or nil, levels = levels[key] or nil }
end
TP.invalidate()
local was = snapshot()
check("nested: lays",                  TP.sync(track), true)
local POST, K1, K2 = G("{POST}"), G("{K1}"), G("{K2}")
check("nested: one tap",               F(POST).params[TP.P_TAPN], 1)
check("nested: v2 record with its path", track.ext[TP.EXT_KEY],
      "v2|TOP|{POST}|{T},{PRE}+{EQ}+{X},5,7,32,g,{K1}+{K2}")
check("nested: latency",               F(POST).params[TP.P_LAG], 32)
check("nested: EQ writes before L",    outbits(G("{EQ}"), 0), b(1, 5))
check("nested: X (inside) writes it too", outbits(G("{X}"), 1), b(2, 6))
check("nested: LA-2A writes after",    outbits(G("{T}"), 0), b(1, 7))
check("nested: Y untouched",           outbits(G("{Y}"), 0) .. "," .. outbits(G("{Y}"), 1), b(1) .. "," .. b(2))
check("nested: W untouched",           outbits(G("{W}"), 0), b(1))
check("nested: 1176 untouched",        outbits(G("{B}"), 0), b(1))
check("nested: K1 pins in/out",        F(K1).nin .. "/" .. F(K1).nout, "6/8")
check("nested: K2 pins in/out",        F(K2).nin .. "/" .. F(K2).nout, "6/8")
check("nested: K2 channels",           F(K2).nch, 8)
check("nested: K1 carries 5/6 in",     inbits(K1, 4) .. "," .. inbits(K1, 5), b(5) .. "," .. b(6))
check("nested: K1 new pins 3/4 empty", inbits(K1, 2) .. "," .. inbits(K1, 3) .. "," ..
      outbits(K1, 2) .. "," .. outbits(K1, 3), "0,0,0,0")
check("nested: K2 carries 5-8 out",    outbits(K2, 4) .. "," .. outbits(K2, 5) .. "," ..
      outbits(K2, 6) .. "," .. outbits(K2, 7), b(5) .. "," .. b(6) .. "," .. b(7) .. "," .. b(8))
check("nested: K1's main pins as they were", inbits(K1, 0) .. "," .. outbits(K1, 1), b(1) .. "," .. b(2))
check("nested: probe before L = 5",    inbits(POST, 2), b(5))
check("nested: probe after R = 8",     inbits(POST, 5), b(8))
check("nested: track grows to 8",      track.nch, 8)
check("nested: status ok",             TP.status(track, "{T}"), "ok")
check("nested: a second sync changes nothing", TP.sync(track), false)
check("nested: is tapped",             TP.is_tapped(track, "{T}"), true)

measure = {}
TP.invalidate()
check("nested: unticked, comes out",   TP.sync(track), true)
check("nested: record gone",           track.ext[TP.EXT_KEY], "")
check("nested: every pin as it was",   same_pins(was, { ["{POST}"] = true }), true)
check("nested: counts stay raised",    F(K1).nin .. "/" .. F(K1).nout, "6/8")
check("nested: but carry nothing",     inbits(K1, 4) .. "," .. outbits(K2, 6), "0,0")
measure = { ["LA-2A"] = true }
TP.invalidate()
TP.sync(track)
check("nested: laid again, same channels (no creep)",
      track.ext[TP.EXT_KEY]:match("{T},[^,]*,(%d+,%d+)"), "5,7")

-- moving it out of the containers: re-routed, and the containers' pins
-- emptied though every nested address in the record has changed
local moved = table.remove(F(K2).kids, 1)
table.insert(track.fx, 4, moved)        -- after K1, before the 1176
TP.invalidate()
check("nested: a move out re-routes",  TP.sync(track), true)
K1, K2 = G("{K1}"), G("{K2}")
check("nested: now v1, no path",       track.ext[TP.EXT_KEY], "v1|TOP|{POST}|{T},{PRE}+{EQ}+{K1},5,7,32,g")
check("nested: K2 carries nothing",    outbits(K2, 4) .. "," .. outbits(K2, 6) .. "," .. inbits(K2, 4), "0,0,0")
check("nested: X no longer writes",    outbits(G("{X}"), 0), b(1))
check("nested: K1 writes as one plugin", outbits(K1, 0), b(1, 5))

-- ---------------------------------------------------------------- in parallel
setup_nested()
TP.invalidate()
F(G("{Y}")).par = 1                     -- Y runs alongside the LA-2A
check("parallel: status",              TP.status(track, "{T}"), "parallel")
check("parallel: not tapped",          TP.sync(track), false)
check("parallel: no record",           track.ext[TP.EXT_KEY], nil)
F(G("{Y}")).par = 0
F(G("{K2}")).par = 2                    -- the container it's in runs alongside X
TP.invalidate()
check("parallel: a container on its path", TP.status(track, "{T}"), "parallel")
F(G("{K2}")).par = 0
F(G("{X}")).par = 1                     -- first in its container: means nothing
TP.invalidate()
check("parallel: a flag on a first slot", TP.status(track, "{T}"), "ok")
F(G("{X}")).par = 0
F(G("{B}")).par = 1                     -- top level, alongside K1
TP.invalidate()
check("parallel: at the top too",      TP.status(track, "{B}"), "parallel")
check("parallel: and everything in its neighbour", TP.status(track, "{X}"), "parallel")
check("outside: still outside",        TP.status(track, "{NOPE}"), "outside")

-- ---------------------------------------------------------------- ARA
-- Header lines as REAPER saves them, from a track with Melodyne running ARA.
check("ARA: Melodyne's header",        TP.ara_header('<VST "VST3: Melodyne (Celemony)" Melodyne.vst3 0 "" ' ..
      '214222609{5653544D6C70676D656C6F64796E6520} com.celemony.ara.chunk.13'), true)
check("ARA: an ordinary VST3",         TP.ara_header('<VST "VST3: SSL 360 Link (SSL)" "SSL 360 Link.vst3" 0 "" ' ..
      '597173370{5653543336304C73736C20333630206C} ""'), false)
check("ARA: a JSFX",                   TP.ara_header('<JS "DocShadrach FXs/Effects/The_Analog_Molecule.jsfx" ""'), false)
check("ARA: a container",              TP.ara_header('<CONTAINER Container ""'), false)
do
  reset()
  local chunk = '<TRACK\nNAME ACG\n<FXCHAIN\nWNDRECT 24 52 1898 1090\nSHOW 0\nBYPASS 0 0 0\n' ..
    '<VST "VST3: Melodyne (Celemony)" Melodyne.vst3 0 "" 2142{56} com.celemony.ara.chunk.13\nAAAA\n>\n>\n>'
  reaper.GetTrackStateChunk = function() return true, chunk end
  track.fx = { fx("VST3: Melodyne (Celemony)", "{MEL}", 2, 2), fx("JS: Thing", "{J}", 2, 2) }
  check("ARA: first slot, from the chunk", TP.ara_first(track), true)
  chunk = chunk:gsub("com%.celemony%.ara%.chunk%.13", '""')
  check("ARA: no archive yet, by name",  TP.ara_first(track), true)
  track.fx[1] = fx("VST3: Pro-Q 3 (FabFilter)", "{EQ}", 2, 2)
  check("ARA: an ordinary first plugin", TP.ara_first(track), false)
  -- inserting: the pre probe goes in behind Melodyne, the post at the end
  track.fx[1] = fx("VST3: Melodyne (Celemony)", "{MEL}", 2, 2)
  local asked = {}
  reaper.TrackFX_AddByName = function(tr, nm, rec, pos)
    if nm ~= "TS_TrackProbe.jsfx" then return -1 end
    asked[#asked + 1] = pos
    local at = (pos == -1) and #tr.fx or (-1000 - pos)
    table.insert(tr.fx, at + 1, fx("JS: TS_TrackProbe", "{P" .. #asked .. "}", 18, 2))
    return at
  end
  check("ARA: probes inserted",          (TP.insert_probes(track)), true)
  check("ARA: asked for slot 2, then the end", table.concat(asked, ","), "-1001,-1")
  check("ARA: Melodyne still first",     F(0).guid, "{MEL}")
  check("ARA: pre probe second, post last", F(1).params[TP.P_ROLE] .. "," .. F(3).params[TP.P_ROLE], "0,1")
  check("ARA: the pair is found",        TP.status(track, "{J}"), "ok")
  check("ARA: Melodyne outside it",      TP.status(track, "{MEL}"), "outside")
  reaper.GetTrackStateChunk, reaper.TrackFX_AddByName = nil, nil
end

-- ---------------------------------------------------------------- records
check("v2 round trip", TP.format_record(TP.parse_record("v2|TOP|{P}|{A},{B}+{C},5,7,3,gl,{K1}+{K2}")),
      "v2|TOP|{P}|{A},{B}+{C},5,7,3,gl,{K1}+{K2}")
check("v2 with a top-level tap too", TP.format_record(TP.parse_record("v2|TOP|{P}|{A},{B},5,7,0,g,|{D},{B},9,11,0,l,{K}")),
      "v2|TOP|{P}|{A},{B},5,7,0,g,|{D},{B},9,11,0,l,{K}")
check("v1 reads with no path",         TP.parse_record("v1|TOP|{P}|{A},{B},5,7,0,g").taps[1].pathg, "")
check("unknown version ignored",       TP.parse_record("v3|TOP|{P}|{A},{B},5,7,0,g"), nil)

print(fails == 0 and ("\nALL PASS (" .. checks .. ")") or ("\n" .. fails .. " FAILURES"))
os.exit(fails == 0 and 0 or 1)
