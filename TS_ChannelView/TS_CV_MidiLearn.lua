-- @noindex
-- TS_CV_MidiLearn.lua -- the MIDI learn drawer
--
-- A slim bar under ChannelView's header (the MIDI button in the header
-- opens it): the parameter last touched, in ChannelView or in a plugin's
-- own window, beside the MIDI control last moved, and a link button
-- between them. Linking writes REAPER's own MIDI learn on the parameter
-- (param.<p>.learn.midi1 / midi2 / mode / flags), the same binding
-- REAPER's learn window makes, so it shows there too and works without
-- ChannelView. Defaults: only while the track is selected, Relative 1
-- (127 = -1, 1 = +1); a control seen sweeping 0..127 is suggested as an
-- ordinary knob (Absolute) instead.
--
-- Lane shows (or makes) the parameter's automation lane; More... opens
-- REAPER's learn window for it (OSC, and anything this doesn't cover).
--
-- The control comes from REAPER's recent MIDI input history
-- (MIDI_GetRecentInputEvent): CCs (not the channel mode messages, 120..127),
-- notes, program change and pitch bend.

local C  = require("TS_CV_Config")
local U  = require("TS_CV_Util")
local W  = require("TS_CV_Widgets")
local M  = require("TS_CV_Mappings")
local EN = require("TS_CV_Envelopes")

local ML = {}
local ImGui
function ML.attach(imgui) ImGui = imgui end

ML.EXT = "midi_learn"
ML.ROW_H = 50
ML.MODES = {
  { 0, "Absolute" },
  { 1, "Relative 1 (127 = \u{2212}1, 1 = +1)" },
  { 2, "Relative 2 (63 = \u{2212}1, 65 = +1)" },
  { 3, "Relative 3 (65 = \u{2212}1, 1 = +1)" },
  { 4, "Toggle (on any value)" },
}
ML.MORE_CMD = 41144     -- FX: Set MIDI learn for last touched FX parameter

local st = {
  open = nil,
  target = nil,          -- { track, guid, p, t, src }
  ctl = nil,             -- { dev, status, cc, val, t, vals = {}, key }
  last_seq = nil,
  last_rp = nil,         -- REAPER's last touched, as a key
  mode = 1, mode_for = nil, picked = false,
  sel_only = true, soft = false,
  ever_midi = false,
}

local function ext_get(k, d)
  local v = reaper.GetExtState(C.EXT_SECT, k)
  if v == "" then return d end
  return v
end
local function ext_set(k, v) reaper.SetExtState(C.EXT_SECT, k, tostring(v), true) end

function ML.is_open()
  if st.open == nil then
    st.open = ext_get(ML.EXT, "0") == "1"
    st.sel_only = ext_get(ML.EXT .. "_sel", "1") == "1"
    st.soft = ext_get(ML.EXT .. "_soft", "0") == "1"
  end
  return st.open
end
function ML.set_open(v)
  st.open = v and true or false
  ext_set(ML.EXT, st.open and "1" or "0")
end
function ML.toggle() ML.set_open(not ML.is_open()) end

-- ---------------------------------------------------------------------
-- what was touched, what was moved
-- ---------------------------------------------------------------------

local function track_of(idx)
  if idx == nil then return nil end
  if idx < 0 then return reaper.GetMasterTrack(0) end
  return reaper.GetTrack(0, idx)
end

local function addr_of(track, guid)
  if not (track and guid) then return nil end
  local function walk(n, mk)
    for i = 0, n - 1 do
      local a = mk(i)
      if reaper.TrackFX_GetFXGUID(track, a) == guid then return a end
    end
  end
  local a = walk(reaper.TrackFX_GetCount(track), function(i) return i end)
  if a then return a end
  -- inside containers: REAPER's own last-touched gives the address
  -- directly, so this is only for the right-click route
  return nil
end

-- A parameter to put in the drawer: from a control's right-click (MIDI
-- learn...), or ChannelView's own controls as they're turned.
function ML.set_target(track, guid, addr, p, src)
  if not (track and guid and p) then return end
  st.target = { track = track, guid = guid, addr = addr, p = p, t = reaper.time_precise(), src = src or "cv" }
end
function ML.open_for(track, guid, addr, p)
  ML.set_target(track, guid, addr, p, "menu")
  ML.set_open(true)
end

-- ChannelView's own helpers: the track probes (which ChannelView and
-- Track Analyser write to as they measure, so REAPER keeps calling one of
-- their parameters last touched) and the hidden copies it learns on.
-- Their parameters never take the drawer's place.
ML.HELPERS = { "TS_TrackProbe", "TS_CV_Learn" }
local function is_helper(track, addr)
  -- the plugin's own name and file, so a renamed probe still counts
  local names = {}
  local pok, ok, n = pcall(reaper.TrackFX_GetFXName, track, addr, "")
  if pok and ok and n then names[#names + 1] = n end
  for _, k in ipairs({ "fx_name", "fx_ident" }) do
    local qok, gok, v = pcall(reaper.TrackFX_GetNamedConfigParm, track, addr, k)
    if qok and gok and v then names[#names + 1] = v end
  end
  for _, name in ipairs(names) do
    for _, h in ipairs(ML.HELPERS) do
      if name:find(h, 1, true) then return true end
    end
  end
  return false
end
ML._is_helper = is_helper

local function poll_touched()
  local key, track, addr, p
  if reaper.GetTouchedOrFocusedFX then
    local ok, tidx, iidx, _, fxi, parm = reaper.GetTouchedOrFocusedFX(0)
    if not ok or (iidx and iidx >= 0) then return end
    track, addr, p = track_of(tidx), fxi, parm
    key = ("%s:%s:%s"):format(tidx, fxi, parm)
  else
    local ok, trn, fxn, parm = reaper.GetLastTouchedFX()
    if not ok then return end
    if (fxn >> 16) & 0xff > 0 and fxn < 0x2000000 then return end  -- a take's FX
    track, addr, p = (trn == 0) and reaper.GetMasterTrack(0) or reaper.GetTrack(0, trn - 1), fxn, parm
    key = ("%s:%s:%s"):format(trn, fxn, parm)
  end
  if key == st.last_rp then return end
  local first = st.last_rp == nil
  st.last_rp = key
  if first and st.target then return end
  if not (track and addr and p and p >= 0) then return end
  if is_helper(track, addr) then return end
  local guid = reaper.TrackFX_GetFXGUID(track, addr)
  if guid then st.target = { track = track, guid = guid, addr = addr, p = p, t = reaper.time_precise(), src = "reaper" } end
end

-- The mode a control's values suggest: an endless encoder sends small
-- steps either side of 0 (1 / 127) or of 64 (63 / 65); a knob sweeps.
function ML.guess_mode(vals)
  if not vals or #vals < 3 then return nil end
  local lo, hi, mid, wide = 0, 0, 0, 0
  local seen = {}
  local n = 0
  for _, v in ipairs(vals) do
    if not seen[v] then seen[v] = true; n = n + 1 end
    if v >= 1 and v <= 15 then lo = lo + 1
    elseif v >= 113 and v <= 127 then hi = hi + 1
    elseif v >= 49 and v <= 79 and v ~= 64 then mid = mid + 1
    else wide = wide + 1 end
  end
  local total = #vals
  if n >= 12 then return 0 end                                     -- sweeping: a knob
  if lo + hi == total and lo > 0 and hi > 0 then return 1 end      -- 1 / 127
  if mid == total and n <= 8 then return 2 end                     -- 63 / 65
  if lo + hi == total and n <= 4 then return 1 end                 -- one way only so far
  return nil
end

-- What REAPER's own learn takes from an incoming message: CCs, notes,
-- program changes and pitch bend, as (status, number, value). A note-off
-- (or a note-on at velocity 0) is the same key let go: nil, so the key
-- stays the last control without its value dropping to 0. CC 120 to 127
-- are channel mode messages (All Notes Off and the like), which a
-- controller sends on its own -- a Pacer changing preset, say -- and are
-- never a control you moved. System messages aren't learnable.
function ML.control_of(buf)
  buf = buf or ""
  local s1, d1, d2 = buf:byte(1), buf:byte(2), buf:byte(3)
  if not (s1 and d1) then return nil end
  local kind = s1 & 0xF0
  if kind == 0xB0 then
    if not d2 or d1 >= 120 then return nil end
    return s1, d1, d2
  elseif kind == 0x90 then
    if not d2 or d2 == 0 then return nil end
    return s1, d1, d2
  elseif kind == 0xC0 then
    return s1, d1, d1
  elseif kind == 0xE0 then
    if not d2 then return nil end
    return s1, 0, d2
  end
  return nil
end

local function poll_midi()
  if not reaper.MIDI_GetRecentInputEvent then return end
  local evs = {}
  for i = 0, 63 do
    local seq, buf, _, dev = reaper.MIDI_GetRecentInputEvent(i)
    if not seq or seq == 0 then break end
    if st.last_seq and seq <= st.last_seq then break end
    evs[#evs + 1] = { seq = seq, buf = buf, dev = dev }
  end
  if #evs == 0 then
    if st.last_seq == nil then st.last_seq = 0 end
    return
  end
  local first = st.last_seq == nil
  st.last_seq = math.max(st.last_seq or 0, evs[1].seq)
  if first then return end           -- what came before the drawer opened
  st.ever_midi = true
  for i = #evs, 1, -1 do
    local s1, d1, d2 = ML.control_of(evs[i].buf)
    if s1 then
      local key = ("%d:%d:%d"):format(evs[i].dev or 0, s1, d1)
      if not (st.ctl and st.ctl.key == key) then
        st.ctl = { key = key, dev = evs[i].dev, status = s1, cc = d1, vals = {} }
      end
      st.ctl.val, st.ctl.t = d2, reaper.time_precise()
      local vs = st.ctl.vals
      vs[#vs + 1] = d2
      if #vs > 24 then table.remove(vs, 1) end
    end
  end
  -- a new control: its mode, unless one was picked for it by hand
  if st.ctl and st.mode_for ~= st.ctl.key then
    st.mode_for, st.picked = st.ctl.key, false
  end
  if st.ctl and not st.picked then
    -- a key or pad: Toggle (in Relative 1, velocity 127 would read as a
    -- step down); a CC: what its values look like
    local kind = st.ctl.status & 0xF0
    if kind == 0x90 then st.mode = 4
    elseif kind == 0xB0 then st.mode = ML.guess_mode(st.ctl.vals) or 1
    else st.mode = 0 end
  end
end

-- ---------------------------------------------------------------------
-- REAPER's learn on a parameter
-- ---------------------------------------------------------------------

local function cfg(track, addr, k)
  local ok, v = reaper.TrackFX_GetNamedConfigParm(track, addr, k)
  return ok and v or nil
end

-- { status, cc, mode, flags } or nil
function ML.binding(track, addr, p)
  local m1 = tonumber(cfg(track, addr, ("param.%d.learn.midi1"):format(p)) or "")
  local m2 = tonumber(cfg(track, addr, ("param.%d.learn.midi2"):format(p)) or "")
  if not m1 or m1 == 0 then return nil end
  return { status = m1, cc = m2 or 0,
           mode = tonumber(cfg(track, addr, ("param.%d.learn.mode"):format(p)) or "") or 0,
           flags = tonumber(cfg(track, addr, ("param.%d.learn.flags"):format(p)) or "") or 0 }
end

function ML.link(track, addr, p, status, cc, mode, flags)
  reaper.Undo_BeginBlock()
  local pre = ("param.%d.learn."):format(p)
  reaper.TrackFX_SetNamedConfigParm(track, addr, pre .. "midi1", tostring(status))
  reaper.TrackFX_SetNamedConfigParm(track, addr, pre .. "midi2", tostring(cc))
  reaper.TrackFX_SetNamedConfigParm(track, addr, pre .. "mode", tostring(mode))
  reaper.TrackFX_SetNamedConfigParm(track, addr, pre .. "flags", tostring(flags))
  reaper.Undo_EndBlock("ChannelView: MIDI learn", -1)
end

function ML.unlink(track, addr, p)
  reaper.Undo_BeginBlock()
  local pre = ("param.%d.learn."):format(p)
  reaper.TrackFX_SetNamedConfigParm(track, addr, pre .. "midi1", "0")
  reaper.TrackFX_SetNamedConfigParm(track, addr, pre .. "midi2", "0")
  reaper.Undo_EndBlock("ChannelView: remove MIDI learn", -1)
end

function ML.flags()
  return (st.sel_only and 1 or 0) | (st.soft and 2 or 0)
end

local function mode_name(m)
  for _, e in ipairs(ML.MODES) do if e[1] == m then return e[2] end end
  return ("mode %d"):format(m)
end
local function short_mode(m)
  return ({ [0] = "Absolute", "Relative 1", "Relative 2", "Relative 3", "Toggle" })[m] or ("mode " .. m)
end

local function cc_text(status, cc)
  status = status or 0xB0
  local ch = (status & 0x0F) + 1
  local kind = status & 0xF0
  if kind == 0x90 then return ("Note %d \u{00B7} ch %d"):format(cc or 0, ch) end
  if kind == 0xC0 then return ("Program change \u{00B7} ch %d"):format(ch) end
  if kind == 0xE0 then return ("Pitch bend \u{00B7} ch %d"):format(ch) end
  return ("CC %d \u{00B7} ch %d"):format(cc or 0, ch)
end
ML._cc_text = cc_text

local function dev_name(dev)
  if dev and reaper.GetMIDIInputName then
    local ok, nm = reaper.GetMIDIInputName(dev & 0xFFFF, "")
    if ok and nm and nm ~= "" then return nm end
  end
  return "MIDI"
end

-- ---------------------------------------------------------------------
-- the drawer
-- ---------------------------------------------------------------------

-- Height it takes at this width: one row, or two when the window is narrow.
function ML.height(w)
  if not ML.is_open() then return 0 end
  return (w < 900) and (ML.ROW_H * 2 - 6) or ML.ROW_H
end

local function valid_target()
  local tg = st.target
  if not tg then return nil end
  if not reaper.ValidatePtr2(0, tg.track, "MediaTrack*") then st.target = nil; return nil end
  if reaper.TrackFX_GetFXGUID(tg.track, tg.addr) ~= tg.guid then
    local a = addr_of(tg.track, tg.guid)
    if not a then st.target = nil; return nil end
    tg.addr = a
  end
  return tg
end

local function card(dl, x, y, w, h, live, edge)
  ImGui.DrawList_AddRectFilled(dl, x, y, x + w, y + h, C.COL.header_bg, 4.0)
  ImGui.DrawList_AddRect(dl, x + 0.5, y + 0.5, x + w - 0.5, y + h - 0.5, C.COL.panel_border, 4.0, 0, 1.0)
  if live then ImGui.DrawList_AddRectFilled(dl, x, y + 2, x + 3, y + h - 2, edge or C.COL.accent, 1.5) end
end

local function clip_text(ctx, t, w)
  if ImGui.CalcTextSize(ctx, t) <= w then return t end
  while #t > 1 and ImGui.CalcTextSize(ctx, t .. "\u{2026}") > w do t = t:sub(1, -2) end
  return t .. "\u{2026}"
end

-- Draws the drawer at the cursor, `w` wide; returns the height used.
function ML.draw(ctx, w)
  if not ML.is_open() then return 0 end
  poll_touched()
  poll_midi()
  local now = reaper.time_precise()
  local h = ML.height(w)
  local dl = ImGui.GetWindowDrawList(ctx)
  local x0, y0 = ImGui.GetCursorScreenPos(ctx)
  ImGui.DrawList_AddRectFilled(dl, x0, y0, x0 + w, y0 + h - 4, C.COL.panel_bg, 4.0)
  ImGui.DrawList_AddRect(dl, x0 + 0.5, y0 + 0.5, x0 + w - 0.5, y0 + h - 4.5, C.COL.panel_border, 4.0, 0, 1.0)
  local two = h > ML.ROW_H
  local ch = ML.ROW_H - 14
  local cy = y0 + 5

  local tg = valid_target()
  local bind = tg and ML.binding(tg.track, tg.addr, tg.p) or nil
  local ctl = st.ctl
  -- linked: what the parameter is linked to, until a control moves after
  -- it was touched (then that control is offered in its place)
  local show_bind = bind and (not ctl or (ctl.t or 0) < tg.t
                              or (ctl.status == bind.status and ctl.cc == bind.cc))
  local fresh = function(t) return t and now - t < 1.2 end

  -- Centred: the lane's +, the cards and the link (which unlinks when
  -- linked), then the mode and options, as one group in the middle of the
  -- bar -- clear of More... and the close button on the right. Narrow,
  -- two rows, each centred.
  local fh = ImGui.GetFrameHeight(ctx)
  local lr = 17
  local lw = 22
  local cw  = math.min(260, (w - 16 - lw - 8 - lr * 2 - 16) * 0.53)
  local cw2 = math.min(230, (w - 16 - lw - 8 - lr * 2 - 16) * 0.47)
  local mw = ImGui.CalcTextSize(ctx, "More\u{2026}") + 16
  local right_w = 22 + 8 + mw + 12
  local tail_w = show_bind and 0
                 or (220 + ImGui.CalcTextSize(ctx, "Only when its track is selected") + fh + 8)
  local pair_w = lw + 8 + cw + 8 + lr * 2 + 8 + cw2   -- the lane's +, then the cards
  local function centred(gw, room)
    local sx = x0 + (w - gw) * 0.5
    sx = math.min(sx, x0 + room - gw)
    return math.max(x0 + 8, sx)
  end
  local x, tail_x
  if two then
    x = centred(pair_w, w - 8)
    tail_x = centred(tail_w, w - right_w)
  else
    x = centred(pair_w + (tail_w > 0 and (10 + tail_w) or 0), w - right_w)
  end

  -- the parameter's automation lane: a + like the TCP's, left of its card
  -- (its room kept when nothing is touched, so the bar doesn't shift)
  if tg then
    local lane = EN.fx_lane(tg.track, tg.addr, tg.p)
    local shown = lane and lane.shown
    ImGui.SetCursorScreenPos(ctx, x, cy + (ch - lw) * 0.5)
    if W.icon_button(ctx, "##mllane", "plus", lw, shown,
        shown and "Hide automation lane" or "Add automation lane") then
      EN.toggle_fx_lane(tg.track, tg.addr, tg.p)
    end
  end
  x = x + lw + 8

  -- the parameter
  card(dl, x, cy, cw, ch, tg ~= nil and fresh(tg.t))
  W.push_small(ctx)
  if tg then
    local _, fxn = reaper.TrackFX_GetFXName(tg.track, tg.addr, "")
    local _, pn = reaper.TrackFX_GetParamName(tg.track, tg.addr, tg.p, "")
    local key = U.plugin_key(fxn)
    local shown = M.display_name(key, tg.p, nil, pn, false)
    local _, val = reaper.TrackFX_GetFormattedParamValue(tg.track, tg.addr, tg.p, "")
    ImGui.DrawList_AddText(dl, x + 10, cy + 4, C.COL.header_dim,
      clip_text(ctx, ("LAST TOUCHED \u{00B7} %s"):format(U.clean_fx_name(fxn):upper()), cw - 16))
    W.pop_small(ctx)
    local n = reaper.TrackFX_GetParamNormalized(tg.track, tg.addr, tg.p) or 0
    local bw = 40
    ImGui.DrawList_AddText(dl, x + 10, cy + 17, C.COL.header_text,
      clip_text(ctx, ("%s \u{00B7} %s"):format(shown, U.trim(val or "")), cw - 26 - bw))
    local bx, by = x + cw - bw - 10, cy + 24
    ImGui.DrawList_AddRectFilled(dl, bx, by, bx + bw, by + 4, C.COL.win_bg, 2)
    ImGui.DrawList_AddRectFilled(dl, bx, by, bx + bw * math.max(0, math.min(1, n)), by + 4, C.COL.accent, 2)
  else
    ImGui.DrawList_AddText(dl, x + 10, cy + 4, C.COL.header_dim, "LAST TOUCHED")
    W.pop_small(ctx)
    ImGui.DrawList_AddText(dl, x + 10, cy + 17, C.COL.header_dim, "Touch a parameter\u{2026}")
  end
  x = x + cw + 8

  -- the link
  local lx, ly = x + lr, cy + ch * 0.5
  local can = tg and ctl and not show_bind
  ImGui.SetCursorScreenPos(ctx, x, ly - lr)
  local pressed = ImGui.InvisibleButton(ctx, "##mllink", lr * 2, lr * 2)
  local hov = ImGui.IsItemHovered(ctx)
  -- Not linked: hollow blue (brighter, with a halo, when a click would
  -- link). Linked: filled green. Hovered while linked: filled orange-red,
  -- as a click unlinks.
  if show_bind then
    ImGui.DrawList_AddCircleFilled(dl, lx, ly, lr, hov and (C.COL.warn or 0xe0a040ff) or (C.COL.mon_on or 0x3f9a5aff))
    W.ICONS.chain(dl, lx - 8, ly - 8, 16, 0xffffffff)
  else
    local blue = C.COL.accent
    local ink = can and (hov and U.tint(blue, 0xffffffff, 0.25) or blue) or U.with_alpha(blue, 0x8c)
    ImGui.DrawList_AddCircleFilled(dl, lx, ly, lr, can and hov and U.with_alpha(blue, 0x30) or C.COL.knob_body)
    ImGui.DrawList_AddCircle(dl, lx, ly, lr - 1, ink, 0, 2.0)
    if can then ImGui.DrawList_AddCircle(dl, lx, ly, lr + 3, U.with_alpha(blue, 0x50), 0, 3.0) end
    W.ICONS.chain(dl, lx - 8, ly - 8, 16, ink)
  end
  W.tip(ctx, "mllink", show_bind and ("Linked to %s\nClick: unlink"):format(cc_text(bind.status, bind.cc))
    or can and ("Link %s to %s"):format(cc_text(ctl.status, ctl.cc), "this parameter")
    or "Touch a parameter, move a control\nClick: link them", hov, false)
  if pressed and show_bind then
    ML.unlink(tg.track, tg.addr, tg.p)   -- the last control stays, a click links it back
  elseif pressed and can then
    ML.link(tg.track, tg.addr, tg.p, ctl.status, ctl.cc, st.mode, ML.flags())
    ctl.t = tg.t - 1       -- shows as linked now
  end
  x = x + lr * 2 + 8

  -- the control, or what it's linked to
  card(dl, x, cy, cw2, ch, (ctl and not show_bind and fresh(ctl.t)) or false, nil)
  W.push_small(ctx)
  if show_bind then
    ImGui.DrawList_AddText(dl, x + 10, cy + 4, C.COL.header_dim, "LINKED TO")
    W.pop_small(ctx)
    local fl = {}
    if bind.flags & 1 ~= 0 then fl[#fl + 1] = "selected track" end
    if bind.flags & 2 ~= 0 then fl[#fl + 1] = "soft takeover" end
    ImGui.DrawList_AddText(dl, x + 10, cy + 17, C.COL.header_text,
      clip_text(ctx, ("%s \u{00B7} %s%s"):format(cc_text(bind.status, bind.cc), short_mode(bind.mode),
        #fl > 0 and (" \u{00B7} " .. table.concat(fl, ", ")) or ""), cw2 - 16))
  elseif ctl then
    ImGui.DrawList_AddText(dl, x + 10, cy + 4, C.COL.header_dim,
      clip_text(ctx, "LAST MOVED \u{00B7} " .. dev_name(ctl.dev):upper(), cw2 - 16))
    W.pop_small(ctx)
    ImGui.DrawList_AddText(dl, x + 10, cy + 17, C.COL.header_text,
      ("%s \u{00B7} %d"):format(cc_text(ctl.status, ctl.cc), ctl.val or 0))
  else
    ImGui.DrawList_AddText(dl, x + 10, cy + 4, C.COL.header_dim, "LAST MOVED")
    W.pop_small(ctx)
    ImGui.DrawList_AddText(dl, x + 10, cy + 17, C.COL.header_dim,
      clip_text(ctx, st.ever_midi and "Move a control\u{2026}"
        or "Move a control\u{2026} (its device enabled for input in MIDI Devices)", cw2 - 16))
  end
  x = x + cw2 + 10

  -- second row when narrow
  local ry = cy
  if two then x, ry = tail_x, cy + ML.ROW_H - 6 end

  if not show_bind then
    -- the mode, and what the control looks like
    ImGui.SetCursorScreenPos(ctx, x, ry + 2)
    ImGui.SetNextItemWidth(ctx, 210)
    if ImGui.BeginCombo(ctx, "##mlmode", mode_name(st.mode)) then
      for _, e in ipairs(ML.MODES) do
        if ImGui.Selectable(ctx, e[2], st.mode == e[1]) then st.mode, st.picked = e[1], true end
      end
      ImGui.EndCombo(ctx)
    end
    if ctl then
      local g = ML.guess_mode(ctl.vals)
      local note = (g == 0) and "looks like an ordinary knob"
                   or (g == 1 or g == 2) and "looks like an endless encoder" or nil
      if note then
        W.push_small(ctx)
        ImGui.DrawList_AddText(dl, x + 2, ry + fh + 4, C.COL.header_dim, note)
        W.pop_small(ctx)
      end
    end
    x = x + 220
    -- the options
    ImGui.SetCursorScreenPos(ctx, x, ry)
    local c1, v1 = ImGui.Checkbox(ctx, "Only when its track is selected##mlsel", st.sel_only)
    if c1 then st.sel_only = v1; ext_set(ML.EXT .. "_sel", v1 and "1" or "0") end
    ImGui.SetCursorScreenPos(ctx, x, ry + fh - 2)
    local c2, v2 = ImGui.Checkbox(ctx, "Soft takeover##mlsoft", st.soft)
    if c2 then st.soft = v2; ext_set(ML.EXT .. "_soft", v2 and "1" or "0") end
    W.tip(ctx, "mlsoft", "Parameter waits for the control to reach it\n(absolute controls only)",
      ImGui.IsItemHovered(ctx), false)
  end

  -- right: More..., close
  local bx = x0 + w - 8
  bx = bx - 22
  do  -- close: an x
    local cyy = ry + (ch - 22) * 0.5
    ImGui.SetCursorScreenPos(ctx, bx, cyy)
    if ImGui.InvisibleButton(ctx, "##mlclose", 22, 22) then ML.set_open(false) end
    local hv = ImGui.IsItemHovered(ctx)
    if hv then ImGui.DrawList_AddRectFilled(dl, bx, cyy, bx + 22, cyy + 22, C.COL.knob_body_hi, 3) end
    local ic = hv and C.COL.icon_hot or C.COL.icon
    ImGui.DrawList_AddLine(dl, bx + 7, cyy + 7, bx + 15, cyy + 15, ic, 1.6)
    ImGui.DrawList_AddLine(dl, bx + 15, cyy + 7, bx + 7, cyy + 15, ic, 1.6)
    W.tip(ctx, "mlclose", "Close the MIDI learn bar", hv, false)
  end
  bx = bx - 8
  bx = bx - mw
  ImGui.SetCursorScreenPos(ctx, bx, ry + (ch - fh) * 0.5)
  if ImGui.Button(ctx, "More\u{2026}##mlmore", mw, 0) then
    if tg then
      -- make it REAPER's last touched, then its own learn window
      local v = reaper.TrackFX_GetParamNormalized(tg.track, tg.addr, tg.p)
      reaper.TrackFX_SetParamNormalized(tg.track, tg.addr, tg.p, v)
    end
    reaper.Main_OnCommand(ML.MORE_CMD, 0)
  end
  W.tip(ctx, "mlmore", "REAPER's learn window (OSC and more)",
    ImGui.IsItemHovered(ctx), false)

  ImGui.SetCursorScreenPos(ctx, x0, y0 + h)
  ImGui.Dummy(ctx, 0, 0)
  return h
end

ML._st = st   -- for the tests
return ML
