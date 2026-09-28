--========================================================
-- @noindex
-- @title TS_TA_GR
-- @description Track Analyser -- gain reduction from per-band probe levels
-- @author Tim Shadgett
-- @version 1.1.0
--========================================================
--
-- Not a script you run. TS_TrackAnalyser requires this.
--
-- WHAT THIS IS FOR, AND WHAT IT REPLACES
--   The measured gain-reduction trace used to be post RMS over pre RMS
--   across the span between the probes. That is not gain. It is the
--   span's LEVEL change, and the two are the same thing only when
--   nothing in the span touches the SPECTRUM.
--
--   The moment something does -- one EQ band is enough -- the level
--   change starts depending on where the programme's energy happens to
--   be sitting. A static +6 dB at 100 Hz adds six decibels to the ratio
--   through a bass note and nothing at all through a cymbal. The EQ
--   never moved. The music did, and it went onto the trace looking
--   exactly like compression. Measured against a true 13 dB reduction,
--   that drew a 39 dB one: 3.10 dB of error, correlation 0.71.
--
--   A per-BAND ratio does not have that property. Band b's ratio is
--   whatever the EQ does in band b, regardless of how much energy is
--   there to be changed. So the probes publish a level per band per
--   column, and this splits the two apart:
--
--     a static EQ  is constant in TIME       and varies across bands
--     compression  is constant across BANDS  and varies in time
--
--   Subtract each band's own average over the window and the EQ is
--   gone. Average what is left across the bands and the noise falls
--   with it, leaving the part that moves together -- which is the
--   compressor. Same material, same chain: 0.68 dB of error,
--   correlation 0.97.
--
-- WHAT IT STILL CANNOT DO
--   It is the whole span, not one plugin. Two compressors between the
--   probes give you both. A saturator's gain is genuinely
--   level-dependent, so its contribution is real reduction and is
--   reported as such -- 0.61 dB of error at twelve decibels of drive,
--   which is about as well as the question can be answered from the
--   two ends of a chain.
--
--   It is also blind to a spectral change that MOVES: a dynamic EQ or a
--   multiband compressor breaks the "constant across bands" assumption
--   on purpose, and this will read the band-average of what they do.
--   That is not wrong so much as it is a different question.
--
--   And it assumes the two probes are aligned. They are not, on their
--   own: any FX between them with reported latency delays the post
--   probe, and at one column of skew the columns being compared hold
--   audio from different moments. The probe compensates for that from
--   a figure the panel reads off the chain -- without it, none of the
--   above holds.
--========================================================

local M = {}

-- Where the band levels start inside a scope column. 1..3 are min, max
-- and RMS, which were there first.
M.BAND0 = 4

-- A band with nothing in it is not evidence of anything. Two thresholds,
-- for the same reason the broadband gate needed two: an absolute floor,
-- below which there is no signal to take a ratio of, and one relative to
-- what that band does at its loudest, because a band that lives at -60
-- has real gaps far above any fixed floor.
local GATE_ABS = 10 ^ (-90 / 20)
local GATE_REL = 50

local LOG10 = math.log(10)
local function db(x) return 20 * math.log(x) / LOG10 end

----------------------------------------------------------
-- the estimate
--
--   pre, post   ring arrays, indexed 0 .. len-1, each entry a column
--               table holding linear band levels at BAND0 + b
--   oldest      index of the first column in the visible window
--   total       how many columns the window covers
--   nb          how many bands the probes are publishing
--   out         reused output table, out[k] for k = 0 .. total-1, dB,
--               zero-mean over the window -- the caller slides it onto
--               the level the plugin reports
--
-- Returns out, and the number of bands that carried the estimate. Zero
-- means there was nothing to measure and the caller should draw nothing
-- rather than draw zeros, which look like a chain doing no work.
----------------------------------------------------------
function M.shape(pre, post, len, oldest, total, nb, out, scratch)
  out = out or {}
  scratch = scratch or {}

  local peak = scratch.peak or {} ; scratch.peak = peak
  local sum  = scratch.sum  or {} ; scratch.sum  = sum
  local cnt  = scratch.cnt  or {} ; scratch.cnt  = cnt
  local gate = scratch.gate or {} ; scratch.gate = gate

  for b = 1, nb do peak[b] = 0 end

  -- PASS 1: how loud does each band get in this window? Sets its gate.
  -- Subsampled on the same stride as the averages below. Missing the true
  -- peak by a fraction of a decibel sets the gate a fraction lower, which
  -- lets a marginal column through -- the failure this cannot have is the
  -- other one, a gate set too HIGH, and undersampling cannot cause it.
  local stride = math.max(1, math.floor(total / 256))
  for k = 0, total - 1, stride do
    local a = pre[(oldest + k) % len]
    if a then
      for b = 1, nb do
        local v = a[M.BAND0 + b - 1]
        if v and v > peak[b] then peak[b] = v end
      end
    end
  end
  for b = 1, nb do
    gate[b] = math.max(GATE_ABS, peak[b] * 10 ^ (-GATE_REL / 20))
    sum[b], cnt[b] = 0, 0
  end

  -- PASS 2: each band's average response over the window. This is the
  -- static part -- the EQ, the fixed part of the saturation, and the
  -- compressor's own mean, which the caller replaces anyway when it
  -- slides the shape onto the reported level.
  --
  --   SUBSAMPLED. An average over two thousand columns and one over every
  --   eighth of them differ in the third decimal place, and this is the
  --   only place a logarithm per band per column would be needed. Capped
  --   at 256 columns, so the cost stops growing when you zoom out.
  for k = 0, total - 1, stride do
    local a, c = pre[(oldest + k) % len], post[(oldest + k) % len]
    if a and c then
      for b = 1, nb do
        local va, vc = a[M.BAND0 + b - 1], c[M.BAND0 + b - 1]
        if va and vc and va > gate[b] and vc > GATE_ABS then
          sum[b] = sum[b] + db(vc / va)
          cnt[b] = cnt[b] + 1
        end
      end
    end
  end

  -- A band has to be present for a decent part of the window before its
  -- average means anything. A band alive for two of the sampled columns
  -- contributes an average built from nothing.
  local need = math.max(4, (total / stride) * 0.05)
  local live = 0
  for b = 1, nb do
    if cnt[b] >= need then sum[b] = sum[b] / cnt[b] ; live = live + 1
    else sum[b] = nil end
  end
  if live == 0 then return out, 0 end

  -- PASS 3: what is left once each band's own average is taken off it.
  --
  --   THE MEDIAN ACROSS BANDS, NOT THE MEAN. Compression moves every band
  --   together, so any band will do and the question is only which is
  --   least polluted -- which is what a median answers and a mean does
  --   not. The pollution is not evenly spread: a 2 ms column holds 26
  --   cycles of the 13 kHz band and 0.08 of a cycle of the 41 Hz one, so
  --   the bottom band's level is mostly a statement about phase. Measured,
  --   its column-to-column wobble is 1.56 dB against 0.13 dB at the top --
  --   one band in ten, twelve times noisier than the best, and a mean
  --   hands it a tenth of the answer.
  --
  --   Dropping the low bands instead is worse, not better: they carry real
  --   information on bass-heavy material and excluding them took the error
  --   UP, from 0.52 dB to 0.73. Keeping them and outvoting them is what
  --   works. Across seven EQ and saturation chains the median took the
  --   error from 0.69 dB to 0.52 and the visible hash from 0.57 to 0.45.
  --
  --   Taken on the RATIOS, not on the decibels. A logarithm is monotonic,
  --   so it does not move the middle value -- and doing it this way needs
  --   one log per column rather than one per band.
  local mid = scratch.mid or {} ; scratch.mid = mid
  local div = scratch.div or {} ; scratch.div = div
  for b = 1, nb do
    div[b] = sum[b] and 10 ^ (sum[b] / 20) or nil
  end

  -- ONE COLUMN IN TWO ON THE WIDEST ZOOMS. At eight seconds a pixel is
  -- already five columns wide and the smoothing below spans five more, so
  -- a second sort inside the same pixel changes nothing anybody can see.
  -- Below fifteen hundred columns -- every window you would look at a
  -- transient in -- every column is sorted. Skipped columns hold, which is
  -- what an unmeasurable one does anyway.
  local step = math.max(1, math.floor(total / 1500))

  local held = 0
  for k = 0, total - 1, step do
    local a, c = pre[(oldest + k) % len], post[(oldest + k) % len]
    local n = 0
    if a and c then
      for b = 1, nb do
        local d = div[b]
        if d then
          local va, vc = a[M.BAND0 + b - 1], c[M.BAND0 + b - 1]
          if va and vc and va > gate[b] and vc > GATE_ABS then
            -- insertion sort on the way in: at ten values this beats
            -- sorting afterwards and allocates nothing
            local x, j = (vc / va) / d, n
            while j >= 1 and mid[j] > x do mid[j + 1] = mid[j] ; j = j - 1 end
            mid[j + 1] = x ; n = n + 1
          end
        end
      end
    end
    -- A column nothing could be measured in HOLDS. A gap in the audio is
    -- not a moment of no gain reduction; it is a moment we cannot
    -- measure, and drawing it as zero invents a release that did not
    -- happen.
    if n > 0 then
      local m
      if n % 2 == 1 then
        m = mid[(n + 1) // 2]
      else
        -- The geometric mean of the two middle values IS the arithmetic
        -- mean of their decibels, so the even case costs no extra log.
        m = math.sqrt(mid[n // 2] * mid[n // 2 + 1])
      end
      if m > 0 then held = db(m) end
    end
    for q = k, math.min(k + step - 1, total - 1) do out[q] = held end
  end

  -- FIVE COLUMNS OF SMOOTHING -- ten milliseconds.
  --
  --   What is left after the median is per-column noise, and it does not
  --   merely look untidy: the trace is drawn by taking the DEEPEST column
  --   in each pixel, so noise is rectified into apparent reduction. On a
  --   1 ms attack the raw estimate read the deepest moment as -10.50 dB
  --   where the truth was -8.34; smoothed it reads -9.26. The smoothing
  --   does not blunt the transient -- it stops the noise deepening it --
  --   and that holds at every attack and release setting tested, from
  --   1/30 ms to 30/400. Across the battery it takes the hash from 0.45 dB
  --   to 0.10 and the error from 0.52 to 0.32.
  --   Done with a running sum: five additions a column becomes two,
  --   which matters here only because this is the one pass that cannot
  --   be decimated -- it is what removes the noise the decimation would
  --   otherwise alias.
  local sm = scratch.sm or {} ; scratch.sm = sm
  local acc, lo, hi = 0, 0, -1
  for k = 0, total - 1 do
    local want0, want1 = math.max(0, k - 2), math.min(total - 1, k + 2)
    while hi < want1 do hi = hi + 1 ; acc = acc + out[hi] end
    while lo < want0 do acc = acc - out[lo] ; lo = lo + 1 end
    sm[k] = acc / (hi - lo + 1)
  end
  for k = 0, total - 1 do out[k] = sm[k] end

  return out, live
end

return M
