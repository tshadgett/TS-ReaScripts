-- @noindex
-- Not a package of its own: installed by TS_ChannelView.lua's @provides.
--[[
  TS_CV_ReaComp.lua -- everything about ReaComp that isn't drawing.

  TS_CV_CompPanel.lua draws the panel; this file finds ReaComp's
  parameters, turns their values into real units and back, and does the
  transfer-curve and envelope arithmetic -- the arithmetic has no REAPER
  dependency, so it can be checked with no REAPER running.

  REAL UNITS. Like ReaEQ (see TS_CV_ReaEQ.lua's header), REAPER's own
  effects hand back the same 0..1 from TrackFX_GetParam as from
  GetParamNormalized, so the real value is read off the plugin's own
  display text. Going the other way -- "set the threshold to -18 dB" --
  needs the curve between the two, so each parameter's display is sampled
  across its range ONCE (TrackFX_FormatParamValueNormalized asks what the
  display would read at a value without setting it) and kept as a table:
  real -> normalised is then a lookup with interpolation, either way.
  A parameter whose display has no number in it (a choice, "Off") keeps
  its texts so a choice can be listed.

  PARAMETERS are found by NAME, not number: names survive a REAPER update
  that adds a parameter in the middle; numbers wouldn't.
--]]

local RC = {}

function RC.is_comp(key) return key == "ReaComp" end

-- ---------------------------------------------------------------------
-- parameters, by name
-- ---------------------------------------------------------------------
-- role -> how its name reads (lower case, matched with string.find, the
-- first that matches wins), from REAPER 7.82's ReaComp: Threshold, Ratio,
-- Attack, Release, Pre-comp, resvd, Lowpass, Hipass, SignIn, AudIn, Dry,
-- Wet, Filter Preview, RMS size, Knee, Auto Make Up Gain, Auto Release,
-- Legacy Attack/Knee Options, ... -- then REAPER's own Bypass, Wet, Delta.
-- Its "Limit output" switch isn't a parameter, so it has no role that
-- matches (the panel leaves it out); "limit" is kept in case one appears.
RC.ROLES = {
  { "thr",     { "^thresh" } },
  { "ratio",   { "^ratio" } },
  { "atk",     { "^attack" } },
  { "rel",     { "^release" } },
  { "pre",     { "^pre%-comp", "^precomp", "^pre comp" } },
  { "lp",      { "^lowpass", "^low pass" } },
  { "hp",      { "^hipass", "^highpass", "^high pass" } },
  { "det",     { "^signin" } },
  { "audio",   { "filter preview", "preview" } },
  { "dry",     { "^dry" } },
  { "wet",     { "^wet" } },
  { "rms",     { "^rms" } },
  { "knee",    { "^knee" } },
  { "autorel", { "^auto ?release" } },
  { "makeup",  { "^auto make ?up" } },
  { "limit",   { "^limit" } },
}

local found = {}   -- guid -> { n = param count, [role] = index }

-- Every role's parameter index on this instance (nil where it has none).
-- Re-read only when the parameter count changes.
function RC.params(track, addr, guid)
  local n = reaper.TrackFX_GetNumParams(track, addr)
  local f = found[guid]
  if f and f.n == n then return f end
  f = { n = n }
  local names = {}
  for p = 0, n - 1 do
    local _, nm = reaper.TrackFX_GetParamName(track, addr, p, "")
    names[p] = (nm or ""):lower()
  end
  for _, r in ipairs(RC.ROLES) do
    local role, pats = r[1], r[2]
    for _, pat in ipairs(pats) do
      for p = 0, n - 1 do
        if f[role] == nil and names[p]:find(pat) then
          local taken = false
          for _, rr in ipairs(RC.ROLES) do if f[rr[1]] == p then taken = true end end
          if not taken then f[role] = p end
        end
      end
      if f[role] then break end
    end
  end
  found[guid] = f
  return f
end

-- Whether the panel can be drawn at all: the four it can't do without.
function RC.usable(f)
  return f and f.thr and f.ratio and f.atk and f.rel and true or false
end

-- ---------------------------------------------------------------------
-- display text -> number
-- ---------------------------------------------------------------------
-- The leading number in REAPER's display text, signed by what's before
-- it (a Unicode minus counts), with "inf" read as infinity -- "-inf" for
-- a threshold or a dry at nothing, "inf" (or the infinity sign) for an
-- infinite ratio. nil when there's no number (a choice's name, "Off").
function RC.parse(s)
  if type(s) ~= "string" then return nil end
  local t = s:lower()
  if t:find("inf", 1, true) or t:find("\u{221e}", 1, true) then
    local pre = t:match("^%s*(.-)inf") or t:match("^%s*(.-)\u{221e}") or ""
    if pre:find("-", 1, true) or pre:find("\u{2212}", 1, true) then return -math.huge end
    return math.huge
  end
  local pre, num = t:match("^%s*([^%d%.]-)%s*(%d*%.?%d+)")
  if not num then return nil end
  local v = tonumber(num)
  if not v then return nil end
  if pre:find("-", 1, true) or pre:find("\u{2212}", 1, true) then v = -v end
  local rest = t:sub((t:find(num, 1, true) or 0) + #num)
  if rest:match("^%s*k") then v = v * 1000 end
  return v
end

-- ---------------------------------------------------------------------
-- the curve between normalised and real
-- ---------------------------------------------------------------------
RC.SAMPLES = 200

-- A table from samples { {n, v, text}, ... } in normalised order. Kept per
-- plugin and parameter, not per instance -- every ReaComp maps the same.
local maps = {}

function RC.map_from(samples)
  local m = { n = {}, v = {}, text = {}, numeric = 0 }
  for i, s in ipairs(samples) do
    m.n[i], m.text[i] = s[1], s[3] or ""
    m.v[i] = s[2]
    if s[2] ~= nil then m.numeric = m.numeric + 1 end
  end
  m.count = #samples
  return m
end

function RC.map(track, addr, p)
  local key = p
  local m = maps[key]
  if m then return m end
  local fmt = reaper.TrackFX_FormatParamValueNormalized
  if not fmt then return nil end
  local s = {}
  for i = 0, RC.SAMPLES do
    local x = i / RC.SAMPLES
    local ok, t = fmt(track, addr, p, x, "")
    if not ok then return nil end
    s[#s + 1] = { x, RC.parse(t), t }
  end
  m = RC.map_from(s)
  maps[key] = m
  return m
end
function RC.forget_maps() maps = {} end

local function finite(v) return v and v == v and v > -math.huge and v < math.huge end

-- Real value at a normalised position: interpolated between the samples
-- either side, unless one of them isn't finite (then the nearer one).
function RC.real(m, x)
  if not m or m.count < 2 then return nil end
  x = math.max(0, math.min(1, x))
  local k = x * (m.count - 1) + 1
  local i = math.min(m.count - 1, math.floor(k))
  local a, b = m.v[i], m.v[i + 1]
  local t = k - i
  if finite(a) and finite(b) then return a + (b - a) * t end
  if t < 0.5 then return a ~= nil and a or b end
  return b ~= nil and b or a
end

-- Normalised position for a real value: the samples are searched for the
-- pair it falls between (whichever way the display runs). A value past
-- either end clamps to that end.
function RC.norm(m, v)
  if not m or m.count < 2 or v == nil then return nil end
  local best, bestd = nil, math.huge
  for i = 1, m.count - 1 do
    local a, b = m.v[i], m.v[i + 1]
    if finite(a) and finite(b) then
      local lo, hi = math.min(a, b), math.max(a, b)
      if v >= lo and v <= hi then
        if b == a then return m.n[i] end
        return m.n[i] + (m.n[i + 1] - m.n[i]) * (v - a) / (b - a)
      end
    end
    for _, j in ipairs({ i, i + 1 }) do
      local w = m.v[j]
      if w ~= nil then
        local d
        if finite(w) then d = math.abs(w - v)
        elseif w == v then d = 0
        else d = math.huge end
        if d < bestd then best, bestd = m.n[j], d end
      end
    end
  end
  return best
end

-- The distinct choices of a parameter whose display is a name, in order:
-- { {norm = middle of its run, text}, ... }.
function RC.choices(m)
  if not m then return {} end
  local out = {}
  local i = 1
  while i <= m.count do
    local j = i
    while j < m.count and m.text[j + 1] == m.text[i] do j = j + 1 end
    out[#out + 1] = { norm = (m.n[i] + m.n[j]) * 0.5, text = m.text[i] }
    i = j + 1
  end
  return out
end

-- A parameter's real value (off its display text, else the map), its
-- normalised value, its display text and its map.
function RC.value(track, addr, p)
  if not p then return nil end
  local m = RC.map(track, addr, p)
  local nv = reaper.TrackFX_GetParamNormalized(track, addr, p)
  local _, raw = reaper.TrackFX_GetFormattedParamValue(track, addr, p, "")
  local v = RC.parse(raw)
  if v == nil and m then v = RC.real(m, nv) end
  return v, nv, RC.text(track, addr, p, nv), m
end

-- ReaComp's own display text (TrackFX_GetFormattedParamValue) has no units
-- ("3.0", "-inf", "6.85"); the text it would show for a value
-- (FormatParamValueNormalized) has them ("3.0 ms", "-inf dB", "6.85 :1").
function RC.text(track, addr, p, nv)
  local fmt = reaper.TrackFX_FormatParamValueNormalized
  if fmt then
    local ok, t = fmt(track, addr, p, nv or reaper.TrackFX_GetParamNormalized(track, addr, p), "")
    if ok and t and t ~= "" then return t end
  end
  local _, t = reaper.TrackFX_GetFormattedParamValue(track, addr, p, "")
  return t or ""
end

-- The detector's input ("SignIn") is a channel index, 0..1084, with no
-- names in its display. 0 is the main input; 2 is the auxiliary input --
-- channels 3/4, the sidechain (it's what the community's sidechain-routing
-- scripts set). Anything else is shown by its number.
RC.DET_MAX = 1084
RC.DET_CHOICES = { { 0, "Main input" }, { 2, "Sidechain (aux 3/4)" } }
function RC.det_text(nv)
  local v = math.floor((nv or 0) * RC.DET_MAX + 0.5)
  for _, c in ipairs(RC.DET_CHOICES) do if c[1] == v then return c[2] end end
  return "Input " .. v
end

-- Sets a parameter to a real value, clamped to its range.
function RC.set(track, addr, p, v)
  if not p or v == nil then return end
  local m = RC.map(track, addr, p)
  local n = m and RC.norm(m, v)
  if n then reaper.TrackFX_SetParamNormalized(track, addr, p, math.max(0, math.min(1, n))) end
end

-- The finite ends of a parameter's real range, lowest first.
function RC.range(m)
  local lo, hi = math.huge, -math.huge
  if m then
    for i = 1, m.count do
      local v = m.v[i]
      if v and v > -math.huge and v < math.huge then
        if v < lo then lo = v end
        if v > hi then hi = v end
      end
    end
  end
  if lo > hi then return nil end
  return lo, hi
end

-- ---------------------------------------------------------------------
-- the transfer curve
-- ---------------------------------------------------------------------
-- Output level for an input level, all dB, before make-up: 1:1 below the
-- knee, the ratio above it, and through the knee (knee dB wide, centred on
-- the threshold) the usual quadratic that joins the two smoothly. An
-- infinite ratio holds the output at the threshold.
function RC.transfer(x, thr, ratio, knee)
  local slope = (ratio and ratio > 0 and ratio < math.huge) and (1 / ratio) or 0
  if ratio and ratio > 0 and ratio < 1 then slope = 1 / ratio end
  knee = math.max(0, knee or 0)
  if knee > 0 then
    local h = knee * 0.5
    if x <= thr - h then return x end
    if x >= thr + h then return thr + (x - thr) * slope end
    local t = x - thr + h
    return x + (slope - 1) * t * t / (2 * knee)
  end
  if x <= thr then return x end
  return thr + (x - thr) * slope
end

-- Reduction at an input level (positive dB).
function RC.reduction(x, thr, ratio, knee)
  return math.max(0, x - RC.transfer(x, thr, ratio, knee))
end

-- ---------------------------------------------------------------------
-- the envelope's time axis
-- ---------------------------------------------------------------------
-- Attack, release and pre-comp are drawn on log scales of their own, each
-- across its share of the envelope's width: `lo`..`hi` ms onto 0..1. Below
-- `lo` sits at 0 (an attack of 0 is a vertical rise).
function RC.time_frac(ms, lo, hi)
  if not ms or ms <= lo then return 0 end
  if ms >= hi then return 1 end
  return math.log(ms / lo) / math.log(hi / lo)
end
function RC.frac_time(f, lo, hi)
  if f <= 0 then return 0 end
  if f >= 1 then return hi end
  return lo * (hi / lo) ^ f
end

-- The attack's rise and the release's fall, as fractions 0..1 of the way,
-- for a point `t` (0..1) along each segment: the exponential an RC-style
-- detector follows, normalised to land exactly on 1.
function RC.rise(t, k)
  k = k or 3.2
  return (1 - math.exp(-t * k)) / (1 - math.exp(-k))
end

return RC
