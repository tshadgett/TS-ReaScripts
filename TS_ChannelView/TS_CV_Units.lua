-- @noindex
-- Not a package of its own: installed by TS_ChannelView.lua's @provides.
--[[
  TS_CV_Units.lua -- a plugin parameter's value in real units, from the
  plugin's own text, and the other way round.

  A plugin tells us a parameter's value only as text: "1.20 kHz",
  "-3.5 dB", "4.0:1", "35 ms". UN.parse turns that into a number and a
  unit. Writing goes the other way: the normalised value that shows a
  given number is found by asking the plugin what each value would read
  as (TrackFX_FormatParamValueNormalized, which moves nothing) and
  narrowing in -- a bisection, since a parameter's text rises or falls
  with it.

  A SWITCH (a parameter with a handful of positions, an EQ's stepped
  frequencies) is found by asking what a fine sweep of positions reads as
  and grouping the runs of the same text: UN.positions. Each position is
  the middle of its run, which is where a write lands safely inside it
  whatever the plugin's own rounding.

  Everything that touches REAPER takes a `fmt(norm) -> text` function
  instead of a track and plugin, so the maths runs under the tests
  without a REAPER: UN.formatter(track, addr, p) makes one.
--]]

local UN = {}

local function trim(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end

-- ---------------------------------------------------------------------
-- parsing
-- ---------------------------------------------------------------------

-- "1.2k", "1,200", "-3.5", "+6" -> number; the first number in the text.
local function first_number(s)
  -- a thousands comma ("1,200 Hz") but not a decimal comma ("1,5 dB"):
  -- three digits after it means thousands
  s = s:gsub("(%d),(%d%d%d)%f[%D]", "%1%2")
  s = s:gsub("(%d),(%d)", "%1.%2")
  local num = s:match("[%+%-]?%d*%.?%d+")
  if not num then return nil end
  local v = tonumber(num)
  if not v then return nil end
  -- "1k2" style: 1.2k
  local a, b = s:match("(%d+)[kK](%d+)")
  if a and b then return tonumber(a .. "." .. b), true end
  return v
end

-- The value and unit a plugin's text shows, or nil when there's no
-- number in it. Units: "hz", "db", "ratio", "ms", "pct", or "" (a bare
-- number). Infinity ("-inf dB", "inf:1", "Limit", "∞") reads as
-- -math.huge / math.huge.
function UN.parse(text)
  -- a typographic minus (U+2212) is a minus
  local s = trim(text):gsub("\u{2212}", "-")
  if s == "" then return nil end
  local low = s:lower()
  -- ratios first: "4:1", "4.0 : 1", "1:4" (written the other way round)
  local a, b = low:match("([%d%.]+)%s*:%s*([%d%.]+)")
  if a and b then
    local x, y = tonumber(a), tonumber(b)
    if x and y and x > 0 and y > 0 then return math.max(x / y, y / x), "ratio" end
  end
  if low:match("inf%s*:") or low:match("^%s*limit") or low:match("∞%s*:")
     or low:match("^∞") and low:match(":") then
    return math.huge, "ratio"
  end
  if low:match("%-%s*inf") or low:match("%-∞") then
    return -math.huge, low:match("db") and "db" or ""
  end
  local v, kilo = first_number(s)
  if not v then return nil end
  if low:match("khz") or kilo or low:match("%dk%f[%A]") or low:match("%d%s*k$") then
    return v * 1000, "hz"
  end
  if low:match("hz") then return v, "hz" end
  if low:match("db") then return v, "db" end
  if low:match("ms") or low:match("msec") then return v, "ms" end
  if low:match("µs") then return v / 1000, "ms" end
  if low:match("%d%s*s$") or low:match("%d%s*sec") or low:match("%d%s*s%f[%A]") then
    return v * 1000, "ms"
  end
  if low:match("%%") then return v, "pct" end
  return v, ""
end

-- ---------------------------------------------------------------------
-- reading through the plugin
-- ---------------------------------------------------------------------

-- A text-for-a-value function for one parameter. Nil text when the
-- plugin can't say (an old REAPER without FormatParamValueNormalized).
function UN.formatter(track, addr, p)
  return function(norm)
    if not reaper.TrackFX_FormatParamValueNormalized then return nil end
    local ok, s = reaper.TrackFX_FormatParamValueNormalized(track, addr, p, norm, "")
    if ok and s and trim(s) ~= "" then return trim(s) end
    return nil
  end
end

-- The value at a normalised position, in real units, or nil.
function UN.at(fmt, norm)
  local t = fmt(norm)
  if not t then return nil end
  return UN.parse(t)
end

-- The parameter's positions when it is a switch: { {norm, text, lo, hi}, ... }
-- (norm the middle of its run, lo..hi the run), or nil when it reads
-- differently at nearly every point (a continuous control). `n` is how
-- finely to sweep (default 200); more than `max_pos` distinct runs (default
-- 24) is a knob, not a switch.
function UN.positions(fmt, n, max_pos)
  n = n or 200
  max_pos = max_pos or 24
  local runs, last = {}, nil
  for i = 0, n do
    local v = i / n
    local t = fmt(v)
    if t == nil then return nil end
    if t ~= last then
      runs[#runs + 1] = { text = t, lo = v, hi = v }
      last = t
      if #runs > max_pos then return nil end
    else
      runs[#runs].hi = v
    end
  end
  if #runs < 2 then return nil end
  for _, r in ipairs(runs) do r.norm = (r.lo + r.hi) * 0.5 end
  -- the ends exactly, so position 1 and the last are reachable whatever
  -- the plugin rounds
  runs[1].norm = runs[1].lo
  runs[#runs].norm = runs[#runs].hi
  return runs
end

-- The normalised value at which the plugin's text reads `target` (in the
-- unit it parses to), by bisection. Assumes the value rises or falls
-- with the parameter (true of any knob worth mapping). `lo`, `hi` narrow
-- the search (default the whole range). Returns norm, and the value it
-- actually reads there.
function UN.find_norm(fmt, target, lo, hi, iters)
  lo, hi = lo or 0, hi or 1
  local vlo, vhi = UN.at(fmt, lo), UN.at(fmt, hi)
  if not vlo or not vhi then
    -- an end that isn't a number ("Auto", "Off"): search the part that is
    local a, b
    for i = 0, 32 do
      local t = lo + (hi - lo) * i / 32
      if UN.at(fmt, t) then a = a or t; b = t end
    end
    if not a or a == b or (a == lo and b == hi) then return nil end
    return UN.find_norm(fmt, target, a, b, iters)
  end
  local rising = vhi >= vlo
  if rising then
    if target <= vlo then return lo, vlo end
    if target >= vhi then return hi, vhi end
  else
    if target >= vlo then return lo, vlo end
    if target <= vhi then return hi, vhi end
  end
  local best, bestv, besterr = lo, vlo, math.abs(vlo - target)
  for _ = 1, iters or 18 do
    local mid = (lo + hi) * 0.5
    local v = UN.at(fmt, mid)
    if not v then break end
    local err = math.abs(v - target)
    if err < besterr then best, bestv, besterr = mid, v, err end
    if (v < target) == rising then lo = mid else hi = mid end
  end
  return best, bestv
end

-- Where a value sits in a sorted table of points { {x, y}, ... } (x rising),
-- interpolated: linear in y, or in log(y) with `logy`; clamped to the ends.
function UN.interp(pts, x, logy)
  logy = logy or false
  local n = #pts
  if n == 0 then return nil end
  if n == 1 or x <= pts[1][1] then return pts[1][2] end
  if x >= pts[n][1] then return pts[n][2] end
  for i = 1, n - 1 do
    local a, b = pts[i], pts[i + 1]
    if x <= b[1] then
      local t = (b[1] > a[1]) and (x - a[1]) / (b[1] - a[1]) or 0
      if logy and a[2] > 0 and b[2] > 0 then
        return math.exp(math.log(a[2]) + t * (math.log(b[2]) - math.log(a[2])))
      end
      return a[2] + t * (b[2] - a[2])
    end
  end
  return pts[n][2]
end

-- The other way round: the x at which interpolated y reaches `y` (the
-- points' y rising or falling throughout). Clamped to the ends.
function UN.invert(pts, y, logy)
  logy = logy or false
  local n = #pts
  if n == 0 then return nil end
  if n == 1 then return pts[1][1] end
  local f = logy and function(v) return math.log(math.max(v, 1e-9)) end or function(v) return v end
  local rising = f(pts[n][2]) >= f(pts[1][2])
  local ty = f(y)
  if (rising and ty <= f(pts[1][2])) or (not rising and ty >= f(pts[1][2])) then return pts[1][1] end
  if (rising and ty >= f(pts[n][2])) or (not rising and ty <= f(pts[n][2])) then return pts[n][1] end
  for i = 1, n - 1 do
    local a, b = f(pts[i][2]), f(pts[i + 1][2])
    if (ty - a) * (ty - b) <= 0 and a ~= b then
      local t = (ty - a) / (b - a)
      return pts[i][1] + t * (pts[i + 1][1] - pts[i][1])
    end
  end
  return pts[n][1]
end

-- A short label for a value: "1.6k", "350", "-3.5", "4:1", "120 ms".
function UN.short(v, unit)
  if v == nil then return "" end
  if v == math.huge then return unit == "ratio" and "∞:1" or "∞" end
  if v == -math.huge then return "-∞" end
  if unit == "hz" then
    if v >= 1000 then return (string.format("%.1fk", v / 1000):gsub("%.0k$", "k")) end
    return string.format("%d", math.floor(v + 0.5))
  elseif unit == "db" then return string.format("%+.1f", v)
  elseif unit == "ratio" then return (string.format("%.1f:1", v):gsub("%.0:1$", ":1"))
  elseif unit == "ms" then
    if v >= 1000 then return string.format("%.2f s", v / 1000) end
    return string.format(v < 10 and "%.1f ms" or "%d ms", v)
  elseif unit == "pct" then return string.format("%d%%", math.floor(v + 0.5)) end
  return string.format("%g", v)
end

-- A switched time control (a compressor's attack, hold or release) as
-- steps along a log scale of lo..hi ms: { {norm, lo, hi, text, f}, ... },
-- f how far along (0..1) that setting sits, or nil for a continuous
-- control. Settings that read in time sit where their time puts them; one
-- that doesn't ("Auto") sits beside its neighbours. A switch that reads
-- in no time at all is spread evenly along, the other way round when
-- `rev` (a 1176's attack: 7 is the fastest).
function UN.time_steps(fmt, lo, hi, rev)
  local pos = UN.positions(fmt, 200, 24)
  if not pos then return nil end
  local lf = math.log(hi / lo)
  local function tf(ms)
    if ms <= lo then return 0 end
    if ms >= hi then return 1 end
    return math.log(ms / lo) / lf
  end
  local timed = 0
  for _, r in ipairs(pos) do
    local v, u = UN.parse(r.text)
    if u == "ms" and v then r.f = tf(v); timed = timed + 1 end
  end
  local n = #pos
  if timed < 2 then
    for i, r in ipairs(pos) do
      r.f = (i - 1) / (n - 1)
      if rev then r.f = 1 - r.f end
    end
    return pos
  end
  for i, r in ipairs(pos) do
    if not r.f then
      local before, after
      for j = i - 1, 1, -1 do if pos[j].f then before = pos[j].f break end end
      for j = i + 1, n do if pos[j].f then after = pos[j].f break end end
      if before and after then r.f = (before + after) * 0.5
      elseif before then r.f = math.min(1, before + 0.12)
      else r.f = math.max(0, (after or 0) - 0.12) end
    end
  end
  return pos
end

-- The step a normalised value is on, from UN.time_steps.
function UN.step_at(steps, norm)
  local best, bd = steps[1], math.huge
  for _, s in ipairs(steps) do
    if norm >= s.lo - 1e-6 and norm <= s.hi + 1e-6 then return s end
    local d = math.abs(s.norm - norm)
    if d < bd then best, bd = s, d end
  end
  return best
end

-- The step nearest a place along (0..1).
function UN.step_near(steps, f)
  local best, bd = nil, math.huge
  for _, s in ipairs(steps) do
    local d = math.abs(s.f - f)
    if d < bd then best, bd = s, d end
  end
  return best
end

return UN
