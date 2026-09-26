-- @noindex
-- Not a package of its own: installed by TS_ChannelView.lua's @provides.
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

-- `default` is what an instance nobody has touched shows as -- false
-- (expanded) unless a caller says otherwise. Only a departure from the
-- default is written to the project.
function S.is_collapsed(guid, default)
  default = default or false
  if guid == nil or guid == "" then return false end
  local v = cache[guid]
  if v ~= nil then return v end
  local _, str = reaper.GetProjExtState(0, NS, "collapsed:" .. guid)
  if str == "1" then v = true
  elseif str == "0" then v = false
  else v = default end
  cache[guid] = v
  return v
end

function S.set_collapsed(guid, on, default)
  default = default or false
  if guid == nil or guid == "" then return end
  on = on and true or false
  cache[guid] = on
  local val = (on == default) and "" or (on and "1" or "0")
  reaper.SetProjExtState(0, NS, "collapsed:" .. guid, val)
end

function S.toggle_collapsed(guid, default)
  default = default or false
  S.set_collapsed(guid, not S.is_collapsed(guid, default), default)
end

return S
