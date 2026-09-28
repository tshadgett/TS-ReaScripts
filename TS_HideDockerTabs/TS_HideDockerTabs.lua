-- @description TS_HideDockerTabs - toggle hiding the tab strip on all dockers
-- @author Tim Shadgett
-- @version 0.5
-- @about
--   Toggle action. While ON, the window shown in every docker (main-window
--   dockers and floating dockers) is stretched over the docker's tab strip, so
--   the tabs take no space. Run again to turn OFF and bring the tabs back.
--   Requires js_ReaScriptAPI.

local r = reaper

if not r.JS_Window_ListAllChild then
  r.MB("TS_HideDockerTabs needs the js_ReaScriptAPI extension (install via ReaPack).",
       "TS_HideDockerTabs", 0)
  return
end

----------------------------------------------------------------------------
-- Settings
----------------------------------------------------------------------------
local TAB_CLASS    = "WDLTabCtrl"   -- window class of REAPER's docker tab strip
local MAX_GAP      = 60             -- never reclaim more than this many px per edge
local FIX_INTERVAL = 0.05           -- seconds between layout checks
local SCAN_INTERVAL = 1.0           -- seconds between re-finding docker windows
local DEBUG        = false          -- print what is happening to the console

----------------------------------------------------------------------------
-- Toggle state
----------------------------------------------------------------------------
local _, _, sec, cmd = r.get_action_context()
local function set_toggle(on)
  if r.set_action_options then
    -- 1 = relaunching the script terminates this instance (no prompt)
    -- 4 = toggle ON, 8 = toggle OFF
    r.set_action_options(on and (1 | 4) or 8)
  else
    r.SetToggleCommandState(sec, cmd, on and 1 or 0)
    r.RefreshToolbar2(sec, cmd)
  end
end
set_toggle(true)

local function log(...)
  if DEBUG then r.ShowConsoleMsg(table.concat({...}, " ") .. "\n") end
end

----------------------------------------------------------------------------
-- Window helpers
----------------------------------------------------------------------------
local function handles(list)
  local out = {}
  if not list or list == "" then return out end
  for a in list:gmatch("[^,]+") do
    local h = r.JS_Window_HandleFromAddress(tonumber(a))
    if h then out[#out + 1] = h end
  end
  return out
end

local function children(parent)
  local n, list = r.JS_Window_ListAllChild(parent)
  if not n or n < 1 then return {} end
  return handles(list)
end

local function key(h) return tostring(r.JS_Window_AddressFromHandle(h)) end

local main = r.GetMainHwnd()
local dockers = {}

local function scan()
  local found, seen = {}, {}
  -- A docker is the window that holds a docker tab strip (WDLTabCtrl)
  local function consider(h)
    if r.JS_Window_GetClassName(h) == TAB_CLASS then
      local d = r.JS_Window_GetParent(h)
      if d and d ~= main then
        local k = key(d)
        if not seen[k] then seen[k] = true; found[#found + 1] = d end
      end
    end
  end
  -- dockers attached to the main window
  for _, h in ipairs(children(main)) do consider(h) end
  -- floating dockers: top-level windows owned by REAPER's main window
  local n, list = r.JS_Window_ListAllTop()
  if n and n > 0 then
    for _, top in ipairs(handles(list)) do
      if r.JS_Window_GetRelated(top, "OWNER") == main then
        consider(top)
        for _, h in ipairs(children(top)) do consider(h) end
      end
    end
  end
  if #found ~= #dockers then log("dockers found:", #found) end
  dockers = found
end

----------------------------------------------------------------------------
-- Layout fix
----------------------------------------------------------------------------
local modified = {}   -- [key] = {h=, d=, gL=, gT=, gR=, gB=}
local hiddenTabs = {} -- [key] = hwnd of any separate tab control we hid
local lastReason = {} -- [docker key] = last debug message (avoid spam)

local function why(d, msg)
  local k = key(d)
  if lastReason[k] ~= msg then
    lastReason[k] = msg
    log(string.format("[docker %s] %s", k, msg))
  end
end

local function norm(ok, a, b, c, e)
  -- return left, top, right, bottom with top < bottom
  return math.min(a, c), math.min(b, e), math.max(a, c), math.max(b, e)
end

local function set_rect_screen(d, h, L, T, R, B)
  local x1, y1 = r.JS_Window_ScreenToClient(d, L, T)
  local x2, y2 = r.JS_Window_ScreenToClient(d, R, B)
  r.JS_Window_SetPosition(h, math.min(x1, x2), math.min(y1, y2),
                          math.abs(x2 - x1), math.abs(y2 - y1))
end

local function fix_docker(d)
  if not r.JS_Window_IsVisible(d) then return end
  local ok = r.JS_Window_GetClientRect(d)
  if not ok then return end
  local L, T, R, B = norm(r.JS_Window_GetClientRect(d))

  -- direct children: the tab strip (visible or already hidden) and content
  local content, tab = {}, nil
  for _, h in ipairs(children(d)) do
    if r.JS_Window_GetParent(h) == d then
      local cls = r.JS_Window_GetClassName(h) or ""
      if cls == TAB_CLASS then
        tab = h
        if r.JS_Window_IsVisible(h) then
          r.JS_Window_Show(h, "HIDE")
          hiddenTabs[key(h)] = h
        end
      elseif r.JS_Window_IsVisible(h) then
        content[#content + 1] = h
      end
    end
  end
  if not tab then return end
  if #content ~= 1 then
    local names = {}
    for _, h in ipairs(content) do names[#names + 1] = r.JS_Window_GetClassName(h) or "?" end
    why(d, string.format("skipped: %d visible content windows (%s)", #content, table.concat(names, ", ")))
    return
  end
  local k = content[1]

  -- Grow the content ONLY over the tab strip's area (the union of the two
  -- rects). Any other margin -- e.g. the docker's resize edge -- is left alone.
  local tL, tT, tR, tB = norm(r.JS_Window_GetRect(tab))
  local kL, kT, kR, kB = norm(r.JS_Window_GetRect(k))
  if tB - tT <= 0 or tR - tL <= 0 then return end
  if tB - tT > MAX_GAP and tR - tL > MAX_GAP then
    why(d, "skipped: tab strip bigger than MAX_GAP both ways"); return
  end
  local nL, nT = math.max(L, math.min(kL, tL)), math.max(T, math.min(kT, tT))
  local nR, nB = math.min(R, math.max(kR, tR)), math.min(B, math.max(kB, tB))
  if nL == kL and nT == kT and nR == kR and nB == kB then
    why(d, "filling OK"); return
  end

  set_rect_screen(d, k, nL, nT, nR, nB)

  local kk = key(k)
  local gL, gT, gR, gB = kL - L, kT - T, R - kR, B - kB
  local m = modified[kk]
  if not m or m.d ~= d then
    modified[kk] = { h = k, d = d, gL = gL, gT = gT, gR = gR, gB = gB }
  else
    m.gL, m.gT = math.max(m.gL, gL), math.max(m.gT, gT)
    m.gR, m.gB = math.max(m.gR, gR), math.max(m.gB, gB)
  end
  why(d, string.format("filled over tab strip (%dx%d)", tR - tL, tB - tT))
end

----------------------------------------------------------------------------
-- Restore on exit (toggle OFF)
----------------------------------------------------------------------------
local function restore()
  for _, h in pairs(hiddenTabs) do
    if r.JS_Window_IsWindow(h) then r.JS_Window_Show(h, "SHOW") end
  end
  for _, m in pairs(modified) do
    if r.JS_Window_IsWindow(m.h) and r.JS_Window_IsWindow(m.d) then
      local L, T, R, B = norm(r.JS_Window_GetClientRect(m.d))
      set_rect_screen(m.d, m.h, L + m.gL, T + m.gT, R - m.gR, B - m.gB)
    end
  end
  r.DockWindowRefresh()
  r.UpdateArrange()
  set_toggle(false)
end
r.atexit(restore)

----------------------------------------------------------------------------
-- Main loop
----------------------------------------------------------------------------
local lastFix, lastScan = 0, -math.huge
local warned = false

local function loop()
  local now = r.time_precise()
  if now - lastScan >= SCAN_INTERVAL then
    scan()
    lastScan = now
    if #dockers == 0 and not warned then
      warned = true
      r.ShowConsoleMsg("TS_HideDockerTabs: no dockers found (no '" .. TAB_CLASS ..
        "' windows). Window tree under the main window:\n")
      for _, h in ipairs(children(main)) do
        local p = r.JS_Window_GetParent(h)
        r.ShowConsoleMsg(string.format("  %s  (parent: %s)\n",
          r.JS_Window_GetClassName(h) or "?",
          p and (r.JS_Window_GetClassName(p) or "?") or "-"))
      end
    end
  end
  if now - lastFix >= FIX_INTERVAL then
    for _, d in ipairs(dockers) do
      if r.JS_Window_IsWindow(d) then fix_docker(d) end
    end
    lastFix = now
  end
  r.defer(loop)
end

loop()
