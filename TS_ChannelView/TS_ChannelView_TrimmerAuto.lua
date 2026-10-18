-- @noindex
-- Not a package of its own: installed by TS_ChannelView.lua's @provides.
--[[
  TS_ChannelView_TrimmerAuto.lua -- Auto trim on each selected track's
  TS_CV Trimmer: the trim set from the track's items, their average on
  the meter's 0 VU and their peaks under its ceiling (inside the time
  selection, when there is one). The items themselves aren't changed.
  Select every track for the whole session.
--]]

local script_dir = debug.getinfo(1, "S").source:match("@?(.*[\\/])") or ""
package.path = script_dir .. "?.lua;" .. package.path

local TR = require("TS_CV_Trimmer")
local TP = require("TS_CV_Taps")

local n = reaper.CountSelectedTracks(0)
if n == 0 then
  reaper.MB("Select the tracks to auto trim.", "TS_CV Trimmer", 0)
  return
end

-- one question for every track with an ARA plugin ahead of its Trimmer
local asked, go = false, true
local function ask(msg)
  if not asked then
    asked = true
    go = reaper.MB(msg .. "\n\n(For every track like this in the selection.)", "Auto trim", 4) == 6
  end
  return go
end

local done, skipped = 0, {}
reaper.Undo_BeginBlock()
for i = 0, n - 1 do
  local tr = reaper.GetSelectedTrack(0, i)
  local t, why = TR.auto_trim(tr, ask, TP.ara_first(tr))
  if t then
    done = done + 1
  elseif why ~= "no Trimmer on this track" then
    local _, name = reaper.GetTrackName(tr)
    skipped[#skipped + 1] = name .. ": " .. why
  end
end
reaper.Undo_EndBlock("Auto trim TS_CV Trimmer on selected tracks", -1)
if done == 0 and #skipped == 0 then
  reaper.MB("None of the selected tracks has a TS_CV Trimmer.", "TS_CV Trimmer", 0)
elseif #skipped > 0 then
  reaper.MB("Trimmed " .. done .. " track(s). Not trimmed:\n\n" .. table.concat(skipped, "\n"), "TS_CV Trimmer", 0)
end
