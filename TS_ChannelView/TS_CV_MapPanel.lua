-- @noindex
-- Not a package of its own: installed by TS_ChannelView.lua's @provides.
--[[
  TS_CV_MapPanel.lua -- the EQ canvas for any plugin: an EQ layout's bands
  (TS_CV_Mappings Band<k>), drawn from what was learned about them
  (TS_CV_MapEQ) and dragged through the plugin's own controls.

  Until every band is learned for its mapping as it is now, the canvas
  is a "Set up this layout" button instead (req.canvas_setup).

  Drag a node: across moves the band's frequency control (a switch snaps
  to its positions), up and down its gain. The wheel over a node turns
  its Q control, Alt+wheel steps its shape switch. Right-click a node for
  the band's shapes, its On switch and the setup. The nodes say what the plugin's own controls read.
--]]

local C  = require("TS_CV_Config")
local U  = require("TS_CV_Util")
local W  = require("TS_CV_Widgets")
local M  = require("TS_CV_Mappings")
local ME = require("TS_CV_MapEQ")
local UN = require("TS_CV_Units")
local EQP = require("TS_CV_EQPanel")

local MP = {}
local ImGui

function MP.attach(imgui) ImGui = imgui end

local state = {}
local function panel_state(guid)
  local s = state[guid]
  if not s then s = {}; state[guid] = s end
  return s
end

local function ftext(track, addr, p)
  if not p then return nil end
  local _, t = reaper.TrackFX_GetFormattedParamValue(track, addr, p, "")
  return U.trim(t or "")
end

-- The canvas's width for a layout's canvas kind.
function MP.width(kind)
  return (kind == "comp") and C.MAP_COMP_W or C.MAP_EQ_W
end

-- The placeholder for a layout that isn't ready.
function MP.draw_setup(ctx, dl, x, y, w, h, fx, cv, req)
  local pad = C.PANEL_PAD
  ImGui.DrawList_AddRectFilled(dl, x + pad, y + pad, x + w - pad, y + h - pad, 0x00000030, 3.0)
  local todo = M.canvas_todo(cv)
  local line1 = (cv.kind == "comp") and "This compressor layout has no roles yet."
                or "This EQ layout isn't learned yet."
  local tw = ImGui.CalcTextSize(ctx, line1)
  local cy = y + h * 0.5 - 30
  ImGui.DrawList_AddText(dl, x + (w - tw) * 0.5, cy, C.COL.header_dim, line1)
  local bw, bh = 150, 22
  ImGui.SetCursorScreenPos(ctx, x + (w - bw) * 0.5, cy + 22)
  if ImGui.Button(ctx, "Set up this layout\u{2026}##mpset" .. fx.guid, bw, bh) then
    req.canvas_setup = true
  end
  if todo and todo.total > 0 then
    local t2 = ("%d of %d bands learned"):format(todo.learned, todo.total)
    local w2 = ImGui.CalcTextSize(ctx, t2)
    W.push_small(ctx)
    ImGui.DrawList_AddText(dl, x + (w - w2) * 0.5, cy + 52, C.COL.header_dim, t2)
    W.pop_small(ctx)
  end
end

-- ---------------------------------------------------------------------
-- the EQ canvas
-- ---------------------------------------------------------------------
function MP.draw_eq(ctx, dl, x, y, w, h, track, fx, layout, req)
  local cv = layout.canvas
  if M.canvas_todo(cv) then return MP.draw_setup(ctx, dl, x, y, w, h, fx, cv, req) end
  local u = EQP.util
  local addr = fx.addr
  local ps = panel_state(fx.guid)
  local pad = C.PANEL_PAD
  local gx0, gy0 = x + pad, y + pad
  local gw, gh = w - pad * 2, h - pad * 2
  if gw < 20 or gh < 20 then return end

  local bands = {}
  for k, b in ipairs(cv.bands) do
    local rb = ME.read_band(track, addr, b, cv.all_on)
    if rb then rb.k, rb.map = k, b; bands[#bands + 1] = rb end
  end

  ImGui.DrawList_PushClipRect(dl, gx0, gy0, gx0 + gw, gy0 + gh, true)
  u.draw_spectrum(dl, gx0, gy0, gw, gh)
  u.draw_grid(ctx, dl, gx0, gy0, gw, gh)

  local n = C.EQ_CURVE_SEGS
  local xs = u.sample_xs(gx0, gw, n)
  local y0db = u.y_of(0, gy0, gh)
  local fr = {}
  for i = 1, n do fr[i] = u.freq_of_x(xs[i], gx0, gw) end
  local lim = C.EQ_GAIN_RANGE * 1.5
  local total = {}
  for i = 1, n do total[i] = 0 end
  for _, b in ipairs(bands) do
    if b.on then
      local col = u.band_colour(b.k)
      local ys = {}
      for i = 1, n do
        local db = ME.band_db(b, fr[i])
        total[i] = total[i] + db
        ys[i] = u.y_of(math.max(-lim, math.min(lim, db)), gy0, gh)
      end
      for i = 1, n - 1 do u.fill_to_zero(dl, xs[i], xs[i + 1], ys[i], y0db, col, 0x38) end
      u.polyline(dl, xs, ys, n, U.with_alpha(col, 0xb0), 1.1)
    end
  end
  local ty = {}
  for i = 1, n do ty[i] = u.y_of(math.max(-lim, math.min(lim, total[i])), gy0, gh) end
  u.polyline(dl, xs, ty, n, C.COL.eq_curve, 2.0)

  -- the selected (hovered or dragged) band's switch positions along the foot
  local sel = ps.sel
  if sel then
    local b = cv.bands[sel]
    local L = b and ME.decode(b.learn)
    local rb
    for _, v in ipairs(bands) do if v.k == sel then rb = v end end
    if L and L.S and rb then
      local e = L.shapes[rb.s] or L.shapes[1]
      for _, pn in ipairs(L.S) do
        local f
        if L.D then
          local fmt = UN.formatter(track, addr, b.freq)
          f = UN.at(fmt, pn); if f and e and e.K then f = f * (e.K[1] or 1) end
        elseif e and #e.F > 0 then f = UN.interp(e.F, pn, true) end
        if f and f > 0 then
          local tx = u.x_of(f, gx0, gw)
          ImGui.DrawList_AddLine(dl, tx, gy0 + gh - 6, tx, gy0 + gh, u.band_colour(sel), 2.0)
        end
      end
    end
  end

  W.push_small(ctx)
  ImGui.DrawList_AddText(dl, gx0 + 4, gy0 + gh - 26, U.with_alpha(C.COL.accent, 0xc0), "learned")
  W.pop_small(ctx)
  ImGui.DrawList_PopClipRect(dl)

  -- nodes
  local hot
  for _, b in ipairs(bands) do
    local col = u.band_colour(b.k)
    local has_gain = b.map.gain ~= nil and (b.type == "bell" or b.type == "ls" or b.type == "hs")
    local node_db = has_gain and math.max(-C.EQ_GAIN_RANGE, math.min(C.EQ_GAIN_RANGE, b.g or 0)) or 0
    local nx = math.max(gx0, math.min(gx0 + gw, u.x_of(b.f, gx0, gw)))
    local ny = u.y_of(node_db, gy0, gh)
    local id = ("mpn##%s:%d"):format(fx.guid, b.k)
    local r = C.EQ_NODE_R + 3
    W.allow_overlap(ctx)
    ImGui.SetCursorScreenPos(ctx, nx - r, ny - r)
    ImGui.InvisibleButton(ctx, id, r * 2, r * 2,
      ImGui.ButtonFlags_MouseButtonLeft | ImGui.ButtonFlags_MouseButtonRight)
    local hovered = ImGui.IsItemHovered(ctx)
    local active = ImGui.IsItemActive(ctx)
    if hovered or active then hot = b.k end
    if hovered and ImGui.IsMouseDoubleClicked(ctx, ImGui.MouseButton_Left) then
      -- double-click: the band out of the sound (flat, or off)
      ME.reset(track, addr, b.map)
      ps.drag, ps.dblk = nil, b.k
    elseif active and ps.dblk == b.k then
      -- the rest of that double-click's press moves nothing
    elseif active and ImGui.IsMouseDown(ctx, ImGui.MouseButton_Left) then
      local d = ps.drag
      if not d or d.k ~= b.k then
        local mx, my = ImGui.GetMousePos(ctx)
        d = { k = b.k, f = b.f, g = b.g or 0, mx = mx, my = my }
        ps.drag = d
      end
      local mx, my = ImGui.GetMousePos(ctx)
      local fine = (ImGui.GetKeyMods(ctx) & ImGui.Mod_Shift) ~= 0 and 0.25 or 1
      local dx, dy = (mx - d.mx) * fine, (my - d.my) * fine
      if b.map.freq and math.abs(dx) > 0.5 then
        local tf = d.f * (C.EQ_FREQ_HI / C.EQ_FREQ_LO) ^ (dx / gw)
        ME.set_freq(track, addr, b.map, tf)
      end
      if has_gain and math.abs(dy) > 0.5 then
        local tg = d.g - dy / gh * (C.EQ_GAIN_RANGE * 2)
        ME.set_gain(track, addr, b.map, tg)
      end
      ImGui.SetMouseCursor(ctx, ImGui.MouseCursor_ResizeAll)
    elseif ps.drag and ps.drag.k == b.k and not active then
      ps.drag = nil
    elseif hovered then
      local wheel = W.control_wheel(ctx)
      local alt = (ImGui.GetKeyMods(ctx) & ImGui.Mod_Alt) ~= 0
      if wheel ~= 0 and alt and b.map.shape then
        -- Alt+wheel: the next or previous shape
        local shs = ME.shapes(track, addr, b.map)
        if shs then
          local to = math.max(1, math.min(#shs, b.s + (wheel > 0 and 1 or -1)))
          if to ~= b.s then ME.set_shape(track, addr, b.map, to) end
        end
        W.take_wheel()
      elseif wheel ~= 0 and b.map.q then
        local fine = (ImGui.GetKeyMods(ctx) & ImGui.Mod_Shift) ~= 0 and 0.25 or 1
        ME.nudge_q(track, addr, b.map, wheel * 0.02 * fine)
        W.take_wheel()
      end
    end
    if ImGui.IsItemClicked(ctx, ImGui.MouseButton_Right) then
      ps.menu = b.k
      ImGui.OpenPopup(ctx, "mpctx##" .. fx.guid)
    end
    if hovered or active then
      local name = (b.map.name ~= "" and b.map.name) or ("Band " .. b.k)
      local parts = {}
      for _, f in ipairs({ "freq", "gain", "q" }) do
        local t = ftext(track, addr, b.map[f])
        if t and t ~= "" then parts[#parts + 1] = t end
      end
      local tip = ("%s  (%s)\n%s"):format(name, ME.TYPES[b.type] or b.type,
        table.concat(parts, "   "))
      if b.map.q then tip = tip .. "\nWheel: Q" end
      if b.map.shape then tip = tip .. "\nAlt+wheel or right-click: shape" end
      tip = tip .. "\nDouble-click: " .. (b.map.gain and "flat" or "off")
      W.tip(ctx, id, tip, hovered, active)
    end
    local ring = (hovered or active) and C.COL.header_text or col
    local fill = b.on and col or U.with_alpha(col, 0x50)
    ImGui.DrawList_AddCircleFilled(dl, nx, ny, C.EQ_NODE_R, fill)
    ImGui.DrawList_AddCircle(dl, nx, ny, C.EQ_NODE_R, ring, 0, 1.5)
  end
  if hot then ps.sel = hot elseif not ps.drag then ps.sel = nil end
  if ps.dblk and not ImGui.IsMouseDown(ctx, ImGui.MouseButton_Left) then ps.dblk = nil end

  -- right-click menu
  local pop = "mpctx##" .. fx.guid
  if ImGui.BeginPopup(ctx, pop) then
    local b = cv.bands[ps.menu or 0]
    if b then
      local rb
      for _, v in ipairs(bands) do if v.k == ps.menu then rb = v end end
      ImGui.TextDisabled(ctx, ((b.name ~= "" and b.name) or ("Band " .. ps.menu))
        .. (rb and ("  \u{00B7} " .. (ME.TYPES[rb.type] or rb.type)) or ""))
      -- the band's shape switch, setting by setting
      local shs = rb and ME.shapes(track, addr, b)
      if shs then
        for _, sh in ipairs(shs) do
          if ImGui.MenuItem(ctx, ME.shape_label(sh) .. "##shp" .. sh.s, nil, rb.s == sh.s) then
            ME.set_shape(track, addr, b, sh.s)
          end
        end
        ImGui.Separator(ctx)
      end
      if b.on then
        local on = ME.switch_on(track, addr, b.on)
        if ImGui.MenuItem(ctx, "On", nil, on) then
          local cur = reaper.TrackFX_GetParamNormalized(track, addr, b.on)
          reaper.TrackFX_SetParamNormalized(track, addr, b.on, cur >= 0.5 and 0 or 1)
        end
      end
      ImGui.Separator(ctx)
    end
    if ImGui.MenuItem(ctx, "Set up this layout\u{2026}") then req.canvas_setup = true end
    ImGui.EndPopup(ctx)
  end
end

return MP
