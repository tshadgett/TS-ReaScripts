-- @noindex
-- Not a package of its own: installed by TS_ChannelView.lua's @provides.
--[[
  TS_CV_ReaFX.lua -- ReaDelay's and ReaVerbate's own canvases: no setup,
  their controls known by name.

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

function RB.kind(key)
  local base = M.split_variant and select(1, M.split_variant(key or "")) or key
  if base == "ReaDelay" then return "readelay" end
  if base == "ReaVerbate" then return "reaverbate" end
  return nil
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
  local kind = RB.kind(key)
  if not kind or not layout then return layout end
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
