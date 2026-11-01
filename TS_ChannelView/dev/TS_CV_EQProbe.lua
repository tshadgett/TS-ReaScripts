-- @noindex  (a development tool, not a package: never installed)
--[[
  TS_CV_EQProbe.lua -- what REAPER reports about a ReaEQ while you switch
  its presets, for the canvas that sometimes misses bands.

  Select the track, then run it: for 15 seconds it reads the first ReaEQ
  on the track every frame, as ChannelView's canvas does
  (TrackFX_GetEQParam on every parameter until one isn't an EQ one), and
  logs a line whenever what it finds changes: the parameter count, the
  bands found and where the read stopped. Switch presets in that time
  (ones with different numbers of bands). Written to dev/eqprobe.txt.
--]]

local here = debug.getinfo(1, "S").source:match("@?(.*[\\/])") or ""
local tr = reaper.GetSelectedTrack(0, 0)
if not tr then reaper.MB("Select the track with the ReaEQ first.", "EQ probe", 0) return end
local addr
for i = 0, reaper.TrackFX_GetCount(tr) - 1 do
  local _, n = reaper.TrackFX_GetFXName(tr, i, "")
  if n:find("ReaEQ", 1, true) then addr = i break end
end
if not addr then reaper.MB("No ReaEQ on the selected track.", "EQ probe", 0) return end

local out, last = {}, nil
local t0 = reaper.time_precise()

local function read()
  local np = reaper.TrackFX_GetNumParams(tr, addr)
  local bands, order, stop, master = {}, {}, nil, false
  local i = 0
  while i < 1024 do
    local ok, bt, bi, pt = reaper.TrackFX_GetEQParam(tr, addr, i)
    if not ok then stop = i break end
    if bt == -1 then master = true
    else
      local k = bt .. ":" .. bi
      if not bands[k] then bands[k] = {}; order[#order + 1] = k end
      bands[k][#bands[k] + 1] = pt
    end
    i = i + 1
  end
  local parts = {}
  for _, k in ipairs(order) do
    local bt, bi = k:match("(-?%d+):(%d+)")
    local en = reaper.TrackFX_GetEQBandEnabled(tr, addr, tonumber(bt), tonumber(bi))
    -- ReaEQ's own, by the band's place
    local pos = #parts
    local _, ne = reaper.TrackFX_GetNamedConfigParm(tr, addr, "BANDENABLED" .. pos)
    local _, nt = reaper.TrackFX_GetNamedConfigParm(tr, addr, "BANDTYPE" .. pos)
    parts[#parts + 1] = k .. "(" .. table.concat(bands[k], "") .. (en and "" or ",off")
      .. ",en=" .. tostring(ne) .. ",type=" .. tostring(nt) .. ")"
  end
  local _, preset = reaper.TrackFX_GetPreset(tr, addr, "")
  local _, pname = reaper.TrackFX_GetParamName(tr, addr, stop or 0, "")
  return ("params %d, read stopped at %s (\"%s\"), master %s, %d bands: %s  [preset \"%s\"]"):format(
    np, tostring(stop), pname or "", tostring(master), #order, table.concat(parts, " "), preset or "")
end

local function step()
  local now = reaper.time_precise() - t0
  local s = read()
  if s ~= last then
    out[#out + 1] = ("%6.2f s  %s"):format(now, s)
    last = s
  end
  if now < 15 then reaper.defer(step) return end
  local f = io.open(here .. "eqprobe.txt", "w")
  if f then f:write(table.concat(out, "\n")); f:close() end
  reaper.MB("Written to dev/eqprobe.txt.", "EQ probe", 0)
end
step()
