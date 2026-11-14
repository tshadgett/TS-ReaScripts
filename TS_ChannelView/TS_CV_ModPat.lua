-- @noindex
-- Not a package of its own: installed by TS_ChannelView.lua's @provides.
--[[
  TS_CV_ModPat.lua -- the patterns of the Steps and MSEG modulators.

  A Steps modulator's 32 values (and which of them are joined to the one
  before) and an MSEG's points aren't parameters: the modulator plugin
  (TS_CV_Modulators.jsfx) keeps them, with the project, and this reads
  and writes them through gmem TS_CV_Mod (the plugin's STEPS AND MSEG).
  Each plugin answers to its Instance number, which this gives it: a new
  one, or a copy of another (a duplicated track), gets one of its own.

  One message at a time, the next sent once the plugin has said it's done
  (or after a moment, tried again): a pattern being drawn is sent as it
  is now, not every step of the way.
  What's read is kept, by plugin and modulator, so a tile draws from here.
--]]

local MP = {}

MP.NS, MP.HOME = "TS_CV_Mod", "TS_TA_Mem"   -- ours; and the one the rest of ChannelView keeps attached
MP.INST = 250                                -- the plugin's Instance parameter
MP.STEPS, MP.POINTS = 32, 16
local READ_STEPS, WRITE_STEPS, READ_POINTS, WRITE_POINTS = 1, 2, 3, 4
local WAIT, TRIES = 0.5, 5
local FRESH = 2          -- a pattern read again after this long (another script may have changed it)

local cache = {}       -- key -> { vals, joins } or { pts }
local pending = {}     -- key -> a message not yet sent (the latest)
local order = {}       -- keys in the order they were asked for
local inflight = nil   -- { seq, at, msg }
local failed = {}      -- key -> when a read last gave up
local ids = {}         -- Instance -> the plugin's GUID that has it

-- gmem in our namespace, then back to the one the rest uses
local function with(fn)
  reaper.gmem_attach(MP.NS)
  local r = table.pack(pcall(fn))
  reaper.gmem_attach(MP.HOME)
  if not r[1] then error(r[2], 0) end
  return table.unpack(r, 2, r.n)
end
MP._with = with

-- The plugin's Instance number: its own, or a new one when it has none
-- or another plugin has the same (a copy)
function MP.inst(track, slot)
  local guid = reaper.TrackFX_GetFXGUID(track, slot) or ""
  local id = math.floor((reaper.TrackFX_GetParam(track, slot, MP.INST) or 0) + 0.5)
  local other = id > 0 and ids[id]
  if id <= 0 or (other and other ~= guid) then
    repeat id = math.random(1, 1048575) until not ids[id]
    reaper.TrackFX_SetParam(track, slot, MP.INST, id)
  end
  ids[id] = guid
  return id
end

local function key_of(track, slot, j)
  return (reaper.TrackFX_GetFXGUID(track, slot) or tostring(track)) .. ":" .. j
end
MP.key_of = key_of

local function queue(key, msg)
  if not pending[key] then order[#order + 1] = key end
  pending[key] = msg
end

-- A default pattern for a new one
function MP.default(kind)
  if kind == "steps" then
    local v = { 0.1, 0.25, 0.7, 0.68, 0.55, 0.8, 0.2, 0.1, 0.95, 0.5, 0.6, 0.52, 0.9, 0.22, 0.65, 0.55 }
    local p = { vals = {}, joins = {} }
    for i = 1, MP.STEPS do p.vals[i] = v[(i - 1) % #v + 1]; p.joins[i] = false end
    return p
  end
  return { pts = { { 0, 0, 0 }, { 0.5, 1, 0 }, { 1, 0, 0 } } }
end

-- The pattern of modulator j of `kind` ("steps" / "mseg"), as last read
-- or written; nil until it has been read (asked for here).
function MP.get(track, slot, j, kind)
  local key = key_of(track, slot, j)
  local p = cache[key]
  local now = reaper.time_precise()
  local have = p and p.kind == kind
  if (not have or now - (p._at or 0) > FRESH)
     and not pending[key] and not (inflight and inflight.msg.key == key)
     and now - (failed[key] or -10) > 2 then
    queue(key, { key = key, track = track, slot = slot, j = j, kind = kind,
                 cmd = (kind == "steps") and READ_STEPS or READ_POINTS })
  end
  return have and p or nil
end

-- A pattern written: kept here at once, and sent
function MP.put(track, slot, j, kind, p)
  local key = key_of(track, slot, j)
  local now = reaper.time_precise()
  p.kind, p._at, p._put = kind, now, now
  cache[key] = p
  queue(key, { key = key, track = track, slot = slot, j = j, kind = kind, p = p,
               cmd = (kind == "steps") and WRITE_STEPS or WRITE_POINTS })
end

-- Forget what's kept of a modulator (its kind changed, or it went)
function MP.forget(track, slot, j)
  local key = key_of(track, slot, j)
  cache[key], pending[key], failed[key] = nil, nil, nil
end

-- Where modulator j is now: the step playing (1-based), or 0..1 along the MSEG
function MP.where(track, slot, j, kind)
  local id = math.floor((reaper.TrackFX_GetParam(track, slot, MP.INST) or 0) + 0.5)
  if id <= 0 then return nil end
  local v = with(function() return reaper.gmem_read(1000 + 8 * (id % 8192) + j - 1) end)
  if kind == "steps" then return math.floor((v or 0) + 0.5) + 1 end
  return v
end

-- what a pattern is in gmem's cells from 10, and back
local function to_cells(msg)
  local out = {}
  if msg.kind == "steps" then
    for i = 1, MP.STEPS do
      out[i] = msg.p.vals[i] or 0
      out[MP.STEPS + i] = msg.p.joins[i] and 1 or 0
    end
  else
    local pts = msg.p.pts
    out[1] = #pts
    for k = 1, MP.POINTS do
      local q = pts[k] or { 0, 0, 0 }
      out[2 + (k - 1) * 3], out[3 + (k - 1) * 3], out[4 + (k - 1) * 3] = q[1], q[2], q[3]
    end
  end
  return out
end
MP._to_cells = to_cells

local function from_cells(kind, read)
  if kind == "steps" then
    local p = { kind = kind, vals = {}, joins = {} }
    for i = 1, MP.STEPS do
      p.vals[i] = math.max(0, math.min(1, read(10 + i - 1) or 0))
      p.joins[i] = i > 1 and (read(10 + MP.STEPS + i - 1) or 0) >= 0.5
    end
    return p
  end
  local n = math.floor((read(10) or 0) + 0.5)
  if n < 2 then return nil end
  local p = { kind = kind, pts = {} }
  for k = 1, math.min(MP.POINTS, n) do
    local b = 11 + (k - 1) * 3
    p.pts[k] = { read(b) or 0, read(b + 1) or 0, read(b + 2) or 0 }
  end
  return p
end
MP._from_cells = from_cells

local function send(msg)
  local id = MP.inst(msg.track, msg.slot)
  return with(function()
    local seq = math.floor(reaper.gmem_read(0) or 0) + 1
    if msg.p then
      for i, v in ipairs(to_cells(msg)) do reaper.gmem_write(10 + i - 1, v) end
    end
    reaper.gmem_write(1, id)
    reaper.gmem_write(2, msg.j)
    reaper.gmem_write(3, msg.cmd)
    reaper.gmem_write(0, seq)
    return seq
  end)
end

-- Once a frame: the message on its way answered, or the next sent
function MP.tick()
  local now = reaper.time_precise()
  if inflight then
    local m = inflight.msg
    local done = with(function()
      if reaper.gmem_read(4) ~= inflight.seq then return false end
      if m.cmd == READ_STEPS or m.cmd == READ_POINTS then
        local p = from_cells(m.kind, reaper.gmem_read)
        local had = cache[m.key]
        if not p then
          -- (an MSEG never written: its default, sent)
          p = MP.default(m.kind)
          MP.put(m.track, m.slot, m.j, m.kind, p)
        elseif not pending[m.key] and not (had and (had._put or 0) >= inflight.at) then
          -- (not over what's been drawn since it was asked)
          p._at = now
          cache[m.key] = p
        elseif had then
          had._at = now
        end
      end
      return true
    end)
    if done then inflight = nil
    elseif now - inflight.at > WAIT then
      -- not answered: tried again, a few times (a write as it is now)
      m.tries = (m.tries or 0) + 1
      if m.tries < TRIES and not pending[m.key] then queue(m.key, m)
      elseif m.cmd == READ_STEPS or m.cmd == READ_POINTS then failed[m.key] = now end
      inflight = nil
    else
      return
    end
  end
  while #order > 0 do
    local key = table.remove(order, 1)
    local m = pending[key]
    pending[key] = nil
    if m and reaper.ValidatePtr2(0, m.track, "MediaTrack*") then
      local ok, seq = pcall(send, m)
      if ok then inflight = { seq = seq, at = now, msg = m } end
      return
    end
  end
end

-- (tests)
function MP._reset() cache, pending, order, inflight, failed, ids = {}, {}, {}, nil, {}, {} end

-- ---------------------------------------------------------------------
-- the patterns themselves (pure)
-- ---------------------------------------------------------------------

-- A Steps pattern never written: every value 0, none joined
function MP.blank(p)
  if p.kind ~= "steps" then return false end
  for i = 1, MP.STEPS do
    if (p.vals[i] or 0) ~= 0 or p.joins[i] then return false end
  end
  return true
end

-- A step's value: its run's first step's (joined steps hold one)
function MP.first(p, i)
  while i > 1 and p.joins[i] do i = i - 1 end
  return i
end
-- the runs of n steps: { first, last } each
function MP.runs(p, n)
  local out, i = {}, 1
  while i <= n do
    local e = i
    while e < n and p.joins[e + 1] do e = e + 1 end
    out[#out + 1] = { i, e }
    i = e + 1
  end
  return out
end

-- An MSEG's level at f (0..1): as the plugin works it out (ms_eval)
function MP.level(p, f)
  local pts = p and p.pts
  if not pts or #pts < 2 then return f end
  if f <= pts[1][1] then return pts[1][2] end
  if f >= pts[#pts][1] then return pts[#pts][2] end
  local k = 1
  while k < #pts - 1 and f >= pts[k + 1][1] do k = k + 1 end
  local a, b = pts[k], pts[k + 1]
  local t = (b[1] > a[1]) and (f - a[1]) / (b[1] - a[1]) or 1
  local c = a[3] or 0
  if math.abs(c) > 0.001 then t = (math.exp(c * 6 * t) - 1) / (math.exp(c * 6) - 1) end
  return a[2] + (b[2] - a[2]) * t
end

-- The notes the scale takes across lo..hi (as the plugin's st_note)
MP.SCALES = { { "Chromatic", 4095 }, { "Major", 2741 }, { "Minor", 1453 }, { "Dorian", 1709 },
              { "Pentatonic major", 661 }, { "Pentatonic minor", 1193 }, { "Harmonic minor", 2477 },
              { "Blues", 1257 } }
function MP.note_of(v, lo, hi, scale, key)
  if v < 0.005 then return nil end
  lo, hi = math.floor(lo + 0.5), math.floor(hi + 0.5)
  if lo > hi then lo, hi = hi, lo end
  local mask = (MP.SCALES[(scale or 0) + 1] or MP.SCALES[1])[2]
  local list = {}
  for n = lo, hi do
    if (mask >> ((n - (key or 0) + 120) % 12)) & 1 == 1 then list[#list + 1] = n end
  end
  if #list == 0 then return nil end
  return list[math.floor(v * (#list - 1) + 0.5) + 1]
end

return MP
