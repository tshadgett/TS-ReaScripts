-- @noindex
-- Not a package of its own: installed by TS_ChannelView.lua's @provides.
--[[
  TS_ChannelView_ToggleMixer.lua -- switch ChannelView between its channel
  view and its mixer view.

  An action for the Action List, so it can go on a keyboard shortcut or a
  toolbar button: ChannelView's own window never sees the keyboard (REAPER
  keeps it), so a shortcut has to be REAPER's.

  ChannelView, while it's open, looks for the request this leaves and
  switches; a toolbar button for this action lights while the mixer is
  showing. With ChannelView closed it just flips the view ChannelView
  opens in.
--]]

local NS = "TS_ChannelView"
local _, _, sec, cmd = reaper.get_action_context()

-- which command this is, so ChannelView can light toolbar buttons for it
reaper.SetExtState(NS, "toggle_mixer_cmd", ("%d:%d"):format(sec, cmd), true)

local alive = tonumber(reaper.GetExtState(NS, "cv_alive")) or 0
if reaper.time_precise() - alive < 2 then
  reaper.SetExtState(NS, "toggle_mixer", "1", false)
else
  local on = reaper.GetExtState(NS, "mixer_view") == "1"
  reaper.SetExtState(NS, "mixer_view", on and "0" or "1", true)
end
reaper.defer(function() end)    -- no undo point
