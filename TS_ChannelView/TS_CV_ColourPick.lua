-- @noindex
-- Not a package of its own: installed by TS_ChannelView.lua's @provides.
--[[
  TS_CV_ColourPick.lua -- the colour picker, shared by every colour dialog:
  the track colour dialog (TS_CV_TrackMenu, in ChannelView and the TCP
  window alike) and the custom faceplate / background / section colour
  dialog here.

  Its parts:

    * the palettes -- any of REAPER's (built-in, user, the project's own
      colours) and the old custom colours, chosen from a list, one click
      on a swatch taking that colour;
    * "any colour" -- ImGui's picker, with an EYEDROPPER beside it that
      takes the colour of any pixel on any screen, inside REAPER or out;
    * the recent colours: every custom colour given to a faceplate, a
      background or a section since ChannelView started (not saved --
      they're for going back and forth between a few while you try them).

  The eyedropper needs the js_ReaScriptAPI extension: it copies the pixel
  under the pointer off the screen into a one-pixel bitmap of its own
  (JS_GDI_Blit from the screen's DC to the bitmap's) and reads it there
  (JS_LICE_GetPixel) -- the extension has no way to read the screen's
  pixel directly -- and JS_Mouse_GetState sees a click wherever it lands;
  without it the button simply isn't there. While it's on, the colour
  under the pointer shows in a tag beside it; a click takes it -- outside
  REAPER the click also lands on whatever is under it, so Enter takes it
  too, without clicking -- and Esc or a right-click puts it away.

  The screen hands back its pixels in one byte order or the other
  depending on the platform and the extension's version, so the first
  time the eyedropper is used it reads the dialog's own colour swatch --
  a colour it knows -- to see which, and remembers.
--]]

local C  = require("TS_CV_Config")
local TO = require("TS_CV_TrackOps")
local W  = require("TS_CV_Widgets")

local CP = {}
local ImGui

-- Menus that stay open while you click through them (the flag was
-- renamed in ReaImGui 0.10; either name, or none).
CP.KEEP_OPEN = 0
function CP.attach(imgui)
  ImGui = imgui
  for _, n in ipairs({ "SelectableFlags_NoAutoClosePopups", "SelectableFlags_DontClosePopups" }) do
    local ok, v = pcall(function() return ImGui[n] end)
    if ok and type(v) == "number" then CP.KEEP_OPEN = v break end
  end
end

local NS = "TS_ChannelView"

CP.SWATCH   = 20     -- palette swatch size
CP.PAL_COLS = 8      -- swatches to a row
CP.PAL_ROWS = 6      -- rows shown before the swatches scroll
local PAL_KEY   = "colour_palette"     -- ExtState: the palette last chosen
local ORDER_KEY = "dropper_order"      -- ExtState: "rgb" or "bgr", once known
local RECENT_MAX = 16

local function rgba(rgb) return ((rgb & 0xffffff) << 8) | 0xff end
local function tip(ctx, text)
  if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, text) end
end

function CP.width() return CP.PAL_COLS * (CP.SWATCH + 4) + 60 end

-- The state one dialog keeps while it's open: the colour being made, and
-- which palette is showing.
function CP.new_state(rgb)
  return { rgb = (rgb or 0x808080) & 0xffffff }
end

-- ---------------------------------------------------------------------
-- palettes
-- ---------------------------------------------------------------------

-- Which palette to open on: the one last chosen here, else the one
-- REAPER's picker last showed, else the first with any colours in it.
local function pick_palette(pals)
  local function find(name)
    if not name or name == "" then return nil end
    for i, p in ipairs(pals) do
      if p.name == name and #p.colours > 0 then return i end
    end
  end
  local i = find(reaper.GetExtState(NS, PAL_KEY)) or find(TO.picker_palette())
  if i then return i end
  for k, p in ipairs(pals) do if #p.colours > 0 then return k end end
  return 1
end

-- The palette list and its swatches. Returns the 0xRRGGBB of a swatch
-- clicked, or nil.
function CP.palette(ctx, s, id)
  if not s.pals then
    s.pals = TO.palettes()                 -- read afresh each time a dialog opens
    s.pal  = pick_palette(s.pals)
  end
  local pals, width = s.pals, CP.width()
  local cur = pals[s.pal]
  ImGui.SetNextItemWidth(ctx, width)
  if ImGui.BeginCombo(ctx, "##pal" .. id, cur and cur.name or "") then
    for i, p in ipairs(pals) do
      if ImGui.Selectable(ctx, ("%s  (%d)##pal%s%d"):format(p.name, #p.colours, id, i), i == s.pal) then
        s.pal = i
        reaper.SetExtState(NS, PAL_KEY, p.name, true)
      end
    end
    ImGui.EndCombo(ctx)
  end
  cur = pals[s.pal]
  local sw = cur and cur.colours or {}
  local picked
  if #sw == 0 then
    ImGui.TextDisabled(ctx, (cur and cur.name == TO.PROJECT_PALETTE)
      and "No colours used in this project yet." or "This palette is empty.")
  else
    local rows = math.ceil(#sw / CP.PAL_COLS)
    local h = math.min(rows, CP.PAL_ROWS) * (CP.SWATCH + 4)
    if ImGui.BeginChild(ctx, "##palsw" .. id, width, h, 0) then
      for i, c in ipairs(sw) do
        if (i - 1) % CP.PAL_COLS ~= 0 then ImGui.SameLine(ctx, 0, 4) end
        local rgb = (c[1] << 16) | (c[2] << 8) | c[3]
        if ImGui.ColorButton(ctx, "Colour " .. i .. "##palsw" .. id .. i, rgba(rgb),
            ImGui.ColorEditFlags_NoTooltip, CP.SWATCH, CP.SWATCH) then
          picked = rgb
        end
        tip(ctx, ("%s %d  #%06X"):format(cur.name, i, rgb))
      end
      ImGui.EndChild(ctx)
    end
  end
  return picked
end

-- ---------------------------------------------------------------------
-- recent colours
-- ---------------------------------------------------------------------

CP.recent = {}

-- Puts a colour at the front of the recent list.
function CP.remember(rgb)
  if not rgb then return end
  rgb = rgb & 0xffffff
  for i = #CP.recent, 1, -1 do
    if CP.recent[i] == rgb then table.remove(CP.recent, i) end
  end
  table.insert(CP.recent, 1, rgb)
  while #CP.recent > RECENT_MAX do table.remove(CP.recent) end
end

-- The recent colours as a row of swatches. Returns the one clicked, or nil.
function CP.recent_row(ctx, id, size)
  size = size or CP.SWATCH
  local picked
  for i, rgb in ipairs(CP.recent) do
    if (i - 1) % CP.PAL_COLS ~= 0 then ImGui.SameLine(ctx, 0, 4) end
    if ImGui.ColorButton(ctx, ("#%06X##rc%s%d"):format(rgb, id, i), rgba(rgb),
        ImGui.ColorEditFlags_NoTooltip, size, size) then
      picked = rgb
    end
    tip(ctx, ("#%06X"):format(rgb))
  end
  return picked
end

-- ---------------------------------------------------------------------
-- the eyedropper
-- ---------------------------------------------------------------------

local drop = { owner = nil, wait_up = false, rgb = nil }
local screen_dc
local order, order_read     -- the screen's byte order, once known (read when first needed)
local function known_order()
  if not order_read then
    order_read = true
    local o = reaper.GetExtState(NS, ORDER_KEY)
    if o == "rgb" or o == "bgr" then order = o end
  end
  return order
end
local probe          -- { x, y, rgb }: the dialog's own swatch, in screen pixels

function CP.can_drop()
  return reaper.JS_GDI_GetScreenDC ~= nil and reaper.JS_GDI_Blit ~= nil
     and reaper.JS_LICE_CreateBitmap ~= nil and reaper.JS_LICE_GetDC ~= nil
     and reaper.JS_LICE_GetPixel ~= nil
     and reaper.JS_Mouse_GetState ~= nil and reaper.GetMousePosition ~= nil
end

-- Whether the eyedropper is out (so Esc is its, not the dialog's).
function CP.dropping() return drop.owner ~= nil end

local function swap(c) return ((c & 0xff) << 16) | (c & 0xff00) | ((c >> 16) & 0xff) end

-- The raw pixel at screen (x, y), as the extension gives it, or nil.
-- The screen's DC, the one-pixel bitmap and its DC are made once and kept
-- for as long as the script runs: making and freeing them every frame
-- would leak whenever a free failed.
local pix_bmp, pix_dc
local function raw_pixel(x, y)
  if not screen_dc then
    local ok, dc = pcall(reaper.JS_GDI_GetScreenDC)
    if not ok or not dc then return nil end
    screen_dc = dc
  end
  if not pix_bmp then
    local ok, bmp = pcall(reaper.JS_LICE_CreateBitmap, true, 1, 1)
    if not ok or not bmp then return nil end
    local ok2, dc = pcall(reaper.JS_LICE_GetDC, bmp)
    if not ok2 or not dc then return nil end
    pix_bmp, pix_dc = bmp, dc
  end
  if not pcall(reaper.JS_GDI_Blit, pix_dc, 0, 0, screen_dc, math.floor(x), math.floor(y), 1, 1) then
    return nil
  end
  local ok, c = pcall(reaper.JS_LICE_GetPixel, pix_bmp, 0, 0)
  if not ok or type(c) ~= "number" then return nil end
  return math.floor(c) & 0xffffff          -- 0xAARRGGBB: the alpha goes
end

local function dist(a, b)
  local d = 0
  for _, sh in ipairs({ 16, 8, 0 }) do d = d + math.abs(((a >> sh) & 0xff) - ((b >> sh) & 0xff)) end
  return d
end

-- Works out the byte order from the dialog's swatch, whose colour is
-- known -- when that colour tells the two apart (red and blue unlike).
local function calibrate()
  if known_order() or not probe then return end
  local k = probe.rgb
  if math.abs(((k >> 16) & 0xff) - (k & 0xff)) < 48 then return end
  local c = raw_pixel(probe.x, probe.y)
  if not c then return end
  local as_is, swapped = dist(c, k), dist(swap(c), k)
  if math.min(as_is, swapped) > 60 then return end   -- not the swatch after all
  order = (as_is <= swapped) and "rgb" or "bgr"
  reaper.SetExtState(NS, ORDER_KEY, order, true)
end

local function pixel(x, y)
  local c = raw_pixel(x, y)
  if c and order == "bgr" then c = swap(c) end
  return c
end

local function stop() drop.owner, drop.rgb = nil, nil end

-- Each frame while the eyedropper is out: follow the pointer, show what's
-- under it, and take it on a click or Enter. Returns the colour taken, or
-- nil.
local function dropper_frame(ctx)
  local mx, my = reaper.GetMousePosition()
  calibrate()
  local c = pixel(mx, my)
  if c then drop.rgb = c end
  local btn = reaper.JS_Mouse_GetState(3) or 0
  local taken
  if drop.wait_up then
    -- the click that switched it on is still down
    if (btn & 1) == 0 then drop.wait_up = false end
  elseif (btn & 1) ~= 0 then
    taken = drop.rgb
  end
  if ImGui.IsKeyPressed(ctx, ImGui.Key_Enter) or ImGui.IsKeyPressed(ctx, ImGui.Key_KeypadEnter) then
    taken = drop.rgb
  end
  if taken then stop() return taken end
  if (btn & 2) ~= 0 or ImGui.IsKeyPressed(ctx, ImGui.Key_Escape) then stop() return nil end

  -- the tag beside the pointer, wherever it is
  if drop.rgb then
    local ok, ix, iy = pcall(ImGui.PointConvertNative, ctx, mx, my, false)
    if ok and ix then ImGui.SetNextWindowPos(ctx, ix + 20, iy + 20) end
    if ImGui.BeginTooltip(ctx) then
      local dl = ImGui.GetWindowDrawList(ctx)
      local x, y = ImGui.GetCursorScreenPos(ctx)
      ImGui.Dummy(ctx, 44, 22)
      ImGui.DrawList_AddRectFilled(dl, x, y, x + 44, y + 22, rgba(drop.rgb), 3.0)
      ImGui.DrawList_AddRect(dl, x, y, x + 44, y + 22, 0x000000a0, 3.0, 0, 1.0)
      ImGui.SameLine(ctx)
      ImGui.Text(ctx, ("#%06X"):format(drop.rgb))
      ImGui.TextDisabled(ctx, "Click or Enter: take it   Esc: stop")
      ImGui.EndTooltip(ctx)
    end
  end
  return nil
end

-- ---------------------------------------------------------------------
-- any colour: the picker, the eyedropper, the colour as it stands
-- ---------------------------------------------------------------------

-- Draws the picker for state `s` (its .rgb), with the eyedropper beside
-- it. Returns true when the colour changed this frame.
function CP.any_colour(ctx, s, id)
  local changed = false
  local width = CP.width()
  ImGui.SetNextItemWidth(ctx, width)
  local pch, rgb = ImGui.ColorPicker3(ctx, "##pick" .. id, s.rgb,
    ImGui.ColorEditFlags_DisplayRGB | ImGui.ColorEditFlags_DisplayHex | ImGui.ColorEditFlags_NoSidePreview)
  if pch then s.rgb = rgb & 0xffffff; changed = true end

  -- the colour as it stands -- also what the eyedropper reads to learn
  -- the screen's byte order
  ImGui.ColorButton(ctx, "##now" .. id, rgba(s.rgb), ImGui.ColorEditFlags_NoTooltip, 44, 24)
  do
    local x0, y0 = ImGui.GetItemRectMin(ctx)
    local x1, y1 = ImGui.GetItemRectMax(ctx)
    local ok, nx, ny = pcall(ImGui.PointConvertNative, ctx, (x0 + x1) * 0.5, (y0 + y1) * 0.5, true)
    if ok and nx then probe = { x = nx, y = ny, rgb = s.rgb } end
  end
  ImGui.SameLine(ctx)
  ImGui.AlignTextToFramePadding(ctx)
  ImGui.Text(ctx, ("#%06X"):format(s.rgb))

  if CP.can_drop() then
    ImGui.SameLine(ctx, 0, 14)
    local mine = drop.owner == s
    if W.icon_button(ctx, "##drop" .. id, "dropper", 24, mine,
        mine and "Stop (Esc)" or "Eyedropper: take a colour from anywhere on screen") then
      if mine then stop()
      else drop.owner, drop.wait_up, drop.rgb = s, true, nil end
    end
    if mine then
      ImGui.SameLine(ctx)
      ImGui.AlignTextToFramePadding(ctx)
      ImGui.TextDisabled(ctx, "Click anywhere")
      local got = dropper_frame(ctx)
      if got then s.rgb = got; changed = true end
    end
  end
  return changed
end

-- ---------------------------------------------------------------------
-- a row of cap colours, for a menu
-- ---------------------------------------------------------------------

-- The cap colours (C.CAPS) as swatches, the one chosen now outlined; under
-- them a [+] that opens the colour picker, the colour of your own chosen
-- now (when there is one) and the recent colours. `now`: the key chosen
-- (a name or #rrggbb), nil for none. `from`: 0xRRGGBB the picker starts on
-- when there's no custom colour. `pick(key, save)`: makes a choice --
-- `save` false while the picker is only showing it. `revert()`: puts back
-- what was there when the picker's Cancel is pressed.
function CP.cap_swatches(ctx, id, now, from, title, pick, revert)
  local dl = ImGui.GetWindowDrawList(ctx)
  local function outline()
    local x0, y0 = ImGui.GetItemRectMin(ctx)
    local x1, y1 = ImGui.GetItemRectMax(ctx)
    ImGui.DrawList_AddRect(dl, x0 - 2, y0 - 2, x1 + 2, y1 + 2, C.COL.header_text, 3.0, 0, 1.5)
  end
  for i, cp in ipairs(C.CAPS) do
    if i > 1 then ImGui.SameLine(ctx, 0, 4) end
    if ImGui.ColorButton(ctx, cp.label .. "##" .. id .. "_c" .. cp.key, cp.col or C.COL.knob_fill,
        ImGui.ColorEditFlags_NoTooltip, 18, 18) then
      pick(cp.key, true)
    end
    tip(ctx, cp.label)
    if cp.key == now then outline() end
  end
  local x, y = ImGui.GetCursorScreenPos(ctx)
  if ImGui.Button(ctx, "##" .. id .. "_add", 18, 18) then
    CP.open({
      title   = title,
      rgb     = C.custom_rgb(now) or from or 0x808080,
      preview = function(rgb) pick(("#%06x"):format(rgb), false) end,
      apply   = function(rgb) pick(("#%06x"):format(rgb), true) end,
      cancel  = revert,
    })
  end
  tip(ctx, "Custom colour\u{2026}")
  W.ICONS.plus(dl, x + 3, y + 3, 12, C.COL.icon)
  local ck, shown = C.custom_key(now), {}
  if ck then
    ImGui.SameLine(ctx, 0, 4)
    ImGui.ColorButton(ctx, ck:upper() .. "##" .. id .. "_now", rgba(C.custom_rgb(ck)),
      ImGui.ColorEditFlags_NoTooltip, 18, 18)
    tip(ctx, ck:upper())
    outline()
    shown[ck] = true
  end
  for i, rgb in ipairs(CP.recent) do
    local k = ("#%06x"):format(rgb)
    if not shown[k] then
      ImGui.SameLine(ctx, 0, 4)
      if ImGui.ColorButton(ctx, k:upper() .. "##" .. id .. "_rc" .. i, rgba(rgb),
          ImGui.ColorEditFlags_NoTooltip, 18, 18) then
        pick(k, true)
        CP.remember(rgb)
      end
      tip(ctx, "Recent  " .. k:upper())
    end
  end
end

-- A dialog closing puts its eyedropper away.
function CP.release(s) if drop.owner == s then stop() end end

-- ---------------------------------------------------------------------
-- the faceplate / background / section colour dialog
-- ---------------------------------------------------------------------

local DLG_ID = "###cp_dlg"
local dlg      -- { req, s, title, preview, apply, cancel }

-- Opens the dialog on the next frame. `o`: { title, rgb (to start from),
-- preview(rgb) (shows a colour on the panel while it's being chosen),
-- apply(rgb) (keeps it), cancel() (puts back what was there) }.
function CP.open(o)
  if dlg and dlg.cancel then dlg.cancel() end
  dlg = { req = true, s = CP.new_state(o.rgb), title = o.title or "Colour",
          preview = o.preview, apply = o.apply, cancel = o.cancel }
end

-- Draws the dialog, if one is open; call once a frame from the window's
-- top level. Returns true when a colour was kept.
function CP.draw(ctx)
  if not dlg then return false end
  if dlg.req then
    dlg.req = false
    ImGui.OpenPopup(ctx, DLG_ID)
  end
  local visible, open = ImGui.BeginPopupModal(ctx, dlg.title .. DLG_ID, true,
    ImGui.WindowFlags_AlwaysAutoResize | ImGui.WindowFlags_NoCollapse)
  if not visible then
    -- closed with its X (or never shown): as Cancel
    if dlg then
      CP.release(dlg.s)
      if dlg.cancel then dlg.cancel() end
      dlg = nil
    end
    return false
  end

  local d, s = dlg, dlg.s
  local done, kept = false, false
  local function keep(rgb)
    s.rgb = rgb
    if d.apply then d.apply(rgb) end
    CP.remember(rgb)
    done, kept = true, true
  end

  ImGui.SeparatorText(ctx, "Palette")
  local p = CP.palette(ctx, s, "cp")
  if p then keep(p) end
  -- REAPER's own picker, as the track colour dialog has (it's modal, and
  -- keeps the colour as soon as it's OK'd)
  if not done and reaper.GR_SelectColor and ImGui.Button(ctx, "REAPER's colour picker\u{2026}##cp") then
    local ok, rv, native = pcall(reaper.GR_SelectColor, reaper.GetMainHwnd())
    if ok and rv and rv ~= 0 and native then
      local r, g, b = reaper.ColorFromNative(native)
      keep((r << 16) | (g << 8) | b)
    end
  end

  if #CP.recent > 0 then
    ImGui.SeparatorText(ctx, "Recent")
    local r = CP.recent_row(ctx, "cp")
    if r then keep(r) end
  end

  ImGui.SeparatorText(ctx, "Any colour")
  if CP.any_colour(ctx, s, "cp") and d.preview and not done then d.preview(s.rgb) end

  ImGui.Spacing(ctx)
  if not done then
    if ImGui.Button(ctx, "Apply") then keep(s.rgb) end
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, "Cancel")
       or (not CP.dropping() and ImGui.IsKeyPressed(ctx, ImGui.Key_Escape)) then
      if d.cancel then d.cancel() end
      done = true
    end
  end

  if done then
    CP.release(s)
    ImGui.CloseCurrentPopup(ctx)
    dlg = nil
  end
  ImGui.EndPopup(ctx)
  if not open and dlg then
    CP.release(s)
    if d.cancel then d.cancel() end
    dlg = nil
  end
  return kept
end

return CP
