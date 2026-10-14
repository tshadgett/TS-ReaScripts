-- @noindex
-- Not a package of its own: installed by TS_ChannelView.lua's @provides.
--[[
  TS_CV_Taps.lua -- gain reduction for plugins that don't report it.

  Some compressors never answer REAPER's GainReduction_dB query, so there
  is nothing to meter. Their reduction can still be MEASURED, from the
  audio going in and coming out, and TS_TrackProbe does the measuring:
  its post probe has tap inputs for up to four plugins (see the notes at
  the top of TS_TrackProbe.jsfx for how the estimate works and where it
  can be wrong).

  This module does the plumbing. For every plugin type ticked "Measure
  gain reduction" or "Input/output meters" in Setup Edit Parameters, on
  every track with a probe pair around it:

    * two spare stereo pairs are found, from 5/6 upward, that no plugin at
      that level reads or writes, no send or receive uses, and (at the top
      level) a parent track has too few channels to receive
    * the plugin in front of the measured one also writes its output to
      the first pair -- the "before" copy -- and the measured plugin also
      writes its output to the second, the "after" copy
    * the post probe's tap pins are pointed at both, told the plugin's
      latency, and told how many taps are in use

  INSIDE CONTAINERS. A plugin between the probes is measured however deep
  it sits in containers. The copies use the same channel numbers at every
  level, chosen free at all of them, and every container on the way in is
  given the pins to carry them: an input pin for the "before" pair, output
  pins for both. Inside a container, the plugins in front of the measured
  one write the "before" copy too, after those in front of the container
  -- so the copy is still the plugin's real input, whatever is bypassed. A
  container's pin counts are only ever raised, and pins it didn't have are
  created empty, so nothing it passed before changes.

  IN PARALLEL. A plugin running in parallel with another (REAPER 7's "Run
  in parallel"), or inside a container that does, isn't measured: its own
  output isn't what the chain passes on, and the copies would sum with
  its neighbours'. TP.status says "parallel" for it.

  Nothing is inserted next to the plugin. What was changed is written on
  the track (P_EXT:TS_CV_TAPS), so it can be taken back out exactly: when
  the box is unticked, the plugin moves, or anything around it changes,
  the old routing is removed and, if still wanted, laid again. Each
  change is one undo point; a check that finds nothing to change makes
  none.

  The readings come out on the probe's tap_grN sliders, read with
  TrackFX_GetParam -- any track, no arming. The same two copies are the
  plugin's input and output, so their levels come out too (tap_inpkN and
  the rest). A plugin wanted for its levels alone -- one that reports its
  own reduction -- gets a tap marked "levels only" (tap_nogr), which costs
  the probe a few operations a sample instead of a filterbank. The probe only measures while
  something keeps gmem[73] moving, which TP.update does every frame.

  THE ZERO. Each time playback stops, the pre probe plays a second of
  quiet pink noise at two levels through the chain while the post probe
  stays silent, and the taps take what they see as "no reduction" (see
  THE ZERO POINT in TS_TrackProbe.jsfx). This module arms the pre probe
  for that (cal_arm) while it has taps to serve, bumps tap_gen when the
  routing is laid so old zeros are forgotten, and reads tap_calN back.
  "Measure the zero while stopped" in Setup can turn it off everywhere.
--]]

local U = require("TS_CV_Util")
local M = require("TS_CV_Mappings")
local RQ = require("TS_CV_ReaEQ")
local RC = require("TS_CV_ReaComp")
local St = require("TS_CV_State")

local TP = {}

TP.PROBE_NAME = "TS_TrackProbe"
TP.MAX_TAPS   = 4
TP.EXT_KEY    = "P_EXT:TS_CV_TAPS"

-- A tapped plugin's delay from input to output, samples, as the trace
-- measured it from the audio (TS_CV_Trace): used for its tap in place of
-- its reported latency. { [guid] = samples }
TP.measured_lag = {}
function TP.set_measured_lag(guid, n)
  if TP.measured_lag[guid] ~= n then TP.measured_lag[guid] = n end
end
TP.GMEM_NS    = "TS_TA_Mem"
TP.HB_SLOT    = 73
TP.WAVE_SLOT  = 74   -- which track's post probe writes the per-tap waveforms

-- TS_TrackProbe slider indices, 0-based as TrackFX_GetParam sees them.
TP.P_ROLE  = 0
TP.P_TAPN  = 5
TP.P_LAG   = 6      -- 6..9
TP.P_RST   = 10     -- 10..13
TP.P_GR    = 14     -- 14..17
TP.P_CAL   = 18     -- 18..21  0 none, 1 measured, 2 level-dependent, 3 touched since
TP.P_GEN   = 22     -- bumped on every new routing
TP.P_ARM   = 23     -- pre probe: measure the zero while stopped
TP.P_NOGR  = 24     -- taps measuring levels only, a bit per tap
TP.P_INPK  = 25     -- 25..28  input peak, dBFS
TP.P_OUTPK = 29     -- 29..32  output peak
TP.P_INRMS = 33     -- 33..36  input RMS
TP.P_OUTRMS = 37    -- 37..40  output RMS
TP.P_MB    = 41     -- the multiband tap, 1..4 (0 none)
TP.P_MBX   = 42     -- 42..44  its crossovers, Hz (0 unused)
TP.P_MBGR  = 45     -- 45..48  each of its bands' reduction, dB
TP.P_FINE  = 49     -- the tap measured in third-octaves, 1..4 (0 none; no longer asked for)
TP.P_MBL   = 50     -- 50..53  each multiband band's input level, dBFS (1.8.0)
-- The reduction by frequency (third-octaves, before against after) is
-- retired: comparing before with after held up for one number, not for
-- thirty. Its code stays, switched off here.
TP.FINE_ON = false
TP.FINE_GM = 0x70000   -- its results, + track index * TP.FINE_GSTR (see the probe)
TP.FINE_GSTR = 128

TP.ZERO_KEY = "tap_zero"   -- ExtState, "0" turns the stop-time zero off

TP.FIRST_CH  = 5    -- 1-based; 1/2 are the signal, 3/4 are sidechains
TP.MAX_CH    = 64

TP.CHECK_EVERY = 1.0    -- seconds between re-checks of any one track

-- ---------------------------------------------------------------------
-- pure: channels and masks
-- ---------------------------------------------------------------------

-- A pin mapping is 64 channels in two 32-bit halves. Channel `ch` is
-- 1-based.
function TP.bit(ch)
  if ch <= 32 then return 1 << (ch - 1), 0 end
  return 0, 1 << (ch - 33)
end

-- Channels (1-based) set in a lo/hi pair of masks, into the set `into`.
function TP.channels_of(lo, hi, into)
  into = into or {}
  lo, hi = math.floor(lo or 0), math.floor(hi or 0)
  for c = 1, 32 do
    if (lo >> (c - 1)) & 1 == 1 then into[c] = true end
    if (hi >> (c - 1)) & 1 == 1 then into[c + 32] = true end
  end
  return into
end

-- The first channel of the lowest pair at or above `start` (made odd, so
-- pairs sit where REAPER's own do) with both channels free.
local function free_pair(used, start)
  local c = start
  if c % 2 == 0 then c = c + 1 end
  while c + 1 <= TP.MAX_CH do
    if not used[c] and not used[c + 1] then return c end
    c = c + 2
  end
  return nil
end

-- `n` pairs, each marked used as it's taken. Returns a list of first
-- channels, or nil if they don't all fit.
function TP.alloc(used, start, n)
  local u = {}
  for k in pairs(used) do u[k] = true end
  local out = {}
  for i = 1, n do
    local c = free_pair(u, start)
    if not c then return nil end
    out[i] = c
    u[c], u[c + 1] = true, true
  end
  return out
end

-- Where to start looking: 5/6, or above a parent track's channel count
-- when the parent has more than four (so it can't receive the copies).
function TP.start_channel(parent_nch)
  local s = math.max(TP.FIRST_CH, (parent_nch or 0) + 1)
  if s % 2 == 0 then s = s + 1 end
  return s
end

-- A send's or receive's channel field -> the channels it covers (1-based).
-- Low ten bits the first channel; above them 0 = stereo, 1 = mono, n = 2n.
function TP.send_channels(v, into)
  into = into or {}
  v = math.floor(v or -1)
  if v < 0 then return into end
  local first = (v & 1023) + 1
  local code = v >> 10
  local n = (code == 0) and 2 or ((code == 1) and 1 or code * 2)
  for c = first, first + n - 1 do into[c] = true end
  return into
end

-- The record on the track: what was routed, so it can be removed exactly.
--   v1|<level guid or TOP>|<post probe guid>|t1|t2...
--   t = <target guid>,<writers>,<before ch>,<after ch>,<latency>,<what>
-- <what> is what the tap is for: "g" gain reduction, "l" levels, or both.
-- A record from before levels existed has no <what>, and means "g".
-- <writers> is every plugin that writes the "before" copy, GUIDs joined
-- with "+" (see WHO WRITES THE BEFORE COPY, below).
--
-- A tap inside containers (v2) adds a seventh field, <path>: the
-- containers the copies pass out through, outermost first, GUIDs joined
-- with "+". A record with no such tap is still written as v1, so an older
-- ChannelView can still read -- and take out -- what this one laid.
function TP.format_record(r)
  if not r or not r.taps or #r.taps == 0 then return "" end
  local v2 = false
  for _, t in ipairs(r.taps) do
    if (t.pathg or "") ~= "" then v2 = true end
  end
  local parts = { v2 and "v2" or "v1", r.level or "TOP", r.probe or "" }
  for _, t in ipairs(r.taps) do
    local s = ("%s,%s,%d,%d,%d,%s"):format(t.guid, t.prev, t.pre, t.post,
                                           t.lag or 0, t.what or "g")
    if v2 then s = s .. "," .. (t.pathg or "") end
    parts[#parts + 1] = s
  end
  return table.concat(parts, "|")
end

function TP.parse_record(s)
  if not s or s == "" then return nil end
  local f = {}
  for p in (s .. "|"):gmatch("([^|]*)|") do f[#f + 1] = p end
  if (f[1] ~= "v1" and f[1] ~= "v2") or #f < 4 then return nil end
  local r = { level = f[2], probe = f[3], taps = {} }
  for i = 4, #f do
    local g, pv, a, b, l, w, pg
    if f[1] == "v2" then
      g, pv, a, b, l, w, pg = f[i]:match("^([^,]+),([^,]+),(%d+),(%d+),(%-?%d+),([gl]*),([^,]*)$")
    else
      g, pv, a, b, l, w = f[i]:match("^([^,]+),([^,]+),(%d+),(%d+),(%-?%d+),?([gl]*)$")
    end
    -- pv is the "+"-joined list of writers, pg the containers
    if g then
      r.taps[#r.taps + 1] = { guid = g, prev = pv, pre = tonumber(a),
                              post = tonumber(b), lag = tonumber(l),
                              what = (w ~= "") and w or "g", pathg = pg or "" }
    end
  end
  if #r.taps == 0 then return nil end
  return r
end

-- Whether two plans route the same things the same way (channels aside:
-- those are chosen at apply time, so a plan is compared on WHAT is tapped
-- and where it sits).
function TP.same_shape(a, b)
  if not a or not b then return (a == nil) == (b == nil) end
  if a.level ~= b.level or a.probe ~= b.probe or #a.taps ~= #b.taps then return false end
  for i, t in ipairs(a.taps) do
    local u = b.taps[i]
    if t.guid ~= u.guid or t.prev ~= u.prev or (t.what or "g") ~= (u.what or "g")
       or (t.pathg or "") ~= (u.pathg or "") then
      return false
    end
  end
  return true
end

-- ---------------------------------------------------------------------
-- REAPER side: finding things
-- ---------------------------------------------------------------------

-- The plugin's own name, even for an instance renamed in REAPER's chain
-- (layouts and probes are found by the plugin, not by your name for it).
local function fx_name(tr, addr)
  local ok, n = reaper.TrackFX_GetFXName(tr, addr, "")
  local rok, ren = reaper.TrackFX_GetNamedConfigParm(tr, addr, "renamed_name")
  if rok and ren and ren ~= "" then
    local fok, orig = reaper.TrackFX_GetNamedConfigParm(tr, addr, "fx_name")
    if fok and orig and orig ~= "" then return orig end
  end
  return ok and n or ""
end

local function fx_guid(tr, addr)
  local g = reaper.TrackFX_GetFXGUID(tr, addr)
  return g or ""
end

local function container_count(tr, addr)
  local ok, v = reaper.TrackFX_GetNamedConfigParm(tr, addr, "container_count")
  if ok then return tonumber(v) end
  return nil
end

-- The addresses at one level: the track's own chain (`caddr` nil) or one
-- container's children, in order.
local function level_items(tr, caddr)
  local out = {}
  if not caddr then
    for i = 0, reaper.TrackFX_GetCount(tr) - 1 do out[#out + 1] = i end
  else
    for j = 0, (container_count(tr, caddr) or 0) - 1 do
      local ok, a = reaper.TrackFX_GetNamedConfigParm(tr, caddr, "container_item." .. j)
      a = ok and tonumber(a)
      if a then out[#out + 1] = a end
    end
  end
  return out
end

local function is_probe(tr, addr)
  return fx_name(tr, addr):find(TP.PROBE_NAME, 1, true) ~= nil
end

local function probe_role(tr, addr)
  return math.floor((reaper.TrackFX_GetParam(tr, addr, TP.P_ROLE) or 0) + 0.5)
end

-- The level holding a pre probe followed by a post probe: its container
-- address (nil for the top), the items, and the indices of the two
-- probes. Searches containers too, since that's where a template keeps
-- them.
local function find_level(tr, caddr, depth)
  depth = depth or 0
  local items = level_items(tr, caddr)
  local pre, post
  for i, a in ipairs(items) do
    if is_probe(tr, a) then
      local role = probe_role(tr, a)
      if role == 0 and not pre then pre = i
      elseif role == 1 and pre and not post then post = i end
    end
  end
  if pre and post then return { caddr = caddr, items = items, pre = pre, post = post } end
  if depth < 4 then
    for _, a in ipairs(items) do
      if (container_count(tr, a) or 0) > 0 then
        local lv = find_level(tr, a, depth + 1)
        if lv then return lv end
      end
    end
  end
  return nil
end

-- Plugins that answer GainReduction_dB themselves never need a tap.
local native = {}
function TP.native_gr(tr, addr, guid)
  local key = guid ~= "" and guid or tostring(addr)
  local v = native[key]
  if v == nil then
    local ok = reaper.TrackFX_GetNamedConfigParm(tr, addr, "GainReduction_dB")
    v = ok and true or false
    native[key] = v
  end
  return v
end

-- Whether a plugin should be tapped: ticked for measuring, and it doesn't
-- report its own reduction (one that does never needs measuring). Never
-- ReaEQ: an EQ has no reduction, and what the probe would "measure" is its
-- curve's effect on the programme, which swings with every note. (Older
-- layouts can still carry Measure=1 for it; it is ignored.)
local function wants_measure(tr, addr)
  local key = St.layout_key(fx_name(tr, addr), fx_guid(tr, addr), tr, addr)
  if RQ.is_eq(key) then return false end
  local layout = M.get(key)
  if not (layout and layout.measure == true) then return false end
  return not TP.native_gr(tr, addr, fx_guid(tr, addr))
end

-- Whether a plugin's input and output levels are wanted (Levels=1).
local function wants_levels(tr, addr)
  local layout = M.get(St.layout_key(fx_name(tr, addr), fx_guid(tr, addr), tr, addr))
  return layout ~= nil and layout.levels == true
end

-- Whether this instance's gain-reduction meter is opened out into its trace
-- (TS_CV_Panel): the trace needs the plugin's own audio, so a plugin that
-- reports its reduction -- and so isn't otherwise tapped -- is tapped for
-- its levels while it's open. Per instance, as the open state is.
--
-- The web companion opens traces of its own, per device: its bridge lists
-- the instances in ExtState TS_CV_WEB/wave, so the window and the bridge --
-- two scripts each re-checking the routing -- agree on what's tapped
-- rather than undoing each other's taps.
local web_wave = { at = -10, set = {} }
local function web_open(guid)
  local now = reaper.time_precise()
  if now - web_wave.at > 0.5 then
    web_wave.at, web_wave.set = now, {}
    local s = reaper.GetExtState("TS_CV_WEB", "wave") or ""
    for g in s:gmatch("[^,]+") do web_wave.set[g] = true end
  end
  return web_wave.set[guid] == true
end

-- A ReaComp panel (TS_CV_CompPanel) shows its trace whenever it's drawn,
-- so it says so each frame it is; it stays tapped a while after it was
-- last drawn, so scrolling it out of view for a moment doesn't take the
-- routing out and put it back.
local PANEL_LINGER = 8
local panel_at = {}   -- guid -> when its panel was last drawn (TP.panel_open, below)
-- Every script's open panels, not just this one's: the window and the web
-- bridge each re-check the routing, so each publishes what it has open in
-- ExtState TS_CV_WEB/panels ("guid=when,..."), and reads the others' --
-- else one of them, not knowing the panel is open, takes the tap out and
-- the other puts it back, once a second, and the history blinks.
local shared = { at = -10, set = {} }
local function shared_panels()
  local now = reaper.time_precise()
  if now - shared.at > 0.5 then
    shared.at, shared.set = now, {}
    local s = reaper.GetExtState("TS_CV_WEB", "panels") or ""
    for g, t in s:gmatch("([^,=]+)=([^,]+)") do
      local when = tonumber(t)
      if when and now - when < PANEL_LINGER then shared.set[g] = when end
    end
  end
  return shared.set
end
local function panel_open(guid)
  local now = reaper.time_precise()
  local t = panel_at[guid]
  if t and now - t < PANEL_LINGER then return true end
  local st = shared_panels()[guid]
  return st ~= nil and now - st < PANEL_LINGER
end
TP.panel_is_open = panel_open

-- this script's open panels, merged with the others' that are still
-- fresh, written every half second while there are any
local panels_written, panels_at = "", -10
local function publish_panels(now)
  if now - panels_at < 0.5 then return end
  panels_at = now
  local all = {}
  for g, t in pairs(shared_panels()) do all[g] = t end
  for g, t in pairs(panel_at) do
    if now - t < PANEL_LINGER then all[g] = t end
  end
  local parts = {}
  for g, t in pairs(all) do parts[#parts + 1] = g .. "=" .. string.format("%.2f", t) end
  table.sort(parts)
  local s = table.concat(parts, ",")
  if s ~= panels_written then
    panels_written = s
    reaper.SetExtState("TS_CV_WEB", "panels", s, false)
  end
end

local function wants_wave(tr, addr)
  local guid = fx_guid(tr, addr)
  if panel_open(guid) then return true end
  if not (St.is_gr_open(guid) or web_open(guid)) then return false end
  local key = St.layout_key(fx_name(tr, addr), guid, tr, addr)
  -- the web page's ReaComp canvas, open on some device
  if RC.is_comp(key) then return true end
  local layout = M.get(key)
  return layout ~= nil and M.meter_of(layout) ~= nil
end

-- Whether this instance's panel wants its reduction split by frequency:
-- a multiband or de-esser layout's (its bands), or any panel showing
-- its reduction by frequency (TP.want_fine). It is measured then even
-- when the plugin reports a reduction of its own.
local fine_asked = {}
function TP.want_fine(guid) fine_asked[guid] = reaper.time_precise() end
local function wants_mb(tr, addr)
  local guid = fx_guid(tr, addr)
  if not panel_open(guid) then return false end
  if fine_asked[guid] and reaper.time_precise() - fine_asked[guid] < 1.0 then return true end
  local layout = M.get(St.layout_key(fx_name(tr, addr), guid, tr, addr))
  local cv = layout and layout.canvas
  local k = cv and cv.kind
  if k == "eq" then
    -- a dynamic EQ: what its bands are doing
    for _, b in ipairs(cv.bands or {}) do if M.band_dynamic(b) then return true end end
    return false
  end
  return k == "multi" or k == "deess"
end

-- Whether a probe is new enough to measure levels (TS_TrackProbe 1.4.0+).
-- A project keeps running the JSFX it compiled when it was opened, so after
-- an update the old probe is still there until the project is reopened --
-- and its parameter 24 onward are REAPER's own (bypass, wet), not levels.
-- Asked by NAME, so it can't be fooled by a count. Cached per instance.
local levels_ok = {}
function TP.probe_has_levels(tr, probe)
  if not tr or not probe then return false end
  local key = tostring(tr) .. ":" .. (reaper.TrackFX_GetFXGUID(tr, probe) or tostring(probe))
  local v = levels_ok[key]
  if v == nil then
    local ok, nm = reaper.TrackFX_GetParamName(tr, probe, TP.P_INPK, "")
    v = (ok and nm and nm:lower():find("input peak", 1, true)) ~= nil
    levels_ok[key] = v
  end
  return v
end

-- The bits of tap_nogr: the taps that measure levels and not reduction.
function TP.nogr_mask(taps)
  local m = 0
  for i, t in ipairs(taps or {}) do
    if not (t.what or "g"):find("g", 1, true) then m = m | (1 << (i - 1)) end
  end
  return m
end

-- REAPER's "parallel" setting: 0 runs after the one before, 1 or 2
-- alongside it.
local function parallel_of(tr, addr)
  local ok, v = reaper.TrackFX_GetNamedConfigParm(tr, addr, "parallel")
  v = ok and tonumber(v) or 0
  return v == 1 or v == 2
end

-- Whether the item at `i` in a level runs in parallel with a neighbour: it
-- is flagged (a flag on a level's first slot means nothing), or the one
-- after it is.
local function in_parallel(tr, items, i)
  if i > 1 and parallel_of(tr, items[i]) then return true end
  return items[i + 1] ~= nil and parallel_of(tr, items[i + 1])
end

TP.MAX_DEPTH = 8     -- containers deep, below the probes' level

local function copy_list(l)
  local o = {}
  for i, v in ipairs(l) do o[i] = v end
  return o
end

-- Every plugin between the probes, however deep in containers, in chain
-- order: { addr, writers, path, parallel }. `writers` are the addresses
-- that write its "before" copy, `path` the containers it sits in below the
-- probes' level, outermost first, and `parallel` whether it -- or any
-- container on its path -- runs in parallel with a neighbour.
--
-- WHO WRITES THE BEFORE COPY
--   Not just the plugin in front: every plugin from the pre probe up to
--   the measured one. A BYPASSED plugin writes nothing to its extra pins
--   -- REAPER passes the buffer straight through -- so with one writer,
--   bypassing it left the copy silent and the reading dead. With all of
--   them writing, a bypassed one leaves the copy as the enabled one
--   before it wrote it, which is the same audio a bypassed plugin passes
--   on. So the copy is always the measured plugin's real input, whatever
--   is bypassed, and a bypass never needs re-routing.
--
--   Inside containers the same holds level by level: whatever is in front
--   of the container at each level writes the copy, the container carries
--   it in on an input pin, and whatever is in front of the plugin inside
--   writes it again. A container in front -- not one the plugin is in --
--   writes it as a single plugin would, from its own outputs.
local function candidates(tr, lv)
  local out = {}
  local writers = { lv.items[lv.pre] }
  local path = {}
  local function walk(items, from, to, par, depth)
    for i = from, to do
      local a = items[i]
      local p = par or in_parallel(tr, items, i)
      if (container_count(tr, a) or 0) > 0 then
        if depth < TP.MAX_DEPTH then
          local kids = level_items(tr, a)
          local mark = #writers
          path[#path + 1] = a
          walk(kids, 1, #kids, p, depth + 1)
          path[#path] = nil
          for k = #writers, mark + 1, -1 do writers[k] = nil end
        end
      elseif not is_probe(tr, a) then
        out[#out + 1] = { addr = a, writers = copy_list(writers),
                          path = copy_list(path), parallel = p }
      end
      writers[#writers + 1] = a
    end
  end
  walk(lv.items, lv.pre + 1, lv.post - 1, false, 0)
  return out
end

-- What SHOULD be tapped on a track right now: the level, and up to four
-- plugins between its probes that want measuring -- their gain
-- reduction, their levels, or both. nil when nothing does (or there are
-- no probes).
function TP.desired(tr)
  local lv = find_level(tr, nil)
  if not lv then return nil, nil end
  local r = {
    level = lv.caddr and fx_guid(tr, lv.caddr) or "TOP",
    probe = fx_guid(tr, lv.items[lv.post]),
    taps = {},
  }
  for _, c in ipairs(candidates(tr, lv)) do
    if #r.taps >= TP.MAX_TAPS then break end
    local a = c.addr
    local gr = not c.parallel and (wants_measure(tr, a) or wants_mb(tr, a))
    local lvl = not c.parallel
                and (wants_levels(tr, a) or (not gr and wants_wave(tr, a)))
    if gr or lvl then
      local ok, pdc = reaper.TrackFX_GetNamedConfigParm(tr, a, "pdc")
      local gs, pg = {}, {}
      for _, w in ipairs(c.writers) do gs[#gs + 1] = fx_guid(tr, w) end
      for _, ca in ipairs(c.path) do pg[#pg + 1] = fx_guid(tr, ca) end
      r.taps[#r.taps + 1] = {
        guid = fx_guid(tr, a), prev = table.concat(gs, "+"),
        addr = a, writers = c.writers, path = c.path, pathg = table.concat(pg, "+"),
        -- how long the input is held back to sit on the output: as measured
        -- from the audio when the trace has found it (a plugin's reported
        -- latency can be wrong: a de-esser reporting none was 2048 samples
        -- out, which reads as 9 dB of reduction it wasn't doing), else as
        -- the plugin reports
        lag = TP.measured_lag[fx_guid(tr, a)] or math.floor(tonumber(ok and pdc or 0) or 0),
        what = (gr and "g" or "") .. (lvl and "l" or ""),
      }
    end
  end
  if #r.taps == 0 then return nil, lv end
  return r, lv
end

-- Every plugin and container on the track, by GUID, however deep: what a
-- record names can have moved anywhere since it was laid.
local function guid_map(tr)
  local map = {}
  local function walk(caddr, depth)
    for _, a in ipairs(level_items(tr, caddr)) do
      map[fx_guid(tr, a)] = a
      if depth < TP.MAX_DEPTH + 4 and (container_count(tr, a) or 0) > 0 then
        walk(a, depth + 1)
      end
    end
  end
  walk(nil, 0)
  return map
end

-- ---------------------------------------------------------------------
-- REAPER side: pins
-- ---------------------------------------------------------------------

local function io_size(tr, addr)
  local _, i, o = reaper.TrackFX_GetIOSize(tr, addr)
  return math.max(0, i or 0), math.max(0, o or 0)
end

local function get_pin(tr, addr, out, pin)
  local lo, hi = reaper.TrackFX_GetPinMappings(tr, addr, out and 1 or 0, pin)
  return math.floor(lo or 0), math.floor(hi or 0)
end

local function set_pin(tr, addr, out, pin, lo, hi)
  reaper.TrackFX_SetPinMappings(tr, addr, out and 1 or 0, pin, lo & 0xFFFFFFFF, hi & 0xFFFFFFFF)
end

-- Adds (on) or removes (not on) channel `ch` on one pin.
local function pin_channel(tr, addr, out, pin, ch, on)
  local lo, hi = get_pin(tr, addr, out, pin)
  local bl, bh = TP.bit(ch)
  if on then lo, hi = lo | bl, hi | bh
  else lo, hi = lo & ~bl, hi & ~bh end
  set_pin(tr, addr, out, pin, lo, hi)
end

-- The plugin's L and R outputs also write to `ch` and `ch + 1` (or stop
-- writing to them). A one-output plugin writes both.
local function out_copy(tr, addr, ch, on)
  local _, nout = io_size(tr, addr)
  if nout < 1 then return end
  pin_channel(tr, addr, true, 0, ch, on)
  pin_channel(tr, addr, true, nout >= 2 and 1 or 0, ch + 1, on)
end

local function nconf(tr, addr, key, default)
  local ok, v = reaper.TrackFX_GetNamedConfigParm(tr, addr, key)
  return tonumber(ok and v or "") or default
end

-- The channels every item at one level reads or writes, into `used`.
local function items_used(tr, items, used)
  for _, a in ipairs(items) do
    local nin, nout = io_size(tr, a)
    if is_probe(tr, a) then nin = math.min(nin, 2) end
    for p = 0, nin - 1 do
      local lo, hi = get_pin(tr, a, false, p)
      TP.channels_of(lo, hi, used)
    end
    for p = 0, nout - 1 do
      local lo, hi = get_pin(tr, a, true, p)
      TP.channels_of(lo, hi, used)
    end
  end
end

-- Inside a container the copies pass out through: what its plugins use,
-- and the channels its own pins carry in and out. By the pins' MAPPINGS,
-- not their count -- the count only ever grows (see lay), and pins left
-- empty carry nothing.
local function container_used(tr, c, used)
  items_used(tr, level_items(tr, c), used)
  for p = 0, nconf(tr, c, "container_nch_in", 2) - 1 do
    local lo, hi = get_pin(tr, c, false, p)
    if lo ~= 0 or hi ~= 0 then used[p + 1] = true end
  end
  for p = 0, nconf(tr, c, "container_nch_out", 2) - 1 do
    local lo, hi = get_pin(tr, c, true, p)
    if lo ~= 0 or hi ~= 0 then used[p + 1] = true end
  end
end

-- Every channel something at this level reads or writes, plus sends and
-- receives at the top.
local function used_channels(tr, lv)
  local used = { [1] = true, [2] = true, [3] = true, [4] = true }
  -- (A probe's tap pins only ever READ, and the post probe's are ours to
  -- set: neither makes a channel unusable -- items_used skips them.)
  items_used(tr, lv.items, used)
  if not lv.caddr then
    for i = 0, reaper.GetTrackNumSends(tr, 0) - 1 do
      TP.send_channels(reaper.GetTrackSendInfo_Value(tr, 0, i, "I_SRCCHAN"), used)
    end
    for i = 0, reaper.GetTrackNumSends(tr, 1) - 1 do
      TP.send_channels(reaper.GetTrackSendInfo_Value(tr, 1, i, "I_SRCCHAN"), used)
    end
    for i = 0, reaper.GetTrackNumSends(tr, -1) - 1 do
      TP.send_channels(reaper.GetTrackSendInfo_Value(tr, -1, i, "I_DSTCHAN"), used)
    end
  else
    local ok, ni = reaper.TrackFX_GetNamedConfigParm(tr, lv.caddr, "container_nch_in")
    local ok2, no = reaper.TrackFX_GetNamedConfigParm(tr, lv.caddr, "container_nch_out")
    for c = 1, math.max(tonumber(ok and ni or 0) or 0, tonumber(ok2 and no or 0) or 0) do used[c] = true end
  end
  return used
end

-- ---------------------------------------------------------------------
-- REAPER side: laying and lifting the routing
-- ---------------------------------------------------------------------

local function read_record(tr)
  local ok, s = reaper.GetSetMediaTrackInfo_String(tr, TP.EXT_KEY, "", false)
  return TP.parse_record(ok and s or "")
end

local function write_record(tr, r)
  reaper.GetSetMediaTrackInfo_String(tr, TP.EXT_KEY, TP.format_record(r), true)
end

-- A container a tap's copies pass out through: input pins for the
-- "before" pair, output pins for both, each on its own channel number
-- (container pin k is the container's channel k + 1, and the copies keep
-- their numbers at every level). Adds (on) or removes them; a pin the
-- container hasn't got is left alone.
local function path_pins(tr, c, t, on)
  local nin = nconf(tr, c, "container_nch_in", 0)
  local nout = nconf(tr, c, "container_nch_out", 0)
  for _, ch in ipairs({ t.pre, t.pre + 1 }) do
    if ch - 1 < nin then pin_channel(tr, c, false, ch - 1, ch, on) end
  end
  for _, ch in ipairs({ t.pre, t.pre + 1, t.post, t.post + 1 }) do
    if ch - 1 < nout then pin_channel(tr, c, true, ch - 1, ch, on) end
  end
end

-- Raises one of a container's pin counts to at least `want`, never lowers
-- it, and empties the pins it creates: whatever REAPER maps a new pin to,
-- it carried nothing before, so it carries nothing now.
local function grow_pins(tr, c, key, out, want)
  local n = nconf(tr, c, key, 2)
  if n >= want then return end
  reaper.TrackFX_SetNamedConfigParm(tr, c, key, tostring(want))
  for p = n, want - 1 do set_pin(tr, c, out, p, 0, 0) end
end

-- Takes out exactly what `rec` says was put in. Plugins that have since
-- gone are skipped: there is nothing left on them to undo.
local function lift(tr, rec)
  if not rec then return end
  local lv = find_level(tr, nil)
  local map = guid_map(tr)
  local probe = lv and map[rec.probe]
  for _, t in ipairs(rec.taps) do
    for g in t.prev:gmatch("[^+]+") do
      local w = map[g]
      if w then out_copy(tr, w, t.pre, false) end
    end
    local tgt = map[t.guid]
    if tgt then out_copy(tr, tgt, t.post, false) end
    for g in (t.pathg or ""):gmatch("[^+]+") do
      local c = map[g]
      if c then path_pins(tr, c, t, false) end
    end
  end
  if probe then
    for p = 2, 2 + TP.MAX_TAPS * 4 - 1 do set_pin(tr, probe, false, p, 0, 0) end
    reaper.TrackFX_SetParam(tr, probe, TP.P_TAPN, 0)
    if TP.probe_has_levels(tr, probe) then reaper.TrackFX_SetParam(tr, probe, TP.P_NOGR, 0) end
  end
  if lv then reaper.TrackFX_SetParam(tr, lv.items[lv.pre], TP.P_ARM, 0) end
  write_record(tr, nil)
end

-- Lays `want` down: channels, pins, latency, the record.
local function lay(tr, want, lv)
  local used = used_channels(tr, lv)
  -- The copies keep their channel numbers all the way out, so they must
  -- be free inside every container they pass through as well.
  local conts = {}       -- container address -> the taps through it
  local order = {}
  for _, t in ipairs(want.taps) do
    for _, c in ipairs(t.path or {}) do
      if not conts[c] then
        conts[c] = {}
        order[#order + 1] = c
        container_used(tr, c, used)
      end
      table.insert(conts[c], t)
    end
  end
  local start = TP.FIRST_CH
  if not lv.caddr then
    local parent = reaper.GetParentTrack(tr)
    start = TP.start_channel(parent and reaper.GetMediaTrackInfo_Value(parent, "I_NCHAN") or 0)
  end
  local pairs_ = TP.alloc(used, start, #want.taps * 2)
  if not pairs_ then return false, "no free channels" end

  local top = 0
  local probe = lv.items[lv.post]
  for i, t in ipairs(want.taps) do
    t.pre, t.post = pairs_[i * 2 - 1], pairs_[i * 2]
    top = math.max(top, t.post + 1)
  end
  -- Room for them: the track's channel count, or the container's.
  if not lv.caddr then
    local n = reaper.GetMediaTrackInfo_Value(tr, "I_NCHAN")
    if n < top then reaper.SetMediaTrackInfo_Value(tr, "I_NCHAN", top + (top % 2)) end
  else
    local ok, n = reaper.TrackFX_GetNamedConfigParm(tr, lv.caddr, "container_nch")
    n = tonumber(ok and n or 2) or 2
    if n < top then reaper.TrackFX_SetNamedConfigParm(tr, lv.caddr, "container_nch", tostring(top + (top % 2))) end
  end
  -- And in every container on the way: channels, and pins to carry them.
  for _, c in ipairs(order) do
    local need_in, need_out = 0, 0
    for _, t in ipairs(conts[c]) do
      need_in = math.max(need_in, t.pre + 1)
      need_out = math.max(need_out, t.pre + 1, t.post + 1)
    end
    if nconf(tr, c, "container_nch", 2) < top then
      reaper.TrackFX_SetNamedConfigParm(tr, c, "container_nch", tostring(top + (top % 2)))
    end
    grow_pins(tr, c, "container_nch_in", false, need_in)
    grow_pins(tr, c, "container_nch_out", true, need_out)
    for _, t in ipairs(conts[c]) do path_pins(tr, c, t, true) end
  end

  for i, t in ipairs(want.taps) do
    for _, w in ipairs(t.writers) do out_copy(tr, w, t.pre, true) end
    out_copy(tr, t.addr, t.post, true)
    -- The probe's pins for this tap: before L/R, after L/R, each on
    -- exactly one channel.
    local p0 = 2 + (i - 1) * 4
    for k, ch in ipairs({ t.pre, t.pre + 1, t.post, t.post + 1 }) do
      local lo, hi = TP.bit(ch)
      set_pin(tr, probe, false, p0 + k - 1, lo, hi)
    end
    reaper.TrackFX_SetParam(tr, probe, TP.P_LAG + i - 1, t.lag or 0)
  end
  reaper.TrackFX_SetParam(tr, probe, TP.P_TAPN, #want.taps)
  if TP.probe_has_levels(tr, probe) then
    reaper.TrackFX_SetParam(tr, probe, TP.P_NOGR, TP.nogr_mask(want.taps))
  end
  -- New routing: whatever zeros the probe measured belonged to the old one.
  reaper.TrackFX_SetParam(tr, probe, TP.P_GEN,
    (math.floor(reaper.TrackFX_GetParam(tr, probe, TP.P_GEN) or 0) + 1) % 1000000)
  reaper.TrackFX_SetParam(tr, lv.items[lv.pre], TP.P_ARM, TP.zero_on() and 1 or 0)
  write_record(tr, want)
  return true
end

-- Brings one track into line with what's wanted. Returns true when it
-- changed anything.
function TP.sync(tr)
  local rec = read_record(tr)
  local want, lv = TP.desired(tr)
  if TP.same_shape(rec, want) then
    if not want then return false end
    -- Same plugins, same places: only the latency can have moved.
    local probe = lv.items[lv.post]
    local changed = false
    for i, t in ipairs(want.taps) do
      local cur = reaper.TrackFX_GetParam(tr, probe, TP.P_LAG + i - 1)
      if math.floor(cur + 0.5) ~= t.lag then
        reaper.TrackFX_SetParam(tr, probe, TP.P_LAG + i - 1, t.lag)
        rec.taps[i].lag = t.lag
        changed = true
      end
    end
    if math.floor(reaper.TrackFX_GetParam(tr, probe, TP.P_TAPN) + 0.5) ~= #want.taps then
      reaper.TrackFX_SetParam(tr, probe, TP.P_TAPN, #want.taps)
      changed = true
    end
    local mask = TP.nogr_mask(want.taps)
    if TP.probe_has_levels(tr, probe)
       and math.floor((reaper.TrackFX_GetParam(tr, probe, TP.P_NOGR) or 0) + 0.5) ~= mask then
      reaper.TrackFX_SetParam(tr, probe, TP.P_NOGR, mask)
    end
    -- The pre probe armed for the zero, or not, as the setting says --
    -- also arms routing laid before the zero existed.
    local pre = lv.items[lv.pre]
    local arm = TP.zero_on() and 1 or 0
    if math.floor((reaper.TrackFX_GetParam(tr, pre, TP.P_ARM) or 0) + 0.5) ~= arm then
      reaper.TrackFX_SetParam(tr, pre, TP.P_ARM, arm)
    end
    if changed then write_record(tr, rec) end
    return false
  end
  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)
  lift(tr, rec)
  local ok = true
  if want then ok = lay(tr, want, lv) end
  reaper.PreventUIRefresh(-1)
  reaper.Undo_EndBlock(want and "ChannelView: route measurement taps"
                            or "ChannelView: remove measurement taps", -1)
  -- Couldn't lay it (no free channels): say so, so the caller stops
  -- retrying -- and making an undo point -- every second.
  return ok, not ok
end

-- ---------------------------------------------------------------------
-- status, and adding a probe pair
-- ---------------------------------------------------------------------

-- Where a plugin stands: "ok" (between a probe pair, at any depth, so it
-- can be measured), "parallel" (between them, but running in parallel --
-- see IN PARALLEL), "no_probes" (the track has no pair at all), or
-- "outside" (there is a pair, but not around this plugin).
function TP.status(tr, guid)
  local lv = find_level(tr, nil)
  if not lv then return "no_probes" end
  for _, c in ipairs(candidates(tr, lv)) do
    if fx_guid(tr, c.addr) == guid then return c.parallel and "parallel" or "ok" end
  end
  return "outside"
end

-- Whether a track has a probe pair (anywhere: top level or in a
-- container). Cached for a second per track -- the header asks every frame.
local has_cache = {}
function TP.has_probes(tr)
  if not tr then return false end
  local key = tostring(tr)
  local now = reaper.time_precise()
  local c = has_cache[key]
  if not c or now - c.t > 1.0 then
    c = { t = now, v = find_level(tr, nil) ~= nil }
    has_cache[key] = c
  end
  return c.v
end

-- REAPER resolves a JSFX by path under Effects/, which depends on how it
-- was installed; each is tried until one instantiates.
TP.PROBE_PATHS = {
  "TS-ReaScripts/TS_TrackAnalyser/TS_TrackProbe.jsfx",
  "TS-ReaScripts/TS_ChannelView/TS_TrackProbe.jsfx",
  "TS_TrackAnalyser/TS_TrackProbe.jsfx",
  "TS_TrackProbe.jsfx",
  "JS: TS_TrackProbe",
}

local function add_probe(tr, pos)
  for _, nm in ipairs(TP.PROBE_PATHS) do
    local idx = reaper.TrackFX_AddByName(tr, nm, false, pos)
    if idx and idx >= 0 then return idx end
  end
  return nil
end

-- ARA. REAPER allows an ARA plugin (Melodyne, VocAlign...) only in a
-- track's first slot, and refuses -- with an error box -- anything put in
-- front of it. So the pre probe goes second on such a track: the ARA
-- plugin sits outside the pair and isn't measured, which costs nothing
-- (it isn't a compressor), and the zero's test noise starts after it.
--
-- REAPER has no query for it. The FX chain says so instead: an instance
-- running ARA saves an ARA archive name at the end of its header line
--   <VST "VST3: Melodyne (Celemony)" Melodyne.vst3 0 "" 2142…{…} com.celemony.ara.chunk.13
-- where any other plugin has "". The names below are a fallback for an
-- instance that hasn't saved one yet; one of them in the first slot
-- without ARA just means the pre probe goes after it.
TP.ARA_NAMES = { "melodyne", "vocalign", "revoice", "spectralayers",
                 "spectral editor", "auto-tune" }

function TP.ara_header(line)
  local last = line and line:match("(%S+)%s*$")
  if not last or last:find('"', 1, true) then return false end
  return last:lower():find("ara", 1, true) ~= nil
end

function TP.ara_first(tr)
  if reaper.TrackFX_GetCount(tr) == 0 then return false end
  local ok, chunk = reaper.GetTrackStateChunk(tr, "", false)
  if ok and TP.ara_header(chunk:match("<FXCHAIN.-\n%s*(<[^\n]*)")) then return true end
  local name = fx_name(tr, 0):lower()
  for _, n in ipairs(TP.ARA_NAMES) do
    if name:find(n, 1, true) then return true end
  end
  return false
end

-- A pre probe in the first slot (the second behind an ARA plugin) and a
-- post probe in the last, both idle, the way Track Analyser's own "insert
-- probes" does it. Returns true, or false and why not.
function TP.insert_probes(tr)
  if find_level(tr, nil) then return true end
  local first = TP.ara_first(tr) and 1 or 0
  -- one already there (the other deleted): only the missing one is added
  local have_pre, have_post = TP.top_probes(tr)
  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)
  local pre = have_pre or add_probe(tr, -1000 - first)    -- -1000 - n: insert at slot n
  -- a pre probe put in front of the lone post probe moves it along one
  if have_post and not have_pre and pre and pre <= have_post then have_post = have_post + 1 end
  local post = pre and (have_post or add_probe(tr, -1))   -- -1: append
  if pre then
    reaper.TrackFX_SetParam(tr, pre, TP.P_ROLE, 0)
    reaper.TrackFX_SetParam(tr, pre, 1, 0)    -- Publish: idle
  end
  if post then
    reaper.TrackFX_SetParam(tr, post, TP.P_ROLE, 1)
    reaper.TrackFX_SetParam(tr, post, 1, 0)
  end
  reaper.PreventUIRefresh(-1)
  reaper.Undo_EndBlock("ChannelView: add TS_TrackProbe pair", -1)
  TP.invalidate()
  if not (pre and post) then
    return false, "REAPER couldn't load TS_TrackProbe.jsfx -- is it installed under Effects?"
  end
  return true
end

-- ---------------------------------------------------------------------
-- hidden, and kept at the ends
-- ---------------------------------------------------------------------
-- The probes have nothing to show, so the plugin row leaves them out
-- (unless "Show the probes in the plugin row" is ticked) -- and since you
-- can't see them, ChannelView keeps them where they belong: the pre probe
-- first (second behind an ARA plugin), the post probe last, after any
-- insert, move or removal. One of the pair dragged into a container comes
-- back out to its end; a pair kept together inside a container is left
-- alone (that's deliberate).
--
-- The moves make NO undo point of their own. If they did, undoing your
-- insert would first undo the move, which would put the probe straight
-- back -- and you could never get past it. Without one, undo takes the
-- chain back to before your insert, probes and all.

TP.SHOWN_KEY = "probes_shown"
function TP.probes_shown()
  return reaper.GetExtState("TS_ChannelView", TP.SHOWN_KEY) == "1"
end
function TP.set_probes_shown(on)
  reaper.SetExtState("TS_ChannelView", TP.SHOWN_KEY, on and "1" or "0", true)
end

-- The top-level pre and post probe slots (the first of each), or nil.
function TP.top_probes(tr)
  local pre, post
  for i = 0, (reaper.TrackFX_GetCount(tr) or 0) - 1 do
    if is_probe(tr, i) then
      local r = probe_role(tr, i)
      if r == 0 and not pre then pre = i
      elseif r == 1 and not post then post = i end
    end
  end
  return pre, post
end

-- The first probe of `role` inside any container, its address.
local function nested_probe(tr, caddr, role, depth)
  depth = depth or 0
  for _, a in ipairs(level_items(tr, caddr)) do
    if caddr and is_probe(tr, a) and probe_role(tr, a) == role then return a end
    if depth < 4 and (container_count(tr, a) or 0) > 0 then
      local hit = nested_probe(tr, a, role, depth + 1)
      if hit then return hit end
    end
  end
  return nil
end

local function top_slot_of(tr, guid)
  for i = 0, (reaper.TrackFX_GetCount(tr) or 0) - 1 do
    if fx_guid(tr, i) == guid then return i end
  end
  return nil
end

-- Moves the FX at `src` to top-level slot `final` (REAPER reads the
-- destination against the chain before the move, which within one level
-- is the final slot; one try more covers anything else).
local function move_to(tr, src, final)
  local g = fx_guid(tr, src)
  for _, d in ipairs({ final, final + 1 }) do
    reaper.TrackFX_CopyToTrack(tr, src, tr, d, true)
    local at = top_slot_of(tr, g)
    if at == final or not at then return true end
    src = at
  end
  return true
end

-- Puts the probes back where they belong. Returns true if anything moved.
function TP.keep_in_place(tr)
  if not tr or TP.probes_shown() or tr == reaper.GetMasterTrack(0) then return false end
  local pre, post = TP.top_probes(tr)
  if not (pre or post) then return false end
  local moved = false
  reaper.PreventUIRefresh(1)
  -- one of the pair taken into a container: back out to its end
  if pre and not post then
    local a = nested_probe(tr, nil, 1)
    if a then move_to(tr, a, reaper.TrackFX_GetCount(tr)); moved = true end
  elseif post and not pre then
    local a = nested_probe(tr, nil, 0)
    if a then move_to(tr, a, TP.ara_first(tr) and 1 or 0); moved = true end
  end
  pre, post = TP.top_probes(tr)
  if pre and post then
    local n = reaper.TrackFX_GetCount(tr)
    if post ~= n - 1 then move_to(tr, post, n - 1); moved = true end
    pre = TP.top_probes(tr)
    if pre ~= 0 then
      -- ask about ARA (it reads the chain) only when it could matter
      local want = TP.ara_first(tr) and 1 or 0
      if pre ~= want then move_to(tr, pre, want); moved = true end
    end
  end
  reaper.PreventUIRefresh(-1)
  if moved then TP.invalidate() end
  return moved
end

-- The plugin row without the top-level probes.
function TP.strip_probes(tr, list)
  local T = require("TS_CV_FXTree")
  return T.without(list, function(slot) return is_probe(tr, slot) end)
end

-- Which top-level probes the track has: "pair", "pre", "post" (one of
-- them missing) or nil, and (for a pair) which is in the Visualizer.
-- Cached for a second, as has_probes is -- the header asks every frame.
local which_cache = {}
function TP.probe_state(tr)
  if not tr then return nil end
  local key = tostring(tr)
  local now = reaper.time_precise()
  local c = which_cache[key]
  if not c or now - c.t > 1.0 then
    local v, vis
    if find_level(tr, nil) then v, vis = "pair", TP.vis_state(tr)
    else
      local pre, post = TP.top_probes(tr)
      v = (pre and "pre") or (post and "post") or nil
    end
    c = { t = now, v = v, vis = vis }
    which_cache[key] = c
  end
  return c.v, c.vis
end

-- "Include in Visualizer Spectrum" (the probe's own slider4): TS_Visualizer
-- takes the first probe on a track with it ticked, and shows what that
-- probe hears -- the pre probe the track's input, the post probe its
-- output. "pre", "post" or nil.
TP.P_VIS = 3
function TP.vis_state(tr)
  local lv = tr and find_level(tr, nil)
  if not lv then return nil end
  local function on(a) return (reaper.TrackFX_GetParam(tr, a, TP.P_VIS) or 0) >= 0.5 end
  if on(lv.items[lv.pre]) then return "pre" end
  if on(lv.items[lv.post]) then return "post" end
  return nil
end
function TP.set_vis(tr, which)
  local lv = tr and find_level(tr, nil)
  if not lv then return end
  reaper.Undo_BeginBlock()
  reaper.TrackFX_SetParam(tr, lv.items[lv.pre], TP.P_VIS, which == "pre" and 1 or 0)
  reaper.TrackFX_SetParam(tr, lv.items[lv.post], TP.P_VIS, which == "post" and 1 or 0)
  reaper.Undo_EndBlock(which and "ChannelView: include the track in the Visualizer"
                              or "ChannelView: leave the track out of the Visualizer", -1)
  which_cache = {}
end

-- Takes the probes off the track: the measuring routing first (every pin
-- it set put back), then the pair and any lone pre or post probe at the
-- top level. One undo point. A Comparison probe (another track's) stays.
function TP.remove_probes(tr)
  if not tr then return end
  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)
  lift(tr, read_record(tr))
  local lv = find_level(tr, nil)
  if lv and lv.caddr then
    -- a pair inside a container: the later one first, so the other's
    -- address still holds
    reaper.TrackFX_Delete(tr, lv.items[lv.post])
    lv = find_level(tr, nil) or lv
    local pre = nil
    for _, a in ipairs(level_items(tr, lv.caddr)) do
      if is_probe(tr, a) and probe_role(tr, a) == 0 then pre = a break end
    end
    if pre then reaper.TrackFX_Delete(tr, pre) end
  end
  for i = (reaper.TrackFX_GetCount(tr) or 0) - 1, 0, -1 do
    if is_probe(tr, i) and probe_role(tr, i) <= 1 then reaper.TrackFX_Delete(tr, i) end
  end
  reaper.PreventUIRefresh(-1)
  reaper.Undo_EndBlock("ChannelView: remove TS_TrackProbe pair", -1)
  TP.invalidate()
end

-- The pre or post probe's address, for opening its window.
function TP.probe_addr(tr, which)
  local lv = tr and find_level(tr, nil)
  if not lv then return nil end
  return lv.items[which == "pre" and lv.pre or lv.post]
end

-- ---------------------------------------------------------------------
-- reading
-- ---------------------------------------------------------------------

-- Per track: { [target guid] = { probe guid, index } } from the record,
-- and the probe's last known address.
local readers = {}

local function reader_for(tr)
  local key = tostring(tr)
  local rd = readers[key]
  local now = reaper.time_precise()
  if rd and now - rd.t < 0.5 then return rd end
  local rec = read_record(tr)
  rd = { t = now, map = {}, what = {}, probe = nil }
  if rec then
    for i, t in ipairs(rec.taps) do rd.map[t.guid] = i; rd.what[t.guid] = t.what or "g" end
    local lv = find_level(tr, nil)
    if lv then
      local a = lv.items[lv.post]
      if fx_guid(tr, a) == rec.probe then rd.probe = a end
    end
  end
  readers[key] = rd
  return rd
end

-- The tap on this plugin, if there is one doing `what` ("g" reduction,
-- "l" levels): its index, and the reader.
local function tap_for(tr, guid, what)
  if not tr or not guid then return nil end
  local rd = reader_for(tr)
  local i = rd.map[guid]
  if not i or not (rd.what[guid] or "g"):find(what, 1, true) then return nil end
  return i, rd
end

-- This plugin's tap, whatever it measures: its index (1..4) and the post
-- probe's address, or nil. For the per-tap waveforms, which every tap has.
function TP.tap_index(tr, guid)
  local i, rd = tap_for(tr, guid, "")
  if not i or not rd.probe then return nil end
  return i, rd.probe
end

-- Whether this plugin's gain reduction is being measured by a tap.
function TP.is_tapped(tr, guid)
  return tap_for(tr, guid, "g") ~= nil
end

-- Whether this plugin's input and output levels are being measured.
function TP.is_metered(tr, guid)
  return tap_for(tr, guid, "l") ~= nil
end

-- Its levels, dBFS: { in_pk, out_pk, in_rms, out_rms }, or nil when it
-- isn't metered. -150 while the probe isn't running. { old = true } when the
-- probe on the track predates levels (see TP.probe_has_levels).
function TP.levels(tr, guid)
  local i, rd = tap_for(tr, guid, "l")
  if not i or not rd.probe then return nil end
  if not TP.probe_has_levels(tr, rd.probe) then return { old = true } end
  local function g(base) return reaper.TrackFX_GetParam(tr, rd.probe, base + i - 1) or -150 end
  return { in_pk = g(TP.P_INPK), out_pk = g(TP.P_OUTPK),
           in_rms = g(TP.P_INRMS), out_rms = g(TP.P_OUTRMS) }
end

-- The measured reduction, positive dB, or nil when this plugin isn't
-- tapped. 0 while the probe isn't running.
function TP.reading(tr, guid)
  local i, rd = tap_for(tr, guid, "g")
  if not i or not rd.probe then return nil end
  local v = reaper.TrackFX_GetParam(tr, rd.probe, TP.P_GR + i - 1)
  return math.max(0, v or 0)
end

-- Whether a probe is new enough to split a multiband's bands
-- (TS_TrackProbe 1.6.0+): as with levels, a project keeps running the probe
-- it opened with.
local mb_ok = {}
function TP.probe_has_mb(tr, probe)
  if not tr or not probe then return false end
  local key = tostring(tr) .. ":" .. (reaper.TrackFX_GetFXGUID(tr, probe) or tostring(probe))
  local v = mb_ok[key]
  if v == nil then
    local ok, nm = reaper.TrackFX_GetParamName(tr, probe, TP.P_MB, "")
    v = (ok and nm and nm:lower():find("multiband", 1, true)) ~= nil
    mb_ok[key] = v
  end
  return v
end

-- Asks the probe to split this plugin's measured audio at its crossovers
-- (Hz, ascending, 1 to 3 of them). One multiband tap per probe: the last
-- open panel to ask has it. Writes only what changed. Returns whether the
-- plugin is measured that way.
function TP.set_mb(tr, guid, xos)
  local i, rd = tap_for(tr, guid, "g")
  if not i or not rd.probe or not TP.probe_has_mb(tr, rd.probe) then return false end
  local function put(p, v)
    if math.abs((reaper.TrackFX_GetParam(tr, rd.probe, p) or 0) - v) > 0.5 then
      reaper.TrackFX_SetParam(tr, rd.probe, p, v)
    end
  end
  put(TP.P_MB, i)
  for k = 1, 3 do put(TP.P_MBX + k - 1, xos[k] and math.floor(xos[k] + 0.5) or 0) end
  return true
end

-- Asks the probe to measure this plugin in third-octaves. One tap per
-- probe: an instance asking keeps it while it goes on asking (half a
-- second), so two open panels don't take it in turns. Returns whether it
-- has it.
local fine_owner = {}
-- Whether this plugin can be measured in third-octaves: true; "old" when
-- it's tapped but the project still runs a probe from before 1.7.0 (a
-- project keeps the JSFX it opened with); false when it isn't tapped.
function TP.fine_ok(tr, guid)
  local i, rd = tap_for(tr, guid, "g")
  if not i or not rd.probe then return false end
  local ok, nm = reaper.TrackFX_GetParamName(tr, rd.probe, TP.P_FINE, "")
  return (ok and nm and nm:lower():find("third", 1, true)) and true or "old"
end
function TP.set_fine(tr, guid, polite)
  local i, rd = tap_for(tr, guid, "g")
  if not i or not rd.probe then return false end
  local ok, nm = reaper.TrackFX_GetParamName(tr, rd.probe, TP.P_FINE, "")
  if not (ok and nm and nm:lower():find("third", 1, true)) then return false end
  local now = reaper.time_precise()
  local key = tostring(tr)
  local o = fine_owner[key]
  if o and o.guid ~= guid and now - o.t < 0.5 then return false end
  -- polite (the web bridge): only when no other tap has it, so it never
  -- takes the measurement from a window's panel
  local cur = math.floor((reaper.TrackFX_GetParam(tr, rd.probe, TP.P_FINE) or 0) + 0.5)
  if polite and cur ~= 0 and cur ~= i then return false end
  fine_owner[key] = { guid = guid, t = now, tr = tr, probe = rd.probe, i = i,
                      pguid = reaper.TrackFX_GetFXGUID(tr, rd.probe) }
  if math.floor((reaper.TrackFX_GetParam(tr, rd.probe, TP.P_FINE) or 0) + 0.5) ~= i then
    reaper.TrackFX_SetParam(tr, rd.probe, TP.P_FINE, i)
  end
  return true
end

-- Lets go of a measurement nobody has asked for in a while: the probe
-- stops paying for it, and another panel (or the web page) can have it.
function TP.fine_tidy(now)
  for key, o in pairs(fine_owner) do
    if now - o.t > 1.5 then
      fine_owner[key] = nil
      if reaper.ValidatePtr(o.tr, "MediaTrack*") and o.probe
         and reaper.TrackFX_GetFXGUID(o.tr, o.probe) == o.pguid
         and math.floor((reaper.TrackFX_GetParam(o.tr, o.probe, TP.P_FINE) or 0) + 0.5) == o.i then
        reaper.TrackFX_SetParam(o.tr, o.probe, TP.P_FINE, 0)
      end
    end
  end
end

-- This plugin's reduction in third-octaves, when the probe is measuring
-- it that way: { n, f = { centre Hz }, d = { dB from its zero, below 0
-- reduced, nil no signal }, lv = { level going in, dBFS }, cal = the zero
-- measured }, or nil.
local fine_seen = {}
function TP.fine(tr, guid)
  local i, rd = tap_for(tr, guid, "g")
  if not i or not rd.probe then return nil end
  local idx = math.floor(reaper.GetMediaTrackInfo_Value(tr, "IP_TRACKNUMBER") or 0) - 1
  if idx < 0 then return nil end
  local b = TP.FINE_GM + idx * TP.FINE_GSTR
  if not TP._fine_gm then reaper.gmem_attach(TP.GMEM_NS); TP._fine_gm = true end
  if math.floor(reaper.gmem_read(b + 2) + 0.5) ~= i then return nil end
  -- a frame every 20 ms or so while it runs: a count that stops is old
  local seq, now = reaper.gmem_read(b), reaper.time_precise()
  local fs = fine_seen[guid]
  if not fs or fs.seq ~= seq then fine_seen[guid] = { seq = seq, t = now }
  elseif now - fs.t > 0.6 then return nil end
  local n = math.floor(reaper.gmem_read(b + 1) + 0.5)
  if n < 1 or n > 31 then return nil end
  local out = { n = n, f = {}, d = {}, lv = {}, cal = reaper.gmem_read(b + 3) > 0.5 }
  for k = 1, n do
    out.f[k] = 1000 * 2 ^ ((k - 17) / 3)
    local d = reaper.gmem_read(b + 8 + k - 1)
    out.d[k] = (d > -900) and d or nil
    out.lv[k] = reaper.gmem_read(b + 72 + k - 1)
  end
  return out
end

-- A multiband plugin's band k reduction, positive dB, or nil when its
-- bands aren't being measured.
function TP.band_gr(tr, guid, k)
  local i, rd = tap_for(tr, guid, "g")
  if not i or not rd.probe or not TP.probe_has_mb(tr, rd.probe) then return nil end
  if math.floor((reaper.TrackFX_GetParam(tr, rd.probe, TP.P_MB) or 0) + 0.5) ~= i then return nil end
  return math.max(0, reaper.TrackFX_GetParam(tr, rd.probe, TP.P_MBGR + k - 1) or 0)
end

-- A multiband's bands, where they are: { nb, own (each band has its own
-- edges, as FabFilter Pro-MB's do, rather than shared crossovers), [k] =
-- { lo, hi (Hz), used } , xs (the crossovers to split the measured audio
-- at, ascending, for TP.set_mb), at[k] (band k's place among the split
-- bands, nil when it isn't one) }. Crossovers out of order are put in
-- order; a band's missing edge is its neighbour's.
TP.MB_LO, TP.MB_HI = 20, 20000
local MB_DEFAULT_XO = { 120, 1000, 5000 }
local function hz_of(tr, addr, p, rev)
  if not p then return nil end
  local UN = require("TS_CV_Units")
  local nv = reaper.TrackFX_GetParamNormalized(tr, addr, p) or 0
  local v, unit = UN.parse(RC.text(tr, addr, p, nv))
  if v and unit == "hz" and v > 0 and v < math.huge then return v end
  local n = rev and (1 - nv) or nv
  return TP.MB_LO * (TP.MB_HI / TP.MB_LO) ^ n
end
-- What a band's "in use" control says, from its words: "off" (no band
-- in that slot: unused, none), "byp" (a band, switched off: disabled,
-- bypassed -- FabFilter Pro-MB's State reads Disabled / Enabled / Unused),
-- or "on"; a plain switch, by its position.
function TP.mb_state_of(text, nv)
  local t = (text or ""):lower()
  for _, w in ipairs({ "unused", "not used", "none", "empty" }) do if t:find(w, 1, true) then return "off" end end
  for _, w in ipairs({ "disabled", "disable", "bypass", "inactive", "mute" }) do if t:find(w, 1, true) then return "byp" end end
  if t:match("^%s*off%s*$") then return "off" end
  for _, w in ipairs({ "enabled", "used", "active", "on" }) do if t:find(w, 1, true) then return "on" end end
  return (nv or 0) >= 0.5 and "on" or "off"
end
function TP.mb_state(tr, addr, p)
  if not p then return "on" end
  local nv = reaper.TrackFX_GetParamNormalized(tr, addr, p) or 0
  return TP.mb_state_of(RC.text(tr, addr, p, nv), nv)
end
-- whether a band's "in use" control says there's a band there (bypassed
-- or not)
function TP.mb_used(tr, addr, p) return TP.mb_state(tr, addr, p) ~= "off" end
function TP.mb_plan(tr, addr, cv)
  local nb = cv.nb or 3
  local R, rev = cv.roles or {}, cv.rev or {}
  local plan = { nb = nb, own = false, xs = {}, at = {} }
  for k = 1, nb do if R["B" .. k .. "Low"] or R["B" .. k .. "High"] then plan.own = true end end
  if not plan.own then
    local prev = TP.MB_LO
    for k = 1, nb - 1 do
      local x = hz_of(tr, addr, R["Crossover" .. k], rev["Crossover" .. k]) or MB_DEFAULT_XO[k] or 1000
      x = math.max(x, prev * 1.02)
      plan.xs[k] = x
      prev = x
    end
    for k = 1, nb do
      local st = TP.mb_state(tr, addr, R["B" .. k .. "Used"])
      plan[k] = { lo = (k == 1) and TP.MB_LO or plan.xs[k - 1], hi = (k == nb) and TP.MB_HI or plan.xs[k],
                  used = st ~= "off", byp = st == "byp" }
      plan.at[k] = k
    end
    return plan
  end
  -- each band its own edges; one missing is its neighbour's
  local lo, hi = {}, {}
  for k = 1, nb do
    lo[k] = hz_of(tr, addr, R["B" .. k .. "Low"], rev["B" .. k .. "Low"])
    hi[k] = hz_of(tr, addr, R["B" .. k .. "High"], rev["B" .. k .. "High"])
  end
  for k = 1, nb do
    local l = lo[k] or (k > 1 and hi[k - 1]) or TP.MB_LO
    local h = hi[k] or (k < nb and lo[k + 1]) or TP.MB_HI
    if h < l then l, h = h, l end
    local st = TP.mb_state(tr, addr, R["B" .. k .. "Used"])
    plan[k] = { lo = math.max(TP.MB_LO, l), hi = math.min(TP.MB_HI, math.max(h, l * 1.01)),
                used = st ~= "off", byp = st == "byp" }
  end
  -- the measured audio split between the bands in use, low to high
  local order = {}
  for k = 1, nb do if plan[k].used then order[#order + 1] = k end end
  table.sort(order, function(a, b) return plan[a].lo < plan[b].lo end)
  while #order > 4 do table.remove(order) end
  local prev = TP.MB_LO
  for j = 1, #order do
    plan.at[order[j]] = j
    if j < #order then
      local a, b = plan[order[j]], plan[order[j + 1]]
      local x = math.max(math.sqrt(a.hi * b.lo), prev * 1.02)
      plan.xs[j] = x
      prev = x
    end
  end
  return plan
end
-- Band k's reduction from the split (positive dB), or nil: not measured,
-- not in use, or too narrow (under half an octave, or all under 40 Hz) to
-- hold enough of the music to say -- a near-empty band compares next to
-- nothing with next to nothing.
function TP.mb_reading(tr, guid, plan, k)
  local b, j = plan[k], plan.at[k]
  if not b or not j or not b.used then return nil end
  if b.hi / b.lo < 1.41 or b.hi <= 40 then return nil end
  return TP.band_gr(tr, guid, j)
end

-- Whether a probe publishes the multiband bands' input levels
-- (TS_TrackProbe 1.8.0+). Asked by name, cached per instance.
local mbl_ok = {}
function TP.probe_has_mbl(tr, probe)
  if not tr or not probe then return false end
  local key = tostring(tr) .. ":" .. (reaper.TrackFX_GetFXGUID(tr, probe) or tostring(probe))
  local v = mbl_ok[key]
  if v == nil then
    local ok, nm = reaper.TrackFX_GetParamName(tr, probe, TP.P_MBL, "")
    v = (ok and nm and nm:lower():find("input level", 1, true)) ~= nil
    mbl_ok[key] = v
  end
  return v
end

-- Band k's input level, dBFS (a 2 ms mean square scaled so a sine reads
-- its peak, falling 20 dB/s): measured on the way in only, so it needs no
-- zero and no alignment. nil when the band isn't in use or split, or the
-- probe is older; "old" when the probe predates it.
function TP.mb_level(tr, guid, plan, k)
  local b, j = plan[k], plan.at[k]
  if not b or not j or not b.used then return nil end
  local i, rd = tap_for(tr, guid, "g")
  if not i or not rd.probe or not TP.probe_has_mb(tr, rd.probe) then return nil end
  if not TP.probe_has_mbl(tr, rd.probe) then return "old" end
  if math.floor((reaper.TrackFX_GetParam(tr, rd.probe, TP.P_MB) or 0) + 0.5) ~= i then return nil end
  local v = reaper.TrackFX_GetParam(tr, rd.probe, TP.P_MBL + j - 1)
  if not v or v <= -149 then return nil end
  return v
end

-- Where a measured plugin's zero stands: 0 never measured (the probe is
-- still using the zero it learnt from the music), 1 measured, 2 measured
-- but the plugin was level-dependent even at the test level, 3 measured
-- but the plugin was touched since. nil when it isn't tapped.
function TP.cal_status(tr, guid)
  local i, rd = tap_for(tr, guid, "g")
  if not i or not rd.probe then return nil end
  return math.floor((reaper.TrackFX_GetParam(tr, rd.probe, TP.P_CAL + i - 1) or 0) + 0.5)
end

-- One line on it, for tooltips.
function TP.cal_text(st)
  if not TP.zero_on() then
    return "Zero learnt from the music (measuring it while stopped is off in\n" ..
           "Setup), so a compressor that never lets go reads low."
  end
  if st == 1 then return "Zero measured at the last stop."
  elseif st == 2 then
    return "Zero measured at the last stop, but the plugin was already\n" ..
           "working on the quiet test signal, so it may read a little low."
  elseif st == 3 then
    return "Zero measured at the last stop; the plugin has been touched since.\n" ..
           "If that was make-up or output gain, stop playback to measure again."
  end
  return "Zero not measured yet: it's measured each time playback stops\n" ..
         "(needs REAPER's \"Run FX when stopped\"). Until then it's learnt\n" ..
         "from the music, so a compressor that never lets go reads low."
end

-- Whether the zero is measured while stopped. On unless turned off.
function TP.zero_on()
  return reaper.GetExtState("TS_ChannelView", TP.ZERO_KEY) ~= "0"
end

function TP.set_zero_on(on)
  reaper.SetExtState("TS_ChannelView", TP.ZERO_KEY, on and "1" or "0", true)
  TP.invalidate()
end

-- A track's total gain reduction: every plugin that reports its own,
-- plus every measured one, added in dB (compressors in series multiply,
-- so their reductions add). Returns total, estimated (true when any part
-- was measured), and the parts: { { name, db, est } ... } in chain order.
-- nil when the track has nothing that reports or is measured.
--
-- Which plugins report is re-read once a second per track, not per frame.
local sources = {}
function TP.track_total(tr)
  if not tr then return nil end
  local key = tostring(tr)
  local now = reaper.time_precise()
  local src = sources[key]
  if not src or now - src.t > 1.0 then
    src = { t = now, list = {} }
    local T = require("TS_CV_FXTree")
    for _, fx in ipairs(T.collect(tr)) do
      local nat = T.reports_gr_natively(tr, fx.addr, fx.guid)
      if nat or TP.is_tapped(tr, fx.guid) then
        src.list[#src.list + 1] = { addr = fx.addr, guid = fx.guid,
          name = U.fx_label(fx), est = not nat }
      end
    end
    sources[key] = src
  end
  if #src.list == 0 then return nil end
  local T = require("TS_CV_FXTree")
  local total, est, parts = 0, false, {}
  for _, s in ipairs(src.list) do
    local v = T.gain_reduction(tr, s.addr) or 0
    total = total + v
    if s.est then est = true end
    parts[#parts + 1] = { name = s.name, db = v, est = s.est,
                          cal = s.est and TP.cal_status(tr, s.guid) or nil }
  end
  return total, est, parts
end

-- ---------------------------------------------------------------------
-- relearning
-- ---------------------------------------------------------------------

-- A measured plugin was touched: its make-up or EQ may have moved, so the
-- probe drops what it learnt from the music, and marks a measured zero as
-- touched-since (it's measured again at the next stop).
function TP.touched(tr, guid)
  local i, rd = tap_for(tr, guid, "g")
  if not i or not rd.probe then return end
  local p = TP.P_RST + i - 1
  reaper.TrackFX_SetParam(tr, rd.probe, p, ((reaper.TrackFX_GetParam(tr, rd.probe, p) or 0) + 1) % 1000000)
end

local last_touch = nil
local function poll_touched()
  local ok, trn, fxn, parm = reaper.GetLastTouchedFX()
  if not ok then return end
  local k = ("%d:%d:%d"):format(trn, fxn, parm)
  if k == last_touch then return end
  local first = (last_touch == nil)
  last_touch = k
  if first then return end
  local tr = (trn == 0) and reaper.GetMasterTrack(0) or reaper.GetTrack(0, trn - 1)
  if tr then TP.touched(tr, fx_guid(tr, fxn)) end
end

-- ---------------------------------------------------------------------
-- the per-frame part
-- ---------------------------------------------------------------------

local hb, attached = 0, false
local rr, next_at = 0, {}
local any_until = 0

-- THE PER-TAP WAVEFORMS (PER-PLUGIN WAVEFORMS in TS_TrackProbe.jsfx) are
-- written by one track's post probe at a time, the one named in
-- gmem[WAVE_SLOT]. A panel showing a trace asks for its track each frame;
-- TP.update names it, and stops naming it half a second after the last ask.
local wave_tr, wave_at, wave_written = nil, -10, -1
function TP.wave_track(tr)
  wave_tr, wave_at = tr, reaper.time_precise()
  if not TP.active then any_until = 0 end
end

-- A ReaComp panel being drawn (see panel_open above).
function TP.panel_open(guid)
  local now = reaper.time_precise()
  local was = panel_at[guid]
  panel_at[guid] = now
  -- newly open: re-check the routing now rather than on its next turn
  if not was or now - was > PANEL_LINGER then any_until = 0; next_at = {} end
end

-- Whether any plugin type is ticked for measuring, or any track still has
-- routing to take out. Checked now and then, not every frame.
local function anything_to_do()
  if M.any_measure() then return true end
  if reaper.time_precise() - wave_at < 2 then return true end
  if next(shared_panels()) then return true end
  for i = 0, reaper.CountTracks(0) - 1 do
    local ok, s = reaper.GetSetMediaTrackInfo_String(reaper.GetTrack(0, i), TP.EXT_KEY, "", false)
    if ok and s ~= "" then return true end
  end
  return false
end

-- Call once per frame. Keeps the probes running (the heartbeat), picks up
-- touched plugins, and re-checks one track's routing -- round robin, each
-- track at most once a second -- so a big project costs a little every
-- frame rather than a lot at once.
function TP.update(now)
  now = now or reaper.time_precise()
  TP.fine_tidy(now)
  if now >= any_until then
    TP.active = anything_to_do()
    any_until = now + 2
  end
  publish_panels(now)
  if not TP.active then return end
  if not attached then reaper.gmem_attach(TP.GMEM_NS); attached = true end
  hb = (hb + 1) % 1000000
  reaper.gmem_write(TP.HB_SLOT, hb)
  do
    local want = 0
    if wave_tr and now - wave_at < 0.5 and reaper.ValidatePtr(wave_tr, "MediaTrack*") then
      want = math.max(0, math.floor(reaper.GetMediaTrackInfo_Value(wave_tr, "IP_TRACKNUMBER")))
    end
    -- The window and the web bridge both run this: whichever is showing a
    -- trace keeps its track named, so one letting go (writing 0) can't
    -- leave the other's trace waiting.
    if want ~= wave_written or (want > 0 and reaper.gmem_read(TP.WAVE_SLOT) ~= want) then
      reaper.gmem_write(TP.WAVE_SLOT, want)
      wave_written = want
    end
  end
  poll_touched()
  local n = reaper.CountTracks(0)
  if n == 0 then return end
  rr = rr % n
  local tr = reaper.GetTrack(0, rr)
  rr = rr + 1
  local key = tostring(tr)
  if (next_at[key] or 0) <= now then
    next_at[key] = now + TP.CHECK_EVERY
    local changed, failed = TP.sync(tr)
    if changed then readers[key] = nil end
    if failed then next_at[key] = now + 30 end
  end
end

-- Forget cached answers (a layout changed: re-check everything now).
function TP.invalidate()
  next_at, readers, native, sources = {}, {}, {}, {}
  levels_ok = {}
  has_cache = {}
  which_cache = {}
  any_until = 0
end

return TP
