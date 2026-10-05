-- @noindex
-- Not a package of its own: installed by TS_ChannelView.lua's @provides.
--[[
  TS_CV_Envelopes.lua -- automation lanes in the TCP.

  Two things:

  THE LANE PANEL. Every envelope REAPER is showing in a lane of its own
  under a track gets a panel in the TCP, level with that lane -- the
  envelope's own I_TCPY / I_TCPH, relative to its track, the same way the
  tracks themselves are placed (TS_CV_Arrange). A panel carries the name,
  the value the parameter has right now, a bar you can drag to set it,
  and three buttons: arm, bypass, and hide the lane. Right-click for the
  rest.

  THE ADD MENU. The "+" on a track opens a menu in the same shape as the
  Sends panel's: hover submenus, one for the track's own envelopes
  (volume, pan, mute) and one per plugin listing its parameters. A tick
  means the lane is showing; choosing a ticked one hides it again. A
  filter box at the top flattens everything into one list of matches, for
  the plugin with four hundred parameters.

  Arm, bypass and visibility aren't in REAPER's API as values you can set
  -- they're lines in the envelope's state chunk (ACT, VIS, ARM), so
  that's what is read and written. Reading a chunk isn't free, so each
  envelope's flags are cached against the project's change count: read
  once after anything changes, not sixty times a second. The chunk
  parsing is pure and tested offline.
--]]

local C  = require("TS_CV_Config")
local U  = require("TS_CV_Util")
local W  = require("TS_CV_Widgets")
local T  = require("TS_CV_FXTree")

local EN = {}
local ImGui

function EN.attach(imgui) ImGui = imgui end

-- ---------------------------------------------------------------------
-- pure: the state chunk's flags
-- ---------------------------------------------------------------------

-- { act, vis, lane, arm } from an envelope state chunk. Missing lines
-- read as REAPER's defaults (active, visible in its own lane, unarmed).
function EN.parse_flags(chunk)
  chunk = chunk or ""
  local act = chunk:match("\nACT (%-?%d+)")
  local v1, v2 = chunk:match("\nVIS (%-?%d+) (%-?%d+)")
  local arm = chunk:match("\nARM (%-?%d+)")
  return {
    act  = (act or "1") ~= "0",
    vis  = (v1 or "1") ~= "0",
    lane = (v2 or "1") ~= "0",
    arm  = (arm or "0") ~= "0",
  }
end

-- The chunk with one flag changed. `which` is "act", "vis", "lane" or
-- "arm". A line that isn't there is added after the first line (the
-- envelope's own tag), which is where REAPER keeps them.
function EN.set_flag(chunk, which, on)
  local b = on and "1" or "0"
  local function ensure(pat, line)
    if chunk:find(pat) then return end
    chunk = chunk:gsub("\n", "\n" .. line .. "\n", 1)
  end
  if which == "act" then
    ensure("\nACT %-?%d+", "ACT 1 -1")
    chunk = chunk:gsub("\nACT %-?%d+", "\nACT " .. b, 1)
  elseif which == "vis" then
    ensure("\nVIS %-?%d+ %-?%d+", "VIS 1 1 1")
    chunk = chunk:gsub("\nVIS %-?%d+", "\nVIS " .. b, 1)
  elseif which == "lane" then
    ensure("\nVIS %-?%d+ %-?%d+", "VIS 1 1 1")
    chunk = chunk:gsub("\nVIS (%-?%d+) %-?%d+", "\nVIS %1 " .. b, 1)
  elseif which == "arm" then
    ensure("\nARM %-?%d+", "ARM 0")
    chunk = chunk:gsub("\nARM %-?%d+", "\nARM " .. b, 1)
  end
  return chunk
end

-- The chunk with the lane's height set. 0 hands it back to REAPER's
-- default. LANEHEIGHT's second field is left as it was.
function EN.set_lane_height(chunk, h)
  h = math.max(0, math.floor(h + 0.5))
  if chunk:find("\nLANEHEIGHT %-?%d+") then
    return (chunk:gsub("\nLANEHEIGHT %-?%d+", "\nLANEHEIGHT " .. h, 1))
  end
  return (chunk:gsub("\n", "\nLANEHEIGHT " .. h .. " 0\n", 1))
end

-- ---------------------------------------------------------------------
-- flags, cached
-- ---------------------------------------------------------------------

local cache = {}      -- tostring(env) -> { cc, flags }

local function chunk_of(env)
  local ok, s = reaper.GetEnvelopeStateChunk(env, "", false)
  if ok then return s end
  return nil
end

function EN.flags(env)
  local cc = reaper.GetProjectStateChangeCount(0)
  local k = tostring(env)
  local c = cache[k]
  if c and c.cc == cc then return c.flags end
  local f = EN.parse_flags(chunk_of(env))
  cache[k] = { cc = cc, flags = f }
  return f
end

local function write_flags(env, pairs_list, undo)
  local s = chunk_of(env)
  if not s then return end
  for _, p in ipairs(pairs_list) do s = EN.set_flag(s, p[1], p[2]) end
  reaper.Undo_BeginBlock()
  reaper.SetEnvelopeStateChunk(env, s, false)
  reaper.Undo_EndBlock("ChannelView TCP: " .. undo, -1)
  cache[tostring(env)] = nil
  reaper.TrackList_AdjustWindows(false)
  reaper.UpdateArrange()
end

function EN.set_shown(env, on)
  if on then
    write_flags(env, { { "vis", true }, { "lane", true } }, "show envelope lane")
  else
    write_flags(env, { { "vis", false } }, "hide envelope lane")
  end
end
function EN.set_armed(env, on)  write_flags(env, { { "arm", on } }, on and "arm envelope" or "disarm envelope") end
function EN.set_active(env, on) write_flags(env, { { "act", on } }, on and "enable envelope" or "bypass envelope") end

-- Height, in REAPER pixels, without an undo point per pixel of a drag.
function EN.set_height(env, h)
  local c = chunk_of(env)
  if not c then return end
  reaper.SetEnvelopeStateChunk(env, EN.set_lane_height(c, h), false)
  reaper.TrackList_AdjustWindows(false)
end

-- Every envelope on the track that exists but isn't showing: what the
-- "+" menu offers to bring back.
function EN.hidden(track)
  local out = {}
  for i = 0, reaper.CountTrackEnvelopes(track) - 1 do
    local env = reaper.GetTrackEnvelope(track, i)
    if not EN.flags(env).vis then
      local _, name = reaper.GetEnvelopeName(env)
      out[#out + 1] = { env = env, name = name or "?" }
    end
  end
  return out
end

function EN.clear_points(env)
  reaper.Undo_BeginBlock()
  reaper.DeleteEnvelopePointRange(env, -1e12, 1e12)
  reaper.Envelope_SortPoints(env)
  reaper.Undo_EndBlock("ChannelView TCP: clear envelope", -1)
  reaper.UpdateArrange()
end

-- ---------------------------------------------------------------------
-- which envelope is what
-- ---------------------------------------------------------------------

-- The track's own envelopes the menu offers, by the tag REAPER files
-- each under in the track's state chunk, and the name of REAPER's own
-- "show" action for it (looked up by name -- see TS_CV_Actions -- with
-- the command id as the fallback). `pt`
-- gives the value of the starting point when the envelope has to be
-- built by hand. There is no solo envelope: REAPER doesn't automate solo.
-- Width is left out: its lanes didn't come up reliably from here.
local function tv(track, key, d) return reaper.GetMediaTrackInfo_Value(track, key) or d end
EN.TRACK_ENVS = {
  { name = "Volume", chunk = "<VOLENV2",
    action = "Track: Toggle track volume envelope visible", id = 40406,
    pt = function(tr) return tv(tr, "D_VOL", 1) end },
  { name = "Pan", chunk = "<PANENV2",
    action = "Track: Toggle track pan envelope visible", id = 40407,
    pt = function(tr) return -tv(tr, "D_PAN", 0) end },
  { name = "Mute", chunk = "<MUTEENV", shape = 1,
    action = "Track: Toggle track mute envelope visible", id = 40867,
    pt = function(tr) return (tv(tr, "B_MUTE", 0) > 0.5) and 0 or 1 end },
  { name = "Trim Volume", chunk = "<VOLENV3",
    action = "Track: Toggle track trim envelope visible", id = 42020,
    pt = function() return 1 end },
  { name = "Volume (Pre-FX)", chunk = "<VOLENV",
    action = "Track: Toggle track pre-FX volume envelope visible", id = 40408,
    pt = function() return 1 end },
  { name = "Pan (Pre-FX)", chunk = "<PANENV",
    action = "Track: Toggle track pre-FX pan envelope visible", id = 40409,
    pt = function() return 0 end },
}

-- fx and param for an FX parameter envelope; -1, -1 for the track's own.
local function parent_of(env)
  if not reaper.Envelope_GetParentTrack then return -1, -1 end
  local ok, _, fx, p = pcall(reaper.Envelope_GetParentTrack, env)
  if ok and fx then return fx, p or -1 end
  return -1, -1
end

-- The envelopes under `track` that REAPER is drawing in lanes of their
-- own, in its order, with each one's offset and height in REAPER pixels
-- relative to the track's top. `tcph` is the track's own height: an
-- envelope inside it is drawn over the items, not in a lane.
function EN.lanes(track, tcph)
  local out = {}
  for i = 0, reaper.CountTrackEnvelopes(track) - 1 do
    local env = reaper.GetTrackEnvelope(track, i)
    local y = reaper.GetEnvelopeInfo_Value(env, "I_TCPY") or 0
    local h = reaper.GetEnvelopeInfo_Value(env, "I_TCPH") or 0
    if h > 0 and y >= tcph - 1 then
      local _, name = reaper.GetEnvelopeName(env)
      local fx, p = parent_of(env)
      out[#out + 1] = { env = env, tcpy = y, tcph = h, name = name or "?",
                        fx = fx, param = p, idx = i }
    end
  end
  return out
end

-- ---------------------------------------------------------------------
-- pure: writing a value into an envelope
-- ---------------------------------------------------------------------

-- Where a new value goes, given the envelope's point count and whether
-- a point already sits at the time being edited:
--   "first"   no points yet: one point at the start, which is a flat line
--   "only"    one point: move it, keeping the line flat
--   "move"    a point at the edit time: move it
--   "insert"  otherwise: a new point at the edit time
-- That is how an envelope lane's own fader behaves in REAPER: with no
-- points or one it sets the whole envelope, with more it edits the
-- value where you are.
function EN.write_plan(npoints, point_here)
  if npoints == 0 then return "first" end
  if npoints == 1 then return "only" end
  if point_here then return "move" end
  return "insert"
end

-- The edit time: the play position while playing, the edit cursor
-- otherwise -- where REAPER's own lane fader edits too.
local function edit_time()
  if (reaper.GetPlayState() & 1) == 1 then return reaper.GetPlayPosition() end
  return reaper.GetCursorPosition()
end

function EN.write_value(env, raw)
  local t = edit_time()
  local n = reaper.CountEnvelopePoints(env)
  local idx, here = -1, false
  if n > 1 then
    idx = reaper.GetEnvelopePointByTime(env, t)
    if idx >= 0 then
      local _, pt = reaper.GetEnvelopePoint(env, idx)
      here = pt and math.abs(pt - t) < 1e-4
    end
  end
  local plan = EN.write_plan(n, here)
  if plan == "first" then
    reaper.InsertEnvelopePoint(env, 0, raw, 0, 0, false, true)
  elseif plan == "only" then
    reaper.SetEnvelopePoint(env, 0, nil, raw, nil, nil, nil, true)
  elseif plan == "move" then
    reaper.SetEnvelopePoint(env, idx, nil, raw, nil, nil, nil, true)
  else
    reaper.InsertEnvelopePoint(env, t, raw, 0, 0, false, true)
  end
  reaper.Envelope_SortPoints(env)
  reaper.UpdateArrange()
end

-- How a lane's 0..1 bar maps onto the envelope's own values. nil for an
-- envelope whose range isn't known (the bar is then hidden).
local function mapping(track, L)
  if L.fx >= 0 then
    local _, mn, mx = reaper.TrackFX_GetParamEx(track, L.fx, L.param)
    mn, mx = mn or 0, mx or 1
    if mx <= mn then mn, mx = 0, 1 end
    return { to_raw   = function(v) return mn + v * (mx - mn) end,
             from_raw = function(r) return (r - mn) / (mx - mn) end }
  end
  local n = L.name
  if n:match("^Volume") or n:match("^Trim") then
    local mode = reaper.GetEnvelopeScalingMode(L.env)
    return { to_raw   = function(v) return reaper.ScaleToEnvelopeMode(mode, U.fader_to_vol(v)) end,
             from_raw = function(r) return U.vol_to_fader(reaper.ScaleFromEnvelopeMode(mode, r)) end,
             dflt = U.UNITY_POS }
  end
  if n:match("^Pan") or n:match("^Width") then
    -- Pan runs the "wrong" way inside the envelope on some builds; rather
    -- than trust either, REAPER is asked which side +0.5 prints as.
    local sign = 1
    if n:match("^Pan") then
      local t = reaper.Envelope_FormatValue(L.env, 0.5) or ""
      if t:find("L") then sign = -1 end
    end
    return { to_raw   = function(v) return sign * (v * 2 - 1) end,
             from_raw = function(r) return (sign * r + 1) * 0.5 end,
             dflt = n:match("^Pan") and 0.5 or 1.0, bipolar = true }
  end
  if n == "Mute" then
    return { toggle = true }
  end
  return nil
end

-- What a lane's bar shows and sets. Returns a table:
--   norm     0..1, or nil when there's no sensible bar
--   text     the value as REAPER would print it
--   set(v)   writes a 0..1 back (nil: read-only)
--   dflt     where a double-click goes
--   bipolar  fill from the middle
--   toggle   a two-state value: click flips it rather than dragging
--
-- An active envelope owns its parameter -- setting the parameter
-- directly is undone by the envelope a moment later, which is why the
-- bar has to write into the envelope itself (EN.write_value). A bypassed
-- envelope doesn't, so there the parameter is set directly.
function EN.value(track, L)
  local r = {}
  local t = edit_time()
  local _, raw = reaper.Envelope_Evaluate(L.env, t, 0, 0)
  raw = raw or 0
  local active = EN.flags(L.env).act
  local m = mapping(track, L)

  if L.fx >= 0 then
    local _, ft = reaper.TrackFX_GetFormattedParamValue(track, L.fx, L.param, "")
    r.text = ft
  else
    r.text = reaper.Envelope_FormatValue(L.env, raw)
  end
  if not m then return r end

  if m.toggle then
    -- Mute: flip whatever the envelope says, whichever way round its
    -- values run.
    local on = raw > 0.5
    r.norm, r.toggle = on and 1 or 0, true
    r.set = function()
      if active then EN.write_value(L.env, on and 0 or 1)
      else reaper.SetMediaTrackInfo_Value(track, "B_MUTE",
             ((reaper.GetMediaTrackInfo_Value(track, "B_MUTE") or 0) > 0.5) and 0 or 1) end
    end
    return r
  end

  r.dflt, r.bipolar = m.dflt, m.bipolar
  r.norm = math.max(0, math.min(1, m.from_raw(raw)))
  r.set = function(v)
    if active then EN.write_value(L.env, m.to_raw(v)) end
    -- And the parameter itself, so it moves now rather than at the
    -- envelope's next evaluation (and so a bypassed lane works at all).
    if L.fx >= 0 then
      reaper.TrackFX_SetParamNormalized(track, L.fx, L.param, v)
    elseif L.name == "Volume" then
      reaper.SetMediaTrackInfo_Value(track, "D_VOL", U.fader_to_vol(v))
    elseif L.name == "Pan" then
      reaper.SetMediaTrackInfo_Value(track, "D_PAN", v * 2 - 1)
    elseif L.name == "Width" then
      reaper.SetMediaTrackInfo_Value(track, "D_WIDTH", v * 2 - 1)
    end
  end
  return r
end

-- ---------------------------------------------------------------------
-- showing and creating
-- ---------------------------------------------------------------------

function EN.track_env(track, def)
  return reaper.GetTrackEnvelopeByChunkName(track, def.chunk)
end

-- A new envelope block, visible in its own lane, with one point at the
-- start holding the track's current value -- REAPER drops an envelope
-- with no points at all when it reads the chunk back, which is why the
-- first version of this made nothing.
function EN.env_block(tag, value, shape)
  return ("%s\nACT 1 -1\nVIS 1 1 1\nLANEHEIGHT 0 0\nARM 0\nDEFSHAPE %d -1 -1\nPT 0 %.10g %d\n>\n")
    :format(tag, shape or 0, value or 0, shape or 0)
end

-- The track chunk with `block` added where REAPER keeps envelopes:
-- before the FX chain, else before the first item, else at the end.
function EN.insert_env_block(chunk, block)
  for _, tag in ipairs({ "\n<FXCHAIN", "\n<ITEM" }) do
    local i = chunk:find(tag, 1, true)
    if i then return chunk:sub(1, i) .. block .. chunk:sub(i + 1) end
  end
  local j = chunk:match("^.*()\n>%s*$")
  if j then return chunk:sub(1, j) .. block .. chunk:sub(j + 1) end
  return chunk
end

-- Creates a track envelope that doesn't exist yet by adding it to the
-- track's state chunk. The API has no call for this, and REAPER's own
-- "toggle envelope visible" actions differ between versions; the chunk
-- is the one thing that doesn't.
function EN.create_track_env(track, def)
  local ok, ch = reaper.GetTrackStateChunk(track, "", false)
  if not ok or type(ch) ~= "string" then return nil end
  reaper.Undo_BeginBlock()
  reaper.SetTrackStateChunk(track, EN.insert_env_block(ch,
    EN.env_block(def.chunk, def.pt and def.pt(track) or 0, def.shape)), false)
  reaper.Undo_EndBlock("ChannelView TCP: add " .. def.name:lower() .. " envelope", -1)
  reaper.TrackList_AdjustWindows(false)
  reaper.UpdateArrange()
  return EN.track_env(track, def)
end

-- Shows a track envelope, creating it if it doesn't exist. REAPER's own
-- "toggle ... envelope visible" action first -- found by name, run on
-- this track alone, selection put back after -- since that builds the
-- envelope exactly as REAPER would; the chunk only if that found nothing.
-- Runs a Main action on `track` alone, putting the selection back after.
local function run_on_track(track, id, undo)
  local sel = {}
  for i = 0, reaper.CountSelectedTracks2(0, true) - 1 do
    sel[#sel + 1] = reaper.GetSelectedTrack2(0, i, true)
  end
  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)
  reaper.SetOnlyTrackSelected(track)
  reaper.Main_OnCommand(id, 0)
  reaper.Main_OnCommand(40297, 0)                 -- Track: Unselect all tracks
  for _, t in ipairs(sel) do
    if reaper.ValidatePtr2(0, t, "MediaTrack*") then reaper.SetTrackSelected(t, true) end
  end
  reaper.PreventUIRefresh(-1)
  reaper.Undo_EndBlock(undo, -1)
  reaper.TrackList_AdjustWindows(false)
  reaper.UpdateArrange()
end

-- The TRACK_ENVS entry an envelope is, or nil (an FX envelope, say).
function EN.def_for(track, env)
  if not track or not env then return nil end
  for _, def in ipairs(EN.TRACK_ENVS) do
    if EN.track_env(track, def) == env then return def end
  end
  return nil
end

local function action_id(def)
  if not def or not def.action then return nil end
  return require("TS_CV_Actions").find(def.action, def.id)
end

-- Shows or hides any envelope. A track's own envelopes (volume, pan...)
-- go through REAPER's toggle action: REAPER does NOT honour a VIS line
-- written into their state chunk -- the envelope reads as visible and
-- still gets no lane -- whereas FX parameter envelopes do, and take the
-- chunk.
function EN.show(track, env, on)
  local def = EN.def_for(track, env)
  local id = action_id(def)
  if id then
    if EN.flags(env).vis ~= on then
      run_on_track(track, id, "ChannelView TCP: " .. (on and "show " or "hide ")
                              .. def.name:lower() .. " envelope")
      cache[tostring(env)] = nil
    end
    -- Shown over the items rather than in a lane of its own: the lane is
    -- a chunk flag that REAPER does honour, once the envelope is visible.
    if on and not EN.flags(env).lane then
      write_flags(env, { { "lane", true } }, "envelope in its own lane")
    end
  else
    EN.set_shown(env, on)
  end
end

-- Shows a track envelope, creating it if it doesn't exist: REAPER's own
-- toggle action creates and shows in one go; the chunk only when there
-- is no action for it.
function EN.show_track_env(track, def)
  local env = EN.track_env(track, def)
  if env then EN.show(track, env, true) return end
  local id = action_id(def)
  if id then
    run_on_track(track, id, "ChannelView TCP: show " .. def.name:lower() .. " envelope")
    env = EN.track_env(track, def)
  end
  if not env then env = EN.create_track_env(track, def) end
  if env then EN.show(track, env, true) end
end

function EN.show_fx_env(track, fx, p)
  reaper.Undo_BeginBlock()
  local env = reaper.GetFXEnvelope(track, fx, p, true)
  reaper.Undo_EndBlock("ChannelView TCP: add automation lane", -1)
  if env then
    local s = chunk_of(env)
    if s then
      s = EN.set_flag(EN.set_flag(EN.set_flag(s, "vis", true), "lane", true), "act", true)
      reaper.SetEnvelopeStateChunk(env, s, false)
      cache[tostring(env)] = nil
    end
  end
  reaper.TrackList_AdjustWindows(false)
  reaper.UpdateArrange()
end

local function shown(env)
  return env ~= nil and EN.flags(env).vis
end

-- ---------------------------------------------------------------------
-- the add menu
-- ---------------------------------------------------------------------

local st = { req = nil, track = nil, fx = nil, filter = "", focus = false,
             lane_req = nil, lane = nil }

function EN.open_menu(track) st.req = track end

local function fx_label(f)
  local n = U.fx_label(f)
  if f.depth and f.depth > 0 then n = ("  "):rep(f.depth) .. n end
  return n
end

local function param_name(track, fx, p)
  local _, n = reaper.TrackFX_GetParamName(track, fx, p, "")
  return n or ("Param " .. (p + 1))
end

local function toggle_fx(track, fx, p)
  local env = reaper.GetFXEnvelope(track, fx, p, false)
  if shown(env) then EN.set_shown(env, false) else EN.show_fx_env(track, fx, p) end
end

local function toggle_track(track, def)
  local env = EN.track_env(track, def)
  if shown(env) then EN.show(track, env, false) else EN.show_track_env(track, def) end
end

local MAX_MATCHES = 200

function EN.draw_menu(ctx)
  if st.req then
    st.track, st.req = st.req, nil
    st.fx = T.collect(st.track)
    st.filter, st.focus = "", true
    ImGui.OpenPopup(ctx, "tcp_auto")
  end
  if not ImGui.BeginPopup(ctx, "tcp_auto") then return end
  local tr = st.track
  if not tr or not reaper.ValidatePtr2(0, tr, "MediaTrack*") then
    ImGui.CloseCurrentPopup(ctx)
    ImGui.EndPopup(ctx)
    return
  end

  ImGui.TextDisabled(ctx, "Automation lanes")
  if st.focus then ImGui.SetKeyboardFocusHere(ctx); st.focus = false end
  ImGui.SetNextItemWidth(ctx, 220)
  -- Enter toggles the first match, as a click on it would
  local _, v = ImGui.InputTextWithHint(ctx, "##autoflt", "filter parameters\u{2026}", st.filter)
  local flt_enter = (ImGui.IsItemDeactivated(ctx) and (ImGui.IsKeyPressed(ctx, ImGui.Key_Enter) or ImGui.IsKeyPressed(ctx, ImGui.Key_KeypadEnter)))
  st.filter = v
  local first_hit
  ImGui.Separator(ctx)

  local flt = U.trim(st.filter):lower()
  if flt == "" then
    -- Lanes that were hidden come back from here: listed first, since
    -- that is usually why you opened the menu.
    local hid = EN.hidden(tr)
    if #hid > 0 then
      ImGui.TextDisabled(ctx, "Hidden lanes")
      for i, hl in ipairs(hid) do
        if ImGui.MenuItem(ctx, "   Show " .. hl.name .. "##hid" .. i) then
          EN.show(tr, hl.env, true)
        end
      end
      if #hid > 1 and ImGui.MenuItem(ctx, "   Show all") then
        for _, hl in ipairs(hid) do EN.show(tr, hl.env, true) end
      end
      ImGui.Separator(ctx)
    end
    if ImGui.BeginMenu(ctx, "Track") then
      for _, def in ipairs(EN.TRACK_ENVS) do
        local env = EN.track_env(tr, def)
        if ImGui.MenuItem(ctx, def.name, nil, shown(env)) then toggle_track(tr, def) end
      end
      ImGui.EndMenu(ctx)
    end
    if #st.fx > 0 then ImGui.Separator(ctx) end
    for i, f in ipairs(st.fx) do
      if ImGui.BeginMenu(ctx, fx_label(f) .. "##autofx" .. i) then
        local n = reaper.TrackFX_GetNumParams(tr, f.addr) or 0
        if n == 0 then ImGui.TextDisabled(ctx, "No parameters") end
        for p = 0, n - 1 do
          local env = reaper.GetFXEnvelope(tr, f.addr, p, false)
          if ImGui.MenuItem(ctx, param_name(tr, f.addr, p) .. "##ap" .. p, nil, shown(env)) then
            toggle_fx(tr, f.addr, p)
          end
        end
        ImGui.EndMenu(ctx)
      end
    end
    if #st.fx == 0 then ImGui.TextDisabled(ctx, "No plugins on this track") end
  else
    local shown_n = 0
    for _, def in ipairs(EN.TRACK_ENVS) do
      local env = EN.track_env(tr, def)
      if def.name:lower():find(flt, 1, true) then
        shown_n = shown_n + 1
        first_hit = first_hit or function() toggle_track(tr, def) end
        if ImGui.MenuItem(ctx, "Track \u{203A} " .. def.name, nil, shown(env)) then
          toggle_track(tr, def)
        end
      end
    end
    for i, f in ipairs(st.fx) do
      local fl = U.fx_label(f)
      local fx_hit = fl:lower():find(flt, 1, true)
      local n = reaper.TrackFX_GetNumParams(tr, f.addr) or 0
      for p = 0, n - 1 do
        if shown_n >= MAX_MATCHES then break end
        local pn = param_name(tr, f.addr, p)
        if fx_hit or pn:lower():find(flt, 1, true) then
          shown_n = shown_n + 1
          first_hit = first_hit or function() toggle_fx(tr, f.addr, p) end
          local env = reaper.GetFXEnvelope(tr, f.addr, p, false)
          if ImGui.MenuItem(ctx, ("%s \u{203A} %s##af%d_%d"):format(fl, pn, i, p), nil, shown(env)) then
            toggle_fx(tr, f.addr, p)
          end
        end
      end
    end
    if shown_n == 0 then ImGui.TextDisabled(ctx, "Nothing matches.") end
    if shown_n >= MAX_MATCHES then ImGui.TextDisabled(ctx, "\u{2026}more: narrow the filter.") end
    if flt_enter and first_hit then first_hit(); ImGui.CloseCurrentPopup(ctx) end
  end
  ImGui.EndPopup(ctx)
end

-- ---------------------------------------------------------------------
-- the lane panel
-- ---------------------------------------------------------------------

local function lane_menu(ctx)
  if st.lane_req then
    st.lane, st.lane_req = st.lane_req, nil
    ImGui.OpenPopup(ctx, "tcp_lane")
  end
  if not ImGui.BeginPopup(ctx, "tcp_lane") then return end
  local L = st.lane
  if not L or not reaper.ValidatePtr2(0, L.env, "TrackEnvelope*") then
    ImGui.CloseCurrentPopup(ctx)
    ImGui.EndPopup(ctx)
    return
  end
  local f = EN.flags(L.env)
  ImGui.TextDisabled(ctx, U.truncate(L.name, 40))
  ImGui.Separator(ctx)
  if ImGui.MenuItem(ctx, "Armed", nil, f.arm) then EN.set_armed(L.env, not f.arm) end
  if ImGui.MenuItem(ctx, "Active", nil, f.act) then EN.set_active(L.env, not f.act) end
  if ImGui.MenuItem(ctx, "Hide lane") then EN.show(L.track, L.env, false) end
  ImGui.Separator(ctx)
  if L.fx >= 0 and ImGui.MenuItem(ctx, "Open the plugin's window") then
    reaper.TrackFX_Show(L.track, L.fx, 3)
  end
  if ImGui.MenuItem(ctx, "Clear all points") then EN.clear_points(L.env) end
  ImGui.EndPopup(ctx)
end

function EN.draw_menus(ctx)
  EN.draw_menu(ctx)
  lane_menu(ctx)
end

-- Draws one lane's panel in the box x0..x1, y..y+h. `base` is the
-- track's colour, carried down the left edge; `id` keeps the widgets
-- apart.
function EN.draw_lane(ctx, dl, track, L, x0, y, x1, h, base, id)
  local f = EN.flags(L.env)
  L.track = track
  local y1 = y + h
  ImGui.DrawList_AddRectFilled(dl, x0, y, x1, y1 - 1, C.COL.strip_bg, 0)
  ImGui.DrawList_AddRectFilled(dl, x0, y, x0 + 3, y1 - 1, U.with_alpha(base, 0x99), 0)
  ImGui.DrawList_AddLine(dl, x0 + 3, y + 0.5, x1, y + 0.5, C.COL.panel_border, 1.0)

  -- Background: right-click for the lane menu. First, so the buttons
  -- and the bar sit on top of it.
  ImGui.SetCursorScreenPos(ctx, x0, y)
  W.allow_overlap(ctx)
  ImGui.InvisibleButton(ctx, "lanebg" .. id, math.max(1, x1 - x0), math.max(1, h - 1),
    ImGui.ButtonFlags_MouseButtonRight)
  if ImGui.IsItemClicked(ctx, ImGui.MouseButton_Right) then st.lane_req = L end

  local pad = C.TCP_PAD
  local _, th = ImGui.CalcTextSize(ctx, "Ag")
  -- The bottom edge: drag for the lane's height, double-click for
  -- REAPER's default. Without overlap, so it keeps the pixels it shares
  -- with the next lane or track, whatever is drawn after it.
  ImGui.SetCursorScreenPos(ctx, x0, y1 - C.TCP_EDGE * 0.5)
  ImGui.InvisibleButton(ctx, "laneedge" .. id, math.max(1, x1 - x0), C.TCP_EDGE)
  local ehov, eact = ImGui.IsItemHovered(ctx), ImGui.IsItemActive(ctx)
  if ehov or eact then ImGui.SetMouseCursor(ctx, ImGui.MouseCursor_ResizeNS) end
  if ImGui.IsItemActivated(ctx) then
    local _, my = ImGui.GetMousePos(ctx)
    st.resize = { env = L.env, h0 = L.tcph, my0 = my, scale = L.scale or 1, last = L.tcph }
  end
  if eact and st.resize and st.resize.env == L.env then
    local _, my = ImGui.GetMousePos(ctx)
    local nh = math.max(1, st.resize.h0 + (my - st.resize.my0) / st.resize.scale)
    if math.abs(nh - st.resize.last) >= 1 then
      EN.set_height(L.env, nh)
      st.resize.last = nh
    end
  end
  if ImGui.IsItemDeactivated(ctx) then st.resize = nil end
  if ehov and ImGui.IsMouseDoubleClicked(ctx, ImGui.MouseButton_Left) then
    EN.set_height(L.env, 0)
  end
  W.tip(ctx, "laneedge" .. id, "Resize",
    ehov and not eact, false)

  if h - 1 < th + 2 then return end

  -- Buttons, right to left: hide, bypass, arm.
  local bs = math.min(C.TCP_CHIP + 1, th + 2)
  local by = y + math.min(pad, (h - 1 - bs) * 0.5)
  local bx = x1 - pad - bs
  ImGui.SetCursorScreenPos(ctx, bx, by)
  local hit = ImGui.InvisibleButton(ctx, "lanex" .. id, bs, bs)
  local hov = ImGui.IsItemHovered(ctx)
  do
    local c = hov and C.COL.icon_hot or C.COL.icon
    local p = bs * 0.3
    ImGui.DrawList_AddLine(dl, bx + p, by + p, bx + bs - p, by + bs - p, c, 1.4)
    ImGui.DrawList_AddLine(dl, bx + bs - p, by + p, bx + p, by + bs - p, c, 1.4)
  end
  W.tip(ctx, "lanex" .. id, "Hide lane", hov, false)
  if hit then EN.show(track, L.env, false) end

  bx = bx - bs - 3
  local h1, d1 = W.state_icon(ctx, "lanea" .. id, "power", bx, by, bs, bs,
    not f.act, C.COL.bypass_on, f.act and "Bypass" or "Enable")
  if h1 or d1 then EN.set_active(L.env, not f.act) end

  bx = bx - bs - 3
  local h2, d2 = W.state_button(ctx, "lanearm" .. id, "A", bx, by, bs, bs,
    f.arm, C.COL.rec_on, f.arm and "Disarm" or "Arm")
  if h2 or d2 then EN.set_armed(L.env, not f.arm) end

  -- Name and value on the first line; the value right-aligned beside
  -- the buttons, the name taking what's left.
  local val = EN.value(track, L)
  local nl, nr = x0 + 3 + pad, bx - 5
  local vt = val.text or ""
  local vw = ImGui.CalcTextSize(ctx, vt)
  local ty = by + (bs - th) * 0.5
  if vw < (nr - nl) * 0.45 then
    ImGui.DrawList_AddText(dl, nr - vw, ty, C.COL.value, vt)
    nr = nr - vw - 6
  end
  local name = L.name
  local tw = ImGui.CalcTextSize(ctx, name)
  while tw > nr - nl and #name > 1 do
    name = name:sub(1, #name - 1)
    tw = ImGui.CalcTextSize(ctx, name .. ".")
    if tw <= nr - nl then name = name .. "." break end
  end
  ImGui.DrawList_AddText(dl, nl, ty, f.act and C.COL.header_text or C.COL.header_dim, name)
  W.tip(ctx, "lanename" .. id, L.name .. "\n" .. vt,
    ImGui.IsMouseHoveringRect(ctx, nl, ty, nr, ty + th) and ImGui.IsWindowHovered(ctx), false)

  -- The bar: drag (or click) to set, wheel to nudge, double-click for
  -- the default. Only when the lane is tall enough and there's a value
  -- the bar can honestly show.
  local bar_y = by + bs + 4
  local bar_h = 6
  if val.norm and val.set and bar_y + bar_h <= y1 - 3 then
    local bl, br = nl, x1 - pad
    ImGui.SetCursorScreenPos(ctx, bl, bar_y - 2)
    ImGui.InvisibleButton(ctx, "lanebar" .. id, math.max(1, br - bl), bar_h + 4)
    local bh_, ba = ImGui.IsItemHovered(ctx), ImGui.IsItemActive(ctx)
    local v = math.max(0, math.min(1, val.norm))
    if val.toggle then
      if ImGui.IsItemClicked(ctx, ImGui.MouseButton_Left) then val.set(v > 0.5 and 0 or 1) end
    else
      if ba then
        local mx = ImGui.GetMousePos(ctx)
        v = math.max(0, math.min(1, (mx - bl) / math.max(1, br - bl)))
        val.set(v)
        st.bar_edit = true
      elseif bh_ then
        local wh = W.control_wheel(ctx)
        if wh ~= 0 then
          local mods = ImGui.GetKeyMods(ctx)
          local step = 0.01 * (((mods & ImGui.Mod_Shift) ~= 0) and C.FINE_MULT or 1)
          v = math.max(0, math.min(1, v + wh * step))
          val.set(v)
          W.take_wheel()
        end
      end
      if bh_ and val.dflt and ImGui.IsMouseDoubleClicked(ctx, ImGui.MouseButton_Left) then
        val.set(val.dflt)
      end
    end
    -- One undo point for the whole drag, not one per frame of it.
    if ImGui.IsItemDeactivated(ctx) and st.bar_edit then
      st.bar_edit = false
      reaper.Undo_OnStateChange("ChannelView TCP: edit " .. L.name)
    end
    ImGui.DrawList_AddRectFilled(dl, bl, bar_y, br, bar_y + bar_h, C.COL.knob_track, 2.0)
    local fx0 = val.bipolar and (bl + (br - bl) * 0.5) or bl
    local fx1 = bl + (br - bl) * v
    local col = (f.act and C.COL.knob_fill or C.COL.header_dim)
    ImGui.DrawList_AddRectFilled(dl, math.min(fx0, fx1), bar_y, math.max(fx0, fx1),
      bar_y + bar_h, col, 2.0)
    if bh_ or ba then
      ImGui.DrawList_AddRect(dl, bl, bar_y, br, bar_y + bar_h, C.COL.knob_ring, 2.0, 0, 1.0)
    end
    W.tip(ctx, "lanebar" .. id, L.name .. "   " .. vt, bh_, ba)
  end
end

return EN
