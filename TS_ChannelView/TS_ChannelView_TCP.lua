-- @noindex
-- Not a package of its own: installed by TS_ChannelView.lua's @provides.
--[[
  TS_ChannelView_TCP.lua -- a track control panel in ChannelView's image,
  docked beside the arrange view and lined up with it row for row.

  Dock it to the LEFT of the arrange view (a docker attached to the left
  of REAPER's main window is the natural home) and every row sits level
  with its track's lane: same top, same height, scrolling with it. The
  space above the first track -- beside the ruler and the marker and
  region lanes -- is a toolbar of REAPER actions.

  What a row is:
    * a strip of the track's colour down the left, indented per folder
      level the way REAPER's own panel does it
    * the name, and a horizontal peak meter under it
    * the track's icon on the right, when View > Track icons is on
    * small M / S / record chips, only while one of those is ON -- so a
      muted track still says so with the panel below closed

  What you can do to one:
    * click          select it (ctrl adds, shift takes the range) and
                     open its channel panel beside the TCP; click it
                     again to close the panel
    * double-click   rename
    * right-click    ChannelView's own track menu -- the same one, not a
                     copy: rename, colour, spacer, folders
    * drag           reorder (the selection moves with it, as in REAPER)
    * drag an edge   change its height -- every selected track's, when
                     it's one of them; double-click an edge for the
                     default height
    * wheel          scrolls the arrange view; ctrl+wheel zooms it
  The empty space under the last track inserts: double-click for a new
  track, right-click or the "+" tile for new-or-template.

  THE SAME CODE, NOT A COPY. The channel panel is CH.draw_body -- the
  function that draws ChannelView's own Channel panel and every mixer
  strip -- so the fader taper, the meter, ganging, swipe-to-mute and
  double-click-for-default are ChannelView's, because they are
  ChannelView. The track menus are TS_CV_TrackMenu, the colours are
  TS_CV_Config's palette, and Hue and Tint are read from ChannelView's
  own settings, so changing them in either window changes both.

  ALIGNMENT. Nothing here is kept in step with the arrange view by hand:
  each row's position is REAPER's own I_TCPY / I_TCPH for that track,
  read every frame, against where the arrange view actually is on screen
  -- see TS_CV_Arrange. Vertical zoom, heights changed in REAPER's panel,
  folders collapsing and spacers all come through on their own. This
  needs js_ReaScriptAPI, which is the only way a script can find where a
  REAPER window is.

  REAPER's own TCP stays where it is -- no script can remove it. Drag the
  divider between it and the arrange view as narrow as it goes, or give
  it an empty layout in your theme.

  Requires ReaImGui (v0.10 or newer) and js_ReaScriptAPI.
--]]

-- ---------------------------------------------------------------------
-- module loading
-- ---------------------------------------------------------------------

local script_dir = debug.getinfo(1, "S").source:match("@?(.*[\\/])") or ""

if not reaper.ImGui_GetBuiltinPath then
  reaper.MB("ChannelView TCP needs the ReaImGui extension.\n\n" ..
            "Install it with ReaPack: Extensions > ReaPack > Browse packages, " ..
            "search for \"ReaImGui\".", "ChannelView TCP", 0)
  return
end

package.path = script_dir .. "?.lua;"
            .. reaper.ImGui_GetBuiltinPath() .. "/?.lua;"
            .. package.path

local ok_imgui, ImGui = pcall(require, "imgui")
if ok_imgui then ok_imgui, ImGui = pcall(ImGui, "0.10") end
if not ok_imgui then
  reaper.MB("ChannelView TCP could not load ReaImGui:\n\n" .. tostring(ImGui),
            "ChannelView TCP", 0)
  return
end

local C  = require("TS_CV_Config")
local U  = require("TS_CV_Util")
local W  = require("TS_CV_Widgets")
local CH = require("TS_CV_Channel")
local G  = require("TS_CV_Gang")
local TM = require("TS_CV_TrackMenu")
local TO = require("TS_CV_TrackOps")
local IC = require("TS_CV_Icons")
local FO = require("TS_CV_Focus")
local AR = require("TS_CV_Arrange")
local TB = require("TS_CV_Toolbar")
local EN = require("TS_CV_Envelopes")
local SD = require("TS_CV_Sends")
local RV = require("TS_CV_Receives")
local B  = require("TS_CV_Browser")
local LN = require("TS_CV_Lanes")
-- Its own "Run when REAPER starts" block and command id, separate from
-- ChannelView's, so either can be on without the other.
local SU = require("TS_CV_Startup").make("ChannelView TCP", "TS_ChannelView_TCP.lua",
                                         "channelview_tcp_cmd")

W.attach(ImGui); CH.attach(ImGui); TM.attach(ImGui); IC.attach(ImGui); TB.attach(ImGui)
EN.attach(ImGui); SD.attach(ImGui); RV.attach(ImGui); B.attach(ImGui); LN.attach(ImGui)
-- Asked for while the action context is still this script's, as
-- ChannelView does.
SU.init()
-- The Channel panel's record-input menu lives in TS_CV_Inputs where that
-- module exists; it needs ImGui like everything else it draws with.
do
  local ok, IN = pcall(require, "TS_CV_Inputs")
  if ok and type(IN) == "table" and IN.attach then IN.attach(ImGui) end
end

-- NOTE ON Begin/End PAIRING: as in TS_ChannelView.lua, End() and
-- EndChild() are called only when the matching Begin returned true.

-- ---------------------------------------------------------------------
-- settings
-- ---------------------------------------------------------------------

local function ext_get(k, default)
  local v = reaper.GetExtState(C.TCP_EXT_SECT, k)
  if v == "" then return default end
  return v
end
local function ext_set(k, v) reaper.SetExtState(C.TCP_EXT_SECT, k, tostring(v), true) end

-- ChannelView's own settings. Colour and keyboard focus are one choice
-- made once, not one per window.
local function cv_get(k, default)
  local v = reaper.GetExtState(C.EXT_SECT, k)
  if v == "" then return default end
  return v
end
local function cv_set(k, v) reaper.SetExtState(C.EXT_SECT, k, tostring(v), true) end

-- Hue and tint are no longer ChannelView's to own -- see TS_Palette in
-- TS_ChannelView.lua. Falls through to the old location once so an
-- existing setting survives the update.
local function pal_get()
  local h = reaper.GetExtState("TS_Palette", "base_hue")
  local t = reaper.GetExtState("TS_Palette", "tint")
  if h == "" then h = reaper.GetExtState(C.EXT_SECT, "base_hue") end
  if t == "" then t = reaper.GetExtState(C.EXT_SECT, "tint") end
  return tonumber(h), tonumber(t)
end

do
  local h, t = pal_get()
  C.BASE_HUE = h or C.BASE_HUE
  C.TINT     = t or C.TINT
end
C.FOCUS_BACK = cv_get("focus_back", "1") == "1"
C.build_palette()

-- View options that mean the same thing in both windows live in
-- ChannelView's own keys: one setting, both windows follow it.
C.TCP_ICONS       = cv_get("track_icons", "0") == "1"
C.SHOW_VALUES     = cv_get("show_values", C.SHOW_VALUES and "1" or "0") == "1"
C.set_cell_w(cv_get("cell_w", tostring(C.CELL_W_DEFAULT)))
C.TCP_INDENT_FOLDERS = ext_get("indent", C.TCP_INDENT_FOLDERS and "1" or "0") == "1"
C.TCP_LANES       = ext_get("lanes", C.TCP_LANES and "1" or "0") == "1"
C.TCP_STATE_CHIPS = ext_get("chips", C.TCP_STATE_CHIPS and "1" or "0") == "1"
C.TCP_PANEL_H     = tonumber(ext_get("panel_h", C.TCP_PANEL_H)) or C.TCP_PANEL_H
local dock_id     = tonumber(ext_get("dock", "0")) or 0

TB.load()
-- A second toolbar under the tracks, beside the transport: the space
-- between the bottom of the arrange view and the bottom of the window.
local TB2 = TB.make("toolbar2", "tb2", {})
TB2.load()

local ctx = ImGui.CreateContext(C.TCP_WIN_TITLE)
local small_font = ImGui.CreateFont("sans-serif")
ImGui.Attach(ctx, small_font)
W.set_meter_font(small_font)

local app = {
  rows    = {},
  geom    = nil,
  win     = nil,     -- last frame's window rect, for placing the flyout
  anchor  = nil,     -- guid of the last plain click, for shift ranges
  drag    = nil,     -- { track, guid } while a row is being dragged
  resize  = nil,     -- { tracks, h0, my0, scale } while an edge is dragged
  fly     = nil,     -- { track, guid } whose channel panel is open
  suppress = nil,    -- guid whose next click is the tail of a double-click
  open_settings = false,
  overflow = {},
  last_poll = 0,
  first_sel = nil,
}

-- ---------------------------------------------------------------------
-- keeping up with ChannelView
-- ---------------------------------------------------------------------

-- Hue and Tint are ChannelView's settings, and either window can change
-- them, so both look twice a second. ExtState is a string lookup; this
-- costs nothing worth measuring.
local function poll_shared(now)
  if now - app.last_poll < 0.5 then return end
  app.last_poll = now
  do
    local h, t = pal_get()
    C.apply_colour(h or C.BASE_HUE, t or C.TINT)
  end
  C.FOCUS_BACK = cv_get("focus_back", "1") == "1"
  C.TCP_ICONS   = cv_get("track_icons", "0") == "1"
  C.SHOW_VALUES = cv_get("show_values", "1") == "1"
  C.set_cell_w(cv_get("cell_w", tostring(C.CELL_W_DEFAULT)))
end

-- The channel panel follows the selection once it's open: select a
-- track (here, in the arrange view or anywhere else) and the panel shows
-- that one. It never OPENS on selection -- that takes a click on an
-- already-selected track. Only a CHANGE of first-selected track moves
-- it, and an empty selection leaves it where it is.
local function follow_selection()
  local first = reaper.GetSelectedTrack2(0, 0, true)
  if first == app.first_sel then return end
  app.first_sel = first
  if app.fly and first and first ~= app.fly.track then
    app.fly = { track = first, guid = reaper.GetTrackGUID(first) }
  end
end

-- ---------------------------------------------------------------------
-- selection
-- ---------------------------------------------------------------------

-- The mixer's rules, in the TCP's order: plain click selects just this
-- one, ctrl adds or removes, shift takes everything from the last plain
-- click to this one -- among the tracks you can see.
local function click_select(e, mods)
  local ctrl  = (mods & ImGui.Mod_Ctrl) ~= 0 or (mods & ImGui.Mod_Super) ~= 0
  local shift = (mods & ImGui.Mod_Shift) ~= 0
  if ctrl then
    local on = G.is_selected(e.track)
    reaper.SetTrackSelected(e.track, not on)
    if not on then app.anchor = e.guid end
  elseif shift and app.anchor and not e.master then
    local range = AR.range(app.rows, app.anchor, e.guid)
    if range then
      reaper.Main_OnCommand(40297, 0)          -- Track: Unselect all tracks
      for _, tr in ipairs(range) do reaper.SetTrackSelected(tr, true) end
    else
      reaper.SetOnlyTrackSelected(e.track)
      app.anchor = e.guid
    end
  else
    reaper.SetOnlyTrackSelected(e.track)
    -- Last touched, as a click in REAPER's own panel makes it: inserts
    -- and a good many actions go by it.
    reaper.Main_OnCommand(40914, 0)            -- first selected is last touched
    app.anchor = e.guid
  end
  reaper.UpdateArrange()
end

local function on_click(e)
  local mods = ImGui.GetKeyMods(ctx)
  local was_open = app.fly and app.fly.guid == e.guid
  local was_sel  = G.is_selected(e.track)
  click_select(e, mods)
  if mods ~= 0 then return end
  -- The panel: the first click on a track only selects it. A click on a
  -- track that was ALREADY selected opens its panel -- or closes it, if
  -- that's the track it's showing.
  if not was_sel then return end
  if was_open then
    app.fly = nil
  else
    app.fly = { track = e.track, guid = e.guid }
  end
  app.first_sel = reaper.GetSelectedTrack2(0, 0, true)
end

local function selected_or(track)
  if G.is_selected(track) and G.count() > 1 then
    local out = {}
    for i = 0, G.count() - 1 do out[#out + 1] = reaper.GetSelectedTrack2(0, i, true) end
    return out
  end
  return { track }
end

-- ---------------------------------------------------------------------
-- one row
-- ---------------------------------------------------------------------

local FOLDER_ICON = { [0] = "folder_full", [1] = "folder_collapsed", [2] = "folder_hidden" }
local FOLDER_TIP  = {
  [0] = "Collapse folder",
  [1] = "Hide children",
  [2] = "Expand folder",
}

local function fit(ctx, text, w)
  local tw = ImGui.CalcTextSize(ctx, text)
  if tw <= w then return text, tw end
  local n = #text
  while n > 1 do
    n = n - 1
    local t = text:sub(1, n) .. "."
    tw = ImGui.CalcTextSize(ctx, t)
    if tw <= w then return t, tw end
  end
  return "", 0
end

local function draw_row(dl, e, x, w, now)
  local tr   = e.track
  local y0   = e.y
  local h    = e.h
  local y1   = y0 + h
  local ix   = x + (C.TCP_INDENT_FOLDERS and e.depth * C.TCP_INDENT or 0)
  local rw   = math.max(1, x + w - ix)
  local col  = U.track_colour(tr, 0xff)
  if e.master and not col then col = 0x8a90a0ff end
  local sel  = G.is_selected(tr)
  local base = col or C.COL.header_bg
  local body_l = ix + C.TCP_STRIP_W

  -- Frame. One pixel short at the bottom, so neighbouring rows read as
  -- separate things with the window colour between them.
  ImGui.DrawList_AddRectFilled(dl, ix, y0, x + w, y1 - 1,
    sel and C.COL.header_bg or C.COL.panel_bg, 0)
  ImGui.DrawList_AddRectFilled(dl, ix, y0, body_l, y1 - 1, base, 0)
  if e.env > 1 then
    -- Envelope lanes belong to the track: the colour carries on down
    -- beside them, faintly, the way REAPER's own panel does it.
    ImGui.DrawList_AddRectFilled(dl, ix, y1, ix + 3, y1 + e.env - 1,
      U.with_alpha(base, 0x77), 0)
  end
  if sel then
    local oc = U.sel_colour(C.SEL_OUTLINE, col, C.COL.strip_sel)
    ImGui.DrawList_AddRect(dl, ix + 0.5, y0 + 0.5, x + w - 0.5, y1 - 1.5, oc, 0, 0, 1.0)
  end
  if app.fly and app.fly.guid == e.guid then
    -- The row whose panel is open gets a notch on the right edge,
    -- pointing out at the panel beside it.
    local my = y0 + (h - 1) * 0.5
    local nh = math.min(6, (h - 1) * 0.5)
    ImGui.DrawList_AddTriangleFilled(dl, x + w, my - nh, x + w, my + nh,
      x + w - nh, my, C.COL.accent)
  end

  -- The whole row is one button, submitted first so the folder icon,
  -- the chips and the edge handle on top of it take their own clicks.
  ImGui.SetCursorScreenPos(ctx, ix, y0)
  W.allow_overlap(ctx)
  local pressed = ImGui.InvisibleButton(ctx, "tcprow" .. e.guid, rw, math.max(1, h - 1),
    ImGui.ButtonFlags_MouseButtonLeft | ImGui.ButtonFlags_MouseButtonRight)
  local hovered = ImGui.IsItemHovered(ctx)
  if ImGui.IsItemClicked(ctx, ImGui.MouseButton_Right) then TM.open_context(tr) end
  if hovered and ImGui.IsMouseDoubleClicked(ctx, ImGui.MouseButton_Left) then
    app.suppress = e.guid
    if not e.master then TM.open_rename(tr) end
  end
  if not e.master and not app.drag and not app.resize
     and ImGui.IsItemActive(ctx) and ImGui.IsMouseDown(ctx, ImGui.MouseButton_Left) then
    -- x and y are output slots in the Lua API and are passed as nil;
    -- the button is the fourth argument.
    local _, dy = ImGui.GetMouseDragDelta(ctx, nil, nil, ImGui.MouseButton_Left)
    if math.abs(dy) >= C.DRAG_THRESHOLD then app.drag = { track = tr, guid = e.guid } end
  end
  if pressed and not app.drag and ImGui.IsMouseReleased(ctx, ImGui.MouseButton_Left) then
    if app.suppress == e.guid then app.suppress = nil else on_click(e) end
  end

  -- Contents.
  local pad = C.TCP_PAD
  local cl  = body_l + pad
  local cr  = x + w - pad - ((app.fly and app.fly.guid == e.guid) and 5 or 0)
  local _, th = ImGui.CalcTextSize(ctx, "Ag")

  if C.TCP_ICONS then
    -- A fixed column, reserved on every row whether or not the track has
    -- an icon, so the meters all end at the same place.
    local col_w = C.TCP_ICON_MAX
    local raw = IC.path_of(tr)
    local s = math.min(h - 1 - pad * 2, col_w)
    if raw and s >= 12 then
      IC.draw(ctx, dl, raw, cr - col_w + (col_w - s) * 0.5, y0 + (h - 1 - s) * 0.5, s, s)
    end
    cr = cr - col_w - pad
  end

  -- Fixed item lanes: a play button and name per lane, level with each
  -- lane. The column is kept on every row while any track uses fixed
  -- lanes, so the meters stay one width.
  if app.any_lanes then
    local lw = C.TCP_LANE_W
    if LN.is_fixed(tr) and LN.count(tr) > 0 then
      ImGui.DrawList_AddLine(dl, cr - lw - 2.5, y0 + 2, cr - lw - 2.5, y1 - 3,
        C.COL.panel_border, 1.0)
      LN.draw(ctx, dl, tr, e, cr - lw, cr, e.guid)
    end
    cr = cr - lw - pad - 3
  end

  -- Where the name and the meter go. A row tall enough gets both at the
  -- top, the way REAPER lays its own panel out; a short one keeps the
  -- name and lets the meter shrink to a line along the bottom; one too
  -- short for both keeps the name alone -- the name is the minimum,
  -- since a meter you can't put a name to says nothing.
  local name_y, meter_y, meter_h
  if h - 1 >= pad + th + 3 + C.TCP_METER_H + pad then
    name_y  = y0 + pad
    meter_y = name_y + th + 3
    meter_h = C.TCP_METER_H
  elseif h - 1 >= th + C.TCP_METER_THIN + 4 then
    meter_h = C.TCP_METER_THIN
    meter_y = y1 - 2 - meter_h
    name_y  = y0 + math.max(1, (meter_y - y0 - th) * 0.5)
  else
    name_y = y0 + (h - 1 - th) * 0.5
  end
  -- Clip the contents to the row: at REAPER's smallest heights the name
  -- is taller than the row it sits in.
  ImGui.DrawList_PushClipRect(dl, ix, y0, x + w, y1 - 1, true)

  if name_y then
    local nl = cl
    if e.folder then
      local isz = math.min(th + 2, 16)
      local fx, fy = cl - 1, name_y + (th - isz) * 0.5
      ImGui.SetCursorScreenPos(ctx, fx, fy)
      if ImGui.InvisibleButton(ctx, "tcpfold" .. e.guid, isz, isz) then
        TO.cycle_folder(tr)
      end
      local ihov = ImGui.IsItemHovered(ctx)
      if ihov then
        ImGui.DrawList_AddRectFilled(dl, fx, fy, fx + isz, fy + isz, C.COL.knob_body_hi, 2.0)
      end
      local m = TO.folder_mode(tr)
      W.ICONS[FOLDER_ICON[m]](dl, fx, fy, isz, ihov and C.COL.icon_hot or C.COL.icon)
      W.tip(ctx, "tcpfold" .. e.guid, FOLDER_TIP[m], ihov, false)
      nl = nl + isz + 4
    end

    -- State chips, right to left, only while on. Each one turns its
    -- state back off -- through the gang, like every other state write.
    local chip_r = cr
    -- Automation: the "+" at the far right of the name line, always
    -- there. Opens the lane menu -- the track's own envelopes and every
    -- plugin's parameters.
    do
      local ps = math.min(C.TCP_CHIP, th + 1)
      chip_r = chip_r - ps
      ImGui.SetCursorScreenPos(ctx, chip_r, name_y + (th - ps) * 0.5)
      if W.icon_button(ctx, "tcpauto" .. e.guid, "plus", ps, false,
          "Add lane") then
        EN.open_menu(tr)
      end
      chip_r = chip_r - 4
    end
    if C.TCP_STATE_CHIPS then
      local cs = math.min(C.TCP_CHIP, th + 1)
      local cy = name_y + (th - cs) * 0.5
      local function chip(id, text, on_col, tip, key, icon)
        chip_r = chip_r - cs
        local hit, dbl
        if icon then
          hit, dbl = W.state_icon(ctx, id, icon, chip_r, cy, cs, cs, true, on_col, tip)
        else
          hit, dbl = W.state_button(ctx, id, text, chip_r, cy, cs, cs, true, on_col, tip)
        end
        if hit or dbl then G.set(tr, key, 0) end
        chip_r = chip_r - 3
      end
      if not e.master and CH.read(tr, "I_RECARM") > 0.5 then
        chip("tcpR" .. e.guid, nil, C.COL.rec_on, "Disarm",
             "I_RECARM", "record")
      end
      if CH.read(tr, "I_SOLO") > 0.5 then
        chip("tcpS" .. e.guid, "S", C.COL.solo_on, "Unsolo", "I_SOLO")
      end
      if CH.read(tr, "B_MUTE") > 0.5 then
        chip("tcpM" .. e.guid, "M", C.COL.mute_on, "Unmute", "B_MUTE")
      end
    end

    -- The number dim, the name bright -- dim too while muted, so a muted
    -- track reads as one even with the chips turned off.
    local muted = CH.read(tr, "B_MUTE") > 0.5
    local room  = chip_r - 4 - nl
    if room > 8 then
      if e.master then
        local t = fit(ctx, "MASTER", room)
        ImGui.DrawList_AddText(dl, nl, name_y, C.COL.header_text, t)
      else
        local num = tostring(e.num)
        local nw  = ImGui.CalcTextSize(ctx, num)
        local nm  = U.trim(TO.name(tr))
        if nm == "" then nm = "Track " .. e.num end
        if nw + 6 < room then
          ImGui.DrawList_AddText(dl, nl, name_y, C.COL.header_dim, num)
          local t = fit(ctx, nm, room - nw - 6)
          ImGui.DrawList_AddText(dl, nl + nw + 6, name_y,
            muted and C.COL.header_dim or C.COL.header_text, t)
        end
        W.tip(ctx, "tcpname" .. e.guid, num .. "  " .. nm,
          hovered and ImGui.IsMouseHoveringRect(ctx, nl, name_y, chip_r, name_y + th), false)
      end
    end
  end

  -- The meter. Same stores and keys scheme as ChannelView's own meters,
  -- prefixed so the two windows never share a peak hold.
  local mw = cr - cl
  if meter_h and mw > 12 then
    -- Peak only: at this size an RMS hairline is noise, not information.
    local nch = W.meter_channels(tr)
    local lv, pk = {}, {}
    for i = 1, nch do
      local key = "tcp" .. e.guid .. "c" .. i
      lv[i] = U.val2db(reaper.Track_GetPeakInfo(tr, i - 1))
      pk[i] = W.level_peak(key, lv[i], now)
    end
    W.level_meter_h(ctx, dl, cl, meter_y, mw, meter_h, lv, pk, nil)
    local over = hovered and ImGui.IsMouseHoveringRect(ctx, cl, meter_y - 1, cr, meter_y + meter_h + 1)
    local tip = {}
    for i = 1, nch do
      tip[i] = ((nch > 1) and ((i == 1) and "L " or "R ") or "") .. U.db_str(pk[i])
    end
    W.tip(ctx, "tcpmeter" .. e.guid, table.concat(tip, "\n"), over, false)
  end

  ImGui.DrawList_PopClipRect(dl)

  -- The bottom edge: drag for height. Submitted last and WITHOUT
  -- allowing overlap, so across the few pixels it shares with the next
  -- row's top, the edge wins.
  local eh = C.TCP_EDGE
  ImGui.SetCursorScreenPos(ctx, ix, y1 - eh * 0.5)
  ImGui.InvisibleButton(ctx, "tcpedge" .. e.guid, rw, eh)
  local ehov, eact = ImGui.IsItemHovered(ctx), ImGui.IsItemActive(ctx)
  if ehov or eact then ImGui.SetMouseCursor(ctx, ImGui.MouseCursor_ResizeNS) end
  if ImGui.IsItemActivated(ctx) then
    local _, my = ImGui.GetMousePos(ctx)
    app.resize = { tracks = selected_or(tr), h0 = e.tcph, my0 = my,
                   scale = (app.geom and app.geom.scale) or 1, last = e.tcph }
  end
  if eact and app.resize then
    local _, my = ImGui.GetMousePos(ctx)
    local nh = math.max(1, app.resize.h0 + (my - app.resize.my0) / app.resize.scale)
    if math.abs(nh - app.resize.last) >= 1 then
      AR.set_height(app.resize.tracks, nh)
      app.resize.last = nh
    end
  end
  if ImGui.IsItemDeactivated(ctx) then app.resize = nil end
  if ehov and ImGui.IsMouseDoubleClicked(ctx, ImGui.MouseButton_Left) then
    AR.set_height(selected_or(tr), 0)
  end
  W.tip(ctx, "tcpedge" .. e.guid,
    "Resize", ehov and not eact, false)
end

-- ---------------------------------------------------------------------
-- the track area
-- ---------------------------------------------------------------------

-- The automation lanes under a track, each level with its own lane in
-- the arrange view: the envelope's I_TCPY / I_TCPH are relative to the
-- track's top, in REAPER's pixels, exactly as the track's are relative to
-- the arrange view's.
local function draw_lanes(dl, e, x, w, top, bot)
  local s = (app.geom and app.geom.scale) or 1
  local ix = x + (C.TCP_INDENT_FOLDERS and e.depth * C.TCP_INDENT or 0)
  local base = U.track_colour(e.track, 0xff) or C.COL.header_bg
  for _, L in ipairs(EN.lanes(e.track, e.tcph)) do
    local ly, lh = e.y + L.tcpy * s, L.tcph * s
    if ly + lh > top and ly < bot and lh >= 4 then
      L.scale = s
      EN.draw_lane(ctx, dl, e.track, L, ix, ly, x + w, lh, base, e.guid .. ":" .. L.idx)
    end
  end
end

local function track_area(x, top, w, h, now)
  local g = app.geom
  local ok = ImGui.BeginChild(ctx, "tcptracks", w, h, 0,
    ImGui.WindowFlags_NoScrollbar | ImGui.WindowFlags_NoScrollWithMouse)
  if not ok then return end
  local dl = ImGui.GetWindowDrawList(ctx)

  -- The empty space: click to deselect, double-click for a new track,
  -- right-click for the insert menu. First, so every row is on top.
  ImGui.SetCursorScreenPos(ctx, x, top)
  W.allow_overlap(ctx)
  local bg_pressed = ImGui.InvisibleButton(ctx, "tcpbg", math.max(1, w), math.max(1, h),
    ImGui.ButtonFlags_MouseButtonLeft | ImGui.ButtonFlags_MouseButtonRight)
  local bg_hov = ImGui.IsItemHovered(ctx)
  if bg_hov and ImGui.IsMouseDoubleClicked(ctx, ImGui.MouseButton_Left) then
    TO.insert_new(nil)
  elseif bg_pressed and ImGui.IsMouseReleased(ctx, ImGui.MouseButton_Left) and not app.drag then
    reaper.Main_OnCommand(40297, 0)          -- Track: Unselect all tracks
    app.anchor, app.fly = nil, nil
    reaper.UpdateArrange()
  end
  if ImGui.IsItemClicked(ctx, ImGui.MouseButton_Right) then TM.open_insert(nil) end

  local last_bottom = g.top
  for _, e in ipairs(app.rows) do
    if e.h > 0 then last_bottom = math.max(last_bottom, e.y + e.h + e.env) end
    if e.visible then
      draw_row(dl, e, x, w, now)
      if e.env > 1 then draw_lanes(dl, e, x, w, top, top + h) end
    end
  end

  -- The "+" tile, under the last track while there's room for it.
  local ay = last_bottom + 4
  if ay + C.TCP_ADD_H < top + h and ay > top - C.TCP_ADD_H then
    ImGui.SetCursorScreenPos(ctx, x + 4, ay)
    if W.dashed_plus(ctx, "tcpadd", math.max(8, w - 8), C.TCP_ADD_H,
        "Add track") then
      TM.open_insert(nil)
    end
  end

  -- Reordering: a marker at the gap under the pointer, or an outline on
  -- the row a drop would go INTO (as its children); the move on release.
  if app.drag then
    local _, my = ImGui.GetMousePos(ctx)
    local before, ly, into = AR.drop_target(app.rows, my, reaper.CountTracks(0))
    if into and not TO.can_nest_into(app.drag.track, into.track) then into = nil end
    if into then
      ImGui.DrawList_AddRect(dl, x + 1, into.y + 0.5, x + w - 1, into.y + into.h - 1,
        C.COL.drop_marker, 0, 0, 3.0)
      local nm = TO.name(into.track)
      ImGui.SetTooltip(ctx, "Into " .. (nm ~= "" and nm or ("Track " .. into.num)))
    elseif ly then
      ImGui.DrawList_AddRectFilled(dl, x + 2, ly - 1.5, x + w - 2, ly + 1.5,
        C.COL.drop_marker, 1.0)
    end
    if ImGui.IsKeyPressed(ctx, ImGui.Key_Escape) then
      app.drag = nil
    elseif not ImGui.IsMouseDown(ctx, ImGui.MouseButton_Left) then
      if reaper.ValidatePtr2(0, app.drag.track, "MediaTrack*") then
        if into then
          if reaper.ValidatePtr2(0, into.track, "MediaTrack*") then
            TO.nest_tracks(app.drag.track, into.track)
          end
        elseif before then
          TO.move_tracks(app.drag.track, before)
        end
      end
      app.drag = nil
    end
  end

  -- The wheel belongs to the arrange view: the TCP has no scroll of its
  -- own, it shows whatever the arrange view is showing. Ctrl+wheel is
  -- vertical zoom, as over REAPER's own track panel.
  if ImGui.IsWindowHovered(ctx, ImGui.HoveredFlags_ChildWindows) and not W.wheel_taken() then
    local wheel = ImGui.GetMouseWheel(ctx)
    if wheel ~= 0 then
      local mods = ImGui.GetKeyMods(ctx)
      if (mods & ImGui.Mod_Ctrl) ~= 0 or (mods & ImGui.Mod_Super) ~= 0 then
        reaper.Main_OnCommand(wheel > 0 and 40111 or 40112, 0)  -- View: Zoom in/out vertical
      else
        AR.scroll(-wheel * C.TCP_WHEEL_PX)
      end
    end
  end

  -- Every row moved the cursor by hand; this is the item that makes
  -- that legitimate. See W.child_skipped.
  ImGui.SetCursorScreenPos(ctx, x, top)
  ImGui.Dummy(ctx, 0, 0)
  ImGui.EndChild(ctx)
end

-- ---------------------------------------------------------------------
-- the channel flyout
-- ---------------------------------------------------------------------

-- ChannelView's Channel panel, in a borderless window of its own just
-- right of the TCP, level with the row it belongs to. A window rather
-- than part of this one because a docked window can't widen its own
-- docker: the panel would have to come out of the rows' width, or the
-- arrange view would have to move every time it opened.
local FLY_FLAGS = nil

local function draw_flyout()
  local f = app.fly
  if not f then return end
  if not reaper.ValidatePtr2(0, f.track, "MediaTrack*") then app.fly = nil return end
  local g, win = app.geom, app.win
  if not g or not win then return end

  local row = nil
  for _, e in ipairs(app.rows) do if e.guid == f.guid then row = e break end end
  local H  = math.max(C.HEADER_H + 120, math.min(C.TCP_PANEL_H, g.bottom - g.top))
  -- Channel, then Sends and Receives beside it, as in ChannelView's own
  -- channel view -- the same panels, drawn by the same module.
  local CW   = C.CHANNEL_W
  local sd_w = SD.width_for(f.track, H)
  -- the master has no Receives panel here either (see ChannelView's channel view)
  local no_rv = (f.track == reaper.GetMasterTrack(0))
  local rv_w = no_rv and 0 or RV.width_for(f.track, H)
  local Wd   = CW + C.PANEL_GAP + sd_w + (no_rv and 0 or (C.PANEL_GAP + rv_w))
  local y  = row and row.y or g.top
  y = math.max(g.top, math.min(y, g.bottom - H))
  local x  = win.x + win.w

  FLY_FLAGS = FLY_FLAGS or (ImGui.WindowFlags_NoDecoration | ImGui.WindowFlags_NoDocking
    | ImGui.WindowFlags_NoSavedSettings | ImGui.WindowFlags_NoMove
    | ImGui.WindowFlags_NoScrollWithMouse | ImGui.WindowFlags_NoFocusOnAppearing)

  ImGui.SetNextWindowPos(ctx, x, y, ImGui.Cond_Always)
  ImGui.SetNextWindowSize(ctx, Wd, H, ImGui.Cond_Always)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowPadding, 0, 0)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowBorderSize, 0)
  ImGui.PushStyleColor(ctx, ImGui.Col_WindowBg, C.COL.win_bg)
  local visible = ImGui.Begin(ctx, "##tcpchannel", nil, FLY_FLAGS)
  if visible then
    local dl = ImGui.GetWindowDrawList(ctx)
    local wx, wy = ImGui.GetWindowPos(ctx)
    local tr = f.track
    local col = U.track_colour(tr, 0xff)
    if tr == reaper.GetMasterTrack(0) and not col then col = 0x8a90a0ff end
    local base = col or C.COL.header_bg
    local ink  = U.contrast_text(base)
    ImGui.DrawList_AddRectFilled(dl, wx, wy, wx + CW, wy + H, C.COL.panel_bg, 3.0)

    -- Background first, so right-click anywhere empty is the track menu,
    -- as on ChannelView's own Channel panel.
    ImGui.SetCursorScreenPos(ctx, wx, wy)
    W.allow_overlap(ctx)
    ImGui.InvisibleButton(ctx, "flybg", CW, H)
    if ImGui.IsItemClicked(ctx, ImGui.MouseButton_Right) then TM.open_context(tr) end

    ImGui.DrawList_AddRect(dl, wx + 0.5, wy + 0.5, wx + CW - 0.5, wy + H - 0.5,
      C.COL.panel_border, 3.0, 0, 1.0)

    -- The cap: ChannelView's own Channel header, in the track's colour,
    -- with the track's name and a close button -- the same function, so
    -- input FX, automation mode and whatever else it grows appear here too.
    local label
    if tr == reaper.GetMasterTrack(0) then label = "MASTER"
    else
      local nm = U.trim(TO.name(tr))
      local n = math.floor(reaper.GetMediaTrackInfo_Value(tr, "IP_TRACKNUMBER") or 0)
      label = (nm ~= "") and nm or ("Track " .. n)
    end
    CH.draw_header(ctx, dl, wx, wy, CW, tr, {
      title = label, base = base, ink = ink, idp = "tcpfly",
      on_close = function() app.fly = nil end,
    })

    if app.fly then
      CH.draw_body(ctx, dl, wx, wy + C.HEADER_H, CW, H - C.HEADER_H, tr, "tcpf" .. f.guid)
    end
    if app.fly then
      ImGui.SetCursorScreenPos(ctx, wx + CW + C.PANEL_GAP, wy)
      SD.draw(ctx, tr, H)
      if not no_rv then
        ImGui.SetCursorScreenPos(ctx, wx + CW + C.PANEL_GAP + sd_w + C.PANEL_GAP, wy)
        RV.draw(ctx, tr, H)
      end
      SD.draw_menu(ctx, tr); SD.draw_ctx(ctx, tr)
      RV.draw_menu(ctx, tr); RV.draw_ctx(ctx, tr)
      -- The plugin search dialog, for the IN button's "Search..."
      B.draw(ctx, tr)
    end

    if ImGui.IsWindowHovered(ctx, ImGui.HoveredFlags_ChildWindows)
       and ImGui.IsKeyPressed(ctx, ImGui.Key_Escape) then
      app.fly = nil
    end

    ImGui.SetCursorScreenPos(ctx, wx, wy)
    ImGui.Dummy(ctx, 0, 0)
    W.draw_tip(ctx)
    ImGui.End(ctx)
  end
  ImGui.PopStyleColor(ctx)
  ImGui.PopStyleVar(ctx, 2)
end

-- ---------------------------------------------------------------------
-- settings menu
-- ---------------------------------------------------------------------

local DOCKS = {
  { "Floating", 0 }, { "Docker 1", -1 }, { "Docker 2", -2 },
  { "Docker 3", -3 }, { "Docker 4", -4 },
}

local function settings_menu()
  if app.open_settings then
    ImGui.OpenPopup(ctx, "tcp_settings")
    app.open_settings = false
  end
  if not ImGui.BeginPopup(ctx, "tcp_settings") then
    -- Closed: forget what __startup.lua said, so the next opening reads
    -- it afresh (see TS_CV_Startup).
    SU.forget()
    return
  end

  if #app.overflow > 0 and ImGui.BeginMenu(ctx, "More buttons") then
    for i, it in ipairs(app.overflow) do
      if ImGui.MenuItem(ctx, TB.label_of(it) .. "##ovf" .. i) then TB.run(it) end
    end
    ImGui.EndMenu(ctx)
  end
  if ImGui.MenuItem(ctx, "Add toolbar action\u{2026}") then TB.pick_start(nil) end
  if ImGui.MenuItem(ctx, "Add bottom toolbar action\u{2026}") then TB2.pick_start(nil) end
  ImGui.Separator(ctx)

  if ImGui.MenuItem(ctx, "Track icons", nil, C.TCP_ICONS) then
    C.TCP_ICONS = not C.TCP_ICONS
    cv_set("track_icons", C.TCP_ICONS and "1" or "0")
  end
  if ImGui.MenuItem(ctx, "Values under controls", nil, C.SHOW_VALUES) then
    C.SHOW_VALUES = not C.SHOW_VALUES
    cv_set("show_values", C.SHOW_VALUES and "1" or "0")
  end
  if ImGui.IsItemHovered(ctx) then
    ImGui.SetTooltip(ctx, "Shared with ChannelView")
  end
  if ImGui.MenuItem(ctx, "Fixed item lane controls", nil, C.TCP_LANES) then
    C.TCP_LANES = not C.TCP_LANES
    ext_set("lanes", C.TCP_LANES and "1" or "0")
  end
  if ImGui.MenuItem(ctx, "Indent folders", nil, C.TCP_INDENT_FOLDERS) then
    C.TCP_INDENT_FOLDERS = not C.TCP_INDENT_FOLDERS
    ext_set("indent", C.TCP_INDENT_FOLDERS and "1" or "0")
  end
  if ImGui.MenuItem(ctx, "Mute / solo / record chips", nil, C.TCP_STATE_CHIPS) then
    C.TCP_STATE_CHIPS = not C.TCP_STATE_CHIPS
    ext_set("chips", C.TCP_STATE_CHIPS and "1" or "0")
  end
  if ImGui.IsItemHovered(ctx) then
    ImGui.SetTooltip(ctx, "Only while on")
  end
  ImGui.SetNextItemWidth(ctx, 150)
  local pch, pv = ImGui.SliderInt(ctx, "Channel panel height", math.floor(C.TCP_PANEL_H), 180, 700)
  if pch then C.TCP_PANEL_H = pv; ext_set("panel_h", pv) end

  do
    local how = FO.mechanism()
    if ImGui.MenuItem(ctx, "Return keyboard focus to REAPER", nil,
        C.FOCUS_BACK and how ~= nil, how ~= nil) then
      C.FOCUS_BACK = not C.FOCUS_BACK
      cv_set("focus_back", C.FOCUS_BACK and "1" or "0")
    end
    if ImGui.IsItemHovered(ctx) then
      ImGui.SetTooltip(ctx, "Shared with ChannelView")
    end
  end

  -- Run at startup: this script's own fenced line in __startup.lua.
  do
    if not SU.checked() then SU.scan() end
    local st_, note = SU.state()
    if ImGui.MenuItem(ctx, "Run when REAPER starts", nil, SU.on(), st_ ~= "nocmd") then
      local ok, why
      if SU.on() then ok, why = SU.remove() else ok, why = SU.add() end
      if not ok then
        reaper.MB("__startup.lua was NOT changed.\n\n" .. tostring(why), "ChannelView TCP", 0)
      end
    end
    if note then ImGui.TextColored(ctx, C.COL.warn, "   " .. U.wrap_note(note, 52)) end
  end

  ImGui.Separator(ctx)
  if ImGui.BeginMenu(ctx, "Colour") then
    -- ChannelView's own two settings, written back to ChannelView's own
    -- keys: the palette is one choice, and both windows follow it.
    ImGui.SetNextItemWidth(ctx, 190)
    local hch, hv = ImGui.SliderInt(ctx, "Hue", math.floor(C.BASE_HUE), 0, 359)
    if hch then
      C.BASE_HUE = hv; C.build_palette(); cv_set("base_hue", hv)
    end
    ImGui.SetNextItemWidth(ctx, 190)
    local tch, tv = ImGui.SliderDouble(ctx, "Tint", C.TINT, 0.0, 2.0, "%.2f")
    if tch then
      C.TINT = tv; C.build_palette(); cv_set("tint", string.format("%.3f", tv))
    end
    ImGui.TextDisabled(ctx, "Shared with ChannelView.")
    if ImGui.MenuItem(ctx, "Reset to default") then
      C.BASE_HUE, C.TINT = 219, 1.0
      C.build_palette()
      cv_set("base_hue", 219); cv_set("tint", "1.000")
    end
    ImGui.EndMenu(ctx)
  end

  if ImGui.BeginMenu(ctx, "Dock") then
    for _, d in ipairs(DOCKS) do
      if ImGui.MenuItem(ctx, d[1], nil, dock_id == d[2]) then
        dock_id = d[2]
        ImGui.SetNextWindowDockID(ctx, dock_id, ImGui.Cond_Always)
        ext_set("dock", dock_id)
      end
    end
    ImGui.EndMenu(ctx)
  end
  ImGui.Separator(ctx)
  ImGui.TextDisabled(ctx, "Dock left of the arrange view to line up.")
  ImGui.EndPopup(ctx)
end

-- ---------------------------------------------------------------------
-- main loop
-- ---------------------------------------------------------------------

local safe_frame

local function frame()
  local now = reaper.time_precise()
  W.begin_frame()
  poll_shared(now)
  follow_selection()
  -- A double-click whose second release landed somewhere else never
  -- consumed its suppression; drop it once the mouse is plainly up.
  if app.suppress and not ImGui.IsMouseDown(ctx, ImGui.MouseButton_Left)
     and not ImGui.IsMouseReleased(ctx, ImGui.MouseButton_Left) then
    app.suppress = nil
  end

  -- Rows are placed before either window is drawn: the flyout needs
  -- them, and it is drawn first so its clicks are in before the main
  -- window's end-of-frame bookkeeping (keyboard focus) runs.
  app.geom = AR.available() and AR.geometry(ctx, ImGui) or nil
  if app.geom then
    app.rows = AR.place(AR.collect(), app.geom)
    app.any_lanes = C.TCP_LANES and LN.any()
  else
    app.rows = {}
  end

  draw_flyout()

  ImGui.SetNextWindowSize(ctx, 240, 600, ImGui.Cond_FirstUseEver)
  if dock_id ~= 0 then ImGui.SetNextWindowDockID(ctx, dock_id, ImGui.Cond_FirstUseEver) end
  ImGui.PushStyleColor(ctx, ImGui.Col_WindowBg, C.COL.win_bg)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowPadding, 0, 0)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_ItemSpacing, 4, 4)
  local visible, open = ImGui.Begin(ctx, C.TCP_WIN_TITLE, true,
    ImGui.WindowFlags_NoScrollbar | ImGui.WindowFlags_NoScrollWithMouse)

  if visible then
    local d = ImGui.GetWindowDockID(ctx)
    if d ~= dock_id then dock_id = d; ext_set("dock", d) end

    local wx, wy = ImGui.GetWindowPos(ctx)
    local ww, wh = ImGui.GetWindowSize(ctx)
    app.win = { x = wx, y = wy, w = ww, h = wh }
    local cx, cy = ImGui.GetCursorScreenPos(ctx)
    local g = app.geom

    if not g then
      ImGui.SetCursorScreenPos(ctx, cx + 8, cy + 8)
      ImGui.PushTextWrapPos(ctx, ww - 8)   -- window-local, not screen
      if AR.available() then
        ImGui.TextWrapped(ctx, "Can't find REAPER's arrange view.")
      else
        ImGui.TextWrapped(ctx, "ChannelView TCP needs the js_ReaScriptAPI extension " ..
          "to find where the arrange view is.\n\nExtensions > ReaPack > Browse " ..
          "packages, search for js_ReaScriptAPI, install, and restart REAPER.")
      end
      ImGui.PopTextWrapPos(ctx)
    else
      local bottom = wy + wh
      -- The toolbar is everything above the arrange view's top edge:
      -- the ruler and marker/region lanes' own height, measured.
      local tb_bottom = math.max(cy, math.min(g.top, bottom))
      local res = TB.draw(ctx, cx, cy, ww, tb_bottom - cy - 1)
      if res.menu then app.open_settings = true end
      app.overflow = res.overflow
      if tb_bottom > cy then
        local dl = ImGui.GetWindowDrawList(ctx)
        ImGui.DrawList_AddLine(dl, wx, tb_bottom - 0.5, wx + ww, tb_bottom - 0.5,
          C.COL.panel_border, 1.0)
      end

      local area_top = tb_bottom
      local area_bot = math.min(g.bottom, bottom)
      if area_bot - area_top > 4 then
        ImGui.SetCursorScreenPos(ctx, wx, area_top)
        track_area(wx, area_top, ww, area_bot - area_top, now)
      end

      -- The bottom toolbar: whatever is left below the arrange view --
      -- level with its scrollbar and the transport under it.
      if bottom - area_bot >= C.TB_MIN_H + 2 then
        local dl = ImGui.GetWindowDrawList(ctx)
        ImGui.DrawList_AddLine(dl, wx, area_bot + 0.5, wx + ww, area_bot + 0.5,
          C.COL.panel_border, 1.0)
        local res2 = TB2.draw(ctx, cx, area_bot + 1, ww, bottom - area_bot - 2, true)
        for _, it in ipairs(res2.overflow) do app.overflow[#app.overflow + 1] = it end
      end
      ImGui.SetCursorScreenPos(ctx, cx, cy)
      ImGui.Dummy(ctx, 0, 0)
    end

    if app.fly and ImGui.IsWindowFocused(ctx) and ImGui.IsKeyPressed(ctx, ImGui.Key_Escape) then
      app.fly = nil
    end

    TB.draw_menus(ctx)
    TB2.draw_menus(ctx)
    settings_menu()
    TM.draw(ctx)
    EN.draw_menus(ctx)
    LN.draw_menus(ctx)
    FO.update(ctx, ImGui, C.FOCUS_BACK)
    W.draw_tip(ctx)
    ImGui.End(ctx)
  else
    -- Docked behind another tab: no TCP on screen, so no flyout beside it.
    app.win = nil
  end
  ImGui.PopStyleVar(ctx, 2)
  ImGui.PopStyleColor(ctx)

  if open then
    reaper.defer(safe_frame)
  else
    TB.cancel_pick(); TB2.cancel_pick()
  end
end

function safe_frame()
  local ok, err = xpcall(frame, function(e)
    return debug.traceback(tostring(e), 2)
  end)
  if ok then return end
  TB.cancel_pick(); TB2.cancel_pick()
  reaper.ShowConsoleMsg(
    "\n--- ChannelView TCP stopped on an error ---------------------\n" ..
    tostring(err) ..
    "\n-------------------------------------------------------------\n")
end

reaper.atexit(function() TB.cancel_pick(); TB2.cancel_pick() end)
reaper.defer(safe_frame)
