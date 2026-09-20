--========================================================
-- @noindex
-- @title TS_TA_QuietProbes
-- @description Track Analyser -- make the probes visually recede
-- @author Tim Shadgett (with Claude)
-- @version 1.0.0
-- MIT licence -- see LICENSE in the TS-ReaScripts repository.
--========================================================
--
-- Run it with tracks selected. It renames every TS_TrackProbe it finds to a
-- single dot, so the pair stops competing for attention in the FX chain.
-- Run it again to put the real names back.
--
-- Nothing is inserted, removed, reordered or bypassed. The only thing
-- that changes is the label REAPER shows.
--
-- WHY RENAMING RATHER THAN HIDING
--   REAPER has no hidden-FX flag, and reaching into the FX chain window
--   to hide rows is how this project already crashed REAPER once: the
--   Docked Plugin Display reparented a plugin's child window and did not
--   return it, and every FX chain opened afterwards took REAPER down.
--   A label is a label.
--
-- WHY IT MIGHT DO NOTHING, AND WHY THAT IS THE RIGHT OUTCOME
--   The rename goes through TrackFX_SetNamedConfigParm with the key
--   "renamed_name". I could not confirm that key from REAPER's own
--   documentation, so the script does not assume it: it writes to one
--   probe, reads the value back, and only proceeds if the value stuck.
--   If it did not, nothing is changed and it says so, rather than
--   spraying writes at config keys on your plugins to see what happens.
--
-- WHY IT CHECKS THE PANEL STILL WORKS AFTERWARDS
--   TS_TA_Chain identifies a probe by ANY of the names REAPER will admit to
--   -- the displayed one, fx_name, original_name, fx_ident -- precisely
--   so a renamed plugin is still findable. That is the intent; this
--   verifies it in fact. Every track is re-resolved after renaming and
--   the whole thing is rolled back if the pair can no longer be found.
--========================================================

local r = reaper

local sep  = package.config:sub(1, 1)
local here = ({ r.get_action_context() })[2]:match("^(.*)[\\/]") or "."

local TA
do
  local ok, m = pcall(dofile, here .. sep .. "TS_TA_Chain.lua")
  if ok and type(m) == "table" and type(m.walk) == "function" then TA = m end
end
if not TA then
  r.ShowMessageBox("TS_TA_Chain.lua is not next to this script.",
    "Track Analyser", 0)
  return
end

local KEY   = "renamed_name"
local QUIET = "\u{00B7}"          -- a middle dot: present, but silent

----------------------------------------------------------
-- probes on the selected tracks
----------------------------------------------------------

local sel = r.CountSelectedTracks(0)
if sel == 0 then
  r.ShowMessageBox("Select the track or tracks whose probes you want quietened.",
    "Track Analyser", 0)
  return
end

local found = {}
for t = 0, sel - 1 do
  local tr = r.GetSelectedTrack(0, t)
  local chain = TA.walk(tr, {})
  for _, fxe in ipairs(chain) do
    if not fxe.isContainer then
      local isProbe = false
      for _, n in ipairs(fxe.names or {}) do
        if n:find("TS_TrackProbe", 1, true) then isProbe = true break end
      end
      if isProbe then
        found[#found + 1] = { tr = tr, idx = fxe.idx, shown = fxe.name }
      end
    end
  end
end

if #found == 0 then
  r.ShowMessageBox("No TS_TrackProbe found on the selected tracks.",
    "Track Analyser", 0)
  return
end

----------------------------------------------------------
-- does this REAPER support the key at all?
--
-- Established by writing to the first probe and reading it back, then
-- putting it straight back the way it was. One plugin, one round trip,
-- and no assumption carried forward.
----------------------------------------------------------

local probe = found[1]
local hadOk, had = r.TrackFX_GetNamedConfigParm(probe.tr, probe.idx, KEY)
local before = (hadOk and had) or ""

r.TrackFX_SetNamedConfigParm(probe.tr, probe.idx, KEY, "TA_TEST")
local gotOk, got = r.TrackFX_GetNamedConfigParm(probe.tr, probe.idx, KEY)
r.TrackFX_SetNamedConfigParm(probe.tr, probe.idx, KEY, before)

if not (gotOk and got == "TA_TEST") then
  r.ShowMessageBox(
    ("This REAPER does not accept \"%s\", so the probes cannot be renamed " ..
     "from a script.\n\nNothing was changed. You can still rename them by " ..
     "hand: right-click the FX in the chain and choose Rename."):format(KEY),
    "Track Analyser", 0)
  return
end

-- Already quiet? Then this run is the undo.
local restoring = (before == QUIET)

----------------------------------------------------------
-- do it
----------------------------------------------------------

r.Undo_BeginBlock()
r.PreventUIRefresh(1)

-- Kept so a failed verification can put every one of them back exactly
-- as it was, including probes that were already renamed by hand.
local prior = {}
for i, p in ipairs(found) do
  local ok, v = r.TrackFX_GetNamedConfigParm(p.tr, p.idx, KEY)
  prior[i] = (ok and v) or ""
  r.TrackFX_SetNamedConfigParm(p.tr, p.idx, KEY, restoring and "" or QUIET)
end

-- THE CHECK THAT MATTERS. A rename the panel cannot see through is worse
-- than a cluttered chain.
local broken = {}
for t = 0, sel - 1 do
  local tr = r.GetSelectedTrack(0, t)
  local rig = TA.find(tr)
  if not rig or not rig.post then
    local _, nm = r.GetSetMediaTrackInfo_String(tr, "P_NAME", "", false)
    broken[#broken + 1] = (nm ~= "" and nm) or ("track " .. (t + 1))
  end
end

if #broken > 0 then
  for i, p in ipairs(found) do
    r.TrackFX_SetNamedConfigParm(p.tr, p.idx, KEY, prior[i])
  end
end

r.PreventUIRefresh(-1)
r.TrackList_AdjustWindows(false)
r.UpdateArrange()
r.Undo_EndBlock("Track Analyser: rename probes", -1)

r.ShowConsoleMsg("\nTRACK ANALYSER -- QUIET PROBES\n")
if #broken > 0 then
  r.ShowConsoleMsg(
    ("Rolled back: after renaming, the panel could no longer find the " ..
     "probes on %d track(s):\n"):format(#broken))
  for _, n in ipairs(broken) do r.ShowConsoleMsg("   " .. n .. "\n") end
  r.ShowConsoleMsg("Every probe has been put back exactly as it was.\n")
else
  r.ShowConsoleMsg(("%s %d probe(s) across %d track(s).\n"):format(
    restoring and "Restored" or "Quietened", #found, sel))
  r.ShowConsoleMsg("Run it again to " ..
    (restoring and "quieten them." or "put the names back.") .. "\n")
end
