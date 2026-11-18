-- @noindex
-- Not a package of its own: installed by TS_ChannelView.lua's @provides.
--[[
  TS_CV_Channel.lua -- the Channel panel, pinned to the left.

  Fader, level meter, pan, and the channel's state buttons. Pinned outside
  the scrolling row on purpose: the fader is the one control you reach for
  regardless of which plugin you were looking at, and hunting for it after
  scrolling through a long chain would be absurd.

  Volume, dB and the fader taper all come from TS_CV_Util. REAPER's Lua API
  does not expose VAL2DB / DB2VAL / DB2SLIDER / SLIDER2DB, so the maths is
  ours; see there for the shape of the curve and why it isn't linear.
--]]

local C  = require("TS_CV_Config")
local U  = require("TS_CV_Util")
local W  = require("TS_CV_Widgets")
local ST = require("TS_CV_Style")
local St = require("TS_CV_State")
local G  = require("TS_CV_Gang")
local TM = require("TS_CV_TrackMenu")
local IN = require("TS_CV_Inputs")
local TP = require("TS_CV_Taps")
local B  = require("TS_CV_Browser")
local AC = require("TS_CV_Actions")
local TO = require("TS_CV_TrackOps")
local CP = require("TS_CV_ColourPick")

local CH = {}
local ImGui

-- Inputs draws its menu from inside the strip body, so it is attached
-- here along with the module that uses it.
function CH.attach(imgui) ImGui = imgui; IN.attach(imgui) end

local KEY = "##channel"        -- collapse state key, not an FX GUID

-- ---------------------------------------------------------------------
-- the fader's look, and its right-click menu
-- ---------------------------------------------------------------------
-- A track's fader can have a style and colour of its own, or take its
-- group's -- folder parents, VCA leaders and FX returns each can have one
-- (TS_CV_TrackOps). Right-click the fader, here, in a mixer strip or in the
-- TCP window's panel: it acts on the selection when the track is part of
-- it, on the one track otherwise, as REAPER's own menus do.

-- How a track's fader is drawn: W.fader's `look`, or nil for the plain one.
local function look_for(track, now)
  local l = TO.effective_fader_look(track, now)
  if not l then return nil end
  return { style = l.style, cap = W.cap_col(l.cap) }
end

local function fader_targets(track)
  if reaper.IsTrackSelected(track) then
    local out = {}
    for i = 0, reaper.CountSelectedTracks2(0, true) - 1 do
      out[#out + 1] = reaper.GetSelectedTrack2(0, i, true)
    end
    if #out > 0 then return out end
  end
  return { track }
end

-- Style and colour choices: `now` = { style, cap } chosen now (either nil);
-- `none` = the label for choosing nothing; choose_part(field, value, save)
-- makes a choice; undo_pick() puts back what was there (the picker's
-- Cancel); `from`
-- the colour the picker starts on.
local function look_choices(ctx, id, now, none, none_tip, choose_part, undo_pick, from, title)
  now = now or {}
  ST.caption(ctx, "Style")
  if ImGui.Selectable(ctx, none .. "##" .. id .. "_sn", now.style == nil, CP.KEEP_OPEN, 160, 0) then
    choose_part("style", nil, true)
  end
  if none_tip and ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, none_tip) end
  for _, fs in ipairs(C.FADER_STYLES) do
    if ImGui.Selectable(ctx, fs.label .. "##" .. id .. "_s" .. fs.key, now.style == fs.key, CP.KEEP_OPEN, 160, 0) then
      choose_part("style", fs.key, true)
    end
  end
  ImGui.Spacing(ctx)
  ST.caption(ctx, "Colour")
  if ImGui.Selectable(ctx, none .. "##" .. id .. "_cn", now.cap == nil, CP.KEEP_OPEN, 160, 0) then
    choose_part("cap", nil, true)
  end
  if none_tip and ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, none_tip) end
  CP.cap_swatches(ctx, id, now.cap, from, title,
    function(k, save) choose_part("cap", k, save) end, undo_pick)
end

-- "Volume / Pan automation lane": shows the track's envelope (made if
-- there isn't one), or hides it.
function CH.lane_item(ctx, track, name, label)
  local EN = require("TS_CV_Envelopes")
  local l = EN.track_lane(track, name)
  if ImGui.MenuItem(ctx, (label or name) .. " automation lane", l and l.auto and "has automation" or nil,
                    l ~= nil and l.shown) then
    EN.toggle_track_lane(track, name)
  end
end

-- The menu itself; call every frame with the popup id the fader opened.
local function fader_menu(ctx, track, pid)
  if not ImGui.BeginPopup(ctx, pid) then return end
  if not reaper.ValidatePtr2(0, track, "MediaTrack*") then
    ImGui.EndPopup(ctx)
    return
  end
  local tg = fader_targets(track)
  local now = reaper.time_precise()
  local own = TO.fader_look(track, now)
  local cat = TO.fader_category(track, now)
  local cat_label
  for _, c in ipairs(TO.FADER_CATS) do if c.key == cat then cat_label = c.label end end
  local _, name = reaper.GetTrackName(track)
  ImGui.TextDisabled(ctx, (#tg > 1) and (#tg .. " tracks' faders") or ((name or "Track") .. "'s fader"))
  ImGui.Separator(ctx)
  CH.lane_item(ctx, track, "Volume")
  ImGui.Separator(ctx)

  -- this track's (or the selection's) own
  local snap = {}
  for i, tr in ipairs(tg) do snap[i] = TO.fader_raw(tr) end
  local function revert()
    for i, tr in ipairs(tg) do TO.set_fader_raw(tr, snap[i]) end
  end
  local eff = TO.effective_fader_look(track, now)
  local col = W.cap_col(eff and eff.cap)
  look_choices(ctx, "fown", own, cat_label and ("As " .. cat_label:lower()) or "Default",
    cat_label and ("The " .. cat_label:lower() .. " group's look, else Default")
      or "The Default look, else plain",
    function(field, value, save) TO.set_fader_part(tg, field, value, save) end,
    revert, col and (col >> 8), "Fader colour")

  -- this track's (or the selection's) own background strength, over its
  -- group's -- as the fader look above
  do
    local mine = TO.own_tint(track, now)
    local grp = TO.track_tint(track)
    ImGui.Spacing(ctx)
    ST.caption(ctx, "Background")
    ImGui.SetNextItemWidth(ctx, 250)
    local shown = mine or math.floor(grp * 100 + 0.5)
    local fmt = mine and (mine > 0 and "%d%% track colour" or "Off")
                or (shown > 0 and ("%d%%  (" .. (cat_label and cat_label:lower() or "default") .. ")") or "As group: off")
    local bch, bv = ST.slider_int(ctx, "##bgown", shown, 0, 100, fmt)
    if bch then TO.set_own_tint(tg, bv) end
    if ImGui.IsItemHovered(ctx) then
      ImGui.SetTooltip(ctx, "Strip, name and Channel panel tinted in the track colour\n" ..
        "Overrides the group's setting")
    end
    if mine then
      ImGui.SameLine(ctx)
      if ImGui.SmallButton(ctx, "As group##bgown") then TO.set_own_tint(tg, nil) end
    end
  end

  ImGui.Spacing(ctx)
  ImGui.Separator(ctx)
  if ImGui.MenuItem(ctx, "Reset to default", nil, false, own ~= nil) then TO.clear_fader_look(tg) end
  if ImGui.IsItemHovered(ctx, ImGui.HoveredFlags_AllowWhenDisabled) then
    ImGui.SetTooltip(ctx, cat_label and ("Back to the " .. cat_label:lower() .. " look") or "Back to the Default look")
  end

  -- each group's look, width and background: Options ▸ Faders &
  -- strips (the window that drew this hands CH.group_looks its opener)
  if CH.group_looks and ImGui.MenuItem(ctx, "Group looks\u{2026}") then CH.group_looks() end
  ImGui.EndPopup(ctx)
end

-- ---------------------------------------------------------------------

function CH.width(collapsed)
  return collapsed and C.COLLAPSED_W or C.CHANNEL_W
end

function CH.is_collapsed() return St.is_collapsed(KEY) end

-- Collapsing gangs like everything else: fold one of six selected
-- strips and all six fold. A mixer collapse key is "<prefix>:<guid>",
-- so the others' keys are the same prefix with their own guid; the
-- pinned Channel panel's key has no guid in it at all and falls
-- straight through to the plain set, which is right -- there is only
-- one of it.
function CH.set_collapse(ckey, track, want)
  local prefix = ckey:match("^(.-:)")
  if prefix and track then
    local keys = G.collapse_keys(track, prefix)
    if #keys > 0 then
      for _, k in ipairs(keys) do St.set_collapsed(k, want) end
      return
    end
  end
  St.set_collapsed(ckey, want)
end

-- Set when the panel's background was double-clicked. The caller reads
-- and clears it: this module has no business knowing what a view is.
CH.want_mixer = false

-- REAPER answers nil, not 0, when a track does not HAVE the thing you
-- asked about -- record arm on the master, most obviously -- and `nil >
-- 0.5` is a hard error, not a false. So every read has a default, and
-- CH.state below decides which of these the track has at all.
function CH.read(track, key, dflt)
  local v = track and reaper.GetMediaTrackInfo_Value(track, key)
  if v == nil then return dflt or 0 end
  return v
end
local function get(track, key, dflt) return CH.read(track, key, dflt) end
-- Every absolute write goes through the gang: if this track is one of
-- several selected, they all take it. One function, so there is no
-- control that quietly forgot. Volume and pan are the exceptions and
-- call G.vol / G.pan, because they move BY an amount rather than TO a
-- value -- see TS_CV_Gang.
local function set(track, key, v) G.set(track, key, v) end

-- Ctrl+click (Cmd on a Mac) on the volume or pan: a value typed in (W.type_box).
-- Volume in dB ("-6", "+2.5", "-inf"); pan as "30L", "15R", "C" or -100..100.
function CH.typed_vol(text)
  local low = (text or ""):lower()
  if low:match("inf") then return 0 end
  local db = tonumber(low:match("[%+%-]?%d*%.?%d+") or "")
  if not db then return nil end
  return 10 ^ (math.min(24, db) / 20)
end
function CH.typed_pan(text)
  local up = U.trim(text or ""):upper()
  if up == "C" or up == "CENTRE" or up == "CENTER" then return 0 end
  local n = tonumber(up:match("[%+%-]?%d*%.?%d+") or "")
  if not n then return nil end
  if up:find("L") then n = -math.abs(n) elseif up:find("R") then n = math.abs(n) end
  return math.max(-1, math.min(1, n / 100))
end
local pan_pair_half = {}   -- a concentric pan knob being typed into: "inner" or "outer"

-- REAPER's pan modes (I_PANMODE), as its own pan right-click names them:
-- -1 the project's default, 0 the 3.x balance, 3 stereo balance / mono
-- pan, 5 stereo pan (pan and width), 6 dual pan (left and right).
CH.PAN_MODES = { { -1, "Project default" }, { 3, "Stereo balance" }, { 5, "Stereo pan" }, { 6, "Dual pan" } }
local PAN_NAME = { [0] = "Balance (3.x)", [3] = "Stereo balance", [5] = "Stereo pan", [6] = "Dual pan" }
-- The track's pan mode as set (-1 the project's) and as it works: the
-- project's default resolved (GetTrackUIPan), else stereo balance.
function CH.pan_mode(track)
  local set_to = math.floor(CH.read(track, "I_PANMODE", -1) + 0.5)
  local eff = set_to
  if eff < 0 and reaper.GetTrackUIPan then
    local ok, _, _, m = reaper.GetTrackUIPan(track)
    if ok and m and m >= 0 then eff = math.floor(m + 0.5) end
  end
  if eff < 0 then eff = 3 end
  return set_to, eff
end
CH.pan_name = function(m) return PAN_NAME[m] or "Stereo balance" end

-- A pan value as REAPER writes it: 24R, 100L, C
function CH.pan_text(p)
  if math.abs(p) < 0.005 then return "C" end
  return ("%d%s"):format(math.floor(math.abs(p) * 100 + 0.5), p < 0 and "L" or "R")
end
-- Width, -100 % to 100 %
function CH.width_text(v) return ("%d%%"):format(math.floor(v * 100 + (v < 0 and -0.5 or 0.5))) end
function CH.typed_width(text)
  local n = tonumber((U.trim(text or "")):match("[%+%-]?%d*%.?%d+") or "")
  return n and math.max(-1, math.min(1, n / 100)) or nil
end

-- The pan knob's right-click: the track's pan mode, the lanes that mode
-- has, and the knobs back to where they start
function CH.pan_menu(ctx, track)
  local set_to, eff = CH.pan_mode(track)
  ImGui.TextDisabled(ctx, "Pan mode")
  for _, e in ipairs(CH.PAN_MODES) do
    local hint = (e[1] == -1 and set_to == -1) and CH.pan_name(eff) or nil
    if ImGui.MenuItem(ctx, e[2], hint, set_to == e[1]) and set_to ~= e[1] then
      set(track, "I_PANMODE", e[1])
      reaper.Undo_OnStateChange("ChannelView: pan mode " .. e[2]:lower())
    end
  end
  if set_to == 0 then ImGui.MenuItem(ctx, PAN_NAME[0], nil, true, false) end
  ImGui.Separator(ctx)
  -- (in Dual pan REAPER's pan envelope is the left channel's, its width
  -- envelope the right's)
  if eff == 6 then
    CH.lane_item(ctx, track, "Pan", "Left pan")
    CH.lane_item(ctx, track, "Width", "Right pan")
  else
    CH.lane_item(ctx, track, "Pan")
    if eff == 5 then CH.lane_item(ctx, track, "Width") end
  end
  if eff == 5 or eff == 6 then
    ImGui.Separator(ctx)
    local what = (eff == 5) and "Reset (centre, full width)" or "Reset (hard left and right)"
    if ImGui.MenuItem(ctx, what) then
      if eff == 5 then set(track, "D_PAN", 0); set(track, "D_WIDTH", 1)
      else set(track, "D_DUALPANL", -1); set(track, "D_DUALPANR", 1) end
      reaper.Undo_OnStateChange("ChannelView: reset pan")
    end
  end
end

-- Stereo pan's pan and width, or Dual pan's left and right: two knobs side
-- by side when the strip has room for them, else one concentric knob (the
-- pan, or left, in the middle; the width, or right, the ring). Same height
-- either way. Returns whether it was right-clicked.
local function pan_pair(ctx, track, idp, x, y, w, eff)
  local dual = eff == 6
  local k1, k2 = dual and "D_DUALPANL" or "D_PAN", dual and "D_DUALPANR" or "D_WIDTH"
  local n1, n2 = dual and "Left" or "Pan", dual and "Right" or "Width"
  local d1, d2 = dual and -1 or 0, 1
  local a, b = get(track, k1, d1), get(track, k2, d2)
  local ta = CH.pan_text(a)
  local tb = dual and CH.pan_text(b) or CH.width_text(b)
  local function typed2(t) if dual then return CH.typed_pan(t) end return CH.typed_width(t) end
  local right = false
  if w >= 2 * C.CELL_W + C.S(8) then
    local x0 = x + (w - 2 * C.CELL_W) * 0.5
    local function one(i, key, name, v, txt, dflt, parse)
      ImGui.SetCursorScreenPos(ctx, x0 + (i - 1) * C.CELL_W, y)
      local id = idp .. "pan" .. i
      local ch, nv, act = W.knob(ctx, id, name, (v + 1) * 0.5, txt, { bipolar = true, tooltip = name .. ": " .. txt })
      if act and act.double_click then nv, ch = (dflt + 1) * 0.5, true end
      if ch then set(track, key, nv * 2 - 1) end
      if act and act.right_click then right = true end
      local t = W.type_box(ctx, id, act and act.type_in, name, txt)
      local tv = t and parse(t)
      if tv then set(track, key, tv) end
    end
    one(1, k1, n1, a, ta, d1, CH.typed_pan)
    one(2, k2, n2, b, tb, d2, typed2)
  else
    ImGui.SetCursorScreenPos(ctx, x + (w - C.CELL_W) * 0.5, y)
    local id = idp .. "pan"
    local c1, v1, c2, v2, act = W.dual_knob(ctx, id, n1 .. " / " .. n2, (b + 1) * 0.5, (a + 1) * 0.5,
      { shown1 = tb, shown2 = ta, bip1 = true, bip2 = true, tip = n1 .. ": " .. ta .. "\n" .. n2 .. ": " .. tb
        .. "\nDrag the middle: " .. n1:lower() .. "; the ring: " .. n2:lower() })
    if act.double_click == "inner" then v2, c2 = (d1 + 1) * 0.5, true
    elseif act.double_click == "outer" then v1, c1 = (d2 + 1) * 0.5, true end
    if c2 then set(track, k1, v2 * 2 - 1) end
    if c1 then set(track, k2, v1 * 2 - 1) end
    if act.right_click then right = true end
    local half = act.type_in
    if half then pan_pair_half[id] = half end
    local inner = pan_pair_half[id] == "inner"
    local t = W.type_box(ctx, id, act.type_in and true or false, inner and n1 or n2, inner and ta or tb)
    if t then
      if inner then local tv = CH.typed_pan(t); if tv then set(track, k1, tv) end
      else local tv = typed2(t); if tv then set(track, k2, tv) end end
    end
  end
  return right
end

local function type_vol(ctx, id, act, track, vol)
  local t = W.type_box(ctx, id, act and act.type_in, "Volume (dB)", U.db_text(vol))
  local v = t and CH.typed_vol(t)
  if v then set(track, "D_VOL", v) end
end

-- The master track has no record arm, no input monitoring and no phase
-- invert. Drawing dead buttons for them would be worse than leaving the
-- space to the fader and meter, which the master does have.
function CH.is_master(track)
  return track ~= nil and track == reaper.GetMasterTrack(0)
end

-- Record monitoring cycles off / input / auto. Short labels because the
-- button is 40-odd pixels wide, and a distinct colour for auto: it is a
-- different behaviour from plain input monitoring, not a stronger one, so
-- showing it in the same green would read as "on, but more".
local MON = {
  [0] = { text = "\u{2013}",  col = nil,              tip = "Monitoring off" },
  [1] = { text = "IN", col = "mon_on",        tip = "Monitoring input" },
  [2] = { text = "AU", col = "mon_auto",      tip = "Monitoring auto (input while stopped)" },
}

-- ---------------------------------------------------------------------
-- automation mode
-- ---------------------------------------------------------------------

-- REAPER's I_AUTOMODE. Short labels because the button is thirty pixels
-- wide, and a colour each because which mode you are in is the sort of
-- thing you want to notice from across the room rather than read.
CH.AUTO = {
  [0] = { text = "TRIM", col = "auto_trim",    name = "Trim / Read off" },
  [1] = { text = "READ", col = "auto_read",    name = "Read" },
  [2] = { text = "TCH",  col = "auto_touch",   name = "Touch" },
  [3] = { text = "WRT",  col = "auto_write",   name = "Write" },
  [4] = { text = "LTCH", col = "auto_latch",   name = "Latch" },
  [5] = { text = "LPRV", col = "auto_preview", name = "Latch preview" },
}

function CH.auto_mode(track)
  local m = math.floor(CH.read(track, "I_AUTOMODE", 0))
  if CH.AUTO[m] then return m end
  return 0
end

-- The button, plus the popup it opens. A five-way setting is a menu, not
-- a cycle: clicking four times to get back to where you were is how you
-- end up recording automation you did not mean to.
function CH.auto_button(ctx, x, y, w, h, track, idp)
  if not track then return end
  local m = CH.auto_mode(track)
  local e = CH.AUTO[m]
  local id = idp .. "auto"

  if W.state_button(ctx, id, e.text, x, y, w, h, m ~= 0, C.COL[e.col],
      "Automation: " .. e.name) then
    ImGui.OpenPopup(ctx, id .. "pop")
  end

  if ImGui.BeginPopup(ctx, id .. "pop") then
    for i = 0, 5 do
      local o = CH.AUTO[i]
      if ImGui.MenuItem(ctx, o.name, nil, i == m) then
        G.set(track, "I_AUTOMODE", i)
      end
    end
    ImGui.EndPopup(ctx)
  end
end

-- The input FX button: lit when the track has input FX (the bypass
-- colour when every one of them is bypassed), and opening that chain.
-- On the master it's the monitoring FX chain instead.
-- The input FX button's width: "IN" fits the usual one; the master's
-- "MON" (its monitoring FX) needs a few pixels more.
function CH.infx_width(track)
  return C.INFX_BTN_W + (CH.is_master(track) and C.S(8) or 0)
end

-- A header's input FX and automation buttons, each as wide as its words
-- in the current font (at least its usual width), and both narrowed alike
-- when `room` (what's left beside the collapse button) can't take them
-- with their gaps: they never go. Returns iw, aw.
function CH.header_widths(ctx, track, room)
  local pad = C.S(10)
  local iw = math.max(CH.infx_width(track), ImGui.CalcTextSize(ctx, CH.is_master(track) and "MON" or "IN") + pad)
  local aw = C.AUTO_BTN_W
  for _, e in pairs(CH.AUTO) do aw = math.max(aw, ImGui.CalcTextSize(ctx, e.text) + pad) end
  local gap = C.S(3)
  if room and room < iw + aw + C.S(10) then
    local k = math.max(0.3, math.min(1, (room - gap) / (iw + aw)))
    iw, aw = math.floor(iw * k), math.floor(aw * k)
  end
  return iw, aw
end

function CH.infx_button(ctx, x, y, w, h, track, idp)
  if not track then return end
  local master = CH.is_master(track)
  local n, any_on = IN.fx_state(track)
  local label = master and "MON" or "IN"
  local noun  = master and "monitoring FX" or "input FX"
  local tip = ((n > 0) and ((master and "Monitoring FX: " or "Input FX: ") .. n
                             .. (any_on and "" or " (all bypassed)"))
                        or ((master and "Monitoring FX" or "Input FX") .. ": none"))

  local id = idp .. "infx"
  if W.state_button(ctx, id, label, x, y, w, h, n > 0,
      any_on and C.COL.accent or C.COL.bypass_on, tip) then
    ImGui.OpenPopup(ctx, id .. "pop")
  end

  -- The same menu a plugin panel's add tile opens -- Search, Recent,
  -- Folders, Categories, Developers -- adding to the input chain instead,
  -- above the plugins already there.
  if ImGui.BeginPopup(ctx, id .. "pop") then
    ImGui.TextDisabled(ctx, master and "Monitoring FX" or "Input FX")
    ImGui.Separator(ctx)
    for i = 0, n - 1 do
      local addr = 0x1000000 + i
      local _, nm = reaper.TrackFX_GetFXName(track, addr, "")
      local on = reaper.TrackFX_GetEnabled(track, addr)
      if ImGui.BeginMenu(ctx, U.clean_fx_name(nm or "?") .. (on and "" or "  (bypassed)")
                              .. "##infx" .. i) then
        if ImGui.MenuItem(ctx, "Open the plugin's window") then
          reaper.TrackFX_Show(track, addr, 3)
        end
        if ImGui.MenuItem(ctx, "Bypass", nil, not on) then
          reaper.TrackFX_SetEnabled(track, addr, not on)
        end
        if ImGui.MenuItem(ctx, "Remove") then
          reaper.Undo_BeginBlock()
          reaper.TrackFX_Delete(track, addr)
          reaper.Undo_EndBlock("ChannelView: remove " .. noun, -1)
        end
        ImGui.EndMenu(ctx)
      end
    end
    if n > 0 then ImGui.Separator(ctx) end
    if ImGui.BeginMenu(ctx, "Add " .. noun) then
      B.menu_items(ctx, track, { track = track, input = true })
      ImGui.EndMenu(ctx)
    end
    -- Only with something in it: an empty chain opens as REAPER's Add FX
    -- browser, which is the item above.
    if ImGui.MenuItem(ctx, "Show the " .. noun .. " chain", nil, false, n > 0) then
      IN.open_fx(track)
    end
    ImGui.EndPopup(ctx)
  end
end

-- `opts`, all optional, is for the same header drawn somewhere else --
-- ChannelView TCP's flyout -- so both get every button this header
-- grows, rather than one of them drifting behind:
--   title     text instead of "Channel" (cut to fit rather than dropped)
--   base      the cap's colour (a track colour) instead of header_bg
--   ink       text and icon colour on that cap
--   on_close  the right-hand button closes rather than collapses
--   idp       widget-id prefix, default "ch"
function CH.draw_header(ctx, dl, x, y, w, track, opts)
  opts = opts or {}
  local idp = opts.idp or "ch"
  if opts.base then
    ImGui.DrawList_AddRectFilled(dl, x, y, x + w, y + C.HEADER_H, opts.base,
      C.STRIP_ROUND, ImGui.DrawFlags_RoundCornersTop)
  else
    ImGui.DrawList_AddRectFilled(dl, x, y, x + w, y + C.HEADER_H, C.COL.header_bg, C.PANEL_RR,
      ImGui.DrawFlags_RoundCornersTop)
  end
  ImGui.DrawList_AddLine(dl, x, y + C.HEADER_H, x + w, y + C.HEADER_H,
    C.COL.panel_border, 1.0)

  local btn = C.ICON_SIZE
  local p3 = C.S(3)
  ImGui.SetCursorScreenPos(ctx, x + w - btn - p3, y + p3)
  if opts.on_close then
    if W.icon_button(ctx, idp .. "close", "collapse", btn, false,
        "Close", nil, opts.ink) then
      opts.on_close()
    end
  elseif W.icon_button(ctx, idp .. "col", "collapse", btn, false, "Collapse channel strip", nil, opts.ink) then
    St.toggle_collapsed(KEY)
  end

  -- Automation mode, left of the collapse control -- the same corner the
  -- Sends panel keeps its routing button in. Input FX sits at the left
  -- edge, where the signal enters the strip. The "Channel" title takes
  -- whatever room is left between them, and gives way when there isn't
  -- enough, as a mixer strip's header does.
  local iw, aw = CH.header_widths(ctx, track, w - btn - C.S(8) - p3)
  local bh = C.HEADER_H - C.S(6)
  CH.auto_button(ctx, x + w - btn - aw - C.S(8), y + p3, aw, bh, track, idp)
  local left_of_buttons = x + w - btn - aw - C.S(8)
  CH.infx_button(ctx, x + p3, y + p3, iw, bh, track, idp)
  local title_x = x + p3 + iw + C.S(5)

  local title = opts.title or "Channel"
  local room  = left_of_buttons - 4 - title_x
  local tw, th = ImGui.CalcTextSize(ctx, title)
  if opts.title then
    -- A track name is worth a truncated version; "Channel" isn't.
    while tw > room and #title > 1 do
      title = title:sub(1, #title - 1)
      tw = ImGui.CalcTextSize(ctx, title .. ".")
      if tw <= room then title = title .. "." break end
    end
  end
  if tw <= room then
    ImGui.DrawList_AddText(dl, title_x, y + (C.HEADER_H - th) * 0.5,
      opts.ink or C.COL.header_text, title)
  end
  if opts.title then
    W.tip(ctx, idp .. "title", opts.title,
      ImGui.IsWindowHovered(ctx) and ImGui.IsMouseHoveringRect(ctx, title_x, y, left_of_buttons, y + C.HEADER_H), false)
  end
end

-- The master's mono switch, in record arm's place: REAPER's own action,
-- so its state is the action's toggle state. (The master has no record
-- arm, and summing to mono is the check you reach for there.)
local MONO_ACTION = "Master track: Toggle stereo/mono (L+R)"
function CH.master_mono()
  local id = AC.find(MONO_ACTION, 40917)
  return id and reaper.GetToggleCommandState(id) == 1 or false
end
function CH.toggle_master_mono()
  local id = AC.find(MONO_ACTION, 40917)
  if id then reaper.Main_OnCommand(id, 0) end
end
-- An open circle on red while the master is mono, two linked circles on
-- the plain button while it's stereo.
local function mono_button(ctx, id, label, x, y, w, h)
  local on = CH.master_mono()
  local hit, dbl = W.state_icon(ctx, id, on and "mono" or "stereo", x, y, w, h, on, C.COL.rec_on,
    on and "Master in mono\nClick: stereo" or "Master in stereo\nClick: mono")
  if hit or dbl then CH.toggle_master_mono() end
end

-- Pan on a collapsed strip: a slim bar with a mark at the pan position and
-- the fill from centre to it, and the value under it when values under
-- controls are on -- the pair centred in the space between the strip's cap
-- and its meter (`y0` to `y1`), all of which takes the drag. Drag sideways
-- (or up and down, like the knob), Shift for fine, wheel, double-click for
-- centre. Ganged like the knob.
local function mini_pan(ctx, dl, idp, x, y0, y1, w, track)
  local pan = get(track, "D_PAN")
  W.push_small(ctx)
  local _, th = ImGui.CalcTextSize(ctx, "0")
  W.pop_small(ctx)
  local text_h = C.SHOW_VALUES and (th + 2) or 0
  local fy  = (y0 + y1) * 0.5 - text_h * 0.5
  local x0, x1 = x + 4, x + w - 4
  local mid = (x0 + x1) * 0.5

  ImGui.SetCursorScreenPos(ctx, x + 1, y0)
  ImGui.InvisibleButton(ctx, idp .. "mpan", w - 2, math.max(8, y1 - y0))
  local hovered, active = ImGui.IsItemHovered(ctx), ImGui.IsItemActive(ctx)
  local nv = nil
  if active and ImGui.IsMouseDown(ctx, ImGui.MouseButton_Left) then
    local dx, dy = ImGui.GetMouseDelta(ctx)
    if dx ~= 0 or dy ~= 0 then
      local sens = 0.012
      if (ImGui.GetKeyMods(ctx) & ImGui.Mod_Shift) ~= 0 then sens = sens * C.FINE_MULT end
      nv = pan + (dx - dy) * sens
    end
    ImGui.SetMouseCursor(ctx, ImGui.MouseCursor_ResizeEW)
  elseif hovered then
    local wheel = W.control_wheel(ctx)
    if wheel ~= 0 then nv = pan + wheel * 0.02; W.take_wheel() end
  end
  local txt = (math.abs(pan) < 0.005) and "C"
    or string.format("%d%s", math.floor(math.abs(pan) * 100 + 0.5), pan < 0 and "L" or "R")
  if hovered and ImGui.IsMouseDoubleClicked(ctx, ImGui.MouseButton_Left) then
    set(track, "D_PAN", 0)
  elseif nv then
    G.pan(track, math.max(-1, math.min(1, nv)))
  end

  local px = mid + (x1 - mid) * pan
  ImGui.DrawList_AddRectFilled(dl, x0, fy - 2, x1, fy + 2, C.COL.knob_track, 2.0)
  ImGui.DrawList_AddRectFilled(dl, math.min(mid, px), fy - 2, math.max(mid, px), fy + 2,
    C.COL.knob_fill_bi, 2.0)
  ImGui.DrawList_AddLine(dl, mid, fy - 4, mid, fy + 4, C.COL.knob_ring, 1.0)
  ImGui.DrawList_AddCircleFilled(dl, px, fy, (hovered or active) and 4 or 3.5,
    C.COL.knob_pointer, 12)
  if C.SHOW_VALUES then
    W.push_small(ctx)
    local tw = ImGui.CalcTextSize(ctx, txt)
    ImGui.DrawList_AddText(dl, mid - tw * 0.5, fy + 6, C.COL.value, txt)
    W.pop_small(ctx)
  end
  W.tip(ctx, idp .. "mpan", "Pan " .. txt, hovered, active)
end

-- The collapsed bar, for the pinned Channel panel AND for a collapsed
-- mixer strip -- the same argument as CH.draw_body below. `idp` is the
-- widget-id prefix and the peak-hold key, `ckey` the collapse-state key
-- to toggle. The defaults are the pinned panel's.
-- `expand`, when given, replaces what the expand button does: a strip
-- that's collapsed because its folder is collapsed expands the folder,
-- not just itself. `expand_tip` is that button's tooltip. `ink`, when
-- given, colours the expand button for a track-coloured cap behind it.
-- Returns true when the ghost fader was CLICKED rather than dragged --
-- see W.fader. The caller uses it to select the track, since on a
-- collapsed strip the fader lies right over the meter and a plain click
-- there means "this one", not "move the level".
function CH.draw_collapsed(ctx, dl, x, y, w, h, track, idp, ckey, expand, expand_tip, ink)
  idp   = idp or "ch"
  ckey  = ckey or KEY
  local bare = false
  local btn = C.ICON_SIZE
  local cx  = x + w * 0.5

  ImGui.SetCursorScreenPos(ctx, cx - btn * 0.5, y + 4)
  -- ink is optional: without it the button takes the palette's colours.
  if W.icon_button(ctx, idp .. "exp", "expand", btn, false,
      expand_tip or "Expand strip", nil, ink or nil) then
    if expand then expand() else CH.set_collapse(ckey, track, false) end
  end

  -- Laid out on the full strip's own lines (CH.geometry): the meter and
  -- fader over exactly the span the full strip's fader covers, the level
  -- where the full strip prints it, and the buttons in the full strip's
  -- button rows -- mute, solo and record arm stacked, one to a row -- so a
  -- row of mixed strips has one line of faders and one of buttons.
  local master = CH.is_master(track)
  local g = CH.geometry(y + C.HEADER_H, h - C.HEADER_H, master)
  -- pan, in the space between the cap and the meter
  mini_pan(ctx, dl, idp, x, y + C.HEADER_H + C.S(2), g.top - 4, w, track)
  local muted = get(track, "B_MUTE") > 0.5
  local solo  = get(track, "I_SOLO") > 0.5
  local rec   = get(track, "I_RECARM") > 0.5
  local bw, bh = w - 8, g.bh
  local function row(k) return g.btm + k * (bh + g.bgap) end
  -- Swipeable here too: a row of collapsed strips is exactly where you
  -- want to drag mute across six tracks at once.
  local hit, _, want = W.state_button(ctx, idp .. "cM", "M",
    x + 4, row(0), bw, bh, muted, C.COL.mute_on, "Mute", "mute")
  if want ~= nil then set(track, "B_MUTE", want and 1 or 0)
  elseif hit then set(track, "B_MUTE", muted and 0 or 1) end

  hit, _, want = W.state_button(ctx, idp .. "cS", "S",
    x + 4, row(1), bw, bh, solo, C.COL.solo_on, "Solo", "solo")
  if want ~= nil then set(track, "I_SOLO", want and 1 or 0)
  elseif hit then set(track, "I_SOLO", solo and 0 or 1) end

  if not master then
    hit, _, want = W.state_icon(ctx, idp .. "cR", "record", x + 4, row(2), bw, bh,
      rec, C.COL.rec_on, rec and "Record armed" or "Record arm", "rec")
    if want ~= nil then set(track, "I_RECARM", want and 1 or 0)
    elseif hit then set(track, "I_RECARM", rec and 0 or 1) end
  else
    mono_button(ctx, idp .. "cMo", "MO", x + 4, row(2), bw, bh)
  end

  -- Read out here, not inside: the readout below prints it whether or
  -- not there was room for a meter.
  local vol = get(track, "D_VOL", 1)

  -- the meter is what makes a collapsed strip worth keeping visible
  local top, mh = g.top, g.fh
  if mh > 30 then
    local now = reaper.time_precise()
    -- One hold per channel: a single figure drawn across both bars is
    -- the louder channel's peak laid over the quieter one's meter.
    local nch = W.meter_channels(track)
    local lv, pk = {}, {}
    for i = 1, nch do
      lv[i] = U.val2db(U.track_peak(track, i - 1))
      pk[i] = W.level_peak(idp .. "c" .. i, lv[i], now)
    end
    -- No ladder and no RMS on the collapsed bar: at this width the
    -- numbers wouldn't fit and the strip would stop being a glance.
    W.level_meter(ctx, dl, x + 4, top, w - 8, mh, lv, pk, false, nil)

    -- The fader, as a translucent cap laid straight over the meter.
    -- There is no room for a fader beside a meter at this width, and
    -- collapsing the strip shouldn't mean going somewhere else to pull
    -- the level down -- which is usually exactly why you looked.
    -- (its colour only: a see-through cap has no room for a style)
    local lk = look_for(track, reaper.time_precise())
    local fch, fnv, fact = W.fader(ctx, idp .. "fmini", x + 4, top, w - 8, mh,
      U.vol_to_fader(vol), "Volume   " .. U.db_text(vol) .. " dB",
      U.UNITY_POS, true, lk and lk.cap and { cap = lk.cap } or nil)
    if fact and fact.right_click then ImGui.OpenPopup(ctx, idp .. "fmenu") end
    fader_menu(ctx, track, idp .. "fmenu")
    local dblv = fact and fact.double_click
    if fact and fact.click then bare = true end
    if dblv then fnv, fch = U.UNITY_POS, true end
    -- Double-click means unity, and unity is a place, not a distance:
    -- it sets the whole gang TO it. A drag moves them BY the ratio.
    if fch then
      local nv = U.fader_to_vol(fnv)
      if dblv then set(track, "D_VOL", nv) else G.vol(track, nv) end
    end
  end

  -- Under the meter, on the full strip's readout line: the level in dB.
  -- Not the track's name -- that's in the track list directly below, and
  -- at thirty pixels wide it wouldn't run down the bar legibly anyway.
  local vt = U.db_text(vol)
  local tw = ImGui.CalcTextSize(ctx, vt)
  ImGui.DrawList_AddText(dl, cx - tw * 0.5, top + math.max(mh, 0) + 2, C.COL.value, vt)

  return bare
end

-- `idp` is the widget-id prefix and the peak-hold key. It defaults to
-- "ch" -- the one pinned Channel panel -- and the mixer passes a
-- per-track one, because this same body is every strip in mixer view.
-- Without it every strip would share one set of ImGui ids and one peak
-- store, and they would all fight over both.
-- Height of the record-input row across the top of the body: as tall as
-- its words need, and following Overall size.
function CH.input_row_h() return math.max(C.S(18), C.text_px() + C.S(6)) end

-- Where a strip's body puts things, from the body's top `y` and height
-- `h`: the fader's top and height, and the first button row. The full
-- body and the collapsed strip both lay out from this, so the two line up
-- side by side in the mixer. Three button rows (mute|solo, phase|monitor,
-- record arm), the master's too -- mute|solo, nothing, mono -- so its fader
-- and buttons sit on the same lines as every other strip's.
-- A button as tall as its words need (and at least its usual 15 px), all
-- following Overall size.
function CH.geometry(y, h, master)
  local pad, bh, bgap = C.S(5), math.max(C.S(15), C.text_px() + C.S(3)), C.S(3)
  local rows = 3
  local btm  = y + h - pad - rows * bh - (rows - 1) * bgap
  local top  = y + CH.input_row_h() + C.CELL_H + C.S(2)
  -- Two lines of readout under the meter (peak, then RMS) and one under
  -- the fader; the taller of the two sets how much the fader gives up.
  -- The extra few pixels keep the RMS figure off the Solo button.
  local fh   = btm - top - 2 * C.text_px() - C.S(10)
  return { top = top, fh = fh, btm = btm, bh = bh, bgap = bgap, rows = rows }
end

-- A fader shorter than this is too short to use: the volume is a knob
-- instead, its level meter a ring round it.
CH.FADER_MIN = 90       -- (at 100 %: C.S of it)

-- The volume as a knob between `top` and `bottom`, centred across x..x+w,
-- with each channel's level (and its peak hold) on a ring round the dial:
-- the fader panel when it's too short for a fader.
local function volume_knob(ctx, dl, x, w, top, bottom, track, idp, vol, now)
  local small = (bottom - top) < C.CELL_H
  local sz = C.SIZES[small and "small" or "medium"]
  local cw = C.CELL_W * sz.w / 2
  local ch = C.CELL_H * sz.h / 2
  ImGui.SetCursorScreenPos(ctx, x + (w - cw) * 0.5, top + math.max(0, (bottom - top - ch) * 0.5))
  local vt = U.db_text(vol)
  -- its name drawn here, over the ring (the knob's own would sit under it)
  local kch, knv, kact = W.knob(ctx, idp .. "volk", "", U.vol_to_fader(vol), vt,
    { size = small and "small" or nil, tooltip = "Volume   " .. vt .. " dB" })
  if kact and kact.right_click then ImGui.OpenPopup(ctx, idp .. "fmenu") end
  fader_menu(ctx, track, idp .. "fmenu")
  local dbl = kact and kact.double_click
  if dbl then knv, kch = U.UNITY_POS, true end
  if kch then
    local nv = U.fader_to_vol(knv)
    if dbl then set(track, "D_VOL", nv) else G.vol(track, nv) end
  end
  type_vol(ctx, idp .. "volk", kact, track, vol)
  local k = W.last_knob
  if not k then return end
  -- the ring: one arc a channel (left inside, right outside), over the
  -- knob's own sweep, lit to the level, a tick at the peak hold
  local nch = math.min(2, W.meter_channels(track))
  local a0, a1 = math.pi * 0.75, math.pi * 2.25
  local tip = {}
  for i = 1, nch do
    local key = idp .. "c" .. i
    local lv = U.val2db(U.track_peak(track, i - 1))
    local hold = W.level_peak(key, lv, now)
    local rms = W.level_rms(key, lv, now)
    local rh = W.level_peak(key .. "#r", rms, now)
    local r = k.r + 3 + (i - 1) * 3.5
    ImGui.DrawList_PathClear(dl)
    ImGui.DrawList_PathArcTo(dl, k.cx, k.cy, r, a0, a1, 32)
    ImGui.DrawList_PathStroke(dl, C.COL.knob_track, 0, 2.5)
    local f = W.level_frac(lv)
    if f > 0 then
      ImGui.DrawList_PathClear(dl)
      ImGui.DrawList_PathArcTo(dl, k.cx, k.cy, r, a0, a0 + (a1 - a0) * f, math.max(4, math.floor(32 * f)))
      ImGui.DrawList_PathStroke(dl, W.level_bar_colour(lv), 0, 2.5)
    end
    local hf = W.level_frac(hold)
    if hf > 0 then
      local a = a0 + (a1 - a0) * hf
      ImGui.DrawList_AddLine(dl, k.cx + math.cos(a) * (r - 1.5), k.cy + math.sin(a) * (r - 1.5),
        k.cx + math.cos(a) * (r + 1.5), k.cy + math.sin(a) * (r + 1.5), W.level_colour(hold, C.COL.header_text), 1.5)
    end
    tip[i] = ("%speak %s   RMS %s   now %s"):format((nch > 1) and ((i == 1) and "L  " or "R  ") or "",
      U.db_str(hold), U.db_str(rh), U.db_str(lv))
  end
  local reach = k.r + 3 + (nch - 1) * 3.5 + 2
  local lab = "Volume"
  if small then W.push_small(ctx) end
  local lw, lh = ImGui.CalcTextSize(ctx, lab)
  ImGui.DrawList_AddText(dl, k.cx - lw * 0.5, math.max(top, k.cy - reach - lh - 1), C.COL.label, lab)
  if small then W.pop_small(ctx) end
  local over = ImGui.IsWindowHovered(ctx)
    and ImGui.IsMouseHoveringRect(ctx, k.cx - reach, k.cy - reach, k.cx + reach, k.cy + reach)
    and not ImGui.IsMouseHoveringRect(ctx, k.cx - k.r, k.cy - k.r, k.cx + k.r, k.cy + k.r)
  W.tip(ctx, idp .. "ringtip", table.concat(tip, "\n"), over, false)
end

function CH.draw_body(ctx, dl, x, y, w, h, track, idp)
  idp = idp or "ch"
  local pad = C.S(5)
  local now = reaper.time_precise()
  local irh = CH.input_row_h()

  -- The record input, as a dropdown across the top. The master has no
  -- input, but keeps the row empty so its fader lines up with the rest.
  if not CH.is_master(track) then
    local pid = idp .. "inpop"
    if W.dropdown(ctx, idp .. "inp", IN.text(track), x + pad, y + C.S(3),
        w - pad * 2, irh - C.S(4), "Record input: " .. IN.text(track)) then
      ImGui.OpenPopup(ctx, pid)
    end
    if ImGui.BeginPopup(ctx, pid) then
      IN.menu(ctx, track)
      ImGui.EndPopup(ctx)
    end
  end
  y = y + irh
  h = h - irh

  -- (the body's lines: buttons along the bottom, the fader above them;
  -- y and h are below the input row now, the geometry counts from the
  -- body's own top -- CH.geometry)
  local master = CH.is_master(track)
  local geo = CH.geometry(y - irh, h + irh, master)
  -- Too short for a fader, and too short for the volume knob under the
  -- pan: the pan goes and the volume takes its place.
  local no_pan = geo.fh < C.S(CH.FADER_MIN) and (geo.btm - C.S(4) - geo.top) < C.CELL_H

  -- pan across the top
  local _, pan_eff = CH.pan_mode(track)
  if not no_pan and (pan_eff == 5 or pan_eff == 6) then
    if pan_pair(ctx, track, idp, x, y + C.S(2), w, pan_eff) then ImGui.OpenPopup(ctx, idp .. "panmenu") end
    if ImGui.BeginPopup(ctx, idp .. "panmenu") then
      CH.pan_menu(ctx, track)
      ImGui.EndPopup(ctx)
    end
  elseif not no_pan then
    local pan = get(track, "D_PAN")
    local pan_txt = CH.pan_text(pan)
    ImGui.SetCursorScreenPos(ctx, x + (w - C.CELL_W) * 0.5, y + C.S(2))
    local pch, pnv, pact = W.knob(ctx, idp .. "pan", "Pan", (pan + 1) * 0.5, pan_txt,
      { bipolar = true, tooltip = pan_txt })
    local dblp = pact and pact.double_click
    if dblp then pnv, pch = 0.5, true end
    if pact and pact.right_click then ImGui.OpenPopup(ctx, idp .. "panmenu") end
    if ImGui.BeginPopup(ctx, idp .. "panmenu") then
      CH.pan_menu(ctx, track)
      ImGui.EndPopup(ctx)
    end
    -- Centre is a place; a drag is a distance. See the fader below.
    if pch then
      local np = pnv * 2 - 1
      if dblp then set(track, "D_PAN", np) else G.pan(track, np) end
    end
    local tp = W.type_box(ctx, idp .. "pan", pact and pact.type_in, "Pan (30L, 15R, C)", pan_txt)
    local tpv = tp and CH.typed_pan(tp)
    if tpv then set(track, "D_PAN", tpv) end
  end

  -- buttons along the bottom, two columns, three rows (see CH.geometry)
  local bh, bgap = geo.bh, geo.bgap
  local bw = (w - pad * 2 - bgap) * 0.5
  local btm = geo.btm

  local muted = get(track, "B_MUTE") > 0.5
  local solo  = get(track, "I_SOLO") > 0.5
  local rec   = get(track, "I_RECARM") > 0.5
  local mon   = math.floor(get(track, "I_RECMON")) % 3
  local phase = get(track, "B_PHASE") > 0.5

  local function cell(col, row)
    return x + pad + col * (bw + bgap), btm + row * (bh + bgap)
  end

  local full = w - pad * 2

  -- Mute, solo and record arm take a swipe: press one and drag along the
  -- row in mixer view and every one you cross follows the first. `want`
  -- carries the value the click or the swipe asks for.
  local bx, by = cell(0, 0)
  local hit, dbl, want = W.state_button(ctx, idp .. "bM", "M", bx, by, bw, bh,
    muted, C.COL.mute_on, "Mute", "mute")
  if dbl then set(track, "B_MUTE", 0)
  elseif want ~= nil then set(track, "B_MUTE", want and 1 or 0) end

  bx, by = cell(1, 0)
  hit, dbl, want = W.state_button(ctx, idp .. "bS", "S", bx, by, bw, bh,
    solo, C.COL.solo_on, "Solo", "solo")
  if dbl then set(track, "I_SOLO", 0)
  elseif want ~= nil then set(track, "I_SOLO", want and 1 or 0) end

  if not master then
    -- Phase and monitoring share the middle row; record arm gets a row of
    -- its own at full width, because it is the one you hit in a hurry and
    -- the one whose state you check from across the room.
    bx, by = cell(0, 1)
    -- No swipe on phase: it is not a thing you set across a row, and a
    -- stray drag flipping the polarity of six tracks is a bad afternoon.
    hit, dbl = W.state_button(ctx, idp .. "bP", "\u{00F8}", bx, by, bw, bh,
      phase, C.COL.warn, "Invert phase")
    if hit or dbl then set(track, "B_PHASE", (dbl or phase) and 0 or 1) end

    bx, by = cell(1, 1)
    -- Nor monitoring: three states have no "the same way as the first".
    local m = MON[mon]
    hit, dbl = W.state_button(ctx, idp .. "bI", m.text, bx, by, bw, bh, mon > 0,
      m.col and C.COL[m.col] or nil, m.tip .. "\nClick: cycle")
    if dbl then set(track, "I_RECMON", 0)
    elseif hit then set(track, "I_RECMON", (mon + 1) % 3) end

    bx, by = cell(0, 2)
    hit, dbl, want = W.state_icon(ctx, idp .. "bR", "record", bx, by, full, bh,
      rec, C.COL.rec_on, rec and "Record armed" or "Record arm", "rec")
    if dbl then set(track, "I_RECARM", 0)
    elseif want ~= nil then set(track, "I_RECARM", want and 1 or 0) end
  else
    -- The master: its middle row stays empty (it has no phase or input
    -- monitoring), and mono takes record arm's row.
    bx, by = cell(0, 2)
    mono_button(ctx, idp .. "bMo", "MONO", bx, by, full, bh)
  end

  -- Fader and meter take half the inner width each, so the pair reads as
  -- balanced rather than as a fader with something tacked on beside it.
  local vol   = get(track, "D_VOL", 1)   -- unity if the track has none
  local inner = w - pad * 2
  local half  = inner * 0.5
  -- the strip's width against the default: the meter scales with it, and
  -- the fader a little (its cap stays a cap -- the strip width)
  local k     = w / C.CHANNEL_W_DEFAULT
  local fw    = math.floor(C.FADER_W * math.max(0.75, math.min(1.35, k)) + 0.5)
  local top   = geo.top
  local fh    = geo.fh

  if fh < C.S(CH.FADER_MIN) then
    -- too short for a fader to be any use: a knob, the meter round it
    volume_knob(ctx, dl, x + pad, inner, no_pan and (y + C.S(2)) or top, btm - C.S(4), track, idp, vol, now)
  else
    local fx = x + pad + (half - fw) * 0.5
    local fch, fnv, fact = W.fader(ctx, idp .. "fader", fx, top, fw, fh,
      U.vol_to_fader(vol), "Volume   " .. U.db_text(vol) .. " dB",
      U.UNITY_POS, false, look_for(track, now))
    if fact and fact.right_click then ImGui.OpenPopup(ctx, idp .. "fmenu") end
    fader_menu(ctx, track, idp .. "fmenu")
    local dblv = fact and fact.double_click
    if dblv then fnv, fch = U.UNITY_POS, true end
    if fch then
      local nv = U.fader_to_vol(fnv)
      if dblv then set(track, "D_VOL", nv) else G.vol(track, nv) end
    end
    type_vol(ctx, idp .. "fader", fact, track, vol)

    -- the fader's own value, with the fader rather than lost among the
    -- buttons
    local vt = U.db_text(vol)
    local tw, th = ImGui.CalcTextSize(ctx, vt)
    ImGui.DrawList_AddText(dl, x + pad + (half - tw) * 0.5, top + fh + C.S(2),
      C.COL.value, vt)

    -- Everything the meter shows, per channel: the live level, the peak
    -- hold, the live RMS, and the RMS HELD.
    --
    -- The RMS figure holds exactly as the peak figure does. A number
    -- that changes sixty times a second is not a number anybody reads,
    -- and the strip beside the bar is already showing the live one -- a
    -- readout is for the value you want to catch and look at. Same hold
    -- and same fall as the peak, so the two figures under the meter
    -- behave the same way as each other.
    local nch = W.meter_channels(track)
    local lv, hold, rms_live, rms_hold = {}, {}, {}, {}
    for i = 1, nch do
      local key = idp .. "c" .. i
      lv[i]       = U.val2db(U.track_peak(track, i - 1))
      hold[i]     = W.level_peak(key, lv[i], now)
      rms_live[i] = W.level_rms(key, lv[i], now)
      rms_hold[i] = W.level_peak(key .. "#r", rms_live[i], now)
    end
    -- Centred in its half, the same way the fader's track is centred in
    -- the other one -- a meter flush to the panel edge beside a centred
    -- fader reads as a misalignment even though both are in their column.
    -- The track's total gain reduction, when anything on it reports or
    -- is measured: a slim bar to the meter's right, and the meter a little
    -- narrower to make room, the pair centred together.
    local grt, gre, grp = TP.track_total(track)
    local gside = grt and (C.GR_BAR_W + C.S(2)) or 0
    local mw = math.min(half - C.S(4) - gside, C.LEVEL_METER_W * math.min(k, 1.75))
    local mx = x + pad + half + (half - mw - gside) * 0.5
    W.level_meter(ctx, dl, mx, top, mw, fh, lv, hold, true, rms_live)
    if grt then
      local gx = mx + mw + 2
      local gpk, grange = W.gr_state(idp .. "#grt", grt, now, C.MAX_GR_DB)
      local est_db = 0
      for _, p in ipairs(grp) do if p.est then est_db = est_db + p.db end end
      W.gr_bar(dl, gx, top, C.GR_BAR_W, fh, grt, gpk, grange, est_db)
      local g_over = ImGui.IsWindowHovered(ctx)
                     and ImGui.IsMouseHoveringRect(ctx, gx - 1, top, gx + C.GR_BAR_W + C.S(1), top + fh)
      local lines = { ("Track gain reduction: %.1f dB (peak %.1f)"):format(grt, gpk) }
      local unzeroed = false
      for _, p in ipairs(grp) do
        local tag = ""
        if p.est then
          tag = "  est."
          if p.cal == 0 then tag, unzeroed = "  est., not zeroed", true end
        end
        lines[#lines + 1] = ("  %s  %.1f dB%s"):format(p.name, p.db, tag)
      end
      if gre then
        lines[#lines + 1] = "\nest. = measured by the probes"
        if unzeroed then
          lines[#lines + 1] = "not zeroed: stop playback a few seconds"
        end
      end
      W.tip(ctx, idp .. "grt", table.concat(lines, "\n"), g_over, false)
    end

    -- Hovering the meter reports what it is showing -- by RECTANGLE,
    -- not by an invisible button over it. A button here would be an
    -- item, and an item swallows the click that the strip's background
    -- needs in order to select the track. The meter reads out; it does
    -- not do anything, so it has no business being clickable.
    local m_over = ImGui.IsWindowHovered(ctx)
                   and ImGui.IsMouseHoveringRect(ctx, mx, top, mx + mw, top + fh)
    local tip = {}
    for i = 1, nch do
      tip[i] = ("%speak %s   RMS %s   now %s"):format(
        (nch > 1) and ((i == 1) and "L  " or "R  ") or "",
        U.db_str(hold[i]), U.db_str(rms_hold[i]), U.db_str(lv[i]))
    end
    W.tip(ctx, idp .. "meter", table.concat(tip, "\n"), m_over, false)

    -- Peak on the first line, RMS on the second, and ONE COLUMN PER
    -- CHANNEL, each centred under the bar it is about -- a stereo track
    -- has two levels, and a single combined figure wouldn't say which
    -- side it came from.
    --
    -- Shown in the smaller face, because two columns of "-12.3" don't fit
    -- a fifty-pixel column at the body size, and a readout is the one
    -- place where a smaller face costs nothing. The RMS figure carries no
    -- trailing "r": with two columns already in play, the colour and the
    -- position say enough, and the tooltip names them outright.
    W.push_small(ctx)
    local _, rh = ImGui.CalcTextSize(ctx, "0")
    local mbl = mx + 1.5                          -- the bars' own left
    local mbw = (mw - 3 - (nch - 1)) / nch        -- and their width
    -- A strip narrowed until the columns would run into each other shows
    -- ONE column instead -- the louder channel's figures, under the
    -- middle of the meter. The tooltip still has every channel.
    local show = nch
    if nch > 1 then
      local widest = 0
      for i = 1, nch do
        local pt = (hold[i] > C.METER_FLOOR) and U.db_str(hold[i]) or "-inf"
        local pw = ImGui.CalcTextSize(ctx, pt)
        widest = math.max(widest, pw)
        if rms_hold[i] > C.METER_FLOOR then
          local rw = ImGui.CalcTextSize(ctx, U.db_str(rms_hold[i]))
          widest = math.max(widest, rw)
        end
      end
      if widest + 2 > mbw + 1 then
        show = 1
        local hi, ri = -math.huge, -math.huge
        for i = 1, nch do hi = math.max(hi, hold[i]); ri = math.max(ri, rms_hold[i]) end
        hold, rms_hold = { hi }, { ri }
        mbw = mw - 3
      end
    end
    for i = 1, show do
      local ccx = mbl + (i - 1) * (mbw + 1) + mbw * 0.5
      local pt  = (hold[i] > C.METER_FLOOR) and U.db_str(hold[i]) or "-inf"
      local ptw = ImGui.CalcTextSize(ctx, pt)
      ImGui.DrawList_AddText(dl, ccx - ptw * 0.5, top + fh + 2,
        W.level_colour(hold[i], C.COL.header_dim), pt)

      if rms_hold[i] > C.METER_FLOOR then
        local rt  = U.db_str(rms_hold[i])
        local rtw = ImGui.CalcTextSize(ctx, rt)
        ImGui.DrawList_AddText(dl, ccx - rtw * 0.5, top + fh + 2 + rh,
          C.COL.level_rms, rt)
      end
    end
    W.pop_small(ctx)
  end
end

-- The panel itself: frame, then either the collapsed bar or header plus
-- body. Same shape as a plugin panel so the row reads as one thing, but
-- it is pinned outside the scrolling child rather than in it.
function CH.draw(ctx, track, avail_h)
  local collapsed = St.is_collapsed(KEY)
  local w = CH.width(collapsed)

  local cp_x, cp_y = ImGui.GetCursorPos(ctx)
  local ok = ImGui.BeginChild(ctx, "chanpanel", w, avail_h, 0,
    ImGui.WindowFlags_NoScrollbar | ImGui.WindowFlags_NoScrollWithMouse)
  if ok then
    local dl = ImGui.GetWindowDrawList(ctx)
    local x, y = ImGui.GetWindowPos(ctx)
    local ww, wh = ImGui.GetWindowSize(ctx)

    local bg = C.COL.panel_bg
    local tint = track and TO.track_tint(track) or 0
    local inks
    if tint > 0 then
      local tc = U.track_colour(track, 0xff)
      if tc then
        bg = U.tint_readable(bg, tc, tint)
        -- its slots, buttons and outlines in shades of it, as a mixer strip
        inks = W.push_tinted(bg, tc)
      end
    end
    ImGui.DrawList_AddRectFilled(dl, x, y, x + ww, y + wh, bg, C.PANEL_RR)
    ImGui.DrawList_AddRect(dl, x, y, x + ww, y + wh, C.COL.panel_border, C.PANEL_RR, 0, 1.0)

    -- The panel's own background is a double-click target: back to mixer
    -- view. Submitted BEFORE the controls so all of them sit on top of
    -- it -- a double-click on the fader is the fader's, and means unity.
    -- A right-click on it opens the track menu, the same as on a mixer
    -- strip or a name button.
    ImGui.SetCursorScreenPos(ctx, x, y)
    W.allow_overlap(ctx)
    ImGui.InvisibleButton(ctx, "chbg", ww, wh)
    if ImGui.IsItemHovered(ctx)
       and ImGui.IsMouseDoubleClicked(ctx, ImGui.MouseButton_Left) then
      CH.want_mixer = true
    end
    if track and ImGui.IsItemClicked(ctx, ImGui.MouseButton_Right) then
      TM.open_context(track)
    end

    -- With no track selected the frame and the collapse control stay --
    -- the row shouldn't change shape just because the selection went
    -- away, and the control that got you here has to still be there.
    if collapsed then
      if track then
        CH.draw_collapsed(ctx, dl, x, y, ww, wh, track)
      else
        local btn = C.ICON_SIZE
        ImGui.SetCursorScreenPos(ctx, x + (ww - btn) * 0.5, y + 4)
        if W.icon_button(ctx, "chexp", "expand", btn, false,
            "Expand channel strip") then
          St.toggle_collapsed(KEY)
        end
        W.vertical_text(ctx, dl, x + ww * 0.5, y + 4 + btn + 6,
          "CH", C.COL.header_dim, wh - btn - 16)
      end
    else
      -- the cap in the track's colour, as the TCP's flyout has it (the
      -- master, with none of its own, a cool grey)
      local cap = track and U.track_colour(track, 0xff)
      if track and not cap and track == reaper.GetMasterTrack(0) then cap = 0x8a90a0ff end
      CH.draw_header(ctx, dl, x, y, ww, track,
        cap and { base = cap, ink = U.contrast_text(cap) } or nil)
      if track then
        CH.draw_body(ctx, dl, x, y + C.HEADER_H, ww, wh - C.HEADER_H, track)
      end
    end
    W.pop_tinted(inks)
    ImGui.EndChild(ctx)
  else
    -- Culled: still occupy the space, or the parent's bounds
    -- never grow past it. See W.child_skipped.
    W.child_skipped(ctx, w, avail_h, cp_x, cp_y)
  end
  return w
end

return CH
