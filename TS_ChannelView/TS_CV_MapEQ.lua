-- @noindex
-- Not a package of its own: installed by TS_ChannelView.lua's @provides.
--[[
  TS_CV_MapEQ.lua -- any plugin as an EQ canvas: the band models, what
  was learned about each band, and reading and writing the plugin's own
  parameters through them.

  A mapped band names up to five of the plugin's parameters (frequency,
  gain, Q, a shape switch, an On switch; TS_CV_Mappings Band<k>). Its
  SHAPE isn't set by hand: TS_CV_Learn measures a copy of the plugin and
  fits a model to each measurement (ME.fit); ME.summarise turns the fits
  into the tables kept in Learn<k>:

    T<s>  the model: bell, ls (low shelf), hs (high shelf), hp (high-pass),
          lp (low-pass); and for a pass filter its order (1..4: 6..24 dB/oct)
    F<s>  frequency: the frequency control's position -> where the band
          really sits, Hz (one point when the band has no frequency control)
    G<s>  gain: the gain control's position -> the gain it really gives, dB
    Q<s>  Q against gain (dB -> Q): proportional-Q designs narrow as they boost
    R<s>  the Q control's position -> a multiplier on that Q
    S     the frequency control's switch positions, when it has them
    H     the shape switch's positions, when there is one
    Z     where the gain control is flat (0 dB)
    O     the frequency switch's positions that switch the band off ("Off")
    D     1: the band reports its values (Hz, dB and a Q), so the canvas uses
          them as they are and only the shape was learned ("quick" learning)
    K<s>  for such a band: the measured frequency over the reported one, and
          the model's Q over the reported Q -- a plugin that means bandwidth
          or its own scale by "Q" is put right by the second

  <s> is the shape switch's position (1 when there's no switch). The
  models are analogue prototypes evaluated in closed form (ME.band_db), so
  the canvas doesn't depend on the sample rate and a fit doesn't either.
--]]

local UN = require("TS_CV_Units")

local ME = {}

ME.F_LO, ME.F_HI = 20, 20000
ME.NBANDS = 120                       -- 1/12 octave, 20 Hz .. 20 kHz
ME.TYPES = { bell = "Bell", ls = "Low shelf", hs = "High shelf", hp = "Low cut", lp = "High cut" }

-- The analyser's band centres (TS_CV_Learn.jsfx uses the same edges:
-- 20 * 2^(i/12), i = 0..120; centres are their geometric middles).
function ME.centres()
  local out = {}
  for i = 0, ME.NBANDS - 1 do out[i + 1] = 20 * 2 ^ ((i + 0.5) / 12) end
  return out
end

-- ---------------------------------------------------------------------
-- models (analogue prototypes, |H|^2 in closed form)
-- ---------------------------------------------------------------------

local LOG10 = math.log(10)
local function db10(v) return 10 * math.log(math.max(v, 1e-30)) / LOG10 end

-- 2nd-order high-pass |H|^2 at x = f/f0
local function hp2(x2, q) local a = 1 - x2; return (x2 * x2) / (a * a + x2 / (q * q)) end
local function hp1(x2) return x2 / (1 + x2) end
local BW = { [1] = {}, [2] = { 0.7071 }, [3] = { 1.0 }, [4] = { 0.5412, 1.3066 } }

-- One band's response in dB at f. `b`: { type, f, g, q, order }.
function ME.band_db(b, f)
  local t, f0, q = b.type, b.f or 1000, math.max(0.05, b.q or 0.7071)
  if f0 <= 0 then return 0 end
  local x = f / f0
  if t == "bell" or t == "ls" or t == "hs" then
    local g = b.g or 0
    if g == 0 then return 0 end
    local A = 10 ^ (g / 40)
    local x2 = x * x
    if t == "bell" then
      local a = 1 - x2
      return db10((a * a + (A * x / q) ^ 2) / (a * a + (x / (A * q)) ^ 2))
    elseif t == "ls" then
      local n = (A - x2) ^ 2 + (A / (q * q)) * x2
      local d = (1 - A * x2) ^ 2 + (A / (q * q)) * x2
      return db10(A * A * n / d)
    else
      local n = (1 - A * x2) ^ 2 + (A / (q * q)) * x2
      local d = (A - x2) ^ 2 + (A / (q * q)) * x2
      return db10(A * A * n / d)
    end
  elseif t == "hp" or t == "lp" then
    if t == "lp" then x = 1 / x end
    local x2 = x * x
    local order = b.order or 2
    local p = 1
    if order == 1 then p = hp1(x2)
    elseif order == 2 then p = hp2(x2, q)
    elseif order == 3 then p = hp1(x2) * hp2(x2, q)
    else p = hp2(x2, 0.5412) * hp2(x2, q) end
    return db10(p)
  end
  return 0
end

-- ---------------------------------------------------------------------
-- fitting a measurement
-- ---------------------------------------------------------------------

local FLOOR = -30   -- a cut's stop band, compared no deeper than this

local function err_of(b, freqs, D, valid)
  local e, n = 0, 0
  for i = 1, #freqs do
    if valid == nil or valid[i] then
      local m = math.max(FLOOR, ME.band_db(b, freqs[i]))
      local d = math.max(FLOOR, D[i])
      e = e + (m - d) ^ 2
      n = n + 1
    end
  end
  return n > 0 and math.sqrt(e / n) or math.huge
end

local function logspace(lo, hi, n)
  local out = {}
  for i = 0, n - 1 do out[#out + 1] = lo * (hi / lo) ^ (i / math.max(1, n - 1)) end
  return out
end

-- Coordinate descent on f (log), q (log) and g (linear) around a start.
local function refine(b, freqs, D, fields, rounds)
  local best = err_of(b, freqs, D)
  local step = { f = 0.25, q = 0.35, g = 1.0 }
  for _ = 1, rounds or 24 do
    local improved = false
    for _, k in ipairs(fields) do
      for _, dir in ipairs({ 1, -1 }) do
        local old = b[k]
        if k == "g" then b[k] = old + dir * step.g
        else b[k] = old * math.exp(dir * step[k]) end
        if k == "f" then b.f = math.max(10, math.min(30000, b.f)) end
        if k == "q" then b.q = math.max(0.1, math.min(12, b.q)) end
        local e = err_of(b, freqs, D)
        if e < best then best = e; improved = true else b[k] = old end
      end
    end
    if not improved then
      step.f, step.q, step.g = step.f * 0.5, step.q * 0.5, step.g * 0.5
      if step.f < 0.002 then break end
    end
  end
  return best
end

-- The model that best explains a measured response D (dB at `freqs`).
-- `kind`: "gain" (a band with a gain control: bell or shelf) or "cut" (a
-- pass filter). `force` fixes the type (and order) when it's already
-- known. Returns { type, f, g, q, order, err }, or nil when D is flat.
function ME.fit(freqs, D, kind, force)
  force = force or {}
  local n = #freqs
  local imax, vmax = 1, 0
  for i = 1, n do if math.abs(D[i]) > math.abs(vmax) then imax, vmax = i, D[i] end end
  if math.abs(vmax) < 0.4 then return nil end
  local best
  local function try(b, fields)
    local e = refine(b, freqs, D, fields)
    b.err = e
    if not best or e < best.err then best = b end
  end
  if kind == "cut" then
    local lo_avg = (D[1] + D[2] + D[3]) / 3
    local hi_avg = (D[n] + D[n - 1] + D[n - 2]) / 3
    local t = force.type or ((lo_avg < hi_avg) and "hp" or "lp")
    local orders = force.order and { force.order } or { 1, 2, 3, 4 }
    for _, order in ipairs(orders) do
      local cand
      for _, f0 in ipairs(logspace(15, 25000, 40)) do
        local b = { type = t, order = order, f = f0, q = BW[order][#BW[order]] or 0.7071 }
        b.err = err_of(b, freqs, D)
        if not cand or b.err < cand.err then cand = b end
      end
      try(cand, order == 1 and { "f" } or { "f", "q" })
    end
  else
    local types = force.type and { force.type } or { "bell", "ls", "hs" }
    for _, t in ipairs(types) do
      local cand
      if t == "bell" then
        for _, q in ipairs(logspace(0.15, 10, 24)) do
          local b = { type = "bell", f = freqs[imax], g = vmax, q = q }
          b.err = err_of(b, freqs, D)
          if not cand or b.err < cand.err then cand = b end
        end
      else
        local edge = (t == "ls") and (D[1] + D[2]) / 2 or (D[n] + D[n - 1]) / 2
        if math.abs(edge) < 0.2 then edge = vmax end
        local flo, fhi = (t == "ls") and 15 or 300, (t == "ls") and 3000 or 25000
        for _, f0 in ipairs(logspace(flo, fhi, 30)) do
          for _, q in ipairs({ 0.4, 0.55, 0.7071, 0.9, 1.2, 1.6 }) do
            local b = { type = t, f = f0, g = edge, q = q }
            b.err = err_of(b, freqs, D)
            if not cand or b.err < cand.err then cand = b end
          end
        end
      end
      try(cand, { "f", "q", "g" })
    end
  end
  return best
end

-- ---------------------------------------------------------------------
-- learned tables: encode / decode
-- ---------------------------------------------------------------------

local function enc_pts(pts)
  local t = {}
  for i, p in ipairs(pts) do t[i] = string.format("%.4g:%.4g", p[1], p[2]) end
  return table.concat(t, " ")
end
local function dec_pts(s)
  local out = {}
  for a, b in (s or ""):gmatch("([%-%+%d%.e]+):([%-%+%d%.e]+)") do
    out[#out + 1] = { tonumber(a), tonumber(b) }
  end
  return out
end
local function enc_list(l)
  local t = {}
  for i, v in ipairs(l) do t[i] = string.format("%.4g", v) end
  return table.concat(t, ",")
end
local function dec_list(s)
  local out = {}
  for v in (s or ""):gmatch("[^,]+") do out[#out + 1] = tonumber(v) end
  return out
end

-- L: { S = {norm...}|nil, H = {norm...}|nil, Z = norm|nil,
--      shapes = { [s] = { type, order, F = pts, G = pts, Q = pts, R = pts } } }
function ME.encode(L)
  local parts = {}
  if L.Z then parts[#parts + 1] = "Z=" .. string.format("%.4g", L.Z) end
  if L.S and #L.S > 0 then parts[#parts + 1] = "S=" .. enc_list(L.S) end
  if L.H and #L.H > 0 then parts[#parts + 1] = "H=" .. enc_list(L.H) end
  if L.O and #L.O > 0 then parts[#parts + 1] = "O=" .. enc_list(L.O) end
  if L.D then parts[#parts + 1] = "D=1" end
  local keys = {}
  for s in pairs(L.shapes or {}) do keys[#keys + 1] = s end
  table.sort(keys)
  for _, s in ipairs(keys) do
    local e = L.shapes[s]
    parts[#parts + 1] = ("T%d=%s,%d"):format(s, e.type, e.order or 0)
    if e.F and #e.F > 0 then parts[#parts + 1] = ("F%d=%s"):format(s, enc_pts(e.F)) end
    if e.G and #e.G > 0 then parts[#parts + 1] = ("G%d=%s"):format(s, enc_pts(e.G)) end
    if e.Q and #e.Q > 0 then parts[#parts + 1] = ("Q%d=%s"):format(s, enc_pts(e.Q)) end
    if e.R and #e.R > 0 then parts[#parts + 1] = ("R%d=%s"):format(s, enc_pts(e.R)) end
    if e.K then parts[#parts + 1] = ("K%d=%s"):format(s, enc_list(e.K)) end
  end
  return table.concat(parts, ";")
end

local dec_cache = {}
function ME.decode(str)
  if not str or str == "" then return nil end
  local hit = dec_cache[str]
  if hit then return hit end
  local L = { shapes = {} }
  for k, v in str:gmatch("([%a]%d*)=([^;]*)") do
    if k == "Z" then L.Z = tonumber(v)
    elseif k == "S" then L.S = dec_list(v)
    elseif k == "H" then L.H = dec_list(v)
    elseif k == "O" then L.O = dec_list(v)
    elseif k == "D" then L.D = (v == "1")
    else
      local tag, s = k:match("^(%a)(%d+)$")
      s = tonumber(s)
      if tag and s then
        L.shapes[s] = L.shapes[s] or {}
        local e = L.shapes[s]
        if tag == "T" then
          local t, o = v:match("^(%a+),?(%d*)")
          e.type, e.order = t, tonumber(o)
          if e.order == 0 then e.order = nil end
        elseif tag == "F" then e.F = dec_pts(v)
        elseif tag == "G" then e.G = dec_pts(v)
        elseif tag == "Q" then e.Q = dec_pts(v)
        elseif tag == "R" then e.R = dec_pts(v)
        elseif tag == "K" then e.K = dec_list(v) end
      end
    end
  end
  if not next(L.shapes) then return nil end
  -- a reported-values band needs only its type; the rest are optional
  for _, e in pairs(L.shapes) do
    e.F = e.F or {}; e.G = e.G or {}; e.Q = e.Q or {}; e.R = e.R or {}
  end
  dec_cache[str] = L
  return L
end

-- ---------------------------------------------------------------------
-- summarising a band's measurements
-- ---------------------------------------------------------------------

local function median(t)
  if #t == 0 then return nil end
  table.sort(t)
  local m = math.floor((#t + 1) / 2)
  if #t % 2 == 1 then return t[m] end
  return (t[m] + t[m + 1]) / 2
end

local function sorted_pts(map, logy)
  local pts = {}
  for x, ys in pairs(map) do
    local m = median(ys)
    if m and (not logy or m > 0) then pts[#pts + 1] = { x, m } end
  end
  table.sort(pts, function(a, b) return a[1] < b[1] end)
  return pts
end

-- `samples`: { { s = shape pos, fn = freq norm, gn = gain norm, qn = Q
-- norm (only on Q sweeps), fit = ME.fit result } }. `opts`: { kind,
-- S, H, Z, has_freq }. Returns L for ME.encode, or nil and why.
function ME.summarise(samples, opts)
  local L = { S = opts.S, H = opts.H, Z = opts.Z, O = opts.O, D = opts.direct or nil, shapes = {} }
  local by_s = {}
  for _, sm in ipairs(samples) do
    if sm.fit then
      by_s[sm.s] = by_s[sm.s] or {}
      table.insert(by_s[sm.s], sm)
    end
  end
  for s, list in pairs(by_s) do
    -- the type: the one that explains most of the bigger moves
    local votes = {}
    for _, sm in ipairs(list) do
      local w = math.abs(sm.fit.g or 6)
      local key = sm.fit.type .. "," .. (sm.fit.order or 0)
      votes[key] = (votes[key] or 0) + w
    end
    local tkey, tw = nil, -1
    for k, w in pairs(votes) do if w > tw then tkey, tw = k, w end end
    local t, o = tkey:match("^(%a+),(%d+)$")
    o = tonumber(o); if o == 0 then o = nil end
    local e = { type = t, order = o }
    local F, G, Q, R = {}, {}, {}, {}
    local qref = {}
    for _, sm in ipairs(list) do
      local fit = sm.fit
      if fit.type == t then
        if not sm.qn then
          local fk = sm.fn or 0
          F[fk] = F[fk] or {}; table.insert(F[fk], fit.f)
          if sm.gn then
            G[sm.gn] = G[sm.gn] or {}; table.insert(G[sm.gn], fit.g or 0)
          end
          -- by the gain control's position, so one setting is one point
          local gk = sm.gn or 0
          Q[gk] = Q[gk] or { g = {}, q = {} }
          table.insert(Q[gk].g, fit.g or 0); table.insert(Q[gk].q, fit.q)
          qref[#qref + 1] = fit.q
        end
      end
    end
    local q0 = median(qref) or 0.7071
    for _, sm in ipairs(list) do
      if sm.qn and sm.fit.type == t then
        R[sm.qn] = R[sm.qn] or {}; table.insert(R[sm.qn], sm.fit.q / q0)
      end
    end
    if opts.direct then
      -- reported values: keep the type, and how the measurement compares
      -- with what the plugin said (rep_f / rep_q on each sample)
      local fk, qk, qc = {}, {}, {}
      for _, sm in ipairs(list) do
        if sm.fit.type == t then
          if sm.rep_f and sm.rep_f > 0 then fk[#fk + 1] = sm.fit.f / sm.rep_f end
          if sm.rep_q and sm.rep_q > 0 then
            -- boosts and cuts apart: a band can be narrower one way
            if (sm.fit.g or 0) < 0 then qc[#qc + 1] = sm.fit.q / sm.rep_q
            else qk[#qk + 1] = sm.fit.q / sm.rep_q end
          end
        end
      end
      local kb = median(qk)
      local kc = median(qc)
      e.K = { median(fk) or 1, kb or kc or 1, kc or kb or 1 }
      e.F, e.G, e.Q, e.R = {}, {}, {}, {}
      if not opts.has_freq then
        -- no frequency control: where it sits is measured
        local fs = {}
        for _, sm in ipairs(list) do if sm.fit.type == t then fs[#fs + 1] = sm.fit.f end end
        e.F = { { 0, median(fs) or 1000 } }
      end
      L.shapes[s] = e
      goto continue
    end
    if opts.Z and next(G) then G[opts.Z] = { 0 } end
    e.F = sorted_pts(F, true)
    e.G = sorted_pts(G)
    e.Q = {}
    for _, v in pairs(Q) do
      local g, q = median(v.g), median(v.q)
      if g and q and q > 0 then e.Q[#e.Q + 1] = { g, q } end
    end
    table.sort(e.Q, function(a, b) return a[1] < b[1] end)
    e.R = sorted_pts(R, true)
    if #e.F == 0 then return nil, "no frequency could be measured" end
    if #e.Q == 0 then e.Q = { { 0, q0 } } end
    L.shapes[s] = e
    ::continue::
  end
  if not next(L.shapes) then return nil, "the band didn't change the sound" end
  return L
end

-- Q at a gain from a Q-against-gain table. Boosts and cuts are read on
-- their own sides; a side measured at fewer gains borrows the other
-- side's shape (by |gain|), scaled to meet its own measurement -- most
-- designs narrow or widen with how far the band moves, either way.
function ME.q_at(Q, g)
  if not Q or #Q == 0 then return 0.7071 end
  if #Q == 1 then return Q[1][2] end
  local pos, neg = {}, {}
  for _, pt in ipairs(Q) do
    if pt[1] >= 0 then pos[#pos + 1] = pt end
    if pt[1] <= 0 then neg[#neg + 1] = { -pt[1], pt[2] } end
  end
  table.sort(neg, function(a, b) return a[1] < b[1] end)
  local mine, other = (g >= 0) and pos or neg, (g >= 0) and neg or pos
  local ag = math.abs(g)
  if #mine >= 2 or #other < 2 then
    if #mine == 0 then mine = other end
    return UN.interp(mine, ag, true)
  end
  local shape = UN.interp(other, ag, true)
  -- nothing measured on this side at all (only cuts learned, say): the
  -- other side's shape as it is
  if #mine == 0 then return shape end
  local at_mine = UN.interp(other, mine[1][1], true)
  return shape * ((at_mine and at_mine > 0) and (mine[1][2] / at_mine) or 1)
end

-- The gain a band really gives for what its control reads: the learned
-- gains over what the control said at the same places, boosts and cuts
-- apart. 1 where there's nothing to go on.
local scale_cache = {}
local function gain_scale(track, addr, b, e)
  local ck = (b.learn or "") .. "#" .. tostring(b.gain)
  local hit = scale_cache[ck]
  if hit then return hit[1], hit[2] end
  local fmt = UN.formatter(track, addr, b.gain)
  local kp, kn = 1, 1
  for _, pt in ipairs(e.G or {}) do
    local t = UN.at(fmt, pt[1])
    if t and math.abs(t) > 1 and math.abs(pt[2]) > 0.5 then
      if t > 0 then kp = pt[2] / t else kn = pt[2] / t end
    end
  end
  scale_cache[ck] = { kp, kn }
  return kp, kn
end
ME.gain_scale = gain_scale

-- Where a frequency control's dial is off, and by how much: the learned
-- frequencies over what the dial said at the same places, as a table by
-- position -- only where the measurement can be trusted (well inside
-- 20 Hz .. 20 kHz, where a shelf or cut still shows its corner). Nil
-- when the control doesn't read in Hz.
local fscale_cache = {}
local function freq_scale(track, addr, b, e)
  local ck = (b.learn or "") .. "#f" .. tostring(b.freq)
  local hit = fscale_cache[ck]
  if hit ~= nil then return hit or nil end
  local fmt = UN.formatter(track, addr, b.freq)
  local pts = {}
  for _, pt in ipairs(e.F or {}) do
    local t, unit = UN.at(fmt, pt[1])
    if unit == "hz" and t and t > 40 and t < 10000 and pt[2] > 40 and pt[2] < 12000 then
      pts[#pts + 1] = { pt[1], pt[2] / t }
    end
  end
  fscale_cache[ck] = (#pts > 0) and pts or false
  return fscale_cache[ck] or nil
end

-- ---------------------------------------------------------------------
-- reading a band from the plugin
-- ---------------------------------------------------------------------

local function nearest_index(list, v)
  local bi, bd = 1, math.huge
  for i, x in ipairs(list or {}) do
    local d = math.abs(x - v)
    if d < bd then bi, bd = i, d end
  end
  return bi
end
ME.nearest_index = nearest_index

local function norm(track, addr, p) return reaper.TrackFX_GetParamNormalized(track, addr, p) or 0 end

-- Whether a switch reads "on". A parameter named Bypass is on when it
-- reads off; otherwise "Off", "Out", "Bypass" or 0 is off.
function ME.switch_on(track, addr, p)
  local _, name = reaper.TrackFX_GetParamName(track, addr, p, "")
  local _, txt = reaper.TrackFX_GetFormattedParamValue(track, addr, p, "")
  local t = (txt or ""):lower()
  local off = t:match("off") or t:match("^%s*out") or t:match("bypass") or t == "0" or t == ""
  if t == "" then off = norm(track, addr, p) < 0.5 end
  local lit = not off
  if (name or ""):lower():match("bypass") then lit = not lit end
  return lit
end

-- The band as it is now: { type, order, f, g, q, on, s } -- or nil when
-- it hasn't been learned.
function ME.read_band(track, addr, b, all_on)
  local L = ME.decode(b.learn)
  if not L then return nil end
  local s = 1
  if b.shape and L.H then s = nearest_index(L.H, norm(track, addr, b.shape)) end
  local e = L.shapes[s] or L.shapes[1]
  if not e then
    for _, v in pairs(L.shapes) do e = v break end
  end
  local out = { type = e.type, order = e.order, s = s }
  if L.D then
    -- the plugin's own values, put right by what was measured
    local K = e.K or { 1, 1 }
    local function val(p)
      if not p then return nil end
      local _, t = reaper.TrackFX_GetFormattedParamValue(track, addr, p, "")
      return (UN.parse(t))
    end
    out.f = (val(b.freq) or (e.F[1] and e.F[1][2]) or 1000) * (b.freq and (K[1] or 1) or 1)
    out.g = val(b.gain) or 0
    if out.g == -math.huge then out.g = -60 end
    out.q = (val(b.q) or 0.7071) * (((out.g or 0) < 0 and (K[3] or K[2])) or K[2] or 1)
    out.on = true
    if b.on then out.on = ME.switch_on(track, addr, b.on) end
    if all_on and not ME.switch_on(track, addr, all_on) then out.on = false end
    return out
  end
  if b.freq and #e.F > 1 then
    local fn = norm(track, addr, b.freq)
    if L.S then fn = L.S[nearest_index(L.S, fn)] end
    for _, o in ipairs(L.O or {}) do if math.abs(o - fn) < 1e-6 then out.off = true end end
    local fs = (not L.S) and freq_scale(track, addr, b, e)
    local t, unit = nil, nil
    if fs then t, unit = UN.parse(select(2, reaper.TrackFX_GetFormattedParamValue(track, addr, b.freq, ""))) end
    if fs and unit == "hz" and t and t > 0 then
      out.f = t * UN.interp(fs, fn)
    else
      out.f = UN.interp(e.F, fn, true)
    end
  else
    out.f = e.F[1] and e.F[1][2] or 1000
  end
  if b.gain and e.G and #e.G > 0 then
    local gn = norm(track, addr, b.gain)
    -- the plugin's own reading where it gives one in dB, the learned
    -- table where it doesn't
    local v, unit = UN.parse(select(2, reaper.TrackFX_GetFormattedParamValue(track, addr, b.gain, "")))
    if unit == "db" and v and v > -200 and v < 200 then
      local kp, kn = gain_scale(track, addr, b, e)
      out.g = v * ((v >= 0) and kp or kn)
    else
      out.g = UN.interp(e.G, gn)
    end
  else
    out.g = 0
  end
  local q = ME.q_at(e.Q, out.g or 0) or 0.7071
  if b.q and e.R and #e.R > 0 then q = q * (UN.interp(e.R, norm(track, addr, b.q), true) or 1) end
  out.q = q
  out.on = not out.off
  if b.on and not ME.switch_on(track, addr, b.on) then out.on = false end
  if all_on and not ME.switch_on(track, addr, all_on) then out.on = false end
  return out
end

-- ---------------------------------------------------------------------
-- writing
-- ---------------------------------------------------------------------

-- Moves the band's frequency control so the band sits as near `hz` as it
-- can: the nearest switch position, or the learned table run backwards.
function ME.set_freq(track, addr, b, hz)
  local L = ME.decode(b.learn)
  if not (L and b.freq) then return end
  local s = 1
  if b.shape and L.H then s = nearest_index(L.H, norm(track, addr, b.shape)) end
  local e = L.shapes[s] or L.shapes[1]
  if not e then return end
  local v
  if L.D then
    local fmt = UN.formatter(track, addr, b.freq)
    local target = hz / ((e.K and e.K[1]) or 1)
    if L.S then
      local bi, bd = 1, math.huge
      for i, pn in ipairs(L.S) do
        local f = UN.at(fmt, pn)
        if f and f > 0 then
          local d = math.abs(math.log(f / target))
          if d < bd then bi, bd = i, d end
        end
      end
      v = L.S[bi]
    else
      v = UN.find_norm(fmt, target)
    end
  elseif #e.F < 2 then return
  elseif L.S then
    local bi, bd = 1, math.huge
    for i, pn in ipairs(L.S) do
      local f = UN.interp(e.F, pn, true)
      local d = math.abs(math.log(f / hz))
      if d < bd then bi, bd = i, d end
    end
    v = L.S[bi]
  else
    local fs = freq_scale(track, addr, b, e)
    if fs then
      -- the dial's own reading, put right: one pass of the correction at
      -- the target's neighbourhood is close enough
      local guess = UN.invert(e.F, hz, true) or 0.5
      v = UN.find_norm(UN.formatter(track, addr, b.freq), hz / UN.interp(fs, guess))
    else
      v = UN.invert(e.F, hz, true)
    end
  end
  if v and math.abs(v - norm(track, addr, b.freq)) > 1e-6 then
    reaper.TrackFX_SetParamNormalized(track, addr, b.freq, math.max(0, math.min(1, v)))
  end
end

-- Moves the gain control to give `db`: through the plugin's own text when
-- it reads in dB, the learned table otherwise.
function ME.set_gain(track, addr, b, db)
  local L = ME.decode(b.learn)
  if not (L and b.gain) then return end
  local fmt = UN.formatter(track, addr, b.gain)
  local _, unit = UN.at(fmt, 0.5)
  local v
  local s0 = 1
  if b.shape and L.H then s0 = nearest_index(L.H, norm(track, addr, b.shape)) end
  local e0 = L.shapes[s0] or L.shapes[1]
  if unit == "db" then
    local kp, kn = 1, 1
    if not L.D and e0 then kp, kn = gain_scale(track, addr, b, e0) end
    local t = (db >= 0) and db / (kp ~= 0 and kp or 1) or db / (kn ~= 0 and kn or 1)
    v = UN.find_norm(fmt, t)
  else
    local s = 1
    if b.shape and L.H then s = nearest_index(L.H, norm(track, addr, b.shape)) end
    local e = L.shapes[s] or L.shapes[1]
    if e and e.G and #e.G > 1 then v = UN.invert(e.G, db) end
  end
  if v and math.abs(v - norm(track, addr, b.gain)) > 1e-6 then
    reaper.TrackFX_SetParamNormalized(track, addr, b.gain, math.max(0, math.min(1, v)))
  end
end

-- ---------------------------------------------------------------------
-- a dynamic EQ band's dynamics (TS_CV_Mappings Dyn<k>)
-- ---------------------------------------------------------------------
-- What doesn't read in its unit runs along its range: a threshold over
-- -60..0 dB, a range over +/- ME.DYN_SPAN dB (reversed: the other way).
ME.DYN_SPAN = 18

local function ptext(track, addr, p)
  local _, t = reaper.TrackFX_GetFormattedParamValue(track, addr, p, "")
  return ((t or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

-- The band's dynamics as they read: { thr (dB), thr_along, thr_text,
-- range (dB, signed: below 0 a cut), range_along, range_text, ratio_text,
-- atk_text, rel_text, on }; nil when it isn't dynamic.
function ME.read_dyn(track, addr, b)
  local d = b.dyn
  if not d then return nil end
  local rev = d.rev or {}
  local out = { on = true }
  if d.thr then
    local n, t = norm(track, addr, d.thr), ptext(track, addr, d.thr)
    local v, u = UN.parse(t)
    out.thr_text = t
    if u == "db" and v then out.thr = (v == -math.huge) and -100 or v
    else out.thr, out.thr_along = -60 + 60 * (rev.thr and (1 - n) or n), true end
  end
  if d.range then
    local n, t = norm(track, addr, d.range), ptext(track, addr, d.range)
    local v, u = UN.parse(t)
    out.range_text = t
    if u == "db" and v and v > -200 and v < 200 then out.range = rev.range and -v or v
    else
      out.range = (n * 2 - 1) * ME.DYN_SPAN
      if rev.range then out.range = -out.range end
      out.range_along = true
    end
  end
  if d.ratio then out.ratio_text = ptext(track, addr, d.ratio) end
  if d.atk then out.atk_text = ptext(track, addr, d.atk) end
  if d.rel then out.rel_text = ptext(track, addr, d.rel) end
  if d.on then out.on = ME.switch_on(track, addr, d.on) end
  return out
end

local function set_n(track, addr, p, v)
  if v and math.abs(v - norm(track, addr, p)) > 1e-6 then
    reaper.TrackFX_SetParamNormalized(track, addr, p, math.max(0, math.min(1, v)))
  end
end

-- Sets the band's range to `db` (signed: below 0 a cut).
function ME.set_range(track, addr, b, db)
  local d = b.dyn
  if not (d and d.range) then return end
  local rev = d.rev or {}
  local fmt = UN.formatter(track, addr, d.range)
  local _, u = UN.at(fmt, 0.5)
  if u == "db" then
    set_n(track, addr, d.range, UN.find_norm(fmt, rev.range and -db or db))
  else
    local n = (db / ME.DYN_SPAN + 1) * 0.5
    set_n(track, addr, d.range, rev.range and (1 - n) or n)
  end
end

-- Sets the band's threshold to `db`.
function ME.set_thr(track, addr, b, db)
  local d = b.dyn
  if not (d and d.thr) then return end
  local rev = d.rev or {}
  local fmt = UN.formatter(track, addr, d.thr)
  local _, u = UN.at(fmt, 0.5)
  if u == "db" then
    set_n(track, addr, d.thr, UN.find_norm(fmt, db))
  else
    local n = (db + 60) / 60
    set_n(track, addr, d.thr, rev.thr and (1 - n) or n)
  end
end

-- The threshold's ends, dB, for its slider: the control's own when it
-- reads in dB, else -60..0.
function ME.thr_span(track, addr, b)
  local d = b.dyn
  if d and d.thr then
    local fmt = UN.formatter(track, addr, d.thr)
    local a, ua = UN.at(fmt, 0)
    local c, uc = UN.at(fmt, 1)
    if ua == "db" and uc == "db" and a and c and a > -200 and c > -200 and a < 200 and c < 200 and a ~= c then
      return math.min(a, c), math.max(a, c)
    end
  end
  return -60, 0
end

-- Where on the spectrum a band is heard most, for reading what it's doing:
-- a bell at its frequency, a shelf an octave into its plateau.
function ME.dyn_focus(rb)
  if rb.type == "ls" then return rb.f * 0.5 end
  if rb.type == "hs" then return rb.f * 2 end
  return rb.f
end

-- The frequencies a band covers, Hz, for summing its level going in: a
-- bell its bandwidth, a shelf its plateau.
function ME.dyn_span(rb)
  local q = math.max(0.1, rb.q or 0.7071)
  if rb.type == "ls" then return 20, rb.f * 1.2 end
  if rb.type == "hs" then return rb.f / 1.2, 20000 end
  local bw = 2 * math.log(1 / (2 * q) + math.sqrt(1 / (4 * q * q) + 1)) / math.log(2)
  local h = 2 ^ (math.max(1 / 3, bw) / 2)
  return rb.f / h, rb.f * h
end

-- What the probe measures the plugin doing at `f` Hz, dB (below 0 cut),
-- from a third-octave frame (TS_CV_CompPanel CP.fine_frame: g = reduction,
-- positive), between the bands' centres; 0 where there's no signal.
function ME.dev_at(fr, f)
  if not fr or fr.n < 1 or f <= 0 then return 0 end
  local x = 17 + 3 * math.log(f / 1000) / math.log(2)
  x = math.max(1, math.min(fr.n, x))
  local a = math.floor(x)
  local b = math.min(fr.n, a + 1)
  local t = x - a
  local ga, gb = fr.g[a], fr.g[b]
  if ga == nil and gb == nil then return 0 end
  ga, gb = ga or gb, gb or ga
  return -(ga + (gb - ga) * t)
end

-- The level going in between lo and hi Hz, dBFS: the third-octaves whose
-- centres fall there, summed (the nearest one when none do); nil without.
function ME.level_in(fr, lo, hi)
  if not fr or not fr.lv then return nil end
  local p, any = 0, false
  for k = 1, fr.n do
    local f, l = fr.f[k], fr.lv[k]
    if f >= lo and f <= hi and l and l > -140 then p = p + 10 ^ (l / 10); any = true end
  end
  if not any then
    local mid, best, bd = math.sqrt(lo * hi), nil, math.huge
    for k = 1, fr.n do
      local dd = math.abs(math.log(fr.f[k] / mid))
      if fr.lv[k] and fr.lv[k] > -140 and dd < bd then best, bd = fr.lv[k], dd end
    end
    return best
  end
  return 10 * math.log(p) / LOG10
end

-- Takes a band out of the sound (a double-click on its node): its gain to
-- flat, or a cut to its Off position, or its On switch off.
function ME.reset(track, addr, b)
  local L = ME.decode(b.learn)
  if not L then return end
  if b.gain and L.Z then
    reaper.TrackFX_SetParamNormalized(track, addr, b.gain, L.Z)
  elseif b.gain then
    ME.set_gain(track, addr, b, 0)
  elseif b.freq and L.O and L.O[1] then
    reaper.TrackFX_SetParamNormalized(track, addr, b.freq, L.O[1])
  elseif b.on and ME.switch_on(track, addr, b.on) then
    local cur = norm(track, addr, b.on)
    reaper.TrackFX_SetParamNormalized(track, addr, b.on, cur >= 0.5 and 0 or 1)
  end
end

-- A band's shape switch, setting by setting: { {s, norm, type, order,
-- text}, ... } in the switch's order -- type what that setting was learned
-- as (nil if it wasn't), text what the plugin calls it -- or nil when the
-- band has no shape switch.
function ME.shapes(track, addr, b)
  if not b.shape then return nil end
  local L = ME.decode(b.learn)
  if not (L and L.H and #L.H > 1) then return nil end
  local out = {}
  for i, n in ipairs(L.H) do
    local e = L.shapes[i]
    local ok, t = false, nil
    if reaper.TrackFX_FormatParamValueNormalized then
      ok, t = reaper.TrackFX_FormatParamValueNormalized(track, addr, b.shape, n, "")
    end
    t = ok and t and t:match("^%s*(.-)%s*$") or ""
    out[i] = { s = i, norm = n, type = e and e.type, order = e and e.order, text = t }
  end
  return out
end

-- Sets a band's shape switch to its setting s (from ME.shapes).
function ME.set_shape(track, addr, b, s)
  if not b.shape then return end
  local L = ME.decode(b.learn)
  local n = L and L.H and L.H[s]
  if n then reaper.TrackFX_SetParamNormalized(track, addr, b.shape, n) end
end

-- What a shape setting is called in a menu: the plugin's name for it, and
-- what it was learned as when that says something more.
function ME.shape_label(sh)
  local kind = sh.type and ME.TYPES[sh.type] or nil
  if kind and sh.order and sh.order > 0 and (sh.type == "hp" or sh.type == "lp") then
    kind = kind .. (" %d dB/oct"):format(sh.order * 6)
  end
  if sh.text == "" then return kind or ("Setting " .. sh.s) end
  if not kind or sh.text:lower():find(kind:lower(), 1, true) then return sh.text end
  return sh.text .. "  \u{00B7}  " .. kind
end

-- Nudges the Q control (wheel): `d` in normalised steps.
function ME.nudge_q(track, addr, b, d)
  if not b.q then return end
  local v = math.max(0, math.min(1, norm(track, addr, b.q) + d))
  reaper.TrackFX_SetParamNormalized(track, addr, b.q, v)
end

-- ---------------------------------------------------------------------
-- guessing a mapping from parameter names
-- ---------------------------------------------------------------------

local BAND_WORDS = {
  { "hpf", "low cut", "lowcut", "lo cut", "high pass", "highpass", "hp " },
  { "low", "lf", "lo ", "bass" },
  { "low mid", "lmf", "lo mid", "lm " },
  { "mid", "mf" },
  { "high mid", "hmf", "hi mid", "hm " },
  { "high", "hf", "hi ", "treble", "air" },
  { "lpf", "high cut", "highcut", "hi cut", "low pass", "lowpass", "lp " },
}
local BAND_NAMES = { "Low cut", "Low", "Low mid", "Mid", "High mid", "High", "High cut" }

local function role_of(nm)
  if nm:match("freq") or nm:match("hz") or nm:match("frq") then return "freq" end
  if nm:match("gain") or nm:match("boost") or nm:match("level") or nm:match("db") then return "gain" end
  if nm:match("%f[%a]q%f[%A]") or nm:match("width") or nm:match("bandwidth") or nm:match("bw") then return "q" end
  if nm:match("shape") or nm:match("bell") or nm:match("peak") or nm:match("shelf") then return "shape" end
  if nm:match("%f[%a]on%f[%A]") or nm:match("enable") or nm:match("active") or nm:match("bypass") then return "on" end
  return nil
end

-- A dynamic EQ band's dynamics control from its name (checked before the
-- band's own roles: "Dynamic Range", "Dyn On"), or nil.
function ME.dyn_role_of(nm)
  if nm:match("auto") or nm:match("mode") or nm:match("sidechain") or nm:match("listen") then return nil end
  if nm:match("thresh") or nm:match("%f[%a]thr%f[%A]") then return "thr" end
  if nm:match("ratio") then return "ratio" end
  if nm:match("attack") or nm:match("%f[%a]atk%f[%A]") then return "atk" end
  if nm:match("release") or nm:match("%f[%a]rel%f[%A]") then return "rel" end
  if nm:match("range") or nm:match("dyn%a* gain") or nm:match("dyn%a* amount") then return "range" end
  if nm:match("dyn") and (nm:match("%f[%a]on%f[%A]") or nm:match("enable") or nm:match("active")
     or nm:match("bypass") or nm:match("%f[%a]off%f[%A]")) then return "on" end
  return nil
end

local function put_role(b, role, dyn, p)
  if dyn then
    b.dyn = b.dyn or { rev = {} }
    if not b.dyn[dyn] then b.dyn[dyn] = p end
  elseif not b[role] then b[role] = p end
end

-- A first go at bands from the parameters' names: { {name, freq, gain,
-- q, shape, on}, ... }, in band order. `names[p+1]` is parameter p's name.
function ME.guess(names)
  local bands = {}
  for p0, raw in ipairs(names) do
    local nm = " " .. (raw or ""):lower() .. " "
    local dyn = ME.dyn_role_of(nm)
    local role = (not dyn) and role_of(nm) or nil
    if role or dyn then
      local which
      -- the longest matching band word wins ("low mid" over "low")
      local best_len = 0
      for bi, words in ipairs(BAND_WORDS) do
        for _, w in ipairs(words) do
          if nm:find(w, 1, true) and #w > best_len then which, best_len = bi, #w end
        end
      end
      if which and (which == 1 or which == 7) and role ~= "freq" and role ~= "on" then which = nil end
      if which then
        bands[which] = bands[which] or { name = BAND_NAMES[which] }
        put_role(bands[which], role, dyn, p0 - 1)
      end
    end
  end
  local out = {}
  for i = 1, #BAND_WORDS do
    local b = bands[i]
    if b and (b.freq or b.gain) then out[#out + 1] = b end
  end
  if #out > 0 then return out end
  -- numbered bands: "Band 3 Gain", "Gain 3", "B3 Freq"
  local num = {}
  for p0, raw in ipairs(names) do
    local nm = " " .. (raw or ""):lower() .. " "
    local dyn = ME.dyn_role_of(nm)
    local role = (not dyn) and role_of(nm) or nil
    local n = nm:match("band%s*(%d+)") or nm:match("%f[%a]b(%d+)%f[%D]") or nm:match("(%d+)")
    n = tonumber(n)
    if (role or dyn) and n and n >= 1 and n <= 24 then
      num[n] = num[n] or { name = "Band " .. n }
      put_role(num[n], role, dyn, p0 - 1)
    end
  end
  local ks = {}
  for n, b in pairs(num) do if b.freq or b.gain then ks[#ks + 1] = n end end
  table.sort(ks)
  for i = 1, math.min(#ks, 8) do out[#out + 1] = num[ks[i]] end
  return out
end

return ME
