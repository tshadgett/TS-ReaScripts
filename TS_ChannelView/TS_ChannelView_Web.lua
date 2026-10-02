-- @noindex
-- Not a package of its own: installed by TS_ChannelView.lua's @provides.
--[[
  TS_ChannelView_Web.lua -- the bridge between REAPER and ChannelView's web
  page (TS_ChannelView.html), for a tablet beside the desk.

  REAPER's own web interface (Preferences > Control/OSC/web > Add > Web
  browser interface) serves the page and answers its transport, action and
  ExtState requests by itself. What it cannot do is reach a plugin's
  parameters -- so this script does: it runs in the background, publishes
  the selected track's chain as ChannelView lays it out (your saved layouts,
  styles and faceplates, the theme's colours), and applies whatever the page
  sends back. Everything passes through ExtState section TS_CV_WEB:

    layout   JSON, rewritten only when something structural changes: the
             tracks, the selected track's plugins and their panels, the
             palette. Numbered, so the page refetches only when it moves.
    vals     JSON, every cycle that anything moved: parameter values and
             their text, the channel strip, meters, the layout's number and
             the last command applied.
    cmd      written by the page: "seq|verb|arg|arg~seq|verb|...". Every
             command not yet applied is resent until "vals" acknowledges it,
             so a burst of knob moves can't lose one between two reads.
    found    the answer to an action search, for the macro editor.
    macros   (persistent) the page's macro buttons; the page reads and
             writes it itself, this script never touches it.
    alive    a counter, bumped every cycle: the page says so when it stops.

  It needs nothing from ChannelView's window and runs whether that is open
  or not. Run it once, or from REAPER's startup (__startup.lua).
--]]

local script_dir = debug.getinfo(1, "S").source:match("@?(.*[\\/])") or ""
package.path = script_dir .. "?.lua;" .. package.path

local C  = require("TS_CV_Config")
local U  = require("TS_CV_Util")
local M  = require("TS_CV_Mappings")
local T  = require("TS_CV_FXTree")
local St = require("TS_CV_State")
local SC = require("TS_CV_Steps")
local TP = require("TS_CV_Taps")
local RQ = require("TS_CV_ReaEQ")
local IX = require("TS_CV_FXIndex")
local Tr = require("TS_CV_Trace")
local G  = require("TS_CV_Gang")
local SR = require("TS_CV_Search")

local NS = "TS_CV_WEB"

M.init(script_dir)
SC.init(script_dir)

-- ---------------------------------------------------------------------
-- the palette: the same Hue/Tint every TS_ tool shares
-- ---------------------------------------------------------------------
local function pal_get()
  local h = reaper.GetExtState("TS_Palette", "base_hue")
  local t = reaper.GetExtState("TS_Palette", "tint")
  if h == "" then h = reaper.GetExtState("TS_ChannelView", "base_hue") end
  if t == "" then t = reaper.GetExtState("TS_ChannelView", "tint") end
  return tonumber(h), tonumber(t)
end
do
  local h, t = pal_get()
  C.BASE_HUE = h or C.BASE_HUE
  C.TINT     = t or C.TINT
  C.build_palette()
end

-- ImGui's 0xRRGGBBAA to CSS.
local function hex(col)
  if not col then return nil end
  return string.format("#%06x", (col >> 8) & 0xffffff)
end

local PAL_KEYS = { "win_bg", "panel_bg", "panel_border", "header_bg", "header_bg_byp",
  "header_text", "header_dim", "label", "value", "knob_track", "knob_fill",
  "knob_fill_bi", "knob_body", "knob_pointer", "knob_ring", "toggle_off", "toggle_on",
  "toggle_text", "accent", "strip_bg", "strip_sel", "gr_measured", "fader_cap",
  "bypass_on", "mute_on", "solo_on", "rec_on", "level_lo", "level_clip", "level_over",
  "empty_text", "warn", "mon_on", "mon_auto", "eq_spectrum" }

local function palette()
  local out = {}
  for _, k in ipairs(PAL_KEYS) do out[k] = hex(C.COL[k]) end
  return out
end

-- ---------------------------------------------------------------------
-- JSON, just enough of it
-- ---------------------------------------------------------------------
local function jstr(s)
  return '"' .. tostring(s):gsub('[%c"\\]', function(c)
    if c == '"' then return '\\"' elseif c == "\\" then return "\\\\"
    elseif c == "\n" then return "\\n" elseif c == "\t" then return "\\t" end
    return string.format("\\u%04x", c:byte())
  end) .. '"'
end

local function json(v)
  local t = type(v)
  if t == "nil" then return "null" end
  if t == "boolean" then return v and "true" or "false" end
  if t == "number" then
    if v ~= v or v == math.huge or v == -math.huge then return "0" end
    if math.type and math.type(v) == "integer" then return tostring(v) end
    return string.format("%.5g", v)
  end
  if t == "string" then return jstr(v) end
  -- an array when it has a [1] or is marked empty-array
  if v[1] ~= nil or getmetatable(v) == "array" then
    local parts = {}
    for i = 1, #v do parts[i] = json(v[i]) end
    return "[" .. table.concat(parts, ",") .. "]"
  end
  local parts = {}
  for k, x in pairs(v) do
    if x ~= nil then parts[#parts + 1] = jstr(k) .. ":" .. json(x) end
  end
  table.sort(parts)   -- stable output, so "unchanged" compares equal
  return "{" .. table.concat(parts, ",") .. "}"
end
local function arr(t) return setmetatable(t or {}, { __metatable = "array" }) end

-- ---------------------------------------------------------------------
-- the selected track and its chain
-- ---------------------------------------------------------------------
local track = nil
local chain = {}

local function valid(tr) return tr ~= nil and reaper.ValidatePtr2(0, tr, "MediaTrack*") end

local function current_track()
  local tr = reaper.GetSelectedTrack2(0, 0, true)
  if tr then return tr end
  if valid(track) then return track end
  return reaper.GetTrack(0, 0)
end

local function fx_by_guid(guid)
  for _, fx in ipairs(chain) do if fx.guid == guid then return fx end end
  return nil
end

local function track_colour(tr)
  local c = reaper.GetMediaTrackInfo_Value(tr, "I_CUSTOMCOLOR")
  if not c or c == 0 then return nil end
  local r, g, b = reaper.ColorFromNative(math.floor(c) & 0xffffff)
  return string.format("#%02x%02x%02x", r, g, b)
end

local function track_name(tr)
  if tr == reaper.GetMasterTrack(0) then return "MASTER" end
  local _, n = reaper.GetTrackName(tr)
  return n or ""
end

local function round(v, places)
  local m = 10 ^ (places or 4)
  return math.floor(v * m + 0.5) / m
end

-- ---------------------------------------------------------------------
-- the layout
-- ---------------------------------------------------------------------
-- The choices of a stepped parameter, by name: ChannelView's own cache of
-- them where it has one, otherwise formatted here without touching the
-- parameter. Kept per plugin instance until the chain changes.
local choice_cache = {}

-- Returns two lists: the names, and each one's normalised position (cached
-- lists can skip positions, so the page mustn't assume even spacing).
local function choices(fx, key, p)
  local ck = fx.guid .. ":" .. p
  local c = choice_cache[ck]
  if c ~= nil then
    if not c then return nil end
    return c.names, c.norms
  end
  c = false
  local ok, step = reaper.TrackFX_GetParameterStepSizes(track, fx.addr, p)
  if ok and step and step > 0 then
    local n = math.floor(1 / step + 0.5) + 1
    if n >= 2 and n <= 64 then
      local cached = SC.get and SC.get(key, p, step)
      local names, norms = arr(), arr()
      if type(cached) == "table" and #cached > 0 then
        -- TS_CV_Steps entries are { norm = , text = }
        for i, e in ipairs(cached) do
          if type(e) == "table" then
            names[i] = tostring(e.text or e.name or e[1] or i)
            norms[i] = round(tonumber(e.norm) or (i - 1) * step)
          else
            names[i] = tostring(e)
            norms[i] = round((i - 1) * step)
          end
        end
      elseif reaper.TrackFX_FormatParamValueNormalized then
        for i = 0, n - 1 do
          local v = i / (n - 1)
          local _, s = reaper.TrackFX_FormatParamValueNormalized(track, fx.addr, p, v, "")
          names[i + 1] = (s and s ~= "") and s or tostring(i)
          norms[i + 1] = round(v)
        end
      end
      if #names > 0 then c = { names = names, norms = norms } end
    end
  end
  choice_cache[ck] = c
  if not c then return nil end
  return c.names, c.norms
end

-- The picker's format chips, in the same colours as the desktop's badges.
local function format_cols()
  local out = {}
  for k, c in pairs(C.FORMAT_COL or {}) do out[k] = { bg = hex(c.bg), fg = hex(c.fg) } end
  return out
end

local function cap_hex(key)
  local cp = key and C.CAP[key]
  if not cp then return nil end
  return hex(cp.col or C.COL.knob_fill)
end

local function plate_json(key)
  local pl = C.plate_of(key)
  if not pl then return nil end
  return { bg = hex(pl.bg), head = hex(pl.head), text = hex(pl.text), dim = hex(pl.dim),
           tick = hex(pl.tick), border = hex(pl.border), brushed = pl.brushed or nil,
           sheen = pl.sheen or 1 }
end

local function panel_of(fx, i)
  local key = U.plugin_key(fx.name)
  local layout, is_default = M.get_or_default(key, track, fx.addr, fx.guid)
  local nparams = reaper.TrackFX_GetNumParams(track, fx.addr)
  local ctls = arr()
  for _, ctl in ipairs(layout.controls or {}) do
    local o = { t = ctl.type or "knob" }
    if ctl.param and ctl.param >= 0 and ctl.param < nparams
       and o.t ~= "blank" and o.t ~= "divider" and o.t ~= "half_gap" then
      local _, pname = reaper.TrackFX_GetParamName(track, fx.addr, ctl.param, "")
      o.p   = ctl.param
      o.l   = M.display_name(key, ctl.param, ctl.label, pname, ctl.live or layout.live)
      o.bi  = ctl.bipolar or nil
      o.inv = (ctl.invert and (o.t == "knob" or o.t == "toggle" or o.t == "stepped")) or nil
      o.st  = ctl.style
      o.cap = cap_hex(ctl.cap)
      if o.t == "combo" or o.t == "stepped" then o.ch, o.cn = choices(fx, key, ctl.param) end
    elseif o.t == "divider" then
      o.nr = ctl.no_rule or nil
    elseif o.t ~= "blank" and o.t ~= "half_gap" then
      o.t = "missing"
    end
    ctls[#ctls + 1] = o
  end
  local meter = M.meter_of(layout)
  local has_gr = meter and T.reports_gr(track, fx.addr, fx.guid) or false
  return {
    g = fx.guid, i = i, n = U.clean_fx_name(fx.name), k = key, d = is_default or nil,
    ti = fx.is_top_level and fx.top_index or nil,
    c = ctls, plate = plate_json(layout.plate),
    gr = has_gr and (meter.range or C.MAX_GR_DB) or nil,
    gw = has_gr and (meter.win or C.GRV_DEFAULT) or nil,
    eq = (key == "ReaEQ") or nil,
  }
end

-- ---------------------------------------------------------------------
-- ReaEQ -- TS_CV_ReaEQ's reading and writing, the canvas drawn by the page
-- ---------------------------------------------------------------------
-- Frequency takes real Hz. Gain and Q don't: ReaEQ only honours normalised
-- writes for them, with no stated mapping, so a target is reached by
-- writing, reading back and correcting, a step per cycle, exactly as the
-- desktop canvas does while you drag (RQ.set_gain / RQ.set_q). A job per
-- band and parameter carries that state; a new target from the page just
-- moves the job's goal, so a drag converges as it goes.
local eq_jobs = {}
local eq_reads = {}      -- guid -> { bands, master }, read once per cycle

local function eq_read(fx)
  local r = eq_reads[fx.guid]
  if not r then
    local bands, master = RQ.read(track, fx.addr)
    r = { bands = bands, master = master }
    eq_reads[fx.guid] = r
  end
  return r
end

local function eq_band(fx, bt, bi)
  for _, b in ipairs(eq_read(fx).bands) do
    if b.bandtype == bt and b.bandidx == bi then return b end
  end
  return nil
end

local function eq_target(guid, bt, bi, pt, target)
  local k = guid .. ":" .. bt .. ":" .. bi .. ":" .. pt
  local j = eq_jobs[k]
  if not j then
    j = { guid = guid, bt = bt, bi = bi, pt = pt, state = {}, n = 0 }
    eq_jobs[k] = j
  end
  j.target, j.n = target, 0
end

local HAS_GAIN = { [1] = true, [2] = true, [4] = true }

local function eq_step()
  for k, j in pairs(eq_jobs) do
    local fx = fx_by_guid(j.guid)
    local b = fx and eq_band(fx, j.bt, j.bi)
    j.n = j.n + 1
    if not b then
      if j.n > 90 then eq_jobs[k] = nil end
    else
      local v = (j.pt == 1) and b.gain or b.q
      local tol = (j.pt == 1) and 0.1 or 0.02
      if v and v == v and math.abs(v - j.target) <= tol then
        eq_jobs[k] = nil
      elseif j.n > 120 then
        eq_jobs[k] = nil                      -- best effort stands
      elseif j.pt == 1 then
        RQ.set_gain(track, fx.addr, b, j.target, j.state)
      else
        RQ.set_q(track, fx.addr, b, j.target, j.state)
      end
    end
  end
end

local function eq_vals(fx)
  local r = eq_read(fx)
  local out = arr()
  for _, b in ipairs(r.bands) do
    local g = b.gain or 0
    if g ~= g then g = 0 end
    out[#out + 1] = { t = b.bandtype, i = b.bandidx, f = round(b.freq or 1000, 1),
                      g = round(math.max(-60, math.min(60, g)), 2), q = round(b.q or 1, 3),
                      e = b.enabled or nil }
  end
  local m = r.master and r.master.val or 0
  if m ~= m or m == -math.huge then m = -60 end
  return { b = out, m = round(m, 2) }
end

-- ---------------------------------------------------------------------
-- sends and receives -- TS_CV_Sends' rules, without its window
-- ---------------------------------------------------------------------
-- cat 0 is a send on this track, -1 a receive: the same REAPER object seen
-- from the other end. Modes as on the desktop: direct (channels 1/2),
-- sidechain (3/4, widening the receiving track) and MIDI (all channels,
-- no audio). I_SENDMODE 0 is post-fader, 3 pre-fader.
local POST, PRE, MIDI_OFF = 0, 3, 31
local OTHER = { [0] = "P_DESTTRACK", [-1] = "P_SRCTRACK" }

local function mode_of(src, dst, mf)
  if (src or 0) < 0 and ((mf or 0) & 31) ~= MIDI_OFF then return "midi" end
  if (dst or 0) >= 2 then return "sidechain" end
  return "direct"
end

local function sget(cat, i, k) return reaper.GetTrackSendInfo_Value(track, cat, i, k) or 0 end

local function send_mode(cat, i)
  return mode_of(math.floor(sget(cat, i, "I_SRCCHAN")), math.floor(sget(cat, i, "I_DSTCHAN")),
                 math.floor(sget(cat, i, "I_MIDIFLAGS")))
end

local function apply_mode(get, set, dst, mode)
  if mode == "midi" then
    set("I_SRCCHAN", -1); set("I_MIDIFLAGS", 0)
    return
  end
  if (get("I_SRCCHAN") or 0) < 0 then
    set("I_SRCCHAN", 0)
    set("I_MIDIFLAGS", (math.floor(get("I_MIDIFLAGS") or 0) & ~31) | MIDI_OFF)
  end
  if mode == "sidechain" and dst and (reaper.GetMediaTrackInfo_Value(dst, "I_NCHAN") or 2) < 4 then
    reaper.SetMediaTrackInfo_Value(dst, "I_NCHAN", 4)
  end
  set("I_DSTCHAN", mode == "sidechain" and 2 or 0)
end

local function sends_layout(cat)
  local out = arr()
  if not track then return out end
  for i = 0, (reaper.GetTrackNumSends(track, cat) or 0) - 1 do
    local other = reaper.GetTrackSendInfo_Value(track, cat, i, OTHER[cat])
    local name, num, col = "?", 0, nil
    if other and other ~= 0 then
      num  = math.floor(reaper.GetMediaTrackInfo_Value(other, "IP_TRACKNUMBER") or 0)
      name = track_name(other)
      if name == "" then name = "Track " .. num end
      col  = track_colour(other)
    end
    out[#out + 1] = { n = num, nm = name, c = col }
  end
  return out
end

local function sends_vals(cat)
  local out = arr()
  if not track then return out end
  for i = 0, (reaper.GetTrackNumSends(track, cat) or 0) - 1 do
    local vol = sget(cat, i, "D_VOL")
    local db = U.val2db(vol)
    out[#out + 1] = {
      f = round(U.vol_to_fader(vol)),
      db = (db <= -150) and "-inf" or string.format("%+.1f", db),
      m = sget(cat, i, "B_MUTE") > 0.5 or nil,
      pre = (math.floor(sget(cat, i, "I_SENDMODE")) ~= POST) or nil,
      md = send_mode(cat, i),
    }
  end
  return out
end

local function build_layout()
  local tracks = arr()
  local n = reaper.CountTracks(0)
  for i = 0, n - 1 do
    local tr = reaper.GetTrack(0, i)
    tracks[#tracks + 1] = {
      i = i + 1, n = track_name(tr), c = track_colour(tr),
      s = reaper.IsTrackSelected(tr) or nil,
      f = math.floor(reaper.GetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH")),
      -- REAPER's own TCP spacer above this track: a gap, as the mixer draws it
      sp = (reaper.GetMediaTrackInfo_Value(tr, "I_SPACER") or 0) > 0.5 or nil,
      -- hidden from REAPER's mixer, so from this one too
      hm = reaper.GetMediaTrackInfo_Value(tr, "B_SHOWINMIXER") < 0.5 or nil,
    }
  end
  local panels = arr()
  for i, fx in ipairs(chain) do panels[#panels + 1] = panel_of(fx, i) end
  local tn = track and math.floor(reaper.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER")) or 0
  return {
    tracks = tracks,
    mc = track_colour(reaper.GetMasterTrack(0)),
    track = track and { i = tn, n = track_name(track), c = track_colour(track),
                        m = (track == reaper.GetMasterTrack(0)) or nil } or nil,
    fx = panels,
    nfx = track and reaper.TrackFX_GetCount(track) or 0,
    sends = sends_layout(0),
    recv = sends_layout(-1),
    pal = palette(),
    fmt = format_cols(),
    tex = C.PLATE_TEXTURE,
    sr = (function() local r = reaper.GetSetProjectInfo(0, "PROJECT_SRATE", 0, false)
                     return (r and r > 0) and r or 48000 end)(),
    eqr = { lo = C.EQ_FREQ_LO, hi = C.EQ_FREQ_HI, g = C.EQ_GAIN_RANGE },
    grw = arr({ table.unpack(C.GRV_WINDOWS) }),
    vals = C.SHOW_VALUES,
  }
end

-- ---------------------------------------------------------------------
-- the values
-- ---------------------------------------------------------------------
-- ---------------------------------------------------------------------
-- the gain-reduction trace -- TS_CV_Trace's columns, packed for the page
-- ---------------------------------------------------------------------
-- The page opens traces per device and says which (verb grset), every few
-- seconds while any are open; a page gone quiet for longer than that has
-- its traces dropped. The open set is published in ExtState TS_CV_WEB/wave
-- so ChannelView's window, which also keeps the probe taps in order, taps
-- the same reporting plugins rather than undoing this script's taps.
local TRACE_W = 200          -- columns sent per trace
local TRACE_TTL = 8          -- seconds without a grset before the set lapses
local web_tr = { set = {}, at = -100, key = "" }

local function publish_wave()
  local gs = {}
  for g in pairs(web_tr.set) do gs[#gs + 1] = g end
  table.sort(gs)
  local key = table.concat(gs, ",")
  if key ~= web_tr.key then
    web_tr.key = key
    reaper.SetExtState(NS, "wave", key, false)
    TP.invalidate()
  end
end

-- One character per column, 0..63: the level as a share of full scale.
local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
local B64C = {}
for i = 1, 64 do B64C[i - 1] = B64:sub(i, i) end
local function q64(v)
  local i = math.floor(math.max(0, math.min(1, v)) * 63 + 0.5)
  return B64C[i]
end

-- { o = output peaks, u = output troughs, i = input peaks (each a string
-- of TRACE_W characters), g = the reduction, two characters a column in
-- 1/64 dB ("--" where there's no reading), b = beat lines } or { m, m2 }
-- while there's nothing to draw yet.
local function trace_of(fx, meter, est, gr)
  local w = web_tr.set[fx.guid]
  Tr.want(track)
  local d, m1, m2 = Tr.columns(track, fx, { win = (w ~= "" and w) or meter.win }, est, gr, TRACE_W)
  if not d then return { m = m1, m2 = m2 } end
  local o, u, ip, g = {}, {}, {}, {}
  local sc = d.sc
  for k = 1, TRACE_W do
    o[k] = q64((d.mx[k] or 0) / sc)
    u[k] = q64(-(d.mn[k] or 0) / sc)
    ip[k] = q64((d.ip[k] or 0) / sc)
    local v = d.g[k]
    if v then
      local n = math.floor(math.max(0, math.min(4095, v * 64 + 0.5)))
      g[k] = B64C[n // 64] .. B64C[n % 64]
    else
      g[k] = ".."
    end
  end
  return { o = table.concat(o), u = table.concat(u), i = table.concat(ip),
           g = table.concat(g), b = d.beats }
end

local function peak_db(tr, ch)
  local v = reaper.Track_GetPeakInfo(tr, ch) or 0
  return v > 0.0000001 and 20 * math.log(v, 10) or -150
end

-- ---------------------------------------------------------------------
-- the mixer -- every track REAPER shows in its mixer, plus the master
-- ---------------------------------------------------------------------
-- Sent only while the page has its mixer open (verb mix, repeated every
-- few seconds, dropped after MIX_TTL of silence): sixty tracks of meters
-- are not worth writing every cycle for a page that isn't showing them.
local MIX_TTL = 8
local mix_at = -100

local function track_at(i)
  i = tonumber(i)
  if not i then return nil end
  if i == 0 then return reaper.GetMasterTrack(0) end
  return reaper.GetTrack(0, i - 1)
end

local function strip_vals(tr, i)
  local function gv(k) return reaper.GetMediaTrackInfo_Value(tr, k) or 0 end
  local vol = gv("D_VOL")
  local db = U.val2db(vol)
  return {
    i = i,
    f = round(U.vol_to_fader(vol)),
    db = (db <= -150) and "-inf" or string.format("%+.1f", db),
    pan = round(gv("D_PAN")),
    m = gv("B_MUTE") > 0.5 or nil,
    s = gv("I_SOLO") > 0 or nil,
    r = (i ~= 0 and gv("I_RECARM") > 0.5) or nil,
    ph = (i ~= 0 and gv("B_PHASE") > 0.5) or nil,
    mo = (i ~= 0) and (math.floor(gv("I_RECMON")) % 3) or nil,
    sel = (i ~= 0 and gv("I_SELECTED") > 0.5) or nil,
    pl = round(peak_db(tr, 0), 1), pr = round(peak_db(tr, 1), 1),
  }
end

local function mixer_vals()
  local out = arr({ strip_vals(reaper.GetMasterTrack(0), 0) })
  for i = 0, reaper.CountTracks(0) - 1 do
    local tr = reaper.GetTrack(0, i)
    if reaper.GetMediaTrackInfo_Value(tr, "B_SHOWINMIXER") >= 0.5 then
      out[#out + 1] = strip_vals(tr, i + 1)
    end
  end
  return out
end

-- ---------------------------------------------------------------------
-- the navigator -- the whole session in a strip, as REAPER's Navigator
-- ---------------------------------------------------------------------
-- While the page shows it (verb nav, as mix): ExtState `nav`, rebuilt once
-- a second and written when it changes -- each visible track's items as
-- spans of NAV_BINS slices across the project, plus regions and markers.
-- The moving parts (play position, arrange view, time selection) go in
-- vals, every cycle. A session of thousands of items costs the same as a
-- small one: spans merge, and nothing per item crosses to the page.
local NAV_BINS = 400
local nav_at, next_nav, nav_seq, last_nav = -100, 0, 0, nil

local function nav_open() return reaper.time_precise() - nav_at < MIX_TTL end

local function build_nav()
  local L = reaper.GetProjectLength(0) or 0
  local regions, markers = arr(), arr()
  local _, nm, nr = reaper.CountProjectMarkers(0)
  for k = 0, (nm or 0) + (nr or 0) - 1 do
    local ok, isrgn, pos, rend, name, num, col = reaper.EnumProjectMarkers3(0, k)
    if ok and ok > 0 then
      local c = (col and col ~= 0) and (function()
        local r, g, b = reaper.ColorFromNative(math.floor(col) & 0xffffff)
        return string.format("#%02x%02x%02x", r, g, b) end)() or nil
      if isrgn then
        regions[#regions + 1] = { s = round(pos, 3), e = round(rend, 3), n = name or "", c = c, x = num }
        if rend > L then L = rend end
      else
        markers[#markers + 1] = { p = round(pos, 3), n = name or "", c = c, x = num }
        if pos > L then L = pos end
      end
    end
  end
  if L <= 0 then L = 60 end
  local lanes = arr()
  local hide_below = nil          -- depth under a collapsed folder, its children hidden
  local depth = 0
  for i = 0, reaper.CountTracks(0) - 1 do
    local tr = reaper.GetTrack(0, i)
    local visible = hide_below == nil and reaper.GetMediaTrackInfo_Value(tr, "B_SHOWINTCP") >= 0.5
    local fd = math.floor(reaper.GetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH"))
    if visible then
      local bins = {}
      for j = 0, reaper.CountTrackMediaItems(tr) - 1 do
        local it = reaper.GetTrackMediaItem(tr, j)
        local pos = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
        local len = reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
        local b0 = math.max(0, math.floor(pos / L * NAV_BINS))
        local b1 = math.min(NAV_BINS - 1, math.max(b0, math.ceil((pos + len) / L * NAV_BINS) - 1))
        for b = b0, b1 do bins[b] = true end
      end
      local spans, b = arr(), 0
      while b < NAV_BINS do
        if bins[b] then
          local e = b
          while bins[e + 1] do e = e + 1 end
          spans[#spans + 1] = b; spans[#spans + 1] = e
          b = e + 1
        else
          b = b + 1
        end
      end
      lanes[#lanes + 1] = { i = i + 1, s = spans }
      if fd > 0 and reaper.GetMediaTrackInfo_Value(tr, "I_FOLDERCOMPACT") >= 2 then
        hide_below = depth + 1
      end
    end
    depth = depth + fd
    if hide_below and depth < hide_below then hide_below = nil end
  end
  return { L = round(L, 3), n = NAV_BINS, lanes = lanes, rg = regions, mk = markers }
end

local function nav_vals()
  local v0, v1 = reaper.GetSet_ArrangeView2(0, false, 0, 0)
  local playing = (reaper.GetPlayState() & 1) == 1
  local ts0, ts1 = reaper.GetSet_LoopTimeRange2(0, false, false, 0, 0, false)
  return {
    a = round(v0 or 0, 3), b = round(v1 or 0, 3),
    p = round(playing and reaper.GetPlayPosition() or reaper.GetCursorPosition(), 3),
    c = round(reaper.GetCursorPosition(), 3),
    pl = playing or nil,
    t0 = (ts1 and ts1 > ts0) and round(ts0, 3) or nil, t1 = (ts1 and ts1 > ts0) and round(ts1, 3) or nil,
    N = nav_seq,
  }
end

-- ---------------------------------------------------------------------
-- the spectrum behind the ReaEQ canvas -- as the desktop's (TS_CV_EQPanel):
-- TS_TrackAnalyser's POST spectrum from its probe, read straight from gmem,
-- and only while something is publishing it
-- ---------------------------------------------------------------------
local TA_POST_BASE, TA_H_SEQ, TA_H_ROLE = 0x20000, 0, 11
local TA_H_BANDN, TA_H_BANDLO, TA_H_BANDHI = 16, 17, 18
local TA_OFF_BAND, TA_STRIDE = 16384, 4
local SPEC_FLOOR_DB = -80
local spec_attached, spec_seq, spec_seq_t = false, nil, 0

-- { lo, hi, d = one character a band, 0..63 from SPEC_FLOOR_DB to 0 dB }
local function spectrum_vals()
  if not spec_attached then reaper.gmem_attach(TP.GMEM_NS); spec_attached = true end
  if reaper.gmem_read(TA_POST_BASE + TA_H_ROLE) ~= 1 then return nil end
  local seq = reaper.gmem_read(TA_POST_BASE + TA_H_SEQ)
  local now = reaper.time_precise()
  if seq ~= spec_seq then spec_seq, spec_seq_t = seq, now end
  if now - spec_seq_t >= 1.0 then return nil end
  local n = math.floor(reaper.gmem_read(TA_POST_BASE + TA_H_BANDN) or 0)
  if n < 2 then return nil end
  local d = {}
  for i = 0, n - 1 do
    local db = reaper.gmem_read(TA_POST_BASE + TA_OFF_BAND + i * TA_STRIDE) or SPEC_FLOOR_DB
    d[i + 1] = q64((db - SPEC_FLOOR_DB) / -SPEC_FLOOR_DB)
  end
  return { lo = round(reaper.gmem_read(TA_POST_BASE + TA_H_BANDLO) or C.EQ_FREQ_LO, 1),
           hi = round(reaper.gmem_read(TA_POST_BASE + TA_H_BANDHI) or C.EQ_FREQ_HI, 1),
           d = table.concat(d) }
end

local function build_vals(lseq, ack)
  local fxv = {}
  local any_eq = false
  for _, fx in ipairs(chain) do
    local key = U.plugin_key(fx.name)
    local layout = M.get_or_default(key, track, fx.addr, fx.guid)
    local nparams = reaper.TrackFX_GetNumParams(track, fx.addr)
    local v, x = arr(), arr()
    for ci, ctl in ipairs(layout.controls or {}) do
      if ctl.param and ctl.param >= 0 and ctl.param < nparams then
        local raw = reaper.TrackFX_GetParamNormalized(track, fx.addr, ctl.param) or 0
        local inv = ctl.invert and (ctl.type == "knob" or ctl.type == "toggle" or ctl.type == "stepped")
        v[ci] = round(inv and (1 - raw) or raw)
        x[ci] = U.fmt_value(track, fx.addr, ctl.param)
      else
        v[ci] = 0; x[ci] = ""
      end
    end
    local meter = M.meter_of(layout)
    local gr = nil
    if meter and T.reports_gr(track, fx.addr, fx.guid) then
      gr = round(T.gain_reduction(track, fx.addr) or 0, 2)
    end
    local est = (gr and T.gr_estimated(track, fx.addr, fx.guid)) or nil
    fxv[fx.guid] = { e = T.get_enabled(track, fx.addr), v = v, x = x, gr = gr,
                     est = est,
                     tw = (gr and web_tr.set[fx.guid]) and trace_of(fx, meter, est, gr) or nil,
                     eq = RQ.is_eq(key) and eq_vals(fx) or nil }
    if RQ.is_eq(key) then any_eq = true end
  end
  local tr = nil
  if track then
    local vol = reaper.GetMediaTrackInfo_Value(track, "D_VOL")
    local db  = U.val2db(vol)
    tr = {
      f  = round(U.vol_to_fader(vol)),
      db = (db <= -150) and "-inf" or string.format("%+.1f", db),
      pan = round(reaper.GetMediaTrackInfo_Value(track, "D_PAN")),
      m = reaper.GetMediaTrackInfo_Value(track, "B_MUTE") > 0.5 or nil,
      s = reaper.GetMediaTrackInfo_Value(track, "I_SOLO") > 0 or nil,
      r = reaper.GetMediaTrackInfo_Value(track, "I_RECARM") > 0.5 or nil,
      pl = round(peak_db(track, 0), 1), pr = round(peak_db(track, 1), 1),
      ph = reaper.GetMediaTrackInfo_Value(track, "B_PHASE") > 0.5 or nil,
      mo = math.floor(reaper.GetMediaTrackInfo_Value(track, "I_RECMON") or 0) % 3,
    }
  end
  local mx = (reaper.time_precise() - mix_at < MIX_TTL) and mixer_vals() or nil
  return { L = lseq, A = ack, fx = fxv, tr = tr, s = sends_vals(0), r = sends_vals(-1), mx = mx,
           nv = nav_open() and nav_vals() or nil,
           sp = any_eq and spectrum_vals() or nil }
end

-- ---------------------------------------------------------------------
-- adding plugins -- TS_CV_Browser's list, searched here for the page
-- ---------------------------------------------------------------------
-- Inserted by ident, never by display name (names collide across formats),
-- at a position through TrackFX_AddByName's own -1000 - n. The recently
-- used list is the desktop's, so both pick up where the other left off.
local fx_lib, fx_tree = nil, nil
local RECENT_KEY = "recent_fx"

local function fx_library()
  if fx_lib then return fx_lib end
  local list, i = {}, 0
  while true do
    local ok, name, ident = reaper.EnumInstalledFX(i)
    if not ok then break end
    if name and ident and name ~= "" then
      list[#list + 1] = { name = name, ident = ident, short = U.clean_fx_name(name),
                          vendor = U.fx_vendor(name) or "", fmt = U.fx_format(name) or "",
                          lower = name:lower() }
    end
    i = i + 1
    if i > 30000 then break end
  end
  table.sort(list, function(a, b) return a.short:lower() < b.short:lower() end)
  local devs, cats, folds = IX.build(list)
  fx_lib = list
  local function names(t, withid)
    local out = arr()
    for _, e in ipairs(t or {}) do
      out[#out + 1] = withid and { id = e.id, n = e.name, c = e.count } or { n = e.name, c = e.count }
    end
    return out
  end
  fx_tree = { folders = names(folds, true), cats = names(cats), devs = names(devs) }
  return fx_lib
end

local function recents()
  local out = {}
  for id in reaper.GetExtState(C.EXT_SECT, RECENT_KEY):gmatch("[^\n]+") do out[#out + 1] = id end
  return out
end

local function remember(ident)
  local out = { ident }
  for _, id in ipairs(recents()) do
    if id ~= ident and #out < 10 then out[#out + 1] = id end
  end
  reaper.SetExtState(C.EXT_SECT, RECENT_KEY, table.concat(out, "\n"), true)
end

local function fx_search(q, kind, val)
  local list = fx_library()
  local terms = SR.terms(q)
  local function in_filter(e)
    if kind == "folder" then return e.folders ~= nil and e.folders[tonumber(val) or val] == true end
    if kind == "cat" then
      for _, c in ipairs(e.cats or {}) do if c == val then return true end end
      return false
    end
    if kind == "dev" then return e.dev == val end
    return true
  end
  local out, seen = arr(), {}
  local function add(e, rec)
    if seen[e.ident] or #out >= 120 then return end
    seen[e.ident] = true
    out[#out + 1] = { n = e.short, v = e.vendor, f = e.fmt, id = e.ident, r = rec or nil }
  end
  if #terms == 0 and (kind or "") == "" then
    local by = {}
    for _, e in ipairs(list) do by[e.ident] = e end
    for _, id in ipairs(recents()) do if by[id] then add(by[id], true) end end
  end
  if #terms == 0 then
    for _, e in ipairs(list) do
      if #out >= 120 then break end
      if in_filter(e) then add(e) end
    end
  else
    -- forgiving and ranked, as the desktop's picker (TS_CV_Search)
    local rec = {}
    for _, id in ipairs(recents()) do rec[id] = true end
    for _, e in ipairs(SR.search(list, q, in_filter, function(e) return rec[e.ident] and 15 or 0 end, 120)) do
      add(e)
    end
  end
  return out
end

-- ---------------------------------------------------------------------
-- commands from the page
-- ---------------------------------------------------------------------
local applied = 0
local found_seq = 0

-- REAPER's action list, for the macro editor's search. Built once, on the
-- first search.
local actions = nil
local function action_list()
  if actions then return actions end
  actions = {}
  local sec = reaper.SectionFromUniqueID and reaper.SectionFromUniqueID(0)
  local i = 0
  while true do
    local id, name
    if reaper.kbd_enumerateActions and sec then
      id, name = reaper.kbd_enumerateActions(sec, i)
    elseif reaper.CF_EnumerateActions then
      id, name = reaper.CF_EnumerateActions(0, i, "")
    else
      break
    end
    if not id or id == 0 then break end
    local named = reaper.ReverseNamedCommandLookup(id)
    actions[#actions + 1] = { id = named and ("_" .. named) or tostring(id),
                              name = name or "", low = (name or ""):lower() }
    i = i + 1
    if i > 100000 then break end
  end
  return actions
end

local function find_actions(q)
  local words = {}
  for w in q:lower():gmatch("%S+") do words[#words + 1] = w end
  local out = arr()
  if #words == 0 then return out end
  for _, a in ipairs(action_list()) do
    local ok = true
    for _, w in ipairs(words) do
      if not a.low:find(w, 1, true) and a.id:lower() ~= w then ok = false break end
    end
    if ok then
      out[#out + 1] = { id = a.id, n = a.name }
      if #out >= 40 then break end
    end
  end
  return out
end

local layout_dirty = false

local function apply(verb, a)
  if verb == "nav" then
    nav_at = (a[1] == "1") and reaper.time_precise() or -100
    if a[1] == "1" then next_nav = 0 end
  elseif verb == "navgo" then
    -- a tap on the navigator: the edit cursor there (the play position too
    -- while playing), and the arrange view follows if it has to
    local t = tonumber(a[1])
    if t then reaper.SetEditCurPos2(0, math.max(0, t), true, true) end
  elseif verb == "navview" then
    -- the view box dragged: the arrange view keeps its zoom, starts at t
    local t = tonumber(a[1])
    if t then
      local v0, v1 = reaper.GetSet_ArrangeView2(0, false, 0, 0)
      local w = (v1 or 0) - (v0 or 0)
      if w > 0 then reaper.GetSet_ArrangeView2(0, true, 0, 0, math.max(0, t), math.max(0, t) + w) end
    end
  elseif verb == "mix" then
    mix_at = (a[1] == "1") and reaper.time_precise() or -100
  elseif verb == "tvol" or verb == "tvol0" or verb == "tpan" or verb == "tpan0"
         or verb == "tset" or verb == "tmon" then
    -- Any track's channel, by number (0 = master). Ganged as the desktop's
    -- mixer is: touch one of several selected tracks and they all follow
    -- (TS_CV_Gang) -- volume by ratio, pan by offset, switches to one value.
    local tr = track_at(a[1])
    if not tr then return end
    -- the master has no record arm, phase invert or input monitoring
    local master = tr == reaper.GetMasterTrack(0)
    if master and (verb == "tmon" or (verb == "tset" and a[2] ~= "mute" and a[2] ~= "solo")) then return end
    if verb == "tvol" then
      local f = tonumber(a[2])
      if f then G.vol(tr, U.fader_to_vol(math.max(0, math.min(1, f)))) end
    elseif verb == "tvol0" then
      G.set(tr, "D_VOL", 1)
    elseif verb == "tpan" then
      local v = tonumber(a[2])
      if v then G.pan(tr, math.max(-1, math.min(1, v))) end
    elseif verb == "tpan0" then
      G.set(tr, "D_PAN", 0)
    elseif verb == "tset" then
      local k = ({ mute = "B_MUTE", solo = "I_SOLO", arm = "I_RECARM", phase = "B_PHASE" })[a[2] or ""]
      if not k then return end
      local cur = reaper.GetMediaTrackInfo_Value(tr, k)
      if cur == nil then return end
      -- a third argument sets rather than toggles: a swipe along the
      -- mixer's buttons carries the first one's new state to the rest
      local want
      if a[3] == "1" then want = true elseif a[3] == "0" then want = false else want = not (cur > 0) end
      local on = want and (k == "I_SOLO" and 2 or 1) or 0
      G.set(tr, k, on)
    elseif verb == "tmon" then
      local cur = reaper.GetMediaTrackInfo_Value(tr, "I_RECMON")
      if cur == nil then return end
      G.set(tr, "I_RECMON", (a[2] == "0") and 0 or ((math.floor(cur) + 1) % 3))
    end
  elseif verb == "grset" then
    -- "guid=window,guid=window": the traces open on the page (an empty
    -- window is the layout's own)
    local set = {}
    for item in (a[1] or ""):gmatch("[^,]+") do
      local g, w = item:match("^([^=]+)=?(.*)$")
      if g then set[g] = w end
    end
    web_tr.set, web_tr.at = set, reaper.time_precise()
    publish_wave()
  elseif verb == "p" then
    local fx = fx_by_guid(a[1]); local p, v = tonumber(a[2]), tonumber(a[3])
    if fx and p and v then
      local key = U.plugin_key(fx.name)
      local layout = M.get_or_default(key, track, fx.addr, fx.guid)
      local inv = false
      for _, ctl in ipairs(layout.controls or {}) do
        if ctl.param == p and ctl.invert
           and (ctl.type == "knob" or ctl.type == "toggle" or ctl.type == "stepped") then inv = true end
      end
      v = math.max(0, math.min(1, v))
      reaper.TrackFX_SetParamNormalized(track, fx.addr, p, inv and (1 - v) or v)
      TP.touched(track, fx.guid)
    end
  elseif verb == "def" then
    local fx = fx_by_guid(a[1]); local p = tonumber(a[2])
    if fx and p then
      reaper.TrackFX_SetParamNormalized(track, fx.addr, p, U.param_mid_norm(track, fx.addr, p))
      TP.touched(track, fx.guid)
    end
  elseif verb == "byp" then
    local fx = fx_by_guid(a[1])
    if fx then T.set_enabled(track, fx.addr, not T.get_enabled(track, fx.addr)) end
  elseif verb == "float" then
    local fx = fx_by_guid(a[1])
    if fx then T.toggle_float(track, fx.addr) end
  elseif verb == "sel" then
    local i = tonumber(a[1])
    local tr = (i == 0) and reaper.GetMasterTrack(0) or (i and reaper.GetTrack(0, i - 1))
    if tr then
      reaper.SetOnlyTrackSelected(tr)
      reaper.SetMixerScroll(tr)
      layout_dirty = true
    end
  elseif track and verb == "vol" then
    local f = tonumber(a[1])
    if f then reaper.SetMediaTrackInfo_Value(track, "D_VOL", U.fader_to_vol(math.max(0, math.min(1, f)))) end
  elseif track and verb == "vol0" then
    reaper.SetMediaTrackInfo_Value(track, "D_VOL", 1)
  elseif track and verb == "pan" then
    local v = tonumber(a[1])
    if v then reaper.SetMediaTrackInfo_Value(track, "D_PAN", math.max(-1, math.min(1, v))) end
  elseif track and (verb == "mute" or verb == "solo" or verb == "arm") then
    local k = ({ mute = "B_MUTE", solo = "I_SOLO", arm = "I_RECARM" })[verb]
    local on = reaper.GetMediaTrackInfo_Value(track, k) > 0
    reaper.SetMediaTrackInfo_Value(track, k, on and 0 or (verb == "solo" and 2 or 1))
  elseif track and (verb == "svol" or verb == "sv0" or verb == "smute" or verb == "spre"
                    or verb == "smode" or verb == "srem") then
    local cat, i = tonumber(a[1]), tonumber(a[2])
    if not (cat == 0 or cat == -1) or not i or i < 0
       or i >= (reaper.GetTrackNumSends(track, cat) or 0) then return end
    local function set(k, v) reaper.SetTrackSendInfo_Value(track, cat, i, k, v) end
    if verb == "svol" then
      local f = tonumber(a[3])
      if f then set("D_VOL", U.fader_to_vol(math.max(0, math.min(1, f)))) end
    elseif verb == "sv0" then
      set("D_VOL", 1)
    elseif verb == "smute" then
      set("B_MUTE", sget(cat, i, "B_MUTE") > 0.5 and 0 or 1)
    elseif verb == "spre" then
      set("I_SENDMODE", math.floor(sget(cat, i, "I_SENDMODE")) == POST and PRE or POST)
    elseif verb == "smode" then
      local mode = a[3]
      if mode == "direct" or mode == "sidechain" or mode == "midi" then
        local dst = (cat == -1) and track or reaper.GetTrackSendInfo_Value(track, cat, i, "P_DESTTRACK")
        reaper.Undo_BeginBlock()
        apply_mode(function(k) return sget(cat, i, k) end, set, dst, mode)
        reaper.Undo_EndBlock("ChannelView: " .. mode .. " send", -1)
      end
    elseif verb == "srem" then
      reaper.Undo_BeginBlock()
      reaper.RemoveTrackSend(track, cat, i)
      reaper.Undo_EndBlock(cat == 0 and "ChannelView: remove send" or "ChannelView: remove receive", -1)
    end
    layout_dirty = true
  elseif track and verb == "sadd" then
    -- sadd|cat|track number (0 = a new track at the end)|mode
    local cat, num, mode = tonumber(a[1]), tonumber(a[2]), a[3]
    if mode ~= "sidechain" and mode ~= "midi" then mode = "direct" end
    if cat ~= 0 and cat ~= -1 then return end
    reaper.Undo_BeginBlock()
    local other
    if num == 0 then
      reaper.InsertTrackAtIndex(reaper.CountTracks(0), true)
      other = reaper.GetTrack(0, reaper.CountTracks(0) - 1)
      reaper.SetOnlyTrackSelected(track)      -- stay on the track being worked on
    else
      other = num and reaper.GetTrack(0, num - 1)
    end
    if other and other ~= track then
      local src, dst = track, other
      if cat == -1 then src, dst = other, track end
      local idx = reaper.CreateTrackSend(src, dst)
      if idx and idx >= 0 then
        apply_mode(function(k) return reaper.GetTrackSendInfo_Value(src, 0, idx, k) end,
                   function(k, v) reaper.SetTrackSendInfo_Value(src, 0, idx, k, v) end, dst, mode)
      end
    end
    reaper.Undo_EndBlock(cat == 0 and "ChannelView: add send" or "ChannelView: add receive", -1)
    layout_dirty = true
  elseif track and (verb == "eqf" or verb == "eqg" or verb == "eqq" or verb == "eqtype" or verb == "eqrem") then
    local fx = fx_by_guid(a[1]); local bt, bi = tonumber(a[2]), tonumber(a[3])
    local b = fx and bt and bi and eq_band(fx, bt, bi)
    if not b then return end
    if verb == "eqf" then
      local hz = tonumber(a[4]); if hz then RQ.set_freq(track, fx.addr, b, hz) end
    elseif verb == "eqg" then
      local db = tonumber(a[4]); if db and HAS_GAIN[bt] then eq_target(fx.guid, bt, bi, 1, db) end
    elseif verb == "eqq" then
      local q = tonumber(a[4]); if q then eq_target(fx.guid, bt, bi, 2, math.max(RQ.Q_MIN, math.min(RQ.Q_MAX, q))) end
    else
      local nbt = (verb == "eqtype") and tonumber(a[4]) or nil
      reaper.Undo_BeginBlock()
      local ok, rbt, rbi = RQ.replace_band(track, fx.addr, b, nbt)
      reaper.Undo_EndBlock(nbt and "ChannelView: change EQ band type" or "ChannelView: remove EQ band", -1)
      if nbt and ok and rbt then
        if HAS_GAIN[rbt] then eq_target(fx.guid, rbt, rbi, 1, b.gain or 0) end
        eq_target(fx.guid, rbt, rbi, 2, RQ.DEFAULT_Q[rbt] or 1)
      end
      eq_reads[fx.guid] = nil
    end
  elseif track and verb == "eqadd" then
    -- eqadd|guid|hz|db: the type follows from where, as on the desktop
    local fx = fx_by_guid(a[1]); local hz, db = tonumber(a[2]), tonumber(a[3]) or 0
    if fx and hz then
      local bt = RQ.infer_type(hz)
      reaper.Undo_BeginBlock()
      local ok, rbt, rbi = RQ.add_band(track, fx.addr, bt, hz, 0, RQ.DEFAULT_Q[bt])
      reaper.Undo_EndBlock("ChannelView: add EQ band", -1)
      if ok and rbt then
        if HAS_GAIN[rbt] then eq_target(fx.guid, rbt, rbi, 1, db) end
        eq_target(fx.guid, rbt, rbi, 2, RQ.DEFAULT_Q[rbt] or 1)
      end
      eq_reads[fx.guid] = nil
    end
  elseif verb == "fxfind" then
    -- fxfind|seq|query|kind|val
    local seq = tonumber(a[1]) or 0
    local r = fx_search(a[2] or "", a[3] or "", a[4] or "")
    reaper.SetExtState(NS, "fxfound", json({ s = seq, r = r, tree = fx_tree }), false)
  elseif track and verb == "fxadd" then
    -- fxadd|ident|top-level slot to insert before (-1: the end)
    -- the page escapes the ident, so a "|" or "~" in it can't split the command
    local ident = (a[1] or ""):gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end)
    local at = tonumber(a[2]) or -1
    if ident and ident ~= "" then
      reaper.Undo_BeginBlock()
      local idx = reaper.TrackFX_AddByName(track, ident, false, (at >= 0) and (-1000 - at) or -1)
      local short = ident
      for _, e in ipairs(fx_library()) do if e.ident == ident then short = e.short break end end
      reaper.Undo_EndBlock("ChannelView: add " .. short, -1)
      if idx and idx >= 0 then remember(ident) end
      layout_dirty = true
    end
  elseif track and verb == "fxmove" then
    -- fxmove|guid|gap: gaps count insertion points, 0 = before the first
    -- plugin, as the desktop's drag does. Top level only.
    local fx = fx_by_guid(a[1]); local gap = tonumber(a[2])
    if fx and fx.is_top_level and gap then
      local src = fx.top_index
      local dest = (gap > src) and (gap - 1) or gap
      if dest ~= src then
        reaper.Undo_BeginBlock()
        reaper.TrackFX_CopyToTrack(track, src, track, dest, true)
        reaper.Undo_EndBlock("ChannelView: reorder plugin", -1)
      end
      layout_dirty = true
    end
  elseif track and verb == "fxdel" then
    local fx = fx_by_guid(a[1])
    if fx and fx.is_top_level then
      reaper.Undo_BeginBlock()
      reaper.TrackFX_Delete(track, fx.top_index)
      reaper.Undo_EndBlock("ChannelView: remove " .. U.clean_fx_name(fx.name), -1)
      layout_dirty = true
    end
  elseif verb == "find" then
    found_seq = found_seq + 1
    reaper.SetExtState(NS, "found", json({ q = a[1] or "", s = found_seq, r = find_actions(a[1] or "") }), false)
  end
end

local function read_commands()
  local s = reaper.GetExtState(NS, "cmd")
  if s == "" then return end
  for item in (s .. "~"):gmatch("([^~]*)~") do
    local parts = {}
    for f in (item .. "|"):gmatch("([^|]*)|") do parts[#parts + 1] = f end
    local seq = tonumber(parts[1])
    if seq and seq > applied then
      local verb = parts[2]
      local args = {}
      for k = 3, #parts do args[#args + 1] = parts[k] end
      local ok, err = pcall(apply, verb, args)
      if not ok then reaper.ShowConsoleMsg("TS_ChannelView_Web: " .. tostring(err) .. "\n") end
      applied = seq
    elseif seq and seq < applied - 1000 then
      applied = seq   -- the page restarted its count
    end
  end
end

-- ---------------------------------------------------------------------
-- the loop
-- ---------------------------------------------------------------------
local lseq, last_layout, last_vals = 0, nil, nil
local next_layout, next_pal = 0, 0
local alive = 0
local chain_hash = nil
local lib_body = nil

local function cycle()
  local now = reaper.time_precise()
  eq_reads = {}

  read_commands()

  -- follow REAPER's selection, as ChannelView does
  local tr = current_track()
  if tr ~= track then
    track = tr
    layout_dirty = true
  end
  if valid(track) then
    local list = T.collect(track)
    local h = T.hash(list)
    if h ~= chain_hash then
      chain_hash = h
      chain = list
      choice_cache = {}
      layout_dirty = true
    end
  else
    track, chain = nil, {}
  end

  if now >= next_pal then
    next_pal = now + 1
    -- A layout edited in ChannelView's window lands in the library file;
    -- this script has its own copy of the library, so notice the file
    -- changing and read it again.
    local f = io.open(M.file_path(), "rb")
    local body = f and f:read("a") or ""
    if f then f:close() end
    if body ~= lib_body then
      if lib_body ~= nil then M.reload(); layout_dirty = true end
      lib_body = body
    end
    local h, t = pal_get()
    if C.apply_colour(h or C.BASE_HUE, t or C.TINT) then layout_dirty = true end
    C.PLATE_TEXTURE = reaper.GetExtState("TS_ChannelView", "plate_texture") ~= "0"
    local sv = reaper.GetExtState("TS_ChannelView", "show_values")
    C.SHOW_VALUES = (sv == "") or (sv == "1")
  end

  -- The layout is rebuilt twice a second regardless, which also catches
  -- what has no event to watch: a layout edited in ChannelView, a renamed
  -- track, a live parameter name.
  if layout_dirty or now >= next_layout then
    next_layout = now + 0.5
    layout_dirty = false
    local s = json(build_layout())
    if s ~= last_layout then
      last_layout = s
      lseq = lseq + 1
      reaper.SetExtState(NS, "layout", s, false)
    end
  end

  if next(web_tr.set) and now - web_tr.at > TRACE_TTL then
    web_tr.set = {}
    publish_wave()
  end
  Tr.begin_frame()

  if nav_open() and now >= next_nav then
    next_nav = now + 1
    local s = json(build_nav())
    if s ~= last_nav then
      last_nav = s
      nav_seq = nav_seq + 1
      reaper.SetExtState(NS, "nav", s, false)
    end
  end

  if track and next(eq_jobs) then
    eq_reads = {}
    eq_step()
    eq_reads = {}      -- the values below read what the step just wrote
  end

  if track then
    local s = json(build_vals(lseq, applied))
    if s ~= last_vals then
      last_vals = s
      reaper.SetExtState(NS, "vals", s, false)
    end
  end

  TP.update(now)

  alive = (alive + 1) % 1000000
  reaper.SetExtState(NS, "alive", tostring(alive), false)
  reaper.defer(cycle)
end

reaper.SetExtState(NS, "wave", "", false)   -- nothing open until the page says

-- A toggle in the action list, lit while it runs.
local _, _, sec, cmd = reaper.get_action_context()
if cmd and cmd ~= 0 then
  reaper.SetToggleCommandState(sec, cmd, 1)
  reaper.RefreshToolbar2(sec, cmd)
end
reaper.atexit(function()
  reaper.SetExtState(NS, "alive", "", false)
  reaper.SetExtState(NS, "vals", "", false)
  reaper.SetExtState(NS, "wave", "", false)
  if cmd and cmd ~= 0 then
    reaper.SetToggleCommandState(sec, cmd, 0)
    reaper.RefreshToolbar2(sec, cmd)
  end
end)

reaper.SetExtState(NS, "cmd", "", false)
cycle()
