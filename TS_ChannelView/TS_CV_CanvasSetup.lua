-- @noindex
-- Not a package of its own: installed by TS_ChannelView.lua's @provides.
--[[
  TS_CV_CanvasSetup.lua -- setting up an EQ or Compressor layout for any
  plugin.

  EQ: up to 8 bands, each naming the plugin's controls for it (frequency,
  gain, Q, a shape switch, an On switch -- any can be left out). Its shape
  isn't chosen here: Learn measures a hidden copy of the plugin
  (TS_CV_Learn). Done is only offered once every band is learned for its
  mapping as it is; leaving before that keeps the layout, and its panel
  offers to finish it. Changing a band's mapping means learning it again.

  Compressor, Gate, Limiter: each role (a compressor's Threshold, Ratio,
  Knee, Attack, Hold, Release, Make-up, Mix; a gate's Threshold, Close or
  Hysteresis, Range, Ratio and times; a limiter's Threshold or Input,
  Ceiling and Release -- TS_CV_Mappings M.ROLES) names a control, or
  none. No learning: the canvas takes the plugin's own values. A
  "Compression" control is a threshold the other way round: tick
  Reversed. So can an attack, hold or release that doesn't read in time
  (a 1176's 1 to 7, fastest at 7).

  Every change is saved as it's made. The window is modal while it's
  open; closing it during learning cancels the learning.
--]]

local C  = require("TS_CV_Config")
local U  = require("TS_CV_Util")
local M  = require("TS_CV_Mappings")
local ME = require("TS_CV_MapEQ")
local LN = require("TS_CV_Learn")

local CS = {}
local ImGui

function CS.attach(imgui) ImGui = imgui end

local dlg = nil
local TITLE = "Set up layout###tscvcanvas"

local function names_of(track, addr)
  local out = {}
  for p = 0, (reaper.TrackFX_GetNumParams(track, addr) or 0) - 1 do
    local _, nm = reaper.TrackFX_GetParamName(track, addr, p, "")
    out[p + 1] = nm or ("Param " .. (p + 1))
  end
  return out
end

-- ---------------------------------------------------------------------
-- guesses
-- ---------------------------------------------------------------------

-- the words that suggest each role, by kind
local GATE_WORDS = {
  Threshold  = { "thresh", "open" },
  Close      = { "close" },
  Hysteresis = { "hyst" },
  Range      = { "range", "depth", "floor", "atten" },
  Ratio      = { "ratio" },
  Attack     = { "attack", "atk" },
  Hold       = { "hold" },
  Release    = { "release", "rel", "decay" },
}
local LIMIT_WORDS = {
  Threshold = { "thresh" },
  Input     = { "input", "gain", "drive", "boost" },
  Ceiling   = { "ceiling", "out ceil", "output level", "out level", "output", "out " },
  Release   = { "release", "rel" },
}
local DEESS_WORDS = {
  Frequency = { "freq", "cutoff", "centre", "center" },
  Low       = { "low freq", "lo freq", "freq low", "low cut", "lower" },
  High      = { "high freq", "hi freq", "freq high", "high cut", "upper" },
  Width     = { "width", "bandwidth", " q " },
  Threshold = { "thresh" },
  Range     = { "range", "depth", "reduction", "max" },
}
local DELAY_WORDS = {
  Time     = { "time", "delay" },
  Note     = { "note", "division", "beat", "delay sync" },
  Rhythm   = { "rhythm", "feel", "modifier" },
  Sync     = { "sync", "tempo", "snap" },
  Multiplier = { "multipl" },
  Feedback = { "feedback", "fdbk", "regen", "repeat" },
  -- the right's own: the same words, with "right" or an R in the name
  TimeR    = { "time", "delay" },
  NoteR    = { "note", "division", "beat" },
  FeedbackR = { "feedback", "fdbk", "regen", "repeat" },
  Offset   = { "offset", "skew", "spread" },
  Ratio    = { "ratio" },
  Cross    = { "cross", "x-feed", "xfeed", "x-fb" },
  Width    = { "width", "image" },
  Link     = { "link" },
  PingPong = { " ping", "_ping", "pong" },
  LowCut   = { "low cut", "lowcut", "lo cut", "hipass", "high pass", "highpass", "hpf", "hp filter" },
  HighCut  = { "high cut", "highcut", "hi cut", "lowpass", "low pass", "lpf", "lp filter" },
  Mix      = { "mix", "dry/wet", "wet" },
}
-- a delay's mode switch, by the likeliest word first (a delay's "Mode" is
-- as often its sound as its stereo)
local DELAY_MODE_WORDS = { "style", "stereo mode", "routing", "channel mode", "type", "stereo", "mode" }
local DL_SIDED = { Time = true, Note = true, Feedback = true }
local DL_RIGHT = { TimeR = true, NoteR = true, FeedbackR = true }
local function dl_right(l, nm)
  if l:find("right", 1, true) or l:match("[%s_%-%(%[%.]r[%s_%-%)%]%.:]") then return true end
  -- run together: "DelayR_Ms", "DelayRNote"
  nm = nm or ""
  return (nm:find("%lR[%u_%d]") or nm:find("%lR$")) ~= nil
end
-- a delay tap's number from a control's name: "Tap 2 Level", "T3 State",
-- "Time 4" (Echoes), "TapB"; nil for none
local function dl_tap_of(nm)
  local l = (nm or ""):lower()
  local k = l:match("tap%s*(%d+)") or l:match("^t(%d+)%f[%D]")
  if k then return tonumber(k) end
  k = l:match("^%a[%a ]-%s(%d+)$")
  if k and (l:find("time", 1, true) or l:find("pan", 1, true) or l:find("level", 1, true) or l:find("feedback", 1, true)
            or l:find("state", 1, true) or l:find("gain", 1, true)) then return tonumber(k) end
  return nil
end
CS._dl_tap_of = dl_tap_of
local DL_TAP_WORDS = {
  Time = { "time", "delay" }, Note = { "division", "note", "beat" }, Rhythm = { "rhythm", "feel" },
  Sync = { "sync", "free" }, Level = { "level", "gain", "vol" }, Pan = { "pan" },
  On = { " in", "enable", "state", " on", "active", "tap" }, PingPong = { " ping", "pong" }, Feedback = { "feedback" },
  LowCut = { "low cut", "hipass", "high pass", "hpf" }, HighCut = { "high cut", "lowpass", "low pass", "lpf" },
}
-- a delay's time isn't its sync, mode, note or any other control that
-- names the delay
local DL_NOT_TIME = { "sync", "mode", "style", "note", "type", "link", "offset", "ratio", "feedback", "mix",
                      "cross", "width", "level", "filter", "cut", "mod", "volume", "gain", "wet", "dry",
                      "spread", "spacing", "swell", "bpm", "multipl", "rhythm", "division", "snap", "pattern" }
local REVERB_WORDS = {
  Predelay = { "pre-delay", "predelay", "pre delay" },
  Decay    = { "decay", "rt60", "length", "time", "space" },
  Size     = { "size", "room" },
  Balance  = { "early late", "early / late", "early/late", "er/late", "er / late", "er late" },
  Early    = { "early", " er ", "reflect" },
  Diffusion = { "diffus", "density" },
  LowFreq  = { "crossover", "xover", "x-over", "low freq", "lo freq", "bass freq", "low xover" },
  Bass     = { "bass", "low mult", "lf mult", "low decay", "low time", "lo time", "low rt" },
  HighFreq = { "high freq", "hi freq", "hf freq", "treble freq", "damp freq", "high xover" },
  Damping  = { "damp", "hf decay", "high mult", "hf mult", "high time", "hi time", "treble", "high shelf" },
  Tone     = { "tone", "bright", "tilt", "colour", "color" },
  LowEQ    = { " low ", " low eq ", " bass eq ", " lo eq ", " low shelf " },
  HighEQ   = { " high ", " high eq ", " treble eq ", " hi eq " },
  LowCutOn = { "high pass enable", "high pass on", "hp enable", "hpf on", "low cut on", "low cut enable", "lowcut on" },
  HighCutOn = { "low pass enable", "low pass on", "lp enable", "lpf on", "high cut on", "high cut enable", "highcut on" },
  LowCut   = { "low cut", "lo cut", "lowcut", "hpf", "high pass", "highpass" },
  HighCut  = { "high cut", "hi cut", "highcut", "lpf", "low pass", "lowpass" },
  Style    = { "reverb mode", "algorithm", "algo", "style", "type", "mode", "model", "character" },
  Freeze   = { "freeze", "infinite" },
  Mix      = { "mix", "dry/wet", "wet" },
}
-- A reverb's control name with its run-together words apart ("HiCut",
-- "RTHighMultiply", "earlyLateMix": "Hi Cut", "RT High Multiply", "early
-- Late Mix"), so its words are found.
local function rv_words(nm)
  return ((nm or ""):gsub("(%l)(%u)", "%1 %2"):gsub("(%u)(%u%l)", "%1 %2"))
end
CS._rv_words = rv_words
-- A reverb's words a role must not have (beside its own): a decay rate or
-- EQ band isn't its decay, an early control that's a type, size or
-- diffusion isn't its early level, and so on
local RV_NOT = {
  Decay = { "rate", "band", " eq ", "target", "gate", "mod", "early", "pre" },
  Size = { "early", "er " },
  Early = { "diffus", "type", "size", "mod", "cross", "send", "late", "time" },
  Diffusion = { "early" },
  LowFreq = { "high", " hi " },
  Bass = { " eq ", "shelf" },
  Damping = { "freq", "xover" },
  Tone = { "mode", "tilt " },
  LowEQ = { "cut", "pass", "freq", "gain " },
  HighEQ = { "cut", "pass", "freq", "gain " },
  LowCut = { "enable", "slope", " on ", "active" },
  HighCut = { "enable", "slope", " on ", "active" },
  Style = { "filter", "finisher", "sync", "gate", "analog", "color", "colour", "er type", "early", "analyzer", "display", "speaker", "eq ", "shape", "placement" },
  Mix = { "early", " er ", "late", "lock", "tilt", "eq " },
}
local ENV_WORDS = {
  Delay        = { "delay" },
  Attack       = { "attack", "atk" },
  Hold         = { "hold" },
  Decay        = { "decay", "dec" },
  Sustain      = { "sustain", "sus" },
  Release      = { "release", "rel" },
  AttackCurve  = { "attack curve", "atk curve", "attack shape", "attack slope" },
  DecayCurve   = { "decay curve", "dec curve", "decay shape", "decay slope" },
  ReleaseCurve = { "release curve", "rel curve", "release shape", "release slope" },
}
local MOD_WORDS = {
  Rate     = { "rate", "speed", "freq" },
  Depth    = { "depth", "amount", "intensity" },
  Shape    = { "shape", "wave", "lfo type" },
  Phase    = { "phase", "stereo", "spread", "offset" },
  Delay    = { "delay", "centre", "center" },
  Feedback = { "feedback", "regen", "resonance" },
  Mix      = { "mix", "dry/wet", "wet" },
  Voices   = { "numvoices", "num voices", "voices", "voice count", "no. of voices" },
}
-- A modulation's voice: "Voice 2 Rate", "V2 Depth", or a depth per side
-- ("DEPTH L / C / R": voices 1, 2, 3); its number, and whether it's a side's
local function mod_voice_of(nm)
  local l = (nm or ""):lower()
  local k = l:match("voice%s*(%d)%f[%D]") or l:match("^v(%d)%f[%D]") or l:match("%sv(%d)%f[%D]")
  if k then k = tonumber(k); return (k >= 1 and k <= M.MOD_VOICES) and k or nil end
  if l:find("depth", 1, true) or l:find("amount", 1, true) then
    local side = l:match("%s([lcr])%s*$") or l:match("%s(left)%s*$") or l:match("%s(right)%s*$")
              or l:match("%s(centre)%s*$") or l:match("%s(center)%s*$")
    if side then return ({ l = 1, left = 1, c = 2, centre = 2, center = 2, r = 3, right = 3 })[side], true end
  end
  return nil
end
CS._mod_voice_of = mod_voice_of
local MOD_VOICE_WORDS = {
  Depth = { "depth", "amount", "intensity" }, Rate = { "rate", "speed", "freq" },
  Note = {}, Sync = { "bpm", "sync", "tempo" }, Phase = { "phase" }, Pan = { "pan" },
  On = { " on ", "enable", "active", "power", "switch" },
}
local SAT_WORDS = {
  Drive  = { "drive", "saturat", "amount", "input", "heat", "push" },
  Style  = { "style", "mode", "type", "character", "model", "flavo" },
  Tone   = { "tone", "colour", "color", "tilt", "warm", "low" },
  Tone2  = { "soft", "bright", "air", "high", "presence" },
  Output = { "output", "out gain", "trim", "level" },
  Mix    = { "mix", "dry/wet", "blend", "wet" },
}
local COMP_WORDS = {
  Threshold = { "thresh", "compression", "peak reduction", "squeeze" },
  Input     = { "input", "drive" },
  Ratio     = { "ratio" },
  Knee      = { "knee" },
  Attack    = { "attack", "atk" },
  Hold      = { "hold" },
  Release   = { "release", "rel" },
  Makeup    = { "makeup", "make up", "make-up", "gain out", "output gain" },
  Mix       = { "mix", "blend", "dry/wet", "parallel" },
}

-- A multiband's roles from its parameters' names: each name's band from a
-- digit ("Thresh 2", "Band 3 Ratio") or a word (low, low mid, mid, high
-- mid, high), its role from the compressor's words; crossovers by their
-- number, their word, or the order they come in.
local MB_WORDS = {
  Threshold = { "thresh" }, Ratio = { "ratio" }, Knee = { "knee" }, Attack = { "attack", "atk" },
  Release = { "release", "rel" }, Gain = { "gain", "makeup", "make up", "make-up", "level", "output" },
  Solo = { "solo" }, Bypass = { "bypass", "mute" },
  -- a band's own edges come from crossover-like names with a band number
  -- and "low" or "high" (guess_multi); whether it's in use, from these
  Low = {}, High = {}, Used = { "used", "state", "active", "enable" },
}
local XO_WORDS = { "cross", "xover", "x-over", "split", "freq" }
local function mb_band_of(l, nb)
  local d = l:match("%f[%d]([1-9])%f[%D]")
  if d then d = tonumber(d); return (d >= 1 and d <= nb) and d or nil end
  local function has(w) return l:find(w, 1, true) end
  if has("low mid") or has("lo mid") or has("lowmid") or has("lmf") then return math.min(2, nb) end
  if has("high mid") or has("hi mid") or has("highmid") or has("hmf") then return math.max(1, nb - 1) end
  if has("low") or has(" lo ") or has(" lf ") then return 1 end
  if has("high") or has(" hi ") or has(" hf ") then return nb end
  if has("mid") then return (nb == 3) and 2 or nil end
  return nil
end
-- how many bands the names suggest: the crossovers' count, the highest
-- band number, or the band words (2..4; 3 when nothing says)
function CS.mb_count(names)
  local xo, top, four, mid = 0, 0, false, false
  for _, nm in ipairs(names) do
    local l = " " .. (nm or ""):lower() .. " "
    local is_xo = false
    for _, w in ipairs(XO_WORDS) do if l:find(w, 1, true) then is_xo = true end end
    if is_xo then xo = xo + 1 end
    local d = tonumber(l:match("%f[%d]([1-9])%f[%D]") or "")
    if d and not is_xo then
      for _, r in ipairs(M.MB_BAND_ROLES) do
        for _, w in ipairs(MB_WORDS[r]) do if l:find(w, 1, true) then top = math.max(top, d) end end
      end
    end
    if l:find("low mid", 1, true) or l:find("lo mid", 1, true) or l:find("high mid", 1, true) then four = true end
    if l:find("mid", 1, true) then mid = true end
  end
  local nb = (top >= 2 and top) or (xo > 0 and xo + 1) or (four and 4) or (mid and 3) or 3
  return math.max(2, math.min(M.MB_MAX, nb))
end

function CS.guess_multi(names, nb)
  nb = nb or CS.mb_count(names)
  local roles, xos = {}, {}
  for p0, nm in ipairs(names) do
    local l = " " .. (nm or ""):lower() .. " "
    local p = p0 - 1
    local is_xo = false
    for _, w in ipairs(XO_WORDS) do if l:find(w, 1, true) then is_xo = true end end
    -- "Band 2 Low Crossover": a band's own edge, not a crossover between two
    local edge_k = is_xo and l:match("%f[%d]([1-9])%f[%D]") and (l:find("low", 1, true) or l:find("high", 1, true))
                   and not l:find("mid", 1, true) and mb_band_of(l, nb)
    if edge_k then
      local key = "B" .. edge_k .. (l:find("low", 1, true) and "Low" or "High")
      if not roles[key] then roles[key] = p end
    elseif is_xo then
      xos[#xos + 1] = { p = p, l = l }
    else
      local k = mb_band_of(l, nb)
      local done = false
      for _, r in ipairs(M.MB_BAND_ROLES) do
        if not done then
          for _, w in ipairs(MB_WORDS[r]) do
            if l:find(w, 1, true) and not (r == "Release" and l:match("auto")) then
              if k then
                local key = "B" .. k .. r
                -- "used" itself beats "state" / "enable" for whether it's in use
                if not roles[key] or (r == "Used" and l:find("used", 1, true)) then roles[key] = p end
              elseif r == "Gain" and not roles.Output and (l:find("output", 1, true) or l:find("master", 1, true)) then
                roles.Output = p
              end
              done = true
              break
            end
          end
        end
      end
      if not done and not k and not roles.Mix and (l:find("mix", 1, true) or l:find("dry/wet", 1, true) or l:find(" wet ", 1, true)) then
        roles.Mix = p
      end
    end
  end
  -- the crossovers: numbered, worded, or in the order they come
  local used, n = {}, 0
  for _, x in ipairs(xos) do
    local d = tonumber(x.l:match("%f[%d]([1-9])%f[%D]") or "")
    local k
    if d and d <= nb - 1 then k = d
    elseif x.l:find("low", 1, true) and not x.l:find("mid", 1, true) then k = 1
    elseif x.l:find("high", 1, true) and not x.l:find("mid", 1, true) then k = nb - 1 end
    if k and not used[k] then used[k] = x.p; x.done = true end
  end
  for _, x in ipairs(xos) do
    if not x.done then
      repeat n = n + 1 until not used[n] or n > nb - 1
      if n <= nb - 1 then used[n] = x.p end
    end
  end
  -- bands with their own edges have no crossovers between them
  local own = false
  for k = 1, nb do if roles["B" .. k .. "Low"] or roles["B" .. k .. "High"] then own = true end end
  if not own then
    for k = 1, nb - 1 do if used[k] then roles["Crossover" .. k] = used[k] end end
  end
  return { kind = "multi", nb = nb, roles = roles, rev = {} }
end

-- A first go at a canvas from the parameters' names.
function CS.guess(names, kind, nb)
  nb = nb or false   -- a multiband's band count; worked out when not given
  if kind == "multi" then return CS.guess_multi(names, nb) end
  if kind == "eq" then
    local bands = ME.guess(names)
    local all_on
    for p0, nm in ipairs(names) do
      local l = (nm or ""):lower()
      if l:match("eq in") or l:match("eq on") or l:match("^eq bypass") then all_on = p0 - 1 break end
    end
    return { kind = "eq", bands = bands, all_on = all_on }
  end
  if kind == "reverb" then
    local n2 = {}
    for i, nm in ipairs(names) do n2[i] = rv_words(nm) end
    names = n2
  end
  local WORDS = ({ comp = COMP_WORDS, gate = GATE_WORDS, limit = LIMIT_WORDS, deess = DEESS_WORDS,
                   delay = DELAY_WORDS, reverb = REVERB_WORDS, env = ENV_WORDS, mod = MOD_WORDS,
                   sat = SAT_WORDS })[kind] or COMP_WORDS
  local roles, rev = {}, {}
  for _, r in ipairs(M.ROLES[kind] or M.COMP_ROLES) do
    for p0, nm in ipairs(names) do
      local l = " " .. (nm or ""):lower() .. " "
      local taken = false
      for _, v in pairs(roles) do if v == p0 - 1 then taken = true end end
      if not taken and not roles[r] then
        for _, w in ipairs(WORDS[r] or {}) do
          if l:find(w, 1, true) and not (r == "Release" and l:match("auto"))
             and not (r == "Input" and roles.Threshold)
             and not (r == "Hysteresis" and roles.Close)
             and not (kind == "limit" and r == "Input" and l:find("out", 1, true))
             -- a de-esser's "Low Freq" is an edge, not its frequency
             and not (kind == "deess" and r == "Frequency" and (l:find("low", 1, true) or l:find("high", 1, true)
                      or l:find(" lo ", 1, true) or l:find(" hi ", 1, true)))
             -- a reverb's "Low Time" or "High Time" is a band's, not its decay
             and not (kind == "reverb" and r == "Decay" and (l:find("low", 1, true) or l:find("high", 1, true)
                      or l:find(" lo ", 1, true) or l:find(" hi ", 1, true) or l:find("pre", 1, true)
                      or l:find("bass", 1, true)))
             and not (kind == "reverb" and (function()
                      for _, x in ipairs(RV_NOT[r] or {}) do if l:find(x, 1, true) then return true end end
                      return false end)())
             -- a delay's right-hand control isn't the left's (or both's),
             -- and its right-hand roles want a right-hand control
             and not (kind == "delay" and DL_SIDED[r] and dl_right(l, nm))
             and not (kind == "delay" and DL_RIGHT[r] and not dl_right(l, nm))
             and not (kind == "delay" and dl_tap_of(nm))
             -- "Global Delay Sync" (Echoes) is a note list; "Delay Sync" its switch
             and not (kind == "delay" and r == "Note" and w == "delay sync" and not l:find("%a%s+delay sync"))
             and not (kind == "delay" and r == "Multiplier" and (l:find(" in ", 1, true) or l:find(" on ", 1, true)))
             and not (kind == "delay" and r == "Ratio" and l:find("saturat", 1, true))
             and not (kind == "delay" and r == "Note" and l:find("snap", 1, true))
             and not (kind == "delay" and r == "Feedback" and l:find("swell", 1, true))
             and not (kind == "delay" and (r == "Time" or r == "TimeR") and (function()
                      for _, x in ipairs(DL_NOT_TIME) do if l:find(x, 1, true) then return true end end
                      return false end)())
             -- a modulation's voice's controls are the voice's; "Stereo"
             -- on its own is a mono / stereo switch, not a phase; a rate's
             -- sync is a note value or a switch
             and not (kind == "mod" and mod_voice_of(nm))
             and not (kind == "mod" and r == "Phase" and l == " stereo ")
             and not (kind == "mod" and r == "Rate" and (l:find("sync", 1, true) or l:find("env", 1, true)))
             -- an envelope's "Attack Curve" is a curve, not its attack
             and not (kind == "env" and not r:find("Curve") and (l:find("curve", 1, true) or l:find("shape", 1, true)
                      or l:find("slope", 1, true))) then
            roles[r] = p0 - 1
            if r == "Threshold" and (l:match("compression") or l:match("peak reduction") or l:match("squeeze")) then
              rev[r] = true
            end
            break
          end
        end
      end
    end
  end
  local nt
  if kind == "delay" and not roles.Mode then
    for _, w in ipairs(DELAY_MODE_WORDS) do
      for p0, nm in ipairs(names) do
        local l = " " .. (nm or ""):lower() .. " "
        local taken = false
        for _, v in pairs(roles) do if v == p0 - 1 then taken = true end end
        if not taken and not roles.Mode and l:find(w, 1, true) and not dl_tap_of(nm) then roles.Mode = p0 - 1 end
      end
    end
  end
  if kind == "delay" then
    -- its taps: each control with a tap's number, by the tap's role words
    local top = 0
    local used = {}
    for _, v in pairs(roles) do used[v] = true end
    for _, r in ipairs(M.DL_TAP_ROLES) do
      for p0, nm in ipairs(names) do
        local k = dl_tap_of(nm)
        if k and k <= M.DL_TAPS and not used[p0 - 1] and not roles["T" .. k .. r] then
          local l = " " .. (nm or ""):lower() .. " "
          -- a tap's "Ping Pong Pan" is neither its ping-pong nor its pan
          local skip = l:find("ping", 1, true) and l:find("pan", 1, true)
          -- "Tap A" on its own is the tap's switch
          local bare = not l:find("%a%a%a+%s*%d*%s*%a%a%a") and l:find("tap", 1, true)
          for _, w in ipairs(DL_TAP_WORDS[r]) do
            if not skip and (l:find(w, 1, true) or (r == "On" and bare)) and not (r == "Time" and (l:find("division", 1, true)
               or l:find("sync", 1, true))) and not (r == "On" and (l:find("ping", 1, true) or l:find("pan", 1, true)
               or l:find("level", 1, true) or l:find("time", 1, true) or l:find("division", 1, true) or l:find("sync", 1, true)
               or l:find("rhythm", 1, true) or l:find("feedback", 1, true))) then
              roles["T" .. k .. r] = p0 - 1
              used[p0 - 1] = true
              if r == "Time" or r == "Note" or r == "Level" or r == "On" then top = math.max(top, k) end
              break
            end
          end
        end
      end
    end
    if top >= 2 then nt = top end
  end
  if kind == "mod" then
    -- its voices: each control with a voice's number, by the voice's words
    local used = {}
    for _, v in pairs(roles) do used[v] = true end
    for p0, nm in ipairs(names) do
      local k, side = mod_voice_of(nm)
      if k and not used[p0 - 1] then
        local l = " " .. (nm or ""):lower() .. " "
        local r
        if side then r = "Depth"
        elseif l:find("sync", 1, true) and (l:find("rate", 1, true) or l:find("div", 1, true) or l:find("note", 1, true))
           and not l:find("bpm", 1, true) then r = "Note"
        else
          for _, rr in ipairs(M.MOD_VOICE_ROLES) do
            for _, w in ipairs(MOD_VOICE_WORDS[rr]) do
              if not r and l:find(w, 1, true) and not (rr == "Rate" and l:find("sync", 1, true)) then r = rr end
            end
          end
          -- "Voice 2" on its own is the voice's switch
          if not r and not l:find("%a%a%a+%s*%d%s*%a%a") then r = "On" end
        end
        if r and not roles["V" .. k .. r] then roles["V" .. k .. r] = p0 - 1; used[p0 - 1] = true end
      end
    end
  end
  return { kind = M.ROLES[kind] and kind or "comp", roles = roles, rev = rev, nt = nt }
end

-- what each kind of canvas is, for the menu that makes one
CS.TIPS = {
  eq = "This plugin on an EQ canvas: name its bands' controls, then\n" ..
       "ChannelView learns each band's shape.",
  comp = "This plugin on a compressor canvas: name its threshold, ratio,\nattack and so on.",
  gate = "A gate or expander: threshold, close or hysteresis, range,\nratio and times.",
  limit = "A limiter: threshold (or input gain), ceiling and release.",
  deess = "A de-esser: its band over the spectrum, and the track's waveform\n" ..
          "with what it's reducing lit up. Threshold and range.",
  delay = "A delay: its echoes on a timeline, left above and right below.\n" ..
          "Time (or a note value), feedback, mix; the right's own time,\n" ..
          "offset or ratio, cross-feedback, width, ping-pong.",
  reverb = "A reverb: the sound's energy over time. Pre-delay, decay, size,\n" ..
           "early reflections, damping and bass.",
  env = "An instrument's envelope: attack, hold, decay, sustain, release\nand their curves.",
  mod = "A chorus, flanger, phaser or tremolo: the LFO as it moves.\nRate, depth, shape, phase.",
  sat = "A saturator: its curve and harmonics (learned on a hidden copy),\n" ..
        "the music riding the curve, and how hard it's driven.",
}

-- ---------------------------------------------------------------------
-- opening
-- ---------------------------------------------------------------------

function CS.open(track, fx, key)
  local layout = M.get(key)
  -- ReaDelay's or ReaVerbate's own canvas, before it's saved
  if not layout and require("TS_CV_ReaFX").kind(key) then
    layout = M.copy(M.get_or_default(key, track, fx.addr, fx.guid))
    M.set(key, layout)
    layout = require("TS_CV_ReaFX").ensure(track, fx.addr, fx.guid, key, M.get(key))
  end
  if not (layout and layout.canvas) then return end
  if dlg and dlg.job then LN.cancel(dlg.job) end
  dlg = { track = track, fx = fx, addr = fx.addr, guid = fx.guid, key = key,
          names = names_of(track, fx.addr), filter = "", open = true }
end

function CS.is_open() return dlg ~= nil end

local function save()
  local l = M.get(dlg.key)
  if l then
    -- a control the canvas now takes leaves the side columns
    M.drop_placed(l)
    M.set(dlg.key, l); M.save()
  end
end

-- the plugin instance may have moved in the chain since it was opened
local function addr_now()
  if not reaper.ValidatePtr2(0, dlg.track, "MediaTrack*") then return nil end
  local n = reaper.TrackFX_GetCount(dlg.track)
  if dlg.addr and dlg.addr < n and reaper.TrackFX_GetFXGUID(dlg.track, dlg.addr) == dlg.guid then
    return dlg.addr
  end
  local T = require("TS_CV_FXTree")
  for _, f in ipairs(T.collect(dlg.track)) do
    if f.guid == dlg.guid then dlg.addr = f.addr return f.addr end
  end
  return nil
end

-- a parameter picker: a combo with a filter at its top
local function picker(ctx, id, cur, width, allow_none)
  local nm = cur and ((cur + 1) .. ": " .. (dlg.names[cur + 1] or "?")) or "\u{2014}"
  ImGui.SetNextItemWidth(ctx, width)
  local changed, out = false, cur
  if ImGui.BeginCombo(ctx, "##" .. id, nm) then
    if ImGui.IsWindowAppearing(ctx) then dlg.filter = ""; ImGui.SetKeyboardFocusHere(ctx) end
    ImGui.SetNextItemWidth(ctx, 220)
    local _, f = ImGui.InputTextWithHint(ctx, "##flt" .. id, "filter\u{2026}", dlg.filter)
    dlg.filter = f
    if allow_none ~= false and ImGui.Selectable(ctx, "\u{2014} (none)##none" .. id, cur == nil) then
      changed, out = true, nil
    end
    local fl = f:lower()
    for p0, name in ipairs(dlg.names) do
      if fl == "" or name:lower():find(fl, 1, true) then
        if ImGui.Selectable(ctx, ("%d: %s##%s%d"):format(p0, name, id, p0), cur == p0 - 1) then
          changed, out = true, p0 - 1
        end
      end
    end
    ImGui.EndCombo(ctx)
  end
  return changed, out
end

-- ---------------------------------------------------------------------
-- the EQ page
-- ---------------------------------------------------------------------

local FIELDS = { { "freq", "Freq" }, { "gain", "Gain" }, { "q", "Q" }, { "shape", "Shape switch" }, { "on", "On" },
                 { "slope", "Slope" } }

local function learned_text(b)
  if not (b.freq or b.gain) then return "needs a frequency or gain", C.COL.warn end
  if not M.band_learned(b) then
    return b.learn and "mapping changed: learn again" or "not learned", C.COL.warn
  end
  local L = ME.decode(b.learn)
  if not L then return "not learned", C.COL.warn end
  local e = L.shapes[1]
  if not e then for _, v in pairs(L.shapes) do e = v break end end
  local t = ME.TYPES[e.type] or e.type
  if e.order and (e.type == "hp" or e.type == "lp") then
    t = t .. ((e.order >= ME.BRICK) and " brickwall" or (" %d dB/oct"):format(e.order * 6))
  end
  local n = 0
  for _ in pairs(L.shapes) do n = n + 1 end
  if n > 1 then t = t .. (" (+%d more shapes)"):format(n - 1) end
  if L.D then t = t .. " \u{00B7} its own values"
  elseif e.Q and #e.Q > 1 then
    t = t .. (" \u{00B7} Q %.1f\u{2192}%.1f"):format(e.Q[1][2], e.Q[#e.Q][2])
  elseif e.Q and e.Q[1] then t = t .. (" \u{00B7} Q %.2f"):format(e.Q[1][2]) end
  return t, C.COL.accent
end

-- a band's dynamics (a dynamic EQ): role_rows over the band's Dyn fields
local role_rows   -- below
local DYN_BASE = { thr = "Threshold", range = "Range", ratio = "Ratio", atk = "Attack", rel = "Release", on = "On" }
local function dyn_rows(ctx, b, k)
  local d = b.dyn or { rev = {} }
  d.rev = d.rev or {}
  local proxy = { kind = "dyneq", roles = d, rev = d.rev }
  local changed = role_rows(ctx, proxy, "dyn" .. k, M.DYN_FIELDS,
    function(r) return M.DYN_NAMES[r] end, function(r) return DYN_BASE[r] end)
  if changed then
    local any = false
    for _, f in ipairs(M.DYN_FIELDS) do if d[f] then any = true end end
    b.dyn = any and d or nil
  end
  return changed
end

local function eq_page(ctx, layout, cv, busy)
  local EQP = require("TS_CV_EQPanel")
  local changed = false
  ImGui.BeginDisabled(ctx, busy)
  local flags = ImGui.TableFlags_RowBg | ImGui.TableFlags_BordersInnerH
  if ImGui.BeginTable(ctx, "##mpbands", 9, flags) then
    ImGui.TableSetupColumn(ctx, "Band", ImGui.TableColumnFlags_WidthFixed, 110)
    for _, f in ipairs(FIELDS) do ImGui.TableSetupColumn(ctx, f[2], ImGui.TableColumnFlags_WidthFixed, 120) end
    ImGui.TableSetupColumn(ctx, "Learned", ImGui.TableColumnFlags_WidthFixed, 230)
    ImGui.TableSetupColumn(ctx, "", ImGui.TableColumnFlags_WidthFixed, 22)
    ImGui.TableHeadersRow(ctx)
    local remove
    for k, b in ipairs(cv.bands) do
      ImGui.TableNextRow(ctx)
      ImGui.TableNextColumn(ctx)
      local col = EQP.util.band_colour(k)
      local x, y = ImGui.GetCursorScreenPos(ctx)
      local dl = ImGui.GetWindowDrawList(ctx)
      ImGui.DrawList_AddRectFilled(dl, x, y + 5, x + 9, y + 14, col, 2.0)
      ImGui.SetCursorScreenPos(ctx, x + 14, y)
      ImGui.SetNextItemWidth(ctx, 92)
      local ch, nm = ImGui.InputText(ctx, "##bn" .. k, b.name or "")
      if ch then b.name = nm; changed = true end
      for _, f in ipairs(FIELDS) do
        ImGui.TableNextColumn(ctx)
        local c2, v = picker(ctx, "b" .. k .. f[1], b[f[1]], 116)
        if c2 then b[f[1]] = v; changed = true end
      end
      ImGui.TableNextColumn(ctx)
      local t, tc = learned_text(b)
      ImGui.TextColored(ctx, tc, t)
      ImGui.TableNextColumn(ctx)
      if ImGui.SmallButton(ctx, "\u{00D7}##rm" .. k) then remove = k end
      if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "Remove this band") end
    end
    ImGui.EndTable(ctx)
    if remove then table.remove(cv.bands, remove); changed = true end
  end
  if #cv.bands < M.MAX_BANDS then
    if ImGui.Button(ctx, "+ Band") then
      cv.bands[#cv.bands + 1] = { name = "Band " .. (#cv.bands + 1) }
      changed = true
    end
    ImGui.SameLine(ctx)
  end
  if ImGui.Button(ctx, "Guess from names") then
    local g = CS.guess(dlg.names, "eq")
    if #g.bands > 0 then
      cv.bands = g.bands
      cv.all_on = cv.all_on or g.all_on
      changed = true
    end
  end
  if ImGui.IsItemHovered(ctx) then
    ImGui.SetTooltip(ctx, "Fill the bands from the plugin's parameter names.\nReplaces the bands above.")
  end
  ImGui.SameLine(ctx)
  ImGui.Text(ctx, "  All bands On:")
  ImGui.SameLine(ctx)
  local ca, va = picker(ctx, "allon", cv.all_on, 160)
  if ca then cv.all_on = va; changed = true end
  if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "The whole EQ's In / On switch, if it has one") end

  -- a dynamic EQ: each band's dynamics, a tab a band
  ImGui.Spacing(ctx)
  local any_dyn = false
  for _, b in ipairs(cv.bands) do if b.dyn then any_dyn = true end end
  if dlg.show_dyn == nil then dlg.show_dyn = any_dyn end
  local cd, vd = ImGui.Checkbox(ctx, "Dynamics (a dynamic EQ)", dlg.show_dyn)
  if cd then dlg.show_dyn = vd end
  if ImGui.IsItemHovered(ctx) then
    ImGui.SetTooltip(ctx, "Each band's threshold, range, ratio, attack, release and switch.\n" ..
      "A band with a threshold or range is dynamic.")
  end
  if dlg.show_dyn and #cv.bands > 0 then
    dlg.dyn_tab = math.min(dlg.dyn_tab or 1, #cv.bands)
    for k, b in ipairs(cv.bands) do
      if k > 1 then ImGui.SameLine(ctx) end
      local on = dlg.dyn_tab == k
      if on then ImGui.PushStyleColor(ctx, ImGui.Col_Button, EQP.util.band_colour(k)) end
      local nm = (b.name and b.name ~= "") and b.name or ("Band " .. k)
      if ImGui.Button(ctx, nm .. (M.band_dynamic(b) and " \u{25C6}" or "") .. "##dt" .. k) then dlg.dyn_tab = k end
      if on then ImGui.PopStyleColor(ctx) end
    end
    if dyn_rows(ctx, cv.bands[dlg.dyn_tab], dlg.dyn_tab) then changed = true end
  end
  ImGui.EndDisabled(ctx)
  return changed
end

-- ---------------------------------------------------------------------
-- the compressor page
-- ---------------------------------------------------------------------

local ROLE_NAMES = { Makeup = "Make-up", PingPong = "Ping-pong", Predelay = "Pre-delay",
                     TimeR = "Time R", NoteR = "Note R", FeedbackR = "Feedback R", Mode = "Stereo mode",
                     Rhythm = "Rhythm (dotted, triplet)",
                     LowFreq = "Low freq", HighFreq = "High freq", LowCut = "Low cut", HighCut = "High cut",
                     AttackCurve = "Attack curve", DecayCurve = "Decay curve", ReleaseCurve = "Release curve",
                     Tone2 = "Tone 2", Balance = "Early / late", LowEQ = "Low shelf", HighEQ = "High shelf",
                     LowCutOn = "Low cut on", HighCutOn = "High cut on" }
-- the kinds whose every role can run the other way (TS_CV_RolePanel), but
-- their switches
local REV_ALL = { deess = true, delay = true, reverb = true, env = true, mod = true, dyneq = true, sat = true }
local NO_REV = { Sync = true, PingPong = true, Shape = true, Note = true, On = true, NoteR = true, Link = true, Mode = true,
                 Rhythm = true, Multiplier = true, Pan = true, LowCutOn = true, HighCutOn = true, Style = true,
                 Freeze = true }
-- the roles that can run the other way, and what that means for each
local REV_TIPS = {
  Threshold = "More of it is a lower threshold\n" ..
              "(a \"Compression\" or \"Peak reduction\" control).",
  Attack = "Turning it up makes the attack faster (1176-style).\n" ..
           "Only matters when it doesn't read in ms.",
  Hold = "Turning it up makes the hold shorter.\nOnly matters when it doesn't read in ms.",
  Release = "Turning it up makes the release faster (1176-style).\n" ..
            "Only matters when it doesn't read in ms or s.",
}

-- what a role means, where its name doesn't say, by kind
local ROLE_TIPS = {
  comp = {
    Input = "No threshold (1176-style): drives into a fixed threshold.\n" ..
            "Ignored when Threshold is mapped. Map its Output as Make-up.",
  },
  gate = {
    Threshold  = "Where the gate opens.",
    Close      = "Its own closing threshold, below the opening one.\nOr map Hysteresis instead.",
    Hysteresis = "How far under the threshold it closes again.\nIgnored when Close is mapped.",
    Range      = "How far down it turns the signal when shut.",
    Ratio      = "An expander's ratio. Leave out for a gate.",
  },
  multi = {
    Crossover = "Where one band hands over to the next.",
    Gain      = "The band's own output gain, or make-up.",
    Knee      = "The band's knee (on the band's own view).",
    Solo      = "The band's solo switch.",
    Bypass    = "The band's bypass (or mute) switch.",
    Output    = "The plugin's output level.",
    Low       = "The band's own lower edge (FabFilter Pro-MB style).\n" ..
                "Leave the crossovers empty then.",
    High      = "The band's own upper edge (see Low edge).",
    Used      = "Whether the band is in use.\n" ..
                "Unused bands aren't drawn or measured.",
  },
  deess = {
    Frequency = "Its frequency: the band's centre, or where it starts.",
    Low       = "Its band's lower edge, when it has a control for each.",
    High      = "Its band's upper edge, when it has a control for each.",
    Width     = "Its band's width, if it has one (octaves or Hz).",
    Range     = "How far down it turns the esses.",
  },
  delay = {
    Note     = "Note value, used while Sync is on (or with no Time).",
    Sync     = "Its tempo sync switch: while on, Note is the time.",
    PingPong = "Its ping-pong switch: echoes alternate left and right.",
    TimeR    = "The right's own time (Time is the left's or both).",
    NoteR    = "The right's own note value, used while Sync is on.",
    Offset   = "The right's offset from the left:\nms, a note value or a % of the left's time.",
    Ratio    = "The right's time against the left's (0.75, 3:4, 75 %).",
    FeedbackR = "The right's own feedback (Feedback is the left's or both).",
    Cross    = "Cross-feedback: how much of each side's echo feeds the other.",
    Width    = "How wide the echoes are: at 0 both sides are the same.",
    Link     = "Its link switch: while on, the right follows the left.",
    Mode     = "Its stereo mode switch (mono, dual/stereo, ping-pong),\n" ..
               "not a sound mode (tape, digital). Settings: below.",
    Rhythm   = "Straight / dotted / triplet, combined with the note value.",
    Multiplier = "A multiplier on its times (x0.5 .. x2).",
    Time     = "Its time (ms or a note value).\nMulti-tap: the repeat period (else the longest tap).",
    Level    = "The tap's level.",
    Pan      = "The tap's pan: where it comes out, left to right.",
    On       = "The tap's switch (on, enabled, in).",
  },
  reverb = {
    Early     = "The early reflections' level.",
    Diffusion = "How dense the reflections are (low: echoes, high: a wash).",
    LowFreq   = "The lows' crossover: below it, Bass sets how long they last.",
    Bass      = "How much longer the lows last (x1.2, a time, or %).",
    HighFreq  = "The highs' crossover: above it, Damping sets how much sooner they die.",
    Damping   = "How much sooner the highs die (dB, %, a multiplier or a time).\n" ..
                "One in Hz is taken as the highs' frequency.",
    LowCut    = "A low cut on the reverb's sound (its tone, not its decay).",
    HighCut   = "A high cut on the reverb's sound (its tone, not its decay).",
    Balance   = "Early against late, as one control (a crossfade, or % late).\n" ..
                "Use instead of Early.",
    Tone      = "A tone or brightness tilt (-100..+100 %),\n" ..
                "drawn as a tilt on the decay.",
    LowEQ     = "A low shelf on the reverb's sound, in dB.",
    HighEQ    = "A high shelf on the reverb's sound, in dB.",
    LowCutOn  = "The low cut's own on/off switch.",
    HighCutOn = "The high cut's own on/off switch.",
    Style     = "Its character switch (room, hall, plate...): chips on the canvas.",
    Freeze    = "Its freeze (infinite hold) switch: the tail is drawn held.",
  },
  env = {
    Sustain      = "The level it holds while the note is held (dB or %).",
    AttackCurve  = "The attack's curve or shape control.",
    DecayCurve   = "The decay's curve or shape control.",
    ReleaseCurve = "The release's curve or shape control.",
  },
  sat = {
    Drive  = "How hard it's driven: the curve's shape follows it.",
    Style  = "Its character switch (tape, tube...): each setting is learned.",
    Tone   = "A tone or colour control (warmth, say).\n" ..
             "Learning leaves it where it is.",
    Tone2  = "A second one (softness, say): the same.",
    Output = "Its output level.",
  },
  mod = {
    Phase = "The right's phase against the left (stereo spread).\nA voice's: its LFO's start against the others'.",
    Delay = "Its delay or centre time (a chorus's or flanger's).",
    Voices = "How many voices it has (a switch: 2, 3, 4...).",
    Note = "Note value, used while the voice's Sync is on.",
    Sync = "The voice's tempo sync switch: while on, its Note is its rate.",
    Pan = "Where the voice sits, left to right.",
    On = "The voice's switch.",
  },
  dyneq = {
    Threshold = "Where the band starts to move.",
    Range     = "How far the band can move from its gain (cut or boost).\n" ..
                "Drawn as the band's tail.",
    Ratio     = "How hard it moves past the threshold.\n" ..
                "With no Range, the tail shows its recent depth.",
    On        = "The band's dynamics switch (apart from the band's own On).",
  },
  limit = {
    Threshold = "Where it starts limiting (gain: the gap to the ceiling).",
    Input     = "Gain instead of a threshold: drives into the ceiling.\nIgnored when Threshold is mapped.",
    Ceiling   = "The most it lets out. Left out: 0 dB.",
  },
}
local WANT = { Threshold = "db", Input = "db", Knee = "db", Makeup = "db", Attack = "ms", Hold = "ms",
               Release = "ms", Ratio = "ratio", Mix = "pct", Close = "db", Hysteresis = "db",
               Range = "db", Ceiling = "db", Frequency = "hz", Low = "hz", High = "hz", Time = "ms",
               Feedback = "pct", Predelay = "ms", Decay = "ms", Early = "db", Delay = "ms", Diffusion = "pct", LowFreq = "hz", HighFreq = "hz", LowCut = "hz", HighCut = "hz",
               Rate = "hz", Depth = "pct", Crossover = "hz", Gain = "db", Output = "db",
               TimeR = "ms", FeedbackR = "pct", Cross = "pct", LowEQ = "db", HighEQ = "db" }

-- One row per role: its name (and Reversed where it applies), the
-- plugin's control, and what that control reads as. `list` the roles,
-- `label(r)` a role's name, `base(r)` the role it acts as (a multiband
-- band's "B2Ratio" is a Ratio). Returns whether anything changed.
function role_rows(ctx, cv, id, list, label, base)
  local changed = false
  label = label or function(r) return ROLE_NAMES[r] or r end
  base = base or function(r) return r end
  local flags = ImGui.TableFlags_RowBg | ImGui.TableFlags_BordersInnerH
  if ImGui.BeginTable(ctx, "##mproles" .. id, 3, flags) then
    ImGui.TableSetupColumn(ctx, "Role", ImGui.TableColumnFlags_WidthFixed, 150)
    ImGui.TableSetupColumn(ctx, "Parameter", ImGui.TableColumnFlags_WidthFixed, 230)
    ImGui.TableSetupColumn(ctx, "Reads as", ImGui.TableColumnFlags_WidthFixed, 230)
    ImGui.TableHeadersRow(ctx)
    local addr = addr_now()
    local tips = ROLE_TIPS[cv.kind] or {}
    for _, r in ipairs(list) do
      local br = base(r)
      ImGui.TableNextRow(ctx)
      ImGui.TableNextColumn(ctx)
      ImGui.Text(ctx, label(r))
      if (tips[r] or tips[br]) and ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, tips[r] or tips[br]) end
      local rev_tip = REV_TIPS[br]
      if REV_ALL[cv.kind] then
        rev_tip = (not NO_REV[br]) and "Turning it up goes the other way.\nOnly matters when it doesn't read in its unit." or nil
      end
      if rev_tip and not (cv.kind == "gate" and br == "Threshold") then
        ImGui.SameLine(ctx)
        local ch, v = ImGui.Checkbox(ctx, "Reversed##rev" .. r, cv.rev[r] == true)
        if ch then cv.rev[r] = v or nil; changed = true end
        if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, rev_tip) end
      end
      ImGui.TableNextColumn(ctx)
      local ch, v = picker(ctx, "r" .. id .. r, cv.roles[r], 224)
      if ch then cv.roles[r] = v; changed = true end
      ImGui.TableNextColumn(ctx)
      if cv.roles[r] and addr then
        local _, t = reaper.TrackFX_GetFormattedParamValue(dlg.track, addr, cv.roles[r], "")
        -- your own range for it (Range<p>) reads as that
        local rg = M.get_range(dlg.key, cv.roles[r])
        if rg then t = U.range_text(rg, reaper.TrackFX_GetParamNormalized(dlg.track, addr, cv.roles[r]) or 0) end
        local UN = require("TS_CV_Units")
        local _, unit = UN.parse(t)
        local want = WANT[br]
        local note = (t or "")
        local noted = (br == "Time" or br == "TimeR" or br == "Rate" or br == "Note") and UN.note_beats(t or "")
        if want == "ms" and unit == "" and (br == "Delay" or br == "Time" or br == "TimeR") and noted then want = nil end
        if cv.kind == "delay" and br == "Ratio" and M.dl_ratio_of(t) then want = nil end
        if cv.kind == "delay" and br == "Time" and unit == "pct" and M.dl_tap_split(r) then want = nil end
        if br == "Rate" and (noted or unit == "ms") then want = nil end
        if want and unit ~= want and not (br == "Threshold" and cv.rev[r]) then
          note = note .. "   (not " .. want .. ": along its range)"
        end
        ImGui.TextDisabled(ctx, note)
      end
    end
    ImGui.EndTable(ctx)
  end
  return changed
end

local function comp_page(ctx, cv)
  cv.roles = cv.roles or {}
  cv.rev = cv.rev or {}
  local changed = role_rows(ctx, cv, "", M.ROLES[cv.kind] or M.COMP_ROLES)
  if ImGui.Button(ctx, "Guess from names") then
    local g = CS.guess(dlg.names, cv.kind)
    cv.roles, cv.rev = g.roles, g.rev
    changed = true
  end
  return changed
end

-- A compressor's threshold, where it really is: measured on a hidden copy
-- (TS_CV_Learn LN.start_thr), since its own dB often isn't dBFS.
local function thr_section(ctx, layout, cv, job, busy)
  local p, via_in = M.thr_param(cv)
  local addr = addr_now()
  ImGui.Spacing(ctx)
  ImGui.Text(ctx, "Its threshold in dBFS:")
  ImGui.SameLine(ctx)
  if busy and job and job.mode == "thr" then
    ImGui.ProgressBar(ctx, job.progress or 0, 240, 0, ("%d%%"):format(math.floor((job.progress or 0) * 100)))
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, "Cancel##thr") then LN.cancel(job) end
    return
  end
  local tc = M.thr_cal(cv)
  if tc and via_in then
    -- an input driving it: where the threshold falls, input low to high
    local a, b = tc.pts[1], tc.pts[#tc.pts]
    ImGui.TextColored(ctx, C.COL.accent, ("measured: %.1f dBFS with the input low, %.1f dBFS with it up"):format(
      M.thr_dbfs(cv, tc.n and 0 or a[1]) or a[2], M.thr_dbfs(cv, tc.n and 1 or b[1]) or b[2]))
  elseif tc then
    if tc.n then
      ImGui.TextColored(ctx, C.COL.accent, ("measured: halfway is %.1f dBFS"):format(M.thr_dbfs(cv, 0.5) or 0))
    else
      ImGui.TextColored(ctx, C.COL.accent, ("measured: its 0 dB is %.1f dBFS"):format(M.thr_dbfs(cv, 0) or 0))
    end
  elseif p and addr and via_in then
    ImGui.TextColored(ctx, C.COL.warn, "not measured: no threshold, so the input's fixed one is guessed")
  elseif p and addr then
    local UN_ = require("TS_CV_Units")
    local fmt = UN_.formatter(dlg.track, addr, p)
    local a, ua = UN_.at(fmt, 0)
    local b = UN_.at(fmt, 1)
    local hi = (a and b) and math.max(a, b) or nil
    if ua == "db" and hi and hi > 3 and hi < 1e9 then
      ImGui.TextColored(ctx, C.COL.warn, ("not measured: it goes up to %+.0f dB, so its dB is likely its own"):format(hi))
    elseif ua == "db" then
      ImGui.TextDisabled(ctx, "not measured: its dB is taken as dBFS")
    else
      ImGui.TextDisabled(ctx, "not measured: it doesn't read in dB, so it runs along its range")
    end
  else
    ImGui.TextDisabled(ctx, "map its threshold (or, with none, its input) first")
  end
  ImGui.SameLine(ctx)
  ImGui.BeginDisabled(ctx, busy or not (p and addr))
  if ImGui.Button(ctx, (tc and "Measure again" or "Measure threshold") .. "##thr") then
    local play = reaper.GetPlayState() & 1 == 1
    if not (play and reaper.MB("Measuring works best with the transport stopped. Measure anyway?",
        "ChannelView", 4) ~= 6) then
      dlg.job = LN.start_thr(dlg.track, addr, dlg.key, layout)
    end
  end
  ImGui.EndDisabled(ctx)
  if ImGui.IsItemHovered(ctx, ImGui.HoveredFlags_AllowWhenDisabled) then
    ImGui.SetTooltip(ctx, "Measures where it starts to compress\n" ..
      "(a test tone through a hidden copy).")
  end
  if job and job.mode == "thr" and job.msg and job.state ~= "measuring" and job.state ~= "starting" then
    ImGui.TextColored(ctx, job.state == "done" and C.COL.accent or C.COL.warn, job.msg)
  end
end

-- A compressor or limiter with no threshold, only an input gain: the
-- level its gain's 0 dB stands for (where its canvas puts the gain's bar
-- at 0 dB). Not something a measurement can find -- a gain has no level
-- of its own -- so said here; -18 dBFS (0 VU) unless changed.
local function ref_row(ctx, cv)
  local r = cv.roles or {}
  if r.Threshold or not r.Input then return false end
  ImGui.Spacing(ctx)
  ImGui.Text(ctx, "Its input's 0 dB is")
  ImGui.SameLine(ctx)
  ImGui.SetNextItemWidth(ctx, 110)
  local ch, v = ImGui.InputDouble(ctx, "dBFS##ref0", M.ref0(cv), 1, 6, "%.1f")
  if ImGui.IsItemHovered(ctx) then
    ImGui.SetTooltip(ctx, "The level the input gain's 0 dB stands for.\n" ..
      "Analogue models: usually -18 dBFS (0 VU).")
  end
  if ch and v then
    v = math.max(-60, math.min(0, v))
    cv.ref0 = (math.abs(v - M.REF0) > 1e-6) and v or nil
    return true
  end
  return false
end

-- A de-esser with only a frequency control: split-band (it turns down
-- everything above the frequency, the usual) or a band around it.
local function dshape_row(ctx, cv)
  local r = cv.roles or {}
  if not r.Frequency or r.Width or r.Low or r.High then return false end
  ImGui.Spacing(ctx)
  ImGui.Text(ctx, "Its band:")
  local changed = false
  ImGui.SameLine(ctx)
  if ImGui.RadioButton(ctx, "Above the frequency (split-band)##dsh", cv.dshape ~= "around") and cv.dshape == "around" then
    cv.dshape = nil; changed = true
  end
  ImGui.SameLine(ctx)
  if ImGui.RadioButton(ctx, "Around the frequency##dsh", cv.dshape == "around") and cv.dshape ~= "around" then
    cv.dshape = "around"; changed = true
  end
  if ImGui.IsItemHovered(ctx) then
    ImGui.SetTooltip(ctx, "For a de-esser working on an octave around its frequency.")
  end
  return changed
end

-- A saturator's curve and harmonics: learned on a hidden copy (TS_CV_Learn
-- LN.start_sat).
local function sat_section(ctx, layout, cv, job, busy)
  local p = cv.roles and cv.roles.Drive
  local addr = addr_now()
  ImGui.Spacing(ctx)
  ImGui.Text(ctx, "Its curve and harmonics:")
  ImGui.SameLine(ctx)
  if busy and job and job.mode == "sat" then
    ImGui.ProgressBar(ctx, job.progress or 0, 240, 0, ("%d%%"):format(math.floor((job.progress or 0) * 100)))
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, "Cancel##sat") then LN.cancel(job) end
    return
  end
  local c = cv.sat_cal
  if c and c.d == p then
    local n = 0
    for _ in pairs(c.e) do n = n + 1 end
    ImGui.TextColored(ctx, C.COL.accent, ("learned at %d settings"):format(n))
  elseif p then
    ImGui.TextColored(ctx, C.COL.warn, "not learned yet")
  else
    ImGui.TextDisabled(ctx, "map its drive first")
  end
  ImGui.SameLine(ctx)
  ImGui.BeginDisabled(ctx, busy or not (p and addr))
  if ImGui.Button(ctx, (c and "Learn again" or "Learn") .. "##sat") then
    local play = reaper.GetPlayState() & 1 == 1
    if not (play and reaper.MB("Learning works best with the transport stopped. Learn anyway?",
        "ChannelView", 4) ~= 6) then
      dlg.job = LN.start_sat(dlg.track, addr, dlg.key, layout)
    end
  end
  ImGui.EndDisabled(ctx)
  if ImGui.IsItemHovered(ctx, ImGui.HoveredFlags_AllowWhenDisabled) then
    ImGui.SetTooltip(ctx, "Learns its curve and harmonics\n" ..
      "(a 250 Hz sine through a hidden copy). Takes a minute.")
  end
  if job and job.mode == "sat" and job.msg and job.state ~= "measuring" and job.state ~= "starting" then
    ImGui.TextColored(ctx, job.state == "done" and C.COL.accent or C.COL.warn, job.msg)
  end
end

-- A reverb's decay in seconds, when its control reads in a scale of its
-- own: timed on a hidden copy (TS_CV_Learn LN.start_decay).
local function decay_section(ctx, layout, cv, job, busy)
  local p = cv.roles and cv.roles.Decay
  local addr = addr_now()
  ImGui.Spacing(ctx)
  ImGui.Text(ctx, "Its decay in seconds:")
  ImGui.SameLine(ctx)
  if busy and job and job.mode == "dec" then
    ImGui.ProgressBar(ctx, job.progress or 0, 240, 0, ("%d%%"):format(math.floor((job.progress or 0) * 100)))
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, "Cancel##dec") then LN.cancel(job) end
    return
  end
  local dc = M.dec_cal(cv)
  if dc and dc.builtin then
    ImGui.TextDisabled(ctx, "worked out from ReaVerbate's design (measure it to be sure): " .. LN.decay_summary(dc))
  elseif dc then
    ImGui.TextColored(ctx, C.COL.accent, "measured: " .. LN.decay_summary(dc))
  elseif p and addr then
    local _, t = reaper.TrackFX_GetFormattedParamValue(dlg.track, addr, p, "")
    local UN_ = require("TS_CV_Units")
    local _, unit = UN_.parse(t)
    if unit == "ms" then
      ImGui.TextDisabled(ctx, "it reads in time: nothing to measure")
    else
      ImGui.TextColored(ctx, C.COL.warn, "not measured: it doesn't read in seconds, so it runs along its range")
    end
  else
    ImGui.TextDisabled(ctx, "map its decay first")
  end
  ImGui.SameLine(ctx)
  ImGui.BeginDisabled(ctx, busy or not (p and addr))
  if ImGui.Button(ctx, (dc and "Measure again" or "Measure decay") .. "##dec") then
    local play = reaper.GetPlayState() & 1 == 1
    if not (play and reaper.MB("Measuring works best with the transport stopped. Measure anyway?",
        "ChannelView", 4) ~= 6) then
      dlg.job = LN.start_decay(dlg.track, addr, dlg.key, layout)
    end
  end
  ImGui.EndDisabled(ctx)
  if ImGui.IsItemHovered(ctx, ImGui.HoveredFlags_AllowWhenDisabled) then
    ImGui.SetTooltip(ctx, "Times its tail at five decay settings\n" ..
      "(noise bursts through a hidden copy). Takes a minute or two.")
  end
  if job and job.mode == "dec" and job.msg and job.state ~= "measuring" and job.state ~= "starting" then
    ImGui.TextColored(ctx, job.state == "done" and C.COL.accent or C.COL.warn, job.msg)
  end
end

-- a multiband's bands, by name
function CS.band_names(nb)
  if nb == 2 then return { "Low", "High" } end
  if nb == 3 then return { "Low", "Mid", "High" } end
  return { "Low", "Low mid", "High mid", "High" }
end

-- the multiband page: how many bands, the crossovers, each band's roles
-- (a tab each), and the output
local function multi_page(ctx, cv)
  cv.roles = cv.roles or {}
  cv.rev = cv.rev or {}
  cv.nb = cv.nb or 3
  local changed = false
  ImGui.Text(ctx, "Bands")
  for nb = 2, M.MB_MAX do
    ImGui.SameLine(ctx)
    if ImGui.RadioButton(ctx, tostring(nb) .. "##mbnb", cv.nb == nb) then cv.nb = nb; changed = true end
  end
  local names = CS.band_names(cv.nb)
  local xo = {}
  for k = 1, cv.nb - 1 do xo[#xo + 1] = "Crossover" .. k end
  local function xlabel(r)
    local k = tonumber(r:match("%d+"))
    return ("%s / %s"):format(names[k], names[k + 1])
  end
  ImGui.Spacing(ctx)
  ImGui.TextDisabled(ctx, "Crossovers")
  if role_rows(ctx, cv, "x", xo, xlabel, function() return "Crossover" end) then changed = true end
  ImGui.Spacing(ctx)
  if ImGui.BeginTabBar(ctx, "##mbbands") then
    for k = 1, cv.nb do
      if ImGui.BeginTabItem(ctx, names[k] .. "##mbt" .. k) then
        local list = {}
        for _, b in ipairs(M.MB_BAND_ROLES) do list[#list + 1] = "B" .. k .. b end
        if role_rows(ctx, cv, "b" .. k, list,
            function(r)
              local _, b = M.mb_split(r)
              return ({ Gain = "Gain (make-up)", Low = "Low edge", High = "High edge", Used = "In use" })[b] or b
            end,
            function(r) local _, b = M.mb_split(r); return b end) then
          changed = true
        end
        ImGui.EndTabItem(ctx)
      end
    end
    ImGui.EndTabBar(ctx)
  end
  ImGui.Spacing(ctx)
  if role_rows(ctx, cv, "o", { "Output", "Mix" }) then changed = true end
  if ImGui.Button(ctx, "Guess from names") then
    local g = CS.guess(dlg.names, "multi", cv.nb)
    cv.roles, cv.rev = g.roles, g.rev
    changed = true
  end
  return changed
end

-- ---------------------------------------------------------------------
-- the delay page: its time, its stereo (and what each setting of its mode
-- switch means), its taps
-- ---------------------------------------------------------------------
local DL_GROUPS = {
  { "Time", { "Time", "Note", "Rhythm", "Sync", "Multiplier", "Feedback" } },
  { "Stereo", { "Mode", "PingPong", "TimeR", "NoteR", "Offset", "Ratio", "FeedbackR", "Cross", "Width", "Link" } },
  { "Filters", { "LowCut", "HighCut" } },
  { "", { "Mix", "Dry" } },
}
local DL_MEANS = { { nil, "(by its name)" }, { "mono", "Mono" }, { "dual", "Stereo / dual" }, { "pp", "Ping-pong" },
                   { "none", "Not stereo" } }
local DL_TAP_NAMES = { Time = "Time", Note = "Note value", Rhythm = "Rhythm", Sync = "Sync (free / sync)", Level = "Level",
                       Pan = "Pan", On = "On", PingPong = "Ping-pong", Feedback = "Feedback (its own)",
                       LowCut = "Low cut", HighCut = "High cut" }

-- the controls as the canvas reads them, for the line that shows what it
-- makes of them
local function dl_readings(cv, addr)
  local UN_ = require("TS_CV_Units")
  local R = {}
  for r, p in pairs(cv.roles or {}) do
    local nv = reaper.TrackFX_GetParamNormalized(dlg.track, addr, p) or 0
    local ok, t = reaper.TrackFX_FormatParamValueNormalized(dlg.track, addr, p, nv, "")
    if not (ok and t and t ~= "") then _, t = reaper.TrackFX_GetFormattedParamValue(dlg.track, addr, p, "") end
    local v, unit = UN_.parse(t or "")
    R[r] = { p = p, n = nv, text = t or "", v = v, unit = unit }
  end
  return R
end

local function delay_page(ctx, cv)
  cv.roles = cv.roles or {}
  cv.rev = cv.rev or {}
  local changed = false
  local addr = addr_now()
  for i, g in ipairs(DL_GROUPS) do
    if g[1] ~= "" then ImGui.Spacing(ctx); ImGui.TextDisabled(ctx, g[1]) end
    if role_rows(ctx, cv, "dl" .. i, g[2]) then changed = true end
  end
  -- what each setting of its mode switch means
  if cv.roles.Mode and addr then
    local UN_ = require("TS_CV_Units")
    local pos = UN_.positions(UN_.formatter(dlg.track, addr, cv.roles.Mode), 256, 24)
    if pos and #pos >= 2 then
      ImGui.Spacing(ctx)
      ImGui.TextDisabled(ctx, "Its stereo mode's settings")
      for i, s_ in ipairs(pos) do
        local said = cv.dmodes and cv.dmodes[s_.text]
        local guess = M.dl_mode_of(s_.text)
        local cur = "(by its name" .. (guess and (": " .. ({ mono = "mono", dual = "stereo", pp = "ping-pong" })[guess]) or ": nothing") .. ")"
        for _, o in ipairs(DL_MEANS) do if o[1] and o[1] == said then cur = o[2] end end
        ImGui.Text(ctx, s_.text)
        ImGui.SameLine(ctx, 180)
        ImGui.SetNextItemWidth(ctx, 200)
        if ImGui.BeginCombo(ctx, "##dlmean" .. i, cur) then
          for _, o in ipairs(DL_MEANS) do
            if ImGui.Selectable(ctx, o[2], said == o[1]) then
              cv.dmodes = cv.dmodes or {}
              cv.dmodes[s_.text] = o[1]
              if not next(cv.dmodes) then cv.dmodes = nil end
              changed = true
            end
          end
          ImGui.EndCombo(ctx)
        end
      end
    end
  end
  -- its taps
  ImGui.Spacing(ctx)
  ImGui.TextDisabled(ctx, "Taps (a multi-tap)")
  ImGui.SameLine(ctx)
  ImGui.SetNextItemWidth(ctx, 160)
  local nt = cv.nt or 0
  local ch, v = ImGui.SliderInt(ctx, "##dlnt", nt, 0, M.DL_TAPS, nt == 0 and "none" or "%d")
  if ch then cv.nt = (v > 0) and v or nil; changed = true end
  if ImGui.IsItemHovered(ctx) then
    ImGui.SetTooltip(ctx, "Each tap's own time, level, pan and switch.\n" ..
      "A tap with no time sits at its share of the main time.")
  end
  if (cv.nt or 0) > 0 and ImGui.BeginTabBar(ctx, "##dltaps") then
    for k = 1, cv.nt do
      if ImGui.BeginTabItem(ctx, ("Tap %d##dlt%d"):format(k, k)) then
        local list = {}
        for _, r in ipairs(M.DL_TAP_ROLES) do list[#list + 1] = "T" .. k .. r end
        if role_rows(ctx, cv, "t" .. k, list,
            function(r) local _, b = M.dl_tap_split(r); return DL_TAP_NAMES[b] or b end,
            function(r) local _, b = M.dl_tap_split(r); return b end) then changed = true end
        ImGui.EndTabItem(ctx)
      end
    end
    ImGui.EndTabBar(ctx)
  end
  -- what the canvas makes of it
  if addr and (cv.roles.Time or cv.roles.Note or (cv.nt or 0) > 0) then
    local DLY = require("TS_CV_Delay")
    local R = dl_readings(cv, addr)
    local names = {}
    if cv.roles.Mode then local _, nm = reaper.TrackFX_GetParamName(dlg.track, addr, cv.roles.Mode, ""); names.Mode = nm end
    local mdl = DLY.model(R, cv, { bpm = reaper.Master_GetTempo(), names = names })
    local function t_of(ms)
      local nl = DLY.note_label(ms / mdl.beat)
      return ("%.0f ms"):format(ms) .. (nl and (" = " .. nl) or "")
    end
    local parts = {}
    if mdl.taps then
      for _, tp in ipairs(mdl.taps) do if tp.on then parts[#parts + 1] = ("%d: %s"):format(tp.k, t_of(tp.t)) end end
      parts[#parts + 1] = "repeats every " .. t_of(mdl.period)
    elseif mdl.tL then
      parts[#parts + 1] = (mdl.stereo and "L " or "") .. t_of(mdl.tL)
      if mdl.stereo and mdl.tR then parts[#parts + 1] = "R " .. t_of(mdl.tR) end
      parts[#parts + 1] = ({ mono = "mono", dual = "stereo", pp = "ping-pong" })[mdl.mode or ""] or (mdl.stereo and "stereo" or "mono")
    end
    if mdl.sync then parts[#parts + 1] = "synced" end
    ImGui.Spacing(ctx)
    ImGui.TextDisabled(ctx, "The canvas reads:  " .. table.concat(parts, "  \u{00B7}  "))
  end
  if ImGui.Button(ctx, "Guess from names") then
    local g = CS.guess(dlg.names, "delay")
    cv.roles, cv.rev, cv.nt = g.roles, g.rev, g.nt
    changed = true
  end
  return changed
end

-- A modulation: its main roles, then its voices (a chorus with voices of
-- its own), a tab each
local MOD_VOICE_NAMES = { Depth = "Depth", Rate = "Rate", Note = "Note value (synced)", Sync = "Sync (free / sync)",
                          Phase = "Phase", Pan = "Pan", On = "On" }
local function mod_page(ctx, cv)
  cv.roles = cv.roles or {}
  cv.rev = cv.rev or {}
  local changed = role_rows(ctx, cv, "md", M.MOD_MAIN)
  ImGui.Spacing(ctx)
  ImGui.TextDisabled(ctx, "Voices of its own")
  if ImGui.IsItemHovered(ctx) then
    ImGui.SetTooltip(ctx, "Up to three voices, each with its own depth, rate, phase or pan.\n" ..
      "Leave empty for one LFO.")
  end
  if ImGui.BeginTabBar(ctx, "##mdvoices") then
    for k = 1, M.MOD_VOICES do
      if ImGui.BeginTabItem(ctx, ("Voice %d##mdv%d"):format(k, k)) then
        local list = {}
        for _, r in ipairs(M.MOD_VOICE_ROLES) do list[#list + 1] = "V" .. k .. r end
        if role_rows(ctx, cv, "v" .. k, list,
            function(r) local _, b = M.mod_voice_split(r); return MOD_VOICE_NAMES[b] or b end,
            function(r) local _, b = M.mod_voice_split(r); return b end) then changed = true end
        ImGui.EndTabItem(ctx)
      end
    end
    ImGui.EndTabBar(ctx)
  end
  if ImGui.Button(ctx, "Guess from names") then
    local g = CS.guess(dlg.names, "mod")
    cv.roles, cv.rev = g.roles, g.rev
    changed = true
  end
  return changed
end

-- ---------------------------------------------------------------------
-- the window
-- ---------------------------------------------------------------------

local function draw_body(ctx, layout, cv, job, busy)
  local base, var = M.split_variant(dlg.key)
  ImGui.Text(ctx, ("%s  \u{00B7}  %s layout \"%s\""):format(base, M.CANVAS_NAMES[cv.kind] or "Compressor", var or "Standard"))
  ImGui.Spacing(ctx)
  local changed
  if cv.kind == "eq" then
    ImGui.TextWrapped(ctx, "Name each band's controls. Its shape isn't set here: Learn measures a hidden copy " ..
      "of the plugin and works it out. A band that shows its frequency in Hz, its gain in dB and has a Q " ..
      "control is learned in a moment; the others take longer.")
    ImGui.Spacing(ctx)
    changed = eq_page(ctx, layout, cv, busy)
  else
    ImGui.TextWrapped(ctx, "Name the plugin's control for each role, or leave it out. The canvas takes the " ..
      "plugin's own values; a control that doesn't read in its unit moves along its range.")
    ImGui.Spacing(ctx)
    ImGui.BeginDisabled(ctx, busy)
    if cv.builtin then
      ImGui.TextColored(ctx, C.COL.accent, cv.builtin == "readelay"
        and "ReaDelay's canvas sets itself up: its taps as ReaDelay has them (add and remove them on the canvas)."
        or "ReaVerbate's canvas sets itself up.")
    elseif cv.kind == "multi" then changed = multi_page(ctx, cv)
    elseif cv.kind == "delay" then changed = delay_page(ctx, cv)
    elseif cv.kind == "mod" then changed = mod_page(ctx, cv)
    else changed = comp_page(ctx, cv) end
    ImGui.EndDisabled(ctx)
    if cv.kind == "comp" then thr_section(ctx, layout, cv, job, busy) end
    if (cv.kind == "comp" or cv.kind == "limit") and ref_row(ctx, cv) then changed = true end
    if cv.kind == "deess" and dshape_row(ctx, cv) then changed = true end
    if cv.kind == "reverb" then decay_section(ctx, layout, cv, job, busy) end
    if cv.kind == "sat" then sat_section(ctx, layout, cv, job, busy) end
  end
  if changed then save() end

  ImGui.Separator(ctx)
  if cv.kind == "eq" then
    local addr = addr_now()
    local any_mapped = #cv.bands > 0
    for _, b in ipairs(cv.bands) do if not (b.freq or b.gain) then any_mapped = false end end
    local todo = M.canvas_todo(cv)
    if busy then
      ImGui.ProgressBar(ctx, job.progress or 0, 360, 0, ("%d%%"):format(math.floor((job.progress or 0) * 100)))
      ImGui.SameLine(ctx)
      ImGui.Text(ctx, job.msg or "")
      ImGui.SameLine(ctx)
      if ImGui.Button(ctx, "Cancel##learn") then LN.cancel(job) end
    else
      ImGui.BeginDisabled(ctx, not (any_mapped and addr))
      local label = todo and "Learn" or "Learn again"
      if ImGui.Button(ctx, label .. "##learn") then
        local play = reaper.GetPlayState() & 1 == 1
        if play and reaper.MB("Learning works best with the transport stopped. Learn anyway?",
            "ChannelView", 4) ~= 6 then
          -- not now
        else
          local which = nil
          if not todo then
            which = {}
            for k in ipairs(cv.bands) do which[#which + 1] = k end
          end
          dlg.job = LN.start(dlg.track, addr, dlg.key, layout, which)
        end
      end
      ImGui.EndDisabled(ctx)
      if ImGui.IsItemHovered(ctx, ImGui.HoveredFlags_AllowWhenDisabled) then
        ImGui.SetTooltip(ctx, any_mapped and
          "Measures each band's shape on a hidden copy.\n" ..
          "Takes up to a minute."
          or "Map each band's frequency or gain first.")
      end
      if job and job.msg and job.state ~= "measuring" then
        ImGui.SameLine(ctx)
        ImGui.TextColored(ctx, job.state == "done" and C.COL.accent or C.COL.warn, job.msg)
      end
    end
    ImGui.Spacing(ctx)
    ImGui.BeginDisabled(ctx, todo ~= nil or busy)
    if ImGui.Button(ctx, "Done", 90, 0) then dlg = nil; ImGui.CloseCurrentPopup(ctx) end
    ImGui.EndDisabled(ctx)
    if todo and ImGui.IsItemHovered(ctx, ImGui.HoveredFlags_AllowWhenDisabled) then
      ImGui.SetTooltip(ctx, "Learn every band first.")
    end
    ImGui.SameLine(ctx)
    if not busy and todo and ImGui.Button(ctx, "Leave for now") then
      dlg = nil; ImGui.CloseCurrentPopup(ctx)
    end
  else
    ImGui.BeginDisabled(ctx, busy)
    if ImGui.Button(ctx, "Done", 90, 0) then dlg = nil; ImGui.CloseCurrentPopup(ctx) end
    ImGui.EndDisabled(ctx)
  end
end

-- Call once a frame, outside any panel.
function CS.draw(ctx)
  if not dlg then return end
  local layout = M.get(dlg.key)
  if not (layout and layout.canvas) then dlg = nil return end
  local cv = layout.canvas
  local job = dlg.job
  if job then LN.step(job) end
  local busy = job ~= nil and (job.state == "starting" or job.state == "measuring")

  if dlg.open then ImGui.OpenPopup(ctx, TITLE); dlg.open = false end
  ImGui.SetNextWindowSize(ctx, cv.kind == "eq" and 1060 or 640, 0, ImGui.Cond_Appearing)
  local visible, open = ImGui.BeginPopupModal(ctx, TITLE, true, ImGui.WindowFlags_AlwaysAutoResize)
  if visible then
    draw_body(ctx, layout, cv, job, busy)
    ImGui.EndPopup(ctx)
  elseif not open then
    if job then LN.cancel(job) end
    dlg = nil
  end
end

-- A new EQ, Compressor, Gate or Limiter layout for this instance, named
-- `name`, guessed from the plugin's parameter names, then opened for
-- setting up.
-- Returns its variant name, or nil when the name won't do.
function CS.create(track, fx, base, name, kind, from)
  local k, nm = M.new_variant(base, name, from, false)
  if not k then return nil end
  local l = M.get(k)
  l.canvas = CS.guess(names_of(track, fx.addr), kind)
  -- the layout it was made from comes across: its faceplate, and the
  -- controls the canvas doesn't take, with their looks
  M.drop_placed(l)
  M.set(k, l)
  M.save()
  CS.open(track, fx, k)
  return nm, k
end

return CS
