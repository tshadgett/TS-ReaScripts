-- @description ChannelView -- docked channel strip: one editable control panel per plugin
-- @author Tim Shadgett (with Claude)
-- @version 1.2.0
-- @license MIT
-- @provides
--  [main]   TS_CV_Diag.lua
--  [nomain] TS_CV_Browser.lua
--  [nomain] TS_CV_Channel.lua
--  [nomain] TS_CV_Config.lua
--  [nomain] TS_CV_Editor.lua
--  [nomain] TS_CV_EQPanel.lua
--  [nomain] TS_CV_FXIndex.lua
--  [nomain] TS_CV_FXTree.lua
--  [nomain] TS_CV_Gang.lua
--  [nomain] TS_CV_Mappings.lua
--  [nomain] TS_CV_Mixer.lua
--  [nomain] TS_CV_Panel.lua
--  [nomain] TS_CV_ReaEQ.lua
--  [nomain] TS_CV_Sends.lua
--  [nomain] TS_CV_Startup.lua
--  [nomain] TS_CV_State.lua
--  [nomain] TS_CV_Steps.lua
--  [nomain] TS_CV_TrackStrip.lua
--  [nomain] TS_CV_Util.lua
--  [nomain] TS_CV_Widgets.lua
-- @about
--  A dockable window showing one panel per plugin on the selected track.
--  Each panel carries a float button, a bypass button and a set of knobs
--  and buttons wired straight to that plugin's parameters -- what you
--  assign to a panel is remembered per plugin, so the same plugin always
--  comes up looking the same wherever it turns up.
--
--  Panels are a fixed height and grow in COLUMNS: rows fall out of the
--  window height, controls flow down a column and wrap into a new one, so
--  a panel never scrolls vertically -- the row of panels scrolls sideways
--  instead. The track strip along the bottom mirrors REAPER's own track
--  selection both ways.
--
--  Lineage. The parameter-mapping idea and the layout-library file format
--  were taken from Wormhole Labs' StripLink -- the concepts and the file
--  format, not its code: nothing here is copied from it. StripLink puts
--  that idea behind a JSFX embedded UI; this is a ReaImGui window that
--  writes parameters directly.
--
--  The container-aware FX chain walk is ported from RackLib.lua, shared by
--  my own Plugin Rack.lua and Docked Plugin Display.lua. That is my code,
--  not a third party's.
--
--  Requires the ReaImGui extension (v0.9 or newer).

-- ---------------------------------------------------------------------
-- module loading
-- ---------------------------------------------------------------------

local script_dir = debug.getinfo(1, "S").source:match("@?(.*[\\/])") or ""

if not reaper.ImGui_GetBuiltinPath then
  reaper.MB("ChannelView needs the ReaImGui extension.\n\n" ..
            "Install it with ReaPack: Extensions > ReaPack > Browse packages, " ..
            "search for \"ReaImGui\".", "ChannelView", 0)
  return
end

package.path = script_dir .. "?.lua;"
            .. reaper.ImGui_GetBuiltinPath() .. "/?.lua;"
            .. package.path

local ok_imgui, ImGui = pcall(require, "imgui")
if ok_imgui then ok_imgui, ImGui = pcall(ImGui, "0.10") end
if not ok_imgui then
  reaper.MB("ChannelView could not load ReaImGui:\n\n" .. tostring(ImGui),
            "ChannelView", 0)
  return
end

local C = require("TS_CV_Config")
local U = require("TS_CV_Util")
local T = require("TS_CV_FXTree")
local M = require("TS_CV_Mappings")
local W = require("TS_CV_Widgets")
local P = require("TS_CV_Panel")
local E  = require("TS_CV_Editor")
local S  = require("TS_CV_TrackStrip")
local St = require("TS_CV_State")
local B  = require("TS_CV_Browser")
local SC = require("TS_CV_Steps")
local CH = require("TS_CV_Channel")
local SD = require("TS_CV_Sends")
local MX = require("TS_CV_Mixer")
local SU = require("TS_CV_Startup")

W.attach(ImGui); P.attach(ImGui); E.attach(ImGui); S.attach(ImGui); B.attach(ImGui)
CH.attach(ImGui); SD.attach(ImGui); MX.attach(ImGui)

-- Asked for while the action context still belongs to this script, so the
-- startup option has a real command id to write. Harmless if REAPER hasn't
-- given us one yet -- the option then says so instead of writing a dead
-- line into __startup.lua.
SU.init()
M.init(script_dir)
SC.init(script_dir)

-- NOTE ON Begin/End PAIRING
-- ReaImGui keeps Dear ImGui's PRE-1.90 convention: End() and EndChild()
-- are called ONLY when the matching Begin()/BeginChild() returned true.
-- Calling them unconditionally -- which is what upstream Dear ImGui now
-- requires -- trips an assertion and kills the defer loop, so the window
-- just disappears. Every Begin/BeginChild in this project is guarded.

-- ---------------------------------------------------------------------
-- state
-- ---------------------------------------------------------------------

local ctx = ImGui.CreateContext(C.WIN_TITLE)

-- A smaller face for meter readouts. In ReaImGui 0.10 a font carries no
-- size of its own -- the size is given at PushFont -- so one font object
-- covers every small-text use.
local small_font = ImGui.CreateFont("sans-serif")
ImGui.Attach(ctx, small_font)
W.set_meter_font(small_font)

local app = {
  track        = nil,
  chain        = {},
  chain_hash   = "",
  last_scan    = 0,
  menu_fx      = nil,   -- index into app.chain, for the panel menu
  ctl_menu     = nil,   -- {fx = index, ctl = index}, for the control menu
  row_dbl      = false, -- the plugin row's empty space was double-clicked
  header_dbl   = false, -- the window header was double-clicked
  open_panel_menu = false,
  open_ctl_menu   = false,
  rename_buf   = "",
  want_quit    = false,
  change_count = -1,    -- reaper.GetProjectStateChangeCount, for edits elsewhere
  drag         = nil,   -- {chain_i, guid} while a panel header is dragged
  drop_gap     = nil,   -- gap index the drop would land in
  panel_rects  = {},    -- per-frame {chain_i, x, w, top_index, collapsed}
}

local function ext_get(k, default)
  local v = reaper.GetExtState(C.EXT_SECT, k)
  if v == "" then return default end
  return v
end

local function ext_set(k, v)
  reaper.SetExtState(C.EXT_SECT, k, tostring(v), true)
end

local dock_id = tonumber(ext_get("dock", "0")) or 0
C.SHOW_VALUES = ext_get("show_values", C.SHOW_VALUES and "1" or "0") == "1"
-- Which of the two views is up. Persisted, because reopening the window
-- into the view you were not in is a small daily annoyance.
C.MIXER_VIEW  = ext_get("mixer_view", "0") == "1"
C.FLOW        = ext_get("flow", C.FLOW)
C.ROW_ALIGN   = ext_get("row_align", C.ROW_ALIGN)
C.BASE_HUE    = tonumber(ext_get("base_hue", C.BASE_HUE)) or C.BASE_HUE
C.TINT        = tonumber(ext_get("tint", C.TINT)) or C.TINT
C.build_palette()

-- ---------------------------------------------------------------------
-- chain tracking
-- ---------------------------------------------------------------------

local function current_track()
  return reaper.GetSelectedTrack2(0, 0, true)
end

local function track_valid(tr)
  return tr ~= nil and reaper.ValidatePtr2(0, tr, "MediaTrack*")
end

local function rescan(force)
  local now = reaper.time_precise()
  if not force and (now - app.last_scan) < C.RESCAN_INTERVAL then return end
  app.last_scan = now

  local list = app.track and T.collect(app.track) or {}
  local h = T.hash(list)
  -- Two different things happen here. A FORCED rescan re-reads the chain,
  -- because an FX address is a position and an edit anywhere can have
  -- moved it. Throwing away the caches is a separate matter, and must
  -- follow the chain actually CHANGING -- REAPER's project change count
  -- moves on every parameter write, so a forced rescan happens on every
  -- frame of every knob drag, and clearing there would reset the meters'
  -- peak hold and re-anchor the tooltip to the pointer sixty times a
  -- second.
  local moved = (h ~= app.chain_hash)
  if force or moved then
    app.chain, app.chain_hash = list, h
  end
  if moved then
    -- Menus hold an INDEX into the old chain, so they can't survive it
    -- changing shape.
    app.menu_fx, app.ctl_menu, app.drag = nil, nil, nil
    P.clear_caches()
    M.clear_default_cache()
    T.clear_gr_cache()
    W.clear_peaks()
    W.clear_levels()
    W.clear_rms()
    W.clear_tips()
    W.clear_rot()
  end
end

-- Every cached FX address is a position, so an edit anywhere -- REAPER's
-- FX chain window, another script, an undo -- can leave this window
-- pointing at the wrong plugin. Two guards, both cheap:
--
--   1. The project's change count moves on ANY edit, so it catches the
--      common cases within a frame rather than within a poll interval.
--   2. Comparing each panel's remembered GUID against whatever is now at
--      its address catches the rest, including changes that don't bump
--      the counter the way we expect.
--
-- Without these, dragging a knob after someone reordered the chain
-- elsewhere would write to a different plugin entirely.
local function chain_is_stale()
  if not app.track then return false end
  for _, fx in ipairs(app.chain) do
    if T.guid_at(app.track, fx.addr) ~= fx.guid then return true end
  end
  return false
end

local function follow_selection()
  local tr = current_track()
  -- A stale pointer (track deleted, or the project switched under us) has
  -- to be dropped before anything reads FX off it.
  if not track_valid(app.track) and app.track ~= nil then
    app.track, app.chain, app.chain_hash = nil, {}, ""
  end
  if tr ~= app.track then
    app.track = tr
    app.menu_fx, app.ctl_menu, app.drag = nil, nil, nil
    St.clear_cache()
    S.request_scroll()
    rescan(true)
  end
end

-- The layout a panel should draw, and the key it's filed under.
local function layout_for(fx)
  local key = U.plugin_key(fx.name)
  local layout, is_default = M.get_or_default(key, app.track, fx.addr, fx.guid)
  return layout, key, is_default
end

-- Direct manipulation (right-click a knob, Remove) has to write to the
-- library, so a plugin still showing its generated default gets that
-- default committed first -- otherwise the edit would vanish on the next
-- frame when the default regenerated.
local function materialise(fx)
  local layout, key, is_default = layout_for(fx)
  if is_default then
    layout = M.copy(layout)
    M.set(key, layout)
  end
  return layout, key
end

-- ---------------------------------------------------------------------
-- reordering
-- ---------------------------------------------------------------------

-- Only TOP-LEVEL plugins can be reordered from here. REAPER 7's container
-- addressing is a community reverse-engineering, and while it's reliable
-- enough to READ a chain, moving an FX into or out of a container isn't
-- something the documented API exposes -- so nested panels aren't drag
-- handles at all, and say why on hover.
local function move_fx(src_top, gap)
  if not app.track then return end
  -- `gap` counts insertion points (0 = before the first plugin). Removing
  -- the source first shifts everything after it down one, so a move to the
  -- right needs the destination decremented to land where the marker was.
  local dest = (gap > src_top) and (gap - 1) or gap
  if dest == src_top then return end
  reaper.Undo_BeginBlock()
  reaper.TrackFX_CopyToTrack(app.track, src_top, app.track, dest, true)
  reaper.Undo_EndBlock("ChannelView: reorder plugin", -1)
  rescan(true)
end

-- Removing a plugin. Top-level only, for the same reason reordering is:
-- addressing inside a REAPER container is reverse-engineered, and a wrong
-- address here deletes the wrong plugin rather than just failing. No
-- confirmation prompt -- it's a single undo step, same as deleting from
-- REAPER's own FX chain window.
local function remove_fx(fx)
  if not app.track or not fx or not fx.is_top_level then return end
  reaper.Undo_BeginBlock()
  reaper.TrackFX_Delete(app.track, fx.top_index)
  reaper.Undo_EndBlock("ChannelView: remove " .. U.clean_fx_name(fx.name), -1)
  app.menu_fx, app.ctl_menu = nil, nil
  rescan(true)
end

-- Which insertion gap the pointer is over, from the panel rectangles
-- recorded while drawing. Only top-level panels define gaps.
local function gap_under(mx)
  local tops = {}
  for _, r in ipairs(app.panel_rects) do
    if r.top_index then tops[#tops + 1] = r end
  end
  if #tops == 0 then return nil end
  for _, r in ipairs(tops) do
    if mx < r.x + r.w * 0.5 then return r.top_index, r.x - C.PANEL_GAP * 0.5 end
  end
  local last = tops[#tops]
  return last.top_index + 1, last.x + last.w + C.PANEL_GAP * 0.5
end

-- ---------------------------------------------------------------------
-- menus
-- ---------------------------------------------------------------------

local function panel_menu()
  if not ImGui.BeginPopup(ctx, "panelmenu") then return end
  local fx = app.chain[app.menu_fx or -1]
  if not fx then ImGui.EndPopup(ctx) return end

  local layout, key, is_default = layout_for(fx)
  ImGui.TextDisabled(ctx, U.clean_fx_name(fx.name))
  ImGui.Separator(ctx)

  if ImGui.MenuItem(ctx, "Edit parameters\u{2026}") then
    E.open(app.track, fx, key, layout)
  end
  if ImGui.MenuItem(ctx, St.is_collapsed(fx.guid) and "Expand" or "Collapse to a bar") then
    St.toggle_collapsed(fx.guid)
  end

  -- The meter is a property of the plugin, so it saves with the layout and
  -- applies to every instance -- same as everything else here.
  if T.reports_gr(app.track, fx.addr, fx.guid) then
    local on = M.meter_of(layout) ~= nil
    if ImGui.MenuItem(ctx, "Gain reduction meter", nil, on) then
      local l = materialise(fx)
      M.set_meter(l, not on)
      M.set(key, l); M.save()
    end
  else
    ImGui.MenuItem(ctx, "Gain reduction meter", nil, false, false)
    if ImGui.IsItemHovered(ctx) then
      ImGui.SetTooltip(ctx, "This plugin doesn't report gain reduction to REAPER.")
    end
  end
  if fx.is_top_level then
    local n_top = reaper.TrackFX_GetCount(app.track)
    if ImGui.MenuItem(ctx, "Move left", nil, false, fx.top_index > 0) then
      move_fx(fx.top_index, fx.top_index - 1)
    end
    if ImGui.MenuItem(ctx, "Move right", nil, false, fx.top_index < n_top - 1) then
      move_fx(fx.top_index, fx.top_index + 2)
    end
  end
  if ImGui.MenuItem(ctx, "Auto-fill layout") then
    M.set(key, M.build_default(app.track, fx.addr)); M.save()
  end
  if ImGui.MenuItem(ctx, "Clear layout", nil, false, not is_default) then
    M.set(key, { controls = {} }); M.save()
  end
  if ImGui.MenuItem(ctx, "Forget saved layout", nil, false, not is_default) then
    M.remove(key); M.save()
  end
  if fx.is_top_level then
    ImGui.Separator(ctx)
    if ImGui.MenuItem(ctx, "Insert plugin before\u{2026}") then
      B.open_menu(fx.top_index)
    end
    if ImGui.MenuItem(ctx, "Insert plugin after\u{2026}") then
      B.open_menu(fx.top_index + 1)
    end
  end
  ImGui.Separator(ctx)
  if ImGui.MenuItem(ctx, "Open the plugin's window") then
    reaper.TrackFX_Show(app.track, fx.addr, 3)
  end
  if ImGui.MenuItem(ctx, "Show in the FX chain") then
    reaper.TrackFX_Show(app.track, fx.addr, 1)
  end
  ImGui.Separator(ctx)
  if fx.is_top_level then
    if ImGui.MenuItem(ctx, "Remove plugin from the chain") then
      remove_fx(fx)
      ImGui.EndPopup(ctx)
      return
    end
  else
    ImGui.MenuItem(ctx, "Remove plugin from the chain", nil, false, false)
    if ImGui.IsItemHovered(ctx) then
      ImGui.SetTooltip(ctx,
        "Inside an FX container \u{2014} remove it in REAPER's FX chain window.")
    end
  end

  ImGui.Separator(ctx)
  ImGui.TextDisabled(ctx, is_default and "auto-generated layout"
                                      or ("saved as \"" .. key .. "\""))
  ImGui.EndPopup(ctx)
end

local TYPE_LABELS = { knob = "Knob", toggle = "Button", combo = "Stepped value",
                      fader = "Fader",
                      blank = "Gap", half_gap = "Half gap", divider = "Divider" }
local TYPE_ORDER  = { "knob", "toggle", "combo", "fader", "blank", "half_gap", "divider" }

local function control_menu()
  if not ImGui.BeginPopup(ctx, "ctlmenu") then return end
  local cm = app.ctl_menu
  local fx = cm and app.chain[cm.fx]
  if not fx then ImGui.EndPopup(ctx) return end

  local layout, key = layout_for(fx)
  local c = layout.controls and layout.controls[cm.ctl]
  if not c then ImGui.EndPopup(ctx) return end

  local _, pname = reaper.TrackFX_GetParamName(app.track, fx.addr, c.param or 0, "")
  ImGui.TextDisabled(ctx, U.truncate(pname or "", 28))
  ImGui.Separator(ctx)

  local function commit()
    local l, k = materialise(fx)
    M.save()
    return l, k
  end

  if ImGui.BeginMenu(ctx, "Show as") then
    for _, t in ipairs(TYPE_ORDER) do
      if ImGui.MenuItem(ctx, TYPE_LABELS[t], nil, c.type == t) then
        local l = commit()
        l.controls[cm.ctl].type = t
        M.set(key, l); M.save()
      end
    end
    ImGui.EndMenu(ctx)
  end

  if ImGui.MenuItem(ctx, "Centred fill", nil, c.bipolar and true or false) then
    local l = commit()
    l.controls[cm.ctl].bipolar = not l.controls[cm.ctl].bipolar
    M.set(key, l); M.save()
  end

  ImGui.Separator(ctx)
  -- Renaming here sets the parameter's ALIAS: the name sticks to the
  -- parameter for this plugin everywhere, panels and editor lists alike,
  -- rather than to this one slot. A slot-only caption is still available
  -- in the full editor for cramped layouts.
  ImGui.TextDisabled(ctx, "Alias (this plugin, everywhere)")
  ImGui.SetNextItemWidth(ctx, 170)
  local ch, v = ImGui.InputTextWithHint(ctx, "##alias", "name\u{2026}", app.rename_buf)
  if ch then app.rename_buf = v end
  ImGui.SameLine(ctx)
  if ImGui.Button(ctx, "Set") then
    materialise(fx)
    M.set_alias(key, c.param, app.rename_buf)
    M.save()
    ImGui.CloseCurrentPopup(ctx)
  end

  ImGui.Separator(ctx)
  if ImGui.MenuItem(ctx, "Remove from panel") then
    local l = commit()
    table.remove(l.controls, cm.ctl)
    M.set(key, l); M.save()
  end
  if ImGui.MenuItem(ctx, "Insert gap before") then
    local l = commit()
    table.insert(l.controls, cm.ctl, { param = -1, type = "blank", bipolar = false, label = "" })
    M.set(key, l); M.save()
  end
  if ImGui.MenuItem(ctx, "Insert half-gap before") then
    local l = commit()
    table.insert(l.controls, cm.ctl, { param = -1, type = "half_gap", bipolar = false, label = "" })
    M.set(key, l); M.save()
  end
  if c.type == "combo" and ImGui.MenuItem(ctx, "Rescan choices") then
    P.rescan_choices(key, c.param)
  end
  if ImGui.MenuItem(ctx, "Insert divider before") then
    local l = commit()
    table.insert(l.controls, cm.ctl, { param = -1, type = "divider", bipolar = false, label = "" })
    M.set(key, l); M.save()
  end
  ImGui.Separator(ctx)
  if ImGui.MenuItem(ctx, "Edit parameters\u{2026}") then
    E.open(app.track, fx, key, layout)
  end
  if ImGui.MenuItem(ctx, St.is_collapsed(fx.guid) and "Expand" or "Collapse to a bar") then
    St.toggle_collapsed(fx.guid)
  end
  if fx.is_top_level then
    local n_top = reaper.TrackFX_GetCount(app.track)
    if ImGui.MenuItem(ctx, "Move left", nil, false, fx.top_index > 0) then
      move_fx(fx.top_index, fx.top_index - 1)
    end
    if ImGui.MenuItem(ctx, "Move right", nil, false, fx.top_index < n_top - 1) then
      move_fx(fx.top_index, fx.top_index + 2)
    end
  end
  ImGui.EndPopup(ctx)
end

-- Thin colour rules top and bottom, plus a chip carrying the track's own
-- colour and name. Enough to always know which track the panels belong to,
-- without a banner taking height away from the controls -- and bracketing
-- the window means the colour is in view wherever you happen to be
-- looking, including down at the track strip.
-- Forward: the view toggle and the double-click handlers all switch
-- views, and they are written above the function that does it.
local set_view

-- Switching views. The peak stores are keyed per strip, and the strips
-- that are about to disappear would otherwise hold their last reading
-- until you came back and found a meter frozen at a level from minutes
-- ago.
function set_view(mixer)
  C.MIXER_VIEW = mixer and true or false
  ext_set("mixer_view", C.MIXER_VIEW and "1" or "0")
  W.clear_levels()
  W.clear_rms()
  W.clear_peaks()
  W.clear_tips()
  -- A swipe that started in the view we are leaving has nothing left to
  -- paint onto.
  W.end_paint()
end

local function track_rule(dl, x, y, w)
  if not app.track then return end
  local col = U.track_colour(app.track, 0xff)
  if app.track == reaper.GetMasterTrack(0) then col = col or 0x8a90a0ff end
  -- Snapped to the nearest whole pixel, exactly as Track Analyser's trackRule
  -- does. A two-pixel rect starting on a half covers three rows with two
  -- of them at partial coverage; rounding also lands this and TA's rule
  -- on the same row when the two docked panes start half a pixel apart,
  -- which they usually do.
  y = math.floor(y + 0.5)
  ImGui.DrawList_AddRectFilled(dl, x, y, x + w, y + C.RULE_H,
    col or C.COL.panel_border, 0)
end

-- Bypasses every FX on the track at once (I_FXEN), which is a different
-- thing from bypassing one plugin and belongs where you can always see it
-- rather than inside any one panel.
-- `mid_y` is the vertical centre of the header bar. ImGui centres a menu
-- label in the bar itself, but the cursor inside a menu bar sits at the
-- TOP of the row, so anything drawn by hand has to be told where the
-- middle is or it rides high -- which is what had the track name and this
-- button sitting above the menus.
-- Channel view or mixer view. The icon shows the view you would GET,
-- because a button should say what it does rather than where you are.
local function view_toggle(ctx, mid_y)
  local to_mixer = not C.MIXER_VIEW
  if mid_y then
    local cx = ImGui.GetCursorScreenPos(ctx)
    ImGui.SetCursorScreenPos(ctx, cx, mid_y - C.ICON_SIZE * 0.5)
  end
  if W.icon_button(ctx, "viewtog", to_mixer and "mixer" or "channel",
      C.ICON_SIZE, false,
      to_mixer and "Mixer view \u{2014} every track's channel"
                or "Channel view \u{2014} this track's plugins") then
    set_view(to_mixer)
  end
end

local function fx_bypass_button(ctx, mid_y)
  if not app.track then return end
  local on = T.chain_bypassed(app.track)
  if mid_y then
    local cx = ImGui.GetCursorScreenPos(ctx)
    ImGui.SetCursorScreenPos(ctx, cx, mid_y - C.ICON_SIZE * 0.5)
  end
  if W.icon_button(ctx, "fxen", "power", C.ICON_SIZE, on,
      on and "FX chain bypassed \u{2014} click to enable"
          or "Bypass the whole FX chain",
      C.COL.bypass_on) then
    reaper.Undo_BeginBlock()
    reaper.SetMediaTrackInfo_Value(app.track, "I_FXEN", on and 1 or 0)
    reaper.Undo_EndBlock("ChannelView: toggle FX chain bypass", -1)
  end
  ImGui.SameLine(ctx)
  local tw, th = ImGui.CalcTextSize(ctx, "FX")
  local dl = ImGui.GetWindowDrawList(ctx)
  local cx, cy = ImGui.GetCursorScreenPos(ctx)
  local ty = (mid_y or (cy + th * 0.5)) - th * 0.5
  ImGui.DrawList_AddText(dl, cx, ty, on and C.COL.bypass_on or C.COL.header_dim, "FX")
  ImGui.Dummy(ctx, tw, th)
end

-- The track name sits in the middle of the header bar with its colour as
-- a chip beside it. Centred on the WINDOW rather than on whatever the
-- menus left over, so it doesn't shuffle sideways as menu labels change;
-- when that would run into either neighbour it is dropped rather than
-- drawn over them.
local function track_title(ctx, left_limit, right_limit, mid_y)
  if not app.track then return end
  local is_master = (app.track == reaper.GetMasterTrack(0))
  local name
  if is_master then
    name = "MASTER"
  else
    local _, n = reaper.GetSetMediaTrackInfo_String(app.track, "P_NAME", "", false)
    local num = math.floor(reaper.GetMediaTrackInfo_Value(app.track, "IP_TRACKNUMBER") or 0)
    n = U.trim(n)
    name = (n ~= "" and ("%d  %s"):format(num, n)) or ("Track " .. num)
  end
  name = U.truncate(name, 34)
  local col = U.track_colour(app.track, 0xff) or 0x555a66ff
  local sub = ("%d plugin%s"):format(#app.chain, #app.chain == 1 and "" or "s")

  local chip_w, gap = 9, 7
  local nw, th = ImGui.CalcTextSize(ctx, name)
  local sw     = ImGui.CalcTextSize(ctx, sub)
  local total  = chip_w + gap + nw + gap + sw

  local wx = ImGui.GetWindowPos(ctx)
  local ww = ImGui.GetWindowSize(ctx)
  local x  = wx + (ww - total) * 0.5
  if x < left_limit then x = left_limit end
  if x + total > right_limit then return end

  local _, cy = ImGui.GetCursorScreenPos(ctx)
  local y = (mid_y or (cy + th * 0.5)) - th * 0.5

  local dl = ImGui.GetWindowDrawList(ctx)
  ImGui.DrawList_AddRectFilled(dl, x, y + 1, x + chip_w, y + th - 1, col, 2.0)
  ImGui.DrawList_AddText(dl, x + chip_w + gap, y, C.COL.header_text, name)
  ImGui.DrawList_AddText(dl, x + chip_w + gap + nw + gap, y,
    C.COL.header_dim, sub)
end

-- ---------------------------------------------------------------------
-- menu bar
-- ---------------------------------------------------------------------

local DOCKS = {
  { "Floating", 0 }, { "Docker 1", -1 }, { "Docker 2", -2 },
  { "Docker 3", -3 }, { "Docker 4", -4 },
}

local function menu_bar()
  if not ImGui.BeginMenuBar(ctx) then return end

  if ImGui.BeginMenu(ctx, "View") then
    if ImGui.MenuItem(ctx, "Values under controls", nil, C.SHOW_VALUES) then
      C.SHOW_VALUES = not C.SHOW_VALUES
      ext_set("show_values", C.SHOW_VALUES and "1" or "0")
    end

    ImGui.Separator(ctx)

    -- Run at startup. Scanned from __startup.lua the first frame this
    -- menu is open rather than remembered in ExtState: the file is the
    -- truth, and a cached boolean is just something that can disagree
    -- with it after a hand edit. See TS_CV_Startup for why that file is
    -- treated as gingerly as it is.
    do
      if not SU.checked() then SU.scan() end
      local st, note = SU.state()
      if ImGui.MenuItem(ctx, "Run when REAPER starts", nil, SU.on(),
          st ~= "nocmd") then
        local ok, why
        if SU.on() then ok, why = SU.remove() else ok, why = SU.add() end
        if not ok then
          reaper.MB("__startup.lua was NOT changed.\n\n" .. tostring(why),
                    "ChannelView", 0)
        end
      end
      -- A note only when there is something the tick can't say: the
      -- command id isn't available yet, or the line is in __startup.lua
      -- but somebody else wrote it. "It worked" needs no caption.
      if note then
        ImGui.TextColored(ctx, C.COL.warn, "   " .. U.wrap_note(note, 52))
      end
    end
    if ImGui.BeginMenu(ctx, "Panel alignment") then
      if ImGui.MenuItem(ctx, "Left", nil, C.ROW_ALIGN == "left") then
        C.ROW_ALIGN = "left"; ext_set("row_align", C.ROW_ALIGN)
      end
      if ImGui.MenuItem(ctx, "Centred", nil, C.ROW_ALIGN == "centre") then
        C.ROW_ALIGN = "centre"; ext_set("row_align", C.ROW_ALIGN)
      end
      ImGui.EndMenu(ctx)
    end
    if ImGui.BeginMenu(ctx, "Control flow") then
      if ImGui.MenuItem(ctx, "Down, then across", nil, C.FLOW == "column") then
        C.FLOW = "column"; ext_set("flow", C.FLOW)
      end
      if ImGui.MenuItem(ctx, "Across, then down", nil, C.FLOW == "row") then
        C.FLOW = "row"; ext_set("flow", C.FLOW)
      end
      ImGui.EndMenu(ctx)
    end
    ImGui.Separator(ctx)
    if ImGui.BeginMenu(ctx, "Colour") then
      -- One hue drives the whole palette, so this can be brought into
      -- line with a REAPER theme without picking thirty colours. Bypass
      -- and warnings deliberately don't follow it -- see TS_CV_Config.
      ImGui.SetNextItemWidth(ctx, 190)
      local hch, hv = ImGui.SliderInt(ctx, "Hue", math.floor(C.BASE_HUE), 0, 359)
      if hch then
        C.BASE_HUE = hv
        C.build_palette()
        ext_set("base_hue", hv)
      end

      ImGui.SetNextItemWidth(ctx, 190)
      local tch, tv = ImGui.SliderDouble(ctx, "Tint", C.TINT, 0.0, 2.0, "%.2f")
      if tch then
        C.TINT = tv
        C.build_palette()
        ext_set("tint", string.format("%.3f", tv))
      end
      W.tip(ctx, "tint",
        "How far the greys lean toward the hue.\n0 is neutral grey, 1 is the default.",
        ImGui.IsItemHovered(ctx), ImGui.IsItemActive(ctx))

      -- a live swatch, so the slider isn't guesswork
      local dl = ImGui.GetWindowDrawList(ctx)
      local cx, cy = ImGui.GetCursorScreenPos(ctx)
      local sw, sh = 190, 14
      local keys = { "win_bg", "panel_bg", "header_bg", "knob_body",
                     "knob_ring", "label", "accent", "knob_fill_bi", "warn" }
      for i, k in ipairs(keys) do
        local x0 = cx + (i - 1) * (sw / #keys)
        ImGui.DrawList_AddRectFilled(dl, x0, cy, x0 + sw / #keys, cy + sh,
          C.COL[k] or 0, 0)
      end
      ImGui.Dummy(ctx, sw, sh + 2)

      ImGui.Separator(ctx)
      if ImGui.MenuItem(ctx, "Reset to default") then
        C.BASE_HUE, C.TINT = 219, 1.0
        C.build_palette()
        ext_set("base_hue", 219); ext_set("tint", "1.000")
      end
      ImGui.EndMenu(ctx)
    end

    ImGui.Separator(ctx)
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
    ImGui.EndMenu(ctx)
  else
    -- Closed: forget what we read, so the next opening reflects any edit
    -- made to __startup.lua in the meantime.
    SU.forget()
  end

  if ImGui.BeginMenu(ctx, "Layouts") then
    if ImGui.MenuItem(ctx, "Reload library from disk") then M.reload() end
    if ImGui.MenuItem(ctx, "Save library now") then M.save() end
    ImGui.Separator(ctx)
    if ImGui.MenuItem(ctx, "Show the library file") then
      -- Opens the containing folder; the file itself is plain text and
      -- safe to edit by hand while this is running (Reload picks it up).
      if reaper.CF_ShellExecute then
        reaper.CF_ShellExecute(script_dir)
      else
        reaper.MB(M.file_path(), "ChannelView layout library", 0)
      end
    end
    ImGui.Separator(ctx)
    ImGui.TextDisabled(ctx, U.truncate(M.file_path(), 48))
    ImGui.EndMenu(ctx)
  end

  -- Where the menus finished, so the centred title knows what it must
  -- not run into on the left -- and, from the last menu item's own
  -- rectangle, where the middle of the bar actually is. Asking ImGui
  -- beats computing it: whatever it does to lay a menu label out, this
  -- matches.
  local menus_right = ImGui.GetCursorScreenPos(ctx)
  local _, item_top = ImGui.GetItemRectMin(ctx)
  local _, item_bot = ImGui.GetItemRectMax(ctx)
  local mid_y = (item_top + item_bot) * 0.5

  -- FX chain bypass is pushed hard right; the title then gets whatever
  -- is between the two.
  local fx_tw = ImGui.CalcTextSize(ctx, "FX")
  local fx_w  = C.ICON_SIZE + 4 + fx_tw
  local avail = ImGui.GetContentRegionAvail(ctx)
  local fx_left = menus_right + avail
  if app.track and avail > fx_w + 12 then
    ImGui.SameLine(ctx, 0, avail - fx_w)
    fx_left = ImGui.GetCursorScreenPos(ctx)
    fx_bypass_button(ctx, mid_y)
  end

  -- The view toggle sits left of the FX bypass, which means measuring
  -- back from where the bypass started rather than from the right edge.
  do
    local tw = C.ICON_SIZE + 10
    if fx_left - menus_right > tw + 40 then
      ImGui.SameLine(ctx, 0, 0)
      ImGui.SetCursorScreenPos(ctx, fx_left - tw, mid_y - C.ICON_SIZE * 0.5)
      view_toggle(ctx, mid_y)
      fx_left = fx_left - tw
    end
  end

  track_title(ctx, menus_right + 12, fx_left - 12, mid_y)

  -- Double-clicking the header switches views, the same as the toggle.
  -- Only where nothing else lives: IsAnyItemHovered catches the menus,
  -- the toggle and the bypass, so this is the bar's own empty space and
  -- the track name drawn on it, which is not an item at all.
  --
  -- The bar is centred on mid_y and starts at the window top, so its
  -- height falls out of that rather than needing MenuBarHeight -- which
  -- ImGui does not report, as the header arithmetic found out the hard
  -- way.
  if ImGui.IsMouseDoubleClicked(ctx, ImGui.MouseButton_Left)
     and not ImGui.IsAnyItemHovered(ctx) then
    local wx, wy = ImGui.GetWindowPos(ctx)
    local ww = ImGui.GetWindowSize(ctx)
    local mx, my = ImGui.GetMousePos(ctx)
    if mx >= wx and mx <= wx + ww and my >= wy and my <= 2 * mid_y - wy then
      app.header_dbl = true
    end
  end

  ImGui.EndMenuBar(ctx)
end

-- ---------------------------------------------------------------------
-- panel row
-- ---------------------------------------------------------------------

-- A dashed placeholder at the end of the row. Deliberately not styled as
-- a panel: it isn't a plugin, and shouldn't read as an empty one.
local function add_tile(h)
  local w = C.ADD_TILE_W
  local dl = ImGui.GetWindowDrawList(ctx)
  local x, y = ImGui.GetCursorScreenPos(ctx)
  local pressed = ImGui.InvisibleButton(ctx, "addfx", w, h)
  local hovered = ImGui.IsItemHovered(ctx)

  local col = hovered and C.COL.accent or C.COL.panel_border
  -- hand-drawn dashes: ImGui's rect has no dashed stroke
  local dash, gap = 5, 4
  local function dashed_h(yy)
    local px = x
    while px < x + w do
      ImGui.DrawList_AddLine(dl, px, yy, math.min(px + dash, x + w), yy, col, 1.0)
      px = px + dash + gap
    end
  end
  local function dashed_v(xx)
    local py = y
    while py < y + h do
      ImGui.DrawList_AddLine(dl, xx, py, xx, math.min(py + dash, y + h), col, 1.0)
      py = py + dash + gap
    end
  end
  dashed_h(y); dashed_h(y + h - 1); dashed_v(x); dashed_v(x + w - 1)

  local sz = 18
  W.ICONS.plus(dl, x + (w - sz) * 0.5, y + h * 0.5 - sz * 0.5, sz,
    hovered and C.COL.icon_hot or C.COL.icon)

  W.tip(ctx, "addfx", "Add a plugin to the end of the chain", hovered, false)
  return pressed
end

local function panel_row(row_h, row_w)
  local pr_x, pr_y = ImGui.GetCursorPos(ctx)
  local ok = ImGui.BeginChild(ctx, "panelrow", row_w or 0, row_h, 0,
    ImGui.WindowFlags_HorizontalScrollbar | ImGui.WindowFlags_NoScrollWithMouse)
  if ok then
    local _, inner_h = ImGui.GetContentRegionAvail(ctx)
    app.panel_rects = {}

    -- The row's empty space is a double-click target: back to mixer
    -- view. Submitted first, so every panel and control drawn after it
    -- takes precedence -- this only ever catches the gaps.
    do
      local bw, bh = ImGui.GetContentRegionAvail(ctx)
      if bw > 0 and bh > 0 then
        local bx, by = ImGui.GetCursorScreenPos(ctx)
        W.allow_overlap(ctx)
        ImGui.InvisibleButton(ctx, "rowbg", bw, bh)
        if ImGui.IsItemHovered(ctx)
           and ImGui.IsMouseDoubleClicked(ctx, ImGui.MouseButton_Left) then
          app.row_dbl = true
        end
        ImGui.SetCursorScreenPos(ctx, bx, by)
      end
    end

    if not app.track then
      ImGui.TextDisabled(ctx, "Select a track.")
    else
      -- Centring needs the row's full width up front, so measure first.
      -- Only worth it when everything fits; once the panels overflow they
      -- pack left and the row scrolls, which is the only sane behaviour.
      if C.ROW_ALIGN == "centre" and #app.chain > 0 then
        local total = C.PANEL_GAP + C.ADD_TILE_W
        for i, fx in ipairs(app.chain) do
          local lay, k = layout_for(fx)
          local has_meter = M.meter_of(lay) ~= nil
                            and T.reports_gr(app.track, fx.addr, fx.guid)
          total = total + P.width(lay.controls or {}, inner_h,
                                  St.is_collapsed(fx.guid), has_meter, k)
          if i > 1 then total = total + C.PANEL_GAP end
        end
        local avail_w = ImGui.GetContentRegionAvail(ctx)
        if total < avail_w then
          ImGui.SetCursorPosX(ctx, ImGui.GetCursorPosX(ctx) + (avail_w - total) * 0.5)
        end
      end

      if #app.chain == 0 then
        ImGui.TextDisabled(ctx, "No plugins on this track yet \u{2014}")
        ImGui.SameLine(ctx)
      end
      for i, fx in ipairs(app.chain) do
        if i > 1 then ImGui.SameLine(ctx, 0, C.PANEL_GAP) end
        local px, py = ImGui.GetCursorScreenPos(ctx)
        local layout, key = layout_for(fx)
        local is_src = app.drag ~= nil and app.drag.guid == fx.guid
        local w, req = P.draw(ctx, app.track, fx, layout, key, inner_h, i, is_src)

        app.panel_rects[#app.panel_rects + 1] = {
          chain_i   = i,
          x         = px,
          y         = py,
          w         = w,
          top_index = fx.is_top_level and fx.top_index or nil,
        }

        if req.toggle_bypass then
          T.set_enabled(app.track, fx.addr, not T.get_enabled(app.track, fx.addr))
        end
        if req.toggle_float then
          T.toggle_float(app.track, fx.addr)
        end
        if req.toggle_collapse then
          St.toggle_collapsed(fx.guid)
        end
        if req.begin_drag and not app.drag and fx.is_top_level then
          app.drag = { chain_i = i, guid = fx.guid, top_index = fx.top_index }
        end
        if req.open_menu then
          app.menu_fx = i
          app.open_panel_menu = true
        end
        if req.open_editor then
          E.open(app.track, fx, key, layout)
        end
        if req.ctx_control then
          app.ctl_menu = { fx = i, ctl = req.ctx_control }
          local c = layout.controls and layout.controls[req.ctx_control]
          local pn = ""
          if c and c.param then
            _, pn = reaper.TrackFX_GetParamName(app.track, fx.addr, c.param, "")
          end
          app.rename_buf = (c and M.get_alias(key, c.param)) or pn or ""
          app.open_ctl_menu = true
        end
      end

      -- Trailing tile: adds to the END of the chain. Inserting at a
      -- specific point is the panel menu's "Insert plugin before/after",
      -- which knows which slot it's next to.
      if #app.chain > 0 then ImGui.SameLine(ctx, 0, C.PANEL_GAP) end
      if add_tile(inner_h) then B.open_menu(nil) end
    end

    -- Wheel scrolls the row sideways -- but only when no control under the
    -- pointer wanted it, otherwise turning a knob would drag the whole row
    -- along with it. A tilt wheel or trackpad's horizontal axis always
    -- scrolls, since no control uses that.
    if ImGui.IsWindowHovered(ctx, ImGui.HoveredFlags_ChildWindows) then
      local wy, wx = ImGui.GetMouseWheel(ctx)
      local d = 0
      if wx ~= 0 then d = wx
      elseif wy ~= 0 and not W.wheel_taken() then d = wy end
      if d ~= 0 then
        ImGui.SetScrollX(ctx, ImGui.GetScrollX(ctx) - d * C.WHEEL_SCROLL_PX)
      end
    end

    -- Drop marker, drawn after the panels so it sits above them.
    if app.drag then
      local mx = ImGui.GetMousePos(ctx)
      local gap, line_x = gap_under(mx)
      app.drop_gap = gap
      if line_x then
        local dl = ImGui.GetWindowDrawList(ctx)
        local wy = select(2, ImGui.GetWindowPos(ctx))
        local wh = select(2, ImGui.GetWindowSize(ctx))
        ImGui.DrawList_AddRectFilled(dl, line_x - 1.5, wy + 2,
          line_x + 1.5, wy + wh - 2, C.COL.drop_marker, 1.0)
      end
      if not ImGui.IsMouseDown(ctx, ImGui.MouseButton_Left) then
        if app.drop_gap then move_fx(app.drag.top_index, app.drop_gap) end
        app.drag, app.drop_gap = nil, nil
      end
    end

    ImGui.EndChild(ctx)
  else
    -- Culled: still occupy the space, or the parent's bounds
    -- never grow past it. See W.child_skipped.
    W.child_skipped(ctx, row_w or 0, row_h, pr_x, pr_y)
  end
end

-- ---------------------------------------------------------------------
-- main loop
-- ---------------------------------------------------------------------

-- Forward declaration: frame() re-arms the loop through the wrapper, not
-- through itself, so every iteration goes through the error trap below.
local safe_frame

local function frame()
  W.begin_frame()
  P.begin_frame()
  follow_selection()

  local cc = reaper.GetProjectStateChangeCount(0)
  if cc ~= app.change_count then
    app.change_count = cc
    rescan(true)
  end
  if chain_is_stale() then rescan(true) end

  rescan(false)

  ImGui.SetNextWindowSize(ctx, 1100, 300, ImGui.Cond_FirstUseEver)
  if dock_id ~= 0 then
    ImGui.SetNextWindowDockID(ctx, dock_id, ImGui.Cond_FirstUseEver)
  end

  ImGui.PushStyleColor(ctx, ImGui.Col_WindowBg, C.COL.win_bg)
  -- Read BEFORE our own ItemSpacing goes on the stack: what the header
  -- arithmetic wants is the spacing Track Analyser gets, which is the
  -- default. There is no GetStyleVar in this build, but the difference
  -- between a text line with and without spacing is exactly it.
  local def_isy = ImGui.GetTextLineHeightWithSpacing(ctx)
                  - ImGui.GetTextLineHeight(ctx)

  ImGui.PushStyleVar(ctx, ImGui.StyleVar_ItemSpacing, 4, 4)
  -- ImGui works the menu bar's height out inside Begin, from FramePadding,
  -- so a taller header has to be asked for BEFORE the window opens. It
  -- stays pushed across the bar itself -- that is what keeps the menu
  -- labels centred in it -- and comes off again before any panel is drawn,
  -- so nothing below the header inherits the header's padding.
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_FramePadding, 6, C.MENU_PAD_Y)

  local wflags = ImGui.WindowFlags_MenuBar | ImGui.WindowFlags_NoScrollWithMouse
  -- C.WIN_NO_SCROLLBAR is not decoration: the header measurement below
  -- relies on there being no bottom decoration to subtract.
  if C.WIN_NO_SCROLLBAR then wflags = wflags | ImGui.WindowFlags_NoScrollbar end

  local visible, open = ImGui.Begin(ctx, C.WIN_TITLE, true, wflags)

  if visible then
    local d = ImGui.GetWindowDockID(ctx)
    if d ~= dock_id then dock_id = d; ext_set("dock", d) end
    menu_bar()
  end
  ImGui.PopStyleVar(ctx)

  if app.header_dbl then
    app.header_dbl = false
    set_view(not C.MIXER_VIEW)
  end

  if visible then
    -- trackrow's own horizontal WindowPadding (see C.TRACKROW_PAD_Y):
    -- read off the main window below, alongside win_pad (its vertical
    -- counterpart), since nothing between here and "trackrow" ever
    -- pushes a different one. Horizontal has no menu bar to cancel out,
    -- so unlike win_pad this is usable as-is: GetCursorStartPos().x IS
    -- WindowPadding.x, no arithmetic required.
    local win_pad_x = 0
    do  -- the track's colour as a hairline across the top of the panel row
      local dl = ImGui.GetWindowDrawList(ctx)
      local cx, cy = ImGui.GetCursorScreenPos(ctx)
      local rule_w = ImGui.GetContentRegionAvail(ctx)
      -- Where Track Analyser puts its rule. TS_TrackAnalyser.lua pushes no
      -- WindowPadding, ItemSpacing or FramePadding of its own, so its
      -- rule sits at WindowPadding.y + a frame-height header row +
      -- ItemSpacing.y below the window top.
      --
      -- WindowPadding.y is not available through GetStyleVar in this
      -- build, and there is no fixed value to assume in its place:
      -- ReaImGui's own defaults don't match Dear ImGui's, and its menu
      -- bar isn't FontSize + 2*FramePadding either, so neither an
      -- assumed constant nor a MenuBarHeight-based estimate holds up.
      --
      -- So it is MEASURED, from three things the window will tell us:
      --
      --   start  = GetCursorStartPos().y = WindowPadding.y + decorations
      --   avail  = the content height, = Size.y - 2*WindowPadding.y
      --                                      - decorations
      --   Size.y - avail - start = WindowPadding.y
      --
      -- The decorations -- title bar, menu bar -- cancel, which is the
      -- whole point: their height never has to be known. There is no
      -- bottom decoration to worry about because this window is created
      -- with NoScrollbar.
      local _, wy = ImGui.GetWindowPos(ctx)
      local _, wh = ImGui.GetWindowSize(ctx)
      local start_x, start_y = ImGui.GetCursorStartPos(ctx)
      local _, avail_h = ImGui.GetContentRegionAvail(ctx)
      local win_pad = wh - avail_h - start_y
      win_pad_x = start_x

      local ry = wy + win_pad + ImGui.GetFrameHeight(ctx) + def_isy
                 + C.HEADER_NUDGE
      -- Clamped to the WINDOW position, never to the content start: the
      -- content area begins below the menu bar, but the rule is meant
      -- to sit a few pixels up into the menu bar's lower margin --
      -- empty space under the labels -- which is exactly where Track
      -- Analyser's own rule lands. Clamping to content start instead
      -- would push the rule down below the menu bar.
      ry = math.max(ry, wy)

      track_rule(dl, cx, ry, rule_w)
      -- step the cursor past the rule so the panel borders clear it
      -- The panels, though, must start below the content boundary: the
      -- rule may overlap the menu bar, the panels may not.
      ImGui.SetCursorScreenPos(ctx, cx,
        math.max(ry + C.RULE_H + C.ROW_TOP_GAP, wy + start_y))
      -- Moving the cursor is a promise to draw something there. The
      -- panels below normally keep it, but any of them can be culled,
      -- and ImGui only complains at End -- hundreds of lines away from
      -- the line it is actually about. This keeps the promise outright.
      ImGui.Dummy(ctx, 0, 0)
    end

    local _, avail_h = ImGui.GetContentRegionAvail(ctx)

    -- The Channel/plugin-row/Sends panels (channel view) and a mixer
    -- strip's own body (mixer view, inside MX.draw_row's "trackrow"
    -- child) both want to end up the SAME height for the SAME track,
    -- or the strip visibly resizes every time you switch views.
    --
    -- What eats the difference between avail_h and what a strip
    -- actually gets is "trackrow" itself: WindowPadding top and bottom
    -- (C.TRACKROW_PAD_Y, trimmed below ReaImGui's own default -- see
    -- that constant), plus its own horizontal scrollbar's height,
    -- reserved ALWAYS now, not only on a frame the row's content
    -- actually overflows (see MX.row_pad_y) -- so this is one constant,
    -- the same in both views,
    -- rather than something computed from trackrow's own content width
    -- versus the window's -- that bookkeeping isn't available here
    -- anyway, since "trackrow" doesn't exist until after these panels
    -- do, so their height has to be decided before it can be asked.
    --
    -- MX.row_pad_y is called exactly HERE, once per frame, and its
    -- result is handed into every MX.draw_row call below rather than
    -- measured a second time in there: row_pad_y's probe is a stable,
    -- reused child id, and reopening the same child id twice in one
    -- frame is undefined and can double-count the reserved padding.
    -- One call, one number, handed down.
    local child_pad_y = MX.row_pad_y(ctx, win_pad_x)

    -- There is a SECOND gap neither child_pad_y nor either panel's own
    -- height accounts for: CH.draw / panel_row / SD.draw sit on one
    -- SameLine'd line, but nothing SameLine's that line with
    -- MX.draw_row's "trackrow" child below it -- so ImGui inserts its
    -- own ItemSpacing.y between them, same as it would between any two
    -- ordinary stacked widgets. Mixer view never pays this: it hands
    -- MX.draw_row the whole avail_h as a single item, nothing stacked
    -- under it. Channel view splits avail_h between two stacked items,
    -- so this gap has to come out of that split too, or the second
    -- item (the track row, scrollbar included) lands short of the
    -- window's bottom edge by however many pixels this is -- exactly
    -- the "padded up" mismatch against mixer view.
    --
    -- No GetStyleVar here either, so it's measured the same way as
    -- child_pad_y: a zero-height Dummy has no height of its own, so the
    -- entire distance the cursor advances past it IS ItemSpacing.y.
    -- Restored immediately after, like the probe above -- this must be
    -- invisible to everything drawn below it.
    local spacing_y = 0
    do
      local sx0, sy0 = ImGui.GetCursorPos(ctx)
      ImGui.Dummy(ctx, 0, 0)
      local _, sy1 = ImGui.GetCursorPos(ctx)
      spacing_y = sy1 - sy0
      ImGui.SetCursorPos(ctx, sx0, sy0)
    end

    -- The standalone name row (channel view) needs a total height that
    -- lands ITS OWN "trackrow" child at exactly the height mixer view's
    -- gets for the same track -- not merely enough for the name button
    -- (STRIP_H - 8 tall, see name_button) to fit inside it without a
    -- scrollbar.
    --
    -- What gets subtracted here is spacing_y, not the button's own
    -- height offset (a coincidentally similar constant): row_h below
    -- spends spacing_y once, to clear the gap ImGui puts above this row
    -- (see spacing_y above), and strip_h has to give back that same
    -- amount for row_h + spacing_y + strip_h to land on avail_h
    -- exactly, matching mixer view's total for the same track.
    local strip_h = (C.STRIP_H - spacing_y) + child_pad_y

    -- And row_h (the Channel/plugin-row/Sends height) is everything
    -- left in avail_h once strip_h AND the ItemSpacing.y between the
    -- two of them are both spent -- so row_h + spacing_y + strip_h
    -- lands on avail_h exactly, the same total mixer view gets, split
    -- differently rather than shrunk.
    local row_h = math.max(C.CELL_H + C.HEADER_H + C.PANEL_PAD * 2,
                           avail_h - spacing_y - strip_h)
    -- Channel pinned left, Sends pinned right, the plugin row scrolling
    -- between them. Both pinned panels are measured first so the row in
    -- the middle knows what is left for it.
    local full_w = ImGui.GetContentRegionAvail(ctx)
    local ch_w   = CH.width(CH.is_collapsed())
    local sd_w   = SD.width_for(app.track, row_h)
    local mid_w  = math.max(80, full_w - ch_w - sd_w - C.PANEL_GAP * 2)

    -- A double-click on a NAME BUTTON opens that track in channel view,
    -- in either branch below -- the button means the same thing whether
    -- it's sitting under a strip or on its own. One place to act on it,
    -- since MX.draw_row hands it back the same way from both views.
    local function open_from_name(tr)
      app.track = tr
      S.request_scroll()
      rescan(true)
      set_view(false)
    end

    if C.MIXER_VIEW then
      -- Mixer view takes the whole upper area. The track row underneath
      -- -- strips and their name buttons together, one scrolling child
      -- -- stays: it is the one thing both views share, and losing it
      -- would make switching feel like changing windows rather than
      -- changing what you are looking at.
      local open_it, want_view, dbl_track =
        MX.draw_row(ctx, avail_h, app.track, true, child_pad_y, win_pad_x)
      if want_view then
        set_view(false)
      end
      if open_it then
        reaper.SetOnlyTrackSelected(open_it)
        reaper.UpdateArrange()
        app.track = open_it
        S.request_scroll()
        rescan(true)
        set_view(false)
      elseif dbl_track then
        open_from_name(dbl_track)
      end
    else
      CH.draw(ctx, app.track, row_h)
      ImGui.SameLine(ctx, 0, C.PANEL_GAP)
      panel_row(row_h, mid_w)
      ImGui.SameLine(ctx, 0, C.PANEL_GAP)
      local _, sd_req = SD.draw(ctx, app.track, row_h)
      if sd_req and sd_req.changed then rescan(true) end

      -- Double-clicking the Channel panel's background -- not the fader,
      -- which still means unity -- goes back to the mixer.
      if CH.want_mixer then
        CH.want_mixer = false
        set_view(true)
      end
      if app.row_dbl then
        app.row_dbl = false
        set_view(true)
      end

      -- The track row, on its own now -- same window id as mixer view's
      -- row, just without the strips above the names, so the scroll
      -- position it lands on here is exactly the one mixer view left it
      -- at. Double-clicking its empty background (past the last name
      -- button) is the mirror of mixer view's own empty-space
      -- double-click: back to mixer, same as double-clicking the
      -- Channel panel or the empty plugin row already do.
      local _, want_mixer, dbl_track =
        MX.draw_row(ctx, strip_h, app.track, false, child_pad_y, win_pad_x)
      if want_mixer then
        set_view(true)
      elseif dbl_track then
        open_from_name(dbl_track)
      end
    end

    do  -- and the matching rule along the bottom edge of the window
      local dl = ImGui.GetWindowDrawList(ctx)
      local wx, wy = ImGui.GetWindowPos(ctx)
      local ww, wh = ImGui.GetWindowSize(ctx)
      track_rule(dl, wx + 6, wy + wh - 5, ww - 12)
    end

    if app.open_panel_menu then ImGui.OpenPopup(ctx, "panelmenu"); app.open_panel_menu = false end
    if app.open_ctl_menu   then ImGui.OpenPopup(ctx, "ctlmenu");   app.open_ctl_menu   = false end
    panel_menu()
    control_menu()

    E.draw(ctx, app.track)
    if SD.draw_menu(ctx, app.track) then rescan(true) end
    if SD.draw_ctx(ctx, app.track) then rescan(true) end
    if B.draw_menu(ctx, app.track) then rescan(true) end
    if B.draw(ctx, app.track) then rescan(true) end

    -- Last thing in the frame, on the foreground draw list: a tooltip
    -- that is following a control being dragged has to sit above every
    -- panel, popup and menu regardless of what was drawn when.
    W.draw_tip(ctx)
    ImGui.End(ctx)
  end

  -- The style pushes happened before Begin, so they unwind either way.
  ImGui.PopStyleVar(ctx, 1)
  ImGui.PopStyleColor(ctx)

  if open and not app.want_quit then
    reaper.defer(safe_frame)
  else
    M.save()
    SC.save()
  end
end

-- A runtime error inside a deferred function is reported by REAPER with
-- only the file and line it happened ON -- which, when a nil is handed to
-- a drawing helper, names the helper rather than the caller that produced
-- the nil. The loop runs through xpcall instead: the console gets a full
-- traceback naming every frame on the way down, the layouts are saved,
-- and the loop stops rather than throwing the same error sixty times a
-- second.
function safe_frame()
  local ok, err = xpcall(frame, function(e)
    return debug.traceback(tostring(e), 2)
  end)
  if ok then return end
  M.save(); SC.save()
  reaper.ShowConsoleMsg(
    "\n--- ChannelView stopped on an error -------------------------\n" ..
    tostring(err) ..
    "\n-------------------------------------------------------------\n")
end

reaper.atexit(function() M.save(); SC.save() end)
reaper.defer(safe_frame)
