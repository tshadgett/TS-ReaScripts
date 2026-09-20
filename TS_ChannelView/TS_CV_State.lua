--[[
  TS_CV_State.lua -- per-FX-instance view state.

  Deliberately separate from TS_CV_Mappings. A layout says what a PLUGIN
  looks like and is shared by every instance of it; whether one particular
  instance on one particular track is collapsed is not that -- you'd
  collapse the reverb on the drum bus without wanting it collapsed on the
  vocal. So this is keyed by FX GUID and lives in the project file, which
  also means it survives a save/reopen.
--]]

local NS = "TS_ChannelView"

local S = {}

local cache = {}   -- guid -> bool, so a frame doesn't hit ProjExtState per panel

function S.clear_cache() cache = {} end

function S.is_collapsed(guid)
  if guid == nil or guid == "" then return false end
  local v = cache[guid]
  if v ~= nil then return v end
  local _, str = reaper.GetProjExtState(0, NS, "collapsed:" .. guid)
  v = (str == "1")
  cache[guid] = v
  return v
end

function S.set_collapsed(guid, on)
  if guid == nil or guid == "" then return end
  cache[guid] = on and true or false
  reaper.SetProjExtState(0, NS, "collapsed:" .. guid, on and "1" or "")
end

function S.toggle_collapsed(guid)
  S.set_collapsed(guid, not S.is_collapsed(guid))
end

return S
