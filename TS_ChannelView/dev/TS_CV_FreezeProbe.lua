-- @noindex
-- Dev probe (not released): the selected track's chunk outline -- every
-- <BLOCK opening line and its depth, without plugin state data -- and what
-- TS_CV_Freeze reads from it. Writes dev/freeze_probe.txt beside this
-- script. Run from the Actions list with a frozen track selected.

local dir = debug.getinfo(1, "S").source:match("^@(.*[/\\])") or ""
package.path = dir .. "../?.lua;" .. package.path
local FZ = require("TS_CV_Freeze")
local U = require("TS_CV_Util")

local tr = reaper.GetSelectedTrack(0, 0)
if not tr then reaper.ShowMessageBox("Select a frozen track first.", "Freeze probe", 0) return end
local _, chunk = reaper.GetTrackStateChunk(tr, "", false)
local out, depth = {}, 0
for line in chunk:gmatch("[^\r\n]+") do
  if line:match("^%s*<") then
    depth = depth + 1
    out[#out + 1] = ("%d %s"):format(depth, line:sub(1, 160))
  elseif line:match("^%s*>%s*$") then
    depth = depth - 1
  elseif line:match("^%s*%u[%u_]+") and depth <= 3 then
    out[#out + 1] = ("%d   %s"):format(depth, line:sub(1, 100))
  end
end
local st = FZ.parse(chunk, U.clean_fx_name)
out[#out + 1] = ""
out[#out + 1] = ("Read: %d level(s): %s"):format(st.levels, table.concat(st.fx, " | "))
out[#out + 1] = ("Live FX now: %d"):format(reaper.TrackFX_GetCount(tr))
local f = io.open(dir .. "freeze_probe.txt", "w")
if f then f:write(table.concat(out, "\n")); f:close() end
reaper.ShowMessageBox("Written: " .. dir .. "freeze_probe.txt", "Freeze probe", 0)
