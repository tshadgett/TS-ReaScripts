-- @noindex
-- Not a package of its own: installed by TS_ChannelView.lua's @provides.
--[[
  TS_CV_KnobEditor.lua -- "Knob look": a knob built from parts, part by part
  (right-click a knob > Style > Customise...).

  On the left the knob as it will look, big, on its own faceplate (or
  aluminium, or the theme), with a slider to turn it; on the right its
  parts -- body, grip, top, pointer, material and colours, the skirt and
  its print, washer and nut, an inner cap, the scale. Start from any
  recipe. Apply it to this knob, its section or every knob on the panel,
  or save it as one of your recipes (TS_CV_Recipes).

  KE.open{ title, look, start, plate, apply = function(look, scope) } --
  `scope` "knob" | "section" | "panel". KE.draw(ctx) every frame.

  A concentric knob is two looks, its outer knob and the inner one on it:
  KE.open{ ..., look = outer, inner = inner_look, start2, apply =
  function(outer, scope, inner) }, with an Outer / Inner switch over the
  parts.
--]]

local C  = require("TS_CV_Config")
local U  = require("TS_CV_Util")
local W  = require("TS_CV_Widgets")
local KP = require("TS_CV_KnobParts")
local RC = require("TS_CV_Recipes")
local CPk = require("TS_CV_ColourPick")

local KE = {}
local ImGui
local st = nil        -- the open editor's state, or nil

function KE.attach(imgui) ImGui = imgui end
function KE.is_open() return st ~= nil end

-- the choices, as { value, label }
local PROFILES = { { "straight", "Straight" }, { "slight", "Slight taper" }, { "tapered", "Tapered" }, { "domed", "Domed" } }
local GRIPS = { { "smooth", "Smooth" }, { "fluted", "Fluted" }, { "knurled", "Knurled" }, { "ridged", "Ridged" },
                { "coin", "Coin edge" }, { "grooves", "Grooves" } }
local TOPS = { { "flat", "Flat" }, { "insert", "Two-tone insert" }, { "recessed", "Recessed" } }
local POINTERS = { { "line", "Line" }, { "dot", "Dot" }, { "inset", "Inset line" }, { "notch", "Notch" },
                   { "chicken", "Chicken-head" }, { "wing", "Wing" }, { "skirtline", "Line across the skirt" },
                   { "none", "None" } }
local MATS = { { "plastic", "Satin plastic" }, { "gloss", "Gloss" }, { "matte", "Matte" }, { "rubber", "Soft-touch" },
               { "metal", "Spun metal" }, { "chrome", "Chrome" }, { "enamel", "Enamel" } }
local SKIRTS = { { false, "None" }, { "plain", "Plain" }, { "printed", "Printed ticks" }, { "dial", "Dial" } }
local SMATS = { { "plastic", "Satin" }, { "matte", "Matte" }, { "metal", "Spun metal" }, { "clear", "Clear" } }
local INKS = { 0xf2f2eeff, 0x1d1e20ff, 0xc8453cff, 0xe6e0d2ff, 0xd9be45ff }
local SCOPES = { { "knob", "This knob" }, { "section", "This section" }, { "panel", "Every knob on this panel" } }

local function caps()
  local out = {}
  for _, c in ipairs(C.CAPS) do if c.col then out[#out + 1] = c.col end end
  return out
end

-- Opens the editor. o.look: the knob's look to start from (copied); o.title;
-- o.plate: its faceplate's colour (0xRRGGBBAA, nil: the theme's); o.apply.
function KE.open(o)
  if st and st.pick then CPk.release(st.pick.s) end
  st = { look = KP.copy(o.look) or { col = 0x26282bff }, title = o.title or "", plate = o.plate,
         apply = o.apply, scope = "knob", turn = 0.62, bg = "panel", name = "", saving = false,
         start = o.start, first = true }
  if o.inner then
    -- a concentric knob: both looks, and which one the parts edit
    st.pair = { outer = st.look, inner = KP.copy(o.inner), start = { outer = o.start, inner = o.start2 } }
    st.part, st.turn2 = "outer", 0.3
  end
end

local function close()
  if st and st.pick then CPk.release(st.pick.s) end
  st = nil
end

local function row_label(ctx, text)
  ImGui.AlignTextToFramePadding(ctx)
  ImGui.TextDisabled(ctx, text)
  ImGui.SameLine(ctx, 96)
end

local function combo(ctx, label, list, now, id, w)
  row_label(ctx, label)
  local cur = list[1][2]
  for _, o in ipairs(list) do if o[1] == now then cur = o[2] end end
  ImGui.SetNextItemWidth(ctx, w or 200)
  local out, changed = now, false
  if ImGui.BeginCombo(ctx, "##ke_" .. id, cur) then
    for i, o in ipairs(list) do
      if ImGui.Selectable(ctx, o[2] .. "##ke_" .. id .. i, o[1] == now) then out, changed = o[1], true end
    end
    ImGui.EndCombo(ctx)
  end
  return changed, out
end

-- a row of colour swatches (and "..." for any colour); `none_label` adds a
-- first choice for no colour. Sets look[field].
local function swatches(ctx, label, field, list, none_label, default)
  row_label(ctx, label)
  local L = st.look
  local now = L[field]
  if none_label then
    -- sized to its text: a Selectable with no width spans the row, and
    -- would take the clicks meant for the swatches after it
    local tw = ImGui.CalcTextSize(ctx, none_label)
    if ImGui.Selectable(ctx, none_label .. "##ke_none_" .. field, now == nil, 0, tw + 6, 0) then L[field] = nil end
    ImGui.SameLine(ctx, 0, 6)
  end
  local dl = ImGui.GetWindowDrawList(ctx)
  for i, col in ipairs(list) do
    if i > 1 or none_label then ImGui.SameLine(ctx, 0, 3) end
    if ImGui.ColorButton(ctx, "##ke_" .. field .. i, col, ImGui.ColorEditFlags_NoTooltip, 16, 16) then L[field] = col end
    if now == col then
      local x0, y0 = ImGui.GetItemRectMin(ctx)
      local x1, y1 = ImGui.GetItemRectMax(ctx)
      ImGui.DrawList_AddRect(dl, x0 - 2, y0 - 2, x1 + 2, y1 + 2, C.COL.header_text, 2.0, 0, 1.5)
    end
  end
  ImGui.SameLine(ctx, 0, 4)
  if ImGui.Button(ctx, "...##ke_any_" .. field) then
    local rgb = ((now or default or 0x808080ff) >> 8) & 0xffffff
    st.pick = { field = field, s = CPk.new_state(rgb) }
  end
  if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "Any colour") end
end

-- the colour tool in place of the parts, for st.pick.field
local function pick_colour(ctx)
  local p = st.pick
  local done = false
  local function keep(rgb)
    st.look[p.field] = ((rgb & 0xffffff) << 8) | 0xff
    CPk.remember(rgb)
    done = true
  end
  ImGui.SeparatorText(ctx, "Any colour")
  local c = CPk.palette(ctx, p.s, "kep")
  if c then keep(c) end
  if not done and #CPk.recent > 0 then
    ImGui.Spacing(ctx)
    ImGui.TextDisabled(ctx, "Recent")
    local r = CPk.recent_row(ctx, "kep")
    if r then keep(r) end
  end
  if not done then
    ImGui.Spacing(ctx)
    CPk.any_colour(ctx, p.s, "kep")
    ImGui.Spacing(ctx)
    if ImGui.Button(ctx, "Use it##kep") then keep(p.s.rgb) end
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, "Cancel##kep") then done = true end
  end
  if done then
    CPk.release(p.s)
    st.pick = nil
  end
end

-- the recipes to start from: the parts-built styles, then yours
local function starts()
  local out = {}
  for _, s in ipairs(C.KNOB_STYLES) do
    if s.parts then out[#out + 1] = { key = s.key, label = s.label, look = s.parts, cap = W.cap_col(s.cap) } end
  end
  for _, r in ipairs(RC.list()) do
    out[#out + 1] = { key = "user:" .. r.name, label = r.name .. " (yours)", look = r.look }
  end
  return out
end

local function preview(ctx)
  local dl = ImGui.GetWindowDrawList(ctx)
  local x, y = ImGui.GetCursorScreenPos(ctx)
  local S = 230
  ImGui.InvisibleButton(ctx, "##ke_prev", S, S)
  local bg = (st.bg == "panel" and st.plate) or (st.bg == "alu" and 0xb9bcbfff) or C.COL.panel_bg
  ImGui.DrawList_AddRectFilled(dl, x, y, x + S, y + S, bg, 4)
  ImGui.DrawList_AddRect(dl, x, y, x + S, y + S, C.COL.panel_border, 4, 0, 1)
  local keep = W.hw
  W.hw = C.EFFECT_3D and C.METAL_K or 0
  if st.pair then
    W.dual_face(dl, x + S * 0.5, y + S * 0.5, S * 0.30, st.turn, st.turn2,
      { look = st.pair.outer, look2 = st.pair.inner, ctx = ctx, hot = nil })
  else
    W.knob_face(dl, x + S * 0.5, y + S * 0.5, S * 0.30, st.turn, { look = st.look, ctx = ctx })
  end
  W.hw = keep
  ImGui.TextDisabled(ctx, st.pair and "Turn the outer knob" or "Turn it")
  ImGui.SetNextItemWidth(ctx, S)
  local ch, v = ImGui.SliderDouble(ctx, "##ke_turn", st.turn, 0, 1, "")
  if ch then st.turn = v end
  if st.pair then
    ImGui.TextDisabled(ctx, "Turn the inner knob")
    ImGui.SetNextItemWidth(ctx, S)
    ch, v = ImGui.SliderDouble(ctx, "##ke_turn2", st.turn2, 0, 1, "")
    if ch then st.turn2 = v end
  end
  ImGui.Spacing(ctx)
  ImGui.TextDisabled(ctx, "Shown on")
  for i, o in ipairs({ { "panel", "This panel" }, { "alu", "Aluminium" }, { "theme", "Theme" } }) do
    if i > 1 then ImGui.SameLine(ctx) end
    if ImGui.RadioButton(ctx, o[2] .. "##ke_bg" .. i, st.bg == o[1]) then st.bg = o[1] end
  end
end

local function parts(ctx)
  local ch, v
  if st.pair then
    -- which of the two the parts below edit
    for i, o in ipairs({ { "outer", "Outer knob" }, { "inner", "Inner knob" } }) do
      if i > 1 then ImGui.SameLine(ctx) end
      if ImGui.RadioButton(ctx, o[2] .. "##ke_part" .. i, st.part == o[1]) then
        st.part = o[1]
        st.look = st.pair[o[1]]
        st.start = st.pair.start[o[1]]
      end
    end
    ImGui.Spacing(ctx)
  end
  local L = st.look
  ImGui.SeparatorText(ctx, "Knob")
  do
    local list = starts()
    row_label(ctx, "Start from")
    ImGui.SetNextItemWidth(ctx, 200)
    local cur = "Choose a recipe"
    for _, s in ipairs(list) do if s.key == st.start then cur = s.label end end
    if ImGui.BeginCombo(ctx, "##ke_start", cur) then
      for i, s in ipairs(list) do
        if ImGui.Selectable(ctx, s.label .. "##ke_st" .. i, s.key == st.start) then
          st.look = KP.copy(s.look)
          if not st.look.col then st.look.col = s.cap end
          st.start = s.key
          if st.pair then st.pair[st.part] = st.look; st.pair.start[st.part] = s.key end
          L = st.look
        end
      end
      ImGui.EndCombo(ctx)
    end
  end
  ch, v = combo(ctx, "Body", PROFILES, L.profile or "straight", "profile")
  if ch then L.profile = (v ~= "straight") and v or nil; L.top_r = nil end
  ch, v = combo(ctx, "Grip", GRIPS, L.grip or "smooth", "grip", 140)
  if ch then L.grip = (v ~= "smooth") and v or nil end
  if L.grip == "fluted" or L.grip == "ridged" or L.grip == "grooves" then
    ImGui.SameLine(ctx)
    ImGui.SetNextItemWidth(ctx, 90)
    local def = (L.grip == "ridged") and 32 or ((L.grip == "grooves") and 6 or 12)
    local cn, nv = ImGui.SliderInt(ctx, "##ke_n", math.floor(L.n or def), 4, 48, "%d")
    if cn then L.n = nv end
  end
  ch, v = combo(ctx, "Face", { { "dome", "Soft dome" }, { "flat", "Flat, flush" } }, L.face or "dome", "face")
  if ch then L.face = (v ~= "dome") and v or nil end
  ch, v = combo(ctx, "Top", TOPS, L.top or "flat", "top")
  if ch then L.top = (v ~= "flat") and v or nil end
  if L.top == "insert" then swatches(ctx, "Insert", "insert", caps(), nil, 0xc9ccd0ff) end
  ch, v = combo(ctx, "Pointer", POINTERS, L.ptr or "line", "ptr")
  if ch then L.ptr = (v ~= "line") and v or nil end
  ch, v = combo(ctx, "Material", MATS, L.mat or "plastic", "mat")
  if ch then L.mat = (v ~= "plastic") and v or nil end
  swatches(ctx, "Colour", "col", caps(), nil, 0x26282bff)
  swatches(ctx, "Sides", "side", caps(), "Darker", 0x6c6e72ff)
  swatches(ctx, "Pointer ink", "ink", INKS, "Auto", 0xf2f2eeff)
  swatches(ctx, "Rim", "rim", INKS, "None", 0xf2f2eeff)

  if st.pair and st.part == "inner" then
    -- no room for a skirt, washer or nut on the inner knob
    ImGui.Spacing(ctx)
    ImGui.TextDisabled(ctx, "The inner knob sits on the outer one: no skirt, washer or nut.")
    return
  end
  ImGui.SeparatorText(ctx, "Skirt")
  ch, v = combo(ctx, "Skirt", SKIRTS, L.skirt or false, "skirt")
  if ch then L.skirt = v or nil end
  if L.skirt then
    ch, v = combo(ctx, "Material", SMATS, L.smat or "plastic", "smat")
    if ch then L.smat = (v ~= "plastic") and v or nil end
    if L.smat ~= "clear" then swatches(ctx, "Colour", "scol", caps(), "Body's", 0x1b1c1eff) end
    if L.skirt ~= "plain" then swatches(ctx, "Print", "sink", INKS, "Auto", 0x1a1a1aff) end
    row_label(ctx, "Size")
    ImGui.SetNextItemWidth(ctx, 140)
    ch, v = ImGui.SliderDouble(ctx, "##ke_sr", L.sr or 1.42, 1.2, 1.7, "%.2f")
    if ch then L.sr = v end
    ImGui.SameLine(ctx)
    local kch, kv = ImGui.Checkbox(ctx, "Knurled edge##ke_sg", L.sgrip == "knurled")
    if kch then L.sgrip = kv and "knurled" or nil end
  end

  ImGui.SeparatorText(ctx, "Extras")
  row_label(ctx, "Under it")
  local wch, wv = ImGui.Checkbox(ctx, "Washer##ke_w", L.washer == true)
  if wch then L.washer = wv or nil end
  ImGui.SameLine(ctx)
  local nch, nv = ImGui.Checkbox(ctx, "Hex nut##ke_nut", L.nut == true)
  if nch then L.nut = nv or nil end
  row_label(ctx, "Centre")
  local ich, iv = ImGui.Checkbox(ctx, "Inner cap, in a groove##ke_in", L.inner ~= nil)
  if ich then L.inner = iv and { r = 0.62, col = 0x9b9b97ff, mat = "bead", screws = true } or nil end
  ch, v = combo(ctx, "Shadow", { { "normal", "Normal" }, { "none", "None (flush)" }, { "tall", "Tall" } },
    L.shadow or "normal", "shadow")
  if ch then L.shadow = (v ~= "normal") and v or nil end
  if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "How far it stands off the panel.") end
  row_label(ctx, "Scale")
  if ImGui.RadioButton(ctx, "Ticks##ke_sc1", L.scale ~= "dots") then L.scale = nil end
  ImGui.SameLine(ctx)
  if ImGui.RadioButton(ctx, "Dots##ke_sc2", L.scale == "dots") then L.scale = "dots" end
end

function KE.draw(ctx)
  if not st then return end
  if st.first then
    ImGui.SetNextWindowSize(ctx, 680, 640, ImGui.Cond_Appearing)
    st.first = false
  end
  local visible, open = ImGui.Begin(ctx, "Knob look" .. (st.title ~= "" and ("  ·  " .. st.title) or "") .. "###cv_knob_look",
    true, ImGui.WindowFlags_NoCollapse)
  if visible then
    if ImGui.BeginChild(ctx, "##ke_left", 240, -64) then
      preview(ctx)
      ImGui.EndChild(ctx)
    end
    ImGui.SameLine(ctx)
    if ImGui.BeginChild(ctx, "##ke_right", 0, -64) then
      if st.pick then pick_colour(ctx) else parts(ctx) end
      ImGui.EndChild(ctx)
    end
    ImGui.Separator(ctx)
    ImGui.AlignTextToFramePadding(ctx)
    ImGui.TextDisabled(ctx, "Apply to")
    for _, o in ipairs(SCOPES) do
      ImGui.SameLine(ctx)
      local lab = (st.pair and o[1] == "panel") and "Every concentric knob on this panel" or o[2]
      if ImGui.RadioButton(ctx, lab .. "##ke_sc_" .. o[1], st.scope == o[1]) then st.scope = o[1] end
    end
    if st.saving then
      ImGui.SetNextItemWidth(ctx, 180)
      local ch, v = ImGui.InputTextWithHint(ctx, "##ke_name", "Recipe name", st.name)
      if ch then st.name = v end
      ImGui.SameLine(ctx)
      if ImGui.Button(ctx, "Save##ke_save") and st.name:match("%S") then
        RC.put(st.name, st.look)
        st.start = "user:" .. st.name
        st.saving = false
      end
      ImGui.SameLine(ctx)
      if ImGui.Button(ctx, "Cancel##ke_savex") then st.saving = false end
    else
      if ImGui.Button(ctx, "Save as recipe...##ke_saveas") then st.saving = true end
    end
    ImGui.SameLine(ctx, ImGui.GetWindowWidth(ctx) - 150)
    local applied = false
    if ImGui.Button(ctx, "Cancel##ke_cancel") then open = false end
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, "Apply##ke_apply") then
      if st.pair then
        if st.apply then st.apply(KP.copy(st.pair.outer), st.scope, KP.copy(st.pair.inner)) end
      elseif st.apply then st.apply(KP.copy(st.look), st.scope) end
      applied = true
    end
    if applied then open = false end
    -- ReaImGui: End only when Begin returned visible
    ImGui.End(ctx)
  end
  if not open then close() end
end

return KE
