-- @noindex
-- Not a package of its own: installed by TS_ChannelView.lua's @provides.
--[[
  TS_CV_ReaEQ.lua -- everything about ReaEQ that isn't drawing.

  Two jobs, kept apart from TS_CV_EQPanel.lua's ImGui/interaction code so
  both halves stay testable: reading and writing ReaEQ's own bands through
  REAPER's EQ-specific API, and computing the filter curve those bands
  produce. The curve math has no REAPER dependency at all -- it is plain
  arithmetic on numbers this file was handed -- so it can be, and is,
  exercised by a standalone harness the same way P.layout's fader math
  was, with no REAPER instance involved.

  THE API SURFACE (reaper-sdk's reaper_plugin_functions.h; the
  reascripthelp.html page is a stale mirror -- it still says "0=lhipass"
  instead of the current "0=hipass"):

    TrackFX_GetEQ(track, instantiate)              -> fx index of ReaEQ
    TrackFX_GetEQParam(track, fx, paramidx)         -> ok, bandtype, bandidx,
                                                        paramtype, normval
    TrackFX_GetEQBandEnabled(track, fx, bandtype, bandidx) -> bool
    TrackFX_SetEQBandEnabled(track, fx, bandtype, bandidx, enable)
    TrackFX_SetEQParam(track, fx, bandtype, bandidx, paramtype, val, isnorm)

    bandtype:  -1=master gain, 0=hipass, 1=loshelf, 2=band, 3=notch,
               4=hishelf, 5=lopass, 6=bandpass, 7=parallel bandpass
    paramtype: 0=freq, 1=gain, 2=Q (ignored for master gain)
    bandidx:   0=first band matching bandtype, 1=2nd, etc -- bands are
               addressed PER TYPE, not in one global list.

  GetEQParam's own paramidx IS the plugin's ordinary flat FX-parameter
  index -- the same space TrackFX_GetFormattedParamValue already uses
  elsewhere in this codebase. THE GENERIC TrackFX_GetParam IS NOT usable
  for real Hz/dB/Q values here: REAPER's own built-in effects (ReaEQ
  among them) don't implement TrackFX_GetParam's real-value/min/max
  distinction the way third-party plugins do -- it hands back the same
  0..1 normalized number GetParamNormalized would, which would clamp
  straight down to the 20Hz floor of this canvas's frequency range
  regardless of the band's actual position. RQ.read below gets real
  units the way the rest of this codebase already does for every
  ordinary knob (U.fmt_value): off ReaEQ's own formatted string, via
  TrackFX_GetFormattedParamValue, which native effects DO implement
  correctly since it's their own display text.

  TWO THINGS UNDOCUMENTED, because REAPER exposes no "add band" or
  "remove band" call and the public docs don't say what SetEQParam does
  to a (bandtype, bandidx) pair that isn't there yet:

  ADDING A BAND. There is no separate insert function anywhere in the EQ
  API, so writing freq/gain/Q for a bandidx one past the current count of
  that type is the only candidate mechanism scripting has at all --
  RQ.add_band does exactly that, and then RE-READS the band to confirm it
  actually took, rather than assuming success; the panel surfaces it
  plainly if it doesn't.

  REMOVING A BAND. Scripting can only disable one (SetEQBandEnabled), never
  delete it. So "remove" and "change this node's type" (which has no
  in-place API either -- band TYPE isn't a settable EQ param, only
  SetNamedConfigParm string keys nobody has documented the numbering for)
  both work the same way here: disable the old band, add a fresh one. The
  old one stays in ReaEQ's own band list, disabled, rather than vanishing --
  a real seam, not a bug, until REAPER exposes true removal.
--]]

local C = require("TS_CV_Config")

local RQ = {}

RQ.BAND_TYPE = {
  MASTER    = -1,
  HIPASS    = 0,
  LOSHELF   = 1,
  BAND      = 2,
  NOTCH     = 3,
  HISHELF   = 4,
  LOPASS    = 5,
  BANDPASS  = 6,
  PBANDPASS = 7,
}

RQ.TYPE_NAME = {
  [0] = "High pass", [1] = "Low shelf",  [2] = "Bell",
  [3] = "Notch",      [4] = "High shelf", [5] = "Low pass",
  [6] = "Band pass",  [7] = "Band pass (parallel)",
}

-- The types offered on the "change type" menu and inferred from where you
-- double-click. Bandpass/parallel-bandpass exist in the API (and stay
-- readable/drawable if a project already has one) but aren't part of the
-- five supported types, so they're left off both.
RQ.MENU_TYPES = { 0, 1, 2, 3, 4, 5 }

-- A sane starting Q per type, used only when a node is first created.
RQ.DEFAULT_Q = {
  [0] = 0.7071, [1] = 0.7071, [2] = 1.0,
  [3] = 4.0,    [4] = 0.7071, [5] = 0.7071,
  [6] = 1.0,    [7] = 1.0,
}

function RQ.is_eq(key) return key == "ReaEQ" end

-- ---------------------------------------------------------------------
-- reading real units off ReaEQ's own formatted text -- see the file
-- header for why TrackFX_GetParam can't be trusted for this. A leading
-- number, optionally signed, optionally with a "k" multiplier before
-- "Hz" for the frequency case ("125 Hz", "1.20 kHz", "+3.50 dB", "0.71").
--
-- The sign is read by WHAT'S THERE, not by matching a literal "-": every
-- character between the start of the string and the first digit is
-- captured as `pre`, and anything in it other than "+" (or nothing at
-- all) reads as negative. A plain ASCII hyphen falls out of that the same
-- as "+"/nothing falls out positive -- but so does a true Unicode minus
-- sign (U+2212) or any other dash a locale/build might format negative
-- numbers with, none of which match a literal "%-" in a Lua pattern
-- (patterns work byte-by-byte, and those are multi-byte UTF-8). This
-- matters because gain cuts read back through here (see RQ.read), so a
-- build that formats a negative dB value with one of those glyphs must
-- still parse as negative rather than silently falling back to 0.
--
-- "-inf dB" IS A REAL, LEGITIMATE READING, not a formatting glitch: it is
-- what ReaEQ's own gain slider shows once a band's gain has been driven
-- all the way to its floor. "inf" has no digits at all, so it is checked
-- before the digit-anchored match below, using the same "read the sign
-- from what's there" logic -- a fully-cut band must read back as -inf,
-- not silently fall back to 0 and be drawn/treated as sitting at 0dB.
local function parse_num(s)
  if not s then return nil end
  local pre_inf, inf = s:lower():match("^%s*(%S-)%s*(inf)")
  if inf then
    return (pre_inf ~= "" and pre_inf ~= "+") and -math.huge or math.huge
  end
  local pre, numstr = s:match("^%s*(%S-)%s*(%d*%.?%d+)")
  if not numstr then return nil end
  local n = tonumber(numstr)
  if not n then return nil end
  if pre ~= "" and pre ~= "+" then n = -n end
  return n
end

local function parse_freq(s)
  local n = parse_num(s)
  if not n then return nil end
  if s:lower():find("khz", 1, true) then return n * 1000 end
  return n
end

RQ.parse_num  = parse_num   -- exposed for the standalone math harness
RQ.parse_freq = parse_freq

-- ---------------------------------------------------------------------
-- reading
-- ---------------------------------------------------------------------

-- Every band on this ReaEQ instance, plus the master-gain control if the
-- instance exposes one. Order is whatever GetEQParam's own paramidx order
-- yields, which is stable frame to frame as long as nothing is added or
-- removed -- good enough to key a band's on-screen colour off its
-- position in this list.
--
-- Returns bands (array) and master (a { val, pidx } table, or nil if this
-- FX doesn't publish one).
function RQ.read(track, addr)
  local by_key, order, master = {}, {}, nil

  local i = 0
  while i < 1024 do   -- generous; ReaEQ never has remotely this many params
    local ok, bandtype, bandidx, paramtype, normval = reaper.TrackFX_GetEQParam(track, addr, i)
    if not ok then break end

    local _, formatted = reaper.TrackFX_GetFormattedParamValue(track, addr, i, "")

    if bandtype == RQ.BAND_TYPE.MASTER then
      master = { val = parse_num(formatted) or 0, norm = normval, pidx = i }
    else
      local bkey = bandtype .. ":" .. bandidx
      local b = by_key[bkey]
      if not b then
        b = { bandtype = bandtype, bandidx = bandidx }
        by_key[bkey] = b
        order[#order + 1] = bkey
      end
      if paramtype == 0 then
        -- Fallback if the string ever fails to parse: place it from the
        -- normalized value on this canvas's own log scale. Not
        -- necessarily where ReaEQ's internal curve would put it, but a
        -- far better failure mode than silently pinning to 20Hz.
        b.freq = parse_freq(formatted) or RQ.frac_to_freq(normval, C.EQ_FREQ_LO, C.EQ_FREQ_HI)
        b.freq_norm, b.freq_pidx = normval, i
      elseif paramtype == 1 then
        -- b.gain can legitimately come back as -math.huge (ReaEQ's own
        -- "-inf dB" reading -- see parse_num) when a band's gain sits at
        -- its floor. That's the TRUE value, not a sentinel to catch and
        -- discard: eq_fix_step's search compares it against a real dB
        -- target with plain arithmetic, which is exactly as well-behaved
        -- with an infinity on one side as with any other number.
        -- Anything that turns this into a screen pixel (EQP.draw's node
        -- circle) clamps it there instead, the same way the curve trace
        -- already clamps every sampled point before calling y_of.
        b.gain = parse_num(formatted) or 0
        b.gain_norm, b.gain_pidx = normval, i
      elseif paramtype == 2 then
        b.q = parse_num(formatted) or 1.0
        b.q_norm, b.q_pidx = normval, i
      end
    end
    i = i + 1
  end

  local bands = {}
  for _, bkey in ipairs(order) do
    local b = by_key[bkey]
    b.enabled = reaper.TrackFX_GetEQBandEnabled(track, addr, b.bandtype, b.bandidx)
    bands[#bands + 1] = b
  end
  return bands, master
end

-- How many bands of `bandtype` already exist -- the next one lands at
-- this count, per GetEQParam's own "0=first matching, 1=2nd..." scheme.
function RQ.next_bandidx(bands, bandtype)
  local n = 0
  for _, b in ipairs(bands) do
    if b.bandtype == bandtype then n = n + 1 end
  end
  return n
end

-- ---------------------------------------------------------------------
-- writing
-- ---------------------------------------------------------------------
-- Every write goes through SetEQParam with isnorm=false, i.e. real units
-- (Hz, dB, Q) rather than the 0..1 normalized space GetEQParam reads in --
-- REAPER's own SDK comment doesn't spell out what isnorm=false means, but
-- it is the standard meaning of that flag everywhere else it appears in
-- the API, and using it means never having to reverse-engineer whatever
-- shaped-slider curve ReaEQ's frequency knob uses internally.

-- Clamped to fixed, generous ranges rather than a per-band min/max read
-- off the API -- see the file header on why that read can't be trusted
-- for a native effect. These exist only to keep a wild drag from sending
-- a value somewhere pathological (Q of 0, say), not to mirror ReaEQ's own
-- exact limits. Exposed on RQ too -- EQP.draw's creation-time binary
-- search (see its own header) searches within these same bounds.
RQ.Q_MIN, RQ.Q_MAX = 0.05, 20
RQ.GAIN_CLAMP = 30
local Q_MIN, Q_MAX = RQ.Q_MIN, RQ.Q_MAX
local GAIN_CLAMP = RQ.GAIN_CLAMP

function RQ.set_freq(track, addr, band, hz)
  hz = math.max(C.EQ_FREQ_LO, math.min(C.EQ_FREQ_HI, hz))
  reaper.TrackFX_SetEQParam(track, addr, band.bandtype, band.bandidx, 0, hz, false)
  band.freq = hz
end

-- DRAGGING AN EXISTING NODE. A raw isnorm=false write for gain or Q sends
-- a cut straight to -inf and a boost straight to this file's own
-- GAIN_CLAMP ceiling, not a scaled-wrong version of the target --
-- isnorm=true (normalized 0..1 space) is the write that actually lands
-- where asked (see RQ.eq_search_direction's header and EQP.draw's
-- eq_fix_step for the same fact applied at band-creation time). But a
-- drag can't afford eq_fix_step's multi-frame probe-then-bisect -- that's
-- built to tolerate looking wrong for up to a couple dozen frames, which
-- reads as a visible stall under a live drag, not a settle.
--
-- So dragging uses a plain secant method instead (RQ.secant_step below,
-- pure and unit-tested on its own): every frame already hands this file
-- a fresh (normalized, real) reading for free -- band.gain_norm/band.gain
-- and band.q_norm/band.q, off the exact same trusted read RQ.read does
-- regardless of whether anything is being dragged -- so two consecutive
-- frames' worth of "what did the last write actually produce" is a live,
-- continuously-refreshed local slope, not a guessed formula or a
-- deliberately-probed one. One secant step per frame, clamped to [0,1],
-- self-corrects as the drag moves through different parts of a curve
-- nobody has (or needs) a closed form for. `state` is a small table the
-- caller owns for the lifetime of one drag gesture (EQP.draw keys one
-- per band so switching bands doesn't reuse a stale slope).
function RQ.secant_step(prev_norm, prev_real, cur_norm, cur_real, target, lo, hi)
  local function finite(x) return x ~= nil and x == x and x ~= math.huge and x ~= -math.huge end
  if not prev_norm or cur_norm == prev_norm or not finite(prev_real) or not finite(cur_real) then
    return cur_norm   -- no prior sample, no usable slope yet, or a band pinned at
                       -- its floor/ceiling right now -- hold position, the next
                       -- frame tries again
  end
  local dr = cur_real - prev_real
  if dr == 0 then return cur_norm end
  local slope = dr / (cur_norm - prev_norm)
  local next_norm = cur_norm + (target - cur_real) / slope
  if next_norm < lo then next_norm = lo end
  if next_norm > hi then next_norm = hi end
  return next_norm
end

-- Bootstrap nudge used the first time a gesture has no usable two-point
-- slope yet (see below) -- small enough to be an imperceptible single-frame
-- blip, big enough that the read-back is guaranteed to differ from what
-- came before so the NEXT frame has a real secant slope to work with.
local BOOTSTRAP_PROBE = 0.03

function RQ.set_gain(track, addr, band, db, state)
  db = math.max(-GAIN_CLAMP, math.min(GAIN_CLAMP, db))
  local cur_norm, cur_real = band.gain_norm, band.gain
  if not (cur_norm and cur_real) then return end
  local next_norm
  if state.prev_norm and cur_norm ~= state.prev_norm then
    next_norm = RQ.secant_step(state.prev_norm, state.prev_real, cur_norm, cur_real, db, 0, 1)
  else
    -- No usable slope yet: either this is the first frame of a fresh
    -- gesture (state.prev_norm is nil), or the previous write didn't
    -- move the read-back value at all (cur_norm == prev_norm). Writing
    -- nothing in that case would mean a second, distinct sample never
    -- arrives, permanently stalling the drag. Take one small step toward
    -- the target instead so next frame has two real samples to build a
    -- slope from.
    local dir = (db >= cur_real) and 1 or -1
    next_norm = math.max(0, math.min(1, cur_norm + dir * BOOTSTRAP_PROBE))
  end
  if next_norm ~= cur_norm then
    reaper.TrackFX_SetEQParam(track, addr, band.bandtype, band.bandidx, 1, next_norm, true)
  end
  state.prev_norm, state.prev_real = cur_norm, cur_real
end

function RQ.set_q(track, addr, band, q, state)
  q = math.max(Q_MIN, math.min(Q_MAX, q))
  local cur_norm, cur_real = band.q_norm, band.q
  if not (cur_norm and cur_real) then return end
  local next_norm
  if state.prev_norm and cur_norm ~= state.prev_norm then
    next_norm = RQ.secant_step(state.prev_norm, state.prev_real, cur_norm, cur_real, q, 0, 1)
  else
    -- See RQ.set_gain's comment: same stall, same bootstrap fix.
    local dir = (q >= cur_real) and 1 or -1
    next_norm = math.max(0, math.min(1, cur_norm + dir * BOOTSTRAP_PROBE))
  end
  if next_norm ~= cur_norm then
    reaper.TrackFX_SetEQParam(track, addr, band.bandtype, band.bandidx, 2, next_norm, true)
  end
  state.prev_norm, state.prev_real = cur_norm, cur_real
end

function RQ.set_enabled(track, addr, band, on)
  reaper.TrackFX_SetEQBandEnabled(track, addr, band.bandtype, band.bandidx, on)
  band.enabled = on
end

-- ---------------------------------------------------------------------
-- gain/Q creation-time binary search -- pure math only, pulled out on its
-- own so it can be checked by the standalone harness with no REAPER
-- instance involved. See EQP.draw's eq_fix_step for what drives this and
-- why: a straight SetEQParam real-value write for gain or Q, on a band
-- this file just created, doesn't reliably mean what the read path
-- (which IS trusted -- see RQ.read's own header) reports back. Gain
-- overshoots a boost and clamps a cut flat to 0dB; Q comes out inverted.
-- Both are consistent, monotonic mismatches rather than noise, which is
-- enough to correct for WITHOUT knowing what the true relationship is:
-- probe the two search bounds once to learn which direction increasing
-- the written value actually moves the read-back value, then bisect.
-- ---------------------------------------------------------------------

-- True if a LARGER real-value input is observed to produce a LARGER
-- read-back value (the two probes at the search bounds), false if it's
-- the other way round.
function RQ.eq_search_direction(lo, lo_read, hi, hi_read)
  return hi_read > lo_read
end

-- One bisection step: given the current (lo, hi) in OUR OWN units, the
-- established `direction` (see above), and the most recently written
-- value plus what it read back, returns the narrowed (lo, hi) bracketing
-- `target`. Works whichever way `direction` goes -- it never assumes
-- increasing the input increases the reading, only that SOME direction
-- does, consistently.
function RQ.eq_search_narrow(lo, hi, direction, written, read, target)
  local higher_input_needed = (direction == (read < target))
  if higher_input_needed then return written, hi end
  return lo, written
end

-- Creates a band of `bandtype` at (freq, gain, q). See the file header's
-- "ADDING A BAND" note: this is the only mechanism scripting has for
-- creating a band at all, and it relies on undocumented API behavior.
-- ENABLED FIRST, THEN freq/gain/Q: a (bandtype, bandidx) pair that
-- doesn't exist yet may only actually come into being on the enable call
-- -- writing its params first, before that slot exists, is a plausible
-- way for a freshly added band to land at whatever ReaEQ defaults a new
-- band of that type to rather than where it was clicked.
--
-- GAIN AND Q ARE BEST-EFFORT ONLY HERE. freq (right above) reliably lands
-- where asked with a straight real-Hz write through SetEQParam's
-- isnorm=false path. Gain and Q do not: a boost overshoots well past what
-- was asked for, and a cut drives the band all the way to its floor --
-- -inf dB, ReaEQ's own genuine reading, not a "0dB clamp" (an unparsed
-- "-inf" falling back to 0 would be this file's own read path failing --
-- see parse_num); Q comes out inverted (a narrow-intending high Q
-- produces a wide band). Both are consistent with SetEQParam's
-- isnorm=false write for these two paramtypes actually landing in
-- normalized (0..1) space on this native effect regardless of the flag --
-- unlike freq, which genuinely takes real Hz -- so a raw dB/Q number gets
-- clamped into [0,1] and mapped back through whatever curve ReaEQ's own
-- normalized<->real conversion uses for that parameter (evidently one
-- where 0.0 normalized is -inf dB, not 0dB).
--
-- Correcting for this needs more than a single linear extrapolation: the
-- relationship isn't guaranteed linear across the whole range, and a
-- just-enabled band's read-back (via RQ.read, REAPER's flat generic
-- parameter list) doesn't catch up within the same script tick the way
-- the direct bandtype+bandidx calls do. The actual correction lives in
-- EQP.draw: a real binary search, deferred across several UI frames so
-- every read happens well after that flat list has caught up (the same
-- reason freq already reads back correctly one frame after creation, not
-- the same frame), using RQ.eq_search_direction / RQ.eq_search_narrow
-- above for the pure part of the arithmetic.
-- Returns ok, bandtype, bandidx: ok is true only once GetEQBandEnabled
-- reads the new band back as present, not merely "the calls didn't error".
function RQ.add_band(track, addr, bandtype, freq, gain, q)
  local bands = RQ.read(track, addr)
  local bandidx = RQ.next_bandidx(bands, bandtype)

  reaper.TrackFX_SetEQBandEnabled(track, addr, bandtype, bandidx, true)
  reaper.TrackFX_SetEQParam(track, addr, bandtype, bandidx, 0, freq, false)
  reaper.TrackFX_SetEQParam(track, addr, bandtype, bandidx, 1, gain or 0, false)
  reaper.TrackFX_SetEQParam(track, addr, bandtype, bandidx, 2,
    q or RQ.DEFAULT_Q[bandtype] or 1.0, false)

  local ok = reaper.TrackFX_GetEQBandEnabled(track, addr, bandtype, bandidx)
  return ok, bandtype, bandidx
end

-- "Change type" / "remove", both built the same way -- see the file
-- header. Disables `band` and, unless `bandtype` is nil (a pure remove),
-- adds a replacement of the new type at the same freq/gain/Q.
function RQ.replace_band(track, addr, band, new_bandtype)
  RQ.set_enabled(track, addr, band, false)
  if not new_bandtype then return true end
  return RQ.add_band(track, addr, new_bandtype, band.freq,
    (new_bandtype == RQ.BAND_TYPE.HIPASS or new_bandtype == RQ.BAND_TYPE.LOPASS
      or new_bandtype == RQ.BAND_TYPE.NOTCH) and 0 or (band.gain or 0),
    RQ.DEFAULT_Q[new_bandtype])
end

-- ---------------------------------------------------------------------
-- position <-> value mapping (log frequency, linear gain)
-- ---------------------------------------------------------------------

function RQ.freq_to_frac(freq, lo, hi)
  freq = math.max(lo, math.min(hi, freq))
  return math.log(freq / lo) / math.log(hi / lo)
end

function RQ.frac_to_freq(frac, lo, hi)
  frac = math.max(0, math.min(1, frac))
  return lo * (hi / lo) ^ frac
end

-- frac 0 at the TOP of the canvas (+range dB), 1 at the bottom (-range).
function RQ.gain_to_frac(db, range)
  return 0.5 - (db / (2 * range))
end

function RQ.frac_to_gain(frac, range)
  return range - frac * 2 * range
end

-- Where a freshly double-clicked node should land: extremes are a pass
-- filter, a little in from there is a shelf, and the broad middle -- low
-- mids to high mids -- is a bell. Four thresholds, five zones; kept as
-- plain numbers rather than buried in the drawing code so they're the
-- one place to retune.
function RQ.infer_type(freq_hz)
  if freq_hz < C.EQ_HP_MAX      then return RQ.BAND_TYPE.HIPASS  end
  if freq_hz < C.EQ_LOSHELF_MAX then return RQ.BAND_TYPE.LOSHELF end
  if freq_hz < C.EQ_HISHELF_MIN then return RQ.BAND_TYPE.BAND    end
  if freq_hz < C.EQ_LP_MIN      then return RQ.BAND_TYPE.HISHELF end
  return RQ.BAND_TYPE.LOPASS
end

-- ---------------------------------------------------------------------
-- curve math -- standard RBJ Audio EQ Cookbook biquads. This is display
-- only: REAPER doesn't expose ReaEQ's actual internal DSP, so the curve
-- is a well-established textbook approximation of it, not a readout of
-- what ReaEQ itself is computing.
-- ---------------------------------------------------------------------

-- math.log10 was removed as a separate function from Lua's standard
-- library in 5.2+, and REAPER's embedded Lua doesn't carry the 5.1
-- compatibility shim for it. math.log(x) alone, base e, is the one form
-- guaranteed to exist everywhere, so log10 is built from that once here
-- instead.
local LOG10 = math.log(10)

local function coeffs(bandtype, freq, gain_db, q, sr)
  freq = math.max(1, math.min(sr * 0.499, freq))
  q = math.max(0.05, q or 1.0)
  local w0 = 2 * math.pi * freq / sr
  local cw, sw = math.cos(w0), math.sin(w0)
  -- The RBJ cookbook's own alpha, sw/(2*q), is the standard convention
  -- where a bigger Q means a NARROWER band -- but ReaEQ's own "Q"
  -- parameter is inverted from that convention: in ReaEQ, a HIGHER Q
  -- value produces a WIDER band, not a narrower one. Feeding 1/q into the
  -- textbook formula in place of q accounts for that inversion
  -- (sw/(2*(1/q)) == sw*q/2) without touching what "q" means anywhere
  -- else in this file -- still the real value read straight from ReaEQ,
  -- still what eq_fix_step's search targets, still what the wheel
  -- handler scales by.
  local alpha = sw * q / 2
  local A = 10 ^ ((gain_db or 0) / 40)
  local BT = RQ.BAND_TYPE
  local b0, b1, b2, a0, a1, a2

  if bandtype == BT.HIPASS then
    b0, b1, b2 = (1 + cw) / 2, -(1 + cw), (1 + cw) / 2
    a0, a1, a2 = 1 + alpha, -2 * cw, 1 - alpha
  elseif bandtype == BT.LOPASS then
    b0, b1, b2 = (1 - cw) / 2, 1 - cw, (1 - cw) / 2
    a0, a1, a2 = 1 + alpha, -2 * cw, 1 - alpha
  elseif bandtype == BT.NOTCH then
    b0, b1, b2 = 1, -2 * cw, 1
    a0, a1, a2 = 1 + alpha, -2 * cw, 1 - alpha
  elseif bandtype == BT.BANDPASS or bandtype == BT.PBANDPASS then
    b0, b1, b2 = alpha, 0, -alpha
    a0, a1, a2 = 1 + alpha, -2 * cw, 1 - alpha
  elseif bandtype == BT.LOSHELF or bandtype == BT.HISHELF then
    -- Shelves don't take the plain peaking alpha above at all in the
    -- textbook cookbook -- they have their own formula for how sharply the
    -- transition overshoots, and that formula has a real mathematical
    -- floor: past a certain point the term under the square root bottoms
    -- out at 0 (the gentlest possible shelf, no overshoot) and cannot get
    -- any gentler no matter how far past that point the input goes. This
    -- matches ReaEQ's own display, where a shelf's shape stops changing
    -- once Q is driven low enough. Reusing the plain peaking alpha here
    -- has no such floor and keeps flattening indefinitely, which does not
    -- match ReaEQ's behavior.
    --
    -- The same q -> 1/q substitution as the peaking alpha above still
    -- applies here (same file, same "q" meaning throughout -- still the
    -- real value read straight from ReaEQ) -- substituted into the
    -- cookbook's own Q-based shelf alpha, sw/2 * sqrt((A+1/A)*(1/Q-1)+2),
    -- with Q = 1/q that's sw/2 * sqrt((A+1/A)*(q-1)+2).
    local inner = (A + 1 / A) * (q - 1) + 2
    local shelf_alpha = sw / 2 * math.sqrt(math.max(0, inner))
    local sqA = math.sqrt(A)
    if bandtype == BT.LOSHELF then
      b0 =      A * ((A + 1) - (A - 1) * cw + 2 * sqA * shelf_alpha)
      b1 =  2 * A * ((A - 1) - (A + 1) * cw)
      b2 =      A * ((A + 1) - (A - 1) * cw - 2 * sqA * shelf_alpha)
      a0 =           (A + 1) + (A - 1) * cw + 2 * sqA * shelf_alpha
      a1 =     -2 * ((A - 1) + (A + 1) * cw)
      a2 =           (A + 1) + (A - 1) * cw - 2 * sqA * shelf_alpha
    else
      b0 =      A * ((A + 1) + (A - 1) * cw + 2 * sqA * shelf_alpha)
      b1 = -2 * A * ((A - 1) + (A + 1) * cw)
      b2 =      A * ((A + 1) + (A - 1) * cw - 2 * sqA * shelf_alpha)
      a0 =           (A + 1) - (A - 1) * cw + 2 * sqA * shelf_alpha
      a1 =      2 * ((A - 1) - (A + 1) * cw)
      a2 =           (A + 1) - (A - 1) * cw - 2 * sqA * shelf_alpha
    end
  else -- BT.BAND -- peaking/bell, and the fallback for anything unknown
    b0, b1, b2 = 1 + alpha * A, -2 * cw, 1 - alpha * A
    a0, a1, a2 = 1 + alpha / A, -2 * cw, 1 - alpha / A
  end

  return b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0
end

-- One band's own magnitude response, in dB, at frequency f. A disabled
-- band contributes nothing -- 0 dB, not omitted -- so callers that sum
-- straight across every band never have to filter first.
function RQ.band_db(band, f, sr)
  if not band.enabled then return 0 end
  local b0, b1, b2, a1, a2 = coeffs(band.bandtype, band.freq, band.gain, band.q, sr)
  local w = 2 * math.pi * f / sr
  local c1, s1 = math.cos(w), math.sin(w)
  local c2, s2 = math.cos(2 * w), math.sin(2 * w)
  local nre, nim = b0 + b1 * c1 + b2 * c2, -(b1 * s1 + b2 * s2)
  local dre, dim = 1 + a1 * c1 + a2 * c2, -(a1 * s1 + a2 * s2)
  local num = math.sqrt(nre * nre + nim * nim)
  local den = math.max(1e-12, math.sqrt(dre * dre + dim * dim))
  return 20 * math.log(math.max(1e-9, num / den)) / LOG10
end

-- The combined response of every band plus the master gain, in dB, at f.
function RQ.total_db(bands, master, f, sr)
  local db = master and master.val or 0
  for _, b in ipairs(bands) do
    db = db + RQ.band_db(b, f, sr)
  end
  return db
end

return RQ
