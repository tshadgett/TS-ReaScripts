-- @noindex
-- Not a package of its own: installed by TS_ChannelView.lua's @provides.
--[[
  TS_CV_Util.lua -- small helpers shared by the rest of ChannelView.
  No ImGui in here; this file is pure Lua plus a few reaper.* calls, so
  most of it can be reasoned about (and unit-tested) on its own.
--]]

local U = {}

-- ---------------------------------------------------------------------
-- strings
-- ---------------------------------------------------------------------

function U.trim(s)
  return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Greedy word wrap, for the odd multi-line note in a menu. Menus have no
-- width to wrap against, so the column count is given rather than
-- measured -- these notes are fixed strings, not user text.
function U.wrap_note(text, cols)
  cols = cols or 52
  local out, line = {}, ""
  for word in tostring(text or ""):gmatch("%S+") do
    if line == "" then
      line = word
    elseif #line + 1 + #word <= cols then
      line = line .. " " .. word
    else
      out[#out + 1] = line
      line = word
    end
  end
  if line ~= "" then out[#out + 1] = line end
  return table.concat(out, "\n")
end

-- Shorten to `n` characters with a trailing ellipsis. Used for panel
-- headers and knob labels, where the cell width is fixed.
function U.truncate(s, n)
  s = tostring(s or "")
  if #s <= n then return s end
  if n <= 1 then return s:sub(1, n) end
  return s:sub(1, n - 1) .. "\u{2026}"
end

-- "VST3: DF-SMACK (Dawesome)" -> "DF-SMACK"
-- "VST: ReaComp (Cockos)"     -> "ReaComp"
-- "JS: Volume/Pan Smoother"   -> "Volume/Pan Smoother"
-- The leading format tag and the trailing "(Vendor)" tag are both
-- conventions REAPER bakes onto every FX display name. Stripping them is
-- what lets one saved layout apply to the same plugin regardless of which
-- format wrapper happens to be loaded.
function U.clean_fx_name(raw)
  if not raw or raw == "" then return "" end
  local s = raw
  s = s:gsub("^%s*[%u%d]+i?:%s*", "")          -- VST:, VST3:, JS:, CLAP:, AU:, VSTi:
  -- Up to three trailing groups: a channel suffix, a vendor, and the
  -- occasional variant tag -- "BM-COZY (UJAM) (32 out)" is all three.
  for _ = 1, 3 do
    local stripped = s:gsub("%s*%([^()]+%)%s*$", "")
    if stripped == s then break end
    s = stripped
  end
  return U.trim(s)
end

-- "VST3: Saturn 2 (FabFilter)" -> "VST3". REAPER prefixes every FX name
-- with its format, and instruments carry an "i" (VSTi, VST3i, CLAPi),
-- which is worth keeping -- it's the difference between the effect and
-- the instrument build of the same plugin.
function U.fx_format(name)
  local f = (name or ""):match("^%s*(%a[%w]*)%s*:")
  return f
end

-- "VST3: Saturn 2 (FabFilter)" -> "FabFilter".
--
-- REAPER bakes the vendor on as a trailing parenthetical, the same
-- convention its own Add-FX browser's DEVELOPER tab uses -- but for
-- multi-output instruments it appends a CHANNEL-CONFIG suffix AFTER that:
--
--     BM-COZY (UJAM) (32 out)
--     Komplete Kontrol (Native Instruments) (32 out)
--     Channel Mixer (4->8ch)
--
-- so "the last parenthetical" is wrong often enough to fill a developer
-- list with "32 out" and "4->8ch". Walk the trailing groups right to left
-- instead, skipping anything that reads as a channel or I/O descriptor,
-- and take the first real one. A name whose only trailing group is a
-- descriptor has no vendor at all, which is the honest answer.
local CHANNEL_DESC = {
  "^%d+%s*outs?$",          -- 32 out
  "^%d+%s*ins?$",           -- 4 in
  "^%d+%s*ch$",             -- 32ch
  "^%d+%s*ch%s*outs?$",
  "^%d+%s*%->%s*%d+%s*ch$", -- 4->8ch
  "^%d+%s*%->%s*%d+$",      -- 3->5
  "^%d+%.%d+$",             -- 5.1, 7.1
  "^%d+%s*x%s*%d+$",        -- 2x2
  "^mono$",
  "^stereo$",
  "^m/s$",
  "^mid/side$",
}

local function is_channel_desc(text)
  local t = text:lower():gsub("^%s+", ""):gsub("%s+$", "")
  for _, pat in ipairs(CHANNEL_DESC) do
    if t:match(pat) then return true end
  end
  return false
end

function U.fx_vendor(name)
  local s = name or ""
  for _ = 1, 4 do          -- no real name stacks more groups than this
    local head, group = s:match("^(.*)%(([^()]+)%)%s*$")
    if not group then return nil end
    if not is_channel_desc(group) then return U.trim(group) end
    s = head
  end
  return nil
end

-- The key a layout is filed under. Global per-plugin, so every instance
-- of the same plugin shares one layout by design.
function U.plugin_key(raw_name)
  local k = U.clean_fx_name(raw_name)
  if k == "" then k = U.trim(raw_name) end
  -- INI section names can't contain these.
  return (k:gsub("[%[%]\r\n]", ""))
end

-- ---------------------------------------------------------------------
-- INI (own parser: no SWS dependency, and the files stay hand-editable)
-- ---------------------------------------------------------------------

-- Returns { [section] = { [key] = value } }, plus an ordered list of
-- section names so a rewrite keeps the file's existing order.
function U.read_ini(path)
  local data, order = {}, {}
  local f = io.open(path, "r")
  if not f then return data, order end
  local cur = nil
  for line in f:lines() do
    line = line:gsub("\r$", "")
    local sect = line:match("^%s*%[(.-)%]%s*$")
    if sect then
      cur = sect
      if not data[cur] then data[cur] = {}; order[#order + 1] = cur end
    elseif cur then
      local k, v = line:match("^([^=;#][^=]-)%s*=%s*(.*)$")
      if k then data[cur][U.trim(k)] = v end
    end
  end
  f:close()
  return data, order
end

function U.write_ini(path, data, order, header)
  local f, err = io.open(path, "w")
  if not f then return false, err end
  if header then f:write(header, "\n") end

  local seen, names = {}, {}
  for _, s in ipairs(order or {}) do
    if data[s] and not seen[s] then seen[s] = true; names[#names + 1] = s end
  end
  local rest = {}
  for s in pairs(data) do if not seen[s] then rest[#rest + 1] = s end end
  table.sort(rest, function(a, b) return a:lower() < b:lower() end)
  for _, s in ipairs(rest) do names[#names + 1] = s end

  for _, s in ipairs(names) do
    f:write("[", s, "]\n")
    -- numeric-suffixed keys (Ctl0, Ctl1, ...) must come out in order
    local keys = {}
    for k in pairs(data[s]) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b)
      local pa, na = a:match("^(%a+)(%d+)$")
      local pb, nb = b:match("^(%a+)(%d+)$")
      if pa and pb and pa == pb then return tonumber(na) < tonumber(nb) end
      return a < b
    end)
    for _, k in ipairs(keys) do f:write(k, "=", tostring(data[s][k]), "\n") end
    f:write("\n")
  end
  f:close()
  return true
end

-- ---------------------------------------------------------------------
-- FX parameters
-- ---------------------------------------------------------------------

-- REAPER appends its own Wet / Bypass / Delta params to the end of every
-- FX's parameter list. They're real, addressable params (and worth
-- assigning deliberately), but they shouldn't crowd out the plugin's own
-- controls in an auto-generated default layout. Returns the count of the
-- plugin's OWN params, i.e. the index where REAPER's begin.
local BUILTIN_TAIL = { ["wet"] = true, ["bypass"] = true, ["delta"] = true }

function U.own_param_count(track, addr)
  local n = reaper.TrackFX_GetNumParams(track, addr)
  local cut = n
  for i = n - 1, math.max(0, n - 3), -1 do
    local _, nm = reaper.TrackFX_GetParamName(track, addr, i, "")
    if nm and BUILTIN_TAIL[nm:lower()] then cut = i else break end
  end
  return cut, n
end

-- {retval, step, smallstep, largestep, istoggle} -> a control type guess.
function U.guess_control_type(track, addr, param)
  local ok, _, _, _, istoggle = reaper.TrackFX_GetParameterStepSizes(track, addr, param)
  if ok and istoggle then return "toggle" end
  -- TrackFX_GetParamEx returns the VALUE first, then min/max/mid --
  -- there is no leading boolean, unlike most TrackFX_Get* calls.
  local _, minv, maxv = reaper.TrackFX_GetParamEx(track, addr, param)
  if minv and maxv and (maxv - minv) > 0 then
    local steps = select(2, reaper.TrackFX_GetParameterStepSizes(track, addr, param))
    if ok and steps and steps > 0 then
      local n = (maxv - minv) / steps
      if n >= 1 and n <= 24 then return "combo" end
    end
  end
  return "knob"
end

-- True when a param reads naturally as centred-at-zero, so the knob's
-- fill should grow out from 12 o'clock rather than from the minimum.
function U.guess_bipolar(name, track, addr, param)
  local n = (name or ""):lower()
  if n:find("pan") or n:find("balance") or n:find("trim") or n:find("tilt")
     or n:find("width") then
    return true
  end
  local _, minv, maxv = reaper.TrackFX_GetParamEx(track, addr, param)
  if minv and maxv and minv < 0 and maxv > 0 and math.abs(minv + maxv) < 1e-6 then
    return true
  end
  return false
end

function U.fmt_value(track, addr, param)
  local ok, s = reaper.TrackFX_GetFormattedParamValue(track, addr, param, "")
  if ok and s and s ~= "" then return s end
  local v = reaper.TrackFX_GetParamNormalized(track, addr, param)
  return string.format("%.2f", v or 0)
end

-- REAPER's "default" for a param isn't exposed; GetParamEx's midval is the
-- closest thing the API offers and is the plugin's own centre/detent for
-- most plugins. Used as the double-click reset target.
function U.param_mid_norm(track, addr, param)
  local _, minv, maxv, midv = reaper.TrackFX_GetParamEx(track, addr, param)
  if minv and maxv and midv and maxv > minv then
    return math.max(0, math.min(1, (midv - minv) / (maxv - minv)))
  end
  return 0.5
end

-- ---------------------------------------------------------------------
-- gain, dB, and the fader taper
-- ---------------------------------------------------------------------
-- REAPER's Lua API does not expose VAL2DB / DB2VAL / DB2SLIDER /
-- SLIDER2DB -- they are not there to call, so every conversion here is
-- our own. (Worth knowing before reaching for them: plenty of forum
-- snippets reference names the Lua API doesn't actually have.)

U.MIN_DB = -72        -- below this a fader reads as silence

function U.val2db(v)
  if not v or v <= 0 then return -math.huge end
  return 20 * math.log(v, 10)
end

function U.db2val(db)
  if not db or db <= U.MIN_DB then return 0 end
  return 10 ^ (db / 20)
end

-- A fader position of 0..1 to dB and back.
--
-- With no API taper available this is ours: unity at about 72% of travel
-- and a curve below it, so half travel lands near -14 dB rather than the
-- -36 a linear-in-dB fader would give. Linear-in-dB spends far too much of
-- its length on levels nobody mixes at.
--
-- This is a console-shaped curve, not a measurement of REAPER's own -- the
-- API doesn't expose that, so it can't be matched exactly. Adjust
-- U.UNITY_POS and U.CURVE if you want it to feel different.
-- Tunable: UNITY_POS is where 0 dB sits on the travel, CURVE shapes the
-- length below it. CURVE 1.38 puts half travel near -14 dB, which is
-- about where a console fader lands. Raising it pushes the quiet end
-- further down the throw, lowering it spreads the loud end out.
U.UNITY_POS = 0.72
U.MAX_DB    = 12
U.CURVE     = 1.38

function U.fader_to_db(p)
  p = math.max(0, math.min(1, p or 0))
  if p <= 0 then return -math.huge end
  if p >= U.UNITY_POS then
    return U.MAX_DB * (p - U.UNITY_POS) / (1 - U.UNITY_POS)
  end
  return U.MIN_DB * (1 - p / U.UNITY_POS) ^ U.CURVE
end

function U.db_to_fader(db)
  if not db or db == -math.huge or db <= U.MIN_DB then return 0 end
  if db >= 0 then
    return math.min(1, U.UNITY_POS + (1 - U.UNITY_POS) * (db / U.MAX_DB))
  end
  return U.UNITY_POS * (1 - (db / U.MIN_DB) ^ (1 / U.CURVE))
end

function U.vol_to_fader(v) return U.db_to_fader(U.val2db(v)) end
function U.fader_to_vol(p) return U.db2val(U.fader_to_db(p)) end

-- "+1.4", "-12.0", "-inf" -- the readout under a fader, send or meter.
--
-- db_str takes a figure that is ALREADY in dB (a meter reading, say), so
-- it doesn't have to be pushed back through db2val just to be printed;
-- db_text takes a VOLUME and converts.
function U.db_str(db)
  if not db or db <= U.MIN_DB then return "-inf" end
  return string.format("%+.1f", db)
end

function U.db_text(v)
  local db = U.val2db(v)
  if db <= U.MIN_DB then return "-inf" end
  return string.format("%+.1f", db)
end

-- ---------------------------------------------------------------------
-- colour
-- ---------------------------------------------------------------------

-- Black or white, whichever can actually be read on this background.
--
-- A mixer strip's header IS the track's colour, and the track's colour is
-- whatever the user picked -- pale yellow one row, near-black the next.
-- Rec. 709 luma rather than a plain average: the eye is far more
-- sensitive to green than to blue, so averaging calls a saturated blue
-- "light" and puts black text on it.
function U.contrast_text(col)
  if not col then return 0xffffffff end
  local r = ((col >> 24) & 0xff) / 255
  local g = ((col >> 16) & 0xff) / 255
  local b = ((col >> 8)  & 0xff) / 255
  local luma = 0.2126 * r + 0.7152 * g + 0.0722 * b
  return (luma > 0.55) and 0x121418ff or 0xf2f4f8ff
end

-- REAPER native colour -> ImGui 0xRRGGBBAA, or nil when unset.
function U.native_to_imgui(native, alpha)
  if not native or native == 0 then return nil end
  local r, g, b = reaper.ColorFromNative(native)
  return (r << 24) | (g << 16) | (b << 8) | (alpha or 0xff)
end

-- A track's custom colour, or nil when it has none. I_CUSTOMCOLOR carries
-- a 0x1000000 flag meaning "a colour was actually set"; without it the
-- low bits are stale and must not be used.
function U.track_colour(track, alpha)
  local v = reaper.GetMediaTrackInfo_Value(track, "I_CUSTOMCOLOR")
  if not v or v == 0 then return nil end
  v = math.floor(v)
  if (v & 0x1000000) == 0 then return nil end
  return U.native_to_imgui(v & 0xffffff, alpha)
end

function U.with_alpha(col, a)
  return (col & 0xffffff00) | (a & 0xff)
end

-- Perceptual-ish luminance, for picking readable text over a track colour.
function U.is_light(col)
  local r = (col >> 24) & 0xff
  local g = (col >> 16) & 0xff
  local b = (col >> 8) & 0xff
  return (0.299 * r + 0.587 * g + 0.114 * b) > 140
end

-- Pull a colour towards white by `amt` (0..1). Alpha is left alone.
function U.lighten(col, amt)
  amt = math.max(0, math.min(1, amt or 0.5))
  local r = (col >> 24) & 0xff
  local g = (col >> 16) & 0xff
  local b = (col >>  8) & 0xff
  local a =  col        & 0xff
  r = math.floor(r + (255 - r) * amt + 0.5)
  g = math.floor(g + (255 - g) * amt + 0.5)
  b = math.floor(b + (255 - b) * amt + 0.5)
  return (r << 24) | (g << 16) | (b << 8) | a
end

-- What marks the selected strip. `mode` is C.SEL_OUTLINE.
--
-- In "track" mode the outline is a lightened version of the track's own
-- colour: the row then reads as a set of coloured channels with one of
-- them lit, rather than a set of coloured channels and a blue one. It
-- has to be lightened rather than used straight, or on the selected
-- strip -- where the fill is already that colour -- there would be
-- nothing to see.
--
-- The palette colours arrive as arguments because this file knows
-- nothing about the palette, and is the better for it.
function U.sel_colour(mode, track_col, accent)
  if mode == "track" and track_col then return U.lighten(track_col, 0.55) end
  return accent
end

return U
