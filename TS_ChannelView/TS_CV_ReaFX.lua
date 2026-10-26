-- @noindex
-- Not a package of its own: installed by TS_ChannelView.lua's @provides.
--[[
  TS_CV_ReaFX.lua -- ReaDelay's and ReaVerbate's own canvases: no setup,
  their controls known by name. And ReaGate's and ReaLimit's default
  canvases: a gate and a limiter canvas their default layout starts with,
  its roles found by name, which Set up the canvas can change like any
  other's once it's saved.

  A layout for either (its saved one, or the generated default) is given
  its canvas here, in memory, every time it's fetched (M.get_or_default):
  a delay canvas for ReaDelay, its taps as REAPER has them; a reverb canvas
  for ReaVerbate. A canvas of another kind the user chose is left alone.
  Nothing is written to the library for it -- a decay measured for
  ReaVerbate is, with the layout, when it's measured.

  REAPDELAY'S TAPS
    Wet, Dry, then ten per tap ("1: Enabled", "1: Length (time)",
    "1: Length (musical)", Feedback, Lowpass, Hipass, Resolution, Stereo
    width, Volume, Pan). A tap's delay is its time plus its musical length
    (in eighth notes, "2.00 8N" a quarter), each tap feeding itself back.
    Taps are added and taken away through its stored state (vst_chunk): a
    header (taps at byte 9, each tap's size at 13) then each tap's floats,
    one more than its parameters (the first unused).
--]]

local M = require("TS_CV_Mappings")

local RB = {}

-- REAPER's plugins that ChannelView gives a panel of its own: ReaEQ's and
-- ReaComp's (TS_CV_EQPanel, TS_CV_CompPanel), and the canvases here. That
-- is their Standard layout; any other layout of theirs (Layout > Copy to
-- new layout, New empty layout, New canvas layout) is a normal one.
RB.PANELS = { ReaEQ = true, ReaComp = true, ReaGate = true, ReaLimit = true, ReaDelay = true, ReaVerbate = true }
local function base_of(key) return (M.split_variant and select(1, M.split_variant(key or ""))) or key end
function RB.has_panel(key) return RB.PANELS[base_of(key) or ""] == true end
-- ReaEQ's / ReaComp's own panel is shown: their Standard layout
function RB.own_eq(key) return key == "ReaEQ" end
function RB.own_comp(key) return key == "ReaComp" end

function RB.kind(key)
  local base = M.split_variant and select(1, M.split_variant(key or "")) or key
  if base == "ReaDelay" then return "readelay" end
  if base == "ReaVerbate" then return "reaverbate" end
  if base == "ReaGate" then return "reagate" end
  if base == "ReaLimit" then return "realimit" end
  return nil
end

-- ReaGate and ReaLimit: the canvas each default layout starts with, and
-- each role's control by the start of its name (case-blind; "Pre-open"
-- isn't the threshold, so a name has to START with the word).
RB.DEFAULT_CANVAS = {
  reagate  = { kind = "gate", roles = { Threshold = "threshold", Attack = "attack", Hold = "hold",
                                        Release = "release", Hysteresis = "hyster", Preopen = "pre-open",
                                        Lowpass = "lowpass", Hipass = "hipass", Preview = "preview",
                                        RMS = "rms size" },
               side = {} },
  realimit = { kind = "limit", roles = { Threshold = "threshold", Ceiling = "ceiling", Release = "release" },
               anywhere = { Ceiling = true } },
}

-- Role -> parameter for `kind` from the plugin's parameter names
-- (`names[p]`, 0-based).
function RB.roles_by_name(kind, names)
  local d = RB.DEFAULT_CANVAS[kind]
  local out = {}
  if not d then return out end
  for role, word in pairs(d.roles) do
    for p = 0, #names do
      local nm = (names[p] or ""):lower()
      local hit = (d.anywhere and d.anywhere[role]) and nm:find(word, 1, true) or nm:sub(1, #word) == word
      if hit then out[role] = p; break end
    end
  end
  return out
end

local name_cache = {}
local function param_names(track, addr, guid)
  local np = reaper.TrackFX_GetNumParams(track, addr) or 0
  local c = guid and name_cache[guid]
  if c and c.np == np then return c.names end
  local names = {}
  for p = 0, np - 1 do
    local _, nm = reaper.TrackFX_GetParamName(track, addr, p, "")
    names[p] = nm or ""
  end
  if guid then name_cache[guid] = { np = np, names = names } end
  return names
end

-- A default layout (never a saved one) for ReaGate or ReaLimit, given its
-- canvas: the roles found, and beside the canvas only the controls it
-- doesn't already show.
function RB.default_canvas(track, addr, guid, kind, layout)
  local d = RB.DEFAULT_CANVAS[kind]
  if not (d and layout) or layout.canvas then return layout end
  -- canvases are Pro: without it the default keeps every control
  if not require("TS_CV_Edition").PRO then return layout end
  local roles = RB.roles_by_name(kind, param_names(track, addr, guid))
  if not roles.Threshold then return layout end
  layout.canvas = { kind = d.kind, roles = roles, rev = {} }
  if d.side then
    -- beside it, the controls named (the rest stay in the plugin's window)
    local names, keep = param_names(track, addr, guid), {}
    for _, word in ipairs(d.side) do
      for p = 0, #names do
        if (names[p] or ""):lower():sub(1, #word) == word then
          keep[#keep + 1] = M.apply_default_look({ param = p, type = "knob", label = "" })
          break
        end
      end
    end
    layout.controls = keep
    return layout
  end
  local shown = {}
  for _, p in pairs(roles) do shown[p] = true end
  local keep = {}
  for _, c in ipairs(layout.controls or {}) do
    if not shown[c.param] then keep[#keep + 1] = c end
  end
  layout.controls = keep
  return layout
end

-- the tap count, from the parameters' names (kept while the count of
-- parameters doesn't change)
local tap_cache = {}
function RB.taps(track, addr, guid)
  local np = reaper.TrackFX_GetNumParams(track, addr) or 0
  local c = guid and tap_cache[guid]
  if c and c.np == np then return c.nt end
  local nt = 0
  for p = 2, np - 1 do
    local _, nm = reaper.TrackFX_GetParamName(track, addr, p, "")
    local k = tonumber((nm or ""):match("^(%d+):%s*Enabled"))
    if k and k > nt then nt = k end
  end
  if guid then tap_cache[guid] = { np = np, nt = nt } end
  return nt
end

-- ReaDelay's tap k's parameters: base index and roles
local TAP_FIELDS = { "On", "Time", "Note", "Feedback", "HighCut", "LowCut", false, false, "Level", "Pan" }
function RB.tap_base(k) return 2 + (k - 1) * 10 end

-- The layout with its canvas (in memory): ReaDelay's or ReaVerbate's.
function RB.ensure(track, addr, guid, key, layout)
  if not layout then return layout end
  -- (another layout of theirs is the user's own: left as it is)
  if M.split_variant and select(2, M.split_variant(key or "")) then return layout end
  local kind = RB.kind(key)
  if not kind then return layout end
  if RB.DEFAULT_CANVAS[kind] then return layout end     -- (theirs: RB.default_canvas)
  local want = (kind == "readelay") and "delay" or "reverb"
  local cv = layout.canvas
  if cv and cv.kind ~= want then return layout end
  if not cv then cv = { kind = want, roles = {}, rev = {} }; layout.canvas = cv end
  cv.builtin, cv.rev = kind, cv.rev or {}
  local roles = {}
  if kind == "readelay" then
    local nt = math.min(M.DL_TAPS, RB.taps(track, addr, guid))
    for k = 1, nt do
      local b = RB.tap_base(k)
      for i, r in ipairs(TAP_FIELDS) do if r then roles["T" .. k .. r] = b + i - 1 end end
    end
    roles.Mix, roles.Dry = 0, 1
    cv.nt = nt
  else
    roles = { Mix = 0, Decay = 2, Damping = 3, Predelay = 5, HighCut = 6, LowCut = 7 }
    -- its decay until it's measured: ReaVerbate is a Freeverb, its room
    -- size (30..98) the combs' feedback, their delays averaging 31 ms, so
    -- 60 dB down takes 3 x 31 ms / -log10(feedback)
    if not cv.dec_cal then
      local pts = {}
      for i = 0, 10 do
        local n = i / 10
        pts[#pts + 1] = { 0, n, 3 * 31.2 / -math.log(0.30 + 0.68 * n, 10) }
      end
      cv.dec_cal = { p = 2, s = nil, pts = pts, builtin = true }
    end
  end
  cv.roles = roles
  return layout
end

-- ---------------------------------------------------------------------
-- adding and taking away ReaDelay's taps
-- ---------------------------------------------------------------------
local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local DEC = {}
for i = 1, 64 do DEC[B64:byte(i)] = i - 1 end
function RB.b64dec(s)
  s = (s or ""):gsub("[^%w%+/]", "")
  local out = {}
  for i = 1, #s, 4 do
    local a, b, c, d = DEC[s:byte(i)], DEC[s:byte(i + 1) or 0], DEC[s:byte(i + 2) or 0], DEC[s:byte(i + 3) or 0]
    if not (a and b) then break end
    local n = a * 262144 + b * 4096 + (c or 0) * 64 + (d or 0)
    out[#out + 1] = string.char(n // 65536)
    if c then out[#out + 1] = string.char((n // 256) % 256) end
    if d then out[#out + 1] = string.char(n % 256) end
  end
  return table.concat(out)
end
function RB.b64enc(data)
  local out = {}
  for i = 1, #data, 3 do
    local a, b, c = data:byte(i, i + 2)
    local n = a * 65536 + (b or 0) * 256 + (c or 0)
    out[#out + 1] = B64:sub(n // 262144 + 1, n // 262144 + 1)
    out[#out + 1] = B64:sub((n // 4096) % 64 + 1, (n // 4096) % 64 + 1)
    out[#out + 1] = b and B64:sub((n // 64) % 64 + 1, (n // 64) % 64 + 1) or "="
    out[#out + 1] = c and B64:sub(n % 64 + 1, n % 64 + 1) or "="
  end
  return table.concat(out)
end

-- its state: header, taps (strings), tap size; nil when it doesn't read
function RB.state_split(raw)
  if #raw < 16 then return nil end
  local nt = string.unpack("<i4", raw, 9)
  local tsz = string.unpack("<i4", raw, 13)
  if nt < 1 or nt > 64 or tsz < 8 or tsz > 256 or #raw < nt * tsz + 16 then return nil end
  local hlen = #raw - nt * tsz
  local taps = {}
  for k = 1, nt do taps[k] = raw:sub(hlen + (k - 1) * tsz + 1, hlen + k * tsz) end
  return raw:sub(1, hlen), taps, tsz
end
function RB.state_join(head, taps)
  return head:sub(1, 8) .. string.pack("<i4", #taps) .. head:sub(13) .. table.concat(taps)
end
-- a tap with its musical length (the 4th float) moved on by `by` eighths
-- (stored as eighths / 256)
function RB.tap_moved(tap, tsz, by)
  local n = tsz // 4
  local fl = { string.unpack("<" .. string.rep("f", n), tap) }
  fl[4] = math.min(1, (fl[4] or 0) + by / 256)
  return string.pack("<" .. string.rep("f", n), table.unpack(fl, 1, n))
end

local function rewrite(track, addr, label, fn)
  local ok, c = reaper.TrackFX_GetNamedConfigParm(track, addr, "vst_chunk")
  if not ok then return false end
  local head, taps, tsz = RB.state_split(RB.b64dec(c))
  if not head then return false end
  local new = fn(taps, tsz)
  if not new then return false end
  reaper.Undo_BeginBlock()
  local done = reaper.TrackFX_SetNamedConfigParm(track, addr, "vst_chunk", RB.b64enc(RB.state_join(head, new)))
  reaper.Undo_EndBlock(label, -1)
  return done
end

-- ---------------------------------------------------------------------
-- ReaLimit's options that aren't parameters
-- ---------------------------------------------------------------------
-- Its state is a version (3) then a flags word, little-endian: 1 true
-- peak, 2 constant gain, 64 low latency (else high performance). Read and
-- set there; a state that doesn't start that way is left alone.
RB.LIMIT_FLAGS = { truepeak = 1, constgain = 2, lowlat = 64 }

local flag_cache = {}
function RB.limit_flags(track, addr, guid)
  local now = reaper.time_precise()
  local c = guid and flag_cache[guid]
  if c and now - c.t < 0.5 then return c.v end
  local ok, b64 = reaper.TrackFX_GetNamedConfigParm(track, addr, "vst_chunk")
  local raw = ok and RB.b64dec(b64) or ""
  local v = nil
  if #raw >= 8 and string.unpack("<i4", raw, 1) == 3 then v = string.unpack("<i4", raw, 5) end
  if guid then flag_cache[guid] = { t = now, v = v } end
  return v
end

-- One of them on or off (`name` a key of RB.LIMIT_FLAGS). One undo step.
function RB.set_limit_flag(track, addr, guid, name, on)
  local bit = RB.LIMIT_FLAGS[name]
  local ok, b64 = reaper.TrackFX_GetNamedConfigParm(track, addr, "vst_chunk")
  local raw = ok and RB.b64dec(b64) or ""
  if not bit or #raw < 8 or string.unpack("<i4", raw, 1) ~= 3 then return false end
  local v = string.unpack("<i4", raw, 5)
  v = on and (v | bit) or (v & ~bit)
  raw = raw:sub(1, 4) .. string.pack("<i4", v) .. raw:sub(9)
  reaper.Undo_BeginBlock()
  local done = reaper.TrackFX_SetNamedConfigParm(track, addr, "vst_chunk", RB.b64enc(raw))
  reaper.Undo_EndBlock("ReaLimit: " .. name .. (on and " on" or " off"), -1)
  if guid then flag_cache[guid] = nil end
  return done
end

-- a tap more: the last one again, an eighth later
function RB.add_tap(track, addr)
  return rewrite(track, addr, "ReaDelay: add tap", function(taps, tsz)
    if #taps >= M.DL_TAPS then return nil end
    taps[#taps + 1] = RB.tap_moved(taps[#taps], tsz, 1)
    return taps
  end)
end

-- Whether tap k can go: not the only one, and no automation on a later
-- tap's controls (they'd move onto the tap before)
function RB.can_remove(track, addr, k, nt)
  if nt <= 1 then return false, "ReaDelay keeps at least one tap" end
  for p = RB.tap_base(k + 1), RB.tap_base(nt + 1) - 1 do
    if reaper.GetFXEnvelope(track, addr, p, false) then
      return false, "A later tap has automation: it would move onto this tap's controls"
    end
  end
  if reaper.GetFXEnvelope then
    for p = RB.tap_base(k), RB.tap_base(k + 1) - 1 do
      if reaper.GetFXEnvelope(track, addr, p, false) then return false, "This tap has automation" end
    end
  end
  return true
end
function RB.remove_tap(track, addr, k)
  return rewrite(track, addr, "ReaDelay: remove tap", function(taps)
    if #taps <= 1 or not taps[k] then return nil end
    table.remove(taps, k)
    return taps
  end)
end

return RB
