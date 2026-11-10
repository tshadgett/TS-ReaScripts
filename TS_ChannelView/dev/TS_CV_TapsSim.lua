-- @noindex  (a development tool, not a package: never installed)
-- Offline check of TS_CV_Taps' routing against a pretend REAPER: which
-- channels it picks, which pins it changes, what it records, and that
-- taking it back out leaves every pin as it found it.
--
--   lua TS_CV_TapsSim.lua        (from this folder)
--   PROBE_NEW=1 lua TS_CV_TapsSim.lua
--     the same, against TS_TrackProbe 2.0.0 (no parameters: everything in
--     its track's gmem block). The checks still read "params[TP.P_x]":
--     for a new probe those read and write the block (see probe_params).

local HERE = debug.getinfo(1, "S").source:match("@?(.*[\\/])") or "./"
package.path = HERE .. "../?.lua;" .. package.path

local fails, checks = 0, 0
local function check(name, got, want)
  checks = checks + 1
  if got == want then print("ok   " .. name)
  else fails = fails + 1; print(("FAIL %s  got %s  want %s"):format(name, tostring(got), tostring(want))) end
end

-- ---------------------------------------------------------------- the pretend project
local NEW = os.getenv("PROBE_NEW") == "1"
local gmem = {}
local track, project
local TPref                              -- TS_CV_Taps, once loaded
local PLF = {}                           -- old slider -> block offset
-- A 2.0.0 probe's "params": its track's block (the track is number 3,
-- index 2), read and written by the old slider numbers; its role is
-- where it sits, and the Visualizer's choice is kept on the track.
local function probe_params(f)
  return setmetatable({}, {
    __index = function(_, p)
      if p == 0 then return TPref and TPref.probe_role(project[1], f.addr) or 0 end
      if p == 3 then
        local r = TPref and TPref.probe_role(project[1], f.addr)
        local c = project[1].ext["P_EXT:TS_TrackProbe_vis"]
        return ((r == 0 and c == "pre") or (r == 1 and c == "post")) and 1 or 0
      end
      local off = PLF[p]
      return off and (gmem[0x100000 + 3 * 128 + off] or 0) or 0
    end,
    __newindex = function(_, p, v)
      local off = PLF[p]
      if off then gmem[0x100000 + 3 * 128 + off] = v end
    end,
  })
end
local function fx(name, guid, nin, nout, extra)
  local f = { name = name, guid = guid, nin = nin, nout = nout, pin_in = {}, pin_out = {}, params = {} }
  for p = 0, nin - 1 do f.pin_in[p] = { p < 32 and (1 << p) or 0, 0 } end
  for p = 0, nout - 1 do f.pin_out[p] = { p < 32 and (1 << p) or 0, 0 } end
  for k, v in pairs(extra or {}) do f[k] = v end
  if NEW and name:find("TrackProbe", 1, true) then f.params = probe_params(f) end
  return f
end

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

-- A surround VST3 that follows the track (Pro-C 3): main inputs, then as
-- many sidechain inputs, one output per channel; every pin wired afresh,
-- each to its own channel -- so a sidechain on 3/4 no longer arrives.
function relayout(f, nch)
  f.nin, f.nout = nch * 2, nch
  f.pin_in, f.pin_out = {}, {}
  for p = 0, f.nin - 1 do f.pin_in[p] = { p < 32 and (1 << p) or 0, 0 } end
  for p = 0, f.nout - 1 do f.pin_out[p] = { p < 32 and (1 << p) or 0, 0 } end
end

local projext = {}
local probe_old = false
local now_t = 0
reaper = {
  GetProjExtState = function(_, ns, k) return 0, projext[ns .. k] or "" end,
  SetProjExtState = function(_, ns, k, v) projext[ns .. k] = v end,
  time_precise = function() return os.clock() + now_t end,
  GetPlayState = function() return 0 end,
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
    if k == "channel_config" then
      if not f.cc then return false, "" end
      return true, tostring(f.held or 0) .. " -1 2"
    end
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
    if f and f.cc and k == "channel_config" then
      local n = tonumber(tostring(v):match("^%s*(%-?%d+)")) or 0
      f.held = (n > 0) and n or nil
      -- held at another count than the one it took from the track: laid
      -- out afresh at it; released: following the track again
      if not f.held then relayout(f, track.nch)
      elseif f.nout == track.nch and f.held ~= track.nch then relayout(f, f.held) end
      return true
    end
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
    if f and f.name:find("TrackProbe") and p == 41 then return true, "Multiband tap (0 none)" end
    if f and f.name:find("TrackProbe") and p == 49 and not probe_old then return true, "Third-octave tap (0 none)" end
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
  GetMediaTrackInfo_Value = function(tr, k)
    if k == "I_NCHAN" then return tr.nch end
    if k == "IP_TRACKNUMBER" then return 3 end
    if k == "I_RECARM" then return tr.recarm or 0 end
    return 0
  end,
  -- A plugin marked `follow` takes the track's channel count, as many
  -- VST3s do: its pins become one per channel, each on its own.
  SetMediaTrackInfo_Value = function(tr, k, v)
    if k == "I_NCHAN" then
      tr.nch = v
      for _, f in ipairs(tr.fx) do
        if f.cc and not f.held then relayout(f, v) end
        if f.follow then
          for p = f.nin, v - 1 do f.pin_in[p] = { p < 32 and (1 << p) or 0, 0 } end
          for p = f.nout, v - 1 do f.pin_out[p] = { p < 32 and (1 << p) or 0, 0 } end
          f.nin, f.nout = v, v
        end
      end
    end
    return true
  end,
  Undo_BeginBlock = function() end, Undo_EndBlock = function() end,
  TrackFX_Delete = function(tr, a) index(); table.remove(tr.fx, a + 1); return true end,
  PreventUIRefresh = function() end,
  ValidatePtr = function() return true end,
  TrackFX_GetIOSize = function(_, a) index(); local f = amap[a]; return 0, f and f.nin or 0, f and f.nout or 0 end,
  gmem_attach = function() end, gmem_write = function(i, v) gmem[i] = v end,
  gmem_read = function(i) return gmem[i] or 0 end,
  GetLastTouchedFX = function() return false end,
  TrackFX_GetNumParams = function(tr, a)
    local f = F(a)
    if f and f.name:find("TrackProbe", 1, true) then return NEW and 3 or 57 end
    return 10
  end,
  GetTrackGUID = function(tr) return "{TRACK}" end,
  GetProjectStateChangeCount = function() now_t = now_t; return math.random(1, 1 << 30) end,
  ValidatePtr2 = function() return true end,
  GetMasterTrack = function() return nil end,
  GetExtState = function(sec, k) return (extstate[sec .. "/" .. k]) or "" end,
  SetExtState = function(sec, k, v) extstate[sec .. "/" .. k] = v end,
}

local TP = require("TS_CV_Taps")
-- (most of what follows is about plugins that don't report their own
-- reduction, so reporting ones are set to show their own figure here;
-- measured, the default, is tried at the end)
reaper.SetExtState("TS_ChannelView", TP.READING_KEY, "own", true)
TPref = TP
for _, f in pairs(require("TS_CV_ProbeLink").F) do
  if f.leg and f.leg ~= 1 and f.leg ~= 4 then
    for k = 0, (f.n or 1) - 1 do PLF[f.leg + k] = f.off + k end
  end
end
if NEW then print("-- against TS_TrackProbe 2.0.0 (no parameters)") end

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
-- (REAPER holds back the channels a plugin doesn't use by the latency it
-- reports, so the copies arrive in line: no lag for it)
check("latency of the first: none",   F(5).params[TP.P_LAG] or 0, 0)
check("latency of the second",        F(5).params[TP.P_LAG + 1] or 0, 0)
if NEW then
  -- the pair named in track 3's block: places + 1 (pre at 0, post at 5)
  check("2.0: the pre named",            gmem[0x100000 + 3 * 128 + 0], 1)
  check("2.0: the post named",           gmem[0x100000 + 3 * 128 + 1], 6)
end
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
check("unused taps unplugged",        inbits(5, 10) .. "," .. inbits(5, 17), "0,0")
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
-- a track armed to record: no test noise in the take
track.recarm = 1
TP.sync(track)
check("armed to record: not armed for the zero", F(0).params[TP.P_ARM], 0)
track.recarm = 0
TP.sync(track)
check("disarmed: armed for it again",  F(0).params[TP.P_ARM], 1)
F(5).params[TP.P_CAL] = 1; F(5).params[TP.P_CAL + 1] = 3
TP.invalidate()
check("cal status, tap 1",            TP.cal_status(track, "{C1}"), 1)
check("cal status, tap 2",            TP.cal_status(track, "{C2}"), 3)
check("cal status, not tapped",       TP.cal_status(track, "{EQ}"), nil)

-- a reported latency changing: nothing to do
F(2).pdc = 128
check("latency change: no re-route",  TP.sync(track), false)
check("  nor a lag",                  F(5).params[TP.P_LAG] or 0, 0)
-- a latency the trace measured (one the plugin doesn't report): the probe
-- is told, without re-routing
TP.set_measured_lag("{C1}", 96)
check("measured lag: no re-route",    TP.sync(track), false)
check("  but the probe is told",      F(5).params[TP.P_LAG], 96)
for k in pairs(TP.measured_lag) do TP.measured_lag[k] = nil end
reaper.SetExtState("TS_CV_WEB", "lags", "", false)
now_t = now_t + 1
TP.sync(track)

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

-- ---------------------------------------------------------------- a plugin added to the chain
-- What reaches the post probe's tap pins, worked out by passing names
-- through the top level: each output pin writes "<guid>.L", ".R" or
-- ".x<pin>" to its channels, and a channel no output writes keeps what
-- it had. Returns, per tap, "before L/after L" as the probe sees them, and
-- what they should be (the measured plugin's input and output).
local function flow()
  index()
  local chan = {}
  for c = 1, 64 do chan[c] = "in" .. c end
  local input_of, seen = {}, {}
  for i, f in ipairs(track.fx) do
    input_of[f.guid] = chan[1]
    if f.name:find("TrackProbe", 1, true) and i > 1 then
      for p = 2, 17 do
        local m = f.pin_in[p]
        if m then for c in pairs(TP.channels_of(m[1], m[2])) do seen[p] = chan[c] end end
      end
    end
    local new = {}
    for p = 0, f.nout - 1 do
      local m = f.pin_out[p]
      for c in pairs(TP.channels_of(m[1], m[2])) do
        new[c] = f.guid .. (p == 0 and ".L" or p == 1 and ".R" or (".x" .. p))
      end
    end
    for c, v in pairs(new) do chan[c] = v end
  end
  local rec = TP.parse_record(track.ext[TP.EXT_KEY] or "")
  local got, want = {}, {}
  for i, t in ipairs(rec and rec.taps or {}) do
    local p0 = 2 + (i - 1) * 4
    got[#got + 1] = tostring(seen[p0]) .. "/" .. tostring(seen[p0 + 2])
    want[#want + 1] = tostring(input_of[t.guid]) .. "/" .. t.guid .. ".L"
  end
  return table.concat(got, " "), table.concat(want, " ")
end

reset()
measure = { ["LA-2A"] = true, ["1176"] = true }
package.loaded["TS_CV_Mappings"].get = function(key) return { measure = measure[key] or nil } end
TP.invalidate()
TP.sync(track)
local got, want = flow()
check("added: the taps read right to begin with", got, want)
-- a plugin added after them, before the post probe, taking all 12 channels
table.insert(track.fx, 6, fx("VST3: Pro-L 2 (FabFilter)", "{NEW}", 12, 12))
got, want = flow()
check("added: it writes over the copies", got ~= want, true)
TP.invalidate()
TP.sync(track)
got, want = flow()
check("added: the copies come through again", got, want)
check("added: its own channels untouched", outbits(5, 0) .. "," .. outbits(5, 1) .. "," .. outbits(5, 3),
      b(1) .. "," .. b(2) .. "," .. b(4))
check("added: and nothing more to do", TP.sync(track), false)
-- one added in front of a tapped plugin, that follows the track's channel
-- count as it grows: it changes the writers, so the routing is laid again,
-- and whatever it takes on the way is cleared
reset()
TP.invalidate()
TP.sync(track)
table.insert(track.fx, 3, fx("VST3: Saturn 2 (FabFilter)", "{FOL}", track.nch, track.nch, { follow = true }))
TP.invalidate()
TP.sync(track)
got, want = flow()
check("follower: the copies come through", got, want)
check("follower: the track grew past it", track.nch > 12, true)
check("follower: settles", TP.sync(track), false)
got, want = flow()
check("follower: still right", got, want)
-- one routed onto a copy's channel on purpose (not REAPER's own mapping):
-- left as it is, and the taps move to other channels
reset()
TP.invalidate()
TP.sync(track)
local ch_was = TP.parse_record(track.ext[TP.EXT_KEY]).taps[1].post
local eq_was = F(1).pin_out[0][1]
F(1).pin_out[0] = { eq_was | b(ch_was), 0 }
TP.invalidate()
check("routed on purpose: laid again", TP.sync(track), true)
local ch_now = TP.parse_record(track.ext[TP.EXT_KEY]).taps[1].post
check("routed on purpose: its pin kept", F(1).pin_out[0][1] & b(ch_was), b(ch_was))
check("routed on purpose: the taps moved", ch_now ~= ch_was and ch_now + 1 ~= ch_was, true)
check("routed on purpose: settles", TP.sync(track), false)

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
-- only the tracks on screen measure: a track read is named in its block
-- (TS_TrackProbe's ONLY THE TRACKS ON SCREEN), and the gate keeps moving
do
  local blk = 0x100000 + 3 * 128 + TP.WATCH_OFF      -- track 3: index 2
  gmem[TP.GATE_SLOT], gmem[blk] = nil, nil
  TP.update()
  local g1, w1 = gmem[TP.GATE_SLOT], gmem[blk]
  TP.update()
  check("on screen: the gate moves",       g1 ~= nil and gmem[TP.GATE_SLOT] ~= g1, true)
  check("on screen: named when read",      w1 ~= nil and gmem[blk] ~= w1, true)
  now_t = now_t + 1                                  -- nothing has read it for a second
  local w2 = gmem[blk]
  TP.update()
  check("on screen: not named once unread", gmem[blk], w2)
  TP.levels(track, "{C3}")
  TP.update()
  check("on screen: named again when read", gmem[blk] ~= w2, true)
end
-- a multiband: the probe splits the tap's audio at the crossovers asked for
check("multiband: asked",              TP.set_mb(track, "{C1}", { 200, 2000 }), true)
check("multiband: tap and crossovers", ("%d %d %d %d"):format(F(5).params[TP.P_MB], F(5).params[TP.P_MBX],
      F(5).params[TP.P_MBX + 1], F(5).params[TP.P_MBX + 2] or 0), "1 200 2000 0")
F(5).params[TP.P_MBGR + 1] = 4.5
check("multiband: a band's reduction", TP.band_gr(track, "{C1}", 2), 4.5)
check("multiband: a levels-only tap can't", TP.set_mb(track, "{C3}", { 300 }), false)
F(5).params[TP.P_MB] = 2
check("multiband: another tap's bands aren't its", TP.band_gr(track, "{C1}", 2), nil)
F(5).params[TP.P_MB] = 0
-- stereo: one tap's output (TS_TrackProbe 2.4.0+), and the scope one
-- track writes; an older probe says so
if NEW then
  local b = 0x100000 + 3 * 128
  gmem[b + 125] = 0
  check("stereo: an older probe",        TP.set_stereo(track, "{C3}"), "old")
  gmem[b + 125] = 1
  check("stereo: asked",                 TP.set_stereo(track, "{C3}"), true)
  local ti = TP.tap_index(track, "{C3}")
  check("stereo: its tap and the scope's writer", ("%d %d"):format(gmem[b + 25], gmem[TP.ST_CTRL]), ti .. " 4")
  gmem[b + 122], gmem[b + 123], gmem[b + 124] = 0.5, -12, -20
  gmem[TP.ST_HDR], gmem[TP.ST_HDR + 1], gmem[TP.ST_HDR + 2] = 7, 2, 4
  for k = 0, 3 do gmem[TP.ST_PTS + k] = (k + 1) / 10 end
  local sv = TP.stereo(track, "{C3}")
  check("stereo: read",                  ("%.1f %d %d %d %.1f"):format(sv.corr, sv.mid, sv.side, #sv.pts, sv.pts[4]),
        "0.5 -12 -20 4 0.4")
  check("stereo: not another plugin's",  TP.stereo(track, "{C1}"), nil)
  gmem[TP.ST_HDR + 2] = 9
  check("stereo: another track's scope", TP.stereo(track, "{C3}").pts, nil)
  -- each channel's levels, at this track's place for this tap
  local lb = TP.LR_BASE + 3 * TP.LR_STRIDE + (ti - 1) * 8
  for k = 0, 7 do gmem[lb + k] = -10 - k end
  local lr = TP.levels_lr(track, "{C3}")
  check("stereo: levels per channel", ("%d %d %d %d"):format(lr.in_pk[1], lr.in_pk[2], lr.out_pk[2], lr.out_rms[2]), "-10 -11 -13 -17")
  gmem[b + 125] = 0
  check("stereo: an older probe's levels per channel", TP.levels_lr(track, "{C3}").old, true)
  gmem[b + 125] = 1
end
-- third-octaves: one tap a probe, read back from gmem
check("fine: a gain tap can be",       TP.fine_ok(track, "{C1}"), true)
check("fine: a levels-only tap can't", TP.fine_ok(track, "{C3}"), false)
if not NEW then
  probe_old = true
  check("fine: an older probe says so",  TP.fine_ok(track, "{C1}"), "old")
  check("fine: and isn't asked",         TP.set_fine(track, "{C1}"), false)
  probe_old = false
end
check("fine: asked",                   TP.set_fine(track, "{C1}"), true)
check("fine: the probe's tap",         F(5).params[TP.P_FINE], 1)
check("fine: nothing published yet",   TP.fine(track, "{C1}"), nil)
do
  local b = TP.FINE_GM + 2 * TP.FINE_GSTR   -- the track's index, 2
  gmem[b], gmem[b + 1], gmem[b + 2], gmem[b + 3] = 7, 30, 1, 1
  for k = 0, 29 do gmem[b + 8 + k] = -999; gmem[b + 72 + k] = -40 end
  gmem[b + 8 + 16] = -3.5          -- 1 kHz reduced 3.5 dB
  gmem[b + 8 + 17] = 0.5
  local fd = TP.fine(track, "{C1}")
  check("fine: read back",             fd and ("%d %s %s"):format(fd.n, fd.d[17], tostring(fd.d[1])), "30 -3.5 nil")
  check("fine: band 17 is 1 kHz",      fd and math.floor(fd.f[17] + 0.5), 1000)
  check("fine: the zero was measured", fd and fd.cal, true)
  now_t = now_t + 1                 -- the count hasn't moved in a second: stale
  check("fine: a stopped count is old", TP.fine(track, "{C1}"), nil)
  gmem[b] = 8
  check("fine: a moving one isn't",    TP.fine(track, "{C1}") ~= nil, true)
  gmem[b + 2] = 2
  check("fine: another tap's isn't its", TP.fine(track, "{C1}"), nil)
  gmem[b + 2] = 1
end
-- let go when nobody asks; the web bridge asks politely
now_t = now_t + 2
TP.fine_tidy(os.clock() + now_t)
check("fine: let go when nobody asks",  F(5).params[TP.P_FINE], 0)
F(5).params[TP.P_FINE] = 2
check("fine: polite doesn't take it",   TP.set_fine(track, "{C1}", true), false)
check("fine: ...and leaves it",         F(5).params[TP.P_FINE], 2)
F(5).params[TP.P_FINE] = 0
check("fine: polite takes a free one",  TP.set_fine(track, "{C1}", true), true)
F(5).params[TP.P_FINE] = 0
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
if not NEW then
  local real = reaper.TrackFX_GetParamName
  reaper.TrackFX_GetParamName = function() return true, "Bypass" end
  TP.invalidate()
  check("old probe: levels say so",      TP.levels(track, "{C3}") and TP.levels(track, "{C3}").old, true)
  F(5).params[TP.P_NOGR] = 99
  TP.sync(track)
  check("old probe: param 24 untouched", F(5).params[TP.P_NOGR], 99)
  reaper.TrackFX_GetParamName = real
  TP.invalidate()
end
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
      "v2|TOP|{POST}|{T},{PRE}+{EQ}+{X},5,7,0,g,{K1}+{K2}")
check("nested: no lag for its latency", F(POST).params[TP.P_LAG] or 0, 0)
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
check("nested: now v1, no path",       track.ext[TP.EXT_KEY], "v1|TOP|{POST}|{T},{PRE}+{EQ}+{K1},5,7,0,g")
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
  check("ARA: pre probe second, post last", (F(1).params[TP.P_ROLE] or 0) .. "," .. (F(3).params[TP.P_ROLE] or 0), "0,1")
  check("new probes: tap pins unplugged", inbits(1, 2) .. "," .. inbits(1, 17) .. "," .. inbits(3, 2), "0,0,0")
  check("new probes: main pins kept",   inbits(1, 0) .. "," .. inbits(1, 1), b(1) .. "," .. b(2))
  check("ARA: the pair is found",        TP.status(track, "{J}"), "ok")
  check("ARA: Melodyne outside it",      TP.status(track, "{MEL}"), "outside")
  reaper.GetTrackStateChunk, reaper.TrackFX_AddByName = nil, nil
end

-- ---------------------------------------------------------------- probes hidden, kept at the ends
do
  -- REAPER's move: the destination is read against the chain before the
  -- move; within one level that's the final slot
  reaper.TrackFX_CopyToTrack = function(tr, src, dtr, dest, move)
    index()
    local function find(list)
      for i, f in ipairs(list) do
        if f.addr == src then return list, i end
        if f.kids then local l, j = find(f.kids) if l then return l, j end end
      end
    end
    local list, i = find(tr.fx)
    local f = table.remove(list, i)
    table.insert(tr.fx, math.min(dest, #tr.fx) + 1, f)
  end
  reaper.GetTrackStateChunk = function() return true, "<TRACK\n<FXCHAIN\n<JS x \"\"\n>\n>\n>" end
  local function P(role, g) return fx("JS: TS_TrackProbe", g, 18, 2, { params = { [0] = role } }) end
  local function order()
    index()
    local t = {}
    for _, f in ipairs(track.fx) do
      t[#t + 1] = f.guid:gsub("[{}]", "")
      if f.kids then
        local k = {}
        for _, c in ipairs(f.kids) do k[#k + 1] = c.guid:gsub("[{}]", "") end
        t[#t] = t[#t] .. "[" .. table.concat(k, " ") .. "]"
      end
    end
    return table.concat(t, " ")
  end
  reset()
  track.fx = { P(0, "{PRE}"), fx("A", "{EQ}", 2, 2), P(1, "{POST}"), fx("B", "{NEW}", 2, 2) }
  check("keep: insert after the post probe", (TP.keep_in_place(track)), true)
  check("keep: post back last",           order(), "PRE EQ NEW POST")
  check("keep: nothing more to do",       (TP.keep_in_place(track)), false)
  track.fx = { fx("B", "{NEW}", 2, 2), P(0, "{PRE}"), fx("A", "{EQ}", 2, 2), P(1, "{POST}") }
  TP.keep_in_place(track)
  check("keep: insert in front of the pre probe", order(), "PRE NEW EQ POST")
  track.fx = { P(0, "{PRE}"), P(1, "{POST}"), fx("A", "{EQ}", 2, 2) }
  TP.keep_in_place(track)
  check("keep: post dragged up",          order(), "PRE EQ POST")
  -- the pre probe behind an ARA plugin stays second
  reaper.GetTrackStateChunk = function() return true, '<TRACK\n<FXCHAIN\n<VST "VST3: Melodyne (Celemony)" M.vst3 0 "" 1{2} com.celemony.ara.chunk.13\n>\n>' end
  track.fx = { fx("VST3: Melodyne (Celemony)", "{MEL}", 2, 2), P(0, "{PRE}"), fx("A", "{EQ}", 2, 2), P(1, "{POST}") }
  check("keep: behind ARA, left alone",   (TP.keep_in_place(track)), false)
  track.fx = { fx("VST3: Melodyne (Celemony)", "{MEL}", 2, 2), fx("A", "{EQ}", 2, 2), P(0, "{PRE}"), P(1, "{POST}") }
  TP.keep_in_place(track)
  check("keep: pre back behind ARA",      order(), "MEL PRE EQ POST")
  reaper.GetTrackStateChunk = function() return true, "<TRACK\n<FXCHAIN\n<JS x \"\"\n>\n>\n>" end
  -- one of the pair dragged into a container comes back out
  track.fx = { P(0, "{PRE}"), fx("Container", "{BOX}", 2, 2, { kids = { P(1, "{POST}"), fx("A", "{EQ}", 2, 2) },
               nch = 2, pin_in = {}, pin_out = {} }), fx("B", "{X}", 2, 2) }
  TP.keep_in_place(track)
  check("keep: post out of the container", order(), "PRE BOX[EQ] X POST")
  -- a pair kept together inside a container is deliberate
  track.fx = { fx("Container", "{BOX}", 2, 2, { kids = { P(0, "{PRE}"), fx("A", "{EQ}", 2, 2), P(1, "{POST}") },
               nch = 2, pin_in = {}, pin_out = {} }), fx("B", "{X}", 2, 2) }
  check("keep: a pair in a container left", (TP.keep_in_place(track)), false)
  -- shown: where you put them
  track.fx = { P(0, "{PRE}"), P(1, "{POST}"), fx("A", "{EQ}", 2, 2) }
  -- state, the Visualizer, the row
  track.fx = { P(0, "{PRE}"), fx("A", "{EQ}", 2, 2), P(1, "{POST}") }
  TP.invalidate()
  check("state: pair",                    TP.probe_state(track), "pair")
  check("vis: none",                      TP.vis_state(track), nil)
  TP.set_vis(track, "post")
  check("vis: post",                      TP.vis_state(track) .. F(2).params[TP.P_VIS] .. F(0).params[TP.P_VIS], "post10")
  TP.set_vis(track, "pre")
  check("vis: pre (post cleared)",        TP.vis_state(track) .. F(2).params[TP.P_VIS], "pre0")
  TP.set_vis(track, nil)
  check("vis: off",                       TP.vis_state(track), nil)
  local list = { { path_t = { 0 }, name = "pre" }, { path_t = { 1 }, name = "eq" }, { path_t = { 2 }, name = "post" },
                 tree = { { path = { 0 } }, { path = { 1 } }, { path = { 2 } } } }
  local st = TP.strip_probes(track, list)
  check("row: probes left out",           #st .. " " .. st[1].name .. " " .. #st.tree .. " " .. st.tree[1].first, "1 eq 1 1")
  -- one probe missing: only it is added
  track.fx = { fx("A", "{EQ}", 2, 2), P(1, "{POST}") }
  TP.invalidate()
  check("state: pre missing",             TP.probe_state(track), "post")
  local added = 0
  reaper.TrackFX_AddByName = function(tr, nm, rec, pos)
    if nm ~= "TS_TrackProbe.jsfx" then return -1 end
    added = added + 1
    local at = (pos == -1) and #tr.fx or (-1000 - pos)
    table.insert(tr.fx, at + 1, fx("JS: TS_TrackProbe", "{N" .. added .. "}", 18, 2, { params = {} }))
    return at
  end
  check("complete: inserted",             (TP.insert_probes(track)), true)
  check("complete: only the pre probe",   added .. " " .. order(), "1 N1 EQ POST")
  check("complete: roles",                (F(0).params[TP.P_ROLE] or 0) .. (F(2).params[TP.P_ROLE] or 0), "01")
  reaper.GetTrackStateChunk, reaper.TrackFX_AddByName, reaper.TrackFX_CopyToTrack = nil, nil, nil
end

-- a receive put on the copies' channels after they were laid: the taps
-- move to channels nothing uses
reset()
TP.invalidate()
TP.sync(track)
do
  local was = TP.parse_record(track.ext[TP.EXT_KEY]).taps[1].post
  track.recv[1].dst = was - 1          -- onto that pair
  TP.invalidate()
  check("receive on the copies: laid again",  TP.sync(track), true)
  local r = TP.parse_record(track.ext[TP.EXT_KEY])
  local clash = false
  for _, t in ipairs(r.taps) do
    for _, ch in ipairs({ t.pre, t.pre + 1, t.post, t.post + 1 }) do if ch == was or ch == was + 1 then clash = true end end
  end
  check("receive on the copies: moved off it", clash, false)
  got, want = flow()
  check("receive on the copies: the copies come through", got, want)
  check("receive on the copies: then settles", TP.sync(track), false)
end

-- ------------------------------------------------- plugins held at their channels
-- A surround VST3 that follows the track (Pro-C 3), its sidechain on 3/4:
-- widening the track for the copies must not change its layout.
reset()
do
  local pc = fx("VST3: Pro-C 3 (FabFilter)", "{PC3}", 4, 2, { cc = true })
  pc.pin_in[2], pc.pin_in[3] = { b(3), 0 }, { b(4), 0 }
  table.insert(track.fx, 2, pc)
  TP.invalidate()
  TP.sync(track)
  local function find(g) index(); for a, f in pairs(amap) do if f.guid == g then return a, f end end end
  local _, f = find("{PC3}")
  check("held: the track grew",                track.nch > 4, true)
  check("held: its layout kept",               f.nin .. " " .. f.nout .. " " .. tostring(f.held), "4 2 4")
  check("held: its sidechain still on 3/4",    f.pin_in[2][1] .. " " .. f.pin_in[3][1], b(3) .. " " .. b(4))
  check("held: recorded",                      track.ext["P_EXT:TS_CV_HOLD"], "TOP|4|{PC3}")
  -- one added later, following the widened track: held at the same count
  table.insert(track.fx, 3, fx("VST3: Pro-Q 4 (FabFilter)", "{PQ4}", track.nch * 2, track.nch, { cc = true }))
  TP.invalidate()
  check("held: a later one, at the next check", TP.sync(track), true)
  local _, q = find("{PQ4}")
  check("held: the later one too",             tostring(q.held), "4")
  -- (held at 4 it has 4 sidechain inputs on 5..8, where the copies are:
  -- unplugged, and noted to be put back)
  check("held: both recorded",                 track.ext["P_EXT:TS_CV_HOLD"],
        "TOP|4|{PC3},{PQ4}|{PQ4}:4:16:0+{PQ4}:5:32:0+{PQ4}:6:64:0+{PQ4}:7:128:0")
  check("held: its sidechain inputs off the copies", q.pin_in[4][1] .. q.pin_in[5][1] .. q.pin_in[6][1] .. q.pin_in[7][1], "0000")
  check("held: then nothing to do",            TP.sync(track), false)
  -- the probes taken out: the track back to 4, both following it again
  TP.remove_probes(track)
  local _, f2 = find("{PC3}")
  check("released: the track back to 4",       track.nch, 4)
  check("released: following again",          tostring(f2.held), "nil")
  check("released: the record gone",           track.ext["P_EXT:TS_CV_HOLD"], "")
end
local measure_was, get_was = measure, package.loaded["TS_CV_Mappings"].get
-- A plugin with a sidechain on a two-channel track (Waves SSLComp: 4 in,
-- its sidechain on 3/4, channels the track hasn't got). Widened, the
-- track has them, silent, and the plugin would key from them: unplugged
-- while the probes are in, put back when they come out.
reset()
do
  track.nch, track.recv = 2, {}
  local w = fx("VST3: SSLComp Stereo (Waves)", "{WV}", 4, 2)
  table.insert(track.fx, 2, w)
  measure = { ["SSLComp Stereo"] = true }
  package.loaded["TS_CV_Mappings"].get = function(key) return { measure = measure[key] or nil } end
  TP.invalidate()
  TP.sync(track)
  local function find(g) index(); for a, f in pairs(amap) do if f.guid == g then return a, f end end end
  local _, f = find("{WV}")
  check("sidechain: the track grew",            track.nch > 2, true)
  check("sidechain: measured",                  #TP.parse_record(track.ext[TP.EXT_KEY]).taps, 1)
  check("sidechain: unplugged",                 f.pin_in[2][1] .. " " .. f.pin_in[3][1], "0 0")
  check("sidechain: its main inputs kept",      f.pin_in[0][1] .. " " .. f.pin_in[1][1], b(1) .. " " .. b(2))
  -- (the 1176's sidechain too: 4 in, on 3/4)
  check("sidechain: noted",                     track.ext["P_EXT:TS_CV_HOLD"], "TOP|2||{C2}:2:4:0+{C2}:3:8:0+{WV}:2:4:0+{WV}:3:8:0")
  check("sidechain: settles",                   TP.sync(track), false)
  TP.remove_probes(track)
  local _, f2 = find("{WV}")
  check("sidechain out: the track back to 2",   track.nch, 2)
  check("sidechain out: plugged back in",       f2.pin_in[2][1] .. " " .. f2.pin_in[3][1], b(3) .. " " .. b(4))
  check("sidechain out: the record gone",       track.ext["P_EXT:TS_CV_HOLD"], "")
end
-- A sidechain the track really has (a receive on 3/4, the track at 4):
-- left alone.
reset()
do
  local w = fx("VST3: SSLComp Stereo (Waves)", "{WV}", 4, 2)
  table.insert(track.fx, 2, w)
  measure = { ["SSLComp Stereo"] = true }
  package.loaded["TS_CV_Mappings"].get = function(key) return { measure = measure[key] or nil } end
  TP.invalidate()
  TP.sync(track)
  local function find(g) index(); for a, f in pairs(amap) do if f.guid == g then return a, f end end end
  local _, f = find("{WV}")
  check("real sidechain: kept",                 f.pin_in[2][1] .. " " .. f.pin_in[3][1], b(3) .. " " .. b(4))
end
measure, package.loaded["TS_CV_Mappings"].get = measure_was, get_was
-- ... unless something else now uses the channels above: the receive
-- moved up to 17/18 while the taps were in
reset()
do
  local pc = fx("VST3: Pro-C 3 (FabFilter)", "{PC3}", 4, 2, { cc = true })
  table.insert(track.fx, 2, pc)
  TP.invalidate()
  TP.sync(track)
  local grown = track.nch
  track.recv[1].dst = 16
  TP.remove_probes(track)
  check("kept: channels stay for the receive", track.nch, grown)
  check("kept: still held",                    tostring(pc.held), "4")
end

-- ---------------------------------------------------------------- eight
-- A probe that takes eight (34 input pins) measures past four; an older
-- one (18) stops at four.
reset()
measure = { ["LA-2A"] = true, ["1176"] = true, ["Pro-C 2"] = true, ["Comp A"] = true, ["Comp B"] = true, ["Comp C"] = true, ["Comp D"] = true }
package.loaded["TS_CV_Mappings"].get = function(key) return { measure = measure[key] or nil } end
-- (Pro-C 2 reports its own: not measured; six that don't)
for k, nm in ipairs({ "Comp A", "Comp B", "Comp C", "Comp D" }) do
  table.insert(track.fx, #track.fx, fx("VST3: " .. nm .. " (Test)", "{X" .. k .. "}", 2, 2, { pdc = 10 * k }))
end
TP.invalidate()
TP.sync(track)
check("eight: an older probe measures four", #TP.parse_record(track.ext[TP.EXT_KEY]).taps, 4)
local post = track.fx[#track.fx]
post.nin = 34
for p = 18, 33 do post.pin_in[p] = { 0, 0 } end
TP.invalidate()
TP.sync(track)
local rec8 = TP.parse_record(track.ext[TP.EXT_KEY])
check("eight: one that takes eight measures all six", #rec8.taps, 6)
local t6 = rec8.taps[6]
check("eight: tap 6's pins on its copies", ("%d %d"):format(post.pin_in[22][1], post.pin_in[24][1]), ("%d %d"):format(TP.bit(t6.pre), TP.bit(t6.post)))
check("eight: tap 7's pins unplugged", post.pin_in[26][1] .. " " .. post.pin_in[29][1], "0 0")
if NEW then
  TP.set_measured_lag(t6.guid, 40)
  TP.sync(track)
  check("eight: tap 6's lag apart from 1..4's", gmem[0x100000 + 3 * 128 + 50 + 1], 40)
  for k in pairs(TP.measured_lag) do TP.measured_lag[k] = nil end
  reaper.SetExtState("TS_CV_WEB", "lags", "", false)
  now_t = now_t + 1
  TP.sync(track)
  check("eight: taps in use", gmem[0x100000 + 3 * 128 + 8], 6)
end
check("eight: settles", TP.sync(track), false)

-- a latency the window measured: the web bridge (its own TP, which never
-- measured it) lays the same, so the two don't undo each other
do
  local g = rec8.taps[1].guid
  TP.set_measured_lag(g, 777)
  TP.sync(track)
  check("lag: the measured one laid", TP.parse_record(track.ext[TP.EXT_KEY]).taps[1].lag, 777)
  for k in pairs(TP.measured_lag) do TP.measured_lag[k] = nil end
  now_t = now_t + 1
  check("lag: another script reads it", TP.lag_of(g), 777)
  TP.invalidate()
  check("lag: and leaves the record", TP.sync(track), false)
  check("lag: still the measured one", TP.parse_record(track.ext[TP.EXT_KEY]).taps[1].lag, 777)
end

-- ------------------------------------------------- measured first
-- A plugin that reports its own reduction (Pro-C 2) is measured too when
-- that's what's shown, and its reading is the measured one once its zero
-- is measured -- its own figure until then.
reset()
measure = { ["LA-2A"] = true, ["1176"] = true }
package.loaded["TS_CV_Mappings"].get = function(key) return { measure = measure[key] or nil } end
reaper.SetExtState("TS_ChannelView", TP.READING_KEY, "measured", true)
TP.invalidate()
TP.sync(track)
do
  local r = TP.parse_record(track.ext[TP.EXT_KEY])
  local g = {}
  for _, t in ipairs(r.taps) do g[#g + 1] = t.guid end
  check("measured first: the reporting one tapped too", table.concat(g, " "), "{C1} {C2} {C3}")
  check("measured first: its own figure before the zero", TP.measured_for_reporting(track, "{C3}"), nil)
  F(5).params[TP.P_CAL + 2] = 1
  F(5).params[TP.P_GR + 2] = 4.5
  TP.invalidate()
  check("measured first: measured once the zero is", TP.measured_for_reporting(track, "{C3}"), 4.5)
  F(5).params[25 + 2] = -150          -- tap 3's input peak: silence
  -- reporting no reduction while stopped and silent (a compressor): still measured
  check("measured first: a compressor at rest", TP.measured_for_reporting(track, "{C3}", 0), 4.5)
  -- reporting 20 dB while stopped and silent: a gate, shut on the silence
  -- (its zero is its shut level): its own figure, once it's held a moment
  check("shut: not straight away", TP.measured_for_reporting(track, "{C3}", 20), 4.5)
  now_t = now_t + 2
  check("shut: its own figure", TP.measured_for_reporting(track, "{C3}", 20), nil)
  check("shut: and stays so",   TP.measured_for_reporting(track, "{C3}", 0), nil)
  -- playing, it's looked at afresh: a compressor that only seemed shut
  -- (its figure held at its last on the silence) is measured again
  local gps = reaper.GetPlayState
  reaper.GetPlayState = function() return 1 end
  check("shut: playing, measured again", TP.measured_for_reporting(track, "{C3}", 0), 4.5)
  reaper.GetPlayState = gps
  F(5).params[TP.P_CAL + 2] = 3
  TP.invalidate()
  check("measured first: touched since, its own again", TP.measured_for_reporting(track, "{C3}"), nil)
  -- a multiband, a de-esser, a gate: their own figure, not tapped for it
  for _, nm in ipairs({ "VST3: Pro-MB (FabFilter)", "VST3: Pro-DS (FabFilter)", "VST3: Pro-G (FabFilter)", "VST: ReaXcomp (Cockos)" }) do
    check("keeps its own: " .. nm, TP._keeps_own(track, 0, nil) == false and (function()
      local f = F(4); local was = f.name; f.name = nm
      local r = TP._keeps_own(track, 4, nil); f.name = was; return r end)(), true)
  end
  check("a compressor doesn't", TP._keeps_own(track, 4, nil), false)
  check("a Multiband canvas does", TP._keeps_own(track, 4, { canvas = { kind = "multi" } }), true)
  TP.set_zero_on(false)
  TP.sync(track)
  check("measured first, zero off: not tapped", #TP.parse_record(track.ext[TP.EXT_KEY]).taps, 2)
  TP.set_zero_on(true)
  TP.set_measured_first(false)
  TP.sync(track)
  check("its own: not tapped", #TP.parse_record(track.ext[TP.EXT_KEY]).taps, 2)
  check("its own: nothing measured to show", TP.measured_for_reporting(track, "{C3}"), nil)
end

-- ------------------------------------------------- make-up gain
-- Which control is a plugin's make-up, and what goes to the probe: its dB
-- + 1000 * a count, the count moved when what's taken out changes rather
-- than the audio. (The block: a probe with no parameters.)
do
  local s = TP.makeup_of({ controls = {}, canvas = { kind = "multi", nb = 3, roles = { Output = 20, B1Gain = 5, B3Gain = 9 } } })
  check("make-up: a multiband's Output", s.p, 20)
  check("make-up:   and its bands' Gain", s.bands[1] .. "," .. s.bands[3], "5,9")
  check("make-up: a mark wins over the role", TP.makeup_of({ mug = 4, controls = { { param = 4 } },
        canvas = { kind = "comp", roles = { Makeup = 7 } } }).p, 4)
  check("make-up: a mark on no control: the role", TP.makeup_of({ mug = 4, controls = {},
        canvas = { kind = "comp", roles = { Makeup = 7 } } }).p, 7)
  check("make-up: none", TP.makeup_of({ controls = {} }), nil)
end
if NEW then
  reset()
  measure = { ["LA-2A"] = true, ["1176"] = true }
  reaper.SetExtState("TS_ChannelView", TP.READING_KEY, "own", true)
  local Ms = package.loaded["TS_CV_Mappings"]
  local mk = { ["LA-2A"] = 7 }
  local cvs = {}
  Ms.get = function(key)
    return { measure = measure[key] or nil, mug = mk[key], canvas = cvs[key],
             controls = mk[key] and { { param = mk[key] } } or {} }
  end
  Ms.range_line = Ms.range_line or function() return "" end
  local text = { ["{C1}"] = "+3.0 dB" }
  reaper.TrackFX_GetFormattedParamValue = function(tr, a, p)
    local f = F(a); return true, (f and p == 7 and text[f.guid]) or "0.50"
  end
  reaper.TrackFX_GetParamNormalized = function() return 0.5 end
  TP.invalidate(); TP.sync(track)
  local B = 0x100000 + 3 * 128
  local function slot(i) return gmem[B + (i <= 4 and 25 + i or 53 + i)] or 0 end
  local function rst() return gmem[B + 13] or 0 end
  -- a slot: its dB and its count
  local function at(i) local v = slot(i); local k = math.floor((v + 500) / 1000); return v - 1000 * k, k end
  local k0 = select(2, at(1))
  TP.update()
  local v, k = at(1)
  check("make-up: written in dB", v, 3)
  check("make-up:   with a new count", k, (k0 + 1) % 100)
  check("make-up: none: nothing taken out", (at(2)), 0)
  text["{C1}"] = "-2.5 dB"; TP.update()
  check("make-up: moved, the same count", select(2, at(1)) == k and (at(1)) == -2.5, true)
  gmem[B + 126] = 1                         -- the probe follows make-up
  local r0 = rst()
  TP.touched(track, "{C1}", 7)
  check("make-up: moving it isn't a touch", rst(), r0)
  TP.touched(track, "{C1}", 3)
  check("make-up: moving anything else is", rst() ~= r0, true)
  local function next_one(name, want)
    TP.update()
    local v2, k2 = at(1)
    check(name, v2 == want and k2 == (k + 1) % 100, true)
    k = k2
  end
  text["{C1}"] = "5.0"
  next_one("make-up: not in dB: nothing taken out, a new count", 0)
  r0 = rst(); TP.touched(track, "{C1}", 7)
  check("make-up:   and moving it is a touch", rst() ~= r0, true)
  text["{C1}"] = "+1.0 dB"
  next_one("make-up: in dB again: a new count", 1)
  mk["LA-2A"] = nil; TP.makeup_changed()
  next_one("make-up: unmarked: nothing, a new count", 0)
  cvs["LA-2A"] = { kind = "comp", roles = { Makeup = 7 } }
  text["{C1}"] = "+4.0 dB"; TP.makeup_changed()
  next_one("make-up: a compressor canvas's Makeup", 4)
  text["{C1}"] = "+6.0 dB"; TP.update(nil, true)
  check("make-up: the web bridge leaves it to the window", (at(1)), 4)
  TP.update()
  check("make-up: the window writes it", (at(1)), 6)
  check("make-up: no multiband split: its bands' gains 0", (gmem[B + 30] or 0) % 1000, 0)
  -- named as one: Makeup and Out Gain, both followed, added up
  check("make-up: names", tostring(TP.makeup_name("Out Gain")) .. tostring(TP.makeup_name("Make-Up Gain [dB]"))
    .. tostring(TP.makeup_name("Output")) .. tostring(TP.makeup_name("Output Mode")) .. tostring(TP.makeup_name("Gain"))
    .. tostring(TP.makeup_name("Wet")),
    "truetruetruefalsefalsetrue")
  local gpn = reaper.TrackFX_GetParamName
  reaper.TrackFX_GetParamName = function(tr, a, p)
    local f = F(a)
    if f and f.guid == "{C1}" then return true, (p == 7 and "Makeup") or (p == 9 and "Out Gain") or "Ratio" end
    return gpn(tr, a, p)
  end
  local gfp = reaper.TrackFX_GetFormattedParamValue
  reaper.TrackFX_GetFormattedParamValue = function(tr, a, p)
    local f = F(a)
    if f and f.guid == "{C1}" and p == 9 then return true, "-2.0 dB" end
    return gfp(tr, a, p)
  end
  cvs["LA-2A"] = nil; TP.makeup_changed()
  next_one("make-up: by name, both added", 4)
  r0 = rst(); TP.touched(track, "{C1}", 9)
  check("make-up:   moving the second isn't a touch", rst(), r0)
  -- a gain that leaves the unit off (Kotelnikov's Makeup: -18 to 18,
  -- "6.0"): its own number, whatever custom range it was given
  local fpn = reaper.TrackFX_FormatParamValueNormalized
  reaper.TrackFX_FormatParamValueNormalized = function(tr, a, p, v)
    local f = F(a)
    if f and f.guid == "{C1}" and p == 9 then return true, v == 0 and "-18.0" or v == 1 and "18.0" or "?" end
    return true, "?"
  end
  reaper.TrackFX_GetFormattedParamValue = function(tr, a, p)
    local f = F(a)
    if f and f.guid == "{C1}" and p == 9 then return true, "6.0" end
    return gfp(tr, a, p)
  end
  TP.makeup_changed()
  local ca
  for a = 0, 20 do local f = F(a); if f and f.guid == "{C1}" then ca = a end end
  check("make-up: a bare gain, its own number", TP.makeup_db(track, ca, 9, { [9] = { lo = -60, hi = 18, unit = "dB", curve = "lin" } }), 6)
  check("make-up: a bare number not across 0 isn't one", TP.makeup_db(track, ca, 3, nil), nil)
  -- Kotelnikov: its readout "6.0", but asked at its position "6.0 dB"
  local fpn2 = reaper.TrackFX_FormatParamValueNormalized
  reaper.TrackFX_FormatParamValueNormalized = function(tr, a, p, v)
    local f = F(a)
    if f and f.guid == "{C1}" and p == 9 then return true, ("%.1f dB"):format(v == 0.5 and 6 or -60) end
    return true, "?"
  end
  TP.makeup_changed()
  check("make-up: in dB when asked at its place", TP.makeup_db(track, ca, 9, { [9] = { lo = -60, hi = 18, unit = "dB", curve = "lin" } }), 6)
  reaper.TrackFX_FormatParamValueNormalized = fpn2
  TP.makeup_changed()
  TP.update()
  check("make-up: by name, a bare gain added", (at(1)), 12)
  reaper.TrackFX_FormatParamValueNormalized = fpn
  TP.makeup_changed()
  reaper.TrackFX_GetParamName, reaper.TrackFX_GetFormattedParamValue = gpn, gfp
  gmem[B + 126] = 0
  r0 = rst(); TP.touched(track, "{C1}", 7)
  check("make-up: an older probe: moving it is a touch", rst() ~= r0, true)
end

-- ---------------------------------------------------------------- spectrum
if NEW then
  reset(); TP.invalidate(); TP.sync(track)
  local B = 0x100000 + 3 * 128
  local S = TP.SPEC_BASE + 3 * TP.SPEC_STRIDE
  check("spectrum: none before the probe writes one", TP.spectrum(track), nil)
  local h1 = gmem[B + 127]
  check("spectrum: asked for (field 127)", h1 ~= nil and h1 ~= 0, true)
  now_t = now_t + 0.05
  TP.spectrum(track)
  check("spectrum: asked for again: 127 moves", gmem[B + 127] ~= h1, true)
  gmem[S] = 1; gmem[S + 1] = 4; gmem[S + 2] = 20; gmem[S + 3] = 20000; gmem[S + 5] = 4
  for i = 0, 3 do gmem[S + 16 + i] = -10 * (i + 1) end
  now_t = now_t + 0.05
  local s = TP.spectrum(track)
  check("spectrum: this track's", s and (s.n .. " " .. s.lo .. " " .. s.hi .. " " .. s.db[1] .. " " .. s.db[4]), "4 20 20000 -10 -40")
  gmem[S + 5] = 5; now_t = now_t + 0.05
  check("spectrum: another track's place: none", TP.spectrum(track), nil)
  gmem[S + 5] = 4; now_t = now_t + 2
  check("spectrum: not moving for a second: none", TP.spectrum(track), nil)
  gmem[S] = 2; now_t = now_t + 0.05
  check("spectrum: moving again", TP.spectrum(track) ~= nil, true)
  -- an older probe: Track Analyser's, only while it shows this track
  gmem[S] = 0
  for i = 0, 15 do gmem[0x20000 + i] = 0 end
  gmem[0x20000] = 7; gmem[0x20000 + 11] = 1; gmem[0x20000 + 16] = 2
  gmem[0x20000 + 17] = 20; gmem[0x20000 + 18] = 20000
  gmem[0x20000 + 16384] = -12; gmem[0x20000 + 16388] = -24
  gmem[B + 3] = 0; now_t = now_t + 2
  check("spectrum: Track Analyser's, another track shown: none", TP.spectrum(track), nil)
  gmem[B + 3] = 1; gmem[0x20000] = 8; now_t = now_t + 0.05
  s = TP.spectrum(track)
  check("spectrum: Track Analyser's, this track shown", s and (s.n .. " " .. s.db[1] .. " " .. s.db[2]), "2 -12 -24")
  gmem[B + 3] = 0
  -- listening to a band: only through a probe that writes its own spectrum
  gmem[S] = 0; now_t = now_t + 2; TP.spectrum(track)
  check("listen: an older probe can't", TP.listen(track, 1000, 2, 0), false)
  gmem[S] = 5; gmem[S + 5] = 4; now_t = now_t + 0.05; TP.spectrum(track)
  check("listen: this one can", TP.listen(track, 1000, 2, 1), true)
  local c1 = gmem[S + 8]
  check("listen: what's heard", ("%s %s %s"):format(gmem[S + 6], gmem[S + 7], gmem[S + 9]), "1000 2 1")
  TP.listen(track, 1000, 2, 1)
  check("listen: moving while held", gmem[S + 8] ~= c1, true)
  TP.listen(track)
  check("listen: let go", gmem[S + 6], 0)
  -- held from the web page: kept while it keeps coming, let go after
  gmem[S] = 6; now_t = now_t + 0.05; TP.spectrum(track)
  TP.listen_hold("a", track, function() return 2000, 1.5, 0 end)
  TP.listen_tick()
  check("listen hold: heard", gmem[S + 6], 2000)
  now_t = now_t + 0.2; TP.listen_hold("a", track, function() return 2000, 1.5, 0 end); TP.listen_tick()
  check("listen hold: kept while it comes", gmem[S + 6], 2000)
  now_t = now_t + 0.5; TP.listen_tick()
  check("listen hold: let go when it stops", gmem[S + 6], 0)
  local sw = {}
  TP.listen_hold("b", track, nil, function(on) sw[#sw + 1] = tostring(on) end)
  TP.listen_release("b")
  check("listen hold: the band's own Solo, on and off", table.concat(sw, ","), "true,false")
end

-- a plugin's own meters moving on the test noise aren't touches: no new
-- zero asked for while one is measured, or just after
do
  local got, real, real_lt = {}, TP.touched, reaper.GetLastTouchedFX
  TP.touched = function(_, _, p) got[#got + 1] = tostring(p) end
  local lt = { 1, 0, 1 }
  reaper.GetLastTouchedFX = function() return true, lt[1], lt[2], lt[3] end
  local ph = TP.CAL_BASE + 1                      -- track 1's pre probe phase
  TP.update()                                      -- the first seen: remembered
  lt = { 1, 0, 2 }; TP.update()                    -- a touch
  gmem[ph] = 1
  lt = { 1, 0, 5 }; TP.update(); lt = { 1, 0, 6 }; TP.update()
  gmem[ph] = 0
  lt = { 1, 0, 7 }; TP.update()                    -- a moment after
  now_t = now_t + 4
  lt = { 1, 0, 8 }; TP.update()                    -- later: a touch again
  check("zero run: its meters aren't touches", table.concat(got, ","), "2,8")
  TP.touched, reaper.GetLastTouchedFX = real, real_lt
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
