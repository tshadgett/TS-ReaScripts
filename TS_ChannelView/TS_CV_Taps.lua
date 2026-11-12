-- @noindex
-- Not a package of its own: installed by TS_ChannelView.lua's @provides.
--[[
  TS_CV_Taps.lua -- gain reduction for plugins that don't report it.

  Some compressors never answer REAPER's GainReduction_dB query, so there
  is nothing to meter. Their reduction can still be MEASURED, from the
  audio going in and coming out, and TS_TrackProbe does the measuring:
  its post probe has tap inputs for up to eight plugins (four on an older
  probe; see the notes at the top of TS_TrackProbe.jsfx for how the
  estimate works and where it can be wrong).

  This module does the plumbing. For every plugin type ticked "Measure
  gain reduction" or "Input/output meters" in Setup Edit Parameters, on
  every track with a probe pair around it:

    * two spare stereo pairs are found, from 5/6 upward, that no plugin at
      that level reads or writes, no send or receive uses, and (at the top
      level) a parent track has too few channels to receive
    * the plugin in front of the measured one also writes its output to
      the first pair -- the "before" copy -- and the measured plugin also
      writes its output to the second, the "after" copy
    * the post probe's tap pins are pointed at both and told how many
      taps are in use (no delay for the plugin's latency: REAPER already
      holds back the channels a plugin doesn't use by that much)
    * a plugin's inputs past its first two lose the channels the track
      only has because of the copies (a sidechain on 3/4 of a two-channel
      track would key from them), and get them back when the probes go

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
  the probe a few operations a sample instead of a filterbank. The probe
  only measures while something keeps gmem[73] moving, which TP.update
  does every frame.

  THE ZERO. While stopped, for a tap with no zero yet or whose plugin was
  touched since, the pre probe plays a second of quiet pink noise at two
  levels through the chain while the post probe stays silent, and the
  taps take what they see as "no reduction" (see THE ZERO POINT in
  TS_TrackProbe.jsfx). This module arms the pre probe for that (cal_arm)
  while it has taps to serve and the track isn't armed to record, bumps
  tap_gen when the routing is laid so old zeros are forgotten, and reads
  tap_calN back. "Measure the zero while stopped" in Setup can turn it
  off everywhere; ChannelView learning a plugin holds it (TS_CV_Learn).

  MAKE-UP GAIN. A plugin's make-up moves its output as reduction would,
  so each tapped plugin's make-up, in dB, goes to the probe every frame
  (automation included), which takes it out (MAKE-UP GAIN, FOLLOWED in
  TS_TrackProbe.jsfx). Moving it then isn't a touch.
--]]

local U = require("TS_CV_Util")
local M = require("TS_CV_Mappings")
local RQ = require("TS_CV_ReaEQ")
local RC = require("TS_CV_ReaComp")
local St = require("TS_CV_State")
local PL = require("TS_CV_ProbeLink")

local TP = {}

TP.PROBE_NAME = "TS_TrackProbe"
TP.MAX_TAPS   = 8    -- a probe that takes eight; older ones four
TP.EXT_KEY    = "P_EXT:TS_CV_TAPS"

-- How far a tapped plugin's output trails the copy of its input, samples,
-- as the trace measured it from the audio (TS_CV_Trace): a latency it
-- doesn't report. Its tap holds the input back by that. { [guid] = samples }
-- Shared through ExtState TS_CV_WEB/lags ("guid=samples,..."): the window
-- and the web bridge each re-check the routing, and a bridge that only
-- didn't know it would put the tap back to none every time the window laid
-- the measured one (Track Analyser starting over each time).
TP.measured_lag = {}
local lags_read = -10
local function shared_lags()
  local now = reaper.time_precise()
  if now - lags_read < 0.5 then return end
  lags_read = now
  local s = reaper.GetExtState("TS_CV_WEB", "lags") or ""
  for g, n in s:gmatch("([^,=]+)=(%-?%d+)") do TP.measured_lag[g] = tonumber(n) end
end
function TP.set_measured_lag(guid, n)
  shared_lags()
  if TP.measured_lag[guid] == n then return end
  TP.measured_lag[guid] = n
  local parts = {}
  for g, v in pairs(TP.measured_lag) do parts[#parts + 1] = g .. "=" .. v end
  table.sort(parts)
  reaper.SetExtState("TS_CV_WEB", "lags", table.concat(parts, ","), false)
end
function TP.lag_of(guid)
  shared_lags()
  return TP.measured_lag[guid]
end
TP.GMEM_NS    = "TS_TA_Mem"
TP.HB_SLOT    = 73
TP.WAVE_SLOT  = 74   -- which track's post probe writes the per-tap waveforms
TP.GATE_SLOT  = 76   -- moving: only the tracks named in their blocks measure
TP.WATCH_OFF  = 7    -- a track's block: moving while something shows it
TP.WATCH_FOR  = 0.5  -- seconds a track stays named after its last reading

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
TP.P_FINE  = 49     -- the tap measured in third-octaves, 1..4 (0 none; unused while FINE_ON is off)
TP.P_MBL   = 50     -- 50..53  each multiband band's input level, dBFS
-- The reduction by frequency (third-octaves, before against after) is
-- switched off here: comparing before with after holds up for one
-- number, not for thirty.
TP.FINE_ON = false
TP.FINE_GM = 0x70000   -- its results, + track index * TP.FINE_GSTR (see the probe)
TP.FINE_GSTR = 128

TP.ZERO_KEY = "tap_zero"   -- ExtState, "0" turns the stop-time zero off
TP.READING_KEY = "gr_reading"   -- ExtState, "own": a reporting plugin shows its own figure

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
-- A tap with no <what> means "g".
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

-- Every probe on the track, in the order the audio meets them (into
-- containers as it goes). Cached until the project changes.
local order_cache = {}
local function probes_in_order(tr)
  local key = tostring(tr)
  local sc = reaper.GetProjectStateChangeCount(0)
  local c = order_cache[key]
  if c and c.sc == sc then return c.list end
  local list = {}
  local function walk(caddr, depth)
    for _, a in ipairs(level_items(tr, caddr)) do
      if is_probe(tr, a) then list[#list + 1] = { addr = a, caddr = caddr }
      elseif depth < 4 and (container_count(tr, a) or 0) > 0 then walk(a, depth + 1) end
    end
  end
  walk(nil, 0)
  order_cache[key] = { sc = sc, list = list }
  return list
end

-- A probe's role: 0 pre, 1 post, 2 the comparison (Track Analyser's), 3
-- one too many. A legacy probe keeps it in a slider; otherwise it's where
-- it sits: the first probe on the track is the pre, the last the post --
-- as Track Analyser finds them, so the two name a pair the same way. A
-- lone probe is the post when it's last in the chain (its pre deleted),
-- else the pre.
local function probe_role(tr, addr)
  local r = PL.legacy_role(tr, addr)
  if r then return r end
  local list = probes_in_order(tr)
  if #list == 1 then
    local n = reaper.TrackFX_GetCount(tr)
    local one = list[1]
    if one.addr == addr then
      return (not one.caddr and n > 1 and one.addr == n - 1) and 1 or 0
    end
  end
  if list[1] and list[1].addr == addr then return 0 end
  if #list >= 2 and list[#list].addr == addr then
    return PL.get(tr, addr, "compare") >= 0.5 and 2 or 1
  end
  return 3
end
TP.probe_role = probe_role

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
-- curve's effect on the programme, which swings with every note. (A
-- layout carrying Measure=1 for it is ignored.)
-- Plugins that keep their own figure (when they report one): a gate or
-- expander, shut on the probes' quiet test signal so it can't show its
-- zero (the probe finds one that isn't laid out as one: THE ZERO POINT);
-- and those whose reduction is in a band, not the whole signal -- a
-- multiband compressor, a de-esser, a dynamic EQ -- where one figure
-- across the spectrum says too little. By the layout's canvas, else the
-- plugin's name.
local OWN_NAMES = { "multiband", "multi%-band", "multi band", "de%-?ess", "pro%-mb", "pro%-ds",
                    "xcomp", "dynamic eq", "dyn eq", "dyneq", "dynamiceq", "sibil",
                    "gate", "expander", "pro%-g " }
local function keeps_own(tr, addr, layout)
  local cv = layout and layout.canvas
  local k = cv and cv.kind
  if k == "multi" or k == "deess" or k == "gate" then return true end
  if k == "eq" then
    for _, b in ipairs(cv.bands or {}) do if M.band_dynamic(b) then return true end end
  end
  local nm = fx_name(tr, addr):lower()
  for _, p in ipairs(OWN_NAMES) do if nm:find(p) then return true end end
  return false
end
TP._keeps_own = keeps_own

local function wants_measure(tr, addr)
  local key = St.layout_key(fx_name(tr, addr), fx_guid(tr, addr), tr, addr)
  if RQ.is_eq(key) then return false end
  local layout = M.get(key)
  -- a plugin that reports its own reduction: measured too, when that's
  -- what's shown (TP.measured_first; it takes the zero measured while stopped)
  if TP.native_gr(tr, addr, fx_guid(tr, addr)) then
    return TP.measured_first() and TP.zero_on() and not keeps_own(tr, addr, layout)
  end
  return layout ~= nil and (layout.measure == true or (M.has_vu and M.has_vu(layout, "gr")))
end

-- Whether a plugin's input and output levels are wanted (Levels=1, a VU
-- meter showing its in or out, a drive meter, harmonics or curve, or a
-- width).
local function wants_levels(tr, addr)
  local layout = M.get(St.layout_key(fx_name(tr, addr), fx_guid(tr, addr), tr, addr))
  return layout ~= nil and (layout.levels == true or (M.has_vu and M.has_vu(layout, "lvl"))
    or (M.has_vis and (M.has_vis(layout, "drive") or M.has_vis(layout, "harm") or M.has_vis(layout, "scurve")
      or M.has_vis(layout, "width"))))
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
-- a multiband or de-esser layout's (its bands), a frequency range's, or
-- any panel showing its reduction by frequency (TP.want_fine). It is
-- measured then even when the plugin reports a reduction of its own.
local fine_asked = {}
function TP.want_fine(guid) fine_asked[guid] = reaper.time_precise() end
local function wants_mb(tr, addr)
  local guid = fx_guid(tr, addr)
  if not panel_open(guid) then return false end
  if fine_asked[guid] and reaper.time_precise() - fine_asked[guid] < 1.0 then return true end
  local layout = M.get(St.layout_key(fx_name(tr, addr), guid, tr, addr))
  -- an EQ curve's own dynamic bands too, and a frequency range's
  for _, c in ipairs((layout and layout.controls) or {}) do
    for _, b in ipairs((c.vis and c.vis.bands) or {}) do if M.band_dynamic(b) then return true end end
    if c.vis and c.vis.kind == "frange" then return true end
  end
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
    if not PL.is_legacy(tr, probe) then v = true
    else
      local ok, nm = reaper.TrackFX_GetParamName(tr, probe, TP.P_INPK, "")
      v = (ok and nm and nm:lower():find("input peak", 1, true)) ~= nil
    end
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
--   bypassing it would leave the copy silent and the reading dead. With
--   all of them writing, a bypassed one leaves the copy as the enabled one
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

-- How many plugins a probe can measure: one for every four input pins
-- past its own two (34 pins: eight; an older probe's 18: four). Read off
-- the running instance, so a project still running an older probe gets
-- four until it's reopened.
function TP.capacity(tr, probe)
  if not (tr and probe and reaper.TrackFX_GetIOSize) then return 4 end
  local _, ins = reaper.TrackFX_GetIOSize(tr, probe)
  local n = math.floor(((ins or 0) - 2) / 4)
  return math.max(1, math.min(TP.MAX_TAPS, n >= 1 and n or 4))
end

-- What SHOULD be tapped on a track right now: the level, and up to eight
-- plugins between its probes that want measuring -- their gain
-- reduction, their levels, or both. nil when nothing does (or there are
-- no probes).
function TP.desired(tr)
  local lv = find_level(tr, nil)
  if not lv then return nil, nil end
  local cap = TP.capacity(tr, lv.items[lv.post])
  local r = {
    level = lv.caddr and fx_guid(tr, lv.caddr) or "TOP",
    probe = fx_guid(tr, lv.items[lv.post]),
    taps = {},
  }
  for _, c in ipairs(candidates(tr, lv)) do
    if #r.taps >= cap then break end
    local a = c.addr
    local gr = not c.parallel and (wants_measure(tr, a) or wants_mb(tr, a))
    local lvl = not c.parallel
                and (wants_levels(tr, a) or (not gr and wants_wave(tr, a)))
    if gr or lvl then
      local gs, pg = {}, {}
      for _, w in ipairs(c.writers) do gs[#gs + 1] = fx_guid(tr, w) end
      for _, ca in ipairs(c.path) do pg[#pg + 1] = fx_guid(tr, ca) end
      r.taps[#r.taps + 1] = {
        guid = fx_guid(tr, a), prev = table.concat(gs, "+"),
        addr = a, writers = c.writers, path = c.path, pathg = table.concat(pg, "+"),
        -- how long the input is held back to sit on the output. REAPER
        -- already delays the channels a plugin doesn't use by the latency
        -- it reports, so the copy arrives in line: none, unless the trace
        -- has measured otherwise from the audio (a plugin reporting none
        -- but 2048 samples out reads as about 9 dB that isn't there)
        lag = TP.lag_of(fx_guid(tr, a)) or 0,
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

-- The channels the track's sends read and its receives arrive on (hardware
-- outputs too), into `used`.
local function routing_channels(tr, used)
  for i = 0, reaper.GetTrackNumSends(tr, 0) - 1 do
    TP.send_channels(reaper.GetTrackSendInfo_Value(tr, 0, i, "I_SRCCHAN"), used)
  end
  for i = 0, reaper.GetTrackNumSends(tr, 1) - 1 do
    TP.send_channels(reaper.GetTrackSendInfo_Value(tr, 1, i, "I_SRCCHAN"), used)
  end
  for i = 0, reaper.GetTrackNumSends(tr, -1) - 1 do
    TP.send_channels(reaper.GetTrackSendInfo_Value(tr, -1, i, "I_DSTCHAN"), used)
  end
  return used
end

-- Every channel something at this level reads or writes, plus sends and
-- receives at the top.
local function used_channels(tr, lv)
  local used = { [1] = true, [2] = true, [3] = true, [4] = true }
  -- (A probe's tap pins only ever READ, and the post probe's are ours to
  -- set: neither makes a channel unusable -- items_used skips them.)
  items_used(tr, lv.items, used)
  if not lv.caddr then
    routing_channels(tr, used)
  else
    local ok, ni = reaper.TrackFX_GetNamedConfigParm(tr, lv.caddr, "container_nch_in")
    local ok2, no = reaper.TrackFX_GetNamedConfigParm(tr, lv.caddr, "container_nch_out")
    for c = 1, math.max(tonumber(ok and ni or 0) or 0, tonumber(ok2 and no or 0) or 0) do used[c] = true end
  end
  return used
end

-- ---------------------------------------------------------------------
-- REAPER side: plugins kept at the channels they had
-- ---------------------------------------------------------------------

-- Many VST3s follow their track's channel count (REAPER's channel_config
-- 0): Pro-C 3 is stereo on a 2-channel track, quad on 4, 9.1.6 on 16. So
-- when the copies need more channels, such a plugin would change layout
-- and REAPER would wire every pin afresh: its sidechain pins move up past
-- the new main inputs, and a sidechain routed to it stops arriving. Before
-- a level gets more channels, each plugin there that follows the count is
-- held at the count the level had (channel_config N), as is one added
-- later; the record (P_EXT:TS_CV_HOLD) keeps that count and who was held,
-- per level ("TOP", or a container's GUID), so removing the probes puts
-- them back. The probes and ChannelView's own plugins are never held.
local HOLD_KEY = "P_EXT:TS_CV_HOLD"

local function read_holds(tr)
  local ok, s = reaper.GetSetMediaTrackInfo_String(tr, HOLD_KEY, "", false)
  local t = {}
  for e in ((ok and s) or ""):gmatch("[^;]+") do
    local key, n0, gs, ps = e:match("^([^|]+)|(%d+)|([^|]*)|?(.*)$")
    if key then
      local held, pins = {}, {}
      for g in gs:gmatch("[^,]+") do held[g] = true end
      for g, p, lo, hi in ps:gmatch("([^:+]+):(%d+):(%d+):(%d+)") do
        pins[g] = pins[g] or {}
        pins[g][tonumber(p)] = { tonumber(lo), tonumber(hi) }
      end
      t[key] = { n0 = tonumber(n0), held = held, pins = pins }
    end
  end
  return t
end

local function write_holds(tr, t)
  local parts = {}
  for key, h in pairs(t) do
    local gs = {}
    for g in pairs(h.held) do gs[#gs + 1] = g end
    table.sort(gs)
    local ps = {}
    for g, pins in pairs(h.pins or {}) do
      for p, m in pairs(pins) do ps[#ps + 1] = ("%s:%d:%d:%d"):format(g, p, m[1], m[2]) end
    end
    table.sort(ps)
    parts[#parts + 1] = key .. "|" .. math.floor(h.n0) .. "|" .. table.concat(gs, ",")
                        .. (#ps > 0 and ("|" .. table.concat(ps, "+")) or "")
  end
  table.sort(parts)
  reaper.GetSetMediaTrackInfo_String(tr, HOLD_KEY, table.concat(parts, ";"), true)
end

-- Whether a plugin takes its level's channel count (channel_config 0).
local function follows_count(tr, a)
  local ok, v = reaper.TrackFX_GetNamedConfigParm(tr, a, "channel_config")
  return ok and tonumber((v or ""):match("^%s*(%-?%d+)")) == 0
end

local function own_plugin(tr, a)
  if is_probe(tr, a) then return true end
  local n = fx_name(tr, a)
  return n:find("ChannelView Modulators", 1, true) ~= nil or n:find("TS_CV_Modulators", 1, true) ~= nil
end

-- Holds each plugin among `items` that follows the count at h.n0, noting
-- it in h.held. True when it held any.
local function hold_items(tr, items, h)
  local any = false
  for _, a in ipairs(items) do
    if not own_plugin(tr, a) and follows_count(tr, a) then
      reaper.TrackFX_SetNamedConfigParm(tr, a, "channel_config", tostring(h.n0))
      h.held[fx_guid(tr, a)] = true
      any = true
    end
  end
  return any
end

-- Inputs past a level's own channels read nothing there; once the level
-- is widened they read the new channels -- silence, or a copy. A plugin
-- with a sidechain then keys from it and stops working (Waves SSLComp
-- and API-2500 do). So, at a widened level, a plugin's inputs past its
-- first two lose the channels past h.n0, noted in h.pins to be put back
-- (h.pins[guid][pin] = { lo, hi } taken off). `dry`: only whether any
-- would. True when any did.
local function unplug_past(tr, items, h, dry)
  local ml, mh = 0, 0
  for ch = h.n0 + 1, TP.MAX_CH do
    local bl, bh = TP.bit(ch)
    ml, mh = ml | bl, mh | bh
  end
  local any = false
  for _, a in ipairs(items) do
    if not own_plugin(tr, a) and not container_count(tr, a) then
      local nin = io_size(tr, a)
      for p = 2, nin - 1 do
        local lo, hi = get_pin(tr, a, false, p)
        local rl, rh = lo & ml, hi & mh
        if rl ~= 0 or rh ~= 0 then
          any = true
          if dry then return true end
          set_pin(tr, a, false, p, lo & ~rl, hi & ~rh)
          local g = fx_guid(tr, a)
          h.pins = h.pins or {}
          h.pins[g] = h.pins[g] or {}
          local was = h.pins[g][p] or { 0, 0 }
          h.pins[g][p] = { was[1] | rl, was[2] | rh }
        end
      end
    end
  end
  return any
end

-- A level's channel count (the track's, `caddr` nil, or a container's).
local function level_nch(tr, caddr)
  if caddr then return nconf(tr, caddr, "container_nch", 2) end
  return math.floor(reaper.GetMediaTrackInfo_Value(tr, "I_NCHAN"))
end

-- Gives a level at least `want` channels, its plugins held first.
local function widen(tr, caddr, want)
  local n = level_nch(tr, caddr)
  if n >= want then return end
  local t = read_holds(tr)
  local key = caddr and fx_guid(tr, caddr) or "TOP"
  local h = t[key] or { n0 = n, held = {}, pins = {} }
  t[key] = h
  local items = level_items(tr, caddr)
  hold_items(tr, items, h)
  -- before (a plugin takes a sidechain for connected once its channels
  -- exist, Waves's do) and after (one that can't be held takes the new
  -- channels as it grows)
  unplug_past(tr, items, h)
  if caddr then reaper.TrackFX_SetNamedConfigParm(tr, caddr, "container_nch", tostring(want))
  else reaper.SetMediaTrackInfo_Value(tr, "I_NCHAN", want) end
  unplug_past(tr, items, h)
  write_holds(tr, t)
end

-- A plugin added since a level was widened, that follows the count, held
-- too, and inputs past the level's channels unplugged (one undo step,
-- only when there's one). True when it changed any.
local function keep_held(tr)
  local t = read_holds(tr)
  if not next(t) then return false end
  local map
  local todo, unplug = {}, {}
  for key, h in pairs(t) do
    local caddr
    if key ~= "TOP" then
      map = map or guid_map(tr)
      caddr = map[key]
    end
    if key == "TOP" or caddr then
      local items = level_items(tr, caddr)
      for _, a in ipairs(items) do
        if not own_plugin(tr, a) and follows_count(tr, a) then todo[#todo + 1] = { a, h } end
      end
      unplug[#unplug + 1] = { items, h }
    end
  end
  local any_unplug = false
  for _, u in ipairs(unplug) do
    if unplug_past(tr, u[1], u[2], true) then any_unplug = true; break end
  end
  if #todo == 0 and not any_unplug then return false end
  reaper.Undo_BeginBlock()
  for _, e in ipairs(todo) do hold_items(tr, { e[1] }, e[2]) end
  for _, u in ipairs(unplug) do unplug_past(tr, u[1], u[2]) end
  write_holds(tr, t)
  reaper.Undo_EndBlock("ChannelView: keep plugins at the track's channels", -1)
  return true
end

-- Taking the probes out: each level back to the channels it had, and the
-- plugins held there following it again. A level something else now
-- reads or writes above that count (a receive, a plugin's pins, a send)
-- keeps its channels and its plugins stay held.
local function release_holds(tr)
  local t = read_holds(tr)
  if not next(t) then return end
  local map = guid_map(tr)
  for key, h in pairs(t) do
    local caddr = (key ~= "TOP") and map[key] or nil
    if key == "TOP" or caddr then
      local items, used = {}, {}
      for _, a in ipairs(level_items(tr, caddr)) do
        if not own_plugin(tr, a) and not h.held[fx_guid(tr, a)] then items[#items + 1] = a end
      end
      items_used(tr, items, used)
      if not caddr then routing_channels(tr, used) end
      local top = 0
      for ch in pairs(used) do top = math.max(top, ch) end
      if top <= h.n0 then
        if level_nch(tr, caddr) > h.n0 then
          if caddr then reaper.TrackFX_SetNamedConfigParm(tr, caddr, "container_nch", tostring(h.n0))
          else reaper.SetMediaTrackInfo_Value(tr, "I_NCHAN", h.n0) end
        end
        for _, a in ipairs(level_items(tr, caddr)) do
          if h.held[fx_guid(tr, a)] then reaper.TrackFX_SetNamedConfigParm(tr, a, "channel_config", "0") end
        end
        -- the inputs unplugged while it was wide, back as they were
        for g, pins in pairs(h.pins or {}) do
          local a = map[g]
          if a then
            local nin = io_size(tr, a)
            for p, m in pairs(pins) do
              if p < nin then
                local lo, hi = get_pin(tr, a, false, p)
                set_pin(tr, a, false, p, lo | m[1], hi | m[2])
              end
            end
          end
        end
        t[key] = nil
      end
    end
  end
  write_holds(tr, t)
end

-- ---------------------------------------------------------------------
-- REAPER side: keeping the copies' channels clear
-- ---------------------------------------------------------------------

-- A plugin added to a chain whose track already carries copies can come
-- in writing over them, two ways:
--   * it takes the track's channel count (many VST3s do, and the copies
--     raise it to 8 or more), and REAPER maps each extra output to its
--     own channel. Nobody chose that: those pins are cleared (a channel
--     no output pin writes passes through untouched).
--   * someone routed it there on purpose. That's left alone: the taps
--     move to other free channels instead (TP.sync lays them again).

-- Which output pin of each address may write which channel: L and R
-- (pins 0 and 1, or 0 for both on a one-output plugin) to its "before"
-- pairs as a writer and to its "after" pair as the measured plugin; pin
-- ch - 1 to each channel of both pairs for a container the copies pass
-- out through. allow[addr][ch] = pin.
local function tap_writers(tr, taps)
  local allow = {}
  local function set(a, ch, pin)
    allow[a] = allow[a] or {}
    allow[a][ch] = pin
  end
  local function pair(a, ch)
    local _, nout = io_size(tr, a)
    set(a, ch, 0)
    set(a, ch + 1, nout >= 2 and 1 or 0)
  end
  for _, t in ipairs(taps) do
    for _, w in ipairs(t.writers or {}) do pair(w, t.pre) end
    pair(t.addr, t.post)
    for _, c in ipairs(t.path or {}) do
      for _, ch in ipairs({ t.pre, t.pre + 1, t.post, t.post + 1 }) do set(c, ch, ch - 1) end
    end
  end
  return allow
end

-- Every output pin between the probes (and inside the containers the
-- copies pass through) that writes a copy's channel without being meant
-- to: { addr, pin, ch }. `taps` need pre, post, addr, writers and path.
-- A pin is REAPER's own mapping when it writes only its own channel (pin
-- p to channel p + 1) on a plugin with as many outputs as its level has
-- channels: `auto` in what clobbers returns.
local function clobbers(tr, lv, taps)
  local chans, on_path = {}, {}
  for _, t in ipairs(taps) do
    for _, ch in ipairs({ t.pre, t.pre + 1, t.post, t.post + 1 }) do chans[ch] = true end
    for _, c in ipairs(t.path or {}) do on_path[c] = true end
  end
  local allow = tap_writers(tr, taps)
  local out = {}
  local function look(a, nch)
    local nout
    if (container_count(tr, a) or 0) > 0 then nout = nconf(tr, a, "container_nch_out", 2)
    else local _, o = io_size(tr, a); nout = o end
    for p = 0, nout - 1 do
      local lo, hi = get_pin(tr, a, true, p)
      for ch in pairs(TP.channels_of(lo, hi)) do
        if chans[ch] and not (allow[a] and allow[a][ch] == p) then
          local bl, bh = TP.bit(ch)
          local auto = ch == p + 1 and lo == bl and hi == bh and nout >= nch
          out[#out + 1] = { addr = a, pin = p, ch = ch, auto = auto }
        end
      end
    end
  end
  local function walk(items, from, to, depth, nch)
    for i = from, to do
      local a = items[i]
      if not is_probe(tr, a) then
        look(a, nch)
        if on_path[a] and depth < TP.MAX_DEPTH then
          local kids = level_items(tr, a)
          walk(kids, 1, #kids, depth + 1, nconf(tr, a, "container_nch", 2))
        end
      end
    end
  end
  local nch = lv.caddr and nconf(tr, lv.caddr, "container_nch", 2)
              or reaper.GetMediaTrackInfo_Value(tr, "I_NCHAN")
  walk(lv.items, lv.pre + 1, lv.post - 1, 0, nch)
  return out
end
TP._clobbers = clobbers

-- Clears what clobbers found that REAPER mapped by itself. Returns how
-- many pins it changed, and how many it left (routed on purpose).
local function clear_clobbers(tr, lv, taps)
  local found = clobbers(tr, lv, taps)
  local cleared = 0
  for _, c in ipairs(found) do
    if c.auto then pin_channel(tr, c.addr, true, c.pin, c.ch, false); cleared = cleared + 1 end
  end
  return cleared, #found - cleared
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
    PL.set(tr, probe, "tap_n", 1, 0)
    if TP.probe_has_levels(tr, probe) then PL.set(tr, probe, "nogr", 1, 0) end
  end
  if lv then PL.set(tr, lv.items[lv.pre], "arm", 1, 0) end
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
  -- Room for them: the track's channel count, or the container's (its
  -- plugins held at the count they had).
  widen(tr, lv.caddr, top + (top % 2))
  -- And in every container on the way: channels, and pins to carry them.
  for _, c in ipairs(order) do
    local need_in, need_out = 0, 0
    for _, t in ipairs(conts[c]) do
      need_in = math.max(need_in, t.pre + 1)
      need_out = math.max(need_out, t.pre + 1, t.post + 1)
    end
    widen(tr, c, top + (top % 2))
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
    PL.set(tr, probe, "lag", i, t.lag or 0)
  end
  -- the taps not in use: unplugged
  for p = 2 + #want.taps * 4, 2 + TP.MAX_TAPS * 4 - 1 do set_pin(tr, probe, false, p, 0, 0) end
  PL.name(tr, lv.items[lv.pre], probe)
  PL.set(tr, probe, "tap_n", 1, #want.taps)
  if TP.probe_has_levels(tr, probe) then
    PL.set(tr, probe, "nogr", 1, TP.nogr_mask(want.taps))
  end
  -- New routing: whatever zeros the probe measured belonged to the old one.
  PL.set(tr, probe, "gen", 1, (math.floor(PL.get(tr, probe, "gen") or 0) + 1) % 1000000)
  PL.set(tr, lv.items[lv.pre], "arm", 1, TP.zero_wanted(tr) and 1 or 0)
  -- The channels were free when chosen; a plugin that follows the track's
  -- channel count has taken them since the count went up.
  clear_clobbers(tr, lv, want.taps)
  write_record(tr, want)
  return true
end

-- Brings one track into line with what's wanted. Returns true when it
-- changed anything.
function TP.sync(tr)
  -- a plugin added to a widened level comes in held, like the others
  local held_new = keep_held(tr)
  local rec = read_record(tr)
  local want, lv = TP.desired(tr)
  -- something routed onto the copies' channels on purpose: laid again,
  -- on channels it doesn't use
  local move = false
  if want and TP.same_shape(rec, want) then
    local now_taps = {}
    for i, t in ipairs(want.taps) do
      now_taps[i] = { pre = rec.taps[i].pre, post = rec.taps[i].post,
                      addr = t.addr, writers = t.writers, path = t.path }
    end
    for _, c in ipairs(clobbers(tr, lv, now_taps)) do
      if not c.auto then move = true; break end
    end
    -- or a send or receive put on them since: the receive would mix into
    -- the copies, the send carry them
    if not move then
      local routed = routing_channels(tr, {})
      for _, t in ipairs(now_taps) do
        if routed[t.pre] or routed[t.pre + 1] or routed[t.post] or routed[t.post + 1] then move = true; break end
      end
    end
  end
  if not move and TP.same_shape(rec, want) then
    if not want then return held_new end
    -- Same plugins, same places: only the latency can have moved -- or a
    -- plugin added since writes over the copies.
    local probe = lv.items[lv.post]
    local pre = lv.items[lv.pre]
    local changed = false
    do
      local now_taps = {}
      for i, t in ipairs(want.taps) do
        now_taps[i] = { pre = rec.taps[i].pre, post = rec.taps[i].post,
                        addr = t.addr, writers = t.writers, path = t.path }
      end
      local found = clobbers(tr, lv, now_taps)
      if #found > 0 then
        reaper.Undo_BeginBlock()
        clear_clobbers(tr, lv, now_taps)
        reaper.Undo_EndBlock("ChannelView: keep the measurement taps' channels clear", -1)
        changed = true
      end
    end
    -- The pair named in its track's block (a new probe): every check, as
    -- gmem starts empty with REAPER, and a track can move.
    PL.name(tr, pre, probe)
    for i, t in ipairs(want.taps) do
      local cur = PL.get(tr, probe, "lag", i)
      if math.floor(cur + 0.5) ~= t.lag then
        PL.set(tr, probe, "lag", i, t.lag)
        rec.taps[i].lag = t.lag
        changed = true
      end
    end
    if math.floor(PL.get(tr, probe, "tap_n") + 0.5) ~= #want.taps then
      PL.set(tr, probe, "tap_n", 1, #want.taps)
      changed = true
    end
    if TP.probe_has_levels(tr, probe) then PL.set(tr, probe, "nogr", 1, TP.nogr_mask(want.taps)) end
    -- The pre probe armed for the zero, or not (the setting; a track armed
    -- to record) -- also arms routing that was laid without it.
    PL.set(tr, pre, "arm", 1, TP.zero_wanted(tr) and 1 or 0)
    if changed then write_record(tr, rec) end
    return held_new
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

-- A new probe's tap pins come unplugged: REAPER connects inputs 3..18 to
-- channels 3..18, which reads (in the pin connector) as if the probe used
-- 3/4, a sidechain's usual pair. They're only read, and only once a tap
-- is laid (lay points them at the copies' channels).
local function add_probe(tr, pos)
  for _, nm in ipairs(TP.PROBE_PATHS) do
    local idx = reaper.TrackFX_AddByName(tr, nm, false, pos)
    if idx and idx >= 0 then
      for p = 2, 2 + TP.MAX_TAPS * 4 - 1 do set_pin(tr, idx, false, p, 0, 0) end
      return idx
    end
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
local function add_pair(tr)
  local first = TP.ara_first(tr) and 1 or 0
  -- one already there (the other deleted): only the missing one is added
  local have_pre, have_post = TP.top_probes(tr)
  reaper.PreventUIRefresh(1)
  local pre = have_pre or add_probe(tr, -1000 - first)    -- -1000 - n: insert at slot n
  -- a pre probe put in front of the lone post probe moves it along one
  if have_post and not have_pre and pre and pre <= have_post then have_post = have_post + 1 end
  local post = pre and (have_post or add_probe(tr, -1))   -- -1: append
  order_cache = {}
  if pre and post then PL.name(tr, pre, post) end   -- an old probe: its role slider
  reaper.PreventUIRefresh(-1)
  TP.invalidate()
  return pre, post
end

function TP.insert_probes(tr)
  if find_level(tr, nil) then return true end
  reaper.Undo_BeginBlock()
  local pre, post = add_pair(tr)
  reaper.Undo_EndBlock("ChannelView: add TS_TrackProbe pair", -1)
  if not (pre and post) then
    return false, "REAPER couldn't load TS_TrackProbe.jsfx -- is it installed under Effects?"
  end
  return true
end

-- ---------------------------------------------------------------------
-- hidden, and kept at the ends
-- ---------------------------------------------------------------------
-- The probes have nothing to show, so the plugin row always leaves them
-- out -- and since you can't see them, ChannelView keeps them where they
-- belong: the pre probe first (second behind an ARA plugin), the post
-- probe last, after any insert, move or removal. One of the pair dragged
-- into a container comes back out to its end; a pair kept together
-- inside a container is left alone (that's deliberate).
--
-- The moves make NO undo point of their own. If they did, undoing your
-- insert would first undo the move, which would put the probe straight
-- back -- and you could never get past it. Without one, undo takes the
-- chain back to before your insert, probes and all.

-- Always hidden; a function so its callers read the same.
function TP.probes_shown() return false end

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

-- A track left with one probe of its pair (the other deleted) gets the
-- other back, as the probes are kept in place. Not the master, and not a
-- pair inside a container. No undo point, for the same reason as the
-- moves. True if one was added.
function TP.complete_pair(tr)
  if not tr or tr == reaper.GetMasterTrack(0) or find_level(tr, nil) then return false end
  local pre, post = TP.top_probes(tr)
  if (pre ~= nil) == (post ~= nil) then return false end
  local a, b = add_pair(tr)
  return a ~= nil and b ~= nil
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

-- Which of the pair TS_Visualizer shows, "pre", "post" or nil: the pre
-- probe the track's input, the post its output. Kept on the track
-- (TS_CV_ProbeLink's vis_choice); a legacy probe keeps it in its own
-- "Include in Visualizer Spectrum" checkbox, which also counts.
TP.P_VIS = 3
function TP.vis_state(tr)
  local lv = tr and find_level(tr, nil)
  if not lv then return nil end
  local pre, post = lv.items[lv.pre], lv.items[lv.post]
  if PL.is_legacy(tr, pre) then
    local function on(a) return (reaper.TrackFX_GetParam(tr, a, TP.P_VIS) or 0) >= 0.5 end
    if on(pre) then return "pre" end
    if on(post) then return "post" end
    return nil
  end
  return PL.vis_choice(tr)
end
function TP.set_vis(tr, which)
  local lv = tr and find_level(tr, nil)
  if not lv then return end
  local pre, post = lv.items[lv.pre], lv.items[lv.post]
  reaper.Undo_BeginBlock()
  PL.set_vis_choice(tr, which)
  if PL.is_legacy(tr, pre) then
    reaper.TrackFX_SetParam(tr, pre, TP.P_VIS, which == "pre" and 1 or 0)
    reaper.TrackFX_SetParam(tr, post, TP.P_VIS, which == "post" and 1 or 0)
  end
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
  release_holds(tr)
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
  PL.forget(tr)
  reaper.Undo_EndBlock("ChannelView: remove TS_TrackProbe pair", -1)
  TP.invalidate()
end

-- Before the track is saved as a template: the taps lifted and the
-- plugins held for them let go, so the template is the track as it was
-- before ChannelView laid them. TP.sync lays them again afterwards. The
-- probes themselves stay (Track Analyser's too).
-- Whether ChannelView has laid taps on the track, or holds plugins at a
-- channel count for them.
function TP.has_taps(tr)
  if not tr then return false end
  local r = read_record(tr)
  return (r ~= nil and #(r.taps or {}) > 0) or next(read_holds(tr)) ~= nil
end

function TP.for_template(tr)
  if not tr then return end
  lift(tr, read_record(tr))
  release_holds(tr)
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
-- The tracks something read this moment (on screen): only theirs are
-- measured (TS_TrackProbe's ONLY THE TRACKS ON SCREEN). { [key] = { tr, t } }
local watched = {}

local function reader_for(tr)
  local key = tostring(tr)
  local rd = readers[key]
  local now = reaper.time_precise()
  local w = watched[key]
  if w then w.t = now else watched[key] = { tr = tr, t = now } end
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
  local function g(f) return PL.get(tr, rd.probe, f, i) or -150 end
  return { in_pk = g("inpk"), out_pk = g("outpk"),
           in_rms = g("inrms"), out_rms = g("outrms") }
end

-- STEREO, ONE TAP (TS_TrackProbe 2.4.0+): a plugin's output in stereo,
-- for the Width visualiser. One stereo tap per probe, and one scope in all
-- (gmem[TP.ST_CTRL] names the track that writes it): the last open panel
-- to ask has them.
TP.ST_CTRL, TP.ST_HDR, TP.ST_PTS = 77, 0x340000, 0x340010
-- Asks for it. Returns true; "old" when the project's probe predates it
-- (a project keeps the probe it opened with); false when it isn't tapped.
function TP.set_stereo(tr, guid)
  local i, rd = tap_for(tr, guid, "")
  if not i or not rd.probe then return false end
  if PL.is_legacy(tr, rd.probe) or PL.get(tr, rd.probe, "st_cap") < 0.5 then return "old" end
  PL.set(tr, rd.probe, "st", 1, i)
  local ti = PL.track_index(tr)
  if ti and reaper.gmem_read(TP.ST_CTRL) ~= ti + 2 then reaper.gmem_write(TP.ST_CTRL, ti + 2) end
  return true
end
-- What it measures: { corr (-1..1), mid, side (dBFS, RMS over 300 ms),
-- pts (the scope: L, R, L, R ..., oldest first, or nil when another
-- track has it) }, or nil when it isn't this plugin's.
local st_pts = {}
function TP.stereo(tr, guid)
  local i, rd = tap_for(tr, guid, "")
  if not i or not rd.probe then return nil end
  if math.floor(PL.get(tr, rd.probe, "st") + 0.5) ~= i then return nil end
  local out = { corr = PL.get(tr, rd.probe, "corr"), mid = PL.get(tr, rd.probe, "st_mid"),
                side = PL.get(tr, rd.probe, "st_side") }
  local ti = PL.track_index(tr)
  if ti and reaper.gmem_read(TP.ST_HDR + 2) == ti + 2 then
    local seq = reaper.gmem_read(TP.ST_HDR)
    local c = st_pts[guid]
    if not c or c.seq ~= seq then
      local n = math.max(0, math.min(512, math.floor(reaper.gmem_read(TP.ST_HDR + 1) + 0.5)))
      c = { seq = seq, pts = {} }
      for k = 0, n * 2 - 1 do c.pts[k + 1] = reaper.gmem_read(TP.ST_PTS + k) end
      st_pts[guid] = c
    end
    out.pts = c.pts
  end
  return out
end

-- LEVELS PER CHANNEL (TS_TrackProbe 2.4.0+): this plugin's levels, left
-- and right apart: { in_pk = { l, r }, out_pk, in_rms, out_rms } (dBFS);
-- { old = true } from an older probe; nil when it isn't measured (or past
-- the probe's 3000 tracks).
TP.LR_BASE, TP.LR_STRIDE, TP.LR_TRACKS = 0x350000, 64, 3000
function TP.levels_lr(tr, guid)
  local i, rd = tap_for(tr, guid, "l")
  if not i or not rd.probe then return nil end
  if PL.is_legacy(tr, rd.probe) or PL.get(tr, rd.probe, "st_cap") < 0.5 then return { old = true } end
  local ti = PL.track_index(tr)
  if not ti or ti + 1 >= TP.LR_TRACKS then return nil end
  local b = TP.LR_BASE + (ti + 1) * TP.LR_STRIDE + (i - 1) * 8
  local function g(k) return reaper.gmem_read(b + k) or -150 end
  return { in_pk = { g(0), g(1) }, out_pk = { g(2), g(3) }, in_rms = { g(4), g(5) }, out_rms = { g(6), g(7) } }
end

-- The measured reduction, positive dB, or nil when this plugin isn't
-- tapped. 0 while the probe isn't running.
function TP.reading(tr, guid)
  local i, rd = tap_for(tr, guid, "g")
  if not i or not rd.probe then return nil end
  return math.max(0, PL.get(tr, rd.probe, "gr", i) or 0)
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
    if not PL.is_legacy(tr, probe) then v = true
    else
      local ok, nm = reaper.TrackFX_GetParamName(tr, probe, TP.P_MB, "")
      v = (ok and nm and nm:lower():find("multiband", 1, true)) ~= nil
    end
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
  local function put(f, k, v)
    if math.abs((PL.get(tr, rd.probe, f, k) or 0) - v) > 0.5 then PL.set(tr, rd.probe, f, k, v) end
  end
  put("mb", 1, i)
  for k = 1, 3 do put("mbx", k, xos[k] and math.floor(xos[k] + 0.5) or 0) end
  return true
end

local fine_owner = {}
-- Whether a probe can measure in third-octaves (TS_TrackProbe 1.7.0+, or
-- one without parameters).
function TP.probe_has_fine(tr, probe)
  if not PL.is_legacy(tr, probe) then return true end
  local ok, nm = reaper.TrackFX_GetParamName(tr, probe, TP.P_FINE, "")
  return (ok and nm and nm:lower():find("third", 1, true)) ~= nil
end
-- Whether this plugin can be measured in third-octaves: true; "old" when
-- it's tapped but the project still runs a probe older than 1.7.0 (a
-- project keeps the JSFX it opened with); false when it isn't tapped.
function TP.fine_ok(tr, guid)
  local i, rd = tap_for(tr, guid, "g")
  if not i or not rd.probe then return false end
  return TP.probe_has_fine(tr, rd.probe) and true or "old"
end
-- Asks the probe to measure this plugin in third-octaves. One tap per
-- probe: an instance asking keeps it while it goes on asking (half a
-- second), so two open panels don't take it in turns. Returns whether it
-- has it.
function TP.set_fine(tr, guid, polite)
  local i, rd = tap_for(tr, guid, "g")
  if not i or not rd.probe then return false end
  if not TP.probe_has_fine(tr, rd.probe) then return false end
  local now = reaper.time_precise()
  local key = tostring(tr)
  local o = fine_owner[key]
  if o and o.guid ~= guid and now - o.t < 0.5 then return false end
  -- polite (the web bridge): only when no other tap has it, so it never
  -- takes the measurement from a window's panel
  local cur = math.floor((PL.get(tr, rd.probe, "fine") or 0) + 0.5)
  if polite and cur ~= 0 and cur ~= i then return false end
  fine_owner[key] = { guid = guid, t = now, tr = tr, probe = rd.probe, i = i,
                      pguid = reaper.TrackFX_GetFXGUID(tr, rd.probe) }
  if cur ~= i then PL.set(tr, rd.probe, "fine", 1, i) end
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
         and math.floor((PL.get(o.tr, o.probe, "fine") or 0) + 0.5) == o.i then
        PL.set(o.tr, o.probe, "fine", 1, 0)
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
  if math.floor((PL.get(tr, rd.probe, "mb") or 0) + 0.5) ~= i then return nil end
  return math.max(0, PL.get(tr, rd.probe, "mbgr", k) or 0)
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
      -- the probe splits in four: past four bands, the first three are
      -- measured and the rest (one split together) aren't
      plan.at[k] = (nb <= 4 or k <= 3) and k or nil
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
    if not PL.is_legacy(tr, probe) then v = true
    else
      local ok, nm = reaper.TrackFX_GetParamName(tr, probe, TP.P_MBL, "")
      v = (ok and nm and nm:lower():find("input level", 1, true)) ~= nil
    end
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
  if math.floor((PL.get(tr, rd.probe, "mb") or 0) + 0.5) ~= i then return nil end
  local v = PL.get(tr, rd.probe, "mbl", j)
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
  return math.floor((PL.get(tr, rd.probe, "cal", i) or 0) + 0.5)
end

-- One line on it, for tooltips.
function TP.cal_text(st)
  if not TP.zero_on() then
    return "Zero learnt from the music (measuring it off in Setup)\n" ..
           "A compressor that never lets go reads low."
  end
  if st == 1 then return "Zero measured."
  elseif st == 2 then
    return "Zero measured; the plugin was already working\n" ..
           "on the test signal, so may read a little low."
  elseif st == 3 then
    return "Plugin touched since: its zero is measured\n" ..
           "again once stopped and quiet."
  elseif st == 4 then
    return "Shut on the test signal: zero learnt from the music."
  elseif st == 5 then
    return "A gate: zero learnt from the music,\n" ..
           "its closed reading held through silence."
  end
  return "Zero not measured yet: it is once stopped and quiet\n" ..
         "(needs \"Run FX when stopped\"). Until then it may read low."
end

-- Whether the zero is measured while stopped. On unless turned off.
function TP.zero_on()
  return reaper.GetExtState("TS_ChannelView", TP.ZERO_KEY) ~= "0"
end

-- Whether a track's pre probe is armed for the zero: as the setting says,
-- and never on a track armed to record (its test noise would be in the take).
function TP.zero_wanted(tr)
  return TP.zero_on() and (reaper.GetMediaTrackInfo_Value(tr, "I_RECARM") or 0) ~= 1
end

-- What a plugin that reports its own reduction shows: the measured
-- reading ("measured", the default) or its own figure ("own").
function TP.measured_first()
  return reaper.GetExtState("TS_ChannelView", TP.READING_KEY) ~= "own"
end

function TP.set_measured_first(on)
  reaper.SetExtState("TS_ChannelView", TP.READING_KEY, on and "measured" or "own", true)
  TP.invalidate()
end

-- A gate or expander reports reduction while stopped and silent: it's
-- shut on the silence, and so on the test noise too -- the zero measured
-- then is its shut level, and the measured reading would sit at 0. Such a
-- plugin shows its own figure. Found once it reports TP.SHUT_DB or more
-- for TP.SHUT_FOR seconds while stopped, its input under TP.QUIET_DB.
-- { [guid] = true }, or a time while it's being watched for.
TP.SHUT_DB, TP.SHUT_FOR, TP.QUIET_DB = 3, 1.5, -70
local shut = {}

-- The measured reading to show for a plugin that reports its own, or nil
-- for its own figure: measured first, tapped, its zero measured (not
-- touched since -- a make-up change would read as reduction), and not a
-- gate shut on the silence. `own`: its own figure now, positive dB.
function TP.measured_for_reporting(tr, guid, own)
  if not tr or not TP.measured_first() then return nil end
  local i, rd = tap_for(tr, guid, "g")
  if not i or not rd.probe then return nil end
  -- (shut on the silence is while stopped: playing, it's looked at afresh)
  local stopped = (reaper.GetPlayState() & 1) == 0
  if shut[guid] == true and not stopped then shut[guid] = nil end
  if shut[guid] == true then return nil end
  if own then
    local quiet = (PL.get(tr, rd.probe, "inpk", i) or -150) < TP.QUIET_DB
    if stopped and quiet and own >= TP.SHUT_DB then
      local now = reaper.time_precise()
      shut[guid] = shut[guid] or now
      if now - shut[guid] >= TP.SHUT_FOR then shut[guid] = true; return nil end
    else
      shut[guid] = nil
    end
  end
  local cs = TP.cal_status(tr, guid)
  if cs ~= 1 and cs ~= 2 then return nil end
  return TP.reading(tr, guid)
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
        src.list[#src.list + 1] = { addr = fx.addr, guid = fx.guid, name = U.fx_label(fx) }
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
    -- (measured or reported: a reporting plugin's changes with its zero)
    local e = T.gr_estimated(tr, s.addr, s.guid)
    if e then est = true end
    parts[#parts + 1] = { name = s.name, db = v, est = e,
                          cal = e and TP.cal_status(tr, s.guid) or nil }
  end
  return total, est, parts
end

-- ---------------------------------------------------------------------
-- a track's spectrum
-- ---------------------------------------------------------------------

-- The spectrum behind an EQ canvas: this track's post probe writes it for
-- as long as something asks (TS_TrackProbe 2.6.0, A SPECTRUM PER TRACK),
-- each track at its own place, so channel view, the rack and pop-outs
-- can each show their own. With an older probe, Track Analyser's
-- spectrum, but only while it shows this very track.
-- Returns { db = { ... }, n, lo, hi } (dB per band, lowest and highest
-- frequency), or nil while there's nothing live. Asked for each frame
-- it's drawn; the answer is kept for the frame.
TP.SPEC_BASE, TP.SPEC_STRIDE, TP.SPEC_TRACKS = 0x3A0000, 272, 4096
TP.TA_POST = 0x20000
local spec_seen, spec_frame, spec_probe, spec_tick = {}, {}, {}, 0

-- Keeps a track's post probe running its spectrum (field 127 moving),
-- without reading it: TP.spectrum below, and Collisions (TS_CV_Collisions,
-- which reads the probe's ERB bands instead). Returns the track's index
-- and its post probe, or nil when it has none.
function TP.want_spectrum(tr)
  if not tr then return nil end
  local now = reaper.time_precise()
  local key = tostring(tr)
  local idx = PL.track_index(tr)
  -- where its post probe is: looked for twice a second, not every frame
  local pc = spec_probe[key]
  if not pc or now - pc.t > 0.5 then
    local lv = find_level(tr, nil)
    pc = { t = now, fx = lv and lv.items[lv.post] }
    spec_probe[key] = pc
  end
  local probe = pc.fx
  if not (idx and probe and idx + 1 < TP.SPEC_TRACKS) then return nil end
  if not TP._spec_gm then reaper.gmem_attach(TP.GMEM_NS); TP._spec_gm = true end
  spec_tick = (spec_tick + 1) % 1000000
  PL.set(tr, probe, "cv_spec", 1, spec_tick + 1)
  return idx, probe
end
function TP.spectrum(tr)
  if not tr then return nil end
  local now = reaper.time_precise()
  local key = tostring(tr)
  local f = spec_frame[key]
  if f and now - f.t < 0.012 then return f.s end
  if not TP._spec_gm then reaper.gmem_attach(TP.GMEM_NS); TP._spec_gm = true end
  local idx, probe = TP.want_spectrum(tr)
  local out
  if probe then
    local b = TP.SPEC_BASE + (idx + 1) * TP.SPEC_STRIDE
    local seq = reaper.gmem_read(b)
    local s = spec_seen[key]
    if not s or s.seq ~= seq then s = { seq = seq, t = now }; spec_seen[key] = s end
    local n = math.floor(reaper.gmem_read(b + 1))
    if seq > 0 and now - s.t < 1.0 and n >= 2 and reaper.gmem_read(b + 5) == idx + 2 then
      s.own = now   -- (a probe that writes its own: it can listen too)
      out = { n = n, lo = reaper.gmem_read(b + 2), hi = reaper.gmem_read(b + 3), db = {} }
      for i = 1, n do out.db[i] = reaper.gmem_read(b + 15 + i) end
    elseif not PL.is_legacy(tr, probe) and (PL.get(tr, probe, "pub_post") or 0) >= 0.5 then
      -- an older probe: Track Analyser's, while it shows this track
      local P = TP.TA_POST
      local tseq = reaper.gmem_read(P)
      local t = spec_seen.ta
      if not t or t.seq ~= tseq then t = { seq = tseq, t = now }; spec_seen.ta = t end
      n = math.floor(reaper.gmem_read(P + 16))
      if reaper.gmem_read(P + 11) == 1 and now - t.t < 1.0 and n >= 2 then
        out = { n = n, lo = reaper.gmem_read(P + 17), hi = reaper.gmem_read(P + 18), db = {} }
        for i = 1, n do out.db[i] = reaper.gmem_read(P + 16384 + (i - 1) * 4) end
      end
    end
  end
  spec_frame[key] = { t = now, s = out }
  return out
end

-- Listening to a band (TS_TrackProbe 2.6.0, LISTENING TO A BAND): the
-- track's output about `hz` alone (kind 0, of Q `q`), below it (1) or
-- above it (2), for as long as this is called each frame; TP.listen(tr)
-- lets go at once. False when the track's probe can't (none, or older).
local lsn_tick = 0
function TP.can_listen(tr)
  if not tr then return false end
  local s = spec_seen[tostring(tr)]
  return s ~= nil and s.own ~= nil and reaper.time_precise() - s.own < 1.0
end
function TP.listen(tr, hz, q, kind)
  local idx = tr and PL.track_index(tr)
  if not idx or idx + 1 >= TP.SPEC_TRACKS then return false end
  if not TP._spec_gm then reaper.gmem_attach(TP.GMEM_NS); TP._spec_gm = true end
  local b = TP.SPEC_BASE + (idx + 1) * TP.SPEC_STRIDE
  if not hz then reaper.gmem_write(b + 6, 0); return true end
  if not TP.can_listen(tr) then return false end
  reaper.gmem_write(b + 6, hz)
  reaper.gmem_write(b + 7, q or 1)
  reaper.gmem_write(b + 9, kind or 0)
  lsn_tick = lsn_tick % 1000000 + 1
  reaper.gmem_write(b + 8, lsn_tick)
  return true
end

-- A band held to listen to from elsewhere (the web page): `band()` gives
-- hz, q, kind each time it's asked; `sw(on)`, when given, is the band's
-- own Solo instead. Kept while TP.listen_hold keeps coming with its key,
-- let go a third of a second after it stops (TP.listen_tick, each cycle)
-- or at once by TP.listen_release.
local web_held = nil
local function held_stop()
  if not web_held then return end
  if web_held.sw then web_held.sw(false) else TP.listen(web_held.tr) end
  web_held = nil
end
function TP.listen_hold(key, tr, band, sw)
  if web_held and web_held.key ~= key then held_stop() end
  if not web_held then
    web_held = { key = key, tr = tr, band = band, sw = sw }
    if sw then sw(true) end
  end
  web_held.t = reaper.time_precise()
end
function TP.listen_release(key)
  if web_held and (key == nil or web_held.key == key) then held_stop() end
end
function TP.listen_tick()
  if not web_held then return end
  if reaper.time_precise() - web_held.t > 0.35 then held_stop() return end
  if not web_held.sw then
    local hz, q, kind = web_held.band()
    if hz then TP.listen(web_held.tr, hz, q, kind) end
  end
end

-- ---------------------------------------------------------------------
-- make-up gain
-- ---------------------------------------------------------------------

-- Which controls are a plugin's make-up: the layout's own (Makeup=, a
-- control on it), else a compressor canvas's Makeup role or a multiband
-- canvas's Output; and any parameter named as one (Makeup, Out Gain,
-- Output...), added together; a multiband canvas's band Gain roles too,
-- for the tap the probe splits (tap_mb). Each is written as dB + 1000 * a count, the
-- count moved when what's taken out changes rather than the audio (the
-- script starting, another control being the make-up): the probe then
-- moves what it has learnt with it. A control that doesn't read in dB
-- isn't followed.
--
-- The window and the web bridge both run TP.update; the bridge leaves it
-- to the window while the window is running (ExtState mug_at), so the two
-- never write different answers turn about.
TP.MUG_EVERY, TP.MUG_KEY = 1.0, "mug_at"
TP.MUG_LO = -150   -- dB: the lowest make-up passed on (a knob turned right down)
local mug = { list = {}, at = -10, k = {}, kb = {}, by_addr = {}, by_guid = {}, said = -10 }

-- A control's own value in dB, before any custom range: what the plugin
-- says at its position when that's in dB (some VST3s leave the unit off
-- their readout but give it when asked at a position), or a bare number
-- on a control that runs from below 0 to above it (-18 to 18, -inf to
-- 12): a gain in dB without the unit.
local bare_gain = {}
local function bare(s)
  s = U.trim(s or ""):lower()
  if s == "-inf" or s == "-oo" then return -math.huge end
  return s:match("^[%+%-]?%d*%.?%d+$") and tonumber(s) or nil
end
local function as_db(s)
  local b = bare(s)
  if b then return b, false end
  local v, unit = require("TS_CV_Units").parse(s or "")
  if unit == "db" and v and v == v then return v, true end
  local t = U.trim(s or ""):lower()
  if t:match("^%-inf") or t:match("^%-oo") then return -math.huge, true end
  return nil
end
local function own_db(tr, addr, p)
  local fmt = reaper.TrackFX_FormatParamValueNormalized
  if not fmt then return nil end
  local _, now = fmt(tr, addr, p, reaper.TrackFX_GetParamNormalized(tr, addr, p) or 0, "")
  local v, unit = as_db(now)
  if v and unit then return math.max(TP.MUG_LO, math.min(60, v)) end
  local k = tostring(reaper.TrackFX_GetFXGUID(tr, addr)) .. ":" .. p
  local ok = bare_gain[k]
  if ok == nil then
    local _, a = fmt(tr, addr, p, 0, "")
    local _, b = fmt(tr, addr, p, 1, "")
    local va, vb = as_db(a), as_db(b)
    ok = (va and vb and va < 0 and vb > 0) and true or false
    bare_gain[k] = ok
  end
  if not ok then return nil end
  if not v then
    local _, s = reaper.TrackFX_GetFormattedParamValue(tr, addr, p, "")
    v = bare(s)
  end
  return v and math.max(TP.MUG_LO, math.min(60, v)) or nil
end

-- A control's value in dB as it reads (through its custom range, if it
-- has one), or nil when it doesn't read in dB.
function TP.makeup_db(tr, addr, p, ranges, law)
  if not (tr and addr and p and p >= 0) then return nil end
  -- a knob measured as a gain (GainLaw<p>): its dB at where it is
  if law then return U.gainlaw_at(law, reaper.TrackFX_GetParamNormalized(tr, addr, p) or 0) end
  local own = own_db(tr, addr, p)
  if own then return own end
  local UN = require("TS_CV_Units")
  local was = U.with_ranges(ranges)
  local txt = U.fmt_value(tr, addr, p)
  U.with_ranges(was)
  local v, unit = UN.parse(txt or "")
  if unit ~= "db" or not v or v ~= v or math.abs(v) >= 1000 then return nil end
  return math.max(TP.MUG_LO, math.min(60, v))
end

-- A parameter's name that says it's a gain the whole signal goes through:
-- Makeup, Make-up Gain, Out Gain, Output, Output Trim, Wet (ReaComp's
-- output), and Input, Input Gain, In Gain, Gain -- a gain before the
-- compressor moves what "no reduction" is just as one after it does, and
-- the extra reduction it brings is measured (dB on the end allowed). Only
-- followed when it reads in dB, so a Wet in % or a Gain of 0 to 100 isn't.
function TP.makeup_name(name)
  local n = (name or ""):lower():gsub("[^%a]", ""):gsub("db$", "")
  return n:find("^makeup") ~= nil or n == "mug" or n == "output" or n == "out" or n == "outputgain"
    or n == "outgain" or n == "gainout" or n == "outputtrim" or n == "outtrim" or n == "wet"
    or n == "input" or n == "inputgain" or n == "ingain" or n == "gainin" or n == "gain"
end
-- A plugin's parameters named as output gains, kept by plugin while its
-- parameter count stays the same.
local mug_named = {}
local function named_makeups(tr, addr)
  local guid = reaper.TrackFX_GetFXGUID(tr, addr)
  local n = reaper.TrackFX_GetNumParams(tr, addr)
  local c = guid and mug_named[guid]
  if c and c.n == n then return c.ps end
  local ps = {}
  for p = 0, n - 1 do
    local ok, nm = reaper.TrackFX_GetParamName(tr, addr, p, "")
    if ok and TP.makeup_name(nm) then ps[#ps + 1] = p end
  end
  if guid then mug_named[guid] = { n = n, ps = ps } end
  return ps
end
TP.named_makeups = named_makeups

-- A plugin's make-up controls: { p (the first), ps (all of them), bands =
-- { [k] = param }, plan (the multiband's, TP.mb_plan), ranges, sig, bsig },
-- or nil.
function TP.makeup_of(layout, tr, addr)
  layout = layout or {}
  local p
  if layout.mug then
    for _, c in ipairs(layout.controls or {}) do
      if c.param == layout.mug then p = layout.mug; break end
    end
  end
  local cv = layout.canvas
  local R = (cv and cv.roles) or {}
  if not p and cv then p = (cv.kind == "comp" and R.Makeup) or (cv.kind == "multi" and R.Output) or nil end
  -- (a knob checked as not a gain never is: GainRole<p>=no)
  local role = layout.gainrole or {}
  local ps, seen = {}, {}
  for q in pairs(role) do if role[q] == "no" then seen[q] = true end end
  local function add(q) if q and not seen[q] then ps[#ps + 1] = q; seen[q] = true end end
  add(p)
  -- named as one, until the plugin's gain knobs are checked: then the
  -- knobs checked as gains instead
  if tr and addr and not layout.gaincheck then
    for _, q in ipairs(named_makeups(tr, addr)) do add(q) end
  end
  local more = {}
  for q, r in pairs(role) do if r ~= "no" then more[#more + 1] = q end end
  -- and any knob measured as a gain
  for q in pairs(layout.gainlaw or {}) do more[#more + 1] = q end
  table.sort(more)
  for _, q in ipairs(more) do add(q) end
  p = ps[1]
  local bands, plan, bsig
  if cv and cv.kind == "multi" then
    for k = 1, cv.nb or 3 do
      local bp = R["B" .. k .. "Gain"]
      if bp then bands = bands or {}; bands[k] = bp end
    end
    if bands and tr then
      plan = TP.mb_plan(tr, addr, cv)
      local t = {}
      for k = 1, cv.nb or 3 do
        if bands[k] then t[#t + 1] = ("%d=%d@%s"):format(k, bands[k], tostring(plan.at[k])) end
      end
      bsig = table.concat(t, ",")
    end
  end
  if not p and not bands then return nil end
  local sig = {}
  for _, q in ipairs(ps) do
    local rg = layout.ranges and layout.ranges[q]
    local law = layout.gainlaw and layout.gainlaw[q]
    sig[#sig + 1] = tostring(q) .. "|" .. (rg and M.range_line(rg) or "") .. (law and ("|" .. (M.gainlaw_line and M.gainlaw_line(law) or "law")) or "")
  end
  return { p = p, ps = ps, bands = bands, plan = plan, ranges = layout.ranges, laws = layout.gainlaw,
           sig = table.concat(sig, ";"), bsig = bsig }
end

-- A multiband's split bands' gains, dB (four, 0 where none): each of its
-- bands' Gain, in the split band it's measured in (bands past four on
-- shared crossovers are measured together in the fourth: their mean).
local function band_gains(e)
  local sum, n, out = {}, {}, {}
  local plan = e.src.plan
  for k, bp in pairs(e.src.bands or {}) do
    local j = plan and (plan.at[k] or ((not plan.own and k > 3) and 4 or nil))
    local v = j and (not plan[k] or plan[k].used ~= false) and TP.makeup_db(e.tr, e.addr, bp, e.src.ranges)
    if v then sum[j] = (sum[j] or 0) + v; n[j] = (n[j] or 0) + 1 end
  end
  for j = 1, 4 do out[j] = n[j] and sum[j] / n[j] or 0 end
  return out
end

-- Every tapped plugin's make-up controls, again (once a second).
local function mug_rebuild()
  local list, by_addr, by_guid = {}, {}, {}
  for ti = 0, reaper.CountTracks(0) - 1 do
    local tr = reaper.GetTrack(0, ti)
    local rec = read_record(tr)
    local lv = rec and find_level(tr, nil)
    local probe = lv and lv.items[lv.post]
    if probe and fx_guid(tr, probe) == rec.probe and not PL.is_legacy(tr, probe) then
      local gm
      for i, t in ipairs(rec.taps) do
        if (t.what or "g"):find("g", 1, true) then
          gm = gm or guid_map(tr)
          local addr = gm[t.guid]
          if addr then
            local layout = M.get(St.layout_key(fx_name(tr, addr), t.guid, tr, addr))
            local e = { tr = tr, probe = probe, i = i, guid = t.guid, addr = addr,
                        src = TP.makeup_of(layout, tr, addr) }
            list[#list + 1] = e
            by_addr[tostring(tr) .. ":" .. addr] = e
            by_guid[t.guid] = e
          end
        end
      end
    end
  end
  mug.list, mug.by_addr, mug.by_guid = list, by_addr, by_guid
end

-- A count that says what's taken out changed: one on from the probe's.
local function next_count(v) return (math.floor(((v or 0) + 500) / 1000) + 1) % 100 end

local function mug_tick(now, web)
  if web then
    local t = tonumber(reaper.GetExtState("TS_ChannelView", TP.MUG_KEY))
    if t and now - t < 1.5 and now >= t then return end
  elseif now - mug.said > 0.5 then
    mug.said = now
    reaper.SetExtState("TS_ChannelView", TP.MUG_KEY, ("%.3f"):format(now), false)
  end
  local fresh = now - mug.at >= TP.MUG_EVERY
  if fresh then mug.at = now; mug_rebuild() end
  local probes = {}
  for _, e in ipairs(mug.list) do
    if reaper.ValidatePtr(e.tr, "MediaTrack*") then
      -- every make-up control that reads in dB, added up
      local v, sig, d = 0, "none", nil
      local fs
      for _, q in ipairs(e.src and e.src.ps or {}) do
        local dq = TP.makeup_db(e.tr, e.addr, q, e.src.ranges, e.src.laws and e.src.laws[q])
        if dq then d = (d or 0) + dq; fs = fs or {}; fs[q] = true end
      end
      if d then v, sig = math.max(TP.MUG_LO, math.min(60, d)), e.src.sig end
      sig = sig .. "|" .. e.i
      local st = mug.k[e.guid]
      if not st or st.sig ~= sig then
        st = { sig = sig, k = next_count(PL.get(e.tr, e.probe, "mug", e.i)) }
        mug.k[e.guid] = st
      end
      PL.set(e.tr, e.probe, "mug", e.i, v + 1000 * st.k)
      e.fset = fs
      local pk = tostring(e.tr)
      local pr = probes[pk]
      if not pr then
        pr = { e = e, used = {}, mb = math.floor((PL.get(e.tr, e.probe, "mb") or 0) + 0.5) }
        probes[pk] = pr
      end
      pr.used[e.i] = true
      if pr.mb == e.i then pr.owner = e end
    end
  end
  for pk, pr in pairs(probes) do
    local tr, probe = pr.e.tr, pr.e.probe
    -- slots no tap uses: nothing taken out
    for i = 1, fresh and TP.capacity(tr, probe) or 0 do
      if not pr.used[i] then
        local cur = PL.get(tr, probe, "mug", i) or 0
        local k = math.floor((cur + 500) / 1000)
        if cur - 1000 * k ~= 0 then PL.set(tr, probe, "mug", i, 1000 * k) end
      end
    end
    -- the split bands' own gains, from the plugin the probe splits
    local o = pr.owner
    local g = (o and o.src and o.src.bands) and band_gains(o) or { 0, 0, 0, 0 }
    local bsig = (o and o.src and o.src.bsig) and (o.guid .. "|" .. o.src.bsig) or "none"
    local st = mug.kb[pk]
    if not st or st.sig ~= bsig then
      st = { sig = bsig, k = next_count(PL.get(tr, probe, "mbmug", 1)) }
      mug.kb[pk] = st
    end
    for j = 1, 4 do PL.set(tr, probe, "mbmug", j, g[j] + 1000 * st.k) end
    if o and o.src and o.src.bands then
      o.fset = o.fset or {}
      for _, bp in pairs(o.src.bands) do o.fset[bp] = true end
    end
  end
end

-- Whether moving this control of a plugin is its make-up moving, which the
-- probe follows (and so not a touch).
function TP.makeup_followed(tr, guid, p)
  local e = guid and mug.by_guid[guid]
  return (e and e.tr == tr and p and e.fset and e.fset[p]
          and (PL.get(tr, e.probe, "mug_cap") or 0) >= 0.5) and true or false
end

-- What a gain knob's name says it is: "in", "out" or "mu" (make-up), or nil.
function TP.gain_role_of(name)
  local n = (name or ""):lower():gsub("[^%a]", ""):gsub("db$", "")
  if n:find("makeup", 1, true) or n == "mug" then return "mu" end
  if n:find("^input") or n:find("^ingain") or n:find("^intrim") or n == "in" or n == "gainin" then return "in" end
  if n:find("^output") or n:find("^outgain") or n:find("^outtrim") or n == "out" or n == "gainout"
     or n == "wet" then return "out" end
  if TP.makeup_name(name) then return "mu" end
  return nil
end

-- A plugin's gain knobs, for checking: { { p, role }, ... } by parameter.
-- Those checked (GainRole<p>), else those named as gains (TP.gain_role_of;
-- a Wet only when it reads in dB, as ReaComp's does), the knob marked as
-- the make-up, and its compressor canvas's Makeup and Input or
-- multiband's Output.
function TP.gain_candidates(tr, addr, layout)
  layout = layout or {}
  local out, seen = {}, {}
  local function add(q, r)
    if q and q >= 0 and not seen[q] then out[#out + 1] = { q, r }; seen[q] = true end
  end
  for q, r in pairs(layout.gainrole or {}) do add(q, r) end
  if not layout.gaincheck then
    -- (what its name says first: a knob marked as the make-up may be the
    -- plugin's Output)
    local function by_name(q, r)
      if not q or q < 0 then return end
      local _, nm = reaper.TrackFX_GetParamName(tr, addr, q, "")
      add(q, TP.gain_role_of(nm) or r)
    end
    by_name(layout.mug, "mu")
    local cv = layout.canvas
    local R = (cv and cv.roles) or {}
    if cv and cv.kind == "comp" then by_name(R.Makeup, "mu"); by_name(R.Input, "in") end
    if cv and cv.kind == "multi" then by_name(R.Output, "out") end
    for _, q in ipairs(named_makeups(tr, addr)) do
      local _, nm = reaper.TrackFX_GetParamName(tr, addr, q, "")
      local r = TP.gain_role_of(nm)
      if (nm or ""):lower():gsub("[^%a]", "") ~= "wet" or TP.makeup_db(tr, addr, q, layout.ranges) then add(q, r or "mu") end
    end
  end
  table.sort(out, function(a, b) return a[1] < b[1] end)
  return out
end

-- The knobs to measure as gains: those of TP.gain_candidates that are.
function TP.gain_knobs(tr, addr, layout)
  local out = {}
  for _, c in ipairs(TP.gain_candidates(tr, addr, layout)) do
    if c[2] ~= "no" then out[#out + 1] = c[1] end
  end
  return out
end

-- Gain knobs being measured on a hidden copy (TS_CV_Learn LN.start_gain),
-- in the background: { job, guid, ps, what }. One at a time. How each
-- ended, for the panel's header: { [guid] = { ok, why, at } }.
local gjob
local gdone = {}
function TP.measure_gain(tr, addr, key, layout, ps)
  if gjob or not (ps and #ps > 0) then return false end
  local ok, LN = pcall(require, "TS_CV_Learn")
  if not ok then return false end
  local what = "its gain knobs"
  if #ps == 1 then
    local _, nm = reaper.TrackFX_GetParamName(tr, addr, ps[1], "")
    if nm and nm ~= "" then what = nm end
  end
  local guid = fx_guid(tr, addr)
  gjob = { job = LN.start_gain(tr, addr, key, layout, ps), guid = guid, ps = ps, what = what,
           t0 = reaper.time_precise() }
  gdone[guid] = nil
  return true
end
-- The measuring now, for a window to show: { guid, ps, p (the knob being
-- measured), i (its place in ps), progress, left (s, a guess) }, or nil.
function TP.gain_job()
  if not gjob then return nil end
  local j = gjob.job
  local st = j.steps and j.steps[j.i]
  local gi = st and st.gi or 1
  local pr = j.progress or 0
  local el = reaper.time_precise() - gjob.t0
  return { guid = gjob.guid, ps = gjob.ps, p = gjob.ps[gi], i = gi, progress = pr,
           left = pr > 0.05 and el * (1 - pr) / pr or nil }
end
-- How the last measuring of this plugin ended: { ok, why, results (TS_CV_
-- Learn's, each knob's), cancelled }, or nil. Kept until asked again.
local gres = {}
function TP.gain_result(guid) return gres[guid] end
function TP.gain_forget(guid) gres[guid] = nil end
function TP.gain_cancel()
  if not gjob then return end
  require("TS_CV_Learn").cancel(gjob.job)
  gres[gjob.guid] = { ok = false, cancelled = true, results = {} }
  gjob = nil
end
-- What the panel's header says about it: { text, progress (0..1, while
-- measuring), ok (when done), why (when it failed) }, or nil.
TP.GAIN_SAID_OK, TP.GAIN_SAID_FAIL = 3, 10   -- s the outcome stays up
function TP.gain_status(guid)
  if gjob and gjob.guid == guid then
    return { text = "Measuring " .. gjob.what .. "\u{2026}", progress = gjob.job.progress or 0 }
  end
  local d = gdone[guid]
  if not d then return nil end
  if reaper.time_precise() - d.at > (d.ok and TP.GAIN_SAID_OK or TP.GAIN_SAID_FAIL) then gdone[guid] = nil return nil end
  return { text = d.ok and "Measured" or "Not measured", ok = d.ok, why = d.why }
end
-- How far along measuring this knob is (0..1), or nil when it isn't.
function TP.gain_measuring(guid, p)
  if not gjob or gjob.guid ~= guid then return nil end
  for _, q in ipairs(gjob.ps) do if q == p then return gjob.job.progress or 0 end end
  return nil
end
local function gain_tick()
  if not gjob then return end
  require("TS_CV_Learn").step(gjob.job)
  local st = gjob.job.state
  if st ~= "starting" and st ~= "measuring" then
    gdone[gjob.guid] = { ok = st == "done", why = (st ~= "done") and gjob.job.msg or nil, at = reaper.time_precise() }
    gres[gjob.guid] = { ok = st == "done", why = (st ~= "done") and gjob.job.msg or nil, results = gjob.job.results or {} }
    gjob = nil
    TP.makeup_changed()
  end
end

-- Forget which controls are the make-up (a layout changed).
function TP.makeup_changed() mug.at = -10; mug_named = {}; bare_gain = {} end

-- ---------------------------------------------------------------------
-- relearning
-- ---------------------------------------------------------------------

-- A measured plugin was touched: its make-up or EQ may have moved, so the
-- probe drops what it learnt from the music, and marks a measured zero as
-- touched-since (measured again once stopped and quiet).
--
-- On a current probe it goes through gmem, not a parameter, so "Tap 1
-- relearn" never becomes REAPER's last touched parameter. `p`, the control
-- moved: its make-up, followed (TP.makeup_followed), isn't a touch.
local last_touch = nil
function TP.touched(tr, guid, p)
  if p and TP.makeup_followed(tr, guid, p) then return end
  local i, rd = tap_for(tr, guid, "g")
  if not i or not rd.probe then return end
  PL.set(tr, rd.probe, "rst", i, (math.floor(PL.get(tr, rd.probe, "rst", i) or 0) + 1) % 1000000)
end

-- A track's zero being measured (the pre probe's phase, TS_TrackProbe's
-- CAL_BASE + index * 8 + 1), or a moment after: a plugin that reports its
-- own meters as parameters moves them on the test noise, and REAPER takes
-- that for a touch -- which would ask for the zero again, every five
-- seconds, for as long as it's stopped.
TP.CAL_BASE, TP.CAL_STRIDE = 0x60000, 8
TP.cal_seen = {}
local function zero_running(tr, trn)
  if trn < 1 or trn > 4096 then return false end
  local now = reaper.time_precise()
  if reaper.gmem_read(TP.CAL_BASE + (trn - 1) * TP.CAL_STRIDE + 1) > 0 then TP.cal_seen[tr] = now end
  return now - (TP.cal_seen[tr] or -100) < 3
end

local function poll_touched()
  local ok, trn, fxn, parm = reaper.GetLastTouchedFX()
  if not ok then return end
  local tr = (trn == 0) and reaper.GetMasterTrack(0) or reaper.GetTrack(0, trn - 1)
  -- (watched every frame, so the moment after a run is caught too)
  local running = tr and zero_running(tr, trn)
  local k = ("%d:%d:%d"):format(trn, fxn, parm)
  if k == last_touch then return end
  local first = (last_touch == nil)
  last_touch = k
  if first or running then return end
  if tr then TP.touched(tr, fx_guid(tr, fxn), parm) end
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
function TP.update(now, web)
  now = now or reaper.time_precise()
  web = web or false          -- (the web bridge's: see make-up gain)
  if not web then gain_tick() end
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
  -- only the tracks on screen: each one read lately named in its block
  reaper.gmem_write(TP.GATE_SLOT, hb)
  for key, w in pairs(watched) do
    if now - w.t > TP.WATCH_FOR or not reaper.ValidatePtr(w.tr, "MediaTrack*") then watched[key] = nil
    else
      local b = PL.block(w.tr)
      if b then reaper.gmem_write(b + TP.WATCH_OFF, hb) end
    end
  end
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
  mug_tick(now, web)
  -- tracks that moved: their names follow (TS_CV_ProbeLink), and their
  -- taps' settings are written again where they are now
  local moved = PL.tick()
  for _, m in ipairs(moved or {}) do
    if reaper.ValidatePtr(m.tr, "MediaTrack*") then
      next_at[tostring(m.tr)] = now + TP.CHECK_EVERY
      TP.sync(m.tr)
    end
  end
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
  mug.at = -10
  levels_ok = {}
  order_cache = {}
  has_cache = {}
  which_cache = {}
  any_until = 0
end

return TP
