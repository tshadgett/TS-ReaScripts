--========================================================
-- @noindex
-- @title TS_TA_InsertProbes
-- @description Track Analyser -- put a probe at each end of the chain
-- @author Tim Shadgett (with Claude)
-- @version 1.0.0
-- MIT licence -- see LICENSE in the TS-ReaScripts repository.
--========================================================
--
-- Run it with tracks selected. For each one it makes sure there is a
-- TS_TrackProbe in the FIRST slot and another in the LAST, and sets each one's
-- Position so the panel knows which is which. Both are left idle -- the
-- panel arms the pair on whatever track you select, and an idle probe does
-- no FFT and writes nothing.
--
-- IT ONLY EVER ADDS. Nothing is removed, reordered or replaced, and a track
-- that already has a pair is left alone -- including a pair living inside a
-- container, which is what a baked track template gives you. Such a track is
-- skipped rather than silently double-probed.
--
-- IT IS QUIET WHEN IT WORKS. The FX chains change in front of you and there
-- is an undo point, so a console report of what you can already see is just
-- noise. You hear from it in the two cases you cannot see: something failed,
-- or there was nothing to do at all.
--
-- WHY THE PANEL DOES NOT DO THIS ITSELF
--   Inserting a plugin rebuilds the FX chain, which is not something that
--   should happen because you clicked a track. This is the deliberate,
--   run-it-yourself version.
--========================================================

local r = reaper

local sep  = package.config:sub(1, 1)
local here = ({ r.get_action_context() })[2]:match("^(.*)[\\/]") or "."

-- TS_TA_Chain is used only to see what is already there -- the walk understands
-- containers, and a probe inside one still counts as a probe.
local TA
do
  local ok, m = pcall(dofile, here .. sep .. "TS_TA_Chain.lua")
  if ok and type(m) == "table" and type(m.find) == "function" then TA = m end
end

local PROBE = "TS_TrackProbe"

-- HOW REAPER IS ASKED FOR A JSFX
--   The name that resolves depends on where the effect sits and how REAPER
--   catalogued it, and a wrong guess here does not fail loudly -- it adds
--   nothing and returns -1. So the candidates are tried in order and the
--   first one that actually instantiates wins, which is also what tells us
--   the file is installed at all.
--
--   AND NOTHING HERE ASSUMES WHERE IT WAS INSTALLED. REAPER resolves a JSFX
--   path relative to Effects/. ReaPack puts scripts under
--   Scripts/<repo>/<category>/ and effects under Effects/<repo>/<category>/,
--   so the tail after Scripts/ is identical on both sides -- and it is not
--   the same tail for someone who installed by hand. Take it from this
--   script's own path instead of spelling out one folder that is only right
--   for one kind of install.
local tail = here:gsub("\\", "/"):match("[Ss]cripts/(.+)$")
if tail then tail = tail:gsub("/+$", "") end

local NAMES = {}
if tail and tail ~= "" then NAMES[#NAMES + 1] = tail .. "/" .. PROBE .. ".jsfx" end
NAMES[#NAMES + 1] = PROBE .. ".jsfx"
NAMES[#NAMES + 1] = "JS: " .. PROBE
NAMES[#NAMES + 1] = PROBE

local resolved = nil

-- Adds a probe at the end of the track's chain and returns its index, or
-- nil plus a reason.
local function addProbe(tr)
  local list = resolved and { resolved } or NAMES
  for _, nm in ipairs(list) do
    local idx = r.TrackFX_AddByName(tr, nm, false, -1)
    if idx and idx >= 0 then
      resolved = nm
      return idx
    end
  end
  return nil, "REAPER could not instantiate " .. PROBE .. ".jsfx -- is it " ..
              "installed under Effects/?"
end

local function isProbe(tr, idx)
  local ok, nm = r.TrackFX_GetFXName(tr, idx, "")
  return ok and nm and nm:find(PROBE, 1, true) ~= nil
end

-- Position 0 = pre, 1 = post. Publish 0 = idle.
local function configure(tr, idx, role)
  r.TrackFX_SetParam(tr, idx, 0, role)
  r.TrackFX_SetParam(tr, idx, 1, 0)
end

local sel = r.CountSelectedTracks(0)
if sel == 0 then
  r.ShowMessageBox("Select the track or tracks you want probed.",
    "Track Analyser", 0)
  return
end

r.Undo_BeginBlock()
r.PreventUIRefresh(1)

local added, failed = {}, {}

for t = 0, sel - 1 do
  local tr = r.GetSelectedTrack(0, t)
  local _, name = r.GetSetMediaTrackInfo_String(tr, "P_NAME", "", false)
  if name == "" then name = ("track %d"):format(t + 1) end

  -- A pair already present anywhere -- top level or inside a container --
  -- means this track is already set up, and adding more would give the
  -- panel three probes to choose between.
  local have = TA and select(1, TA.find(tr)) or nil
  if have and have.pre and have.post then
    -- Already set up. Leave it alone: a third probe would give the panel a
    -- choice it has no way to make.
  else
    local n = r.TrackFX_GetCount(tr)
    local didSomething = false

    -- PRE: added at the end, then moved to the front. Adding directly at a
    -- position needs an encoded index whose exact form I could not confirm;
    -- moving is documented, does the same thing, and cannot land the plugin
    -- somewhere unintended.
    if n == 0 or not isProbe(tr, 0) then
      local idx, err = addProbe(tr)
      if not idx then
        failed[#failed + 1] = name .. ": " .. err
        goto continue
      end
      r.TrackFX_CopyToTrack(tr, idx, tr, 0, true)
      configure(tr, 0, 0)
      didSomething = true
    end

    -- POST: whatever is last now. If the pre probe we just added is also
    -- the last thing on the track, the chain is empty and it still needs a
    -- partner behind it.
    n = r.TrackFX_GetCount(tr)
    if n == 1 or not isProbe(tr, n - 1) then
      local idx, err = addProbe(tr)
      if not idx then
        failed[#failed + 1] = name .. ": " .. err
        goto continue
      end
      configure(tr, idx, 1)
      didSomething = true
    end

    if didSomething then added[#added + 1] = name end
  end
  ::continue::
end

r.PreventUIRefresh(-1)
r.TrackList_AdjustWindows(false)
r.UpdateArrange()
r.Undo_EndBlock("Track Analyser: insert probes", -1)

-- Something went wrong on at least one track. This is the case worth
-- interrupting for: usually the JSFX is not installed, and every track
-- failed for the same reason.
if #failed > 0 then
  local lines = { ("Could not probe %d of %d track(s):"):format(#failed, sel), "" }
  for _, n in ipairs(failed) do lines[#lines + 1] = "   " .. n end
  if #added > 0 then
    lines[#lines + 1] = ""
    lines[#lines + 1] = ("%d track(s) were probed successfully."):format(#added)
  end
  if not resolved then
    lines[#lines + 1] = ""
    lines[#lines + 1] = "REAPER could not instantiate the probe at all. Check that"
    lines[#lines + 1] = "TS_TrackProbe.jsfx is in Effects/TS_TrackAnalyser/."
  end
  r.ShowMessageBox(table.concat(lines, "\n"), "Track Analyser", 0)

-- Nothing added and nothing broken: every selected track was already set
-- up. Worth one line, because otherwise running this looks like it did
-- nothing and you cannot tell whether it worked.
elseif #added == 0 then
  r.ShowMessageBox(
    ("Nothing to do -- all %d selected track(s) already have a probe pair.")
      :format(sel),
    "Track Analyser", 0)
end

-- Success is silent.
