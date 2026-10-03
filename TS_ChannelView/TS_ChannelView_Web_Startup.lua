-- @noindex
-- Not a package of its own: installed by TS_ChannelView.lua's @provides.
--[[
  TS_ChannelView_Web_Startup.lua -- start the web companion with REAPER, or
  stop doing so.

  An action for the Action List (or a toolbar): it says whether
  TS_ChannelView_Web.lua is set to start with REAPER and offers to switch
  it. It writes the same fenced block in __startup.lua as ChannelView's
  View > Start web companion with REAPER, with the same care -- a backup
  first, nothing written that doesn't compile, nobody else's lines
  touched (TS_CV_Startup).
--]]

local script_dir = debug.getinfo(1, "S").source:match("@?(.*[\\/])") or ""
package.path = script_dir .. "?.lua;" .. package.path

local SU  = require("TS_CV_Startup")
local WEB = SU.web(script_dir)
local TITLE = "ChannelView web companion"

if not WEB.resolve() then
  reaper.MB("Couldn't find TS_ChannelView_Web.lua in the Action List, and couldn't add it.\n\n" ..
            "It should be in the same folder as this script: " .. script_dir, TITLE, 0)
  return
end

local state = WEB.scan()
if state == "manual" then
  reaper.MB("The web companion already starts with REAPER, from a line in __startup.lua\n" ..
            "that ChannelView didn't write, so it's left alone. Remove that line by hand\n" ..
            "to stop it:\n\n" .. SU.path(), TITLE, 0)
  return
end

if WEB.on() then
  if reaper.MB("The web companion starts with REAPER.\n\nStop starting it with REAPER?",
               TITLE, 4) ~= 6 then return end
  local ok, why = WEB.remove()
  if not ok then reaper.MB("__startup.lua was NOT changed.\n\n" .. tostring(why), TITLE, 0) end
else
  local now = WEB.running() and "" or "\n\nIt isn't running now either; it will be started now too."
  if reaper.MB("The web companion doesn't start with REAPER.\n\nStart it with REAPER from now on?" .. now,
               TITLE, 4) ~= 6 then return end
  local ok, why = WEB.add()
  if not ok then
    reaper.MB("__startup.lua was NOT changed.\n\n" .. tostring(why), TITLE, 0)
  elseif not WEB.running() then
    WEB.start()
  end
end
