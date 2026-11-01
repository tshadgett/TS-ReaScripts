-- @noindex
-- dev tool, not released: the selected track's row as ChannelView builds it -> dev/row.txt
local script_dir = debug.getinfo(1, "S").source:match("@?(.*[\\/])") or ""
package.path = script_dir:gsub("dev[\\/]$", "") .. "?.lua;" .. package.path
local out = {}
local ok, err = pcall(function()
local T = require("TS_CV_FXTree")
local MD = require("TS_CV_Mod")
local TP = require("TS_CV_Taps")
local CMP = require("TS_CV_Compare")
local tr = reaper.GetSelectedTrack(0, 0)
local function say(x) out[#out + 1] = x end
local function dump(tag, list)
  say(tag .. ": " .. #list)
  for i, fx in ipairs(list) do say(("  %d %s %s %s"):format(i, fx.path, fx.name, fx.guid)) end
  for _, n in ipairs(list.tree or {}) do say(("  node %s %s first=%s last=%s"):format(table.concat(n.path, "."), n.name, tostring(n.first), tostring(n.last))) end
end
local full = T.collect(tr)
dump("collect", full)
local l = MD.strip(tr, full); dump("mod strip", l)
if not TP.probes_shown() then l = TP.strip_probes(tr, l); dump("probe strip", l) end
l = CMP.strip(tr, l); dump("compare strip", l)
end)
if not ok then out[#out + 1] = "ERROR " .. tostring(err) end
local f = io.open(script_dir .. "row.txt", "w")
if f then f:write(table.concat(out, "\n") .. "\n"); f:close() end
