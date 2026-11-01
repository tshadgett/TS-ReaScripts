-- @noindex
--[[
  TS_CV_PresetSyncProbe.lua -- dev probe, not released.

  A user report: picking a preset in ChannelView changes the plugin (TDR
  Slick EQ, on a Mac), but ChannelView's controls stay where they were.
  ChannelView reads every value from REAPER each frame
  (TrackFX_GetParamNormalized), so either REAPER isn't told the values
  changed, or it's told late. This finds out which, and whether handing
  the plugin its own state back makes REAPER catch up.

  Use: open the plugin's window (so it's the focused FX), run this. It
  steps to the next preset (as ChannelView's > button does), then logs to
  the console how many of the plugin's parameters REAPER reports as
  changed: at once, after 10 frames, after about 1 s; then (if none or few
  changed) reads the plugin's state and sets it straight back, and counts
  again. Run it twice on a plugin that works (ReaEQ, say) to compare.
--]]

local function out(s) reaper.ShowConsoleMsg(s .. "\n") end

local tr, fx
do
  -- retval (1: a track's FX), track number (0: master), item, take, FX
  local rv, tnum, _, _, fxnum = reaper.GetFocusedFX2()
  if rv and (rv & 1) == 1 and (fxnum or -1) >= 0 then
    tr = (tnum == 0) and reaper.GetMasterTrack(0) or reaper.GetTrack(0, tnum - 1)
    fx = fxnum
  end
end
if not tr then
  tr = reaper.GetSelectedTrack(0, 0); fx = 0
end
if not tr or reaper.TrackFX_GetCount(tr) <= fx then
  reaper.MB("Open the plugin's window first (or select a track whose first FX is the plugin).", "Preset probe", 0)
  return
end

local _, name = reaper.TrackFX_GetFXName(tr, fx, "")
local _, ftype = reaper.TrackFX_GetNamedConfigParm(tr, fx, "fx_type")
local np = math.min(reaper.TrackFX_GetNumParams(tr, fx), 400)

local function snap()
  local t = {}
  for p = 0, np - 1 do t[p] = reaper.TrackFX_GetParamNormalized(tr, fx, p) end
  return t
end
local function changed(a, b)
  local n, first = 0, nil
  for p = 0, np - 1 do
    if math.abs((a[p] or 0) - (b[p] or 0)) > 1e-6 then
      n = n + 1
      if not first then first = p end
    end
  end
  return n, first
end
local function preset() local _, pn = reaper.TrackFX_GetPreset(tr, fx, ""); return pn or "?" end

out(("\n== %s  (%s, %d params)"):format(name, ftype or "?", np))
out("preset before: " .. preset())
local before = snap()
reaper.TrackFX_NavigatePresets(tr, fx, 1)
out("preset after:  " .. preset())
local n0 = changed(before, snap())
out(("changed at once:        %d"):format(n0))

local frame = 0
local function step()
  frame = frame + 1
  if frame == 10 then
    out(("changed after 10 frames: %d"):format((changed(before, snap()))))
  elseif frame == 40 then
    local n, first = changed(before, snap())
    out(("changed after ~1 s:      %d%s"):format(n, first and ("  (first: param %d)"):format(first) or ""))
    -- hand the plugin its own state back: does REAPER catch up then?
    local ok, chunk = reaper.TrackFX_GetNamedConfigParm(tr, fx, "vst_chunk")
    if ok and chunk and chunk ~= "" then
      reaper.TrackFX_SetNamedConfigParm(tr, fx, "vst_chunk", chunk)
      out("state handed back (vst_chunk, " .. #chunk .. " chars)")
    else
      out("no vst_chunk for this plugin (not VST2/VST3?)")
    end
  elseif frame == 60 then
    local n, first = changed(before, snap())
    out(("changed after the state went back: %d%s"):format(n, first and ("  (first: param %d)"):format(first) or ""))
    out("(the plugin's own window should still show the new preset)")
    return
  end
  reaper.defer(step)
end
reaper.defer(step)
