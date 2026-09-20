--========================================================
-- @noindex
-- @title TS_TA_Mask
-- @description Track Analyser -- perceptual masking between two tracks
-- @author Tim Shadgett (with Claude)
-- @version 1.0.0
-- MIT licence -- see LICENSE in the TS-ReaScripts repository.
--========================================================
--
-- Not a script you run. TS_TrackAnalyser requires this.
--
-- WHAT THIS IS FOR
--   Two tracks each publish a 256-point log-spaced spectrum. This turns
--   that pair into a per-band answer to one question: where is the track
--   you are looking at being masked by the other one?
--
--   Nothing here touches REAPER. It is arithmetic on two arrays of
--   decibels, which means it can be tested on synthetic spectra with
--   known answers instead of by staring at a screen.
--
-- THE MODEL, AND WHY EACH PART IS THERE
--
--   1  ERB BANDS.  Comparing raw FFT bands says "both have energy at
--      3,412 Hz", which the ear does not care about. The ear integrates
--      over critical bands, so energy is summed into equivalent
--      rectangular bands first -- about 41 of them from 20 Hz to 20 kHz.
--      Summing is done in POWER, not in decibels.
--
--   2  SPREADING.  A band does not only mask itself. Masking spreads, and
--      asymmetrically: Schroeder's function is about 4 dB down one Bark
--      ABOVE the masker and 8 dB down one Bark below, 12 up against 28
--      down at two Bark. Upward spread is the dominant effect in a mix --
--      it is why a loud bass eats the body of a vocal it shares no
--      critical band with. A same-band-only rule cannot see that
--      collision at all, which is the main thing separating this from the
--      "both have energy here" overlay.
--
--      The width is adjustable, and at width 0 the model collapses to
--      same-band-only on purpose -- that is roughly what the commercial
--      tools describe themselves as doing, so the two can be compared on
--      the same material rather than argued about.
--
--   3  A MASKING OFFSET.  The spread excitation is not itself a
--      threshold; the threshold sits some way below it, and how far
--      depends on how tone-like the masker is. Rather than infer
--      tonality, this is one number you turn until the overlay agrees
--      with your ears.
--
--   4  AN AUDIBILITY GATE, shaped by the threshold of hearing. Without
--      it the bottom and top of the range flag permanently, because down
--      there everything is below everything else and none of it is
--      audible anyway. This is what keeps the red to places worth
--      looking at.
--
-- WHAT IT DOES NOT MODEL
--   Temporal masking -- this compares running averages, so a kick
--   masking a vocal 20 ms later is invisible to it. Absolute level: the
--   gate is in dBFS with a hearing-threshold SHAPE applied, not in SPL,
--   because nothing here knows your monitoring level.
--========================================================

local M = {}

----------------------------------------------------------
-- perceptual scales
----------------------------------------------------------

-- Glasberg & Moore ERB-rate. 20 Hz to 20 kHz spans 40.9 of these.
local function erbRate(f)
  return 21.4 * math.log(4.37 * f / 1000 + 1, 10)
end

local function erbRateInv(e)
  return (10 ^ (e / 21.4) - 1) * 1000 / 4.37
end

-- Traunmuller's Bark. The spreading function is defined in Bark, so band
-- centres are carried in both scales rather than converted per lookup.
local function barkOf(f)
  return 26.81 * f / (1960 + f) - 0.53
end

-- Terhardt's approximation to the threshold of hearing, dB SPL. Only its
-- SHAPE is used -- see the gate below -- so the absolute values do not
-- have to correspond to anything in your room.
local function athOf(f)
  local k = f / 1000
  return 3.64 * k ^ -0.8
       - 6.5 * math.exp(-0.6 * (k - 3.3) ^ 2)
       + 0.001 * k ^ 4
end

-- Schroeder's spreading function: dB relative to the masker, dz in Bark,
-- positive dz meaning ABOVE the masker in frequency.
local function schroeder(dz)
  local x = dz + 0.474
  return 15.81 + 7.5 * x - 17.5 * math.sqrt(1 + x * x)
end

----------------------------------------------------------
-- the grid
--
-- Built once for a given source-band layout and cached. Everything that
-- needs a logarithm happens here, so the per-update path has none.
----------------------------------------------------------

local gridCache = nil

-- nSrc      how many bands the probes publish (256)
-- loHz/hiHz the range those bands cover (20 .. 20000)
function M.grid(nSrc, loHz, hiHz)
  if gridCache and gridCache.nSrc == nSrc
     and gridCache.lo == loHz and gridCache.hi == hiHz then
    return gridCache
  end

  local g = { nSrc = nSrc, lo = loHz, hi = hiHz }
  local eLo, eHi = erbRate(loHz), erbRate(hiHz)
  g.n = math.max(4, math.floor(eHi - eLo + 0.5))   -- one ERB per band

  -- Band centres, in Hz and in Bark, plus the hearing-threshold shape
  -- normalised so its most sensitive point is zero.
  g.hz, g.bark, g.ath = {}, {}, {}
  local athMin = math.huge
  for b = 1, g.n do
    local e = eLo + (b - 0.5) * (eHi - eLo) / g.n
    local f = erbRateInv(e)
    g.hz[b]   = f
    g.bark[b] = barkOf(f)
    g.ath[b]  = athOf(f)
    if g.ath[b] < athMin then athMin = g.ath[b] end
  end
  for b = 1, g.n do g.ath[b] = g.ath[b] - athMin end

  -- Which ERB band each source band belongs to, and the reverse lookup
  -- the drawing needs. A source band lands in exactly one ERB band, so
  -- summing is a single pass with no weights to get wrong.
  g.owner = {}
  local ratio = math.log(hiHz / loHz)
  for i = 0, nSrc - 1 do
    local f = loHz * math.exp(ratio * (i + 0.5) / nSrc)
    local b = math.floor((erbRate(f) - eLo) / (eHi - eLo) * g.n) + 1
    g.owner[i] = math.max(1, math.min(g.n, b))
  end

  gridCache = g
  return g
end

----------------------------------------------------------
-- the spreading matrix
----------------------------------------------------------

local sfCache = { width = nil, m = nil, n = nil }

-- width 1 is Schroeder as published. Smaller narrows it, and at or below
-- 0.05 it becomes same-band-only, which is the model to compare against
-- rather than a degenerate case to avoid.
--
-- Narrowing scales the DISTANCE, not the decibels: halving the width
-- makes one Bark away look like two Bark away, which keeps the curve's
-- shape. Scaling the decibels instead would flatten it toward "everything
-- masks everything equally", which is the opposite of narrow.
function M.spreading(g, width)
  width = math.max(0, math.min(4, width or 1))
  if sfCache.m and sfCache.width == width and sfCache.n == g.n then
    return sfCache.m
  end

  local m = {}
  local sameBandOnly = width < 0.05
  for i = 1, g.n do
    local row = {}
    for j = 1, g.n do
      if sameBandOnly then
        row[j] = (i == j) and 1 or 0
      else
        local dz = (g.bark[i] - g.bark[j]) / width
        -- Below about -60 dB the term cannot change a sum that already
        -- contains the masker's own band, so it is dropped rather than
        -- multiplied in 41 times per band.
        local db = schroeder(dz)
        row[j] = (db > -60) and 10 ^ (db / 10) or 0
      end
    end
    m[i] = row
  end

  sfCache.width, sfCache.m, sfCache.n = width, m, g.n
  return m
end

----------------------------------------------------------
-- excitation
----------------------------------------------------------

-- Sums the published bands into ERB bands, in power, and returns dB.
--   readBand(i)  source band i's mean power in dB, or nil
--   gainDb       the track's fader, so the comparison happens at the
--                levels you are actually hearing rather than at the
--                levels inside the FX chain. A track pulled down 20 dB
--                is not masking anything.
function M.excitation(g, readBand, gainDb, out)
  out = out or {}
  local lin = {}
  for b = 1, g.n do lin[b] = 0 end

  for i = 0, g.nSrc - 1 do
    local d = readBand(i)
    -- -180 is the probe's silence, -400 its "no FFT bin here". Neither is
    -- energy, and 10^(-400/10) is a denormal nobody needs.
    if d and d > -179 then
      local b = g.owner[i]
      lin[b] = lin[b] + 10 ^ (d / 10)
    end
  end

  local gain = 10 ^ ((gainDb or 0) / 10)
  for b = 1, g.n do
    local p = lin[b] * gain
    out[b] = (p > 1e-30) and (10 * math.log(p, 10)) or -300
  end
  return out
end

----------------------------------------------------------
-- the masked threshold, and the collision
----------------------------------------------------------

-- Spread one track's excitation across the bands it masks.
function M.spread(g, sf, E, out)
  out = out or {}
  local lin = {}
  for j = 1, g.n do
    lin[j] = (E[j] > -299) and 10 ^ (E[j] / 10) or 0
  end
  for i = 1, g.n do
    local row, acc = sf[i], 0
    for j = 1, g.n do
      local w = row[j]
      if w > 0 then acc = acc + lin[j] * w end
    end
    out[i] = (acc > 1e-30) and (10 * math.log(acc, 10)) or -300
  end
  return out
end

-- How far the track you are looking at sits BELOW the masked threshold
-- the other track creates. Positive means masked; the number is decibels
-- of masking depth, which is what the overlay's intensity comes from.
--
--   Ea       the selected track's excitation, dB
--   Eb       the comparison track's, dB
--   opt.offsetDb   how far the threshold sits below the spread
--                  excitation. The masking index; one knob instead of a
--                  tonality estimator.
--   opt.floorDb    audibility gate, dBFS at the ear's most sensitive
--                  point, shaped by the threshold of hearing.
--   opt.marginDb   how deep the masking has to be before it is worth
--                  drawing at all.
function M.collide(g, sf, Ea, Eb, opt, out)
  out = out or {}
  local offset = opt.offsetDb or 6
  local floor  = opt.floorDb  or -60
  local margin = opt.marginDb or 0

  local Tb = M.spread(g, sf, Eb, opt._scratch or {})
  opt._scratch = Tb

  for b = 1, g.n do
    local gate = floor + g.ath[b]
    -- BOTH have to be audible for this to be a collision worth showing.
    --   The masker, obviously. But also the masked track: if it has
    --   nothing there, nothing of it is being lost, and flagging it is
    --   how an overlay ends up red everywhere and trusted nowhere.
    if Ea[b] > gate and Eb[b] > gate then
      local depth = (Tb[b] - offset) - Ea[b]
      out[b] = (depth > margin) and (depth - margin) or 0
    else
      out[b] = 0
    end
  end
  return out
end

----------------------------------------------------------
-- for the diagnostics
----------------------------------------------------------

function M.count(g)     return g.n end

return M
