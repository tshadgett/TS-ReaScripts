-- @noindex  (a development tool, not a package: never installed)
-- dev/TS_CV_LearnSim.lua -- learning an EQ layout (TS_CV_Learn) against
-- fake plugins in a fake REAPER: an EQ73-style plugin (switched
-- frequencies, a fixed high shelf, proportional Q, a dial that's a little
-- off) and a parametric one that reports Hz / dB / Q (learned quickly).
-- Checks what's learned against the fakes' own curves. Plain Lua:
--   lua5.4 dev/TS_CV_LearnSim.lua
local here = (debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "./")
package.path = here .. "../?.lua;" .. package.path
local fails = 0
local function check(name, got, want)
  local ok = got == want
  if not ok then fails = fails + 1 end
  print((ok and "ok   " or "FAIL ") .. name .. (ok and "" or ("  got " .. tostring(got) .. " want " .. tostring(want))))
end
local function checkf(name, fn) check(name, fn() and true or false, true) end

local ME = require("TS_CV_MapEQ")
local BASE = 1048576

-- ---------------------------------------------------------------------
-- the fake REAPER
-- ---------------------------------------------------------------------
local tracks, gmem, clock = {}, {}, 0
local P, NP, truth          -- the current fake plugin
local truth_gain            -- a fake compressor's gain for a sine at a level
local truth_rt              -- a fake reverb's decay time, ms
local truth_sat             -- a fake saturator: y(x) for the plugin's settings
local old_jsfx = false      -- a REAPER still running the measuring plugin from before
local answer = true         -- whether the analyser answers (Run FX when stopped)

local function fmt(p, n)
  local d = P[p]
  if d.fn then return d.fn(n) end
  if d.list then local i = math.min(#d.list, math.floor(n * #d.list) + 1); return d.list[i], i end
  return string.format("%.1f %s", d.lo + (d.hi - d.lo) * n, d.unit)
end
local function newtrack(name) return { name = name, fx = {}, info = {} } end

reaper = {
  CountTracks = function() return #tracks end,
  InsertTrackAtIndex = function(i) table.insert(tracks, i + 1, newtrack("")) end,
  GetTrack = function(_, i) return tracks[i + 1] end,
  GetSetMediaTrackInfo_String = function(t, _, v, set) if set then t.name = v end return true, t.name end,
  SetMediaTrackInfo_Value = function(t, k, v) t.info[k] = v end,
  TrackFX_CopyToTrack = function(src, sa, dst, da)
    local c = { kind = "eq", vals = {} }
    for p, v in pairs(src.fx[sa + 1].vals) do c.vals[p] = v end
    table.insert(dst.fx, da + 1, c)
  end,
  TrackFX_GetCount = function(t) return #t.fx end,
  -- the copy's pins, put back to plain stereo
  TrackFX_GetIOSize = function(t, fx) return 0, 4, 2 end,
  TrackFX_SetPinMappings = function(t, fx, out, pin, lo, hi)
    local f = t.fx[fx + 1]; f.pins = f.pins or {}; f.pins[out .. ":" .. pin] = lo
  end,
  TrackFX_AddByName = function(t, name, _, at)
    if not name:match("TS_CV_Learn") then return -1 end
    local pos = -1000 - at
    table.insert(t.fx, pos + 1, { kind = "learn", vals = { [0] = 0, 0, 0, 4, 0.2 } })
    return pos
  end,
  TrackFX_Show = function() end, TrackFX_SetEnabled = function() end, TrackFX_SetOffline = function() end,
  TrackFX_SetParam = function(t, fx, p, v)
    local f = t.fx[fx + 1]; f.vals[p] = v
    if answer and f.kind == "learn" and p == 1 and f.vals[0] == 1 and (f.vals[9] or 0) >= 0.5 then
      -- a reverb's tail after a burst: its level every 10 ms
      local rt = truth_rt(t.fx[fx].vals)
      local nb = 0
      for i = 0, 1499 do
        local tms = i * 10
        -- no rt: the burst straight through, dry, then nothing
        local db = (tms < 330) and 0 or (rt and -60 * (tms - 330) / rt or -120)
        gmem[BASE + 200 + i] = db + (math.random() - 0.5) * 0.4
        nb = i + 1
        if db < -75 then break end
      end
      gmem[BASE + 1] = nb
      gmem[BASE] = v
      return
    end
    if answer and f.kind == "learn" and p == 1 and f.vals[0] == 1 and (f.vals[11] or 0) >= 0.5 then
      -- a sine at the source's level through a saturator: its curve, binned
      -- rising and falling, and its harmonics (a DFT of one period)
      local A = 10 ^ ((f.vals[6] or 0) / 20)
      local y = truth_sat(t.fx[fx].vals)
      local N = 512
      local up, upn, dn, dnn = {}, {}, {}, {}
      for b = 0, 23 do up[b], upn[b], dn[b], dnn[b] = 0, 0, 0, 0 end
      local re, im = {}, {}
      local prev = 0
      for i = 0, N - 1 do
        local x = A * math.sin(2 * math.pi * i / N)
        local v = y(x)
        local b = math.max(0, math.min(23, math.floor((x / A + 1) * 0.5 * 24)))
        if x >= prev then up[b] = up[b] + v; upn[b] = upn[b] + 1 else dn[b] = dn[b] + v; dnn[b] = dnn[b] + 1 end
        prev = x
        for h = 1, 9 do
          re[h] = (re[h] or 0) + v * math.cos(2 * math.pi * h * i / N)
          im[h] = (im[h] or 0) + v * math.sin(2 * math.pi * h * i / N)
        end
      end
      for b = 0, 23 do
        gmem[BASE + 300 + b] = upn[b] > 0 and up[b] / upn[b] or -999
        gmem[BASE + 330 + b] = dnn[b] > 0 and dn[b] / dnn[b] or -999
      end
      local mag = function(h) return math.sqrt(re[h] ^ 2 + im[h] ^ 2) * 2 / N end
      local m1 = math.max(mag(1), 1e-9)
      gmem[BASE + 361] = 20 * math.log(m1 / A, 10)
      for h = 2, 9 do gmem[BASE + 360 + h] = 20 * math.log(math.max(mag(h), 1e-9) / m1, 10) end
      gmem[BASE] = v
      return
    end
    if answer and f.kind == "learn" and p == 1 and f.vals[0] == 1 and (t.fx[1].vals[5] or 0) >= 0.5 then
      -- a sine at the source's level through a compressor: its gain at 1 kHz
      local level = t.fx[1].vals[6] or -40
      gmem[BASE + 1] = 120; gmem[BASE + 3] = level
      for i = 0, 119 do gmem[BASE + 8 + i] = -999 end
      gmem[BASE + 8 + 67] = truth_gain(t.fx[fx].vals, level)
      gmem[BASE] = v
      return
    end
    if answer and f.kind == "learn" and p == 1 and f.vals[0] == 1 then
      local bands = truth(t.fx[fx].vals)
      gmem[BASE + 1] = 120; gmem[BASE + 3] = -20
      for i, c in ipairs(ME.centres()) do
        local db = 0
        for _, b in ipairs(bands) do db = db + ME.band_db(b, c) end
        gmem[BASE + 8 + i - 1] = db + (math.random() - 0.5) * 0.1
      end
      gmem[BASE] = v
    end
  end,
  TrackFX_GetNamedConfigParm = function() return true, "0" end,
  TrackFX_SetNamedConfigParm = function() return true end,
  GetFXEnvelope = function() return nil end,
  TrackFX_FormatParamValueNormalized = function(_, _, p, n) return true, fmt(p, n) end,
  TrackFX_GetFormattedParamValue = function(t, fx, p) return true, fmt(p, t.fx[fx + 1].vals[p] or 0) end,
  TrackFX_SetParamNormalized = function(t, fx, p, v) t.fx[fx + 1].vals[p] = v end,
  TrackFX_GetParamNormalized = function(t, fx, p) return t.fx[fx + 1].vals[p] or 0 end,
  TrackFX_GetParamName = function(t, fx, p)
    local f = t and t.fx and t.fx[fx + 1]
    if f and f.kind == "learn" then
      return true, ({ "Role", "Measurement", "Latency", "Frames", "Settle", old_jsfx and "" or "Signal", old_jsfx and "" or "Level",
        old_jsfx and "" or "Sidechain too", old_jsfx and "" or "Burst", old_jsfx and "" or "Envelope",
        old_jsfx and "" or "Sine frequency", old_jsfx and "" or "Curve" })[p + 1] or ""
    end
    return true, P[p] and P[p].name or ""
  end,
  TrackFX_GetNumParams = function() return NP end,
  PreventUIRefresh = function() end, TrackList_AdjustWindows = function() end,
  DeleteTrack = function(t) for i, x in ipairs(tracks) do if x == t then table.remove(tracks, i) end end end,
  ValidatePtr2 = function(_, t) for _, x in ipairs(tracks) do if x == t then return true end end return false end,
  gmem_attach = function() end, gmem_read = function(i) return gmem[i] end,
  time_precise = function() clock = clock + 0.05; return clock end,
  GetPlayState = function() return 0 end,
  GetResourcePath = function() return "/tmp" end,
}

local M = require("TS_CV_Mappings")
local tmpdir = os.tmpname()
os.remove(tmpdir)
M.init(tmpdir)
local LN = require("TS_CV_Learn")

local function run(job)
  local guard = 0
  while job.state == "starting" or job.state == "measuring" do
    LN.step(job); guard = guard + 1
    if guard > 5000 then break end
  end
end

-- the largest difference, dB, between the fake's curve and the learned
-- one, at a set of settings
local function worst(user, layout, settings)
  local fx, w = user.fx[1], 0
  for _, set in ipairs(settings) do
    for p, v in pairs(set) do fx.vals[p] = v end
    local tb = truth(fx.vals)
    local lb = {}
    for _, b in ipairs(layout.canvas.bands) do
      local r = ME.read_band(user, 0, b, layout.canvas.all_on)
      if r and r.on then lb[#lb + 1] = r end
    end
    for _, c in ipairs(ME.centres()) do
      local a, b = 0, 0
      for _, x in ipairs(tb) do a = a + ME.band_db(x, c) end
      for _, x in ipairs(lb) do b = b + ME.band_db(x, c) end
      w = math.max(w, math.abs(math.max(a, -30) - math.max(b, -30)))
    end
  end
  return w
end

-- ---------------------------------------------------------------------
-- an EQ73-style plugin
-- ---------------------------------------------------------------------
do
  local function stepped(name, list) return { name = name, list = list } end
  local function knob(name, lo, hi, unit) return { name = name, lo = lo, hi = hi, unit = unit } end
  P = {
    [0] = stepped("HPF Freq", { "Off", "50 Hz", "80 Hz", "160 Hz", "300 Hz" }),
    knob("Low Gain", -16, 16, "dB"),
    stepped("Low Freq", { "35 Hz", "60 Hz", "110 Hz", "220 Hz" }),
    knob("Mid Gain", -18, 18, "dB"),
    stepped("Mid Freq", { "360 Hz", "700 Hz", "1.6 kHz", "3.2 kHz", "4.8 kHz", "7.2 kHz" }),
    knob("High Gain", -16, 16, "dB"),
    knob("Input", -20, 20, "dB"),
    stepped("EQ In", { "Off", "On" }),
  }
  NP = 8
  truth = function(vals)
    local bands = {}
    local _, hi = fmt(0, vals[0])
    local hpf = ({ nil, 50, 80, 160, 300 })[hi]
    if hpf then bands[#bands + 1] = { type = "hp", order = 3, f = hpf, q = 1 } end
    local lg = -16 + 32 * vals[1]
    local _, li = fmt(2, vals[2])
    bands[#bands + 1] = { type = "ls", f = ({ 35, 60, 110, 220 })[li] * 1.1, g = lg, q = 0.6 + 0.02 * math.abs(lg) }
    local mg = -18 + 36 * vals[3]
    local _, mi = fmt(4, vals[4])
    -- narrower cutting than boosting, as some designs are
    bands[#bands + 1] = { type = "bell", f = ({ 360, 700, 1600, 3200, 4800, 7200 })[mi], g = mg,
                          q = (0.6 + 0.05 * math.abs(mg)) * (mg < 0 and 1.4 or 1) }
    bands[#bands + 1] = { type = "hs", f = 12000, g = -16 + 32 * vals[5], q = 0.7 }
    if vals[7] < 0.5 then bands = {} end
    return bands
  end
  tracks = {}
  local user = newtrack("Vox"); tracks[1] = user
  user.fx[1] = { kind = "eq", vals = {} }
  for p = 0, NP - 1 do user.fx[1].vals[p] = 0.5 end
  user.fx[1].vals[7] = 1
  local names = {}
  for p = 0, NP - 1 do names[p + 1] = P[p].name end
  local CS = { guess = nil }
  local bands = ME.guess(names)
  check("eq73: guessed bands", #bands, 4)
  check("eq73: guessed high shelf has no freq", bands[4] and bands[4].freq, nil)
  local layout = { controls = {}, aliases = {}, canvas = { kind = "eq", all_on = 7, bands = bands } }
  M.set("EQ73 :: EQ", layout)
  check("eq73: not ready before learning", M.canvas_todo(layout.canvas) ~= nil, true)
  local job = LN.start(user, 0, "EQ73 :: EQ", layout)
  run(job)
  check("eq73: learned", job.state, "done")
  check("eq73: temporary track removed", #tracks, 1)
  check("eq73: ready", M.canvas_todo(layout.canvas), nil)
  checkf("eq73: thorough (30+ measurements)", function() return #job.steps >= 30 end)
  local L = {}
  for k, b in ipairs(layout.canvas.bands) do L[k] = ME.decode(b.learn) end
  check("eq73: low cut type", L[1].shapes[1].type, "hp")
  check("eq73: low cut 18 dB/oct", L[1].shapes[1].order, 3)
  check("eq73: low cut knows Off", L[1].O and #L[1].O, 1)
  check("eq73: low shelf", L[2].shapes[1].type, "ls")
  check("eq73: mid bell", L[3].shapes[1].type, "bell")
  check("eq73: high shelf", L[4].shapes[1].type, "hs")
  checkf("eq73: low dial 10% off, learned", function()
    return math.abs(L[2].shapes[1].F[2][2] / 66 - 1) < 0.03 end)
  checkf("eq73: high shelf found near 12k", function()
    local f = L[4].shapes[1].F[1][2]; return f > 9000 and f < 14000 end)
  checkf("eq73: proportional Q seen", function()
    local Q = L[3].shapes[1].Q; return Q[#Q][2] > Q[3][2] + 0.2 end)
  check("eq73: four gains measured (boost and cut both ways)", #L[3].shapes[1].Q, 4)
  checkf("eq73: cut narrower than boost", function()
    local Q = L[3].shapes[1].Q; return Q[1][2] > Q[#Q][2] * 1.2 end)
  local w = worst(user, layout, {
    { [0] = 0.5, [1] = 0.8, [2] = 0.6, [3] = 0.2, [4] = 0.5, [5] = 0.7 },
    { [0] = 0.9, [1] = 0.3, [2] = 0.1, [3] = 0.9, [4] = 0.9, [5] = 0.2 },
    { [0] = 0.0, [1] = 0.55, [2] = 0.9, [3] = 0.4, [4] = 0.1, [5] = 0.5 } })
  checkf(("eq73: curve within 1 dB (%.2f)"):format(w), function() return w < 1 end)
  -- HPF off: the band is off
  user.fx[1].vals[0] = 0
  local r = ME.read_band(user, 0, layout.canvas.bands[1], 7)
  check("eq73: HPF Off reads off", r and r.on, false)
  -- EQ In off: every band off
  user.fx[1].vals[7] = 0
  r = ME.read_band(user, 0, layout.canvas.bands[2], 7)
  check("eq73: EQ In off", r and r.on, false)
  user.fx[1].vals[7] = 1
  -- writing: a node dragged to 1.6 kHz lands on the mid's 1.6k step
  ME.set_freq(user, 0, layout.canvas.bands[3], 1650)
  check("eq73: snaps to a step", (fmt(4, user.fx[1].vals[4])), "1.6 kHz")
  ME.set_gain(user, 0, layout.canvas.bands[3], -6)
  checkf("eq73: gain written", function() return math.abs((-18 + 36 * user.fx[1].vals[3]) + 6) < 0.3 end)
  ME.reset(user, 0, layout.canvas.bands[3])
  checkf("eq73: double-click flattens", function() return math.abs(-18 + 36 * user.fx[1].vals[3]) < 0.3 end)
  user.fx[1].vals[0] = 0.5
  ME.reset(user, 0, layout.canvas.bands[1])
  check("eq73: double-click turns the HPF off", (fmt(0, user.fx[1].vals[0])), "Off")
  -- a mapping change asks for learning again
  layout.canvas.bands[2].q = 6
  check("eq73: changed mapping not learned", M.band_learned(layout.canvas.bands[2]), false)
  layout.canvas.bands[2].q = nil
  check("eq73: back as it was", M.band_learned(layout.canvas.bands[2]), true)
  -- cancelled midway: track gone, nothing saved
  local saved = layout.canvas.bands[1].learn
  layout.canvas.bands[1].learn = nil
  local j2 = LN.start(user, 0, "EQ73 :: EQ", layout)
  for _ = 1, 4 do LN.step(j2) end
  LN.cancel(j2)
  check("eq73: cancel", j2.state, "cancelled")
  check("eq73: cancel removes the track", #tracks, 1)
  check("eq73: cancel learns nothing", layout.canvas.bands[1].learn, nil)
  -- no answer from the analyser (FX not running while stopped)
  answer = false
  local j3 = LN.start(user, 0, "EQ73 :: EQ", layout)
  run(j3)
  check("eq73: no answer is an error", j3.state, "error")
  checkf("eq73: says why", function() return j3.msg:find("Run FX when stopped", 1, true) ~= nil end)
  check("eq73: error removes the track", #tracks, 1)
  answer = true
  layout.canvas.bands[1].learn = saved
end

-- ---------------------------------------------------------------------
-- a parametric EQ that reports its values
-- ---------------------------------------------------------------------
do
  local function knob(name, lo, hi, unit) return { name = name, lo = lo, hi = hi, unit = unit } end
  local function hz(n) local f = 20 * 1000 ^ n
    return f >= 1000 and ("%.2f kHz"):format(f / 1000) or ("%.1f Hz"):format(f) end
  P = {
    [0] = { name = "Band 1 Frequency", fn = hz },
    knob("Band 1 Gain", -24, 24, "dB"),
    { name = "Band 1 Q", fn = function(n) return ("%.2f"):format(0.1 * 100 ^ n) end },
    { name = "Band 2 Frequency", fn = hz },
    knob("Band 2 Gain", -24, 24, "dB"),
    knob("Output", -24, 24, "dB"),
    { name = "Bypass", list = { "Off", "On" } },
  }
  NP = 7
  truth = function(vals)
    local g1 = -24 + 48 * vals[1]
    local b = { { type = "bell", f = 20 * 1000 ^ vals[0], g = g1, q = 0.1 * 100 ^ vals[2] * 0.5 * (g1 < 0 and 1.6 or 1) },
                { type = "hs", f = 20 * 1000 ^ vals[3], g = -24 + 48 * vals[4], q = 0.7 } }
    if vals[6] >= 0.5 then b = {} end
    return b
  end
  tracks = {}
  local user = newtrack("Gtr"); tracks[1] = user
  user.fx[1] = { kind = "eq", vals = {} }
  for p = 0, NP - 1 do user.fx[1].vals[p] = 0.5 end
  user.fx[1].vals[6] = 0
  local names = {}
  for p = 0, NP - 1 do names[p + 1] = P[p].name end
  local bands = ME.guess(names)
  check("para: numbered bands guessed", #bands, 2)
  check("para: band 1 Q", bands[1] and bands[1].q, 2)
  local layout = { controls = {}, aliases = {}, canvas = { kind = "eq", all_on = 6, bands = bands } }
  M.set("Para :: EQ", layout)
  local job = LN.start(user, 0, "Para :: EQ", layout)
  run(job)
  check("para: learned", job.state, "done")
  local L1 = ME.decode(layout.canvas.bands[1].learn)
  check("para: band 1 is quick (its own values)", L1.D, true)
  checkf("para: its Q means half ours", function() return math.abs(L1.shapes[1].K[2] - 0.5) < 0.02 end)
  checkf("para: cuts narrower, learned apart", function() return math.abs(L1.shapes[1].K[3] - 0.8) < 0.03 end)
  local L2 = ME.decode(layout.canvas.bands[2].learn)
  check("para: band 2 has no Q control: thorough", L2.D, nil)
  check("para: band 2 shelf", L2.shapes[1].type, "hs")
  local w = worst(user, layout, {
    { [0] = 0.3, [1] = 0.8, [2] = 0.6, [3] = 0.9, [4] = 0.2 },
    { [0] = 0.7, [1] = 0.1, [2] = 0.2, [3] = 0.7, [4] = 0.7 } })
  checkf(("para: curve within 1 dB (%.2f)"):format(w), function() return w < 1 end)
  ME.set_freq(user, 0, layout.canvas.bands[1], 1000)
  checkf("para: frequency written", function() return math.abs(20 * 1000 ^ user.fx[1].vals[0] - 1000) < 15 end)
  check("para: bypass reads off", ME.read_band(user, 0, layout.canvas.bands[1], 6).on, true)
  user.fx[1].vals[6] = 1
  check("para: bypassed is off", ME.read_band(user, 0, layout.canvas.bands[1], 6).on, false)
end

-- ---------------------------------------------------------------------
-- a dynamic EQ: its dynamics held off while its shape is learned
-- ---------------------------------------------------------------------
for _, variant in ipairs({ "switch", "range", "threshold" }) do
  local function knob(name, lo, hi, unit) return { name = name, lo = lo, hi = hi, unit = unit } end
  local function hz(n) local f = 20 * 1000 ^ n
    return f >= 1000 and ("%.2f kHz"):format(f / 1000) or ("%.1f Hz"):format(f) end
  P = {
    [0] = { name = "Band 1 Frequency", fn = hz },
    knob("Band 1 Gain", -24, 24, "dB"),
    { name = "Band 1 Q", fn = function(n) return ("%.2f"):format(0.1 * 100 ^ n) end },
    knob("Band 1 Threshold", -60, 0, "dB"),
    knob("Band 1 Dynamic Range", -24, 24, "dB"),
    { name = "Band 1 Dynamics Enabled", list = { "Off", "On" } },
  }
  NP = 6
  -- the learning noise sits at -20 dBFS: a threshold under it pulls the
  -- band by half its range (unless the dynamics are off)
  truth = function(vals)
    local g = -24 + 48 * vals[1]
    local thr, rng = -60 + 60 * vals[3], -24 + 48 * vals[4]
    local on = vals[5] >= 0.5 or variant ~= "switch"
    if on and thr < -20 then g = g + rng * 0.5 end
    return { { type = "bell", f = 20 * 1000 ^ vals[0], g = g, q = 0.1 * 100 ^ vals[2] } }
  end
  tracks = {}
  local user = newtrack("Dyn"); tracks[1] = user
  user.fx[1] = { kind = "eq", vals = { [0] = 0.5, 0.7, 0.5, 0.2, 0.25, 1 } }
  local names = {}
  for p = 0, NP - 1 do names[p + 1] = P[p].name end
  local bands = ME.guess(names)
  check(variant .. ": guessed its dynamics", bands[1] and bands[1].dyn and
    ("%s %s %s"):format(bands[1].dyn.thr, bands[1].dyn.range, bands[1].dyn.on), "3 4 5")
  if variant ~= "switch" then bands[1].dyn.on = nil end
  if variant == "threshold" then bands[1].dyn.range = nil end
  local layout = { controls = {}, aliases = {}, canvas = { kind = "eq", bands = bands } }
  M.set("Dyn :: EQ", layout)
  local job = LN.start(user, 0, "Dyn :: EQ", layout)
  run(job)
  check(variant .. ": learned", job.state, "done")
  -- the curve learned is the static one: compare with the dynamics off
  local w = 0
  for _, set in ipairs({ { [1] = 0.8, [0] = 0.4 }, { [1] = 0.2, [0] = 0.6 } }) do
    for p, v in pairs(set) do user.fx[1].vals[p] = v end
    local keep = { user.fx[1].vals[3], user.fx[1].vals[5] }
    user.fx[1].vals[3], user.fx[1].vals[5] = 1, 0
    local tb = truth(user.fx[1].vals)
    user.fx[1].vals[3], user.fx[1].vals[5] = keep[1], keep[2]
    local r = ME.read_band(user, 0, layout.canvas.bands[1])
    for _, c in ipairs(ME.centres()) do
      w = math.max(w, math.abs(ME.band_db(tb[1], c) - ME.band_db(r, c)))
    end
  end
  checkf(("%s: the static shape, within 1 dB (%.2f)"):format(variant, w), function() return w < 1 end)
  check(variant .. ": the user's dynamics untouched", ("%.2f %.2f %.0f"):format(user.fx[1].vals[3], user.fx[1].vals[4],
    user.fx[1].vals[5]), "0.20 0.25 1")
  local dy = ME.read_dyn(user, 0, layout.canvas.bands[1])
  check(variant .. ": range read signed", dy and dy.range, variant ~= "threshold" and -12 or nil)
  M.remove("Dyn :: EQ")
end

-- ---------------------------------------------------------------------
-- a compressor whose threshold reads in a dB of its own
-- ---------------------------------------------------------------------
for _, variant in ipairs({ "own dB", "along" }) do
  local function knob(name, lo, hi, unit) return { name = name, lo = lo, hi = hi, unit = unit } end
  P = {
    [0] = variant == "own dB" and knob("Threshold", -15, 15, "dB")
          or { name = "Threshold", fn = function(n) return ("%.0f"):format(n * 10) end },
    { name = "Ratio", list = { "2:1", "4:1", "10:1" } },
    knob("Make-Up", 0, 15, "dB"),
    knob("Mix", 0, 100, "%"),
  }
  NP = 4
  -- its 0 dB is -18 dBFS (sine peak); "along": -40 at the bottom, -10 at the top
  local function true_thr(vals)
    if variant == "own dB" then return -15 + 30 * vals[0] - 18 end
    return -40 + 30 * vals[0]
  end
  truth_gain = function(vals, level)
    local T = true_thr(vals)
    local r = ({ 2, 4, 10 })[math.min(3, math.floor(vals[1] * 3) + 1)]
    local gr = level > T and (level - T) * (1 - 1 / r) or 0
    local mk = 15 * vals[2]
    return mk - gr * vals[3]      -- a dry share dilutes it (the measuring sets it wet)
  end
  tracks = {}
  local user = newtrack("Bus"); tracks[1] = user
  user.fx[1] = { kind = "eq", vals = { [0] = 0.6, 0.5, 0.2, 0.4 } }
  local layout = { controls = {}, aliases = {}, canvas = { kind = "comp", roles = { Threshold = 0, Ratio = 1, Makeup = 2, Mix = 3 }, rev = {} } }
  M.set("Bus :: Comp", layout)
  local job = LN.start_thr(user, 0, "Bus :: Comp", layout)
  run(job)
  check(variant .. ": threshold measured", job.state, "done")
  local cv = layout.canvas
  local tc = M.thr_cal(cv)
  check(variant .. ": by its reading or its position", tc and tc.n, variant ~= "own dB")
  if variant == "own dB" then
    checkf(("own dB: its 0 dB is -18 dBFS (%.2f)"):format(M.thr_dbfs(cv, 0) or 0), function() return math.abs(M.thr_dbfs(cv, 0) + 18) < 0.3 end)
    checkf("own dB: back again", function() return math.abs(M.thr_from_dbfs(cv, -20) - (-2)) < 0.3 end)
  else
    checkf(("along: halfway is -25 dBFS (%.2f)"):format(M.thr_dbfs(cv, 0.5) or 0), function() return math.abs(M.thr_dbfs(cv, 0.5) + 25) < 0.5 end)
  end
  check(variant .. ": the user's plugin untouched", ("%.1f %.1f"):format(user.fx[1].vals[0], user.fx[1].vals[3]), "0.6 0.4")
  check(variant .. ": the user's pins untouched", user.fx[1].pins, nil)
  check(variant .. ": stopped early once deep in", #job.steps > 0 and job.i - 1 <= #job.steps, true)
  M.remove("Bus :: Comp")
end
-- a compressor with no threshold, only an input (1176-style): the input
-- drives a fixed threshold, -24 dBFS at the input's 0 dB
for _, variant in ipairs({ "input dB", "input along" }) do
  local function knob(name, lo, hi, unit) return { name = name, lo = lo, hi = hi, unit = unit } end
  P = {
    [0] = variant == "input dB" and knob("Input", -10, 50, "dB")
          or { name = "Input", fn = function(n) return ("%.0f"):format(n * 10) end },
    { name = "Ratio", list = { "4:1", "8:1", "20:1" } },
    knob("Output", -20, 20, "dB"),
  }
  NP = 3
  local function in_gain(vals) return -10 + 60 * vals[0] end
  truth_gain = function(vals, level)
    local x = level + in_gain(vals)
    local r = ({ 4, 8, 20 })[math.min(3, math.floor(vals[1] * 3) + 1)]
    local gr = x > -24 and (x + 24) * (1 - 1 / r) or 0
    return in_gain(vals) - gr + (-20 + 40 * vals[2])
  end
  tracks = {}
  local user = newtrack("Vox"); tracks[1] = user
  user.fx[1] = { kind = "eq", vals = { [0] = 0.5, 0.5, 0.5 } }
  local layout = { controls = {}, aliases = {}, canvas = { kind = "comp", roles = { Input = 0, Ratio = 1, Makeup = 2 }, rev = {} } }
  M.set("Vox :: 1176", layout)
  local job = LN.start_thr(user, 0, "Vox :: 1176", layout)
  run(job)
  check(variant .. ": measured", job.state, "done")
  local cv = layout.canvas
  local tc = M.thr_cal(cv)
  check(variant .. ": stored for the input", tc and tc.p, 0)
  check(variant .. ": by its reading or its position", tc and tc.n, variant ~= "input dB")
  local x30 = variant == "input dB" and 30 or (40 / 60)    -- input at +30 dB: threshold -54 dBFS
  checkf(("%s: +30 dB of input puts it at -54 dBFS (%.2f)"):format(variant, M.thr_dbfs(cv, x30) or 0),
    function() return math.abs(M.thr_dbfs(cv, x30) + 54) < 0.6 end)
  checkf(variant .. ": back again", function() return math.abs(M.thr_from_dbfs(cv, -54) - x30) < (variant == "input dB" and 0.6 or 0.01) end)
  check(variant .. ": says where it fell", job.msg:find("with the input at", 1, true) ~= nil, true)
  check(variant .. ": a Threshold mapped later sets it aside", (function()
    cv.roles.Threshold = 2; local r = M.thr_cal(cv); cv.roles.Threshold = nil; return r end)(), nil)
  M.remove("Vox :: 1176")
end
do
  -- REAPER still running the older measuring plugin: said so, and nothing stored
  old_jsfx = true
  local user = tracks[1]
  local layout = { controls = {}, aliases = {}, canvas = { kind = "comp", roles = { Threshold = 0 }, rev = {} } }
  M.set("Old :: Comp", layout)
  local job = LN.start_thr(user, 0, "Old :: Comp", layout)
  run(job)
  check("older jsfx: says so", job.state == "error" and job.msg:find("older measuring plugin", 1, true) ~= nil, true)
  check("older jsfx: the track removed", #tracks, 1)
  M.remove("Old :: Comp")
  old_jsfx = false
  -- a compressor that never reduces: says what it measured
  truth_gain = function() return 0 end
  M.set("Flat :: Comp", layout)
  local j2 = LN.start_thr(user, 0, "Flat :: Comp", layout)
  run(j2)
  check("no reduction: says what it measured", j2.state == "error" and j2.msg:find("10%: 0.0 dB", 1, true) ~= nil, true)
  M.remove("Flat :: Comp")
  -- a copy that passes no sound: waited for, then said so, nothing kept
  truth_gain = function(vals, level) return -120 - level end
  M.set("Dead :: Comp", layout)
  local j3 = LN.start_thr(user, 0, "Dead :: Comp", layout)
  run(j3)
  check("silent copy: says it passed nothing", j3.state == "error" and j3.msg:find("passed almost nothing", 1, true) ~= nil, true)
  check("silent copy: waited for it first", (j3.wake or 0) > LN.THR_WAKE, true)
  check("silent copy: nothing kept", layout.canvas.thr_cal, nil)
  M.remove("Dead :: Comp")
  -- a copy whose output never moves (a constant level, whatever goes in):
  -- every threshold at the bottom of the sweep, so none
  truth_gain = function(vals, level) return -50 - level end
  M.set("Stuck :: Comp", layout)
  local j4 = LN.start_thr(user, 0, "Stuck :: Comp", layout)
  run(j4)
  check("constant output: no threshold kept", j4.state == "error" and layout.canvas.thr_cal == nil, true)
  M.remove("Stuck :: Comp")
  -- a stored measurement that never moved (an older bad one): set aside
  check("flat stored measurement: set aside", M.thr_cal({ roles = { Threshold = 20 },
    thr_cal = { p = 20, n = false, pts = { { -54, -60 }, { -39, -60 }, { -24, -60 }, { -9, -60 } } } }), nil)
end

-- ---------------------------------------------------------------------
-- a reverb whose decay reads 0..100
-- ---------------------------------------------------------------------
for _, with_size in ipairs({ false, true }) do
  local name = with_size and "with size" or "decay only"
  P = {
    [0] = { name = "Rvb Time", fn = function(n) return ("%.0f"):format(n * 100) end },
    { name = "Size", fn = function(n) return ("%.0f"):format(n * 100) end },
    { name = "Mix", fn = function(n) return ("%.0f %%"):format(n * 100) end },
  }
  NP = 3
  -- 0.3 s to 12 s along the knob, longer the bigger the room
  truth_rt = function(vals) return 300 * 40 ^ vals[0] * (with_size and (0.6 + 0.8 * vals[1]) or 1) end
  tracks = {}
  local user = newtrack("Verb"); tracks[1] = user
  user.fx[1] = { kind = "eq", vals = { [0] = 0.64, 0.5, 0.2 } }
  local roles = { Decay = 0, Mix = 2 }
  if with_size then roles.Size = 1 end
  local layout = { controls = {}, aliases = {}, canvas = { kind = "reverb", roles = roles, rev = {} } }
  M.set("Verb :: Reverb", layout)
  local job = LN.start_decay(user, 0, "Verb :: Reverb", layout)
  run(job)
  check(name .. ": decay measured", job.state, "done")
  local cv = layout.canvas
  check(name .. ": points", M.dec_cal(cv) and #M.dec_cal(cv).pts, with_size and 15 or 5)
  local want = truth_rt({ [0] = 0.64, 0.3 })
  local got = M.decay_ms(cv, 0.64, with_size and 0.3 or nil)
  checkf(("%s: between the points (%.0f ms, truly %.0f)"):format(name, got or 0, want), function() return got and math.abs(got / want - 1) < 0.04 end)
  local pos = M.decay_pos(cv, 2000, with_size and 0.3 or nil)
  checkf(("%s: back to a position for 2 s (%.3f)"):format(name, pos or -1), function()
    return pos and math.abs(truth_rt({ [0] = pos, 0.3 }) / 2000 - 1) < 0.04 end)
  check(name .. ": the user's plugin untouched", ("%.2f %.2f"):format(user.fx[1].vals[0], user.fx[1].vals[2]), "0.64 0.20")
  M.remove("Verb :: Reverb")
end

-- a reverb whose Mix runs the other way (its 100 is all dry): found by
-- trying it the other way round; one with no wet at all says so
do
  P = {
    [0] = { name = "Rvb Time", fn = function(n) return ("%.0f"):format(n * 100) end },
    { name = "Size", fn = function(n) return ("%.0f"):format(n * 100) end },
    { name = "Dry", fn = function(n) return ("%.0f %%"):format(n * 100) end },
  }
  NP = 3
  truth_rt = function(vals) if vals[2] >= 0.5 then return nil end return 300 * 40 ^ vals[0] end
  tracks = {}
  local user = newtrack("Verb"); tracks[1] = user
  user.fx[1] = { kind = "eq", vals = { [0] = 0.5, 0.5, 0.2 } }
  local layout = { controls = {}, aliases = {}, canvas = { kind = "reverb", roles = { Decay = 0, Mix = 2 }, rev = {} } }
  M.set("Rev :: Reverb", layout)
  local job = LN.start_decay(user, 0, "Rev :: Reverb", layout)
  run(job)
  check("mix the other way: measured", job.state, "done")
  checkf("mix the other way: the right times", function() return math.abs(M.decay_ms(layout.canvas, 0.5) / (300 * 40 ^ 0.5) - 1) < 0.04 end)
  -- its shortest setting rings for only 15 ms: kept, and Mix not flipped
  truth_rt = function(vals) if vals[2] >= 0.5 then return nil end return 15 * 2000 ^ vals[0] end
  P[2] = { name = "Mix", fn = function(n) return ("%.0f %%"):format(n * 100) end }
  truth_rt = function(vals) if vals[2] < 0.5 then return nil end return 15 * 2000 ^ vals[0] end
  layout.canvas.dec_cal = nil
  local j3 = LN.start_decay(user, 0, "Rev :: Reverb", layout)
  run(j3)
  check("a very short setting: measured", j3.state, "done")
  check("a very short setting: Mix left as it was", j3.flipped, nil)
  checkf(("a very short setting: kept (%.0f ms)"):format(M.decay_ms(layout.canvas, 0) or 0), function()
    return math.abs(M.decay_ms(layout.canvas, 0) - 15) < 3 end)
  truth_rt = function() return nil end
  layout.canvas.dec_cal = nil
  local j2 = LN.start_decay(user, 0, "Rev :: Reverb", layout)
  run(j2)
  check("no wet at all: says the burst came through dry", j2.state == "error" and j2.msg:find("straight through", 1, true) ~= nil, true)
  check("no wet at all: nothing stored", layout.canvas.dec_cal, nil)
  M.remove("Rev :: Reverb")
end

-- a saturator: its curve and harmonics learned at each Drive and Style;
-- what the canvas would draw, against the fake's own
do
  P = {
    [0] = { name = "Drive", fn = function(n) return ("%.1f"):format(n * 10) end },
    { name = "Style", list = { "Tape", "Tube" } },
    { name = "Mix", fn = function(n) return ("%.0f %%"):format(n * 100) end },
  }
  NP = 3
  truth_sat = function(vals)
    local k = 1 + 6 * (vals[0] or 0)
    local bias = (vals[1] or 0) >= 0.5 and 0.3 or 0
    local nrm = math.tanh(k * (1 + bias)) - math.tanh(k * bias)
    return function(x) return (math.tanh(k * (x + bias)) - math.tanh(k * bias)) / nrm end
  end
  tracks = {}
  local user = newtrack("Sat"); tracks[1] = user
  user.fx[1] = { kind = "eq", vals = { [0] = 0.4, 0, 1 } }
  local layout = { controls = {}, aliases = {}, canvas = { kind = "sat", roles = { Drive = 0, Style = 1, Mix = 2 }, rev = {} } }
  M.set("Sat :: Sat", layout)
  local job = LN.start_sat(user, 0, "Sat :: Sat", layout)
  run(job)
  check("saturator: learned", job.state, "done")
  local c = layout.canvas.sat_cal
  check("saturator: drive points, styles, tones", c and ("%d %d %s"):format(#c.dn, #c.sn, tostring(c.tn[1])), "5 2 false")
  -- between the learned drives: the curve near the fake's own
  local at = M.sat_at(c, 0.4, 0, 0)
  local y = truth_sat({ [0] = 0.4, 0 })
  local worst = 0
  for _, x in ipairs({ -0.9, -0.5, -0.2, 0.1, 0.3, 0.7, 0.95 }) do worst = math.max(worst, math.abs(M.sat_curve(at, x) - y(x))) end
  checkf(("saturator: the curve between learned drives (off by %.3f)"):format(worst), function() return worst < 0.06 end)
  -- odd harmonics only without a bias; the even ones lead with it
  local h0 = M.sat_harm(c, at, -6)
  local h1 = M.sat_harm(c, M.sat_at(c, 0.4, 1, 0), -6)
  checkf(("saturator: symmetric, odd-heavy (h2 %.0f, h3 %.0f dB)"):format(h0[2] or 0, h0[3] or 0), function() return h0[3] > h0[2] + 20 end)
  checkf(("saturator: biased, even harmonics come up (h2 %.0f dB)"):format(h1[2] or -999), function() return h1[2] > -40 end)
  -- quieter, cleaner
  local _, thd_q = M.sat_harm(c, at, -18)
  local _, thd_l = M.sat_harm(c, at, 0)
  checkf(("saturator: quieter is cleaner (%.1f%% at -18, %.1f%% at 0)"):format(thd_q, thd_l), function() return thd_q < thd_l end)
  local b = M.sat_bite(at)
  checkf(("saturator: bites from %.1f dBFS"):format(b or 99), function() return b and b < -6 and b > -30 end)
  check("saturator: no bite in a clean one", M.sat_bite({ up = (function() local t = {} for i = 1, 24 do t[i] = -1 + (i - 0.5) / 12 end return t end)(), dn = {}, h = {} }), nil)
  -- kept through a save
  M.save(); M.reload()
  local c2 = M.get("Sat :: Sat").canvas.sat_cal
  check("saturator: kept", c2 and #c2.dn, 5)
  checkf("saturator: the same curve back", function() return math.abs(M.sat_curve(M.sat_at(c2, 0.4, 0, 0), 0.3) - M.sat_curve(at, 0.3)) < 0.002 end)
  check("saturator: the user's plugin untouched", ("%.2f %.2f"):format(user.fx[1].vals[0], user.fx[1].vals[1]), "0.40 0.00")
  M.remove("Sat :: Sat")
end

os.remove(tmpdir .. "TS_ChannelView_Mappings.ini")
os.remove(tmpdir .. "TS_ChannelView_Mappings.bak.ini")
print(fails == 0 and ("\nALL PASS") or ("\n" .. fails .. " FAILURES"))
os.exit(fails == 0 and 0 or 1)
