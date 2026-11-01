-- @noindex
-- dev tool, not released. Can a plugin's own window be made to look as if
-- it sits inside a panel? Opens a small ReaImGui window with a "panel" the
-- size of the plugin's GUI, floats the chosen plugin (selected track) and
-- lays its window over the panel, two ways:
--
--   A  "On top":   the FX window loses its border and title bar and sits
--                  over the panel. REAPER's FX toolbar can't be cut off
--                  this way, so the window is placed with the plugin's own
--                  view on the panel and the toolbar above it.
--   B  "Cropped":  a borderless holder window the panel's size (owned by
--                  this window, so it stays above it) takes the FX window
--                  inside it, shifted up and left so only the plugin's own
--                  view shows: REAPER's toolbar is cut off.
--
-- Detach (or closing the window) puts the FX window back as it was and
-- closes it. Nothing in the project changes. Writes dev/guidockprobe.txt.
-- Try: move and resize this window, dock it, open "A menu", hover for the
-- tooltip, click into the plugin then press a REAPER shortcut.

local here = debug.getinfo(1, "S").source:match("@?(.*[\\/])") or ""
package.path = reaper.ImGui_GetBuiltinPath() .. "/?.lua;" .. package.path
local ImGui = require("imgui")("0.10")

if not reaper.JS_Window_SetStyle then
  reaper.MB("Needs js_ReaScriptAPI.", "GUI dock probe", 0)
  return
end

local ctx = ImGui.CreateContext("TS_CV GUI dock probe")
local TITLE = "TS_CV GUI dock probe"

local log = {}
local function say(s) log[#log + 1] = os.date("%H:%M:%S ") .. s end
say("REAPER " .. reaper.GetAppVersion())

local WS_POPUP, WS_CHILD, WS_VISIBLE = 0x80000000, 0x40000000, 0x10000000
local WS_CLIPCH, WS_CLIPSIB = 0x02000000, 0x04000000

local st = {
  pick = 0, mode = "A", follow = true, hide_menu = true,
  att = nil,        -- { tr, fx, hwnd, view, style, exstyle, parent, rect, offx, offy, w, h, host }
  me = nil,         -- this window's own HWND
}

local function children(h)
  local arr = reaper.new_array({}, 1024)
  reaper.JS_Window_ArrayAllChild(h, arr)
  local out = {}
  for _, a in ipairs(arr.table()) do
    local c = reaper.JS_Window_HandleFromAddress(a)
    if c then out[#out + 1] = c end
  end
  return out
end

local function rect(h)
  local _, l, t, r, b = reaper.JS_Window_GetRect(h)
  return l, t, r, b
end

local function depth_of(c, root)
  local d, p = 0, c
  while p and p ~= root and d < 12 do p = reaper.JS_Window_GetParent(p); d = d + 1 end
  return d
end

-- REAPER's FX window holds one container (the client area: its toolbar,
-- then the plugin). The plugin's own view is the biggest visible window
-- inside that container that's smaller than it and isn't a toolbar control.
local CONTROL = { Button = true, ComboBox = true, Static = true, Edit = true, ScrollBar = true }
local function find_parts(fxw)
  local box, barea = nil, 0
  for _, c in ipairs(children(fxw)) do
    if reaper.JS_Window_GetParent(c) == fxw and reaper.JS_Window_IsVisible(c) then
      local l, t, r, b = rect(c)
      local ar = math.abs(r - l) * math.abs(b - t)
      if ar > barea then box, barea = c, ar end
    end
  end
  if not box then return nil end
  local view, varea = nil, 0
  for _, c in ipairs(children(box)) do
    local cls = reaper.JS_Window_GetClassName(c) or ""
    if reaper.JS_Window_IsVisible(c) and not CONTROL[cls] and not cls:find("^msctls") then
      local l, t, r, b = rect(c)
      local ar = math.abs(r - l) * math.abs(b - t)
      if ar < barea * 0.98 and ar > varea then view, varea = c, ar end
    end
  end
  return box, view
end

local function list_tree(fxw)
  local fl, ft = rect(fxw)
  for _, c in ipairs(children(fxw)) do
    local l, t, r, b = rect(c)
    local d = depth_of(c, fxw)
    if d <= 4 then
      say(("    %s%-22s %4d,%4d  %4dx%-4d %s %s"):format(string.rep("  ", d - 1), reaper.JS_Window_GetClassName(c) or "?",
        l - fl, t - ft, math.abs(r - l), math.abs(b - t), reaper.JS_Window_IsVisible(c) and "" or "(hidden)",
        (reaper.JS_Window_GetTitle(c) or ""):sub(1, 24)))
    end
  end
end

local last = {}

local function detach(why)
  local a = st.att
  if not a then return end
  st.att = nil
  if reaper.JS_Window_IsWindow(a.hwnd) then
    if a.host then reaper.JS_Window_SetParent(a.hwnd, nil) end
    reaper.JS_Window_SetLong(a.hwnd, "STYLE", a.style)
    reaper.JS_Window_SetLong(a.hwnd, "EXSTYLE", a.exstyle)
    pcall(reaper.JS_Window_SetPosition, a.hwnd, a.rect[1], a.rect[2], a.rect[3] - a.rect[1], a.rect[4] - a.rect[2], "TOP", "FRAMECHANGED|NOACTIVATE")
  end
  if a.host and reaper.JS_Window_IsWindow(a.host) then reaper.JS_Window_Destroy(a.host) end
  if reaper.ValidatePtr2(0, a.tr, "MediaTrack*") then reaper.TrackFX_Show(a.tr, a.fx, 2) end
  say("detached (" .. (why or "button") .. ")")
end

local function attach(tr, fx)
  detach("re-attach")
  last = {}
  reaper.TrackFX_Show(tr, fx, 3)
  local hwnd = reaper.TrackFX_GetFloatingWindow(tr, fx)
  if not hwnd then say("no floating window for FX " .. fx) return end
  local _, nm = reaper.TrackFX_GetFXName(tr, fx, "")
  local l, t, r, b = rect(hwnd)
  say(("attach %s  mode %s  FX window %dx%d at %d,%d"):format(nm, st.mode, r - l, b - t, l, t))
  list_tree(hwnd)
  local box, view = find_parts(hwnd)
  if not box then say("  no container found") return end
  view = view or box
  local bl, bt, br, bb = rect(box)
  local vl, vt, vr, vb = rect(view)
  local a = { tr = tr, fx = fx, hwnd = hwnd, view = view, rect = { l, t, r, b },
              style = reaper.JS_Window_GetLong(hwnd, "STYLE"), exstyle = reaper.JS_Window_GetLong(hwnd, "EXSTYLE"),
              w = math.abs(vr - vl), h = math.abs(vb - vt),
              bw = math.abs(br - bl), bh = math.abs(bb - bt),
              offx = vl - bl, offy = vt - bt }
  say(("  container %dx%d; plugin view %s %dx%d at %d,%d in it"):format(a.bw, a.bh,
    reaper.JS_Window_GetClassName(view) or "?", a.w, a.h, a.offx, a.offy))
  if st.mode == "A" then
    reaper.JS_Window_SetLong(hwnd, "STYLE", WS_POPUP | WS_VISIBLE | WS_CLIPCH | WS_CLIPSIB)
    -- (a style change shows once the frame is recalculated)
    local ok = pcall(reaper.JS_Window_SetPosition, hwnd, l, t, a.bw, a.bh, "TOP", "FRAMECHANGED|NOACTIVATE")
    if not ok then say("  SetPosition with flags not supported") end
  else
    local host = reaper.JS_Window_Create("TS_CV dock host", "TS_CV_DockHost", 0, 0, a.w, a.h, "POPUP", st.me)
    if not host then say("  couldn't make the holder window") return end
    a.host = host
    reaper.JS_Window_SetLong(hwnd, "STYLE", WS_CHILD | WS_VISIBLE | WS_CLIPCH | WS_CLIPSIB)
    reaper.JS_Window_SetParent(hwnd, host)
    pcall(reaper.JS_Window_SetPosition, hwnd, -a.offx, -a.offy, a.bw, a.bh, "TOP", "FRAMECHANGED|NOACTIVATE")
    reaper.JS_Window_Show(host, "SHOWNA")
  end
  st.att = a
end

-- Puts the window (A) or the holder (B) on the panel at native x, y. It's
-- checked every frame and moved back if anything (REAPER restoring a
-- floating window's place, say) has moved it.
local function place(x, y, show, vis)
  local a = st.att
  if not a then return end
  local win = a.host or a.hwnd
  if not reaper.JS_Window_IsWindow(a.hwnd) then detach("its window closed") return end
  if not show then
    if last.shown ~= false then reaper.JS_Window_Show(win, "HIDE"); last.shown = false end
    return
  end
  if last.shown == false then reaper.JS_Window_Show(win, "SHOWNA") end
  last.shown = true
  local px, py = math.floor(x + 0.5), math.floor(y + 0.5)
  local l, t = rect(win)
  if a.host then
    -- the holder covers only the part of the panel that's in view, and
    -- the FX window inside it shifts by as much: the rest is cut off
    local hx, hy = math.floor(vis[1] + 0.5), math.floor(vis[2] + 0.5)
    local hw, hh = math.floor(vis[3] - vis[1] + 0.5), math.floor(vis[4] - vis[2] + 0.5)
    local _, _, r, b = rect(a.host)
    if l ~= hx or t ~= hy or r - l ~= hw or b - t ~= hh then
      reaper.JS_Window_SetPosition(a.host, hx, hy, hw, hh); last.moves = (last.moves or 0) + 1
    end
    local want_x, want_y = -a.offx - (hx - px), -a.offy - (hy - py)
    local fl, ft = rect(a.hwnd)
    local cx, cy = reaper.JS_Window_ScreenToClient(a.host, fl, ft)
    if cx ~= want_x or cy ~= want_y then reaper.JS_Window_Move(a.hwnd, want_x, want_y) end
  else
    -- the view on the panel, REAPER's toolbar above it
    local wx, wy = px - a.offx, py - a.offy
    if l ~= wx or t ~= wy then reaper.JS_Window_SetPosition(a.hwnd, wx, wy, a.bw, a.bh); last.moves = (last.moves or 0) + 1 end
  end
end

local frames, moves, t0 = 0, 0, reaper.time_precise()

local function loop()
  ImGui.SetNextWindowSize(ctx, 520, 460, ImGui.Cond_FirstUseEver)
  local visible, open = ImGui.Begin(ctx, TITLE, true)
  local menu_open = false
  if visible then
    local tr = reaper.GetSelectedTrack(0, 0)
    if not tr then ImGui.Text(ctx, "Select a track.")
    else
      local n = reaper.TrackFX_GetCount(tr)
      local names = {}
      for i = 0, n - 1 do names[#names + 1] = select(2, reaper.TrackFX_GetFXName(tr, i, "")):gsub("%z", "") end
      ImGui.SetNextItemWidth(ctx, 260)
      local ch, v = ImGui.Combo(ctx, "##fx", st.pick, table.concat(names, "\0") .. "\0")
      if ch then st.pick = v end
      ImGui.SameLine(ctx)
      if ImGui.RadioButton(ctx, "A on top", st.mode == "A") then st.mode = "A" end
      ImGui.SameLine(ctx)
      if ImGui.RadioButton(ctx, "B cropped", st.mode == "B") then st.mode = "B" end
      if ImGui.Button(ctx, st.att and "Attach again" or "Attach") and n > 0 then
        -- this window's own handle, found under the mouse before the plugin covers anything
        local mx, my = ImGui.GetMousePos(ctx)
        local nx, ny = ImGui.PointConvertNative(ctx, mx, my, true)
        local under = reaper.JS_Window_FromPoint(math.floor(nx), math.floor(ny))
        -- its top-level window (a docked one's is REAPER's main window)
        local top, guard = under, 0
        while top and guard < 20 do
          local p = reaper.JS_Window_GetParent(top)
          if not p then break end
          top, guard = p, guard + 1
        end
        st.me = top
        say(("this window: under the mouse %s, top-level %s (%s)"):format(reaper.JS_Window_GetClassName(under) or "?",
          reaper.JS_Window_GetClassName(top) or "?", reaper.JS_Window_GetTitle(top) or ""))
        attach(tr, st.pick)
        frames, moves, t0 = 0, 0, reaper.time_precise()
      end
      ImGui.SameLine(ctx)
      if ImGui.Button(ctx, "Detach") then detach() end
      ImGui.SameLine(ctx)
      if ImGui.Button(ctx, "A menu") then ImGui.OpenPopup(ctx, "probe_menu") end
      if ImGui.BeginPopup(ctx, "probe_menu") then
        menu_open = true
        for i = 1, 8 do ImGui.MenuItem(ctx, "Menu item " .. i) end
        ImGui.EndPopup(ctx)
      end
      ImGui.SameLine(ctx)
      local _, f = ImGui.Checkbox(ctx, "Hide for menus", st.hide_menu); st.hide_menu = f
      ImGui.TextDisabled(ctx, "Hover here for a tooltip; the panel is below.")
      if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "A tooltip.\nDoes the plugin cover it?") end
      local a = st.att
      local w, h = a and a.w or 300, a and a.h or 200
      ImGui.Text(ctx, a and ("Panel %dx%d   crop %d,%d   frames %d   moves %d"):format(w, h, a.offx, a.offy, frames, last.moves or 0) or "Panel")
      -- the panel: a frame the plugin's size
      local x, y = ImGui.GetCursorScreenPos(ctx)
      local dl = ImGui.GetWindowDrawList(ctx)
      ImGui.DrawList_AddRectFilled(dl, x, y, x + w, y + h, 0x2a2c30ff, 4)
      ImGui.DrawList_AddRect(dl, x - 1, y - 1, x + w + 1, y + h + 1, 0x7a5cc4ff, 4, 0, 2)
      ImGui.Dummy(ctx, w, h)
      if a then
        local nx, ny = ImGui.PointConvertNative(ctx, x, y, true)
        -- the part of the panel in view: inside the window, under its title
        local wx, wy = ImGui.GetWindowPos(ctx)
        local ww, wh = ImGui.GetWindowSize(ctx)
        local top = wy + ImGui.GetFrameHeight(ctx)
        local vx1, vy1 = math.max(x, wx), math.max(y, top)
        local vx2, vy2 = math.min(x + w, wx + ww), math.min(y + h, wy + wh)
        local any = vx2 - vx1 > 4 and vy2 - vy1 > 4
        local all = vx1 == x and vy1 == y and vx2 == x + w and vy2 == y + h
        local n1x, n1y = ImGui.PointConvertNative(ctx, vx1, vy1, true)
        local n2x, n2y = ImGui.PointConvertNative(ctx, vx2, vy2, true)
        local any_popup = ImGui.IsPopupOpen(ctx, "", ImGui.PopupFlags_AnyPopupId)
        local show = (a.host and any or all) and not (st.hide_menu and (menu_open or any_popup))
        place(nx, ny, show, { n1x, n1y, n2x, n2y })
        frames = frames + 1
      end
    end
    ImGui.End(ctx)
  else
    place(0, 0, false)
  end
  if open then reaper.defer(loop) else detach("window closed") end
end

reaper.atexit(function()
  detach("script ended")
  local f = io.open(here .. "guidockprobe.txt", "w")
  if f then f:write(table.concat(log, "\n") .. "\n"); f:close() end
end)
reaper.defer(loop)
