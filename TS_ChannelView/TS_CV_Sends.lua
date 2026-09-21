-- @noindex
-- Not a package of its own: installed by TS_ChannelView.lua's @provides.
--[[
  TS_CV_Sends.lua -- the Sends panel, pinned to the right.

  One column per send: the destination's name over its colour, a bypass,
  a level knob and a pre/post button. Plus an add control in the same
  dashed style as the insert one, opening the same kind of hover menu.

  THE ADD MENU
    Direct   -> the send lands on the destination's channels 1/2
    Sidechain-> channels 3/4, and the destination is widened to at least
                four channels if it isn't already, because a sidechain
                send into a two-channel track goes nowhere and REAPER
                will not widen it for you.

  Tracks whose name is nothing but punctuation ("--------") are spacers,
  not destinations: people use them to group a template. They render as a
  gap in the menu rather than as something you can send to -- the same
  convention REAPER's own FX folder list uses.
--]]

local C  = require("TS_CV_Config")
local U  = require("TS_CV_Util")
local W  = require("TS_CV_Widgets")
local St = require("TS_CV_State")
local P  = require("TS_CV_Panel")

local SD = {}
local ImGui

function SD.attach(imgui) ImGui = imgui end

local KEY = "##sends"

-- REAPER's send categories: 0 is track sends (what this panel shows).
local CAT = 0

-- I_SENDMODE: 0 post-fader, 1 pre-fx, 3 post-fx (ie. pre-fader).
local POST, PRE = 0, 3

function SD.is_collapsed() return St.is_collapsed(KEY) end

-- ---------------------------------------------------------------------
-- reading the sends
-- ---------------------------------------------------------------------

local function send_get(track, i, key)
  -- nil, not 0, if the send went away between collecting and reading --
  -- and `nil > 0.5` is a hard error rather than a false
  local v = reaper.GetTrackSendInfo_Value(track, CAT, i, key)
  if v == nil then return 0 end
  return v
end
local function send_set(track, i, key, v)
  reaper.SetTrackSendInfo_Value(track, CAT, i, key, v)
end

function SD.collect(track)
  local out = {}
  if not track then return out end
  local n = reaper.GetTrackNumSends(track, CAT) or 0
  for i = 0, n - 1 do
    local dest = reaper.GetTrackSendInfo_Value(track, CAT, i, "P_DESTTRACK")
    local name, colour, num = "?", nil, 0
    if dest then
      local _, nm = reaper.GetSetMediaTrackInfo_String(dest, "P_NAME", "", false)
      num = math.floor(reaper.GetMediaTrackInfo_Value(dest, "IP_TRACKNUMBER") or 0)
      name = (U.trim(nm) ~= "") and U.trim(nm) or ("Track " .. num)
      colour = U.track_colour(dest, 0xff)
    end
    out[#out + 1] = {
      idx    = i,
      name   = name,
      num    = num,
      colour = colour,
      vol    = send_get(track, i, "D_VOL"),
      mute   = send_get(track, i, "B_MUTE") > 0.5,
      mode   = math.floor(send_get(track, i, "I_SENDMODE") or 0),
      dstch  = math.floor(send_get(track, i, "I_DSTCHAN") or 0),
    }
  end
  return out
end

-- The width the panel will take, worked out before anything is drawn so
-- the scrolling row in the middle knows how much is left for it.
function SD.width_for(track, panel_h)
  if St.is_collapsed(KEY) then return C.COLLAPSED_W end
  local n = track and (reaper.GetTrackNumSends(track, CAT) or 0) or 0
  return SD.width(false, n, panel_h)
end

-- Sends sit on the SAME grid the plugin panels use, in double-width
-- cells: knob in the left half, buttons in the right. A send therefore
-- lines up row-for-row with the parameters beside it, and the add tile is
-- just the next cell rather than something bolted on the end.
function SD.width(collapsed, n_sends, panel_h)
  if collapsed then return C.COLLAPSED_W end
  local rows = P.rows_for(panel_h or 300)
  local cells = n_sends + 1                      -- +1 for the add tile
  local cols = math.max(1, math.ceil(cells / rows))
  return math.min(C.SENDS_MAX_W,
                  cols * C.SEND_W + (cols - 1) * C.SEND_COL_GAP
                  + C.PANEL_PAD * 2)
end

-- ---------------------------------------------------------------------
-- the add menu
-- ---------------------------------------------------------------------

-- A track used purely as a spacer in a template: its name is nothing but
-- punctuation. Not somewhere anyone means to send audio.
function SD.is_separator(name)
  local t = U.trim(name or "")
  return t ~= "" and t:match("^[%-%_%=%~%.%*%s]+$") ~= nil
end

local pending_menu = false
local ctx_send     = nil     -- send index whose right-click menu is open
local want_ctx     = false

function SD.open_menu() pending_menu = true end

-- Lists every track except `track` itself, with spacers marked.
local function project_tracks(track)
  local out = {}
  for i = 0, reaper.CountTracks(0) - 1 do
    local tr = reaper.GetTrack(0, i)
    local _, nm = reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", "", false)
    nm = U.trim(nm)
    out[#out + 1] = {
      track = tr,
      num   = i + 1,
      name  = (nm ~= "") and nm or ("Track " .. (i + 1)),
      sep   = SD.is_separator(nm),
      self  = (tr == track),
      -- REAPER's own TCP spacer, the "Space" column in the track manager.
      -- Grouping you set up in the project should survive into this menu
      -- rather than being flattened out of it.
      space = (reaper.GetMediaTrackInfo_Value(tr, "I_SPACER") or 0) > 0.5,
      col   = U.track_colour(tr, 0xff),
    }
  end
  return out
end

-- Creates the send. A sidechain send needs somewhere to land: REAPER will
-- happily make a send to channels 3/4 of a two-channel track and pass no
-- audio, so widen the destination first.
function SD.add_send(track, dest, sidechain)
  if not track or not dest or track == dest then return false end
  reaper.Undo_BeginBlock()
  if sidechain then
    local nch = reaper.GetMediaTrackInfo_Value(dest, "I_NCHAN") or 2
    if nch < 4 then
      reaper.SetMediaTrackInfo_Value(dest, "I_NCHAN", 4)
    end
  end
  local idx = reaper.CreateTrackSend(track, dest)
  if idx and idx >= 0 then
    reaper.SetTrackSendInfo_Value(track, CAT, idx, "I_DSTCHAN", sidechain and 2 or 0)
  end
  reaper.Undo_EndBlock(sidechain and "ChannelView: add sidechain send"
                                 or "ChannelView: add send", -1)
  return idx ~= nil and idx >= 0
end

local function track_items(ctx, track, sidechain)
  local added = false
  local pending_gap = false
  local first = true
  for _, t in ipairs(project_tracks(track)) do
    if t.sep then
      pending_gap = true
    else
      -- A spacer set on the track itself goes ABOVE it, the way REAPER
      -- draws it; a spacer track goes where it sits. Never a rule before
      -- the first entry -- that reads as something missing above it.
      if (pending_gap or t.space) and not first then ImGui.Separator(ctx) end
      pending_gap, first = false, false

      local label = ("   %d  %s##sd%d"):format(t.num, t.name, t.num)
      -- The track you are sending FROM is listed but disabled rather than
      -- dropped. A number missing from the middle of the list reads as a
      -- bug in the list, not as "you can't send to yourself".
      local hit = ImGui.MenuItem(ctx, label, nil, false, not t.self)
      -- the colour swatch, drawn into the item we just laid out
      local ix, iy = ImGui.GetItemRectMin(ctx)
      local _, iy2 = ImGui.GetItemRectMax(ctx)
      local dl = ImGui.GetWindowDrawList(ctx)
      local sw = t.col or C.COL.panel_border
      if t.self then sw = U.with_alpha(sw, 0x60) end
      ImGui.DrawList_AddRectFilled(dl, ix + 2, iy + 2, ix + 9, iy2 - 2, sw, 1.5)
      if hit and SD.add_send(track, t.track, sidechain) then added = true end
    end
  end
  return added
end

-- The right-click menu on a send. Returns true if the chain changed.
function SD.draw_ctx(ctx, track)
  local changed = false
  if want_ctx then
    ImGui.OpenPopup(ctx, "sendctx")
    want_ctx = false
  end
  if ImGui.BeginPopup(ctx, "sendctx") then
    local i = ctx_send
    if i and track then
      local dstch = math.floor(send_get(track, i, "I_DSTCHAN") or 0)
      if ImGui.MenuItem(ctx, "Direct (channels 1/2)", nil, dstch < 2) then
        send_set(track, i, "I_DSTCHAN", 0)
      end
      if ImGui.MenuItem(ctx, "Sidechain (channels 3/4)", nil, dstch >= 2) then
        local dest = reaper.GetTrackSendInfo_Value(track, CAT, i, "P_DESTTRACK")
        if dest and (reaper.GetMediaTrackInfo_Value(dest, "I_NCHAN") or 2) < 4 then
          reaper.SetMediaTrackInfo_Value(dest, "I_NCHAN", 4)
        end
        send_set(track, i, "I_DSTCHAN", 2)
      end
      ImGui.Separator(ctx)
      if ImGui.MenuItem(ctx, "Remove send") then
        reaper.Undo_BeginBlock()
        reaper.RemoveTrackSend(track, CAT, i)
        reaper.Undo_EndBlock("ChannelView: remove send", -1)
        changed = true
      end
    end
    ImGui.EndPopup(ctx)
  end
  return changed
end

-- Returns true on the frame a send was added.
function SD.draw_menu(ctx, track)
  if pending_menu then
    ImGui.OpenPopup(ctx, "sendmenu")
    pending_menu = false
  end
  local added = false
  if ImGui.BeginPopup(ctx, "sendmenu") then
    if ImGui.BeginMenu(ctx, "Direct") then
      ImGui.TextDisabled(ctx, "to channels 1/2")
      ImGui.Separator(ctx)
      if track_items(ctx, track, false) then added = true end
      ImGui.EndMenu(ctx)
    end
    if ImGui.BeginMenu(ctx, "Sidechain") then
      ImGui.TextDisabled(ctx, "to channels 3/4")
      ImGui.Separator(ctx)
      if track_items(ctx, track, true) then added = true end
      ImGui.EndMenu(ctx)
    end
    ImGui.EndPopup(ctx)
  end
  return added
end

-- ---------------------------------------------------------------------
-- routing
-- ---------------------------------------------------------------------

-- REAPER's own routing window, via the action that opens it for the
-- last-touched track. There is no API that takes a track, so the track
-- has to BE the last-touched one first -- which it normally already is,
-- since this window follows the selection both ways, but not if the
-- selection was changed from a script or a control surface since.
local ROUTING_ACTION = 40293   -- Track: View routing and I/O for current track

function SD.open_routing(track)
  if not track then return end
  -- Only reselect if we have to. Clobbering a multi-track selection to
  -- open a window the user could have opened from the mixer would be a
  -- poor trade, and this window follows the selection anyway, so the
  -- track is almost always already the one.
  if track ~= reaper.GetSelectedTrack2(0, 0, true) then
    reaper.SetOnlyTrackSelected(track)
  end
  reaper.Main_OnCommand(ROUTING_ACTION, 0)
end

-- { parent/master send, sends out, receives in } -- the same three the
-- routing button in REAPER's mixer lights up.
function SD.route_leds(track)
  if not track then return { false, false, false } end
  local master = (track == reaper.GetMasterTrack(0))
  return {
    -- The master has nowhere to send to, so its lamp is off rather than
    -- reporting on a property it does not have.
    (not master) and (reaper.GetMediaTrackInfo_Value(track, "B_MAINSEND") or 0) > 0.5 or false,
    (reaper.GetTrackNumSends(track, 0)  or 0) > 0,
    (reaper.GetTrackNumSends(track, -1) or 0) > 0,
  }
end

-- ---------------------------------------------------------------------
-- drawing
-- ---------------------------------------------------------------------

function SD.draw(ctx, track, avail_h)
  local collapsed = St.is_collapsed(KEY)
  local sends = collapsed and {} or SD.collect(track)
  local w = SD.width(collapsed, #sends, avail_h)

  local ok = ImGui.BeginChild(ctx, "sendspanel", w, avail_h, 0,
    ImGui.WindowFlags_NoScrollbar | ImGui.WindowFlags_NoScrollWithMouse)
  local req = {}
  if ok then
    local dl = ImGui.GetWindowDrawList(ctx)
    local x, y = ImGui.GetWindowPos(ctx)
    local ww, wh = ImGui.GetWindowSize(ctx)

    ImGui.DrawList_AddRectFilled(dl, x, y, x + ww, y + wh, C.COL.panel_bg, 3.0)
    ImGui.DrawList_AddRect(dl, x, y, x + ww, y + wh, C.COL.panel_border, 3.0, 0, 1.0)

    if collapsed then
      local btn = C.ICON_SIZE
      ImGui.SetCursorScreenPos(ctx, x + (ww - btn) * 0.5, y + 4)
      if W.icon_button(ctx, "sdexp", "expand", btn, false, "Expand the sends") then
        St.toggle_collapsed(KEY)
      end
      local n = track and (reaper.GetTrackNumSends(track, CAT) or 0) or 0
      W.vertical_text(ctx, dl, x + ww * 0.5, y + 4 + btn + 6,
        "SENDS " .. n, C.COL.header_dim, wh - btn - 16)
    else
      -- header
      ImGui.DrawList_AddRectFilled(dl, x, y, x + ww, y + C.HEADER_H, C.COL.header_bg, 0)
      ImGui.DrawList_AddLine(dl, x, y + C.HEADER_H, x + ww, y + C.HEADER_H,
        C.COL.panel_border, 1.0)
      local _, th = ImGui.CalcTextSize(ctx, "Sends")
      ImGui.DrawList_AddText(dl, x + 6, y + (C.HEADER_H - th) * 0.5,
        C.COL.header_text, "Sends")
      local btn = C.ICON_SIZE

      -- Routing, to the left of the collapse control. The lamps report
      -- what the panel below cannot: sends are in view here, but the
      -- parent send and anything arriving from elsewhere are not.
      local leds = SD.route_leds(track)
      ImGui.SetCursorScreenPos(ctx, x + ww - btn * 2 - 9, y + 3)
      if W.route_button(ctx, "sdroute", btn, btn, leds,
          ("Routing and I/O\n%s\n%s\n%s")
          :format(leds[1] and "Sends to parent/master" or "No parent/master send",
                  leds[2] and "Sends to other tracks"  or "No sends",
                  leds[3] and "Receives from elsewhere" or "No receives")) then
        SD.open_routing(track)
      end

      ImGui.SetCursorScreenPos(ctx, x + ww - btn - 3, y + 3)
      if W.icon_button(ctx, "sdcol", "collapse", btn, false, "Collapse the sends") then
        St.toggle_collapsed(KEY)
      end

      if track then
        if SD.draw_sends(ctx, dl, x, y + C.HEADER_H, ww, wh - C.HEADER_H,
                         track, sends) then
          req.changed = true
        end
      end
    end
    ImGui.EndChild(ctx)
  else
    -- Culled: still occupy the space, or the parent's bounds
    -- never grow past it. See W.child_skipped.
    W.child_skipped(ctx, w, avail_h)
  end
  return w, req
end

-- Returns true when a send was removed, so the caller can rescan.
function SD.draw_sends(ctx, dl, x, y, w, h, track, sends)
  local remove_idx = nil
  local pad  = C.PANEL_PAD
  local rows = P.rows_for(h + C.HEADER_H)     -- same row count as a panel
  local gx, gy = x + pad, y + C.GRID_TOP_PAD

  -- cell(i) -> top-left of the i'th cell, flowing down then across, in
  -- double-width columns
  local function cell(i)
    local col = math.floor(i / rows)
    local row = i % rows
    return gx + col * (C.SEND_W + C.SEND_COL_GAP), gy + row * C.CELL_H
  end

  for n, sd in ipairs(sends) do
    local cxp, cyp = cell(n - 1)

    -- The destination's colour is a bar down the LEFT edge, the way a
    -- mixer marks a strip. Across the top it was stealing the row the
    -- name wanted and pushing everything else down; down the side it
    -- costs four pixels and leaves the cell to its contents.
    local BAR = 4
    ImGui.DrawList_AddRectFilled(dl, cxp + 2, cyp,
      cxp + 2 + BAR, cyp + C.CELL_H - 4,
      sd.colour or C.COL.panel_border, 1.5)

    local ix  = cxp + 2 + BAR + 3          -- inside the bar
    local iw  = C.SEND_W - (ix - cxp) - 3  -- and what's left of the cell

    -- The name goes in the band the knob already reserves for a label,
    -- just drawn across the rest of the cell rather than over one half of
    -- it. The knob itself stays at the TOP of its cell: lift it and its
    -- value readout drops out of the bottom, drop it and the name and the
    -- knob's face collide -- which is what they were doing.
    local nm  = U.truncate(sd.name, 22)
    local ntw = ImGui.CalcTextSize(ctx, nm)
    while ntw > iw and #nm > 2 do
      nm = nm:sub(1, #nm - 1)
      ntw = ImGui.CalcTextSize(ctx, nm)
    end
    ImGui.DrawList_AddText(dl, ix, cyp, C.COL.label, nm)

    ImGui.SetCursorScreenPos(ctx, ix, cyp)
    local ch, nv, act = W.knob(ctx, "sv" .. sd.idx, "",
      U.vol_to_fader(sd.vol), U.db_text(sd.vol),
      { tooltip = ("%s\n%s dB   %s"):format(sd.name, U.db_text(sd.vol),
          (sd.dstch >= 2) and "sidechain 3/4" or "direct 1/2") })
    -- Double-click is unity here, the same as the channel fader: a send
    -- at 0 dB is the thing you keep coming back to.
    if act and act.double_click then nv, ch = U.UNITY_POS, true end
    if ch then send_set(track, sd.idx, "D_VOL", U.fader_to_vol(nv)) end
    if act and act.right_click then ctx_send, want_ctx = sd.idx, true end

    -- The buttons are centred on the knob's FACE, not on the cell: the
    -- name sits above it and the value below, so the cell's own middle is
    -- a few pixels off from the thing the eye actually lines up with.
    local face  = W.knob_face_y(cyp)
    local rx    = ix + C.CELL_W + 2
    local rw    = C.SEND_W - (rx - cxp) - 3
    local bh, bgap = 15, 3
    local by1   = face - (bh * 2 + bgap) * 0.5
    local by2   = by1 + bh + bgap
    local hw    = (rw - bgap) * 0.5
    local sc    = (sd.dstch or 0) >= 2

    -- Mute and sidechain side by side: one is the send's own state, the
    -- other is where it lands, and stacking them implied an order that
    -- isn't there.
    local hit, dbl = W.state_button(ctx, "sm" .. sd.idx, "M", rx, by1, hw, bh,
      sd.mute, C.COL.mute_on, "Bypass this send")
    if hit or dbl then send_set(track, sd.idx, "B_MUTE", (dbl or sd.mute) and 0 or 1) end

    hit, dbl = W.state_button(ctx, "sc" .. sd.idx, "SC", rx + hw + bgap, by1,
      hw, bh, sc, C.COL.knob_fill_bi,
      sc and "Sidechain \u{2014} channels 3/4" or "Direct \u{2014} channels 1/2")
    if hit or dbl then
      local want = (dbl or sc) and 0 or 2
      if want == 2 then
        local dest = reaper.GetTrackSendInfo_Value(track, CAT, sd.idx, "P_DESTTRACK")
        if dest and (reaper.GetMediaTrackInfo_Value(dest, "I_NCHAN") or 2) < 4 then
          reaper.SetMediaTrackInfo_Value(dest, "I_NCHAN", 4)
        end
      end
      send_set(track, sd.idx, "I_DSTCHAN", want)
    end

    local is_pre = (sd.mode ~= POST)
    hit, dbl = W.state_button(ctx, "sp" .. sd.idx, is_pre and "PRE" or "POST",
      rx, by2, rw, bh, is_pre, C.COL.accent,
      is_pre and "Pre-fader \u{2014} click for post"
              or "Post-fader \u{2014} click for pre")
    -- REAPER's own default for a new send is post-fader, so that is what
    -- a double-click goes back to.
    if dbl then send_set(track, sd.idx, "I_SENDMODE", POST)
    elseif hit then send_set(track, sd.idx, "I_SENDMODE", is_pre and POST or PRE) end

    -- Same corner, same badge as a parameter cell -- here it deletes the
    -- send itself rather than a control, which is why it says so.
    -- Inset past the colour bar: the two share the left edge and the x
    -- was sitting on top of it.
    if W.remove_badge(ctx, "sd" .. sd.idx, cxp, cyp, C.SEND_W, C.CELL_H,
                      "Remove this send", BAR + 4) then
      remove_idx = sd.idx
    end
  end

  -- the add tile: simply the next cell on the grid, inset evenly inside
  -- it. Drawn at the cell's own corner it carried all its slack on the
  -- right and read as pushed left -- most obviously with a single column,
  -- where there is nothing beside it to blame the gap on.
  local cx0, cy0 = cell(#sends)
  local aw, ah = C.SEND_W - 6, C.CELL_H - 6
  local ax, ay = cx0 + (C.SEND_W - aw) * 0.5, cy0 + (C.CELL_H - ah) * 0.5
  ImGui.SetCursorScreenPos(ctx, ax, ay)
  local pressed = ImGui.InvisibleButton(ctx, "addsend", aw, ah)
  local hovered = ImGui.IsItemHovered(ctx)
  local colr = hovered and C.COL.accent or C.COL.panel_border
  local dash, gap = 5, 4
  local function dashed_h(yy)
    local px = ax
    while px < ax + aw do
      ImGui.DrawList_AddLine(dl, px, yy, math.min(px + dash, ax + aw), yy, colr, 1.0)
      px = px + dash + gap
    end
  end
  local function dashed_v(xx)
    local py = ay
    while py < ay + ah do
      ImGui.DrawList_AddLine(dl, xx, py, xx, math.min(py + dash, ay + ah), colr, 1.0)
      py = py + dash + gap
    end
  end
  dashed_h(ay); dashed_h(ay + ah - 1); dashed_v(ax); dashed_v(ax + aw - 1)
  W.ICONS.plus(dl, ax + (aw - 18) * 0.5, ay + (ah - 18) * 0.5, 18,
    hovered and C.COL.icon_hot or C.COL.icon)
  W.tip(ctx, "addsend", "Add a send", hovered, false)
  if pressed then SD.open_menu() end

  -- Deleted at the END of the frame, never in the middle of the loop:
  -- every send after this one shifts down by one, and the cells for them
  -- have already been drawn with the old indices.
  if remove_idx then
    reaper.Undo_BeginBlock()
    reaper.RemoveTrackSend(track, CAT, remove_idx)
    reaper.Undo_EndBlock("ChannelView: remove send", -1)
    return true
  end
  return false
end

return SD
