-- @noindex
-- Not a package of its own: installed by TS_ChannelView.lua's @provides.
--[[
  TS_CV_FXButtons.lua -- action-bar buttons that add a plugin or an FX
  chain, without an "Insert FX" action in REAPER's Action List.

  The button's command is ChannelView's own: "_TSCV_FX:<ident>" for a
  plugin (the identifier REAPER's EnumInstalledFX gives it, the one
  TrackFX_AddByName takes), "_TSCV_CHAIN:<path>" for an .RfxChain (its
  path under the FXChains folder). "|", ";", "~" and "%" in them are
  written as %7C, %3B, %7E and %25, so they can't break the bar's stored
  line or the web companion's commands.

  A click adds it to every selected track (the last touched one when none
  is): after the plugin selected in ChannelView on that track, else at the
  end of the chain -- never ahead of the TS_CV Trimmer, the pre probe or
  the modulators, never after the post probe. Its window stays closed;
  ChannelView's panel shows it. On the selected plugin's track the new
  one becomes the selected plugin, so clicks in a row add in that order.

  The selected plugin: the panel last clicked in ChannelView, kept in
  ExtState (not saved), so the toolbars window, the TCP and the web
  companion all add after the same one.
--]]

local FB = {}

FB.FX, FB.CHAIN = "_TSCV_FX:", "_TSCV_CHAIN:"
local EXT, SEL_KEY = "TS_ChannelView", "sel_fx"

-- ---------------------------------------------------------------------
-- pure
-- ---------------------------------------------------------------------

function FB.enc(s)
  return (s:gsub("[%%|;~]", function(c) return ("%%%02X"):format(c:byte()) end))
end
function FB.dec(s)
  return (s:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end))
end

function FB.fx_cmd(ident) return FB.FX .. FB.enc(ident) end
function FB.chain_cmd(rel) return FB.CHAIN .. FB.enc(rel) end

-- "fx" or "chain", and what it adds; nil for anything else.
function FB.kind(it)
  if not it or it.menu or it.sep or type(it.cmd) ~= "string" then return nil end
  if it.cmd:sub(1, #FB.FX) == FB.FX then return "fx", FB.dec(it.cmd:sub(#FB.FX + 1)) end
  if it.cmd:sub(1, #FB.CHAIN) == FB.CHAIN then return "chain", FB.dec(it.cmd:sub(#FB.CHAIN + 1)) end
  return nil
end

-- What a plugin is called on a button: its name without the format and
-- the developer ("VST3: Pro-Q 3 (FabFilter)" -> "Pro-Q 3"); a chain, its
-- file name.
function FB.short(kind, what)
  if kind == "chain" then
    local f = what:match("([^\\/]+)$") or what
    return (f:gsub("%.[Rr][Ff][Xx][Cc][Hh][Aa][Ii][Nn]$", ""))
  end
  local s = what:gsub("^%w+:%s*", "")
  s = s:gsub("%s*%b()%s*$", ""):gsub("%s*%b()%s*$", "")
  s = s:match("([^\\/]+)$") or s                -- a JSFX's path
  s = s:gsub("%.jsfx$", "")
  return s
end

-- ChannelView's effect-type icon for a plugin, from its name and
-- REAPER's categories for it; nil when nothing fits.
local GUESS = {
  { "fx_deesser",    { "de%-?ess", "sibil", "pro%-ds" } },
  { "fx_multiband",  { "multiband", "multi%-band", "mb%-" } },
  { "fx_limiter",    { "limit", "maximi[sz]", "clipper" } },
  { "fx_gate",       { "gate", "expander" } },
  { "fx_transient",  { "transient" } },
  { "fx_comp",       { "comp", "dynamic", "leveler", "leveller", "opto", "fet", "1176", "la%-?2a", "vca" } },
  { "fx_eq",         { "%f[%w]eq", "eq%f[%W]", "equal", "pultec", "pro%-q" } },
  { "fx_amp",        { "%f[%w]amp", "amp%f[%W]", "cab%f[%W]", "cabinet" } },
  { "fx_reverb",     { "reverb", "verb", "plate", "hall", "room", "spring" } },
  { "fx_delay",      { "delay", "echo" } },
  { "fx_mod",        { "chorus", "flang", "phas", "tremolo", "vibrato", "rotary", "modulat" } },
  { "fx_pitch",      { "pitch", "tune", "melodyne", "harmoni", "vocalign" } },
  { "fx_tape",       { "tape" } },
  { "fx_saturation", { "satur", "distort", "drive", "tube", "warmth", "fuzz", "exciter" } },
  { "fx_filter",     { "filter" } },
  { "fx_stereo",     { "stereo", "width", "imager", "spread" } },
  { "fx_analyser",   { "analy", "meter", "scope", "spectrum", "loudness" } },
  { "fx_gain",       { "gain", "trim", "utility", "volume" } },
}
function FB.icon_for(kind, name, cats)
  if kind == "chain" then return "cv:fx_chain" end
  local n = (name or ""):lower()
  local fmt = n:match("^(%w+):")
  if fmt and fmt:sub(-1) == "i" then return "cv:fx_instrument" end   -- VSTi, VST3i, CLAPi, AUi...
  local hay = FB.short("fx", n) .. " " .. table.concat(cats or {}, " "):lower()
  if hay:find("instrument", 1, true) or hay:find("synth", 1, true) or hay:find("sampler", 1, true) then
    return "cv:fx_instrument"
  end
  for _, g in ipairs(GUESS) do
    for _, pat in ipairs(g[2]) do
      if hay:find(pat) then return "cv:" .. g[1] end
    end
  end
  return nil
end

-- A new button for a plugin picked in the browser (its entry) or a chain
-- (an entry from TS_CV_Chains' list).
function FB.fx_item(e)
  return { cmd = FB.fx_cmd(e.ident), icon = FB.icon_for("fx", e.name, e.cats) or "",
           label = e.short or FB.short("fx", e.name) }
end
function FB.chain_item(f)
  return { cmd = FB.chain_cmd(f.rel), icon = "cv:fx_chain", label = f.name }
end

-- Where a new plugin goes in a chain of top-level `names` (in order),
-- when nothing is selected: the end, before a post probe there; not
-- ahead of what has to stay first (`first`, the slot after the Trimmer,
-- the pre probe and the modulators).
function FB.end_gap(names, first)
  local n = #names
  local gap = n
  if n > 0 and (names[n] or ""):find("TS_TrackProbe", 1, true) and n - 1 >= (first or 0) then gap = n - 1 end
  return math.max(gap, first or 0)
end

-- ---------------------------------------------------------------------
-- the selected plugin
-- ---------------------------------------------------------------------

local sel_cache, sel_at = nil, -1

function FB.select(track, guid)
  if not track or not guid then return end
  local v = reaper.GetTrackGUID(track) .. " " .. guid
  reaper.SetExtState(EXT, SEL_KEY, v, false)
  sel_cache, sel_at = v, reaper.time_precise()
end

-- The selected plugin's GUID when it's on `track`, else nil.
function FB.selected(track)
  if not track then return nil end
  local now = reaper.time_precise()
  if now - sel_at > 0.2 then sel_cache, sel_at = reaper.GetExtState(EXT, SEL_KEY), now end
  local tg, g = (sel_cache or ""):match("^(%S+) (%S+)$")
  if tg and tg == reaper.GetTrackGUID(track) then return g end
  return nil
end

-- ---------------------------------------------------------------------
-- adding
-- ---------------------------------------------------------------------

local T, TR, TP
local function mods()
  T  = T  or require("TS_CV_FXTree")
  -- (the Trimmer is Pro; without it, what's needed here of it: telling one
  -- that's on a track, and the slot after the probes and the modulators)
  TR = TR or require("TS_CV_Edition").module("TS_CV_Trimmer") or {
    is = function(n) return type(n) == "string" and n:find("TS_CV Trimmer", 1, true) ~= nil end,
    slot_in = function(names, ara_first)
      local slot = (ara_first and #names > 0) and 1 or 0
      while slot < #names do
        local n = names[slot + 1] or ""
        if n:find("TS_TrackProbe", 1, true) or n:find("ChannelView Modulators", 1, true)
           or n:find("TS_CV_Learn", 1, true) then slot = slot + 1 else break end
      end
      return slot
    end,
  }
  TP = TP or require("TS_CV_Taps")
end

local function top_names(track)
  local names = {}
  for i = 0, (reaper.TrackFX_GetCount(track) or 0) - 1 do
    local ok, n = reaper.TrackFX_GetNamedConfigParm(track, i, "fx_name")
    if not (ok and n and n ~= "") then local _, nm = reaper.TrackFX_GetFXName(track, i, ""); n = nm end
    names[#names + 1] = n or ""
  end
  return names
end

-- Where to add on a track: the level (a container path, {} for the chain
-- itself) and the gap in it.
function FB.target(track)
  mods()
  local names = top_names(track)
  local first = TR.slot_in(names, TP.ara_first(track))
  if names[first + 1] and TR.is(names[first + 1]) then first = first + 1 end
  local g = FB.selected(track)
  if g then
    for _, fx in ipairs(T.collect(track)) do
      if fx.guid == g then
        local parent, gap = fx.parent_path or {}, (fx.index or 0) + 1
        if #parent == 0 then gap = math.max(gap, first) end
        return parent, gap
      end
    end
  end
  return {}, FB.end_gap(names, first)
end

-- The tracks a click adds to: the selected ones, else the last touched.
function FB.tracks()
  local out = {}
  for i = 0, reaper.CountSelectedTracks2(0, true) - 1 do out[#out + 1] = reaper.GetSelectedTrack2(0, i, true) end
  if #out == 0 then
    local t = reaper.GetLastTouchedTrack()
    if t then out[1] = t end
  end
  return out
end

local function chain_dir()
  local root = reaper.GetResourcePath()
  local sep = root:find("\\", 1, true) and "\\" or "/"
  return root .. sep .. "FXChains" .. sep
end

-- Adds a plugin (ident) or a chain (path under FXChains) to `track` at
-- `parent`/`gap`. Returns how many plugins went in.
local function add_one(track, kind, what, parent, gap)
  mods()
  local before = reaper.TrackFX_GetCount(track)
  if kind == "fx" then
    return T.add_into(track, what, parent, gap) and 1 or 0
  end
  -- a chain: REAPER adds one only at the end; its plugins are moved into
  -- place from there, one at a time, in order
  for _, name in ipairs({ what, chain_dir() .. what }) do
    reaper.TrackFX_AddByName(track, name, false, -1)
    if reaper.TrackFX_GetCount(track) > before then break end
  end
  local n = reaper.TrackFX_GetCount(track) - before
  if n <= 0 then return 0 end
  if not (#parent == 0 and gap >= before) then
    -- into the chain itself, each one moves up and the next is one on;
    -- into a container, each one leaves the top level and the next takes
    -- its place
    for k = 0, n - 1 do
      T.move(track, { (#parent == 0) and (before + k) or before }, parent, gap + k)
    end
  end
  return n
end

-- ChannelView's own plugins on a track, which replacing the FX leaves:
-- the probes, the Trimmer and ChannelView Modulators.
function FB.is_ours(name)
  mods()
  name = name or ""
  return name:find("TS_TrackProbe", 1, true) ~= nil
      or name:find("ChannelView Modulators", 1, true) ~= nil
      or name:find("TS_CV_Modulators", 1, true) ~= nil
      or TR.is(name)
end

-- Replaces the plugins on `track` with the chain `what` (a path under
-- FXChains). ChannelView's own stay (FB.is_ours) and the chain goes where
-- the plugins began, after the ones that stay first. The chain is loaded
-- before anything goes, so one that fails leaves the track as it was.
-- Returns how many plugins went in.
function FB.replace(track, what)
  mods()
  local old = {}
  local names = top_names(track)
  for i, n in ipairs(names) do
    if not FB.is_ours(n) then old[reaper.TrackFX_GetFXGUID(track, i - 1)] = true end
  end
  local before = #names
  local n = add_one(track, "chain", what, {}, before)
  if n <= 0 then return 0 end
  local new = {}
  for i = before, before + n - 1 do new[#new + 1] = reaper.TrackFX_GetFXGUID(track, i) end
  for i = reaper.TrackFX_GetCount(track) - 1, 0, -1 do
    if old[reaper.TrackFX_GetFXGUID(track, i)] then reaper.TrackFX_Delete(track, i) end
  end
  -- into place: after the probe, Trimmer and modulators that lead
  names = top_names(track)
  local first = TR.slot_in(names, false)
  if names[first + 1] and TR.is(names[first + 1]) then first = first + 1 end
  for k, g in ipairs(new) do
    for i = 0, reaper.TrackFX_GetCount(track) - 1 do
      if reaper.TrackFX_GetFXGUID(track, i) == g then
        if i ~= first + k - 1 then T.move(track, { i }, {}, first + k - 1) end
        break
      end
    end
  end
  return n
end

-- What an FX chain button does with the plugins already there (it.cm):
-- nil adds the chain, "replace" replaces them (FB.replace), "ask" asks
-- which at each click (its host asks, then calls FB.run with the answer).
FB.CM = { replace = true, ask = true }

-- The GUID of what's now at `gap` in `parent` (the first plugin added).
local function guid_at(track, parent, gap)
  mods()
  local path = {}
  for i, v in ipairs(parent) do path[i] = v end
  path[#path + 1] = gap
  local addr = T.addr_of(track, path)
  return addr and reaper.TrackFX_GetFXGUID(track, addr) or nil
end

-- A click on the button `it`. `mode`: "replace" for an FX chain to
-- replace the plugins, else it's added (nil takes the button's own,
-- it.cm; an unanswered "ask" adds). Returns how many tracks it went on.
function FB.run(it, mode)
  local kind, what = FB.kind(it)
  if not kind then return 0 end
  local tracks = FB.tracks()
  if #tracks == 0 then return 0 end
  local replace = kind == "chain" and (mode or it.cm) == "replace"
  local done = 0
  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)
  for _, tr in ipairs(tracks) do
    if replace then
      if FB.replace(tr, what) > 0 then done = done + 1 end
    else
      local had_sel = FB.selected(tr) ~= nil
      local parent, gap = FB.target(tr)
      local n = add_one(tr, kind, what, parent, gap)
      if n > 0 then
        done = done + 1
        if had_sel then
          local g = guid_at(tr, parent, gap + n - 1)
          if g then FB.select(tr, g) end
        end
      end
    end
  end
  reaper.PreventUIRefresh(-1)
  reaper.Undo_EndBlock((replace and "ChannelView: replace FX with " or "ChannelView: add ") .. FB.short(kind, what), -1)
  if done == 0 then
    reaper.MB((kind == "fx" and "Couldn't add the plugin\n\n" or "Couldn't load the FX chain\n\n") .. what,
      "ChannelView", 0)
  end
  return done
end

-- Lit: the plugin is on the first selected track (or the last touched).
-- Chains aren't lit. Read at most every half second per track.
local have_cache = {}
function FB.is_on(it)
  local kind, what = FB.kind(it)
  if kind ~= "fx" then return false end
  local tr = reaper.GetSelectedTrack2(0, 0, true) or reaper.GetLastTouchedTrack()
  if not tr then return false end
  local key = tostring(tr)
  local now = reaper.time_precise()
  local c = have_cache[key]
  if not c or now - c.t > 0.5 then
    local set = {}
    for _, n in ipairs(top_names(tr)) do set[FB.short("fx", n):lower()] = true end
    mods()
    for _, fx in ipairs(T.collect(tr)) do
      local ok, n = reaper.TrackFX_GetNamedConfigParm(tr, fx.addr, "fx_name")
      if ok and n then set[FB.short("fx", n):lower()] = true end
    end
    c = { t = now, set = set }
    have_cache[key] = c
  end
  return c.set[FB.short("fx", what):lower()] == true
end

-- What the button does, for its tooltip.
function FB.tip(it)
  local kind, what = FB.kind(it)
  if not kind then return nil end
  local name = FB.short(kind, what)
  if kind == "chain" and it.cm == "replace" then
    return "Replace the plugins with the FX chain " .. name .. "\n(the probes, Trimmer and Modulators stay)"
  elseif kind == "chain" and it.cm == "ask" then
    return "Add the FX chain " .. name .. "\nAsks: add it, or replace the plugins"
  end
  return (kind == "fx" and "Add " or "Add the FX chain ") .. name ..
         "\nAfter the selected plugin, else at the end of the chain"
end

return FB
