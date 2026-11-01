-- @noindex  (a development tool, not a package)
--[[
  TS_CV_ParamDump.lua -- every parameter of every plugin on the selected
  track, written to dev/paramdump.txt beside this script: its name, its
  value as the plugin shows it, its range, whether it steps, and how it
  reads across its range (0, 25, 50, 75, 100%). For building a plugin's
  canvas from what REAPER actually reports.

  Run it from the action list with a track selected.
--]]

local own = debug.getinfo(1, "S").source:match("@?(.*[\\/])") or ""
local track = reaper.GetSelectedTrack2(0, 0, true)
if not track then reaper.MB("Select a track first.", "Param dump", 0) return end

local out = {}
local function w(s) out[#out + 1] = s end
local _, tname = reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
w(("track: %s   REAPER %s"):format(tname, reaper.GetAppVersion()))

for fx = 0, reaper.TrackFX_GetCount(track) - 1 do
  local _, name = reaper.TrackFX_GetFXName(track, fx, "")
  local n = reaper.TrackFX_GetNumParams(track, fx)
  w(""); w(("[%d] %s   (%d parameters)"):format(fx, name, n))
  for p = 0, n - 1 do
    local _, nm = reaper.TrackFX_GetParamName(track, fx, p, "")
    local _, txt = reaper.TrackFX_GetFormattedParamValue(track, fx, p, "")
    local v, lo, hi = reaper.TrackFX_GetParam(track, fx, p)
    local norm = reaper.TrackFX_GetParamNormalized(track, fx, p)
    local ok, step, small, large, toggle = reaper.TrackFX_GetParameterStepSizes(track, fx, p)
    local reads = {}
    for _, k in ipairs({ 0, 0.25, 0.5, 0.75, 1 }) do
      local _, t = reaper.TrackFX_FormatParamValueNormalized(track, fx, p, k, "")
      reads[#reads + 1] = t or ""
    end
    w(("  %3d  %-28s = %-14s  norm %.4f  raw %.4f [%.4f..%.4f]%s   reads: %s"):format(
      p, nm or "", txt or "", norm or 0, v or 0, lo or 0, hi or 0,
      ok and (toggle and "  TOGGLE" or ("  step " .. tostring(step))) or "",
      table.concat(reads, " | ")))
  end
end

local f = io.open(own .. "paramdump.txt", "w")
if f then f:write(table.concat(out, "\n"), "\n"); f:close() end
reaper.MB("Written to " .. own .. "paramdump.txt", "Param dump", 0)
