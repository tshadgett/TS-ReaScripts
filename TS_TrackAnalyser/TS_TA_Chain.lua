--========================================================
-- @noindex
-- @title TS_TA_Chain
-- @description Track Analyser -- find the probes and the strip on a track,
--              through containers, and arm the right pair
-- @author Tim Shadgett (with Claude)
-- @version 1.0.0
-- MIT licence -- see LICENSE in the TS-ReaScripts repository.
--========================================================
--
-- Not a script you run. The panel requires this.
--
-- WHAT IT IS FOR
--   The panel does not insert or remove anything. The container with
--   TS_TrackProbe / InfiniStrip / TS_TrackProbe lives in the track template. All this
--   module does is find that container on whatever track is selected, work
--   out which probe is which, and flip one parameter to arm the pair --
--   and flip the previous pair back off.
--
-- THE CONTAINER PROBLEM, AND HOW THIS AVOIDS GUESSING
--   REAPER addresses FX inside a container with an encoded index, not a
--   plain one. I could not confirm the exact encoding from the documentation
--   available to me, and a tool that guesses wrong here does not fail --
--   it quietly writes parameters to the wrong plugin. So this does not
--   guess. It tries each candidate encoding, reads the FX name back, and
--   keeps the form that answers. If none answers it says so rather than
--   carrying on.
--
--   The working form is cached per session once proven.
--========================================================

local r = reaper
local M = {}

M.PROBE_NAME  = "TS_TrackProbe"
M.STRIP_MATCH = "InfiniStrip"

-- TS_TrackProbe slider indices (0-based, as TrackFX_SetParam sees them)
M.P_ROLE    = 0
M.P_PUBLISH = 1
M.P_RELEASE = 2

-- Values for P_ROLE.
M.ROLE_PRE     = 0
M.ROLE_POST    = 1
M.ROLE_COMPARE = 2

----------------------------------------------------------
-- naming
----------------------------------------------------------

local function fxName(tr, idx)
  local ok, nm = r.TrackFX_GetFXName(tr, idx, "")
  if not ok or not nm or nm == "" then return nil end
  return nm
end

-- Every name REAPER will admit to for one FX: what it shows, and what it
-- was called before anyone renamed it. Tim's container is called "Strip",
-- so anything that keys off the displayed name alone is already broken.
local function namesOf(tr, idx)
  local out = {}
  local shown = fxName(tr, idx)
  if shown then out[#out + 1] = shown end
  for _, key in ipairs({ "fx_name", "original_name", "fx_ident" }) do
    local ok, v = r.TrackFX_GetNamedConfigParm(tr, idx, key)
    if ok and v and v ~= "" then out[#out + 1] = v end
  end
  return out
end

local function anyNameHas(names, needle)
  for _, n in ipairs(names) do
    if n:find(needle, 1, true) then return true end
  end
  return false
end

----------------------------------------------------------
-- container addressing, established by experiment
----------------------------------------------------------

-- Candidate encodings for "sub-FX `sub` of the container at `cont`, where
-- the level containing that container holds `levelCount` FX and the
-- container itself holds `contCount`".
local function candidates(cont, sub, levelCount, contCount)
  return {
    { form = "0x2000000 + (cont+1) + (sub+1)*(levelCount+1)",
      idx  = 0x2000000 + (cont + 1) + (sub + 1) * (levelCount + 1) },
    { form = "0x2000000 + (cont+1) + (sub+1)*(contCount+1)",
      idx  = 0x2000000 + (cont + 1) + (sub + 1) * (contCount + 1) },
    { form = "0x2000000 + (cont+1) + (sub+1)*(contCount+2)",
      idx  = 0x2000000 + (cont + 1) + (sub + 1) * (contCount + 2) },
  }
end

M.encoding = nil   -- set once a form has been proven on this project

local function containerCount(tr, cont)
  local ok, v = r.TrackFX_GetNamedConfigParm(tr, cont, "container_count")
  if ok and v then return tonumber(v) end
  return nil
end

-- Resolve one child. Returns index, formLabel  (or nil, reason)
local function childIndex(tr, cont, sub, levelCount, contCount)
  local list = candidates(cont, sub, levelCount, contCount)

  -- If a form is already proven, use it and nothing else -- consistency
  -- matters more than a lucky hit from a different formula.
  if M.encoding then
    for _, c in ipairs(list) do
      if c.form == M.encoding then
        return (fxName(tr, c.idx) and c.idx or nil), c.form
      end
    end
  end

  for _, c in ipairs(list) do
    if fxName(tr, c.idx) then
      M.encoding = c.form
      return c.idx, c.form
    end
  end
  return nil, "no addressing form reached sub-FX " .. sub
end

----------------------------------------------------------
-- walking a chain
----------------------------------------------------------

-- Returns a flat, ordered list of every FX on the track, containers
-- expanded in place:
--   { idx = <index usable with TrackFX_*>, name = ..., depth = n,
--     container = <container idx or nil>, path = "2 / 1" }
function M.walk(tr, problems)
  problems = problems or {}
  local out = {}

  -- count            how many FX sit at THIS level
  -- outerCount       how many FX sit at the level that HOLDS parentIdx
  local function level(parentIdx, count, depth, prefix, outerCount)
    for i = 0, count - 1 do
      local idx, nm
      if parentIdx == nil then
        idx = i
        nm = fxName(tr, idx)
      else
        local got, form = childIndex(tr, parentIdx, i, outerCount, count)
        if not got then
          problems[#problems + 1] = form
          idx = nil
        else
          idx = got
          nm = fxName(tr, idx)
        end
      end

      if idx then
        local path = prefix == "" and tostring(i) or (prefix .. " / " .. i)
        -- A container is whatever answers container_count. Nothing here
        -- depends on what it is called.
        local cc = containerCount(tr, idx)
        out[#out + 1] = {
          idx = idx, name = nm or "?", names = namesOf(tr, idx),
          depth = depth, container = parentIdx, path = path,
          isContainer = (cc ~= nil and cc >= 0), count = cc,
        }
        if cc and cc > 0 and depth < 4 then
          level(idx, cc, depth + 1, path, count)
        end
      end
    end
  end

  local top = r.TrackFX_GetCount(tr)
  level(nil, top, 0, "", top)
  return out, problems
end

----------------------------------------------------------
-- identifying the rig on a track
----------------------------------------------------------

-- Returns a table, or nil plus a reason:
--   { track, pre = {idx,...}, post = {idx,...}, strip = {idx,...} or nil,
--     chain = <walk result>, problems = {...} }
function M.find(tr)
  if not tr then return nil, "no track" end

  local problems = {}
  local chain = M.walk(tr, problems)

  local probes, strip = {}, nil
  for _, fx in ipairs(chain) do
    if not fx.isContainer then
      if anyNameHas(fx.names, M.PROBE_NAME) then
        probes[#probes + 1] = fx
      elseif anyNameHas(fx.names, M.STRIP_MATCH) then
        strip = strip or fx
      end
    end
  end

  if #probes == 0 then
    return nil, "no TS_TrackProbe on this track", chain, problems
  end

  local rig = { track = tr, chain = chain, problems = problems, strip = strip }

  if #probes == 1 then
    -- One probe still gives a usable post view; say so rather than refuse.
    rig.post = probes[1]
    rig.single = true
  else
    -- Order in the walk is chain order, so the first is pre and the last
    -- is post. If there are more than two, the outermost pair wins.
    rig.pre  = probes[1]
    rig.post = probes[#probes]
    if #probes > 2 then
      problems[#problems + 1] =
        ("%d probes found; using the first and the last"):format(#probes)
    end
    -- Sanity: the strip should sit between them.
    if strip then
      local sawPre, sawStrip = false, false
      for _, fx in ipairs(chain) do
        if fx.idx == rig.pre.idx then sawPre = true
        elseif strip and fx.idx == strip.idx then
          sawStrip = true
          if not sawPre then
            problems[#problems + 1] =
              "InfiniStrip comes before the first probe -- pre/post are the wrong way round"
          end
        elseif fx.idx == rig.post.idx and not sawStrip then
          problems[#problems + 1] =
            "the second probe comes before InfiniStrip -- nothing is measuring the output"
        end
      end
    end
  end

  return rig
end

----------------------------------------------------------
-- arming
----------------------------------------------------------

-- Writing a JSFX slider costs a parameter set, nothing more: no chain
-- rebuild, no plugin instantiation, no audio glitch.
--
-- THE TRACK POINTER IS CHECKED, NOT ASSUMED. disarm() is called from the
-- panel's atexit, and on a REAPER shutdown the project -- and every
-- MediaTrack in it -- can already be gone by the time that runs. Writing a
-- slider to a freed track is what threw
--   "bad argument #1 to 'TrackFX_SetParam' (MediaTrack expected)"
-- in everyone's face on the way out.
local function setSlider(tr, fx, param, value01)
  if not fx or not tr then return end
  if not r.ValidatePtr2(0, tr, "MediaTrack*") then return end
  pcall(r.TrackFX_SetParam, tr, fx.idx, param, value01)
end

function M.arm(rig)
  if not rig then return end
  setSlider(rig.track, rig.pre,  M.P_ROLE, 0)
  setSlider(rig.track, rig.post, M.P_ROLE, 1)
  setSlider(rig.track, rig.pre,  M.P_PUBLISH, 1)
  setSlider(rig.track, rig.post, M.P_PUBLISH, 1)
end

function M.disarm(rig)
  if not rig then return end
  setSlider(rig.track, rig.pre,  M.P_PUBLISH, 0)
  setSlider(rig.track, rig.post, M.P_PUBLISH, 0)
end

----------------------------------------------------------
-- the comparison track
--
-- Its POST probe is pointed at CMP_BASE and told to publish, so two
-- tracks are producing spectra at once. Nothing else about it changes,
-- and its own pre probe stays idle: the masking overlay wants the track's
-- output, not the response of its plugins.
--
-- ITS ROLE IS PUT BACK ON RELEASE. A probe left saying "Comparison" would
-- keep writing to CMP_BASE when that track later became the selected one,
-- so the panel would show it masking itself.
----------------------------------------------------------

function M.armCompare(rig)
  if not rig or not rig.post then return false end
  setSlider(rig.track, rig.post, M.P_ROLE, M.ROLE_COMPARE)
  setSlider(rig.track, rig.post, M.P_PUBLISH, 1)
  return true
end

function M.releaseCompare(rig)
  if not rig or not rig.post then return end
  setSlider(rig.track, rig.post, M.P_PUBLISH, 0)
  setSlider(rig.track, rig.post, M.P_ROLE, M.ROLE_POST)
end

----------------------------------------------------------
-- gmem map, shared with TS_TrackProbe.jsfx
----------------------------------------------------------

M.gmem = {
  NAMESPACE  = "TS_TA_Mem",
  CTRL_EPOCH = 64,
  CTRL_FFT   = 65,
  CTRL_SLICE = 66,
  CTRL_BEAT  = 67,
  CTRL_MEAS  = 68,   -- 0 off, 1 accumulate for one capture, 2 running average
  CTRL_TAU   = 69,   -- running-average time constant, ms
  CTRL_SMOO  = 70,   -- response smoothing width in octaves, 0 = none

  PRE_BASE   = 0x10000,
  POST_BASE  = 0x20000,
  -- Written by the POST probe of whatever track the panel is comparing
  -- against, with its Position set to 2. Only ever one comparison track:
  -- the masking overlay is between the track you are looking at and the
  -- one you picked, which is the scope that was asked for.
  CMP_BASE   = 0x30000,

  H_SEQ = 0, H_RMS = 1, H_PEAK = 2, H_SRATE = 3, H_NBINS = 4, H_FFTSZ = 5,
  H_SLICE = 6, H_EPOCHACK = 7, H_CUR = 8, H_COLS = 9, H_BLOCKS = 10,
  H_ROLE = 11, H_NCH = 12, H_PKL = 13, H_PKR = 14,

  -- RESERVED, NOT PUBLISHED. The probe used to write a per-bin spectrum
  -- and a per-bin average here -- about two thousand gmem writes a frame,
  -- each -- and nothing read either one. The panel reads OFF_BAND and
  -- OFF_SCOPE. Kept in the map so nothing else claims the regions, and so
  -- an archived measurement tool that expects them finds zeros rather than
  -- something plausible and stale.
  OFF_SPEC  = 64,
  OFF_AVG   = 2048,
  OFF_SCOPE = 4096,
  H_AVGN    = 15,

  -- The log-spaced summary the probes publish, so the panel does not have
  -- to read a thousand bins and reduce them itself every frame.
  --   stride 4:  0 display dB | 1 average dB | 2 response dB | 3 excitation dB
  -- Fields 2 and 3 are written by the POST probe only.
  H_BANDN   = 16,
  H_BANDLO  = 17,
  H_BANDHI  = 18,
  OFF_BAND  = 16384,
  BAND_STRIDE = 4,
}

-- Ask the probes for a running average of the spectrum, which is what makes
-- a live measured response possible: the difference between the two probes'
-- averages IS the magnitude response of whatever sits between them, without
-- reading a single plugin parameter.
--   tauMs  how long the average remembers. Short follows knob moves and is
--          noisy; long is smooth and lags.
function M.measureLive(tauMs, smoothOctaves)
  r.gmem_write(M.gmem.CTRL_TAU, tauMs or 1000)
  r.gmem_write(M.gmem.CTRL_SMOO, smoothOctaves or 0)
  r.gmem_write(M.gmem.CTRL_MEAS, 2)
end

-- The counterpart to measureLive. The panel leaves the running average on
-- for as long as it is open, so nothing here calls this -- it is kept so a
-- caller that arms the probes can also put them back.
function M.measureOff()
  r.gmem_write(M.gmem.CTRL_MEAS, 0)
end

function M.attach()
  r.gmem_attach(M.gmem.NAMESPACE)
end

-- Make both probes restart their windows on the same block, so column n of
-- pre and column n of post describe the same audio.
-- The counter is SEEDED FROM SHARED MEMORY, not from zero. A script that
-- starts fresh and counts 1, 2, 3 can write an epoch the probes already
-- acknowledged in a previous run of the same script, and a caller waiting
-- for the acknowledgement would be satisfied instantly by a stale one.
local epoch = nil
function M.resync()
  if not epoch then
    local v = tonumber(r.gmem_read(M.gmem.CTRL_EPOCH))
    epoch = (v and v == v and v >= 0) and v or 0
  end
  epoch = epoch + 1
  r.gmem_write(M.gmem.CTRL_EPOCH, epoch)
  return epoch
end

function M.setAnalysis(fftSize, sliceSamples)
  if fftSize then r.gmem_write(M.gmem.CTRL_FFT, fftSize) end
  if sliceSamples then r.gmem_write(M.gmem.CTRL_SLICE, sliceSamples) end
end

return M
