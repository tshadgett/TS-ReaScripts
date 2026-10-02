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

local gr_open = {} -- guid -> bool: the gain-reduction meter opened out into its trace

function S.clear_cache() cache = {}; gr_open = {} end

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

-- Whether this instance's gain-reduction meter is opened out into its
-- trace (TS_CV_Panel). Per instance, like collapsed: you want to watch the
-- vocal's compressor, not every copy of that compressor in the project.
function S.is_gr_open(guid)
  if guid == nil or guid == "" then return false end
  local v = gr_open[guid]
  if v ~= nil then return v end
  local _, str = reaper.GetProjExtState(0, NS, "grview:" .. guid)
  v = (str == "1")
  gr_open[guid] = v
  return v
end

function S.set_gr_open(guid, on)
  if guid == nil or guid == "" then return end
  on = on and true or false
  gr_open[guid] = on
  reaper.SetProjExtState(0, NS, "grview:" .. guid, on and "1" or "")
end

function S.toggle_gr_open(guid)
  S.set_gr_open(guid, not S.is_gr_open(guid))
end

return S
