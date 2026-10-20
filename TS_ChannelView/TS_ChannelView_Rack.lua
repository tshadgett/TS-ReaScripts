-- @noindex
-- Not a package of its own: installed by TS_ChannelView.lua's @provides.
--[[
  TS_ChannelView_Rack.lua -- ChannelView's Rack view: the selected track's
  plugins down a column, in a window of its own -- dock it beside the
  arrange while ChannelView stays in its docker.

  No fader panel, track names or mixer: the track is whichever REAPER has
  selected, in its mixer or the TCP. The macros and the modulators are
  strips across the top, the sends and the receives strips across the
  foot (View menu: any of them can go). Every panel is as wide as the
  column. Its toolbars are its own -- put a bar on "Rack · top" (left,
  right, bottom) from any bar's right-click ▸ Place. Layouts, settings
  and the web companion are ChannelView's.

  It is ChannelView itself, told to draw as the rack.
--]]

TS_CV_RACK = true
local dir = debug.getinfo(1, "S").source:match("@?(.*[\\/])") or ""
dofile(dir .. "TS_ChannelView.lua")
