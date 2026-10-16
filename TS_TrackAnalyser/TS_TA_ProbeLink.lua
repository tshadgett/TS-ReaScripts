-- @noindex
--[[
  TS_TA_ProbeLink -- talking to TS_TrackProbe, whichever version it is.
  (ChannelView's TS_CV_ProbeLink.lua is the same code: keep them so.)

  Since TS_TrackProbe 2.0.0 the probe has no parameters at all (see NO
  PARAMETERS in TS_TrackProbe.jsfx): everything the scripts tell it, and
  everything it tells them, goes through a block of gmem per track, THE
  PROBE BLOCK, at 0x100000 + (track index + 1) * 128 in TS_TA_Mem. Up to
  1.8.0 it was all hidden sliders -- still REAPER parameters, so in every
  automation and learn list, and each write made one of them REAPER's
  "last touched".

  A project keeps running the probe it compiled when it was opened, so
  after an update the old one is still there until the project is
  reopened. So every read and write here asks which it is talking to: a
  probe with more than REAPER's own three parameters (Bypass, Wet, Delta)
  is the old one, and gets its sliders as before.

  WHICH PROBE IS WHICH. The old probe kept its role (pre, post,
  comparison) in a slider. The new one finds its place in the chain with
  get_host_placement() -- which is REAPER's own FX address, containers
  included (checked on REAPER 7.82: 0, 7, 0x2000015, 0x2000041 all came
  back as themselves) -- and recognises itself when that place is written
  into its track's block as the pre or the post. PL.name() does that. A
  probe nobody names does nothing.

  Track Analyser and ChannelView each keep their own copy of this module
  (TS_CV_ProbeLink.lua is the same code): the two packages install apart.

  TRACKS MOVING. The block is the track's by its index, so when a track
  moves, its names have to follow it. PL.tick() (every frame) writes each
  named track's names where the track is now, and takes them off the block
  it left when nothing of ours is there now. Whatever else lived in the
  block it left -- a script's settings for the taps, say -- the script
  writes again: tick returns the tracks that moved.
--]]

local PL = {}

PL.NS = "TS_TA_Mem"
PL.BASE, PL.STRIDE, PL.TRACKS = 0x100000, 128, 8192
PL.CTRL_REL = 75          -- spectrum release, ms (0: the probe's 400)
PL.REAPER_PARAMS = 3      -- Bypass, Wet, Delta
PL.VIS_EXT = "P_EXT:TS_TrackProbe_vis"   -- "pre" / "post": the one in the Visualizer

-- Each field: its offset in the block, and the old probe's slider (its
-- 0-based parameter). `n` of them in a row.
PL.F = {
  pre      = { off = 0 },                 -- names, new probe only
  post     = { off = 1 },
  pub_pre  = { off = 2, leg = 1 },        -- old: the publish slider of that probe
  pub_post = { off = 3, leg = 1 },
  compare  = { off = 4 },
  vis_pre  = { off = 5, leg = 4 },        -- Visualizer slot + 1 (old: slot, -1 none)
  vis_post = { off = 6, leg = 4 },
  tap_n    = { off = 8,  leg = 5 },
  lag      = { off = 9,  leg = 6,  n = 4 },
  rst      = { off = 13, leg = 10, n = 4 },
  gen      = { off = 17, leg = 22 },
  arm      = { off = 18, leg = 23 },
  nogr     = { off = 19, leg = 24 },
  mb       = { off = 20, leg = 41 },
  mbx      = { off = 21, leg = 42, n = 3 },
  fine     = { off = 24, leg = 49 },
  ack_pre  = { off = 32 },
  ack_post = { off = 33 },
  gr       = { off = 64, leg = 14, n = 4 },
  cal      = { off = 68, leg = 18, n = 4 },
  inpk     = { off = 72, leg = 25, n = 4 },
  outpk    = { off = 76, leg = 29, n = 4 },
  inrms    = { off = 80, leg = 33, n = 4 },
  outrms   = { off = 84, leg = 37, n = 4 },
  mbgr     = { off = 88, leg = 45, n = 4 },
  mbl      = { off = 92, leg = 50, n = 4 },
}
PL.LEG_ROLE, PL.LEG_REL, PL.LEG_VIS = 0, 2, 3

local attached = false
local function attach()
  if not attached then reaper.gmem_attach(PL.NS); attached = true end
end
-- Another module attached something else (it says so).
function PL.detached() attached = false end

-- A track's index as the probe sees it: 0-based, -1 for the master.
function PL.track_index(tr)
  if not tr then return nil end
  local n = reaper.GetMediaTrackInfo_Value(tr, "IP_TRACKNUMBER")
  if n == -1 then return -1 end
  if not n or n < 1 then return nil end
  return math.floor(n) - 1
end

function PL.block(tr)
  local i = PL.track_index(tr)
  if not i or i + 1 >= PL.TRACKS then return nil end
  return PL.BASE + (i + 1) * PL.STRIDE
end

-- Old (sliders) or new (gmem)? Cached per instance.
local legacy = {}
function PL.is_legacy(tr, fx)
  if not (tr and fx) then return false end
  local g = reaper.TrackFX_GetFXGUID(tr, fx)
  local key = g or (tostring(tr) .. ":" .. tostring(fx))
  local v = legacy[key]
  if v == nil then
    v = (reaper.TrackFX_GetNumParams(tr, fx) or 0) > PL.REAPER_PARAMS
    if g then legacy[key] = v end
  end
  return v
end

local function rd(addr) attach(); return reaper.gmem_read(addr) or 0 end
local function wr(addr, v)
  attach()
  if reaper.gmem_read(addr) ~= v then reaper.gmem_write(addr, v) end
end

-- A field: `fx` is the probe it belongs to (the post for the taps' own,
-- the pre for arm), only asked to tell old from new. `i` is 1-based.
function PL.get(tr, fx, field, i)
  local f = PL.F[field]
  i = (i or 1) - 1
  if PL.is_legacy(tr, fx) then
    if not f.leg then return 0 end
    return reaper.TrackFX_GetParam(tr, fx, f.leg + i) or 0
  end
  local b = PL.block(tr)
  if not b then return 0 end
  return rd(b + f.off + i)
end

-- Only when it changes: on an old probe a write is a parameter change,
-- and REAPER makes it "last touched".
function PL.set(tr, fx, field, i, v)
  local f = PL.F[field]
  i = (i or 1) - 1
  if PL.is_legacy(tr, fx) then
    if not f.leg then return end
    local cur = reaper.TrackFX_GetParam(tr, fx, f.leg + i)
    if cur and math.abs(cur - v) < 1e-9 then return end
    reaper.TrackFX_SetParam(tr, fx, f.leg + i, v)
    return
  end
  local b = PL.block(tr)
  if b then wr(b + f.off + i, v) end
end

-- The old probe's role slider (0 pre, 1 post, 2 comparison); nil for a
-- new one, whose role is where it sits.
function PL.legacy_role(tr, fx)
  if not PL.is_legacy(tr, fx) then return nil end
  return math.floor((reaper.TrackFX_GetParam(tr, fx, PL.LEG_ROLE) or 0) + 0.5)
end

-- NAMES ----------------------------------------------------------------

-- What get_host_placement() says for an FX at REAPER address `addr`: the
-- address itself, + 1 so that 0 means "nobody".
local function place(addr) return addr + 1 end

local named = {}   -- track GUID -> { tr, idx, pre, post } (pre/post: places + 1, or 0)

local function write_names(b, pre, post)
  wr(b + PL.F.pre.off, pre)
  wr(b + PL.F.post.off, post)
end

-- Name a track's pair: `pre` and `post` are REAPER addresses (either may
-- be nil). An old probe is told by its role slider instead.
function PL.name(tr, pre, post)
  if not tr then return end
  if pre and PL.is_legacy(tr, pre) then
    if PL.legacy_role(tr, pre) ~= 0 then reaper.TrackFX_SetParam(tr, pre, PL.LEG_ROLE, 0) end
    pre = nil
  end
  if post and PL.is_legacy(tr, post) then
    -- a comparison stays one (Track Analyser puts it back)
    if PL.legacy_role(tr, post) == 0 then reaper.TrackFX_SetParam(tr, post, PL.LEG_ROLE, 1) end
    post = nil
  end
  local g = reaper.GetTrackGUID(tr)
  local b = PL.block(tr)
  if not (g and b) then return end
  local e = named[g] or { tr = tr }
  e.tr, e.idx = tr, PL.track_index(tr)
  e.pre, e.post = pre and place(pre) or 0, post and place(post) or 0
  named[g] = e
  write_names(b, e.pre, e.post)
end

-- Whether the new probes have recognised themselves: their block counts,
-- which move while they run. Read twice, a moment apart, to tell.
function PL.acks(tr)
  local b = PL.block(tr)
  if not b then return 0, 0 end
  return rd(b + PL.F.ack_pre.off), rd(b + PL.F.ack_post.off)
end

-- Every frame: names where each named track is now. Returns the list of
-- tracks that moved (so their scripts write their own fields again).
function PL.tick()
  local moved, at = nil, {}
  for g, e in pairs(named) do
    if not reaper.ValidatePtr2(0, e.tr, "MediaTrack*") then
      named[g] = nil
    else
      local idx = PL.track_index(e.tr)
      if idx ~= e.idx then
        moved = moved or {}
        moved[#moved + 1] = { tr = e.tr, from = e.idx }
        e.idx = idx
      end
      if idx then at[idx] = true end
    end
  end
  for _, m in ipairs(moved or {}) do
    -- the block it left: ours no longer, unless one of ours is there now
    if m.from and not at[m.from] and m.from + 1 < PL.TRACKS then
      local b = PL.BASE + (m.from + 1) * PL.STRIDE
      write_names(b, 0, 0)
      for k = PL.F.pub_pre.off, PL.F.fine.off do wr(b + k, 0) end
    end
  end
  for _, e in pairs(named) do
    local b = PL.block(e.tr)
    if b then write_names(b, e.pre, e.post) end
  end
  return moved
end

-- Forget a track (its probes went away). Its block's names come off.
function PL.forget(tr)
  local g = tr and reaper.GetTrackGUID(tr)
  if g and named[g] then
    local b = PL.block(tr)
    if b then write_names(b, 0, 0) end
    named[g] = nil
  end
end

-- THE VISUALIZER'S CHOICE -------------------------------------------------
-- Which of a track's pair the Visualizer shows ("pre", "post" or nil).
-- Kept on the track; an old probe also keeps it in its own checkbox.
function PL.vis_choice(tr)
  local ok, s = reaper.GetSetMediaTrackInfo_String(tr, PL.VIS_EXT, "", false)
  if ok and (s == "pre" or s == "post") then return s end
  return nil
end
function PL.set_vis_choice(tr, which)
  reaper.GetSetMediaTrackInfo_String(tr, PL.VIS_EXT, which or "", true)
end

-- PUBLISHING ---------------------------------------------------------------
-- `which` is "pre" or "post": the probe `fx` is.
function PL.set_publish(tr, fx, which, on)
  PL.set(tr, fx, "pub_" .. which, 1, on and 1 or 0)
end

-- The post probe as Track Analyser's comparison track (or back).
function PL.set_compare(tr, post, on)
  if PL.is_legacy(tr, post) then
    local want = on and 2 or 1
    if PL.legacy_role(tr, post) ~= want then reaper.TrackFX_SetParam(tr, post, PL.LEG_ROLE, want) end
    return
  end
  local b = PL.block(tr)
  if b then wr(b + PL.F.compare.off, on and 1 or 0) end
end

-- A Visualizer slot (0..15, or nil to let go).
function PL.set_vis_slot(tr, fx, which, slot)
  if PL.is_legacy(tr, fx) then
    PL.set(tr, fx, "vis_" .. which, 1, slot or -1)
  else
    PL.set(tr, fx, "vis_" .. which, 1, slot and (slot + 1) or 0)
  end
end

-- Spectrum release for every probe (Track Analyser's setting).
function PL.set_release(ms) wr(PL.CTRL_REL, ms or 0) end

-- for tests
PL._named = named
PL._legacy = legacy

return PL
