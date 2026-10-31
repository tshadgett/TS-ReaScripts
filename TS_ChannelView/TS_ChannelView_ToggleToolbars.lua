-- @noindex
-- Not a package of its own: installed by TS_ChannelView.lua's @provides.
--[[
  TS_ChannelView_ToggleToolbars.lua -- show or hide ChannelView's toolbar
  drawers, all at once.

  An action for a keyboard shortcut or a toolbar button. With any drawer
  open along ChannelView's sides, it closes them; run again, it brings
  back the ones it closed (every one, when it has none to bring back).
  Toolbars in their own windows, the TCP's and the web page's stay as
  they are. A toolbar button for it lights while drawers are out.
--]]

local own = debug.getinfo(1, "S").source:match("@?(.*[\\/])") or ""
package.path = own .. "?.lua;" .. package.path
local DR = require("TS_CV_Drawers")

local _, _, sec, cmd = reaper.get_action_context()
-- which command this is, so ChannelView can light toolbar buttons for it
reaper.SetExtState("TS_ChannelView", DR.GROUP_CMD.cv, ("%d:%d"):format(sec, cmd), true)
DR.toggle_bars("cv")
reaper.defer(function() end)    -- no undo point
