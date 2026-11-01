-- @noindex  (a development tool, not a package)
--[[
  TS_CV_DockProbe.lua -- can a script widen the docker ChannelView's TCP
  window sits in? (For the TCP patch bay, which wants the docker wider
  while it's open.)

  Run it with the ChannelView TCP window docked. It opens a small window
  of its own as a tab in the same docker, finds the docker, and offers
  two ways of widening it by 150 px:

    A  REAPER's own setting for that side's docker width (the reaper.ini
       value, through SWS), then a docker refresh
    B  resizing the docker's window directly (js_ReaScriptAPI)

  After each, the docker's width and the arrange view's left edge are
  read again at once, after half a second and after two seconds, so we
  can see whether REAPER keeps it, moves the arrange view, or snaps it
  back. "Put it back" restores the width it started with.

  Everything goes in the window and into dev/dockprobe.txt beside this
  script. Send me that file.

  Second round (the first found the arrange view, not the docker, and
  SWS couldn't write the setting as an int): the docker is now found from
  the TCP window itself; the setting is read as int, double and long to
  see which SWS knows it as, and written as that; and C nudges REAPER's
  main window a pixel and back, which makes it lay the dockers out again.

  Third round (A and C: REAPER won't take the setting from SWS; B sizes
  the docker but REAPER doesn't move the arrange view to suit): D drags
  the splitter between the docker and the arrange view the way a mouse
  would, with window messages to REAPER's main window; E does the same
  while really moving the pointer there (and puts it back after). Each
  has its own "back" button that drags the same amount the other way.

  REAPER's own TCP is still there between the docker and the arrange view,
  squeezed to nothing, with a divider of its own. D and E aim at the
  docker's edge (the 2 px just right of it, left of REAPER's TCP); F drags
  REAPER's TCP divider instead (between its TCP and the arrange view), to
  see whether that one moves the arrange view (logged either way: the
  docker's width and the arrange view's left edge both).
--]]

local own = debug.getinfo(1, "S").source:match("@?(.*[\\/])") or ""
local LOG = own .. "dockprobe.txt"

if not reaper.JS_Window_FindChildByID then
  reaper.MB("This needs js_ReaScriptAPI (ReaPack).", "Dock probe", 0) return
end
package.path = reaper.ImGui_GetBuiltinPath() .. "/?.lua;" .. package.path
local ImGui = require("imgui")("0.10")

local ctx = ImGui.CreateContext("TS Dock Probe")
local lines = {}
local function log(fmt, ...)
  local s = (select("#", ...) > 0) and fmt:format(...) or fmt
  lines[#lines + 1] = s
  local f = io.open(LOG, "a")
  if f then f:write(s, "\n") f:close() end
end
log("==== %s  REAPER %s  SWS %s", os.date("%Y-%m-%d %H:%M:%S"), reaper.GetAppVersion(),
  reaper.SNM_GetIntConfigVar and "yes" or "no")

-- the TCP window's docker, so this opens as a tab beside it
local tcp_dock = tonumber(reaper.GetExtState("TS_ChannelView_TCP", "dock")) or 0
log("ChannelView TCP dock id (saved): %d", tcp_dock)

local main = reaper.GetMainHwnd()
local function rect(h)
  if not h then return nil end
  local ok, l, t, r, b = reaper.JS_Window_GetRect(h)
  if not ok then return nil end
  return l, t, r, b
end
local function arrange_left()
  local a = reaper.JS_Window_FindChildByID(main, 1000)
  local l = rect(a)
  return l
end

local CFG = { "dockheight_l", "dockheight_r", "dockheight_t", "dockheight" }
local function cfg_all()
  local out = {}
  for _, k in ipairs(CFG) do
    local ok, s = reaper.get_config_var_string(k)
    out[#out + 1] = k .. "=" .. (ok and s or "?")
  end
  return table.concat(out, "  ")
end

-- which SWS getter knows the setting, and its value that way
local function cfg_types(k)
  local res = {}
  local ok, s = reaper.get_config_var_string(k)
  res[#res + 1] = "string=" .. (ok and s or "?")
  if reaper.SNM_GetIntConfigVar then res[#res + 1] = "int=" .. tostring(reaper.SNM_GetIntConfigVar(k, -99999)) end
  if reaper.SNM_GetDoubleConfigVar then res[#res + 1] = "double=" .. tostring(reaper.SNM_GetDoubleConfigVar(k, -99999)) end
  if reaper.SNM_GetLongConfigVar then
    local hi, lo = reaper.SNM_GetLongConfigVar(k)
    res[#res + 1] = "long=" .. tostring(hi) .. "," .. tostring(lo)
  end
  return table.concat(res, "  ")
end
local function cfg_get(k)
  local ok, s = reaper.get_config_var_string(k)
  return ok and tonumber(s) or nil
end
-- written the first way that reads back right
local function cfg_set(k, v)
  local tries = {
    { "int",    function() return reaper.SNM_SetIntConfigVar and reaper.SNM_SetIntConfigVar(k, math.floor(v)) end },
    { "double", function() return reaper.SNM_SetDoubleConfigVar and reaper.SNM_SetDoubleConfigVar(k, v) end },
  }
  for _, t in ipairs(tries) do
    local okc = t[2]()
    local back = cfg_get(k)
    log("   set as %s: call %s, reads back %s", t[1], tostring(okc), tostring(back))
    if back == v then return true end
  end
  return false
end

-- REAPER lays its dockers out again when its window changes size
local function nudge_main()
  local ok, l, t, r, b = reaper.JS_Window_GetRect(main)
  if not ok then return end
  reaper.JS_Window_Resize(main, r - l, b - t - 1)
  reaper.JS_Window_Resize(main, r - l, b - t)
end

-- found once docked: the chain of windows from ours up to REAPER's main
local chain, docker, side_key, start_w, start_cfg
local SIDES = { [0] = "bottom", [1] = "left", [2] = "top", [3] = "right", [4] = "floating" }
local SIDE_KEY = { [0] = "dockheight", [1] = "dockheight_l", [2] = "dockheight_t", [3] = "dockheight_r" }

local function find_chain()
  local h = reaper.JS_Window_Find("ChannelView TCP", true)
  log("ChannelView TCP window: %s", tostring(h))
  if not h then h = reaper.JS_Window_Find("TS Dock Probe", true); log("this window: %s", tostring(h)) end
  chain = {}
  local guard = 0
  while h and guard < 12 do
    guard = guard + 1
    local l, t, r, b = rect(h)
    chain[#chain + 1] = { h = h, cls = reaper.JS_Window_GetClassName(h) or "?",
      title = reaper.JS_Window_GetTitle(h) or "", w = l and (r - l) or -1, hgt = t and (b - t) or -1 }
    if h == main then break end
    h = reaper.JS_Window_GetParent(h)
  end
  log("window chain, from this window up:")
  for i, e in ipairs(chain) do
    log("  %d  class=%-24s w=%5d h=%5d  title=%q%s", i, e.cls, e.w, e.hgt, e.title, e.h == main and "  (main)" or "")
  end
  -- the docker: the last window before the main one
  for i = #chain, 1, -1 do
    if chain[i].h == main and i > 1 then docker = chain[i - 1].h break end
  end
  if docker then
    local l, _, r = rect(docker)
    start_w = r - l
    log("docker taken as the window under main: w=%d", start_w)
  else
    log("no docker found under the main window")
  end
end

local checks = {}           -- pending reads: { at = time, what = label }
local function read_now(what)
  local l, _, r = rect(docker)
  log("  %-18s docker w=%s  arrange left=%s  %s", what, l and tostring(r - l) or "?", tostring(arrange_left()), cfg_all())
end
local function schedule(label)
  read_now(label .. " +0s")
  local now = reaper.time_precise()
  checks[#checks + 1] = { at = now + 0.5, what = label .. " +0.5s" }
  checks[#checks + 1] = { at = now + 2.0, what = label .. " +2s" }
end

local function method_a(delta, nudge)
  if not side_key then log("A: no side for this docker") return end
  local v = cfg_get(side_key)
  if not v then log("A: can't read %s", side_key) return end
  log("%s: %s %d -> %d, then DockWindowRefresh%s", nudge and "C" or "A", side_key, v, v + delta,
    nudge and " and a main-window nudge" or "")
  cfg_set(side_key, v + delta)
  reaper.DockWindowRefresh()
  if nudge then nudge_main() end
  schedule(nudge and "C" or "A")
end

local function method_b(delta)
  if not docker then log("B: no docker") return end
  if reaper.JS_Window_GetClassName(docker) == "REAPERTrackListWindow" then
    log("B: that's the arrange view, not a docker -- skipped") return
  end
  local l, t, r, b = rect(docker)
  log("B: JS_Window_Resize docker %d -> %d, then DockWindowRefresh", r - l, r - l + delta)
  reaper.JS_Window_Resize(docker, r - l + delta, b - t)
  reaper.DockWindowRefresh()
  schedule("B")
end

-- the splitter: just right of the docker, half way down it, in the main
-- window's client coordinates
local function splitter_at()
  local l, t, r, b = rect(docker)
  if not l then return nil end
  local sx, sy = r + 1, math.floor((t + b) / 2)
  local cx, cy = reaper.JS_Window_ScreenToClient(main, sx, sy)
  return sx, sy, cx, cy
end
-- REAPER's own TCP's divider: between its TCP and the arrange view
local function tcp_divider_at()
  local n, list = reaper.JS_Window_ListAllChild(main)
  local tl, tr
  for addr in (list or ""):gmatch("[^,]+") do
    local c = reaper.JS_Window_HandleFromAddress(addr)
    if c and reaper.JS_Window_GetClassName(c) == "REAPERTCPDisplay" then
      local l, _, r = rect(c)
      tl, tr = l, r
    end
  end
  local al, at, _, ab = rect(reaper.JS_Window_FindChildByID(main, 1000))
  if not (tr and al) then return nil end
  log("  REAPER's TCP x=%d..%d, arrange left=%d", tl, tr, al)
  local sx, sy = math.floor((tr + al) / 2), math.floor((at + ab) / 2)
  local cx, cy = reaper.JS_Window_ScreenToClient(main, sx, sy)
  return sx, sy, cx, cy
end

-- the docker's edge again, one pixel further left (its first gap pixel)
local function splitter_at_edge()
  local l, t, r, b = rect(docker)
  if not l then return nil end
  local sx, sy = r, math.floor((t + b) / 2)
  local cx, cy = reaper.JS_Window_ScreenToClient(main, sx, sy)
  return sx, sy, cx, cy
end

local function drag_splitter(delta, real, label, where, target)
  if not docker or reaper.JS_Window_GetClassName(docker) == "REAPERTrackListWindow" then
    log("%s: no docker", label) return
  end
  local sx, sy, cx, cy = (where or splitter_at)()
  local to = target or main
  if target then cx, cy = reaper.JS_Window_ScreenToClient(target, sx, sy) end
  if not sx then log("%s: couldn't find it", label) return end
  local ok_m, mx, my = true, reaper.GetMousePosition()
  log("%s: splitter at screen %d,%d = client %d,%d; drag %+d%s", label, sx, sy, cx, cy, delta,
    real and " (moving the pointer too)" or "")
  local function msg(m, x)
    if real then reaper.JS_Mouse_SetPosition(sx + (x - cx), sy) end
    return reaper.JS_WindowMessage_Send(to, m, (m == "WM_LBUTTONUP") and 0 or 1, 0, x, cy)
  end
  msg("WM_MOUSEMOVE", cx)
  msg("WM_LBUTTONDOWN", cx)
  local steps = 10
  for i = 1, steps do msg("WM_MOUSEMOVE", cx + math.floor(delta * i / steps)) end
  msg("WM_LBUTTONUP", cx + delta)
  if real and ok_m then reaper.JS_Mouse_SetPosition(mx, my) end
  schedule(label)
end

local function put_back()
  if side_key and start_cfg and cfg_get(side_key) ~= start_cfg then cfg_set(side_key, start_cfg) end
  if docker and start_w then
    local l, t, r, b = rect(docker)
    if r - l ~= start_w then reaper.JS_Window_Resize(docker, start_w, b - t) end
  end
  reaper.DockWindowRefresh()
  nudge_main()
  schedule("put back")
end

local first = true
local function frame()
  if first and tcp_dock ~= 0 then ImGui.SetNextWindowDockID(ctx, tcp_dock, ImGui.Cond_Once) end
  ImGui.SetNextWindowSize(ctx, 560, 360, ImGui.Cond_FirstUseEver)
  local visible, open = ImGui.Begin(ctx, "TS Dock Probe", true)
  if visible then
    local id = ImGui.GetWindowDockID(ctx)
    if id < 0 and not chain then
      local idx = -id - 1
      local pos = reaper.DockGetPosition(idx)
      side_key = SIDE_KEY[pos]
      log("docked: dock id %d -> docker %d, side %s (%s)", id, idx, SIDES[pos] or tostring(pos), side_key or "-")
      log("start: %s  arrange left=%s", cfg_all(), tostring(arrange_left()))
      if side_key then start_cfg = cfg_get(side_key) end
      log("%s: %s", side_key or "-", side_key and cfg_types(side_key) or "")
      find_chain()
      -- REAPER's main window's own children, left of the arrange view
      local n, list = reaper.JS_Window_ListAllChild(main)
      log("main's direct children at the left (%d windows in all):", n or 0)
      for addr in (list or ""):gmatch("[^,]+") do
        local c = reaper.JS_Window_HandleFromAddress(addr)
        if c and reaper.JS_Window_GetParent(c) == main then
          local l, t, r, b = rect(c)
          if l and l < 1200 then
            log("  class=%-24s x=%5d w=%5d h=%5d title=%q", reaper.JS_Window_GetClassName(c) or "?",
              l, r - l, b - t, reaper.JS_Window_GetTitle(c) or "")
          end
        end
      end
    elseif id >= 0 then
      ImGui.TextWrapped(ctx, "Dock this window in the same docker as the ChannelView TCP window.")
    end
    if chain then
      if ImGui.Button(ctx, "A: widen by 150 (REAPER's docker setting)") then method_a(150) end
      if ImGui.Button(ctx, "B: widen by 150 (resize the docker's window)") then method_b(150) end
      if ImGui.Button(ctx, "C: as A, then nudge REAPER's window to lay out again") then method_a(150, true) end
      ImGui.Separator(ctx)
      if ImGui.Button(ctx, "D: drag the splitter +150 (messages)") then drag_splitter(150, false, "D") end
      ImGui.SameLine(ctx)
      if ImGui.Button(ctx, "D back##db") then drag_splitter(-150, false, "D back") end
      if ImGui.Button(ctx, "E: drag the splitter +150 (moving the pointer)") then drag_splitter(150, true, "E") end
      ImGui.SameLine(ctx)
      if ImGui.Button(ctx, "E back##eb") then drag_splitter(-150, true, "E back") end
      if ImGui.Button(ctx, "F: drag REAPER's TCP divider +150 (moving the pointer)") then drag_splitter(150, true, "F", tcp_divider_at) end
      ImGui.SameLine(ctx)
      if ImGui.Button(ctx, "F back##fb") then drag_splitter(-150, true, "F back", tcp_divider_at) end
      ImGui.Separator(ctx)
      if ImGui.Button(ctx, "G: drag the docker's edge +150 (one pixel left of D)") then drag_splitter(150, true, "G", splitter_at_edge) end
      ImGui.SameLine(ctx)
      if ImGui.Button(ctx, "G back##gb") then drag_splitter(-150, true, "G back", splitter_at_edge) end
      if ImGui.Button(ctx, "H: drag the docker's edge +150 (sent to the docker itself)") then
        local l, t, r, b = rect(docker)
        drag_splitter(150, true, "H", function()
          local sx, sy = r - 2, math.floor((t + b) / 2)
          return sx, sy, 0, 0
        end, docker)
      end
      ImGui.SameLine(ctx)
      if ImGui.Button(ctx, "H back##hb") then
        local l, t, r, b = rect(docker)
        drag_splitter(-150, true, "H back", function()
          local sx, sy = r - 2, math.floor((t + b) / 2)
          return sx, sy, 0, 0
        end, docker)
      end
      if ImGui.Button(ctx, "Put it back") then put_back() end
      ImGui.SameLine(ctx)
      ImGui.TextDisabled(ctx, "Log: dev/dockprobe.txt")
    end
    ImGui.Separator(ctx)
    if ImGui.BeginChild(ctx, "##log", 0, 0) then
      for _, s in ipairs(lines) do ImGui.Text(ctx, s) end
      ImGui.SetScrollHereY(ctx, 1.0)
      ImGui.EndChild(ctx)
    end
    ImGui.End(ctx)
  end
  first = false
  local now = reaper.time_precise()
  for i = #checks, 1, -1 do
    if now >= checks[i].at then read_now(checks[i].what) table.remove(checks, i) end
  end
  if open then reaper.defer(frame) end
end
reaper.defer(frame)
