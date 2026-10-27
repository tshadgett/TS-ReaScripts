-- @noindex
-- Not a package of its own: installed by TS_ChannelView.lua's @provides.
--[[
  TS_CV_Style.lua -- the look of every panel, dialogue and menu.

  Two halves:

    * ST.push / ST.pop: one style put around each script's whole frame,
      so every stock ImGui button, field, slider, list and title bar takes
      the palette's greys and accent (TS_CV_Config: the ui_* entries)
      instead of ImGui's blue. It follows the base hue like the rest.

    * The kit, for options panels and dialogues, in the look of the patch
      bay's connection sheet:
        - ST.caption: a small dim label ABOVE its control. Every label
          sits there; ST.cap / ST.done group one with its control (a
          blank one lines a button up with captioned neighbours).
        - ST.seg: one of a few, as joined chips, the picked one outlined.
        - ST.checkbox: on / off, as a chip with a light. Takes and gives
          what ImGui.Checkbox does.
        - ST.button: grey; "main" in the accent (the one main action);
          "remove" outlined red.
        - ST.slider_double / ST.slider_int: a thin bar in the accent with
          a round thumb, the value at its right; a caption above when the
          label shows one. Double-click (or Ctrl+click) to type a value.
          Take and give what ImGui.SliderDouble / SliderInt do.
]]

local C = require("TS_CV_Config")

local ST = {}
local ImGui
local W                       -- TS_CV_Widgets, for its small font

function ST.attach(imgui, widgets)
  ImGui = imgui
  W = widgets or W
end

local function alpha(col, a) return (col & 0xffffff00) | (a & 0xff) end

-- sizes and places, never nil (the tests' stand-in ImGui answers little)
local function frame_h(ctx) return ImGui.GetFrameHeight(ctx) or 22 end
local function line_h(ctx) return ImGui.GetTextLineHeight(ctx) or 14 end
local function text_w(ctx, t)
  local w = ImGui.CalcTextSize(ctx, t)
  return w or (#t * 7)
end
local function cursor(ctx)
  local x, y = ImGui.GetCursorScreenPos(ctx)
  return x or 0, y or 0
end

-- ---------------------------------------------------------------------
-- the frame's style
-- ---------------------------------------------------------------------
local pushed_c, pushed_v = 0, 0

function ST.colours()
  local K = C.COL
  return {
    { "Col_Text",                 K.header_text },
    { "Col_TextDisabled",         K.header_dim },
    { "Col_Button",               K.ui_chip },
    { "Col_ButtonHovered",        K.ui_chip_hov },
    { "Col_ButtonActive",         K.ui_chip_on },
    { "Col_FrameBg",              K.ui_field },
    { "Col_FrameBgHovered",       K.ui_chip },
    { "Col_FrameBgActive",        K.ui_chip_hov },
    { "Col_CheckMark",            K.accent },
    { "Col_SliderGrab",           K.accent },
    { "Col_SliderGrabActive",     K.ui_hi },
    { "Col_Header",               alpha(K.accent, 0x48) },
    { "Col_HeaderHovered",        alpha(K.accent, 0x30) },
    { "Col_HeaderActive",         alpha(K.accent, 0x60) },
    { "Col_Border",               K.ui_edge },
    { "Col_PopupBg",              K.panel_bg },
    { "Col_TitleBg",              K.win_bg },
    { "Col_TitleBgActive",        K.header_bg },
    { "Col_TitleBgCollapsed",     K.win_bg },
    { "Col_Separator",            K.panel_border },
    { "Col_SeparatorHovered",     alpha(K.accent, 0x90) },
    { "Col_SeparatorActive",      K.accent },
    { "Col_ResizeGrip",           alpha(K.accent, 0x30) },
    { "Col_ResizeGripHovered",    alpha(K.accent, 0x90) },
    { "Col_ResizeGripActive",     K.accent },
    { "Col_ScrollbarGrab",        K.ui_chip_hov },
    { "Col_ScrollbarGrabHovered", K.ui_chip_on },
    { "Col_ScrollbarGrabActive",  K.ui_edge },
    { "Col_Tab",                  K.ui_chip },
    { "Col_TabHovered",           K.ui_chip_on },
    { "Col_TabSelected",          K.ui_chip_on },
    { "Col_TabSelectedOverline",  K.accent },
    { "Col_TabDimmed",            K.ui_field },
    { "Col_TabDimmedSelected",    K.ui_chip },
    { "Col_TextSelectedBg",       alpha(K.accent, 0x60) },
    { "Col_DragDropTarget",       K.accent },
    { "Col_NavCursor",            K.accent },
  }
end

local VARS = {
  { "StyleVar_FrameRounding",   4 },
  { "StyleVar_GrabRounding",    4 },
  { "StyleVar_PopupRounding",   6 },
  { "StyleVar_FrameBorderSize", 1 },
}

function ST.push(ctx)
  pushed_c, pushed_v = 0, 0
  for _, e in ipairs(ST.colours()) do
    local k = ImGui[e[1]]
    if k and e[2] then ImGui.PushStyleColor(ctx, k, e[2]); pushed_c = pushed_c + 1 end
  end
  for _, e in ipairs(VARS) do
    local k = ImGui[e[1]]
    if k then ImGui.PushStyleVar(ctx, k, e[2]); pushed_v = pushed_v + 1 end
  end
end

function ST.pop(ctx)
  if pushed_v > 0 then ImGui.PopStyleVar(ctx, pushed_v) end
  if pushed_c > 0 then ImGui.PopStyleColor(ctx, pushed_c) end
  pushed_c, pushed_v = 0, 0
end

-- ---------------------------------------------------------------------
-- captions
-- ---------------------------------------------------------------------
local function small(ctx, on)
  if not W then return end
  if on then W.push_small(ctx) else W.pop_small(ctx) end
end

-- the visible part of an ImGui label ("Name##id" -> "Name")
function ST.visible(label)
  label = tostring(label or "")
  local s = label:find("##", 1, true)
  return s and label:sub(1, s - 1) or label
end

function ST.caption(ctx, text)
  small(ctx, true)
  ImGui.PushStyleColor(ctx, ImGui.Col_Text, C.COL.header_dim)
  ImGui.Text(ctx, (text and text ~= "") and text or " ")
  ImGui.PopStyleColor(ctx)
  small(ctx, false)
end

-- A caption over a control, as one group, so the next item can go
-- SameLine beside it: ST.cap(ctx, "Name") ... the control ... ST.done(ctx).
-- A nil or "" caption leaves the line blank, so a button among captioned
-- controls lines up with them.
function ST.cap(ctx, caption)
  caption = caption or ""
  ImGui.BeginGroup(ctx)
  ST.caption(ctx, caption)
end

function ST.done(ctx) ImGui.EndGroup(ctx) end

-- ---------------------------------------------------------------------
-- chips
-- ---------------------------------------------------------------------
local PAD = 11

local function chip_face(dl, x, y, w, h, on, hov, flags, dim)
  local K = C.COL
  local f = on and K.ui_chip_on or (hov and K.ui_chip_hov or K.ui_chip)
  ImGui.DrawList_AddRectFilled(dl, x, y, x + w, y + h, f, 4.0, flags or 0)
  local edge = on and K.ui_hi or K.ui_edge
  if dim then edge = alpha(edge, 0x80) end
  ImGui.DrawList_AddRect(dl, x + 0.5, y + 0.5, x + w - 0.5, y + h - 0.5, edge, 4.0, flags or 0, on and 1.5 or 1.0)
end

local function ink(on, dim)
  local K = C.COL
  if dim then return alpha(K.header_dim, 0x90) end
  return on and K.header_text or K.label
end

-- One of a few. items: { { label, value[, tip] }, ... }. Gives the value
-- clicked (even the current one), or nil. opts.w: each chip's width.
function ST.seg(ctx, id, items, cur, opts)
  opts = opts or {}
  local dl = ImGui.GetWindowDrawList(ctx)
  local h = frame_h(ctx)
  local picked
  local n = #items
  local cur_i
  for i, it in ipairs(items) do if it[2] == cur then cur_i = i end end
  local rects = {}
  for i, it in ipairs(items) do
    if i > 1 then ImGui.SameLine(ctx, 0, 0) end
    local label = ST.visible(it[1])
    local tw = text_w(ctx, label)
    local w = math.floor((opts.w or (tw + PAD * 2)) + 0.5)
    local x, y = cursor(ctx)
    if ImGui.InvisibleButton(ctx, id .. "##seg" .. i, w, h) then picked = it[2] end
    local hov = ImGui.IsItemHovered(ctx)
    if hov and it[3] then ImGui.SetTooltip(ctx, it[3]) end
    rects[i] = { x, y, w, hov, label, tw }
  end
  -- the unpicked first, the picked one last so its bright edge is whole
  local order = {}
  for i = 1, n do if i ~= cur_i then order[#order + 1] = i end end
  if cur_i then order[#order + 1] = cur_i end
  for _, i in ipairs(order) do
    local r = rects[i]
    local flags = ImGui.DrawFlags_RoundCornersNone
    if n == 1 then flags = 0
    elseif i == 1 then flags = ImGui.DrawFlags_RoundCornersLeft
    elseif i == n then flags = ImGui.DrawFlags_RoundCornersRight end
    local x0 = (i > 1) and (r[1] - 1) or r[1]           -- shared edges overlap
    local on = (i == cur_i)
    chip_face(dl, x0, r[2], r[3] + (r[1] - x0), h, on, r[4], flags, opts.dim)
    local th = line_h(ctx)
    ImGui.DrawList_AddText(dl, math.floor(r[1] + (r[3] - r[6]) * 0.5 + 0.5),
      math.floor(r[2] + (h - th) * 0.5 + 0.5), ink(on, opts.dim), r[5])
  end
  return picked
end

-- On / off, as a chip with a light. Same returns as ImGui.Checkbox.
function ST.checkbox(ctx, label, v, opts)
  opts = opts or {}
  local K = C.COL
  local dl = ImGui.GetWindowDrawList(ctx)
  local text = ST.visible(label)
  local h = frame_h(ctx)
  local tw = text_w(ctx, text)
  local w = math.floor(opts.w or (tw + PAD * 2 + 15))
  local x, y = cursor(ctx)
  local id = label:find("##", 1, true) and label or (label .. "##stcb")
  local hit = ImGui.InvisibleButton(ctx, id, w, h)
  local hov = ImGui.IsItemHovered(ctx)
  local on = v and true or false
  chip_face(dl, x, y, w, h, on, hov, 0, opts.dim)
  local cx, cy = x + PAD + 3, y + h * 0.5
  if on and not opts.dim then
    ImGui.DrawList_AddCircleFilled(dl, cx, cy, 6.5, alpha(K.accent, 0x40), 16)
    ImGui.DrawList_AddCircleFilled(dl, cx, cy, 4.0, K.accent, 16)
  else
    ImGui.DrawList_AddCircleFilled(dl, cx, cy, 4.0, K.toggle_off, 16)
    ImGui.DrawList_AddCircle(dl, cx, cy, 4.0, K.ui_edge, 16, 1.0)
  end
  local th = line_h(ctx)
  ImGui.DrawList_AddText(dl, math.floor(x + PAD + 13 + 0.5), math.floor(y + (h - th) * 0.5 + 0.5),
    ink(on, opts.dim), text)
  if hit and not opts.dim then return true, not on end
  return false, on
end

-- A button. kind: nil (grey), "main" (the accent), "remove" (red edge).
-- opts.dim: drawn faded and does nothing (a disabled one).
function ST.button(ctx, label, kind, w, h, opts)
  opts = opts or {}
  kind = kind or "plain"
  local K = C.COL
  local n_col = 0
  if kind == "main" then
    ImGui.PushStyleColor(ctx, ImGui.Col_Button, K.accent)
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, alpha(K.accent, 0xd8))
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, K.ui_hi)
    ImGui.PushStyleColor(ctx, ImGui.Col_Border, K.accent)
    ImGui.PushStyleColor(ctx, ImGui.Col_Text, 0x0d1116ff)
    n_col = 5
  elseif kind == "remove" then
    ImGui.PushStyleColor(ctx, ImGui.Col_Button, K.ui_remove_bg)
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, alpha(K.warn, 0x50))
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, alpha(K.warn, 0x80))
    ImGui.PushStyleColor(ctx, ImGui.Col_Border, K.warn)
    ImGui.PushStyleColor(ctx, ImGui.Col_Text, K.warn)
    n_col = 5
  end
  if opts.dim then ImGui.BeginDisabled(ctx, true) end
  local hit = ImGui.Button(ctx, label, w or 0, h or 0)
  if opts.dim then ImGui.EndDisabled(ctx) end
  if n_col > 0 then ImGui.PopStyleColor(ctx, n_col) end
  return hit and not opts.dim
end

-- ---------------------------------------------------------------------
-- sliders
-- ---------------------------------------------------------------------
local typing = {}            -- id -> true while a value is typed in

local function fmt_value(fmt, v, int)
  if fmt == "" then return "" end
  fmt = fmt or (int and "%d" or "%.3f")
  local ok, s = pcall(string.format, fmt, int and math.floor(v + 0.5) or v)
  return ok and s or tostring(v)
end

-- the bar itself; returns changed, value
local function slider(ctx, label, v, lo, hi, fmt, int, opts)
  opts = opts or {}
  local K = C.COL
  local cap = ST.visible(label)
  local id = label:find("##", 1, true) and label or ("##st" .. label)
  local w = ImGui.CalcItemWidth(ctx) or 120
  if cap ~= "" then
    ImGui.BeginGroup(ctx)
    ST.caption(ctx, cap)
  end
  local changed, nv = false, v
  if typing[id] then
    ImGui.SetNextItemWidth(ctx, w)
    if typing[id] == 1 then ImGui.SetKeyboardFocusHere(ctx); typing[id] = 2 end
    local ch, tv
    if int then ch, tv = ImGui.InputInt(ctx, "##type" .. id, math.floor(v + 0.5), 0, 0)
    else ch, tv = ImGui.InputDouble(ctx, "##type" .. id, v, 0, 0, "%.3f") end
    if ch then
      tv = math.max(lo, math.min(hi, tv))
      if int then tv = math.floor(tv + 0.5) end
      if tv ~= v then changed, nv = true, tv end
    end
    if ImGui.IsItemDeactivated(ctx) then typing[id] = nil end
  else
    local dl = ImGui.GetWindowDrawList(ctx)
    local h = frame_h(ctx)
    local text = fmt_value(fmt, v, int)
    local tw = (text ~= "") and (text_w(ctx, text) + 10) or 0
    local bw = math.max(24, w - tw)
    local x, y = cursor(ctx)
    ImGui.InvisibleButton(ctx, id, w, h)
    local hov, act = ImGui.IsItemHovered(ctx), ImGui.IsItemActive(ctx)
    local span = (hi - lo)
    if hov and (ImGui.IsMouseDoubleClicked(ctx, ImGui.MouseButton_Left)
                or (ImGui.IsMouseClicked(ctx, ImGui.MouseButton_Left) and ImGui.IsKeyDown(ctx, ImGui.Mod_Ctrl))) then
      typing[id] = 1
    elseif act and span ~= 0 then
      local mx = ImGui.GetMousePos(ctx)
      local t = math.max(0, math.min(1, (mx - x - 7) / math.max(1, bw - 14)))
      local tv = lo + t * span
      if int then tv = math.floor(tv + 0.5) end
      if tv ~= v then changed, nv = true, tv end
    end
    local t = (span ~= 0) and math.max(0, math.min(1, (nv - lo) / span)) or 0
    local cy = y + h * 0.5
    local x0, x1 = x + 7, x + bw - 7
    ImGui.DrawList_AddRectFilled(dl, x0, cy - 2.5, x1, cy + 2.5, K.ui_chip_on, 2.5)
    local kx = x0 + (x1 - x0) * t
    if kx > x0 then ImGui.DrawList_AddRectFilled(dl, x0, cy - 2.5, kx, cy + 2.5, K.accent, 2.5) end
    local r = (hov or act) and 7.5 or 6.5
    ImGui.DrawList_AddCircleFilled(dl, kx, cy, r, act and K.ui_hi or 0xe6e6e6ff, 16)
    ImGui.DrawList_AddCircle(dl, kx, cy, r, 0x00000080, 16, 1.0)
    if text ~= "" then
      local th = line_h(ctx)
      text = fmt_value(fmt, nv, int)
      ImGui.DrawList_AddText(dl, math.floor(x + bw + 6 + 0.5), math.floor(y + (h - th) * 0.5 + 0.5), K.header_text, text)
    end
  end
  if cap ~= "" then ImGui.EndGroup(ctx) end
  return changed, nv
end

function ST.slider_double(ctx, label, v, lo, hi, fmt)
  return slider(ctx, label, v or 0, lo, hi, fmt or nil, false)
end

function ST.slider_int(ctx, label, v, lo, hi, fmt)
  return slider(ctx, label, math.floor(v or 0), lo, hi, fmt or nil, true)
end

ST._alpha = alpha
return ST
