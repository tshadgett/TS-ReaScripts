-- @noindex
-- Dev probe: how ReaEQ's band parameters read against their 0..1 value.
-- Select a track with ReaEQ on it and run this. Writes dev/eqlaw.txt:
-- for each band parameter, its value now (as GetEQParam and
-- GetParamNormalized read it, and its text), what ReaEQ says it would read
-- at that value and at 0, 0.05 .. 1 (FormatParamValueNormalized), and its
-- link (baseline, scale, offset) when it has one. Changes nothing.

local track = reaper.GetSelectedTrack(0, 0)
if not track then reaper.MB("Select a track with ReaEQ on it.", "EQ law probe", 0) return end
local fx
for i = 0, reaper.TrackFX_GetCount(track) - 1 do
  local _, n = reaper.TrackFX_GetFXName(track, i, "")
  if n:find("ReaEQ") then fx = i break end
end
if not fx then reaper.MB("No ReaEQ on the selected track.", "EQ law probe", 0) return end

local out = {}
local function say(s) out[#out + 1] = s end
local function fmt(p, n)
  local ok, s = reaper.TrackFX_FormatParamValueNormalized(track, fx, p, n, "")
  return ok and s or "?"
end
local function cfg(k)
  local ok, v = reaper.TrackFX_GetNamedConfigParm(track, fx, k)
  return ok and v or "-"
end

say(("REAPER %s   fx %d"):format(reaper.GetAppVersion(), fx))
local i = 0
while i < 200 do
  local ok, bt, bi, pt, nv = reaper.TrackFX_GetEQParam(track, fx, i)
  if not ok then break end
  local _, now = reaper.TrackFX_GetFormattedParamValue(track, fx, i, "")
  local gn = reaper.TrackFX_GetParamNormalized(track, fx, i)
  local _, name = reaper.TrackFX_GetParamName(track, fx, i, "")
  say(("\n%d  %s   type %d band %d param %d"):format(i, name, bt, bi, pt))
  say(("   now: eq %.4f  norm %.4f  text %q  says-at-eq %q"):format(nv, gn, now, fmt(i, nv)))
  local reads = {}
  for k = 0, 20 do reads[#reads + 1] = ("%.2f=%s"):format(k / 20, fmt(i, k / 20)) end
  say("   at: " .. table.concat(reads, "  "))
  if cfg(("param.%d.plink.active"):format(i)) == "1" then
    say(("   link: baseline %s  scale %s  offset %s  from fx %s param %s"):format(
      cfg(("param.%d.mod.baseline"):format(i)), cfg(("param.%d.plink.scale"):format(i)),
      cfg(("param.%d.plink.offset"):format(i)), cfg(("param.%d.plink.effect"):format(i)),
      cfg(("param.%d.plink.param"):format(i))))
  end
  i = i + 1
end

local path = debug.getinfo(1, "S").source:match("^@(.*[\\/])") or ""
local f = io.open(path .. "eqlaw.txt", "w")
if f then f:write(table.concat(out, "\n"), "\n"); f:close() end
reaper.MB("Written to dev/eqlaw.txt", "EQ law probe", 0)
