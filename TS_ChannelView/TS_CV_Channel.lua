-- @noindex
-- Not a package of its own: installed by TS_ChannelView.lua's @provides.
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
local G  = require("TS_CV_Gang")

local CH = {}
local ImGui

function CH.attach(imgui) ImGui = imgui end

local KEY = "##channel"        -- collapse state key, not an FX GUID

-- ---------------------------------------------------------------------

function CH.width(collapsed)
  return collapsed and C.COLLAPSED_W or C.CHANNEL_W
end

function CH.is_collapsed() return St.is_collapsed(KEY) end

-- Collapsing gangs like everything else: fold one of six selected
-- strips and all six fold. A mixer collapse key is "<prefix>:<guid>",
-- so the others' keys are the same prefix with their own guid; the
-- pinned Channel panel's key has no guid in it at all and falls
-- straight through to the plain set, which is right -- there is only
-- one of it.
function CH.set_collapse(ckey, track, want)
  local prefix = ckey:match("^(.-:)")
  if prefix and track then
    local keys = G.collapse_keys(track, prefix)
    if #keys > 0 then
      for _, k in ipairs(keys) do St.set_collapsed(k, want) end
      return
    end
  end
  St.set_collapsed(ckey, want)
end

-- Set when the panel's background was double-clicked. The caller reads
-- and clears it: this module has no business knowing what a view is.
CH.want_mixer = false

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
-- Every absolute write goes through the gang: if this track is one of
-- several selected, they all take it. One function, so there is no
-- control that quietly forgot. Volume and pan are the exceptions and
-- call G.vol / G.pan, because they move BY an amount rather than TO a
-- value -- see TS_CV_Gang.
local function set(track, key, v) G.set(track, key, v) end

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

-- ---------------------------------------------------------------------
-- automation mode
-- ---------------------------------------------------------------------

-- REAPER's I_AUTOMODE. Short labels because the button is thirty pixels
-- wide, and a colour each because which mode you are in is the sort of
-- thing you want to notice from across the room rather than read.
CH.AUTO = {
  [0] = { text = "TRIM", col = "auto_trim",    name = "Trim / Read off" },
  [1] = { text = "READ", col = "auto_read",    name = "Read" },
  [2] = { text = "TCH",  col = "auto_touch",   name = "Touch" },
  [3] = { text = "WRT",  col = "auto_write",   name = "Write" },
  [4] = { text = "LTCH", col = "auto_latch",   name = "Latch" },
  [5] = { text = "LPRV", col = "auto_preview", name = "Latch preview" },
}

function CH.auto_mode(track)
  local m = math.floor(CH.read(track, "I_AUTOMODE", 0))
  if CH.AUTO[m] then return m end
  return 0
end

-- The button, plus the popup it opens. A five-way setting is a menu, not
-- a cycle: clicking four times to get back to where you were is how you
-- end up recording automation you did not mean to.
function CH.auto_button(ctx, x, y, w, h, track, idp)
  if not track then return end
  local m = CH.auto_mode(track)
  local e = CH.AUTO[m]
  local id = idp .. "auto"

  if W.state_button(ctx, id, e.text, x, y, w, h, m ~= 0, C.COL[e.col],
      "Automation: " .. e.name) then
    ImGui.OpenPopup(ctx, id .. "pop")
  end

  if ImGui.BeginPopup(ctx, id .. "pop") then
    for i = 0, 5 do
      local o = CH.AUTO[i]
      if ImGui.MenuItem(ctx, o.name, nil, i == m) then
        G.set(track, "I_AUTOMODE", i)
      end
    end
    ImGui.EndPopup(ctx)
  end
end

function CH.draw_header(ctx, dl, x, y, w, track)
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

  -- Automation mode, left of the collapse control -- the same corner the
  -- Sends panel keeps its routing button in.
  local aw = C.AUTO_BTN_W
  if w - aw - btn - 12 > 20 then
    CH.auto_button(ctx, x + w - btn - aw - 8, y + 3, aw, C.HEADER_H - 6,
                   track, "ch")
  end
end

-- The collapsed bar, for the pinned Channel panel AND for a collapsed
-- mixer strip -- the same argument as CH.draw_body below. `idp` is the
-- widget-id prefix and the peak-hold key, `ckey` the collapse-state key
-- to toggle, `label` what runs down the bar. The defaults are the
-- pinned panel's, so the one call that had none still reads as it did.
-- Returns true when the ghost fader was CLICKED rather than dragged --
-- see W.fader. The caller uses it to select the track, since on a
-- collapsed strip the fader lies right over the meter and a plain click
-- there means "this one", not "move the level".
function CH.draw_collapsed(ctx, dl, x, y, w, h, track, idp, ckey)
  idp   = idp or "ch"
  ckey  = ckey or KEY
  local bare = false
  local btn = C.ICON_SIZE
  local cx  = x + w * 0.5

  ImGui.SetCursorScreenPos(ctx, cx - btn * 0.5, y + 4)
  if W.icon_button(ctx, idp .. "exp", "expand", btn, false,
      "Expand this strip") then
    CH.set_collapse(ckey, track, false)
  end

  local muted = get(track, "B_MUTE") > 0.5
  local solo  = get(track, "I_SOLO") > 0.5
  local bw = w - 8
  -- Swipeable here too: a row of collapsed strips is exactly where you
  -- want to drag mute across six tracks at once.
  local hit, _, want = W.state_button(ctx, idp .. "cM", "M",
    x + 4, y + 4 + btn + 4, bw, 14, muted, C.COL.mute_on, "Mute", "mute")
  if want ~= nil then set(track, "B_MUTE", want and 1 or 0)
  elseif hit then set(track, "B_MUTE", muted and 0 or 1) end

  hit, _, want = W.state_button(ctx, idp .. "cS", "S",
    x + 4, y + 4 + btn + 22, bw, 14, solo, C.COL.solo_on, "Solo", "solo")
  if want ~= nil then set(track, "I_SOLO", want and 1 or 0)
  elseif hit then set(track, "I_SOLO", solo and 0 or 1) end

  -- Read out here, not inside: the readout below prints it whether or
  -- not there was room for a meter.
  local vol = get(track, "D_VOL", 1)

  -- the meter is what makes a collapsed strip worth keeping visible
  local top = y + 4 + btn + 42
  local mh  = h - (top - y) - 24
  if mh > 30 then
    local now = reaper.time_precise()
    -- One hold per channel: a single figure drawn across both bars is
    -- the louder channel's peak laid over the quieter one's meter.
    local nch = W.meter_channels(track)
    local lv, pk = {}, {}
    for i = 1, nch do
      lv[i] = U.val2db(reaper.Track_GetPeakInfo(track, i - 1))
      pk[i] = W.level_peak(idp .. "c" .. i, lv[i], now)
    end
    -- No ladder and no RMS on the collapsed bar: at this width the
    -- numbers wouldn't fit and the strip would stop being a glance.
    W.level_meter(ctx, dl, x + 4, top, w - 8, mh, lv, pk, false, nil)

    -- The fader, as a translucent cap laid straight over the meter.
    -- There is no room for a fader beside a meter at this width, and
    -- collapsing the strip shouldn't mean going somewhere else to pull
    -- the level down -- which is usually exactly why you looked.
    local fch, fnv, fact = W.fader(ctx, idp .. "fmini", x + 4, top, w - 8, mh,
      U.vol_to_fader(vol), "Volume   " .. U.db_text(vol) .. " dB",
      U.UNITY_POS, true)
    local dblv = fact and fact.double_click
    if fact and fact.click then bare = true end
    if dblv then fnv, fch = U.UNITY_POS, true end
    -- Double-click means unity, and unity is a place, not a distance:
    -- it sets the whole gang TO it. A drag moves them BY the ratio.
    if fch then
      local nv = U.fader_to_vol(fnv)
      if dblv then set(track, "D_VOL", nv) else G.vol(track, nv) end
    end
  end

  -- Under the meter: the level, in dB. It used to be the strip's name
  -- run down the bar, and at thirty pixels wide with twenty to spare
  -- there was room for exactly one stacked letter -- so what it
  -- actually showed, always, was a single ellipsis. The name is in the
  -- track list directly below; the number is the thing you collapsed
  -- the strip to keep an eye on.
  local vt = U.db_text(vol)
  local tw = ImGui.CalcTextSize(ctx, vt)
  ImGui.DrawList_AddText(dl, cx - tw * 0.5, y + h - 16, C.COL.value, vt)

  return bare
end

-- `idp` is the widget-id prefix and the peak-hold key. It defaults to
-- "ch" -- the one pinned Channel panel -- and the mixer passes a
-- per-track one, because this same body is every strip in mixer view.
-- Without it every strip would share one set of ImGui ids and one peak
-- store, and they would all fight over both.
function CH.draw_body(ctx, dl, x, y, w, h, track, idp)
  idp = idp or "ch"
  local pad = 5
  local now = reaper.time_precise()

  -- pan across the top
  local pan = get(track, "D_PAN")
  local pan_txt = (math.abs(pan) < 0.005) and "C"
    or string.format("%d%s", math.floor(math.abs(pan) * 100 + 0.5),
                     pan < 0 and "L" or "R")
  ImGui.SetCursorScreenPos(ctx, x + (w - C.CELL_W) * 0.5, y + 2)
  local pch, pnv, pact = W.knob(ctx, idp .. "pan", "Pan", (pan + 1) * 0.5, pan_txt,
    { bipolar = true, tooltip = pan_txt })
  local dblp = pact and pact.double_click
  if dblp then pnv, pch = 0.5, true end
  -- Centre is a place; a drag is a distance. See the fader below.
  if pch then
    local np = pnv * 2 - 1
    if dblp then set(track, "D_PAN", np) else G.pan(track, np) end
  end

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

  -- Mute, solo and record arm take a swipe: press one and drag along the
  -- row in mixer view and every one you cross follows the first. `want`
  -- carries the value the click or the swipe asks for.
  local bx, by = cell(0, 0)
  local hit, dbl, want = W.state_button(ctx, idp .. "bM", "M", bx, by, bw, bh,
    muted, C.COL.mute_on, "Mute", "mute")
  if dbl then set(track, "B_MUTE", 0)
  elseif want ~= nil then set(track, "B_MUTE", want and 1 or 0) end

  bx, by = cell(1, 0)
  hit, dbl, want = W.state_button(ctx, idp .. "bS", "S", bx, by, bw, bh,
    solo, C.COL.solo_on, "Solo", "solo")
  if dbl then set(track, "I_SOLO", 0)
  elseif want ~= nil then set(track, "I_SOLO", want and 1 or 0) end

  if not master then
    -- Phase and monitoring share the middle row; record arm gets a row of
    -- its own at full width, because it is the one you hit in a hurry and
    -- the one whose state you check from across the room.
    bx, by = cell(0, 1)
    -- No swipe on phase: it is not a thing you set across a row, and a
    -- stray drag flipping the polarity of six tracks is a bad afternoon.
    hit, dbl = W.state_button(ctx, idp .. "bP", "\u{00F8}", bx, by, bw, bh,
      phase, C.COL.warn, "Invert phase")
    if hit or dbl then set(track, "B_PHASE", (dbl or phase) and 0 or 1) end

    bx, by = cell(1, 1)
    -- Nor monitoring: three states have no "the same way as the first".
    local m = MON[mon]
    hit, dbl = W.state_button(ctx, idp .. "bI", m.text, bx, by, bw, bh, mon > 0,
      m.col and C.COL[m.col] or nil, m.tip .. "  \u{2014} click to cycle")
    if dbl then set(track, "I_RECMON", 0)
    elseif hit then set(track, "I_RECMON", (mon + 1) % 3) end

    bx, by = cell(0, 2)
    hit, dbl, want = W.state_icon(ctx, idp .. "bR", "record", bx, by, full, bh,
      rec, C.COL.rec_on, rec and "Record armed" or "Record arm", "rec")
    if dbl then set(track, "I_RECARM", 0)
    elseif want ~= nil then set(track, "I_RECARM", want and 1 or 0) end
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
    local fch, fnv, fact = W.fader(ctx, idp .. "fader", fx, top, C.FADER_W, fh,
      U.vol_to_fader(vol), "Volume   " .. U.db_text(vol) .. " dB",
      U.UNITY_POS)
    local dblv = fact and fact.double_click
    if dblv then fnv, fch = U.UNITY_POS, true end
    if fch then
      local nv = U.fader_to_vol(fnv)
      if dblv then set(track, "D_VOL", nv) else G.vol(track, nv) end
    end

    -- the fader's own value, with the fader rather than lost among the
    -- buttons
    local vt = U.db_text(vol)
    local tw, th = ImGui.CalcTextSize(ctx, vt)
    ImGui.DrawList_AddText(dl, x + pad + (half - tw) * 0.5, top + fh + 2,
      C.COL.value, vt)

    -- Everything the meter shows, per channel: the live level, the peak
    -- hold, the live RMS, and the RMS HELD.
    --
    -- The RMS figure holds exactly as the peak figure does. A number
    -- that changes sixty times a second is not a number anybody reads,
    -- and the strip beside the bar is already showing the live one -- a
    -- readout is for the value you want to catch and look at. Same hold
    -- and same fall as the peak, so the two figures under the meter
    -- behave the same way as each other.
    local nch = W.meter_channels(track)
    local lv, hold, rms_live, rms_hold = {}, {}, {}, {}
    for i = 1, nch do
      local key = idp .. "c" .. i
      lv[i]       = U.val2db(reaper.Track_GetPeakInfo(track, i - 1))
      hold[i]     = W.level_peak(key, lv[i], now)
      rms_live[i] = W.level_rms(key, lv[i], now)
      rms_hold[i] = W.level_peak(key .. "#r", rms_live[i], now)
    end
    -- Centred in its half, the same way the fader's track is centred in
    -- the other one -- a meter flush to the panel edge beside a centred
    -- fader reads as a misalignment even though both are in their column.
    local mw = math.min(half - 4, C.LEVEL_METER_W)
    local mx = x + pad + half + (half - mw) * 0.5
    W.level_meter(ctx, dl, mx, top, mw, fh, lv, hold, true, rms_live)

    -- Hovering the meter reports what it is showing -- by RECTANGLE,
    -- not by an invisible button over it. A button here would be an
    -- item, and an item swallows the click that the strip's background
    -- needs in order to select the track. The meter reads out; it does
    -- not do anything, so it has no business being clickable.
    local m_over = ImGui.IsWindowHovered(ctx)
                   and ImGui.IsMouseHoveringRect(ctx, mx, top, mx + mw, top + fh)
    local tip = {}
    for i = 1, nch do
      tip[i] = ("%speak %s   RMS %s   now %s"):format(
        (nch > 1) and ((i == 1) and "L  " or "R  ") or "",
        U.db_str(hold[i]), U.db_str(rms_hold[i]), U.db_str(lv[i]))
    end
    W.tip(ctx, idp .. "meter", table.concat(tip, "\n"), m_over, false)

    -- Peak on the first line, RMS on the second, and ONE COLUMN PER
    -- CHANNEL, each centred under the bar it is about -- a stereo track
    -- has two levels and printing the louder one on its own was a
    -- number you could not act on, since it never said which side it
    -- came from.
    --
    -- In the smaller face, because two columns of "-12.3" do not fit a
    -- fifty-pixel column at the body size, and a readout is the one
    -- place where a smaller face costs nothing. The RMS line dropped
    -- its trailing "r": with two columns that was two more marks for
    -- something the colour and the position already say, and the
    -- tooltip names them outright.
    W.push_small(ctx)
    local _, rh = ImGui.CalcTextSize(ctx, "0")
    local mbl = mx + 1.5                          -- the bars' own left
    local mbw = (mw - 3 - (nch - 1)) / nch        -- and their width
    for i = 1, nch do
      local ccx = mbl + (i - 1) * (mbw + 1) + mbw * 0.5
      local pt  = (hold[i] > C.METER_FLOOR) and U.db_str(hold[i]) or "-inf"
      local ptw = ImGui.CalcTextSize(ctx, pt)
      ImGui.DrawList_AddText(dl, ccx - ptw * 0.5, top + fh + 2,
        W.level_colour(hold[i], C.COL.header_dim), pt)

      if rms_hold[i] > C.METER_FLOOR then
        local rt  = U.db_str(rms_hold[i])
        local rtw = ImGui.CalcTextSize(ctx, rt)
        ImGui.DrawList_AddText(dl, ccx - rtw * 0.5, top + fh + 2 + rh,
          C.COL.level_rms, rt)
      end
    end
    W.pop_small(ctx)
  end
end

-- The panel itself: frame, then either the collapsed bar or header plus
-- body. Same shape as a plugin panel so the row reads as one thing, but
-- it is pinned outside the scrolling child rather than in it.
function CH.draw(ctx, track, avail_h)
  local collapsed = St.is_collapsed(KEY)
  local w = CH.width(collapsed)

  local cp_x, cp_y = ImGui.GetCursorPos(ctx)
  local ok = ImGui.BeginChild(ctx, "chanpanel", w, avail_h, 0,
    ImGui.WindowFlags_NoScrollbar | ImGui.WindowFlags_NoScrollWithMouse)
  if ok then
    local dl = ImGui.GetWindowDrawList(ctx)
    local x, y = ImGui.GetWindowPos(ctx)
    local ww, wh = ImGui.GetWindowSize(ctx)

    ImGui.DrawList_AddRectFilled(dl, x, y, x + ww, y + wh, C.COL.panel_bg, 3.0)
    ImGui.DrawList_AddRect(dl, x, y, x + ww, y + wh, C.COL.panel_border, 3.0, 0, 1.0)

    -- The panel's own background is a double-click target: back to mixer
    -- view. Submitted BEFORE the controls so all of them sit on top of
    -- it -- a double-click on the fader is the fader's, and means unity.
    ImGui.SetCursorScreenPos(ctx, x, y)
    W.allow_overlap(ctx)
    ImGui.InvisibleButton(ctx, "chbg", ww, wh)
    if ImGui.IsItemHovered(ctx)
       and ImGui.IsMouseDoubleClicked(ctx, ImGui.MouseButton_Left) then
      CH.want_mixer = true
    end

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
      CH.draw_header(ctx, dl, x, y, ww, track)
      if track then
        CH.draw_body(ctx, dl, x, y + C.HEADER_H, ww, wh - C.HEADER_H, track)
      end
    end
    ImGui.EndChild(ctx)
  else
    -- Culled: still occupy the space, or the parent's bounds
    -- never grow past it. See W.child_skipped.
    W.child_skipped(ctx, w, avail_h, cp_x, cp_y)
  end
  return w
end

return CH
