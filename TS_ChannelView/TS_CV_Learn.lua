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
  reaper.TrackFX_Show(tr, job.p, 2)
  reaper.TrackFX_SetEnabled(tr, job.p, true)
  if reaper.TrackFX_SetOffline then reaper.TrackFX_SetOffline(tr, job.p, false) end
  reaper.TrackFX_SetParam(tr, 0, 0, 0)          -- source
  reaper.TrackFX_SetParam(tr, ana, 0, 1)        -- analyser
  local _, pdc = reaper.TrackFX_GetNamedConfigParm(tr, job.p, "pdc")
  reaper.TrackFX_SetParam(tr, ana, 2, tonumber(pdc) or 0)
  -- the copy must answer only to what we write: no links from the
  -- original track's macros, no lanes holding a parameter where it is
  local EN = require("TS_CV_Envelopes")
  for p in pairs(job.params) do
    reaper.TrackFX_SetNamedConfigParm(tr, job.p, ("param.%d.mod.active"):format(p), "0")
    local env = reaper.GetFXEnvelope(tr, job.p, p, false)
    if env then EN.remove(tr, env) end
  end
  return true
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

local function plan(job)
  local steps, flat = {}, {}
  local cv = job.layout.canvas
  if cv.all_on then flat[cv.all_on] = on_value(job, cv.all_on) end
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
    plan(job)
    job.i, job.state = 1, "measuring"
    job.msg = "Measuring\u{2026}"
    begin_step(job)
    return
  end
  if not (job.tmp and reaper.ValidatePtr2(0, job.tmp, "MediaTrack*")) then
    return fail(job, "The learning track was removed.")
  end
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
