-- @noindex
-- Not a package of its own: installed by TS_ChannelView.lua's @provides.
--[[
  TS_CV_Edition.lua -- which ChannelView this is: Standard, or Standard
  with the Pro add-on.

  Pro is a package of its own (from its own ReaPack link) holding only
  its own files; TS_CV_Pro.lua is its marker. Standard runs without any
  of them, and turns each Pro feature on when it finds them, of the same
  release as itself (one built for another release is left alone, and
  ED.mismatch says which it was).

  ED.PRO          the Pro marker, or nil
  ED.module(n)    a Pro module, or nil without Pro
  ED.module(n, stub)  ... or `stub` without Pro: the same names, doing
                  nothing (for modules called from many places)
  ED.item(...)    a Pro menu item: as ImGui.MenuItem with Pro; greyed
                  "(Pro)" with a tooltip without it
  ED.note(ctx)    the tooltip for anything greyed for Pro

  Where the two packages put their files (ReaPack: Scripts/<repo>/<category>)
  is added to package.path as this loads (ED.paths), so Standard's scripts
  find Pro's files; Pro's own scripts add Standard's folder themselves.

  TS_CV_EDITION = "standard" (a global, set before this loads) makes it
  Standard whatever is installed: the tests, and trying Standard out.
--]]

local ED = {}

-- the release both editions are; Pro must be the same
ED.RELEASE = "3.3.0"

-- where ReaPack puts each edition's files, under REAPER's Scripts
ED.STANDARD_DIR = "TS-ReaScripts/TS_ChannelView/"
ED.PRO_DIR      = "TS-ChannelView-Pro/TS_ChannelView/"

-- package.path entries for both editions' folders, after `own` (the
-- folder of the script starting up)
function ED.paths(own)
  local res = (reaper and reaper.GetResourcePath and reaper.GetResourcePath() or ".") .. "/Scripts/"
  return own .. "?.lua;" .. res .. ED.STANDARD_DIR .. "?.lua;" .. res .. ED.PRO_DIR .. "?.lua;"
end

-- both folders, wherever this was loaded from: so Standard's scripts find
-- Pro's files, and Pro's scripts Standard's
do
  local own = debug.getinfo(1, "S").source:match("@?(.*[\\/])") or ""
  package.path = ED.paths(own) .. package.path
end

do
  local forced = rawget(_G, "TS_CV_EDITION") == "standard"
  local ok, pro = false, nil
  if not forced then ok, pro = pcall(require, "TS_CV_Pro") end
  if ok and type(pro) == "table" then
    if pro.RELEASE == ED.RELEASE then ED.PRO = pro
    else ED.mismatch = tostring(pro.RELEASE) end
  end
end

function ED.module(name, stub)
  if ED.PRO then
    local ok, m = pcall(require, name)
    if ok then return m end
  end
  return stub or nil
end

-- A stand-in for a module Standard calls from many places: every name a
-- function that does nothing (returns nil), apart from those in `fields`.
function ED.stub(fields)
  return setmetatable(fields or {}, { __index = function() return function() return nil end end })
end

-- Lighting (TS_CV_Light) without Pro: the same light, casting no shadows.
function ED.light()
  return ED.module("TS_CV_Light") or (function()
    local a = math.atan(-0.8, -0.6)
    return { STRENGTH = 0, A = a, UX = math.cos(a), UY = math.sin(a),
             attach = function() end, circle = function() end, rect = function() end,
             drop = function() return {}, 0 end, offset = function() return 0, 0, 0 end,
             shade = function() return 0 end }
  end)()
end
-- Hardware switch styles (TS_CV_Switches) without Pro: none.
function ED.switches()
  return ED.module("TS_CV_Switches") or { attach = function() end, is = function() return false end,
                                          draw = function() end }
end

-- Pro installed at another version (ED.mismatch, its release): what to
-- say, naming the one that's behind.
local function newer(a, b)
  local x, y = {}, {}
  for d in a:gmatch("%d+") do x[#x + 1] = tonumber(d) end
  for d in b:gmatch("%d+") do y[#y + 1] = tonumber(d) end
  for i = 1, math.max(#x, #y) do
    if (x[i] or 0) ~= (y[i] or 0) then return (x[i] or 0) > (y[i] or 0) end
  end
  return false
end
-- The one to update: "ChannelView" or "ChannelView Pro".
function ED.behind()
  if not ED.mismatch then return nil end
  return newer(ED.mismatch, ED.RELEASE) and "ChannelView" or "ChannelView Pro"
end
function ED.mismatch_text()
  if not ED.mismatch then return nil end
  local pro_newer = ED.behind() == "ChannelView"
  return ("ChannelView is %s and ChannelView Pro is %s. They have to be the same version, " ..
          "so Pro is switched off for now.\n\nUpdate %s: Extensions > ReaPack > Synchronize packages%s, " ..
          "then restart ChannelView."):format(ED.RELEASE, ED.mismatch,
          pro_newer and "ChannelView" or "ChannelView Pro",
          pro_newer and "" or " (Pro comes from its own ReaPack link: check it's still in ReaPack's repositories)")
end
-- The message box, once for each pair of versions (or every time, `always`).
function ED.warn_mismatch(always)
  if not ED.mismatch then return end
  local pair = ED.RELEASE .. "|" .. ED.mismatch
  if not always and reaper.GetExtState("TS_ChannelView", "edition_warned") == pair then return end
  reaper.SetExtState("TS_ChannelView", "edition_warned", pair, true)
  reaper.ShowMessageBox(ED.mismatch_text(), "ChannelView", 0)
end

ED.NOTE = "In ChannelView Pro."
function ED.note(ImGui, ctx)
  if ImGui.IsItemHovered(ctx, ImGui.HoveredFlags_AllowWhenDisabled) then
    ImGui.SetTooltip(ctx, ED.mismatch and ("In ChannelView Pro. " .. ED.mismatch_text()) or ED.NOTE)
  end
end

-- A Pro menu item: ImGui.MenuItem's arguments; true when chosen (never
-- without Pro, where it's greyed and says so).
function ED.item(ImGui, ctx, label, shortcut, selected, enabled)
  if enabled == nil then enabled = true end
  selected, shortcut = selected or false, shortcut or nil
  if ED.PRO then return ImGui.MenuItem(ctx, label, shortcut, selected, enabled) end
  ImGui.MenuItem(ctx, label .. "  (Pro)", nil, false, false)
  ED.note(ImGui, ctx)
  return false
end

-- A Pro submenu: as ImGui.BeginMenu with Pro; a greyed item without it.
function ED.menu(ImGui, ctx, label, enabled)
  if enabled == nil then enabled = true end
  if ED.PRO then return ImGui.BeginMenu(ctx, label, enabled) end
  ImGui.MenuItem(ctx, label .. "  (Pro)", nil, false, false)
  ED.note(ImGui, ctx)
  return false
end

return ED
