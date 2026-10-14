-- @noindex
-- Not a package of its own: installed by TS_ChannelView.lua's @provides.
--[[
  TS_CV_Learn.lua -- learning an EQ layout's bands from the plugin itself.

  The plugin is COPIED onto a temporary track that nothing can hear
  (hidden, no master send, its output silenced), between two instances of
  TS_CV_Learn.jsfx: a source playing quiet noise into it and an analyser
  comparing what comes out with what went in, band by band. Then each of
  the layout's bands is moved through its controls -- every frequency
  step (or five points along a knob), three gains, each position of a
  shape switch, a sweep of its Q control -- with the others held flat,
  and each measurement is fitted to a model (TS_CV_MapEQ ME.fit). The
  fits are summarised into the band's Learn<k> line, and the track is
  removed. The user's own track, its plugins and its probes are never
  touched.

  A band that reports its values in real units -- frequency in Hz, gain in
  dB, and a Q control -- is learned QUICKLY: one measurement per shape,
  for its type and a check of what it means by Q. The canvas then uses
  its own readings (TS_CV_MapEQ, "D").

  Runs a step per frame (LN.step) so ChannelView keeps drawing: a
  measurement takes about a second (the noise has to settle through the
  plugin, then a few FFT frames are averaged). It needs REAPER to run FX
  while stopped (Preferences > Audio > Playback), which it does by default.
--]]

local UN = require("TS_CV_Units")
local ME = require("TS_CV_MapEQ")
local M  = require("TS_CV_Mappings")

local LN = {}

LN.NS   = "TS_TA_Mem"
LN.BASE = 1048576
LN.DESC = "ChannelView Learn (temporary)"
LN.PATHS = {
  "TS-ReaScripts/TS_ChannelView/TS_CV_Learn.jsfx",
  "TS_ChannelView/TS_CV_Learn.jsfx",
  "TS_CV_Learn.jsfx",
  "JS: " .. LN.DESC,
}
LN.TIMEOUT = 8          -- seconds a measurement may take before giving up
LN.TRACK_NAME = "ChannelView learning (temporary)"

local GAIN_PTS = 3
local plan_thr, begin_thr, step_thr   -- a compressor's threshold, below
local plan_dec, begin_dec, step_dec   -- a reverb's decay, below
local plan_sat, begin_sat, step_sat   -- a saturator's curve, below
local KNOB_PTS = { 0, 0.25, 0.5, 0.75, 1 }

-- ---------------------------------------------------------------------
-- the temporary track
-- ---------------------------------------------------------------------

local function add_jsfx(tr, at)
  for _, p in ipairs(LN.PATHS) do
    local idx = reaper.TrackFX_AddByName(tr, p, false, -1000 - at)
    if idx and idx >= 0 then
      reaper.TrackFX_Show(tr, idx, 2)
      return idx
    end
  end
  return nil
end

local function remove_track(job)
  if job.tmp and reaper.ValidatePtr2(0, job.tmp, "MediaTrack*") then
    reaper.PreventUIRefresh(1)
    reaper.DeleteTrack(job.tmp)
    reaper.PreventUIRefresh(-1)
    reaper.TrackList_AdjustWindows(false)
  end
  job.tmp = nil
end

local function make_track(job)
  local n = reaper.CountTracks(0)
  reaper.PreventUIRefresh(1)
  reaper.InsertTrackAtIndex(n, false)
  local tr = reaper.GetTrack(0, n)
  job.tmp = tr
  reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", LN.TRACK_NAME, true)
  reaper.SetMediaTrackInfo_Value(tr, "B_SHOWINTCP", 0)
  reaper.SetMediaTrackInfo_Value(tr, "B_SHOWINMIXER", 0)
  reaper.SetMediaTrackInfo_Value(tr, "B_MAINSEND", 0)
  reaper.SetMediaTrackInfo_Value(tr, "I_NCHAN", 8)
  reaper.TrackFX_CopyToTrack(job.track, job.addr, tr, 0, false)
  local ok = reaper.TrackFX_GetCount(tr) == 1
  local src = ok and add_jsfx(tr, 0)
  local ana = src and add_jsfx(tr, 2)
  reaper.PreventUIRefresh(-1)
  reaper.TrackList_AdjustWindows(false)
  if not ok then return nil, "couldn't copy the plugin" end
  if not (src and ana) then return nil, "TS_CV_Learn.jsfx wasn't found (reinstall ChannelView)" end
  job.p = 1                       -- the copy sits between them
  job.ana = 2
  -- the copy's pins as plain stereo: the original's may be rewired (a
  -- tap's extra outputs, a parallel path, its sidechain on other channels),
  -- and then the copy would read or write channels the measuring doesn't.
  -- In: pin k from channel k (L, R, then a sidechain on 3/4, 5/6); out: L, R.
  if reaper.TrackFX_GetIOSize and reaper.TrackFX_SetPinMappings then
    local _, ni, no = reaper.TrackFX_GetIOSize(tr, job.p)
    job.io = { ni, no }
    for pin = 0, math.max(0, ni or 0) - 1 do
      reaper.TrackFX_SetPinMappings(tr, job.p, 0, pin, pin < 6 and (1 << pin) or 0, 0)
    end
    for pin = 0, math.max(0, no or 0) - 1 do
      reaper.TrackFX_SetPinMappings(tr, job.p, 1, pin, pin < 2 and (1 << pin) or 0, 0)
    end
  end
  reaper.TrackFX_Show(tr, job.p, 2)
  reaper.TrackFX_SetEnabled(tr, job.p, true)
  if reaper.TrackFX_SetOffline then reaper.TrackFX_SetOffline(tr, job.p, false) end
  reaper.TrackFX_SetParam(tr, 0, 0, 0)          -- source
  reaper.TrackFX_SetParam(tr, ana, 0, 1)        -- analyser
  local _, pdc = reaper.TrackFX_GetNamedConfigParm(tr, job.p, "pdc")
  reaper.TrackFX_SetParam(tr, ana, 2, tonumber(pdc) or 0)
  -- the copy must answer only to what we write: no links from the
  -- original track's macros or modulators (on the hidden track they'd
  -- point at the measuring plugins, or at nothing), no LFOs, no lanes
  -- holding a parameter where it is -- on every parameter, not just the
  -- mapped ones: an In Level pinned at the bottom silences a reverb
  local EN = require("TS_CV_Envelopes")
  local np = reaper.TrackFX_GetNumParams and reaper.TrackFX_GetNumParams(tr, job.p) or 0
  local all = {}
  for p in pairs(job.params) do all[p] = true end
  for p = 0, math.min(np, 4096) - 1 do all[p] = true end
  for p in pairs(all) do
    for _, k in ipairs({ "mod.active", "plink.active", "lfo.active", "acs.active" }) do
      reaper.TrackFX_SetNamedConfigParm(tr, job.p, ("param.%d.%s"):format(p, k), "0")
    end
    local env = reaper.GetFXEnvelope(tr, job.p, p, false)
    if env then EN.remove(tr, env) end
  end
  return true
end

-- The copy, in a few words, for a measurement that came back wrong: did it
-- load, is it on, its pins, its latency, its parameters against the
-- original's.
local function copy_health_(job)
  local tr, p = job.tmp, job.p
  if not (tr and p) then return "" end
  local t = {}
  local _, nm = reaper.TrackFX_GetFXName(tr, p, "")
  t[#t + 1] = "copy: " .. (nm or "?")
  if reaper.TrackFX_GetOffline and reaper.TrackFX_GetOffline(tr, p) then t[#t + 1] = "OFFLINE" end
  if reaper.TrackFX_GetEnabled and not reaper.TrackFX_GetEnabled(tr, p) then t[#t + 1] = "BYPASSED" end
  local np = reaper.TrackFX_GetNumParams and reaper.TrackFX_GetNumParams(tr, p) or nil
  local no = reaper.TrackFX_GetNumParams and reaper.TrackFX_GetNumParams(job.track, job.addr) or nil
  if np then t[#t + 1] = ("params %d (yours %d)"):format(np, no or -1) end
  if job.io then t[#t + 1] = ("pins in %s out %s"):format(tostring(job.io[1]), tostring(job.io[2])) end
  if reaper.TrackFX_GetPinMappings then
    local m = {}
    for _, q in ipairs({ { 0, 0 }, { 0, 1 }, { 1, 0 }, { 1, 1 } }) do
      local lo = reaper.TrackFX_GetPinMappings(tr, p, q[1], q[2])
      m[#m + 1] = ("%s%d=%s"):format(q[1] == 0 and "in" or "out", q[2] + 1, tostring(lo))
    end
    t[#t + 1] = table.concat(m, " ")
  end
  local _, pdc = reaper.TrackFX_GetNamedConfigParm(tr, p, "pdc")
  t[#t + 1] = "latency " .. tostring(pdc)
  return " [" .. table.concat(t, ", ") .. "]"
end
-- (never let saying what went wrong go wrong)
local function copy_health(job)
  local ok, h = pcall(copy_health_, job)
  return ok and h or ""
end

-- ---------------------------------------------------------------------
-- planning
-- ---------------------------------------------------------------------

local function fmt_of(job, p) return UN.formatter(job.tmp, job.p, p) end

-- The control's positions when it's a switch, else nil (cached).
local function positions(job, p)
  if job.pos_cache[p] == nil then
    job.pos_cache[p] = UN.positions(fmt_of(job, p), 200, 24) or false
  end
  return job.pos_cache[p] or nil
end

local function unit_at(job, p, n)
  local _, u = UN.at(fmt_of(job, p), n or 0.5)
  return u
end

-- Where a gain control is flat, and its far ends: flat, top, bottom.
local function gain_points(job, p)
  local fmt = fmt_of(job, p)
  local v0, v1 = UN.at(fmt, 0), UN.at(fmt, 1)
  local flat = 0.5
  if v0 and v1 then
    local lo = math.min(v0, v1)
    if lo >= 0 then flat = (v0 <= v1) and 0 or 1
    else flat = UN.find_norm(fmt, 0) or 0.5 end
  end
  local top = (v0 and v1 and v0 > v1) and 0 or 1
  local bot = 1 - top
  local pts = { top }
  if math.abs(bot - flat) > 0.1 then
    -- boosts and cuts both ways: many EQs are narrower one way than the other
    pts[#pts + 1] = flat + (top - flat) * 0.5
    pts[#pts + 1] = flat + (bot - flat) * 0.5
    pts[#pts + 1] = bot
  else
    pts[#pts + 1] = flat + (top - flat) * (2 / 3)
    pts[#pts + 1] = flat + (top - flat) * (1 / 3)
  end
  -- a switched gain: the nearest positions
  local sw = positions(job, p)
  if sw then
    local function snap(v)
      local best, bd = v, math.huge
      for _, r in ipairs(sw) do local d = math.abs(r.norm - v); if d < bd then best, bd = r.norm, d end end
      return best
    end
    flat = snap(flat)
    for i, v in ipairs(pts) do pts[i] = snap(v) end
  end
  return flat, pts
end

-- The "on" end of a switch: whichever of 1 / 0 reads on.
local function on_value(job, p)
  reaper.TrackFX_SetParamNormalized(job.tmp, job.p, p, 1)
  if ME.switch_on(job.tmp, job.p, p) then return 1 end
  return 0
end

local function is_off_text(t)
  t = (t or ""):lower()
  return t:match("off") or t:match("^%s*out") or t:match("bypass") or not t:match("%d")
end

-- A dynamic EQ band's dynamics, held off on the copy so its shape is
-- measured still: its dynamics switch off; else its range at 0 dB; else
-- its threshold at the top (and its ratio 1:1). Into `flat`.
local function hold_dynamics(job, d, flat)
  local function ends(p)
    local fmt = fmt_of(job, p)
    return fmt, UN.at(fmt, 0), UN.at(fmt, 1)
  end
  if d.on then flat[d.on] = 1 - on_value(job, d.on) return end
  if d.range then
    local fmt, v0, v1 = ends(d.range)
    local n = UN.find_norm(fmt, 0)
    if not n then
      if v0 and v1 then n = (math.abs(v0) <= math.abs(v1)) and 0 or 1
      else n = (d.rev and d.rev.range) and 1 or 0 end
    end
    flat[d.range] = n
    return
  end
  if d.thr then
    local _, v0, v1 = ends(d.thr)
    if v0 and v1 then flat[d.thr] = (v1 >= v0) and 1 or 0
    else flat[d.thr] = (d.rev and d.rev.thr) and 0 or 1 end
  end
  if d.ratio then
    local fmt, v0, v1 = ends(d.ratio)
    flat[d.ratio] = UN.find_norm(fmt, 1) or ((v0 and v1 and v1 < v0) and 1 or 0)
  end
end

local function plan(job)
  local steps, flat = {}, {}
  local cv = job.layout.canvas
  if cv.all_on then flat[cv.all_on] = on_value(job, cv.all_on) end
  for _, b in ipairs(cv.bands or {}) do
    if b.dyn then hold_dynamics(job, b.dyn, flat) end
  end
  job.meta = {}
  for _, k in ipairs(job.which) do
    local b = cv.bands[k]
    local meta = { k = k, kind = b.gain and "gain" or "cut" }
    job.meta[k] = meta
    if b.on then flat[b.on] = on_value(job, b.on) end
    if b.gain then
      meta.flat, meta.gpts = gain_points(job, b.gain)
      flat[b.gain] = meta.flat
    end
    if b.freq then
      local sw = positions(job, b.freq)
      if sw then
        meta.S, meta.fpts = {}, {}
        for _, r in ipairs(sw) do
          meta.S[#meta.S + 1] = r.norm
          if is_off_text(r.text) then
            meta.off = meta.off or r.norm
            meta.O = meta.O or {}
            meta.O[#meta.O + 1] = r.norm
          else meta.fpts[#meta.fpts + 1] = r.norm end
        end
      else
        meta.fpts = KNOB_PTS
      end
      if not b.gain then
        -- a cut: off when it has an off position or an On switch, else
        -- at the end where it does least
        if meta.off then flat[b.freq] = meta.off
        elseif b.on then flat[b.on] = 1 - flat[b.on]; meta.on_off = true
        else
          local hc = (b.name or ""):lower():match("high cut") or (b.name or ""):lower():match("lpf")
          local f0, f1 = UN.at(fmt_of(job, b.freq), 0), UN.at(fmt_of(job, b.freq), 1)
          local low_end = (f0 and f1 and f0 > f1) and 1 or 0
          flat[b.freq] = hc and (1 - low_end) or low_end
        end
      end
    end
    if b.shape then
      local sw = positions(job, b.shape)
      if sw then
        meta.H = {}
        for _, r in ipairs(sw) do meta.H[#meta.H + 1] = r.norm end
      end
      flat[b.shape] = reaper.TrackFX_GetParamNormalized(job.tmp, job.p, b.shape)
    end
    if b.q then flat[b.q] = reaper.TrackFX_GetParamNormalized(job.tmp, job.p, b.q) end
    -- reports its values: quick
    meta.direct = (not b.freq or unit_at(job, b.freq) == "hz")
      and (not b.gain or unit_at(job, b.gain) == "db")
      and b.q ~= nil and unit_at(job, b.q) ~= "hz" and unit_at(job, b.q) ~= "db"
      and (UN.at(fmt_of(job, b.q), 0.5)) ~= nil
  end
  job.flat = flat
  steps[1] = { ref = true }
  for _, k in ipairs(job.which) do
    local b, meta = cv.bands[k], job.meta[k]
    local shapes = meta.H or { false }
    for si, sv in ipairs(shapes) do
      local fpts = meta.fpts or { false }
      if meta.direct then
        fpts = { fpts[math.floor((#fpts + 1) / 2)] }
      end
      for _, fv in ipairs(fpts) do
        local gpts = meta.gpts or { false }
        -- quick: full boost, and full cut where there is one
        if meta.direct then gpts = { gpts[1], (#gpts >= 4) and gpts[#gpts] or nil } end
        for _, gv in ipairs(gpts) do
          local set = {}
          if sv then set[b.shape] = sv end
          if fv then set[b.freq] = fv end
          if gv then set[b.gain] = gv end
          if not b.gain and meta.on_off then set[b.on] = 1 - job.flat[b.on] end
          steps[#steps + 1] = { k = k, set = set, s = si, fn = fv or nil, gn = gv or nil }
        end
      end
      -- the Q control's sweep, at the middle frequency and full gain
      if b.q and not meta.direct then
        local fpts2 = meta.fpts or { false }
        local fv = fpts2[math.floor((#fpts2 + 1) / 2)]
        for _, qv in ipairs(KNOB_PTS) do
          local set = { [b.q] = qv }
          if sv then set[b.shape] = sv end
          if fv then set[b.freq] = fv end
          if meta.gpts then set[b.gain] = meta.gpts[1] end
          steps[#steps + 1] = { k = k, set = set, s = si, qn = qv }
        end
      end
    end
  end
  job.steps = steps
end

-- ---------------------------------------------------------------------
-- the job
-- ---------------------------------------------------------------------

-- Starts learning bands `which` (indices into layout.canvas.bands; nil:
-- every band not learned for its mapping as it is now) of the plugin at
-- `addr` on `track`. `key` is the layout's library key. Returns the job.
function LN.start(track, addr, key, layout, which)
  local cv = layout.canvas
  local job = { track = track, addr = addr, key = key, layout = layout,
                state = "starting", progress = 0, msg = "Starting\u{2026}",
                samples = {}, pos_cache = {}, params = {} }
  if not which then
    which = {}
    for k, b in ipairs(cv.bands or {}) do
      if not M.band_learned(b) then which[#which + 1] = k end
    end
  end
  job.which = which
  for _, k in ipairs(which) do
    local b = cv.bands[k]
    for _, f in ipairs({ "freq", "gain", "q", "shape", "on" }) do if b[f] then job.params[b[f]] = true end end
    job.samples[k] = {}
  end
  if cv.all_on then job.params[cv.all_on] = true end
  -- every band's dynamics are held off while learning: theirs too
  for _, b in ipairs(cv.bands or {}) do
    for _, f in ipairs(M.DYN_FIELDS) do if b.dyn and b.dyn[f] then job.params[b.dyn[f]] = true end end
  end
  if #which == 0 then job.state, job.msg = "done", "Every band is learned." end
  return job
end

local function finish(job)
  remove_track(job)
  local cv = job.layout.canvas
  local failed = {}
  for _, k in ipairs(job.which) do
    local b, meta = cv.bands[k], job.meta[k]
    local L, why = ME.summarise(job.samples[k], { S = meta.S, H = meta.H, Z = meta.flat, O = meta.O,
                                                  direct = meta.direct, has_freq = b.freq ~= nil })
    if L then
      b.learn = ME.encode(L)
      b.learn_sig = M.band_sig(b)
    else
      failed[#failed + 1] = (b.name ~= "" and b.name or ("Band " .. k)) .. ": " .. (why or "?")
    end
  end
  M.set(job.key, job.layout)
  M.save()
  if #failed > 0 then
    job.state, job.msg = "error", "Not learned \u{2014} " .. table.concat(failed, "; ")
  else
    job.state, job.msg, job.progress = "done", "Learned.", 1
  end
end

local function fail(job, why)
  remove_track(job)
  job.state, job.msg = "error", why
end

function LN.cancel(job)
  if not job or job.state == "done" or job.state == "error" then return end
  remove_track(job)
  job.state, job.msg = "cancelled", "Cancelled."
end

local function read_response()
  local nb = reaper.gmem_read(LN.BASE + 1)
  local out = {}
  for i = 0, (nb or 0) - 1 do out[i + 1] = reaper.gmem_read(LN.BASE + 8 + i) end
  return out, reaper.gmem_read(LN.BASE + 3)
end

local function apply(job, set)
  for p, v in pairs(job.flat) do
    reaper.TrackFX_SetParamNormalized(job.tmp, job.p, p, (set and set[p]) or v)
  end
  for p, v in pairs(set or {}) do
    if job.flat[p] == nil then reaper.TrackFX_SetParamNormalized(job.tmp, job.p, p, v) end
  end
end

local function begin_step(job)
  local st = job.steps[job.i]
  apply(job, st.set)
  job.meas = (job.meas or math.random(1, 1000000)) + 1
  reaper.TrackFX_SetParam(job.tmp, job.ana, 1, job.meas)
  job.t0 = reaper.time_precise()
  job.hb = reaper.gmem_read(LN.BASE + 4) or 0
end

-- One frame's worth of learning. Call every frame while job.state is
-- "starting" or "measuring".
function LN.step(job)
  if not job or (job.state ~= "starting" and job.state ~= "measuring") then return end
  if not reaper.ValidatePtr2(0, job.track, "MediaTrack*") then return fail(job, "The track was removed.") end
  if job.state == "starting" then
    reaper.gmem_attach(LN.NS)
    local ok, why = make_track(job)
    if not ok then return fail(job, why) end
    job.i, job.state = 1, "measuring"
    job.msg = "Measuring\u{2026}"
    if job.mode == "thr" then
      -- a REAPER still running the measuring plugin from before it could
      -- play a tone (TS_CV_Learn.jsfx as it was when first loaded)
      local _, sig = reaper.TrackFX_GetParamName(job.tmp, 0, 7, "")
      if not (sig or ""):lower():find("sidechain", 1, true) then
        return fail(job, "REAPER is still running the older measuring plugin (TS_CV_Learn.jsfx). " ..
          "Restart REAPER and measure again.")
      end
      plan_thr(job); begin_thr(job) return
    end
    if job.mode == "sat" then
      local _, cu = reaper.TrackFX_GetParamName(job.tmp, job.ana, 11, "")
      if not (cu or ""):lower():find("curve", 1, true) then
        return fail(job, "REAPER is still running the older measuring plugin (TS_CV_Learn.jsfx). " ..
          "Restart REAPER and learn again.")
      end
      plan_sat(job); begin_sat(job) return
    end
    if job.mode == "dec" then
      local _, env = reaper.TrackFX_GetParamName(job.tmp, job.ana, 9, "")
      if not (env or ""):lower():find("envelope", 1, true) then
        return fail(job, "REAPER is still running the older measuring plugin (TS_CV_Learn.jsfx). " ..
          "Restart REAPER and measure again.")
      end
      plan_dec(job); begin_dec(job) return
    end
    plan(job)
    begin_step(job)
    return
  end
  if not (job.tmp and reaper.ValidatePtr2(0, job.tmp, "MediaTrack*")) then
    return fail(job, "The learning track was removed.")
  end
  if job.mode == "thr" then return step_thr(job) end
  if job.mode == "dec" then return step_dec(job) end
  if job.mode == "sat" then return step_sat(job) end
  local now = reaper.time_precise()
  if reaper.gmem_read(LN.BASE) ~= job.meas then
    if now - job.t0 > LN.TIMEOUT then
      if (reaper.gmem_read(LN.BASE + 4) or 0) == job.hb then
        return fail(job, "The measuring plugin (TS_CV_Learn.jsfx) isn't running: it may not have " ..
          "loaded, or REAPER isn't running FX while stopped (Preferences \u{25B8} Audio \u{25B8} " ..
          "Playback \u{25B8} Run FX when stopped).")
      end
      return fail(job, "The measurement didn't finish. The plugin may not have passed audio through.")
    end
    return
  end
  local resp, level = read_response()
  if not level or level < -200 then return fail(job, "No sound reached the plugin.") end
  local st = job.steps[job.i]
  if st.ref then
    job.ref = resp
  else
    local freqs, D = {}, {}
    local centres = ME.centres()
    for i, v in ipairs(resp) do
      local r = job.ref[i]
      if v > -500 and r and r > -500 then
        freqs[#freqs + 1] = centres[i]
        D[#D + 1] = v - r
      end
    end
    local b, meta = job.layout.canvas.bands[st.k], job.meta[st.k]
    local fit = ME.fit(freqs, D, meta.kind)
    local sm = { s = st.s, fn = st.fn, gn = st.gn, qn = st.qn, fit = fit }
    if meta.direct and fit then
      if b.freq then sm.rep_f = (UN.parse(select(2, reaper.TrackFX_GetFormattedParamValue(job.tmp, job.p, b.freq, "")))) end
      if b.q then sm.rep_q = (UN.parse(select(2, reaper.TrackFX_GetFormattedParamValue(job.tmp, job.p, b.q, "")))) end
    end
    table.insert(job.samples[st.k], sm)
  end
  job.i = job.i + 1
  job.progress = (job.i - 1) / #job.steps
  local left = (#job.steps - job.i + 1) * math.max(0.5, now - job.t0)
  job.msg = ("Learning on a hidden copy \u{00B7} %d s left"):format(math.ceil(left))
  if job.i > #job.steps then return finish(job) end
  begin_step(job)
end

-- ---------------------------------------------------------------------
-- a compressor's threshold, where it really is
-- ---------------------------------------------------------------------
-- Many compressors' thresholds read in a dB of their own (an SSL's, an
-- API's: 0 dB is some calibrated level, not 0 dBFS). On the same hidden
-- copy, a 1 kHz sine is stepped up in level, 3 dB at a time, at three
-- threshold settings; the reduction above the knee is a straight line
-- whose foot is the threshold, in dBFS (of the sine's peak). Stored as
-- the layout's ThrCal: the threshold's reading (or its position, when it
-- doesn't read in dB) against that.
LN.THR_SETTINGS = { 0.1, 0.35, 0.6, 0.85 }
LN.THR_LO, LN.THR_HI, LN.THR_STEP = -60, 0, 3
LN.THR_LO_IN = -84
-- a copy passing less than this (its gain at 1 kHz, dB) at the quietest
-- tone isn't passing it at all: waited for (a big plugin on a hidden track
-- can take a while to start), up to THR_WAKE times
LN.THR_DEAD, LN.THR_WAKE = -40, 5
local BAND_1K = 68            -- the analyser's band holding 1 kHz (958..1015 Hz)

-- Where the reduction starts, from { {level, reduction}, ... }: a line
-- through the points reduced by 1 dB or more, run back to none. nil when
-- there aren't two, or it hardly reduces.
-- Whether measured thresholds {x, dBFS} move with their control: more
-- than 1 dB between the highest and the lowest.
function LN.thr_moves(pts)
  local lo, hi = math.huge, -math.huge
  for _, q in ipairs(pts) do lo = math.min(lo, q[2]); hi = math.max(hi, q[2]) end
  return hi - lo > 1
end

function LN.thr_fit(pts)
  local xs, ys = {}, {}
  for _, q in ipairs(pts) do
    if q[2] >= 1 and q[2] <= 30 then xs[#xs + 1], ys[#ys + 1] = q[1], q[2] end
  end
  if #xs < 2 then return nil end
  local n, sx, sy, sxx, sxy = #xs, 0, 0, 0, 0
  for i = 1, n do sx = sx + xs[i]; sy = sy + ys[i]; sxx = sxx + xs[i] ^ 2; sxy = sxy + xs[i] * ys[i] end
  local den = n * sxx - sx * sx
  if math.abs(den) < 1e-9 then return nil end
  local slope = (n * sxy - sx * sy) / den
  if slope < 0.05 then return nil end
  local icpt = (sy - slope * sx) / n
  return -icpt / slope, slope
end

function LN.start_thr(track, addr, key, layout)
  local cv = layout.canvas
  local p, via_in = M.thr_param(cv)
  local job = { mode = "thr", track = track, addr = addr, key = key, layout = layout,
                state = "starting", progress = 0, msg = "Starting\u{2026}", pos_cache = {}, params = {} }
  if not p then job.state, job.msg = "error", "Map its threshold (or, with none, its input) first." return job end
  job.thr, job.via_in = p, via_in
  for _, q in pairs(cv.roles) do job.params[q] = true end
  return job
end

function plan_thr(job)
  local cv = job.layout.canvas
  job.flat = {}
  -- fully wet: the reduction undiluted
  local mix = cv.roles.Mix
  if mix then
    local fmt = fmt_of(job, mix)
    local a, b = UN.at(fmt, 0), UN.at(fmt, 1)
    job.flat[mix] = (a and b and a > b) and 0 or 1
  end
  local _, unit = UN.at(fmt_of(job, job.thr), 0.5)
  job.by_db = (unit == "db")
  job.steps = {}
  for si, n in ipairs(LN.THR_SETTINGS) do
    -- an input turned well up puts its threshold far down: start lower
    local lo = job.via_in and LN.THR_LO_IN or LN.THR_LO
    for L = lo, LN.THR_HI, LN.THR_STEP do
      job.steps[#job.steps + 1] = { set = { [job.thr] = n }, si = si, level = L, first = (L == lo) }
    end
  end
  job.thr_pts = {}
  job.thr_ref = {}
end

function begin_thr(job)
  local st = job.steps[job.i]
  apply(job, st.set)
  reaper.TrackFX_SetParam(job.tmp, 0, 5, 1)                  -- the source: a sine
  reaper.TrackFX_SetParam(job.tmp, 0, 7, 1)                  -- on the sidechain too
  reaper.TrackFX_SetParam(job.tmp, 0, 6, st.level)           -- at this level
  reaper.TrackFX_SetParam(job.tmp, job.ana, 3, 1)            -- one frame
  -- the first of each setting: time to recover from the loud end of the last
  reaper.TrackFX_SetParam(job.tmp, job.ana, 4, st.first and 2 or 0.25)
  job.meas = (job.meas or math.random(1, 1000000)) + 1
  reaper.TrackFX_SetParam(job.tmp, job.ana, 1, job.meas)
  job.t0 = reaper.time_precise()
  job.hb = reaper.gmem_read(LN.BASE + 4) or 0
end

local function finish_thr(job)
  local health = copy_health(job)
  remove_track(job)
  local cv = job.layout.canvas
  local pts = {}
  for si, n in ipairs(LN.THR_SETTINGS) do
    local T = LN.thr_fit(job.thr_pts[si] or {})
    -- at the very bottom of the sweep: reducing from the quietest tone on,
    -- which is no threshold (or the tone wasn't coming through)
    local lo = job.via_in and LN.THR_LO_IN or LN.THR_LO
    if T and T <= lo + LN.THR_STEP * 0.5 then T = nil end
    if T then
      local x = n
      if job.by_db then x = job.thr_read[si] end
      if x and x > -math.huge and x < math.huge then pts[#pts + 1] = { x, T } end
    end
  end
  if #pts < 2 then
    -- say what it did, so it can be put right
    local said = {}
    for si, n in ipairs(LN.THR_SETTINGS) do
      local most = 0
      for _, q in ipairs(job.thr_pts[si] or {}) do most = math.max(most, q[2]) end
      said[#said + 1] = ("%d%%: %.1f dB"):format(math.floor(n * 100 + 0.5), most)
    end
    -- and, at the last setting, the tone going in and the gain at 1 kHz,
    -- quietest and loudest: whether the tone moved, and whether the plugin
    -- passed it
    local raw = job.thr_raw and job.thr_raw[#LN.THR_SETTINGS] or {}
    local a, b = raw[1], raw[#raw]
    local how = ""
    if a and b then
      how = (" Tone %+.0f dBFS: in %.1f, gain %.1f dB; tone %+.0f dBFS: in %.1f, gain %.1f dB."):format(
        a[1], a[3], a[2], b[1], b[3], b[2])
      if math.abs(b[3] - a[3]) < 1 then
        how = how .. " The tone's level didn't change: the measuring plugin isn't taking its settings."
      elseif b[2] < -90 then
        how = how .. " No sound came out of the copy: it may not run on a hidden track while stopped."
      else
        how = how .. " The copy passed the tone untouched: it may be bypassed, switched out (its In / Comp switch), " ..
          "or listening to a sidechain on channels other than 3 to 6."
      end
    end
    job.state, job.msg = "error", "It didn't compress a test tone enough to tell where its threshold is " ..
      "(the most it reduced, at each " .. (job.via_in and "input" or "threshold") .. " setting: " .. table.concat(said, ", ") .. ")." .. how .. health
    return
  end
  table.sort(pts, function(a, b) return a[1] < b[1] end)
  -- a threshold that stays put whatever its control says isn't being read
  if not LN.thr_moves(pts) then
    job.state, job.msg = "error", ("Its threshold came out at %.1f dBFS whatever the control was set to, " ..
      "so it wasn't measured: nothing was kept.%s"):format(pts[1][2], health)
    return
  end
  cv.thr_cal = { p = job.thr, n = not job.by_db, pts = pts }
  M.set(job.key, job.layout)
  M.save()
  local z = M.thr_dbfs(cv, job.by_db and 0 or 0.5)
  job.state, job.progress = "done", 1
  if job.via_in then
    -- an input driving it: where the threshold is with the input low, and up
    local function at(x) return job.by_db and ("%+.1f dB"):format(x) or ("%d%%"):format(math.floor(x * 100 + 0.5)) end
    local a, b = pts[1], pts[#pts]
    job.msg = ("Measured: its threshold is %.1f dBFS with the input at %s, %.1f dBFS at %s."):format(
      a[2], at(a[1]), b[2], at(b[1]))
    return
  end
  job.msg = job.by_db and ("Measured: its 0 dB is %.1f dBFS."):format(z or 0)
    or ("Measured: halfway is %.1f dBFS."):format(z or 0)
end

function step_thr(job)
  local now = reaper.time_precise()
  if reaper.gmem_read(LN.BASE) ~= job.meas then
    if now - job.t0 > LN.TIMEOUT then
      if (reaper.gmem_read(LN.BASE + 4) or 0) == job.hb then
        return fail(job, "The measuring plugin (TS_CV_Learn.jsfx) isn't running: it may not have " ..
          "loaded, or REAPER isn't running FX while stopped (Preferences \u{25B8} Audio \u{25B8} " ..
          "Playback \u{25B8} Run FX when stopped).")
      end
      return fail(job, "The measurement didn't finish. The plugin may not have passed audio through.")
    end
    return
  end
  local st = job.steps[job.i]
  local g = reaper.gmem_read(LN.BASE + 8 + BAND_1K - 1)
  if not g or g < -500 then return fail(job, "No sound reached the plugin.") end
  -- (an input-driven one at its lowest input can be quiet anyway: only
  -- nothing at all counts there)
  if st.first and st.si == 1 and g < (job.via_in and -80 or LN.THR_DEAD) then
    -- the quietest tone hardly came out: the copy isn't passing sound (yet)
    job.wake = (job.wake or 0) + 1
    if job.wake <= LN.THR_WAKE then
      job.msg = "Waiting for the copy to pass sound\u{2026}"
      begin_thr(job)
      return
    end
    local health = copy_health(job)
    return fail(job, ("The copy of the plugin passed almost nothing (%.0f dB at 1 kHz, %d tries): " ..
      "it may be bypassed or switched out, its output turned down, or not running on a hidden " ..
      "track while stopped.%s"):format(g, LN.THR_WAKE + 1, health))
  end
  if st.first then job.wake = 0 end
  if st.first then
    job.thr_ref[st.si] = g
    job.thr_read = job.thr_read or {}
    if job.by_db then
      job.thr_read[st.si] = (UN.parse(select(2, reaper.TrackFX_GetFormattedParamValue(job.tmp, job.p, job.thr, ""))))
    end
  end
  local list = job.thr_pts[st.si] or {}
  job.thr_pts[st.si] = list
  local gr = job.thr_ref[st.si] - g
  list[#list + 1] = { st.level, gr }
  -- for saying what happened when it fails: the tone going in, and what
  -- came out at 1 kHz
  job.thr_raw = job.thr_raw or {}
  job.thr_raw[st.si] = job.thr_raw[st.si] or {}
  table.insert(job.thr_raw[st.si], { st.level, g, reaper.gmem_read(LN.BASE + 3) or -999 })
  job.i = job.i + 1
  -- enough of this setting: well into its reduction
  local deep = 0
  for _, q in ipairs(list) do if q[2] >= 1 then deep = deep + 1 end end
  if gr > 12 and deep >= 3 then
    while job.steps[job.i] and job.steps[job.i].si == st.si do job.i = job.i + 1 end
  end
  job.progress = (job.i - 1) / #job.steps
  job.msg = "Finding its threshold on a hidden copy\u{2026}"
  if job.i > #job.steps then return finish_thr(job) end
  begin_thr(job)
end

-- ---------------------------------------------------------------------
-- a reverb's decay, in seconds
-- ---------------------------------------------------------------------
-- A reverb whose decay reads in a scale of its own (0..100): on the same
-- hidden copy, fully wet, a third of a second of noise, and its tail's
-- level every 10 ms until it has fallen 70 dB; the fall from 5 to 25 dB
-- down, run on to 60 dB, is its decay time. At five decay positions, by
-- three size positions when it has a size (size changes the decay too).
LN.DEC_POS = { 0, 0.25, 0.5, 0.75, 1 }
LN.DEC_SIZES = { 0, 0.5, 1 }
LN.DEC_TIMEOUT = 25
local ENV_BASE = 200

-- The decay time (ms) from a tail's levels every 10 ms (dB): the line
-- through the fall from 5 to 25 dB below its loudest, after it. Only
-- what comes after block `from` counts: the burst itself, and any of it
-- heard dry (a mix that isn't fully wet), ends with a sudden drop that
-- isn't the reverb's. nil when it hardly falls.
LN.DEC_FROM = 37                -- the burst is 330 ms, and a block for luck
function LN.decay_fit(env, from)
  from = from or 1
  local pk, ipk = -math.huge, nil
  for i = from, #env do local v = env[i]; if v > pk then pk, ipk = v, i end end
  -- it fell silent before the burst had even ended: no tail
  if not ipk then return nil, (from > 1 and #env > 0) and "dry" or nil end
  -- nothing after the burst worth the name (60 dB under it): no tail at
  -- all, the burst came straight through
  local all = -math.huge
  for i = 1, #env do all = math.max(all, env[i]) end
  if from > 1 and pk < all - 60 then return nil, "dry" end
  local xs, ys = {}, {}
  for i = ipk, #env do
    local v = env[i]
    if v <= pk - 5 and v >= pk - 25 then xs[#xs + 1], ys[#ys + 1] = (i - 1) * 10, v end
    if v < pk - 25 then break end
  end
  if #xs < 2 then
    -- a very short tail: the first two blocks below 5 dB down
    xs, ys = {}, {}
    for i = ipk, #env do
      if env[i] <= pk - 5 then xs[#xs + 1], ys[#ys + 1] = (i - 1) * 10, env[i] end
      if #xs >= 2 then break end
    end
    if #xs < 2 then return nil end
  end
  local n, sx, sy, sxx, sxy = #xs, 0, 0, 0, 0
  for i = 1, n do sx = sx + xs[i]; sy = sy + ys[i]; sxx = sxx + xs[i] ^ 2; sxy = sxy + xs[i] * ys[i] end
  local den = n * sxx - sx * sx
  if math.abs(den) < 1e-9 then return nil end
  local slope = (n * sxy - sx * sy) / den      -- dB a ms
  if slope >= -0.0005 then return 120000 end   -- held (a freeze): two minutes
  return math.min(120000, -60 / slope)
end

-- What was measured, in words: the time at each decay position (at the
-- middle size, when it was measured by size).
function LN.decay_summary(dc)
  local mid
  for _, q in ipairs(dc.pts) do if q[1] >= 0 and (not mid or math.abs(q[1] - 0.5) < math.abs(mid - 0.5)) then mid = q[1] end end
  local t = {}
  for _, q in ipairs(dc.pts) do
    if q[1] == (mid or -1) then t[#t + 1] = ("%d: %.2f s"):format(math.floor(q[2] * 100 + 0.5), q[3] / 1000) end
  end
  return table.concat(t, ", ") .. (mid and (" (size at %d%%)"):format(math.floor(mid * 100 + 0.5)) or "")
end

function LN.start_decay(track, addr, key, layout)
  local cv = layout.canvas
  local p = cv and cv.roles and cv.roles.Decay
  local job = { mode = "dec", track = track, addr = addr, key = key, layout = layout,
                state = "starting", progress = 0, msg = "Starting\u{2026}", pos_cache = {}, params = {} }
  if not p then job.state, job.msg = "error", "Map its decay first." return job end
  job.dec, job.size = p, cv.roles.Size
  for _, q in pairs(cv.roles) do job.params[q] = true end
  return job
end

function plan_dec(job)
  local cv = job.layout.canvas
  job.flat = {}
  local mix = cv.roles.Mix
  if mix then
    local fmt = fmt_of(job, mix)
    local a, b = UN.at(fmt, 0), UN.at(fmt, 1)
    job.flat[mix] = (a and b and a > b) and 0 or 1
  end
  -- first, in the middle of its range: which end of its Mix is wet. (Not
  -- at the first point of the grid: its shortest, smallest setting can
  -- ring for so short a time it looks dry.)
  job.steps = { { probe = true, set = { [job.dec] = 0.5, [job.size or -1] = job.size and 0.5 or nil }, dn = 0.5 } }
  for _, sn in ipairs(job.size and LN.DEC_SIZES or { false }) do
    for _, dn in ipairs(LN.DEC_POS) do
      local set = { [job.dec] = dn }
      if sn then set[job.size] = sn end
      job.steps[#job.steps + 1] = { set = set, dn = dn, sn = sn }
    end
  end
  job.dec_pts = {}
end

function begin_dec(job)
  local st = job.steps[job.i]
  apply(job, st.set)
  reaper.TrackFX_SetParam(job.tmp, 0, 5, 2)                  -- the source: bursts
  reaper.TrackFX_SetParam(job.tmp, 0, 6, -12)                -- of noise at -12 dBFS
  reaper.TrackFX_SetParam(job.tmp, job.ana, 9, 1)            -- the analyser: the tail
  job.meas = (job.meas or math.random(1, 1000000)) + 1
  -- a moment for the setting to take (longer the first time: a big plugin
  -- takes a while to wake), then the burst and the recording together
  job.wait_until = reaper.time_precise() + (job.wait_next or ((job.i == 1 and not job.flipped) and 1.5 or 0.4))
  job.wait_next = nil
  job.started = false
  job.t0 = reaper.time_precise()
  job.hb = reaper.gmem_read(LN.BASE + 4) or 0
end

local function finish_dec(job)
  local health = copy_health(job)
  remove_track(job)
  local cv = job.layout.canvas
  if #job.dec_pts < 2 then
    if (job.dry or 0) > 0 then
      local d = job.dec_seen or {}
      local function f(v) return (v and v > -500) and ("%.0f dB"):format(v) or "silence" end
      job.state, job.msg = "error", "No reverb came back: the burst came straight through, dry, at either end of " ..
        "its Mix. Check Mix is mapped to its wet/dry control, and that the plugin runs while REAPER is stopped. " ..
        ("(Out of the copy: during the burst %s; just after %s; half a second on %s; later %s; %d blocks.)"):format(
          f(d[1]), f(d[2]), f(d[3]), f(d[4]), d[5] or 0) .. health
    else
      job.state, job.msg = "error", "Its tail couldn't be timed: no sound came back, or it didn't fall away."
    end
    return
  end
  cv.dec_cal = { p = job.dec, s = job.size, pts = job.dec_pts }
  M.set(job.key, job.layout)
  M.save()
  job.state, job.progress = "done", 1
  job.msg = "Measured: " .. LN.decay_summary(cv.dec_cal)
end

function step_dec(job)
  local now = reaper.time_precise()
  if not job.started then
    if now < job.wait_until then return end
    job.started = true
    reaper.TrackFX_SetParam(job.tmp, job.ana, 1, job.meas)
    reaper.TrackFX_SetParam(job.tmp, 0, 8, job.meas)
    job.t0 = now
    return
  end
  if reaper.gmem_read(LN.BASE) ~= job.meas then
    if now - job.t0 > LN.DEC_TIMEOUT then
      if (reaper.gmem_read(LN.BASE + 4) or 0) == job.hb then
        return fail(job, "The measuring plugin (TS_CV_Learn.jsfx) isn't running: REAPER may not be " ..
          "running FX while stopped (Preferences \u{25B8} Audio \u{25B8} Playback \u{25B8} Run FX when stopped).")
      end
      return fail(job, "The tail didn't finish in time.")
    end
    return
  end
  local st = job.steps[job.i]
  local nb = math.floor(reaper.gmem_read(LN.BASE + 1) or 0)
  local env = {}
  for i = 0, nb - 1 do env[i + 1] = reaper.gmem_read(LN.BASE + ENV_BASE + i) end
  local ms, why = LN.decay_fit(env, LN.DEC_FROM)
  -- for saying what came back if it fails: during the burst, and after
  local function lv(a, b)
    local m = -math.huge
    for i = a, math.min(b, #env) do m = math.max(m, env[i] or -math.huge) end
    return m
  end
  job.dec_seen = { lv(1, 33), lv(38, 45), lv(60, 110), lv(150, 400), #env }
  local dry = (why == "dry") or (ms ~= nil and ms < 30)
  if st.probe then
    -- in the middle of its range, no tail (or one under 30 ms) is the burst
    -- coming straight through, not a reverb: try its Mix the other way
    -- round (a mix whose wet end is where we thought dry was), and if
    -- that's dry too, say so and stop
    if dry then
      local mix = job.layout.canvas.roles.Mix
      job.dry = (job.dry or 0) + 1
      -- a big plugin can pass audio straight through while it's still
      -- waking up (seconds, for some): give it a few more goes first
      job.probe_tries = (job.probe_tries or 0) + 1
      if job.probe_tries < 5 then
        job.wait_next = 2
        job.msg = "Waiting for the copy to wake up\u{2026}"
        return begin_dec(job)
      end
      job.probe_tries = 0
      if mix and not job.flipped then
        job.flipped = true
        job.flat[mix] = 1 - (job.flat[mix] or 1)
        return begin_dec(job)
      end
      job.dec_pts = {}
      return finish_dec(job)
    end
    job.dry = nil
  else
    -- across the grid a short setting may ring only briefly: kept; only
    -- no tail at all is left out
    if why == "dry" then job.dry = (job.dry or 0) + 1; ms = nil end
    if ms then job.dec_pts[#job.dec_pts + 1] = { st.sn or -1, st.dn, math.max(1, ms) } end
  end
  job.i = job.i + 1
  job.progress = (job.i - 1) / #job.steps
  job.msg = "Timing its tail on a hidden copy\u{2026}"
  if job.i > #job.steps then return finish_dec(job) end
  begin_dec(job)
end

-- ---------------------------------------------------------------------
-- a saturator's curve and harmonics
-- ---------------------------------------------------------------------
-- On the same hidden copy, fully wet: a 250 Hz sine at each of a few
-- levels, at each Drive (five points along it, or its settings) and each
-- Style; tone controls stay where they are (they shape the sound more than
-- the curve, and each would multiply the time). What comes out, lined up
-- with what went in at the sine's frequency, is binned against
-- what went in -- the transfer curve, rising and falling apart -- at the
-- loudest level, and its harmonics read at every level. Stored as the
-- layout's SatCal (TS_CV_Mappings M.sat_*).
LN.SAT_FREQ = 250
LN.SAT_LEVELS = { -18, -6, 0 }
LN.SAT_KNOB = { 0, 0.25, 0.5, 0.75, 1 }
LN.SAT_TONE = { 0, 0.5, 1 }
LN.SAT_MAX_POS = 12             -- a switch with more settings: this many of them, spread

function LN.start_sat(track, addr, key, layout)
  local cv = layout.canvas
  local p = cv and cv.roles and cv.roles.Drive
  local job = { mode = "sat", track = track, addr = addr, key = key, layout = layout,
                state = "starting", progress = 0, msg = "Starting\u{2026}", pos_cache = {}, params = {} }
  if not p then job.state, job.msg = "error", "Map its drive first." return job end
  for _, q in pairs(cv.roles) do job.params[q] = true end
  return job
end

-- a control's points to learn at: its settings (spread, when many), else `knob`
local function sat_points(job, p, knob)
  if not p then return { false } end
  local sw = positions(job, p)
  if not sw then return knob end
  local out = {}
  local n = #sw
  local take = math.min(n, LN.SAT_MAX_POS)
  for i = 1, take do
    local r = sw[math.floor((i - 1) * (n - 1) / math.max(1, take - 1) + 0.5) + 1]
    out[#out + 1] = r.norm
  end
  return out
end

function plan_sat(job)
  local cv = job.layout.canvas
  local R = cv.roles
  job.flat = {}
  local mix = R.Mix
  if mix then
    local fmt = fmt_of(job, mix)
    local a, b = UN.at(fmt, 0), UN.at(fmt, 1)
    job.flat[mix] = (a and b and a > b) and 0 or 1
  end
  job.cal = { d = R.Drive, s = R.Style, t = R.Tone, L = LN.SAT_LEVELS, e = {} }
  job.cal.dn = sat_points(job, R.Drive, LN.SAT_KNOB)
  job.cal.sn = sat_points(job, R.Style, { 0, 0.5, 1 })
  job.cal.tn = { false }
  job.steps = {}
  for si, sn in ipairs(job.cal.sn) do
    for ti, tn in ipairs(job.cal.tn) do
      for di, dn in ipairs(job.cal.dn) do
        for li, L in ipairs(LN.SAT_LEVELS) do
          local set = { [R.Drive] = dn }
          if sn then set[R.Style] = sn end
          if tn then set[R.Tone] = tn end
          job.steps[#job.steps + 1] = { set = set, key = ("%d.%d.%d"):format(di, si, ti), li = li, level = L,
                                        first = (li == 1), curve = (li == #LN.SAT_LEVELS) }
        end
      end
    end
  end
end

function begin_sat(job)
  local st = job.steps[job.i]
  apply(job, st.set)
  for _, fx in ipairs({ 0, job.ana }) do
    reaper.TrackFX_SetParam(job.tmp, fx, 5, 1)                 -- a sine
    reaper.TrackFX_SetParam(job.tmp, fx, 6, st.level)          -- at this level
    reaper.TrackFX_SetParam(job.tmp, fx, 10, LN.SAT_FREQ)      -- and frequency
  end
  reaper.TrackFX_SetParam(job.tmp, 0, 7, 0)                    -- not on a sidechain
  reaper.TrackFX_SetParam(job.tmp, job.ana, 11, 1)             -- the curve and harmonics
  reaper.TrackFX_SetParam(job.tmp, job.ana, 3, 1)              -- one frame
  reaper.TrackFX_SetParam(job.tmp, job.ana, 4, (job.i == 1) and 1 or (st.first and 0.3 or 0.12))
  job.meas = (job.meas or math.random(1, 1000000)) + 1
  reaper.TrackFX_SetParam(job.tmp, job.ana, 1, job.meas)
  job.t0 = reaper.time_precise()
  job.hb = reaper.gmem_read(LN.BASE + 4) or 0
end

local function finish_sat(job)
  local health = copy_health(job)
  remove_track(job)
  local cv = job.layout.canvas
  local n = 0
  for _ in pairs(job.cal.e) do n = n + 1 end
  if n == 0 then
    job.state, job.msg = "error", "Nothing came back to learn from." .. health
    return
  end
  cv.sat_cal = job.cal
  M.set(job.key, job.layout)
  M.save()
  job.state, job.progress = "done", 1
  local mid = M.sat_at(job.cal, 0.5, 0, 0.5)
  local b = M.sat_bite(mid)
  job.msg = ("Learned at %d settings%s."):format(n,
    b and (": with Drive halfway it starts to bite from %.0f dBFS"):format(b) or "")
end

function step_sat(job)
  local now = reaper.time_precise()
  if reaper.gmem_read(LN.BASE) ~= job.meas then
    if now - job.t0 > LN.TIMEOUT then
      if (reaper.gmem_read(LN.BASE + 4) or 0) == job.hb then
        return fail(job, "The measuring plugin (TS_CV_Learn.jsfx) isn't running: REAPER may not be " ..
          "running FX while stopped (Preferences \u{25B8} Audio \u{25B8} Playback \u{25B8} Run FX when stopped).")
      end
      return fail(job, "The measurement didn't finish. The plugin may not have passed audio through.")
    end
    return
  end
  local st = job.steps[job.i]
  local g = reaper.gmem_read(LN.BASE + 361)
  -- the very first: the copy may not pass sound yet
  if job.i == 1 and (not g or g < -60) then
    job.wake = (job.wake or 0) + 1
    if job.wake <= 5 then
      job.msg = "Waiting for the copy to pass sound\u{2026}"
      return begin_sat(job)
    end
    return fail(job, ("The copy of the plugin passed almost nothing (%.0f dB): it may be bypassed, " ..
      "its output turned down, or not running on a hidden track while stopped.%s"):format(g or -999, copy_health(job)))
  end
  local e = job.cal.e[st.key] or { up = {}, dn = {}, h = {} }
  job.cal.e[st.key] = e
  local h = { (g and g > -200) and g or nil }
  for k = 2, M.SAT_NH do
    local v = reaper.gmem_read(LN.BASE + 360 + k)
    h[k] = (v and v > -200) and math.max(-120, v) or nil
  end
  e.h[st.li] = h
  if st.curve then
    for b = 1, M.SAT_CB do
      local u = reaper.gmem_read(LN.BASE + 300 + b - 1)
      local d = reaper.gmem_read(LN.BASE + 330 + b - 1)
      e.up[b] = (u and u > -900) and u or nil
      e.dn[b] = (d and d > -900) and d or nil
    end
  end
  job.i = job.i + 1
  job.progress = (job.i - 1) / #job.steps
  job.msg = "Learning its curve on a hidden copy\u{2026}"
  if job.i > #job.steps then return finish_sat(job) end
  begin_sat(job)
end

-- Whether a temporary track was left behind (ChannelView stopped in the
-- middle of learning): removed on the next start.
function LN.sweep()
  for i = reaper.CountTracks(0) - 1, 0, -1 do
    local tr = reaper.GetTrack(0, i)
    local _, nm = reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", "", false)
    if nm == LN.TRACK_NAME then reaper.DeleteTrack(tr) end
  end
end

return LN
