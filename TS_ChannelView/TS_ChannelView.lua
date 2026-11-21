-- @description ChannelView -- docked channel strip: one editable control panel per plugin
-- @author Tim Shadgett
-- @version 4.5.1
-- @changelog
--  The whole FX chain bypassed shows BYPASSED on every panel. Sends: New
--  track with plugin. TS_TrackProbe 2.9.0 (reopen a project after
--  updating). Fixed a memory leak from vertical text.
--  Moves with ChannelView Pro 4.5.1. See the CHANGELOG.
-- @license MIT
-- @provides
--  [main]   TS_CV_Diag.lua
--  [main]   TS_ChannelView_TCP.lua
--  [main]   TS_ChannelView_ToggleMixer.lua
--  [main]   TS_ChannelView_BypassModulation.lua
--  [main]   TS_ChannelView_ToggleToolbars.lua
--  [webinterface] TS_CV_ActionIcons.json
--  [nomain] TS_CV_Actions.lua
--  [nomain] TS_CV_Arrange.lua
--  [nomain] TS_CV_Toolbar.lua
--  [nomain] TS_CV_Browser.lua
--  [nomain] TS_CV_Mod.lua
--  [nomain] TS_CV_Units.lua
--  [nomain] TS_CV_ReaFX.lua
--  [nomain] TS_CV_ModRack.lua
--  [nomain] TS_CV_ModPat.lua
--  [nomain] TS_CV_Busy.lua
--  [nomain] TS_CV_MidiLearn.lua
--  [nomain] TS_CV_Drawers.lua
--  [nomain] TS_CV_Style.lua
--  [nomain] TS_CV_Containers.lua
--  [nomain] TS_CV_ActionEditor.lua
--  [nomain] TS_CV_ActionIcons.lua
--  [main]   TS_ChannelView_Toolbars.lua
--  [main]   TS_ChannelView_OrganiseActions.lua
--  [nomain] TS_CV_ProbeLink.lua
--  [nomain] TS_CV_Chains.lua
--  [nomain] TS_CV_ColourPick.lua
--  [nomain] TS_CV_Channel.lua
--  [nomain] TS_CV_Config.lua
--  [nomain] TS_CV_Edition.lua
--  [nomain] TS_CV_Editor.lua
--  [nomain] TS_CV_Envelopes.lua
--  [nomain] TS_CV_ReaComp.lua
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
--  [nomain] TS_CV_Carry.lua
--  [nomain] TS_CV_Upkeep.lua
--  [nomain] TS_CV_Steps.lua
--  [nomain] TS_CV_Taps.lua
--  [nomain] TS_CV_Trace.lua
--  [nomain] TS_CV_TrackMenu.lua
--  [nomain] TS_CV_TrackOps.lua
--  [nomain] TS_CV_TrackRules.lua
--  [nomain] TS_CV_TrackStrip.lua
--  [nomain] TS_CV_FXButtons.lua
--  [nomain] TS_CV_KnobParts.lua
--  [nomain] TS_CV_Freeze.lua
--  [nomain] TS_CV_AutoFloat.lua
--  [nomain] TS_CV_Menus.lua
--  [nomain] TS_CV_Util.lua
--  [nomain] TS_CV_VisualOptions.lua
--  [nomain] TS_CV_Widgets.lua
--  [nomain] TS_CV_WebLink.lua
--  [nomain] TS_CV_GainCheck.lua
--  [nomain] TS_CV_Learn.lua
--  [effect] TS_TrackProbe.jsfx
--  [effect] TS_CV_Modulators.jsfx
--  [effect] TS_CV_Learn.jsfx
-- @about
--  A dockable window showing one panel per plugin on the selected track.
--  Each panel carries a float button, a bypass button and a set of knobs
--  and buttons wired straight to that plugin's parameters -- what you
--  assign to a panel is remembered per plugin, so the same plugin always
--  comes up looking the same wherever it turns up.
--
--  ChannelView Pro, an add-on installed from its own ReaPack link (the same
--  version as this), adds grid layouts and the grid editor, the Rack view,
--  the web companion, canvases, hardware looks and the rest the README
--  marks (Pro). Layouts made with it still work here, drawn plainly.
--
--  Action bars: buttons for any REAPER action, with menus, toolbar
--  switches and ChannelView's own icons, as drawers in this window, in
--  windows of their own (TS_ChannelView_Toolbars.lua), in the TCP window
--  and on the web page -- all arranged in Organise actions.
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
--  Macros and modulators are the idea of Saxmand's FX Modulator Linking
--  (Jesper Ankarfeldt), with thanks; none of its code or JSFX is used, and
--  ChannelView doesn't read or need setups made with it.
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
local ST = require("TS_CV_Style")
-- Standard, or with Pro (TS_CV_Edition): Pro's modules are there only with
-- it; without, those called from many places are stand-ins doing nothing
local ED = require("TS_CV_Edition")
local SWI = ED.switches()
local P = require("TS_CV_Panel")
local E  = require("TS_CV_Editor")
local S  = require("TS_CV_TrackStrip")
local St = require("TS_CV_State")
local B  = require("TS_CV_Browser")
local PU = require("TS_CV_PresetUI")
local LS = require("TS_CV_Share")
local CS = ED.module("TS_CV_CanvasSetup", ED.stub({ TIPS = {} }))
local SC = require("TS_CV_Steps")
local CH = require("TS_CV_Channel")
local SD = require("TS_CV_Sends")
local RV = require("TS_CV_Receives")
local MX = require("TS_CV_Mixer")
local SU = require("TS_CV_Startup")
local FZ = require("TS_CV_Freeze")
local AF = require("TS_CV_AutoFloat")
local PC = ED.module("TS_CV_PluginColours", ED.stub())
local FB = require("TS_CV_FXButtons")
local WL = require("TS_CV_WebLink")
local TM = require("TS_CV_TrackMenu")
local TO = require("TS_CV_TrackOps")
local CP = require("TS_CV_ColourPick")
local FO = require("TS_CV_Focus")
local TRM = ED.module("TS_CV_Trimmer")
local IC = require("TS_CV_Icons")
local CN = require("TS_CV_Chains")
local TP = require("TS_CV_Taps")
local RQ = require("TS_CV_ReaEQ")
local RC = require("TS_CV_ReaComp")
local BZ = require("TS_CV_Busy")
local ML = require("TS_CV_MidiLearn")
local MD = require("TS_CV_Mod")
local CT = require("TS_CV_Containers")
local MR = require("TS_CV_ModRack")
local TB = require("TS_CV_Toolbar")
local DR = require("TS_CV_Drawers")
local AE = require("TS_CV_ActionEditor")
local KE = ED.module("TS_CV_KnobEditor", ED.stub())
local KPm = require("TS_CV_KnobParts")
local RCP = ED.module("TS_CV_Recipes", ED.stub({ list = function() return {} end }))

-- RACK VIEW: the same ChannelView, run by TS_ChannelView_Rack.lua in a
-- window of its own -- the track's plugins down a column, toolbars of its
-- own on every side, no fader panel, track names or mixer (the track is
-- whichever REAPER has selected). Everything else -- layouts, settings,
-- the web companion -- is shared; the library merges both windows' saves
-- (TS_CV_Mappings M.sync).
local RACK = rawget(_G, "TS_CV_RACK") == true
-- popped-out panels (Pro): windows of ChannelView's own, not the rack's
-- (POP.PO the module; the rest of POP further down)
local POP = {}
POP.PO = (not RACK) and ED.module("TS_CV_PopOut") or nil
-- comparing two plugins (Pro): the bar is the row's; the rack still
-- leaves the switch out of its column
POP.CMP = ED.module("TS_CV_Compare")
if RACK then C.WIN_TITLE = "ChannelView Rack" end

-- ChannelView Pro at another version: said once for each pair of
-- versions (and in the header while it lasts). The Rack is Pro's, so it
-- says so every time and doesn't start.
if RACK and ED.mismatch then ED.warn_mismatch(true) do return end end
ED.warn_mismatch()

W.attach(ImGui); P.attach(ImGui); E.attach(ImGui); S.attach(ImGui); B.attach(ImGui)
CH.attach(ImGui); SD.attach(ImGui); RV.attach(ImGui); MX.attach(ImGui); TM.attach(ImGui); IC.attach(ImGui)
CN.attach(ImGui); LS.attach(ImGui); MR.attach(ImGui); CS.attach(ImGui); ML.attach(ImGui)
TB.attach(ImGui); DR.attach(ImGui); AE.attach(ImGui); KE.attach(ImGui)
if ED.PRO then require("TS_CV_GridEditor").attach(ImGui) end
if ED.PRO then ED.module("TS_CV_ConsoleSetup", ED.stub()).attach(ImGui) end
-- DrumToolbox Pro's panel, when it's installed (TS_CV_DrumPanel)
if ED.PRO then ED.module("TS_CV_DrumPanel", ED.stub()).attach(ImGui) end
if POP.CMP then POP.CMP.attach(ImGui); P.over_panel = POP.CMP.overlay end
-- action drawers (global, not per project), and the window that organises
-- every action bar
DR.load()
if RACK then
  DR.host("rack"); P.RACK = true
  -- its panels fold on their own, apart from ChannelView's
  St.COLLAPSED, St.FOLD = "rcollapsed:", "rfold:"
  MR.EXT_PFX = "rack_"
  -- its layouts picked apart from ChannelView's (each falls back to
  -- ChannelView's until one is picked here)
  St.VARIANT = "rvariant:"
  M.VIEW_DEFAULTS = M.RACK_DEFAULTS_SECT
  -- its panels fold upwards: chevrons point up to fold, down to unfold
  W.CHEVRONS_UPDOWN = true
end
DR.organise = function(d, it) AE.open(d, it) end
DR.share = function(mode) AE.share(mode) end
-- a learning track left behind by a ChannelView stopped mid-learn
pcall(function() require("TS_CV_Learn").sweep() end)

-- Asked for while the action context still belongs to this script, so the
-- startup option has a real command id to write. Harmless if REAPER hasn't
-- given us one yet -- the option then says so instead of writing a dead
-- line into __startup.lua. The rack has a block of its own (its own
-- markers and command id), so either can start with REAPER without the
-- other.
local SU_ME = RACK and SU.make("ChannelView Rack", "TS_ChannelView_Rack.lua", "channelview_rack_cmd") or SU
SU_ME.init()
M.init(script_dir)
SC.init(script_dir)
RCP.init(script_dir)
if ED.PRO then require("TS_CV_Finish").init(script_dir) end

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

-- The panels besides the plugins, each of which can be hidden (View
-- menu). ChannelView and the rack choose apart.
local AUX = {
  { key = "macros", label = "Macros" },
  { key = "mods",   label = "Modulators" },
  { key = "sends",  label = "Sends" },
  { key = "recv",   label = "Receives" },
}
local AUX_PFX = RACK and "rack_" or "show_"
app.aux = {}
for _, a in ipairs(AUX) do app.aux[a.key] = ext_get(AUX_PFX .. a.key, "1") == "1" end
-- View > Float plugins without controls (TS_CV_AutoFloat): the rack keeps
-- its own
local FLOAT_KEY = RACK and "rack_float_empty" or "float_empty"
app.float_empty = ext_get(FLOAT_KEY, "0") == "1"
-- Auto-hide the header (for a small screen): the panels take its room,
-- and it slides out over them while the pointer is at the window's top
-- edge or on it. ChannelView and the rack each keep their own.
app.hide_key = RACK and "rack_header_hide" or "header_hide"
app.header_hide = ext_get(app.hide_key, "0") == "1"
app.header_out = nil      -- when the hidden header last had the pointer

-- ---------------------------------------------------------------------
-- THE SHARED PALETTE
--
--   Hue and tint are one choice for the whole TS_ family, not one per
--   tool, so they live in their own ExtState section rather than in any
--   one tool's. ChannelView, the TCP window, TS_Visualizer and its editor
--   all read and write this one section, so none of them depends on a
--   section name that belongs to another tool.
--
--   Reading falls back to ChannelView's own section when the shared one
--   is empty, so a setting kept there still loads instead of the colours
--   snapping back to stock. Nothing anywhere returns a default: nil means
--   "no shared setting", and each tool keeps its own, which is what lets
--   any of them run on its own.
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

local DOCK_KEY = RACK and "rack_dock" or "dock"
local dock_id = tonumber(ext_get(DOCK_KEY, "0")) or 0
C.SHOW_VALUES = ext_get("show_values", C.SHOW_VALUES and "1" or "0") == "1"
C.WHEEL_CONTROLS = ext_get("wheel_controls", "1") == "1"
C.set_channel_w(ext_get("channel_w", tostring(C.CHANNEL_W_DEFAULT)))
C.PRESET_BAR = ext_get("preset_bar", C.PRESET_BAR and "1" or "0") == "1"
-- Which of the two views is up. Persisted, because reopening the window
-- into the view you were not in is a small daily annoyance.
C.MIXER_VIEW  = (not RACK) and ext_get("mixer_view", "0") == "1"
C.ROW_ALIGN   = ext_get("row_align", C.ROW_ALIGN)
C.FOCUS_BACK  = ext_get("focus_back", "1") == "1"
U.ADAPTIVE    = ext_get("adaptive_units", "0") == "1"
-- View > Options: colours, the default control styles, panels,
-- track buttons, sizes and depth -- the rack's own tab, or ChannelView's
-- (TS_CV_VisualOptions; it brings older settings over the first time)
app.VO = require("TS_CV_VisualOptions")
app.vo_tab = RACK and "rack" or "cv"
-- Options ▸ Behaviour's "Float plugins without controls" (this window's own)
app.VO.float = {
  get = function() return app.float_empty end,
  assign = function(v) app.float_empty = v; ext_set(FLOAT_KEY, v and "1" or "0") end,
}
app.VO.load(not RACK)
app.VO.apply(app.vo_tab)
app.VO.attach(ImGui)
CH.group_looks = function() app.VO.show(app.vo_tab, "faders") end
-- the default knob built from parts: in the knob look editor
app.VO.customise = ED.PRO and function(start, apply)
  KE.open({ title = "Default knob", look = start, apply = function(look) apply(look) end })
end or nil

-- ---------------------------------------------------------------------
-- chain tracking
-- ---------------------------------------------------------------------

-- The rack locked to one track (the padlock in its header bar): it stays
-- on that track whatever's selected. Kept with the project, by the track's
-- GUID; a track that's gone unlocks it.
local rack_lock = { proj = nil, guid = nil, track = nil }
local function rack_lock_set(guid)
  rack_lock.guid, rack_lock.track = guid, nil
  reaper.SetProjExtState(0, C.EXT_SECT, "rack_lock", guid or "")
end
local function locked_track()
  local proj = reaper.EnumProjects(-1)
  if proj ~= rack_lock.proj then
    rack_lock.proj = proj
    local _, g = reaper.GetProjExtState(0, C.EXT_SECT, "rack_lock")
    rack_lock.guid, rack_lock.track = (g ~= "") and g or nil, nil
  end
  if not rack_lock.guid then return nil end
  local tr = rack_lock.track
  if tr and reaper.ValidatePtr2(0, tr, "MediaTrack*") and reaper.GetTrackGUID(tr) == rack_lock.guid then return tr end
  local master = reaper.GetMasterTrack(0)
  if reaper.GetTrackGUID(master) == rack_lock.guid then rack_lock.track = master return master end
  for i = 0, reaper.CountTracks(0) - 1 do
    local t = reaper.GetTrack(0, i)
    if reaper.GetTrackGUID(t) == rack_lock.guid then rack_lock.track = t return t end
  end
  rack_lock_set(nil)
  return nil
end

local function current_track()
  if RACK then
    local tr = locked_track()
    if tr then return tr end
  end
  return reaper.GetSelectedTrack2(0, 0, true)
end

local function track_valid(tr)
  return tr ~= nil and reaper.ValidatePtr2(0, tr, "MediaTrack*")
end

local function rescan(force)
  -- asked from a popped-out panel's menu (app.track is its track for the
  -- moment): done for ChannelView's own track once that's back
  if app.popout then app.popout_dirty = true return end
  local now = reaper.time_precise()
  if not force and (now - app.last_scan) < C.RESCAN_INTERVAL then return end
  app.last_scan = now
  -- ChannelView Modulators (TS_CV_Mod) has panels of its own, Macros
  -- and Modulators; it isn't a plugin in the row. Nor are the probes,
  -- unless they're asked for -- and while they're out of sight they're
  -- kept at the ends of the chain (TS_CV_Upkeep, with the rest of what's
  -- kept right on the selected tracks, by whichever window holds it).
  local list = {}
  local full = app.track and T.collect(app.track) or nil
  local took
  full, took = require("TS_CV_Upkeep").run(now, app.track, full)
  if took then St.clear_cache() end
  if app.track then
    list = MD.strip(app.track, full)
    if not TP.probes_shown() then list = TP.strip_probes(app.track, list) end
    if POP.CMP then list = POP.CMP.strip(app.track, list) end
    -- the console's plugins, when its panel stands for them (Pro)
    if ED.PRO then list = ED.module("TS_CV_ConsoleDrawer", ED.stub()).strip(app.track, list) or list end
    -- and DrumToolbox's, which its panel stands for (Pro)
    if ED.PRO then list = ED.module("TS_CV_DrumPanel", ED.stub()).strip(app.track, list) or list end
    -- a container with knobs on it gets a panel of its own, at its head;
    -- folded to that panel, what's inside it stays out of the row
    local tr, with_panel = app.track, {}
    list = T.with_container_panels(list, function(n)
      local vis = CT.visible(tr, n.addr, n.guid, n.path)
      if #vis == 0 then return nil end
      with_panel[n.guid] = true
      return { visible = vis, sig = table.concat(vis, ","), name = CT.key(tr, n.addr, n.guid, n.path) }
    end)
    list = T.fold(list, function(g) return with_panel[g] and CT.folded(g) end)
    CT.note(app.track, list)
  end
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
    MX.fx_drag = nil
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
    MX.fx_drag = nil
    St.clear_cache()
    S.request_scroll()
    rescan(true)
  end
end

-- The layout a panel should draw, and the key it's filed under.
local function layout_for(fx)
  -- the instance's layout variant when it has one (St.variant)
  local key = St.layout_key(fx.name, fx.guid, app.track, fx.addr)
  local layout, is_default = M.get_or_default(key, app.track, fx.addr, fx.guid)
  return layout, key, is_default
end

-- The plugins on the track whose layout puts nothing on their panel, for
-- View > Float plugins without controls: no controls (the spacers aside)
-- and no canvas; never ReaEQ, ReaComp or the Trimmer (panels of their
-- own), a container, or a plugin that's offline.
local SPACER = { divider = true, blank = true, half_gap = true }
local function no_controls()
  local out = {}
  for _, fx in ipairs(app.chain or {}) do
    if not fx.is_container and fx.guid ~= "" and not T.get_offline(app.track, fx.addr) then
      local layout, key = layout_for(fx)
      local shows = (layout == nil) or P.canvas_of(layout) ~= nil or P.own_eq(key) or P.own_rc(key) or P.own_trim(key)
      for _, c in ipairs((layout and layout.controls) or {}) do
        if not SPACER[c.type] then shows = true break end
      end
      if not shows then out[#out + 1] = fx end
    end
  end
  return out
end

-- The Rack view's Collapse all: folds every open plugin of the track and
-- remembers which, so the button's second press opens only those (one
-- already folded stays folded). Per track, for the session.
local rack_folded = {}          -- track GUID -> { fx guid, ... }
local function rack_key() return app.track and reaper.GetTrackGUID(app.track) or "" end
-- the plugins Collapse all folded that are still here and still folded
local function rack_folded_back()
  local list = rack_folded[rack_key()]
  if not list then return nil end
  local here = {}
  for _, fx in ipairs(app.chain or {}) do here[fx.guid] = true end
  local out = {}
  for _, g in ipairs(list) do
    if here[g] and St.is_collapsed(g) then out[#out + 1] = g end
  end
  if #out == 0 then rack_folded[rack_key()] = nil; return nil end
  return out
end
local function rack_fold_all()
  local list = {}
  for _, fx in ipairs(app.chain or {}) do
    if not St.is_collapsed(fx.guid) then
      St.set_collapsed(fx.guid, true)
      list[#list + 1] = fx.guid
    end
  end
  if #list > 0 then rack_folded[rack_key()] = list end
end
local function rack_unfold_all()
  for _, g in ipairs(rack_folded_back() or {}) do St.set_collapsed(g, false) end
  rack_folded[rack_key()] = nil
end

-- ---------------------------------------------------------------------
-- freeze (TS_CV_Freeze): REAPER's own, with the frozen plugins shown
-- where they were
-- ---------------------------------------------------------------------
local function frozen_state()
  if not app.track then return { levels = 0, fx = {} } end
  return FZ.state(app.track, U.clean_fx_name)
end
-- the top-level slot (0-based) and name of the selected plugin, or nil
local function freeze_point()
  local g = app.track and FB.selected(app.track)
  if not g then return nil end
  for _, fx in ipairs(app.chain or {}) do
    if fx.guid == g then
      local top = (fx.ancestors and fx.ancestors[1]) or fx
      return fx.top_index, U.clean_fx_name(top.name or "")
    end
  end
  return nil
end
local function do_freeze(upto)
  local ok, why = FZ.freeze(app.track, upto)
  if not ok and why then reaper.MB(why, "ChannelView", 0) end
  rescan(true)
end
local function do_unfreeze()
  FZ.unfreeze(app.track)
  rescan(true)
end
-- The freeze menu's items (the header's button, a frozen strip's click).
local function freeze_items(ctx, st)
  local upto, name = freeze_point()
  local idle = not FZ.busy(app.track)
  if ImGui.MenuItem(ctx, "Freeze track", nil, false, idle) then do_freeze(nil) end
  if ImGui.MenuItem(ctx, upto and ("Freeze up to " .. name) or "Freeze up to selected", nil, false, idle and upto ~= nil) then
    do_freeze(upto)
  end
  if idle and not upto and ImGui.IsItemHovered(ctx, ImGui.HoveredFlags_AllowWhenDisabled) then
    ImGui.SetTooltip(ctx, "Click a plugin's panel first.")
  end
  ImGui.Separator(ctx)
  if ImGui.MenuItem(ctx, "Unfreeze", nil, false, idle and st.levels > 0) then do_unfreeze() end
end

-- The frozen plugins' names, one per strip (a level with none read: one
-- strip for it).
local function frozen_names(st)
  if #st.fx > 0 then return st.fx end
  local out = {}
  for i = 1, st.levels do out[i] = "Frozen plugins" end
  return out
end

-- A frozen plugin's strip at x, y, w by h: ice, a snowflake and its name
-- (across, or up the strip when it's narrow). A click opens the freeze
-- menu, for Unfreeze.
local function frozen_strip(ctx, id, x, y, w, h, name, st)
  local dl = ImGui.GetWindowDrawList(ctx)
  ImGui.SetCursorScreenPos(ctx, x, y)
  ImGui.InvisibleButton(ctx, id, math.max(1, w), math.max(1, h))
  local hov = ImGui.IsItemHovered(ctx)
  if ImGui.IsItemClicked(ctx, ImGui.MouseButton_Left) or ImGui.IsItemClicked(ctx, ImGui.MouseButton_Right) then
    ImGui.OpenPopup(ctx, id .. "_m")
  end
  if hov then ImGui.SetTooltip(ctx, name .. " (frozen)\nClick: Unfreeze") end
  ImGui.DrawList_AddRectFilled(dl, x, y, x + w, y + h, hov and C.COL.frozen_head or C.COL.frozen_bg, C.PANEL_RR)
  ImGui.DrawList_AddRect(dl, x, y, x + w, y + h, U.with_alpha(C.COL.frozen_line, 0x70), C.PANEL_RR, 0, 1.0)
  local isz = math.min(14, w - 6, h - 6)
  if w >= h then
    W.ICONS.freeze(dl, x + 5, y + (h - isz) * 0.5, isz, C.COL.frozen_text)
    local _, th = ImGui.CalcTextSize(ctx, "X")
    ImGui.DrawList_PushClipRect(dl, x, y, x + w - 4, y + h, true)
    ImGui.DrawList_AddText(dl, x + isz + 10, y + (h - th) * 0.5, C.COL.frozen_text, name)
    ImGui.DrawList_PopClipRect(dl)
  else
    W.ICONS.freeze(dl, x + (w - isz) * 0.5, y + 5, isz, C.COL.frozen_text)
    W.vertical_text(ctx, dl, x + w * 0.5, y + isz + 10, name, C.COL.frozen_text, h - isz - 16)
  end
  if ImGui.BeginPopup(ctx, id .. "_m") then
    freeze_items(ctx, st)
    ImGui.EndPopup(ctx)
  end
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
-- as the browser takes it, or a slot inside a container.
local function insert_target(fx, after)
  local gap = (fx.index or fx.top_index or 0) + (after and 1 or 0)
  if fx.is_top_level then return gap end
  return { parent = fx.parent_path, gap = gap }
end

-- ---------------------------------------------------------------------
-- menus: the panel's, a control's, a container's (TS_CV_Menus, shared
-- with the TCP window's overview), made for this window
-- ---------------------------------------------------------------------

local MNU = require("TS_CV_Menus").make({
  ImGui = ImGui,
  ctx = ctx,
  app = app,
  POP = POP,
  RACK = RACK,
  B = B,
  C = C,
  CN = CN,
  CP = CP,
  CS = CS,
  CT = CT,
  E = E,
  ED = ED,
  KE = KE,
  KPm = KPm,
  M = M,
  MD = MD,
  ML = ML,
  P = P,
  PC = PC,
  RCP = RCP,
  RQ = RQ,
  ST = ST,
  SWI = SWI,
  St = St,
  T = T,
  TP = TP,
  TRM = TRM,
  U = U,
  W = W,
  S = S,
  AF = AF,
  MX = MX,
  insert_target = insert_target,
  layout_for = layout_for,
  materialise = materialise,
  nudge = nudge,
  remove_fx = remove_fx,
  rescan = rescan,
  set_fold = set_fold,
  set_parallel = set_parallel,
  toggle_fold = toggle_fold,
})
local box_ancestors, box_label, box_menu, control_menu, link_source, panel_menu, panel_requests =
  MNU.box_ancestors, MNU.box_label, MNU.box_menu, MNU.control_menu, MNU.link_source, MNU.panel_menu,
  MNU.panel_requests
local bracket_tip, draw_brackets = MNU.bracket_tip, MNU.draw_brackets
local confirm_probes, probes_menu, trimmer_click, trimmer_menu =
  MNU.confirm_probes, MNU.probes_menu, MNU.trimmer_click, MNU.trimmer_menu

-- Forward: the view toggle and the double-click handlers all switch
-- views, and they are written above the function that does it.
local set_view

-- The "Toggle mixer view" action (TS_ChannelView_ToggleMixer.lua) can't
-- reach this window's keyboard -- nothing can, from inside it -- so it
-- leaves a request in the ExtState that each frame looks for, and says
-- which command it is so a toolbar button for it can light while the
-- mixer is showing. The heartbeat tells it whether this window is open.
local TOGGLE_REQ, TOGGLE_CMD, ALIVE = "toggle_mixer", "toggle_mixer_cmd", RACK and "rack_alive" or "cv_alive"
local function show_toggle_state(on)
  if RACK then return end      -- (the mixer's toggle is ChannelView's)
  local sec, cmd = reaper.GetExtState(C.EXT_SECT, TOGGLE_CMD):match("^(%-?%d+):(%d+)$")
  if sec and tonumber(cmd) > 0 then
    reaper.SetToggleCommandState(tonumber(sec), tonumber(cmd), on and 1 or 0)
    reaper.RefreshToolbar2(tonumber(sec), tonumber(cmd))
  end
end

-- Switching views. The peak stores are keyed per strip, and the strips
-- that are about to disappear would otherwise hold their last reading
-- until you came back and found a meter frozen at a level from minutes
-- ago.
function set_view(mixer)
  if RACK then return end        -- the rack has no mixer view
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

-- Thin colour rules top and bottom, plus a chip carrying the track's own
-- colour and name. Enough to always know which track the panels belong to,
-- without a banner taking height away from the controls -- and bracketing
-- the window means the colour is in view wherever you happen to be
-- looking, including down at the track strip.
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

-- `mid_y` is the vertical centre of the header bar. ImGui centres a menu
-- label in the bar itself, but the cursor inside a menu bar sits at the
-- TOP of the row, so anything drawn by hand has to be told where the
-- middle is or it rides high, above the menu labels beside it -- the
-- track name and these buttons included.
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
      to_mixer and "Mixer view"
                or "Channel view") then
    set_view(to_mixer)
  end
end

-- Bypasses every FX on the track at once (I_FXEN), which is a different
-- thing from bypassing one plugin and belongs where you can always see it
-- rather than inside any one panel.
local function fx_bypass_button(ctx, mid_y)
  if not app.track then return end
  local on = T.chain_bypassed(app.track)
  if mid_y then
    local cx = ImGui.GetCursorScreenPos(ctx)
    ImGui.SetCursorScreenPos(ctx, cx, mid_y - C.ICON_SIZE * 0.5)
  end
  if W.icon_button(ctx, "fxen", "power", C.ICON_SIZE, on,
      on and "FX chain bypassed. Click: enable"
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
  -- the rack's padlock, in front: locked to this track, or following the
  -- selection (it stays when the name doesn't fit, so it can be undone)
  local lock_w = RACK and (C.ICON_SIZE + C.S(6)) or 0
  local nw, th = ImGui.CalcTextSize(ctx, name)
  local sw     = ImGui.CalcTextSize(ctx, sub)
  local total  = lock_w + chip_w + gap + nw + gap + sw

  local wx = ImGui.GetWindowPos(ctx)
  local ww = ImGui.GetWindowSize(ctx)
  local x  = wx + (ww - total) * 0.5
  if x < left_limit then x = left_limit end
  local fits = x + total <= right_limit
  if not fits then x = left_limit end

  local _, cy = ImGui.GetCursorScreenPos(ctx)
  local y = (mid_y or (cy + th * 0.5)) - th * 0.5
  if RACK and x + lock_w <= right_limit then
    ImGui.SameLine(ctx, 0, 0)
    ImGui.SetCursorScreenPos(ctx, x, (mid_y or (y + th * 0.5)) - C.ICON_SIZE * 0.5)
    local locked = rack_lock.guid ~= nil
    if W.icon_button(ctx, "racklock", locked and "lock" or "unlock", C.ICON_SIZE, locked,
        locked and "Locked to this track\nClick: follow the selected track again"
               or "Following the selected track\nClick: lock the rack to this track") then
      rack_lock_set((not locked) and reaper.GetTrackGUID(app.track) or nil)
    end
    x = x + lock_w
  end
  if not fits then return end

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


-- The web companion's state, polled four times a second: running, and
-- how many pages are connected (TS_CV_WebLink).
local weblink = WL.new()
local weblink_at = 0
local function web_state()
  local now = reaper.time_precise()
  if now - weblink_at > 0.25 then
    weblink_at = now
    WL.update(weblink, now, reaper.GetExtState("TS_CV_WEB", "alive"),
                            reaper.GetExtState("TS_CV_WEB", "seen"))
  end
  return WL.state(weblink, now)
end

-- Its colour, how strongly to show it, and what it means: green with a
-- page connected, a fainter green running with none, amber with a page
-- open but the companion not running. nil when there's nothing to say.
local WEB_GREEN = 0x3fb55aff
local function web_look()
  local running, pages = web_state()
  if running and pages > 0 then
    return WEB_GREEN, 1.0, pages == 1 and "Web companion: 1 page connected"
                             or ("Web companion: %d pages connected"):format(pages)
  elseif running then
    return WEB_GREEN, 0.5, "Web companion running, no page connected"
  elseif pages > 0 then
    return C.COL.warn or 0xe0a040ff, 1.0,
      "Web page open, but the companion isn't running.\nStart it: \u{2630} \u{25B8} Web companion."
  end
  return nil
end

-- A strip of that colour along the top of the header, fading down into
-- it, in place of an icon: it says the web companion is there without
-- taking a button's room. Hovering its top edge says what it means.
local function web_strip(x0, y0, w)
  local col, k, tip = web_look()
  if not col then return end
  local dl = ImGui.GetWindowDrawList(ctx)
  local function a(alpha) return (col & 0xffffff00) | math.floor(alpha * 255 * k + 0.5) end
  local solid = k >= 1 and 3 or 2
  ImGui.DrawList_AddRectFilled(dl, x0, y0, x0 + w, y0 + solid, a(1.0))
  ImGui.DrawList_AddRectFilledMultiColor(dl, x0, y0 + solid, x0 + w, y0 + solid + 8,
    a(0.30), a(0.30), a(0.0), a(0.0))
  local mx, my = ImGui.GetMousePos(ctx)
  if my >= y0 and my <= y0 + 5 and mx >= x0 and mx <= x0 + w
     and ImGui.IsWindowHovered(ctx) and not ImGui.IsAnyItemHovered(ctx) then
    ImGui.SetTooltip(ctx, tip)
  end
end

-- ☰ › Web companion: what it's doing, start or stop, and starting it with
-- REAPER.
local function web_menu()
  local running, pages = web_state()
  local col = web_look()
  local status = running and (pages > 0 and (pages == 1 and "Running \u{00B7} a page connected"
                                             or ("Running \u{00B7} %d pages connected"):format(pages))
                              or "Running \u{00B7} no page connected")
                 or (pages > 0 and "Not running \u{00B7} a page is waiting for it")
                 or "Not running"
  ImGui.TextColored(ctx, col or C.COL.header_dim, status)
  ImGui.Separator(ctx)
  if running then
    if ImGui.MenuItem(ctx, "Stop the web companion") then
      -- it reads this on its next pass and closes (TS_ChannelView_Web.lua)
      reaper.SetExtState("TS_CV_WEB", "quit", "1", false)
    end
  elseif ImGui.MenuItem(ctx, "Start the web companion") then
    reaper.DeleteExtState("TS_CV_WEB", "quit", false)
    if not SU.web(script_dir).start() then
      reaper.MB("Couldn't find TS_ChannelView_Web.lua in the Action List.", "ChannelView", 0)
    end
  end
  -- The web companion at startup too: the same fenced block the
  -- TS_ChannelView_Web_Startup action writes.
  do
    local WEB = SU.web(script_dir)
    if not WEB.checked() then WEB.resolve(); WEB.scan() end
    local st, note = WEB.state()
    if ImGui.MenuItem(ctx, "Start it with REAPER", nil, WEB.on(),
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
      ImGui.SetTooltip(ctx, "Start the web companion with REAPER.")
    end
    if st == "nocmd" then
      note = "TS_ChannelView_Web.lua isn't in the Action List."
    end
    if note then
      ImGui.TextColored(ctx, C.COL.warn, "   " .. U.wrap_note(note, 52))
    end
  end
end

local function menu_bar()
  if not ImGui.BeginMenuBar(ctx) then return end
  -- the bar's top edge, for the web companion's strip: a menu bar's
  -- cursor starts at the top of its row
  local _, bar_top = ImGui.GetCursorScreenPos(ctx)

  -- The \u{2630} menu: View, Layouts and the web companion, and the settings
  -- about ChannelView as a whole. A menu of the bar (so it opens, and
  -- switches on hover, like one), its label blank and the icon drawn over
  -- it.
  local main_open = ImGui.BeginMenu(ctx, "      ##cvmain")
  local main_x2, main_y1, main_y2
  do
    local x1, y1 = ImGui.GetItemRectMin(ctx)
    local x2, y2 = ImGui.GetItemRectMax(ctx)
    main_x2, main_y1, main_y2 = x2, y1, y2
    local hov = ImGui.IsItemHovered(ctx)
    local sz = C.ICON_SIZE
    W.ICONS.menu(ImGui.GetWindowDrawList(ctx), (x1 + x2 - sz) * 0.5, (y1 + y2 - sz) * 0.5, sz,
      (hov or main_open) and C.COL.icon_hot or C.COL.icon)
    W.tip(ctx, "cvmain", "View, layouts, web companion and options", hov and not main_open, false)
  end
  if main_open then
    if ImGui.BeginMenu(ctx, "View") then
      -- the panels besides the plugins: each can go (the rack keeps its
      -- own choice)
      for _, a in ipairs(AUX) do
        if ImGui.MenuItem(ctx, a.label, nil, app.aux[a.key]) then
          app.aux[a.key] = not app.aux[a.key]
          ext_set(AUX_PFX .. a.key, app.aux[a.key] and "1" or "0")
        end
      end
      -- the patch bay (Pro) at all (shared with the TCP window)
      do
        local bay = MX.patch_bay()
        if ED.item(ImGui, ctx, "Patch bay", nil, bay and bay.enabled()) and bay then
          bay.set_enabled(not bay.enabled())
        end
        if ImGui.IsItemHovered(ctx) then
          ImGui.SetTooltip(ctx, "Rest on the row's bottom edge: a chip that opens it.\nOff: no chip, and its actions do nothing.")
        end
      end

      if ImGui.MenuItem(ctx, "Preset bar", nil, C.PRESET_BAR) then
        C.PRESET_BAR = not C.PRESET_BAR
        ext_set("preset_bar", C.PRESET_BAR and "1" or "0")
      end
      if ImGui.IsItemHovered(ctx) then
        ImGui.SetTooltip(ctx, "Preset controls along each panel's foot.")
      end

      ImGui.Separator(ctx)
      if ImGui.MenuItem(ctx, "Auto-hide this header", nil, app.header_hide) then
        app.header_hide = not app.header_hide
        ext_set(app.hide_key, app.header_hide and "1" or "0")
      end
      if ImGui.IsItemHovered(ctx) then
        ImGui.SetTooltip(ctx, "For a small screen: the panels take the header's room, and it slides\n"
          .. "out over them while the pointer is at the window's top edge.")
      end
      ImGui.EndMenu(ctx)
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
    -- the web companion, with a dot of its strip's colour
    local web_open = ED.menu(ImGui, ctx, "Web companion   ")
    do
      local col = web_look()
      if col then
        local x1, y1 = ImGui.GetItemRectMin(ctx)
        local _, y2 = ImGui.GetItemRectMax(ctx)
        local tw = ImGui.CalcTextSize(ctx, "Web companion ")
        ImGui.DrawList_AddCircleFilled(ImGui.GetWindowDrawList(ctx),
          x1 + tw + 8, (y1 + y2) * 0.5, 3.5, col)
      end
    end
    if web_open then
      web_menu()
      ImGui.EndMenu(ctx)
    end
    ImGui.Separator(ctx)
    if ED.PRO and ED.module("TS_CV_ConsoleSetup") and ImGui.MenuItem(ctx, "Console setup\u{2026}") then
      ED.module("TS_CV_ConsoleSetup").show()
    end
    -- DrumToolbox, when it's installed (ticked while it's open)
    do
      local AC = require("TS_CV_Actions")
      local dt, dt_on = AC.drumtoolbox()
      if dt and ImGui.MenuItem(ctx, "DrumToolbox\u{2026}", nil, dt_on, not dt_on) then AC.open_drumtoolbox() end
    end
    if ImGui.MenuItem(ctx, "Options\u{2026}") then app.VO.show(app.vo_tab) end
    if ImGui.IsItemHovered(ctx) then
      ImGui.SetTooltip(ctx, "Looks, behaviour and track rules.")
    end
    ImGui.Separator(ctx)
    if ImGui.BeginMenu(ctx, "Dock") then
      for _, d in ipairs(DOCKS) do
        -- asked for here, done before the window opens next frame: a
        -- SetNextWindowDockID inside the menu would dock the menu
        if ImGui.MenuItem(ctx, d[1], nil, dock_id == d[2]) then app.dock_req = d[2] end
      end
      ImGui.EndMenu(ctx)
    end
    -- Run at startup. Scanned from __startup.lua the first frame this
    -- menu is open rather than remembered in ExtState: the file is the
    -- truth, and a cached boolean is just something that can disagree
    -- with it after a hand edit. See TS_CV_Startup for why that file is
    -- treated as gingerly as it is.
    do
      if not SU_ME.checked() then SU_ME.scan() end
      local st, note = SU_ME.state()
      if ImGui.MenuItem(ctx, "Run when REAPER starts", nil, SU_ME.on(),
          st ~= "nocmd") then
        local ok, why
        if SU_ME.on() then ok, why = SU_ME.remove() else ok, why = SU_ME.add() end
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
    ImGui.EndMenu(ctx)
  else
    -- Closed: forget what we read, so the next opening reflects any edit
    -- made to __startup.lua in the meantime.
    SU_ME.forget()
    SU.web(script_dir).forget()
  end

  -- Where the \u{2630} menu finished, so the centred title knows what it
  -- must not run into on the left -- and, from its own rectangle (taken
  -- before anything inside it was drawn), where the middle of the bar
  -- actually is. Asking ImGui beats computing it: whatever it does to lay
  -- a menu label out, this matches.
  local menus_right = math.max(ImGui.GetCursorScreenPos(ctx), main_x2)
  local mid_y = (main_y1 + main_y2) * 0.5

  -- FX chain bypass is pushed hard right; the title then gets whatever
  -- is between the two.
  local fx_tw = ImGui.CalcTextSize(ctx, "FX")
  local fx_w  = C.ICON_SIZE + C.S(4) + fx_tw
  local avail = ImGui.GetContentRegionAvail(ctx)
  local fx_left = menus_right + avail
  if app.track and avail > fx_w + 12 then
    ImGui.SameLine(ctx, 0, avail - fx_w)
    fx_left = ImGui.GetCursorScreenPos(ctx)
    fx_bypass_button(ctx, mid_y)
  end

  -- Two groups, each kept together, with a hairline between: on the left
  -- ChannelView itself (\u{2630}, the view toggle | MIDI learn, probes), on
  -- the right the track's FX chain (oversampling, load a chain | FX on/off).
  -- The web companion has no button: it's the strip along the top
  -- (web_strip) and \u{2630} \u{25B8} Web companion.
  local GROUP_GAP = 10
  local function hairline(x)
    ImGui.DrawList_AddLine(ImGui.GetWindowDrawList(ctx), x, mid_y - 7, x, mid_y + 7,
      C.COL.panel_border, 1.0)
  end

  -- Pro at another version: which to update, first after the menus; the
  -- whole message on hover, and again in a box on a click
  if ED.mismatch then
    local lbl = "Update " .. (ED.behind() == "ChannelView" and "ChannelView" or "Pro")
    local tw_, th_ = ImGui.CalcTextSize(ctx, lbl)
    local bw = tw_ + 14
    if fx_left - menus_right > bw + 50 then
      local bx, by = menus_right + 6, mid_y - C.ICON_SIZE * 0.5
      ImGui.SameLine(ctx, 0, 0)
      ImGui.SetCursorScreenPos(ctx, bx, by)
      if ImGui.InvisibleButton(ctx, "edmismatch", bw, C.ICON_SIZE) then ED.warn_mismatch(true) end
      local hov = ImGui.IsItemHovered(ctx)
      local dl = ImGui.GetWindowDrawList(ctx)
      ImGui.DrawList_AddRectFilled(dl, bx, by, bx + bw, by + C.ICON_SIZE,
        hov and C.COL.warn or U.with_alpha(C.COL.warn, 0x55), 3.0)
      ImGui.DrawList_AddRect(dl, bx, by, bx + bw, by + C.ICON_SIZE, C.COL.warn, 3.0, 0, 1.0)
      ImGui.DrawList_AddText(dl, bx + 7, by + (C.ICON_SIZE - th_) * 0.5, C.COL.header_text, lbl)
      W.tip(ctx, "edmismatch", ED.mismatch_text() .. "\n\nClick: this message in a box.", hov, false)
      menus_right = menus_right + bw + 8
    end
  end

  -- The view toggle sits on the left, straight after the menus; the
  -- title's left limit moves past it.
  do
    local tw = C.ICON_SIZE + C.S(10)
    if not RACK and fx_left - menus_right > tw + 40 then
      ImGui.SameLine(ctx, 0, 0)
      ImGui.SetCursorScreenPos(ctx, menus_right + 6, mid_y - C.ICON_SIZE * 0.5)
      view_toggle(ctx, mid_y)
      menus_right = menus_right + tw
    end
  end

  -- a hairline, then the tools
  if fx_left - menus_right > GROUP_GAP + C.ICON_SIZE + C.S(46) then
    hairline(menus_right + GROUP_GAP * 0.5)
    menus_right = menus_right + GROUP_GAP
  end

  -- MIDI learn: the drawer under the header (TS_CV_MidiLearn), first after
  -- the hairline
  do
    local tw = C.ICON_SIZE + C.S(6)
    if fx_left - menus_right > tw + 40 then
      ImGui.SameLine(ctx, 0, 0)
      ImGui.SetCursorScreenPos(ctx, menus_right + 2, mid_y - C.ICON_SIZE * 0.5)
      if W.icon_button(ctx, "midilearn", "midi", C.ICON_SIZE, ML.is_open(),
          ML.is_open() and "Close the MIDI learn bar" or "MIDI learn") then
        ML.toggle()
      end
      menus_right = menus_right + tw
    end
  end

  -- Probes, after MIDI learn: the TS_TrackProbe pair that
  -- measured gain reduction (and Track Analyser) need. The plugin row
  -- leaves them out, so this says they're there: dim with none, lit when
  -- the pair is in place, in the Visualizer's colour while the track is
  -- in the Visualizer's spectrum, amber with one of them missing. Click
  -- for the menu.
  if app.track then
    local tw = C.ICON_SIZE + C.S(6)
    if fx_left - menus_right > tw + 40 then
      ImGui.SameLine(ctx, 0, 0)
      ImGui.SetCursorScreenPos(ctx, menus_right + 2, mid_y - C.ICON_SIZE * 0.5)
      local state, vis = TP.probe_state(app.track)
      local tip, col
      if state == "pair" and vis then
        tip, col = "Probes in place \u{00B7} Visualizer (" .. vis .. ")", C.PROBE_VIS_COL
      elseif state == "pair" then
        tip = "Probes in place"
      elseif state then
        tip, col = "One probe missing", C.COL.warn or 0xe0a040ff
      else
        tip = "Add probes"
      end
      if W.icon_button(ctx, "probes", "probe", C.ICON_SIZE, state ~= nil, tip, col) then
        if state == nil then
          if confirm_probes() then rescan(true) end
        else
          ImGui.OpenPopup(ctx, "probesmenu")
        end
      end
      probes_menu(state, vis)
      menus_right = menus_right + tw
    end
  end

  -- The TS_CV Trimmer, after the probes: dim with none on the track, lit
  -- with one. With none, a click puts one first in the chain (after an
  -- ARA plugin, the pre probe and the modulators); with one, its menu.
  -- (the Trimmer: Pro)
  if app.track and TRM then
    local tw = C.ICON_SIZE + C.S(6)
    if fx_left - menus_right > tw + 40 then
      ImGui.SameLine(ctx, 0, 0)
      ImGui.SetCursorScreenPos(ctx, menus_right + 2, mid_y - C.ICON_SIZE * 0.5)
      local have = TRM.find(app.track)
      if W.icon_button(ctx, "trimmer", "trimmer", C.ICON_SIZE, have ~= nil,
          have and "Trimmer" or "Add Trimmer") then
        trimmer_click()
      end
      trimmer_menu()
      menus_right = menus_right + tw
    end
  end

  -- Action drawers (TS_CV_Drawers): lit while any is open; click for the
  -- list, to open or close each, make a new one, or organise them.
  do
    local tw = C.ICON_SIZE + C.S(6)
    if fx_left - menus_right > tw + 40 then
      ImGui.SameLine(ctx, 0, 0)
      ImGui.SetCursorScreenPos(ctx, menus_right + 2, mid_y - C.ICON_SIZE * 0.5)
      if W.icon_button(ctx, "drawers", "drawers", C.ICON_SIZE, DR.any_open(), "Action drawers") then
        ImGui.OpenPopup(ctx, "drawersmenu")
      end
      if ImGui.BeginPopup(ctx, "drawersmenu") then
        DR.header_menu(ctx)
        ImGui.EndPopup(ctx)
      end
      menus_right = menus_right + tw
    end
  end

  -- the FX chain's group, after a hairline left of FX on/off
  if app.track and fx_left - menus_right > GROUP_GAP + C.ICON_SIZE + C.S(46) then
    fx_left = fx_left - GROUP_GAP
    hairline(fx_left + GROUP_GAP * 0.5)
  end

  -- Load an FX chain, left of the FX bypass.
  if app.track then
    local tw = C.ICON_SIZE + C.S(6)
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

  -- Oversampling for the whole chain, left of the FX chain button: REAPER's
  -- own chain setting (T.chain_os), lit while it's on.
  if app.track then
    local cst = T.chain_state(app.track)
    local n = cst.n
    local tw = W.os_width(ctx, cst.lit) + 6
    if fx_left - menus_right > tw + 40 then
      ImGui.SameLine(ctx, 0, 0)
      ImGui.SetCursorScreenPos(ctx, fx_left - tw, mid_y - C.ICON_SIZE * 0.5)
      local tip = cst.lit
        and ("FX chain oversampled (%s): %dx.\nClick: change"):format(
              T.os_label(n, cst.rate):lower(), cst.lit)
        or (n > 0) and ("FX chain oversampling %s: no effect at this rate.\nClick: change"):format(T.os_label(n, cst.rate):lower())
        or  "Oversample the whole FX chain"
      if W.os_badge(ctx, "chainos", cst.lit, C.ICON_SIZE, tip, C.COL.header_text, C.COL.header_bg, cst.faint) then
        ImGui.OpenPopup(ctx, "chainosmenu")
      end
      if ImGui.BeginPopup(ctx, "chainosmenu") then
        ImGui.TextDisabled(ctx, "Oversample the whole chain")
        local rate = cst.rate
        for _, k in ipairs(T.OS_CHOICES) do
          local hint
          if k > 0 and rate then
            local hz = T.os_cap(k, rate)
            hint = (hz > rate) and ("%dx"):format(T.os_factor(hz, rate)) or "no effect"
          end
          if ImGui.MenuItem(ctx, T.os_label(k, rate), hint, n == k) and n ~= k then
            T.set_chain_os(app.track, k)
          end
        end
        ImGui.TextDisabled(ctx, "Takes effect when playback next starts.")
        ImGui.EndPopup(ctx)
      end
      fx_left = fx_left - tw
    end
  end

  -- Freeze: lit while the track has frozen plugins
  if app.track then
    local tw = C.ICON_SIZE + C.S(6)
    if fx_left - menus_right > tw + 40 then
      local fst = frozen_state()
      ImGui.SameLine(ctx, 0, 0)
      ImGui.SetCursorScreenPos(ctx, fx_left - tw, mid_y - C.ICON_SIZE * 0.5)
      if W.icon_button(ctx, "freezebtn", "freeze", C.ICON_SIZE, fst.levels > 0,
          fst.levels > 0 and "Frozen" or "Freeze", C.COL.frozen_text) then
        ImGui.OpenPopup(ctx, "freezemenu")
      end
      if ImGui.BeginPopup(ctx, "freezemenu") then
        freeze_items(ctx, fst)
        ImGui.EndPopup(ctx)
      end
      fx_left = fx_left - tw
    end
  end

  -- The rack: fold every plugin, or open again the ones that folded
  if RACK and app.track then
    local tw = C.ICON_SIZE + C.S(6)
    if fx_left - menus_right > tw + 40 then
      ImGui.SameLine(ctx, 0, 0)
      ImGui.SetCursorScreenPos(ctx, fx_left - tw, mid_y - C.ICON_SIZE * 0.5)
      local back = rack_folded_back()
      if W.icon_button(ctx, "rackfoldall", back and "expand_all" or "collapse_all", C.ICON_SIZE, false,
          back and "Expand all" or "Collapse all") then
        if back then rack_unfold_all() else rack_fold_all() end
      end
      fx_left = fx_left - tw
    end
  end

  track_title(ctx, menus_right + 12, fx_left - 12, mid_y)

  do
    local wx = ImGui.GetWindowPos(ctx)
    local ww = ImGui.GetWindowSize(ctx)
    -- The whole FX chain bypassed: a red glow up from the bar's bottom
    -- edge and a faint wash over it, so it can't be missed (each plugin's
    -- own header only dims).
    if app.track and T.chain_bypassed(app.track) then
      local dl = ImGui.GetWindowDrawList(ctx)
      local col = C.COL.bypass_on or 0xd8463cff
      local function a(alpha) return (col & 0xffffff00) | math.floor(alpha * 255 + 0.5) end
      local bot = 2 * mid_y - bar_top
      ImGui.DrawList_AddRectFilled(dl, wx, bar_top, wx + ww, bot, a(0.10))
      ImGui.DrawList_AddRectFilledMultiColor(dl, wx, bot - 12, wx + ww, bot - 2,
        a(0.0), a(0.0), a(0.35), a(0.35))
      ImGui.DrawList_AddRectFilled(dl, wx, bot - 2, wx + ww, bot, a(1.0))
    end
    web_strip(wx, bar_top, ww)
  end

  -- Double-clicking the header switches views, the same as the toggle.
  -- Only where nothing else lives: IsAnyItemHovered catches the menus,
  -- the toggle and the bypass, so this is the bar's own empty space and
  -- the track name drawn on it, which is not an item at all.
  --
  -- The bar is centred on mid_y and starts at the window top, so its
  -- height falls out of that rather than needing MenuBarHeight, which
  -- ImGui does not report (the header arithmetic in frame() works round
  -- the same gap).
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

-- The hidden header (app.header_hide): while the pointer is in the top few
-- pixels of the window, on the header itself, or in a menu it opened, the
-- header is drawn over the panels in a child of its own; a moment after
-- the pointer leaves, it folds away again. Drawn last, so it sits on top.
-- (a field of app: this file is at Lua's limit of locals)
function app.header_overlay()
  if not app.header_hide then return end
  local HIDE_EDGE, HIDE_LINGER = 6, 0.35
  local wx, wy = ImGui.GetWindowPos(ctx)
  local ww = ImGui.GetWindowSize(ctx)
  local mx, my = ImGui.GetMousePos(ctx)
  local now = reaper.time_precise()
  local hh = ImGui.GetFontSize(ctx) + 2 * C.MENU_PAD_Y
  local inside = mx >= wx and mx <= wx + ww
  local at_edge = inside and my >= wy and my <= wy + HIDE_EDGE
    and ImGui.IsWindowHovered(ctx, ImGui.HoveredFlags_ChildWindows | ImGui.HoveredFlags_AllowWhenBlockedByActiveItem)
  local on_it = app.header_out and inside and my >= wy and my <= wy + hh
  local menu = app.header_out and ImGui.IsPopupOpen(ctx, "", ImGui.PopupFlags_AnyPopupId | ImGui.PopupFlags_AnyPopupLevel)
  if at_edge or on_it or menu then app.header_out = now end
  if not app.header_out then
    -- the edge it comes out from: a hairline, so it can be found
    ImGui.DrawList_AddLine(ImGui.GetWindowDrawList(ctx), wx + ww * 0.5 - 20, wy + 1.5, wx + ww * 0.5 + 20, wy + 1.5,
      C.COL.knob_ring, 2.0)
    return
  end
  if now - app.header_out > HIDE_LINGER then app.header_out = nil; return end
  ImGui.SetCursorScreenPos(ctx, wx, wy)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_FramePadding, 6, C.MENU_PAD_Y)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowPadding, 0, 0)
  if ImGui.BeginChild(ctx, "##cvhdrout", ww, hh, 0,
      ImGui.WindowFlags_MenuBar | ImGui.WindowFlags_NoScrollbar | ImGui.WindowFlags_NoScrollWithMouse) then
    menu_bar()
    ImGui.EndChild(ctx)
  end
  ImGui.PopStyleVar(ctx, 2)
end

-- ---------------------------------------------------------------------
-- panel row
-- ---------------------------------------------------------------------

-- A dashed placeholder at the end of the row. Deliberately not styled as
-- a panel: it isn't a plugin, and shouldn't read as an empty one.
local function add_tile(h, w)
  w = w or C.ADD_TILE_W
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

  W.tip(ctx, "addfx", "Add a plugin at the end", hovered, false)
  return pressed
end



-- ChannelView's own panel rows, for the rack (P.RACK_ROWS: a layout
-- ChannelView shows too keeps the rows it fills there, P.rack_from_rows):
-- ChannelView publishes them as its window changes height, kept for when
-- it isn't running; the rack reads them twice a second.
-- ---------------------------------------------------------------------
-- popped-out panels (TS_CV_PopOut, Pro): windows of this window's, each
-- panel drawn as the row draws its own, with app's track, chain and menu
-- state swapped for the window's while it is
-- ---------------------------------------------------------------------
-- A popped-out window's menu (a panel's ≡ ▸ Window, or a right-click
-- round its panels).
function POP.menu(w)
  -- ChannelView's own track (from a panel's menu, app.track is the panel's)
  local tr, chain = POP.cv_track, POP.cv_chain or {}
  if ImGui.BeginMenu(ctx, "Add from " .. U.truncate(tr and POP.PO.track_name(tr) or "the track", 20)) then
    if not tr or #chain == 0 then ImGui.TextDisabled(ctx, "(no plugins)") end
    local has = {}
    for _, p in ipairs(w.panels) do has[p.f] = true end
    for i, fx in ipairs(chain) do
      if not fx.container_panel and not fx.is_container and fx.guid ~= "" then
        if ImGui.MenuItem(ctx, U.fx_label(fx) .. "##poadd" .. i, nil, has[fx.guid], not has[fx.guid]) then
          POP.PO.add(w.id, reaper.GetTrackGUID(tr), fx.guid)
        end
      end
    end
    ImGui.EndMenu(ctx)
  end
  if ImGui.BeginMenu(ctx, "Rename") then
    if POP.ren_for ~= w.id then POP.ren_for, POP.ren_buf = w.id, w.name end
    ImGui.SetNextItemWidth(ctx, 160)
    local _, v = ImGui.InputText(ctx, "##poren", POP.ren_buf)
    POP.ren_buf = v
    local enter = ImGui.IsItemDeactivated(ctx) and (ImGui.IsKeyPressed(ctx, ImGui.Key_Enter) or ImGui.IsKeyPressed(ctx, ImGui.Key_KeypadEnter))
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, "OK##poren") or enter then
      POP.PO.rename(w.id, U.trim(POP.ren_buf)); POP.ren_for = nil
      ImGui.CloseCurrentPopup(ctx)
    end
    ImGui.EndMenu(ctx)
  end
  if ImGui.BeginMenu(ctx, "Panels") then
    local dir = w.dir or "auto"
    if ImGui.MenuItem(ctx, "By the window's shape", nil, dir == "auto") then POP.PO.set_dir(w.id, "auto") end
    if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "Side by side, or stacked down\nwhen it's taller than it's wide.") end
    if ImGui.MenuItem(ctx, "Side by side", nil, dir == "across") then POP.PO.set_dir(w.id, "across") end
    if ImGui.MenuItem(ctx, "Stacked down", nil, dir == "down") then POP.PO.set_dir(w.id, "down") end
    ImGui.EndMenu(ctx)
  end
  if ImGui.BeginMenu(ctx, "Dock") then
    for _, d in ipairs(DOCKS) do
      -- done before the window opens next frame (here it would dock the menu)
      if ImGui.MenuItem(ctx, d[1], nil, (w.dock or 0) == d[2]) then POP.dock_req = { w.id, d[2] } end
    end
    ImGui.EndMenu(ctx)
  end
  ImGui.Separator(ctx)
  if ImGui.MenuItem(ctx, "Close") then POP.close = w.id end
  if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "The plugins stay where they are.") end
end

-- One popped-out window: its panels side by side or stacked down, each
-- with its track's name over it.
function POP.window(w, now)
  local view = POP.views[w.id] or {}
  POP.views[w.id] = view
  view.win = w.id
  -- what it shows, found again (a panel's index is its place in the window)
  local items, chain = {}, {}
  for k, p in ipairs(w.panels) do
    local tr, fx = POP.PO.resolve(p.t, p.f, now)
    items[k] = { tr = tr, fx = fx }
    chain[k] = fx or { guid = "", gone = true }
  end
  view.chain = chain

  if POP.dock_req and POP.dock_req[1] == w.id then
    ImGui.SetNextWindowDockID(ctx, POP.dock_req[2], ImGui.Cond_Always)
    POP.PO.set_dock(w.id, POP.dock_req[2])
    POP.dock_req = nil
  elseif not POP.applied[w.id] then
    ImGui.SetNextWindowDockID(ctx, w.dock or 0, ImGui.Cond_FirstUseEver)
  end
  POP.applied[w.id] = true
  if POP.place and POP.place.id == w.id then
    ImGui.SetNextWindowPos(ctx, POP.place.x, POP.place.y, ImGui.Cond_Always)
    POP.place = nil
  end
  local row_h = (app.cv_h or 240)
  ImGui.SetNextWindowSize(ctx, 420, row_h + POP.LABEL_H + 48, ImGui.Cond_FirstUseEver)
  ImGui.PushStyleColor(ctx, ImGui.Col_WindowBg, C.COL.win_bg)
  -- a narrow margin: the panels are what the window is for
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowPadding, POP.PAD, POP.PAD)
  local vis, open = ImGui.Begin(ctx, w.name .. "###cvpop" .. w.id, true,
    ImGui.WindowFlags_NoScrollbar | ImGui.WindowFlags_NoScrollWithMouse | ImGui.WindowFlags_NoCollapse)
  ImGui.PopStyleVar(ctx)
  ImGui.PopStyleColor(ctx)
  if not open then POP.close = w.id end
  if vis then
    local d = ImGui.GetWindowDockID(ctx)
    if d ~= (w.dock or 0) then POP.PO.set_dock(w.id, d) end
    do
      local x, y = ImGui.GetWindowPos(ctx)
      local ww, wh = ImGui.GetWindowSize(ctx)
      POP.rects[w.id] = { x, y, ww, wh }
    end

    -- the panels (the window's own menu: a panel's ≡ ▸ Window, or a
    -- right-click on the space round them)
    local avail_w, avail_h = ImGui.GetContentRegionAvail(ctx)
    -- side by side, or stacked down (by its shape, unless it's set)
    local down = (w.dir == "down") or (w.dir ~= "across" and avail_h > avail_w)
    view.down = down
    local cflags = ImGui.WindowFlags_NoScrollWithMouse | (down and 0 or ImGui.WindowFlags_HorizontalScrollbar)
    local menu_here = false
    if ImGui.BeginChild(ctx, "porow", avail_w, avail_h, 0, cflags) then
      local inner_w, inner_h = ImGui.GetContentRegionAvail(ctx)
      local ph = math.max(60, inner_h - POP.LABEL_H)
      local dl = ImGui.GetWindowDrawList(ctx)
      local function track_line(x, y, wd, tr)
        local name = tr and POP.PO.track_name(tr) or "(track gone)"
        local col = tr and U.track_colour(tr, 0xff) or C.COL.label
        ImGui.DrawList_AddRectFilled(dl, x, y + 5, x + 10, y + 9, col, 2)
        ImGui.DrawList_PushClipRect(dl, x, y, x + wd, y + POP.LABEL_H, true)
        ImGui.DrawList_AddText(dl, x + 14, y, C.COL.label, name)
        ImGui.DrawList_PopClipRect(dl)
      end
      -- one panel at x, y (its track's line first); returns its width, height
      local function one(k, it, x, y)
        if not it.fx then
          track_line(x, y, 160, it.tr)
          ImGui.SetCursorScreenPos(ctx, x, y + POP.LABEL_H + 4)
          ImGui.TextDisabled(ctx, "Its plugin isn't there.")
          ImGui.SetCursorScreenPos(ctx, x, y + POP.LABEL_H + 26)
          if ImGui.SmallButton(ctx, "Take it out##pogone" .. k) then POP.take_out = { w.id, k } end
          return 160, POP.LABEL_H + 48
        end
        ImGui.SetCursorScreenPos(ctx, x, y + POP.LABEL_H)
        local wd, ht
        POP.scope(view, it.tr, function()
          local layout, key = layout_for(it.fx)
          local h = ph
          if down then
            -- (the space left of a scrollbar, when there is one)
            P.FILL_W = math.max(80, inner_w)
            h = POP.rack_height(it.fx, layout, key, P.FILL_W)
          end
          P.SITE = "pop" .. w.id          -- (a window of its own: P.split)
          local pw, req = P.draw(ctx, it.tr, it.fx, layout, key, h, k, false)
          P.SITE = nil
          P.FILL_W = nil
          wd, ht = pw, h
          -- not here: dragging (it moves plugins in ChannelView's row),
          -- Alt+click remove (asked before the frame), and modulator drops
          -- (a modulator is ChannelView's track's)
          req.begin_drag, req.remove, req.mod_drop = nil, nil, nil
          panel_requests(k, it.fx, layout, key, req)
          if req.open_menu or req.ctx_control then view.menu_track = it.tr end
        end)
        track_line(x, y, wd or 120, it.tr)
        return wd or 120, POP.LABEL_H + (ht or ph)
      end
      local x, y = ImGui.GetCursorScreenPos(ctx)
      local gap = C.PANEL_GAP + C.S(4)
      for k, it in ipairs(items) do
        local pw, h = one(k, it, x, y)
        -- every panel's line at the row's top, or each under the last
        if down then y = y + h + gap else x = x + pw + gap end
      end
      if #items > 0 then
        -- room made for what was drawn (no gap after the last), so the
        -- child scrolls to it and no further
        if down then y = y - gap else x = x - gap end
        ImGui.SetCursorScreenPos(ctx, x, y)
        ImGui.Dummy(ctx, 0, 0)
      else
        ImGui.TextDisabled(ctx, "No panels: right-click \u{25B8} Add from.")
      end
      if ImGui.IsWindowHovered(ctx) and not ImGui.IsAnyItemHovered(ctx)
         and ImGui.IsMouseClicked(ctx, ImGui.MouseButton_Right) then
        menu_here = true
      end
      if ImGui.IsWindowHovered(ctx, ImGui.HoveredFlags_ChildWindows) then
        local wy, wx = ImGui.GetMouseWheel(ctx)
        if down then
          if wy ~= 0 and not W.wheel_taken() then
            ImGui.SetScrollY(ctx, ImGui.GetScrollY(ctx) - wy * C.WHEEL_SCROLL_PX)
          end
        else
          local dx = (wx ~= 0) and wx or ((wy ~= 0 and not W.wheel_taken()) and wy or 0)
          if dx ~= 0 then ImGui.SetScrollX(ctx, ImGui.GetScrollX(ctx) - dx * C.WHEEL_SCROLL_PX) end
        end
      end
      ImGui.EndChild(ctx)
    end

    -- the panels' menus, for the panel they were opened on
    POP.scope(view, view.menu_track, function()
      if app.open_panel_menu then ImGui.OpenPopup(ctx, "panelmenu"); app.open_panel_menu = false end
      if app.open_ctl_menu   then ImGui.OpenPopup(ctx, "ctlmenu");   app.open_ctl_menu   = false end
      if app.track then
        panel_menu()
        control_menu()
      end
    end)
    if menu_here then ImGui.OpenPopup(ctx, "pomenu") end
    if ImGui.BeginPopup(ctx, "pomenu") then
      ImGui.TextDisabled(ctx, w.name)
      ImGui.Separator(ctx)
      POP.menu(w)
      ImGui.EndPopup(ctx)
    end
    W.draw_tip(ctx)
    ImGui.End(ctx)
  end
end

-- Every popped-out window, after ChannelView's own.
function POP.windows()
  if not POP.PO then return end
  POP.applied = POP.applied or {}
  POP.rects = {}
  POP.cv_track, POP.cv_chain = app.track, app.chain
  local now = reaper.time_precise()
  for _, w in ipairs(POP.PO.windows()) do POP.window(w, now) end
  if POP.close then POP.PO.close(POP.close); POP.views[POP.close] = nil; POP.close = nil end
  if POP.take_out then POP.PO.take_out(POP.take_out[1], POP.take_out[2]); POP.take_out = nil end
  -- something changed from a popped-out panel's menu: ChannelView's own
  -- chain read again too (it may be the same track)
  if app.popout_dirty then
    app.popout_dirty = false
    POP.PO.forget()
    rescan(true)
  end
end

local ROWS = { key = "panel_rows", said = nil, read_at = -1 }
function ROWS.publish(inner_h)
  local n = P.rows_for(inner_h)
  app.cv_rows, app.cv_h = n, inner_h
  if n ~= ROWS.said then
    ROWS.said = n
    reaper.SetExtState(C.EXT_SECT, ROWS.key, tostring(n), true)
  end
end
function ROWS.read()
  local now = reaper.time_precise()
  if now - ROWS.read_at < 0.5 then return end
  ROWS.read_at = now
  P.RACK_ROWS = tonumber(reaper.GetExtState(C.EXT_SECT, ROWS.key))
end

local function panel_row(row_h, row_w)
  local pr_x, pr_y = ImGui.GetCursorPos(ctx)
  local ok = ImGui.BeginChild(ctx, "panelrow", row_w or 0, row_h, 0,
    ImGui.WindowFlags_HorizontalScrollbar | ImGui.WindowFlags_NoScrollWithMouse)
  if ok then
    local _, inner_h = ImGui.GetContentRegionAvail(ctx)
    app.panel_rects = {}
    if not RACK then ROWS.publish(inner_h) end

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
      -- Only the panels under a bracket give up height, and only as many
      -- rows as their own brackets stack: the outermost one over them.
      local drop = {}
      for _, b in ipairs(app.brackets) do
        local d = (b.row + 1) * C.BRK_ROW_H + C.BRK_PAD
        -- (a compare's bar stands in for its bracket, and is taller)
        if POP.CMP and b.kind == "container" and POP.CMP.is_container(app.track, b.node.guid) then
          d = d + POP.CMP.BAR_H - C.BRK_ROW_H
        end
        for k = b.first, b.last do drop[k] = math.max(drop[k] or 0, d) end
      end
      local function panel_h(i) return inner_h - (drop[i] or 0) end
      -- Two panels side by side share one meter in the gap between them
      -- when the second plugin comes next after the first (probes aside)
      -- and both show their input and output (P.shares_io): shared[i], panels i
      -- and i + 1. Not on a blind compare's boxes, nor where their tops
      -- differ.
      local shared = {}
      do
        local blind = POP.CMP and POP.CMP.blind(app.track)
        for i = 1, #app.chain - 1 do
          local a, b = app.chain[i], app.chain[i + 1]
          if (drop[i] or 0) == (drop[i + 1] or 0)
             and not (blind and (POP.CMP.side_of(app.track, a.guid) or POP.CMP.side_of(app.track, b.guid))) then
            local la, ka = layout_for(a)
            local lb, kb = layout_for(b)
            shared[i] = P.shares_io(app.track, a, la, ka, b, lb, kb)
          end
        end
      end
      local function io_of(i, fx, lay)
        local io = P.has_io(app.track, fx, lay)
        if io and (shared[i - 1] or shared[i]) then io = { l = not shared[i - 1], r = not shared[i] } end
        return io
      end

      -- Centring needs the row's full width up front, so measure first.
      -- Only worth it when everything fits; once the panels overflow they
      -- pack left and the row scrolls, which is the only sane behaviour.
      if C.ROW_ALIGN == "centre" and #app.chain > 0 then
        local total = C.PANEL_GAP + C.ADD_TILE_W
        local fst0 = frozen_state()
        if fst0.levels > 0 then total = total + #frozen_names(fst0) * (26 + C.PANEL_GAP) end
        for i, fx in ipairs(app.chain) do
          local lay, k = layout_for(fx)
          local has_meter = M.meter_of(lay) ~= nil
                            and T.reports_gr(app.track, fx.addr, fx.guid)
          total = total + P.width(P.visible(lay.controls or {}, app.track, fx), panel_h(i),
                                  St.is_collapsed(fx.guid), has_meter, k,
                                  io_of(i, fx, lay),
                                  St.is_gr_open(fx.guid), M.locked(lay),
                                  (not P.own_eq(k) and not P.own_rc(k)) and P.canvas_of(lay) or nil)
          if i > 1 then total = total + C.PANEL_GAP end
          if shared[i] then total = total + C.IO_COL_W + C.PANEL_GAP end
        end
        local avail_w = ImGui.GetContentRegionAvail(ctx)
        if total < avail_w then
          ImGui.SetCursorPosX(ctx, ImGui.GetCursorPosX(ctx) + (avail_w - total) * 0.5)
        end
      end

      local row_top = select(2, ImGui.GetCursorScreenPos(ctx))
      app.brk_top = row_top
      -- the frozen plugins first, as narrow strips where they were
      local fst = frozen_state()
      if fst.levels > 0 then
        for k, name in ipairs(frozen_names(fst)) do
          local sx = ImGui.GetCursorScreenPos(ctx)
          frozen_strip(ctx, "fz" .. k, sx, row_top, 26, inner_h, name, fst)
          ImGui.SetCursorScreenPos(ctx, sx + 26 + C.PANEL_GAP, row_top)
        end
      end
      if #app.chain == 0 and fst.levels == 0 then
        ImGui.TextDisabled(ctx, "No plugins on this track yet \u{2014}")
        ImGui.SameLine(ctx)
      end
      for i, fx in ipairs(app.chain) do
        if i > 1 then ImGui.SameLine(ctx, 0, C.PANEL_GAP) end
        -- the meter this panel shares with the one before it, in the gap
        if shared[i - 1] then
          local gx, gy0 = ImGui.GetCursorScreenPos(ctx)
          local gy = row_top + (drop[i] or 0) + P.head_h() + C.PANEL_PAD
          local gh = panel_h(i) - P.head_h() - P.footer_h() - C.PANEL_PAD * 2
          P.draw_gap_io(ctx, ImGui.GetWindowDrawList(ctx), gx, gy, C.IO_COL_W, gh,
                        app.track, app.chain[i - 1], fx)
          ImGui.SetCursorScreenPos(ctx, gx + C.IO_COL_W + C.PANEL_GAP, gy0)
        end
        local px = ImGui.GetCursorScreenPos(ctx)
        local py = row_top + (drop[i] or 0)
        ImGui.SetCursorScreenPos(ctx, px, py)
        local layout, key = layout_for(fx)
        local is_src = app.drag ~= nil and app.drag.guid == fx.guid
        local w, req
        -- compared blind: a numbered box instead (TS_CV_Compare)
        local cmp = POP.CMP and POP.CMP.side_of(app.track, fx.guid)
        if cmp and POP.CMP.blind(app.track) then
          w, req = POP.CMP.blind_panel(ctx, app.track, fx, panel_h(i)), {}
        else
          if shared[i - 1] or shared[i] then P.io_next = { l = shared[i - 1] or false, r = shared[i] or false } end
          w, req = P.draw(ctx, app.track, fx, layout, key, panel_h(i), i, is_src)
          P.io_next = nil
        end

        app.panel_rects[#app.panel_rects + 1] = {
          chain_i   = i,
          x         = px,
          y         = py,
          w         = w,
        }

        panel_requests(i, fx, layout, key, req)
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
      local mx, my = ImGui.GetMousePos(ctx)
      local drop = app.track and drop_under(mx) or nil
      -- dragged out of the window: a popped-out copy (Pro), into the
      -- popped-out window it's over or one of its own
      local r = app.win_rect
      local out = POP.PO and r and app.drag.what == "plugin"
                  and not (mx >= r[1] and mx < r[1] + r[3] and my >= r[2] and my < r[2] + r[4])
      local into = out and POP.at(mx, my)
      -- over another track in the track row: copied (moved) there instead
      local to_track = MX.fx_drop
      if to_track then drop, out = nil, false end
      if out then
        drop = nil
        local w = into and POP.PO.window(into)
        ImGui.SetTooltip(ctx, w and ("Pop out into \u{201C}" .. w.name .. "\u{201D}") or "Pop out")
      end
      app.drop_gap = drop
      if drop then
        -- over the panels (child windows draw over this window's own
        -- list), kept inside the row
        local dl = ImGui.GetForegroundDrawList(ctx)
        local rx, wy = ImGui.GetWindowPos(ctx)
        local ww, wh = ImGui.GetWindowSize(ctx)
        -- (before the first panel: inside the row's left edge)
        local dx = math.max(drop.x, rx + 2)
        ImGui.DrawList_PushClipRect(dl, rx, wy, rx + ww, wy + wh, false)
        ImGui.DrawList_AddRectFilled(dl, dx - 1.5, wy + 2,
          dx + 1.5, wy + wh - 2, drop.into and C.COL.brk_container or C.COL.drop_marker, 1.0)
        ImGui.DrawList_PopClipRect(dl)
        if drop.into then
          ImGui.SetTooltip(ctx, "Into " .. box_label(drop.into))
        end
      end
      if not ImGui.IsMouseDown(ctx, ImGui.MouseButton_Left) then
        if drop then move_to(app.drag.path, drop.parent, drop.gap, app.drag.what) end
        if out then
          for _, f in ipairs(app.chain) do
            if f.guid == app.drag.guid then POP.pop_out(app.track, f, into, { mx - 20, my - 10 }) break end
          end
        end
        if to_track and reaper.ValidatePtr2(0, to_track, "MediaTrack*") then
          -- to the end of that track's chain, with its settings; Alt moves it
          local move = (ImGui.GetKeyMods(ctx) & ImGui.Mod_Alt) ~= 0
          for _, f in ipairs(app.chain) do
            if f.guid == app.drag.guid then
              reaper.Undo_BeginBlock()
              reaper.TrackFX_CopyToTrack(app.track, f.addr, to_track, reaper.TrackFX_GetCount(to_track), move)
              reaper.Undo_EndBlock("ChannelView: " .. (move and "move " or "copy ") .. U.fx_label(f) .. " to another track", -1)
              break
            end
          end
        end
        app.drag, app.drop_gap, MX.fx_drag, MX.fx_drop = nil, nil, nil, nil
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
-- RACK VIEW: the column
-- ---------------------------------------------------------------------
-- Down the column: the macros and modulators (each a strip, when shown),
-- the plugins in chain order, an add tile, then the sends and receives
-- (strips too). Every strip and every plugin's
-- plate is the column's width (P.FILL_W); its height is the least that
-- lays its controls out within that width. The wheel scrolls the column
-- unless a control under the pointer took it; a dragged panel drops above
-- or below the one under the pointer.

-- (the AUX panels are shown or not per view: see the View menu)

-- a macro or modulator added, or something changed, in either view
local function aux_mod_requests(ma_req, mo_req)
  if ma_req.add_macro or mo_req.add_mod then
    local done
    if ma_req.add_macro then done = MD.add_macro(app.track, ma_req.add_macro, TP.ara_first(app.track))
    else done = MD.add_mod(app.track, mo_req.add_mod, TP.ara_first(app.track)) end
    if not done and not MD.plugin(app.track) then
      reaper.MB("ChannelView couldn't find its ChannelView Modulators plugin\n" ..
                "(TS_CV_Modulators.jsfx). Reinstalling ChannelView from ReaPack puts it back.",
                "ChannelView", 0)
    end
    rescan(true)
  end
  if ma_req.changed or mo_req.changed then rescan(true) end
end

-- the rack's strips: each the column's width and as short as fits; the
-- cursor goes on below it
local function rack_strip(h, draw)
  local x, y = ImGui.GetCursorScreenPos(ctx)
  local _, req = draw(h)
  ImGui.SetCursorScreenPos(ctx, x, y + h + C.PANEL_GAP)
  return req or {}
end

local rack_fit = {}      -- guid -> { sig, h }
local function rack_height(fx, layout, key, rack_w)
  if St.is_collapsed(fx.guid) then return C.HEADER_H + C.S(2) end
  ROWS.read()
  local sig = table.concat({ tostring(layout), key, math.floor(rack_w), math.floor(reaper.time_precise() * 2),
                             tostring(P.RACK_ROWS),
                             tostring(St.is_gr_open(fx.guid)), tostring(C.SHOW_VALUES) }, "|")
  local hit = rack_fit[fx.guid]
  if hit and hit.sig == sig then return hit.h end
  -- whether ChannelView shows this layout too: a switching rule puts it
  -- up in both, otherwise ChannelView's own pick
  local shared = St.switch_rule(fx.guid) ~= nil
  if not shared then
    local was, was_a = St.VARIANT, St.VARIANT_ALSO
    St.VARIANT, St.VARIANT_ALSO = "variant:", nil
    shared = St.chosen_key(fx.name, fx.guid) == key
    St.VARIANT, St.VARIANT_ALSO = was, was_a
  end
  local h = P.rack_height(app.track, fx, layout, key, rack_w, shared)
  rack_fit[fx.guid] = { sig = sig, h = h }
  return h
end
POP.rack_height = rack_height

-- where a dragged panel would land: above or below the panel under the
-- pointer (the column's take on drop_under)
local function rack_drop(my)
  local rects = app.panel_rects
  if #rects == 0 then return nil end
  for _, r in ipairs(rects) do
    local fx = app.chain[r.chain_i]
    if fx and my < r.y + r.h + C.PANEL_GAP then
      local into = fx.ancestors and fx.ancestors[#fx.ancestors] or nil
      if my < r.y + r.h * 0.5 then
        return { parent = fx.parent_path or {}, gap = fx.index or 0, y = r.y - C.PANEL_GAP * 0.5, into = into }
      end
      return { parent = fx.parent_path or {}, gap = (fx.index or 0) + 1,
               y = r.y + r.h + C.PANEL_GAP * 0.5, into = into }
    end
  end
  local last = rects[#rects]
  return { parent = {}, gap = reaper.TrackFX_GetCount(app.track), y = last.y + last.h + C.PANEL_GAP * 0.5 }
end

-- Container and parallel brackets down the column's left edge: a gutter
-- with a line per bracket (the outermost furthest left), its ends turning
-- in to the panels it spans. A container also gets a strip across the
-- column over its first panel -- its on/off square, its name, its
-- oversampling -- which opens its menu; a parallel run is marked "=".
C.RACK_BRK_W = 9
-- Each panel moves in by the brackets round it only: depth n (the
-- deepest bracket row covering it, plus one) indents it n rows' worth;
-- a panel in no bracket keeps the column's full width.
local function rack_indents()
  local depth = {}
  for _, b in ipairs(app.brackets or {}) do
    for i = b.first, b.last do depth[i] = math.max(depth[i] or 0, b.row + 1) end
  end
  return function(i)
    local d = depth[i] or 0
    return d > 0 and (d * C.RACK_BRK_W + 4) or 0
  end
end

local function rack_brk_strip(b, colx, colw)
  local dl = ImGui.GetWindowDrawList(ctx)
  local x0, y0 = ImGui.GetCursorScreenPos(ctx)
  local h = C.BRK_ROW_H + C.S(4)
  local lx = colx + 3 + (b.row + 0.5) * C.RACK_BRK_W
  local col = C.COL.brk_container
  local off = not T.get_enabled(app.track, b.node.addr)
  if off then col = U.with_alpha(col, 0x80) end
  local id = ("rbrk%d_%d_%d"):format(b.first, b.last, b.row)
  ImGui.SetCursorScreenPos(ctx, lx - 4, y0)
  ImGui.InvisibleButton(ctx, id, math.max(1, colx + colw - lx + 4), h,
    ImGui.ButtonFlags_MouseButtonLeft | ImGui.ButtonFlags_MouseButtonRight)
  local hov = ImGui.IsItemHovered(ctx)
  W.tip(ctx, id, bracket_tip(b), hov, false)
  if ImGui.IsItemClicked(ctx, ImGui.MouseButton_Left) or ImGui.IsItemClicked(ctx, ImGui.MouseButton_Right) then
    app.box_for, app.open_box_menu = b.node, true
  end
  local my = math.floor(y0 + h * 0.5) + 0.5
  ImGui.DrawList_AddLine(dl, lx, my, lx + 6, my, col, 1.5)
  local sq, sx = 7, lx + 8
  if off then ImGui.DrawList_AddRect(dl, sx + 0.5, my - 3, sx + sq - 0.5, my + 3, col, 0, 0, 1.0)
  else ImGui.DrawList_AddRectFilled(dl, sx, my - 3.5, sx + sq, my + 3.5, col) end
  local label = box_label(b.node)
  local _, th = ImGui.CalcTextSize(ctx, label)
  ImGui.DrawList_AddText(dl, sx + sq + 5, my - th * 0.5, hov and C.COL.header_text or col, label)
  local tw = ImGui.CalcTextSize(ctx, label)
  local os_lit = T.os_state(app.track, { addr = b.node.addr, ancestors = box_ancestors(b.node) }).lit
  if os_lit then
    local ox, ow, bh = sx + sq + 5 + tw + 6, W.os_width(ctx, os_lit), C.BRK_ROW_H - C.S(1)
    ImGui.DrawList_AddRectFilled(dl, ox, my - bh * 0.5, ox + ow, my + bh * 0.5, col, 2.0)
    W.push_small(ctx)
    local ot = ("%dx"):format(os_lit)
    local otw, oth = ImGui.CalcTextSize(ctx, ot)
    ImGui.DrawList_AddText(dl, ox + (ow - otw) * 0.5, my - oth * 0.5, C.COL.panel_bg, ot)
    W.pop_small(ctx)
  end
  ImGui.SetCursorScreenPos(ctx, x0, y0 + h)
  return my
end

-- the lines, after the panels: every bracket from its top (a container's
-- strip, or its first panel) to the foot of its last panel
local function rack_brk_lines(colx, strip_y)
  if (app.brk_rows or 0) == 0 then return end
  local dl = ImGui.GetWindowDrawList(ctx)
  local rect = {}
  for _, r in ipairs(app.panel_rects) do rect[r.chain_i] = r end
  for _, b in ipairs(app.brackets) do
    local ra, rb = rect[b.first], rect[b.last]
    if ra and rb then
      local box = b.kind == "container"
      local col = box and C.COL.brk_container or C.COL.brk_parallel
      if box and not T.get_enabled(app.track, b.node.addr) then col = U.with_alpha(col, 0x80) end
      local lx = math.floor(colx + 3 + (b.row + 0.5) * C.RACK_BRK_W) + 0.5
      local top = (box and strip_y[b]) or (math.floor(ra.y + 4) + 0.5)
      local bot = math.floor(rb.y + rb.h - 4) + 0.5
      ImGui.DrawList_AddLine(dl, lx, top, lx, bot, col, 1.5)
      -- the ticks in to the panels' own edges (each is indented by its depth)
      if not (box and strip_y[b]) then ImGui.DrawList_AddLine(dl, lx, top, ra.x - 2, top, col, 1.5) end
      ImGui.DrawList_AddLine(dl, lx, bot, rb.x - 2, bot, col, 1.5)
      if not box then
        -- a parallel run: "=" across the middle of its line
        local mid = math.floor((top + bot) * 0.5)
        ImGui.DrawList_AddLine(dl, lx - 3, mid - 2, lx + 3, mid - 2, col, 1.5)
        ImGui.DrawList_AddLine(dl, lx - 3, mid + 2, lx + 3, mid + 2, col, 1.5)
        local id = ("rpar%d_%d_%d"):format(b.first, b.last, b.row)
        ImGui.SetCursorScreenPos(ctx, lx - 4, mid - 6)
        ImGui.InvisibleButton(ctx, id, 8, 12)
        W.tip(ctx, id, bracket_tip(b), ImGui.IsItemHovered(ctx), false)
      end
    end
  end
end

-- inside the column's child window, `rack_w` wide: the column less the
-- scrollbar's room, kept whether or not it's showing, so the panels don't
-- jump when it comes and goes (and, showing, it sits right against them)
local function rack_inside(rack_w)
  app.panel_rects = {}
  rack_w = math.max(120, math.min(rack_w, (ImGui.GetContentRegionAvail(ctx))))
  -- its width, for the grid editor's In the rack (opened from ChannelView too)
  if math.floor(rack_w) ~= app.rack_w then
    app.rack_w = math.floor(rack_w)
    reaper.SetExtState(C.EXT_SECT, "rack_width", tostring(app.rack_w), false)
  end
  if not app.track then
    ImGui.TextDisabled(ctx, "Select a track.")
  else
    -- the plugins, each as wide as the column (less the brackets round it)
    if #app.chain == 0 and frozen_state().levels == 0 then
      ImGui.TextDisabled(ctx, "No plugins on this track yet.")
    end
    local colx = ImGui.GetCursorScreenPos(ctx)
    local indent = rack_indents()
    -- the frozen plugins first, where they were, then a line to unfreeze at
    local fst = frozen_state()
    if fst.levels > 0 then
      local _, fy = ImGui.GetCursorScreenPos(ctx)
      for k, name in ipairs(frozen_names(fst)) do
        frozen_strip(ctx, "rfz" .. k, colx, fy, rack_w, C.HEADER_H + C.S(2), k .. " \u{00B7} " .. name, fst)
        fy = fy + C.HEADER_H + C.S(2) + C.PANEL_GAP
      end
      -- the line between: "frozen above", dashes, Unfreeze, on a band of
      -- its own the column's width
      local dl = ImGui.GetWindowDrawList(ctx)
      local lh = 18
      ImGui.DrawList_AddRectFilled(dl, colx, fy, colx + rack_w, fy + lh, C.COL.panel_bg, 3.0)
      local my = math.floor(fy + lh * 0.5) + 0.5
      W.push_small(ctx)
      local lbl = "frozen above"
      local lw, lth = ImGui.CalcTextSize(ctx, lbl)
      ImGui.DrawList_AddText(dl, colx + 6, my - lth * 0.5, C.COL.frozen_text, lbl)
      local bt = "Unfreeze"
      local bw = ImGui.CalcTextSize(ctx, bt) + 12
      local bx = colx + rack_w - bw - 2
      local px = colx + lw + 12
      while px < bx - 6 do
        ImGui.DrawList_AddLine(dl, px, my, math.min(px + 4, bx - 6), my, C.COL.frozen_line, 1.0)
        px = px + 7
      end
      ImGui.SetCursorScreenPos(ctx, bx, fy + 1)
      if ImGui.InvisibleButton(ctx, "rfz_unfreeze", bw, lh - 2) then do_unfreeze() end
      local bh = ImGui.IsItemHovered(ctx)
      ImGui.DrawList_AddRectFilled(dl, bx, fy + 1, bx + bw, fy + lh - 1,
        bh and C.COL.frozen_line or U.with_alpha(C.COL.frozen_line, 0x90), 3.0)
      ImGui.DrawList_AddText(dl, bx + 6, my - lth * 0.5, C.COL.frozen_bg, bt)
      W.pop_small(ctx)
      ImGui.SetCursorScreenPos(ctx, colx, fy + lh + C.PANEL_GAP)
    end
    -- the containers starting at each panel, outermost first
    local starts = {}
    for _, b in ipairs(app.brackets or {}) do
      if b.kind == "container" then
        starts[b.first] = starts[b.first] or {}
        table.insert(starts[b.first], b)
      end
    end
    for _, l in pairs(starts) do table.sort(l, function(a, c) return a.row < c.row end) end
    local strip_y = {}
    for i, fx in ipairs(app.chain) do
      local gut = indent(i)
      local pw = rack_w - gut
      P.FILL_W = pw
      for _, b in ipairs(starts[i] or {}) do
        ImGui.SetCursorScreenPos(ctx, colx, select(2, ImGui.GetCursorScreenPos(ctx)))
        strip_y[b] = rack_brk_strip(b, colx, rack_w)
      end
      local layout, key = layout_for(fx)
      local h = rack_height(fx, layout, key, pw)
      local _, py = ImGui.GetCursorScreenPos(ctx)
      local px = colx + gut
      ImGui.SetCursorScreenPos(ctx, px, py)
      local is_src = app.drag ~= nil and app.drag.guid == fx.guid
      local w, req = P.draw(ctx, app.track, fx, layout, key, h, i, is_src)
      app.panel_rects[#app.panel_rects + 1] = { chain_i = i, x = px, y = py, w = w, h = h }
      panel_requests(i, fx, layout, key, req)
      ImGui.SetCursorScreenPos(ctx, colx, py + h + C.PANEL_GAP)
    end
    P.FILL_W = nil
    if #app.chain > 0 then
      local keep_x, keep_y = ImGui.GetCursorScreenPos(ctx)
      rack_brk_lines(colx, strip_y)
      ImGui.SetCursorScreenPos(ctx, keep_x, keep_y)
    end
    if add_tile(C.HEADER_H + C.S(12), rack_w) then B.open_menu(nil) end
  end
  -- the wheel scrolls the column, when no control took it
  if ImGui.IsWindowHovered(ctx, ImGui.HoveredFlags_ChildWindows) then
    local wy = ImGui.GetMouseWheel(ctx)
    if wy ~= 0 and not W.wheel_taken() then
      ImGui.SetScrollY(ctx, ImGui.GetScrollY(ctx) - wy * C.WHEEL_SCROLL_PX)
    end
  end
  -- a panel being dragged: the drop marker across the column
  if app.drag then
    local _, my = ImGui.GetMousePos(ctx)
    local drop = app.track and rack_drop(my) or nil
    app.drop_gap = drop
    if drop then
      local dl = ImGui.GetForegroundDrawList(ctx)
      local wx, wy = ImGui.GetWindowPos(ctx)
      local ww, wh = ImGui.GetWindowSize(ctx)
      ImGui.DrawList_PushClipRect(dl, wx, wy, wx + ww, wy + wh, false)
      ImGui.DrawList_AddRectFilled(dl, wx + 2, drop.y - 1.5, wx + ww - 2, drop.y + 1.5,
        drop.into and C.COL.brk_container or C.COL.drop_marker, 1.0)
      ImGui.DrawList_PopClipRect(dl)
      if drop.into then ImGui.SetTooltip(ctx, "Into " .. box_label(drop.into)) end
    end
    if not ImGui.IsMouseDown(ctx, ImGui.MouseButton_Left) then
      if drop then move_to(app.drag.path, drop.parent, drop.gap, app.drag.what) end
      app.drag, app.drop_gap, MX.fx_drag = nil, nil, nil
    end
  end
end

-- The column: the macros and modulators pinned across the top, the sends
-- and receives across the foot, and between them the plugins, which
-- scroll. The strips are as wide as the plugins. The plugins' scrollbar
-- sits in the window's own margin at the right edge (as thin as that
-- margin), so the column keeps the same margins either side whether it's
-- showing or not; with a drawer on the right, an 8 px one is kept room for.
C.RACK_SB = 8
local function rack_column(col_w, col_h)
  local x0, y0 = ImGui.GetCursorScreenPos(ctx)
  local wx = ImGui.GetWindowPos(ctx)
  local ww = ImGui.GetWindowSize(ctx)
  local edge = wx + ww - (ImGui.GetStyleVar(ctx, ImGui.StyleVar_WindowBorderSize) or 0)
  local room = math.floor(edge - (x0 + col_w))
  local margin = room >= 5 and room <= 16
  local sb_w = margin and room or C.RACK_SB
  local reach = margin and room or 0
  local rack_w = math.max(120, col_w + reach - sb_w)
  local top_h, foot = 0, {}
  if app.track then
    MR.STRIP_W, SD.STRIP_W, RV.STRIP_W = rack_w, rack_w, rack_w
    local ma_req, mo_req = {}, {}
    if app.aux.macros then
      local h = MR.strip_h("macros", app.track, rack_w)
      ma_req = rack_strip(h, function(hh) return MR.draw_macros(ctx, app.track, hh) end)
      top_h = top_h + h + C.PANEL_GAP
    end
    if app.aux.mods then
      local h = MR.strip_h("mods", app.track, rack_w)
      mo_req = rack_strip(h, function(hh) return MR.draw_mods(ctx, app.track, hh) end)
      top_h = top_h + h + C.PANEL_GAP
    end
    aux_mod_requests(ma_req, mo_req)
    -- the master has no receives
    if app.aux.sends then foot[#foot + 1] = { SD, SD.strip_h(app.track, rack_w) } end
    if app.aux.recv and app.track ~= reaper.GetMasterTrack(0) then
      foot[#foot + 1] = { RV, RV.strip_h(app.track, rack_w) }
    end
  end
  local foot_h = 0
  for _, f in ipairs(foot) do foot_h = foot_h + C.PANEL_GAP + f[2] end
  local mid_h = math.max(100, col_h - top_h - foot_h)
  -- the plugins
  ImGui.SetCursorScreenPos(ctx, x0, y0 + top_h)
  local cx0, cy0 = ImGui.GetCursorPos(ctx)
  -- (the window clips its children half a margin in: let this one reach
  -- the edge, so its scrollbar isn't cut)
  ImGui.PushClipRect(ctx, x0, y0 + top_h, x0 + col_w + reach, y0 + top_h + mid_h, false)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_ScrollbarSize, sb_w)
  local open = ImGui.BeginChild(ctx, "rackcol", col_w + reach, mid_h, 0,
      ImGui.WindowFlags_NoScrollWithMouse | ImGui.WindowFlags_HorizontalScrollbar)
  ImGui.PopStyleVar(ctx)
  if open then
    rack_inside(rack_w)
    ImGui.EndChild(ctx)
  else
    W.child_skipped(ctx, col_w + reach, mid_h, cx0, cy0)
  end
  ImGui.PopClipRect(ctx)
  -- the sends and the receives
  local fy = y0 + top_h + mid_h
  for _, f in ipairs(foot) do
    ImGui.SetCursorScreenPos(ctx, x0, fy + C.PANEL_GAP)
    local _, req = f[1].draw(ctx, app.track, f[2])
    if req and req.changed then rescan(true) end
    fy = fy + C.PANEL_GAP + f[2]
  end
  -- the column's whole height taken, as one item, for what follows
  ImGui.SetCursorScreenPos(ctx, x0, y0)
  ImGui.Dummy(ctx, col_w, math.max(col_h, fy - y0))
  -- (reaching into the margin makes the window a few pixels wider than it
  -- shows; it never scrolls across for them)
  if reach > 0 and ImGui.GetScrollX(ctx) ~= 0 then ImGui.SetScrollX(ctx, 0) end
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
  -- plugin pictures (Pro): ChannelView's own window watches for plugin
  -- windows opening, to take their picture the first time
  if not app.thumbs_on then
    app.thumbs_on = true
    local th = not RACK and W.thumbs()
    if th then th.watch = true end
  end
  P.begin_frame()
  P.begin_rects()
  MR.begin_frame()
  if FZ.poll() then rescan(true) end
  -- an Alt+click on a plugin's header last frame: asked here, before
  -- anything is drawn from the chain it changes
  if app.remove_ask then
    local fx = app.remove_ask
    app.remove_ask = nil
    if reaper.MB(("Remove %s from the chain?"):format(U.fx_label(fx)), "ChannelView", 1) == 1 then remove_fx(fx) end
  end
  follow_selection()
  -- (not while the TCP window's overview is on: it changes track too
  -- often for windows to come and go with it)
  AF.tick((app.float_empty and reaper.GetExtState(C.EXT_SECT, "overview_on") ~= "1") and app.track or nil,
    no_controls)
  PC.tick()
  P.AUTO_FLOAT = app.float_empty
  do
    local now = reaper.time_precise()
    if now - colour_poll > 0.5 then
      colour_poll = now
      -- Options changed in another window (the rack, the TCP's),
      -- or the shared hue and tint by another TS_ tool
      if app.VO.poll() then
        app.VO.apply(app.vo_tab)
      elseif app.vo_tab == "cv" or app.VO.follows(app.vo_tab) then
        local h, t = pal_get()
        C.apply_colour(h or C.BASE_HUE, t or C.TINT)
      end
      -- and the view options the two windows share
      C.SHOW_VALUES = ext_get("show_values", "1") == "1"
      C.WHEEL_CONTROLS = ext_get("wheel_controls", "1") == "1"
      C.FOCUS_BACK  = ext_get("focus_back", "1") == "1"
      U.ADAPTIVE    = ext_get("adaptive_units", "0") == "1"
      TO.reload_fader_defaults()      -- the TCP window may have changed them
      -- a layout saved by the other window (ChannelView / its Rack view)
      local ms, ss = M.sync(), SC.sync()
      if ms or ss then rescan(true) end
      C.set_channel_w(ext_get("channel_w", tostring(C.CHANNEL_W_DEFAULT)))
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

  -- the action bars' list, when the TCP or the toolbars script changed it
  DR.sync()

  ImGui.SetNextWindowSize(ctx, 1100, 300, ImGui.Cond_FirstUseEver)
  if app.dock_req then
    -- the Dock menu's pick (0: floating)
    ImGui.SetNextWindowDockID(ctx, app.dock_req, ImGui.Cond_Always)
    dock_id = app.dock_req
    ext_set(DOCK_KEY, dock_id)
    app.dock_req = nil
  elseif dock_id ~= 0 then
    ImGui.SetNextWindowDockID(ctx, dock_id, ImGui.Cond_FirstUseEver)
  end

  ImGui.PushStyleColor(ctx, ImGui.Col_WindowBg, C.COL.win_bg)
  -- the look of every panel, dialogue and menu drawn this frame, in its
  -- text font (Options > Text)
  ST.push(ctx)
  local text_font = W.push_font(ctx, "text")
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

  local wflags = ImGui.WindowFlags_NoScrollWithMouse
  -- hidden, the header is a child of its own drawn over the panels at the
  -- end of the frame (app.header_overlay)
  if not app.header_hide then wflags = wflags | ImGui.WindowFlags_MenuBar end
  -- C.WIN_NO_SCROLLBAR is not decoration: the header measurement below
  -- relies on there being no bottom decoration to subtract.
  if C.WIN_NO_SCROLLBAR then wflags = wflags | ImGui.WindowFlags_NoScrollbar end

  -- Track rules as tracks are added and moved: every frame, whether the
  -- window shows or not (docked behind another tab, say)
  require("TS_CV_TrackRules").tick()

  local visible, open = ImGui.Begin(ctx, C.WIN_TITLE, true, wflags)

  if visible then
    local d = ImGui.GetWindowDockID(ctx)
    if d ~= dock_id then dock_id = d; ext_set(DOCK_KEY, d) end
    do  -- for a panel dragged out of it (a popped-out copy)
      local wx, wy = ImGui.GetWindowPos(ctx)
      local ww, wh = ImGui.GetWindowSize(ctx)
      app.win_rect = { wx, wy, ww, wh }
    end
    if not app.header_hide then menu_bar() end
    app.shown_once = true
  elseif not app.shown_once and not RACK and dock_id ~= 0 then
    -- Started with REAPER into a docker whose tab REAPER doesn't bring
    -- forward (another window's tab is showing, or the tabs are hidden):
    -- bring ours forward, once a second for the first 15 seconds.
    local now = reaper.time_precise()
    app.start_t = app.start_t or now
    if now - app.start_t < 15 and (not app.activate_t or now - app.activate_t >= 1)
       and reaper.JS_Window_Find and reaper.DockWindowActivate then
      app.activate_t = now
      local h = reaper.JS_Window_Find(C.WIN_TITLE, true)
      if h then reaper.DockWindowActivate(h) end
    end
  end
  ImGui.PopStyleVar(ctx)

  if app.header_dbl then
    app.header_dbl = false
    set_view(not C.MIXER_VIEW)
  end
  -- the Toggle mixer view action, from a shortcut or a toolbar
  if not RACK and reaper.GetExtState(C.EXT_SECT, TOGGLE_REQ) ~= "" then
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
      -- the header hidden: the rule at the window's top, the panels
      -- straight under it -- the header's room is theirs
      if app.header_hide then ry = wy + 3 end

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

    -- action drawers along the top (TS_CV_Drawers): first under the
    -- header, above MIDI learn -- they stay, MIDI learn comes and goes
    if #DR.open_on("top") > 0 then
      local tw = ImGui.GetContentRegionAvail(ctx)
      local tx, ty = ImGui.GetCursorScreenPos(ctx)
      local th = DR.draw_h(ctx, "top", tx, ty, tw)
      ImGui.SetCursorScreenPos(ctx, tx, ty + th + 2)
      ImGui.Dummy(ctx, 0, 0)
    end

    -- the MIDI learn drawer, full width under the header: the rows below
    -- lose its height while it's open
    if ML.is_open() then
      local dw = ImGui.GetContentRegionAvail(ctx)
      ML.draw(ctx, dw)
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
    -- reserved ALWAYS, not only on a frame the row's content
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
    -- window's bottom edge by however many pixels this is, and comes out
    -- shorter than mixer view's.
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

    -- Drawers (TS_CV_Drawers): along the bottom they take their height
    -- (and one more ItemSpacing) from the row; down the sides, their
    -- width from the panels.
    local full_w0 = ImGui.GetContentRegionAvail(ctx)
    local bot_h = DR.extent(ctx, "bottom", full_w0)
    local bot_take = bot_h > 0 and (bot_h + spacing_y) or 0
    local left_w, right_w = DR.extent(ctx, "left", 0), DR.extent(ctx, "right", 0)
    local SIDE_GAP = 4
    local left_take  = left_w > 0 and (left_w + SIDE_GAP) or 0
    local right_take = right_w > 0 and (right_w + SIDE_GAP) or 0

    -- And row_h (the Channel/plugin-row/Sends height) is everything
    -- left in avail_h once strip_h AND the ItemSpacing.y between the
    -- two of them are both spent -- so row_h + spacing_y + strip_h
    -- lands on avail_h exactly, the same total mixer view gets, split
    -- differently rather than shrunk.
    -- the patch bay (Pro), open in channel view: between the panels and
    -- the name row, the panels giving up its height
    local cv_bay = (not RACK and not C.MIXER_VIEW) and MX.bay_lift(ctx) or 0
    local row_h = math.max(C.CELL_H + C.HEADER_H + C.PANEL_PAD * 2,
                           avail_h - spacing_y - strip_h - bot_take - cv_bay)
    -- Channel pinned left, Sends and Receives pinned right, the plugin
    -- row scrolling between them. The pinned panels are measured first so
    -- the row in the middle knows what is left for it.
    local full_w = full_w0 - left_take - right_take
    local ch_w   = CH.width(CH.is_collapsed())
    -- The master has no Receives panel: every track feeds it, and the
    -- list would only ever be the odd real send to the master.
    local on_master = app.track ~= nil and app.track == reaper.GetMasterTrack(0)
    -- (any of the four can be hidden from the View menu)
    local ma_on, mo_on = app.aux.macros, app.aux.mods
    local sd_on, rv_on = app.aux.sends, app.aux.recv and not on_master
    local rv_w   = rv_on and RV.width_for(app.track, row_h) or 0
    local sd_w   = sd_on and SD.width_for(app.track, row_h) or 0
    -- the macros and the modulators, pinned beside the fader panel
    -- (and the console and DrumToolbox panels before the fader, Pro:
    -- counted in with them)
    local mr_w   = (ma_on and MR.width_for("macros", app.track, row_h) or 0)
                   + (mo_on and MR.width_for("mods", app.track, row_h) or 0)
                   + (ED.PRO and (ED.module("TS_CV_ConsoleDrawer", ED.stub()).panel_w() or 0) or 0)
                   + (ED.PRO and (ED.module("TS_CV_DrumPanel", ED.stub()).panel_w(app.track) or 0) or 0)
    local n_gaps = 1 + (ma_on and 1 or 0) + (mo_on and 1 or 0) + (sd_on and 1 or 0) + (rv_on and 1 or 0)
                   + ((ED.PRO and (ED.module("TS_CV_ConsoleDrawer", ED.stub()).panel_w() or 0) or 0) > 0 and 1 or 0)
                   + ((ED.PRO and (ED.module("TS_CV_DrumPanel", ED.stub()).panel_w(app.track) or 0) or 0) > 0 and 1 or 0)
    local mid_w  = math.max(80, full_w - ch_w - mr_w - rv_w - sd_w - C.PANEL_GAP * n_gaps)

    -- A double-click on a NAME BUTTON renames that track (name_dbl), in
    -- either branch below -- the button means the same thing whether it's
    -- sitting under a strip or on its own. One place to act on it, since
    -- MX.draw_row hands it back the same way from both views.
    local function open_from_name(tr)
      app.track = tr
      S.request_scroll()
      rescan(true)
      set_view(false)
    end
    -- a name button double-clicked: renamed there, as on REAPER's track
    -- panel (the master, which has no name to change, opens)
    local function name_dbl(tr)
      if tr == reaper.GetMasterTrack(0) then open_from_name(tr) else TM.open_rename(tr) end
    end

    -- the side drawers, beside a row h tall starting at the cursor; the
    -- cursor is left where the row's first item goes
    local function side_drawers(h)
      local rx, ry = ImGui.GetCursorScreenPos(ctx)
      if left_w > 0 then DR.draw_v(ctx, "left", rx, ry, h) end
      if right_w > 0 then DR.draw_v(ctx, "right", rx + full_w0 - right_w, ry, h) end
      ImGui.SetCursorScreenPos(ctx, rx + left_take, ry)
    end
    -- the bottom drawers, at the cursor (the start of a line)
    local function bottom_drawers()
      if bot_h <= 0 then return end
      local bx, by = ImGui.GetCursorScreenPos(ctx)
      DR.draw_h(ctx, "bottom", bx, by, full_w0)
      ImGui.SetCursorScreenPos(ctx, bx, by + bot_h)
      ImGui.Dummy(ctx, 0, 0)
    end

    if RACK then
      local col_h = avail_h - bot_take
      side_drawers(col_h)
      rack_column(full_w, col_h)
      bottom_drawers()
    elseif C.MIXER_VIEW then
      -- Mixer view takes the whole upper area. The track row underneath
      -- -- strips and their name buttons together, one scrolling child
      -- -- stays: it is the one thing both views share, and losing it
      -- would make switching feel like changing windows rather than
      -- changing what you are looking at.
      local mix_h = avail_h - bot_take
      side_drawers(mix_h)
      local open_it, want_view, dbl_track =
        MX.draw_row(ctx, mix_h, app.track, true, child_pad_y, win_pad_x,
          (left_take + right_take > 0) and full_w or nil)
      bottom_drawers()
      if want_view then
        set_view(false)
      end
      if open_it then
        MX.select_only(open_it)
        reaper.TrackList_AdjustWindows(false)
        reaper.UpdateArrange()
        app.track = open_it
        S.request_scroll()
        rescan(true)
        set_view(false)
      elseif dbl_track then
        name_dbl(dbl_track)
      end
    else
      side_drawers(row_h)
      if ED.PRO and (ED.module("TS_CV_ConsoleDrawer", ED.stub()).panel_w() or 0) > 0 then
        ED.module("TS_CV_ConsoleDrawer").draw_panel(ctx, row_h)
        ImGui.SameLine(ctx, 0, C.PANEL_GAP)
      end
      if ED.PRO and (ED.module("TS_CV_DrumPanel", ED.stub()).panel_w(app.track) or 0) > 0 then
        ED.module("TS_CV_DrumPanel").draw(ctx, app.track, row_h)
        ImGui.SameLine(ctx, 0, C.PANEL_GAP)
      end
      CH.draw(ctx, app.track, row_h)
      local ma_req, mo_req = {}, {}
      if ma_on then
        ImGui.SameLine(ctx, 0, C.PANEL_GAP)
        ma_req = select(2, MR.draw_macros(ctx, app.track, row_h)) or {}
      end
      if mo_on then
        ImGui.SameLine(ctx, 0, C.PANEL_GAP)
        mo_req = select(2, MR.draw_mods(ctx, app.track, row_h)) or {}
      end
      if app.track then aux_mod_requests(ma_req, mo_req) end
      ImGui.SameLine(ctx, 0, C.PANEL_GAP)
      panel_row(row_h, mid_w)
      if sd_on then
        ImGui.SameLine(ctx, 0, C.PANEL_GAP)
        local _, sd_req = SD.draw(ctx, app.track, row_h)
        if sd_req and sd_req.changed then rescan(true) end
      end
      if rv_on then
        ImGui.SameLine(ctx, 0, C.PANEL_GAP)
        local _, rv_req = RV.draw(ctx, app.track, row_h)
        if rv_req and rv_req.changed then rescan(true) end
      end

      -- Double-clicking the Channel panel's background -- not the fader,
      -- which means unity -- goes back to the mixer.
      if CH.want_mixer then
        CH.want_mixer = false
        set_view(true)
      end
      if app.row_dbl then
        app.row_dbl = false
        set_view(true)
      end

      -- The track row, on its own -- same window id as mixer view's
      -- row, just without the strips above the names, so the scroll
      -- position it lands on here is exactly the one mixer view left it
      -- at. Double-clicking its empty background (past the last name
      -- button) is the mirror of mixer view's own empty-space
      -- double-click: back to mixer, same as double-clicking the
      -- Channel panel or the empty plugin row does.
      local _, want_mixer, dbl_track =
        MX.draw_row(ctx, strip_h + cv_bay, app.track, false, child_pad_y, win_pad_x)
      if want_mixer then
        set_view(true)
      elseif dbl_track then
        name_dbl(dbl_track)
      end
      -- the bottom drawers: under the track names, where mixer view has
      -- them too
      bottom_drawers()
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
    DR.draw_menus(ctx)
    DR.poll()

    E.draw(ctx, app.track)
    if SD.draw_menu(ctx, app.track) then rescan(true) end
    if SD.draw_ctx(ctx, app.track) then rescan(true) end
    if RV.draw_menu(ctx, app.track) then rescan(true) end
    if RV.draw_ctx(ctx, app.track) then rescan(true) end
    if B.draw_menu(ctx, app.track) then rescan(true) end
    if B.draw(ctx, app.track, false) then rescan(true) end
    PU.draw(ctx)
    if LS.draw(ctx, function(k) return E.is_open() and E.key() == k end) then rescan(true) end
    CS.draw(ctx)
    require("TS_CV_GainCheck").draw(ctx)
    if TM.draw(ctx) then rescan(true) end
    CP.draw(ctx, false)
    if CN.draw(ctx) then rescan(true) end

    -- Probe taps: the heartbeat that keeps them measuring, and one
    -- track's routing re-checked per frame.
    TP.update()
    -- Steps' and MSEGs' patterns on their way to and from their plugin
    require("TS_CV_ModPat").tick()
    -- a factory preset the plugin didn't tell REAPER about (TS_CV_Presets)
    require("TS_CV_Presets").tick()
    FO.update(ctx, ImGui, C.FOCUS_BACK)

    -- Last thing in the frame, on the foreground draw list: a tooltip
    -- that is following a control being dragged has to sit above every
    -- panel, popup and menu regardless of what was drawn when.
    MR.overlay(ctx, (not C.MIXER_VIEW) and app.track or nil, P.panel_at)
    app.header_overlay()
    W.draw_tip(ctx)
    ImGui.End(ctx)
  end
  -- popped-out panels (Pro), each a window of its own
  POP.take_request()
  POP.windows()
  -- the Organise actions window, its own window beside this one
  AE.draw(ctx)
  -- the knob look editor (Style > Customise...), its own window too
  KE.draw(ctx)
  -- View > Options
  app.VO.draw(ctx, app.vo_tab)
  -- View > Console setup (Pro)
  ED.module("TS_CV_ConsoleSetup", ED.stub()).draw(ctx)
  -- the grid editor (Edit layout...), and the menu of a control
  -- right-clicked in it
  do
    local GE = ED.module("TS_CV_GridEditor", ED.stub())
    GE.draw(ctx)
    local m = GE.take_menu()
    if m then
      for i, f in ipairs(app.chain or {}) do
        if f.guid == m.guid then
          app.ctl_menu = { fx = i, ctl = m.idx, ed = true }
          app.open_ctl_menu = true
          break
        end
      end
    end
  end

  -- The style pushes happened before Begin, so they unwind either way.
  ImGui.PopStyleVar(ctx, 1)
  W.pop_font(ctx, text_font)
  ST.pop(ctx)
  ImGui.PopStyleColor(ctx)

  if open and not app.want_quit then
    reaper.defer(safe_frame)
  else
    M.save()
    SC.save()
  end
end

-- While REAPER is busy on a long job (TS_CV_Busy), the window is drawn
-- with a note and nothing else: no FX calls to contend with the job,
-- and the ImGui context stays alive. A full frame is tried once a
-- second, and the first quick one ends it.
local function busy_frame()
  ImGui.PushStyleColor(ctx, ImGui.Col_WindowBg, C.COL.win_bg)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_FramePadding, 6, C.MENU_PAD_Y)
  local wflags = ImGui.WindowFlags_MenuBar | ImGui.WindowFlags_NoScrollWithMouse
  if C.WIN_NO_SCROLLBAR then wflags = wflags | ImGui.WindowFlags_NoScrollbar end
  local visible, open = ImGui.Begin(ctx, C.WIN_TITLE, true, wflags)
  if visible then
    local msg = "ChannelView is waiting while REAPER is busy\u{2026}"
    local w, h = ImGui.GetContentRegionAvail(ctx)
    local tw, th = ImGui.CalcTextSize(ctx, msg)
    local cx, cy = ImGui.GetCursorScreenPos(ctx)
    ImGui.DrawList_AddText(ImGui.GetWindowDrawList(ctx),
      cx + (w - tw) * 0.5, cy + (h - th) * 0.5, C.COL.empty_text, msg)
    ImGui.End(ctx)
  end
  ImGui.PopStyleVar(ctx)
  ImGui.PopStyleColor(ctx)
  local now = reaper.time_precise()
  if not app.alive_t or now - app.alive_t > 0.5 then
    app.alive_t = now
    reaper.SetExtState(C.EXT_SECT, ALIVE, tostring(now), false)
  end
  if open and not app.want_quit then
    reaper.defer(safe_frame)
  else
    M.save()
    SC.save()
  end
end

local function timed_frame()
  local now = reaper.time_precise()
  if not BZ.probe_due(now) then return busy_frame() end
  frame()
  BZ.note(reaper.time_precise() - now, now)
end

-- A runtime error inside a deferred function is reported by REAPER with
-- only the file and line it happened ON -- which, when a nil is handed to
-- a drawing helper, names the helper rather than the caller that produced
-- the nil. The loop runs through xpcall instead: the console gets a full
-- traceback naming every frame on the way down, the layouts are saved,
-- and the loop stops rather than throwing the same error sixty times a
-- second.
--
-- ReaImGui can't start a frame while a screen reports no scale (macOS,
-- with the display asleep, say): the first call of the frame fails on
-- new_dpi_scale. Nothing has been drawn then, so the loop waits half a
-- second and tries again instead of stopping.
function safe_frame()
  if app.dpi_wait and reaper.time_precise() - app.dpi_wait < 0.5 then
    reaper.defer(safe_frame)
    return
  end
  local ok, err = xpcall(timed_frame, function(e)
    return debug.traceback(tostring(e), 2)
  end)
  if ok then app.dpi_wait = nil return end
  if tostring(err):find("new_dpi_scale", 1, true) then
    app.dpi_wait = reaper.time_precise()
    reaper.defer(safe_frame)
    return
  end
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
  DR.cancel_picks(); AE.cancel_picks(); E.cancel_vpick()
  M.save(); SC.save()
  reaper.DeleteExtState(C.EXT_SECT, ALIVE, false)
  require("TS_CV_Upkeep").release()
  show_toggle_state(false)      -- no window, no mixer showing
end)
if not RACK then reaper.DeleteExtState(C.EXT_SECT, TOGGLE_REQ, false) end   -- one left from a window since closed
show_toggle_state(C.MIXER_VIEW)
reaper.defer(safe_frame)
