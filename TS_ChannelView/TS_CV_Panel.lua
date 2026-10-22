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
local FN  = require("TS_CV_Finish")
local SC  = require("TS_CV_Steps")
local St  = require("TS_CV_State")
local RQ  = require("TS_CV_ReaEQ")
local EQP = require("TS_CV_EQPanel")
local TR  = require("TS_CV_Trimmer")
local AF  = require("TS_CV_AutoFloat")
local TRP = require("TS_CV_TrimmerPanel")
local FB  = require("TS_CV_FXButtons")
local RC  = require("TS_CV_ReaComp")
local CP  = require("TS_CV_CompPanel")
local RP  = require("TS_CV_RolePanel")
local MP  = require("TS_CV_MapPanel")
local CK  = require("TS_CV_ColourPick")
local TP  = require("TS_CV_Taps")
local ML  = require("TS_CV_MidiLearn")
local PU  = require("TS_CV_PresetUI")
local Tr  = require("TS_CV_Trace")
local MD  = require("TS_CV_Mod")
local MR  = require("TS_CV_ModRack")

local P   = {}
local ImGui
local panel_at = {}

function P.attach(imgui) ImGui = imgui; EQP.attach(imgui); CP.attach(imgui); PU.attach(imgui); MP.attach(imgui); RP.attach(imgui); TRP.attach(imgui); FN.attach(imgui) end

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
  -- Top and bottom pads differ: the grid starts tight under the header
  -- so a cell's name line isn't pushed down, and keeps the full pad at
  -- the bottom.
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
-- ordinary one 2 x 2 (one whole cell), a half_gap 2 x 1, and the sizes
-- in C.SIZES whatever they say. A control too tall for the panel is
-- drawn at the ordinary size instead.
-- With every control 2 x 2 each one lands on a whole cell --
-- dev/TS_CV_LayoutFixture.lua holds reference positions for a set of
-- layouts, and TS_CV_Test.lua checks them all.
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
-- controls that is ceil(n / rows) cells. A half_gap is
-- an ordinary empty slot here; its half-step is a down-the-column idea.
local HALF_H = C.CELL_H * 0.5

-- `n` half-cells across, or down, in pixels: a whole number whenever it
-- is one, so an ordinary layout's positions stay whole pixels.
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
--   "column"  vertical and full height: it splits the sections, a column
--             wide or half of one
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

-- What makes two sections look the same: the style, the faceplate, its
-- finish and flake. Neighbouring sections that match join into one.
function P.section_key(div)
  local kind, pl = P.section_style(div)
  if not kind then return nil end
  return kind .. "|" .. (kind == "plate" and div.cap or "") .. "|"
         .. (M.part_finish(kind, pl, div.finish, div.brush) or "")
         .. (M.part_metal(kind, div.metal) and "|m" or "")
         .. (M.corners_of(div.corners) and ("|" .. div.corners) or "")
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

-- A panel with faders placed among its controls (any but a
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
  -- a page break has no place in a grid: a list that still has them (a
  -- caller that didn't go through P.pages) lays out as if they weren't there
  for _, ctl in ipairs(controls) do
    if ctl.type == "page" then
      local rest = {}
      for _, c in ipairs(controls) do if c.type ~= "page" then rest[#rest + 1] = c end end
      controls = rest
      break
    end
  end
  local rows  = lock or P.rows_for(panel_h)
  local half_rows = rows * 2
  -- faders placed among the controls: merged-cell flow (place_flow);
  -- anything else is laid out in sections and strips
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

-- ---------------------------------------------------------------------
-- pages
-- ---------------------------------------------------------------------
-- A "page" control is a page break: what follows it, up to the next
-- break, is a page of its own, and the panel shows one page at a time
-- with a tab strip under its header. Controls before the first break are
-- page 1. Dividers inside a page split its columns as usual.
-- Returns a list of { label, cap, controls, ctl }, or nil when the layout
-- has no break (an ordinary, unpaged panel); a leading break's empty
-- first page is dropped.
function P.pages(controls)
  local pages, cur, any = {}, { controls = {} }, false
  for i, ctl in ipairs(controls or {}) do
    if ctl.type == "page" then
      any = true
      pages[#pages + 1] = cur
      cur = { label = ctl.label, cap = ctl.cap, controls = {}, ctl = ctl, idx = i }
    else
      cur.controls[#cur.controls + 1] = ctl
    end
  end
  pages[#pages + 1] = cur
  if not any then return nil end
  if #pages[1].controls == 0 and not pages[1].ctl then table.remove(pages, 1) end
  for i, pg in ipairs(pages) do pg.n = i end
  return pages
end

-- A page's tab text: its name, else its number.
function P.page_label(pg)
  return (pg.label and pg.label ~= "") and pg.label or tostring(pg.n)
end

-- About how wide the tab strip needs to be: the panel is never narrower
-- than its strip. P.width has no context to measure text with, so this
-- is a guess by character count until the strip has been drawn once,
-- after which its measured width (per set of tab names) is used instead.
local TAB_PAD_X, TAB_GAP = 8, 2
local strip_measured = {}   -- joined tab names -> width the strip needed
local function tab_strip_key(pages)
  local t = {}
  for i, pg in ipairs(pages) do t[i] = P.page_label(pg) end
  return table.concat(t, "\n")
end
local function tab_strip_est(pages)
  local m = strip_measured[tab_strip_key(pages)]
  if m then return m end
  local w = C.PANEL_PAD
  for _, pg in ipairs(pages) do
    w = w + #P.page_label(pg) * 6.2 + TAB_PAD_X * 2 + TAB_GAP
  end
  return w + C.PANEL_PAD
end

-- The controls a panel shows right now: those whose Show rule (if any)
-- the plugin's current values satisfy (TS_CV_Mappings M.visible). The
-- full list is what the context menu indexes into; this is what gets
-- laid out.
function P.visible(controls, track, fx)
  if not (track and fx) then return controls or {} end
  local any = false
  for _, c in ipairs(controls or {}) do if c.show then any = true break end end
  if not any then return controls or {} end
  local base = U.plugin_key(fx.name or "")
  local shown = M.visible(controls, function(p, vname)
    if vname then return St.vvalue(fx.guid, vname, base, controls) end
    return reaper.TrackFX_GetParamNormalized(track, fx.addr, p) or 0
  end)
  return shown
end

-- A virtual control's colour (TS_CV_Mappings Virt<n>): violet, the
-- canvases' second colour, so it reads as the layout's and not the plugin's
P.VIRT_COL = 0x8a63e6ff

-- A virtual control: a button, a selector (chips or a dropdown) or a
-- knob with no parameter behind it; its setting is the instance's own
-- (TS_CV_State St.vget). Returns its act (for the right-click).
local function draw_virtual(ctx, dl, id, ctl, item, fx, controls, key)
  local name = M.vname_of(ctl)
  local base = M.split_variant(key)
  local v = St.vvalue(fx.guid, name, base, controls)
  local shown = M.vtext(ctl, v)
  local changed, nv, act
  local size = P.item_size(item)
  if ctl.type == "toggle" then
    changed, nv, act = W.toggle(ctx, id, name, v, shown,
      { tooltip = name .. ": " .. shown .. "\n(layout control)", text = shown,
        on_col = P.VIRT_COL, size = size, style = ctl.style })
  elseif ctl.type == "combo" and item.kind == "buttons" then
    local list = {}
    for i, t in ipairs(M.vchoices(ctl)) do list[i] = { norm = M.vnorm(ctl, i), text = t } end
    changed, nv, act = W.button_row(ctx, id, name, v, list,
      { dir = ctl.buttons, n = #list, w = hx(item.w), h = hy(item.h),
        tooltip = name .. ": " .. shown, on_col = P.VIRT_COL, style = ctl.style })
  elseif ctl.type == "combo" then
    local list = {}
    for i, t in ipairs(M.vchoices(ctl)) do list[i] = { norm = M.vnorm(ctl, i), text = t } end
    local n = #list
    changed, nv, act = W.combo(ctx, id, name, v, shown, (n >= 2) and (1 / (n - 1)) or nil,
      { tooltip = name .. ": " .. shown, steps = list, style = ctl.style })
  else
    changed, nv, act = W.knob(ctx, id, name, v, shown,
      { tooltip = name .. ": " .. shown .. "\n(layout control)", cap = P.VIRT_COL,
        style = ctl.style, size = size })
  end
  if act and act.double_click then nv, changed = (ctl.virtual and ctl.virtual.start) or 0, true end
  if changed and nv then
    if ctl.type ~= "knob" then nv = M.vnorm(ctl, M.vindex(ctl, nv)) end
    St.vset(fx.guid, name, nv)
    -- a REAPER action for the setting picked, when it has one (VAct<n>)
    M.run_vaction(ctl, nv)
  end
  return act
end

-- The page a panel is open at, clamped to what it has.
function P.page_of(guid, pages)
  return math.max(1, math.min(#pages, St.page(guid)))
end

-- Whether a locked panel's grid is taller than its body, and scrolls.
function P.scrolls(lay, panel_h, lock)
  if not lock then return false end
  local body = panel_h - C.HEADER_H - P.footer_h()
  return C.GRID_TOP_PAD + lay.height + C.PANEL_PAD > body
end

-- `key` is optional -- a caller drawing a plain grid needn't pass one --
-- and only matters for one thing: a ReaEQ panel isn't a grid at all, so
-- none of the layout applies to it -- it gets a fixed canvas width
-- instead. See TS_CV_EQPanel.lua.
function P.width(n_or_controls, avail_h, collapsed, has_meter, key, has_io, has_trace, lock, canvas)
  if collapsed then return C.COLLAPSED_W end
  -- the TS_CV Trimmer: its own panel, as wide as the strip's height needs
  if key and TR.is(key) then return TRP.width(avail_h) end
  -- an EQ or compressor canvas (any plugin): the canvas, and its layout's
  -- controls in columns beside it
  if canvas then
    local side = 0
    local n = type(n_or_controls) == "table" and #n_or_controls or (n_or_controls or 0)
    if n > 0 then
      side = P.width(n_or_controls, avail_h, false, false, nil, false, false, lock) - C.PANEL_PAD
    end
    -- with input/output meters: on the panel's two outside edges
    return MP.width(canvas.kind) + side + (has_io and (C.IO_COL_W + C.PANEL_PAD) * 2 or 0)
  end
  if key and RQ.is_eq(key) then
    return C.EQ_PANEL_W + (has_io and (C.IO_COL_W + C.PANEL_PAD) * 2 or 0)
  end
  -- ReaComp: its own canvas, meters included (TS_CV_CompPanel.lua)
  if key and RC.is_comp(key) then return C.RC_PANEL_W + (has_io and (C.IO_COL_W + C.PANEL_PAD) * 2 or 0) end
  local controls = n_or_controls
  if type(controls) == "number" then
    -- callers that only know the count get a plain grid, no dividers
    local n = controls
    controls = {}
    for i = 1, n do controls[i] = { type = "knob" } end
  end
  -- paged: as wide as its widest page, never narrower than its tab strip
  local pages = type(controls) == "table" and P.pages(controls) or nil
  local inner = 0
  if pages then
    local body_h = avail_h - C.TAB_STRIP_H
    for _, pg in ipairs(pages) do
      local lay = P.layout(pg.controls, body_h, lock)
      local sb = P.scrolls(lay, body_h, lock) and C.SCROLL_W + 2 or 0
      inner = math.max(inner, lay.width + sb)
    end
    inner = math.max(inner, tab_strip_est(pages) - C.PANEL_PAD * 2)
  else
    local lay = P.layout(controls, avail_h, lock)
    -- a locked grid too tall for the panel scrolls, its scrollbar beside it
    local sb = P.scrolls(lay, avail_h, lock) and C.SCROLL_W + 2 or 0
    inner = lay.width + sb
  end
  local w = math.max(C.PANEL_MIN_W, inner + C.PANEL_PAD * 2)
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
  local rg = U.range_of(p)
  local ck = table.concat({ fx.guid or key or "", p, kind, size or "medium",
                            rev and "r" or "", st and "s" or "", rg and M.range_line(rg) or "" }, "|")
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
-- it, and caches the answer (on disk too: TS_CV_Steps).
--
-- By default it won't sweep in the background while the transport is
-- rolling (C.SCAN_WHILE_PLAYING); a click on the control still does, and
-- nothing sweeps while automation is being written. Each write is queued
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

-- The rack's gain-reduction meter: across the top, `w` wide (nothing
-- reading yet: an empty bar).
function P.gr_strip_h() return C.GR_BAR_H + C.PANEL_PAD end
local function draw_meter_h(ctx, dl, x, y, w, track, fx, meter)
  local gr = T.gain_reduction(track, fx.addr) or 0
  local now = reaper.time_precise()
  local peak, range = W.gr_state(fx.guid, gr, now, meter.range)
  local est = T.gr_estimated(track, fx.addr, fx.guid)
  local zst = est and TP.cal_status(track, fx.guid) or nil
  W.gr_meter_h(ctx, dl, x, y, w, C.GR_BAR_H, gr, peak, range, est, zst == 0)
  ImGui.SetCursorScreenPos(ctx, x, y)
  ImGui.InvisibleButton(ctx, "grh##" .. fx.guid, w, C.GR_BAR_H)
  W.tip(ctx, "grh##" .. fx.guid,
    ("Gain reduction%s\n%.2f dB, peak %.2f\nScale 0 to %g dB%s")
    :format(est and " (estimated)" or "", gr, peak, range,
            (range > (meter.range or 0)) and "  (expanded)" or "")
    .. (est and ("\n\nMeasured by the probe\n" ..
                 TP.cal_text(TP.cal_status(track, fx.guid))) or ""),
    ImGui.IsItemHovered(ctx), false)
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
    ("Gain reduction%s\n%.2f dB, peak %.2f\nScale 0 to %g dB%s\n%s")
    :format(est and " (estimated)" or "", gr, peak, range,
            (range > (meter.range or 0)) and "  (expanded)" or "",
            St.is_gr_open(fx.guid) and "Click: close trace" or "Click: trace")
    .. (est and ("\n\nMeasured by the probe\n" ..
                 TP.cal_text(TP.cal_status(track, fx.guid))) or ""),
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
    -- A probe from an older version, still running: nothing to read.
    W.io_bar(ctx, dl, lx, y, w, h, key .. "i", -150, nil, "?")
    W.io_bar(ctx, dl, rx, y, w, h, key .. "o", -150, nil, "?")
    tip = "Older probe: no levels.\n" ..
          "Reopen the project to update it."
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
              or ((lv.in_rms > -70) and ("Change %+.1f dB RMS")
                  :format(lv.out_rms - lv.in_rms) or "No input signal"))
  end
  for _, c in ipairs({ { lx, "ioi##" }, { rx, "ioo##" } }) do
    ImGui.SetCursorScreenPos(ctx, c[1], y)
    ImGui.InvisibleButton(ctx, c[2] .. fx.guid, w, h, ImGui.ButtonFlags_MouseButtonRight)
    W.tip(ctx, c[2] .. fx.guid, tip, ImGui.IsItemHovered(ctx), false)
  end
  return true
end

-- ---------------------------------------------------------------------
-- header
-- ---------------------------------------------------------------------

local function draw_header(ctx, dl, x, y, w, track, fx, index, enabled, req)
  local h = C.HEADER_H
  local dragging = req.is_drag_source
  -- A plugin can read as bypassed for either of two independent reasons:
  -- its own enabled flag is off, or the whole chain is (T.chain_bypassed,
  -- I_FXEN) -- the latter doesn't touch any one FX's own enabled state, so
  -- without this a panel would keep its plain header even while every FX
  -- on the track, itself included, is silently doing nothing. Only the
  -- tint follows the chain state here: `enabled` stays this FX's own
  -- flag, since that's what the bypass button toggles and what its
  -- tooltip and icon state describe.
  local tint_bypassed = (not enabled) or T.chain_bypassed(track)
  ImGui.DrawList_AddRectFilled(dl, x, y, x + w, y + h,
    dragging and C.COL.header_drag
      or (req.offline and C.COL.header_bg_off)
      or (tint_bypassed and C.COL.header_bg_byp or C.COL.header_bg), 0)
  ImGui.DrawList_AddLine(dl, x, y + h, x + w, y + h, C.COL.panel_border, 1.0)

  local btn = C.ICON_SIZE
  local gap = 2
  -- collapse, bypass, float, menu; and a pin before float while its window
  -- is one ChannelView floated itself (View > Float plugins without controls)
  local auto = AF.is_auto(fx.guid)
  local n_btn = auto and 5 or 4
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
      full = full .. (where and "\n" or "\n\n") .. "Parallel with the previous plugin" ..
        (fx.parallel == 2 and ", MIDI merged" or "")
    end
    local rn = St.switch_rule(fx.guid)
    if rn then full = full .. ("\n\nLayout from switching rule %d"):format(rn) end
    W.tip(ctx, "hdr##" .. fx.guid, full, true, false)
  end
  if ImGui.IsItemClicked(ctx, ImGui.MouseButton_Right) then req.open_menu = true end
  if hdr_hovered and ImGui.IsMouseDoubleClicked(ctx, ImGui.MouseButton_Left) then
    req.toggle_collapse = true
  end

  -- put up by a layout switching rule (TS_CV_Mappings Switch<n>): that
  -- layout's name in a pill after the plugin's
  local rule = St.switch_rule(fx.guid)
  if rule then
    local base = U.plugin_key(fx.name or "")
    local rr = (M.switch_rules(base) or {})[rule]
    local bt = rr and (rr.layout or "Standard") or nil
    if bt then
      W.push_small(ctx)
      local bw, bh = ImGui.CalcTextSize(ctx, bt)
      local pw = math.min(bw + 10, name_w * 0.45)
      if pw >= 24 then
        local bx = name_x + name_w - pw
        local by_ = y + (h - bh - 4) * 0.5
        ImGui.DrawList_AddRectFilled(dl, bx, by_, bx + pw, by_ + bh + 4, U.with_alpha(C.COL.accent, 0x40), 3.0)
        ImGui.DrawList_PushClipRect(dl, bx, by_, bx + pw - 4, by_ + bh + 4, true)
        ImGui.DrawList_AddText(dl, bx + 5, by_ + 2, C.COL.header_text, bt)
        ImGui.DrawList_PopClipRect(dl)
        name_w = name_w - pw - 4
      end
      W.pop_small(ctx)
    end
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
      ("Wet %s\nClick: slider"):format(wet_txt),
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
  -- (the rack draws a folded panel's header too: there it unfolds)
  local folded = P.RACK and St.is_collapsed(fx.guid)
  if W.icon_button(ctx, "col##" .. fx.guid, folded and "expand" or "collapse", btn, false,
      folded and "Expand (or double-click the name)" or "Collapse (or double-click the name)") then
    req.toggle_collapse = true
  end

  at(1)
  if W.icon_button(ctx, "byp##" .. fx.guid, "power", btn, not enabled,
      enabled and "Bypass" or "Bypassed\nClick: enable",
      C.COL.bypass_on) then
    req.toggle_bypass = true
  end

  local k = 2
  if auto then
    at(k); k = k + 1
    local pinned = AF.is_pinned(fx.guid)
    if W.icon_button(ctx, "pin##" .. fx.guid, "pin", btn, pinned,
        pinned and "Pinned: its window stays open when you change track\nClick: unpin"
               or "Its window closes when you change track\nClick: pin it open",
        C.COL.float_on) then
      req.toggle_pin = true
    end
  end

  at(k)
  local floating = T.is_floating(track, fx.addr)
  if W.icon_button(ctx, "flt##" .. fx.guid, "float", btn, floating,
      floating and "Close plugin window" or "Open plugin window",
      C.COL.float_on) then
    req.toggle_float = true
  end

  at(k + 1)
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
      enabled and "Bypass" or "Bypassed\nClick: enable",
      C.COL.bypass_on) then
    req.toggle_bypass = true
  end

  ImGui.SetCursorScreenPos(ctx, cx - btn * 0.5, y + 4 + (btn + 3) * 2)
  local floating = T.is_floating(track, fx.addr)
  if W.icon_button(ctx, "xflt##" .. fx.guid, "float", btn, floating,
      floating and "Close plugin window" or "Open plugin window",
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

-- A finish over a surface (TS_CV_Finish), laid from ox, oy. Brushed falls
-- back to the drawn grain when there are no images (an older ReaImGui).
local function finish_rect(ctx, dl, key, bg, x1, y1, x2, y2, ox, oy, box)
  if not key then return end
  if FN.image(ctx, key) then
    FN.rect(ctx, dl, key, x1, y1, x2, y2, ox, oy, box)
  elseif key == "brushed" then
    grain(dl, bg, oy, y1, y2, function() return { x1, x2 } end)
  end
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

-- A shape's outline as a path, its corners rounded (radius `r`, less where
-- an edge is too short for it): each corner is an arc from the incoming
-- edge's tangent point to the outgoing one's.
local function corner_arcs(pts, r, fn)
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
    fn(cx, cy, rr, a0, d)
  end
end

local function back_path(dl, ox, oy, pts, r)
  corner_arcs(pts, r, function(cx, cy, rr, a0, d)
    ImGui.DrawList_PathArcTo(dl, ox + cx, oy + cy, rr, a0, a0 + d, r > 6 and 0 or 4)
  end)
end

-- The same outline as points, each corner's arc in a few straight pieces,
-- for laying a finish inside rounder corners.
local function rounded_poly(pts, r)
  local out = {}
  corner_arcs(pts, r, function(cx, cy, rr, a0, d)
    local k = rr > 6 and 8 or 3
    for i = 0, k do
      local a = a0 + d * i / k
      out[#out + 1] = cx + rr * math.cos(a); out[#out + 1] = cy + rr * math.sin(a)
    end
  end)
  return out
end

-- Where a line at y crosses closed outlines (even-odd), left to right.
local function poly_spans(polys, ox, y)
  local xs = {}
  for _, p in ipairs(polys) do
    local n = #p // 2
    for i = 1, n do
      local j = i % n + 1
      local x1, y1, x2, y2 = p[2 * i - 1], p[2 * i], p[2 * j - 1], p[2 * j]
      if (y1 <= y) ~= (y2 <= y) then xs[#xs + 1] = ox + x1 + (y - y1) * (x2 - x1) / (y2 - y1) end
    end
  end
  table.sort(xs)
  return xs
end
P._poly_spans, P._rounded_poly = poly_spans, rounded_poly   -- for the tests

-- The corner radius of a background or section (Corners<n>): the usual
-- slight rounding, soft, or round -- half the shorter side, so a narrow
-- one's ends are fully round, but never past ROUND_MAX, so a wide one
-- doesn't round off its controls -- on a plain rectangle; any other shape
-- is drawn soft.
local ROUND_MAX = 28
local function corner_r(corners, w, h, plain)
  if corners == "round" and plain then return math.max(4, math.min(w / 2, h / 2, ROUND_MAX)) end
  if corners == "round" or corners == "soft" then return 10 end
  return 4
end
P.corner_r = corner_r

-- What a shape sits on: its section's faceplate, if the control it starts
-- from is in one, else the panel's own colour.
local function back_base(lay, item)
  if item and item.sec then
    local kind, pl = P.section_style(lay.sections[item.sec].by)
    if kind == "plate" then return pl.bg end
  end
  return C.COL.panel_bg
end

-- A background's key for joining: what it is, its finish and flake, so a
-- brushed aluminium and a plain one stay two shapes. Also gives the finish
-- (nil: plain) and whether it has the flake.
function P.back_key(ctl)
  local kind, pl = P.back_style(ctl.back)
  if not kind then return nil end
  local fin = M.part_finish(kind, pl, ctl.finish, ctl.brush)
  local mt = M.part_metal(kind, ctl.metal)
  local cn = M.corners_of(ctl.corners)
  return ctl.back .. (fin and ("/" .. fin) or "") .. (mt and "/m" or "") .. (cn and ("/c" .. cn) or ""), fin, mt, cn
end

-- The metallic flake -- or, given `finish`, that finish -- inside a traced
-- shape: the shape cut into bands at every corner's height, each band's
-- insides (by the even-odd rule) filled, tiled from the grid's origin so
-- joined shapes line up.
local function flake_shape(ctx, dl, gx0, gy0, loops, light, finish, bg, r)
  local ys = {}
  for _, p in ipairs(loops) do for i = 2, #p, 2 do ys[#ys + 1] = p[i] end end
  -- rounder corners: thin strips where the outline curves, each laid
  -- inside the curve
  local polys
  if r and r > 4 then
    polys = {}
    for k, p in ipairs(loops) do polys[k] = rounded_poly(p, r) end
    local n = #ys
    for i = 1, n do
      for dy = -r, r, 2.5 do ys[#ys + 1] = ys[i] + dy end
    end
  end
  table.sort(ys)
  for i = 1, #ys - 1 do
    local ya, yb = ys[i], ys[i + 1]
    if yb - ya > 0.5 then
      local xs = polys and poly_spans(polys, gx0, (ya + yb) / 2) or loop_spans(loops, gx0, (ya + yb) / 2)
      for k = 1, #xs - 1, 2 do
        if finish then
          -- Bright and Satin reflect once across the whole shape
          local box
          if C.FINISH[finish] and C.FINISH[finish].stretch then
            local bx1, by1, bx2, by2 = math.huge, math.huge, -math.huge, -math.huge
            for j = 1, #loops[1], 2 do
              bx1 = math.min(bx1, loops[1][j]); bx2 = math.max(bx2, loops[1][j])
              by1 = math.min(by1, loops[1][j + 1]); by2 = math.max(by2, loops[1][j + 1])
            end
            box = { gx0 + bx1, gy0 + by1, gx0 + bx2, gy0 + by2 }
          end
          finish_rect(ctx, dl, finish, bg, xs[k] + 1, gy0 + ya, xs[k + 1] - 1, gy0 + yb, gx0, gy0, box)
        else
          W.flake_rect(ctx, dl, xs[k] + 1, gy0 + ya, xs[k + 1] - 1, gy0 + yb, light, gx0, gy0)
        end
      end
    end
  end
end

draw_backs = function(ctx, dl, gx0, gy0, lay)
  local rects, owner, finish, metal, corners = {}, {}, {}, {}, {}
  local function take(it)
    local k, fin, mt, cn = P.back_key(it.ctl)
    if k and it.sx then
      rects[#rects + 1] = { it.sx, it.y, it.sx + it.sw, it.y + hy(it.h), k }
      owner[#rects] = it
      finish[k], metal[k], corners[k] = fin, mt, cn
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
    local kind, pl = P.back_style(sh.key:match("^[^/]+"))
    local fill, edge
    if kind == "plate" then
      fill, edge = pl.bg, pl.border
    else
      fill = U.is_light(base) and mix(base, 0x000000ff, 0.10) or mix(base, 0xffffffff, 0.05)
      edge = 0x00000040
    end
    -- its corners: a plain rectangle can have fully round ends
    local bx1, by1, bx2, by2 = math.huge, math.huge, -math.huge, -math.huge
    for j = 1, #sh.outer, 2 do
      bx1 = math.min(bx1, sh.outer[j]); bx2 = math.max(bx2, sh.outer[j])
      by1 = math.min(by1, sh.outer[j + 1]); by2 = math.max(by2, sh.outer[j + 1])
    end
    local r = corner_r(corners[sh.key], bx2 - bx1, by2 - by1, #sh.outer == 8 and #sh.holes == 0)
    back_path(dl, gx0, gy0, sh.outer, r)
    ImGui.DrawList_PathFillConcave(dl, fill)
    -- a hole shows what's under the shape again
    for _, h in ipairs(sh.holes) do
      back_path(dl, gx0, gy0, h, r)
      ImGui.DrawList_PathFillConcave(dl, base)
    end
    local loops = { sh.outer }
    for _, h in ipairs(sh.holes) do loops[#loops + 1] = h end
    if finish[sh.key] then flake_shape(ctx, dl, gx0, gy0, loops, U.is_light(fill), finish[sh.key], fill, r) end
    if metal[sh.key] then flake_shape(ctx, dl, gx0, gy0, loops, U.is_light(fill), nil, nil, r) end
    back_path(dl, gx0, gy0, sh.outer, r)
    ImGui.DrawList_PathStroke(dl, edge, ImGui.DrawFlags_Closed, 1.0)
    for _, h in ipairs(sh.holes) do
      back_path(dl, gx0, gy0, h, r)
      ImGui.DrawList_PathStroke(dl, edge, ImGui.DrawFlags_Closed, 1.0)
    end
  end
end

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
    -- a link from the rack shows as its ring, not this mark: the mark is
    -- for the parameter's own LFO or audio follower set in REAPER
    if v and MD.link_of(track, fx.guid, p) then
      local function on(key)
        local ok2, s2 = reaper.TrackFX_GetNamedConfigParm(track, fx.addr, ("param.%d.%s"):format(p, key))
        return ok2 and tonumber(s2) == 1
      end
      v = on("lfo.active") or on("acs.active") or false
    end
    mod_cache[k] = v
  end
  return v
end
function P.forget_mod(fx, p) mod_cache[fx.guid .. ":" .. p] = nil end

local range_hot = {}    -- "guid:param" -> the end under the pointer

-- The ends as values (the plugin's way up, not reversed), and what
-- dragging end e to value v does.
local function link_ends(track, link)
  if link.macro then
    local from, to = MD.range(link)
    return { from, to }, function(e, v)
      local a, b = MD.range(link)
      if e == 1 then MD.set_range(track, link, v, b) else MD.set_range(track, link, a, v) end
    end
  end
  return (MD.swing_ends(track, link)), function(e, v) MD.set_swing_end(track, link, e, v) end
end

local function clamp01(v) return math.max(0, math.min(1, v)) end

-- A link's handles on a control -- on a knob's ring, or beside a fader.
-- From a macro: its range's two ends, where the control sits at 0% (the
-- first) and at 100% (the second); they can cross, to run it backwards.
-- From a modulator: the two ends of its swing, where the control is with
-- the modulator at rest and at full; they can cross (it then works the
-- other way). `pos(v)` is where value v is drawn, `val(mx, my)`
-- the value at the pointer.
local function range_ends(ctx, track, link, rev, key, pos, val)
  local ends, set_end = link_ends(track, link)
  local hot
  for e, v0 in ipairs(ends) do
    local v = clamp01(v0)
    if rev then v = 1 - v end
    local hx, hy = pos(v)
    local id = ("##rangeend%d%s"):format(e, key)
    ImGui.SetCursorScreenPos(ctx, hx - 7, hy - 7)
    ImGui.InvisibleButton(ctx, id, 14, 14)
    local hov, act = ImGui.IsItemHovered(ctx), ImGui.IsItemActive(ctx)
    if hov or act then
      hot = e
      ImGui.SetMouseCursor(ctx, ImGui.MouseCursor_Hand)
    end
    local tip
    if link.macro then
      tip = ("Value at %s of %s\nDrag: set"):format(e == 1 and "0%" or "100%", link.mod.name)
    else
      tip = ("%s swing, %s\nDrag: set"):format(link.mod.name, e == 1 and "at rest" or "at full")
    end
    W.tip(ctx, id, tip, hov and not act, false)
    if act and ImGui.IsMouseDown(ctx, ImGui.MouseButton_Left) then
      local mx, my = ImGui.GetMousePos(ctx)
      local nv = val(mx, my)
      if rev then nv = 1 - nv end
      set_end(e, nv)
    end
  end
  range_hot[key] = hot
end

-- The ends as the ring / bar draws them (clamped, reversed if need be).
local function drawn_ends(track, link, rev)
  local ends = link_ends(track, link)
  local out = {}
  for i, v in ipairs(ends) do
    v = clamp01(v)
    out[i] = rev and (1 - v) or v
  end
  return out
end

-- A link on a fader: a bar beside it over where the source can take it,
-- the live dot, and the handles.
local function fader_pos(fd, v)
  local p = fd.p0 + (fd.p1 - fd.p0) * v
  if fd.v then return fd.x1 + 5, p end
  return p, fd.y1 + 2
end
local function fader_range(ctx, dl, track, link, fd, ring, rev, key)
  local ax, ay = fader_pos(fd, ring.lo)
  local bx, by = fader_pos(fd, ring.hi)
  ImGui.DrawList_AddLine(dl, ax, ay, bx, by, U.with_alpha(ring.col, ring.hot and 0xe0 or 0x90), ring.hot and 3.0 or 2.2)
  local lx, ly = fader_pos(fd, ring.live or 0)
  ImGui.DrawList_AddCircleFilled(dl, lx, ly, 2.6, ring.col, 10)
  range_ends(ctx, track, link, rev, key,
    function(v) return fader_pos(fd, v) end,
    function(mx, my)
      local q = fd.v and my or mx
      return clamp01((q - fd.p0) / (fd.p1 - fd.p0))
    end)
  for e, v in ipairs(ring.ends or {}) do
    local hx, hy = fader_pos(fd, v)
    ImGui.DrawList_AddCircleFilled(dl, hx, hy, 3.6, C.COL.panel_bg, 12)
    ImGui.DrawList_AddCircle(dl, hx, hy, 3.6, ring.col, 12, range_hot[key] == e and 2.4 or 1.6)
  end
end

-- The tab strip under a paged panel's header: a tab per page, its name
-- under a stripe in its colour (the theme's accent unless the page break
-- was given one), the open one lifted into the body. Click a tab, or
-- wheel over the strip, to change page; right-click a tab for its colour.
local tab_menu = nil   -- { guid, page, orig } while a tab's colour popup is open
local function draw_tab_strip(ctx, dl, x, y, w, fx, pages, cur, req)
  local guid = fx.guid
  local h = C.TAB_STRIP_H
  ImGui.DrawList_AddRectFilled(dl, x, y, x + w, y + h, C.COL.header_bg)
  ImGui.DrawList_AddLine(dl, x, y + h - 0.5, x + w, y + h - 0.5, C.COL.panel_border, 1.0)
  ImGui.SetCursorScreenPos(ctx, x, y)
  W.allow_overlap(ctx)
  ImGui.InvisibleButton(ctx, "tabs##" .. guid, math.max(1, w), h)
  if ImGui.IsItemHovered(ctx) then
    local wheel = W.control_wheel(ctx)
    if wheel ~= 0 then
      St.set_page(guid, math.max(1, math.min(#pages, cur - wheel)))
      W.take_wheel()
    end
  end
  W.push_small(ctx)
  -- measure the whole strip first, so P.width can size the panel to it
  -- from the next frame on (its guess by character count is only for
  -- the first)
  local need = C.PANEL_PAD * 2
  for _, pg in ipairs(pages) do
    need = need + ImGui.CalcTextSize(ctx, P.page_label(pg)) + TAB_PAD_X * 2 + TAB_GAP
  end
  strip_measured[tab_strip_key(pages)] = need
  local tx = x + C.PANEL_PAD
  local open_x1, open_x2
  for i, pg in ipairs(pages) do
    local label = P.page_label(pg)
    local tw, th = ImGui.CalcTextSize(ctx, label)
    local bw = tw + TAB_PAD_X * 2
    local on = (i == cur)
    local x1, y1, x2, y2 = tx, y + (on and 2 or 4), tx + bw, y + h
    ImGui.SetCursorScreenPos(ctx, x1, y1)
    W.allow_overlap(ctx)
    ImGui.InvisibleButton(ctx, "tab" .. i .. "##" .. guid, bw, y2 - y1,
      ImGui.ButtonFlags_MouseButtonLeft | ImGui.ButtonFlags_MouseButtonRight)
    local hov = ImGui.IsItemHovered(ctx)
    if ImGui.IsItemClicked(ctx, ImGui.MouseButton_Left) then St.set_page(guid, i) end
    if ImGui.IsItemClicked(ctx, ImGui.MouseButton_Right) then
      tab_menu = { guid = guid, page = i, orig = pg.cap }
      ImGui.OpenPopup(ctx, "tabcol##" .. guid)
    end
    local fill = on and C.COL.panel_bg or (hov and C.COL.knob_body_hi or C.COL.toggle_off)
    ImGui.DrawList_AddRectFilled(dl, x1, y1, x2, y2 + (on and 1 or 0), fill, 3.0,
      ImGui.DrawFlags_RoundCornersTop)
    ImGui.DrawList_AddRect(dl, x1 + 0.5, y1 + 0.5, x2 - 0.5, y2 + (on and 1.5 or 0.5),
      C.COL.panel_border, 3.0, ImGui.DrawFlags_RoundCornersTop, 1.0)
    local stripe = W.cap_col(pg.cap) or C.COL.accent
    if not on then stripe = U.with_alpha(stripe, 0xa0) end
    ImGui.DrawList_AddRectFilled(dl, x1 + 4, y1 + 2, x2 - 4, y1 + 4, stripe, 1.0)
    ImGui.DrawList_AddText(dl, x1 + TAB_PAD_X, y1 + (y2 - y1 - th) * 0.5 + 1.5,
      on and C.COL.header_text or C.COL.label, label)
    if on then open_x1, open_x2 = x1, x2 end
    tx = x2 + TAB_GAP
  end
  W.pop_small(ctx)
  -- the open tab joins the body: no line along its foot
  if open_x1 then
    ImGui.DrawList_AddLine(dl, open_x1 + 1, y + h - 0.5, open_x2 - 1, y + h - 0.5, C.COL.panel_bg, 1.0)
  end
  -- its colour, from the cap swatches, previewed as you hover and kept
  -- when you pick (or put back when you cancel)
  if tab_menu and tab_menu.guid == guid and ImGui.BeginPopup(ctx, "tabcol##" .. guid) then
    local pg = pages[tab_menu.page]
    if pg then
      ImGui.TextDisabled(ctx, "Tab colour: " .. P.page_label(pg))
      ImGui.Separator(ctx)
      if ImGui.Selectable(ctx, "Theme accent##tabcol", pg.cap == nil, CK.KEEP_OPEN, 160, 0) then
        req.page_cap = { idx = pg.idx, cap = nil, save = true }
      end
      local from = W.cap_col(pg.cap) or C.COL.accent
      CK.cap_swatches(ctx, "tabcol" .. guid, pg.cap, from >> 8, "Tab colour",
        function(k, save) req.page_cap = { idx = pg.idx, cap = k, save = save } end,
        function() req.page_cap = { idx = pg.idx, cap = tab_menu.orig, save = true } end)
    end
    ImGui.EndPopup(ctx)
  elseif tab_menu and tab_menu.guid == guid then
    tab_menu = nil
  end
end

-- `panel_h` is the panel's FULL height, header included -- the same value
-- P.width() was given, so the column count here can't disagree with the
-- width the panel was allotted.
local function draw_controls(ctx, dl, x, y, w, panel_h, track, fx, layout, key, req, meter, io)
  local controls = layout.controls or {}
  -- in the rack, on a panel under three rows, the gain-reduction meter lies
  -- across the top, the width of the panel, and the grid starts under it
  if meter and P.RACK and P.rack_gr_across(fx.guid) then
    draw_meter_h(ctx, dl, x + C.PANEL_PAD, y + C.GRID_TOP_PAD, w - C.PANEL_PAD * 2, track, fx, meter)
    y = y + P.gr_strip_h()
    panel_h = panel_h - P.gr_strip_h()
    meter = nil
  end
  -- conditional controls left out, then paged: the strip under the
  -- header, then one page's controls below (the index lookup for the
  -- context menu still runs over the whole list)
  local page_controls = P.visible(controls, track, fx)
  local pages = P.pages(page_controls)
  -- a break's index is into the list it was split from; the colour menu
  -- wants the full list's (a hidden control before it shifts them)
  if pages and page_controls ~= controls then
    for _, pg in ipairs(pages) do
      if pg.ctl then
        for i, c in ipairs(controls) do if c == pg.ctl then pg.idx = i break end end
      end
    end
  end
  if pages then
    local cur = P.page_of(fx.guid, pages)
    draw_tab_strip(ctx, dl, x, y, w, fx, pages, cur, req)
    y = y + C.TAB_STRIP_H
    panel_h = panel_h - C.TAB_STRIP_H
    page_controls = pages[cur].controls
  end
  local lock = M.locked(layout)
  local lay = P.layout(page_controls, panel_h, lock)
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
    -- with View > Float plugins without controls on, its own window is
    -- where it's played (P.AUTO_FLOAT, set by the window drawing it)
    local msg = P.AUTO_FLOAT and "auto float" or "no layout"
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
    -- its corners (Corners<n> on the divider): a section is a plain
    -- rectangle, so round gives it fully round ends
    local r = corner_r(M.corners_of(s.by.corners), x2 - x1, y2 - y1, true)
    local function grained(fill)
      local fin = M.part_finish(kind, pl, s.by.finish, s.by.brush)
      local mt = M.part_metal(kind, s.by.metal)
      if r > 4 then
        -- the finish laid inside the rounder corners
        local loop = { { x1 + 1 - gx0, y1 + 1 - gy0, x2 - 1 - gx0, y1 + 1 - gy0,
                         x2 - 1 - gx0, y2 - 1 - gy0, x1 + 1 - gx0, y2 - 1 - gy0 } }
        if fin then flake_shape(ctx, dl, gx0, gy0, loop, U.is_light(fill), fin, fill, r - 1) end
        if mt then flake_shape(ctx, dl, gx0, gy0, loop, U.is_light(fill), nil, nil, r - 1) end
        return
      end
      finish_rect(ctx, dl, fin, fill, x1 + 1, y1 + 1, x2 - 1, y2 - 1, gx0, gy0)
      if mt then
        W.flake_rect(ctx, dl, x1 + 1, y1 + 1, x2 - 1, y2 - 1, U.is_light(fill), gx0, gy0)
      end
    end
    local inr = math.max(0, r - 1)
    if kind == "plate" then
      ImGui.DrawList_AddRectFilled(dl, x1, y1, x2, y2, pl.bg, r)
      grained(pl.bg)
      ImGui.DrawList_AddRect(dl, x1, y1, x2, y2, pl.border, r, 0, 1.0)
      ImGui.DrawList_AddLine(dl, x1 + math.max(4, inr), y1 + 1, x2 - math.max(4, inr), y1 + 1, 0xffffff18, 1.0)
    else
      local base = C.COL.panel_bg
      local fill = U.is_light(base) and mix(base, 0x000000ff, 0.10) or mix(base, 0xffffffff, 0.05)
      ImGui.DrawList_AddRectFilled(dl, x1, y1, x2, y2, fill, r)
      grained(fill)
      ImGui.DrawList_AddLine(dl, x1 + math.max(3, inr), y1 + 0.5, x2 - math.max(3, inr), y1 + 0.5, 0x00000050, 1.0)
      ImGui.DrawList_AddLine(dl, x1 + math.max(3, inr), y2 - 0.5, x2 - math.max(3, inr), y2 - 0.5, 0xffffff18, 1.0)
      ImGui.DrawList_AddRect(dl, x1, y1, x2, y2, 0x00000030, r, 0, 1.0)
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

    elseif M.is_virtual(ctl) then
      local act = draw_virtual(ctx, dl, id, ctl, item, fx, controls, key)
      if act and act.right_click then req.ctx_control = i end

    elseif not ctl.param or ctl.param < 0 or ctl.param >= nparams then
      -- The layout refers to a parameter this instance doesn't have --
      -- a plugin updated, or two different plugins sharing a name.
      --
      -- The cursor is already at this item's own cell -- SetCursorScreenPos
      -- above, from item.x/item.y, positions every item in lay.items the
      -- same way regardless of which branch below actually draws it, so this
      -- branch draws from the cursor rather than working a position out
      -- for itself.
      local px, py = ImGui.GetCursorScreenPos(ctx)
      ImGui.InvisibleButton(ctx, id, C.CELL_W, C.CELL_H)
      W.tip(ctx, "oob" .. id, ("Parameter %s out of range")
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
      -- Linked, the control follows its source: it's where the macro or
      -- modulator has it now, and the ring's handles set the range or
      -- swing; turning it moves the whole range.
      local link     = MD.link_of(track, fx.guid, p)
      local raw
      if link then raw = MD.live(track, link)
      else raw = reaper.TrackFX_GetParamNormalized(track, fx.addr, p) or 0 end
      local value    = rev and (1 - raw) or raw
      local function make_ring(lk, rv, pp)
        local lo, hi = MD.span(lk, track)
        local live = MD.live(track, lk)
        if rv then lo, hi, live = 1 - hi, 1 - lo, 1 - live end
        return { col = lk.mod.col, lo = lo, hi = hi, live = live,
                 hot = MR.hover == lk.mod.guid
                       or (MR.ctl_hover_prev and MR.ctl_hover_prev.guid == lk.mod.guid),
                 ends = drawn_ends(track, lk, rv), hot_end = range_hot[fx.guid .. ":" .. pp] }
      end
      local ring = link and make_ring(link, rev, p) or nil
      -- an XY pad's Y, a dual knob's inner knob: a link of its own
      local link2, ring2
      local p2x = (ctl.type == "xy" or ctl.type == "dual") and ctl.param2 or nil
      if p2x and p2x >= 0 and p2x < nparams then
        link2 = MD.link_of(track, fx.guid, p2x)
        if link2 then ring2 = make_ring(link2, ctl.invert2 and true or false, p2x) end
      end
      local cell_x, cell_y = gx0 + item.x, gy0 + item.y
      local cell_w, cell_h = item.pw or hx(item.w), hy(item.h)
      W.last_knob, W.last_fader, W.last_xy = nil, nil, nil
      local shown    = U.fmt_value(track, fx.addr, p)
      local _, pname = reaper.TrackFX_GetParamName(track, fx.addr, p, "")
      local label    = M.display_name(key, p, ctl.label, pname,
                                      ctl.live or layout.live)
      -- Just the value. The plugin's name is on the header two
      -- centimetres away and the parameter index is an implementation
      -- detail -- neither is what you're hovering to find out.
      local tip      = shown
      local modded   = P.mod_on(track, fx, p)
      if modded then tip = (tip or "") .. "\nModulation on" end

      local changed, nv, act
      if ctl.type == "xy" or ctl.type == "dual" then
        -- two parameters: an XY pad's X and Y, a concentric knob's ring and
        -- inner knob (Dual<n>); one not chosen yet, or out of range, shows ?
        local p2 = ctl.param2
        local ok2 = p2 ~= nil and p2 >= 0 and p2 < nparams
        local raw2 = ok2 and (reaper.TrackFX_GetParamNormalized(track, fx.addr, p2) or 0) or 0
        if link2 then raw2 = MD.live(track, link2) end
        local live2 = raw2
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
          .. (ok2 and "" or "\nRight-click: choose second parameter")
          .. ((modded or mod2) and "\nModulation on" or "")
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
              shown1 = shown, shown2 = shown2, tip = tip2,
              style = ctl.style, style2 = ctl.style2, look = ctl.look, look2 = ctl.look2 })
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
          local pv2 = rev2 and (1 - v2) or v2
          if link2 then MD.shift_link(track, link2, pv2 - live2)
          else reaper.TrackFX_SetParamNormalized(track, fx.addr, p2, pv2) end
          TP.touched(track, fx.guid)
          ML.set_target(track, fx.guid, fx.addr, p2, "cv")
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
            mod         = modded,
            style       = ctl.style })
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
          -- linked: its handles sit at its edge and must win the pointer
          if link then W.allow_overlap(ctx) end
          changed, nv, act = W.fader(ctx, id, fx0, fy0, fw, lay.height,
            value, label .. "   " .. shown, unity, false, look)
          if modded then
            -- top right of the fader's column, against the panel under it
            W.mod_corner(dl, fx0 + fw, fy0, 6, under)
          end
        else
          -- placed among the controls: its name over it, its value under
          if link then W.allow_overlap(ctx) end
          changed, nv, act = W.param_fader(ctx, id, gx0 + item.x, gy0 + item.y,
            item.pw or hx(item.w), hy(item.h), value, label, shown,
            { dir = ctl.dir, thin = ctl.thin, unity = unity, look = look,
              tip = label .. "   " .. shown, mod = modded and under or nil })
        end
      elseif ctl.type == "stepped" then
        local size = P.item_size(item)
        local st = step_norm(track, fx.addr, p, key)
        -- Same dial as a plain knob, quantised to the parameter's own
        -- step grid (see W.knob's step_norm), which needs only the step
        -- SIZE -- a cheap native read, no sweep. The readout text above
        -- is already the plugin's own formatted value for any control
        -- type, choice name included.
        -- The plugin's own choices, once they've been read (the same list
        -- a dropdown shows): the knob lands only on those. Until then, or
        -- when the plugin can't be swept, the even step grid.
        local snaps
        local list = combo_steps(track, fx.addr, p, key)
        if type(list) == "table" and #list > 1 then
          snaps = {}
          for i = 1, #list do snaps[i] = rev and (1 - list[i].norm) or list[i].norm end
        end
        changed, nv, act = W.knob(ctx, id, label, value, shown,
          { bipolar = ctl.bipolar, arc = ctl.arc, tooltip = tip, dim = not T.get_enabled(track, fx.addr),
            step_norm = st, snaps = snaps, mod = modded, ring = ring,
            style = ctl.style, cap = W.cap_col(ctl.cap), size = size, look = ctl.look,
            scale = P.knob_scale(track, fx, p, key, ctl, size, rev, st) })
      else
        local size = P.item_size(item)
        changed, nv, act = W.knob(ctx, id, label, value, shown,
          { bipolar = ctl.bipolar, arc = ctl.arc, tooltip = tip, dim = not T.get_enabled(track, fx.addr),
            style = ctl.style, cap = W.cap_col(ctl.cap), size = size, mod = modded, ring = ring, look = ctl.look,
            scale = P.knob_scale(track, fx, p, key, ctl, size, rev, nil) })
      end

      if act and act.double_click then
        local d = U.param_mid_norm(track, fx.addr, p)
        nv, changed = rev and (1 - d) or d, true
      end
      if changed then
        local pv = rev and (1 - nv) or nv
        if link then MD.shift_link(track, link, pv - raw)
        else reaper.TrackFX_SetParamNormalized(track, fx.addr, p, pv) end
        -- A measured plugin relearns its zero point when it's changed.
        TP.touched(track, fx.guid)
        -- the MIDI learn bar's "last touched"
        ML.set_target(track, fx.guid, fx.addr, p, "cv")
      end
      if act and act.right_click then req.ctx_control = i end
      -- the rack: a knob has its ring; anything else a corner in the
      -- modulator's colour. Where it is, for the hover lines.
      local kn = W.last_knob
      local tx, ty = cell_x + cell_w * 0.5, cell_y + cell_h * 0.5
      if kn then tx, ty = kn.cx, kn.cy end
      local fd = (not kn) and W.last_fader or nil
      local xy = (ctl.type == "xy") and W.last_xy or nil
      local dk = (kn and kn.dual) and kn or nil
      local k1, k2 = fx.guid .. ":" .. p, p2x and (fx.guid .. ":" .. p2x) or nil
      local rev_2 = ctl.invert2 and true or false
      -- which of a two-parameter control's the pointer is over: an XY pad's
      -- right half is Y, a dual knob's middle its inner knob
      local function second_under()
        local mx, my = ImGui.GetMousePos(ctx)
        if xy then return mx > (xy.x1 + xy.x2) * 0.5 end
        if dk then return (mx - dk.cx) ^ 2 + (my - dk.cy) ^ 2 <= (dk.ri * 1.15) ^ 2 end
        return false
      end
      if xy then
        -- bars along the pad's foot (X) and left side (Y), handles on them
        local fX = { v = false, p0 = xy.x1, p1 = xy.x2, y1 = xy.bottom }
        local fY = { v = true, p0 = xy.y2, p1 = xy.y1, x1 = xy.left - 7 }
        if link and ring then fader_range(ctx, dl, track, link, fX, ring, rev, k1) end
        if link2 and ring2 then fader_range(ctx, dl, track, link2, fY, ring2, rev_2, k2) end
      elseif dk then
        -- the ring's link round the outside, the inner knob's just outside it
        if link and ring then W.mod_ring(dl, dk.cx, dk.cy, dk.r, ring) end
        if link2 and ring2 then
          W.mod_ring(dl, dk.cx, dk.cy, dk.ri, ring2)
          range_ends(ctx, track, link2, rev_2, k2,
            function(v) return W.ring_point(dk.cx, dk.cy, dk.ri, v) end,
            function(mx, my) return W.ring_value(dk.cx, dk.cy, mx, my) end)
        end
      end
      if link and kn then
        range_ends(ctx, track, link, rev, fx.guid .. ":" .. p,
          function(v) return W.ring_point(kn.cx, kn.cy, kn.r, v) end,
          function(mx, my) return W.ring_value(kn.cx, kn.cy, mx, my) end)
      end
      if link and fd and ring then fader_range(ctx, dl, track, link, fd, ring, rev, fx.guid .. ":" .. p) end
      if link2 then
        local x2, y2 = tx, ty
        if xy then x2, y2 = xy.left - 2, (xy.y1 + xy.y2) * 0.5 end
        MR.note_target(link2.mod.guid, fx.guid, p2x, x2, y2)
        if not MR.drag then
          local mx, my = ImGui.GetMousePos(ctx)
          if mx >= cell_x and mx < cell_x + cell_w and my >= cell_y and my < cell_y + cell_h
             and (second_under() or not link) then
            MR.note_ctl_hover(link2.mod.guid, link2.out, x2, y2)
          end
        end
      end
      if link then
        if not ring or not (kn or fd or xy) then W.mod_corner_col(dl, cell_x + cell_w, cell_y, 6, link.mod.col) end
        MR.note_target(link.mod.guid, fx.guid, p, tx, ty)
        -- under the pointer: its line back to the modulator
        if not MR.drag then
          local mx, my = ImGui.GetMousePos(ctx)
          if mx >= cell_x and mx < cell_x + cell_w and my >= cell_y and my < cell_y + cell_h
             and not (link2 and second_under()) then
            local hx_, hy_ = tx, ty
            if xy then hx_, hy_ = (xy.x1 + xy.x2) * 0.5, xy.bottom + 2 end
            MR.note_ctl_hover(link.mod.guid, link.out, hx_, hy_)
          end
        end
      end
      -- a modulator's link being dragged in: this control takes it
      if MR.drag then
        local mx, my = ImGui.GetMousePos(ctx)
        if mx >= cell_x and mx < cell_x + cell_w and my >= cell_y and my < cell_y + cell_h then
          local col = MR.drag.mod.col
          -- a two-parameter control: the half (or middle) under the pointer
          local second = p2x and p2x >= 0 and p2x < nparams and second_under()
          local dp, dwas = p, link
          if second then dp, dwas = p2x, link2 end
          if xy then
            local mid = (xy.x1 + xy.x2) * 0.5
            local ax0 = second and mid or (xy.left)
            local ax1 = second and (xy.x2 + 5) or mid
            ImGui.DrawList_AddRect(dl, ax0, xy.y1 - 5, ax1, xy.bottom, col, 3, 0, 2.0)
            local t = second and "Y" or "X"
            local tw = ImGui.CalcTextSize(ctx, t)
            ImGui.DrawList_AddText(dl, (ax0 + ax1 - tw) * 0.5, xy.y1, col, t)
          elseif dk then
            if second then ImGui.DrawList_AddCircle(dl, dk.cx, dk.cy, dk.ri + 3, col, 32, 2.0)
            else ImGui.DrawList_AddCircle(dl, dk.cx, dk.cy, dk.r + 9, col, 32, 2.0) end
          elseif kn then ImGui.DrawList_AddCircle(dl, kn.cx, kn.cy, kn.r + 9, col, 32, 2.0)
          else ImGui.DrawList_AddRect(dl, cell_x + 1, cell_y + 1, cell_x + cell_w - 1, cell_y + cell_h - 1, col, 4, 0, 2.0) end
          if ImGui.IsMouseReleased(ctx, ImGui.MouseButton_Left) then
            req.mod_drop = { mod = MR.drag.mod, k = MR.drag.k or 1, path = fx.path_t, param = dp,
                             guid = fx.guid, was = dwas, label = label , centre = ctl.bipolar or nil }
          end
        end
      end
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

-- The background at height `yy` of the panel being drawn: what draw_plate
-- painted there (gradient included), or the flat panel colour. The trace's
-- fade blends into this.
-- (cur_bg is declared further up, before draw_controls, which uses it too)
bg_at = function(yy)
  local pl = cur_bg.plate
  if not (pl and C.EFFECT_3D) then return C.COL.panel_bg end
  local sh = (pl.sheen or 1) * (C.LIGHT or 100) / 100
  local split = cur_bg.y + cur_bg.h * 0.4
  if yy <= split then
    local t = math.max(0, math.min(1, (yy - cur_bg.y) / math.max(1, split - cur_bg.y)))
    return mix(mix(pl.bg, 0xffffffff, 0.08 * sh), pl.bg, t)
  end
  local t = math.max(0, math.min(1, (yy - split) / math.max(1, cur_bg.y + cur_bg.h - split)))
  return mix(pl.bg, mix(pl.bg, 0x000000ff, 0.12 * sh), t)
end

-- The plate itself: flat, or with the 3D effect a gentle top-lit gradient
-- -- real faceplates catch the light from above, and a flat fill reads as
-- a colour rather than a surface -- and its finish (C.FINISHES: the
-- layout's choice, or aluminium's own brushed grain), with the metallic
-- flake and sheen over it if chosen. The border is drawn over it afterwards
-- and tidies the corners.
local function draw_plate(ctx, dl, x, y, w, h, pl, finish, metal)
  ImGui.DrawList_AddRectFilled(dl, x, y, x + w, y + h, pl.bg, 3.0)
  -- the light falling on it (3D effect)
  if C.EFFECT_3D then
    local split = y + h * 0.4
    local L = (C.LIGHT or 100) / 100
    local sh = (pl.sheen or 1) * L
    W.vgrad(dl, x + 1, y + 1, x + w - 1, split, mix(pl.bg, 0xffffffff, math.min(0.5, 0.08 * sh)), pl.bg)
    W.vgrad(dl, x + 1, split, x + w - 1, y + h - 1, pl.bg, mix(pl.bg, 0x000000ff, math.min(0.6, 0.12 * sh)))
    if L > 1 then
      -- View > Lighting above 100%: the light across it, bright on the top
      -- left and deep on the bottom right, and its edges falling away
      local up = math.min(1.5, L - 1)
      local sk = math.max(0.5, pl.sheen or 1)
      local wa = math.floor(math.min(0x50, 0x2a * up * sk))
      local ba = math.floor(math.min(0x80, 0x48 * up * sk))
      W.grad4(dl, x + 1, y + 1, x + w - 1, y + h - 1,
        U.with_alpha(0xffffffff, wa), 0xffffff00, U.with_alpha(0x000000ff, ba), 0x00000000)
      local e = math.min(w, h) * 0.16
      local va = math.floor(math.min(0x60, 0x30 * up))
      local dk, cl = U.with_alpha(0x000000ff, va), 0x00000000
      W.grad4(dl, x + w - 1 - e, y + 1, x + w - 1, y + h - 1, cl, dk, dk, cl)            -- right
      W.grad4(dl, x + 1, y + h - 1 - e, x + w - 1, y + h - 1, cl, cl, dk, dk)            -- bottom
      local lk = U.with_alpha(0x000000ff, math.floor(va * 0.5))
      W.grad4(dl, x + 1, y + 1, x + 1 + e, y + h - 1, lk, cl, cl, lk)                    -- left
    end
  end
  -- its surface: the finish, then the flake over it
  finish_rect(ctx, dl, finish, pl.bg, x + 1, y + 1, x + w - 1, y + h - 1, x, y)
  if metal then
    W.flake_rect(ctx, dl, x + 1, y + 1, x + w - 1, y + h - 1, U.is_light(pl.bg), x, y)
    W.metal_sheen(dl, x, y, w, h)
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
    lines[1] = ("Oversampled (%s): %dx here"):format(T.os_label(st.n, rate):lower(), st.lit)
  elseif st.n > 0 then
    lines[1] = ("Set to %s: already the running rate, no effect"):format(
      T.os_label(st.n, rate):lower())
  else
    lines[1] = "Oversampling off"
  end
  for _, o in ipairs(st.outer or {}) do
    lines[#lines + 1] = ("Inside %s, oversampled %s"):format(o.what, T.os_label(o.n, rate):lower())
  end
  lines[#lines + 1] = "Click: change"
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
      rows and ("Layout locked at %d rows\n" ..
                "Click: unlock"):format(rows)
           or "Lock layout: no edits, controls stay put\n" ..
              "Meters can still be toggled",
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

-- Where each panel's header was drawn this frame, for the rack's lines
-- to controls that aren't on screen.
function P.begin_rects() panel_at = {} end
function P.panel_at(guid) return panel_at[guid] end

-- A canvas is a screen set into the faceplate. On a light faceplate
-- (aluminium, cream, stone, amber, gold) it gets a dark screen of the
-- theme's and the theme's inks for the length of its draw -- the plate's
-- dark inks vanish on a canvas's dark grounds, and its translucent
-- grounds wash out over a light plate. A dark faceplate shows through
-- unchanged. `plate` and `saved` are the panel's (push_plate).
local function plate_light(pl)
  local c = pl and pl.bg
  if not c then return false end
  local r, g, b = (c >> 24) & 0xff, (c >> 16) & 0xff, (c >> 8) & 0xff
  return (0.299 * r + 0.587 * g + 0.114 * b) / 255 > 0.5
end
local function on_screen(plate, saved, dl, x, y, w, h, fn, ...)
  if not (saved and plate_light(plate)) then return fn(...) end
  pop_plate(saved)
  ImGui.DrawList_AddRectFilled(dl, x, y, x + w, y + h, C.COL.panel_bg, 3.0)
  ImGui.DrawList_AddRect(dl, x, y, x + w, y + h, U.with_alpha(0x000000ff, 0x60), 3.0, 0, 1.0)
  local r = fn(...)
  push_plate(plate)
  return r
end

-- ReaComp's canvas, with input/output meters on the panel's outside
-- edges when asked for: false when it can't draw (the grid instead)
local function rc_body(ctx, dl, x, y, ww, bh, track, fx, req, io, enabled, plate, saved)
  local ex, ew = x, ww
  if io and draw_io(ctx, dl, x + C.PANEL_PAD, x + ww - C.PANEL_PAD - C.IO_COL_W,
                    y + C.HEADER_H + C.PANEL_PAD, C.IO_COL_W, bh - C.PANEL_PAD * 2, track, fx, enabled) then
    ex, ew = x + C.IO_COL_W + C.PANEL_PAD, ww - (C.IO_COL_W + C.PANEL_PAD) * 2
  end
  return on_screen(plate, saved, dl, ex + 1, y + C.HEADER_H + 1, ew - 2, bh - 2,
    CP.draw, ctx, dl, ex, y + C.HEADER_H, ew, bh, track, fx, req)
end

local draw_panel

-- The Rack view (TS_ChannelView_Rack.lua) draws panels down a column:
-- P.FILL_W, when set, is the column's width -- a panel's plate, header and
-- foot span it, its body centred on it -- and P.RACK draws a collapsed
-- panel as just its header strip.
P.FILL_W = nil
P.RACK = false

-- In the rack every panel is exactly the column's width, and its height is
-- what that width leaves it: a grid takes the fewest rows that fit across
-- the column, never fewer than its tallest control needs (a fader's
-- length, a large knob, an XY pad). When it's the layout ChannelView
-- shows and the rack runs down then across, it takes no fewer than the
-- rows its controls fill in ChannelView's own window (laid out at
-- P.RACK_ROWS, which ChannelView publishes), so it's arranged as it is
-- there; a layout only the rack shows, or one running across then down,
-- has nothing there to follow. A canvas (any EQ or compressor, ReaEQ,
-- ReaComp) spans the column at a height of its own, its layout's other
-- controls in rows UNDER it rather than beside it; the Trimmer stands its
-- two columns side by side when they fit, or stacks them.
P.RACK_ROWS_MAX = 40
P.RACK_ROWS = nil       -- ChannelView's own rows, when known

-- The rows a grid's tallest control needs: a fader's length, a large knob,
-- an XY pad, a button row. An upright fader is never less than two rows
-- (a full-height one included).
function P.tallest_rows(vis)
  local n = 1
  for _, c in ipairs(vis or {}) do
    local k = P.fader_kind(c)
    if k == "column" then n = math.max(n, 2)
    elseif k ~= "band" and c.type ~= "divider" and c.type ~= "page" then
      local _, h = P.cell_size(c, 2 * P.RACK_ROWS_MAX)
      n = math.max(n, math.ceil((h or 2) / 2))
    end
  end
  return n
end
-- The rows a grid fills in ChannelView's window: laid out at its rows
-- (P.RACK_ROWS) and in its Control flow (P.CV_FLOW; the rack's can
-- differ), its deepest column. 1 when they aren't known.
P.CV_FLOW = nil
function P.cv_rows_used(vis)
  if not P.RACK_ROWS or #(vis or {}) == 0 then return 1 end
  local was = C.FLOW
  C.FLOW = P.CV_FLOW or was
  local ok, lay = pcall(P.layout, vis, 0, P.RACK_ROWS)
  C.FLOW = was
  if not ok then return 1 end
  return math.max(1, math.ceil((lay.height or 0) / C.CELL_H - 0.01))
end
-- The rows a rack grid starts from (`shared`: ChannelView shows the same
-- layout).
function P.rack_from_rows(vis, shared)
  local n = P.tallest_rows(vis)
  if shared and C.FLOW ~= "row" then n = math.max(n, P.cv_rows_used(vis)) end
  return n
end
function P.rack_canvas_h(w)
  return math.floor(math.max(240, math.min(384, w * 0.5)))
end
-- a grid of n rows: the panel height that holds it
local function grid_panel_h(n, paged)
  return C.HEADER_H + P.footer_h() + C.GRID_TOP_PAD + C.PANEL_PAD + n * C.CELL_H
         + (paged and C.TAB_STRIP_H or 0)
end
-- the least panel height whose grid fits across w (all of it, when
-- nothing does), from `from` rows up
-- (has_meter: the gain-reduction meter upright at the side, `trace` its
-- history beside it, as in ChannelView). Returns the height and the rows.
local function rack_grid_h(vis, w, has_meter, key, io, trace, lock, from)
  local paged = P.pages(vis) ~= nil
  if lock then return grid_panel_h(lock, paged), lock end
  local h, n0 = nil, math.min(from or 1, P.RACK_ROWS_MAX)
  for n = n0, P.RACK_ROWS_MAX do
    h = grid_panel_h(n, paged)
    if P.width(vis, h, false, has_meter, key, io, trace, nil, nil) <= w then return h, n end
  end
  return h, P.RACK_ROWS_MAX
end

-- The rack's gain-reduction meter: upright at the side (and its trace) as
-- in ChannelView when the panel has three rows or more; lying across the
-- top, with no trace, when it has fewer. Kept by fx GUID by P.rack_height
-- for the drawing to read.
P.RACK_GR_ROWS = 3
local gr_across = {}
function P.rack_gr_across(guid) return gr_across[guid] == true end
-- the space either side the input and output meters take
local function io_w(io) return io and (C.IO_COL_W + C.PANEL_PAD) * 2 or 0 end

-- (`shared`: ChannelView shows this layout too, P.rack_from_rows)
function P.rack_height(track, fx, layout, key, w, shared)
  if St.is_collapsed(fx.guid) then return C.HEADER_H + 2 end
  local base = C.HEADER_H + P.footer_h()
  if TR.is(key) then return base + TRP.rack_body_h(w) end
  local io = P.has_io(track, fx, layout)
  if RQ.is_eq(key) or RC.is_comp(key) then return base + P.rack_canvas_h(w - io_w(io)) end
  local vis = P.visible(layout.controls or {}, track, fx)
  local lock = M.locked(layout)
  local canvas = layout.canvas
  if canvas then
    local ew = w - io_w(io)
    local h = base + P.rack_canvas_h(ew)
    if #vis > 0 then
      -- the controls under it: their own grid's body, header and foot aside
      h = h + (rack_grid_h(vis, ew, false, nil, false, false, lock, P.tallest_rows(vis))) - base
    end
    return h
  end
  local has_meter = M.meter_of(layout) ~= nil and T.reports_gr(track, fx.addr, fx.guid)
  local from = P.rack_from_rows(vis, shared)
  if not has_meter then
    gr_across[fx.guid] = nil
    return (rack_grid_h(vis, w, false, key, io, false, lock, from))
  end
  local h, rows = rack_grid_h(vis, w, true, key, io, St.is_gr_open(fx.guid), lock, from)
  if rows >= P.RACK_GR_ROWS then gr_across[fx.guid] = nil; return h end
  gr_across[fx.guid] = true
  return (rack_grid_h(vis, w, false, key, io, false, lock, from)) + P.gr_strip_h()
end

-- Draws one panel at the current cursor position and advances past it.
-- Returns a `req` table of things the caller should act on this frame:
--   toggle_bypass, toggle_float, open_menu, open_editor, ctx_control
-- (your own ranges for its parameters in force while it's drawn: TS_CV_Util
-- U.with_ranges -- the values, scales, tooltips and canvases read them)
function P.draw(ctx, track, fx, layout, key, avail_h, index, is_drag_source)
  local was = U.with_ranges(layout and layout.ranges)
  local a, b, c, d = draw_panel(ctx, track, fx, layout, key, avail_h, index, is_drag_source)
  U.with_ranges(was)
  return a, b, c, d
end
draw_panel = function(ctx, track, fx, layout, key, avail_h, index, is_drag_source)
  local req = { is_drag_source = is_drag_source }
  local collapsed = St.is_collapsed(fx.guid)
  local is_eq = RQ.is_eq(key)
  -- ReaComp's panel is its own canvas, with its own meters beside it
  local is_rc = RC.is_comp(key)
  -- the TS_CV Trimmer: meters, trims and filters of its own
  local is_trim = TR.is(key)
  -- ReaEQ has nothing to meter -- T.reports_gr would already say no for
  -- it, but skipping the check entirely is one fewer FX-parameter scan
  -- for the one plugin type that's never going to answer yes.
  local meter = (not is_eq and not is_rc and not is_trim) and M.meter_of(layout) or nil
  if meter and not T.reports_gr(track, fx.addr, fx.guid) then meter = nil end
  -- input/output meters: on any panel, a canvas's or ReaComp's included
  -- (their own strip beside the curve is the reduction only)
  local io = (not is_trim) and P.has_io(track, fx, layout)
  local canvas = (not is_eq and not is_rc and not is_trim) and layout.canvas or nil
  if canvas then meter = nil end
  local nat_w = P.width(P.visible(layout.controls or {}, track, fx), avail_h, collapsed, meter ~= nil, key, io,
                    St.is_gr_open(fx.guid), M.locked(layout), canvas)
  local w = (P.FILL_W and P.FILL_W > nat_w) and P.FILL_W or nat_w
  local off = math.floor((w - nat_w) * 0.5)
  -- the rack: every panel the column's width, its body all of it
  if P.RACK and P.FILL_W then w, nat_w, off = P.FILL_W, P.FILL_W, 0 end

  local pn_x, pn_y = ImGui.GetCursorPos(ctx)
  local ok = ImGui.BeginChild(ctx, "pnl##" .. fx.guid, w, avail_h, 0,
    ImGui.WindowFlags_NoScrollbar | ImGui.WindowFlags_NoScrollWithMouse)
  if ok then
    local dl = ImGui.GetWindowDrawList(ctx)
    local x, y = ImGui.GetWindowPos(ctx)
    local ww, wh = ImGui.GetWindowSize(ctx)
    panel_at[fx.guid] = { x + ww * 0.5, y + C.HEADER_H * 0.5 }
    local enabled = T.get_enabled(track, fx.addr)
    local plate = C.plate_of(layout.plate)
    local saved = plate and push_plate(plate)
    cur_bg.plate, cur_bg.y, cur_bg.h = plate, y, wh

    if is_drag_source then
      ImGui.DrawList_AddRectFilled(dl, x, y, x + ww, y + wh, C.COL.header_drag, 3.0)
    elseif plate then
      draw_plate(ctx, dl, x, y, ww, wh, plate, M.finish(layout, plate), M.metal(layout, plate))
    else
      ImGui.DrawList_AddRectFilled(dl, x, y, x + ww, y + wh, C.COL.panel_bg, 3.0)
    end
    ImGui.DrawList_AddRect(dl, x, y, x + ww, y + wh,
      is_drag_source and C.COL.drop_marker or C.COL.panel_border, 3.0, 0,
      is_drag_source and 2.0 or 1.0)

    -- The selected plugin: the panel last clicked. Plugin and FX chain
    -- buttons on the action bars add after it (TS_CV_FXButtons).
    if ImGui.IsMouseClicked(ctx, 0) or ImGui.IsMouseClicked(ctx, 1) then
      if ImGui.IsWindowHovered(ctx, ImGui.HoveredFlags_ChildWindows
                                    | ImGui.HoveredFlags_AllowWhenBlockedByActiveItem) then
        FB.select(track, fx.guid)
      end
    end

    -- the 3D effect: knobs and buttons cast shadows, the edges catch the light
    W.hw = (not is_drag_source and C.EFFECT_3D) and C.METAL_K or 0

    req.offline = T.get_offline(track, fx.addr)
    if collapsed then
      if req.offline and not is_drag_source then
        ImGui.DrawList_AddRectFilled(dl, x + 1, y + 1, x + ww - 1, y + wh - 1, C.COL.header_bg_off, 3.0)
      end
      if P.RACK then
        draw_header(ctx, dl, x, y, ww, track, fx, index, enabled, req)
      else
        draw_collapsed(ctx, dl, x, y, ww, wh, track, fx, enabled, req, meter)
      end
    else
      draw_header(ctx, dl, x, y, ww, track, fx, index, enabled, req)
      local fh = P.footer_h()
      -- the body: as wide as the panel's own layout, centred on a wider plate
      local bx, bw = x + off, ww - (w - nat_w)
      if req.offline then
        draw_offline(ctx, dl, bx, y + C.HEADER_H, bw, wh - C.HEADER_H - fh, track, fx)
      elseif is_trim then
        TRP.draw(ctx, dl, bx, y + C.HEADER_H, bw, wh - C.HEADER_H - fh, track, fx, req)
      elseif is_eq then
        -- The whole body becomes the draggable-node curve canvas rather
        -- than the ordinary parameter grid: a ReaEQ panel IS the EQ view,
        -- not a grid you can optionally switch away from.
        -- With input/output meters, they take the two outside edges here
        -- too, and the canvas keeps its own width between them.
        local ex, ew = bx, bw
        if io and draw_io(ctx, dl, bx + C.PANEL_PAD, bx + bw - C.PANEL_PAD - C.IO_COL_W,
                          y + C.HEADER_H + C.PANEL_PAD, C.IO_COL_W,
                          wh - C.HEADER_H - fh - C.PANEL_PAD * 2, track, fx, enabled) then
          ex, ew = bx + C.IO_COL_W + C.PANEL_PAD, bw - (C.IO_COL_W + C.PANEL_PAD) * 2
        end
        EQP.draw(ctx, dl, ex, y + C.HEADER_H, ew, wh - C.HEADER_H - fh, track, fx, req)
      elseif canvas then
        -- any plugin's EQ or compressor layout: the canvas, then the
        -- layout's own controls in columns beside it; with input/output
        -- meters, they take the two outside edges, as on any panel
        local cw = MP.width(canvas.kind)
        local bh = wh - C.HEADER_H - fh
        local ex, ew = bx, bw
        if io and draw_io(ctx, dl, bx + C.PANEL_PAD, bx + bw - C.PANEL_PAD - C.IO_COL_W,
                          y + C.HEADER_H + C.PANEL_PAD, C.IO_COL_W, bh - C.PANEL_PAD * 2, track, fx, enabled) then
          ex, ew = bx + C.IO_COL_W + C.PANEL_PAD, bw - (C.IO_COL_W + C.PANEL_PAD) * 2
        end
        -- the rack: the canvas across the whole width, the controls under it
        local stacked = P.RACK and P.FILL_W and true or false
        local full_bh = bh
        if stacked then
          cw = ew
          if #(layout.controls or {}) > 0 then bh = math.min(bh, P.rack_canvas_h(ew)) end
        end
        -- (a light faceplate gives the canvas a dark screen: on_screen)
        local todo = M.canvas_todo(canvas) or (canvas.kind ~= "eq" and not next(canvas.roles or {}))
        local function screen(fn, ...)
          if todo then return fn(...) end
          return on_screen(plate, saved, dl, ex + 1, y + C.HEADER_H + 1, cw - 2, bh - 2, fn, ...)
        end
        if RP.KINDS[canvas.kind] then
          if not screen(RP.draw, ctx, dl, ex, y + C.HEADER_H, cw, bh, track, fx, req, canvas) then
            MP.draw_setup(ctx, dl, ex, y + C.HEADER_H, cw, bh, fx, canvas, req)
          end
        elseif canvas.kind ~= "eq" then
          if not screen(CP.draw_mapped, ctx, dl, ex, y + C.HEADER_H, cw, bh, track, fx, req, canvas) then
            MP.draw_setup(ctx, dl, ex, y + C.HEADER_H, cw, bh, fx, canvas, req)
          end
        else
          screen(MP.draw_eq, ctx, dl, ex, y + C.HEADER_H, cw, bh, track, fx, layout, req)
        end
        if #(layout.controls or {}) > 0 then
          if stacked then
            -- a grid of its own under the canvas: its panel height is what
            -- the canvas leaves, with a header and foot's worth added back
            -- (none left: every control hidden just now)
            if full_bh - bh >= C.CELL_H then
              draw_controls(ctx, dl, ex, y + C.HEADER_H + bh, ew, C.HEADER_H + fh + (full_bh - bh),
                            track, fx, layout, key, req, nil, nil)
            end
          else
            draw_controls(ctx, dl, ex + cw - C.PANEL_PAD, y + C.HEADER_H, ew - cw + C.PANEL_PAD, wh, track, fx, layout,
                          key, req, nil, nil)
          end
        end
      elseif is_rc and rc_body(ctx, dl, bx, y, bw, wh - C.HEADER_H - fh, track, fx, req, io, enabled, plate, saved) then
        -- drawn: the transfer-curve canvas (one missing a parameter it
        -- needs falls through to the ordinary grid below instead)
      else
        draw_controls(ctx, dl, bx, y + C.HEADER_H, bw, wh, track, fx, layout,
                      key, req, meter, io)
      end
      if fh > 0 then draw_footer(ctx, dl, x, y + wh - fh, ww, fh, track, fx, layout, avail_h, is_eq or is_trim, req) end
    end
    if W.hw > 0 then W.metal_edges(dl, x, y, ww, wh, W.hw) end
    W.hw = 0
    -- the selected plugin's outline, last, so the header, footer and
    -- edges don't cover parts of it
    if not is_drag_source and FB.selected(track) == fx.guid then
      ImGui.DrawList_AddRect(dl, x + 0.5, y + 0.5, x + ww - 0.5, y + wh - 0.5, C.COL.accent, 3.0, 0, 1.6)
    end
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
