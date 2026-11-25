-- @noindex
-- Not a package of its own: installed by TS_ChannelView.lua's @provides.
--[[
  TS_CV_Upkeep.lua -- what's kept right on the selected tracks, by one
  window at a time.

  Whichever of ChannelView's windows is running (ChannelView itself, the
  TCP window's overview) calls UK.run each time it rescans. One of them
  holds the upkeep (a claim in ExtState, renewed while it runs and lapsing
  two seconds after it stops); the others skip it. The one holding it,
  for each selected track whose chain has changed:

    - after an unfreeze (from anywhere) the helpers go back to their
      slots (TS_CV_Freeze)
    - a lone probe gets its partner back, unless the other is frozen and
      comes back with an unfreeze; out of sight, the probes are kept at
      the ends of the chain (TS_CV_Taps)
    - the console's plugins kept in place (Pro)
    - a duplicated or pasted track, or one from a template: its plugins
      take up the settings it carries (TS_CV_Carry)

  and, every couple of seconds, what each carries is kept up to date; a
  console set up (Pro) gets its stages on new tracks, moved ones follow
  their bus.

  Settings taken up change TS_CV_State's records under every window's
  feet: UK.run returns true then, in whichever window took them up or saw
  another do it, for it to clear its cache.
--]]

local UK = {}

local C  = require("TS_CV_Config")
local T  = require("TS_CV_FXTree")
local U  = require("TS_CV_Util")

UK.OWNER = "upkeep_owner"     -- "<id>|<time>"
UK.REV   = "upkeep_rev"       -- changes when settings were taken up
UK.LEASE = 2.0                -- s: a claim not renewed lapses
UK.MAX_TRACKS = 16            -- selected tracks looked after at once

-- this window's name for itself: its start time and a table's address
local me = ("%d.%s"):format(math.floor(reaper.time_precise() * 1000) % 100000000,
  (tostring({}):match("(%x+)$") or tostring(math.random(1, 99999))))
local held = false
local renewed = 0
local hashes, carry_at = {}, {}
local rev_seen = nil

-- Holds the upkeep, or takes it when no one else does. True while this
-- window holds it.
function UK.claim(now)
  local v = reaper.GetExtState(C.EXT_SECT, UK.OWNER)
  local id, t = v:match("^(.-)|([%d.]+)$")
  t = tonumber(t)
  if id == me or not t or now - t > UK.LEASE then
    if id ~= me or now - renewed > 0.5 then
      reaper.SetExtState(C.EXT_SECT, UK.OWNER, me .. "|" .. ("%.3f"):format(now), false)
      renewed = now
    end
    if not held then hashes, carry_at = {}, {} end
    held = true
    return true
  end
  held = false
  return false
end

-- Let go (a window closing): another takes it up at once.
function UK.release()
  if not held then return end
  local v = reaper.GetExtState(C.EXT_SECT, UK.OWNER)
  if v:match("^(.-)|") == me then reaper.DeleteExtState(C.EXT_SECT, UK.OWNER, false) end
  held = false
end

function UK.holds() return held end

-- Looked at again on the next run (the chain changed in a way its hash
-- may not show)
function UK.forget(track)
  if track and reaper.ValidatePtr2(0, track, "MediaTrack*") then hashes[reaper.GetTrackGUID(track)] = nil end
end

-- One track: its chain looked at when it has changed (`full`: its
-- T.collect, when the caller has it). Returns the chain as it is after,
-- and true when settings were taken up.
function UK.track(track, full, now)
  if not (track and reaper.ValidatePtr2(0, track, "MediaTrack*")) then return full, false end
  local FZ, TP = require("TS_CV_Freeze"), require("TS_CV_Taps")
  local CR = require("TS_CV_Carry")
  full = full or T.collect(track)
  local g = reaper.GetTrackGUID(track)
  local took = false
  -- (and whether an instrument at the top is given audio: TP.pre_slot)
  local fh = T.hash(full) .. "|" .. TP.feed_key(track)
  if fh ~= hashes[g] then
    local moved = FZ.sync(track)
    FZ.forget()
    local fz = FZ.state(track, U.clean_fx_name)
    if not FZ.busy(track) and fz.probes == 0 and TP.complete_pair(track) then moved = true end
    local ED = require("TS_CV_Edition")
    local CD = ED.PRO and ED.module("TS_CV_ConsoleDrawer") or nil
    if CD and CD.keep_in_place(track) then moved = true end
    if TP.keep_in_place(track) or moved then full = T.collect(track) end
    hashes[g] = T.hash(full) .. "|" .. TP.feed_key(track)
    if CR.adopt(track, full) then took = true end
  end
  if now - (carry_at[g] or 0) > 2 then
    carry_at[g] = now
    CR.write(track, full)
  end
  return full, took
end

-- Each rescan, from any window. `own` (optional): the window's own track,
-- looked after too, with `full` its chain. Returns the chain of `own` as
-- it is after (or `full`), and true when settings were taken up here or
-- by another window since this one last asked.
function UK.run(now, own, full)
  local took = false
  if UK.claim(now) then
    local ED = require("TS_CV_Edition")
    local CD = ED.PRO and ED.module("TS_CV_ConsoleDrawer") or nil
    if CD then CD.follow() end
    local n = math.min(reaper.CountSelectedTracks(0), UK.MAX_TRACKS)
    for i = 0, n - 1 do
      local tr = reaper.GetSelectedTrack(0, i)
      if tr ~= own then
        local _, t = UK.track(tr, nil, now)
        took = took or t
      end
    end
    if own then
      local t
      full, t = UK.track(own, full, now)
      took = took or t
    end
    if took then reaper.SetExtState(C.EXT_SECT, UK.REV, ("%s.%.3f"):format(me, now), false) end
  end
  local rev = reaper.GetExtState(C.EXT_SECT, UK.REV)
  if rev_seen == nil then rev_seen = rev end
  if rev ~= rev_seen then rev_seen = rev; took = true end
  return full, took
end

return UK
