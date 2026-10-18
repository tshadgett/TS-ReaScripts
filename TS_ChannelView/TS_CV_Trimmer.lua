-- @noindex
-- Not a package of its own: installed by TS_ChannelView.lua's @provides.
--[[
  TS_CV_Trimmer.lua -- the TS_CV Trimmer plugin (TS_CV_Trimmer.jsfx):
  finding it, putting it on a track, its parameters, its meters and
  spectrum (through gmem), Listen, and Auto trim. The panel that draws it
  is TS_CV_TrimmerPanel.lua.

  AUTO TRIM sets the trim so the track's items sit where the meter wants
  them: their average (RMS) on 0 VU and their peaks under the peak
  ceiling, whichever needs less gain. Each item is measured on its own
  (REAPER's CalculateNormalization, over the part of its source that
  plays, inside the time selection when there is one), with its item and
  take volume, which come before the trim. The loudest item decides, so
  the items keep their levels against each other. The items themselves
  are never changed. Take FX and envelopes aren't part of the reading.

  LISTEN does the same from what's playing: the plugin measures its input
  (before the trim) from Start to Stop, and the trim is set by the same
  rule. For tracks with nothing recorded yet.

  The meter is sine-calibrated (a sine peaking at the 0 VU reference
  reads 0 VU); REAPER's RMS is plain RMS, 3 dB under that for a sine, so
  the RMS target is the reference less 3 dB.
--]]

local TR = {}

TR.DESC = "TS_CV Trimmer"
TR.NS   = "TS_TA_Mem"

-- REAPER resolves a JSFX by path under Effects/, which depends on how it
-- was installed; each is tried until one instantiates.
TR.PATHS = {
  "TS-ReaScripts/TS_ChannelView/TS_CV_Trimmer.jsfx",
  "TS_ChannelView/TS_CV_Trimmer.jsfx",
  "TS_CV_Trimmer.jsfx",
  "JS: " .. TR.DESC,
}

-- parameters, 0-based
TR.P = { TRIM_L = 0, TRIM_R = 1, LINK = 2, LC_F = 3, LC_S = 4, HC_F = 5, HC_S = 6, REF = 7, CEIL = 8 }
TR.SLOPES = { "6 dB/oct", "12 dB/oct", "18 dB/oct", "24 dB/oct", "36 dB/oct", "48 dB/oct" }
TR.ORDERS = { [0] = 1, 2, 3, 4, 6, 8 }         -- slope setting -> filter order
TR.TRIM_MAX = 24
TR.LC_LO, TR.LC_HI = 20, 1000
TR.HC_LO, TR.HC_HI = 1000, 20000

-- Each filter is off at the end of its range (as the plugin has it).
function TR.lc_on(f) return f and f > 20.5 end
function TR.hc_on(f) return f and f < 19900 end

-- The filter order a frequency and slope setting give: 0 when off.
function TR.order(on, s)
  if not on then return 0 end
  return TR.ORDERS[math.max(0, math.min(#TR.SLOPES - 1, math.floor((s or 0) + 0.5)))]
end
TR.REFS  = { -24, -20, -18, -14, -12 }
TR.CEILS = { -12, -9, -6, -3, -1 }
TR.SINE_RMS = 3.0103          -- a sine's peak over its plain RMS, dB

-- the plugin's gmem block for a track
local TB_BASE, TB_STRIDE = 0x200000, 256
TR.G = { VUL = 0, VUR = 1, PKL = 2, PKR = 3, SEQ = 4, NCH = 5,
         SHB = 8, SSEQ = 9, SBN = 10, SBLO = 11, SBHI = 12,
         LCMD = 16, LACK = 17, LMSL = 18, LMSR = 19, LPKL = 20, LPKR = 21, LN = 22,
         BAND = 64 }

local EXT = "TS_ChannelView"

-- ---------------------------------------------------------------------
-- pure helpers
-- ---------------------------------------------------------------------

function TR.is(name_or_key)
  return type(name_or_key) == "string" and name_or_key:find(TR.DESC, 1, true) ~= nil
end

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
TR.clamp = clamp

function TR.db(lin) return (lin and lin > 0) and 20 * math.log(lin, 10) or -math.huge end

-- The trim, in dB, that puts a reading on target: its RMS (plain, dB) on
-- the reference and its peak (dBFS) under the ceiling, whichever needs
-- less. nil when there's nothing to go on.
function TR.trim_for(rms_db, pk_db, ref, ceil)
  local want
  if rms_db and rms_db > -120 then want = (ref - TR.SINE_RMS) - rms_db end
  if pk_db and pk_db > -120 then
    local p = ceil - pk_db
    want = want and math.min(want, p) or p
  end
  if not want then return nil end
  return clamp(want, -TR.TRIM_MAX, TR.TRIM_MAX)
end

-- Auto trim's rule over items: each { rms = gain dB, pk = gain dB, vol = dB }
-- (the gains CalculateNormalization gives for the item's source to reach
-- the RMS target and the ceiling, and the item's own volume, which the
-- trim comes after). The smallest wins: the loudest item lands on target.
function TR.trim_from_items(items)
  local best
  for _, it in ipairs(items) do
    local g = it.rms
    if it.pk and (not g or it.pk < g) then g = it.pk end
    if g then
      g = g - (it.vol or 0)
      if not best or g < best then best = g end
    end
  end
  if not best then return nil end
  return clamp(best, -TR.TRIM_MAX, TR.TRIM_MAX)
end

-- The part of an item's source that plays, as start and end in source
-- seconds, inside [ts0, ts1] when a time selection is given; nil when
-- the item is outside it.
function TR.source_bounds(pos, len, offs, rate, ts0, ts1)
  rate = (rate and rate > 0) and rate or 1
  local a, b = pos, pos + len
  if ts0 and ts1 and ts1 > ts0 then
    a, b = math.max(a, ts0), math.min(b, ts1)
    if b - a < 0.01 then return nil end
  end
  return offs + (a - pos) * rate, offs + (b - pos) * rate
end

-- The filters' response at f, dB: Butterworth, through the bilinear
-- transform as the plugin builds them (so it falls away near Nyquist as
-- the plugin does). n = 0 is off.
function TR.response_db(f, lc_f, lc_n, hc_f, hc_n, sr)
  sr = sr or 48000
  local function w(x) return math.tan(math.pi * math.min(x, sr * 0.4999) / sr) end
  local d = 0
  if lc_n and lc_n > 0 then d = d - 10 * math.log(1 + (w(f) / w(math.min(lc_f, sr * 0.45))) ^ (-2 * lc_n), 10) end
  if hc_n and hc_n > 0 then d = d - 10 * math.log(1 + (w(f) / w(math.min(hc_f, sr * 0.45))) ^ (2 * hc_n), 10) end
  return d
end

-- Where the plugin goes in a chain of `names` (top level, in order):
-- after an ARA plugin in the first slot, then after the pre probe and
-- ChannelView's own modulators, so it's the first thing that touches
-- the sound.
function TR.slot_in(names, ara_first)
  local slot = (ara_first and #names > 0) and 1 or 0
  while slot < #names do
    local n = names[slot + 1] or ""
    if n:find("TS_TrackProbe", 1, true) or n:find("ChannelView Modulators", 1, true)
       or n:find("TS_CV_Learn", 1, true) then
      slot = slot + 1
    else
      break
    end
  end
  return slot
end

-- ---------------------------------------------------------------------
-- the plugin on a track
-- ---------------------------------------------------------------------

local function fx_name(track, i)
  local ok, n = reaper.TrackFX_GetNamedConfigParm(track, i, "fx_name")
  if ok and n and n ~= "" then return n end
  local ok2, nm = reaper.TrackFX_GetFXName(track, i, "")
  return ok2 and nm or ""
end

-- The top-level slot of the track's Trimmer, or nil.
function TR.find(track)
  if not track then return nil end
  for i = 0, (reaper.TrackFX_GetCount(track) or 0) - 1 do
    if TR.is(fx_name(track, i)) then return i end
  end
  return nil
end

function TR.slot_for(track, ara_first)
  local names = {}
  for i = 0, (reaper.TrackFX_GetCount(track) or 0) - 1 do names[#names + 1] = fx_name(track, i) end
  return TR.slot_in(names, ara_first)
end

-- The defaults a new Trimmer starts with: the 0 VU reference and the
-- peak ceiling ("Set as default" in the meter's menu).
function TR.defaults()
  local r = tonumber(reaper.GetExtState(EXT, "trim_ref"))
  local c = tonumber(reaper.GetExtState(EXT, "trim_ceil"))
  return r or -18, c or -6
end

function TR.set_defaults(ref, ceil)
  reaper.SetExtState(EXT, "trim_ref", tostring(ref), true)
  reaper.SetExtState(EXT, "trim_ceil", tostring(ceil), true)
end

-- Puts a Trimmer on the track if it hasn't one. Returns its slot, or
-- nil when REAPER can't find the JSFX.
function TR.insert(track, ara_first)
  local have = TR.find(track)
  if have then return have end
  local slot = TR.slot_for(track, ara_first)
  for _, p in ipairs(TR.PATHS) do
    local idx = reaper.TrackFX_AddByName(track, p, false, -1000 - slot)
    if idx and idx >= 0 then
      reaper.TrackFX_Show(track, idx, 2)      -- no floating window
      local ref, ceil = TR.defaults()
      reaper.TrackFX_SetParam(track, idx, TR.P.REF, ref)
      reaper.TrackFX_SetParam(track, idx, TR.P.CEIL, ceil)
      return idx
    end
  end
  return nil
end

function TR.get(track, idx, p)
  local v = reaper.TrackFX_GetParam(track, idx, p)
  return v
end

function TR.set(track, idx, p, v)
  reaper.TrackFX_SetParam(track, idx, p, v)
end

-- Both trims to their own values, the link left as it was (the plugin's
-- link would otherwise carry the first write onto the second).
function TR.set_trims(track, idx, l, r)
  local link = TR.get(track, idx, TR.P.LINK) >= 0.5
  if link then TR.set(track, idx, TR.P.LINK, 0) end
  TR.set(track, idx, TR.P.TRIM_L, clamp(l, -TR.TRIM_MAX, TR.TRIM_MAX))
  TR.set(track, idx, TR.P.TRIM_R, clamp(r, -TR.TRIM_MAX, TR.TRIM_MAX))
  if link then TR.set(track, idx, TR.P.LINK, 1) end
end

-- ---------------------------------------------------------------------
-- gmem: meters, spectrum, Listen
-- ---------------------------------------------------------------------

local attached = false
local function gm()
  if not attached then reaper.gmem_attach(TR.NS); attached = true end
end

-- The track's block in gmem: the plugin's get_host_placement() index + 1,
-- the master at 0.
function TR.block(track)
  local n = reaper.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER")
  if n == -1 then return TB_BASE end
  if not n or n < 1 then return nil end
  return TB_BASE + math.floor(n) * TB_STRIDE
end

local seen = {}     -- block -> { seq, t }: when the plugin last moved

-- VU L, VU R (meter dB), peak L, peak R (dBFS), and whether it's running.
function TR.meters(track)
  local b = TR.block(track)
  if not b then return nil end
  gm()
  local g = TR.G
  local seq = reaper.gmem_read(b + g.SEQ)
  local now = reaper.time_precise()
  local s = seen[b]
  if not s or s.seq ~= seq then s = { seq = seq, t = now }; seen[b] = s end
  local alive = seq > 0 and now - s.t < 0.5
  return reaper.gmem_read(b + g.VUL), reaper.gmem_read(b + g.VUR),
         reaper.gmem_read(b + g.PKL), reaper.gmem_read(b + g.PKR), alive
end

-- Keeps the plugin's spectrum running; call each frame it's shown.
local beat = 0
function TR.spectrum_beat(track)
  local b = TR.block(track)
  if not b then return end
  gm()
  beat = (beat + 1) % 1000000
  reaper.gmem_write(b + TR.G.SHB, beat + 1)
end

-- The spectrum: a list of dB per band, its lowest and highest frequency,
-- and its frame count (0 before the first frame).
function TR.bands(track, out)
  local b = TR.block(track)
  if not b then return nil end
  gm()
  local g = TR.G
  local n = math.floor(reaper.gmem_read(b + g.SBN))
  if n < 2 then return nil end
  out = out or {}
  for i = 0, n - 1 do out[i + 1] = reaper.gmem_read(b + g.BAND + i) end
  for i = n + 1, #out do out[i] = nil end
  return out, reaper.gmem_read(b + g.SBLO), reaper.gmem_read(b + g.SBHI), reaper.gmem_read(b + g.SSEQ)
end

local listening = {}   -- block -> { n = the number written, t = start }

function TR.listening(track)
  local b = TR.block(track)
  return b and listening[b] ~= nil
end

function TR.listen_start(track)
  local b = TR.block(track)
  if not b then return false end
  gm()
  local n = math.floor(reaper.time_precise() * 1000) % 100000000 + 1
  reaper.gmem_write(b + TR.G.LCMD, n)
  listening[b] = { n = n, t = reaper.time_precise() }
  return true
end

-- Stops and returns what was heard: RMS (plain, dB) and peak (dBFS) of
-- the louder channel, and seconds measured; nil when nothing was.
function TR.listen_stop(track)
  local b = TR.block(track)
  if not b then return nil end
  gm()
  local g = TR.G
  reaper.gmem_write(b + g.LCMD, 0)
  local was = listening[b]
  listening[b] = nil
  if not was then return nil end
  local n = reaper.gmem_read(b + g.LN)
  local sr = reaper.GetSetProjectInfo(0, "PROJECT_SRATE_USE", 0, false) > 0
             and reaper.GetSetProjectInfo(0, "PROJECT_SRATE", 0, false)
             or tonumber(select(2, reaper.GetAudioDeviceInfo("SRATE"))) or 48000
  if n < 1 then return nil end
  local ms = math.max(reaper.gmem_read(b + g.LMSL), reaper.gmem_read(b + g.LMSR))
  local pk = math.max(reaper.gmem_read(b + g.LPKL), reaper.gmem_read(b + g.LPKR))
  if ms <= 0 then return nil end
  return 10 * math.log(ms, 10), TR.db(pk), n / sr
end

-- ---------------------------------------------------------------------
-- Auto trim
-- ---------------------------------------------------------------------

-- The readings Auto trim goes by, one per item that plays (not muted,
-- not MIDI, inside the time selection when there is one).
function TR.item_readings(track, ref, ceil)
  local ts0, ts1 = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
  if not (ts1 and ts0 and ts1 > ts0) then ts0, ts1 = nil, nil end
  local out = {}
  for i = 0, reaper.CountTrackMediaItems(track) - 1 do
    local item = reaper.GetTrackMediaItem(track, i)
    local take = reaper.GetActiveTake(item)
    if take and (reaper.GetMediaItemInfo_Value(item, "B_MUTE") or 0) < 0.5 and not reaper.TakeIsMIDI(take) then
      local src = reaper.GetMediaItemTake_Source(take)
      local s, e = TR.source_bounds(reaper.GetMediaItemInfo_Value(item, "D_POSITION"),
        reaper.GetMediaItemInfo_Value(item, "D_LENGTH"),
        reaper.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS"),
        reaper.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE"), ts0, ts1)
      if src and s then
        local rg = reaper.CalculateNormalization(src, 1, ref - TR.SINE_RMS, s, e)
        local pg = reaper.CalculateNormalization(src, 2, ceil, s, e)
        local vol = (reaper.GetMediaItemInfo_Value(item, "D_VOL") or 1) * (reaper.GetMediaItemTakeInfo_Value(take, "D_VOL") or 1)
        out[#out + 1] = {
          rms = (rg and rg > 0) and TR.db(rg) or nil,
          pk  = (pg and pg > 0) and TR.db(pg) or nil,
          vol = TR.db(math.abs(vol)),
        }
      end
    end
  end
  return out
end

-- Sets the track's trim from its items. Returns the trim (dB), or nil
-- and why not. `ask(msg)` is asked before going on when an ARA plugin
-- (Melodyne and the like) plays the items before the Trimmer hears them.
function TR.auto_trim(track, ask, ara_first)
  local idx = TR.find(track)
  if not idx then return nil, "no Trimmer on this track" end
  if ara_first and idx > 0 and ask and not ask(
      "An ARA plugin (Melodyne or the like) comes before the Trimmer, so the " ..
      "items' audio isn't quite what the Trimmer hears.\n\nAuto trim anyway?") then
    return nil, "cancelled"
  end
  local ref, ceil = TR.get(track, idx, TR.P.REF), TR.get(track, idx, TR.P.CEIL)
  local t = TR.trim_from_items(TR.item_readings(track, ref, ceil))
  if not t then return nil, "nothing to measure (no audio items here)" end
  TR.set_trims(track, idx, t, t)
  return t
end

-- Sets the trim from a Listen reading.
function TR.trim_from_listen(track, rms_db, pk_db)
  local idx = TR.find(track)
  if not idx then return nil end
  local t = TR.trim_for(rms_db, pk_db, TR.get(track, idx, TR.P.REF), TR.get(track, idx, TR.P.CEIL))
  if t then TR.set_trims(track, idx, t, t) end
  return t
end

-- ---------------------------------------------------------------------
-- per instance: whether the spectrum shows (saved with the project)
-- ---------------------------------------------------------------------

local spec_cache = {}
function TR.spectrum_shown(guid)
  if not guid then return true end
  local v = spec_cache[guid]
  if v == nil then
    local _, s = reaper.GetProjExtState(0, EXT, "trimspec:" .. guid)
    v = s ~= "0"
    spec_cache[guid] = v
  end
  return v
end

function TR.set_spectrum_shown(guid, on)
  if not guid then return end
  spec_cache[guid] = on and true or false
  reaper.SetProjExtState(0, EXT, "trimspec:" .. guid, on and "" or "0")
end

return TR
