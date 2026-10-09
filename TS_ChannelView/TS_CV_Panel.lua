-- @noindex
-- Not a package of its own: installed by TS_ChannelView.lua's @provides.
--[[
  TS_CV_Panel.lua -- one plugin's panel.

  Panels are a FIXED HEIGHT (they fill the window) and GROW IN COLUMNS:
  the number of rows falls out of the available height, controls flow down
  a column and wrap into a new one, and the panel gets wider. So a plugin
  with four assigned controls is a narrow strip and one with twenty is a
  wide block, and neither ever scrolls vertically -- the row of panels
  scrolls sideways instead.
--]]

local C   = require("TS_CV_Config")
local U   = require("TS_CV_Util")
local W   = require("TS_CV_Widgets")
local T   = require("TS_CV_FXTree")
local M   = require("TS_CV_Mappings")
local TL  = require("TS_CV_Tiles")
local SC  = require("TS_CV_Steps")
local St  = require("TS_CV_State")
local RQ  = require("TS_CV_ReaEQ")
local EQP = require("TS_CV_EQPanel")
local RC  = require("TS_CV_ReaComp")
local CP  = require("TS_CV_CompPanel")
local TP  = require("TS_CV_Taps")
local PU  = require("TS_CV_PresetUI")
local Tr  = require("TS_CV_Trace")

local P   = {}
local ImGui

function P.attach(imgui) ImGui = imgui; EQP.attach(imgui); CP.attach(imgui); PU.attach(imgui) end

-- An expanded panel's foot: the layout lock at its left, and the preset
-- bar (TS_CV_PresetUI, View > Preset bar) when that's on. It's always
-- there, for the lock. Its height comes off the body, so everything that
-- sizes the body -- the row count, the grid, the meters, the EQ canvas --
-- asks here.
function P.footer_h() return C.FOOTER_H end

-- ---------------------------------------------------------------------
-- geometry
-- ---------------------------------------------------------------------
-- One layout pass, used by BOTH the width calculation and the draw. Computing
-- columns separately for each would risk the two disagreeing, which would put
-- controls outside their own panel border; dividers make that easy to get
-- wrong, so there is exactly one place that decides.

-- How many rows fit in a panel of `panel_h`.
function P.rows_for(panel_h)
  -- Top and bottom are no longer the same: the grid starts tight under
  -- the header so a cell's name line isn't pushed down, and keeps the
  -- full pad at the bottom.
  local body_h = panel_h - C.HEADER_H - P.footer_h() - C.GRID_TOP_PAD - C.PANEL_PAD
  return math.max(C.MIN_ROWS, math.floor(body_h / C.CELL_H))
end

-- Places every control, returning:
--   rows     how many rows the grid has
--   items    { ctl, x, y, w, h, sx, sw } -- x, y offsets from the grid
--            origin in pixels; w, h the control's size in half-cells (see
--            below); sx, sw the column it sits in, in pixels
--   rules    x offsets of vertical dividers, in the same space
--   width    total width of the grid, dividers included
--   height   how far down the grid actually reaches, for the rules
--   gaps     { x, w } for every divider's gap
--   spacers  { ctl, x, y, w, h, sx, sw } for every half_gap in column flow:
--            not controls, but they have a place, and can have a background
--   sections { x, w, by } for every section a divider gave a style to
--            (an inset, or its own faceplate, behind it) --
--            x and w in the grid's space, `by` the divider; the items
--            in it carry `sec`, the index into this list
--
-- THE HALF-CELL GRID. Everything is placed in half-cells, half a CELL_W
-- across and half a CELL_H down. A control is a block of them: an
-- ordinary one 2 x 2 (exactly the one cell every control has always
-- been), a half_gap 2 x 1, and the sizes in C.SIZES whatever they say. A
-- control too tall for the panel is drawn at the ordinary size instead.
-- With every control 2 x 2 this places each exactly where the old
-- one-cell layout did -- dev/TS_CV_LayoutFixture.lua holds the positions
-- every layout had before, and TS_CV_Test.lua checks them all.
--
-- A DIVIDER SPLITS THE PANEL INTO SECTIONS. Each section is laid out
-- independently in its own block of columns, so whatever follows a divider
-- always begins a new column -- no matter how the previous section ended,
-- whether it filled its last column or left gaps in it. That's the whole
-- point of a divider: "this group is finished, a new one starts here."
-- The rule is vertical in either flow, because it separates groups, and
-- that reads as a vertical break whichever way the controls run.
--
-- A "fader" SPLITS THE PANEL THE SAME WAY, but claims the column between
-- the two sections for itself, at the panel's full height, rather than
-- leaving a rule-only gap.
--
-- COLUMN FLOW (down, then across) runs a cursor down a strip of columns.
-- A control goes where the cursor is if it fits in the half-rows left,
-- otherwise the strip is finished and a new one starts to its right. A
-- strip is as wide as its widest control, and narrower controls in it are
-- centred. A half_gap only moves the cursor down half a row -- the way
-- some hardware staggers its knobs -- and one that doesn't fit what's
-- left of a strip starts the next strip, spent for nothing there.
--
-- ROW FLOW (across, then down) fills rows of a fixed width, chosen as the
-- narrowest that gets everything into the panel's height: with ordinary
-- controls that is ceil(n / rows) cells, as it always was. A half_gap is
-- an ordinary empty slot here; its half-step is a down-the-column idea.
local HALF_H = C.CELL_H * 0.5

-- `n` half-cells across, or down, in pixels: a whole number whenever it
-- is one, so an ordinary layout's positions are exactly what they were.
local function hx(n) local v = n * C.CELL_W / 2; return math.tointeger(v) or v end
local function hy(n) local v = n * C.CELL_H / 2; return math.tointeger(v) or v end

-- How many half-cells a control takes, across and down, in a panel of
-- `half_rows` half-rows. Faders and dividers aren't placed in a section
-- and never ask. Knobs and stepped knobs come in every size, toggles in
-- small and ordinary. A dropdown shown as buttons (P.button_span) also
-- answers "buttons" third, so the panel knows to draw it that way; one
-- whose buttons won't fit the panel's height is an ordinary dropdown.
function P.button_span(ctl)
  if ctl.type ~= "combo" or not ctl.buttons or not ctl.nbtn then return nil end
  local n = ctl.nbtn
  if ctl.buttons == "across" then return math.max(2, n), 2 end
  return 2, math.ceil((n + 1) / 2)
end

-- Where a fader goes (its Shape<n>, TS_CV_Mappings.shape_of):
--   "column"  vertical and full height: it splits the sections, as faders
--             always have, a column wide or half of one
--   "band"    horizontal and full length: from where it lands to the
--             panel's right edge (place_flow)
--   "block"   any other: placed among the controls like a knob, its
--             length in rows (or columns) and its thickness
function P.fader_kind(ctl)
  if ctl.type ~= "fader" then return nil end
  if ctl.dir == "h" then return ctl.len and "block" or "band" end
  return ctl.len and "block" or "column"
end

-- A fader's thickness in half-cells.
local function fader_thick(ctl) return ctl.thin and 1 or 2 end
P.fader_thick = fader_thick

function P.cell_size(ctl, half_rows)
  if ctl.type == "fader" then
    local t = fader_thick(ctl)
    if ctl.dir == "h" then return (ctl.len or 2) * 2, t, "hfader" end
    return t, math.min(half_rows, (ctl.len or 2) * 2), "vfader"
  end
  -- an XY pad: 2 or 3 columns by 2 or 3 rows, no taller than the panel
  if ctl.type == "xy" then
    local pw, ph = M.pad_dims(ctl)
    return pw * 2, math.min(half_rows, ph * 2), "xy"
  end
  local bw, bh = P.button_span(ctl)
  if bw and bh <= half_rows then return bw, bh, "buttons" end
  if ctl.type == "half_gap" then
    if C.FLOW == "row" then return 2, 2 end
    return 2, 1
  end
  local sizable = ctl.type == nil or ctl.type == "knob" or ctl.type == "stepped"
    or (ctl.type == "dual" and ctl.size ~= "small")
    or (ctl.type == "toggle" and ctl.size == "small")
  local sz = sizable and ctl.size and C.SIZES[ctl.size]
  if sz and sz.h <= half_rows then return sz.w, sz.h end
  return 2, 2
end

-- The size a placed item is drawn at, from the half-cells it was given:
-- "small", "large", or nil for the ordinary one (which is also what a
-- size too tall for the panel was given instead).
function P.item_size(item)
  for _, k in ipairs(C.SIZE_LIST) do
    local sz = C.SIZES[k]
    if k ~= "medium" and item.w == sz.w and item.h == sz.h then return k end
  end
  return nil
end

-- A divider's section style: "inset" for a recessed panel
-- behind the section after it, "plate" for that section on a faceplate of
-- its own (the plate's key in its colour field), or nil.
function P.section_style(div)
  if div.style == "inset" then return "inset" end
  if div.style == "plate" and C.plate_of(div.cap) then return "plate", C.plate_of(div.cap) end
  return nil
end

-- What makes two sections look the same: the style, the faceplate, and
-- whether it's brushed. Neighbouring sections that match join into one.
function P.section_key(div)
  local kind, pl = P.section_style(div)
  if not kind then return nil end
  return kind .. "|" .. (kind == "plate" and div.cap or "") .. "|"
         .. (M.part_brushed(kind, pl, div.brush) and "b" or "")
         .. (M.part_metal(kind, div.metal) and "m" or "")
end

-- A control's own background (Back<n>): "inset", or a faceplate key.
function P.back_style(back)
  if back == "inset" then return "inset" end
  local pl = back and C.plate_of(back)
  if pl then return "plate", pl end
  return nil
end

local function place_column(sec, x0, half_rows, items, spacers)
  local cx, cy, sw, deepest = 0, 0, 0, 0
  local strip = {}
  local function close_strip()
    for _, it in ipairs(strip) do
      if it.w < sw then it.x = it.x + hx(sw - it.w) / 2 end
      -- the whole column it sits in, for its background (full width)
      it.sx, it.sw = x0 + hx(cx), hx(sw)
    end
    strip = {}
    cx, cy, sw = cx + sw, 0, 0
  end
  for _, ctl in ipairs(sec) do
    local w, h, kind = P.cell_size(ctl, half_rows)
    if cy + h > half_rows then close_strip() end
    if ctl.type ~= "half_gap" then
      local it = { ctl = ctl, x = x0 + hx(cx), y = hy(cy), w = w, h = h, kind = kind }
      items[#items + 1] = it
      strip[#strip + 1] = it
      if cy + h > deepest then deepest = cy + h end
    elseif spacers then
      -- not a control, but it has a place (and maybe a background): kept
      -- aside so the panel can give it one and a right-click
      local sp = { ctl = ctl, x = x0 + hx(cx), y = hy(cy), w = w, h = h }
      spacers[#spacers + 1] = sp
      strip[#strip + 1] = sp
    end
    cy = cy + h
    if w > sw then sw = w end
  end
  local width = cx + sw
  close_strip()
  return hx(width), deepest
end

-- A panel with faders placed among its controls (any but the old
-- full-height column fader), or an XY pad: MERGED-CELL FLOW. The same down-then-across
-- strips as place_column, always in list order -- a control never goes
-- back into an earlier gap -- but a fader takes every cell it covers when
-- it's placed, like merged cells in a spreadsheet, and whatever comes
-- after skips those cells: below it in its own column, then above, below
-- or between in the columns it runs into. An across fader runs over
-- dividers (the rule stops at its edges), and so does an XY pad wider
-- than a column; everything else still starts a
-- new column at one. A half-width control goes beside a half-width one
-- before it if it's the same height (a row of them, a graphic EQ); any
-- other control after one starts below it. A full-length across fader
-- runs from where it lands to the panel's right edge, at least two
-- columns. Everything is worked in half-cells first and turned into
-- pixels at the end, once every divider's place is known.
local function place_flow(controls, half_rows, rows)
  local DW = C.DIVIDER_W
  local occ, fulls, bounds, cuts = {}, {}, {}, {}
  local placed, secs = {}, {}
  local function free(c, r, w, h)
    if r < 0 or r + h > half_rows then return false end
    for i = c, c + w - 1 do
      local col = occ[i]
      if col then for j = r, r + h - 1 do if col[j] then return false end end end
    end
    for _, f in ipairs(fulls) do
      if c + w > f.c and r < f.r + f.h and f.r < r + h then return false end
    end
    return true
  end
  local function take(c, r, w, h)
    for i = c, c + w - 1 do
      occ[i] = occ[i] or {}
      for j = r, r + h - 1 do occ[i][j] = true end
    end
  end
  local cs, sw, cy, strip, prev = 0, 0, 0, {}, nil
  local function close()
    for _, it in ipairs(strip) do it.sc, it.ssw = cs, sw end
    cs, sw, cy, strip, prev = cs + sw, 0, 0, {}, nil
  end
  local sec = { c0 = 0, first = 1 }
  for li, ctl in ipairs(controls) do
    if ctl.type == "divider" then
      if #strip > 0 then close() end
      sec.c1, sec.last = cs, #placed
      secs[#secs + 1] = sec
      bounds[#bounds + 1] = { b = cs, no_rule = ctl.no_rule }
      sec = { c0 = cs, first = #placed + 1, by = ctl }
    else
      local w, h, kind = P.cell_size(ctl, half_rows)
      local k = P.fader_kind(ctl)
      if k == "column" then h = half_rows end
      local full = k == "band"
      if full then w = 4; kind = "hfader" end
      h = math.min(h, half_rows)
      local pc, pr, pair
      -- half-width beside the half-width one before it
      if w == 1 and prev and prev.w == 1 and prev.h == h and prev.c == cs and not prev.pair
         and free(cs + 1, prev.r, 1, h) then
        pc, pr, pair = cs + 1, prev.r, true
        prev.pair = true
      end
      local guard = 0
      while not pc do
        for r = cy, half_rows - h do
          if free(cs, r, w, h) then pc, pr = cs, r break end
        end
        if not pc then
          guard = guard + 1
          if guard > 400 then pc, pr = cs, 0 break end
          -- an empty strip that can't take it (spans in the way): skip a column
          if #strip == 0 then cs, cy = cs + 2, 0 else close() end
        end
      end
      -- across faders and XY pads take cells to their right: merged cells
      local span = (kind == "hfader" or kind == "xy") or nil
      if full then fulls[#fulls + 1] = { c = pc, r = pr, h = h } else take(pc, pr, w, h) end
      local it = { ctl = ctl, c = pc, r = pr, w = w, h = h, kind = kind, span = span, full = full or nil,
                   pair = pair or nil, spacer = ctl.type == "half_gap" or nil }
      placed[#placed + 1] = it
      strip[#strip + 1] = it
      local used = span and 2 or (pc - cs + w)
      if used > sw then sw = used end
      if pr + h > cy then cy = pr + h end
      prev = it
    end
  end
  if #strip > 0 then close() end
  sec.c1, sec.last = cs, #placed
  secs[#secs + 1] = sec

  -- how many half-columns across, and the full-length faders' lengths
  local total, deepest = cs, 0
  for _, it in ipairs(placed) do
    if it.full then total = math.max(total, it.c + 4)
    else total = math.max(total, it.c + it.w) end
    -- a half-gap is room, not a control: it never makes the panel deeper
    if not it.spacer and it.r + it.h > deepest then deepest = it.r + it.h end
  end
  for _, it in ipairs(placed) do if it.full then it.w = total - it.c end end

  -- pixels: a half-column's left edge, past every divider gap at or before
  -- it; a span's right edge, past the gaps inside it
  local function left(c)
    local n = 0
    for _, g in ipairs(bounds) do if g.b <= c then n = n + 1 end end
    return hx(c) + DW * n
  end
  local function right(c)
    local n = 0
    for _, g in ipairs(bounds) do if g.b < c then n = n + 1 end end
    return hx(c) + DW * n
  end
  local items, spacers, rules, gaps, styled = {}, {}, {}, {}, {}
  for _, it in ipairs(placed) do
    local x = left(it.c)
    local out = { ctl = it.ctl, x = x, y = hy(it.r), w = it.w, h = it.h, kind = it.kind }
    if it.span then
      out.pw = right(it.c + it.w) - x
      out.sx, out.sw = x, out.pw
    else
      local ssw = it.ssw or it.w
      if not it.pair and it.w < ssw and it.c == it.sc then out.x = x + hx(ssw - it.w) / 2 end
      out.sx, out.sw = left(it.sc or it.c), hx(ssw)
    end
    it.out = out
    if it.spacer then spacers[#spacers + 1] = out else items[#items + 1] = out end
  end
  -- the dividers: their gaps, their rules, where an across fader crosses
  local per = {}
  for _, g in ipairs(bounds) do
    per[g.b] = (per[g.b] or 0) + 1
    local n = 0
    for _, o in ipairs(bounds) do if o.b < g.b then n = n + 1 end end
    local gx = hx(g.b) + DW * (n + per[g.b] - 1)
    gaps[#gaps + 1] = { x = gx, w = DW }
    if not g.no_rule then
      local rx = gx + DW * 0.5
      rules[#rules + 1] = rx
      local cut = {}
      for _, it in ipairs(placed) do
        if it.span and it.c < g.b and g.b < it.c + it.w then
          cut[#cut + 1] = { hy(it.r) - 3, hy(it.r + it.h) + 3 }
        end
      end
      if #cut > 0 then cuts[#rules] = cut end
    end
  end
  -- sections a divider styled, joined to the one before when they match
  -- and only a divider apart
  for _, s in ipairs(secs) do
    if s.by and P.section_style(s.by) and s.c1 > s.c0 then
      local x = left(s.c0)
      local w = right(s.c1) - x
      local prev = styled[#styled]
      if prev and math.abs(prev.x + prev.w + DW - x) < 0.5
         and P.section_key(prev.by) == P.section_key(s.by) then
        prev.w = x + w - prev.x
      else
        styled[#styled + 1] = { x = x, w = w, by = s.by }
      end
      for k = s.first, s.last do placed[k].out.sec = #styled end
    end
  end
  return { rows = rows, items = items, rules = rules, rule_cuts = cuts, width = left(total),
           sections = styled, gaps = gaps, spacers = spacers,
           height = math.max(1, math.min(half_rows, deepest)) * HALF_H }
end

P.place_flow = place_flow   -- for the tests: it must agree with the strips

local function place_row(sec, x0, half_rows, items)
  local area, widest, total_w = 0, 0, 0
  local sizes = {}
  for i, ctl in ipairs(sec) do
    local w, h, kind = P.cell_size(ctl, half_rows)
    sizes[i] = { w, h, kind }
    area = area + w * h
    total_w = total_w + w
    if w > widest then widest = w end
  end
  local rows = half_rows // 2
  local lim = math.max(widest, 2 * math.ceil(area / 4 / rows))
  local placed, deepest
  while true do
    placed, deepest = {}, 0
    local cx, cy, lh = 0, 0, 0
    for i, ctl in ipairs(sec) do
      local w, h = sizes[i][1], sizes[i][2]
      if cx + w > lim then cy, cx, lh = cy + lh, 0, 0 end
      placed[#placed + 1] = { ctl = ctl, x = x0 + hx(cx), y = hy(cy), w = w, h = h, kind = sizes[i][3] }
      if cy + h > deepest then deepest = cy + h end
      cx = cx + w
      if h > lh then lh = h end
    end
    if deepest <= half_rows or lim >= total_w then break end
    lim = lim + 1
  end
  for _, it in ipairs(placed) do
    it.sx, it.sw = it.x, hx(it.w)
    items[#items + 1] = it
  end
  return hx(lim), deepest
end

-- `lock` is a locked layout's row count (Lock=<rows>): the arrangement it
-- had then, whatever the panel's height now.
function P.layout(controls, panel_h, lock)
  local rows  = lock or P.rows_for(panel_h)
  local half_rows = rows * 2
  -- faders placed among the controls: merged-cell flow (place_flow);
  -- anything else keeps the sections and strips it always had
  if C.FLOW ~= "row" then
    for _, ctl in ipairs(controls) do
      local k = P.fader_kind(ctl)
      if k == "block" or k == "band" or ctl.type == "xy" then return place_flow(controls, half_rows, rows) end
    end
  end
  local items, rules = {}, {}

  -- split the control list at dividers and faders; a leading, trailing
  -- or doubled one simply yields an empty section in between, which
  -- costs that splitter's own space and no columns of section content.
  -- `splitters[n]` is the control that opened sections[n+1].
  local sections, splitters, cur = {}, {}, {}
  for _, ctl in ipairs(controls) do
    if ctl.type == "divider" or P.fader_kind(ctl) == "column" then
      sections[#sections + 1] = cur
      splitters[#splitters + 1] = ctl
      cur = {}
    else
      cur[#cur + 1] = ctl
    end
  end
  sections[#sections + 1] = cur

  local x, deepest = 0, 0
  local styled, gaps, spacers = {}, {}, {}
  for si, sec in ipairs(sections) do
    if si > 1 then
      local sp = splitters[si - 1]
      if sp.type == "fader" then
        -- full height always: a fader isn't capped by `deepest`, it sets it
        local t = fader_thick(sp)
        items[#items + 1] = { ctl = sp, x = x, y = 0, w = t, h = half_rows, sx = x, sw = hx(t) }
        if half_rows > deepest then deepest = half_rows end
        x = x + hx(t)
      else
        -- The gap is unconditional -- a no-rule divider still ends the
        -- column and opens the same C.DIVIDER_W space, it just adds no
        -- entry to `rules`, so the draw side has nothing to draw for it.
        if not sp.no_rule then
          rules[#rules + 1] = x + C.DIVIDER_W * 0.5
        end
        gaps[#gaps + 1] = { x = x, w = C.DIVIDER_W }
        x = x + C.DIVIDER_W
      end
    end
    local w, d
    local first = #items + 1
    if C.FLOW == "row" then w, d = place_row(sec, x, half_rows, items)
    else w, d = place_column(sec, x, half_rows, items, spacers) end
    -- a section styled by the divider in front of it
    local sp = splitters[si - 1]
    if sp and sp.type == "divider" and P.section_style(sp) and w > 0 then
      -- the same style as the section just before, only a divider apart:
      -- one section, across the divider
      local prev = styled[#styled]
      if prev and math.abs(prev.x + prev.w + C.DIVIDER_W - x) < 0.5
         and P.section_key(prev.by) == P.section_key(sp) then
        prev.w = x + w - prev.x
      else
        styled[#styled + 1] = { x = x, w = w, by = sp }
      end
      for k = first, #items do items[k].sec = #styled end
    end
    x = x + w
    if d > deepest then deepest = d end
  end

  return { rows = rows, items = items, rules = rules, width = x, sections = styled, gaps = gaps,
           spacers = spacers,
           height = math.max(1, math.min(half_rows, deepest)) * HALF_H }
end

-- `key` is optional (existing callers that only ever draw a plain grid
-- don't have to pass one) and only ever matters for one thing: a ReaEQ
-- panel isn't a grid at all, so none of the layout below applies to it --
-- it gets a fixed canvas width instead. See TS_CV_EQPanel.lua.
-- Whether a locked panel's grid is taller than its body, and scrolls.
function P.scrolls(lay, panel_h, lock)
  if not lock then return false end
  local body = panel_h - C.HEADER_H - P.footer_h()
  return C.GRID_TOP_PAD + lay.height + C.PANEL_PAD > body
end

function P.width(n_or_controls, avail_h, collapsed, has_meter, key, has_io, has_trace, lock)
  if collapsed then return C.COLLAPSED_W end
  if key and RQ.is_eq(key) then
    return C.EQ_PANEL_W + (has_io and (C.IO_COL_W + C.PANEL_PAD) * 2 or 0)
  end
  -- ReaComp: its own canvas, meters included (TS_CV_CompPanel.lua)
  if key and RC.is_comp(key) then return C.RC_PANEL_W end
  local controls = n_or_controls
  if type(controls) == "number" then
    -- callers that only know the count get a plain grid, no dividers
    local n = controls
    controls = {}
    for i = 1, n do controls[i] = { type = "knob" } end
  end
  local lay = P.layout(controls, avail_h, lock)
  -- a locked grid too tall for the panel scrolls, its scrollbar beside it
  local sb = P.scrolls(lay, avail_h, lock) and C.SCROLL_W + 2 or 0
  local w = math.max(C.PANEL_MIN_W, lay.width + sb + C.PANEL_PAD * 2)
  -- The meter is a strip, not a column: it adds its own narrow width
  -- rather than pushing the panel out by a whole CELL_W.
  if has_meter then w = w + C.METER_COL_W + C.PANEL_PAD end
  -- ...and opened out into its trace, the trace beside it.
  if has_meter and has_trace then w = w + C.GRV_W + C.PANEL_PAD end
  if has_io then w = w + (C.IO_COL_W + C.PANEL_PAD) * 2 end
  return w
end

-- Whether a panel shows input/output meters: the plugin is set to
-- (Levels=1), and the probes are measuring this instance.
function P.has_io(track, fx, layout)
  return layout ~= nil and layout.levels == true and TP.is_metered(track, fx.guid)
end

-- ---------------------------------------------------------------------
-- per-parameter step size, cached: TrackFX_GetParameterStepSizes is cheap
-- but not free, and it never changes for a given plugin instance.
-- ---------------------------------------------------------------------

local step_cache  = {}
local steps_cache = {}

function P.clear_caches() step_cache = {}; steps_cache = {} end

local function step_norm(track, addr, param, key)
  local ck = key .. ":" .. param
  local v = step_cache[ck]
  if v ~= nil then return v end
  local ok, step = reaper.TrackFX_GetParameterStepSizes(track, addr, param)
  -- GetParamEx returns the VALUE first, then min/max/mid -- mixing up the
  -- argument order silently breaks step detection for every parameter.
  local _, minv, maxv = reaper.TrackFX_GetParamEx(track, addr, param)
  local out = false
  if ok and step and step > 0 and minv and maxv and maxv > minv then
    out = step / (maxv - minv)
    if out <= 0 or out >= 1 then out = false end
  end
  step_cache[ck] = out
  return out
end
P.step_norm = step_norm      -- exposed for TS_CV_Test.lua

-- A knob's numbered scale (Scale<n>): where its numbers go and what they
-- say, for W.knob's opts.scale. The plugin is asked what each mark's value
-- reads as (U.scale_labels), which is a round trip per number, so the
-- answer is kept a few seconds -- long enough not to ask every frame,
-- short enough to follow a plugin whose readout depends on another
-- control (a range switch). A reversed control's marks are read from the
-- other end. A small knob has no room for one.
-- Values are every knob's scale unless it says otherwise (M.scale_kind),
-- so each answer is kept on its own clock, staggered, rather than the
-- whole lot being asked for again in one frame.
local scale_cache = {}
function P.knob_scale(track, fx, p, key, ctl, size, rev, st)
  local kind = M.scale_kind(ctl)
  if not kind or size == "small" then return nil end
  local now = reaper.time_precise()
  local ck = table.concat({ fx.guid or key or "", p, kind, size or "medium",
                            rev and "r" or "", st and "s" or "" }, "|")
  local sc = scale_cache[ck]
  if not sc or now > sc.until_t then
    local n = st and (math.floor(1 / st + 0.5) + 1) or nil
    local marks = U.scale_marks(kind, size, n)
    local at = {}
    for i, m in ipairs(marks) do at[i] = rev and (1 - m) or m end
    sc = { marks = marks, labels = U.scale_labels(track, fx.addr, p, kind, at),
           until_t = now + 2.5 + math.random() }
    scale_cache[ck] = sc
  end
  local ink
  if ctl.scale_ink == "cap" then
    local style = C.KNOB_STYLE_ALIAS[ctl.style] or ctl.style
    local def = C.KNOB_STYLE[style or "arc"] or C.KNOB_STYLE.arc
    ink = W.cap_col(ctl.cap) or W.cap_col(def.cap)
  end
  return { marks = sc.marks, labels = sc.labels, ink = ink }
end

-- ---------------------------------------------------------------------
-- stepped-parameter choices
-- ---------------------------------------------------------------------

-- The only way to learn a plugin's step LABELS through the ReaScript API
-- is to write each value into it and read back the formatted result. There
-- is no read-only enumeration. So this sweeps the parameter once, restores
-- it, and caches the answer for the session.
--
-- It will NOT sweep while the transport is rolling. Each write is queued
-- to the audio thread, and a frame is comparable to a buffer, so a sweep
-- during playback can genuinely be heard. Stopped, it is inaudible and
-- instant; playing, the control falls back to stepping up and down, which
-- needs no sweep.
local MAX_STEPS = 64

-- Sweeps allowed this frame; reset by P.begin_frame.
local scan_budget = 0

-- Controls whose list was just fetched on demand and should open next
-- frame, keyed by the control's ImGui id.
local pending_open = {}

-- (the gain-reduction trace reads the probe once a frame, too)
function P.begin_frame() scan_budget = C.SCAN_BUDGET; Tr.begin_frame() end

-- Returns a list of choices, or:
--   nil    not scanned yet, but scannable -- ask again, or force it
--   false  never scannable (continuous, or too many positions to sweep)
--
-- `force` means the user just clicked the control asking for the list.
-- That is a deliberate action, no different from them turning the knob,
-- so it scans whatever the transport is doing. Only the automation guard
-- still applies, because that one is about not writing a lane full of
-- garbage rather than about audibility.
local function combo_steps(track, addr, param, key, force)
  local ck = key .. ":" .. param
  local c = steps_cache[ck]
  if c ~= nil then return c end

  local st = step_norm(track, addr, param, key)
  if not st then steps_cache[ck] = false; return false end

  local n = math.floor(1 / st + 0.5) + 1
  if n < 2 or n > MAX_STEPS then steps_cache[ck] = false; return false end

  -- Scanned on a previous run? Then there is nothing to sweep at all.
  local saved_list = SC.get(key, param, st)
  if saved_list then
    steps_cache[ck] = saved_list
    return saved_list
  end

  -- Nothing is cached when a scan is refused, so it's retried every frame
  -- and the list appears by itself the moment it becomes safe.
  local rolling = (reaper.GetPlayState() & 1) == 1
  if rolling then
    -- Never while automation is being written, whatever anyone asked for.
    -- A sweep under write/touch/latch doesn't just move the parameter, it
    -- records the entire sweep into the lane -- damage to the project
    -- rather than a click.
    local mode = reaper.GetMediaTrackInfo_Value(track, "I_AUTOMODE") or 0
    if mode >= 2 then return nil end
    -- Otherwise the transport only holds back BACKGROUND scanning. An
    -- explicit click goes ahead.
    if not force and not C.SCAN_WHILE_PLAYING then return nil end
  end

  -- Spread background sweeping over frames; returning nil here just means
  -- "not yet", and this is retried until the budget comes round. A click
  -- isn't rationed -- the user is waiting for it.
  if not force then
    if scan_budget <= 0 then return nil end
    scan_budget = scan_budget - 1
  end

  local saved = reaper.TrackFX_GetParamNormalized(track, addr, param)
  local out, seen = {}, {}
  for i = 0, n - 1 do
    local v = math.min(1, i * st)
    reaper.TrackFX_SetParamNormalized(track, addr, param, v)
    local ok, txt = reaper.TrackFX_GetFormattedParamValue(track, addr, param, "")
    txt = (ok and txt ~= "") and txt or string.format("%d", i)
    -- Some plugins format several positions identically; keeping the
    -- duplicates would make the list longer than it is meaningful.
    if not seen[txt] then
      seen[txt] = true
      out[#out + 1] = { norm = v, text = txt }
    end
  end
  reaper.TrackFX_SetParamNormalized(track, addr, param, saved)

  steps_cache[ck] = (#out >= 2) and out or false
  if steps_cache[ck] then SC.set(key, param, out) end
  return steps_cache[ck]
end
P.combo_steps = combo_steps  -- exposed for TS_CV_Test.lua

-- A dropdown's choices for its buttons. The scanned list when there is one;
-- until then -- the transport is rolling, say, when nothing is swept in the
-- background, and buttons never ask for a sweep the way an opened list
-- does -- the plugin is asked what each position would read as, which
-- moves nothing. Numbers only when it can't say (it answers every position
-- the same, or not at all). `n`: how many there are, when the plugin
-- reports no step size of its own (the layout's Buttons count).
local fmt_cache = {}
local function button_choices(track, addr, param, key, n)
  local list = combo_steps(track, addr, param, key)
  if type(list) == "table" then return list end
  local st = step_norm(track, addr, param, key)
  local count = st and (math.floor(1 / st + 0.5) + 1) or n
  if not count or count < 2 then return {} end
  local ck = key .. ":" .. param .. ":" .. count
  local now = reaper.time_precise()
  local hit = fmt_cache[ck]
  if hit and now < hit.until_t then return hit.list end
  local out, named, first, differ = {}, 0, nil, false
  for k = 0, count - 1 do
    local v = st and math.min(1, k * st) or (k / (count - 1))
    local txt
    if reaper.TrackFX_FormatParamValueNormalized then
      local ok, sv = reaper.TrackFX_FormatParamValueNormalized(track, addr, param, v, "")
      if ok and sv and U.trim(sv) ~= "" then txt = U.trim(sv); named = named + 1 end
    end
    if txt then
      if first == nil then first = txt elseif txt ~= first then differ = true end
    end
    out[k + 1] = { norm = v, text = txt }
  end
  local use = named == count and differ
  for k, e in ipairs(out) do if not use then e.text = tostring(k) end end
  fmt_cache[ck] = { list = out, until_t = now + 4 }
  return out
end
P.button_choices = button_choices
do
  local clear = P.clear_caches
  function P.clear_caches() clear(); fmt_cache = {} end
end

-- Drops both caches for one parameter so it is swept again -- the fix for
-- a plugin that has been updated and renamed its positions.
function P.rescan_choices(key, param)
  steps_cache[key .. ":" .. param] = nil
  step_cache[key .. ":" .. param]  = nil
  SC.forget(key, param)
  SC.save()
end

-- ---------------------------------------------------------------------
-- header
-- ---------------------------------------------------------------------

-- Draws the gain-reduction strip and returns the width it consumed,
-- including its gap, so the control grid can start beside it.
-- ---------------------------------------------------------------------
-- the gain-reduction trace
-- ---------------------------------------------------------------------
-- Click a gain-reduction meter and it opens out into a trace beside it.
-- The columns come from TS_CV_Trace (shared with the web companion); this
-- part only draws them.
-- The panel's background colour at a height, for fading the trace into it:
-- set up by the faceplate code further down (see bg_at there).
local bg_at
local push_plate, pop_plate, mix   -- the faceplate swap and colour mix, defined with the faceplates below
local draw_backs                   -- controls' own backgrounds, defined above draw_controls
local draw_footer                  -- the panel's foot: lock and preset bar, defined above P.draw

function P.grv_label(win) return Tr.label(win) end

local function trace_msg(ctx, dl, x, y, w, h, text, text2)
  W.push_small(ctx)
  local tw_, th = ImGui.CalcTextSize(ctx, text)
  local ty = y + (h - th * (text2 and 2 or 1)) * 0.5
  ImGui.DrawList_AddText(dl, x + (w - tw_) * 0.5, ty, C.COL.header_dim, text)
  if text2 then
    local tw2 = ImGui.CalcTextSize(ctx, text2)
    ImGui.DrawList_AddText(dl, x + (w - tw2) * 0.5, ty + th, C.COL.header_dim, text2)
  end
  W.pop_small(ctx)
end

-- The far edge -- the one away from the meter -- fades into the panel,
-- so the trace reads as coming out of the bar rather than as a box beside
-- it. `fade` is that edge's side: "left" or "right".
-- Two stages, so it eases out rather than stopping at a hard line: the
-- outer part goes from solid panel to half, the inner from half to clear.
local FADE_W = 110
local function trace_fade(dl, x, y, w, h, side)
  local fw = math.min(FADE_W, w * 0.5)
  local f1 = fw * 0.4                       -- the solid-to-half stage
  local top, bot = bg_at(y), bg_at(y + h)
  local t0, b0 = U.with_alpha(top, 0), U.with_alpha(bot, 0)
  local th, bh = U.with_alpha(top, 0x80), U.with_alpha(bot, 0x80)
  if side == "right" then
    W.hgrad4(dl, x + w - fw, y - 1, x + w - f1, y + h + 1, t0, th, bh, b0)
    W.hgrad4(dl, x + w - f1, y - 1, x + w + 1, y + h + 1, th, top, bot, bh)
  else
    W.hgrad4(dl, x - 1, y - 1, x + f1, y + h + 1, top, th, bh, bot)
    W.hgrad4(dl, x + f1, y - 1, x + fw, y + h + 1, th, t0, b0, bh)
  end
end

local function draw_trace(ctx, dl, x, y, w, h, track, fx, meter, range, est, gr, req, fade)
  ImGui.DrawList_AddRectFilled(dl, x, y, x + w, y + h, 0x00000038, 2.0)
  ImGui.DrawList_AddRect(dl, x, y, x + w, y + h, U.with_alpha(C.COL.knob_ring, 0x90), 2.0, 0, 1.0)
  local function done() trace_fade(dl, x, y, w, h, fade) end

  -- the window menu, and a way to close the trace that isn't the meter
  ImGui.SetCursorScreenPos(ctx, x, y)
  ImGui.InvisibleButton(ctx, "grv##" .. fx.guid, w, h, ImGui.ButtonFlags_MouseButtonRight)
  local pop = "grvwin##" .. fx.guid
  if ImGui.IsItemClicked(ctx, ImGui.MouseButton_Right) then ImGui.OpenPopup(ctx, pop) end
  W.tip(ctx, "grv##" .. fx.guid, "Right-click: window", ImGui.IsItemHovered(ctx), false)
  if ImGui.BeginPopup(ctx, pop) then
    ImGui.TextDisabled(ctx, "Window")
    local cur = meter.win or C.GRV_DEFAULT
    for _, wv in ipairs(C.GRV_WINDOWS) do
      if ImGui.MenuItem(ctx, P.grv_label(wv), nil, wv == cur) then req.grv_window = wv end
    end
    ImGui.Separator(ctx)
    if ImGui.MenuItem(ctx, "Close the trace") then
      St.set_gr_open(fx.guid, false); TP.invalidate()
    end
    ImGui.EndPopup(ctx)
  end

  Tr.want(track)
  local pw = math.max(1, math.floor(w - 4))
  local d, m1, m2 = Tr.columns(track, fx, meter, est, gr, pw)
  if not d then
    trace_msg(ctx, dl, x, y, w, h, m1, m2)
    return done()
  end
  local sc, n, beat = d.sc, d.beats, d.beats ~= nil

  local ix0, ix1 = x + 2, x + w - 2
  local mid, hh = y + h * 0.5, (h - 6) * 0.5
  local top, gh = y + 2, h - 4

  -- beat lines
  if beat then
    for b = 1, n - 1 do
      local bx = math.floor(ix0 + pw * b / n) + 0.5
      ImGui.DrawList_AddLine(dl, bx, y + 1, bx, y + h - 1, U.with_alpha(C.COL.knob_ring, 0x60), 1.0)
    end
  end
  ImGui.DrawList_AddLine(dl, ix0, mid, ix1, mid, U.with_alpha(C.COL.knob_ring, 0x50), 1.0)

  local in_col  = U.with_alpha(C.COL.header_dim, 0x45)
  local out_col = U.with_alpha(C.COL.value, 0xa8)
  local gr_col  = W.gr_fill_col(est)
  local fill    = U.with_alpha(gr_col, 0x24)
  local gx, gy, gn = {}, {}, 0
  for px = 0, pw - 1 do
    local mn, mx, ip, g = d.mn[px + 1], d.mx[px + 1], d.ip[px + 1], d.g[px + 1]
    local xx = ix0 + px + 0.5
    if ip > 0 then
      local e = math.min(1, ip / sc) * hh
      ImGui.DrawList_AddLine(dl, xx, mid - e, xx, mid + e, in_col, 1.0)
    end
    local y0 = mid - math.min(1, mx / sc) * hh
    local y1 = mid - math.max(-1, mn / sc) * hh
    if y1 - y0 < 1 then y0, y1 = mid - 0.5, mid + 0.5 end
    ImGui.DrawList_AddLine(dl, xx, y0, xx, y1, out_col, 1.0)
    if g then
      local gyy = top + math.min(1, math.max(0, g) / range) * gh
      if gyy > top + 0.5 then ImGui.DrawList_AddLine(dl, xx, top, xx, gyy, fill, 1.0) end
      gn = gn + 1; gx[gn], gy[gn] = xx, gyy
    end
  end

  for i = 1, gn - 1 do
    ImGui.DrawList_AddLine(dl, gx[i], gy[i], gx[i + 1], gy[i + 1], gr_col, 1.6)
  end

  done()
  -- the window, in the corner by the meter, clear of the fade
  W.push_small(ctx)
  local lbl = P.grv_label(meter.win)
  local lw = ImGui.CalcTextSize(ctx, lbl)
  local lx = (fade == "right") and (x + 4) or (x + w - lw - 4)
  ImGui.DrawList_AddText(dl, lx, y + h - 13, C.COL.header_dim, lbl)
  W.pop_small(ctx)
end

-- The gain-reduction meter, and -- when it's opened out -- its trace to
-- the left of it, `tw` wide. Returns the width used, 0 when there's no
-- reading to show.
local function draw_meter(ctx, dl, x, y, w, h, track, fx, meter, tw_, req)
  local gr = T.gain_reduction(track, fx.addr)
  if not gr then return 0 end
  local now = reaper.time_precise()
  -- meter.range is the MINIMUM: the scale steps up a ladder if the plugin
  -- pulls down harder than that, so a meter set for gentle bus compression
  -- still reads truthfully when something slams.
  local peak, range = W.gr_state(fx.guid, gr, now, meter.range)
  local est = T.gr_estimated(track, fx.addr, fx.guid)
  local zst = est and TP.cal_status(track, fx.guid) or nil
  local bx, by, bw, bh = W.gr_meter(ctx, dl, x, y, w, h, gr, peak, range, est, zst == 0)
  -- The trace sits flush against the bar and ends where the bar ends, over
  -- the room P.width set aside beside the meter's column.
  if tw_ and tw_ > 0 and bx then
    if C.METER_SIDE == "right" then
      local tx0 = x - C.PANEL_PAD - tw_
      draw_trace(ctx, dl, tx0, by, bx - tx0, bh, track, fx, meter, range, est, gr, req, "left")
    else
      local tx1 = x + w + C.PANEL_PAD + tw_
      draw_trace(ctx, dl, bx + bw, by, tx1 - (bx + bw), bh, track, fx, meter, range, est, gr, req, "right")
    end
  end

  ImGui.SetCursorScreenPos(ctx, x, y)
  ImGui.InvisibleButton(ctx, "gr##" .. fx.guid, w, h,
    ImGui.ButtonFlags_MouseButtonLeft | ImGui.ButtonFlags_MouseButtonRight)
  if ImGui.IsItemClicked(ctx, ImGui.MouseButton_Left) then
    St.toggle_gr_open(fx.guid)
    TP.invalidate()
  end
  W.tip(ctx, "gr##" .. fx.guid,
    ("Gain reduction%s\n%.2f dB now, peak %.2f\nscale 0 to %g dB%s\n%s")
    :format(est and " (measured, estimated)" or "", gr, peak, range,
            (range > (meter.range or 0)) and "  (expanded)" or "",
            St.is_gr_open(fx.guid) and "Click to close the trace" or "Click for a trace")
    .. (est and ("\n\nMeasured by the track's TS_TrackProbe from the audio in\n" ..
                 "and out.\n" .. TP.cal_text(TP.cal_status(track, fx.guid))) or ""),
    ImGui.IsItemHovered(ctx), false)
  return w
end


-- WET. REAPER's own per-plugin wet/dry mix, the one in the FX window's
-- top corner -- every plugin has it, whether or not the plugin has a mix
-- control of its own. Its parameter index is asked for by name (":wet").
-- REAPER puts it after the plugin's own parameters, so its index moves
-- whenever the plugin's parameter count does (ReaEQ adding or removing a
-- band): the cached index is kept only while that count stays the same.
local wet_idx, wet_n = {}, {}
local function wet_param(track, fx)
  local n = reaper.TrackFX_GetNumParams(track, fx.addr)
  local p = wet_idx[fx.guid]
  if p == nil or wet_n[fx.guid] ~= n then
    p = false
    if reaper.TrackFX_GetParamFromIdent then
      local i = reaper.TrackFX_GetParamFromIdent(track, fx.addr, ":wet")
      if i and i >= 0 then p = i end
    end
    wet_idx[fx.guid], wet_n[fx.guid] = p, n
  end
  return p or nil
end

-- A plugin's input and output meters, from the probe's tap on it: input
-- hard left of the panel, output hard right, so the panel reads the way
-- the audio flows. `lx` and `rx` are the two columns' left edges. Returns
-- true when it drew them.
local function draw_io(ctx, dl, lx, rx, y, w, h, track, fx, enabled)
  local lv = TP.levels(track, fx.guid)
  if not lv then return false end
  local key = "io" .. fx.guid
  local tip
  if lv.old then
    -- An older probe, still running from before the update: nothing to read.
    W.io_bar(ctx, dl, lx, y, w, h, key .. "i", -150, nil, "?")
    W.io_bar(ctx, dl, rx, y, w, h, key .. "o", -150, nil, "?")
    tip = "This track's TS_TrackProbe is an older version that doesn't measure\n" ..
          "levels. Reopen the project (or remove and re-add the probes) to\n" ..
          "load the new one."
  else
    local byp = not enabled
    local out_pk  = byp and -150 or lv.out_pk
    local out_rms = byp and -150 or lv.out_rms
    local in_hold = W.level_peak(key .. "i", lv.in_pk, reaper.time_precise())
    local itxt, otxt, ocol = W.io_readouts(lv, byp, in_hold)
    W.io_bar(ctx, dl, lx, y, w, h, key .. "i", lv.in_pk, lv.in_rms, itxt, C.COL.header_dim)
    W.io_bar(ctx, dl, rx, y, w, h, key .. "o", out_pk, out_rms, otxt, ocol)
    local function f(v) return (v and v > -149) and ("%.1f"):format(v) or "-inf" end
    tip = ("Input   peak %s   RMS %s dBFS\nOutput  peak %s   RMS %s dBFS\n%s")
      :format(f(lv.in_pk), f(lv.in_rms), f(not byp and lv.out_pk or nil), f(not byp and lv.out_rms or nil),
              byp and "Bypassed"
              or ((lv.in_rms > -70) and ("Change %+.1f dB (output RMS minus input RMS)")
                  :format(lv.out_rms - lv.in_rms) or "No signal coming in"))
      .. "\n\nMeasured by the track's TS_TrackProbe pair."
  end
  for _, c in ipairs({ { lx, "ioi##" }, { rx, "ioo##" } }) do
    ImGui.SetCursorScreenPos(ctx, c[1], y)
    ImGui.InvisibleButton(ctx, c[2] .. fx.guid, w, h, ImGui.ButtonFlags_MouseButtonRight)
    W.tip(ctx, c[2] .. fx.guid, tip, ImGui.IsItemHovered(ctx), false)
  end
  return true
end

local function draw_header(ctx, dl, x, y, w, track, fx, index, enabled, req)
  local h = C.HEADER_H
  local dragging = req.is_drag_source
  -- A plugin can read as bypassed for either of two independent reasons:
  -- its own enabled flag is off, or the whole chain is (T.chain_bypassed,
  -- I_FXEN) -- the latter doesn't touch any one FX's own enabled state, so
  -- without this a panel would keep its plain header even while every FX
  -- on the track, itself included, is silently doing nothing. Only the
  -- tint follows the chain state here: `enabled` itself stays exactly what
  -- it was (this FX's own flag), since that's still what the bypass button
  -- toggles and what its tooltip and icon state describe.
  local tint_bypassed = (not enabled) or T.chain_bypassed(track)
  ImGui.DrawList_AddRectFilled(dl, x, y, x + w, y + h,
    dragging and C.COL.header_drag
      or (req.offline and C.COL.header_bg_off)
      or (tint_bypassed and C.COL.header_bg_byp or C.COL.header_bg), 0)
  ImGui.DrawList_AddLine(dl, x, y + h, x + w, y + h, C.COL.panel_border, 1.0)

  local btn = C.ICON_SIZE
  local gap = 2
  -- collapse, bypass, float, menu
  local n_btn = 4
  local btn_x = x + w - (btn + gap) * n_btn - 2

  -- The wet %, centred in the header: dim at 100%, in the accent colour
  -- when it's anything else, so a plugin mixed back stands out. Only when
  -- the name keeps a useful width to its left and it clears the buttons.
  local wet_p, wet_v, wet_txt, wet_w, wet_x = wet_param(track, fx), 1, nil, 0, nil
  if wet_p then
    wet_v = reaper.TrackFX_GetParam(track, fx.addr, wet_p) or 1
    wet_txt = ("%d%%"):format(math.floor(wet_v * 100 + 0.5))
    local ww = ImGui.CalcTextSize(ctx, wet_txt) + 6
    local wx = x + (w - ww) * 0.5
    if wx - (x + 30) >= 40 and wx + ww <= btn_x - 4 then wet_w, wet_x = ww, wx end
  end

  -- index chip
  local chip = tostring(index)
  local tw, th = ImGui.CalcTextSize(ctx, chip)
  ImGui.DrawList_AddText(dl, x + 5, y + (h - th) * 0.5, C.COL.header_dim, chip)

  -- The name area is the drag handle. It sits under the text so the whole
  -- label is grabbable -- anywhere in the chain, containers included.
  local name_x = x + 5 + tw + 6
  local name_w = math.max(8, (wet_x or btn_x) - name_x - 4)
  ImGui.SetCursorScreenPos(ctx, name_x, y)
  ImGui.InvisibleButton(ctx, "hdr##" .. fx.guid, name_w, h,
    ImGui.ButtonFlags_MouseButtonLeft | ImGui.ButtonFlags_MouseButtonRight)
  local hdr_hovered = ImGui.IsItemHovered(ctx)

  if ImGui.IsItemActive(ctx) and ImGui.IsMouseDown(ctx, ImGui.MouseButton_Left) then
    -- x and y are output slots in the Lua API and must be passed as
    -- nil; the button is the FOURTH argument, not the second.
    local dx = ImGui.GetMouseDragDelta(ctx, nil, nil, ImGui.MouseButton_Left)
    if math.abs(dx) >= C.DRAG_THRESHOLD then req.begin_drag = true end
    ImGui.SetMouseCursor(ctx, ImGui.MouseCursor_ResizeEW)
  end

  -- Hovering the header gives you the name in full. Panel headers are
  -- narrow and a long plugin name loses its tail exactly where the
  -- version number lives, which is the part you were squinting at. Where
  -- it sits -- the containers it's in, whether it runs in parallel -- goes
  -- underneath.
  if hdr_hovered then
    local full = U.clean_fx_name(fx.name)
    if fx.alias then full = fx.alias .. "\n" .. full end
    local fmt  = U.fx_format(fx.name)
    local ven  = U.fx_vendor(fx.name)
    if ven and ven ~= "" then full = full .. "\n" .. ven end
    if fmt and fmt ~= "" then
      full = full .. ((ven and ven ~= "") and "   \u{00B7} " or "\n") .. fmt
    end
    local _, where = T.where(fx)
    if where then full = full .. "\n\nIn container: " .. where end
    if (fx.index or 0) > 0 and (fx.parallel or 0) ~= 0 then
      full = full .. (where and "\n" or "\n\n") .. "Runs in parallel with the one before it" ..
        (fx.parallel == 2 and ", MIDI merged" or "")
    end
    W.tip(ctx, "hdr##" .. fx.guid, full, true, false)
  end
  if ImGui.IsItemClicked(ctx, ImGui.MouseButton_Right) then req.open_menu = true end
  if hdr_hovered and ImGui.IsMouseDoubleClicked(ctx, ImGui.MouseButton_Left) then
    req.toggle_collapse = true
  end

  local name = U.fx_label(fx)
  local nw, nh = ImGui.CalcTextSize(ctx, name)
  if nw > name_w then
    local k = #name
    while k > 1 do
      k = k - 1
      local t = name:sub(1, k) .. "."
      nw = ImGui.CalcTextSize(ctx, t)
      if nw <= name_w then name = t break end
    end
  end
  ImGui.DrawList_AddText(dl, name_x, y + (h - nh) * 0.5,
    enabled and C.COL.header_text or C.COL.header_dim, name)

  if wet_w > 0 then
    local wx = wet_x
    ImGui.SetCursorScreenPos(ctx, wx, y)
    ImGui.InvisibleButton(ctx, "wet##" .. fx.guid, wet_w, h)
    local hov = ImGui.IsItemHovered(ctx)
    local full = wet_v >= 0.995
    local _, th2 = ImGui.CalcTextSize(ctx, wet_txt)
    ImGui.DrawList_AddText(dl, wx + 3, y + (h - th2) * 0.5,
      full and (hov and C.COL.header_text or C.COL.header_dim) or C.COL.accent, wet_txt)
    W.tip(ctx, "wet##" .. fx.guid,
      ("Wet %s \u{2014} REAPER's own mix for this plugin\nClick for a slider"):format(wet_txt),
      hov, false)
    if ImGui.IsItemClicked(ctx, ImGui.MouseButton_Left) then
      ImGui.OpenPopup(ctx, "wetpop##" .. fx.guid)
    end
    if ImGui.BeginPopup(ctx, "wetpop##" .. fx.guid) then
      ImGui.TextDisabled(ctx, "Wet")
      ImGui.SetNextItemWidth(ctx, 160)
      local ch, nv = ImGui.SliderDouble(ctx, "##wet", wet_v * 100, 0, 100, "%.0f%%")
      if ch then reaper.TrackFX_SetParam(track, fx.addr, wet_p, nv / 100) end
      ImGui.EndPopup(ctx)
    end
  end

  local function at(i) ImGui.SetCursorScreenPos(ctx, btn_x + (btn + gap) * i, y + 3) end

  at(0)
  if W.icon_button(ctx, "col##" .. fx.guid, "collapse", btn, false,
      "Collapse to a bar (or double-click the name)") then
    req.toggle_collapse = true
  end

  at(1)
  if W.icon_button(ctx, "byp##" .. fx.guid, "power", btn, not enabled,
      enabled and "Bypass" or "Bypassed \u{2014} click to enable",
      C.COL.bypass_on) then
    req.toggle_bypass = true
  end

  at(2)
  local floating = T.is_floating(track, fx.addr)
  if W.icon_button(ctx, "flt##" .. fx.guid, "float", btn, floating,
      floating and "Close the plugin's window" or "Open the plugin's window",
      C.COL.float_on) then
    req.toggle_float = true
  end

  at(3)
  if W.icon_button(ctx, "mnu##" .. fx.guid, "menu", btn, false, "Panel menu") then
    req.open_menu = true
  end
end

-- A collapsed panel: a narrow bar with the name running down it, plus the
-- two controls worth reaching without expanding -- bypass and float.
local function draw_collapsed(ctx, dl, x, y, w, h, track, fx, enabled, req, meter)
  local btn = C.ICON_SIZE
  local cx = x + w * 0.5

  ImGui.SetCursorScreenPos(ctx, cx - btn * 0.5, y + 4)
  if W.icon_button(ctx, "xcol##" .. fx.guid, "expand", btn, false, "Expand") then
    req.toggle_collapse = true
  end

  ImGui.SetCursorScreenPos(ctx, cx - btn * 0.5, y + 4 + btn + 3)
  if W.icon_button(ctx, "xbyp##" .. fx.guid, "power", btn, not enabled,
      enabled and "Bypass" or "Bypassed \u{2014} click to enable",
      C.COL.bypass_on) then
    req.toggle_bypass = true
  end

  ImGui.SetCursorScreenPos(ctx, cx - btn * 0.5, y + 4 + (btn + 3) * 2)
  local floating = T.is_floating(track, fx.addr)
  if W.icon_button(ctx, "xflt##" .. fx.guid, "float", btn, floating,
      floating and "Close the plugin's window" or "Open the plugin's window",
      C.COL.float_on) then
    req.toggle_float = true
  end

  -- oversampled: the lit switch under them, so a folded plugin still says so
  local rows = 3
  local os_st = T.os_state(track, fx)
  if os_st.lit then
    P.os_switch(ctx, cx - W.os_width(ctx, os_st.lit) * 0.5, y + 4 + (btn + 3) * 3, btn,
                track, fx, os_st)
    rows = 4
  end

  local text_y = y + 4 + (btn + 3) * rows + 4
  local avail = h - (text_y - y) - 4
  local name = U.fx_label(fx)

  -- Collapsed, the meter is the whole point: a folded-down chain still
  -- shows which compressor is working. It takes the lower half and the
  -- name takes what's left.
  if meter then
    local m_h = math.max(40, math.floor(avail * 0.55))
    local m_y = y + h - 4 - m_h
    draw_meter(ctx, dl, x + 4, m_y, w - 8, m_h, track, fx, meter)
    avail = (m_y - text_y) - 4
  end

  W.vertical_text(ctx, dl, cx, text_y, name,
    enabled and C.COL.header_text or C.COL.header_dim, math.max(0, avail))

  -- the whole bar is a grab handle and a right-click target
  ImGui.SetCursorScreenPos(ctx, x, y)
  ImGui.InvisibleButton(ctx, "cbar##" .. fx.guid, w, h,
    ImGui.ButtonFlags_MouseButtonLeft | ImGui.ButtonFlags_MouseButtonRight)
  W.tip(ctx, "cbar##" .. fx.guid, name, ImGui.IsItemHovered(ctx), false)
  if ImGui.IsItemClicked(ctx, ImGui.MouseButton_Right) then req.open_menu = true end
  if ImGui.IsItemHovered(ctx) and ImGui.IsMouseDoubleClicked(ctx, ImGui.MouseButton_Left) then
    req.toggle_collapse = true
  end
  if ImGui.IsItemActive(ctx) and ImGui.IsMouseDown(ctx, ImGui.MouseButton_Left) then
    -- x and y are output slots in the Lua API and must be passed as
    -- nil; the button is the FOURTH argument, not the second.
    local dx = ImGui.GetMouseDragDelta(ctx, nil, nil, ImGui.MouseButton_Left)
    if math.abs(dx) >= C.DRAG_THRESHOLD then req.begin_drag = true end
  end
end

-- ---------------------------------------------------------------------
-- body
-- ---------------------------------------------------------------------

-- A shape's outline as a path, its corners rounded (radius `r`, less where
-- an edge is too short for it): each corner is an arc from the incoming
-- edge's tangent point to the outgoing one's.
local function sgn(v) return (v > 0 and 1) or (v < 0 and -1) or 0 end

-- Brushed grain, the faceplate's (see draw_plate): a faint light line
-- every 3 px and a faint dark one every 7, lighter on a dark surface.
-- The lines are counted from `y0`, so sections and backgrounds in one grid
-- share one grain. `spans(y)` gives the x ranges a line at height y may
-- cover, as a flat { a1, b1, a2, b2 ... } list.
local function grain(dl, bg, y0, ya, yb, spans)
  local light = U.is_light(bg)
  local hi, lo = light and 0xffffff09 or 0xffffff04, light and 0x00000007 or 0x0000000b
  local function lines(col, step, off)
    local ly = y0 + off + math.ceil((ya - y0 - off) / step) * step
    while ly <= yb do
      local sp = spans(ly)
      for k = 1, #sp, 2 do
        ImGui.DrawList_AddLine(dl, sp[k], ly + 0.5, sp[k + 1], ly + 0.5, col, 1.0)
      end
      ly = ly + step
    end
  end
  lines(hi, 3, 2); lines(lo, 7, 4)
end

-- Where a horizontal line at `y` is inside a shape's loops (outer and
-- holes, flat point lists offset by ox): the even-odd rule along the line,
-- against the vertical edges -- every edge of a traced shape is upright or
-- level.
local function loop_spans(loops, ox, y)
  local xs = {}
  for _, p in ipairs(loops) do
    local n = #p
    for i = 1, n, 2 do
      local j = (i + 2 > n) and 1 or i + 2
      local ya, yb = p[i + 1], p[j + 1]
      if p[i] == p[j] and ((ya <= y and y < yb) or (yb <= y and y < ya)) then xs[#xs + 1] = ox + p[i] end
    end
  end
  table.sort(xs)
  return xs
end

-- The same, kept `m` px clear of every edge, so the grain stays inside the
-- rounded corners: a line's spans at y, less what isn't inside at y - m
-- and y + m too, each end then pulled in by m.
local function inner_spans(loops, ox, oy, y, m)
  local function at(yy) return loop_spans(loops, ox, yy - oy) end
  local a, b, c = at(y), at(y - m), at(y + m)
  local out = {}
  for i = 1, #a, 2 do
    local lo, hi = a[i], a[i + 1]
    -- clip [lo, hi] against each of b's and c's spans in turn
    local cur = { lo, hi }
    for _, other in ipairs({ b, c }) do
      local nxt = {}
      for k = 1, #cur, 2 do
        for q = 1, #other, 2 do
          local l, h = math.max(cur[k], other[q]), math.min(cur[k + 1], other[q + 1])
          if h > l then nxt[#nxt + 1] = l; nxt[#nxt + 1] = h end
        end
      end
      cur = nxt
    end
    for k = 1, #cur, 2 do
      if cur[k + 1] - cur[k] > 2 * m then out[#out + 1] = cur[k] + m; out[#out + 1] = cur[k + 1] - m end
    end
  end
  return out
end
P._inner_spans = inner_spans    -- for the tests

local function back_path(dl, ox, oy, pts, r)
  local n = #pts // 2
  for m = 1, n do
    local pm = (m - 2) % n + 1
    local nm = m % n + 1
    local px, py = pts[2 * m - 1], pts[2 * m]
    local qx, qy = pts[2 * pm - 1], pts[2 * pm]
    local sx, sy = pts[2 * nm - 1], pts[2 * nm]
    local ax, ay = sgn(px - qx), sgn(py - qy)
    local bx, by = sgn(sx - px), sgn(sy - py)
    local rr = math.min(r, (math.abs(px - qx) + math.abs(py - qy)) / 2,
                           (math.abs(sx - px) + math.abs(sy - py)) / 2)
    local cx, cy = px - ax * rr + bx * rr, py - ay * rr + by * rr
    local a0 = math.atan(-by, -bx)
    local d = math.atan(ay, ax) - a0
    while d > math.pi do d = d - 2 * math.pi end
    while d < -math.pi do d = d + 2 * math.pi end
    ImGui.DrawList_PathArcTo(dl, ox + cx, oy + cy, rr, a0, a0 + d, 4)
  end
end

-- What a shape sits on: its section's faceplate, if the control it starts
-- from is in one, else the panel's own colour.
local function back_base(lay, item)
  if item and item.sec then
    local kind, pl = P.section_style(lay.sections[item.sec].by)
    if kind == "plate" then return pl.bg end
  end
  return C.COL.panel_bg
end

-- A background's key for joining: what it is and whether it's brushed,
-- so a brushed aluminium and a plain one stay two shapes.
function P.back_key(ctl)
  local kind, pl = P.back_style(ctl.back)
  if not kind then return nil end
  local br = M.part_brushed(kind, pl, ctl.brush)
  local mt = M.part_metal(kind, ctl.metal)
  return ctl.back .. (br and "/b" or "") .. (mt and "/m" or ""), br, mt
end

-- The metallic flake inside a traced shape: the shape cut into bands at
-- every corner's height, each band's insides (by the even-odd rule) filled
-- with the flake, tiled from the grid's origin so joined shapes line up.
local function flake_shape(ctx, dl, gx0, gy0, loops, light)
  local ys = {}
  for _, p in ipairs(loops) do for i = 2, #p, 2 do ys[#ys + 1] = p[i] end end
  table.sort(ys)
  for i = 1, #ys - 1 do
    local ya, yb = ys[i], ys[i + 1]
    if yb - ya > 0.5 then
      local xs = loop_spans(loops, gx0, (ya + yb) / 2)
      for k = 1, #xs - 1, 2 do
        W.flake_rect(ctx, dl, xs[k] + 1, gy0 + ya, xs[k + 1] - 1, gy0 + yb, light, gx0, gy0)
      end
    end
  end
end

draw_backs = function(ctx, dl, gx0, gy0, lay)
  local rects, owner, brushed, metal = {}, {}, {}, {}
  local function take(it)
    local k, br, mt = P.back_key(it.ctl)
    if k and it.sx then
      rects[#rects + 1] = { it.sx, it.y, it.sx + it.sw, it.y + hy(it.h), k }
      owner[#rects] = it
      brushed[k], metal[k] = br, mt
    end
  end
  for _, it in ipairs(lay.items) do take(it) end
  for _, sp in ipairs(lay.spacers or {}) do take(sp) end
  if #rects == 0 then return end
  local gaps = {}
  for _, g in ipairs(lay.gaps or {}) do gaps[#gaps + 1] = { g.x, g.x + g.w } end
  for _, sh in ipairs(TL.shapes(rects, gaps, 2)) do
    -- the control it starts from: the first of its key whose middle is in it
    local from
    for k, r in ipairs(rects) do
      if r[5] == sh.key and TL.inside(sh.outer, (r[1] + r[3]) / 2, (r[2] + r[4]) / 2) then from = owner[k] break end
    end
    local base = back_base(lay, from)
    local kind, pl = P.back_style((sh.key:gsub("/[bm]", "")))
    local fill, edge
    if kind == "plate" then
      fill, edge = pl.bg, pl.border
    else
      fill = U.is_light(base) and mix(base, 0x000000ff, 0.10) or mix(base, 0xffffffff, 0.05)
      edge = 0x00000040
    end
    back_path(dl, gx0, gy0, sh.outer, 4)
    ImGui.DrawList_PathFillConcave(dl, fill)
    -- a hole shows what's under the shape again
    for _, h in ipairs(sh.holes) do
      back_path(dl, gx0, gy0, h, 4)
      ImGui.DrawList_PathFillConcave(dl, base)
    end
    local loops = { sh.outer }
    for _, h in ipairs(sh.holes) do loops[#loops + 1] = h end
    if metal[sh.key] then flake_shape(ctx, dl, gx0, gy0, loops, U.is_light(fill)) end
    if brushed[sh.key] then
      local ya, yb = math.huge, -math.huge
      for k = 2, #sh.outer, 2 do ya = math.min(ya, sh.outer[k]); yb = math.max(yb, sh.outer[k]) end
      grain(dl, fill, gy0, gy0 + ya, gy0 + yb, function(ly) return inner_spans(loops, gx0, gy0, ly, 2) end)
    end
    back_path(dl, gx0, gy0, sh.outer, 4)
    ImGui.DrawList_PathStroke(dl, edge, ImGui.DrawFlags_Closed, 1.0)
    for _, h in ipairs(sh.holes) do
      back_path(dl, gx0, gy0, h, 4)
      ImGui.DrawList_PathStroke(dl, edge, ImGui.DrawFlags_Closed, 1.0)
    end
  end
end

-- `panel_h` is the panel's FULL height, header included -- the same value
-- P.width() was given, so the column count here can't disagree with the
-- width the panel was allotted.
-- The faceplate and extent of the panel being drawn (see draw_plate).
local cur_bg = { plate = nil, y = 0, h = 1 }

-- Whether REAPER's parameter modulation is switched on for a parameter
-- (LFO, audio control signal, MIDI or parameter link all hang off it).
-- Read once and kept until the project changes -- switching modulation on
-- or off is an edit like any other, so REAPER's change count moves -- with
-- a slow re-read as a backstop for anything that doesn't move it.
local mod_cache, mod_count, mod_at = {}, nil, 0
local MOD_BACKSTOP = 5
function P.mod_on(track, fx, p)
  local now = reaper.time_precise()
  local cc = reaper.GetProjectStateChangeCount(0)
  if cc ~= mod_count or now - mod_at > MOD_BACKSTOP then
    mod_cache, mod_count, mod_at = {}, cc, now
  end
  local k = fx.guid .. ":" .. p
  local v = mod_cache[k]
  if v == nil then
    local ok, s = reaper.TrackFX_GetNamedConfigParm(track, fx.addr, ("param.%d.mod.active"):format(p))
    v = ok and tonumber(s) == 1 or false
    mod_cache[k] = v
  end
  return v
end
function P.forget_mod(fx, p) mod_cache[fx.guid .. ":" .. p] = nil end

local function draw_controls(ctx, dl, x, y, w, panel_h, track, fx, layout, key, req, meter, io)
  local controls = layout.controls or {}
  local lock = M.locked(layout)
  local lay = P.layout(controls, panel_h, lock)
  local h = panel_h - C.HEADER_H - P.footer_h()
  local scroll = P.scrolls(lay, panel_h, lock)

  local grid_x0 = x + C.PANEL_PAD
  local grid_w  = w - C.PANEL_PAD * 2
  -- Input and output meters take the two outside edges: in at the far
  -- left, out at the far right. Everything else sits between them.
  if io then
    local ok = draw_io(ctx, dl, grid_x0, grid_x0 + grid_w - C.IO_COL_W,
                       y + C.PANEL_PAD, C.IO_COL_W, h - C.PANEL_PAD * 2,
                       track, fx, T.get_enabled(track, fx.addr))
    if ok then
      grid_x0 = grid_x0 + C.IO_COL_W + C.PANEL_PAD
      grid_w  = grid_w - (C.IO_COL_W + C.PANEL_PAD) * 2
    end
  end
  if meter then
    local mx = (C.METER_SIDE == "right")
      and (grid_x0 + grid_w - C.METER_COL_W)
      or  grid_x0
    local trace = St.is_gr_open(fx.guid) and C.GRV_W or 0
    local used = draw_meter(ctx, dl, mx, y + C.PANEL_PAD, C.METER_COL_W,
                            h - C.PANEL_PAD * 2, track, fx, meter, trace, req)
    if used > 0 then
      -- the trace, when open, sits on the grid's side of the meter
      if trace > 0 then used = used + trace + C.PANEL_PAD end
      grid_w = grid_w - used - C.PANEL_PAD
      if C.METER_SIDE ~= "right" then grid_x0 = grid_x0 + used + C.PANEL_PAD end
    end
  end

  -- a locked grid too tall to fit scrolls, its scrollbar at the right
  local reg_x0 = grid_x0
  if scroll then grid_w = grid_w - (C.SCROLL_W + 2) end
  local reg_w = grid_w

  -- A grid narrower than the room it has is CENTRED in it. The panel has
  -- a minimum width, so a plugin with a single column of parameters would
  -- otherwise sit hard against the left edge with all the empty air on the
  -- right, which reads as a layout that went wrong rather than as a small
  -- plugin.
  if lay.width < grid_w then
    grid_x0 = grid_x0 + (grid_w - lay.width) * 0.5
  end

  if #lay.items == 0 and #lay.rules == 0 then
    local msg = "no layout"
    local tw, th = ImGui.CalcTextSize(ctx, msg)
    ImGui.DrawList_AddText(dl, x + w * 0.5 - tw * 0.5, y + h * 0.5 - th - 6,
      C.COL.empty_text, msg)
    local msg2 = "click to set up"
    local tw2 = ImGui.CalcTextSize(ctx, msg2)
    ImGui.DrawList_AddText(dl, x + w * 0.5 - tw2 * 0.5, y + h * 0.5 + 2,
      C.COL.empty_text, msg2)
    ImGui.SetCursorScreenPos(ctx, x, y)
    if ImGui.InvisibleButton(ctx, "empty##" .. fx.guid, w, h) then
      req.open_editor = true
    end
    return
  end

  local gx0 = grid_x0
  local gy0 = y + C.GRID_TOP_PAD
  local nparams = reaper.TrackFX_GetNumParams(track, fx.addr)

  -- Locked, and taller than the panel: the grid goes in a child window of
  -- its own that scrolls up and down -- the meters beside it stay put. It
  -- reaches a few pixels past the grid each side, for the sections' and
  -- backgrounds' edges. The wheel turns a control under the pointer and
  -- scrolls anywhere else (see the end of this function).
  if scroll then
    local cx = reg_x0 - 4
    ImGui.SetCursorScreenPos(ctx, cx, y)
    ImGui.PushStyleColor(ctx, ImGui.Col_ChildBg, 0)
    ImGui.PushStyleColor(ctx, ImGui.Col_ScrollbarBg, 0)
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_ScrollbarSize, C.SCROLL_W)
    local ok = ImGui.BeginChild(ctx, "grid##" .. fx.guid, reg_w + C.SCROLL_W + 2 + 4, h, 0,
      ImGui.WindowFlags_NoScrollWithMouse)
    ImGui.PopStyleVar(ctx)
    ImGui.PopStyleColor(ctx, 2)
    if not ok then return end
    dl = ImGui.GetWindowDrawList(ctx)
    -- the whole grid's height, so there's something to scroll
    ImGui.Dummy(ctx, 1, C.GRID_TOP_PAD + lay.height + C.PANEL_PAD)
    gy0 = gy0 - ImGui.GetScrollY(ctx)
  end

  -- Styled sections first, behind everything: an inset
  -- just darker than the plate it's on (lighter on a dark one), with a
  -- shadowed top edge and a lit bottom one, or a faceplate of its own.
  -- They reach a few pixels into the divider gaps on either side.
  for _, s in ipairs(lay.sections or {}) do
    local kind, pl = P.section_style(s.by)
    local x1, y1 = gx0 + s.x - 3, gy0 - 3
    local x2, y2 = gx0 + s.x + s.w + 3, gy0 + lay.height + 2
    local function grained(fill)
      if M.part_metal(kind, s.by.metal) then
        W.flake_rect(ctx, dl, x1 + 1, y1 + 1, x2 - 1, y2 - 1, U.is_light(fill), gx0, gy0)
      end
      if M.part_brushed(kind, pl, s.by.brush) then
        grain(dl, fill, gy0, y1 + 2, y2 - 3, function() return { x1 + 2, x2 - 2 } end)
      end
    end
    if kind == "plate" then
      ImGui.DrawList_AddRectFilled(dl, x1, y1, x2, y2, pl.bg, 4.0)
      grained(pl.bg)
      ImGui.DrawList_AddRect(dl, x1, y1, x2, y2, pl.border, 4.0, 0, 1.0)
      ImGui.DrawList_AddLine(dl, x1 + 4, y1 + 1, x2 - 4, y1 + 1, 0xffffff18, 1.0)
    else
      local base = C.COL.panel_bg
      local fill = U.is_light(base) and mix(base, 0x000000ff, 0.10) or mix(base, 0xffffffff, 0.05)
      ImGui.DrawList_AddRectFilled(dl, x1, y1, x2, y2, fill, 4.0)
      grained(fill)
      ImGui.DrawList_AddLine(dl, x1 + 3, y1 + 0.5, x2 - 3, y1 + 0.5, 0x00000050, 1.0)
      ImGui.DrawList_AddLine(dl, x1 + 3, y2 - 0.5, x2 - 3, y2 - 0.5, 0xffffff18, 1.0)
      ImGui.DrawList_AddRect(dl, x1, y1, x2, y2, 0x00000030, 4.0, 0, 1.0)
    end
  end

  -- Dividers first, so a control's hit area is never shadowed by a rule.
  -- (an across fader running over one cuts it: lay.rule_cuts)
  for ri, rx in ipairs(lay.rules) do
    local y = 2
    local cuts = lay.rule_cuts and lay.rule_cuts[ri]
    if cuts then
      table.sort(cuts, function(a, b) return a[1] < b[1] end)
      for _, cut in ipairs(cuts) do
        if cut[1] > y then
          ImGui.DrawList_AddLine(dl, gx0 + rx, gy0 + y, gx0 + rx, gy0 + cut[1], C.COL.knob_ring, 1.0)
        end
        if cut[2] > y then y = cut[2] end
      end
    end
    if lay.height - 2 > y then
      ImGui.DrawList_AddLine(dl, gx0 + rx, gy0 + y,
        gx0 + rx, gy0 + lay.height - 2, C.COL.knob_ring, 1.0)
    end
  end

  -- Controls' own backgrounds, over the sections and the rules: controls
  -- side by side or stacked with the same background join into one shape
  -- (TS_CV_Tiles), across a divider too. Recomputed every frame from
  -- where the layout put them, so they follow every resize and reorder.
  draw_backs(ctx, dl, gx0, gy0, lay)

  -- The layout pass placed everything; this only has to draw it. Note the
  -- index into `controls` is tracked separately, because dividers take a
  -- place in the list but not in the grid.
  local ci = 0
  for _, item in ipairs(lay.items) do
    local ctl = item.ctl
    -- find this control's index in the source list for the context menu
    repeat ci = ci + 1 until controls[ci] == ctl or ci > #controls
    local i = ci

    ImGui.SetCursorScreenPos(ctx, gx0 + item.x, gy0 + item.y)

    -- a control on its own background's faceplate, or else its
    -- section's, takes that plate's inks
    local sec_saved
    local bkind, bpl = P.back_style(ctl.back)
    if bkind == "plate" then
      sec_saved = push_plate(bpl)
    elseif item.sec then
      local kind, pl = P.section_style(lay.sections[item.sec].by)
      if kind == "plate" then sec_saved = push_plate(pl) end
    end

    local id = ("c%d##%s_%d"):format(i, fx.guid, i)

    if ctl.type == "half_gap" then
      -- Nothing to draw -- it's pure vertical spacing for whatever
      -- comes after it (see P.layout). Column flow never lands one
      -- here at all (P.layout leaves it out of lay.items entirely,
      -- same as a divider); this guard only matters if C.FLOW is ever
      -- "row", where half_gap isn't a stagger and P.layout falls back
      -- to placing it like any other control -- without this, THAT
      -- would fall through to "out of range parameter" below, since a
      -- half_gap carries no real param.
    elseif ctl.type == "blank" then
      local _, _, act = W.blank(ctx, id)
      if act.right_click then req.ctx_control = i end

    elseif not ctl.param or ctl.param < 0 or ctl.param >= nparams then
      -- The layout refers to a parameter this instance doesn't have --
      -- a plugin updated, or two different plugins sharing a name.
      --
      -- The cursor is already at this item's own cell -- SetCursorScreenPos
      -- above, from item.x/item.y, positions every item in lay.items the
      -- same way regardless of which branch below actually draws it; this
      -- branch must not try to recompute a position from `col`/`row`, which
      -- are local to P.layout's own loop and don't exist here.
      local px, py = ImGui.GetCursorScreenPos(ctx)
      ImGui.InvisibleButton(ctx, id, C.CELL_W, C.CELL_H)
      W.tip(ctx, "oob" .. id, ("parameter %s is out of range for this plugin")
        :format(tostring(ctl.param)), ImGui.IsItemHovered(ctx), false)
      if ImGui.IsItemClicked(ctx, ImGui.MouseButton_Right) then req.ctx_control = i end
      local tw = ImGui.CalcTextSize(ctx, "!")
      ImGui.DrawList_AddText(dl, px + C.CELL_W * 0.5 - tw * 0.5,
        py + C.CELL_H * 0.5 - 6, C.COL.warn, "!")

    else
      local p        = ctl.param
      -- Reverse is applied at the BOUNDARY and nowhere else: the value
      -- is flipped on the way in and flipped back on the way out, so
      -- every widget, tooltip and default below deals in what the
      -- control shows and the plugin only ever sees its own numbers.
      -- Knobs, stepped knobs and toggles only -- a combo's steps are
      -- positions in the plugin's own scale, and mirroring those means
      -- mirroring the list, which is a different job. A stepped knob
      -- turns like a knob (see W.knob's step_norm), not a list, so it
      -- reverses the same way a plain one does.
      local rev      = ctl.invert and (ctl.type == "knob" or ctl.type == "toggle"
                                        or ctl.type == "stepped" or ctl.type == "dual"
                                        or ctl.type == "xy")
      local raw      = reaper.TrackFX_GetParamNormalized(track, fx.addr, p) or 0
      local value    = rev and (1 - raw) or raw
      local shown    = U.fmt_value(track, fx.addr, p)
      local _, pname = reaper.TrackFX_GetParamName(track, fx.addr, p, "")
      local label    = M.display_name(key, p, ctl.label, pname,
                                      ctl.live or layout.live)
      -- Just the value. The plugin's name is on the header two
      -- centimetres away and the parameter index is an implementation
      -- detail -- neither is what you're hovering to find out.
      local tip      = shown
      local modded   = P.mod_on(track, fx, p)
      if modded then tip = (tip or "") .. "\nParameter modulation on" end

      local changed, nv, act
      if ctl.type == "xy" or ctl.type == "dual" then
        -- two parameters: an XY pad's X and Y, a concentric knob's ring and
        -- inner knob (Dual<n>); one not chosen yet, or out of range, shows ?
        local p2 = ctl.param2
        local ok2 = p2 ~= nil and p2 >= 0 and p2 < nparams
        local raw2 = ok2 and (reaper.TrackFX_GetParamNormalized(track, fx.addr, p2) or 0) or 0
        local rev2 = ctl.invert2 and true or false
        if rev2 then raw2 = 1 - raw2 end
        local shown2 = ok2 and U.fmt_value(track, fx.addr, p2) or "?"
        local name1 = M.display_name(key, p, nil, pname, ctl.live or layout.live)
        local name2 = "?"
        if ok2 then
          local _, pn2 = reaper.TrackFX_GetParamName(track, fx.addr, p2, "")
          name2 = M.display_name(key, p2, nil, pn2, ctl.live or layout.live)
        end
        local mod2 = ok2 and P.mod_on(track, fx, p2) or false
        local name = (ctl.label and ctl.label ~= "") and ctl.label or (name1 .. " / " .. name2)
        local tip2 = name1 .. ": " .. (shown or "") .. "\n" .. name2 .. ": " .. shown2
          .. (ok2 and "" or "\n(right-click to choose its second parameter)")
          .. ((modded or mod2) and "\nParameter modulation on" or "")
        local c1, v1, c2, v2
        if ctl.type == "xy" then
          local under = cur_bg.plate and cur_bg.plate.bg or C.COL.panel_bg
          c1, v1, c2, v2, act = W.xypad(ctx, id, gx0 + item.x, gy0 + item.y,
            item.pw or hx(item.w), hy(item.h), value, raw2, name,
            { cap = W.cap_col(ctl.cap), dim = not T.get_enabled(track, fx.addr),
              mod = modded or mod2, shown_x = shown, shown_y = shown2, tip = tip2, under = under })
          -- a double-click puts both back: Y here, X below
          if act.double_click and ok2 then
            reaper.TrackFX_SetParamNormalized(track, fx.addr, p2, U.param_mid_norm(track, fx.addr, p2))
          end
        else
          c1, v1, c2, v2, act = W.dual_knob(ctx, id, name, value, raw2,
            { size = (P.item_size(item) == "large") and "large" or nil, cap = W.cap_col(ctl.cap),
              dim = not T.get_enabled(track, fx.addr), mod1 = modded, mod2 = mod2,
              shown1 = shown, shown2 = shown2, tip = tip2 })
          -- a double-click puts back the one under the pointer: the inner
          -- knob's here, the ring's below
          if act.double_click == "inner" then
            if ok2 then
              reaper.TrackFX_SetParamNormalized(track, fx.addr, p2, U.param_mid_norm(track, fx.addr, p2))
            end
            act.double_click = nil
          end
        end
        if c2 and ok2 then
          reaper.TrackFX_SetParamNormalized(track, fx.addr, p2, rev2 and (1 - v2) or v2)
          TP.touched(track, fx.guid)
        end
        changed, nv = c1, v1
      elseif ctl.type == "toggle" then
        -- your names for its two states, when you've given them
        local st = M.state_text(key, p, raw, shown)
        local lit = W.lit_col(ctl.cap)
        local size = P.item_size(item)
        local said = M.button_text(key, p, raw, shown)
        changed, nv, act = W.toggle(ctx, id, label, value, st,
          { tooltip = (size == "small") and (label .. ": " .. (st or "")) or st,
            text = said or ((size == "small") and label or nil),
            on_col = lit, size = size, style = ctl.style, mod = modded })
      elseif ctl.type == "combo" and item.kind == "buttons" then
        -- its choices as buttons: the plugin's own names (button_choices)
        local list = button_choices(track, fx.addr, p, key, ctl.nbtn)
        local lit = W.lit_col(ctl.cap)
        changed, nv, act = W.button_row(ctx, id, label, value, list,
          { dir = ctl.buttons, n = ctl.nbtn, w = hx(item.w), h = hy(item.h),
            tooltip = tip, on_col = lit, style = ctl.style, mod = modded })
      elseif ctl.type == "combo" then
        changed, nv, act = W.combo(ctx, id, label, value, shown,
          step_norm(track, fx.addr, p, key),
          { tooltip     = tip,
            steps       = combo_steps(track, fx.addr, p, key),
            open_now    = pending_open[id],
            mod         = modded })
        pending_open[id] = nil
        if act and act.want_steps then
          -- scan right now, and open the list on the next frame once it
          -- has something to show
          if combo_steps(track, fx.addr, p, key, true) then
            pending_open[id] = true
          end
        end
      elseif ctl.type == "fader" then
        -- A fader's item already claims a whole column at the panel's
        -- full height (see P.layout) -- SetCursorScreenPos above put the
        -- cursor at its top-left for that reason, but W.fader wants an
        -- explicit rect of its own rather than the ambient cursor, so
        -- it's recomputed here from the same item.x/item.y. Centred at
        -- C.FADER_W within the column, the same width the channel
        -- strip's own fader uses, rather than stretched to the full
        -- CELL_W -- a fader needs a defined width to grab, not a whole
        -- cell. `value` is the plain normalized parameter (rev already
        -- applied above), not REAPER's volume taper -- there is no
        -- taper to speak of for an arbitrary plugin parameter, and
        -- W.fader doesn't care what 0..1 means, only that the caller
        -- does.
        local look = (ctl.style or ctl.cap) and { style = ctl.style, cap = W.cap_col(ctl.cap) } or nil
        local unity = ctl.bipolar and 0.5 or nil
        local under = cur_bg.plate and cur_bg.plate.bg or C.COL.panel_bg
        if P.fader_kind(ctl) == "column" then
          local cw = hx(item.w)
          local fw = ctl.thin and 14 or C.FADER_W
          local fx0 = gx0 + item.x + (cw - fw) * 0.5
          local fy0 = gy0 + item.y
          changed, nv, act = W.fader(ctx, id, fx0, fy0, fw, lay.height,
            value, label .. "   " .. shown, unity, false, look)
          if modded then
            -- top right of the fader's column, against the panel under it
            W.mod_corner(dl, fx0 + fw, fy0, 6, under)
          end
        else
          -- placed among the controls: its name over it, its value under
          changed, nv, act = W.param_fader(ctx, id, gx0 + item.x, gy0 + item.y,
            item.pw or hx(item.w), hy(item.h), value, label, shown,
            { dir = ctl.dir, thin = ctl.thin, unity = unity, look = look,
              tip = label .. "   " .. shown, mod = modded and under or nil })
        end
      elseif ctl.type == "stepped" then
        local size = P.item_size(item)
        local st = step_norm(track, fx.addr, p, key)
        -- Same dial as a plain knob, just quantised to the parameter's own
        -- step grid -- see W.knob's own header for why this needs nothing
        -- from the (separate, sweep-and-cache) combo_steps machinery: the
        -- step SIZE is a cheap, un-cached native read, and the readout
        -- text above is already the plugin's own formatted value for any
        -- control type, choice name included.
        changed, nv, act = W.knob(ctx, id, label, value, shown,
          { bipolar = ctl.bipolar, tooltip = tip, dim = not T.get_enabled(track, fx.addr),
            step_norm = st, mod = modded,
            style = ctl.style, cap = W.cap_col(ctl.cap), size = size,
            scale = P.knob_scale(track, fx, p, key, ctl, size, rev, st) })
      else
        local size = P.item_size(item)
        changed, nv, act = W.knob(ctx, id, label, value, shown,
          { bipolar = ctl.bipolar, tooltip = tip, dim = not T.get_enabled(track, fx.addr),
            style = ctl.style, cap = W.cap_col(ctl.cap), size = size, mod = modded,
            scale = P.knob_scale(track, fx, p, key, ctl, size, rev, nil) })
      end

      if act and act.double_click then
        local d = U.param_mid_norm(track, fx.addr, p)
        nv, changed = rev and (1 - d) or d, true
      end
      if changed then
        reaper.TrackFX_SetParamNormalized(track, fx.addr, p,
          rev and (1 - nv) or nv)
        -- A measured plugin relearns its zero point when it's changed.
        TP.touched(track, fx.guid)
      end
      if act and act.right_click then req.ctx_control = i end
    end

    -- No remove badge on a parameter cell. A control is taken off a panel
    -- from the setup dialog or the cell's own right-click menu, and a
    -- permanent x over every knob buys nothing for that -- unlike a send,
    -- which has nowhere else to be removed from.
    if sec_saved then pop_plate(sec_saved) end
  end

  -- half-gaps: nothing to draw, but a right-click on one opens its menu
  -- (it can have a background)
  for _, sp in ipairs(lay.spacers or {}) do
    local si
    for k, c in ipairs(controls) do if c == sp.ctl then si = k break end end
    if si then
      ImGui.SetCursorScreenPos(ctx, gx0 + sp.sx, gy0 + sp.y)
      local _, _, act = W.blank(ctx, ("g%d##%s_%d"):format(si, fx.guid, si), sp.sw, hy(sp.h))
      if act.right_click then req.ctx_control = si end
    end
  end

  if scroll then
    -- the wheel, when no control under the pointer took it this frame
    if ImGui.IsWindowHovered(ctx) and not W.wheel_taken() then
      local wheel = ImGui.GetMouseWheel(ctx)
      if wheel ~= 0 then
        ImGui.SetScrollY(ctx, ImGui.GetScrollY(ctx) - wheel * C.CELL_H * 0.5)
        W.take_wheel()
      end
    end
    ImGui.EndChild(ctx)
  end
end

-- ---------------------------------------------------------------------
-- faceplates
-- ---------------------------------------------------------------------
-- A panel with a faceplate (C.PLATES) is drawn with the palette's panel
-- colours swapped for the plate's own for the length of its draw, and put
-- back after. Everything inside -- header, labels, values, icons, scale
-- ticks, dividers -- already reads those palette entries, so one swap
-- retints the lot and no widget needs to know faceplates exist. The
-- tooltip and anything else painted after the panels sees the theme again.
-- Bypass keeps its own header colour: a bypassed plugin must still look
-- bypassed on any faceplate.
local PLATE_INKS = {
  panel_bg = "bg", panel_border = "border", header_bg = "head",
  header_text = "text", header_dim = "dim", label = "text", value = "dim",
  icon = "dim", knob_ring = "tick", empty_text = "dim",
}
-- (icon_hot is left alone: a hovered header button lights a dark square
-- behind its icon on every faceplate, so the hot icon stays the theme's
-- light one.)

push_plate = function(pl)
  local saved = {}
  for k, f in pairs(PLATE_INKS) do
    saved[k] = C.COL[k]
    C.COL[k] = pl[f]
  end
  return saved
end

pop_plate = function(saved)
  for k, v in pairs(saved) do C.COL[k] = v end
end

mix = function(col, to, t)
  local out = 0
  for _, sh in ipairs({ 24, 16, 8 }) do
    local a, b = (col >> sh) & 0xff, (to >> sh) & 0xff
    out = out | (math.floor(a + (b - a) * t + 0.5) << sh)
  end
  return out | (col & 0xff)
end

-- The plate itself: flat, or with the 3D effect a gentle top-lit gradient
-- -- real faceplates catch the light from above, and a flat fill reads as
-- a colour rather than a surface -- and its finish: a metallic flake and
-- sheen, a fine brushed grain (the layout's choice, or aluminium's own),
-- both or neither. The grain is lighter on a dark plate, where white lines
-- show far more. The border is drawn over it afterwards and tidies the
-- corners.
-- The background at height `yy` of the panel being drawn: what draw_plate
-- painted there (gradient included), or the flat panel colour. The trace's
-- fade blends into this.
-- (cur_bg is declared further up, before draw_controls, which uses it too)
bg_at = function(yy)
  local pl = cur_bg.plate
  if not (pl and C.EFFECT_3D) then return C.COL.panel_bg end
  local sh = pl.sheen or 1
  local split = cur_bg.y + cur_bg.h * 0.4
  if yy <= split then
    local t = math.max(0, math.min(1, (yy - cur_bg.y) / math.max(1, split - cur_bg.y)))
    return mix(mix(pl.bg, 0xffffffff, 0.08 * sh), pl.bg, t)
  end
  local t = math.max(0, math.min(1, (yy - split) / math.max(1, cur_bg.y + cur_bg.h - split)))
  return mix(pl.bg, mix(pl.bg, 0x000000ff, 0.12 * sh), t)
end

local function draw_plate(ctx, dl, x, y, w, h, pl, brushed, metal)
  ImGui.DrawList_AddRectFilled(dl, x, y, x + w, y + h, pl.bg, 3.0)
  -- the light falling on it (3D effect)
  if C.EFFECT_3D then
    local split = y + h * 0.4
    local sh = pl.sheen or 1
    W.vgrad(dl, x + 1, y + 1, x + w - 1, split, mix(pl.bg, 0xffffffff, 0.08 * sh), pl.bg)
    W.vgrad(dl, x + 1, split, x + w - 1, y + h - 1, pl.bg, mix(pl.bg, 0x000000ff, 0.12 * sh))
  end
  -- its surface: metallic, brushed, both or neither
  if metal then
    W.flake_rect(ctx, dl, x + 1, y + 1, x + w - 1, y + h - 1, U.is_light(pl.bg), x, y)
    W.metal_sheen(dl, x, y, w, h)
  end
  if brushed then
    local light = U.is_light(pl.bg)
    local hi, lo = light and 0xffffff09 or 0xffffff04, light and 0x00000007 or 0x0000000b
    for ly = y + 2, y + h - 2, 3 do
      ImGui.DrawList_AddLine(dl, x + 1, ly + 0.5, x + w - 1, ly + 0.5, hi, 1.0)
    end
    for ly = y + 4, y + h - 2, 7 do
      ImGui.DrawList_AddLine(dl, x + 1, ly + 0.5, x + w - 1, ly + 0.5, lo, 1.0)
    end
  end
end

-- OFFLINE. An unloaded plugin has no parameters to show: its body says so
-- and offers to bring it back. The header and foot take their offline
-- colour (draw_header, draw_footer).
local function draw_offline(ctx, dl, x, y, w, h, track, fx)
  local cx = x + w * 0.5
  local t1, t2 = "Offline", "not loaded"
  local w1, h1 = ImGui.CalcTextSize(ctx, t1)
  local w2 = ImGui.CalcTextSize(ctx, t2)
  local ty = y + math.max(8, h * 0.35)
  ImGui.DrawList_AddText(dl, cx - w1 * 0.5, ty, C.COL.header_text, t1)
  ImGui.DrawList_AddText(dl, cx - w2 * 0.5, ty + h1 + 2, C.COL.header_dim, t2)
  local bt = "Bring online"
  local bw, bh = ImGui.CalcTextSize(ctx, bt)
  bw, bh = bw + 14, bh + 8
  local bx, by = math.floor(cx - bw * 0.5), math.floor(ty + h1 * 2 + 12)
  ImGui.SetCursorScreenPos(ctx, bx, by)
  if ImGui.InvisibleButton(ctx, "online##" .. fx.guid, bw, bh) then
    T.set_offline(track, fx.addr, false, U.fx_label(fx))
  end
  local hot = ImGui.IsItemHovered(ctx)
  ImGui.DrawList_AddRectFilled(dl, bx, by, bx + bw, by + bh,
    hot and C.COL.header_bg_off or C.COL.toggle_off, 3.0)
  ImGui.DrawList_AddRect(dl, bx + 0.5, by + 0.5, bx + bw - 0.5, by + bh - 0.5, C.COL.header_bg_off, 3.0, 0, 1.0)
  ImGui.DrawList_AddText(dl, bx + 7, by + 4, C.COL.header_text, bt)
end

-- OVERSAMPLING. The switch in a panel's foot, beside the lock: REAPER's
-- own per-plugin oversampling (TS_CV_FXTree), lit with the factor the
-- plugin runs at while its setting is what raises the rate. Click for Off
-- and REAPER's "up to" rates, each with what it would mean here. Outlined
-- instead for a plugin oversampled from around it (its container, or the
-- whole chain), or set to a rate REAPER already runs at.
function P.os_tip(st)
  local lines = {}
  local rate = st.rate
  if st.lit and st.n > 0 then
    lines[1] = ("Oversampled by REAPER (%s): %dx here."):format(T.os_label(st.n, rate):lower(), st.lit)
  elseif st.n > 0 then
    lines[1] = ("Set to oversample %s, which REAPER already runs at: no effect here."):format(
      T.os_label(st.n, rate):lower())
  else
    lines[1] = "Oversampling: off."
  end
  for _, o in ipairs(st.outer or {}) do
    lines[#lines + 1] = ("Inside %s, oversampled %s."):format(o.what, T.os_label(o.n, rate):lower())
  end
  lines[#lines + 1] = "Click to change."
  return table.concat(lines, "\n")
end

function P.os_switch(ctx, x, y, h, track, fx, st)
  ImGui.SetCursorScreenPos(ctx, x, y)
  if W.os_badge(ctx, "os##" .. fx.guid, st.lit, h, P.os_tip(st),
                C.COL.header_text, C.COL.header_bg, st.faint) then
    ImGui.OpenPopup(ctx, "osmenu##" .. fx.guid)
  end
  if ImGui.BeginPopup(ctx, "osmenu##" .. fx.guid) then
    ImGui.TextDisabled(ctx, "Oversampling")
    P.os_choices(ctx, track, fx.addr, st, "plugin")
    ImGui.EndPopup(ctx)
  end
end

-- Off and REAPER's "up to" rates for one plugin or container (`st` from
-- T.os_state), as menu items, each with what it means at the rate REAPER
-- runs at: the factor, or "no effect" when it's no higher than the rate
-- (or than what's around it already gives).
function P.os_choices(ctx, track, addr, st, what)
  for _, o in ipairs(st.outer or {}) do
    ImGui.TextDisabled(ctx, ("Inside %s, oversampled %s."):format(o.what, T.os_label(o.n, st.rate):lower()))
  end
  local floor = math.max(st.rate or 0, st.top or 0)
  for _, n in ipairs(T.OS_CHOICES) do
    local hint
    if n > 0 then
      local hz = T.os_cap(n, st.rate)
      if st.rate then
        hint = (hz > floor) and ("%dx"):format(T.os_factor(hz, st.rate)) or "no effect"
      end
    end
    if ImGui.MenuItem(ctx, T.os_label(n, st.rate), hint, st.n == n) and st.n ~= n then
      T.set_os_shift(track, addr, n, what)
    end
  end
  ImGui.TextDisabled(ctx, "Takes effect when playback next starts.")
end

-- The panel's foot: the layout lock at the hard left -- a padlock, lit
-- while locked -- and the preset bar beside it when that's on. Clicking
-- the lock asks the caller (req.toggle_lock) to lock the layout at the
-- rows it has now, or unlock it. A ReaEQ panel is a canvas, not a grid,
-- so it has nothing to lock.
draw_footer = function(ctx, dl, x, y, w, h, track, fx, layout, avail_h, is_eq, req)
  local btn = C.ICON_SIZE
  local os_st = T.os_state(track, fx)
  local osw = W.os_width(ctx, os_st.lit)
  local lw = (is_eq and 0 or (btn + 3)) + osw + 3
  -- offline: no presets to load into it, and the foot takes the header's
  -- offline colour
  if C.PRESET_BAR and not req.offline then
    PU.footer(ctx, dl, x, y, w, h, track, fx, lw)
  else
    ImGui.DrawList_AddRectFilled(dl, x + 1, y, x + w - 1, y + h - 1,
      req.offline and C.COL.header_bg_off or C.COL.header_bg, 2.5,
      ImGui.DrawFlags_RoundCornersBottom)
    ImGui.DrawList_AddLine(dl, x, y, x + w, y, C.COL.panel_border, 1.0)
  end
  P.os_switch(ctx, x + 3 + (is_eq and 0 or (btn + 3)), y + (h - btn) * 0.5, btn,
              track, fx, os_st)
  if is_eq then return end
  local rows = M.locked(layout)
  local bx, by = x + 3, y + (h - btn) * 0.5
  ImGui.SetCursorScreenPos(ctx, bx, by)
  -- locked, it's lit: the padlock in the foot's own colour on a block of
  -- the foot's text colour, which stands out on every faceplate (a fixed
  -- accent colour vanishes on some)
  if W.icon_button(ctx, "lock##" .. fx.guid, rows and "none" or "unlock", btn, false,
      rows and ("Layout locked at %d rows: no edits, and it scrolls rather than\n" ..
                "rearranging when the panel is too short. Click to unlock."):format(rows)
           or "Lock this layout: no more edits, and the controls stay where\n" ..
              "they are when the panel is resized (it scrolls if too short).\n" ..
              "Meters can still be switched on and off.",
      nil, nil) then
    -- (false to unlock: `rows and false or ...` would never give false)
    if rows then req.toggle_lock = false else req.toggle_lock = P.rows_for(avail_h) end
  end
  if rows then
    local hot = ImGui.IsItemHovered(ctx)
    ImGui.DrawList_AddRectFilled(dl, bx, by, bx + btn, by + btn,
      hot and C.COL.header_dim or C.COL.header_text, 2.5)
    W.draw_lock(dl, bx, by, btn, C.COL.header_bg, false, hot and C.COL.header_dim or C.COL.header_text)
  end
end

-- ---------------------------------------------------------------------
-- public
-- ---------------------------------------------------------------------

-- Draws one panel at the current cursor position and advances past it.
-- Returns a `req` table of things the caller should act on this frame:
--   toggle_bypass, toggle_float, open_menu, open_editor, ctx_control
function P.draw(ctx, track, fx, layout, key, avail_h, index, is_drag_source)
  local req = { is_drag_source = is_drag_source }
  local collapsed = St.is_collapsed(fx.guid)
  local is_eq = RQ.is_eq(key)
  -- ReaComp's panel is its own canvas, with its own meters beside it
  local is_rc = RC.is_comp(key)
  -- ReaEQ has nothing to meter -- T.reports_gr would already say no for
  -- it, but skipping the check entirely is one fewer FX-parameter scan
  -- for the one plugin type that's never going to answer yes.
  local meter = (not is_eq and not is_rc) and M.meter_of(layout) or nil
  if meter and not T.reports_gr(track, fx.addr, fx.guid) then meter = nil end
  local io = (not is_rc) and P.has_io(track, fx, layout)
  local w = P.width(layout.controls or {}, avail_h, collapsed, meter ~= nil, key, io,
                    St.is_gr_open(fx.guid), M.locked(layout))

  local pn_x, pn_y = ImGui.GetCursorPos(ctx)
  local ok = ImGui.BeginChild(ctx, "pnl##" .. fx.guid, w, avail_h, 0,
    ImGui.WindowFlags_NoScrollbar | ImGui.WindowFlags_NoScrollWithMouse)
  if ok then
    local dl = ImGui.GetWindowDrawList(ctx)
    local x, y = ImGui.GetWindowPos(ctx)
    local ww, wh = ImGui.GetWindowSize(ctx)
    local enabled = T.get_enabled(track, fx.addr)
    local plate = C.plate_of(layout.plate)
    local saved = plate and push_plate(plate)
    cur_bg.plate, cur_bg.y, cur_bg.h = plate, y, wh

    if is_drag_source then
      ImGui.DrawList_AddRectFilled(dl, x, y, x + ww, y + wh, C.COL.header_drag, 3.0)
    elseif plate then
      draw_plate(ctx, dl, x, y, ww, wh, plate, M.brushed(layout, plate), M.metal(layout, plate))
    else
      ImGui.DrawList_AddRectFilled(dl, x, y, x + ww, y + wh, C.COL.panel_bg, 3.0)
    end
    ImGui.DrawList_AddRect(dl, x, y, x + ww, y + wh,
      is_drag_source and C.COL.drop_marker or C.COL.panel_border, 3.0, 0,
      is_drag_source and 2.0 or 1.0)

    -- the 3D effect: knobs and buttons cast shadows, the edges catch the light
    W.hw = (not is_drag_source and C.EFFECT_3D) and C.METAL_K or 0

    req.offline = T.get_offline(track, fx.addr)
    if collapsed then
      if req.offline and not is_drag_source then
        ImGui.DrawList_AddRectFilled(dl, x + 1, y + 1, x + ww - 1, y + wh - 1, C.COL.header_bg_off, 3.0)
      end
      draw_collapsed(ctx, dl, x, y, ww, wh, track, fx, enabled, req, meter)
    else
      draw_header(ctx, dl, x, y, ww, track, fx, index, enabled, req)
      local fh = P.footer_h()
      if req.offline then
        draw_offline(ctx, dl, x, y + C.HEADER_H, ww, wh - C.HEADER_H - fh, track, fx)
      elseif is_eq then
        -- The whole body becomes the draggable-node curve canvas rather
        -- than the ordinary parameter grid: a ReaEQ panel IS the EQ view,
        -- not a grid you can optionally switch away from.
        -- With input/output meters, they take the two outside edges here
        -- too, and the canvas keeps its own width between them.
        local ex, ew = x, ww
        if io and draw_io(ctx, dl, x + C.PANEL_PAD, x + ww - C.PANEL_PAD - C.IO_COL_W,
                          y + C.HEADER_H + C.PANEL_PAD, C.IO_COL_W,
                          wh - C.HEADER_H - fh - C.PANEL_PAD * 2, track, fx, enabled) then
          ex, ew = x + C.IO_COL_W + C.PANEL_PAD, ww - (C.IO_COL_W + C.PANEL_PAD) * 2
        end
        EQP.draw(ctx, dl, ex, y + C.HEADER_H, ew, wh - C.HEADER_H - fh, track, fx, req)
      elseif is_rc and CP.draw(ctx, dl, x, y + C.HEADER_H, ww, wh - C.HEADER_H - fh, track, fx, req) then
        -- drawn: the transfer-curve canvas (one missing a parameter it
        -- needs falls through to the ordinary grid below instead)
      else
        draw_controls(ctx, dl, x, y + C.HEADER_H, ww, wh, track, fx, layout,
                      key, req, meter, io)
      end
      if fh > 0 then draw_footer(ctx, dl, x, y + wh - fh, ww, fh, track, fx, layout, avail_h, is_eq, req) end
    end
    if W.hw > 0 then W.metal_edges(dl, x, y, ww, wh, W.hw) end
    W.hw = 0
    if saved then pop_plate(saved) end
    -- ReaImGui: EndChild only when BeginChild returned true.
    ImGui.EndChild(ctx)
  else
    -- Culled: still occupy the space, or the parent's bounds
    -- never grow past it. See W.child_skipped.
    W.child_skipped(ctx, w, avail_h, pn_x, pn_y)
  end

  return w, req, collapsed
end

return P
