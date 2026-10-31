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

local U = require("TS_CV_Util")
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
  -- ratios first, as written, in over out: "4:1", "4.0 : 1" -- and under
  -- 1:1, an expander's (upward, above the threshold): "1:5", "0.50:1".
  -- (A plugin that writes its compression the other way round, "1:4",
  -- every setting under 1:1, is turned round where it's drawn.)
  local a, b = low:match("([%d%.]+)%s*:%s*([%d%.]+)")
  if a and b then
    local x, y = tonumber(a), tonumber(b)
    if x and y and x > 0 and y > 0 then return x / y, "ratio" end
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
--
-- Some plugins (Valhalla's) answer "what would this read at x?" with what
-- it reads now, whatever x. Such a parameter -- the same text at both ends
-- and the middle, and that text what it shows now -- is read once by
-- moving it through its range and reading it back (128 steps, then put
-- back where it was), and those readings kept for the session: numbers
-- between two steps are drawn in between, anything else is the nearer
-- step. Not while its track is writing automation (that would record the
-- sweep) or the transport is playing (it would be heard): it reads as
-- nothing until then.
local function raw_formatter(track, addr, p)
  return function(norm)
    if not reaper.TrackFX_FormatParamValueNormalized then return nil end
    local ok, s = reaper.TrackFX_FormatParamValueNormalized(track, addr, p, norm, "")
    if ok and s and trim(s) ~= "" then return trim(s) end
    return nil
  end
end
UN.SWEEP_N = 128
local swept = {}        -- fx GUID:param -> false (answers fine) | its readings, 0..SWEEP_N
local function sweep(track, addr, p)
  local cur = reaper.TrackFX_GetParamNormalized(track, addr, p)
  local t, first, varied = {}, nil, false
  for i = 0, UN.SWEEP_N do
    reaper.TrackFX_SetParamNormalized(track, addr, p, i / UN.SWEEP_N)
    local _, s = reaper.TrackFX_GetFormattedParamValue(track, addr, p, "")
    t[i] = trim(s)
    if first == nil then first = t[i] elseif t[i] ~= first then varied = true end
  end
  reaper.TrackFX_SetParamNormalized(track, addr, p, cur)
  return varied and t or false
end
local SUF = { ms = " ms", pct = " %", hz = " Hz", db = " dB", [""] = "" }
-- a reading between two kept steps
function UN.from_sweep(t, norm)
  local x = math.max(0, math.min(1, norm or 0)) * UN.SWEEP_N
  local i = math.floor(x)
  local f = x - i
  local a, b = t[i], t[math.min(UN.SWEEP_N, i + 1)]
  if f < 1e-9 or a == b or not b then return a ~= "" and a or nil end
  if not (a:find("/", 1, true) or b:find("/", 1, true)) then
    local va, ua = UN.parse(a)
    local vb, ub = UN.parse(b)
    if va and vb and ua == ub and ua ~= "ratio" and math.abs(va) < 1e9 and math.abs(vb) < 1e9 then
      return ("%.4f%s"):format(va + (vb - va) * f, SUF[ua] or "")
    end
  end
  local r = (f < 0.5) and a or b
  return r ~= "" and r or nil
end
function UN.formatter(track, addr, p)
  -- your own range for it (U.ranges_now): read off that
  local rg = U.range_of and U.range_of(p)
  if rg then return function(norm) return U.range_text(rg, norm) end end
  local raw = raw_formatter(track, addr, p)
  if not (reaper.TrackFX_GetFXGUID and reaper.TrackFX_SetParamNormalized and reaper.TrackFX_GetFormattedParamValue) then
    return raw
  end
  local k = tostring(reaper.TrackFX_GetFXGUID(track, addr) or addr) .. ":" .. tostring(p)
  local t = swept[k]
  if t == nil then
    t = false
    local f0, f1 = raw(0), raw(1)
    if f0 and f0 == f1 and raw(0.5) == f0 then
      local _, now = reaper.TrackFX_GetFormattedParamValue(track, addr, p, "")
      if trim(now) == f0 then
        local am = reaper.GetTrackAutomationMode and reaper.GetTrackAutomationMode(track) or 0
        local playing = reaper.GetPlayState and ((reaper.GetPlayState() or 0) & 5) ~= 0
        -- writing automation (it would record the sweep) or playing (it
        -- would be heard): not now, and asked again later
        if am >= 2 or playing then return function() return nil end end
        t = sweep(track, addr, p)
      end
    end
    swept[k] = t
  end
  if t then return function(norm) return UN.from_sweep(t, norm) end end
  return raw
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

-- Whether parameter p reads now as it would at n, by its text: true or
-- false, nil when the plugin can't say (yet). What it would read at n is
-- kept a few seconds (asked every frame, for each Show rule).
local at_cache = {}
function UN.reads_as(track, addr, guid, p, n)
  local ck = tostring(guid) .. ":" .. p .. ":" .. ("%.4f"):format(n)
  local now = reaper.time_precise()
  local hit = at_cache[ck]
  local want
  if hit and now < hit.until_t then want = hit.text
  else
    want = UN.formatter(track, addr, p)(n) or false
    at_cache[ck] = { text = want, until_t = now + 3 }
  end
  if not want then return nil end
  local _, cur = reaper.TrackFX_GetFormattedParamValue(track, addr, p, "")
  return trim(cur) == want
end

-- Where parameter p goes for a value typed as `text` ("-3", "2k",
-- "250 ms", "+5 semi"): the normalised value that reads nearest it, or nil
-- when it can't be read as a number. A number typed without a unit is in
-- the unit it shows now ("2" on a control at "1.50 kHz" is 2 kHz). A
-- control that reads no numbers takes a plain number as a percentage.
function UN.typed_norm(track, addr, p, text)
  local v, unit = UN.parse(text or "")
  if not v then return nil end
  local _, cur = reaper.TrackFX_GetFormattedParamValue(track, addr, p, "")
  local cv = UN.parse(cur or "")
  local shown = first_number(cur or "")
  if unit == "" and cv and shown and shown ~= 0 and cv ~= 0 then v = v * (cv / shown) end
  local n = UN.find_norm(UN.formatter(track, addr, p), v)
  if n then return n end
  return math.max(0, math.min(1, v / 100))
end

-- A control's settings as a list, { norm, text } each at the middle of
-- its run, read through `fmt` (UN.formatter); nil when it isn't a list
-- (more than max_pos runs, or nothing to read yet). A name seen twice is
-- one setting, at its wider run: a plugin that wraps at the very end of
-- its range (Valhalla's Mode reads Tape again at 1.0) lists it once.
function UN.choice_runs(fmt, max_pos)
  local pos = UN.positions(fmt, nil, max_pos)
  if not pos then return nil end
  local best = {}
  for i, r in ipairs(pos) do
    local b = best[r.text]
    if not b or (r.hi - r.lo) > (pos[b].hi - pos[b].lo) then best[r.text] = i end
  end
  local out = {}
  for i, r in ipairs(pos) do
    if best[r.text] == i then out[#out + 1] = { norm = (r.lo + r.hi) * 0.5, text = r.text } end
  end
  return (#out >= 2) and out or nil
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

-- A note value as beats (a quarter note is 1): "1/8" 0.5, "1/8 D" or
-- "1/8." (dotted) 0.75, "1/8T" or "1/8 triplet" 1/3, "1 bar" 4, "2 bars"
-- 8. Nil when the text isn't one.
function UN.note_beats(text)
  local s = trim(text or ""):lower()
  if s == "" then return nil end
  local n = s:match("^(%d+)%s*bars?%f[%A]")
  if n then return tonumber(n) * 4 end
  local a, b, rest = s:match("^(%d+)%s*/%s*(%d+)(.*)$")
  if not a then a, b, rest = s:match("^(%d+)%-(%d+%.?%d*)(.*)$") end   -- "1-8" (SSL)
  if not a then return nil end
  a, b = tonumber(a), tonumber(b)
  if not (a and b and b > 0) then return nil end
  local beats = 4 * a / b
  rest = rest or ""
  if rest:match("^%s*%.") or rest:match("^%s*d%f[%A]") or rest:match("dot") then
    beats = beats * 1.5
  elseif rest:match("^%s*t%f[%A]") or rest:match("trip") then
    beats = beats * 2 / 3
  end
  return beats
end

-- A time in ms from a control's text: a time ("375 ms", "1.2 s") or a note
-- value at the tempo given (beats a minute, 120 when not given). Nil when
-- it's neither.
function UN.time_ms(text, bpm)
  local v, u = UN.parse(text or "")
  if u == "ms" and v then return v end
  local beats = UN.note_beats(text)
  if beats then return beats * 60000 / ((bpm and bpm > 1) and bpm or 120) end
  return nil
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

-- ---------------------------------------------------------------------
-- a reverb's early / late balance (TS_CV_RolePanel's reverb canvas)
-- ---------------------------------------------------------------------
-- An early/late balance from its reading: the early reflections' level
-- against the late reverb's, dB. A crossfade's "0 dB / -16 dB" (early's
-- first), "Equal", its ends ("Reflections", "Late Reverb"), or a % (0 all
-- early, 100 all late). nil when it says none of those.
function UN.balance_text(t)
  local s = (t or ""):lower()
  local a, b = s:match("(%-?[%d%.]+)%s*d?b?%s*/%s*(%-?[%d%.]+)")
  if a and b and tonumber(a) and tonumber(b) then return math.max(-60, math.min(24, tonumber(a) - tonumber(b))) end
  if s:find("equal", 1, true) then return 0 end
  local v, un = UN.parse(t or "")
  if v and un == "pct" then
    local f = math.max(0.001, math.min(0.999, v / 100))
    return math.max(-60, math.min(24, 20 * math.log((1 - f) / f, 10)))
  end
  if s:find("reflect", 1, true) or s:find("early", 1, true) then return 24 end
  if s:find("late", 1, true) or s:find("reverb", 1, true) or s:find("tail", 1, true) then return -60 end
  return nil
end
-- along its range, nothing read: 0 all early .. 1 all late
function UN.balance_along(n)
  local f = math.max(0.001, math.min(0.999, n))
  return math.max(-60, math.min(24, 20 * math.log((1 - f) / f, 10)))
end
-- its balance along its range, read once: { {n, dB}, ... } (nil: none)
function UN.balance_table(fm)
  local t = {}
  for i = 0, 40 do
    local txt = fm(i / 40)
    local db = txt and UN.balance_text(txt)
    if db then t[#t + 1] = { i / 40, db } end
  end
  return (#t >= 2) and t or nil
end
function UN.balance_at(tab, n)
  if n <= tab[1][1] then return tab[1][2] end
  for i = 1, #tab - 1 do
    local a, b = tab[i], tab[i + 1]
    if n <= b[1] then return a[2] + (b[2] - a[2]) * (n - a[1]) / math.max(1e-9, b[1] - a[1]) end
  end
  return tab[#tab][2]
end
-- the position along it nearest a balance
function UN.balance_norm(tab, db)
  local best, bd = tab[1][1], math.huge
  for i = 1, #tab - 1 do
    local a, b = tab[i], tab[i + 1]
    local lo, hi = math.min(a[2], b[2]), math.max(a[2], b[2])
    if db >= lo and db <= hi and hi > lo then
      return a[1] + (b[1] - a[1]) * (db - a[2]) / (b[2] - a[2])
    end
    for _, q in ipairs({ a, b }) do
      local d = math.abs(q[2] - db)
      if d < bd then best, bd = q[1], d end
    end
  end
  return best
end

return UN
