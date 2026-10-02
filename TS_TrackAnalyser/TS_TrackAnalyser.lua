--========================================================
-- @title TS_TrackAnalyser
-- @description Track Analyser -- measured response over the spectrum, over dynamics
-- @author Tim Shadgett
-- @version 1.5.2
-- @changelog
--  No changes. The version moves to 1.5.2 to match ChannelView, so the two
--  tools carry the same number.
-- @about
--  # Track Analyser
--
--  Shows what your processing is actually doing to the selected track,
--  measured from the audio rather than modelled from parameter values.
--
--  A TS_TrackProbe sits at each end of the FX chain (the header's Install
--  button adds them). The difference between what the two hear IS the
--  magnitude response of everything between them, so it is right about
--  bypass, saturation and plugins nobody has characterised.
--
--  * Panel 1: the spectrum with the measured EQ response over it, and a
--    Collisions overlay that shows where another track masks this one.
--  * Panel 2: the waveform before and after, with gain reduction per
--    compressor over it. Its window can be a number of beats at the
--    project tempo, locked to the beat so hits land in the same place.
--
--  Needs ReaImGui. Works on its own; with ChannelView installed it also
--  shows gain reduction for plugins that don't report it.
-- @license MIT
-- @provides
--   [main]   TS_TA_InsertProbes.lua
--   [main]   TS_TA_QuietProbes.lua
--   [nomain] TS_TA_Chain.lua
--   [nomain] TS_TA_Strip.lua
--   [nomain] TS_TA_Mask.lua
--   [nomain] TS_TA_GR.lua
--   [effect] TS_TrackProbe.jsfx
--========================================================
--
-- Follows the selected track. Finds the TS_TrackProbe pair in your Strip
-- container, arms them, and draws two stacked panels in one dockable
-- window.
--
--   Panel 1  the spectrum the probes are publishing, pre and/or post, with
--            the MEASURED response of whatever sits between them drawn over
--            it. Post minus pre, from a running power average both probes
--            take on the same frames, IS the magnitude response -- checked
--            against the stepped-tone models to 0.069 dB rms. The POST
--            probe does that subtraction itself on a 256-point log grid and
--            smooths it there, so the panel reads a curve rather than
--            building one. It needs no parameter map and is right about
--            bypass, mute, insert slots, saturation, and plugins that have
--            never been characterised. It cannot say which band did what.
--
--   Panel 2  one overlay, not two: the untouched signal in grey behind,
--            the processed one in front. Those come from the probes and
--            work with anything.
--
--            Gain reduction is drawn ONLY from the VST3 route, where
--            REAPER hands over decibels directly. Plugins that instead
--            expose a reduction parameter -- InfiniStrip among them --
--            need a measured law, a staleness test and a hold to be read
--            at all, and every one of those was a source of error: a
--            calibration that was right for one module and wrong for
--            another, a hold that plateaued, a staleness test that never
--            released. The waveforms still show what those plugins do.
--            The reduction trace does not pretend to.
--
-- Nothing on screen is modelled. Both panels read the audio.
--
-- WHAT 1.0.0 TOOK OUT
--   Everything that existed to serve the modelled version of this panel,
--   now that nothing draws from a model:
--     - the per-module Gate / Comp / Lim reduction series, and with them
--       the measured meter laws, the staleness test and the timed hold
--     - the probe-derived "gain change across the span" trace, which was a
--       different quantity wearing the same name and showed no meaningful
--       difference from the measured figure when both were on screen
--     - the InfiniStrip slot, filter, EQ and insert-slot readers in
--       TS_TA_Strip, which cost about two thousand formatted-parameter calls
--       a second and fed nothing
--     - the probe's excitation generator, its per-sample level meters, and
--       its per-bin spectrum publishing -- about two thousand gmem writes
--       per frame per probe that nothing read
--
--   And the sample rate is no longer assumed to be 48 kHz, which at 96 kHz
--   had the scope ring holding half the time it claimed and the first FFT
--   bin sitting at 46.9 Hz, above the bottom of the display.
--
-- REQUIRES  TS_TA_Chain.lua and TS_TA_Strip.lua beside this file, and
--           TS_TrackProbe.jsfx (2026-09-07 or later) installed as an effect.
--           ReaPack puts it under Effects/ mirroring wherever this script
--           landed, so nothing here assumes a fixed path for it. An older
--           probe shows as a missing curve plus a note in Settings.
--           TS_TA_Strip is what finds and reads the reduction reporters, so
--           it is needed even though nothing draws a strip any more.
--========================================================

local r = reaper

----------------------------------------------------------
-- diagnostics
----------------------------------------------------------

-- Off in every release. Turn it on only while chasing a performance
-- problem: it prints a line to the ReaScript console whenever a frame
-- takes longer than FRAME_BUDGET, at most once every two seconds, split
-- into the time spent gathering state and the time spent drawing.
local DEBUG        = false
local FRAME_BUDGET = 0.15   -- seconds

----------------------------------------------------------
-- ReaImGui
----------------------------------------------------------
----------------------------------------------------------

local ImGui
do
  local ok, mod = pcall(function() return require 'imgui' '0.10' end)
  if ok and mod then
    ImGui = mod
  elseif r.ImGui_CreateContext then
    -- Older builds expose the flat reaper.ImGui_* names instead.
    ImGui = setmetatable({}, { __index = function(_, k) return r["ImGui_" .. k] end })
  else
    r.ShowMessageBox(
      "ReaImGui is required.\n\nInstall it from ReaPack:\n" ..
      "Extensions > ReaPack > Browse packages > \"ReaImGui\".",
      "Track Analyser", 0)
    return
  end
end

----------------------------------------------------------
-- modules
----------------------------------------------------------

-- Forward-declared: the context is not created until well below, but the
-- drawing helpers need it to measure text. Without this they would read a
-- nil global, which is silent until the moment it is not.
local ctx

local sep  = package.config:sub(1, 1)
local ACTX = { r.get_action_context() }
local here = ACTX[2]:match("^(.*)[\\/]") or "."

-- THIS SCRIPT'S OWN COMMAND ID, asked for rather than written down.
--   get_action_context gives the numeric id of the running instance;
--   ReverseNamedCommandLookup turns that into the "_RS..." name, which is
--   the stable one and the one __startup.lua needs. Hardcoding the id
--   would tie the startup option to one machine's action list, and would
--   silently write a dead line into __startup.lua anywhere else.
local MY_CMD = nil
do
  local num = ACTX[4]
  if num and r.ReverseNamedCommandLookup then
    local nm = r.ReverseNamedCommandLookup(num)
    if nm and nm ~= "" then
      MY_CMD = (nm:sub(1, 1) == "_") and nm or ("_" .. nm)
    end
  end
end

----------------------------------------------------------
-- run at startup
--
-- __startup.lua is the one file in this project that can break things
-- OTHER than this project: everything else Tim auto-starts runs from it,
-- so a malformed edit costs the grid script, the visualiser and the
-- update utility as well as this panel. Three rules follow from that.
--
--   1  A BACKUP FIRST, every time, to __startup.lua.bak.
--   2  THE RESULT IS COMPILED BEFORE IT IS SAVED. load() on the new text
--      catches a mangled edit while it is still a string in memory. A
--      startup file that does not parse is not written, ever.
--   3  LINES THIS SCRIPT DID NOT WRITE ARE NOT TOUCHED. Its own block is
--      fenced with markers and only that is ever removed. If the command
--      id turns up outside the fence -- added by hand, which is exactly
--      how it got there the first time -- the panel reports it and leaves
--      it alone rather than editing somebody else's line.
----------------------------------------------------------

local START_BEGIN = "-- >>> Track Analyser (added by TS_TrackAnalyser)"
local START_END   = "-- <<< Track Analyser"

-- The markers are full of Lua pattern metacharacters -- ( ) - . > -- so
-- they cannot be used as patterns raw. Matching on them unescaped is
-- exactly what made the panel report a block it had just written as
-- somebody else's hand-edit.
local function esc(str) return (str:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")) end
local BEGIN_PAT, END_PAT = esc(START_BEGIN), esc(START_END)

local function startupPath()
  return r.GetResourcePath() .. sep .. "Scripts" .. sep .. "__startup.lua"
end

local function readAll(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local t = f:read("*a") ; f:close() ; return t
end

-- "none" | "ours" | "manual" | "nocmd"
local startup = { state = "none", checked = false, note = nil }

local function startupScan()
  startup.checked = true
  startup.note = nil
  if not MY_CMD then
    startup.state = "nocmd"
    startup.note = "REAPER has not given this script an action id yet -- " ..
                   "add it to the Action List once and this works."
    return
  end
  local txt = readAll(startupPath())
  if not txt then startup.state = "none" ; return end
  local fenced = txt:match(BEGIN_PAT .. "(.-)" .. END_PAT)
  if fenced and fenced:find(MY_CMD, 1, true) then
    startup.state = "ours"
  elseif txt:find(MY_CMD, 1, true) then
    startup.state = "manual"
    startup.note = "already in __startup.lua, on a line this panel did not " ..
                   "write -- remove it by hand if you want it gone."
  else
    startup.state = "none"
  end
end

-- Writes `txt` only if it compiles. Returns true, or false plus why.
local function startupWrite(txt)
  local chunk, err = load(txt, "__startup.lua")
  if not chunk then
    return false, "the result would not compile: " .. tostring(err)
  end
  local path = startupPath()
  local cur = readAll(path)
  if cur then
    local bf = io.open(path .. ".bak", "wb")
    if bf then bf:write(cur) ; bf:close()
    else return false, "could not write the backup, so nothing was changed" end
  end
  local f = io.open(path, "wb")
  if not f then return false, "could not open __startup.lua for writing" end
  f:write(txt) ; f:close()
  return true
end

local function startupAdd()
  if not MY_CMD then return false, "no action id for this script" end
  -- Never twice. Two Main_OnCommand calls for the same script start two
  -- copies of the panel, both fighting over the same gmem.
  startupScan()
  if startup.state == "ours" or startup.state == "manual" then return true end
  local txt = readAll(startupPath()) or
    "-- REAPER startup script\n"
  if not txt:match("\n$") then txt = txt .. "\n" end
  txt = txt .. ("\n%s\nlocal track_analyser_cmd = '%s'\n" ..
                "reaper.Main_OnCommand(reaper.NamedCommandLookup(track_analyser_cmd), 0)\n%s\n")
    :format(START_BEGIN, MY_CMD, START_END)
  local ok, why = startupWrite(txt)
  startupScan()
  return ok, why
end

local function startupRemove()
  local txt = readAll(startupPath())
  if not txt then startupScan() ; return true end
  -- Only the fenced block, and only when it is ours. Anything else in
  -- that file belongs to something else.
  local out = txt:gsub("\n*" .. BEGIN_PAT .. ".-" .. END_PAT .. "\n*", "\n")
  -- Leave the file ending exactly one newline, the way it started.
  out = out:gsub("%s*$", "\n")
  local ok, why = startupWrite(out)
  startupScan()
  return ok, why
end

local MISSING = {}

-- A half-updated install is the commonest way this breaks, and the error
-- it produces -- a nil call several hundred lines away -- says nothing
-- useful. So every module states what it needs from its dependencies, by
-- name, and a missing one is reported as such before anything runs.
local function need(name, required, needs)
  local ok, m = pcall(dofile, here .. sep .. name .. ".lua")
  if ok and type(m) == "table" and needs then
    local missing = {}
    for _, fn in ipairs(needs) do
      if type(m[fn]) ~= "function" then missing[#missing + 1] = fn end
    end
    if #missing > 0 then
      r.ShowMessageBox(
        ("Your %s.lua is older than this panel needs.\n\nIt is missing: %s\n\n" ..
         "Install the current %s.lua into:\n%s")
        :format(name, table.concat(missing, ", "), name, here),
        "Track Analyser", 0)
      return nil
    end
  end
  if not ok or type(m) ~= "table" then
    if required then
      r.ShowMessageBox(name .. ".lua must sit beside this script.\n\n" .. tostring(m),
        "Track Analyser", 0)
    else
      -- Optional models: the panel still runs, it just cannot draw those
      -- modules, and says so in the window rather than in a dialog you
      -- have to dismiss on every launch.
      MISSING[#MISSING + 1] = name .. ".lua is not installed"
    end
    return nil
  end
  return m
end

local TA    = need("TS_TA_Chain", true, { "walk", "find", "arm", "disarm", "attach" })
if not TA then return end

-- Three functions, and only three: find what reports reduction, read it,
-- and know whether the plugin is switched on. The module-meter reader, its
-- calibration laws and the whole InfiniStrip parameter map went with the
-- per-module bars.
local Strip = need("TS_TA_Strip", true, {
  "reductionSources", "readReduction", "fxActive",
})
-- The masking arithmetic, kept out of here because it is testable on
-- synthetic spectra with known answers and this file is not.
local Mask = need("TS_TA_Mask", true, {
  "grid", "spreading", "excitation", "collide",
})
-- The gain-reduction arithmetic, out here for the same reason: it is
-- testable on synthetic band levels with a known answer, and this file is
-- not. See its header for why the measured trace is no longer a broadband
-- ratio.
local GR = need("TS_TA_GR", true, { "shape" })
if not Strip then return end
if not Mask then return end
if not GR then return end

-- The measured models are no longer part of drawing. They are kept for the
-- measurement tools and are not loaded here at all -- the panel must not
-- fail, or warn, over a file it does not use.

----------------------------------------------------------
-- settings
----------------------------------------------------------

-- CURVE SMOOTHING IS CHOSEN BY NAME, NOT BY A SLIDER
--   The width is in octaves because the band grid is uniform in log
--   frequency, so one setting behaves the same at 40 Hz as at 10 kHz. But
--   the useful values are the ones an analyser has always used, and a
--   continuous 0..1 slider makes you hunt for them. So: a list.
local SMOOTH = {
  { name = "Off",          oct = 0 },
  { name = "1/24 octave",  oct = 1 / 24 },
  { name = "1/12 octave",  oct = 1 / 12 },
  { name = "1/6 octave",   oct = 1 / 6 },
  { name = "1/3 octave",   oct = 1 / 3 },
  { name = "1/2 octave",   oct = 1 / 2 },
  { name = "1 octave",     oct = 1 },
}

local S = {
  showPre     = true,
  showPost    = true,
  showPreWave = true,
  -- Which panels exist at all. Hiding one gives the other the whole
  -- window rather than shrinking to a corner of it -- the point of
  -- turning a panel off is usually to see the other one bigger.
  showSpectrum = true,
  showScope    = true,
  showGR       = true,   -- the meter down the right side
  showGRTrace  = true,   -- and the trace over the waveform
  grTraceSrc   = 2,      -- 1 reported by the plugin, 2 measured by the probes

  -- Appearance, matching ChannelView so the two tools sit together. 219
  -- and 1.0 reproduce the hand-picked palette exactly.
  baseHue   = 219,
  tint      = 1.0,
  trackRule = true,   -- the track's colour as a hairline, top and bottom
  autoScale   = true,
  -- Off until you ask for it. The curve is the most demanding thing here:
  -- it needs BOTH probes publishing and enough signal through them to
  -- average, so on a quiet or half-set-up track it comes and goes. The
  -- spectrum underneath it does not, so that is what you get first.
  showCurve   = false,     -- the measured response over the spectrum
  curveTau    = 0.5,       -- seconds the response average remembers
  smoothIdx   = 5,         -- index into SMOOTH; 5 is 1/3 octave

  excRange    = 60,        -- draw a bin only within this much of the loudest
  curveFill   = true,      -- shade between the curve and 0 dB
  scaleDb     = 12,        -- half-range; 12 dB as asked, expanding on demand
  specTop     = -6,
  specBot     = -96,
  fftSize     = 2048,
  sliceMs     = 2,
  histSec     = 4,         -- how much of the scope ring panel 2 shows
  timeMode    = 1,         -- 1 free (wheel), 2 milliseconds, 3 beats
  windowMs    = 500,
  windowBeats = 4,
  beatLock    = true,
  grRange     = 24,        -- full scale of the reduction axis
  split       = 0.58,      -- panel 1 / panel 2 divide
  showSources = false,     -- the diagnostic block; useful, not wanted always

  -- COLOURS LIVE IN THE SETTINGS, NOT IN THE PALETTE
  --   0xRRGGBBAA, straight from ColorEdit4, and the ALPHA IS THE CONTROL:
  --   the fill is drawn at the colour's own opacity and the outline a
  --   little above it. That is what makes two spectra readable at once --
  --   the one behind is found through the one in front by its edge -- and
  --   it is one control instead of a colour plus a separate opacity
  --   slider that could disagree with it.
  cSpecPre  = 0x6A737C33,
  cSpecPost = 0x2E6E9657,

  -- COLLISIONS. See TS_TA_Mask.lua for what each number means; the defaults
  -- are the published Schroeder spread, a middle-of-the-road masking
  -- index, and a gate low enough to catch quiet parts without flagging
  -- the noise floor.
  showMask   = false,
  maskSpread = 1.0,      -- 0 = same critical band only, 1 = Schroeder
  maskOffset = 6,        -- dB below the spread excitation
  maskFloor  = -60,      -- audibility gate, dBFS at the ear's best point
  maskMargin = 0,        -- how deep before it is worth drawing
  maskDepth  = 12,       -- dB of masking that reads as fully red
  maskEdge   = true,     -- colour the spectrum's contour as well as its fill
  cMask      = 0xD0483CB0,
  cCurve    = 0xE8C25Aff,
  cWavePre  = 0x6E767Eff,
  cWavePost = 0x4E9AC8ff,
  cGR       = 0xF0A860ff,
  cGRMeas   = 0xD2609Bff,     -- reduction MEASURED by a probe tap: ChannelView's pink

  -- Each data colour follows the base hue until you take it off auto by
  -- unticking the box beside it. See DERIVED.
  autoSpecPre  = true,
  autoSpecPost = true,
  autoWavePre  = true,
  autoWavePost = true,
  autoCurve    = true,
  autoGR       = true,
  autoGRMeas   = true,
}

----------------------------------------------------------
-- geometry
----------------------------------------------------------

local F_LO, F_HI = 20, 20000
local LOG_LO, LOG_SPAN = math.log(F_LO), math.log(F_HI) - math.log(F_LO)

local function fx(hz, x0, w)
  return x0 + (math.log(math.max(hz, 1)) - LOG_LO) / LOG_SPAN * w
end

----------------------------------------------------------
-- colours   0xRRGGBBAA
----------------------------------------------------------

-- THE PALETTE IS GENERATED FROM ONE HUE, the same way ChannelView's is,
-- so both tools can be pulled into line with a REAPER theme by moving one
-- slider instead of editing thirty hex values. The entries are
-- { role, hue offset from the base, saturation, lightness }:
--
--   "tint"  -- the greys, which are not neutral: they lean slightly
--              toward the base hue, which is what keeps a dark UI from
--              looking muddy. Tint scales how far they lean -- 0 is true
--              grey, 1 is as designed.
--   "solid" -- the accent, following the base hue at full saturation.
--   "alert" -- warnings, pinned to their own hue and deliberately NOT
--              following the base: a warning should still read as a
--              warning when you have themed everything else blue.
--
-- Lightness is never touched by any of it. The contrast relationships are
-- what make this readable and they should not be at the mercy of a
-- colour picker.
--
-- At hue 219 and tint 1.0 every entry reproduces the hand-picked colour
-- it replaced, exactly -- checked byte for byte across all 21.
local ALERT_HUE = 17

local PALETTE = {
  bg        = { "tint",    -9.0, 0.130, 0.090 },
  grid      = { "tint",    -6.3, 0.126, 0.171 },
  gridStr   = { "tint",    -7.0, 0.128, 0.229 },
  zeroLine  = { "tint",    -7.4, 0.114, 0.327 },
  text      = { "tint",    -9.0, 0.083, 0.576 },
  textDim   = { "tint",    -9.0, 0.080, 0.392 },
  warn      = { "alert",   22.1, 0.667, 0.553 },
  winBg     = { "tint",   -15.0, 0.135, 0.073 },
  popupBg   = { "tint",    -9.0, 0.130, 0.090 },
  frameBg   = { "tint",    -9.0, 0.133, 0.118 },
  frameHov  = { "tint",    -6.7, 0.157, 0.163 },
  frameAct  = { "tint",    -7.0, 0.149, 0.198 },
  btn       = { "tint",    -9.0, 0.133, 0.118 },
  btnHov    = { "tint",    -7.0, 0.165, 0.178 },
  btnAct    = { "tint",    -7.2, 0.143, 0.233 },
  header    = { "tint",    -6.3, 0.136, 0.159 },
  headerHov = { "tint",    -7.0, 0.140, 0.210 },
  headerAct = { "tint",    -9.0, 0.136, 0.259 },
  textOff   = { "tint",    -9.0, 0.098, 0.322 },
  grab      = { "tint",    -9.0, 0.080, 0.392 },
  accent    = { "solid", -175.1, 0.755, 0.631 },
}

-- HSL -> 0xRRGGBBAA. Hue in degrees, s and l in 0..1.
local function hsl(h, s, l, a)
  h = (h % 360) / 360
  s = math.max(0, math.min(1, s))
  l = math.max(0, math.min(1, l))
  local function hue2(p, q, t)
    if t < 0 then t = t + 1 elseif t > 1 then t = t - 1 end
    if t < 1/6 then return p + (q - p) * 6 * t end
    if t < 1/2 then return q end
    if t < 2/3 then return p + (q - p) * (2/3 - t) * 6 end
    return p
  end
  local r, g, b
  if s == 0 then
    r, g, b = l, l, l
  else
    local q = (l < 0.5) and (l * (1 + s)) or (l + s - l * s)
    local p = 2 * l - q
    r, g, b = hue2(p, q, h + 1/3), hue2(p, q, h), hue2(p, q, h - 1/3)
  end
  local function b8(v) return math.max(0, math.min(255, math.floor(v * 255 + 0.5))) end
  return (b8(r) << 24) | (b8(g) << 16) | (b8(b) << 8) | (a or 0xff)
end

-- Rebuilt IN PLACE, because everything else holds a reference to COL.
local COL = {}

-- THE DATA COLOURS, DERIVED FROM THE SAME HUE
--
--   The spectrum, waveform, curve and reduction colours were seven hand
--   picked hex values, which meant moving the Hue slider recoloured the
--   furniture and left the data sitting on the old scheme.
--
--   Each is written here as the offset, saturation and lightness that
--   reproduces the hand-picked value EXACTLY at hue 219 -- every entry
--   round-trips to its original hex -- so turning this on changes
--   nothing until you move the hue.
--
--   Two families, and the split is not arbitrary. The unprocessed and
--   processed pairs sit within about sixteen degrees of the base: they
--   are the subject, and they belong to it. The response curve and the
--   reduction trace come out at -175 and +171 -- complementary, which is
--   what makes them readable ON TOP of the first pair rather than lost
--   in it. Those were the numbers already in the file; naming them is
--   the only thing that changed.
--
--   cMask is deliberately absent. Collision red is a fixed colour for a
--   fixed purpose, like a bypass lamp, and a warning that changes colour
--   with the furniture is not a warning.
--
--   { role, hue offset, saturation, lightness, alpha }
local DERIVED = {
  cSpecPre  = { "tint",   -9.0, 0.078, 0.451, 0.200 },
  cSpecPost = { "solid", -15.9, 0.531, 0.384, 0.341 },
  cWavePre  = { "tint",   -9.0, 0.068, 0.463, 1.000 },
  cWavePost = { "solid", -16.4, 0.526, 0.545, 1.000 },
  cCurve    = { "solid",-175.1, 0.755, 0.631, 1.000 },
  cGR       = { "solid", 171.0, 0.828, 0.659, 1.000 },
  -- Measured by a probe tap rather than reported: the same colour
  -- ChannelView uses for it (its gr_measured), so the two tools agree.
  cGRMeas   = { "solid", 110.0, 0.560, 0.600, 1.000 },
}

-- Which of them are following the hue. One flag per colour, so overriding
-- the reduction trace does not drag the spectrum out with it.
local DERIVED_AUTO = {
  cSpecPre  = "autoSpecPre",  cSpecPost = "autoSpecPost",
  cWavePre  = "autoWavePre",  cWavePost = "autoWavePost",
  cCurve    = "autoCurve",    cGR       = "autoGR",
  cGRMeas   = "autoGRMeas",
}

local function buildPalette()
  local base = S.baseHue or 219
  local tint = S.tint or 1.0
  for name, e in pairs(PALETTE) do
    local role, dh, sat, lum = e[1], e[2], e[3], e[4]
    local h, sa
    if role == "alert" then h, sa = ALERT_HUE + dh, sat
    elseif role == "tint" then h, sa = base + dh, sat * tint
    else h, sa = base + dh, sat end
    COL[name] = hsl(h, sa, lum, 0xff)
  end

  -- The data colours follow the same two knobs, except where you have
  -- said otherwise. Alpha is carried through untouched: on the spectrum
  -- it is the control, not decoration.
  for name, e in pairs(DERIVED) do
    if S[DERIVED_AUTO[name]] ~= false then
      local role, dh, sat, lum, a = e[1], e[2], e[3], e[4], e[5]
      local sa = (role == "tint") and sat * tint or sat
      S[name] = hsl(base + dh, sa, lum, math.floor(a * 255 + 0.5))
    end
  end
  return COL
end

buildPalette()

local function alpha(col, a)
  a = math.max(0, math.min(1, a))
  return (col & 0xFFFFFF00) | math.floor(a * 255)
end

-- The alpha a colour was picked with, 0..1, and the same colour opened up
-- for the outline that makes it findable behind another one.
-- Fit a label into a measured pixel width, ellipsising if it will not go.
-- Returns the text and its width, or nil when even "..." does not fit.
--
-- Cut on a UTF-8 BOUNDARY. Track names are whatever you typed, and
-- slicing a multi-byte character in half renders as a replacement box --
-- which looks exactly like the font missing a glyph, and would have sent
-- somebody looking in the wrong place.
local chipFitCache = { s = nil, w = -1, out = nil, tw = 0 }

local function chipFit(ctx, str, maxW)
  if chipFitCache.s == str and chipFitCache.w == maxW then
    return chipFitCache.out, chipFitCache.tw
  end
  local out, tw = nil, 0
  if maxW > 0 then
    local fullW = ImGui.CalcTextSize(ctx, str)
    if fullW <= maxW then
      out, tw = str, fullW
    else
      local ell = "..."
      local ellW = ImGui.CalcTextSize(ctx, ell)
      if ellW <= maxW then
        -- Binary search on the byte length: six measurements rather than
        -- one per character, and each measurement crosses the Lua/C
        -- boundary.
        local lo, hi, best, bestW = 0, #str, nil, 0
        while lo <= hi do
          local mid = (lo + hi) // 2
          local n = mid
          -- step back off a continuation byte
          while n > 0 do
            local b = str:byte(n + 1)
            if b and b >= 0x80 and b < 0xC0 then n = n - 1 else break end
          end
          local cand = str:sub(1, n) .. ell
          local cw = ImGui.CalcTextSize(ctx, cand)
          if cw <= maxW then best, bestW, lo = cand, cw, mid + 1
          else hi = mid - 1 end
        end
        out, tw = best, bestW
      end
    end
  end
  chipFitCache.s, chipFitCache.w = str, maxW
  chipFitCache.out, chipFitCache.tw = out, tw
  return out, tw
end

-- THE TRACK'S OWN COLOUR AS A HAIRLINE, top and bottom. Same device as
-- ChannelView, and the point of it is the same: with several of these
-- docked you can tell at a glance which one is following which track,
-- without reading a single word.
--
-- I_CUSTOMCOLOR carries a 0x1000000 flag meaning "a colour was actually
-- set". Without that flag the low bits are stale and must not be drawn --
-- that is how you end up with every uncoloured track sharing one
-- arbitrary hue.
local function trackColour(tr)
  if not tr or not r.ValidatePtr2(0, tr, "MediaTrack*") then return nil end
  local v = r.GetMediaTrackInfo_Value(tr, "I_CUSTOMCOLOR")
  if not v or v == 0 then return nil end
  v = math.floor(v)
  if (v & 0x1000000) == 0 then return nil end
  local cr, cg, cb = r.ColorFromNative(v & 0xFFFFFF)
  return (cr << 24) | (cg << 16) | (cb << 8) | 0xFF
end

-- The track is passed in rather than read from the rig: this sits above
-- where the rig locals are declared, and a function that reaches forward
-- for one would silently read a nil global instead.
local function trackRule(dl, x, y, w, tr)
  if not S.trackRule then return end
  local col = trackColour(tr)
  if not col and tr and tr == r.GetMasterTrack(0) then col = 0x8A90A0FF end
  ImGui.DrawList_AddRectFilled(dl, x, y, x + w, y + 2, col or COL.grid, 0)
end

local function alphaOf(col) return (col & 0xFF) / 255 end
local function edgeOf(col)  return alpha(col, math.min(1, alphaOf(col) + 0.35)) end

----------------------------------------------------------
-- the widget style
--
-- ImGui's defaults are a bright blue on mid grey, which is fine in a
-- debug overlay and wrong next to two near-black panels -- the Settings
-- button was the loudest thing on screen, competing with the traces it
-- exists to configure.
--
-- So the stock widgets are dressed in the panel's own palette: near-black
-- frames, a hairline border instead of a fill, and the response curve's
-- gold as the one accent, used only where a control is actually engaged.
-- Nothing here changes behaviour; it stops the furniture shouting.
--
-- Pushed after Begin and popped before End, every frame, because ImGui is
-- immediate mode and there is nowhere else to keep it.
----------------------------------------------------------

-- Enum name paired with a PALETTE key rather than a literal, so moving
-- the hue moves the widgets with everything else. Resolved once; the
-- colour itself is looked up at push time, which is a table read.
local STYLE_COL = {
  { "Col_Text",                 "text"      },
  { "Col_TextDisabled",         "textOff"   },
  { "Col_WindowBg",             "winBg"     },
  { "Col_PopupBg",              "popupBg"   },
  { "Col_Border",               "grid"      },
  { "Col_FrameBg",              "frameBg"   },
  { "Col_FrameBgHovered",       "frameHov"  },
  { "Col_FrameBgActive",        "frameAct"  },
  { "Col_TitleBg",              "winBg"     },
  { "Col_TitleBgActive",        "popupBg"   },
  { "Col_TitleBgCollapsed",     "winBg"     },
  { "Col_Button",               "btn"       },
  { "Col_ButtonHovered",        "btnHov"    },
  { "Col_ButtonActive",         "btnAct"    },
  { "Col_Header",               "header"    },
  { "Col_HeaderHovered",        "headerHov" },
  { "Col_HeaderActive",         "headerAct" },
  { "Col_CheckMark",            "accent"    },
  { "Col_SliderGrab",           "grab"      },
  { "Col_SliderGrabActive",     "accent"    },
  { "Col_Separator",            "grid"      },
  { "Col_SeparatorHovered",     "gridStr"   },
  { "Col_ResizeGripHovered",    "gridStr"   },
  { "Col_ResizeGripActive",     "zeroLine"  },
  { "Col_ScrollbarGrab",        "grid"      },
  { "Col_ScrollbarGrabHovered", "gridStr"   },
  { "Col_ScrollbarGrabActive",  "zeroLine"  },
}

local STYLE_VAR = {
  { "StyleVar_FrameRounding",   3 },
  { "StyleVar_GrabRounding",    3 },
  { "StyleVar_PopupRounding",   4 },
  { "StyleVar_FrameBorderSize", 1 },
  { "StyleVar_PopupBorderSize", 1 },
}

-- Names are looked up rather than assumed: ReaImGui gains and renames
-- enum accessors between versions, and a missing one should cost that
-- one colour, not the whole panel.
--
-- RESOLVED ONCE. The enum accessors return constants, so calling forty
-- of them thirty times a second is forty marshalled calls a frame to
-- learn something that cannot change. The first frame resolves them and
-- every frame after pushes from a plain list of numbers.
--
-- A push that raises anything is dropped from the list rather than
-- retried, so a build that dislikes one particular style var does not
-- spend the rest of the session throwing on it.
local styleReady = nil

local function resolveStyle()
  local cols, vars = {}, {}
  for _, e in ipairs(STYLE_COL) do
    local fn = ImGui[e[1]]
    if fn then
      local ok, v = pcall(fn)
      -- the enum value and the PALETTE KEY, not the colour: the colour is
      -- read fresh each frame so the hue slider takes effect at once
      if ok and v then cols[#cols + 1] = { v, e[2] } end
    end
  end
  for _, e in ipairs(STYLE_VAR) do
    local fn = ImGui[e[1]]
    if fn then
      local ok, v = pcall(fn)
      if ok and v then vars[#vars + 1] = { v, e[2] } end
    end
  end
  return { cols = cols, vars = vars }
end

local function pushStyle(ctx)
  styleReady = styleReady or resolveStyle()
  local nc, nv = 0, 0
  local cols, vars = styleReady.cols, styleReady.vars
  for i = #cols, 1, -1 do
    local e = cols[i]
    if pcall(ImGui.PushStyleColor, ctx, e[1], COL[e[2]] or 0x808080ff) then nc = nc + 1
    else table.remove(cols, i) end
  end
  for i = #vars, 1, -1 do
    local e = vars[i]
    if pcall(ImGui.PushStyleVar, ctx, e[1], e[2]) then nv = nv + 1
    else table.remove(vars, i) end
  end
  return nc, nv
end

local function popStyle(ctx, nc, nv)
  if nv > 0 then ImGui.PopStyleVar(ctx, nv) end
  if nc > 0 then ImGui.PopStyleColor(ctx, nc) end
end

----------------------------------------------------------
-- settings that survive a restart
--
-- A colour you have to pick again every time REAPER starts is not a
-- setting, it is a nuisance. Written at most once a second and only after
-- something changed, so dragging a slider does not write ExtState thirty
-- times a second.
----------------------------------------------------------

local EXT = "TS_TrackAnalyser"

-- ---------------------------------------------------------------------
-- THE SHARED PALETTE
--
--   Hue and tint are one choice across ChannelView, this panel and
--   TS_Visualizer, so they live in a section of their own rather than in
--   any one tool's. They used to live in ChannelView's, which three other
--   scripts reached across into -- workable only for as long as
--   ChannelView was the one that happened to own them.
--
--   The old location is still read when the new one is empty, so an
--   existing setting survives the update rather than everybody's colours
--   snapping back to stock. Nothing here supplies a default: nil means
--   "no shared setting", and this panel then keeps its own, which is what
--   lets it run with neither of the other tools installed.
-- ---------------------------------------------------------------------
local PAL_SECT   = "TS_Palette"
local PAL_LEGACY = "TS_ChannelView"

local function palGet()
  local h = r.GetExtState(PAL_SECT, "base_hue")
  local t = r.GetExtState(PAL_SECT, "tint")
  if h == "" then h = r.GetExtState(PAL_LEGACY, "base_hue") end
  if t == "" then t = r.GetExtState(PAL_LEGACY, "tint") end
  return tonumber(h), tonumber(t)
end

local function palSet(h, t)
  r.SetExtState(PAL_SECT, "base_hue", tostring(math.floor(h)), true)
  r.SetExtState(PAL_SECT, "tint", string.format("%.3f", t), true)
end

-- Poll rather than push, at the same half second ChannelView and its TCP
-- window use. ExtState is a string lookup; twice a second costs nothing
-- measurable, and it means no tool has to know which others exist.
local palPoll = -1
local function palFollow(now)
  if now - palPoll < 0.5 then return end
  palPoll = now
  local h, t = palGet()
  if not h or not t then return end
  if math.abs(h - (S.baseHue or 219)) < 1e-6
     and math.abs(t - (S.tint or 1)) < 1e-4 then return end
  -- Applying does NOT write back. Two tools that each wrote what they
  -- read would ping-pong for ever over the last decimal place.
  S.baseHue, S.tint = h, t
  buildPalette()
end
local settingsDirty, settingsAt = false, 0
local function touchSettings() settingsDirty = true end

local function saveSettings()
  local parts = {}
  for k, v in pairs(S) do
    if type(v) == "number" then parts[#parts + 1] = ("%s=%.10g"):format(k, v)
    elseif type(v) == "boolean" then parts[#parts + 1] = ("%s=%s"):format(k, v and "1" or "0") end
  end
  table.sort(parts)
  r.SetExtState(EXT, "settings", table.concat(parts, ";"), true)
end

local function loadSettings()
  local s = r.GetExtState(EXT, "settings")
  if not s or s == "" then return end
  for k, v in s:gmatch("([%a%d_]+)=([^;]+)") do
    local cur = S[k]
    if type(cur) == "number" then
      local n = tonumber(v)
      -- NaN fails this test, which is the point: a corrupt entry is
      -- ignored rather than becoming a coordinate.
      if n and n == n then
        -- tonumber gives back a float. A colour is about to be masked with
        -- & and |, and those want an integer, so anything that is whole
        -- goes back as one.
        if math.type(n) == "float" and n % 1 == 0 then
          n = math.tointeger(n) or n
        end
        S[k] = n
      end
    elseif type(cur) == "boolean" then
      S[k] = (v == "1")
    end
  end
  S.smoothIdx = math.max(1, math.min(#SMOOTH, math.floor(S.smoothIdx or 5)))
  S.baseHue   = math.max(0, math.min(359, math.floor(S.baseHue or 219)))
  S.tint      = math.max(0, math.min(2, S.tint or 1))
end

loadSettings()
-- The SHARED hue and tint win over this panel's own copy when one has
-- been set, so opening the panel next to ChannelView does not briefly
-- show a different colour before the first poll lands.
do
  local h, t = palGet()
  if h then S.baseHue = math.max(0, math.min(359, math.floor(h))) end
  if t then S.tint    = math.max(0, math.min(2, t)) end
end
-- The palette follows whatever hue and tint came back from ExtState.
buildPalette()

----------------------------------------------------------
-- packed drawing
--
-- ReaImGui marshals every DrawList_* call across the Lua/C boundary, and
-- this panel was issuing about four thousand a frame: one quad and one line
-- per pixel column, per trace, per panel. The arithmetic was never the
-- problem. The same geometry handed over as one packed array of points is
-- a single call.
--
-- It also cures an artefact. Adjacent alpha-blended quads overlap along
-- their shared edge by a fraction of a pixel, and that sliver gets blended
-- twice, so every seam draws a faint vertical line. One polygon has no
-- internal seams to double-blend.
--
-- Everything here degrades rather than fails: if the installed ReaImGui
-- does not have the packed calls, or the first attempt errors, packing is
-- switched off for the session and the per-segment path takes over.
----------------------------------------------------------

-- ONLY STROKES ARE PACKED. FILLS ARE NOT.
--
-- The first version of this also packed the filled areas into single
-- AddConcavePolyFilled calls. Do not do that. A waveform band is about
-- twelve hundred points, ImGui triangulates a concave polygon rather than
-- fanning it, and where the minimum and maximum paths touch, the polygon
-- self-intersects -- which is how you get REAPER sitting there. Strokes are
-- linear in the number of points and are what AddPolyline exists for; the
-- fills go back to a quad per span, which after the band summary is 256 of
-- them for a spectrum rather than 600.
local polyOK = type(ImGui.DrawList_AddPolyline) == "function"
           and type(r.new_array) == "function"

-- Keyed by exact length, because a reaper.array carries its length with it
-- and AddPolyline reads every element -- an over-long buffer would draw
-- whatever was left in the tail. Lengths repeat frame to frame while the
-- window is a fixed size, so this allocates almost never in practice.
local PTBUF = {}
local function ptbuf(npoints)
  local need = npoints * 2
  local a = PTBUF[need]
  if not a then a = r.new_array(need) ; PTBUF[need] = a end
  return a
end

-- One stroked run. i0..i1 index xsA/ysA.
local function polyline(dl, xsA, ysA, i0, i1, col, thick)
  if i1 - i0 < 1 then return end
  if polyOK then
    local done = pcall(function()
      local a = ptbuf(i1 - i0 + 1)
      local j = 0
      for i = i0, i1 do a[j + 1] = xsA[i] ; a[j + 2] = ysA[i] ; j = j + 2 end
      ImGui.DrawList_AddPolyline(dl, a, col, 0, thick or 1.0)
    end)
    if done then return end
    polyOK = false
  end
  for i = i0, i1 - 1 do
    ImGui.DrawList_AddLine(dl, xsA[i], ysA[i], xsA[i + 1], ysA[i + 1], col, thick or 1.0)
  end
end

----------------------------------------------------------
-- probe state
----------------------------------------------------------

local G = TA.gmem

-- Probe taps (plugins measured rather than reported): the heartbeat slot
-- that keeps them running, and where the post probe writes each tap's
-- reduction per scope column while this panel has the track armed.
local TAP_HB, TAP_TRACE, TAP_COLS = 73, 0x50000, 4096
local tapBeat = 0
TA.attach()

local rig, rigTrack, rigNote = nil, nil, nil
-- True when the note is specifically 'this track has no probes', which is
-- the one fault the panel can offer to fix. Anything else is just reported.
local rigNeedsProbes = false
local rigSources = {}     -- everything between the probes that reports reduction
local rigOutside = {}     -- reduction reporters that are NOT between them
local lock       = {}     -- the scope trigger: anchor, step, ring length
local chainSig   = nil    -- what the chain looked like last time we looked
local lagCheckedAt = 0
local rigLag     = 0      -- samples of latency reported by the FX between
                          -- the probes; the pre probe delays itself by it
local grShape    = {}     -- reused, so the trace allocates nothing a frame
local grScratch  = {}
local nextScan   = 0
local lastChange = -1     -- REAPER's own project change counter

----------------------------------------------------------
-- the comparison track
--
-- Its post probe is pointed at a third gmem region and told to publish,
-- so two tracks produce spectra at once. It is held by GUID rather than
-- by pointer: a MediaTrack* is only valid until the project changes
-- under it, and this one has to survive you selecting other tracks,
-- which is the entire point of it.
----------------------------------------------------------

local cmpGuid  = nil      -- what you picked, as a stable identity
local cmpRig   = nil      -- its probe pair, once found
local cmpTrack = nil
local cmpName  = ""

-- WHAT EACH TRACK WAS LAST COMPARED AGAINST.
--   Keyed by the selected track's GUID, holding the comparison track's.
--   Switching to a track you have compared before puts its partner back
--   rather than making you pick it again, which is the difference
--   between a comparison you use and one you set up once.
--
--   Deliberately NOT persisted. It is a working set for this sitting;
--   restoring it days later would arm probes on tracks you had forgotten
--   about, and the pairing you want tomorrow is rarely the one you
--   wanted today.
local cmpFor = {}

-- What the gate above last acted on, so the track walk happens on a
-- change rather than on a clock.
local cmpLastTrack, cmpLastChange = nil, -1

local function guidOf(tr)
  if not tr or not r.ValidatePtr2(0, tr, "MediaTrack*") then return nil end
  local _, g = r.GetSetMediaTrackInfo_String(tr, "GUID", "", false)
  return (g ~= "" and g) or nil
end

local function trackByGuid(guid)
  if not guid or guid == "" then return nil end
  for i = 0, r.CountTracks(0) - 1 do
    local tr = r.GetTrack(0, i)
    local _, g = r.GetSetMediaTrackInfo_String(tr, "GUID", "", false)
    if g == guid then return tr end
  end
  return nil
end

-- The fader, in dB, so the comparison happens at the levels you are
-- actually hearing. The probes sit inside the FX chain, which is
-- pre-fader: without this a track pulled right down reads as masking
-- everything while being inaudible.
--
-- A muted track masks nothing at all, and is reported as silent rather
-- than as quiet.
local function trackGainDb(tr)
  if not tr or not r.ValidatePtr2(0, tr, "MediaTrack*") then return nil end
  if r.GetMediaTrackInfo_Value(tr, "B_MUTE") == 1 then return nil end
  local v = r.GetMediaTrackInfo_Value(tr, "D_VOL") or 1
  if v <= 0 then return nil end
  return 20 * math.log(v, 10)
end

-- NEVER DISARM A PROBE THE PANEL'S OWN RIG IS USING.
--
--   This is what froze the post spectrum. Select track A, compare
--   against B, then select B: B's probes now belong to the rig, armed by
--   TA.arm, with its post probe publishing to POST_BASE. But cmpRig was
--   still pointing at B. Picking a new comparison track called
--   releaseCompare first, which set publish = 0 on B's post probe -- the
--   selected track's own post probe -- and the post spectrum stopped
--   dead while everything else carried on.
--
--   So the release checks whose track it is. If the comparison track has
--   become the selected one, the reference is dropped and the probes are
--   left exactly as the rig set them.
local function releaseCompare()
  if cmpRig and cmpRig.track ~= rigTrack then
    TA.releaseCompare(cmpRig)
  end
  cmpRig, cmpTrack = nil, nil
end

-- Called when the pick changes, when the project changes under us, and
-- whenever the selected track becomes the comparison track -- which is
-- not an error, it just means there is nothing to compare right now.
local function refreshCompare()
  local want = trackByGuid(cmpGuid)

  -- Checked BEFORE the early return. The old code returned as soon as
  -- the wanted track matched the one already held, which meant becoming
  -- the selected track went unnoticed for as long as the pick did not
  -- change.
  if want and want == rigTrack then
    releaseCompare()
    cmpTrack, cmpName = nil, ""
    return
  end

  if want == cmpTrack and cmpRig then return end
  releaseCompare()
  cmpTrack = want
  if not cmpTrack then cmpName = "" ; return end
  local _, n = r.GetSetMediaTrackInfo_String(cmpTrack, "P_NAME", "", false)
  cmpName = (n ~= "" and n) or "(unnamed)"
  local found = TA.find(cmpTrack)
  if found and found.post then
    cmpRig = found
    TA.armCompare(cmpRig)
  end
end

-- The selected track changed: put back whatever it was last compared
-- against, and release the previous partner so two comparison probes are
-- never publishing into the one region.
-- The partner chosen most recently, whatever track you were on. See
-- compareFollowTrack for what it is for.
local cmpLast = nil

local function compareFollowTrack()
  local g = guidOf(rigTrack)
  -- WHAT THIS TRACK WAS PAIRED WITH, OR FAILING THAT, THE LAST PARTNER
  -- YOU CHOSE AT ALL.
  --
  --   Falling back to nothing meant that switching to a track you had
  --   not compared before left collisions switched on and inert -- lamp
  --   lit, nothing on screen, no track named. That reads as the feature
  --   having quietly turned itself off.
  --
  --   The fallback matches how the tool actually gets used: you pick the
  --   vocal once and then walk the arrangement checking everything
  --   against it. Selecting a track you HAVE paired before still gets
  --   its own partner back, so the per-track memory still wins where it
  --   has something to say.
  local want = (g and cmpFor[g]) or cmpLast
  -- A track cannot be compared with itself, and offering to is worse
  -- than offering nothing.
  if want and g and want == g then want = nil end
  if want ~= cmpGuid then
    releaseCompare()
    cmpGuid = want
  end
  refreshCompare()
end

-- Remember this pairing for the track you are on.
local function setCompare(guid)
  releaseCompare()
  cmpGuid = guid
  local g = guidOf(rigTrack)
  if g then cmpFor[g] = guid end
  if guid then cmpLast = guid end
  refreshCompare()
end

----------------------------------------------------------
-- the analysis geometry, kept in step with the real sample rate
--
-- Both of these used to assume 48 kHz. At 96 kHz that made the scope ring
-- hold 4.1 seconds while claiming 8.2, and it put the first FFT bin at
-- 46.9 Hz -- so the bottom half-octave of the display had nothing behind
-- it and drew as background. At 48 kHz nothing here changes: 48000/2048 is
-- 23.4 Hz, already under the limit, so the size you asked for is the size
-- you get.
----------------------------------------------------------

local function fftFor(srate)
  local want = S.fftSize
  if want ~= 256 and want ~= 512 and want ~= 1024
     and want ~= 2048 and want ~= 4096 then want = 2048 end
  -- Long enough that the first bin is at or below 24 Hz, within what the
  -- probe supports. Below that there is nothing to draw at the left edge.
  while want < 4096 and (srate / want) > 24 do want = want * 2 end
  return want
end

local anaFft, anaSlice = 0, 0
local function applyAnalysis(force)
  local sr = r.gmem_read(G.POST_BASE + G.H_SRATE)
  if not sr or sr ~= sr or sr < 8000 or sr > 768000 then sr = 48000 end
  local fft   = fftFor(sr)
  local slice = math.max(8, math.floor(sr * S.sliceMs * 0.001))
  if force or fft ~= anaFft or slice ~= anaSlice then
    anaFft, anaSlice = fft, slice
    TA.setAnalysis(fft, slice)
  end
end

-- Defined further down, once the buffers it clears exist. Declared here
-- because followTrack calls it, and a function body that names a local
-- declared later silently reads a global instead.
local clearState

-- WHEN TO LOOK AT THE CHAIN AGAIN
--
--   Moving a plugin in or out of the probes changes what the panel should
--   be reading, and nothing about the TRACK changes when you do it. The
--   first attempt fingerprinted the chain twice a second regardless, which
--   was wrong: walking it costs three GetNamedConfigParm calls per FX to
--   collect alternate names -- around twenty a second on a chain this size,
--   on the same API that serves GainReduction_dB -- and it disturbed the
--   meter readings it was meant to keep honest.
--
--   REAPER already counts project changes. Reading that integer is one
--   call per frame and costs nothing, and while you are not editing
--   anything it never changes, so the chain is not walked at all. When it
--   does change -- which a knob move also does -- the walk happens at most
--   once a second, and only a genuine difference rebuilds anything.
local function signatureOf(tr)
  if not tr then return "none" end
  local parts = { tostring(r.TrackFX_GetCount(tr)) }
  local ok, chain = pcall(TA.walk, tr, {})
  if ok and chain then
    for _, fx in ipairs(chain) do
      parts[#parts + 1] = ("%d:%s:%s"):format(fx.idx, fx.name,
        r.TrackFX_GetEnabled(tr, fx.idx) and "1" or "0")
    end
  end
  -- ChannelView laying or lifting probe taps changes which plugins are
  -- measured without changing the chain itself, so its record is part of
  -- what the sources were built from.
  local okt, taps = r.GetSetMediaTrackInfo_String(tr, "P_EXT:TS_CV_TAPS", "", false)
  parts[#parts + 1] = okt and taps or ""
  return table.concat(parts, "|")
end

----------------------------------------------------------
-- inserting probes
----------------------------------------------------------

-- Two places offer this: the button in Settings, and the Install? prompt in
-- the header when the selected track has none. Both run the same script, so
-- there is one set of rules about what inserting does rather than two.
--
-- EVERYTHING IS RELEASED FIRST, and that is not tidiness.
--
--   The panel holds FX INDICES for the probes it has armed. Inserting at
--   slot 0 shifts every index on that track by one, so a disarm afterwards
--   would write publish = 0 to whatever plugin had moved into the old slot
--   -- a silent parameter write to somebody else's compressor.
--
--   So the rig is disarmed while its indices are still true, and then
--   forgotten. followTrack sees no rig and builds a fresh one from the
--   chain as it now is.
local function runInsertProbes()
  if rig then TA.disarm(rig) end
  releaseCompare()
  rig, rigTrack = nil, nil

  -- pcall, because a fault in a script run from inside the defer loop would
  -- otherwise take the panel down with it.
  local ok, err = pcall(dofile, here .. sep .. "TS_TA_InsertProbes.lua")
  if not ok then
    r.ShowMessageBox("TS_TA_InsertProbes.lua could not be run.\n\n" ..
      tostring(err), "Track Analyser", 0)
  end
  -- Rescan on the next frame rather than waiting out the once-a-second timer.
  chainSig, lastChange, nextScan = nil, -1, 0
  cmpLastTrack, cmpLastChange = nil, -1
end

-- Yes/no first. Inserting rebuilds the FX chain, so it is never something
-- that happens on a single stray click.
local function confirmInsertProbes()
  local nsel = r.CountSelectedTracks(0)
  local what = (nsel > 1)
    and ("Add a probe at each end of the FX chain on %d selected tracks?")
          :format(nsel)
     or "Add a probe at each end of this track's FX chain?"
  if r.ShowMessageBox(
       what .. "\n\nIt only ever adds. Nothing is removed, reordered or " ..
       "replaced,\nand a track that already has a pair is left alone.",
       "Track Analyser", 4) == 6 then
    runInsertProbes()
  end
end

-- THE LATENCY BETWEEN THE PROBES
--
--   Everything between the probes delays the post one by its own reported
--   PDC. REAPER compensates delay at the track OUTPUT, so that tracks line
--   up with each other; it does not time-travel inside a chain, and nothing
--   puts this right before it reaches the probes.
--
--   Uncorrected it is not a small error. At 32 samples -- a third of a
--   scope column, which is what one oversampled plugin costs -- the
--   measured trace's error against a known reduction goes from 0.01 dB to
--   2.36 dB and its correlation from 1.00 to 0.74. At one whole column a
--   silent gap in one ring lines up with a transient in the other and it
--   stops being wrong and starts being noise: 226 dB spikes on a 12 dB
--   reduction.
--
--   Walked in CHAIN ORDER rather than by comparing indices, because an FX
--   inside a container carries an encoded index and `i > lo and i < hi` is
--   not true of it in any useful way. Containers themselves are skipped and
--   their children counted, so nothing is added twice. Disabled and offline
--   plugins are skipped because REAPER does not run them.
local function chainLatency(tr, rg)
  if not (tr and rg and rg.pre and rg.post) then return 0 end
  if rg.pre.idx == rg.post.idx then return 0 end
  local seen, total = false, 0
  for _, fx in ipairs(rg.chain or {}) do
    if fx.idx == rg.pre.idx then
      seen = true
    elseif fx.idx == rg.post.idx then
      break
    elseif seen and not fx.isContainer then
      local on = r.TrackFX_GetEnabled(tr, fx.idx)
      local off = r.TrackFX_GetOffline(tr, fx.idx)
      if on and not off then
        local ok, v = r.TrackFX_GetNamedConfigParm(tr, fx.idx, "pdc")
        local n = ok and tonumber(v)
        if n and n > 0 then total = total + n end
      end
    end
  end
  -- Clamped to what the probe's delay line can hold. Past this something is
  -- either misreporting or doing something the measured trace was never
  -- going to describe.
  return math.min(math.floor(total), 65536)
end

-- HOW LATE A SOURCE'S READING MUST BE DRAWN, in samples.
--   The waveform is the post probe's input. Everything after a plugin and
--   before the post probe delays that plugin's output by its own latency
--   -- REAPER compensates at the track's output, not inside the chain --
--   so a reduction read at the plugin is early against the waveform by
--   that much.
--     * a tap reads the plugin's OUTPUT (on spare channels nothing else
--       touches), so only what comes after it counts
--     * a reported reading comes from the plugin's detector, which runs
--       ahead of its own output by its own latency -- a lookahead
--       compressor's meter moves before the audio it is turning down
--       comes out -- so its own latency counts as well
--   Bypassed and offline plugins add nothing, as in chainLatency.
local function sourceDelay(tr, rg, src)
  if not (tr and rg and rg.post and src) then return 0 end
  local function lat(idx)
    if not r.TrackFX_GetEnabled(tr, idx) or r.TrackFX_GetOffline(tr, idx) then return 0 end
    local ok, v = r.TrackFX_GetNamedConfigParm(tr, idx, "pdc")
    local n = ok and tonumber(v)
    return (n and n > 0) and n or 0
  end
  local seen, total = false, 0
  for _, fx in ipairs(rg.chain or {}) do
    if fx.idx == rg.post.idx then break end
    if seen and not fx.isContainer then total = total + lat(fx.idx) end
    if fx.idx == src.fx then seen = true end
  end
  if not seen then return 0 end
  if not src.est then total = total + lat(src.fx) end
  return math.min(math.floor(total), 65536)
end

local function setUpRig(tr, keepPre, keepPost)
  rigTrack, rig, rigNote, rigNeedsProbes = tr, nil, nil, false
  rigLag = 0
  clearState(keepPre ~= nil)
  if not tr then rigNote = "No track selected." return end
  local found, why = TA.find(tr)
  if not found then
    -- Distinguish "there are no probes here", which is one click from being
    -- fixed, from any other reason find() refused.
    rigNeedsProbes = (why or ""):find(TA.PROBE_NAME or "Probe", 1, true) ~= nil
    rigNote = rigNeedsProbes and "No probes on track"
              or (why or "No probes on this track.")
    return
  end
  rig = found
  -- One probe is a supported setup, not a fault -- output spectrum,
  -- output waveform, gain reduction and collisions all work from it. Said
  -- quietly so it is clear WHY there is no response curve, rather than
  -- leaving that to be worked out.
  if rig.single then rigNote = "output only -- one probe on this track" end
  -- Reduction comes from whatever between the probes reports it, by
  -- whichever route that plugin offers: REAPER's own GainReduction_dB
  -- where the plugin reports properly (decibels, no calibration), a
  -- reduction parameter plus a measured law where it does not, and the
  -- probes when neither exists.
  rigSources, rigOutside = Strip.reductionSources(rigTrack, rig.chain,
                 rig.pre and rig.pre.idx or -1,
                 rig.post and rig.post.idx or -1)

  rigLag = chainLatency(rigTrack, rig)
  lagCheckedAt = 0          -- the sources' own delays, on the next frame

  -- Only the VST3 route is drawn. It reports decibels directly, so there is
  -- no law to calibrate, no staleness to detect and nothing to hold through
  -- -- which is where every fault in the parameter-meter path came from. A
  -- plugin that only fakes a reduction parameter is listed but not drawn.
  --
  -- NAMING THE BAR
  --   One bar showing one thing is gain reduction, so it says GR. It used
  --   to take an initial from the plugin's name, which is why a single
  --   Pro-C 3 appeared as "P" -- a letter that told you nothing you did not
  --   already know from the track. Initials are only worth having when
  --   there are two sources to tell apart, so that is the only case that
  --   gets them.
  local nUsable = 0
  for _, s in ipairs(rigSources) do
    -- Reported in decibels, or measured by a probe tap: both are drawn.
    -- A tap is an estimate, and said so wherever it is shown.
    s.usable = (s.route and (s.route.kind == "named" or s.route.kind == "tap")) or false
    s.est = (s.route and s.route.kind == "tap") or false
    if s.usable then nUsable = nUsable + 1 end
  end

  local usedTags = {}
  for n, s in ipairs(rigSources) do
    if nUsable <= 1 then
      s.tag = "GR"
    else
      local name = s.plugin:gsub("^%a+%d*:%s*", "")
      local tag
      for ch in name:gmatch("%a") do
        local up = ch:upper()
        if not usedTags[up] then tag = up break end
      end
      tag = tag or tostring(n)
      usedTags[tag] = true
      s.tag = tag
    end
  end

  lock = {}
  TA.arm(rig)
  applyAnalysis(true)

  -- NOTHING IS WRITING THE PRE REGION, SO EMPTY IT.
  --
  --   Disarming a probe stops it writing; it does not clear what it
  --   wrote. On a one-probe track the pre region therefore still held the
  --   last two-probe track's spectrum and scope ring -- frozen, and drawn
  --   as though it belonged to the track in front of you.
  --
  --   Guarding each drawing site on rig.pre fixed the ones I could find,
  --   which is the weaker fix: it leaves live-looking stale data sitting
  --   in shared memory for the next reader to trip over. Clearing the
  --   region at the source means every consumer -- the spectrum, the
  --   scope, the response, and anything added later -- sees "no data"
  --   because there is none, rather than because it remembered to ask.
  --
  --   Safe to write: by definition no probe is publishing here.
  if not rig.pre then
    r.gmem_write(G.PRE_BASE + G.H_BANDN, 0)   -- the spectrum stops reading
    r.gmem_write(G.PRE_BASE + G.H_COLS,  0)   -- and so does the scope ring
    r.gmem_write(G.PRE_BASE + G.H_CUR,   0)
    r.gmem_write(G.PRE_BASE + G.H_SEQ,   0)
    r.gmem_write(G.PRE_BASE + G.H_AVGN,  0)
    for i = 0, 255 do
      local b = G.PRE_BASE + G.OFF_BAND + i * G.BAND_STRIDE
      r.gmem_write(b, -180) ; r.gmem_write(b + 1, -240)
    end
  end
  -- Resyncing restarts both probes and throws away the ring, so only do it
  -- when the probes are genuinely different from the ones already running.
  local samePair = keepPre and keepPost
                   and rig.pre and rig.post
                   and rig.pre.idx == keepPre and rig.post.idx == keepPost
  if not samePair then TA.resync() end
end

local function followTrack()
  local tr = r.GetSelectedTrack(0, 0)
  local now = r.time_precise()

  if tr ~= rigTrack then
    if rig then TA.disarm(rig) end
    setUpRig(tr)
    chainSig   = signatureOf(tr)
    lastChange = r.GetProjectStateChangeCount(0)
    nextScan   = now + 1.0
    return
  end

  local cnt = r.GetProjectStateChangeCount(0)
  if cnt == lastChange then return end      -- nothing has happened at all
  if now < nextScan then return end         -- and at most once a second
  lastChange, nextScan = cnt, now + 1.0

  local sig = signatureOf(tr)
  if sig == chainSig then return end        -- a knob moved, not the chain
  chainSig = sig

  -- The probes themselves usually have not moved, so the audio history is
  -- still valid and there is no reason to blank the display.
  local oldPre  = rig and rig.pre  and rig.pre.idx
  local oldPost = rig and rig.post and rig.post.idx
  if rig then TA.disarm(rig) end
  setUpRig(tr, oldPre, oldPost)
end

----------------------------------------------------------
-- the response
--
-- It used to be built from a MODEL: every module, every band and every
-- control law of InfiniStrip measured by hand, so the panel could draw
-- each band's own contribution. That model is real and it is accurate --
-- the archived TA_*_Model scripts still hold it -- but it was unbounded
-- work, because every new module, insert slot and channel strip started
-- again from nothing, and every gap in it showed on screen as a confident
-- curve that was quietly wrong.
--
-- The probe pair measures the real response instead. See drawPanel1.
----------------------------------------------------------

-- Set by the drawing code when the probes are older than this panel: they
-- are the ones that compute the response now, so a stale JSFX shows as a
-- missing curve and nothing else, which would be a puzzle rather than a
-- message.
local probeTooOld = false

-- The response is a 1.5 second running average by the time it reaches here,
-- so rebuilding its point list thirty times a second buys nothing: it is
-- the same curve six times over. The DRAWING still happens every frame --
-- ImGui is immediate mode, there is no way around that -- but the reads and
-- the arithmetic behind it run at ten hertz. The spectrum is left at full
-- rate, because that one you actually watch move.
local CURVE_HZ = 10
local curveCache = { t = -1, xs = {}, sums = {}, ok = {}, n = 0, peak = 0,
                     mean = nil, lo = 0, hi = 0 }

----------------------------------------------------------
-- the masking overlay
--
-- Recomputed at the same ten hertz as the response, and for the same
-- reason: it is built from running averages, so doing it every frame
-- produces the same answer three times over.
--
-- BOTH TRACKS ARE READ AT ONE INSTANT, IN LUA, rather than each probe
-- reading the other's region in the DSP. Two probes on ONE track share an
-- audio thread and a block boundary, which is what makes post-minus-pre a
-- valid magnitude response. Two separate tracks do not: REAPER renders
-- independent tracks in parallel, in no guaranteed order, with their own
-- delay compensation, so a cross-track read in the DSP would pick up
-- whichever block the other track last happened to finish. For a slow
-- perceptual statistic the error would be small -- and it would vary
-- frame to frame for no visible reason, which is the kind of thing that
-- cannot be debugged.
----------------------------------------------------------

local MC = {
  t = -1,            -- last computed
  grid = nil, sf = nil, spreadAt = nil,
  Ea = {}, Eb = {},  -- excitations, dB
  depth = {},        -- masking depth per ERB band, dB, 0 where clear
  active = false,    -- is there anything to show
  why = nil,         -- and if not, why not, in words
  peak = 0, peakHz = 0, nBands = 0,
  -- Reused, so the scratch buffer Mask.collide keeps inside it is
  -- allocated once rather than ten times a second.
  opt = { offsetDb = 6, floorDb = -60, marginDb = 0 },
}

local function clearMask()
  MC.active, MC.peak, MC.peakHz, MC.nBands = false, 0, 0, 0
  for i = 1, #MC.depth do MC.depth[i] = 0 end
end

local function updateMask()
  local nowT = r.time_precise()
  if nowT - MC.t < 1 / CURVE_HZ then return end
  MC.t = nowT

  if not S.showMask then MC.why = nil ; clearMask() ; return end
  if not rig or not rig.post then MC.why = "no probe on this track" ; clearMask() ; return end
  if not cmpGuid or cmpGuid == "" then MC.why = "pick a track to compare with" ; clearMask() ; return end
  if not cmpTrack then MC.why = "the comparison track is gone" ; clearMask() ; return end
  if cmpTrack == rigTrack then MC.why = "that is this track" ; clearMask() ; return end
  if not cmpRig then MC.why = "no probe on " .. cmpName ; clearMask() ; return end

  local nb = r.gmem_read(G.POST_BASE + G.H_BANDN)
  local lo = r.gmem_read(G.POST_BASE + G.H_BANDLO) or 20
  local hi = r.gmem_read(G.POST_BASE + G.H_BANDHI) or 20000
  if not nb or nb < 8 or hi <= lo then
    MC.why = "the probes are not publishing yet" ; clearMask() ; return
  end

  -- A comparison probe that has not started writing yet is a blank region
  -- reading as digital silence, which would look like "nothing masks you"
  -- rather than "not ready". The band count is written by every armed
  -- probe, so it doubles as the readiness flag.
  local cnb = r.gmem_read(G.CMP_BASE + G.H_BANDN)
  if not cnb or cnb < 8 then
    MC.why = cmpName .. " is not publishing yet" ; clearMask() ; return
  end

  local gA = trackGainDb(rigTrack)
  local gB = trackGainDb(cmpTrack)
  if not gA then MC.why = "this track is muted"        ; clearMask() ; return end
  if not gB then MC.why = cmpName .. " is muted"       ; clearMask() ; return end

  MC.grid = Mask.grid(math.floor(nb), lo, hi)
  if MC.spreadAt ~= S.maskSpread or not MC.sf then
    MC.sf, MC.spreadAt = Mask.spreading(MC.grid, S.maskSpread), S.maskSpread
  end

  -- Field 1 is the band's mean POWER in dB, which is the one to compare.
  -- Field 0 is the ballistic display level -- it has an attack and a
  -- release on it, and masking is not a peak phenomenon.
  Mask.excitation(MC.grid, function(i)
    return r.gmem_read(G.POST_BASE + G.OFF_BAND + i * G.BAND_STRIDE + 1)
  end, gA, MC.Ea)
  Mask.excitation(MC.grid, function(i)
    return r.gmem_read(G.CMP_BASE + G.OFF_BAND + i * G.BAND_STRIDE + 1)
  end, gB, MC.Eb)

  MC.opt.offsetDb = S.maskOffset
  MC.opt.floorDb  = S.maskFloor
  MC.opt.marginDb = S.maskMargin
  Mask.collide(MC.grid, MC.sf, MC.Ea, MC.Eb, MC.opt, MC.depth)

  local peak, peakHz, n = 0, 0, 0
  for b = 1, MC.grid.n do
    local d = MC.depth[b] or 0
    if d > 0 then
      n = n + 1
      if d > peak then peak, peakHz = d, MC.grid.hz[b] end
    end
  end
  MC.peak, MC.peakHz, MC.nBands = peak, peakHz, n
  MC.active = true
  MC.why = (n == 0) and "nothing masked" or nil
end

----------------------------------------------------------
-- drawing
----------------------------------------------------------

----------------------------------------------------------
-- scope history
--
-- The probes publish a min/max/RMS triple every 2 ms into a ring. Reading
-- the whole ring every frame would be 24,000 gmem reads; instead only the
-- columns that have appeared since the last frame are pulled across, which
-- at 30 fps is about a hundred. The rest already sit in these tables.
----------------------------------------------------------

local scope = {
  pre  = { cols = {}, cur = -1, len = 0, sr = 48000, slice = 96 },
  post = { cols = {}, cur = -1, len = 0, sr = 48000, slice = 96 },
}

local function pumpScope(which, base)
  local sc = scope[which]
  local len = r.gmem_read(base + G.H_COLS)
  if not len or len < 16 then return end
  sc.len   = len
  sc.sr    = r.gmem_read(base + G.H_SRATE) or 48000
  sc.slice = math.max(1, r.gmem_read(base + G.H_SLICE) or 96)
  local cur = math.floor(r.gmem_read(base + G.H_CUR) or 0) % len
  if sc.cur < 0 then sc.cur = cur return end
  -- Zero unless the panel has asked for the filterbank, so this costs
  -- nothing at all when the measured trace is not on screen.
  local nbg = math.floor(r.gmem_read(base + G.H_GRBN) or 0)
  if nbg > G.GRB_N then nbg = G.GRB_N end
  sc.nbg = nbg
  local i, guard = sc.cur, 0
  while i ~= cur and guard < len do
    local b = base + G.OFF_SCOPE + i * 3
    local col = { r.gmem_read(b), r.gmem_read(b + 1), r.gmem_read(b + 2) }
    if nbg > 0 then
      local gb = base + G.OFF_GRB + i * G.GRB_N
      for q = 0, nbg - 1 do col[4 + q] = r.gmem_read(gb + q) end
    end
    sc.cols[i] = col
    i = (i + 1) % len
    guard = guard + 1
  end
  sc.cur = cur
end

-- Gain reduction only exists at frame rate: the meters are parameters, not
-- audio. So each frame's reading is written at whatever scope column is
-- current, and the gap since the last frame is filled by interpolation.
-- Fast limiter action is smoothed by that; slow compression is not.
local grHist, grLastCol, grLastVal = {}, nil, {}
-- Per series: the column where its value last actually changed, and what it
-- was. Needed to draw between two readings rather than at them.
local grChangeCol, grChangeVal = {}, {}
-- How often each series actually produces a new number, in columns. Used to
-- decide how far it is reasonable to interpolate, and shown in Settings so
-- the difference between a plugin that publishes at 16 Hz and one that
-- publishes at 1 Hz is a number rather than an impression.
local grGapEma = {}

-- THE MODULE METERS ARE GONE, AND WITH THEM THEIR MACHINERY.
--   Reading InfiniStrip's per-module Gate / Comp / Lim meters needed a
--   measured law per module, a staleness test (seventy per cent of reads
--   came back as an identical idle tuple), and a timed hold to bridge the
--   stale runs. Every one of those was a source of error in turn: a
--   calibration right for one module and wrong for another, a hold that
--   plateaued, a staleness test that never released.
--
--   The VST3 route needs none of it. It answers in decibels, it answered
--   on every one of 159 logged samples, and it is what the bars draw. So
--   the laws, the hold, the staleness test and the three module series
--   have all been taken out rather than left switched off.
local GRsrc = {}

-- PEAK HOLD, the same law ChannelView uses so the two read alike:
-- instant rise, hold, then a linear fall. A peak that decays
-- exponentially never quite arrives anywhere, and "how much did that just
-- pull down" is a number you want to be able to read off, not chase.
local GR_HOLD = 1.2    -- seconds the held peak sits before it starts to fall
local GR_FALL = 18     -- dB per second once it is released

local grPeaks = {}

local function grPeak(key, db, now)
  local p = grPeaks[key]
  if not p then p = { v = 0, t = now } ; grPeaks[key] = p end
  if db >= p.v then
    p.v, p.t = db, now
  elseif now - p.t > GR_HOLD then
    p.v = math.max(db, p.v - GR_FALL * (now - p.t - GR_HOLD))
    -- Wind the clock back to the end of the hold rather than to now, so
    -- the fall stays linear in real time instead of slowing down as the
    -- frame rate varies.
    p.t = now - GR_HOLD
  end
  return p.v
end

-- A frozen picture of a track you are no longer looking at is worse than
-- an empty one: it invites you to read it.
function clearState(keepAudio)
  if not keepAudio then
    for _, k in ipairs({ "pre", "post" }) do
      scope[k].cols = {} ; scope[k].cur = -1 ; scope[k].len = 0
    end
  end
  grHist, grLastCol, grLastVal = {}, nil, {}
  grChangeCol, grChangeVal, grGapEma = {}, {}, {}
  GRsrc = {}
  grPeaks = {}
  rigSources, rigOutside = {}, {}
end

local function updateGR()
  for i, s in ipairs(rigSources) do
    -- A bypassed plugin keeps reporting whatever it was doing when you
    -- switched it off, and so does REAPER's own meter.
    s.active = Strip.fxActive(rigTrack, s.fx, s.parent)

    local db = 0
    if s.usable and s.active then
      db = Strip.readReduction(rigTrack, s.fx, s.route, s.law)
      -- The route answered on every one of 159 logged samples. If it ever
      -- does not, the previous value is better than a hole, but there is
      -- no timed hold and no staleness test: this path does not need one.
      if db == nil then db = GRsrc[i] or 0 end
    end
    GRsrc[i] = db
  end
  for i = #rigSources + 1, #GRsrc do GRsrc[i] = nil end
end

-- True when any source REPORTS its reduction (rather than being measured
-- by a probe tap): those are the ones the span trace is drawn for.
local function anyReported()
  for _, src in ipairs(rigSources) do
    if src.usable and not src.est then return true end
  end
  return false
end
local function anyTap()
  for _, src in ipairs(rigSources) do
    if src.usable and src.est then return true end
  end
  return false
end
local rigFitA = nil   -- the last span-to-report scale, for Settings

local function pumpGR()
  local sc = scope.post
  if sc.cur < 0 or sc.len < 16 then return end

  -- One series per reduction source, in the order the bars are built.
  local v = {}
  for i = 1, #rigSources do v[i] = GRsrc[i] or 0 end
  if #v == 0 then return end

  local cur = sc.cur

  -- WHY THE TRACE WAS A STAIRCASE
  --
  -- There used to be two passes here and they fought each other.
  --
  --   The first wrote a HOLD across every column since the last frame --
  --   the previous reading, repeated. That is a flat run followed by a
  --   vertical jump, i.e. a staircase, and it was written every frame.
  --
  --   The second tried to undo it: when a value CHANGED, it went back and
  --   replaced the flat run with a ramp -- but only if the run was shorter
  --   than a learned cap. Measured on Pro-C 3, the readings arrive about
  --   18 times a second against a frame rate near 30, so most frames see
  --   no change at all and the hold is what stays on screen. The ramp only
  --   sometimes caught up, and only sometimes was allowed to.
  --
  -- One pass replaces both. Each frame reads the value once; that reading
  -- and the previous one are two samples of a continuous quantity, and the
  -- straight line between them is the best estimate of what happened in
  -- between. So every column since the last frame is filled with that
  -- line, unconditionally. No change detection, no learned cap, nothing to
  -- disagree with itself -- and no lag, because the newest column is still
  -- the newest reading.
  --
  -- The one limit left is a plain sanity bound: half a second. A longer
  -- gap than that means the panel was not running -- the window was shut,
  -- the track changed, a frame took a second -- and joining across it
  -- would draw a ramp through time that was never observed.
  local colsPerSec = sc.sr / math.max(1, sc.slice)
  local MAX_BRIDGE = math.floor(0.5 * colsPerSec)

  local span = grLastCol and ((cur - grLastCol) % sc.len) or 0

  if grLastCol and span > 0 and span <= MAX_BRIDGE then
    local i, k = grLastCol, 0
    while k <= span do
      local row = grHist[i] or {}
      for j = 1, #v do
        local a = grLastVal[j] or v[j]
        row[j] = a + (v[j] - a) * (k / span)
      end
      grHist[i] = row
      i = (i + 1) % sc.len
      k = k + 1
    end
  else
    -- Nothing to join to. Stamp this reading and start again from here.
    local row = grHist[cur] or {}
    for j = 1, #v do row[j] = v[j] end
    grHist[cur] = row
  end

  -- HOW OFTEN THE PLUGIN ACTUALLY PRODUCES A NEW NUMBER.
  --   Kept only as a statistic now -- it decides nothing about the
  --   drawing. It is what told us Pro-C reports at about 18 Hz rather
  --   than at frame rate, which is worth being able to see.
  for j = 1, #v do
    local prev = grChangeVal[j]
    if prev == nil then
      grChangeVal[j], grChangeCol[j] = v[j], cur
    elseif math.abs(v[j] - prev) > 1e-9 then
      local gap = (cur - grChangeCol[j]) % sc.len
      local ema = grGapEma[j]
      grGapEma[j] = ema and (ema * 0.8 + gap * 0.2) or gap
      grChangeVal[j], grChangeCol[j] = v[j], cur
    end
  end

  -- TAP SOURCES DON'T NEED THE LINE.
  --   A plugin measured by a probe tap has its reduction written by the
  --   post probe once per scope column, on the scope's own clock (see
  --   TS_TrackProbe.jsfx). So those columns are real readings, 500 a
  --   second, and they replace the interpolation between frame readings
  --   above -- the trace for a measured plugin is sharper than for a
  --   reported one, not blurrier.
  if grLastCol and span > 0 and span <= MAX_BRIDGE then
    for j, src in ipairs(rigSources) do
      if src.est and src.route and src.route.index then
        local tb = TAP_TRACE + (src.route.index - 1) * TAP_COLS
        local i, k = grLastCol, 0
        while k <= span do
          local row = grHist[i] or {}
          row[j] = r.gmem_read(tb + (i % TAP_COLS)) or row[j]
          grHist[i] = row
          i = (i + 1) % sc.len
          k = k + 1
        end
      end
    end
  end

  grLastCol, grLastVal = cur, v
end

----------------------------------------------------------
-- panel 1 -- spectrum and the EQ curve
----------------------------------------------------------

local function drawPanel1(dl, x0, y0, w, h)
  -- Everything below walks one pixel column at a time. A docker mid-relayout
  -- can hand over a width that is nonsense for a frame, and a loop from x0
  -- to a nonsense x1 is not a glitch, it is REAPER stopping. Cheap insurance.
  if not (w == w) or not (h == h) or w < 8 or h < 8 or w > 8192 or h > 8192 then
    return
  end
  local x1, y1 = x0 + w, y0 + h
  ImGui.DrawList_AddRectFilled(dl, x0, y0, x1, y1, COL.bg, 4)
  ImGui.DrawList_PushClipRect(dl, x0, y0, x1, y1, true)

  ---------------------------------------------------- frequency grid
  local marks = { 20, 30, 50, 100, 200, 300, 500, 1000, 2000, 3000, 5000, 10000, 20000 }
  local named = { [20] = "20", [100] = "100", [1000] = "1k", [10000] = "10k" }
  for _, f in ipairs(marks) do
    local x = fx(f, x0, w)
    ImGui.DrawList_AddLine(dl, x, y0, x, y1, named[f] and COL.gridStr or COL.grid)
    if named[f] then ImGui.DrawList_AddText(dl, x + 3, y1 - 14, COL.textDim, named[f]) end
  end

  ---------------------------------------------------- spectrum
  -- Every pixel column gets a value. Where the column spans one or more
  -- bins we take the loudest, so narrow peaks survive; where it spans less
  -- than a bin -- which below about 1 kHz is most of them, since a 2048
  -- point FFT is 23 Hz per bin -- we interpolate between neighbours
  -- instead of leaving a gap. Skipping those was what drew the picket
  -- fence.
  -- The probes now publish a log-spaced summary of their own spectrum, so
  -- this reads 256 points instead of 1024 bins and draws 256 spans instead
  -- of one per pixel column. Reducing bins to pixels was the panel's single
  -- largest per-frame cost and none of it needed to happen in Lua.
  -- The colour's own alpha is the fill; the outline sits a little above it,
  -- which is what lets the trace behind be found through the one in front.
  -- Two filled shapes at usable opacities are otherwise one shape.
  -- The post spectrum's outline is kept, because the collision overlay is
  -- drawn INTO that shape rather than over the top of it.
  local SP = { n = 0, x = {}, y = {}, lo = 20, hi = 20000 }

  local function drawSpectrum(base, col, keep)
    local fillA = alphaOf(col)
    local nb = r.gmem_read(base + G.H_BANDN)
    if not nb or nb < 8 then return end
    local lo = r.gmem_read(base + G.H_BANDLO) or 20
    local hi = r.gmem_read(base + G.H_BANDHI) or 20000
    if hi <= lo then return end
    local ratio = math.log(hi / lo)

    local top, bot = S.specTop, S.specBot
    local function yOf(v)
      local t = (v - bot) / (top - bot)
      return y1 - math.max(0, math.min(1, t)) * h
    end

    local sx, sy = keep and SP.x or {}, keep and SP.y or {}
    for i = 0, nb - 1 do
      sx[i + 1] = fx(lo * math.exp(ratio * (i + 0.5) / nb), x0, w)
      sy[i + 1] = yOf(r.gmem_read(base + G.OFF_BAND + i * G.BAND_STRIDE) or -180)
    end
    if keep then SP.n, SP.lo, SP.hi = nb, lo, hi end

    local fc = alpha(col, fillA)
    for i = 1, nb - 1 do
      ImGui.DrawList_AddQuadFilled(dl, sx[i], sy[i], sx[i + 1], sy[i + 1],
        sx[i + 1], y1, sx[i], y1, fc)
    end
    polyline(dl, sx, sy, 1, nb, edgeOf(col), 1.0)
  end

  SP.n = 0
  if rig then
    -- GATED ON THE PROBE EXISTING, not just on the checkbox.
    --
    --   A track with only ONE probe is a legitimate setup -- it gives the
    --   output spectrum, the output waveform and everything the collision
    --   overlay needs, for half the install. But disarming a probe stops
    --   it WRITING; it does not clear what it wrote. So on a single-probe
    --   track the pre region still held the last two-probe track's
    --   spectrum, frozen, and the panel drew it as though it belonged to
    --   the track you were looking at.
    --
    --   The response curve was already guarded this way. These two were
    --   not, which made the single-probe setup look broken when it is
    --   actually supported.
    if S.showPre and rig.pre then drawSpectrum(G.PRE_BASE, S.cSpecPre) end
    if S.showPost then drawSpectrum(G.POST_BASE, S.cSpecPost, true) end
  end

  ---------------------------------------------------- collisions
  -- THE RED IS PART OF THE SPECTRUM, NOT A CURTAIN OVER IT.
  --
  -- It used to be full-height columns. That was defensible -- masking is
  -- a property of a frequency region, not of a level, so any height is an
  -- invention -- but it reads as a separate object sitting in front of
  -- the display, and it buries the traces it is describing.
  --
  -- So it is drawn INTO the post spectrum's own silhouette: the same
  -- quads, in the same places, recoloured where that band is masked. The
  -- shape carries no extra meaning -- it is the shape already on screen --
  -- and the red now reads as "this part of the track is being covered"
  -- rather than as a band across the panel.
  --
  -- The top edge is stroked brighter over the same span. The contour is
  -- what the eye follows, and a lit contour says where far more precisely
  -- than a wash underneath it can.
  if S.showMask and MC.active and MC.grid and MC.nBands > 0 and SP.n > 8 and MC.grid.nSrc == SP.n then
    local g2, full = MC.grid, math.max(1, S.maskDepth)
    local baseA = alphaOf(S.cMask)
    local nb = SP.n

    -- One pass over the SOURCE bands, each coloured by the masking depth
    -- of the ERB band that owns it. The owner map already exists for the
    -- excitation sum, so no frequency has to be looked up twice.
    --
    -- THE CONTOUR HAS TO FADE WITH THE FILL.
    --
    --   It used to stroke a whole contiguous run of masked bands in one
    --   flat colour. The fill was per band and varied with depth; the
    --   contour did not, so a band masked by half a decibel wore the same
    --   bright red as one masked by fifteen, and the line ran at full
    --   strength across regions the fill had almost given up on. It read
    --   as a much larger and more confident finding than the measurement
    --   supports, which is the one thing an indicative overlay must not
    --   do.
    --
    --   Per-segment alpha is the fix, but a separate AddLine per band is
    --   256 marshalled calls a frame and this panel has been there
    --   before. So the depth is QUANTISED into a few levels and runs of
    --   equal level are packed into one polyline each -- typically a
    --   couple of dozen calls, and the banding is invisible because the
    --   fill underneath is already continuous.
    local LEVELS = 8
    local function levelOf(d)
      if d <= 0 then return 0 end
      local t = math.min(1, d / full)
      return math.max(1, math.floor(t * LEVELS + 0.5))
    end

    local runFrom, runLvl = nil, 0
    local function flushRun(upto)
      if runFrom and runLvl > 0 and upto > runFrom then
        local t = runLvl / LEVELS
        -- Same t the fill uses, lifted by the same proportion the contour
        -- was always lifted by. At full depth it is the bright edge; at a
        -- tenth of it, a tenth as present.
        polyline(dl, SP.x, SP.y, runFrom, upto,
          alpha(S.cMask, math.min(1, (baseA + 0.35) * t)), 1.6)
      end
      runFrom, runLvl = nil, 0
    end

    for i = 0, nb - 2 do
      local own = g2.owner[i]
      local d = own and MC.depth[own] or 0
      local k = i + 1
      if d > 0 then
        local t = math.min(1, d / full)
        ImGui.DrawList_AddQuadFilled(dl, SP.x[k], SP.y[k], SP.x[k + 1], SP.y[k + 1],
          SP.x[k + 1], y1, SP.x[k], y1, alpha(S.cMask, baseA * t))
      end
      if S.maskEdge then
        local lv = levelOf(d)
        if lv ~= runLvl then
          -- The run ends ON this point, not before it, so consecutive
          -- runs share a vertex and the contour has no gaps in it.
          flushRun(k)
          if lv > 0 then runFrom, runLvl = k, lv end
        end
      end
    end
    if S.maskEdge then flushRun(nb) end
  end

  ---------------------------------------------------- the measured response
  -- THE CURVE IS MEASURED, NOT MODELLED, AND IT IS NOT COMPUTED HERE.
  --
  -- Both probes take a running power average of their own spectrum on the
  -- same frames; post minus pre, per band, IS the magnitude response of
  -- whatever sits between them, checked against the stepped-tone models to
  -- 0.069 dB rms. The POST probe does that subtraction itself, on the log
  -- grid, and smooths it there -- so no parameter is read, no control law
  -- is fitted, and no module has to have been characterised first. It is
  -- right about bypass, mute, insert slots, saturation and plugins nobody
  -- has ever seen, because it looks at the audio.
  --
  -- What it cannot do is say which band did what. That is the trade.
  --
  -- Doing the arithmetic in the DSP is not only cheaper. Averaging a band
  -- of bins into one point is what stopped the curve looking like noise at
  -- the top end, where a per-bin difference showed every wobble in the
  -- average.
  local CC = curveCache
  if not (S.showCurve and rig and rig.pre and rig.post) then
    CC.n, CC.peak = 0, 0
  else
    local nowT = r.time_precise()
    -- Rebuilt on the clock, but also whenever the panel is resized or the
    -- gate is moved, so a drag does not lag behind the mouse.
    if nowT - CC.t > 1 / CURVE_HZ or CC.x0 ~= x0 or CC.w ~= w
       or CC.range ~= S.excRange then
      CC.t, CC.x0, CC.w, CC.range = nowT, x0, w, S.excRange
      CC.n, CC.peak = 0, 0
      local nb = r.gmem_read(G.POST_BASE + G.H_BANDN) or 0
      local nA = r.gmem_read(G.PRE_BASE + G.H_AVGN) or 0
      if nb < 8 then
        probeTooOld = true
      elseif nA >= 8 then
        probeTooOld = false
        local lo = r.gmem_read(G.POST_BASE + G.H_BANDLO) or 20
        local hi = r.gmem_read(G.POST_BASE + G.H_BANDHI) or 20000
        local ratio = math.log(hi / lo)

        -- BOTH ENDS HAVE TO BE MEASURABLE.
        --
        -- The gate used to look only at the excitation, which is the wrong
        -- half below a high-pass corner: there is plenty of signal going IN
        -- at 20 Hz and nothing at all coming out, so the ratio was the
        -- filter's stopband plus whatever noise the post probe had -- fifty
        -- and more decibels of a number that means nothing, and that number
        -- then dragged the levelling reference along with it. The post side
        -- now gets the same test as the pre side, and where it fails the
        -- curve breaks rather than reporting a noise floor as a filter slope.
        local postMax = -400
        for i = 0, nb - 1 do
          local pv = r.gmem_read(G.POST_BASE + G.OFF_BAND + i * G.BAND_STRIDE + 1)
          if pv and pv > postMax then postMax = pv end
        end
        local postGate = postMax - S.excRange

        for i = 0, nb - 1 do
          local k = i + 1
          CC.xs[k] = fx(lo * math.exp(ratio * (i + 0.5) / nb), x0, w)
          CC.sums[k], CC.ok[k] = 0, false
          local v = r.gmem_read(G.POST_BASE + G.OFF_BAND + i * G.BAND_STRIDE + 2)
          local e = r.gmem_read(G.POST_BASE + G.OFF_BAND + i * G.BAND_STRIDE + 3)
          -- A band is only drawn where BOTH probes have enough energy in
          -- it. In the gaps the curve breaks rather than inventing a number.
          local pv = r.gmem_read(G.POST_BASE + G.OFF_BAND + i * G.BAND_STRIDE + 1)
          if v and e and pv and v == v and e == e
             and e > -S.excRange and pv > postGate then
            CC.sums[k], CC.ok[k] = v, true
            if math.abs(v) > CC.peak then CC.peak = math.abs(v) end
          end
        end
        CC.n = nb - 1

        -- The broadband average of the curve, and its extremes. Reading
        -- "is this zero?" off a gridline is guesswork, and the first
        -- question of any measurement is whether it nulls: put a null
        -- chain between the probes and this must read 0.00.
        local sum, cnt = 0, 0
        CC.lo, CC.hi = 999, -999
        for i = 1, CC.n + 1 do
          if CC.ok[i] then
            sum = sum + CC.sums[i] ; cnt = cnt + 1
            if CC.sums[i] < CC.lo then CC.lo = CC.sums[i] end
            if CC.sums[i] > CC.hi then CC.hi = CC.sums[i] end
          end
        end
        CC.mean = cnt > 0 and (sum / cnt) or nil

        -- THE REFERENCE IS A MEDIAN, NOT A MEAN.
        --
        -- A high-pass takes the bottom two octaves down by more than fifty
        -- decibels, and a handful of bands sitting at -55 drag an average
        -- a long way: the curve then floats up bodily and the mid-band --
        -- the part you are actually reading -- ends up nowhere near zero.
        -- A median does not care how deep the tails go, only how many
        -- bands are in them, so the reference stays where the music is.
        local vals = {}
        for i = 1, CC.n + 1 do
          if CC.ok[i] then vals[#vals + 1] = CC.sums[i] end
        end
        if #vals > 0 then
          table.sort(vals)
          local m = #vals
          CC.ref = (m % 2 == 1) and vals[(m + 1) // 2]
                   or (vals[m // 2] + vals[m // 2 + 1]) * 0.5
        else
          CC.ref = nil
        end

        -- A compressor's whole effect on this curve is broadband: it pulls
        -- the level down without changing the shape, so the curve sits at
        -- minus-however-many decibels and the EQ you were trying to look at
        -- comes along for the ride. Levelling the curve against its own
        -- middle throws the gain away and keeps the shape.
        --
        -- Compensating from the plugin's REPORTED reduction was tried
        -- instead and dropped: it was indistinguishable from doing nothing
        -- on real material, which is what you would expect from sampling a
        -- millisecond-scale quantity thirty times a second.
        CC.shift = CC.ref and -CC.ref or nil

        if CC.shift then
          CC.peak, CC.lo, CC.hi = 0, 999, -999
          for i = 1, CC.n + 1 do
            if CC.ok[i] then
              CC.sums[i] = CC.sums[i] + CC.shift
              local v = CC.sums[i]
              if v < CC.lo then CC.lo = v end
              if v > CC.hi then CC.hi = v end
              if math.abs(v) > CC.peak then CC.peak = math.abs(v) end
            end
          end
        end
      end
    end
  end

  local xs, sums, ok = CC.xs, CC.sums, CC.ok
  local NPTS, peak = CC.n, CC.peak

  if S.autoScale then
    local want = 12
    for _, step in ipairs({ 12, 18, 24, 30, 36, 48 }) do
      want = step
      if peak <= step - 1 then break end
    end
    S.scaleDb = S.scaleDb + (want - S.scaleDb) * 0.15
  end
  local range = S.scaleDb
  local ymid  = y0 + h * 0.5
  local function fy(db) return ymid - (db / range) * (h * 0.5) end

  local stepDb = range <= 12 and 3 or (range <= 24 and 6 or 12)
  local d = stepDb
  while d < range do
    for _, sgn in ipairs({ 1, -1 }) do
      local y = fy(d * sgn)
      ImGui.DrawList_AddLine(dl, x0, y, x1, y, COL.grid)
      ImGui.DrawList_AddText(dl, x1 - 26, y - 7, COL.textDim, ("%+d"):format(d * sgn))
    end
    d = d + stepDb
  end
  ImGui.DrawList_AddLine(dl, x0, ymid, x1, ymid, COL.zeroLine)

  -- Fill and line are drawn only across spans where BOTH ends are usable,
  -- so a gap in the excitation shows as a gap rather than as a line ruled
  -- through it.
  if S.curveFill then
    for i = 1, NPTS do
      if ok[i] and ok[i + 1] then
        local v = sums[i]
        local strong = alpha(S.cCurve, alphaOf(S.cCurve) * math.min(1, math.abs(v) / 4 + 0.2))
        local fade   = alpha(S.cCurve, 0)
        local xa, xb = xs[i], xs[i + 1]
        local ya, yb = fy(v), ymid
        if v >= 0 then
          ImGui.DrawList_AddRectFilledMultiColor(dl, xa, ya, xb, yb, strong, strong, fade, fade)
        else
          ImGui.DrawList_AddRectFilledMultiColor(dl, xa, yb, xb, ya, fade, fade, strong, strong)
        end
      end
    end
  end

  -- One stroke per unbroken run, rather than one per point. Where the
  -- excitation gives out the run ends and the next one starts, so a gap
  -- still reads as a gap.
  if NPTS > 0 then
    local ys = {}
    for i = 1, NPTS + 1 do ys[i] = fy(sums[i]) end
    local runStart = nil
    for i = 1, NPTS + 2 do
      if i <= NPTS + 1 and ok[i] then
        runStart = runStart or i
      elseif runStart then
        -- 1.1, near enough to the 0.9 the per-band contributor lines used
        -- to be drawn at. At 2.0 it read as a bar rather than a curve.
        polyline(dl, xs, ys, runStart, i - 1, S.cCurve, 1.1)
        runStart = nil
      end
    end
  end

  ImGui.DrawList_AddText(dl, x1 - 30, y0 + 4, COL.textDim, ("%+d"):format(math.floor(range)))

  ImGui.DrawList_AddText(dl, x1 - 118, y1 - 15, COL.textDim,
    ("floor %d dB  (wheel)"):format(math.floor(S.specBot)))
  ImGui.DrawList_PopClipRect(dl)
end

----------------------------------------------------------
-- panel 2 -- dynamics
--
-- One overlay, not two panels: the untouched signal in grey behind, the
-- processed one in front. Gain reduction hangs from the top edge on its
-- own scale, gate blue, compressor yellow, limiter red, each a thin line
-- with the same gradient fill as the EQ bands. The three bars on the right
-- are the same three numbers as a level.
----------------------------------------------------------

local function drawPanel2(dl, x0, y0, w, h)
  -- Everything below walks one pixel column at a time. A docker mid-relayout
  -- can hand over a width that is nonsense for a frame, and a loop from x0
  -- to a nonsense x1 is not a glitch, it is REAPER stopping. Cheap insurance.
  if not (w == w) or not (h == h) or w < 8 or h < 8 or w > 8192 or h > 8192 then
    return
  end
  -- Build the bars first, because how many there are decides the width.
  -- The total always exists -- Pro-C 3 has no per-module split and would
  -- otherwise leave three empty bars labelled for a strip it is not.
  local labels, cols, vals = {}, {}, {}
  local function bar(lab, col, v)
    labels[#labels + 1] = lab ; cols[#cols + 1] = col ; vals[#vals + 1] = v
  end
  -- One entry per SOURCE. A plugin that breaks its reduction down shows
  -- the breakdown -- that is the useful information, and a total beside it
  -- is the same reduction counted twice. A plugin that does not, shows its
  -- own total. Two plugins between the probes therefore contribute
  -- separately instead of one suppressing the other.
  -- The meter and the trace are separate things wanting separate
  -- switches: the bar says how much right now, the trace says what the
  -- shape of it was, and there are plenty of times you want one without
  -- the other cluttering the waveform.
  local series = {}
  local anyUsable = false
  local nUse, grTotal = 0, 0
  -- Two sources of the same kind would be two bars and two traces in one
  -- colour. The second and third of a kind are drawn paler -- the same
  -- hue, so "reported" and "measured" still read at a glance -- and each
  -- bar matches its trace.
  local function paler(c, f)
    local function ch(sh) local v = (c >> sh) & 0xFF ; return math.floor(v + (255 - v) * f + 0.5) end
    return (ch(24) << 24) | (ch(16) << 16) | (ch(8) << 8) | (c & 0xFF)
  end
  local nthRep, nthMeas = 0, 0
  for i, src in ipairs(rigSources) do
    if src.usable then
      anyUsable = true
      nUse = nUse + 1
      grTotal = grTotal + (GRsrc[i] or 0)
      -- A measured source in its own colour: an estimate, not a report.
      local col
      if src.est then nthMeas = nthMeas + 1 ; col = paler(S.cGRMeas, (nthMeas - 1) * 0.3)
      else nthRep = nthRep + 1 ; col = paler(S.cGR, (nthRep - 1) * 0.3) end
      if S.showGR then bar(src.tag or "GR", col, GRsrc[i]) end
      if S.showGRTrace then series[#series + 1] = { i, col } end
    end
  end
  -- The track's whole reduction, when more than one thing contributes:
  -- compressors in series multiply, so their decibels add.
  if S.showGR and nUse > 1 then
    local allMeas = true
    for _, src in ipairs(rigSources) do
      if src.usable and not src.est then allMeas = false end
    end
    bar("\u{03A3}", allMeas and S.cGRMeas or S.cGR, grTotal)
  end

  -- THE TAG IS GONE, and the column is the better for it. It cost twelve
  -- pixels at the top -- which is precisely the twelve pixels that made
  -- the meter's scale disagree with the trace's -- to print a word that
  -- only ever said what the panel it sits in already says.
  --
  -- The column is now as wide as the held figure needs and no wider; the
  -- bar itself is narrower than that and centred in it.
  -- The bar fills its column and the column sits almost against the panel
  -- edge: no centring slack, no gap to the waveform, and three pixels of
  -- inset on the right.
  --
  -- Those three pixels are not decoration. The held figure is about
  -- twenty pixels wide and the column is twelve, so it has to overhang
  -- its bar. Centred, it overhung BOTH ways and the right-hand end fell
  -- outside the clip rect -- which is why "8.2" arrived as "8.". It is
  -- right-aligned to the bar now and overhangs only to the left, onto
  -- the waveform, where there is room for it.
  local BAR_W    = 12
  local RIGHT_PAD = 3
  local BARW  = (#labels > 0) and (BAR_W * #labels) or 0
  local gx0  = x0 + w - BARW - ((#labels > 0) and RIGHT_PAD or 0)
  local x1, y1 = gx0, y0 + h
  ImGui.DrawList_AddRectFilled(dl, x0, y0, x0 + w, y1, COL.bg, 4)
  ImGui.DrawList_PushClipRect(dl, x0, y0, x0 + w, y1, true)

  local sc = scope.post
  local ok = sc.len >= 16 and sc.cur >= 0
  local wv = x1 - x0

  ---------------------------------------------------- time axis
  --
  -- Three ways to decide how much time is on screen. Free is the wheel.
  -- Milliseconds is a fixed window, for looking at attack shapes. Beats
  -- asks the project what the tempo is, so the window is musical rather
  -- than arbitrary -- and with beat lock on, the right edge is pinned to
  -- the last beat boundary, so the picture steps a beat at a time instead
  -- of sliding, and the same part of the bar lands in the same place every
  -- time round.
  local total, newest, oldest, colsPerSec = 0, 0, 0, 1
  local beatSec = nil
  if ok then
    colsPerSec = sc.sr / sc.slice

    if S.timeMode == 2 then
      S.histSec = S.windowMs / 1000
    elseif S.timeMode == 3 then
      local bpm = r.Master_GetTempo()
      if bpm and bpm > 1 then
        beatSec = 60 / bpm
        S.histSec = S.windowBeats * beatSec
      end
    end

    total  = math.min(sc.len - 2, math.floor(S.histSec * colsPerSec))
    newest = sc.cur

    -- THE TRIGGER
    --   The first version derived the right edge every frame from the play
    --   position, and shuddered: the play clock and the probe's column
    --   counter are sampled at different instants, so their difference
    --   jittered by a frame's worth of columns -- about 16, which at a two
    --   second window is 16 pixels of wobble every frame.
    --
    --   A scope does not work that way. It arms once and then free-runs on
    --   its own counter. So the anchor is set from the play position when
    --   it is first needed, and after that it advances in whole steps of
    --   the column counter alone. Nothing to disagree with.
    local step = nil
    if S.beatLock then
      if S.timeMode == 3 and beatSec then step = beatSec * colsPerSec
      elseif S.timeMode == 2 then step = S.histSec * colsPerSec end
    end

    if step and step >= 1 then
      if lock.step ~= step or not lock.anchor or lock.len ~= sc.len then
        lock.step, lock.len = step, sc.len
        lock.anchor = sc.cur
        -- Align to the music where the transport can say where that is.
        if S.timeMode == 3 and beatSec and (r.GetPlayState() & 1) == 1 then
          local qn = r.TimeMap2_timeToQN(0, r.GetPlayPosition())
          local frac = qn - math.floor(qn)
          lock.anchor = sc.cur - frac * beatSec * colsPerSec
        end
      end
      local guard = 0
      while ((sc.cur - lock.anchor) % sc.len) >= step and guard < 256 do
        lock.anchor = lock.anchor + step
        guard = guard + 1
      end
      if lock.anchor > sc.len then lock.anchor = lock.anchor % sc.len end
      newest = math.floor(lock.anchor) % sc.len
    else
      lock.anchor = nil
    end

    oldest = (newest - total) % sc.len
  end

  local ymid = y0 + h * 0.5
  ImGui.DrawList_AddLine(dl, x0, ymid, x1, ymid, COL.grid)

  if S.timeMode == 3 and beatSec and total >= 4 then
    local perBeat = wv / math.max(1, S.windowBeats)
    for b = 0, S.windowBeats do
      local bx = x1 - b * perBeat
      if bx >= x0 then
        ImGui.DrawList_AddLine(dl, bx, y0, bx, y1,
          (b % 4 == 0) and COL.gridStr or COL.grid)
      end
    end
  end

  ---------------------------------------------------- waveform
  local function drawWave(sc2, col, a)
    if not ok or total < 4 then return end
    local lo, hi = {}, {}
    for k = 0, total - 1 do
      local c = sc2.cols[(oldest + k) % sc2.len]
      if c then
        local px = math.floor(x0 + (k / total) * wv)
        if not lo[px] or c[1] < lo[px] then lo[px] = c[1] end
        if not hi[px] or c[2] > hi[px] then hi[px] = c[2] end
      end
    end
    -- The waveform is a band between a minimum and a maximum path, which
    -- is one closed polygon: out along the top, back along the bottom.
    -- It used to be a quad per pixel column, six hundred calls a frame
    -- for each of the two waveforms.
    local half = h * 0.5 * 0.92
    local wx, wt, wb, n = {}, {}, {}, 0
    for px = math.floor(x0), math.floor(x1) do
      if lo[px] then
        n = n + 1
        wx[n] = px
        wb[n] = ymid - math.max(-1, math.min(1, lo[px])) * half
        wt[n] = ymid - math.max(-1, math.min(1, hi[px])) * half
      end
    end
    if n < 2 then return end
    local fc = alpha(col, a)
    for i = 1, n - 1 do
      ImGui.DrawList_AddQuadFilled(dl, wx[i], wt[i], wx[i + 1], wt[i + 1],
        wx[i + 1], wb[i + 1], wx[i], wb[i], fc)
    end
  end

  -- Same reason as the pre spectrum: the ring stops being filled when
  -- there is no pre probe, it does not empty.
  if S.showPreWave and rig and rig.pre then
    drawWave(scope.pre, S.cWavePre, 0.55)
  end
  drawWave(scope.post, S.cWavePost, 0.80)

  ---------------------------------------------------- gain reduction
  local grRange = S.grRange
  local function yGR(db) return y0 + math.max(0, math.min(1, db / grRange)) * h end

  -- THE CURTAIN
  --   One series per reduction source, from what each plugin reports to
  --   the host, so this works with any compliant plugin rather than only
  --   with InfiniStrip's module meters. Measured 2026-08-31: the
  --   host-facing readout is bit-identical to the module meter, so nothing
  --   was lost by dropping the per-module split.
  --
  --   The probe-derived version of this went with it. What the two probes
  --   bracket is the whole span, so pre-minus-post is the compressor AND
  --   the limiter AND the EQ together, moving with the signal's spectrum
  --   from moment to moment -- a different quantity wearing the same
  --   name, and it showed no meaningful difference from the measured
  --   figure when both were on screen.
  -- HOW THE TRACE IS SAMPLED, AND WHY IT LOOKED COARSE
  --
  --   It used to read ONE column per pixel -- k = (px - x0) / w * total --
  --   and with a four second window that is 2000 columns across about 840
  --   pixels, so more than half of them were skipped. Which one a pixel
  --   landed on shifted as the ring advanced, so the trace shimmered
  --   between neighbouring readings instead of holding still.
  --
  --   And a column with no reading in it was drawn as `or 0`, i.e. at the
  --   top of the axis, meaning no reduction at all. Every gap in the ring
  --   -- the wrap, a dropped frame, the columns ahead of the write cursor
  --   -- became a spike to zero and back.
  --
  --   Both are fixed the same way the waveform already handles it: a pixel
  --   covers every column it spans and keeps the DEEPEST reduction in
  --   them, and a column with nothing in it holds the last real value
  --   rather than inventing a zero.
  -- MEASURED FROM THE PROBES, WHEN THAT IS WHAT YOU ASKED FOR.
  --
  --   GainReduction_dB is a plugin PARAMETER, so it arrives only when the
  --   script runs -- measured on Pro-C at about 18 readings a second.
  --   The plugin draws its own trace from its internal envelope at audio
  --   rate, which is why side by side ours looks like a cartoon of it.
  --   No amount of interpolation invents the detail back.
  --
  --   The probes do have it. They publish min/max/RMS every 2 ms, so
  --   post-RMS over pre-RMS is the gain change across the span at 500
  --   readings a second -- twenty-eight times the parameter route, and
  --   the same order as the plugin's own display.
  --
  --   WHAT IT COSTS: it is the whole span, not one plugin, so an EQ
  --   between the probes moves it too. And with makeup or auto gain on --
  --   as it is in Pro-C by default -- the absolute figure is meaningless,
  --   because the plugin gives back what it took. So this is drawn as
  --   SHAPE: the least-reducing moment in the visible window is the zero,
  --   and everything is measured down from there.
  --
  --   Which is the right division of labour. The meter reports the real
  --   decibels from the plugin, where 18 a second is plenty for a number
  --   you read. The trace shows the envelope, where resolution is the
  --   whole point.
  -- IT NEEDS SOMETHING TO ANCHOR TO, AND SOMETHING TO BE ABOUT.
  --
  --   post-RMS over pre-RMS is the gain change across the span, from any
  --   cause -- an EQ, a saturator, a fader inside the chain. It is gain
  --   REDUCTION only when a compressor dominates that change, and the
  --   panel cannot tell by looking.
  --
  --   Worse, with nothing reporting there is nothing to slide the shape
  --   onto, so the offset came out zero and the trace was drawn zeroed
  --   at the window's least-reducing moment -- swinging across the full
  --   scale and looking like heavy compression on a chain doing none.
  --
  --   So a reporting plugin is required. It is what makes the number
  --   mean decibels of reduction, and it is what puts the trace at the
  --   right height. Without one, nothing is drawn and the panel says so.
  -- WANTED versus GOT. These were one variable, and that was a hole: the
  -- reported trace was suppressed whenever the measured one was ASKED for,
  -- whether or not it turned out to have anything to draw. While the
  -- measured route was a broadband ratio it always had something, so the
  -- hole never opened. Now that it can legitimately come up empty -- a
  -- probe from before the filterbank, a window that has not filled yet --
  -- a chain with a compressor reporting perfectly well drew no trace at
  -- all and said nothing about why.
  local measuredDrew = false
  -- WHO DRAWS WHAT.
  --   A plugin measured by a probe tap draws its own series: 500 a
  --   second already, with a zero measured while stopped -- the same
  --   number its meter shows. The REPORTING plugins, at 18 a second, get
  --   one trace from the span between the probes with the taps' share
  --   taken out (below). Without a reporting plugin there is no span trace.
  local measured = (S.grTraceSrc == 2) and anyReported()
                   and rig and rig.pre and rig.post
  if S.showGRTrace and measured and ok and total >= 4 then
    local pre = scope.pre
    local px0, px1 = math.floor(x0), math.floor(x1)
    local span = math.max(1, px1 - px0)
    -- Ratios, not decibels, in the inner loop: one logarithm per PIXEL at
    -- the end instead of one per column, which is 840 rather than 2000
    -- and does not grow when you zoom out.
    -- A LEVEL GATE, BECAUSE A RATIO OF TWO SMALL NUMBERS IS NOISE.
    --
    --   The only guard here was a[3] > 1e-7, which is -140 dBFS -- so in
    --   the gaps between notes the trace was dividing one noise floor by
    --   another and drawing whatever came out. On quiet material that is
    --   a spike to the bottom of the scale on every gap.
    --
    --   Two thresholds, because one will not do. An absolute floor, since
    --   below about -70 dBFS there is no signal to take a ratio of. And a
    --   relative one, because a track riding at -50 has real gaps far
    --   above any fixed floor: anything more than 45 dB below the loudest
    --   moment in the window is not what the compressor is working on
    --   either.
    --
    --   Gated columns are HELD, not dropped to zero. A gap in the audio
    --   is not a moment of no gain reduction; it is a moment we cannot
    --   measure, and the honest thing is to carry the last real reading
    --   across it.
    --
    --   It matters for the height as well as the spikes: the offset that
    --   slides this onto the reported level is a mean, and garbage in the
    --   gaps drags the whole trace off.
    -- PER BAND, NOT BROADBAND.
    --
    --   This used to be post RMS over pre RMS. That is the span's LEVEL
    --   change, which equals its gain only while nothing in the span
    --   touches the spectrum -- and one EQ band is enough to break it. A
    --   static +6 dB at 100 Hz adds six decibels to the ratio through a
    --   bass note and nothing through a cymbal, so the EQ's contribution
    --   swings with the programme and lands on the trace looking exactly
    --   like compression. Against a true 13 dB reduction it drew 39 dB.
    --
    --   The bands come from the probes' own filterbank and the separation
    --   is done in TS_TA_GR.lua, where it can be tested. Both probes have
    --   to be publishing the same number of bands: a mismatch means one of
    --   them is an older build, and half a measurement is not one.
    local nbg  = math.floor(r.gmem_read(G.POST_BASE + G.H_GRBN) or 0)
    local pnbg = math.floor(r.gmem_read(G.PRE_BASE  + G.H_GRBN) or 0)
    local grOut, grLive = nil, 0
    if nbg >= 4 and pnbg == nbg then
      grOut, grLive = GR.shape(pre.cols, sc.cols, sc.len, oldest, total, nbg,
                               grShape, grScratch)
    end

    -- THE SHAPE IS MEASURED; THE SCALE AND LEVEL ARE WHAT THE PLUGINS REPORT.
    --
    --   The span between the probes sees the whole chain's reduction, 500
    --   times a second. Take away what the taps measured -- their plugins'
    --   share, each at its own delay -- and what is left is the REPORTING
    --   plugins' share, at full rate. Their reports (18 a second, joined
    --   by straight lines) say how big it really is.
    --
    --   The two are matched by a straight-line fit over the visible
    --   window, reported = a * span + b, rather than by sliding means
    --   together as this used to:
    --     * nothing reducing: the span's wobble has nothing in common
    --       with reports of zero, a comes out 0, and the trace lies flat
    --       on zero. Sliding means drew the wobble, half of it clipped
    --       against the top -- the square wave beside meters reading 0.
    --     * reducing: a comes out near 1 and the trace has the span's
    --       detail at the reports' size.
    --   The span is smoothed to about the reports' own rate (60 ms) for the
    --   FIT only -- fitting a sharp signal against a blurred one shrinks a,
    --   by a quarter in a test against a known reduction; smoothed, 0.96.
    --   It is drawn sharp.
    local rep, repN = {}, {}
    local each = {}          -- per reporting source: its reports, column by column
    local colsPerSec = sc.sr / math.max(1, sc.slice)
    if grLive > 0 then
      local held = nil
      local R = {}
      for j, src in ipairs(rigSources) do
        if src.usable and not src.est then each[j] = {} end
      end
      for k = 0, total - 1 do
        local v = grOut[k]
        local tapSum, repSum, haveRep = 0, 0, false
        for j, src in ipairs(rigSources) do
          if src.usable then
            local g = grHist[(oldest + k - (src.delayCols or 0)) % sc.len]
            local x = g and g[j]
            if src.est then tapSum = tapSum + (x or 0)
            elseif x then repSum = repSum + x ; haveRep = true ; each[j][k] = x end
          end
        end
        if v then held = -v - tapSum end     -- gated columns hold
        R[k] = held
        repN[k] = haveRep and repSum or nil
      end
      -- the fit, on a 60 ms running mean of the span
      local W = math.max(1, math.floor(0.06 * colsPerSec + 0.5))
      local half = math.floor(W / 2)
      -- running sums, so the window costs the same at any width
      local PS, PC = { [0] = 0 }, { [0] = 0 }
      for k = 0, total - 1 do
        local v = R[k]
        PS[k + 1] = PS[k] + (v or 0)
        PC[k + 1] = PC[k] + (v and 1 or 0)
      end
      local n, sx, sy, sxx, sxy = 0, 0, 0, 0, 0
      for c = 0, total - 1 do
        local y = repN[c]
        if y and R[c] then
          local lo, hi = math.max(0, c - half), math.min(total, c - half + W)
          local cnt = PC[hi] - PC[lo]
          if cnt > 0 then
            local xm = (PS[hi] - PS[lo]) / cnt
            n = n + 1
            sx, sy, sxx, sxy = sx + xm, sy + y, sxx + xm * xm, sxy + xm * y
          end
        end
      end
      if n >= 8 then
        local mx, my = sx / n, sy / n
        local vx = sxx / n - mx * mx
        local a = 0
        if vx > 1e-6 then a = (sxy / n - mx * my) / vx end
        a = math.max(0, math.min(2, a))
        local b = my - a * mx
        for k = 0, total - 1 do
          if R[k] then rep[k] = math.max(0, a * R[k] + b) end
        end
        rigFitA = a
      end
    end
    -- ONE TRACE PER REPORTING PLUGIN.
    --   The span can't tell two reporting compressors apart -- it sees
    --   their sum. Their reports can: at each moment, each plugin's share
    --   of what they report between them. So each plugin's trace is the
    --   fitted span at that column times its share -- the detail from the
    --   probes, the split from the plugins. Exact for one plugin; for two
    --   that duck at the same instant it's as good as their reports'
    --   timing allows, and the traces always add up to the fitted sum.
    if next(rep) ~= nil then
      local nRep = 0
      for _ in pairs(each) do nRep = nRep + 1 end
      for _, m in ipairs(series) do
        local j = m[1]
        local mine = each[j]
        if mine then
          local gx, gy, n = {}, {}, 0
          local held = 0
          for px = px0, px1 do
            local k0 = math.floor((px - px0) / span * total)
            local k1 = math.max(k0, math.floor((px + 1 - px0) / span * total) - 1)
            local deepest = nil
            for k = k0, math.min(k1, total - 1) do
              local v = rep[k]
              if v then
                local tot = repN[k]
                local share = (tot and tot > 0.05) and ((mine[k] or 0) / tot) or (1 / nRep)
                v = v * share
                if not deepest or v > deepest then deepest = v end
              end
            end
            if deepest then held = deepest end
            n = n + 1 ; gx[n] = px ; gy[n] = yGR(held)
          end
          polyline(dl, gx, gy, 1, n, alpha(m[2], 0.95), 1.6)
        end
      end
      measuredDrew = true
    end
  end

  for _, m in ipairs(series) do
    local idx, col = m[1], m[2]
    -- Drawn late by the latency between where the reading comes from and
    -- the post probe, so it sits on the transient it belongs to (see
    -- sourceDelay).
    local dly = (rigSources[idx] and rigSources[idx].delayCols) or 0
    local src = rigSources[idx]
    if ok and total >= 4 and not (measuredDrew and src and not src.est) then
      local gx, gy, n = {}, {}, 0
      local px0, px1 = math.floor(x0), math.floor(x1)
      local span = math.max(1, px1 - px0)
      local held = nil
      for px = px0, px1 do
        local k0 = math.floor((px - px0) / span * total)
        local k1 = math.max(k0, math.floor((px + 1 - px0) / span * total) - 1)
        local deepest = nil
        for k = k0, math.min(k1, total - 1) do
          local g = grHist[(oldest + k - dly) % sc.len]
          local v = g and g[idx]
          if v and (not deepest or v > deepest) then deepest = v end
        end
        if deepest then held = deepest end
        n = n + 1 ; gx[n] = px ; gy[n] = yGR(held or 0)
      end
      polyline(dl, gx, gy, 1, n, alpha(col, 0.95), 1.6)
    end
  end

  -- GR scale down the left
  local step = grRange <= 12 and 3 or 6
  local d = step
  while d < grRange do
    local y = yGR(d)
    ImGui.DrawList_AddLine(dl, x0, y, x1, y, COL.grid)
    ImGui.DrawList_AddText(dl, x0 + 3, y - 7, COL.textDim, ("-%d"):format(d))
    d = d + step
  end

  ---------------------------------------------------- the meters
  --
  -- ONE MAPPING FOR BOTH. The bar used to run from y0+12 (under the tag)
  -- to y1-15 (above the readout), while the trace and the dB scale down
  -- the left both used yGR, which spans the full y0..y1. So -3.1 dB on
  -- the trace and -3.1 dB on the bar were at different heights, and the
  -- meter quietly disagreed with the picture next to it.
  --
  -- The bar now uses yGR itself. Nothing is derived from it, nothing is
  -- parallel to it -- it IS it, so the two cannot drift apart again.
  local colw = BAR_W
  local now  = r.time_precise()
  for i = 1, #labels do
    local cx0 = gx0 + (i - 1) * colw
    local bx, bxe = cx0, cx0 + colw

    ImGui.DrawList_AddRectFilled(dl, bx, y0, bxe, y1, COL.frameBg, 0)
    -- One hairline on the left, where it divides the meter from the
    -- waveform. No box: a border all the way round is a margin drawn in
    -- ink.
    ImGui.DrawList_AddLine(dl, bx, y0, bx, y1, COL.grid, 1)

    local v    = vals[i] or 0
    local peak = grPeak(labels[i] .. i, v, now)

    if vals[i] then
      ImGui.DrawList_AddRectFilledMultiColor(dl, bx, y0, bxe, yGR(v),
        alpha(cols[i], 0.35), alpha(cols[i], 0.35), cols[i], cols[i])
    end

    -- The same rungs the scale down the left side prints, so a tick on
    -- the bar is the same decibel as the label opposite it.
    local step = grRange <= 12 and 3 or 6
    local d = step
    while d < grRange do
      ImGui.DrawList_AddLine(dl, bxe - 4, yGR(d), bxe - 1, yGR(d), COL.grid, 1)
      d = d + step
    end

    if peak > 0.05 then
      ImGui.DrawList_AddLine(dl, bx + 1, yGR(peak), bxe - 1, yGR(peak), COL.text, 1.5)
    end

    -- The held figure, over the foot of the bar. An en dash rather than
    -- "0.0" when nothing is happening: a compressor at rest has no
    -- reduction to report, and a number implies it measured one.
    local txt = (peak >= 0.05) and ("%.1f"):format(peak) or "\u{2013}"
    local tww, tth = ImGui.CalcTextSize(ctx, txt)
    -- Right-aligned to the bar: the only edge it must not cross.
    local tx, ty = bxe - tww, y1 - tth - 2
    -- A backing, because at full scale the fill reaches down here.
    ImGui.DrawList_AddRectFilled(dl, tx - 2, ty - 1, tx + tww + 2, ty + tth + 1,
      alpha(COL.bg, 0.85), 2)
    ImGui.DrawList_AddText(dl, tx, ty,
      (peak >= 0.05) and COL.text or COL.textDim, txt)
  end

  local readout
  if S.timeMode == 2 then
    readout = ("%.0f ms"):format(S.histSec * 1000)
  elseif S.timeMode == 3 then
    readout = ("%d beats  %.0f ms%s"):format(S.windowBeats, S.histSec * 1000,
      S.beatLock and "  locked" or "")
  else
    readout = ("%.2f s  (wheel to zoom)"):format(S.histSec)
  end
  ImGui.DrawList_AddText(dl, x0 + 6, y1 - 15, COL.textDim, readout)

  -- An empty reduction axis should say why it is empty.
  if (S.showGR or S.showGRTrace) and not anyUsable then
    local msg = (#rigSources > 0)
      and "no VST3 gain reduction between the probes -- waveform only"
      or  "nothing between the probes reports gain reduction"
    ImGui.DrawList_AddText(dl, x0 + 6, y0 + 4, COL.textDim, msg)
  end
  ImGui.DrawList_PopClipRect(dl)
end

----------------------------------------------------------
-- main loop
----------------------------------------------------------

ctx = ImGui.CreateContext('Track Analyser')

----------------------------------------------------------
-- where the window lives
--
-- ReaImGui remembers a window's size and position by itself, in its own ini
-- file, but NOT which REAPER docker it was in -- REAPER's dockers are
-- outside ImGui's world, so the dock ID has to be saved and handed back.
--
-- It is written whenever it CHANGES rather than on the way out. Saving at
-- exit is the obvious thing and it is what fails across a REAPER restart:
-- by the time a shutdown reaches the script the window is already going
-- away, and what gets saved is "floating".
----------------------------------------------------------

local dockId = tonumber(r.GetExtState(EXT, "dock")) or 0
local dockApplied = false
local openSettings = false

-- A FRAME THAT TAKES TOO LONG SAYS SO, AND SAYS WHERE
--
-- "REAPER hangs" is not something anyone can act on, and guessing at it is
-- how this project has lost time before. So the frame times itself in three
-- parts and, when one goes pathological, prints the breakdown once -- rate
-- limited, so a genuinely stuck panel does not also flood the console.
local wd = { last = 0, worst = 0 }

-- THE PANEL'S OWN FRAME RATE.
--
--   The publish-rate figure counts how often the reduction value
--   CHANGES, which is only the plugin's update rate if we are looking
--   more often than it changes. If the panel runs at 18 frames a second
--   then we look 18 times, every look shows a change, and the figure
--   reports our frame rate wearing the plugin's name.
--
--   Printed next to it so the two can be compared. Equal means we are
--   the bottleneck; publish clearly below fps means the plugin is.
local fps = { t = -1, v = 0 }
local function tickFps(now)
  if fps.t > 0 then
    local dt = now - fps.t
    if dt > 0 then
      local inst = 1 / dt
      fps.v = (fps.v > 0) and (fps.v * 0.9 + inst * 0.1) or inst
    end
  end
  fps.t = now
end

local function frame()
  local tA = r.time_precise()
  tickFps(tA)
  palFollow(tA)
  followTrack()

  if rig then
    -- Only when something is actually publishing there. Pumping a dead
    -- region just re-reads the same stale columns for ever -- and the
    -- panel's own copy of the ring is emptied too, because setUpRig
    -- keeps the audio when it is merely re-scanning the same track's
    -- chain, which is exactly the case where you have just pulled the
    -- pre probe out.
    if rig.pre then
      pumpScope("pre", G.PRE_BASE)
    elseif scope.pre.len ~= 0 or scope.pre.cur >= 0 then
      scope.pre.cols, scope.pre.cur, scope.pre.len = {}, -1, 0
    end
    pumpScope("post", G.POST_BASE)
    -- The probes report the real sample rate once they are publishing, and
    -- the FFT size and the scope slice both follow it.
    applyAnalysis(false)
    -- Written every frame rather than on change: a probe that restarted --
    -- a new epoch, a sample-rate change, a reload -- comes back with these
    -- at zero, and a trace that is silently uncompensated is worse than one
    -- that is obviously missing.
    -- Re-read twice a second, not only when the track is picked: bypassing
    -- a plugin with latency changes the delay between the probes, and an
    -- alignment that has gone stale turns every transient into a spike.
    local tnow = r.time_precise()
    if rig and tnow - (lagCheckedAt or 0) > 0.5 then
      lagCheckedAt = tnow
      rigLag = chainLatency(rigTrack, rig)
      local slice = math.max(1, (scope.post and scope.post.slice) or 96)
      for _, src in ipairs(rigSources) do
        src.delaySmp = sourceDelay(rigTrack, rig, src)
        src.delayCols = math.floor(src.delaySmp / slice + 0.5)
      end
    end
    r.gmem_write(G.CTRL_LAG, rigLag)
    -- Keeps the probe's taps measuring (see TS_TrackProbe.jsfx): they stop
    -- when nothing is reading them.
    tapBeat = (tapBeat + 1) % 1000000
    r.gmem_write(TAP_HB, tapBeat)
    r.gmem_write(G.CTRL_GRB,
      (S.showGRTrace and S.grTraceSrc == 2 and anyReported()) and 1 or 0)
    updateGR()
    pumpGR()
    -- Ask the probes for a running average unless a measurement tool has
    -- taken the control word for a one-shot capture; that mode is exclusive
    -- and the panel must not fight it.
    if (r.gmem_read(G.CTRL_MEAS) or 0) ~= 1 then
      TA.measureLive(S.curveTau * 1000, (SMOOTH[S.smoothIdx] or SMOOTH[1]).oct)
    end
  end
  -- The comparison track is re-resolved on the same project-change signal
  -- the chain scan uses, so deleting or reordering tracks cannot leave a
  -- stale pointer behind.
  -- ONLY WHEN SOMETHING COULD HAVE CHANGED.
  --   compareFollowTrack resolves a GUID by walking every track in the
  --   project, which is one string read per track. Doing that on every
  --   frame would be a few thousand calls a second on a big session to
  --   answer a question whose answer only moves when you change the
  --   selection or edit the track list.
  if S.showMask then
    local cnt = r.GetProjectStateChangeCount(0)
    if rigTrack ~= cmpLastTrack or cnt ~= cmpLastChange then
      cmpLastTrack, cmpLastChange = rigTrack, cnt
      compareFollowTrack()
    end
  end
  updateMask()
  local tB = r.time_precise()

  ImGui.SetNextWindowSize(ctx, 1000, 720, ImGui.Cond_FirstUseEver())

  -- Only on the very first frame: after that the dock is yours to change,
  -- and forcing it every frame would make the window impossible to drag out.
  if not dockApplied then
    dockApplied = true
    if dockId ~= 0 and ImGui.SetNextWindowDockID then
      ImGui.SetNextWindowDockID(ctx, dockId)
    end
  end

  -- PUSHED BEFORE Begin, NOT AFTER IT.
  --   ReaImGui checks at End that the style stack is where Begin left
  --   it, so anything pushed inside the window has to be popped inside
  --   it too -- pushing after Begin and popping after End throws
  --   "ImGui_End: Missing PopStyleColor()". Pushing outside the
  --   Begin/End pair puts the whole thing beyond that check, and has the
  --   side benefit that the window's own chrome -- background, border,
  --   title -- is styled as well as the widgets in it.
  local styleC, styleV = pushStyle(ctx)

  local visible, open = ImGui.Begin(ctx, 'Track Analyser', true,
    ImGui.WindowFlags_NoScrollWithMouse())

  if visible then
    -- Read inside the Begin/End pair, where this window is the current one.
    if ImGui.GetWindowDockID then
      local cur = ImGui.GetWindowDockID(ctx)
      if cur and cur ~= dockId then
        dockId = cur
        r.SetExtState(EXT, "dock", tostring(dockId), true)
      end
    end

    ---------------------------------------------------- header
    local name = "no track"
    if rigTrack then
      local _, n = r.GetSetMediaTrackInfo_String(rigTrack, "P_NAME", "", false)
      name = (n ~= "" and n) or "(unnamed track)"
    end
    -- The header row's origin AND the width actually available to it.
    -- GetWindowSize is the whole window including its padding and border;
    -- drawing is clipped to the CONTENT region, which is narrower. Using
    -- the former as the right-hand limit is why the chip lost its last
    -- few pixels no matter how short the label was.
    local headX, headY = ImGui.GetCursorScreenPos(ctx)
    local headAvail = ImGui.GetContentRegionAvail(ctx)
    ImGui.Text(ctx, name)
    ImGui.SameLine(ctx)
    if ImGui.SmallButton(ctx, 'Settings') then
      openSettings = not openSettings
      -- The startup file may have been edited outside this panel since
      -- the last look, so the state is re-read rather than remembered.
      if openSettings then startup.checked = false end
    end
    -- The window mode is the one thing you change while listening, so it
    -- lives on the title row rather than three clicks away.
    ImGui.SameLine(ctx)
    ImGui.SetNextItemWidth(ctx, 104)
    local modeNames = { "Free", "ms", "Beats" }
    if ImGui.BeginCombo(ctx, '##mode', modeNames[S.timeMode]) then
      for i, m in ipairs({ "Free (wheel)", "Milliseconds", "Beats" }) do
        if ImGui.Selectable(ctx, m, i == S.timeMode) then
          S.timeMode = i ; lock = {} ; touchSettings()
        end
      end
      ImGui.EndCombo(ctx)
    end
    ImGui.SameLine(ctx)
    local rvh
    local function markh(c) if c then touchSettings() end end
    if S.timeMode == 2 then
      ImGui.SetNextItemWidth(ctx, 96)
      rvh, S.windowMs = ImGui.DragDouble(ctx, '##len', S.windowMs, 5, 20, 8000, "%.0f ms") ; markh(rvh)
      ImGui.SameLine(ctx)
      rvh, S.beatLock = ImGui.Checkbox(ctx, 'Hold', S.beatLock) ; markh(rvh)
    elseif S.timeMode == 3 then
      ImGui.SetNextItemWidth(ctx, 76)
      rvh, S.windowBeats = ImGui.DragInt(ctx, '##beats', S.windowBeats, 0.2, 1, 32, "%d beats") ; markh(rvh)
      ImGui.SameLine(ctx)
      rvh, S.beatLock = ImGui.Checkbox(ctx, 'Lock', S.beatLock) ; markh(rvh)
    else
      ImGui.SetNextItemWidth(ctx, 96)
      rvh, S.histSec = ImGui.DragDouble(ctx, '##hist', S.histSec, 0.02, 0.05, 8, "%.2f s") ; markh(rvh)
    end

    if rigNote then
      ImGui.SameLine(ctx)
      if rigNeedsProbes then
        -- Drawn as a button rather than a line of text: the thing to do
        -- about "no probes" is to add them, and the offer belongs where the
        -- problem is stated, not three menus away. Transparent background,
        -- so it still reads as a note until you put the pointer on it.
        local pushed = 0
        local function pc(which, col)
          if which then ImGui.PushStyleColor(ctx, which(), col) ; pushed = pushed + 1 end
        end
        pc(ImGui.Col_Button,        0x00000000)
        pc(ImGui.Col_ButtonHovered, 0xFFFFFF1A)
        pc(ImGui.Col_ButtonActive,  0xFFFFFF33)
        pc(ImGui.Col_Text,          COL.warn)
        local hit = ImGui.SmallButton(ctx, rigNote .. " -- Install?")
        if pushed > 0 then ImGui.PopStyleColor(ctx, pushed) end
        if ImGui.IsItemHovered(ctx) and ImGui.SetTooltip then
          ImGui.SetTooltip(ctx,
            "Add a probe at each end of this track's FX chain.\n" ..
            "It only ever adds -- nothing is removed, reordered or replaced.")
        end
        if hit then confirmInsertProbes() end
      else
        ImGui.TextColored(ctx, COL.warn, rigNote)
      end
    end

    ----------------------------------------------------------
    -- the collisions chip
    --
    -- A checkbox and a combo would have done the job and looked like a
    -- settings dialog that escaped onto the title bar. This is drawn
    -- instead: a lamp, a rule, and a name, sitting at the right-hand end
    -- where nothing else competes for the space.
    --
    -- The lamp IS the switch, and it carries the state rather than
    -- reporting it. Unlit when off. Lit in the mask colour when on and
    -- clear. Ringed when something is actually being masked, with the
    -- ring's opacity following the deepest collision -- so the one glance
    -- you give the title row already tells you whether to look down at
    -- the spectrum.
    --
    -- Everything is an InvisibleButton over a drawn shape, so it inherits
    -- ImGui's hit testing and hover semantics without any of its chrome.
    ----------------------------------------------------------
    do
      local wx     = ImGui.GetWindowPos(ctx)
      local hdl    = ImGui.GetWindowDrawList(ctx)
      -- Where drawing actually stops being visible.
      local contentRight = headX + headAvail
      -- Where the header's own controls finished, so the chip can be told
      -- how much room is left rather than guessing at a fixed 260.
      local lastRight = wx + 260
      if ImGui.GetItemRectMax then
        local ok, ix = pcall(ImGui.GetItemRectMax, ctx)
        if ok and ix then lastRight = ix end
      end
      -- Where the header row actually is, captured before the row was
      -- built. Reading the cursor here gives the position AFTER the row
      -- wrapped, which is how the chip ended up on a line of its own.
      local cy = headY
      local savedX, savedY = ImGui.GetCursorScreenPos(ctx)

      -- Sized to its content, then pushed against the right edge. A fixed
      -- width would either clip long track names or leave a hole after
      -- short ones.
      -- "track missing" is only true when the panel WENT LOOKING and did
      -- not find it. With collisions off nothing looks, so saying it
      -- reported a fault that had not occurred: the partner is simply
      -- released, and the honest word for that is none.
      local full = cmpTrack and cmpName
                 or (S.showMask and cmpGuid and cmpGuid ~= "" and "track missing")
                 or "no track"

      local vsW = ImGui.CalcTextSize(ctx, "vs")
      local LAMP, GAP2, PAD = 9, 7, 4
      local chipH = 18
      local fixedW = LAMP + GAP2 + vsW + GAP2 + PAD * 2

      -- TRUNCATED BY MEASURED WIDTH, NOT BY BYTE COUNT.
      --   A fixed 22-character cut says nothing about how wide those
      --   characters are, and nothing at all about how much room is left.
      --   This asks the font, and asks it about the space that actually
      --   exists on this row at this window size.
      --
      --   Binary search rather than shrinking a character at a time: six
      --   measurements instead of forty, and each one is a marshalled
      --   call. Cached on the name and the width, because neither moves
      --   between most frames.
      local maxText = (contentRight - 2) - (lastRight + 14) - fixedW
      local label, tw = chipFit(ctx, full, maxText)

      -- No room for a name is not a reason to lose the lamp: the lamp is
      -- the state and the switch, and it is 9 pixels wide.
      local lampOnly = (label == nil)
      if lampOnly then label, tw = "", 0 end

      local chipW = lampOnly and (LAMP + PAD * 2)
                              or (fixedW + tw)
      local cx = (contentRight - 2) - chipW
      local top = cy - 1

      if cx > lastRight + 6 then
        local on   = S.showMask
        local hot  = MC.active and MC.nBands > 0
        local depth = hot and math.min(1, MC.peak / math.max(1, S.maskDepth)) or 0

        -- lamp ---------------------------------------------------------
        ImGui.SetCursorScreenPos(ctx, cx, top)
        ImGui.InvisibleButton(ctx, "##maskLamp", LAMP + PAD * 2, chipH)
        local lampHover = ImGui.IsItemHovered(ctx)
        if lampOnly and ImGui.IsItemClicked(ctx, 1) then
          ImGui.OpenPopup(ctx, "##maskMenu")
        elseif ImGui.IsItemClicked(ctx) then
          S.showMask = not S.showMask
          touchSettings()
          if S.showMask then
            -- compareFollowTrack, not refreshCompare: switching it back
            -- on should reconsider which partner belongs to the track
            -- you are on NOW, not re-arm whichever one was current when
            -- it was switched off. Clearing the gate's memory makes the
            -- frame loop agree.
            cmpLastTrack, cmpLastChange = nil, -1
            compareFollowTrack()
          else
            releaseCompare()
          end
        end
        local lx, ly = cx + PAD + LAMP * 0.5, top + chipH * 0.5
        local rad = LAMP * 0.5
        if on then
          ImGui.DrawList_AddCircleFilled(hdl, lx, ly, rad - 2,
            alpha(S.cMask, hot and 1.0 or 0.55), 16)
          if hot then
            -- The ring is the alarm. It only appears when there is
            -- something to be alarmed about, and it grows with the
            -- deepest collision rather than blinking on at a threshold.
            ImGui.DrawList_AddCircle(hdl, lx, ly, rad + 1.5,
              alpha(S.cMask, 0.25 + 0.6 * depth), 18, 1.4)
          end
        else
          ImGui.DrawList_AddCircle(hdl, lx, ly, rad - 2,
            lampHover and COL.text or COL.textDim, 16, 1.2)
        end

        -- the name, and the menu behind it ------------------------------
        local pickHover = false
        if not lampOnly then
        local nx = cx + PAD + LAMP + GAP2
        ImGui.SetCursorScreenPos(ctx, nx, top)
        ImGui.InvisibleButton(ctx, "##maskPick", vsW + GAP2 + tw + PAD, chipH)
        pickHover = ImGui.IsItemHovered(ctx)
        if ImGui.IsItemClicked(ctx) then ImGui.OpenPopup(ctx, "##maskMenu") end

        -- A hairline under the name, not a box around it. It says
        -- "this is clickable" at the weight of a text field rather than
        -- a button, and it brightens instead of filling on hover.
        ImGui.DrawList_AddLine(hdl, nx, top + chipH - 2, nx + vsW + GAP2 + tw, top + chipH - 2,
          pickHover and alpha(S.cMask, 0.8) or COL.grid, 1)
        ImGui.DrawList_AddText(hdl, nx, top + 2, COL.textDim, "vs")
        ImGui.DrawList_AddText(hdl, nx + vsW + GAP2, top + 2,
          (cmpTrack and (pickHover and COL.text or COL.textDim))
            or alpha(COL.warn, 0.9), label)
        end

        -- The popup is ImGui's, but it does not have to look like it.
        local pushedC, pushedV = 0, 0
        local function pc(which, col)
          if which then ImGui.PushStyleColor(ctx, which(), col) ; pushedC = pushedC + 1 end
        end
        pc(ImGui.Col_PopupBg,       0x14171Aff)
        pc(ImGui.Col_Border,        0x333A42ff)
        pc(ImGui.Col_Text,          0x8A939Cff)
        pc(ImGui.Col_HeaderHovered, alpha(S.cMask, 0.30))
        pc(ImGui.Col_HeaderActive,  alpha(S.cMask, 0.45))
        pc(ImGui.Col_Header,        alpha(S.cMask, 0.22))
        if ImGui.StyleVar_WindowPadding then
          ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowPadding(), 10, 8) ; pushedV = pushedV + 1
        end
        if ImGui.StyleVar_ItemSpacing then
          ImGui.PushStyleVar(ctx, ImGui.StyleVar_ItemSpacing(), 6, 4) ; pushedV = pushedV + 1
        end
        if ImGui.StyleVar_FrameRounding then
          ImGui.PushStyleVar(ctx, ImGui.StyleVar_FrameRounding(), 3) ; pushedV = pushedV + 1
        end

        if ImGui.BeginPopup and ImGui.BeginPopup(ctx, "##maskMenu") then
          local dl2 = ImGui.GetWindowDrawList(ctx)
          local selDim = (ImGui.SelectableFlags_Disabled
                          and ImGui.SelectableFlags_Disabled()) or 0

          -- THE COLOUR SWATCH, drawn INTO the row after it is laid out.
          -- Same device as ChannelView's send menu: three leading spaces
          -- reserve the column, and the colour goes down in absolute
          -- coordinates over the item's own rectangle. Two lists that
          -- name the project's tracks should read as the same list.
          local function swatch(tr2, dim)
            local ix, iy  = ImGui.GetItemRectMin(ctx)
            local _,  iy2 = ImGui.GetItemRectMax(ctx)
            local sw = trackColour(tr2) or COL.grid
            if dim then sw = alpha(sw, 0.38) end
            ImGui.DrawList_AddRectFilled(dl2, ix + 2, iy + 2, ix + 9, iy2 - 2, sw, 1.5)
          end

          ImGui.TextColored(ctx, COL.textDim, "COMPARE AGAINST")
          ImGui.Separator(ctx)
          if ImGui.Selectable(ctx, "   none##tanone", cmpGuid == nil) then
            setCompare(nil) ; cmpName = ""
          end

          -- A track named with nothing but punctuation is a template
          -- spacer, and REAPER's own I_SPACER puts a gap above a track.
          -- Both are grouping you set up in the project; flattening them
          -- out would make this list harder to read than the track panel
          -- it is describing. Never a rule before the first entry -- that
          -- reads as something missing above it.
          local pendingGap, first = false, true
          for i = 0, r.CountTracks(0) - 1 do
            local tr2 = r.GetTrack(0, i)
            local _, nm = r.GetSetMediaTrackInfo_String(tr2, "P_NAME", "", false)
            local _, gu = r.GetSetMediaTrackInfo_String(tr2, "GUID", "", false)
            local trimmed = (nm or ""):match("^%s*(.-)%s*$")
            if trimmed ~= "" and trimmed:match("^[%-%_%=%~%.%*%s]+$") then
              pendingGap = true
            else
              local space = (r.GetMediaTrackInfo_Value(tr2, "I_SPACER") or 0) > 0.5
              if (pendingGap or space) and not first then ImGui.Separator(ctx) end
              pendingGap, first = false, false

              local shown = (trimmed ~= "") and trimmed or ("Track %d"):format(i + 1)
              -- The id suffix, not the text, is what tells two rows apart:
              -- two tracks can carry the same name, and ImGui would treat
              -- them as one item.
              local label = ("   %d  %s##ta%d"):format(i + 1, shown, i + 1)

              if tr2 == rigTrack then
                -- Listed, disabled, swatch dimmed. Seeing your own track
                -- there and unavailable answers "why is mine not in the
                -- list" before it gets asked; a number missing from the
                -- middle reads as a fault in the list itself.
                ImGui.Selectable(ctx, label, false, selDim)
                swatch(tr2, true)
              else
                local hit = ImGui.Selectable(ctx, label, gu == cmpGuid)
                swatch(tr2, false)
                if hit then
                  setCompare(gu)
                  -- Choosing a track to compare against, while collisions
                  -- are off, otherwise does nothing visible at all. The lamp
                  -- lighting is the feedback that the choice landed.
                  if not S.showMask then S.showMask = true ; touchSettings() end
                end
              end
            end
          end
          ImGui.EndPopup(ctx)
        end
        if pushedV > 0 then ImGui.PopStyleVar(ctx, pushedV) end
        if pushedC > 0 then ImGui.PopStyleColor(ctx, pushedC) end

        if (lampHover or pickHover) and ImGui.SetTooltip then
          if MC.why then
            ImGui.SetTooltip(ctx, "collisions -- " .. MC.why)
          elseif hot then
            ImGui.SetTooltip(ctx, ("%d bands masked, deepest %.1f dB at %.0f Hz")
              :format(MC.nBands, MC.peak, MC.peakHz))
          else
            ImGui.SetTooltip(ctx, on and "collisions on" or "collisions off")
          end
        end

        -- Put the cursor back exactly where the header left it. The chip
        -- is drawn and hit-tested in absolute coordinates, so it owes the
        -- layout nothing.
        ImGui.SetCursorScreenPos(ctx, savedX, savedY)
      end
    end

    -- Set below when settings is open and the pointer is inside it.
    local settingsHovered = false

    if openSettings then
      ImGui.Separator(ctx)

      -- SETTINGS SCROLLS ITSELF.
      --
      --   The panel window is created with NoScrollWithMouse, because over
      --   the spectrum the wheel means floor and over the scope it means
      --   time. That flag belongs to the window, and settings is drawn
      --   inside it -- so the wheel did nothing here, and anything past the
      --   bottom edge could not be reached at all.
      --
      --   A child window has its own scrollbar and its own wheel, and the
      --   parent's flag does not reach into it. Bounding its height also
      --   stops settings pushing the panels off the bottom of a short
      --   window: below 300px of room it takes what there is, above that it
      --   takes 60% and leaves the panels at least 140.
      local availH   = select(2, ImGui.GetContentRegionAvail(ctx))
      local settingsH = availH
      if availH > 300 then
        settingsH = math.max(200, math.min(availH - 140, availH * 0.6))
      end
      local inSettings = ImGui.BeginChild(ctx, '##settings', 0, settingsH, 0)
      -- Jumped to the label at the end of the block, so the body below keeps
      -- its indentation rather than gaining a level for a guard clause.
      if not inSettings then goto settingsDone end

      -- Read here, where the child is the current window, and used by the
      -- wheel handler further down. Stated rather than inferred: the wheel
      -- must not reach the spectrum floor while you are scrolling settings.
      settingsHovered = ImGui.IsWindowHovered(ctx)

      local rv

      local function heading(t)
        ImGui.TextColored(ctx, COL.textDim, t)
      end
      -- Anything that changed is worth writing down, once things settle.
      local function mark(changed) if changed then touchSettings() end end

      local cflags = ImGui.ColorEditFlags_NoInputs()
      if ImGui.ColorEditFlags_AlphaBar then
        cflags = cflags | ImGui.ColorEditFlags_AlphaBar()
      end
      if ImGui.ColorEditFlags_AlphaPreviewHalf then
        cflags = cflags | ImGui.ColorEditFlags_AlphaPreviewHalf()
      end

      -- A data colour and its auto box. Auto GREYS the picker rather than
      -- hiding it: the point of following the hue is to see what the hue
      -- produced, and a control that vanishes when it is doing its job
      -- leaves you wondering where the colour came from. Untick to take
      -- that one colour off the hue; the others carry on following.
      local canDis = (ImGui.BeginDisabled and ImGui.EndDisabled) and true or false
      local function colAuto(key, label)
        local flag = DERIVED_AUTO[key]
        local on   = S[flag] ~= false
        if canDis and on then ImGui.BeginDisabled(ctx) end
        local ch, v = ImGui.ColorEdit4(ctx, label, S[key], cflags)
        if ch then S[key] = v ; touchSettings() end
        if canDis and on then ImGui.EndDisabled(ctx) end
        ImGui.SameLine(ctx, 0, 3)
        local ch2, v2 = ImGui.Checkbox(ctx, '##' .. key .. 'auto', on)
        if ch2 then S[flag] = v2 ; buildPalette() ; touchSettings() end
        if ImGui.IsItemHovered(ctx) then
          ImGui.SetTooltip(ctx,
            "Follow the hue.\nUntick to set this one colour by hand.")
        end
      end

      ---------------------------------------------- appearance
      heading("APPEARANCE")
      -- The same two controls ChannelView has, over the same palette
      -- maths, so the pair can be brought into line with a REAPER theme
      -- together. 219 and 1.00 are the hand-picked colours exactly.
      ImGui.SetNextItemWidth(ctx, 190)
      local hch, hv = ImGui.SliderInt(ctx, 'Hue', math.floor(S.baseHue), 0, 359)
      if hch then
        S.baseHue = hv ; buildPalette() ; touchSettings()
        palSet(hv, S.tint)
      end
      ImGui.SameLine(ctx)
      ImGui.SetNextItemWidth(ctx, 150)
      local tch, tv = ImGui.SliderDouble(ctx, 'Tint', S.tint, 0.0, 2.0, "%.2f")
      if tch then
        S.tint = tv ; buildPalette() ; touchSettings()
        palSet(S.baseHue, tv)
      end
      if ImGui.IsItemHovered(ctx) then
        ImGui.SetTooltip(ctx,
          "How far the greys lean toward the hue.\n0 is neutral grey, 1 is the default.")
      end

      do  -- a live swatch, so the sliders are not guesswork
        local sdl = ImGui.GetWindowDrawList(ctx)
        local cx, cy = ImGui.GetCursorScreenPos(ctx)
        local sw, sh = 190, 12
        local keys = { "winBg", "bg", "frameBg", "grid", "gridStr",
                       "zeroLine", "textDim", "text", "accent", "warn" }
        for i, k in ipairs(keys) do
          local x0 = cx + (i - 1) * (sw / #keys)
          ImGui.DrawList_AddRectFilled(sdl, x0, cy, x0 + sw / #keys, cy + sh, COL[k] or 0, 0)
        end
        ImGui.Dummy(ctx, sw, sh + 2)
      end
      ImGui.SameLine(ctx)
      rv, S.trackRule = ImGui.Checkbox(ctx, 'Track colour rule', S.trackRule) ; mark(rv)
      ImGui.SameLine(ctx)
      if ImGui.SmallButton(ctx, 'Reset') then
        S.baseHue, S.tint = 219, 1.0
        -- Reset means reset: any colour taken off the hue by hand comes
        -- back onto it, which is the only way back to the stock scheme
        -- without hunting six tick boxes.
        for _, f in pairs(DERIVED_AUTO) do S[f] = true end
        buildPalette() ; touchSettings()
        palSet(219, 1.0)
      end

      ImGui.Separator(ctx)

      ---------------------------------------------- what is on screen
      heading("PANELS")
      -- A guard rather than a rule: turning off the last visible panel
      -- leaves an empty window and no way back except Settings, which is
      -- itself inside the empty window. The other one comes on instead.
      local function keepOne(which)
        if not S.showSpectrum and not S.showScope then
          if which == "spectrum" then S.showScope = true else S.showSpectrum = true end
        end
      end
      rv, S.showSpectrum = ImGui.Checkbox(ctx, 'Spectrum', S.showSpectrum)
      if rv then keepOne("spectrum") ; touchSettings() end
      ImGui.SameLine(ctx)
      rv, S.showScope = ImGui.Checkbox(ctx, 'Scope', S.showScope)
      if rv then keepOne("scope") ; touchSettings() end

      ImGui.Separator(ctx)

      ---------------------------------------------- panel 1
      heading("SPECTRUM AND RESPONSE CURVE")
      -- WHAT THE TRANSFORM CAN ACTUALLY RESOLVE, AS A NUMBER.
      --   Below the first bin the probe holds bin 1's value, so the trace
      --   runs flat to the axis rather than falling into a hole -- but
      --   flat is a hold, not detail, and the frequency it starts at is
      --   worth being able to read rather than infer from the picture.
      do
        local sr = r.gmem_read(G.POST_BASE + G.H_SRATE) or 0
        local sz = r.gmem_read(G.POST_BASE + G.H_FFTSZ) or 0
        if sr > 0 and sz > 0 then
          ImGui.TextColored(ctx, COL.textDim,
            ("%.0f kHz, %d point transform -- first bin %.1f Hz, flat below that")
            :format(sr / 1000, sz, sr / sz))
        end
      end
      -- Each trace with its own colour beside its own switch, so there is
      -- no guessing which picker belongs to which line. The alpha bar on
      -- each one is what sets how solid the fill is: the pre spectrum wants
      -- to be faint enough to read the post one through, and how faint
      -- depends on your monitor, not on a number I can pick for you.
      -- With one probe there is no "before" to show, and a live-looking
      -- checkbox that changes nothing is worse than a greyed one.
      local havePre = (rig and rig.pre) and true or false
      local canDim  = (ImGui.BeginDisabled and ImGui.EndDisabled) and true or false
      local function dimOn()  if canDim and not havePre then ImGui.BeginDisabled(ctx) end end
      local function dimOff() if canDim and not havePre then ImGui.EndDisabled(ctx) end end
      dimOn()
      rv, S.showPre   = ImGui.Checkbox(ctx, 'Pre spectrum',  S.showPre)   ; mark(rv) ; ImGui.SameLine(ctx)
      colAuto('cSpecPre', '##cspre')
      dimOff()
      ImGui.SameLine(ctx)
      rv, S.showPost  = ImGui.Checkbox(ctx, 'Post spectrum', S.showPost)  ; mark(rv) ; ImGui.SameLine(ctx)
      colAuto('cSpecPost', '##cspost')

      rv, S.showCurve = ImGui.Checkbox(ctx, 'Response curve', S.showCurve) ; mark(rv) ; ImGui.SameLine(ctx)
      colAuto('cCurve', '##ccurve') ; ImGui.SameLine(ctx)
      rv, S.curveFill = ImGui.Checkbox(ctx, 'Curve fill',     S.curveFill) ; mark(rv) ; ImGui.SameLine(ctx)
      rv, S.autoScale = ImGui.Checkbox(ctx, 'Auto expand',    S.autoScale) ; mark(rv)

      -- Short follows a knob move and shows the noise with it; long is
      -- smooth and lags. 1.5 s is about the point where a filter sweep still
      -- reads as a sweep.
      ImGui.SetNextItemWidth(ctx, 150)
      rv, S.curveTau  = ImGui.SliderDouble(ctx, 'Curve averaging (s)', S.curveTau, 0.05, 5) ; mark(rv)
      ImGui.SameLine(ctx)
      ImGui.SetNextItemWidth(ctx, 130)
      local sm = SMOOTH[S.smoothIdx] or SMOOTH[1]
      if ImGui.BeginCombo(ctx, 'Curve smoothing', sm.name) then
        for i, e in ipairs(SMOOTH) do
          if ImGui.Selectable(ctx, e.name, i == S.smoothIdx) then
            S.smoothIdx = i ; touchSettings()
          end
        end
        ImGui.EndCombo(ctx)
      end

      -- How far below the loudest bin the excitation may fall before the
      -- curve breaks rather than divides by nothing.
      ImGui.SetNextItemWidth(ctx, 150)
      rv, S.excRange  = ImGui.SliderDouble(ctx, 'Excitation range (dB)', S.excRange, 20, 96) ; mark(rv)
      ImGui.SameLine(ctx)
      ImGui.SetNextItemWidth(ctx, 150)
      rv, S.specBot   = ImGui.SliderDouble(ctx, 'Spectrum floor', S.specBot, -120, -40, "%.0f dB") ; mark(rv)

      ImGui.Separator(ctx)

      ---------------------------------------------- collisions
      heading("COLLISIONS")
      ImGui.TextColored(ctx, COL.textDim,
        "the lamp on the title row switches this on and picks the track")
      ImGui.SameLine(ctx)
      local rvm
      rvm, S.cMask = ImGui.ColorEdit4(ctx, '##cmask', S.cMask, cflags) ; mark(rvm)

      if S.showMask then
        ImGui.SetNextItemWidth(ctx, 150)
        -- 0 is same-critical-band only, which is roughly what Pro-Q and
        -- Claro describe themselves as doing. 1 is Schroeder as
        -- published. Having both on one control is what makes them
        -- comparable on the same material.
        rv, S.maskSpread = ImGui.SliderDouble(ctx, 'Spread', S.maskSpread, 0, 2,
          S.maskSpread < 0.05 and "same band only" or "%.2f") ; mark(rv)
        ImGui.SameLine(ctx)
        ImGui.SetNextItemWidth(ctx, 150)
        rv, S.maskOffset = ImGui.SliderDouble(ctx, 'Masking index', S.maskOffset, 0, 24, "%.0f dB") ; mark(rv)

        ImGui.SetNextItemWidth(ctx, 150)
        rv, S.maskFloor = ImGui.SliderDouble(ctx, 'Audibility gate', S.maskFloor, -100, -20, "%.0f dB") ; mark(rv)
        ImGui.SameLine(ctx)
        ImGui.SetNextItemWidth(ctx, 150)
        rv, S.maskDepth = ImGui.SliderDouble(ctx, 'Full red at', S.maskDepth, 3, 30, "%.0f dB") ; mark(rv)

        -- The contour is the line along the top of the post spectrum. It
        -- reads more precisely than the fill does, and some material is
        -- easier to judge with it off and only the wash showing.
        rv, S.maskEdge = ImGui.Checkbox(ctx, 'Colour the contour too', S.maskEdge) ; mark(rv)

        if MC.why then
          ImGui.TextColored(ctx, COL.textDim, "collisions: " .. MC.why)
        elseif MC.active then
          ImGui.TextColored(ctx, COL.textDim,
            ("collisions: %d of %d bands masked, deepest %.1f dB at %.0f Hz  --  levels include both faders")
            :format(MC.nBands, MC.grid and MC.grid.n or 0, MC.peak, MC.peakHz))
        end
      end

      ImGui.Separator(ctx)

      ---------------------------------------------- panel 2
      heading("WAVEFORM AND GAIN REDUCTION")
      ImGui.SetNextItemWidth(ctx, 130)
      local modes = { "Free (wheel)", "Milliseconds", "Beats" }
      if ImGui.BeginCombo(ctx, 'Window', modes[S.timeMode]) then
        for i, m in ipairs(modes) do
          if ImGui.Selectable(ctx, m, i == S.timeMode) then
            S.timeMode = i ; lock = {} ; touchSettings()
          end
        end
        ImGui.EndCombo(ctx)
      end
      ImGui.SameLine(ctx)
      if S.timeMode == 2 then
        ImGui.SetNextItemWidth(ctx, 150)
        rv, S.windowMs = ImGui.SliderDouble(ctx, 'Length', S.windowMs, 20, 8000, "%.0f ms")
        ImGui.SameLine(ctx)
        rv, S.beatLock = ImGui.Checkbox(ctx, 'Hold window', S.beatLock)
      elseif S.timeMode == 3 then
        ImGui.SetNextItemWidth(ctx, 120)
        rv, S.windowBeats = ImGui.SliderInt(ctx, 'Beats', S.windowBeats, 1, 32)
        ImGui.SameLine(ctx)
        rv, S.beatLock = ImGui.Checkbox(ctx, 'Lock to beat', S.beatLock)
      else
        ImGui.SetNextItemWidth(ctx, 150)
        rv, S.histSec = ImGui.SliderDouble(ctx, 'History', S.histSec, 0.05, 8, "%.2f s")
      end

      -- How often each plugin actually produces a new reduction number.
      -- The difference between one that publishes at 16 Hz and one that
      -- publishes at 1 Hz is worth a figure rather than an impression.
      do
        local cps = scope.post.sr / math.max(1, scope.post.slice)
        local bits = {}
        for i, src in ipairs(rigSources) do
          local g = grGapEma[i]
          if g and g > 0 then
            bits[#bits + 1] = ("%s %.1f/s"):format(src.tag or "?", cps / g)
          end
        end
        -- WHAT THE MEASURED TRACE IS STANDING ON. Both of these are
        -- invisible when they work and indistinguishable from a broken
        -- trace when they do not, which is exactly the kind of thing that
        -- belongs on screen rather than in a comment.
        do
          local applied = math.floor(r.gmem_read(G.PRE_BASE + G.H_LAG) or 0)
          local sr = (scope.post and scope.post.sr) or 48000
          local nbg = math.floor(r.gmem_read(G.POST_BASE + G.H_GRBN) or 0)
          local lagTxt
          if rigLag <= 0 then
            lagTxt = "chain latency: none"
          elseif applied == rigLag then
            lagTxt = ("chain latency: %d smp (%.1f ms) compensated")
                     :format(rigLag, rigLag / sr * 1000)
          else
            lagTxt = ("chain latency: %d smp -- probe applied %d, not compensated")
                     :format(rigLag, applied)
          end
          ImGui.TextColored(ctx, COL.textDim, lagTxt ..
            (nbg > 0 and ("      GR bands: %d"):format(nbg)
                     or  "      GR bands: off"))
        end
        if #bits > 0 then
          ImGui.TextColored(ctx, COL.textDim,
            "publish rate:  " .. table.concat(bits, "   ") ..
            ("      panel frame rate: %.1f/s"):format(fps.v))
          -- Which of the two is the bottleneck, said rather than left to
          -- be worked out from the numbers.
          --
          -- THE FASTEST SOURCE, NOT THE FIRST. Keying this to grGapEma[1]
          -- meant it stayed silent whenever source one happened to be the
          -- idle plugin -- which with three reporters on a track is most
          -- of the time. What matters is whether ANY of them is keeping
          -- up with the panel.
          local pub = 0
          for i = 1, #rigSources do
            local g = grGapEma[i]
            if g and g > 0 then
              local rate = cps / g
              if rate > pub then pub = rate end
            end
          end
          if pub > 0 and fps.v > 1 then
            ImGui.TextColored(ctx, COL.textDim, (pub > fps.v * 0.9)
              and ("the plugin is keeping up; the panel's frame rate is the " ..
                   "limit (no script can poll faster than about 30/s)")
              or  ("the plugin is publishing more slowly than the panel is " ..
                   "looking, so this is the plugin's rate"))
          end
        end
      end

      rv, S.showGR = ImGui.Checkbox(ctx, 'GR meter', S.showGR) ; mark(rv)
      ImGui.SameLine(ctx)
      rv, S.showGRTrace = ImGui.Checkbox(ctx, 'GR trace', S.showGRTrace) ; mark(rv)
      if S.showGRTrace then
        ImGui.SameLine(ctx)
        ImGui.SetNextItemWidth(ctx, 210)
        local srcs = { "reported by the plugin  (~18/s)",
                       "measured by the probes  (500/s)" }
        local cur = srcs[S.grTraceSrc] or srcs[1]
        if ImGui.BeginCombo(ctx, '##grsrc', cur) then
          for i, nm in ipairs(srcs) do
            if ImGui.Selectable(ctx, nm, i == S.grTraceSrc) then
              S.grTraceSrc = i ; touchSettings()
            end
          end
          ImGui.EndCombo(ctx)
        end
        if S.grTraceSrc == 2 then
          local haveSrc = false
          for _, src in ipairs(rigSources) do
            if src.usable then haveSrc = true break end
          end
          local nbg = math.floor(r.gmem_read(G.POST_BASE + G.H_GRBN) or 0)
          if not (rig and rig.pre) then
            ImGui.TextColored(ctx, COL.warn,
              "measuring needs both probes -- falling back to what the plugin reports")
          elseif rig.pre and rig.post and nbg < 4 then
            -- A probe from before the filterbank. It cannot publish the
            -- per-band levels the measured trace is built from, and the
            -- panel will not guess: it says so and draws the reported one.
            ImGui.TextColored(ctx, COL.warn,
              "these probes are older than the panel -- reload the FX, or re-run " ..
              "TS_TA_InsertProbes.  Showing what the plugin reports meanwhile")
          elseif not anyReported() then
            ImGui.TextColored(ctx, COL.textDim,
              "every source here is measured by a probe tap -- each drawn as its meter reads")
          elseif not haveSrc then
            ImGui.TextColored(ctx, COL.warn,
              "nothing here reports reduction, so there is no level to anchor the " ..
              "measured shape to -- no trace is drawn")
          else
            ImGui.TextColored(ctx, COL.textDim,
              ("shape from the probes, size and level from the plugin's reports%s"):format(
                rigFitA and (" (scale %.2f)"):format(rigFitA) or ""))
          end
        end
      end

      ImGui.SetNextItemWidth(ctx, 150)
      rv, S.grRange = ImGui.SliderDouble(ctx, 'Reduction scale', S.grRange, 6, 36, "%.0f dB") ; mark(rv)
      ImGui.SameLine(ctx)
      dimOn()
      rv, S.showPreWave = ImGui.Checkbox(ctx, 'Unprocessed behind', S.showPreWave) ; mark(rv)
      dimOff()

      colAuto('cWavePre', 'Unprocessed')
      ImGui.SameLine(ctx)
      colAuto('cWavePost', 'Processed')
      ImGui.SameLine(ctx)
      colAuto('cGR', 'Reduction')
      ImGui.SameLine(ctx)
      colAuto('cGRMeas', 'Measured')

      ImGui.Separator(ctx)

      ---------------------------------------------- startup
      heading("STARTUP")
      -- Scanned when Settings opens rather than held in ExtState: the
      -- file is the truth, and a remembered boolean is just something
      -- that can disagree with it.
      if not startup.checked then startupScan() end
      do
        local on = (startup.state == "ours" or startup.state == "manual")
        local rvS, want = ImGui.Checkbox(ctx, 'Run when REAPER starts', on)
        if rvS then
          local ok, why
          if want then ok, why = startupAdd() else ok, why = startupRemove() end
          if not ok then
            r.ShowMessageBox(
              "__startup.lua was NOT changed.\n\n" .. tostring(why),
              "Track Analyser", 0)
          end
        end
        ImGui.SameLine(ctx)
        if startup.note then
          ImGui.TextColored(ctx, COL.warn, startup.note)
        elseif startup.state == "ours" then
          ImGui.TextColored(ctx, COL.textDim,
            "in __startup.lua -- takes effect next time REAPER starts")
        else
          ImGui.TextColored(ctx, COL.textDim,
            "edits Scripts/__startup.lua, backing it up first")
        end
      end

      ImGui.Separator(ctx)

      ---------------------------------------------- what it is reading
      local rvs
      rvs, S.showSources = ImGui.Checkbox(ctx, 'Show sources', S.showSources) ; mark(rvs)
      if S.showSources then
      heading("SOURCES")
      if #rigSources == 0 then
        ImGui.TextColored(ctx, COL.warn,
          "Nothing between the probes reports gain reduction to the host.")
      end
      for i, src in ipairs(rigSources) do
        local note
        if src.est then
          local z = rigTrack and Strip.tapZero and Strip.tapZero(rigTrack, src.route)
          note = "measured by the post probe -- an estimate"
            .. ((z == 1 and ", zero measured at the last stop")
             or (z == 2 and ", zero measured but level-dependent")
             or (z == 3 and ", plugin touched since its zero")
             or ", zero not measured yet: stop playback a moment")
        elseif not src.usable then
          note = "no VST3 reduction readout -- listed, not drawn"
        elseif src.active == false then
          note = "BYPASSED -- counted as zero"
        else
          note = "decibels direct from REAPER"
        end
        if src.usable and (src.delaySmp or 0) > 0 then
          local sr = (scope.post and scope.post.sr) or 48000
          note = note .. ("; trace drawn %.1f ms late to sit on the waveform")
                         :format(src.delaySmp / sr * 1000)
        end
        ImGui.TextColored(ctx,
          (src.usable and src.active ~= false) and COL.text or COL.warn,
          ("%-6s %-26s %6.2f dB   %s   %s"):format(
            src.tag or "?", src.plugin:sub(1, 26), GRsrc[i] or 0,
            src.est and "probe tap " or (src.usable and "VST3 route" or "parameter only"), note))
      end
      for _, o in ipairs(rigOutside) do
        -- Only worth saying if it is actually doing something. A bypassed
        -- plugin outside the probes is not a missing measurement.
        local parent
        for _, fx in ipairs(rig and rig.chain or {}) do
          if fx.idx == o.fx then parent = fx.container break end
        end
        if Strip.fxActive(rigTrack, o.fx, parent) then
          ImGui.TextColored(ctx, COL.warn,
            ("%s reports reduction but sits %s, so it is not counted")
            :format(o.plugin:sub(1, 30), o.where))
        end
      end
      if probeTooOld then
        ImGui.TextColored(ctx, COL.warn,
          "TS_TrackProbe.jsfx is older than this panel: it is the probe that measures")
        ImGui.TextColored(ctx, COL.warn,
          "the response now. Reinstall it into Effects/TS_TrackAnalyser and reload.")
      end
      for _, m in ipairs(MISSING)    do ImGui.TextColored(ctx, COL.warn, m) end
      end

      -- ReaImGui: EndChild only when BeginChild returned true.
      ImGui.EndChild(ctx)
      ::settingsDone::
    end

    ---------------------------------------------------- stacked panels
    local dl = ImGui.GetWindowDrawList(ctx)

    do  -- the track's colour across the top of the panel area
      local cx, cy = ImGui.GetCursorScreenPos(ctx)
      trackRule(dl, cx, cy, select(1, ImGui.GetContentRegionAvail(ctx)), rigTrack)
      -- step past it so the panel corners do not sit on the rule
      ImGui.Dummy(ctx, 0, 5)
    end

    local aw, ah = ImGui.GetContentRegionAvail(ctx)
    local px, py = ImGui.GetCursorScreenPos(ctx)
    -- Leave room for the matching rule along the bottom edge.
    ah = math.max(40, ah - 7)

    local GAP = 6
    -- ONE PANEL, OR TWO.
    --   With both on this is the old split. With one hidden the other
    --   takes the whole height and the divider goes with it -- a
    --   draggable line with nothing on one side of it is furniture
    --   pretending to be a control.
    local both = S.showSpectrum and S.showScope
    local h1, h2, y2
    if both then
      h1 = math.max(120, (ah - GAP) * S.split)
      h2 = math.max(90,  (ah - GAP) - h1)
      y2 = py + h1 + GAP
    elseif S.showSpectrum then
      h1, h2, y2 = ah, 0, py
    else
      h1, h2, y2 = 0, ah, py
    end

    if S.showSpectrum then drawPanel1(dl, px, py, aw, h1) end

    if both then
      ImGui.Dummy(ctx, aw, h1)
      -- draggable divider
      ImGui.InvisibleButton(ctx, '##split', aw, GAP)
      if ImGui.IsItemActive(ctx) then
        local _, dy = ImGui.GetMouseDragDelta(ctx)
        if ah > 0 then
          S.split = math.max(0.2, math.min(0.85, S.split + dy / ah * 0.06))
          touchSettings()
        end
      end
      if ImGui.IsItemHovered(ctx) then
        ImGui.DrawList_AddLine(dl, px, py + h1 + GAP * 0.5, px + aw, py + h1 + GAP * 0.5,
          COL.zeroLine, 2)
      end
    end

    if S.showScope then
      drawPanel2(dl, px, y2, aw, h2)
      ImGui.Dummy(ctx, aw, h2)
    end

    do  -- and the matching rule along the bottom edge of the window
      local wx, wy = ImGui.GetWindowPos(ctx)
      local ww, wh = ImGui.GetWindowSize(ctx)
      trackRule(dl, wx + 6, wy + wh - 5, ww - 12, rigTrack)
    end

    -- The wheel means whatever panel it is over. Nothing is hidden behind a
    -- menu that you have to remember exists.
    local p2hot = S.showScope
      and ImGui.IsMouseHoveringRect(ctx, px, y2, px + aw, y2 + h2)

    local wheel = ImGui.GetMouseWheel(ctx)
    if wheel and wheel ~= 0 and not settingsHovered and ImGui.IsWindowHovered(ctx) then
      touchSettings()
      if S.showSpectrum and ImGui.IsMouseHoveringRect(ctx, px, py, px + aw, py + h1) then
        S.specBot = math.max(-120, math.min(-40, S.specBot + wheel * 3))
      elseif p2hot then
        -- Gentler the further in you are, so the short end is not a cliff.
        if S.timeMode == 1 then
          local f = wheel > 0 and (1 / 1.12) or 1.12
          S.histSec = math.max(0.05, math.min(8, S.histSec * f))
        elseif S.timeMode == 2 then
          S.windowMs = math.max(20, math.min(8000,
            S.windowMs * (wheel > 0 and (1 / 1.12) or 1.12)))
        else
          S.windowBeats = math.max(1, math.min(32, S.windowBeats + (wheel > 0 and -1 or 1)))
        end
      end
    end

    ImGui.End(ctx)
  end
  -- Balanced against the push above, outside the Begin/End pair. The
  -- pairing itself is left exactly as it was.
  popStyle(ctx, styleC, styleV)

  -- Written at most once a second, and only after something changed, so a
  -- slider being dragged does not write ExtState thirty times a second.
  -- Never at exit: by the time a REAPER shutdown reaches a script the
  -- window is already going away, which is how the dock ID used to be lost.
  if settingsDirty and r.time_precise() - settingsAt > 1.0 then
    settingsDirty, settingsAt = false, r.time_precise()
    saveSettings()
  end

  if DEBUG then
    local tC = r.time_precise()
    if tC - tA > FRAME_BUDGET and tC - wd.last > 2.0 then
      wd.last = tC
      r.ShowConsoleMsg(("[Track Analyser] slow frame %.0f ms  --  state %.0f, draw %.0f\n")
        :format((tC - tA) * 1000, (tB - tA) * 1000, (tC - tB) * 1000))
    end
  end

  if open then r.defer(frame) else if rig then TA.disarm(rig) end end
end

r.atexit(function()
  if rig then TA.disarm(rig) end
  -- The comparison probe's Position is put back to Post here as well as
  -- on release. A probe left saying "Comparison" would keep writing to
  -- the comparison region when that track later became the selected one.
  releaseCompare()
end)
r.defer(frame)
