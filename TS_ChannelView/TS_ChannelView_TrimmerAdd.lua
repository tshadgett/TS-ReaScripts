-- @noindex
-- Not a package of its own: installed by TS_ChannelView.lua's @provides.
--[[
  TS_ChannelView_TrimmerAdd.lua -- puts a TS_CV Trimmer first in the
  chain of each selected track that hasn't one: after an ARA plugin in
  the first slot, the pre probe and ChannelView's modulators.
--]]

local script_dir = debug.getinfo(1, "S").source:match("@?(.*[\\/])") or ""
package.path = script_dir .. "?.lua;" .. package.path

local TR = require("TS_CV_Trimmer")
local TP = require("TS_CV_Taps")

local n = reaper.CountSelectedTracks(0)
if n == 0 then
  reaper.MB("Select the tracks to add the Trimmer to.", "TS_CV Trimmer", 0)
  return
end
reaper.Undo_BeginBlock()
reaper.PreventUIRefresh(1)
local missing = false
for i = 0, n - 1 do
  local tr = reaper.GetSelectedTrack(0, i)
  if not TR.insert(tr, TP.ara_first(tr)) then missing = true end
end
reaper.PreventUIRefresh(-1)
reaper.Undo_EndBlock("Add TS_CV Trimmer to selected tracks", -1)
if missing then
  reaper.MB("Couldn't find the TS_CV Trimmer plugin (TS_CV_Trimmer.jsfx).\n" ..
            "Reinstalling ChannelView from ReaPack puts it back.", "TS_CV Trimmer", 0)
end
