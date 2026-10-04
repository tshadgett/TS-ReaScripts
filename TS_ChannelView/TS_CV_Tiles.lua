-- @noindex
-- Not a package of its own: installed by TS_ChannelView.lua's @provides.
--[[
  TS_CV_Tiles.lua -- control backgrounds, joined into shapes.

  A control can have a background of its own (Back<n> in the layout: an
  inset, or a faceplate colour), drawn behind it over whatever the panel
  or its section is. Controls next to each other -- side by side or one
  above the other -- with the same background join into one shape, an L
  or a ring as readily as a rectangle, outlined once round the outside.

  Pure geometry, no drawing: TS_CV_Panel draws the shapes, and the web
  page traces them the same way in its own code.

    TL.shapes(rects, gaps, pad) -> { { key, outer = pts, holes = { pts... } } }

  `rects` are { x0, y0, x1, y1, key } -- each control's whole column width
  by its own height, in the grid's pixels; they never overlap. `gaps` are
  { x0, x1 }, the dividers' gaps: a same-background pair facing each other
  across one is joined over it (the background trumps the divider). `pad`
  pulls every edge in that far, so separate shapes have air between them.
  `pts` is a flat { x1, y1, x2, y2, ... } loop, clockwise on screen with
  the inside on the right; holes run the other way.

  How: every x and y edge in play cuts the grid into a lattice of cells;
  each cell takes the key of the rect covering it. A boundary is any cell
  side whose neighbour has a different key. Those sides, each directed
  with the inside on its right, chain into closed loops; corners where
  nothing turns are dropped; each edge moves in by `pad`.
--]]

local TL = {}

local function uniq_sorted(t)
  table.sort(t)
  local out = {}
  for _, v in ipairs(t) do
    if out[#out] == nil or math.abs(out[#out] - v) > 1e-6 then out[#out + 1] = v end
  end
  return out
end

local function index_of(list, v)
  for i, x in ipairs(list) do if math.abs(x - v) < 1e-6 then return i end end
end

-- the signed area of a flat loop: positive for clockwise on screen
local function area(p)
  local s, n = 0, #p
  for i = 1, n, 2 do
    local j = (i + 2 > n) and 1 or i + 2
    s = s + p[i] * p[j + 1] - p[j] * p[i + 1]
  end
  return s / 2
end
TL.area = area

local function inside(p, x, y)
  local c, n = false, #p
  local j = n - 1
  for i = 1, n, 2 do
    local xi, yi, xj, yj = p[i], p[i + 1], p[j], p[j + 1]
    if ((yi > y) ~= (yj > y)) and (x < (xj - xi) * (y - yi) / (yj - yi) + xi) then c = not c end
    j = i
  end
  return c
end

TL.inside = function(p, x, y) return inside(p, x, y) end

function TL.shapes(rects, gaps, pad)
  pad = pad or 0
  if #rects == 0 then return {} end
  local xs, ys = {}, {}
  for _, r in ipairs(rects) do
    xs[#xs + 1] = r[1]; xs[#xs + 1] = r[3]; ys[#ys + 1] = r[2]; ys[#ys + 1] = r[4]
  end
  for _, g in ipairs(gaps or {}) do xs[#xs + 1] = g[1]; xs[#xs + 1] = g[2] end
  xs, ys = uniq_sorted(xs), uniq_sorted(ys)
  local nx, ny = #xs - 1, #ys - 1

  -- each lattice cell's key
  local key = {}
  for i = 1, nx do
    key[i] = {}
    local cx = (xs[i] + xs[i + 1]) / 2
    for j = 1, ny do
      local cy = (ys[j] + ys[j + 1]) / 2
      for _, r in ipairs(rects) do
        if cx > r[1] and cx < r[3] and cy > r[2] and cy < r[4] then key[i][j] = r[5] break end
      end
    end
  end
  -- across a divider: an empty gap cell between two of the same joins them
  for _, g in ipairs(gaps or {}) do
    local i = index_of(xs, g[1])
    if i and i > 1 and i < nx and math.abs(xs[i + 1] - g[2]) < 1e-6 then
      for j = 1, ny do
        local l, r = key[i - 1][j], key[i + 1][j]
        if key[i][j] == nil and l ~= nil and l == r then key[i][j] = l end
      end
    end
  end
  local function k(i, j) return (key[i] or {})[j] end

  -- the boundary, as directed edges keyed by where they start
  local from, edges = {}, {}
  local function add(x0, y0, x1, y1, kk)
    local e = { x0, y0, x1, y1, kk, used = false }
    edges[#edges + 1] = e
    local s = x0 .. "," .. y0
    from[s] = from[s] or {}
    table.insert(from[s], e)
  end
  for i = 1, nx do
    for j = 1, ny do
      local kk = key[i][j]
      if kk ~= nil then
        local x0, x1, y0, y1 = xs[i], xs[i + 1], ys[j], ys[j + 1]
        if k(i, j - 1) ~= kk then add(x0, y0, x1, y0, kk) end   -- top, left to right
        if k(i + 1, j) ~= kk then add(x1, y0, x1, y1, kk) end   -- right, downward
        if k(i, j + 1) ~= kk then add(x1, y1, x0, y1, kk) end   -- bottom, right to left
        if k(i - 1, j) ~= kk then add(x0, y1, x0, y0, kk) end   -- left, upward
      end
    end
  end

  -- chain them into loops; where two leave the same corner (shapes that
  -- only touch at a corner), take the right turn, which keeps them apart
  local loops = {}
  for _, e0 in ipairs(edges) do
    if not e0.used then
      local pts, e = {}, e0
      local guard = 0
      repeat
        e.used = true
        pts[#pts + 1] = { e[1], e[2], e[3] - e[1], e[4] - e[2] }
        local nexts = from[e[3] .. "," .. e[4]] or {}
        local pick
        local dx, dy = e[3] - e[1], e[4] - e[2]
        for _, c in ipairs(nexts) do
          if not c.used and c[5] == e[5] then
            local cdx, cdy = c[3] - c[1], c[4] - c[2]
            local cross = dx * cdy - dy * cdx       -- > 0: a right turn on screen
            if not pick or cross > 0 then pick = c end
          end
        end
        e = pick
        guard = guard + 1
      until not e or guard > 10000
      -- corners only: drop the points where the direction doesn't change
      local corners = {}
      local n = #pts
      for m = 1, n do
        local prev = pts[(m - 2) % n + 1]
        local cur = pts[m]
        local sx = (prev[3] > 0 and 1) or (prev[3] < 0 and -1) or 0
        local sy = (prev[4] > 0 and 1) or (prev[4] < 0 and -1) or 0
        local cx = (cur[3] > 0 and 1) or (cur[3] < 0 and -1) or 0
        local cy = (cur[4] > 0 and 1) or (cur[4] < 0 and -1) or 0
        if sx ~= cx or sy ~= cy then
          corners[#corners + 1] = { cur[1], cur[2], px = sx, py = sy, nx = cx, ny = cy }
        end
      end
      -- each edge in by `pad`: the inside of a direction (dx, dy) is on
      -- its right, (-dy, dx) on screen, and a corner moves along both
      local flat = {}
      for _, c in ipairs(corners) do
        flat[#flat + 1] = c[1] + (-c.py + -c.ny) * pad
        flat[#flat + 1] = c[2] + (c.px + c.nx) * pad
      end
      if #flat >= 8 then loops[#loops + 1] = { key = e0[5], pts = flat } end
    end
  end

  -- outer loops are clockwise; a hole runs the other way and belongs to
  -- the outer loop of the same key that holds it
  local shapes, holes = {}, {}
  for _, l in ipairs(loops) do
    if area(l.pts) > 0 then shapes[#shapes + 1] = { key = l.key, outer = l.pts, holes = {} }
    else holes[#holes + 1] = l end
  end
  for _, h in ipairs(holes) do
    for _, s in ipairs(shapes) do
      if s.key == h.key and inside(s.outer, h.pts[1], h.pts[2]) then
        s.holes[#s.holes + 1] = h.pts
        break
      end
    end
  end
  return shapes
end

return TL
