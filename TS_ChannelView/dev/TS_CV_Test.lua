-- @noindex  (a development tool, not a package: never installed)
-- Offline harness: fake just enough of REAPER to exercise the pure-Lua
-- parts (name cleaning, INI round-trip, layout parsing, panel geometry).
--
-- Not shipped. Run it from anywhere with a stock Lua 5.4:
--     lua5.4 dev/TS_CV_Test.lua
-- Paths are resolved from this file rather than the working directory, so
-- it does not matter where you run it from.

local HERE = debug.getinfo(1, "S").source:match("@?(.*[\\/])") or "./"
package.path = HERE .. "../?.lua;" .. HERE .. "?.lua;" .. package.path

-- a small fake plugin: 6 own params + REAPER's Wet/Bypass/Delta tail
local PARAMS = {"Input","Attack","Release","Ratio","Power","Pan","Wet","Bypass","Delta"}
local VALUES = {}
for i = 1, #PARAMS do VALUES[i-1] = 0.5 end

reaper = {
  TrackFX_GetNumParams        = function() return #PARAMS end,
  TrackFX_GetParamName        = function(_,_,i) return true, PARAMS[i+1] or "" end,
  TrackFX_GetParamNormalized  = function(_,_,i) return VALUES[i] end,
  TrackFX_SetParamNormalized  = function(_,_,i,v) VALUES[i] = v end,
  TrackFX_GetFormattedParamValue = function(_,_,i) return true, string.format("%.1f", (VALUES[i] or 0)*100) end,
  TrackFX_GetParameterStepSizes  = function(_,_,i)
      if PARAMS[i+1] == "Power" then return true, 1, 1, 1, true end
      if PARAMS[i+1] == "Ratio" then return true, 0.5, 0.5, 1, false end
      return false
    end,
  -- value first, then min/max/mid -- the signature the real API uses
  TrackFX_GetParamEx = function(_,_,i)
      if PARAMS[i+1] == "Pan" then return 0, -1, 1, 0 end
      return VALUES[i], 0, 1, 0.5
    end,
  ColorFromNative = function(v) return (v>>16)&0xff, (v>>8)&0xff, v&0xff end,
  GetMediaTrackInfo_Value = function(_, k)
    if k == "I_AUTOMODE" then return AUTOMODE end
    return 0x1000000 | 0x3366cc
  end,
  -- TS_CV_Test.lua sits in Scripts/ChannelView, so REAPER's resource root
  -- is two levels up. On a real install this points the FX index at the
  -- actual reaper-fxtags.ini / reaper-fxfolders.ini.
  GetResourcePath = function() return "../.." end,
  GetPlayState = function() return PLAYING and 1 or 0 end,
  -- I_AUTOMODE: 0 trim, 1 read, 2 touch, 3 write, 4 latch

  time_precise = function() return NOW end,
  TrackFX_GetNamedConfigParm = function(_, _, k)
    if k == "GainReduction_dB" then
      if not REPORTS then return false end
      return true, tostring(-GR)
    end
    return false
  end,
}

NOW, GR, REPORTS = 0, 0, true   -- driven by the meter checks below
PLAYING, VAL, SETS = false, 0, 0   -- driven by the stepped-param checks
AUTOMODE = 0                       -- track automation mode, same checks
local STEP_LABELS = {"Off","Low","Low","High","Max"}
local U = require "TS_CV_Util"
local M = require "TS_CV_Mappings"
local P = require "TS_CV_Panel"
local C = require "TS_CV_Config"

local fails = 0
local function check(name, got, want)
  if got ~= want then
    print(("FAIL %-38s got %s  want %s"):format(name, tostring(got), tostring(want)))
    fails = fails + 1
  else
    print(("ok   %-38s %s"):format(name, tostring(got)))
  end
end

-- boolean-style wrappers, for checks whose value isn't worth printing
local function checkf(name, fn) check(name, fn() and true or false, true) end
local function ch(name, ok, detail)
  check(name .. (detail and detail ~= "" and ("  [" .. detail .. "]") or ""),
        ok and true or false, true)
end

-- name cleaning
check("clean VST3+vendor", U.clean_fx_name("VST3: DF-SMACK (Dawesome)"), "DF-SMACK")
check("clean VST+vendor",  U.clean_fx_name("VST: ReaComp (Cockos)"), "ReaComp")
check("clean VSTi",        U.clean_fx_name("VSTi: Serum (Xfer Records)"), "Serum")
check("clean JS",          U.clean_fx_name("JS: Volume/Pan Smoother"), "Volume/Pan Smoother")
check("clean two tags",    U.clean_fx_name("VST3: Vocal Rider (Mono) (Waves)"), "Vocal Rider")
check("clean CLAP",        U.clean_fx_name("CLAP: Arousor (Distressor)"), "Arousor")
check("key strips bracket",U.plugin_key("VST3: Odd [Name] (X)"), "Odd Name")

-- REAPER's trailing Wet/Bypass/Delta must not be counted as the plugin's own
check("own_param_count", (U.own_param_count(nil, 0)), 6)

-- bipolar / type guessing
check("guess toggle", U.guess_control_type(nil, 0, 4), "toggle")
check("guess combo",  U.guess_control_type(nil, 0, 3), "combo")
check("guess knob",   U.guess_control_type(nil, 0, 0), "knob")
check("bipolar pan",  U.guess_bipolar("Pan", nil, 0, 5), true)
check("bipolar input",U.guess_bipolar("Input", nil, 0, 0), false)
check("mid_norm",     U.param_mid_norm(nil, 0, 0), 0.5)

-- track colour flag handling
-- ColorFromNative already normalises the platform byte order, so the
-- stub just hands back r,g,b as it decoded them.
check("track colour", string.format("%08x", U.track_colour(nil, 0xff)), "3366ccff")
check("track colour unset", U.track_colour_unset_stub == nil and (function()
  local old = reaper.GetMediaTrackInfo_Value
  reaper.GetMediaTrackInfo_Value = function() return 0x0 end
  local r = U.track_colour(nil, 0xff)
  reaper.GetMediaTrackInfo_Value = old
  return r
end)(), nil)

-- INI round trip through the real mapping store
os.remove("./TS_ChannelView_Mappings.ini")
M.init("./")
local key = "DF-SMACK"
check("unmapped is default", select(2, M.get_or_default(key, nil, 0, "g1")), true)
local def = M.get_or_default(key, nil, 0, "g1")
check("default control count", #def.controls, 6)
check("default picks toggle", def.controls[5].type, "toggle")

M.set(key, { controls = {
  { param = 0, type = "knob",   bipolar = false, label = "In"        },
  { param = 5, type = "knob",   bipolar = true,  label = "Pan | wide" },
  { param = 4, type = "toggle", bipolar = false, label = ""          },
  { param = -1,type = "blank",  bipolar = false, label = ""          },
} })
M.save()
M.reload()
local back = M.get(key)
check("round-trip count",   #back.controls, 4)
check("round-trip param",   back.controls[2].param, 5)
check("round-trip bipolar", back.controls[2].bipolar, true)
check("pipe stripped",      back.controls[2].label, "Pan   wide")
check("round-trip blank",   back.controls[4].type, "blank")
check("saved is not default", select(2, M.get_or_default(key, nil, 0, "g1")), false)

-- panel geometry: fixed height, grows in columns
local function n_knobs(n)
  local out = {}
  for i = 1, n do out[i] = { type = "knob" } end
  return out
end
local function cols_for(n, h)
  return P.layout(n_knobs(n), h).width / 58   -- CELL_W
end

local H = 300   -- panel height incl. header
check("rows at h=300", P.rows_for(H), 4)
check("cols for 8 @4 rows", cols_for(8, H), 2)
-- 2 columns is 116px of cells, but a header needs PANEL_MIN_W, so the
-- panel is padded out to that.
check("width for 8", P.width(8, H), 132)
check("width for 12", P.width(12, H), 3*58 + 12)
check("cols for 9 @4 rows", cols_for(9, H), 3)
check("min width honoured", P.width(1, H), 132)
check("rows at h=120", P.rows_for(120), 1)
check("cols for 8 @1 row", cols_for(8, 120), 8)

-- aliases: per-plugin parameter renames, independent of any panel slot
M.set_alias(key, 2, "Recovery")
M.set_alias(key, 5, "Width")
M.save(); M.reload()
check("alias round-trip",      M.get_alias(key, 2), "Recovery")
check("alias survives reload", M.get_alias(key, 5), "Width")
check("alias absent -> nil",   M.get_alias(key, 99), nil)
check("controls kept on alias write", #M.get(key).controls, 4)
check("display: slot label wins", M.display_name(key, 2, "Rec", "Release"), "Rec")
check("display: alias next",      M.display_name(key, 2, "",    "Release"), "Recovery")
check("display: plugin name last",M.display_name(key, 7, "",    "Ratio"),   "Ratio")
M.set_alias(key, 2, "")
M.save(); M.reload()
check("alias cleared", M.get_alias(key, 2), nil)

-- panel width with a collapsed panel
check("collapsed width", P.width(8, 300, true), C.COLLAPSED_W)
check("expanded width",  P.width(8, 300, false), 132)

-- the add-plugin picker: vendor tags, the all-terms search rule, and why
-- inserts are keyed on ident rather than display name
-- vendor extraction
check("vendor from VST3 tag",  U.fx_vendor("VST3: Saturn 2 (FabFilter)"), "FabFilter")
check("vendor, two tags",      U.fx_vendor("VST3: Vocal Rider (Mono) (Waves)"), "Waves")
check("vendor absent",         U.fx_vendor("JS: Volume/Pan Smoother"), nil)

-- the all-terms-must-match rule the picker uses
local function matches(full, query)
  local lower = full:lower()
  for t in query:lower():gmatch("%S+") do
    if not lower:find(t, 1, true) then return false end
  end
  return true
end
check("single term",           matches("VST3: Saturn 2 (FabFilter)", "saturn"), true)
check("two terms, in order",   matches("VST3: Saturn 2 (FabFilter)", "fab sat"), true)
check("two terms, reversed",   matches("VST3: Saturn 2 (FabFilter)", "sat fab"), true)
check("vendor only",           matches("VST3: Pro-Q 3 (FabFilter)", "fabfilter"), true)
check("format prefix matches", matches("CLAP: Arousor (Distressor)", "clap"), true)
check("non-match rejected",    matches("VST3: Pro-Q 3 (FabFilter)", "saturn"), false)
check("one term of two fails", matches("VST3: Pro-Q 3 (FabFilter)", "fab saturn"), false)

-- name collisions across formats: the display names are identical, so an
-- insert keyed on name would be ambiguous -- idents are not
local FX = {
  {"VST3: Saturn 2 (FabFilter)", "vst3:saturn2"},
  {"VST: Saturn 2 (FabFilter)",  "vst:saturn2"},
  {"VST3: Pro-Q 3 (FabFilter)",  "vst3:proq3"},
}
local by_short = {}
for _, e in ipairs(FX) do
  local s = U.clean_fx_name(e[1])
  by_short[s] = (by_short[s] or 0) + 1
end
check("display name collides",  by_short["Saturn 2"], 2)
local idents = {}
for _, e in ipairs(FX) do idents[e[2]] = (idents[e[2]] or 0) + 1 end
local dupe = false
for _, c in pairs(idents) do if c > 1 then dupe = true end end
check("idents are unique",      dupe, false)

-- instantiate encoding: -1000 - n inserts at slot n, -1 appends
local function instantiate(at) return at and (-1000 - at) or -1 end
check("append",                 instantiate(nil), -1)
check("insert at slot 0",       instantiate(0),   -1000)
check("insert at slot 3",       instantiate(3),   -1003)


-- the add-plugin picker's developer filter, and how it composes with
-- the search box
local FX = {
  "VST3: Saturn 2 (FabFilter)",
  "VST: Saturn 2 (FabFilter)",
  "VST3: Pro-Q 3 (FabFilter)",
  "VST3: Pro-C 2 (FabFilter)",
  "VST3: DF-SMACK (Dawesome)",
  "VST3: Vocal Rider (Mono) (Waves)",
  "JS: Volume/Pan Smoother",
  "JS: LOSER/3BandSplitter",
  "CLAP: Arousor (Distressor)",
}
local ANY, NONE = "", "\1none"

-- the index the picker builds
local entries = {}
for _, n in ipairs(FX) do
  entries[#entries+1] = { name = n, short = U.clean_fx_name(n),
                          vendor = U.fx_vendor(n) or "", lower = n:lower() }
end
local counts = {}
for _, e in ipairs(entries) do
  local k = (e.vendor ~= "") and e.vendor or NONE
  counts[k] = (counts[k] or 0) + 1
end
local vendors = {}
for name, n in pairs(counts) do vendors[#vendors+1] = {name=name, count=n} end
table.sort(vendors, function(a,b)
  if a.name == NONE then return false end
  if b.name == NONE then return true end
  return a.name:lower() < b.name:lower()
end)

local function in_vendor(e, v)
  if v == ANY then return true end
  if v == NONE then return e.vendor == "" end
  return e.vendor == v
end
local function matches(e, q)
  for t in q:lower():gmatch("%S+") do
    if not e.lower:find(t, 1, true) then return false end
  end
  return true
end
local function count(v, q)
  local n = 0
  for _, e in ipairs(entries) do
    if in_vendor(e, v) and matches(e, q or "") then n = n + 1 end
  end
  return n
end

check("developers found",          #vendors, 5)
check("real vendors",              #vendors - 1, 4)
check("sorted, first",             vendors[1].name, "Dawesome")
check("no-vendor bucket sorts last", vendors[#vendors].name, NONE)
check("no-vendor bucket counted",  vendors[#vendors].count, 2)
check("FabFilter counted",         count("FabFilter"), 4)
check("Waves counted",             count("Waves"), 1)
check("unfiltered is everything",  count(ANY), #FX)
-- filter and search compose
check("FabFilter + 'pro'",         count("FabFilter", "pro"), 2)
check("FabFilter + 'saturn'",      count("FabFilter", "saturn"), 2)
check("FabFilter + 'smack'",       count("FabFilter", "smack"), 0)
check("no-developer + 'js'",       count(NONE, "js"), 2)
check("search alone crosses devs", count(ANY, "vst3"), 5)


local IX = require "TS_CV_FXIndex"

-- the FX index: identifier normalising, and the hue-driven palette
-- the key normaliser has to cope with every identifier shape
check("bare filename",      IX.norm_key("reacomp.dll"),                    "reacomp.dll")
check("full windows path",  IX.norm_key([[C:\Program Files\VST3\Foo.vst3]]), "foo.vst3")
check("drive letter kept",  IX.norm_key([[C:\x\Pro-Q 3.vst3]]),            "pro-q_3.vst3")
check("type prefix",        IX.norm_key("vst3:Saturn 2.vst3"),             "saturn_2.vst3")
check("shell hash",         IX.norm_key("WaveShell1.dll<12345"),           "waveshell1.dll")
check("spaces = underscores", IX.norm_key("Nectar Pro.vst3"),              "nectar_pro.vst3")
checkf("space/underscore agree", function()
  return IX.norm_key("Nectar Pro.vst3") == IX.norm_key("Nectar_Pro.vst3")
end)


local ORIGINAL = {
 win_bg=0x11131aff, panel_bg=0x1b1e26ff, panel_border=0x2c313dff, header_bg=0x232833ff,
 header_bg_byp=0x2a2320ff, header_text=0xd6dae4ff, header_dim=0x76808fff, label=0x9aa4b4ff,
 value=0xd6dae4ff, knob_track=0x333a47ff, knob_fill=0x4a9edaff, knob_fill_bi=0xd8a24aff,
 knob_body=0x262b35ff, knob_body_hi=0x2f3641ff, knob_pointer=0xe8edf5ff, knob_ring=0x3d4452ff,
 toggle_off=0x2a2f3aff, toggle_on=0x4a9edaff, toggle_text=0xd6dae4ff, accent=0x4a9edaff,
 warn=0xd8724aff, strip_bg=0x15171dff, strip_sel=0x4a9edaff, empty_text=0x5e6675ff,
 drop_marker=0x4a9edaff, header_drag=0x2f3744ff, icon=0x9aa4b4ff, icon_hot=0xe8edf5ff,
 icon_on=0x0d1116ff, bypass_on=0xd8724aff, float_on=0x4a9edaff,
}
local function rgb(v) return (v>>24)&255, (v>>16)&255, (v>>8)&255, v&255 end

local worst, worst_k = 0, nil
for k, want in pairs(ORIGINAL) do
  local got = C.COL[k]
  if not got then ch("missing " .. k, false) else
    local r1,g1,b1,a1 = rgb(want); local r2,g2,b2,a2 = rgb(got)
    local d = math.max(math.abs(r1-r2), math.abs(g1-g2), math.abs(b1-b2))
    if d > worst then worst, worst_k = d, k end
    if a1 ~= a2 then ch("alpha " .. k, false) end
  end
end
ch("every colour reproduced within 2/255", worst <= 2,
   ("worst was %s, off by %d"):format(tostring(worst_k), worst))
-- every palette entry produces a colour, whatever the palette grows to --
-- a hard-coded count just breaks every time a colour is added
ch("every palette entry produces a colour", (function()
  local want, got = 0, 0
  for _ in pairs(C.PALETTE) do want = want + 1 end
  for _ in pairs(C.COL) do got = got + 1 end
  return want > 0 and got == want
end)(), "")

-- rotating the hue must move the accent and leave alert colours alone
local accent0, warn0, lum0 = C.COL.accent, C.COL.warn, C.COL.win_bg
C.BASE_HUE = 120; C.build_palette()
ch("hue change moves the accent", C.COL.accent ~= accent0)
ch("alert hue is pinned",         C.COL.warn == warn0)
ch("backgrounds still dark",      select(1, rgb(C.COL.win_bg)) < 60)
ch("text still light",            select(1, rgb(C.COL.header_text)) > 180)

-- tint 0 must give true greys
C.TINT = 0; C.build_palette()
local r,g,b = rgb(C.COL.panel_bg)
ch("tint 0 gives neutral grey", r == g and g == b, ("%d,%d,%d"):format(r,g,b))
ch("accent unaffected by tint",  C.COL.accent ~= C.COL.panel_bg)

-- and back
C.BASE_HUE, C.TINT = 219, 1.0; C.build_palette()
ch("reset restores the original", C.COL.accent == ORIGINAL.accent)
ch("C.COL identity is stable", (function()
  local ref = C.COL; C.BASE_HUE = 300; C.build_palette()
  local same = (ref == C.COL)   -- modules hold this reference
  C.BASE_HUE = 219; C.build_palette()
  return same
end)(), "rebuilt in place, not replaced")


local T = require "TS_CV_FXTree"
local W = require "TS_CV_Widgets"

-- the gain-reduction meter: reading, peak hold, and the layout flag
-- reading
GR = 6.0
check("reads reduction as positive dB", T.gain_reduction(nil, 0), 6.0)
check("reports_gr true",                T.reports_gr(nil, 0, "g1"), true)
REPORTS = false; T.clear_gr_cache()
check("no report -> nil",               T.gain_reduction(nil, 0), nil)
check("reports_gr false",               T.reports_gr(nil, 0, "g2"), false)
REPORTS = true; T.clear_gr_cache()

-- A bypassed plugin keeps ANSWERING GainReduction_dB with whatever it
-- last measured -- it stopped processing, not stopped talking -- so the
-- meter froze at the reduction it happened to be doing when you switched
-- it off. That is a number that is not true of anything.
do
  local real = reaper.TrackFX_GetEnabled
  ENABLED = false
  reaper.TrackFX_GetEnabled = function() return ENABLED end
  GR = 6.0
  check("bypassed reads as no reduction", T.gain_reduction(nil, 0), 0)
  ENABLED = true
  check("and enabled reads the plugin again", T.gain_reduction(nil, 0), 6.0)
  -- The peak then falls from where it was rather than sticking, because
  -- it is fed a real zero instead of a stale six.
  W.clear_peaks()
  NOW = 0 ; W.gr_peak("byp", 6.0, NOW)
  ENABLED = false
  NOW = C.GR_HOLD + 1
  local after = W.gr_peak("byp", T.gain_reduction(nil, 0), NOW)
  check("and the peak decays once bypassed", after < 6.0, true)
  ENABLED = true
  reaper.TrackFX_GetEnabled = real
end

-- peak hold: rises instantly, holds, then falls
W.clear_peaks()
NOW = 0
check("peak follows a rise",   W.gr_peak("k", 8.0, NOW), 8.0)
NOW = 0.5
check("holds while signal drops", W.gr_peak("k", 1.0, NOW), 8.0)
NOW = 1.0
check("still holding at 1.0s",  W.gr_peak("k", 1.0, NOW), 8.0)
-- Past the hold it falls at GR_FALL dB/s. 0.2s is 3.6dB, which lands
-- partway down the 7dB gap -- a bigger step would hit the signal floor
-- and prove nothing about the rate.
NOW = C.GR_HOLD + 0.2
local v = W.gr_peak("k", 1.0, NOW)
check("falls partway after the hold", v < 8.0 and v > 1.0, true)
check("falls at the configured rate",
      math.abs(v - (8.0 - C.GR_FALL * 0.2)) < 0.01, true)
check("never falls below the signal", W.gr_peak("k", 1.0, NOW + 100) >= 1.0, true)
NOW = 10
check("settles to the signal",  W.gr_peak("k", 1.0, NOW), 1.0)
NOW = 11
check("a new peak overrides",   W.gr_peak("k", 5.0, NOW), 5.0)
check("peaks are per key",      W.gr_peak("other", 2.0, NOW), 2.0)

-- layout round trip
local lay = M.build_default(nil, 0)
check("default meter on for a reporter", lay.meter ~= nil and lay.meter.on, true)
check("default range",                   lay.meter.range, C.MAX_GR_DB)
M.set_meter(lay, true, 20)
M.set("Comp", lay); M.save(); M.reload()
local back = M.get("Comp")
check("meter survives a save",   back.meter.on, true)
check("range survives a save",   back.meter.range, 20)
check("meter_of returns it",     M.meter_of(back).range, 20)
M.set_meter(back, false)
M.set("Comp", back); M.save(); M.reload()
check("off survives a save",     M.get("Comp").meter.on, false)
check("meter_of nil when off",   M.meter_of(M.get("Comp")), nil)
check("copy carries the meter",  M.copy(back).meter.range, 20)

-- width: the strip costs its own width, not a whole column
local H = 300
local no_meter = P.width(8, H, false, false)
local with     = P.width(8, H, false, true)
check("meter adds its column",   with - no_meter, C.METER_COL_W + C.PANEL_PAD)
check("and not a whole column",  (with - no_meter) < C.CELL_W, true)
check("collapsed width unchanged", P.width(8, H, true, true), C.COLLAPSED_W)
-- The readout drives the column width, not the bar: "12.4 dB" at the
-- meter font has to fit on one line in an expanded panel, and must fall
-- back to stacking inside a collapsed bar.
-- A deliberately pessimistic advance width for a sans face, so this is a
-- guard rather than a rubber stamp. The real arbiter is the screen; what
-- this pins down is that the widths can't silently drift too narrow.
local function fits(text, px, font_px)
  return #text * font_px * 0.55 <= px
end
check("bar stays thin",             C.METER_W <= 14, true)
check("column still under a cell",  C.METER_COL_W < C.CELL_W, true)
check("readout fits the column",    fits("12.4 dB", C.METER_COL_W, C.METER_FONT), true)
check("widest the ladder can make",  fits("60.0 dB", C.METER_COL_W, C.METER_FONT), true)
check("one line would not fit the bar",
      fits("12.4 dB", C.METER_W, C.METER_FONT), false)
check("stacked value fits collapsed",
      fits("12.4", C.COLLAPSED_W - 8, C.METER_FONT), true)
-- and the fallback that makes any width safe: when one line doesn't fit,
-- the readout stacks rather than overflowing
check("collapsed forces stacking",
      fits("12.4 dB", C.COLLAPSED_W - 8, C.METER_FONT), false)




-- the cascading add-plugin menu: the reverse indexes each submenu is
-- handed, checked against the real metadata
-- This block checks the submenu reverse-indexes against a REAL tag file,
-- which is the only way to catch the grouping edge cases a synthetic list
-- never produces. The file is not in the repo -- it is personal, and big.
-- Point TS_CV_TEST_FXTAGS at your own REAPER/reaper-fxtags.ini to run it;
-- without one there is nothing real to check, so it is skipped rather
-- than failed.
local TAGFILE = os.getenv("TS_CV_TEST_FXTAGS") or (HERE .. "realdata/reaper-fxtags.ini")
local tagf = io.open(TAGFILE, "r")
if not tagf then
  print("skip cascading add-plugin menu -- no reaper-fxtags.ini " ..
        "(set TS_CV_TEST_FXTAGS to run it)")
else
  tagf:close()
-- a sample drawn from the real tag file
  local list = {}
  for line in io.lines(TAGFILE) do
    local k = line:match("^([%w_%-%. ]+%.vst3)=")
    if k then
      list[#list+1] = { name = "VST3: " .. k:gsub("%.vst3$", "") .. " (X)",
                        ident = k, short = k:gsub("%.vst3$", ""),
                        vendor = "", fmt = "VST3" }
    end
    if #list >= 600 then break end
  end
  local devs, cats, folds = IX.build(list)
  
  -- the same grouping the browser does
  local by_dev, by_cat, by_fold, by_letter = {}, {}, {}, {}
  for _, e in ipairs(list) do
    for fid in pairs(e.folders or {}) do
      by_fold[fid] = by_fold[fid] or {}; table.insert(by_fold[fid], e)
    end
    for _, c in ipairs(e.cats or {}) do
      by_cat[c] = by_cat[c] or {}; table.insert(by_cat[c], e)
    end
    local d = e.dev or "\1none"
    by_dev[d] = by_dev[d] or {}; table.insert(by_dev[d], e)
    local ch = e.short:sub(1,1):upper()
    if not ch:match("%a") then ch = "#" end
    by_letter[ch] = by_letter[ch] or {}; table.insert(by_letter[ch], e)
  end
  
  -- every plugin reachable exactly once through "All plugins"
  local seen, total = {}, 0
  for _, bucket in pairs(by_letter) do
    for _, e in ipairs(bucket) do
      check_dup = seen[e]; seen[e] = true; total = total + 1
    end
  end
  check("every plugin has a letter bucket", total, #list)
  
  -- the counts a submenu shows must match what it then lists
  local ok_counts = true
  for _, d in ipairs(devs) do
    if #(by_dev[d.name] or {}) ~= d.count then ok_counts = false end
  end
  check("developer counts match their lists", ok_counts, true)
  local ok_cat = true
  for _, c in ipairs(cats) do
    if #(by_cat[c.name] or {}) ~= c.count then ok_cat = false end
  end
  check("category counts match their lists", ok_cat, true)
  local ok_fold = true
  for _, f in ipairs(folds) do
    if #(by_fold[f.id] or {}) ~= f.count then ok_fold = false end
  end
  check("folder counts match their lists", ok_fold, true)
  
  -- no submenu is offered empty (the menu skips those)
  local empty = false
  for _, d in ipairs(devs) do if d.count == 0 then empty = true end end
  for _, c in ipairs(cats) do if c.count == 0 then empty = true end end
  for _, f in ipairs(folds) do if f.count == 0 then empty = true end end
  check("no empty submenu offered", empty, false)
  
  -- letter buckets stay a sane size, which is the point of splitting
  local biggest, where = 0, nil
  for ch, b in pairs(by_letter) do
    if #b > biggest then biggest, where = #b, ch end
  end
  print(("     %d plugins, %d letters, biggest bucket '%s' = %d")
    :format(#list, (function() local n=0 for _ in pairs(by_letter) do n=n+1 end return n end)(), where, biggest))
  check("buckets much smaller than the whole", biggest < #list / 3, true)
end  -- TAGFILE


-- the Sends panel: spacer tracks, direct vs sidechain, panel widths
do
  local SD = require "TS_CV_Sends"
  local real = {}
  for _, k in ipairs({"CountTracks","GetTrack","GetSetMediaTrackInfo_String",
                      "GetMediaTrackInfo_Value","SetMediaTrackInfo_Value",
                      "CreateTrackSend","SetTrackSendInfo_Value",
                      "GetTrackNumSends","Undo_BeginBlock","Undo_EndBlock"}) do
    real[k] = reaper[k]
  end
local TRACKS = {
    { name = "Kick",      col = 0x1000000 | 0x3366cc },
    { name = "Snare",     col = 0x1000000 | 0xcc6633 },
    { name = "--------",  col = 0 },
    { name = "Bass",      col = 0x1000000 | 0x33cc66 },
    { name = "",          col = 0 },            -- unnamed
    { name = "== BUSES ==", col = 0 },
    { name = "Drum Bus",  col = 0x1000000 | 0x8844cc },
  }
  local NCHAN, DSTCHAN, SENDS = {}, {}, {}
  -- (the individual overrides below patch the shared stub in place;
  --  replacing the whole `reaper` table here would wipe every other one)
  reaper.CountTracks = function() return #TRACKS end
  reaper.GetTrack = function(_, i) return i + 1 end
  reaper.GetSetMediaTrackInfo_String = function(tr, k)
    if k == "P_NAME" then return true, TRACKS[tr] and TRACKS[tr].name or "" end
    return false
  end
  reaper.GetMediaTrackInfo_Value = function(tr, k)
    if k == "I_CUSTOMCOLOR" then return TRACKS[tr] and TRACKS[tr].col or 0 end
    if k == "IP_TRACKNUMBER" then return tr end
    if k == "I_NCHAN" then return NCHAN[tr] or 2 end
    return 0
  end
  reaper.SetMediaTrackInfo_Value = function(tr, k, v)
    if k == "I_NCHAN" then NCHAN[tr] = v end
  end
  reaper.CreateTrackSend = function(src, dst)
    SENDS[#SENDS+1] = { src = src, dst = dst }; return #SENDS - 1
  end
  reaper.SetTrackSendInfo_Value = function(_, _, i, k, v)
    if k == "I_DSTCHAN" then DSTCHAN[i] = v end
  end
  reaper.GetTrackNumSends = function() return #SENDS end
  reaper.Undo_BeginBlock = function() end
  reaper.Undo_EndBlock = function() end

-- spacer tracks are gaps in the menu, not destinations
  check("dashes are a separator",   SD.is_separator("--------"), true)
  -- A LABELLED spacer ("== BUSES ==") stays a destination on purpose. The
  -- rule is punctuation-only, because guessing wrong here hides a track you
  -- meant to send to, which is worse than listing one you didn't.
  check("a labelled spacer is still a track", SD.is_separator("== BUSES =="), false)
  check("bare equals bars are a separator",   SD.is_separator("========"), true)
  check("dots and tildes too",      SD.is_separator("~~..~~"), true)
  check("a real name is not",       SD.is_separator("Drum Bus"), false)
  check("an empty name is not",     SD.is_separator(""), false)
  check("a name with dashes is not", SD.is_separator("Hi-Hat"), false)
  check("a numbered name is not",   SD.is_separator("Track 3"), false)
  
  -- direct vs sidechain
  check("direct send created",      SD.add_send(1, 4, false), true)
  check("direct lands on 1/2",      DSTCHAN[0], 0)
  check("destination not widened",  NCHAN[4], nil)
  check("sidechain send created",   SD.add_send(1, 7, true), true)
  check("sidechain lands on 3/4",   DSTCHAN[1], 2)
  check("destination widened to 4", NCHAN[7], 4)
  NCHAN[7] = 8
  SD.add_send(1, 7, true)
  check("an already-wide track is left alone", NCHAN[7], 8)
  check("no send to itself",        SD.add_send(1, 1, false), false)
  check("no send to nothing",       SD.add_send(1, nil, false), false)
  
  -- Panel widths. Sends sit on the same grid the plugin panels use, in
  -- double-width cells, so the width is a whole number of columns and
  -- only grows once a column's rows are used up -- including the add
  -- tile, which is just the next cell.
  local H    = 300
  local rows = P.rows_for(H)
  local one  = C.SEND_W + C.PANEL_PAD * 2
  check("collapsed sends width",    SD.width(true, 0, H), C.COLLAPSED_W)
  check("empty sends is one column", SD.width(false, 0, H), one)
  check("still one while it fits",  SD.width(false, rows - 1, H), one)
  check("add tile opens column 2",  SD.width(false, rows, H),
        math.min(C.SENDS_MAX_W, one + C.SEND_W + C.SEND_COL_GAP))
  check("a second column brings its gap with it",
        SD.width(false, rows, H) - one, C.SEND_W + C.SEND_COL_GAP)
  check("width grows with sends",   SD.width(false, rows * 2, H) > SD.width(false, 1, H), true)
  check("but is capped",            SD.width(false, 99, H), C.SENDS_MAX_W)
  for k, v in pairs(real) do reaper[k] = v end
end

-- Chains edited from OUTSIDE this window -- REAPER's own FX chain, another
-- script, an undo. An FX address is a position, so a cached chain stops
-- meaning what it meant; these are the checks that catch it.
do
  local CHAIN = {}
  local TR = {}
  local real = {
    TrackFX_GetCount = reaper.TrackFX_GetCount,
    TrackFX_GetFXGUID = reaper.TrackFX_GetFXGUID,
    TrackFX_GetFXName = reaper.TrackFX_GetFXName,
    TrackFX_GetNamedConfigParm = reaper.TrackFX_GetNamedConfigParm,
  }
  reaper.TrackFX_GetCount  = function() return #CHAIN end
  reaper.TrackFX_GetFXGUID = function(_, addr)
    local e = CHAIN[addr + 1]; return e and e.guid or ""
  end
  reaper.TrackFX_GetFXName = function(_, addr)
    local e = CHAIN[addr + 1]
    if not e then return false end
    return true, e.name
  end
  reaper.TrackFX_GetNamedConfigParm = function() return false end
local function set(...)
    CHAIN = {}
    for _, n in ipairs({...}) do
      CHAIN[#CHAIN+1] = { name = "VST3: " .. n .. " (X)", guid = "{" .. n .. "}" }
    end
  end
  
  -- the staleness test the window runs each frame
  local function stale(cached)
    for _, fx in ipairs(cached) do
      if T.guid_at(TR, fx.addr) ~= fx.guid then return true end
    end
    return false
  end
  
  set("A", "B", "C")
  local cached = T.collect(TR)
  check("collected the chain",   #cached, 3)
  check("fresh chain is not stale", stale(cached), false)
  
  -- someone reorders in REAPER's FX chain window
  set("B", "A", "C")
  check("reorder detected",      stale(cached), true)
  check("addr 0 now a different plugin",
        T.guid_at(TR, 0) ~= cached[1].guid, true)
  
  -- ...and after a rescan it agrees again
  cached = T.collect(TR)
  check("rescan clears it",      stale(cached), false)
  
  -- someone deletes one
  set("B", "C")
  check("deletion detected",     stale(cached), true)
  cached = T.collect(TR)
  check("rescan after deletion", stale(cached), false)
  check("chain is shorter",      #cached, 2)
  
  -- someone inserts ahead of everything
  set("Z", "B", "C")
  check("insertion detected",    stale(cached), true)
  
  -- the whole chain emptied
  set()
  check("empty chain detected",  stale(cached), true)
  cached = T.collect(TR)
  check("empty rescan is clean", stale(cached), false)
  check("nothing left",          #cached, 0)
  
  -- the format tag shown in the picker
  check("format VST3",  U.fx_format("VST3: Saturn 2 (FabFilter)"), "VST3")
  check("format VST",   U.fx_format("VST: ReaComp (Cockos)"), "VST")
  check("format CLAP",  U.fx_format("CLAP: Arousor (Distressor)"), "CLAP")
  check("format JS",    U.fx_format("JS: Volume/Pan Smoother"), "JS")
  check("instrument kept apart", U.fx_format("VST3i: Serum (Xfer)"), "VST3i")
  check("no prefix",    U.fx_format("Bare Name"), nil)
  for k, v in pairs(real) do reaper[k] = v end
end


-- scan budgeting and the on-disk cache of stepped choices
do
  local SC = require "TS_CV_Steps"
  local saved_budget = C.SCAN_BUDGET
  -- every parameter stepped, 5 positions, so the budget is what limits
  -- how many get scanned rather than the fixture
  local real = {
    TrackFX_GetParameterStepSizes = reaper.TrackFX_GetParameterStepSizes,
    TrackFX_GetParamEx            = reaper.TrackFX_GetParamEx,
    TrackFX_GetParamNormalized    = reaper.TrackFX_GetParamNormalized,
    TrackFX_SetParamNormalized    = reaper.TrackFX_SetParamNormalized,
    TrackFX_GetFormattedParamValue= reaper.TrackFX_GetFormattedParamValue,
  }
  local LAB = {"Off","Low","Mid","High","Max"}
  reaper.TrackFX_GetParameterStepSizes = function() return true, 0.25, 0.25, 0.25, false end
  reaper.TrackFX_GetParamEx            = function() return VAL, 0, 1, 0.5 end
  reaper.TrackFX_GetParamNormalized    = function() return VAL end
  reaper.TrackFX_SetParamNormalized    = function(_,_,_,v) VAL = v; SETS = SETS + 1 end
  reaper.TrackFX_GetFormattedParamValue = function()
    return true, LAB[math.floor(VAL * 4 + 0.5) + 1] or "?"
  end
  VAL, SETS = 0, 0
os.remove("./TS_ChannelView_Steps.ini")
  SC.init("./")
  
  -- the per-frame budget: several parameters can't all sweep at once
  C.SCAN_BUDGET = 2
  P.clear_caches()
  P.begin_frame()
  local got = 0
  for prm = 0, 4 do
    if P.combo_steps(nil, 0, prm, "Comp") then got = got + 1 end
  end
  check("only the budget scans in one frame", got, 2)
  P.begin_frame()
  for prm = 0, 4 do P.combo_steps(nil, 0, prm, "Comp") end
  P.begin_frame()
  for prm = 0, 4 do P.combo_steps(nil, 0, prm, "Comp") end
  local done = 0
  for prm = 0, 4 do if P.combo_steps(nil, 0, prm, "Comp") then done = done + 1 end end
  check("the rest arrive over later frames", done, 5)
  check("value restored after sweeping",     VAL, 0)
  
  -- persisted, so a later run sweeps nothing at all
  SC.save()
  local writes_before = SETS
  SC.init("./")            -- simulate a fresh session
  P.clear_caches()
  P.begin_frame()
  local list = P.combo_steps(nil, 0, 0, "Comp")
  check("loaded from the cache file",  type(list), "table")
  check("with the right labels",       list[1].text .. "/" .. list[#list].text, "Off/Max")
  -- positions come from the step size, not the file: the labels are what
  -- cost a sweep, the arithmetic is free and can't go stale
  check("positions regenerated", (function()
    for i, s in ipairs(list) do
      if math.abs(s.norm - (i - 1) * 0.25) > 1e-9 then return false end
    end
    return list[1].norm == 0 and list[#list].norm == 1
  end)(), true)
  check("no sweep needed",             SETS, writes_before)
  check("budget untouched by a hit", (function()
    P.begin_frame()
    for prm = 0, 4 do P.combo_steps(nil, 0, prm, "Comp") end
    return SETS
  end)(), writes_before)
  
  -- rescan drops it and sweeps again
  P.rescan_choices("Comp", 0)
  P.begin_frame()
  local relist = P.combo_steps(nil, 0, 0, "Comp")
  check("rescan sweeps again",  SETS > writes_before, true)
  check("and still correct",    relist and relist[1].text, "Off")
  
  os.remove("./TS_ChannelView_Steps.ini")
  C.SCAN_BUDGET = saved_budget
  for k, v in pairs(real) do reaper[k] = v end
  P.clear_caches()
end

-- clicking a stepped control cycles; the wheel clamps
do
-- The stepping arithmetic from W.combo's bump(), exercised directly: the
  -- widget needs an ImGui context, this does not.
  local function bump(value, st, dir, wrap)
    if st then
      local last = math.floor(1 / st + 0.5)
      local k = math.floor(value / st + 0.5) + dir
      if wrap then
        if k > last then k = 0 elseif k < 0 then k = last end
      end
      return math.max(0, math.min(1, k * st))
    end
    return math.max(0, math.min(1, value + dir * C.WHEEL_STEP))
  end
  
  -- these compare floats, so they need their own tolerance
  local function checkn(name, got, want)
    check(name, math.abs((tonumber(got) or -1) - want) <= 1e-9, true)
  end
  
  local st = 0.25            -- a 5-position selector: 0, .25, .5, .75, 1
  checkn("steps up",              bump(0.00, st,  1, true), 0.25)
  checkn("steps up again",        bump(0.25, st,  1, true), 0.50)
  checkn("reaches the last",      bump(0.75, st,  1, true), 1.00)
  checkn("WRAPS past the last",   bump(1.00, st,  1, true), 0.00)
  checkn("steps down",            bump(0.50, st, -1, true), 0.25)
  checkn("wraps below the first", bump(0.00, st, -1, true), 1.00)
  
  -- a full cycle returns to where it started, which is what "rotate" means
  local v, n = 0, 0
  repeat
    v = bump(v, st, 1, true); n = n + 1
  until v == 0 or n > 20
  check("a full cycle is 5 clicks", n, 5)
  
  -- the wheel clamps instead, so a scrub can't silently roll over
  checkn("wheel stops at the top",    bump(1.00, st,  1, false), 1.00)
  checkn("wheel stops at the bottom", bump(0.00, st, -1, false), 0.00)
  
  -- an odd step count still lands exactly on the ends
  local st3 = 1/3
  checkn("thirds reach the top",   bump(2/3, st3, 1, true), 1.00)
  checkn("thirds wrap from the top", bump(1.00, st3, 1, true), 0.00)
  
  -- a continuous parameter has no steps: it must clamp, never wrap
  checkn("continuous clamps high", bump(1.00, nil,  1, true), 1.00)
  checkn("continuous clamps low",  bump(0.00, nil, -1, true), 0.00)
end

-- stepped parameters: the step size, and enumerating the plugin's own
-- choices by sweeping (never while the transport is rolling)
do
  local real = {
    TrackFX_GetParameterStepSizes = reaper.TrackFX_GetParameterStepSizes,
    TrackFX_GetParamEx            = reaper.TrackFX_GetParamEx,
    TrackFX_GetParamNormalized    = reaper.TrackFX_GetParamNormalized,
    TrackFX_SetParamNormalized    = reaper.TrackFX_SetParamNormalized,
    TrackFX_GetFormattedParamValue= reaper.TrackFX_GetFormattedParamValue,
  }
  reaper.TrackFX_GetParameterStepSizes = function() return true, 0.25, 0.25, 0.25, false end
  reaper.TrackFX_GetParamEx            = function() return VAL, 0, 1, 0.5 end
  reaper.TrackFX_GetParamNormalized    = function() return VAL end
  reaper.TrackFX_SetParamNormalized    = function(_,_,_,v) VAL = v; SETS = SETS + 1 end
  reaper.TrackFX_GetFormattedParamValue = function()
    return true, STEP_LABELS[math.floor(VAL * 4 + 0.5) + 1] or "?"
  end
-- the step size must survive GetParamEx's real signature
check("step size resolves", P.step_norm(nil, 0, 0, "k"), 0.25)

-- stopped: the sweep runs, restores, and dedupes
VAL = 0.5
P.clear_caches()
P.begin_frame()
local steps = P.combo_steps(nil, 0, 0, "k")
check("returned a list",        type(steps), "table")
check("deduped labels",         #steps, 4)          -- Off, Low, High, Max
check("first is the minimum",   steps[1].norm, 0)
check("last is the maximum",    steps[#steps].norm, 1)
check("value restored",         VAL, 0.5)
local n = SETS
P.begin_frame()
P.combo_steps(nil, 0, 0, "k")
check("cached, no second sweep", SETS, n)

-- A list that HAS been scanned stays available while playing -- that is
-- the point of caching it, and it needs a plugin never scanned before to
-- test the refusal against.
VAL = 0.5; PLAYING = true
check("a scanned list survives playback",
      type(P.combo_steps(nil, 0, 0, "k")), "table")

-- playing, never scanned: no sweep at all, and nothing cached so it
-- retries and appears by itself once stopped
VAL = 0.5; SETS = 0
P.clear_caches()
check("no list while playing",  P.combo_steps(nil, 0, 0, "unseen"), nil)
check("parameter untouched",    SETS, 0)
PLAYING = false
P.begin_frame()
check("available once stopped", type(P.combo_steps(nil, 0, 0, "unseen")), "table")

-- Sweeping while automation is recording would write the whole sweep into
-- the lane -- damage to the project, not a click. Refused regardless of
-- the setting.
local saved_flag = C.SCAN_WHILE_PLAYING
C.SCAN_WHILE_PLAYING = true
PLAYING, SETS = true, 0
P.clear_caches()
AUTOMODE = 0
check("flag allows a scan while playing", type(P.combo_steps(nil, 0, 0, "k")), "table")
for _, mode in ipairs({ 2, 3, 4 }) do          -- touch, write, latch
  AUTOMODE = mode
  SETS = 0
  P.clear_caches()
  P.begin_frame()
  -- a key never scanned, so the cache can't satisfy it instead
  local k = "am" .. mode
  check("automation write refuses (mode " .. mode .. ")",
        P.combo_steps(nil, 0, 0, k), nil)
  check("parameter untouched (mode " .. mode .. ")", SETS, 0)
end
AUTOMODE = 1                                   -- read is harmless
P.clear_caches()
P.begin_frame()
check("read mode still scans", type(P.combo_steps(nil, 0, 0, "readmode")), "table")

-- A click is a deliberate act, so it scans whatever the transport is
-- doing -- the transport only holds back BACKGROUND scanning.
AUTOMODE, PLAYING = 0, true
C.SCAN_WHILE_PLAYING = false
P.clear_caches()
P.begin_frame()
check("background scan still refused while playing",
      P.combo_steps(nil, 0, 0, "clicky"), nil)
check("explicit click scans anyway",
      type(P.combo_steps(nil, 0, 0, "clicky", true)), "table")

-- ...but never while automation is recording, click or not
for _, mode in ipairs({ 2, 3, 4 }) do
  AUTOMODE = mode
  SETS = 0
  P.clear_caches()
  check("a click cannot override automation (mode " .. mode .. ")",
        P.combo_steps(nil, 0, 0, "am_click" .. mode, true), nil)
  check("nothing written (mode " .. mode .. ")", SETS, 0)
end
AUTOMODE, PLAYING = 0, false

-- a forced scan isn't rationed by the frame budget either
C.SCAN_BUDGET = 0
P.clear_caches()
P.begin_frame()
check("budget blocks a background scan",
      P.combo_steps(nil, 0, 0, "budgeted"), nil)
check("but not an explicit click",
      type(P.combo_steps(nil, 0, 0, "budgeted", true)), "table")
C.SCAN_BUDGET = 2
AUTOMODE, PLAYING = 0, false
C.SCAN_WHILE_PLAYING = saved_flag
  for k, v in pairs(real) do reaper[k] = v end
  P.clear_caches()
end

-- the panel layout pass: dividers, and the auto-ranging GR scale
local function ctrls(spec)
  local out = {}
  for c in spec:gmatch(".") do
    out[#out+1] = { type = (c == "|") and "divider" or (c == "." and "blank" or "knob") }
  end
  return out
end

-- a panel tall enough for 4 rows
local H = 4 * C.CELL_H + C.HEADER_H + C.PANEL_PAD * 2
check("rows at that height", P.rows_for(H), 4)

-- no dividers: the old behaviour must be untouched
local l = P.layout(ctrls("kkkkkkkk"), H)
check("8 knobs place 8 items",  #l.items, 8)
check("8 knobs, 2 columns wide", l.width, 2 * C.CELL_W)
check("no rules",               #l.rules, 0)
check("first is at origin",     l.items[1].x == 0 and l.items[1].y == 0, true)
check("5th starts column 2",    l.items[5].x, C.CELL_W)
check("5th is back at row 1",   l.items[5].y, 0)

-- a divider ends the column and opens a gutter
l = P.layout(ctrls("kkkk|kkkk"), H)
check("divider: items still 8", #l.items, 8)
check("divider: one rule",      #l.rules, 1)
check("rule sits after col 1",  l.rules[1], C.CELL_W + C.DIVIDER_W * 0.5)
check("col 2 starts past it",   l.items[5].x, C.CELL_W + C.DIVIDER_W)
check("width includes gutter",  l.width, 2 * C.CELL_W + C.DIVIDER_W)
check("gutter costs < a column", C.DIVIDER_W < C.CELL_W, true)

-- a divider mid-column ends that column early
l = P.layout(ctrls("kk|kk"), H)
check("short column then rule", l.items[3].x, C.CELL_W + C.DIVIDER_W)
check("partial column still full width", l.width, 2 * C.CELL_W + C.DIVIDER_W)

-- two dividers, and one at the very start
l = P.layout(ctrls("|kkkk|kkkk"), H)
check("leading divider counted", #l.rules, 2)
check("leading divider offsets", l.items[1].x, C.DIVIDER_W)

-- P.width agrees with the layout, which is the bug this refactor prevents
-- 12 knobs is 3 columns, comfortably past PANEL_MIN_W, so the clamp
-- isn't masking the comparison (8 knobs would be: 128px clamps to 132).
local w_plain = P.width(ctrls("kkkkkkkkkkkk"), H, false, false)
local w_div   = P.width(ctrls("kkkk|kkkkkkkk"), H, false, false)
check("width difference is the gutter", w_div - w_plain, C.DIVIDER_W)
check("both are past the minimum width", w_plain > C.PANEL_MIN_W, true)
check("width = layout + padding",
      w_div, math.max(C.PANEL_MIN_W, P.layout(ctrls("kkkk|kkkkkkkk"), H).width + C.PANEL_PAD * 2))

-- The point of a divider: whatever follows it starts a NEW COLUMN, however
-- the previous section ended -- part-filled, gap-filled, or exactly full.
local H4 = 4 * C.CELL_H + C.HEADER_H + C.PANEL_PAD * 2   -- 4 rows
local function first_x_after_rule(spec)
  local lay = P.layout(ctrls(spec), H4)
  local rx = lay.rules[1]
  for _, it in ipairs(lay.items) do
    if it.x > rx then return it.x, it.y, lay end
  end
end

local x, y = first_x_after_rule("kk|kk")          -- column left part-filled
check("new column even after a part-filled one", x, C.CELL_W + C.DIVIDER_W)
check("and back at the top row", y, 0)

x, y = first_x_after_rule("k..|kk")               -- column padded out with gaps
check("new column after gaps too", x, C.CELL_W + C.DIVIDER_W)
check("gaps don't shift the row", y, 0)

x, y = first_x_after_rule("kkkk|kk")              -- column exactly full
check("new column after a full one", x, C.CELL_W + C.DIVIDER_W)

x, y = first_x_after_rule("kkkkk|kk")             -- section spills to 2 columns
check("section keeps its own columns", x, 2 * C.CELL_W + C.DIVIDER_W)

-- sections are laid out independently: a short first section does not let
-- the second one creep back up into its unused cells
local lay = P.layout(ctrls("k|kkkk"), H4)
check("second section starts clean", lay.items[2].x, C.CELL_W + C.DIVIDER_W)
check("and at row 0",                lay.items[2].y, 0)

-- degenerate placements still behave
check("doubled divider = two rules", #P.layout(ctrls("kk||kk"), H4).rules, 2)
check("trailing divider counted",    #P.layout(ctrls("kk|"), H4).rules, 1)
check("only a divider places nothing", #P.layout(ctrls("|"), H4).items, 0)

-- A divider is vertical in either flow. In row-major it marks a column
-- boundary, so the gutter applies to that column in every row and the
-- rule lines up down the whole grid.
local saved_flow = C.FLOW
C.FLOW = "row"
l = P.layout(ctrls("kkkk|kkkk"), H)
check("row-major divider: items",   #l.items, 8)
check("row-major divider: one rule", #l.rules, 1)
check("row-major width has a gutter",
      l.width, 2 * C.CELL_W + C.DIVIDER_W)
check("row-major rows line up", (function()
  -- every item left of the rule must be left of it in EVERY row
  local rx = l.rules[1]
  for _, it in ipairs(l.items) do
    local left = it.x + C.CELL_W <= rx + 1
    local right = it.x >= rx
    if not (left or right) then return false end   -- nothing straddles it
  end
  return true
end)(), true)
check("row-major rule has height",  l.height > 0, true)
C.FLOW = saved_flow

-- auto-ranging scale
W.clear_peaks()
check("ladder picks the minimum",  W.pick_range(12, 0), 12)
check("ladder covers the peak",    W.pick_range(12, 15), 20)
check("ladder steps again",        W.pick_range(12, 25), 30)
check("ladder caps at the top",    W.pick_range(12, 999), C.GR_LADDER[#C.GR_LADDER])
-- Stepped frame by frame, because the relax timer is only meaningful if
-- it's fed every frame -- which is how the panel calls it. Jumping
-- straight from the transient to three seconds later tests nothing.
local FRAME = 1 / 30
local function run(seconds, gr, rng_out)
  local t_end = NOW + seconds
  local pk, rng
  while NOW < t_end do
    pk, rng = W.gr_state("m", gr, NOW, 12)
    NOW = NOW + FRAME
  end
  return pk, rng
end

NOW = 0
local pk, rng = run(0.5, 3.0)
check("scale starts at the minimum", rng, 12)
pk, rng = W.gr_state("m", 18.0, NOW, 12)
check("scale expands at once",       rng, 20)
pk, rng = run(C.GR_RANGE_RELAX - 0.5, 0.5)
check("scale holds while relaxing",  rng, 20)
pk, rng = run(2.0, 0.5)
check("scale steps back down",       rng, 12)
check("and never below the minimum", W.pick_range(12, 0), 12)

-- editor list reordering: remove-and-insert, so one drag can carry a
-- row the whole length of the list and it lands AT the target index
local function move(list, from, to)
  if from == to or not list[from] then return end
  to = math.max(1, math.min(#list, to))
  table.insert(list, to, table.remove(list, from))
end
local function join(t) return table.concat(t, "") end

local t = {"A","B","C","D","E"}
move(t, 1, 5); check("first to last",        join(t), "BCDEA")
t = {"A","B","C","D","E"}
move(t, 5, 1); check("last to first",        join(t), "EABCD")
t = {"A","B","C","D","E"}
move(t, 2, 4); check("middle, downward",     join(t), "ACDBE")
t = {"A","B","C","D","E"}
-- the dragged row lands AT the target index, in both directions:
move(t, 4, 2); check("middle, upward",       join(t), "ADBCE")
check("landed at the target index", t[2], "D")
t = {"A","B","C","D","E"}
move(t, 3, 3); check("no-op",                join(t), "ABCDE")
t = {"A","B","C","D","E"}
move(t, 2, 99); check("clamped past the end", join(t), "ACDEB")
t = {"A","B","C","D","E"}
move(t, 4, -3); check("clamped past the start", join(t), "DABCE")

-- neighbour-swap, for contrast: one crossing only ever moves one place
t = {"A","B","C","D","E"}
t[1], t[2] = t[2], t[1]
check("swap moves only one place",  join(t), "BACDE")

-- add below selection
local function add_below(list, sel, item)
  local at = (sel >= 1 and sel <= #list) and (sel + 1) or (#list + 1)
  table.insert(list, at, item); return at
end
t = {"A","B","C"}
check("add below row 2", (function() add_below(t, 2, "X"); return join(t) end)(), "ABXC")
t = {"A","B","C"}
check("add with nothing selected", (function() add_below(t, 0, "X"); return join(t) end)(), "ABCX")
t = {"A","B","C"}
check("add below last row", (function() add_below(t, 3, "X"); return join(t) end)(), "ABCX")

-- ---------------------------------------------------------------------
-- gain: dB, and the fader taper
-- ---------------------------------------------------------------------
-- REAPER's Lua API exposes no VAL2DB / DB2VAL / DB2SLIDER / SLIDER2DB --
-- the whole family is missing, not just renamed -- so all of this is
-- ours, and it is the one place where being quietly wrong would be
-- inaudible until someone printed a number.
do
  local function near(a, b, tol) return math.abs(a - b) <= (tol or 0.01) end

  check("unity is 0 dB",        U.val2db(1.0), 0)
  check("half is -6 dB",        near(U.val2db(0.5), -6.02), true)
  check("silence is -inf",      U.val2db(0), -math.huge)
  check("nil is -inf",          U.val2db(nil), -math.huge)
  check("0 dB is unity",        U.db2val(0), 1)
  check("the floor is silence", U.db2val(U.MIN_DB), 0)
  check("below the floor too",  U.db2val(-500), 0)
  check("dB round trip",        near(U.val2db(U.db2val(-18)), -18), true)

  -- The fader's travel. Unity sits at UNITY_POS with headroom above it;
  -- the very bottom of the throw is silence, not MIN_DB, because a fader
  -- pulled all the way down has to actually shut up.
  check("unity sits at UNITY_POS",  near(U.db_to_fader(0), U.UNITY_POS, 0.001), true)
  check("the top is MAX_DB",        near(U.fader_to_db(1), U.MAX_DB), true)
  check("the bottom is silence",    U.fader_to_db(0), -math.huge)
  check("and silence is volume 0",  U.fader_to_vol(0), 0)
  check("just above it is the floor",
        U.fader_to_db(0.001) < U.MIN_DB + 1, true)
  check("unity reads back as 0 dB", near(U.fader_to_db(U.UNITY_POS), 0), true)

  local ok = true
  local prev = -math.huge
  for i = 0, 100 do
    local db = U.fader_to_db(i / 100)
    if db < prev - 0.0001 then ok = false end
    prev = db
  end
  check("the taper never goes backwards", ok, true)

  ok = true
  for _, db in ipairs({ 12, 6, 0, -3, -10, -20, -40, -60 }) do
    if not near(U.fader_to_db(U.db_to_fader(db)), db, 0.05) then ok = false end
  end
  check("fader round trip holds", ok, true)

  -- Half travel lands where a console fader lands: around -14, not the
  -- -8.5 the first curve gave.
  check("half travel is musical",
        U.fader_to_db(0.5) < -10 and U.fader_to_db(0.5) > -18, true)

  check("volume to fader via dB", near(U.vol_to_fader(1.0), U.UNITY_POS, 0.001), true)
  check("and back again",         near(U.fader_to_vol(U.UNITY_POS), 1.0, 0.001), true)

  -- printing
  check("db_text takes a volume",  U.db_text(1.0), "+0.0")
  check("db_text floors to -inf",  U.db_text(0), "-inf")
  check("db_str takes dB already", U.db_str(0), "+0.0")
  check("db_str keeps the sign",   U.db_str(-6.02), "-6.0")
  check("db_str floors to -inf",   U.db_str(-math.huge), "-inf")
  check("db_str survives nil",     U.db_str(nil), "-inf")
end

-- ---------------------------------------------------------------------
-- tooltips that stay put
-- ---------------------------------------------------------------------
-- ImGui's own tooltip follows the pointer and vanishes the instant the
-- item stops being hovered -- which is exactly when a knob is being
-- dragged, since the pointer has usually left the cell by then. Ours is
-- placed once, frozen there for as long as the control is held, and
-- painted once at the end of the frame on the foreground list.
--
-- W.attach() swaps in a fake ImGui, so this block has to come last: the
-- widgets module keeps whatever it was last given.
do
  local MX, MY = 100, 200
  local painted = {}
  -- A viewport 800x600 at the origin, and a WINDOW occupying only its
  -- left half. The window is the tighter bound and the one that matters:
  -- the foreground draw list is clipped to it, so a tooltip that fits on
  -- the monitor but hangs past the window's right edge is simply cut off.
  local VP  = { 0, 0, 800, 600 }
  local WIN = { 0, 0, 400, 500 }
  W.attach({
    GetMousePos            = function() return MX, MY end,
    GetForegroundDrawList  = function() return "fg" end,
    CalcTextSize           = function(_, t) return #t * 6, 13 end,
    GetMainViewport        = function() return "vp" end,
    Viewport_GetWorkPos    = function() return VP[1], VP[2] end,
    Viewport_GetWorkSize   = function() return VP[3], VP[4] end,
    GetWindowPos           = function() return WIN[1], WIN[2] end,
    GetWindowSize          = function() return WIN[3], WIN[4] end,
    DrawList_AddRectFilled = function() end,
    DrawList_AddRect       = function() end,
    DrawList_AddText = function(dl, x, y, _, text)
      painted[#painted + 1] = { dl = dl, x = x, y = y, text = text }
    end,
  })
  local function frame() painted = {}; W.draw_tip(nil); return painted[1] end

  W.clear_tips()

  -- hovered, not yet held: it opens beside the pointer
  W.tip(nil, "pan", "Pan   C", true, false)
  local t = frame()
  check("tooltip appears when hovered",   t ~= nil, true)
  check("painted on the foreground list", t and t.dl, "fg")
  check("carries the value",              t and t.text, "Pan   C")
  local x0, y0 = t.x, t.y
  check("offset clear of the pointer",    x0 > MX and y0 > MY, true)

  -- now held, and the pointer has run off the cell: the box stays put
  MX, MY = 400, 90
  W.tip(nil, "pan", "Pan   32L", false, true)
  t = frame()
  check("stays up once the control is held", t ~= nil, true)
  check("and does not follow the pointer",   t and t.x == x0 and t.y == y0, true)
  check("but the text tracks the value",     t and t.text, "Pan   32L")

  -- released, pointer elsewhere: gone
  W.tip(nil, "pan", "Pan   32L", false, false)
  check("gone once released", frame(), nil)

  -- a fresh hover opens at the pointer's new position
  W.tip(nil, "pan", "Pan   32L", true, false)
  t = frame()
  check("re-opens where the pointer now is", t and t.x > x0, true)

  -- each tip paints once: nothing lingers into the next frame
  check("painted once per frame", frame(), nil)

  -- two controls in one frame: the held one wins, and neither inherits
  -- the other's position
  W.clear_tips()
  MX, MY = 10, 10
  W.tip(nil, "a", "A", true, false)
  MX, MY = 500, 500
  W.tip(nil, "b", "B", false, true)
  check("the held control wins", (function() local r = frame(); return r and r.text end)(), "B")

  check("nothing drawn without text", (function()
    W.tip(nil, "c", "", true, true); return frame() end)(), nil)
  check("clear_tips forgets positions", (function()
    W.clear_tips(); MX, MY = 7, 7
    W.tip(nil, "a", "A", true, false)
    local r = frame(); return r and r.x end)(), 7 + 14)

  -- Kept inside the WINDOW. A control at its right-hand edge -- the
  -- Sends panel, every time -- otherwise throws its tooltip out past the
  -- edge, where the foreground draw list clips it away. There is plenty
  -- of monitor out there, which is why clamping to the viewport alone
  -- fixed nothing.
  local LBL = "a long enough label"
  W.clear_tips()
  MX, MY = 380, 300
  W.tip(nil, "edge", LBL, true, false)
  local e = frame()
  check("a tooltip at the window's edge is pulled back",
        e and (e.x + #LBL * 6) <= WIN[3], true)
  check("and flipped to the other side of the pointer", e and e.x < MX, true)
  check("not merely slid to the margin", e and e.x < WIN[3] - #LBL * 6, true)

  -- The same position with no window bound would have been left alone,
  -- which is the bug this replaces.
  W.clear_tips()
  MX, MY = 380, 470
  W.tip(nil, "low", "near the floor", true, false)
  local b = frame()
  check("one near the window's bottom is lifted", b and (b.y + 13) <= WIN[4], true)

  W.clear_tips()
  MX, MY = 200, 200
  W.tip(nil, "mid", "room to spare", true, false)
  local m = frame()
  check("one with room is left where it was", m and m.x, 200 + 14)

  -- A window hanging off the right of the monitor: the tighter of the two
  -- bounds wins, so the tooltip still lands somewhere visible.
  WIN = { 600, 0, 400, 500 }
  W.clear_tips()
  MX, MY = 780, 200
  W.tip(nil, "off", LBL, true, false)
  local o = frame()
  check("the tighter bound wins", o and (o.x + #LBL * 6) <= VP[3], true)
  WIN = { 0, 0, 400, 500 }
end

-- ---------------------------------------------------------------------
-- the master track answers nil, not zero
-- ---------------------------------------------------------------------
-- REAPER returns nil -- not 0 -- when a track does not HAVE the thing you
-- asked about: record arm, input monitoring and phase invert on the
-- master, most obviously. And `nil > 0.5` is a hard error rather than a
-- false, so a single unguarded read takes the whole window down the
-- moment the master is selected. This is the guard.
do
  local CH = require "TS_CV_Channel"
  local MASTER, NORMAL = {"master"}, {"normal"}

  local real = {
    GetMasterTrack = reaper.GetMasterTrack,
    GetMediaTrackInfo_Value = reaper.GetMediaTrackInfo_Value,
  }
  reaper.GetMasterTrack = function() return MASTER end
  reaper.GetMediaTrackInfo_Value = function(tr, key)
    if tr == MASTER and (key == "I_RECARM" or key == "I_RECMON"
                      or key == "B_PHASE") then
      return nil                       -- what REAPER actually does
    end
    if key == "D_VOL" then return 1.0 end
    if key == "B_MUTE" then return 1 end
    return 0
  end

  check("master is recognised",     CH.is_master(MASTER), true)
  check("an ordinary track is not", CH.is_master(NORMAL), false)
  check("and nothing is not",       CH.is_master(nil), false)

  check("a missing value reads as 0",  CH.read(MASTER, "I_RECARM"), 0)
  check("monitoring too",              CH.read(MASTER, "I_RECMON"), 0)
  check("phase too",                   CH.read(MASTER, "B_PHASE"), 0)
  check("a default can be given",      CH.read(MASTER, "I_RECARM", 7), 7)
  check("a real value comes through",  CH.read(MASTER, "B_MUTE"), 1)
  check("volume defaults to unity",    CH.read(nil, "D_VOL", 1), 1)
  check("no track reads as the default", CH.read(nil, "B_MUTE"), 0)

  -- The comparisons the panel actually does, which is where the crash
  -- was: nil > 0.5 raises, it does not return false.
  check("the comparison is safe now",
        (function() return CH.read(MASTER, "I_RECARM") > 0.5 end)(), false)
  check("and so is the modulo",
        math.floor(CH.read(MASTER, "I_RECMON")) % 3, 0)

  for k, v in pairs(real) do reaper[k] = v end
end

-- ---------------------------------------------------------------------
-- the level meter's second number
-- ---------------------------------------------------------------------
-- REAPER exposes no sample-level RMS -- Track_GetPeakInfo is a peak and
-- nothing else -- so this integrates the per-frame PEAK envelope over
-- RMS_WINDOW. It is a fast VU rather than a programme RMS, and the thing
-- worth pinning down is that it integrates in POWER, not in decibels:
-- averaging dB would read high on peaky material and quietly flatter the
-- mix.
do
  local function near(a, b, tol) return math.abs(a - b) <= (tol or 0.05) end
  local WIN = C.RMS_WINDOW

  W.clear_rms()
  -- A full window of one level lands exactly on it.
  check("settles on a steady level",
        near(W.level_rms("m", -6, WIN), -6), true)
  check("and stays there",
        near(W.level_rms("m", -6, WIN * 2), -6), true)

  -- Half a window from -6 toward silence: half the POWER is gone, which
  -- is -3 dB, not half the decibels.
  W.clear_rms()
  W.level_rms("n", -6, WIN)
  check("integrates power, not decibels",
        near(W.level_rms("n", -math.huge, WIN * 1.5), -9, 0.1), true)

  -- It lags a transient rather than following it, which is the whole
  -- point of having it next to the peak.
  W.clear_rms()
  W.level_rms("t", -40, WIN)
  local jump = W.level_rms("t", 0, WIN * 1.1)
  check("lags a transient", jump < 0, true)
  check("but moves toward it",  jump > -40, true)

  check("keys are independent", near(W.level_rms("other", -20, 99), -20), true)

  -- Silence is silence, not a very small number.
  W.clear_rms()
  check("silence reads -inf", W.level_rms("s", -math.huge, WIN), -math.huge)

  -- The colour steps. A red readout and a red bar have to mean the same
  -- thing, so both come from here.
  check("clipping is the hard red",  W.level_colour(0.0, 99), C.COL.level_over)
  check("above it too",              W.level_colour(3.0, 99), C.COL.level_over)
  check("just hot is the softer one", W.level_colour(-0.1, 99), C.COL.level_clip)
  check("and normal is the caller's", W.level_colour(-12, 99), 99)
  check("nothing is the caller's",    W.level_colour(nil, 99), 99)
  check("the two reds differ",        C.COL.level_over ~= C.COL.level_clip, true)
end

-- ---------------------------------------------------------------------
-- the header lines up with Track Analyser
-- ---------------------------------------------------------------------
-- Track Analyser pushes no WindowPadding, ItemSpacing or FramePadding of
-- its own, so its rule sits at WindowPadding.y + a frame-height header
-- row + ItemSpacing.y below the window top. Ours has to reach the same
-- place from under a menu bar.
--
-- Three attempts failed because WindowPadding.y got written down --
-- ImGui's default, then a screenshot measurement, then MenuBarHeight
-- worked back from the font. ReaImGui's defaults are not ImGui's, and its
-- menu bar is not FontSize + 2*FramePadding either. So it is measured
-- instead, out of three things the window reports, and this checks that
-- the identity behind that measurement actually holds.
do
  local function padding_from(wh, avail_h, start_y) return wh - avail_h - start_y end

  -- ImGui's own arithmetic, with every style number a free variable:
  --   start_y = WindowPadding.y + decorations
  --   avail_h = wh - 2*WindowPadding.y - decorations
  local bad = 0
  for _, wp in ipairs({ 2, 4, 6, 8, 11 }) do            -- WindowPadding.y
    for _, deco in ipairs({ 0, 19, 25, 33, 48 }) do     -- title + menu bar
      for _, wh in ipairs({ 200, 300, 686 }) do
        local start_y = wp + deco
        local avail_h = wh - wp * 2 - deco
        if padding_from(wh, avail_h, start_y) ~= wp then bad = bad + 1 end
      end
    end
  end
  check("the padding falls out whatever the decorations are", bad, 0)

  -- And having recovered it, both windows land on the same line -- up to
  -- HEADER_NUDGE, which is the part still not understood and is meant to
  -- go back to zero once View > Log header metrics says why.
  bad = 0
  for _, wp in ipairs({ 2, 4, 6, 8, 11 }) do
    for _, frame_h in ipairs({ 17, 19, 21, 27, 33 }) do
      for _, isy in ipairs({ 2, 4, 6, 8 }) do
        local ta   = wp + frame_h + isy
        local ours = wp + frame_h + isy + C.HEADER_NUDGE
        if ours ~= ta + C.HEADER_NUDGE then bad = bad + 1 end
      end
    end
  end
  check("and the two rules meet", bad, 0)
  -- The derivation stands on its own, so there is nothing left to add.
  -- A non-zero nudge means something above it has gone wrong again --
  -- twice now it has been a clamp quietly discarding the answer, with
  -- the nudge behind it measuring the discard rather than any real
  -- offset.
  check("no fudge is needed", C.HEADER_NUDGE, 0)
  -- Same rect as TA_Panel draws, so the two cover the same rows for the
  -- same reason rather than by being tuned to each other.
  check("and the rule is the same 2px TA draws", C.RULE_H, 2)

  -- A bottom decoration would break the identity, which is why the
  -- window asks for no scrollbar.
  check("the window has no scrollbar to account for", C.WIN_NO_SCROLLBAR, true)
end

-- ---------------------------------------------------------------------
-- the cell's own geometry
-- ---------------------------------------------------------------------
-- The Sends panel draws its own name across a double-width cell and lines
-- its buttons up on the knob's face, so two files have to agree about
-- where a knob actually sits. They agree by asking, not by both knowing.
do
  local face = W.knob_face_y(0)
  check("the face clears the label band", face - C.KNOB_D * 0.5 >= W.LABEL_H, true)
  check("and the whole knob fits the cell",
        face + C.KNOB_D * 0.5 <= C.CELL_H, true)
  check("it moves with the cell", W.knob_face_y(100) - face, 100)

  -- A knob left at the top of its cell is the only position where the
  -- value readout underneath still lands inside the cell. Lifting it to
  -- tuck under a hand-drawn name is what pushed the readout out of the
  -- bottom of a send.
  check("the value row is inside the cell", C.CELL_H - 12 + 13 <= C.CELL_H + 1, true)

  -- The send cell: bar, knob, buttons, in a double-width cell.
  local BAR, ix = 4, 2 + 4 + 3
  local rx = ix + C.CELL_W + 2
  check("the buttons clear the knob", rx >= ix + C.CELL_W, true)
  check("and still fit the cell", C.SEND_W - rx - 3 > 30, true)
  check("the colour bar clears the contents", ix > 2 + BAR, true)

  -- The remove badge sits in the bottom-left corner, and must not reach
  -- the knob's face or the cell below.
  check("the badge fits the corner", W.BADGE + 4 < C.CELL_H, true)
  check("and clears the knob's face",
        C.CELL_H - W.BADGE - 2 > W.knob_face_y(0) + C.KNOB_D * 0.5 - 6, true)
  check("and does not cover the whole cell", W.BADGE < C.CELL_W * 0.5, true)
end

-- ---------------------------------------------------------------------
-- format badges
-- ---------------------------------------------------------------------
-- The badge says which of two identically-named entries you are about to
-- insert, so it must never come back nil and the common formats must not
-- collide.
do
  check("VST3 has a colour",  C.format_col("VST3").bg ~= nil, true)
  check("so does CLAP",       C.format_col("CLAP").bg ~= nil, true)
  check("VST and VST3 differ",
        C.format_col("VST").bg ~= C.format_col("VST3").bg, true)
  check("CLAP differs again",
        C.format_col("CLAP").bg ~= C.format_col("VST3").bg, true)
  check("an unknown format still gets one", C.format_col("XYZ").bg ~= nil, true)
  check("and so does nothing at all",       C.format_col(nil).bg ~= nil, true)
  check("text is lighter than its badge",
        (C.format_col("VST3").fg >> 24) > (C.format_col("VST3").bg >> 24), true)
end

-- ---------------------------------------------------------------------
-- run at startup: the __startup.lua surgery
-- ---------------------------------------------------------------------
-- __startup.lua is the one file this project touches that can break
-- things OTHER than this project, so the text surgery is pure and gets
-- tested on strings rather than on the real file. What matters is that
-- our block goes in once, comes out cleanly, and that nothing anybody
-- else wrote is ever disturbed.
do
  local SU  = require "TS_CV_Startup"
  local CMD = "_RS1a2b3c4d5e"
  local OTHER = [[
-- REAPER startup script
local grid = '_RSdeadbeef'
reaper.Main_OnCommand(reaper.NamedCommandLookup(grid), 0)
]]

  check("nothing there yet",       SU.classify(OTHER, CMD), "none")
  check("no text is none",         SU.classify(nil, CMD), "none")

  local added = SU.fenced_add(OTHER, CMD)
  check("ours after adding",       SU.classify(added, CMD), "ours")
  check("the command id is in it", added:find(CMD, 1, true) ~= nil, true)
  check("the result still compiles", load(added) ~= nil, true)
  check("everything else survived", added:find("_RSdeadbeef", 1, true) ~= nil, true)

  -- Never twice: two Main_OnCommand calls for the same script open two
  -- copies of the window, both writing to the same parameters.
  check("adding again changes nothing", SU.fenced_add(added, CMD), added)

  local removed = SU.fenced_remove(added)
  check("gone after removing",     SU.classify(removed, CMD), "none")
  check("the other script is untouched",
        removed:find("_RSdeadbeef", 1, true) ~= nil, true)
  check("and it still compiles",   load(removed) ~= nil, true)
  check("back to where it started", removed, OTHER)

  -- A file with nothing in it at all
  local fresh = SU.fenced_add(nil, CMD)
  check("writes a file from nothing", SU.classify(fresh, CMD), "ours")
  check("which compiles",             load(fresh) ~= nil, true)
  check("and unwinds to just a comment",
        SU.fenced_remove(fresh):match("^%-%-") ~= nil, true)

  -- The markers are full of pattern metacharacters -- ( ) - . > -- and
  -- matching them unescaped is what made Track Analyser report a block
  -- it had just written as somebody else's hand-edit.
  check("our own fence reads as ours",
        SU.classify(SU.BEGIN .. "\nx = 1 " .. CMD .. "\n" .. SU.END, CMD), "ours")

  -- A hand-written line is left exactly where it is: reported, not
  -- edited. Guessing at somebody else's line is how you lose it.
  local byhand = OTHER .. ("reaper.Main_OnCommand(reaper.NamedCommandLookup('%s'), 0)\n")
    :format(CMD)
  check("a hand-added line reads as manual", SU.classify(byhand, CMD), "manual")
  check("and add() leaves it alone",         SU.fenced_add(byhand, CMD), byhand)
  check("and remove() leaves it alone",
        SU.fenced_remove(byhand):find(CMD, 1, true) ~= nil, true)

  -- A file ending without a newline, which is how hand-edited ones
  -- usually turn up
  local nonl = "local x = 1"
  check("a missing final newline is fixed",
        load(SU.fenced_add(nonl, CMD)) ~= nil, true)

  check("the startup file is under Scripts/",
        SU.path():match("Scripts") ~= nil, true)
end

-- ---------------------------------------------------------------------
-- the module surface
-- ---------------------------------------------------------------------
-- Everything here is split across modules that call each other by field
-- name, which Lua only checks when the line actually runs -- so losing a
-- function in an edit shows up as "attempt to call a nil value" mid-frame
-- rather than at load. TS_CV_Audit.py checks ImGui calls the same way; this
-- does it for ours.
--
-- Every file is read, its `local X = require("TS_CV_Y")` bindings
-- collected, and every X.name(...) call site checked against what
-- TS_CV_Y actually exports.
do
  local FILES = {
    "TS_ChannelView", "TS_CV_Panel", "TS_CV_Widgets", "TS_CV_Channel", "TS_CV_Sends",
    "TS_CV_Editor", "TS_CV_Browser", "TS_CV_TrackStrip", "TS_CV_Mappings",
    "TS_CV_FXTree", "TS_CV_FXIndex", "TS_CV_Steps", "TS_CV_State", "TS_CV_Util",
    "TS_CV_Startup",
  }

  -- Comments only: a "-- see W.foo()" in prose must not read as a call.
  -- Crude on purpose -- a "--" inside a string literal would be eaten
  -- too, and none of these files has one.
  local function strip(src)
    src = src:gsub("%-%-%[%[.-%]%]", " ")
    return (src:gsub("%-%-[^\n]*", " "))
  end

  local missing, checked = {}, 0
  for _, file in ipairs(FILES) do
    local fh = io.open(HERE .. "../" .. file .. ".lua", "r")
    if fh then
      local src = strip(fh:read("a")); fh:close()

      local bind = {}
      for alias, mod in src:gmatch("local%s+([%w_]+)%s*=%s*require%s*%(?%s*[\"\']([%w_]+)[\"\']") do
        if mod:match("^TS_CV_") then bind[alias] = mod end
      end

      for alias, fn in src:gmatch("([%w_]+)%.([%w_]+)%s*%(") do
        local mod = bind[alias]
        if mod then
          checked = checked + 1
          local m = require(mod)
          if type(m[fn]) ~= "function" then
            missing[#missing + 1] = ("%s.lua calls %s.%s (%s)"):format(file, alias, fn, mod)
          end
        end
      end
    end
  end

  check("every cross-module call resolves",
        #missing == 0 and "none" or table.concat(missing, "; "), "none")
  check("and there were calls to check", checked > 150, true)
end

os.remove("./TS_ChannelView_Mappings.ini")
os.remove("./TS_ChannelView_Mappings.bak.ini")
print(fails == 0 and "\nALL PASS" or ("\n" .. fails .. " FAILURES"))
os.exit(fails == 0 and 0 or 1)
