-- @noindex  (a development tool, not a package: never installed)
-- The role and mapped canvases at a tile's heights (the TCP window's
-- overview, 1 and 2 rows: TS_CV_Panel P.TILE, TS_CV_CompPanel CP.TILE),
-- each drawn with a fake ImGui that objects to an empty or negative size,
-- as ReaImGui stops the script on one. Run: lua5.4 dev/TS_CV_CanvasSizeTest.lua
local HERE = debug.getinfo(1, "S").source:match("@?(.*[\\/])") or "./"
package.path = HERE .. "../?.lua;" .. package.path
local function anyf(ret) return function() return ret end end
reaper = setmetatable({
  TrackFX_GetNumParams = function() return 40 end,
  TrackFX_GetParamNormalized = function() return 0.5 end,
  TrackFX_GetParam = function() return 0.5, 0, 1 end,
  TrackFX_GetParamEx = function() return 0.5, 0, 1, 0.5 end,
  TrackFX_GetFormattedParamValue = function() return true, "0.5" end,
  TrackFX_FormatParamValueNormalized = function(_, _, _, v) return true, string.format("%.2f", v) end,
  TrackFX_GetParamName = function(_, _, i) return true, "P" .. i end,
  TrackFX_GetNamedConfigParm = function() return false, "" end,
  TrackFX_GetEnabled = function() return true end,
  TrackFX_GetOffline = function() return false end,
  TrackFX_GetFXName = function() return true, "VST: Test" end,
  TrackFX_GetFXGUID = function() return "{FX}" end,
  TrackFX_GetCount = function() return 1 end,
  TrackFX_GetParameterStepSizes = function() return false end,
  GetMediaTrackInfo_Value = function() return 0 end,
  GetExtState = function() return "" end, HasExtState = function() return false end,
  time_precise = os.clock, GetPlayState = function() return 0 end,
  GetResourcePath = function() return "/nonexistent" end,
  gmem_read = function() return 0 end, gmem_attach = function() end,
  new_array = function(n) return setmetatable({}, { __index = function() return 0 end }) end,
  ValidatePtr2 = function() return true end, ValidatePtr = function() return true end,
  GetTrackGUID = function() return "{T}" end, GetProjectTimeSignature2 = function() return 120, 4 end,
  Master_GetTempo = function() return 120 end, GetSetProjectInfo = function() return 0 end,
  GetAppVersion = function() return "7.0" end, GetOS = function() return "Win64" end,
  CountTracks = function() return 1 end, GetTrack = function() return {} end, GetMasterTrack = function() return {} end,
  Track_GetPeakInfo = function() return 0 end, GetProjectStateChangeCount = function() return 1 end,
}, { __index = function(_, k) return function() return nil end end })
local bad = {}
CALLS, CHIPS, CUR = 0, {}, { 0, 0 }
local function sz(name, w, h)
  if not (w and h) or w <= 0 or h <= 0 or w ~= w or h ~= h then bad[#bad + 1] = ("%s %s x %s"):format(name, tostring(w), tostring(h)) end
end
local fake = setmetatable({
  InvisibleButton = function(_, id, w, h)
    sz("InvisibleButton " .. tostring(id), w, h)
    if tostring(id):find("^slim") then CHIPS[#CHIPS + 1] = { id = id, x = CUR[1], w = w } end
    return false
  end,
  SetCursorScreenPos = function(_, x, y) CUR = { x, y } end,
  Button = function(_, id, w, h) if w and h and (w < 0 or h < 0) then sz("Button " .. tostring(id), w, h) end return false end,
  BeginChild = function(_, id, w, h) if (w or 0) < 0 or (h or 0) < 0 then sz("BeginChild " .. tostring(id), w, h) end return false end,
  Dummy = function(_, w, h) if w < 0 or h < 0 then sz("Dummy", w, h) end end,
  CalcTextSize = function(_, t) return 6 * #tostring(t or ""), 12 end,
  GetMousePos = function() return -1000, -1000 end, GetMouseDelta = function() return 0, 0 end,
  GetCursorScreenPos = function() return 0, 0 end, GetCursorPos = function() return 0, 0 end,
  GetWindowPos = function() return 0, 0 end, GetWindowSize = function() return 800, 600 end,
  GetContentRegionAvail = function() return 800, 600 end,
  GetMouseWheel = function() return 0, 0 end, GetKeyMods = function() return 0 end,
  GetFontSize = function() return 13 end, GetFrameHeight = function() return 20 end,
  GetTime = function() return 0 end, GetFrameCount = function() return 1 end,
  GetWindowDrawList = function() return "dl" end, GetForegroundDrawList = function() return "fg" end,
  GetItemRectMin = function() return 0, 0 end, GetItemRectMax = function() return 0, 0 end,
  GetItemRectSize = function() return 0, 0 end, GetStyleVar = function() return 4 end,
  GetScrollX = function() return 0 end, GetScrollY = function() return 0 end,
  ValidatePtr = function() return true end, CreateImage = function() return nil end,
}, { __index = function(_, key)
  if key:find("^DrawList_") then return function() CALLS = CALLS + 1 return false end end
  if key:find("Flags_") or key:find("MouseButton_") or key:find("MouseCursor_") or key:find("^Mod_")
     or key:find("^Col_") or key:find("^StyleVar_") or key:find("^Key_") or key:find("^Cond_") or key:find("^Dir_") then return 1 end
  return function() return false end
end })
local C = require("TS_CV_Config")
local W = require("TS_CV_Widgets"); W.attach(fake)
local ok, CP = pcall(require, "TS_CV_CompPanel")
if not ok then print("CP load", CP) os.exit(1) end
CP.attach(fake)
local RP = require("TS_CV_RolePanel"); RP.attach(fake)
local M = require("TS_CV_Mappings")
local fails = 0
local kinds = { "comp", "gate", "limit", "deess", "delay", "reverb", "env", "mod", "sat" }
local fx = { addr = 0, guid = "{FX}", name = "VST: Test" }
for _, k in ipairs(kinds) do
  local roles = {}
  for i, r in ipairs(M.ROLES[k]) do roles[r] = i - 1 end
  local cv = { kind = k, roles = roles, rev = {} }
  for _, case in ipairs({ { 300, 200, false }, { 300, 128, true }, { 300, 64, true }, { 230, 64, true },
                           { 382, 64, "short" }, { 300, 128, "short" } }) do
    local w, h, tile = case[1], case[2], case[3]
    CP.TILE = (tile == true) or nil
    -- (a tile: its controls over the first 100 px, one of them on parameter 0)
    CP.TILE_X, CP.TILE_ON = CP.TILE and 100 or nil, CP.TILE and { [0] = true } or nil
    CHIPS = {}
    CP.SHORT = (tile == "short") or nil
    C.CANVAS_QUIET = tile and true or nil
    bad = {}; CALLS = 0
    local fn = RP.KINDS[k] and RP.draw or CP.draw_mapped
    local ok2, err = pcall(fn, "ctx", "dl", 0, 0, w, h, {}, fx, {}, cv)
    CP.TILE, CP.SHORT, C.CANVAS_QUIET, CP.TILE_X, CP.TILE_ON = nil, nil, nil, nil, nil
    -- a tile's own row of values, clear of its controls, not theirs again
    local row_bad
    if tile and k ~= "env" then
      if #CHIPS == 0 then row_bad = "no row of values" end
      for _, c in ipairs(CHIPS) do if c.x < ((tile == true) and 100 or 0) or c.x + c.w > w + 0.5 then row_bad = "a value out of its room" end end
    end
    if not ok2 or #bad > 0 or row_bad then fails = fails + 1 end
    print(("%-7s %3dx%-3d %s %4d draws  %s%s%s"):format(k, w, h, (tile == true) and "tile" or (tile and "shrt" or "    "), CALLS, ok2 and "ok" or ("ERR " .. tostring(err):sub(1, 140)),
      #bad > 0 and (#bad .. " bad sizes: " .. bad[1]) or "", row_bad and ("  " .. row_bad) or (tile and ("  " .. #CHIPS .. " values") or "")))
  end
end
print(fails == 0 and "\nALL PASS" or ("\n" .. fails .. " FAILURES"))
os.exit(fails == 0 and 0 or 1)
