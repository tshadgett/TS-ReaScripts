-- @noindex
-- Not a package of its own: installed by TS_ChannelView.lua's @provides.
--[[
  TS_CV_Trace.lua -- the gain-reduction trace's data, without the drawing.

  Click a gain-reduction meter and it opens out into a trace beside it:
  the plugin's own output waveform, its input faintly behind, and its
  reduction drawn down from the top -- the same picture Track Analyser
  draws for the whole track, for just this plugin. TS_CV_Panel draws it in
  the window; TS_ChannelView_Web.lua sends the same columns to the page.

  The audio comes from the plugin's probe tap (PER-PLUGIN WAVEFORMS in
  TS_TrackProbe.jsfx): columns of output min/max, input peak and, for a
  measured plugin, its reduction, 4 ms apart. A plugin that reports its
  own reduction is tapped for its levels while open (TS_CV_Taps), and its
  reports are laid onto the same column clock here, late by the latency
  between it and the post probe so they sit on the audio they belong to.
--]]

local C  = require("TS_CV_Config")
local TP = require("TS_CV_Taps")

local Tr = {}

local TW_BASE, TW_HDR, TW_COLS = 0x54000, 0x5C000, 2048
Tr.COLS = TW_COLS

local frame_no = 0
-- Call once a frame (or cycle): the probe is read at most once per call.
function Tr.begin_frame() frame_no = frame_no + 1 end

-- A mirror of the probe's columns. Only the columns written since the last
-- frame are read, so an open trace costs a handful of reads a frame, not
-- the 8000 a full window would.
local tw = { n = -1, cur = 0, writer = -1, moved = -10, live = false, frame = -1 }
for t = 1, 4 do tw[t] = { mn = {}, mx = {}, ip = {}, gr = {} } end

local function tw_sync()
  if tw.frame == frame_no then return tw.live end
  tw.frame = frame_no
  local rd = reaper.gmem_read
  local n      = rd(TW_HDR + 5) or 0
  local cur    = math.floor(rd(TW_HDR) or 0) % TW_COLS
  local writer = rd(TW_HDR + 4) or 0
  tw.slice, tw.sr = rd(TW_HDR + 2) or 0, rd(TW_HDR + 3) or 0
  local now = reaper.time_precise()
  if n ~= tw.n then tw.moved = now end
  -- Live while the columns move -- or, with the transport stopped (the
  -- probe stops advancing them then), while there's a pass to look at.
  local stopped = (reaper.GetPlayState() & 1) == 0
  tw.live = tw.slice > 0 and tw.sr > 0
            and ((now - tw.moved) < 0.5 or (stopped and n > 0))
  if n ~= tw.n or writer ~= tw.writer then
    local todo = n - tw.n
    if tw.n < 0 or writer ~= tw.writer or todo < 0 or todo >= TW_COLS then todo = TW_COLS end
    for k = todo - 1, 0, -1 do
      local c = (cur - k) % TW_COLS
      for t = 1, 4 do
        local b, d = TW_BASE + ((t - 1) * TW_COLS + c) * 4, tw[t]
        d.mn[c], d.mx[c], d.ip[c], d.gr[c] = rd(b), rd(b + 1), rd(b + 2), rd(b + 3)
      end
    end
    tw.n, tw.cur, tw.writer = n, cur, writer
  end
  return tw.live
end

-- Reported reduction, laid onto the probe's column clock, per instance.
local reps = {}
local function rep_record(guid, c, v)
  local h = reps[guid]
  if not h then h = { gr = {} }; reps[guid] = h end
  if h.c then
    local span = (c - h.c) % TW_COLS
    if span == 0 then
      h.gr[c] = math.max(h.gr[c] or 0, v)
    elseif span < 256 then
      for k = 1, span do h.gr[(h.c + k) % TW_COLS] = h.v + (v - h.v) * k / span end
    else
      h.gr[c] = v
    end
  else
    h.gr[c] = v
  end
  h.c, h.v = c, v
end

-- Samples of latency between a plugin and the post probe: the plugins after
-- it (its tapped copies pass through them), and for a reporting plugin its
-- own as well, since it reports on audio it has yet to put out. Top-level
-- chains only; anything else counts as none. Re-read once a second.
local lat_cache = {}
local function latency_to_probe(track, fx, probe, own)
  local key = fx.guid .. (own and "+" or "")
  local e = lat_cache[key]
  local now = reaper.time_precise()
  if e and now - e.t < 1 then return e.v end
  local function pdc(a)
    if not reaper.TrackFX_GetEnabled(track, a) or reaper.TrackFX_GetOffline(track, a) then return 0 end
    local ok, v = reaper.TrackFX_GetNamedConfigParm(track, a, "pdc")
    local n = ok and tonumber(v)
    return (n and n > 0) and n or 0
  end
  local total = 0
  if type(fx.addr) == "number" and type(probe) == "number" and fx.addr < probe
     and fx.addr < 0x2000000 and probe < 0x2000000 then
    for a = fx.addr + 1, probe - 1 do total = total + pdc(a) end
    if own then total = total + pdc(fx.addr) end
  end
  lat_cache[key] = { t = now, v = total }
  return total
end

-- Beat lock, as Track Analyser's: armed once from the play position, then
-- stepped a whole beat at a time on the probe's own column count, so hits
-- land in the same place every pass instead of crawling across.
local locks = {}

function Tr.win_parts(win)
  local n, u = tostring(win or ""):match("^(%d+)([bs])$")
  if not n then n, u = C.GRV_DEFAULT:match("^(%d+)([bs])$") end
  return tonumber(n), u
end

function Tr.label(win)
  local n, u = Tr.win_parts(win)
  if u == "b" then return n == 1 and "1 beat" or (n .. " beats") end
  return n .. " s"
end

local waiting = {}   -- guid -> when the trace started waiting for the probe

-- Asks for the probe's waveforms for this track. Call every frame a trace
-- on it is showing.
function Tr.want(track) TP.wave_track(track) end

-- The trace for one plugin instance, `pw` columns wide:
--   nil, msg1, msg2   nothing to draw yet (msg2 may be nil)
--   t                 { mn, mx, ip, g = arrays 1..pw (g[i] nil where there's
--                       no reading), sc = the waveform's full scale,
--                       beats = the window's beat count when beat-locked }
-- `meter` is the layout's meter ({ win = ... }), `est` whether the reduction
-- is measured, `gr` the current reported reduction (dB).
function Tr.columns(track, fx, meter, est, gr, pw)
  local ti, probe = TP.tap_index(track, fx.guid)
  if not ti then
    return nil, TP.has_probes(track) and "connecting\u{2026}" or "needs TS_TrackProbe"
  end
  local live = tw_sync()
  local mine = math.floor(reaper.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER"))
  if not live or tw.writer ~= mine then
    -- A project keeps running the probe it loaded with, so after an update
    -- the old one -- which writes no waveforms -- is there until reopened.
    local since = waiting[fx.guid]
    if not since then since = reaper.time_precise(); waiting[fx.guid] = since end
    if reaper.time_precise() - since > 3 then
      return nil, "no waveform from the probe", "reopen the project to update it"
    end
    return nil, "waiting for the probe\u{2026}"
  end
  waiting[fx.guid] = nil

  -- the window, in columns
  local cps = tw.sr / tw.slice
  local n, unit = Tr.win_parts(meter and meter.win)
  local beat
  local secs = n
  if unit == "b" then
    local bpm = reaper.Master_GetTempo()
    beat = 60 / ((bpm and bpm > 1) and bpm or 120)
    secs = n * beat
  end
  local total = math.max(8, math.min(TW_COLS - 16, math.floor(secs * cps)))
  local newest = tw.cur
  if beat then
    local L = locks[fx.guid]
    if not L then L = {}; locks[fx.guid] = L end
    local step = beat * cps
    if L.step ~= step or not L.anchor then
      L.step, L.anchor = step, tw.cur
      if (reaper.GetPlayState() & 1) == 1 then
        local qn = reaper.TimeMap2_timeToQN(0, reaper.GetPlayPosition())
        L.anchor = tw.cur - (qn - math.floor(qn)) * step
      end
    end
    local guard = 0
    while ((tw.cur - L.anchor) % TW_COLS) >= step and guard < 256 do
      L.anchor = L.anchor + step
      guard = guard + 1
    end
    L.anchor = L.anchor % TW_COLS
    newest = math.floor(L.anchor) % TW_COLS
  else
    locks[fx.guid] = nil
  end
  local oldest = (newest - total) % TW_COLS

  -- a reporting plugin's reports, laid onto the clock
  if not est then
    local lag = latency_to_probe(track, fx, probe, true)
    rep_record(fx.guid, (tw.cur + math.floor(lag / tw.slice + 0.5)) % TW_COLS, gr or 0)
  end
  local d = tw[ti]
  local gsrc = est and d.gr or (reps[fx.guid] and reps[fx.guid].gr) or {}

  -- scale: the loudest moment in view, held so a quiet bar doesn't pump
  local pk = 0
  for k = 0, total - 1 do
    local c = (oldest + k) % TW_COLS
    local a = math.max(-(d.mn[c] or 0), d.mx[c] or 0, d.ip[c] or 0)
    if a > pk then pk = a end
  end
  local sk = "s" .. fx.guid
  local sc = math.max(pk, (locks[sk] or 0.05) * 0.985, 0.02)
  locks[sk] = sc

  pw = math.max(1, math.floor(pw))
  local out = { mn = {}, mx = {}, ip = {}, g = {}, sc = sc,
                beats = (beat and n > 1) and n or nil }
  for px = 0, pw - 1 do
    local k0 = math.floor(px / pw * total)
    local k1 = math.max(k0, math.floor((px + 1) / pw * total) - 1)
    local mn, mx, ip, g = 0, 0, 0, nil
    for k = k0, k1 do
      local c = (oldest + k) % TW_COLS
      local a, b, i = d.mn[c] or 0, d.mx[c] or 0, d.ip[c] or 0
      if a < mn then mn = a end
      if b > mx then mx = b end
      if i > ip then ip = i end
      local v = gsrc[c]
      if v and (not g or v > g) then g = v end
    end
    out.mn[px + 1], out.mx[px + 1], out.ip[px + 1], out.g[px + 1] = mn, mx, ip, g
  end
  return out
end

return Tr
