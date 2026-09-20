--[[
  TS_CV_Channel.lua -- the Channel panel, pinned to the left.

  Fader, level meter, pan, and the channel's state buttons. Pinned outside
  the scrolling row on purpose: the fader is the one control you reach for
  regardless of which plugin you were looking at, and hunting for it after
  scrolling through a long chain would be absurd.

  Volume, dB and the fader taper all come from TS_CV_Util. REAPER's Lua API
  does not expose VAL2DB / DB2VAL / DB2SLIDER / SLIDER2DB, so the maths is
  ours; see there for the shape of the curve and why it isn't linear.
--]]

local C  = require("TS_CV_Config")
local U  = require("TS_CV_Util")
local W  = require("TS_CV_Widgets")
local St = require("TS_CV_State")

local CH = {}
local ImGui

function CH.attach(imgui) ImGui = imgui end

local KEY = "##channel"        -- collapse state key, not an FX GUID

-- ---------------------------------------------------------------------

function CH.width(collapsed)
  return collapsed and C.COLLAPSED_W or C.CHANNEL_W
end

function CH.is_collapsed() return St.is_collapsed(KEY) end

-- REAPER answers nil, not 0, when a track does not HAVE the thing you
-- asked about -- record arm on the master, most obviously -- and `nil >
-- 0.5` is a hard error, not a false. So every read has a default, and
-- CH.state below decides which of these the track has at all.
function CH.read(track, key, dflt)
  local v = track and reaper.GetMediaTrackInfo_Value(track, key)
  if v == nil then return dflt or 0 end
  return v
end
local function get(track, key, dflt) return CH.read(track, key, dflt) end
local function set(track, key, v) reaper.SetMediaTrackInfo_Value(track, key, v) end

-- The master track has no record arm, no input monitoring and no phase
-- invert. Drawing dead buttons for them would be worse than leaving the
-- space to the fader and meter, which the master does have.
function CH.is_master(track)
  return track ~= nil and track == reaper.GetMasterTrack(0)
end

-- Record monitoring cycles off / input / auto. Short labels because the
-- button is 40-odd pixels wide, and a distinct colour for auto: it is a
-- different behaviour from plain input monitoring, not a stronger one, so
-- showing it in the same green would read as "on, but more".
local MON = {
  [0] = { text = "\u{2013}",  col = nil,              tip = "Monitoring off" },
  [1] = { text = "IN", col = "mon_on",        tip = "Monitoring input" },
  [2] = { text = "AU", col = "mon_auto",      tip = "Monitoring auto (input while stopped)" },
}

function CH.draw_header(ctx, dl, x, y, w)
  ImGui.DrawList_AddRectFilled(dl, x, y, x + w, y + C.HEADER_H, C.COL.header_bg, 0)
  ImGui.DrawList_AddLine(dl, x, y + C.HEADER_H, x + w, y + C.HEADER_H,
    C.COL.panel_border, 1.0)

  local _, th = ImGui.CalcTextSize(ctx, "Channel")
  ImGui.DrawList_AddText(dl, x + 6, y + (C.HEADER_H - th) * 0.5,
    C.COL.header_text, "Channel")

  local btn = C.ICON_SIZE
  ImGui.SetCursorScreenPos(ctx, x + w - btn - 3, y + 3)
  if W.icon_button(ctx, "chcol", "collapse", btn, false, "Collapse the channel strip") then
    St.toggle_collapsed(KEY)
  end
end

function CH.draw_collapsed(ctx, dl, x, y, w, h, track)
  local btn = C.ICON_SIZE
  local cx  = x + w * 0.5

  ImGui.SetCursorScreenPos(ctx, cx - btn * 0.5, y + 4)
  if W.icon_button(ctx, "chexp", "expand", btn, false, "Expand the channel strip") then
    St.toggle_collapsed(KEY)
  end

  local muted = get(track, "B_MUTE") > 0.5
  local solo  = get(track, "I_SOLO") > 0.5
  local bw = w - 8
  if W.state_button(ctx, "cM", "M", x + 4, y + 4 + btn + 4, bw, 14,
      muted, C.COL.mute_on, "Mute") then
    set(track, "B_MUTE", muted and 0 or 1)
  end
  if W.state_button(ctx, "cS", "S", x + 4, y + 4 + btn + 22, bw, 14,
      solo, C.COL.solo_on, "Solo") then
    set(track, "I_SOLO", solo and 0 or 1)
  end

  -- the meter is what makes a collapsed strip worth keeping visible
  local top = y + 4 + btn + 42
  local mh  = h - (top - y) - 24
  if mh > 30 then
    local now = reaper.time_precise()
    local l = U.val2db(reaper.Track_GetPeakInfo(track, 0))
    local r = U.val2db(reaper.Track_GetPeakInfo(track, 1))
    local pk = W.level_peak(KEY, math.max(l, r), now)
    -- No ladder and no RMS on the collapsed bar: at this width the
    -- numbers wouldn't fit and the strip would stop being a glance.
    W.level_meter(ctx, dl, x + 4, top, w - 8, mh, { l, r }, pk, false, nil)

    -- The fader, as a translucent cap laid straight over the meter.
    -- There is no room for a fader beside a meter at this width, and
    -- collapsing the strip shouldn't mean going somewhere else to pull
    -- the level down -- which is usually exactly why you looked.
    local vol = get(track, "D_VOL", 1)
    local fch, fnv, fact = W.fader(ctx, "chfadermini", x + 4, top, w - 8, mh,
      U.vol_to_fader(vol), "Volume   " .. U.db_text(vol) .. " dB",
      U.UNITY_POS, true)
    if fact and fact.double_click then fnv, fch = U.UNITY_POS, true end
    if fch then set(track, "D_VOL", U.fader_to_vol(fnv)) end
  end

  W.vertical_text(ctx, dl, cx, y + h - 20, "CH", C.COL.header_dim, 20)
end

function CH.draw_body(ctx, dl, x, y, w, h, track)
  local pad = 5
  local now = reaper.time_precise()

  -- pan across the top
  local pan = get(track, "D_PAN")
  local pan_txt = (math.abs(pan) < 0.005) and "C"
    or string.format("%d%s", math.floor(math.abs(pan) * 100 + 0.5),
                     pan < 0 and "L" or "R")
  ImGui.SetCursorScreenPos(ctx, x + (w - C.CELL_W) * 0.5, y + 2)
  local pch, pnv, pact = W.knob(ctx, "chpan", "Pan", (pan + 1) * 0.5, pan_txt,
    { bipolar = true, tooltip = pan_txt })
  if pact and pact.double_click then pnv, pch = 0.5, true end
  if pch then set(track, "D_PAN", pnv * 2 - 1) end

  -- buttons along the bottom, two columns -- one row on the master, which
  -- has only mute and solo, so the fader and meter get the rest
  local master = CH.is_master(track)
  local bh, bgap = 15, 3
  local bw = (w - pad * 2 - bgap) * 0.5
  local rows = master and 1 or 3
  local btm = y + h - pad - rows * bh - (rows - 1) * bgap

  local muted = get(track, "B_MUTE") > 0.5
  local solo  = get(track, "I_SOLO") > 0.5
  local rec   = get(track, "I_RECARM") > 0.5
  local mon   = math.floor(get(track, "I_RECMON")) % 3
  local phase = get(track, "B_PHASE") > 0.5

  local function cell(col, row)
    return x + pad + col * (bw + bgap), btm + row * (bh + bgap)
  end

  local full = w - pad * 2

  local bx, by = cell(0, 0)
  local hit, dbl = W.state_button(ctx, "bM", "M", bx, by, bw, bh,
    muted, C.COL.mute_on, "Mute")
  if hit or dbl then set(track, "B_MUTE", (dbl or muted) and 0 or 1) end
  bx, by = cell(1, 0)
  hit, dbl = W.state_button(ctx, "bS", "S", bx, by, bw, bh,
    solo, C.COL.solo_on, "Solo")
  if hit or dbl then set(track, "I_SOLO", (dbl or solo) and 0 or 1) end

  if not master then
    -- Phase and monitoring share the middle row; record arm gets a row of
    -- its own at full width, because it is the one you hit in a hurry and
    -- the one whose state you check from across the room.
    bx, by = cell(0, 1)
    hit, dbl = W.state_button(ctx, "bP", "\u{00F8}", bx, by, bw, bh,
      phase, C.COL.warn, "Invert phase")
    if hit or dbl then set(track, "B_PHASE", (dbl or phase) and 0 or 1) end

    bx, by = cell(1, 1)
    local m = MON[mon]
    hit, dbl = W.state_button(ctx, "bI", m.text, bx, by, bw, bh, mon > 0,
      m.col and C.COL[m.col] or nil, m.tip .. "  \u{2014} click to cycle")
    if dbl then set(track, "I_RECMON", 0)
    elseif hit then set(track, "I_RECMON", (mon + 1) % 3) end

    bx, by = cell(0, 2)
    hit, dbl = W.state_icon(ctx, "bR", "record", bx, by, full, bh, rec,
      C.COL.rec_on, rec and "Record armed" or "Record arm")
    if hit or dbl then set(track, "I_RECARM", (dbl or rec) and 0 or 1) end
  end

  -- Fader and meter take half the inner width each, so the pair reads as
  -- balanced rather than as a fader with something tacked on beside it.
  local vol   = get(track, "D_VOL", 1)   -- unity if the track has none
  local inner = w - pad * 2
  local half  = inner * 0.5
  local top   = y + C.CELL_H + 2
  -- Two lines of readout under the meter (peak, then RMS) and one under
  -- the fader; the taller of the two sets how much the fader gives up.
  -- The extra few pixels keep the RMS figure off the Solo button.
  local vh    = 32
  local fh    = btm - top - vh - 4

  if fh > 40 then
    local fx = x + pad + (half - C.FADER_W) * 0.5
    local fch, fnv, fact = W.fader(ctx, "chfader", fx, top, C.FADER_W, fh,
      U.vol_to_fader(vol), "Volume   " .. U.db_text(vol) .. " dB",
      U.UNITY_POS)
    if fact and fact.double_click then fnv, fch = U.UNITY_POS, true end
    if fch then set(track, "D_VOL", U.fader_to_vol(fnv)) end

    -- the fader's own value, with the fader rather than lost among the
    -- buttons
    local vt = U.db_text(vol)
    local tw, th = ImGui.CalcTextSize(ctx, vt)
    ImGui.DrawList_AddText(dl, x + pad + (half - tw) * 0.5, top + fh + 2,
      C.COL.value, vt)

    local l = U.val2db(reaper.Track_GetPeakInfo(track, 0))
    local r = U.val2db(reaper.Track_GetPeakInfo(track, 1))
    local sum = math.max(l, r)
    local pk  = W.level_peak(KEY, sum, now)
    -- Per channel, so the RMS strip beside each bar belongs to that bar.
    local rl  = W.level_rms(KEY .. "L", l, now)
    local rr  = W.level_rms(KEY .. "R", r, now)
    local rms = math.max(rl, rr)
    -- Centred in its half, the same way the fader's track is centred in
    -- the other one -- a meter flush to the panel edge beside a centred
    -- fader reads as a misalignment even though both are in their column.
    local mw = math.min(half - 4, C.LEVEL_METER_W)
    local mx = x + pad + half + (half - mw) * 0.5
    W.level_meter(ctx, dl, mx, top, mw, fh, { l, r }, pk, true, { rl, rr })

    -- hovering the meter reports what it is showing
    ImGui.SetCursorScreenPos(ctx, mx, top)
    ImGui.InvisibleButton(ctx, "chmeter", mw, fh)
    W.tip(ctx, "chmeter",
      ("Peak %s   RMS %s\nL %s   R %s")
      :format(U.db_str(pk), U.db_str(rms), U.db_str(l), U.db_str(r)),
      ImGui.IsItemHovered(ctx), false)

    -- Peak over the meter, RMS under it -- two numbers in a column 50-odd
    -- pixels wide, so they get a line each rather than a cramped row.
    local hx = x + pad + half          -- the meter's half, for the readouts
    local pt = (pk > C.METER_FLOOR) and U.db_str(pk) or "-inf"
    local ptw = ImGui.CalcTextSize(ctx, pt)
    ImGui.DrawList_AddText(dl, hx + (half - ptw) * 0.5, top + fh + 2,
      W.level_colour(pk, C.COL.header_dim), pt)

    local rt = (rms > C.METER_FLOOR) and (U.db_str(rms) .. "r") or ""
    if rt ~= "" then
      local rtw = ImGui.CalcTextSize(ctx, rt)
      ImGui.DrawList_AddText(dl, hx + (half - rtw) * 0.5, top + fh + 2 + th,
        C.COL.level_rms, rt)
    end
  end
end

-- The panel itself: frame, then either the collapsed bar or header plus
-- body. Same shape as a plugin panel so the row reads as one thing, but
-- it is pinned outside the scrolling child rather than in it.
function CH.draw(ctx, track, avail_h)
  local collapsed = St.is_collapsed(KEY)
  local w = CH.width(collapsed)

  local ok = ImGui.BeginChild(ctx, "chanpanel", w, avail_h, 0,
    ImGui.WindowFlags_NoScrollbar | ImGui.WindowFlags_NoScrollWithMouse)
  if ok then
    local dl = ImGui.GetWindowDrawList(ctx)
    local x, y = ImGui.GetWindowPos(ctx)
    local ww, wh = ImGui.GetWindowSize(ctx)

    ImGui.DrawList_AddRectFilled(dl, x, y, x + ww, y + wh, C.COL.panel_bg, 3.0)
    ImGui.DrawList_AddRect(dl, x, y, x + ww, y + wh, C.COL.panel_border, 3.0, 0, 1.0)

    -- With no track selected the frame and the collapse control stay --
    -- the row shouldn't change shape just because the selection went
    -- away, and the control that got you here has to still be there.
    if collapsed then
      if track then
        CH.draw_collapsed(ctx, dl, x, y, ww, wh, track)
      else
        local btn = C.ICON_SIZE
        ImGui.SetCursorScreenPos(ctx, x + (ww - btn) * 0.5, y + 4)
        if W.icon_button(ctx, "chexp", "expand", btn, false,
            "Expand the channel strip") then
          St.toggle_collapsed(KEY)
        end
        W.vertical_text(ctx, dl, x + ww * 0.5, y + 4 + btn + 6,
          "CH", C.COL.header_dim, wh - btn - 16)
      end
    else
      CH.draw_header(ctx, dl, x, y, ww)
      if track then
        CH.draw_body(ctx, dl, x, y + C.HEADER_H, ww, wh - C.HEADER_H, track)
      end
    end
    ImGui.EndChild(ctx)
  end
  return w
end

return CH
