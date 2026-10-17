-- @noindex
-- Not a package of its own: installed by TS_ChannelView.lua's @provides.
--[[
  TS_ChannelView_OrganiseActions.lua -- opens Organise actions: every
  action bar (ChannelView's drawers, toolbars in their own windows, the
  TCP's two and the web companion's), built and arranged in one place.

  The window itself is the toolbars script's (TS_ChannelView_Toolbars):
  this asks it, and starts it if it isn't running.
--]]

local script_dir = debug.getinfo(1, "S").source:match("@?(.*[\\/])") or ""
package.path = script_dir .. "?.lua;" .. package.path

local C = require("TS_CV_Config")
reaper.SetExtState(C.EXT_SECT, "bars_organise", "1", false)
local t = tonumber(reaper.GetExtState(C.EXT_SECT, "bars_host_alive"))
if t and math.abs(reaper.time_precise() - t) < 3 then return end

-- not running: start it (the Action List knows it once ReaPack installed it)
local file = "TS_ChannelView_Toolbars.lua"
local num = 0
local fh = io.open(reaper.GetResourcePath() .. package.config:sub(1, 1) .. "reaper-kb.ini", "rb")
if fh then
  local txt = fh:read("*a"); fh:close()
  local ok, SU = pcall(require, "TS_CV_Startup")
  local id = ok and SU.kb_find(txt, file)
  if id then num = reaper.NamedCommandLookup(id) end
end
if num == 0 and reaper.AddRemoveReaScript then
  num = reaper.AddRemoveReaScript(true, 0, script_dir .. file, true) or 0
end
if num > 0 then
  reaper.Main_OnCommand(num, 0)
else
  reaper.MB("Couldn't find TS_ChannelView_Toolbars.lua beside this script.", "ChannelView", 0)
end
