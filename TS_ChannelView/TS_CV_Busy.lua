-- @noindex
-- TS_CV_Busy.lua -- backing off while REAPER is busy
--
-- A deferred script keeps running while REAPER does a long job on the
-- main thread behind a progress dialog -- a plugin scan, say. Every
-- frame ChannelView makes a few hundred TrackFX calls, and when those
-- have to wait on the job, and the job on them, both crawl: a scan that
-- takes seconds on its own takes minutes with ChannelView open.
--
-- Rather than know about scans, the loop times itself. When frames are
-- suddenly many times slower than they have been (BZ.SLOW_ABS and
-- SLOW_REL, SLOW_RUN in a row) the script backs off: it stops polling
-- FX and draws next to nothing, trying one full frame a second until a
-- frame is quick again. A slow machine, where every frame is slow, never
-- trips it: the test is relative to the script's own typical frame.
--
-- A job ends; a frame that's slow for some other reason (a plugin that's
-- slow to answer something asked of it every frame) doesn't. So when the
-- probes have been slow for BZ.GIVE_UP seconds on end, that is taken as
-- what a frame costs now: the typical is learnt again from them and the
-- script carries on -- slower, but never stuck on its note.
--
-- Both ChannelView's window and the web bridge keep an instance each.

local BZ = {}

BZ.SLOW_ABS    = 0.15   -- s: never back off for frames shorter than this
BZ.SLOW_REL    = 5      -- ...nor for frames under this many times the typical
BZ.SLOW_RUN    = 3      -- slow frames in a row before backing off
BZ.PROBE_EVERY = 1.0    -- s between full frames while backed off
BZ.TYPICAL_0   = 0.02   -- s: the typical frame before any have been timed
BZ.WARMUP      = 30     -- frames that only teach the typical, never trip
BZ.GIVE_UP     = 15     -- s of slow probes before they're the new typical

local typical    = BZ.TYPICAL_0
local slow_run   = 0
local backed     = false
local since      = 0      -- when the back-off began
local last_probe = 0
local seen       = 0      -- frames timed so far
local probe_sum, probe_n = 0, 0   -- the slow probes since backing off

-- Called after every full frame with how long it took. Returns whether
-- the script is backed off after it.
function BZ.note(dur, now)
  -- the first frames teach what a frame costs here, slow machine or
  -- not, so a slow machine's ordinary frames are never "sudden"
  if seen < BZ.WARMUP then
    seen = seen + 1
    typical = typical + (dur - typical) * 0.1
    return false
  end
  local slow = dur > BZ.SLOW_ABS and dur > typical * BZ.SLOW_REL
  if backed then
    -- a probe frame: quick again, so carry on
    if not slow then
      backed, slow_run, probe_sum, probe_n = false, 0, 0, 0
      return false
    end
    probe_sum, probe_n = probe_sum + dur, probe_n + 1
    -- slow for good: that's what a frame costs now
    if (now or 0) - since >= BZ.GIVE_UP and probe_n >= 3 then
      typical = probe_sum / probe_n
      backed, slow_run, probe_sum, probe_n = false, 0, 0, 0
    end
    return backed
  end
  if slow then
    slow_run = slow_run + 1
  else
    slow_run = 0
    typical = typical + (dur - typical) * 0.05
  end
  if slow_run >= BZ.SLOW_RUN then
    backed, slow_run, since, last_probe = true, 0, now or 0, now or 0
  end
  return backed
end

function BZ.backed() return backed end
function BZ.typical() return typical end
function BZ.since() return since end

-- While backed off: whether a full frame is due (once a second).
function BZ.probe_due(now)
  if not backed then return true end
  if now - last_probe >= BZ.PROBE_EVERY then
    last_probe = now
    return true
  end
  return false
end

function BZ.reset()
  typical, slow_run, backed, since, last_probe, seen = BZ.TYPICAL_0, 0, false, 0, 0, 0
  probe_sum, probe_n = 0, 0
end

return BZ
