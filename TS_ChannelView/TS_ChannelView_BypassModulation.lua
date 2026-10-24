-- @noindex
-- Not a package of its own: installed by TS_ChannelView.lua's @provides.
--[[
  TS_ChannelView_BypassModulation.lua -- bypass every modulator on the
  selected tracks, or let them move again.

  An action for a keyboard shortcut or a toolbar button: the same as the
  power button in the Modulators panel's header. Bypassed, each control a
  modulator drives sits where it's set, so you hear the track without the
  movement. Macros carry on. It's a parameter of the track's ChannelView
  Modulators plugin, so it works with ChannelView closed.

  The first selected track with modulators decides: bypassed there, all
  of them move again; otherwise all are bypassed. A toolbar button for it
  lights while the selected track's modulators are bypassed.
--]]

local own = debug.getinfo(1, "S").source:match("@?(.*[\\/])") or ""
package.path = own .. "?.lua;" .. package.path
local MD = require("TS_CV_Mod")

local NS = "TS_ChannelView"
local _, _, sec, cmd = reaper.get_action_context()
-- which command this is, so the Modulators panel can light it
reaper.SetExtState(NS, "bypass_mods_cmd", ("%d:%d"):format(sec, cmd), true)

local tracks = {}
for i = 0, reaper.CountSelectedTracks(0) - 1 do
  local tr = reaper.GetSelectedTrack(0, i)
  local slot = MD.plugin(tr)
  if MD.bypass_ok(tr, slot) then tracks[#tracks + 1] = { tr, slot } end
end

if #tracks > 0 then
  local on = not MD.bypassed(tracks[1][1], tracks[1][2])
  for _, t in ipairs(tracks) do MD.set_bypass(t[1], t[2], nil, on) end
  reaper.SetToggleCommandState(sec, cmd, on and 1 or 0)
  reaper.RefreshToolbar2(sec, cmd)
end
reaper.defer(function() end)    -- no undo point
