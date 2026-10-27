-- @noindex
-- Not a package of its own: installed by TS_TrackAnalyser.lua's @provides.
--[[
  TS_TA_Style.lua -- the look of the settings: ChannelView's look, so the
  three TS_ tools' options read alike.

  Self-contained (each tool installs on its own): it works out its own
  greys and accent from the shared hue and tint with the same sums as
  ChannelView's palette, and takes either ReaImGui API -- the module
  (constants are numbers) or the flat reaper.ImGui_* names (constants are
  functions).

    K.attach(ImGui)        the ImGui table (module or flat shim)
    K.palette(hue, tint)   rebuild the colours (hue 0-360, tint 0-2)
    K.push(ctx) / K.pop(ctx)
                           the stock widgets in these greys and accent,
                           pushed before Begin, popped after End
    K.caption(ctx, text)   a small dim label ABOVE its control
    K.cap(ctx, text) ... K.done(ctx)
                           a caption and its control as one group (a blank
                           one lines a button up with captioned neighbours)
    K.seg(ctx, id, {{label, value[, tip]}, ...}, cur[, opts])
                           one of a few, as joined chips; the value clicked
    K.checkbox(ctx, label, v[, opts])
                           on / off as a chip with a light; returns as
                           ImGui.Checkbox does
    K.button(ctx, label, kind, w, h, opts)
                           kind "main" (the accent) or "remove" (red edge)
    K.slider_double / K.slider_int(ctx, label, v, lo, hi, fmt[, opts])
                           a thin accent bar with a round thumb, the value
                           at its right, a caption from the visible label;
                           double-click or Ctrl+click to type a value.
                           Returns changed, value, released (true the frame
                           a drag ends or a typed value goes in: the time
                           to save). opts.dim: faded, does nothing.
]]

local K = {}
local ImGui
local enum_cache = {}

function K.attach(imgui) ImGui = imgui; enum_cache = {} end

-- a constant, whichever API: a number in the module, a function in the
-- flat one; nil when this build hasn't got it
local function E(name)
  local v = enum_cache[name]
  if v ~= nil then return v or nil end
  v = ImGui[name]
  if type(v) == "function" then
    local ok, r = pcall(v)
    v = ok and r or nil
  end
  enum_cache[name] = v or false
  return v
end
K.E = E

-- ---------------------------------------------------------------------
-- the colours: ChannelView's palette entries, by the same sums
-- ---------------------------------------------------------------------
local ALERT_HUE = 17
local PALETTE = {
  text       = { "tint",    3.9, 0.206, 0.867 },
  dim        = { "tint",   -3.0, 0.100, 0.512 },
  label      = { "tint",   -2.1, 0.148, 0.655 },
  accent     = { "solid", -14.0, 0.661, 0.573 },
  warn       = { "alert",  -0.1, 0.645, 0.569 },
  panel_bg   = { "tint",    4.6, 0.169, 0.127 },
  header_bg  = { "tint",    2.2, 0.186, 0.169 },
  border     = { "tint",    3.4, 0.162, 0.206 },
  win_bg     = { "tint",    7.7, 0.209, 0.084 },
  toggle_off = { "tint",    2.2, 0.160, 0.196 },
  field      = { "tint",    3.0, 0.120, 0.150 },
  chip       = { "tint",    3.0, 0.100, 0.180 },
  chip_hov   = { "tint",    3.0, 0.100, 0.215 },
  chip_on    = { "tint",    3.0, 0.100, 0.250 },
  edge       = { "tint",    3.0, 0.080, 0.320 },
  hi         = { "tint",    0.0, 0.080, 0.830 },
  remove_bg  = { "alert",   0.0, 0.450, 0.150 },
}

local function hsl(h, s, l)
  h = (h % 360) / 360
  s = math.max(0, math.min(1, s))
  l = math.max(0, math.min(1, l))
  local function hue2(p, q, t)
    if t < 0 then t = t + 1 elseif t > 1 then t = t - 1 end
    if t < 1/6 then return p + (q - p) * 6 * t end
    if t < 1/2 then return q end
    if t < 2/3 then return p + (q - p) * (2/3 - t) * 6 end
    return p
  end
  local r, g, b
  if s == 0 then
    r, g, b = l, l, l
  else
    local q = (l < 0.5) and (l * (1 + s)) or (l + s - l * s)
    local p = 2 * l - q
    r, g, b = hue2(p, q, h + 1/3), hue2(p, q, h), hue2(p, q, h - 1/3)
  end
  local function b8(v) return math.max(0, math.min(255, math.floor(v * 255 + 0.5))) end
  return (b8(r) << 24) | (b8(g) << 16) | (b8(b) << 8) | 0xff
end

local COL = {}
K.COL = COL

function K.palette(hue, tint)
  hue, tint = hue or 219, tint or 1.0
  for name, e in pairs(PALETTE) do
    local role, dh, sat, lum = e[1], e[2], e[3], e[4]
    local h, s
    if role == "alert" then h, s = ALERT_HUE + dh, sat
    elseif role == "tint" then h, s = hue + dh, sat * tint
    else h, s = hue + dh, sat end
    COL[name] = hsl(h, s, lum)
  end
  return COL
end
K.palette()

local function alpha(col, a) return (col & 0xffffff00) | (a & 0xff) end

-- ---------------------------------------------------------------------
-- the frame's style
-- ---------------------------------------------------------------------
local function colours()
  return {
    { "Col_Text",                 COL.text },
    { "Col_TextDisabled",         COL.dim },
    { "Col_Button",               COL.chip },
    { "Col_ButtonHovered",        COL.chip_hov },
    { "Col_ButtonActive",         COL.chip_on },
    { "Col_FrameBg",              COL.field },
    { "Col_FrameBgHovered",       COL.chip },
    { "Col_FrameBgActive",        COL.chip_hov },
    { "Col_CheckMark",            COL.accent },
    { "Col_SliderGrab",           COL.accent },
    { "Col_SliderGrabActive",     COL.hi },
    { "Col_Header",               alpha(COL.accent, 0x48) },
    { "Col_HeaderHovered",        alpha(COL.accent, 0x30) },
    { "Col_HeaderActive",         alpha(COL.accent, 0x60) },
    { "Col_Border",               COL.edge },
    { "Col_PopupBg",              COL.panel_bg },
    { "Col_TitleBg",              COL.win_bg },
    { "Col_TitleBgActive",        COL.header_bg },
    { "Col_TitleBgCollapsed",     COL.win_bg },
    { "Col_Separator",            COL.border },
    { "Col_SeparatorHovered",     alpha(COL.accent, 0x90) },
    { "Col_SeparatorActive",      COL.accent },
    { "Col_ResizeGrip",           alpha(COL.accent, 0x30) },
    { "Col_ResizeGripHovered",    alpha(COL.accent, 0x90) },
    { "Col_ResizeGripActive",     COL.accent },
    { "Col_ScrollbarGrab",        COL.chip_hov },
    { "Col_ScrollbarGrabHovered", COL.chip_on },
    { "Col_ScrollbarGrabActive",  COL.edge },
    { "Col_Tab",                  COL.chip },
    { "Col_TabHovered",           COL.chip_on },
    { "Col_TabSelected",          COL.chip_on },
    { "Col_TabActive",            COL.chip_on },
    { "Col_TextSelectedBg",       alpha(COL.accent, 0x60) },
    { "Col_DragDropTarget",       COL.accent },
  }
end

local VARS = {
  { "StyleVar_FrameRounding",   4 },
  { "StyleVar_GrabRounding",    4 },
  { "StyleVar_PopupRounding",   6 },
  { "StyleVar_FrameBorderSize", 1 },
}

-- A push that a build refuses costs that one entry, not the frame.
local stack = {}
function K.push(ctx)
  local nc, nv = 0, 0
  for _, e in ipairs(colours()) do
    local k = E(e[1])
    if k and e[2] and pcall(ImGui.PushStyleColor, ctx, k, e[2]) then nc = nc + 1 end
  end
  for _, e in ipairs(VARS) do
    local k = E(e[1])
    if k and pcall(ImGui.PushStyleVar, ctx, k, e[2]) then nv = nv + 1 end
  end
  stack[#stack + 1] = { nc, nv }
end

function K.pop(ctx)
  local t = table.remove(stack)
  if not t then return end
  if t[2] > 0 then ImGui.PopStyleVar(ctx, t[2]) end
  if t[1] > 0 then ImGui.PopStyleColor(ctx, t[1]) end
end

-- ---------------------------------------------------------------------
-- captions
-- ---------------------------------------------------------------------
local small_push, small_pop
-- optional: a smaller face for captions (two functions taking ctx)
function K.set_small(push, pop) small_push, small_pop = push, pop end

function K.visible(label)
  label = tostring(label or "")
  local s = label:find("##", 1, true)
  return s and label:sub(1, s - 1) or label
end

function K.caption(ctx, text)
  if small_push then small_push(ctx) end
  ImGui.PushStyleColor(ctx, E("Col_Text"), COL.dim)
  ImGui.Text(ctx, (text and text ~= "") and text or " ")
  ImGui.PopStyleColor(ctx)
  if small_pop then small_pop(ctx) end
end

function K.cap(ctx, caption)
  caption = caption or ""
  ImGui.BeginGroup(ctx)
  K.caption(ctx, caption)
end

function K.done(ctx) ImGui.EndGroup(ctx) end

-- ---------------------------------------------------------------------
-- chips
-- ---------------------------------------------------------------------
local PAD = 11

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

local function chip_face(dl, x, y, w, h, on, hov, flags, dim)
  local f = on and COL.chip_on or (hov and COL.chip_hov or COL.chip)
  ImGui.DrawList_AddRectFilled(dl, x, y, x + w, y + h, f, 4.0, flags or 0)
  local edge = on and COL.hi or COL.edge
  if dim then edge = alpha(edge, 0x80) end
  ImGui.DrawList_AddRect(dl, x + 0.5, y + 0.5, x + w - 0.5, y + h - 0.5, edge, 4.0, flags or 0, on and 1.5 or 1.0)
end

local function ink(on, dim)
  if dim then return alpha(COL.dim, 0x90) end
  return on and COL.text or COL.label
end

function K.seg(ctx, id, items, cur, opts)
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
    local label = K.visible(it[1])
    local tw = text_w(ctx, label)
    local w = math.floor((opts.w or (tw + PAD * 2)) + 0.5)
    local x, y = cursor(ctx)
    if ImGui.InvisibleButton(ctx, id .. "##seg" .. i, w, h) and not opts.dim then picked = it[2] end
    local hov = ImGui.IsItemHovered(ctx)
    if hov and it[3] then ImGui.SetTooltip(ctx, it[3]) end
    rects[i] = { x, y, w, hov, label, tw }
  end
  local order = {}
  for i = 1, n do if i ~= cur_i then order[#order + 1] = i end end
  if cur_i then order[#order + 1] = cur_i end
  local th = line_h(ctx)
  for _, i in ipairs(order) do
    local r = rects[i]
    local flags = E("DrawFlags_RoundCornersNone") or 0
    if n == 1 then flags = 0
    elseif i == 1 then flags = E("DrawFlags_RoundCornersLeft") or 0
    elseif i == n then flags = E("DrawFlags_RoundCornersRight") or 0 end
    local x0 = (i > 1) and (r[1] - 1) or r[1]
    local on = (i == cur_i)
    chip_face(dl, x0, r[2], r[3] + (r[1] - x0), h, on, r[4], flags, opts.dim)
    ImGui.DrawList_AddText(dl, math.floor(r[1] + (r[3] - r[6]) * 0.5 + 0.5),
      math.floor(r[2] + (h - th) * 0.5 + 0.5), ink(on, opts.dim), r[5])
  end
  return picked
end

function K.checkbox(ctx, label, v, opts)
  opts = opts or {}
  local dl = ImGui.GetWindowDrawList(ctx)
  local text = K.visible(label)
  local h = frame_h(ctx)
  local tw = (text ~= "") and text_w(ctx, text) or 0
  local w = math.floor(opts.w or ((text ~= "") and (tw + PAD * 2 + 15) or 24))
  local x, y = cursor(ctx)
  local id = label:find("##", 1, true) and label or (label .. "##kcb")
  local hit = ImGui.InvisibleButton(ctx, id, w, h)
  local hov = ImGui.IsItemHovered(ctx)
  local on = v and true or false
  chip_face(dl, x, y, w, h, on, hov, 0, opts.dim)
  local cx, cy = (text ~= "") and (x + PAD + 3) or (x + w * 0.5), y + h * 0.5
  if on and not opts.dim then
    ImGui.DrawList_AddCircleFilled(dl, cx, cy, 6.5, alpha(COL.accent, 0x40), 16)
    ImGui.DrawList_AddCircleFilled(dl, cx, cy, 4.0, COL.accent, 16)
  else
    ImGui.DrawList_AddCircleFilled(dl, cx, cy, 4.0, COL.toggle_off, 16)
    ImGui.DrawList_AddCircle(dl, cx, cy, 4.0, COL.edge, 16, 1.0)
  end
  if text ~= "" then
    local th = line_h(ctx)
    ImGui.DrawList_AddText(dl, math.floor(x + PAD + 13 + 0.5), math.floor(y + (h - th) * 0.5 + 0.5),
      ink(on, opts.dim), text)
  end
  if hit and not opts.dim then return true, not on end
  return false, on
end

function K.button(ctx, label, kind, w, h, opts)
  opts = opts or {}
  kind = kind or "plain"
  local n_col = 0
  local function pc(name, col) ImGui.PushStyleColor(ctx, E(name), col); n_col = n_col + 1 end
  if kind == "main" then
    pc("Col_Button", COL.accent); pc("Col_ButtonHovered", alpha(COL.accent, 0xd8))
    pc("Col_ButtonActive", COL.hi); pc("Col_Border", COL.accent); pc("Col_Text", 0x0d1116ff)
  elseif kind == "remove" then
    pc("Col_Button", COL.remove_bg); pc("Col_ButtonHovered", alpha(COL.warn, 0x50))
    pc("Col_ButtonActive", alpha(COL.warn, 0x80)); pc("Col_Border", COL.warn); pc("Col_Text", COL.warn)
  end
  local dis = opts.dim and ImGui.BeginDisabled and ImGui.EndDisabled
  if dis then ImGui.BeginDisabled(ctx, true) end
  local hit = ImGui.Button(ctx, label, w or 0, h or 0)
  if dis then ImGui.EndDisabled(ctx) end
  if n_col > 0 then ImGui.PopStyleColor(ctx, n_col) end
  return hit and not opts.dim
end

-- ---------------------------------------------------------------------
-- sliders
-- ---------------------------------------------------------------------
local typing = {}
local held = {}              -- id -> was being dragged last frame

local function fmt_value(fmt, v, int)
  if fmt == "" then return "" end
  fmt = fmt or (int and "%d" or "%.3f")
  local ok, s = pcall(string.format, fmt, int and math.floor(v + 0.5) or v)
  return ok and s or tostring(v)
end

local function slider(ctx, label, v, lo, hi, fmt, int, opts)
  opts = opts or {}
  local cap = K.visible(label)
  local id = label:find("##", 1, true) and label or ("##k" .. label)
  local w = ImGui.CalcItemWidth(ctx) or 120
  if cap ~= "" then
    ImGui.BeginGroup(ctx)
    K.caption(ctx, cap)
  end
  local changed, nv, released = false, v, false
  if typing[id] and not opts.dim then
    ImGui.SetNextItemWidth(ctx, w)
    if typing[id] == 1 then ImGui.SetKeyboardFocusHere(ctx); typing[id] = 2 end
    local ch, tv
    if int then ch, tv = ImGui.InputInt(ctx, "##type" .. id, math.floor(v + 0.5), 0, 0)
    else ch, tv = ImGui.InputDouble(ctx, "##type" .. id, v, 0, 0, "%.3f") end
    if ch and tv then
      tv = math.max(lo, math.min(hi, tv))
      if int then tv = math.floor(tv + 0.5) end
      if tv ~= v then changed, nv = true, tv end
    end
    if ImGui.IsItemDeactivated(ctx) then typing[id] = nil; released = true end
  else
    local dl = ImGui.GetWindowDrawList(ctx)
    local h = frame_h(ctx)
    local text = fmt_value(fmt, v, int)
    local tw = (text ~= "") and (text_w(ctx, text) + 10) or 0
    local bw = math.max(24, w - tw)
    local x, y = cursor(ctx)
    ImGui.InvisibleButton(ctx, id, w, h)
    local hov, act = ImGui.IsItemHovered(ctx), ImGui.IsItemActive(ctx)
    if opts.dim then hov, act = false, false end
    released = held[id] and not act or false
    held[id] = act or nil
    local span = hi - lo
    local lmb = E("MouseButton_Left") or 0
    local ctrl = E("Mod_Ctrl")
    if opts.dim then
      -- drawn, not used
    elseif hov and (ImGui.IsMouseDoubleClicked(ctx, lmb)
                or (ctrl and ImGui.IsMouseClicked(ctx, lmb) and ImGui.IsKeyDown(ctx, ctrl))) then
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
    ImGui.DrawList_AddRectFilled(dl, x0, cy - 2.5, x1, cy + 2.5, COL.chip_on, 2.5)
    local kx = x0 + (x1 - x0) * t
    local fill = opts.dim and alpha(COL.accent, 0x60) or COL.accent
    if kx > x0 then ImGui.DrawList_AddRectFilled(dl, x0, cy - 2.5, kx, cy + 2.5, fill, 2.5) end
    local r = (hov or act) and 7.5 or 6.5
    ImGui.DrawList_AddCircleFilled(dl, kx, cy, r, act and COL.hi or (opts.dim and 0x8a8a8aff or 0xe6e6e6ff), 16)
    ImGui.DrawList_AddCircle(dl, kx, cy, r, 0x00000080, 16, 1.0)
    if text ~= "" then
      local th = line_h(ctx)
      ImGui.DrawList_AddText(dl, math.floor(x + bw + 6 + 0.5), math.floor(y + (h - th) * 0.5 + 0.5),
        opts.dim and COL.dim or COL.text, fmt_value(fmt, nv, int))
    end
  end
  if cap ~= "" then ImGui.EndGroup(ctx) end
  return changed, nv, released
end

function K.slider_double(ctx, label, v, lo, hi, fmt, opts)
  return slider(ctx, label, v or 0, lo, hi, fmt or nil, false, opts or nil)
end

function K.slider_int(ctx, label, v, lo, hi, fmt, opts)
  return slider(ctx, label, math.floor(v or 0), lo, hi, fmt or nil, true, opts or nil)
end

return K
