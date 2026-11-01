-- @noindex
-- Dev probe: REAPER's parameter link law, measured. Select a track with a
-- linked parameter whose modulator is moving (an LFO) and run. It takes the
-- first linked parameter, sets its baseline and offset to a few test
-- values in turn (under a second each), reads the source and the
-- parameter, then puts the link back as it was. Writes dev/linklaw.txt:
-- for each setting, the fit value = a + b * source.

local track = reaper.GetSelectedTrack(0, 0)
if not track then reaper.MB("Select a track first.", "Link law", 0) return end

local L
for fx = 0, reaper.TrackFX_GetCount(track) - 1 do
  for p = 0, reaper.TrackFX_GetNumParams(track, fx) - 1 do
    local ok, on = reaper.TrackFX_GetNamedConfigParm(track, fx, ("param.%d.plink.active"):format(p))
    if ok and on == "1" then L = { fx = fx, p = p } break end
  end
  if L then break end
end
if not L then reaper.MB("No linked parameter on this track.", "Link law", 0) return end

local function key(k) return ("param.%d."):format(L.p) .. k end
local function get(k) local _, v = reaper.TrackFX_GetNamedConfigParm(track, L.fx, key(k)); return v end
local function set(k, v) reaper.TrackFX_SetNamedConfigParm(track, L.fx, key(k), tostring(v)) end
local orig = { base = get("mod.baseline"), off = get("plink.offset"), scale = get("plink.scale") }
local sfx, sp = tonumber(get("plink.effect")), tonumber(get("plink.param"))
local _, name = reaper.TrackFX_GetParamName(track, L.fx, L.p, "")
local own = reaper.TrackFX_GetParamNormalized(track, L.fx, L.p)

local TESTS = { { 0.2, 0 }, { 0.4, 0 }, { 0.2, -0.5 }, { 0.4, -0.5 }, { 0.6, -0.5 }, { 0.4, 0.25 } }
local out = { ("REAPER %s   fx %d param %d %s   was: baseline %s offset %s scale %s   from fx %s param %s"):format(
  reaper.GetAppVersion(), L.fx, L.p, name, orig.base, orig.off, orig.scale, tostring(sfx), tostring(sp)) }
local i, t_start, rows = 0, 0, nil

local function fit(r)
  local n, sx, sy, sxx, sxy = #r, 0, 0, 0, 0
  for _, q in ipairs(r) do sx, sy, sxx, sxy = sx + q[1], sy + q[2], sxx + q[1] * q[1], sxy + q[1] * q[2] end
  local d = n * sxx - sx * sx
  if n < 3 or math.abs(d) < 1e-9 then return nil end
  local b = (n * sxy - sx * sy) / d
  return (sy - b * sx) / n, b
end

local function next_test()
  if rows then
    local a, b = fit(rows)
    local lo, hi = 1, 0
    for _, q in ipairs(rows) do lo, hi = math.min(lo, q[1]), math.max(hi, q[1]) end
    out[#out + 1] = ("baseline %.2f offset %.2f scale %s:  value = %s + %s * source   (source %.2f..%.2f, %d reads)"):format(
      TESTS[i][1], TESTS[i][2], orig.scale, a and ("%.4f"):format(a) or "?", b and ("%.4f"):format(b) or "?", lo, hi, #rows)
  end
  i = i + 1
  if i > #TESTS then
    set("mod.baseline", orig.base); set("plink.offset", orig.off); set("plink.scale", orig.scale)
    out[#out + 1] = ("put back: baseline %s offset %s scale %s"):format(get("mod.baseline"), get("plink.offset"), get("plink.scale"))
    local path = debug.getinfo(1, "S").source:match("^@(.*[\\/])") or ""
    local f = io.open(path .. "linklaw.txt", "w")
    if f then f:write(table.concat(out, "\n"), "\n"); f:close() end
    reaper.MB("Written to dev/linklaw.txt (the link is back as it was)", "Link law", 0)
    return
  end
  set("mod.baseline", TESTS[i][1]); set("plink.offset", TESTS[i][2])
  rows, t_start = {}, reaper.time_precise()
  local function read()
    local t = reaper.time_precise() - t_start
    if t > 0.15 then
      rows[#rows + 1] = { reaper.TrackFX_GetParamNormalized(track, sfx, sp), reaper.TrackFX_GetParamNormalized(track, L.fx, L.p) }
    end
    if t < 1.2 then reaper.defer(read) else next_test() end
  end
  reaper.defer(read)
end
out[#out + 1] = ("its own value before: %.4f"):format(own)
next_test()
