-- @noindex
-- Not a package of its own: installed by TS_ChannelView.lua's @provides.
--[[
  TS_CV_VisualOptions.lua -- View > Options: one window for how
  ChannelView, the Rack, the TCP window and the web companion look.

  Each of the four has a tab and its own settings; the Rack, the TCP
  window and the web companion can Follow ChannelView instead (they do to
  start). A tab's settings:

    Colour         the panel colour (Pro), Hue, Tint, the accent (Pro)
    Controls       the default knob, button, dropdown and fader (Pro): what
                   a control with no style of its own draws as, live
    Panels         corner rounding, the power switch, auto-hiding the
                   header and foot (Pro)
    Track buttons  the track's colour on its name button (Pro); icons
    Text           the panels' text, their headers and the toolbars: a
                   font, size, bold, italic, underline each
    Sizes          control spacing
    Depth          3D effect, Lighting, Shadows (Pro)

  The TCP tab has the TCP window's own row settings too (background tint,
  folder indent, which track buttons show), kept in its ExtState section
  and never followed.

  Faders & strips -- the groups' fader looks, widths and backgrounds, and
  REAPER's own spacer size -- describe tracks, not a window, so they're
  shared by all four.

  Presets set every setting of a tab at once: four built in, and your
  own. Your own keep Faders & strips too, and put them back. Stored in
  ExtState section
  TS_ChannelView_Visual: "tab_<key>" each tab's settings, "follow_<key>",
  "presets" your own, "rev" bumped on every change so the other windows
  (separate scripts) pick it up.

  By time (Pro): a tab's presets changed at set times of day, each held
  from its time until the next. "bytime_<key>" on or off, "times_<key>"
  the list ("HH:MM=name" each), "time_at_<key>" the change last made
  (its day and time): a preset picked by hand stays until the next time,
  and only one window makes each change.

  Hue and Tint are also the TS_ tools' shared palette (TS_Palette):
  ChannelView's tab reads and writes them there.
--]]

local C  = require("TS_CV_Config")
local ED = require("TS_CV_Edition")
local U  = require("TS_CV_Util")

local VO = {}
local ImGui, W, ST, CP, TO
function VO.attach(imgui)
  ImGui = imgui
  W  = require("TS_CV_Widgets")
  ST = require("TS_CV_Style")
  CP = require("TS_CV_ColourPick")
  TO = require("TS_CV_TrackOps")
end

local SECT = "TS_ChannelView_Visual"
local PAL  = "TS_Palette"

VO.TABS = {
  { key = "cv",   label = "ChannelView" },
  { key = "rack", label = "Rack" },
  { key = "tcp",  label = "TCP window" },
  { key = "web",  label = "Web" },
}
-- after the looks: settings
VO.SETTINGS = {
  { key = "behaviour", label = "Behaviour" },
  { key = "rules",     label = "Track rules" },
}

-- name, default, kind, part of a preset (true: a tab's own; "g": the
-- shared Faders & strips settings, kept only in your own presets)
local FIELDS = {
  { "bg",         nil,      "col",  true },
  { "hue",        219,      "num",  true },
  { "tint",       1.0,      "num",  true },
  { "accent",     nil,      "col",  true },
  { "knob",       nil,      "str",  true },
  { "knob_cap",   nil,      "str",  true },
  { "knob_look",  nil,      "str",  true },
  { "knob_arc",   false,    "bool", true },
  { "button",     nil,      "str",  true },
  { "button_col", nil,      "str",  true },
  { "combo",      nil,      "str",  true },
  { "fader",      nil,      "str",  true },
  { "fader_cap",  nil,      "str",  true },
  { "corners",    3,        "num",  true },
  { "tcp_rr",     nil,      "num",  true },     -- the TCP's track panels: nil follows corners
  { "power",      "icon",   "str",  true },
  { "hide_head",  false,    "bool", true },
  { "hide_foot",  false,    "bool", true },
  { "mscale",     false,    "bool", true },     -- figures on the GR and In / Out meters
  { "trackcol",   "stripe", "str",  true },
  { "icons",      false,    "bool", true },
  { "cell_w",     C.CELL_W_DEFAULT, "num", true },
  { "ui",         100,      "num",  true },     -- the overall size, % (not the web page's)
  -- Text: t_ the panels' text, h_ their headers, b_ the toolbars; a font
  -- nil is ReaImGui's own (t_) or the text's (h_, b_)
  { "t_font",     nil,      "str",  true },
  { "t_size",     13,       "num",  true },
  { "t_b",        false,    "bool", true },
  { "t_i",        false,    "bool", true },
  { "t_u",        false,    "bool", true },
  { "h_font",     nil,      "str",  true },
  { "h_size",     13,       "num",  true },
  { "h_b",        false,    "bool", true },
  { "h_i",        false,    "bool", true },
  { "h_u",        false,    "bool", true },
  { "b_font",     nil,      "str",  true },
  { "b_size",     13,       "num",  true },
  { "b_b",        false,    "bool", true },
  { "b_i",        false,    "bool", true },
  { "b_u",        false,    "bool", true },
  { "d3",         true,     "bool", true },
  { "light",      100,      "num",  true },
  { "shadow",     100,      "num",  true },
  { "preset",     "Standard", "str", false },
  -- Faders & strips: the groups' fader looks, backgrounds and widths, the
  -- strip width, REAPER's spacer size, folder borders
  { "g_fd",       nil,      "str",  "g" },
  { "g_bt",       nil,      "str",  "g" },
  { "g_gw",       nil,      "str",  "g" },
  { "g_cw",       nil,      "num",  "g" },
  { "g_sp",       nil,      "num",  "g" },
  { "g_fb",       nil,      "num",  "g" },     -- folder borders' width, 0 off
}
local FIELD = {}
for _, f in ipairs(FIELDS) do FIELD[f[1]] = f end
-- whether a setting is kept in a preset (a tab's own)
function VO.field_in_preset(k) return FIELD[k] ~= nil and FIELD[k][4] == true end

VO.BUILTIN = {
  { name = "Standard", s = {} },
  { name = "Minimal dark", s = { accent = "#f5a524", knob = "minimal", button = "minimal",
      combo = "minimal", fader = "dot", power = "lamp", trackcol = "bar", d3 = false } },
  { name = "Minimal light", s = { bg = "#c4c4c4", accent = "#1a1a1a", knob = "minimal",
      button = "minimal", combo = "minimal", fader = "dot", power = "lamp", trackcol = "bar", d3 = false } },
  { name = "Studio", s = { accent = "#2f7de1", knob = "studio", button = "solid", combo = "minimal",
      corners = 9, trackcol = "filled" } },
}

-- ---------------------------------------------------------------------
-- storage
-- ---------------------------------------------------------------------
local function esc(v) return (tostring(v):gsub("[%%;=\n\t]", function(c) return ("%%%02x"):format(c:byte()) end)) end
local function unesc(v) return (v:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end)) end

local function encode(t)
  local out = {}
  for _, f in ipairs(FIELDS) do
    local v = t[f[1]]
    if v ~= nil then
      if f[3] == "bool" then v = v and "1" or "0" end
      out[#out + 1] = f[1] .. "=" .. esc(v)
    end
  end
  return table.concat(out, ";")
end

local function decode(str)
  local t = {}
  for k, v in (str or ""):gmatch("([%w_]+)=([^;]*)") do
    local f = FIELD[k]
    if f then
      v = unesc(v)
      if f[3] == "num" then t[k] = tonumber(v)
      elseif f[3] == "bool" then t[k] = (v == "1")
      else t[k] = (v ~= "") and v or nil end
    end
  end
  return t
end

local data, follow = {}, {}
local user = {}            -- your presets: { name, s }
local rev_seen = nil

local function get(k) local v = reaper.GetExtState(SECT, k); return v ~= "" and v or nil end
local function put(k, v) reaper.SetExtState(SECT, k, v, true) end
local function bump() put("rev", tostring(math.floor(reaper.time_precise() * 1000) % 1000000000)) end

-- By time's lists: tab -> { { m = minutes past midnight, name }, ... },
-- in time order
local times = {}

-- "7", "7:30", "0730", "19.30" as minutes past midnight; nil if not a time
function VO.parse_time(str)
  str = (str or ""):gsub("%s", "")
  local h, m = str:match("^(%d%d?)[:%.h]?(%d%d)$")
  if not h then h, m = str:match("^(%d%d?)$"), "0" end
  h, m = tonumber(h), tonumber(m)
  if not h or not m or h > 23 or m > 59 then return nil end
  return h * 60 + m
end
function VO.time_text(m) return ("%02d:%02d"):format(m // 60, m % 60) end

function VO.read_times(tab)
  local list = {}
  for _, line in ipairs(U.ext_split(get("times_" .. tab))) do
    local hm, name = line:match("^([%d:]+)=(.*)$")
    local m = VO.parse_time(hm)
    if m and name ~= "" then list[#list + 1] = { m = m, name = unesc(name) } end
  end
  table.sort(list, function(a, b) return a.m < b.m end)
  times[tab] = list
end

-- `keep`: the change already made stands (else the one due now is made
-- again, from the list as it now is)
local function write_times(tab, keep)
  local list = times[tab] or {}
  table.sort(list, function(a, b) return a.m < b.m end)
  local lines = {}
  for _, e in ipairs(list) do lines[#lines + 1] = VO.time_text(e.m) .. "=" .. esc(e.name) end
  put("times_" .. tab, U.ext_join(lines))
  if not keep then put("time_at_" .. tab, "") end
  bump()
  rev_seen = get("rev")
end

local function read_all()
  for _, t in ipairs(VO.TABS) do
    data[t.key] = decode(get("tab_" .. t.key))
    follow[t.key] = t.key ~= "cv" and get("follow_" .. t.key) ~= "0"
  end
  for _, t in ipairs(VO.TABS) do VO.read_times(t.key) end
  user = {}
  -- a name, then its settings ("-" for none), and so on (U.ext_split)
  local parts = U.ext_split(get("presets"))
  for i = 1, #parts - 1, 2 do
    user[#user + 1] = { name = parts[i], s = decode(parts[i + 1]) }
  end
  rev_seen = get("rev")
end

local function write_tab(tab)
  put("tab_" .. tab, encode(data[tab]))
  bump()
  rev_seen = get("rev")
end

local function write_user()
  local lines = {}
  for _, p in ipairs(user) do
    local s = encode(p.s)
    lines[#lines + 1] = p.name
    lines[#lines + 1] = (s ~= "") and s or "-"
  end
  put("presets", U.ext_join(lines))
  bump()
  rev_seen = get("rev")
end

-- The palette shared by the TS_ tools: hue and tint (ChannelView's tab).
local function pal_get()
  local h = reaper.GetExtState(PAL, "base_hue")
  local t = reaper.GetExtState(PAL, "tint")
  if h == "" then h = reaper.GetExtState(C.EXT_SECT, "base_hue") end
  if t == "" then t = reaper.GetExtState(C.EXT_SECT, "tint") end
  return tonumber(h), tonumber(t)
end
local function pal_set(h, t)
  reaper.SetExtState(PAL, "base_hue", tostring(math.floor(h)), true)
  reaper.SetExtState(PAL, "tint", ("%.3f"):format(t), true)
end

-- A field's value in a settings table, its default when unset.
local function val(s, k)
  local v = s[k]
  if v == nil then return FIELD[k][2] end
  return v
end
VO.val = val

-- The settings a tab draws with: ChannelView's when it follows them.
function VO.effective(tab)
  local s = (follow[tab] and data.cv) or data[tab] or {}
  if s == data.cv then
    local h, t = pal_get()
    if h then s.hue = h end
    if t then s.tint = t end
  end
  return s
end

function VO.follows(tab) return follow[tab] end

-- ---------------------------------------------------------------------
-- first run: ChannelView's older settings brought over
-- ---------------------------------------------------------------------
local function migrate()
  local s = {}
  local function ext(k) local v = reaper.GetExtState(C.EXT_SECT, k); return v ~= "" and v or nil end
  if ext("plate_texture") then s.d3 = ext("plate_texture") == "1" end
  if ext("light") then s.light = tonumber(ext("light")) end
  if ext("shadow") then s.shadow = tonumber(ext("shadow")) end
  if ext("track_icons") then s.icons = ext("track_icons") == "1" end
  if ext("cell_w") then s.cell_w = tonumber(ext("cell_w")) end
  -- the older Look setting: its preset, and its accent
  local look = ext("look")
  local from = { minimal = "Minimal dark", light = "Minimal light", studio = "Studio" }
  if look and from[look] then
    for _, p in ipairs(VO.BUILTIN) do
      if p.name == from[look] then
        for k, v in pairs(p.s) do s[k] = v end
        s.preset = p.name
      end
    end
    local akey = (look == "minimal") and "accent" or ("accent_" .. look)
    local a = reaper.GetExtState(PAL, akey)
    if a ~= "" then s.accent = "#" .. a:lower() end
  end
  -- the older look for new knobs and buttons: taken as the defaults, and
  -- cleared
  local ok, M = pcall(require, "TS_CV_Mappings")
  if ok and M.default_look then
    local k = M.default_look("knob")
    if k then
      s.knob, s.knob_cap = k.style, k.cap
      if k.look then
        local KP = require("TS_CV_KnobParts")
        s.knob_look = KP.encode(k.look)
      end
      M.set_default_look("knob", nil)
    end
    local b = M.default_look("toggle")
    if b then
      s.button, s.button_col = b.style, b.cap
      M.set_default_look("toggle", nil)
    end
  end
  data.cv = s
  write_tab("cv")
end

-- Read everything; `first` (ChannelView, once) brings older settings over.
function VO.load(first)
  read_all()
  if first and not get("tab_cv") then migrate() end
end

-- True when another window changed something since this one last looked (then
-- everything has been read again), or By time changed a preset.
function VO.poll()
  local r = get("rev")
  local changed = false
  if r ~= rev_seen then read_all(); changed = true end
  if VO.tick() then changed = true end
  return changed
end

-- ---------------------------------------------------------------------
-- applying a tab's settings
-- ---------------------------------------------------------------------
local function col_of(hex)
  local rgb = C.custom_rgb(hex)
  return rgb and ((rgb << 8) | 0xff) or nil
end

function VO.apply(tab)
  local s = VO.effective(tab)
  local pro = ED.PRO
  C.BASE_HUE = val(s, "hue")
  C.TINT     = val(s, "tint")
  C.BG       = pro and col_of(s.bg) or nil
  C.ACCENT   = pro and col_of(s.accent) or nil
  local KP = require("TS_CV_KnobParts")
  C.DEF = pro and {
    knob = s.knob, knob_cap = s.knob_cap, knob_look = s.knob_look and KP.decode(s.knob_look) or nil,
    knob_arc = val(s, "knob_arc") or nil,
    button = s.button, button_col = s.button_col, combo = s.combo,
    fader = s.fader, fader_cap = s.fader_cap,
  } or {}
  C.PANEL_RR  = pro and val(s, "corners") or 3.0
  C.STRIP_ROUND = C.PANEL_RR          -- the mixer's strips and name buttons too
  C.TCP_RR = pro and (s.tcp_rr or C.PANEL_RR) or 0   -- the TCP window's track panels
  C.POWER     = pro and val(s, "power") or "icon"
  C.TRACK_COL = pro and val(s, "trackcol") or "stripe"
  C.HIDE_HEAD = pro and val(s, "hide_head") or false
  C.HIDE_FOOT = pro and val(s, "hide_foot") or false
  C.METER_SCALES = pro and val(s, "mscale") or false
  C.TRACK_ICONS = val(s, "icons")
  C.TCP_ICONS   = C.TRACK_ICONS
  -- the overall size first: the cell width and the type follow it
  C.set_ui(((tab == "web") and 100 or val(s, "ui")) / 100)
  local okW, Wd = pcall(require, "TS_CV_Widgets")
  if okW and Wd then Wd.LABEL_H = math.floor(11 * C.UI + 0.5) end
  C.set_cell_w(val(s, "cell_w"))
  VO.apply_fonts(s)
  C.EFFECT_3D = pro and val(s, "d3") or false
  C.LIGHT  = math.max(0, math.min(C.LIGHT_MAX, val(s, "light")))
  C.SHADOW = math.max(0, math.min(C.SHADOW_MAX, val(s, "shadow")))
  KP.LIGHT = C.LIGHT / 100
  ED.light().STRENGTH = C.SHADOW / 100
  C.build_palette()
end

-- Options > Text into C.FONTS (TS_CV_Widgets W.push_font): each
-- of text, head and bar { name, size, b, i, u, key }. Always a size, the
-- default 13 too: left to ReaImGui's own default it needn't scale with
-- Windows' display scaling as the others do (at 175 % it came out the
-- same as 12). A taller header font makes the header taller.
VO.SIZE_DEFAULT = 13
VO.SIZES = { t = { 11, 14 }, h = { 11, 18 }, b = { 11, 15 } }
function VO.apply_fonts(s)
  local function one(p, name)
    local lim = VO.SIZES[p]
    local size = math.max(lim[1], math.min(lim[2], math.floor(val(s, p .. "_size") + 0.5)))
    size = math.max(7, math.floor(size * (C.UI or 1) + 0.5))         -- the overall size
    local f = { name = name, size = size, b = val(s, p .. "_b"), i = val(s, p .. "_i"), u = val(s, p .. "_u") }
    f.key = ("%s|%d|%s%s"):format(f.name or "", size, f.b and "b" or "", f.i and "i" or "")
    return f
  end
  C.FONTS = {
    text = one("t", s.t_font),
    head = one("h", s.h_font or s.t_font),
    bar  = one("b", s.b_font or s.t_font),
  }
  C.HEADER_H = math.floor(math.max(C.S(20), (C.FONTS.head and C.FONTS.head.size or VO.SIZE_DEFAULT) + C.S(7)) + 0.5)
end

-- ---------------------------------------------------------------------
-- changing them
-- ---------------------------------------------------------------------
local own_tab = "cv"           -- the window's own: changes show live
local function own_changed(tab)
  if tab == own_tab or (follow[own_tab] and tab == "cv") then VO.apply(own_tab) end
end

local function set(tab, k, v)
  local s = data[tab]
  s[k] = v
  if tab == "cv" and (k == "hue" or k == "tint") then pal_set(val(s, "hue"), val(s, "tint")) end
  write_tab(tab)
  own_changed(tab)
end
VO.set = set

-- A preset by name: built in first, then yours.
local function preset_of(name)
  for _, p in ipairs(VO.BUILTIN) do if p.name == name then return p, true end end
  for _, p in ipairs(user) do if p.name == name then return p, false end end
end

-- the Faders & strips settings now, as a preset keeps them (VO.groups_now,
-- VO.set_groups: further down, with the spacer)
local function apply_preset(tab, name)
  local p = preset_of(name)
  if not p then return end
  local s = data[tab]
  for _, f in ipairs(FIELDS) do if f[4] == true then s[f[1]] = p.s[f[1]] end end
  s.preset = name
  if tab == "cv" then pal_set(val(s, "hue"), val(s, "tint")) end
  if p.s.g_fd ~= nil or p.s.g_cw ~= nil then VO.set_groups(p.s) end
  write_tab(tab)
  own_changed(tab)
end

-- Whether a tab's settings differ from its preset's.
local function modified(tab)
  local s = VO.effective(tab)
  local p = preset_of(val(data[tab], "preset"))
  if not p then return true end
  for _, f in ipairs(FIELDS) do
    if f[4] == true and val(s, f[1]) ~= val(p.s, f[1]) then return true end
  end
  if p.s.g_fd ~= nil or p.s.g_cw ~= nil then
    local g = VO.groups_now()
    for k, v in pairs(g) do if p.s[k] ~= nil and p.s[k] ~= v then return true end end
  end
  return false
end

local function all_presets()
  local out = {}
  for _, p in ipairs(VO.BUILTIN) do out[#out + 1] = p.name end
  for _, p in ipairs(user) do out[#out + 1] = p.name end
  return out
end

local function save_preset(tab, name)
  local s = {}
  local now = VO.effective(tab)
  for _, f in ipairs(FIELDS) do if f[4] == true then s[f[1]] = now[f[1]] end end
  for k, v in pairs(VO.groups_now()) do s[k] = v end
  local _, built = preset_of(name)
  if built then return false end
  local found
  for _, p in ipairs(user) do if p.name == name then p.s = s; found = true end end
  if not found then user[#user + 1] = { name = name, s = s } end
  write_user()
  data[tab].preset = name
  write_tab(tab)
  return true
end

-- ---------------------------------------------------------------------
-- By time
-- ---------------------------------------------------------------------
VO.TIMES_DEFAULT = { { m = 7 * 60, name = "Minimal light" }, { m = 19 * 60, name = "Minimal dark" } }
VO.clock = function() return os.time() end          -- (the tests set it)

function VO.by_time(tab) return get("bytime_" .. tab) == "1" end
function VO.times(tab) return times[tab] or {} end

-- The entry that holds now: its index, and the change's key (the day it
-- began, and its time).
local function slot_now(list)
  if #list == 0 then return nil end
  local now = VO.clock()
  local d = os.date("*t", now)
  local mins = d.hour * 60 + d.min
  local idx, day = nil, now
  for i, e in ipairs(list) do if e.m <= mins then idx = i end end
  if not idx then idx, day = #list, now - 86400 end
  return idx, os.date("%Y-%m-%d", day) .. " " .. VO.time_text(list[idx].m)
end

-- The next time on a tab's list, or nil (one entry or none).
function VO.next_time(tab)
  local list = times[tab] or {}
  if #list < 2 then return nil end
  local idx = slot_now(list)
  return VO.time_text(list[idx % #list + 1].m)
end

-- Make any change that's due (Pro). A tab that follows ChannelView has
-- none of its own. True when one was made.
function VO.tick()
  if not ED.PRO then return false end
  local made = false
  for _, t in ipairs(VO.TABS) do
    local k = t.key
    if not follow[k] and get("bytime_" .. k) == "1" then
      local list = times[k] or {}
      local idx, key = slot_now(list)
      if idx and get("time_at_" .. k) ~= key then
        put("time_at_" .. k, key)
        if preset_of(list[idx].name) then apply_preset(k, list[idx].name) end
        made = true
      end
    end
  end
  return made
end

-- By time on or off. On, with no list yet, it starts from the default
-- one; the preset due now is put on at once. Off keeps the preset on.
function VO.set_by_time(tab, on)
  put("bytime_" .. tab, on and "1" or "0")
  if on then
    if #(times[tab] or {}) == 0 then
      times[tab] = {}
      for _, e in ipairs(VO.TIMES_DEFAULT) do times[tab][#times[tab] + 1] = { m = e.m, name = e.name } end
    end
    write_times(tab)
    VO.tick()
  else
    bump()
    rev_seen = get("rev")
  end
end

-- (for the tests)
VO.write_times_for_test = function(...) return write_times(...) end
VO.save_preset_for_test = function(...) return save_preset(...) end
VO.apply_preset_for_test = function(...) return apply_preset(...) end
VO.modified_for_test = function(...) return modified(...) end

-- ---------------------------------------------------------------------
-- REAPER's spacer size (Preferences > Appearance: the visual spacer).
-- Writing it needs SWS; REAPER has no call of its own for a preference.
-- ---------------------------------------------------------------------
local function spacer_get()
  if not reaper.get_config_var_string then return 16 end
  local ok, sv = reaper.get_config_var_string("trackgapmax")
  return ok and tonumber(sv) or 16
end
local function spacer_set(v)
  if not reaper.SNM_SetIntConfigVar then return false end
  reaper.SNM_SetIntConfigVar("trackgapmax", math.floor(v + 0.5))
  reaper.TrackList_AdjustWindows(false)
  reaper.UpdateArrange()
  if C.spacer_refresh then C.spacer_refresh() end
  return true
end

-- Faders & strips as your presets keep them: the raw settings (TS_CV_
-- TrackOps' ExtState lines), the strip width and the spacer size.
local GROUP_KEYS = { g_fd = "fader_defaults", g_bt = "bg_tints", g_gw = "group_w" }
function VO.groups_now()
  local g = {}
  for k, ext in pairs(GROUP_KEYS) do g[k] = reaper.GetExtState(C.EXT_SECT, ext) end
  g.g_cw = C.CHANNEL_W
  g.g_sp = spacer_get()
  g.g_fb = C.fold_bw()
  return g
end
function VO.set_groups(p)
  for k, ext in pairs(GROUP_KEYS) do
    if p[k] ~= nil then reaper.SetExtState(C.EXT_SECT, ext, p[k], true) end
  end
  if TO then TO.reload_fader_defaults() end
  if p.g_cw then
    C.set_channel_w(p.g_cw)
    reaper.SetExtState(C.EXT_SECT, "channel_w", tostring(C.CHANNEL_W), true)
  end
  if p.g_sp and p.g_sp ~= spacer_get() then spacer_set(p.g_sp) end
  if p.g_fb then
    reaper.SetExtState(C.EXT_SECT, "fold_borders", p.g_fb > 0 and "1" or "0", true)
    if p.g_fb > 0 then reaper.SetExtState(C.EXT_SECT, "fold_bw", tostring(math.floor(p.g_fb)), true) end
    C.fold_refresh()
  end
end

-- ---------------------------------------------------------------------
-- the window
-- ---------------------------------------------------------------------
local win = { open = false, tab = "cv", page = "colour", select = nil }

VO.PAGES = {
  { key = "colour",   label = "Colour" },
  { key = "controls", label = "Controls" },
  { key = "panels",   label = "Panels" },
  { key = "tracks",   label = "Track buttons" },
  { key = "faders",   label = "Faders & strips" },
  { key = "text",     label = "Text" },
  { key = "sizes",    label = "Sizes" },
  { key = "depth",    label = "Depth" },
}

-- Opens the window on a tab (the caller's own by default) and a page.
function VO.show(tab, page)
  win.open = true
  win.tab = tab or own_tab
  win.select = win.tab
  if page then win.page = page end
end
function VO.is_open() return win.open end

-- Knob customising lives in ChannelView (TS_CV_KnobEditor): it hands
-- this its opener, `customise(start_look, apply(look))`.
VO.customise = nil

local KEEP = 0

local function pro_note(ctx)
  if ED.PRO then return end
  ImGui.SameLine(ctx)
  ImGui.TextDisabled(ctx, "(Pro)")
end

local function row(ctx, label)
  ImGui.AlignTextToFramePadding(ctx)
  ImGui.Text(ctx, label)
  ImGui.SameLine(ctx, 130)
end

local function section(ctx, title, pro)
  ImGui.Spacing(ctx)
  ImGui.SeparatorText(ctx, title .. ((pro and not ED.PRO) and "  (Pro)" or ""))
end

-- A colour swatch that opens the colour picker. `hex` "#rrggbb" or nil.
local function colour_button(ctx, id, hex, fallback, title, on_pick)
  local rgb = C.custom_rgb(hex) or fallback
  if ImGui.ColorButton(ctx, "##" .. id, (rgb << 8) | 0xff, ImGui.ColorEditFlags_NoTooltip, 34, 20) then
    local before = hex
    CP.open({ title = title, rgb = rgb, window = true,
      preview = function(v) on_pick(("#%06x"):format(v)) end,
      apply   = function(v) on_pick(("#%06x"):format(v)) end,
      cancel  = function() on_pick(before) end })
  end
end

-- the knob styles as a grid of thumbnails, your recipes after them
local function knob_grid(ctx, s, tab)
  local dl = ImGui.GetWindowDrawList(ctx)
  local cap = W.cap_col(s.knob_cap)
  local COLS, CS = 7, 46
  local hov
  local KP = require("TS_CV_KnobParts")
  -- `id` unique across both grids ("s3", "r1"): a style and a recipe in
  -- the same place must not share one
  local function cell(i, id, key, label, look, pick)
    if (i - 1) % COLS ~= 0 then ImGui.SameLine(ctx, 0, 2) end
    local x, y = ImGui.GetCursorScreenPos(ctx)
    local on
    if look then on = s.knob_look ~= nil and s.knob_look == KP.encode(look)
    else on = not s.knob_look and (key == (s.knob or "arc")) end
    if ImGui.Selectable(ctx, "##vok_" .. id, on, KEEP, CS, CS) then pick() end
    if ImGui.IsItemHovered(ctx) then hov = label end
    W.knob_face(dl, x + CS * 0.5, y + CS * 0.5 - 2, CS * 0.5 - 8, 0.62,
      { style = key or "arc", cap = cap, look = look, ctx = ctx })
  end
  local i = 0
  for _, st in ipairs(C.KNOB_STYLES) do
    i = i + 1
    cell(i, "s" .. i, st.key, st.label, nil, function()
      set(tab, "knob_look", nil); set(tab, "knob", (st.key ~= "arc") and st.key or nil)
    end)
  end
  local ok, RCP = pcall(require, "TS_CV_Recipes")
  local mine = (ok and ED.PRO and RCP.list) and RCP.list() or {}
  if #mine > 0 then
    ImGui.TextDisabled(ctx, "Your recipes")
    for j, r in ipairs(mine) do
      cell(j, "r" .. j, nil, r.name, r.look, function()
        set(tab, "knob", nil); set(tab, "knob_look", KP.encode(r.look))
      end)
    end
  end
  ImGui.TextDisabled(ctx, hov or " ")
end

local function style_label(list, key, plain)
  for _, st in ipairs(list) do if st.key == key then return st.label end end
  return plain
end

local function page_colour(ctx, tab, s, dis)
  section(ctx, "Colour")
  row(ctx, "Background")
  if not ED.PRO then ImGui.BeginDisabled(ctx, true) end
  colour_button(ctx, "vo_bg", s.bg, C.COL.panel_bg >> 8, "Background", function(h) set(tab, "bg", h) end)
  ImGui.SameLine(ctx)
  if ImGui.Button(ctx, "Theme##vo_bgr") then set(tab, "bg", nil) end
  if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "The theme's greys.") end
  if not ED.PRO then ImGui.EndDisabled(ctx) end
  pro_note(ctx)

  row(ctx, "Hue")
  ImGui.SetNextItemWidth(ctx, 240)
  local hch, hv = ST.slider_int(ctx, "##vo_hue", math.floor(val(s, "hue")), 0, 359)
  if hch then set(tab, "hue", hv) end
  row(ctx, "Tint")
  ImGui.SetNextItemWidth(ctx, 240)
  local tch, tv = ST.slider_double(ctx, "##vo_tint", val(s, "tint"), 0.0, 2.0, "%.2f")
  if tch then set(tab, "tint", tv) end
  if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "How coloured the greys are.") end

  row(ctx, "Accent")
  if not ED.PRO then ImGui.BeginDisabled(ctx, true) end
  local pick = ST.seg(ctx, "##vo_accm", { { "From hue", false }, { "Picked", true } }, s.accent ~= nil)
  if pick == false then set(tab, "accent", nil)
  elseif pick == true and not s.accent then set(tab, "accent", ("#%06x"):format(C.COL.accent >> 8)) end
  if s.accent then
    ImGui.SameLine(ctx)
    colour_button(ctx, "vo_acc", s.accent, C.COL.accent >> 8, "Accent", function(h) set(tab, "accent", h) end)
  end
  if not ED.PRO then ImGui.EndDisabled(ctx) end
  pro_note(ctx)

  -- a strip of the palette, so the sliders aren't guesswork
  ImGui.Spacing(ctx)
  ImGui.SetCursorPosX(ctx, 130)
  local dl = ImGui.GetWindowDrawList(ctx)
  local cx, cy = ImGui.GetCursorScreenPos(ctx)
  local keys = { "win_bg", "panel_bg", "header_bg", "knob_body", "knob_ring", "label",
                 "accent", "knob_fill_bi", "warn" }
  local sw = 240 / #keys
  for i, k in ipairs(keys) do
    ImGui.DrawList_AddRectFilled(dl, cx + (i - 1) * sw, cy, cx + i * sw, cy + 14, C.COL[k] or 0)
  end
  ImGui.Dummy(ctx, 240, 16)
end

local function page_controls(ctx, tab, s)
  section(ctx, "Controls", true)
  ImGui.TextDisabled(ctx, "For controls without a style of their own.")
  if not ED.PRO then ImGui.BeginDisabled(ctx, true) end
  local dl = ImGui.GetWindowDrawList(ctx)

  -- knob
  row(ctx, "Knob")
  local label = s.knob_look and "Your own" or style_label(C.KNOB_STYLES, s.knob, "Arc")
  if ImGui.Button(ctx, label .. "  \u{25BE}##vo_knob", 160, 0) then ImGui.OpenPopup(ctx, "vo_knobs") end
  if ImGui.BeginPopup(ctx, "vo_knobs") then
    knob_grid(ctx, s, tab)
    if VO.customise then
      ImGui.Separator(ctx)
      if ImGui.Selectable(ctx, "Customise\u{2026}##vo_kcust") then
        local KP = require("TS_CV_KnobParts")
        local start = s.knob_look and KP.decode(s.knob_look) or {}
        VO.customise(start, function(look)
          set(tab, "knob", nil); set(tab, "knob_look", KP.encode(look))
        end)
      end
    end
    ImGui.EndPopup(ctx)
  end
  ImGui.SameLine(ctx)
  ImGui.Text(ctx, "Colour")
  ImGui.SameLine(ctx)
  ImGui.BeginGroup(ctx)
  local kbefore = s.knob_cap
  CP.cap_swatches_win(ctx, "vo_kcap", s.knob_cap, 0x808080, "Knob colour",
    function(k, save) set(tab, "knob_cap", k) end, function() set(tab, "knob_cap", kbefore) end)
  ImGui.EndGroup(ctx)
  if s.knob_cap and ImGui.SmallButton(ctx, "Style's own colour##vo_kcr") then set(tab, "knob_cap", nil) end
  ImGui.SetCursorPosX(ctx, 130)
  local ach, av = ST.checkbox(ctx, "Value arc##vo_karc", val(s, "knob_arc"))
  if ach then set(tab, "knob_arc", av) end
  if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "Round knobs that have no arc of their own.") end

  -- button
  ImGui.Spacing(ctx)
  row(ctx, "Button")
  local blabel = style_label(C.BUTTON_STYLES, s.button, nil) or style_label(C.SWITCH_STYLES, s.button, "Flat")
  if ImGui.Button(ctx, blabel .. "  \u{25BE}##vo_btn", 160, 0) then ImGui.OpenPopup(ctx, "vo_btns") end
  if ImGui.BeginPopup(ctx, "vo_btns") then
    local lit = W.lit_col(s.button_col) or C.COL.toggle_on
    for _, bs in ipairs(C.BUTTON_STYLES) do
      local x, y = ImGui.GetCursorScreenPos(ctx)
      if ImGui.Selectable(ctx, "          " .. bs.label .. "##vob_" .. bs.key,
          (s.button or "flat") == bs.key, 0, 170, 20) then
        set(tab, "button", (bs.key ~= "flat") and bs.key or nil)
      end
      if not W.button_face(dl, x + 3, y + 3, x + 33, y + 17, 2.5, true, lit, bs.key, false) then
        ImGui.DrawList_AddRectFilled(dl, x + 3, y + 3, x + 33, y + 17, lit, 2.5)
      end
    end
    ImGui.SeparatorText(ctx, "Switches")
    for _, sw in ipairs(C.SWITCH_STYLES or {}) do
      if ImGui.Selectable(ctx, sw.label .. "##vob_" .. sw.key, s.button == sw.key, 0, 170, 0) then
        set(tab, "button", sw.key)
      end
    end
    ImGui.EndPopup(ctx)
  end
  ImGui.SameLine(ctx)
  ImGui.Text(ctx, "Lit")
  for i, cp in ipairs(C.TOGGLE_COLS) do
    ImGui.SameLine(ctx, 0, 4)
    if ImGui.ColorButton(ctx, cp.label .. "##vo_bl" .. i, cp.col or C.COL.toggle_on,
        ImGui.ColorEditFlags_NoTooltip, 18, 18) then
      set(tab, "button_col", (cp.key ~= "theme") and cp.key or nil)
    end
    if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, cp.label) end
    if (s.button_col or "theme") == cp.key then
      local x0, y0 = ImGui.GetItemRectMin(ctx)
      local x1, y1 = ImGui.GetItemRectMax(ctx)
      ImGui.DrawList_AddRect(dl, x0 - 2, y0 - 2, x1 + 2, y1 + 2, C.COL.header_text, 3.0, 0, 1.5)
    end
  end

  -- dropdown
  ImGui.Spacing(ctx)
  row(ctx, "Dropdown")
  local c = ST.seg(ctx, "##vo_combo", { { "Flat", "flat" }, { "Raised", "raised" }, { "Minimal", "minimal" } },
    s.combo or "flat")
  if c then set(tab, "combo", (c ~= "flat") and c or nil) end

  -- fader
  ImGui.Spacing(ctx)
  row(ctx, "Fader")
  local f = {}
  for _, fs in ipairs(C.FADER_STYLES) do f[#f + 1] = { fs.label, fs.key } end
  local fc = ST.seg(ctx, "##vo_fader", f, s.fader or "flat")
  if fc then set(tab, "fader", (fc ~= "flat") and fc or nil) end
  ImGui.SetCursorPosX(ctx, 130)
  ImGui.BeginGroup(ctx)
  local fbefore = s.fader_cap
  CP.cap_swatches_win(ctx, "vo_fcap", s.fader_cap, 0x808080, "Fader colour",
    function(k) set(tab, "fader_cap", k) end, function() set(tab, "fader_cap", fbefore) end)
  ImGui.EndGroup(ctx)
  ImGui.TextDisabled(ctx, "Plugin faders. Track faders: Faders & strips.")
  if not ED.PRO then ImGui.EndDisabled(ctx) end
end

local function page_panels(ctx, tab, s)
  section(ctx, "Panels", true)
  if not ED.PRO then ImGui.BeginDisabled(ctx, true) end
  row(ctx, "Corner rounding")
  ImGui.SetNextItemWidth(ctx, 200)
  local ch, v = ST.slider_int(ctx, "##vo_rr", math.floor(val(s, "corners")), 0, 12, "%d px")
  if ch then set(tab, "corners", v) end
  -- the TCP window's track panels: as the panels, or their own
  if tab == "tcp" then
    row(ctx, "Track panels")
    local fch2, fv2 = ST.checkbox(ctx, "Follow corner rounding##vo_trr", s.tcp_rr == nil)
    if fch2 then set(tab, "tcp_rr", (not fv2) and math.floor(val(s, "corners")) or nil) end
    if s.tcp_rr ~= nil then
      ImGui.SameLine(ctx)
      ImGui.SetNextItemWidth(ctx, 140)
      local tch, tv = ST.slider_int(ctx, "##vo_trrv", math.floor(s.tcp_rr), 0, 12, "%d px")
      if tch then set(tab, "tcp_rr", tv) end
    end
  end
  -- (the TCP window's track panels have neither a power switch nor a
  -- header and foot)
  if tab == "tcp" then
    if not ED.PRO then ImGui.EndDisabled(ctx) end
    return
  end
  row(ctx, "Power switch")
  local pw = ST.seg(ctx, "##vo_pw", { { "Icon", "icon" }, { "Lamp", "lamp" } }, val(s, "power"))
  if pw then set(tab, "power", pw) end
  row(ctx, "Auto-hide")
  local hch, hv = ST.checkbox(ctx, "Header##vo_hh", val(s, "hide_head"))
  if hch then set(tab, "hide_head", hv) end
  ImGui.SameLine(ctx)
  local fch, fv = ST.checkbox(ctx, "Foot##vo_hf", val(s, "hide_foot"))
  if fch then set(tab, "hide_foot", fv) end
  if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "Shown while the pointer is over the panel.") end
  row(ctx, "Meter scales")
  local mch, mv = ST.checkbox(ctx, "On the GR and In / Out meters##vo_ms", val(s, "mscale"))
  if mch then set(tab, "mscale", mv) end
  if not ED.PRO then ImGui.EndDisabled(ctx) end
end

local function page_tracks(ctx, tab, s)
  section(ctx, "Track buttons")
  -- (the TCP window has no name buttons: its tracks' icons only)
  if tab == "tcp" then
    row(ctx, "Track icons")
    local ich, iv = ST.checkbox(ctx, "Show##vo_ic", val(s, "icons"))
    if ich then set(tab, "icons", iv) end
    return
  end
  row(ctx, "Track colour")
  if not ED.PRO then ImGui.BeginDisabled(ctx, true) end
  local tc = ST.seg(ctx, "##vo_tc", { { "Bar below", "stripe" }, { "Bar above", "bar" }, { "Filled", "filled" } },
    val(s, "trackcol"))
  if tc then set(tab, "trackcol", tc) end
  if not ED.PRO then ImGui.EndDisabled(ctx) end
  pro_note(ctx)
  row(ctx, "Track icons")
  local ich, iv = ST.checkbox(ctx, "Above the name##vo_ic", val(s, "icons"))
  if ich then set(tab, "icons", iv) end
end

-- The TCP window's own row settings (its ExtState section, read by the
-- window twice a second): not looks ChannelView has, so never followed.
local function tcp_get(k, default)
  local v = reaper.GetExtState(C.TCP_EXT_SECT, k)
  return v ~= "" and v or default
end
local function tcp_put(k, v) reaper.SetExtState(C.TCP_EXT_SECT, k, v, true) end
local function tcp_check(ctx, label, k, default)
  local on = tcp_get(k, default and "1" or "0") == "1"
  local ch, v = ST.checkbox(ctx, label, on)
  if ch then tcp_put(k, v and "1" or "0") end
end

local function tcp_rows(ctx, page)
  if page == "panels" then
    row(ctx, "Rows")
    tcp_check(ctx, "Background tint##vo_ttint", "tint", true)
    if ImGui.IsItemHovered(ctx) then
      ImGui.SetTooltip(ctx, "In the track's colour.\nStrength: Faders & strips.")
    end
    row(ctx, "Folder indent")
    local px = (tcp_get("indent", C.TCP_INDENT_FOLDERS and "1" or "0") == "1")
      and (tonumber(tcp_get("indent_px", "")) or C.TCP_INDENT) or 0
    ImGui.SetNextItemWidth(ctx, 200)
    local ich, iv = ST.slider_int(ctx, "##vo_tind", math.floor(px), 0, 32, "%d px")
    if ich then
      tcp_put("indent", iv > 0 and "1" or "0")
      if iv > 0 then tcp_put("indent_px", tostring(iv)) end
    end
    if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "Per folder level.") end
  elseif page == "tracks" then
    row(ctx, "Always show")
    local always = tcp_get("always", C.TCP_ALWAYS)
    for i, b in ipairs({ { "I", "Monitoring" }, { "R", "Record arm" }, { "M", "Mute" }, { "S", "Solo" } }) do
      if i > 1 then ImGui.SameLine(ctx) end
      local ch = ST.checkbox(ctx, b[2] .. "##vo_ta" .. b[1], always:find(b[1], 1, true) ~= nil)
      if ch then
        local t = {}
        for _, k in ipairs({ "I", "R", "M", "S" }) do
          if (k == b[1]) ~= (always:find(k, 1, true) ~= nil) then t[#t + 1] = k end
        end
        tcp_put("always", #t > 0 and table.concat(t) or "-")   -- "-": none
      end
    end
    row(ctx, "The others")
    tcp_check(ctx, "Show while on##vo_tch", "chips", C.TCP_STATE_CHIPS)
    if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "Buttons keep their place on every row.") end
  end
end

-- A swatch for a Track rules colour (0xRRGGBB, or nil: an outline)
-- that opens the colour picker; `on_pick(rgb)` as it changes.
local function rules_colour_button(ctx, id, rgb, title, on_pick)
  local face = rgb and ((rgb << 8) | 0xff) or 0x00000000
  if ImGui.ColorButton(ctx, "##" .. id, face, ImGui.ColorEditFlags_NoTooltip, 34, 20) then
    local before = rgb
    CP.open({ title = title, rgb = rgb or 0x808080, window = true,
      preview = function(v) on_pick(v) end,
      apply   = function(v) on_pick(v) end,
      cancel  = function() on_pick(before) end })
  end
  if not rgb then
    local x1, y1 = ImGui.GetItemRectMin(ctx)
    local x2, y2 = ImGui.GetItemRectMax(ctx)
    ImGui.DrawList_AddRect(ImGui.GetWindowDrawList(ctx), x1, y1, x2, y2, C.COL.ui_edge or 0x808080ff, 2)
  end
end

local function page_faders(ctx)
  section(ctx, "Strips")
  row(ctx, "Spacer size")
  ImGui.SetNextItemWidth(ctx, 200)
  local can = reaper.SNM_SetIntConfigVar ~= nil
  if not can then ImGui.BeginDisabled(ctx, true) end
  local ch, v = ST.slider_int(ctx, "##vo_sp", spacer_get(), 1, 64, "%d px")
  if ch then spacer_set(v) end
  if not can then
    ImGui.EndDisabled(ctx)
    ImGui.SameLine(ctx)
    ImGui.TextDisabled(ctx, "Needs SWS")
  end
  row(ctx, "Folder borders")
  local fon = C.fold_bw() > 0
  local fch, fv = ST.checkbox(ctx, "##vo_fb", fon)
  if fch then reaper.SetExtState(C.EXT_SECT, "fold_borders", fv and "1" or "0", true); C.fold_refresh() end
  if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "A bar in the folder's colour at each side of its tracks.") end
  if fon then
    ImGui.SameLine(ctx)
    ImGui.SetNextItemWidth(ctx, 140)
    local wch, wv = ST.slider_int(ctx, "##vo_fbw", C.fold_bw(), 1, C.FOLD_BW_MAX, "%d px")
    if wch then reaper.SetExtState(C.EXT_SECT, "fold_bw", tostring(wv), true); C.fold_refresh() end
  end

  section(ctx, "Track faders, widths and backgrounds, by group")
  local now = reaper.time_precise()
  local TR = require("TS_CV_TrackRules")
  local rules = TR.get()
  if ImGui.BeginTable(ctx, "##vo_groups", 6, ImGui.TableFlags_SizingFixedFit) then
    ImGui.TableSetupColumn(ctx, "")
    ImGui.TableSetupColumn(ctx, "Fader style")
    ImGui.TableSetupColumn(ctx, "Colour")
    ImGui.TableSetupColumn(ctx, "Strip width")
    ImGui.TableSetupColumn(ctx, "Background")
    ImGui.TableSetupColumn(ctx, "Track colour")
    ImGui.TableHeadersRow(ctx)
    for _, c in ipairs(TO.FADER_CATS) do
      local d = TO.fader_default(c.key) or {}
      ImGui.TableNextRow(ctx)
      ImGui.TableNextColumn(ctx)
      ImGui.AlignTextToFramePadding(ctx)
      ImGui.Text(ctx, c.label)
      ImGui.TableNextColumn(ctx)
      ImGui.SetNextItemWidth(ctx, 120)
      if ImGui.BeginCombo(ctx, "##vo_fs" .. c.key,
          d.style and style_label(C.FADER_STYLES, d.style, "Flat") or (c.key == "default" and "Plain" or "As Default"), ImGui.ComboFlags_HeightLargest) then
        if ImGui.Selectable(ctx, (c.key == "default") and "Plain" or "As Default", d.style == nil) then
          TO.set_fader_default(c.key, "style", nil, true)
        end
        for _, fs in ipairs(C.FADER_STYLES) do
          if ImGui.Selectable(ctx, fs.label, d.style == fs.key) then
            TO.set_fader_default(c.key, "style", fs.key, true)
          end
        end
        ImGui.EndCombo(ctx)
      end
      ImGui.TableNextColumn(ctx)
      local cc = W.cap_col(d.cap)
      if ImGui.ColorButton(ctx, "##vo_fc" .. c.key, cc or C.COL.fader_cap, ImGui.ColorEditFlags_NoTooltip, 34, 20) then
        ImGui.OpenPopup(ctx, "vo_fcp" .. c.key)
      end
      if ImGui.BeginPopup(ctx, "vo_fcp" .. c.key) then
        local before = d.cap
        CP.cap_swatches_win(ctx, "vo_fcs" .. c.key, d.cap, 0x808080, c.label .. " fader colour",
          function(k, save) TO.set_fader_default(c.key, "cap", k, save) end,
          function() TO.set_fader_default(c.key, "cap", before, true) end)
        if d.cap and ImGui.Selectable(ctx, "No colour of its own") then
          TO.set_fader_default(c.key, "cap", nil, true)
        end
        ImGui.EndPopup(ctx)
      end
      ImGui.TableNextColumn(ctx)
      ImGui.SetNextItemWidth(ctx, 120)
      if c.key == "default" then
        local wch, wv = ST.slider_int(ctx, "##vo_w" .. c.key, C.CHANNEL_W, C.CHANNEL_W_MIN, C.CHANNEL_W_MAX, "%d px")
        if wch then
          C.set_channel_w(wv)
          reaper.SetExtState(C.EXT_SECT, "channel_w", tostring(C.CHANNEL_W), true)
          bump()
        end
      else
        local gw = TO.group_w(c.key)
        local wch, wv = ST.slider_int(ctx, "##vo_w" .. c.key, gw or C.CHANNEL_W, C.CHANNEL_W_MIN, C.CHANNEL_W_MAX,
          gw and "%d px" or "As Default")
        if wch then TO.set_group_w(c.key, wv); bump() end
        if gw and ImGui.IsItemClicked(ctx, ImGui.MouseButton_Right) then TO.set_group_w(c.key, nil); bump() end
        if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "Right-click: as Default.") end
      end
      ImGui.TableNextColumn(ctx)
      ImGui.SetNextItemWidth(ctx, 160)
      local pct = TO.bg_tint(c.key)
      local bch, bv = ST.slider_int(ctx, "##vo_bt" .. c.key, pct, 0, 100, pct > 0 and "%d%% track colour" or "Off")
      if bch then TO.set_bg_tint(c.key, bv, true); bump() end
      -- the group's track colour (Track rules' colours)
      ImGui.TableNextColumn(ctx)
      if c.key == "default" then
        ImGui.AlignTextToFramePadding(ctx)
        ImGui.TextDisabled(ctx, "\u{2014}")
      else
        local cur = rules.grp[c.key]
        rules_colour_button(ctx, "vo_tc" .. c.key, cur, c.label .. " track colour", function(v)
          rules.grp[c.key] = v
          TR.save(rules)
        end)
        if cur then
          ImGui.SameLine(ctx)
          if ImGui.SmallButton(ctx, "\u{00d7}##vo_tcx" .. c.key) then rules.grp[c.key] = nil; TR.save(rules) end
        end
      end
    end
    ImGui.EndTable(ctx)
  end
  ImGui.TextDisabled(ctx, "A track's own look wins, then its group's, then the Default.")
  ImGui.TextDisabled(ctx, "Track colours: by Options \u{25B8} Track rules.")
  local _ = now
end

-- the fonts offered by name (any other: Other...)
local FONT_LIST, GENERIC = C.FONT_LIST, C.FONT_GENERIC
local other_name = {}     -- section -> the name being typed in Other...
local function font_row(ctx, tab, s, p, first)
  row(ctx, "Font")
  local cur = s[p .. "_font"]
  ImGui.SetNextItemWidth(ctx, 200)
  if ImGui.BeginCombo(ctx, "##vo_ff" .. p, cur or first, ImGui.ComboFlags_HeightLargest) then
    if ImGui.Selectable(ctx, first, cur == nil) then set(tab, p .. "_font", nil); other_name[p] = nil end
    ImGui.Separator(ctx)
    for _, n in ipairs(FONT_LIST) do
      if ImGui.Selectable(ctx, n, cur == n) then set(tab, p .. "_font", n); other_name[p] = nil end
    end
    ImGui.Separator(ctx)
    for _, n in ipairs(GENERIC) do
      if ImGui.Selectable(ctx, n, cur == n) then set(tab, p .. "_font", n); other_name[p] = nil end
    end
    ImGui.Separator(ctx)
    if ImGui.Selectable(ctx, "Other\u{2026}", false) then other_name[p] = cur or "" end
    ImGui.EndCombo(ctx)
  end
  if other_name[p] then
    ImGui.SameLine(ctx)
    ImGui.SetNextItemWidth(ctx, 160)
    local _, v = ImGui.InputTextWithHint(ctx, "##vo_fo" .. p, "Font name", other_name[p])
    other_name[p] = v
    if ImGui.IsItemDeactivatedAfterEdit(ctx) then
      local n = v:match("^%s*(.-)%s*$")
      set(tab, p .. "_font", n ~= "" and n or nil)
      other_name[p] = nil
    end
  end
  row(ctx, "Size")
  ImGui.SetNextItemWidth(ctx, 200)
  local lim = VO.SIZES[p]
  local ch, v = ST.slider_int(ctx, "##vo_fz" .. p, math.floor(val(s, p .. "_size")), lim[1], lim[2], "%d px")
  if ch then set(tab, p .. "_size", v) end
  row(ctx, "Style")
  local bch, bv = ST.checkbox(ctx, "Bold##vo_fb" .. p, val(s, p .. "_b"))
  if bch then set(tab, p .. "_b", bv) end
  ImGui.SameLine(ctx)
  local ich, iv = ST.checkbox(ctx, "Italic##vo_fi" .. p, val(s, p .. "_i"))
  if ich then set(tab, p .. "_i", iv) end
  ImGui.SameLine(ctx)
  local uch, uv = ST.checkbox(ctx, "Underline##vo_fu" .. p, val(s, p .. "_u"))
  if uch then set(tab, p .. "_u", uv) end
end

local function page_text(ctx, tab, s)
  section(ctx, "Text")
  font_row(ctx, tab, s, "t", "Default")
  section(ctx, "Headers")
  font_row(ctx, tab, s, "h", "Same as text")
  section(ctx, "Toolbars")
  font_row(ctx, tab, s, "b", "Same as text")
end

local function page_sizes(ctx, tab, s)
  section(ctx, "Sizes")
  if tab ~= "web" then
    row(ctx, "Overall size")
    ImGui.SetNextItemWidth(ctx, 200)
    local uch, uv = ST.slider_int(ctx, "##vo_ui", math.floor(val(s, "ui") + 0.5), 50, 150, "%d%%")
    if uch then set(tab, "ui", math.floor(uv / 5 + 0.5) * 5) end
    if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "Everything together: controls, text, panels and bars.") end
  end
  row(ctx, "Control spacing")
  ImGui.SetNextItemWidth(ctx, 200)
  local ch, v = ST.slider_int(ctx, "##vo_cw", math.floor(val(s, "cell_w")), C.CELL_W_MIN, C.CELL_W_MAX, "%d px")
  if ch then set(tab, "cell_w", v) end
end

local function page_depth(ctx, tab, s)
  section(ctx, "Depth", true)
  if not ED.PRO then ImGui.BeginDisabled(ctx, true) end
  row(ctx, "3D effect")
  local dch, dv = ST.checkbox(ctx, "On##vo_3d", val(s, "d3"))
  if dch then set(tab, "d3", dv) end
  if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "Gradients, lit edges and soft shadows.") end
  local d3 = val(s, "d3")
  if not d3 then ImGui.BeginDisabled(ctx, true) end
  row(ctx, "Lighting")
  ImGui.SetNextItemWidth(ctx, 200)
  local lch, lv = ST.slider_int(ctx, "##vo_li", math.floor(val(s, "light")), 0, C.LIGHT_MAX, "%d%%")
  if lch then set(tab, "light", lv) end
  row(ctx, "Shadows")
  ImGui.SetNextItemWidth(ctx, 200)
  local sch, sv = ST.slider_int(ctx, "##vo_sh", math.floor(val(s, "shadow")), 0, C.SHADOW_MAX, "%d%%")
  if sch then set(tab, "shadow", sv) end
  if not d3 then ImGui.EndDisabled(ctx) end
  if not ED.PRO then ImGui.EndDisabled(ctx) end
end

local PAGE_FN = { colour = page_colour, controls = page_controls, panels = page_panels,
                  tracks = page_tracks, text = page_text, sizes = page_sizes, depth = page_depth }

-- ---------------------------------------------------------------------
-- settings, not looks: Behaviour and Track rules
-- ---------------------------------------------------------------------

local function tip(ctx, text)
  if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, text) end
end

local function put_cv(k, v) reaper.SetExtState(C.EXT_SECT, k, v and "1" or "0", true) end

local function page_behaviour(ctx)
  section(ctx, "Plugins")
  if VO.float then
    local ch, v = ST.checkbox(ctx, "Float plugins without controls##vo_bfl", VO.float.get())
    if ch then VO.float.assign(v) end
    tip(ctx, "A plugin whose layout has no controls opens its own window when you\n" ..
      "come to its track, and it closes when you move on, unless you pin it\n" ..
      "(the pin in its panel's header).")
  end
  if ED.PRO and VO.float then
    local ch, v = ST.checkbox(ctx, "Offer canvases for new plugins##vo_bco", C.CANVAS_OFFERS)
    if ch then
      C.CANVAS_OFFERS = v
      put_cv("canvas_offers", v)
      if v then require("TS_CV_CanvasSetup").forget_nevers() end
    end
    tip(ctx, "A plugin with no layout whose controls look like a\n" ..
      "compressor, EQ, gate... offers that canvas.\nTurning it on again asks again for every plugin.")
  end
  section(ctx, "Controls")
  local ch, v = ST.checkbox(ctx, "Use mouse wheel on controls##vo_bwh", C.WHEEL_CONTROLS)
  if ch then C.WHEEL_CONTROLS = v; put_cv("wheel_controls", v) end
  tip(ctx, "Off: the wheel only scrolls.")
  local how = require("TS_CV_Focus").mechanism()
  ch, v = ST.checkbox(ctx, "Return keyboard focus to REAPER##vo_bfo", C.FOCUS_BACK and how ~= nil, { dim = how == nil })
  if ch then C.FOCUS_BACK = v; put_cv("focus_back", v) end
  tip(ctx, how and "Keyboard goes back to REAPER after a click,\nso Space and shortcuts keep working."
           or "Needs js_ReaScriptAPI or SWS.")
end

-- Settings that aren't part of a look, under a look's page: Values under
-- controls (Controls), Panel alignment (Panels, ChannelView and the rack).
local function page_extra(ctx, tab, page)
  if page == "controls" then
    section(ctx, "Every tab")
    local ch, v = ST.checkbox(ctx, "Values under controls##vo_xval", C.SHOW_VALUES)
    if ch then C.SHOW_VALUES = v; put_cv("show_values", v); bump() end
    tip(ctx, "Off: a control's value shows while you hover it.")
  elseif page == "panels" and (tab == "cv" or tab == "rack") and own_tab ~= "tcp" then
    section(ctx, "Every tab")
    row(ctx, "Panel alignment")
    ImGui.SetNextItemWidth(ctx, 140)
    if ImGui.BeginCombo(ctx, "##vo_xalign", C.ROW_ALIGN == "centre" and "Centred" or "Left") then
      if ImGui.Selectable(ctx, "Left", C.ROW_ALIGN ~= "centre") then
        C.ROW_ALIGN = "left"; reaper.SetExtState(C.EXT_SECT, "row_align", "left", true)
      end
      if ImGui.Selectable(ctx, "Centred", C.ROW_ALIGN == "centre") then
        C.ROW_ALIGN = "centre"; reaper.SetExtState(C.EXT_SECT, "row_align", "centre", true)
      end
      ImGui.EndCombo(ctx)
    end
  end
end

-- SWS's own auto colouring or auto layout on: it would fight the rules.
local sws = { ids = nil }
local function sws_auto_on()
  if not sws.ids then
    sws.ids = {}
    local sec = reaper.SectionFromUniqueID and reaper.SectionFromUniqueID(0)
    if reaper.kbd_enumerateActions and sec then
      local i = 0
      while true do
        local id, name = reaper.kbd_enumerateActions(sec, i)
        if not id or id <= 0 then break end
        local n = name and name:lower() or ""
        if n:find("^sws") and n:find("toggle auto") and (n:find("colo") or n:find("layout")) then
          sws.ids[#sws.ids + 1] = id
        end
        i = i + 1
      end
    end
  end
  for _, id in ipairs(sws.ids) do
    if reaper.GetToggleCommandState(id) == 1 then return true end
  end
  return false
end

local function rcombo(ctx, id, cur, opts, w)
  local label = cur
  for _, o in ipairs(opts) do if o[1] == cur then label = o[2] end end
  ImGui.SetNextItemWidth(ctx, w or 170)
  local out = nil
  if ImGui.BeginCombo(ctx, id, label) then
    for _, o in ipairs(opts) do
      if ImGui.Selectable(ctx, o[2], o[1] == cur) then out = o[1] end
    end
    ImGui.EndCombo(ctx)
  end
  return out
end

local function rrow(ctx, label)
  ImGui.AlignTextToFramePadding(ctx)
  ImGui.Text(ctx, label)
  ImGui.SameLine(ctx, 190)
end

local function page_rules(ctx)
  local TR = require("TS_CV_TrackRules")
  local r = TR.get()
  local dirty = false
  local function box(label, key, opts)
    local ch, v = ST.checkbox(ctx, label, r[key], opts)
    if ch then r[key] = v; dirty = true end
  end
  local function rpick(id, key, opts, w)
    local v = rcombo(ctx, id, r[key], opts, w)
    if v ~= nil and v ~= r[key] then r[key] = v; dirty = true end
  end
  local IND = 22

  if TR.colours_on(r) or TR.spacers_on(r) then
    if sws_auto_on() then
      ImGui.TextColored(ctx, C.COL.warn, "SWS auto colouring or auto layout is on: it changes tracks too. Use one or the other.")
    end
  end
  if ImGui.BeginTable(ctx, "##vo_rules", 2, ImGui.TableFlags_SizingStretchSame) then
    ImGui.TableNextRow(ctx)
    ImGui.TableNextColumn(ctx)

    section(ctx, "Adding and duplicating")
    box("Number them##vo_rnum", "number")
    tip(ctx, "Guitar 1 beside Guitar 1 becomes Guitar 2.")
    ImGui.SameLine(ctx)
    rpick("##vo_rnsc", "number_scope", { { "folder", "in their folder" }, { "project", "across the project" } }, 150)
    ImGui.Indent(ctx, IND)
    box("Templates with more than one track keep their names##vo_rmul", "keep_multi")
    tip(ctx, "A drum kit's Rack Tom 1 and 2 stay as they are.")
    ImGui.AlignTextToFramePadding(ctx)
    ImGui.TextDisabled(ctx, "Leave these folders alone")
    ImGui.SameLine(ctx)
    ImGui.SetNextItemWidth(ctx, 150)
    local ach, av = ImGui.InputTextWithHint(ctx, "##vo_ralone", "Drums, Strings", table.concat(r.alone, ", "))
    if ach then
      r.alone = {}
      for n in av:gmatch("[^,]+") do
        n = n:match("^%s*(.-)%s*$")
        if n ~= "" then r.alone[#r.alone + 1] = n end
      end
      dirty = true
    end
    tip(ctx, "Not numbered or sorted.")
    ImGui.Unindent(ctx, IND)
    rrow(ctx, "Sort the folder")
    rpick("##vo_rsort", "sort", { { "off", "Off" }, { "az", "A\u{2013}Z" }, { "series", "Keep a series together" } })
    rrow(ctx, "New children go")
    rpick("##vo_rkids", "children", { { "top", "at the top" }, { "bottom", "at the bottom" } })
    rrow(ctx, "Template's folders")
    rpick("##vo_rtf", "tfolders", { { "flatten", "flatten" }, { "keep", "keep as a sub-folder" } })
    box("Select and arm the new track##vo_rarm", "arm")
    tip(ctx, "The one with sends, when one has any; else all of them.")
    if r.arm then
      ImGui.Indent(ctx, IND)
      box("Disarm the others##vo_rdis", "disarm")
      if TR.tracking_installed() then
        box("Only in Tracking mode##vo_rtrk", "arm_tracking")
        tip(ctx, "TS_TrackingMode: in Mixing mode they're selected, not armed.")
      end
      ImGui.Unindent(ctx, IND)
    end

    section(ctx, "FX returns")
    rrow(ctx, "New returns go")
    rpick("##vo_rret", "ret_where", { { "end", "at the end" }, { "folder", "into the folder named" } })
    if r.ret_where == "folder" then
      ImGui.SameLine(ctx)
      ImGui.SetNextItemWidth(ctx, 100)
      local fch, fv = ImGui.InputText(ctx, "##vo_rretf", r.ret_folder or "")
      if fch then r.ret_folder = fv; dirty = true end
    end

    section(ctx, "End of the project")
    rrow(ctx, "Keep at the end")
    ImGui.SetNextItemWidth(ctx, 120)
    local lch, lv = ImGui.InputTextWithHint(ctx, "##vo_rlast", "a track's name", r.last or "")
    if lch then r.last = lv:match("^%s*(.-)%s*$"); dirty = true end
    tip(ctx, "Tracks ChannelView adds at the end go before it.\nSUM is Console setup's summing track.")

    section(ctx, "Spacers")
    box("Before each folder##vo_rsp1", "sp_folder")
    box("After each folder's last track##vo_rsp2", "sp_after")
    box("Before the FX returns##vo_rsp3", "sp_returns")
    if (r.last or "") ~= "" then box("Before " .. r.last .. "##vo_rsp4", "sp_sum") end
    if TR.spacers_on(r) then ImGui.TextDisabled(ctx, "Spacers elsewhere are taken out.") end

    ImGui.TableNextColumn(ctx)
    section(ctx, "Colours")
    rrow(ctx, "Tracks in a folder take")
    rpick("##vo_rcf", "col_folder", { { "off", "nothing" }, { "same", "its colour" }, { "shades", "shades of its colour" } })
    ImGui.Indent(ctx, IND)
    box("A template's own colour wins##vo_rtpl", "tpl_col")
    ImGui.Unindent(ctx, IND)
    ImGui.TextDisabled(ctx, "Name rules, first match wins:")
    local drop = nil
    for i, rule in ipairs(r.rules) do
      ImGui.PushID(ctx, "vo_rr" .. i)
      local v = rcombo(ctx, "##how", rule.how, { { "contains", "contains" }, { "is", "is" } }, 90)
      if v and v ~= rule.how then rule.how = v; dirty = true end
      ImGui.SameLine(ctx)
      ImGui.SetNextItemWidth(ctx, 120)
      local tch, tv = ImGui.InputText(ctx, "##txt", rule.text or "")
      if tch then rule.text = tv; dirty = true end
      ImGui.SameLine(ctx)
      rules_colour_button(ctx, "vo_rrc" .. i, rule.col, "Colour for \"" .. (rule.text or "") .. "\"", function(c)
        rule.col = c
        TR.save(r)
      end)
      ImGui.SameLine(ctx)
      if ImGui.SmallButton(ctx, "\u{00d7}##x") then drop = i end
      ImGui.PopID(ctx)
    end
    if drop then table.remove(r.rules, drop); dirty = true end
    if ImGui.SmallButton(ctx, "+ Rule##vo_radd") then
      r.rules[#r.rules + 1] = { how = "contains", text = "", col = 0x808080 }
      dirty = true
    end
    ImGui.TextDisabled(ctx, "Then group colours (Faders & strips), then the folder's.")
    ImGui.TextDisabled(ctx, "Tracks you've coloured yourself are left alone.")

    section(ctx, "When")
    rpick("##vo_rlive", "live", { { false, "Only on tracks ChannelView adds" }, { true, "As tracks are added and moved" } }, 230)
    if ImGui.Button(ctx, "Apply to the project now##vo_rapply") then
      local force = false
      local n = TR.colours_on(r) and TR.hand_coloured() or 0
      local go = true
      if n > 0 then
        local a = reaper.MB(("%d track%s have colours no rule gave them.\n\nRecolour them too?"):format(n, n == 1 and "" or "s"),
          "Track rules", 3)
        if a == 2 then go = false elseif a == 6 then force = true end
      end
      if go then TR.apply_all(force) end
    end
    ImGui.EndTable(ctx)
  end
  if dirty then TR.save(r) end
end

-- the preset bar: previous, the list, next, and + (save, rename, delete)
local naming = nil          -- { mode = "save"|"rename", name, old }
local function preset_bar(ctx, tab)
  local s = data[tab]
  local names = all_presets()
  local cur = val(s, "preset")
  local idx = 1
  for i, n in ipairs(names) do if n == cur then idx = i end end
  if not ED.PRO then ImGui.BeginDisabled(ctx, true) end
  ImGui.AlignTextToFramePadding(ctx)
  ImGui.Text(ctx, "Preset")
  ImGui.SameLine(ctx)
  if ImGui.ArrowButton(ctx, "##vo_pprev", ImGui.Dir_Left) then
    apply_preset(tab, names[(idx - 2) % #names + 1])
  end
  ImGui.SameLine(ctx, 0, 2)
  ImGui.SetNextItemWidth(ctx, 220)
  if ImGui.BeginCombo(ctx, "##vo_plist", cur .. (modified(tab) and " *" or ""), ImGui.ComboFlags_HeightLargest) then
    ImGui.TextDisabled(ctx, "Built in")
    for _, p in ipairs(VO.BUILTIN) do
      if ImGui.Selectable(ctx, p.name, p.name == cur) then apply_preset(tab, p.name) end
    end
    if #user > 0 then
      ImGui.SeparatorText(ctx, "Yours")
      for _, p in ipairs(user) do
        if ImGui.Selectable(ctx, p.name .. "##vou", p.name == cur) then apply_preset(tab, p.name) end
      end
    end
    ImGui.EndCombo(ctx)
  end
  ImGui.SameLine(ctx, 0, 2)
  if ImGui.ArrowButton(ctx, "##vo_pnext", ImGui.Dir_Right) then
    apply_preset(tab, names[idx % #names + 1])
  end
  ImGui.SameLine(ctx)
  if ImGui.Button(ctx, "+##vo_pplus", 22, 0) then ImGui.OpenPopup(ctx, "vo_pmenu") end
  if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "Save, rename or delete") end
  if ImGui.BeginPopup(ctx, "vo_pmenu") then
    local _, built = preset_of(cur)
    if ImGui.MenuItem(ctx, "Save preset\u{2026}") then
      naming = { mode = "save", name = built and "" or cur }
    end
    if ImGui.MenuItem(ctx, "Rename\u{2026}", nil, false, not built) then
      naming = { mode = "rename", name = cur, old = cur }
    end
    if ImGui.MenuItem(ctx, "Delete", nil, false, not built) then
      for i, p in ipairs(user) do if p.name == cur then table.remove(user, i) break end end
      write_user()
      s.preset = "Standard"
      write_tab(tab)
    end
    ImGui.EndPopup(ctx)
  end
  -- By time, its list shown or hidden, and the next time while hidden
  ImGui.SameLine(ctx)
  local on = VO.by_time(tab)
  local bch, bv = ST.checkbox(ctx, "By time##vo_bt", on)
  if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "Change preset at set times of day") end
  if bch then
    VO.set_by_time(tab, bv)
    win.times = bv
    own_changed(tab)
  end
  if on and not bch then
    ImGui.SameLine(ctx, 0, 2)
    if ImGui.ArrowButton(ctx, "##vo_btshow", win.times and ImGui.Dir_Down or ImGui.Dir_Right) then
      win.times = not win.times
    end
    if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, win.times and "Hide the times" or "Show the times") end
    local nx = VO.next_time(tab)
    if nx and not win.times then
      ImGui.SameLine(ctx)
      ImGui.AlignTextToFramePadding(ctx)
      ImGui.TextDisabled(ctx, "until " .. nx)
    end
  end
  if naming then
    ImGui.SameLine(ctx)
    ImGui.SetNextItemWidth(ctx, 160)
    if naming.focus == nil then ImGui.SetKeyboardFocusHere(ctx); naming.focus = true end
    local ch, v = ImGui.InputTextWithHint(ctx, "##vo_pname", "Preset name", naming.name)
    if ch then naming.name = v end
    ImGui.SameLine(ctx)
    local done = ImGui.Button(ctx, "OK##vo_pok") or ImGui.IsKeyPressed(ctx, ImGui.Key_Enter)
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, "Cancel##vo_pc") or ImGui.IsKeyPressed(ctx, ImGui.Key_Escape) then naming = nil end
    if done and naming and naming.name:match("%S") then
      local name = naming.name:gsub("^%s+", ""):gsub("%s+$", "")
      if naming.mode == "rename" then
        if not preset_of(name) then
          for _, p in ipairs(user) do if p.name == naming.old then p.name = name end end
          write_user()
          for _, t in ipairs(VO.TABS) do
            if data[t.key].preset == naming.old then data[t.key].preset = name; write_tab(t.key) end
            local renamed = false
            for _, e in ipairs(times[t.key] or {}) do
              if e.name == naming.old then e.name = name; renamed = true end
            end
            if renamed then write_times(t.key, true) end
          end
        end
      else
        save_preset(tab, name)
      end
      naming = nil
    end
  end
  if not ED.PRO then ImGui.EndDisabled(ctx) end
  pro_note(ctx)
end

-- By time's list: a time and a preset a row, a lamp on the one on now
local typed = {}             -- row -> the time being typed
local function times_list(ctx, tab)
  local list = times[tab] or {}
  local cur = slot_now(list)
  local names = all_presets()
  local K = C.COL
  local dirty, drop = false, nil
  ImGui.Indent(ctx, 44)
  for i, e in ipairs(list) do
    ImGui.PushID(ctx, i)
    ImGui.SetNextItemWidth(ctx, 52)
    local ch, v = ImGui.InputText(ctx, "##vo_tm", typed[i] or VO.time_text(e.m))
    if ch then typed[i] = v end
    if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "From (24-hour, HH:MM)") end
    if ImGui.IsItemDeactivated(ctx) then
      local m = VO.parse_time(typed[i])
      if m and m ~= e.m then e.m = m; dirty = true end
      typed[i] = nil
    end
    ImGui.SameLine(ctx)
    ImGui.SetNextItemWidth(ctx, 200)
    if ImGui.BeginCombo(ctx, "##vo_tp", e.name .. (preset_of(e.name) and "" or "  (deleted)"), ImGui.ComboFlags_HeightLargest) then
      for _, n in ipairs(names) do
        if ImGui.Selectable(ctx, n, n == e.name) and n ~= e.name then e.name = n; dirty = true end
      end
      ImGui.EndCombo(ctx)
    end
    ImGui.SameLine(ctx)
    local x, y = ImGui.GetCursorScreenPos(ctx)
    local h = ImGui.GetFrameHeight(ctx)
    local dl = ImGui.GetWindowDrawList(ctx)
    if i == cur then
      ImGui.DrawList_AddCircleFilled(dl, x + 6, y + h * 0.5, 6.5, (K.accent & 0xffffff00) | 0x40, 16)
      ImGui.DrawList_AddCircleFilled(dl, x + 6, y + h * 0.5, 4.0, K.accent, 16)
    else
      ImGui.DrawList_AddCircleFilled(dl, x + 6, y + h * 0.5, 4.0, K.toggle_off, 16)
      ImGui.DrawList_AddCircle(dl, x + 6, y + h * 0.5, 4.0, K.ui_edge, 16, 1.0)
    end
    ImGui.Dummy(ctx, 12, h)
    if i == cur and ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "On now") end
    ImGui.SameLine(ctx)
    if ST.button(ctx, "\u{00D7}##vo_tx", "remove", 22, 0) then drop = i end
    ImGui.PopID(ctx)
  end
  if ST.button(ctx, "+ Add a time##vo_tadd") then
    local last = list[#list]
    list[#list + 1] = { m = last and (last.m + 60) % 1440 or 12 * 60, name = val(data[tab], "preset") }
    dirty = true
  end
  ImGui.Unindent(ctx, 44)
  if drop then table.remove(list, drop); typed = {}; dirty = true end
  if dirty then
    times[tab] = list
    write_times(tab)
    VO.tick()
    own_changed(tab)
  end
end

-- a few controls in the tab's look
local function draw_preview(ctx, tab)
  local swapped = tab ~= own_tab and not (follow[own_tab] and follow[tab]) and not (tab == "cv" and follow[own_tab])
  if swapped then VO.apply(tab) end
  ImGui.TextDisabled(ctx, "Preview")
  local dl = ImGui.GetWindowDrawList(ctx)
  local x, y = ImGui.GetCursorScreenPos(ctx)
  local w, h = 210, 230
  ImGui.DrawList_AddRectFilled(dl, x, y, x + w, y + h, C.COL.panel_bg, C.PANEL_RR)
  ImGui.DrawList_AddRectFilled(dl, x, y, x + w, y + 22, C.COL.header_bg, C.PANEL_RR, ImGui.DrawFlags_RoundCornersTop)
  ImGui.DrawList_AddRect(dl, x, y, x + w, y + h, C.COL.panel_border, C.PANEL_RR)
  -- every control works, its state kept in `win` while the window's open
  win.pw = (win.pw == nil) and true or win.pw
  win.kv = win.kv or { 0.45, 0.62, 0.3 }
  win.btn = win.btn or 1
  win.sc = win.sc or 1
  win.trk = win.trk or 1
  local function hit(id, bx, by, bw, bh)
    ImGui.SetCursorScreenPos(ctx, bx, by)
    return ImGui.InvisibleButton(ctx, id, bw, bh)
  end
  if hit("##vo_ppw", x + 4, y + 3, 16, 16) then win.pw = not win.pw end
  if C.POWER == "lamp" then
    ImGui.DrawList_AddRectFilled(dl, x + 8, y + 7, x + 16, y + 15, win.pw and C.COL.accent or C.COL.knob_track, 1.0)
  else
    W.ICONS.power(dl, x + 5, y + 4, 14, win.pw and C.COL.icon or C.COL.header_dim)
  end
  do
    local hf = W.push_font(ctx, "head")
    local tw, th = ImGui.CalcTextSize(ctx, "Compressor")
    local ty = y + (22 - th) * 0.5
    ImGui.DrawList_AddText(dl, x + 22, ty, C.COL.header_text, "Compressor")
    if W.underlined("head") then W.underline(dl, x + 22, ty, tw, th, C.COL.header_text) end
    W.pop_font(ctx, hf)
  end
  local text_font = W.push_font(ctx, "text")
  local KD = 34
  for i = 1, 3 do
    local cx = x + 36 + (i - 1) * 68
    hit("##vo_pk" .. i, cx - KD * 0.5, y + 49, KD, KD)
    if ImGui.IsItemActive(ctx) then
      local _, dy = ImGui.GetMouseDelta(ctx)
      win.kv[i] = math.max(0, math.min(1, win.kv[i] - dy * 0.006))
      ImGui.SetMouseCursor(ctx, ImGui.MouseCursor_ResizeNS)
    elseif ImGui.IsItemHovered(ctx) then
      local wh = W.control_wheel(ctx)
      if wh ~= 0 then win.kv[i] = math.max(0, math.min(1, win.kv[i] + wh * 0.02)); W.take_wheel() end
      if ImGui.IsMouseDoubleClicked(ctx, ImGui.MouseButton_Left) then win.kv[i] = (i == 2) and 0.5 or 0.45 end
    end
    W.centred_text(ctx, dl, cx, y + 30, ({ "Thresh", "Gain", "Mix" })[i], C.COL.label, 64)
    W.knob_face(dl, cx, y + 66, KD * 0.5, win.kv[i], { bipolar = (i == 2), ctx = ctx })
  end
  -- buttons
  local bst = C.DEF.button
  for i = 1, 3 do
    local on = win.btn == i
    local bx = x + 10 + (i - 1) * 64
    local by = y + 100
    if hit("##vo_pb" .. i, bx, by, 58, 20) then win.btn = i end
    local ink = W.button_face(dl, bx, by, bx + 58, by + 20, 3.0, on, W.lit_col(C.DEF.button_col) or C.COL.toggle_on,
      (bst and C.BUTTON_STYLE[bst]) and bst or nil, false)
    if not ink then
      ImGui.DrawList_AddRectFilled(dl, bx, by, bx + 58, by + 20, on and C.COL.toggle_on or C.COL.toggle_off, 3.0)
      ImGui.DrawList_AddRect(dl, bx, by, bx + 58, by + 20, C.COL.knob_ring, 3.0, 0, 1.0)
      ink = on and 0x0d1116ff or C.COL.toggle_text
    end
    ImGui.DrawList_AddText(dl, bx + 18, by + 3, ink, ({ "VCA", "FET", "OPT" })[i])
  end
  -- dropdown
  local SC = { "Off", "Internal", "External" }
  if hit("##vo_pcb", x + 10, y + 132, w - 20, 20) then ImGui.OpenPopup(ctx, "##vo_pcm") end
  W.combo_swatch(dl, x + 10, y + 132, x + w - 10, y + 152, C.DEF.combo == "raised", C.DEF.combo == "minimal")
  ImGui.DrawList_AddText(dl, x + 16, y + 135, C.COL.toggle_text, "Sidechain: " .. SC[win.sc])
  if ImGui.BeginPopup(ctx, "##vo_pcm") then
    for i, n in ipairs(SC) do
      if ImGui.Selectable(ctx, n .. "##vo_pcs" .. i, win.sc == i) then win.sc = i end
    end
    ImGui.EndPopup(ctx)
  end
  -- a fader across
  ImGui.SetCursorScreenPos(ctx, x + 10, y + 166)
  win.fv = win.fv or 0.6
  local _, fv = W.hfader(ctx, "##vo_pf", x + 10, y + 166, w - 20, 26, win.fv, nil, nil,
    C.DEF.fader and { style = C.DEF.fader, cap = W.cap_col(C.DEF.fader_cap) } or nil)
  win.fv = fv
  -- track buttons
  local tw = (w - 4) / 3
  for i, tc in ipairs({ 0xe05a8aff, 0xa05ae0ff, 0x5ab4e0ff }) do
    local bx, by = x + (i - 1) * (tw + 2), y + h + 6
    local filled = C.TRACK_COL == "filled"
    if hit("##vo_pt" .. i, bx, by, tw, 22) then win.trk = i end
    ImGui.DrawList_AddRectFilled(dl, bx, by, bx + tw, by + 22, filled and tc or C.COL.panel_bg, C.STRIP_ROUND)
    if win.trk == i then
      ImGui.DrawList_AddRect(dl, bx, by, bx + tw, by + 22, C.COL.header_text, C.STRIP_ROUND, 0, 1.0)
    end
    if C.TRACK_COL == "bar" then ImGui.DrawList_AddRectFilled(dl, bx, by, bx + tw, by + 3, tc)
    elseif not filled then ImGui.DrawList_AddRectFilled(dl, bx, by + 19, bx + tw, by + 22, tc) end
    ImGui.DrawList_AddText(dl, bx + 5, by + (C.TRACK_COL == "bar" and 5 or 3),
      filled and U.contrast_text(tc) or C.COL.header_text, ({ "4 Vox", "5 BV", "6 Keys" })[i])
  end
  W.pop_font(ctx, text_font)
  -- a toolbar's buttons
  local bar_font = W.push_font(ctx, "bar")
  local bx = x
  for _, t in ipairs({ "EQ", "Comp", "Reverb" }) do
    local tw, th = ImGui.CalcTextSize(ctx, t)
    local bw, by = tw + 14, y + h + 34
    ImGui.DrawList_AddRectFilled(dl, bx, by, bx + bw, by + 22, C.COL.toggle_off, 2.5)
    ImGui.DrawList_AddRect(dl, bx, by, bx + bw, by + 22, C.COL.knob_ring, 2.5, 0, 1.0)
    ImGui.DrawList_AddText(dl, bx + 7, by + (22 - th) * 0.5, C.COL.label, t)
    if W.underlined("bar") then W.underline(dl, bx + 7, by + (22 - th) * 0.5, tw, th, C.COL.label) end
    bx = bx + bw + 4
  end
  W.pop_font(ctx, bar_font)
  ImGui.SetCursorScreenPos(ctx, x, y + h + 60)
  ImGui.Dummy(ctx, w, 1)
  if swapped then VO.apply(own_tab) end
end

-- Draw the window, if open; `mine` the caller's tab ("cv", "rack" or
-- "tcp"). Call once a frame, outside the main window.
function VO.draw(ctx, mine)
  own_tab = mine or own_tab
  if not win.open then return end
  ImGui.SetNextWindowSize(ctx, 900, 560, ImGui.Cond_FirstUseEver)
  local visible, open = ImGui.Begin(ctx, "Options###tscv_visual", true, ImGui.WindowFlags_NoCollapse)
  if visible then
    if ImGui.BeginTabBar(ctx, "##vo_tabs") then
      for _, t in ipairs(VO.TABS) do
        local flags = (win.select == t.key) and ImGui.TabItemFlags_SetSelected or 0
        if ImGui.BeginTabItem(ctx, t.label .. "##vo_t" .. t.key, nil, flags) then
          win.tab = t.key
          ImGui.EndTabItem(ctx)
        end
      end
      -- settings, not looks
      ImGui.BeginDisabled(ctx, true)
      ImGui.TabItemButton(ctx, "|##vo_tdiv", ImGui.TabItemFlags_NoTooltip)
      ImGui.EndDisabled(ctx)
      for _, t in ipairs(VO.SETTINGS) do
        local flags = (win.select == t.key) and ImGui.TabItemFlags_SetSelected or 0
        if ImGui.BeginTabItem(ctx, t.label .. "##vo_t" .. t.key, nil, flags) then
          win.tab = t.key
          ImGui.EndTabItem(ctx)
        end
      end
      ImGui.EndTabBar(ctx)
    end
    win.select = nil
    local tab = win.tab
    if tab == "behaviour" or tab == "rules" then
      if ImGui.BeginChild(ctx, "##vo_settings", 0, 0) then
        if tab == "behaviour" then page_behaviour(ctx) else page_rules(ctx) end
        ImGui.EndChild(ctx)
      end
      ImGui.End(ctx)
      if not open then win.open = false; naming = nil end
      return
    end
    local s = data[tab]
    local follows = follow[tab]
    if follows then ImGui.BeginDisabled(ctx, true) end
    preset_bar(ctx, tab)
    if follows then ImGui.EndDisabled(ctx) end
    if tab ~= "cv" then
      ImGui.SameLine(ctx)
      ImGui.SetCursorPosX(ctx, math.max(ImGui.GetCursorPosX(ctx), ImGui.GetWindowWidth(ctx) - 190))
      local fch, fv = ST.checkbox(ctx, "Follow ChannelView##vo_fol", follows)
      if fch then
        follow[tab] = fv
        if not fv then
          -- starts from a copy of ChannelView's
          data[tab] = {}
          for k, v in pairs(VO.effective("cv")) do data[tab][k] = v end
          write_tab(tab)
        end
        put("follow_" .. tab, fv and "1" or "0")
        bump()
        rev_seen = get("rev")
        own_changed(tab)
        if tab == own_tab then VO.apply(own_tab) end
      end
    end
    if win.times and VO.by_time(tab) then
      if follows or not ED.PRO then ImGui.BeginDisabled(ctx, true) end
      times_list(ctx, tab)
      if follows or not ED.PRO then ImGui.EndDisabled(ctx) end
    end
    ImGui.Separator(ctx)

    -- pages down the left
    if ImGui.BeginChild(ctx, "##vo_nav", 140, 0) then
      for _, p in ipairs(VO.PAGES) do
        if ImGui.Selectable(ctx, p.label, win.page == p.key) then win.page = p.key end
      end
      ImGui.EndChild(ctx)
    end
    ImGui.SameLine(ctx)
    if ImGui.BeginChild(ctx, "##vo_page", -240, 0) then
      if win.page == "faders" then
        page_faders(ctx)
      else
        if follows then ImGui.BeginDisabled(ctx, true) end
        PAGE_FN[win.page](ctx, tab, follows and VO.effective(tab) or s)
        if follows then ImGui.EndDisabled(ctx) end
        page_extra(ctx, tab, win.page)
        if tab == "tcp" then tcp_rows(ctx, win.page) end
      end
      ImGui.EndChild(ctx)
    end
    ImGui.SameLine(ctx)
    if ImGui.BeginChild(ctx, "##vo_prev", 0, 0) then
      draw_preview(ctx, tab)
      ImGui.EndChild(ctx)
    end
    ImGui.End(ctx)
  end
  if not open then win.open = false; naming = nil end
end

return VO
