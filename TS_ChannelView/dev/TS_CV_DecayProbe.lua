-- @noindex
-- dev tool, not released. Read-only: how a reverb's Decay reads along its
-- range, for the canvas (Seventh Heaven Professional works backwards).
-- Select the track with the reverb on it, run, and read dev/decayprobe.txt.

local here = debug.getinfo(1, "S").source:match("@?(.*[\\/])") or ""
local out = {}
local function say(s) out[#out + 1] = s end

local tr = reaper.GetSelectedTrack(0, 0)
if not tr then reaper.MB("Select the reverb's track first.", "Decay probe", 0) return end
for fx = 0, reaper.TrackFX_GetCount(tr) - 1 do
  local _, name = reaper.TrackFX_GetFXName(tr, fx, "")
  if name:lower():find("seventh heaven") or name:lower():find("reverb") then
    say("== " .. name)
    for p = 0, math.min(reaper.TrackFX_GetNumParams(tr, fx), 80) - 1 do
      local _, pn = reaper.TrackFX_GetParamName(tr, fx, p, "")
      if pn:lower():find("decay") or pn:lower():find("time") or pn:lower():find("size") then
        local _, now = reaper.TrackFX_GetFormattedParamValue(tr, fx, p, "")
        local okst, st = reaper.TrackFX_GetParameterStepSizes(tr, fx, p)
        say(("  %d  %s   now %q  n=%.4f  step %s"):format(p, pn, now, reaper.TrackFX_GetParamNormalized(tr, fx, p),
          okst and tostring(st) or "none"))
        local row = {}
        for k = 0, 20 do
          local v = k / 20
          local _, t = reaper.TrackFX_FormatParamValueNormalized(tr, fx, p, v, "")
          row[#row + 1] = ("%.2f=%s"):format(v, t)
        end
        say("     " .. table.concat(row, " | "))
      end
    end
  end
end
local f = io.open(here .. "decayprobe.txt", "w")
if f then f:write(table.concat(out, "\n") .. "\n"); f:close() end
reaper.ShowConsoleMsg("Decay probe: wrote " .. here .. "decayprobe.txt\n")
