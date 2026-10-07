-- @description ChannelView -- docked channel strip: one editable control panel per plugin
-- @author Tim Shadgett
-- @version 1.9.0
-- @changelog
--  Parallel FX and FX containers: brackets over the panels, Route in
--  series / parallel / parallel with MIDI merged, put in a new container,
--  container menu (bypass, add into, unpack, remove, save as chain), drag
--  into and out of containers.
--  Parameter modulation from a control's menu, with marks on modulated
--  controls. Save and delete FX chains. Edit REAPER's FX folders from the
--  add-plugin menu. Collapsed plugins come in collapsed.
--  Faders of any shape (up or across, length, half thickness) placed among
--  the controls as merged cells; Slim fader style. XY pad and concentric
--  knob. Copy and paste a control's style. Matte knob caps. Buttons show
--  the plugin's own choice names. Edit parameters reorganised into a
--  settings column.
--  The web page has the same: restart the web companion script after
--  updating.
-- @license MIT
-- @provides
--  [main]   TS_CV_Diag.lua
--  [main]   TS_ChannelView_TCP.lua
--  [main]   TS_ChannelView_ToggleMixer.lua
--  [main]   TS_ChannelView_Web.lua
--  [main]   TS_ChannelView_Web_Startup.lua
--  [webinterface] TS_ChannelView.html
--  [webinterface] TS_ChannelView.webapp.json
--  [webinterface] TS_ChannelView-192.png
--  [webinterface] TS_ChannelView-512.png
--  [webinterface] TS_ChannelView-maskable.png
--  [nomain] TS_CV_Actions.lua
--  [nomain] TS_CV_Arrange.lua
--  [nomain] TS_CV_Toolbar.lua
--  [nomain] TS_CV_Browser.lua
--  [nomain] TS_CV_Chains.lua
--  [nomain] TS_CV_ColourPick.lua
--  [nomain] TS_CV_Channel.lua
--  [nomain] TS_CV_Config.lua
--  [nomain] TS_CV_Editor.lua
--  [nomain] TS_CV_Envelopes.lua
--  [nomain] TS_CV_EQPanel.lua
--  [nomain] TS_CV_Focus.lua
--  [nomain] TS_CV_FXIndex.lua
--  [nomain] TS_CV_FXTree.lua
--  [nomain] TS_CV_Gang.lua
--  [nomain] TS_CV_HwOut.lua
--  [nomain] TS_CV_Icons.lua
--  [nomain] TS_CV_Inputs.lua
--  [nomain] TS_CV_Lanes.lua
--  [nomain] TS_CV_Mappings.lua
--  [nomain] TS_CV_Mixer.lua
--  [nomain] TS_CV_Panel.lua
--  [nomain] TS_CV_ReaEQ.lua
--  [nomain] TS_CV_Presets.lua
--  [nomain] TS_CV_PresetUI.lua
--  [nomain] TS_CV_Receives.lua
--  [nomain] TS_CV_Search.lua
--  [nomain] TS_CV_Sends.lua
--  [nomain] TS_CV_Share.lua
--  [nomain] TS_CV_Startup.lua
--  [nomain] TS_CV_State.lua
--  [nomain] TS_CV_Steps.lua
--  [nomain] TS_CV_Taps.lua
--  [nomain] TS_CV_Tiles.lua
--  [nomain] TS_CV_Trace.lua
--  [nomain] TS_CV_TrackMenu.lua
--  [nomain] TS_CV_TrackOps.lua
--  [nomain] TS_CV_TrackStrip.lua
--  [nomain] TS_CV_Util.lua
--  [nomain] TS_CV_Widgets.lua
--  [nomain] TS_CV_WebLink.lua
--  [effect] TS_TrackProbe.jsfx
-- @about
--  A dockable window showing one panel per plugin on the selected track.
--  Each panel carries a float button, a bypass button and a set of knobs
--  and buttons wired straight to that plugin's parameters -- what you
--  assign to a panel is remembered per plugin, so the same plugin always
--  comes up looking the same wherever it turns up.
--
--  On a tablet: TS_ChannelView_Web.lua and the TS_ChannelView.html page put
--  the same panels in a browser, through REAPER's own web interface.
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

-- ImGui asserts on an invisible button of zero width or height, and
-- stops the script. A window docked very short (or very narrow) leaves
-- some of them -- a mixer strip's background, a row's -- with no room at
-- all, so a zero is made the smallest size there is instead: that one
-- pixel can't be seen or clicked, but nothing stops.
do
  local invisible = ImGui.InvisibleButton
  ImGui.InvisibleButton = function(c, id, w, h, ...)
    if w == 0 then w = 1 end
    if h == 0 then h = 1 end
    return invisible(c, id, w, h, ...)
  end
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
local PU = require("TS_CV_PresetUI")
local LS = require("TS_CV_Share")
local SC = require("TS_CV_Steps")
local CH = require("TS_CV_Channel")
local SD = require("TS_CV_Sends")
local RV = require("TS_CV_Receives")
local MX = require("TS_CV_Mixer")
local SU = require("TS_CV_Startup")
local WL = require("TS_CV_WebLink")
local TM = require("TS_CV_TrackMenu")
local TO = require("TS_CV_TrackOps")
local CP = require("TS_CV_ColourPick")
local FO = require("TS_CV_Focus")
local IC = require("TS_CV_Icons")
local CN = require("TS_CV_Chains")
local TP = require("TS_CV_Taps")
local RQ = require("TS_CV_ReaEQ")

W.attach(ImGui); P.attach(ImGui); E.attach(ImGui); S.attach(ImGui); B.attach(ImGui)
CH.attach(ImGui); SD.attach(ImGui); RV.attach(ImGui); MX.attach(ImGui); TM.attach(ImGui); IC.attach(ImGui)
CN.attach(ImGui); LS.attach(ImGui)

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
  state_buf    = { "", "" },   -- a toggle's state names, being edited
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
  panel_rects  = {},    -- per-frame {chain_i, x, y, w}
  brackets     = {},    -- T.groups: containers and parallel runs over the row
  brk_rows     = 0,     -- ...and how many rows of strip they need
  box_for      = nil,   -- the container node the container menu is for
  open_box_menu = false,
}

local function ext_get(k, default)
  local v = reaper.GetExtState(C.EXT_SECT, k)
  if v == "" then return default end
  return v
end

local function ext_set(k, v)
  reaper.SetExtState(C.EXT_SECT, k, tostring(v), true)
end

-- ---------------------------------------------------------------------
-- THE SHARED PALETTE
--
--   Hue and tint are one choice for the whole TS_ family, not one per
--   tool, so they live in their own ExtState section rather than in any
--   one tool's. Before this they lived in ChannelView's section and the
--   TCP window, TS_Visualizer and its editor all reached across into it
--   -- which worked only because ChannelView happened to be the one that
--   owned them, and made every other tool depend on a name that is none
--   of its business.
--
--   Reading falls through to the old location once, so an existing
--   setting survives the update instead of everybody's colours snapping
--   back to stock. Nothing anywhere returns a default: nil means "no
--   shared setting", and each tool keeps its own, which is what lets any
--   of them run on its own.
-- ---------------------------------------------------------------------
local PAL_SECT   = "TS_Palette"
local PAL_LEGACY = "TS_ChannelView"

local function pal_get()
  local h = reaper.GetExtState(PAL_SECT, "base_hue")
  local t = reaper.GetExtState(PAL_SECT, "tint")
  if h == "" then h = reaper.GetExtState(PAL_LEGACY, "base_hue") end
  if t == "" then t = reaper.GetExtState(PAL_LEGACY, "tint") end
  return tonumber(h), tonumber(t)
end

local function pal_set(h, t)
  reaper.SetExtState(PAL_SECT, "base_hue", tostring(math.floor(h)), true)
  reaper.SetExtState(PAL_SECT, "tint", string.format("%.3f", t), true)
end

local dock_id = tonumber(ext_get("dock", "0")) or 0
C.SHOW_VALUES = ext_get("show_values", C.SHOW_VALUES and "1" or "0") == "1"
C.WHEEL_CONTROLS = ext_get("wheel_controls", "1") == "1"
C.set_cell_w(ext_get("cell_w", tostring(C.CELL_W_DEFAULT)))
-- (saved under its old name, Faceplate texture, so the choice carries over)
C.EFFECT_3D = ext_get("plate_texture", C.EFFECT_3D and "1" or "0") == "1"
C.PRESET_BAR = ext_get("preset_bar", C.PRESET_BAR and "1" or "0") == "1"
-- Which of the two views is up. Persisted, because reopening the window
-- into the view you were not in is a small daily annoyance.
C.MIXER_VIEW  = ext_get("mixer_view", "0") == "1"
C.FLOW        = ext_get("flow", C.FLOW)
C.ROW_ALIGN   = ext_get("row_align", C.ROW_ALIGN)
do
  local h, t = pal_get()
  C.BASE_HUE = h or C.BASE_HUE
  C.TINT     = t or C.TINT
end
C.FOCUS_BACK  = ext_get("focus_back", "1") == "1"
C.TRACK_ICONS = ext_get("track_icons", "0") == "1"
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
  if moved and app.track and app.scan_track == app.track then
    -- A plugin that has just turned up on the track being watched starts
    -- the way you last left that plugin (St.last_fold). Not on a track
    -- change or a project load: those are plugins that were already there.
    local had = {}
    for _, fx in ipairs(app.chain) do had[fx.guid] = true end
    for _, fx in ipairs(list) do
      if not had[fx.guid] and fx.guid ~= "" and not St.has_collapsed(fx.guid) then
        if St.last_fold(U.plugin_key(fx.name)) then St.set_collapsed(fx.guid, true) end
      end
    end
  end
  app.scan_track = app.track
  if force or moved then
    app.chain, app.chain_hash = list, h
    app.brackets, app.brk_rows = T.groups(list)
  end
  if moved then
    -- Menus hold an INDEX into the old chain, so they can't survive it
    -- changing shape.
    app.menu_fx, app.ctl_menu, app.drag, app.box_for = nil, nil, nil, nil
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
    app.brackets, app.brk_rows = {}, 0
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

-- Moving a plugin, or a whole container, to insertion point `gap` of the
-- level `parent` ({} = the chain itself; see T.move). Anywhere in the
-- chain, into and out of containers too: REAPER 7 documents how a slot
-- inside a container is addressed, and T.move works the address out from
-- the chain as it is at that moment.
local function move_to(src_path, parent, gap, what)
  if not app.track or not src_path then return end
  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)
  local done = T.move(app.track, src_path, parent, gap)
  reaper.PreventUIRefresh(-1)
  reaper.Undo_EndBlock("ChannelView: move " .. (what or "plugin"), -1)
  if done then rescan(true) end
end

-- One slot left (-1) or right (+1) within its own level.
local function nudge(path, dir, what)
  local parent, i = T.parent_of(path)
  move_to(path, parent, dir < 0 and i - 1 or i + 2, what)
end

-- Collapsing or expanding a panel: this instance, and how the next one
-- of this plugin to be inserted starts.
local function set_fold(fx, on)
  St.set_collapsed(fx.guid, on)
  St.remember_fold(U.plugin_key(fx.name), on)
end
local function toggle_fold(fx) set_fold(fx, not St.is_collapsed(fx.guid)) end

-- Removing a plugin, wherever it sits. No confirmation prompt -- it's a
-- single undo step, same as deleting from REAPER's own FX chain window.
local function remove_fx(fx)
  if not app.track or not fx then return end
  reaper.Undo_BeginBlock()
  reaper.TrackFX_Delete(app.track, fx.addr)
  reaper.Undo_EndBlock("ChannelView: remove " .. U.fx_label(fx), -1)
  app.menu_fx, app.ctl_menu = nil, nil
  rescan(true)
end

-- REAPER's parallel setting for a plugin or container: 0 in series, 1
-- alongside the one before, 2 alongside it with its MIDI merged too.
local function set_parallel(addr, v, what)
  if not app.track then return end
  reaper.Undo_BeginBlock()
  T.set_parallel(app.track, addr, v)
  reaper.Undo_EndBlock("ChannelView: " .. (v == 0 and "run " .. what .. " in series"
                                       or "run " .. what .. " in parallel"), -1)
  rescan(true)
end

-- Where a dragged panel would land, from the panel rectangles recorded
-- while drawing. The panel under the pointer decides: its left half puts
-- the dragged one just before it, its right half just after it -- in
-- whatever container IT is in. So the same gap between two panels means
-- "end of that container" from one side and "after the container" from
-- the other, and the marker says which. Past the last panel is the end
-- of the chain.
-- Returns { parent, gap, x, into = container node or nil }, or nil.
local function drop_under(mx)
  local rects = app.panel_rects
  if #rects == 0 then return nil end
  for _, r in ipairs(rects) do
    local fx = app.chain[r.chain_i]
    if fx and mx < r.x + r.w + C.PANEL_GAP then
      local into = fx.ancestors and fx.ancestors[#fx.ancestors] or nil
      if mx < r.x + r.w * 0.5 then
        return { parent = fx.parent_path or {}, gap = fx.index or 0,
                 x = r.x - C.PANEL_GAP * 0.5, into = into }
      end
      return { parent = fx.parent_path or {}, gap = (fx.index or 0) + 1,
               x = r.x + r.w + C.PANEL_GAP * 0.5, into = into }
    end
  end
  local last = rects[#rects]
  return { parent = {}, gap = reaper.TrackFX_GetCount(app.track),
           x = last.x + last.w + C.PANEL_GAP * 0.5 }
end

-- Where "Insert plugin before/after" adds: a top-level slot as a number,
-- the way the browser always took it, or a slot inside a container.
local function insert_target(fx, after)
  local gap = (fx.index or fx.top_index or 0) + (after and 1 or 0)
  if fx.is_top_level then return gap end
  return { parent = fx.parent_path, gap = gap }
end

-- ---------------------------------------------------------------------
-- menus
-- ---------------------------------------------------------------------

local box_menu_items   -- the container menu, below; the panel menu nests it

-- ---------------------------------------------------------------------
-- hardware styles: the Faceplate and Style menus
-- ---------------------------------------------------------------------
-- Both stay open while you click through them, so you can try a few
-- faceplates or cap colours and see each on the panel behind the menu.
-- The flag was renamed in ReaImGui 0.10; either name, or none.
local KEEP_OPEN = 0
do
  for _, n in ipairs({ "SelectableFlags_NoAutoClosePopups", "SelectableFlags_DontClosePopups" }) do
    local ok, v = pcall(function() return ImGui[n] end)
    if ok and type(v) == "number" then KEEP_OPEN = v break end
  end
end

local SWATCH_W, SWATCH_H = 18, 13

-- A menu row with a faceplate's swatch at its front.
local function swatch_row(label, id, selected, width, bg, border, flags)
  local dl = ImGui.GetWindowDrawList(ctx)
  local x, y = ImGui.GetCursorScreenPos(ctx)
  local hit = ImGui.Selectable(ctx, "      " .. label .. "##" .. id, selected, flags or KEEP_OPEN, width, 0)
  local _, th = ImGui.CalcTextSize(ctx, "Ag")
  local sy = y + (th - SWATCH_H) * 0.5
  ImGui.DrawList_AddRectFilled(dl, x + 1, sy, x + 1 + SWATCH_W, sy + SWATCH_H, bg, 2.0)
  ImGui.DrawList_AddRect(dl, x + 1, sy, x + 1 + SWATCH_W, sy + SWATCH_H, border, 2.0, 0, 1.0)
  return hit
end

local function hex_key(rgb) return ("#%06x"):format(rgb & 0xffffff) end

-- After a menu's faceplate swatches: the colour of your own it has now
-- (when it has one), the Recent colours flyout -- every custom colour
-- given to a faceplate, background or section since ChannelView started --
-- and the [+] that opens the colour picker (TS_CV_ColourPick), with its
-- palettes and eyedropper. While the picker is open the panel shows the
-- colour being chosen; Cancel puts back what was there.
--   now:   the key chosen now
--   pick_key(k, save): makes key k the choice (nil = none), saving if `save`
--   from:  the colour the picker starts on when there's no custom one
local function custom_rows(id, now, width, pick_key, title, from)
  local ck = C.custom_key(now)
  if ck then
    local pl = C.plate_of(ck)
    swatch_row("Custom  " .. pl.label, id .. "_now", true, width, pl.bg, pl.border)
  end
  if ImGui.BeginMenu(ctx, "Recent colours##" .. id, #CP.recent > 0) then
    for i, rgb in ipairs(CP.recent) do
      local pl = C.plate_of(hex_key(rgb))
      if swatch_row(pl.label, id .. "_rc" .. i, pl.key == ck, 130, pl.bg, pl.border) then
        pick_key(pl.key, true)
        CP.remember(rgb)
      end
    end
    ImGui.EndMenu(ctx)
  end
  if ImGui.IsItemHovered(ctx, ImGui.HoveredFlags_AllowWhenDisabled) and #CP.recent == 0 then
    ImGui.SetTooltip(ctx, "The colours of your own you give faceplates, backgrounds\nand sections are kept here until ChannelView closes.")
  end
  local dl = ImGui.GetWindowDrawList(ctx)
  local x, y = ImGui.GetCursorScreenPos(ctx)
  if ImGui.Selectable(ctx, "      Custom colour\u{2026}##" .. id .. "_add", false, 0, width, 0) then
    local before = now
    CP.open({
      title   = title,
      rgb     = C.custom_rgb(now) or from or 0x808080,
      preview = function(rgb) pick_key(hex_key(rgb), false) end,
      apply   = function(rgb) pick_key(hex_key(rgb), true) end,
      cancel  = function() pick_key(before, false) end,
    })
  end
  if ImGui.IsItemHovered(ctx) then
    ImGui.SetTooltip(ctx, "Any colour: from a palette, the picker, or anywhere\non screen with the eyedropper.")
  end
  -- the [+], where the swatch would be
  local _, th = ImGui.CalcTextSize(ctx, "Ag")
  local sy = y + (th - SWATCH_H) * 0.5
  ImGui.DrawList_AddRect(dl, x + 1, sy, x + 1 + SWATCH_W, sy + SWATCH_H, C.COL.panel_border, 2.0, 0, 1.0)
  local ps = SWATCH_H - 2
  W.ICONS.plus(dl, x + 1 + (SWATCH_W - ps) * 0.5, sy + 1, ps, C.COL.icon)
end

-- Under a row of cap or lit-colour swatches: a [+] that opens the colour
-- picker, the colour of your own the control has now (when it has one),
-- and the recent colours (TS_CV_ColourPick), one click each.
--   now:    the key chosen now (a name, or #rrggbb)
--   from:   0xRRGGBB the picker starts on when there's no custom one
--   pick_key(k, save): makes key k the choice, saving if `save`
local function swatch_extras(id, now, from, title, pick_key)
  local dl = ImGui.GetWindowDrawList(ctx)
  local ck = C.custom_key(now)
  local function outline()
    local x0, y0 = ImGui.GetItemRectMin(ctx)
    local x1, y1 = ImGui.GetItemRectMax(ctx)
    ImGui.DrawList_AddRect(dl, x0 - 2, y0 - 2, x1 + 2, y1 + 2, C.COL.header_text, 3.0, 0, 1.5)
  end
  local x, y = ImGui.GetCursorScreenPos(ctx)
  if ImGui.Button(ctx, "##" .. id .. "_add", 18, 18) then
    local before = now
    CP.open({
      title   = title,
      rgb     = C.custom_rgb(now) or from or 0x808080,
      preview = function(rgb) pick_key(hex_key(rgb), false) end,
      apply   = function(rgb) pick_key(hex_key(rgb), true) end,
      cancel  = function() pick_key(before, false) end,
    })
  end
  if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "Custom colour\u{2026}") end
  W.ICONS.plus(dl, x + 3, y + 3, 12, C.COL.icon)
  local shown = {}
  if ck then
    ImGui.SameLine(ctx, 0, 4)
    ImGui.ColorButton(ctx, ck:upper() .. "##" .. id .. "_now", (C.custom_rgb(ck) << 8) | 0xff,
      ImGui.ColorEditFlags_NoTooltip, 18, 18)
    if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, ck:upper()) end
    outline()
    shown[ck] = true
  end
  for i, rgb in ipairs(CP.recent) do
    local k = hex_key(rgb)
    if not shown[k] then
      ImGui.SameLine(ctx, 0, 4)
      if ImGui.ColorButton(ctx, k:upper() .. "##" .. id .. "_rc" .. i, (rgb << 8) | 0xff,
          ImGui.ColorEditFlags_NoTooltip, 18, 18) then
        pick_key(k, true)
        CP.remember(rgb)
      end
      if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "Recent  " .. k:upper()) end
    end
  end
end

local function plate_menu(fx, key, layout)
  local cur = layout.plate or "theme"
  local dl = ImGui.GetWindowDrawList(ctx)
  for _, pl in ipairs(C.PLATES) do
    local x, y = ImGui.GetCursorScreenPos(ctx)
    if ImGui.Selectable(ctx, "      " .. pl.label .. "##plate_" .. pl.key,
        pl.key == cur, KEEP_OPEN, 150, 0) then
      local l = materialise(fx)
      l.plate = (pl.key ~= "theme") and pl.key or nil
      M.set(key, l); M.save()
    end
    if pl.key == "theme" and ImGui.IsItemHovered(ctx) then
      ImGui.SetTooltip(ctx, "The theme's own panel colour, following Hue/Tint.")
    end
    local _, th = ImGui.CalcTextSize(ctx, "Ag")
    local sy = y + (th - SWATCH_H) * 0.5
    ImGui.DrawList_AddRectFilled(dl, x + 1, sy, x + 1 + SWATCH_W, sy + SWATCH_H,
      pl.bg or C.COL.panel_bg, 2.0)
    ImGui.DrawList_AddRect(dl, x + 1, sy, x + 1 + SWATCH_W, sy + SWATCH_H,
      pl.border or C.COL.panel_border, 2.0, 0, 1.0)
  end
  do
    local function set(k, save)
      local l, pk = materialise(fx)
      l.plate = k
      M.set(pk, l)
      if save then M.save() end
    end
    local now_pl = C.plate_of(layout.plate)
    custom_rows("plate", layout.plate, 150, set, "Faceplate colour", now_pl and (now_pl.bg >> 8))
  end
  -- the grain, on whichever faceplate is chosen (the theme's has none)
  ImGui.Separator(ctx)
  local plate = C.plate_of(layout.plate)
  local on = M.brushed(layout, plate)
  if ImGui.MenuItem(ctx, "Brushed finish##plate_brush", nil, on, plate ~= nil) then
    local l = materialise(fx)
    local want = not on
    -- the faceplate's own choice is no choice at all, so it isn't saved
    if want == (plate.brushed or false) then l.brush = nil else l.brush = want end
    M.set(key, l); M.save()
  end
  if ImGui.IsItemHovered(ctx, ImGui.HoveredFlags_AllowWhenDisabled) then
    ImGui.SetTooltip(ctx, plate and "A fine brushed grain across this faceplate."
      or "Choose a faceplate first: the theme's panel has no grain.")
  end
  -- and/or a metallic flake, like metallic paint
  local mt = M.metal(layout, plate)
  if ImGui.MenuItem(ctx, "Metallic finish##plate_metal", nil, mt, plate ~= nil) then
    local l = materialise(fx)
    l.metal = (not mt) or nil
    M.set(key, l); M.save()
  end
  if ImGui.IsItemHovered(ctx, ImGui.HoveredFlags_AllowWhenDisabled) then
    ImGui.SetTooltip(ctx, plate and "A fine metallic flake and sheen across this faceplate,\nlike metallic paint. Goes with the brushed finish or on its own."
      or "Choose a faceplate first.")
  end
end

-- The knobs and faders a style can be copied between: a stepped knob is a
-- knob as far as looks go.
local function style_family(t)
  if t == "knob" or t == "stepped" then return "knob" end
  if t == "fader" then return "fader" end
  if t == "toggle" then return "toggle" end
  return nil
end

-- A toggle has no style, only the colour it lights when on (C.TOGGLE_COLS);
-- "Theme" is the theme's own toggle colour, following Hue/Tint.
local function toggle_colour_menu(fx, key, idx, c)
  local dl = ImGui.GetWindowDrawList(ctx)
  local now = c.cap or "theme"
  local function set(v)
    local l = materialise(fx)
    local lc = l.controls[idx]
    if lc then lc.cap = v end
    M.set(key, l); M.save()
  end
  -- the face: flat, or one of the lit ones (W.button_face), each shown lit
  -- in this button's colour
  ImGui.TextDisabled(ctx, "Style")
  do
    local cur = (c.style and C.BUTTON_STYLE[c.style]) and c.style or "flat"
    local lit = W.lit_col(c.cap) or C.COL.toggle_on
    local _, th = ImGui.CalcTextSize(ctx, "Ag")
    local rh = math.max(th, 20)
    for _, bs in ipairs(C.BUTTON_STYLES) do
      local x, y = ImGui.GetCursorScreenPos(ctx)
      if ImGui.Selectable(ctx, "         " .. bs.label .. "##bstyle_" .. bs.key, bs.key == cur,
          KEEP_OPEN, 150, rh) then
        local l = materialise(fx)
        local lc = l.controls[idx]
        if lc then lc.style = (bs.key ~= "flat") and bs.key or nil end
        M.set(key, l); M.save()
      end
      local bx1, by1, bx2, by2 = x + 3, y + 3, x + 33, y + rh - 3
      if not W.button_face(dl, bx1, by1, bx2, by2, 2.5, true, lit, bs.key, false) then
        ImGui.DrawList_AddRectFilled(dl, bx1, by1, bx2, by2, lit, 2.5)
        ImGui.DrawList_AddRect(dl, bx1, by1, bx2, by2, C.COL.knob_ring, 2.5, 0, 1.0)
      end
    end
  end
  ImGui.Spacing(ctx)
  ImGui.TextDisabled(ctx, "Lit colour")
  for i, cp in ipairs(C.TOGGLE_COLS) do
    if i > 1 then ImGui.SameLine(ctx, 0, 4) end
    local col = cp.col or C.COL.toggle_on
    if ImGui.ColorButton(ctx, cp.label .. "##tcol_" .. cp.key, col,
        ImGui.ColorEditFlags_NoTooltip, 18, 18) then
      set((cp.key ~= "theme") and cp.key or nil)
    end
    if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, cp.label) end
    if cp.key == now then
      local x0, y0 = ImGui.GetItemRectMin(ctx)
      local x1, y1 = ImGui.GetItemRectMax(ctx)
      ImGui.DrawList_AddRect(dl, x0 - 2, y0 - 2, x1 + 2, y1 + 2, C.COL.header_text, 3.0, 0, 1.5)
    end
  end
  -- any colour: the picker, and the recent ones
  do
    local function choose(k, save)
      local l, pk = materialise(fx)
      local lc = l.controls[idx]
      if lc then lc.cap = k end
      M.set(pk, l)
      if save then M.save() end
    end
    local lit = W.lit_col(c.cap) or C.COL.toggle_on
    swatch_extras("lit", c.cap, lit >> 8, "Lit colour", choose)
  end
  -- small: a half-height lit push-button with its name on it (buttons
  -- for a dropdown's choices have no sizes: their count sets their room)
  if c.type == "toggle" then
    ImGui.Spacing(ctx)
    ImGui.TextDisabled(ctx, "Size")
    local sz_now = (c.size == "small") and "small" or "medium"
    for i, k in ipairs({ "small", "medium" }) do
      if i > 1 then ImGui.SameLine(ctx, 0, 4) end
      if ImGui.Selectable(ctx, C.SIZES[k].label .. "##tsize_" .. k, k == sz_now, KEEP_OPEN, 56, 0) then
        local l = materialise(fx)
        local lc = l.controls[idx]
        if lc then lc.size = (k == "small") and "small" or nil end
        M.set(key, l); M.save()
      end
      if ImGui.IsItemHovered(ctx) then
        ImGui.SetTooltip(ctx, (k == "small") and "Half height: all button, its name on it when the\nstate has no name of its own. Two stack in one cell."
          or "The ordinary size.")
      end
    end
  end

  ImGui.Spacing(ctx)
  ImGui.Separator(ctx)
  if ImGui.MenuItem(ctx, "Apply to every button on this panel") then
    local l = materialise(fx)
    for _, o in ipairs(l.controls) do
      if o.type == "toggle" or (o.type == "combo" and o.buttons) then o.cap, o.style = c.cap, c.style end
    end
    M.set(key, l); M.save()
  end
end

-- "Brushed finish" for a control's background or a divider's section:
-- a tick that saves Brush<n>, or clears it when the choice is the one the
-- faceplate makes anyway (aluminium is brushed, an inset isn't).
local function brush_tick(fx, key, idx, c, kind, pl, id)
  local on = M.part_brushed(kind, pl, c.brush)
  local ch, v = ImGui.Checkbox(ctx, "Brushed finish##" .. id, on)
  if ch and kind then
    local l = materialise(fx)
    local lc = l.controls[idx]
    if lc then
      if v == M.part_brushed(kind, pl, nil) then lc.brush = nil else lc.brush = v end
    end
    M.set(key, l); M.save()
  end
  if ImGui.IsItemHovered(ctx, ImGui.HoveredFlags_AllowWhenDisabled) then
    ImGui.SetTooltip(ctx, kind and "A fine brushed grain across it."
      or "Choose a background first.")
  end
  -- and/or a metallic flake (Metal<n>)
  local mt = M.part_metal(kind, c.metal)
  local mch, mv = ImGui.Checkbox(ctx, "Metallic finish##" .. id .. "_m", mt)
  if mch and kind then
    local l = materialise(fx)
    local lc = l.controls[idx]
    if lc then lc.metal = mv or nil end
    M.set(key, l); M.save()
  end
  if ImGui.IsItemHovered(ctx, ImGui.HoveredFlags_AllowWhenDisabled) then
    ImGui.SetTooltip(ctx, kind and "A fine metallic flake across it, like metallic paint."
      or "Choose a background first.")
  end
end

-- A control's own background: nothing (its section's shows), an inset, or
-- a faceplate. Controls next to each other with the same one join up.
local function back_menu(fx, key, idx, c)
  local dl = ImGui.GetWindowDrawList(ctx)
  local now = c.back or "none"
  local function set(v)
    local l = materialise(fx)
    local lc = l.controls[idx]
    if lc then lc.back = v; if not v then lc.brush, lc.metal = nil, nil end end
    M.set(key, l); M.save()
  end
  ImGui.TextDisabled(ctx, "Behind this control")
  if ImGui.Selectable(ctx, "None##back_none", now == "none", KEEP_OPEN, 170, 0) then set(nil) end
  if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "Its section's background (or the panel's) shows.") end
  if ImGui.Selectable(ctx, "Inset##back_inset", now == "inset", KEEP_OPEN, 170, 0) then set("inset") end
  for _, pl in ipairs(C.PLATES) do
    if pl.bg then
      local x, y = ImGui.GetCursorScreenPos(ctx)
      if ImGui.Selectable(ctx, "      " .. pl.label .. "##back_" .. pl.key, now == pl.key, KEEP_OPEN, 170, 0) then
        set(pl.key)
      end
      local _, th = ImGui.CalcTextSize(ctx, "Ag")
      local sy = y + (th - SWATCH_H) * 0.5
      ImGui.DrawList_AddRectFilled(dl, x + 1, sy, x + 1 + SWATCH_W, sy + SWATCH_H, pl.bg, 2.0)
      ImGui.DrawList_AddRect(dl, x + 1, sy, x + 1 + SWATCH_W, sy + SWATCH_H, pl.border, 2.0, 0, 1.0)
    end
  end
  do
    local function cset(k, save)
      local l, pk = materialise(fx)
      local lc = l.controls[idx]
      if lc then lc.back = k; if not k then lc.brush, lc.metal = nil, nil end end
      M.set(pk, l)
      if save then M.save() end
    end
    local now_pl = C.plate_of(c.back)
    custom_rows("back", c.back, 170, cset, "Background colour", now_pl and (now_pl.bg >> 8))
  end
  ImGui.Separator(ctx)
  local bkind, bpl = P.back_style(c.back)
  ImGui.BeginDisabled(ctx, not bkind)
  brush_tick(fx, key, idx, c, bkind, bpl, "back_brush")
  ImGui.EndDisabled(ctx)
  ImGui.Spacing(ctx)
  ImGui.TextWrapped(ctx, "Controls side by side or above each other with the same background join into one shape, across a divider too.")
end

-- What a divider does to the section after it (up to the
-- next divider) -- nothing, an inset behind it, or a faceplate of its own.
local function section_menu(fx, key, idx, c)
  local dl = ImGui.GetWindowDrawList(ctx)
  local now = (c.style == "inset" and "inset") or (c.style == "plate" and C.plate_of(c.cap) and c.cap) or "none"
  local function set(style, cap)
    local l = materialise(fx)
    local lc = l.controls[idx]
    if lc then lc.style, lc.cap = style, cap; if not style then lc.brush, lc.metal = nil, nil end end
    M.set(key, l); M.save()
  end
  ImGui.TextDisabled(ctx, "The controls after this divider")
  if ImGui.Selectable(ctx, "None##sec_none", now == "none", KEEP_OPEN, 170, 0) then set(nil, nil) end
  if ImGui.Selectable(ctx, "Inset##sec_inset", now == "inset", KEEP_OPEN, 170, 0) then set("inset", nil) end
  if ImGui.IsItemHovered(ctx) then
    ImGui.SetTooltip(ctx, "A recessed panel behind them, up to the next divider.")
  end
  ImGui.Spacing(ctx)
  ImGui.TextDisabled(ctx, "On a faceplate of their own")
  for _, pl in ipairs(C.PLATES) do
    if pl.bg then
      local x, y = ImGui.GetCursorScreenPos(ctx)
      if ImGui.Selectable(ctx, "      " .. pl.label .. "##sec_" .. pl.key, now == pl.key, KEEP_OPEN, 170, 0) then
        set("plate", pl.key)
      end
      local _, th = ImGui.CalcTextSize(ctx, "Ag")
      local sy = y + (th - SWATCH_H) * 0.5
      ImGui.DrawList_AddRectFilled(dl, x + 1, sy, x + 1 + SWATCH_W, sy + SWATCH_H, pl.bg, 2.0)
      ImGui.DrawList_AddRect(dl, x + 1, sy, x + 1 + SWATCH_W, sy + SWATCH_H, pl.border, 2.0, 0, 1.0)
    end
  end
  do
    local before_style = c.style
    local function sset(k, save)
      local l, pk = materialise(fx)
      local lc = l.controls[idx]
      if lc then
        if k then lc.style, lc.cap = "plate", k
        elseif before_style == "inset" then lc.style, lc.cap = "inset", nil
        else lc.style, lc.cap, lc.brush, lc.metal = nil, nil, nil, nil end
      end
      M.set(pk, l)
      if save then M.save() end
    end
    local cur = (c.style == "plate") and c.cap or nil
    local now_pl = C.plate_of(cur)
    custom_rows("sec", cur, 170, sset, "Section colour", now_pl and (now_pl.bg >> 8))
  end
  ImGui.Separator(ctx)
  local skind, spl = P.section_style(c)
  ImGui.BeginDisabled(ctx, not skind)
  brush_tick(fx, key, idx, c, skind, spl, "sec_brush")
  ImGui.EndDisabled(ctx)
end

-- An XY pad's or a concentric knob's look: the colour (the pad's dot, the
-- inner knob) and the size. Neither takes the knob styles.
local function pad_style_menu(fx, key, idx, c)
  local dl = ImGui.GetWindowDrawList(ctx)
  local function set(fields)
    local l = materialise(fx)
    local lc = l.controls[idx]
    if lc then for k, v in pairs(fields) do lc[k] = v or nil end end
    M.set(key, l); M.save()
  end
  ImGui.TextDisabled(ctx, (c.type == "xy") and "Dot colour" or "Inner knob colour")
  for i, cp in ipairs(C.CAPS) do
    if i > 1 then ImGui.SameLine(ctx, 0, 4) end
    if ImGui.ColorButton(ctx, cp.label .. "##pcap_" .. cp.key, cp.col or C.COL.knob_fill,
        ImGui.ColorEditFlags_NoTooltip, 18, 18) then
      set({ cap = (cp.key ~= "accent") and cp.key or false })
    end
    if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, cp.label) end
    if cp.key == (c.cap or "accent") then
      local x0, y0 = ImGui.GetItemRectMin(ctx)
      local x1, y1 = ImGui.GetItemRectMax(ctx)
      ImGui.DrawList_AddRect(dl, x0 - 2, y0 - 2, x1 + 2, y1 + 2, C.COL.header_text, 3.0, 0, 1.5)
    end
  end
  do
    local function choose(k, save)
      local l, pk = materialise(fx)
      local lc = l.controls[idx]
      if lc then lc.cap = k end
      M.set(pk, l)
      if save then M.save() end
    end
    local now_col = W.cap_col(c.cap)
    swatch_extras("pcap", c.cap, now_col and (now_col >> 8), "Colour", choose)
  end
  ImGui.Spacing(ctx)
  ImGui.TextDisabled(ctx, "Size")
  if c.type == "xy" then
    -- columns by rows
    local now = c.size or "2x2"
    for i, k in ipairs({ "2x2", "3x2", "2x3", "3x3" }) do
      if i > 1 then ImGui.SameLine(ctx, 0, 4) end
      if ImGui.Selectable(ctx, k:gsub("x", "\u{00d7}") .. "##psize_" .. k, k == now, KEEP_OPEN, 40, 0) then
        set({ size = (k ~= "2x2") and k or false })
      end
      if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "Columns \u{00d7} rows.") end
    end
  else
    local now = (c.size == "large") and "large" or "medium"
    for i, k in ipairs({ "medium", "large" }) do
      if i > 1 then ImGui.SameLine(ctx, 0, 4) end
      if ImGui.Selectable(ctx, C.SIZES[k].label .. "##psize_" .. k, k == now, KEEP_OPEN, 56, 0) then
        set({ size = (k == "large") and "large" or false })
      end
    end
  end
  ImGui.Spacing(ctx)
  ImGui.Separator(ctx)
  if ImGui.MenuItem(ctx, "Reset to default", nil, false, c.cap ~= nil or c.size ~= nil) then
    set({ cap = false, size = false })
  end
end

local function style_menu(fx, key, idx, c)
  if c.type == "xy" or c.type == "dual" then return pad_style_menu(fx, key, idx, c) end
  local fam = style_family(c.type)
  if fam == "toggle" or c.type == "combo" then return toggle_colour_menu(fx, key, idx, c) end
  local list = (fam == "fader") and C.FADER_STYLES or C.KNOB_STYLES
  local cur = C.KNOB_STYLE_ALIAS[c.style] or c.style or list[1].key
  local dl = ImGui.GetWindowDrawList(ctx)
  local _, th = ImGui.CalcTextSize(ctx, "Ag")
  local row_h = (fam == "knob") and math.max(th, 26) or 0

  local function set(fields)
    local l = materialise(fx)
    local lc = l.controls[idx]
    if lc then for k, v in pairs(fields) do lc[k] = v or nil end end
    M.set(key, l); M.save()
  end

  ImGui.TextDisabled(ctx, "Style")
  for _, st in ipairs(list) do
    local x, y = ImGui.GetCursorScreenPos(ctx)
    local text = (fam == "knob") and ("        " .. st.label) or st.label
    if ImGui.Selectable(ctx, text .. "##style_" .. st.key, st.key == cur,
        KEEP_OPEN, 150, row_h) then
      set({ style = (st.key ~= list[1].key) and st.key or false })
    end
    if fam == "knob" then
      local r = row_h * 0.5 - 4     -- the scale ticks sit outside this
      W.knob_face(dl, x + 4 + r, y + row_h * 0.5, r, 0.62,
        { style = st.key, cap = W.cap_col(c.cap) })
    end
  end

  -- a fader's shape: which way it runs, how long, how thick (Shape<n>).
  -- Full length and a full column is the fader as it always was.
  if fam == "fader" then
    ImGui.Spacing(ctx)
    ImGui.TextDisabled(ctx, "Shape")
    local function row(name, choices, now, apply)
      ImGui.Text(ctx, name)
      for i, ch in ipairs(choices) do
        if i == 1 then ImGui.SameLine(ctx, 76) else ImGui.SameLine(ctx) end
        if ImGui.Selectable(ctx, ch[2] .. "##shape_" .. name .. i, now == ch[1], KEEP_OPEN, 36, 0) then
          apply(ch[1])
        end
      end
    end
    row("Direction", { { false, "Up" }, { "h", "Across" } }, c.dir or false,
      function(v) set({ dir = v }) end)
    row("Length", { { 2, "2" }, { 3, "3" }, { 4, "4" }, { false, "Full" } }, c.len or false,
      function(v) set({ len = v }) end)
    row("Thickness", { { false, "Full" }, { true, "Half" } }, c.thin or false,
      function(v) set({ thin = v }) end)
    if ImGui.IsItemHovered(ctx) then
      ImGui.SetTooltip(ctx, "Half: half a column wide (or half a row high, across) --\n" ..
        "for a row of faders side by side, a graphic EQ's bands say.")
    end
  end

  ImGui.Spacing(ctx)
  ImGui.TextDisabled(ctx, "Colour")
  local style_def = (fam == "fader") and C.FADER_STYLE[cur] or C.KNOB_STYLE[cur]
  local cap_now = c.cap or (style_def and style_def.cap)
  for i, cp in ipairs(C.CAPS) do
    if i > 1 then ImGui.SameLine(ctx, 0, 4) end
    local col = cp.col or C.COL.knob_fill
    if ImGui.ColorButton(ctx, cp.label .. "##cap_" .. cp.key, col,
        ImGui.ColorEditFlags_NoTooltip, 18, 18) then
      set({ cap = cp.key })
    end
    if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, cp.label) end
    if cp.key == cap_now then
      local x0, y0 = ImGui.GetItemRectMin(ctx)
      local x1, y1 = ImGui.GetItemRectMax(ctx)
      ImGui.DrawList_AddRect(dl, x0 - 2, y0 - 2, x1 + 2, y1 + 2, C.COL.header_text, 3.0, 0, 1.5)
    end
  end
  -- any colour: the picker, and the recent ones
  do
    local function choose(k, save)
      local l, pk = materialise(fx)
      local lc = l.controls[idx]
      if lc then lc.cap = k end
      M.set(pk, l)
      if save then M.save() end
    end
    local now_col = W.cap_col(cap_now)
    swatch_extras("cap", c.cap, now_col and (now_col >> 8),
      (fam == "fader") and "Fader cap colour" or "Knob colour", choose)
  end

  -- knobs come in three sizes (C.SIZES); the panel reflows round them
  if fam == "knob" then
    ImGui.Spacing(ctx)
    ImGui.TextDisabled(ctx, "Size")
    local now = c.size or "medium"
    for i, k in ipairs(C.SIZE_LIST) do
      if i > 1 then ImGui.SameLine(ctx, 0, 4) end
      if ImGui.Selectable(ctx, C.SIZES[k].label .. "##size_" .. k, k == now, KEEP_OPEN, 56, 0) then
        set({ size = (k ~= "medium") and k or false })
      end
      if ImGui.IsItemHovered(ctx) then
        ImGui.SetTooltip(ctx, (k == "small") and "Half height: a small dial under its name in small type, its value\nin the tooltip. Two stack in the space of one ordinary knob."
          or (k == "large") and "Half again as big, name and value kept.\nDrawn ordinary size in a panel only one row tall."
          or "The ordinary size.")
      end
    end

    -- numbers round the dial, like a hardware knob's printed scale
    ImGui.Spacing(ctx)
    ImGui.TextDisabled(ctx, "Scale")
    -- (values unless the knob says otherwise: no Scale line is values)
    local sc_now = M.scale_kind(c) or "none"
    for i, o in ipairs({ { "none", "None" }, { "values", "Values" }, { "ten", "0\u{2013}10" } }) do
      if i > 1 then ImGui.SameLine(ctx, 0, 4) end
      if ImGui.Selectable(ctx, o[2] .. "##scale_" .. o[1], o[1] == sc_now, KEEP_OPEN, 56, 0) then
        set({ scale = (o[1] ~= "values") and o[1] or false,
              scale_ink = (o[1] == "none") and false or nil })
      end
      if ImGui.IsItemHovered(ctx) then
        ImGui.SetTooltip(ctx, (o[1] == "values") and "Numbers round the dial in the plugin's own values\n(units left off; thousands as k)."
          or (o[1] == "ten") and "Numbers round the dial from 0 to 10."
          or "No numbers.")
      end
    end
    ImGui.BeginDisabled(ctx, sc_now == "none")
    local rv, on = ImGui.Checkbox(ctx, "Numbers in cap colour##scale_ink", c.scale_ink == "cap")
    if rv then set({ scale_ink = on and "cap" or false }) end
    ImGui.EndDisabled(ctx)
    if ImGui.IsItemHovered(ctx, ImGui.HoveredFlags_AllowWhenDisabled) then
      ImGui.SetTooltip(ctx, "The numbers in the knob's colour rather than the faceplate's.\n" ..
        "A medium knob with numbers shows its value in the tooltip; a small\none has no room for them.")
    end
  end

  ImGui.Spacing(ctx)
  ImGui.Separator(ctx)
  if ImGui.MenuItem(ctx, fam == "fader" and "Apply to every fader on this panel"
                                        or "Apply to every knob on this panel") then
    local l = materialise(fx)
    local src = l.controls[idx]
    if src then
      for _, o in ipairs(l.controls) do
        if style_family(o.type) == fam then
          o.style, o.cap = src.style, src.cap
          if fam == "knob" then o.scale, o.scale_ink = src.scale, src.scale_ink end
          if fam == "fader" then o.dir, o.len, o.thin = src.dir, src.len, src.thin end
        end
      end
    end
    M.set(key, l); M.save()
  end
  if ImGui.MenuItem(ctx, "Reset to default", nil, false, c.style ~= nil or c.cap ~= nil or c.scale ~= nil) then
    set({ style = false, cap = false, scale = false, scale_ink = false })
  end
end

-- ---------------------------------------------------------------------
-- parallel FX and containers
-- ---------------------------------------------------------------------

-- A container's name as REAPER shows it: its own name when it's been
-- renamed, else just "Container".
local function box_label(node)
  return node.alias or U.fx_label(node)
end

-- The three ways REAPER can run a plugin (or container) against the one
-- before it. The first slot of a level has nothing before it, so the
-- choice is offered there greyed out, with the reason.
local PAR_CHOICES = {
  { 0, "In series" },
  { 1, "In parallel with previous" },
  { 2, "In parallel with previous, merge MIDI" },
}
local function parallel_menu(addr, cur, index, what)
  local first = (index or 0) == 0
  if ImGui.BeginMenu(ctx, "Route", not first) then
    for _, ch in ipairs(PAR_CHOICES) do
      if ImGui.MenuItem(ctx, ch[2], nil, (cur or 0) == ch[1]) and (cur or 0) ~= ch[1] then
        set_parallel(addr, ch[1], what)
      end
    end
    ImGui.EndMenu(ctx)
  end
  if first and ImGui.IsItemHovered(ctx, ImGui.HoveredFlags_AllowWhenDisabled) then
    ImGui.SetTooltip(ctx, "First in its " .. ((addr or 0) >= T.CONTAINER_FLAG and "container" or "chain") ..
      " \u{2014} there's nothing before it to route beside.")
  end
end

-- Every panel inside a container, empty-container stand-ins included.
local function panels_in(node)
  local out = {}
  for i = node.first, node.last do
    if app.chain[i] then out[#out + 1] = app.chain[i] end
  end
  return out
end

-- The container menu's items: from its square on the bracket, and as a
-- submenu of the panel menu of anything inside it.
box_menu_items = function(node)
  local tr = app.track
  if not tr then return end
  ImGui.TextDisabled(ctx, "Container: " .. U.truncate(box_label(node), 30))

  -- REAPER's own name for it, as its FX chain shows
  if app.boxren_for ~= node.guid then app.boxren_for, app.boxren_buf = node.guid, node.alias or "" end
  ImGui.SetNextItemWidth(ctx, 150)
  local _, v = ImGui.InputTextWithHint(ctx, "##boxren", "Container", app.boxren_buf)
  local enter = ImGui.IsItemDeactivated(ctx) and (ImGui.IsKeyPressed(ctx, ImGui.Key_Enter)
                or ImGui.IsKeyPressed(ctx, ImGui.Key_KeypadEnter))
  app.boxren_buf = v
  ImGui.SameLine(ctx)
  if ImGui.Button(ctx, "Rename##boxren") or enter then
    T.rename(tr, node.addr, node.guid, U.trim(app.boxren_buf))
    app.boxren_for = nil
    rescan(true)
    ImGui.CloseCurrentPopup(ctx)
  end
  ImGui.Separator(ctx)

  local on = T.get_enabled(tr, node.addr)
  if ImGui.MenuItem(ctx, "Bypass container", nil, not on) then
    reaper.Undo_BeginBlock()
    T.set_enabled(tr, node.addr, not on)
    reaper.Undo_EndBlock("ChannelView: " .. (on and "bypass" or "enable") .. " container", -1)
  end
  -- the container's own wet, as its FX chain window has it
  local wet = reaper.TrackFX_GetParamFromIdent and reaper.TrackFX_GetParamFromIdent(tr, node.addr, ":wet")
  if wet and wet >= 0 then
    local wv = reaper.TrackFX_GetParam(tr, node.addr, wet) or 1
    ImGui.SetNextItemWidth(ctx, 150)
    local ch, nv = ImGui.SliderDouble(ctx, "Wet##boxwet", wv * 100, 0, 100, "%.0f%%")
    if ch then reaper.TrackFX_SetParam(tr, node.addr, wet, nv / 100) end
  end
  parallel_menu(node.addr, node.parallel, node.index, "container")
  ImGui.Separator(ctx)

  local inside = panels_in(node)
  if ImGui.MenuItem(ctx, "Collapse everything in it", nil, false, #inside > 0) then
    for _, f in ipairs(inside) do set_fold(f, true) end
  end
  if ImGui.MenuItem(ctx, "Expand everything in it", nil, false, #inside > 0) then
    for _, f in ipairs(inside) do set_fold(f, false) end
  end
  if ImGui.MenuItem(ctx, "Add plugin into it\u{2026}") then
    B.open_menu({ parent = node.path, gap = #(node.children or {}) })
  end
  if ImGui.MenuItem(ctx, "Move left", nil, false, node.index > 0) then
    nudge(node.path, -1, "container")
  end
  if ImGui.MenuItem(ctx, "Move right", nil, false, node.index < node.count - 1) then
    nudge(node.path, 1, "container")
  end
  ImGui.Separator(ctx)
  if ImGui.MenuItem(ctx, "Open the container's window") then
    reaper.TrackFX_Show(tr, node.addr, 3)
  end
  if ImGui.MenuItem(ctx, "Show in the FX chain") then
    reaper.TrackFX_Show(tr, node.addr, 1)
  end
  if ImGui.MenuItem(ctx, "Save as FX chain\u{2026}") then
    CN.open_save(tr, node.path, box_label(node))
  end
  ImGui.Separator(ctx)
  if ImGui.MenuItem(ctx, "Unpack: take everything out") then
    reaper.Undo_BeginBlock()
    reaper.PreventUIRefresh(1)
    T.unpack(tr, node.path)
    reaper.PreventUIRefresh(-1)
    reaper.Undo_EndBlock("ChannelView: unpack container", -1)
    rescan(true)
    ImGui.CloseCurrentPopup(ctx)
  end
  if ImGui.IsItemHovered(ctx) then
    ImGui.SetTooltip(ctx, "Puts what's inside back in the container's place, in order,\nand removes the empty container.")
  end
  if ImGui.MenuItem(ctx, "Remove container and everything in it") then
    reaper.Undo_BeginBlock()
    reaper.TrackFX_Delete(tr, node.addr)
    reaper.Undo_EndBlock("ChannelView: remove container", -1)
    rescan(true)
    ImGui.CloseCurrentPopup(ctx)
  end
end

local function box_menu()
  if not ImGui.BeginPopup(ctx, "boxmenu") then return end
  local node = app.box_for
  -- the node is from the chain as it was: still the same container?
  if not node or not app.track or T.guid_at(app.track, node.addr) ~= node.guid then
    ImGui.EndPopup(ctx) return
  end
  box_menu_items(node)
  ImGui.EndPopup(ctx)
end

local function panel_menu()
  if not ImGui.BeginPopup(ctx, "panelmenu") then return end
  local fx = app.chain[app.menu_fx or -1]
  if not fx then ImGui.EndPopup(ctx) return end

  local layout, key, is_default = layout_for(fx)
  ImGui.TextDisabled(ctx, U.fx_label(fx) .. (fx.alias and ("  \u{00B7}  " .. U.clean_fx_name(fx.name)) or ""))

  -- REAPER's own name for this instance (its FX chain's Rename): shown on
  -- the panel, in the FX chain and everywhere else REAPER lists it. The
  -- layout stays the plugin's. Empty goes back to the plugin's name.
  if app.fxren_for ~= fx.guid then app.fxren_for, app.fxren_buf = fx.guid, fx.alias or "" end
  ImGui.SetNextItemWidth(ctx, 150)
  local _, ren_v = ImGui.InputTextWithHint(ctx, "##fxren", U.clean_fx_name(fx.name),
    app.fxren_buf)
  local ren_enter = (ImGui.IsItemDeactivated(ctx) and (ImGui.IsKeyPressed(ctx, ImGui.Key_Enter) or ImGui.IsKeyPressed(ctx, ImGui.Key_KeypadEnter)))
  app.fxren_buf = ren_v
  if ImGui.IsItemHovered(ctx) then
    ImGui.SetTooltip(ctx, "Rename this instance -- REAPER's own name for it, as its FX\n" ..
      "chain shows. The layout is still the plugin's. Clear it to go back.")
  end
  ImGui.SameLine(ctx)
  if ImGui.Button(ctx, "Rename##fxren") or ren_enter then
    T.rename(app.track, fx.addr, fx.guid, U.trim(app.fxren_buf))
    app.fxren_for = nil
    rescan(true)
    ImGui.CloseCurrentPopup(ctx)
  end
  ImGui.Separator(ctx)

  -- a locked layout takes no edits (the padlock in the panel's foot);
  -- its meters can still be switched on and off
  local locked = M.locked(layout) ~= nil
  local function locked_tip()
    if locked and ImGui.IsItemHovered(ctx, ImGui.HoveredFlags_AllowWhenDisabled) then
      ImGui.SetTooltip(ctx, "The layout is locked: unlock it with the padlock\nat the left of the panel's foot.")
    end
  end
  if ImGui.MenuItem(ctx, "Edit parameters\u{2026}", nil, false, not locked) then
    E.open(app.track, fx, key, layout)
  end
  locked_tip()
  if ImGui.MenuItem(ctx, St.is_collapsed(fx.guid) and "Expand" or "Collapse to a bar") then
    toggle_fold(fx)
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
  elseif not RQ.is_eq(key) then
    -- Doesn't report it: it can be MEASURED instead, by the track's probe
    -- pair (TS_CV_Taps). Not ReaEQ, which has no reduction to measure.
    local on = layout.measure == true
    if ImGui.MenuItem(ctx, "Measure gain reduction (estimated)", nil, on) then
      local l = materialise(fx)
      l.measure = (not on) or nil
      M.set_meter(l, not on)
      M.set(key, l); M.save()
      TP.invalidate()
      if not on and TP.status(app.track, fx.guid) == "no_probes" then
        if reaper.MB("This plugin doesn't report its gain reduction, so it's measured\n" ..
                     "by a TS_TrackProbe pair: one at the start of the chain, one at\n" ..
                     "the end. This track doesn't have them.\n\nAdd them now?",
                     "ChannelView", 4) == 6 then
          local ok, why = TP.insert_probes(app.track)
          if not ok then reaper.MB(why, "ChannelView", 0) end
        end
      end
    end
    if ImGui.IsItemHovered(ctx) then
      ImGui.SetTooltip(ctx,
        "This plugin doesn't report gain reduction to REAPER. Measure it\n" ..
        "instead, from the audio going in and coming out -- every instance\n" ..
        "between a TS_TrackProbe pair. An estimate: see the meter's tooltip.")
    end
  end
  -- Input and output meters: any plugin, measured by the same probe pair.
  do
    local on = layout.levels == true
    if ImGui.MenuItem(ctx, "Input/output meters", nil, on) then
      local l = materialise(fx)
      l.levels = (not on) or nil
      M.set(key, l); M.save()
      TP.invalidate()
      if not on and TP.status(app.track, fx.guid) == "no_probes" then
        if reaper.MB("Input and output levels are measured by a TS_TrackProbe pair:\n" ..
                     "one at the start of the chain, one at the end. This track\n" ..
                     "doesn't have them.\n\nAdd them now?", "ChannelView", 4) == 6 then
          local ok, why = TP.insert_probes(app.track)
          if not ok then reaper.MB(why, "ChannelView", 0) end
        end
      end
    end
    if ImGui.IsItemHovered(ctx) then
      ImGui.SetTooltip(ctx,
        "Meters for what goes into this plugin and what comes out, and the\n" ..
        "change in level between them -- every instance between a\n" ..
        "TS_TrackProbe pair.")
    end
  end
  if ImGui.BeginMenu(ctx, "Faceplate", not locked) then
    plate_menu(fx, key, layout)
    ImGui.EndMenu(ctx)
  end
  locked_tip()
  if ImGui.MenuItem(ctx, "Move left", nil, false, fx.index > 0) then
    nudge(fx.path_t, -1)
  end
  if ImGui.MenuItem(ctx, "Move right", nil, false, fx.index < fx.siblings - 1) then
    nudge(fx.path_t, 1)
  end
  parallel_menu(fx.addr, fx.parallel, fx.index, "plugin")
  if ImGui.MenuItem(ctx, "Put in a new container") then
    reaper.Undo_BeginBlock()
    reaper.PreventUIRefresh(1)
    T.wrap(app.track, fx.path_t)
    reaper.PreventUIRefresh(-1)
    reaper.Undo_EndBlock("ChannelView: put " .. U.fx_label(fx) .. " in a container", -1)
    rescan(true)
  end
  do
    local box = fx.ancestors and fx.ancestors[#fx.ancestors]
    if box and ImGui.BeginMenu(ctx, "Container: " .. U.truncate(box_label(box), 24)) then
      box_menu_items(box)
      ImGui.EndMenu(ctx)
    end
  end
  -- These three replace a saved layout outright and save straight away --
  -- one stray click and a layout you spent an hour on is gone, for every
  -- instance of the plugin. So each asks first whenever there is a saved
  -- layout to lose. (The Edit Parameters dialog's own Auto-fill needs no
  -- such guard: nothing there is kept until you press Save.)
  local function sure(what)
    if is_default then return true end
    return reaper.MB(what .. "\n\nThis replaces the saved layout for every " .. key ..
      " on every track. The library as it was before is kept as\n" ..
      "TS_ChannelView_Mappings.bak.ini, until the next save.", "ChannelView", 1) == 1
  end
  if ImGui.MenuItem(ctx, "Auto-fill layout\u{2026}", nil, false, not locked) then
    if sure(("Replace this layout with the plugin's first %d parameters?"):format(C.AUTO_DEFAULT_N)) then
      M.set(key, M.build_default(app.track, fx.addr)); M.save()
    end
  end
  locked_tip()
  if ImGui.MenuItem(ctx, "Clear layout\u{2026}", nil, false, not is_default and not locked) then
    if sure("Clear every control from this layout?") then
      M.set(key, { controls = {} }); M.save()
    end
  end
  locked_tip()
  if ImGui.MenuItem(ctx, "Forget saved layout\u{2026}", nil, false, not is_default and not locked) then
    if sure("Forget this saved layout and go back to the automatic one?") then
      M.remove(key); M.save()
    end
  end
  locked_tip()
  ImGui.Separator(ctx)
  if ImGui.MenuItem(ctx, "Insert plugin before\u{2026}") then
    B.open_menu(insert_target(fx, false))
  end
  if ImGui.MenuItem(ctx, "Insert plugin after\u{2026}") then
    B.open_menu(insert_target(fx, true))
  end
  ImGui.Separator(ctx)
  if ImGui.MenuItem(ctx, "Open the plugin's window") then
    reaper.TrackFX_Show(app.track, fx.addr, 3)
  end
  if ImGui.MenuItem(ctx, "Show in the FX chain") then
    reaper.TrackFX_Show(app.track, fx.addr, 1)
  end
  ImGui.Separator(ctx)
  if ImGui.MenuItem(ctx, fx.is_container and "Remove container" or "Remove plugin from the chain") then
    remove_fx(fx)
    ImGui.EndPopup(ctx)
    return
  end

  ImGui.Separator(ctx)
  ImGui.TextDisabled(ctx, is_default and "auto-generated layout"
                                      or ("saved as \"" .. key .. "\""))
  ImGui.EndPopup(ctx)
end

-- ---------------------------------------------------------------------
-- copy and paste a control's look (TS_CV_Mappings.look_of / paste_look)
-- ---------------------------------------------------------------------
-- One copied look, for this session: from any control on any panel,
-- pasted onto one control, or every one of its kind in a section or on
-- the panel. app.style_clip = { look = M.look_of(control) }.

local LOOK_NOUN = { knob = "knob", fader = "fader", button = "button" }

-- "Knob: Skirted, Red, Large, Values scale, on Inset" -- what's on the
-- clipboard, for the menu's tooltip
local function look_text(s)
  local parts = {}
  local function label_of(list, key)
    for _, t in ipairs(list) do if t.key == key then return t.label end end
    return nil
  end
  if s.fam == "knob" then
    parts[#parts + 1] = label_of(C.KNOB_STYLES, C.KNOB_STYLE_ALIAS[s.style] or s.style) or "Arc"
  elseif s.fam == "fader" then
    parts[#parts + 1] = label_of(C.FADER_STYLES, s.style) or "Flat"
  elseif s.fam == "button" then
    parts[#parts + 1] = label_of(C.BUTTON_STYLES, s.style) or "Flat"
  end
  if s.cap then
    parts[#parts + 1] = label_of(s.fam == "button" and C.TOGGLE_COLS or C.CAPS, s.cap)
                        or C.custom_key(s.cap) or s.cap
  end
  if s.size and C.SIZES[s.size] then parts[#parts + 1] = C.SIZES[s.size].label end
  if s.fam == "xy" and s.size then parts[#parts + 1] = (s.size:gsub("x", "\u{00d7}")) end
  if s.fam == "fader" then
    parts[#parts + 1] = ((s.dir == "h") and "across " or "up ") .. (s.len and tostring(s.len) or "full")
      .. (s.thin and ", half width" or "")
  end
  if s.fam == "knob" then
    local sc = M.scale_kind(s)
    if sc == "values" then parts[#parts + 1] = "values scale"
    elseif sc == "ten" then parts[#parts + 1] = "0\u{2013}10 scale" end
  end
  if s.back then
    local pl = C.plate_of(s.back)
    parts[#parts + 1] = "on " .. ((s.back == "inset") and "Inset" or (pl and pl.label) or s.back)
  end
  local head = s.fam and (s.fam:sub(1, 1):upper() .. s.fam:sub(2)) or "Background"
  return head .. ((#parts > 0) and (": " .. table.concat(parts, ", ")) or ": none")
end

-- the controls in the same section as control `idx`: between the dividers
-- either side of it
local function section_range(controls, idx)
  local a, b = 1, #controls
  for k = idx - 1, 1, -1 do if controls[k].type == "divider" then a = k + 1 break end end
  for k = idx + 1, #controls do if controls[k].type == "divider" then b = k - 1 break end end
  return a, b
end

local function look_items(fx, key, layout, idx, c, locked)
  if ImGui.MenuItem(ctx, "Copy style") then
    app.style_clip = { look = M.look_of(c) }
  end
  if ImGui.IsItemHovered(ctx) then
    ImGui.SetTooltip(ctx, "Its style, colour, size (a fader's shape), scale, background\n" ..
      "and finish, to paste onto other controls, on any panel.")
  end
  if locked then return end
  local s = app.style_clip and app.style_clip.look
  local have = s ~= nil
  local function tip()
    if ImGui.IsItemHovered(ctx, ImGui.HoveredFlags_AllowWhenDisabled) then
      ImGui.SetTooltip(ctx, have and look_text(s) or "Copy a control's style first.")
    end
  end
  local function paste(from, to)
    local l = materialise(fx)
    local n = 0
    for k = from, to do
      local o = l.controls[k]
      local fits = o and o.type ~= "divider"
        and (k == idx or s.fam == nil or M.look_family(o) == s.fam)
      if fits and M.paste_look(o, s) then n = n + 1 end
    end
    if n > 0 then M.set(key, l); M.save() end
  end
  if ImGui.MenuItem(ctx, "Paste style", nil, false, have) then paste(idx, idx) end
  tip()
  local noun = have and (s.fam and LOOK_NOUN[s.fam] or "control") or "control"
  if ImGui.MenuItem(ctx, "Paste to every " .. noun .. " in this section", nil, false, have) then
    paste(section_range(layout.controls, idx))
  end
  tip()
  if ImGui.MenuItem(ctx, "Paste to every " .. noun .. " on this panel", nil, false, have) then
    paste(1, #layout.controls)
  end
  tip()
end

-- Choosing an XY pad's Y, or a concentric knob's inner knob: every
-- parameter of the plugin, filtered as you type.
local function second_param_menu(fx, key, idx, c)
  ImGui.SetNextItemWidth(ctx, 240)
  local _, f = ImGui.InputTextWithHint(ctx, "##p2filter", "filter\u{2026}", app.p2_filter or "")
  app.p2_filter = f
  local want = U.trim(f or ""):lower()
  local n = reaper.TrackFX_GetNumParams(app.track, fx.addr)
  if ImGui.BeginChild(ctx, "##p2list", 240, math.min(320, 20 + n * 19)) then
    for p = 0, n - 1 do
      local _, pn = reaper.TrackFX_GetParamName(app.track, fx.addr, p, "")
      local shown = M.display_name(key, p, nil, pn, false)
      if want == "" or shown:lower():find(want, 1, true) or tostring(p) == want then
        if ImGui.Selectable(ctx, ("%d  %s##p2_%d"):format(p, shown, p), c.param2 == p) then
          local l = materialise(fx)
          local lc = l.controls[idx]
          if lc then lc.param2 = p end
          M.set(key, l); M.save()
          ImGui.CloseCurrentPopup(ctx)
        end
      end
    end
    ImGui.EndChild(ctx)
  end
end

local TYPE_LABELS = { knob = "Knob", toggle = "Button", combo = "Dropdown",
                      stepped = "Stepped knob", fader = "Fader",
                      xy = "XY pad", dual = "Concentric knob",
                      blank = "Gap", half_gap = "Half gap", divider = "Divider" }
local TYPE_ORDER  = { "knob", "toggle", "combo", "stepped", "fader", "xy", "dual", "blank", "half_gap", "divider" }

-- REAPER's Parameter Modulation / Link window for this one parameter --
-- LFO, audio control signal, MIDI link, parameter link -- straight from
-- the control, rather than touching it and hunting for the last-touched
-- action. Ticked while the parameter has modulation switched on. Not a
-- layout edit, so a locked layout offers it too.
local function param_mod_item(fx, c)
  if not (app.track and c and c.param and c.param >= 0) then return end
  -- two of them for a control with two parameters, named for which is which
  local list = { { c.param, "Parameter modulation\u{2026}" } }
  if M.has_second(c) and c.param2 and c.param2 >= 0 then
    local a, b = (c.type == "xy") and "X" or "ring", (c.type == "xy") and "Y" or "inner knob"
    list = { { c.param, "Parameter modulation (" .. a .. ")\u{2026}" },
             { c.param2, "Parameter modulation (" .. b .. ")\u{2026}" } }
  end
  for _, e in ipairs(list) do
    local pre = ("param.%d.mod."):format(e[1])
    local ok, act = reaper.TrackFX_GetNamedConfigParm(app.track, fx.addr, pre .. "active")
    if ImGui.MenuItem(ctx, e[2], nil, ok and tonumber(act) == 1) then
      reaper.TrackFX_SetNamedConfigParm(app.track, fx.addr, pre .. "visible", "1")
    end
    if ImGui.IsItemHovered(ctx) then
      ImGui.SetTooltip(ctx, "REAPER's Parameter Modulation / Link window for this\n" ..
        "parameter: LFO, audio control signal, MIDI or parameter link.\n" ..
        "Ticked while its modulation is switched on.")
    end
  end
end

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

  -- a locked layout takes no edits: say so, and offer only what isn't one
  if M.locked(layout) then
    ImGui.TextDisabled(ctx, "Layout locked")
    ImGui.TextDisabled(ctx, "(the padlock at the left of the panel's foot)")
    ImGui.Separator(ctx)
    look_items(fx, key, layout, cm.ctl, c, true)
    ImGui.Separator(ctx)
    param_mod_item(fx, c)
    if c.type == "combo" then
      ImGui.Separator(ctx)
      if ImGui.MenuItem(ctx, "Rescan choices") then P.rescan_choices(key, c.param) end
    end
    ImGui.EndPopup(ctx)
    return
  end

  local function commit()
    local l, k = materialise(fx)
    M.save()
    return l, k
  end

  if ImGui.BeginMenu(ctx, "Show as") then
    for _, t in ipairs(TYPE_ORDER) do
      if ImGui.MenuItem(ctx, TYPE_LABELS[t], nil, c.type == t and not (t == "combo" and c.buttons)) then
        local l = commit()
        local lc = l.controls[cm.ctl]
        local was = lc.type
        lc.type = t
        lc.buttons, lc.nbtn = nil, nil
        -- sizes don't carry between an XY pad and anything else, and a
        -- concentric knob is never small
        if (t == "xy") ~= (was == "xy") or (t == "dual" and lc.size == "small") then lc.size = nil end
        -- two parameters: the second starts as the next one along
        if (t == "xy" or t == "dual") and not lc.param2 and lc.param then
          local n = reaper.TrackFX_GetNumParams(app.track, fx.addr)
          lc.param2 = (lc.param + 1 < n) and (lc.param + 1) or lc.param
        end
        M.set(key, l); M.save()
      end
      -- right after Dropdown: its choices as a row, or a column, of buttons
      if t == "combo" then
        local n
        local list = c.param and P.combo_steps(app.track, fx.addr, c.param, key)
        if type(list) == "table" then n = #list
        else
          local st = c.param and P.step_norm(app.track, fx.addr, c.param, key)
          n = st and (math.floor(1 / st + 0.5) + 1) or nil
        end
        local ok = n and n >= 2 and n <= C.BUTTONS_MAX
        for _, d in ipairs({ { "across", "Buttons across" }, { "down", "Buttons down" } }) do
          if ImGui.MenuItem(ctx, d[2], nil, c.type == "combo" and c.buttons == d[1], ok and true or false) then
            local l = commit()
            local lc = l.controls[cm.ctl]
            lc.type, lc.buttons, lc.nbtn = "combo", d[1], n
            M.set(key, l); M.save()
          end
          if ImGui.IsItemHovered(ctx, ImGui.HoveredFlags_AllowWhenDisabled) then
            ImGui.SetTooltip(ctx, ok and ("One button per choice (%d), the current one lit."):format(n)
              or ("Only for a parameter with 2 to %d choices."):format(C.BUTTONS_MAX))
          end
        end
      end
    end
    ImGui.EndMenu(ctx)
  end

  if not M.has_second(c) and ImGui.MenuItem(ctx, "Centred fill", nil, c.bipolar and true or false) then
    local l = commit()
    l.controls[cm.ctl].bipolar = not l.controls[cm.ctl].bipolar
    M.set(key, l); M.save()
  end

  -- an XY pad's Y, a concentric knob's inner knob
  if M.has_second(c) and ImGui.BeginMenu(ctx, (c.type == "xy") and "Y parameter" or "Inner knob parameter") then
    second_param_menu(fx, key, cm.ctl, c)
    ImGui.EndMenu(ctx)
  end

  local styled = style_family(c.type) or c.type == "xy" or c.type == "dual" or (c.type == "combo" and c.buttons)
  if styled and ImGui.BeginMenu(ctx, "Style") then
    style_menu(fx, key, cm.ctl, c)
    ImGui.EndMenu(ctx)
  end

  -- its own background, over its section's; neighbours with the same one
  -- join into one shape
  if c.type ~= "divider" and ImGui.BeginMenu(ctx, "Background") then
    back_menu(fx, key, cm.ctl, c)
    ImGui.EndMenu(ctx)
  end

  -- the section this control is in belongs to the divider in front of it
  -- (dividers aren't on the panel to right-click, so it's offered here)
  local div_idx
  for k = cm.ctl - 1, 1, -1 do
    local o = layout.controls[k]
    if o.type == "divider" then div_idx = k break end
    if P.fader_kind(o) == "column" then break end
  end
  if ImGui.BeginMenu(ctx, "Section", div_idx ~= nil) then
    section_menu(fx, key, div_idx, layout.controls[div_idx])
    ImGui.EndMenu(ctx)
  end
  if not div_idx and ImGui.IsItemHovered(ctx, ImGui.HoveredFlags_AllowWhenDisabled) then
    ImGui.SetTooltip(ctx, "A section starts at a divider. To style the first group,\n" ..
      "put a divider (Line off) at the very start in Edit parameters.")
  end

  ImGui.Separator(ctx)
  look_items(fx, key, layout, cm.ctl, c, false)

  ImGui.Separator(ctx)
  -- Renaming here sets the parameter's ALIAS: the name sticks to the
  -- parameter for this plugin everywhere, panels and editor lists alike,
  -- rather than to this one slot. A slot-only caption is still available
  -- in the full editor for cramped layouts -- but this slot's own label,
  -- if it has one, is cleared, or it would go on hiding the new name on
  -- the very control you renamed.
  ImGui.TextDisabled(ctx, "Alias (this plugin, everywhere)")
  ImGui.SetNextItemWidth(ctx, 170)
  local _, v = ImGui.InputTextWithHint(ctx, "##alias", "name\u{2026}", app.rename_buf)
  local alias_enter = (ImGui.IsItemDeactivated(ctx) and (ImGui.IsKeyPressed(ctx, ImGui.Key_Enter) or ImGui.IsKeyPressed(ctx, ImGui.Key_KeypadEnter)))
  app.rename_buf = v
  ImGui.SameLine(ctx)
  if ImGui.Button(ctx, "Set") or alias_enter then
    local l = materialise(fx)
    local lc = l.controls[cm.ctl]
    if lc and lc.label and lc.label ~= "" then lc.label = ""; M.set(key, l) end
    M.set_alias(key, c.param, app.rename_buf)
    M.save()
    ImGui.CloseCurrentPopup(ctx)
  end

  -- A toggle's two states can have names of their own, for plugins whose
  -- switches read "0.0"/"1.0" or worse. Hints are what the plugin says.
  if c.type == "toggle" then
    ImGui.Separator(ctx)
    ImGui.TextDisabled(ctx, "State names (this plugin, everywhere)")
    local function hint(v)
      if reaper.TrackFX_FormatParamValueNormalized then
        local ok, t = reaper.TrackFX_FormatParamValueNormalized(app.track, fx.addr, c.param, v, "")
        if ok and t and t ~= "" then return t end
      end
      return v < 0.5 and "off" or "on"
    end
    ImGui.SetNextItemWidth(ctx, 82)
    local _, v1 = ImGui.InputTextWithHint(ctx, "##stoff", hint(0), app.state_buf[1])
    local e1 = (ImGui.IsItemDeactivated(ctx) and (ImGui.IsKeyPressed(ctx, ImGui.Key_Enter) or ImGui.IsKeyPressed(ctx, ImGui.Key_KeypadEnter)))
    app.state_buf[1] = v1
    ImGui.SameLine(ctx, 0, 6)
    ImGui.SetNextItemWidth(ctx, 82)
    local _, v2 = ImGui.InputTextWithHint(ctx, "##ston", hint(1), app.state_buf[2])
    local e2 = (ImGui.IsItemDeactivated(ctx) and (ImGui.IsKeyPressed(ctx, ImGui.Key_Enter) or ImGui.IsKeyPressed(ctx, ImGui.Key_KeypadEnter)))
    app.state_buf[2] = v2
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, "Set##states") or e1 or e2 then
      materialise(fx)
      M.set_states(key, c.param, app.state_buf[1], app.state_buf[2])
      M.save()
      ImGui.CloseCurrentPopup(ctx)
    end
    if ImGui.IsItemHovered(ctx) then
      ImGui.SetTooltip(ctx, "Off, then on. Leave one empty to keep the plugin's own text;\n" ..
                            "clear both to go back to it entirely.")
    end
  end

  ImGui.Separator(ctx)
  param_mod_item(fx, c)
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
    toggle_fold(fx)
  end
  if ImGui.MenuItem(ctx, "Move left", nil, false, fx.index > 0) then
    nudge(fx.path_t, -1)
  end
  if ImGui.MenuItem(ctx, "Move right", nil, false, fx.index < fx.siblings - 1) then
    nudge(fx.path_t, 1)
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
-- The "Toggle mixer view" action (TS_ChannelView_ToggleMixer.lua) can't
-- reach this window's keyboard -- nothing can, from inside it -- so it
-- leaves a request in the ExtState that each frame looks for, and says
-- which command it is so a toolbar button for it can light while the
-- mixer is showing. The heartbeat tells it whether this window is open.
local TOGGLE_REQ, TOGGLE_CMD, ALIVE = "toggle_mixer", "toggle_mixer_cmd", "cv_alive"
local function show_toggle_state(on)
  local sec, cmd = reaper.GetExtState(C.EXT_SECT, TOGGLE_CMD):match("^(%-?%d+):(%d+)$")
  if sec and tonumber(cmd) > 0 then
    reaper.SetToggleCommandState(tonumber(sec), tonumber(cmd), on and 1 or 0)
    reaper.RefreshToolbar2(tonumber(sec), tonumber(cmd))
  end
end

function set_view(mixer)
  C.MIXER_VIEW = mixer and true or false
  ext_set("mixer_view", C.MIXER_VIEW and "1" or "0")
  show_toggle_state(C.MIXER_VIEW)
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

-- The probes button. The selected tracks that have no TS_TrackProbe pair
-- (or just this one, if it isn't selected) get one, after a yes/no:
-- inserting rebuilds the FX chain, so it never happens on a stray click.
-- It only ever adds. Returns true when anything was added.
local PROBES_ABOUT =
  "A TS_TrackProbe at the start of the FX chain and another at the end.\n" ..
  "They measure gain reduction for plugins that don't report it (tick\n" ..
  "\"Measure gain reduction\" on the plugin), and they're what Track\n" ..
  "Analyser reads. They don't change the audio, and sit idle until\n" ..
  "something reads them."

local function confirm_probes()
  local list, need = {}, {}
  local tr_sel = false
  for i = 0, reaper.CountSelectedTracks(0) - 1 do
    local t = reaper.GetSelectedTrack(0, i)
    list[#list + 1] = t
    if t == app.track then tr_sel = true end
  end
  if not tr_sel then list = { app.track } end
  for _, t in ipairs(list) do
    if t ~= reaper.GetMasterTrack(0) and not TP.has_probes(t) then need[#need + 1] = t end
  end
  if #need == 0 then
    reaper.MB((#list > 1 and "These tracks already have their probes.\n\n"
                         or "This track already has its probes.\n\n") .. PROBES_ABOUT,
              "ChannelView", 0)
    return false
  end
  local what = (#need > 1)
    and ("Add probes to %d selected tracks?"):format(#need)
     or "Add probes to this track?"
  if reaper.MB(what .. "\n\n" .. PROBES_ABOUT .. "\n\nIt only ever adds: nothing is removed, " ..
               "reordered or replaced.", "ChannelView", 4) ~= 6 then
    return false
  end
  reaper.Undo_BeginBlock()
  local failed
  for _, t in ipairs(need) do
    local ok, why = TP.insert_probes(t)
    if not ok then failed = why break end
  end
  reaper.Undo_EndBlock("ChannelView: add TS_TrackProbe pairs", -1)
  TP.invalidate()
  if failed then reaper.MB(failed, "ChannelView", 0) end
  return true
end

-- The web companion's tablet, in the header while there's anything to
-- say: dim while the bridge runs with no page open, lit and filled in
-- while a page is connected, amber when a page is open but the bridge isn't running (a
-- click starts it). Hidden otherwise. See TS_CV_WebLink.
local weblink = WL.new()
local weblink_at = 0
local function web_indicator(ctx, x, mid_y)
  local now = reaper.time_precise()
  if now - weblink_at > 0.25 then
    weblink_at = now
    WL.update(weblink, now, reaper.GetExtState("TS_CV_WEB", "alive"),
                            reaper.GetExtState("TS_CV_WEB", "seen"))
  end
  local running, pages = WL.state(weblink, now)
  if not running and pages == 0 then return false end
  local ink, tip
  if not running then
    ink, tip = C.COL.warn, "A web page is open, but the web companion isn't running.\nClick to start it."
  elseif pages > 0 then
    ink = C.COL.accent
    tip = pages == 1 and "Web companion: a page is connected"
                      or ("Web companion: %d pages connected"):format(pages)
  else
    tip = "Web companion running \u{2014} no page connected"
  end
  ImGui.SetCursorScreenPos(ctx, x, mid_y - C.ICON_SIZE * 0.5)
  if W.icon_button(ctx, "weblink", (running and pages > 0) and "tablet_on" or "tablet",
                   C.ICON_SIZE, false, tip, nil, ink)
     and not running then
    if not SU.web(script_dir).start() then
      reaper.MB("Couldn't find TS_ChannelView_Web.lua in the Action List.", "ChannelView", 0)
    end
  end
  return true
end

local function menu_bar()
  if not ImGui.BeginMenuBar(ctx) then return end

  if ImGui.BeginMenu(ctx, "View") then
    if ImGui.MenuItem(ctx, "Values under controls", nil, C.SHOW_VALUES) then
      C.SHOW_VALUES = not C.SHOW_VALUES
      ext_set("show_values", C.SHOW_VALUES and "1" or "0")
    end
    -- off: the wheel never moves a control, it only scrolls (shared with
    -- the TCP window)
    if ImGui.MenuItem(ctx, "Use mouse wheel on controls", nil, C.WHEEL_CONTROLS) then
      C.WHEEL_CONTROLS = not C.WHEEL_CONTROLS
      ext_set("wheel_controls", C.WHEEL_CONTROLS and "1" or "0")
    end
    if ImGui.IsItemHovered(ctx) then
      ImGui.SetTooltip(ctx, "Off: the wheel scrolls, and never turns a knob or\nmoves a fader. Shared with the TCP window.")
    end

    -- the width of a control's column, for every panel
    if ImGui.BeginMenu(ctx, "Control spacing") then
      ImGui.SetNextItemWidth(ctx, 140)
      local cwch, cwv = ImGui.SliderInt(ctx, "##cell_w", C.CELL_W, C.CELL_W_MIN, C.CELL_W_MAX, "%d px")
      if cwch then
        C.set_cell_w(cwv)
        ext_set("cell_w", tostring(C.CELL_W))
      end
      if ImGui.IsItemHovered(ctx) then
        ImGui.SetTooltip(ctx, "How wide each control's column is: narrower packs panels tighter.\n" ..
          "Names that no longer fit are shortened. Ctrl+click to type a number.")
      end
      if ImGui.MenuItem(ctx, ("Reset to %d px"):format(C.CELL_W_DEFAULT), nil, false, C.CELL_W ~= C.CELL_W_DEFAULT) then
        C.set_cell_w(C.CELL_W_DEFAULT)
        ext_set("cell_w", tostring(C.CELL_W))
      end
      ImGui.EndMenu(ctx)
    end

    if ImGui.MenuItem(ctx, "Preset bar", nil, C.PRESET_BAR) then
      C.PRESET_BAR = not C.PRESET_BAR
      ext_set("preset_bar", C.PRESET_BAR and "1" or "0")
    end
    if ImGui.IsItemHovered(ctx) then
      ImGui.SetTooltip(ctx, "The plugin's presets along each panel's foot:\nload, save, save as default, rename, delete.")
    end

    if ImGui.MenuItem(ctx, "3D effect", nil, C.EFFECT_3D) then
      C.EFFECT_3D = not C.EFFECT_3D
      ext_set("plate_texture", C.EFFECT_3D and "1" or "0")
    end
    if ImGui.IsItemHovered(ctx) then
      ImGui.SetTooltip(ctx, "Light from the top left: a gentle gradient on coloured faceplates,\n" ..
        "panel edges that catch it, and soft shadows under knobs and buttons.\n" ..
        "Brushed and metallic finishes are chosen for each faceplate.")
    end

    if ImGui.MenuItem(ctx, "Track icons", nil, C.TRACK_ICONS) then
      C.TRACK_ICONS = not C.TRACK_ICONS
      ext_set("track_icons", C.TRACK_ICONS and "1" or "0")
    end
    if ImGui.IsItemHovered(ctx) then
      ImGui.SetTooltip(ctx, "Show REAPER's track icons above the name buttons.\n" ..
        "The row only grows when a track actually has one.")
    end

    -- Keyboard focus back to REAPER after a click here, so its shortcuts
    -- keep working. See TS_CV_Focus.
    do
      local how = FO.mechanism()
      if ImGui.MenuItem(ctx, "Return keyboard focus to REAPER", nil,
          C.FOCUS_BACK and how ~= nil, how ~= nil) then
        C.FOCUS_BACK = not C.FOCUS_BACK
        ext_set("focus_back", C.FOCUS_BACK and "1" or "0")
      end
      if ImGui.IsItemHovered(ctx) then
        ImGui.SetTooltip(ctx, how and
          "After a click or drag in ChannelView, the keyboard goes back to\n" ..
          "REAPER's arrange view, so Space and your other shortcuts keep\n" ..
          "working. Text fields and menus keep it until you're done."
          or "Needs the js_ReaScriptAPI or SWS extension (both on ReaPack).")
      end
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
    -- The web companion at startup too: the same fenced block the
    -- TS_ChannelView_Web_Startup action writes.
    do
      local WEB = SU.web(script_dir)
      if not WEB.checked() then WEB.resolve(); WEB.scan() end
      local st, note = WEB.state()
      if ImGui.MenuItem(ctx, "Start web companion with REAPER", nil, WEB.on(),
          st ~= "nocmd" and st ~= "manual") then
        local ok, why
        if WEB.on() then ok, why = WEB.remove() else ok, why = WEB.add() end
        if not ok then
          reaper.MB("__startup.lua was NOT changed.\n\n" .. tostring(why), "ChannelView", 0)
        elseif WEB.on() and not WEB.running() and
               reaper.MB("The web companion will start with REAPER from now on.\n\n" ..
                         "Start it now as well?", "ChannelView", 4) == 6 then
          WEB.start()
        end
      end
      if ImGui.IsItemHovered(ctx) then
        ImGui.SetTooltip(ctx, "Runs TS_ChannelView_Web.lua when REAPER starts, so the\n" ..
                              "tablet page works without starting it by hand.")
      end
      if st == "nocmd" then
        note = "TS_ChannelView_Web.lua isn't in the Action List."
      end
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
        pal_set(hv, C.TINT)
      end

      ImGui.SetNextItemWidth(ctx, 190)
      local tch, tv = ImGui.SliderDouble(ctx, "Tint", C.TINT, 0.0, 2.0, "%.2f")
      if tch then
        C.TINT = tv
        C.build_palette()
        pal_set(C.BASE_HUE, tv)
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
        pal_set(219, 1.0)
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
    SU.web(script_dir).forget()
  end

  if ImGui.BeginMenu(ctx, "Layouts") then
    if ImGui.MenuItem(ctx, "Reload library from disk") then M.reload() end
    if ImGui.MenuItem(ctx, "Save library now") then M.save() end
    ImGui.Separator(ctx)
    -- sharing: some of your layouts to a file, or someone else's into yours
    if ImGui.MenuItem(ctx, "Import layouts from file\u{2026}") then LS.start_import() end
    if ImGui.MenuItem(ctx, "Export layouts to file\u{2026}") then
      local cur = {}
      for _, fx in ipairs(app.chain or {}) do cur[#cur + 1] = U.plugin_key(fx.name) end
      LS.start_export(cur)
    end
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

  -- The view toggle sits on the left, straight after the menus; the
  -- title's left limit moves past it.
  do
    local tw = C.ICON_SIZE + 10
    if fx_left - menus_right > tw + 40 then
      ImGui.SameLine(ctx, 0, 0)
      ImGui.SetCursorScreenPos(ctx, menus_right + 6, mid_y - C.ICON_SIZE * 0.5)
      view_toggle(ctx, mid_y)
      menus_right = menus_right + tw
    end
  end

  -- The web companion's tablet, straight after the view toggle.
  do
    local tw = C.ICON_SIZE + 4
    if fx_left - menus_right > tw + 40 then
      ImGui.SameLine(ctx, 0, 0)
      if web_indicator(ctx, menus_right + 2, mid_y) then menus_right = menus_right + tw end
    end
  end

  -- Load an FX chain, left of the FX bypass.
  if app.track then
    local tw = C.ICON_SIZE + 6
    if fx_left - menus_right > tw + 40 then
      ImGui.SameLine(ctx, 0, 0)
      ImGui.SetCursorScreenPos(ctx, fx_left - tw, mid_y - C.ICON_SIZE * 0.5)
      if W.icon_button(ctx, "fxchainload", "chain", C.ICON_SIZE, false,
          "Load an FX chain onto this track") then
        CN.open(app.track)
      end
      fx_left = fx_left - tw
    end
  end

  -- Probes, left of the FX chain button: the TS_TrackProbe pair that
  -- measured gain reduction (and Track Analyser) need.
  if app.track then
    local tw = C.ICON_SIZE + 6
    if fx_left - menus_right > tw + 40 then
      ImGui.SameLine(ctx, 0, 0)
      ImGui.SetCursorScreenPos(ctx, fx_left - tw, mid_y - C.ICON_SIZE * 0.5)
      local have = TP.has_probes(app.track)
      if W.icon_button(ctx, "probes", "probe", C.ICON_SIZE, false,
          have and "Probes in place" or "Add probes") then
        if confirm_probes() then rescan(true) end
      end
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

-- The bracket strip: one bracket per FX container and per run of plugins
-- in parallel, over the panels they hold, drawn after the panels so the
-- rectangles are known. A container's square opens its menu.
local function bracket_tip(b)
  if b.kind == "container" then
    local n = b.node
    local inside = #(n.children or {})
    local t = ("Container: %s \u{2014} %d %s"):format(box_label(n), inside,
      inside == 1 and "slot" or "slots")
    if not T.get_enabled(app.track, n.addr) then t = t .. "\nBypassed" end
    if n.parallel ~= 0 then t = t .. "\nRuns in parallel with the one before it" end
    return t .. "\n\nClick for the container's menu"
  end
  local lines = { "Running in parallel:" }
  for k, m in ipairs(b.members) do
    local nm = m.kind == "container" and ("container " .. box_label(m)) or (m.alias or U.fx_label(m))
    if k > 1 and m.parallel == 2 then nm = nm .. "  (MIDI merged)" end
    lines[#lines + 1] = "  \u{2022} " .. nm
  end
  lines[#lines + 1] = "\nREAPER adds their outputs together. Right-click a\npanel \u{25B8} Route to change it."
  return table.concat(lines, "\n")
end

-- Each bracket's line is on its row of the strip (the outermost at the
-- top, T.groups), and its ends come down to its first and last panels.
-- Panels only drop as far as the brackets over them need, so a group one
-- row deep sits higher than one two rows deep -- inside one container too.
local function draw_brackets()
  if app.brk_rows == 0 or not app.track then return end
  local dl = ImGui.GetWindowDrawList(ctx)
  local rect = {}
  for _, r in ipairs(app.panel_rects) do rect[r.chain_i] = r end
  for _, b in ipairs(app.brackets) do
    local ra, rb = rect[b.first], rect[b.last]
    if ra and rb then
      local box = b.kind == "container"
      local col = box and C.COL.brk_container or C.COL.brk_parallel
      local off = box and not T.get_enabled(app.track, b.node.addr)
      if off then col = U.with_alpha(col, 0x80) end
      local x1, x2 = math.floor(ra.x + 3) + 0.5, math.floor(rb.x + rb.w - 3) + 0.5
      -- its line on its row, counted from the top of the strip; each end
      -- comes down to the top of its own panel, which drops only as far
      -- as the brackets over that panel need
      local ly = math.floor((app.brk_top or ra.y) + (b.row + 0.5) * C.BRK_ROW_H) + 0.5
      local sq = 7
      local label = box and box_label(b.node) or nil
      local tw, th = 0, 0
      if label then
        tw, th = ImGui.CalcTextSize(ctx, label)
        if tw + sq + 4 + 30 > x2 - x1 then label, tw = nil, 0 end
      end
      local mw = box and (sq + (label and (4 + tw) or 0)) or 6
      local mid = math.floor((x1 + x2) * 0.5)
      local m1, m2 = mid - mw * 0.5 - 3, mid + mw * 0.5 + 3
      ImGui.DrawList_AddLine(dl, x1, ra.y - 1, x1, ly, col, 1.5)
      ImGui.DrawList_AddLine(dl, x1, ly, m1, ly, col, 1.5)
      ImGui.DrawList_AddLine(dl, m2, ly, x2, ly, col, 1.5)
      ImGui.DrawList_AddLine(dl, x2, ly, x2, rb.y - 1, col, 1.5)
      if box then
        local sx = mid - mw * 0.5
        if off then
          ImGui.DrawList_AddRect(dl, sx + 0.5, ly - 3, sx + sq - 0.5, ly + 3, col, 0, 0, 1.0)
        else
          ImGui.DrawList_AddRectFilled(dl, sx, ly - 3.5, sx + sq, ly + 3.5, col)
        end
        if label then
          ImGui.DrawList_AddText(dl, sx + sq + 4, ly - th * 0.5, col, label)
        end
      else
        ImGui.DrawList_AddLine(dl, mid - 2, ly - 4, mid - 2, ly + 4, col, 1.5)
        ImGui.DrawList_AddLine(dl, mid + 2, ly - 4, mid + 2, ly + 4, col, 1.5)
      end
      local id = ("brk%s%d_%d_%d"):format(b.kind:sub(1, 1), b.first, b.last, b.row)
      ImGui.SetCursorScreenPos(ctx, m1, ly - C.BRK_ROW_H * 0.5)
      ImGui.InvisibleButton(ctx, id, math.max(1, m2 - m1), C.BRK_ROW_H,
        ImGui.ButtonFlags_MouseButtonLeft | ImGui.ButtonFlags_MouseButtonRight)
      local hov = ImGui.IsItemHovered(ctx)
      W.tip(ctx, id, bracket_tip(b), hov, false)
      if box and (ImGui.IsItemClicked(ctx, ImGui.MouseButton_Left)
                  or ImGui.IsItemClicked(ctx, ImGui.MouseButton_Right)) then
        app.box_for, app.open_box_menu = b.node, true
      end
    end
  end
  -- (no putting the cursor back: a SetCursorScreenPos with no item after
  -- it would trip ImGui's check on the child's bounds at EndChild)
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
      -- Only the panels under a bracket give up height, and only as many
      -- rows as their own brackets stack: the outermost one over them.
      local drop = {}
      for _, b in ipairs(app.brackets) do
        local d = (b.row + 1) * C.BRK_ROW_H + C.BRK_PAD
        for k = b.first, b.last do drop[k] = math.max(drop[k] or 0, d) end
      end
      local function panel_h(i) return inner_h - (drop[i] or 0) end

      if C.ROW_ALIGN == "centre" and #app.chain > 0 then
        local total = C.PANEL_GAP + C.ADD_TILE_W
        for i, fx in ipairs(app.chain) do
          local lay, k = layout_for(fx)
          local has_meter = M.meter_of(lay) ~= nil
                            and T.reports_gr(app.track, fx.addr, fx.guid)
          total = total + P.width(lay.controls or {}, panel_h(i),
                                  St.is_collapsed(fx.guid), has_meter, k,
                                  P.has_io(app.track, fx, lay),
                                  St.is_gr_open(fx.guid), M.locked(lay))
          if i > 1 then total = total + C.PANEL_GAP end
        end
        local avail_w = ImGui.GetContentRegionAvail(ctx)
        if total < avail_w then
          ImGui.SetCursorPosX(ctx, ImGui.GetCursorPosX(ctx) + (avail_w - total) * 0.5)
        end
      end

      local row_top = select(2, ImGui.GetCursorScreenPos(ctx))
      app.brk_top = row_top
      if #app.chain == 0 then
        ImGui.TextDisabled(ctx, "No plugins on this track yet \u{2014}")
        ImGui.SameLine(ctx)
      end
      for i, fx in ipairs(app.chain) do
        if i > 1 then ImGui.SameLine(ctx, 0, C.PANEL_GAP) end
        local px = ImGui.GetCursorScreenPos(ctx)
        local py = row_top + (drop[i] or 0)
        ImGui.SetCursorScreenPos(ctx, px, py)
        local layout, key = layout_for(fx)
        local is_src = app.drag ~= nil and app.drag.guid == fx.guid
        local w, req = P.draw(ctx, app.track, fx, layout, key, panel_h(i), i, is_src)

        app.panel_rects[#app.panel_rects + 1] = {
          chain_i   = i,
          x         = px,
          y         = py,
          w         = w,
        }

        if req.toggle_bypass then
          T.set_enabled(app.track, fx.addr, not T.get_enabled(app.track, fx.addr))
        end
        if req.toggle_float then
          T.toggle_float(app.track, fx.addr)
        end
        if req.toggle_collapse then
          toggle_fold(fx)
        end
        if req.begin_drag and not app.drag then
          app.drag = { chain_i = i, guid = fx.guid, path = fx.path_t,
                       what = fx.is_container and "container" or "plugin" }
        end
        if req.open_menu then
          app.menu_fx = i
          app.open_panel_menu = true
        end
        if req.open_editor and not M.locked(layout) then
          E.open(app.track, fx, key, layout)
        end
        -- the padlock: lock at the rows the panel has now, or unlock
        if req.toggle_lock ~= nil then
          if E.is_open() and E.key() == key then
            reaper.MB("Close Edit parameters for " .. key .. " first: saving it would\n" ..
                      "undo the lock.", "ChannelView", 0)
          else
            local l = materialise(fx)
            l.lock = req.toggle_lock or nil
            M.set(key, l); M.save()
          end
        end
        if req.grv_window then
          local l = materialise(fx)
          if l.meter then l.meter.win = (req.grv_window ~= C.GRV_DEFAULT) and req.grv_window or nil end
          M.set(key, l); M.save()
        end
        if req.ctx_control then
          app.ctl_menu = { fx = i, ctl = req.ctx_control }
          local c = layout.controls and layout.controls[req.ctx_control]
          local pn = ""
          if c and c.param then
            _, pn = reaper.TrackFX_GetParamName(app.track, fx.addr, c.param, "")
          end
          -- starts as the name the control shows now
          app.rename_buf = c and c.param
            and M.display_name(key, c.param, c.label, pn, false) or pn or ""
          local st = c and c.param and M.get_states(key, c.param)
          app.state_buf = { st and st[1] or "", st and st[2] or "" }
          app.open_ctl_menu = true
        end
      end

      -- Trailing tile: adds to the END of the chain. Inserting at a
      -- specific point is the panel menu's "Insert plugin before/after",
      -- which knows which slot it's next to.
      if #app.chain > 0 then
        ImGui.SameLine(ctx, 0, C.PANEL_GAP)
        ImGui.SetCursorScreenPos(ctx, ImGui.GetCursorScreenPos(ctx), row_top)
      end
      if add_tile(inner_h) then B.open_menu(nil) end
      draw_brackets()
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
    -- The marker takes the container's colour when the drop goes into
    -- one, and says which.
    if app.drag then
      local mx = ImGui.GetMousePos(ctx)
      local drop = app.track and drop_under(mx) or nil
      app.drop_gap = drop
      if drop then
        local dl = ImGui.GetWindowDrawList(ctx)
        local wy = select(2, ImGui.GetWindowPos(ctx))
        local wh = select(2, ImGui.GetWindowSize(ctx))
        ImGui.DrawList_AddRectFilled(dl, drop.x - 1.5, wy + 2,
          drop.x + 1.5, wy + wh - 2, drop.into and C.COL.brk_container or C.COL.drop_marker, 1.0)
        if drop.into then
          ImGui.SetTooltip(ctx, "Into " .. box_label(drop.into))
        end
      end
      if not ImGui.IsMouseDown(ctx, ImGui.MouseButton_Left) then
        if drop then move_to(app.drag.path, drop.parent, drop.gap, app.drag.what) end
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

-- Hue and Tint, track icons, values under controls and keyboard focus
-- can all be changed from ChannelView TCP as well, which writes the same
-- keys; looked at twice a second so the two windows keep one setting.
local colour_poll = 0

local function frame()
  W.begin_frame()
  P.begin_frame()
  follow_selection()
  do
    local now = reaper.time_precise()
    if now - colour_poll > 0.5 then
      colour_poll = now
      do
        local h, t = pal_get()
        C.apply_colour(h or C.BASE_HUE, t or C.TINT)
      end
      -- and the view options the two windows share
      C.TRACK_ICONS = ext_get("track_icons", "0") == "1"
      C.SHOW_VALUES = ext_get("show_values", "1") == "1"
      C.WHEEL_CONTROLS = ext_get("wheel_controls", "1") == "1"
      C.FOCUS_BACK  = ext_get("focus_back", "1") == "1"
      TO.reload_fader_defaults()      -- the TCP window may have changed them
      C.set_cell_w(ext_get("cell_w", tostring(C.CELL_W_DEFAULT)))
    end
  end
  -- The name row's height for this whole frame: taller while any track
  -- in it has an icon to show. Set once, here, before anything is laid
  -- out (the row itself reports what it found at the end of the last
  -- frame).
  C.set_icon_row(C.TRACK_ICONS and MX.any_icon)

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
  -- the Toggle mixer view action, from a shortcut or a toolbar
  if reaper.GetExtState(C.EXT_SECT, TOGGLE_REQ) ~= "" then
    reaper.DeleteExtState(C.EXT_SECT, TOGGLE_REQ, false)
    set_view(not C.MIXER_VIEW)
  end
  do
    local now = reaper.time_precise()
    if not app.alive_t or now - app.alive_t > 0.5 then
      app.alive_t = now
      reaper.SetExtState(C.EXT_SECT, ALIVE, tostring(now), false)
    end
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
    -- Channel pinned left, Sends and Receives pinned right, the plugin
    -- row scrolling between them. The pinned panels are measured first so
    -- the row in the middle knows what is left for it.
    local full_w = ImGui.GetContentRegionAvail(ctx)
    local ch_w   = CH.width(CH.is_collapsed())
    -- The master has no Receives panel: every track feeds it, and the
    -- list would only ever be the odd real send to the master.
    local on_master = app.track ~= nil and app.track == reaper.GetMasterTrack(0)
    local rv_w   = on_master and 0 or RV.width_for(app.track, row_h)
    local sd_w   = SD.width_for(app.track, row_h)
    local mid_w  = math.max(80, full_w - ch_w - rv_w - sd_w
                                - C.PANEL_GAP * (on_master and 2 or 3))

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
      if not on_master then
        ImGui.SameLine(ctx, 0, C.PANEL_GAP)
        local _, rv_req = RV.draw(ctx, app.track, row_h)
        if rv_req and rv_req.changed then rescan(true) end
      end

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
    if app.open_box_menu   then ImGui.OpenPopup(ctx, "boxmenu");   app.open_box_menu   = false end
    panel_menu()
    control_menu()
    box_menu()

    E.draw(ctx, app.track)
    if SD.draw_menu(ctx, app.track) then rescan(true) end
    if SD.draw_ctx(ctx, app.track) then rescan(true) end
    if RV.draw_menu(ctx, app.track) then rescan(true) end
    if RV.draw_ctx(ctx, app.track) then rescan(true) end
    if B.draw_menu(ctx, app.track) then rescan(true) end
    if B.draw(ctx, app.track) then rescan(true) end
    PU.draw(ctx)
    if LS.draw(ctx, function(k) return E.is_open() and E.key() == k end) then rescan(true) end
    if TM.draw(ctx) then rescan(true) end
    CP.draw(ctx)
    if CN.draw(ctx) then rescan(true) end

    -- Probe taps: the heartbeat that keeps them measuring, and one
    -- track's routing re-checked per frame.
    TP.update()
    FO.update(ctx, ImGui, C.FOCUS_BACK)

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
  local report = "\n--- ChannelView stopped on an error -------------------------\n" ..
    tostring(err) ..
    "\n-------------------------------------------------------------\n"
  reaper.ShowConsoleMsg(report)
  -- And to a file beside the script: the console can open somewhere it
  -- can't be seen (off a screen that's since been unplugged), and an
  -- error nobody can read is an error nobody can fix.
  local fh = io.open(script_dir .. "TS_ChannelView_error.log", "a")
  if fh then fh:write(os.date("%Y-%m-%d %H:%M:%S"), report); fh:close() end
end

reaper.atexit(function()
  M.save(); SC.save()
  reaper.DeleteExtState(C.EXT_SECT, ALIVE, false)
  show_toggle_state(false)      -- no window, no mixer showing
end)
reaper.DeleteExtState(C.EXT_SECT, TOGGLE_REQ, false)   -- one left from a window since closed
show_toggle_state(C.MIXER_VIEW)
reaper.defer(safe_frame)
