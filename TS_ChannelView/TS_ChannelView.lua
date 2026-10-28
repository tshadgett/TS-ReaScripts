-- @description ChannelView -- docked channel strip: one editable control panel per plugin
-- @author Tim Shadgett
-- @version 3.6.1
-- @changelog
--  Moves with ChannelView Pro 3.6.1: plugin pictures taken many at once
--  (every plugin button, or a developer's plugins). See the CHANGELOG.
-- @license MIT
-- @provides
--  [main]   TS_CV_Diag.lua
--  [main]   TS_ChannelView_TCP.lua
--  [main]   TS_ChannelView_ToggleMixer.lua
--  [main]   TS_ChannelView_BypassModulation.lua
--  [webinterface] TS_CV_ActionIcons.json
--  [nomain] TS_CV_Actions.lua
--  [nomain] TS_CV_Arrange.lua
--  [nomain] TS_CV_Toolbar.lua
--  [nomain] TS_CV_Browser.lua
--  [nomain] TS_CV_Mod.lua
--  [nomain] TS_CV_Units.lua
--  [nomain] TS_CV_ReaFX.lua
--  [nomain] TS_CV_ModRack.lua
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
--  [nomain] TS_CV_Steps.lua
--  [nomain] TS_CV_Taps.lua
--  [nomain] TS_CV_Trace.lua
--  [nomain] TS_CV_TrackMenu.lua
--  [nomain] TS_CV_TrackOps.lua
--  [nomain] TS_CV_TrackStrip.lua
--  [nomain] TS_CV_FXButtons.lua
--  [nomain] TS_CV_KnobParts.lua
--  [nomain] TS_CV_Freeze.lua
--  [nomain] TS_CV_AutoFloat.lua
--  [nomain] TS_CV_Util.lua
--  [nomain] TS_CV_Widgets.lua
--  [nomain] TS_CV_WebLink.lua
--  [effect] TS_TrackProbe.jsfx
--  [effect] TS_CV_Modulators.jsfx
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
C.set_cell_w(ext_get("cell_w", tostring(C.CELL_W_DEFAULT)))
C.set_channel_w(ext_get("channel_w", tostring(C.CHANNEL_W_DEFAULT)))
-- (stored under the key plate_texture, so saved choices still load)
C.EFFECT_3D = ED.PRO and ext_get("plate_texture", C.EFFECT_3D and "1" or "0") == "1" or false
C.SHADOW = math.max(0, math.min(C.SHADOW_MAX, tonumber(ext_get("shadow", tostring(C.SHADOW))) or C.SHADOW))
ED.light().STRENGTH = C.SHADOW / 100
C.LIGHT = math.max(0, math.min(C.LIGHT_MAX, tonumber(ext_get("light", tostring(C.LIGHT))) or C.LIGHT))
require("TS_CV_KnobParts").LIGHT = C.LIGHT / 100
C.PRESET_BAR = ext_get("preset_bar", C.PRESET_BAR and "1" or "0") == "1"
-- Which of the two views is up. Persisted, because reopening the window
-- into the view you were not in is a small daily annoyance.
C.MIXER_VIEW  = (not RACK) and ext_get("mixer_view", "0") == "1"
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
  -- kept at the ends of the chain (TP.keep_in_place), checked whenever
  -- the whole chain's shape changes.
  local list = {}
  if app.track then
    local full = T.collect(app.track)
    local fh = T.hash(full)
    if fh ~= app.full_hash or app.track ~= app.full_track then
      app.full_hash, app.full_track = fh, app.track
      -- after an unfreeze (from anywhere) the helpers go back to their
      -- slots; a lone probe gets its partner back, unless the other is
      -- frozen and comes back with an unfreeze
      local moved = FZ.sync(app.track)
      FZ.forget()
      local fz = FZ.state(app.track, U.clean_fx_name)
      if not FZ.busy(app.track) and fz.probes == 0 and TP.complete_pair(app.track) then moved = true end
      if TP.keep_in_place(app.track) or moved then
        full = T.collect(app.track)
        app.full_hash = T.hash(full)
      end
      -- a duplicated or pasted track, or one from a template: its plugins
      -- take up the settings it carries (TS_CV_Carry)
      if require("TS_CV_Carry").adopt(app.track, full) then St.clear_cache() end
    end
    -- and what it carries kept up to date, every couple of seconds
    if now - (app.carry_at or 0) > 2 then
      app.carry_at = now
      require("TS_CV_Carry").write(app.track, full)
    end
    list = MD.strip(app.track, full)
    if not TP.probes_shown() then list = TP.strip_probes(app.track, list) end
    -- a container with knobs on it gets a panel of its own, at its head;
    -- folded to that panel, what's inside it stays out of the row
    local tr, with_panel = app.track, {}
    list = T.with_container_panels(list, function(n)
      local vis = CT.visible(tr, n.addr, n.guid, n.path)
      if #vis == 0 then return nil end
      with_panel[n.guid] = true
      return { visible = vis, sig = table.concat(vis, ",") }
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
  ImGui.DrawList_AddRectFilled(dl, x, y, x + w, y + h, hov and C.COL.frozen_head or C.COL.frozen_bg, 3.0)
  ImGui.DrawList_AddRect(dl, x, y, x + w, y + h, U.with_alpha(C.COL.frozen_line, 0x70), 3.0, 0, 1.0)
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

-- ---------------------------------------------------------------------
-- the plugin's own colours (TS_CV_PluginColours): read off its window
-- into its layout's palette, offered in every colour menu (From the
-- plugin) and put on the whole panel by Faceplate > Match the plugin
-- ---------------------------------------------------------------------
local pal_fail = {}     -- fx guid -> why its colours couldn't be read

local function fx_by_guid(guid)
  for _, f in ipairs(app.chain or {}) do
    if f.guid == guid then return f end
  end
  return nil
end

-- a touch lighter (a dark colour) or darker (a light one)
local function lift(rgb)
  local r, g, b = (rgb >> 16) & 0xff, (rgb >> 8) & 0xff, rgb & 0xff
  local d = ((0.299 * r + 0.587 * g + 0.114 * b) < 128) and 18 or -18
  local function ch(v) return math.max(0, math.min(255, v + d)) end
  return (ch(r) << 16) | (ch(g) << 8) | ch(b)
end

-- The panel in the plugin's colours: the faceplate its main surface,
-- sections on their own faceplate its second, controls' own backgrounds
-- its third; buttons lit, and Arc and LED ring knobs and Slim faders
-- coloured, in its first accent. Only what's there is recoloured: a
-- section or background isn't added.
local function match_palette(l, pal)
  local s = pal.surfaces or {}
  if not s[1] then return end
  local s2 = s[2] or lift(s[1])
  local s3 = s[3] or s2
  local a = (pal.accents or {})[1]
  l.plate = hex_key(s[1])
  for _, c in ipairs(l.controls or {}) do
    if c.type == "divider" then
      if c.style == "plate" then c.cap = hex_key(s2) end
    elseif c.back and c.back ~= "inset" then
      c.back = hex_key(s3)
    end
    if a then
      local ks = C.KNOB_STYLE_ALIAS[c.style] or c.style
      if c.type == "toggle" or (c.type == "combo" and c.buttons)
          or ((c.type == "knob" or c.type == "stepped") and not c.look and (ks == "arc" or ks == "led"))
          or (c.type == "fader" and c.style == "slim") then
        c.cap = hex_key(a)
      end
    end
  end
end

-- Read plugin fx's colours into its layout; then `after(layout, pal)`.
local function read_palette(fx, after)
  local guid = fx.guid
  pal_fail[guid] = nil
  local function on_read(pal, why)
    if not pal then pal_fail[guid] = why or "nothing read" return end
    local f = fx_by_guid(guid)
    if not f then return end
    local l, pk = materialise(f)
    l.palette = pal
    if after then after(l, pal) end
    M.set(pk, l); M.save()
  end
  PC.start(app.track, fx.addr, guid, on_read)
end

-- A colour menu's From the plugin row: the plugin's surfaces, then its
-- accents, one click each, and the eyedropper that reads them (again).
local function palette_row(fx, id, pick_key)
  if not fx or not fx.guid or fx.guid == "" or not ED.PRO then return end
  local layout = layout_for(fx)
  local pal = layout and layout.palette
  local dl = ImGui.GetWindowDrawList(ctx)
  ImGui.Spacing(ctx)
  ImGui.TextDisabled(ctx, "From the plugin")
  if not PC.supported() then
    ImGui.SameLine(ctx)
    ImGui.TextDisabled(ctx, "(Windows, with js_ReaScriptAPI)")
    return
  end
  if PC.busy(fx.guid) then
    ImGui.TextDisabled(ctx, "Reading its window\u{2026}")
    return
  end
  local x, y = ImGui.GetCursorScreenPos(ctx)
  if ImGui.Button(ctx, "##" .. id .. "_pread", 18, 18) and not PC.busy() then read_palette(fx) end
  if ImGui.IsItemHovered(ctx) then
    ImGui.SetTooltip(ctx, (pal and "Read the plugin's colours again" or "Read the plugin's colours") ..
      "\n(its window comes to the front for a moment)")
  end
  W.ICONS.dropper(dl, x + 3, y + 3, 12, C.COL.icon)
  local n = 0
  for gi, group in ipairs({ pal and pal.surfaces or {}, pal and pal.accents or {} }) do
    for i, rgb in ipairs(group) do
      ImGui.SameLine(ctx, 0, (i == 1 and gi == 2 and n > 0) and 10 or 4)
      if ImGui.ColorButton(ctx, hex_key(rgb):upper() .. "##" .. id .. "_pal" .. gi .. "_" .. i,
          (rgb << 8) | 0xff, ImGui.ColorEditFlags_NoTooltip, 18, 18) then
        pick_key(hex_key(rgb), true)
        CP.remember(rgb)
      end
      if ImGui.IsItemHovered(ctx) then
        ImGui.SetTooltip(ctx, ((gi == 1) and "Surface  " or "Accent  ") .. hex_key(rgb):upper())
      end
      n = n + 1
    end
  end
  if pal_fail[fx.guid] then
    ImGui.TextDisabled(ctx, "Couldn't read it: " .. pal_fail[fx.guid])
  end
end

-- After a menu's faceplate swatches: the colour of your own it has now
-- (when it has one), the Recent colours flyout -- every custom colour
-- given to a faceplate, background or section since ChannelView started --
-- and the [+] that opens the colour picker (TS_CV_ColourPick), with its
-- palettes and eyedropper. While the picker is open the panel shows the
-- colour being chosen; Cancel puts back what was there.
--   now:   the key chosen now
--   pick_key(k, save): makes key k the choice (nil = none), saving if `save`
--   from:  the colour the picker starts on when there's no custom one
local function custom_rows(id, now, width, pick_key, title, from, fx)
  local ck = C.custom_key(now)
  if ck then
    local pl = C.plate_of(ck)
    swatch_row("Custom  " .. pl.label, id .. "_now", true, width, pl.bg, pl.border)
  end
  palette_row(fx, id, pick_key)
  ImGui.Spacing(ctx)
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
    ImGui.SetTooltip(ctx, "Your custom colours appear here until ChannelView closes.")
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
    ImGui.SetTooltip(ctx, "Pick any colour: palette, picker or eyedropper.")
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
local function swatch_extras(id, now, from, title, pick_key, fx)
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
  palette_row(fx, id, pick_key)
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
      ImGui.SetTooltip(ctx, "Theme panel colour, follows Hue/Tint.")
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
    custom_rows("plate", layout.plate, 150, set, "Faceplate colour", now_pl and (now_pl.bg >> 8), fx)
  end
  -- the whole panel in the plugin's colours (read from its window first,
  -- when they haven't been)
  ImGui.Separator(ctx)
  if ImGui.MenuItem(ctx, "Match the plugin##plate_match", nil, false, PC.supported() and not PC.busy()) then
    local l, pk = materialise(fx)
    if l.palette then
      match_palette(l, l.palette)
      M.set(pk, l); M.save()
    else
      read_palette(fx, match_palette)
    end
  end
  if ImGui.IsItemHovered(ctx, ImGui.HoveredFlags_AllowWhenDisabled) then
    ImGui.SetTooltip(ctx, not PC.supported() and "Needs Windows and js_ReaScriptAPI."
      or "The faceplate, section faceplates and backgrounds in the plugin's own\n" ..
         "colours, and its accent on buttons, Arc and LED ring knobs and Slim faders.\n" ..
         "The first time, its window comes to the front for a moment to be read.")
  end
  -- the surface finish, on whichever faceplate is chosen (the theme's has none)
  ImGui.Separator(ctx)
  local plate = C.plate_of(layout.plate)
  local fin = M.finish(layout, plate) or "plain"
  if ImGui.BeginMenu(ctx, "Finish##plate_finish", plate ~= nil) then
    local dflt = (plate and plate.brushed) and "brushed" or "plain"
    for _, f in ipairs(C.FINISHES) do
      if ImGui.MenuItem(ctx, f.label .. "##plate_fin_" .. f.key, nil, fin == f.key) then
        local l = materialise(fx)
        -- the faceplate's own choice is no choice at all, so it isn't saved
        l.brush = nil
        l.finish = (f.key ~= dflt) and f.key or nil
        M.set(key, l); M.save()
      end
    end
    ImGui.EndMenu(ctx)
  end
  if ImGui.IsItemHovered(ctx, ImGui.HoveredFlags_AllowWhenDisabled) then
    ImGui.SetTooltip(ctx, plate and "The faceplate's surface." or "Choose a faceplate first.")
  end
  -- and/or a metallic flake, like metallic paint
  local mt = M.metal(layout, plate)
  if ImGui.MenuItem(ctx, "Metallic flake##plate_metal", nil, mt, plate ~= nil) then
    local l = materialise(fx)
    l.metal = (not mt) or nil
    M.set(key, l); M.save()
  end
  if ImGui.IsItemHovered(ctx, ImGui.HoveredFlags_AllowWhenDisabled) then
    ImGui.SetTooltip(ctx, plate and "Metallic flake over the finish."
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

-- The look new knobs or buttons start with (M.default_look): this
-- control's, or forget it. Ticked while this control has that look.
local function new_look_items(fam, c, noun)
  local d = M.default_look(fam)
  local same = d ~= nil and (d.style or false) == (c.style or false) and (d.cap or false) == (c.cap or false)
  if same and fam == "knob" then
    same = (d.scale_ink or false) == (c.scale_ink or false)
           and (KPm.encode(d.look) or "") == (KPm.encode(c.look) or "")
           and ((d.arc ~= nil) == (c.arc ~= nil))
  end
  if ImGui.MenuItem(ctx, "Use this look for new " .. noun, nil, same) then
    M.set_default_look(fam, c)
  end
  if ImGui.IsItemHovered(ctx) then
    ImGui.SetTooltip(ctx, (fam == "knob")
      and "New and automatic layouts, and knobs added in the editor,\n" ..
          "start with this knob's style, colours and value arc.\n" ..
          "(A centred knob gets the Centred arc.)"
      or "New and automatic layouts, and buttons added in the editor,\n" ..
         "start with this button's style and lit colour.")
  end
  if d and ImGui.MenuItem(ctx, "Forget the look for new " .. noun) then
    M.set_default_look(fam, nil)
  end
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
    -- (a switch's style is lit in its own row below, not Flat's)
    local cur = (c.style and (C.BUTTON_STYLE[c.style] or C.SWITCH[c.style])) and c.style or "flat"
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
    -- a toggle can be a hardware switch instead, each shown on, in the
    -- same list
    if c.type == "toggle" then
      local sh = 30
      for _, sw in ipairs(C.SWITCH_STYLES) do
        local x, y = ImGui.GetCursorScreenPos(ctx)
        if ImGui.Selectable(ctx, "         " .. sw.label .. "##bstyle_" .. sw.key, sw.key == cur,
            KEEP_OPEN, 150, sh) then
          local l = materialise(fx)
          local lc = l.controls[idx]
          if lc then lc.style = sw.key end
          M.set(key, l); M.save()
        end
        SWI.draw(ctx, dl, sw.key, x + 2, y + 1, x + 34, y + sh - 1, true, lit, not C.EFFECT_3D, "ON", false,
          W.lit_col(c.cap))
      end
    end
  end
  ImGui.Spacing(ctx)
  -- a pill rocker doesn't light: its colour is its cap's (TS_CV_Switches)
  local body_col = c.style == "rocker"
  ImGui.TextDisabled(ctx, body_col and "Colour" or "Lit colour")
  for i, cp in ipairs(C.TOGGLE_COLS) do
    if i > 1 then ImGui.SameLine(ctx, 0, 4) end
    -- (a pill rocker with no colour of its own is black)
    local plain = body_col and cp.key == "theme"
    local col = cp.col or (plain and 0x26272bff) or C.COL.toggle_on
    if ImGui.ColorButton(ctx, cp.label .. "##tcol_" .. cp.key, col,
        ImGui.ColorEditFlags_NoTooltip, 18, 18) then
      set((cp.key ~= "theme") and cp.key or nil)
    end
    if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, plain and "Black" or cp.label) end
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
    swatch_extras("lit", c.cap, lit >> 8, body_col and "Rocker colour" or "Lit colour", choose, fx)
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
        ImGui.SetTooltip(ctx, (k == "small") and "Half height, name on the button.\nTwo stack in one cell."
          or "Normal size.")
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
  if c.type == "toggle" then new_look_items("toggle", c, "buttons") end
end

-- The finish of a control's background or a divider's section: a combo
-- that saves Finish<n>, or clears it when the choice is the one the
-- faceplate makes anyway (aluminium is brushed, an inset isn't).
local function brush_tick(fx, key, idx, c, kind, pl, id)
  local fin = M.part_finish(kind, pl, c.finish, c.brush) or "plain"
  local f_now = C.FINISH[fin] or C.FINISH.plain
  ST.caption(ctx, "Finish")
  ImGui.SetNextItemWidth(ctx, 120)
  if ImGui.BeginCombo(ctx, "##Finish" .. id, f_now.label) then
    local dflt = M.part_brushed(kind, pl, nil) and "brushed" or "plain"
    for _, f in ipairs(C.FINISHES) do
      if ImGui.Selectable(ctx, f.label .. "##" .. id .. "_" .. f.key, fin == f.key) and kind then
        local l = materialise(fx)
        local lc = l.controls[idx]
        if lc then
          lc.brush = nil
          lc.finish = (f.key ~= dflt) and f.key or nil
        end
        M.set(key, l); M.save()
      end
    end
    ImGui.EndCombo(ctx)
  end
  if ImGui.IsItemHovered(ctx, ImGui.HoveredFlags_AllowWhenDisabled) then
    ImGui.SetTooltip(ctx, kind and "The surface." or "Choose a background first.")
  end
  -- and/or a metallic flake (Metal<n>)
  local mt = M.part_metal(kind, c.metal)
  local mch, mv = ST.checkbox(ctx, "Metallic flake##" .. id .. "_m", mt)
  if mch and kind then
    local l = materialise(fx)
    local lc = l.controls[idx]
    if lc then lc.metal = mv or nil end
    M.set(key, l); M.save()
  end
  if ImGui.IsItemHovered(ctx, ImGui.HoveredFlags_AllowWhenDisabled) then
    ImGui.SetTooltip(ctx, kind and "Metallic flake over the finish."
      or "Choose a background first.")
  end
end

-- How round a background's or section's corners are (Corners<n>): the
-- usual slight rounding, soft, or round (fully round ends).
local CORNER_CHOICES = { { nil, "Square" }, { "soft", "Soft" }, { "round", "Round" } }
local function corners_combo(fx, key, idx, c, kind, id)
  local now = M.corners_of(c.corners)
  local label = "Square"
  for _, o in ipairs(CORNER_CHOICES) do if o[1] == now then label = o[2] end end
  ST.caption(ctx, "Corners")
  ImGui.SetNextItemWidth(ctx, 120)
  if ImGui.BeginCombo(ctx, "##Corners" .. id, label) then
    for _, o in ipairs(CORNER_CHOICES) do
      if ImGui.Selectable(ctx, o[2] .. "##" .. id .. "_" .. (o[1] or "square"), now == o[1]) and kind then
        local l = materialise(fx)
        local lc = l.controls[idx]
        if lc then lc.corners = o[1] end
        M.set(key, l); M.save()
      end
    end
    ImGui.EndCombo(ctx)
  end
  if ImGui.IsItemHovered(ctx, ImGui.HoveredFlags_AllowWhenDisabled) then
    ImGui.SetTooltip(ctx, kind and "Round: fully round ends (other shapes: soft)." or "Choose a background first.")
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
    if lc then lc.back = v; if not v then lc.brush, lc.metal, lc.finish, lc.corners = nil, nil, nil, nil end end
    M.set(key, l); M.save()
  end
  ImGui.TextDisabled(ctx, "Behind this control")
  if ImGui.Selectable(ctx, "None##back_none", now == "none", KEEP_OPEN, 170, 0) then set(nil) end
  if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "No background of its own.") end
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
      if lc then lc.back = k; if not k then lc.brush, lc.metal, lc.finish, lc.corners = nil, nil, nil, nil end end
      M.set(pk, l)
      if save then M.save() end
    end
    local now_pl = C.plate_of(c.back)
    custom_rows("back", c.back, 170, cset, "Background colour", now_pl and (now_pl.bg >> 8), fx)
  end
  ImGui.Separator(ctx)
  local bkind, bpl = P.back_style(c.back)
  ImGui.BeginDisabled(ctx, not bkind)
  brush_tick(fx, key, idx, c, bkind, bpl, "back_brush")
  corners_combo(fx, key, idx, c, bkind, "back_corners")
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
    if lc then lc.style, lc.cap = style, cap; if not style then lc.brush, lc.metal, lc.finish, lc.corners = nil, nil, nil, nil end end
    M.set(key, l); M.save()
  end
  ImGui.TextDisabled(ctx, c.type == "section" and "The section it's on" or "The controls after this divider")
  if ImGui.Selectable(ctx, "None##sec_none", now == "none", KEEP_OPEN, 170, 0) then set(nil, nil) end
  if ImGui.Selectable(ctx, "Inset##sec_inset", now == "inset", KEEP_OPEN, 170, 0) then set("inset", nil) end
  if ImGui.IsItemHovered(ctx) then
    ImGui.SetTooltip(ctx, "Recessed panel up to the next divider.")
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
        else lc.style, lc.cap, lc.brush, lc.metal, lc.finish, lc.corners = nil, nil, nil, nil, nil, nil end
      end
      M.set(pk, l)
      if save then M.save() end
    end
    local cur = (c.style == "plate") and c.cap or nil
    local now_pl = C.plate_of(cur)
    custom_rows("sec", cur, 170, sset, "Section colour", now_pl and (now_pl.bg >> 8), fx)
  end
  ImGui.Separator(ctx)
  local skind, spl = P.section_style(c)
  ImGui.BeginDisabled(ctx, not skind)
  brush_tick(fx, key, idx, c, skind, spl, "sec_brush")
  corners_combo(fx, key, idx, c, skind, "sec_corners")
  ImGui.EndDisabled(ctx)
end

-- An XY pad's or a concentric knob's look: the colour (the pad's dot, the
-- inner knob) and the size. Neither takes the knob styles.
local dual_style_grid     -- a concentric knob's styles, below
local function pad_style_menu(fx, key, idx, c)
  local dl = ImGui.GetWindowDrawList(ctx)
  local function set(fields)
    local l = materialise(fx)
    local lc = l.controls[idx]
    if lc then for k, v in pairs(fields) do lc[k] = v or nil end end
    M.set(key, l); M.save()
  end
  if c.type == "dual" then dual_style_grid(fx, key, idx, c) end
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
    swatch_extras("pcap", c.cap, now_col and (now_col >> 8), "Colour", choose, fx)
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
  if ImGui.MenuItem(ctx, "Reset to default", nil, false, c.cap ~= nil or c.size ~= nil
      or c.style ~= nil or c.look ~= nil or c.style2 ~= nil or c.look2 ~= nil) then
    set({ cap = false, size = false, style = false, look = false, style2 = false, look2 = false })
  end
end

-- A look built from parts onto knob idx, its section (the controls
-- between the dividers either side) or every knob on the panel; each
-- takes its own copy, and its colour from the look.
local function apply_look(fx, idx, look, scope)
  local l, pk = materialise(fx)
  local ctl = l.controls
  local function put(c)
    if c and (c.type == "knob" or c.type == "stepped") then c.look = KPm.copy(look); c.cap = nil end
  end
  if scope == "section" then
    local function edge(c) return c.type == "divider" or c.type == "page" end
    local a, b = idx, idx
    while a > 1 and not edge(ctl[a - 1]) do a = a - 1 end
    while b < #ctl and not edge(ctl[b + 1]) do b = b + 1 end
    for i = a, b do put(ctl[i]) end
  elseif scope == "panel" then
    for _, c in ipairs(ctl) do put(c) end
  else
    put(ctl[idx])
  end
  M.set(pk, l); M.save()
end

-- A concentric knob's pair of looks (outer, inner) onto knob idx, its
-- section or every concentric knob on the panel, the same way.
local function apply_dual(fx, idx, outer, inner, scope)
  local l, pk = materialise(fx)
  local ctl = l.controls
  local function put(c)
    if c and c.type == "dual" then
      c.look, c.look2, c.cap = KPm.copy(outer), KPm.copy(inner), nil
      if c.style == "arc" then c.style = nil end
    end
  end
  if scope == "section" then
    local function edge(c) return c.type == "divider" or c.type == "page" end
    local a, b = idx, idx
    while a > 1 and not edge(ctl[a - 1]) do a = a - 1 end
    while b < #ctl and not edge(ctl[b + 1]) do b = b + 1 end
    for i = a, b do put(ctl[i]) end
  elseif scope == "panel" then
    for _, c in ipairs(ctl) do put(c) end
  else
    put(ctl[idx])
  end
  M.set(pk, l); M.save()
end

-- A concentric knob's style: the default, the flat Arc, or any parts
-- recipe (or one of yours) for the outer knob, with another for the inner
-- one; Customise... builds both from parts. Thumbnails as the knobs'.
local DUAL_START = "console"      -- Customise... on the default starts here
dual_style_grid = function(fx, key, idx, c)
  local dl = ImGui.GetWindowDrawList(ctx)
  local function set(fields)
    local l = materialise(fx)
    local lc = l.controls[idx]
    if lc then for k, v in pairs(fields) do lc[k] = v or nil end end
    M.set(key, l); M.save()
  end
  local _, th = ImGui.CalcTextSize(ctx, "Ag")
  local COLS, CS = 6, 40
  local hov
  local cap = W.cap_col(c.cap)
  local keep = W.hw
  W.hw = C.EFFECT_3D and C.METAL_K or 0          -- the thumbnails as the panel draws them
  local function thumb(x, y, o)
    o.cap, o.ctx = o.cap or cap, ctx
    W.dual_face(dl, x + CS * 0.5, y + CS * 0.5, CS * 0.5 - 6, 0.35, 0.7, o)
  end
  local title_x, title_y = ImGui.GetCursorScreenPos(ctx)
  ImGui.Dummy(ctx, 10, th)
  local items = { { key = false, label = "Default" }, { key = "arc", label = "Arc (flat)" } }
  for _, st in ipairs(C.KNOB_STYLES) do
    if st.parts then items[#items + 1] = { key = st.key, label = st.label } end
  end
  local now_label = c.look and "Your own look" or "Default"
  for i, it in ipairs(items) do
    if (i - 1) % COLS ~= 0 then ImGui.SameLine(ctx, 0, 2) end
    local x, y = ImGui.GetCursorScreenPos(ctx)
    local on = not c.look and ((it.key or nil) == c.style)
    if on then now_label = it.label end
    if ImGui.Selectable(ctx, "##dstyle_" .. i, on, KEEP_OPEN, CS, CS) then
      set({ style = it.key, look = false })
    end
    if ImGui.IsItemHovered(ctx) then hov = it.label end
    thumb(x, y, { style = it.key or nil, style2 = c.style2, look2 = c.look2 })
  end
  local mine = RCP.list()
  if #mine > 0 then
    ImGui.Spacing(ctx)
    ImGui.TextDisabled(ctx, "Your recipes")
    for i, r in ipairs(mine) do
      if (i - 1) % COLS ~= 0 then ImGui.SameLine(ctx, 0, 2) end
      local x, y = ImGui.GetCursorScreenPos(ctx)
      if ImGui.Selectable(ctx, "##dmine_" .. i, false, KEEP_OPEN, CS, CS) then
        set({ look = KPm.copy(r.look), style = (c.style ~= "arc") and c.style or false })
      end
      if ImGui.IsItemHovered(ctx) then hov = r.name end
      thumb(x, y, { look = r.look, style2 = c.style2, look2 = c.look2 })
    end
  end
  -- the inner knob, once the outer is a recipe
  local outer, inner, odef, idef = W.dual_looks(c)
  if outer then
    ImGui.Spacing(ctx)
    ImGui.TextDisabled(ctx, "Inner knob")
    local n = 0
    local function cell()
      if n % COLS ~= 0 then ImGui.SameLine(ctx, 0, 2) end
      n = n + 1
      return ImGui.GetCursorScreenPos(ctx)
    end
    for _, st in ipairs(C.KNOB_STYLES) do
      if st.parts then
        local x, y = cell()
        local on = not c.look2 and (c.style2 or "softtouch") == st.key
        if ImGui.Selectable(ctx, "##dinner_" .. st.key, on, KEEP_OPEN, CS, CS) then
          set({ style2 = (st.key ~= "softtouch") and st.key or false, look2 = false })
        end
        if ImGui.IsItemHovered(ctx) then hov = "Inner: " .. st.label end
        thumb(x, y, { style = c.style, look = c.look, style2 = st.key })
      end
    end
    for i, r in ipairs(mine) do
      local x, y = cell()
      if ImGui.Selectable(ctx, "##dinmine_" .. i, false, KEEP_OPEN, CS, CS) then
        set({ look2 = KPm.copy(r.look), cap = false })
      end
      if ImGui.IsItemHovered(ctx) then hov = "Inner: " .. r.name end
      thumb(x, y, { style = c.style, look = c.look, look2 = r.look })
    end
  end
  W.hw = keep
  ImGui.Spacing(ctx)
  if ImGui.Selectable(ctx, "Customise...##dstyle_custom", false, 0, 150, 0) then
    local o_def = odef or C.KNOB_STYLE[DUAL_START]
    local start = KPm.copy(outer or o_def.parts)
    if not start.col then start.col = W.cap_col(o_def.cap) or 0x26282bff end
    local in_def = idef or C.KNOB_STYLE.softtouch
    local start2 = KPm.copy(inner or in_def.parts)
    start2.skirt, start2.washer, start2.nut = nil, nil, nil
    start2.col = cap or ((not c.look2) and W.cap_col(in_def.cap)) or start2.col or 0x3a3b3eff
    local lay = M.get(key)
    local pl = lay and C.plate_of(lay.plate)
    KE.open({ title = (fx.name or "") .. "  ·  " .. ((c.label and c.label ~= "") and c.label or "Concentric knob"),
              look = start, inner = start2,
              start = (not c.look) and (odef and c.style or DUAL_START) or nil,
              start2 = (not c.look2) and (idef and idef.key) or nil,
              plate = pl and pl.bg or nil,
              apply = function(o, scope, i) apply_dual(fx, idx, o, i, scope) end })
  end
  if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "Build both knobs from parts.") end
  ImGui.DrawList_AddText(dl, title_x, title_y, C.COL.header_dim or 0x9a9a9aff, "Style: " .. (hov or now_label))
  ImGui.Spacing(ctx)
  ImGui.Separator(ctx)
end

-- A dropdown's look: printed flat on the faceplate, or raised (a backlit
-- button's cap, unlit, standing off it). A button row's lit styles count
-- as raised on a dropdown (W.combo_raised).
local function combo_style_menu(fx, key, idx, c)
  local dl = ImGui.GetWindowDrawList(ctx)
  local raised = W.combo_raised(c.style)
  local function set(v)
    local l = materialise(fx)
    local lc = l.controls[idx]
    if lc then lc.style = v end
    M.set(key, l); M.save()
  end
  ImGui.TextDisabled(ctx, "Style")
  local _, th = ImGui.CalcTextSize(ctx, "Ag")
  local rh = math.max(th, 20)
  for _, o in ipairs({ { false, "Flat", "Printed on the faceplate." },
                       { true, "Raised", "A backlit button's cap, unlit, standing off the faceplate." } }) do
    local x, y = ImGui.GetCursorScreenPos(ctx)
    if ImGui.Selectable(ctx, "            " .. o[2] .. "##cstyle_" .. o[2], raised == o[1], KEEP_OPEN, 160, rh) then
      set(o[1] and "raised" or nil)
    end
    if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, o[3]) end
    W.combo_swatch(dl, x + 3, y + 3, x + 41, y + rh - 3, o[1])
  end
  ImGui.Spacing(ctx)
  ImGui.Separator(ctx)
  if ImGui.MenuItem(ctx, "Apply to every dropdown on this panel") then
    local l = materialise(fx)
    for _, o in ipairs(l.controls) do
      if o.type == "combo" and not o.buttons then o.style = raised and "raised" or nil end
    end
    M.set(key, l); M.save()
  end
end

local function style_menu(fx, key, idx, c)
  if c.type == "xy" or c.type == "dual" then return pad_style_menu(fx, key, idx, c) end
  if c.type == "combo" and not c.buttons then return combo_style_menu(fx, key, idx, c) end
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

  if fam == "knob" then
    -- the knobs as a grid of thumbnails, each in this knob's colour; the
    -- name of the one under the pointer (or the chosen one) above them
    local now_def = (not c.look) and C.KNOB_STYLE[cur] or nil
    local hov_label
    local title_x, title_y = ImGui.GetCursorScreenPos(ctx)
    ImGui.Dummy(ctx, 10, th)
    local COLS, CS = 6, 40
    for i, st in ipairs(list) do
      if (i - 1) % COLS ~= 0 then ImGui.SameLine(ctx, 0, 2) end
      local x, y = ImGui.GetCursorScreenPos(ctx)
      if ImGui.Selectable(ctx, "##style_" .. st.key, st.key == cur and not c.look, KEEP_OPEN, CS, CS) then
        set({ style = (st.key ~= list[1].key) and st.key or false, look = false })
      end
      if ImGui.IsItemHovered(ctx) then hov_label = st.label end
      local r = CS * 0.5 - 6     -- the scale ticks sit outside this
      W.knob_face(dl, x + CS * 0.5, y + CS * 0.5, r, 0.62,
        { style = st.key, cap = W.cap_col(c.cap), ctx = ctx })
    end
    -- your recipes: looks you've saved from Customise...
    local mine = RCP.list()
    if #mine > 0 then
      ImGui.Spacing(ctx)
      ImGui.TextDisabled(ctx, "Your recipes")
      for i, r in ipairs(mine) do
        if (i - 1) % COLS ~= 0 then ImGui.SameLine(ctx, 0, 2) end
        local x, y = ImGui.GetCursorScreenPos(ctx)
        if ImGui.Selectable(ctx, "##myrecipe_" .. i, false, KEEP_OPEN, CS, CS) then
          set({ look = KPm.copy(r.look), cap = false })
        end
        if ImGui.IsItemHovered(ctx) then hov_label = r.name end
        W.knob_face(dl, x + CS * 0.5, y + CS * 0.5, CS * 0.5 - 6, 0.62, { look = r.look, ctx = ctx })
      end
    end
    ImGui.Spacing(ctx)
    if ImGui.Selectable(ctx, "Customise...##style_custom", false, 0, 150, 0) then
      local def = C.KNOB_STYLE[cur]
      local start = c.look and KPm.copy(c.look) or (def and def.parts and KPm.copy(def.parts)) or {}
      if not c.look then start.col = W.cap_col(c.cap) or (def and W.cap_col(def.cap)) or start.col or 0x26282bff
      elseif c.cap then start.col = W.cap_col(c.cap) end
      local lay = M.get(key)
      local pl = lay and C.plate_of(lay.plate)
      KE.open({ title = (fx.name or "") .. "  ·  " .. ((c.label and c.label ~= "") and c.label or "Knob"),
                look = start, start = (not c.look and def and def.parts) and cur or nil,
                plate = pl and pl.bg or nil,
                apply = function(look, scope) apply_look(fx, idx, look, scope) end })
    end
    if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "Build this knob from parts.") end
    ImGui.DrawList_AddText(dl, title_x, title_y, C.COL.header_dim or 0x9a9a9aff,
      "Style: " .. (hov_label or (now_def and now_def.label) or (c.look and "Your own look") or ""))
  else
    ImGui.TextDisabled(ctx, "Style")
    for _, st in ipairs(list) do
      if ImGui.Selectable(ctx, st.label .. "##style_" .. st.key, st.key == cur, KEEP_OPEN, 150, row_h) then
        set({ style = (st.key ~= list[1].key) and st.key or false })
      end
    end
  end

  -- a fader's shape: which way it runs, how long, how thick (Shape<n>).
  -- Full length and a full column is the standard fader.
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
      ImGui.SetTooltip(ctx, "Half: half-width, for faders side by side.")
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
      (fam == "fader") and "Fader cap colour" or "Knob colour", choose, fx)
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
        ImGui.SetTooltip(ctx, (k == "small") and "Half height, value in the tooltip.\nTwo stack in one cell."
          or (k == "large") and "One and a half times the size.\nNormal size in a one-row panel."
          or "Normal size.")
      end
    end

    -- a value arc in place of the scale's ticks or dots (on an Arc knob,
    -- the way its own arc fills): from the start, from the end, or out
    -- from the middle; for this knob, its section or the whole panel.
    -- Centred also makes the knob centred (c.bipolar): an Arc or LED ring
    -- face fills from the middle, and a modulator swings it both ways. An
    -- Arc or LED ring knob that's centred without an arc reads as Centred.
    ImGui.Spacing(ctx)
    ImGui.TextDisabled(ctx, "Value arc")
    local ARCS = { { false, "Off", "The knob's own scale ticks or dots." },
                   { "pos", "Positive", "Lit from the start of the travel up to the value." },
                   { "neg", "Negative", "Lit from the end of the travel back to the value." },
                   { "mid", "Centred", "Lit out from the middle to the value.\n" ..
                                       "A modulator swings it both ways round its setting." } }
    local own_face = not c.look and (cur == "arc" or cur == "led")
    local arc_now = c.arc or ((c.bipolar and own_face) and "mid") or false
    for i, a in ipairs(ARCS) do
      if i > 1 then ImGui.SameLine(ctx, 0, 4) end
      if ImGui.Selectable(ctx, a[2] .. "##varc_" .. i, arc_now == a[1], KEEP_OPEN, 64, 0) then
        set({ arc = a[1], bipolar = (a[1] == "mid") })
      end
      if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, a[3]) end
    end
    local function arc_to(scope)
      local l, pk = materialise(fx)
      local ctl = l.controls
      local function put(o)
        if o and (o.type == "knob" or o.type == "stepped") then o.arc, o.bipolar, o.arcc = c.arc, c.bipolar, c.arcc end
      end
      if scope == "section" then
        local function edge(o) return o.type == "divider" or o.type == "page" end
        local a, b = idx, idx
        while a > 1 and not edge(ctl[a - 1]) do a = a - 1 end
        while b < #ctl and not edge(ctl[b + 1]) do b = b + 1 end
        for i = a, b do put(ctl[i]) end
      else
        for _, o in ipairs(ctl) do put(o) end
      end
      M.set(pk, l); M.save()
    end
    -- its colour: the theme's fill unless one is picked (an Arc or LED
    -- ring knob's own arc is its Colour, above)
    if arc_now and not own_face then
      ImGui.Spacing(ctx)
      ImGui.TextDisabled(ctx, "Arc colour")
      local arc_cur = c.arcc or "accent"
      for i, cp in ipairs(C.CAPS) do
        if i > 1 then ImGui.SameLine(ctx, 0, 4) end
        local col = cp.col or ((arc_now == "mid") and C.COL.knob_fill_bi or C.COL.knob_fill)
        if ImGui.ColorButton(ctx, cp.label .. "##arcc_" .. cp.key, col, ImGui.ColorEditFlags_NoTooltip, 18, 18) then
          set({ arcc = (cp.key ~= "accent") and cp.key or false })
        end
        if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, (cp.key == "accent") and "Theme" or cp.label) end
        if cp.key == arc_cur then
          local x0, y0 = ImGui.GetItemRectMin(ctx)
          local x1, y1 = ImGui.GetItemRectMax(ctx)
          ImGui.DrawList_AddRect(dl, x0 - 2, y0 - 2, x1 + 2, y1 + 2, C.COL.header_text, 3.0, 0, 1.5)
        end
      end
      local function choose_arc(k, save)
        local l, pk = materialise(fx)
        local lc = l.controls[idx]
        if lc then lc.arcc = k end
        M.set(pk, l)
        if save then M.save() end
      end
      local now_ac = W.cap_col(c.arcc) or C.COL.knob_fill
      swatch_extras("arcc", c.arcc, now_ac >> 8, "Arc colour", choose_arc, fx)
    end
    if ImGui.Selectable(ctx, "The same for its section##varc_sec", false, KEEP_OPEN, 160, 0) then arc_to("section") end
    ImGui.SameLine(ctx, 0, 4)
    if ImGui.Selectable(ctx, "For the whole panel##varc_all", false, KEEP_OPEN, 140, 0) then arc_to("panel") end

    -- the numbers round the dial are chosen under Values; their colour
    -- is a look, so it's here
    ImGui.Spacing(ctx)
    local sc_now = M.scale_kind(c) or "none"
    local rv, on = ST.checkbox(ctx, "Numbers in cap colour##scale_ink", c.scale_ink == "cap", { dim = sc_now == "none" })
    if rv then set({ scale_ink = on and "cap" or false }) end
    if ImGui.IsItemHovered(ctx) then
      ImGui.SetTooltip(ctx, "Dial numbers in the knob's colour, not the faceplate's.")
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
          if fam == "knob" then o.scale_ink, o.arc, o.bipolar, o.arcc = src.scale_ink, src.arc, src.bipolar, src.arcc end
          if fam == "fader" then o.dir, o.len, o.thin = src.dir, src.len, src.thin end
        end
      end
    end
    M.set(key, l); M.save()
  end
  if fam == "knob" then new_look_items("knob", c, "knobs") end
  if ImGui.MenuItem(ctx, "Reset to default", nil, false, c.style ~= nil or c.cap ~= nil or c.scale_ink ~= nil
                     or c.arc ~= nil) then
    set({ style = false, cap = false, scale_ink = false, arc = false })
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
      ": nothing before it to route beside.")
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

-- The containers above a container, outermost first: read off the first
-- panel inside it, whose own list runs down through this one. (An empty
-- container's stand-in panel lists only the ones around it.)
local function box_ancestors(node)
  local f = app.chain[node.first]
  local out = {}
  for _, a in ipairs((f and f.ancestors) or {}) do
    if a.guid == node.guid then break end
    out[#out + 1] = a
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
    local ch, nv = ST.slider_double(ctx, "Wet##boxwet", wv * 100, 0, 100, "%.0f%%")
    if ch then reaper.TrackFX_SetParam(tr, node.addr, wet, nv / 100) end
  end
  parallel_menu(node.addr, node.parallel, node.index, "container")
  do
    -- the container's own setting: everything inside it, oversampled
    local st = T.os_state(tr, { addr = node.addr, ancestors = box_ancestors(node) })
    if ImGui.BeginMenu(ctx, "Oversample everything in it" .. (st.lit and ("  (" .. st.lit .. "x)") or "")) then
      P.os_choices(ctx, tr, node.addr, st, "container")
      ImGui.EndMenu(ctx)
    end
  end
  ImGui.Separator(ctx)

  local inside = panels_in(node)
  if ImGui.MenuItem(ctx, "Collapse everything in it", nil, false, #inside > 0) then
    for _, f in ipairs(inside) do set_fold(f, true) end
  end
  if ImGui.MenuItem(ctx, "Expand everything in it", nil, false, #inside > 0) then
    for _, f in ipairs(inside) do set_fold(f, false) end
  end
  -- its own panel (the controls put on it) standing for everything in it
  do
    local has = CT.shown[node.guid] and #CT.shown[node.guid] > 0
    local folded = has and CT.folded(node.guid)
    if ImGui.MenuItem(ctx, folded and "Unfold: show what's in it" or "Fold to its panel", nil, false, has and true or false) then
      CT.set_folded(node.guid, not folded)
      rescan(true)
    end
    if ImGui.IsItemHovered(ctx, ImGui.HoveredFlags_AllowWhenDisabled) then
      ImGui.SetTooltip(ctx, has and (folded and "Bring its plugins back into the row." or
        "Show only the container's own panel: the controls put on it.") or
        "Put a control on it first (a control's right-click \u{25B8} On its container).")
    end
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
  if ImGui.MenuItem(ctx, "Duplicate") then
    reaper.Undo_BeginBlock()
    reaper.PreventUIRefresh(1)
    T.duplicate(tr, node.path)
    reaper.PreventUIRefresh(-1)
    reaper.Undo_EndBlock("ChannelView: duplicate container", -1)
    rescan(true)
    ImGui.CloseCurrentPopup(ctx)
  end
  if ImGui.IsItemHovered(ctx) then
    ImGui.SetTooltip(ctx, "Copy the container and its contents, right after it.")
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
    ImGui.SetTooltip(ctx, "Move the contents out and remove the container.")
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

-- popped-out panels: see POP.window
POP.views, POP.rects, POP.place, POP.LABEL_H, POP.PAD = {}, {}, nil, 16, 3
POP.SCOPED = { "track", "chain", "menu_fx", "open_panel_menu", "ctl_menu", "open_ctl_menu",
                 "remove_ask", "drag", "fxren_for", "fxren_buf", "rename_buf", "label_buf",
                 "rng_for", "rng", "state_buf", "popout" }

function POP.scope(view, track, fn)
  local saved = {}
  for _, k in ipairs(POP.SCOPED) do saved[k] = app[k]; app[k] = view[k] end
  app.track, app.popout = track, view
  -- folded on its own, apart from ChannelView's
  local was_c, was_f, was_v, was_a = St.COLLAPSED, St.FOLD, St.VARIANT, St.VARIANT_ALSO
  St.COLLAPSED, St.FOLD = "pcollapsed:", "pfold:"
  -- its own layout picked, else the one of the view it's laid out like:
  -- ChannelView's side by side, the rack's stacked down (then ChannelView's)
  St.VARIANT = "pvariant:"
  St.VARIANT_ALSO = view.down and { "rvariant:" } or { "variant:" }
  if view.down then POP.rack_mode(true) end
  local ok, err = xpcall(fn, debug.traceback)
  if view.down then POP.rack_mode(false) end
  St.COLLAPSED, St.FOLD, St.VARIANT, St.VARIANT_ALSO = was_c, was_f, was_v, was_a
  for _, k in ipairs(POP.SCOPED) do view[k] = app[k]; app[k] = saved[k] end
  view.popout, view.track = nil, nil
  if not ok then error(err, 0) end
end

-- A window of panels stacked down draws them as the Rack view does: each
-- as wide as the window, as tall as it needs, the rack's defaults.
function POP.rack_mode(on)
  if on then
    POP.was = { P.RACK, M.VIEW_DEFAULTS, W.CHEVRONS_UPDOWN }
    P.RACK, M.VIEW_DEFAULTS, W.CHEVRONS_UPDOWN = true, M.RACK_DEFAULTS_SECT, true
  elseif POP.was then
    P.RACK, M.VIEW_DEFAULTS, W.CHEVRONS_UPDOWN = table.unpack(POP.was, 1, 3)
    POP.was = nil
  end
end

-- Pops the plugin `fx` on `track` out: into window `into`, or a window of
-- its own (named after it) at `at` = { x, y } when given.
function POP.pop_out(track, fx, into, at)
  if not POP.PO or not track or not fx or fx.guid == "" then return end
  local w = into and POP.PO.window(into)
  if not w then
    w = POP.PO.new_window(U.fx_label(fx))
    if at then POP.place = { id = w.id, x = at[1], y = at[2] } end
  end
  POP.PO.add(w.id, reaper.GetTrackGUID(track), fx.guid)
end

-- The window a screen point is over, or nil.
function POP.at(x, y)
  for id, r in pairs(POP.rects) do
    if x >= r[1] and x < r[1] + r[3] and y >= r[2] and y < r[2] + r[4] then return id end
  end
  return nil
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
    ImGui.SetTooltip(ctx, "Rename this instance (layout unchanged).\nClear to restore the plugin's name.")
  end
  ImGui.SameLine(ctx)
  if ImGui.Button(ctx, "Rename##fxren") or ren_enter then
    T.rename(app.track, fx.addr, fx.guid, U.trim(app.fxren_buf))
    app.fxren_for = nil
    rescan(true)
    ImGui.CloseCurrentPopup(ctx)
  end
  -- REAPER's own wet for the plugin: the header shows it where there's
  -- room, and here it works at any panel width
  do
    local wet = reaper.TrackFX_GetParamFromIdent and reaper.TrackFX_GetParamFromIdent(app.track, fx.addr, ":wet")
    if wet and wet >= 0 then
      local wv = reaper.TrackFX_GetParam(app.track, fx.addr, wet) or 1
      ImGui.SetNextItemWidth(ctx, 150)
      local ch, nv = ST.slider_double(ctx, "Wet##fxwet", wv * 100, 0, 100, "%.0f%%")
      if ch then reaper.TrackFX_SetParam(app.track, fx.addr, wet, nv / 100) end
      if ImGui.IsItemHovered(ctx) then
        ImGui.SetTooltip(ctx, "Wet/dry mix.\nCtrl+click: type a value.")
      end
    end
  end

  -- a locked layout takes no edits (the padlock in the panel's foot);
  -- its meters can still be switched on and off
  local locked = M.locked(layout) ~= nil
  local function locked_tip()
    if locked and ImGui.IsItemHovered(ctx, ImGui.HoveredFlags_AllowWhenDisabled) then
      ImGui.SetTooltip(ctx, "Layout locked: unlock with the padlock\nin the panel's foot.")
    end
  end
  ------------------------------------------------------------- LAYOUT
  ImGui.SeparatorText(ctx, "Layout")
  -- Layout variants: another layout for the same plugin, picked per
  -- instance (TS_CV_Mappings "<plugin> :: <name>", St.variant). Not for
  -- REAPER's plugins with a panel of ChannelView's (ReaEQ, ReaComp,
  -- ReaGate, ReaLimit, ReaDelay, ReaVerbate): that's their Standard, and
  -- other layouts of theirs are normal ones, with or without a canvas.
  do
    local base, shown = M.split_variant(key)
    local dflt = M.default_variant(base)
    local function mark(nm) return (nm == dflt) and "  (default)" or "" end
    -- a layout switching rule in charge: the one shown is its, the ticks
    -- are the instance's own pick (shown again once no rule matches)
    local rule = St.switch_rule(fx.guid)
    local _, cur = M.split_variant(rule and St.chosen_key(fx.name, fx.guid) or key)
    local title = "Layout: " .. (shown and U.truncate(shown, 20) or "Standard") .. (rule and "  \u{00B7} auto" or "")
    if ED.menu(ImGui, ctx, ED.PRO and (title .. "###fxlayout") or "Other layouts") then
      local rules = M.switch_rules(base)
      if rules then
        local r = rules[rule or 0]
        local function pname(p)
          local _, pn = reaper.TrackFX_GetParamName(app.track, fx.addr, p, "")
          return M.display_name(base, p, nil, pn, false)
        end
        local function fmt(p, n)
          local ok_, sv = reaper.TrackFX_FormatParamValueNormalized(app.track, fx.addr, p, n, "")
          return ok_ and U.trim(sv or "") or nil
        end
        local function vfind(nm)
          local _, vc = M.vstart(base, nm, layout.controls)
          return vc
        end
        local said = r and M.rule_text(r, pname, fmt, vfind)
        ImGui.TextDisabled(ctx, said and ("Rule %d is in charge: %s"):format(rule, U.truncate(said, 60))
          or ("%d switching rule%s, none in charge"):format(#rules, #rules == 1 and "" or "s"))
        ImGui.TextDisabled(ctx, "(set them in Edit Parameters)")
        ImGui.Separator(ctx)
      end
      if ImGui.MenuItem(ctx, "Standard" .. mark(nil) .. "##varown", nil, cur == nil) then
        St.set_variant(fx.guid, St.OWN)
      end
      if ImGui.IsItemHovered(ctx) then
        ImGui.SetTooltip(ctx, "The plugin's standard layout.")
      end
      for _, nm in ipairs(M.variants(base)) do
        if ImGui.MenuItem(ctx, nm .. mark(nm) .. "##var", nil, cur == nm) then St.set_variant(fx.guid, nm) end
      end
      -- which one new instances (and any not set to another) use
      if cur ~= dflt then
        if ImGui.MenuItem(ctx, "Make \"" .. U.truncate(cur or "Standard", 20) .. "\" the "
            .. (P.RACK and "rack's default" or "default")) then
          M.set_default_variant(base, cur); M.save()
        end
        if ImGui.IsItemHovered(ctx) then
          ImGui.SetTooltip(ctx, P.RACK
            and "Used in the Rack view by new instances and any not set to another layout there."
            or "Used by new instances and any not set to another layout.")
        end
      end
      ImGui.Separator(ctx)
      ImGui.SetNextItemWidth(ctx, 190)
      -- (not EnterReturnsTrue: with it ImGui only hands the text back on
      -- Enter, so the buttons would always see an empty name)
      local _, txt = ImGui.InputTextWithHint(ctx, "##newvar", "new layout's name", app.var_name or "")
      local ch = ImGui.IsItemDeactivated(ctx) and (ImGui.IsKeyPressed(ctx, ImGui.Key_Enter)
                 or ImGui.IsKeyPressed(ctx, ImGui.Key_KeypadEnter))
      app.var_name = txt
      local ok = M.clean_variant(txt) ~= nil and not M.has(M.variant_key(base, M.clean_variant(txt) or ""))
      local function make(empty)
        -- copied from a panel of ChannelView's (TS_CV_ReaFX): the plugin's
        -- controls, as a normal layout
        local from = layout
        if not shown and require("TS_CV_ReaFX").has_panel(key) then from = M.build_default(app.track, fx.addr) end
        local _, nm = M.new_variant(base, txt, from, empty)
        if nm then St.set_variant(fx.guid, nm); app.var_name = nil; ImGui.CloseCurrentPopup(ctx) end
      end
      if ch and ok then make(false) end
      if not ok then ImGui.BeginDisabled(ctx, true) end
      if ImGui.Button(ctx, "Copy to new layout") then make(false) end
      if ImGui.IsItemHovered(ctx, ImGui.HoveredFlags_AllowWhenDisabled) then
        ImGui.SetTooltip(ctx, "Copy this layout under the name above.\nEnter does the same.")
      end
      ImGui.SameLine(ctx)
      if ImGui.Button(ctx, "New empty layout") then make(true) end
      if ImGui.IsItemHovered(ctx, ImGui.HoveredFlags_AllowWhenDisabled) then
        ImGui.SetTooltip(ctx, "Empty layout under the name above.\nParameter names carry over.")
      end
      if not ok then ImGui.EndDisabled(ctx) end
      -- an EQ or compressor canvas for any plugin (TS_CV_CanvasSetup):
      -- the name above, or "EQ" / "Compressor" (numbered if taken)
      local function make_canvas(kind)
        local nm = M.clean_variant(txt)
        if not nm or M.has(M.variant_key(base, nm)) then
          local stem = M.CANVAS_NAMES[kind] or "Compressor"
          nm = stem
          local i = 2
          while M.has(M.variant_key(base, nm)) do nm = stem .. " " .. i; i = i + 1 end
        end
        local made = CS.create(app.track, fx, base, nm, kind, layout)
        if made then St.set_variant(fx.guid, made); app.var_name = nil; ImGui.CloseCurrentPopup(ctx) end
      end
      -- a canvas of its kind (EQ, compressor, gate, limiter, de-esser,
      -- delay, reverb, envelope, modulation): TS_CV_CanvasSetup
      if ImGui.BeginMenu(ctx, "New canvas layout") then
        for _, k in ipairs(M.CANVAS_ORDER) do
          if ImGui.MenuItem(ctx, M.CANVAS_NAMES[k] .. "\u{2026}") then make_canvas(k) end
          if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, CS.TIPS[k] or "") end
        end
        ImGui.EndMenu(ctx)
      end
      do
        local cl = M.get(key)
        if cl and cl.canvas and ImGui.MenuItem(ctx, "Set up this layout\u{2026}") then
          CS.open(app.track, fx, key)
        end
      end
      if cur then
        ImGui.Separator(ctx)
        if ImGui.MenuItem(ctx, "Delete layout \"" .. U.truncate(cur, 20) .. "\"\u{2026}") then
          if reaper.MB(("Delete the layout \"%s\"?\n\nEvery instance using it goes back to " ..
              "the plugin's default layout. The library as it was before is kept as\n" ..
              "TS_ChannelView_Mappings.bak.ini, until the next save."):format(cur), "ChannelView", 1) == 1 then
            if dflt == cur then M.set_default_variant(base, nil) end
            M.remove(key); M.save()
            St.set_variant(fx.guid, nil)
          end
        end
      end
      ImGui.EndMenu(ctx)
    end
  end
  -- Standard's editor is Edit parameters; Pro's the grid editor (but for
  -- a panel of its own: ReaEQ's, ReaComp's, the Trimmer's)
  local own_panel = P.own_eq(key) or P.own_rc(key) or P.own_trim(key)
  if not ED.PRO or own_panel then
    if ImGui.MenuItem(ctx, "Edit parameters\u{2026}", nil, false, not locked) then
      E.open(app.track, fx, key, layout)
    end
    locked_tip()
  end
  -- the grid editor (TS_CV_GridEditor): the layout as a grid, live
  -- (a canvas layout's: the controls beside the canvas)
  if not own_panel then
    if ED.item(ImGui, ctx, "Edit layout\u{2026}") then
      require("TS_CV_GridEditor").open(app.track, fx, key, layout, nil,
        { rows = M.locked(layout) or (P.RACK and P.RACK_ROWS) or app.cv_rows or 2, index = app.menu_fx, cv_h = app.cv_h,
          rack_w = app.rack_w or tonumber(reaper.GetExtState(C.EXT_SECT, "rack_width")) })
    end
    if ED.PRO and ImGui.IsItemHovered(ctx) then
      ImGui.SetTooltip(ctx, "The layout as a grid: drag parameters onto it, move and resize them.")
    end
  end
  if ED.menu(ImGui, ctx, "Faceplate", not locked) then
    plate_menu(fx, key, layout)
    ImGui.EndMenu(ctx)
  end
  locked_tip()
  if ImGui.BeginMenu(ctx, "Meters") then
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
          "Estimate gain reduction from audio in vs out.\nNeeds a TS_TrackProbe pair on the track.")
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
          "Input, output and level-change meters.\nNeeds a TS_TrackProbe pair on the track.")
      end
    end
    ImGui.EndMenu(ctx)
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
  if ImGui.BeginMenu(ctx, "Reset layout", not locked) then
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
    ImGui.EndMenu(ctx)
  end
  locked_tip()
  ------------------------------------------------------------- PLUGIN
  ImGui.SeparatorText(ctx, "Plugin")
  if ImGui.MenuItem(ctx, St.is_collapsed(fx.guid) and "Expand" or "Collapse to a bar") then
    toggle_fold(fx)
  end
  if ImGui.MenuItem(ctx, "Open the plugin's window") then
    reaper.TrackFX_Show(app.track, fx.addr, 3)
  end
  if ImGui.MenuItem(ctx, "Show in the FX chain") then
    reaper.TrackFX_Show(app.track, fx.addr, 1)
  end
  do
    -- its picture, for the hover previews (TS_CV_Thumbs, Pro)
    local th = not (fx.container_panel or fx.is_container) and W.thumbs()
    if th and ImGui.BeginMenu(ctx, "Picture") then
      local key = th.key_of_fx(app.track, fx.addr)
      local has = key and th.has(key)
      if th.can_capture() and ImGui.MenuItem(ctx, has and "Take it again" or "Take it now") then
        th.retake(app.track, fx.addr)
      end
      if ImGui.IsItemHovered(ctx) then
        ImGui.SetTooltip(ctx, "From its window, once it's open\nwith nothing over it.")
      end
      if ImGui.MenuItem(ctx, "From a file\u{2026}", nil, false, key ~= nil) then th.from_file(key) end
      if ImGui.MenuItem(ctx, "Remove", nil, false, has) then th.remove(key) end
      ImGui.EndMenu(ctx)
    end
  end
  -- a copy of the panel in a window of its own (TS_CV_PopOut, Pro)
  if POP.PO and not app.popout and not (fx.container_panel or fx.is_container) and ImGui.BeginMenu(ctx, "Pop out") then
    if ImGui.MenuItem(ctx, "In a window of its own") then POP.pop_out(app.track, fx) end
    local inside = POP.PO.windows_with(fx.guid)
    local ws = POP.PO.windows()
    if #ws > 0 then ImGui.Separator(ctx) end
    for _, w in ipairs(ws) do
      if ImGui.MenuItem(ctx, "Into \u{201C}" .. U.truncate(w.name, 24) .. "\u{201D}##po" .. w.id, nil, inside[w.id], not inside[w.id]) then
        POP.pop_out(app.track, fx, w.id)
      end
    end
    ImGui.EndMenu(ctx)
  end
  if POP.PO and not app.popout and ImGui.IsItemHovered(ctx) and not (fx.container_panel or fx.is_container) then
    ImGui.SetTooltip(ctx, "A copy of this panel, floating or docked.\nOr drag its header out of ChannelView.")
  end
  do
    local st = T.os_state(app.track, fx)
    if ImGui.BeginMenu(ctx, "Oversampling" .. (st.lit and ("  (" .. st.lit .. "x)") or "")) then
      P.os_choices(ctx, app.track, fx.addr, st, "plugin")
      ImGui.EndMenu(ctx)
    end
  end
  do
    -- offline: unloaded, not just bypassed (the panel turns steel blue)
    local off = T.get_offline(app.track, fx.addr)
    if ImGui.MenuItem(ctx, off and "Bring online" or "Set offline") then
      T.set_offline(app.track, fx.addr, not off, U.fx_label(fx))
    end
    if ImGui.IsItemHovered(ctx) then
      ImGui.SetTooltip(ctx, off and "Reload the plugin, as it was."
        or "Unload the plugin to free CPU and memory.\nSettings are kept.")
    end
  end
  do
    -- a plugin with sidechain inputs in a container that doesn't pass 3/4
    if #T.sidechain_gap(app.track, fx) > 0 then
      if ImGui.MenuItem(ctx, "Pass the sidechain into its container") then
        T.pass_sidechain(app.track, fx)
      end
      if ImGui.IsItemHovered(ctx) then
        ImGui.SetTooltip(ctx, "Widen the container to pass channels 3/4,\nso the track's sidechain reaches this plugin.")
      end
    end
  end
  -------------------------------------------------------------- CHAIN
  if app.popout then
    -- a popped-out panel: its place in its window
    local id, k = app.popout.win, app.menu_fx
    local w = POP.PO.window(id)
    ImGui.SeparatorText(ctx, "Popped out")
    if ImGui.MenuItem(ctx, "Move left", nil, false, k > 1) then POP.PO.nudge(id, k, -1) end
    if ImGui.MenuItem(ctx, "Move right", nil, false, w and k < #w.panels) then POP.PO.nudge(id, k, 1) end
    if ImGui.BeginMenu(ctx, "Move to") then
      if ImGui.MenuItem(ctx, "A window of its own") then POP.PO.move(id, k, nil, U.fx_label(fx)) end
      for _, o in ipairs(POP.PO.windows()) do
        if o.id ~= id and ImGui.MenuItem(ctx, "\u{201C}" .. U.truncate(o.name, 24) .. "\u{201D}##pomv" .. o.id) then
          POP.PO.move(id, k, o.id)
        end
      end
      ImGui.EndMenu(ctx)
    end
    if ImGui.MenuItem(ctx, "Take it out of this window") then POP.PO.take_out(id, k) end
    if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "The plugin stays on its track.") end
    if w and ImGui.BeginMenu(ctx, "Window: " .. U.truncate(w.name, 20)) then
      POP.menu(w)
      ImGui.EndMenu(ctx)
    end
  else
  ImGui.SeparatorText(ctx, "Chain")
  if ImGui.MenuItem(ctx, "Move left", nil, false, fx.index > 0) then
    nudge(fx.path_t, -1)
  end
  if ImGui.MenuItem(ctx, "Move right", nil, false, fx.index < fx.siblings - 1) then
    nudge(fx.path_t, 1)
  end
  parallel_menu(fx.addr, fx.parallel, fx.index, "plugin")
  if ImGui.MenuItem(ctx, "Duplicate") then
    reaper.Undo_BeginBlock()
    reaper.PreventUIRefresh(1)
    T.duplicate(app.track, fx.path_t)
    reaper.PreventUIRefresh(-1)
    reaper.Undo_EndBlock("ChannelView: duplicate " .. U.fx_label(fx), -1)
    rescan(true)
  end
  if ImGui.IsItemHovered(ctx) then
    ImGui.SetTooltip(ctx, "Copy with settings, right after it.")
  end
  if ImGui.MenuItem(ctx, "Insert plugin before\u{2026}") then
    B.open_menu(insert_target(fx, false))
  end
  if ImGui.MenuItem(ctx, "Insert plugin after\u{2026}") then
    B.open_menu(insert_target(fx, true))
  end
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
    -- a container's own panel: its own menu
    if fx.container_panel then
      box = nil
      for _, b in ipairs(app.brackets or {}) do
        if b.kind == "container" and b.node.guid == fx.guid then box = b.node break end
      end
    end
    if box and ImGui.BeginMenu(ctx, "Container: " .. U.truncate(box_label(box), 24)) then
      box_menu_items(box)
      ImGui.EndMenu(ctx)
    end
  end
  end
  ImGui.Separator(ctx)
  if ImGui.MenuItem(ctx, fx.container_panel and "Remove container and everything in it"
                        or fx.is_container and "Remove container" or "Remove plugin from the chain") then
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
    parts[#parts + 1] = label_of(C.BUTTON_STYLES, s.style) or label_of(C.SWITCH_STYLES, s.style) or "Flat"
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
  -- (Standard: copy and paste are Pro's)
  if not ED.PRO and not locked then ED.menu(ImGui, ctx, "Copy / paste style") return end
  if ImGui.MenuItem(ctx, "Copy style") then
    app.style_clip = { look = M.look_of(c) }
  end
  if ImGui.IsItemHovered(ctx) then
    ImGui.SetTooltip(ctx, "Copy its whole look to paste onto other controls.")
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
  -- several picked in Edit layout (this plugin, this layout): on all of them
  local picked = require("TS_CV_GridEditor").picked_for(fx.guid, key)
  if picked and #picked > 1 then
    if ImGui.MenuItem(ctx, ("Paste style to the %d selected"):format(#picked), nil, false, have) then
      local l = materialise(fx)
      local n = 0
      for _, k in ipairs(picked) do
        local o = l.controls[k]
        local fits = o and o.type ~= "divider" and (s.fam == nil or M.look_family(o) == s.fam)
        if fits and M.paste_look(o, s) then n = n + 1 end
      end
      if n > 0 then M.set(key, l); M.save() end
    end
    tip()
  end
  local noun = have and (s.fam and LOOK_NOUN[s.fam] or "control") or "control"
  if ImGui.BeginMenu(ctx, "Paste style to every " .. noun, have) then
    if ImGui.MenuItem(ctx, "In this section") then paste(section_range(layout.controls, idx)) end
    if ImGui.MenuItem(ctx, "On this panel") then paste(1, #layout.controls) end
    ImGui.EndMenu(ctx)
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
      ImGui.SetTooltip(ctx, "Open REAPER's modulation / link window for this parameter.\nTicked while modulation is on.")
    end
  end
end

-- Links a macro or modulator to a control, after asking when that
-- replaces another. A dropdown macro dropped on a stepped parameter
-- (2 to 8 steps) offers to take that parameter's choices.
local function link_source(src, k, path, param, label, was, centre)
  if was and was.mod.guid == src.guid and was.out == (k or 1) then return end
  local nm = src.name .. ((src.labels and src.labels[k or 1]) and (" " .. src.labels[k or 1]) or "")
  if was and reaper.MB(("%s is driven by %s.\n\nReplace it with %s?"):format(
       label or "This control", was.mod.name, nm), "ChannelView", 4) ~= 6 then
    return
  end
  if not MD.link(app.track, src, k or 1, path, param, centre) then return end
  if src.kind == "dropdown" then
    local taddr = T.addr_of(app.track, path)
    local names = taddr and MD.steps_of(app.track, taddr, param)
    if names and table.concat(names, "\0") ~= table.concat(src.choices or {}, "\0") then
      local q = ("Use %s's choices for %s?\n\n%s"):format(label or "this control", src.name,
                  table.concat(names, ", "))
      if reaper.MB(q, "ChannelView", 4) == 6 then
        local n0 = #(src.choices or {})
        local c = n0 >= 2 and MD.choice_of(MD.value(app.track, src, 1), n0) or 1
        MD.set_choices(app.track, src, names)
        MD.set_macro(app.track, src, 1, MD.choice_value(math.min(c, #names), #names))
      end
    end
  end
end

-- The link on this control (TS_CV_Mod): which macro or modulator drives
-- it and how -- a macro's range, a modulator's depth, invert, bipolar --
-- and Link to / Remove. Not a layout edit: offered when the layout is
-- locked too.
local function link_items(fx, c, param, axis)
  local s = MD.scan(app.track)
  local l = MD.link_of(app.track, fx.guid, param)
  local tag = "##" .. param
  local pre = axis and (axis .. ": ") or ""
  if l then
    local dl = ImGui.GetWindowDrawList(ctx)
    local x, y = ImGui.GetCursorScreenPos(ctx)
    ImGui.DrawList_AddRectFilled(dl, x + 1, y + 4, x + 10, y + 13, l.mod.col, 2)
    ImGui.SetCursorScreenPos(ctx, x + 16, y)
    local who = l.mod.name .. ((l.mod.labels and l.mod.labels[l.out]) and (" " .. l.mod.labels[l.out]) or "")
    ImGui.Text(ctx, pre .. "Driven by " .. who)
    if l.macro then
      local a, b = MD.range(l)
      ImGui.SetNextItemWidth(ctx, 170)
      local ca, na = ST.slider_double(ctx, "At 0%##modfrom" .. tag, a * 100, 0, 100, "%.0f%%")
      if ca then MD.set_range(app.track, l, na / 100, b) end
      if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "Control position at macro 0%.\nCtrl+click: type a value.") end
      ImGui.SetNextItemWidth(ctx, 170)
      local cb, nb = ST.slider_double(ctx, "At 100%##modto" .. tag, b * 100, 0, 100, "%.0f%%")
      if cb then MD.set_range(app.track, l, a, nb / 100) end
      if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "Control position at macro 100%.\nCtrl+click: type a value.") end
      if ImGui.MenuItem(ctx, "Swap the ends" .. tag) then MD.set_range(app.track, l, b, a) end
      if ImGui.MenuItem(ctx, "Whole range" .. tag) then MD.set_range(app.track, l, 0, 1) end
      if ImGui.MenuItem(ctx, "Remove the link" .. tag) then MD.unlink(app.track, l) end
    else
      ImGui.SetNextItemWidth(ctx, 170)
      local depth = math.abs(l.scale) * 100
      local ch, nv = ST.slider_double(ctx, "Depth##moddepth" .. tag, depth, 0, 100, "%.0f%%")
      if ch then MD.set_depth(app.track, l, (l.scale < 0 and -1 or 1) * nv / 100) end
      if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "Modulation amount.\nCtrl+click: type a value.") end
      local inv = l.scale < 0
      local ich = ST.checkbox(ctx, "Invert##modinv" .. tag, inv)
      if ich then MD.invert(app.track, l) end
      ImGui.SameLine(ctx, 0, 14)
      local bi = MD.is_bipolar(l)
      local bch = ST.checkbox(ctx, "Bipolar##modbi" .. tag, bi)
      if bch then MD.set_bipolar(app.track, l, not bi) end
      if ImGui.IsItemHovered(ctx) then
        ImGui.SetTooltip(ctx, "Swing both ways around the set position.")
      end
      if ImGui.MenuItem(ctx, "Remove modulation" .. tag) then MD.unlink(app.track, l) end
    end
  end
  if #s.list > 0 then
    if ImGui.BeginMenu(ctx, pre .. (l and "Driven by another\u{2026}" or "Link to a macro or modulator") .. tag) then
      local last
      for _, src in ipairs(s.list) do
        if last and last ~= src.src then ImGui.Separator(ctx) end
        last = src.src
        -- one entry per output (an XY pad's X and Y)
        for k = 1, #src.out do
          local dl = ImGui.GetWindowDrawList(ctx)
          local x, y = ImGui.GetCursorScreenPos(ctx)
          local nm = src.name
          if #src.out > 1 then nm = nm .. " \u{00B7} " .. ((src.labels and src.labels[k]) or tostring(k)) end
          local cur = l and l.mod.guid == src.guid and l.out == k
          if ImGui.MenuItem(ctx, "      " .. nm .. "##lk" .. src.guid .. k .. tag, nil, cur) then
            if not cur then
              link_source(src, k, fx.path_t, param, c.label, l, c.bipolar or nil)
            end
          end
          ImGui.DrawList_AddRectFilled(dl, x + 2, y + 4, x + 11, y + 13, src.col, 2)
        end
      end
      ImGui.EndMenu(ctx)
    end
  end
end

-- The links on this control: an XY pad's X and Y, a dual knob's ring and
-- inner knob each take their own.
local function mod_items(fx, c)
  if not (app.track and c and c.param and c.param >= 0) then return end
  local two = (c.type == "xy" or c.type == "dual") and c.param2 and c.param2 >= 0
  if not two then return link_items(fx, c, c.param, nil) end
  local a1, a2 = "X", "Y"
  if c.type == "dual" then a1, a2 = "Ring", "Inner" end
  link_items(fx, c, c.param, a1)
  ImGui.Separator(ctx)
  link_items(fx, c, c.param2, a2)
  ImGui.Separator(ctx)
end

-- "Automation lane" for a control's parameter(s): shows it (made if
-- there isn't one), or hides it. An XY pad or a dual knob has two.
local function lane_items(fx, c)
  if not (app.track and c and c.param and c.param >= 0) then return end
  local EN = require("TS_CV_Envelopes")
  local function item(p, what)
    local l = EN.fx_lane(app.track, fx.addr, p)
    if ImGui.MenuItem(ctx, "Automation lane" .. (what and (": " .. what) or "") .. "##lane" .. p,
                      l and l.auto and "has automation" or nil, l ~= nil and l.shown) then
      EN.toggle_fx_lane(app.track, fx.addr, p)
    end
    if l and ImGui.MenuItem(ctx, "Remove the lane" .. (what and (": " .. what) or "") .. "##lanerm" .. p) then
      local n = reaper.CountEnvelopePoints(l.env) or 0
      if not l.auto or reaper.MB(("Remove the lane and its automation (%d points)?"):format(n), "ChannelView", 4) == 6 then
        EN.remove(app.track, l.env)
      end
    end
  end
  local two = (c.type == "xy" or c.type == "dual") and c.param2 and c.param2 >= 0
  if two then
    local _, n1 = reaper.TrackFX_GetParamName(app.track, fx.addr, c.param, "")
    local _, n2 = reaper.TrackFX_GetParamName(app.track, fx.addr, c.param2, "")
    item(c.param, U.truncate(n1 or "", 20))
    item(c.param2, U.truncate(n2 or "", 20))
  else
    item(c.param)
  end
end

-- ---------------------------------------------------------------------
-- a control's right-click, in four parts: CONTROL (what it does: every
-- one of these is in Edit parameters too), LOOK (how it looks: only
-- here), AUTOMATE (what drives it) and ARRANGE (where it sits)
-- ---------------------------------------------------------------------

local function enter_pressed()
  return ImGui.IsItemDeactivated(ctx) and (ImGui.IsKeyPressed(ctx, ImGui.Key_Enter)
         or ImGui.IsKeyPressed(ctx, ImGui.Key_KeypadEnter))
end

-- Name: everything a control is called -- the parameter's alias (this
-- plugin, everywhere), this slot's own label, its live name, and a
-- button's names for its two states.
local function name_menu(fx, key, layout, idx, c)
  local function tip(t) if ImGui.IsItemHovered(ctx, ImGui.HoveredFlags_AllowWhenDisabled) then ImGui.SetTooltip(ctx, t) end end
  -- Renaming here sets the parameter's ALIAS: the name sticks to the
  -- parameter for this plugin everywhere, panels and editor lists alike.
  -- This slot's own label, if it has one, is cleared, or it would go on
  -- hiding the new name on the very control you renamed.
  ImGui.TextDisabled(ctx, "Alias: this plugin, everywhere")
  ImGui.SetNextItemWidth(ctx, 170)
  local _, v = ImGui.InputTextWithHint(ctx, "##alias", "name\u{2026}", app.rename_buf or "")
  local alias_enter = enter_pressed()
  app.rename_buf = v
  ImGui.SameLine(ctx)
  if ImGui.Button(ctx, "Set##alias") or alias_enter then
    local l = materialise(fx)
    local lc = l.controls[idx]
    if lc and lc.label and lc.label ~= "" then lc.label = ""; M.set(key, l); app.label_buf = "" end
    M.set_alias(key, c.param, app.rename_buf)
    M.save()
    ImGui.CloseCurrentPopup(ctx)
  end
  ImGui.TextDisabled(ctx, "Label: this slot only")
  ImGui.SetNextItemWidth(ctx, 170)
  local _, lv = ImGui.InputTextWithHint(ctx, "##label", "name\u{2026}", app.label_buf or "")
  local label_enter = enter_pressed()
  app.label_buf = lv
  ImGui.SameLine(ctx)
  if ImGui.Button(ctx, "Set##label") or label_enter then
    local l = materialise(fx)
    local lc = l.controls[idx]
    if lc then lc.label = U.trim(app.label_buf or "") end
    M.set(key, l); M.save()
    ImGui.CloseCurrentPopup(ctx)
  end
  tip("Name for this slot only, over the alias.\nClear to show the alias.")
  if ImGui.MenuItem(ctx, "Live name", nil, (c.live or layout.live) and true or false, not layout.live) then
    local l = materialise(fx)
    local lc = l.controls[idx]
    if lc then lc.live = (not c.live) or nil end
    M.set(key, l); M.save()
  end
  tip(layout.live and "On for the whole layout (Live parameter names)."
    or "Show the plugin's current name for this parameter.")

  -- A button's two states can have names of their own, for plugins whose
  -- switches read "0.0"/"1.0" or worse. Hints are what the plugin says.
  if c.type == "toggle" then
    ImGui.Separator(ctx)
    ImGui.TextDisabled(ctx, "State names: this plugin, everywhere")
    local function hint(n)
      if reaper.TrackFX_FormatParamValueNormalized then
        local ok, t = reaper.TrackFX_FormatParamValueNormalized(app.track, fx.addr, c.param, n, "")
        if ok and t and t ~= "" then return t end
      end
      return n < 0.5 and "off" or "on"
    end
    app.state_buf = app.state_buf or { "", "" }
    ImGui.SetNextItemWidth(ctx, 82)
    local _, v1 = ImGui.InputTextWithHint(ctx, "##stoff", hint(0), app.state_buf[1])
    local e1 = enter_pressed()
    app.state_buf[1] = v1
    ImGui.SameLine(ctx, 0, 6)
    ImGui.SetNextItemWidth(ctx, 82)
    local _, v2 = ImGui.InputTextWithHint(ctx, "##ston", hint(1), app.state_buf[2])
    local e2 = enter_pressed()
    app.state_buf[2] = v2
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, "Set##states") or e1 or e2 then
      materialise(fx)
      M.set_states(key, c.param, app.state_buf[1], app.state_buf[2])
      M.save()
      ImGui.CloseCurrentPopup(ctx)
    end
    tip("Off, then on. Leave empty to keep the plugin's text.")
  end
end

-- Values: what the parameter reads as -- the plugin's own, or your range
-- for a plugin that won't say (Range<p>, TS_CV_Util U.range_*). The same
-- as Edit parameters' Values row.
local function values_menu(fx, key, layout, idx, c)
  local p = c.param
  local rg = layout.ranges and layout.ranges[p]
  local tag = fx.guid .. ":" .. p
  if app.rng_for ~= tag then
    local r0 = rg or E.range_start(app.track, fx.addr, p)
    local ui, ci = 1, 1
    for i, u in ipairs(U.RANGE_UNITS) do if u == (r0.unit or "") then ui = i end end
    for i, k in ipairs(U.RANGE_CURVES) do if k == (r0.curve or "lin") then ci = i end end
    app.rng_for = tag
    app.rng = { lo = ("%g"):format(r0.lo), hi = ("%g"):format(r0.hi), unit = ui, curve = ci }
  end
  local b = app.rng
  local function typed()
    local lo, hi = E.parse_num(b.lo), E.parse_num(b.hi)
    if not lo or not hi or lo == hi then return nil end
    return { lo = lo, hi = hi, unit = U.RANGE_UNITS[b.unit] or "", curve = U.RANGE_CURVES[b.curve] or "lin" }
  end
  local function store(r)
    local l = materialise(fx)
    if r then l.ranges = l.ranges or {}; l.ranges[p] = r
    elseif l.ranges then l.ranges[p] = nil end
    M.set(key, l); M.save()
  end
  -- numbers round the dial, like a hardware knob's printed scale (a
  -- knob's; values unless it says otherwise; a small knob has no room)
  if c.type == "knob" or c.type == "stepped" or c.type == nil then
    ImGui.TextDisabled(ctx, "Numbers round the dial")
    local sc_now = M.scale_kind(c) or "none"
    local small = c.size == "small"
    ImGui.BeginDisabled(ctx, small)
    for i, o in ipairs({ { "none", "None" }, { "values", "Values" }, { "ten", "0\u{2013}10" } }) do
      if i > 1 then ImGui.SameLine(ctx, 0, 4) end
      if ImGui.Selectable(ctx, o[2] .. "##scale_" .. o[1], o[1] == sc_now, KEEP_OPEN, 56, 0) then
        local l = materialise(fx)
        local lc = l.controls[idx]
        if lc then
          lc.scale = (o[1] ~= "values") and o[1] or nil
          if o[1] == "none" then lc.scale_ink = nil end
        end
        M.set(key, l); M.save()
      end
      if ImGui.IsItemHovered(ctx, ImGui.HoveredFlags_AllowWhenDisabled) then
        ImGui.SetTooltip(ctx, small and "A small knob has no room for numbers."
          or (o[1] == "values") and "Its values, without units (thousands as k).\nMedium knobs then show the value in the tooltip."
          or (o[1] == "ten") and "0 to 10."
          or "No numbers.")
      end
    end
    ImGui.EndDisabled(ctx)
    ImGui.Separator(ctx)
  end
  ImGui.TextDisabled(ctx, "What it reads as")
  if ImGui.MenuItem(ctx, "The plugin's own", nil, rg == nil) and rg then
    store(nil); app.rng_for = nil
  end
  local want = typed()
  if ImGui.MenuItem(ctx, "Custom range", nil, rg ~= nil, want ~= nil) then store(want) end
  if ImGui.IsItemHovered(ctx, ImGui.HoveredFlags_AllowWhenDisabled) then
    ImGui.SetTooltip(ctx, "Your own range (below), for plugins that don't report values.")
  end
  ImGui.Separator(ctx)
  ST.cap(ctx, "From")
  ImGui.SetNextItemWidth(ctx, 74)
  local _, lo = ImGui.InputText(ctx, "##rmlo", b.lo)
  local e1 = enter_pressed()
  b.lo = lo
  ST.done(ctx)
  ImGui.SameLine(ctx, 0, 8)
  ST.cap(ctx, "To")
  ImGui.SetNextItemWidth(ctx, 74)
  local _, hi = ImGui.InputText(ctx, "##rmhi", b.hi)
  local e2 = enter_pressed()
  b.hi = hi
  ST.done(ctx)
  local un = {}
  for i, u in ipairs(U.RANGE_UNITS) do un[i] = (u == "") and "none" or u end
  ST.cap(ctx, "Unit")
  ImGui.SetNextItemWidth(ctx, 74)
  local uch, ui = ImGui.Combo(ctx, "##rmunit", b.unit - 1, table.concat(un, "\0") .. "\0")
  if uch then b.unit = ui + 1 end
  ST.done(ctx)
  ImGui.SameLine(ctx, 0, 8)
  ST.cap(ctx, "Curve")
  ImGui.SetNextItemWidth(ctx, 74)
  local cch, ci = ImGui.Combo(ctx, "##rmcurve", b.curve - 1, "Linear\0Log\0Squared\0")
  if cch then b.curve = ci + 1 end
  ST.done(ctx)
  want = typed()
  local now = reaper.TrackFX_GetParamNormalized(app.track, fx.addr, p) or 0
  ImGui.TextDisabled(ctx, want and ("now reads " .. U.range_text(want, now)) or "type two different ends")
  if ST.button(ctx, "Set##rmset", "main", nil, nil, { dim = not want }) or ((e1 or e2) and want) then
    store(want); ImGui.CloseCurrentPopup(ctx)
  end
  ImGui.SameLine(ctx)
  if ST.button(ctx, "Clear##rmclr", "remove", nil, nil, { dim = not rg }) then
    store(nil); app.rng_for = nil; ImGui.CloseCurrentPopup(ctx)
  end
end

-- Show when: Always, or one click on a button, dropdown, stepped knob or
-- virtual control on this layout; anything else (another parameter, is
-- not / above / between) is Edit parameters, opened at this control.
local function show_when_menu(fx, key, layout, idx, c)
  local function set(r)
    local l = materialise(fx)
    local lc = l.controls[idx]
    if lc then lc.show = r end
    M.set(key, l); M.save()
  end
  local base = M.split_variant(key)
  if c.show then
    local function pname(p)
      local _, pn = reaper.TrackFX_GetParamName(app.track, fx.addr, p, "")
      return M.display_name(key, p, nil, pn, false)
    end
    local function fmt(p, n)
      local ok_, sv = reaper.TrackFX_FormatParamValueNormalized(app.track, fx.addr, p, n, "")
      return ok_ and U.trim(sv or "") or nil
    end
    local function vfind(nm)
      local _, vc = M.vstart(base or key, nm, layout.controls)
      return vc
    end
    ImGui.TextDisabled(ctx, "Now: " .. U.truncate(M.rule_text(c.show, pname, fmt, vfind), 44))
    ImGui.Separator(ctx)
  end
  if ImGui.MenuItem(ctx, "Always", nil, c.show == nil) and c.show then set(nil) end
  local list = E.show_sources(app.track, fx.addr, key, layout.controls, c)
  if #list > 0 then ImGui.Separator(ctx) end
  for i, e in ipairs(list) do
    local mine = c.show and M.show_op(c.show) == "is"
      and ((e.vname and c.show.vname == e.vname) or (not e.vname and not c.show.vname and c.show.param == e.param))
    if ImGui.BeginMenu(ctx, U.truncate(e.label, 28) .. "##sw" .. i) then
      for k, ch in ipairs(e.choices) do
        local cur = mine and math.abs((c.show.norm or 0) - ch.norm) < 1e-4
        if ImGui.MenuItem(ctx, "is " .. U.truncate((ch.text or tostring(k)):gsub("%z", ""), 24) .. "##swc" .. k, nil, cur) then
          set({ param = e.param, vname = e.vname, op = "is", norm = ch.norm, tol = e.tol })
        end
      end
      ImGui.EndMenu(ctx)
    end
  end
  ImGui.Separator(ctx)
  if ImGui.MenuItem(ctx, "Another rule\u{2026}") then E.open(app.track, fx, key, layout, idx) end
  if ImGui.IsItemHovered(ctx) then
    ImGui.SetTooltip(ctx, "Other conditions (is not / above / below / between)\nin Edit parameters.")
  end
end

-- What acts on the whole plugin rather than this control
local function plugin_sub(fx)
  if ImGui.BeginMenu(ctx, "Plugin") then
    if ImGui.MenuItem(ctx, St.is_collapsed(fx.guid) and "Expand" or "Collapse to a bar") then
      toggle_fold(fx)
    end
    if ImGui.MenuItem(ctx, "Move left", nil, false, fx.index > 0) then nudge(fx.path_t, -1) end
    if ImGui.MenuItem(ctx, "Move right", nil, false, fx.index < fx.siblings - 1) then nudge(fx.path_t, 1) end
    if ImGui.MenuItem(ctx, "Open the plugin's window") then reaper.TrackFX_Show(app.track, fx.addr, 3) end
    ImGui.EndMenu(ctx)
  end
end

-- A control and its container's panel (TS_CV_Containers): put it on the
-- panel of the container it's in (or one further out), or, on a
-- container's own panel, take it off.
local function container_items(fx, c)
  if not (app.track and c and c.param and c.param >= 0) then return end
  local tr = app.track
  if fx.container_panel then
    ImGui.SeparatorText(ctx, "Container")
    local slot, p = CT.source(tr, fx.addr, c.param)
    local inner
    if slot then
      local path = {}
      for d, v in ipairs(fx.path_t) do path[d] = v end
      path[#path + 1] = slot
      inner = T.addr_of(tr, path)
    end
    -- a macro's or modulator's link runs through it: off the panel, but
    -- the parameter stays (the link needs it)
    local busy = CT.carries(tr, fx.addr, fx.path_t, c.param)
    if ImGui.MenuItem(ctx, busy and "Hide from the container" or "Take off the container") then
      reaper.Undo_BeginBlock()
      local what = CT.take_off(tr, fx.addr, fx.guid, fx.path_t, c.param)
      if what then CT.fix_layout(fx.guid, c.param, what == "deleted") end
      reaper.Undo_EndBlock("ChannelView: take a control off its container", -1)
      M.clear_default_cache()
      rescan(true)
    end
    if busy and ImGui.IsItemHovered(ctx) then
      ImGui.SetTooltip(ctx, "A macro or modulator drives it through the container, so the\n" ..
        "container keeps the parameter (REAPER's Param menu still lists it);\nit just leaves this panel.")
    end
    if inner and ImGui.MenuItem(ctx, "Open " .. U.truncate(U.clean_fx_name(select(2, reaper.TrackFX_GetFXName(tr, inner, ""))), 24) .. "'s window") then
      reaper.TrackFX_Show(tr, inner, 3)
    end
    return
  end
  local anc = fx.ancestors
  if not anc or #anc == 0 then return end
  ImGui.SeparatorText(ctx, "Container")
  -- the container it's in first, then those further out
  for up = 1, #anc do
    local node = anc[#anc - up + 1]
    local on = CT.is_on(tr, fx.path_t, c.param, up)
    local label = (up == 1 and "On its container" or "On the outer container") .. ": " .. box_label(node)
    if ImGui.MenuItem(ctx, label .. "##ct" .. up, nil, on) then
      reaper.Undo_BeginBlock()
      if on then
        local p = CT.put(tr, fx.path_t, c.param, up)   -- (found, not made)
        local what = p and CT.take_off(tr, node.addr, node.guid, node.path, p)
        if what then CT.fix_layout(node.guid, p, what == "deleted") end
      else
        local p, cguid = CT.put(tr, fx.path_t, c.param, up)
        -- a container panel with a layout of its own takes it at the end
        local l = p and M.get("Container " .. cguid)
        if l then
          l = M.copy(l)
          l.controls = l.controls or {}
          l.controls[#l.controls + 1] = M.apply_default_look({ param = p, type = "knob", label = "" })
          M.set("Container " .. cguid, l); M.save()
        end
      end
      reaper.Undo_EndBlock("ChannelView: " .. (on and "take a control off" or "put a control on") .. " its container", -1)
      M.clear_default_cache()
      rescan(true)
    end
    if ImGui.IsItemHovered(ctx) then
      ImGui.SetTooltip(ctx, on and "On that container's panel. Click: take it off."
        or "Show this control on the container's own panel too:\nturning either turns both, and it goes with the container\ninto an FX chain or a track template.")
    end
  end
end

local function automate_items(fx, c)
  if not (app.track and c and c.param and c.param >= 0) then return end
  ImGui.SeparatorText(ctx, "Automate")
  mod_items(fx, c)
  lane_items(fx, c)
  -- the MIDI learn bar, with this control's parameter in it
  local two = M.has_second(c) and c.param2 and c.param2 >= 0
  local a1, a2 = (c.type == "xy") and "X" or "ring", (c.type == "xy") and "Y" or "inner knob"
  if ImGui.MenuItem(ctx, two and ("MIDI learn (" .. a1 .. ")\u{2026}") or "MIDI learn\u{2026}") then
    ML.open_for(app.track, fx.guid, fx.addr, c.param)
  end
  if ImGui.IsItemHovered(ctx) then
    ImGui.SetTooltip(ctx, "Link to a MIDI control via the MIDI learn bar.")
  end
  if two and ImGui.MenuItem(ctx, "MIDI learn (" .. a2 .. ")\u{2026}") then
    ML.open_for(app.track, fx.guid, fx.addr, c.param2)
  end
  param_mod_item(fx, c)
end

-- The grid editor's sheet draws the panel's own menus (TS_CV_GridEditor
-- GE.hooks): for the plugin it's editing while ChannelView shows its
-- track with the same layout, so they work on the same list.
if ED.PRO then
require("TS_CV_GridEditor").hooks = (function()
  local function live(fx)
    for _, f in ipairs(app.chain or {}) do if f.guid == fx.guid then return f end end
    return nil
  end
  return {
    ready = function(track, fx, key)
      local f = (track == app.track) and live(fx)
      if not f then return false end
      local _, k = layout_for(f)
      return k == key
    end,
    style    = function(fx, key, idx, c) style_menu(live(fx), key, idx, c) end,
    back     = function(fx, key, idx, c) back_menu(live(fx), key, idx, c) end,
    section  = function(fx, key, idx, c) section_menu(live(fx), key, idx, c) end,
    look     = function(fx, key, layout, idx, c, locked) look_items(live(fx), key, layout, idx, c, locked) end,
    plate    = function(fx, key, layout) plate_menu(live(fx), key, layout) end,
    -- a colour for control idx's `field` (a line's or a section
    -- outline's, Edge<n>): none (`none`), a faceplate's, the plugin's own,
    -- recent ones, or one of your own -- the same choices as a background
    colour   = function(fx, key, idx, c, field, title, none)
      local f = live(fx)
      local function cset(k, save)
        local l, pk = materialise(f)
        local lc = l.controls[idx]
        if lc then lc[field] = k end
        M.set(pk, l)
        if save then M.save() end
      end
      local now = c[field]
      if swatch_row(none, field .. "_none", now == nil, 170, 0, C.COL.panel_border) then cset(nil, true) end
      for _, pl in ipairs(C.PLATES) do
        if pl.bg and swatch_row(pl.label, field .. "_" .. pl.key, now == pl.key, 170, pl.bg, pl.border) then
          cset(pl.key, true)
        end
      end
      local now_pl = C.plate_of(now)
      custom_rows(field, now, 170, cset, title, now_pl and (now_pl.bg >> 8), f)
    end,
  }
end)()
end

local function control_menu()
  if not ImGui.BeginPopup(ctx, "ctlmenu") then return end
  local cm = app.ctl_menu
  local fx = cm and app.chain[cm.fx]
  if not fx then ImGui.EndPopup(ctx) return end

  local layout, key = layout_for(fx)
  local c = layout.controls and layout.controls[cm.ctl]
  if not c then ImGui.EndPopup(ctx) return end
  local idx = cm.ctl

  -- a virtual control (the layout's own): its name, back to where it
  -- starts, and the layout's edits; no parameter to link or automate
  if M.is_virtual(c) then
    local nm = M.vname_of(c)
    ImGui.TextDisabled(ctx, "\u{25C6} " .. U.truncate(nm, 26) .. "  (virtual)")
    ImGui.Separator(ctx)
    if ImGui.MenuItem(ctx, "Back to where it starts") then St.vset(fx.guid, nm, c.virtual.start or 0) end
    if not M.locked(layout) then
      ImGui.SeparatorText(ctx, "Arrange")
      if ImGui.MenuItem(ctx, "Remove from panel") then
        local l = materialise(fx); M.save()
        table.remove(l.controls, idx)
        M.set(key, l); M.save()
      end
      ImGui.Separator(ctx)
      if not ED.PRO and ImGui.MenuItem(ctx, "Edit parameters\u{2026}") then E.open(app.track, fx, key, layout, idx) end
      if ED.item(ImGui, ctx, "Edit layout\u{2026}") then
        require("TS_CV_GridEditor").open(app.track, fx, key, layout, idx,
          { rows = M.locked(layout) or (P.RACK and P.RACK_ROWS) or app.cv_rows or 2, index = cm.fx, cv_h = app.cv_h,
          rack_w = app.rack_w or tonumber(reaper.GetExtState(C.EXT_SECT, "rack_width")) })
      end
    end
    plugin_sub(fx)
    ImGui.EndPopup(ctx)
    return
  end

  local _, pname = reaper.TrackFX_GetParamName(app.track, fx.addr, c.param or 0, "")
  ImGui.TextDisabled(ctx, U.truncate(pname or "", 26) .. "  \u{00B7}  " .. U.truncate(U.fx_label(fx), 20))

  local rescan_ok = (c.type == "combo" or c.type == "stepped") and c.param and c.param >= 0

  -- a locked layout takes no edits: say so, and offer only what isn't one
  if M.locked(layout) then
    ImGui.TextDisabled(ctx, "Layout locked (the padlock at the left of the panel's foot)")
    if rescan_ok then
      ImGui.SeparatorText(ctx, "Control")
      if ImGui.MenuItem(ctx, "Rescan choices") then P.rescan_choices(key, c.param) end
    end
    ImGui.SeparatorText(ctx, "Look")
    look_items(fx, key, layout, idx, c, true)
    automate_items(fx, c)
    container_items(fx, c)
    ImGui.Separator(ctx)
    plugin_sub(fx)
    ImGui.EndPopup(ctx)
    return
  end

  local function commit()
    local l, k = materialise(fx)
    M.save()
    return l, k
  end
  local function flip(field)
    local l = commit()
    local lc = l.controls[idx]
    if lc then lc[field] = (not lc[field]) or nil end
    M.set(key, l); M.save()
  end

  ------------------------------------------------------------- CONTROL
  ImGui.SeparatorText(ctx, "Control")
  if ImGui.BeginMenu(ctx, "Show as") then
    for _, t in ipairs(TYPE_ORDER) do
      if ImGui.MenuItem(ctx, TYPE_LABELS[t], nil, c.type == t and not (t == "combo" and c.buttons)) then
        local l = commit()
        local lc = l.controls[idx]
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
            local lc = l.controls[idx]
            lc.type, lc.buttons, lc.nbtn = "combo", d[1], n
            M.set(key, l); M.save()
          end
          if ImGui.IsItemHovered(ctx, ImGui.HoveredFlags_AllowWhenDisabled) then
            ImGui.SetTooltip(ctx, ok and ("One button per choice (%d)."):format(n)
              or ("Needs 2 to %d choices."):format(C.BUTTONS_MAX))
          end
        end
      end
    end
    -- an XY pad's Y, a concentric knob's inner knob
    if M.has_second(c) then
      ImGui.Separator(ctx)
      if ImGui.BeginMenu(ctx, (c.type == "xy") and "Y parameter" or "Inner knob parameter") then
        second_param_menu(fx, key, idx, c)
        ImGui.EndMenu(ctx)
      end
    end
    if rescan_ok then
      ImGui.Separator(ctx)
      if ImGui.MenuItem(ctx, "Rescan choices") then P.rescan_choices(key, c.param) end
    end
    ImGui.EndMenu(ctx)
  end

  if ImGui.BeginMenu(ctx, "Name") then
    name_menu(fx, key, layout, idx, c)
    ImGui.EndMenu(ctx)
  end

  local has_values = (c.type == "knob" or c.type == "stepped" or c.type == "fader" or c.type == "dual"
                      or c.type == nil) and c.param and c.param >= 0
  if has_values and ImGui.BeginMenu(ctx, "Values") then
    values_menu(fx, key, layout, idx, c)
    ImGui.EndMenu(ctx)
  end

  -- (a knob's is its Style > Value arc's Centred)
  if not M.has_second(c) and c.type ~= "toggle" and c.type ~= "combo"
     and c.type ~= "knob" and c.type ~= "stepped" and c.type ~= nil
     and ImGui.MenuItem(ctx, "Centred fill", nil, c.bipolar and true or false) then
    flip("bipolar")
  end
  -- reverse: knobs, buttons, and both halves of a two-parameter control
  -- (a dropdown's entries are positions in the plugin's own scale)
  if c.type == "knob" or c.type == "toggle" or c.type == "stepped" or c.type == nil then
    if ImGui.MenuItem(ctx, "Reverse", nil, c.invert and true or false) then flip("invert") end
  elseif M.has_second(c) then
    local a, b = (c.type == "xy") and "X" or "ring", (c.type == "xy") and "Y" or "inner knob"
    if ImGui.MenuItem(ctx, "Reverse " .. a, nil, c.invert and true or false) then flip("invert") end
    if ImGui.MenuItem(ctx, "Reverse " .. b, nil, c.invert2 and true or false) then flip("invert2") end
  end
  if ImGui.IsItemHovered(ctx) and (c.type ~= "combo" and c.type ~= "fader") then
    ImGui.SetTooltip(ctx, "Flip the direction on screen only.")
  end

  if ED.menu(ImGui, ctx, "Show when" .. (c.show and "  \u{25D0}" or "")) then
    show_when_menu(fx, key, layout, idx, c)
    ImGui.EndMenu(ctx)
  end

  ---------------------------------------------------------------- LOOK
  ImGui.SeparatorText(ctx, "Look")
  local styled = style_family(c.type) or c.type == "xy" or c.type == "dual" or c.type == "combo"
  if styled and ED.menu(ImGui, ctx, "Style") then
    style_menu(fx, key, idx, c)
    ImGui.EndMenu(ctx)
  end
  -- its own background, over its section's; neighbours with the same one
  -- join into one shape
  if c.type ~= "divider" and ED.menu(ImGui, ctx, "Background") then
    back_menu(fx, key, idx, c)
    ImGui.EndMenu(ctx)
  end
  -- the section this control is in belongs to the divider in front of it
  -- (dividers aren't on the panel to right-click, so it's offered here)
  -- (on a grid, the section rectangle it's on, the topmost)
  local div_idx
  if layout.grid and c.at then
    local mx, my = c.at.c + c.at.w / 2, c.at.r + c.at.h / 2
    for k = #layout.controls, 1, -1 do
      local o = layout.controls[k]
      local a = o.type == "section" and o.at
      if a and mx >= a.c and mx <= a.c + a.w and my >= a.r and my <= a.r + a.h then div_idx = k break end
    end
  else
    for k = idx - 1, 1, -1 do
      local o = layout.controls[k]
      if o.type == "divider" then div_idx = k break end
      if P.fader_kind(o) == "column" then break end
    end
  end
  if ED.menu(ImGui, ctx, "Section", div_idx ~= nil) then
    section_menu(fx, key, div_idx, layout.controls[div_idx])
    ImGui.EndMenu(ctx)
  end
  if ED.PRO and not div_idx and ImGui.IsItemHovered(ctx, ImGui.HoveredFlags_AllowWhenDisabled) then
    ImGui.SetTooltip(ctx, layout.grid and "Not on a section." or "Needs a divider first:\nArrange > Insert before > Divider.")
  end
  look_items(fx, key, layout, idx, c, false)

  ------------------------------------------------------------ AUTOMATE
  automate_items(fx, c)
  container_items(fx, c)

  ------------------------------------------------------------- ARRANGE
  ImGui.SeparatorText(ctx, "Arrange")
  -- (a grid's gaps are its empty space)
  if not layout.grid and ImGui.BeginMenu(ctx, "Insert before") then
    for _, g in ipairs({ { "blank", "Gap" }, { "half_gap", "Half gap" }, { "divider", "Divider" } }) do
      if ImGui.MenuItem(ctx, g[2]) then
        local l = commit()
        table.insert(l.controls, idx, { param = -1, type = g[1], bipolar = false, label = "" })
        M.set(key, l); M.save()
      end
    end
    ImGui.EndMenu(ctx)
  end
  if ImGui.MenuItem(ctx, "Remove from panel") then
    local l = commit()
    table.remove(l.controls, idx)
    M.set(key, l); M.save()
  end
  ImGui.Separator(ctx)
  if not ED.PRO and ImGui.MenuItem(ctx, "Edit parameters\u{2026}") then
    E.open(app.track, fx, key, layout, idx)
  end
  if ED.item(ImGui, ctx, "Edit layout\u{2026}") then
    require("TS_CV_GridEditor").open(app.track, fx, key, layout, idx,
      { rows = M.locked(layout) or (P.RACK and P.RACK_ROWS) or app.cv_rows or 2, index = cm.fx, cv_h = app.cv_h,
          rack_w = app.rack_w or tonumber(reaper.GetExtState(C.EXT_SECT, "rack_width")) })
  end
  plugin_sub(fx)
  ImGui.EndPopup(ctx)
end

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
  local lock_w = RACK and (C.ICON_SIZE + 6) or 0
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

-- The probes' menu, from the header's probe button.
local function probes_menu(state, vis)
  if not ImGui.BeginPopup(ctx, "probesmenu") then return end
  ImGui.TextDisabled(ctx, state == "pair" and "TS_TrackProbe pair in place"
                          or (state == "pre" and "The post probe is missing"
                          or "The pre probe is missing"))
  ImGui.Separator(ctx)
  if state ~= "pair" then
    if ImGui.MenuItem(ctx, "Add the missing probe") then
      local ok, why = TP.insert_probes(app.track)
      if not ok then reaper.MB(why, "ChannelView", 0) end
      rescan(true)
    end
  else
    ImGui.TextDisabled(ctx, "In the Visualizer's spectrum")
    local function opt(label, which, note)
      if ImGui.MenuItem(ctx, "   " .. label .. "##vis" .. tostring(which), note, vis == which) then
        TP.set_vis(app.track, which)
        TP.invalidate()
      end
    end
    opt("Not included", nil)
    opt("Before the chain", "pre", "pre probe")
    opt("After the chain", "post", "post probe")
  end
  ImGui.Separator(ctx)
  if ImGui.MenuItem(ctx, "Remove the probes\u{2026}") then
    local n = 0
    for _, fx in ipairs(app.chain) do
      local l = M.get(St.layout_key(fx.name, fx.guid, app.track, fx.addr))
      if l and (l.measure or l.levels) then n = n + 1 end
    end
    local q = "Take the TS_TrackProbe pair off this track?"
    if n > 0 then
      q = q .. ("\n\n%d plugin%s here %s measured by them: %s meter%s go%s until probes are added again.")
            :format(n, n == 1 and "" or "s", n == 1 and "is" or "are", n == 1 and "its" or "their",
                    n == 1 and "" or "s", n == 1 and "es" or "")
    end
    if reaper.MB(q, "ChannelView", 4) == 6 then
      TP.remove_probes(app.track)
      app.full_hash = nil
      rescan(true)
    end
  end
  ImGui.EndPopup(ctx)
end

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
    W.tip(ctx, "cvmain", "View, layouts and web companion", hov and not main_open, false)
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
      ImGui.Separator(ctx)
      if ImGui.MenuItem(ctx, "Float plugins without controls", nil, app.float_empty) then
        app.float_empty = not app.float_empty
        ext_set(FLOAT_KEY, app.float_empty and "1" or "0")
      end
      if ImGui.IsItemHovered(ctx) then
        ImGui.SetTooltip(ctx, "A plugin whose layout has no controls opens its own window when you\n" ..
          "come to its track, and it closes when you move on, unless you pin it\n" ..
          "(the pin in its panel's header).")
      end
      if ImGui.MenuItem(ctx, "Auto-hide this header", nil, app.header_hide) then
        app.header_hide = not app.header_hide
        ext_set(app.hide_key, app.header_hide and "1" or "0")
      end
      if ImGui.IsItemHovered(ctx) then
        ImGui.SetTooltip(ctx, "For a small screen: the panels take the header's room, and it slides\n"
          .. "out over them while the pointer is at the window's top edge.")
      end
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
        ImGui.SetTooltip(ctx, "Off: the wheel only scrolls.")
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

      -- the width of a control's column, for every panel
      if ImGui.BeginMenu(ctx, "Control spacing") then
        ImGui.SetNextItemWidth(ctx, 140)
        local cwch, cwv = ST.slider_int(ctx, "##cell_w", C.CELL_W, C.CELL_W_MIN, C.CELL_W_MAX, "%d px")
        if cwch then
          C.set_cell_w(cwv)
          ext_set("cell_w", tostring(C.CELL_W))
        end
        if ImGui.IsItemHovered(ctx) then
          ImGui.SetTooltip(ctx, "Width of each control's column.\nCtrl+click: type a value.")
        end
        if ImGui.MenuItem(ctx, ("Reset to %d px"):format(C.CELL_W_DEFAULT), nil, false, C.CELL_W ~= C.CELL_W_DEFAULT) then
          C.set_cell_w(C.CELL_W_DEFAULT)
          ext_set("cell_w", tostring(C.CELL_W))
        end
        ImGui.EndMenu(ctx)
      end

      -- the width of an expanded channel strip: the pinned fader panel, every
      -- mixer strip and the track name buttons (collapsed ones keep theirs)
      if ImGui.BeginMenu(ctx, "Strip width") then
        ImGui.SetNextItemWidth(ctx, 140)
        local swch, swv = ST.slider_int(ctx, "##channel_w", C.CHANNEL_W, C.CHANNEL_W_MIN, C.CHANNEL_W_MAX, "%d px")
        if swch then
          C.set_channel_w(swv)
          ext_set("channel_w", tostring(C.CHANNEL_W))
        end
        if ImGui.IsItemHovered(ctx) then
          ImGui.SetTooltip(ctx, "Width of the fader panel, mixer strips and name buttons.\nCtrl+click: type a value.")
        end
        if ImGui.MenuItem(ctx, ("Reset to %d px"):format(C.CHANNEL_W_DEFAULT), nil, false,
                          C.CHANNEL_W ~= C.CHANNEL_W_DEFAULT) then
          C.set_channel_w(C.CHANNEL_W_DEFAULT)
          ext_set("channel_w", tostring(C.CHANNEL_W))
        end
        ImGui.EndMenu(ctx)
      end

      if ImGui.MenuItem(ctx, "Preset bar", nil, C.PRESET_BAR) then
        C.PRESET_BAR = not C.PRESET_BAR
        ext_set("preset_bar", C.PRESET_BAR and "1" or "0")
      end
      if ImGui.IsItemHovered(ctx) then
        ImGui.SetTooltip(ctx, "Preset controls along each panel's foot.")
      end

      if ED.item(ImGui, ctx, "3D effect", nil, C.EFFECT_3D) then
        C.EFFECT_3D = not C.EFFECT_3D
        ext_set("plate_texture", C.EFFECT_3D and "1" or "0")
      end
      if ED.PRO and ImGui.IsItemHovered(ctx) then
        ImGui.SetTooltip(ctx, "Gradients, lit edges and soft shadows.")
      end

      -- how strongly the light models the plates and knobs
      if ED.menu(ImGui, ctx, "Lighting", C.EFFECT_3D) then
        ImGui.SetNextItemWidth(ctx, 140)
        local lch, lv = ST.slider_int(ctx, "##light", C.LIGHT, 0, C.LIGHT_MAX, "%d%%")
        if lch then
          C.LIGHT = lv
          require("TS_CV_KnobParts").LIGHT = C.LIGHT / 100
          ext_set("light", tostring(C.LIGHT))
        end
        if ImGui.IsItemHovered(ctx) then
          ImGui.SetTooltip(ctx, "Above 100: studio-lit, bright top left to deep bottom right.\nCtrl+click: type a value.")
        end
        if ImGui.MenuItem(ctx, "Reset to 100%", nil, false, C.LIGHT ~= 100) then
          C.LIGHT = 100
          require("TS_CV_KnobParts").LIGHT = 1
          ext_set("light", "100")
        end
        ImGui.EndMenu(ctx)
      end

      -- how deep and far the shadows fall (all of them: knobs, switches,
      -- buttons, fader caps; and the web page's)
      if ED.menu(ImGui, ctx, "Shadows", C.EFFECT_3D) then
        ImGui.SetNextItemWidth(ctx, 140)
        local shch, shv = ST.slider_int(ctx, "##shadow", C.SHADOW, 0, C.SHADOW_MAX, "%d%%")
        if shch then
          C.SHADOW = shv
          ED.light().STRENGTH = C.SHADOW / 100
          ext_set("shadow", tostring(C.SHADOW))
        end
        if ImGui.IsItemHovered(ctx) then
          ImGui.SetTooltip(ctx, "0: none. 200: deep and long.\nCtrl+click: type a value.")
        end
        if ImGui.MenuItem(ctx, "Reset to 100%", nil, false, C.SHADOW ~= 100) then
          C.SHADOW = 100
          ED.light().STRENGTH = 1
          ext_set("shadow", "100")
        end
        ImGui.EndMenu(ctx)
      end

      if ImGui.MenuItem(ctx, "Track icons", nil, C.TRACK_ICONS) then
        C.TRACK_ICONS = not C.TRACK_ICONS
        ext_set("track_icons", C.TRACK_ICONS and "1" or "0")
      end
      if ImGui.IsItemHovered(ctx) then
        ImGui.SetTooltip(ctx, "Track icons above the name buttons.")
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
            "Keyboard goes back to REAPER after a click,\nso Space and shortcuts keep working."
            or "Needs js_ReaScriptAPI or SWS.")
        end
      end

      ImGui.Separator(ctx)

      if ImGui.BeginMenu(ctx, "Panel alignment") then
        if ImGui.MenuItem(ctx, "Left", nil, C.ROW_ALIGN == "left") then
          C.ROW_ALIGN = "left"; ext_set("row_align", C.ROW_ALIGN)
        end
        if ImGui.MenuItem(ctx, "Centred", nil, C.ROW_ALIGN == "centre") then
          C.ROW_ALIGN = "centre"; ext_set("row_align", C.ROW_ALIGN)
        end
        ImGui.EndMenu(ctx)
      end
      ImGui.Separator(ctx)
      if ImGui.BeginMenu(ctx, "Colour") then
        -- One hue drives the whole palette, so this can be brought into
        -- line with a REAPER theme without picking thirty colours. Bypass
        -- and warnings deliberately don't follow it -- see TS_CV_Config.
        ImGui.SetNextItemWidth(ctx, 190)
        local hch, hv = ST.slider_int(ctx, "Hue", math.floor(C.BASE_HUE), 0, 359)
        if hch then
          C.BASE_HUE = hv
          C.build_palette()
          pal_set(hv, C.TINT)
        end

        ImGui.SetNextItemWidth(ctx, 190)
        local tch, tv = ST.slider_double(ctx, "Tint", C.TINT, 0.0, 2.0, "%.2f")
        if tch then
          C.TINT = tv
          C.build_palette()
          pal_set(C.BASE_HUE, tv)
        end
        W.tip(ctx, "tint",
          "How much the greys lean toward the hue.\n0: neutral, 1: default.",
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
  local fx_w  = C.ICON_SIZE + 4 + fx_tw
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
    local tw = C.ICON_SIZE + 10
    if not RACK and fx_left - menus_right > tw + 40 then
      ImGui.SameLine(ctx, 0, 0)
      ImGui.SetCursorScreenPos(ctx, menus_right + 6, mid_y - C.ICON_SIZE * 0.5)
      view_toggle(ctx, mid_y)
      menus_right = menus_right + tw
    end
  end

  -- a hairline, then the tools
  if fx_left - menus_right > GROUP_GAP + C.ICON_SIZE + 46 then
    hairline(menus_right + GROUP_GAP * 0.5)
    menus_right = menus_right + GROUP_GAP
  end

  -- MIDI learn: the drawer under the header (TS_CV_MidiLearn), first after
  -- the hairline
  do
    local tw = C.ICON_SIZE + 6
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
    local tw = C.ICON_SIZE + 6
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
    local tw = C.ICON_SIZE + 6
    if fx_left - menus_right > tw + 40 then
      ImGui.SameLine(ctx, 0, 0)
      ImGui.SetCursorScreenPos(ctx, menus_right + 2, mid_y - C.ICON_SIZE * 0.5)
      local have = TRM.find(app.track)
      if W.icon_button(ctx, "trimmer", "trimmer", C.ICON_SIZE, have ~= nil,
          have and "Trimmer" or "Add Trimmer") then
        if have then
          ImGui.OpenPopup(ctx, "trimmermenu")
        else
          reaper.Undo_BeginBlock()
          local idx = TRM.insert(app.track, TP.ara_first(app.track))
          reaper.Undo_EndBlock("ChannelView: add Trimmer", -1)
          if idx then
            rescan(true)
          else
            reaper.MB("ChannelView couldn't find its TS_CV Trimmer plugin\n" ..
                      "(TS_CV_Trimmer.jsfx). Reinstalling ChannelView from ReaPack puts it back.",
                      "ChannelView", 0)
          end
        end
      end
      if ImGui.BeginPopup(ctx, "trimmermenu") then
        local idx = TRM.find(app.track)
        if idx then
          if ImGui.MenuItem(ctx, "Auto trim from the items") then
            reaper.Undo_BeginBlock()
            local t, why = TRM.auto_trim(app.track, function(msg)
              return reaper.MB(msg, "Auto trim", 4) == 6
            end, TP.ara_first(app.track))
            reaper.Undo_EndBlock("ChannelView: auto trim", -1)
            if not t and why ~= "cancelled" then reaper.MB("Auto trim: " .. why .. ".", "ChannelView", 0) end
          end
          ImGui.Separator(ctx)
          if ImGui.MenuItem(ctx, "Remove the Trimmer") then
            reaper.Undo_BeginBlock()
            reaper.TrackFX_Delete(app.track, idx)
            reaper.Undo_EndBlock("ChannelView: remove Trimmer", -1)
            rescan(true)
          end
        end
        ImGui.EndPopup(ctx)
      end
      menus_right = menus_right + tw
    end
  end

  -- Action drawers (TS_CV_Drawers): lit while any is open; click for the
  -- list, to open or close each, make a new one, or organise them.
  do
    local tw = C.ICON_SIZE + 6
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
  if app.track and fx_left - menus_right > GROUP_GAP + C.ICON_SIZE + 46 then
    fx_left = fx_left - GROUP_GAP
    hairline(fx_left + GROUP_GAP * 0.5)
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
    local tw = C.ICON_SIZE + 6
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
    local tw = C.ICON_SIZE + 6
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

-- The bracket strip: one bracket per FX container and per run of plugins
-- in parallel, over the panels they hold, drawn after the panels so the
-- rectangles are known. A container's square opens its menu.
local function bracket_tip(b)
  if b.kind == "container" then
    local n = b.node
    local inside = #(n.children or {})
    local t = ("Container: %s \u{2014} %d %s"):format(box_label(n), inside,
      inside == 1 and "slot" or "slots")
    if CT.folded(n.guid) and CT.shown[n.guid] then t = t .. "\nFolded to its panel" end
    if not T.get_enabled(app.track, n.addr) then t = t .. "\nBypassed" end
    if n.parallel ~= 0 then t = t .. "\nIn parallel with previous" end
    local st = T.os_state(app.track, { addr = n.addr, ancestors = box_ancestors(n) })
    if st.lit then t = t .. ("\nOversampled %dx (%s)"):format(st.lit, T.os_label(st.n, st.rate):lower()) end
    return t .. "\nClick: menu"
  end
  local lines = { "In parallel:" }
  for k, m in ipairs(b.members) do
    local nm = m.kind == "container" and ("container " .. box_label(m)) or (m.alias or U.fx_label(m))
    if k > 1 and m.parallel == 2 then nm = nm .. "  (MIDI merged)" end
    lines[#lines + 1] = "  \u{2022} " .. nm
  end
  lines[#lines + 1] = "Outputs summed. Change: right-click a panel \u{25B8} Route"
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
      -- folded to its panel: says so, and how much it stands for
      if label and CT.shown[b.node.guid] and CT.folded(b.node.guid) then
        label = label .. "  \u{25B8} " .. #(b.node.children or {})
      end
      local tw, th = 0, 0
      if label then
        tw, th = ImGui.CalcTextSize(ctx, label)
        if tw + sq + 4 + 30 > x2 - x1 then label, tw = nil, 0 end
      end
      -- oversampled: the factor, lit, after the name
      local os_lit = box and T.os_state(app.track, { addr = b.node.addr, ancestors = box_ancestors(b.node) }).lit or nil
      local os_n = os_lit and 1 or 0
      local ow = 0
      if os_lit then
        ow = W.os_width(ctx, os_lit)
        if (label and tw or 0) + sq + 4 + ow + 4 + 30 > x2 - x1 then label, tw = nil, 0 end
      end
      local mw = box and (sq + (label and (4 + tw) or 0) + (os_n > 0 and (4 + ow) or 0)) or 6
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
        if os_n > 0 then
          local ox = sx + sq + 4 + (label and (tw + 4) or 0)
          local bh = C.BRK_ROW_H - 1
          ImGui.DrawList_AddRectFilled(dl, ox, ly - bh * 0.5, ox + ow, ly + bh * 0.5, col, 2.0)
          W.push_small(ctx)
          local ot = ("%dx"):format(os_lit)
          local otw, oth = ImGui.CalcTextSize(ctx, ot)
          ImGui.DrawList_AddText(dl, ox + (ow - otw) * 0.5, ly - oth * 0.5, C.COL.panel_bg, ot)
          W.pop_small(ctx)
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

-- What a panel asked for this frame (P.draw's req): acted on the same way
-- wherever it was drawn -- the row, or the Rack view's column.
local function panel_requests(i, fx, layout, key, req)
    if req.toggle_bypass then
      T.set_enabled(app.track, fx.addr, not T.get_enabled(app.track, fx.addr))
    end
    if req.toggle_float then
      T.toggle_float(app.track, fx.addr)
    end
    if req.toggle_pin then AF.toggle_pin(fx.guid) end
    if req.toggle_collapse then
      toggle_fold(fx)
    end
    if req.remove then app.remove_ask = fx end
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
    if req.canvas_setup then CS.open(app.track, fx, key) end
    -- a modulator's link dropped on a control: linked, after asking
    -- when that replaces another modulator
    if req.mod_drop then
      local d = req.mod_drop
      link_source(d.mod, d.k or 1, d.path, d.param, d.label, d.was, d.centre)
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
    if req.page_cap then
      -- a page tab's colour, from its right-click picker: previewed as
      -- you hover (not saved to disk until you pick)
      local l = materialise(fx)
      local c = l.controls and l.controls[req.page_cap.idx]
      if c and c.type == "page" then
        c.cap = req.page_cap.cap
        M.set(key, l)
        if req.page_cap.save then M.save() end
      end
    end
    if req.grv_window then
      local l = materialise(fx)
      if l.meter then
        l.meter.win = (req.grv_window ~= C.GRV_DEFAULT) and req.grv_window or nil
      elseif P.own_rc(key) then
        -- ReaComp's canvas keeps its history's window in the same
        -- place, with no meter of its own (the canvas has the meters)
        l.meter = { on = false, win = (req.grv_window ~= require("TS_CV_CompPanel").WINDOW_DEFAULT) and req.grv_window or nil }
      end
      M.set(key, l); M.save()
    end
    if req.ctx_control then
      app.ctl_menu = { fx = i, ctl = req.ctx_control }
      local c = layout.controls and layout.controls[req.ctx_control]
      local pn = ""
      if c and c.param then
        pn = select(2, reaper.TrackFX_GetParamName(app.track, fx.addr, c.param, ""))
      end
      -- starts as the name the control shows now
      app.rename_buf = c and c.param
        and M.display_name(key, c.param, nil, pn, false) or pn or ""
      app.label_buf = c and c.label or ""
      app.rng_for = nil
      local st = c and c.param and M.get_states(key, c.param)
      app.state_buf = { st and st[1] or "", st and st[2] or "" }
      app.open_ctl_menu = true
    end
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
          local pw, req = P.draw(ctx, it.tr, it.fx, layout, key, h, k, false)
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
      local gap = C.PANEL_GAP + 4
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
        for k = b.first, b.last do drop[k] = math.max(drop[k] or 0, d) end
      end
      local function panel_h(i) return inner_h - (drop[i] or 0) end

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
                                  P.has_io(app.track, fx, lay),
                                  St.is_gr_open(fx.guid), M.locked(lay),
                                  (not P.own_eq(k) and not P.own_rc(k)) and lay.canvas or nil)
          if i > 1 then total = total + C.PANEL_GAP end
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
      if out then
        drop = nil
        local w = into and POP.PO.window(into)
        ImGui.SetTooltip(ctx, w and ("Pop out into \u{201C}" .. w.name .. "\u{201D}") or "Pop out")
      end
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
        if out then
          for _, f in ipairs(app.chain) do
            if f.guid == app.drag.guid then POP.pop_out(app.track, f, into, { mx - 20, my - 10 }) break end
          end
        end
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
  if St.is_collapsed(fx.guid) then return C.HEADER_H + 2 end
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
  local h = C.BRK_ROW_H + 4
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
    local ox, ow, bh = sx + sq + 5 + tw + 6, W.os_width(ctx, os_lit), C.BRK_ROW_H - 1
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
        frozen_strip(ctx, "rfz" .. k, colx, fy, rack_w, C.HEADER_H + 2, k .. " \u{00B7} " .. name, fst)
        fy = fy + C.HEADER_H + 2 + C.PANEL_GAP
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
    if add_tile(C.HEADER_H + 12, rack_w) then B.open_menu(nil) end
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
      local dl = ImGui.GetWindowDrawList(ctx)
      local wx = ImGui.GetWindowPos(ctx)
      local ww = ImGui.GetWindowSize(ctx)
      ImGui.DrawList_AddRectFilled(dl, wx + 2, drop.y - 1.5, wx + ww - 2, drop.y + 1.5,
        drop.into and C.COL.brk_container or C.COL.drop_marker, 1.0)
      if drop.into then ImGui.SetTooltip(ctx, "Into " .. box_label(drop.into)) end
    end
    if not ImGui.IsMouseDown(ctx, ImGui.MouseButton_Left) then
      if drop then move_to(app.drag.path, drop.parent, drop.gap, app.drag.what) end
      app.drag, app.drop_gap = nil, nil
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
  AF.tick(app.float_empty and app.track or nil, no_controls)
  PC.tick()
  P.AUTO_FLOAT = app.float_empty
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
      -- a layout saved by the other window (ChannelView / its Rack view)
      local ms, ss = M.sync(), SC.sync()
      if ms or ss then rescan(true) end
      C.set_cell_w(ext_get("cell_w", tostring(C.CELL_W_DEFAULT)))
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
  -- the look of every panel, dialogue and menu drawn this frame
  ST.push(ctx)
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
    local mr_w   = (ma_on and MR.width_for("macros", app.track, row_h) or 0)
                   + (mo_on and MR.width_for("mods", app.track, row_h) or 0)
    local n_gaps = 1 + (ma_on and 1 or 0) + (mo_on and 1 or 0) + (sd_on and 1 or 0) + (rv_on and 1 or 0)
    local mid_w  = math.max(80, full_w - ch_w - mr_w - rv_w - sd_w - C.PANEL_GAP * n_gaps)

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
      side_drawers(row_h)
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
        open_from_name(dbl_track)
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
    if TM.draw(ctx) then rescan(true) end
    CP.draw(ctx, false)
    if CN.draw(ctx) then rescan(true) end

    -- Probe taps: the heartbeat that keeps them measuring, and one
    -- track's routing re-checked per frame.
    TP.update()
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
  POP.windows()
  -- the Organise actions window, its own window beside this one
  AE.draw(ctx)
  -- the knob look editor (Style > Customise...), its own window too
  KE.draw(ctx)
  -- the grid editor (Edit layout...), and the menu of a control
  -- right-clicked in it
  do
    local GE = ED.module("TS_CV_GridEditor", ED.stub())
    GE.draw(ctx)
    local m = GE.take_menu()
    if m then
      for i, f in ipairs(app.chain or {}) do
        if f.guid == m.guid then
          app.ctl_menu = { fx = i, ctl = m.idx }
          app.open_ctl_menu = true
          break
        end
      end
    end
  end

  -- The style pushes happened before Begin, so they unwind either way.
  ImGui.PopStyleVar(ctx, 1)
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
function safe_frame()
  local ok, err = xpcall(timed_frame, function(e)
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
  DR.cancel_picks(); AE.cancel_picks(); E.cancel_vpick()
  M.save(); SC.save()
  reaper.DeleteExtState(C.EXT_SECT, ALIVE, false)
  show_toggle_state(false)      -- no window, no mixer showing
end)
if not RACK then reaper.DeleteExtState(C.EXT_SECT, TOGGLE_REQ, false) end   -- one left from a window since closed
show_toggle_state(C.MIXER_VIEW)
reaper.defer(safe_frame)
