-- @noindex
--[[
  TS_DrumToolbox_Clear.lua -- remove the hit map from the selected tracks:
  every DrumToolbox take marker (other markers stay) and the track's
  DrumToolbox flag. One undo point.
]]

local r = reaper
local dir = debug.getinfo(1, "S").source:match("^@?(.*[\\/])") or ""
package.path = dir .. "?.lua;" .. package.path
local DT = require("TS_DrumToolbox_core")

local n = r.CountSelectedTracks(0)
if n == 0 then return end
r.Undo_BeginBlock2(0)
r.PreventUIRefresh(1)
for i = 0, n - 1 do DT.clear_track(r.GetSelectedTrack(0, i)) end
r.PreventUIRefresh(-1)
r.UpdateArrange()
r.Undo_EndBlock2(0, "TS DrumToolbox: clear hit map", -1)
