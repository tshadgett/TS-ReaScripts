-- @noindex
-- Not a package of its own: installed by TS_ChannelView.lua's @provides.
--[[
  TS_CV_VisualOptions.lua -- View > Visual Options: one window for how
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
  { "trackcol",   "stripe", "str",  true },
  { "icons",      false,    "bool", true },
  { "cell_w",     C.CELL_W_DEFAULT, "num", true },
  { "d3",         true,     "bool", true },
  { "light",      100,      "num",  true },
  { "shadow",     100,      "num",  true },
  { "preset",     "Standard", "str", false },
  -- Faders & strips: the groups' fader looks, backgrounds and widths, the
  -- strip width, REAPER's spacer size
  { "g_fd",       nil,      "str",  "g" },
  { "g_bt",       nil,      "str",  "g" },
  { "g_gw",       nil,      "str",  "g" },
  { "g_cw",       nil,      "num",  "g" },
  { "g_sp",       nil,      "num",  "g" },
}
local FIELD = {}
for _, f in ipairs(FIELDS) do FIELD[f[1]] = f end

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

local function read_all()
  for _, t in ipairs(VO.TABS) do
    data[t.key] = decode(get("tab_" .. t.key))
    follow[t.key] = t.key ~= "cv" and get("follow_" .. t.key) ~= "0"
  end
  user = {}
  for line in (get("presets") or ""):gmatch("[^\n]+") do
    local name, s = line:match("^(.-)\t(.*)$")
    if name and name ~= "" then user[#user + 1] = { name = name, s = decode(s) } end
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
  for _, p in ipairs(user) do lines[#lines + 1] = p.name:gsub("[\t\n]", " ") .. "\t" .. encode(p.s) end
  put("presets", table.concat(lines, "\n"))
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
-- everything has been read again).
function VO.poll()
  local r = get("rev")
  if r ~= rev_seen then read_all(); return true end
  return false
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
  C.TRACK_ICONS = val(s, "icons")
  C.TCP_ICONS   = C.TRACK_ICONS
  C.set_cell_w(val(s, "cell_w"))
  C.EFFECT_3D = pro and val(s, "d3") or false
  C.LIGHT  = math.max(0, math.min(C.LIGHT_MAX, val(s, "light")))
  C.SHADOW = math.max(0, math.min(C.SHADOW_MAX, val(s, "shadow")))
  KP.LIGHT = C.LIGHT / 100
  ED.light().STRENGTH = C.SHADOW / 100
  C.build_palette()
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
    for k, v in pairs(g) do if p.s[k] ~= v then return true end end
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

-- (for the tests)
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

  section(ctx, "Track faders, widths and backgrounds, by group")
  local now = reaper.time_precise()
  if ImGui.BeginTable(ctx, "##vo_groups", 5, ImGui.TableFlags_SizingFixedFit) then
    ImGui.TableSetupColumn(ctx, "")
    ImGui.TableSetupColumn(ctx, "Fader style")
    ImGui.TableSetupColumn(ctx, "Colour")
    ImGui.TableSetupColumn(ctx, "Strip width")
    ImGui.TableSetupColumn(ctx, "Background")
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
          d.style and style_label(C.FADER_STYLES, d.style, "Flat") or (c.key == "default" and "Plain" or "As Default")) then
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
    end
    ImGui.EndTable(ctx)
  end
  ImGui.TextDisabled(ctx, "A track's own look wins, then its group's, then the Default.")
  local _ = now
end

local function page_sizes(ctx, tab, s)
  section(ctx, "Sizes")
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
                  tracks = page_tracks, sizes = page_sizes, depth = page_depth }

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
  if ImGui.BeginCombo(ctx, "##vo_plist", cur .. (modified(tab) and " *" or "")) then
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
  ImGui.DrawList_AddText(dl, x + 22, y + 4, C.COL.header_text, "Compressor")
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
    ImGui.DrawList_AddText(dl, cx - 16, y + 30, C.COL.label, ({ "Thresh", "Gain", "Mix" })[i])
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
  ImGui.SetCursorScreenPos(ctx, x, y + h + 32)
  ImGui.Dummy(ctx, w, 1)
  if swapped then VO.apply(own_tab) end
end

-- Draw the window, if open; `mine` the caller's tab ("cv", "rack" or
-- "tcp"). Call once a frame, outside the main window.
function VO.draw(ctx, mine)
  own_tab = mine or own_tab
  if not win.open then return end
  ImGui.SetNextWindowSize(ctx, 900, 560, ImGui.Cond_FirstUseEver)
  local visible, open = ImGui.Begin(ctx, "Visual Options###tscv_visual", true, ImGui.WindowFlags_NoCollapse)
  if visible then
    if ImGui.BeginTabBar(ctx, "##vo_tabs") then
      for _, t in ipairs(VO.TABS) do
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
