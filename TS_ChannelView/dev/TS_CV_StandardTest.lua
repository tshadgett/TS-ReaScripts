-- @noindex  (a development tool, not a package)
--[[
  TS_CV_StandardTest.lua -- ChannelView Standard on its own: every
  Standard module loads, and none of Pro's is ever asked for (a require of
  one fails here, as it would where Pro isn't installed). Then what
  Standard does with a layout Pro made: draws its grid, ignores its other
  layouts, draws its controls plainly.

  lua5.4 dev/TS_CV_StandardTest.lua (from the TS_ChannelView folder or dev)
--]]

TS_CV_EDITION = "standard"
local here = (debug.getinfo(1, "S").source:match("@?(.*[\\/])") or "./")
package.path = here .. "../?.lua;" .. package.path

local PRO = {}
for _, n in ipairs({ "TS_CV_Pro", "TS_CV_GridEditor", "TS_CV_MapPanel", "TS_CV_MapEQ", "TS_CV_CompPanel",
                     "TS_CV_CanvasSetup", "TS_CV_EQPanel", "TS_CV_RolePanel", "TS_CV_Delay",
                     "TS_CV_Trimmer", "TS_CV_TrimmerPanel", "TS_CV_KnobEditor", "TS_CV_Recipes",
                     "TS_CV_Switches", "TS_CV_Finish", "TS_CV_Tiles", "TS_CV_PluginColours",
                     "TS_CV_Vendors", "TS_CV_Light" }) do PRO[n] = true end
local asked = {}
table.insert(package.searchers, 1, function(name)
  if PRO[name] then
    asked[#asked + 1] = name
    return "\n\tnot installed (ChannelView Pro)"
  end
end)

-- a REAPER that answers everything with nothing, and the few things
-- loading needs with something
local store = {}
reaper = setmetatable({
  GetResourcePath = function() return "/tmp" end,
  time_precise = function() return os.clock() end,
  GetExtState = function(s, k) return store[s .. "/" .. k] or "" end,
  SetExtState = function(s, k, v) store[s .. "/" .. k] = v end,
  HasExtState = function() return false end,
  GetProjExtState = function() return 0, "" end,
  SetProjExtState = function() end,
  GetAppVersion = function() return "7.20/x64" end,
  file_exists = function() return false end,
  GetOS = function() return "Win64" end,
  ImGui_GetBuiltinPath = function() return "/tmp" end,
}, { __index = function() return function() return nil end end })

local fails = 0
local function check(name, got, want)
  local ok = got == want
  if not ok then fails = fails + 1 end
  print(("%s %-46s %s"):format(ok and "ok  " or "FAIL", name, ok and tostring(got) or ("got " .. tostring(got) .. "  want " .. tostring(want))))
end

local ED = require("TS_CV_Edition")
check("Standard: no Pro", ED.PRO, nil)

-- every Standard module loads: each [nomain] TS_CV_*.lua in TS_ChannelView.lua's
-- @provides (what Standard installs), so the TCP window's and the
-- toolbars' modules are covered too
local STD = {}
do
  local fh = assert(io.open(here .. "../TS_ChannelView.lua"))
  local on = false
  for line in fh:lines() do
    if line:match("^%-%- @provides") then on = true
    elseif on and line:match("^%-%- @") then break
    elseif on then
      local m = line:match("^%-%-%s+%[nomain%]%s+(TS_CV_[%w_]+)%.lua")
      if m and m ~= "TS_CV_Edition" then STD[#STD + 1] = m end
    end
  end
  fh:close()
end
check("Standard modules found", #STD > 30, true)
for _, n in ipairs(STD) do
  local ok, err = pcall(require, n)
  check("loads: " .. n, ok and "ok" or tostring(err):sub(1, 120), "ok")
end
local nasked = {}
for _, n in ipairs(asked) do if n ~= "TS_CV_Pro" then nasked[#nasked + 1] = n end end
check("no Pro module required outright", #nasked == 0 or table.concat(nasked, ","), true)

local P = require("TS_CV_Panel")
local St = require("TS_CV_State")
local W = require("TS_CV_Widgets")

-- a grid Pro made: drawn as it is
local g = { { type = "knob", param = 0, at = { c = 0, r = 0, w = 4, h = 4 } },
            { type = "knob", param = 1, at = { c = 4, r = 0, w = 4, h = 4 } },
            { type = "section", style = "plate", cap = "cream", at = { c = 0, r = 0, w = 8, h = 4 } },
            { type = "divider", at = { c = 8, r = 4, w = 4, h = -4 } } }
g.grid = { cols = 12, rows = 4 }
local lay = P.layout(g, 400)
check("a grid drawn as it is", #lay.items .. " " .. lay.items[2].x .. " " .. #lay.segs, "2 " .. P.qx(4) .. " 1")

-- other layouts and switching rules: the plugin's own, always
check("the plugin's own layout", St.layout_key("VST: Some Comp (Vendor)", "{g}", nil, nil), "Some Comp")
-- the trace stays closed
St.set_gr_open("{g}", true)
check("no trace", St.is_gr_open("{g}"), false)
-- plain controls
local o = W.plain({ style = "chicken", cap = "red", look = {}, bipolar = true })
check("controls drawn plainly", tostring(o.style) .. tostring(o.cap) .. tostring(o.look) .. tostring(o.bipolar), "nilnilniltrue")
-- a canvas layout: its controls, as an ordinary panel
check("no canvas", P.canvas_of({ canvas = { kind = "eq" } }), nil)
check("ReaEQ an ordinary plugin", P.own_eq("ReaEQ"), false)

-- a grid panel drawn whole, with no Pro to call: words, a picture, a step
-- button and a section with a picture of its own (they draw plainly)
local function fakeimgui()
  local num = { CalcTextSize = function(_, t) return #(t or "") * 6, 13 end, GetFontSize = function() return 13 end,
    GetCursorScreenPos = function() return 0, 0 end, GetContentRegionAvail = function() return 600, 400 end,
    GetWindowPos = function() return 0, 0 end, GetWindowSize = function() return 600, 400 end,
    GetMousePos = function() return -1, -1 end, GetFrameHeight = function() return 20 end,
    BeginChild = function() return true end, Begin = function() return true, true end,
    GetFrameCount = function() return 1 end, GetTime = function() return 0 end,
    GetItemRectMin = function() return 0, 0 end, GetItemRectMax = function() return 10, 10 end,
    GetMouseDelta = function() return 0, 0 end, GetMouseWheel = function() return 0, 0 end, GetKeyMods = function() return 0 end,
    GetStyleVar = function() return 4, 4 end, GetScrollY = function() return 0 end, GetScrollMaxY = function() return 0 end,
    GetWindowDrawList = function() return "dl" end, GetForegroundDrawList = function() return "dl" end,
    GetTextLineHeight = function() return 13 end, GetCursorPosX = function() return 0 end, GetCursorPosY = function() return 0 end,
    GetMouseClickedPos = function() return 0, 0 end, GetDisplaySize = function() return 1600, 900 end,
    GetMainViewport = function() return "vp" end, Viewport_GetPos = function() return 0, 0 end, Viewport_GetSize = function() return 1600, 900 end,
    Viewport_GetWorkPos = function() return 0, 0 end, Viewport_GetWorkSize = function() return 1600, 900 end }
  return setmetatable(num, { __index = function(_, k)
    if type(k) == "string" and k:match("^%u%a*_%u") and not k:match("^DrawList_") and not k:match("^Viewport_") then return 1 end
    return function() return false end
  end })
end
local fake = fakeimgui()
local mods = { "TS_CV_Panel", "TS_CV_Widgets", "TS_CV_Switches" }
for _, n in ipairs(mods) do local ok, m = pcall(require, n); if ok and m and m.attach then pcall(m.attach, fake) end end
require("TS_CV_Widgets").attach(fake)
P.attach(fake)
reaper.TrackFX_GetNumParams = function() return 8 end
reaper.TrackFX_GetParamNormalized = function() return 0.5 end
reaper.TrackFX_GetParamEx = function() return 0.5, 0, 1, 0.5 end
reaper.TrackFX_GetFormattedParamValue = function() return true, "0.5" end
reaper.TrackFX_GetParamName = function(_, _, p) return true, "P" .. p end
reaper.TrackFX_GetEnabled = function() return true end
reaper.TrackFX_GetFXName = function() return true, "VST: Some Comp (Vendor)" end
reaper.ValidatePtr2 = function() return true end
reaper.ValidatePtr = function() return true end
local M = require("TS_CV_Mappings")
local lay2 = { controls = {
  { type = "knob", param = 0, label = "Gain", at = { c = 0, r = 0, w = 4, h = 4 } },
  { type = "text", param = -1, label = "HELLO", at = { c = 4, r = 0, w = 8, h = 2 } },
  { type = "image", param = -1, label = "", pic = { file = "x.png", fill = "fit", op = 100, rr = 0 }, at = { c = 4, r = 2, w = 8, h = 2 } },
  { type = "combo", param = 1, label = "Mode", buttons = "step", nbtn = 3, at = { c = 12, r = 0, w = 4, h = 4 } },
  { type = "section", param = -1, finish = "img:foo.png|edges|16", at = { c = 0, r = 0, w = 16, h = 4 } } },
  grid = { cols = 16, rows = 4 } }
local fx = { addr = 0, guid = "{std}", name = "VST: Some Comp (Vendor)" }
local ok, err = pcall(P.draw, "ctx", "tr", fx, lay2, "Some Comp", 300, 1, false)
check("Standard: a grid panel drawn (text, image, step button)", ok and "ok" or tostring(err):sub(1, 200), "ok")
-- measuring gain knobs is Standard's: Learn loads without Pro's EQ code,
-- and a measured plugin's panel (its note to check them) draws
local okl, LNs = pcall(require, "TS_CV_Learn")
check("Standard: gain measuring there", okl and type(LNs.start_gain), "function")
check("Standard: the gain knob check there", type(require("TS_CV_GainCheck").open), "function")
lay2.measure = true
ok, err = pcall(P.draw, "ctx", "tr", fx, lay2, "Some Comp", 300, 1, false)
check("Standard: a measured plugin's panel drawn", ok and "ok" or tostring(err):sub(1, 200), "ok")

print(fails == 0 and "\nALL PASS" or ("\n" .. fails .. " FAILURES"))
os.exit(fails == 0 and 0 or 1)
