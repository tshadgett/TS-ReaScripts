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

  Whether a plugin's report is early (a look-ahead that reports on audio
  it has yet to put out) or already lined up with its output (many delay
  their own meter to match) isn't something it says. So the reports are
  recorded at the latency of the plugins AFTER it, and the plugin's own
  share is found: about once a second, the reports are compared with the
  reduction the tap itself sees (its input against its output) at each
  offset from a little early to past its own latency, and drawn at the
  one where they agree best. Until there's music enough to tell, they're
  drawn late by its own latency, as a look-ahead's would be.

  The output is the guide. The tap's input copy may or may not have been
  held back by the plugin's latency on its way (REAPER delays what passes
  a plugin; a copy that skips it isn't), so it's lined up the same way:
  about once a second, the input's levels against the output's at each
  delay from a little early to past the plugin's own latency, and the
  input drawn at the delay where they match best (as Track Analyser holds
  its input back by the plugins' latency). The reports are then matched
  against that input.
--]]

local C  = require("TS_CV_Config")
local TP = require("TS_CV_Taps")

local Tr = {}

local TW_BASE, TW_HDR, TW_COLS = 0x54000, 0x5C000, 2048
local TW_BASE2 = 0x208000      -- taps 5..8 (a probe that takes eight)
local TAPS = 8
-- tap t's (1-based) column c
local function tw_at(t, c)
  if t <= 4 then return TW_BASE + ((t - 1) * TW_COLS + c) * 4 end
  return TW_BASE2 + ((t - 5) * TW_COLS + c) * 4
end
Tr.COLS = TW_COLS

local frame_no = 0
-- Call once a frame (or cycle): the probe is read at most once per call.
function Tr.begin_frame() frame_no = frame_no + 1 end

-- A mirror of the probe's columns. Only the columns written since the last
-- frame are read, so an open trace costs a handful of reads a frame, not
-- the 8000 a full window would.
local tw = { n = -1, cur = 0, writer = -1, moved = -10, live = false, frame = -1 }
for t = 1, TAPS do tw[t] = { mn = {}, mx = {}, ip = {}, gr = {} } end

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
  -- the taps the writer has (an older probe doesn't say: four)
  local taps = math.floor(rd(TW_HDR + 6) or 0)
  taps = (taps >= 1 and taps <= TAPS) and taps or 4
  if n ~= tw.n or writer ~= tw.writer then
    local todo = n - tw.n
    if tw.n < 0 or writer ~= tw.writer or todo < 0 or todo >= TW_COLS then todo = TW_COLS end
    for k = todo - 1, 0, -1 do
      local c = (cur - k) % TW_COLS
      for t = 1, taps do
        local b, d = tw_at(t, c), tw[t]
        d.mn[c], d.mx[c], d.ip[c], d.gr[c] = rd(b), rd(b + 1), rd(b + 2), rd(b + 3)
      end
    end
    tw.n, tw.cur, tw.writer = n, cur, writer
  end
  return tw.live
end

-- Reported reduction, laid onto the probe's column clock, per instance.
local reps = {}
-- How far each instance's tap input is held back to sit on its output.
local ins = {}
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

-- Where a reporting plugin's reports line up with its audio. h: its
-- reports on the column clock (h.gr), and what was found (h.k: columns to
-- draw them late by; h.corr). d: the tap's columns. own_c: the plugin's
-- own latency, in columns (the input is early by that). Looks again about
-- once a second, over the last few seconds: the offset where the reports
-- and the tap's own reduction (input over output, in dB, while there's
-- signal) agree best, as long as they agree well.
Tr.ALIGN_COLS, Tr.ALIGN_MIN = 750, 0.4
Tr.ALIGN_BACK = 160     -- columns a report may come late by (about 0.6 s)
local log10 = function(x) return math.log(x, 10) end

-- The delay k (columns, k_lo..k_hi) at which series b, read k columns
-- back, best matches series a (both { [j] = value }, j columns back from
-- now): the Pearson correlation over the columns both have. best k, corr.
local function best_lag(a, b_at, k_lo, k_hi)
  local most = 0
  local function corr_at(k, stride)
    local n, sx, sy, sxx, syy, sxy = 0, 0, 0, 0, 0, 0
    for j, x in pairs(a) do
      if j % stride == 0 then
        local y = b_at(j + k)
        if y then
          n = n + 1; sx = sx + x; sy = sy + y
          sxx = sxx + x * x; syy = syy + y * y; sxy = sxy + x * y
        end
      end
    end
    if stride == 1 and n > most then most = n end
    if n < 80 / stride then return nil end
    local vx, vy = n * sxx - sx * sx, n * syy - sy * sy
    if vx <= 1e-9 or vy <= 1e-9 then return nil end
    return (n * sxy - sx * sy) / math.sqrt(vx * vy)
  end
  -- coarse (every 4th offset, every 3rd column), then fine around the best
  local best, bk = -2, nil
  for k = k_lo, k_hi, 4 do
    local c = corr_at(k, 3)
    if c and c > best then best, bk = c, k end
  end
  if not bk then corr_at(k_lo, 1); return nil, best, most end
  local c0 = bk
  best, bk = -2, nil
  for k = math.max(k_lo, c0 - 4), math.min(k_hi, c0 + 4) do
    local c = corr_at(k, 1)
    if c and c > best then best, bk = c, k end
  end
  return bk, best, most, corr_at
end

-- How far the tap's input is to be held back (columns) to sit on its
-- output: e.k, found about once a second while there's signal; nil until
-- then. own_c: the plugin's own latency, in columns (the search runs past it).
function Tr.align_input(e, d, own_c, cur, now)
  now = now or reaper.time_precise()
  if e.t_in and now - e.t_in < 1 then return end
  e.t_in = now
  local out, any, top, itop = {}, 0, 0, 0
  for j = 0, Tr.ALIGN_COLS - 1 do
    local c = (cur - j) % TW_COLS
    local op = math.max(-(d.mn[c] or 0), d.mx[c] or 0)
    if op > top then top = op end
    if (d.ip[c] or 0) > itop then itop = d.ip[c] end
    if op > 0.003 then out[j] = 20 * log10(op); any = any + 1 end
  end
  e.peaks = ("loudest out %.4f in %.4f, cur %s"):format(top, itop, tostring(cur))
  -- (what it saw is kept from the last time there was signal)
  if any < 100 then e.quiet = true return end
  e.quiet = nil
  local k, corr, most, corr_at = best_lag(out, function(jj)
    local ip = d.ip[(cur - jj) % TW_COLS] or 0
    return ip > 0.0001 and 20 * log10(ip) or nil
  end, -8, own_c + 24)
  -- between columns: the peak of a parabola through the best and its
  -- neighbours (the probe's tap wants samples, not 4 ms steps)
  e.frac = nil
  if k then
    local a, c = corr_at(k - 1, 1), corr_at(k + 1, 1)
    if a and c and corr then
      local den = a - 2 * corr + c
      if den < -1e-9 then e.frac = math.max(-0.5, math.min(0.5, 0.5 * (a - c) / den)) end
    end
  end
  e.dbg = ("out %d, both %d, best k %s at %.2f"):format(any, most, tostring(k), corr or -2)
  if k and corr >= Tr.ALIGN_MIN then
    -- the same twice running: steady enough to hand the probe (a tap's
    -- delay is only moved for a real change, not a column's wobble)
    local kf = k + (e.frac or 0)
    if e.k and math.abs(e.k - k) <= 1 then
      -- moved on only for a real change: a quarter of a column (1 ms)
      if not e.stable or math.abs(e.stable - kf) > 0.25 then e.stable = kf end
    end
    e.k, e.corr = k, corr
  end
end
function Tr.realign(h, d, in_c, cur, now, own_c)
  now = now or reaper.time_precise()
  if h.t_al and now - h.t_al < 1 then return end
  h.t_al = now
  local m, any = {}, 0
  for j = 0, Tr.ALIGN_COLS - 1 do
    local c = (cur - j) % TW_COLS
    local ip = d.ip[(c - in_c) % TW_COLS] or 0
    local op = math.max(-(d.mn[c] or 0), d.mx[c] or 0)
    if ip > 0.003 and op > 0.0001 then            -- signal: over -50 dBFS
      m[j] = 20 * log10(ip / op); any = any + 1
    end
  end
  if any < 100 then h.quiet = true return end
  h.quiet = nil
  -- (reports can come late as well as early: a plugin may hold its meter
  -- back to when the audio is heard, REAPER rendering ahead of that)
  local function rep_at(jj)
    local i = (cur - jj) % TW_COLS
    -- nothing past the latest report (the ring holds older ones there)
    if h.c and ((h.c - i) % TW_COLS) >= TW_COLS / 2 then return nil end
    return h.gr[i]
  end
  local k, corr, most = best_lag(m, rep_at,
    -Tr.ALIGN_BACK, math.max(in_c, own_c or 0) + 24)
  h.dbg = ("signal %d, with reports %d, best k %s at %.2f"):format(any, most, tostring(k), corr or -2)
  if k and corr >= Tr.ALIGN_MIN then h.k, h.corr = k, corr end
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
local where_cache = {}   -- guid -> { t, where }: TP.status, asked once a second

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
    -- why there's no tap: no probes, or this plugin isn't between them
    -- (or runs in parallel there, which a tap can't measure); otherwise
    -- the tap just hasn't been laid yet
    if not TP.has_probes(track) then return nil, "needs TS_TrackProbe" end
    -- walking the chain every frame is wasteful: asked once a second
    local now = reaper.time_precise()
    local hit = where_cache[fx.guid]
    if not hit or now - hit.t > 1 then
      hit = { t = now, where = TP.status(track, fx.guid) }
      where_cache[fx.guid] = hit
    end
    local where = hit.where
    if where == "outside" then return nil, "outside the probes" end
    if where == "parallel" then return nil, "in parallel", "can't be measured" end
    return nil, "connecting\u{2026}"
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

  -- the plugin's own latency, in columns: its input is drawn that much
  -- later, on the output it became
  local d = tw[ti]
  local after = latency_to_probe(track, fx, probe, false)
  local own = math.max(0, latency_to_probe(track, fx, probe, true) - after)
  local own_c = math.floor(own / tw.slice + 0.5)
  -- a reporting plugin's reports, laid onto the clock (late by the plugins
  -- after it), then drawn at the offset where they match what the tap sees
  -- the input, held back to sit on the output (found from the audio)
  local e = ins[fx.guid]
  if not e then e = {}; ins[fx.guid] = e end
  Tr.align_input(e, d, own_c, tw.cur)
  local in_c = e.k or 0
  -- the probe's tap holds the input back by this too (its measurement
  -- compares the two): what was found, not what the plugin reports
  if e.stable then TP.set_measured_lag(fx.guid, math.floor(math.max(0, e.stable) * tw.slice + 0.5)) end
  local gsrc, gk, rep_last = d.gr, 0, nil
  if not est then
    rep_record(fx.guid, (tw.cur + math.floor(after / tw.slice + 0.5)) % TW_COLS, gr or 0)
    local h = reps[fx.guid]
    Tr.realign(h, d, in_c, tw.cur, nil, own_c)
    gsrc, gk, rep_last = h.gr, h.k or own_c, h.c
  end
  -- what the lining up found, for dev/TS_CV_LatencyProbe.lua (once a
  -- second, and only while it has asked: ExtState align_debug)
  local dbg_t = (Tr.dbg_t or {})[fx.guid] or 0
  local now_ = reaper.time_precise()
  if now_ - dbg_t > 1 and reaper.GetExtState("TS_ChannelView", "align_debug") == "1" then
    Tr.dbg_t = Tr.dbg_t or {}; Tr.dbg_t[fx.guid] = now_
    local h = reps[fx.guid]
    local who = (select(2, reaper.get_action_context()) or ""):match("[^/\\]+$") or "?"
    reaper.SetExtState("TS_ChannelView", "align " .. fx.guid,
      ("by %s, live %s, tap %s\n        "):format(who, tostring(tw.live), tostring(ti)) ..
      ("slice=%d own=%d after=%d in_k=%s in_corr=%s gr_k=%s gr_corr=%s est=%s\n        input: %s\n        reduction: %s"):format(
        tw.slice, own, after, tostring(e.k), e.corr and ("%.2f"):format(e.corr) or "-",
        tostring(h and h.k), (h and h.corr) and ("%.2f"):format(h.corr) or "-", tostring(est),
        (e.dbg or "no signal yet") .. (e.quiet and "  (quiet now)" or "") .. "  [" .. (e.peaks or "-") .. "]",
        ((h and h.dbg) or "no signal yet") .. ((h and h.quiet) and "  (quiet now)" or "")), false)
  end

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
      local a, b, i = d.mn[c] or 0, d.mx[c] or 0, d.ip[(c - in_c) % TW_COLS] or 0
      if a < mn then mn = a end
      if b > mx then mx = b end
      if i > ip then ip = i end
      local gi = (c - gk) % TW_COLS
      local v = gsrc[gi]
      if v and rep_last and ((rep_last - gi) % TW_COLS) >= TW_COLS / 2 then v = nil end
      if v and (not g or v > g) then g = v end
    end
    out.mn[px + 1], out.mx[px + 1], out.ip[px + 1], out.g[px + 1] = mn, mx, ip, g
  end
  return out
end

return Tr
