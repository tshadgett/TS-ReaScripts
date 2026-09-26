-- @noindex
-- Not a package of its own: installed by TS_ChannelView.lua's @provides.
--[[
  TS_CV_Receives.lua -- the Receives panel.

  The Sends panel seen from the other end: one cell per track sending
  into this one, with the same level, bypass, sidechain and pre/post
  controls, and an add menu listing the tracks it could receive from.
  Collapsed by default. All of it lives in TS_CV_Sends.lua; this is the
  receive-side instance of it.
--]]

return require("TS_CV_Sends").make("receive")
