-- @noindex
-- Not a package of its own: installed by TS_ChannelView.lua's @provides.
--[[
  TS_CV_AutoFloat.lua -- View > Float plugins without controls.

  A plugin whose layout has no controls (an instrument whose own window is
  where you work, say) gets its own window floated when ChannelView moves
  to its track, a moment after, so stepping through tracks doesn't open
  and shut windows on the way. On the next track change the windows it
  opened close again, unless pinned (the pin in the panel's header, shown
  while it's open). It never closes a window you opened yourself, and one
  you close by hand stays closed until you come back to its track.

  ChannelView and the rack each keep their own: each closes only what it
  opened.
--]]

local T = require("TS_CV_FXTree")

local AF = {}

AF.DELAY = 0.35        -- seconds on a track before its windows open

-- the windows opened here: fx GUID -> { track, pinned }
local opened = {}
local cur, since, done = nil, 0, true
local last_check = 0

local function addr_of(track, guid)
  for _, f in ipairs(T.collect(track)) do
    if f.guid == guid then return f.addr end
  end
  return nil
end

-- Whether ChannelView opened this plugin's window, and whether it's pinned.
function AF.is_auto(guid) return opened[guid] ~= nil end
function AF.is_pinned(guid) return opened[guid] ~= nil and opened[guid].pinned == true end
function AF.toggle_pin(guid)
  local o = opened[guid]
  if o then o.pinned = not o.pinned end
end

-- Call every frame. `track`: the track shown, or nil when the option is
-- off (then nothing opens, and what was opened closes at the next change).
-- `wanted()`: the plugins on it to float, { { guid, addr }, ... }.
function AF.tick(track, wanted)
  local now = reaper.time_precise()
  -- forget the windows closed by hand (a few times a second)
  if now - last_check > 0.25 then
    last_check = now
    for guid, o in pairs(opened) do
      local ok = reaper.ValidatePtr(o.track, "MediaTrack*")
      local a = ok and addr_of(o.track, guid)
      if not (a and T.is_floating(o.track, a)) then opened[guid] = nil end
    end
  end
  if track ~= cur then cur, since, done = track, now, false end
  if done or now - since < AF.DELAY then return end
  done = true
  -- what was opened for another track, unless pinned
  for guid, o in pairs(opened) do
    if not o.pinned and o.track ~= track then
      if reaper.ValidatePtr(o.track, "MediaTrack*") then
        local a = addr_of(o.track, guid)
        if a and T.is_floating(o.track, a) then reaper.TrackFX_Show(o.track, a, 2) end
      end
      opened[guid] = nil
    end
  end
  if not track then return end
  for _, fx in ipairs(wanted()) do
    if not T.is_floating(track, fx.addr) then
      reaper.TrackFX_Show(track, fx.addr, 3)
      opened[fx.guid] = { track = track }
    end
  end
end

return AF
