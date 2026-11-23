-- @noindex
-- Not a package of its own: installed by TS_ChannelView.lua's @provides.
--[[
  TS_CV_Menus.lua -- ChannelView's menus: a panel's (right-click, its menu
  button), a control's (right-click), a container's (its bracket), the
  faceplate and style menus they hold, and what a panel asks for when
  clicked (panel_requests).

  Made for a window with M.make(env): ChannelView's own, and the TCP
  window's overview (its open row), each with its own `app` -- the track
  and chain the menus act on, and the menu state -- and its own helpers:
    env.ImGui, env.ctx, env.app, env.POP, env.RACK
    env.<module>   the modules they use, as the window has them
    env.insert_target(fx, after), env.layout_for(fx), env.materialise(fx),
    env.nudge(path, dir, what), env.remove_fx(fx), env.rescan(force),
    env.set_fold(fx, on), env.set_parallel(addr, v, what),
    env.toggle_fold(fx)
  Returns { panel_menu, control_menu, box_menu, box_label, box_ancestors,
  link_source, panel_requests, bracket_tip, draw_brackets } (the brackets
  over the panels: app.brackets, app.brk_rows, app.brk_top, app.panel_rects).
--]]

local MN = {}

function MN.make(env)
local ImGui, ctx, app, POP, RACK = env.ImGui, env.ctx, env.app, env.POP, env.RACK
local S = env.S
local B, C, CN, CP, CS, CT, E, ED, KE, KPm, M, MD, ML, P, PC, RCP, RQ, ST, SWI, St, T, TP, TRM, U, W, AF, MX =
  env.B, env.C, env.CN, env.CP, env.CS, env.CT, env.E, env.ED, env.KE, env.KPm, env.M, env.MD, env.ML, env.P, env.PC, env.RCP, env.RQ, env.ST, env.SWI, env.St, env.T, env.TP, env.TRM, env.U, env.W, env.AF, env.MX
local insert_target, layout_for, materialise, nudge, remove_fx, rescan, set_fold, set_parallel, toggle_fold =
  env.insert_target, nil, nil, env.nudge, env.remove_fx, env.rescan, env.set_fold, env.set_parallel, env.toggle_fold
-- A short form's menus (a control on one, TS_CV_Mappings FORMS): while
-- FRM.on is { guid, k }, that plugin's layout is its form k, which M.set
-- saves as the form
local FRM = {}
function FRM.k(fx) return FRM.on and fx and FRM.on.guid == fx.guid and FRM.on.k or nil end
function FRM.set(fx, k) FRM.on = (k and fx) and { guid = fx.guid, k = k } or nil end
-- `fn` for later (another window's Apply): on the form it's on now
function FRM.keep(fx, fn)
  local k = FRM.k(fx)
  return function(...)
    local was = FRM.on
    FRM.set(fx, k)
    fn(...)
    FRM.on = was
  end
end
-- (one not set up yet, as the editor shows it: Full's top rows, saved
-- as the form once it's changed)
layout_for = function(fx)
  local l, k, d = env.layout_for(fx)
  local f = FRM.k(fx)
  if not (f and l and l.grid) then return l, k, d end
  return M.form_of(l, f) or M.form_of(M.form_seed(l, f), f), k, d
end
materialise = function(fx)
  local l, k = env.materialise(fx)
  local f = FRM.k(fx)
  if not (f and l and l.grid) then return l, k end
  if not M.form_of(l, f) then
    M.set(k, M.form_seed(l, f))
    l = M.get(k)
  end
  return M.form_of(l, f), k
end
-- ---------------------------------------------------------------------
-- menus
-- ---------------------------------------------------------------------

local box_menu_items   -- the container menu, below; the panel menu nests it

-- ---------------------------------------------------------------------
-- hardware styles: the Faceplate and Style menus
-- ---------------------------------------------------------------------
-- Both stay open while you click through them, so you can try a few
-- faceplates or cap colours and see each on the panel behind the menu.
-- The flag was renamed in ReaImGui 0.10; either name, or none.
local KEEP_OPEN = 0
do
  for _, n in ipairs({ "SelectableFlags_NoAutoClosePopups", "SelectableFlags_DontClosePopups" }) do
    local ok, v = pcall(function() return ImGui[n] end)
    if ok and type(v) == "number" then KEEP_OPEN = v break end
  end
end

local SWATCH_W, SWATCH_H = 18, 13

-- A menu row with a faceplate's swatch at its front.
local function swatch_row(label, id, selected, width, bg, border, flags)
  local dl = ImGui.GetWindowDrawList(ctx)
  local x, y = ImGui.GetCursorScreenPos(ctx)
  local hit = ImGui.Selectable(ctx, "      " .. label .. "##" .. id, selected, flags or KEEP_OPEN, width, 0)
  local _, th = ImGui.CalcTextSize(ctx, "Ag")
  local sy = y + (th - SWATCH_H) * 0.5
  ImGui.DrawList_AddRectFilled(dl, x + 1, sy, x + 1 + SWATCH_W, sy + SWATCH_H, bg, 2.0)
  ImGui.DrawList_AddRect(dl, x + 1, sy, x + 1 + SWATCH_W, sy + SWATCH_H, border, 2.0, 0, 1.0)
  return hit
end

local function hex_key(rgb) return ("#%06x"):format(rgb & 0xffffff) end

-- ---------------------------------------------------------------------
-- the plugin's own colours (TS_CV_PluginColours): read off its window
-- into its layout's palette, offered in every colour menu (From the
-- plugin) and put on the whole panel by Faceplate > Match the plugin
-- ---------------------------------------------------------------------
local pal_fail = {}     -- fx guid -> why its colours couldn't be read

local function fx_by_guid(guid)
  for _, f in ipairs(app.chain or {}) do
    if f.guid == guid then return f end
  end
  return nil
end

-- a touch lighter (a dark colour) or darker (a light one)
local function lift(rgb)
  local r, g, b = (rgb >> 16) & 0xff, (rgb >> 8) & 0xff, rgb & 0xff
  local d = ((0.299 * r + 0.587 * g + 0.114 * b) < 128) and 18 or -18
  local function ch(v) return math.max(0, math.min(255, v + d)) end
  return (ch(r) << 16) | (ch(g) << 8) | ch(b)
end

-- The panel in the plugin's colours: the faceplate its main surface,
-- sections on their own faceplate its second, controls' own backgrounds
-- its third; buttons lit, and Arc and LED ring knobs and Slim faders
-- coloured, in its first accent. Only what's there is recoloured: a
-- section or background isn't added.
local function match_palette(l, pal)
  local s = pal.surfaces or {}
  if not s[1] then return end
  local s2 = s[2] or lift(s[1])
  local s3 = s[3] or s2
  local a = (pal.accents or {})[1]
  l.plate = hex_key(s[1])
  for _, c in ipairs(l.controls or {}) do
    if c.type == "divider" then
      if c.style == "plate" then c.cap = hex_key(s2) end
    elseif c.back and c.back ~= "inset" then
      c.back = hex_key(s3)
    end
    if a then
      local ks = C.KNOB_STYLE_ALIAS[c.style] or c.style
      if c.type == "toggle" or (c.type == "combo" and c.buttons)
          or ((c.type == "knob" or c.type == "stepped") and not c.look and (ks == "arc" or ks == "led"))
          or (c.type == "fader" and c.style == "slim") then
        c.cap = hex_key(a)
      end
    end
  end
end

-- Read plugin fx's colours into its layout; then `after(layout, pal)`.
local function read_palette(fx, after)
  local guid = fx.guid
  pal_fail[guid] = nil
  local function on_read(pal, why)
    if not pal then pal_fail[guid] = why or "nothing read" return end
    local f = fx_by_guid(guid)
    if not f then return end
    local l, pk = materialise(f)
    l.palette = pal
    if after then after(l, pal) end
    M.set(pk, l); M.save()
  end
  PC.start(app.track, fx.addr, guid, on_read)
end

-- A colour menu's From the plugin row: the plugin's surfaces, then its
-- accents, one click each, and the eyedropper that reads them (again).
local function palette_row(fx, id, pick_key)
  if not fx or not fx.guid or fx.guid == "" or not ED.PRO then return end
  local layout = layout_for(fx)
  local pal = layout and layout.palette
  local dl = ImGui.GetWindowDrawList(ctx)
  ImGui.Spacing(ctx)
  ImGui.TextDisabled(ctx, "From the plugin")
  if not PC.supported() then
    ImGui.SameLine(ctx)
    ImGui.TextDisabled(ctx, "(Windows, with js_ReaScriptAPI)")
    return
  end
  if PC.busy(fx.guid) then
    ImGui.TextDisabled(ctx, "Reading its window\u{2026}")
    return
  end
  local x, y = ImGui.GetCursorScreenPos(ctx)
  if ImGui.Button(ctx, "##" .. id .. "_pread", 18, 18) and not PC.busy() then read_palette(fx) end
  if ImGui.IsItemHovered(ctx) then
    ImGui.SetTooltip(ctx, (pal and "Read the plugin's colours again" or "Read the plugin's colours") ..
      "\n(its window comes to the front for a moment)")
  end
  W.ICONS.dropper(dl, x + 3, y + 3, 12, C.COL.icon)
  local n = 0
  for gi, group in ipairs({ pal and pal.surfaces or {}, pal and pal.accents or {} }) do
    for i, rgb in ipairs(group) do
      ImGui.SameLine(ctx, 0, (i == 1 and gi == 2 and n > 0) and 10 or 4)
      if ImGui.ColorButton(ctx, hex_key(rgb):upper() .. "##" .. id .. "_pal" .. gi .. "_" .. i,
          (rgb << 8) | 0xff, ImGui.ColorEditFlags_NoTooltip, 18, 18) then
        pick_key(hex_key(rgb), true)
        CP.remember(rgb)
      end
      if ImGui.IsItemHovered(ctx) then
        ImGui.SetTooltip(ctx, ((gi == 1) and "Surface  " or "Accent  ") .. hex_key(rgb):upper())
      end
      n = n + 1
    end
  end
  if pal_fail[fx.guid] then
    ImGui.TextDisabled(ctx, "Couldn't read it: " .. pal_fail[fx.guid])
  end
end

-- After a menu's faceplate swatches: the colour of your own it has now
-- (when it has one), the Recent colours flyout -- every custom colour
-- given to a faceplate, background or section since ChannelView started --
-- and the [+] that opens the colour picker (TS_CV_ColourPick), with its
-- palettes and eyedropper. While the picker is open the panel shows the
-- colour being chosen; Cancel puts back what was there.
--   now:   the key chosen now
--   pick_key(k, save): makes key k the choice (nil = none), saving if `save`
--   from:  the colour the picker starts on when there's no custom one
local function custom_rows(id, now, width, pick_key, title, from, fx)
  local ck = C.custom_key(now)
  if ck then
    local pl = C.plate_of(ck)
    swatch_row("Custom  " .. pl.label, id .. "_now", true, width, pl.bg, pl.border)
  end
  palette_row(fx, id, pick_key)
  ImGui.Spacing(ctx)
  if ImGui.BeginMenu(ctx, "Recent colours##" .. id, #CP.recent > 0) then
    for i, rgb in ipairs(CP.recent) do
      local pl = C.plate_of(hex_key(rgb))
      if swatch_row(pl.label, id .. "_rc" .. i, pl.key == ck, 130, pl.bg, pl.border) then
        pick_key(pl.key, true)
        CP.remember(rgb)
      end
    end
    ImGui.EndMenu(ctx)
  end
  if ImGui.IsItemHovered(ctx, ImGui.HoveredFlags_AllowWhenDisabled) and #CP.recent == 0 then
    ImGui.SetTooltip(ctx, "Your custom colours appear here until ChannelView closes.")
  end
  local dl = ImGui.GetWindowDrawList(ctx)
  local x, y = ImGui.GetCursorScreenPos(ctx)
  if ImGui.Selectable(ctx, "      Custom colour\u{2026}##" .. id .. "_add", false, 0, width, 0) then
    local before = now
    CP.open({
      title   = title,
      rgb     = C.custom_rgb(now) or from or 0x808080,
      preview = function(rgb) pick_key(hex_key(rgb), false) end,
      apply   = function(rgb) pick_key(hex_key(rgb), true) end,
      cancel  = function() pick_key(before, false) end,
    })
  end
  if ImGui.IsItemHovered(ctx) then
    ImGui.SetTooltip(ctx, "Pick any colour: palette, picker or eyedropper.")
  end
  -- the [+], where the swatch would be
  local _, th = ImGui.CalcTextSize(ctx, "Ag")
  local sy = y + (th - SWATCH_H) * 0.5
  ImGui.DrawList_AddRect(dl, x + 1, sy, x + 1 + SWATCH_W, sy + SWATCH_H, C.COL.panel_border, 2.0, 0, 1.0)
  local ps = SWATCH_H - 2
  W.ICONS.plus(dl, x + 1 + (SWATCH_W - ps) * 0.5, sy + 1, ps, C.COL.icon)
end

-- Under a row of cap or lit-colour swatches: a [+] that opens the colour
-- picker, the colour of your own the control has now (when it has one),
-- and the recent colours (TS_CV_ColourPick), one click each.
--   now:    the key chosen now (a name, or #rrggbb)
--   from:   0xRRGGBB the picker starts on when there's no custom one
--   pick_key(k, save): makes key k the choice, saving if `save`
local function swatch_extras(id, now, from, title, pick_key, fx)
  local dl = ImGui.GetWindowDrawList(ctx)
  local ck = C.custom_key(now)
  local function outline()
    local x0, y0 = ImGui.GetItemRectMin(ctx)
    local x1, y1 = ImGui.GetItemRectMax(ctx)
    ImGui.DrawList_AddRect(dl, x0 - 2, y0 - 2, x1 + 2, y1 + 2, C.COL.header_text, 3.0, 0, 1.5)
  end
  local x, y = ImGui.GetCursorScreenPos(ctx)
  if ImGui.Button(ctx, "##" .. id .. "_add", 18, 18) then
    local before = now
    CP.open({
      title   = title,
      rgb     = C.custom_rgb(now) or from or 0x808080,
      preview = function(rgb) pick_key(hex_key(rgb), false) end,
      apply   = function(rgb) pick_key(hex_key(rgb), true) end,
      cancel  = function() pick_key(before, false) end,
    })
  end
  if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "Custom colour\u{2026}") end
  W.ICONS.plus(dl, x + 3, y + 3, 12, C.COL.icon)
  local shown = {}
  if ck then
    ImGui.SameLine(ctx, 0, 4)
    ImGui.ColorButton(ctx, ck:upper() .. "##" .. id .. "_now", (C.custom_rgb(ck) << 8) | 0xff,
      ImGui.ColorEditFlags_NoTooltip, 18, 18)
    if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, ck:upper()) end
    outline()
    shown[ck] = true
  end
  for i, rgb in ipairs(CP.recent) do
    local k = hex_key(rgb)
    if not shown[k] then
      ImGui.SameLine(ctx, 0, 4)
      if ImGui.ColorButton(ctx, k:upper() .. "##" .. id .. "_rc" .. i, (rgb << 8) | 0xff,
          ImGui.ColorEditFlags_NoTooltip, 18, 18) then
        pick_key(k, true)
        CP.remember(rgb)
      end
      if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "Recent  " .. k:upper()) end
    end
  end
  palette_row(fx, id, pick_key)
end

-- A faceplate's gradient (TS_CV_Mappings grad_of), as a submenu: none,
-- down, across or radial, and the colour it goes to. `g` the gradient now,
-- `pl` the faceplate (its colour the start), `put(g, save)` sets it.
local function grad_menu(id, g, pl, set_g, fx)
  if ImGui.BeginMenu(ctx, "Gradient##" .. id, pl ~= nil) then
    local dir = g and g.dir or nil
    -- (to start with: the faceplate's colour, darker)
    local function dark()
      local rgb = (pl.bg >> 8) & 0xffffff
      local r, gg, b = (rgb >> 16) & 0xff, (rgb >> 8) & 0xff, rgb & 0xff
      return hex_key((math.floor(r * 0.45) << 16) | (math.floor(gg * 0.45) << 8) | math.floor(b * 0.45))
    end
    for _, d in ipairs({ { nil, "None" }, { "down", "Down" }, { "across", "Across" }, { "radial", "Radial" } }) do
      if ImGui.MenuItem(ctx, d[2] .. "##" .. id .. "_gd" .. d[2], nil, dir == d[1]) then
        set_g(d[1] and { dir = d[1], col = (g and g.col) or dark() } or nil, true)
      end
      if d[1] == "radial" and ImGui.IsItemHovered(ctx) then
        ImGui.SetTooltip(ctx, "The faceplate's colour in the middle, the other out to the corners.")
      end
    end
    ImGui.Separator(ctx)
    ImGui.TextDisabled(ctx, "To")
    local function to(k, save) set_g({ dir = dir or "down", col = k }, save) end
    for _, p2 in ipairs(C.PLATES) do
      if p2.bg and swatch_row(p2.label, id .. "_gc" .. p2.key, g ~= nil and g.col == p2.key, 150, p2.bg, p2.border) then
        to(p2.key, true)
      end
    end
    local now = g and C.plate_of(g.col)
    custom_rows(id .. "_g", g and g.col, 150, to, "Gradient colour", now and (now.bg >> 8), fx)
    ImGui.EndMenu(ctx)
  elseif ImGui.IsItemHovered(ctx, ImGui.HoveredFlags_AllowWhenDisabled) then
    ImGui.SetTooltip(ctx, pl and "From the faceplate's colour to another." or "Choose a faceplate first.")
  end
end

local function plate_menu(fx, key, layout)
  local cur = layout.plate or "theme"
  local dl = ImGui.GetWindowDrawList(ctx)
  -- (the list folds away, as the others do)
  local shown = W.fold_head(ctx, "plate_colours", "Faceplates", KEEP_OPEN)
  for _, pl in ipairs(shown and C.PLATES or {}) do
    local x, y = ImGui.GetCursorScreenPos(ctx)
    if ImGui.Selectable(ctx, "      " .. pl.label .. "##plate_" .. pl.key,
        pl.key == cur, KEEP_OPEN, 150, 0) then
      local l = materialise(fx)
      l.plate = (pl.key ~= "theme") and pl.key or nil
      M.set(key, l); M.save()
    end
    if pl.key == "theme" and ImGui.IsItemHovered(ctx) then
      ImGui.SetTooltip(ctx, "Theme panel colour, follows Hue/Tint.")
    end
    local _, th = ImGui.CalcTextSize(ctx, "Ag")
    local sy = y + (th - SWATCH_H) * 0.5
    ImGui.DrawList_AddRectFilled(dl, x + 1, sy, x + 1 + SWATCH_W, sy + SWATCH_H,
      pl.bg or C.COL.panel_bg, 2.0)
    ImGui.DrawList_AddRect(dl, x + 1, sy, x + 1 + SWATCH_W, sy + SWATCH_H,
      pl.border or C.COL.panel_border, 2.0, 0, 1.0)
  end
  do
    local function set(k, save)
      local l, pk = materialise(fx)
      l.plate = k
      M.set(pk, l)
      if save then M.save() end
    end
    local now_pl = C.plate_of(layout.plate)
    custom_rows("plate", layout.plate, 150, set, "Faceplate colour", now_pl and (now_pl.bg >> 8), fx)
  end
  -- the whole panel in the plugin's colours (read from its window first,
  -- when they haven't been)
  ImGui.Separator(ctx)
  if ImGui.MenuItem(ctx, "Match the plugin##plate_match", nil, false, PC.supported() and not PC.busy()) then
    local l, pk = materialise(fx)
    if l.palette then
      match_palette(l, l.palette)
      M.set(pk, l); M.save()
    else
      read_palette(fx, match_palette)
    end
  end
  if ImGui.IsItemHovered(ctx, ImGui.HoveredFlags_AllowWhenDisabled) then
    ImGui.SetTooltip(ctx, not PC.supported() and "Needs Windows and js_ReaScriptAPI."
      or "The faceplate, section faceplates and backgrounds in the plugin's own\n" ..
         "colours, and its accent on buttons, Arc and LED ring knobs and Slim faders.\n" ..
         "The first time, its window comes to the front for a moment to be read.")
  end
  -- the surface finish, on whichever faceplate is chosen (the theme's has none)
  ImGui.Separator(ctx)
  local plate = C.plate_of(layout.plate)
  local fin = M.finish(layout, plate) or "plain"
  if ImGui.BeginMenu(ctx, "Finish##plate_finish", plate ~= nil) then
    local dflt = (plate and plate.brushed) and "brushed" or "plain"
    for _, f in ipairs(C.FINISHES) do
      if ImGui.MenuItem(ctx, f.label .. "##plate_fin_" .. f.key, nil, fin == f.key) then
        local l = materialise(fx)
        -- the faceplate's own choice is no choice at all, so it isn't saved
        l.brush = nil
        l.finish = (f.key ~= dflt) and f.key or nil
        M.set(key, l); M.save()
      end
    end
    -- how strongly it shows (FinishK)
    ImGui.Separator(ctx)
    local has = fin ~= "plain" and not M.surface_of(fin)
    if not has then ImGui.BeginDisabled(ctx, true) end
    ImGui.TextDisabled(ctx, "Strength")
    ImGui.SetNextItemWidth(ctx, 160)
    local kch, kv = ST.slider_int(ctx, "##plate_fink", layout.fink or 100, 0, 200, "%d%%")
    if kch then
      local l = materialise(fx)
      l.fink = M.fink_of(kv)
      M.set(key, l)
    end
    if ImGui.IsItemDeactivatedAfterEdit(ctx) then M.save() end
    if not has then ImGui.EndDisabled(ctx) end
    ImGui.EndMenu(ctx)
  end
  if ImGui.IsItemHovered(ctx, ImGui.HoveredFlags_AllowWhenDisabled) then
    ImGui.SetTooltip(ctx, plate and "The faceplate's surface." or "Choose a faceplate first.")
  end
  grad_menu("plate", layout.grad, plate, function(g, save)
    local l, pk = materialise(fx)
    l.grad = g
    M.set(pk, l)
    if save then M.save() end
  end, fx)
  -- and/or a metallic flake, like metallic paint
  local mt = M.metal(layout, plate)
  if ImGui.MenuItem(ctx, "Metallic flake##plate_metal", nil, mt, plate ~= nil) then
    local l = materialise(fx)
    l.metal = (not mt) or nil
    M.set(key, l); M.save()
  end
  if ImGui.IsItemHovered(ctx, ImGui.HoveredFlags_AllowWhenDisabled) then
    ImGui.SetTooltip(ctx, plate and "Metallic flake over the finish."
      or "Choose a faceplate first.")
  end
  -- a picture of your own over it, in place of a finish
  if ED.PRO then
    ImGui.Separator(ctx)
    local function put_pic(k, col)
      local l, pk = materialise(fx)
      if k then
        l.finish, l.brush = k, nil
        -- its colour, on average: the ink on it follows
        l.plate = col or l.plate or "#5a5c60"
      elseif M.surface_of(l.finish) then
        l.finish = nil
      end
      M.set(pk, l); M.save()
    end
    KE.surface_tiles(ctx, "plate", layout.finish, put_pic, KEEP_OPEN)
    if ImGui.MenuItem(ctx, "Picture...##plate_pic", nil, M.surface_of(layout.finish) ~= nil) then
      KE.open_surface({ title = fx.name or "", what = "Faceplate", key = layout.finish, apply = put_pic })
    end
    if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "A picture of your own for the faceplate.") end
  end
end

-- The knobs and faders a style can be copied between: a stepped knob is a
-- knob as far as looks go.
local function style_family(t)
  if t == "knob" or t == "stepped" then return "knob" end
  if t == "fader" then return "fader" end
  if t == "toggle" then return "toggle" end
  return nil
end

-- A toggle has no style, only the colour it lights when on (C.TOGGLE_COLS);
-- "Theme" is the theme's own toggle colour, following Hue/Tint.
local function toggle_colour_menu(fx, key, idx, c)
  local dl = ImGui.GetWindowDrawList(ctx)
  local now = c.cap or "theme"
  local function set(v)
    local l = materialise(fx)
    local lc = l.controls[idx]
    if lc then lc.cap = v end
    M.set(key, l); M.save()
  end
  -- the face: flat, or one of the lit ones (W.button_face), each shown lit
  -- in this button's colour (the list folds away)
  if W.fold_head(ctx, "button_styles", "Styles", KEEP_OPEN) then
    -- (a switch's style is lit in its own row below, not Flat's)
    local cur = (not c.img and c.style and (C.BUTTON_STYLE[c.style] or C.SWITCH[c.style])) and c.style or nil
    local lit = W.lit_col(c.cap) or C.COL.toggle_on
    local _, th = ImGui.CalcTextSize(ctx, "Ag")
    local rh = math.max(th, 20)
    for _, bs in ipairs(C.BUTTON_STYLES) do
      local x, y = ImGui.GetCursorScreenPos(ctx)
      if ImGui.Selectable(ctx, "         " .. bs.label .. "##bstyle_" .. bs.key, bs.key == cur,
          KEEP_OPEN, 150, rh) then
        local l = materialise(fx)
        local lc = l.controls[idx]
        -- (a style in place of its pictures)
        if lc then lc.style, lc.img = bs.key, nil end
        M.set(key, l); M.save()
      end
      local bx1, by1, bx2, by2 = x + 3, y + 3, x + 33, y + rh - 3
      if not W.button_face(dl, bx1, by1, bx2, by2, 2.5, true, lit, bs.key, false) then
        ImGui.DrawList_AddRectFilled(dl, bx1, by1, bx2, by2, lit, 2.5)
        ImGui.DrawList_AddRect(dl, bx1, by1, bx2, by2, C.COL.knob_ring, 2.5, 0, 1.0)
      end
    end
    -- a toggle can be a hardware switch instead, each shown on, in the
    -- same list (a step button a push-button one)
    if c.type == "toggle" or (c.type == "combo" and c.buttons == "step") then
      local sh = 30
      for _, sw in ipairs(C.SWITCH_STYLES) do
        if c.type == "toggle" or W.STEP_SWITCH[sw.key] then
          local x, y = ImGui.GetCursorScreenPos(ctx)
          if ImGui.Selectable(ctx, "         " .. sw.label .. "##bstyle_" .. sw.key, sw.key == cur,
              KEEP_OPEN, 150, sh) then
            local l = materialise(fx)
            local lc = l.controls[idx]
            if lc then lc.style, lc.img = sw.key, nil end
            M.set(key, l); M.save()
          end
          SWI.draw(ctx, dl, sw.key, x + 2, y + 1, x + 34, y + sh - 1, true, lit, not C.EFFECT_3D, "ON", false,
            W.lit_col(c.cap))
        end
      end
    end
  end
  if (c.type == "toggle" or (c.type == "combo" and c.buttons == "step")) and ED.PRO then
    ImGui.Spacing(ctx)
    -- your pictures for buttons: one click puts it on this one
    local FNm = ED.module("TS_CV_Finish")
    local pics = FNm and FNm.gallery("button") or {}
    if #pics > 0 and W.fold_head(ctx, "button_pictures", "Your pictures", KEEP_OPEN) then
      local CS = 40
      for i, g in ipairs(pics) do
        if (i - 1) % 6 ~= 0 then ImGui.SameLine(ctx, 0, 2) end
        local x, y = ImGui.GetCursorScreenPos(ctx)
        local picked = ImGui.Selectable(ctx, "##mybpic_" .. i, c.img ~= nil and c.img.file == g.img.file, KEEP_OPEN, CS, CS)
        if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, g.name) end
        local img, iw, ih = W.picture(ctx, g.img, g.img.file2 or g.img.file)
        if img then
          local own_on = g.img.file2 ~= nil
          W.draw_frame(dl, img, iw, ih, own_on and { frames = 1 } or g.img, own_on and 0 or math.min(1, (g.img.frames or 1) - 1),
            x + 3, y + 3, x + CS - 3, y + CS - 3)
        end
        -- (over the picture)
        local from = W.tile_drag(ctx, "pic_button", i, g.name)
        if from then app.tile_move = { "button", from, i } end
        local on_x, x_hit = W.tile_x(ctx, dl, x, y, CS)
        if x_hit then
          if reaper.MB(("Remove the picture \"%s\"?\n\nControls using it keep it."):format(g.name),
              "ChannelView", 4) == 6 then FNm.gallery_remove(g.name) end
        elseif picked and not on_x then
          local l, pk = materialise(fx)
          M.put_img(l, idx, g.img, "knob")
          M.set(pk, l); M.save()
        end
        W.tile_rename(ctx, "pic_button" .. i, g.name, function(new) return FNm.gallery_rename(g.name, new) end)
      end
      if app.tile_move then
        local mv = app.tile_move
        app.tile_move = nil
        FNm.gallery_move(mv[1], mv[2], mv[3])
      end
      ImGui.Spacing(ctx)
    end
    if ImGui.Selectable(ctx, "Image...##bstyle_image", c.img ~= nil, 0, 150, 0) then
      KE.open_image({ title = (fx.name or "") .. "  ·  " .. ((c.label and c.label ~= "") and c.label or "Button"),
                      img = c.img, button = true,
                      apply = FRM.keep(fx, function(im, scope)
                        local l, pk = materialise(fx)
                        M.put_img(l, idx, im, scope)
                        M.set(pk, l); M.save()
                      end) })
    end
    if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "Pictures of your own for Off and On.") end
  end
  ImGui.Spacing(ctx)
  -- a pill rocker doesn't light: its colour is its cap's (TS_CV_Switches)
  local body_col = c.style == "rocker"
  ImGui.TextDisabled(ctx, body_col and "Colour" or "Lit colour")
  for i, cp in ipairs(C.TOGGLE_COLS) do
    if i > 1 then ImGui.SameLine(ctx, 0, 4) end
    -- (a pill rocker with no colour of its own is black)
    local plain = body_col and cp.key == "theme"
    local col = cp.col or (plain and 0x26272bff) or C.COL.toggle_on
    if ImGui.ColorButton(ctx, cp.label .. "##tcol_" .. cp.key, col,
        ImGui.ColorEditFlags_NoTooltip, 18, 18) then
      set((cp.key ~= "theme") and cp.key or nil)
    end
    if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, plain and "Black" or cp.label) end
    if cp.key == now then
      local x0, y0 = ImGui.GetItemRectMin(ctx)
      local x1, y1 = ImGui.GetItemRectMax(ctx)
      ImGui.DrawList_AddRect(dl, x0 - 2, y0 - 2, x1 + 2, y1 + 2, C.COL.header_text, 3.0, 0, 1.5)
    end
  end
  -- any colour: the picker, and the recent ones
  do
    local function choose(k, save)
      local l, pk = materialise(fx)
      local lc = l.controls[idx]
      if lc then lc.cap = k end
      M.set(pk, l)
      if save then M.save() end
    end
    local lit = W.lit_col(c.cap) or C.COL.toggle_on
    swatch_extras("lit", c.cap, lit >> 8, body_col and "Rocker colour" or "Lit colour", choose, fx)
  end
  -- a dropdown's buttons: a lit colour for each choice, too
  if c.type == "combo" then app.choice_colours(fx, key, idx, c) end
  -- small: a half-height lit push-button with its name on it (buttons
  -- for a dropdown's choices have no sizes: their count sets their room)
  if c.type == "toggle" then
    ImGui.Spacing(ctx)
    ImGui.TextDisabled(ctx, "Size")
    local sz_now = (c.size == "small") and "small" or "medium"
    for i, k in ipairs({ "small", "medium" }) do
      if i > 1 then ImGui.SameLine(ctx, 0, 4) end
      if ImGui.Selectable(ctx, C.SIZES[k].label .. "##tsize_" .. k, k == sz_now, KEEP_OPEN, 56, 0) then
        local l = materialise(fx)
        local lc = l.controls[idx]
        if lc then lc.size = (k == "small") and "small" or nil end
        M.set(key, l); M.save()
      end
      if ImGui.IsItemHovered(ctx) then
        ImGui.SetTooltip(ctx, (k == "small") and "Half height, name on the button.\nTwo stack in one cell."
          or "Normal size.")
      end
    end
  end

  ImGui.Spacing(ctx)
  ImGui.Separator(ctx)
  if (c.style or c.img) and ImGui.MenuItem(ctx, "Reset style to default") then
    local l = materialise(fx)
    local lc = l.controls[idx]
    if lc then lc.style, lc.img = nil, nil end
    M.set(key, l); M.save()
  end
  if ImGui.MenuItem(ctx, "Apply to every button on this panel") then
    local l = materialise(fx)
    for _, o in ipairs(l.controls) do
      if o.type == "toggle" or (o.type == "combo" and o.buttons) then o.cap, o.style = c.cap, c.style end
    end
    M.set(key, l); M.save()
  end
end

-- The finish of a control's background or a divider's section: a combo
-- that saves Finish<n>, or clears it when the choice is the one the
-- faceplate makes anyway (aluminium is brushed, an inset isn't).
local function brush_tick(fx, key, idx, c, kind, pl, id)
  local fin = M.part_finish(kind, pl, c.finish, c.brush) or "plain"
  local f_now = C.FINISH[fin] or C.FINISH.plain
  ST.caption(ctx, "Finish")
  ImGui.SetNextItemWidth(ctx, 120)
  if ImGui.BeginCombo(ctx, "##Finish" .. id, f_now.label, ImGui.ComboFlags_HeightLargest) then
    local dflt = M.part_brushed(kind, pl, nil) and "brushed" or "plain"
    for _, f in ipairs(C.FINISHES) do
      if ImGui.Selectable(ctx, f.label .. "##" .. id .. "_" .. f.key, fin == f.key) and kind then
        local l = materialise(fx)
        local lc = l.controls[idx]
        if lc then
          lc.brush = nil
          lc.finish = (f.key ~= dflt) and f.key or nil
        end
        M.set(key, l); M.save()
      end
    end
    ImGui.EndCombo(ctx)
  end
  if ImGui.IsItemHovered(ctx, ImGui.HoveredFlags_AllowWhenDisabled) then
    ImGui.SetTooltip(ctx, kind and "The surface." or "Choose a background first.")
  end
  -- how strongly it shows (FinishK<n>)
  local has = kind and fin ~= "plain" and not M.surface_of(fin)
  if not has then ImGui.BeginDisabled(ctx, true) end
  ST.caption(ctx, "Strength")
  ImGui.SetNextItemWidth(ctx, 160)
  local kch, kv = ST.slider_int(ctx, "##" .. id .. "_fink", c.fink or 100, 0, 200, "%d%%")
  if kch then
    local l = materialise(fx)
    local lc = l.controls[idx]
    if lc then lc.fink = M.fink_of(kv) end
    M.set(key, l)
  end
  if ImGui.IsItemDeactivatedAfterEdit(ctx) then M.save() end
  if not has then ImGui.EndDisabled(ctx) end
  -- and/or a metallic flake (Metal<n>)
  local mt = M.part_metal(kind, c.metal)
  local mch, mv = ST.checkbox(ctx, "Metallic flake##" .. id .. "_m", mt)
  if mch and kind then
    local l = materialise(fx)
    local lc = l.controls[idx]
    if lc then lc.metal = mv or nil end
    M.set(key, l); M.save()
  end
  if ImGui.IsItemHovered(ctx, ImGui.HoveredFlags_AllowWhenDisabled) then
    ImGui.SetTooltip(ctx, kind and "Metallic flake over the finish."
      or "Choose a background first.")
  end
end

-- How round a background's or section's corners are (Corners<n>): the
-- usual slight rounding, soft, or round (fully round ends).
local CORNER_CHOICES = { { nil, "Square" }, { "soft", "Soft" }, { "round", "Round" } }
local function corners_combo(fx, key, idx, c, kind, id)
  local now = M.corners_of(c.corners)
  local label = "Square"
  for _, o in ipairs(CORNER_CHOICES) do if o[1] == now then label = o[2] end end
  ST.caption(ctx, "Corners")
  ImGui.SetNextItemWidth(ctx, 120)
  if ImGui.BeginCombo(ctx, "##Corners" .. id, label, ImGui.ComboFlags_HeightLargest) then
    for _, o in ipairs(CORNER_CHOICES) do
      if ImGui.Selectable(ctx, o[2] .. "##" .. id .. "_" .. (o[1] or "square"), now == o[1]) and kind then
        local l = materialise(fx)
        local lc = l.controls[idx]
        if lc then lc.corners = o[1] end
        M.set(key, l); M.save()
      end
    end
    ImGui.EndCombo(ctx)
  end
  if ImGui.IsItemHovered(ctx, ImGui.HoveredFlags_AllowWhenDisabled) then
    ImGui.SetTooltip(ctx, kind and "Round: fully round ends (other shapes: soft)." or "Choose a background first.")
  end
end

-- A control's own background: nothing (its section's shows), an inset, or
-- a faceplate. Controls next to each other with the same one join up.
local function back_menu(fx, key, idx, c)
  local dl = ImGui.GetWindowDrawList(ctx)
  local now = c.back or "none"
  local function set(v)
    local l = materialise(fx)
    local lc = l.controls[idx]
    if lc then lc.back = v; if not v then lc.brush, lc.metal, lc.finish, lc.corners, lc.fink = nil, nil, nil, nil, nil end end
    M.set(key, l); M.save()
  end
  ImGui.TextDisabled(ctx, "Behind this control")
  if ImGui.Selectable(ctx, "None##back_none", now == "none", KEEP_OPEN, 170, 0) then set(nil) end
  if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "No background of its own.") end
  if ImGui.Selectable(ctx, "Inset##back_inset", now == "inset", KEEP_OPEN, 170, 0) then set("inset") end
  local shown = W.fold_head(ctx, "back_colours", "Faceplates", KEEP_OPEN)
  for _, pl in ipairs(shown and C.PLATES or {}) do
    if pl.bg then
      local x, y = ImGui.GetCursorScreenPos(ctx)
      if ImGui.Selectable(ctx, "      " .. pl.label .. "##back_" .. pl.key, now == pl.key, KEEP_OPEN, 170, 0) then
        set(pl.key)
      end
      local _, th = ImGui.CalcTextSize(ctx, "Ag")
      local sy = y + (th - SWATCH_H) * 0.5
      ImGui.DrawList_AddRectFilled(dl, x + 1, sy, x + 1 + SWATCH_W, sy + SWATCH_H, pl.bg, 2.0)
      ImGui.DrawList_AddRect(dl, x + 1, sy, x + 1 + SWATCH_W, sy + SWATCH_H, pl.border, 2.0, 0, 1.0)
    end
  end
  do
    local function cset(k, save)
      local l, pk = materialise(fx)
      local lc = l.controls[idx]
      if lc then lc.back = k; if not k then lc.brush, lc.metal, lc.finish, lc.corners, lc.fink = nil, nil, nil, nil, nil end end
      M.set(pk, l)
      if save then M.save() end
    end
    local now_pl = C.plate_of(c.back)
    custom_rows("back", c.back, 170, cset, "Background colour", now_pl and (now_pl.bg >> 8), fx)
  end
  ImGui.Separator(ctx)
  local bkind, bpl = P.back_style(c.back)
  ImGui.BeginDisabled(ctx, not bkind)
  brush_tick(fx, key, idx, c, bkind, bpl, "back_brush")
  corners_combo(fx, key, idx, c, bkind, "back_corners")
  ImGui.EndDisabled(ctx)
  -- a picture of your own behind it
  local function put_pic(k, col)
    local l, pk = materialise(fx)
    local lc = l.controls[idx]
    if lc and k then
      lc.finish, lc.brush = k, nil
      lc.back = col or ((lc.back and lc.back ~= "inset") and lc.back) or "#5a5c60"
    elseif lc and M.surface_of(lc.finish) then
      lc.finish = nil
    end
    M.set(pk, l); M.save()
  end
  if ED.PRO then KE.surface_tiles(ctx, "back", c.finish, put_pic, KEEP_OPEN) end
  if ED.PRO and ImGui.Selectable(ctx, "Picture...##back_pic", M.surface_of(c.finish) ~= nil, 0, 170, 0) then
    KE.open_surface({ title = fx.name or "", what = "Background", key = c.finish, apply = FRM.keep(fx, put_pic) })
  end
  ImGui.Spacing(ctx)
  ImGui.TextWrapped(ctx, "Controls side by side or above each other with the same background join into one shape, across a divider too.")
end

-- What a divider does to the section after it (up to the
-- next divider) -- nothing, an inset behind it, or a faceplate of its own.
local function section_menu(fx, key, idx, c)
  local dl = ImGui.GetWindowDrawList(ctx)
  local now = (c.style == "inset" and "inset") or (c.style == "plate" and C.plate_of(c.cap) and c.cap) or "none"
  local function set(style, cap)
    local l = materialise(fx)
    local lc = l.controls[idx]
    if lc then lc.style, lc.cap = style, cap; if not style then lc.brush, lc.metal, lc.finish, lc.corners, lc.fink = nil, nil, nil, nil, nil end end
    M.set(key, l); M.save()
  end
  ImGui.TextDisabled(ctx, c.type == "section" and "The section it's on" or "The controls after this divider")
  if ImGui.Selectable(ctx, "None##sec_none", now == "none", KEEP_OPEN, 170, 0) then set(nil, nil) end
  if ImGui.Selectable(ctx, "Inset##sec_inset", now == "inset", KEEP_OPEN, 170, 0) then set("inset", nil) end
  if ImGui.IsItemHovered(ctx) then
    ImGui.SetTooltip(ctx, "Recessed panel up to the next divider.")
  end
  ImGui.Spacing(ctx)
  local shown = W.fold_head(ctx, "sec_colours", "On a faceplate of their own", KEEP_OPEN)
  for _, pl in ipairs(shown and C.PLATES or {}) do
    if pl.bg then
      local x, y = ImGui.GetCursorScreenPos(ctx)
      if ImGui.Selectable(ctx, "      " .. pl.label .. "##sec_" .. pl.key, now == pl.key, KEEP_OPEN, 170, 0) then
        set("plate", pl.key)
      end
      local _, th = ImGui.CalcTextSize(ctx, "Ag")
      local sy = y + (th - SWATCH_H) * 0.5
      ImGui.DrawList_AddRectFilled(dl, x + 1, sy, x + 1 + SWATCH_W, sy + SWATCH_H, pl.bg, 2.0)
      ImGui.DrawList_AddRect(dl, x + 1, sy, x + 1 + SWATCH_W, sy + SWATCH_H, pl.border, 2.0, 0, 1.0)
    end
  end
  do
    local before_style = c.style
    local function sset(k, save)
      local l, pk = materialise(fx)
      local lc = l.controls[idx]
      if lc then
        if k then lc.style, lc.cap = "plate", k
        elseif before_style == "inset" then lc.style, lc.cap = "inset", nil
        else lc.style, lc.cap, lc.brush, lc.metal, lc.finish, lc.corners, lc.fink = nil, nil, nil, nil, nil, nil, nil end
      end
      M.set(pk, l)
      if save then M.save() end
    end
    local cur = (c.style == "plate") and c.cap or nil
    local now_pl = C.plate_of(cur)
    custom_rows("sec", cur, 170, sset, "Section colour", now_pl and (now_pl.bg >> 8), fx)
  end
  ImGui.Separator(ctx)
  local skind, spl = P.section_style(c)
  ImGui.BeginDisabled(ctx, not skind)
  brush_tick(fx, key, idx, c, skind, spl, "sec_brush")
  corners_combo(fx, key, idx, c, skind, "sec_corners")
  ImGui.EndDisabled(ctx)
  grad_menu("sec", c.grad, (skind == "plate") and spl or nil, function(g, save)
    local l, pk = materialise(fx)
    local lc = l.controls[idx]
    if lc then lc.grad = g end
    M.set(pk, l)
    if save then M.save() end
  end, fx)
  -- a picture of your own for the section
  local function put_pic(k, col)
    local l, pk = materialise(fx)
    local lc = l.controls[idx]
    if lc and k then
      lc.finish, lc.brush = k, nil
      lc.style, lc.cap = "plate", col or ((lc.style == "plate") and lc.cap) or "#5a5c60"
    elseif lc and M.surface_of(lc.finish) then
      lc.finish = nil
    end
    M.set(pk, l); M.save()
  end
  if ED.PRO then KE.surface_tiles(ctx, "sec", c.finish, put_pic, KEEP_OPEN) end
  if ED.PRO and ImGui.Selectable(ctx, "Picture...##sec_pic", M.surface_of(c.finish) ~= nil, 0, 170, 0) then
    KE.open_surface({ title = fx.name or "", what = "Section", key = c.finish, apply = FRM.keep(fx, put_pic) })
  end
end

-- An XY pad's or a concentric knob's look: the colour (the pad's dot, the
-- inner knob) and the size. Neither takes the knob styles.
local dual_style_grid     -- a concentric knob's styles, below
local function pad_style_menu(fx, key, idx, c)
  local dl = ImGui.GetWindowDrawList(ctx)
  local function set(fields)
    local l = materialise(fx)
    local lc = l.controls[idx]
    if lc then for k, v in pairs(fields) do lc[k] = v or nil end end
    M.set(key, l); M.save()
  end
  if c.type == "dual" then dual_style_grid(fx, key, idx, c) end
  ImGui.TextDisabled(ctx, (c.type == "xy") and "Dot colour" or "Inner knob colour")
  for i, cp in ipairs(C.CAPS) do
    if i > 1 then ImGui.SameLine(ctx, 0, 4) end
    if ImGui.ColorButton(ctx, cp.label .. "##pcap_" .. cp.key, cp.col or C.COL.knob_fill,
        ImGui.ColorEditFlags_NoTooltip, 18, 18) then
      set({ cap = (cp.key ~= "accent") and cp.key or false })
    end
    if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, cp.label) end
    if cp.key == (c.cap or "accent") then
      local x0, y0 = ImGui.GetItemRectMin(ctx)
      local x1, y1 = ImGui.GetItemRectMax(ctx)
      ImGui.DrawList_AddRect(dl, x0 - 2, y0 - 2, x1 + 2, y1 + 2, C.COL.header_text, 3.0, 0, 1.5)
    end
  end
  do
    local function choose(k, save)
      local l, pk = materialise(fx)
      local lc = l.controls[idx]
      if lc then lc.cap = k end
      M.set(pk, l)
      if save then M.save() end
    end
    local now_col = W.cap_col(c.cap)
    swatch_extras("pcap", c.cap, now_col and (now_col >> 8), "Colour", choose, fx)
  end
  ImGui.Spacing(ctx)
  ImGui.TextDisabled(ctx, "Size")
  if c.type == "xy" then
    -- columns by rows
    local now = c.size or "2x2"
    for i, k in ipairs({ "2x2", "3x2", "2x3", "3x3" }) do
      if i > 1 then ImGui.SameLine(ctx, 0, 4) end
      if ImGui.Selectable(ctx, k:gsub("x", "\u{00d7}") .. "##psize_" .. k, k == now, KEEP_OPEN, 40, 0) then
        set({ size = (k ~= "2x2") and k or false })
      end
      if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "Columns \u{00d7} rows.") end
    end
  else
    local now = (c.size == "large" or c.size == "xl") and c.size or "medium"
    for i, k in ipairs({ "medium", "large", "xl" }) do
      if i > 1 then ImGui.SameLine(ctx, 0, 4) end
      if ImGui.Selectable(ctx, C.SIZES[k].label .. "##psize_" .. k, k == now, KEEP_OPEN, 56, 0) then
        set({ size = (k ~= "medium") and k or false })
      end
    end
  end
  ImGui.Spacing(ctx)
  ImGui.Separator(ctx)
  if ImGui.MenuItem(ctx, "Reset to default", nil, false, c.cap ~= nil or c.size ~= nil
      or c.style ~= nil or c.look ~= nil or c.style2 ~= nil or c.look2 ~= nil or c.img ~= nil or c.img2 ~= nil) then
    set({ cap = false, size = false, style = false, look = false, style2 = false, look2 = false, img = false, img2 = false })
  end
end

-- A look built from parts onto knob idx, its section (the controls
-- between the dividers either side) or every knob on the panel; each
-- takes its own copy, and its colour from the look.
local function apply_look(fx, idx, look, scope)
  local l, pk = materialise(fx)
  local ctl = l.controls
  local function put(c)
    if c and (c.type == "knob" or c.type == "stepped") then c.look = KPm.copy(look); c.cap, c.img = nil, nil end
  end
  if scope == "section" then
    local function edge(c) return c.type == "divider" or c.type == "page" end
    local a, b = idx, idx
    while a > 1 and not edge(ctl[a - 1]) do a = a - 1 end
    while b < #ctl and not edge(ctl[b + 1]) do b = b + 1 end
    for i = a, b do put(ctl[i]) end
  elseif scope == "panel" then
    for _, c in ipairs(ctl) do put(c) end
  else
    put(ctl[idx])
  end
  M.set(pk, l); M.save()
end

-- A concentric knob's pair of looks (outer, inner) onto knob idx, its
-- section or every concentric knob on the panel, the same way.
local function apply_dual(fx, idx, outer, inner, scope)
  local l, pk = materialise(fx)
  local ctl = l.controls
  local function put(c)
    if c and c.type == "dual" then
      c.look, c.look2, c.cap = KPm.copy(outer), KPm.copy(inner), nil
      if c.style == "arc" then c.style = nil end
    end
  end
  if scope == "section" then
    local function edge(c) return c.type == "divider" or c.type == "page" end
    local a, b = idx, idx
    while a > 1 and not edge(ctl[a - 1]) do a = a - 1 end
    while b < #ctl and not edge(ctl[b + 1]) do b = b + 1 end
    for i = a, b do put(ctl[i]) end
  elseif scope == "panel" then
    for _, c in ipairs(ctl) do put(c) end
  else
    put(ctl[idx])
  end
  M.set(pk, l); M.save()
end

-- A concentric knob's style: the default, the flat Arc, or any parts
-- recipe (or one of yours) for the outer knob, with another for the inner
-- one; Customise... builds both from parts. Thumbnails as the knobs'.
local DUAL_START = "console"      -- Customise... on the default starts here
dual_style_grid = function(fx, key, idx, c)
  local dl = ImGui.GetWindowDrawList(ctx)
  local function set(fields)
    local l = materialise(fx)
    local lc = l.controls[idx]
    if lc then for k, v in pairs(fields) do lc[k] = v or nil end end
    M.set(key, l); M.save()
  end
  local _, th = ImGui.CalcTextSize(ctx, "Ag")
  local COLS, CS = 6, 40
  local hov
  local cap = W.cap_col(c.cap)
  local keep = W.hw
  W.hw = C.EFFECT_3D and C.METAL_K or 0          -- the thumbnails as the panel draws them
  local function thumb(x, y, o)
    o.cap, o.ctx = o.cap or cap, ctx
    W.dual_face(dl, x + CS * 0.5, y + CS * 0.5, CS * 0.5 - 6, 0.35, 0.7, o)
  end
  local title_x, title_y = ImGui.GetCursorScreenPos(ctx)
  ImGui.Dummy(ctx, 10, th)
  local items = { { key = false, label = "Default" }, { key = "arc", label = "Arc (flat)" } }
  for _, st in ipairs(C.KNOB_STYLES) do
    if st.parts then items[#items + 1] = { key = st.key, label = st.label } end
  end
  local now_label = c.look and "Your own look" or "Default"
  for i, it in ipairs(items) do
    if (i - 1) % COLS ~= 0 then ImGui.SameLine(ctx, 0, 2) end
    local x, y = ImGui.GetCursorScreenPos(ctx)
    local on = not c.look and ((it.key or nil) == c.style)
    if on then now_label = it.label end
    if ImGui.Selectable(ctx, "##dstyle_" .. i, on and not c.img, KEEP_OPEN, CS, CS) then
      set({ style = it.key, look = false, img = false })
    end
    if ImGui.IsItemHovered(ctx) then hov = it.label end
    thumb(x, y, { style = it.key or nil, style2 = c.style2, look2 = c.look2 })
  end
  local mine = RCP.list()
  if #mine > 0 then
    ImGui.Spacing(ctx)
    ImGui.TextDisabled(ctx, "Your recipes")
    for i, r in ipairs(mine) do
      if (i - 1) % COLS ~= 0 then ImGui.SameLine(ctx, 0, 2) end
      local x, y = ImGui.GetCursorScreenPos(ctx)
      if ImGui.Selectable(ctx, "##dmine_" .. i, false, KEEP_OPEN, CS, CS) then
        set({ look = KPm.copy(r.look), style = (c.style ~= "arc") and c.style or false, img = false })
      end
      if ImGui.IsItemHovered(ctx) then hov = r.name end
      thumb(x, y, { look = r.look, style2 = c.style2, look2 = c.look2 })
    end
  end
  -- the inner knob, once the outer is a recipe
  local outer, inner, odef, idef = W.dual_looks(c)
  if outer then
    ImGui.Spacing(ctx)
    ImGui.TextDisabled(ctx, "Inner knob")
    local n = 0
    local function cell()
      if n % COLS ~= 0 then ImGui.SameLine(ctx, 0, 2) end
      n = n + 1
      return ImGui.GetCursorScreenPos(ctx)
    end
    for _, st in ipairs(C.KNOB_STYLES) do
      if st.parts then
        local x, y = cell()
        local on = not c.look2 and not c.img2 and (c.style2 or "softtouch") == st.key
        if ImGui.Selectable(ctx, "##dinner_" .. st.key, on, KEEP_OPEN, CS, CS) then
          set({ style2 = (st.key ~= "softtouch") and st.key or false, look2 = false, img2 = false })
        end
        if ImGui.IsItemHovered(ctx) then hov = "Inner: " .. st.label end
        thumb(x, y, { style = c.style, look = c.look, style2 = st.key })
      end
    end
    for i, r in ipairs(mine) do
      local x, y = cell()
      if ImGui.Selectable(ctx, "##dinmine_" .. i, false, KEEP_OPEN, CS, CS) then
        set({ look2 = KPm.copy(r.look), cap = false, img2 = false })
      end
      if ImGui.IsItemHovered(ctx) then hov = "Inner: " .. r.name end
      thumb(x, y, { style = c.style, look = c.look, look2 = r.look })
    end
  end
  W.hw = keep
  ImGui.Spacing(ctx)
  if ImGui.Selectable(ctx, "Customise...##dstyle_custom", false, 0, 150, 0) then
    local o_def = odef or C.KNOB_STYLE[DUAL_START]
    local start = KPm.copy(outer or o_def.parts)
    if not start.col then start.col = W.cap_col(o_def.cap) or 0x26282bff end
    local in_def = idef or C.KNOB_STYLE.softtouch
    local start2 = KPm.copy(inner or in_def.parts)
    start2.skirt, start2.washer, start2.nut = nil, nil, nil
    start2.col = cap or ((not c.look2) and W.cap_col(in_def.cap)) or start2.col or 0x3a3b3eff
    local lay = M.get(key)
    local pl = lay and C.plate_of(lay.plate)
    KE.open({ title = (fx.name or "") .. "  ·  " .. ((c.label and c.label ~= "") and c.label or "Concentric knob"),
              look = start, inner = start2,
              start = (not c.look) and (odef and c.style or DUAL_START) or nil,
              start2 = (not c.look2) and (idef and idef.key) or nil,
              plate = pl and pl.bg or nil,
              apply = FRM.keep(fx, function(o, scope, i) apply_dual(fx, idx, o, i, scope) end) })
  end
  if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "Build both knobs from parts.") end
  -- pictures of your own, for the ring and the inner knob
  if ED.PRO then
    local name = (fx.name or "") .. "  \u{00B7}  " .. ((c.label and c.label ~= "") and c.label or "Concentric knob")
    for _, w in ipairs({ { "img", "Outer image...", "Outer", "The ring as a picture of your own: a filmstrip, or one that turns." },
                         { "img2", "Inner image...", "Inner", "The inner knob as a picture of your own." } }) do
      if ImGui.Selectable(ctx, w[2] .. "##dstyle_" .. w[1], c[w[1]] ~= nil, 0, 150, 0) then
        KE.open_image({ title = name .. "  \u{00B7}  " .. w[3], img = c[w[1]], inner = (w[1] == "img2") or nil,
                        apply = FRM.keep(fx, function(im, scope)
                          local l, pk = materialise(fx)
                          M.put_img(l, idx, im, scope, w[1])
                          M.set(pk, l); M.save()
                        end) })
      end
      if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, w[4]) end
    end
  end
  if c.img then now_label = "Your picture" end
  ImGui.DrawList_AddText(dl, title_x, title_y, C.COL.header_dim or 0x9a9a9aff, "Style: " .. (hov or now_label))
  ImGui.Spacing(ctx)
  ImGui.Separator(ctx)
end

-- A dropdown's colours per choice (ChoiceCol<n>): a submenu with a row
-- for each of its choices (your names), each opening the lit colours and
-- the picker. Kept by the plugin's text, so they follow the choice. The
-- list is read when the menu opens, and again every second or so.
function app.choice_colours(fx, key, idx, c)
  if not (c.param and c.param >= 0) then return end
  ImGui.Spacing(ctx)
  local n_set = 0
  for _ in pairs(c.ccols or {}) do n_set = n_set + 1 end
  local function rows()
    local tag = fx.guid .. ":" .. c.param
    local now_t = reaper.time_precise()
    local cl = app.ccol_list
    if not cl or cl.tag ~= tag or now_t > cl.until_t then
      local raw = P.read_choices(app.track, fx.addr, c.param, key)
        or P.button_choices(app.track, fx.addr, c.param, key, c.nbtn)
      cl = { tag = tag, until_t = now_t + 1.5, list = raw }
      app.ccol_list = cl
    end
    local list = (type(cl.list) == "table") and M.choice_list(key, c.param, cl.list, app.track, fx.addr) or nil
    local function set_col(raw, k, save)
      local l, pk = materialise(fx)
      local lc = l.controls[idx]
      if lc then
        lc.ccols = lc.ccols or {}
        lc.ccols[raw] = k
        if not next(lc.ccols) then lc.ccols = nil end
      end
      M.set(pk, l)
      if save then M.save() end
    end
    if type(list) ~= "table" or #list < 2 then
      ImGui.TextDisabled(ctx, "Open the dropdown once to read its choices.")
    else
      local dl = ImGui.GetWindowDrawList(ctx)
      local _, th = ImGui.CalcTextSize(ctx, "Ag")
      for i, e in ipairs(list) do
        local raw = U.trim(e.raw or e.text or tostring(i))
        local ck = c.ccols and c.ccols[raw]
        local col = W.lit_col(ck)
        local x, y = ImGui.GetCursorScreenPos(ctx)
        local open = ImGui.BeginMenu(ctx, "      " .. (e.text or raw) .. "##ccrow" .. i)
        local sy = y + (th - SWATCH_H) * 0.5
        if col then
          ImGui.DrawList_AddRectFilled(dl, x + 1, sy, x + 1 + SWATCH_W, sy + SWATCH_H, col, 2.0)
        end
        ImGui.DrawList_AddRect(dl, x + 1, sy, x + 1 + SWATCH_W, sy + SWATCH_H, C.COL.panel_border, 2.0, 0, 1.0)
        if open then
          for j, cp in ipairs(C.TOGGLE_COLS) do
            if j > 1 then ImGui.SameLine(ctx, 0, 4) end
            local none = cp.key == "theme"
            if ImGui.ColorButton(ctx, cp.label .. "##ccc_" .. i .. cp.key, cp.col or C.COL.knob_body,
                ImGui.ColorEditFlags_NoTooltip, 18, 18) then
              set_col(raw, (not none) and cp.key or nil, true)
            end
            if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, none and "None: the control's colour" or cp.label) end
            if none then
              local x0, y0 = ImGui.GetItemRectMin(ctx)
              local x1, y1 = ImGui.GetItemRectMax(ctx)
              ImGui.DrawList_AddLine(ImGui.GetWindowDrawList(ctx), x0 + 3, y1 - 3, x1 - 3, y0 + 3, C.COL.label, 1.5)
            end
            if (none and not ck) or cp.key == ck then
              local x0, y0 = ImGui.GetItemRectMin(ctx)
              local x1, y1 = ImGui.GetItemRectMax(ctx)
              ImGui.DrawList_AddRect(ImGui.GetWindowDrawList(ctx), x0 - 2, y0 - 2, x1 + 2, y1 + 2, C.COL.header_text, 3.0, 0, 1.5)
            end
          end
          swatch_extras("ccx" .. i, ck, col and (col >> 8) or nil, (e.text or raw) .. " colour",
            function(k, save) set_col(raw, k, save) end, fx)
          ImGui.EndMenu(ctx)
        end
      end
      if n_set > 0 then
        ImGui.Separator(ctx)
        if ImGui.MenuItem(ctx, "Clear all##ccclear") then
          local l = materialise(fx)
          local lc = l.controls[idx]
          if lc then lc.ccols = nil end
          M.set(key, l); M.save()
        end
      end
    end
  end
  if ImGui.BeginMenu(ctx, "Choice colours" .. (n_set > 0 and ("  (" .. n_set .. ")") or "") .. "##ccols") then
    rows()
    ImGui.EndMenu(ctx)
  elseif ImGui.IsItemHovered(ctx) then
    ImGui.SetTooltip(ctx, "A colour for each choice.")
  end
end

-- A dropdown's look: printed flat on the faceplate, or raised (a backlit
-- button's cap, unlit, standing off it). A button row's lit styles count
-- as raised on a dropdown (W.combo_raised).
local function combo_style_menu(fx, key, idx, c)
  local dl = ImGui.GetWindowDrawList(ctx)
  local raised = W.combo_raised(c.style)
  local cur = c.style
  local function set(v)
    local l = materialise(fx)
    local lc = l.controls[idx]
    if lc then lc.style = v end
    M.set(key, l); M.save()
  end
  ImGui.TextDisabled(ctx, "Style")
  local _, th = ImGui.CalcTextSize(ctx, "Ag")
  local rh = math.max(th, 20)
  for _, o in ipairs({ { "flat", "Flat", "Printed on the faceplate." },
                       { "raised", "Raised", "A backlit button's cap, unlit, standing off the faceplate." },
                       { "minimal", "Minimal", "A flat block, no outline." } }) do
    local x, y = ImGui.GetCursorScreenPos(ctx)
    local on = (o[1] == "raised") and raised or (cur == o[1])
    if ImGui.Selectable(ctx, "            " .. o[2] .. "##cstyle_" .. o[2], on, KEEP_OPEN, 160, rh) then
      set(o[1])
    end
    if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, o[3]) end
    W.combo_swatch(dl, x + 3, y + 3, x + 41, y + rh - 3, o[1] == "raised", o[1] == "minimal")
  end
  if c.style and ImGui.MenuItem(ctx, "Reset to default") then set(nil) end
  -- its text's colour: the theme's, a lamp colour or your own
  ImGui.Spacing(ctx)
  ImGui.TextDisabled(ctx, "Text colour")
  do
    local now = c.cap or "theme"
    local function choose(k, save)
      local l, pk = materialise(fx)
      local lc = l.controls[idx]
      if lc then lc.cap = k end
      M.set(pk, l)
      if save then M.save() end
    end
    for i, cp in ipairs(C.TOGGLE_COLS) do
      if i > 1 then ImGui.SameLine(ctx, 0, 4) end
      if ImGui.ColorButton(ctx, cp.label .. "##ctcol_" .. cp.key, cp.col or C.COL.toggle_text,
          ImGui.ColorEditFlags_NoTooltip, 18, 18) then
        choose((cp.key ~= "theme") and cp.key or nil, true)
      end
      if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, cp.label) end
      if cp.key == now then
        local x0, y0 = ImGui.GetItemRectMin(ctx)
        local x1, y1 = ImGui.GetItemRectMax(ctx)
        ImGui.DrawList_AddRect(dl, x0 - 2, y0 - 2, x1 + 2, y1 + 2, C.COL.header_text, 3.0, 0, 1.5)
      end
    end
    local ink = W.lit_col(c.cap) or C.COL.toggle_text
    swatch_extras("ctext", c.cap, ink >> 8, "Text colour", choose, fx)
  end
  -- the box's own colour: the theme's, a faceplate's or your own
  ImGui.Spacing(ctx)
  ImGui.TextDisabled(ctx, "Box colour")
  do
    local now = C.plate_key(c.boxc)
    local function choose(k, save)
      local l, pk = materialise(fx)
      local lc = l.controls[idx]
      if lc then lc.boxc = k end
      M.set(pk, l)
      if save then M.save() end
    end
    local n = 0
    local function mark()
      local x0, y0 = ImGui.GetItemRectMin(ctx)
      local x1, y1 = ImGui.GetItemRectMax(ctx)
      ImGui.DrawList_AddRect(dl, x0 - 2, y0 - 2, x1 + 2, y1 + 2, C.COL.header_text, 3.0, 0, 1.5)
    end
    if ImGui.ColorButton(ctx, "Theme##cbox_theme", W.combo_raised(c.style) and C.COL.toggle_off or C.COL.knob_body,
        ImGui.ColorEditFlags_NoTooltip, 18, 18) then
      choose(nil, true)
    end
    if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "Theme") end
    if not now then mark() end
    for _, pl in ipairs(C.PLATES) do
      if pl.bg then
        n = n + 1
        if n % 8 ~= 0 then ImGui.SameLine(ctx, 0, 4) end
        if ImGui.ColorButton(ctx, pl.label .. "##cbox_" .. pl.key, pl.bg, ImGui.ColorEditFlags_NoTooltip, 18, 18) then
          choose(pl.key, true)
        end
        if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, pl.label) end
        if now == pl.key then mark() end
      end
    end
    local pl_now = now and C.plate_of(now)
    swatch_extras("cbox", c.boxc, pl_now and (pl_now.bg >> 8), "Box colour", choose, fx)
  end
  app.choice_colours(fx, key, idx, c)
  ImGui.Spacing(ctx)
  ImGui.Separator(ctx)
  if ImGui.MenuItem(ctx, "Apply to every dropdown on this panel") then
    local l = materialise(fx)
    for _, o in ipairs(l.controls) do
      if o.type == "combo" and not o.buttons then o.style, o.boxc = c.style, c.boxc end
    end
    M.set(key, l); M.save()
  end
end

local function style_menu(fx, key, idx, c)
  if c.type == "xy" or c.type == "dual" then return pad_style_menu(fx, key, idx, c) end
  if c.type == "combo" and not c.buttons then return combo_style_menu(fx, key, idx, c) end
  local fam = style_family(c.type)
  if fam == "toggle" or c.type == "combo" then return toggle_colour_menu(fx, key, idx, c) end
  local list = (fam == "fader") and C.FADER_STYLES or C.KNOB_STYLES
  -- (no style: Options' default, Reset to default below)
  local cur = C.KNOB_STYLE_ALIAS[c.style] or c.style
  local dl = ImGui.GetWindowDrawList(ctx)
  local _, th = ImGui.CalcTextSize(ctx, "Ag")
  local row_h = (fam == "knob") and math.max(th, 26) or 0

  local function set(fields)
    local l = materialise(fx)
    local lc = l.controls[idx]
    if lc then for k, v in pairs(fields) do lc[k] = v or nil end end
    M.set(key, l); M.save()
  end

  if fam == "knob" then
    -- the knobs as a grid of thumbnails, each in this knob's colour; the
    -- name of the one under the pointer (or the chosen one) above them
    local now_def = (not c.look) and C.KNOB_STYLE[cur] or nil
    local hov_label
    local title_x, title_y = ImGui.GetCursorScreenPos(ctx)
    ImGui.Dummy(ctx, 10, th)
    local COLS, CS = 6, 40
    -- (each list folds away: they grow long)
    if W.fold_head(ctx, "knob_styles", "Styles", KEEP_OPEN) then
      for i, st in ipairs(list) do
        if (i - 1) % COLS ~= 0 then ImGui.SameLine(ctx, 0, 2) end
        local x, y = ImGui.GetCursorScreenPos(ctx)
        if ImGui.Selectable(ctx, "##style_" .. st.key, st.key == cur and not c.look and not c.img, KEEP_OPEN, CS, CS) then
          set({ style = st.key, look = false, img = false })
        end
        if ImGui.IsItemHovered(ctx) then hov_label = st.label end
        local r = CS * 0.5 - 6     -- the scale ticks sit outside this
        W.knob_face(dl, x + CS * 0.5, y + CS * 0.5, r, 0.62,
          { style = st.key, cap = W.cap_col(c.cap), ctx = ctx })
      end
    end
    -- your recipes: looks you've saved from Customise...
    local mine = RCP.list()
    if #mine > 0 then
      ImGui.Spacing(ctx)
    end
    if #mine > 0 and W.fold_head(ctx, "knob_recipes", "Your recipes", KEEP_OPEN) then
      for i, r in ipairs(mine) do
        if (i - 1) % COLS ~= 0 then ImGui.SameLine(ctx, 0, 2) end
        local x, y = ImGui.GetCursorScreenPos(ctx)
        local picked = ImGui.Selectable(ctx, "##myrecipe_" .. i, false, KEEP_OPEN, CS, CS)
        if ImGui.IsItemHovered(ctx) then hov_label = r.name end
        W.knob_face(dl, x + CS * 0.5, y + CS * 0.5, CS * 0.5 - 6, 0.62, { look = r.look, ctx = ctx })
        -- drag one onto another to move it there; an x in its corner takes
        -- it away, once you've said so; right-click to rename it
        local from = W.tile_drag(ctx, "recipe", i, r.name)
        if from then app.tile_move = { "recipe", from, i } end
        local on_x, x_hit = W.tile_x(ctx, dl, x, y, CS)
        if x_hit then
          if reaper.MB(("Remove the recipe \"%s\"?\n\nKnobs wearing it keep their look."):format(r.name),
              "ChannelView", 4) == 6 then RCP.remove(r.name) end
        elseif picked and not on_x then
          set({ look = KPm.copy(r.look), cap = false, img = false })
        end
        W.tile_rename(ctx, "recipe" .. i, r.name, function(new) return RCP.rename(r.name, new) end)
      end
    end
    -- your pictures (Style > Image...): one click puts it on this knob
    local FNm = ED.PRO and ED.module("TS_CV_Finish")
    local pics = (FNm and c.type ~= "dual") and FNm.gallery("knob") or {}
    if #pics > 0 then
      ImGui.Spacing(ctx)
    end
    if #pics > 0 and W.fold_head(ctx, "knob_pictures", "Your pictures", KEEP_OPEN) then
      for i, g in ipairs(pics) do
        if (i - 1) % COLS ~= 0 then ImGui.SameLine(ctx, 0, 2) end
        local x, y = ImGui.GetCursorScreenPos(ctx)
        local picked = ImGui.Selectable(ctx, "##mypic_" .. i, c.img ~= nil and c.img.file == g.img.file, KEEP_OPEN, CS, CS)
        if ImGui.IsItemHovered(ctx) then hov_label = g.name end
        W.picture_knob(ctx, dl, x + CS * 0.5, y + CS * 0.5, CS * 0.5 - 6, 0.62, g.img, false)
        local from = W.tile_drag(ctx, "pic_knob", i, g.name)
        if from then app.tile_move = { "knob", from, i } end
        local on_x, x_hit = W.tile_x(ctx, dl, x, y, CS)
        if x_hit then
          if reaper.MB(("Remove the picture \"%s\"?\n\nControls using it keep it."):format(g.name),
              "ChannelView", 4) == 6 then FNm.gallery_remove(g.name) end
        elseif picked and not on_x then
          local l, pk = materialise(fx)
          M.put_img(l, idx, g.img, "knob")
          M.set(pk, l); M.save()
        end
        W.tile_rename(ctx, "pic_knob" .. i, g.name, function(new) return FNm.gallery_rename(g.name, new) end)
      end
    end
    -- a tile dragged onto another: moved there (once the lists are drawn)
    if app.tile_move then
      local mv = app.tile_move
      app.tile_move = nil
      if mv[1] == "recipe" then RCP.move(mv[2], mv[3])
      elseif FNm then FNm.gallery_move(mv[1], mv[2], mv[3]) end
    end
    ImGui.Spacing(ctx)
    if ImGui.Selectable(ctx, "Customise...##style_custom", false, 0, 150, 0) then
      local def = C.KNOB_STYLE[cur]
      local start = c.look and KPm.copy(c.look) or (def and def.parts and KPm.copy(def.parts)) or {}
      if not c.look then start.col = W.cap_col(c.cap) or (def and W.cap_col(def.cap)) or start.col or 0x26282bff
      elseif c.cap then start.col = W.cap_col(c.cap) end
      local lay = M.get(key)
      local pl = lay and C.plate_of(lay.plate)
      KE.open({ title = (fx.name or "") .. "  ·  " .. ((c.label and c.label ~= "") and c.label or "Knob"),
                look = start, start = (not c.look and def and def.parts) and cur or nil,
                plate = pl and pl.bg or nil,
                apply = FRM.keep(fx, function(look, scope) apply_look(fx, idx, look, scope) end) })
    end
    if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "Build this knob from parts.") end
    if c.type ~= "dual" and ImGui.Selectable(ctx, "Image...##style_image", c.img ~= nil, 0, 150, 0) then
      KE.open_image({ title = (fx.name or "") .. "  ·  " .. ((c.label and c.label ~= "") and c.label or "Knob"),
                      img = c.img,
                      apply = FRM.keep(fx, function(im, scope)
                        local l, pk = materialise(fx)
                        M.put_img(l, idx, im, scope)
                        M.set(pk, l); M.save()
                      end) })
    end
    if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "A picture of your own: a filmstrip, or one that turns.") end
    ImGui.DrawList_AddText(dl, title_x, title_y, C.COL.header_dim or 0x9a9a9aff,
      "Style: " .. (hov_label or (c.img and "Your picture") or (now_def and now_def.label) or (c.look and "Your own look") or "Default"))
  else
    ImGui.TextDisabled(ctx, "Style")
    for _, st in ipairs(list) do
      if ImGui.Selectable(ctx, st.label .. "##style_" .. st.key, st.key == cur and not c.img, KEEP_OPEN, 150, row_h) then
        set({ style = st.key, img = false })
      end
    end
    -- a fader of your own pictures: its cap over its slot, or a filmstrip
    if fam == "fader" and ED.PRO then
      if ImGui.Selectable(ctx, "Image...##style_fimage", c.img ~= nil, 0, 150, 0) then
        KE.open_image({ title = (fx.name or "") .. "  \u{00B7}  " .. ((c.label and c.label ~= "") and c.label or "Fader"),
                        img = c.img, fader = true, across = c.dir == "h",
                        apply = FRM.keep(fx, function(im, scope)
                          local l, pk = materialise(fx)
                          M.put_img(l, idx, im, scope)
                          M.set(pk, l); M.save()
                        end) })
      end
      if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "Pictures of your own: a cap over a slot, or a filmstrip.") end
    end
  end

  -- a fader's shape: which way it runs, how long, how thick (Shape<n>).
  -- Full length and a full column is the standard fader.
  if fam == "fader" then
    ImGui.Spacing(ctx)
    ImGui.TextDisabled(ctx, "Shape")
    local function row(name, choices, now, apply)
      ImGui.Text(ctx, name)
      for i, ch in ipairs(choices) do
        if i == 1 then ImGui.SameLine(ctx, 76) else ImGui.SameLine(ctx) end
        if ImGui.Selectable(ctx, ch[2] .. "##shape_" .. name .. i, now == ch[1], KEEP_OPEN, 36, 0) then
          apply(ch[1])
        end
      end
    end
    row("Direction", { { false, "Up" }, { "h", "Across" } }, c.dir or false,
      function(v) set({ dir = v }) end)
    row("Length", { { 1, "1" }, { 2, "2" }, { 3, "3" }, { 4, "4" }, { false, "Full" } }, c.len or false,
      function(v) set({ len = v }) end)
    row("Thickness", { { false, "Full" }, { true, "Half" } }, c.thin or false,
      function(v) set({ thin = v }) end)
    if ImGui.IsItemHovered(ctx) then
      ImGui.SetTooltip(ctx, "Half: half-width, for faders side by side.")
    end
  end

  ImGui.Spacing(ctx)
  ImGui.TextDisabled(ctx, "Colour")
  local style_def = (fam == "fader") and C.FADER_STYLE[cur] or C.KNOB_STYLE[cur]
  local cap_now = c.cap or (style_def and style_def.cap)
  for i, cp in ipairs(C.CAPS) do
    if i > 1 then ImGui.SameLine(ctx, 0, 4) end
    local col = cp.col or C.COL.knob_fill
    if ImGui.ColorButton(ctx, cp.label .. "##cap_" .. cp.key, col,
        ImGui.ColorEditFlags_NoTooltip, 18, 18) then
      set({ cap = cp.key })
    end
    if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, cp.label) end
    if cp.key == cap_now then
      local x0, y0 = ImGui.GetItemRectMin(ctx)
      local x1, y1 = ImGui.GetItemRectMax(ctx)
      ImGui.DrawList_AddRect(dl, x0 - 2, y0 - 2, x1 + 2, y1 + 2, C.COL.header_text, 3.0, 0, 1.5)
    end
  end
  -- any colour: the picker, and the recent ones
  do
    local function choose(k, save)
      local l, pk = materialise(fx)
      local lc = l.controls[idx]
      if lc then lc.cap = k end
      M.set(pk, l)
      if save then M.save() end
    end
    local now_col = W.cap_col(cap_now)
    swatch_extras("cap", c.cap, now_col and (now_col >> 8),
      (fam == "fader") and "Fader cap colour" or "Knob colour", choose, fx)
  end

  -- knobs come in three sizes (C.SIZES); the panel reflows round them
  if fam == "knob" then
    ImGui.Spacing(ctx)
    ImGui.TextDisabled(ctx, "Size")
    local now = c.size or "medium"
    for i, k in ipairs(C.SIZE_LIST) do
      if i > 1 then ImGui.SameLine(ctx, 0, 4) end
      if ImGui.Selectable(ctx, C.SIZES[k].label .. "##size_" .. k, k == now, KEEP_OPEN, 56, 0) then
        set({ size = (k ~= "medium") and k or false })
      end
      if ImGui.IsItemHovered(ctx) then
        ImGui.SetTooltip(ctx, (k == "small") and "Half height, value in the tooltip.\nTwo stack in one cell."
          or (k == "large") and "One and a half times the size.\nNormal size in a one-row panel."
          or (k == "xl") and "Twice the size: two cells by two.\nNormal size in a panel under two rows."
          or "Normal size.")
      end
    end

    -- a value arc in place of the scale's ticks or dots (on an Arc knob,
    -- the way its own arc fills): from the start, from the end, or out
    -- from the middle; for this knob, its section or the whole panel.
    -- Centred also makes the knob centred (c.bipolar): an Arc or LED ring
    -- face fills from the middle, and a modulator swings it both ways. An
    -- Arc or LED ring knob that's centred without an arc reads as Centred.
    ImGui.Spacing(ctx)
    ImGui.TextDisabled(ctx, "Value arc")
    local ARCS = { { false, "Off", "The knob's own scale ticks or dots." },
                   { "pos", "Positive", "Lit from the start of the travel up to the value." },
                   { "neg", "Negative", "Lit from the end of the travel back to the value." },
                   { "mid", "Centred", "Lit out from the middle to the value.\n" ..
                                       "A modulator swings it both ways round its setting." } }
    local own_face = not c.look and (cur == "arc" or cur == "led")
    local arc_now = c.arc or ((c.bipolar and own_face) and "mid") or false
    for i, a in ipairs(ARCS) do
      if i > 1 then ImGui.SameLine(ctx, 0, 4) end
      if ImGui.Selectable(ctx, a[2] .. "##varc_" .. i, arc_now == a[1], KEEP_OPEN, 64, 0) then
        set({ arc = a[1], bipolar = (a[1] == "mid") })
      end
      if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, a[3]) end
    end
    local function arc_to(scope)
      local l, pk = materialise(fx)
      local ctl = l.controls
      local function put(o)
        if o and (o.type == "knob" or o.type == "stepped") then o.arc, o.bipolar, o.arcc = c.arc, c.bipolar, c.arcc end
      end
      if scope == "section" then
        local function edge(o) return o.type == "divider" or o.type == "page" end
        local a, b = idx, idx
        while a > 1 and not edge(ctl[a - 1]) do a = a - 1 end
        while b < #ctl and not edge(ctl[b + 1]) do b = b + 1 end
        for i = a, b do put(ctl[i]) end
      else
        for _, o in ipairs(ctl) do put(o) end
      end
      M.set(pk, l); M.save()
    end
    -- its colour: the theme's fill unless one is picked (an Arc or LED
    -- ring knob's own arc is its Colour, above)
    if arc_now and not own_face then
      ImGui.Spacing(ctx)
      ImGui.TextDisabled(ctx, "Arc colour")
      local arc_cur = c.arcc or "accent"
      for i, cp in ipairs(C.CAPS) do
        if i > 1 then ImGui.SameLine(ctx, 0, 4) end
        local col = cp.col or ((arc_now == "mid") and C.COL.knob_fill_bi or C.COL.knob_fill)
        if ImGui.ColorButton(ctx, cp.label .. "##arcc_" .. cp.key, col, ImGui.ColorEditFlags_NoTooltip, 18, 18) then
          set({ arcc = (cp.key ~= "accent") and cp.key or false })
        end
        if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, (cp.key == "accent") and "Theme" or cp.label) end
        if cp.key == arc_cur then
          local x0, y0 = ImGui.GetItemRectMin(ctx)
          local x1, y1 = ImGui.GetItemRectMax(ctx)
          ImGui.DrawList_AddRect(dl, x0 - 2, y0 - 2, x1 + 2, y1 + 2, C.COL.header_text, 3.0, 0, 1.5)
        end
      end
      local function choose_arc(k, save)
        local l, pk = materialise(fx)
        local lc = l.controls[idx]
        if lc then lc.arcc = k end
        M.set(pk, l)
        if save then M.save() end
      end
      local now_ac = W.cap_col(c.arcc) or C.COL.knob_fill
      swatch_extras("arcc", c.arcc, now_ac >> 8, "Arc colour", choose_arc, fx)
    end
    if ImGui.Selectable(ctx, "The same for its section##varc_sec", false, KEEP_OPEN, 160, 0) then arc_to("section") end
    ImGui.SameLine(ctx, 0, 4)
    if ImGui.Selectable(ctx, "For the whole panel##varc_all", false, KEEP_OPEN, 140, 0) then arc_to("panel") end

    -- the numbers round the dial are chosen under Values; their colour
    -- is a look, so it's here
    ImGui.Spacing(ctx)
    local sc_now = M.scale_kind(c) or "none"
    local rv, on = ST.checkbox(ctx, "Numbers in cap colour##scale_ink", c.scale_ink == "cap", { dim = sc_now == "none" })
    if rv then set({ scale_ink = on and "cap" or false }) end
    if ImGui.IsItemHovered(ctx) then
      ImGui.SetTooltip(ctx, "Dial numbers in the knob's colour, not the faceplate's.")
    end
  end

  ImGui.Spacing(ctx)
  ImGui.Separator(ctx)
  if ImGui.MenuItem(ctx, fam == "fader" and "Apply to every fader on this panel"
                                        or "Apply to every knob on this panel") then
    local l = materialise(fx)
    local src = l.controls[idx]
    if src then
      for _, o in ipairs(l.controls) do
        if style_family(o.type) == fam then
          o.style, o.cap = src.style, src.cap
          if fam == "knob" then o.scale_ink, o.arc, o.bipolar, o.arcc = src.scale_ink, src.arc, src.bipolar, src.arcc end
          if fam == "fader" then o.dir, o.len, o.thin, o.img = src.dir, src.len, src.thin, M.copy_img(src.img) end
        end
      end
    end
    M.set(key, l); M.save()
  end
  if ImGui.MenuItem(ctx, "Reset to default", nil, false, c.style ~= nil or c.cap ~= nil or c.scale_ink ~= nil
                     or c.arc ~= nil or c.img ~= nil) then
    set({ style = false, cap = false, scale_ink = false, arc = false, img = false })
  end
end

-- ---------------------------------------------------------------------
-- parallel FX and containers
-- ---------------------------------------------------------------------

-- A container's name as REAPER shows it: its own name when it's been
-- renamed, else just "Container".
local function box_label(node)
  return node.alias or U.fx_label(node)
end

-- The three ways REAPER can run a plugin (or container) against the one
-- before it. The first slot of a level has nothing before it, so the
-- choice is offered there greyed out, with the reason.
local PAR_CHOICES = {
  { 0, "In series" },
  { 1, "In parallel with previous" },
  { 2, "In parallel with previous, merge MIDI" },
}
local function parallel_menu(addr, cur, index, what)
  local first = (index or 0) == 0
  if ImGui.BeginMenu(ctx, "Route", not first) then
    for _, ch in ipairs(PAR_CHOICES) do
      if ImGui.MenuItem(ctx, ch[2], nil, (cur or 0) == ch[1]) and (cur or 0) ~= ch[1] then
        set_parallel(addr, ch[1], what)
      end
    end
    ImGui.EndMenu(ctx)
  end
  if first and ImGui.IsItemHovered(ctx, ImGui.HoveredFlags_AllowWhenDisabled) then
    ImGui.SetTooltip(ctx, "First in its " .. ((addr or 0) >= T.CONTAINER_FLAG and "container" or "chain") ..
      ": nothing before it to route beside.")
  end
end

-- Every panel inside a container, empty-container stand-ins included.
local function panels_in(node)
  local out = {}
  for i = node.first, node.last do
    if app.chain[i] then out[#out + 1] = app.chain[i] end
  end
  return out
end

-- The containers above a container, outermost first: read off the first
-- panel inside it, whose own list runs down through this one. (An empty
-- container's stand-in panel lists only the ones around it.)
local function box_ancestors(node)
  local f = app.chain[node.first]
  local out = {}
  for _, a in ipairs((f and f.ancestors) or {}) do
    if a.guid == node.guid then break end
    out[#out + 1] = a
  end
  return out
end

-- The container menu's items: from its square on the bracket, and as a
-- submenu of the panel menu of anything inside it.
box_menu_items = function(node)
  local tr = app.track
  if not tr then return end
  ImGui.TextDisabled(ctx, "Container: " .. U.truncate(box_label(node), 30))

  -- REAPER's own name for it, as its FX chain shows
  if app.boxren_for ~= node.guid then app.boxren_for, app.boxren_buf = node.guid, node.alias or "" end
  ImGui.SetNextItemWidth(ctx, 150)
  local _, v = ImGui.InputTextWithHint(ctx, "##boxren", "Container", app.boxren_buf)
  local enter = ImGui.IsItemDeactivated(ctx) and (ImGui.IsKeyPressed(ctx, ImGui.Key_Enter)
                or ImGui.IsKeyPressed(ctx, ImGui.Key_KeypadEnter))
  app.boxren_buf = v
  ImGui.SameLine(ctx)
  if ImGui.Button(ctx, "Rename##boxren") or enter then
    -- (its panel's layout goes with the name)
    local was = CT.key(tr, node.addr, node.guid, node.path)
    T.rename(tr, node.addr, node.guid, U.trim(app.boxren_buf))
    CT.carry(was, CT.key(tr, node.addr, nil, node.path))
    app.boxren_for = nil
    rescan(true)
    ImGui.CloseCurrentPopup(ctx)
  end
  ImGui.Separator(ctx)

  local on = T.get_enabled(tr, node.addr)
  if ImGui.MenuItem(ctx, "Bypass container", nil, not on) then
    reaper.Undo_BeginBlock()
    T.set_enabled(tr, node.addr, not on)
    reaper.Undo_EndBlock("ChannelView: " .. (on and "bypass" or "enable") .. " container", -1)
  end
  -- the container's own wet, as its FX chain window has it
  local wet = reaper.TrackFX_GetParamFromIdent and reaper.TrackFX_GetParamFromIdent(tr, node.addr, ":wet")
  if wet and wet >= 0 then
    local wv = reaper.TrackFX_GetParam(tr, node.addr, wet) or 1
    ImGui.SetNextItemWidth(ctx, 150)
    local ch, nv = ST.slider_double(ctx, "Wet##boxwet", wv * 100, 0, 100, "%.0f%%")
    if ch then reaper.TrackFX_SetParam(tr, node.addr, wet, nv / 100) end
  end
  parallel_menu(node.addr, node.parallel, node.index, "container")
  do
    -- the container's own setting: everything inside it, oversampled
    local st = T.os_state(tr, { addr = node.addr, ancestors = box_ancestors(node) })
    if ImGui.BeginMenu(ctx, "Oversample everything in it" .. (st.lit and ("  (" .. st.lit .. "x)") or "")) then
      P.os_choices(ctx, tr, node.addr, st, "container")
      ImGui.EndMenu(ctx)
    end
  end
  ImGui.Separator(ctx)

  local inside = panels_in(node)
  if ImGui.MenuItem(ctx, "Collapse everything in it", nil, false, #inside > 0) then
    for _, f in ipairs(inside) do set_fold(f, true) end
  end
  if ImGui.MenuItem(ctx, "Expand everything in it", nil, false, #inside > 0) then
    for _, f in ipairs(inside) do set_fold(f, false) end
  end
  -- its own panel (the controls put on it) standing for everything in it
  do
    local has = CT.shown[node.guid] and #CT.shown[node.guid] > 0
    local folded = has and CT.folded(node.guid)
    if ImGui.MenuItem(ctx, folded and "Unfold: show what's in it" or "Fold to its panel", nil, false, has and true or false) then
      CT.set_folded(node.guid, not folded)
      rescan(true)
    end
    if ImGui.IsItemHovered(ctx, ImGui.HoveredFlags_AllowWhenDisabled) then
      ImGui.SetTooltip(ctx, has and (folded and "Bring its plugins back into the row." or
        "Show only the container's own panel: the controls put on it.") or
        "Put a control on it first (a control's right-click \u{25B8} On its container).")
    end
  end
  if ImGui.MenuItem(ctx, "Add plugin into it\u{2026}") then
    B.open_menu({ parent = node.path, gap = #(node.children or {}) })
  end
  if ImGui.MenuItem(ctx, "Move left", nil, false, node.index > 0) then
    nudge(node.path, -1, "container")
  end
  if ImGui.MenuItem(ctx, "Move right", nil, false, node.index < node.count - 1) then
    nudge(node.path, 1, "container")
  end
  if ImGui.MenuItem(ctx, "Duplicate") then
    reaper.Undo_BeginBlock()
    reaper.PreventUIRefresh(1)
    T.duplicate(tr, node.path)
    reaper.PreventUIRefresh(-1)
    reaper.Undo_EndBlock("ChannelView: duplicate container", -1)
    rescan(true)
    ImGui.CloseCurrentPopup(ctx)
  end
  if ImGui.IsItemHovered(ctx) then
    ImGui.SetTooltip(ctx, "Copy the container and its contents, right after it.")
  end
  ImGui.Separator(ctx)
  if ImGui.MenuItem(ctx, "Open the container's window") then
    reaper.TrackFX_Show(tr, node.addr, 3)
  end
  if ImGui.MenuItem(ctx, "Show in the FX chain") then
    reaper.TrackFX_Show(tr, node.addr, 1)
  end
  if ImGui.MenuItem(ctx, "Save as FX chain\u{2026}") then
    CN.open_save(tr, node.path, box_label(node))
  end
  ImGui.Separator(ctx)
  if ImGui.MenuItem(ctx, "Unpack: take everything out") then
    reaper.Undo_BeginBlock()
    reaper.PreventUIRefresh(1)
    T.unpack(tr, node.path)
    reaper.PreventUIRefresh(-1)
    reaper.Undo_EndBlock("ChannelView: unpack container", -1)
    rescan(true)
    ImGui.CloseCurrentPopup(ctx)
  end
  if ImGui.IsItemHovered(ctx) then
    ImGui.SetTooltip(ctx, "Move the contents out and remove the container.")
  end
  if ImGui.MenuItem(ctx, "Remove container and everything in it") then
    reaper.Undo_BeginBlock()
    reaper.TrackFX_Delete(tr, node.addr)
    reaper.Undo_EndBlock("ChannelView: remove container", -1)
    rescan(true)
    ImGui.CloseCurrentPopup(ctx)
  end
end

local function box_menu()
  if not ImGui.BeginPopup(ctx, "boxmenu") then return end
  local node = app.box_for
  -- the node is from the chain as it was: still the same container?
  if not node or not app.track or T.guid_at(app.track, node.addr) ~= node.guid then
    ImGui.EndPopup(ctx) return
  end
  box_menu_items(node)
  ImGui.EndPopup(ctx)
end

-- popped-out panels: see POP.window
POP.views, POP.rects, POP.place, POP.LABEL_H, POP.PAD = {}, {}, nil, 16, 3
POP.SCOPED = { "track", "chain", "menu_fx", "open_panel_menu", "ctl_menu", "open_ctl_menu",
                 "remove_ask", "drag", "fxren_for", "fxren_buf", "rename_buf", "label_buf",
                 "rng_for", "rng", "state_buf", "popout" }

function POP.scope(view, track, fn)
  local saved = {}
  for _, k in ipairs(POP.SCOPED) do saved[k] = app[k]; app[k] = view[k] end
  app.track, app.popout = track, view
  -- folded on its own, apart from ChannelView's
  local was_c, was_f, was_v, was_a = St.COLLAPSED, St.FOLD, St.VARIANT, St.VARIANT_ALSO
  St.COLLAPSED, St.FOLD = "pcollapsed:", "pfold:"
  -- its own layout picked, else the one of the view it's laid out like:
  -- ChannelView's side by side, the rack's stacked down (then ChannelView's)
  St.VARIANT = "pvariant:"
  St.VARIANT_ALSO = view.down and { "rvariant:" } or { "variant:" }
  if view.down then POP.rack_mode(true) end
  local ok, err = xpcall(fn, debug.traceback)
  if view.down then POP.rack_mode(false) end
  St.COLLAPSED, St.FOLD, St.VARIANT, St.VARIANT_ALSO = was_c, was_f, was_v, was_a
  for _, k in ipairs(POP.SCOPED) do view[k] = app[k]; app[k] = saved[k] end
  view.popout, view.track = nil, nil
  if not ok then error(err, 0) end
end

-- A window of panels stacked down draws them as the Rack view does: each
-- as wide as the window, as tall as it needs, the rack's defaults.
function POP.rack_mode(on)
  if on then
    POP.was = { P.RACK, M.VIEW_DEFAULTS, W.CHEVRONS_UPDOWN }
    P.RACK, M.VIEW_DEFAULTS, W.CHEVRONS_UPDOWN = true, M.RACK_DEFAULTS_SECT, true
  elseif POP.was then
    P.RACK, M.VIEW_DEFAULTS, W.CHEVRONS_UPDOWN = table.unpack(POP.was, 1, 3)
    POP.was = nil
  end
end

-- Pops the plugin `fx` on `track` out: into window `into`, or a window of
-- its own (named after it) at `at` = { x, y } when given.
function POP.pop_out(track, fx, into, at)
  if not POP.PO or not track or not fx or fx.guid == "" then return end
  local w = into and POP.PO.window(into)
  if not w then
    w = POP.PO.new_window(U.fx_label(fx))
    if at then POP.place = { id = w.id, x = at[1], y = at[2] } end
  end
  POP.PO.add(w.id, reaper.GetTrackGUID(track), fx.guid)
end

-- A panel dragged out of the TCP window's overview, or popped out from its
-- menu: popped out here, as one from this window is (ExtState popout_req
-- "track guid,fx guid,x,y" and ",window id" to go into one; taken once)
POP.REQ = "popout_req"
function POP.take_request()
  local v = reaper.GetExtState(C.EXT_SECT, POP.REQ)
  if v == "" then return end
  reaper.DeleteExtState(C.EXT_SECT, POP.REQ, false)
  if not POP.PO then return end
  local tg, fg, x, y, into = v:match("^([^,]+),([^,]+),(%-?[%d.]+),(%-?[%d.]+),?(%d*)$")
  if not tg then return end
  into = tonumber(into)
  for i = 0, reaper.CountTracks(0) - 1 do
    local tr = reaper.GetTrack(0, i)
    if reaper.GetTrackGUID(tr) == tg then
      for _, f in ipairs(T.collect(tr)) do
        if f.guid == fg then POP.pop_out(tr, f, into, { tonumber(x), tonumber(y) }) return end
      end
      return
    end
  end
end

-- The window a screen point is over, or nil.
function POP.at(x, y)
  for id, r in pairs(POP.rects) do
    if x >= r[1] and x < r[1] + r[3] and y >= r[2] and y < r[2] + r[4] then return id end
  end
  return nil
end

local function panel_menu()
  if not ImGui.BeginPopup(ctx, "panelmenu") then return end
  local fx = app.chain[app.menu_fx or -1]
  if not fx then ImGui.EndPopup(ctx) return end

  local layout, key, is_default = layout_for(fx)
  ImGui.TextDisabled(ctx, U.fx_label(fx) .. (fx.alias and ("  \u{00B7}  " .. U.clean_fx_name(fx.name)) or ""))

  -- REAPER's own name for this instance (its FX chain's Rename): shown on
  -- the panel, in the FX chain and everywhere else REAPER lists it. The
  -- layout stays the plugin's. Empty goes back to the plugin's name.
  if app.fxren_for ~= fx.guid then app.fxren_for, app.fxren_buf = fx.guid, fx.alias or "" end
  ImGui.SetNextItemWidth(ctx, 150)
  local _, ren_v = ImGui.InputTextWithHint(ctx, "##fxren", U.clean_fx_name(fx.name),
    app.fxren_buf)
  local ren_enter = (ImGui.IsItemDeactivated(ctx) and (ImGui.IsKeyPressed(ctx, ImGui.Key_Enter) or ImGui.IsKeyPressed(ctx, ImGui.Key_KeypadEnter)))
  app.fxren_buf = ren_v
  if ImGui.IsItemHovered(ctx) then
    ImGui.SetTooltip(ctx, "Rename this instance (layout unchanged).\nClear to restore the plugin's name.")
  end
  ImGui.SameLine(ctx)
  if ImGui.Button(ctx, "Rename##fxren") or ren_enter then
    T.rename(app.track, fx.addr, fx.guid, U.trim(app.fxren_buf))
    -- (a container's panel layout goes with the name)
    if fx.container_panel then CT.carry(fx.name, CT.key(app.track, fx.addr, nil, fx.path_t)) end
    app.fxren_for = nil
    rescan(true)
    ImGui.CloseCurrentPopup(ctx)
  end
  -- REAPER's own wet for the plugin: the header shows it where there's
  -- room, and here it works at any panel width
  do
    local wet = reaper.TrackFX_GetParamFromIdent and reaper.TrackFX_GetParamFromIdent(app.track, fx.addr, ":wet")
    if wet and wet >= 0 then
      local wv = reaper.TrackFX_GetParam(app.track, fx.addr, wet) or 1
      ImGui.SetNextItemWidth(ctx, 150)
      local ch, nv = ST.slider_double(ctx, "Wet##fxwet", wv * 100, 0, 100, "%.0f%%")
      if ch then reaper.TrackFX_SetParam(app.track, fx.addr, wet, nv / 100) end
      if ImGui.IsItemHovered(ctx) then
        ImGui.SetTooltip(ctx, "Wet/dry mix.\nCtrl+click: type a value.")
      end
    end
  end
  -- its gain reduction measured: which knobs are its input, make-up and
  -- output gains, then measured (TS_CV_GainCheck)
  if layout.measure and not fx.is_container then
    if ImGui.MenuItem(ctx, "Check gain knobs\u{2026}") then
      require("TS_CV_GainCheck").open(app.track, fx, key)
    end
    if ImGui.IsItemHovered(ctx) then
      ImGui.SetTooltip(ctx, "Say which knobs are its gains, then measure them.")
    end
  end

  -- a locked layout takes no edits (the padlock in the panel's foot);
  -- its meters can still be switched on and off
  local locked = M.locked(layout) ~= nil
  local function locked_tip()
    if locked and ImGui.IsItemHovered(ctx, ImGui.HoveredFlags_AllowWhenDisabled) then
      ImGui.SetTooltip(ctx, "Layout locked: unlock with the padlock\nin the panel's foot.")
    end
  end
  ------------------------------------------------------------- LAYOUT
  ImGui.SeparatorText(ctx, "Layout")
  -- Layout variants: another layout for the same plugin, picked per
  -- instance (TS_CV_Mappings "<plugin> :: <name>", St.variant). Not for
  -- REAPER's plugins with a panel of ChannelView's (ReaEQ, ReaComp,
  -- ReaGate, ReaLimit, ReaDelay, ReaVerbate): that's their Standard, and
  -- other layouts of theirs are normal ones, with or without a canvas.
  do
    local base, shown = M.split_variant(key)
    local dflt = M.default_variant(base)
    local function mark(nm) return (nm == dflt) and "  (default)" or "" end
    -- a layout switching rule in charge: the one shown is its, the ticks
    -- are the instance's own pick (shown again once no rule matches)
    local rule = St.switch_rule(fx.guid)
    local _, cur = M.split_variant(rule and St.chosen_key(fx.name, fx.guid) or key)
    local title = "Layout: " .. (shown and U.truncate(shown, 20) or "Standard") .. (rule and "  \u{00B7} auto" or "")
    if ED.menu(ImGui, ctx, ED.PRO and (title .. "###fxlayout") or "Other layouts") then
      local rules = M.switch_rules(base)
      if rules then
        local r = rules[rule or 0]
        local function pname(p)
          local _, pn = reaper.TrackFX_GetParamName(app.track, fx.addr, p, "")
          return M.display_name(base, p, nil, pn, false)
        end
        local function fmt(p, n)
          local ok_, sv = U.format_norm(app.track, fx.addr, p, n, "")
          return ok_ and U.trim(sv or "") or nil
        end
        local function vfind(nm)
          local _, vc = M.vstart(base, nm, layout.controls)
          return vc
        end
        local said = r and M.rule_text(r, pname, fmt, vfind)
        ImGui.TextDisabled(ctx, said and ("Rule %d is in charge: %s"):format(rule, U.truncate(said, 60))
          or ("%d switching rule%s, none in charge"):format(#rules, #rules == 1 and "" or "s"))
        ImGui.TextDisabled(ctx, "(set them in Edit Parameters)")
        ImGui.Separator(ctx)
      end
      if ImGui.MenuItem(ctx, "Standard" .. mark(nil) .. "##varown", nil, cur == nil) then
        St.set_variant(fx.guid, St.OWN)
      end
      if ImGui.IsItemHovered(ctx) then
        ImGui.SetTooltip(ctx, "The plugin's standard layout.")
      end
      for _, nm in ipairs(M.variants(base)) do
        if ImGui.MenuItem(ctx, nm .. mark(nm) .. "##var", nil, cur == nm) then St.set_variant(fx.guid, nm) end
      end
      -- which one new instances (and any not set to another) use
      if cur ~= dflt then
        if ImGui.MenuItem(ctx, "Make \"" .. U.truncate(cur or "Standard", 20) .. "\" the "
            .. (P.RACK and "rack's default" or "default")) then
          M.set_default_variant(base, cur); M.save()
        end
        if ImGui.IsItemHovered(ctx) then
          ImGui.SetTooltip(ctx, P.RACK
            and "Used in the Rack view by new instances and any not set to another layout there."
            or "Used by new instances and any not set to another layout.")
        end
      end
      ImGui.Separator(ctx)
      ImGui.SetNextItemWidth(ctx, 190)
      -- (not EnterReturnsTrue: with it ImGui only hands the text back on
      -- Enter, so the buttons would always see an empty name)
      local _, txt = ImGui.InputTextWithHint(ctx, "##newvar", "new layout's name", app.var_name or "")
      local ch = ImGui.IsItemDeactivated(ctx) and (ImGui.IsKeyPressed(ctx, ImGui.Key_Enter)
                 or ImGui.IsKeyPressed(ctx, ImGui.Key_KeypadEnter))
      app.var_name = txt
      local ok = M.clean_variant(txt) ~= nil and not M.has(M.variant_key(base, M.clean_variant(txt) or ""))
      local function make(empty)
        -- copied from a panel of ChannelView's (TS_CV_ReaFX): the plugin's
        -- controls, as a normal layout
        local from = layout
        if not shown and require("TS_CV_ReaFX").has_panel(key) then from = M.build_default(app.track, fx.addr) end
        -- the Trimmer's own panel: a layout like it, to change
        if not empty and TRM and P.own_trim(key) then from = TRM.starter_layout() end
        local _, nm = M.new_variant(base, txt, from, empty)
        if nm then St.set_variant(fx.guid, nm); app.var_name = nil; ImGui.CloseCurrentPopup(ctx) end
      end
      if ch and ok then make(false) end
      if not ok then ImGui.BeginDisabled(ctx, true) end
      if ImGui.Button(ctx, "Copy to new layout") then make(false) end
      if ImGui.IsItemHovered(ctx, ImGui.HoveredFlags_AllowWhenDisabled) then
        ImGui.SetTooltip(ctx, "Copy this layout under the name above.\nEnter does the same.")
      end
      ImGui.SameLine(ctx)
      if ImGui.Button(ctx, "New empty layout") then make(true) end
      if ImGui.IsItemHovered(ctx, ImGui.HoveredFlags_AllowWhenDisabled) then
        ImGui.SetTooltip(ctx, "Empty layout under the name above.\nParameter names carry over.")
      end
      if not ok then ImGui.EndDisabled(ctx) end
      -- an EQ or compressor canvas for any plugin (TS_CV_CanvasSetup):
      -- the name above, or "EQ" / "Compressor" (numbered if taken)
      local function make_canvas(kind)
        local nm = M.clean_variant(txt)
        if not nm or M.has(M.variant_key(base, nm)) then
          local stem = M.CANVAS_NAMES[kind] or "Compressor"
          nm = stem
          local i = 2
          while M.has(M.variant_key(base, nm)) do nm = stem .. " " .. i; i = i + 1 end
        end
        local made = CS.create(app.track, fx, base, nm, kind, layout)
        if made then St.set_variant(fx.guid, made); app.var_name = nil; ImGui.CloseCurrentPopup(ctx) end
      end
      -- a canvas of its kind (EQ, compressor, gate, limiter, de-esser,
      -- delay, reverb, envelope, modulation): TS_CV_CanvasSetup
      if ImGui.BeginMenu(ctx, "New canvas layout") then
        for _, k in ipairs(M.CANVAS_ORDER) do
          if ImGui.MenuItem(ctx, M.CANVAS_NAMES[k] .. "\u{2026}") then make_canvas(k) end
          if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, CS.TIPS[k] or "") end
        end
        ImGui.EndMenu(ctx)
      end
      do
        local cl = M.get(key)
        if cl and cl.canvas and ImGui.MenuItem(ctx, "Set up this layout\u{2026}") then
          CS.open(app.track, fx, key)
        end
      end
      if cur then
        ImGui.Separator(ctx)
        if ImGui.MenuItem(ctx, "Delete layout \"" .. U.truncate(cur, 20) .. "\"\u{2026}") then
          if reaper.MB(("Delete the layout \"%s\"?\n\nEvery instance using it goes back to " ..
              "the plugin's default layout. The library as it was before is kept as\n" ..
              "TS_ChannelView_Mappings.bak.ini, until the next save."):format(cur), "ChannelView", 1) == 1 then
            if dflt == cur then M.set_default_variant(base, nil) end
            M.remove(key); M.save()
            St.set_variant(fx.guid, nil)
          end
        end
      end
      ImGui.EndMenu(ctx)
    end
  end
  -- Standard's editor is Edit parameters; Pro's the grid editor (but for
  -- a panel of its own: ReaEQ's, ReaComp's, the Trimmer's)
  local own_panel = P.own_eq(key) or P.own_rc(key) or P.own_trim(key)
  if not ED.PRO or own_panel then
    if ImGui.MenuItem(ctx, "Edit parameters\u{2026}", nil, false, not locked) then
      E.open(app.track, fx, key, layout)
    end
    locked_tip()
  end
  -- the grid editor (TS_CV_GridEditor): the layout as a grid, live
  -- (a canvas layout's: the controls beside the canvas)
  if not own_panel then
    if ED.item(ImGui, ctx, "Edit layout\u{2026}") then
      require("TS_CV_GridEditor").open(app.track, fx, key, layout, nil,
        { rows = M.locked(layout) or (P.RACK and P.RACK_ROWS) or app.cv_rows or 2, index = app.menu_fx, cv_h = app.cv_h,
          rack_w = app.rack_w or tonumber(reaper.GetExtState(C.EXT_SECT, "rack_width")) })
    end
    if ED.PRO and ImGui.IsItemHovered(ctx) then
      ImGui.SetTooltip(ctx, "The layout as a grid: drag parameters onto it, move and resize them.")
    end
  end
  if ED.menu(ImGui, ctx, "Faceplate", not locked) then
    plate_menu(fx, key, layout)
    ImGui.EndMenu(ctx)
  end
  locked_tip()
  -- the panel's whole style, onto other panels (TS_CV_Mappings M.style_of):
  -- the copy stays until another is made
  if not own_panel then
    -- (one clipboard for ChannelView and the Rack: M.clip_put / clip_get)
    if ED.item(ImGui, ctx, "Copy panel style") then
      M.clip_put("panel", M.style_of(layout), U.fx_label(fx))
    end
    if ED.PRO and ImGui.IsItemHovered(ctx) then
      ImGui.SetTooltip(ctx, "Its faceplate and each kind of control's look,\nto paste onto other panels.")
    end
    local clip, from = M.clip_get("panel")
    if ED.item(ImGui, ctx, "Paste panel style" .. (from and ("  (" .. from .. ")") or ""), nil, false,
        clip ~= nil and not locked) then
      local l = materialise(fx)
      M.apply_style(l, clip)
      M.set(key, l); M.save()
    end
    if ED.PRO and ImGui.IsItemHovered(ctx, ImGui.HoveredFlags_AllowWhenDisabled) then
      ImGui.SetTooltip(ctx, locked and "Layout locked: unlock with the padlock\nin the panel's foot."
        or clip and "Its faceplate, and every knob, button, dropdown and fader\nin the copied panel's looks."
        or "Copy a panel's style first.")
    end
  end
  if ImGui.BeginMenu(ctx, "Meters") then
    -- The meter is a property of the plugin, so it saves with the layout and
    -- applies to every instance -- same as everything else here.
    if T.reports_gr(app.track, fx.addr, fx.guid) then
      local on = M.meter_of(layout) ~= nil
      if ImGui.MenuItem(ctx, "Gain reduction meter", nil, on) then
        local l = materialise(fx)
        M.set_meter(l, not on)
        M.set(key, l); M.save()
      end
    elseif not RQ.is_eq(key) then
      -- Doesn't report it: it can be MEASURED instead, by the track's probe
      -- pair (TS_CV_Taps). Not ReaEQ, which has no reduction to measure.
      local on = layout.measure == true
      if ImGui.MenuItem(ctx, "Measure gain reduction (estimated)", nil, on) then
        local l = materialise(fx)
        l.measure = (not on) or nil
        M.set_meter(l, not on)
        M.set(key, l); M.save()
        TP.invalidate()
        if not on and TP.status(app.track, fx.guid) == "no_probes" then
          if reaper.MB("This plugin doesn't report its gain reduction, so it's measured\n" ..
                       "by a TS_TrackProbe pair: one at the start of the chain, one at\n" ..
                       "the end. This track doesn't have them.\n\nAdd them now?",
                       "ChannelView", 4) == 6 then
            local ok, why = TP.insert_probes(app.track)
            if not ok then reaper.MB(why, "ChannelView", 0) end
          end
        end
      end
      if ImGui.IsItemHovered(ctx) then
        ImGui.SetTooltip(ctx,
          "Estimate gain reduction from audio in vs out.\nNeeds a TS_TrackProbe pair on the track.")
      end
    end
    -- Input and output meters: any plugin, measured by the same probe pair.
    do
      local on = layout.levels == true
      if ImGui.MenuItem(ctx, "Input/output meters", nil, on) then
        local l = materialise(fx)
        l.levels = (not on) or nil
        M.set(key, l); M.save()
        TP.invalidate()
        if not on and TP.status(app.track, fx.guid) == "no_probes" then
          if reaper.MB("Input and output levels are measured by a TS_TrackProbe pair:\n" ..
                       "one at the start of the chain, one at the end. This track\n" ..
                       "doesn't have them.\n\nAdd them now?", "ChannelView", 4) == 6 then
            local ok, why = TP.insert_probes(app.track)
            if not ok then reaper.MB(why, "ChannelView", 0) end
          end
        end
      end
      if ImGui.IsItemHovered(ctx) then
        ImGui.SetTooltip(ctx,
          "Input, output and level-change meters.\nNeeds a TS_TrackProbe pair on the track.")
      end
    end
    ImGui.EndMenu(ctx)
  end
  -- These three replace a saved layout outright and save straight away --
  -- one stray click and a layout you spent an hour on is gone, for every
  -- instance of the plugin. So each asks first whenever there is a saved
  -- layout to lose. (The Edit Parameters dialog's own Auto-fill needs no
  -- such guard: nothing there is kept until you press Save.)
  local function sure(what)
    if is_default then return true end
    return reaper.MB(what .. "\n\nThis replaces the saved layout for every " .. key ..
      " on every track. The library as it was before is kept as\n" ..
      "TS_ChannelView_Mappings.bak.ini, until the next save.", "ChannelView", 1) == 1
  end
  if ImGui.BeginMenu(ctx, "Reset layout", not locked) then
    if ImGui.MenuItem(ctx, "Auto-fill layout\u{2026}", nil, false, not locked) then
      if sure(("Replace this layout with the plugin's first %d parameters?"):format(C.AUTO_DEFAULT_N)) then
        M.set(key, M.build_default(app.track, fx.addr)); M.save()
      end
    end
    locked_tip()
    if ImGui.MenuItem(ctx, "Clear layout\u{2026}", nil, false, not is_default and not locked) then
      if sure("Clear every control from this layout?") then
        M.set(key, { controls = {} }); M.save()
      end
    end
    locked_tip()
    if ImGui.MenuItem(ctx, "Forget saved layout\u{2026}", nil, false, not is_default and not locked) then
      if sure("Forget this saved layout and go back to the automatic one?") then
        M.remove(key); M.save()
      end
    end
    locked_tip()
    ImGui.EndMenu(ctx)
  end
  locked_tip()
  ------------------------------------------------------------- PLUGIN
  ImGui.SeparatorText(ctx, "Plugin")
  if ImGui.MenuItem(ctx, St.is_collapsed(fx.guid) and "Expand" or "Collapse to a bar") then
    toggle_fold(fx)
  end
  if ImGui.MenuItem(ctx, "Open the plugin's window") then
    reaper.TrackFX_Show(app.track, fx.addr, 3)
  end
  if ImGui.MenuItem(ctx, "Show in the FX chain") then
    reaper.TrackFX_Show(app.track, fx.addr, 1)
  end
  do
    -- its picture, for the hover previews (TS_CV_Thumbs, Pro)
    local th = not (fx.container_panel or fx.is_container) and W.thumbs()
    if th and ImGui.BeginMenu(ctx, "Picture") then
      local key = th.key_of_fx(app.track, fx.addr)
      local has = key and th.has(key)
      if th.can_capture() and ImGui.MenuItem(ctx, has and "Take it again" or "Take it now") then
        th.retake(app.track, fx.addr)
      end
      if ImGui.IsItemHovered(ctx) then
        ImGui.SetTooltip(ctx, "From its window, once it's open\nwith nothing over it.")
      end
      if ImGui.MenuItem(ctx, "From a file\u{2026}", nil, false, key ~= nil) then th.from_file(key) end
      if ImGui.MenuItem(ctx, "Remove", nil, false, has) then th.remove(key) end
      ImGui.EndMenu(ctx)
    end
  end
  -- a copy of the panel in a window of its own (TS_CV_PopOut, Pro)
  if POP.PO and not app.popout and not (fx.container_panel or fx.is_container) and ImGui.BeginMenu(ctx, "Pop out") then
    if ImGui.MenuItem(ctx, "In a window of its own") then POP.pop_out(app.track, fx) end
    local inside = POP.PO.windows_with(fx.guid)
    local ws = POP.PO.windows()
    if #ws > 0 then ImGui.Separator(ctx) end
    for _, w in ipairs(ws) do
      if ImGui.MenuItem(ctx, "Into \u{201C}" .. U.truncate(w.name, 24) .. "\u{201D}##po" .. w.id, nil, inside[w.id], not inside[w.id]) then
        POP.pop_out(app.track, fx, w.id)
      end
    end
    ImGui.EndMenu(ctx)
  end
  if POP.PO and not app.popout and ImGui.IsItemHovered(ctx) and not (fx.container_panel or fx.is_container) then
    ImGui.SetTooltip(ctx, "A copy of this panel, floating or docked.\nOr drag its header out of ChannelView.")
  end
  -- two plugins side by side, one heard at a time (TS_CV_Compare, Pro)
  if POP.CMP and not RACK and not app.popout and not (fx.container_panel or fx.is_container) then
    local busy = POP.CMP.parts(app.track) ~= nil
    if ImGui.BeginMenu(ctx, "Compare with", not busy) then
      if POP.CMP.menu_items(ctx, app.track, fx) then rescan(true) end
      ImGui.EndMenu(ctx)
    end
    if ImGui.IsItemHovered(ctx, ImGui.HoveredFlags_AllowWhenDisabled) then
      ImGui.SetTooltip(ctx, busy and "This track is comparing already:\nkeep one first."
        or "Hear it against another plugin, one at a time,\nmatched in level, before you choose.")
    end
  end
  do
    local st = T.os_state(app.track, fx)
    if ImGui.BeginMenu(ctx, "Oversampling" .. (st.lit and ("  (" .. st.lit .. "x)") or "")) then
      P.os_choices(ctx, app.track, fx.addr, st, "plugin")
      ImGui.EndMenu(ctx)
    end
  end
  do
    -- offline: unloaded, not just bypassed (the panel turns steel blue)
    local off = T.get_offline(app.track, fx.addr)
    if ImGui.MenuItem(ctx, off and "Bring online" or "Set offline") then
      T.set_offline(app.track, fx.addr, not off, U.fx_label(fx))
    end
    if ImGui.IsItemHovered(ctx) then
      ImGui.SetTooltip(ctx, off and "Reload the plugin, as it was."
        or "Unload the plugin to free CPU and memory.\nSettings are kept.")
    end
  end
  do
    -- a plugin with sidechain inputs in a container that doesn't pass 3/4
    if #T.sidechain_gap(app.track, fx) > 0 then
      if ImGui.MenuItem(ctx, "Pass the sidechain into its container") then
        T.pass_sidechain(app.track, fx)
      end
      if ImGui.IsItemHovered(ctx) then
        ImGui.SetTooltip(ctx, "Widen the container to pass channels 3/4,\nso the track's sidechain reaches this plugin.")
      end
    end
  end
  -------------------------------------------------------------- CHAIN
  if app.popout then
    -- a popped-out panel: its place in its window
    local id, k = app.popout.win, app.menu_fx
    local w = POP.PO.window(id)
    ImGui.SeparatorText(ctx, "Popped out")
    if ImGui.MenuItem(ctx, "Move left", nil, false, k > 1) then POP.PO.nudge(id, k, -1) end
    if ImGui.MenuItem(ctx, "Move right", nil, false, w and k < #w.panels) then POP.PO.nudge(id, k, 1) end
    if ImGui.BeginMenu(ctx, "Move to") then
      if ImGui.MenuItem(ctx, "A window of its own") then POP.PO.move(id, k, nil, U.fx_label(fx)) end
      for _, o in ipairs(POP.PO.windows()) do
        if o.id ~= id and ImGui.MenuItem(ctx, "\u{201C}" .. U.truncate(o.name, 24) .. "\u{201D}##pomv" .. o.id) then
          POP.PO.move(id, k, o.id)
        end
      end
      ImGui.EndMenu(ctx)
    end
    if ImGui.MenuItem(ctx, "Take it out of this window") then POP.PO.take_out(id, k) end
    if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "The plugin stays on its track.") end
    if w and ImGui.BeginMenu(ctx, "Window: " .. U.truncate(w.name, 20)) then
      POP.menu(w)
      ImGui.EndMenu(ctx)
    end
  else
  ImGui.SeparatorText(ctx, "Chain")
  if ImGui.MenuItem(ctx, "Move left", nil, false, fx.index > 0) then
    nudge(fx.path_t, -1)
  end
  if ImGui.MenuItem(ctx, "Move right", nil, false, fx.index < fx.siblings - 1) then
    nudge(fx.path_t, 1)
  end
  parallel_menu(fx.addr, fx.parallel, fx.index, "plugin")
  if ImGui.MenuItem(ctx, "Duplicate") then
    reaper.Undo_BeginBlock()
    reaper.PreventUIRefresh(1)
    T.duplicate(app.track, fx.path_t)
    reaper.PreventUIRefresh(-1)
    reaper.Undo_EndBlock("ChannelView: duplicate " .. U.fx_label(fx), -1)
    rescan(true)
  end
  if ImGui.IsItemHovered(ctx) then
    ImGui.SetTooltip(ctx, "Copy with settings, right after it.")
  end
  if ImGui.MenuItem(ctx, "Insert plugin before\u{2026}") then
    B.open_menu(insert_target(fx, false))
  end
  if ImGui.MenuItem(ctx, "Insert plugin after\u{2026}") then
    B.open_menu(insert_target(fx, true))
  end
  if ImGui.MenuItem(ctx, "Put in a new container") then
    reaper.Undo_BeginBlock()
    reaper.PreventUIRefresh(1)
    T.wrap(app.track, fx.path_t)
    reaper.PreventUIRefresh(-1)
    reaper.Undo_EndBlock("ChannelView: put " .. U.fx_label(fx) .. " in a container", -1)
    rescan(true)
  end
  do
    local box = fx.ancestors and fx.ancestors[#fx.ancestors]
    -- a container's own panel: its own menu
    if fx.container_panel then
      box = nil
      for _, b in ipairs(app.brackets or {}) do
        if b.kind == "container" and b.node.guid == fx.guid then box = b.node break end
      end
    end
    if box and ImGui.BeginMenu(ctx, "Container: " .. U.truncate(box_label(box), 24)) then
      box_menu_items(box)
      ImGui.EndMenu(ctx)
    end
  end
  end
  ImGui.Separator(ctx)
  if ImGui.MenuItem(ctx, fx.container_panel and "Remove container and everything in it"
                        or fx.is_container and "Remove container" or "Remove plugin from the chain") then
    remove_fx(fx)
    ImGui.EndPopup(ctx)
    return
  end

  ImGui.Separator(ctx)
  ImGui.TextDisabled(ctx, is_default and "auto-generated layout"
                                      or ("saved as \"" .. key .. "\""))
  ImGui.EndPopup(ctx)
end

-- ---------------------------------------------------------------------
-- copy and paste a control's look (TS_CV_Mappings.look_of / paste_look)
-- ---------------------------------------------------------------------
-- One copied look, for this session: from any control on any panel,
-- pasted onto one control, or every one of its kind in a section or on
-- the panel; ChannelView and the Rack share it (M.clip_put("look", ...)).

local LOOK_NOUN = { knob = "knob", fader = "fader", button = "button" }

-- "Knob: Skirted, Red, Large, Values scale, on Inset" -- what's on the
-- clipboard, for the menu's tooltip
local function look_text(s)
  local parts = {}
  local function label_of(list, key)
    for _, t in ipairs(list) do if t.key == key then return t.label end end
    return nil
  end
  if s.fam == "knob" then
    parts[#parts + 1] = label_of(C.KNOB_STYLES, C.KNOB_STYLE_ALIAS[s.style] or s.style) or "Arc"
  elseif s.fam == "fader" then
    parts[#parts + 1] = label_of(C.FADER_STYLES, s.style) or "Flat"
  elseif s.fam == "button" then
    parts[#parts + 1] = label_of(C.BUTTON_STYLES, s.style) or label_of(C.SWITCH_STYLES, s.style) or "Flat"
  end
  if s.cap then
    parts[#parts + 1] = label_of(s.fam == "button" and C.TOGGLE_COLS or C.CAPS, s.cap)
                        or C.custom_key(s.cap) or s.cap
  end
  if s.size and C.SIZES[s.size] then parts[#parts + 1] = C.SIZES[s.size].label end
  if s.fam == "xy" and s.size then parts[#parts + 1] = (s.size:gsub("x", "\u{00d7}")) end
  if s.fam == "fader" then
    parts[#parts + 1] = ((s.dir == "h") and "across " or "up ") .. (s.len and tostring(s.len) or "full")
      .. (s.thin and ", half width" or "")
  end
  if s.fam == "knob" then
    local sc = M.scale_kind(s)
    if sc == "values" then parts[#parts + 1] = "values scale"
    elseif sc == "ten" then parts[#parts + 1] = "0\u{2013}10 scale"
    elseif s.scale == "blank" then parts[#parts + 1] = "no numbers" end
  end
  if s.img and s.img.file then parts[#parts + 1] = "picture" end
  if s.back then
    local pl = C.plate_of(s.back)
    parts[#parts + 1] = "on " .. ((s.back == "inset") and "Inset" or (pl and pl.label) or s.back)
  end
  local head = s.fam and (s.fam:sub(1, 1):upper() .. s.fam:sub(2)) or "Background"
  return head .. ((#parts > 0) and (": " .. table.concat(parts, ", ")) or ": none")
end

-- the controls in the same section as control `idx`: between the dividers
-- either side of it
local function section_range(controls, idx)
  local a, b = 1, #controls
  for k = idx - 1, 1, -1 do if controls[k].type == "divider" then a = k + 1 break end end
  for k = idx + 1, #controls do if controls[k].type == "divider" then b = k - 1 break end end
  return a, b
end

local function look_items(fx, key, layout, idx, c, locked)
  -- (Standard: copy and paste are Pro's)
  if not ED.PRO and not locked then ED.menu(ImGui, ctx, "Copy / paste style") return end
  if ImGui.MenuItem(ctx, "Copy style") then
    M.clip_put("look", { look = M.look_of(c) })
  end
  if ImGui.IsItemHovered(ctx) then
    ImGui.SetTooltip(ctx, "Copy its whole look to paste onto other controls.")
  end
  if locked then return end
  local s = (M.clip_get("look") or {}).look
  local have = s ~= nil
  local function tip()
    if ImGui.IsItemHovered(ctx, ImGui.HoveredFlags_AllowWhenDisabled) then
      ImGui.SetTooltip(ctx, have and look_text(s) or "Copy a control's style first.")
    end
  end
  local function paste(from, to)
    local l = materialise(fx)
    local n = 0
    for k = from, to do
      local o = l.controls[k]
      local fits = o and o.type ~= "divider"
        and (k == idx or s.fam == nil or M.look_family(o) == s.fam)
      if fits and M.paste_look(o, s) then n = n + 1 end
    end
    if n > 0 then M.set(key, l); M.save() end
  end
  if ImGui.MenuItem(ctx, "Paste style", nil, false, have) then paste(idx, idx) end
  tip()
  -- several picked in Edit layout (this plugin, this layout): on all of them
  local picked = require("TS_CV_GridEditor").picked_for(fx.guid, key)
  if picked and #picked > 1 then
    if ImGui.MenuItem(ctx, ("Paste style to the %d selected"):format(#picked), nil, false, have) then
      local l = materialise(fx)
      local n = 0
      for _, k in ipairs(picked) do
        local o = l.controls[k]
        local fits = o and o.type ~= "divider" and (s.fam == nil or M.look_family(o) == s.fam)
        if fits and M.paste_look(o, s) then n = n + 1 end
      end
      if n > 0 then M.set(key, l); M.save() end
    end
    tip()
  end
  local noun = have and (s.fam and LOOK_NOUN[s.fam] or "control") or "control"
  if ImGui.BeginMenu(ctx, "Paste style to every " .. noun, have) then
    if ImGui.MenuItem(ctx, "In this section") then paste(section_range(layout.controls, idx)) end
    if ImGui.MenuItem(ctx, "On this panel") then paste(1, #layout.controls) end
    ImGui.EndMenu(ctx)
  end
  tip()
end

-- Choosing an XY pad's Y, or a concentric knob's inner knob: every
-- parameter of the plugin, filtered as you type.
local function second_param_menu(fx, key, idx, c)
  ImGui.SetNextItemWidth(ctx, 240)
  local _, f = ImGui.InputTextWithHint(ctx, "##p2filter", "filter\u{2026}", app.p2_filter or "")
  app.p2_filter = f
  local want = U.trim(f or ""):lower()
  local n = reaper.TrackFX_GetNumParams(app.track, fx.addr)
  if ImGui.BeginChild(ctx, "##p2list", 240, math.min(320, 20 + n * 19)) then
    for p = 0, n - 1 do
      local _, pn = reaper.TrackFX_GetParamName(app.track, fx.addr, p, "")
      local shown = M.display_name(key, p, nil, pn, false)
      if want == "" or shown:lower():find(want, 1, true) or tostring(p) == want then
        if ImGui.Selectable(ctx, ("%d  %s##p2_%d"):format(p, shown, p), c.param2 == p) then
          local l = materialise(fx)
          local lc = l.controls[idx]
          if lc then lc.param2 = p end
          M.set(key, l); M.save()
          ImGui.CloseCurrentPopup(ctx)
        end
      end
    end
    ImGui.EndChild(ctx)
  end
end

local TYPE_LABELS = { knob = "Knob", toggle = "Button", combo = "Dropdown",
                      stepped = "Stepped knob", fader = "Fader",
                      xy = "XY pad", dual = "Concentric knob",
                      blank = "Gap", half_gap = "Half gap", divider = "Divider" }
local TYPE_ORDER  = { "knob", "toggle", "combo", "stepped", "fader", "xy", "dual", "blank", "half_gap", "divider" }

-- REAPER's Parameter Modulation / Link window for this one parameter --
-- LFO, audio control signal, MIDI link, parameter link -- straight from
-- the control, rather than touching it and hunting for the last-touched
-- action. Ticked while the parameter has modulation switched on. Not a
-- layout edit, so a locked layout offers it too.
local function param_mod_item(fx, c)
  if not (app.track and c and c.param and c.param >= 0) then return end
  -- two of them for a control with two parameters, named for which is which
  local list = { { c.param, "Parameter modulation\u{2026}" } }
  if M.has_second(c) and c.param2 and c.param2 >= 0 then
    local a, b = (c.type == "xy") and "X" or "ring", (c.type == "xy") and "Y" or "inner knob"
    list = { { c.param, "Parameter modulation (" .. a .. ")\u{2026}" },
             { c.param2, "Parameter modulation (" .. b .. ")\u{2026}" } }
  end
  for _, e in ipairs(list) do
    local pre = ("param.%d.mod."):format(e[1])
    local ok, act = reaper.TrackFX_GetNamedConfigParm(app.track, fx.addr, pre .. "active")
    if ImGui.MenuItem(ctx, e[2], nil, ok and tonumber(act) == 1) then
      reaper.TrackFX_SetNamedConfigParm(app.track, fx.addr, pre .. "visible", "1")
    end
    if ImGui.IsItemHovered(ctx) then
      ImGui.SetTooltip(ctx, "Open REAPER's modulation / link window for this parameter.\nTicked while modulation is on.")
    end
  end
end

-- Links a macro or modulator to a control, after asking when that
-- replaces another. A dropdown macro dropped on a stepped parameter
-- (2 to 8 steps) offers to take that parameter's choices.
local function link_source(src, k, path, param, label, was, centre)
  if was and was.mod.guid == src.guid and was.out == (k or 1) then return end
  local nm = src.name .. ((src.labels and src.labels[k or 1]) and (" " .. src.labels[k or 1]) or "")
  if was and reaper.MB(("%s is driven by %s.\n\nReplace it with %s?"):format(
       label or "This control", was.mod.name, nm), "ChannelView", 4) ~= 6 then
    return
  end
  if not MD.link(app.track, src, k or 1, path, param, centre) then return end
  if src.kind == "dropdown" then
    local taddr = T.addr_of(app.track, path)
    local names = taddr and MD.steps_of(app.track, taddr, param)
    if names and table.concat(names, "\0") ~= table.concat(src.choices or {}, "\0") then
      local q = ("Use %s's choices for %s?\n\n%s"):format(label or "this control", src.name,
                  table.concat(names, ", "))
      if reaper.MB(q, "ChannelView", 4) == 6 then
        local n0 = #(src.choices or {})
        local c = n0 >= 2 and MD.choice_of(MD.value(app.track, src, 1), n0) or 1
        MD.set_choices(app.track, src, names)
        MD.set_macro(app.track, src, 1, MD.choice_value(math.min(c, #names), #names))
      end
    end
  end
end

-- The link on this control (TS_CV_Mod): which macro or modulator drives
-- it and how -- a macro's range, a modulator's depth, invert, bipolar --
-- and Link to / Remove. Not a layout edit: offered when the layout is
-- locked too.
local function link_items(fx, c, param, axis)
  local s = MD.scan(app.track)
  local l = MD.link_of(app.track, fx.guid, param)
  local tag = "##" .. param
  local pre = axis and (axis .. ": ") or ""
  if l then
    local dl = ImGui.GetWindowDrawList(ctx)
    local x, y = ImGui.GetCursorScreenPos(ctx)
    ImGui.DrawList_AddRectFilled(dl, x + 1, y + 4, x + 10, y + 13, l.mod.col, 2)
    ImGui.SetCursorScreenPos(ctx, x + 16, y)
    local who = l.mod.name .. ((l.mod.labels and l.mod.labels[l.out]) and (" " .. l.mod.labels[l.out]) or "")
    ImGui.Text(ctx, pre .. "Driven by " .. who)
    if l.macro then
      local a, b = MD.range(l)
      ImGui.SetNextItemWidth(ctx, 170)
      local ca, na = ST.slider_double(ctx, "At 0%##modfrom" .. tag, a * 100, 0, 100, "%.0f%%")
      if ca then MD.set_range(app.track, l, na / 100, b) end
      if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "Control position at macro 0%.\nCtrl+click: type a value.") end
      ImGui.SetNextItemWidth(ctx, 170)
      local cb, nb = ST.slider_double(ctx, "At 100%##modto" .. tag, b * 100, 0, 100, "%.0f%%")
      if cb then MD.set_range(app.track, l, a, nb / 100) end
      if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "Control position at macro 100%.\nCtrl+click: type a value.") end
      if ImGui.MenuItem(ctx, "Swap the ends" .. tag) then MD.set_range(app.track, l, b, a) end
      if ImGui.MenuItem(ctx, "Whole range" .. tag) then MD.set_range(app.track, l, 0, 1) end
      if ImGui.MenuItem(ctx, "Remove the link" .. tag) then MD.unlink(app.track, l) end
    else
      ImGui.SetNextItemWidth(ctx, 170)
      local depth = math.abs(l.scale) * 100
      local ch, nv = ST.slider_double(ctx, "Depth##moddepth" .. tag, depth, 0, 100, "%.0f%%")
      if ch then MD.set_depth(app.track, l, (l.scale < 0 and -1 or 1) * nv / 100) end
      if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "Modulation amount.\nCtrl+click: type a value.") end
      local inv = l.scale < 0
      local ich = ST.checkbox(ctx, "Invert##modinv" .. tag, inv)
      if ich then MD.invert(app.track, l) end
      ImGui.SameLine(ctx, 0, 14)
      local bi = MD.is_bipolar(l)
      local bch = ST.checkbox(ctx, "Bipolar##modbi" .. tag, bi)
      if bch then MD.set_bipolar(app.track, l, not bi) end
      if ImGui.IsItemHovered(ctx) then
        ImGui.SetTooltip(ctx, "Swing both ways around the set position.")
      end
      if ImGui.MenuItem(ctx, "Remove modulation" .. tag) then MD.unlink(app.track, l) end
    end
  end
  if #s.list > 0 then
    if ImGui.BeginMenu(ctx, pre .. (l and "Driven by another\u{2026}" or "Link to a macro or modulator") .. tag) then
      local last
      for _, src in ipairs(s.list) do
        if last and last ~= src.src then ImGui.Separator(ctx) end
        last = src.src
        -- one entry per output (an XY pad's X and Y)
        for k = 1, #src.out do
          local dl = ImGui.GetWindowDrawList(ctx)
          local x, y = ImGui.GetCursorScreenPos(ctx)
          local nm = src.name
          if #src.out > 1 then nm = nm .. " \u{00B7} " .. ((src.labels and src.labels[k]) or tostring(k)) end
          local cur = l and l.mod.guid == src.guid and l.out == k
          if ImGui.MenuItem(ctx, "      " .. nm .. "##lk" .. src.guid .. k .. tag, nil, cur) then
            if not cur then
              link_source(src, k, fx.path_t, param, c.label, l, c.bipolar or nil)
            end
          end
          ImGui.DrawList_AddRectFilled(dl, x + 2, y + 4, x + 11, y + 13, src.col, 2)
        end
      end
      ImGui.EndMenu(ctx)
    end
  end
end

-- The links on this control: an XY pad's X and Y, a dual knob's ring and
-- inner knob each take their own.
local function mod_items(fx, c)
  if not (app.track and c and c.param and c.param >= 0) then return end
  local two = (c.type == "xy" or c.type == "dual") and c.param2 and c.param2 >= 0
  if not two then return link_items(fx, c, c.param, nil) end
  local a1, a2 = "X", "Y"
  if c.type == "dual" then a1, a2 = "Ring", "Inner" end
  link_items(fx, c, c.param, a1)
  ImGui.Separator(ctx)
  link_items(fx, c, c.param2, a2)
  ImGui.Separator(ctx)
end

-- "Automation lane" for a control's parameter(s): shows it (made if
-- there isn't one), or hides it. An XY pad or a dual knob has two.
local function lane_items(fx, c)
  if not (app.track and c and c.param and c.param >= 0) then return end
  local EN = require("TS_CV_Envelopes")
  local function item(p, what)
    local l = EN.fx_lane(app.track, fx.addr, p)
    if ImGui.MenuItem(ctx, "Automation lane" .. (what and (": " .. what) or "") .. "##lane" .. p,
                      l and l.auto and "has automation" or nil, l ~= nil and l.shown) then
      EN.toggle_fx_lane(app.track, fx.addr, p)
    end
    if l and ImGui.MenuItem(ctx, "Remove the lane" .. (what and (": " .. what) or "") .. "##lanerm" .. p) then
      local n = reaper.CountEnvelopePoints(l.env) or 0
      if not l.auto or reaper.MB(("Remove the lane and its automation (%d points)?"):format(n), "ChannelView", 4) == 6 then
        EN.remove(app.track, l.env)
      end
    end
  end
  local two = (c.type == "xy" or c.type == "dual") and c.param2 and c.param2 >= 0
  if two then
    local _, n1 = reaper.TrackFX_GetParamName(app.track, fx.addr, c.param, "")
    local _, n2 = reaper.TrackFX_GetParamName(app.track, fx.addr, c.param2, "")
    item(c.param, U.truncate(n1 or "", 20))
    item(c.param2, U.truncate(n2 or "", 20))
  else
    item(c.param)
  end
end

-- ---------------------------------------------------------------------
-- a control's right-click, in four parts: CONTROL (what it does: every
-- one of these is in Edit parameters too), LOOK (how it looks: only
-- here), AUTOMATE (what drives it) and ARRANGE (where it sits)
-- ---------------------------------------------------------------------

local function enter_pressed()
  return ImGui.IsItemDeactivated(ctx) and (ImGui.IsKeyPressed(ctx, ImGui.Key_Enter)
         or ImGui.IsKeyPressed(ctx, ImGui.Key_KeypadEnter))
end

-- Name: everything a control is called -- the parameter's alias (this
-- plugin, everywhere), this slot's own label, its live name, a button's
-- names for its two states, and a dropdown's (or stepped knob's) names
-- for its choices.
local function name_menu(fx, key, layout, idx, c)
  local function tip(t) if ImGui.IsItemHovered(ctx, ImGui.HoveredFlags_AllowWhenDisabled) then ImGui.SetTooltip(ctx, t) end end
  -- Renaming here sets the parameter's ALIAS: the name sticks to the
  -- parameter for this plugin everywhere, panels and editor lists alike.
  -- This slot's own label, if it has one, is cleared, or it would go on
  -- hiding the new name on the very control you renamed.
  ImGui.TextDisabled(ctx, "Alias: this plugin, everywhere")
  ImGui.SetNextItemWidth(ctx, 170)
  local _, v = ImGui.InputTextWithHint(ctx, "##alias", "name\u{2026}", app.rename_buf or "")
  local alias_enter = enter_pressed()
  app.rename_buf = v
  ImGui.SameLine(ctx)
  if ImGui.Button(ctx, "Set##alias") or alias_enter then
    local l = materialise(fx)
    local lc = l.controls[idx]
    if lc and lc.label and lc.label ~= "" then lc.label = ""; M.set(key, l); app.label_buf = "" end
    M.set_alias(key, c.param, app.rename_buf)
    M.save()
    ImGui.CloseCurrentPopup(ctx)
  end
  ImGui.TextDisabled(ctx, "Label: this slot only")
  ImGui.SetNextItemWidth(ctx, 170)
  local _, lv = ImGui.InputTextWithHint(ctx, "##label", "name\u{2026}", app.label_buf or "")
  local label_enter = enter_pressed()
  app.label_buf = lv
  ImGui.SameLine(ctx)
  if ImGui.Button(ctx, "Set##label") or label_enter then
    local l = materialise(fx)
    local lc = l.controls[idx]
    if lc then lc.label = U.trim(app.label_buf or "") end
    M.set(key, l); M.save()
    ImGui.CloseCurrentPopup(ctx)
  end
  tip("Name for this slot only, over the alias.\nClear to show the alias.")
  if ImGui.MenuItem(ctx, "Live name", nil, (c.live or layout.live) and true or false, not layout.live) then
    local l = materialise(fx)
    local lc = l.controls[idx]
    if lc then lc.live = (not c.live) or nil end
    M.set(key, l); M.save()
  end
  tip(layout.live and "On for the whole layout (Live parameter names)."
    or "Show the plugin's current name for this parameter.")
  if ImGui.MenuItem(ctx, "Show name", nil, not c.noname) then
    local l = materialise(fx)
    local lc = l.controls[idx]
    if lc then
      local old = {}
      for k, v in pairs(lc) do old[k] = v end
      lc.noname = (not c.noname) or nil
      P.knob_reframe(lc, old)
    end
    M.set(key, l); M.save()
  end
  tip("Off: no name over it, and no room kept for one. Its name shows on hover.")
  if c.type == nil or c.type == "knob" or c.type == "stepped" or c.type == "dual" then
    if ImGui.MenuItem(ctx, "Value inside the knob", nil, c.vin == true) then
      local l = materialise(fx)
      local lc = l.controls[idx]
      if lc then
        local old = {}
        for k, v in pairs(lc) do old[k] = v end
        lc.vin = (not c.vin) or nil
        P.knob_reframe(lc, old)
      end
      M.set(key, l); M.save()
    end
    tip("Its value in the knob's middle, without units, and no value line under it.")
  end

  -- A button's two states can have names of their own, for plugins whose
  -- switches read "0.0"/"1.0" or worse. Hints are what the plugin says.
  if c.type == "toggle" then
    ImGui.Separator(ctx)
    ImGui.TextDisabled(ctx, "State names: this plugin, everywhere")
    local function hint(n)
      if reaper.TrackFX_FormatParamValueNormalized then
        local ok, t = U.format_norm(app.track, fx.addr, c.param, n, "")
        if ok and t and t ~= "" then return t end
      end
      return n < 0.5 and "off" or "on"
    end
    app.state_buf = app.state_buf or { "", "" }
    ImGui.SetNextItemWidth(ctx, 82)
    local _, v1 = ImGui.InputTextWithHint(ctx, "##stoff", hint(0), app.state_buf[1])
    local e1 = enter_pressed()
    app.state_buf[1] = v1
    ImGui.SameLine(ctx, 0, 6)
    ImGui.SetNextItemWidth(ctx, 82)
    local _, v2 = ImGui.InputTextWithHint(ctx, "##ston", hint(1), app.state_buf[2])
    local e2 = enter_pressed()
    app.state_buf[2] = v2
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, "Set##states") or e1 or e2 then
      materialise(fx)
      M.set_states(key, c.param, app.state_buf[1], app.state_buf[2])
      M.save()
      ImGui.CloseCurrentPopup(ctx)
    end
    tip("Off, then on, read under the button. Leave empty to keep the plugin's text.")
    -- and the words on the button itself, apart from them
    ImGui.TextDisabled(ctx, "Button text: this plugin, everywhere")
    ImGui.SetNextItemWidth(ctx, 82)
    local _, b1 = ImGui.InputTextWithHint(ctx, "##btoff", "OFF", app.state_buf[3] or "")
    local f1 = enter_pressed()
    app.state_buf[3] = b1
    ImGui.SameLine(ctx, 0, 6)
    ImGui.SetNextItemWidth(ctx, 82)
    local _, b2 = ImGui.InputTextWithHint(ctx, "##bton", "ON", app.state_buf[4] or "")
    local f2 = enter_pressed()
    app.state_buf[4] = b2
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, "Set##btext") or f1 or f2 then
      materialise(fx)
      M.set_btext(key, c.param, app.state_buf[3], app.state_buf[4])
      M.save()
      ImGui.CloseCurrentPopup(ctx)
    end
    tip("Off, then on. Leave empty to show the state names.")
  end

  -- A dropdown's choices, likewise (Choices<p>): one box each, the
  -- plugin's text as the hint. Read without moving anything.
  if (c.type == "combo" or c.type == "stepped") and (c.param or -1) >= 0 then
    ImGui.Separator(ctx)
    ImGui.TextDisabled(ctx, "Choice names: this plugin, everywhere")
    -- names that follow another control (a list that changes with it and
    -- only numbers its choices): a set for each of its settings, the one
    -- being named picked here (which switches the plugin to it)
    -- (the setting being named is kept here, app.choice_ctx, not read back
    -- from the plugin: a plugin can take a moment to show a change)
    local by = M.choice_by(key, c.param)
    if by and not app.choice_ctx then app.choice_ctx = M.choice_context(key, c.param, app.track, fx.addr) end
    local function load_buf()
      app.choice_buf = {}
      for t, nm in pairs(M.get_choice_names(key, c.param, app.track, fx.addr, app.choice_ctx) or {}) do app.choice_buf[t] = nm end
    end
    do
      local opts, keys, now = { "Nothing" }, { false }, 0
      for _, o in ipairs(layout.controls or {}) do
        if (o.type == "combo" or o.type == "stepped") and o.param and o.param >= 0 and o.param ~= c.param then
          local _, pn = reaper.TrackFX_GetParamName(app.track, fx.addr, o.param, "")
          opts[#opts + 1] = M.display_name(key, o.param, o.label, pn, false)
          keys[#keys + 1] = o.param
          if o.param == by then now = #keys - 1 end
        end
      end
      if #keys > 1 or by then
        ImGui.SetNextItemWidth(ctx, 150)
        local fch, fi = ImGui.Combo(ctx, "Names follow##chby", now, table.concat(opts, "\0") .. "\0")
        if fch then
          materialise(fx)
          M.set_choice_by(key, c.param, keys[fi + 1] or nil)
          M.save()
          by = M.choice_by(key, c.param)
          app.choice_ctx = by and M.choice_context(key, c.param, app.track, fx.addr) or nil
          load_buf()
        end
        tip("For a list that changes with another control:\na set of names for each of its settings.")
      end
    end
    if by then
      -- which of its settings is being named: picking one switches the
      -- plugin to it (what's typed for the one before is kept first)
      local blist = P.read_choices(app.track, fx.addr, by, key) or P.button_choices(app.track, fx.addr, by, key, nil)
      local cur = app.choice_ctx
      if type(blist) == "table" and #blist > 1 then
        local names, now = {}, 0
        for i, e in ipairs(blist) do
          names[i] = (e.text or tostring(i)):gsub("%z", "")
          if e.text == cur then now = i - 1 end
        end
        ImGui.SetNextItemWidth(ctx, 150)
        local bch, bi = ImGui.Combo(ctx, "Naming##chctx", now, table.concat(names, "\0") .. "\0")
        if bch and blist[bi + 1] then
          materialise(fx)
          -- what's typed stays with the one it was typed for
          if cur then M.set_choice_names(key, c.param, app.choice_buf or {}, app.track, fx.addr, cur) end
          reaper.TrackFX_SetParamNormalized(app.track, fx.addr, by, blist[bi + 1].norm)
          app.choice_ctx = (blist[bi + 1].text or ""):gsub("[~|\r\n]", " ")
          M.save()
          load_buf()
        end
        tip("The setting whose names you're typing.\nPicking one switches the plugin to it.")
      elseif cur then
        ImGui.TextDisabled(ctx, "For " .. cur .. ":")
      end
    end
    local list = P.read_choices(app.track, fx.addr, c.param, key) or P.button_choices(app.track, fx.addr, c.param, key, c.nbtn)
    if type(list) ~= "table" or #list < 2 then
      ImGui.TextDisabled(ctx, "Open the dropdown once to read its choices.")
    else
      app.choice_buf = app.choice_buf or {}
      local buf = app.choice_buf
      local HID = M.HIDDEN
      -- how many there are: the rest are left out of the list
      local count = 0
      for i, e in ipairs(list) do if buf[e.text or tostring(i)] ~= HID then count = i end end
      ImGui.SetNextItemWidth(ctx, 90)
      local cch, cv_ = ImGui.InputInt(ctx, "How many##chcount", count)
      if cch then
        cv_ = math.max(1, math.min(#list, cv_))
        for i, e in ipairs(list) do
          local t = e.text or tostring(i)
          if i > cv_ then buf[t] = HID elseif buf[t] == HID then buf[t] = nil end
        end
      end
      tip("How many it has here: the rest are left out of the list.")
      local rows = math.min(#list, 12)
      local entered = false
      local fh = ImGui.GetFrameHeightWithSpacing(ctx)
      -- a dropdown's: the folder each is in, in the open list
      local folds = c.type == "combo"
      app.fold_buf = app.fold_buf or {}
      local fbuf = app.fold_buf
      if folds then
        ImGui.TextDisabled(ctx, "Name")
        ImGui.SameLine(ctx, 212)
        ImGui.TextDisabled(ctx, "Folder")
      end
      if ImGui.BeginChild(ctx, "##chnames", folds and 360 or 250, rows * fh + 4, 0) then
        for i, e in ipairs(list) do
          local t = e.text or tostring(i)
          local hidden = buf[t] == HID
          if hidden then ImGui.BeginDisabled(ctx, true) end
          ImGui.SetNextItemWidth(ctx, 200)
          local _, nv = ImGui.InputTextWithHint(ctx, "##chn" .. i, t, hidden and "" or (buf[t] or ""))
          if not hidden then
            if enter_pressed() then entered = true end
            buf[t] = nv
          end
          if folds then
            ImGui.SameLine(ctx, 0, 4)
            ImGui.SetNextItemWidth(ctx, 106)
            local _, fv = ImGui.InputTextWithHint(ctx, "##chf" .. i, "\u{2014}", hidden and "" or (fbuf[t] or ""))
            if not hidden then
              if enter_pressed() then entered = true end
              fbuf[t] = fv
            end
            if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "Its folder in the list. Empty: the top.") end
          end
          if hidden then ImGui.EndDisabled(ctx) end
          ImGui.SameLine(ctx, 0, 4)
          if ImGui.SmallButton(ctx, (hidden and "\u{21BA}" or "\u{2715}") .. "##chx" .. i) then
            buf[t] = (not hidden) and HID or nil
          end
          if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, hidden and "Put it back in the list" or "Leave it out of the list") end
        end
        ImGui.EndChild(ctx)
      end
      if ImGui.Button(ctx, "Set##choices") or entered then
        materialise(fx)
        M.set_choice_names(key, c.param, buf, app.track, fx.addr, by and app.choice_ctx or nil)
        if folds then M.set_choice_folders(key, c.param, fbuf) end
        M.save()
        ImGui.CloseCurrentPopup(ctx)
      end
      ImGui.SameLine(ctx)
      if ImGui.Button(ctx, "Clear##choices") then app.choice_buf, app.fold_buf = {}, {} end
      tip("Empty: the plugin's own name (Set after Clear: all back).")
    end
  end
end

-- Values: what the parameter reads as -- the plugin's own, or your range
-- for a plugin that won't say (Range<p>, TS_CV_Util U.range_*). The same
-- as Edit parameters' Values row.
local function values_menu(fx, key, layout, idx, c)
  local p = c.param
  local rg = layout.ranges and layout.ranges[p]
  local tag = fx.guid .. ":" .. p
  local only = rg and rg.only
  if app.rng_for ~= tag then
    local r0 = (rg and not only) and rg or E.range_start(app.track, fx.addr, p)
    if only then r0.unit = rg.unit end
    local ui, ci = 1, 1
    for i, u in ipairs(U.RANGE_UNITS) do if u == (r0.unit or "") then ui = i end end
    for i, k in ipairs(U.RANGE_CURVES) do if k == (r0.curve or "lin") then ci = i end end
    app.rng_for = tag
    app.rng = { lo = ("%g"):format(r0.lo), hi = ("%g"):format(r0.hi), unit = ui, curve = ci }
  end
  local b = app.rng
  local function typed()
    local lo, hi = E.parse_num(b.lo), E.parse_num(b.hi)
    if not lo or not hi or lo == hi then return nil end
    return { lo = lo, hi = hi, unit = U.RANGE_UNITS[b.unit] or "", curve = U.RANGE_CURVES[b.curve] or "lin" }
  end
  local function store(r)
    local l = materialise(fx)
    if r then l.ranges = l.ranges or {}; l.ranges[p] = r
    elseif l.ranges then l.ranges[p] = nil end
    M.set(key, l); M.save()
  end
  -- numbers round the dial, like a hardware knob's printed scale (a
  -- knob's; values unless it says otherwise; a small knob has no room)
  -- a concentric knob's: its values under it, or nothing there
  if c.type == "dual" then
    ImGui.TextDisabled(ctx, "Under it")
    for i, o in ipairs({ { false, "Values" }, { "blank", "Nothing" } }) do
      if i > 1 then ImGui.SameLine(ctx, 0, 4) end
      if ImGui.Selectable(ctx, o[2] .. "##dscale_" .. i, (c.scale == "blank") == (o[1] == "blank"), KEEP_OPEN, 56, 0) then
        local l = materialise(fx)
        local lc = l.controls[idx]
        if lc then
          local old = {}
          for k, v in pairs(lc) do old[k] = v end
          lc.scale = o[1] or nil
          P.knob_reframe(lc, old)
        end
        M.set(key, l); M.save()
      end
      if o[1] and ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "No values under it: they're in the tooltip.") end
    end
    ImGui.Separator(ctx)
  end
  if c.type == "knob" or c.type == "stepped" or c.type == nil then
    ImGui.TextDisabled(ctx, "Numbers round the dial")
    local sc_now = (c.scale == "blank") and "blank" or M.scale_kind(c) or "none"
    local small = c.size == "small"
    ImGui.BeginDisabled(ctx, small)
    for i, o in ipairs({ { "none", "None" }, { "values", "Values" }, { "ten", "0\u{2013}10" }, { "blank", "Nothing" } }) do
      if i > 1 then ImGui.SameLine(ctx, 0, 4) end
      if ImGui.Selectable(ctx, o[2] .. "##scale_" .. o[1], o[1] == sc_now, KEEP_OPEN, 56, 0) then
        local l = materialise(fx)
        local lc = l.controls[idx]
        if lc then
          local old = {}
          for k, v in pairs(lc) do old[k] = v end
          lc.scale = (o[1] ~= "values") and o[1] or nil
          if o[1] == "none" or o[1] == "blank" then lc.scale_ink = nil end
          P.knob_reframe(lc, old)
        end
        M.set(key, l); M.save()
      end
      if ImGui.IsItemHovered(ctx, ImGui.HoveredFlags_AllowWhenDisabled) then
        ImGui.SetTooltip(ctx, small and "A small knob has no room for numbers."
          or (o[1] == "values") and "Its values, without units (thousands as k).\nMedium knobs then show the value in the tooltip."
          or (o[1] == "ten") and "0 to 10."
          or (o[1] == "blank") and "No numbers and no value under it:\nthe value's in its tooltip."
          or "No numbers: its value under it.")
      end
    end
    ImGui.EndDisabled(ctx)
    ImGui.Separator(ctx)
  end
  -- how many settings, for a parameter that reports no steps (Steps<p>)
  if not P.own_step(app.track, fx.addr, p, key) then
    local cur = layout.steps and layout.steps[p] or 0
    local function put(n)
      local l = materialise(fx)
      if n then l.steps = l.steps or {}; l.steps[p] = n
      elseif l.steps then l.steps[p] = nil; if not next(l.steps) then l.steps = nil end end
      -- buttons follow the count
      for _, lc in ipairs(l.controls or {}) do
        if lc.param == p and lc.buttons then lc.nbtn = n or lc.nbtn end
      end
      M.set(key, l); M.save()
    end
    ImGui.TextDisabled(ctx, "Steps")
    ImGui.SetNextItemWidth(ctx, 90)
    local ch, v = ImGui.InputInt(ctx, "##steps", cur)
    if ch then
      if v == 1 then v = (cur == 0) and 2 or 0 end
      put((v >= 2) and math.min(64, v) or nil)
    end
    if ImGui.IsItemHovered(ctx) then
      ImGui.SetTooltip(ctx, "How many settings it has, for a plugin that doesn't say. 0: none.")
    end
    local dn = cur == 0 and P.detect_steps(app.track, fx.addr, p, key)
    if dn then
      ImGui.SameLine(ctx, 0, 6)
      if ImGui.SmallButton(ctx, ("Use %d##steps_use"):format(dn)) then put(dn) end
      if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "What the plugin's readout shows along its range.") end
    end
    ImGui.Separator(ctx)
  end
  -- (a dropdown's values are its settings)
  if c.type == "combo" then return end
  ImGui.TextDisabled(ctx, "What it reads as")
  if ImGui.MenuItem(ctx, "The plugin's own", nil, rg == nil or only) and rg and not only then
    store(nil); app.rng_for = nil
  end
  -- the plugin's own numbers in a unit (Range<p>=||Hz|): no ends to know
  if (rg == nil or only) and ImGui.BeginMenu(ctx, "Unit") then
    if ImGui.MenuItem(ctx, "None", nil, not only) and only then store(nil); app.rng_for = nil end
    for _, u in ipairs(U.RANGE_UNITS) do
      if u ~= "" and ImGui.MenuItem(ctx, u .. "##unit", nil, only and rg.unit == u) then
        store({ unit = u, only = true }); app.rng_for = nil
      end
    end
    ImGui.EndMenu(ctx)
  end
  if (rg == nil or only) and ImGui.IsItemHovered(ctx) then
    ImGui.SetTooltip(ctx, "Its own numbers, read in a unit (20000 as 20 kHz).")
  end
  local want = typed()
  if ImGui.MenuItem(ctx, "Custom range", nil, rg ~= nil and not only, want ~= nil) then store(want) end
  if ImGui.IsItemHovered(ctx, ImGui.HoveredFlags_AllowWhenDisabled) then
    ImGui.SetTooltip(ctx, "Your own range (below), for plugins that don't report values.")
  end
  ImGui.Separator(ctx)
  ST.cap(ctx, "From")
  ImGui.SetNextItemWidth(ctx, 74)
  local _, lo = ImGui.InputText(ctx, "##rmlo", b.lo)
  local e1 = enter_pressed()
  b.lo = lo
  ST.done(ctx)
  ImGui.SameLine(ctx, 0, 8)
  ST.cap(ctx, "To")
  ImGui.SetNextItemWidth(ctx, 74)
  local _, hi = ImGui.InputText(ctx, "##rmhi", b.hi)
  local e2 = enter_pressed()
  b.hi = hi
  ST.done(ctx)
  local un = {}
  for i, u in ipairs(U.RANGE_UNITS) do un[i] = (u == "") and "none" or u end
  ST.cap(ctx, "Unit")
  ImGui.SetNextItemWidth(ctx, 74)
  local uch, ui = ImGui.Combo(ctx, "##rmunit", b.unit - 1, table.concat(un, "\0") .. "\0")
  if uch then b.unit = ui + 1 end
  ST.done(ctx)
  ImGui.SameLine(ctx, 0, 8)
  ST.cap(ctx, "Curve")
  ImGui.SetNextItemWidth(ctx, 74)
  local cch, ci = ImGui.Combo(ctx, "##rmcurve", b.curve - 1, "Linear\0Log\0Squared\0")
  if cch then b.curve = ci + 1 end
  ST.done(ctx)
  want = typed()
  local now = reaper.TrackFX_GetParamNormalized(app.track, fx.addr, p) or 0
  ImGui.TextDisabled(ctx, want and ("now reads " .. U.range_text(want, now)) or "type two different ends")
  if ST.button(ctx, "Set##rmset", "main", nil, nil, { dim = not want }) or ((e1 or e2) and want) then
    store(want); ImGui.CloseCurrentPopup(ctx)
  end
  ImGui.SameLine(ctx)
  if ST.button(ctx, "Clear##rmclr", "remove", nil, nil, { dim = not rg or only }) then
    store(nil); app.rng_for = nil; ImGui.CloseCurrentPopup(ctx)
  end
end

-- Show when: Always, or one click on a button, dropdown, stepped knob or
-- virtual control on this layout; anything else (another parameter, is
-- not / above / between) is Edit parameters, opened at this control.
local function show_when_menu(fx, key, layout, idx, c)
  local function set(r)
    local l = materialise(fx)
    local lc = l.controls[idx]
    if lc then lc.show = r end
    M.set(key, l); M.save()
  end
  local base = M.split_variant(key)
  if c.show then
    local function pname(p)
      local _, pn = reaper.TrackFX_GetParamName(app.track, fx.addr, p, "")
      return M.display_name(key, p, nil, pn, false)
    end
    local function fmt(p, n)
      local ok_, sv = U.format_norm(app.track, fx.addr, p, n, "")
      return ok_ and U.trim(sv or "") or nil
    end
    local function vfind(nm)
      local _, vc = M.vstart(base or key, nm, layout.controls)
      return vc
    end
    ImGui.TextDisabled(ctx, "Now: " .. U.truncate(M.rule_text(c.show, pname, fmt, vfind), 44))
    ImGui.Separator(ctx)
  end
  if ImGui.MenuItem(ctx, "Always", nil, c.show == nil) and c.show then set(nil) end
  local list = E.show_sources(app.track, fx.addr, key, layout.controls, c)
  if #list > 0 then ImGui.Separator(ctx) end
  for i, e in ipairs(list) do
    -- its settings with ticks: shown while it's on any ticked one (the
    -- list stays open, to tick several); a "not" rule on it keeps its op
    local op = c.show and M.show_op(c.show)
    local mine = c.show and (op == "is" or op == "not")
      and ((e.vname and c.show.vname == e.vname) or (not e.vname and not c.show.vname and c.show.param == e.param))
    if ImGui.BeginMenu(ctx, U.truncate(e.label, 28) .. "##sw" .. i) then
      local now = mine and M.show_values(c.show) or {}
      local function ticked(n)
        for _, v in ipairs(now) do if math.abs(v - n) < 1e-4 then return true end end
        return false
      end
      if mine and op == "not" then ImGui.TextDisabled(ctx, "Hidden on the ticked ones") end
      for k, ch in ipairs(e.choices) do
        local cur = ticked(ch.norm)
        if ImGui.Checkbox(ctx, U.truncate((ch.text or tostring(k)):gsub("%z", ""), 24) .. "##swc" .. k, cur) then
          local keep = {}
          for _, ch2 in ipairs(e.choices) do
            local on = ticked(ch2.norm)
            if ch2.norm == ch.norm then on = not on end
            if on then keep[#keep + 1] = ch2.norm end
          end
          local r = { param = e.param, vname = e.vname, op = mine and op or "is", tol = e.tol }
          set(M.show_set_values(r, keep) and r or nil)
        end
      end
      if mine then
        ImGui.Separator(ctx)
        if ImGui.MenuItem(ctx, "Clear##swclr" .. i) then set(nil) end
      end
      ImGui.EndMenu(ctx)
    end
  end
  ImGui.Separator(ctx)
  if ImGui.MenuItem(ctx, "Another rule\u{2026}") then E.open(app.track, fx, key, layout, idx) end
  if ImGui.IsItemHovered(ctx) then
    ImGui.SetTooltip(ctx, "Other conditions (is not / above / below / between)\nin Edit parameters.")
  end
end

-- What acts on the whole plugin rather than this control
local function plugin_sub(fx)
  if ImGui.BeginMenu(ctx, "Plugin") then
    if ImGui.MenuItem(ctx, St.is_collapsed(fx.guid) and "Expand" or "Collapse to a bar") then
      toggle_fold(fx)
    end
    if ImGui.MenuItem(ctx, "Move left", nil, false, fx.index > 0) then nudge(fx.path_t, -1) end
    if ImGui.MenuItem(ctx, "Move right", nil, false, fx.index < fx.siblings - 1) then nudge(fx.path_t, 1) end
    if ImGui.MenuItem(ctx, "Open the plugin's window") then reaper.TrackFX_Show(app.track, fx.addr, 3) end
    ImGui.EndMenu(ctx)
  end
end

-- A control and its container's panel (TS_CV_Containers): put it on the
-- panel of the container it's in (or one further out), or, on a
-- container's own panel, take it off.
local function container_items(fx, c)
  if not (app.track and c and c.param and c.param >= 0) then return end
  local tr = app.track
  if fx.container_panel then
    ImGui.SeparatorText(ctx, "Container")
    local slot, p = CT.source(tr, fx.addr, c.param)
    local inner
    if slot then
      local path = {}
      for d, v in ipairs(fx.path_t) do path[d] = v end
      path[#path + 1] = slot
      inner = T.addr_of(tr, path)
    end
    -- a macro's or modulator's link runs through it: off the panel, but
    -- the parameter stays (the link needs it)
    local busy = CT.carries(tr, fx.addr, fx.path_t, c.param)
    if ImGui.MenuItem(ctx, busy and "Hide from the container" or "Take off the container") then
      reaper.Undo_BeginBlock()
      local what = CT.take_off(tr, fx.addr, fx.guid, fx.path_t, c.param)
      if what then CT.fix_layout(fx.name, CT.key(tr, fx.addr, nil, fx.path_t), c.param, what == "deleted") end
      reaper.Undo_EndBlock("ChannelView: take a control off its container", -1)
      M.clear_default_cache()
      rescan(true)
    end
    if busy and ImGui.IsItemHovered(ctx) then
      ImGui.SetTooltip(ctx, "A macro or modulator drives it through the container, so the\n" ..
        "container keeps the parameter (REAPER's Param menu still lists it);\nit just leaves this panel.")
    end
    if inner and ImGui.MenuItem(ctx, "Open " .. U.truncate(U.clean_fx_name(select(2, reaper.TrackFX_GetFXName(tr, inner, ""))), 24) .. "'s window") then
      reaper.TrackFX_Show(tr, inner, 3)
    end
    return
  end
  local anc = fx.ancestors
  if not anc or #anc == 0 then return end
  ImGui.SeparatorText(ctx, "Container")
  -- the container it's in first, then those further out
  for up = 1, #anc do
    local node = anc[#anc - up + 1]
    local on = CT.is_on(tr, fx.path_t, c.param, up)
    local label = (up == 1 and "On its container" or "On the outer container") .. ": " .. box_label(node)
    if ImGui.MenuItem(ctx, label .. "##ct" .. up, nil, on) then
      reaper.Undo_BeginBlock()
      local was = CT.key(tr, node.addr, node.guid, node.path)
      if on then
        local p = CT.put(tr, fx.path_t, c.param, up)   -- (found, not made)
        local what = p and CT.take_off(tr, node.addr, node.guid, node.path, p)
        if what then CT.fix_layout(was, CT.key(tr, node.addr, nil, node.path), p, what == "deleted") end
      else
        local p = CT.put(tr, fx.path_t, c.param, up)
        -- a container panel with a layout of its own takes it at the end
        if p then
          CT.carry(was, CT.key(tr, node.addr, nil, node.path), function(l, own)
            if not own then return end
            l.controls = l.controls or {}
            l.controls[#l.controls + 1] = M.apply_default_look({ param = p, type = "knob", label = "" })
          end)
        end
      end
      reaper.Undo_EndBlock("ChannelView: " .. (on and "take a control off" or "put a control on") .. " its container", -1)
      M.clear_default_cache()
      rescan(true)
    end
    if ImGui.IsItemHovered(ctx) then
      ImGui.SetTooltip(ctx, on and "On that container's panel. Click: take it off."
        or "Show this control on the container's own panel too:\nturning either turns both, and it goes with the container\ninto an FX chain or a track template.")
    end
  end
end

local function automate_items(fx, c)
  if not (app.track and c and c.param and c.param >= 0) then return end
  ImGui.SeparatorText(ctx, "Automate")
  mod_items(fx, c)
  lane_items(fx, c)
  -- the MIDI learn bar, with this control's parameter in it
  local two = M.has_second(c) and c.param2 and c.param2 >= 0
  local a1, a2 = (c.type == "xy") and "X" or "ring", (c.type == "xy") and "Y" or "inner knob"
  if ImGui.MenuItem(ctx, two and ("MIDI learn (" .. a1 .. ")\u{2026}") or "MIDI learn\u{2026}") then
    ML.open_for(app.track, fx.guid, fx.addr, c.param)
  end
  if ImGui.IsItemHovered(ctx) then
    ImGui.SetTooltip(ctx, "Link to a MIDI control via the MIDI learn bar.")
  end
  if two and ImGui.MenuItem(ctx, "MIDI learn (" .. a2 .. ")\u{2026}") then
    ML.open_for(app.track, fx.guid, fx.addr, c.param2)
  end
  param_mod_item(fx, c)
end

-- The grid editor's sheet draws the panel's own menus (TS_CV_GridEditor
-- GE.hooks): for the plugin it's editing while ChannelView shows its
-- track with the same layout, so they work on the same list.
if ED.PRO then
require("TS_CV_GridEditor").hooks = (function()
  local GEd = require("TS_CV_GridEditor")
  local function live(fx)
    for _, f in ipairs(app.chain or {}) do if f.guid == fx.guid then return f end end
    return nil
  end
  -- (on a short form, the editor's: that form's controls)
  local function on(fx, fn, ...)
    local f = live(fx)
    FRM.set(f, GEd.form())
    fn(f, ...)
    FRM.on = nil
  end
  return {
    ready = function(track, fx, key)
      local f = (track == app.track) and live(fx)
      if not f then return false end
      local _, k = layout_for(f)
      return k == key
    end,
    style    = function(fx, key, idx, c) on(fx, style_menu, key, idx, c) end,
    back     = function(fx, key, idx, c) on(fx, back_menu, key, idx, c) end,
    section  = function(fx, key, idx, c) on(fx, section_menu, key, idx, c) end,
    look     = function(fx, key, layout, idx, c, locked) on(fx, look_items, key, layout, idx, c, locked) end,
    plate    = function(fx, key, layout) plate_menu(live(fx), key, layout) end,
    -- a colour for control idx's `field` (a line's or a section
    -- outline's, Edge<n>): none (`none`), a faceplate's, the plugin's own,
    -- recent ones, or one of your own -- the same choices as a background
    colour   = function(fx, key, idx, c, field, title, none)
      local f = live(fx)
      local form = GEd.form()
      local function cset(k, save)
        FRM.set(f, form)
        local l, pk = materialise(f)
        FRM.on = nil
        local lc = l.controls[idx]
        if lc then lc[field] = k end
        M.set(pk, l)
        if save then M.save() end
      end
      local now = c[field]
      if swatch_row(none, field .. "_none", now == nil, 170, 0, C.COL.panel_border) then cset(nil, true) end
      for _, pl in ipairs(C.PLATES) do
        if pl.bg and swatch_row(pl.label, field .. "_" .. pl.key, now == pl.key, 170, pl.bg, pl.border) then
          cset(pl.key, true)
        end
      end
      local now_pl = C.plate_of(now)
      custom_rows(field, now, 170, cset, title, now_pl and (now_pl.bg >> 8), f)
    end,
  }
end)()
end

-- A VU meter's settings changed (its switch or its menu): saved with the
-- layout. Showing levels or a reduction the plugin doesn't report needs
-- the TS_TrackProbe pair: offered when the track hasn't one.
function app.vu_set(fx, idx, changes)
  local l, key = materialise(fx)
  local c = l.controls and l.controls[idx]
  if not (c and c.type == "vu") then return end
  c.vu = c.vu or M.vu_default()
  for k, v in pairs(changes) do c.vu[k] = v end
  M.set(key, l); M.save()
  -- a Trimmer's 0 VU is its own setting (Auto and Listen aim for it)
  if changes.ref and TRM and TRM.is(fx.name or "") then TRM.set(app.track, fx.addr, TRM.P.REF, changes.ref) end
  -- (a Trimmer's levels are its own: no probes)
  if changes.src and not (TRM and TRM.is(fx.name or "")) then
    local needs = changes.src ~= "gr" or not T.reports_gr_natively(app.track, fx.addr, fx.guid)
    if needs then
      -- laid now, not on the track's next turn
      TP.invalidate()
      TP.sync(app.track)
      if TP.status(app.track, fx.guid) == "no_probes" and reaper.MB("It's measured by a TS_TrackProbe pair,\n" ..
          "which this track doesn't have.\n\nAdd them now?", "ChannelView", 4) == 6 then
        local ok, why = TP.insert_probes(app.track)
        if not ok then reaper.MB(why, "ChannelView", 0) end
      end
    end
  end
end

local function control_menu()
  if not ImGui.BeginPopup(ctx, "ctlmenu") then return end
  local cm = app.ctl_menu
  local fx = cm and app.chain[cm.fx]
  if not fx then ImGui.EndPopup(ctx) return end
  FRM.set(fx, cm.form)

  local layout, key = layout_for(fx)
  local c = layout.controls and layout.controls[cm.ctl]
  if not c then ImGui.EndPopup(ctx) return end
  local idx = cm.ctl
  -- from Edit layout (cm.ed): its edits whatever the lock, and nothing on
  -- the plugin or the editor it's already in
  local locked = M.locked(layout) and not cm.ed

  -- a virtual control (the layout's own): its name, back to where it
  -- starts, and the layout's edits; no parameter to link or automate
  if M.is_virtual(c) then
    local nm = M.vname_of(c)
    ImGui.TextDisabled(ctx, "\u{25C6} " .. U.truncate(nm, 26) .. "  (virtual)")
    ImGui.Separator(ctx)
    if ImGui.MenuItem(ctx, "Back to where it starts") then St.vset(fx.guid, nm, c.virtual.start or 0) end
    if not locked then
      ImGui.SeparatorText(ctx, "Arrange")
      if ImGui.MenuItem(ctx, "Remove from panel") then
        local l = materialise(fx); M.save()
        table.remove(l.controls, idx)
        M.set(key, l); M.save()
      end
      if not cm.ed then ImGui.Separator(ctx) end
      if not ED.PRO and ImGui.MenuItem(ctx, "Edit parameters\u{2026}") then E.open(app.track, fx, key, layout, idx) end
      if not cm.ed and ED.item(ImGui, ctx, "Edit layout\u{2026}") then
        require("TS_CV_GridEditor").open(app.track, fx, key, layout, idx,
          { rows = M.locked(layout) or (P.RACK and P.RACK_ROWS) or app.cv_rows or 2, index = cm.fx, cv_h = app.cv_h,
          rack_w = app.rack_w or tonumber(reaper.GetExtState(C.EXT_SECT, "rack_width")) })
      end
    end
    if not cm.ed then plugin_sub(fx) end
    ImGui.EndPopup(ctx)
    return
  end

  -- a VU meter: what it shows, its look, where 0 VU sits, its peak lamp
  if c.type == "vu" then
    local vu = c.vu or M.vu_default()
    ImGui.TextDisabled(ctx, "VU meter  \u{00B7}  " .. U.truncate(U.fx_label(fx), 20))
    ImGui.Separator(ctx)
    for _, o in ipairs({ { "in", "Shows: In" }, { "out", "Shows: Out" }, { "gr", "Shows: GR" } }) do
      if ImGui.MenuItem(ctx, o[2], nil, vu.src == o[1]) then app.vu_set(fx, idx, { src = o[1] }) end
    end
    ImGui.Separator(ctx)
    if ImGui.BeginMenu(ctx, "Look") then
      for _, o in ipairs({ { "classic", "Classic" }, { "dark", "Dark" }, { "analogue", "Analogue" },
        { "amber", "Amber" }, { "warm", "Warm white" }, { "bar", "Bar" } }) do
        if ImGui.MenuItem(ctx, o[2], nil, vu.look == o[1]) then app.vu_set(fx, idx, { look = o[1] }) end
      end
      ImGui.EndMenu(ctx)
    end
    if ImGui.MenuItem(ctx, "Stereo (left and right)", nil, vu.stereo == true) then app.vu_set(fx, idx, { stereo = not vu.stereo }) end
    if ImGui.MenuItem(ctx, "Hide the In / Out / GR buttons", nil, vu.noswitch == true) then
      app.vu_set(fx, idx, { noswitch = not vu.noswitch })
    end
    if ImGui.BeginMenu(ctx, "0 VU =") then
      for _, r in ipairs(M.VU_REFS) do
        if ImGui.MenuItem(ctx, r .. " dBFS", nil, vu.ref == r) then app.vu_set(fx, idx, { ref = r }) end
      end
      ImGui.EndMenu(ctx)
    end
    if ImGui.MenuItem(ctx, "Peak lamp", nil, vu.peak ~= false) then app.vu_set(fx, idx, { peak = vu.peak == false }) end
    if not locked then
      ImGui.Separator(ctx)
      if ImGui.MenuItem(ctx, "Remove from panel") then
        local l = materialise(fx); M.save()
        table.remove(l.controls, idx)
        M.set(key, l); M.save()
      end
      if not cm.ed and ED.item(ImGui, ctx, "Edit layout\u{2026}") then
        require("TS_CV_GridEditor").open(app.track, fx, key, layout, idx,
          { rows = M.locked(layout) or (P.RACK and P.RACK_ROWS) or app.cv_rows or 2, index = cm.fx, cv_h = app.cv_h,
          rack_w = app.rack_w or tonumber(reaper.GetExtState(C.EXT_SECT, "rack_width")) })
      end
    end
    if not cm.ed then plugin_sub(fx) end
    ImGui.EndPopup(ctx)
    return
  end

  -- an act button (a Trimmer's Auto, Listen): no parameter of its own
  if c.type == "act" then
    ImGui.TextDisabled(ctx, (M.ACTS[c.act or ""] or "Button") .. "  \u{00B7}  " .. U.truncate(U.fx_label(fx), 20))
    if not locked then
      ImGui.Separator(ctx)
      if ImGui.MenuItem(ctx, "Remove from panel") then
        local l = materialise(fx); M.save()
        table.remove(l.controls, idx)
        M.set(key, l); M.save()
      end
      if not cm.ed and ED.item(ImGui, ctx, "Edit layout\u{2026}") then
        require("TS_CV_GridEditor").open(app.track, fx, key, layout, idx,
          { rows = M.locked(layout) or (P.RACK and P.RACK_ROWS) or app.cv_rows or 2, index = cm.fx, cv_h = app.cv_h,
          rack_w = app.rack_w or tonumber(reaper.GetExtState(C.EXT_SECT, "rack_width")) })
      end
    end
    if not cm.ed then plugin_sub(fx) end
    ImGui.EndPopup(ctx)
    return
  end

  local _, pname = reaper.TrackFX_GetParamName(app.track, fx.addr, c.param or 0, "")
  ImGui.TextDisabled(ctx, U.truncate(pname or "", 26) .. "  \u{00B7}  " .. U.truncate(U.fx_label(fx), 20))

  local rescan_ok = (c.type == "combo" or c.type == "stepped") and c.param and c.param >= 0

  -- a locked layout takes no edits: say so, and offer only what isn't one
  if locked then
    ImGui.TextDisabled(ctx, "Layout locked (the padlock at the left of the panel's foot)")
    if rescan_ok then
      ImGui.SeparatorText(ctx, "Control")
      if ImGui.MenuItem(ctx, "Rescan choices") then P.rescan_choices(key, c.param) end
    end
    ImGui.SeparatorText(ctx, "Look")
    look_items(fx, key, layout, idx, c, true)
    automate_items(fx, c)
    container_items(fx, c)
    ImGui.Separator(ctx)
    if not cm.ed then plugin_sub(fx) end
    ImGui.EndPopup(ctx)
    return
  end

  local function commit()
    local l, k = materialise(fx)
    M.save()
    return l, k
  end
  local function flip(field)
    local l = commit()
    local lc = l.controls[idx]
    if lc then lc[field] = (not lc[field]) or nil end
    M.set(key, l); M.save()
  end

  ------------------------------------------------------------- CONTROL
  ImGui.SeparatorText(ctx, "Control")
  if ImGui.BeginMenu(ctx, "Show as") then
    for _, t in ipairs(TYPE_ORDER) do
      if ImGui.MenuItem(ctx, TYPE_LABELS[t], nil, c.type == t and not (t == "combo" and c.buttons)) then
        local l = commit()
        local lc = l.controls[idx]
        local was = lc.type
        lc.type = t
        lc.buttons, lc.nbtn = nil, nil
        if (t == "combo") ~= (was == "combo") then lc.invert = nil end
        -- a list of settings it doesn't report steps for: its count kept
        if (t == "combo" or t == "stepped") and c.param and not P.step_norm(app.track, fx.addr, c.param, key) then
          local dn = P.detect_steps(app.track, fx.addr, c.param, key)
          if dn then l.steps = l.steps or {}; l.steps[c.param] = dn end
        end
        -- sizes don't carry between an XY pad and anything else, and a
        -- concentric knob is never small
        if (t == "xy") ~= (was == "xy") or (t == "dual" and lc.size == "small") then lc.size = nil end
        -- two parameters: the second starts as the next one along
        if (t == "xy" or t == "dual") and not lc.param2 and lc.param then
          local n = reaper.TrackFX_GetNumParams(app.track, fx.addr)
          lc.param2 = (lc.param + 1 < n) and (lc.param + 1) or lc.param
        end
        M.set(key, l); M.save()
      end
      -- right after Dropdown: its choices as a row, or a column, of buttons
      if t == "combo" then
        local n, found
        local list = c.param and P.combo_steps(app.track, fx.addr, c.param, key)
        if type(list) == "table" then n = #list
        else
          local st = c.param and P.step_norm(app.track, fx.addr, c.param, key)
          n = st and (math.floor(1 / st + 0.5) + 1) or nil
          -- none reported: read off the plugin's text along its range
          if not n and c.param then n = P.detect_steps(app.track, fx.addr, c.param, key); found = n end
        end
        local ok = n and n >= 2 and n <= C.BUTTONS_MAX
        for _, d in ipairs({ { "across", "Buttons across" }, { "down", "Buttons down" }, { "grid", "Buttons grid" },
                             { "step", "Step button" } }) do
          if ImGui.MenuItem(ctx, d[2], nil, c.type == "combo" and c.buttons == d[1], ok and true or false) then
            local l = commit()
            local lc = l.controls[idx]
            if lc.type ~= "combo" then lc.invert = nil end
            lc.type, lc.buttons, lc.nbtn = "combo", d[1], n
            if found then l.steps = l.steps or {}; l.steps[c.param] = n end
            M.set(key, l); M.save()
          end
          if ImGui.IsItemHovered(ctx, ImGui.HoveredFlags_AllowWhenDisabled) then
            ImGui.SetTooltip(ctx, not ok and ("Needs 2 to %d choices (Values \u{25B8} Steps)."):format(C.BUTTONS_MAX)
              or d[1] == "step" and "One button: click for the next choice, Shift+click back."
              or ("One button per choice (%d)%s."):format(n, d[1] == "grid" and ", in rows" or ""))
          end
        end
        -- the gap between a row's, a column's or a grid's buttons
        if c.type == "combo" and c.buttons and c.buttons ~= "step" then
          ImGui.Indent(ctx, 10)
          if ImGui.BeginMenu(ctx, "Gap between buttons") then
            for _, g in ipairs({ 0, 2, 4, 6, 8 }) do
              if ImGui.MenuItem(ctx, g == 0 and "None" or (g .. " px"), nil, (c.bgap or 2) == g) then
                local l = commit()
                local lc = l.controls[idx]
                if lc then lc.bgap = (g ~= 2) and g or nil end
                M.set(key, l); M.save()
              end
            end
            ImGui.EndMenu(ctx)
          end
          ImGui.Unindent(ctx, 10)
        end
        -- a step button's lamps
        if c.type == "combo" and c.buttons == "step" then
          local function put(f, v)
            local l = commit()
            local lc = l.controls[idx]
            if lc then lc[f] = v end
            M.set(key, l); M.save()
          end
          ImGui.Indent(ctx, 10)
          for _, o in ipairs({ { nil, "LEDs beside" }, { "over", "LEDs over it" },
                               { "column", "LEDs in a column over it" }, { "none", "No LEDs" } }) do
            if ImGui.MenuItem(ctx, o[2] .. "##stepleds", nil, c.leds == o[1]) then put("leds", o[1]) end
          end
          if (c.leds == nil or c.leds == "column") and ImGui.MenuItem(ctx, "Their names", nil, c.ledn ~= false) then
            if c.ledn == false then put("ledn", nil) else put("ledn", false) end
          end
          if (c.leds == nil or c.leds == "column") and c.ledn ~= false and not c.litp
             and ImGui.MenuItem(ctx, "No button, just the list", nil, c.nobtn == true) then
            put("nobtn", (not c.nobtn) or nil)
          end
          if c.leds ~= "none" then
            ImGui.Separator(ctx)
            if ImGui.MenuItem(ctx, "Each its own LED", nil, not c.upto and not c.litp) then
              local l = commit()
              local lc = l.controls[idx]
              if lc then lc.upto, lc.litp = nil, nil end
              M.set(key, l); M.save()
            end
            if ImGui.MenuItem(ctx, "Light up to it", nil, c.upto == true and not c.litp) then
              local l = commit()
              local lc = l.controls[idx]
              if lc then lc.upto, lc.litp = true, nil end
              M.set(key, l); M.save()
            end
            if ImGui.MenuItem(ctx, "A pattern of LEDs", nil, c.litp == true) then
              local l = commit()
              local lc = l.controls[idx]
              if lc then
                lc.upto, lc.litp = nil, true
                -- none yet: guessed from the choices' names
                if not lc.pat then
                  local list = M.choice_list(key, c.param, P.button_choices(app.track, fx.addr, c.param, key, c.nbtn),
                                             app.track, fx.addr) or {}
                  local nm = {}
                  for i, e in ipairs(list) do nm[i] = e.text end
                  lc.pat = M.step_guess(nm)
                end
              end
              M.set(key, l); M.save()
            end
            if ImGui.IsItemHovered(ctx) then
              ImGui.SetTooltip(ctx, "Its own LEDs, each setting lighting any of them.\nSet them in Edit layout.")
            end
          end
          ImGui.Unindent(ctx, 10)
        end
      end
    end
    -- an XY pad's Y, a concentric knob's inner knob
    if M.has_second(c) then
      ImGui.Separator(ctx)
      if ImGui.BeginMenu(ctx, (c.type == "xy") and "Y parameter" or "Inner knob parameter") then
        second_param_menu(fx, key, idx, c)
        ImGui.EndMenu(ctx)
      end
    end
    if rescan_ok then
      ImGui.Separator(ctx)
      if ImGui.MenuItem(ctx, "Rescan choices") then P.rescan_choices(key, c.param) end
    end
    ImGui.EndMenu(ctx)
  end

  if ImGui.BeginMenu(ctx, "Name") then
    name_menu(fx, key, layout, idx, c)
    ImGui.EndMenu(ctx)
  end

  local has_values = (c.type == "knob" or c.type == "stepped" or c.type == "fader" or c.type == "dual"
                      or c.type == "combo" or c.type == nil) and c.param and c.param >= 0
  if has_values and ImGui.BeginMenu(ctx, "Values") then
    values_menu(fx, key, layout, idx, c)
    ImGui.EndMenu(ctx)
  end

  -- (a knob's is its Style > Value arc's Centred)
  if not M.has_second(c) and c.type ~= "toggle" and c.type ~= "combo"
     and c.type ~= "knob" and c.type ~= "stepped" and c.type ~= nil
     and ImGui.MenuItem(ctx, "Centred fill", nil, c.bipolar and true or false) then
    flip("bipolar")
  end
  -- reverse: knobs, buttons, and both halves of a two-parameter control
  -- (a dropdown's entries are positions in the plugin's own scale)
  local brow = c.type == "combo" and c.buttons and c.buttons ~= "step"
  if c.type == "knob" or c.type == "toggle" or c.type == "stepped" or c.type == nil or brow then
    if ImGui.MenuItem(ctx, "Reverse", nil, c.invert and true or false) then flip("invert") end
  elseif M.has_second(c) then
    local a, b = (c.type == "xy") and "X" or "ring", (c.type == "xy") and "Y" or "inner knob"
    if ImGui.MenuItem(ctx, "Reverse " .. a, nil, c.invert and true or false) then flip("invert") end
    if ImGui.MenuItem(ctx, "Reverse " .. b, nil, c.invert2 and true or false) then flip("invert2") end
  end
  if ImGui.IsItemHovered(ctx) and (c.type ~= "combo" and c.type ~= "fader") then
    ImGui.SetTooltip(ctx, "Flip the direction on screen only.")
  elseif brow and ImGui.IsItemHovered(ctx) then
    ImGui.SetTooltip(ctx, "Light every button but the current one.")
  end

  -- a lamp before its name, from the plugin's gain reduction (TS_CV_Panel
  -- P.lamp); one that isn't reported is measured by the probes
  local lamp_ok = (c.type == "knob" or c.type == "stepped" or c.type == nil) and c.param and c.param >= 0
  if lamp_ok and ImGui.BeginMenu(ctx, "Lamp") then
    for _, o in ipairs({ { false, "Automatic", "On the Threshold, without a canvas." },
                         { "gr", "Reduction", "Green with signal, amber reducing up to 6 dB,\nred past that. Compressors, limiters,\nclippers, saturators." },
                         { "gate", "Gate", "Green open, amber partly closed, red closed." },
                         { "off", "None", "No lamp on this plugin's controls\nbut those set here." } }) do
      if ImGui.MenuItem(ctx, o[2], nil, (c.lamp or false) == o[1]) then
        local l = commit()
        local lc = l.controls[idx]
        if lc then lc.lamp = o[1] or nil end
        local measure = o[1] and o[1] ~= "off" and not T.reports_gr(app.track, fx.addr, fx.guid)
        if measure then l.measure = true; M.set_meter(l, true) end
        M.set(key, l); M.save()
        if measure then
          TP.invalidate()
          if TP.status(app.track, fx.guid) == "no_probes" and reaper.MB("Its gain reduction is measured by a TS_TrackProbe\n" ..
              "pair, which this track doesn't have.\n\nAdd them now?", "ChannelView", 4) == 6 then
            local ok, why = TP.insert_probes(app.track)
            if not ok then reaper.MB(why, "ChannelView", 0) end
          end
        end
      end
      if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, o[3]) end
    end
    ImGui.EndMenu(ctx)
  end


  if ED.menu(ImGui, ctx, "Show when" .. (c.show and "  \u{25D0}" or "")) then
    show_when_menu(fx, key, layout, idx, c)
    ImGui.EndMenu(ctx)
  end

  ---------------------------------------------------------------- LOOK
  ImGui.SeparatorText(ctx, "Look")
  local styled = style_family(c.type) or c.type == "xy" or c.type == "dual" or c.type == "combo"
  if styled and ED.menu(ImGui, ctx, "Style") then
    style_menu(fx, key, idx, c)
    ImGui.EndMenu(ctx)
  end
  -- a dropdown's width: one to four cells (on a grid, its place's)
  if c.type == "combo" and not c.buttons then
    local on_grid = layout.grid ~= nil
    if ImGui.BeginMenu(ctx, "Width", not on_grid) then
      local now = M.combo_cells(c)
      for n = 1, 4 do
        if ImGui.MenuItem(ctx, n == 1 and "1 cell" or (n .. " cells"), nil, now == n) then
          local l = materialise(fx)
          local lc = l.controls[idx]
          if lc then lc.size = (n > 1) and tostring(n) or nil end
          M.set(key, l); M.save()
        end
      end
      ImGui.EndMenu(ctx)
    end
    if ImGui.IsItemHovered(ctx, ImGui.HoveredFlags_AllowWhenDisabled) then
      ImGui.SetTooltip(ctx, on_grid and "On a grid: the width of its place." or "Wide: arrows each side step it.")
    end
  end
  -- its own background, over its section's; neighbours with the same one
  -- join into one shape
  if c.type ~= "divider" and ED.menu(ImGui, ctx, "Background") then
    back_menu(fx, key, idx, c)
    ImGui.EndMenu(ctx)
  end
  -- the section this control is in belongs to the divider in front of it
  -- (dividers aren't on the panel to right-click, so it's offered here)
  -- (on a grid, the section rectangle it's on, the topmost)
  local div_idx
  if layout.grid and c.at then
    local mx, my = c.at.c + c.at.w / 2, c.at.r + c.at.h / 2
    for k = #layout.controls, 1, -1 do
      local o = layout.controls[k]
      local a = o.type == "section" and o.at
      if a and mx >= a.c and mx <= a.c + a.w and my >= a.r and my <= a.r + a.h then div_idx = k break end
    end
  else
    for k = idx - 1, 1, -1 do
      local o = layout.controls[k]
      if o.type == "divider" then div_idx = k break end
      if P.fader_kind(o) == "column" then break end
    end
  end
  if ED.menu(ImGui, ctx, "Section", div_idx ~= nil) then
    section_menu(fx, key, div_idx, layout.controls[div_idx])
    ImGui.EndMenu(ctx)
  end
  if ED.PRO and not div_idx and ImGui.IsItemHovered(ctx, ImGui.HoveredFlags_AllowWhenDisabled) then
    ImGui.SetTooltip(ctx, layout.grid and "Not on a section." or "Needs a divider first:\nArrange > Insert before > Divider.")
  end
  look_items(fx, key, layout, idx, c, false)

  ------------------------------------------------------------ AUTOMATE
  automate_items(fx, c)
  container_items(fx, c)

  ------------------------------------------------------------- ARRANGE
  ImGui.SeparatorText(ctx, "Arrange")
  -- (a grid's gaps are its empty space)
  if not layout.grid and ImGui.BeginMenu(ctx, "Insert before") then
    for _, g in ipairs({ { "blank", "Gap" }, { "half_gap", "Half gap" }, { "divider", "Divider" } }) do
      if ImGui.MenuItem(ctx, g[2]) then
        local l = commit()
        table.insert(l.controls, idx, { param = -1, type = g[1], bipolar = false, label = "" })
        M.set(key, l); M.save()
      end
    end
    ImGui.EndMenu(ctx)
  end
  if ImGui.MenuItem(ctx, "Remove from panel") then
    local l = commit()
    table.remove(l.controls, idx)
    M.set(key, l); M.save()
  end
  if not cm.ed then ImGui.Separator(ctx) end
  if not ED.PRO and ImGui.MenuItem(ctx, "Edit parameters\u{2026}") then
    E.open(app.track, fx, key, layout, idx)
  end
  if not cm.ed and ED.item(ImGui, ctx, "Edit layout\u{2026}") then
    require("TS_CV_GridEditor").open(app.track, fx, key, layout, idx,
      { rows = M.locked(layout) or (P.RACK and P.RACK_ROWS) or app.cv_rows or 2, index = cm.fx, cv_h = app.cv_h,
          rack_w = app.rack_w or tonumber(reaper.GetExtState(C.EXT_SECT, "rack_width")) })
  end
  if not cm.ed then plugin_sub(fx) end
  ImGui.EndPopup(ctx)
end

-- What a panel asked for this frame (P.draw's req): acted on the same way
-- wherever it was drawn -- the row, or the Rack view's column.
local function panel_requests(i, fx, layout, key, req)
    FRM.set(fx, req.form)
    if req.toggle_bypass then
      T.set_enabled(app.track, fx.addr, not T.get_enabled(app.track, fx.addr))
    end
    if req.toggle_float then
      T.toggle_float(app.track, fx.addr)
    end
    if req.toggle_pin then AF.toggle_pin(fx.guid) end
    if req.toggle_collapse then
      toggle_fold(fx)
    end
    if req.remove then app.remove_ask = fx end
    if req.begin_drag and not app.drag then
      app.drag = { chain_i = i, guid = fx.guid, path = fx.path_t,
                   what = fx.is_container and "container" or "plugin" }
      -- (the track row outlines another track it's over: copied there)
      MX.fx_drag = { track = app.track, name = U.fx_label(fx) }
    end
    if req.open_menu then
      app.menu_fx = i
      app.open_panel_menu = true
    end
    if req.open_editor and not M.locked(layout) then
      E.open(app.track, fx, key, layout)
    end
    -- (a number: an EQ curve's own bands, that control's)
    if req.canvas_setup then
      local n = math.type(req.canvas_setup) and req.canvas_setup or nil
      CS.open(app.track, fx, key, n, n and req.form)
    end
    -- a modulator's link dropped on a control: linked, after asking
    -- when that replaces another modulator
    if req.mod_drop then
      local d = req.mod_drop
      link_source(d.mod, d.k or 1, d.path, d.param, d.label, d.was, d.centre)
    end
    -- the padlock: lock at the rows the panel has now, or unlock
    if req.toggle_lock ~= nil then
      if E.is_open() and E.key() == key then
        reaper.MB("Close Edit parameters for " .. key .. " first: saving it would\n" ..
                  "undo the lock.", "ChannelView", 0)
      else
        local l = materialise(fx)
        l.lock = req.toggle_lock or nil
        M.set(key, l); M.save()
      end
    end
    if req.vu_src then
      -- a VU meter's switch: In, Out or GR
      app.vu_set(fx, req.vu_src.idx, { src = req.vu_src.src })
    end
    if req.page_cap then
      -- a page tab's colour, from its right-click picker: previewed as
      -- you hover (not saved to disk until you pick)
      local l = materialise(fx)
      local c = l.controls and l.controls[req.page_cap.idx]
      if c and c.type == "page" then
        c.cap = req.page_cap.cap
        M.set(key, l)
        if req.page_cap.save then M.save() end
      end
    end
    if req.grv_window then
      local l = materialise(fx)
      if l.meter then
        l.meter.win = (req.grv_window ~= C.GRV_DEFAULT) and req.grv_window or nil
      elseif P.own_rc(key) then
        -- ReaComp's canvas keeps its history's window in the same
        -- place, with no meter of its own (the canvas has the meters)
        l.meter = { on = false, win = (req.grv_window ~= require("TS_CV_CompPanel").WINDOW_DEFAULT) and req.grv_window or nil }
      end
      M.set(key, l); M.save()
    end
    if req.ctx_control then
      app.ctl_menu = { fx = i, ctl = req.ctx_control, form = req.form }
      local c = (layout_for(fx).controls or {})[req.ctx_control]
      local pn = ""
      if c and c.param then
        pn = select(2, reaper.TrackFX_GetParamName(app.track, fx.addr, c.param, ""))
      end
      -- starts as the name the control shows now
      app.rename_buf = c and c.param
        and M.display_name(key, c.param, nil, pn, false) or pn or ""
      app.label_buf = c and c.label or ""
      app.rng_for = nil
      local st = c and c.param and M.get_states(key, c.param)
      local bt = c and c.param and M.get_btext(key, c.param)
      app.state_buf = { st and st[1] or "", st and st[2] or "", bt and bt[1] or "", bt and bt[2] or "" }
      app.choice_buf = {}
      app.choice_ctx = nil
      for t, nm in pairs(c and c.param and M.get_choice_names(key, c.param, app.track, fx.addr) or {}) do app.choice_buf[t] = nm end
      app.fold_buf = {}
      for t, f in pairs(c and c.param and M.get_choice_folders(key, c.param) or {}) do app.fold_buf[t] = f end
      app.open_ctl_menu = true
    end
    FRM.on = nil
end

-- The bracket strip: one bracket per FX container and per run of plugins
-- in parallel, over the panels they hold, drawn after the panels so the
-- rectangles are known. A container's square opens its menu.
local function bracket_tip(b)
  if b.kind == "container" then
    local n = b.node
    local inside = #(n.children or {})
    local t = ("Container: %s \u{2014} %d %s"):format(box_label(n), inside,
      inside == 1 and "slot" or "slots")
    if CT.folded(n.guid) and CT.shown[n.guid] then t = t .. "\nFolded to its panel" end
    if not T.get_enabled(app.track, n.addr) then t = t .. "\nBypassed" end
    if n.parallel ~= 0 then t = t .. "\nIn parallel with previous" end
    local st = T.os_state(app.track, { addr = n.addr, ancestors = box_ancestors(n) })
    if st.lit then t = t .. ("\nOversampled %dx (%s)"):format(st.lit, T.os_label(st.n, st.rate):lower()) end
    return t .. "\nClick: menu"
  end
  local lines = { "In parallel:" }
  for k, m in ipairs(b.members) do
    local nm = m.kind == "container" and ("container " .. box_label(m)) or (m.alias or U.fx_label(m))
    if k > 1 and m.parallel == 2 then nm = nm .. "  (MIDI merged)" end
    lines[#lines + 1] = "  \u{2022} " .. nm
  end
  lines[#lines + 1] = "Outputs summed. Change: right-click a panel \u{25B8} Route"
  return table.concat(lines, "\n")
end

-- Each bracket's line is on its row of the strip (the outermost at the
-- top, T.groups), and its ends come down to its first and last panels.
-- Panels only drop as far as the brackets over them need, so a group one
-- row deep sits higher than one two rows deep -- inside one container too.
local function draw_brackets()
  if app.brk_rows == 0 or not app.track then return end
  local dl = ImGui.GetWindowDrawList(ctx)
  local rect = {}
  for _, r in ipairs(app.panel_rects) do rect[r.chain_i] = r end
  for _, b in ipairs(app.brackets) do
    local ra, rb = rect[b.first], rect[b.last]
    -- a compare's container: its bar instead of a bracket (TS_CV_Compare)
    if ra and rb and POP.CMP and b.kind == "container" and POP.CMP.is_container(app.track, b.node.guid) then
      POP.CMP.draw_bar(ctx, app.track, math.floor(ra.x), math.floor(rb.x + rb.w),
        math.floor((app.brk_top or ra.y) + b.row * C.BRK_ROW_H))
      ra = nil
    end
    if ra and rb then
      local box = b.kind == "container"
      local col = box and C.COL.brk_container or C.COL.brk_parallel
      local off = box and not T.get_enabled(app.track, b.node.addr)
      if off then col = U.with_alpha(col, 0x80) end
      local x1, x2 = math.floor(ra.x + 3) + 0.5, math.floor(rb.x + rb.w - 3) + 0.5
      -- its line on its row, counted from the top of the strip; each end
      -- comes down to the top of its own panel, which drops only as far
      -- as the brackets over that panel need
      local ly = math.floor((app.brk_top or ra.y) + (b.row + 0.5) * C.BRK_ROW_H) + 0.5
      local sq = 7
      local label = box and box_label(b.node) or nil
      -- folded to its panel: says so, and how much it stands for
      if label and CT.shown[b.node.guid] and CT.folded(b.node.guid) then
        label = label .. "  \u{25B8} " .. #(b.node.children or {})
      end
      local tw, th = 0, 0
      if label then
        tw, th = ImGui.CalcTextSize(ctx, label)
        if tw + sq + 4 + 30 > x2 - x1 then label, tw = nil, 0 end
      end
      -- oversampled: the factor, lit, after the name
      local os_lit = box and T.os_state(app.track, { addr = b.node.addr, ancestors = box_ancestors(b.node) }).lit or nil
      local os_n = os_lit and 1 or 0
      local ow = 0
      if os_lit then
        ow = W.os_width(ctx, os_lit)
        if (label and tw or 0) + sq + 4 + ow + 4 + 30 > x2 - x1 then label, tw = nil, 0 end
      end
      local mw = box and (sq + (label and (4 + tw) or 0) + (os_n > 0 and (4 + ow) or 0)) or 6
      local mid = math.floor((x1 + x2) * 0.5)
      local m1, m2 = mid - mw * 0.5 - 3, mid + mw * 0.5 + 3
      ImGui.DrawList_AddLine(dl, x1, ra.y - 1, x1, ly, col, 1.5)
      ImGui.DrawList_AddLine(dl, x1, ly, m1, ly, col, 1.5)
      ImGui.DrawList_AddLine(dl, m2, ly, x2, ly, col, 1.5)
      ImGui.DrawList_AddLine(dl, x2, ly, x2, rb.y - 1, col, 1.5)
      if box then
        local sx = mid - mw * 0.5
        if off then
          ImGui.DrawList_AddRect(dl, sx + 0.5, ly - 3, sx + sq - 0.5, ly + 3, col, 0, 0, 1.0)
        else
          ImGui.DrawList_AddRectFilled(dl, sx, ly - 3.5, sx + sq, ly + 3.5, col)
        end
        if label then
          ImGui.DrawList_AddText(dl, sx + sq + 4, ly - th * 0.5, col, label)
        end
        if os_n > 0 then
          local ox = sx + sq + 4 + (label and (tw + 4) or 0)
          local bh = C.BRK_ROW_H - C.S(1)
          ImGui.DrawList_AddRectFilled(dl, ox, ly - bh * 0.5, ox + ow, ly + bh * 0.5, col, 2.0)
          W.push_small(ctx)
          local ot = ("%dx"):format(os_lit)
          local otw, oth = ImGui.CalcTextSize(ctx, ot)
          ImGui.DrawList_AddText(dl, ox + (ow - otw) * 0.5, ly - oth * 0.5, C.COL.panel_bg, ot)
          W.pop_small(ctx)
        end
      else
        ImGui.DrawList_AddLine(dl, mid - 2, ly - 4, mid - 2, ly + 4, col, 1.5)
        ImGui.DrawList_AddLine(dl, mid + 2, ly - 4, mid + 2, ly + 4, col, 1.5)
      end
      local id = ("brk%s%d_%d_%d"):format(b.kind:sub(1, 1), b.first, b.last, b.row)
      ImGui.SetCursorScreenPos(ctx, m1, ly - C.BRK_ROW_H * 0.5)
      ImGui.InvisibleButton(ctx, id, math.max(1, m2 - m1), C.BRK_ROW_H,
        ImGui.ButtonFlags_MouseButtonLeft | ImGui.ButtonFlags_MouseButtonRight)
      local hov = ImGui.IsItemHovered(ctx)
      W.tip(ctx, id, bracket_tip(b), hov, false)
      if box and (ImGui.IsItemClicked(ctx, ImGui.MouseButton_Left)
                  or ImGui.IsItemClicked(ctx, ImGui.MouseButton_Right)) then
        app.box_for, app.open_box_menu = b.node, true
      end
    end
  end
  -- (no putting the cursor back: a SetCursorScreenPos with no item after
  -- it would trip ImGui's check on the child's bounds at EndChild)
end

-- The probes button. The selected tracks that have no TS_TrackProbe pair
-- (or just this one, if it isn't selected) get one, after a yes/no:
-- inserting rebuilds the FX chain, so it never happens on a stray click.
-- It only ever adds. Returns true when anything was added.
local PROBES_ABOUT =
  "A TS_TrackProbe at the start of the FX chain and another at the end.\n" ..
  "They measure gain reduction for plugins that don't report it (tick\n" ..
  "\"Measure gain reduction\" on the plugin), and they're what Track\n" ..
  "Analyser reads. They don't change the audio, and sit idle until\n" ..
  "something reads them."

local function confirm_probes()
  local list, need = {}, {}
  local tr_sel = false
  for i = 0, reaper.CountSelectedTracks(0) - 1 do
    local t = reaper.GetSelectedTrack(0, i)
    list[#list + 1] = t
    if t == app.track then tr_sel = true end
  end
  if not tr_sel then list = { app.track } end
  for _, t in ipairs(list) do
    if t ~= reaper.GetMasterTrack(0) and not TP.has_probes(t) then need[#need + 1] = t end
  end
  if #need == 0 then
    reaper.MB((#list > 1 and "These tracks already have their probes.\n\n"
                         or "This track already has its probes.\n\n") .. PROBES_ABOUT,
              "ChannelView", 0)
    return false
  end
  local what = (#need > 1)
    and ("Add probes to %d selected tracks?"):format(#need)
     or "Add probes to this track?"
  if reaper.MB(what .. "\n\n" .. PROBES_ABOUT .. "\n\nIt only ever adds: nothing is removed, " ..
               "reordered or replaced.", "ChannelView", 4) ~= 6 then
    return false
  end
  reaper.Undo_BeginBlock()
  local failed
  for _, t in ipairs(need) do
    local ok, why = TP.insert_probes(t)
    if not ok then failed = why break end
  end
  reaper.Undo_EndBlock("ChannelView: add TS_TrackProbe pairs", -1)
  TP.invalidate()
  if failed then reaper.MB(failed, "ChannelView", 0) end
  return true
end

-- The probes' menu, from the header's probe button.
local function probes_menu(state, vis)
  if not ImGui.BeginPopup(ctx, "probesmenu") then return end
  ImGui.TextDisabled(ctx, state == "pair" and "TS_TrackProbe pair in place"
                          or (state == "pre" and "The post probe is missing"
                          or "The pre probe is missing"))
  ImGui.Separator(ctx)
  if state ~= "pair" then
    if ImGui.MenuItem(ctx, "Add the missing probe") then
      local ok, why = TP.insert_probes(app.track)
      if not ok then reaper.MB(why, "ChannelView", 0) end
      rescan(true)
    end
  else
    ImGui.TextDisabled(ctx, "In the Visualizer's spectrum")
    local function opt(label, which, note)
      if ImGui.MenuItem(ctx, "   " .. label .. "##vis" .. tostring(which), note, vis == which) then
        TP.set_vis(app.track, which)
        TP.invalidate()
      end
    end
    opt("Not included", nil)
    opt("Before the chain", "pre", "pre probe")
    opt("After the chain", "post", "post probe")
  end
  ImGui.Separator(ctx)
  if ImGui.MenuItem(ctx, "Remove the probes\u{2026}") then
    local n = 0
    for _, fx in ipairs(app.chain) do
      local l = M.get(St.layout_key(fx.name, fx.guid, app.track, fx.addr))
      if l and (l.measure or l.levels) then n = n + 1 end
    end
    local q = "Take the TS_TrackProbe pair off this track?"
    if n > 0 then
      q = q .. ("\n\n%d plugin%s here %s measured by them: %s meter%s go%s until probes are added again.")
            :format(n, n == 1 and "" or "s", n == 1 and "is" or "are", n == 1 and "its" or "their",
                    n == 1 and "" or "s", n == 1 and "es" or "")
    end
    if reaper.MB(q, "ChannelView", 4) == 6 then
      TP.remove_probes(app.track)
      require("TS_CV_Upkeep").forget(app.track)
      rescan(true)
    end
  end
  ImGui.EndPopup(ctx)
end

-- The Trimmer's button (the header's; the overview's glyph): with none on
-- the track, a click puts one first in the chain (after an ARA plugin,
-- the pre probe and the modulators); with one, its menu (trimmer_menu,
-- drawn after the button, in the same window).
local function trimmer_click()
  if not (TRM and app.track) then return end
  if TRM.find(app.track) then
    ImGui.OpenPopup(ctx, "trimmermenu")
    return
  end
  reaper.Undo_BeginBlock()
  local idx = TRM.insert(app.track, TP.ara_first(app.track))
  reaper.Undo_EndBlock("ChannelView: add Trimmer", -1)
  if idx then
    rescan(true)
  else
    reaper.MB("ChannelView couldn't find its TS_CV Trimmer plugin\n" ..
              "(TS_CV_Trimmer.jsfx). Reinstalling ChannelView from ReaPack puts it back.",
              "ChannelView", 0)
  end
end
local function trimmer_menu()
  if not (TRM and app.track) then return end
  if ImGui.BeginPopup(ctx, "trimmermenu") then
    local idx = TRM.find(app.track)
    if idx then
      if ImGui.MenuItem(ctx, "Auto trim from the items") then
        reaper.Undo_BeginBlock()
        local t, why = TRM.auto_trim(app.track, function(msg)
          return reaper.MB(msg, "Auto trim", 4) == 6
        end, TP.ara_first(app.track))
        reaper.Undo_EndBlock("ChannelView: auto trim", -1)
        if not t and why ~= "cancelled" then reaper.MB("Auto trim: " .. why .. ".", "ChannelView", 0) end
      end
      ImGui.Separator(ctx)
      if ImGui.MenuItem(ctx, "Remove the Trimmer") then
        reaper.Undo_BeginBlock()
        reaper.TrackFX_Delete(app.track, idx)
        reaper.Undo_EndBlock("ChannelView: remove Trimmer", -1)
        rescan(true)
      end
    end
    ImGui.EndPopup(ctx)
  end
end

return {
  panel_menu = panel_menu, box_menu = box_menu,
  -- (a form's control: its form only while its menu draws)
  control_menu = function() control_menu(); FRM.on = nil end,
  box_label = box_label, box_ancestors = box_ancestors, link_source = link_source,
  panel_requests = panel_requests, bracket_tip = bracket_tip, draw_brackets = draw_brackets,
  confirm_probes = confirm_probes, probes_menu = probes_menu,
  trimmer_click = trimmer_click, trimmer_menu = trimmer_menu,
}
end

return MN
