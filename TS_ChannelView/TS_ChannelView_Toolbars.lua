-- @noindex
-- Not a package of its own: installed by TS_ChannelView.lua's @provides.
--[[
  TS_ChannelView_Toolbars.lua -- ChannelView's action bars in windows of
  their own, and the Organise actions window when nothing else has it.

  Every action bar set to "Own window" (TS_CV_Drawers) gets a window here:
  floating, or in one of REAPER's dockers (a bar's right-click ▸ Dock).
  A window wider than it is tall lays its buttons out in rows, a taller
  one in a column. Close a window and its bar is closed (open it again
  from ChannelView's drawers button or Organise actions); the script keeps
  running for the next one. Run it again to stop it.

  ChannelView starts it when a bar is put in a window, and the TCP and the
  Organise actions action ask it for the organiser (ExtState
  TS_ChannelView/bars_organise). It needs nothing from ChannelView's
  window and runs whether that's open or not.
--]]

local script_dir = debug.getinfo(1, "S").source:match("@?(.*[\\/])") or ""

if not reaper.ImGui_GetBuiltinPath then
  reaper.MB("ChannelView toolbars need the ReaImGui extension.\n\n" ..
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
  reaper.MB("ChannelView toolbars could not load ReaImGui:\n\n" .. tostring(ImGui), "ChannelView", 0)
  return
end

-- as in the TCP: a zero-sized invisible button would stop the script
do
  local invisible = ImGui.InvisibleButton
  ImGui.InvisibleButton = function(c, id, w, h, ...)
    if w == 0 then w = 1 end
    if h == 0 then h = 1 end
    return invisible(c, id, w, h, ...)
  end
end

local C  = require("TS_CV_Config")
local W  = require("TS_CV_Widgets")
local TB = require("TS_CV_Toolbar")
local DR = require("TS_CV_Drawers")
local AE = require("TS_CV_ActionEditor")
local CP = require("TS_CV_ColourPick")
local SU = require("TS_CV_Startup").make("ChannelView toolbars", "TS_ChannelView_Toolbars.lua",
                                         "channelview_toolbars_cmd")

W.attach(ImGui); TB.attach(ImGui); DR.attach(ImGui); AE.attach(ImGui); CP.attach(ImGui)
SU.init()

-- the shared palette (hue and tint), as the TCP reads it
do
  local h = tonumber(reaper.GetExtState("TS_Palette", "base_hue"))
  local t = tonumber(reaper.GetExtState("TS_Palette", "tint"))
  C.BASE_HUE = h or C.BASE_HUE
  C.TINT     = t or C.TINT
end
C.build_palette()

DR.load()
DR.organise = function(d, item) AE.open(d, item) end
DR.share = function(mode) AE.share(mode) end

-- A ReaImGui context lives only while it's used every defer cycle, and
-- with no toolbar open nothing would use it: each frame touches it, and
-- one lost anyway (REAPER busy, say) is made again, the bars with it (their
-- icons were attached to the old one).
local ctx = ImGui.CreateContext("ChannelView toolbars")
local function keep_context()
  if not ImGui.ValidatePtr(ctx, "ImGui_Context*") then
    ctx = ImGui.CreateContext("ChannelView toolbars")
    DR.load()
  end
  ImGui.GetFrameCount(ctx)
end
local applied = {}       -- bar id -> the dock it was last put in
local rects = {}         -- bar id -> { x, y, w, h } of its window last frame

-- A bar's right-click menu (TS_CV_Toolbar, with its place, dock, look and
-- Organise actions from TS_CV_Drawers) gets one more thing here.
DR.host_extra = function()
  if not SU.checked() then SU.scan() end
  local st_ = SU.state()
  if ImGui.MenuItem(ctx, "Run toolbars when REAPER starts", nil, SU.on(), st_ ~= "nocmd") then
    if SU.on() then SU.remove() else SU.add() end
    SU.forget()
  end
end

local function bar_window(d)
  local dock = d.dock or 0
  -- switched in from another bar's window: opens where that one was
  local from = d.took_from and rects[d.took_from]
  d.took_from = nil
  if applied[d.id] ~= dock or from then
    ImGui.SetNextWindowDockID(ctx, dock, (applied[d.id] == nil and not from) and ImGui.Cond_FirstUseEver or ImGui.Cond_Always)
    applied[d.id] = dock
  end
  if from and dock == 0 then
    ImGui.SetNextWindowPos(ctx, from[1], from[2], ImGui.Cond_Always)
    ImGui.SetNextWindowSize(ctx, from[3], from[4], ImGui.Cond_Always)
  end
  ImGui.SetNextWindowSize(ctx, 420, 46, ImGui.Cond_FirstUseEver)
  ImGui.PushStyleColor(ctx, ImGui.Col_WindowBg, C.COL.header_bg)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowPadding, 4, 4)
  local title = (d.name ~= "" and d.name or ("Toolbar " .. d.id)) .. "###cvbar" .. d.id
  local vis, open = ImGui.Begin(ctx, title, true,
    ImGui.WindowFlags_NoScrollbar | ImGui.WindowFlags_NoScrollWithMouse | ImGui.WindowFlags_NoCollapse)
  ImGui.PopStyleVar(ctx)
  if vis then
    -- docked or undocked by dragging: remember where
    local now = ImGui.GetWindowDockID(ctx)
    if now ~= dock then d.dock = now; applied[d.id] = now; DR.save() end
    local wx, wy = ImGui.GetWindowPos(ctx)
    local ww, wh = ImGui.GetWindowSize(ctx)
    rects[d.id] = { wx, wy, ww, wh }
    DR.draw_window_bar(ctx, d)
    d.tb.draw_menus(ctx)
    W.draw_tip(ctx)
    ImGui.End(ctx)
  end
  ImGui.PopStyleColor(ctx)
  if open == false then d.open = false; DR.save() end
end

local safe_frame
local function frame()
  keep_context()
  DR.sync()
  W.begin_frame()
  if reaper.GetExtState(C.EXT_SECT, DR.HOST_ORGANISE) == "1" then
    reaper.DeleteExtState(C.EXT_SECT, DR.HOST_ORGANISE, false)
    AE.open()
  end
  for _, d in ipairs(DR.list) do
    if d.side == "window" and d.open then bar_window(d)
    elseif d.tb then d.tb.poll() end
  end
  AE.draw(ctx)
  -- the colour dialog opened from a bar button's right-click Colour menu,
  -- from a small window of its own: a modal needs a window to open from
  if CP.is_open() then
    ImGui.SetNextWindowSize(ctx, 1, 1)
    local f = ImGui.WindowFlags_NoDecoration | ImGui.WindowFlags_NoBackground | ImGui.WindowFlags_NoInputs
              | ImGui.WindowFlags_NoSavedSettings | ImGui.WindowFlags_NoFocusOnAppearing
    if ImGui.Begin(ctx, "##cvcolour", nil, f) then
      CP.draw(ctx, false)
      ImGui.End(ctx)
    end
  end
  reaper.SetExtState(C.EXT_SECT, DR.HOST_ALIVE, tostring(reaper.time_precise()), false)
  if reaper.GetExtState(C.EXT_SECT, DR.HOST_QUIT) == "1" then
    reaper.DeleteExtState(C.EXT_SECT, DR.HOST_QUIT, false)
    return
  end
  reaper.defer(safe_frame)
end

safe_frame = function()
  local ok, err = xpcall(frame, function(e) return debug.traceback(tostring(e), 2) end)
  if ok then return end
  DR.cancel_picks()
  reaper.ShowConsoleMsg("\n--- ChannelView toolbars stopped on an error ---\n" .. tostring(err) .. "\n")
end

-- A toggle in the action list, lit while it runs.
local _, _, sec, cmd = reaper.get_action_context()
if cmd and cmd ~= 0 then
  reaper.SetToggleCommandState(sec, cmd, 1)
  reaper.RefreshToolbar2(sec, cmd)
end
reaper.atexit(function()
  DR.cancel_picks()
  reaper.DeleteExtState(C.EXT_SECT, DR.HOST_ALIVE, false)
  if cmd and cmd ~= 0 then
    reaper.SetToggleCommandState(sec, cmd, 0)
    reaper.RefreshToolbar2(sec, cmd)
  end
end)
reaper.DeleteExtState(C.EXT_SECT, DR.HOST_QUIT, false)
reaper.defer(safe_frame)
