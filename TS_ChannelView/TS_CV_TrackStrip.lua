-- @noindex
-- Not a package of its own: installed by TS_ChannelView.lua's @provides.
--[[
  TS_CV_TrackStrip.lua -- asks the track row to scroll to the selection.

  The row itself -- strips and their name buttons, in both views -- is
  drawn by TS_CV_Mixer.lua's MX.draw_row, on one shared BeginChild. That
  used to be two windows (a mixer row and a track strip) kept in step by
  hand, which is exactly where two real scroll bugs turned up: one
  window's wheel not reaching into the other's child windows, and the
  second window never having its own wheel handling at all. One window
  can't disagree with itself, so this file no longer draws anything --
  it just holds the one piece of state that belongs to "the selection
  changed from outside this window", which channel view's button loop
  reads and clears.
--]]

local MX = require("TS_CV_Mixer")

local S = {}
local ImGui

function S.attach(imgui) ImGui = imgui end

-- Ask the track row to bring the selected track into view on the next
-- frame (used when the selection changed from outside this window).
function S.request_scroll() MX.scroll_to_sel = true end

return S
