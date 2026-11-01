-- @noindex
--[[
  TS_CV_LatencyProbe.lua -- dev probe, not released.

  For the selected track: every FX's reported latency (pdc), in samples and
  ms, and -- for any whose ChannelView trace is open -- what the trace's
  lining up found (TS_CV_Trace: in_k, how many columns the input is held
  back; gr_k, how many the reported reduction is drawn late by; slice,
  samples a column). Play a few bars with the trace open, then run this.
--]]
local function out(s) reaper.ShowConsoleMsg(s .. "\n") end
-- ChannelView writes what its traces found only while this is set (for
-- this session); the first run turns it on, so run it again a few seconds
-- later with the trace open
local was_on = reaper.GetExtState("TS_ChannelView", "align_debug") == "1"
reaper.SetExtState("TS_ChannelView", "align_debug", "1", false)
if not was_on then out("(trace reporting switched on: run this again in a few seconds with the trace open)") end
local tr = reaper.GetSelectedTrack(0, 0)
if not tr then reaper.MB("Select the track first.", "Latency probe", 0) return end
-- the rate the audio actually runs at (the project's setting only counts
-- when it's set to be used)
local sr = tonumber(select(2, reaper.GetAudioDeviceInfo("SRATE", ""))) or 0
if sr <= 0 then sr = reaper.GetSetProjectInfo(0, "PROJECT_SRATE", 0, false) or 48000 end
local _, tname = reaper.GetTrackName(tr)
out(("\n== %s  (%d Hz)"):format(tname, sr))
local _, buf = reaper.GetAudioDeviceInfo("BSIZE", "")
out("audio buffer: " .. tostring(buf))
out(("track channels: %d"):format(reaper.GetMediaTrackInfo_Value(tr, "I_NCHAN")))
local _, rec = reaper.GetSetMediaTrackInfo_String(tr, "P_EXT:TS_CV_TAPS", "", false)
out("taps record: " .. ((rec and rec ~= "") and rec or "(none)"))
for i = 0, reaper.TrackFX_GetCount(tr) - 1 do
  local _, name = reaper.TrackFX_GetFXName(tr, i, "")
  local ok, pdc = reaper.TrackFX_GetNamedConfigParm(tr, i, "pdc")
  local n = tonumber(ok and pdc or 0) or 0
  local on = reaper.TrackFX_GetEnabled(tr, i) and "" or "  (bypassed)"
  out(("%2d  %-40s pdc %6d  (%.1f ms)%s"):format(i + 1, name:sub(1, 40), n, n / sr * 1000, on))
  -- its pins: which track channels each reads and writes
  local _, nin, nout = reaper.TrackFX_GetIOSize(tr, i)
  local function chans(isout, pin)
    local lo, hi = reaper.TrackFX_GetPinMappings(tr, i, isout and 1 or 0, pin)
    local t = {}
    for b = 0, 31 do if ((lo or 0) >> b) & 1 == 1 then t[#t + 1] = b + 1 end end
    for b = 0, 31 do if ((hi or 0) >> b) & 1 == 1 then t[#t + 1] = b + 33 end end
    return #t > 0 and table.concat(t, "+") or "-"
  end
  local ins, outs = {}, {}
  for p = 0, math.min((nin or 0), 20) - 1 do ins[#ins + 1] = chans(false, p) end
  for p = 0, math.min((nout or 0), 20) - 1 do outs[#outs + 1] = chans(true, p) end
  out(("      pins: %d in [%s]   %d out [%s]"):format(nin or -1, table.concat(ins, " "), nout or -1, table.concat(outs, " ")))
  local g = reaper.TrackFX_GetFXGUID(tr, i)
  local a = reaper.GetExtState("TS_ChannelView", "align " .. g)
  if a ~= "" then out("      trace: " .. a) end
end

-- The probe's third-octave reading for this track (what the spectrum strip
-- draws), sampled 20 times over 2 seconds: each band's average and its
-- lowest, and the level going in. Play while it runs.
reaper.gmem_attach("TS_TA_Mem")
local idx = math.floor(reaper.GetMediaTrackInfo_Value(tr, "IP_TRACKNUMBER")) - 1
local gb = 0x70000 + idx * 128
local nb = math.floor(reaper.gmem_read(gb + 1) + 0.5)
if nb < 1 or nb > 31 then
  out("third-octaves: none on this track (open the de-esser canvas while playing)")
else
  out(("third-octaves: %d bands, tap %d, zero %s"):format(nb, math.floor(reaper.gmem_read(gb + 2) + 0.5),
    reaper.gmem_read(gb + 3) > 0.5 and "measured" or "from the music"))
  local sum, cnt, low, lvs = {}, {}, {}, {}
  local n = 0
  local function sample()
    for k = 0, nb - 1 do
      local d = reaper.gmem_read(gb + 8 + k)
      if d > -900 then
        sum[k] = (sum[k] or 0) + d; cnt[k] = (cnt[k] or 0) + 1
        low[k] = math.min(low[k] or 999, d)
      end
      lvs[k] = math.max(lvs[k] or -999, reaper.gmem_read(gb + 72 + k))
    end
    n = n + 1
    if n < 20 then
      local t0 = reaper.time_precise()
      local function wait() if reaper.time_precise() - t0 < 0.1 then reaper.defer(wait) else sample() end end
      reaper.defer(wait)
      return
    end
    out("  band Hz    average  lowest   input dBFS")
    for k = 0, nb - 1 do
      local f = 1000 * 2 ^ ((k - 16) / 3)
      out(("  %7.0f  %7s  %7s   %6.1f"):format(f,
        cnt[k] and ("%.1f"):format(sum[k] / cnt[k]) or "-", low[k] and ("%.1f"):format(low[k]) or "-", lvs[k]))
    end
  end
  sample()
end
