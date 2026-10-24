-- @noindex
-- Not a package of its own: installed by TS_ChannelView.lua's @provides.
--[[
  TS_CV_Mod.lua -- macros and modulators: the mechanics, without the drawing.

  ONE PLUGIN PER TRACK
    A track's macros and modulators all live in one JSFX of ours,
    "ChannelView Modulators" (TS_CV_Modulators.jsfx), at the top level of
    the chain after the pre probe (and any ARA plugin in the first slot).
    It's put there when the first macro or modulator is added, and taken
    away again when the last one goes (unless it has automation of its
    own). Its parameters:
      0-15                 Macro 1-16 (0..1)
      16 + 22*(n-1) + k    Modulator n's field k (MD.FIELDS)
    so every macro and every modulator setting is a REAPER parameter:
    automation lanes, control surfaces and ReaLearn all reach them, and
    they run with ChannelView closed.

  LINKS (REAPER's own parameter modulation)
    A control is driven by giving its parameter a link from one of ours:
    mod.active 1, plink.active 1, plink.effect = our plugin's slot,
    plink.param = the macro or the modulator's output. Its value is then
        baseline + scale * (source + offset)
      * from a macro: baseline is where the control sits with the macro
        at 0%, baseline + scale where it sits at 100% (the two ends of
        its range; scale < 0 runs it backwards), offset 0
      * from a modulator: baseline is where the control is set, scale how
        far it swings (the depth), offset 0 from the Output (one way), or
        -0.5 from the Output bipolar (both ways round where it's set)
    A control inside a container is exposed up through each container
    above it (container_map) and the link is made on the outermost one's
    parameter -- links live at the top level.
    A parameter takes one link: a control is driven by one source.

  What's ours (names, colours, a macro's control type and a dropdown's
  choices) is kept on the track, P_EXT:TS_CV_MACROS / TS_CV_MODS. A
  modulator is in use when its Type isn't Off; a macro when the track
  says so.

  The track's links are read in one pass (MD.scan) and kept until the
  project changes, since it means asking every parameter of every plugin.

  The idea of macros and modulators in the chain, linked by REAPER's
  parameter modulation, is Saxmand's (FX Modulator Linking), with thanks.
--]]

local U  = require("TS_CV_Util")
local T  = require("TS_CV_FXTree")

local MD = {}

MD.DESC = "ChannelView Modulators"
MD.NM, MD.NO, MD.PER = 16, 8, 22
MD.EXT_MACROS = "P_EXT:TS_CV_MACROS"
MD.EXT_MODS   = "P_EXT:TS_CV_MODS"

-- REAPER resolves a JSFX by its path under Effects/, which depends on how
-- it was installed; each is tried in turn.
MD.PATHS = {
  "TS-ReaScripts/TS_ChannelView/TS_CV_Modulators.jsfx",
  "TS_ChannelView/TS_CV_Modulators.jsfx",
  "TS_CV_Modulators.jsfx",
  "JS: " .. MD.DESC,
}

-- A modulator's fields, in the plugin's order: key, default, lo, hi.
MD.FIELDS = {
  { "type",   0,    0, 3 },
  { "out",    0,    0, 1 },
  { "outb",   0.5,  0, 1 },
  { "depth",  1,    0, 1 },
  { "smooth", 0,    0, 1 },
  { "shape",  0,    0, 5 },
  { "sync",   1,    0, 1 },
  { "rsync",  5,    0, 15 },
  { "rhz",    1,    0.01, 20 },
  { "phase",  0,    0, 1 },
  { "fsrc",   0,    0, 1 },
  { "att",    10,   0, 500 },
  { "rel",    200,  0, 2000 },
  { "floor",  -48,  -80, 0 },
  { "ceil",   0,    -60, 12 },
  { "gate",   0,    0, 1 },
  { "msrc",   0,    0, 4 },
  { "mch",    0,    0, 16 },
  { "mcc",    1,    0, 127 },
  { "mlo",    36,   0, 127 },
  { "mhi",    96,   0, 127 },
  { "mhold",  1,    0, 1 },
}
local OFF = {}
for k, f in ipairs(MD.FIELDS) do OFF[f[1]] = k - 1; MD.FIELDS[f[1]] = f end
MD.OFF = OFF
assert(#MD.FIELDS == MD.PER)

-- 0-based parameter of macro i / modulator j's field
function MD.macro_param(i) return i - 1 end
function MD.param(j, key) return MD.NM + (j - 1) * MD.PER + OFF[key] end

-- the kinds of modulator, by Type
MD.KINDS = { "lfo", "follower", "midi" }
MD.KIND_NAME = { lfo = "LFO", follower = "Follower", midi = "MIDI" }
local KIND_TYPE = { lfo = 1, follower = 2, midi = 3 }
MD.KIND_TYPE = KIND_TYPE

-- the control types a macro can be shown as
MD.CTLS = {
  { key = "knob",     name = "Knob" },
  { key = "button",   name = "Button",   note = "on / off" },
  { key = "fader",    name = "Fader" },
  { key = "dropdown", name = "Dropdown", note = "2\u{2013}8 choices" },
  { key = "xy",       name = "XY pad",   note = "two macros" },
}

MD.SHAPES = { "Sine", "Triangle", "Square", "Saw up", "Saw down", "Random" }
MD.SYNC = { "1/16", "1/8 T", "1/8", "1/8 D", "1/4 T", "1/4", "1/4 D", "1/2 T",
            "1/2", "1/2 D", "1 T", "1", "1 D", "2", "4", "8" }
MD.MIDI_SRC = { "Velocity", "Note", "CC", "Pitch bend", "Aftertouch" }

MD.COLOURS = { 0xe8a23aff, 0xb07ce8ff, 0x4cc3a8ff, 0xd9604aff, 0x5aa0e0ff, 0xd8c450ff,
               0x9ac46aff, 0xc07aa0ff, 0x6ac4c4ff, 0x7a9ae8ff, 0xe07ab0ff, 0xa0a8b0ff }
local KIND_COL = { lfo = 0xb07ce8ff, follower = 0x4cc3a8ff, midi = 0x7a9ae8ff }

-- ---------------------------------------------------------------------
-- small REAPER helpers
-- ---------------------------------------------------------------------

local function get(track, addr, k)
  local ok, v = reaper.TrackFX_GetNamedConfigParm(track, addr, k)
  if ok then return v end
  return nil
end
local function getn(track, addr, k) return tonumber(get(track, addr, k) or "") end
local function set(track, addr, k, v)
  return reaper.TrackFX_SetNamedConfigParm(track, addr, k, tostring(v))
end
MD.get, MD.getn, MD.set = get, getn, set

local function fx_name(track, addr)
  local n = get(track, addr, "fx_name")
  if n and n ~= "" then return n end
  local ok, nm = reaper.TrackFX_GetFXName(track, addr, "")
  return ok and nm or ""
end

-- ---------------------------------------------------------------------
-- the plugin
-- ---------------------------------------------------------------------

function MD.is_ours(name) return (name or ""):find(MD.DESC, 1, true) ~= nil end

-- The top-level slot of the track's ChannelView Modulators, or nil.
function MD.plugin(track)
  if not track then return nil end
  local n = reaper.TrackFX_GetCount(track) or 0
  for i = 0, n - 1 do
    if MD.is_ours(fx_name(track, i)) then return i end
  end
  return nil
end

-- Where it goes: after any ARA plugin in the first slot and the pre
-- probe (TS_TrackProbe), so the probes still measure the whole chain and
-- nothing sits in front of an ARA plugin, which REAPER refuses.
function MD.slot_for(track, ara_first)
  local n = reaper.TrackFX_GetCount(track) or 0
  local slot = 0
  if ara_first and n > 0 then slot = 1 end
  while slot < n do
    if fx_name(track, slot):find("TS_TrackProbe", 1, true) then slot = slot + 1 else break end
  end
  return slot
end

-- The plugin, put on the track if it isn't there. nil if REAPER can't
-- find the JSFX.
function MD.ensure(track, ara_first)
  local m = MD.plugin(track)
  if m then return m end
  local slot = MD.slot_for(track, ara_first)
  for _, p in ipairs(MD.PATHS) do
    local idx = reaper.TrackFX_AddByName(track, p, false, -1000 - slot)
    if idx and idx >= 0 then
      reaper.TrackFX_Show(track, idx, 2)    -- no floating window
      MD.invalidate(track)
      return idx
    end
  end
  return nil
end

-- One of our own parameters with REAPER's parameter modulation switched on
-- (by hand in the plugin window, or a stray link) holds at its modulation
-- baseline whatever is written to it -- a macro would snap back the moment
-- you let go. Writing the baseline too makes the write stick.
-- Modulation switched on with nothing driving it (no link, no LFO, no
-- follower) does nothing but pin the parameter: it's switched off.
local function hold_baseline(track, slot, p, norm)
  local function on(k) return get(track, slot, ("param.%d.%s"):format(p, k)) == "1" end
  if on("mod.active") then
    if not (on("plink.active") or on("lfo.active") or on("acs.active")) then
      set(track, slot, ("param.%d.mod.active"):format(p), 0)
    else
      set(track, slot, ("param.%d.mod.baseline"):format(p), math.max(0, math.min(1, norm)))
    end
  end
end

-- A lane with one point (a flat line, no automation) still holds its
-- parameter there -- even stopped, the envelope wins a moment later. So a
-- flat lane follows the control: its point moves with it. A lane with real
-- automation (more points) owns the parameter, as in REAPER: write to it
-- with Touch / Latch.
local function follow_flat_lane(track, slot, p, norm)
  local env = reaper.GetFXEnvelope(track, slot, p, false)
  if not env or (reaper.CountEnvelopePoints(env) or 0) ~= 1 then return end
  local _, mn, mx = reaper.TrackFX_GetParamEx(track, slot, p)
  mn, mx = mn or 0, mx or 1
  if mx <= mn then mn, mx = 0, 1 end
  local v = math.max(0, math.min(1, norm))
  reaper.SetEnvelopePoint(env, 0, nil, mn + v * (mx - mn), nil, nil, nil, true)
  reaper.Envelope_SortPoints(env)
end

-- Real values (in the field's own units) of a modulator's fields.
function MD.field(track, slot, j, key)
  local v = reaper.TrackFX_GetParam(track, slot, MD.param(j, key))
  return v or MD.FIELDS[key][2]
end
function MD.set_field(track, slot, j, key, v)
  local f = MD.FIELDS[key]
  v = math.max(f[3], math.min(f[4], v))
  reaper.TrackFX_SetParam(track, slot, MD.param(j, key), v)
  hold_baseline(track, slot, MD.param(j, key), (v - f[3]) / (f[4] - f[3]))
  follow_flat_lane(track, slot, MD.param(j, key), (v - f[3]) / (f[4] - f[3]))
end

-- ---------------------------------------------------------------------
-- what's ours, kept on the track
-- ---------------------------------------------------------------------

local function clean(s) return U.trim(((s or ""):gsub("[|;\r\n]", " "))) end
local function hex(c) return ("%06x"):format((c >> 8) & 0xffffff) end
local function unhex(h) local n = tonumber(h or "", 16) return n and ((n << 8) | 0xff) or nil end

-- macros[i] = { ctl, col, name, choices }
function MD.read_macros(track)
  local ok, s = reaper.GetSetMediaTrackInfo_String(track, MD.EXT_MACROS, "", false)
  local out = {}
  if not (ok and s) then return out end
  for line in s:gmatch("[^\n]+") do
    local i, ctl, h, name, ch = line:match("^(%d+)|([%w]+)|(%x*)|([^|]*)|?(.*)$")
    i = tonumber(i)
    if i and i >= 1 and i <= MD.NM then
      local choices
      if ch and ch ~= "" then
        choices = {}
        for c in (ch .. ";"):gmatch("([^;]*);") do choices[#choices + 1] = c end
      end
      out[i] = { ctl = ctl, col = unhex(h), name = name, choices = choices }
    end
  end
  return out
end
function MD.write_macros(track, macros)
  local lines = {}
  for i = 1, MD.NM do
    local m = macros[i]
    if m then
      local ch = {}
      for k, c in ipairs(m.choices or {}) do ch[k] = clean(c) end
      ch = table.concat(ch, ";")
      lines[#lines + 1] = ("%d|%s|%s|%s|%s"):format(i, m.ctl or "knob", m.col and hex(m.col) or "",
                                                 clean(m.name), ch)
    end
  end
  reaper.GetSetMediaTrackInfo_String(track, MD.EXT_MACROS, table.concat(lines, "\n"), true)
  MD.invalidate(track)
end

-- mods[j] = { col, name }
function MD.read_mods(track)
  local ok, s = reaper.GetSetMediaTrackInfo_String(track, MD.EXT_MODS, "", false)
  local out = {}
  if not (ok and s) then return out end
  for line in s:gmatch("[^\n]+") do
    local j, h, name = line:match("^(%d+)|(%x*)|(.*)$")
    j = tonumber(j)
    if j and j >= 1 and j <= MD.NO then out[j] = { col = unhex(h), name = name } end
  end
  return out
end
function MD.write_mods(track, mods)
  local lines = {}
  for j = 1, MD.NO do
    local m = mods[j]
    if m then lines[#lines + 1] = ("%d|%s|%s"):format(j, m.col and hex(m.col) or "", clean(m.name)) end
  end
  reaper.GetSetMediaTrackInfo_String(track, MD.EXT_MODS, table.concat(lines, "\n"), true)
  MD.invalidate(track)
end

-- ---------------------------------------------------------------------
-- the sources: macros and modulators in use
-- ---------------------------------------------------------------------
--   { guid ("m3", "o2"), src ("macro"/"mod"), kind (a macro's control
--     type; a modulator's "lfo"/"follower"/"midi"), i or j, name, col,
--     out = { param, ... } (an XY's two), labels, outb (a modulator's
--     bipolar output), choices (a dropdown's) }

local function build(track, slot)
  local list, macros, mods = {}, {}, {}
  if not slot then return list, macros, mods end
  local meta = MD.read_macros(track)
  local covered = {}
  for i = 1, MD.NM do
    local m = meta[i]
    if m and not covered[i] then
      local ctl = m.ctl or "knob"
      local src = { guid = "m" .. i, src = "macro", kind = ctl, i = i, slot = slot,
                    name = (m.name and m.name ~= "") and m.name or ("Macro " .. i),
                    col = m.col or MD.COLOURS[(i - 1) % #MD.COLOURS + 1],
                    out = { i - 1 }, choices = m.choices }
      if ctl == "xy" and i < MD.NM then
        src.out = { i - 1, i }
        src.labels = { "X", "Y" }
        covered[i + 1] = true
      elseif ctl == "xy" then
        src.kind = "knob"
      end
      if ctl == "dropdown" and not (src.choices and #src.choices >= 2) then
        src.choices = { "1", "2", "3" }
      end
      list[#list + 1] = src
      macros[#macros + 1] = src
    end
  end
  local mmeta = MD.read_mods(track)
  for j = 1, MD.NO do
    local t = math.floor((reaper.TrackFX_GetParam(track, slot, MD.param(j, "type")) or 0) + 0.5)
    local kind = MD.KINDS[t]
    if kind then
      local m = mmeta[j] or {}
      local src = { guid = "o" .. j, src = "mod", kind = kind, j = j, slot = slot,
                    name = (m.name and m.name ~= "") and m.name or (MD.KIND_NAME[kind] .. " " .. j),
                    col = m.col or KIND_COL[kind],
                    out = { MD.param(j, "out") }, outb = MD.param(j, "outb") }
      list[#list + 1] = src
      mods[#mods + 1] = src
    end
  end
  return list, macros, mods
end

-- How many of the 16 macro slots are taken (an XY takes two).
function MD.macros_used(track)
  local n = 0
  for i, m in pairs(MD.read_macros(track)) do n = n + ((m.ctl == "xy" and i < MD.NM) and 2 or 1) end
  return n
end

-- ---------------------------------------------------------------------
-- links
-- ---------------------------------------------------------------------

-- The parameter of container `caddr` that exposes parameter `param` of
-- the plugin in its slot `slot` (0-based), made if there isn't one.
function MD.expose(track, caddr, slot, param, find_only)
  local n = reaper.TrackFX_GetNumParams(track, caddr) or 0
  for i = 0, n - 1 do
    local fi = getn(track, caddr, ("param.%d.container_map.fx_index"):format(i))
    if fi == slot and getn(track, caddr, ("param.%d.container_map.fx_parm"):format(i)) == param then
      return i
    end
  end
  if find_only then return nil end
  return getn(track, caddr, ("container_map.add.%d.%d"):format(slot, param))
end

-- Where the link for parameter `param` of the plugin at `path` lives: the
-- top-level slot and the parameter there (exposed up through each
-- container above it).
function MD.top_of(track, path, param, find_only)
  local p = param
  for depth = #path, 2, -1 do
    local parent = {}
    for i = 1, depth - 1 do parent[i] = path[i] end
    local caddr = T.addr_of(track, parent)
    if not caddr then return nil end
    p = MD.expose(track, caddr, path[depth], p, find_only)
    if not p then return nil end
  end
  return path[1], p
end

-- What a top-level parameter is underneath: follows container_map down
-- to the plugin and parameter it exposes. Returns path, param.
function MD.resolve(track, slot, param)
  local path, p = { slot }, param
  for _ = 1, 8 do
    local addr = T.addr_of(track, path)
    if not addr then break end
    if not get(track, addr, "container_count") then break end
    local fi = getn(track, addr, ("param.%d.container_map.fx_index"):format(p))
    local fp = getn(track, addr, ("param.%d.container_map.fx_parm"):format(p))
    if not fi or not fp then break end
    path[#path + 1], p = fi, fp
  end
  return path, p
end

-- links["{guid}:7"] = { mod = <source>, out = k, slot, param (where the
--   link lives), path, tparam, tguid, sparam (the source parameter),
--   scale, offset, baseline, macro (bool), bipolar (bool) }
-- by_mod[guid] = { link, ... }
local cache = {}     -- track -> { stamp, at, res }
local SCAN_EVERY = 0.5

function MD.invalidate(track)
  if track then cache[track] = nil else cache = {} end
end

local function do_scan(track)
  local slot = MD.plugin(track)
  local list, macros, mods = build(track, slot)
  local res = { links = {}, by_mod = {}, list = list, macros = macros, mods = mods, slot = slot }
  if not slot then return res end
  local by_param = {}
  for _, src in ipairs(list) do
    res.by_mod[src.guid] = {}
    for k, p in ipairs(src.out) do by_param[p] = { src = src, k = k } end
    if src.outb then by_param[src.outb] = { src = src, k = 1, bipolar = true } end
  end
  local n = reaper.TrackFX_GetCount(track) or 0
  for s = 0, n - 1 do
    if s ~= slot then
      local pn = reaper.TrackFX_GetNumParams(track, s) or 0
      for p = 0, pn - 1 do
        if get(track, s, ("param.%d.plink.active"):format(p)) == "1"
           and getn(track, s, ("param.%d.plink.effect"):format(p)) == slot then
          local sp = getn(track, s, ("param.%d.plink.param"):format(p))
          local hit = sp and by_param[sp]
          if hit then
            local path, tp = MD.resolve(track, s, p)
            local taddr = T.addr_of(track, path)
            local tguid = taddr and reaper.TrackFX_GetFXGUID(track, taddr) or ""
            local l = {
              mod = hit.src, out = hit.k, slot = s, param = p, sparam = sp,
              path = path, tparam = tp, tguid = tguid,
              macro = hit.src.src == "macro", bipolar = hit.bipolar or false,
              scale = getn(track, s, ("param.%d.plink.scale"):format(p)) or 1,
              offset = getn(track, s, ("param.%d.plink.offset"):format(p)) or 0,
              baseline = getn(track, s, ("param.%d.mod.baseline"):format(p)) or 0,
            }
            res.links[tguid .. ":" .. tp] = l
            local t = res.by_mod[hit.src.guid]
            t[#t + 1] = l
          end
        end
      end
    end
  end
  return res
end

-- The track's sources and links, read again when the project has changed
-- (at most twice a second) or after our own edits.
function MD.scan(track)
  if not track then return { links = {}, by_mod = {}, list = {}, macros = {}, mods = {} } end
  local now = reaper.time_precise()
  local stamp = reaper.GetProjectStateChangeCount(0)
  local c = cache[track]
  if c and (c.stamp == stamp or now - c.at < SCAN_EVERY) then return c.res end
  local res = do_scan(track)
  cache[track] = { stamp = stamp, at = now, res = res }
  return res
end

function MD.find(track, guid)
  for _, src in ipairs(MD.scan(track).list) do if src.guid == guid then return src end end
  return nil
end

-- The link driving this plugin's parameter, or nil.
function MD.link_of(track, guid, param)
  return MD.scan(track).links[(guid or "") .. ":" .. param]
end

-- A source's value now, 0..1 (its output k, or a modulator's output).
function MD.value(track, src, k)
  if not src.slot then return 0 end
  return reaper.TrackFX_GetParamNormalized(track, src.slot, src.out[k or 1] or src.out[1]) or 0
end

-- A macro's two ends: where the control sits at 0% and at 100%.
function MD.range(l)
  return l.baseline, l.baseline + l.scale
end

-- Where a linked control's value can go, 0..1 at each end, for the ring.
-- A modulator's swing takes its Depth into account.
function MD.span(l, track)
  local a, b
  if l.macro then
    a, b = MD.range(l)
  else
    local d = 1
    if track and l.mod.slot then d = MD.field(track, l.mod.slot, l.mod.j, "depth") end
    local lo, hi
    if l.bipolar then lo, hi = 0.5 - d * 0.5, 0.5 + d * 0.5 else lo, hi = 0, d end
    a = l.baseline + l.scale * (lo + l.offset)
    b = l.baseline + l.scale * (hi + l.offset)
  end
  if a > b then a, b = b, a end
  return math.max(0, math.min(1, a)), math.max(0, math.min(1, b))
end

-- What a linked control's ring (or a fader's bar) shows, 0..1, reversed
-- when the control is: the span, where it is now, and the handles' ends
-- (a macro's range, a modulator's swing). For the web page.
function MD.ring_of(track, l, rev)
  local lo, hi = MD.span(l, track)
  local live = MD.live(track, l)
  local ends = l.macro and { MD.range(l) } or (MD.swing_ends(track, l))
  local out = {}
  for i, v in ipairs(ends) do
    v = math.max(0, math.min(1, v))
    out[i] = rev and (1 - v) or v
  end
  if rev then lo, hi, live = 1 - hi, 1 - lo, 1 - live end
  return lo, hi, live, out
end

-- The value the source gives the control right now (the live dot).
function MD.live(track, l)
  local v = reaper.TrackFX_GetParamNormalized(track, l.mod.slot, l.sparam) or 0
  return math.max(0, math.min(1, l.baseline + l.scale * (v + l.offset)))
end

local function write_link(track, s, p, base, scale, offset, slot, sp)
  -- ours replaces REAPER's own modulation on it: one source per control
  set(track, s, ("param.%d.lfo.active"):format(p), 0)
  set(track, s, ("param.%d.acs.active"):format(p), 0)
  set(track, s, ("param.%d.mod.active"):format(p), 1)
  set(track, s, ("param.%d.mod.baseline"):format(p), base)
  set(track, s, ("param.%d.plink.active"):format(p), 1)
  set(track, s, ("param.%d.plink.offset"):format(p), offset)
  set(track, s, ("param.%d.plink.scale"):format(p), scale)
  set(track, s, ("param.%d.plink.effect"):format(p), slot)
  set(track, s, ("param.%d.plink.param"):format(p), sp)
  set(track, s, ("param.%d.plink.midi_bus"):format(p), 0)
  set(track, s, ("param.%d.plink.midi_chan"):format(p), 0)
end

-- How far a modulator swings a control set at `v` by default: all the
-- way to whichever end has more room.
function MD.default_depth(v)
  if v <= 0.5 then return 1 - v end
  return -v
end

-- Whether a parameter is centre-oriented (pan, a ± gain): the plugin
-- shows a negative number at its bottom and not at its top.
function MD.is_centred(track, addr, param)
  local function txt(v)
    local ok, t = reaper.TrackFX_FormatParamValueNormalized(track, addr, param, v, "")
    return ok and t or ""
  end
  local lo, hi = txt(0), txt(1)
  local function neg(t)
    t = t:gsub("\u{2212}", "-")                    -- a typographic minus
    return t:match("^%s*%-%s*%.?%d") ~= nil          -- "-12 dB", "-.5"
        or t:match("^%s*%d+%.?%d*%s*%%?%s*L") ~= nil  -- "100L", "50% L" (pan)
  end
  return neg(lo) and not neg(hi)
end

-- How far a modulator swings a control set at `v` both ways by default:
-- as far as it can go each side.
function MD.default_depth_bi(v) return 2 * math.min(v, 1 - v) end

-- Links source `src` (output `k`) to parameter `param` of the plugin at
-- `path`, replacing whatever link it had (the caller asks first). A macro
-- takes the control over its whole range (drag the ring's ends to narrow
-- it); a modulator swings it from where it's set.
-- `centre`: the control is centre-oriented (its layout says bipolar, or
-- MD.is_centred), so a modulator swings it both ways round where it's set
-- rather than up from it.
function MD.link(track, src, k, path, param, centre)
  local s0 = MD.scan(track)
  local slot = s0.slot
  if not (slot and src) then return false end
  reaper.Undo_BeginBlock()
  local ts, tp = MD.top_of(track, path, param, false)
  local ok = false
  if ts then
    local taddr = T.addr_of(track, path)
    local now = (taddr and reaper.TrackFX_GetParamNormalized(track, taddr, param)) or 0
    local was = MD.link_of(track, taddr and reaper.TrackFX_GetFXGUID(track, taddr), param)
    if src.src == "macro" then
      write_link(track, ts, tp, 0, 1, 0, slot, src.out[k or 1] or src.out[1])
    else
      if centre == nil and taddr then centre = MD.is_centred(track, taddr, param) end
      local base, scale, bi = now, MD.default_depth(now), false
      if centre then scale, bi = MD.default_depth_bi(now), true end
      if was and not was.macro then base, scale, bi = was.baseline, was.scale, was.bipolar end
      write_link(track, ts, tp, base, scale, bi and -0.5 or 0, slot, bi and src.outb or src.out[1])
    end
    ok = true
  end
  reaper.Undo_EndBlock("ChannelView: link " .. (src.src == "macro" and "macro" or "modulator"), -1)
  MD.invalidate(track)
  return ok
end

-- Takes the link off. REAPER's own LFO or follower on the parameter, if
-- it has one, keeps its modulation on.
function MD.unlink(track, l, no_undo)
  if not no_undo then reaper.Undo_BeginBlock() end
  local s, p = l.slot, l.param
  -- the control stays where it is now
  local here = MD.live(track, l)
  set(track, s, ("param.%d.plink.active"):format(p), 0)
  set(track, s, ("param.%d.plink.effect"):format(p), -1)
  local own = get(track, s, ("param.%d.lfo.active"):format(p)) == "1"
           or get(track, s, ("param.%d.acs.active"):format(p)) == "1"
  if not own then
    set(track, s, ("param.%d.mod.active"):format(p), 0)
    reaper.TrackFX_SetParamNormalized(track, s, p, l.macro and here or l.baseline)
  end
  if not no_undo then reaper.Undo_EndBlock("ChannelView: remove link", -1) end
  MD.invalidate(track)
end

-- Sets a link's depth (its scale). `limit`: how far the scale may go (1
-- unless a swing end needs more -- see set_swing_end; REAPER keeps a
-- scale past 1). What REAPER keeps is read back into the link. No
-- rescan: the link is the scan's own, changed in place, and a drag calls
-- this every frame.
function MD.set_depth(track, l, scale, limit)
  limit = limit or 1
  scale = math.max(-limit, math.min(limit, scale))
  set(track, l.slot, ("param.%d.plink.scale"):format(l.param), scale)
  l.scale = getn(track, l.slot, ("param.%d.plink.scale"):format(l.param)) or scale
end

-- A modulator's swing on a control: where the control is with the
-- modulator at rest (end 1) and at full (end 2), as values (not clamped).
-- One way: baseline, and baseline + scale × Depth. Both ways: either
-- side of the baseline, half each. And the modulator's Depth.
function MD.swing_ends(track, l)
  local D = MD.field(track, l.mod.slot, l.mod.j, "depth")
  if l.bipolar then return { l.baseline - l.scale * D * 0.5, l.baseline + l.scale * D * 0.5 }, D end
  return { l.baseline, l.baseline + l.scale * D }, D
end

-- Drags end `e` of the swing to value v, the other end staying put: the
-- handles set the swing, as a macro's range ends do. They can cross (the
-- modulator then works the other way).
function MD.set_swing_end(track, l, e, v)
  local ends, D = MD.swing_ends(track, l)
  if D < 0.001 then return end
  ends[e] = math.max(0, math.min(1, v))
  local a, b = ends[1], ends[2]
  local base = l.bipolar and (a + b) * 0.5 or a
  MD.set_baseline(track, l, base)
  -- With the modulator's Depth under 100% the swing can only reach the
  -- whole range if the link scales past 1: allowed up to 1 / Depth.
  MD.set_depth(track, l, (b - a) / D, 1 / D)
end

-- Moves a link's whole swing (or a macro's range) by `d`, keeping its
-- width, inside 0..1: what turning a linked control does.
function MD.shift_link(track, l, d)
  if l.macro then return MD.shift_range(track, l, d) end
  local ends = MD.swing_ends(track, l)
  local lo, hi = math.min(ends[1], ends[2]), math.max(ends[1], ends[2])
  d = math.max(-lo, math.min(1 - hi, d))
  MD.set_baseline(track, l, l.baseline + d)
end

function MD.invert(track, l) MD.set_depth(track, l, -l.scale) end

-- Both ways round where it's set (the bipolar output, offset -0.5) or one
-- way from it (the plain output).
function MD.set_bipolar(track, l, on)
  if l.macro then return end
  local p = on and l.mod.outb or l.mod.out[1]
  set(track, l.slot, ("param.%d.plink.param"):format(l.param), p)
  set(track, l.slot, ("param.%d.plink.offset"):format(l.param), on and -0.5 or 0)
  l.offset, l.bipolar, l.sparam = on and -0.5 or 0, on, p
  MD.invalidate(track)
end
function MD.is_bipolar(l) return l.bipolar == true end

-- A modulated control's own value (where the knob sits) is its baseline.
function MD.set_baseline(track, l, v)
  v = math.max(0, math.min(1, v))
  set(track, l.slot, ("param.%d.mod.baseline"):format(l.param), v)
  l.baseline = v
end

-- A macro's range on a control: where it sits at 0% and at 100%.
function MD.set_range(track, l, from, to)
  from = math.max(0, math.min(1, from))
  to = math.max(0, math.min(1, to))
  set(track, l.slot, ("param.%d.mod.baseline"):format(l.param), from)
  set(track, l.slot, ("param.%d.plink.scale"):format(l.param), to - from)
  l.baseline, l.scale = from, to - from
end

-- Moves a macro's range by `d`, keeping its width, inside 0..1.
function MD.shift_range(track, l, d)
  local a, b = MD.range(l)
  local lo, hi = math.min(a, b), math.max(a, b)
  d = math.max(-lo, math.min(1 - hi, d))
  MD.set_range(track, l, a + d, b + d)
end

-- ---------------------------------------------------------------------
-- adding, changing, removing
-- ---------------------------------------------------------------------

local function free_macro(meta, two)
  local used = {}
  for i, m in pairs(meta) do
    used[i] = true
    if m.ctl == "xy" then used[i + 1] = true end
  end
  for i = 1, MD.NM - (two and 1 or 0) do
    if not used[i] and (not two or not used[i + 1]) then return i end
  end
  return nil
end

local function fresh_name(list, base)
  local taken = {}
  for _, s in ipairs(list) do taken[s.name] = true end
  if not taken[base] then return base end
  local n = 2
  while taken[base .. " " .. n] do n = n + 1 end
  return base .. " " .. n
end

-- Adds a macro shown as `ctl`. Returns its guid, or nil (all slots taken,
-- or the plugin couldn't be put on the track).
function MD.add_macro(track, ctl, ara_first)
  local meta = MD.read_macros(track)
  local i = free_macro(meta, ctl == "xy")
  if not i then return nil end
  reaper.Undo_BeginBlock()
  local slot = MD.ensure(track, ara_first)
  local guid
  if slot then
    local list = build(track, slot)
    meta[i] = { ctl = ctl, name = fresh_name(list, ctl == "xy" and "XY" or "Macro"),
                col = MD.COLOURS[(i - 1) % #MD.COLOURS + 1],
                choices = ctl == "dropdown" and { "1", "2", "3" } or nil }
    reaper.TrackFX_SetParamNormalized(track, slot, i - 1, 0)
    if ctl == "xy" then reaper.TrackFX_SetParamNormalized(track, slot, i, 0) end
    MD.write_macros(track, meta)
    guid = "m" .. i
  end
  reaper.Undo_EndBlock("ChannelView: add macro", -1)
  MD.invalidate(track)
  return guid
end

-- Adds a modulator of `kind` ("lfo", "follower", "midi"), every field at
-- its default.
function MD.add_mod(track, kind, ara_first)
  local t = KIND_TYPE[kind]
  if not (track and t) then return nil end
  local slot0 = MD.plugin(track)
  local j
  for jj = 1, MD.NO do
    local busy = slot0 and math.floor((reaper.TrackFX_GetParam(track, slot0, MD.param(jj, "type")) or 0) + 0.5) ~= 0
    if not busy then j = jj break end
  end
  if not j then return nil end
  reaper.Undo_BeginBlock()
  local slot = MD.ensure(track, ara_first)
  local guid
  if slot then
    local list = build(track, slot)
    for _, f in ipairs(MD.FIELDS) do
      if f[1] ~= "out" and f[1] ~= "outb" then MD.set_field(track, slot, j, f[1], f[2]) end
    end
    MD.set_field(track, slot, j, "type", t)
    local mods = MD.read_mods(track)
    mods[j] = { name = fresh_name(list, MD.KIND_NAME[kind]), col = KIND_COL[kind] }
    -- another of the same kind: the next colour along
    for _, s in ipairs(list) do
      if s.src == "mod" and s.col == mods[j].col then
        mods[j].col = MD.COLOURS[(j + 3) % #MD.COLOURS + 1]
        break
      end
    end
    MD.write_mods(track, mods)
    guid = "o" .. j
  end
  reaper.Undo_EndBlock("ChannelView: add modulator", -1)
  MD.invalidate(track)
  return guid
end

function MD.rename(track, src, name)
  name = clean(name)
  if src.src == "macro" then
    local meta = MD.read_macros(track)
    if meta[src.i] then meta[src.i].name = name; MD.write_macros(track, meta) end
  else
    local mods = MD.read_mods(track)
    mods[src.j] = mods[src.j] or {}
    mods[src.j].name = name
    MD.write_mods(track, mods)
  end
end

function MD.set_colour(track, src, col)
  if src.src == "macro" then
    local meta = MD.read_macros(track)
    if meta[src.i] then meta[src.i].col = col; MD.write_macros(track, meta) end
  else
    local mods = MD.read_mods(track)
    mods[src.j] = mods[src.j] or {}
    mods[src.j].col = col
    MD.write_mods(track, mods)
  end
end

-- A macro shown as another control type. To an XY pad it needs the next
-- slot free (false if not); from one, the Y slot's links go and it frees.
function MD.set_ctl(track, src, ctl)
  local meta = MD.read_macros(track)
  local m = meta[src.i]
  if not m or m.ctl == ctl then return true end
  if ctl == "xy" then
    if src.i >= MD.NM or meta[src.i + 1] then return false end
  end
  reaper.Undo_BeginBlock()
  if m.ctl == "xy" then
    local s = MD.scan(track)
    for _, l in ipairs(s.by_mod[src.guid] or {}) do
      if l.out == 2 then MD.unlink(track, l, true) end
    end
  end
  m.ctl = ctl
  if ctl == "dropdown" and not (m.choices and #m.choices >= 2) then m.choices = { "1", "2", "3" } end
  if ctl ~= "dropdown" then m.choices = nil end
  MD.write_macros(track, meta)
  -- a button or a dropdown sits on one of its own values
  if ctl == "button" or ctl == "dropdown" then
    local v = MD.value(track, src, 1)
    local n = ctl == "button" and 2 or #m.choices
    reaper.TrackFX_SetParamNormalized(track, src.slot, src.i - 1, math.floor(v * (n - 1) + 0.5) / (n - 1))
  end
  reaper.Undo_EndBlock("ChannelView: macro control type", -1)
  return true
end

function MD.set_choices(track, src, choices)
  local meta = MD.read_macros(track)
  local m = meta[src.i]
  if not m then return end
  local n = math.max(2, math.min(8, #choices))
  local out = {}
  for k = 1, n do out[k] = clean(choices[k] or tostring(k)) end
  m.choices = out
  MD.write_macros(track, meta)
end

-- A dropdown's current choice (1-based) and the macro value of choice c.
function MD.choice_of(v, n) return math.floor(v * (n - 1) + 0.5) + 1 end
function MD.choice_value(c, n) return (c - 1) / (n - 1) end

-- A macro's value (output k), 0..1.
function MD.set_macro(track, src, k, v)
  local p = src.out[k or 1]
  if p and src.slot then
    reaper.TrackFX_SetParamNormalized(track, src.slot, p, math.max(0, math.min(1, v)))
    hold_baseline(track, src.slot, p, v)
    follow_flat_lane(track, src.slot, p, v)
  end
end

-- The choices a stepped parameter offers (2 to 8 of them), as the plugin
-- names them, for a dropdown macro dropped on it. nil when it isn't.
function MD.steps_of(track, addr, param)
  local ok, step, _, _, istoggle = reaper.TrackFX_GetParameterStepSizes(track, addr, param)
  local n
  if istoggle then
    n = 2
  elseif ok and step and step > 0 then
    local _, mn, mx = reaper.TrackFX_GetParam(track, addr, param)
    if mn and mx and mx > mn then n = math.floor((mx - mn) / step + 0.5) + 1 end
  end
  if not n or n < 2 or n > 8 then return nil end
  local names = {}
  for k = 1, n do
    local _, s = reaper.TrackFX_FormatParamValueNormalized(track, addr, param, (k - 1) / (n - 1), "")
    names[k] = (s and s ~= "") and s or tostring(k)
  end
  return names
end

-- Does the plugin have automation (or a lane) of its own?
local function has_envelopes(track, slot)
  local n = reaper.TrackFX_GetNumParams(track, slot) or 0
  for p = 0, n - 1 do
    if reaper.GetFXEnvelope(track, slot, p, false) then return true end
  end
  return false
end

-- ---------------------------------------------------------------------
-- THE MATRIX: a modulator's settings moved by a macro or another
-- modulator (TS_CV_Modulators.jsfx's own)
-- ---------------------------------------------------------------------
--   Per modulator two slots, each three parameters after the 192 above:
--   source (1-16 Macro, 17-24 Modulator), target (MD.MX_TARGETS' code,
--   + 100 x the macro's choices for a switch), amount (a share of the
--   setting's knob range, -1..1; a switch: its setting by choice, one
--   decimal digit each, 0 = its own). Worked out inside the plugin.

MD.MX_BASE = MD.NM + MD.NO * MD.PER          -- 192
MD.MX_SLOTS = 2
MD.MX_TARGETS = {
  { key = "depth", label = "Depth" },  { key = "rate", label = "Rate" },
  { key = "phase", label = "Phase" },  { key = "smooth", label = "Smooth" },
  { key = "att", label = "Attack" },   { key = "rel", label = "Release" },
  { key = "floor", label = "Floor" },  { key = "ceil", label = "Ceiling" },
  { key = "mlo", label = "Low note" }, { key = "mhi", label = "High note" },
  { key = "shape", label = "Shape", n = 6 }, { key = "sync", label = "Sync", n = 2 },
  { key = "fsrc", label = "Source", n = 2 }, { key = "gate", label = "Gate", n = 2 },
  { key = "mhold", label = "Hold", n = 2 },
}
MD.MX_CODE = {}
for c, t in ipairs(MD.MX_TARGETS) do MD.MX_CODE[t.key] = c; t.code = c end
MD.MX_CODE.rsync, MD.MX_CODE.rhz = 2, 2      -- either Rate knob is "rate"
MD.MX_MAX_CHOICES = 6

function MD.mx_param(j, sl, k) return MD.MX_BASE + (j - 1) * MD.MX_SLOTS * 3 + (sl - 1) * 3 + k end

-- Does the plugin on this track have the matrix? An older copy saved in
-- a project may not have its parameters.
function MD.mx_ok(track, slot)
  return slot ~= nil and (reaper.TrackFX_GetNumParams(track, slot) or 0) >= MD.MX_BASE + MD.NO * MD.MX_SLOTS * 3
end

-- ---------------------------------------------------------------------
-- bypass
-- ---------------------------------------------------------------------
-- The plugin's parameter after the matrix holds every modulator at rest
-- (the controls they drive sit where they're set), and one per modulator
-- holds that one: to hear the track with and without its movement.
-- Macros carry on. Parameters, so they can be automated or mapped.
MD.BYPASS = MD.MX_BASE + MD.NO * MD.MX_SLOTS * 3
function MD.bypass_param(j) return MD.BYPASS + (j or 0) end

-- Whether the plugin on this track has them (an older copy may not).
function MD.bypass_ok(track, slot)
  return slot ~= nil and (reaper.TrackFX_GetNumParams(track, slot) or 0) > MD.BYPASS + MD.NO
end

-- Whether all (j nil) or modulator j alone is bypassed.
function MD.bypassed(track, slot, j)
  if not MD.bypass_ok(track, slot) then return false end
  local p = (j == nil) and MD.BYPASS or MD.bypass_param(j)
  return (reaper.TrackFX_GetParam(track, slot, p) or 0) >= 0.5
end

-- Bypasses all (j nil) or modulator j, or (on false) lets it move again.
function MD.set_bypass(track, slot, j, on)
  if not MD.bypass_ok(track, slot) then return false end
  reaper.TrackFX_SetParam(track, slot, MD.bypass_param(j), on and 1 or 0)
  return true
end

-- A source's code, and back: macro i -> i, modulator j -> 16 + j. An XY
-- pad's second macro is i + 1.
function MD.mx_code_of(src, k)
  if src.src == "macro" then return src.i + ((k or 1) - 1) end
  return MD.NM + src.j
end
function MD.mx_source(track, code)
  if code <= MD.NM then
    local src = MD.find(track, "m" .. code)
    if src then return src, 1 end
    src = MD.find(track, "m" .. (code - 1))
    if src and src.kind == "xy" then return src, 2 end
    return nil
  end
  return MD.find(track, "o" .. (code - MD.NM))
end

-- Modulator j's slots: { [sl] = { sl, code, tg (MD.MX_TARGETS entry),
-- nch, amt } } -- empty ones left out.
function MD.mx_get(track, slot, j)
  local out = {}
  if not MD.mx_ok(track, slot) then return out end
  for sl = 1, MD.MX_SLOTS do
    local code = math.floor((reaper.TrackFX_GetParam(track, slot, MD.mx_param(j, sl, 0)) or 0) + 0.5)
    local tgr = math.floor((reaper.TrackFX_GetParam(track, slot, MD.mx_param(j, sl, 1)) or 0) + 0.5)
    local tg = MD.MX_TARGETS[tgr % 100]
    if code >= 1 and tg then
      out[sl] = { sl = sl, code = code, tg = tg, nch = tgr // 100,
                  amt = reaper.TrackFX_GetParam(track, slot, MD.mx_param(j, sl, 2)) or 0 }
    end
  end
  return out
end

local function mx_write(track, slot, j, sl, code, tgr, amt)
  reaper.TrackFX_SetParam(track, slot, MD.mx_param(j, sl, 0), code)
  reaper.TrackFX_SetParam(track, slot, MD.mx_param(j, sl, 1), tgr)
  reaper.TrackFX_SetParam(track, slot, MD.mx_param(j, sl, 2), amt)
end

-- A switch's settings by choice, packed: digit c-1 = setting + 1 (0 its own).
function MD.mx_pack(map, n)
  local v = 0
  for c = math.min(n, MD.MX_MAX_CHOICES), 1, -1 do v = v * 10 + (map[c] and (map[c] + 1) or 0) end
  return v
end
function MD.mx_unpack(amt, n)
  local map, v = {}, math.floor(math.max(0, amt) + 0.5)
  for c = 1, math.min(n, MD.MX_MAX_CHOICES) do
    local d = v % 10
    v = v // 10
    if d > 0 then map[c] = d - 1 end
  end
  return map
end

-- Can `from` (a source, its output k) move modulator `to`'s `key`?
-- Returns true, or false and why not.
function MD.mx_can(track, to, key, from, k)
  local tg = MD.MX_TARGETS[MD.MX_CODE[key] or 0]
  if not tg then return false, "Can't be moved" end
  if from.src == "mod" and from.j == to.j then return false, "Can't move itself" end
  if tg.n and not (from.src == "macro" and (from.kind == "button" or from.kind == "dropdown")) then
    return false, "Switches: button or dropdown macros only"
  end
  local code = MD.mx_code_of(from, k)
  local used = MD.mx_get(track, to.slot, to.j)
  local free = false
  for sl = 1, MD.MX_SLOTS do
    if not used[sl] or (used[sl].code == code and used[sl].tg == tg) then free = true end
  end
  if not free then return false, ("%s is moved by two already"):format(to.name) end
  return true
end

-- Links `from` to modulator `to`'s `key`. `setting` is the switch's
-- setting for a button's on (or a dropdown's second choice). Returns
-- true, or false and why not.
function MD.mx_link(track, to, key, from, k, setting)
  local ok, why = MD.mx_can(track, to, key, from, k)
  if not ok then return false, why end
  local tg = MD.MX_TARGETS[MD.MX_CODE[key]]
  local code = MD.mx_code_of(from, k)
  local used = MD.mx_get(track, to.slot, to.j)
  local sl
  for i = 1, MD.MX_SLOTS do
    if used[i] and used[i].code == code and used[i].tg == tg then sl = i end
  end
  if not sl then for i = MD.MX_SLOTS, 1, -1 do if not used[i] then sl = i end end end
  local tgr, amt = tg.code, 0.5
  if tg.n then
    local n = from.kind == "dropdown" and math.max(2, #(from.choices or {})) or 2
    n = math.min(n, MD.MX_MAX_CHOICES)
    tgr = tg.code + 100 * n
    amt = MD.mx_pack({ [2] = setting or 0 }, n)
  end
  reaper.Undo_BeginBlock()
  mx_write(track, to.slot, to.j, sl, code, tgr, amt)
  reaper.Undo_EndBlock(("ChannelView: %s moves %s %s"):format(from.name, to.name, tg.label), -1)
  return true
end

-- A switch's settings, by name.
function MD.mx_names(key)
  if key == "shape" then return MD.SHAPES end
  if key == "sync" then return { "Free", "Sync" } end
  if key == "fsrc" then return { "Track", "Sidechain" } end
  return { "Off", "On" }
end

-- A dropdown macro on a switch, choice by choice: choice c picks the
-- switch's setting c (its choices are the switch's names). Rewrites the
-- slot from `from` to `to`'s `key`.
function MD.mx_direct(track, to, key, from, k)
  local tg = MD.MX_TARGETS[MD.MX_CODE[key]]
  local code = MD.mx_code_of(from, k)
  local n = math.min(#MD.mx_names(key), MD.MX_MAX_CHOICES)
  for sl, e in pairs(MD.mx_get(track, to.slot, to.j)) do
    if e.code == code and e.tg == tg then
      local map = {}
      for c = 1, n do map[c] = c - 1 end
      mx_write(track, to.slot, to.j, sl, code, tg.code + 100 * n, MD.mx_pack(map, n))
      return true
    end
  end
  return false
end

function MD.mx_set_amount(track, to, sl, amt)
  reaper.TrackFX_SetParam(track, to.slot, MD.mx_param(to.j, sl, 2), amt)
end

function MD.mx_unlink(track, to, sl, no_undo)
  if not no_undo then reaper.Undo_BeginBlock() end
  mx_write(track, to.slot, to.j, sl, 0, 0, 0)
  if not no_undo then reaper.Undo_EndBlock("ChannelView: unlink a modulator setting", -1) end
end

-- Every slot that a source feeds, or that belongs to modulator j, cleared
-- (a macro or modulator being removed).
local function mx_forget(track, slot, src)
  if not MD.mx_ok(track, slot) then return end
  local codes = {}
  if src.src == "macro" then
    codes[src.i] = true
    if src.kind == "xy" then codes[src.i + 1] = true end
  else
    codes[MD.NM + src.j] = true
  end
  for j = 1, MD.NO do
    for sl, e in pairs(MD.mx_get(track, slot, j)) do
      if codes[e.code] or (src.src == "mod" and j == src.j) then mx_write(track, slot, j, sl, 0, 0, 0) end
    end
  end
end

-- Removes a macro or modulator and every link from it. The plugin goes
-- too when nothing's left on it (and it has no automation).
function MD.remove(track, src)
  local s = MD.scan(track)
  local slot = s.slot
  if not slot then return end
  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)
  for _, l in ipairs(s.by_mod[src.guid] or {}) do MD.unlink(track, l, true) end
  mx_forget(track, slot, src)
  if src.src == "macro" then
    local meta = MD.read_macros(track)
    meta[src.i] = nil
    MD.write_macros(track, meta)
    for _, p in ipairs(src.out) do reaper.TrackFX_SetParamNormalized(track, slot, p, 0) end
  else
    MD.set_field(track, slot, src.j, "type", 0)
    local mods = MD.read_mods(track)
    mods[src.j] = nil
    MD.write_mods(track, mods)
  end
  MD.invalidate(track)
  local left = build(track, slot)
  if #left == 0 and not has_envelopes(track, slot) then
    reaper.TrackFX_Delete(track, slot)
    reaper.GetSetMediaTrackInfo_String(track, MD.EXT_MACROS, "", true)
    reaper.GetSetMediaTrackInfo_String(track, MD.EXT_MODS, "", true)
  end
  reaper.PreventUIRefresh(-1)
  reaper.Undo_EndBlock("ChannelView: remove " .. (src.src == "macro" and "macro" or "modulator"), -1)
  MD.invalidate(track)
end

-- A follower listening to the sidechain needs the track to carry 3/4.
function MD.need_sidechain(track)
  if (reaper.GetMediaTrackInfo_Value(track, "I_NCHAN") or 2) < 4 then
    reaper.SetMediaTrackInfo_Value(track, "I_NCHAN", 4)
  end
end

-- ---------------------------------------------------------------------
-- automation lanes
-- ---------------------------------------------------------------------

-- A parameter's lane: nil when there's none; else env, shown, has
-- automation (points beyond the first, or an automation item).
function MD.lane(track, slot, param)
  if not (track and slot) then return nil end
  return require("TS_CV_Envelopes").fx_lane(track, slot, param)
end

-- Takes a parameter's lane away altogether: the envelope and its
-- automation. Returns true when it went.
function MD.remove_lane(track, slot, param)
  local l = MD.lane(track, slot, param)
  if not l then return false end
  return require("TS_CV_Envelopes").remove(track, l.env)
end

-- Click on a lane button: make the lane (shown) if there isn't one, show
-- it if it's hidden, hide it if it's showing.
function MD.toggle_lane(track, slot, param)
  if not (track and slot) then return end
  require("TS_CV_Envelopes").toggle_fx_lane(track, slot, param)
end

-- ---------------------------------------------------------------------
-- the plugin row leaves ours out
-- ---------------------------------------------------------------------

-- T.collect's list without ChannelView Modulators.
function MD.strip(track, list)
  local m = MD.plugin(track)
  if not m then return list end
  return T.without(list, function(slot) return slot == m end)
end

return MD
