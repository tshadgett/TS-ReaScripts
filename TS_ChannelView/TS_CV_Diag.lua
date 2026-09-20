-- @noindex
-- Not a package of its own: installed by TS_ChannelView.lua's @provides.
--[[
  TS_CV_Diag.lua -- dump what REAPER reports about the selected track's FX.

  Run it from the action list with a track selected. Everything goes to the
  ReaScript console. Use it to settle questions like "is this parameter
  list short because the script capped it, or because REAPER did?" --
  ChannelView itself imposes no limit anywhere, so if a count looks low
  here, it's what REAPER is reporting.
--]]

local script_dir = debug.getinfo(1, "S").source:match("@?(.*[\\/])") or ""
package.path = script_dir .. "?.lua;" .. package.path

local U  = require("TS_CV_Util")
local T  = require("TS_CV_FXTree")
local IX = require("TS_CV_FXIndex")

local out = {}
local function w(fmt, ...) out[#out + 1] = select("#", ...) > 0 and fmt:format(...) or fmt end

local track = reaper.GetSelectedTrack2(0, 0, true)
if not track then
  reaper.ShowConsoleMsg("TS_CV_Diag: select a track first.\n")
  return
end

local _, tname = reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
w("ChannelView diagnostics")
w("REAPER %s   ReaImGui %s", reaper.GetAppVersion(),
  reaper.ImGui_GetBuiltinPath and "present" or "MISSING")
w("track: %s", tname ~= "" and tname or "(unnamed)")
w(("="):rep(72))

local chain = T.collect(track)
w("%d leaf FX in chain (containers expanded)\n", #chain)

for i, fx in ipairs(chain) do
  local n = reaper.TrackFX_GetNumParams(track, fx.addr)
  local own = U.own_param_count(track, fx.addr)
  w("[%d] %s", i, fx.name)
  w("     clean name    : %s", U.clean_fx_name(fx.name))
  w("     layout key    : %s", U.plugin_key(fx.name))
  w("     address       : %d   path %s   %s", fx.addr, fx.path,
    fx.is_top_level and "top level" or ("nested, depth " .. fx.depth))
  w("     GetNumParams  : %d   (plugin's own: %d, REAPER's tail: %d)",
    n, own, n - own)

  -- Walk every index REAPER claims exists and note any that misbehave,
  -- which is what a plugin with a partially-exposed parameter list would
  -- look like from here.
  local empty, errored = 0, 0
  for p = 0, n - 1 do
    local ok, nm = pcall(reaper.TrackFX_GetParamName, track, fx.addr, p, "")
    if not ok then errored = errored + 1
    elseif U.trim(tostring(nm)) == "" then empty = empty + 1 end
  end
  if empty > 0 or errored > 0 then
    w("     ODD           : %d unnamed, %d failed to read", empty, errored)
  end

  -- first and last few, so a truncated list is obvious at a glance
  local function show(p)
    local _, nm = reaper.TrackFX_GetParamName(track, fx.addr, p, "")
    local _, val = reaper.TrackFX_GetFormattedParamValue(track, fx.addr, p, "")
    w("       %4d  %-32s %s", p, nm or "", val or "")
  end
  local head = math.min(n, 6)
  for p = 0, head - 1 do show(p) end
  if n > head + 6 then
    w("       ...   (%d more)", n - head - 6)
    for p = n - 6, n - 1 do show(p) end
  elseif n > head then
    for p = head, n - 1 do show(p) end
  end
  w("")
end

-- ---------------------------------------------------------------------
-- The add-plugin index: how much of the installed set REAPER's own
-- metadata actually accounts for. If "tagged by REAPER" is far below the
-- installed count, the key matching in TS_CV_FXIndex.norm_key isn't lining
-- up with the identifiers EnumInstalledFX hands back -- the sample of
-- unmatched idents below is what to look at.
w(("="):rep(72))
w("add-plugin index")

local list, i = {}, 0
while true do
  local ok, name, ident = reaper.EnumInstalledFX(i)
  if not ok then break end
  if name and ident and name ~= "" then
    list[#list + 1] = { name = name, ident = ident,
                        short = U.clean_fx_name(name),
                        vendor = U.fx_vendor(name) or "" }
  end
  i = i + 1
  if i > 30000 then break end
end

local devs, cats, folds = IX.build(list)
local s2 = IX.stats()
w("  installed FX        : %d", #list)
w("  tagged by REAPER    : %d  (%.0f%%)", s2.resolved,
  #list > 0 and (s2.resolved / #list * 100) or 0)
w("  developer entries   : %d in reaper-fxtags.ini", s2.tagged)
w("  developers in use   : %d", #devs)
w("  categories in use   : %d", #cats)
w("  FX folders in use   : %d of %d", #folds, s2.folders)

local with_dev, no_dev = 0, {}
for _, e in ipairs(list) do
  if e.dev then with_dev = with_dev + 1
  elseif #no_dev < 12 then no_dev[#no_dev + 1] = e end
end
w("  resolved a developer: %d  (tag, or parsed from the name)", with_dev)
if #no_dev > 0 then
  w("  a few with none:")
  for _, e in ipairs(no_dev) do
    w("       %-44s key=%s", U.truncate(e.name, 44), IX.norm_key(e.ident))
  end
end

w("")
w("  first few idents, for checking the key matching:")
for k = 1, math.min(6, #list) do
  w("       %-40s -> %s", U.truncate(list[k].ident, 40), IX.norm_key(list[k].ident))
end
w("")

reaper.ShowConsoleMsg(table.concat(out, "\n") .. "\n")
