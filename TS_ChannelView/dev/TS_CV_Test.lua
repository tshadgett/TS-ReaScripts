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
  { param = 4, type = "toggle", bipolar = false, label = "",
    invert = true },
  { param = -1,type = "blank",  bipolar = false, label = ""          },
  { param = 7, type = "knob",   bipolar = true,  label = "Both",
    invert = true },
} })
M.save()
M.reload()
local back = M.get(key)
check("round-trip count",   #back.controls, 5)
check("round-trip param",   back.controls[2].param, 5)
check("round-trip bipolar", back.controls[2].bipolar, true)
check("pipe stripped",      back.controls[2].label, "Pan   wide")
check("round-trip blank",   back.controls[4].type, "blank")
check("saved is not default", select(2, M.get_or_default(key, nil, 0, "g1")), false)

-- Reverse rides in the same field as bipolar, as bit 1. The two are
-- independent, and neither must leak into the other.
check("round-trip reverse",        back.controls[3].invert, true)
check("reverse alone is not centred", back.controls[3].bipolar, false)
check("centred alone is not reversed", back.controls[2].invert, false)
check("both together survive",
      back.controls[5].bipolar and back.controls[5].invert, true)
check("neither is neither",
      back.controls[1].bipolar == false and back.controls[1].invert == false, true)
check("and M.copy carries it", M.copy(back).controls[3].invert, true)

-- Bit 2, no_rule (a divider's line, off), must survive both the ini
-- round trip and M.copy. M.copy's own field list has to be kept in sync
-- with every control flag, since it is used both when the editor
-- scratch-copies a layout and when the save path copies it -- a flag
-- missing from that list is silently dropped on every copy, not just on
-- disk.
do
  local dkey = "DividerLine"
  M.set(dkey, { controls = {
    { param = -1, type = "divider", no_rule = true  },
    { param = -1, type = "divider", no_rule = false },
  } })
  M.save()
  M.reload()
  local dback = M.get(dkey)
  check("round-trip no_rule true",  dback.controls[1].no_rule, true)
  check("round-trip no_rule false", dback.controls[2].no_rule, false)
  check("M.copy carries no_rule true",  M.copy(dback).controls[1].no_rule, true)
  check("M.copy carries no_rule false", M.copy(dback).controls[2].no_rule, false)
  M.remove(dkey); M.save(); M.reload()
end

-- "stepped" (a knob quantised to the parameter's own step grid, an
-- alternative to combo's dropdown -- see TS_CV_Widgets.W.knob's
-- step_norm) is a brand new TYPE name, not a flag on an existing one.
-- VALID_TYPE and M.copy both have to recognise it, or it silently
-- downgrades to a plain knob instead of surviving the round trip.
do
  local skey = "SteppedType"
  M.set(skey, { controls = { { param = 2, type = "stepped", label = "Slope" } } })
  M.save()
  M.reload()
  local sback = M.get(skey)
  check("round-trip stepped type",   sback.controls[1].type, "stepped")
  check("M.copy carries stepped type", M.copy(sback).controls[1].type, "stepped")
  M.remove(skey); M.save(); M.reload()
end

-- Live names survive the ini: the layout's Live=1 and a slot's flag bit,
-- alongside the other flag bits rather than instead of them.
do
  local lkey = "LiveNames"
  M.set(lkey, { live = true, controls = {
    { param = 0, type = "knob", label = "Macro 1", live = true, invert = true },
    { param = 1, type = "knob", label = "Macro 2", bipolar = true } } })
  M.save()
  M.reload()
  local b = M.get(lkey)
  check("round-trip layout live",        b.live, true)
  check("round-trip slot live",          b.controls[1].live, true)
  check("  reverse kept beside it",      b.controls[1].invert, true)
  check("  label kept, just not shown",  b.controls[1].label, "Macro 1")
  check("other slot not live",           b.controls[2].live, false)
  check("  centred kept",                b.controls[2].bipolar, true)
  M.set(lkey, { controls = { { param = 0, type = "knob", label = "X" } } })
  M.save()
  M.reload()
  check("live off stays off",            M.get(lkey).live, nil)
  M.remove(lkey); M.save(); M.reload()
end

-- Input/output meters (Levels=1) survive the ini, beside Measure=1, and
-- either one marks the library as having something to measure.
do
  local k = "LevelsPlug"
  M.set(k, { levels = true, measure = true, controls = {} })
  M.save(); M.reload()
  check("round-trip levels",             M.get(k).levels, true)
  check("  measure beside it",           M.get(k).measure, true)
  check("copy keeps levels",             M.copy(M.get(k)).levels, true)
  M.set(k, { levels = true, controls = {} })
  M.save(); M.reload()
  check("levels alone counts as measuring", M.any_measure(), true)
  M.remove(k); M.save(); M.reload()
end

-- Type names may contain underscores (e.g. half_gap); the ini line
-- parser must accept those, not just plain letters. This has to
-- round-trip through an actual save+reload, since M.set/M.get never
-- touch the ini parser and so would not catch a parser regression here.
do
  local hkey = "HalfGapType"
  M.set(hkey, { controls = { { param = -1, type = "half_gap", label = "" },
                             { param = 3, type = "knob", label = "After" } } })
  M.save()
  M.reload()
  local hback = M.get(hkey)
  check("half_gap control survives save+reload", hback.controls[1] and hback.controls[1].type, "half_gap")
  check("the control after it survives too",      hback.controls[2] and hback.controls[2].type, "knob")
  M.remove(hkey); M.save(); M.reload()
end

-- Bit 0 keeps its meaning, so a layout written without reverse reads
-- back unchanged. This is that shape, hand-written into the library the
-- way an existing file has it.
do
  local old_key = "OldFormat"
  M.set(old_key, { controls = { { param = 1, type = "knob", label = "x" } } })
  M.save()
  local raw = io.open(M.file_path(), "rb"):read("a")
  raw = raw:gsub("%[OldFormat%]\r?\n[^\n]*", "[OldFormat]\nCtl0=3|knob|1|x")
  local f = io.open(M.file_path(), "wb"); f:write(raw); f:close()
  M.reload()
  local o = M.get(old_key).controls[1]
  check("an old layout still reads as centred", o.bipolar, true)
  check("and is not silently reversed",         o.invert, false)
  M.remove(old_key); M.save(); M.reload()
end

-- panel geometry: fixed height, grows in columns. Measured without the
-- panel's foot; the foot's own cost is checked just below.
do
  local CC = require("TS_CV_Config")
  CC.PRESET_BAR = true
  local with_bar = P.rows_for(300 + CC.FOOTER_H)
  CC.PRESET_BAR = false
  check("foot: there with the preset bar off too (the lock)", P.rows_for(300 + CC.FOOTER_H), with_bar)
  check("foot: its height comes off the body", P.footer_h(), CC.FOOTER_H)
  CC.FOOTER_H = 0        -- the rest of the geometry, without it
  check("foot: none, for the checks below", P.rows_for(300), 4)
end
local function n_knobs(n)
  local out = {}
  for i = 1, n do out[i] = { type = "knob" } end
  return out
end
local function cols_for(n, h)
  return P.layout(n_knobs(n), h).width / C.CELL_W
end

local H = 300   -- panel height incl. header
check("rows at h=300", P.rows_for(H), 4)
check("cols for 8 @4 rows", cols_for(8, H), 2)
-- 2 columns is 116px of cells, but a header needs PANEL_MIN_W, so the
-- panel is padded out to that.
check("width for 8", P.width(8, H), 132)
check("width for 12", P.width(12, H), 3 * C.CELL_W + 12)
check("cols for 9 @4 rows", cols_for(9, H), 3)
check("min width honoured", P.width(1, H), 132)
-- the Rack view: the fewest rows that lay a grid across the column
do
  local ctl = {}
  for i = 1, 12 do ctl[i] = { type = "knob", param = i - 1 } end
  local function ph(n) return C.HEADER_H + P.footer_h() + C.GRID_TOP_PAD + C.PANEL_PAD + n * C.CELL_H end
  local cols = function(w) return math.floor((w - C.PANEL_PAD * 2) / C.CELL_W) end
  for _, w in ipairs({ 200, 300, 700 }) do
    local n = math.ceil(12 / cols(w))
    local got
    for k = 1, 40 do if P.width(ctl, ph(k)) <= w then got = ph(k) break end end
    check("rack grid " .. w .. ": rows as the width needs", got, ph(n))
  end
  check("rack canvas height, narrow", P.rack_canvas_h(300), 240)
  check("rack canvas height, wide", P.rack_canvas_h(2000), 384)
  local TRP = require("TS_CV_TrimmerPanel")
  check("rack trimmer side by side", TRP.one_column(TRP.rack_body_h(600)), false)
  check("rack trimmer stacked", TRP.one_column(TRP.rack_body_h(400)), true)
  -- never fewer rows than the tallest control needs
  check("rack: knobs need a row", P.tallest_rows({ { type = "knob" }, { type = "toggle" } }), 1)
  check("rack: a large knob needs two", P.tallest_rows({ { type = "knob", size = "large" } }), 2)
  check("rack: a fader its length", P.tallest_rows({ { type = "fader", len = 3 } }), 3)
  check("rack: a full-height fader two", P.tallest_rows({ { type = "fader" } }), 2)
  check("rack: an across fader none", P.tallest_rows({ { type = "fader", dir = "h" } }), 1)
  -- the rows a layout fills in ChannelView: two sections of four, in a
  -- window ten rows tall, fill four
  local was = P.RACK_ROWS
  local two = { { type = "divider" } }
  for i = 1, 4 do two[#two + 1] = { type = "knob", param = i } end
  two[#two + 1] = { type = "divider" }
  for i = 5, 8 do two[#two + 1] = { type = "knob", param = i } end
  P.RACK_ROWS = 10
  check("rack: the rows ChannelView fills", P.cv_rows_used(two), 4)
  P.RACK_ROWS = 3
  check("rack: no more than ChannelView has", P.cv_rows_used(two), 3)
  P.RACK_ROWS = 10
  check("rack: shared layout", P.rack_from_rows(two, true), 4)
  check("rack: rack-only layout", P.rack_from_rows(two, false), P.tallest_rows(two))
  P.RACK_ROWS = nil
  check("rack: not known", P.cv_rows_used(two), 1)
  P.RACK_ROWS = was
end

-- grids: placed where they say, flowing in units (sections, and runs of
-- controls on none) where they don't fit
do
  local QX, QY = P.qx, P.qy
  local function ph(n) return C.HEADER_H + P.footer_h() + C.GRID_TOP_PAD + C.PANEL_PAD + n * C.CELL_H end
  local function K(c, r, extra)
    local k = { type = "knob", param = c, at = { c = c, r = r, w = 4, h = 4 } }
    for kk, v in pairs(extra or {}) do k[kk] = v end
    return k
  end
  -- two sections: four knobs 2 x 2, a divider, a knob over a fader
  local g = { K(0, 0), K(0, 4), K(4, 0), K(4, 4),
              { type = "divider", at = { c = 8.5, r = 0, w = 0, h = 8 } },
              K(9, 0), { type = "fader", param = 20, at = { c = 13, r = 0, w = 4, h = 8 } },
              { type = "section", at = { c = 0, r = 0, w = 8, h = 8 } },
              { type = "section", at = { c = 9, r = 0, w = 8, h = 8 } } }
  g.grid = { cols = 17, rows = 8 }
  check("grid: is one", P.is_grid(g), true)
  check("grid: size", table.concat({ P.grid_size(g) }, "x"), "17x8")
  local lay = P.layout(g, ph(2))
  check("grid: fits, as it is", lay.items[3].x .. "," .. lay.items[3].y, QX(4) .. ",0")
  check("grid: width and height", lay.width .. "/" .. lay.height, QX(17) .. "/" .. QY(8))
  check("grid: the divider a line", #lay.segs .. ":" .. lay.segs[1].x1 .. "-" .. lay.segs[1].y2, "1:" .. QX(8.5) .. "-" .. QY(8))
  check("grid: a section with no background drawn as nothing", #lay.sections, 0)
  local us = P.units_of(g)
  check("grid: units, a section and what's on it", #us .. " " .. #us[1].list .. " " .. #us[2].list, "2 5 3")
  check("grid: a fader fills its place", lay.items[6].kind .. " " .. lay.items[6].h, "vfader 4")
  check("grid: items in list order", lay.items[5].ctl == g[6], true)
  -- one row: the first unit (two rows) and the second (two) both flow
  local l1 = P.layout(g, ph(1))
  check("grid: too short flows", l1.height, C.CELL_H)
  check("grid: first section down then across", l1.items[2].x .. "," .. l1.items[2].y, C.CELL_W .. ",0")
  check("grid: locked, as it is", P.layout(g, ph(1), 1).height, QY(8))
  -- a unit that fits keeps its arrangement and moves along; a line on no
  -- section between two units is drawn between them still
  local g2 = { K(0, 0), K(0, 4), { type = "divider", at = { c = 4.5, r = 0, w = 0, h = 8 } }, K(5, 0) }
  g2.grid = { cols = 9, rows = 8 }
  local l2 = P.layout(g2, ph(1))
  check("grid: controls on no section flow together", l2.items[3].x .. "," .. #l2.segs, (2 * C.CELL_W) .. ",0")
  g2[#g2 + 1] = { type = "section", at = { c = 0, r = 0, w = 4, h = 8 } }
  g2[#g2 + 1] = { type = "section", style = "inset", at = { c = 5, r = 0, w = 4, h = 4 } }
  l2 = P.layout(g2, ph(1))
  check("grid: sections, the tall one flows", l2.items[2].x .. "," .. l2.items[2].y, C.CELL_W .. ",0")
  check("grid: the next moves along", l2.items[3].x, 2 * C.CELL_W + QX(1))
  check("grid: the line between them too", l2.segs[1].x1, 2 * C.CELL_W + QX(0.5))
  check("grid: its background with it", l2.sections[1].x .. "," .. l2.sections[1].w, (2 * C.CELL_W + QX(1)) .. "," .. QX(4))
  -- a section inside another goes with it
  local nest = { K(0, 0), { type = "section", at = { c = 0, r = 0, w = 8, h = 8 } }, { type = "section", at = { c = 0, r = 0, w = 4, h = 4 } } }
  check("grid: a section on a section is on it", #P.units_of(nest) .. " " .. #P.units_of(nest)[1].list, "1 3")
  -- the rack: narrower than the grid, units wrap whole
  local lw = P.layout_w(g, QX(9))
  check("rack grid: second section on a new line", lw.items[5].x .. "," .. lw.items[5].y, "0," .. (QY(8) + QY(1)))
  check("rack grid: as it is when it fits", P.layout_w(g, QX(17)).height, QY(8))
  check("rack grid: locked, as it is", P.layout_w(g, QX(9), 1).width, QX(17))
  check("rack grid: not a grid", P.layout_w({ { type = "knob" } }, 100), nil)
  -- a unit wider than the column: across then down
  local wide = { K(0, 0), K(4, 0), K(8, 0), K(12, 0) }
  local lw2 = P.layout_w(wide, QX(8))
  check("rack grid: too wide, across then down", lw2.items[3].x .. "," .. lw2.items[3].y, "0," .. QY(4))
  check("rack grid: its height", lw2.height, QY(8))
  -- a knob smaller than its place sits in the middle of it
  local big = { K(0, 0) }
  big[1].at.w, big[1].at.h = 6, 6
  local lb = P.layout(big, ph(3))
  check("grid: medium knob centred in 6x6", lb.items[1].x .. "," .. lb.items[1].w, ((QX(6) - C.CELL_W) / 2) .. ",2")
  big[1].size = "large"
  check("grid: a large knob fills it", P.layout(big, ph(3)).items[1].w, 3)
  -- a section: a rectangle, and its inks for what's on it
  local sg = { { type = "section", style = "inset", at = { c = 0, r = 0, w = 8, h = 4 } }, K(0, 0), K(4, 0), K(8, 0) }
  local ls = P.layout(sg, ph(2))
  check("grid: a section's rectangle", ls.sections[1].w .. "x" .. ls.sections[1].h .. "@" .. ls.sections[1].y, QX(8) .. "x" .. QY(4) .. "@0")
  check("grid: on it, and not", tostring(ls.items[1].sec) .. tostring(ls.items[3].sec), "1nil")
  -- a line any way: diagonal, drawn from either end
  local dg = { K(0, 0), { type = "divider", at = { c = 4, r = 8, w = 4, h = -8 } } }
  check("grid: a line's far end counts", table.concat({ P.grid_size(dg) }, "x"), "8x8")
  local ld = P.layout(dg, ph(2))
  check("grid: a line drawn any way", ld.segs[1].x1 .. "," .. ld.segs[1].y1 .. ">" .. ld.segs[1].x2 .. "," .. ld.segs[1].y2,
    QX(4) .. "," .. QY(8) .. ">" .. QX(8) .. ",0")
  check("grid: a line's place read back", M.at_line(M.at_of("4,8,4,-8", true)) .. " " .. tostring(M.at_of("4,8,4,-8")), "4,8,4,-8 nil")
  check("grid: a line going off the grid", M.at_of("4,8,-5,0", true), nil)
  -- a section with an outline and no background: drawn, gives no inks
  local eg = { { type = "section", edge = "#ff0000", at = { c = 0, r = 0, w = 8, h = 4 } }, K(0, 0) }
  local le = P.layout(eg, ph(2))
  check("grid: an outline alone drawn", #le.sections .. " " .. tostring(le.items[1].sec), "1 nil")
  -- a control with no place yet goes under the grid
  local np = { K(0, 0), { type = "knob", param = 9 } }
  P.layout(np, ph(3))
  check("grid: a new control placed under it", np[2].at.c .. "," .. np[2].at.r, "0,4")
  -- making one from a layout without a grid
  local flat = { controls = {
    { type = "knob", param = 0 }, { type = "knob", param = 1 }, { type = "knob", param = 2 }, { type = "knob", param = 3 },
    { type = "divider", style = "inset" },
    { type = "knob", param = 4 }, { type = "blank", back = "inset" }, { type = "knob", param = 5 },
  } }
  local before = P.layout(flat.controls, ph(2))
  check("to grid: made", P.to_grid(flat, 2), true)
  check("to grid: not twice", P.to_grid(flat, 2), false)
  local fc = flat.controls
  check("to grid: knobs where they were", fc[3].at.c .. "," .. fc[3].at.r .. " " .. fc[4].at.c .. "," .. fc[4].at.r, "4,0 4,4")
  check("to grid: the divider down its gap", fc[5].at.c .. "/" .. fc[5].at.w .. "/" .. fc[5].at.h, "8.5/0/8")
  check("to grid: its section after it", fc[6].type .. " " .. fc[6].style .. " " .. fc[6].at.c .. "," .. fc[6].at.w, "section inset 9,8")
  check("to grid: the divider unstyled", fc[5].style, nil)
  check("to grid: a gap's background a section", fc[8].type .. " " .. fc[8].at.c .. "," .. fc[8].at.r, "section 9,4")
  check("to grid: last knob", fc[9].at.c .. "," .. fc[9].at.r, "13,0")
  check("to grid: size", flat.grid.cols .. "x" .. flat.grid.rows, "17x8")
  check("to grid: what the divider kept together a section", fc[10].type .. " " .. tostring(fc[10].style) .. " " .. M.at_line(fc[10].at), "section nil 0,0,8,8")
  check("to grid: not where one was already", fc[11], nil)
  local after = P.layout(flat.controls, ph(2))
  check("to grid: the first block as it was", after.items[4].x .. "," .. after.items[4].y, before.items[4].x .. "," .. before.items[4].y)
  -- the file
  local gk = "GridPlug"
  M.set(gk, { grid = { cols = 17, rows = 8 }, controls = {
    { param = 0, type = "knob", label = "", at = { c = 0, r = 0, w = 4, h = 4 } },
    { param = -1, type = "divider", label = "", at = { c = 8.5, r = 0, w = 0, h = 8 } },
    { param = -1, type = "section", label = "", style = "plate", cap = "cream", corners = "soft",
      at = { c = 9, r = 0, w = 8, h = 8 }, edge = "#FF8800" },
    { param = -1, type = "divider", label = "", at = { c = 0, r = 8, w = 8, h = -8 }, edge = "cream" } } })
  M.save(); M.reload()
  local gb = M.get(gk)
  check("grid file: a section's outline", gb.controls[3].edge, "#ff8800")
  -- words anywhere on the grid, and a short dropdown
  M.set("GridText", { grid = { cols = 16, rows = 8 }, controls = {
    { param = -1, type = "text", label = "COMPRESSOR", size = "large", align = "left", edge = "#d0a060",
      at = { c = 0, r = 0, w = 12, h = 2 } },
    { param = -1, type = "text", label = "INPUT", at = { c = 14, r = 0, w = 2, h = 8 } },
    { param = 3, type = "combo", label = "Mode", at = { c = 0, r = 2, w = 8, h = 2 } },
    { param = 4, type = "combo", label = "Type", at = { c = 0, r = 4, w = 8, h = 4 } } } })
  M.save(); M.reload()
  local gt = M.get("GridText").controls
  check("text: read back", table.concat({ gt[1].type, gt[1].label, gt[1].size, gt[1].align, gt[1].edge }, " "),
        "text COMPRESSOR large left #d0a060")
  check("text: centred and normal without lines", tostring(gt[2].align) .. " " .. tostring(gt[2].size), "nil nil")
  check("text: copied", M.copy({ controls = gt }).controls[1].align, "left")
  local lt = P.layout(gt, ph(2))
  check("text: drawn as words, not controls", #lt.texts .. " " .. #lt.items, "2 2")
  check("text: up when taller than wide", lt.texts[2].h > lt.texts[2].w, true)
  check("combo: half a cell tall is short", tostring(lt.items[1].short) .. " " .. tostring(lt.items[2].short), "true nil")
  M.remove("GridText"); M.save(); M.reload()
  check("grid file: a line any way", M.at_line(gb.controls[4].at), "0,8,8,-8")
  check("grid file: a line's colour, a faceplate's", gb.controls[4].edge, "cream")
  check("grid file: drawn in it", P.layout(gb.controls, ph(2)).segs[2].col, C.PLATE.cream.bg)
  check("grid file: Grid", gb.grid.cols .. "x" .. gb.grid.rows, "17x8")
  check("grid file: on the controls too", gb.controls.grid == gb.grid, true)
  check("grid file: At", M.at_line(gb.controls[2].at), "8.5,0,0,8")
  check("grid file: a section and its style", gb.controls[3].type .. " " .. gb.controls[3].style .. " " .. gb.controls[3].cap .. " " .. gb.controls[3].corners, "section plate cream soft")
  check("grid file: copied", M.copy(gb).controls[2].at.c .. " " .. M.copy(gb).grid.cols .. " " .. M.copy(gb).controls.grid.rows, "8.5 17 8")
  check("grid file: is_grid", M.is_grid(gb), true)
  check("grid file: bad At", M.at_of("1,2,x,4"), nil)
  M.remove(gk); M.save()
end

-- the grid editor: shown as a grid, saved with the first change, undone
do
  local GE = require("TS_CV_GridEditor")
  local T = GE._t
  local key = "GridEdPlug"
  M.set(key, { controls = { { param = 0, type = "knob", label = "" }, { param = 1, type = "knob", label = "" },
                            { param = -1, type = "divider", label = "" }, { param = 2, type = "knob", label = "" } } })
  M.save()
  GE.open({}, { addr = 0, guid = "ge1", name = "VST: GridEd" }, key, M.get(key), 4, { rows = 1 })
  check("grid editor: shown as a grid", T.cur().grid ~= nil, true)
  check("grid editor: made a grid as it opened", M.get(key).grid ~= nil, true)
  check("grid editor: the control it opened on", T.sel(), 4)
  local c = T.cur().controls[1]
  T.edit(function() c.at.r = 4 end)
  check("grid editor: the move saved", M.get(key).controls[1].at.r, 4)
  check("grid editor: the grid grew", M.get(key).grid.rows, 8)
  T.undo()
  check("grid editor: undo the move", M.get(key).controls[1].at.r, 0)
  T.undo()
  check("grid editor: undo, as it was before it opened", M.get(key).grid, nil)
  T.redo(); T.redo()
  check("grid editor: redo", M.get(key).controls[1].at.r, 4)
  -- the sheet's changes: on the grid being edited, saved by watch, one step
  T.cur().controls[1].label = "Dr"
  T.watch()
  check("grid editor: a sheet change saved", M.get(key).controls[1].label, "Dr")
  T.cur().controls[1].label = "Drive"
  T.watch()
  check("grid editor: typing goes on saving", M.get(key).controls[1].label, "Drive")
  T.undo()
  check("grid editor: typing is one step", M.get(key).controls[1].label, "")
  T.redo()
  -- changed elsewhere (a menu of the panel's): shown, and a step too
  local lib = M.get(key)
  lib.controls[2].back = "inset"
  M.set(key, lib)
  T.sync()
  check("grid editor: a change elsewhere shown", T.cur().controls[2].back, "inset")
  T.undo()
  check("grid editor: and undone", M.get(key).controls[2].back, nil)
  check("grid editor: the label kept", M.get(key).controls[1].label, "Drive")
  check("grid editor: no going on another", T.free(0, 4, 4, 4, nil), false)
  check("grid editor: room beside it", T.free(4, 4, 4, 4, nil), true)
  local k = { type = "knob" }
  check("grid editor: a knob dragged big", table.concat({ T.fit(k, 7, 7) }, "x") .. tostring(k.size), "6x6large")
  check("grid editor: dragged flat, small", table.concat({ T.fit(k, 4, 2) }, "x") .. tostring(k.size), "4x2small")
  check("grid editor: back to medium", table.concat({ T.fit(k, 4, 4) }, "x") .. tostring(k.size), "4x4nil")
  local f = { type = "fader" }
  check("grid editor: a fader dragged wide", table.concat({ T.fit(f, 10, 3) }, "x") .. tostring(f.dir), "10x3h")
  T.insert("col", 0)
  check("grid editor: a column inserted", T.cur().controls[1].at.c .. " " .. T.cur().controls[3].at.c, "4 12.5")
  T.delete("col", 0)
  check("grid editor: and deleted", T.cur().controls[1].at.c .. " " .. T.cur().controls[3].at.c, "0 8.5")
  T.delete("col", 8)
  -- (the two sections are what the divider kept together, made as it opened)
  check("grid editor: a column, its control and divider gone", #T.cur().controls, 4)
  T.fit_grid()
  check("grid editor: fitted to what's on it", M.get(key).grid.cols .. "x" .. M.get(key).grid.rows, "9x8")
  T.add(5)
  local added = M.get(key).controls[#M.get(key).controls]
  check("grid editor: added where it first fits", added.param .. " " .. M.at_line(added.at), "5 0,0,4,4")
  T.add(5)
  check("grid editor: not twice", #M.get(key).controls, 5)
  GE.close()
  M.remove(key); M.save()
end
-- a canvas layout's controls beside it: a grid too, edited in the grid editor
do
  local GE = require("TS_CV_GridEditor")
  local T = GE._t
  local key = "GridCanvasPlug"
  M.set(key, { canvas = { kind = "eq", bands = {} }, controls = { { param = 0, type = "knob", label = "" },
                                                                   { param = 1, type = "knob", label = "" } } })
  M.save()
  GE.open({}, { addr = 0, guid = "ge3", name = "VST: GridCanvas" }, key, M.get(key), nil, { rows = 2 })
  local l = M.get(key)
  check("canvas grid: made a grid as it opened", M.is_grid(l), true)
  check("canvas grid: the canvas kept", l.canvas and l.canvas.kind, "eq")
  check("canvas grid: its controls placed", M.at_line(l.controls[1].at) .. " " .. M.at_line(l.controls[2].at), "0,0,4,4 0,4,4,4")
  M.reload()
  check("canvas grid: read back", M.is_grid(M.get(key)) and M.get(key).canvas.kind, "eq")
  -- the canvas's own size: ChannelView's width, the rack's height
  local cl = M.get(key)
  cl.canvas.w, cl.canvas.h = 520, 300
  M.set(key, cl); M.save(); M.reload()
  local cv2 = M.get(key).canvas
  check("canvas size: read back", cv2.w .. "x" .. cv2.h, "520x300")
  check("canvas size: its width in ChannelView", require("TS_CV_MapPanel").width("eq", cv2), 520)
  check("canvas size: its height in the rack", P.rack_canvas_h(800, cv2) .. " " .. P.rack_canvas_h(800, nil), "300 384")
  check("canvas size: copied", M.copy(M.get(key)).canvas.w, 520)
  GE.close()
  M.remove(key); M.save()
end
-- a panel's style, onto another plugin's panel
do
  local src = { plate = "cream", brush = true, finish = "satin", controls = {
    { param = 0, type = "knob", style = "chicken", cap = "red", arc = "pos" },
    { param = 1, type = "knob", style = "chicken", cap = "red", arc = "pos" },
    { param = 2, type = "knob", style = "arc" },
    { param = 3, type = "toggle", style = "backlit", cap = "amber" },
    { param = 4, type = "combo", style = "raised", cap = "green" },
    { param = -1, type = "text", edge = "#ff0000", label = "Hi" } },
    canvas = { kind = "eq", bands = {}, cols = { curve = 0xff4a3a } } }
  local st = M.style_of(src)
  check("style: the faceplate", st.plate .. " " .. tostring(st.brush) .. " " .. st.finish, "cream true satin")
  check("style: most knobs' look", st.kinds.knob.style .. " " .. st.kinds.knob.cap, "chicken red")
  local dst = { controls = {
    { param = 7, type = "stepped", bipolar = true },
    { param = 8, type = "toggle", style = "lens" },
    { param = 9, type = "combo", buttons = "across", nbtn = 3, style = "lens" },
    { param = 10, type = "combo" },
    { param = -1, type = "text", label = "Yo" } }, canvas = { kind = "comp" } }
  local n = M.apply_style(dst, st)
  check("style: pasted onto", n, 4)
  check("style: knobs", dst.controls[1].style .. " " .. dst.controls[1].cap .. " " .. dst.controls[1].arc, "chicken red mid")
  check("style: buttons", dst.controls[2].style .. " " .. dst.controls[2].cap, "backlit amber")
  check("style: a button row has none on the source, its own kept", dst.controls[3].style, "lens")
  check("style: dropdowns", dst.controls[4].style .. " " .. dst.controls[4].cap, "raised green")
  check("style: text colour", dst.controls[5].edge, "#ff0000")
  check("style: faceplate and canvas colours", dst.plate .. " " .. tostring(dst.canvas.cols and dst.canvas.cols.curve), "cream " .. tostring(0xff4a3a))
end
-- REAPER's track spacer size (trackgapmax), for the mixer's spacers
do
  local real = reaper
  local t = 100
  reaper = setmetatable({ time_precise = function() return t end,
    get_config_var_string = function(k) if k == "trackgapmax" then return true, "23" end return false, "" end },
    { __index = real })
  check("spacer: REAPER's size", C.spacer_w(), 23)
  reaper = setmetatable({ time_precise = function() return t end,
    get_config_var_string = function() return false, "" end }, { __index = real })
  t = 110
  check("spacer: none set, 16", C.spacer_w(), 16)
  reaper = real
end
-- a value typed in (Ctrl+click a knob or fader)
do
  local CH_ = require("TS_CV_Channel")
  check("typed volume: -6 dB", math.abs(CH_.typed_vol("-6") - 10 ^ (-6 / 20)) < 1e-9, true)
  check("typed volume: -inf", CH_.typed_vol("-inf"), 0)
  check("typed volume: not a number", CH_.typed_vol("loud"), nil)
  check("typed pan", tostring(CH_.typed_pan("30L")) .. " " .. tostring(CH_.typed_pan("15r")) .. " " .. tostring(CH_.typed_pan("c")) .. " " .. tostring(CH_.typed_pan("-50")), "-0.3 0.15 0 -0.5")
  local UN_ = require("TS_CV_Units")
  local real = reaper
  local now = 0.5
  local function txt(n) local hz = 20 * 1000 ^ n; return hz >= 1000 and ("%.2f kHz"):format(hz / 1000) or ("%.1f Hz"):format(hz) end
  reaper = setmetatable({
    TrackFX_GetFormattedParamValue = function() return true, txt(now) end,
    TrackFX_FormatParamValueNormalized = function(_, _, _, n) return true, txt(n) end,
    TrackFX_GetFXGUID = function() return "{TYPETEST}" end,
  }, { __index = real })
  local n1 = UN_.typed_norm("tr", 0, 7, "2k")
  check("typed value: 2k on a frequency", n1 and txt(n1):sub(1, 4), "2.00")
  now = UN_.typed_norm("tr", 0, 7, "2k")
  local n2 = UN_.typed_norm("tr", 0, 7, "5")
  check("typed value: a bare number in the unit it shows (kHz)", n2 and txt(n2):sub(1, 4), "5.00")
  local n3 = UN_.typed_norm("tr", 0, 7, "300 Hz")
  check("typed value: with its unit", n3 and txt(n3):sub(1, 3), "300")
  reaper = real
end
-- an EQ curve on a grid: kept, and the canvas drawn there, not beside
do
  local key = "VST3: CurveTest :: EQ"
  M.set(key, { grid = { cols = 24, rows = 8 }, canvas = { kind = "eq", bands = {} }, aliases = {}, controls = {
    { param = 3, type = "knob", label = "", at = { c = 0, r = 0, w = 4, h = 4 } },
    { param = -1, type = "curve", label = "", at = { c = 4, r = 0, w = 16, h = 8 } } } })
  M.save(); M.reload()
  local l = M.get(key)
  check("curve: kept", l.controls[2] and l.controls[2].type, "curve")
  check("curve: its place", l.controls[2] and l.controls[2].at and (l.controls[2].at.w .. "x" .. l.controls[2].at.h), "16x8")
  check("curve: the layout has one", M.has_curve(l), true)
  local P_ = require("TS_CV_Panel")
  check("curve: no canvas beside the controls", P_.canvas_of(l) == nil, true)
  table.remove(l.controls, 2)
  check("curve: without one, the canvas beside", P_.canvas_of(l) ~= nil, true)
  M.remove(key); M.save()
end
-- Show when's choices for a list along a knob that reports no steps
-- (ValhallaDelay's Mode): read by name
do
  local E_ = require("TS_CV_Editor")
  local real = reaper
  local MODES = { "Tape", "HiFi", "BBD", "BBDuck", "Digital", "Ghost", "Pitch" }
  local function txt(n) return MODES[math.min(#MODES, math.floor(n * #MODES) + 1)] end
  reaper = setmetatable({
    TrackFX_GetParameterStepSizes = function() return false end,
    TrackFX_GetParamEx = function() return 0, 0, 1 end,
    TrackFX_FormatParamValueNormalized = function(_, _, p, n) if p == 32 then return true, txt(n) end return true, "" end,
    TrackFX_GetParamName = function(_, _, p) return true, "Mode" end,
    TrackFX_GetFormattedParamValue = function() return true, "Tape" end,
  }, { __index = real })
  local src = E_.show_sources("tr", 0, "VST3: ValTest", { { param = 32, type = "combo" }, { param = 25, type = "knob" } }, nil)
  check("show when: a list along a knob, by name", src[1] and (#src[1].choices .. " " .. src[1].choices[4].text) or "none", "7 BBDuck")
  -- a plugin that only says what it reads now (ValhallaDelay): moved
  -- through once and put back
  local now = 0.0417
  local V12 = { "Tape", "HiFi", "BBD", "BBDuck", "Digital", "Ghost", "Pitch", "Ratio", "Single", "Dual", "Rainbow", "RevSwell" }
  -- (wraps to the first at the very end, as Valhalla's does)
  local function vtxt(n) return V12[(math.floor(n * 12) % 12) + 1] end
  reaper = setmetatable({
    TrackFX_GetParameterStepSizes = function() return false end,
    TrackFX_GetParamEx = function() return 0, 0, 1 end,
    TrackFX_FormatParamValueNormalized = function() return true, vtxt(now) end,
    TrackFX_GetFormattedParamValue = function() return true, vtxt(now) end,
    TrackFX_GetParamNormalized = function() return now end,
    TrackFX_SetParamNormalized = function(_, _, _, v) now = v end,
    TrackFX_GetFXGUID = function() return "{VALTEST}" end,
    TrackFX_GetParamName = function() return true, "Mode" end,
    GetTrackAutomationMode = function() return 0 end,
    GetPlayState = function() return 0 end,
  }, { __index = real })
  local src2 = E_.show_sources("tr2", 1, "VST3: ValTest2", { { param = 32, type = "combo" } }, nil)
  local ch = src2[1] and src2[1].choices
  check("show when: read by moving it once", ch and (#ch .. " " .. ch[4].text) or "none", "12 BBDuck")
  check("show when: put back", now, 0.0417)
  local r = { param = 32, op = "is", norm = ch and ch[1].norm or 0, tol = src2[1] and src2[1].tol or 0 }
  check("show when: its setting now matches its first", M.show_match(0.0417, r), true)
  local P_ = require("TS_CV_Panel")
  local pl = P_.read_choices("tr2", 1, 32, "VST3: ValTest2")
  check("dropdown: a list from a plugin that only says what it reads now", pl and (#pl .. " " .. pl[2].text) or "none", "12 HiFi")
  check("dropdown: a step along it", P_.step_choice(pl, "Tape", 0.0417, 1, true) == pl[2].norm, true)
  reaper = real
end
-- several selected in the grid editor: aligned, spaced, copied, pasted,
-- their shared settings made on all
do
  local GE = require("TS_CV_GridEditor")
  local E_ = require("TS_CV_Editor")
  local T = GE._t
  local key = "GridMultiPlug"
  local v = E_.new_virtual("knob", {})
  v.at = { c = 0, r = 4, w = 4, h = 4 }
  M.set(key, { grid = { cols = 24, rows = 8 }, controls = {
    { param = 0, type = "knob", label = "", at = { c = 0, r = 0, w = 4, h = 4 } },
    { param = 1, type = "knob", label = "", at = { c = 5, r = 1, w = 4, h = 4 } },
    { param = 2, type = "knob", label = "", at = { c = 16, r = 2, w = 4, h = 4 } }, v } })
  M.save()
  GE.open({}, { addr = 0, guid = "ge4", name = "VST: GridMulti" }, key, M.get(key), nil, { rows = 2 })
  local function places()
    local t = {}
    for i = 1, 3 do t[i] = T.cur().controls[i].at.c .. "," .. T.cur().controls[i].at.r end
    return table.concat(t, " ")
  end
  T.select(1); T.pick(2); T.pick(3)
  check("multi: three picked", table.concat(T.picked(), ","), "1,2,3")
  T.toggle(2)
  check("multi: Ctrl+click takes one out", table.concat(T.picked(), ","), "1,3")
  T.pick(2)
  T.arrange("top")
  check("multi: aligned to the top", places(), "0,0 5,0 16,0")
  T.arrange("across")
  check("multi: spaced evenly across", places(), "0,0 8,0 16,0")
  T.undo()
  check("multi: undone in one step", places(), "0,0 5,0 16,0")
  T.arrange("left")
  check("multi: no room to align, nothing moved", places() .. " " .. tostring(T.warn() ~= nil), "0,0 5,0 16,0 true")
  T.arrange("bottom")
  check("multi: aligned to the bottom", places(), "0,0 5,0 16,0")
  -- shared settings: made on all
  local c = T.cur().controls[1]
  local before = T.deep(c)
  c.bipolar = true
  c.size = "small"
  T.spread(c, before, T.picked())
  check("multi: a setting made on all", tostring(T.cur().controls[2].bipolar) .. " " .. tostring(T.cur().controls[3].bipolar), "true true")
  check("multi: a size made on all, each its own size", T.cur().controls[3].size .. " " .. T.cur().controls[3].at.h, "small 2")
  -- copy and paste: a parameter on the panel isn't pasted, a virtual one is, renamed
  T.select(1); T.copy(); T.paste()
  check("multi: a parameter on the panel not pasted", tostring(T.warn() ~= nil) .. " " .. #T.cur().controls, "true 4")
  T.select(4); T.copy(); T.paste()
  local pasted = T.cur().controls[#T.cur().controls]
  check("multi: a virtual pasted, a name of its own", #T.cur().controls .. " " .. M.vname_of(pasted), "5 Amount 2")
  check("multi: pasted where it fits, selected", tostring(T.free(pasted.at.c, pasted.at.r, 4, 4, pasted)) .. " " .. table.concat(T.picked(), ","), "true 5")
  T.select(1); T.pick(5); T.remove()
  check("multi: both taken off", #T.cur().controls, 3)
  -- a line any way: its ends move with columns put in or taken out
  T.edit(function(l) l.controls[#l.controls + 1] = { param = -1, type = "divider", label = "", at = { c = 0, r = 8, w = 8, h = -8 } } end)
  local ln = function() return M.at_line(T.cur().controls[#T.cur().controls].at) end
  T.insert("col", 4)
  check("multi: a column in, the line's far end moves", ln(), "0,8,12,-8")
  T.delete("col", 4)
  check("multi: and out again", ln(), "0,8,8,-8")
  GE.close()
  M.remove(key); M.save()
end
-- copy from one plugin's layout, paste into another's: each control to
-- the parameter of the same name there (or your alias); Paste look
do
  local GE = require("TS_CV_GridEditor")
  local T = GE._t
  local NAMES = { [0] = { "Gain", "Ratio", "Attack", "Drive" }, [1] = { "Attack", "Mix", "gain", "Ratio" } }
  local gn, gp = reaper.TrackFX_GetNumParams, reaper.TrackFX_GetParamName
  reaper.TrackFX_GetNumParams = function(_, a) return #(NAMES[a] or {}) end
  reaper.TrackFX_GetParamName = function(_, a, p) local t = NAMES[a] or {}; return true, t[p + 1] or "" end
  M.set("CrossA", { grid = { cols = 24, rows = 8 }, aliases = { [1] = "Squash" }, controls = {
    { param = 0, type = "knob", label = "", style = "chicken", at = { c = 0, r = 0, w = 4, h = 4 } },
    { param = 1, type = "knob", label = "", at = { c = 4, r = 0, w = 4, h = 4 } },
    { param = 3, type = "knob", label = "", at = { c = 8, r = 0, w = 4, h = 4 } },
    { param = 2, type = "toggle", label = "", at = { c = 12, r = 0, w = 4, h = 2 } } } })
  M.set("CrossB", { grid = { cols = 24, rows = 8 }, controls = {
    { param = 1, type = "knob", label = "", at = { c = 0, r = 4, w = 4, h = 4 } } } })
  M.save()
  GE.open({}, { addr = 0, guid = "gx1", name = "VST: CrossA" }, "CrossA", M.get("CrossA"), nil, { rows = 2 })
  T.select(1); T.pick(2); T.pick(3); T.pick(4)
  T.copy()
  GE.open({}, { addr = 1, guid = "gx2", name = "VST: CrossB" }, "CrossB", M.get("CrossB"), nil, { rows = 2 })
  T.paste()
  local got = {}
  for _, c in ipairs(T.cur().controls) do got[#got + 1] = tostring(c.param) end
  check("cross paste: by name, case aside", table.concat(got, " "), "1 2 3 0")
  check("cross paste: the alias comes too", T.cur().aliases[3], "Squash")
  check("cross paste: the look kept", T.cur().controls[2].style, "chicken")
  check("cross paste: what isn't here, said", (T.warn() or ""):find("Drive", 1, true) ~= nil, true)
  -- several picked: the panel's menu can paste a style on them all
  T.select(1); T.pick(2)
  check("picked for the menu", table.concat(GE.picked_for("gx2", "CrossB") or {}, ","), "1,2")
  check("picked: not another instance's", tostring(GE.picked_for("other", "CrossB")), "nil")
  GE.close()
  reaper.TrackFX_GetNumParams, reaper.TrackFX_GetParamName = gn, gp
  M.remove("CrossA"); M.remove("CrossB"); M.save()
end
-- pages in the grid editor: added, controls moved onto one, reordered,
-- taken out again (what was on it put where it fits)
do
  local GE = require("TS_CV_GridEditor")
  local T = GE._t
  local St_ = require("TS_CV_State")
  local proj = {}
  local gp, sp = reaper.GetProjExtState, reaper.SetProjExtState
  reaper.GetProjExtState = function(_, _, k) return 1, proj[k] or "" end
  reaper.SetProjExtState = function(_, _, k, v) proj[k] = v end
  St_.clear_cache()
  M.set("PagePlug", { grid = { cols = 16, rows = 4 }, controls = {
    { param = 0, type = "knob", label = "", at = { c = 0, r = 0, w = 4, h = 4 } },
    { param = 1, type = "knob", label = "", at = { c = 4, r = 0, w = 4, h = 4 } },
    { param = 2, type = "knob", label = "", at = { c = 8, r = 0, w = 4, h = 4 } } } })
  M.save()
  GE.open({}, { addr = 0, guid = "gpg", name = "VST: PagePlug" }, "PagePlug", M.get("PagePlug"), nil, { rows = 2 })
  local function shape()
    local t = {}
    for _, c in ipairs(T.cur().controls) do
      t[#t + 1] = (c.type == "page") and ("|" .. (c.label or "")) or (tostring(c.param) .. "@" .. c.at.c .. "," .. c.at.r)
    end
    return table.concat(t, " ")
  end
  T.add_page()
  check("pages: a second, empty", shape(), "0@0,0 1@4,0 2@8,0 |")
  check("pages: and shown", St_.page("gpg"), 2)
  T.move_to_page({ 2 }, 2)
  check("pages: a control moved to it, where it fits", shape(), "0@0,0 2@8,0 | 1@0,0")
  T.cur().controls[3].label = "Two"
  T.move_page(2, 1)
  check("pages: reordered", shape(), "|Two 1@0,0 | 0@0,0 2@8,0")
  T.remove_page(1)
  check("pages: one taken out, its controls on the next where they fit, no tabs left", shape(), "1@4,0 0@0,0 2@8,0")
  check("pages: saved", #M.get("PagePlug").controls, 3)
  T.add_page()
  check("pages: the new page's break selected (the sheet's)", T.cur().controls[T.sel()].type, "page")
  T.remove()
  check("pages: Delete on a break takes its page out", shape(), "1@4,0 0@0,0 2@8,0")
  GE.close()
  reaper.GetProjExtState, reaper.SetProjExtState = gp, sp
  St_.clear_cache()
  M.remove("PagePlug"); M.save()
end
-- a value arc's own colour: kept, read back, copied
do
  M.set("ArcColPlug", { controls = {
    { param = 0, type = "knob", label = "", arc = "pos", arcc = "red" },
    { param = 1, type = "knob", label = "", arc = "mid", arcc = "#12ab34" },
    { param = 2, type = "toggle", label = "", arcc = "red" } } })
  M.save(); M.reload()
  local l = M.get("ArcColPlug")
  check("arc colour: read back", tostring(l.controls[1].arcc) .. " " .. tostring(l.controls[2].arcc), "red #12ab34")
  check("arc colour: knobs only", tostring(l.controls[3].arcc), "nil")
  check("arc colour: copied", M.copy(l).controls[1].arcc, "red")
  check("arc colour: in a copied style", M.look_of(l.controls[2]).arcc, "#12ab34")
  check("arc colour: junk ignored", tostring(M.arc_col_of("nonsense")), "nil")
  M.remove("ArcColPlug"); M.save()
end
check("rows at h=120", P.rows_for(120), 1)
check("cols for 8 @1 row", cols_for(8, 120), 8)

-- aliases: per-plugin parameter renames, independent of any panel slot
M.set_alias(key, 2, "Recovery")
M.set_alias(key, 5, "Width")
M.save(); M.reload()
check("alias round-trip",      M.get_alias(key, 2), "Recovery")
check("alias survives reload", M.get_alias(key, 5), "Width")
check("alias absent -> nil",   M.get_alias(key, 99), nil)
check("controls kept on alias write", #M.get(key).controls, 5)
check("display: slot label wins", M.display_name(key, 2, "Rec", "Release"), "Rec")
check("display: alias next",      M.display_name(key, 2, "",    "Release"), "Recovery")
check("display: plugin name last",M.display_name(key, 7, "",    "Ratio"),   "Ratio")
check("display: a label that's just the plugin's name lets the alias through",
      M.display_name(key, 2, "Release", "Release"), "Recovery")
do
  -- a toggle's state names
  M.set_states(key, 5, "Off", "Auto")
  check("state names: off",         M.state_text(key, 5, 0, "0.0"), "Off")
  check("state names: on",          M.state_text(key, 5, 1, "1.0"), "Auto")
  M.set_states(key, 5, "", "Auto")
  check("state names: one left empty keeps the plugin's", M.state_text(key, 5, 0, "0.0"), "0.0")
  local txt = M.serialise_for_test and M.serialise_for_test(key) or nil
  M.set_states(key, 5, "", "")
  check("state names: cleared",     M.get_states(key, 5), nil)
  check("state names: none set",    M.state_text(key, 9, 1, "1.0"), "1.0")
end
do
  -- a dropdown's choice names, keyed by the plugin's text
  M.set_choice_names(key, 3, { Opto = "Warm", ["Vocal Mode"] = "Vox", Clean = "", Punch = "Punch" })
  check("choice names: renamed",              M.choice_text(key, 3, "Opto"), "Warm")
  check("choice names: by its text, trimmed", M.choice_text(key, 3, " Vocal Mode "), "Vox")
  check("choice names: empty keeps the plugin's", M.choice_text(key, 3, "Clean"), "Clean")
  check("choice names: same as the plugin's isn't kept", M.get_choice_names(key, 3).Punch, nil)
  check("choice names: another parameter untouched", M.choice_text(key, 4, "Opto"), "Opto")
  local list = { { norm = 0, text = "Clean" }, { norm = 0.5, text = "Opto" }, { norm = 1, text = "Vocal Mode" } }
  local named = M.choice_list(key, 3, list)
  check("choice names: the list renamed",     named[1].text .. "/" .. named[2].text .. "/" .. named[3].text, "Clean/Warm/Vox")
  check("choice names: positions kept",       named[2].norm, 0.5)
  check("choice names: the plugin's list untouched", list[2].text, "Opto")
  check("choice names: the renamed list kept", M.choice_list(key, 3, list) == named, true)
  check("choice names: no names, the same list", M.choice_list(key, 4, list) == list, true)
  M.save(); M.reload()
  check("choice names: survive reload",       M.choice_text(key, 3, "Vocal Mode"), "Vox")
  check("choice names: copied",               M.copy(M.get(key)).choice_names[3].Opto, "Warm")
  check("choice names: line",                 M.choices_line({ ["A|B"] = "x=y", Q = "R" }), "A B=x y|Q=R")
  check("choice names: line read back, = in the plugin's text",
        M.choices_of_line("Q=1=Narrow|Q=2=Wide")["Q=2"], "Wide")
  check("choice names: an empty line, none", M.choices_of_line(""), nil)
  -- names that follow another control: a set for each of its settings
  do
    local real = reaper
    local bank = "Plates 1"
    reaper = setmetatable({ TrackFX_GetFormattedParamValue = function(_, _, q) return true, (q == 9) and bank or "x" end },
                          { __index = real })
    M.set_choice_by(key, 4, 9)
    M.set_choice_names(key, 4, { ["06 (Preset Index)"] = "06 Big Plate" }, "tr", 1)
    bank = "Rooms 2"
    M.set_choice_names(key, 4, { ["06 (Preset Index)"] = "06 Drum Room" }, "tr", 1)
    check("follow: this bank's name", M.choice_text(key, 4, "06 (Preset Index)", "tr", 1), "06 Drum Room")
    bank = "Plates 1"
    check("follow: the other bank's", M.choice_text(key, 4, "06 (Preset Index)", "tr", 1), "06 Big Plate")
    bank = "Halls"
    check("follow: a bank with none, the plugin's", M.choice_text(key, 4, "06 (Preset Index)", "tr", 1), "06 (Preset Index)")
    check("follow: no plugin to ask, none", M.choice_text(key, 4, "06 (Preset Index)"), "06 (Preset Index)")
    M.save(); M.reload()
    bank = "Rooms 2"
    check("follow: survives reload", M.choice_text(key, 4, "06 (Preset Index)", "tr", 1), "06 Drum Room")
    check("follow: copied", M.copy(M.get(key)).choice_ctx[4]["Plates 1"]["06 (Preset Index)"], "06 Big Plate")
    -- a bank with fewer presets: the rest left out; naming another bank
    -- without being on it
    M.set_choice_names(key, 4, { ["01 (Preset Index)"] = "01 Small", ["02 (Preset Index)"] = "-", ["03 (Preset Index)"] = "-" },
                       "tr", 1, "Halls")
    bank = "Halls"
    local hl = M.choice_list(key, 4, { { norm = 0, text = "01 (Preset Index)" }, { norm = 0.5, text = "02 (Preset Index)" },
                                      { norm = 1, text = "03 (Preset Index)" } }, "tr", 1)
    check("hidden: left out of the list", #hl .. " " .. hl[1].text, "1 01 Small")
    check("hidden: the one it's on still reads", M.choice_text(key, 4, "02 (Preset Index)", "tr", 1), "02 (Preset Index)")
    M.set_choice_by(key, 4, nil)
    check("follow: off, the plain names again", M.choice_text(key, 4, "06 (Preset Index)", "tr", 1), "06 (Preset Index)")
    reaper = real
  end
  do
    -- a dropdown's colours per choice (ChoiceCol<n>), by the plugin's text
    local ck = "VST3: ChoiceColTest (Test)"
    M.set(ck, { controls = { { param = 3, type = "combo", cap = "blue",
                               ccols = { Opto = "amber", ["Vocal Mode"] = "#FF8800", Bad = "nope" } },
                             { param = 4, type = "knob", ccols = { Opto = "red" } } }, aliases = {} })
    M.save(); M.reload()
    local cc = M.get(ck).controls
    check("choice colours: a named one",  M.choice_col(cc[1], "Opto"), "amber")
    check("choice colours: your own, trimmed text", M.choice_col(cc[1], " Vocal Mode "), "#ff8800")
    check("choice colours: not a colour, dropped", M.choice_col(cc[1], "Bad"), nil)
    check("choice colours: the control's own kept", cc[1].cap, "blue")
    check("choice colours: dropdowns only", cc[2].ccols, nil)
    check("choice colours: copied", M.copy(M.get(ck)).controls[1].ccols.Opto, "amber")
    check("choice colours: line", M.choice_cols_line({ B = "red", A = "#00ff00", C = "x" }), "A=#00ff00|B=red")
    local named = M.choice_list(key, 3, { { norm = 0, text = "Opto" } })
    check("choice colours: a renamed choice keeps the plugin's text", named[1].raw, "Opto")
    M.remove(ck); M.save()
  end
  M.set_choice_names(key, 3, {})
  check("choice names: cleared",              M.get_choice_names(key, 3), nil)
  M.save(); M.reload()
end
check("display: ... trimmed",     M.display_name(key, 2, " Release ", "Release"), "Recovery")
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
check("drive letter kept",  IX.norm_key([[C:\x\Pro-Q 3.vst3]]),            "pro_q_3.vst3")
check("type prefix",        IX.norm_key("vst3:Saturn 2.vst3"),             "saturn_2.vst3")
-- a shell plugin's "<hash" tells its builds apart, and REAPER's tag file
-- keys them with it
check("shell hash kept",    IX.norm_key("WaveShell1.dll<12345"),           "waveshell1.dll<12345")
checkf("hyphens = underscores", function()
  return IX.norm_key("WaveShell1-VST3 14.15_x64.vst3") == IX.norm_key("WaveShell1_VST3_14.15_x64.vst3")
end)
check("spaces = underscores", IX.norm_key("Nectar Pro.vst3"),              "nectar_pro.vst3")
check("brackets = underscores (u-he's files, as REAPER's tag file keys them)",
      IX.norm_key([[C:\Program Files\Common Files\VST3\Satin(x64).vst3]]) == IX.norm_key("Satin_x64_.vst3"), true)
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
  -- a JS effect: REAPER tags none, so no developer, whatever its name ends in
  list[#list + 1] = { name = "JS: Delay (Lo-Fi)", ident = "delay_lofi", short = "Delay", vendor = "Lo-Fi", fmt = "JS" }
  -- read from the tag file's own folder
  local grp = reaper.GetResourcePath
  reaper.GetResourcePath = function() return (TAGFILE:match("^(.*)[/\\]") or ".") end
  IX.reset()
  local devs, cats, folds = IX.build(list)
  check("the tag file was read", IX.tagged(), true)
  check("a JS effect has no developer", list[#list].dev, nil)
  local junk = false
  for _, d in ipairs(devs) do if d.name == "Lo-Fi" then junk = true end end
  check("no developer from a JS effect's name", junk, false)
  reaper.GetResourcePath = grp
  
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
  -- every send field, per send, for the mode tests; I_DSTCHAN also kept
  -- where the older checks look for it
  local SFIELD = {}
  reaper.SetTrackSendInfo_Value = function(_, _, i, k, v)
    SFIELD[i] = SFIELD[i] or {}
    SFIELD[i][k] = v
    if k == "I_DSTCHAN" then DSTCHAN[i] = v end
  end
  reaper.GetTrackSendInfo_Value = function(_, _, i, k)
    return (SFIELD[i] or {})[k] or 0
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

  -- MIDI: audio off, every MIDI channel on, nothing widened
  NCHAN[9] = nil
  check("MIDI send created",        SD.add_send(1, 9, "midi"), true)
  local mi = #SENDS - 1
  check("MIDI send has no audio",   SFIELD[mi].I_SRCCHAN, -1)
  check("MIDI send, all channels",  SFIELD[mi].I_MIDIFLAGS, 0)
  check("MIDI doesn't widen",       NCHAN[9], nil)
  check("named modes work too",     SD.add_send(1, 9, "sidechain") and DSTCHAN[#SENDS - 1], 2)

  -- Receives: the same send, made from the other end. Track 4 receiving
  -- from track 1 is a send FROM 1 TO 4, and a sidechain widens track 4 --
  -- the panel's own track, since that's the one receiving.
  do
    local RV = require "TS_CV_Receives"
    local before = #SENDS
    NCHAN[4] = nil
    check("receive created",          RV.add_send(4, 1, true), true)
    check("as a send from the source", SENDS[#SENDS].src, 1)
    check("to the panel's own track", SENDS[#SENDS].dst, 4)
    check("sidechain widens the receiver", NCHAN[4], 4)
    check("sidechain receive lands on 3/4", DSTCHAN[#SENDS - 1], 2)
    check("one send made",            #SENDS, before + 1)
    check("no receive from itself",   RV.add_send(4, 4, false), false)
    check("receives share the width rules", RV.width(false, 0, 300), SD.width(false, 0, 300))
  end
  
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
  -- strip mode (the Rack view): as wide as asked, as short as fits
  do
    SD.STRIP_W = 400
    local was_c = SD.is_collapsed
    SD.is_collapsed = function() return false end
    local per = math.floor((400 - C.PANEL_PAD * 2 + C.SEND_COL_GAP) / (C.SEND_W + C.SEND_COL_GAP))
    local was, wm = reaper.GetTrackNumSends, reaper.GetMasterTrack
    reaper.GetMasterTrack = function() return 0 end
    for _, n in ipairs({ 0, 1, per - 1, per, per * 2 + 1, 40 }) do
      reaper.GetTrackNumSends = function() return n end
      local h = SD.strip_h(1, 400)
      check("strip: " .. n .. " sends fit across 400", SD.width(false, n, h), 400)
      check("strip: " .. n .. " sends, no taller than needed",
            P.rows_for(h), math.max(C.MIN_ROWS, math.ceil((n + 1) / per)))
    end
    reaper.GetTrackNumSends, reaper.GetMasterTrack = was, wm
    SD.is_collapsed = function() return true end
    check("strip: folded is a bar", SD.strip_h(1, 400), C.HEADER_H + 2)
    SD.is_collapsed = was_c
    check("strip: folded is the strip's width", SD.width(true, 0, H), 400)
    SD.STRIP_W = nil
    check("strip off: as before", SD.width(true, 0, H), C.COLLAPSED_W)
  end
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

-- Containers and parallel FX, against a simulated chain that decodes
-- addresses the way REAPER 7 does: a container's slot, then each nested
-- slot, packed into one number past 0x2000000 with the level above's slot
-- count (+1) as the radix. A move's destination is read against the chain
-- BEFORE the move and the FX lands at that slot of that level.
do
  local FLAG = 0x2000000
  local TOP = {}
  local TR = {}
  local function decode(addr)
    if addr < FLAG then return TOP, addr end
    -- each level's digit is its slot + 1, in base (that level's count + 1);
    -- what's left once it fits in one digit is the slot itself, so one
    -- past the last addresses the level's end
    local v, list = addr - FLAG, TOP
    while true do
      local n = #list
      if v <= n + 1 then return list, v - 1 end
      local p = v % (n + 1) - 1
      v = v // (n + 1)
      local item = list[p + 1]
      if not (item and item.kids) then return nil end
      list = item.kids
    end
  end
  local function item_at(addr)
    local l, i = decode(addr)
    return l and l[i + 1]
  end
  local saved = {}
  for _, k in ipairs({ "TrackFX_GetCount", "TrackFX_GetFXGUID", "TrackFX_GetFXName",
                       "TrackFX_GetNamedConfigParm", "TrackFX_SetNamedConfigParm",
                       "TrackFX_CopyToTrack", "TrackFX_Delete", "TrackFX_AddByName" }) do
    saved[k] = reaper[k]
  end
  reaper.TrackFX_GetCount = function() return #TOP end
  reaper.TrackFX_GetFXGUID = function(_, a) local it = item_at(a); return it and it.guid or "" end
  reaper.TrackFX_GetFXName = function(_, a)
    local it = item_at(a); if not it then return false, "" end
    return true, it.name
  end
  reaper.TrackFX_GetNamedConfigParm = function(_, a, k)
    local it = item_at(a); if not it then return false, "" end
    if k == "container_count" then
      if it.kids then return true, tostring(#it.kids) end
      return false, ""
    end
    if k == "parallel" then return true, tostring(it.par or 0) end
    return false, ""
  end
  reaper.TrackFX_SetNamedConfigParm = function(_, a, k, v)
    local it = item_at(a); if not it then return false end
    if k == "parallel" then it.par = tonumber(v) end
    return true
  end
  reaper.TrackFX_CopyToTrack = function(_, src, _, dest, move)
    local sl, si = decode(src)
    local dl, di = decode(dest)          -- read before anything moves
    assert(sl and sl[si + 1] and dl and di >= 0 and di <= #dl, "bad address")
    local it
    if move == false then
      local function clone(x)
        local c = { name = x.name .. "'", guid = x.guid .. "'", par = x.par }
        if x.kids then c.kids = {}; for k, y in ipairs(x.kids) do c.kids[k] = clone(y) end end
        return c
      end
      it = clone(sl[si + 1])
    else
      it = table.remove(sl, si + 1)
    end
    table.insert(dl, math.min(di, #dl) + 1, it)
  end
  reaper.TrackFX_Delete = function(_, a)
    local l, i = decode(a)
    if l and l[i + 1] then table.remove(l, i + 1) return true end
    return false
  end
  local made = 0
  reaper.TrackFX_AddByName = function(_, name, _, inst)
    made = made + 1
    local it = { name = name, guid = "{N" .. made .. "}" }
    if name == "Container" then it.kids = {} end
    if inst == -1 then TOP[#TOP + 1] = it; return #TOP - 1 end
    local at = -1000 - inst
    table.insert(TOP, at + 1, it); return at
  end

  local function fx(n, par) return { name = n, guid = "{" .. n .. "}", par = par } end
  local function box(n, kids, par) return { name = n, guid = "{" .. n .. "}", kids = kids, par = par } end
  -- the chain as text: [..] a container, |1 / |2 a parallel setting
  local function shape(list)
    local out = {}
    for _, it in ipairs(list or TOP) do
      local t = it.kids and (it.name .. "[" .. shape(it.kids) .. "]") or it.name
      if (it.par or 0) ~= 0 then t = t .. "|" .. it.par end
      out[#out + 1] = t
    end
    return table.concat(out, ",")
  end
  local function reset()
    TOP = { fx("A"), box("C1", { fx("B"), box("C2", { fx("D"), fx("E", 1) }) }), fx("F", 1), fx("G", 2) }
  end

  reset()
  local list = T.collect(TR)
  local names = {}
  for i, e in ipairs(list) do names[i] = e.name end
  check("containers: every panel, in order", table.concat(names, ","), "A,B,D,E,F,G")
  local ok_addr = true
  for _, e in ipairs(list) do
    if (item_at(e.addr) or {}).guid ~= e.guid then ok_addr = false end
  end
  check("containers: each address finds its own plugin", ok_addr, true)
  check("containers: where E sits", list[4].path .. " " .. list[4].index .. "/" .. list[4].siblings, "1.1.1 1/2")
  check("containers: E's containers, outermost first",
        list[4].ancestors[1].name .. ">" .. list[4].ancestors[2].name, "C1>C2")
  check("containers: parallel read", list[4].parallel .. list[5].parallel .. list[6].parallel, "112")
  check("containers: top level has no ancestors", #list[1].ancestors, 0)

  local br, rows = T.groups(list)
  local desc = {}
  for _, b in ipairs(br) do
    desc[#desc + 1] = ("%s%d-%d@%d%s"):format(b.kind:sub(1, 1), b.first, b.last, b.row,
                                              b.merge and "m" or "")
  end
  table.sort(desc)
  -- E runs beside D inside C2; C2 inside C1; C1, F and G side by side --
  -- four deep: rows from the outside in, the innermost two sharing the last
  check("brackets: all of them", table.concat(desc, " "), "c2-4@1 c3-4@2 p2-6@0m p3-4@2")
  check("brackets: rows", rows, 3)

  -- deeper than the cap folds into the top row
  TOP = { box("X1", { box("X2", { box("X3", { box("X4", { fx("Z") }) }) }) }) }
  br, rows = T.groups(T.collect(TR))
  local top_row = 0
  for _, b in ipairs(br) do top_row = math.max(top_row, b.row) end
  check("brackets: capped", rows .. "/" .. #br .. "/" .. top_row, "3/4/2")

  -- a plain chain needs no strip at all
  TOP = { fx("A"), fx("B") }
  br, rows = T.groups(T.collect(TR))
  check("brackets: none on a plain chain", #br .. "/" .. rows, "0/0")
  -- a flag on the first slot means nothing
  TOP = { fx("A", 1), fx("B") }
  br, rows = T.groups(T.collect(TR))
  check("brackets: first slot's flag ignored", #br, 0)
  -- an empty container stands in for itself, bracket and all
  TOP = { fx("A"), box("E0", {}) }
  list = T.collect(TR)
  br = T.groups(list)
  check("brackets: empty container", #list .. (list[2].is_container and "c" or "") ..
        "/" .. br[1].kind .. br[1].first .. br[1].last, "2c/container22")

  -- a container with knobs on it: its own panel at the head of its
  -- bracket; folded to it, what's inside drops out of the row
  do
    reset()
    local lp = T.with_container_panels(T.collect(TR), function(n)
      if n.name == "C1" or n.name == "C2" then return { visible = { 0 }, sig = "0" } end
    end)
    local g = {}
    for i, e in ipairs(lp) do g[i] = (e.container_panel and "*" or "") .. e.guid:gsub("[{}]", "") end
    check("container panels: at the head of each container", table.concat(g, ","), "A,*C1,B,*C2,D,E,F,G")
    local brs = {}
    for _, b in ipairs(T.groups(lp)) do if b.kind == "container" then brs[#brs + 1] = b.node.name .. b.first .. "-" .. b.last end end
    table.sort(brs)
    check("container panels: the brackets take them in", table.concat(brs, " "), "C12-6 C24-6")
    check("container panels: a panel is its container", lp[2].addr == lp[3].ancestors[1].addr and lp[2].path == "1", true)
    local f2 = T.fold(lp, function(gd) return gd == "{C2}" end)
    g = {}
    for i, e in ipairs(f2) do g[i] = e.guid:gsub("[{}]", "") end
    check("container panels: folded, its plugins leave the row", table.concat(g, ","), "A,C1,B,C2,F,G")
    local f1 = T.fold(lp, function(gd) return gd == "{C1}" end)
    g = {}
    for i, e in ipairs(f1) do g[i] = e.guid:gsub("[{}]", "") end
    check("container panels: an outer one folded takes the inner one's panel too", table.concat(g, ","), "A,C1,F,G")
    check("container panels: what's on them changes the chain's hash", T.hash(lp) ~= T.hash(T.with_container_panels(T.collect(TR), function(n)
      if n.name == "C1" or n.name == "C2" then return { visible = { 0, 1 }, sig = "0,1" } end end)), true)
  end

  -- moves
  reset()
  T.move(TR, { 1, 1, 0 }, {}, 0)                -- D out to the front
  check("move: out of a nested container", shape(), "D,A,C1[B,C2[E|1]],F|1,G|2")
  reset()
  T.move(TR, { 0 }, { 1, 1 }, 2)                -- A to the end of C2
  check("move: into a nested container", shape(), "C1[B,C2[D,E|1,A]],F|1,G|2")
  reset()
  T.move(TR, { 3 }, { 1 }, 0)                   -- G to the front of C1
  check("move: later top-level FX into a container", shape(), "A,C1[G|2,B,C2[D,E|1]],F|1")
  reset()
  T.move(TR, { 1, 0 }, { 1 }, 2)                -- B after C2, same level
  check("move: within a container", shape(), "A,C1[C2[D,E|1],B],F|1,G|2")
  reset()
  T.move(TR, { 0 }, {}, 4)                      -- A to the end, same level
  check("move: within the chain", shape(), "C1[B,C2[D,E|1]],F|1,G|2,A")
  -- duplicates: a copy right after, at the same level
  reset()
  T.duplicate(TR, { 0 })
  check("duplicate: top level", shape(), "A,A',C1[B,C2[D,E|1]],F|1,G|2")
  reset()
  T.duplicate(TR, { 1, 1, 1 })                  -- E, last in C2
  check("duplicate: last in a nested container", shape(), "A,C1[B,C2[D,E|1,E'|1]],F|1,G|2")
  reset()
  T.duplicate(TR, { 1, 1 })                     -- C2 and what's in it
  check("duplicate: a container", shape(), "A,C1[B,C2[D,E|1],C2'[D',E'|1]],F|1,G|2")
  reset()
  T.duplicate(TR, { 3 })
  check("duplicate: the last slot", shape(), "A,C1[B,C2[D,E|1]],F|1,G|2,G'|2")
  reset()
  check("move: back where it is goes nowhere", tostring(T.move(TR, { 2 }, {}, 3)), "nil")
  check("move: a container into itself refused", tostring(T.move(TR, { 1 }, { 1, 1 }, 0)), "nil")
  check("move: nothing changed", shape(), "A,C1[B,C2[D,E|1]],F|1,G|2")

  -- containers made and unmade
  reset()
  check("wrap: done", T.wrap(TR, { 2 }), true)  -- F into a container of its own
  check("wrap: in place, setting carried", shape(), "A,C1[B,C2[D,E|1]],Container[F]|1,G|2")
  reset()
  T.wrap(TR, { 1, 1, 1 })                       -- E, deep inside
  check("wrap: nested", shape(), "A,C1[B,C2[D,Container[E]|1]],F|1,G|2")
  reset()
  check("unpack: done", T.unpack(TR, { 1 }), true)
  check("unpack: contents in its place", shape(), "A,B,C2[D,E|1],F|1,G|2")
  reset()
  TOP[2].par = 1
  T.unpack(TR, { 1, 1 })
  check("unpack: nested, first takes the setting", shape(), "A,C1[B,D,E|1]|1,F|1,G|2")

  -- adding a plugin straight into a container
  reset()
  check("add into: done", T.add_into(TR, "New", { 1, 1 }, 1), true)
  check("add into: in place", shape(), "A,C1[B,C2[D,New,E|1]],F|1,G|2")
  reset()
  T.add_into(TR, "Top", {}, 1)
  check("add into: top level", shape(), "A,Top,C1[B,C2[D,E|1]],F|1,G|2")

  -- the parallel setting
  reset()
  list = T.collect(TR)
  T.set_parallel(TR, list[2].addr, 2)
  check("parallel: set inside a container", shape(), "A,C1[B|2,C2[D,E|1]],F|1,G|2")
  check("parallel: changes the chain's hash", T.hash(T.collect(TR)) ~= T.hash(list), true)

  for _, k in ipairs({ "JS_Window_SetFocus", "JS_Window_FindChildByID", "GetMainHwnd",
                       "SetCursorContext", "NamedCommandLookup" }) do reaper[k] = saved[k] end
end



-- a canvas's own colours: stored with its layout, drawn in while it draws
do
  local M_ = require("TS_CV_Mappings")
  local cols = M_.canvas_cols_of("curve:#ff4a3a|bg:#2a0e0e|band3:#00ff00|junk:#123456|grid:#zzzzzz")
  check("canvas colours: read", ("%06x %06x %06x"):format(cols.curve, cols.bg, cols.band3), "ff4a3a 2a0e0e 00ff00")
  check("canvas colours: unknown and bad ones dropped", tostring(cols.junk) .. tostring(cols.grid), "nilnil")
  check("canvas colours: written back", M_.canvas_cols_line(cols), "band3:#00ff00|bg:#2a0e0e|curve:#ff4a3a")
  check("canvas colours: none", tostring(M_.canvas_cols_of("")) .. tostring(M_.canvas_cols_line({})), "nilnil")
  check("canvas colours: copied with the canvas", M_.copy_canvas({ kind = "comp", cols = cols }).cols.curve, 0xff4a3a)
  local P = require("TS_CV_Panel")
  local Cc = require("TS_CV_Config")
  local was_accent, was_grid = Cc.COL.accent, Cc.COL.eq_grid
  local seen
  local ok = pcall(P.with_canvas_cols, { cols = { curve = 0x112233 } }, "dl", 0, 0, 10, 10,
    function(a) seen = { Cc.COL.accent, Cc.COL.eq_grid, a } end, "arg")
  check("canvas colours: the curve stands in for the accent while it draws",
    tostring(ok) .. " " .. (seen and ("%08x %s"):format(seen[1], seen[3]) or ""), "true 112233ff arg")
  check("canvas colours: the grid untouched when not set", seen and seen[2] == was_grid, true)
  check("canvas colours: the theme back after", Cc.COL.accent == was_accent, true)
  local ok2 = pcall(P.with_canvas_cols, { cols = { curve = 0x112233 } }, "dl", 0, 0, 10, 10, function() error("boom") end)
  check("canvas colours: back after an error too", tostring(ok2) .. " " .. tostring(Cc.COL.accent == was_accent), "false true")
end

-- a dropdown's list read by name, without moving the plugin (any length,
-- stepped or not), and stepping along it
do
  local P = require("TS_CV_Panel")
  local M_ = require("TS_CV_Mappings")
  local saved = {}
  for _, k in ipairs({ "TrackFX_GetParameterStepSizes", "TrackFX_FormatParamValueNormalized", "TrackFX_SetParamNormalized" }) do saved[k] = reaper[k] end
  local sets = 0
  reaper.TrackFX_SetParamNormalized = function() sets = sets + 1 end
  -- no steps reported: 120 programs along a plain knob
  reaper.TrackFX_GetParameterStepSizes = function() return false end
  reaper.TrackFX_FormatParamValueNormalized = function(_, _, _, v)
    return true, ("%03d Program"):format(math.min(119, math.floor(v * 120)) + 1)
  end
  P.clear_caches()
  local list = P.read_choices("tr", 0, 7, "Big")
  check("read by name: 120 programs, past 64", list and #list, 120)
  check("read by name: each in the middle of its run", list and (list[1].norm > 0 and list[1].norm < 1 / 120), true)
  check("read by name: nothing moved", sets, 0)
  check("step: next by its name", P.step_choice(list, "002 Program", 0, 1, false) == list[3].norm, true)
  check("step: arrows go round", P.step_choice(list, "120 Program", 1, 1, true) == list[1].norm, true)
  check("step: the wheel stops at the end", P.step_choice(list, "120 Program", 1, 1, false) == list[120].norm, true)
  -- a plugin that can only name the setting it's on: not readable
  reaper.TrackFX_FormatParamValueNormalized = function() return true, "Hall" end
  check("read by name: one name everywhere is no list", P.read_choices("tr", 0, 7, "Big"), nil)
  for k, v in pairs(saved) do reaper[k] = v end
  check("width: Size 3 on a dropdown", M_.combo_cells({ type = "combo", size = "3" }), 3)
  check("width: none is one cell", M_.combo_cells({ type = "combo" }), 1)
  check("width: not on a knob", M_.combo_cells({ type = "knob", size = "3" }), 1)
  check("width: two to four only", tostring(M_.combo_width_of("5")) .. tostring(M_.combo_width_of("1")), "nilnil")
  local w, h = P.cell_size({ type = "combo", size = "4" }, 8)
  check("width: four cells take eight half-cells", w .. "x" .. h, "8x2")
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
  
  -- buttons before any sweep (the budget spent, or the transport rolling):
  -- the plugin's names for each position, asked without moving it
  local fmt = reaper.TrackFX_FormatParamValueNormalized
  local DEC = { "A", "E", "N", "T", "P" }
  reaper.TrackFX_FormatParamValueNormalized = function(_, _, _, v) return true, DEC[math.floor(v * 4 + 0.5) + 1] end
  P.clear_caches(); SC.init("./"); os.remove("./TS_ChannelView_Steps.ini"); SC.init("./")
  C.SCAN_BUDGET = 0
  P.begin_frame()
  local sets0 = SETS
  local bl = P.button_choices(nil, 0, 3, "Decap", 5)
  check("buttons: the plugin's names before a sweep", table.concat((function() local o = {} for i, e in ipairs(bl) do o[i] = e.text end return o end)(), ","), "A,E,N,T,P")
  check("buttons: nothing moved to read them", SETS, sets0)
  -- a plugin that answers every position the same: numbers
  reaper.TrackFX_FormatParamValueNormalized = function() return true, "A" end
  P.clear_caches()
  bl = P.button_choices(nil, 0, 3, "Decap", 5)
  check("buttons: numbers when it can't say", bl[1].text .. bl[5].text, "15")
  reaper.TrackFX_FormatParamValueNormalized = fmt

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

-- no dividers: the plain fill, untouched
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

-- P.width must agree with what P.layout actually computes, not drift out
-- of sync with it. 12 knobs is 3 columns, comfortably past PANEL_MIN_W,
-- so the clamp isn't masking the comparison (8 knobs would be: 128px
-- clamps to 132).
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


-- auto-ranging scale
W.clear_peaks()
check("ladder picks the minimum",  W.pick_range(12, 0), 12)
check("ladder covers the peak",    W.pick_range(12, 15), 18)
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
pk, rng = W.gr_state("m", 20.0, NOW, 12)
check("scale expands at once",       rng, 24)
pk, rng = run(C.GR_RANGE_RELAX - 0.5, 0.5)
check("scale holds while relaxing",  rng, 24)
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

  -- Kept inside the WINDOW, not just the viewport. A control at its
  -- right-hand edge -- the Sends panel, every time -- would otherwise
  -- throw its tooltip out past the window edge, where the foreground
  -- draw list clips it away. There is plenty of monitor out there, so
  -- clamping to the viewport alone is not tight enough.
  local LBL = "a long enough label"
  W.clear_tips()
  MX, MY = 380, 300
  W.tip(nil, "edge", LBL, true, false)
  local e = frame()
  check("a tooltip at the window's edge is pulled back",
        e and (e.x + #LBL * 6) <= WIN[3], true)
  check("and flipped to the other side of the pointer", e and e.x < MX, true)
  check("not merely slid to the margin", e and e.x < WIN[3] - #LBL * 6, true)

  -- The same position, checked against the viewport bound alone, would
  -- be left unclamped -- the window is the tighter of the two bounds here.
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

  -- The comparisons the panel actually performs must resolve safely:
  -- nil > 0.5 raises, it does not return false.
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

  -- The peak HOLD is a different animal: it jumps straight to a new
  -- maximum, sits on it for LEVEL_HOLD seconds, then falls at a fixed
  -- rate. Each channel keeps its own hold -- the meter draws one hold
  -- line per bar, and a louder channel's figure showing across the
  -- quieter channel's bar would misrepresent it -- so the keys must stay
  -- fully independent.
  W.clear_peaks()
  local T = 100
  check("takes a new maximum at once", W.level_peak("p", -12, T), -12)
  check("and holds it while the signal drops",
        W.level_peak("p", -40, T + C.LEVEL_HOLD * 0.5), -12)
  -- `near`, not equality: T + C.LEVEL_HOLD does not land exactly on
  -- C.LEVEL_HOLD once it has been through a float, so this instant is
  -- either the last of the hold or the first femtosecond of the fall,
  -- and either is correct.
  check("still holding at the end of the hold",
        near(W.level_peak("p", -40, T + C.LEVEL_HOLD), -12, 0.001), true)
  -- A second past the hold is LEVEL_FALL dB down.
  check("then falls at the set rate",
        near(W.level_peak("p", -60, T + C.LEVEL_HOLD + 1), -12 - C.LEVEL_FALL, 0.1),
        true)
  -- It never falls below what is actually there.
  check("but never below the signal",
        W.level_peak("p", -20, T + C.LEVEL_HOLD + 60) >= -20, true)
  -- A louder moment resets the hold rather than being averaged in.
  W.clear_peaks()
  W.level_peak("q", -30, T)
  check("a louder moment takes over", W.level_peak("q", -3, T + 0.1), -3)

  -- Two channels, two holds. L peaks and R does not; R must not inherit
  -- L's figure.
  W.clear_peaks()
  W.level_peak("chL", -3,  T)
  W.level_peak("chR", -30, T)
  check("the left channel holds its own",  W.level_peak("chL", -40, T + 0.2), -3)
  check("and the right holds its own",     W.level_peak("chR", -40, T + 0.2), -30)
  check("which are not the same figure",
        W.level_peak("chL", -40, T + 0.2) ~= W.level_peak("chR", -40, T + 0.2),
        true)

  -- The RMS hairline is a fixed few pixels, not a share of the bar, so
  -- it stays a hairline however wide the meter gets.
  check("the RMS strip is a hairline",
        C.RMS_STRIP_W > 0 and C.RMS_STRIP_W < C.LEVEL_METER_W / 8, true)

  -- The RMS READOUT is held, the strip beside the bar is not. Both go
  -- through the same machinery, so what this pins down is that they are
  -- fed from different keys and really can differ: the live figure has
  -- fallen away while the held one is still up.
  W.clear_peaks(); W.clear_rms()
  local live = W.level_rms("hL", -6, C.RMS_WINDOW)
  local held = W.level_peak("hL#r", live, T)
  check("the held figure takes the live one", near(held, live), true)
  local quiet = W.level_rms("hL", -math.huge, C.RMS_WINDOW * 3)
  check("the live figure falls away", quiet < live - 3, true)
  check("while the held one stays up",
        near(W.level_peak("hL#r", quiet, T + C.LEVEL_HOLD * 0.5), held), true)
  check("and the two keys never collide",
        W.level_peak("hL", -60, T) ~= held, true)
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

  -- The bar is green, then red, then a harder red. Three colours, and
  -- no step at -6: -6 dBFS is not a warning about anything, so a colour
  -- change there would mean nothing and happen thirty times a second on
  -- every strip at once.
  check("a quiet bar is green",    W.level_bar_colour(-40), C.COL.level_lo)
  check("and -6 is still green",   W.level_bar_colour(-6),  C.COL.level_lo)
  check("no step at -6",
        W.level_bar_colour(-6) == W.level_bar_colour(-6.1), true)
  check("hot is red",              W.level_bar_colour(-0.1), C.COL.level_clip)
  check("over is the harder red",  W.level_bar_colour(0.5), C.COL.level_over)
  check("and the bar has three colours in all",
        (W.level_bar_colour(-40) ~= W.level_bar_colour(-0.1))
        and (W.level_bar_colour(-0.1) ~= W.level_bar_colour(0.5)), true)
  -- The readout and the bar must agree, or a red number over a green
  -- bar is two opinions about one signal.
  check("bar and readout agree at the top",
        W.level_bar_colour(1.0), W.level_colour(1.0, C.COL.level_lo))

  -- The dB ladder is printed OVER the bars now, which only works if the
  -- two inks really do contrast with what they land on. That is a
  -- property of the palette, and a palette is data -- nothing else would
  -- notice a theme change that quietly made the scale invisible. So it
  -- is measured.
  local function lum(c)
    local r, g, b = (c >> 24) & 0xff, (c >> 16) & 0xff, (c >> 8) & 0xff
    return (0.299 * r + 0.587 * g + 0.114 * b) / 255
  end
  -- A tenth of the range apart is barely visible; a third is comfortable.
  local FLOOR = 0.25
  check("the light ink reads on an unlit bar",
        math.abs(lum(C.COL.meter_ink) - lum(C.COL.knob_body)) > FLOOR, true)
  for _, bar in ipairs({ "level_lo", "level_clip", "level_over" }) do
    check("the dark ink reads on " .. bar,
          math.abs(lum(C.COL.meter_ink_lit) - lum(C.COL[bar])) > FLOOR, true)
  end
  -- And they have to be on opposite sides of everything, or "dark ink
  -- over a lit bar" is not a rule, it is a coincidence.
  check("the two inks straddle the bars",
        lum(C.COL.meter_ink_lit) < lum(C.COL.knob_body)
        and lum(C.COL.meter_ink) > lum(C.COL.level_lo), true)
end

-- ---------------------------------------------------------------------
-- how many bars a meter draws
-- ---------------------------------------------------------------------
-- REAPER never takes a track below two channels, so in practice this
-- always answers two -- but it asks rather than assuming, and the
-- question is worth asking properly, because the number decides how many
-- bars, how many peak holds and how many columns of figures get drawn.
do
  local real = reaper.GetMediaTrackInfo_Value
  local NCH
  reaper.GetMediaTrackInfo_Value = function(_, k)
    if k == "I_NCHAN" then return NCH end
    return 0
  end
  local TR = {}

  NCH = 2   check("a stereo track has two bars", W.meter_channels(TR), 2)
  NCH = 1   check("a one-channel track has one", W.meter_channels(TR), 1)
  -- Two is the ceiling: at fifty pixels a third bar is a stripe.
  NCH = 4   check("four channels still show two", W.meter_channels(TR), 2)
  NCH = 64  check("and so do sixty-four",         W.meter_channels(TR), 2)
  -- Nonsense is not allowed to produce a meter with no bars in it.
  NCH = 0   check("zero is floored at one",       W.meter_channels(TR), 1)
  NCH = nil check("no answer means stereo",       W.meter_channels(TR), 2)
  check("and nothing is not a track",             W.meter_channels(nil), 2)
  reaper.GetMediaTrackInfo_Value = real
end

-- ---------------------------------------------------------------------
-- the header lines up with Track Analyser
-- ---------------------------------------------------------------------
-- Track Analyser pushes no WindowPadding, ItemSpacing or FramePadding of
-- its own, so its rule sits at WindowPadding.y + a frame-height header
-- row + ItemSpacing.y below the window top. Ours has to reach the same
-- place from under a menu bar.
--
-- WindowPadding.y cannot be assumed from ImGui's own default, a
-- screenshot measurement, or FontSize + 2*FramePadding, because
-- ReaImGui's defaults and menu bar height both differ from stock ImGui.
-- It is derived instead from three values the window reports at
-- runtime, and this checks that the identity behind that derivation
-- actually holds.
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
  -- A non-zero nudge would mean the derivation above is not actually
  -- correct -- for example a clamp elsewhere quietly discarding part of
  -- the answer, with the nudge then masking that loss rather than
  -- reflecting any real offset.
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
-- automation mode
-- ---------------------------------------------------------------------
-- Six modes, and the button has to survive REAPER answering with one it
-- has never heard of -- which is exactly what happens when a future
-- version adds a seventh and this script is the old one.
do
  local CHn = require "TS_CV_Channel"
  local real = reaper.GetMediaTrackInfo_Value
  local MODE = 0
  reaper.GetMediaTrackInfo_Value = function(_, k)
    if k == "I_AUTOMODE" then return MODE end
    return 0
  end

  for i = 0, 5 do
    MODE = i
    check(("mode %d reads back"):format(i), CHn.auto_mode({}), i)
    check(("mode %d has a label"):format(i), CHn.AUTO[i].text ~= nil, true)
    check(("mode %d has a colour"):format(i),
          C.COL[CHn.AUTO[i].col] ~= nil, true)
  end

  -- REAPER hands these back as doubles, and a seventh mode from a newer
  -- REAPER must not index a nil.
  MODE = 3.0
  check("a float is still an integer mode", CHn.auto_mode({}), 3)
  MODE = 9
  check("an unknown mode falls back to trim", CHn.auto_mode({}), 0)
  MODE = -1
  check("and so does a negative one", CHn.auto_mode({}), 0)

  -- Trim is the only one that reads as "off" on the button.
  check("trim is the unlit state", CHn.AUTO[0].col, "auto_trim")
  check("write is not trim's colour",
        CHn.AUTO[3].col ~= CHn.AUTO[0].col, true)

  reaper.GetMediaTrackInfo_Value = real
end

-- ---------------------------------------------------------------------
-- mixer view: which tracks, and what reads on them
-- ---------------------------------------------------------------------
-- A mixer strip IS the Channel panel with a different id prefix, so
-- there is little new drawing to check. What IS new is the track set and
-- the contrast rule that keeps a name readable on a colour the user
-- picked, and both are pure.
do
  local MX = require "TS_CV_Mixer"
  local CHn = require "TS_CV_Channel"
  local St = require "TS_CV_State"
  -- The collapse store lives in the project file, which the offline
  -- harness has none of. A table stands in for it.
  local PROJ = {}
  reaper.GetProjExtState = function(_, ns, k) return 1, PROJ[ns .. k] or "" end
  reaper.SetProjExtState = function(_, ns, k, v) PROJ[ns .. k] = v end

  local real = {
    CountTracks = reaper.CountTracks,
    GetTrack = reaper.GetTrack,
    GetMasterTrack = reaper.GetMasterTrack,
    GetTrackGUID = reaper.GetTrackGUID,
    GetMediaTrackInfo_Value = reaper.GetMediaTrackInfo_Value,
    GetSetMediaTrackInfo_String = reaper.GetSetMediaTrackInfo_String,
  }
  local TRACKS = {
    { name = "Kick",  show = 1, space = 0 },
    { name = "Snare", show = 0, space = 0 },   -- hidden from the mixer
    { name = "Bass",  show = 1, space = 1 },
  }
  local MASTER = { name = "MASTER" }
  reaper.GetMasterTrack = function() return MASTER end
  reaper.CountTracks = function() return #TRACKS end
  reaper.GetTrack = function(_, i) return TRACKS[i + 1] end
  reaper.GetTrackGUID = function(t) return "{" .. (t.name or "?") .. "}" end
  reaper.GetSetMediaTrackInfo_String = function(t, k)
    if k == "P_NAME" then return true, t.name or "" end
    return true, ""
  end
  reaper.GetMediaTrackInfo_Value = function(t, k)
    if k == "B_SHOWINMIXER" then return t.show end
    if k == "I_SPACER" then return t.space end
    if k == "I_CUSTOMCOLOR" then return 0 end
    return 0
  end

  check("hidden from REAPER's mixer is hidden here",
        MX.in_mixer(TRACKS[2]), false)
  check("shown stays shown", MX.in_mixer(TRACKS[1]), true)
  -- A track that has never had an opinion should not vanish.
  check("no answer means shown", MX.in_mixer({ name = "x" }), true)
  check("and nothing is not a track", MX.in_mixer(nil), false)

  local list = MX.tracks()
  check("the master leads",        list[1].name, "MASTER")
  check("then the shown tracks",   #list, 3)
  check("Kick is there",           list[2].name, "Kick")
  check("Snare is not",            list[3].name, "Bass")
  check("numbered as in the project", list[3].num, 3)
  check("the spacer comes with it",   list[3].space, true)
  check("guids key the strips",       list[2].guid, "{Kick}")
  -- The master's number is 0, which is what tells the header to print
  -- its name alone rather than "0 MASTER".
  check("the master has no number", list[1].num, 0)

  -- The mixer and the track strip are ONE object: a button lines up
  -- under its own strip, so both take their width from here and neither
  -- owns a size of its own.
  local wide = MX.col_width("{Kick}")
  St.set_collapsed("mx:{Kick}", true)
  local narrow = MX.col_width("{Kick}")
  check("a collapsed strip is narrower", narrow < wide, true)
  check("and matches the panel that drew it", narrow, CHn.width(true))
  St.set_collapsed("mx:{Kick}", false)
  check("expanding puts it back", MX.col_width("{Kick}"), wide)
  check("the master has a column too", MX.col_width("master") > 0, true)

  -- -------------------------------------------------------------------
  -- selection: plain, Ctrl, Shift
  -- -------------------------------------------------------------------
  -- The one piece of genuinely new logic in this module, and the one
  -- where getting it wrong loses somebody's selection, so it is worth
  -- standing a project up in front of it.
  do
    local sel_real = {
      SetTrackSelected = reaper.SetTrackSelected,
      SetOnlyTrackSelected = reaper.SetOnlyTrackSelected,
      CountSelectedTracks2 = reaper.CountSelectedTracks2,
      Main_OnCommand = reaper.Main_OnCommand,
      UpdateArrange = reaper.UpdateArrange,
      GetMediaTrackInfo_Value = reaper.GetMediaTrackInfo_Value,
    }
    local ALL = { MASTER, TRACKS[1], TRACKS[2], TRACKS[3] }
    local function clear() for _, t in ipairs(ALL) do t.sel = false end end
    local function selected_names()
      local out = {}
      for _, t in ipairs(ALL) do if t.sel then out[#out + 1] = t.name end end
      table.sort(out)
      return table.concat(out, ",")
    end

    reaper.SetTrackSelected = function(t, on) t.sel = on and true or false end
    reaper.SetOnlyTrackSelected = function(t) clear(); t.sel = true end
    reaper.CountSelectedTracks2 = function()
      local n = 0
      for _, t in ipairs(ALL) do if t.sel then n = n + 1 end end
      return n
    end
    reaper.Main_OnCommand = function(id) if id == 40297 then clear() end end
    reaper.UpdateArrange = function() end
    reaper.GetMediaTrackInfo_Value = function(t, k)
      if k == "I_SELECTED" then return t.sel and 1 or 0 end
      if k == "B_SHOWINMIXER" then return t.show end
      if k == "I_SPACER" then return t.space end
      if k == "I_CUSTOMCOLOR" then return 0 end
      return 0
    end

    -- MX.click reads the modifiers out of ImGui's bitmask, so it needs
    -- one. These are the only three constants it touches.
    MX.attach({ Mod_Ctrl = 2, Mod_Shift = 1, Mod_Super = 8 })
    local NONE, SHIFT, CTRL = 0, 1, 2

    clear()
    MX.click(TRACKS[1], "{Kick}", NONE)
    check("a plain click takes the track", selected_names(), "Kick")
    check("and drops whatever was there", reaper.CountSelectedTracks2(0, true), 1)

    MX.click(TRACKS[3], "{Bass}", CTRL)
    check("ctrl adds to it", selected_names(), "Bass,Kick")
    MX.click(TRACKS[3], "{Bass}", CTRL)
    check("and ctrl again takes it away", selected_names(), "Kick")
    MX.click(TRACKS[1], "{Kick}", CTRL)
    check("but never down to nothing", selected_names(), "Kick")

    -- Cmd is Ctrl on the other machine, and this runs on both.
    MX.click(TRACKS[3], "{Bass}", 8)
    check("cmd does what ctrl does", selected_names(), "Bass,Kick")

    -- A plain click sets the anchor; the shift-click then reaches back
    -- to it.
    MX.click(TRACKS[1], "{Kick}", NONE)
    MX.click(TRACKS[3], "{Bass}", SHIFT)
    check("shift takes the range", selected_names(), "Bass,Kick")
    -- Snare sits between them in the project but is hidden from the
    -- mixer, so it is not in the range: the range is what you can see.
    check("a hidden track is not in it", TRACKS[2].sel, false)

    -- The master is not part of any range -- it is pinned to the front
    -- and a range through it would mean selecting every track.
    MX.click(MASTER, "master", SHIFT)
    check("shift onto the master is a plain click", selected_names(), "MASTER")

    MX.click(TRACKS[1], "{Kick}", NONE)
    MX.anchor = "{Gone}"
    MX.click(TRACKS[3], "{Bass}", SHIFT)
    check("a stale anchor falls back to a plain click", selected_names(), "Bass")
    check("and becomes the new anchor", MX.anchor, "{Bass}")

    -- Clicking the empty space past the last strip clears the lot.
    MX.click(TRACKS[1], "{Kick}", NONE)
    MX.click(TRACKS[3], "{Bass}", CTRL)
    check("two are selected before", reaper.CountSelectedTracks2(0, true), 2)
    MX.clear_selection()
    check("empty space clears them",  selected_names(), "")
    check("and forgets the anchor",   MX.anchor, nil)

    -- Put one back for the reads below.
    MX.click(TRACKS[3], "{Bass}", NONE)
    check("selected is read from REAPER", MX.selected(TRACKS[3]), true)
    check("and unselected likewise", MX.selected(TRACKS[1]), false)
    check("nothing is not selected", MX.selected(nil), false)

    for k, v in pairs(sel_real) do reaper[k] = v end
    MX.anchor = nil
  end

  for k, v in pairs(real) do reaper[k] = v end
  reaper.GetProjExtState, reaper.SetProjExtState = nil, nil
  St.clear_cache()
end

-- ---------------------------------------------------------------------
-- ganged edits: one move, every selected track
-- ---------------------------------------------------------------------
-- The riskiest arithmetic in the project, because getting it wrong
-- flattens somebody's balance and the undo is one step. All of it is
-- pure bar the reaper.* reads, so it stands up in front of a fake
-- project without drawing anything.
do
  local G = require "TS_CV_Gang"
  local real = {
    GetMediaTrackInfo_Value = reaper.GetMediaTrackInfo_Value,
    SetMediaTrackInfo_Value = reaper.SetMediaTrackInfo_Value,
    CountSelectedTracks2 = reaper.CountSelectedTracks2,
    GetSelectedTrack2 = reaper.GetSelectedTrack2,
    GetTrackGUID = reaper.GetTrackGUID,
  }

  -- A and B are selected, C is not, M is the master -- which has no
  -- record arm at all, and so answers nil for it.
  local A = { name = "A", vol = 1.00, pan =  0.0, sel = true  }
  local B = { name = "B", vol = 0.50, pan = -0.5, sel = true  }
  local Z = { name = "C", vol = 0.25, pan =  0.8, sel = false }
  local M = { name = "M", vol = 1.00, pan =  0.0, sel = false, master = true }
  local ALL = { A, B, Z, M }

  reaper.GetMediaTrackInfo_Value = function(t, k)
    if k == "I_SELECTED" then return t.sel and 1 or 0 end
    if k == "D_VOL"   then return t.vol end
    if k == "D_PAN"   then return t.pan end
    if k == "B_MUTE"  then return t.mute or 0 end
    -- The master has no record arm, and REAPER says so with a nil.
    if k == "I_RECARM" then
      if t.master then return nil end
      return t.rec or 0
    end
    return 0
  end
  reaper.SetMediaTrackInfo_Value = function(t, k, v)
    if k == "D_VOL" then t.vol = v
    elseif k == "D_PAN" then t.pan = v
    elseif k == "B_MUTE" then t.mute = v
    elseif k == "I_RECARM" then t.rec = v end
  end
  reaper.CountSelectedTracks2 = function()
    local n = 0
    for _, t in ipairs(ALL) do if t.sel then n = n + 1 end end
    return n
  end
  reaper.GetSelectedTrack2 = function(_, i)
    local n = 0
    for _, t in ipairs(ALL) do
      if t.sel then
        if n == i then return t end
        n = n + 1
      end
    end
  end
  reaper.GetTrackGUID = function(t) return "{" .. t.name .. "}" end

  local function near(a, b) return math.abs(a - b) < 1e-9 end

  check("a selected track among several gangs", G.ganged(A), true)
  check("an unselected one does not",           G.ganged(Z), false)
  check("and nothing is not a track",           G.ganged(nil), false)

  -- Volume by ratio: the track you dragged lands exactly where you put
  -- it, and the rest keep their relationship to it.
  G.vol(A, 2.0)
  check("the dragged fader lands where it was put", near(A.vol, 2.0), true)
  check("and the gang moves by the same ratio",     near(B.vol, 1.0), true)
  -- A constant ratio on the linear gain IS a constant number of dB,
  -- which is what "move them together" means to an engineer.
  local gap = U.val2db(A.vol) - U.val2db(B.vol)
  check("which leaves them the same dB apart", math.abs(gap - 6.0206) < 0.001, true)
  check("the balance is kept exactly",              near(A.vol / B.vol, 2.0), true)
  check("an unselected track is left alone",        near(Z.vol, 0.25), true)

  -- Touching an UNSELECTED track moves that track and nothing else,
  -- however many others are selected.
  G.vol(Z, 0.5)
  check("touching outside the selection is one track", near(Z.vol, 0.5), true)
  check("and leaves the selection where it was",       near(A.vol, 2.0), true)

  -- A fader at -inf stays at -inf: anything times zero is zero, and the
  -- bottom of the travel is a decision rather than an accident.
  B.vol = 0
  G.vol(A, 4.0)
  check("a track at -inf stays there", near(B.vol, 0), true)
  -- And dragging the one that IS at -inf has no ratio to offer, so it
  -- moves alone rather than doing something arbitrary to the others.
  A.vol, B.vol = 0, 0.5
  G.vol(A, 1.0)
  check("dragging from -inf moves that track", near(A.vol, 1.0), true)
  check("and leaves the gang alone",           near(B.vol, 0.5), true)

  -- Pan by OFFSET. A ratio would leave a centred track centred no
  -- matter how far you dragged, which is not what anybody means.
  A.pan, B.pan = 0.0, -0.5
  G.pan(A, 0.25)
  check("pan moves by the offset",      near(A.pan,  0.25), true)
  check("and the gang comes with it",   near(B.pan, -0.25), true)
  check("a centred track does move",    B.pan ~= -0.5, true)
  -- Clamped at the ends rather than wrapping or running off.
  A.pan, B.pan = 0.0, 0.9
  G.pan(A, 0.5)
  check("pan clamps at hard right", near(B.pan, 1.0), true)
  A.pan, B.pan = 0.0, -0.9
  G.pan(A, -0.5)
  check("and at hard left",         near(B.pan, -1.0), true)

  -- Absolute: everybody takes the same value.
  A.mute, B.mute, Z.mute = 0, 0, 0
  G.set(A, "B_MUTE", 1)
  check("muting one mutes the gang", A.mute == 1 and B.mute == 1, true)
  check("but not the rest of the project", Z.mute, 0)

  -- A track that hasn't GOT the property is skipped, not written to.
  M.sel = true
  A.rec, M.rec = 0, nil
  G.set(A, "I_RECARM", 1)
  check("record arm reaches the track that has one", A.rec, 1)
  check("and skips the master, which has not",       M.rec, nil)
  M.sel = false

  -- Collapse is not a track property, but it gangs by the same rule.
  local keys = G.collapse_keys(A, "mx:")
  table.sort(keys)
  check("collapse keys cover the gang", table.concat(keys, ","),
        "mx:{A},mx:{B}")
  check("and an unselected track is just itself",
        table.concat(G.collapse_keys(Z, "mx:"), ","), "mx:{C}")

  for k, v in pairs(real) do reaper[k] = v end
end

-- A strip's header IS the track's colour, and the track's colour is
-- whatever was picked -- pale yellow on one row, near-black on the next.
do
  -- The selected-strip outline. In "track" mode it is the track's own
  -- colour lightened -- used straight it would vanish into the fill it
  -- is supposed to be outlining.
  check("lighten moves towards white",
        U.lighten(0x000000ff, 1.0), 0xffffffff)
  check("and nothing stays nothing at zero",
        U.lighten(0x336699ff, 0), 0x336699ff)
  check("alpha is left alone",
        U.lighten(0x33669980, 0.5) & 0xff, 0x80)
  check("white cannot get whiter",
        U.lighten(0xffffffff, 0.5), 0xffffffff)
  check("track mode brightens the track's colour",
        U.sel_colour("track", 0x336699ff, 0x00ff00ff) ~= 0x336699ff, true)
  check("and is not the accent",
        U.sel_colour("track", 0x336699ff, 0x00ff00ff) ~= 0x00ff00ff, true)
  check("accent mode is the accent",
        U.sel_colour("accent", 0x336699ff, 0x00ff00ff), 0x00ff00ff)
  -- The master often has no colour of its own, and a nil there must not
  -- leave the strip with no outline at all.
  check("no track colour falls back to the accent",
        U.sel_colour("track", nil, 0x00ff00ff), 0x00ff00ff)

  check("dark background takes light text",
        U.contrast_text(0x101010ff) > 0x800000ff, true)
  check("light background takes dark text",
        U.contrast_text(0xf0f0f0ff) < 0x800000ff, true)
  -- Luma, not an average: the eye is far more sensitive to green than to
  -- blue, so a plain mean calls saturated blue "light" and puts black on
  -- it. Green and blue of the same numeric value must disagree.
  check("saturated blue is dark",  U.contrast_text(0x0000ffff) > 0x800000ff, true)
  check("saturated green is light", U.contrast_text(0x00ff00ff) < 0x800000ff, true)
  check("no colour still reads",   U.contrast_text(nil) ~= nil, true)
end

-- ---------------------------------------------------------------------
-- the routing lamps
-- ---------------------------------------------------------------------
-- Three lamps, and the whole point of them is to report what the panel
-- below cannot: the sends are in view, the parent send and anything
-- arriving from elsewhere are not.
do
  local SD = require "TS_CV_Sends"
  local TR, MASTER = {"track"}, {"master"}
  local real = {
    GetMasterTrack = reaper.GetMasterTrack,
    GetTrackNumSends = reaper.GetTrackNumSends,
    GetMediaTrackInfo_Value = reaper.GetMediaTrackInfo_Value,
  }
  local MAIN, NSEND, NRECV = 1, 0, 0
  reaper.GetMasterTrack = function() return MASTER end
  reaper.GetTrackNumSends = function(_, cat)
    if cat == 0 then return NSEND end
    if cat == -1 then return NRECV end
    return 0
  end
  reaper.GetMediaTrackInfo_Value = function(_, k)
    if k == "B_MAINSEND" then return MAIN end
    return 0
  end

  local function leds() local l = SD.route_leds(TR); return l[1], l[2], l[3] end

  MAIN, NSEND, NRECV = 1, 0, 0
  local p, sn, rc = leds()
  check("parent send lights on its own", p, true)
  check("no sends",                      sn, false)
  check("no receives",                   rc, false)

  MAIN, NSEND, NRECV = 0, 2, 0
  p, sn, rc = leds()
  check("parent off when disabled", p, false)
  check("sends light",              sn, true)

  MAIN, NSEND, NRECV = 0, 0, 3
  p, sn, rc = leds()
  check("receives light",            rc, true)
  check("and sends stay dark",       sn, false)

  MAIN, NSEND, NRECV = 1, 1, 1
  p, sn, rc = leds()
  check("all three at once", p and sn and rc, true)

  -- The master has nowhere to send to, so its parent lamp is off rather
  -- than reporting on a property it does not have.
  MAIN = 1
  local m = SD.route_leds(MASTER)
  check("the master has no parent lamp", m[1], false)

  check("nothing selected is three dark lamps",
        (function() local l = SD.route_leds(nil)
           return l[1] == false and l[2] == false and l[3] == false end)(), true)

  for k, v in pairs(real) do reaper[k] = v end
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
-- track operations: folders, colours, templates
-- ---------------------------------------------------------------------
-- The folder arithmetic and the file parsing behind the track menus are
-- pure functions over plain values, so they're checked here directly.
do
  local TO = require "TS_CV_TrackOps"
  local function same(a, b)
    if #a ~= #b then return false end
    for i = 1, #a do if a[i] ~= b[i] then return false end end
    return true
  end
  local function str(t) return table.concat(t, ",") end

  -- Levels are the running sum of the depths above each track.
  check("levels of a folder",
        str(TO.levels({ 1, 0, -1, 0 })), "0,1,1,0")
  check("levels of a nested folder",
        str(TO.levels({ 1, 1, -2, 0 })), "0,1,2,0")

  -- A block is one ordinary track, or a folder parent and its subtree.
  check("an ordinary track is its own block", TO.block_end({ 0, 0, 0 }, 2), 2)
  check("a folder's block ends at its last child",
        TO.block_end({ 0, 1, 0, -1, 0 }, 2), 4)
  check("a nested folder's block ends where it closes",
        TO.block_end({ 1, 0, 1, -2, 0 }, 3), 4)
  check("an unclosed folder runs to the end",
        TO.block_end({ 0, 1, 0, 0 }, 2), 4)

  -- Into the folder above: the track above opens (or stops closing) one
  -- level, and the block's last track closes one more.
  check("indent under an ordinary track makes it a parent",
        str(TO.indent_plan({ 0, 0, 0 }, 2)), "1,-1,0")
  check("indent after a folder's last child joins that folder",
        str(TO.indent_plan({ 1, -1, 0 }, 3)), "1,0,-1")
  check("indent a folder moves its children with it",
        str(TO.indent_plan({ 0, 1, -1, 0 }, 2)), "1,1,-2,0")
  check("the first track can't indent", TO.indent_plan({ 0, 0 }, 1), nil)
  check("a folder's first child can't indent further",
        TO.indent_plan({ 1, 0, -1 }, 2), nil)

  -- Out of the folder: only the last block in a folder can go.
  check("outdent an only child dissolves the folder",
        str(TO.outdent_plan({ 1, -1 }, 2)), "0,0")
  check("outdent the last child",
        str(TO.outdent_plan({ 1, 0, -1, 0 }, 3)), "1,-1,0,0")
  check("outdent a nested folder keeps its children",
        str(TO.outdent_plan({ 1, 0, 1, -2, 0 }, 3)), "1,-1,1,-1,0")
  check("a top-level track can't outdent", TO.outdent_plan({ 0, 0 }, 2), nil)
  check("a middle child can't outdent",
        TO.outdent_plan({ 1, 0, 0, -1 }, 2), nil)
  do
    -- Every plan keeps the structure valid: levels never go negative and
    -- no track sits more than one level below the track above it.
    local cases = { { 0, 0, 0 }, { 1, -1, 0 }, { 0, 1, -1, 0 }, { 1, 0, 1, -2, 0 },
                    { 1, 1, -1, 0, -1 }, { 1, 0, -1, 1, -1 } }
    local ok = true
    for _, d in ipairs(cases) do
      for k = 1, #d do
        for _, plan in ipairs({ (TO.indent_plan(d, k)), (TO.outdent_plan(d, k)) }) do
          local lv = TO.levels(plan)
          for i = 1, #plan do
            if lv[i] < 0 then ok = false end
            if i > 1 and lv[i] > lv[i - 1] + 1 then ok = false end
          end
          local total = 0
          for i = 1, #plan do total = total + plan[i] end
          local before = 0
          for i = 1, #d do before = before + d[i] end
          if total ~= before then ok = false end
        end
      end
    end
    check("every folder move keeps the tree valid", ok, true)
  end

  -- Collapsed folders hide their whole subtree; small (1) hides nothing.
  check("collapsed folder hides its children",
        str((function()
          local h = TO.hidden_by_folders({ 1, 0, -1, 0 }, { 2, 0, 0, 0 })
          local o = {} for i = 1, #h do o[i] = h[i] and 1 or 0 end return o
        end)()), "0,1,1,0")
  check("small folder hides nothing",
        str((function()
          local h = TO.hidden_by_folders({ 1, 0, -1, 0 }, { 1, 0, 0, 0 })
          local o = {} for i = 1, #h do o[i] = h[i] and 1 or 0 end return o
        end)()), "0,0,0,0")
  check("a collapsed outer folder hides an open inner one",
        str((function()
          local h = TO.hidden_by_folders({ 1, 1, -2, 0 }, { 2, 0, 0, 0 })
          local o = {} for i = 1, #h do o[i] = h[i] and 1 or 0 end return o
        end)()), "0,1,1,0")
  check("a collapsed inner folder hides only its own children",
        str((function()
          local h = TO.hidden_by_folders({ 1, 1, -1, 0, -1, 0 }, { 0, 2, 0, 0, 0, 0 })
          local o = {} for i = 1, #h do o[i] = h[i] and 1 or 0 end return o
        end)()), "0,0,1,0,0,0")

  -- A small folder (1) draws its children collapsed, and says which
  -- folder did it so that expanding one of them can open that folder.
  do
    local h, f, by = TO.folder_view({ 1, 0, -1, 0 }, { 1, 0, 0, 0 })
    check("small folder folds its children",
          (f[2] and f[3] and not f[1] and not f[4]) and true or false, true)
    check("and hides none of them", (h[2] or h[3]) and true or false, false)
    check("and names itself as the cause", by[2] and by[2][1], 1)
    local h2, f2 = TO.folder_view({ 1, 1, -2, 0 }, { 1, 2, 0, 0 })
    check("hidden beats folded", (h2[3] and not f2[3]) and true or false, true)
    check("an inner parent in a small folder is folded too", f2[2], true)
  end

  -- What moves when a track is dragged, and when it isn't really a move.
  check("drag an ordinary track", str(TO.move_set({ 0, 0, 0 }, 2, {})), "2")
  check("drag a folder brings its children",
        str(TO.move_set({ 0, 1, 0, -1, 0 }, 2, {})), "2,3,4")
  check("drag a selected track moves the selection",
        str(TO.move_set({ 0, 0, 0, 0 }, 2, { [2] = true, [4] = true })), "2,4")
  check("drag an unselected track leaves the selection",
        str(TO.move_set({ 0, 0, 0, 0 }, 3, { [2] = true, [4] = true })), "3")
  check("dropping into its own gap is no move", TO.is_move({ 2 }, 2), false)
  check("dropping just after itself is no move", TO.is_move({ 2 }, 3), false)
  check("dropping further along is a move", TO.is_move({ 2 }, 4), true)
  check("dropping inside a moved folder is no move", TO.is_move({ 2, 3, 4 }, 3), false)
  check("scattered tracks gathered after the last is a move",
        TO.is_move({ 2, 4 }, 5), true)

  -- REAPER's custom colours, as reaper.ini stores them: sixteen R G B pad
  -- groups, plus a trailing byte of REAPER's own that has to be ignored.
  local CUST = "1E48A800B21B1B0012620C00F36D3400F5EE1A00808000001ECAC100B21B4D00"
            .. "654DA100000000000000000000000000000000000000000000000000000000001D"
  local cc = TO.parse_custcolors(CUST)
  check("sixteen custom colours", #cc, 16)
  check("custom colour 1", ("%02X%02X%02X"):format(cc[1][1], cc[1][2], cc[1][3]), "1E48A8")
  check("custom colour 8", ("%02X%02X%02X"):format(cc[8][1], cc[8][2], cc[8][3]), "B21B4D")
  check("an unset slot is black", cc[16][1] + cc[16][2] + cc[16][3], 0)
  check("no custom colours is an empty list", #TO.parse_custcolors(nil), 0)
  check("custcolors read from the REAPER section only",
        TO.custcolors_from_ini("[other]\ncustcolors=FFFFFF00\n[REAPER]\nfoo=1\nCustColors=" .. CUST .. "\n[x]\n"),
        CUST)
  check("no REAPER section, no custcolors",
        TO.custcolors_from_ini("[other]\ncustcolors=FFFFFF00\n"), nil)

  -- REAPER 7.81's user palettes, as reaper-colors.ini holds them (CRLF,
  -- sections in any order, a name= only if a palette has one).
  local PALS = "[userpalette_1]\r\ncolors=71778A 6D8A7C 9C383F\r\n"
            .. "[userpalette_0]\r\ncolors=1E48A8 B21B1B 12620C F36D34\r\n"
            .. "[userpalette_2]\r\nname=Drums\r\ncolors=\r\n[other]\r\ncolors=FFFFFF\r\n"
  local up = TO.parse_user_palettes(PALS)
  check("three user palettes", #up, 3)
  check("in palette order, named as the picker names them", up[1].name .. "|" .. up[2].name, "User 1|User 2")
  check("a palette's own name wins", up[3].name, "Drums")
  check("User 1's colours", #up[1].colours, 4)
  check("User 2's first colour", ("%02X%02X%02X"):format(up[2].colours[1][1], up[2].colours[1][2], up[2].colours[1][3]), "71778A")
  check("an empty palette is empty", #up[3].colours, 0)
  check("no file, no palettes", #TO.parse_user_palettes(nil), 0)
  local all = TO.build_palettes(7.81, PALS, {}, cc)
  local order = {}
  for _, p in ipairs(all) do order[#order + 1] = p.name end
  check("palettes in the picker's order, custom colours last", table.concat(order, ","),
        "Project,REAPER,Primary,Pride,Perceptual,Warm,Cool,Vice,Casablanca,Devon,Technoir,"
        .. "User 1,User 2,Drums,User 4,Custom colours (SWS)")
  check("every built-in has sixteen colours", (function()
    for i = 2, 11 do if #all[i].colours ~= 16 then return all[i].name end end
    return true end)(), true)
  check("Pride's fifth colour", ("%02X%02X%02X"):format(all[4].colours[5][1], all[4].colours[5][2], all[4].colours[5][3]), "59A839")
  check("before 7.81, only the project and custom colours",
        #TO.build_palettes(7.80, PALS, {}, cc), 2)
  check("the picker's palette read from reaper.ini",
        TO.ini_value("[REAPER]\r\ncolorpick_palette=User 2\r\n", "colorpick_palette"), "User 2")

  -- A template's colour is its first track's PEAKCOL, flagged as set.
  local TPL = "<TRACK\n  NAME Acoust\n  PEAKCOL 23509357\n  BEAT -1\n"
           .. "  <TRACK\n  PEAKCOL 16777215\n"
  check("template colour from PEAKCOL", TO.template_colour(TPL), 23509357 & 0xffffff)
  check("an unset PEAKCOL is no colour",
        TO.template_colour("<TRACK\n  NAME x\n  PEAKCOL 16576\n"), nil)
  check("no PEAKCOL is no colour", TO.template_colour("<TRACK\n  NAME x\n"), nil)
  check("template name drops the extension",
        TO.template_name("Drums\\Kit 1.RTrackTemplate"), "Kit 1")
  check("template extension is case-insensitive",
        TO.is_template("bass.rtracktemplate"), true)
  check("other files are not templates", TO.is_template("notes.txt"), false)
end

-- Collapse state with a default: an untouched panel shows its default,
-- and only a departure from it is written to the project.
do
  local St = require "TS_CV_State"
  local store = {}
  local rg, rs = reaper.GetProjExtState, reaper.SetProjExtState
  reaper.GetProjExtState = function(_, _, k) return 1, store[k] or "" end
  reaper.SetProjExtState = function(_, _, k, v) store[k] = v end
  St.clear_cache()
  check("untouched, default collapsed",   St.is_collapsed("##rx", true), true)
  check("untouched, default expanded",    St.is_collapsed("##sx"), false)
  St.toggle_collapsed("##rx", true)
  check("toggled open from collapsed",    St.is_collapsed("##rx", true), false)
  check("and that is written as a 0",     store["collapsed:##rx"], "0")
  St.clear_cache()
  check("which survives a re-read",       St.is_collapsed("##rx", true), false)
  St.toggle_collapsed("##rx", true)
  check("back to the default clears it",  store["collapsed:##rx"], "")
  St.set_collapsed("##sx", true)
  check("a plain collapse is still a 1",  store["collapsed:##sx"], "1")
  St.set_collapsed("##sx", false)
  check("and a plain expand still clears", store["collapsed:##sx"], "")
  St.clear_cache()
  reaper.GetProjExtState, reaper.SetProjExtState = rg, rs
end

-- Keyboard focus goes back to REAPER only after a click here, and only
-- once nothing here still wants the keyboard.
do
  local F = require "TS_CV_Focus"
  local s = {}
  local function f(c, b, p) return F.step(s, { clicked = c, busy = b, popup = p }) end
  check("nothing clicked, nothing happens",   f(false, false, false), false)
  check("not while the button is held",       f(true, true, false), false)
  check("on release after a click",            f(false, false, false), true)
  check("and only once",                       f(false, false, false), false)
  f(true, true, false)                        -- click that opens a menu
  check("not while a menu is open",            f(false, true, true), false)
  check("but as soon as it closes",            f(false, false, false), true)
  check("a text field keeps it",               (function() f(true, true, false); return f(false, true, false) end)(), false)
  check("until it's done with",                f(false, false, false), true)
  check("a popup closing hands back too",      (function() f(false, true, true); return f(false, false, false) end)(), true)

  -- Where it goes: the arrange view, or the tracks after a track was
  -- clicked (Insert FX actions follow the context).
  local saved = {}
  for _, k in ipairs({ "JS_Window_SetFocus", "JS_Window_FindChildByID", "GetMainHwnd",
                       "SetCursorContext", "NamedCommandLookup" }) do saved[k] = reaper[k] end
  local calls = {}
  reaper.GetMainHwnd = function() return "main" end
  reaper.JS_Window_FindChildByID = function() return "arrange" end
  reaper.JS_Window_SetFocus = function(h) calls[#calls + 1] = "focus " .. h end
  reaper.SetCursorContext = function(m) calls[#calls + 1] = "context " .. m end
  local h = {}
  local _, to = F.hand_back(h)
  check("hands back to the arrange view",      to, "arrange")
  check("without touching the context",        table.concat(calls, ","), "focus arrange")
  calls = {}
  h.tracks = true
  _, to = F.hand_back(h)
  check("after a track click, to the tracks",  to, "tracks")
  check("focus, then the tracks as context",   table.concat(calls, ","), "focus arrange,context 0")
  check("only for that one hand-back",         h.tracks, nil)
  for _, k in ipairs({ "JS_Window_SetFocus", "JS_Window_FindChildByID", "GetMainHwnd",
                       "SetCursorContext", "NamedCommandLookup" }) do reaper[k] = saved[k] end
end

-- Track icons: no icon, or one whose file can't be found, draws nothing.
do
  local IC = require "TS_CV_Icons"
  check("no icon resolves to nothing",      IC.resolve(nil), nil)
  check("an empty icon resolves to nothing", IC.resolve(""), nil)
  check("a missing file resolves to nothing", IC.resolve("no_such_icon_here.png"), nil)
  check("and stays missing on a second look", IC.resolve("no_such_icon_here.png"), nil)
end

-- Record input: REAPER packs it into one number.
do
  local IN = require "TS_CV_Inputs"
  local names = { [0] = "Mic", [1] = "DI" }
  local function nm(i) return names[i] end
  check("no input",                 IN.label(-1, nm), "No input")
  check("mono input 1",             IN.audio(0, false), 0)
  check("stereo 3/4",               IN.audio(2, true), 1024 + 2)
  check("all MIDI, all channels",   IN.midi(63, 0), 6112)
  check("MIDI device 2, channel 10", IN.midi(2, 10), 4096 + 64 + 10)
  check("decodes MIDI device",      IN.decode(IN.midi(2, 10)).dev, 2)
  check("decodes MIDI channel",     IN.decode(IN.midi(2, 10)).ch, 10)
  check("decodes a stereo pair",    IN.decode(1024 + 2).stereo, true)
  check("and its first channel",    IN.decode(1024 + 2).first, 2)
  check("mono label uses the name", IN.label(0, nm), "Mic")
  check("stereo label names both",  IN.label(IN.audio(0, true), nm), "Mic/DI")
  check("unnamed input numbered",   IN.label(5, nm), "In 6")
  check("all MIDI label",           IN.label(6112, nm), "All MIDI")
  check("VKB channel label",        IN.label(IN.midi(62, 3), nm), "VKB ch 3")
  check("multichannel label",       IN.label(2048 + 0, nm), "Mic+")
end

-- Dragging a track onto another: the outer quarters are the gaps either
-- side, the middle half is "make it a child of this one".
do
  local TO = require "TS_CV_TrackOps"
  check("top edge is the gap before",     TO.drop_zone(0.1), "before")
  check("above the track is the gap too", TO.drop_zone(-2), "before")
  check("the middle is into",             TO.drop_zone(0.5), "into")
  check("a quarter in is into",           TO.drop_zone(0.25), "into")
  check("bottom edge is the gap after",   TO.drop_zone(0.9), "after")
  check("nest into another track",        TO.can_nest({ 3 }, 5), true)
  check("not into itself",                TO.can_nest({ 3 }, 3), false)
  check("not into its own child",         TO.can_nest({ 3, 4, 5 }, 4), false)
  check("not into the master",            TO.can_nest({ 3 }, nil), false)
  check("nothing to nest",                TO.can_nest({}, 2), false)

  -- The TCP's module, where it's installed alongside.
  local has_ar, AR = pcall(require, "TS_CV_Arrange")
  if has_ar then
  -- Three drawn rows 20 tall at y 0, 20, 40; track 3 hidden (a folded
  -- child), track 4 at y 40; the master first.
  local rows = {
    { master = true, num = 0, y = -30, h = 30, env = 0 },
    { num = 1, y = 0,  h = 20, env = 0 },
    { num = 2, y = 20, h = 20, env = 0 },
    { num = 3, y = 40, h = 0,  env = 0 },
    { num = 4, y = 40, h = 20, env = 10 },
  }
  local b, ly, into = AR.drop_target(rows, 2, 4)
  check("top of track 1: before it",       b, 0)
  check("  marker at its top",             ly, 0)
  b, ly, into = AR.drop_target(rows, 10, 4)
  check("middle of track 1: into it",      into and into.num, 1)
  check("  and no gap",                    b, nil)
  b, ly, into = AR.drop_target(rows, 38, 4)
  check("bottom of track 2: before the next drawn row", b, 3)
  check("  marker at its bottom",          ly, 40)
  b = AR.drop_target(rows, 65, 4)
  check("envelope lanes: the gap after",   b, 4)
  b, ly = AR.drop_target(rows, 200, 4)
  check("below everything: the end",       b, 4)
  check("  marker under the last lanes",   ly, 70)
  end
end

-- ---------------------------------------------------------------------
-- ChannelView TCP: envelope state chunks
-- ---------------------------------------------------------------------
do
  local EN = require "TS_CV_Envelopes"
  local ch = "<PARMENV 3 0 1 0.5\nACT 1 -1\nVIS 1 1 1\nLANEHEIGHT 0 0\nARM 0\nDEFSHAPE 0 -1 -1\nPT 0 0.5 0\n>"
  local f = EN.parse_flags(ch)
  check("envelope: active read",            f.act, true)
  check("envelope: visible read",           f.vis, true)
  check("envelope: in its own lane",        f.lane, true)
  check("envelope: not armed",              f.arm, false)
  local c2 = EN.set_flag(EN.set_flag(ch, "arm", true), "act", false)
  local f2 = EN.parse_flags(c2)
  check("arm set",                          f2.arm, true)
  check("bypass set",                       f2.act, false)
  check("and nothing else moved",           f2.vis and f2.lane, true)
  check("ACT keeps its second field",       c2:find("\nACT 0 %-1") ~= nil, true)
  local c3 = EN.set_flag(ch, "lane", false)
  check("lane off leaves visible on",       EN.parse_flags(c3).vis, true)
  check("and turns the lane off",           EN.parse_flags(c3).lane, false)
  check("VIS keeps its third field",        c3:find("\nVIS 1 0 1") ~= nil, true)
  local bare = "<VOLENV2\nPT 0 1 0\n>"
  check("missing lines read as defaults",   EN.parse_flags(bare).act and EN.parse_flags(bare).vis, true)
  local c4 = EN.set_flag(bare, "arm", true)
  check("a missing line is added",          EN.parse_flags(c4).arm, true)
  check("after the envelope's own tag",     c4:sub(1, 13), "<VOLENV2\nARM ")
  check("points untouched",                 c4:find("PT 0 1 0", 1, true) ~= nil, true)
  check("lane height replaced",              EN.set_lane_height("<X\nLANEHEIGHT 40 0\nPT 0 1\n>", 72.4):find("\nLANEHEIGHT 72 0\n") ~= nil, true)
  check("lane height added when missing",   EN.set_lane_height("<X\nPT 0 1\n>", 30):sub(1, 18), "<X\nLANEHEIGHT 30 0")
  check("zero is REAPER's default",         EN.set_lane_height("<X\nLANEHEIGHT 55 1\n>", 0):find("LANEHEIGHT 0 1") ~= nil, true)
  check("no points: one at the start",       EN.write_plan(0, false), "first")
  check("one point: move it (flat line)",   EN.write_plan(1, false), "only")
  check("a point here: move it",            EN.write_plan(5, true), "move")
  check("otherwise: insert one",            EN.write_plan(5, false), "insert")
  local tchunk = "<TRACK\nNAME x\nMAINSEND 1 0\n<FXCHAIN\nSHOW 0\n>\n>"
  local withenv = EN.insert_env_block(tchunk, EN.env_block("<VOLENV2"))
  check("envelope block goes before the FX chain", withenv:find("<VOLENV2", 1, true) < withenv:find("<FXCHAIN", 1, true), true)
  check("and the chunk still ends the track",      withenv:sub(-2), "\n>")
  local bare = EN.insert_env_block("<TRACK\nNAME x\n>", EN.env_block("<PANENV2"))
  check("no FX chain or items: before the end",    bare, "<TRACK\nNAME x\n<PANENV2\nACT 1 -1\nVIS 1 1 1\nLANEHEIGHT 0 0\nARM 0\nDEFSHAPE 0 -1 -1\nPT 0 0 0\n>\n>")
  check("a new envelope starts with a point", EN.env_block("<VOLENV2", 0.5):find("\nPT 0 0.5 0\n", 1, true) ~= nil, true)
  check("mute's point is square",           EN.env_block("<MUTEENV", 1, 1):find("\nPT 0 1 1\n", 1, true) ~= nil, true)
  do
    local SUm = require "TS_CV_Startup"
    local SUt = SUm.make("ChannelView TCP", "TS_ChannelView_TCP.lua", "channelview_tcp_cmd")
    local both = SUt.fenced_add(SUm.fenced_add("-- start\n", "_RSaaa"), "_RSbbb")
    check("two scripts, two startup blocks",  SUm.classify(both, "_RSaaa") .. "/" .. SUt.classify(both, "_RSbbb"), "ours/ours")
    local less = SUt.fenced_remove(both)
    check("removing the TCP's keeps ChannelView's", SUm.classify(less, "_RSaaa") .. "/" .. SUt.classify(less, "_RSbbb"), "ours/none")
    local less2 = SUm.fenced_remove(both)
    check("and the other way round",          SUm.classify(less2, "_RSaaa") .. "/" .. SUt.classify(less2, "_RSbbb"), "none/ours")
  end
  do
    -- the rack's block beside ChannelView's own: neither label's markers
    -- may be read as the other's
    local SUm = require "TS_CV_Startup"
    local SUr = SUm.make("ChannelView Rack", "TS_ChannelView_Rack.lua", "channelview_rack_cmd")
    local both = SUr.fenced_add(SUm.fenced_add("-- start\n", "_RSaaa"), "_RSrrr")
    check("rack and ChannelView blocks side by side", SUm.classify(both, "_RSaaa") .. "/" .. SUr.classify(both, "_RSrrr"), "ours/ours")
    local a1, a2 = SUm.fenced_remove(both), SUr.fenced_remove(both)
    check("removing ChannelView's keeps the rack's", SUm.classify(a1, "_RSaaa") .. "/" .. SUr.classify(a1, "_RSrrr"), "none/ours")
    check("removing the rack's keeps ChannelView's", SUm.classify(a2, "_RSaaa") .. "/" .. SUr.classify(a2, "_RSrrr"), "ours/none")
    check("rack first, then ChannelView", SUm.classify(SUm.fenced_add(SUr.fenced_add(nil, "_RSrrr"), "_RSaaa"), "_RSaaa"), "ours")
    check("rack and ChannelView compile", load(both) ~= nil, true)
  end
  do
    -- the web companion's block beside ChannelView's own
    local SUm = require "TS_CV_Startup"
    local WEBs = SUm.make("ChannelView web companion", "ChannelView", "channelview_web_cmd")
    local both = WEBs.fenced_add(SUm.fenced_add("-- start\n", "_RSaaa"), "_RSwww")
    check("web and ChannelView blocks side by side", SUm.classify(both, "_RSaaa") .. "/" .. WEBs.classify(both, "_RSwww"), "ours/ours")
    check("removing ChannelView's keeps the web one", WEBs.classify(SUm.fenced_remove(both), "_RSwww"), "ours")
    check("removing the web one keeps ChannelView's", SUm.classify(WEBs.fenced_remove(both), "_RSaaa"), "ours")
    check("the result compiles", load(both) ~= nil, true)
    -- the web script's id out of reaper-kb.ini
    local KB = 'ACT 0 0 "x" "Custom: thing" 40001\r\n'
            .. 'SCR 4 32060 RS1111 "Custom: TS_ChannelView_Web.lua" "TS_ChannelView/TS_ChannelView_Web.lua"\r\n'
            .. 'SCR 4 0 RS2222 "Custom: TS_ChannelView.lua" "TS_ChannelView/TS_ChannelView.lua"\r\n'
            .. 'SCR 4 0 RS3333 "Custom: TS_ChannelView_Web.lua" "TS-ReaScripts\\TS_ChannelView\\TS_ChannelView_Web.lua"\r\n'
    check("the web script's id, Main section only", SUm.kb_find(KB, "TS_ChannelView_Web.lua"), "_RS3333")
    check("a name that only ends the same doesn't match",
          SUm.kb_find('SCR 4 0 RS9 "Custom: x" "Foo/MyTS_ChannelView_Web.lua"\n', "TS_ChannelView_Web.lua"), nil)
    check("no kb file, no id", SUm.kb_find(nil, "TS_ChannelView_Web.lua"), nil)
  end
  do
    -- a master's hardware outputs (the Sends panel's Outputs)
    local HO = require "TS_CV_HwOut"
    check("output 1/2",            HO.label(0), "1/2")
    check("output 3/4",            HO.label(2), "3/4")
    check("output 5 alone",        HO.label(4 | 1024), "5")
    check("ReaRoute",              HO.label(512), "RR 1/2")
    local f, n = HO.decode(6 | 1024)
    check("decoded mono 7",        f .. "/" .. n, "6/1")
    local ch = HO.choices(5, function(d) return "x" .. d end)
    check("five outputs: two pairs, five singles", #ch.stereo .. "/" .. #ch.mono, "2/5")
    check("the pairs go up in twos", ch.stereo[2].dst, 2)
    check("the singles are flagged mono", ch.mono[5].dst, 4 | 1024)
  end
  do
    -- is a page connected?
    local WL = require "TS_CV_WebLink"
    local st = WL.new()
    WL.update(st, 0, "41", "abc.7")              -- left over from before: proves nothing
    local r, n = WL.state(st, 0.1)
    check("leftover values: not running, no pages", tostring(r) .. "/" .. n, "false/0")
    WL.update(st, 0.5, "42", "abc.7")
    r, n = WL.state(st, 0.6)
    check("the counter moves: running, still no page", tostring(r) .. "/" .. n, "true/0")
    WL.update(st, 1.0, "50", "abc.8")
    WL.update(st, 1.5, "60", "xyz.1")
    r, n = WL.state(st, 1.6)
    check("two pages beating", n, 2)
    WL.update(st, 7.0, "70", "xyz.2")
    r, n = WL.state(st, 7.1)
    check("one goes quiet, one is left", n, 1)
    r = WL.state(st, 7.0 + WL.BRIDGE_GONE + 0.1)
    check("the bridge goes quiet: not running", r, false)
    WL.update(st, 20, "", "xyz.2")
    r = WL.state(st, 20)
    check("the bridge cleared its counter: not running", r, false)
  end
end

-- ---------------------------------------------------------------------
-- ChannelView TCP: fixed item lanes
-- ---------------------------------------------------------------------
do
  local LN = require "TS_CV_Lanes"
  local fr = LN.fractions(4, { [2] = { y = 0.52, h = 0.24 } })
  check("lanes without items share evenly",   fr[0].y .. "/" .. fr[0].h, "0.0/0.25")
  check("a lane with an item uses its place",  fr[2].y .. "/" .. fr[2].h, "0.52/0.24")
  check("the last lane still gets its share",  fr[3].y, 0.75)
  check("click a silent lane: plays alone",    LN.next_play(0, false), 1)
  check("click the lone lane: stops",          LN.next_play(1, false), 0)
  check("click one playing along: alone",      LN.next_play(2, false), 1)
  check("ctrl-click a silent lane: along",     LN.next_play(0, true), 2)
  check("ctrl-click one playing along: stops", LN.next_play(2, true), 0)
  check("ctrl-click the lone lane: along",     LN.next_play(1, true), 2)
  local pl = { [0] = 1, [1] = 0, [2] = 2, [3] = 0 }
  local iso = LN.isolate_for_delete(pl, 4, 1)
  check("delete lane 2: only it goes silent",  ("%d%d%d%d"):format(iso[0], iso[1], iso[2], iso[3]), "1022")
  local aft = LN.after_delete(pl, 4, 1)
  check("and the rest move up after",          ("%d%d%d"):format(aft[0], aft[1], aft[2]), "120")
  check("nothing past the new end",            aft[3], nil)
end

-- Probe taps: channel bookkeeping and the record kept on the track.
do
  local TP = require "TS_CV_Taps"
  local lo, hi = TP.bit(5)
  check("channel 5 is bit 4",             lo, 16)
  check("  in the low half",              hi, 0)
  lo, hi = TP.bit(33)
  check("channel 33 is the high half",    hi, 1)
  local set = TP.channels_of(3 | 16, 2)
  check("masks back to channels",         (set[1] or false) and (set[2] or false) and set[5] and set[34], true)
  check("and nothing else",               set[3] or set[33] or false, false)

  local used = { [1] = true, [2] = true, [3] = true, [4] = true }
  local a = TP.alloc(used, 5, 2)
  check("first pairs from 5/6",           a and (a[1] .. "," .. a[2]), "5,7")
  used[7] = true
  a = TP.alloc(used, 5, 2)
  check("a used channel skips its pair",  a and (a[1] .. "," .. a[2]), "5,9")
  check("alloc leaves the caller's set",  used[5], nil)
  check("no room: nil",                   TP.alloc({}, 63, 2), nil)
  check("start at 5 normally",            TP.start_channel(2), 5)
  check("above a 6-channel parent",       TP.start_channel(6), 7)
  check("an odd start stays odd",         TP.start_channel(8), 9)

  local sc = TP.send_channels(4)                    -- stereo from 5/6
  check("a stereo send covers two",       (sc[5] and sc[6] and not sc[7]) and true or false, true)
  sc = TP.send_channels(1024 + 6)                   -- mono from 7
  check("a mono send covers one",         (sc[7] and not sc[8]) and true or false, true)
  sc = TP.send_channels(2 * 1024 + 0)               -- 4 channels from 1
  check("a 4-channel send covers four",   (sc[4] and not sc[5]) and true or false, true)
  check("no channel, nothing",            next(TP.send_channels(-1)), nil)

  local rec = { level = "TOP", probe = "{P}", taps = {
    { guid = "{A}", prev = "{Z}", pre = 5, post = 7, lag = 64 },
    { guid = "{B}", prev = "{A}", pre = 9, post = 11, lag = 0 } } }
  local back = TP.parse_record(TP.format_record(rec))
  check("record round trip: taps",        back and #back.taps, 2)
  check("  channels",                     back and (back.taps[2].pre .. "/" .. back.taps[2].post), "9/11")
  check("  latency",                      back and back.taps[1].lag, 64)
  check("  probe",                        back and back.probe, "{P}")
  check("nothing recorded: empty string", TP.format_record(nil), "")
  check("junk isn't a record",            TP.parse_record("hello"), nil)
  check("same plugins, same shape",       TP.same_shape(rec, back), true)
  local moved = TP.parse_record(TP.format_record(rec)); moved.taps[2].prev = "{Y}"
  check("a different neighbour isn't",    TP.same_shape(rec, moved), false)
  check("nothing and nothing agree",      TP.same_shape(nil, nil), true)
  check("something and nothing don't",    TP.same_shape(rec, nil), false)
end

-- Abbreviating a name to fit:-- Abbreviating a name to fit: short forms, then filler words, then
-- vowels from the right, then spaces, and only then a cut.
do
  local function ab(s, n) return U.abbreviate(s, function(x) return #x <= n end) end
  check("fits already: untouched",       ab("Drive", 8), "Drive")
  check("brackets go first",             ab("Threshold (dB)", 9), "Threshold")
  check("audio short form",              ab("Frequency", 6), "Freq")
  check("short forms keep their case",   ab("low frequency", 8), "lo freq")
  check("all caps stays caps",           ab("STEREO WIDTH", 8), "ST WIDTH")
  check("filler word dropped",           ab("Resonance Control", 8), "Reso")
  check("closing spaces when enough",    ab("Output Gain", 7), "OutGain")
  check("vowels from the right",         ab("Reverb Drive", 8), "Verb Drv")
  check("never a word's first letter",   ab("Band 2 Gain", 6), "Bnd2Gn")
  check("cut last, with a dot",          ab("Dry/Wet Mix", 7), "Dry/Wt.")
  check("never longer than asked",       #ab("Supercalifragilistic Level", 5) <= 5, true)
end

-- Live names: for plugins that rename their own parameters.
do
  local M = require "TS_CV_Mappings"
  check("label wins normally",           M.display_name("nokey", 3, "Macro 1", "Deess"), "Macro 1")
  check("live: the plugin's name",       M.display_name("nokey", 3, "Macro 1", "Deess", true), "Deess")
  check("live: trimmed",                 M.display_name("nokey", 3, "", "  Deess ", true), "Deess")
  check("live with no name: numbered",   M.display_name("nokey", 3, "Macro 1", "", true), "P3")
  local l = { live = true, aliases = {}, controls = {
    { param = 0, type = "knob", label = "Macro 1", live = true },
    { param = 1, type = "knob", label = "Macro 2" } } }
  local c = M.copy(l)
  check("copy keeps plugin-level live",  c.live, true)
  check("copy keeps slot live",          c.controls[1].live, true)
  check("and leaves the others off",     c.controls[2].live, nil)
end

-- FX chains: REAPER's own .RfxChain files, named without the extension.
do
  local CN = require "TS_CV_Chains"
  check("a chain file",               CN.is_chain("Lead Vocal.RfxChain"), true)
  check("any case",                   CN.is_chain("drums.RFXCHAIN"), true)
  check("not a track template",       CN.is_chain("Bus.RTrackTemplate"), false)
  check("not a chain in its name",    CN.is_chain("RfxChain notes.txt"), false)
  check("named without the extension", CN.chain_name("Lead Vocal.RfxChain"), "Lead Vocal")
  check("dots in the name kept",      CN.chain_name("Mix v2.1.rfxchain"), "Mix v2.1")
  -- saving: the chain's block from a track chunk, without its window lines
  local CH = table.concat({
    "<TRACK", "NAME x", "<FXCHAIN", "WNDRECT 1 2 3 4", "SHOW 0", "LASTSEL 1", "DOCKED 0",
    "BYPASS 0 0 0", "<JS a/b \"\"", "0 0 -", ">", "FLOATPOS 0 0 0 0", "FXID {A}", "WAK 0 0",
    "BYPASS 0 0 0", "<CONTAINER Container \"Bus\"", "CONTAINER_CFG 2 2 2 0", "SHOW 0", "LASTSEL 0", "DOCKED 0",
      "BYPASS 0 0 0", "<VST \"VST3: X\" x.vst3 0 \"\" 1", "QUJD", ">", "FXID {B}", "WAK 0 0",
      "BYPASS 1 0 0", "<CONTAINER Container \"\"", "CONTAINER_CFG 2 2 2 0", "SHOW 0", "LASTSEL 0", "DOCKED 0",
        "BYPASS 0 0 0", "<JS c/d \"\"", ">", "FXID {D}", "WAK 0 0",
      ">", "FXID {C2}", "WAK 0 0",
    ">", "FLOATPOS 0 0 0 0", "FXID {C}", "WAK 0 0",
    ">", "<FXCHAIN_REC", "BYPASS 0 0 0", "<JS rec \"\"", ">", "WAK 0 0", ">", ">" }, "\n")
  local whole = CN.chain_text(CH)
  check("save: starts at the first plugin", whole:match("^[^\n]*"), "BYPASS 0 0 0")
  check("save: no window lines", whole:find("WNDRECT", 1, true) == nil and whole:find("LASTSEL 1", 1, true) == nil, true)
  check("save: ends with the last plugin", whole:sub(-17), "FXID {C}\nWAK 0 0\n")
  check("save: not the input FX", whole:find("rec", 1, true) == nil, true)
  local box = CN.chain_text(CH, { 1 })
  check("save container: from its BYPASS", box:match("^[^\n]*\n[^\n]*"), "BYPASS 0 0 0\n<CONTAINER Container \"Bus\"")
  check("save container: all of it", box:sub(-17), "FXID {C}\nWAK 0 0\n")
  local inner = CN.chain_text(CH, { 1, 1 })
  check("save nested container", inner:match("^[^\n]*\n[^\n]*"), "BYPASS 1 0 0\n<CONTAINER Container \"\"")
  check("save nested: stops at its own end", inner:sub(-18), "FXID {C2}\nWAK 0 0\n")
  check("save: nothing at a bad path", tostring(CN.chain_text(CH, { 5 })), "nil")
  check("save: no chain", tostring(CN.chain_text("<TRACK\nNAME x\n>")), "nil")
  check("chain name made safe", CN.safe_name(' a/b:c*? "d" . '), "a b c d")

  -- your FX Folders: read, edited and written back
  local FI = require "TS_CV_FXIndex"
  local INI = table.concat({
    "[developer]", "X.vst3=Acme", "",
    "[Folder0]", "Item0=C:\\VST3\\Pro-C 2.vst3", "Item1=C:\\VST3\\Saturn 2.vst3", "Nb=2", "Type0=3", "Type1=3", "",
    "[Folder1]", "Item0=Drums", "Nb=1", "Type0=1000", "",
    "[Folder2]", "Nb=0", "",
    "[Folders]", "Id0=0", "Id1=2", "Id2=1", "Name0=Favourites", "Name1=-----", "Name2=Chains", "NbFolders=3", "" }, "\n")
  local fm = FI.parse_folders(INI)
  check("folders: in their order", #fm.order .. " " .. fm.order[1].name .. "/" .. fm.order[3].name, "3 Favourites/Chains")
  -- smart folders: a search, as the browser's filter takes it
  check("smart: words, all of them", FI.smart_match("pro q", "VST3: Pro-Q 3 (FabFilter)", "Pro-Q 3.vst3"), true)
  check("smart: not every word", FI.smart_match("pro comp", "VST3: Pro-Q 3 (FabFilter)", "Pro-Q 3.vst3"), false)
  check("smart: OR", FI.smart_match("saturn OR pro-q", "VST3: Pro-Q 3 (FabFilter)", ""), true)
  check("smart: NOT", FI.smart_match("fabfilter NOT pro-q", "VST3: Pro-Q 3 (FabFilter)", ""), false)
  check("smart: a phrase", tostring(FI.smart_match('"pro-q 3"', "VST3: Pro-Q 3 (FabFilter)", "")) ..
        tostring(FI.smart_match('"q pro"', "VST3: Pro-Q 3 (FabFilter)", "")), "truefalse")
  check("smart: the file name too", FI.smart_match("vst3", "JS: x", "C:/a/Thing.vst3"), true)
  check("smart: case-blind", FI.smart_match("EQ", "VST3: ReaEQ (Cockos)", ""), true)
  do
    local dir = os.tmpname(); os.remove(dir); os.execute('mkdir -p "' .. dir .. '"')
    local fh = io.open(dir .. "/reaper-fxfolders.ini", "w")
    fh:write(table.concat({
      "[Folder3]", "Item0=C:\\VST3\\Saturn 2.vst3", "Nb=1", "Type0=3", "",
      "[Folder7]", "Item0=reaeq OR pro-q", "Nb=1", "Type0=1048576", "",
      "[Folders]", "Id0=7", "Id1=3", "Name0=EQs", "Name1=Mine", "NbFolders=2", "" }, "\n"))
    fh:close()
    local grp = reaper.GetResourcePath
    reaper.GetResourcePath = function() return dir end
    FI.reset()
    local items = { { name = "VST3: Pro-Q 3 (FabFilter)", ident = "Pro-Q 3.vst3" },
                    { name = "VST3: Saturn 2 (FabFilter)", ident = "Saturn 2.vst3" },
                    { name = "VST: ReaEQ (Cockos)", ident = "reaeq.dll" } }
    local _, _, folds = FI.build(items)
    local by = {}
    for _, f in ipairs(folds) do by[#by + 1] = f.name .. "=" .. f.count end
    check("smart: listed, in the browser's order, with what matches", table.concat(by, ","), "EQs=2,Mine=1")
    check("smart: a plugin in it", tostring(items[1].folders and items[1].folders[7]) .. " " ..
          tostring(items[2].folders and items[2].folders[7]) .. " " .. tostring(items[2].folders and items[2].folders[3]) ..
          " " .. tostring(items[3].folders and items[3].folders[7]), "true nil true true")
    local m2 = FI.read_folders and FI.parse_folders(io.open(dir .. "/reaper-fxfolders.ini"):read("a"))
    check("smart: not offered to put a plugin in", #FI.folder_list(m2) .. " " .. tostring(FI.is_smart(m2, 7)), "1 true")
    -- made, and its search changed
    local id = FI.folder_new(m2, "Comps")
    check("smart: made from a search", tostring(FI.set_smart(m2, id, " comp NOT multi ")) .. " " .. FI.smart_of(m2, id), "true comp NOT multi")
    check("smart: renamed", tostring(FI.folder_rename(m2, id, "Compressors")) .. " " .. m2.order[#m2.order].name, "true Compressors")
    local back = FI.parse_folders(FI.write_folders(m2))
    check("smart: written as REAPER writes one", tostring(FI.is_smart(back, id)) .. " " .. FI.smart_of(back, id) .. " " .. #back.folders[id].items,
          "true comp NOT multi 1")
    check("smart: no empty search", FI.set_smart(m2, id, "  "), false)
    reaper.GetResourcePath = grp
    FI.reset()
    os.remove(dir .. "/reaper-fxfolders.ini"); os.remove(dir)
  end
  check("folders: separators left out of the menu", #FI.folder_list(fm), 2)
  check("folders: has, by file name", FI.folder_has(fm, 0, "C:/Other/pro-c_2.vst3"), true)
  check("folders: kind of a VST3", FI.kind_of("VST3: Pro-C 2 (FabFilter)") .. FI.kind_of("JS: x") .. FI.kind_of("CLAP: y"), "327")
  check("folders: add", FI.folder_add(fm, 0, "C:\\VST3\\Pro-Q 3.vst3", 3), true)
  check("folders: no twice", FI.folder_add(fm, 0, "C:\\VST3\\Pro-Q 3.vst3", 3), false)
  check("folders: remove", FI.folder_remove(fm, 0, "Saturn 2.vst3"), true)
  local nid = FI.folder_new(fm, "Comps")
  FI.folder_add(fm, nid, "JS: loser/comp", 2)
  local out = FI.write_folders(fm)
  local back = FI.parse_folders(out)
  check("folders: other sections kept", out:sub(1, 23), "[developer]\nX.vst3=Acme")
  check("folders: written and read back", table.concat(back.folders[0].items, "|") .. " " ..
        table.concat(back.folders[0].types, "|"), "C:\\VST3\\Pro-C 2.vst3|C:\\VST3\\Pro-Q 3.vst3 3|3")
  check("folders: a chain folder untouched", back.folders[1].items[1] .. "/" .. back.folders[1].types[1], "Drums/1000")
  check("folders: the new one last", back.order[4].id .. " " .. back.order[4].name .. " " .. #back.folders[nid].items, "3 Comps 1")
  check("folders: count", out:match("NbFolders=(%d+)"), "4")
  check("no chains: nothing to offer", CN.has_chains({ dirs = {}, files = {} }), false)
  check("a chain in a subfolder counts", CN.has_chains({ files = {}, dirs = { { name = "Vox",
    node = { dirs = {}, files = { { name = "Lead" } } } } } }), true)
  check("no tree at all",              CN.has_chains(nil), false)
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
    "TS_CV_Startup", "TS_CV_Mixer", "TS_CV_TrackMenu", "TS_CV_TrackOps",
    "TS_CV_Receives", "TS_CV_Focus", "TS_CV_Icons", "TS_CV_Inputs",
    "TS_ChannelView_TCP", "TS_CV_Arrange", "TS_CV_Toolbar", "TS_CV_Envelopes", "TS_CV_Actions", "TS_CV_Lanes",
    "TS_CV_Chains", "TS_CV_Taps", "TS_CV_WebLink", "TS_ChannelView_Web_Startup", "TS_CV_HwOut",
    "TS_CV_Drawers", "TS_CV_ActionEditor", "TS_ChannelView_Toolbars", "TS_ChannelView_OrganiseActions",
    "TS_CV_Vendors", "TS_ChannelView_ToggleToolbars", "TS_ChannelView_ToggleRackToolbars",
  }

  -- Comments only: a "-- see W.foo()" in prose must not read as a call.
  -- Crude on purpose -- a "--" inside a string literal would be eaten
  -- too, and none of these files has one.
  local function strip(src)
    src = src:gsub("%-%-%[%[.-%]%]", " ")
    return (src:gsub("%-%-[^\n]*", " "))
  end

  local missing, checked = {}, 0
  local attached = {}   -- modules something calls .attach() on
  local present  = {}   -- files that exist here (the TCP's may not)
  for _, file in ipairs(FILES) do
    local fh = io.open(HERE .. "../" .. file .. ".lua", "r")
    if fh then
      present[file] = true
      local src = strip(fh:read("a")); fh:close()

      local bind = {}
      for alias, mod in src:gmatch("local%s+([%w_]+)%s*=%s*require%s*%(?%s*[\"\']([%w_]+)[\"\']") do
        if mod:match("^TS_CV_") then bind[alias] = mod end
      end
      -- Pro's modules, by way of TS_CV_Edition (ED.module("X"), and its
      -- stand-ins for the Light and the Switches)
      for alias, mod in src:gmatch("local%s+([%w_]+)%s*=%s*[^\n]-%.module%s*%(%s*[\"\']([%w_]+)[\"\']") do
        bind[alias] = mod
      end
      for alias in src:gmatch("local%s+([%w_]+)%s*=%s*[^\n]-%.switches%s*%(") do bind[alias] = "TS_CV_Switches" end
      for alias in src:gmatch("local%s+([%w_]+)%s*=%s*[^\n]-%.light%s*%(") do bind[alias] = "TS_CV_Light" end
      for alias in src:gmatch("local%s+([%w_]+)%s*=%s*[^\n]-%.thumbs%s*%(") do bind[alias] = "TS_CV_Thumbs" end

      for alias, fn in src:gmatch("([%w_]+)%.([%w_]+)%s*%(") do
        local mod = bind[alias]
        if mod and fn == "attach" then attached[mod] = true end
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

  -- A module that keeps its own ImGui upvalue gets it only through
  -- attach(); one nobody attaches fails on its first ImGui call.
  local unattached = {}
  for _, file in ipairs(FILES) do
    if present[file] and file:match("^TS_CV_") and file ~= "TS_CV_Receives" then
      local m = require(file)
      if type(m) == "table" and type(m.attach) == "function" and not attached[file] then
        unattached[#unattached + 1] = file
      end
    end
  end
  check("every module with attach() is attached",
        #unattached == 0 and "none" or table.concat(unattached, ", "), "none")
end

-- Toolbar storage: separators ("-") and gaps ("_") round-trip, and a
-- gap counts as a non-action (sep) everywhere actions are skipped.
do
  local ok, TB = pcall(require, "TS_CV_Toolbar")
  if ok and type(TB) == "table" and TB.serialize then
    local items = TB.parse("40001|a.png|Add;-;_;40005||")
    check("toolbar parse count", #items, 4)
    check("toolbar sep", items[2].sep == true and not items[2].gap, true)
    check("toolbar gap", items[3].sep == true and items[3].gap == true, true)
    check("toolbar label kept", items[1].label, "Add")
    check("toolbar round-trip", TB.serialize(items), "40001|a.png|Add;-;_;40005||")
    -- a plugin button's own vendor look, after its colour
    local vl = TB.parse("_CVFX:VST3: Pro-Q 3||Q|#4aa3df/u|v=mono;_CVFX:VST3: Pro-L 2||L|v=off;40001||A|v=bogus")
    check("vendor look: read", tostring(vl[1].vo) .. " " .. vl[1].color .. " " .. vl[1].label .. " " .. tostring(vl[2].vo), "mono #4aa3df Q off")
    check("vendor look: an unknown one is label", vl[3].label .. tostring(vl[3].vo), "A|v=bogusnil")
    check("vendor look: written", TB.serialize({ vl[1], vl[2] }), "_CVFX:VST3: Pro-Q 3||Q|#4aa3df/u|v=mono;_CVFX:VST3: Pro-L 2||L|v=off")
    check("vendor look: copied", TB.copy_items(vl)[1].vo, "mono")
    -- an FX chain button's way with the plugins there, beside a vendor look
    local cw = TB.parse("_TSCV_CHAIN:a||A|c=replace;_TSCV_CHAIN:b||B|#4aa3df|v=mono|c=ask;_TSCV_CHAIN:c||C|c=nope")
    check("chain way: read", tostring(cw[1].cm) .. " " .. tostring(cw[2].cm) .. " " .. tostring(cw[2].vo) .. " " .. cw[2].color, "replace ask mono #4aa3df")
    check("chain way: an unknown one is label", cw[3].label .. tostring(cw[3].cm), "C|c=nopenil")
    check("chain way: written", TB.serialize({ cw[1], cw[2] }), "_TSCV_CHAIN:a||A|c=replace;_TSCV_CHAIN:b||B|#4aa3df|v=mono|c=ask")
    check("chain way: copied", TB.copy_items(cw)[2].cm, "ask")

    -- menus: "[|icon|label" ... "]", nested
    local line = "40029||Undo;[|m.png|Render;41824||;[||Stems;40001||All;-;];];1157||Snap"
    local t = TB.parse(line)
    check("menu: top count", #t, 3)
    check("menu: is a menu", t[2].menu == true and t[2].label == "Render" and t[2].icon == "m.png", true)
    check("menu: inside", #t[2].items, 2)
    check("menu: nested", t[2].items[2].menu == true and #t[2].items[2].items == 2, true)
    check("menu: after it", t[3].cmd, "1157")
    check("menu: round-trip", TB.serialize(t), line)
    check("menu: empty menu", TB.serialize(TB.parse("[||Empty;]")), "[||Empty;]")
    -- a menu with large items (as the header's), beside its colour
    local lm = TB.parse("[|m.png|Mix|#4aa3df/u|s=large;40001||A;];[||Plain;]")
    check("menu: large read", tostring(lm[1].large) .. " " .. lm[1].label .. " " .. lm[1].color .. " " .. tostring(lm[2].large), "true Mix #4aa3df nil")
    check("menu: large round-trip", TB.serialize(lm), "[|m.png|Mix|#4aa3df/u|s=large;40001||A;];[||Plain;]")
    check("menu: large copied", TB.copy_items(lm)[1].large, true)
    check("menu: stray close dropped", #TB.parse("40001||;];40002||"), 2)
    check("menu: unclosed kept", #TB.parse("[||M;40001||")[1].items, 1)
    check("menu: flatten", #TB.flatten(t), 4)
    -- moving: into a menu, along a list, and never a menu into itself
    local a = TB.parse("1||A;2||B;[||M;3||C;[||N;];]")
    local M_, N_ = a[3], a[3].items[2]
    check("move: into a menu", TB.move_item(a, 1, M_.items, #M_.items + 1), 3)
    check("move: left the top", a[1].cmd, "2")
    check("move: menu into itself refused", TB.move_item(a, 2, N_.items, 1), false)
    check("move: down the same list", TB.move_item(a, 1, a, 3), 2)
    check("move: order after", a[1].menu and a[2].cmd == "2", true)
    check("inside: nested", TB.inside(M_, N_.items) and not TB.inside(N_, M_.items), true)
    local c = TB.copy_items({ M_ })[1]
    check("copy: deep", c ~= M_ and c.items ~= M_.items and #c.items == #M_.items, true)
    -- REAPER's menus: -2 opens a submenu, -3 closes it
    local ini = "[Main extensions]\nitem_0=40001 Insert track\nitem_1=-2 Render\nitem_2=41824 Render project\nitem_3=-1\nitem_4=-3\nitem_5=40029 Undo\n"
    local r = TB.parse_reaper_toolbar(ini, "Main extensions")
    check("reaper menu: top", #r, 3)
    check("reaper menu: submenu", r[2].menu and r[2].label == "Render" and #r[2].items == 2, true)
    check("reaper menu: sep inside", r[2].items[2].sep == true, true)
    check("reaper menus: listed", table.concat(TB.reaper_menus("[Main toolbar]\n[Main extensions]\n[Floating toolbar 1]\n"), ","), "Main extensions")
  end
end

-- Action bars: the list round-trips (old drawers' lines too); bad places
-- and widths are mended; the first load builds the list from the old
-- one; a single place swaps.
do
  local okd, DR = pcall(require, "TS_CV_Drawers")
  if okd and DR.serialize then
    local line = "1|top|1|128|both|drawer_1|0|Edit;2|window|0|90|icons|drawer_2|-3|Tracks"
    local l = DR.parse(line)
    check("bars: count", #l, 2)
    do
      -- Show/hide toolbars: a window's drawers at once, the ones closed
      -- come back
      local g = DR.parse("1|top|1|128|both|d1|0|Edit;2|left|0|128|both|d2|0|L;3|rtop|1|128|both|d3|0|R;4|window|1|90|icons|d4|-3|W;5|bottom|1|128|both|d5|0|B")
      local on, ids = DR.toggle_group(g, "cv", "")
      check("toggle bars: hidden", tostring(on) .. " " .. ids, "false 1,5")
      check("toggle bars: other places left", g[3].open and g[4].open, true)
      on = DR.toggle_group(g, "cv", ids)
      check("toggle bars: the same ones back", tostring(on) .. (g[1].open and "1" or "") .. (g[2].open and "2" or "") .. (g[5].open and "5" or ""), "true15")
      DR.toggle_group(g, "cv", "")
      DR.toggle_group(g, "cv", "99")
      check("toggle bars: none to bring back, all", g[1].open and g[2].open and g[5].open, true)
      check("toggle bars: the rack's own", select(2, DR.toggle_group(g, "rack", "")), "3")
    end
    check("bars: fields", l[2].side == "window" and l[2].open == false and l[2].width == 90 and l[2].style == "icons" and l[2].dock == -3, true)
    check("bars: round-trip (sizes added)", DR.serialize(l), "1|top|1|128|both|drawer_1|0|24|--|Edit;2|window|0|90|icons|drawer_2|-3|24|--|Tracks")
    local sized = "1|top|1|128|both|drawer_1|0|30|Edit;2|left|1|90|icons|drawer_2|0|99|7"
    local sl = DR.parse(sized)
    check("bars: size read", sl[1].size, 30)
    check("bars: size kept in range", sl[2].size, DR.SIZE_MAX)
    check("bars: a numeric name isn't a size", sl[2].name, "7")
    check("bars: old line with a numeric name", DR.parse("1|top|1|128|both|k|0|12")[1].name .. "/" .. DR.parse("1|top|1|128|both|k|0|12")[1].size, "12/24")
    local old = DR.parse("1|top|1|128|both|Edit;2|left|0|90|icons|Tracks")
    check("bars: old drawers' line", #old == 2 and old[2].side == "left" and old[2].key == "drawer_2" and old[2].name == "Tracks", true)
    local m = DR.parse("3|sideways|1|9999|odd|k|0|X")
    check("bars: mended", m[1].side == "top" and m[1].width == DR.W_MAX and m[1].style == "both", true)
    check("bars: none", #DR.parse("none") + #DR.parse(""), 0)
    -- a window bar's own background, before its name
    local bgl = DR.parse("2|window|1|90|icons|drawer_2|-3|24|--|#2B3A4C|Mixing;3|window|1|90|both|drawer_3|0|24|--|#plain")
    check("bars: background read", tostring(bgl[1].bg) .. " " .. bgl[1].name .. " " .. tostring(bgl[2].bg) .. " " .. bgl[2].name, "#2b3a4c Mixing nil #plain")
    check("bars: background written", DR.serialize({ bgl[1] }), "2|window|1|90|icons|drawer_2|-3|24|--|#2b3a4c|Mixing")
    check("bars: no background, as before", DR.serialize({ bgl[2] }), "3|window|1|90|both|drawer_3|0|24|--|#plain")
    check("bars: background exported", (DR.export_text({ bgl[1] }) or ""):find("bg=#2b3a4c", 1, true) ~= nil, true)
    check("bars: background imported", (DR.parse_export(DR.export_text({ bgl[1] })) or {})[1].bg, "#2b3a4c")
    check("bars: names lose ; and |", DR.serialize({ { id = 1, side = "top", open = true, width = 100, style = "both", key = "drawer_1", name = "a;b|c" } }),
      "1|top|1|100|both|drawer_1|0|24|--|abc")
    local mg = DR.migrate("1|top|1|128|both|Edit")
    local places = {}
    for _, d in ipairs(mg) do places[#places + 1] = d.side .. ":" .. d.key end
    check("bars: migrated", table.concat(places, ","), "top:drawer_1,tcp1:toolbar,tcp2:toolbar2,web:web_actions")
    check("bars: migrated ids", mg[4].id, 4)
    local mg0 = DR.migrate("")
    check("bars: migrated from nothing", #mg0 == 3 and mg0[1].id == 1, true)
    -- moving: onto a single place swaps; onto a side doesn't
    local a, b = mg[1], mg[2]
    local other = DR.place_in(mg, a, "tcp1")
    check("place: swap", other == b and a.side == "tcp1" and b.side == "top", true)
    check("place: side no swap", DR.place_in(mg, mg[3], "left") == nil and mg[3].side == "left", true)
    check("place: same place nothing", DR.place_in(mg, mg[3], "left"), nil)
    check("place: unknown refused", DR.place_in(mg, mg[3], "moon") == nil and mg[3].side == "left", true)
    -- sharing: a file of [Bar] sections round-trips buttons, menus, place
    local TB = require("TS_CV_Toolbar")
    local bars = {
      { name = "Edit", side = "top", style = "icons", width = 140, dock = 0,
        items = TB.parse("40029|undo.png|Undo;[||Render;41824||;-;];_RSabc||") },
      { name = "Web", side = "web", style = "both", width = 128, dock = 0,
        items = { { cmd = "40161", icon = "", label = "M1", color = "#d98a2f" }, { sep = true, gap = true } } },
    }
    local txt = DR.export_text(bars, function(c) return c == "40029" and "Edit: Undo" or nil end)
    local back = DR.parse_export(txt)
    check("share: count", back and #back, 2)
    check("share: fields", back[1].name == "Edit" and back[1].place == "top" and back[1].style == "icons" and back[1].width == 140, true)
    check("share: size", back[1].size, 24)
    check("share: items", TB.serialize(back[1].items), "40029|undo.png|Undo;[||Render;41824||;-;];_RSabc||")
    check("share: action names", back[1].names["40029"] .. "/" .. tostring(back[1].names["_RSabc"]), "Edit: Undo/")
    check("share: web colour kept", back[2].web_items[1].color, "#d98a2f")
    check("share: not a bars file", (select(2, DR.parse_export("[Something]\nx=1\n"))) ~= nil, true)
    check("share: names lose newlines", DR.parse_export(DR.export_text({ { name = "a\nb", side = "none", items = {} } }))[1].name, "a b")
  end
end

-- ChannelView's own action icons: paths flatten (lines, arcs, curves,
-- relative and absolute), the file loads, actions find their icons
-- (scripts by file name), and dashes come out the length asked.
do
  local oki, AI = pcall(require, "TS_CV_ActionIcons")
  check("action icons: module", oki and type(AI.flatten) == "function", true)
  if oki then
    local f = AI.flatten("M4 9v6")
    check("ai path: line", #f == 1 and table.concat(f[1].pts, ","), "4,9,4,15")
    local c = AI.flatten("M2 12a10 10 0 1 0 20 0a10 10 0 1 0 -20 0z")
    local far = 0
    for k = 1, #c[1].pts, 2 do
      far = math.max(far, math.abs(math.sqrt((c[1].pts[k] - 12) ^ 2 + (c[1].pts[k + 1] - 12) ^ 2) - 10))
    end
    check("ai path: circle closed, on its radius", c[1].closed and far < 1e-6, true)
    local a = AI.flatten("M6.34 17.66A8 8 0 0 1 16 5.07")
    local n = #a[1].pts
    check("ai path: arc ends where asked", math.abs(a[1].pts[n - 1] - 16) < 1e-6 and math.abs(a[1].pts[n] - 5.07) < 1e-6, true)
    -- the arc goes over the top (through y < 6), not under
    local top = 24
    for k = 2, n, 2 do top = math.min(top, a[1].pts[k]) end
    check("ai path: arc sweeps the right way", top < 4.5, true)
    local two = AI.flatten("M3 3h4M10 10l2 2z")
    check("ai path: two subpaths", #two == 2 and not two[1].closed and two[2].closed, true)
    local rel = AI.flatten("m1 1l2 0 0 2")
    check("ai path: implicit lines after l", table.concat(rel[1].pts, ","), "1,1,3,1,3,3")
    local cu = AI.flatten("M0 0C0 10 10 10 10 0s10-10 10 0")
    check("ai path: S reflects", math.abs(cu[1].pts[#cu[1].pts - 1] - 20) < 1e-9 and #cu[1].pts == 2 + 32, true)
    check("ai path: numbers run together", table.concat(AI.flatten("M1.5-2L.5.5")[1].pts, ","), "1.5,-2,0.5,0.5")
    check("ai path: junk stops, no error", #AI.flatten("M1 1 Q 2 2 3 3"), 1)
    local d = AI.dashes({ pts = { 0, 0, 20, 0 }, closed = false }, 0, 0, 1, 4, 2)
    check("ai dashes: on 4 off 2 over 20", #d, 4)
    check("ai dashes: first", ("%g,%g,%g,%g"):format(table.unpack(d[1])), "0,0,4,0")

    AI.path = HERE .. "../TS_CV_ActionIcons.json"
    local count = AI.load()
    check("ai file: loaded", count > 200, true)
    check("ai file: families", #AI.families() > 10, true)
    check("ai match: undo", AI.match("40029"), "cv:undo")
    check("ai match: SWS by name", AI.match("_SWS_AWCOUNTRECTOG"), "cv:count_in")
    check("ai match: MIDI-editor icons not for the main section", AI.match("40472"), nil)
    check("ai match: a script by file, any id", AI.match("_RSdeadbeef", function() return "Script: TS_ChannelView_TCP.lua" end), "cv:cv_tcp")
    check("ai match: unknown", AI.match("99999999"), nil)
    check("ai: is/get", AI.is("cv:undo") and AI.get("cv:undo").name ~= nil and AI.get("undo.png") == nil, true)
    -- every icon in the file draws: each path flattens to something
    local empty = {}
    for _, fam in ipairs(AI.families()) do
      for _, ic in ipairs(fam.icons) do
        local sh = AI.shapes(ic)
        if #sh.d + #sh.fi + #sh.ti + #sh.da == 0 then empty[#empty + 1] = ic.key end
      end
    end
    check("ai file: every icon has a shape", table.concat(empty, ","), "")
    -- a REAPER toolbar copied: ChannelView's icon over REAPER's
    local TB = require("TS_CV_Toolbar")
    local r = TB.parse_reaper_toolbar("[T]\nitem_0=40029 Undo\nicon_0=toolbar_undo.png\nitem_1=99999 Odd\nicon_1=mine.png\n", "T")
    check("copy toolbar: our icon", r[1].icon, "cv:undo")
    check("copy toolbar: no match keeps the PNG", r[2].icon, "mine.png")
    local items = { { cmd = "40029", icon = "", label = "" }, { menu = true, icon = "", label = "M", items = { { cmd = "1007", icon = "x.png", label = "" } } } }
    check("use cv icons: count", TB.use_cv_icons(items), 2)
    check("use cv icons: in menus too", items[2].items[1].icon, "cv:play")
  end
end

-- Toolbar switches: the item, swapping two bars' places, ids remapped on
-- import, the export carrying ids.
do
  local TB = require("TS_CV_Toolbar")
  check("switch: menu", TB.switch_of({ cmd = "_TSCV_BAR", icon = "", label = "" }), "menu")
  check("switch: to a bar", TB.switch_of({ cmd = "_TSCV_BAR:7", icon = "", label = "" }), 7)
  check("switch: not one", TB.switch_of({ cmd = "40029" }) == nil and TB.switch_of({ menu = true, cmd = "_TSCV_BAR" }) == nil, true)
  check("switch: cmd", TB.switch_cmd(3) .. "/" .. TB.switch_cmd(nil), "_TSCV_BAR:3/_TSCV_BAR")
  local back = TB.parse(TB.serialize({ { cmd = "_TSCV_BAR:3", icon = "cv:undo", label = "" } }))
  check("switch: round-trips", back[1].cmd .. "|" .. back[1].icon, "_TSCV_BAR:3|cv:undo")
  local okd, DR = pcall(require, "TS_CV_Drawers")
  if okd and DR.swap_in then
    local a = { id = 1, side = "top", open = true, width = 140, dock = 0 }
    local b = { id = 2, side = "none", open = false, width = 90, dock = -2 }
    check("switch: swap", DR.swap_in(a, b) and a.side == "none" and b.side == "top" and b.open and b.width == 140 and a.width == 90, true)
    local w1 = { id = 3, side = "window", open = true, width = 128, dock = -4 }
    local w2 = { id = 4, side = "tcp1", open = true, width = 128, dock = 0 }
    DR.swap_in(w1, w2)
    check("switch: window's dock goes with the place", w2.side == "window" and w2.dock == -4 and w1.side == "tcp1" and w1.dock == 0, true)
    check("switch: itself refused", DR.swap_in(a, a), false)
    local items = { { cmd = "_TSCV_BAR:5", icon = "", label = "" }, { menu = true, icon = "", label = "", items = { { cmd = "_TSCV_BAR:6", icon = "", label = "" } } }, { cmd = "_TSCV_BAR", icon = "", label = "" } }
    DR.remap_switches(items, { [5] = 12 })
    check("switch: remapped", items[1].cmd, "_TSCV_BAR:12")
    check("switch: unknown bar becomes the menu", items[2].items[1].cmd, "_TSCV_BAR")
    check("switch: menu left alone", items[3].cmd, "_TSCV_BAR")
    local txt = DR.export_text({ { id = 9, name = "Tabs", side = "top", items = { { cmd = "_TSCV_BAR:9", icon = "", label = "" } } } })
    local got = DR.parse_export(txt)
    check("switch: export has the bar's id", got[1].id, 9)
    check("switch: no action line for a switch", txt:find("action=_TSCV_BAR", 1, true), nil)
  end
end

-- Bar alignment: rows filled then moved across, a block placed up and
-- down, and the setting stored with the bar.
do
  local TB = require("TS_CV_Toolbar")
  local pos, used = TB.place_rows({ 20, 20, 20 }, 0, 100, 4, 2, "l")
  check("align: left", pos[1].x .. "," .. pos[3].x .. "/" .. used, "0,48/1")
  pos = TB.place_rows({ 20, 20, 20 }, 0, 100, 4, 2, "r")
  check("align: right ends at the edge", pos[3].x + pos[3].w, 100)
  pos = TB.place_rows({ 20, 20, 20 }, 0, 100, 4, 2, "c")
  check("align: centre", pos[1].x, 16)
  pos, used = TB.place_rows({ 60, 60, 60 }, 0, 100, 4, 2, "c")
  check("align: each row on its own", pos[1].x .. "," .. pos[2].x .. "/" .. used .. "/" .. tostring(pos[3]), "20,20/2/false")
  check("align: top / centre / bottom", TB.place_v(0, 100, 20, "t") .. "," .. TB.place_v(0, 100, 20, "c") .. "," .. TB.place_v(0, 100, 20, "b"), "2,40.0,78")
  check("align: usual place", TB.place_v(0, 100, 20, "-"), nil)
  local okd, DR = pcall(require, "TS_CV_Drawers")
  if okd then
    local l = DR.parse("1|top|1|128|both|drawer_1|0|30|cb|Edit;2|left|1|90|icons|k|0|24|Tracks")
    check("align: read", l[1].halign .. l[1].valign .. "/" .. l[2].halign .. l[2].valign .. "/" .. l[2].name, "cb/--/Tracks")
    check("align: written", DR.serialize({ l[1] }), "1|top|1|128|both|drawer_1|0|30|cb|Edit")
    check("align: a name like an alignment stays a name", DR.parse("1|top|1|128|both|k|0|24|cb")[1].name, "cb")
    local got = DR.parse_export(DR.export_text({ { id = 1, name = "A", side = "top", halign = "r", valign = "t", items = {} } }))
    check("align: exported", got[1].halign .. got[1].valign, "rt")
  end
end

-- Button colours: stored after the label, menus too, read back; a bar's
-- colour style rides in its align field.
do
  local TB = require("TS_CV_Toolbar")
  local items = { { cmd = "40029", icon = "cv:undo", label = "Undo", color = "#C8453C" },
                  { menu = true, icon = "", label = "M", color = "#4aa3df", items = { { cmd = "1007", icon = "", label = "" } } },
                  { cmd = "1016", icon = "", label = "", color = "nonsense" } }
  local line = TB.serialize(items)
  check("colour: stored", line, "40029|cv:undo|Undo|#c8453c;[||M|#4aa3df;1007||;];1016||")
  local back = TB.parse(line)
  check("colour: read", back[1].color .. "/" .. back[1].label .. "/" .. back[2].color .. "/" .. back[2].label .. "/" .. tostring(back[3].color), "#c8453c/Undo/#4aa3df/M/nil")
  check("colour: a plain line still reads", TB.parse("40029|x.png|Undo")[1].label, "Undo")
  check("colour: value", TB.colour_of("#ff0000"), 0xff0000ff)
  local okd, DR = pcall(require, "TS_CV_Drawers")
  if okd then
    local l = DR.parse("1|top|1|128|both|k|0|24|cbi|Edit;2|top|1|128|both|k2|0|24|--|B")
    check("colour style: read", l[1].cstyle .. l[1].halign .. l[1].valign .. "/" .. l[2].cstyle, "icb/u")
    check("colour style: written", DR.serialize({ l[1], l[2] }), "1|top|1|128|both|k|0|24|cbi|Edit;2|top|1|128|both|k2|0|24|--|B")
  end
end

-- Adding a PNG: copied into the icon folder, the same file reused, a
-- different one of the same name kept apart, anything else refused.
do
  local TB = require("TS_CV_Toolbar")
  local dir = os.tmpname(); os.remove(dir); os.execute("mkdir -p '" .. dir .. "'")
  local src = os.tmpname() .. ".png"
  local png = "\137PNG\r\n\26\nabc"
  local f = io.open(src, "wb"); f:write(png); f:close()
  local name = TB.import_png(src, dir)
  local base = src:match("([^/]+)$")
  check("add png: copied under its own name", name, base)
  check("add png: the same file again is reused", TB.import_png(src, dir), base)
  f = io.open(src, "wb"); f:write(png .. "x"); f:close()
  check("add png: a different one alongside", TB.import_png(src, dir), base:sub(1, -5) .. " (2).png")
  local txt = os.tmpname() .. ".png"
  f = io.open(txt, "wb"); f:write("not an image"); f:close()
  check("add png: not a PNG refused", TB.import_png(txt, dir), nil)
  check("add png: missing refused", TB.import_png(dir .. "/nope.png", dir), nil)
  os.execute("rm -rf '" .. dir .. "' '" .. src .. "' '" .. txt .. "'")
end

-- The web companion's Actions list, as the organiser reads and writes it.
do
  local oka, AE = pcall(require, "TS_CV_ActionEditor")
  if oka and AE.json_decode then
    local js = '[{"l":"Undo","a":"40029","c":"#4aa3df"},{"sp":1},{"m":1,"l":"Render","c":"","i":[{"l":"","a":"41824","c":""},{"sp":1},{"m":1,"l":"Sub","c":"","i":[]}]},{"l":"Odd \\"q\\"","a":"_RS1","c":"","el":{}}]'
    local arr = AE.json_decode(js)
    check("web json: decoded", type(arr) == "table" and #arr, 4)
    local items = AE.from_web(arr)
    check("web: action", items[1].cmd == "40029" and items[1].label == "Undo" and items[1].color == "#4aa3df", true)
    check("web: spacer", items[2].sep and items[2].gap, true)
    check("web: menu", items[3].menu and #items[3].items == 3 and items[3].items[3].menu, true)
    check("web: escaped label", items[4].label, 'Odd "q"')
    local back = AE.json_encode_list(AE.to_web(items))
    check("web: round-trip", AE.json_encode_list(AE.to_web(AE.from_web(AE.json_decode(back)))), back)
    check("web: no el", back:find('"el"') == nil, true)
    check("web json: junk", AE.json_decode("not json") == nil and AE.json_decode("") == nil, true)
    check("web json: unicode", AE.json_decode('["\\u00e9"]')[1], "\u{00E9}")
    -- a toolbar separator goes to the web as a spacer
    check("web: sep to spacer", AE.json_encode_list(AE.to_web({ { sep = true } })), '[{"sp":1}]')
    -- icons ride along (the page ignores them), only when there are some
    local wi = AE.json_encode_list(AE.to_web({ { cmd = "1", label = "A", icon = "x.png" }, { cmd = "2", label = "B", icon = "" } }))
    check("web: icon kept", wi, '[{"l":"A","a":"1","c":"","ic":"x.png"},{"l":"B","a":"2","c":""}]')
    check("web: icon back", AE.from_web(AE.json_decode(wi))[1].icon, "x.png")
    -- locate finds an item inside a menu
    local l, k = AE.locate(items, items[3].items[2])
    check("locate: in a menu", l == items[3].items and k == 2, true)
  end
end

-- A plugin's input/output meters: under the output bar, output RMS minus
-- input RMS; "byp" for a bypassed plugin; a dash with nothing coming in.
-- Under the input bar, its held peak.
do
  local function out(lv, byp) local _, o = W.io_readouts(lv, byp, lv.in_pk); return o end
  check("io: the change in level",  out({ in_pk = -10, out_pk = -4, in_rms = -18, out_rms = -12.5 }), "+5.5")
  check("io: a cut reads negative", out({ in_pk = -10, out_pk = -14, in_rms = -18, out_rms = -21 }), "-3.0")
  check("io: bypassed",             out({ in_pk = -10, out_pk = -150, in_rms = -18, out_rms = -150 }, true), "byp")
  check("io: nothing coming in",    out({ in_pk = -150, out_pk = -150, in_rms = -150, out_rms = -150 }), "\u{2013}")
  check("io: input readout",        (W.io_readouts({ in_rms = -18, out_rms = -12 }, false, -6.04)), "-6.0")
end

-- Hardware styles: a control's style and cap colour, and the panel's
-- faceplate, survive the ini and M.copy; a faceplate the palette doesn't
-- know is dropped rather than kept as a name nothing can draw; and a
-- layout with no styling writes no Style lines at all.
do
  local MP = require("TS_CV_Mappings")
  local k = "StyledPlug"
  MP.set(k, { plate = "aluminium", controls = {
    { param = 0, type = "knob", label = "In", style = "skirted", cap = "red" },
    { param = 1, type = "fader", label = "Out", style = "console" },
    { param = 2, type = "knob", label = "Plain" },
    { param = 3, type = "stepped", label = "Mode", cap = "blue" } } })
  MP.save(); MP.reload()
  local b = MP.get(k)
  check("style: plate round-trips",        b.plate, "aluminium")
  check("style: knob style",               b.controls[1].style, "skirted")
  check("style: knob cap",                 b.controls[1].cap, "red")
  check("style: fader style, no cap",      b.controls[2].style .. "/" .. tostring(b.controls[2].cap), "console/nil")
  check("style: plain control untouched",  b.controls[3].style == nil and b.controls[3].cap == nil, true)
  check("style: cap without a style",      tostring(b.controls[4].style) .. "/" .. b.controls[4].cap, "nil/blue")
  local cp = MP.copy(b)
  check("style: copy keeps them",          cp.plate .. cp.controls[1].style .. cp.controls[1].cap, "aluminiumskirtedred")
  local f = io.open(MP.file_path(), "rb"); local txt = f and f:read("a") or ""; if f then f:close() end
  check("style: Style2 not written",       txt:find("Style2=", 1, true) == nil, true)
  check("style: Style0 written",           txt:find("Style0=skirted|red", 1, true) ~= nil, true)
  -- state names round-trip through the file
  MP.set_states(k, 4, "Off", "Auto"); MP.save(); MP.reload()
  local st = MP.get_states(k, 4)
  check("state names: round-trip",         st and (st[1] .. "/" .. st[2]), "Off/Auto")
  check("state names: copied",             MP.copy(MP.get(k)).states[4][2], "Auto")
  -- a toggle's lit colour rides in its Style line's colour field
  MP.set("LitPlug", { controls = { { param = 0, type = "toggle", label = "T", cap = "amber" } } })
  MP.save(); MP.reload()
  check("toggle colour: round-trips",      MP.get("LitPlug").controls[1].cap, "amber")
  check("toggle colour: known",            C.TOGGLE_COL.amber ~= nil and C.TOGGLE_COL.theme.col == nil, true)
  MP.remove("LitPlug"); MP.save(); MP.reload()
  -- what the button says
  check("button: your name, on",            MP.button_text(k, 4, 1, "1.0"), "Auto")
  check("button: your name, off",           MP.button_text(k, 4, 0, "0.0"), "Off")
  check("button: the plugin's word",        MP.button_text(k, 9, 1, "Thrust"), "Thrust")
  check("button: a number says ON/OFF",     MP.button_text(k, 9, 1, "1.00"), nil)
  check("button: a level says ON/OFF",      MP.button_text(k, 9, 0, "-inf dB"), nil)
  check("button: a percentage too",         MP.button_text(k, 9, 1, "100 %"), nil)
  check("button: nothing says ON/OFF",      MP.button_text(k, 9, 1, "  "), nil)
  -- the brushed finish: the faceplate's own unless the layout says
  local CC = require("TS_CV_Config")
  check("brush: aluminium brushed by default", MP.brushed(MP.get(k), CC.plate_of("aluminium")), true)
  check("brush: cobalt plain by default",      MP.brushed({}, CC.plate_of("cobalt")), false)
  check("brush: theme never",                  MP.brushed({ brush = true }, nil), false)
  MP.set(k, { plate = "cobalt", brush = true, controls = {} }); MP.save(); MP.reload()
  check("brush: on round-trips",               MP.get(k).brush, true)
  check("brush: drawn brushed",                MP.brushed(MP.get(k), CC.plate_of("cobalt")), true)
  check("brush: copied",                       MP.copy(MP.get(k)).brush, true)
  MP.set(k, { plate = "aluminium", brush = false, controls = {} }); MP.save(); MP.reload()
  check("brush: off round-trips",              MP.get(k).brush, false)
  check("brush: aluminium made plain",         MP.brushed(MP.get(k), CC.plate_of("aluminium")), false)
  MP.set(k, { plate = "stone", controls = {} }); MP.save(); MP.reload()
  check("brush: none set reads nil",           MP.get(k).brush, nil)
  local f2 = io.open(MP.file_path(), "rb"); local t2 = f2 and f2:read("a") or ""; if f2 then f2:close() end
  check("brush: no Brush line when unset",     t2:find("\nBrush=", 1, true) == nil, true)
  -- every knob style has a face size and a cap colour that exists
  for _, ks in ipairs(CC.KNOB_STYLES) do
    if ks.key ~= "arc" then check("knob style " .. ks.key .. ": cap known", (CC.CAP[ks.cap] ~= nil or (ks.parts ~= nil and CC.custom_key(ks.cap) ~= nil)), true) end
  end
  for _, pl in ipairs(CC.PLATES) do
    if pl.bg then check("plate " .. pl.key .. ": all inks", (pl.head and pl.text and pl.dim and pl.tick and pl.border) ~= nil, true) end
  end
  MP.set(k, { plate = "nonsense", controls = {} })
  MP.save(); MP.reload()
  check("style: unknown plate dropped",    MP.get(k).plate, nil)
  MP.remove(k); MP.save(); MP.reload()
end

-- The gain-reduction trace: its window is saved on the Meter line (and an
-- older Meter line without one still reads), its labels, and the room it
-- takes when open.
do
  local MP = require("TS_CV_Mappings")
  local PP = require("TS_CV_Panel")
  local CC = require("TS_CV_Config")
  local k = "TracePlug"
  MP.set(k, { meter = { on = true, range = 24, win = "2s" }, controls = {} })
  MP.save(); MP.reload()
  check("trace: window round-trips",     MP.get(k).meter.win, "2s")
  check("trace: range beside it",        MP.get(k).meter.range, 24)
  check("trace: meter_of carries it",    MP.meter_of(MP.get(k)).win, "2s")
  local cp = MP.copy(MP.get(k)); MP.set_meter(cp, true)
  check("trace: set_meter keeps it",     cp.meter.win, "2s")
  MP.set(k, { meter = { on = true, range = 18 }, controls = {} })
  MP.save(); MP.reload()
  check("trace: no window, none saved",  MP.get(k).meter.win, nil)
  MP.remove(k); MP.save(); MP.reload()
  check("trace: label, beats",           PP.grv_label("4b"), "4 beats")
  check("trace: label, one beat",        PP.grv_label("1b"), "1 beat")
  check("trace: label, seconds",         PP.grv_label("2s"), "2 s")
  check("trace: label, default",         PP.grv_label(nil), PP.grv_label(CC.GRV_DEFAULT))
  local ctl = { { type = "knob" }, { type = "knob" } }
  local w0 = PP.width(ctl, 300, false, true, "X", false, false)
  local w1 = PP.width(ctl, 300, false, true, "X", false, true)
  check("trace: open adds its width",    w1 - w0, CC.GRV_W + CC.PANEL_PAD)
  check("trace: no meter, no trace",     PP.width(ctl, 300, false, false, "X", false, true),
        PP.width(ctl, 300, false, false, "X", false, false))
end

-- The EQ canvases draw a curve in one AddPolyline call once ReaImGui is
-- attached (it isn't yet when the file loads), with the per-segment
-- fallback when the packed call isn't there.
do
  local EQP = require("TS_CV_EQPanel")
  local n = { poly = 0, line = 0, size = nil }
  local fake = { DrawList_AddPolyline = function(_, a) n.poly = n.poly + 1; n.size = a.n end,
                 DrawList_AddLine = function() n.line = n.line + 1 end }
  local had = reaper.new_array
  reaper.new_array = function(sz) return { n = sz } end
  EQP.attach(fake)
  EQP.util.polyline("dl", { 0, 1, 2, 3 }, { 0, 1, 0, 1 }, 4, 0xffffffff, 2.0)
  check("eq polyline: one packed call", n.poly == 1 and n.line == 0, true)
  check("eq polyline: buffer is the points", n.size, 8)
  fake.DrawList_AddPolyline = nil
  EQP.util.polyline("dl", { 0, 1, 2, 3 }, { 0, 1, 0, 1 }, 4, 0xffffffff, 2.0)
  check("eq polyline: no packed call, a line a segment", n.line, 3)
  reaper.new_array = had
end

-- Every knob face and fader style draws without error, bypassed or not,
-- with and without ReaImGui's polygon call (an older ReaImGui has none:
-- the pointer falls back to a stroke).
do
  local CC = require("TS_CV_Config")
  local calls = {}
  local function rec(name) return function() calls[name] = (calls[name] or 0) + 1 end end
  local fake = setmetatable({
    GetMouseDelta = function() return 0, 0 end,
    GetMouseWheel = function() return 0 end,
    GetMousePos = function() return 0, 0 end,
    GetWindowDrawList = function() return "dl" end,
    InvisibleButton = function() return false end,
    DrawList_AddConvexPolyFilled = rec("poly"),
    DrawList_AddPolyline = rec("polyline"),
    DrawList_AddRectFilledMultiColor = rec("grad"),
  }, { __index = function(_, key)
    if key:find("Flags_") or key:find("MouseButton_") or key:find("MouseCursor_") then return 1 end
    return rec(key)
  end })
  W.attach(fake)
  local had = reaper.new_array
  reaper.new_array = function(n) return {} end
  local ok, err = pcall(function()
    for _, st in ipairs(CC.KNOB_STYLES) do
      for _, dim in ipairs({ false, true }) do
        W.knob_face("dl", 50, 50, 17, 0.62, { style = st.key, dim = dim, hot = not dim,
                    bipolar = dim, cap = W.cap_col(dim and "cream" or nil) })
      end
    end
    W.knob_face("dl", 50, 50, 17, 0.3, { style = "nonsense" })
  end)
  check("faces: every knob style draws", ok and true or err, true)
  check("faces: the pointer is modelled from polygons", ((calls.DrawList_PathFillConcave or 0) + (calls.DrawList_PathFillConvex or 0)) > 0, true)
  reaper.new_array = nil
  calls.poly = 0
  ok = pcall(function()
    W.knob_face("dl", 50, 50, 17, 0.62, { style = "pointer" })
  end)
  check("faces: pointer without new_array", ok and (calls.poly or 0) == 0, true)
  reaper.new_array = had
  ok, err = pcall(function()
    for _, st in ipairs(CC.FADER_STYLES) do
      W.fader(nil, "f" .. st.key, 0, 0, 26, 200, 0.7, "Lvl", 0.5, false,
              { style = st.key, cap = W.cap_col("red") })
    end
    W.fader(nil, "fplain", 0, 0, 26, 200, 0.7, "Lvl", nil, false)
  end)
  check("faders: every style draws", ok and true or err, true)
  check("faders: console and rail use gradients", (calls.grad or 0) >= 4, true)
  check("cap colour: accent follows the theme", W.cap_col("accent"), CC.COL.knob_fill)
  check("cap colour: unknown is none", W.cap_col("mauve"), nil)
end

-- forgiving plugin search (TS_CV_Search)
do
  local SR = require("TS_CV_Search")
  local names = { "VST3: Pro-Q 4 (FabFilter)", "VST3: Pro-C 2 (FabFilter)", "VST3: Pro-L 2 (FabFilter)",
    "VST3: Saturn 2 (FabFilter)", "VST: ReaComp (Cockos)", "VST3: SSL EQ (Waves)", "VST3: Decapitator (Soundtoys)",
    "VST3: Compressor (Steinberg)", "VST3: Valhalla VintageVerb (Valhalla DSP, LLC)" }
  local list = {}
  for _, n in ipairs(names) do
    list[#list + 1] = { name = n, short = n:gsub("^%w+:%s*", ""):gsub("%s*%b()$", ""), ident = n }
  end
  table.sort(list, function(a, b) return a.short:lower() < b.short:lower() end)
  local function top(q, bonus)
    local r = SR.search(list, q, nil, bonus)
    local o = {}
    for _, e in ipairs(r) do o[#o + 1] = e.short end
    return table.concat(o, "|")
  end
  check("search: word starts", top("fab sat"), "Saturn 2")
  check("search: punctuation ignored", top("proq"), "Pro-Q 4")
  check("search: in-order letters", top("pq4"), "Pro-Q 4")
  check("search: a wrong letter", top("saturm"), "Saturn 2")
  check("search: swapped letters", top("satrun"), "Saturn 2")
  check("search: a missing letter", top("compresor"), "Compressor")
  check("search: a short term gets no slack", top("proc"), "Pro-C 2")
  check("search: run-together words", top("ssleq"), "SSL EQ")
  check("search: nothing", top("zzzz"), "")
  check("search: a name starting so comes first", top("pro"):match("^[^|]+"), "Pro-C 2")
  check("search: recents nudge", top("pro", function(e) return e.short == "Pro-L 2" and 15 or 0 end):match("^[^|]+"), "Pro-L 2")
end

-- presets (TS_CV_Presets): REAPER's own file format, and editing it
do
  local PR = require("TS_CV_Presets")
  -- a 16384-byte piece and a check byte (its bytes summed, mod 256)
  local lines = PR.data_lines(("\1"):rep(16385))
  check("presets: state splits at 16384 bytes", #lines, 2)
  check("presets: each piece ends in its check byte", lines[1]:sub(-2), "00")
  check("presets: the second piece is Data_1", lines[2], "Data_1=0101")

  local dir = "./tscv_preset_test"
  os.execute((package.config:sub(1, 1) == "\\" and "mkdir " or "mkdir -p ") .. dir)
  local file = dir .. "/vst-test.ini"
  local f = io.open(file, "wb")
  f:write("[General]\nLastDefImpTime=1\nNbPresets=1\n\n[Preset0]\nData=0102030609\nLen=4\nName=Old\n\n")
  f:close()
  local saved = {}
  for _, k in ipairs({ "TrackFX_GetUserPresetFilename", "TrackFX_GetNamedConfigParm", "TrackFX_GetFXGUID",
                       "GetTrackStateChunk", "TrackFX_GetPresetIndex", "TrackFX_SetPreset", "GetResourcePath" }) do
    saved[k] = reaper[k]
  end
  local n = 0
  reaper.TrackFX_GetUserPresetFilename = function() return file end
  reaper.TrackFX_GetNamedConfigParm = function(_, _, k)
    if k == "fx_type" then return true, "VST" end
    return true, "C:\\x\\test.dll<1"
  end
  reaper.TrackFX_GetFXGUID = function() return "{T}" end
  reaper.GetTrackStateChunk = function()
    return true, "<TRACK\n<FXCHAIN\n<VST \"VST: Test\" test.dll 0 \"\" 1\nAQID\n>\nFXID {T}\n>\n>"
  end
  reaper.TrackFX_GetPresetIndex = function() n = n + 1; return 0, n end
  reaper.TrackFX_SetPreset = function() return true end
  reaper.GetResourcePath = function() return dir end

  check("presets: the format is one that saves", PR.kind(0, 0), "vst")
  check("presets: default key", PR.default_key(0, 0), "vst-test")
  check("presets: save", (PR.save(0, 0, "New")), true)
  local doc = PR.parse(io.open(file, "rb"):read("a"))
  check("presets: two now", #doc.presets, 2)
  check("presets: the state as REAPER writes it", doc.presets[2].data[1], "Data=01020306")
  check("presets: other [General] keys kept", doc.general[1], "LastDefImpTime=1")
  check("presets: save as default", (PR.save_default(0, 0, "New")), true)
  check("presets: still two (replaced)", #PR.parse(io.open(file, "rb"):read("a")).presets, 2)
  check("presets: the default is recorded", PR.list(0, 0).default, "New")
  check("presets: rename follows the default", (PR.rename(0, 0, "New", "Newer")), true)
  check("presets: default renamed too", PR.list(0, 0).default, "Newer")
  check("presets: no rename onto another", (PR.rename(0, 0, "Newer", "Old")), false)
  check("presets: delete", (PR.delete(0, 0, "Newer")), true)
  check("presets: the default goes with it", PR.list(0, 0).default, nil)
  check("presets: one left", PR.list(0, 0).user[1], "Old")

  -- CLAP: every line inside the block, each ended by a zero byte, with
  -- CFG naming the preset -- as REAPER saved FabFilter Pro-DS
  reaper.TrackFX_GetNamedConfigParm = function(_, _, k)
    if k == "fx_type" then return true, "CLAP" end
    return true, "com.FabFilter.preset-discovery.Pro-DS.1"
  end
  reaper.GetTrackStateChunk = function()
    return true, "<TRACK\n<FXCHAIN\n<CLAP \"CLAP: Pro-DS (FabFilter)\" com.FabFilter.preset-discovery.Pro-DS.1 \"\"\n"
      .. "  CFG 4 1280 840 \"\"\n  <IN_PINS\n  >\n  <STATE\n    RkZC\n    AwAA\n  >\n>\nFXID {T}\n>\n>"
  end
  check("presets: CLAP saves", PR.kind(0, 0), "clap")
  check("presets: CLAP default key", PR.default_key(0, 0), "clap-com.FabFilter.preset-discovery.Pro-DS.1")
  check("presets: CLAP state", PR.state(0, 0, "Mine"),
        'CFG 4 1280 840 "Mine"\0<IN_PINS\0>\0<STATE\0RkZC\0AwAA\0>\0')
  check("presets: CLAP name with a quote in it", PR.state(0, 0, 'My "Best"'):match("^[^%z]*"),
        "CFG 4 1280 840 'My \"Best\"'")
  for k, v in pairs(saved) do reaper[k] = v end
  os.remove(file); os.remove(dir .. "/reaper-defpresets.ini"); os.remove(dir)
end

-- The layout baseline (TS_CV_LayoutFixture.lua, recorded by
-- TS_CV_LayoutSnap.lua before the half-cell grid): every layout in it, in
-- both flows at one to six rows, must still put every control, rule and
-- edge exactly where it was. One check per layout; a failure names the
-- first flow and row count that moved.
do
  local ok_fx, FX = pcall(dofile, HERE .. "TS_CV_LayoutFixture.lua")
  check("layout baseline: fixture loads", ok_fx and type(FX) == "table", true)
  if ok_fx then
    local TYPE = { k = "knob", t = "toggle", c = "combo", s = "stepped", f = "fader",
                   b = "blank", d = "divider", h = "half_gap" }
    local function parse(str)
      local ctl, i = {}, 1
      while i <= #str do
        local c = { type = TYPE[str:sub(i, i)] }
        if str:sub(i + 1, i + 1) == "!" then c.no_rule = true; i = i + 1 end
        ctl[#ctl + 1] = c; i = i + 1
      end
      return ctl
    end
    -- the baseline is for a 58 px column
    local rows_for, cw0 = P.rows_for, C.CELL_W
    P.rows_for = function(r) return r end
    C.set_cell_w(58)
    for ci, case in ipairs(FX.cases) do
      local bad
      for _, fl in ipairs({ "column" }) do
        for rows = 1, 6 do
          local ctl = parse(case.ctl)
          local idx = {}
          for i, c in ipairs(ctl) do idx[c] = i end
          local lay = P.layout(ctl, rows)
          local items, rules = {}, {}
          for _, it in ipairs(lay.items) do items[#items + 1] = string.format("%d,%g,%g", idx[it.ctl], it.x, it.y) end
          for _, r in ipairs(lay.rules) do rules[#rules + 1] = string.format("%g", r) end
          local want = FX.expect[ci .. "|" .. fl .. "|" .. rows]
          local got = { i = table.concat(items, " "), r = table.concat(rules, " "), w = lay.width, h = lay.height }
          if not bad and (got.i ~= want.i or got.r ~= want.r or got.w ~= want.w or got.h ~= want.h) then
            bad = fl .. " " .. rows .. " rows: " .. got.i .. " | w " .. got.w .. " h " .. got.h
          end
          -- the merged-cell flow, given the same panel, must put it all in
          -- the same places (it's the strips plus spans)
          if fl == "column" and not bad then
            local fl2 = P.place_flow(ctl, rows * 2, rows)
            local i2, r2 = {}, {}
            for _, it in ipairs(fl2.items) do i2[#i2 + 1] = string.format("%d,%g,%g", idx[it.ctl], it.x, it.y) end
            for _, r in ipairs(fl2.rules) do r2[#r2 + 1] = string.format("%g", r) end
            local g2 = { i = table.concat(i2, " "), r = table.concat(r2, " "), w = fl2.width, h = fl2.height }
            if g2.i ~= want.i or g2.r ~= want.r or g2.w ~= want.w or g2.h ~= want.h then
              bad = "flow " .. rows .. " rows: " .. g2.i .. " | r " .. g2.r .. " | w " .. g2.w .. " h " .. g2.h
            end
          end
        end
      end
      check("layout baseline: " .. case.name:sub(1, 22), bad or "same", "same")
    end
    P.rows_for, C.CELL_W = rows_for, cw0
  end
end

-- The half-cell grid with sizes in it (nothing in the baseline has one).
do
  local rows_for, cw0 = P.rows_for, C.CELL_W
  P.rows_for = function(r) return r end
  C.set_cell_w(58)
  local function pos(ctl, rows)
    local lay = P.layout(ctl, rows)
    local t = {}
    for _, it in ipairs(lay.items) do t[#t + 1] = string.format("%g,%g/%dx%d", it.x, it.y, it.w, it.h) end
    return table.concat(t, " ") .. " w" .. lay.width, lay
  end
  local S = function(sz) return { type = "knob", size = sz } end
  check("sizes: two smalls share a cell", (pos({ S"small", S"small", S"medium" }, 2)), "0,0/2x1 0,32/2x1 0,64/2x2 w58")
  check("sizes: a large makes a wide strip, a medium in it centred",
        (pos({ S"large", S"medium", S"medium" }, 3)), "0,0/3x3 14.5,96/2x2 87,0/2x2 w145")
  check("sizes: a large in a one-row panel is medium", (pos({ S"large", S"medium" }, 1)), "0,0/2x2 58,0/2x2 w116")
  check("sizes: a large that won't fit below wraps", (pos({ S"medium", S"large" }, 2)), "0,0/2x2 58,0/3x3 w145")
  check("sizes: small, gap, small", (pos({ S"small", { type = "half_gap" }, S"small" }, 2)), "0,0/2x1 0,64/2x1 w58")
  check("sizes: unknown size is medium", (pos({ S"huge" }, 2)), "0,0/2x2 w58")
  check("sizes: a toggle has no large", (pos({ { type = "toggle", size = "large" } }, 3)), "0,0/2x2 w58")
  check("sizes: small toggles share a cell", (pos({ { type = "toggle", size = "small" }, { type = "toggle", size = "small" } }, 3)), "0,0/2x1 0,32/2x1 w58")
  check("sizes: a stepped knob does", (pos({ { type = "stepped", size = "small" } }, 3)), "0,0/2x1 w58")
  -- View > Control spacing narrows every column
  C.set_cell_w(50)
  check("spacing: narrower columns", (pos({ S"medium", S"medium", S"medium" }, 2)), "0,0/2x2 0,64/2x2 50,0/2x2 w100")
  check("spacing: a large is 1.5 columns", (pos({ S"large" }, 3)), "0,0/3x3 w75")
  C.set_cell_w(20);  check("spacing: clamped low", C.CELL_W, C.CELL_W_MIN)
  C.set_cell_w(999); check("spacing: clamped high", C.CELL_W, C.CELL_W_MAX)
  C.set_cell_w("x"); check("spacing: nonsense is the default", C.CELL_W, C.CELL_W_DEFAULT)
  C.set_cell_w(58)
  -- a dropdown as buttons: across takes a column per choice, down a
  -- half-row per two; one too tall for the panel is a dropdown again
  local function B(dir, n) return { type = "combo", buttons = dir, nbtn = n } end
  check("buttons: four across", (pos({ B("across", 4), S"medium" }, 2)), "0,0/4x2 29,64/2x2 w116")
  check("buttons: four down", (pos({ B("down", 4) }, 2)), "0,0/2x3 w58")
  check("buttons: down too tall", (pos({ B("down", 8) }, 2)), "0,0/2x2 w58")
  local lay = P.layout({ B("across", 3) }, 2)
  check("buttons: the layout says so", lay.items[1].kind, "buttons")
  check("buttons: not on a knob", (pos({ { type = "knob", buttons = "across", nbtn = 4 } }, 2)), "0,0/2x2 w58")
  -- sections a divider styles
  local K = { type = "knob" }
  local ctl = { { type = "knob" }, { type = "divider", style = "inset" }, { type = "knob" }, { type = "knob" },
                { type = "divider" }, { type = "knob" }, { type = "divider", style = "plate", cap = "cream" }, { type = "knob" } }
  local ls = P.layout(ctl, 2)
  check("sections: two styled", #ls.sections, 2)
  check("sections: inset covers its two knobs", (ls.items[2].sec or 0) .. (ls.items[3].sec or 0) .. tostring(ls.items[1].sec), "11nil")
  check("sections: the plain one isn't", ls.items[4].sec, nil)
  check("sections: the plate one", ls.items[5].sec, 2)
  check("sections: inset x and width", ls.sections[1].x .. "/" .. ls.sections[1].w, (58 + 9) .. "/58")
  check("sections: unknown plate is no style", P.section_style({ type = "divider", style = "plate", cap = "nope" }), nil)
  local lf = P.layout({ { type = "divider", style = "inset" }, { type = "fader" }, K }, 2)
  check("sections: a fader's section isn't the divider's", lf.items[2].sec, nil)
  check("sections: an empty one isn't drawn", #lf.sections, 0)
  check("sizes: item_size small", P.item_size({ w = 2, h = 1 }), "small")
  check("sizes: item_size large", P.item_size({ w = 3, h = 3 }), "large")
  check("sizes: item_size ordinary", P.item_size({ w = 2, h = 2 }), nil)
  P.rows_for, C.CELL_W = rows_for, cw0
  -- the Size line in the layout file
  local MP = require("TS_CV_Mappings")
  local k = "SizedPlug"
  MP.set(k, { controls = { { param = 0, type = "knob", label = "A", size = "large" },
                           { param = 1, type = "knob", label = "B", size = "medium" },
                           { param = 2, type = "stepped", label = "C", size = "small" },
                           { param = 3, type = "knob", label = "D", size = "huge" } } })
  MP.save(); MP.reload()
  local g = MP.get(k).controls
  check("size: large round-trips", g[1].size, "large")
  check("size: medium saves as nothing", g[2].size, nil)
  check("size: small round-trips", g[3].size, "small")
  check("size: unknown dropped", g[4].size, nil)
  check("size: copied", MP.copy(MP.get(k)).controls[1].size, "large")
  local f = io.open(MP.file_path(), "rb"); local txt = f and f:read("a") or ""; if f then f:close() end
  check("size: Size0 written", txt:find("Size0=large", 1, true) ~= nil, true)
  check("size: no Size1 line", txt:find("Size1=", 1, true) == nil, true)
  MP.set(k, { controls = { { param = 0, type = "combo", label = "Mode", buttons = "down", nbtn = 3 },
                           { param = 1, type = "combo", label = "X", buttons = "sideways", nbtn = 3 } } })
  MP.save(); MP.reload()
  local gb = MP.get(k).controls
  check("buttons: round-trip", gb[1].buttons .. "|" .. gb[1].nbtn, "down|3")
  check("buttons: nonsense dropped", gb[2].buttons, nil)
  check("buttons: copied", MP.copy(MP.get(k)).controls[1].nbtn, 3)
  MP.remove(k); MP.save(); MP.reload()
end

-- REAPER's own instance names: the layout stays the plugin's, the screen
-- shows yours
do
  local FT = require("TS_CV_FXTree")
  local saved = { reaper.TrackFX_GetFXName, reaper.TrackFX_GetNamedConfigParm }
  local renamed = true
  reaper.TrackFX_GetFXName = function() return true, renamed and "Lead Comp" or "VST3: Pro-C 3 (FabFilter)" end
  reaper.TrackFX_GetNamedConfigParm = function(_, _, k)
    if k == "renamed_name" then return true, renamed and "Lead Comp" or "" end
    if k == "fx_name" then return true, "VST3: Pro-C 3 (FabFilter)" end
    return false, ""
  end
  local n, al = FT.names_of(0, 0)
  check("instance name: the plugin's name kept", n, "VST3: Pro-C 3 (FabFilter)")
  check("instance name: yours beside it", al, "Lead Comp")
  check("instance name: the layout key is the plugin's", U.plugin_key(n), U.plugin_key("VST3: Pro-C 3 (FabFilter)"))
  check("instance name: shown", U.fx_label({ name = n, alias = al }), "Lead Comp")
  renamed = false
  n, al = FT.names_of(0, 0)
  check("instance name: not renamed", tostring(al) .. "|" .. U.fx_label({ name = n, alias = al }), "nil|Pro-C 3")
  -- writing it: REAPER's own way, and the chunk when that doesn't take
  local CH = '<TRACK\nNAME x\n<FXCHAIN\nBYPASS 0 0 0\n<VST "VST3: Pro-C 3 (FabFilter)" "Pro-C 3.vst3" 0 "" 1{ABC} ""\nAAAA\n>\nFXID {G1}\n' ..
             '<JS loser/3BandEQ ""\n0 0\n>\nFXID {G2}\n<AU "AU: X" "Y: X" "" 1\n>\nFXID {G3}\n>\n>'
  local written
  local s2 = { reaper.TrackFX_SetNamedConfigParm, reaper.GetTrackStateChunk, reaper.SetTrackStateChunk,
               reaper.Undo_BeginBlock, reaper.Undo_EndBlock }
  reaper.TrackFX_SetNamedConfigParm = function() return false end
  reaper.TrackFX_GetNamedConfigParm = function() return true, "" end
  reaper.GetTrackStateChunk = function() return true, CH end
  reaper.SetTrackStateChunk = function(_, c) written = c; return true end
  reaper.Undo_BeginBlock = function() end
  reaper.Undo_EndBlock = function() end
  check("rename: falls back to the chunk", FT.rename(0, 0, "{G1}", "Lead Comp"), true)
  check("rename: VST's fourth field", written and written:match('<VST[^\n]*'), '<VST "VST3: Pro-C 3 (FabFilter)" "Pro-C 3.vst3" 0 "Lead Comp" 1{ABC} ""')
  written = nil
  FT.rename(0, 1, "{G2}", 'Say "hi"')
  check("rename: JS's second, quoted around a quote", written and written:match('<JS[^\n]*'), "<JS loser/3BandEQ 'Say \"hi\"'")
  written = nil
  check("rename: an AU isn't touched", FT.rename(0, 2, "{G3}", "Z"), false)
  check("rename: nothing written for it", written, nil)
  reaper.TrackFX_SetNamedConfigParm = function() return true end
  reaper.TrackFX_GetNamedConfigParm = function(_, _, k) return true, k == "renamed_name" and "Lead Comp" or "" end
  written = nil
  check("rename: REAPER's own way, when it takes", FT.rename(0, 0, "{G1}", "Lead Comp"), true)
  check("rename: no chunk needed then", written, nil)
  reaper.TrackFX_SetNamedConfigParm, reaper.GetTrackStateChunk, reaper.SetTrackStateChunk,
    reaper.Undo_BeginBlock, reaper.Undo_EndBlock = table.unpack(s2)
  reaper.TrackFX_GetFXName, reaper.TrackFX_GetNamedConfigParm = saved[1], saved[2]
end

-- Control backgrounds: the shapes neighbours with the same one make
do
  local TL = require("TS_CV_Tiles")
  local function desc(sh)
    local t = {}
    for _, s in ipairs(sh) do t[#t + 1] = s.key .. ":" .. table.concat(s.outer, ",") .. (#s.holes > 0 and ("+" .. #s.holes .. "h") or "") end
    table.sort(t)
    return table.concat(t, " ")
  end
  check("backs: one control, padded", desc(TL.shapes({ { 0, 0, 50, 64, "a" } }, {}, 2)), "a:2,2,48,2,48,62,2,62")
  check("backs: a row joins", desc(TL.shapes({ { 0, 0, 50, 64, "a" }, { 50, 0, 100, 64, "a" } }, {}, 0)), "a:0,0,100,0,100,64,0,64")
  check("backs: a column joins", desc(TL.shapes({ { 0, 0, 50, 64, "a" }, { 0, 64, 50, 128, "a" } }, {}, 0)), "a:0,0,50,0,50,128,0,128")
  check("backs: different ones don't", #TL.shapes({ { 0, 0, 50, 64, "a" }, { 50, 0, 100, 64, "b" } }, {}, 0), 2)
  check("backs: an L is one shape", desc(TL.shapes({ { 0, 0, 50, 64, "a" }, { 0, 64, 50, 128, "a" }, { 50, 64, 100, 128, "a" } }, {}, 0)),
        "a:0,0,50,0,50,64,100,64,100,128,0,128")
  local L2 = TL.shapes({ { 0, 0, 50, 64, "a" }, { 0, 64, 50, 128, "a" }, { 50, 64, 100, 128, "a" } }, {}, 2)
  check("backs: the L's inside corner moves in too", table.concat(L2[1].outer, ","), "2,2,48,2,48,66,98,66,98,126,2,126")
  local ring = {}
  for i = 0, 2 do for j = 0, 2 do ring[#ring + 1] = { i * 50, j * 64, i * 50 + 50, j * 64 + 64, (i == 1 and j == 1) and "b" or "a" } end end
  check("backs: a ring has a hole", desc(TL.shapes(ring, {}, 0)), "a:0,0,150,0,150,192,0,192+1h b:50,64,100,64,100,128,50,128")
  check("backs: corners touching stay apart", #TL.shapes({ { 0, 0, 50, 64, "a" }, { 50, 64, 100, 128, "a" } }, {}, 0), 2)
  check("backs: across a divider", desc(TL.shapes({ { 0, 0, 50, 64, "a" }, { 59, 0, 109, 64, "a" } }, { { 50, 59 } }, 0)), "a:0,0,109,0,109,64,0,64")
  check("backs: not across for different ones", #TL.shapes({ { 0, 0, 50, 64, "a" }, { 59, 0, 109, 64, "b" } }, { { 50, 59 } }, 0), 2)
  check("backs: a divider with one side only", desc(TL.shapes({ { 0, 0, 50, 64, "a" }, { 59, 0, 109, 64, "a" } , { 0, 64, 50, 128, "a" } }, { { 50, 59 } }, 0)),
        "a:0,0,109,0,109,64,50,64,50,128,0,128")
  -- the layout gives each control its whole column and the dividers' gaps
  local rows_for, cw0 = P.rows_for, C.CELL_W
  P.rows_for = function(r) return r end
  C.set_cell_w(58)
  local lay = P.layout({ { type = "knob", size = "large" }, { type = "knob" }, { type = "divider" }, { type = "knob" } }, 3)
  check("backs: a medium under a large spans the column", lay.items[2].sx .. "/" .. lay.items[2].sw, "0/87")
  check("backs: the divider's gap", lay.gaps[1].x .. "/" .. lay.gaps[1].w, "87/9")
  local lh = P.layout({ { type = "knob", back = "inset" }, { type = "half_gap", back = "inset" }, { type = "knob", back = "inset" } }, 3)
  check("backs: a half-gap has a place", #lh.spacers .. ":" .. lh.spacers[1].sx .. "/" .. lh.spacers[1].y .. "/" .. lh.spacers[1].sw, "1:0/64/58")
  check("backs: it isn't a control", #lh.items, 2)
  P.rows_for, C.CELL_W = rows_for, cw0
  -- the Back line
  local MP = require("TS_CV_Mappings")
  MP.set("BackPlug", { controls = { { param = 0, type = "knob", label = "A", back = "inset" },
                                    { param = 1, type = "knob", label = "B", back = "cream" },
                                    { param = 2, type = "knob", label = "C", back = "nope" } } })
  MP.save(); MP.reload()
  local bc = MP.get("BackPlug").controls
  check("backs: inset round-trips", bc[1].back, "inset")
  check("backs: a plate round-trips", bc[2].back, "cream")
  check("backs: unknown dropped", bc[3].back, nil)
  check("backs: copied", MP.copy(MP.get("BackPlug")).controls[2].back, "cream")
  MP.remove("BackPlug"); MP.save(); MP.reload()

  -- brushed backgrounds and sections (Brush<n>)
  local alu, cream = C.plate_of("aluminium"), C.plate_of("cream")
  check("brush: aluminium is brushed of itself", MP.part_brushed("plate", alu, nil), true)
  check("brush: cream isn't", MP.part_brushed("plate", cream, nil), false)
  check("brush: an inset isn't", MP.part_brushed("inset", nil, nil), false)
  check("brush: asked for on an inset", MP.part_brushed("inset", nil, true), true)
  check("brush: turned off on aluminium", MP.part_brushed("plate", alu, false), false)
  check("brush: nothing to brush", MP.part_brushed(nil, nil, true), false)
  MP.set("BrushPlug", { controls = {
    { param = 0, type = "knob", label = "A", back = "cream", brush = true },
    { param = 1, type = "knob", label = "B", back = "aluminium", brush = false },
    { param = -1, type = "divider", style = "inset", brush = true },
    { param = 2, type = "knob", label = "C", brush = true },          -- no background: not saved
    { param = -1, type = "divider", brush = true } } })               -- no section: not saved
  MP.save(); MP.reload()
  local brc = MP.get("BrushPlug").controls
  check("brush: on a background round-trips", brc[1].brush, true)
  check("brush: off round-trips", brc[2].brush, false)
  check("brush: a section's round-trips", brc[3].brush, true)
  check("brush: not without a background", brc[4].brush, nil)
  check("brush: not without a section", brc[5].brush, nil)
  check("brush: copied", MP.copy(MP.get("BrushPlug")).controls[1].brush, true)
  MP.remove("BrushPlug"); MP.save(); MP.reload()
  -- surface finishes (Finish<n>, Finish): one per surface, Brush<n> the
  -- older way of saying brushed, still read
  check("finish: every one has a label", (function()
    for _, f in ipairs(C.FINISHES) do if not (f.key and f.label) then return false end end
    return #C.FINISHES end)(), 12)
  check("finish: aluminium's own", MP.finish({}, alu), "brushed")
  check("finish: cream's own", MP.finish({}, cream), nil)
  check("finish: chosen", MP.finish({ finish = "wood" }, cream), "wood")
  check("finish: plain on aluminium", MP.finish({ finish = "plain" }, alu), nil)
  check("finish: old Brush=1", MP.finish({ brush = true }, cream), "brushed")
  check("finish: no faceplate", MP.finish({ finish = "wood" }, nil), nil)
  check("finish: a part's chosen", MP.part_finish("inset", nil, "tolex", nil), "tolex")
  check("finish: a part's from Brush", MP.part_finish("plate", cream, nil, true), "brushed")
  check("finish: a part's plain", MP.part_finish("plate", alu, "plain", nil), nil)
  check("finish: nothing to finish", MP.part_finish(nil, nil, "wood", nil), nil)
  check("finish: unknown key dropped", MP.finish_of("glitter"), nil)
  MP.set("FinPlug", { plate = "cream", finish = "leather", controls = {
    { param = 0, type = "knob", label = "A", back = "cream", finish = "wood" },
    { param = 1, type = "knob", label = "B", back = "aluminium", finish = "plain" },
    { param = -1, type = "divider", style = "inset", finish = "hammertone" },
    { param = 2, type = "knob", label = "C", finish = "wood" },        -- no background: not saved
    { param = -1, type = "divider", finish = "wood" } } })             -- no section: not saved
  MP.save(); MP.reload()
  local fl = MP.get("FinPlug")
  check("finish: faceplate round-trips", fl.finish, "leather")
  check("finish: background round-trips", fl.controls[1].finish, "wood")
  check("finish: plain round-trips", fl.controls[2].finish, "plain")
  check("finish: section round-trips", fl.controls[3].finish, "hammertone")
  check("finish: not without a background", fl.controls[4].finish, nil)
  check("finish: not without a section", fl.controls[5].finish, nil)
  check("finish: copied", MP.copy(fl).controls[1].finish, "wood")
  check("finish: key", (P.back_key({ back = "cream", finish = "wood", metal = true })), "cream/wood/m")
  check("finish: key, plain aluminium", (P.back_key({ back = "aluminium", finish = "plain" })), "aluminium")
  MP.remove("FinPlug"); MP.save(); MP.reload()
  -- every finish has its texture
  do
    local here = debug.getinfo(1, "S").source:match("@?(.*[\\/])") or "./"
    local FNm = require("TS_CV_Finish")
    FNm.init(here .. "../")
    local missing = {}
    for _, f in ipairs(C.FINISHES) do
      if FNm.draws(f.key) then
        for _, k in ipairs({ f.key, f.under }) do
          local fh = io.open(FNm.file(k), "rb")
          if fh then fh:close() else missing[#missing + 1] = k end
        end
      end
    end
    check("finish: textures present", table.concat(missing, ","), "")
    check("finish: plain draws nothing", FNm.draws("plain"), false)
  end
  -- corners (Corners<n>): soft or round on a background or section
  MP.set("CornPlug", { controls = {
    { param = 0, type = "knob", label = "A", back = "cream", corners = "round" },
    { param = -1, type = "divider", style = "inset", corners = "soft" },
    { param = 1, type = "knob", label = "B", corners = "round" },
    { param = 2, type = "knob", label = "C", back = "inset", corners = "square" } } })
  MP.save(); MP.reload()
  local cc = MP.get("CornPlug").controls
  check("corners: background round-trips", cc[1].corners, "round")
  check("corners: section round-trips", cc[2].corners, "soft")
  check("corners: not without a background", cc[3].corners, nil)
  check("corners: square is no line", cc[4].corners, nil)
  check("corners: copied", MP.copy(MP.get("CornPlug")).controls[1].corners, "round")
  MP.remove("CornPlug"); MP.save(); MP.reload()
  check("corners: key", (P.back_key({ back = "cream", corners = "round" })), "cream/cround")
  check("corners: square key unchanged", (P.back_key({ back = "cream" })), "cream")
  check("corners: section keys differ", P.section_key({ style = "inset", corners = "soft" }) ~= P.section_key({ style = "inset" }), true)
  check("corners: radius, square", P.corner_r(nil, 80, 40, true), 4)
  check("corners: radius, soft", P.corner_r("soft", 80, 40, true), 10)
  check("corners: radius, round", P.corner_r("round", 80, 40, true), 20)
  check("corners: radius, round but wide", P.corner_r("round", 300, 400, true), 28)
  check("corners: radius, round L shape", P.corner_r("round", 80, 40, false), 10)
  do
    local poly = P._rounded_poly({ 0, 0, 100, 0, 100, 60, 0, 60 }, 20)
    local mid = P._poly_spans({ poly }, 0, 30)
    local top = P._poly_spans({ poly }, 0, 2)
    check("corners: spans mid-way", #mid == 2 and math.abs(mid[1]) < 0.01 and math.abs(mid[2] - 100) < 0.01, true)
    check("corners: spans near a round corner", #top == 2 and top[1] > 8 and top[2] < 92, true)
  end
  -- hardware switches: a toggle's Style; a button row never takes one
  check("switch: ten of them", #C.SWITCH_STYLES, 10)
  MP.set("SwPlug", { controls = { { param = 0, type = "toggle", label = "A", style = "litrocker", cap = "green" } } })
  MP.save(); MP.reload()
  check("switch: style round-trips", MP.get("SwPlug").controls[1].style, "litrocker")
  MP.remove("SwPlug"); MP.save(); MP.reload()
  do
    local row = { type = "combo", buttons = "across", nbtn = 3, style = "lens" }
    MP.paste_look(row, MP.look_of({ type = "toggle", style = "bat", cap = "red" }))
    check("switch: not on a button row", row.style, nil)
    local tg = { type = "toggle" }
    MP.paste_look(tg, MP.look_of({ type = "toggle", style = "bat", cap = "red" }))
    check("switch: pasted onto a toggle", tg.style, "bat")
  end
  -- knobs built from parts: recipes in the style list, saved like any style
  do
    local n = 0
    for _, st in ipairs(C.KNOB_STYLES) do if st.parts then n = n + 1 end end
    check("parts: recipes listed", n >= 16, true)
    check("parts: the numbered skirt reads as the printed one", C.KNOB_STYLE_ALIAS.numskirt, "printskirt")
    check("parts: a look's numbered skirt drawn printed", require("TS_CV_KnobParts").decode("skirt=numbered").skirt, "printed")
    MP.set("KpPlug", { controls = { { param = 0, type = "knob", label = "A", style = "bakelite", cap = "red" } } })
    MP.save(); MP.reload()
    check("parts: style round-trips", MP.get("KpPlug").controls[1].style, "bakelite")
    MP.remove("KpPlug"); MP.save(); MP.reload()
    local KPm = require("TS_CV_KnobParts")
    check("parts: reach, plain", KPm.reach({}), 1)
    check("parts: reach, skirt", KPm.reach({ skirt = "plain", sr = 1.5 }), 1.5)
    check("parts: reach, wing", KPm.reach({ ptr = "wing" }), 1.4)
    check("parts: centre, insert", KPm.centre_col({ top = "insert", insert = 0x112233ff }, 0xff0000ff), 0x112233ff)
  end
  -- a knob's own look (Look<n>): parts as text, and back
  do
    local KPm = require("TS_CV_KnobParts")
    local look = { profile = "tapered", grip = "fluted", n = 10, mat = "gloss", col = 0xb3201eff, side = 0x6c6e72ff,
                   top_r = 0.84, skirt = "dial", smat = "metal", sr = 1.62, sgrip = "knurled", washer = true, face = "flat",
                   inner = { r = 0.62, col = 0x9b9b97ff, mat = "bead", screws = true }, ptr = "inset", scale = "dots" }
    local back = KPm.decode(KPm.encode(look))
    check("look: colour round-trips", back.col, 0xb3201eff)
    check("look: words round-trip", back.grip .. "/" .. back.skirt .. "/" .. back.ptr .. "/" .. back.scale .. "/" .. back.face, "fluted/dial/inset/dots/flat")
    check("look: numbers round-trip", back.n == 10 and math.abs(back.top_r - 0.84) < 1e-6 and math.abs(back.sr - 1.62) < 1e-6, true)
    check("look: inner cap round-trips", back.inner and back.inner.screws and back.inner.mat, "bead")
    check("look: washer", back.washer, true)
    check("look: shadow round-trips", KPm.decode(KPm.encode({ shadow = "tall" })).shadow, "tall")
    check("look: shadow junk ignored", KPm.decode("shadow=huge"), nil)
    -- View > Shadows: strength scales every shadow; 0 draws none
    do
      local LTm = require("TS_CV_Light")
      local calls = 0
      local fake = setmetatable({}, { __index = function() return function() calls = calls + 1 end end })
      LTm.attach(fake)
      LTm.STRENGTH = 0; LTm.circle(nil, 0, 0, 20, 0.8); LTm.rect(nil, 0, 0, 10, 10, 2, 0.8)
      check("shadows: none at 0", calls, 0)
      LTm.STRENGTH = 1; LTm.circle(nil, 0, 0, 20, 0.8, 0)
      check("shadows: flush = the seam only", calls, 1)
      local _, _, s1 = LTm.offset(20, 0.8)
      LTm.STRENGTH = 2
      local _, _, s2 = LTm.offset(20, 0.8)
      check("shadows: stronger reach further", math.abs(s2 - 2 * s1) < 1e-9, true)
      check("shadows: deeper", LTm.shade(0x22, 0.8) > 0x22, true)
      LTm.STRENGTH = 1
    end
    check("look: junk ignored", KPm.decode("grip=lumpy,foo=1"), nil)
    check("look: copy is its own", (function() local c = KPm.copy(look); c.inner.r = 0.1; return look.inner.r end)(), 0.62)
    MP.set("LookPlug", { controls = { { param = 0, type = "knob", label = "A", style = "console", look = look },
                                       { param = 1, type = "toggle", label = "B", look = look } } })
    MP.save(); MP.reload()
    local lc = MP.get("LookPlug").controls
    check("look: Look<n> round-trips", lc[1].look and lc[1].look.grip, "fluted")
    check("look: not on a toggle", lc[2].look, nil)
    check("look: copied with the layout", MP.copy(MP.get("LookPlug")).controls[1].look.col, 0xb3201eff)
    local tgt = { type = "knob" }
    MP.paste_look(tgt, MP.look_of(lc[1]))
    check("look: pasted", tgt.look and tgt.look.skirt, "dial")
    -- a concentric knob: an outer recipe, an inner one, and their own looks
    MP.set("DualPlug", { controls = {
      { param = 0, param2 = 1, type = "dual", label = "EQ", style = "british", style2 = "redgloss" },
      { param = 2, param2 = 3, type = "dual", label = "Own", style = "british", look = look, look2 = { grip = "knurled", col = 0x112233ff } },
      { param = 4, param2 = 5, type = "dual", label = "Flat", style = "arc", style2 = "nonsense" },
      { param = 6, type = "knob", label = "K", style2 = "redgloss" } } })
    MP.save(); MP.reload()
    local dc = MP.get("DualPlug").controls
    check("dual: outer recipe", dc[1].style, "british")
    check("dual: inner recipe", dc[1].style2, "redgloss")
    check("dual: own outer look", dc[2].look and dc[2].look.grip, "fluted")
    check("dual: own inner look", dc[2].look2 and dc[2].look2.col, 0x112233ff)
    check("dual: arc", dc[3].style, "arc")
    check("dual: an unknown inner dropped", dc[3].style2, nil)
    check("dual: inner only on a dual", dc[4].style2, nil)
    check("dual: copied", MP.copy(MP.get("DualPlug")).controls[2].look2.grip, "knurled")
    local dt = { type = "dual" }
    MP.paste_look(dt, MP.look_of(dc[1]))
    check("dual: pasted pair", (dt.style or "") .. "/" .. (dt.style2 or ""), "british/redgloss")
    local kt = { type = "knob" }
    MP.paste_look(kt, MP.look_of(dc[2]))
    check("dual: onto a knob, the outer look", kt.look and kt.look.grip, "fluted")
    check("dual: onto a knob, no inner", kt.style2, nil)
    MP.remove("DualPlug")
    MP.remove("LookPlug"); MP.save(); MP.reload()
    -- your recipes: saved by name beside the layouts
    local RCm = require("TS_CV_Recipes")
    local tmpdir = os.tmpname():gsub("[^/\\]+$", "")
    os.remove(tmpdir .. "TS_ChannelView_Recipes.ini")
    RCm.init(tmpdir)
    check("recipes: none to start", #RCm.list(), 0)
    RCm.put("Desk 1176", look)
    RCm.put("Red", { col = 0xff0000ff })
    RCm.init(tmpdir)
    check("recipes: saved and read back", #RCm.list() == 2 and RCm.list()[1].name, "Desk 1176")
    check("recipes: the look", RCm.list()[1].look.grip, "fluted")
    RCm.put("Red", { col = 0x00ff00ff })
    check("recipes: same name replaces", #RCm.list() == 2 and RCm.list()[2].look.col, 0x00ff00ff)
    RCm.remove("Red")
    RCm.init(tmpdir)
    check("recipes: removed", #RCm.list(), 1)
    os.remove(tmpdir .. "TS_ChannelView_Recipes.ini")
  end
  -- a brushed and a plain one of the same colour are different backgrounds
  check("brush: key, brushed", (P.back_key({ back = "cream", brush = true })), "cream/brushed")
  check("brush: key, plain", (P.back_key({ back = "cream" })), "cream")
  check("brush: key, aluminium's own", (P.back_key({ back = "aluminium" })), "aluminium/brushed")
  check("brush: key, none", P.back_key({}), nil)
  -- the grain keeps clear of the edges, round an L and its inside corner
  local L = TL.shapes({ { 0, 0, 50, 64, "a" }, { 0, 64, 50, 128, "a" }, { 50, 64, 100, 128, "a" } }, {}, 0)
  local loops = { L[1].outer }
  check("grain: the upright of the L", table.concat(P._inner_spans(loops, 0, 0, 30, 2), ","), "2,48")
  check("grain: near the inside corner", table.concat(P._inner_spans(loops, 0, 0, 63, 2), ","), "2,48")
  check("grain: the foot", table.concat(P._inner_spans(loops, 0, 0, 100, 2), ","), "2,98")
  check("grain: none at the very top", #P._inner_spans(loops, 0, 0, 1, 2), 0)
  local rg = TL.shapes(ring, {}, 0)
  local outer
  for _, sh in ipairs(rg) do if sh.key == "a" then outer = sh end end
  check("grain: round a hole", table.concat(P._inner_spans({ outer.outer, outer.holes[1] }, 0, 0, 96, 2), ","), "2,48,102,148")
end

-- Sharing layouts: export some to a file, import from one
do
  local MP = require("TS_CV_Mappings")
  MP.set("ShareA", { plate = "cream", controls = { { param = 0, type = "knob", label = "A" },
                                                   { param = 1, type = "knob", label = "B" } } })
  MP.set("ShareB", { controls = { { param = 0, type = "toggle", label = "On" } } })
  MP.save()
  local file = "./share_test.ini"
  check("share: export", (MP.export(file, { "ShareA", "ShareB" })), true)
  check("share: nothing chosen", (MP.export(file .. "x", {})), false)
  -- in the same state: both "same as yours"
  local l = MP.read_shared(file)
  check("share: reads both", #l .. ":" .. l[1].key .. "," .. l[2].key, "2:ShareA,ShareB")
  check("share: identical ones say so", l[1].status .. "," .. l[2].status, "same,same")
  check("share: control counts", l[1].controls .. "," .. l[2].controls, "2,1")
  -- someone else's file: one of ours changed, one new, a future field, a non-layout section
  local f = io.open(file, "a")
  f:write("[ShareC]\nCtl0=3|knob|0|New one\nFutureThing=42\n\n[NotALayout]\nfoo=bar\n")
  f:close()
  MP.set("ShareB", { controls = { { param = 0, type = "knob", label = "Changed" } } })
  MP.save()
  l = MP.read_shared(file)
  local st = {}
  for _, e in ipairs(l) do st[#st + 1] = e.key .. "=" .. e.status end
  check("share: new, differs, same; non-layouts left out", table.concat(st, " "), "ShareA=same ShareB=differs ShareC=new")
  local pick = {}
  for _, e in ipairs(l) do if e.status ~= "same" then pick[#pick + 1] = e end end
  check("share: import", MP.import(pick), 2)
  MP.save(); MP.reload()
  check("share: replaced", MP.get("ShareB").controls[1].type .. "/" .. MP.get("ShareB").controls[1].label, "toggle/On")
  check("share: new one in", MP.get("ShareC").controls[1].label, "New one")
  local raw = io.open("./TS_ChannelView_Mappings.ini"):read("a")
  check("share: fields it doesn't know are kept", raw:find("FutureThing=42", 1, true) ~= nil, true)
  check("share: the old library is the .bak", io.open("./TS_ChannelView_Mappings.bak.ini"):read("a"):find("Changed", 1, true) ~= nil, true)
  check("share: keys lists them", table.concat(MP.keys(), ","):find("ShareA,ShareB,ShareC", 1, true) ~= nil, true)
  check("share: missing file", select(2, MP.read_shared("./nope.ini")) ~= nil, true)
  -- a locked layout here isn't replaced
  MP.set("ShareB", { lock = 2, controls = { { param = 0, type = "knob", label = "Mine, locked" } } })
  MP.save()
  local lk = MP.read_shared(file)
  local lst
  for _, e in ipairs(lk) do if e.key == "ShareB" then lst = e end end
  check("share: a locked one says so", lst.status, "locked")
  check("share: and isn't imported", MP.import({ lst }), 0)
  check("share: still yours", MP.get("ShareB").controls[1].label, "Mine, locked")
  os.remove(file)
  for _, k in ipairs({ "ShareA", "ShareB", "ShareC" }) do MP.remove(k) end
  MP.save(); MP.reload()
end

-- A faceplate not in the list leaves a layout on the theme's; a
-- colour of your own (#rrggbb) works anywhere a faceplate does
do
  local MP = require("TS_CV_Mappings")
  check("plates: a removed one is nothing", C.plate_key("indigo"), nil)
  check("plates: unknown is nothing", C.plate_key("nope"), nil)
  check("custom: key normalised", C.plate_key("#A9B99C"), "#a9b99c")
  check("custom: without the #", C.custom_key("a9b99c"), "#a9b99c")
  check("custom: not a colour", C.custom_key("#a9b99"), nil)
  check("custom: rgb", C.custom_rgb("#a9b99c"), 0xa9b99c)
  local lp = C.plate_of("#a9b99c")
  check("custom: light colour, dark inks", string.format("%08x/%08x/%08x", lp.text, lp.dim, lp.head),
        "181a16ff/40463bff/9aa88eff")
  local dp = C.plate_of("#8a5a59")
  check("custom: dark colour, light inks", string.format("%08x/%08x", dp.text, dp.head), "f6f2f2ff/714a49ff")
  check("custom: label", lp.label, "#A9B99C")
  check("custom: near-black gets less sheen", C.plate_of("#141414").sheen, 0.3)
  MP.set("AliasPlug", { plate = "#A9B99C", controls = {
    { param = 0, type = "knob", label = "A", back = "#112233" },
    { param = -1, type = "divider", style = "plate", cap = "#445566" },
    { param = 1, type = "knob", label = "B" } } })
  MP.save(); MP.reload()
  local l = MP.get("AliasPlug")
  check("custom: Plate round-trips", l.plate, "#a9b99c")
  check("custom: Back round-trips", l.controls[1].back, "#112233")
  check("custom: section round-trips", tostring(l.controls[2].style) .. "|" .. tostring(l.controls[2].cap), "plate|#445566")
  -- written by hand with faceplates since taken out, then read back
  local f = io.open(MP.file_path(), "rb"); local txt = f:read("a"); f:close()
  txt = txt:gsub("Plate=#a9b99c", "Plate=indigo"):gsub("Back0=#112233", "Back0=sage")
           :gsub("Style1=plate|#445566", "Style1=plate|lilac")
  f = io.open(MP.file_path(), "wb"); f:write(txt); f:close()
  MP.reload()
  l = MP.get("AliasPlug")
  check("removed: Plate=indigo is the theme's", l.plate, nil)
  check("removed: Back0=sage is none", l.controls[1].back, nil)
  check("removed: a lilac section is unstyled", l.controls[2].style, nil)
  MP.remove("AliasPlug"); MP.save(); MP.reload()
end

-- Metallic finish: Metal=1 on a faceplate, Metal<n>=1 on a background or section
do
  local MP = require("TS_CV_Mappings")
  MP.set("MetalPlug", { plate = "stone", metal = true, controls = {
    { param = 0, type = "knob", label = "A", back = "cream", metal = true, brush = true },
    { param = -1, type = "divider", style = "inset", metal = true },
    { param = 1, type = "knob", label = "B", metal = true } } })              -- no background: not saved
  MP.save(); MP.reload()
  local l = MP.get("MetalPlug")
  check("metal: faceplate round-trips", MP.metal(l, C.plate_of("stone")), true)
  check("metal: not on the theme's panel", MP.metal(l, nil), false)
  check("metal: background, with brushed too", tostring(l.controls[1].metal) .. "/" .. tostring(l.controls[1].brush), "true/true")
  check("metal: section round-trips", l.controls[2].metal, true)
  check("metal: not without a background", l.controls[3].metal, nil)
  check("metal: copied", tostring(MP.copy(l).metal) .. "/" .. tostring(MP.copy(l).controls[1].metal), "true/true")
  MP.remove("MetalPlug"); MP.save(); MP.reload()
  check("metal: key keeps metallic apart", (P.back_key({ back = "cream", metal = true })), "cream/m")
  check("metal: key, brushed and metallic", (P.back_key({ back = "cream", metal = true, brush = true })), "cream/brushed/m")
  check("metal: sections with and without don't match",
        P.section_key({ type = "divider", style = "inset", metal = true }) ~= P.section_key({ type = "divider", style = "inset" }), true)
end

-- Neighbouring sections with the same style join into one, across the divider
do
  local cw0 = C.CELL_W
  C.set_cell_w(58)
  local rows_for = P.rows_for
  P.rows_for = function(r) return r end
  local function lay(...) local t = {} for _, c in ipairs({ ... }) do t[#t + 1] = c end return P.layout(t, 2) end
  local K = { type = "knob" }
  local function div(style, cap, brush) return { type = "divider", style = style, cap = cap, brush = brush } end
  local l = lay(div("inset"), K, div("inset"), K, K)
  check("sections: two insets in a row join", #l.sections .. ":" .. l.sections[1].x .. "+" .. l.sections[1].w,
        "1:" .. C.DIVIDER_W .. "+" .. (2 * C.CELL_W + C.DIVIDER_W))
  check("sections: their controls share it", l.items[1].sec .. "," .. l.items[2].sec, "1,1")
  check("sections: the rule between stays", #l.rules, 2)
  check("sections: different plates don't join", #lay(div("plate", "cream"), K, div("plate", "cobalt"), K).sections, 2)
  check("sections: same plate does", #lay(div("plate", "cream"), K, div("plate", "cream"), K).sections, 1)
  check("sections: brushed and plain don't", #lay(div("plate", "cream", true), K, div("plate", "cream"), K).sections, 2)
  check("sections: not across an unstyled one", #lay(div("inset"), K, div(), K, div("inset"), K).sections, 2)
  check("sections: not across a fader", #lay(div("inset"), K, { type = "fader" }, div("inset"), K).sections, 2)
  check("sections: three in a row", #lay(div("inset"), K, div("inset"), K, div("inset"), K).sections, 1)
  P.rows_for = rows_for
  C.CELL_W = cw0
end

-- Layout lock: Lock=<rows> keeps the arrangement, and a short panel scrolls
do
  local MP = require("TS_CV_Mappings")
  MP.set("LockPlug", { lock = 3, controls = { { param = 0, type = "knob", label = "A" } } })
  MP.set("LockBad", { lock = 0, controls = { { param = 0, type = "knob", label = "A" } } })
  MP.save(); MP.reload()
  check("lock: round-trips", MP.locked(MP.get("LockPlug")), 3)
  check("lock: nonsense dropped", MP.locked(MP.get("LockBad")), nil)
  check("lock: copied", MP.copy(MP.get("LockPlug")).lock, 3)
  check("lock: none on a plain layout", MP.locked({ controls = {} }), nil)
  MP.remove("LockPlug"); MP.remove("LockBad"); MP.save(); MP.reload()

  local cw0 = C.CELL_W
  C.set_cell_w(58)
  local function knobs(n) local t = {} for i = 1, n do t[i] = { type = "knob" } end return t end
  local tall = C.HEADER_H + P.footer_h() + C.GRID_TOP_PAD + C.PANEL_PAD + 6 * C.CELL_H
  local short = C.HEADER_H + P.footer_h() + C.GRID_TOP_PAD + C.PANEL_PAD + 2 * C.CELL_H
  local a = P.layout(knobs(8), tall, 4)
  local b = P.layout(knobs(8), short, 4)
  check("lock: same rows however tall", a.rows .. "/" .. b.rows, "4/4")
  check("lock: same arrangement", a.width .. "/" .. a.items[5].x .. "," .. a.items[5].y,
        b.width .. "/" .. b.items[5].x .. "," .. b.items[5].y)
  check("lock: unlocked reflows", P.layout(knobs(8), short).rows, 2)
  check("lock: a tall panel doesn't scroll", P.scrolls(a, tall, 4), false)
  check("lock: a short one does", P.scrolls(b, short, 4), true)
  check("lock: unlocked never does", P.scrolls(b, short, nil), false)
  check("lock: its scrollbar widens the panel",
        P.width(knobs(16), short, false, false, nil, false, false, 4) - P.width(knobs(16), tall, false, false, nil, false, false, 4),
        C.SCROLL_W + 2)
  C.CELL_W = cw0
end

-- Numbered knob scales (Scale<n>), the LED ring, and the new plates and caps
do
  local MP = require("TS_CV_Mappings")
  MP.set("ScalePlug", { controls = {
    { param = 0, type = "knob", label = "A", scale = "values", scale_ink = "cap", cap = "gold" },
    { param = 1, type = "stepped", label = "B", scale = "ten", style = "led" },
    { param = 2, type = "knob", label = "C", scale = "bogus", scale_ink = "cap" },
    { param = 3, type = "knob", label = "D" } } })
  MP.save(); MP.reload()
  local l = MP.get("ScalePlug")
  check("scale: values round-trips", l.controls[1].scale .. "/" .. tostring(l.controls[1].scale_ink), "values/cap")
  check("scale: ten round-trips", l.controls[2].scale, "ten")
  check("scale: led style kept", l.controls[2].style, "led")
  check("scale: nonsense is the default", tostring(MP.scale_kind(l.controls[3])) .. "/" .. tostring(l.controls[3].scale_ink), "values/cap")
  check("scale: no line saved", l.controls[4].scale, nil)
  check("scale: no line is values", MP.scale_kind(l.controls[4]), "values")
  check("scale: ten is ten", MP.scale_kind(l.controls[2]), "ten")
  check("scale: not on a toggle", MP.scale_kind({ type = "toggle" }), nil)
  local cp = MP.copy(l)
  check("scale: copied", cp.controls[1].scale .. "/" .. cp.controls[1].scale_ink, "values/cap")
  MP.set("ScalePlug", { controls = {
    { param = 0, type = "knob", label = "A", scale = "none", scale_ink = "cap" },
    { param = 1, type = "knob", label = "B", scale = "values" },
    { param = 2, type = "knob", label = "C", scale_ink = "cap", cap = "#C9A24A" },
    { param = 3, type = "toggle", label = "D", cap = "#112233", style = "lens" },
    { param = 4, type = "combo", label = "E", buttons = "across", nbtn = 3, style = "window", cap = "amber" } } })
  MP.save()
  local f = io.open(MP.file_path(), "rb"); local txt = f:read("a"); f:close()
  check("scale: none written", txt:find("Scale0=none\n", 1, true) ~= nil, true)
  check("scale: values (the default) not written", txt:find("Scale1=", 1, true), nil)
  check("scale: default with |cap written", txt:find("Scale2=values|cap", 1, true) ~= nil, true)
  MP.reload()
  l = MP.get("ScalePlug")
  check("scale: none round-trips", tostring(l.controls[1].scale) .. "/" .. tostring(MP.scale_kind(l.controls[1])), "none/nil")
  check("scale: none drops |cap", l.controls[1].scale_ink, nil)
  check("cap: custom colour round-trips", l.controls[3].cap, "#c9a24a")
  check("cap: custom lit colour round-trips", l.controls[4].cap, "#112233")
  check("cap: custom colour drawn", string.format("%08x", W.cap_col("#c9a24a")), "c9a24aff")
  check("lit: custom colour", string.format("%08x", W.lit_col("#112233")), "112233ff")
  check("lit: by name", W.lit_col("amber"), C.TOGGLE_COL.amber.col)
  check("lit: theme's", W.lit_col(nil), nil)
  check("button style: toggle round-trips", l.controls[4].style, "lens")
  check("button style: button row round-trips", l.controls[5].style .. "|" .. l.controls[5].cap, "window|amber")
  for _, bs in ipairs(C.BUTTON_STYLES) do
    check("button style " .. bs.key .. ": known", C.BUTTON_STYLE[bs.key] ~= nil, true)
  end
  MP.remove("ScalePlug"); MP.save(); MP.reload()

  check("marks: medium values", table.concat(U.scale_marks("values", "medium"), ","), "0.0,0.5,1.0")
  check("marks: medium ten", #U.scale_marks("ten", "medium"), 6)
  check("marks: large values", #U.scale_marks("values", "large"), 7)
  check("marks: large ten", #U.scale_marks("ten", "large"), 11)
  check("marks: every step when few", #U.scale_marks("values", "medium", 4), 4)
  check("marks: too many steps", #U.scale_marks("values", "medium", 9), 3)
  check("marks: large every step", #U.scale_marks("values", "large", 11), 11)
  check("short: Hz", U.short_value("12000 Hz"), "12k")
  check("short: kHz", U.short_value("1.5 kHz"), "1.5k")
  check("short: dB", U.short_value("+6.0 dB"), "+6")
  check("short: negative zero", U.short_value("-0.00"), "0")
  check("short: ms", U.short_value("1000 ms"), "1k")
  check("short: inf", U.short_value("-inf dB"), "-inf")
  check("short: a name", U.short_value("Bell"), "Bell")
  check("labels: 0-10", table.concat(U.scale_labels(nil, 0, 0, "ten", { 0, 0.5, 1 }), ","), "0,5,10")

  check("plates: red is gone", C.plate_of("red"), nil)
  check("plates: gold", C.plate_of("gold") and C.plate_of("gold").label, "Gold")
  check("caps: white/brown/gold", (C.CAP.white and C.CAP.brown and C.CAP.gold) and true or false, true)
  check("knob style: led", C.KNOB_STYLE.led and C.KNOB_STYLE.led.label, "LED ring")
end

-- A track's fader look: its own over its group's (folder parents, VCA
-- leaders, FX returns), part by part
do
  local TO = require("TS_CV_TrackOps")
  local saved = {}
  for _, k in ipairs({ "GetSetMediaTrackInfo_String", "GetExtState", "SetExtState", "GetSetTrackGroupMembership",
      "GetSetTrackGroupMembershipHigh", "GetTrackNumSends", "GetParentTrack", "GetMediaTrackInfo_Value",
      "GetMasterTrack", "Undo_BeginBlock", "Undo_EndBlock", "time_precise" }) do saved[k] = reaper[k] end
  local ext, pext = {}, {}
  local tracks = {
    vca = { depth = 1, vca = 1, recv = 0 }, parent = { depth = 1, recv = 2 }, child = { depth = 0, parent = "parent", recv = 1 },
    ret = { depth = 0, recv = 3 }, plain = { depth = 0, recv = 0 } }
  local clock = 100
  reaper.time_precise = function() return clock end
  reaper.GetMasterTrack = function() return "master" end
  reaper.GetSetMediaTrackInfo_String = function(tr, k, v, set)
    if set then pext[tr .. k] = v; return true, v end
    return true, pext[tr .. k] or ""
  end
  reaper.GetExtState = function(sec, k) return ext[sec .. k] or "" end
  reaper.SetExtState = function(sec, k, v) ext[sec .. k] = v end
  reaper.GetSetTrackGroupMembership = function(tr, g) return (tracks[tr] and g == "VOLUME_VCA_LEAD" and tracks[tr].vca) or 0 end
  reaper.GetSetTrackGroupMembershipHigh = function() return 0 end
  reaper.GetTrackNumSends = function(tr, cat) return cat == -1 and tracks[tr].recv or 0 end
  reaper.GetParentTrack = function(tr) return tracks[tr].parent end
  reaper.GetMediaTrackInfo_Value = function(tr, k) if k == "I_FOLDERDEPTH" then return tracks[tr].depth end return 0 end
  reaper.Undo_BeginBlock = function() end; reaper.Undo_EndBlock = function() end
  TO.reload_fader_defaults()
  check("fader group: VCA leader (also a parent)", TO.fader_category("vca"), "vca")
  check("fader group: folder parent", TO.fader_category("parent"), "parent")
  check("fader group: a child with receives isn't a return", TO.fader_category("child"), nil)
  check("fader group: FX return", TO.fader_category("ret"), "fxret")
  check("fader group: plain", TO.fader_category("plain"), nil)
  check("fader group: master", TO.fader_category("master"), nil)
  check("fader look: none", TO.effective_fader_look("ret"), nil)
  TO.set_fader_default("fxret", "style", "console", true)
  TO.set_fader_default("fxret", "cap", "#C9A24A", true)
  clock = clock + 2
  local l = TO.effective_fader_look("ret")
  check("fader look: the group's", l and (l.style .. "|" .. l.cap), "console|#c9a24a")
  TO.set_fader_part({ "ret" }, "cap", "red", true)
  clock = clock + 2
  l = TO.effective_fader_look("ret")
  check("fader look: own colour on the group's style", l and (l.style .. "|" .. l.cap), "console|red")
  TO.set_fader_part({ "ret" }, "style", "flat", true)
  clock = clock + 2
  l = TO.effective_fader_look("ret")
  check("fader look: own flat wins", l and (l.style .. "|" .. l.cap), "flat|red")
  check("fader look: saved with the track", TO.fader_raw("ret"), "flat|red")
  TO.clear_fader_look({ "ret" })
  clock = clock + 2
  l = TO.effective_fader_look("ret")
  check("fader look: reset goes back to the group's", l and (l.style .. "|" .. l.cap), "console|#c9a24a")
  check("fader look: defaults kept", ext["TS_ChannelViewfader_defaults"], "fxret=console|#c9a24a")
  TO.set_fader_default("default", "style", "rail", true)
  clock = clock + 2
  l = TO.effective_fader_look("plain")
  check("fader look: no group takes the Default", l and l.style, "rail")
  check("fader look: the master too", (TO.effective_fader_look("master") or {}).style, "rail")
  TO.set_fader_default("fxret", "style", nil, true)
  clock = clock + 2
  l = TO.effective_fader_look("ret")
  check("fader look: a group's unset part falls to the Default", l and (l.style .. "|" .. l.cap), "rail|#c9a24a")
  TO.set_fader_default("fxret", "cap", nil, true); TO.set_fader_default("default", "style", nil, true)
  check("fader look: group cleared", ext["TS_ChannelViewfader_defaults"], "")
  -- background tint by group: the group's strength, else the Default's; 0 off
  check("bg tint: off by default", TO.track_tint("parent"), 0)
  check("bg tint: nothing to do when none set", TO.any_bg_tint(), false)
  TO.set_bg_tint("parent", 60, true)
  TO.set_bg_tint("default", 15, true)
  clock = clock + 2
  check("bg tint: parent", TO.track_tint("parent"), 0.6)
  check("bg tint: child takes the Default", TO.track_tint("child"), 0.15)
  check("bg tint: return takes the Default", TO.track_tint("ret"), 0.15)
  check("bg tint: master never", TO.track_tint("master"), 0)
  check("bg tint: saved", ext["TS_ChannelViewbg_tints"], "parent=60;default=15")
  TO.set_bg_tint("fxret", 30.4, true)
  clock = clock + 2
  check("bg tint: return's own", TO.track_tint("ret"), 0.3)
  -- a track's own strength wins over its group's, 0 included
  TO.set_own_tint({ "child" }, 45)
  clock = clock + 2
  check("bg tint: own", TO.track_tint("child"), 0.45)
  check("bg tint: own saved with the track", pext["childP_EXT:TS_CV_BGTINT"], "45")
  TO.set_own_tint({ "ret" }, 0)
  clock = clock + 2
  check("bg tint: own 0 beats the group", TO.track_tint("ret"), 0)
  TO.set_own_tint({ "child", "ret" }, nil)
  clock = clock + 2
  check("bg tint: back to the group's", TO.track_tint("child"), 0.15)
  check("bg tint: cleared from the track", pext["childP_EXT:TS_CV_BGTINT"], "")
  TO.set_bg_tint("parent", 0, true); TO.set_bg_tint("default", 0, true); TO.set_bg_tint("fxret", 0, true)
  check("bg tint: all off clears", ext["TS_ChannelViewbg_tints"], "")
  check("bg tint: off again", TO.track_tint("ret"), 0)
  TO.set_own_tint({ "plain" }, 20)
  clock = clock + 2
  check("bg tint: own works with no group strengths", TO.track_tint("plain"), 0.2)
  TO.set_own_tint({ "plain" }, nil)
  -- the colour maths
  local U = require("TS_CV_Util")
  check("tint: 0 is the base", U.tint(0x202327ff, 0xd9893aff, 0), 0x202327ff)
  check("tint: 1 is the colour, base alpha", U.tint(0x202327ff, 0xd9893aff, 1), 0xd9893aff)
  check("tint: half way", ("%08x"):format(U.tint(0x000000ff, 0x80808000, 0.5)), "404040ff")
  check("tint: a dark colour at full strength stays", U.tint_readable(0x202327ff, 0x2a4a6aff, 0.8), U.tint(0x202327ff, 0x2a4a6aff, 0.8))
  local y = U.tint_readable(0x202327ff, 0xe2d84aff, 0.9)
  check("tint: a pale colour is held back", U.is_light(y), false)
  check("tint: ...but still tinted", y ~= 0x202327ff, true)
  for k, f in pairs(saved) do reaper[k] = f end
  TO.reload_fader_defaults()
end

-- Faders of any shape: up or across, 2 to 4 rows (columns) long or the
-- full height (width), a whole column (row) or half of one
do
  local MP = require "TS_CV_Mappings"
  check("shape: read", table.concat({ tostring(MP.shape_of("h|3|half")) }, ""), "h")
  local d, l, t = MP.shape_of("v|full|half")
  check("shape: full length, half thick", tostring(d) .. tostring(l) .. tostring(t), "nilniltrue")
  check("shape: nonsense is the old fader", select(2, MP.shape_of("x|9|wide")) == nil, true)
  check("shape: line", MP.shape_line({ type = "fader", dir = "h", len = 2 }), "h|2|full")
  check("shape: no line for the old fader", tostring(MP.shape_line({ type = "fader" })), "nil")
  check("shape: no line on a knob", tostring(MP.shape_line({ type = "knob", dir = "h" })), "nil")

  local K = function(n) return { type = "knob", label = n, param = 0 } end
  local F = function(n, dir, len, thin) return { type = "fader", label = n, param = 0, dir = dir, len = len, thin = thin } end
  local function at(lay)
    local out = {}
    for _, it in ipairs(lay.items) do
      out[#out + 1] = ("%s@%g,%g %dx%d"):format(it.ctl.label, it.x / (C.CELL_W / 2), it.y / (C.CELL_H / 2), it.w, it.h)
    end
    return table.concat(out, " ")
  end
  -- a compressor: knobs over a horizontal fader, side by side
  local lay = P.layout({ K"Thr", K"Rat", F("Mk", nil, 2), K"Att", K"Knee", F("Mix", "h", 2), F("Wid", "h", 2),
                         K"Rel", K"Look", F("Out") }, nil, 4)
  check("faders: placed like the mockup", at(lay),
    "Thr@0,0 2x2 Rat@0,2 2x2 Mk@0,4 2x4 Att@2,0 2x2 Knee@2,2 2x2 Mix@2,4 4x2 Wid@2,6 4x2 Rel@4,0 2x2 Look@4,2 2x2 Out@6,0 2x8")
  check("faders: width", lay.width / C.CELL_W, 4)
  -- a row of half-width faders, 3 rows tall, after two knobs
  lay = P.layout({ K"A", K"B", F("31", nil, 3, true), F("63", nil, 3, true), F("125", nil, 3, true) }, nil, 4)
  check("faders: a row of half-width ones", at(lay), "A@0,0 2x2 B@0,2 2x2 31@2,0 1x6 63@3,0 1x6 125@4,0 1x6")
  -- full-length thin, as a column of its own
  lay = P.layout({ K"A", F("Out", nil, nil, true), K"B" }, nil, 4)
  check("faders: a half-width full-height one splits like the old one", at(lay), "A@0,0 2x2 Out@2,0 1x8 B@3,0 2x2")
  -- full length across: from where it lands to the panel's right edge
  lay = P.layout({ K"A", K"B", K"C", K"D", K"E", F("Pan", "h", nil, true) }, nil, 4)
  check("faders: full length to the right edge", at(lay), "A@0,0 2x2 B@0,2 2x2 C@0,4 2x2 D@0,6 2x2 E@2,0 2x2 Pan@2,2 4x1")
  lay = P.layout({ K"A", F("Pan", "h", nil, true), K"B", K"C", K"D", K"E" }, nil, 3)
  check("faders: full length under the first knob, the rest flow round it", at(lay),
    "A@0,0 2x2 Pan@0,2 6x1 B@0,3 2x2 C@2,0 2x2 D@2,3 2x2 E@4,0 2x2")
  -- merged cells: in list order, never back into an earlier gap (a
  -- Flow Mixing panel, 7 rows)
  lay = P.layout({ K"M1", F("M4", "h", 2), K"M2", F("M3", nil, 2, true), K"M5", K"M6", K"M7", K"M8",
                   { type = "divider" }, { type = "divider" }, K"P8" }, nil, 7)
  check("faders: list order kept", at(lay),
    "M1@0,0 2x2 M4@0,2 4x2 M2@0,4 2x2 M3@0.5,6 1x4 M5@0,10 2x2 M6@0,12 2x2 M7@2,0 2x2 M8@2,4 2x2 P8@" ..
    (4 + 2 * C.DIVIDER_W / (C.CELL_W / 2)) .. ",0 2x2")
  -- across a divider: the fader runs over it, the rule stops at it, the
  -- knobs after it start a new column and skip the fader's cells
  lay = P.layout({ K"A", F("X", "h", 3), K"B", { type = "divider" }, K"C", K"D" }, nil, 3)
  local dx = C.DIVIDER_W / (C.CELL_W / 2)
  check("faders: across a divider", at(lay), ("A@0,0 2x2 X@0,2 6x2 B@0,4 2x2 C@%g,0 2x2 D@%g,4 2x2"):format(2 + dx, 2 + dx))
  check("faders: its width covers the gap", lay.items[2].pw, 3 * C.CELL_W + C.DIVIDER_W)
  check("faders: the rule is cut", #lay.rule_cuts[1], 1)
  check("faders: panel width", lay.width, 3 * C.CELL_W + C.DIVIDER_W)
  -- half-width ones the same height pair up; anything else goes below
  lay = P.layout({ F("a", nil, 2, true), F("b", nil, 2, true), F("c", nil, 2, true), F("d", nil, 2, true), K"K" }, nil, 4)
  check("faders: half-width pairs", at(lay), "a@0,0 1x4 b@1,0 1x4 c@0,4 1x4 d@1,4 1x4 K@2,0 2x2")
  -- too long for the panel: as long as it can be
  lay = P.layout({ F("V", nil, 4) }, nil, 2)
  check("faders: no taller than the panel", at(lay), "V@0,0 2x4")
  -- an old layout doesn't move: no shapes, no change
  lay = P.layout({ K"A", K"B", K"C", F("Out"), K"D" }, nil, 2)
  check("faders: old layouts as they were", at(lay), "A@0,0 2x2 B@0,2 2x2 C@2,0 2x2 Out@4,0 2x4 D@6,0 2x2")
end



-- a knob's value arc (Style > Value arc): kept in the control's flags
do
  local MP = require "TS_CV_Mappings"
  MP.set("ArcPlug", { controls = {
    { param = 1, type = "knob", arc = "pos" },
    { param = 2, type = "knob", arc = "neg", invert = true, bipolar = true },
    { param = 3, type = "stepped", arc = "mid" },
    { param = 4, type = "knob" } } })
  MP.save(); MP.reload()
  local l = MP.get("ArcPlug").controls
  check("value arc: reads back", table.concat({ l[1].arc, l[2].arc, l[3].arc, tostring(l[4].arc) }, "|"), "pos|neg|mid|nil")
  check("value arc: the other flags kept", tostring(l[2].invert) .. tostring(l[2].bipolar), "truetrue")
  check("value arc: copied with the layout", MP.copy(MP.get("ArcPlug")).controls[2].arc, "neg")
  local lk = MP.look_of(l[3])
  local o = { type = "knob" }
  MP.paste_look(o, lk)
  check("value arc: pasted with a look", o.arc, "mid")
  check("value arc: centred makes the knob centred", o.bipolar, true)
  local o2 = { type = "knob", bipolar = true }
  MP.paste_look(o2, MP.look_of(l[1]))
  check("value arc: positive makes it not", tostring(o2.bipolar), "nil")
  local o3 = { type = "knob", bipolar = true }
  MP.paste_look(o3, MP.look_of(l[4]))
  check("value arc: no arc leaves it as it was", o3.bipolar, true)
end

-- the plugin's own colours (Palette=, TS_CV_PluginColours)
do
  local MP = require "TS_CV_Mappings"
  local PCx = require "TS_CV_PluginColours"
  local p = MP.palette_of("#1f2530 #2a323e|#70e1fe")
  check("palette: read", ("%06x %06x %06x"):format(p.surfaces[1], p.surfaces[2], p.accents[1]), "1f2530 2a323e 70e1fe")
  check("palette: written", MP.palette_line(p), "#1f2530 #2a323e|#70e1fe")
  check("palette: surfaces only", MP.palette_line(MP.palette_of("#101010")), "#101010|")
  check("palette: none", tostring(MP.palette_of("")) .. tostring(MP.palette_line(nil)), "nilnil")
  MP.set("PalPlug", { controls = { { param = 0, type = "knob" } }, palette = p })
  MP.save(); MP.reload()
  check("palette: kept with the layout", MP.palette_line(MP.get("PalPlug").palette), "#1f2530 #2a323e|#70e1fe")
  check("palette: copied", MP.palette_line(MP.copy(MP.get("PalPlug")).palette), "#1f2530 #2a323e|#70e1fe")
  -- a GUI: 70% dark base, 25% a raised panel, a cyan arc with soft edges
  local function px(x, y)
    if y < 10 and x < 40 then return (x % 2 == 0) and 0xff70e1fe or 0xff3a7a8a end
    if y < 30 then return 0xff2a323e end
    return 0xff1f2530
  end
  local s = PCx.sample(px, 100, 100)
  check("sample: base first", ("%06x"):format(s.surfaces[1]), "1f2530")
  check("sample: panel second", ("%06x"):format(s.surfaces[2]), "2a323e")
  check("sample: accent from the bright core", ("%06x"):format(s.accents[1]), "70e1fe")
end

-- a dropdown's Style: flat, or raised (a button row's lit styles count)
do
  local Wd = require "TS_CV_Widgets"
  check("raised dropdown", tostring(Wd.combo_raised("raised")) .. tostring(Wd.combo_raised("backlit"))
    .. tostring(Wd.combo_raised(nil)) .. tostring(Wd.combo_raised("flat")), "truetruefalsefalse")
end

-- an FX chain replacing a track's plugins (FB.replace): ChannelView's own
-- stay, the chain goes where the plugins began, a chain that won't load
-- leaves the track alone
do
  local FBx = require "TS_CV_FXButtons"
  local Tx = require "TS_CV_FXTree"
  local saved, mv = {}, Tx.move
  local fx, nid = {}, 0
  local function mk(n) nid = nid + 1; return { name = n, guid = "{" .. nid .. "}" } end
  local stub = {
    TrackFX_GetCount = function() return #fx end,
    TrackFX_GetNamedConfigParm = function(_, i, k) if k == "fx_name" and fx[i + 1] then return true, fx[i + 1].name end return false, "" end,
    TrackFX_GetFXName = function(_, i) return true, fx[i + 1] and fx[i + 1].name or "" end,
    TrackFX_GetFXGUID = function(_, i) return fx[i + 1] and fx[i + 1].guid end,
    TrackFX_Delete = function(_, i) table.remove(fx, i + 1) end,
    TrackFX_AddByName = function(_, name)
      if name == "Drums.RfxChain" then fx[#fx + 1] = mk("VST3: Kick EQ"); fx[#fx + 1] = mk("VST3: Kick Comp") end
      return -1
    end,
    GetResourcePath = function() return "/r" end,
  }
  for k, f in pairs(stub) do saved[k] = reaper[k]; reaper[k] = f end
  Tx.move = function(_, src, _, gap)
    local it = table.remove(fx, src[1] + 1)
    table.insert(fx, (gap > src[1]) and gap or gap + 1, it)
    return true
  end
  local function names() local t = {} for i, f in ipairs(fx) do t[i] = f.name end return table.concat(t, ", ") end
  fx = { mk("JS: TS_TrackProbe (pre)"), mk("JS: TS_CV Trimmer"), mk("VST3: Pro-Q 4"), mk("VST3: Pro-C 3"),
         mk("JS: ChannelView Modulators"), mk("JS: TS_TrackProbe (post)") }
  check("replace: the chain in", FBx.replace(nil, "Drums.RfxChain"), 2)
  check("replace: ours stay, the chain where the plugins began", names(),
    "JS: TS_TrackProbe (pre), JS: TS_CV Trimmer, VST3: Kick EQ, VST3: Kick Comp, JS: ChannelView Modulators, JS: TS_TrackProbe (post)")
  local was = names()
  check("replace: a chain that won't load", FBx.replace(nil, "Missing.RfxChain"), 0)
  check("replace: leaves the track as it was", names(), was)
  fx = { mk("VST3: Pro-Q 4") }
  FBx.replace(nil, "Drums.RfxChain")
  check("replace: a track of plugins only", names(), "VST3: Kick EQ, VST3: Kick Comp")
  check("chain way: tooltips", (FBx.tip({ cmd = "_TSCV_CHAIN:x", cm = "replace" }) or ""):find("Replace", 1, true) ~= nil, true)
  Tx.move = mv
  for k in pairs(stub) do reaper[k] = saved[k] end
end

-- the look new knobs and buttons start with (Style > Use this look for new ...)
do
  local MP = require "TS_CV_Mappings"
  local KPx = require "TS_CV_KnobParts"
  local ext = {}
  local g, s, d = reaper.GetExtState, reaper.SetExtState, reaper.DeleteExtState
  reaper.GetExtState = function(sec, k) return ext[sec .. k] or "" end
  reaper.SetExtState = function(sec, k, v) ext[sec .. k] = v end
  reaper.DeleteExtState = function(sec, k) ext[sec .. k] = nil end
  check("new look: none to start", MP.default_look("knob"), nil)
  local plain = MP.apply_default_look({ param = 0, type = "knob" })
  check("new look: none leaves a knob plain", tostring(plain.style) .. tostring(plain.arc), "nilnil")
  local look = KPx.decode("grip=grooves,n=24,mat=metal,col=#c0c0c0")
  MP.set_default_look("knob", { type = "knob", style = "console", cap = "red", scale_ink = "cap", arc = "neg", look = look })
  MP.set_default_look("toggle", { type = "toggle", style = "lens", cap = "green" })
  local k = MP.apply_default_look({ param = 0, type = "knob" })
  check("new look: knob", table.concat({ k.style, k.cap, k.scale_ink, k.arc }, "|"), "console|red|cap|neg")
  check("new look: knob's own look", tostring(KPx.encode(k.look)), "col=#c0c0c0,grip=grooves,mat=metal,n=24")
  local kc = MP.apply_default_look({ param = 1, type = "stepped", bipolar = true })
  check("new look: a centred knob gets Centred", kc.arc, "mid")
  local t = MP.apply_default_look({ param = 2, type = "toggle" })
  check("new look: button", t.style .. "|" .. t.cap, "lens|green")
  local f = MP.apply_default_look({ param = 3, type = "fader" })
  check("new look: a fader as it was", tostring(f.style) .. tostring(f.cap), "nilnil")
  MP.set_default_look("knob", { type = "knob", arc = "mid" })
  local kp = MP.apply_default_look({ param = 0, type = "knob" })
  check("new look: Centred default, not centred knob", kp.arc, "pos")
  check("new look: only what it has", tostring(kp.style) .. tostring(kp.look), "nilnil")
  MP.set_default_look("knob", nil)
  check("new look: forgotten", MP.default_look("knob"), nil)
  check("new look: button kept", MP.default_look("toggle").style, "lens")
  MP.set_default_look("toggle", nil)
  reaper.GetExtState, reaper.SetExtState, reaper.DeleteExtState = g, s, d
end

-- XY pads and concentric knobs: a second parameter (Dual<n>), their sizes,
-- and where an XY pad goes (merged cells, over dividers like an across fader)
do
  local MP = require "TS_CV_Mappings"
  MP.set("TwoPlug", { controls = {
    { param = 1, type = "xy", param2 = 4, size = "3x2", cap = "red", invert = true, invert2 = true },
    { param = 2, type = "dual", param2 = 3, size = "large" },
    { param = 5, type = "dual", param2 = 6, size = "small" },
    { param = 7, type = "xy" },
    { param = 8, type = "knob", param2 = 9 } } })
  MP.save(); MP.reload()
  local l = MP.get("TwoPlug").controls
  check("two: xy reads back", table.concat({ l[1].type, l[1].param, l[1].param2, l[1].size, l[1].cap }, "|"), "xy|1|4|3x2|red")
  check("two: dual reads back", table.concat({ l[2].type, l[2].param, l[2].param2, l[2].size }, "|"), "dual|2|3|large")
  check("two: both reversed", tostring(l[1].invert) .. tostring(l[1].invert2), "truetrue")
  check("two: second not reversed", tostring(l[2].invert2), "nil")
  check("two: a concentric knob is never small", tostring(l[3].size), "nil")
  check("two: a 2x2 pad has no size line", tostring(l[4].size), "nil")
  check("two: no second parameter yet", tostring(l[4].param2), "nil")
  check("two: a knob has no second parameter", tostring(l[5].param2), "nil")
  check("two: pad dims", table.concat({ MP.pad_dims(l[1]) }, "x") .. " " .. table.concat({ MP.pad_dims(l[4]) }, "x"), "3x2 2x2")
  check("two: copy keeps it", MP.copy(MP.get("TwoPlug")).controls[1].param2, 4)
  check("two: pad size nonsense", tostring(MP.pad_size_of("4x4")), "nil")
  -- looks: a pad takes a pad's size, a knob's colour; a dual is a knob
  local pad = { type = "xy" }
  MP.paste_look(pad, MP.look_of({ type = "xy", size = "3x3", cap = "blue" }))
  check("two: pad to pad", pad.size .. "|" .. pad.cap, "3x3|blue")
  local pad2 = { type = "xy", size = "2x3" }
  MP.paste_look(pad2, MP.look_of({ type = "knob", size = "large", cap = "red" }))
  check("two: knob to pad: colour, not size", pad2.size .. "|" .. pad2.cap, "2x3|red")
  local d = { type = "dual" }
  MP.paste_look(d, MP.look_of({ type = "knob", size = "small", cap = "red" }))
  check("two: a small knob's look leaves a dual its size", tostring(d.size) .. "|" .. d.cap, "nil|red")

  local K = function(n) return { type = "knob", label = n, param = 0 } end
  local X = function(n, size) return { type = "xy", label = n, param = 0, param2 = 1, size = size } end
  local function at(lay)
    local out = {}
    for _, it in ipairs(lay.items) do
      out[#out + 1] = ("%s@%g,%g %dx%d"):format(it.ctl.label, it.x / (C.CELL_W / 2), it.y / (C.CELL_H / 2), it.w, it.h)
    end
    return table.concat(out, " ")
  end
  -- merged cells: knobs above and below a 2x2 pad's second column
  local lay = P.layout({ K"A", X("Pad"), K"B", K"C", K"D" }, nil, 4)
  check("two: pad merges cells", at(lay), "A@0,0 2x2 Pad@0,2 4x4 B@0,6 2x2 C@2,0 2x2 D@2,6 2x2")
  -- too tall for the panel: as tall as it can be
  lay = P.layout({ X("Pad", "3x3") }, nil, 2)
  check("two: pad no taller than the panel", at(lay), "Pad@0,0 6x4")
  -- over a divider, like an across fader: the rule is cut
  lay = P.layout({ K"A", X("Pad", "3x2"), { type = "divider" }, K"B" }, nil, 3)
  local dx = C.DIVIDER_W / (C.CELL_W / 2)
  check("two: pad over a divider", at(lay), ("A@0,0 2x2 Pad@0,2 6x4 B@%g,0 2x2"):format(2 + dx))
  check("two: pad over a divider: rule cut", #(lay.rule_cuts[1] or {}), 1)
  check("two: pad's width covers the gap", lay.items[2].pw, 3 * C.CELL_W + C.DIVIDER_W)
  -- a concentric knob sizes like a knob
  lay = P.layout({ { type = "dual", label = "Dl", param = 0, param2 = 1, size = "large" }, K"A" }, nil, 3)
  check("two: dual large", at(lay), "Dl@0,0 3x3 A@0.5,3 2x2")
end

-- Copy and paste a control's look (TS_CV_Mappings.look_of / paste_look)
do
  local MP = require "TS_CV_Mappings"
  local src = { type = "knob", param = 3, label = "Thr", style = "skirted", cap = "red", size = "large",
                scale = "ten", scale_ink = "cap", back = "inset", brush = true, metal = true, bipolar = true }
  local s = MP.look_of(src)
  local k = { type = "stepped", param = 7, label = "Keep", style = "bar", cap = "blue" }
  check("look: knob to knob", MP.paste_look(k, s), true)
  check("look: knob to knob fields", table.concat({ k.style, k.cap, k.size, k.scale, k.scale_ink, k.back,
    tostring(k.brush), tostring(k.metal) }, "|"), "skirted|red|large|ten|cap|inset|true|true")
  check("look: what it is stays", k.param .. k.label .. k.type .. tostring(k.bipolar), "7Keepsteppednil")
  local f = { type = "fader", style = "rail", dir = "h", len = 3, thin = true }
  MP.paste_look(f, s)
  check("look: knob to fader keeps its style and shape", table.concat({ f.style, f.cap, tostring(f.size), f.dir, f.len, tostring(f.thin), f.back }, "|"),
    "rail|red|nil|h|3|true|inset")
  local f3 = { type = "fader" }
  MP.paste_look(f3, MP.look_of({ type = "fader", style = "slim", cap = "red", dir = "h", len = 3, thin = true }))
  check("look: fader to fader takes its shape", table.concat({ f3.style, f3.cap, f3.dir, f3.len, tostring(f3.thin) }, "|"),
    "slim|red|h|3|true")
  local f4 = { type = "fader", dir = "h", len = 2 }
  MP.paste_look(f4, MP.look_of({ type = "fader" }))
  check("look: an ordinary fader's shape too", tostring(f4.dir) .. tostring(f4.len), "nilnil")
  local b = { type = "toggle", style = "lens", size = "small" }
  MP.paste_look(b, s)
  check("look: knob red to a button is the button's red", table.concat({ b.style, b.cap, b.size }, "|"), "lens|red|small")
  -- a colour only one kind has: as a custom colour
  local t = { type = "toggle" }
  MP.paste_look(t, MP.look_of({ type = "knob", cap = "orange" }))
  check("look: a colour the buttons don't have", t.cap, "#d98a2f")
  -- the knob's style colour when it has none of its own
  local f2 = { type = "fader" }
  MP.paste_look(f2, MP.look_of({ type = "knob", style = "skirted" }))
  check("look: a style's own colour goes across", f2.cap, "black")
  local k2 = { type = "knob", cap = "red" }
  MP.paste_look(k2, MP.look_of({ type = "knob", style = "skirted" }))
  check("look: the same kind takes no colour as no colour", tostring(k2.cap), "nil")
  -- button to button: size too; the theme's colour stays the theme's
  local b2 = { type = "toggle", cap = "amber" }
  MP.paste_look(b2, MP.look_of({ type = "toggle", style = "window", size = "small" }))
  check("look: button to button", table.concat({ b2.style, tostring(b2.cap), b2.size }, "|"), "window|nil|small")
  local k3 = { type = "knob", cap = "red" }
  MP.paste_look(k3, MP.look_of({ type = "toggle", cap = "theme" }))
  check("look: the theme's button colour is a knob's own", tostring(k3.cap), "nil")
  -- a gap carries a background only; a divider takes nothing
  local k4 = { type = "knob", style = "bar", back = "inset", brush = true }
  MP.paste_look(k4, MP.look_of({ type = "blank" }))
  check("look: a gap's look is its background", table.concat({ k4.style, tostring(k4.back), tostring(k4.brush) }, "|"), "bar|nil|nil")
  check("look: a divider takes nothing", MP.paste_look({ type = "divider" }, s), false)
  check("look: family of a dropdown as buttons", MP.look_family({ type = "combo", buttons = "across" }), "button")
  check("look: family of a plain dropdown", tostring(MP.look_family({ type = "combo" })), "nil")
end

-- REAPER's oversampling (TS_CV_FXTree): a ceiling, not a factor -- names,
-- what each means at the running rate, what reads and writes which
-- setting, and what oversamples a panel from around it
do
  local FT = require("TS_CV_FXTree")
  check("os: names at 48k", table.concat({ FT.os_label(0, 48000), FT.os_label(1, 48000), FT.os_label(4, 48000) }, " | "),
        "Off | Up to 96 kHz | Up to 768 kHz")
  check("os: names at 44.1k", FT.os_label(2, 44100), "Up to 176.4 kHz")
  check("os: names at 88.2k", FT.os_label(1, 88200), "Up to 88.2 kHz")
  check("os: factor", table.concat({ FT.os_factor(96000, 48000), FT.os_factor(192000, 96000), FT.os_factor(96000, 96000) }, " "), "2 2 1")
  local saved = {}
  for _, k in ipairs({ "TrackFX_GetNamedConfigParm", "TrackFX_SetNamedConfigParm", "TrackFX_GetCount",
                       "GetSetProjectInfo", "GetAudioDeviceInfo", "Undo_BeginBlock", "Undo_EndBlock", "time_precise" }) do
    saved[k] = reaper[k]
  end
  local cfg, sets, clock, rate = { [0] = { chain_oversample_shift = "2" }, [9] = { instance_oversample_shift = "3" } }, {}, 0, 48000
  reaper.time_precise = function() clock = clock + 1; return clock end   -- never cached
  reaper.TrackFX_GetNamedConfigParm = function(_, a, k) local v = cfg[a] and cfg[a][k]; return v ~= nil, v or "" end
  reaper.TrackFX_SetNamedConfigParm = function(_, a, k, v) sets[#sets + 1] = a .. ":" .. k .. "=" .. v
    cfg[a] = cfg[a] or {}; cfg[a][k] = v; return true end
  reaper.TrackFX_GetCount = function() return 2 end
  reaper.Undo_BeginBlock = function() end
  reaper.Undo_EndBlock = function() end
  reaper.GetSetProjectInfo = function(_, k) if k == "PROJECT_SRATE_USE" then return 0 end return 96000 end
  reaper.GetAudioDeviceInfo = function() return true, tostring(rate) end
  check("os: running at the device's rate", FT.run_rate(), 48000)
  check("os: the chain's", FT.chain_os("TR"), 2)
  check("os: chain lit 4x at 48k", FT.chain_state("TR").lit, 4)
  local outer, top = FT.os_outer("TR", { ancestors = { { addr = 9 }, { addr = 8 } } })
  check("os: outer, chain then container", #outer .. " " .. outer[1].hz .. " " .. outer[2].hz .. " " .. top, "2 192000 384000 384000")
  -- a plugin's own 2x under a 4x chain: not what raises it, so not lit
  cfg[1] = { instance_oversample_shift = "1" }
  local st = FT.os_state("TR", { addr = 1 })
  check("os: own lower than the chain: faint", tostring(st.lit) .. " " .. tostring(st.faint), "nil true")
  cfg[1] = { instance_oversample_shift = "3" }
  st = FT.os_state("TR", { addr = 1 })
  check("os: own higher than the chain: lit at its own", st.lit, 8)
  cfg[0].chain_oversample_shift = "0"
  rate = 96000
  cfg[1] = { instance_oversample_shift = "1" }
  st = FT.os_state("TR", { addr = 1 })
  check("os: up to 96k at 96k does nothing", tostring(st.lit) .. " " .. tostring(st.faint), "nil true")
  cfg[1] = { instance_oversample_shift = "2" }
  check("os: up to 192k at 96k is 2x", FT.os_state("TR", { addr = 1 }).lit, 2)
  cfg[1] = {}
  st = FT.os_state("TR", { addr = 1 })
  check("os: off and nothing around: quiet", tostring(st.lit) .. " " .. tostring(st.faint), "nil false")
  sets = {}
  FT.set_os_shift("TR", 1, 2, "plugin")
  FT.set_chain_os("TR", 0)
  check("os: set a plugin's and the chain's (through the first plugin)", table.concat(sets, " "),
        "1:instance_oversample_shift=2 0:chain_oversample_shift=0")
  reaper.TrackFX_GetCount = function() return 0 end
  check("os: an empty chain can't be set", FT.set_chain_os("TR", 1), false)
  check("os: an empty chain reads off", FT.chain_os("TR"), 0)
  reaper.GetSetProjectInfo = function(_, k) if k == "PROJECT_SRATE_USE" then return 1 end return 96000 end
  check("os: or the project's rate, when it's set to use its own", FT.run_rate(), 96000)
  for _, k in ipairs({ "JS_Window_SetFocus", "JS_Window_FindChildByID", "GetMainHwnd",
                       "SetCursorContext", "NamedCommandLookup" }) do reaper[k] = saved[k] end
end

-- View > Strip width: clamped, and the strips' width follows it
do
  local Cf = require("TS_CV_Config")
  local CHm = require("TS_CV_Channel")
  local was = Cf.CHANNEL_W
  Cf.set_channel_w(40);  check("strip width: floor", Cf.CHANNEL_W, Cf.CHANNEL_W_MIN)
  Cf.set_channel_w(999); check("strip width: ceiling", Cf.CHANNEL_W, Cf.CHANNEL_W_MAX)
  Cf.set_channel_w("x"); check("strip width: junk is the default", Cf.CHANNEL_W, 112)
  Cf.set_channel_w(150)
  check("strip width: expanded strips follow, collapsed don't", CHm.width(false) .. " " .. CHm.width(true),
        "150 " .. Cf.COLLAPSED_W)
  Cf.CHANNEL_W = was
end

-- a sidechain into a container, and offline (TS_CV_FXTree)
do
  local FT = require("TS_CV_FXTree")
  local saved = {}
  for _, k in ipairs({ "TrackFX_GetNamedConfigParm", "TrackFX_SetNamedConfigParm", "TrackFX_GetIOSize",
                       "TrackFX_GetPinMappings", "TrackFX_SetPinMappings", "Undo_BeginBlock", "Undo_EndBlock",
                       "TrackFX_GetOffline", "TrackFX_SetOffline" }) do saved[k] = reaper[k] end
  local cfg = { [7] = { container_nch = "2", container_nch_in = "2" }, [8] = { container_nch = "4", container_nch_in = "4" } }
  local pins = { [7] = { [0] = 1, [1] = 2 }, [8] = { [0] = 1, [1] = 2, [2] = 4, [3] = 8 } }
  local nin = { [5] = 4, [6] = 2 }
  reaper.TrackFX_GetNamedConfigParm = function(_, a, k) local v = cfg[a] and cfg[a][k]; return v ~= nil, v or "" end
  reaper.TrackFX_SetNamedConfigParm = function(_, a, k, v) cfg[a] = cfg[a] or {}; cfg[a][k] = v; return true end
  reaper.TrackFX_GetIOSize = function(_, a) return 0, nin[a] or 2, 2 end
  reaper.TrackFX_GetPinMappings = function(_, a, io, p) return (pins[a] or {})[p] or 0, 0 end
  reaper.TrackFX_SetPinMappings = function(_, a, io, p, lo) pins[a] = pins[a] or {}; pins[a][p] = lo; return true end
  reaper.Undo_BeginBlock = function() end
  reaper.Undo_EndBlock = function() end
  local comp = { addr = 5, ancestors = { { addr = 8 }, { addr = 7 } } }
  local gap = FT.sidechain_gap("TR", comp)
  check("sc: only the narrow container", #gap .. " " .. gap[1].addr, "1 7")
  check("sc: two inputs, nothing to pass", #FT.sidechain_gap("TR", { addr = 6, ancestors = comp.ancestors }), 0)
  check("sc: not in a container", #FT.sidechain_gap("TR", { addr = 5 }), 0)
  check("sc: passed", FT.pass_sidechain("TR", comp), true)
  check("sc: widened, pins on 3 and 4", table.concat({ cfg[7].container_nch, cfg[7].container_nch_in, pins[7][2], pins[7][3] }, " "),
        "4 4 4 8")
  check("sc: nothing left to pass", #FT.sidechain_gap("TR", comp), 0)
  check("sc: the wide one untouched", pins[8][2] .. " " .. cfg[8].container_nch_in, "4 4")
  local off = {}
  reaper.TrackFX_GetOffline = function(_, a) return off[a] == true end
  reaper.TrackFX_SetOffline = function(_, a, o) off[a] = o end
  FT.set_offline("TR", 3, true, "X")
  check("offline: set", FT.get_offline("TR", 3), true)
  FT.set_offline("TR", 3, false, "X")
  check("offline: back online", FT.get_offline("TR", 3), false)
  for _, k in ipairs({ "JS_Window_SetFocus", "JS_Window_FindChildByID", "GetMainHwnd",
                       "SetCursorContext", "NamedCommandLookup" }) do reaper[k] = saved[k] end
end

-- ReaEQ: a band at -inf gain (ReaEQ's own floor) must not poison the curve
do
  local RQ = require("TS_CV_ReaEQ")
  local floor = { bandtype = RQ.BAND_TYPE.BAND, freq = 100, gain = -math.huge, q = 1, enabled = true }
  local bell  = { bandtype = RQ.BAND_TYPE.BAND, freq = 1000, gain = 6, q = 1, enabled = true }
  local d = RQ.band_db(floor, 100, 48000)
  check("eq: -inf band is finite", d == d and d > -math.huge, true)
  check("eq: -inf band is a deep cut", d < -25, true)
  local t = RQ.total_db({ floor, bell }, { val = 0 }, 1000, 48000)
  check("eq: total with a -inf band is finite", t == t and t > -math.huge, true)
  check("eq: total keeps the other band", ("%.1f"):format(RQ.total_db({ bell }, { val = 0 }, 1000, 48000)), "6.0")
  check("eq: NaN master counts as 0", ("%.1f"):format(RQ.total_db({ bell }, { val = 0/0 }, 1000, 48000)), "6.0")
  -- a shelf at the floor must not ring: nothing above its corner moves
  local shelf = { bandtype = RQ.BAND_TYPE.LOSHELF, freq = 100, gain = -math.huge, q = 0.7071, enabled = true }
  local s2k = RQ.band_db(shelf, 2000, 48000)
  check("eq: floored shelf is flat above its corner", math.abs(s2k) < 1.5, true)
  check("eq: floored shelf cuts below it", RQ.band_db(shelf, 30, 48000) < -20, true)
end

-- ReaComp: display text, the normalised/real curve, the transfer curve
do
  local RC = require("TS_CV_ReaComp")
  check("rc: is_comp", RC.is_comp("ReaComp") and not RC.is_comp("ReaEQ"), true)
  check("rc: parse -18.0", RC.parse("-18.0"), -18.0)
  check("rc: parse unicode minus", RC.parse("\u{2212}6.5 dB"), -6.5)
  check("rc: parse ratio", RC.parse("4.0:1"), 4.0)
  check("rc: parse -inf", RC.parse("-inf"), -math.huge)
  check("rc: parse inf ratio", RC.parse("inf:1"), math.huge)
  check("rc: parse kHz", RC.parse("1.5 kHz"), 1500)
  check("rc: parse a name", RC.parse("Main inputs"), nil)
  check("rc: parse Off", RC.parse("Off"), nil)
  -- a made-up threshold: -inf at 0, then dB rising with the value
  local s = {}
  for i = 0, 10 do
    local n = i / 10
    local v = (i == 0) and -math.huge or (20 * math.log(n, 10))
    s[#s + 1] = { n, v, tostring(v) }
  end
  local m = RC.map_from(s)
  check("rc: real at 1", RC.real(m, 1), 0)
  check("rc: real at 0.5", ("%.2f"):format(RC.real(m, 0.5)), "-6.02")
  check("rc: real next to -inf", RC.real(m, 0.01), -math.huge)
  check("rc: norm of -6.02", ("%.3f"):format(RC.norm(m, 20 * math.log(0.5, 10))), "0.500")
  check("rc: norm between samples", ("%.3f"):format(RC.norm(m, (20 * math.log(0.5, 10) + 20 * math.log(0.6, 10)) / 2)), "0.550")
  check("rc: norm past the top clamps", RC.norm(m, 6), 1)
  check("rc: norm of -inf", RC.norm(m, -math.huge), 0)
  -- a falling display (larger value, smaller number)
  local f = RC.map_from({ { 0, 10, "10" }, { 0.5, 5, "5" }, { 1, 0, "0" } })
  check("rc: norm on a falling display", RC.norm(f, 7.5), 0.25)
  -- choices
  local c = RC.choices(RC.map_from({ { 0, nil, "Main" }, { 0.25, nil, "Main" }, { 0.5, nil, "Aux" },
                                     { 0.75, nil, "Aux" }, { 1, nil, "Mid" } }))
  check("rc: choices count", #c, 3)
  check("rc: choice middles", c[1].norm .. " " .. c[2].norm .. " " .. c[3].text, "0.125 0.625 Mid")
  -- the transfer curve
  check("rc: below threshold 1:1", RC.transfer(-30, -18, 4, 0), -30)
  check("rc: above threshold", RC.transfer(-10, -18, 4, 0), -16)
  check("rc: infinite ratio holds", RC.transfer(-2, -18, math.huge, 0), -18)
  check("rc: knee start is 1:1", RC.transfer(-21, -18, 4, 6), -21)
  check("rc: knee end meets the ratio", RC.transfer(-15, -18, 4, 6), -18 + 3 / 4)
  check("rc: knee middle below the line", ("%.4f"):format(RC.transfer(-18, -18, 4, 6)), ("%.4f"):format(-18 + (0.25 - 1) * 9 / 12))
  check("rc: reduction", RC.reduction(-10, -18, 4, 0), 6)
  -- continuous across the knee edges
  local a1, a2 = RC.transfer(-15.0001, -18, 4, 6), RC.transfer(-14.9999, -18, 4, 6)
  check("rc: knee joins smoothly", math.abs(a1 - a2) < 0.001, true)
  -- the envelope's time axis
  check("rc: time 0 at the start", RC.time_frac(0, 0.1, 500), 0)
  check("rc: time at the top", RC.time_frac(500, 0.1, 500), 1)
  check("rc: time round trip", ("%.3f"):format(RC.frac_time(RC.time_frac(14, 1, 5000), 1, 5000)), "14.000")
  check("rc: rise ends at 1", ("%.6f"):format(RC.rise(1)), "1.000000")
  -- parameters by name
  local saved = { reaper.TrackFX_GetNumParams, reaper.TrackFX_GetParamName }
  -- REAPER 7.82's ReaComp, as it lists its parameters
  local names = { "Threshold", "Ratio", "Attack", "Release", "Pre-comp", "resvd", "Lowpass", "Hipass",
                  "SignIn", "AudIn", "Dry", "Wet", "Filter Preview", "RMS size", "Knee", "Auto Make Up Gain",
                  "Auto Release", "Legacy Attack/Knee Options", "Deprecated Broken Anti-Alias",
                  "Multichannel Mode", "Metering Index", "Bypass", "Wet", "Delta" }
  reaper.TrackFX_GetNumParams = function() return #names end
  reaper.TrackFX_GetParamName = function(_, _, i) return true, names[i + 1] end
  local fp = RC.params("TR", 0, "{RC}")
  check("rc: params found", table.concat({ fp.thr, fp.ratio, fp.atk, fp.rel, fp.pre, fp.lp, fp.hp, fp.det,
    fp.audio, fp.dry, fp.wet, fp.rms, fp.knee, fp.autorel, fp.makeup }, " "),
    "0 1 2 3 4 6 7 8 12 10 11 13 14 16 15")
  check("rc: no limit parameter", fp.limit, nil)
  check("rc: detector main", RC.det_text(0), "Main input")
  check("rc: detector sidechain", RC.det_text(2 / RC.DET_MAX), "Sidechain (aux 3/4)")
  check("rc: detector other", RC.det_text(5 / RC.DET_MAX), "Input 5")
  check("rc: parse ratio with units", RC.parse("6.85 :1"), 6.85)
  check("rc: parse inf ratio with units", RC.parse("inf :1"), math.huge)
  check("rc: usable", RC.usable(fp), true)
  reaper.TrackFX_GetNumParams, reaper.TrackFX_GetParamName = saved[1], saved[2]
end

-- ---------------------------------------------------------------------
-- Pages: a page-break control splits a panel into tabbed pages
do
  local St = require "TS_CV_State"
  local function K(p) return { type = "knob", param = p } end
  local function PG(l, cap) return { type = "page", param = -1, label = l, cap = cap } end
  local D = { type = "divider", param = -1 }

  check("pages: none without a break", P.pages({ K(0), D, K(1) }), nil)
  check("pages: empty list", P.pages({}), nil)
  check("pages: nil list", P.pages(nil), nil)

  -- controls before the first break are page 1 (unnamed)
  local pages = P.pages({ K(0), K(1), PG("EQ", "#d9893a"), K(2), D, K(3), PG("Dyn"), K(4) })
  check("pages: count", #pages, 3)
  check("pages: first page unnamed", pages[1].label, nil)
  check("pages: first page label is its number", P.page_label(pages[1]), "1")
  check("pages: first page controls", #pages[1].controls, 2)
  check("pages: named page label", P.page_label(pages[2]), "EQ")
  check("pages: page colour", pages[2].cap, "#d9893a")
  check("pages: theme colour by default", pages[3].cap, nil)
  check("pages: divider stays inside a page", #pages[2].controls, 3)
  check("pages: break index in the full list", pages[2].idx, 3)
  check("pages: last page", #pages[3].controls .. " " .. pages[3].n, "1 3")
  check("pages: empty name falls back to number", P.page_label({ label = "", n = 2 }), "2")

  -- a leading break: no empty first page
  pages = P.pages({ PG("A"), K(0), PG("B"), K(1) })
  check("pages: leading break drops empty page", #pages .. " " .. P.page_label(pages[1]), "2 A")
  -- a trailing break is a page of its own, empty
  pages = P.pages({ K(0), PG("Z") })
  check("pages: trailing break keeps its page", #pages .. " " .. #pages[2].controls, "2 0")

  -- the grid ignores page breaks: they take no cell
  local lay = P.layout({ K(0), PG("EQ"), K(1), K(2) }, nil, 3)
  local lay1 = P.layout({ K(0), K(1), K(2) }, nil, 3)
  check("pages: layout skips breaks", lay.width, lay1.width)

  -- width: the widest page, not all pages together
  local six = { K(0), K(1), K(2), K(3), K(4), K(5) }
  local flat, split = {}, {}
  for i = 1, 12 do flat[i] = K(i) end
  for i = 1, 6 do split[i] = K(i) end
  split[7] = PG("B")
  for i = 7, 12 do split[i + 1] = K(i) end
  local one = P.width(flat, 400, false, false, "x")
  local paged = P.width(split, 400, false, false, "x")
  local half = P.width(six, 400 - C.TAB_STRIP_H, false, false, "x")
  check("pages: flat panel wider than the minimum", one > C.PANEL_MIN_W, true)
  check("pages: paged narrower than flat", paged < one, true)
  check("pages: paged as wide as its widest page", paged, half)
  -- ...but never narrower than its tab strip
  local wide = P.width({ K(0), PG("A rather long tab name"), K(1), PG("And another long one"), K(2) }, 400, false, false, "x")
  check("pages: tab strip sets a floor", wide > half, true)

  -- the open page, per instance, in the project
  local PROJ = {}
  reaper.GetProjExtState = function(_, ns, k) return 1, PROJ[ns .. k] or "" end
  reaper.SetProjExtState = function(_, ns, k, v) PROJ[ns .. k] = v end
  St.clear_cache()
  check("pages: page 1 by default", St.page("{P}"), 1)
  St.set_page("{P}", 2)
  check("pages: set page", St.page("{P}"), 2)
  check("pages: page saved with the project", PROJ["TS_ChannelViewpage:{P}"], "2")
  St.set_page("{P}", 1)
  check("pages: page 1 clears the key", PROJ["TS_ChannelViewpage:{P}"], "")
  St.set_page("{P}", 9)
  check("pages: open page clamped to what it has", P.page_of("{P}", P.pages({ K(0), PG("B"), K(1) })), 2)
  check("pages: no guid is page 1", St.page(nil), 1)
  St.clear_cache()
  check("pages: cache cleared rereads", St.page("{P}"), 9)
  reaper.GetProjExtState, reaper.SetProjExtState = nil, nil
  St.clear_cache()
end

-- ---------------------------------------------------------------------
-- Busy: backing off while REAPER is busy
do
  local BZ = require "TS_CV_Busy"
  BZ.reset()
  local t = 0
  local function frames(n, dur) local b for i = 1, n do t = t + dur; b = BZ.note(dur, t) end return b end
  check("busy: quick frames never back off", frames(50, 0.02), false)
  check("busy: typical settles", BZ.typical() > 0.015 and BZ.typical() < 0.025, true)
  check("busy: one slow frame is nothing", frames(1, 0.5), false)
  check("busy: two slow frames still nothing", frames(1, 0.5), false)
  frames(1, 0.02)
  check("busy: a quick one resets the run", frames(2, 0.5), false)
  check("busy: three in a row back off", frames(1, 0.5), true)
  check("busy: no probe straight away", BZ.probe_due(t + 0.5), false)
  check("busy: probe after a second", BZ.probe_due(t + 1.1), true)
  check("busy: a slow probe stays backed off", BZ.note(0.6, t + 1.1), true)
  check("busy: a quick probe resumes", BZ.note(0.02, t + 2.2), false)
  check("busy: not backed off means frames run", BZ.probe_due(t + 2.3), true)
  -- a slow machine: every frame slow, none of them "suddenly"
  BZ.reset()
  frames(200, 0.2)
  check("busy: uniformly slow is not busy", BZ.backed(), false)
  check("busy: typical follows a slow machine", BZ.typical() > 0.15, true)
  check("busy: slow machine needs 5x to trip", frames(3, 0.8), false)
  check("busy: ...and trips at 5x", frames(3, 1.6), true)
  -- slow for good (a plugin slow to answer every frame, not a job that
  -- ends): after BZ.GIVE_UP seconds of slow probes, that's the new typical
  BZ.reset()
  t = 0
  frames(50, 0.02)
  frames(3, 0.4)
  check("busy: backed off", BZ.backed(), true)
  local b0 = t
  for k = 1, 10 do BZ.note(0.4, b0 + k) end
  check("busy: still waiting before giving up", BZ.backed(), true)
  for k = 11, BZ.GIVE_UP + 1 do BZ.note(0.4, b0 + k) end
  check("busy: gives up waiting: carries on", BZ.backed(), false)
  check("busy: the slow frame is the typical now", math.abs(BZ.typical() - 0.4) < 0.01, true)
  t = b0 + BZ.GIVE_UP + 2
  check("busy: and doesn't trip on it again", frames(5, 0.4), false)
  BZ.reset()
end

-- Presets: REAPER's preset count is asked for now and then, not every
-- frame -- and a plugin slow to answer it (VSL Synchron Player, a third
-- of a second) only once a minute or when its preset changes.
do
  local PR = require("TS_CV_Presets")
  local saved = {}
  for _, k in ipairs({ "TrackFX_GetFXGUID", "TrackFX_GetPresetIndex", "time_precise", "TrackFX_GetUserPresetFilename" }) do saved[k] = reaper[k] end
  local now, asked, cost = 100, 0, 0
  reaper.time_precise = function() return now end
  reaper.TrackFX_GetFXGUID = function() return "{SLOW}" end
  reaper.TrackFX_GetUserPresetFilename = function() return nil end
  reaper.TrackFX_GetPresetIndex = function() asked = asked + 1; now = now + cost; return 0, 5 end
  PR.forget()
  for _ = 1, 60 do PR.list(0, 0); now = now + 0.016 end
  check("presets: count asked now and then, not every frame", asked <= 2, true)
  PR.forget(); asked = 0; cost = 0.34
  for _ = 1, 600 do PR.list(0, 0); now = now + 0.016 end
  check("presets: a slow plugin is asked once in ~10 s", asked, 1)
  PR.seen(0, 0, "A"); PR.seen(0, 0, "B")
  PR.list(0, 0)
  check("presets: ...and again when its preset changes", asked, 2)
  for k, v in pairs(saved) do reaper[k] = v end
  PR.forget()
end

-- ---------------------------------------------------------------------
-- Show: conditional controls
do
  check("show: parse toggle rule", M.show_line(M.show_of("3|1|0.499|0")), "3|1.0000|0.4990|0")
  check("show: parse short rule", M.show_of("4|0").tol, 0.499)
  check("show: parse not (old 0/1 field)", M.show_of("4|0|0.1|1").op, "not")
  do
    -- several settings: "is" any of them, "not" none of them
    local r = M.show_of("7|0.2500|0.0500|0|0.5000;0.7500")
    check("show several: read", #M.show_values(r), 3)
    check("show several: written back", M.show_line(r), "7|0.2500|0.0500|0|0.5000;0.7500")
    check("show several: is any", tostring(M.show_match(0.5, r)) .. tostring(M.show_match(0.75, r)) .. tostring(M.show_match(0, r)), "truetruefalse")
    local n = M.show_of("7|0.2500|0.0500|1|0.7500")
    check("show several: not any", tostring(M.show_match(0.75, n)) .. tostring(M.show_match(0.5, n)), "falsetrue")
    check("show several: one alone, as before", M.show_line(M.show_of("7|0.2500|0.0500|0")), "7|0.2500|0.0500|0")
    check("show several: none left, no rule", M.show_set_values({}, {}), false)
    local fmt = function(_, v) return ({ [0.25] = "Hall", [0.5] = "Plate", [0.75] = "Room" })[v] end
    check("show several: said", M.rule_text(r, function() return "Mode" end, fmt), "Mode is Hall, Plate or Room")
    -- a list read off a plugin sits at its settings' middles only roughly:
    -- by text, the setting it's on counts wherever in its run it is
    local rr = M.show_of("32|0.1925|0.0170|0|0.3200")
    local function same(n) return math.abs(n - 0.3200) < 1e-6 end   -- (it reads as at 0.32)
    check("show by text: off the middle, still that setting", M.show_match(0.2990, rr, nil, same), true)
    check("show by text: without, by distance only", M.show_match(0.2990, rr), false)
    check("show by text: is not, too", M.show_match(0.2990, M.show_of("32|0.1925|0.0170|1|0.3200"), nil, same), false)
    check("show several: between ignores them", M.show_line(M.show_of("7|0.2|0.05|4|0.6")), "7|0.2000|0.0500|4|0.6000")
  end
  check("show: bad line", M.show_of("x|y"), nil)
  check("show: nil line", M.show_of(nil), nil)
  check("show: value clamped", M.show_of("2|7").norm, 1)
  local on  = { param = 3, norm = 1, tol = 0.499 }
  local off = { param = 3, norm = 1, tol = 0.499, inv = true }
  check("show: on matches 1", M.show_match(1, on), true)
  check("show: on misses 0", M.show_match(0, on), false)
  check("show: not-on matches 0", M.show_match(0, off), true)
  -- above / below / between: a knob's value, or a dropdown's order
  local ab = M.show_of("6|0.5|0.005|2")
  check("show: parse above", ab.op, "above")
  check("show: above", M.show_match(0.51, ab), true)
  check("show: above excludes the value", M.show_match(0.5, ab), false)
  local be = M.show_of("6|0.5|0.005|3")
  check("show: below", M.show_match(0.2, be) and not M.show_match(0.7, be), true)
  local bt = M.show_of("6|0.75|0.005|4|0.25")
  check("show: parse between", bt.op .. " " .. bt.norm2, "between 0.25")
  check("show: between either way round", M.show_match(0.5, bt), true)
  check("show: between includes ends", M.show_match(0.25, bt) and M.show_match(0.75, bt), true)
  check("show: between excludes outside", M.show_match(0.8, bt), false)
  check("show: between line", M.show_line(bt), "6|0.7500|0.0050|4|0.2500")
  check("show: between with no second value", M.show_of("6|0.3|0.005|4").norm2, 0.3)
  check("show: unknown op reads as is", M.show_of("6|0.3|0.005|9").op, "is")
  check("show: rule made before ops", M.show_match(0, { param = 1, norm = 1, tol = 0.499, inv = true }), true)
  local mid = { param = 5, norm = 0.5, tol = 0.124 }
  check("show: choice hits its step", M.show_match(0.5, mid), true)
  check("show: choice misses the next", M.show_match(0.75, mid), false)

  -- a delay: sync on shows the note knob, off the ms knob, in one place
  local K = function(p, extra) local c = { type = "knob", param = p }; for k, v in pairs(extra or {}) do c[k] = v end; return c end
  local ctls = { K(0), { type = "toggle", param = 3 }, K(1, { show = on }), K(2, { show = off }), K(4) }
  local vals = { [3] = 1 }
  local get = function(p) return vals[p] or 0 end
  local shown, hidden = M.visible(ctls, get)
  check("show: sync on shows note", #shown .. " " .. tostring(shown[3].param), "4 1")
  check("show: sync on hides ms", hidden[4], true)
  vals[3] = 0
  shown, hidden = M.visible(ctls, get)
  check("show: sync off shows ms", tostring(shown[3].param), "2")
  check("show: sync off hides note", hidden[3], true)
  check("show: same tables kept", shown[1] == ctls[1], true)
  local plain = { K(0), K(1) }
  check("show: no rules is the same list", M.visible(plain, get) == plain, true)
  -- the swap takes one cell: the grid is as wide either way
  local la = P.layout(M.visible(ctls, get), nil, 3)
  vals[3] = 1
  local lb = P.layout(M.visible(ctls, get), nil, 3)
  check("show: swap keeps the width", la.width, lb.width)
  check("show: swap takes one cell", #la.items, 4)

  -- round trip through the file, and a page break keeps no rule
  M.set("ShowTest", { controls = { K(1, { show = on }), K(2, { show = off }),
                                   { type = "page", param = -1, label = "B", show = on } } })
  M.save(); M.reload()
  local back = M.get("ShowTest")
  check("show: round trip", M.show_line(back.controls[1].show), "3|1.0000|0.4990|0")
  check("show: round trip not", back.controls[2].show.op, "not")
  check("show: page keeps no rule", back.controls[3].show, nil)
  check("show: copy carries rule", M.copy(back).controls[2].show.op, "not")
  check("show: copy is a copy", M.copy(back).controls[1].show ~= back.controls[1].show, true)
  M.set("ShowTest", { controls = { K(1, { show = { param = 6, op = "between", norm = 0.2, norm2 = 0.6, tol = 0.005 } }) } })
  M.save(); M.reload()
  check("show: between round trip", M.show_line(M.get("ShowTest").controls[1].show), "6|0.2000|0.0050|4|0.6000")
  check("show: copy carries between", M.copy(M.get("ShowTest")).controls[1].show.norm2, 0.6)
  M.remove("ShowTest"); M.save(); M.reload()
end

-- ---------------------------------------------------------------------
-- Variants: more than one layout per plugin, picked per instance
do
  local St = require "TS_CV_State"
  check("variant: key", M.variant_key("Kontakt 7", "Strings"), "Kontakt 7 :: Strings")
  check("variant: no name is the plugin's", M.variant_key("Kontakt 7", nil), "Kontakt 7")
  local b, v = M.split_variant("Kontakt 7 :: Strings")
  check("variant: split", b .. "|" .. v, "Kontakt 7|Strings")
  b, v = M.split_variant("Kontakt 7")
  check("variant: split plain", b .. "|" .. tostring(v), "Kontakt 7|nil")
  check("variant: clean brackets", M.clean_variant(" [Pno] "), "Pno")
  check("variant: clean separator", M.clean_variant("a :: b"), "a - b")
  check("variant: clean empty", M.clean_variant("   "), nil)

  M.set("Kontakt 7", { controls = { { type = "knob", param = 0 } } })
  M.set("Kontakt 7 :: Strings", { controls = { { type = "knob", param = 1 }, { type = "knob", param = 2 } } })
  M.set("Kontakt 7 :: Piano", { controls = { { type = "knob", param = 3 } } })
  M.set("Kontakt 70", { controls = {} })
  M.save(); M.reload()
  check("variant: list", table.concat(M.variants("Kontakt 7"), ","), "Piano,Strings")
  check("variant: none for others", #M.variants("Kontakt 70"), 0)

  local PROJ = {}
  reaper.GetProjExtState = function(_, ns, k) return 1, PROJ[ns .. k] or "" end
  reaper.SetProjExtState = function(_, ns, k, val) PROJ[ns .. k] = val end
  St.clear_cache()
  local name = "VST3i: Kontakt 7 (Native Instruments)"
  check("variant: default instance", St.layout_key(name, "{A}"), "Kontakt 7")
  St.set_variant("{A}", "Strings")
  check("variant: set", St.layout_key(name, "{A}"), "Kontakt 7 :: Strings")
  check("variant: other instance unchanged", St.layout_key(name, "{B}"), "Kontakt 7")
  check("variant: saved with project", PROJ["TS_ChannelViewvariant:{A}"], "Strings")
  St.clear_cache()
  check("variant: reread after cache clear", St.layout_key(name, "{A}"), "Kontakt 7 :: Strings")
  M.remove("Kontakt 7 :: Strings"); M.save(); M.reload()
  check("variant: deleted falls back", St.layout_key(name, "{A}"), "Kontakt 7")
  St.set_variant("{A}", nil)
  check("variant: back to default clears", PROJ["TS_ChannelViewvariant:{A}"], "")
  -- the Rack view picks apart: ChannelView's pick until it has its own
  do
    M.set("Kontakt 7 :: Across", { controls = {} }); M.set("Kontakt 7 :: Down", { controls = {} })
    St.set_variant("{R}", "Across")
    St.VARIANT, M.VIEW_DEFAULTS = "rvariant:", M.RACK_DEFAULTS_SECT
    check("rack: follows ChannelView's pick", St.layout_key(name, "{R}"), "Kontakt 7 :: Across")
    St.set_variant("{R}", "Down")
    check("rack: its own pick", St.layout_key(name, "{R}"), "Kontakt 7 :: Down")
    check("rack: kept apart", PROJ["TS_ChannelViewrvariant:{R}"], "Down")
    St.set_variant("{R}", St.OWN)
    check("rack: own standard", St.layout_key(name, "{R}"), "Kontakt 7")
    St.set_variant("{R}", nil)
    M.set_default_variant("Kontakt 7", "Down")
    check("rack: its default beats ChannelView's pick", St.layout_key(name, "{R}"), "Kontakt 7 :: Down")
    check("rack: default kept apart", M.default_variant("Kontakt 7", M.DEFAULTS_SECT), nil)
    M.set_default_variant("Kontakt 7", nil)
    St.VARIANT, M.VIEW_DEFAULTS = "variant:", M.DEFAULTS_SECT
    check("channelview: unchanged by the rack", St.layout_key(name, "{R}"), "Kontakt 7 :: Across")
    St.set_variant("{R}", nil)
    -- a popped-out panel picks apart too: its own, else the pick of the
    -- view it's laid out like (the rack's when stacked), else defaults
    M.set("Kontakt 7 :: Pop", { controls = {} })
    St.set_variant("{R}", "Across")
    St.VARIANT, St.VARIANT_ALSO = "rvariant:", nil
    St.set_variant("{R}", "Down")
    St.VARIANT, St.VARIANT_ALSO = "pvariant:", { "variant:" }
    check("popout across: ChannelView's pick", St.layout_key(name, "{R}"), "Kontakt 7 :: Across")
    St.VARIANT_ALSO = { "rvariant:" }
    M.VIEW_DEFAULTS = M.RACK_DEFAULTS_SECT
    check("popout down: the rack's pick", St.layout_key(name, "{R}"), "Kontakt 7 :: Down")
    St.set_variant("{R}", "Pop")
    check("popout: its own pick", St.layout_key(name, "{R}"), "Kontakt 7 :: Pop")
    check("popout: kept apart", PROJ["TS_ChannelViewpvariant:{R}"], "Pop")
    St.VARIANT, St.VARIANT_ALSO, M.VIEW_DEFAULTS = "variant:", nil, M.DEFAULTS_SECT
    check("channelview: unchanged by a pop-out", St.layout_key(name, "{R}"), "Kontakt 7 :: Across")
    for _, pf in ipairs({ "variant:", "rvariant:", "pvariant:" }) do
      St.VARIANT = pf; St.set_variant("{R}", nil)
    end
    St.VARIANT = "variant:"
    M.remove("Kontakt 7 :: Across"); M.remove("Kontakt 7 :: Down"); M.remove("Kontakt 7 :: Pop")
  end
  -- making variants: a copy, or empty with the names kept
  local src = { controls = { { type = "knob", param = 5 } }, aliases = { [5] = "Verb" }, lock = 3 }
  local k, nm = M.new_variant("Kontakt 7", " Pads ", src, false)
  check("variant: new copy key", k, "Kontakt 7 :: Pads")
  check("variant: new copy name", nm, "Pads")
  check("variant: copy has controls", #M.get(k).controls, 1)
  check("variant: copy is saved", M.has(k), true)
  check("variant: name taken", M.new_variant("Kontakt 7", "Pads", src, false), nil)
  check("variant: bad name", M.new_variant("Kontakt 7", "  ", src, false), nil)
  local ke = M.new_variant("Kontakt 7", "Blank", src, true)
  check("variant: empty has no controls", #M.get(ke).controls, 0)
  check("variant: empty keeps names", M.get(ke).aliases[5], "Verb")
  check("variant: empty is unlocked", M.get(ke).lock, nil)
  check("variant: copy left the source alone", #src.controls, 1)
  check("variant: signature same", M.signature(M.get(k)) == M.signature(M.copy(M.get(k))), true)
  check("variant: signature differs", M.signature(M.get(k)) ~= M.signature(M.get(ke)), true)
  M.remove(k); M.remove(ke)
  reaper.GetProjExtState, reaper.SetProjExtState = nil, nil
  St.clear_cache()
  M.remove("Kontakt 7"); M.remove("Kontakt 7 :: Piano"); M.remove("Kontakt 70"); M.save(); M.reload()
end

-- ---------------------------------------------------------------------
-- your own range for a parameter (Range<p>): Acustica's numbers
-- ---------------------------------------------------------------------
do
  local f = { lo = 20, hi = 20000, unit = "Hz", curve = "log" }
  check("range: log ends", U.range_text(f, 0) .. " | " .. U.range_text(f, 1), "20.0 Hz | 20.0 kHz")
  check("range: log middle", U.range_text(f, 0.5), "632 Hz")
  check("range: back", ("%.3f"):format(U.range_norm(f, 632.46)), "0.500")
  local t = { lo = 0.1, hi = 2000, unit = "ms", curve = "sq" }
  check("range: squared", U.range_text(t, 0.5) .. " | " .. U.range_text(t, 1), "500 ms | 2.00 s")
  check("range: squared back", ("%.3f"):format(U.range_norm(t, 500.075)), "0.500")
  local d = { lo = -30, hi = 0, unit = "dB", curve = "lin" }
  check("range: linear dB", U.range_text(d, 0.25), "-22.5 dB")
  check("range: log refused across zero", U.range_text({ lo = -1, hi = 1, unit = "", curve = "log" }, 0.75), "0.50")
  check("range: ratio", U.range_text({ lo = 1, hi = 20, unit = ":1", curve = "log" }, 0.5), "4.5:1")
  -- it reads as that while in force, and the values everywhere follow
  local UN_ = require("TS_CV_Units")
  local rgn = reaper.TrackFX_GetParamNormalized
  reaper.TrackFX_GetParamNormalized = function() return 0.5 end
  local was = U.with_ranges({ [3] = f })
  check("range: formatted value", U.fmt_value({}, 0, 3), "632 Hz")
  check("range: a canvas reads it", (UN_.parse(require("TS_CV_ReaComp").text({}, 0, 3))), 632.0)
  local fm = UN_.formatter({}, 0, 3)
  check("range: the formatter", fm(1), "20.0 kHz")
  check("range: find a value", ("%.3f"):format(UN_.find_norm(fm, 1000)), "0.566")
  check("range: scale labels", table.concat(U.scale_labels({}, 0, 3, "values", { 0, 0.5, 1 }), ","), "20,632,20k")
  check("range: other params untouched", U.range_of(4), nil)
  U.with_ranges(was)
  check("range: put back", U.range_of(3), nil)
  reaper.TrackFX_GetParamNormalized = rgn
  -- kept with the layout
  check("range: line", M.range_line(f), "20|20000|Hz|log")
  local r2 = M.range_of_line(" 1 | 10 | bogus | weird ")
  check("range: line read", r2.lo .. " " .. r2.hi .. " [" .. r2.unit .. "] " .. r2.curve, "1 10 [] lin")
  M.set("Acq TAN2", { controls = { { param = 10, type = "knob" } }, aliases = {}, ranges = { [10] = f } })
  M.save(); M.reload()
  local rr = M.get_range("Acq TAN2", 10)
  check("range: kept", rr and (rr.lo .. " " .. rr.hi .. " " .. rr.unit .. " " .. rr.curve), "20 20000 Hz log")
  local cp = M.copy(M.get("Acq TAN2")); cp.ranges[10].lo = 30
  check("range: copy is its own", M.get_range("Acq TAN2", 10).lo, 20)
  M.remove("Acq TAN2"); M.save(); M.reload()
end

-- ---------------------------------------------------------------------
-- virtual controls (Virt<n>) and layout switching (Switch<n>)
-- ---------------------------------------------------------------------
do
  local St = require "TS_CV_State"
  local PROJ = {}
  reaper.GetProjExtState = function(_, ns, k) return 1, PROJ[ns .. k] or "" end
  reaper.SetProjExtState = function(_, ns, k, val) PROJ[ns .. k] = val end
  St.clear_cache()
  check("virt: clean name", M.clean_vname(" View|1 ; x "), "View 1 x")
  check("virt: clean empty", M.clean_vname(" | "), nil)
  local sel = { param = -1, type = "combo", label = "View", buttons = "across", nbtn = 3,
                virtual = { start = 0, choices = { "Main", "Sidechain", "Advanced" } } }
  local btn = { param = -1, type = "toggle", label = "More", virtual = { start = 1, choices = {} } }
  local kn = { param = -1, type = "knob", label = "", virtual = { start = 0.4, choices = {} } }
  local shown = { param = 3, type = "knob", show = { param = -1, vname = "View", op = "is", norm = 1, tol = 0.25 } }
  local more = { param = 4, type = "knob", show = { param = -1, vname = "More", op = "is", norm = 1, tol = 0.499 } }
  M.set("Comp X", { controls = { sel, btn, kn, shown, more, { param = 0, type = "knob" } } })
  M.save(); M.reload()
  local l = M.get("Comp X")
  check("virt: kept", l.controls[1].virtual and table.concat(l.controls[1].virtual.choices, ","), "Main,Sidechain,Advanced")
  check("virt: is virtual", M.is_virtual(l.controls[1]) and M.is_virtual(l.controls[2]) and not M.is_virtual(l.controls[6]), true)
  check("virt: chips one each", l.controls[1].nbtn, 3)
  check("virt: button start", l.controls[2].virtual.start, 1)
  check("virt: knob's name", M.vname_of(l.controls[3]), "Amount")
  check("virt: button names", table.concat(M.vchoices(l.controls[2]), "/"), "Off/On")
  check("virt: selector values", M.vnorm(l.controls[1], 2) .. " " .. M.vindex(l.controls[1], 0.9) .. " " .. M.vtext(l.controls[1], 0.5), "0.5 3 Sidechain")
  check("virt: knob text", M.vtext(l.controls[3], 0.42), "42 %")
  check("virt: show rule kept", l.controls[4].show.vname .. " " .. l.controls[4].show.param, "View -1")
  check("virt: show line", M.show_line(l.controls[4].show):sub(1, 7), "v:View|")
  -- shown or not by its setting: the start, then what the instance has
  local getv = function(p, vn) if vn then return St.vvalue("{V}", vn, "Comp X", l.controls) end return 0 end
  local _, hid = M.visible(l.controls, getv)
  check("virt: at start, sidechain knob hidden, more shown", tostring(hid[4]) .. " " .. tostring(hid[5]), "true nil")
  St.vset("{V}", "View", 1); St.vset("{V}", "More", 0)
  _, hid = M.visible(l.controls, getv)
  check("virt: set, shown and hidden", tostring(hid[4]) .. " " .. tostring(hid[5]), "nil true")
  check("virt: kept per instance", St.vget("{W}", "View"), nil)
  check("virt: in the project", PROJ["TS_ChannelViewvirt:{V}:View"], "1")
  St.clear_cache()
  check("virt: reread", St.vget("{V}", "More"), 0)
  -- copies keep them; the start found from another layout
  local cp = M.copy(l)
  check("virt: copy", cp.controls[1].virtual.choices[3] .. " " .. cp.controls[4].show.vname, "Advanced View")
  cp.controls[1].virtual.choices[1] = "X"
  check("virt: copy is its own", l.controls[1].virtual.choices[1], "Main")
  check("virt: start from the plugin's layout", M.vstart("Comp X", "Amount", {}), 0.4)
  check("virt: start unknown", M.vstart("Comp X", "Nope", {}), 0)

  -- actions per setting (VAct<n>): kept, copied, run for the setting picked
  do
    local sel2 = { param = -1, type = "combo", label = "Mode",
                   virtual = { start = 0, choices = { "A", "B", "C" }, actions = { [1] = "40001", [3] = "_RS9f" } } }
    local btn2 = { param = -1, type = "toggle", label = "Go", virtual = { start = 0, choices = {}, actions = { [2] = "40044" } } }
    local kn2 = { param = -1, type = "knob", label = "K", virtual = { start = 0, choices = {}, actions = { "40001" } } }
    M.set("Act X", { controls = { sel2, btn2, kn2 } })
    M.save(); M.reload()
    local la = M.get("Act X")
    local a1 = la.controls[1].virtual.actions
    check("vact: kept", a1 and (tostring(a1[1]) .. " " .. tostring(a1[2]) .. " " .. tostring(a1[3])), "40001 nil _RS9f")
    check("vact: button", la.controls[2].virtual.actions and la.controls[2].virtual.actions[2], "40044")
    check("vact: a knob has none", la.controls[3].virtual.actions, nil)
    check("vact: line", M.vact_line(a1, 3), "40001;;_RS9f")
    check("vact: trailing gaps dropped", M.vact_line({ "1" }, 3), "1")
    check("vact: none", M.vact_line({}, 3), nil)
    check("vact: by value", tostring(M.vaction(la.controls[1], 0)) .. " " .. tostring(M.vaction(la.controls[1], 0.5)) .. " " .. tostring(M.vaction(la.controls[1], 1)), "40001 nil _RS9f")
    check("vact: button on", M.vaction(la.controls[2], 1), "40044")
    local ran = {}
    reaper.Main_OnCommand = function(id) ran[#ran + 1] = id end
    reaper.NamedCommandLookup = function(n) return n == "_RS9f" and 55123 or 0 end
    M.run_vaction(la.controls[1], 0); M.run_vaction(la.controls[1], 0.5); M.run_vaction(la.controls[1], 1)
    check("vact: ran", table.concat(ran, ","), "40001,55123")
    local cpa = M.copy(la)
    cpa.controls[1].virtual.actions[1] = "1"
    check("vact: copy is its own", la.controls[1].virtual.actions[1], "40001")
    reaper.Main_OnCommand, reaper.NamedCommandLookup = nil, nil
  end

  -- layout switching: rules on the plugin's own layout
  M.set("Comp X :: Side", { controls = { { param = 7, type = "knob" } } })
  M.set("Comp X :: Heavy", { controls = { { param = 8, type = "knob" } } })
  local rules = { { param = 2, op = "is", norm = 1, tol = 0.25, layout = "Side" },
                  { param = 0, op = "above", norm = 0.7, tol = 0.005, layout = "Heavy" },
                  { param = -1, vname = "View", op = "is", norm = 0, tol = 0.25, layout = nil } }
  check("switch: set", M.set_switch_rules("Comp X", rules), true)
  M.reload()
  local sr = M.switch_rules("Comp X")
  check("switch: kept", sr and (#sr .. " " .. sr[1].layout .. " " .. sr[2].op .. " " .. tostring(sr[3].layout) .. " " .. sr[3].vname), "3 Side above nil View")
  check("switch: a variant has none", M.get("Comp X :: Side").switch, nil)
  -- saving the layout over keeps them (the editor's copy doesn't carry them)
  local ed = M.copy(M.get("Comp X")); ed.switch = nil
  M.set("Comp X", ed); M.save(); M.reload()
  check("switch: kept over a save", #(M.switch_rules("Comp X") or {}), 3)
  -- a copy made into a variant drops them
  local k2 = M.new_variant("Comp X", "Copy", M.get("Comp X"), false)
  check("switch: not in a new variant", M.get(k2).switch, nil)
  M.remove(k2)

  local PV = { [0] = 0.2, [2] = 0 }
  local rgp = reaper.TrackFX_GetParamNormalized
  reaper.TrackFX_GetParamNormalized = function(_, _, p) return PV[p] or 0 end
  local nm = "VST3: Comp X (Someone)"
  St.vset("{S}", "View", 1)
  check("switch: none matches, own pick", St.layout_key(nm, "{S}", {}, 0), "Comp X")
  check("switch: no rule in charge", St.switch_rule("{S}"), nil)
  PV[2] = 1
  check("switch: first match", St.layout_key(nm, "{S}", {}, 0), "Comp X :: Side")
  check("switch: which rule", St.switch_rule("{S}"), 1)
  PV[0] = 0.9
  check("switch: first wins", St.layout_key(nm, "{S}", {}, 0), "Comp X :: Side")
  PV[2] = 0
  check("switch: knob above", St.layout_key(nm, "{S}", {}, 0), "Comp X :: Heavy")
  PV[0] = 0.69
  check("switch: slack holds it", St.layout_key(nm, "{S}", {}, 0), "Comp X :: Heavy")
  PV[0] = 0.67
  check("switch: past the slack", St.layout_key(nm, "{S}", {}, 0), "Comp X")
  PV[0] = 0.69
  check("switch: no slack coming up", St.layout_key(nm, "{S}", {}, 0), "Comp X")
  St.vset("{S}", "View", 0)
  check("switch: by a virtual control, to the plugin's own", St.layout_key(nm, "{S}", {}, 0) .. " " .. tostring(St.switch_rule("{S}")), "Comp X 3")
  St.set_variant("{S}", "Heavy")
  check("switch: rule beats the pick", St.layout_key(nm, "{S}", {}, 0), "Comp X")
  St.vset("{S}", "View", 1)
  check("switch: the pick when none match", St.layout_key(nm, "{S}", {}, 0), "Comp X :: Heavy")
  check("switch: without the track, no rules", St.layout_key(nm, "{S}"), "Comp X :: Heavy")
  -- a rule to a layout that's gone is passed over
  M.remove("Comp X :: Side"); PV[2] = 1
  check("switch: gone layout skipped", St.layout_key(nm, "{S}", {}, 0), "Comp X :: Heavy")
  reaper.TrackFX_GetParamNormalized = rgp
  check("switch: in words", M.rule_text({ param = 2, op = "is", norm = 1 }, function() return "Mode" end,
    function(_, n) return n >= 0.5 and "Dual" or "Mono" end), "Mode is Dual")
  check("switch: in words, virtual", M.rule_text({ param = -1, vname = "View", op = "is", norm = 0.5 }, nil, nil,
    function() return sel end), "\u{25C6} View is Sidechain")
  check("switch: in words, between", M.rule_text({ param = 0, op = "between", norm = 0.2, norm2 = 0.6 }), "P0 is between 20 % and 60 %")
  check("switch: cleared", M.set_switch_rules("Comp X", nil) and M.switch_rules("Comp X"), nil)
  M.remove("Comp X"); M.remove("Comp X :: Heavy"); M.save(); M.reload()
  reaper.GetProjExtState, reaper.SetProjExtState = nil, nil
  St.clear_cache()
end

-- ---------------------------------------------------------------------
-- Shared state: the window and the web bridge each have their own copy
-- of TS_CV_State; a change one makes reaches the other within a second
do
  local St = require "TS_CV_State"
  local PROJ, T = {}, 100
  local real_t = reaper.time_precise
  reaper.time_precise = function() return T end
  reaper.GetProjExtState = function(_, ns, k) return 1, PROJ[ns .. k] or "" end
  reaper.SetProjExtState = function(_, ns, k, v) PROJ[ns .. k] = v end
  St.clear_cache()
  check("shared: trace closed at first", St.is_gr_open("{G}"), false)
  PROJ["TS_ChannelViewgrview:{G}"] = "1"            -- the other script opens it
  check("shared: cached within the second", St.is_gr_open("{G}"), false)
  T = T + 1.1
  check("shared: open seen after a second", St.is_gr_open("{G}"), true)
  St.set_gr_open("{G}", false)
  check("shared: own write at once", St.is_gr_open("{G}"), false)
  check("shared: own write saved", PROJ["TS_ChannelViewgrview:{G}"], "")
  check("shared: no variant at first", St.variant("{G}"), nil)
  PROJ["TS_ChannelViewvariant:{G}"] = "Strings"     -- switched in the window
  T = T + 1.1
  check("shared: variant seen after a second", St.variant("{G}"), "Strings")
  reaper.time_precise = real_t
  reaper.GetProjExtState, reaper.SetProjExtState = nil, nil
  St.clear_cache()
end

-- removing an envelope: its block out of the track chunk
do
  local ENr = require("TS_CV_Envelopes")
  local chunk = [[<TRACK
NAME Vox
<VOLENV2
EGUID {V}
ACT 1 -1
PT 0 1 0
>
<FXCHAIN
SHOW 0
BYPASS 0 0 0
<JS "TS_ChannelView/TS_CV_Modulators.jsfx" ""
0 0 0
>
FLOATPOS 0 0 0 0
FXID {MOD}
<PARMENV 0:0 0 1 0.5
EGUID {E0}
ACT 1 -1
VIS 1 1 1
PT 0 0.4351 0
>
<PARMENV 1 0 1 0.5
EGUID {E1}
ACT 1 -1
PT 0 0 0
>
WAK 0 0
BYPASS 0 0 0
<VST "VST3: X" x 0 ""
abc
>
FXID {X}
<PARMENV 0 0 1 0.5
EGUID {EX}
>
WAK 0 0
>
>]]
  local a = ENr.chunk_without(chunk, "{MOD}", 1, nil)
  check("env remove: the param's block gone", a:find("{E1}") == nil and a:find("{E0}") ~= nil and a:find("{EX}") ~= nil, true)
  local b = ENr.chunk_without(chunk, "{MOD}", 0, nil)
  check("env remove: 0:0 form", b:find("{E0}") == nil and b:find("{E1}") ~= nil, true)
  local c = ENr.chunk_without(chunk, "{X}", 0, nil)
  check("env remove: the other plugin's", c:find("{EX}") == nil and c:find("{E0}") ~= nil, true)
  local d = ENr.chunk_without(chunk, nil, nil, "<VOLENV2")
  check("env remove: a track envelope", d:find("{V}") == nil and d:find("<FXCHAIN") ~= nil, true)
  check("env remove: not there", ENr.chunk_without(chunk, "{MOD}", 5, nil), nil)
end

-- ---------------------------------------------------------------------
-- mapped canvases: units, band models, fitting, learned tables, layouts
-- ---------------------------------------------------------------------
do
  local UN = require("TS_CV_Units")
  local function pv(t) local v, u = UN.parse(t); return tostring(v) .. "|" .. tostring(u) end
  check("units: kHz", pv("1.20 kHz"), "1200.0|hz")
  check("units: 1k2", pv("1k2"), "1200.0|hz")
  check("units: dB", pv("-3.5 dB"), "-3.5|db")
  check("units: ratio", pv("4.0:1"), "4.0|ratio")
  check("units: ratio as written (an expander's)", pv("1:4"), "0.25|ratio")
  check("units: ratio under 1:1 (an expander)", pv("0.50:1"), "0.5|ratio")
  check("units: 1:1", pv("1:1"), "1.0|ratio")
  check("units: limit", pv("Limit"), "inf|ratio")
  check("units: -inf dB", pv("-inf dB"), "-inf|db")
  check("units: seconds", pv("0.35 s"), "350.0|ms")
  check("units: percent", pv("50 %"), "50|pct")
  check("units: thousands comma", pv("1,200 Hz"), "1200|hz")
  check("units: decimal comma", pv("1,5 dB"), "1.5|db")
  check("units: no number", UN.parse("Off"), nil)
  local steps = { "Off", "50", "80", "160", "300" }
  local fmt = function(n) return steps[math.min(5, math.floor(n * 5) + 1)] end
  local pos = UN.positions(fmt)
  check("units: switch positions", pos and #pos, 5)
  check("units: first position at 0", pos and pos[1].norm, 0)
  check("units: last position at 1", pos and pos[5].norm, 1)
  check("units: a knob isn't a switch", UN.positions(function(n) return ("%.3f"):format(n) end), nil)
  local f2 = function(n) return ("%.2f dB"):format(-20 + 40 * n * n) end
  local n0 = UN.find_norm(f2, 0)
  checkf("units: find_norm lands on 0 dB", function() return math.abs(n0 - math.sqrt(0.5)) < 0.002 end)
  check("units: find_norm clamps", (UN.find_norm(f2, 99)), 1)
  checkf("units: interp log", function() return math.abs(UN.interp({ { 0, 20 }, { 1, 20000 } }, 0.5, true) - 632.46) < 0.1 end)
  checkf("units: invert log", function() return math.abs(UN.invert({ { 0, 20 }, { 1, 20000 } }, 632.46, true) - 0.5) < 0.001 end)

  local ME = require("TS_CV_MapEQ")
  local fr = ME.centres()
  check("mapeq: 120 bands", #fr, 120)
  local function synth(b) local D = {} for i, f in ipairs(fr) do D[i] = ME.band_db(b, f) end return D end
  do
    -- a dynamics switch on a band that isn't dynamic yet (Pro-Q: every
    -- band's dynamics "Enabled", its range 0 dB): makes it dynamic
    local real = reaper
    local pv = { [9] = 0.5, [10] = 1 }
    local function txt(p, n)
      if p == 9 then return ("%.2f dB"):format((n * 2 - 1) * 30) end
      return n >= 0.5 and "Dynamics Enabled" or "Dynamics Disabled"
    end
    reaper = setmetatable({
      TrackFX_GetParamNormalized = function(_, _, p) return pv[p] or 0 end,
      TrackFX_SetParamNormalized = function(_, _, p, v) pv[p] = v end,
      TrackFX_GetFormattedParamValue = function(_, _, p) return true, txt(p, pv[p] or 0) end,
      TrackFX_FormatParamValueNormalized = function(_, _, p, n) return true, txt(p, n) end,
      TrackFX_GetFXGUID = function() return "{DYNTEST}" end,
    }, { __index = real })
    local b = { dyn = { range = 9, on = 10, rev = {} } }
    check("dyn: no range, not made dynamic", ME.read_dyn("tr", 0, b).made, false)
    ME.toggle_dyn("tr", 0, b)
    local dy = ME.read_dyn("tr", 0, b)
    check("dyn: switched on, given a range", dy.made and dy.on and math.abs(dy.range - ME.DYN_START) < 0.5, true)
    ME.toggle_dyn("tr", 0, b)
    dy = ME.read_dyn("tr", 0, b)
    check("dyn: then off, its range kept", (not dy.on) and dy.made, true)
    reaper = real
  end
  check("mapeq: a frequency table, rising", ME.f_table_ok({ { 0, 20 }, { 0.5, 600 }, { 1, 20000 } }), true)
  check("mapeq: a frequency table, falling", ME.f_table_ok({ { 0, 20000 }, { 1, 20 } }), true)
  check("mapeq: one point, not readable", ME.f_table_ok({ { 0, 30000 } }), false)
  check("mapeq: a cut measured at its far end, not readable",
        ME.f_table_ok({ { 0, 3950 }, { 0.25, 574.5 }, { 0.5, 574.5 }, { 0.75, 4584 }, { 1, 22500 } }), false)
  checkf("mapeq: bell peak = gain", function() return math.abs(ME.band_db({ type = "bell", f = 1000, g = 6, q = 1 }, 1000) - 6) < 0.01 end)
  checkf("mapeq: low shelf full gain far below", function() return math.abs(ME.band_db({ type = "ls", f = 1000, g = 6, q = 0.7 }, 20) - 6) < 0.1 end)
  checkf("mapeq: 12 dB/oct cut", function()
    local b = { type = "hp", f = 1000, order = 2, q = 0.7071 }
    return math.abs(ME.band_db(b, 125) - ME.band_db(b, 250) + 12) < 0.3 end)
  local cases = {
    { { type = "bell", f = 1600, g = -3.5, q = 0.9 }, "gain" },
    { { type = "ls", f = 110, g = 6, q = 0.7 }, "gain" },
    { { type = "hs", f = 12000, g = 8, q = 0.7 }, "gain" },
    { { type = "hp", f = 80, order = 3, q = 1 }, "cut" },
    { { type = "lp", f = 8000, order = 1 }, "cut" },
  }
  for _, c in ipairs(cases) do
    local b = c[1]
    local r = ME.fit(fr, synth(b), c[2])
    check(("mapeq: fits %s %g"):format(b.type, b.f), r and r.type, b.type)
    checkf(("mapeq: %s %g frequency"):format(b.type, b.f), function() return r and math.abs(math.log(r.f / b.f)) < 0.05 end)
    if b.order then check(("mapeq: %s order"):format(b.type), r and r.order, b.order) end
  end
  check("mapeq: flat is no fit", ME.fit(fr, synth({ type = "bell", f = 1000, g = 0, q = 1 }), "gain"), nil)
  -- the other shapes (Pro-Q, Kirchhoff): models, names, slopes
  checkf("mapeq: notch deep at its centre", function() return ME.band_db({ type = "notch", f = 1000, q = 2 }, 1000) < -60 end)
  checkf("mapeq: notch flat far off", function() return math.abs(ME.band_db({ type = "notch", f = 1000, q = 2 }, 20)) < 0.1 end)
  checkf("mapeq: band pass 0 dB at centre", function() return math.abs(ME.band_db({ type = "bp", f = 1000, q = 1 }, 1000)) < 0.01 end)
  checkf("mapeq: band pass falls away", function() return ME.band_db({ type = "bp", f = 1000, q = 1 }, 100) < -15 end)
  checkf("mapeq: tilt half each side", function()
    local b = { type = "tilt", f = 1000, g = 12, q = 0.7071 }
    return math.abs(ME.band_db(b, 20) + 6) < 0.3 and math.abs(ME.band_db(b, 20000) - 6) < 0.3 end)
  checkf("mapeq: flat tilt is a line", function()
    local b = { type = "flattilt", f = 632, g = 10 }
    return math.abs(ME.band_db(b, 632)) < 1e-6 and math.abs(ME.band_db(b, 1264) - 1) < 1e-6 end)
  checkf("mapeq: flat top plateau", function() return math.abs(ME.band_db({ type = "flattop", f = 1000, g = 6, q = 0.5 }, 1000) - 6) < 0.6 end)
  checkf("mapeq: 96 dB/oct cut", function()
    local b = { type = "hp", f = 1000, order = 16, q = 0.7071 }
    return math.abs(ME.band_db(b, 125) - ME.band_db(b, 250) + 96) < 2 end)
  checkf("mapeq: all pass is flat", function() return ME.band_db({ type = "ap", f = 1000, q = 1 }, 1000) == 0 end)
  check("mapeq: name notch", (ME.type_of_name("Notch")), "notch")
  check("mapeq: name band pass", (ME.type_of_name("Band Pass")), "bp")
  check("mapeq: name tilt shelf", (ME.type_of_name("Tilt Shelf")), "tilt")
  check("mapeq: name flat tilt", (ME.type_of_name("Flat Tilt")), "flattilt")
  check("mapeq: name low cut", (ME.type_of_name("Low Cut")), "hp")
  check("mapeq: name high cut", (ME.type_of_name("High Cut")), "lp")
  check("mapeq: name all pass", (ME.type_of_name("All Pass")), "ap")
  check("mapeq: name bell", (ME.type_of_name("Bell")), "bell")
  check("mapeq: name high shelf", (ME.type_of_name("High Shelf")), "hs")
  check("mapeq: name brickwall", select(2, ME.type_of_name("Brickwall Low Pass")), ME.BRICK)
  check("mapeq: name unknown", (ME.type_of_name("Vintage")), nil)
  -- Kirchhoff-EQ's own names
  check("mapeq: kirchhoff console bell", (ME.type_of_name("E LMF")), "bell")
  check("mapeq: kirchhoff console cut", (ME.type_of_name("BritN HP")), "hp")
  check("mapeq: kirchhoff wall", select(2, ME.type_of_name("Wall LP")), ME.BRICK)
  check("mapeq: kirchhoff allpass", (ME.type_of_name("Allpass H")), "ap")
  check("mapeq: kirchhoff tone", (ME.type_of_name("Tone Low")), "ls")
  check("mapeq: kirchhoff valve left to measuring", (ME.type_of_name("VT Boost")), nil)
  check("mapeq: kirchhoff slope", ME.order_of_text("12.0dB/oct %"), 2)
  check("mapeq: slope 24", ME.order_of_text("24 dB/oct"), 4)
  check("mapeq: slope 96", ME.order_of_text("96 dB/oct"), 16)
  check("mapeq: slope brick", ME.order_of_text("Brickwall"), ME.BRICK)
  check("mapeq: slope none", ME.order_of_text("Auto"), nil)
  local fcases = {
    { { type = "notch", f = 2500, q = 3 }, "gain", true },
    { { type = "bp", f = 700, q = 1.2 }, "gain", true },
    { { type = "tilt", f = 1200, g = 8, q = 0.7071 }, "gain", true },
    { { type = "hp", f = 120, order = 2, q = 0.7071 }, "gain", false },
  }
  for _, c in ipairs(fcases) do
    local b = c[1]
    local r = ME.fit(fr, synth(b), c[2], c[3] and { type = b.type } or nil)
    check(("mapeq: fits %s by %s"):format(b.type, c[3] and "name" or "shape"), r and r.type, b.type)
    checkf(("mapeq: %s frequency"):format(b.type), function() return r and math.abs(math.log(r.f / b.f)) < 0.08 end)
  end
  -- summarise: three frequencies x two gains of a proportional-Q bell
  local samples = {}
  for _, fn in ipairs({ 0, 0.5, 1 }) do
    for _, gn in ipairs({ 1, 0 }) do
      local f = 200 * 10 ^ fn
      local g = (gn == 1) and 12 or -12
      local q = (gn == 1) and 1.5 or 0.8
      samples[#samples + 1] = { s = 1, fn = fn, gn = gn, fit = { type = "bell", f = f, g = g, q = q } }
    end
  end
  local L = ME.summarise(samples, { kind = "gain", Z = 0.5 })
  check("mapeq: summary type", L and L.shapes[1].type, "bell")
  check("mapeq: summary F points", L and #L.shapes[1].F, 3)
  check("mapeq: summary G has flat", L and #L.shapes[1].G, 3)
  check("mapeq: Q against gain", L and #L.shapes[1].Q, 2)
  local L2 = ME.decode(ME.encode(L))
  check("mapeq: round trip type", L2 and L2.shapes[1].type, "bell")
  checkf("mapeq: round trip F", function() return L2 and math.abs(L2.shapes[1].F[2][2] - L.shapes[1].F[2][2]) < 1 end)
  check("mapeq: round trip Z", L2 and L2.Z, 0.5)
  local Ld = ME.summarise({ { s = 1, fit = { type = "bell", f = 1100, g = 12, q = 1.4 }, rep_f = 1000, rep_q = 0.7 } },
    { direct = true, has_freq = true })
  check("mapeq: direct keeps type", Ld and Ld.shapes[1].type, "bell")
  checkf("mapeq: direct Q correction", function() return Ld and math.abs(Ld.shapes[1].K[2] - 2) < 0.001 end)
  local Ld2 = ME.decode(ME.encode(Ld))
  check("mapeq: direct round trip", Ld2 and Ld2.D, true)
  -- a measurement that's noise, not the band (Pro-Q 4 learned out of line)
  do
    local fr = ME.centres()
    local seed = 7
    local function meas(noisy, g)
      local D = {}
      for i, f in ipairs(fr) do
        seed = (seed * 1103515245 + 12345) % 2147483648
        D[i] = ME.band_db({ type = "bell", f = 1000, g = g, q = 1 }, f) + (noisy and (seed / 2147483648 - 0.5) * 6 or 0)
          + 0.8 * math.exp(-((math.log(f / 4000) / 0.7) ^ 2))      -- a gentle bump the model hasn't
      end
      return { s = 1, gn = (g > 0) and 1 or 0, freqs = fr, D = D, rep_f = 1000, rep_g = g, rep_q = 1,
               fit = { type = "bell", f = noisy and 194 or 1000, g = noisy and g * 0.42 or g, q = noisy and 12 or 1 } }
    end
    local clean = ME.summarise({ meas(false, 12), meas(false, -12) }, { direct = true, has_freq = true })
    local ce = clean and clean.shapes[1]
    checkf("noise: a real shape is smooth", function() return ce and ce.C and ME.noise(ce.C) < 0.3 end)
    check("noise: a real shape is kept", ce and ce.C ~= nil and not clean.noisy, true)
    local rough = ME.summarise({ meas(true, 12), meas(true, -12) }, { direct = true, has_freq = true })
    local re = rough and rough.shapes[1]
    check("noise: read from the plugin as it is", re and table.concat(re.K, ","), "1,1,1")
    check("noise: no measured shape", re and tostring(re.C), "nil")
    check("noise: said so", rough and rough.noisy, 1)
    check("noise: still a bell", re and re.type, "bell")
    local rs = {}
    for _, gn in ipairs({ 1, 0 }) do
      local m = meas(true, gn == 1 and 12 or -12)
      m.fn = 0.5; m.rep_f, m.rep_g, m.rep_q = nil, nil, nil
      rs[#rs + 1] = m
    end
    local Lt, why = ME.summarise(rs, { kind = "gain", Z = 0.5 })
    check("noise: a learned table isn't kept", tostring(Lt), "nil")
    checkf("noise: and why", function() return (why or ""):find("noise", 1, true) ~= nil end)
  end
  local g = ME.guess({ "Low Gain", "Low Freq", "Mid Gain", "Mid Freq", "High Gain", "HPF Freq", "Input", "EQ In" })
  check("mapeq: guess bands", #g, 4)
  check("mapeq: guess low cut first", g[1] and g[1].name, "Low cut")
  check("mapeq: guess low gain", g[2] and g[2].gain, 0)
  check("mapeq: guess mid freq", g[3] and g[3].freq, 3)
  check("mapeq: guess high has no freq", g[4] and g[4].freq, nil)

  -- layouts: a canvas survives the library
  local key = "TestEQ73 :: EQ"
  M.set(key, { controls = { { param = 6, type = "knob", label = "" } }, aliases = {},
               canvas = { kind = "eq", all_on = 7, bands = {
                 { name = "Low", freq = 1, gain = 0, learn = ME.encode(L), learn_sig = "1,0,-,-,-" },
                 { name = "High", gain = 4 } } } })
  M.save(); M.reload()
  local back = M.get(key)
  check("canvas: kind", back and back.canvas and back.canvas.kind, "eq")
  check("canvas: all on", back and back.canvas.all_on, 7)
  check("canvas: bands", back and #back.canvas.bands, 2)
  check("canvas: band freq", back and back.canvas.bands[1].freq, 1)
  check("canvas: band no freq", back and back.canvas.bands[2].freq, nil)
  check("canvas: learned for its mapping", back and M.band_learned(back.canvas.bands[1]), true)
  check("canvas: not learned", back and M.band_learned(back.canvas.bands[2]), false)
  check("canvas: todo", back and M.canvas_todo(back.canvas).learned, 1)
  back.canvas.bands[1].q = 9
  check("canvas: mapping changed: learn again", M.band_learned(back.canvas.bands[1]), false)
  check("canvas: copy keeps it", M.copy(back).canvas.bands[2].name, "High")
  M.set("TestComp :: Comp", { controls = {}, aliases = {}, canvas = { kind = "comp",
    roles = { Threshold = 2, Ratio = 3, Hold = 9 }, rev = { Threshold = true } } })
  M.save(); M.reload()
  local cb = M.get("TestComp :: Comp")
  check("canvas: comp roles", cb and cb.canvas.roles.Hold, 9)
  check("canvas: comp reversed", cb and cb.canvas.rev.Threshold, true)
  check("canvas: comp not reversed", cb and cb.canvas.rev.Ratio, nil)
  check("canvas: a canvas layout is a layout", (function()
    for _, k in ipairs(M.keys()) do if k == "TestComp :: Comp" then return true end end
    return false end)(), true)
  -- a plugin's default layout
  check("default layout: none set", M.default_variant("TestComp"), nil)
  M.set_default_variant("TestComp", "Comp"); M.save(); M.reload()
  check("default layout: set", M.default_variant("TestComp"), "Comp")
  check("default layout: not a layout itself", (function()
    for _, k in ipairs(M.keys()) do if k == M.DEFAULTS_SECT then return true end end
    return false end)(), false)
  check("default layout: an unknown one is ignored", (function()
    M.set_default_variant("TestComp", "Gone"); return M.default_variant("TestComp") end)(), nil)
  M.set_default_variant("TestComp", nil)
  M.remove(key); M.remove("TestComp :: Comp"); M.save()

  -- a new canvas layout keeps the controls its canvas doesn't take
  local src = { controls = {
      { param = -1, type = "divider" }, { param = 2, type = "knob", style = "skirted" },
      { param = 4, type = "stepped" }, { param = -1, type = "divider" },
      { param = 7, type = "knob", style = "skirted", cap = "blue" }, { param = -1, type = "blank" },
      { param = 3, type = "knob" }, { param = 5, type = "dual", param2 = 6 },
      { param = -1, type = "half_gap" }, { param = -1, type = "divider" }, { param = 8, type = "knob" } },
    aliases = {}, plate = "navy", lock = 5 }
  local cl = M.copy(src)
  cl.canvas = { kind = "comp", roles = { Threshold = 2, Attack = 4, Release = 6, Makeup = 3, Mix = 8 }, rev = {} }
  local _, dropped = M.drop_placed(cl)
  local types = {}
  for _, c in ipairs(cl.controls) do types[#types + 1] = c.type .. (c.param >= 0 and c.param or "") end
  check("canvas: placed controls leave", table.concat(types, " "), "knob7")
  check("canvas: kept control keeps its look", cl.controls[1].cap, "blue")
  check("canvas: the faceplate comes", cl.plate, "navy")
  check("canvas: something taken", dropped, true)
  check("canvas: lock goes", cl.lock, nil)
  local cl2 = M.copy(src); cl2.canvas = { kind = "comp", roles = { Ratio = 11 } }
  local _, d2 = M.drop_placed(cl2)
  check("canvas: nothing taken, nothing changes", #cl2.controls .. " " .. tostring(d2) .. " " .. cl2.lock, "11 false 5")
  local cl3 = M.copy(src)
  cl3.canvas = { kind = "eq", all_on = 8, bands = { { name = "Lo", freq = 4, gain = 5 } } }
  M.drop_placed(cl3)
  types = {}
  for _, c in ipairs(cl3.controls) do types[#types + 1] = c.type .. (c.param >= 0 and c.param or "") end
  check("canvas: EQ bands' controls leave (a pair with either half)",
    table.concat(types, " "), "knob2 divider knob7 blank knob3")
end

-- gate and limiter layouts: kept, and guessed from names
do
  M.set("TestGate :: Gate", { controls = {}, aliases = {}, canvas = { kind = "gate",
    roles = { Threshold = 0, Hysteresis = 3, Range = 4, Release = 6 }, rev = { Release = true } } })
  M.set("TestLim :: Limiter", { controls = {}, aliases = {}, canvas = { kind = "limit",
    roles = { Input = 0, Ceiling = 1, Release = 2 }, rev = {} } })
  M.save(); M.reload()
  local gl, ll = M.get("TestGate :: Gate"), M.get("TestLim :: Limiter")
  check("gate layout: its kind", gl and gl.canvas.kind, "gate")
  check("gate layout: its roles", gl and (gl.canvas.roles.Hysteresis .. "," .. gl.canvas.roles.Range), "3,4")
  check("gate layout: reversed kept", gl and gl.canvas.rev.Release, true)
  check("limiter layout: its kind", ll and ll.canvas.kind, "limit")
  check("limiter layout: its ceiling", ll and ll.canvas.roles.Ceiling, 1)
  check("a comp role isn't a gate's", (function()
    M.set("TestGate2 :: Gate", { controls = {}, aliases = {}, canvas = { kind = "gate", roles = { Makeup = 2, Range = 1 } } })
    M.save(); M.reload(); local l = M.get("TestGate2 :: Gate"); return l.canvas.roles.Makeup end)(), nil)
  M.remove("TestGate :: Gate"); M.remove("TestLim :: Limiter"); M.remove("TestGate2 :: Gate"); M.save()
  check("canvas names", M.CANVAS_NAMES.gate .. "/" .. M.CANVAS_NAMES.limit, "Gate/Limiter")
  local CS = require("TS_CV_CanvasSetup")
  local g = CS.guess({ "Threshold", "Hysteresis", "Range", "Attack", "Hold", "Release", "Sidechain HPF" }, "gate")
  check("guess gate: kind", g.kind, "gate")
  check("guess gate: roles", ("%s %s %s %s %s %s"):format(g.roles.Threshold, g.roles.Hysteresis, g.roles.Range,
    g.roles.Attack, g.roles.Hold, g.roles.Release), "0 1 2 3 4 5")
  local g2 = CS.guess({ "Open", "Close", "Hysteresis", "Depth" }, "gate")
  check("guess gate: close wins over hysteresis", tostring(g2.roles.Close) .. " " .. tostring(g2.roles.Hysteresis), "1 nil")
  local l = CS.guess({ "Gain", "Output Gain", "Release", "Lookahead" }, "limit")
  check("guess limiter: gain is the input", l.roles.Input, 0)
  check("guess limiter: output gain is the ceiling", l.roles.Ceiling, 1)
  local l2 = CS.guess({ "Threshold", "Out Ceiling", "Release", "Input" }, "limit")
  check("guess limiter: threshold, so no input", tostring(l2.roles.Threshold) .. " " .. tostring(l2.roles.Input) .. " " .. tostring(l2.roles.Ceiling), "0 nil 1")
end

-- note values, and the other role canvases
do
  local UN = require("TS_CV_Units")
  check("note: 1/8", UN.note_beats("1/8"), 0.5)
  check("note: dotted", UN.note_beats("1/8 D"), 0.75)
  check("note: dotted with a dot", UN.note_beats("1/16."), 0.375)
  checkf("note: triplet", function() return math.abs(UN.note_beats("1/4T") - 2 / 3) < 1e-9 end)
  check("note: bars", UN.note_beats("2 bars"), 8)
  check("note: not one", UN.note_beats("350 ms"), nil)
  check("time: a note at 120", UN.time_ms("1/8 D", 120), 375.0)
  check("time: seconds", UN.time_ms("1.2 s"), 1200.0)
  check("time: neither", UN.time_ms("Hall"), nil)
  local CS = require("TS_CV_CanvasSetup")
  local function roles_of(g, list)
    local t = {}
    for _, r in ipairs(list) do t[#t + 1] = tostring(g.roles[r]) end
    return table.concat(t, " ")
  end
  check("guess de-esser", roles_of(CS.guess({ "Low Freq", "Frequency", "Threshold", "Range", "Listen" }, "deess"),
    { "Frequency", "Low", "Threshold", "Range" }), "1 0 2 3")
  check("guess delay", roles_of(CS.guess({ "Delay Time", "Note", "Sync", "Feedback", "Ping Pong", "Mix" }, "delay"),
    { "Time", "Note", "Sync", "Feedback", "PingPong", "Mix" }), "0 1 2 3 4 5")
  -- a stereo delay: the right's own controls, its stereo mode by its likeliest word
  check("guess stereo delay", roles_of(CS.guess({ "Mode", "Delay Sync", "Time L", "Time R", "Feedback L", "Feedback R",
      "Cross Feedback", "Width", "Style", "Link", "Mix" }, "delay"),
    { "Time", "TimeR", "Sync", "Feedback", "FeedbackR", "Cross", "Width", "Mode", "Link", "Mix" }), "2 3 1 4 5 6 7 8 9 10")
  check("guess delay: right words", roles_of(CS.guess({ "Left Delay", "Right Delay", "Offset", "Ratio" }, "delay"),
    { "Time", "TimeR", "Offset", "Ratio" }), "0 1 2 3")
  -- five real delays, by their own parameter names
  do
    local function g_of(names)
      local g = CS.guess(names, "delay")
      local t = {}
      for r, p in pairs(g.roles) do if not r:match("^T[2-9]") and not r:match("^T10") then t[#t + 1] = r .. "=" .. names[p + 1] end end
      table.sort(t)
      return table.concat(t, ","), g.nt
    end
    local xd = { "Bypass", "Mix", "Sync to Host", "Multiplier IN", "Multiplier", "Tap 1 IN", "Tap 1 Free/Sync", "Tap 1 Time",
      "Tap 1 Division", "Tap 1 Rhythm", "Tap 1 Level", "Tap 1 Pan", "Tap 1 Ping Pong", "Tap 1 Ping Pong Pan", "Tap 2 IN", "Tap 2 Time",
      "Saturation", "Feedback", "Width" }
    local s_, nt = g_of(xd)
    check("guess X-Delay", s_ .. " " .. tostring(nt), "Feedback=Feedback,Mix=Mix,Multiplier=Multiplier,Sync=Sync to Host," ..
      "T1Level=Tap 1 Level,T1Note=Tap 1 Division,T1On=Tap 1 IN,T1Pan=Tap 1 Pan,T1PingPong=Tap 1 Ping Pong,T1Rhythm=Tap 1 Rhythm," ..
      "T1Sync=Tap 1 Free/Sync,T1Time=Tap 1 Time,Width=Width 2")
    s_, nt = g_of({ "Note Snap", "Delay Time", "Ping Pong", "Tap 1 Enable", "Tap 2 Enable", "Tap 3 Enable", "Tap 4 Enable", "Saturation",
      "Feedback", "Width", "Mix" })
    check("guess X-Echo", s_ .. " " .. tostring(nt), "Feedback=Feedback,Mix=Mix,PingPong=Ping Pong,Sync=Note Snap,T1On=Tap 1 Enable," ..
      "Time=Delay Time,Width=Width 4")
    s_, nt = g_of({ "Input", "Mode", "Output", "Ducking", "Mix", "Time", "Spread", "Type", "Feedback", "Modulation", "Damping", "Sync",
      "FX Feedback" })
    check("guess UFX-Delay", s_ .. " " .. tostring(nt), "Feedback=Feedback,Mix=Mix,Mode=Type,Offset=Spread,Sync=Sync,Time=Time nil")
    s_, nt = g_of({ "Max Time", "DAW Sync", "Global Delay Sync", "Pattern Feedback", "Delay Mode", "Time 1", "Pan 1", "Level 1",
      "T1 State", "Time 2", "Pan 2", "Level 2", "T2 State", "Width", "Dry/Wet Mix" })
    check("guess Echoes", s_ .. " " .. tostring(nt), "Feedback=Pattern Feedback,Mix=Dry/Wet Mix,Mode=Delay Mode,Note=Global Delay Sync," ..
      "Sync=DAW Sync,T1Level=Level 1,T1On=T1 State,T1Pan=Pan 1,T1Time=Time 1,Time=Max Time,Width=Width 2")
    s_, nt = g_of({ "Mix", "DelayStyle", "DelayLSync", "DelayLNote", "DelayL_Ms", "DelayRSync", "DelayRNote", "DelayR_Ms", "DelaySpread",
      "DelaySpacing", "DelayRatio", "RepeatSwell", "TapA", "Feedback", "Width", "Mode" })
    check("guess Valhalla Delay", s_ .. " " .. tostring(nt), "Feedback=Feedback,Mix=Mix,Mode=DelayStyle,Note=DelayLNote,NoteR=DelayRNote," ..
      "Offset=DelaySpread,Ratio=DelayRatio,Sync=DelayLSync,Time=DelayL_Ms,TimeR=DelayR_Ms,Width=Width nil")
  end
  do
    local DLY = require("TS_CV_Delay")
    local function rd(text, n) local v, u = UN.parse(text); return { p = 0, n = n or 0.5, text = text, v = v, unit = u } end
    -- a division and a rhythm beside it: 1-8 dotted at 120 = 375 ms
    local t = DLY.time_of({ Note = rd("1-8"), Rhythm = rd("Dotted"), Sync = rd("Sync") }, { bpm = 120 })
    check("delay time: division x rhythm", ("%s %.0f"):format(t.how, t.ms), "note 375")
    -- free, the ms time rules
    t = DLY.time_of({ Time = rd("520.00 ms"), Note = rd("1-8"), Sync = rd("Free") }, { bpm = 120 })
    check("delay time: free", ("%s %.0f"):format(t.how, t.ms), "ms 520")
    -- snapping to what it can reach: divisions x rhythms
    local DIV = { "1-16", "1-8", "1-4", "1-2" }
    local RH = { "None", "Dotted", "Triplet" }
    local function pos(list) local o = {} for i, x in ipairs(list) do o[i] = { norm = (i - 1) / (#list - 1), text = x } end return o end
    local set_ = {}
    local io = { positions = function(m) return m.text:find("-", 1, true) and pos(DIV) or pos(RH) end,
                 set_norm = function(m, n) set_[m.text] = n end, set_to = function() end }
    DLY.set_time({ Note = rd("1-8", 1 / 3), Rhythm = rd("None", 0), Sync = rd("Sync") }, 760, { bpm = 120 }, io)
    check("delay snap: 760 ms is a dotted 1/4", ("%.3f %.3f"):format(set_["1-8"] or -1, set_["None"] or -1), "0.667 0.500")
    -- a time in ms that follows the tempo snaps onto note values
    local got
    DLY.set_time({ Time = rd("400.0 ms", 0.4), Sync = rd("On") }, 410,
      { bpm = 120 }, { positions = function() return nil end, set_norm = function() end, set_to = function(_, v) got = v end })
    check("delay snap: 410 ms onto a dotted 1/8", ("%.1f"):format(got), "375.0")
    check("delay labels", table.concat({ DLY.note_label(1.5), DLY.note_label(1 / 3), DLY.note_label(1), DLY.note_label(4) }, " "),
      "1/4 D 1/8 T 1/4 1 bar")
    -- X-Echo's taps: no time of their own, each its share of the main time
    local R = { Time = rd("800.0 ms"), Feedback = rd("50 %"), T1On = rd("Off"), T2On = rd("On"), T3On = rd("Off"), T4On = rd("On") }
    local mdl = DLY.model(R, { nt = 4, rev = {} }, { bpm = 120 })
    local on = {}
    for _, tp in ipairs(mdl.taps) do if tp.on then on[#on + 1] = ("%d@%.0f"):format(tp.k, tp.t) end end
    check("delay taps: shares of the time", table.concat(on, " ") .. (" P%.0f"):format(mdl.period), "2@400 4@800 P800")
    -- Echoes' taps: a % of the main time, panned
    R = { Time = rd("1000.0 ms"), Feedback = rd("0 %"), T1Time = rd("50 %"), T1Pan = rd("-100"), T1Level = rd("100 %") }
    mdl = DLY.model(R, { nt = 1, rev = {} }, { bpm = 120 })
    local e = mdl.echoes[1]
    check("delay taps: a % of the time, left", ("%.0f %.2f %.2f"):format(e.t, e.l, e.r), "500 1.00 0.00")
    -- a tap's own feedback gets a dot of its own (drawn while it's
    -- selected), and its pan and feedback are set from the canvas
    R = { Time = rd("1000.0 ms"), Feedback = rd("50 %"), T1Time = rd("25 %"), T1Feedback = rd("40 %"), T1Pan = rd("L50", 0.25),
          T2Time = rd("50 %") }
    mdl = DLY.model(R, { nt = 2, rev = {} }, { bpm = 120 })
    local ids = {}
    for _, h in ipairs(mdl.handles) do ids[#ids + 1] = h.id .. (h.own and ("/" .. h.own) or "") end
    check("delay taps: own feedback handle", table.concat(ids, " "), "t1 f1/1 t2 fb time")
    local wrote = {}
    local io2 = { positions = function() return nil end, set_norm = function(m, n) wrote[#wrote + 1] = ("n%.3f"):format(n) end,
                  set_to = function(m, v) wrote[#wrote + 1] = ("v%.1f"):format(v) end }
    DLY.apply(R, { nt = 2, rev = {} }, { bpm = 120 }, io2, "p1", "v", 0.5)
    DLY.apply(R, { nt = 2, rev = {} }, { bpm = 120 }, io2, "f1", "v", 0.6)
    check("delay taps: pan and own feedback set", table.concat(wrote, " "), "n0.750 v60.0")
    -- a stereo mode by what setup was told its settings mean
    check("delay mode: told", tostring(DLY.mode({ Mode = rd("Tape") }, { Tape = "pp" })) .. " " ..
      tostring(DLY.mode({ Mode = rd("Dual") }, nil)) .. " " .. tostring(DLY.mode({ Mode = rd("On", 1) }, nil, "Ping Pong")), "pp dual pp")
    -- pans as SSL writes them
    check("delay pans", table.concat({ DLY.pan_of(rd("L--")), DLY.pan_of(rd("L50")), DLY.pan_of(rd("-C-")), DLY.pan_of(rd("50R")),
      DLY.pan_of(rd("--R")), DLY.pan_of(rd("-50")) }, " "), "-1 -0.5 0 0.5 1 -0.5")
    -- the modes and taps survive the file
    local cvd = M.parse_canvas and nil
    check("delay modes round trip", M.dl_modes_write(M.dl_modes_parse("Single:mono;PingPong:pp;Tape:none")), "PingPong:pp;Single:mono;Tape:none")
  end
  do
    -- ReaDelay and ReaVerbate: their own canvases
    local RB = require("TS_CV_ReaFX")
    local st0 = "AAAAAAAAAAABAAAALAAAAAIAAAAAAAAAQwIAPwAAgD8AAAAAAACAPwAAAAAAAAA8nNEHMwAAgD8AAAAAAACAPwAAgD8AAIA/AAAAPw=="
    local raw = RB.b64dec(st0)
    check("readelay state: base64 both ways", #raw .. " " .. tostring(RB.b64enc(raw) == st0), "76 true")
    local head, taps, tsz = RB.state_split(raw)
    check("readelay state: one tap of 44", #taps .. " " .. tsz .. " " .. #head, "1 44 32")
    taps[2] = RB.tap_moved(taps[1], tsz, 1)
    local raw2 = RB.state_join(head, taps)
    local _, t2 = RB.state_split(raw2)
    check("readelay state: a tap added an eighth later", ("%d %.4f"):format(#t2, select(4, string.unpack("<ffff", t2[2])) * 256), "2 3.0000")
    -- the same as REAPER wrote it with three taps (TS_CV_ReaProbe2)
    check("readelay state: as REAPER has it", RB.b64enc(RB.state_join(head, { taps[1], RB.tap_moved(taps[1], tsz, 1), RB.tap_moved(taps[1], tsz, 2) })),
      "AAAAAAAAAAADAAAALAAAAAIAAAAAAAAAQwIAPwAAgD8AAAAAAACAPwAAAAAAAAA8nNEHMwAAgD8AAAAAAACAPwAAgD8AAIA/AAAAPwAAAAAAAIA/AAAAAAAAQDyc0QczAACAPwAAAAAAAIA/AACAPwAAgD8AAAA/AAAAAAAAgD8AAAAAAACAPJzRBzMAAIA/AAAAAAAAgD8AAIA/AACAPwAAAD8=")
    local saved = {}
    local function stub(k, f) saved[k] = reaper[k]; reaper[k] = f end
    local NM = { "Wet", "Dry" }
    for k = 1, 3 do for _, f in ipairs({ "Enabled", "Length (time)", "Length (musical)", "Feedback", "Lowpass", "Hipass",
      "Resolution", "Stereo width", "Volume", "Pan" }) do NM[#NM + 1] = k .. ": " .. f end end
    NM[#NM + 1] = "Bypass"; NM[#NM + 1] = "Wet"; NM[#NM + 1] = "Delta"
    stub("TrackFX_GetNumParams", function() return #NM end)
    stub("TrackFX_GetParamName", function(_, _, p) return true, NM[p + 1] or "" end)
    local lay = RB.ensure({}, 0, "{RD}", "ReaDelay", { controls = {} })
    local cvr = lay.canvas
    check("readelay canvas", ("%s %s %d %d %d %d %d %d"):format(cvr.kind, cvr.builtin, cvr.nt, cvr.roles.T2On, cvr.roles.T2Note,
      cvr.roles.T3Pan, cvr.roles.T1HighCut, cvr.roles.Dry), "delay readelay 3 12 14 31 6 1")
    lay = RB.ensure({}, 0, "{RV}", "ReaVerbate", { controls = {} })
    check("reaverbate canvas", ("%s %d %.2f"):format(lay.canvas.kind, lay.canvas.roles.Predelay,
      M.decay_ms(lay.canvas, 0.294, nil) / 1000), "reverb 5 0.31")
    check("reaverbate decay not saved", (function() local o = {}; M.canvas_lines(lay.canvas, o); return o.DecayCal == nil end)(), true)
    check("another kind left alone", RB.ensure({}, 0, "{X}", "ReaDelay", { canvas = { kind = "eq", bands = {} } }).canvas.kind, "eq")
    -- ReaDelay's taps in the model: time plus musical length, each its own feedback
    local DLY = require("TS_CV_Delay")
    local function rd(text, n) local v, u = UN.parse(text); return { p = 0, n = n or 0.5, text = text, v = v, unit = u } end
    local R = { T1On = rd("ON", 1), T1Time = rd("0.0 ms"), T1Note = rd("2.00 8N"), T1Feedback = rd("-6.0 dB"),
                T2On = rd("ON", 1), T2Time = rd("100.0 ms"), T2Note = rd("1.00 8N"), T2Feedback = rd("-inf dB") }
    local mdl = DLY.model(R, { nt = 2, rev = {}, builtin = "readelay" }, { bpm = 120 })
    check("readelay taps: time + musical", ("%.0f %.0f %.2f %s"):format(mdl.taps[1].t, mdl.taps[2].t, mdl.taps[1].fb,
      tostring(mdl.beat_grid)), "500 350 0.50 false")
    local wrote = {}
    local io3 = { positions = function() return nil end, set_norm = function() end, set_to = function(m, v) wrote[#wrote + 1] = m.text .. "=" .. ("%.2f"):format(v) end }
    DLY.apply(R, { nt = 2, rev = {}, builtin = "readelay" }, { bpm = 120 }, io3, "t1", "t", 760)
    DLY.apply(R, { nt = 2, rev = {}, builtin = "readelay" }, { bpm = 120 }, io3, "t2", "t", 400)
    DLY.apply(R, { nt = 2, rev = {}, builtin = "readelay" }, { bpm = 120 }, io3, "f2", "v", 0.5)
    check("readelay drags: musical snaps, ms moves, feedback in dB", table.concat(wrote, " "),
      "2.00 8N=3.00 100.0 ms=150.00 -inf dB=-6.02")
    for k, fn in pairs(saved) do reaper[k] = fn end
  end
  do
    -- a plugin that answers with what it reads now (Valhalla's): read by moving it
    local saved = {}
    local function stub(k, f) saved[k] = reaper[k]; reaper[k] = f end
    local val = 0.3
    stub("TrackFX_FormatParamValueNormalized", function() return true, ("%.1f ms"):format(val * 1000) end)
    stub("TrackFX_GetFormattedParamValue", function() return true, ("%.1f ms"):format(val * 1000) end)
    stub("TrackFX_GetParamNormalized", function() return val end)
    stub("TrackFX_SetParamNormalized", function(_, _, _, n) val = n end)
    stub("TrackFX_GetFXGUID", function() return "{VAL}" end)
    stub("GetTrackAutomationMode", function() return 0 end)
    local f = UN.formatter({}, 0, 4)
    check("dead formatter: read by moving", ("%s %s %.2f"):format(f(0), f(1), val), "0.0 ms 1000.0 ms 0.30")
    check("dead formatter: between steps", f(0.5004) ~= nil and select(1, UN.parse(f(0.5004))) > 500, true)
    check("dead formatter: find", ("%.3f"):format(UN.find_norm(f, 250)), "0.250")
    for k, fn in pairs(saved) do reaper[k] = fn end
  end
  check("delay mode", tostring(M.dl_mode_of("Ping-Pong")) .. tostring(M.dl_mode_of("Dual")) .. tostring(M.dl_mode_of("Single"))
    .. tostring(M.dl_mode_of("Tape")), "ppdualmononil")
  check("delay sync", tostring(M.dl_sync_of("Free", 1)) .. tostring(M.dl_sync_of("Straight", 0.33)) .. tostring(M.dl_sync_of("Dotted", 0.6))
    .. tostring(M.dl_sync_of("On", 1)) .. tostring(M.dl_sync_of("Off", 0)) .. tostring(M.dl_sync_of("", 0.7)), "falsetruetruetruefalsetrue")
  check("delay ratio", ("%g %g %g %s"):format(M.dl_ratio_of("3:4"), M.dl_ratio_of("75 %"), M.dl_ratio_of("1.5"), tostring(M.dl_ratio_of("Off"))),
    "0.75 0.75 1.5 nil")
  check("delay note labels", table.concat({ M.dl_note_label(0.5), M.dl_note_label(1.5), M.dl_note_label(4), M.dl_note_label(8),
    M.dl_note_label(5) }, " "), "1/8 3/8 1 bar 2 bars 5/4")
  do
    -- ping-pong: left, right, left at t, 2t, 3t, each down by the feedback
    local tp = M.dl_taps({ tL = 100, tR = 100, fbL = 0, fbR = 0, cross = 0.5, inL = 1, inR = 0, span = 350 })
    local s_ = {}
    for _, e in ipairs(tp) do s_[#s_ + 1] = ("%s%d:%.2f"):format(e.sd, e.t, e.a) end
    check("delay taps: ping-pong", table.concat(s_, " "), "L100:1.00 R200:0.50 L300:0.25")
    -- dual: each side its own time and feedback
    tp = M.dl_taps({ tL = 100, tR = 150, fbL = 0.5, fbR = 0.5, inL = 1, inR = 1, span = 320 })
    s_ = {}
    for _, e in ipairs(tp) do s_[#s_ + 1] = ("%s%d"):format(e.sd, e.t) end
    check("delay taps: dual", table.concat(s_, " "), "L100 R150 L200 R300 L300")
    -- mono: both sides together, full height either way at no width
    tp = M.dl_taps({ tL = 100, tR = 100, fbL = 0.5, fbR = 0.5, inL = 1, inR = 1, span = 250 })
    local b = M.dl_bars(tp, 0)
    check("delay bars: mono", ("%d %.2f %.2f %.2f"):format(#b, b[1].l, b[1].r, b[2].l), "2 1.00 1.00 0.50")
    -- width narrows a one-sided echo into a little of the other side
    b = M.dl_bars({ { t = 100, sd = "L", a = 1 } }, 0.6)
    check("delay bars: width", ("%.2f %.2f"):format(b[1].l, b[1].r), "0.80 0.20")
  end
  check("guess reverb", roles_of(CS.guess({ "Pre-Delay", "Decay Time", "Size", "Early Level", "HF Damping", "Bass Mult", "Dry/Wet" }, "reverb"),
    { "Predelay", "Decay", "Size", "Early", "Damping", "Bass", "Mix" }), "0 1 2 3 4 5 6")
  -- CSR Hall-style: crossover, low time, high freq, high damp, diffusion
  local csr = { "In Level", "Out Level", "Mix", "Type", "Lock", "Rvb Time", "Low Time", "Crossover", "High Freq",
                "High Damp", "Pre Delay", "Size", "Diffusion", "Early", "Spread", "Modulation" }
  check("guess reverb: CSR-style", roles_of(CS.guess(csr, "reverb"),
    { "Decay", "Bass", "LowFreq", "HighFreq", "Damping", "Predelay", "Size", "Diffusion", "Mix" }), "5 6 7 8 9 10 11 12 2")
  check("guess reverb: cuts are cuts", roles_of(CS.guess({ "Decay", "Low Cut", "High Cut", "HF Damp" }, "reverb"),
    { "LowCut", "HighCut", "Damping" }), "1 2 3")
  -- real reverbs, by their own names
  do
    local function g(names, list) return roles_of(CS.guess(names, "reverb"), list) end
    check("guess reverb: words apart", CS._rv_words("RTHighMultiply") .. "|" .. CS._rv_words("earlyLateMix") .. "|" .. CS._rv_words("HiCut"),
      "RT High Multiply|early Late Mix|Hi Cut")
    check("guess vintageverb", g({ "Mix", "PreDelay", "Decay", "Size", "Attack", "BassMult", "BassXover", "HighShelf", "HighFreq",
      "EarlyDiffusion", "LateDiffusion", "ModRate", "ModDepth", "HighCut", "LowCut", "ColorMode", "ReverbMode", "Bypass", "Bypass", "Wet", "Delta" },
      { "Decay", "Early", "Diffusion", "LowFreq", "Bass", "HighFreq", "Damping", "LowCut", "HighCut", "Style", "Mix" }),
      "2 nil 10 6 5 8 7 14 13 16 0")
    check("guess tsar-1", g({ "Predelay", "Reverb Time", "Density", "Reverb Tone", "High Cut", "ER Type", "ER Mix", "Diffusion",
      "Modulation", "Reverb Mix", "Output Vol", "Bypass", "Bypass", "Wet", "Delta" },
      { "Predelay", "Decay", "Early", "Tone", "HighCut", "Mix" }), "0 1 6 3 4 9")
    check("guess seventh heaven", g({ "Master Gain", "Dry/Wet Mix", "Decay Time", "Early / Late Level", "VLF Reverb Level", "Pre-delay",
      "Pre-delay Sync", "Pre-delay Tempo", "Delay (Echo) Time", "Delay Sync", "Delay Tempo", "Low Pass Freq", "High Pass Freq",
      "Low Pass Enable", "High Pass Enable" },
      { "Decay", "Balance", "Early", "Predelay", "LowCut", "HighCut", "LowCutOn", "HighCutOn", "Mix" }), "2 3 nil 5 12 11 14 13 1")
    check("guess ufx-reverb", g({ "Input", "Mode", "Output", "Ducking", "Mix", "Pre-Delay", "Time", "Size", "Diffusion", "Modulation",
      "Damping", "Freeze", "Filter", "Filter Mode", "Filter Amount" },
      { "Decay", "Size", "Damping", "Style", "Freeze", "Mix" }), "6 7 10 1 11 4")
    check("guess pro-r 2", g({ "Space", "Decay Rate", "Distance", "Brightness", "Style", "Character", "Thickness", "Stereo Width",
      "Ducking", "Mix", "Lock Mix", "Freeze", "Auto Gate", "Auto Gate Enabled", "Auto Gate Offset", "Auto Gate Sync", "Predelay",
      "Predelay Offset", "Predelay Sync", "Decay EQ Band 1 Used", "Decay EQ Band 1 Enabled", "Decay EQ Band 1 Frequency" },
      { "Decay", "Tone", "Style", "Freeze", "Mix", "Predelay" }), "0 3 4 11 9 16")
    check("guess valhallaroom", g({ "mix", "predelay", "decay", "HiCut", "earlyLateMix", "lateSize", "lateCross", "lateModRate",
      "lateModDepth", "RTBassMultiply", "RTXover", "RTHighMultiply", "RTHighXover", "earlySize", "earlyCross", "earlyModRate",
      "earlyModDepth", "earlySend", "diffusion", "type", "space", "LoCut" },
      { "Decay", "Size", "Balance", "Early", "LowFreq", "Bass", "HighFreq", "Damping", "LowCut", "HighCut", "Style" }),
      "2 5 4 nil 10 9 12 11 21 3 19")
    check("guess superplate", g({ "Bypass", "Plate Style", "Analog Style", "Decay", "PreDelay", "Modulation", "Mix", "Output", "Input",
      "Low Cut", "High Cut", "Target Decay", "Threshold", "Recovery Time", "Mod Rate", "Width", "Balance", "EQ1 Gain", "EQ1 Freq",
      "EQ1 Q", "EQ2 Gain", "EQ2 Freq", "EQ2 Q", "Low Cut Slope", "High Cut Slope" },
      { "Decay", "Style", "LowCut", "HighCut", "Mix" }), "3 1 9 10 6")
    check("guess hitsville", g({ "Chamber", "Dist 2648", "Dist 2644", "Speakers", "Microphones", "Width", "Mono", "Predelay", "Low",
      "High", "Decay", "Mix", "Wet Solo", "Power" }, { "Predelay", "Decay", "LowEQ", "HighEQ", "Mix" }), "7 10 8 9 11")
    -- the balance's readings
    check("balance: crossfade", UN.balance_text("0 dB / -16.0 dB") .. " " .. UN.balance_text("-8.0 dB / 0 dB") .. " " .. UN.balance_text("-6.0 / 0 dB"), "16.0 -8.0 -6.0")
    check("balance: named", UN.balance_text("Equal Mix") .. " " .. UN.balance_text("Reflections") .. " " .. UN.balance_text("Late Reverb"), "0 24 -60")
    check("balance: percent", ("%.1f %.1f"):format(UN.balance_text("50.00 %"), UN.balance_text("90 %")), "0.0 -19.1")
    local tab = UN.balance_table(function(n) return ("%.0f %%"):format(n * 100) end)
    check("balance: table", tab and #tab, 41)
    check("balance: along and back", ("%.2f"):format(UN.balance_norm(tab, UN.balance_at(tab, 0.3))), "0.30")
    local RPx = require("TS_CV_RolePanel")
    check("reverb tone: tilt", ("%.2f %.2f %.2f"):format(RPx.rv_tilt(1, 20000), RPx.rv_tilt(-1, 20000), RPx.rv_tilt(1, 1000)), "4.00 0.25 1.00")
    check("reverb shelves", ("%.1f %.1f"):format(RPx.rv_shelves(-6, 3, 30), RPx.rv_shelves(-6, 3, 20000)), "-5.8 2.8")
  end
  check("guess envelope: a curve isn't a time", roles_of(CS.guess({ "Attack Curve", "Attack", "Decay", "Sustain", "Release", "Release Curve" }, "env"),
    { "Attack", "AttackCurve", "Decay", "Sustain", "Release", "ReleaseCurve" }), "1 0 2 3 4 5")
  check("guess modulation", roles_of(CS.guess({ "Rate", "Depth", "Waveform", "Stereo Phase", "Mix" }, "mod"),
    { "Rate", "Depth", "Shape", "Phase", "Mix" }), "0 1 2 3 4")
  -- real choruses, by their own names: voices of their own
  -- (Triad Chorus), a depth per side (TriceraChorus), a count (Thorus)
  do
    local triad = { "In", "Out", "Feedback", "Stereo", "Voice 1 Amount", "Voice 2 Amount", "Voice 3 Amount",
      "Voice 1 Pan", "Voice 2 Pan", "Voice 3 Pan", "Voice 1 Phase", "Voice 2 Phase", "Voice 3 Phase",
      "Voice 1 Rate", "Voice 2 Rate", "Voice 3 Rate", "Voice 1 Rate Sync", "Voice 2 Rate Sync", "Voice 3 Rate Sync",
      "Voice 1 BPM Sync", "Voice 2 BPM Sync", "Voice 3 BPM Sync", "Voice 1 On", "Voice 2 On", "Voice 3 On",
      "Bypass", "Bypass", "Wet", "Delta" }
    local g = CS.guess(triad, "mod")
    check("guess triad: main", roles_of(g, { "Rate", "Depth", "Phase", "Feedback", "Mix" }), "nil nil nil 2 27")
    check("guess triad: voice 2", roles_of(g, { "V2Depth", "V2Pan", "V2Phase", "V2Rate", "V2Note", "V2Sync", "V2On" }), "5 8 11 14 17 20 23")
    check("guess triad: voices", table.concat(M.mod_voices(g.roles), ","), "1,2,3")
    local tri = { "CHORUS/CHORALE MIX", "CHORUS/CHORALE MODE", "RATE", "DEPTH L", "DEPTH C", "DEPTH R", "DELAY", "ENV RATE",
      "DETUNE MIX", "DETUNE", "ENV MIX", "TONE", "SOURCE", "SWIRL", "INPUT LEVEL", "OUTPUT LEVEL", "ACTIVE", "RIBBON CONTROLLER",
      "HOTSWITCH", "TEMPO MODE", "TEMPO", "LFO RETRIGGER" }
    local t = CS.guess(tri, "mod")
    check("guess tricera: rate, sides", roles_of(t, { "Rate", "Depth", "V1Depth", "V2Depth", "V3Depth", "Delay" }), "2 nil 3 4 5 6")
    check("guess tricera: only depths", tostring(t.roles.V1Rate) .. " " .. tostring(t.roles.V1On), "nil nil")
    local th = CS.guess({ "Speed", "Depth", "Edge", "Tone", "Crossover", "LowGain", "Mode", "NumVoices", "Mix", "Trim", "Bypass" }, "mod")
    check("guess thorus", roles_of(th, { "Rate", "Depth", "Voices", "Mix", "Phase" }), "0 1 7 8 nil")
    check("voice of: names", table.concat({ tostring(CS._mod_voice_of("V2 Depth")), tostring(CS._mod_voice_of("Depth Right")),
      tostring(CS._mod_voice_of("NumVoices")), tostring(CS._mod_voice_of("Voice 3 On")) }, " "), "2 3 nil 3")
    -- a voice layout keeps its voices
    M.set("TestCho :: Modulation", { controls = {}, aliases = {}, canvas = { kind = "mod",
      roles = { Rate = 0, V1Depth = 3, V2Depth = 4, V3Pan = 7, Voices = 9 }, rev = { V3Pan = true } } })
    M.save(); M.reload()
    local mc = M.get("TestCho :: Modulation")
    check("mod voices layout: kept", mc and (mc.canvas.roles.V2Depth .. " " .. mc.canvas.roles.V3Pan .. " " .. mc.canvas.roles.Voices
      .. " " .. tostring(mc.canvas.rev.V3Pan)), "4 7 9 true")
    check("mod voices layout: voices", mc and table.concat(M.mod_voices(mc.canvas.roles), ","), "1,2,3")
    M.remove("TestCho :: Modulation"); M.save()
  end
  M.set("TestDly :: Delay", { controls = {}, aliases = {}, canvas = { kind = "delay",
    roles = { Time = 0, Feedback = 3, PingPong = 4 }, rev = { Feedback = true } } })
  M.save(); M.reload()
  local dl = M.get("TestDly :: Delay")
  check("delay layout: kept", dl and (dl.canvas.kind .. " " .. dl.canvas.roles.PingPong .. " " .. tostring(dl.canvas.rev.Feedback)), "delay 4 true")
  M.remove("TestDly :: Delay"); M.save()
  check("canvas order covers every kind", (function()
    for _, k in ipairs(M.CANVAS_ORDER) do if k ~= "eq" and not M.ROLES[k] then return k end end
    return #M.CANVAS_ORDER end)(), 11)
  local RP = require("TS_CV_RolePanel")
  check("envelope curve: straight", RP._env_bend(0.5, 0), 0.5)
  checkf("envelope curve: fast start", function() return RP._env_bend(0.5, -1) > 0.8 end)
  checkf("envelope curve: slow start", function() return RP._env_bend(0.5, 1) < 0.2 end)
  check("lfo shape: triangle", RP._shape_of("Triangle"), "tri")
  check("lfo shape: S&H", RP._shape_of("S&H"), "sh")
  check("lfo shape: saw down", RP._shape_of("Saw Down"), "sawdown")
  check("lfo shape: unknown is sine", RP._shape_of("Wobble"), "sine")
  -- a multiband band's reduction from the third-octaves: their median
  do
    local fr = { n = 30, f = {}, g = {} }
    for k = 1, 30 do fr.f[k] = 1000 * 2 ^ ((k - 17) / 3) end
    fr.g[17], fr.g[18], fr.g[19] = 2, 6, 3          -- 1k, 1.26k, 1.6k
    check("fine bands: median of those inside", RP.fine_band_gr(fr, 900, 1800), 3)
    fr.g[20] = 5
    check("fine bands: an even count averages", RP.fine_band_gr(fr, 900, 2100), 4)
    check("fine bands: a narrow band takes its nearest", RP.fine_band_gr(fr, 1020, 1100), 2)
    fr.g[17] = -1
    check("fine bands: a lift reads as none", RP.fine_band_gr(fr, 990, 1010), 0)
    check("fine bands: no reading, nil", RP.fine_band_gr(nil, 100, 200), nil)
  end
  checkf("lfo: every shape peaks at a quarter, or near", function()
    return RP._lfo("sine", 0.25) > 0.99 and RP._lfo("tri", 0.25) > 0.99 and RP._lfo("square", 0.1) == 1 end)
end

-- a factory preset the plugin didn't tell REAPER about: its state handed back
do
  local PR = require("TS_CV_Presets")
  local saved = {}
  local function stub(k, f) saved[k] = reaper[k]; reaper[k] = f end
  local vals, chunk_set, preset = { [0] = 0.1, 0.2 }, 0, "Factory A"
  stub("TrackFX_GetFXGUID", function() return "{PRS}" end)
  stub("TrackFX_GetCount", function() return 1 end)
  stub("TrackFX_GetNumParams", function() return 2 end)
  stub("TrackFX_GetParamNormalized", function(_, _, p) return vals[p] end)
  stub("TrackFX_GetPreset", function() return false, preset end)
  stub("TrackFX_SetPreset", function() return true end)
  stub("TrackFX_GetPresetIndex", function() return 0, 3 end)
  stub("ValidatePtr", function() return true end)
  stub("TrackFX_GetNamedConfigParm", function(_, _, k) if k == "vst_chunk" then return true, "AAAA" end return false, "" end)
  stub("TrackFX_SetNamedConfigParm", function(_, _, k) if k == "vst_chunk" then chunk_set = chunk_set + 1 end return true end)
  local is_user = PR.is_user
  PR.is_user = function(_, _, n) return n == "Mine" end
  PR.load("tr", 0, "Factory A")
  PR.tick(reaper.time_precise() + 1)
  check("factory preset, nothing moved: handed back", chunk_set, 1)
  PR.load("tr", 0, "Factory A"); vals[0] = 0.7; vals[1] = 0.9
  PR.tick(reaper.time_precise() + 1)
  check("factory preset that told REAPER: left", chunk_set, 1)
  preset = "Mine"; PR.load("tr", 0, "Mine"); vals[0] = 0.3
  PR.tick(reaper.time_precise() + 1)
  check("user preset: left", chunk_set, 1)
  PR.seen("tr", 0, "Mine"); preset = "Factory B"; PR.seen("tr", 0, "Factory B")
  PR.tick(reaper.time_precise() + 1)
  check("picked in the plugin's window: handed back", chunk_set, 2)
  PR.is_user = is_user
  for k, f in pairs(saved) do reaper[k] = f end
end

-- multiband layouts
do
  check("multiband: band role split", table.concat({ M.mb_split("B3Ratio") }, " "), "3 Ratio")
  check("multiband: not a band role", M.mb_split("Output"), nil)
  M.set("TestMB :: Multiband", { controls = {}, aliases = {}, canvas = { kind = "multi", nb = 4,
    roles = { Crossover1 = 0, Crossover3 = 2, B4Threshold = 9, B2Solo = 5, Output = 11 }, rev = { B4Threshold = true } } })
  M.save(); M.reload()
  local l = M.get("TestMB :: Multiband")
  check("multiband: kept", l and ("%s %d %d %d %s"):format(l.canvas.kind, l.canvas.nb, l.canvas.roles.Crossover3,
    l.canvas.roles.B4Threshold, tostring(l.canvas.rev.B4Threshold)), "multi 4 2 9 true")
  check("multiband: a copy keeps its bands", M.copy(l).canvas.nb, 4)
  M.remove("TestMB :: Multiband"); M.save()
  local CS = require("TS_CV_CanvasSetup")
  -- C4-style: worded bands and crossovers
  local c4 = { "Low Crossover", "Mid Crossover", "High Crossover", "Low Thresh", "LowMid Thresh", "HighMid Thresh",
               "High Thresh", "Low Gain", "High Release", "Output", "Low Solo" }
  check("multiband guess: four bands from the words", CS.mb_count(c4), 4)
  local g = CS.guess(c4, "multi")
  check("multiband guess: crossovers", ("%s %s %s"):format(g.roles.Crossover1, g.roles.Crossover2, g.roles.Crossover3), "0 1 2")
  check("multiband guess: thresholds", ("%s %s %s %s"):format(g.roles.B1Threshold, g.roles.B2Threshold,
    g.roles.B3Threshold, g.roles.B4Threshold), "3 4 5 6")
  check("multiband guess: gain, release, solo, output", ("%s %s %s %s"):format(g.roles.B1Gain, g.roles.B4Release,
    g.roles.B1Solo, g.roles.Output), "7 8 10 9")
  -- numbered (ReaXcomp-style)
  local rx = { "Thresh 1", "Ratio 1", "Attack 1", "Release 1", "Freq 1", "Thresh 2", "Ratio 2", "Freq 2", "Thresh 3", "Ratio 3", "Dry/Wet" }
  check("multiband guess: three bands from the numbers", CS.mb_count(rx), 3)
  local g2 = CS.guess(rx, "multi")
  check("multiband guess: numbered", ("%s %s %s %s %s %s"):format(g2.roles.B1Threshold, g2.roles.B2Ratio, g2.roles.B3Threshold,
    g2.roles.Crossover1, g2.roles.Crossover2, g2.roles.Mix), "0 6 8 4 7 10")
  check("multiband: band names", table.concat(CS.band_names(3), "/"), "Low/Mid/High")
  -- Pro-MB-style: each band its own low and high crossover, and a state
  local pm = { "Band 1 State", "Band 1 Low Crossover", "Band 1 Low Slope", "Band 1 High Crossover", "Band 1 Threshold",
               "Band 2 State", "Band 2 Low Crossover", "Band 2 High Crossover", "Band 2 Threshold" }
  local g3 = CS.guess(pm, "multi", 2)
  check("multiband guess: a band's own edges", ("%s %s %s %s"):format(g3.roles.B1Low, g3.roles.B1High, g3.roles.B2Low, g3.roles.B2High), "1 3 6 7")
  check("multiband guess: no crossovers then", tostring(g3.roles.Crossover1), "nil")
  check("multiband guess: in use", ("%s %s"):format(g3.roles.B1Used, g3.roles.B2Used), "0 5")
  check("multiband guess: thresholds still", ("%s %s"):format(g3.roles.B1Threshold, g3.roles.B2Threshold), "4 8")
  check("multiband guess: a band's knee", CS.guess({ "Band 1 Threshold", "Band 1 Knee", "Band 2 Knee" }, "multi", 2).roles.B2Knee, 2)
  -- where the bands are: shared crossovers, or each its own
  do
    local TP = require("TS_CV_Taps")
    local RC = require("TS_CV_ReaComp")
    local vals = {}
    local gn, rt, bg = reaper.TrackFX_GetParamNormalized, RC.text, TP.band_gr
    reaper.TrackFX_GetParamNormalized = function(_, _, p) return (vals[p] or {})[2] or 0 end
    RC.text = function(_, _, p) return (vals[p] or {})[1] or "" end
    TP.band_gr = function(_, _, j) return j * 1.5 end
    vals[0] = { "5.0 kHz", 0.5 }; vals[1] = { "200 Hz", 0.3 }
    local pl = TP.mb_plan("tr", 0, { nb = 3, roles = { Crossover1 = 0, Crossover2 = 1 } })
    check("mb plan: crossovers put in order", ("%.0f %.0f"):format(pl.xs[1], pl.xs[2]), "5000 5100")
    check("mb plan: a band too narrow to measure", TP.mb_reading("tr", "g", pl, 2), nil)
    check("mb plan: the others measured", ("%s %s"):format(TP.mb_reading("tr", "g", pl, 1), TP.mb_reading("tr", "g", pl, 3)), "1.5 4.5")
    vals[0] = { "30 Hz", 0 }; vals[1] = { "250 Hz", 0.3 }; vals[2] = { "Used", 1 }
    vals[3] = { "Unused", 0 }; vals[4] = { "3.0 kHz", 0.6 }; vals[5] = { "Used", 1 }; vals[6] = { "8.0 kHz", 0.7 }
    local own = { nb = 3, roles = { B1Low = 0, B1High = 1, B1Used = 2, B2Used = 3, B3Low = 4, B3Used = 5, B3High = 6 } }
    local po = TP.mb_plan("tr", 0, own)
    check("mb plan: own edges", ("%s %.0f %.0f %.0f %.0f"):format(tostring(po.own), po[1].lo, po[1].hi, po[3].lo, po[3].hi), "true 30 250 3000 8000")
    check("mb plan: an unused band", ("%s %s"):format(tostring(po[2].used), tostring(po.at[2])), "false nil")
    check("mb plan: split between those in use", ("%.0f %s %s"):format(po.xs[1], po.at[1], po.at[3]), "866 1 2")
    check("mb plan: unused, no reading", TP.mb_reading("tr", "g", po, 2), nil)
    check("mb plan: the third band reads the second split", TP.mb_reading("tr", "g", po, 3), 3)
    check("mb state: Pro-MB's three", ("%s %s %s"):format(TP.mb_state_of("Disabled"), TP.mb_state_of("Enabled"), TP.mb_state_of("Unused")), "byp on off")
    check("mb state: a plain switch", ("%s %s %s"):format(TP.mb_state_of("Off", 0), TP.mb_state_of("On", 1), TP.mb_state_of("", 0.7)), "off on on")
    vals[3] = { "Disabled", 0.5 }
    local pd = TP.mb_plan("tr", 0, own)
    check("mb plan: a disabled band is still there", ("%s %s %s"):format(tostring(pd[2].used), tostring(pd[2].byp), tostring(pd.at[2])), "true true 2")
    reaper.TrackFX_GetParamNormalized, RC.text, TP.band_gr = gn, rt, bg
  end
end

-- a reverb's decay by frequency
do
  local RP = require("TS_CV_RolePanel")
  checkf("reverb: flat between the crossovers", function() return math.abs(RP.rv_mult(1000, 200, 1.5, 5000, 0.5) - 1) < 0.08 end)
  checkf("reverb: the lows' multiplier below", function() return math.abs(RP.rv_mult(30, 200, 1.5, 5000, 0.5) - 1.5) < 0.05 end)
  checkf("reverb: the highs' above", function() return math.abs(RP.rv_mult(19000, 200, 1.5, 5000, 0.5) - 0.5) < 0.05 end)
  -- damping in dB or %: along its range, the larger reading the more
  check("reverb: damping 0..-24 dB, halfway", ("%.2f"):format(RP.rv_damp({ v = -12, unit = "db", n = 0.5 }, false, 2000, 0, -24)), "0.50")
  check("reverb: damping all the way", ("%.2f"):format(RP.rv_damp({ v = -24, unit = "db", n = 1 }, false, 2000, 0, -24)), "0.25")
  check("reverb: damping that runs the other way", ("%.2f"):format(RP.rv_damp({ v = 0, unit = "pct", n = 1 }, false, 2000, 100, 0)), "1.00")
  check("reverb: damping as a time of its own", RP.rv_damp({ v = 1000, unit = "ms", n = 0.5 }, false, 2000), 0.5)
  check("reverb: damping as a multiplier", RP.rv_damp({ v = 0.6, unit = "", n = 0.6 }, false, 2000, 0, 1), 0.6)
  check("reverb: a scale of its own isn't a multiplier", ("%.2f"):format(RP.rv_damp({ v = 1.5, unit = "", n = 0.15 }, false, 2000, 0, 10)), ("%.2f"):format(0.25 ^ 0.15))
  check("reverb: bass as a time against the decay", RP.rv_bass({ v = 3000, unit = "ms", n = 0.5 }, false, 2000), 1.5)
  check("reverb: bass as a multiplier", RP.rv_bass({ v = 1.2, unit = "", n = 0.5 }), 1.2)
  check("reverb: bass along its range, x0.5..x2", ("%.2f %.2f"):format(RP.rv_bass({ unit = "x", n = 0 }), RP.rv_bass({ unit = "x", n = 1 })), "0.50 2.00")
  check("reverb: diffusion in %", RP.rv_diffusion({ v = 80, unit = "pct", n = 0.3 }), 0.8)
end

-- a reverb's decay, measured in seconds
do
  M.set("TestDec :: Reverb", { controls = {}, aliases = {}, canvas = { kind = "reverb", roles = { Decay = 5, Size = 11 }, rev = {},
    dec_cal = { p = 5, s = 11, pts = { { 0, 0, 400 }, { 0, 1, 4000 }, { 1, 0, 800 }, { 1, 1, 8000 } } } } })
  M.save(); M.reload()
  local l = M.get("TestDec :: Reverb")
  local dc = l and M.dec_cal(l.canvas)
  check("decay cal: kept", dc and ("%d %d %d"):format(dc.p, dc.s, #dc.pts), "5 11 4")
  checkf("decay cal: log between decay points", function() return math.abs(M.decay_ms(l.canvas, 0.5, 0) - 1264.9) < 1 end)
  checkf("decay cal: log between sizes", function() return math.abs(M.decay_ms(l.canvas, 0, 0.5) - 565.7) < 1 end)
  checkf("decay cal: back to a position", function() return math.abs(M.decay_pos(l.canvas, 1264.9, 0) - 0.5) < 0.001 end)
  check("decay cal: a copy keeps it", M.copy(l).canvas.dec_cal.pts[4][3], 8000)
  l.canvas.roles.Size = nil
  check("decay cal: not when its size isn't mapped as it was", M.dec_cal(l.canvas), nil)
  M.remove("TestDec :: Reverb"); M.save()
  local LN = require("TS_CV_Learn")
  local env = {}
  for i = 1, 300 do local t = (i - 1) * 10; env[i] = t < 300 and 0 or -60 * (t - 300) / 2500 end
  checkf(("decay fit: a 2.5 s tail (%.0f)"):format(LN.decay_fit(env) or 0), function() return math.abs(LN.decay_fit(env) - 2500) < 5 end)
  check("decay fit: no tail", LN.decay_fit({}), nil)
  -- not fully wet: the burst heard dry, then a sudden drop to the tail
  local env2 = {}
  for i = 1, 400 do local t = (i - 1) * 10; env2[i] = t < 330 and 0 or -30 - 60 * (t - 330) / 2500 end
  checkf(("decay fit: past a dry burst (%.0f)"):format(LN.decay_fit(env2, LN.DEC_FROM) or 0), function()
    return math.abs(LN.decay_fit(env2, LN.DEC_FROM) - 2500) < 5 end)
  check("decay summary", LN.decay_summary({ pts = { { 0, 0, 400 }, { 0.5, 0, 800 }, { 0.5, 1, 4000 }, { 1, 1, 9000 } } }),
    "0: 0.80 s, 100: 4.00 s (size at 50%)")
end

-- a compressor's threshold, measured where it really is
do
  M.set("TestThr :: Comp", { controls = {}, aliases = {}, canvas = { kind = "comp", roles = { Threshold = 3, Ratio = 4 }, rev = {},
    thr_cal = { p = 3, n = false, pts = { { -12, -30 }, { 0, -18 }, { 9, -9.2 } } } } })
  M.save(); M.reload()
  local l = M.get("TestThr :: Comp")
  local tc = l and M.thr_cal(l.canvas)
  check("thr cal: kept", tc and ("%d %s %d %.1f"):format(tc.p, tostring(tc.n), #tc.pts, tc.pts[3][2]), "3 false 3 -9.2")
  check("thr cal: between points", M.thr_dbfs(l.canvas, -6), -24)
  checkf("thr cal: past the end, along the last two", function() return math.abs(M.thr_dbfs(l.canvas, 12) - (-6.27)) < 0.01 end)
  check("thr cal: back again", M.thr_from_dbfs(l.canvas, -24), -6)
  check("thr cal: a copy keeps it", M.copy(l).canvas.thr_cal.pts[2][2], -18)
  l.canvas.roles.Threshold = 5
  check("thr cal: not for another threshold", M.thr_cal(l.canvas), nil)
  M.remove("TestThr :: Comp"); M.save()
  -- a reversed control: the points run downwards
  local cv = { roles = { Threshold = 1 }, thr_cal = { p = 1, n = true, pts = { { 0.2, -10 }, { 0.5, -25 }, { 0.8, -40 } } } }
  check("thr cal: reversed, back again", M.thr_from_dbfs(cv, -32.5), 0.65)
  local LN = require("TS_CV_Learn")
  local T, sl = LN.thr_fit({ { -40, 0 }, { -30, 0.2 }, { -24, 2.25 }, { -21, 4.5 }, { -18, 6.75 } })
  checkf(("thr fit: the foot of the line (%.2f, %.2f)"):format(T or 0, sl or 0), function() return T and math.abs(T + 27) < 0.01 and math.abs(sl - 0.75) < 0.01 end)
  check("thr fit: no compression, no threshold", LN.thr_fit({ { -40, 0 }, { -20, 0.3 }, { 0, 0.5 } }), nil)
end

-- an input-driven compressor or limiter: its input's 0 dB (Ref0)
do
  M.set("TestRef :: Limit", { controls = {}, aliases = {}, canvas = { kind = "limit", roles = { Input = 0, Ceiling = 1 }, rev = {}, ref0 = -14 } })
  M.set("TestRef0 :: Limit", { controls = {}, aliases = {}, canvas = { kind = "limit", roles = { Input = 0, Ceiling = 1 }, rev = {} } })
  M.save(); M.reload()
  local l = M.get("TestRef :: Limit")
  check("ref0: kept", l and l.canvas.ref0, -14)
  check("ref0: read", M.ref0(l.canvas), -14)
  check("ref0: a copy keeps it", M.copy(l).canvas.ref0, -14)
  check("ref0: -18 when unsaid", M.ref0(M.get("TestRef0 :: Limit").canvas), -18)
  check("ref0: not written when -18", M.get("TestRef0 :: Limit").canvas.ref0, nil)
  check("thr param: the input, with no threshold", select(2, M.thr_param(l.canvas)), true)
  M.remove("TestRef :: Limit"); M.remove("TestRef0 :: Limit"); M.save()
end

-- a dynamic EQ: each band's dynamics
do
  local ME = require("TS_CV_MapEQ")
  M.set("TestDyn :: EQ", { controls = {}, aliases = {}, canvas = { kind = "eq", bands = {
    { name = "Mid", freq = 1, gain = 2, learn = "x", learn_sig = "1,2,-,-,-",
      dyn = { thr = 5, range = 6, atk = 8, on = 10, rev = { range = true } } },
    { name = "High", freq = 3, gain = 4 } } } })
  M.save(); M.reload()
  local l = M.get("TestDyn :: EQ")
  local d = l and l.canvas.bands[1].dyn
  check("dyn EQ: kept", d and ("%s %s %s %s %s %s"):format(d.thr, d.range, tostring(d.ratio), d.atk, d.on, tostring(d.rev.range)),
    "5 6 nil 8 10 true")
  check("dyn EQ: a band without stays without", l and l.canvas.bands[2].dyn, nil)
  check("dyn EQ: learning untouched by it", l and M.band_sig(l.canvas.bands[1]), "1,2,-,-,-")
  check("dyn EQ: dynamic", l and M.band_dynamic(l.canvas.bands[1]), true)
  check("dyn EQ: a copy keeps it", M.copy(l).canvas.bands[1].dyn.range, 6)
  check("dyn EQ: its controls are the canvas's", M.canvas_params(l.canvas)[8], true)
  M.remove("TestDyn :: EQ"); M.save()
  -- guessed: Pro-Q-style numbered, and worded
  local g = ME.guess({ "Band 1 Frequency", "Band 1 Gain", "Band 1 Q", "Band 1 Dynamic Range", "Band 1 Dynamics Enabled",
                       "Band 1 Threshold", "Band 2 Frequency", "Band 2 Gain", "Band 2 Enabled" })
  check("dyn guess: the band's own On isn't its dynamics'", g[1] and ("%s %s %s %s"):format(g[1].freq, tostring(g[1].on),
    g[1].dyn and g[1].dyn.range, g[1].dyn and g[1].dyn.on), "0 nil 3 4")
  check("dyn guess: threshold", g[1] and g[1].dyn and g[1].dyn.thr, 5)
  check("dyn guess: a plain band stays plain", g[2] and ("%s %s"):format(g[2].on, tostring(g[2].dyn)), "8 nil")
  local g2 = ME.guess({ "Low Mid Freq", "Low Mid Gain", "Low Mid Thresh", "Low Mid Ratio", "Low Mid Attack", "Low Mid Release",
                        "Low Mid Auto Threshold" })
  check("dyn guess: worded", g2[1] and g2[1].dyn and ("%s %s %s %s"):format(g2[1].dyn.thr, g2[1].dyn.ratio, g2[1].dyn.atk,
    g2[1].dyn.rel), "2 3 4 5")
  -- what the probe measures, read where a band is heard
  local fr = { n = 30, f = {}, g = {}, lv = {} }
  for k = 1, 30 do fr.f[k] = 1000 * 2 ^ ((k - 17) / 3); fr.lv[k] = -150 end
  fr.g[17], fr.g[18] = 4, 2
  check("dyn: measured at a centre", ME.dev_at(fr, 1000), -4)
  checkf("dyn: between centres", function() local v = ME.dev_at(fr, 1000 * 2 ^ (1 / 6)); return v < -2.9 and v > -3.1 end)
  check("dyn: nothing measured is 0", ME.dev_at(fr, 100), 0)
  fr.lv[17], fr.lv[18] = -20, -20
  checkf("dyn: level in sums the bands", function() local v = ME.level_in(fr, 900, 1300); return v > -17.1 and v < -16.9 end)
  check("dyn: a bell's span", ("%.0f %.0f"):format(ME.dyn_span({ type = "bell", f = 1000, q = 1.414 })), "707 1414")
  check("dyn: a low shelf is heard below it", ME.dyn_focus({ type = "ls", f = 200 }), 100)
end

-- an EQ band's shape switch
do
  local ME = require("TS_CV_MapEQ")
  local SH = { "Peak", "Shelf" }
  local f0, s0, g0 = reaper.TrackFX_FormatParamValueNormalized, reaper.TrackFX_SetParamNormalized,
                     reaper.TrackFX_GetParamNormalized
  local set
  reaper.TrackFX_FormatParamValueNormalized = function(_, _, _, v) return true, SH[v < 0.5 and 1 or 2] end
  reaper.TrackFX_SetParamNormalized = function(_, _, p, v) set = { p, v } end
  reaper.TrackFX_GetParamNormalized = function() return 1 end
  local b = { freq = 1, gain = 2, shape = 3,
    learn = "Z=0.5;H=0,1;T1=bell,0;F1=0:100 1:10000;G1=0:-15 1:15;Q1=15:1;T2=ls,0;F2=0:100 1:10000;G2=0:-15 1:15;Q2=15:0.7" }
  local shs = ME.shapes(nil, 0, b)
  check("shapes: one per setting", shs and #shs, 2)
  check("shapes: learned as", shs and shs[2].type, "ls")
  check("shapes: label is the plugin's name", shs and ME.shape_label(shs[1]), "Peak  \u{00B7}  Bell")
  check("shapes: label says the learned kind", ME.shape_label({ s = 3, text = "", type = "hp", order = 2 }), "Low cut 12 dB/oct")
  check("shapes: label without repeating", ME.shape_label({ s = 1, text = "Bell", type = "bell" }), "Bell")
  check("shapes: band reads its setting", ME.read_band(nil, 0, b).s, 2)
  ME.set_shape(nil, 0, b, 1)
  check("shapes: set writes the switch", set and (set[1] .. ":" .. (set[2] + 0.0)), "3:0.0")
  check("shapes: none without a switch", ME.shapes(nil, 0, { freq = 1, learn = b.learn }), nil)
  reaper.TrackFX_FormatParamValueNormalized, reaper.TrackFX_SetParamNormalized,
    reaper.TrackFX_GetParamNormalized = f0, s0, g0
end

-- switched times: steps along the envelope
do
  local UN = require("TS_CV_Units")
  local rel = { "0.1 s", "0.3 s", "0.6 s", "1.2 s", "Auto" }
  local fmt = function(n) return rel[math.min(#rel, math.floor(n * #rel) + 1)] end
  local st = UN.time_steps(fmt, 1, 5000)
  check("steps: one per setting", st and #st, 5)
  checkf("steps: in time order", function()
    for i = 2, #st do if st[i].f <= st[i - 1].f then return false end end return true end)
  checkf("steps: Auto beyond the last", function() return st[5].f > st[4].f and st[5].f <= 1 end)
  check("steps: a setting's step", UN.step_at(st, st[3].norm).text, "0.6 s")
  check("steps: nearest", UN.step_near(st, 0.99).text, "Auto")
  check("steps: nearest low", UN.step_near(st, 0).text, "0.1 s")
  local seven = function(n) return tostring(math.floor(n * 6.999) + 1) end
  local s7 = UN.step_at(UN.time_steps(seven, 0.1, 500, true), 1)
  check("steps: reversed with no time", s7.text .. " " .. s7.f, "7 0.0")
  check("steps: a knob has none", UN.time_steps(function(n) return ("%.2f ms"):format(n * 300) end, 1, 5000), nil)
  -- a knob whose top reads Auto: still findable below it
  local kfmt = function(n) return n > 0.97 and "Auto" or ("%.1f ms"):format(10 + n * 990) end
  local n = UN.find_norm(kfmt, 500)
  checkf("find_norm: past a word at the end", function() return n and math.abs(UN.at(kfmt, n) - 500) < 2 end)
end

-- a reporting plugin's reduction, lined up with what its tap sees
do
  local Tr = require("TS_CV_Trace")
  local COLS = Tr.COLS
  local function make(own_c, rep_k, seed)
    math.randomseed(seed)
    local d = { mn = {}, mx = {}, ip = {}, gr = {} }
    local h = { gr = {} }
    local cur = 1500
    -- the plugin's reduction over time: hits that decay
    local red, r = {}, 0
    for c = 0, COLS - 1 do
      if math.random() < 0.02 then r = 6 + math.random() * 8 end
      r = r * 0.93
      red[c] = r
    end
    for c = 0, COLS - 1 do
      local lvl = 10 ^ ((-18 + math.random() * 6) / 20)           -- what goes in
      d.ip[(c - own_c) % COLS] = lvl                              -- early by its latency
      local out = lvl * 10 ^ (-(red[c]) / 20)
      d.mn[c], d.mx[c] = -out, out
      h.gr[(c - rep_k) % COLS] = red[c]                           -- its reports, early by rep_k
    end
    return h, d, cur
  end
  for _, case in ipairs({ { 12, 12 }, { 12, 0 }, { 0, 0 }, { 30, 30 } }) do
    local own_c, rep_k = case[1], case[2]
    local h, d, cur = make(own_c, rep_k, 7 + own_c + rep_k)
    Tr.realign(h, d, own_c, cur, 100)
    check(("gr align: latency %d, reports %d early"):format(own_c, rep_k), h.k, rep_k)
  end
  -- the input held back to sit on the output: by the plugin's latency when
  -- the copy skipped it, not at all when REAPER already delayed it
  for _, case in ipairs({ { 12, 12 }, { 12, 0 }, { 30, 30 } }) do
    local own_c, in_k = case[1], case[2]
    local _, d, cur = make(in_k, 0, 3 + own_c + in_k)
    -- give the music shape: louder hits the output follows
    local e = {}
    Tr.align_input(e, d, own_c, cur, 100)
    check(("input align: latency %d, input early by %d"):format(own_c, in_k), e.k, in_k)
  end
  -- reports that come LATE (a meter held back to when it's heard): found,
  -- and nothing read past the latest report
  do
    local h, d, cur = make(0, -40, 11)
    h.c = cur
    Tr.realign(h, d, 0, cur, 100)
    check("gr align: reports 40 late", h.k, -40)
  end
  -- silence: nothing to go on, nothing found
  local h = { gr = {} }
  local d = { mn = {}, mx = {}, ip = {}, gr = {} }
  Tr.realign(h, d, 12, 100, 100)
  check("gr align: silence finds nothing", h.k, nil)
end

os.remove("./TS_ChannelView_Mappings.ini")
os.remove("./TS_ChannelView_Mappings.bak.ini")
-- An EQ band learned on one side only (cuts, say) asked for its Q on the
-- other: the other side's shape, not a crash.
do
  local ME = require("TS_CV_MapEQ")
  local Q = { { -12, 0.9 }, { -6, 0.8 }, { -3, 0.7 } }
  local ok, q = pcall(ME.q_at, Q, 4)
  check("q_at: boost with only cuts learned", ok and q ~= nil and q > 0, true)
  ok, q = pcall(ME.q_at, { { 3, 1.2 }, { 9, 1.5 } }, -6)
  check("q_at: cut with only boosts learned", ok and q ~= nil and q > 0, true)
  check("q_at: one side each still scales", ME.q_at({ { -6, 1 }, { -12, 2 }, { 6, 0.5 } }, 6) ~= nil, true)
end

-- MIDI learn: the mode a controller's values suggest, and the binding it
-- writes (REAPER's own param.<p>.learn.*).
do
  local ML = require("TS_CV_MidiLearn")
  check("learn: an encoder (1 / 127)", ML.guess_mode({ 1, 1, 127, 1, 127 }), 1)
  check("learn: an encoder one way so far", ML.guess_mode({ 1, 1, 2, 1 }), 1)
  check("learn: a 63 / 65 encoder", ML.guess_mode({ 65, 65, 63, 65 }), 2)
  local sweep = {}
  for v = 40, 80, 3 do sweep[#sweep + 1] = v end
  check("learn: a sweeping knob", ML.guess_mode(sweep), 0)
  -- what counts as a control moved: CCs (not 120..127), notes on, program
  -- change, pitch bend; a note off and All Notes Off don't
  local function cof(...) local a, b, c = ML.control_of(string.char(...)); return a and ("%d %d %d"):format(a, b, c) or "nil" end
  check("learn: a CC", cof(0xB0, 21, 65), "176 21 65")
  check("learn: a footswitch's note", cof(0x90, 59, 127), "144 59 127")
  check("learn: its note off isn't", cof(0x80, 59, 0), "nil")
  check("learn: nor a note on at 0", cof(0x90, 59, 0), "nil")
  check("learn: All Notes Off isn't", cof(0xBF, 123, 127), "nil")
  check("learn: a program change", cof(0xC2, 5), "194 5 5")
  check("learn: pitch bend", cof(0xE0, 0, 64), "224 0 64")
  check("learn: shown as a note", ML._cc_text(0x90, 59), "Note 59 \u{00B7} ch 1")
  check("learn: too little to tell", ML.guess_mode({ 64 }), nil)
  local saved_g, saved_s = reaper.TrackFX_GetNamedConfigParm, reaper.TrackFX_SetNamedConfigParm
  local cfgs = {}
  reaper.TrackFX_GetNamedConfigParm = function(_, _, k) if cfgs[k] then return true, cfgs[k] end return false, "" end
  reaper.TrackFX_SetNamedConfigParm = function(_, _, k, v) cfgs[k] = v; return true end
  check("learn: nothing linked", ML.binding(0, 0, 5), nil)
  ML.link(0, 0, 5, 0xB0, 21, 1, 1)
  local b = ML.binding(0, 0, 5)
  check("learn: linked CC", b and b.cc, 21)
  check("learn: its channel byte", b and b.status, 0xB0)
  check("learn: Relative 1, selected track", b and (b.mode .. "/" .. b.flags), "1/1")
  ML.unlink(0, 0, 5)
  check("learn: removed", ML.binding(0, 0, 5), nil)
  -- the track probe and the learn copies never become the touched parameter
  local saved_n = reaper.TrackFX_GetFXName
  local fxn = { [0] = "VST3: Pro-C 3 (FabFilter)", [1] = "JS: TS_TrackProbe", [2] = "Probe (renamed)" }
  reaper.TrackFX_GetFXName = function(_, a) return true, fxn[a] end
  cfgs = { fx_ident = "TS_TrackAnalyser/TS_TrackProbe.jsfx" }
  check("learn: a probe is a helper", ML._is_helper(0, 1), true)
  check("learn: a renamed probe too", ML._is_helper(0, 2), true)
  cfgs = {}
  check("learn: a plugin isn't", ML._is_helper(0, 0), false)
  -- TS_CV_ProbeLink: names follow a track that moves, and come off the
  -- block it left; an old probe (more than REAPER's 3 parameters) is told
  -- by its sliders
  do
    local PLx = require("TS_CV_ProbeLink")
    local sv = { reaper.GetMediaTrackInfo_Value, reaper.GetTrackGUID, reaper.gmem_read, reaper.gmem_write,
                 reaper.gmem_attach, reaper.ValidatePtr2, reaper.TrackFX_GetNumParams, reaper.TrackFX_GetFXGUID,
                 reaper.TrackFX_GetParam, reaper.TrackFX_SetParam }
    local gm, num, prm = {}, 5, {}
    reaper.GetMediaTrackInfo_Value = function(_, k) if k == "IP_TRACKNUMBER" then return num end return 0 end
    reaper.GetTrackGUID = function() return "{T}" end
    reaper.gmem_read = function(i) return gm[i] or 0 end
    reaper.gmem_write = function(i, v) gm[i] = v end
    reaper.gmem_attach = function() end
    reaper.ValidatePtr2 = function() return true end
    reaper.TrackFX_GetNumParams = function(_, a) return a == 100 and 57 or 3 end
    reaper.TrackFX_GetFXGUID = function(_, a) return "{FX" .. a .. "}" end
    reaper.TrackFX_GetParam = function(_, a, p) return prm[a .. ":" .. p] or 0 end
    reaper.TrackFX_SetParam = function(_, a, p, v) prm[a .. ":" .. p] = v end
    local tr = {}
    local b5 = 0x100000 + 5 * 128
    PLx.name(tr, 0, 0x2000015)
    check("probe link: names in the block", gm[b5] .. " " .. gm[b5 + 1], "1 " .. (0x2000015 + 1))
    PLx.set(tr, 0x2000015, "tap_n", 1, 2)
    num = 8                                   -- the track moved down
    local moved = PLx.tick()
    local b8 = 0x100000 + 8 * 128
    check("probe link: a move is reported", moved and #moved, 1)
    check("probe link: names follow", gm[b8] .. " " .. gm[b8 + 1], "1 " .. (0x2000015 + 1))
    check("probe link: off the old block", gm[b5] .. " " .. gm[b5 + 1] .. " " .. gm[b5 + 8], "0 0 0")
    PLx.set(tr, 100, "lag", 2, 64)            -- an old probe: its slider
    check("probe link: old probe's slider", prm["100:7"], 64)
    check("probe link: new probe readings", (function() gm[b8 + 64 + 1] = 4.5; return PLx.get(tr, 0, "gr", 2) end)(), 4.5)
    PLx.forget(tr)
    reaper.GetMediaTrackInfo_Value, reaper.GetTrackGUID, reaper.gmem_read, reaper.gmem_write,
      reaper.gmem_attach, reaper.ValidatePtr2, reaper.TrackFX_GetNumParams, reaper.TrackFX_GetFXGUID,
      reaper.TrackFX_GetParam, reaper.TrackFX_SetParam = table.unpack(sv, 1, 10)
  end
  reaper.TrackFX_GetFXName = saved_n
  reaper.TrackFX_GetNamedConfigParm, reaper.TrackFX_SetNamedConfigParm = saved_g, saved_s
end

-- TDR Slick EQ: a gain whose readout has no unit ("0.0") but whose
-- settings read in dB ("+18.0 dB") is read from the plugin, not the
-- learned table (which lost its boosts); a learned boost that fitted
-- another shape is kept; a switched Q steps a position a notch.
do
  local ME = require("TS_CV_MapEQ")
  local saved = {}
  for _, k in ipairs({ "TrackFX_GetFormattedParamValue", "TrackFX_FormatParamValueNormalized", "TrackFX_GetParamNormalized",
                       "TrackFX_SetParamNormalized", "TrackFX_GetFXGUID", "TrackFX_GetParameterStepSizes" }) do saved[k] = reaper[k] end
  local V = { [0] = 0.75, [1] = 0.5, [2] = 0.0 }
  reaper.TrackFX_GetFXGUID = function() return "{SLICK}" end
  reaper.TrackFX_GetParamNormalized = function(_, _, p) return V[p] or 0 end
  reaper.TrackFX_SetParamNormalized = function(_, _, p, v) V[p] = v end
  reaper.TrackFX_GetParameterStepSizes = function() return false end
  reaper.TrackFX_GetFormattedParamValue = function(_, _, p)
    if p == 0 then return true, ("%.1f"):format(-18 + 36 * V[0]) end
    if p == 1 then return true, ("%.0f Hz"):format(100 * 100 ^ V[1]) end
    return true, (V[2] >= 0.5) and "Wide" or "Narrow"
  end
  reaper.TrackFX_FormatParamValueNormalized = function(_, _, p, n)
    if p == 0 then return true, ("%.1f dB"):format(-18 + 36 * n) end
    if p == 1 then return true, ("%.0f Hz"):format(100 * 100 ^ n) end
    return true, (n >= 0.5) and "Wide" or "Narrow"
  end
  -- cuts only learned, as Slick EQ's mid band
  local L = { Z = 0.5, shapes = { { type = "bell", F = { { 0, 100 }, { 1, 10000 } },
    G = { { 0, -15.6 }, { 0.25, -7.6 }, { 0.5, 0 } }, Q = { { -15.6, 0.94 }, { -7.6, 0.86 } }, R = {} } } }
  local b = { name = "Mid", freq = 1, gain = 0, q = 2, learn = ME.encode(L) }
  local r = ME.read_band(0, 0, b)
  check("slick: a boost reads from the plugin's dB", r and math.abs((r.g or 0) - 9) < 0.01, true)
  -- learning keeps a boost whose shape fitted another type
  local samples = {
    { s = 1, fn = 0.5, gn = 0, fit = { type = "bell", f = 1000, g = -15, q = 0.9 } },
    { s = 1, fn = 0.5, gn = 0.25, fit = { type = "bell", f = 1000, g = -7.5, q = 0.85 } },
    { s = 1, fn = 0.5, gn = 1, fit = { type = "ls", f = 400, g = 9, q = 0.7 } },
  }
  local Ls = ME.summarise(samples, { kind = "eq", Z = 0.5, has_freq = true })
  local Gs = Ls and Ls.shapes[1] and Ls.shapes[1].G or {}
  local boost
  for _, pt in ipairs(Gs) do if pt[1] == 1 then boost = pt[2] end end
  check("slick: a boost that fitted another shape is kept", boost, 9)
  check("slick: the band stays a bell", Ls.shapes[1].type, "bell")
  -- a switched Q
  local qp = ME.q_positions(0, 0, b)
  check("slick: a Q switch has its positions", qp and #qp, 2)
  ME.nudge_q(0, 0, b, 0.02)
  check("slick: one wheel notch flips it", V[2] >= 0.5, true)
  ME.nudge_q(0, 0, b, 0.02)
  check("slick: and stops at the end", V[2] >= 0.5, true)
  ME.nudge_q(0, 0, b, -0.02)
  check("slick: one notch back", V[2] < 0.5, true)
  ME.set_q_pos(0, 0, b, 2)
  check("slick: picked from the list", ME.q_index(0, 0, b, qp), 2)
  for _, k in ipairs({ "JS_Window_SetFocus", "JS_Window_FindChildByID", "GetMainHwnd",
                       "SetCursorContext", "NamedCommandLookup" }) do reaper[k] = saved[k] end
end

-- The delay canvas's headroom: a tap turned up past unity (ReaDelay's
-- volume in dB) draws the canvas to 2, so its dot stays on the canvas.
do
  local DLY = require("TS_CV_Delay")
  check("delay: headroom 1 at unity", DLY.headroom({ echoes = { { l = 1, r = 0.5 } }, handles = {} }), 1)
  check("delay: headroom 2 over unity", DLY.headroom({ echoes = { { l = 1.6, r = 0 } }, handles = {} }), 2)
  check("delay: a handle over unity counts", DLY.headroom({ echoes = {}, handles = { { side = "L", h = 1.9 } } }), 2)
end

-- A stepped knob follows a slow drag. The plugin reports its value back
-- each frame already on a step; a drag that started again from there every
-- frame would lose every move under half a step and never get anywhere.
-- The drag's own running position is kept until the button lets go.
do
  local CC = require("TS_CV_Config")
  local down, dy, wheel = true, -3, 0
  local fake = setmetatable({
    GetMouseDelta = function() return 0, dy end,
    GetMouseWheel = function() return wheel end,
    GetMousePos = function() return 0, 0 end,
    GetCursorScreenPos = function() return 0, 0 end,
    GetWindowDrawList = function() return "dl" end,
    InvisibleButton = function() return false end,
    IsItemActive = function() return down end,
    IsItemHovered = function() return true end,
    IsItemClicked = function() return false end,
    IsMouseDown = function() return down end,
    IsMouseDoubleClicked = function() return false end,
    IsItemActivated = function() return false end,
    GetKeyMods = function() return 0 end,
    CalcTextSize = function() return 6, 10 end,
  }, { __index = function(_, key)
    if key:find("Flags_") or key:find("MouseButton_") or key:find("MouseCursor_") or key:find("^Mod_") then return 1 end
    return function() end
  end })
  W.attach(fake)
  local had = reaper.new_array
  reaper.new_array = function() return {} end
  local ok, err = pcall(function()
    local v, moves = 0, 0
    for _ = 1, 40 do
      local ch, nv = W.knob("ctx", "##stp", "Slope", v, "", { step_norm = 0.25 })
      if ch then v, moves = nv, moves + 1 end
    end
    check("stepped: a slow drag walks up the steps", v, 0.75)
    check("stepped: one change per step", moves, 3)
    -- the plugin's own choices, unevenly placed: only those are landed on
    down = false; W.knob("ctx", "##stp", "Slope", 0, "", { step_norm = 0.01 })
    down = true; v = 0
    local seen = {}
    for _ = 1, 60 do
      local ch, nv = W.knob("ctx", "##stp", "Slope", v, "", { step_norm = 0.01, snaps = { 0, 0.34, 0.67, 1 } })
      if ch then v = nv; seen[#seen + 1] = nv end
    end
    check("stepped: lands only on the choices", table.concat(seen, ","), "0.34,0.67,1")
    -- letting go forgets the drag; the wheel steps one choice a notch
    down = false; wheel = -1
    local ch, nv = W.knob("ctx", "##stp", "Slope", 0.67, "", { snaps = { 0, 0.34, 0.67, 1 } })
    check("stepped: wheel down one choice", ch and nv, 0.34)
    wheel = 0
    -- a plain knob over a plugin that rounds its own value still moves
    down = true; v = 0
    for _ = 1, 30 do
      local ch2, nv2 = W.knob("ctx", "##pln", "Gain", v, "")
      if ch2 then v = math.floor(nv2 * 10 + 0.5) / 10 end
    end
    check("knob: a rounding plugin still follows a slow drag", v >= 0.5, true)
  end)
  check("stepped: drag sim ran", ok and true or err, true)
  reaper.new_array = had
end

-- a value arc in a colour of its own: drawn in it, through W.knob
do
  local strokes = {}
  local fake = setmetatable({
    GetMouseDelta = function() return 0, 0 end, GetMouseWheel = function() return 0 end,
    GetMousePos = function() return 0, 0 end, GetCursorScreenPos = function() return 0, 0 end,
    GetWindowDrawList = function() return "dl" end, InvisibleButton = function() return false end,
    IsItemActive = function() return false end, IsItemHovered = function() return false end,
    IsItemClicked = function() return false end, IsMouseDown = function() return false end,
    IsMouseDoubleClicked = function() return false end, IsItemActivated = function() return false end,
    GetKeyMods = function() return 0 end, CalcTextSize = function() return 6, 10 end,
    DrawList_PathStroke = function(_, col) strokes[#strokes + 1] = col end,
  }, { __index = function(_, key)
    if key:find("Flags_") or key:find("MouseButton_") or key:find("MouseCursor_") or key:find("^Mod_") then return 1 end
    return function() end
  end })
  W.attach(fake)
  local had = reaper.new_array
  reaper.new_array = function() return {} end
  local ok, err = pcall(function()
    for _, style in ipairs({ "skirted", "bar", "hifi" }) do
      strokes = {}
      W.knob("ctx", "##arcc", "Gain", 0.6, "", { arc = "pos", arc_col = 0x12345678, style = style })
      local seen = false
      for _, c in ipairs(strokes) do if c == 0x12345678 then seen = true end end
      check("arc colour: drawn on a " .. style .. " knob", seen, true)
    end
  end)
  check("arc colour: draw ran", ok and true or err, true)
  reaper.new_array = had
end

-- a modulator's ◯ dropped on an EQ node: which parameter by where it's let
-- go (either side: frequency, above or below: gain, on it: Q); a linked
-- way dragged moves the link's setting
do
  local CM = require("TS_CV_CanvasMod")
  local MR_ = require("TS_CV_ModRack")
  local MD_ = require("TS_CV_Mod")
  local mouse, released = { 0, 0 }, true
  local fake = setmetatable({
    GetMousePos = function() return mouse[1], mouse[2] end,
    IsMouseReleased = function() return released end,
    CalcTextSize = function() return 30, 10 end,
  }, { __index = function(_, key)
    if key:find("Flags_") or key:find("MouseButton_") or key:find("MouseCursor_") or key:find("^Mod_") then return 1 end
    return function() end
  end })
  CM.attach(fake)
  local lo = MD_.link_of
  MD_.link_of = function() return nil end
  local src = { guid = "{M}", col = 0xff0000ff, name = "LFO 1" }
  MR_.drag = { mod = src, k = 1, x = 0, y = 0 }
  local axes = { { key = "freq", param = 4, label = "Frequency" }, { key = "gain", param = 5, label = "Gain" },
                 { key = "q", param = 6, label = "Q" } }
  local node = { x = 100, y = 100, r = 5 }
  local function drop_at(x, y)
    mouse = { x, y }
    local req = {}
    CM.over("ctx", "dl", {}, { guid = "{E}", path_t = { 0 } }, node, axes, req)
    return req.mod_drop and req.mod_drop.param
  end
  check("node drop: left of it, frequency", drop_at(85, 100), 4)
  check("node drop: right of it, frequency", drop_at(115, 101), 4)
  check("node drop: above it, gain", drop_at(100, 85), 5)
  check("node drop: below it, gain", drop_at(99, 116), 5)
  check("node drop: on it, Q", drop_at(101, 101), 6)
  check("node drop: off it, nothing", tostring(drop_at(160, 160)), "nil")
  mouse = { 100, 85 }
  local req = {}
  CM.over("ctx", "dl", {}, { guid = "{E}", path_t = { 0 } }, node, axes, req)
  check("node drop: a gain link swings both ways", req.mod_drop and req.mod_drop.centre, true)
  -- a level line takes it anywhere along it, not off it
  local lnode = { x = 280, y = 100, r = 5, line = { 0, 300 } }
  local laxes = { { key = "thr", dir = "y", param = 9, label = "Threshold" } }
  local function line_drop(x, y)
    mouse = { x, y }
    local rq = {}
    CM.over("ctx", "dl", {}, { guid = "{E}", path_t = { 0 } }, lnode, laxes, rq)
    return rq.mod_drop and rq.mod_drop.param
  end
  check("line drop: far along it", line_drop(40, 103), 9)
  check("line drop: off it", tostring(line_drop(40, 120)), "nil")
  -- a button or a list on a canvas: a ◯ let go over it links it
  do
    local W3 = require("TS_CV_Widgets")
    local mc = W3.mod_corner_col
    local corner
    W3.mod_corner_col = function() corner = true end
    local lo3 = MD_.link_of
    MD_.link_of = function() return nil end
    MR_.drag = { mod = src, k = 1 }
    mouse = { 20, 15 }
    local rq = {}
    CM.rect("ctx", "dl", {}, { guid = "{E}", path_t = { 0 } }, rq, { 10, 10, 50, 26 }, 12, "Sync")
    check("button drop: over it, linked", rq.mod_drop and rq.mod_drop.param, 12)
    mouse = { 80, 15 }
    rq = {}
    CM.rect("ctx", "dl", {}, { guid = "{E}", path_t = { 0 } }, rq, { 10, 10, 50, 26 }, 12, "Sync")
    check("button drop: off it, nothing", tostring(rq.mod_drop), "nil")
    MR_.drag = nil
    local nt3 = MR_.note_target
    MR_.note_target = function() end
    MD_.link_of = function() return { macro = true, mod = src } end
    CM.rect("ctx", "dl", {}, { guid = "{E}", path_t = { 0 } }, {}, { 10, 10, 50, 26 }, 12, "Sync")
    check("button linked: its corner in the source's colour", corner, true)
    -- Alt-click on a linked one: unlinked, its own click left out
    local unl
    local ul3 = MD_.unlink
    MD_.unlink = function() unl = true end
    local km, mc3 = fake.GetKeyMods, fake.IsMouseClicked
    fake.GetKeyMods = function() return 1 end
    fake.IsMouseClicked = function() return true end
    mouse = { 20, 15 }
    local took = CM.rect("ctx", "dl", {}, { guid = "{E}", path_t = { 0 } }, {}, { 10, 10, 50, 26 }, 12, "Sync")
    check("button Alt-click: unlinked, its click left out", tostring(unl) .. " " .. tostring(took), "true true")
    fake.GetKeyMods, fake.IsMouseClicked, MD_.unlink = km, mc3, ul3
    MD_.link_of, W3.mod_corner_col, MR_.note_target = lo3, mc, nt3
  end
  -- a line or slot handle: its ghost and reach dots after it, so they win
  do
    local order = {}
    local lo4, rg4 = MD_.link_of, MD_.range
    MD_.link_of = function() return { macro = true, mod = src } end
    MD_.range = function() return 0.2, 0.8 end
    local W4 = require("TS_CV_Widgets")
    local t4, a4 = W4.tip, W4.allow_overlap
    W4.tip, W4.allow_overlap = function() end, function() end
    local nt4, nh4 = MR_.note_target, MR_.note_ctl_hover
    MR_.note_target, MR_.note_ctl_hover = function() end, function() end
    local ib, km4 = fake.InvisibleButton, fake.GetKeyMods
    fake.GetKeyMods = function() return 0 end
    fake.InvisibleButton = function(_, id) order[#order + 1] = id:match("^cm") and "dot" or "handle" end
    local ax4 = { key = "Release", dir = "x", param = 3, pos = function(v) return 10 + v * 100 end }
    CM.wrap("ctx", "dl", {}, { guid = "{E}" }, {}, "rel", { x = 40, y = 50, r = 5, late = true }, { ax4 },
      function() fake.InvisibleButton("ctx", "rel", 1, 1); return false, false, false end)
    check("slot handle: its dots submitted after it", order[1], "handle")
    fake.InvisibleButton, fake.GetKeyMods = ib, km4
    MD_.link_of, MD_.range, W4.tip, W4.allow_overlap, MR_.note_target, MR_.note_ctl_hover = lo4, rg4, t4, a4, nt4, nh4
  end
  -- a threshold's corner runs up the diagonal but drags up and down
  local diag = { key = "thr", dir = "path", along = "y", param = 9, pos = function(v) return 100 + v * 100, 200 - v * 100 end }
  -- a handle of two ways, one linked: its own drag still runs, the
  -- linked way named so it's left alone
  do
    local lo2, sl2, lv2 = MD_.link_of, MD_.shift_link, MD_.live
    local rg2 = MD_.range
    MD_.link_of = function(_, _, p) return (p == 4) and { macro = true, mod = src } or nil end
    MD_.shift_link, MD_.live = function() end, function() return 0.5 end
    local W2 = require("TS_CV_Widgets")
    local t2, a2 = W2.tip, W2.allow_overlap
    W2.tip, W2.allow_overlap = function() end, function() end
    local nt2, nh2 = MR_.note_target, MR_.note_ctl_hover
    MR_.note_target, MR_.note_ctl_hover = function() end, function() end
    fake.GetKeyMods = function() return 0 end
    fake.GetMouseDelta = function() return 0, 0 end
    local two = { { key = "t", dir = "x", param = 4, pos = function(v) return 100 + v * 100 end },
                  { key = "lv", dir = "y", param = 5, pos = function(v) return 200 - v * 100 end } }
    MD_.range = function() return 0.2, 0.8 end
    local _, _, dg, lk = CM.wrap("ctx", "dl", {}, { guid = "{E}" }, {}, "w2", { x = 150, y = 150, r = 5 }, two,
      function() return true, true, true end)
    check("two ways, one linked: its own drag runs", tostring(dg) .. " " .. tostring(lk.x) .. " " .. tostring(lk.y), "true true nil")
    MD_.link_of = function() return { macro = true, mod = src } end
    local _, _, dg2 = CM.wrap("ctx", "dl", {}, { guid = "{E}" }, {}, "w2", { x = 150, y = 150, r = 5 }, two,
      function() return true, true, true end)
    check("two ways, both linked: its own drag left out", dg2, false)
    MD_.link_of, MD_.shift_link, MD_.live, MD_.range = lo2, sl2, lv2, rg2
    W2.tip, W2.allow_overlap, MR_.note_target, MR_.note_ctl_hover = t2, a2, nt2, nh2
  end
  check("line drag: by its height only", math.floor(CM.v_at(diag, 0, 150, nil, 0) * 1000 + 0.5) / 1000, 0.5)
  MR_.drag = nil
  -- dragging a linked way: the link's setting moves, by the pixels' worth
  local moved
  local sl, lv = MD_.shift_link, MD_.live
  MD_.link_of = function(_, _, p) return (p == 4) and { mod = src } or nil end
  MD_.live = function() return 0.5 end
  MD_.shift_link = function(_, _, d) moved = d end
  local ax = { key = "freq", param = 4, pos = function(v) return 100 + v * 200 end }
  check("node drag: a linked way taken care of", CM.shift({}, { guid = "{E}" }, ax, 20), true)
  check("node drag: by its own scale", math.floor(moved * 1000 + 0.5) / 1000, 0.1)
  check("node drag: an unlinked way left to the canvas", CM.shift({}, { guid = "{E}" }, { key = "gain", param = 5, pos = function() return 0 end }, 0, 20), false)
  -- the ghost and the reach stay put while the source moves the node
  local W_ = require("TS_CV_Widgets")
  local tip, ao, nt, nh, rg = W_.tip, W_.allow_overlap, MR_.note_target, MR_.note_ctl_hover, MD_.range
  W_.tip, W_.allow_overlap = function() end, function() end
  MR_.note_target, MR_.note_ctl_hover = function() end, function() end
  MD_.range = function() return 0.2, 0.8 end
  MD_.link_of = function(_, _, p) return (p == 4) and { macro = true, mod = src } or nil end
  local drawn
  fake.GetKeyMods = function() return 0 end
  fake.IsItemHovered = function() return false end
  fake.IsItemActive = function() return false end
  mouse = { 0, 0 }
  fake.DrawList_AddCircle = function(_, x, y) drawn[#drawn + 1] = math.floor(x + 0.5) .. "," .. math.floor(y + 0.5) end
  fake.DrawList_AddLine = function(_, x1, y1, x2, y2) drawn[#drawn + 1] = math.floor(x2 + 0.5) .. "," .. math.floor(y2 + 0.5) end
  local function handles(nx)
    drawn = {}
    MD_.live = function() return 0.25 end   -- read a moment apart from the node
    CM.under("ctx", "dl", {}, { guid = "{E}" }, "n", { x = nx, y = 100, r = 5 }, { ax })
    return table.concat(drawn, " ")
  end
  local h1 = handles(150)
  check("node mod: ghost at its setting, line to the reach", h1:match("^140,100 260,100") ~= nil, true)
  check("node mod: handles stay put as the node moves", handles(230), h1)
  -- a reach past the canvas's edge is kept inside it, so it can be grabbed
  MD_.range = function() return 0.2, 1.4 end
  drawn = {}
  CM.under("ctx", "dl", {}, { guid = "{E}" }, "n", { x = 150, y = 100, r = 5, box = { 100, 50, 300, 150 } }, { ax })
  check("node mod: a reach past the edge kept inside", drawn[2], "293,100")
  -- a linked Q: an arc round it, its ends dragged round
  local function q(x, y) return math.floor(CM.q_at(0, 0, x, y) * 100 + 0.5) / 100 end
  check("node Q: straight up is half way", q(0, -10), 0.5)
  check("node Q: bottom left is the start", q(-10, 10), 0)
  check("node Q: bottom right is the end", q(10, 10), 1)
  check("node Q: in the gap, the nearer end", q(1, 10) .. " " .. q(-1, 10), "1.0 0.0")
  local set
  MD_.range = function() return 0.25, 0.75 end
  local sr = MD_.set_range
  MD_.set_range = function(_, _, a, b) set = { a, b } end
  MD_.link_of = function(_, _, p) return (p == 6) and { macro = true, mod = src } or nil end
  fake.IsItemActive = function() return true end
  fake.IsMouseDown = function() return true end
  mouse = { 100, 80 }   -- straight above the node: half way
  local okq, eq = pcall(CM.under, "ctx", "dl", {}, { guid = "{E}" }, "n", { x = 100, y = 100, r = 5, box = { 0, 0, 300, 300 } },
    { { key = "q", param = 6, label = "Q" } })
  check("node Q: drawn", okq or eq, true)
  check("node Q: dragged round sets its end", set and (set[1] .. " " .. set[2]), "0.25 0.5")
  -- a reach the canvas pins to its edge (a gain past its range) still moves
  local pinned = { key = "freq", param = 4, pos = function(v) return math.max(50, math.min(150, 100 + (v - 0.5) * 400)) end }
  local function r3(v) return v and math.floor(v * 1000 + 0.5) / 1000 end
  check("node mod: dragged to a place, the value there", r3(CM.v_at(pinned, 140, nil, 1)), 0.6)
  check("node mod: past the edge, it stays where it is", r3(CM.v_at(pinned, 170, nil, 1)), 1)
  MD_.range = function() return 0.5, 1.0 end
  MD_.link_of = function(_, _, p) return (p == 4) and { macro = true, mod = src } or nil end
  set = nil
  mouse = { 130, 100 }
  CM.under("ctx", "dl", {}, { guid = "{E}" }, "n", { x = 100, y = 100, r = 5, box = { 0, 0, 300, 300 } }, { pinned })
  check("node mod: a reach pinned at the edge drags in", set and r3(set[2]), 0.575)
  fake.IsItemActive, fake.IsMouseDown, MD_.set_range = function() return false end, nil, sr
  W_.tip, W_.allow_overlap, MR_.note_target, MR_.note_ctl_hover, MD_.range = tip, ao, nt, nh, rg
  MD_.link_of, MD_.shift_link, MD_.live = lo, sl, lv
end

-- The TS_CV Trimmer: the trim rule, Auto trim over items, where it goes,
-- the filters' curve, and the panel's shape.
do
  local TR = require("TS_CV_Trimmer")
  local function near(a, b) return a and math.abs(a - b) < 0.01 end
  -- RMS -24 (plain) wants the average on -18 (sine-calibrated, so -21.01
  -- plain): +2.99; the peak at -12 against -6 allows +6, so +2.99
  check("trim: the average decides", near(TR.trim_for(-24, -12, -18, -6), 2.99), true)
  -- a peaky source: peak -8 allows only +2
  check("trim: the ceiling decides", near(TR.trim_for(-30, -8, -18, -6), 2), true)
  check("trim: clamped to +24", TR.trim_for(-90, -80, -18, -6), 24)
  check("trim: nothing to go on", TR.trim_for(nil, nil, -18, -6), nil)
  -- items: the loudest decides, item volume comes off
  local t = TR.trim_from_items({ { rms = 6, pk = 9, vol = 0 }, { rms = 3, pk = 8, vol = 0 }, { rms = 10, pk = 2, vol = -2 } })
  check("auto: the item needing least gain wins", t, 3)
  check("auto: item volume counts", TR.trim_from_items({ { rms = 5, pk = 9, vol = 3 } }), 2)
  check("auto: no items", TR.trim_from_items({}), nil)
  -- the part of the source that plays, inside a time selection
  local s, e = TR.source_bounds(10, 4, 1, 1)
  check("bounds: whole item", s == 1 and e == 5, true)
  s, e = TR.source_bounds(10, 4, 1, 2, 12, 20)
  check("bounds: time selection, playrate 2", s == 5 and e == 9, true)
  check("bounds: outside the selection", TR.source_bounds(10, 4, 0, 1, 20, 30), nil)
  -- the curve: -3 dB at each corner, off is flat, 24 dB/oct an octave down
  check("curve: low cut corner -3 dB", near(TR.response_db(100, 100, 4, 18000, 0, 48000), -3.01), true)
  check("curve: off is flat", TR.response_db(30, 100, 0, 18000, 0, 48000), 0)
  check("curve: 24 dB/oct an octave down", math.abs(TR.response_db(50, 100, 4, 18000, 0, 48000) + 24.1) < 0.2, true)
  check("curve: high cut corner -3 dB", near(TR.response_db(5000, 20, 0, 5000, 2, 48000), -3.01), true)
  -- where it goes: after ARA, the pre probe and the modulators
  check("slot: empty chain", TR.slot_in({}, false), 0)
  check("slot: after the pre probe and modulators",
    TR.slot_in({ "JS: TS_TrackProbe", "JS: ChannelView Modulators", "VST3: Pro-Q 3", "JS: TS_TrackProbe" }, false), 2)
  check("slot: after ARA", TR.slot_in({ "VST3: Melodyne", "JS: TS_TrackProbe", "VST3: Pro-Q 3" }, true), 2)
  check("is: by its name", TR.is("JS: TS_CV Trimmer") and not TR.is("JS: TS_TrackProbe"), true)
  -- each filter is off at the end of its range; the slopes have no Off
  check("filters: low cut off at 20 Hz", TR.lc_on(20) or TR.order(TR.lc_on(20), 3), 0)
  check("filters: low cut on above it", TR.order(TR.lc_on(21), 3), 4)
  check("filters: high cut off at 20 kHz", TR.order(TR.hc_on(20000), 0), 0)
  check("filters: 6 dB/oct is first order", TR.order(true, 0), 1)
  check("filters: 48 dB/oct is eighth", TR.order(true, #TR.SLOPES - 1), 8)
  check("filters: no Off in the slopes", TR.SLOPES[1], "6 dB/oct")
  local U_ = require("TS_CV_Util")
  check("name: Trimmer in ChannelView", U_.fx_label({ name = "JS: TS_CV Trimmer" }), "Trimmer")
  check("name: an alias still wins", U_.fx_label({ name = "JS: TS_CV Trimmer", alias = "Vox in" }), "Vox in")

  local TRP = require("TS_CV_TrimmerPanel")
  local C_ = require("TS_CV_Config")
  local tall = 6 * C_.CELL_H
  check("panel: six rows is one column", TRP.width(tall), TRP.COL_W)
  check("panel: three rows goes wide", TRP.width(3 * C_.CELL_H), TRP.COL_W * 2 + C_.PANEL_PAD)
  local L = TRP.layout(0, 0, TRP.COL_W, tall - C_.HEADER_H - C_.FOOTER_H)
  check("panel: column filters under the trims", L.filt[2] > L.trims[2] and L.filt[4] >= TRP.SPEC_MIN, true)
  L = TRP.layout(0, 0, TRP.COL_W * 2 + C_.PANEL_PAD, 3 * C_.CELL_H - C_.HEADER_H - C_.FOOTER_H)
  check("panel: wide filters beside", L.filt[1] >= TRP.COL_W and L.meters[4] >= 34, true)
  check("vu: 0 VU sits at its place on the scale", math.abs(TRP.vu_pos(0) - 0.6857) < 0.01, true)
  check("vu: the ends", TRP.vu_pos(-40) == 0 and TRP.vu_pos(10) == 1, true)
end

-- A button's own colour style over the bar's.
do
  local TBx = require("TS_CV_Toolbar")
  local items = TBx.parse("40001|cv:play|Play|#4aa3df/ui;40002||Stop|#c8453c/n;40003||Rec|#d98a2f;[|cv:x|M|#8a5cc2/i;40004||A;]")
  check("cs: both", items[1].cs, "ui")
  check("cs: neither", items[2].cs, "")
  check("cs: as the bar", items[3].cs, nil)
  check("cs: a menu's", items[4].cs, "i")
  check("cs: label kept", items[1].label .. "," .. items[2].label, "Play,Stop")
  check("cs: round trip", TBx.serialize(items),
    "40001|cv:play|Play|#4aa3df/ui;40002||Stop|#c8453c/n;40003||Rec|#d98a2f;[|cv:x|M|#8a5cc2/i;40004||A;]")
  check("cs: no colour, nothing stored", TBx.serialize({ { cmd = "1", icon = "", label = "", cs = "i" } }), "1||")
  TBx.cstyle = "u"
  local u, i = TBx.cstyle_of(items[3]); check("cs: bar underline", tostring(u) .. tostring(i), "truefalse")
  u, i = TBx.cstyle_of(items[1]); check("cs: own both", tostring(u) .. tostring(i), "truetrue")
  local DRx = require("TS_CV_Drawers")
  local web = DRx.to_web(items)
  check("cs: to the web", web[1].cs == "ui" and web[3].cs == nil, true)
  check("cs: back from the web", DRx.from_web(web)[2].cs, "")
end

-- Plugin and FX chain buttons on the action bars.
do
  local FB = require("TS_CV_FXButtons")
  local TBx = require("TS_CV_Toolbar")
  local id = "VST3: Pro-Q 3 (FabFilter) | odd;name~"
  local cmd = FB.fx_cmd(id)
  check("fxb: no bar separators in the command", cmd:find("[|;~]") == nil, true)
  local k, w = FB.kind({ cmd = cmd })
  check("fxb: reads back", k == "fx" and w == id, true)
  local back = TBx.parse(TBx.serialize({ { cmd = cmd, icon = "cv:fx_eq", label = "Pro-Q" } }))
  check("fxb: survives the stored line", select(2, FB.kind(back[1])), id)
  local ck, cw = FB.kind({ cmd = FB.chain_cmd("Vocals\\Lead.RfxChain") })
  check("fxb: a chain", ck == "chain" and cw == "Vocals\\Lead.RfxChain", true)
  check("fxb: not an action", FB.kind({ cmd = "40001" }), nil)
  check("fxb: short name", FB.short("fx", "VST3: Pro-Q 3 (FabFilter)"), "Pro-Q 3")
  check("fxb: short, two groups", FB.short("fx", "VST: ValhallaRoom (Valhalla DSP, LLC) (32 out)"), "ValhallaRoom")
  check("fxb: short chain", FB.short("chain", "Vocals\\Lead Vox.RfxChain"), "Lead Vox")
  check("fxb: icon eq", FB.icon_for("fx", "VST3: Pro-Q 3 (FabFilter)"), "cv:fx_eq")
  check("fxb: icon comp", FB.icon_for("fx", "VST3: FET Mk II (Softube)"), "cv:fx_comp")
  check("fxb: icon reverb", FB.icon_for("fx", "VST: ValhallaRoom (Valhalla DSP, LLC)"), "cv:fx_reverb")
  check("fxb: icon instrument by format", FB.icon_for("fx", "VST3i: Kontakt 7 (Native Instruments)"), "cv:fx_instrument")
  check("fxb: icon de-esser before dynamics", FB.icon_for("fx", "VST3: Pro-DS (FabFilter)", { "Dynamics" }), "cv:fx_deesser")
  check("fxb: icon by category", FB.icon_for("fx", "VST3: Thing (Acme)", { "Delay" }), "cv:fx_delay")
  check("fxb: icon chain", FB.icon_for("chain", "x"), "cv:fx_chain")
  check("fxb: unknown, no icon", FB.icon_for("fx", "VST3: Wobbulator (Acme)"), nil)
  -- where it goes with nothing selected: the end, before a post probe,
  -- never ahead of what stays first
  check("fxb: end of the chain", FB.end_gap({ "A", "B" }, 0), 2)
  check("fxb: before the post probe", FB.end_gap({ "JS: TS_TrackProbe", "A", "JS: TS_TrackProbe" }, 1), 2)
  check("fxb: after the Trimmer in an empty chain", FB.end_gap({ "JS: TS_CV Trimmer" }, 1), 1)
  local it = FB.fx_item({ ident = "VST3: Pro-Q 3 (FabFilter)", name = "VST3: Pro-Q 3 (FabFilter)", short = "Pro-Q 3" })
  check("fxb: a new button", it.label == "Pro-Q 3" and it.icon == "cv:fx_eq" and FB.kind(it) == "fx", true)
end

-- Vendors (TS_CV_Vendors): a plugin's vendor from its name, initials, the
-- stored line, and how a plugin button shows with a vendor's look.
do
  local VN = require("TS_CV_Vendors")
  check("vn: vendor", VN.of_name("VST3: Pro-Q 3 (FabFilter)"), "FabFilter")
  check("vn: channels skipped", VN.of_name("VST: ValhallaRoom (Valhalla DSP, LLC) (32 out)"), "Valhalla DSP")
  check("vn: 4ch skipped", VN.of_name("VST3: Thing (Acme) (4ch)"), "Acme")
  check("vn: nested brackets", VN.of_name("VST3: UADx 1176 (Universal Audio (UADx))"), "Universal Audio")
  check("vn: Inc. dropped", VN.of_name("VST3: Ozone 11 (iZotope, Inc.)"), "iZotope")
  check("vn: none", VN.of_name("JS: TS_CV Trimmer"), nil)
  check("vn: initials, capitals", VN.initials("IK Multimedia"), "IKM")
  check("vn: initials, camel", VN.initials("FabFilter"), "FF")
  check("vn: initials, lower", VN.initials("sonible"), "SON")
  local l = VN.parse("FabFilter|#4AA3DF|FF|mono;Waves|bad|W|nonsense;|#000000|x|fill")
  check("vn: parsed", #l .. l[1].color .. l[1].look .. tostring(l[2].color) .. l[2].look, "2#4aa3dfmononilnone")
  check("vn: written", VN.serialize(l), "FabFilter|#4aa3df|FF|mono;Waves||W|none")
  check("vn: no separators in a field", VN.serialize({ { name = "A;B|C", init = "x|y", look = "none" } }), "ABC||xy|none")
  local v = { color = "#4aa3df", init = "FF", look = "prefix" }
  check("vn: prefix", VN.apply({}, "Pro-Q 3", v).label, "FF - Pro-Q 3")
  check("vn: prefix once", VN.apply({}, "FF - Pro-Q 3", v).label, "FF - Pro-Q 3")
  check("vn: vendor colour", VN.apply({}, "x", v).color, "#4aa3df")
  check("vn: own colour wins", VN.apply({ color = "#c8453c" }, "x", v).color, "#c8453c")
  v.look = "mono"
  check("vn: tile", VN.apply({ icon = "cv:fx_eq" }, "x", v).mono, "FF")
  check("vn: no tile over a PNG", VN.apply({ icon = "eq.png" }, "x", v).mono, nil)
  v.look = "fill"
  check("vn: fill", VN.apply({}, "x", v).fill, true)
  check("vn: no vendor, as it is", VN.apply({ color = "#111111" }, "x", nil).color, "#111111")
  -- a button's own look over its vendor's
  check("vn: own look", VN.apply({ vo = "prefix" }, "Pro-Q 3", v).label, "FF - Pro-Q 3")
  check("vn: own look, not the vendor's", tostring(VN.apply({ vo = "prefix" }, "x", v).fill), "false")
  check("vn: own tile", VN.apply({ vo = "mono" }, "x", v).mono, "FF")
  local off = VN.apply({ vo = "off" }, "Pro-Q 3", v)
  check("vn: no vendor look", tostring(off.color) .. tostring(off.fill) .. off.label, "nilfalsePro-Q 3")
  -- stored, and new vendors getting a colour not yet taken
  local store = {}
  local gx, sx = reaper.GetExtState, reaper.SetExtState
  reaper.GetExtState = function(a, b) return store[a .. "/" .. b] or "" end
  reaper.SetExtState = function(a, b, val) store[a .. "/" .. b] = val end
  VN.load(true)
  local a = VN.ensure("FabFilter")
  local b = VN.ensure("Waves Audio Ltd")
  check("vn: ensure", a.color ~= b.color and b.name == "Waves Audio" and b.init == "WA", true)
  check("vn: found by another spelling", VN.get("Waves Audio Ltd.") == b, true)
  VN.remove("FabFilter")
  check("vn: removed", VN.get("FabFilter"), nil)
  check("vn: stored", store["TS_ChannelView/vendors"], "Waves Audio|" .. b.color .. "|WA|none")
  -- the same as another vendor: its look, stored as a fifth field
  store["TS_ChannelView/vendors"] = "Plugin Alliance|#4aa3df|PA|mono"
  VN.load(true)
  VN.same_as("Brainworx", "Plugin Alliance")
  check("vn: same as, stored", store["TS_ChannelView/vendors"], "Plugin Alliance|#4aa3df|PA|mono;Brainworx||BRA|none|Plugin Alliance")
  check("vn: same as, its look", VN.get("Brainworx").init, "PA")
  check("vn: same as, read back", VN.parse(store["TS_ChannelView/vendors"])[2].same, "Plugin Alliance")
  VN.same_as("Brainworx", nil)
  check("vn: own look again", VN.get("Brainworx").same == nil and VN.get("Brainworx").color ~= nil, true)
  VN.same_as("Brainworx", "Plugin Alliance")
  VN.remove("Plugin Alliance")
  check("vn: forgetting one forgets those the same as it", store["TS_ChannelView/vendors"], "")
  -- set up all: a different colour each, past the 16 suggestions
  local names = {}
  for i = 1, 40 do names[i] = "Vendor" .. i end
  VN.load(true)
  check("vn: set up all", VN.ensure_all(names), 40)
  local cols, dup = {}, false
  for _, v in ipairs(VN.list()) do if cols[v.color] then dup = true end cols[v.color] = true end
  check("vn: all colours different", dup, false)
  check("vn: set up all again, none new", VN.ensure_all(names), 0)
  -- the installed plugins' vendors
  local fxlist = { { "VST3: Pro-Q 3 (FabFilter)", "Pro-Q 3.vst3" }, { "VST: Pro-Q 3 (FabFilter)", "ProQ3.dll" },
                   { "VST3: Ozone 11 (iZotope, Inc.)", "Ozone.vst3" }, { "JS: Thing", "thing" } }
  local ge = reaper.EnumInstalledFX
  reaper.EnumInstalledFX = function(i) local e = fxlist[i + 1]; if not e then return false end return true, e[1], e[2] end
  package.loaded["TS_CV_Vendors"] = nil
  require("TS_CV_FXIndex").reset()     -- no tag file here: vendors from the names
  local VN2 = require("TS_CV_Vendors")
  local inst = VN2.installed()
  check("vn: installed", #inst .. inst[1].name .. inst[1].n .. inst[2].name, "2FabFilter2iZotope")
  check("vn: ident's vendor", VN2.of_ident("Ozone.vst3"), "iZotope")
  reaper.EnumInstalledFX = ge
  package.loaded["TS_CV_Vendors"] = VN
  store["TS_ChannelView/vendors"] = ""
  VN.load(true)
  -- the web bar carries the look worked out (vc, vl, vm, vf), and
  -- working it out again changes nothing
  local okd, DR = pcall(require, "TS_CV_Drawers")
  local FB = require("TS_CV_FXButtons")
  if okd then
    store["TS_ChannelView/vendors"] = "FabFilter|#4aa3df|FF|mono"
    local cmd = FB.fx_cmd("VST3: Pro-Q 3 (FabFilter)")
    local t = DR.json_encode_list({ { l = "Pro-Q 3", a = cmd, c = "" }, { l = "Undo", a = "40029", c = "" } })
    local w = DR.web_vendors(t)
    local arr = DR.json_decode(w)
    check("vn: web look", arr[1].vc .. arr[1].vm .. tostring(arr[1].vl) .. tostring(arr[2].vc), "#4aa3dfFFnilnil")
    check("vn: web, again the same", DR.web_vendors(w), w)
    check("vn: web, not read back", DR.from_web(arr)[1].vc, nil)
    store["TS_ChannelView/vendors"] = "FabFilter|#4aa3df|FF|prefix"
    check("vn: web prefix", DR.json_decode(DR.web_vendors(w))[1].vl, "FF - Pro-Q 3")
  end
  reaper.GetExtState, reaper.SetExtState = gx, sx
end

-- two windows on one library (ChannelView and its Rack view): each saves
-- its own changes over the other's, not instead of them
do
  local gx, sx = reaper.GetExtState, reaper.SetExtState
  local store = {}
  reaper.GetExtState = function(a, b) return store[a .. "/" .. b] or "" end
  reaper.SetExtState = function(a, b, v) store[a .. "/" .. b] = v end
  local tp = reaper.time_precise
  local tick = 0
  reaper.time_precise = function() tick = tick + 1 return tick end
  package.loaded["TS_CV_Mappings"] = nil
  local A = require("TS_CV_Mappings")
  package.loaded["TS_CV_Mappings"] = nil
  local B = require("TS_CV_Mappings")
  A.init("./"); B.init("./")
  A.set("SyncPlugA", { controls = { { param = 0, type = "knob", label = "A" } } })
  B.set("SyncPlugB", { controls = { { param = 1, type = "knob", label = "B" } } })
  A.save(); B.save()
  A.sync()
  check("sync: the other window's layout arrives", A.get("SyncPlugB") and A.get("SyncPlugB").controls[1].label, "B")
  check("sync: our own layout kept", B.get("SyncPlugA") and B.get("SyncPlugA").controls[1].label, "A")
  B.remove("SyncPlugA"); B.save()
  A.set("SyncPlugB", { controls = { { param = 1, type = "knob", label = "B2" } } }); A.save()
  local C2 = (function() package.loaded["TS_CV_Mappings"] = nil; local m = require("TS_CV_Mappings"); m.init("./"); return m end)()
  check("sync: a removal survives the other's save", C2.get("SyncPlugA") == nil or C2.has("SyncPlugA") == false, true)
  check("sync: the later edit wins", C2.get("SyncPlugB").controls[1].label, "B2")
  C2.remove("SyncPlugB"); C2.save()
  package.loaded["TS_CV_Mappings"] = M
  -- the step labels' cache, the same way
  package.loaded["TS_CV_Steps"] = nil
  local SA = require("TS_CV_Steps")
  package.loaded["TS_CV_Steps"] = nil
  local SB = require("TS_CV_Steps")
  os.remove("./TS_ChannelView_Steps.ini")
  SA.init("./"); SB.init("./")
  SA.set("SyncSteps", 3, { { text = "Low" }, { text = "High" } })
  SB.set("SyncSteps", 4, { { text = "Off" }, { text = "On" } })
  SA.save(); SB.save(); SA.sync()
  check("sync: steps from the other window", SA.get("SyncSteps", 4, 1) and SA.get("SyncSteps", 4, 1)[2].text, "On")
  check("sync: own steps kept", SB.get("SyncSteps", 3, 1) and SB.get("SyncSteps", 3, 1)[1].text, "Low")
  os.remove("./TS_ChannelView_Steps.ini")
  package.loaded["TS_CV_Steps"] = nil
  reaper.GetExtState, reaper.SetExtState, reaper.time_precise = gx, sx, tp
end

-- a switch's reading: words first, the value when they say nothing
do
  local ME = require("TS_CV_MapEQ")
  local R = ME.switch_reads_on
  check("switch: Disabled is off (Kirchhoff Dyn. On)", R("Band1 Dyn. On", "Disabled", 0), false)
  check("switch: Enabled is on", R("Band1 Dyn. On", "Enabled", 1), true)
  check("switch: On / Off", tostring(R("Dyn", "On", 1)) .. "/" .. tostring(R("Dyn", "Off", 0)), "true/false")
  check("switch: In / Out", tostring(R("EQ", "In", 1)) .. "/" .. tostring(R("EQ", "Out", 0)), "true/false")
  check("switch: Bypass param, Not Bypassed is on", R("Band 1 Bypass", "Not Bypassed", 0), true)
  check("switch: Bypass param, Bypassed is off", R("Band 1 Bypass", "Bypassed", 1), false)
  check("switch: Bypass param, Off is on", R("Bypass", "Off", 0), true)
  check("switch: Bypassed elsewhere is off", R("Band 1 State", "Bypassed", 1), false)
  check("switch: no words, by value", tostring(R("Dyn", "", 0.2)) .. "/" .. tostring(R("Dyn", "", 0.8)), "false/true")
  check("switch: Off (Stereo) is off", R("Dyn", "Off (Stereo)", 0), false)
  check("switch: Not Active is off", R("Dyn", "Not Active", 0), false)
  check("switch: Used / Unused (Pro-Q)", tostring(R("Band 1 Used", "Used", 1)) .. "/" .. tostring(R("Band 1 Used", "Unused", 0)), "true/false")
end

-- an EQ band's in-use switch (Pro-Q: "Band k Used"): found beside its
-- controls, and an unused band taken into use (and turned on) when changed
do
  local ME = require("TS_CV_MapEQ")
  local names, vals = {}, {}
  for k = 1, 3 do
    local base = (k - 1) * 4
    names[base] = "Band " .. k .. " Used"; names[base + 1] = "Band " .. k .. " Enabled"
    names[base + 2] = "Band " .. k .. " Frequency"; names[base + 3] = "Band " .. k .. " Gain"
    vals[base], vals[base + 1], vals[base + 2], vals[base + 3] = 0, 0, 0.5, 0.5
  end
  local real = reaper
  reaper = setmetatable({
    TrackFX_GetFXGUID = function() return "{PQ}" end,
    TrackFX_GetNumParams = function() return 12 end,
    TrackFX_GetParamName = function(_, _, p) return true, names[p] or "" end,
    TrackFX_GetFormattedParamValue = function(_, _, p)
      local n = names[p] or ""
      if n:find("Used") then return true, (vals[p] >= 0.5) and "Used" or "Unused" end
      if n:find("Enabled") then return true, (vals[p] >= 0.5) and "Enabled" or "Disabled" end
      return true, tostring(vals[p])
    end,
    TrackFX_GetParamNormalized = function(_, _, p) return vals[p] or 0 end,
    TrackFX_SetParamNormalized = function(_, _, p, v) vals[p] = v end,
  }, { __index = real })
  local b2 = { freq = 6, gain = 7, on = 5 }
  check("in use: band 2's switch found by name", ME.find_used("tr", 1, b2), 4)
  check("in use: band 2 starts unused", ME.in_use("tr", 1, b2), false)
  check("in use: a band with no such switch counts as used", ME.in_use("tr", 1, { freq = 99 }), true)
  check("in use: taken into use, and turned on", tostring(ME.take_in_use("tr", 1, b2)) .. " " .. vals[4] .. " " .. vals[5], "true 1 1")
  check("in use: already in use, nothing done", ME.take_in_use("tr", 1, b2), false)
  check("in use: band 1 untouched", vals[0] .. " " .. vals[1], "0 0")
  reaper = real
end

-- freeze: the frozen plugins out of a track chunk
do
  local FZ = require("TS_CV_Freeze")
  local U_ = require("TS_CV_Util")
  local chunk = table.concat({
    "<TRACK", "  NAME Vox",
    "  <FREEZE 1 0",
    "    <ITEM", "      <TAKEFX", "        <VST \"VST: TakeThing (X)\" x.dll 0 \"\"", "        >", "      >", "    >",
    "    <FXCHAIN", "      BYPASS 0 0 0",
    "      <JS TS_TrackAnalyser/TS_TrackProbe.jsfx \"\"", "      >",
    "      <JS TS_ChannelView/TS_CV_Modulators.jsfx \"\"", "      >",
    "      <VST \"VST3: Pro-C 3 (FabFilter)\" \"Pro-C 3.vst3\" 0 \"\" 1",
    "        AAAA==", "      >",
    "      <JS \"loser/3BandEQ\" \"\"", "      >",
    "      <JS Utility/volume_pan.jsfx \"\"", "      >",
    "      <CONTAINER Container \"Bus comp\" \"\"",
    "        <VST \"VST: Inner (X)\" i.dll 0", "        >", "      >",
    "    >",
    "  >",
    "  <FXCHAIN", "    <VST \"VST3: Pro-Q 4 (FabFilter)\" q.vst3 0", "    >", "  >",
    ">" }, "\n")
  local st = FZ.parse(chunk, U_.clean_fx_name)
  check("freeze: one level", st.levels, 1)
  check("freeze: a frozen probe counted", st.probes, 1)
  check("freeze: the frozen chain only, in order, helpers left out", table.concat(st.fx, "|"), "Pro-C 3|3BandEQ|volume_pan|Bus comp")
  local two = chunk:gsub("  <FXCHAIN\n    <VST", "  <FREEZE 2 0\n    <FXCHAIN\n      <VST \"VST: Later (Y)\" l.dll 0\n      >\n    >\n  >\n  <FXCHAIN\n    <VST", 1)
  local st2 = FZ.parse(two, U_.clean_fx_name)
  check("freeze: two levels, oldest first", st2.levels .. " " .. table.concat(st2.fx, "|"), "2 Pro-C 3|3BandEQ|volume_pan|Bus comp|Later")
  local rec = FZ.push_level(FZ.push_level("", { { 0, "Probe" }, { 2, "Mods" } }), { { 1, "Probe" }, { 0, "JS: Mods" } })
  check("freeze: two levels recorded", FZ.count(rec), 2)
  local mv, rest = FZ.pop_level(rec)
  check("freeze: last level's helpers, by slot", mv[1][1] .. mv[1][2] .. mv[2][1] .. mv[2][2], "0JS: Mods1Probe")
  local mv1, rest1 = FZ.pop_level(rest)
  check("freeze: the level before", #mv1 .. mv1[1][2] .. mv1[2][1] .. "/" .. FZ.count(rest1), "2Probe2/0")
  local mv2, rest2 = FZ.pop_level(FZ.push_level(nil, { { 3, "Probe" } }))
  check("freeze: the only level", #mv2 .. mv2[1][1] .. "/" .. rest2, "13/")
  check("freeze: nothing recorded", #(FZ.pop_level("")) .. FZ.count(""), "00")
  local pad = FZ.push_level("", { { 1, "Mods" } }, 2)
  check("freeze: levels frozen elsewhere padded", FZ.count(pad), 3)
  local mvp, restp = FZ.pop_level(pad)
  check("freeze: ... and the padding pops empty", #mvp .. "/" .. FZ.count(restp) .. "/" .. #(FZ.pop_level(restp)), "1/2/0")
  check("freeze: a level with no helpers still counts", FZ.count(FZ.push_level(FZ.push_level("", {}), {})), 2)
  local old = "0\31Probe" .. "\29" .. "1\31Mods"
  check("freeze: an older record reads as one level", FZ.count(old) .. "/" .. #(FZ.pop_level(old)), "1/2")
  -- a freeze in progress elsewhere (the web bridge, or ChannelView): this
  -- one leaves that track alone until it's done or a minute and a half on
  do
    local ext, real = {}, reaper
    reaper = setmetatable({
      GetExtState = function(ns, k) return ext[ns .. "/" .. k] or "" end,
      SetExtState = function(ns, k, v) ext[ns .. "/" .. k] = v end,
      DeleteExtState = function(ns, k) ext[ns .. "/" .. k] = nil end,
      GetTrackGUID = function(t) return "{" .. t.name .. "}" end,
    }, { __index = real })
    local A, B = { name = "A" }, { name = "B" }
    check("freeze elsewhere: none", tostring(FZ.busy(A)), "false")
    ext["TS_ChannelView/freeze_pending"] = "{A}|" .. os.time()
    check("freeze elsewhere: that track busy, not another", tostring(FZ.busy(A)) .. " " .. tostring(FZ.busy(B)), "true false")
    check("freeze elsewhere: no freeze over it", select(2, FZ.freeze(A)), "A freeze is still finishing.")
    check("freeze elsewhere: no sync under it", tostring(FZ.sync(A)), "false")
    ext["TS_ChannelView/freeze_pending"] = "{A}|" .. (os.time() - 120)
    check("freeze elsewhere: stale after 90 s", tostring(FZ.busy(A)), "false")
    reaper = real
  end
  local m = FZ.match({ "Probe", "Mods", "Probe" }, { "EQ", "Probe", "Mods", "Comp", "Probe" })
  check("freeze: left plugins found by name and order", (m[1] or 0) .. (m[2] or 0) .. (m[3] or 0), "235")
  local m2 = FZ.match({ "Probe", "Mods" }, { "Mods" })
  check("freeze: one went with the freeze", tostring(m2[1]) .. tostring(m2[2]), "nil1")
  check("freeze: none", FZ.parse("<TRACK\n  <FXCHAIN\n    <VST \"VST: A\" a 0\n    >\n  >\n>").levels, 0)
end

-- ---------------------------------------------------------------------
-- what a model misses (TS_CV_MapEQ C<s>) and the model switch (M)
-- ---------------------------------------------------------------------
do
  local ME = require("TS_CV_MapEQ")
  local M_ = require("TS_CV_Mappings")
  local C = { { g = -10, i0 = -1, v = { -1, -2, -3 } }, { g = 5, i0 = 0, v = { 0.5, 1 } }, { g = 10, i0 = 0, v = { 1, 3 } } }
  local function near(a, b) return math.abs(a - b) < 1e-6 end
  local oct = function(i) return 2 ^ (i / 3) end
  check("curve: at a gain measured", ME.curve_db(C, oct(1), 10), 3)
  check("curve: between two gains, blended", near(ME.curve_db(C, oct(1), 7.5), 2), true)
  check("curve: below the smallest, in proportion", near(ME.curve_db(C, oct(1), 2.5), 0.5), true)
  check("curve: past the largest, in proportion", near(ME.curve_db(C, oct(1), 20), 6), true)
  check("curve: between grid points", near(ME.curve_db(C, oct(0.5), 10), 2), true)
  check("curve: past a row's end, held", ME.curve_db(C, oct(9), 10), 3)
  check("curve: cuts their own", ME.curve_db(C, oct(1), -10), -3)
  check("curve: flat at 0 dB", ME.curve_db(C, oct(1), 0), 0)
  local Cb = { { g = 6, i0 = 0, v = { 0, 2 } } }
  check("curve: a side not measured mirrors the other", ME.curve_db(Cb, oct(1), -6), -2)
  local Cz = { { g = 0, i0 = 0, v = { -1, -4 } } }
  check("curve: a gainless one as it is", ME.curve_db(Cz, oct(1), 0), -4)
  local lo, hi = ME.curve_span(C)
  check("curve: span", lo .. ".." .. hi, "-1..1")
  local b = { type = "bell", f = 1000, g = 10, q = 1, c = C }
  check("curve: added to the model", near(ME.band_db(b, 1000 * oct(1)) - ME.model_db(b, 1000 * oct(1)), 3), true)
  -- encoded and back
  local L = { D = true, Mp = 8, M = { 0, 1 }, shapes = {
    [1] = { type = "bell", K = { 1, 1, 1 }, C = { { g = -9, i0 = -2, v = { 0, -0.5, 1.25, -0.04 } }, { g = 9, i0 = -2, v = { 0.1, 0.2 } } } },
    [2] = { type = "ls", K = { 1, 1, 1 } } } }
  local enc = ME.encode(L)
  check("curve: encoded", enc:match("C1=[^;]*"), "C1=-9@-2@0,-.5,1.2,0|9@-2@.1,.2")
  check("model: encoded", enc:match("M=[^;]*"), "M=8:0,1")
  local L2 = ME.decode(enc)
  local vv = {}
  for i, x in ipairs(L2.shapes[1].C[1].v) do vv[i] = ("%.2f"):format(x) end
  check("curve: decoded, smoothed a little", #L2.shapes[1].C .. " " .. L2.shapes[1].C[1].g .. " " .. L2.shapes[1].C[1].i0 .. " " ..
    table.concat(vv, ","), "2 -9 -2 0.00,-0.13,0.72,0.00")
  check("curve: a cut's, faded deep in its stop band", ME.curve_weight("hp", -12) .. " " .. ME.curve_weight("hp", -30) .. " " ..
    ME.curve_weight("bell", -30), "0.5 0 1")
  check("model: decoded", L2.Mp .. ":" .. table.concat(L2.M, ","), "8:0,1")
  check("curve: none where none", L2.shapes[2].C, nil)
  -- the slot: shape within model
  local vals = { [3] = 0.5, [8] = 1 }
  local fake = reaper
  reaper = setmetatable({ TrackFX_GetParamNormalized = function(_, _, p) return vals[p] or 0 end }, { __index = fake })
  local LL = { H = { 0, 0.5, 1 }, M = { 0, 1 }, Mp = 8, shapes = {} }
  check("slot: shape 2 of model 2", ME.slot(nil, 0, { shape = 3 }, LL), 5)
  check("slot: no shape switch", ME.slot(nil, 0, {}, LL), 2)
  check("slot: no model", ME.slot(nil, 0, { shape = 3 }, { H = LL.H, shapes = {} }), 2)
  reaper = fake
  -- the canvas line keeps it
  local cv = M_.canvas_of({ Canvas = "eq|-|10", Band1 = "Low|1|0|-|2|-" })
  check("model: read", tostring(cv.all_on) .. " " .. tostring(cv.model), "nil 10")
  local out = {}
  M_.canvas_lines(cv, out)
  check("model: written", out.Canvas, "eq|-|10")
  cv = M_.canvas_of({ Canvas = "eq|5|x", Band1 = "Low|1|0|-|2|-" })
  check("model: none on purpose", tostring(cv.model) .. " " .. tostring(cv.no_model), "nil true")
  out = {}; M_.canvas_lines(cv, out)
  check("model: none on purpose written", out.Canvas, "eq|5|x")
  cv = M_.canvas_of({ Canvas = "eq|5", Band1 = "Low|1|0|-|2|-" })
  out = {}; M_.canvas_lines(cv, out)
  check("model: an older line as it was", out.Canvas .. " " .. tostring(cv.model), "eq|5 nil")
  check("model: in what learning is checked against", M_.band_sig({ freq = 1 }, 10), "1,-,-,-,-,m10")
  check("model: not without", M_.band_sig({ freq = 1 }), "1,-,-,-,-")
  -- guessed by name
  check("model: guessed", ME.guess_model({ "Low Freq", "EQ Model", "Out" }, {}), 1)
  check("model: not a band's type", ME.guess_model({ "Band 1 Type", "Phase Mode" }, {}), nil)
end

-- The grid editor's window, drawn a frame at a time with a stand-in
-- ImGui (every call answered, nothing shown): its sheets, the Edit
-- parameters parts drawn in them, and the panel's own menus (hooks), for
-- the panel, a control, a divider and a section. Last, as the fake stays.
do
  local GE = require("TS_CV_GridEditor")
  local E_ = require("TS_CV_Editor")
  local T = GE._t
  local answers = {
    Begin = function() return true, true end, BeginChild = function() return true end,
    CollapsingHeader = function() return true end, BeginPopup = function() return true end,
    GetFrameHeight = function() return 20 end,
    Combo = function(_, _, cur) return false, cur end, Checkbox = function(_, _, v) return false, v end,
    InputText = function(_, _, v) return false, v end, InputTextWithHint = function(_, _, _, v) return false, v end,
    SliderDouble = function(_, _, v) return false, v end, GetMousePos = function() return 0, 0 end,
    CalcTextSize = function(_, t) return #(t or "") * 6, 13 end, GetCursorScreenPos = function() return 0, 0 end,
    GetCursorPosX = function() return 0 end, GetContentRegionAvail = function() return 800, 600 end,
    GetItemRectMax = function() return 100, 100 end, GetItemRectMin = function() return 0, 0 end,
    GetWindowPos = function() return 0, 0 end, GetWindowSize = function() return 400, 400 end,
    GetKeyMods = function() return 0 end,
  }
  local fake = setmetatable(answers, { __index = function(_, k)
    if not k:match("^DrawList_") and not k:match("^Viewport_") and k:match("^%u%a*_%u") then return 0 end
    return function() return false end
  end })
  GE.attach(fake); E_.attach(fake)
  local real = reaper
  reaper = setmetatable({
    ValidatePtr2 = function() return true end,
    TrackFX_GetFXGUID = function() return "ge2" end,
    TrackFX_GetNumParams = function() return 4 end,
    TrackFX_GetParamName = function(_, _, p) return true, "P" .. p end,
  }, { __index = real })
  local called = {}
  local function rec(name) return function() called[name] = (called[name] or 0) + 1 end end
  GE.hooks = { ready = function() return true end, style = rec("style"), back = rec("back"), look = rec("look"),
               plate = rec("plate"), section = rec("section"), colour = rec("colour") }
  local key = "GridEdSheet"
  M.set(key, { controls = { { param = 0, type = "knob", label = "" }, { param = -1, type = "divider", label = "" },
                            { param = 1, type = "toggle", label = "" } } })
  GE.open({}, { addr = 0, guid = "ge2", name = "VST: GridSheet" }, key, M.get(key), nil, { rows = 1 })
  local function frame(sel)
    T.select(sel)
    local ok, err = pcall(GE.draw, "ctx")
    return ok and "ok" or tostring(err)
  end
  check("grid sheet: the panel's", frame(nil), "ok")
  check("grid sheet: a knob's", frame(1), "ok")
  check("grid sheet: a button's", frame(3), "ok")
  check("grid sheet: a divider's", frame(2), "ok")
  T.cur().controls[#T.cur().controls + 1] = { param = -1, type = "section", label = "", style = "inset", at = { c = 0, r = 0, w = 4, h = 4 } }
  T.watch()
  check("grid sheet: a section's", frame(#T.cur().controls), "ok")
  T.cur().controls[#T.cur().controls + 1] = E_.new_virtual("combo", T.cur().controls)
  T.cur().controls[#T.cur().controls].at = { c = 12, r = 0, w = 8, h = 4 }
  T.watch()
  check("grid sheet: a virtual control's", frame(#T.cur().controls), "ok")
  T.select(1); T.pick(3)
  local okm, errm = pcall(GE.draw, "ctx")
  check("grid sheet: several selected", okm and "ok" or tostring(errm), "ok")
  check("grid sheet: the panel's menus drawn", (called.style or 0) > 0 and (called.back or 0) > 0 and (called.look or 0) > 0
    and (called.plate or 0) > 0 and (called.section or 0) > 0 and (called.colour or 0) > 0, true)
  -- a new layout from the header: a copy, then an empty one, each edited next
  local St = require("TS_CV_State")
  local real_sv = St.set_variant
  local shown
  St.set_variant = function(_, nm) shown = nm end
  local k1 = T.new_layout("Mix", false)
  check("grid header: a copy made and edited", tostring(k1 == T.key()) .. " " .. shown .. " " .. #M.get(k1).controls,
    "true Mix " .. #M.get(key).controls)
  local k2 = T.new_layout("Bare", true)
  check("grid header: an empty one", #M.get(k2).controls, 0)
  check("grid header: not a name twice", T.new_layout("Mix", false), nil)
  St.set_variant = real_sv
  M.remove(k1); M.remove(k2)
  -- ReaGate's canvas, drawn: the curve, the envelope with its pre-open,
  -- the detector filters along the foot
  do
    local CPm = require("TS_CV_CompPanel")
    CPm.attach(fake)
    require("TS_CV_RolePanel").attach(fake)   -- the detector filters are its filter panel
    local reads = { [0] = "-30.0 dB", "3 ms", "200 ms", "10 ms", "50 ms", "8000 Hz", "120 Hz", "0", "0",
                    "-inf dB", "+0.0 dB", "-inf dB", "-6.0 dB", "0", "0 ms" }
    local real2 = reaper
    reaper = setmetatable({
      TrackFX_GetParamNormalized = function(_, _, p) return 0.3 end,
      TrackFX_GetFormattedParamValue = function(_, _, p) return true, reads[p] or "0" end,
      TrackFX_FormatParamValueNormalized = function(_, _, p) return true, reads[p] or "0" end,
      TrackFX_GetEnabled = function() return true end,
      TrackFX_GetNumParams = function() return 24 end,
      Master_GetTempo = function() return 120 end,
    }, { __index = real2 })
    answers.DrawList_AddRect = nil
    local cv = { kind = "gate", rev = {}, roles = { Threshold = 0, Attack = 1, Release = 2, Preopen = 3, Hold = 4,
                 Lowpass = 5, Hipass = 6, Hysteresis = 12, Preview = 13, RMS = 14 } }
    -- its attack and release driven by a macro: drawn with their reach
    local MDg = require("TS_CV_Mod")
    local lo_, li_ = MDg.link_of, MDg.live
    local src_ = { guid = "{M}", col = 0xff00ffff, name = "Macro 1" }
    MDg.link_of = function(_, _, p)
      if p == 1 or p == 2 then return { macro = true, mod = src_, baseline = 0.2, scale = 0.5 } end
    end
    MDg.live = function() return 0.3 end
    local okd, errd = pcall(CPm.draw_mapped, "ctx", "dl", 0, 0, 600, 320, {}, { addr = 0, guid = "rg-draw", name = "VST: ReaGate (Cockos)", path_t = { 0 } }, {}, cv)
    check("reagate: its canvas draws", okd and "ok" or tostring(errd), "ok")
    MDg.link_of = function() return nil end
    local okd2, errd2 = pcall(CPm.draw_mapped, "ctx", "dl", 0, 0, 600, 320, {}, { addr = 0, guid = "rg-draw", name = "VST: ReaGate (Cockos)", path_t = { 0 } }, {}, cv)
    check("reagate: its canvas draws, nothing linked", okd2 and "ok" or tostring(errd2), "ok")
    -- a compressor's: its ratio and attack driven
    reads[7] = "4.0:1"
    MDg.link_of = function(_, _, p)
      if p == 1 or p == 7 then return { macro = true, mod = src_, baseline = 0.2, scale = 0.5 } end
    end
    local ccv = { kind = "comp", rev = {}, roles = { Threshold = 0, Attack = 1, Release = 2, Ratio = 7 } }
    local okc, errc = pcall(CPm.draw_mapped, "ctx", "dl", 0, 0, 600, 320, {}, { addr = 0, guid = "cc-draw", name = "VST: SomeComp", path_t = { 0 } }, {}, ccv)
    check("comp: its canvas draws, ratio and attack driven", okc and "ok" or tostring(errc), "ok")
    -- an expander's ratio on a gate
    local gcv = { kind = "gate", rev = {}, roles = { Threshold = 0, Attack = 1, Release = 2, Ratio = 7, Range = 9 } }
    local okg, errg = pcall(CPm.draw_mapped, "ctx", "dl", 0, 0, 600, 320, {}, { addr = 0, guid = "ge-draw", name = "VST: SomeGate", path_t = { 0 } }, {}, gcv)
    check("gate: an expander's ratio driven", okg and "ok" or tostring(errg), "ok")
    -- every handle driven: thresholds, knee, hysteresis, range, ceiling
    MDg.link_of = function() return { macro = true, mod = src_, baseline = 0.2, scale = 0.5 } end
    ccv.roles.Knee = 8
    local oka, erra = pcall(CPm.draw_mapped, "ctx", "dl", 0, 0, 600, 320, {}, { addr = 0, guid = "cc-draw", name = "VST: SomeComp", path_t = { 0 } }, {}, ccv)
    check("comp: every handle driven", oka and "ok" or tostring(erra), "ok")
    local okb, errb = pcall(CPm.draw_mapped, "ctx", "dl", 0, 0, 600, 320, {}, { addr = 0, guid = "ge-draw", name = "VST: SomeGate", path_t = { 0 } }, {}, gcv)
    check("gate: every handle driven", okb and "ok" or tostring(errb), "ok")
    local okr, errr = pcall(CPm.draw_mapped, "ctx", "dl", 0, 0, 600, 320, {}, { addr = 0, guid = "rg-draw", name = "VST: ReaGate (Cockos)", path_t = { 0 } }, {}, cv)
    check("reagate: every handle driven", okr and "ok" or tostring(errr), "ok")
    local lcv_ = { kind = "limit", rev = {}, roles = { Threshold = 0, Ceiling = 9, Release = 2 } }
    local okl_, errl_ = pcall(CPm.draw_mapped, "ctx", "dl", 0, 0, 600, 260, {}, { addr = 0, guid = "rl2-draw", name = "VST: SomeLimit", path_t = { 0 } }, {}, lcv_)
    check("limiter: every handle driven", okl_ and "ok" or tostring(errl_), "ok")
    MDg.link_of = function() return nil end
    reads[7] = "0"
    -- the same filter panel under a delay's echoes
    local dcv = { kind = "delay", rev = {}, roles = { Time = 1, Feedback = 2, LowCut = 6, HighCut = 5 } }
    local okdl, errdl = pcall(require("TS_CV_RolePanel").draw, "ctx", "dl", 0, 0, 600, 400, {},
      { addr = 0, guid = "dl-draw", name = "VST: SomeDelay" }, {}, dcv)
    check("delay: its canvas draws, with its filters", okdl and "ok" or tostring(errdl), "ok")
    -- every handle and cut driven
    MDg.link_of = function() return { macro = true, mod = src_, baseline = 0.2, scale = 0.5 } end
    local CMt = require("TS_CV_CanvasMod")
    local cu, seen = CMt.under, {}
    CMt.under = function(c_, d_, t_, f_, id_, n_, axes_)
      for _, a_ in ipairs(axes_) do
        local x1, y1 = a_.pos(0.1)
        local x2, y2 = a_.pos(0.9)
        local moved = (x1 and x2 and math.abs(x1 - x2) > 0.5) or (y1 and y2 and math.abs(y1 - y2) > 0.5)
        seen[#seen + 1] = a_.key .. (moved and "+" or "=")
      end
      return cu(c_, d_, t_, f_, id_, n_, axes_)
    end
    local fpn = reaper.TrackFX_FormatParamValueNormalized
    reaper.TrackFX_FormatParamValueNormalized = function(_, _, p, n)
      if p == 1 then return true, ("%.0f ms"):format(10 + n * 990) end
      if p == 2 then return true, ("%.0f %%"):format(n * 100) end
      if p == 5 or p == 6 then return true, ("%.0f Hz"):format(20 * 1000 ^ n) end
      return true, "0"
    end
    local okdm, errdm = pcall(require("TS_CV_RolePanel").draw, "ctx", "dl", 0, 0, 600, 400, {},
      { addr = 0, guid = "dl-draw", name = "VST: SomeDelay", path_t = { 0 } }, {}, dcv)
    reaper.TrackFX_FormatParamValueNormalized = fpn
    CMt.under = cu
    check("delay: every handle driven", okdm and "ok" or tostring(errdm), "ok")
    table.sort(seen)
    check("delay: its handles and cuts move with their control", table.concat(seen, " "), "Feedback+ Time+ hc+ lc+")
    -- a modulated time doesn't swing the feedback's ghost: the others at
    -- their settings
    do
      local msrc = { guid = "{L}", col = 0xff00ffff, name = "LFO 1", slot = 0, j = 1 }
      MDg.link_of = function() return { mod = msrc, baseline = 0.5, scale = 0.2, offset = 0, slot = 0, param = 1 } end
      local gp, gpn = reaper.TrackFX_GetParam, reaper.TrackFX_GetParamNormalized
      reaper.TrackFX_GetParam = function() return 1, 0, 1 end
      reaper.TrackFX_FormatParamValueNormalized = function(_, _, p, n)
        if p == 1 then return true, ("%.0f ms"):format(10 + n * 990) end
        if p == 2 then return true, ("%.0f %%"):format(n * 100) end
        return true, "0"
      end
      local got = {}
      CMt.under = function(c_, d_, t_, f_, id_, n_, axes_)
        for _, a_ in ipairs(axes_) do
          if a_.key == "Feedback" then local x_, y_ = a_.pos(0.5); got[#got + 1] = ("%.1f,%.1f"):format(x_ or -1, y_ or -1) end
        end
      end
      for _, live in ipairs({ 0.3, 0.7 }) do
        reaper.TrackFX_GetParamNormalized = function() return live end
        pcall(require("TS_CV_RolePanel").draw, "ctx", "dl", 0, 0, 600, 400, {},
          { addr = 0, guid = "dl-draw", name = "VST: SomeDelay", path_t = { 0 } }, {}, dcv)
      end
      CMt.under = cu
      reaper.TrackFX_GetParam, reaper.TrackFX_GetParamNormalized, reaper.TrackFX_FormatParamValueNormalized = gp, gpn, fpn
      check("delay: a modulated time leaves the feedback's handles put", #got == 2 and got[1] == got[2], true)
      MDg.link_of = function() return { macro = true, mod = src_, baseline = 0.2, scale = 0.5 } end
    end
    -- every other role canvas: drawn with nothing linked, with macros,
    -- with modulators; each linked handle moves with its control, and
    -- stays put while the others swing (TS_CV_CanvasMod)
    do
      local RPm = require("TS_CV_RolePanel")
      local CMc = require("TS_CV_CanvasMod")
      local cu2 = CMc.under
      local gp2, gpn2, fpn2 = reaper.TrackFX_GetParam, reaper.TrackFX_GetParamNormalized, reaper.TrackFX_FormatParamValueNormalized
      local msrc = { guid = "{L}", col = 0xff00ffff, name = "LFO 1", slot = 0, j = 1 }
      local CANV = {
        { "deess",  { Threshold = 0, Frequency = 1, Width = 2, Range = 9 }, nil, "Frequency Range Threshold" },
        { "deess",  { Threshold = 0, Low = 5, High = 6 }, nil, "High Low Threshold" },
        { "sat",    { Drive = 1, Mix = 2 }, nil, "Drive Mix" },
        { "reverb", { Predelay = 1, Decay = 2, Early = 3, Size = 4, Diffusion = 5, Mix = 6, LowFreq = 7, HighFreq = 8,
                      Bass = 9, Damping = 10, Tone = 11, LowCut = 12, HighCut = 13, LowEQ = 14, HighEQ = 15 }, nil,
          "Bass Damping Decay Diffusion Early HighCut HighEQ HighFreq LowCut LowEQ LowFreq Mix Predelay Size Tone" },
        { "reverb", { Predelay = 1, Decay = 2, Balance = 3 }, nil, "Balance Decay Predelay" },
        { "env",    { Delay = 1, Attack = 2, Hold = 3, Decay = 4, Sustain = 5, Release = 6,
                      AttackCurve = 7, DecayCurve = 8, ReleaseCurve = 9 }, nil,
          "Attack AttackCurve Decay DecayCurve Delay Hold Release ReleaseCurve Sustain" },
        -- a synth's: its oscillator over the envelope (ReaSynth's)
        { "env",    { Attack = 1, Decay = 2, Sustain = 3, Release = 4, Square = 5, Saw = 6, Triangle = 7, Sine2 = 8,
                      Sine2Tune = 9, PulseWidth = 10, Detune = 11, Portamento = 12, Volume = 13 }, nil,
          "Attack Decay Detune Portamento PulseWidth Release Saw Sine Sine2Tune Sq Sustain Tri Volume" },
        { "mod",    { Rate = 1, Depth = 2, Phase = 3, Mix = 5 }, nil, "Depth Mix Phase Rate" },
        { "mod",    { V1Rate = 1, V1Depth = 2, V1Phase = 3, V1Pan = 4, V2Rate = 5, V2Depth = 6, V2Pan = 7 }, nil, "Pan V1Depth V1Pan V1Phase V1Rate V2Pan" },
        { "multi",  { Crossover1 = 1, Crossover2 = 2, B1Threshold = 3, B2Threshold = 4, B3Threshold = 5,
                      B1Ratio = 6, B1Gain = 7, B1Attack = 8 }, 3,
          "Atk B1Threshold B2Threshold B3Threshold Crossover1 Crossover2 Gain Ratio" },
        -- the dynamics canvases (CompPanel's)
        { "limit",  { Threshold = 1, Ceiling = 2, Release = 3 }, nil, "Ceiling Release Threshold", true },
        { "gate",   { Threshold = 1, Attack = 2, Hold = 3, Release = 4, Range = 5, Hysteresis = 6, Ratio = 7 }, nil,
          "Closes Opens atk hold range ratio rel", true, { [7] = function(n) return ("%.1f:1"):format(1 + n * 19) end } },
        { "comp",   { Threshold = 1, Ratio = 2, Attack = 3, Release = 4, Knee = 5, Makeup = 6, Mix = 7 }, nil,
          "Make-up Mix atk knee ratio rel thr", true, { [2] = function(n) return ("%.1f:1"):format(1 + n * 19) end } },
      }
      -- ReaXcomp's eight bands, every band control and switch mapped
      do
        local r8, keys, rv8 = {}, {}, {}
        local p = 1
        for k = 1, 8 do
          if k < 8 then r8["Crossover" .. k] = p; p = p + 1; keys[#keys + 1] = "Crossover" .. k end
          for _, rl in ipairs({ "Threshold", "Ratio", "Knee", "Attack", "Release", "Gain", "RMS", "AutoMakeup", "AutoRelease", "Feedback", "Bypass" }) do
            r8["B" .. k .. rl] = p; p = p + 1
          end
          rv8["B" .. k .. "Bypass"] = true
          keys[#keys + 1] = "B" .. k .. "Threshold"
        end
        for _, kk in ipairs({ "Atk", "Gain", "RMS", "Ratio", "Rel" }) do keys[#keys + 1] = kk end
        table.sort(keys)
        CANV[#CANV + 1] = { "multi", r8, 8, table.concat(keys, " "), nil, nil, rv8, "VST: ReaXcomp (Cockos)" }
      end
      reaper.TrackFX_GetParam = function() return 1, 0, 1 end
      for i, c in ipairs(CANV) do
        reaper.TrackFX_FormatParamValueNormalized = function(_, _, p, n)
          if c[6] and c[6][p] then return true, c[6][p](n) end
          return true, ("%.3f"):format(n)
        end
        local cv_ = { kind = c[1], rev = c[7] or {}, roles = c[2], nb = c[3] }
        local fx_ = { addr = 0, guid = "rc" .. i, name = c[8] or ("VST: Some " .. c[1]), path_t = { 0 } }
        local function draw(link, live)
          MDg.link_of = link
          reaper.TrackFX_GetParamNormalized = function() return live or 0.3 end
          if c[5] then return pcall(CPm.draw_mapped, "ctx", "dl", 0, 0, 700, 420, {}, fx_, {}, cv_) end
          return pcall(RPm.draw, "ctx", "dl", 0, 0, 700, 420, {}, fx_, {}, cv_)
        end
        local ok1, e1 = draw(function() return nil end)
        -- macros: each axis moves with its control
        local seen, keys = {}, {}
        CMc.under = function(c_, d_, t_, f_, id_, n_, axes_)
          for _, a_ in ipairs(axes_) do
            keys[a_.key] = true
            if a_.pos then
              local x1, y1 = a_.pos(0.1)
              local x2, y2 = a_.pos(0.9)
              local moved = (x1 and x2 and math.abs(x1 - x2) > 0.5) or (y1 and y2 and math.abs(y1 - y2) > 0.5)
              if not moved then seen[#seen + 1] = a_.key end
            end
          end
          return cu2(c_, d_, t_, f_, id_, n_, axes_)
        end
        local ok2, e2 = draw(function() return { macro = true, mod = src_, baseline = 0.2, scale = 0.5 } end)
        CMc.under = cu2
        -- modulators: placed the same however the others are swinging
        local at = {}
        CMc.under = function(c_, d_, t_, f_, id_, n_, axes_)
          for _, a_ in ipairs(axes_) do
            if a_.pos then
              local x_, y_ = a_.pos(0.5)
              local key = id_ .. ":" .. a_.key
              local v_ = ("%.1f,%.1f"):format(x_ or -1, y_ or -1)
              if at[key] == nil then at[key] = v_ elseif at[key] ~= v_ then at[key] = false end
            end
          end
        end
        local mlink = function() return { mod = msrc, baseline = 0.5, scale = 0.2, offset = 0, slot = 0, param = 1 } end
        local ok3, e3 = draw(mlink, 0.3)
        local ok4, e4 = draw(mlink, 0.7)
        CMc.under = cu2
        local swung = {}
        for k_, v_ in pairs(at) do if v_ == false then swung[#swung + 1] = k_ end end
        table.sort(swung)
        local tag = c[1] .. " " .. i .. ": "
        check(tag .. "draws, nothing linked", ok1 or e1, true)
        check(tag .. "draws, macros on every handle", ok2 or e2, true)
        check(tag .. "draws, modulators on every handle", (ok3 and ok4) or e3 or e4, true)
        local kl = {}
        for k_ in pairs(keys) do kl[#kl + 1] = k_ end
        table.sort(kl)
        check(tag .. "its handles", table.concat(kl, " "), c[4])
        check(tag .. "every handle moves with its control", table.concat(seen, " "), "")
        check(tag .. "every handle stays put while the others swing", table.concat(swung, " "), "")
      end
      CMc.under = cu2
      reaper.TrackFX_GetParam, reaper.TrackFX_GetParamNormalized, reaper.TrackFX_FormatParamValueNormalized = gp2, gpn2, fpn2
      MDg.link_of = function() return { macro = true, mod = src_, baseline = 0.2, scale = 0.5 } end
    end
    local okgf, errgf = pcall(CPm.draw_mapped, "ctx", "dl", 0, 0, 600, 320, {}, { addr = 0, guid = "rg-draw", name = "VST: ReaGate (Cockos)", path_t = { 0 } }, {}, cv)
    check("reagate: its detector filters driven", okgf and "ok" or tostring(errgf), "ok")
    MDg.link_of = function() return nil end
    -- ReaLimit's, with its options
    local RBm = require("TS_CV_ReaFX")
    reaper.TrackFX_GetNamedConfigParm = function(_, _, k)
      if k == "vst_chunk" then return true, RBm.b64enc(string.pack("<i4<i4", 3, 1) .. ("\0"):rep(40)) end
      return false, ""
    end
    local lcv = { kind = "limit", rev = {}, roles = { Threshold = 0, Ceiling = 1, Release = 2 } }
    local okl, errl = pcall(CPm.draw_mapped, "ctx", "dl", 0, 0, 600, 260, {}, { addr = 0, guid = "rl-draw", name = "VST: ReaLimit (Cockos)" }, {}, lcv)
    check("realimit: its canvas draws, with its options", okl and "ok" or tostring(errl), "ok")
    -- ReaComp's own panel, every handle driven and not
    do
      local names = { [0] = "Thresh", "Ratio", "Attack", "Release", "Pre-comp", "Knee", "Auto Release", "Wet" }
      local rc_reads = { [0] = "-20.0", "4.0", "3.0", "100", "0.0", "6.0", "0", "0.0" }
      local units = { [0] = " dB", ":1", " ms", " ms", " ms", " dB", "", " dB" }
      local had = {}
      for _, k in ipairs({ "TrackFX_GetNumParams", "TrackFX_GetParamName", "TrackFX_GetFormattedParamValue",
                           "TrackFX_FormatParamValueNormalized" }) do had[k] = reaper[k] end
      reaper.TrackFX_GetNumParams = function() return 8 end
      reaper.TrackFX_GetParamName = function(_, _, p) return true, names[p] or "" end
      reaper.TrackFX_GetFormattedParamValue = function(_, _, p) return true, rc_reads[p] or "0" end
      reaper.TrackFX_FormatParamValueNormalized = function(_, _, p, n)
        local base = tonumber(rc_reads[p]) or 0
        return true, ("%.1f%s"):format(base + n * 10, units[p] or "")
      end
      require("TS_CV_ReaComp").forget_maps()
      MDg.link_of = function() return { macro = true, mod = src_, baseline = 0.2, scale = 0.5 } end
      local ok1, e1 = pcall(CPm.draw, "ctx", "dl", 0, 0, 640, 320, {}, { addr = 0, guid = "rc-draw", name = "VST: ReaComp (Cockos)", path_t = { 0 } }, {})
      check("reacomp: every handle driven", ok1 and "ok" or tostring(e1), "ok")
      MDg.link_of = function() return nil end
      local ok2, e2 = pcall(CPm.draw, "ctx", "dl", 0, 0, 640, 320, {}, { addr = 0, guid = "rc-draw", name = "VST: ReaComp (Cockos)", path_t = { 0 } }, {})
      check("reacomp: its panel draws", ok2 and "ok" or tostring(e2), "ok")
      for k, v in pairs(had) do reaper[k] = v end
      require("TS_CV_ReaComp").forget_maps()
    end
    MDg.link_of, MDg.live = lo_, li_
    reaper = real2
  end
  -- a bar's menu with Large items: its submenu rows drawn as the bar's
  -- buttons, an action row as a menu row
  do
    local TBm = require("TS_CV_Toolbar")
    TBm.attach(fake)
    local items = { { menu = true, icon = "", label = "Pads", large = true,
                      items = { { menu = true, icon = "", label = "Sub", items = {} },
                                { cmd = "40001", icon = "", label = "A" } } } }
    local bar = TBm.make("TestLargeBar", "tlb", {}, { stamp = function() return 1 end,
      load = function() return items end, save = function() end })
    answers.InvisibleButton = function() return true end
    answers.GetTextLineHeight = function() return 13 end
    answers.GetCursorPosY = function() return 0 end
    rawset(reaper, "GetToggleCommandStateEx", function() return 0 end)
    local painted = 0
    answers.DrawList_AddRect = function() painted = painted + 1 end
    local ok1, e1 = pcall(bar.draw_v, "ctx", 0, 0, 200, 400, "right")
    local before = painted
    local ok2, e2 = pcall(bar.draw_menus, "ctx")
    check("large menu: drawn", (ok1 and ok2) and "ok" or tostring(e1 or e2), "ok")
    check("large menu: its submenu row is a button", painted - before, 1)
    answers.InvisibleButton, answers.GetTextLineHeight, answers.GetCursorPosY, answers.DrawList_AddRect = nil, nil, nil, nil
  end
  GE.close()
  GE.hooks = nil
  reaper = real
  M.remove(key); M.save()
end

-- ReaGate's and ReaLimit's default canvases: roles found by name
do
  local RB = require("TS_CV_ReaFX")
  -- as REAPER 7 lists them (dev/TS_CV_ParamDump.lua)
  local gate = { [0] = "Threshold", "Attack", "Release", "Pre-open", "Hold", "Lowpass", "Hipass",
                 "SignIn", "AudIn", "Dry", "Wet", "Noise level", "Hysteresis", "Preview Filter", "RMS size",
                 "Send MIDI", "Midi Note", "Midi Channel", "Invert Wet", "Multichannel Mode", "Metering Index",
                 "Bypass", "Wet", "Delta" }
  local r = RB.roles_by_name("reagate", gate)
  check("reagate: roles by name", ("%s %s %s %s %s %s %s %s %s %s"):format(r.Threshold, r.Attack, r.Hold, r.Release,
        r.Hysteresis, r.Preopen, r.Lowpass, r.Hipass, r.Preview, r.RMS), "0 1 4 2 12 3 5 6 13 14")
  local lim = { [0] = "Threshold", "Ceiling", "Release", "Bypass", "Wet", "Delta" }
  local l = RB.roles_by_name("realimit", lim)
  check("realimit: roles by name", ("%s %s %s"):format(l.Threshold, l.Ceiling, l.Release), "0 1 2")
  check("reagate: the kinds", tostring(RB.kind("ReaGate")) .. " " .. tostring(RB.kind("ReaLimit")), "reagate realimit")
  local real = reaper
  reaper = setmetatable({
    TrackFX_GetNumParams = function() return 24 end,
    TrackFX_GetParamName = function(_, _, p) return true, gate[p] end,
  }, { __index = real })
  local ED = require("TS_CV_Edition")
  local was = ED.PRO
  local function dflt()
    local controls = {}
    for p = 0, 7 do controls[#controls + 1] = { param = p, type = "knob", label = "" } end
    return { controls = controls, aliases = {} }
  end
  ED.PRO = { RELEASE = ED.RELEASE }
  local d = RB.default_canvas({}, 0, "rg-test", "reagate", dflt())
  local ps = {}
  for _, c in ipairs(d.controls) do ps[#ps + 1] = c.param end
  check("reagate: a gate canvas", d.canvas and d.canvas.kind, "gate")
  check("reagate: nothing beside it (RMS size is on the canvas)", table.concat(ps, ","), "")
  check("reagate: a saved layout's own canvas left alone",
        RB.default_canvas({}, 0, "rg-test", "reagate", { controls = {}, canvas = { kind = "comp" } }).canvas.kind, "comp")
  -- ReaLimit's options in its state: version 3, then the flags word
  local state = string.pack("<i4<i4", 3, 0) .. ("\0"):rep(40)
  reaper.TrackFX_GetNamedConfigParm = function(_, _, k) if k == "vst_chunk" then return true, RB.b64enc(state) end return false, "" end
  reaper.TrackFX_SetNamedConfigParm = function(_, _, k, v) if k == "vst_chunk" then state = RB.b64dec(v) end return true end
  reaper.Undo_BeginBlock = function() end; reaper.Undo_EndBlock = function() end
  check("realimit: options read", RB.limit_flags({}, 0, nil), 0)
  RB.set_limit_flag({}, 0, nil, "truepeak", true); RB.set_limit_flag({}, 0, nil, "lowlat", true)
  check("realimit: true peak and low latency set", RB.limit_flags({}, 0, nil), 65)
  RB.set_limit_flag({}, 0, nil, "truepeak", false)
  check("realimit: and one cleared, the rest kept", tostring(RB.limit_flags({}, 0, nil)) .. " " .. #state, "64 48")
  state = string.pack("<i4<i4", 4, 0) .. ("\0"):rep(40)
  check("realimit: a state it doesn't know left alone", tostring(RB.set_limit_flag({}, 0, nil, "truepeak", true)) ..
        " " .. tostring(RB.limit_flags({}, 0, nil)), "false nil")
  -- ReaXcomp (its real names, REAPER 7.83): the multiband canvas, a band
  -- per "<k>-" group, each band's top frequency the crossover above it,
  -- Active turned round as its bypass; nothing beside
  local xnames = {}
  local per = { "Band top frequency", "Gain", "Threshold", "Ratio", "Knee", "Attack", "Release", "RMS", "Make Up Gain",
                "Auto Release", "FeedBack Detector", "Active" }
  local function xcomp(nb_)
    xnames = {}
    for k = 1, nb_ do for j, nm in ipairs(per) do xnames[(k - 1) * 12 + j - 1] = k .. "-" .. nm end end
    xnames[nb_ * 12], xnames[nb_ * 12 + 1], xnames[nb_ * 12 + 2] = "Bypass", "Wet", "Delta"
  end
  xcomp(4)
  reaper.TrackFX_GetNumParams = function() return #xnames + 1 end
  reaper.TrackFX_GetParamName = function(_, _, p) return true, xnames[p] end
  ED.PRO = { RELEASE = ED.RELEASE }
  local xd = RB.default_canvas({}, 0, "rx-test", "reaxcomp", dflt())
  local xr = xd.canvas and xd.canvas.roles or {}
  check("reaxcomp: a multiband canvas of its four bands", (xd.canvas and xd.canvas.kind or "-") .. " " .. tostring(xd.canvas and xd.canvas.nb), "multi 4")
  check("reaxcomp: crossovers are the bands' tops", ("%s %s %s %s"):format(xr.Crossover1, xr.Crossover2, xr.Crossover3, tostring(xr.Crossover4)), "0 12 24 nil")
  check("reaxcomp: band 2's controls", ("%s %s %s %s %s %s"):format(xr.B2Threshold, xr.B2Ratio, xr.B2Knee, xr.B2Gain, xr.B2RMS, xr.B2Release), "14 15 16 13 19 18")
  check("reaxcomp: its switches", ("%s %s %s %s"):format(xr.B3AutoMakeup, xr.B3AutoRelease, xr.B3Feedback, xr.B3Bypass), "32 33 34 35")
  check("reaxcomp: Active turned round as bypass", xd.canvas.rev.B1Bypass, true)
  check("reaxcomp: nothing beside it", #xd.controls, 0)
  xcomp(8)
  local x8 = RB.default_canvas({}, 0, "rx8-test", "reaxcomp", dflt())
  check("reaxcomp: eight bands", tostring(x8.canvas and x8.canvas.nb) .. " " .. tostring(x8.canvas.roles.Crossover7), "8 72")
  -- a preset with more or fewer bands: the canvas follows
  xcomp(3)
  local xf = RB.default_canvas({}, 0, "rxf-test", "reaxcomp", dflt())
  RB.ensure({}, 0, "rxf-test", "ReaXcomp", xf)
  local nb0 = xf.canvas.nb
  xcomp(6)
  RB.ensure({}, 0, "rxf-test", "ReaXcomp", xf)
  local nb1, c5 = xf.canvas.nb, xf.canvas.roles.Crossover5
  xcomp(2)
  RB.ensure({}, 0, "rxf-test", "ReaXcomp", xf)
  check("reaxcomp: follows a preset's bands", ("%s %s %s %s %s"):format(nb0, nb1, tostring(c5), xf.canvas.nb, tostring(xf.canvas.roles.B3Threshold)), "3 6 48 2 nil")
  -- ReaXcomp's stored bands (its real state, four bands): split one, take one away
  do
    local hx = "3800000004000000be644f7c82aa5540000000000000f03f96683bd536a2bc3faaf8bf232ab40f404c37894160e5004014000000c10000001400000007000000ece61f993d419240000000000000f03f19008b93759dc13f1a5cedd4e590f43f00000000000000000f0000006a00000013000000060000006219c3903ea5bf40000000000000f03f34e4bac334f2c03f0d83c8bb2bf8f63f00000000000000000c000000450000001100000006000000000000000070d740000000000000f03f2066b20cac52c03f0000000000000040fa7e6abc7493c83f0c0000001c0000000200000006000000010000000100000020793c074ddbf53f0000000000000000000000000100000002000000"
    local raw4 = hx:gsub("%x%x", function(c) return string.char(tonumber(c, 16)) end)
    local bands, bsz, tail = RB.xcomp_split(raw4)
    check("reaxcomp state: its bands", ("%d %d %d"):format(#bands, bsz, #tail), "4 56 36")
    check("reaxcomp state: back as it was", RB.xcomp_join(bands, bsz, tail) == raw4, true)
    local tops = function(b) local o = {} for i, r in ipairs(b) do o[i] = ("%.0f"):format((string.unpack("<d", r))) end return table.concat(o, " ") end
    check("reaxcomp state: band tops", tops(bands), "87 1168 8101 24000")
    local b5 = RB.xcomp_split_band(bands, 2)
    check("reaxcomp: a band split in two", tops(b5), "87 318 1168 8101 24000")
    check("reaxcomp: the new band its settings", b5[2]:sub(9) == b5[3]:sub(9), true)
    local b4 = RB.xcomp_remove_band(b5, 2)
    check("reaxcomp: taken away again, as it was", RB.xcomp_join(b4, bsz, tail) == raw4, true)
    local b3 = RB.xcomp_remove_band(RB.xcomp_split(raw4), 4)
    check("reaxcomp: the last band away, the one below tops the range", tops(b3), "87 1168 24000")
    check("reaxcomp: one band stays", RB.xcomp_remove_band({ bands[1] }, 1), nil)
    check("reaxcomp: not a state it knows", RB.xcomp_split("abc"), nil)
    -- not while a band at or after it has automation or a link
    xcomp(4)
    local ge, gn = reaper.GetFXEnvelope, reaper.TrackFX_GetNamedConfigParm
    reaper.GetFXEnvelope = function(_, _, p) return p == 30 and "env" or nil end
    reaper.TrackFX_GetNamedConfigParm = function(_, _, k) return k == "param.40.plink.active", "1" end
    local c2, why2 = RB.xcomp_can_change({}, 0, "rxc-test", 2)
    local c4, why4 = RB.xcomp_can_change({}, 0, "rxc-test", 4)
    reaper.GetFXEnvelope = function() return nil end
    local c1 = RB.xcomp_can_change({}, 0, "rxc-test", 4)
    reaper.TrackFX_GetNamedConfigParm = function() return false, "" end
    local c0 = RB.xcomp_can_change({}, 0, "rxc-test", 1)
    reaper.GetFXEnvelope, reaper.TrackFX_GetNamedConfigParm = ge, gn
    check("reaxcomp: automation on a later band stops it", ("%s %s %s %s"):format(tostring(c2), tostring(c4), tostring(c1), tostring(c0)), "false false false true")
    check("reaxcomp: says why", (why2 or ""):find("Automation") ~= nil and (why4 or ""):find("link") ~= nil, true)
  end
  -- ReaSynth (its real names): envelope and oscillator on the canvas, the two odd switches beside
  local snames = { [0] = "Attack", "Release", "Square mix", "Saw mix", "Triangle mix", "Volume", "Decay", "Extra sine mix",
                   "Extra sine tuning", "Sustain", "Pulse Width", "Global detune", "Legacy oscillator mode", "Portamento",
                   "Broken portamento (legacy)" }
  reaper.TrackFX_GetNumParams = function() return 15 end
  reaper.TrackFX_GetParamName = function(_, _, p) return true, snames[p] end
  local sctl = {}
  for p = 0, 14 do sctl[#sctl + 1] = { param = p, type = "knob", label = "" } end
  local sd = RB.default_canvas({}, 0, "rs-test", "reasynth", { controls = sctl, aliases = {} })
  local sr = sd.canvas and sd.canvas.roles or {}
  check("reasynth: an envelope canvas", (sd.canvas and sd.canvas.kind or "-") .. " " .. ("%s %s %s %s"):format(sr.Attack, sr.Decay, sr.Sustain, sr.Release), "env 0 6 9 1")
  local sp = {}
  for _, c in ipairs(sd.controls) do sp[#sp + 1] = c.param end
  check("reasynth: only the odd switches beside it", table.concat(sp, ","), "12,14")
  check("reasynth: the oscillator on the canvas", ("%s %s %s %s %s %s %s %s %s"):format(sr.Square, sr.Saw, sr.Triangle, sr.Sine2,
    sr.Sine2Tune, sr.PulseWidth, sr.Detune, sr.Portamento, sr.Volume), "2 3 4 7 8 10 11 13 5")
  -- its wave, as drawn: a sine alone; the square at its pulse width, the sine gone under it
  local RPw = require("TS_CV_RolePanel")
  check("reasynth: a sine alone", ("%.2f %.2f"):format(RPw.osc_wave(0.25, {}), RPw.osc_wave(0.75, {})), "1.00 -1.00")
  local sqo = { sq = 1, pw = 0.25 }
  check("reasynth: the square at its pulse width", ("%.0f %.0f %.0f"):format(RPw.osc_wave(0.1, sqo), RPw.osc_wave(0.3, sqo), RPw.osc_wave(0.9, sqo)), "1 -1 -1")
  check("reasynth: the extra sine an octave up", ("%.2f"):format(RPw.osc_wave(0.125, { s2 = 1, tune = 1200 }) - RPw.osc_wave(0.125, {})), "1.00")
  ED.PRO = nil
  local s2 = RB.default_canvas({}, 0, "rg-test", "reagate", dflt())
  check("reagate: without Pro, every control and no canvas", #s2.controls .. " " .. tostring(s2.canvas), "8 nil")
  ED.PRO = was
  reaper = real
end

-- a multiband of more than four bands: the probe splits in four, so the
-- first three are measured and the rest aren't
do
  local TPm = require("TS_CV_Taps")
  local gpn, gfp, fpn = reaper.TrackFX_GetParamNormalized, reaper.TrackFX_GetFormattedParamValue, reaper.TrackFX_FormatParamValueNormalized
  reaper.TrackFX_GetParamNormalized = function(_, _, p) return 0.1 + p * 0.1 end
  reaper.TrackFX_FormatParamValueNormalized = function(_, _, p, n) return true, ("%.0f Hz"):format(20 * 1000 ^ n) end
  local cv8 = { nb = 8, roles = { Crossover1 = 0, Crossover2 = 1, Crossover3 = 2, Crossover4 = 3, Crossover5 = 4, Crossover6 = 5, Crossover7 = 6 }, rev = {} }
  local plan = TPm.mb_plan({}, 0, cv8)
  local at = {}
  for k = 1, 8 do at[#at + 1] = tostring(plan.at[k]) end
  check("multiband 8: the first three measured", table.concat(at, " "), "1 2 3 nil nil nil nil nil")
  check("multiband 8: its bands", ("%d %.0f"):format(#plan.xs, plan[8].hi), "7 20000")
  reaper.TrackFX_GetParamNormalized, reaper.TrackFX_GetFormattedParamValue, reaper.TrackFX_FormatParamValueNormalized = gpn, gfp, fpn
end

-- a canvas layout's controls folded away (they pop out from the edge):
-- kept with the canvas, apart for ChannelView and the rack
do
  local M_ = require("TS_CV_Mappings")
  local cv = M_.canvas_of({ Canvas = "comp", CanvasW = "320", CanvasFold = "1" })
  check("canvas fold: read", tostring(cv.fold) .. " " .. tostring(cv.fold_rack) .. " " .. tostring(cv.w), "true nil 320")
  cv.fold_rack = true
  local out = {}
  M_.canvas_lines(cv, out)
  check("canvas fold: written", tostring(out.CanvasFold) .. " " .. tostring(out.CanvasFoldRack), "1 1")
  check("canvas fold: copied", tostring(M_.copy_canvas(cv).fold_rack), "true")
end

-- REAPER's plugins with a panel of ChannelView's: that's their Standard
-- layout; another of theirs (Copy to new layout, ...) is a normal one
do
  local RB = require("TS_CV_ReaFX")
  check("own panel: the Standard layout", tostring(RB.own_eq("ReaEQ")) .. " " .. tostring(RB.own_comp("ReaComp")), "true true")
  check("own panel: not another layout of theirs", tostring(RB.own_eq("ReaEQ :: Knobs")) .. " " .. tostring(RB.own_comp("ReaComp :: Mine")), "false false")
  check("own panel: the six", tostring(RB.has_panel("ReaDelay :: x")) .. " " .. tostring(RB.has_panel("Pro-C 3")), "true false")
  local l = { controls = {} }
  RB.ensure(nil, 0, "d", "ReaDelay :: Knobs", l)
  check("own panel: no delay canvas on another layout", tostring(l.canvas), "nil")
end

-- ChannelView and Pro at different versions: which one to update, said
-- once for each pair; Pro's own scripts (the Rack, the web bridge) won't start
do
  local ED = require("TS_CV_Edition")
  local was, ext, boxes, real = ED.mismatch, {}, {}, reaper
  reaper = setmetatable({
    GetExtState = function(ns, k) return ext[ns .. "/" .. k] or "" end,
    SetExtState = function(ns, k, v) ext[ns .. "/" .. k] = v end,
    ShowMessageBox = function(m) boxes[#boxes + 1] = m return 1 end,
  }, { __index = real })
  ED.mismatch = "3.0.0"
  check("edition: Pro behind", ED.behind(), "ChannelView Pro")
  check("edition: says so", ED.mismatch_text():find("Update ChannelView Pro:", 1, true) ~= nil, true)
  ED.mismatch = "9.0.0"
  check("edition: ChannelView behind", ED.behind(), "ChannelView")
  check("edition: 3.10 is after 3.9", (function() ED.mismatch = "3.10.0"; local r = ED.behind(); return r end)(), "ChannelView")
  ED.mismatch = "3.0.0"
  ED.warn_mismatch(); ED.warn_mismatch()
  check("edition: once for a pair", #boxes, 1)
  ED.warn_mismatch(true)
  check("edition: again when asked", #boxes, 2)
  ED.mismatch = nil
  check("edition: matched, nothing", tostring(ED.behind()) .. " " .. tostring(ED.mismatch_text()), "nil nil")
  -- Pro's check, against ChannelView's own @version
  local PRO = dofile(HERE .. "../TS_CV_Pro.lua")
  local real_std = PRO.standard_release
  PRO.standard_release = function() return PRO.RELEASE end
  check("pro check: same version runs", PRO.check("The Rack"), true)
  PRO.standard_release = function() return "3.0.0" end
  check("pro check: older ChannelView stops it", PRO.check("The Rack"), false)
  check("pro check: names ChannelView", boxes[#boxes]:find("Update ChannelView:", 1, true) ~= nil and
        boxes[#boxes]:find("the rack won't start", 1, true) ~= nil, true)
  PRO.standard_release = real_std
  check("pro check: reads ChannelView's @version", PRO.standard_release(), ED.RELEASE)
  check("pro check: ChannelView's folder holds its layouts", (PRO.standard_dir() or ""):gsub("\\", "/"):match("/$") ~= nil, true)
  ED.mismatch, reaper = was, real
end

-- Carried settings (TS_CV_Carry): a copy of a track (duplicated, pasted,
-- from a template) takes up its plugins' own settings by their places.
do
  local CR = require("TS_CV_Carry")
  local was = {}
  for _, k in ipairs({ "EnumProjExtState", "GetProjExtState", "SetProjExtState", "GetSetMediaTrackInfo_String" }) do
    was[k] = reaper[k]
  end
  local PROJ, keys = {}, {}
  local function setp(_, _, k, v)
    if PROJ[k] == nil then keys[#keys + 1] = k end
    PROJ[k] = v
  end
  reaper.SetProjExtState = setp
  reaper.GetProjExtState = function(_, _, k) return 1, PROJ[k] or "" end
  reaper.EnumProjExtState = function(_, _, i)
    local k = keys[i + 1]
    if not k then return false end
    return true, k, PROJ[k]
  end
  local EXT = {}
  reaper.GetSetMediaTrackInfo_String = function(tr, k, v, set)
    EXT[tr] = EXT[tr] or {}
    if set then EXT[tr][k] = v end
    return true, EXT[tr][k] or ""
  end
  local function tree(g1, g2, g3)
    return { tree = {
      { path = { 0 }, name = "VST3: Pro-C 3", guid = g1 },
      { path = { 1 }, name = "Container", guid = g2,
        children = { { path = { 1, 0 }, name = "JS: Saturator", guid = g3 } } },
    } }
  end
  local A, B, Cc, D = {}, {}, {}, {}
  setp(0, 0, "variant:{A1}", "Pro-C 3 :: Vocal")
  setp(0, 0, "virt:{A3}:Drive", "0.4")
  setp(0, 0, "collapsed:{A2}", "1")
  setp(0, 0, "rack_lock", "{A1}")
  check("carry: written", CR.write(A, tree("{A1}", "{A2}", "{A3}")), true)
  check("carry: not again when unchanged", CR.write(A, tree("{A1}", "{A2}", "{A3}")), false)
  check("carry: a line a setting", select(2, EXT[A][CR.KEY]:gsub("\n", "")) + 1, 3)
  check("carry: the original takes nothing", CR.adopt(A, tree("{A1}", "{A2}", "{A3}")), false)
  EXT[B] = { [CR.KEY] = EXT[A][CR.KEY] }
  check("carry: a copy takes them up", CR.adopt(B, tree("{B1}", "{B2}", "{B3}")), true)
  check("carry: the layout variant", PROJ["variant:{B1}"], "Pro-C 3 :: Vocal")
  check("carry: a virtual control, in a container", PROJ["virt:{B3}:Drive"], "0.4")
  check("carry: the folded container", PROJ["collapsed:{B2}"], "1")
  check("carry: the copy's own record", EXT[B][CR.KEY]:find("{B1}", 1, true) ~= nil
        and EXT[B][CR.KEY]:find("{A1}", 1, true) == nil, true)
  check("carry: only once", CR.adopt(B, tree("{B1}", "{B2}", "{B3}")), false)
  EXT[Cc] = { [CR.KEY] = EXT[A][CR.KEY] }
  local t = tree("{C1}", "{C2}", "{C3}")
  t.tree[1].name = "VST3: Pro-Q 4"
  CR.adopt(Cc, t)
  check("carry: another plugin in that place takes nothing", PROJ["variant:{C1}"], nil)
  check("carry: the others still do", PROJ["virt:{C3}:Drive"], "0.4")
  EXT[D] = { [CR.KEY] = EXT[A][CR.KEY] }
  setp(0, 0, "variant:{D1}", "Pro-C 3 :: Drums")
  CR.adopt(D, tree("{D1}", "{D2}", "{D3}"))
  check("carry: a plugin's own settings kept", PROJ["variant:{D1}"], "Pro-C 3 :: Drums")
  for k, f in pairs(was) do reaper[k] = f end
end

-- ---------------------------------------------------------------------
-- the patch bay (TS_CV_PatchBay)
-- ---------------------------------------------------------------------
do
  local PBt = require("TS_CV_PatchBay")
  check("bay: taller for every rail tier", PBt.height(3) - PBt.height(1), 2 * PBt.RAIL_GAP)
  check("bay: room for the deepest sag", PBt.height(1) >= PBt.jack_y(0, 1) + PBt.JACK_R + PBt.SAG_MAX, true)
  local xs, ys = PBt.curve(10, 100, 210, 100, 50)
  check("bay: a cable starts and ends on its jacks", ("%d,%d %d,%d"):format(xs[1], ys[1], xs[#xs], ys[#ys]), "10,100 210,100")
  check("bay: and sags between", math.floor(ys[math.floor(#ys / 2) + 1] + 0.5), 138)
  check("bay: near a cable", PBt.dist(xs, ys, 110, 137) < 3, true)
  check("bay: a collapsed strip's jacks side by side", PBt.jack_r(30) <= 5 and PBt.jack_x(0, 30, "out") - PBt.jack_x(0, 30, "in") >= 2 * PBt.jack_r(30) + 2, true)
  check("bay: a full strip's jacks full size", PBt.jack_r(96), PBt.JACK_R)
  check("bay: louder, thicker", PBt.width_of(1) > PBt.width_of(0.25), true)
  check("bay: the modes' dashes", tostring(PBt.dash_of(0)) .. " " .. PBt.dash_of(3)[1] .. " " .. PBt.dash_of(1)[1], "nil 9 2")
  -- drawn, open, with a folder (one hidden), a send, a sidechain, a hardware output
  local real = reaper
  local M_, F_, K_, H_, V_ = { n = "M" }, { n = "F" }, { n = "K" }, { n = "H" }, { n = "V" }
  local parent = { [K_] = F_, [H_] = F_ }
  local sends = { [K_] = { { V_, 0, 1, 0 } }, [H_] = { { V_, 0, 0.5, 2 } } }
  local hwo = { [V_] = { 2 } }
  local order = { F_, K_, H_, V_ }
  local made = {}
  reaper = setmetatable({
    GetMasterTrack = function() return M_ end,
    GetParentTrack = function(t) return parent[t] end,
    CountTracks = function() return #order end,
    GetTrack = function(_, i) return order[i + 1] end,
    GetTrackNumSends = function(t, cat) return cat == 0 and #(sends[t] or {}) or (cat == 1 and #(hwo[t] or {}) or 0) end,
    GetTrackSendInfo_Value = function(t, cat, i, k)
      if cat == 1 then return (k == "I_DSTCHAN") and hwo[t][i + 1] or ((k == "D_VOL") and 1 or 0) end
      local e = sends[t][i + 1]
      if k == "P_DESTTRACK" then return e[1] end
      if k == "I_SENDMODE" then return e[2] end
      if k == "D_VOL" then return e[3] end
      if k == "I_DSTCHAN" then return e[4] end
      return 0
    end,
    GetMediaTrackInfo_Value = function(t, k)
      if k == "B_MAINSEND" then return (t == H_) and 0 or 1 end
      if k == "IP_TRACKNUMBER" then for i, o in ipairs(order) do if o == t then return i end end return -1 end
      if k == "I_NCHAN" then return 2 end
      return 0
    end,
    GetSetMediaTrackInfo_String = function(t) return true, t.n end,
    GetNumAudioOutputs = function() return 4 end,
    GetTrackColor = function() return 0 end,
    time_precise = function() return 100 end,
    ValidatePtr2 = function() return true end,
    CreateTrackSend = function(a, b) made[#made + 1] = { a, b }; return 0 end,
    SetTrackSendInfo_Value = function() end, SetMediaTrackInfo_Value = function() end,
    Undo_BeginBlock = function() end, Undo_EndBlock = function() end,
  }, { __index = real })
  local lines = 0
  local fake = setmetatable({
    BeginChild = function() return true end, GetMousePos = function() return -100, -100 end,
    IsWindowHovered = function() return false end, GetKeyMods = function() return 0 end,
    CalcTextSize = function(_, t) return #(t or "") * 6, 12 end, GetMouseWheel = function() return 0 end,
    IsMouseDown = function() return false end, IsMouseClicked = function() return false end,
    IsKeyPressed = function() return false end, InvisibleButton = function() return false end,
    IsItemHovered = function() return false end, BeginPopup = function() return false end,
    DrawList_AddLine = function() lines = lines + 1 end,
    MouseButton_Left = 0, Mod_Alt = 4, Mod_Shift = 2, Key_Escape = 1,
  }, { __index = function(_, k)
    if k:match("^WindowFlags_") or k:match("^MouseCursor_") then return 0 end
    return function() return nil end
  end })
  local Wt = require("TS_CV_Widgets")
  local wa = { Wt.push_small, Wt.pop_small, Wt.tip }
  Wt.push_small, Wt.pop_small, Wt.tip = function() end, function() end, function() end
  PBt.attach(fake)
  PBt._st.open = true
  local list = { { track = M_, num = 0 }, { track = F_, num = 1 }, { track = V_, num = 4 } }   -- K and H hidden in F
  local rects = { { x = 0, w = 96, track = M_ }, { x = 102, w = 30, track = F_ }, { x = 138, w = 96, track = V_ } }
  local ok_, err_ = pcall(PBt.draw, "ctx", { list = list, rects = rects, row_x = 0, row_y = 0, strips_h = 200, bay_y = 200, bay_cy = 200,
    bay_h = PBt.height(PBt.tiers(list)), width = 400, hw_x = 260, cx = 0, cy = 0, sel = function() return false end })
  check("bay: draws, a collapsed folder standing for its tracks", ok_ or err_, true)
  check("bay: its cables and rails drawn", lines > 40, true)
  check("bay: a send made from a drop", PBt.connect(K_, V_, nil, 0, 2, 0, -6) and made[1][1] == K_ and made[1][2] == V_, true)
  -- re-routed: made again at the new end with its settings, the old one gone
  local sets, gone = {}, {}
  reaper.SetTrackSendInfo_Value = function(t, cat, i, k, v) sets[#sets + 1] = ("%s%d:%s=%s"):format(t.n, cat, k, tostring(v)) end
  reaper.RemoveTrackSend = function(t, cat, i) gone[#gone + 1] = ("%s%d#%d"):format(t.n, cat, i) end
  reaper.GetTrackSendInfo_Value = function(_, _, _, k) return ({ D_VOL = 0.5, I_SENDMODE = 3, I_SRCCHAN = 0 })[k] or 0 end
  made = {}
  local cK = { src = K_, dst = V_, cat = 0, idx = 0, dstch = 2 }
  local okr = PBt.reroute(cK, "dst", F_)
  local has = function(x) for _, v in ipairs(sets) do if v == x then return true end end return false end
  check("bay: re-routed to another track", okr and made[1][1] == K_ and made[1][2] == F_ and gone[1] == "K0#0", true)
  check("bay: its level, mode and channels kept", has("K0:D_VOL=0.5") and has("K0:I_SENDMODE=3") and has("K0:I_DSTCHAN=2"), true)
  made, gone, sets = {}, {}, {}
  check("bay: moved from the same track, nothing", PBt.reroute(cK, "src", K_), false)
  check("bay: onto its own track, nothing", PBt.reroute(cK, "dst", K_), false)
  check("bay: nothing made or taken", #made + #gone, 0)
  local okh = PBt.reroute(cK, "dst", nil, 2)
  check("bay: re-routed to an output", okh and made[1][2] == nil and has("K1:I_DSTCHAN=2") and gone[1] == "K0#0", true)
  made, gone, sets = {}, {}, {}
  local okm = PBt.reroute({ src = H_, hw = 0, cat = 1, idx = 0, dstch = 0 }, "src", V_)
  check("bay: an output's send moved to another track", okm and made[1][1] == V_ and has("V1:I_DSTCHAN=0") and gone[1] == "H1#0", true)
  -- a rail drop dragged off its rail switches that send off; a click on
  -- a hollow one switches it on
  do
    local mains = {}
    reaper.SetMediaTrackInfo_Value = function(t, k, v) if k == "B_MAINSEND" then mains[#mains + 1] = t.n .. "=" .. v end end
    reaper.GetTrackSendInfo_Value = function() return 0 end
    sends, hwo = {}, {}
    local list2 = { { track = M_, num = 0 }, { track = F_, num = 1 }, { track = K_, num = 2 }, { track = H_, num = 3 } }
    local rects2 = { { x = 0, w = 96, track = M_ }, { x = 102, w = 96, track = F_ }, { x = 204, w = 96, track = K_ }, { x = 306, w = 96, track = H_ } }
    local g2 = { list = list2, rects = rects2, row_x = 0, row_y = 0, strips_h = 200, bay_y = 200, bay_cy = 200, bay_h = PBt.height(PBt.tiers(list2)),
                 width = 500, hw_x = 420, cx = 0, cy = 0, sel = function() return false end }
    local ry = PBt.rail_y(200, 1)
    local kx, hx = PBt.jack_x(204, 96, "out"), PBt.jack_x(306, 96, "out")
    local mpx, mpy, down, clicked = 0, 0, false, false
    fake.GetMousePos = function() return mpx, mpy end
    fake.IsWindowHovered = function() return true end
    fake.IsMouseDown = function() return down end
    fake.IsMouseClicked = function() return clicked end
    local function frame(x, y, d, c) mpx, mpy, down, clicked = x, y, d, c; PBt.draw("ctx", g2) end
    frame(kx, ry + 8, true, true)            -- press on Kick's drop (on)
    frame(kx + 40, ry + 60, true, false)     -- pull it away
    frame(kx + 40, ry + 60, false, false)    -- let go
    frame(hx, ry + 8, true, true)            -- a click on H's (off, see B_MAINSEND above)
    frame(hx, ry + 8, false, false)
    check("bay: a drop pulled off its rail, then a hollow one clicked", table.concat(mains, " "), "K=0 H=1")
    -- a cable's far end pulled from H's IN onto F's IN: re-routed there
    sends = { [K_] = { { H_, 0, 1, 0 } } }
    reaper.GetTrackSendInfo_Value = function(t, cat, i, k)
      local e = sends[t] and sends[t][i + 1]
      if not e then return 0 end
      if k == "P_DESTTRACK" then return e[1] end
      if k == "D_VOL" then return e[3] end
      return 0
    end
    made, gone = {}, {}
    local jy = PBt.jack_y(200, PBt.tiers(list2))
    local hin, fin = PBt.jack_x(306, 96, "in"), PBt.jack_x(102, 96, "in")
    local cxs, cys = PBt.curve(kx, jy, hin, jy, PBt.sag(kx, hin))
    local gi = math.floor(#cxs * 0.8)
    frame(cxs[gi], cys[gi], true, true)       -- grab it near its far end
    frame(fin, jy, true, false)               -- over F's IN
    frame(fin, jy, false, false)              -- let go
    check("bay: a cable's end moved to another jack", #made == 1 and made[1][1] == K_ and made[1][2] == F_ and gone[1] == "K0#0", true)
    fake.IsWindowHovered = function() return false end
    fake.IsMouseDown = function() return false end
    fake.IsMouseClicked = function() return false end
    fake.GetMousePos = function() return -100, -100 end
  end
  -- the sheet up, hanging over the name row: a click on its buttons there
  -- doesn't close the bay; without it, a click outside the bay does
  do
    PBt._st.open, PBt._st.pinned = true, false
    PBt.remember({ 0, 500, 800, 510 }, { 0, 0, 800, 520 })
    PBt._st.last.bay = { 0, 200, 800, 450 }
    fake.GetMousePos = function() return 300, 505 end
    fake.IsMouseClicked = function() return true end
    fake.IsMousePosValid = function() return true end
    PBt._st.sheet = { src = K_, dst = V_ }
    PBt.reveal("ctx", false)
    local kept = PBt._st.open
    PBt._st.sheet = nil
    fake.GetMousePos = function() return 300, 100 end
    PBt.reveal("ctx", false)
    check("bay: a click under the sheet keeps it, one outside the bay closes it", tostring(kept) .. " " .. tostring(PBt._st.open), "true false")
    fake.IsMouseClicked = function() return false end
    fake.GetMousePos = function() return -100, -100 end
  end
  -- opening: the chip, the toggle action, View > Patch bay off, a pin
  -- kept for next time, and leaving the row closes it only once entered
  do
    local ext, clock = {}, 100
    local tp, ge, se, de = reaper.time_precise, reaper.GetExtState, reaper.SetExtState, reaper.DeleteExtState
    reaper.time_precise = function() return clock end
    reaper.GetExtState = function(sec, k) return ext[sec .. "/" .. k] or "" end
    reaper.SetExtState = function(sec, k, v) ext[sec .. "/" .. k] = v end
    reaper.DeleteExtState = function(sec, k) ext[sec .. "/" .. k] = nil end
    local st_ = PBt._st
    st_.open, st_.pinned, st_.sheet, st_.drag = false, false, nil, nil
    PBt.init({ pin = "pb_pin_t", req = "pb_req_t" })
    PBt.remember({ 0, 500, 800, 510 }, { 0, 0, 800, 520 })
    fake.IsMousePosValid = function() return true end
    fake.IsWindowHovered = function() return true end
    fake.GetMousePos = function() return 300, 505 end           -- on the edge
    PBt.reveal("ctx", false); clock = clock + 1; PBt.reveal("ctx", false)
    check("bay: a rest on the edge brings up the chip, not the bay",
      tostring(st_.open) .. " " .. tostring(st_.chip_at ~= nil), "false true")
    -- the chip: drawn under the pointer, a click on it opens the bay
    fake.InvisibleButton = function() return true end
    fake.GetWindowPos = function() return 286, 493 end
    fake.Begin = function() return true end
    fake.InvisibleButton = function() return false end
    local keep_at, put_x, put_y = st_.chip_at, nil, nil
    fake.SetNextWindowPos = function(_, x, y) put_x, put_y = x, y end
    st_.chip_at = { 3, 300, { 0, 90, 7, 490, side = "left", edge = 0 } }   -- the TCP window's left edge
    local oku, erru = pcall(PBt.chip, "ctx")
    check("bay: the chip draws standing up (the TCP's)", oku or erru, true)
    check("bay: the TCP's chip grows out of the window's left edge, reaching over it", put_x, -PBt.CHIP_OVER)
    -- ChannelView's stands on the row's bottom edge, kept inside the row
    st_.chip_at = { 5, 505, { 0, 497, 800, 516, side = "bottom", edge = 516 } }
    pcall(PBt.chip, "ctx")
    check("bay: ChannelView's chip stands on the row's bottom edge, inside it", tostring(put_y + 24) .. " " .. tostring(put_x >= 0), "516 true")
    fake.SetNextWindowPos = nil
    st_.chip_at = keep_at
    fake.InvisibleButton = function() return true end
    local okc, errc = pcall(PBt.chip, "ctx")
    check("bay: the chip draws", okc or errc, true)
    check("bay: a click on the chip opens it (the chip gone)", tostring(st_.open) .. " " .. tostring(st_.chip_at), "true nil")
    fake.InvisibleButton = function() return false end
    st_.open = false
    -- off the edge and the chip: it goes
    PBt.reveal("ctx", false); clock = clock + 1; PBt.reveal("ctx", false)
    local up = st_.chip_at ~= nil
    fake.GetMousePos = function() return 300, 300 end
    PBt.reveal("ctx", false); clock = clock + 1; PBt.reveal("ctx", false)
    check("bay: the chip goes once the pointer is off it and the edge", tostring(up) .. " " .. tostring(st_.chip_at), "true nil")
    st_.open = false
    -- View > Patch bay off: no chip, the action does nothing
    PBt.set_enabled(false)
    fake.GetMousePos = function() return 300, 505 end
    ext["TS_ChannelView/pb_req_t"] = "1"
    PBt.reveal("ctx", false); clock = clock + 1; PBt.reveal("ctx", false)
    check("bay: off, no chip and the action does nothing", tostring(st_.chip_at) .. " " .. tostring(st_.open), "nil false")
    PBt.set_enabled(true)
    -- the toggle action, from a shortcut with the pointer elsewhere: it
    -- stays open until the pointer has been in the row and left it
    fake.GetMousePos = function() return 300, 900 end
    ext["TS_ChannelView/pb_req_t"] = "1"
    PBt.reveal("ctx", false)
    check("bay: the toggle action opens it (its request taken)", tostring(st_.open) .. " " .. tostring(ext["TS_ChannelView/pb_req_t"]), "true nil")
    clock = clock + 1; PBt.reveal("ctx", false); clock = clock + 1; PBt.reveal("ctx", false)
    local held = st_.open
    fake.GetMousePos = function() return 300, 300 end; PBt.reveal("ctx", false)
    fake.GetMousePos = function() return 300, 900 end
    PBt.reveal("ctx", false); clock = clock + 1; PBt.reveal("ctx", false)
    check("bay: opened from outside, it waits for the pointer to come and go", tostring(held) .. " " .. tostring(st_.open), "true false")
    -- pinned: kept, and open again next time; Escape unpins
    PBt.set_pinned(true)
    st_.open, st_.pinned = false, false
    PBt.init({ pin = "pb_pin_t", req = "pb_req_t" })
    check("bay: pinned, it's open next time", tostring(st_.open) .. " " .. tostring(st_.pinned), "true true")
    fake.IsKeyPressed = function() return true end
    PBt.reveal("ctx", false)
    fake.IsKeyPressed = function() return false end
    check("bay: Escape closes and unpins it, for next time too", tostring(st_.open) .. " " .. tostring(ext["TS_ChannelView/pb_pin_t"]), "false 0")
    st_.keys = nil
    fake.IsWindowHovered = function() return false end
    fake.GetMousePos = function() return -100, -100 end
    reaper.time_precise, reaper.GetExtState, reaper.SetExtState, reaper.DeleteExtState = tp, ge, se, de
  end
  -- the TCP's bay: a column left of the rows, the same cables turned on
  -- their side
  do
    PBt._st.open, PBt._st.drag, PBt._st.move, PBt._st.rdrag = true, nil, nil, nil
    fake.GetMousePos = function() return -100, -100 end
    local l0 = lines
    local rows = { { track = M_, y = 100, h = 40 }, { track = F_, y = 142, h = 30 }, { track = V_, y = 174, h = 40 } }
    local okt, errt = pcall(PBt.draw_tcp, "ctx", { x = 0, y = 90, w = PBt.tcp_width(list), h = 400, rows = rows,
      list = list, sel = function() return true end, bay_rect = { 0, 90, 500, 490 } })
    check("bay (TCP): draws, rows for columns", okt or errt, true)
    check("bay (TCP): its rails drawn (a rail, the arrow in, two drops)", lines - l0 >= 4, true)
    check("bay (TCP): wide enough for the sag and the outputs", PBt.tcp_width(list) >= 230, true)
  end
  PBt._st.open = false
  Wt.push_small, Wt.pop_small, Wt.tip = wa[1], wa[2], wa[3]
  reaper = real
end

-- ---------------------------------------------------------------------
-- a container's own panel: which of its mapped parameters it shows
-- ---------------------------------------------------------------------
do
  local CT = require("TS_CV_Containers")
  local real = reaper
  local cfg, proj = {}, {}
  -- the container at top slot 0 (addr 0) inside an outer container (addr 9, path {3}):
  -- its params 0..3 mapped from slot 1's 0, 2, 5, 7; then Bypass, Wet, Delta
  local nparams = { [0] = 7, [9] = 4 }
  local map = { [0] = { { 1, 0 }, { 1, 2 }, { 1, 5 }, { 1, 7 } }, [9] = { { 0, 3 } } }
  reaper = setmetatable({
    TrackFX_GetNumParams = function(_, a) return nparams[a] or 0 end,
    TrackFX_GetNamedConfigParm = function(_, a, k)
      local i, what = k:match("^param%.(%d+)%.container_map%.(%w+_?%w*)$")
      if i then
        local m = map[a] and map[a][tonumber(i) + 1]
        if not m then return false, "" end
        -- REAPER deletes a mapping when this is read
        if what == "delete" then
          table.remove(map[a], tonumber(i) + 1); nparams[a] = nparams[a] - 1
          return true, ""
        end
        return true, tostring(what == "fx_index" and m[1] or m[2])
      end
      local v = cfg[a .. ":" .. k]
      return v ~= nil, v or ""
    end,
    GetProjExtState = function(_, _, k) return 1, proj[k] or "" end,
    SetProjExtState = function(_, _, k, v) proj[k] = v end,
  }, { __index = real })
  local T2 = require("TS_CV_FXTree")
  local addr_of = T2.addr_of
  T2.addr_of = function(_, path) return (#path == 1 and path[1] == 3) and 9 or nil end
  -- param 1 carries a link; param 3 is mapped up into the outer container
  cfg["0:param.1.plink.active"] = "1"
  check("container panel: mapped ones shown, ones carrying a link or mapped up left off",
    table.concat(CT.visible("tr", 0, "{C}", { 3, 0 }), ","), "0,2")
  proj["cpanel:{C}#1:2"] = "S"   -- (slot 1's parameter 2 is container param 1)
  proj["cpanel:{C}#1:5"] = "H"
  check("container panel: put on shows a link's carrier; taken off hides one",
    table.concat(CT.visible("tr", 0, "{C}", { 3, 0 }), ","), "0,1")
  check("container panel: its mapped count", CT.mapped("tr", 0), 4)
  -- a container's knob shows the link of the plugin parameter under it
  do
    local MDt = require("TS_CV_Mod")
    T2.addr_of = function(_, path)
      if #path == 1 and path[1] == 3 then return 9 end
      if #path == 3 and path[3] == 1 then return 5 end
      return nil
    end
    reaper.TrackFX_GetFXGUID = function(_, a) return a == 5 and "{P}" or nil end
    proj["cpanel:{C}#1:0"] = nil
    CT.note("tr", { { container_panel = true, visible = { 0 }, guid = "{C}", addr = 0, path_t = { 3, 0 } } })
    check("container panel: its knob stands for the plugin's parameter", MDt.aliases["{C}:0"], "{P}:0")
    check("container panel: shown once, it stays shown", proj["cpanel:{C}#1:0"], "S")
    -- the outer container's knob: down through the inner container to the plugin
    T2.addr_of = function(_, path)
      if #path == 1 and path[1] == 3 then return 9 end
      if #path == 2 and path[2] == 0 then return 0 end
      if #path == 3 and path[3] == 1 then return 5 end
      return nil
    end
    local okn = pcall(CT.note, "tr", { { container_panel = true, visible = { 0 }, guid = "{O}", addr = 9, path_t = { 3 } } })
    check("container panel: an outer container's knob reaches the plugin inside the inner one",
      tostring(okn) .. " " .. tostring(MDt.aliases["{O}:0"]), "true {P}:7")
    proj["cpanel:{O}#0:3"] = nil
    T2.addr_of = function(_, path)
      if #path == 1 and path[1] == 3 then return 9 end
      if #path == 3 and path[3] == 1 then return 5 end
      return nil
    end
    CT.note("tr", { { container_panel = true, visible = { 0 }, guid = "{C}", addr = 0, path_t = { 3, 0 } } })
    local scan = MDt.scan
    MDt.scan = function() return { links = { ["{P}:0"] = { tag = "L" } } } end
    check("container panel: a macro's link shows on both knobs",
      (MDt.link_of("tr", "{C}", 0) or {}).tag .. (MDt.link_of("tr", "{P}", 0) or {}).tag, "LL")
    MDt.scan = scan
    reaper.TrackFX_GetFXGUID = nil
    T2.addr_of = function(_, path) return (#path == 1 and path[1] == 3) and 9 or nil end
    proj["cpanel:{C}#1:0"] = nil
  end
  -- taken off: a plain mapping is deleted; one carrying a link is only hidden
  CT.take_off("tr", 0, "{C}", { 3, 0 }, 0)
  check("container panel: taken off, a plain mapping is deleted", CT.mapped("tr", 0) .. " " .. nparams[0], "3 6")
  cfg["0:param.1.plink.active"], cfg["0:param.0.plink.active"] = nil, "1"   -- its link moves down with it
  CT.take_off("tr", 0, "{C}", { 3, 0 }, 0)   -- now slot 1's param 2, put on by hand but carrying a link
  check("container panel: one carrying a link is hidden, not deleted",
    CT.mapped("tr", 0) .. " " .. tostring(proj["cpanel:{C}#1:2"]), "3 H")
  -- the container panel's own layout follows: the control gone, the ones after it renumbered
  do
    local Mt = require("TS_CV_Mappings")
    local g, st_, sv = Mt.get, Mt.set, Mt.save
    local saved
    Mt.get = function(k) return k == "Container {C}" and { controls = { { param = 0 }, { param = 2 }, { param = 3, param2 = 4 } }, grid = { cols = 4 } } or nil end
    Mt.set = function(_, l) saved = l end
    Mt.save = function() end
    CT.fix_layout("Container {C}", "Container #00000000", 2, true)
    local ps = {}
    for i, c in ipairs(saved.controls) do ps[i] = c.param .. (c.param2 and ("/" .. c.param2) or "") end
    check("container panel: its layout follows a deleted parameter", table.concat(ps, ",") .. " " .. tostring(saved.grid ~= nil), "0,2/3 true")
    Mt.get, Mt.set, Mt.save = g, st_, sv
  end
  -- the panel's layout is shared by name and what's mapped, so a copy of
  -- the container (a new guid) finds it
  do
    local Mt = require("TS_CV_Mappings")
    local g, st_, sv, hs = Mt.get, Mt.set, Mt.save, Mt.has
    local lib = { ["Container {A}"] = { controls = { { param = 0, style = "hifi" } } } }
    Mt.get = function(k) return lib[k] end
    Mt.set = function(k, l) lib[k] = l end
    Mt.has = function(k) return lib[k] ~= nil end
    Mt.save = function() end
    nparams[20], map[20] = 5, { { 1, 4 }, { 2, 6 } }
    cfg["21:fx_name"], cfg["22:fx_name"] = "VST3: Pro-Q 3 (FabFilter)", "JS: Comp"
    T2.addr_of = function(_, path)
      if #path == 1 and path[1] == 7 then return 20 end
      if #path == 2 and path[1] == 7 then return 20 + path[2] end
      return nil
    end
    local k1 = CT.key("tr", 20, "{A}", { 7 })
    check("container key: by what's mapped", k1:match("^Container #%x+$") ~= nil and CT.is_key(k1) and CT.is_key("Container {A}"), true)
    check("container key: a layout kept by guid moves to it", lib[k1] and lib[k1].controls[1].style, "hifi")
    check("container key: a copy (another guid) shares it", CT.key("tr", 20, "{B}", { 7 }), k1)
    cfg["20:renamed_name"] = "Vox [bus]"
    local k2 = CT.key("tr", 20, nil, { 7 })
    check("container key: its name in it", k2, "Container Vox bus #" .. k1:match("#(%x+)$"))
    map[20][2] = { 2, 7 }
    check("container key: other parameters, another key", CT.key("tr", 20, nil, { 7 }) ~= k2, true)
    -- put on: the layout goes to the new key with the control at the end
    CT.carry(k1, "Container #11111111", function(l, own) if own then l.controls[#l.controls + 1] = { param = 1 } end end)
    check("container key: carried, the old one left for the others",
      #lib["Container #11111111"].controls .. " " .. #lib[k1].controls, "2 1")
    check("container key: not a plugin's", CT.is_key("Containerizer") or CT.is_key("Container Pro (X)"), false)
    cfg["20:renamed_name"], cfg["21:fx_name"], cfg["22:fx_name"] = nil, nil, nil
    nparams[20], map[20] = nil, nil
    T2.addr_of = function(_, path) return (#path == 1 and path[1] == 3) and 9 or nil end
    Mt.get, Mt.set, Mt.save, Mt.has = g, st_, sv, hs
  end
  CT.set_folded("{C}", true)
  check("container panel: folded is kept in the project", CT.folded("{C}") and proj["cfold:{C}"] == "1", true)
  T2.addr_of = addr_of
  reaper = real
end

-- ---------------------------------------------------------------------
-- plugin pictures (TS_CV_Thumbs): keys, the queue, taking one on a
-- temporary track
-- ---------------------------------------------------------------------
do
  local real = reaper
  local tmp = os.tmpname(); os.remove(tmp)
  local root = tmp .. "_res"
  os.execute('mkdir -p "' .. root .. '/Data"')
  local tracks, shown, deleted, captured, now = {}, {}, 0, 0, 100
  local blur = 0           -- what the window shows changes while it's above 0
  local ext = {}
  reaper = setmetatable({
    GetOS = function() return "Win64" end,
    GetResourcePath = function() return root end,
    RecursiveCreateDirectory = function(p) os.execute('mkdir -p "' .. p .. '"') return 1 end,
    time_precise = function() return now end,
    JS_Window_GetRect = function() return true end, JS_GDI_GetScreenDC = function() return 1 end,
    JS_LICE_CreateBitmap = function() return {} end, JS_LICE_WritePNG = function(p)
      captured = captured + 1; local f = io.open(p, "wb"); f:write("png"); f:close(); return true end,
    JS_Window_GetClientRect = function() return true, 0, 0, 300, 200 end,
    JS_GDI_Blit = function() end, JS_LICE_GetDC = function() return 1 end, JS_GDI_ReleaseDC = function() end,
    JS_LICE_DestroyBitmap = function() end,
    JS_LICE_GetPixel = function(_, x, y) return (x * 7 + y + blur) & 0xffffff end,   -- not blank
    CountTracks = function() return #tracks end,
    InsertTrackAtIndex = function(i) tracks[#tracks + 1] = { n = i } end,
    GetTrack = function(_, i) return tracks[i + 1] end,
    GetSetMediaTrackInfo_String = function() return true, "" end,
    SetMediaTrackInfo_Value = function() end,
    PreventUIRefresh = function() end,
    TrackFX_AddByName = function(_, ident) return ident == "bad" and -1 or 0 end,
    TrackFX_Show = function(_, _, how) shown[#shown + 1] = how end,
    TrackFX_GetFloatingWindow = function() return "HWND" end,
    ValidatePtr = function(t) return t ~= nil and not t.gone end,
    DeleteTrack = function(t) t.gone = true; deleted = deleted + 1 end,
    TrackList_AdjustWindows = function() end,
    SetExtState = function(_, k, v) ext[k] = v end,
    GetExtState = function(_, k) return ext[k] or "" end,
  }, { __index = real })
  package.loaded["TS_CV_Thumbs"] = nil
  local THt = require("TS_CV_Thumbs")
  check("thumbs: a plugin's key leaves out its format and developer", THt.key("VST3: Pro-Q 4 (FabFilter)"), "Pro-Q 4")
  check("thumbs: VST2 and VST3 share one", THt.key("VST: Pro-Q 4 (FabFilter) (2 out)") == THt.key("VST3: Pro-Q 4 (FabFilter)"), true)
  check("thumbs: a JSFX by its file", THt.key("JS: utility/volume.jsfx"), "volume")
  check("thumbs: none yet", THt.has("Pro-Q 4"), false)
  THt.want("C:\\x\\Pro-Q 4.vst3", "VST3: Pro-Q 4 (FabFilter)")
  THt.want("C:\\x\\Pro-Q 4.vst3", "VST3: Pro-Q 4 (FabFilter)")
  local q = THt._q()
  check("thumbs: asked for once", #q, 1)
  THt.tick()                                   -- the temporary track, the plugin, its window
  check("thumbs: a temporary track, the plugin floated", #tracks .. " " .. tostring(shown[1]), "1 3")
  THt.tick()                                   -- the window found
  now = now + 0.5; THt.tick()
  check("thumbs: not before it has drawn itself", captured, 0)
  -- it opens blurred: what it shows keeps changing for a while
  blur = 0x404040
  now = now + 1.0; THt.tick()
  blur = 0x202020
  now = now + 0.5; THt.tick()
  blur = 0x101010
  now = now + 0.5; THt.tick()
  check("thumbs: not while it's still coming into focus", captured, 0)
  blur = 0
  now = now + 0.5; THt.tick()
  check("thumbs: still settling (one look sharp)", captured, 0)
  now = now + 0.5; THt.tick()
  check("thumbs: taken once it has held still, and the track gone", captured .. " " .. deleted .. " " .. tostring(THt.has("Pro-Q 4")), "1 1 true")
  THt.want("x", "VST3: Pro-Q 4 (FabFilter)")
  check("thumbs: not again once there", #THt._q(), 0)
  THt.want("bad", "VST: Nope (X)")
  THt.tick()
  check("thumbs: a plugin that won't load leaves no track behind", deleted, 2)
  THt.remove("Pro-Q 4")
  check("thumbs: removed", THt.has("Pro-Q 4"), false)
  -- each window has its own images: one that looked before the picture
  -- was taken in another finds it once it's there
  local fake = { ValidatePtr = function(i) return i ~= nil end, CreateImage = function(p) return { p = p } end }
  THt.attach(fake)
  package.loaded["TS_CV_Thumbs"] = nil
  local other = require("TS_CV_Thumbs")
  other.attach(fake)
  check("thumbs: no picture yet in the other window", other._image("Pro-Q 4"), nil)
  THt.capture("HWND", "Pro-Q 4")
  now = now + 0.6
  check("thumbs: the other window sees the new picture", other._image("Pro-Q 4") ~= nil, true)
  check("thumbs: a missing one isn't looked for every frame", other._image("Fresh"), nil)
  local f = io.open(other.dir() .. "Fresh.png", "wb"); f:write("png"); f:close()
  now = now + 0.1
  check("thumbs: not straight away", other._image("Fresh"), nil)
  now = now + other.RECHECK
  check("thumbs: ...but is again after a moment (a file put there by hand)", other._image("Fresh") ~= nil, true)
  os.execute('rm -rf "' .. root .. '"')
  package.loaded["TS_CV_Thumbs"] = nil
  reaper = real
end

-- ---------------------------------------------------------------------
-- plugin pictures: a plugin's window open in REAPER, taken once it has
-- settled with nothing over it; taken again when asked
-- ---------------------------------------------------------------------
do
  local real = reaper
  local tmp = os.tmpname(); os.remove(tmp)
  local root = tmp .. "_res2"
  os.execute('mkdir -p "' .. root .. '/Data"')
  local now, captured, covered, open = 100, 0, false, true
  local track = { name = "T1" }
  local shown = 0
  reaper = setmetatable({
    GetOS = function() return "Win64" end,
    GetResourcePath = function() return root end,
    RecursiveCreateDirectory = function(p) os.execute('mkdir -p "' .. p .. '"') return 1 end,
    time_precise = function() return now end,
    JS_Window_GetRect = function() return true end, JS_GDI_GetScreenDC = function() return 1 end,
    JS_LICE_CreateBitmap = function() return {} end, JS_LICE_WritePNG = function(p)
      captured = captured + 1; local f = io.open(p, "wb"); f:write("png"); f:close(); return true end,
    JS_Window_GetClientRect = function() return true, 0, 0, 300, 200 end,
    JS_GDI_Blit = function() end, JS_LICE_GetDC = function() return 1 end, JS_GDI_ReleaseDC = function() end,
    JS_LICE_DestroyBitmap = function() end,
    JS_LICE_GetPixel = function(_, x, y) return (x * 7 + y) & 0xffffff end,
    JS_Window_FromPoint = function() return covered and "OTHER" or "PLUG" end,
    JS_Window_IsChild = function() return false end,
    JS_Window_IsWindow = function() return open end,
    CountTracks = function() return 1 end,
    GetTrack = function() return track end,
    GetMasterTrack = function() return { name = "M" } end,
    TrackFX_GetCount = function(t) return t == track and 1 or 0 end,
    TrackFX_GetFloatingWindow = function(t) return (t == track and open) and "PLUG" or nil end,
    TrackFX_GetNamedConfigParm = function(_, _, k)
      if k == "fx_name" then return true, "VST3: Dimension (Acme)" end
      return false, ""
    end,
    TrackFX_Show = function() shown = shown + 1; open = true end,
    GetTouchedOrFocusedFX = function() return false end,
    ValidatePtr = function() return true end,
    SetExtState = function() end, GetExtState = function() return "" end,
  }, { __index = real })
  package.loaded["TS_CV_Thumbs"] = nil
  local THw = require("TS_CV_Thumbs")
  THw.watch = true
  covered = true
  for _ = 1, 20 do now = now + 0.25; THw.tick() end
  check("thumbs watch: not while something's over the window", captured, 0)
  covered = false
  for _ = 1, 3 do now = now + 0.25; THw.tick() end
  check("thumbs watch: not straight after it comes clear", captured, 0)
  for _ = 1, 12 do now = now + 0.25; THw.tick() end
  check("thumbs watch: taken once clear and settled", captured, 1)
  for _ = 1, 20 do now = now + 0.25; THw.tick() end
  check("thumbs watch: once", captured, 1)
  -- taken again when asked, with the watch off and the window closed
  THw.watch, open = false, false
  THw.retake(track, 0)
  check("thumbs retake: the window opened", shown, 1)
  for _ = 1, 20 do now = now + 0.25; THw.tick() end
  check("thumbs retake: taken again", captured, 2)
  for _ = 1, 20 do now = now + 0.25; THw.tick() end
  check("thumbs retake: once", captured, 2)
  os.execute('rm -rf "' .. root .. '"')
  package.loaded["TS_CV_Thumbs"] = nil
  reaper = real
end

-- ---------------------------------------------------------------------
-- plugin pictures, many at once: those without one, one after another,
-- waiting while REAPER plays, stopped on request
-- ---------------------------------------------------------------------
do
  local real = reaper
  local tmp = os.tmpname(); os.remove(tmp)
  local root = tmp .. "_res3"
  os.execute('mkdir -p "' .. root .. '/Data/TS_ChannelView_Thumbs"')
  local f = io.open(root .. "/Data/TS_ChannelView_Thumbs/Have.png", "wb"); f:write("png"); f:close()
  local now, play, added, tracks = 100, 0, {}, {}
  reaper = setmetatable({
    GetOS = function() return "Win64" end,
    GetResourcePath = function() return root end,
    time_precise = function() return now end,
    JS_Window_GetRect = function() return true end, JS_GDI_GetScreenDC = function() return 1 end,
    JS_LICE_CreateBitmap = function() return {} end, JS_LICE_WritePNG = function() return true end,
    GetPlayState = function() return play end,
    CountTracks = function() return #tracks end,
    InsertTrackAtIndex = function() tracks[#tracks + 1] = {} end,
    GetTrack = function(_, i) return tracks[i + 1] end,
    GetSetMediaTrackInfo_String = function() return true, "" end,
    SetMediaTrackInfo_Value = function() end,
    PreventUIRefresh = function() end,
    TrackFX_AddByName = function(_, ident) added[#added + 1] = ident; return 0 end,
    TrackFX_Show = function() end,
    TrackFX_GetFloatingWindow = function() return nil end,
    ValidatePtr = function(t) return t ~= nil and not t.gone end,
    DeleteTrack = function(t) t.gone = true end,
    TrackList_AdjustWindows = function() end,
    TrackCtl_SetToolTip = function() end,
    GetMainHwnd = function() return "MAIN" end,
  }, { __index = real })
  package.loaded["TS_CV_Thumbs"] = nil
  local THb = require("TS_CV_Thumbs")
  local list = { { ident = "a", name = "VST3: Have (X)" }, { ident = "b", name = "VST3: One (X)" },
                 { ident = "c", name = "VST3: Two (X)" }, { ident = "d", name = "VST: One (X)" } }
  check("bulk: how many need one", THb.missing(list), 2)
  check("bulk: those asked for", THb.want_many(list), 2)
  check("bulk: progress", table.concat({ THb.progress() }, "/"), "0/2")
  play = 1
  THb.tick()
  check("bulk: waits while REAPER plays", #added, 0)
  play = 0
  THb.tick()
  check("bulk: then starts", added[1], "b")
  THb.stop()
  THb.tick()
  check("bulk: stopped", tostring(THb.progress()) .. " " .. #added .. " " .. tostring(tracks[1].gone), "nil 1 true")
  os.execute('rm -rf "' .. root .. '"')
  package.loaded["TS_CV_Thumbs"] = nil
  reaper = real
end

-- ---------------------------------------------------------------------
-- popped-out panels (TS_CV_PopOut): windows of pinned panels, saved with
-- the project, found again by GUID
-- ---------------------------------------------------------------------
do
  local real = reaper
  local ext = {}
  local proj = "P1"
  local trA, trB, master = { g = "{A}" }, { g = "{B}" }, { g = "{M}" }
  local fxs = { [trA] = { "{f1}", "{f2}" }, [trB] = { "{f3}" }, [master] = {} }
  reaper = setmetatable({
    EnumProjects = function() return proj end,
    GetProjExtState = function(_, _, k) return 1, ext[proj .. k] or "" end,
    SetProjExtState = function(_, _, k, v) ext[proj .. k] = v end,
    ValidatePtr2 = function() return true end,
    GetTrackGUID = function(t) return t.g end,
    GetMasterTrack = function() return master end,
    CountTracks = function() return 2 end,
    GetTrack = function(_, i) return ({ trA, trB })[i + 1] end,
    TrackFX_GetFXGUID = function(t, i) return fxs[t][i + 1] end,
    time_precise = function() return 10 end,
  }, { __index = real })
  package.loaded["TS_CV_PopOut"] = nil
  local Tm = require("TS_CV_FXTree")
  local real_collect, real_guid_at = Tm.collect, Tm.guid_at
  Tm.collect = function(t)
    local out = {}
    for i, g in ipairs(fxs[t]) do out[#out + 1] = { guid = g, addr = i - 1, name = "VST: X" .. i } end
    return out
  end
  Tm.guid_at = function(t, addr) return fxs[t][addr + 1] end
  local POm = require("TS_CV_PopOut")
  local w = POm.new_window("Mix watch")
  check("popout: a new window", #POm.windows() .. " " .. w.name, "1 Mix watch")
  check("popout: a panel added", POm.add(w.id, "{A}", "{f2}"), true)
  check("popout: not twice", POm.add(w.id, "{A}", "{f2}"), false)
  POm.add(w.id, "{B}", "{f3}")
  local tr, fx = POm.resolve("{A}", "{f2}")
  check("popout: found by guid", (tr == trA) and fx and fx.addr, 1)
  -- the chain changes under it: found where it went
  fxs[trA] = { "{f2}", "{f1}" }
  tr, fx = POm.resolve("{A}", "{f2}")
  check("popout: found again after a move", fx and fx.addr, 0)
  fxs[trA] = { "{f1}" }
  tr, fx = POm.resolve("{A}", "{f2}")
  check("popout: a plugin gone, its track still there", tostring(tr == trA) .. " " .. tostring(fx), "true nil")
  check("popout: a track gone", POm.resolve("{Z}", "{f1}"), nil)
  -- saved with the project, read again on a project switch
  POm.rename(w.id, "Bus\tthings")
  proj = "P2"
  check("popout: another project has its own", #POm.windows(), 0)
  proj = "P1"
  local back = POm.windows()
  check("popout: back with the project", #back .. " " .. back[1].name .. " " .. #back[1].panels, "1 Bus things 2")
  check("popout: the panels' order kept", back[1].panels[2].f, "{f3}")
  POm.set_dir(w.id, "down")
  local d = POm.decode(POm.encode(POm._data()))
  check("popout: encode/decode", d.windows[1].panels[1].t .. d.windows[1].panels[1].f .. d.next .. d.windows[1].dir, "{A}{f2}2down")
  check("popout: an older line reads as auto", POm.decode("3\tOld\t0\t{A},{f1}").windows[1].dir .. #POm.decode("3\tOld\t0\t{A},{f1}").windows[1].panels, "auto1")
  -- moving, nudging, taking out
  POm.nudge(w.id, 1, 1)
  check("popout: nudged", POm.window(w.id).panels[1].f, "{f3}")
  local w2 = POm.move(w.id, 1, nil, "Bass")
  check("popout: moved to a window of its own", #POm.windows() .. " " .. w2.name .. " " .. #POm.window(w.id).panels, "2 Bass 1")
  check("popout: which windows have it", POm.windows_with("{f3}")[w2.id], true)
  POm.take_out(w.id, 1)
  check("popout: a window goes with its last panel", #POm.windows(), 1)
  POm.close(w2.id)
  check("popout: closed", #POm.windows(), 0)
  Tm.collect, Tm.guid_at = real_collect, real_guid_at
  package.loaded["TS_CV_PopOut"] = nil
  reaper = real
end

-- ---------------------------------------------------------------------
-- a compressor's attack and release, timed (TS_CV_Learn LN.time_fit) and
-- kept with its canvas (AtkCal / RelCal)
-- ---------------------------------------------------------------------
do
  local LNt = require("TS_CV_Learn")
  local Mt = require("TS_CV_Mappings")
  -- a modelled compressor: its reduction a one-pole in dB, 5 ms in, 100 ms out
  local g, L = {}, {}
  local gr, dt = 0, LNt.TIME_DT / 1000
  for i = 1, 7000 do
    local t = i * dt
    local lv = (t > 0.2 and t < 1.4) and -10 or -50
    local want = math.max(0, lv + 30) * 0.9
    local tau = (want > gr) and 0.005 or 0.1
    gr = want + (gr - want) * math.exp(-dt / tau)
    g[i], L[i] = -gr, lv
  end
  local atk, rel, depth = LNt.time_fit(g, L)
  check("timing: attack and release read off the step (within half a millisecond, 2 ms)",
    math.abs((atk or 0) - 5) < 0.5 and math.abs((rel or 0) - 100) < 2 and math.abs((depth or 0) - 18) < 0.1, true)
  local none = {}
  for i = 1, 7000 do none[i] = 0 end
  local a2, why = LNt.time_fit(none, L)
  check("timing: no reduction, said", tostring(a2) .. " " .. tostring(why), "nil it reduced only 0.0 dB")
  check("timing: it moves", tostring(LNt.time_moves({ { 0, 1 }, { 1, 1.05 } })) .. tostring(LNt.time_moves({ { 0, 1 }, { 1, 30 } })), "falsetrue")
  -- kept in the library and read back
  local cv = Mt.canvas_of({ Canvas = "comp", RoleAttack = "3", RoleRelease = "4",
    AtkCal = "3|0:1 0.5:10 1:100", RelCal = "4|0:50 1:2000" })
  check("timing: read back", cv.atk_cal and (#cv.atk_cal.pts .. " " .. cv.rel_cal.p), "3 4")
  check("timing: in ms between the points (log)", ("%.2f %.1f %.0f"):format(Mt.time_ms(cv, "Attack", 0.25), Mt.time_ms(cv, "Attack", 0.5), Mt.time_ms(cv, "Release", 1)), "3.16 10.0 2000")
  local out = {}
  Mt.canvas_lines(cv, out)
  check("timing: written", out.AtkCal .. " / " .. out.RelCal, "3|0:1 0.5:10 1:100 / 4|0:50 1:2000")
  check("timing: copied with the canvas", Mt.copy_canvas(cv).rel_cal.pts[2][2], 2000)
  cv.roles.Attack = 5
  check("timing: not for another control", tostring(Mt.time_cal(cv, "Attack")), "nil")
  check("timing: short", Mt.ms_text(0.3) .. ", " .. Mt.ms_text(12.4) .. ", " .. Mt.ms_text(1200), "0.3 ms, 12 ms, 1.2 s")
  -- copied by its real time: A measured (a 0..10 scale) onto B's measured switch
  do
    local CMPt = require("TS_CV_Compare")
    local real = reaper
    local norm = { [1] = { [3] = 0.5 }, [2] = { [7] = 0 } }
    reaper = setmetatable({
      TrackFX_GetParamNormalized = function(_, a, p) return norm[a][p] or 0 end,
      TrackFX_SetParamNormalized = function(_, a, p, v) norm[a][p] = v end,
      TrackFX_FormatParamValueNormalized = function(_, a, p, n)
        if a == 2 then return true, ({ "Fast", "Medium", "Slow", "Slower" })[math.min(4, math.floor(n * 4) + 1)] end
        return true, ("%.1f"):format(n * 10)
      end,
      TrackFX_GetFormattedParamValue = function(_, a, p) return true, ("%.1f"):format((norm[a][p] or 0) * 10) end,
      TrackFX_GetFXGUID = function(_, a) return "{tm" .. a .. "}" end,
    }, { __index = real })
    local acv = { roles = { Attack = 3 }, atk_cal = { p = 3, pts = { { 0, 1 }, { 0.5, 10 }, { 1, 100 } } } }
    local bcv = { roles = { Attack = 7 }, atk_cal = { p = 7, pts = { { 0.125, 0.3 }, { 0.375, 3 }, { 0.625, 9 }, { 0.875, 30 } } } }
    local what, txt = CMPt.copy_time("tr", 1, 3, acv, 2, 7, bcv, "Attack")
    check("timing: copied by time onto the nearest setting (Slow)",
      tostring(what) .. " " .. tostring(txt):gsub("^[%d%.]+ ms", "x ms") .. " " .. tostring(norm[2][7] > 0.5 and norm[2][7] < 0.75),
      "near x ms for 10 ms true")
    check("timing: neither measured, left to the plain copy", tostring(CMPt.copy_time("tr", 1, 3, nil, 2, 7, nil, "Attack")), "nil")
    reaper = real
  end
end

-- ---------------------------------------------------------------------
-- the EQ canvas setup: bands moved by dragging, and sorted
-- ---------------------------------------------------------------------
do
  local CSt = require("TS_CV_CanvasSetup")
  local function names(bs) local t = {} for i, b in ipairs(bs) do t[i] = b.name end return table.concat(t, ",") end
  local function bands() return { { name = "1", freq = 0 }, { name = "2", freq = 4 }, { name = "4", freq = 12 }, { name = "3", freq = 8 } } end
  local b = bands()
  check("eq bands: dragged up", tostring(CSt.move_band(b, 3, 5)) .. " " .. names(b), "4 1,2,3,4")
  b = bands()
  check("eq bands: dragged to the top", tostring(CSt.move_band(b, 4, 1)) .. " " .. names(b), "1 3,1,2,4")
  b = bands()
  check("eq bands: dropped where it was", tostring(CSt.move_band(b, 2, 3)) .. tostring(CSt.move_band(b, 2, 2)) .. " " .. names(b), "nilnil 1,2,4,3")
  check("eq bands: plugin order", names(CSt.plugin_order(bands())), "1,2,3,4")
  check("eq bands: plugin order, by any of a band's parameters, unmapped last",
    names(CSt.plugin_order({ { name = "x" }, { name = "b", gain = 9, q = 10 }, { name = "a", q = 2 } })), "a,b,x")
end

-- ---------------------------------------------------------------------
-- comparing two plugins (TS_CV_Compare)
-- ---------------------------------------------------------------------
do
  local CMP = require("TS_CV_Compare")
  local real = reaper
  -- the record
  local st = CMP.decode(CMP.encode({ c = "{C}", a = "{A}", b = "{B}", s = "{S}", blind = 1, order = "BA", gr = 0, ap = "1:0,2:0" }))
  check("compare: record round trip", st and (st.c .. st.a .. st.b .. st.s .. tostring(st.blind) .. st.order .. tostring(st.gr) .. st.ap),
    "{C}{A}{B}{S}trueBAfalse1:0,2:0")
  check("compare: a record missing a part is none", CMP.decode("c={C};a={A}"), nil)
  -- values in units
  local function v(t, u) local x = CMP.value(t, u); return x and (math.floor(x * 1000 + 0.5) / 1000) end
  check("compare: ratio", v("4.0:1", "ratio"), 4)
  check("compare: ratio, a plain number", v("4.0", "ratio"), 4)
  check("compare: ratio, infinite capped", v("\u{221E}:1", "ratio"), 1000)
  check("compare: ms", v("10.0 ms", "ms"), 10)
  check("compare: seconds as ms", v("0.3 s", "ms"), 300)
  check("compare: kHz", v("1.2 kHz", "hz"), 1200)
  check("compare: a plain frequency", v("1000.0", "hz"), 1000)
  check("compare: a plain number too low for a frequency", v("2.0", "hz"), nil)
  check("compare: octaves as Q", v("2.00 oct", "q"), 0.667)
  check("compare: Q", v("0.71", "q"), 0.71)
  check("compare: dB", v("-3.5 dB", "db"), -3.5)
  check("compare: a word isn't a time", v("Auto", "ms"), nil)
  check("compare: ms isn't dB", v("10 ms", "db"), nil)
  check("compare: shapes", table.concat({ CMP.canon("Low Shelf"), CMP.canon("HP"), CMP.canon("Bell"),
    CMP.canon("Peak"), CMP.canon("High Cut"), CMP.canon("Low Pass"), CMP.canon("Off") }, ","),
    "lowshelf,lowcut,bell,bell,highcut,highcut,off")
  check("compare: near", tostring(CMP.near(120, 121, "ms")) .. tostring(CMP.near(120, 100, "ms"))
    .. tostring(CMP.near(-3, -3.1, "db")) .. tostring(CMP.near(-3, -3.5, "db")), "truefalsetruefalse")
  -- copying by role: A's ratio, attack and release onto a B with stepped
  -- ratios and releases; threshold left for Match GR; knee B hasn't got
  do
    local norm = { [1] = { [0] = 3 / 19, [1] = math.log(100) / math.log(300), [2] = 110 / 990, [3] = 0.5, [4] = 0.3 },
                   [2] = { [0] = 0, [1] = 0, [2] = 0.9, [3] = 0.5 } }
    local function text(addr, p, n)
      if addr == 1 then
        if p == 0 then return ("%.1f:1"):format(1 + n * 19) end
        if p == 1 then return ("%.1f ms"):format(0.1 * 300 ^ n) end
        if p == 2 then return ("%.0f ms"):format(10 + n * 990) end
        if p == 3 then return ("%.1f dB"):format(-60 + n * 60) end
        if p == 4 then return ("%.1f dB"):format(n * 20) end
      else
        local function step(list) return list[math.min(#list, math.floor(n * #list) + 1)] end
        if p == 0 then return step({ "1.5:1", "2:1", "4:1", "10:1" }) end
        if p == 1 then return ("%.2f ms"):format(0.05 * 1000 ^ n) end
        if p == 2 then return step({ "0.1 s", "0.3 s", "0.6 s", "1.2 s" }) end
        if p == 3 then return ("%.1f dB"):format(-40 + n * 40) end
      end
    end
    reaper = setmetatable({
      TrackFX_FormatParamValueNormalized = function(_, a, p, n) return true, text(a, p, n) end,
      TrackFX_GetFormattedParamValue = function(_, a, p) return true, text(a, p, norm[a][p]) end,
      TrackFX_GetParamNormalized = function(_, a, p) return norm[a][p] end,
      TrackFX_SetParamNormalized = function(_, a, p, n) norm[a][p] = n end,
      TrackFX_GetFXGUID = function(_, a) return "{cmpfx" .. a .. "}" end,
      TrackFX_GetNumParams = function() return 8 end,
    }, { __index = real })
    local roles = CMP.roles_of
    CMP.roles_of = function(_, addr)
      if addr == 1 then return { kind = "comp", roles = { Ratio = 0, Attack = 1, Release = 2, Threshold = 3, Knee = 4 } } end
      return { kind = "comp", roles = { Ratio = 0, Attack = 1, Release = 2, Threshold = 3 } }
    end
    local res = CMP.copy("tr", { addr = 1, guid = "{a}", name = "VST3: Comp A (X)" }, { addr = 2, guid = "{b}", name = "VST3: Comp B (Y)" })
    check("compare: copied by role", res and (res.done .. "|" .. table.concat(res.near, ",") .. "|" .. table.concat(res.missed, ",")),
      "2|Release (0.1 s)|Knee")
    check("compare: B's ratio and attack", text(2, 0, norm[2][0]) .. " " .. text(2, 1, norm[2][1]), "4:1 10.00 ms")
    check("compare: B's threshold left alone", norm[2][3], 0.5)
    -- two of the same plugin: control for control
    local res2 = CMP.copy("tr", { addr = 1, guid = "{a}", name = "VST3: Comp A (X)" }, { addr = 2, guid = "{b}", name = "VST3: Comp A (X)" })
    check("compare: the same plugin, control for control", res2.done .. " " .. tostring(norm[2][4] == norm[1][4]), "5 true")
    -- different kinds
    CMP.roles_of = function(_, addr) return { kind = addr == 1 and "comp" or "eq", roles = {}, bands = {} } end
    local r3, why = CMP.copy("tr", { addr = 1, name = "A" }, { addr = 2, name = "B" })
    check("compare: different kinds aren't copied", tostring(r3) .. " " .. tostring(why), "nil they're different kinds of plugin")
    CMP.roles_of = roles
    reaper = real
  end
  -- the row leaves the switch out, and the container's bracket ends at B
  do
    local proj = { ["compare:{T}"] = "c={C};a={A};b={B};s={S}" }
    reaper = setmetatable({
      GetTrackGUID = function() return "{T}" end,
      -- (the record lives on the track; here, in the same slot the tests seed)
      GetSetMediaTrackInfo_String = function(_, k, v, set)
        local key = (k == "P_EXT:TS_CV_compare") and "compare:{T}" or k
        if set then proj[key] = v return true, v end
        return true, proj[key] or ""
      end,
      GetProjExtState = function(_, _, k) return 1, proj[k] or "" end,
      SetProjExtState = function(_, _, k, val) proj[k] = val end,
      time_precise = function() return 100 end,
    }, { __index = real })
    local node = { path = { 2 }, kind = "container", children = {} }
    local list = { { guid = "{A}", path_t = { 2, 0 } }, { guid = "{B}", path_t = { 2, 1 } }, { guid = "{S}", path_t = { 2, 2 } },
                   tree = { node } }
    local out = CMP.strip("tr", list)
    check("compare: the switch has no panel", #out .. " " .. out[2].guid .. " " .. node.first .. "-" .. node.last, "2 {B} 1-2")
    local Tt = require("TS_CV_FXTree")
    local collect, guid_at = Tt.collect, Tt.guid_at
    local present = { "{C}", "{A}", "{B}", "{S}" }
    Tt.collect = function()
      local kids = {}
      for k = 2, #present do kids[#kids + 1] = { guid = present[k], addr = 10 + k, path = { 2, k - 2 } } end
      return { tree = { { guid = present[1], addr = 10, path = { 2 }, kind = "container", children = kids } } }
    end
    Tt.guid_at = function() return nil end
    check("compare: sides", tostring(CMP.side_of("tr", "{A}")) .. tostring(CMP.side_of("tr", "{B}")) .. tostring(CMP.side_of("tr", "{S}")), "ABnil")
    check("compare: its container", CMP.is_container("tr", "{C}") and not CMP.is_container("tr", "{X}"), true)
    present = { "{C}", "{A}", "{S}" }
    check("compare: B gone, no sides (the bar offers to finish)", tostring(CMP.side_of("tr", "{A}")) .. " " .. tostring(CMP.load("tr") ~= nil), "nil true")
    present = { "{X}" }
    check("compare: its container gone (undone), forgotten", tostring(CMP.parts("tr", true)) .. " " .. tostring(proj["compare:{T}"]), "nil ")
    proj["compare:{T}"] = "c={C};a={A};b={B};s={S}"
    CMP.clear("tr")
    check("compare: cleared", tostring(CMP.load("tr")), "nil")
    do
      -- a record kept in the project's ext state (before it lived on the
      -- track) moves onto the track when read
      local ext, onto = {}, {}
      local was = reaper
      reaper = setmetatable({
        GetTrackGUID = function() return "{T2}" end,
        GetProjExtState = function(_, _, k) return 1, ext[k] or "" end,
        SetProjExtState = function(_, _, k, val) ext[k] = val end,
        GetSetMediaTrackInfo_String = function(_, k, v, set)
          if set then onto[k] = v return true, v end
          return true, onto[k] or ""
        end,
        time_precise = function() return 300 end,
      }, { __index = was })
      ext["compare:{T2}"] = "c={C};a={A};b={B};s={S};blind=1"
      local got = CMP.load("tr2")
      check("compare: an older record moves onto the track",
        tostring(got and got.blind) .. " " .. tostring(onto["P_EXT:TS_CV_compare"]) .. " [" .. ext["compare:{T2}"] .. "]",
        "true c={C};a={A};b={B};s={S};blind=1 []")
      -- an undo puts the track's data back: the record comes with it
      CMP.clear("tr2")
      onto["P_EXT:TS_CV_compare"] = "c={C};a={A};b={B};s={S};blind=1"
      CMP.forget_cache()
      local back = CMP.load("tr2")
      check("compare: back after an undo, blind and all", tostring(back and back.blind), "true")
      reaper = was
      CMP.forget_cache()
    end
    Tt.collect, Tt.guid_at = collect, guid_at
    reaper = real
  end
  check("compare: an octave's Q", math.floor(CMP.oct_to_q(1) * 1000 + 0.5) / 1000, 1.414)
  -- ready to copy into: a canvas of the kind, learned for an EQ, in the
  -- plugin's own layout or another of its layouts
  do
    local Mt = require("TS_CV_Mappings")
    local g, dv, vs, todo = Mt.get, Mt.default_variant, Mt.variants, Mt.canvas_todo
    local lib = {
      ["EQ-PB :: EQ"] = { canvas = { kind = "eq", bands = { { freq = 1 } } } },
      ["Comp X"] = { canvas = { kind = "comp", roles = { Ratio = 2 } } },
      ["EQ-Half"] = { canvas = { kind = "eq", bands = { { freq = 1 } }, half = true } },
      ["Plain"] = { controls = {} },
    }
    Mt.get = function(k) return lib[k] end
    Mt.default_variant = function(b) return b == "EQ-PB" and "EQ" or nil end
    Mt.variants = function(b) return b == "EQ-PB" and { "EQ" } or {} end
    Mt.canvas_todo = function(cv) return cv.half and { learned = 0 } or nil end
    local function r(b, k) local ok, v = CMP.ready_layout(b, k); return tostring(ok) .. (v and (":" .. v) or "") end
    check("compare: ready in another layout of its own", r("EQ-PB", "eq"), "true:EQ")
    check("compare: a compressor's roles", r("Comp X", "comp") .. " " .. r("Comp X", "eq"), "true false")
    check("compare: an EQ not learned isn't ready", r("EQ-Half", "eq"), "false")
    check("compare: no canvas, not ready; ReaComp is", r("Plain", "eq") .. " " .. r("ReaComp", "comp"), "false true")
    -- a plugin showing a layout without its canvas: the canvas is still found
    local Stt = require("TS_CV_State")
    local lk, god = Stt.layout_key, Mt.get_or_default
    Stt.layout_key = function(name) return name == "VST3: EQ-PB (IK)" and "EQ-PB" or "Plain" end
    Mt.get_or_default = function(k) return lib[k] or { controls = {} } end
    lib["EQ-PB"] = { controls = {} }
    local cv = CMP.canvas_of("tr", 1, "{g}", "VST3: EQ-PB (IK)")
    check("compare: its canvas, whichever layout it shows", cv and cv.kind, "eq")
    check("compare: none of that kind", tostring(CMP.canvas_of("tr", 1, "{g}", "VST3: EQ-PB (IK)", "comp")), "nil")
    Stt.layout_key, Mt.get_or_default = lk, god
    lib["EQ-PB"] = nil
    Mt.get, Mt.default_variant, Mt.variants, Mt.canvas_todo = g, dv, vs, todo
  end
  -- an EQ's curve matched by another built differently: A a bell at
  -- 200 Hz +4 dB and a high shelf at 8 kHz +3 dB; B two sweepable bells
  -- and a shelf with stepped frequencies (a console against a Pultec)
  do
    local MEt = require("TS_CV_MapEQ")
    local norm = {}
    local function fhz(n) return 20 * 1000 ^ n end
    local function gdb(n) return -15 + 30 * n end
    local SHELF = { 3000, 5000, 8000, 10000, 12000 }
    local function shelf_f(n) return SHELF[math.min(#SHELF, math.floor(n * #SHELF) + 1)] end
    reaper = setmetatable({
      TrackFX_GetParamNormalized = function(_, _, p) return norm[p] or 0.5 end,
      TrackFX_SetParamNormalized = function(_, _, p, v) norm[p] = v end,
      TrackFX_FormatParamValueNormalized = function(_, _, p, n)
        if p == 4 then return true, ("%d Hz"):format(shelf_f(n)) end
        return true, ("%.4f"):format(n)
      end,
      TrackFX_GetFXGUID = function() return "{eqb}" end,
      time_precise = os.clock,
    }, { __index = real })
    local read = MEt.read_band
    local bcv = { kind = "eq", bands = { { freq = 0, gain = 1 }, { freq = 2, gain = 3 }, { freq = 4, gain = 5 } } }
    MEt.read_band = function(_, _, b)
      if b.freq == 4 then return { type = "hs", f = shelf_f(norm[4] or 0.5), g = gdb(norm[5] or 0.5), q = 0.7071, on = true } end
      return { type = "bell", f = fhz(norm[b.freq] or 0.5), g = gdb(norm[b.gain] or 0.5), q = 1, on = true }
    end
    local target = {}
    for i, f in ipairs(CMP.GRID) do
      target[i] = MEt.band_db({ type = "bell", f = 200, g = 4, q = 1 }, f) + MEt.band_db({ type = "hs", f = 8000, g = 3, q = 0.7071 }, f)
    end
    norm = { [1] = 0.5, [3] = 0.5, [5] = 0.5 }      -- every gain at 0 dB
    local m = CMP.match_eq("tr", 1, bcv, target)
    check("compare: an EQ's curve matched, not band for band",
      m and (m.curve < 0.25 and m.from > 1.5 and m.set >= 3), true)
    check("compare: each part of the curve to the band that suits it",
      ("%.0f Hz %+.0f, shelf %s %+.0f, spare %+.0f"):format(fhz(norm[0]), gdb(norm[1]),
        (shelf_f(norm[4]) >= 8000) and "8k+" or "low", gdb(norm[5]), gdb(norm[3])),
      "201 Hz +4, shelf 8k+ +4, spare +0")
    MEt.read_band = read
    reaper = real
  end
  -- the bar, the panels' letters and blind boxes draw (a stand-in ImGui)
  do
    local proj = { ["compare:{T}"] = "c={C};a={A};b={B};s={S};gr=1" }
    local params = { [0] = 1, [1] = -1.4, [2] = 1, [3] = -14, [4] = -12.6, [5] = 1 }
    reaper = setmetatable({
      GetTrackGUID = function() return "{T}" end,
      -- (the record lives on the track; here, in the same slot the tests seed)
      GetSetMediaTrackInfo_String = function(_, k, v, set)
        local key = (k == "P_EXT:TS_CV_compare") and "compare:{T}" or k
        if set then proj[key] = v return true, v end
        return true, proj[key] or ""
      end,
      GetProjExtState = function(_, _, k) return 1, proj[k] or "" end,
      SetProjExtState = function(_, _, k, val) proj[k] = val end,
      time_precise = function() return 200 end,
      TrackFX_GetParam = function(_, _, p) return params[p] or 0 end,
      TrackFX_SetParam = function(_, _, p, val) params[p] = val end,
      GetPlayState = function() return 0 end,
      EnumInstalledFX = function() return false end,
    }, { __index = real })
    local Tt = require("TS_CV_FXTree")
    local saved = { Tt.collect, Tt.guid_at, Tt.gain_reduction, Tt.reports_gr, CMP.roles_of }
    Tt.collect = function()
      return { tree = { { guid = "{C}", addr = 10, path = { 2 }, kind = "container", children = {
        { guid = "{A}", addr = 11, path = { 2, 0 }, name = "VST3: Comp A (X)" },
        { guid = "{B}", addr = 12, path = { 2, 1 }, name = "VST3: Comp B (Y)" },
        { guid = "{S}", addr = 13, path = { 2, 2 }, name = "JS: TS_CV Compare" } } } } }
    end
    Tt.guid_at = function() return nil end
    Tt.gain_reduction = function(_, a) return a == 11 and 4.1 or 3.9 end
    Tt.reports_gr = function() return true end
    CMP.roles_of = function() return { kind = "comp", roles = { Threshold = 3, Makeup = 4 } } end
    local calls = {}
    local function rec(name) return function() calls[name] = (calls[name] or 0) + 1 end end
    local fake = setmetatable({
      GetWindowDrawList = function() return "dl" end,
      CalcTextSize = function(_, t) return #t * 7, 13 end,
      GetStyleVar = function() return 4, 3 end,
      GetFrameHeight = function() return 18 end,
      GetCursorScreenPos = function() return 0, 0 end,
      GetItemRectMax = function() return 300, 20 end,
      SmallButton = function() return false end,
      BeginPopup = function() return false end,
      IsItemHovered = function() return false end,
      IsItemClicked = function() return false end,
      InvisibleButton = function() return false end,
      BeginMenu = function() return false end,
      MenuItem = function() return false end,
    }, { __index = function(_, key)
      if key:find("Flags_") or key:find("^Col_") or key:find("StyleVar_") then return 1 end
      return rec(key)
    end })
    CMP.attach(fake)
    local ok, err = pcall(function()
      CMP.draw_bar("ctx", "tr", 0, 600, 0)
      CMP.draw_bar("ctx", "tr", 0, 180, 0)     -- (too narrow: short labels)
      CMP.menu_items("ctx", "tr", { guid = "{Z}", addr = 3, name = "VST3: Comp A (X)", path_t = { 3 } })
      local saved_roles = CMP.roles_of
      CMP.roles_of = function() return nil end
      local Brw = require("TS_CV_Browser")
      local saved_mi = Brw.menu_items
      Brw.menu_items = function(_, _, o) calls.plugin_list = o and o.pick and o.single and 1 or 0 end
      CMP.menu_items("ctx", "tr", { guid = "{Y}", addr = 3, name = "VST3: Plain (X)", path_t = { 3 } })
      Brw.menu_items = saved_mi
      CMP.roles_of = saved_roles
      CMP.overlay("ctx", "dl", "tr", { guid = "{A}" }, 0, 30, 280, 300)
      CMP.overlay("ctx", "dl", "tr", { guid = "{B}" }, 290, 30, 280, 300)
      proj["compare:{T}"] = "c={C};a={A};b={B};s={S};blind=1;order=BA"
      CMP.save("tr", CMP.decode(proj["compare:{T}"]))
      CMP.draw_bar("ctx", "tr", 0, 600, 0)
      return CMP.blind_panel("ctx", "tr", { guid = "{A}" }, 300)
    end)
    check("compare: bar, letters and blind boxes draw", tostring(ok) .. " " .. tostring(err), "true " .. CMP.BLIND_W)
    check("compare: no canvas, the whole plugin list to pick from", calls.plugin_list, 1)
    check("compare: the blind boxes' ear icon is in the library", require("TS_CV_ActionIcons").get("cv:ear") ~= nil, true)
    -- Copy and Match GR by kind: a compressor has both, an EQ Copy only,
    -- anything else neither
    do
      local saved_st = proj["compare:{T}"]
      proj["compare:{T}"] = "c={C};a={A};b={B};s={S};blind=0;order=AB"
      local function chips(kind)
        CMP.roles_of = function() return kind and { kind = kind, roles = { Threshold = 3 } } or nil end
        params.kind_probe = (params.kind_probe or 0) + 1
        local seen = {}
        local sb = fake.SmallButton
        rawset(fake, "SmallButton", function(_, label) seen[#seen + 1] = label:match("^[^#]*") return false end)
        local tp = reaper.time_precise
        reaper.time_precise = function() return 200 + params.kind_probe * 10 end   -- (past the kind cache)
        CMP.draw_bar("ctx", "tr", 0, 900, 0)
        reaper.time_precise = tp
        rawset(fake, "SmallButton", sb)
        local s2 = table.concat(seen, ",")
        return (s2:find("Match GR", 1, true) and "GR" or "-") .. " " .. (s2:find("Copy", 1, true) and "Copy" or "-")
      end
      check("compare: compressor bar", chips("comp"), "GR Copy")
      check("compare: limiter bar", chips("limit"), "GR Copy")
      check("compare: EQ bar", chips("eq"), "- Copy")
      check("compare: gate bar (by ear)", chips("gate"), "- -")
      check("compare: no canvas bar (by ear)", chips(nil), "- -")
      local both = CMP.roles_of
      CMP.roles_of = function(_, addr) return addr == 11 and { kind = "comp", roles = { Threshold = 3 } } or nil end
      params.kind_probe = params.kind_probe + 1
      local tp = reaper.time_precise
      reaper.time_precise = function() return 200 + params.kind_probe * 10 end
      check("compare: a compressor against one with no canvas is by ear", CMP.kind("tr"), nil)
      CMP.roles_of = function(_, addr) return { kind = addr == 11 and "comp" or "limit", roles = {} } end
      reaper.time_precise = function() return 300 + params.kind_probe * 10 end
      check("compare: a compressor against a limiter is by ear", CMP.kind("tr"), nil)
      reaper.time_precise = tp
      CMP.roles_of = both
      proj["compare:{T}"] = saved_st
      CMP.save("tr", CMP.decode(saved_st))
    end
    check("compare: heard is B", CMP.heard("tr"), "B")
    CMP.switch("tr")
    check("compare: switched to A", CMP.heard("tr") .. " " .. params[0], "A 0")
    check("compare: B's GR readings smoothed", CMP.tick("tr") ~= nil, true)
    Tt.collect, Tt.guid_at, Tt.gain_reduction, Tt.reports_gr, CMP.roles_of = table.unpack(saved)
    reaper = real
  end
end

-- ---------------------------------------------------------------------
-- the plugin list in a menu with its own search box (a compare's list):
-- typing searches there, Enter picks, and no "Search..." to open a dialog
-- ---------------------------------------------------------------------
do
  local real = reaper
  local fxl = { { "VST3: Bus Comp (Acme)", "Bus Comp.vst3" }, { "VST3: Gate One (Acme)", "Gate One.vst3" } }
  reaper = setmetatable({
    EnumInstalledFX = function(i) local e = fxl[i + 1]; if e then return true, e[1], e[2] end return false end,
  }, { __index = real })
  local saved_b = package.loaded["TS_CV_Browser"]
  package.loaded["TS_CV_Browser"] = nil
  local okb, Bf = pcall(require, "TS_CV_Browser")
  if not okb then
    check("browser: loads fresh", Bf, true)
  else
    local typed, enter, items_seen = "gate", false, {}
    local fake = setmetatable({
      IsWindowAppearing = function() return true end,
      InputTextWithHint = function(_, _, _, q) if q ~= typed then return true, typed end return false, q end,
      IsKeyPressed = function() return enter end,
      MenuItem = function(_, label) items_seen[#items_seen + 1] = label return false end,
      BeginMenu = function() return false end,
      BeginChild = function() return true end,
      Selectable = function() return false end,
      BeginPopupContextItem = function() return false end,
      IsItemHovered = function() return false end,
      CalcTextSize = function(_, t) return #t * 7, 13 end,
      GetTextLineHeightWithSpacing = function() return 17 end,
      GetWindowDrawList = function() return "dl" end,
      GetCursorScreenPos = function() return 0, 0 end,
      GetItemRectMin = function() return 0, 0 end,
      GetItemRectMax = function() return 10, 10 end,
      GetFontSize = function() return 13 end,
    }, { __index = function(_, k)
      if k:find("Flags_") or k:find("^Col_") or k:find("^Key_") or k:find("StyleVar_") then return 1 end
      return function() end
    end })
    Bf.attach(fake)
    local got
    local ok1, e1 = pcall(Bf.menu_items, "ctx", nil, { pick = function(e) got = e.ident end, single = true, search = true })
    check("browser: search box in the list draws", tostring(ok1) .. " " .. tostring(e1), "true false")
    enter = true
    local ok2, e2 = pcall(Bf.menu_items, "ctx", nil, { pick = function(e) got = e.ident end, single = true, search = true })
    check("browser: Enter picks the match", tostring(ok2) .. " " .. tostring(e2) .. " " .. tostring(got), "true true Gate One.vst3")
    typed, enter, items_seen = "", false, {}
    Bf.menu_items("ctx", nil, { pick = function() end, single = true, search = true })
    local has_search = false
    for _, l in ipairs(items_seen) do if l:find("^Search") then has_search = true end end
    check("browser: no Search... item with its own box", has_search, false)
    items_seen = {}
    Bf.menu_items("ctx", nil, { pick = function() end, single = true })
    has_search = false
    for _, l in ipairs(items_seen) do if l:find("^Search") then has_search = true end end
    check("browser: Search... item without one", has_search, true)
  end
  package.loaded["TS_CV_Browser"] = saved_b
  reaper = real
end

-- ---------------------------------------------------------------------
-- no module reads a global it never set (a local used above where it's
-- declared reads as one, and fails only when that line runs)
-- ---------------------------------------------------------------------
do
  local known = {}
  for w in ([[reaper require pairs ipairs type tostring tonumber math string table os io
    pcall xpcall select setmetatable getmetatable rawget rawset rawequal rawlen next error
    assert print debug package utf8 _G load loadfile dofile collectgarbage gfx coroutine]]):gmatch("%S+") do
    known[w] = true
  end
  local probe = io.popen("command -v luac5.4 2>/dev/null")
  local luac = probe and probe:read("l"); if probe then probe:close() end
  if luac and luac ~= "" then
    local bad = {}
    local ls = io.popen("ls *.lua 2>/dev/null")
    for f in ls:lines() do
      local h = io.popen(('luac5.4 -l -l -p "%s" 2>/dev/null'):format(f))
      for line in h:lines() do
        local g = line:match('GETTABUP.-_ENV "([%w_]+)"')
        if g and not known[g] then bad[#bad + 1] = f .. ":" .. g end
      end
      h:close()
    end
    ls:close()
    check("no module reads an unknown global", table.concat(bad, " "), "")
  end
end

print(fails == 0 and "\nALL PASS" or ("\n" .. fails .. " FAILURES"))
os.exit(fails == 0 and 0 or 1)
