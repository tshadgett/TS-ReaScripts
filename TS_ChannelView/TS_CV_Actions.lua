-- @noindex
-- Not a package of its own: installed by TS_ChannelView.lua's @provides.
--[[
  TS_CV_Actions.lua -- finding REAPER's own actions by name.

  A numeric command id written down from memory is a guess: ids differ
  between REAPER versions for some actions, and a wrong one runs
  something else entirely, silently. So actions are looked up by their
  name in the Main section of the Action List, once, and cached; the
  number is only a fallback for when the lookup API isn't there.

  Uses kbd_enumerateActions (REAPER's own), or SWS's CF_EnumerateActions.
--]]

local AC = {}

local cache = {}      -- lower-case name -> id, or false when not found

local function scan(want)
  local sec = reaper.SectionFromUniqueID and reaper.SectionFromUniqueID(0)
  if reaper.kbd_enumerateActions and sec then
    local i = 0
    while true do
      local id, name = reaper.kbd_enumerateActions(sec, i)
      if not id or id <= 0 then break end
      if name and name:lower() == want then return id end
      i = i + 1
    end
  end
  if reaper.CF_EnumerateActions then
    local i = 0
    while true do
      local id, name = reaper.CF_EnumerateActions(0, i, "")
      if not id or id <= 0 then break end
      if name and name:lower() == want then return id end
      i = i + 1
    end
  end
  return nil
end

-- The command id of the Main-section action called `name` (exactly, case
-- aside), or `fallback` when it can't be found. nil if neither.
function AC.find(name, fallback)
  local want = name:lower()
  local hit = cache[want]
  if hit == nil then
    hit = scan(want) or false
    cache[want] = hit
  end
  return hit or fallback
end

-- Runs it; false when there was nothing to run.
function AC.run(name, fallback)
  local id = AC.find(name, fallback)
  if not id then return false end
  reaper.Main_OnCommand(id, 0)
  return true
end

-- Runs it on `track` alone -- for REAPER's actions that work on the
-- selected tracks -- and puts the selection back afterwards, as one undo
-- point called `undo`.
function AC.run_on_track(track, name, fallback, undo)
  local id = AC.find(name, fallback)
  if not id or not track then return false end
  local sel = {}
  for i = 0, reaper.CountSelectedTracks2(0, true) - 1 do
    sel[#sel + 1] = reaper.GetSelectedTrack2(0, i, true)
  end
  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)
  reaper.SetOnlyTrackSelected(track)
  reaper.Main_OnCommand(id, 0)
  reaper.Main_OnCommand(40297, 0)                 -- Track: Unselect all tracks
  for _, t in ipairs(sel) do
    if reaper.ValidatePtr2(0, t, "MediaTrack*") then reaper.SetTrackSelected(t, true) end
  end
  reaper.PreventUIRefresh(-1)
  reaper.Undo_EndBlock(undo or name, -1)
  reaper.TrackList_AdjustWindows(false)
  reaper.UpdateArrange()
  return true
end

return AC
