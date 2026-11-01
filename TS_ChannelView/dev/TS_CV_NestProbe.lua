-- @noindex
-- dev tool: a new track "Nest test" with ReaEQ in a container in a
-- container (and a second level of nesting on a second ReaEQ), selected,
-- so ChannelView shows it. Writes the tree to dev/nest.txt.
local dev = debug.getinfo(1, "S").source:match("@?(.*[\\/])") or ""
local root = dev:gsub("[\\/]dev[\\/]$", "") .. "/"
package.path = root .. "?.lua;" .. package.path
local T = require("TS_CV_FXTree")
reaper.Undo_BeginBlock()
local n = reaper.CountTracks(0)
reaper.InsertTrackAtIndex(n, true)
local tr = reaper.GetTrack(0, n)
reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", "Nest test", true)
reaper.TrackFX_AddByName(tr, "ReaEQ", false, -1)
local a = T.wrap(tr, { 0 })
local b = T.wrap(tr, { 0 })
reaper.SetOnlyTrackSelected(tr)
reaper.Undo_EndBlock("Nest test track", -1)
local f = io.open(dev .. "nest.txt", "w")
f:write(("wrap1 %s wrap2 %s\n"):format(tostring(a), tostring(b)))
for _, e in ipairs(T.collect(tr)) do
  f:write(("%s  addr %d  path %s  container %s\n"):format(e.name or "?", e.addr or -1,
    table.concat(e.path_t or {}, "."), tostring(e.is_container)))
end
f:close()
