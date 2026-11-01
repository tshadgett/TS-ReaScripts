-- @noindex
-- Dev probe: how REAPER applies a parameter link, measured. Select a track
-- whose plugin has linked parameters (with the modulator moving) and run.
-- For 3 seconds it reads every linked parameter of the track's plugins and
-- the parameter driving it, then writes dev/linkprobe.txt: the link's
-- settings and each reading. Changes nothing.

local track = reaper.GetSelectedTrack(0, 0)
if not track then reaper.MB("Select a track first.", "Link probe", 0) return end

local links = {}
for fx = 0, reaper.TrackFX_GetCount(track) - 1 do
  for p = 0, reaper.TrackFX_GetNumParams(track, fx) - 1 do
    local ok, on = reaper.TrackFX_GetNamedConfigParm(track, fx, ("param.%d.plink.active"):format(p))
    if ok and on == "1" then
      local function cfg(k)
        local _, v = reaper.TrackFX_GetNamedConfigParm(track, fx, ("param.%d."):format(p) .. k)
        return v
      end
      local _, name = reaper.TrackFX_GetParamName(track, fx, p, "")
      local env = reaper.GetFXEnvelope(track, fx, p, false)
      links[#links + 1] = { fx = fx, p = p, name = name, env = env and reaper.CountEnvelopePoints(env) or -1,
        base = cfg("mod.baseline"), scale = cfg("plink.scale"), off = cfg("plink.offset"),
        sfx = tonumber(cfg("plink.effect")), sp = tonumber(cfg("plink.param")),
        mod = cfg("mod.active"), lfo = cfg("lfo.active"), acs = cfg("acs.active"), vis = cfg("mod.visible"),
        rows = {} }
    end
  end
end
if #links == 0 then reaper.MB("No linked parameters on this track.", "Link probe", 0) return end

local t0 = reaper.time_precise()
local function step()
  local t = reaper.time_precise() - t0
  for _, l in ipairs(links) do
    local v = reaper.TrackFX_GetParamNormalized(track, l.fx, l.p)
    local raw, mn, mx = reaper.TrackFX_GetParam(track, l.fx, l.p)
    local _, txt = reaper.TrackFX_GetFormattedParamValue(track, l.fx, l.p, "")
    local _, says = reaper.TrackFX_FormatParamValueNormalized(track, l.fx, l.p, v, "")
    local s = (l.sfx and l.sp) and reaper.TrackFX_GetParamNormalized(track, l.sfx, l.sp) or -1
    l.rows[#l.rows + 1] = ("%.3f  src %.4f  param %.4f  raw %.4f [%.3f..%.3f]  text %q  says-at-norm %q"):format(
      t, s, v, raw or -1, mn or 0, mx or 0, txt or "", says or "")
  end
  if t < 3 then reaper.defer(step) return end
  local out = { "REAPER " .. reaper.GetAppVersion() }
  for _, l in ipairs(links) do
    out[#out + 1] = ("\nfx %d param %d %s   baseline %s scale %s offset %s  from fx %s param %s  mod %s lfo %s acs %s  env points %d"):format(
      l.fx, l.p, l.name, l.base, l.scale, l.off, tostring(l.sfx), tostring(l.sp), l.mod, l.lfo, l.acs, l.env)
    for i = 1, #l.rows, 3 do out[#out + 1] = "   " .. l.rows[i] end
  end
  local path = debug.getinfo(1, "S").source:match("^@(.*[\\/])") or ""
  local f = io.open(path .. "linkprobe.txt", "w")
  if f then f:write(table.concat(out, "\n"), "\n"); f:close() end
  reaper.MB("Written to dev/linkprobe.txt", "Link probe", 0)
end
step()
