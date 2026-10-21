-- @noindex
-- Not a package of its own: installed by TS_ChannelView.lua's @provides.
--[[
  TS_CV_Freeze.lua -- REAPER's own track freeze, from ChannelView.

  Freeze renders the track pre-fader into its items and sets the frozen
  plugins aside in the track's state until Unfreeze. They leave the live
  chain, so ChannelView reads their names from the track's chunk (each
  <FREEZE block holds one level's FX chain) to show them where they were.

  REAPER's freeze takes everything up to the last online plugin, offline
  ones included. So the plugins after the chosen one (Freeze up to) are
  set offline for the freeze and put back online after, and ChannelView's
  own helpers -- the TS_TrackProbe pair and ChannelView Modulators --
  that sit among the plugins to freeze are first moved to just after
  them: they keep measuring and modulating the live chain. Unfreeze
  brings the frozen plugins back at the top of the chain, and the helpers
  go back to their old slots, whichever unfreeze it was (FZ.sync). A
  freeze can give the plugins it leaves new IDs, so they are found again
  by name and order, and they are put back online only once the freeze
  shows in the track.
  The freeze is stereo: the measuring taps widen the track, and a
  multichannel freeze would print every one of those channels.
--]]

local FZ = {}

local CMD_STEREO, CMD_UNFREEZE = 41223, 41644
local EXT = "P_EXT:TS_CV_FREEZE2"    -- the helpers to put back (FZ.push_level)

-- ChannelView's own plugins, by name: never frozen
local function is_helper(name)
  name = name or ""
  return name:find("TS_TrackProbe", 1, true) ~= nil
      or name:find("ChannelView Modulators", 1, true) ~= nil
      or name:find("TS_CV_Modulators", 1, true) ~= nil
end
FZ.is_helper = is_helper
local function fx_name(track, i)
  local ok, n = reaper.TrackFX_GetNamedConfigParm(track, i, "fx_name")
  if ok and n ~= "" then return n end
  local _, nm = reaper.TrackFX_GetFXName(track, i, "")
  return nm or ""
end

-- the FX lines a chain holds, by their opening tag
local FX_TAGS = { VST = true, AU = true, JS = true, CLAP = true, DX = true, LV2 = true,
                  CONTAINER = true, VIDEO_EFFECT = true }

-- A plugin's raw name from its chunk line: the first quoted string; a
-- JS effect's is its path (quoted only when it has spaces), so its file
-- name less the .jsfx.
local function raw_name(line)
  local tag = line:match("^%s*<(%u+)")
  local q = line:match('"(.-)"')
  if tag == "CONTAINER" then
    q = line:match('^%s*<CONTAINER%s+%S+%s+"(.-)"') or q or "Container"
  elseif tag == "JS" then
    local path = line:match('^%s*<JS%s+"(.-)"') or line:match("^%s*<JS%s+(%S+)") or ""
    q = (path:match("([^/\\]+)$") or path):gsub("%.jsfx$", "")
  end
  return (q and q ~= "") and q or tag
end

-- The frozen plugins in a track chunk (pure): { levels = n, fx = { name,
-- ... }, probes = n }, the levels in the chunk's order, each level's chain
-- in order; probes counts the TS_TrackProbes frozen with them (a freeze
-- made by REAPER's own action takes them too). Only an FXCHAIN's own
-- plugins count: an item's take FX and what sits inside a container are
-- left out.
function FZ.parse(chunk, clean)
  local out = { levels = 0, fx = {}, probes = 0 }
  if not chunk or chunk == "" then return out end
  local depth = 0
  local freeze_at, chain_at = nil, nil
  for line in chunk:gmatch("[^\r\n]+") do
    local open = line:match("^%s*<(%S+)")
    if open then
      depth = depth + 1
      if open == "FREEZE" and not freeze_at then
        freeze_at = depth
        out.levels = out.levels + 1
      elseif freeze_at and open == "FXCHAIN" and not chain_at then
        chain_at = depth
      elseif chain_at and depth == chain_at + 1 and FX_TAGS[open] then
        local raw = raw_name(line)
        if not is_helper(raw) then out.fx[#out.fx + 1] = clean and clean(raw) or raw
        elseif raw:find("TS_TrackProbe", 1, true) then out.probes = out.probes + 1 end
      end
    elseif line:match("^%s*>%s*$") then
      if chain_at and depth == chain_at then chain_at = nil end
      if freeze_at and depth == freeze_at then freeze_at = nil end
      depth = depth - 1
    end
  end
  return out
end

-- The track's freeze state, read again only when the project has changed
-- (and then at most twice a second): { levels, fx, probes }.
local cache = { track = nil, count = nil, at = 0, state = { levels = 0, fx = {}, probes = 0 } }
function FZ.state(track, clean)
  if not track then return { levels = 0, fx = {}, probes = 0 } end
  local count = reaper.GetProjectStateChangeCount(0)
  local now = reaper.time_precise()
  if track ~= cache.track or (count ~= cache.count and now - cache.at > 0.5) then
    local ok, chunk = reaper.GetTrackStateChunk(track, "", false)
    cache.state = FZ.parse(ok and chunk or "", clean)
    cache.track, cache.count, cache.at = track, count, now
  end
  return cache.state
end
function FZ.forget() cache.track = nil end

-- Runs a track action on this track alone, the selection put back after.
local function on_track(track, cmd)
  local sel = {}
  for i = 0, reaper.CountSelectedTracks(0) - 1 do sel[#sel + 1] = reaper.GetSelectedTrack(0, i) end
  reaper.SetOnlyTrackSelected(track)
  reaper.Main_OnCommand(cmd, 0)
  reaper.SetOnlyTrackSelected(track)
  for _, t in ipairs(sel) do reaper.SetTrackSelected(t, true) end
end

-- The plugin's slot by its GUID, or nil.
local function index_of(track, guid)
  for i = 0, reaper.TrackFX_GetCount(track) - 1 do
    if reaper.TrackFX_GetFXGUID(track, i) == guid then return i end
  end
  return nil
end

-- Moves the plugin `guid` to just after the plugin `after`. REAPER reads
-- a move's destination against the chain before it, so the slot asked
-- for is checked and the other reading tried if it missed.
local function move_after(track, guid, after)
  for try = 1, 2 do
    local from, to = index_of(track, guid), index_of(track, after)
    if not (from and to) or from == to + 1 then return end
    local dest = to + 1
    if from < to and try == 1 then dest = to end
    reaper.TrackFX_CopyToTrack(track, from, track, dest, true)
  end
end

-- Moves the first plugin named `nm` at or after `slot` to `slot`.
local function move_back(track, slot, nm)
  for i = slot, reaper.TrackFX_GetCount(track) - 1 do
    if fx_name(track, i) == nm then
      if i ~= slot then reaper.TrackFX_CopyToTrack(track, i, track, slot, true) end
      return
    end
  end
end

local function chain_names(track)
  local out = {}
  for i = 0, reaper.TrackFX_GetCount(track) - 1 do out[i + 1] = fx_name(track, i) end
  return out
end

-- How many freeze levels the track has now.
local function levels_now(track)
  local ok, chunk = reaper.GetTrackStateChunk(track, "", false)
  return FZ.parse(ok and chunk or "", nil).levels
end

-- Which of `want` (names, in order) the chain `have` (names) holds, in
-- order (pure): want's index -> have's index. A freeze can give the
-- plugins it leaves new IDs, so they are found again by name and order.
function FZ.match(want, have)
  local map, j = {}, 1
  for i, nm in ipairs(want) do
    local k = j
    while k <= #have and have[k] ~= nm do k = k + 1 end
    if k <= #have then map[i] = k; j = k + 1 end
  end
  return map
end

-- The record of the helpers to put back at an unfreeze (pure): one level
-- per freeze level, each led by "\30", its "slot\31name" entries by
-- "\29". A level with none is an empty one, so the record counts the
-- track's levels (FZ.count) and an unfreeze from anywhere shows.
local RS, US, ES = "\30", "\31", "\29"
local function norm(rec)
  rec = rec or ""
  if rec ~= "" and rec:sub(1, 1) ~= RS then rec = RS .. rec end
  return rec
end
function FZ.count(rec)
  local _, n = norm(rec):gsub(RS, "")
  return n
end
-- `levels`: the levels frozen before this one (a freeze made elsewhere
-- left none recorded), so this one lands at its own.
function FZ.push_level(rec, moves, levels)
  rec = norm(rec)
  while levels and FZ.count(rec) < levels do rec = rec .. RS end
  local t = {}
  for _, m in ipairs(moves) do t[#t + 1] = m[1] .. US .. m[2] end
  return rec .. RS .. table.concat(t, ES)
end
function FZ.pop_level(rec)
  rec = norm(rec)
  if rec == "" then return {}, "" end
  local rest, top = rec:match("^(.*)" .. RS .. "([^" .. RS .. "]*)$")
  local moves = {}
  for e in (top .. ES):gmatch("([^" .. ES .. "]*)" .. ES) do
    local slot, nm = e:match("^(%d+)" .. US .. "(.*)$")
    if slot then moves[#moves + 1] = { tonumber(slot), nm } end
  end
  table.sort(moves, function(a, b) return a[1] < b[1] end)
  return moves, rest
end

-- A freeze started and not yet seen through: the plugins it was to leave,
-- to put back online once REAPER's freeze is in the track.
local pending = nil

local function finish(p)
  local track = p.track
  local map = FZ.match(p.after, chain_names(track))
  local missing = 0
  for i, ours in ipairs(p.ours) do
    local k = map[i]
    if not k then
      if ours then missing = missing + 1 end
    elseif ours then
      reaper.TrackFX_SetOffline(track, k - 1, false)
    end
  end
  FZ.forget()
  if missing > 0 then
    reaper.MB(("REAPER froze %d plugin%s it was asked to leave as well. Unfreeze puts them back.")
      :format(missing, missing == 1 and "" or "s"), "ChannelView", 0)
  end
end

-- Call every frame: puts the left plugins back online once the freeze
-- shows in the track (REAPER may finish it after the action returns), or
-- after a minute and a half whatever happened. True when it has finished.
function FZ.poll()
  local p = pending
  if not p then return false end
  if not reaper.ValidatePtr(p.track, "MediaTrack*") then pending = nil return true end
  if levels_now(p.track) > p.levels or reaper.time_precise() - p.t0 > 90 then
    pending = nil
    finish(p)
    return true
  end
  return false
end
function FZ.busy() return pending ~= nil end

-- Puts back the helpers recorded for the levels the track no longer has:
-- unfrozen from ChannelView or from anywhere else (REAPER's own Unfreeze,
-- its undo). Each level's in slot order, the first helper of that name at
-- or after the slot, as REAPER brings the frozen plugins back at the top.
-- No undo point of its own, like the probes' moves (TS_CV_Taps): one
-- would come before the unfreeze in the undo history and make it
-- unreachable. True if the record changed.
function FZ.sync(track)
  if not track or pending then return false end
  local _, rec = reaper.GetSetMediaTrackInfo_String(track, EXT, "", false)
  if not rec or rec == "" then return false end
  local have, n = levels_now(track), FZ.count(rec)
  if n <= have then return false end
  reaper.PreventUIRefresh(1)
  while n > have do
    local moves
    moves, rec = FZ.pop_level(rec)
    for _, m in ipairs(moves) do move_back(track, m[1], m[2]) end
    n = n - 1
  end
  reaper.PreventUIRefresh(-1)
  reaper.GetSetMediaTrackInfo_String(track, EXT, rec, true)
  FZ.forget()
  return true
end

-- Freezes the track: all of it, or up to and including the top-level
-- plugin at `upto` (0-based). Returns true, or false and why.
function FZ.freeze(track, upto)
  if not track then return false, "No track." end
  if pending then return false, "A freeze is still finishing." end
  FZ.sync(track)
  local n = reaper.TrackFX_GetCount(track)
  -- the last plugin to freeze: the chosen one, or the last that isn't a helper
  local last = (upto and upto < n) and upto or nil
  if not last then
    for i = n - 1, 0, -1 do
      if not is_helper(fx_name(track, i)) then last = i; break end
    end
  end
  if not last or is_helper(fx_name(track, last)) then return false, "There are no plugins to freeze." end
  local target = reaper.TrackFX_GetFXGUID(track, last)
  local levels = levels_now(track)
  reaper.Undo_BeginBlock()
  -- REAPER freezes everything up to the last online plugin, offline ones
  -- included: the helpers among the plugins to freeze are moved to just
  -- after the last of them, in their order, their slots and names kept
  -- for the unfreeze
  local moving, back = {}, {}
  for i = 0, last - 1 do
    local nm = fx_name(track, i)
    if is_helper(nm) then
      moving[#moving + 1] = reaper.TrackFX_GetFXGUID(track, i)
      back[#back + 1] = { i, nm }
    end
  end
  local after = target
  for _, g in ipairs(moving) do
    move_after(track, g, after)
    after = g
  end
  -- everything after the last plugin to freeze: offline for the freeze
  local p = { track = track, after = {}, ours = {}, t0 = reaper.time_precise(), levels = levels }
  local t = index_of(track, target) or last
  for i = t + 1, reaper.TrackFX_GetCount(track) - 1 do
    p.after[#p.after + 1] = fx_name(track, i)
    local on = not reaper.TrackFX_GetOffline(track, i)
    p.ours[#p.ours + 1] = on
    if on then reaper.TrackFX_SetOffline(track, i, true) end
  end
  local _, prev = reaper.GetSetMediaTrackInfo_String(track, EXT, "", false)
  reaper.GetSetMediaTrackInfo_String(track, EXT, FZ.push_level(prev, back, levels), true)
  on_track(track, CMD_STEREO)
  reaper.Undo_EndBlock(upto and "ChannelView: freeze up to a plugin" or "ChannelView: freeze track", -1)
  pending = p
  FZ.poll()
  FZ.forget()
  return true
end

-- Unfreezes the track's last frozen level; FZ.sync puts its helpers back.
function FZ.unfreeze(track)
  if not track then return end
  reaper.Undo_BeginBlock()
  on_track(track, CMD_UNFREEZE)
  FZ.sync(track)
  reaper.Undo_EndBlock("ChannelView: unfreeze", -1)
  FZ.forget()
end

return FZ
