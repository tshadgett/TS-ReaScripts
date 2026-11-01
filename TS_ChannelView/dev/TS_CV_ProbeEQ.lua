-- @noindex
-- Dev probe (not released): lists what the selected track's EQ plugins
-- call their band shapes and slopes, for TS_CV_MapEQ's name reading.
-- Writes dev/probe_eq.txt beside this script. Run from the Actions list.

local out = {}
local function w(s) out[#out + 1] = s end

local tr = reaper.GetSelectedTrack(0, 0)
if not tr then reaper.ShowMessageBox("Select a track with the EQs on it first.", "Probe EQ", 0) return end

local function runs(fx, p)
  local res, last = {}, nil
  local supported = reaper.TrackFX_FormatParamValueNormalized ~= nil
  for i = 0, 400 do
    local v = i / 400
    local ok, t = false, nil
    if supported then ok, t = reaper.TrackFX_FormatParamValueNormalized(tr, fx, p, v, "") end
    t = ok and t or "<nil>"
    if t ~= last then res[#res + 1] = ("%.4f=%s"):format(v, t); last = t end
    if #res > 60 then res[#res + 1] = "..."; break end
  end
  return res
end

for fx = 0, reaper.TrackFX_GetCount(tr) - 1 do
  local _, name = reaper.TrackFX_GetFXName(tr, fx, "")
  local lname = name:lower()
  if lname:find("pro%-q") or lname:find("kirchhoff") then
    w("== " .. name)
    local n = reaper.TrackFX_GetNumParams(tr, fx)
    w("params: " .. n)
    -- the first two bands' worth of parameters, named and as they read now
    for p = 0, math.min(n - 1, 70) do
      local _, pn = reaper.TrackFX_GetParamName(tr, fx, p, "")
      local _, txt = reaper.TrackFX_GetFormattedParamValue(tr, fx, p, "")
      w(("%3d  %-40s  now: %s  (%.4f)"):format(p, pn, txt, reaper.TrackFX_GetParamNormalized(tr, fx, p)))
    end
    -- every parameter that sounds like a shape, type or slope, position by position
    for p = 0, n - 1 do
      local _, pn = reaper.TrackFX_GetParamName(tr, fx, p, "")
      local l = pn:lower()
      if (l:find("shape") or l:find("type") or l:find("slope") or l:find("mode")) and (l:find("1") or l:find("band 1")) then
        w("-- " .. p .. " " .. pn)
        for _, r in ipairs(runs(fx, p)) do w("   " .. r) end
        local ok, st = reaper.TrackFX_GetParameterStepSizes(tr, fx, p)
        w("   step sizes: " .. tostring(ok) .. " " .. tostring(st))
      end
    end
  end
end

local path = debug.getinfo(1, "S").source:match("^@(.*[/\\])") or ""
local f = io.open(path .. "probe_eq.txt", "w")
if f then f:write(table.concat(out, "\n")); f:close() end
reaper.ShowMessageBox("Written: " .. path .. "probe_eq.txt", "Probe EQ", 0)
