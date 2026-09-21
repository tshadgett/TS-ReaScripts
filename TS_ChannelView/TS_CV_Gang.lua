-- @noindex
-- Not a package of its own: installed by TS_ChannelView.lua's @provides.
--[[
  TS_CV_Gang.lua -- one edit, every selected track.

  Select six tracks and pull one fader: all six move. That is what a
  console does, what REAPER's own mixer does, and what anybody who has
  selected six tracks on purpose is asking for.

  Two kinds of edit, and the difference matters:

    ABSOLUTE -- mute, solo, record arm, phase, monitoring, automation
    mode, collapse. Every ganged track takes the SAME value. Muting one
    of six mutes six; there is no sensible "proportionally muted".

    RELATIVE -- volume and pan. Every ganged track keeps its own value
    and moves BY the same amount: volume by the same ratio (which is the
    same number of dB), pan by the same offset. A balance you spent an
    hour on is a thing you are trying to move, not a thing you are
    trying to flatten -- absolute here would set six faders to one
    number and throw the mix away.

  Nothing in here draws, and nothing in here knows about ImGui. It is
  the layer between a control deciding what it wants and the tracks that
  end up with it, which is why the collapse state -- not a track
  property at all -- still comes through here: it gangs by the same
  rule, and the rule belongs in one place.
--]]

local G = {}

-- ---------------------------------------------------------------------
-- who is in the gang
-- ---------------------------------------------------------------------

-- Selected as REAPER understands it. The arrange view and this window
-- have to agree about what is selected, or a multi-selection made here
-- would not be one you could act on there.
function G.is_selected(tr)
  if not tr then return false end
  local v = reaper.GetMediaTrackInfo_Value(tr, "I_SELECTED")
  if v == nil then return false end
  return v > 0.5
end

function G.count()
  return reaper.CountSelectedTracks2(0, true) or 0
end

-- An edit gangs only when the track you touched is itself one of several
-- selected. Touching an UNSELECTED track's fader while five others are
-- selected moves that one track: you reached for it specifically, and
-- an edit that jumped to five tracks you did not touch would be the
-- kind of surprise that ends in an undo and a lost afternoon.
function G.ganged(track)
  return G.is_selected(track) and G.count() > 1
end

-- Runs `fn` for every track this edit reaches: the whole selection when
-- it gangs, otherwise the one track.
function G.each(track, fn)
  if not track then return end
  if not G.ganged(track) then fn(track) return end
  for i = 0, G.count() - 1 do
    local tr = reaper.GetSelectedTrack2(0, i, true)
    if tr then fn(tr) end
  end
end

-- ---------------------------------------------------------------------
-- absolute
-- ---------------------------------------------------------------------

-- Every ganged track takes the same value. A track that hasn't GOT the
-- property is skipped rather than written to: the master has no record
-- arm, no input monitoring and no phase invert, and REAPER answers nil
-- rather than 0 for all three.
function G.set(track, key, val)
  G.each(track, function(tr)
    if reaper.GetMediaTrackInfo_Value(tr, key) ~= nil then
      reaper.SetMediaTrackInfo_Value(tr, key, val)
    end
  end)
end

-- ---------------------------------------------------------------------
-- relative
-- ---------------------------------------------------------------------

-- Volume by ratio. The ratio is worked out from the track you actually
-- dragged, so that track lands exactly on `new_v` and the others move
-- with it -- a constant ratio on the linear gain IS a constant number
-- of dB, which is what "move them together" means to an engineer.
--
-- A track sitting at -inf stays there: anything times zero is zero, and
-- a fader at the bottom of its travel is a decision, not an accident.
function G.vol(track, new_v)
  local old = reaper.GetMediaTrackInfo_Value(track, "D_VOL")
  if not G.ganged(track) or not old or old <= 0 then
    reaper.SetMediaTrackInfo_Value(track, "D_VOL", new_v)
    return
  end
  local ratio = new_v / old
  G.each(track, function(tr)
    local v = reaper.GetMediaTrackInfo_Value(tr, "D_VOL")
    if v then reaper.SetMediaTrackInfo_Value(tr, "D_VOL", v * ratio) end
  end)
end

-- Pan by offset, not by ratio: a ratio would leave a centred track
-- centred no matter how far you dragged, which is not what anybody
-- means. Clamped at each end, so a track already hard left stays hard
-- left rather than wrapping or running off.
function G.pan(track, new_p)
  local old = reaper.GetMediaTrackInfo_Value(track, "D_PAN")
  if not G.ganged(track) or not old then
    reaper.SetMediaTrackInfo_Value(track, "D_PAN", new_p)
    return
  end
  local d = new_p - old
  G.each(track, function(tr)
    local v = reaper.GetMediaTrackInfo_Value(tr, "D_PAN")
    if v then
      reaper.SetMediaTrackInfo_Value(tr, "D_PAN",
        math.max(-1, math.min(1, v + d)))
    end
  end)
end

-- ---------------------------------------------------------------------
-- collapse
-- ---------------------------------------------------------------------

-- Not a track property, but it gangs by the same rule, so it comes
-- through the same door. Returns the collapse keys for every track this
-- edit reaches -- `prefix` .. guid, which is how the mixer names them.
function G.collapse_keys(track, prefix)
  local out = {}
  G.each(track, function(tr)
    local g = reaper.GetTrackGUID(tr)
    if g then out[#out + 1] = prefix .. g end
  end)
  return out
end

return G
