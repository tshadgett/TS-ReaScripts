-- @noindex
-- Not a package of its own: installed by TS_ChannelView.lua's @provides.
--[[
  TS_CV_Delay.lua -- a delay canvas's echoes, worked out from whichever
  controls a plugin has, and the way back: a drag to a time, a level or a
  feedback, set on those controls.

  Delays tackle the same few things in very different ways (a ping-pong
  switch or a mode to choose; a time in ms, a note switch, a division and
  a "rhythm" beside it, a % of a longest time; two lines or ten taps). So
  everything is turned into one model, and the canvas (desktop and web)
  only draws that model and hands its drags back here:

    LINES   a delay of one or two lines: the left's time (or the one for
            both), the right's (its own, an offset, a ratio), each one's
            feedback and the cross-feedback between them, the stereo mode
            (mono / dual / ping-pong) and the width.
    TAPS    a multi-tap: up to M.DL_TAPS taps, each with its own time (or a
            % of the main time, or k/n of it), level, pan, on, ping-pong
            and feedback of its own; the whole pattern repeating every main
            time (or every longest tap) by the feedback.

  Echoes come out as { t ms, l, r } -- how much of each comes out of the
  left and of the right (the dry sound 1) -- and handles as
  { id, t, side, h, k, pow, v0, across, updown, label, num }: where it's
  drawn (t, the side its height is on, h), and how a drag maps back
  (across: a time; updown: v0 the value it controls, k the height a unit
  of it draws, pow 2 when the drawn height is the value squared).

  TIME, with sync on, snaps to what the plugin can reach: its note
  settings times its rhythm settings (straight / dotted / triplet), or,
  for a time in ms that follows the tempo ("Note Snap"), the note values
  at the tempo. Everything that touches REAPER goes through `io`
  (DL.io), so the model runs under the tests.
--]]

local UN = require("TS_CV_Units")
local M  = require("TS_CV_Mappings")

local DL = {}

-- ---------------------------------------------------------------------
-- reading controls
-- ---------------------------------------------------------------------

-- a switch that's on: its text when that says, else past halfway
function DL.on_of(m)
  if not m then return false end
  local s = " " .. (m.text or ""):lower() .. " "
  if s:find("disabl", 1, true) or s:find("bypass", 1, true) or s:find(" off ", 1, true) or s:find(" out ", 1, true)
     or s:find(" no ", 1, true) or s:find("inactive", 1, true) or s:find("mute", 1, true) then return false end
  if s:find(" on ", 1, true) or s:find("enabl", 1, true) or s:find(" in ", 1, true) or s:find(" yes ", 1, true)
     or s:find("active", 1, true) then return true end
  return (m.n or 0) >= 0.5
end

-- a control read 0..1(.5): a %, or along its range
local function frac(m, rev, key)
  if not m then return nil end
  if m.unit == "pct" and m.v then return math.max(0, math.min(1.5, m.v / 100)) end
  return (rev and rev[key]) and (1 - m.n) or m.n
end
DL.frac = frac

-- a feedback 0..1(.5): a %, dB (a gain: ReaDelay's), or along its range
local function fb_of(m, rev, key)
  if not m then return nil end
  if m.unit == "db" and m.v then return m.v <= -90 and 0 or math.min(1.5, 10 ^ (m.v / 20)) end
  return frac(m, rev, key)
end
DL.fb_of = fb_of

-- ReaDelay's musical length: eighth notes ("2.00 8N")
function DL.eighths_of(m)
  if not m then return 0 end
  local v = tonumber((m.text or ""):match("([%d%.]+)"))
  return v or 0
end

-- a level 0..1: a %, dB, or along its range
local function level_of(m, rev, key)
  if not m then return 1 end
  if m.unit == "pct" and m.v then return math.max(0, math.min(1.5, m.v / 100)) end
  if m.unit == "db" and m.v then return m.v <= -90 and 0 or math.min(2, 10 ^ (m.v / 20)) end
  return (rev and rev[key]) and (1 - m.n) or m.n
end

-- a pan -1 (left) .. 1 (right): "L--", "L50", "-C-", "50R", "--R", -100..100
function DL.pan_of(m, rev, key)
  if not m then return 0 end
  local s = (m.text or ""):upper()
  local l, r = s:match("^%s*L"), s:match("R%s*$")
  local num = tonumber(s:match("(%d+%.?%d*)") or "")
  if s:find("C") and not s:find("%d") then return 0 end
  if l and not r then return num and -math.min(1, num / 100) or -1 end
  if r and not l then return num and math.min(1, num / 100) or 1 end
  if m.v and m.unit ~= "pct" and math.abs(m.v) <= 100 and math.abs(m.v) > 1.0001 then return m.v / 100 end
  if m.v and m.unit == "pct" then return math.max(-1, math.min(1, m.v / 100)) end
  if m.v and math.abs(m.v) <= 1 and (s:find("-", 1, true) or m.v ~= 0) then return m.v end
  local n = (rev and rev[key]) and (1 - m.n) or m.n
  return n * 2 - 1
end

-- what a rhythm (feel) setting does to a note: dotted x1.5, triplet x2/3
function DL.rhythm_of(text)
  local s = (text or ""):lower()
  if s:find("dot", 1, true) or s:match("^%s*d%s*$") or s:find("%.%s*$") then return 1.5 end
  if s:find("trip", 1, true) or s:match("^%s*t%s*$") then return 2 / 3 end
  return 1
end

-- ---------------------------------------------------------------------
-- time
-- ---------------------------------------------------------------------

-- A time from a set of controls { Time, Note, Rhythm, Sync } (any may be
-- missing): { ms, how = "note" | "ms" | "along", src, key, sync }, or nil.
-- ctx: { bpm, sync (the plugin's), mult, rev, keys = { Time =, Note =, ... } }
function DL.time_of(set, ctx)
  local beat = 60000 / ((ctx.bpm and ctx.bpm > 1) and ctx.bpm or 120)
  local sync = ctx.sync
  if set.Sync then sync = M.dl_sync_of(set.Sync.text, set.Sync.n) end
  local mult = ctx.mult or 1
  local keys = set.keys or {}
  if set.Note and (sync or not set.Time) then
    local b = UN.note_beats(set.Note.text or "")
    if b then
      local f = set.Rhythm and DL.rhythm_of(set.Rhythm.text) or 1
      return { ms = b * f * beat * mult, how = "note", src = set.Note, key = keys.Note, sync = sync }
    end
  end
  local m = set.Time or set.Note
  if not m then return nil end
  local key = (m == set.Time) and keys.Time or keys.Note
  local ms = UN.time_ms(m.text, ctx.bpm)
  if ms then
    if UN.note_beats(m.text or "") and set.Rhythm then ms = ms * DL.rhythm_of(set.Rhythm.text) end
    return { ms = ms * mult, how = "ms", src = m, key = key, sync = sync }
  end
  local n = (ctx.rev and ctx.rev[key]) and (1 - m.n) or m.n
  return { ms = 10 * 200 ^ n * mult, how = "along", src = m, key = key, sync = sync }
end

-- The note values a tempo-following time can land on: straight, dotted
-- and triplet, 1/64 to 4 bars; each { beats, label }.
DL.GRID = {}
do
  local seen = {}
  for _, b in ipairs({ 1 / 16, 1 / 8, 1 / 4, 1 / 2, 1, 2, 4, 8, 16 }) do
    for _, f in ipairs({ 1, 1.5, 2 / 3 }) do
      local v = b * f
      local k = ("%.5f"):format(v)
      if not seen[k] then seen[k] = true; DL.GRID[#DL.GRID + 1] = v end
    end
  end
  table.sort(DL.GRID)
end
function DL.snap_beats(beats)
  local best, bd
  for _, g in ipairs(DL.GRID) do
    local d = math.abs(math.log(g) - math.log(math.max(1e-6, beats)))
    if not bd or d < bd then best, bd = g, d end
  end
  return best
end

-- A time in beats as a note value: "1/8", "1/8 D", "1/8 T", "1 bar", "5/4";
-- nil for none.
function DL.note_label(beats)
  if not beats or beats <= 0 then return nil end
  local s = M.dl_note_label(beats)
  if s then
    -- a plain fraction that's really a dotted one reads better as such
    local d = M.dl_note_label(beats / 1.5)
    if d and s:match("^3/") and not d:find("bar") then return d .. " D" end
    return s
  end
  local d = M.dl_note_label(beats / 1.5)
  if d then return d .. " D" end
  local t = M.dl_note_label(beats * 1.5)
  if t then return t .. " T" end
  return nil
end

-- Set a set of time controls to `target` ms (snapping while synced), via
-- io: { positions(m) -> { {norm, text, lo, hi} } | nil, set_norm(m, n), set_to(m, v) }.
function DL.set_time(set, target, ctx, io)
  local tm = DL.time_of(set, ctx)
  if not tm then return end
  local beat = 60000 / ((ctx.bpm and ctx.bpm > 1) and ctx.bpm or 120)
  local mult = ctx.mult or 1
  target = math.max(1, target) / mult
  local function logd(a, b) return math.abs(math.log(math.max(1e-6, a)) - math.log(math.max(1e-6, b))) end
  if tm.how == "note" then
    local notes = io.positions(set.Note)
    if not notes then return end
    local rh = set.Rhythm and io.positions(set.Rhythm) or nil
    local best, bd
    for _, nt in ipairs(notes) do
      local b = UN.note_beats(nt.text)
      if b then
        if rh then
          for _, r in ipairs(rh) do
            local d = logd(b * DL.rhythm_of(r.text) * beat, target)
            if not bd or d < bd then best, bd = { nt.norm, r.norm }, d end
          end
        else
          local d = logd(b * beat, target)
          if not bd or d < bd then best, bd = { nt.norm }, d end
        end
      end
    end
    if best then
      if math.abs(best[1] - set.Note.n) > 1e-6 then io.set_norm(set.Note, best[1]) end
      if best[2] and set.Rhythm and math.abs(best[2] - set.Rhythm.n) > 1e-6 then io.set_norm(set.Rhythm, best[2]) end
    end
    return
  end
  local m = tm.src
  -- a time in ms that follows the tempo: onto the note values
  if tm.sync and tm.how ~= "note" and not UN.note_beats(m.text or "") then
    target = DL.snap_beats(target / beat) * beat
  end
  local sw = io.positions(m)
  if sw and #sw >= 2 then
    local best, bd
    for _, s_ in ipairs(sw) do
      local v = UN.time_ms(s_.text, ctx.bpm)
      if v then local d = logd(v, target); if not bd or d < bd then best, bd = s_.norm, d end end
    end
    if best then if math.abs(best - m.n) > 1e-6 then io.set_norm(m, best) end return end
  end
  if tm.how == "along" then
    local n = math.max(0, math.min(1, math.log(math.max(10, target) / 10) / math.log(200)))
    io.set_norm(m, (ctx.rev and ctx.rev[tm.key]) and (1 - n) or n)
  else
    io.set_to(m, target)
  end
end

-- ---------------------------------------------------------------------
-- the stereo mode
-- ---------------------------------------------------------------------

-- "mono", "dual", "pp" or nil (nothing said): a ping-pong switch that's
-- on; the mode switch's setting, by what setup was told it means, or by
-- its name; a mode toggle named for ping-pong that's on.
function DL.mode(R, modes, mode_name)
  if R.PingPong and DL.on_of(R.PingPong) then return "pp" end
  local m = R.Mode
  if not m then return nil end
  local t = m.text or ""
  local said = modes and modes[t]
  if said then return said ~= "none" and said or nil end
  local g = M.dl_mode_of(t)
  if g then return g end
  local nm = (mode_name or ""):lower()
  if (nm:find("ping", 1, true) or nm:find("pong", 1, true)) then return DL.on_of(m) and "pp" or nil end
  return nil
end

-- ---------------------------------------------------------------------
-- the model
-- ---------------------------------------------------------------------

local function set_of(R, pre)
  pre = pre or ""
  local s = { Time = R[pre .. "Time"], Note = R[pre .. "Note"], Rhythm = R[pre .. "Rhythm"], Sync = R[pre .. "Sync"],
              keys = { Time = pre .. "Time", Note = pre .. "Note" } }
  return s
end

-- The right's offset (ms) from the left's time: ms, a note value, % of the
-- left's time, or along its range (+/- half); and how it reads.
local function offset_of(m, rev, tL, bpm)
  if m.v and m.unit == "ms" then return m.v, "ms" end
  local nb = UN.note_beats(m.text or "")
  if nb then return nb * 60000 / bpm, "note" end
  if m.v and m.unit == "pct" then return tL * m.v / 100, "pct" end
  local n = rev.Offset and (1 - m.n) or m.n
  return (n - 0.5) * tL, "along"
end
local function ratio_of(m, rev)
  local r = M.dl_ratio_of(m.text)
  if r then return r, true end
  local n = rev.Ratio and (1 - m.n) or m.n
  return math.max(0.05, n * 2), false
end

-- R: the role readings; cv: the canvas (rev, nt taps, dmodes); o: { bpm,
-- names = role -> the plugin's parameter name (for a mode toggle) }.
-- Returns the model: { sync, beat, span, stereo, mode, echoes = { {t, l, r} },
-- decay = { L = {{t, h}}, R = ... }, handles, period, taps }.
function DL.model(R, cv, o)
  o = o or {}
  local rev = cv.rev or {}
  local bpm = (o.bpm and o.bpm > 1) and o.bpm or 120
  local beat = 60000 / bpm
  local sync = R.Sync and M.dl_sync_of(R.Sync.text, R.Sync.n) or false
  local mult = 1
  if R.Multiplier then
    local v = R.Multiplier.v
    mult = (v and v > 0 and v <= 16) and v or (0.5 + 1.5 * R.Multiplier.n)
  end
  local ctx = { bpm = bpm, sync = sync, mult = mult, rev = rev }
  local mode = DL.mode(R, cv.dmodes, o.names and o.names.Mode)
  local width = math.min(1.5, frac(R.Width, rev, "Width") or 1)
  local fb = fb_of(R.Feedback, rev, "Feedback") or 0.5
  local mdl = { sync = sync, beat = beat, bpm = bpm, mode = mode, handles = {}, echoes = {}, decay = {} }
  local main = DL.time_of(set_of(R), ctx)
  mdl.main = main
  mdl.beat_grid = sync or (main and main.how == "note") or false
  local nt = math.max(0, math.min(M.DL_TAPS, cv.nt or 0))

  local function add(t, l, r, tag)
    mdl.echoes[#mdl.echoes + 1] = { t = t, l = l, r = r, tag = tag }
  end

  if nt > 0 then
    -- ---- taps
    local taps, longest = {}, 0
    for k = 1, nt do
      local pre = "T" .. k
      local tp = { k = k, on = R[pre .. "On"] and DL.on_of(R[pre .. "On"]) or (R[pre .. "On"] == nil) }
      tp.set = set_of(R, pre)
      tp.level = level_of(R[pre .. "Level"], rev, pre .. "Level")
      tp.pan = DL.pan_of(R[pre .. "Pan"], rev, pre .. "Pan")
      tp.pp = (R[pre .. "PingPong"] and DL.on_of(R[pre .. "PingPong"])) or mode == "pp"
      tp.fb = R[pre .. "Feedback"] and fb_of(R[pre .. "Feedback"], rev, pre .. "Feedback") or nil
      taps[k] = tp
    end
    -- the main time: the one the pattern repeats on (else the longest tap)
    local P = main and main.ms or nil
    local rd = cv.builtin == "readelay"
    local all_musical = rd
    for _, tp in ipairs(taps) do
      local tm = tp.set.Time
      if rd then
        -- ReaDelay: its time plus its musical length, added
        local ms = (tm and tm.v and tm.unit == "ms") and tm.v or 0
        local e8 = DL.eighths_of(tp.set.Note)
        tp.t, tp.how, tp.ms_part, tp.e8 = ms + e8 * beat / 2, "rd", ms, e8
        if tp.on and ms >= 0.5 then all_musical = false end
      elseif tm and tm.unit == "pct" and tm.v then
        tp.how = "pct"
      elseif tp.set.Time or tp.set.Note then
        local t = DL.time_of(tp.set, ctx)
        tp.t, tp.tm = t and t.ms, t
        tp.how = "own"
      else
        tp.how = "share"
      end
    end
    for _, tp in ipairs(taps) do if tp.on and tp.t then longest = math.max(longest, tp.t) end end
    P = P or (longest > 0 and longest) or 500
    for _, tp in ipairs(taps) do
      if tp.how == "pct" then tp.t = P * tp.set.Time.v / 100
      elseif tp.how == "share" then tp.t = P * tp.k / nt end
      tp.t = math.max(1, tp.t or P)
    end
    mdl.period, mdl.taps = P, taps
    if rd then mdl.beat_grid = all_musical end
    local span = 0
    for _, tp in ipairs(taps) do if tp.on then span = math.max(span, tp.t) end end
    span = math.max(600, math.min(12000, math.max(span, P) * ((fb > 0.05) and 3.2 or 1.5)))
    mdl.span = span
    local floor = 0.012
    for _, tp in ipairs(taps) do
      if tp.on then
        local own = tp.fb ~= nil
        local per, g = own and tp.t or P, own and tp.fb or fb
        local r = 0
        while r < 64 do
          local t = tp.t + r * per
          local a = tp.level * (g ^ r)
          if t > span or (r > 0 and a < floor) then break end
          local pan = tp.pan * width
          if tp.pp and r % 2 == 1 then pan = -pan end
          pan = math.max(-1, math.min(1, pan))
          add(t, a * math.min(1, 1 - pan), a * math.min(1, 1 + pan), { k = tp.k, r = r })
          r = r + 1
        end
      end
    end
    table.sort(mdl.echoes, function(a, b) return a.t < b.t end)
    -- each tap's repeats, joined (dashed when drawn): { {t, height}, ... },
    -- the height above the line for the left, below (negative) the right
    mdl.chains = {}
    for _, tp in ipairs(taps) do
      local ch = {}
      for _, x in ipairs(mdl.echoes) do
        if x.tag.k == tp.k then ch[#ch + 1] = { x.t, (x.l >= x.r) and x.l or -x.r } end
      end
      if #ch >= 2 then mdl.chains[#mdl.chains + 1] = ch end
    end
    -- handles: each tap on its first echo; the feedback on the first
    -- repeat; the main time on the period line
    for _, tp in ipairs(taps) do
      if tp.on then
        local e
        for _, x in ipairs(mdl.echoes) do if x.tag.k == tp.k and x.tag.r == 0 then e = x break end end
        if e then
          local up = e.l >= e.r
          local side_k = up and math.min(1, 1 - tp.pan * width) or math.min(1, 1 + tp.pan * width)
          local pre = "T" .. tp.k
          local tl = tp.how == "own" and tp.tm and DL.label_of(tp.tm, mdl) or (tp.how == "pct" and (R[pre .. "Time"].text or ""))
                     or (tp.how == "rd" and (mdl.beat_grid and DL.note_label(tp.t / beat) or ("%.0f ms"):format(tp.t))) or nil
          mdl.handles[#mdl.handles + 1] = { id = "t" .. tp.k, num = tp.k, t = e.t, tq0 = tp.t, side = up and "L" or "R",
            h = up and e.l or e.r, k = side_k, pow = 1, v0 = tp.level,
            across = (tp.how ~= "share"), updown = R[pre .. "Level"] ~= nil,
            label = tl, pan = tp.pan, haspan = R[pre .. "Pan"] ~= nil }
          -- its own feedback (drawn only while the tap is selected): its
          -- first repeat, up or down
          local fm = R[pre .. "Feedback"]
          if fm and tp.fb then
            local found
            for _, x in ipairs(mdl.echoes) do
              if x.tag.k == tp.k and x.tag.r == 1 then
                local u2 = x.l >= x.r
                local hh = u2 and x.l or x.r
                mdl.handles[#mdl.handles + 1] = { id = "f" .. tp.k, own = tp.k, t = x.t, side = u2 and "L" or "R", h = hh,
                  k = hh / math.max(1e-6, tp.fb), pow = 1, v0 = tp.fb, updown = true, label = "Feedback " .. (fm.text or "") }
                found = true
                break
              end
            end
            -- none yet (no feedback): just off the line where its first
            -- repeat would be, to drag up from
            if not found and tp.t * 2 <= mdl.span then
              local sk = math.min(1, 1 - (tp.pp and -tp.pan or tp.pan) * width)
              mdl.handles[#mdl.handles + 1] = { id = "f" .. tp.k, own = tp.k, t = tp.t * 2, side = up and "L" or "R", h = 0.06,
                k = math.max(0.05, tp.level * sk), pow = 1, v0 = 0, updown = true, label = "Feedback " .. (fm.text or "") }
            end
          end
        end
      end
    end
    -- the pattern's feedback: the first repeat of a tap that hasn't its own
    local first
    for _, x in ipairs(mdl.echoes) do if x.tag.r == 1 and taps[x.tag.k].fb == nil then first = x break end end
    if first and R.Feedback then
      local up = first.l >= first.r
      mdl.handles[#mdl.handles + 1] = { id = "fb", t = first.t, side = up and "L" or "R", h = up and first.l or first.r,
        k = (up and first.l or first.r) / math.max(1e-6, fb), pow = 1, v0 = fb, updown = true,
        label = "Feedback " .. (R.Feedback.text or "") }
    end
    if main and (R.Time or R.Note) then
      mdl.handles[#mdl.handles + 1] = { id = "time", t = P, tq0 = P, side = "top", h = 0, across = true,
        label = "Time " .. DL.label_of(main, mdl) }
    end
  else
    -- ---- one or two lines
    local tL = main and main.ms or nil
    local stereo = (R.TimeR or R.NoteR or R.Offset or R.Ratio or R.FeedbackR or R.Cross or R.Width or R.Mode or R.PingPong)
                   and mode ~= "mono" and true or false
    local link = R.Link and DL.on_of(R.Link)
    local rset = { Time = R.TimeR, Note = R.NoteR, Rhythm = R.Rhythm, Sync = nil, keys = { Time = "TimeR", Note = "NoteR" } }
    local rk, tR, rtm, offhow, ratio_read
    if tL and stereo then
      if (R.TimeR or R.NoteR) and not link then
        rtm = DL.time_of(rset, ctx)
        rk, tR = "own", rtm and rtm.ms
      elseif R.Offset then
        local off
        off, offhow = offset_of(R.Offset, rev, tL, bpm)
        rk, tR = "offset", math.max(1, tL + off)
      elseif R.Ratio then
        local r
        r, ratio_read = ratio_of(R.Ratio, rev)
        rk, tR = "ratio", math.max(1, tL * r)
      end
    end
    tR = tR or tL
    local w = stereo and math.min(1, width) or 0
    local fbR = R.FeedbackR and frac(R.FeedbackR, rev, "FeedbackR") or fb
    local cross = R.Cross and frac(R.Cross, rev, "Cross") or 0
    local lo
    if not stereo then lo = { tL = tL, tR = tL, fbL = fb, fbR = fb, inL = 1, inR = 1 }
    elseif mode == "pp" then lo = { tL = tL, tR = tR, fbL = 0, fbR = 0, cross = fb, inL = 1, inR = 0 }
    else lo = { tL = tL, tR = tR, fbL = fb, fbR = fbR, cross = cross, inL = 1, inR = 1 } end
    mdl.stereo, mdl.rk, mdl.offhow, mdl.ratio_read, mdl.rtm = stereo, rk, offhow, ratio_read, rtm
    local span = math.max(600, math.min(8000, math.max(tL or 300, tR or 0) * 5.2))
    mdl.span = span
    if tL then
      lo.span, lo.floor = span, 0.012
      local taps = M.dl_taps(lo)
      local bars = M.dl_bars(taps, w)
      for _, b in ipairs(bars) do add(b.t, b.l, b.r, {}) end
      for _, sd in ipairs(stereo and { "L", "R" } or { "L" }) do
        local d = {}
        for _, e in ipairs(taps) do
          if e.sd == sd then local b = bars[e.bar]; d[#d + 1] = { e.t, sd == "L" and b.l or b.r } end
        end
        mdl.decay[sd] = d
      end
      local def_k = stereo and (1 + w) / 2 or 1
      local function at(t, sd)
        for _, e in ipairs(taps) do
          if e.sd == sd and math.abs(e.t - t) < 0.6 then
            local b = bars[e.bar]
            local hh = sd == "L" and b.l or b.r
            return hh, (e.a > 1e-6) and hh / e.a or def_k
          end
        end
        return 0, def_k
      end
      if tL <= span and main then
        local h = at(tL, "L")
        mdl.handles[#mdl.handles + 1] = { id = "time", t = tL, tq0 = tL, side = "L", h = h, across = true,
          label = (rk and "Time L " or "Time ") .. DL.label_of(main, mdl) }
      end
      if rk and tR then
        local t1 = mode == "pp" and (tL + tR) or tR
        if t1 <= span then
          local h = at(t1, "R")
          local lab = rk == "own" and ("Time R " .. DL.label_of(rtm, mdl))
                      or rk == "offset" and ("Offset " .. (R.Offset.text or ""))
                      or ("Ratio " .. (R.Ratio.text or ""))
          mdl.handles[#mdl.handles + 1] = { id = "timeR", t = t1, tq0 = tR, side = "R", h = h, across = true, label = lab }
        end
      end
      if R.Feedback then
        local twice = mode == "pp" and stereo
        local t2 = twice and (2 * tL + tR) or 2 * tL
        if t2 <= span then
          local h, kk = at(t2, "L")
          mdl.handles[#mdl.handles + 1] = { id = "fb", t = t2, side = "L", h = h, k = kk, pow = twice and 2 or 1, v0 = fb,
            updown = true, label = (R.FeedbackR and "Feedback L " or "Feedback ") .. (R.Feedback.text or "") }
        end
      end
      if R.FeedbackR and stereo and mode ~= "pp" and 2 * tR <= span then
        local h, kk = at(2 * tR, "R")
        mdl.handles[#mdl.handles + 1] = { id = "fbR", t = 2 * tR, side = "R", h = h, k = kk, pow = 1, v0 = fbR,
          updown = true, label = "Feedback R " .. (R.FeedbackR.text or "") }
      end
    end
    mdl.tL, mdl.tR = tL, tR
  end
  mdl.stereo = mdl.stereo or nt > 0
  -- its filters (a low cut and a high cut), the plugin's own or each tap's
  local function hz_of(m, key)
    if m.unit == "hz" and m.v then return m.v end
    local n = rev[key] and (1 - m.n) or m.n
    return 20 * 1000 ^ n
  end
  local function tone_of(pre)
    local lc, hc = R[pre .. "LowCut"], R[pre .. "HighCut"]
    if not (lc or hc) then return nil end
    return { lc = lc and hz_of(lc, pre .. "LowCut"), hc = hc and hz_of(hc, pre .. "HighCut"),
             lct = lc and lc.text, hct = hc and hc.text, k = tonumber(pre:match("%d+") or "") }
  end
  mdl.tone = tone_of("")
  if mdl.taps then
    mdl.tones = {}
    for _, tp in ipairs(mdl.taps) do mdl.tones[tp.k] = tone_of("T" .. tp.k) end
  end
  return mdl
end

-- A time's label: its note value while it follows the tempo (or reads in
-- notes), "1/4  (500 ms)" for a note when not, else its text.
function DL.label_of(tm, mdl)
  if not tm then return "" end
  local txt = tm.src and tm.src.text or ""
  local nb = UN.note_beats(txt)
  if mdl.beat_grid then
    if tm.how == "note" then
      local nl = DL.note_label(tm.ms / mdl.beat)
      return nl or txt
    end
    if nb then return txt end
    return DL.note_label(tm.ms / mdl.beat) or txt
  end
  if nb then return ("%s  (%.0f ms)"):format(txt, tm.ms) end
  return txt
end

-- A drag's new value for an up/down handle: `dpx` pixels (down positive),
-- `scale` pixels a unit of height.
function DL.drag_value(hd, dpx, scale)
  local per = math.max(1e-6, (hd.k or 1) * scale)
  local sgn = (hd.side == "R") and 1 or -1
  local d = sgn * dpx / per
  if hd.pow == 2 then return math.sqrt(math.max(0, (hd.v0 or 0) ^ 2 + d)) end
  return math.max(0, (hd.v0 or 0) + d)
end

-- ---------------------------------------------------------------------
-- the way back
-- ---------------------------------------------------------------------

-- Apply a drag: handle `id`, `what` "t" (a time, ms, of what it controls)
-- or "v" (its value: a level or feedback 0..1), on R's controls.
function DL.apply(R, cv, o, io, id, what, value)
  local rev = cv.rev or {}
  local bpm = (o.bpm and o.bpm > 1) and o.bpm or 120
  local sync = R.Sync and M.dl_sync_of(R.Sync.text, R.Sync.n) or false
  local mdl = DL.model(R, cv, o)
  local ctx = { bpm = bpm, sync = sync, mult = 1, rev = rev }
  if R.Multiplier then
    local v = R.Multiplier.v
    ctx.mult = (v and v > 0 and v <= 16) and v or (0.5 + 1.5 * R.Multiplier.n)
  end
  local function set_frac(m, key, nv)
    nv = math.max(0, math.min(1.5, nv))
    if m.unit == "db" and m.v then io.set_to(m, nv <= 0.001 and -150 or 20 * math.log(nv, 10))
    elseif m.unit == "pct" and m.v then io.set_to(m, nv * 100)
    else nv = math.min(1, nv); io.set_norm(m, rev[key] and (1 - nv) or nv) end
  end
  if id == "time" then
    DL.set_time(set_of(R), value, ctx, io)
  elseif id == "timeR" then
    local tL = mdl.tL
    if not tL then return end
    if mdl.rk == "own" then
      DL.set_time({ Time = R.TimeR, Note = R.NoteR, Rhythm = R.Rhythm, keys = { Time = "TimeR", Note = "NoteR" } }, value, ctx, io)
    elseif mdl.rk == "offset" then
      local m, off = R.Offset, value - tL
      if mdl.offhow == "ms" then io.set_to(m, off)
      elseif mdl.offhow == "note" then
        local sw = io.positions(m)
        if sw then
          local best, bd
          for _, s_ in ipairs(sw) do
            local b = UN.note_beats(s_.text)
            if b then local d = math.abs(b * 60000 / bpm - off); if not bd or d < bd then best, bd = s_.norm, d end end
          end
          if best then io.set_norm(m, best) end
        end
      elseif mdl.offhow == "pct" then io.set_to(m, off / tL * 100)
      else
        local n = math.max(0, math.min(1, off / tL + 0.5))
        io.set_norm(m, rev.Offset and (1 - n) or n)
      end
    elseif mdl.rk == "ratio" then
      local m, r = R.Ratio, value / tL
      local sw = io.positions(m)
      local best, bd
      for _, s_ in ipairs(sw or {}) do
        local v = M.dl_ratio_of(s_.text)
        if v then local d = math.abs(math.log(v) - math.log(math.max(1e-3, r))); if not bd or d < bd then best, bd = s_.norm, d end end
      end
      if best and sw and #sw >= 2 and #sw <= 48 then io.set_norm(m, best)
      elseif mdl.ratio_read then io.set_to(m, (m.text or ""):find("%%") and r * 100 or r)
      else local k = math.max(0, math.min(1, r / 2)); io.set_norm(m, rev.Ratio and (1 - k) or k) end
    end
  elseif id == "fb" and R.Feedback then
    set_frac(R.Feedback, "Feedback", value)
  elseif id == "fbR" and R.FeedbackR then
    set_frac(R.FeedbackR, "FeedbackR", value)
  elseif (id or ""):match("^[lh]c%d*$") then
    -- a low or high cut, to `value` Hz: as it reads, or along 20 Hz .. 20 kHz
    local which, kk = id:match("^([lh]c)(%d*)$")
    local key = ((kk ~= "") and ("T" .. kk) or "") .. ((which == "lc") and "LowCut" or "HighCut")
    local m = R[key]
    if m then
      local hz = math.max(20, math.min(20000, value))
      if m.unit == "hz" and m.v then io.set_to(m, hz)
      else
        local n = math.max(0, math.min(1, math.log(hz / 20) / math.log(1000)))
        io.set_norm(m, rev[key] and (1 - n) or n)
      end
    end
  elseif (id or ""):match("^f%d+$") then
    local m = R["T" .. id:sub(2) .. "Feedback"]
    if m then set_frac(m, "T" .. id:sub(2) .. "Feedback", value) end
  elseif (id or ""):match("^p%d+$") then
    -- a tap's pan, -1 (left) .. 1 (right): along its range
    local key = "T" .. id:sub(2) .. "Pan"
    local m = R[key]
    if m then
      local n = math.max(0, math.min(1, (value + 1) / 2))
      io.set_norm(m, rev[key] and (1 - n) or n)
    end
  else
    local k = tonumber((id or ""):match("^t(%d+)$") or "")
    if not k then return end
    local pre = "T" .. k
    if what == "t" then
      local tm = R[pre .. "Time"]
      local tp = mdl.taps and mdl.taps[k]
      if cv.builtin == "readelay" and tp then
        -- ReaDelay: a musical tap snaps its musical length onto note
        -- values (its time in ms kept); one set in ms moves its ms
        local beat = mdl.beat
        if tp.ms_part < 0.5 and R[pre .. "Note"] then
          io.set_to(R[pre .. "Note"], DL.snap_beats(math.max(1, value) / beat) * 2)
        elseif tm then
          io.set_to(tm, math.max(0, value - tp.e8 * beat / 2))
        end
      elseif tm and tm.unit == "pct" and tm.v then
        io.set_to(tm, math.max(0, math.min(100, value / math.max(1, mdl.period) * 100)))
      else
        DL.set_time(set_of(R, pre), value, ctx, io)
      end
    elseif what == "v" then
      local m = R[pre .. "Level"]
      if not m then return end
      local v = math.max(0, value)
      if m.unit == "pct" and m.v then io.set_to(m, math.min(150, v * 100))
      elseif m.unit == "db" and m.v then io.set_to(m, v <= 0.001 and -90 or 20 * math.log(v, 10))
      else v = math.min(1, v); io.set_norm(m, rev[pre .. "Level"] and (1 - v) or v) end
    end
  end
end

-- The way to REAPER for one plugin: switch settings (kept per plugin and
-- control, up to 48 of them), set by norm, set to a value in its unit.
local pos_cache = {}
function DL.io(track, addr, guid, set_norm)
  return {
    positions = function(m)
      if not m then return nil end
      local k = (guid or "") .. ":" .. m.p
      local c = pos_cache[k]
      -- none (yet): asked again now and then (a plugin read by moving it
      -- isn't read while the transport plays)
      if c == nil or (c == false and reaper.time_precise and (reaper.time_precise() - (pos_cache[k .. "@"] or 0)) > 2) then
        c = UN.positions(UN.formatter(track, addr, m.p), 256, 48) or false
        pos_cache[k] = c
        if c == false then pos_cache[k .. "@"] = reaper.time_precise and reaper.time_precise() or 0 end
      end
      return c or nil
    end,
    set_norm = function(m, n) set_norm(track, addr, m.p, math.max(0, math.min(1, n))) end,
    set_to = function(m, v)
      local n = UN.find_norm(UN.formatter(track, addr, m.p), v)
      if n then set_norm(track, addr, m.p, n) end
    end,
  }
end
function DL.forget() pos_cache = {} end

return DL
