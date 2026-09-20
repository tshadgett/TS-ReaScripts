--========================================================
-- @noindex
-- @title TS_TA_Strip
-- @description Track Analyser -- read gain reduction from whatever reports it
-- @author Tim Shadgett (with Claude)
-- @version 1.0.0
-- MIT licence -- see LICENSE in the TS-ReaScripts repository.
--========================================================
--
-- Not a script you run. TS_TrackAnalyser requires this.
--
-- WHAT IS LEFT, AND WHAT WENT
--   This used to read the whole of InfiniStrip: every slot's Type, Mute and
--   Solo, the filter and EQ settings, the insert-slot parameters, and the
--   per-module Gate / Comp / Lim meters -- the last of those through a
--   measured meter law, a staleness test and a timed hold, because seventy
--   per cent of reads came back as an identical idle tuple.
--
--   The panel does not draw any of that any more. The response comes from
--   the probe pair, which measures the audio and is therefore right about
--   bypass, mute, insert slots and saturation without being told anything;
--   and reduction is drawn only from the VST3 route, which reports
--   decibels directly and needs no law, no staleness test and no hold.
--
--   So the parameter map, the meter laws, the slot reader and the module
--   meters have gone. What is here is the part that still runs: find every
--   plugin between the probes that reports reduction to the host, read it,
--   and say whether that plugin is actually switched on.
--
-- THE ONE MEASUREMENT WORTH KEEPING (2026-08-31, Pro-C 3 + InfiniStrip):
--   TrackFX_GetNamedConfigParm(tr, fx, "GainReduction_dB") answered on
--   every one of 159 samples and returns DECIBELS -- no scale to work out.
--   The parameter path returned a bare zero on 67% of frames. REAPER also
--   FORMATS the same parameter as 20*log10(v), which read "-0.44 dB" while
--   the compressor was pulling 26: read the value and apply the law, never
--   the text. InfiniStrip does not support the named route -- it fakes its
--   readout as an ordinary parameter -- so the parameter path stays as a
--   fallback, listed but not drawn.
--========================================================

local r = reaper
local M = {}

-- Bumped whenever something callers depend on changes, so a half-updated
-- install says so instead of dying on a nil call.
M.VERSION = 20

-- Normalised key for matching a plugin name against a law we have.
function M.key(s)
  return (s or ""):gsub("[^%w]", ""):lower()
end

----------------------------------------------------------
-- parameter map, built once per plugin instance
--
-- INDICES ARE NOT HARD-CODED. The names are stable strings, the indices
-- are not guaranteed to be, and a panel that silently reads the wrong
-- parameter is worse than one that fails.
----------------------------------------------------------

local cache = setmetatable({}, { __mode = "k" })

local function mapFor(tr, fx)
  local key = tostring(tr) .. ":" .. tostring(fx)
  local m = cache[key]
  if m then return m end
  m = {}
  local n = r.TrackFX_GetNumParams(tr, fx)
  for p = 0, n - 1 do
    local _, nm = r.TrackFX_GetParamName(tr, fx, p, "")
    if nm and nm ~= "" then m[nm] = p end
  end
  cache[key] = m
  return m
end

-- Keys are matched as substrings of the normalised plugin name, because
-- REAPER prefixes the format ("vst3") and the vendor decorates the rest.
M.grLaws = {
  { match = "pspinfinistrip", law = { name = "1 - gain", measured = true } },
}

-- Until a plugin has been swept, this is what gets used, and callers are
-- expected to say so rather than present it as measured.
M.grLawDefault = { name = "1 - gain", measured = false }

function M.grLawFor(fxName)
  local k = M.key(fxName)
  for _, e in ipairs(M.grLaws) do
    if k:find(e.match, 1, true) then return e.law end
  end
  return M.grLawDefault
end

-- Raw reported value to decibels of reduction.
function M.grFromLaw(v, law)
  if not v or v <= 0 then return 0 end
  local name = law and law.name or "1 - gain"
  if name == "gain" then
    -- A plugin that reports the gain it is applying rather than the
    -- reduction: 1.0 means untouched.
    return v >= 0.99999 and 0 or -20 * math.log(v, 10)
  end
  if v >= 0.99999 then return 100 end
  return -20 * math.log(1 - v, 10)
end

----------------------------------------------------------
-- THE ROUTE, IN ORDER OF PREFERENCE
--
-- Measured 2026-08-31 with Pro-C 3 and InfiniStrip on one track:
--
--   TrackFX_GetNamedConfigParm(tr, fx, "GainReduction_dB")
--     answers on Pro-C 3 and returns DECIBELS directly -- no law, no
--     calibration, no meter scale to work out. It answered on every one of
--     159 samples with a sane value, where the parameter path returned a
--     bare zero on 67% of frames. This is REAPER's own route, the one
--     feeding the reduction meter on the mixer strip, and it works for any
--     plugin that reports through the proper VST3 mechanism.
--
--     It is not supported on InfiniStrip, which fakes its readout as an
--     ordinary parameter instead. So the parameter path stays as the
--     fallback, with its per-plugin law.
--
--   Neither: the probes measure it, which needs nothing from the plugin
--   at all -- they measured Pro-C's whole compression curve unaided.
----------------------------------------------------------

M.GR_KEY = "GainReduction_dB"

function M.reductionRoute(tr, fx)
  local ok, v = r.TrackFX_GetNamedConfigParm(tr, fx, M.GR_KEY)
  if ok and tonumber(v) then
    return { kind = "named", key = M.GR_KEY, label = M.GR_KEY .. " (dB, direct)" }
  end
  local p, nm = M.findReduction(tr, fx)
  if p then
    return { kind = "param", param = p, paramName = nm,
             label = ("parameter %d \"%s\""):format(p, nm) }
  end
  return nil
end

-- Decibels of reduction, or nil if this frame had nothing to say.
function M.readReduction(tr, fx, route, law)
  if not route then return nil end
  if route.kind == "named" then
    local ok, v = r.TrackFX_GetNamedConfigParm(tr, fx, route.key)
    local n = ok and tonumber(v)
    if not n then return nil end
    -- Reported as the gain change: negative while reducing.
    return math.max(0, -n)
  end
  local raw = r.TrackFX_GetParam(tr, fx, route.param)
  if not raw then return nil end
  return M.grFromLaw(raw, law)
end

-- Every parameter on an FX that looks like a reduction readout. REAPER
-- appears to give the VST3 one a consistent name of its own, so matching
-- on the name is not as fragile as it sounds -- but it is checked against
-- the name REAPER reports, not assumed.
function M.findReduction(tr, fx)
  local map = mapFor(tr, fx)
  local best, bestName
  for name, idx in pairs(map) do
    local low = name:lower()
    if low:find("gain-reduction", 1, true) or low:find("gain reduction", 1, true) then
      -- Prefer the plugin-wide readout over a per-module one.
      if not low:find(":") then return idx, name end
      best, bestName = best or idx, bestName or name
    end
  end
  return best, bestName
end

-- Is this FX actually processing? A bypassed plugin keeps reporting the
-- last reduction it applied -- REAPER's own meter does the same -- so the
-- value has to be discarded rather than believed. A bypassed CONTAINER
-- stops everything inside it just as effectively, and says nothing about
-- its children's own enabled flags, so both are checked.
function M.fxActive(tr, fx, parent)
  if parent and not r.TrackFX_GetEnabled(tr, parent) then return false end
  return r.TrackFX_GetEnabled(tr, fx)
end

-- Everything between the two probes that can report reduction, so a chain
-- carrying two compressors adds up rather than showing one of them.
--
-- Returns a second list too: reduction-reporting plugins OUTSIDE the probe
-- span. Those are deliberately not counted -- the waveform overlay only
-- describes what happens between the probes, so including reduction from
-- elsewhere would draw a curtain over audio it never touched. But silence
-- about them is how you spend twenty minutes wondering why your compressor
-- is missing, so they are reported.
function M.reductionSources(tr, chain, preIdx, postIdx)
  local out, outside, seen, past = {}, {}, false, false
  for _, fx in ipairs(chain) do
    if fx.idx == preIdx then seen = true
    elseif fx.idx == postIdx then past = true
    elseif not fx.isContainer and (not seen or past) then
      local route = M.reductionRoute(tr, fx.idx)
      if route then
        outside[#outside + 1] = { fx = fx.idx, plugin = fx.name, route = route,
                                  where = past and "after the post probe"
                                               or "before the pre probe" }
      end
    elseif seen and not past and not fx.isContainer then
      local route = M.reductionRoute(tr, fx.idx)
      if route then
        local p, nm = route.param, route.paramName
        -- A level meter on the same plugin is the reliable staleness test:
        -- a plugin passing audio cannot have one reading exactly zero. It
        -- also means a genuine return to no-reduction is recognised
        -- immediately instead of waiting out a hold.
        local lvl
        for name, idx in pairs(mapFor(tr, fx.idx)) do
          local low = name:lower()
          if low:find("meter", 1, true)
             and not low:find("gr", 1, true)
             and not low:find("reduction", 1, true) then
            lvl = lvl or idx
            if low:find("inmeter", 1, true) then lvl = idx end
          end
        end
        out[#out + 1] = {
          fx = fx.idx, parent = fx.container,
          route = route, param = p, paramName = nm, levelParam = lvl,
          plugin = fx.name, law = M.grLawFor(fx.names and fx.names[1] or fx.name),
          -- The named route reports decibels, so there is no law to get
          -- wrong and nothing to sweep.
          needsCal = (route.kind == "param"),
        }
      end
    end
  end
  return out, outside
end


return M
