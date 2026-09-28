-- @noindex
-- Not a package of its own: installed by TS_ChannelView.lua's @provides.
--[[
  TS_CV_Lanes.lua -- REAPER 7's fixed item lanes, in the TCP.

  A track with fixed lanes (I_FREEMODE 2) stacks several lanes of items
  inside its own height -- takes, alternatives, a comp. Nothing about
  that disturbs the TCP's alignment: the lanes are inside I_TCPH, so the
  row is simply taller. What REAPER's own panel adds, and this adds too,
  is a control per lane, level with that lane:

    * a play button -- click: this lane plays alone; ctrl-click: it plays
      along with the others (or stops) -- REAPER's C_LANEPLAYS
    * the lane's name (P_LANENAME) in its tooltip
    * right-click for the rest: play states, rename, collapse the lanes,
      turn fixed lanes off

  They sit in a column one button wide on the right of the row, beside
  the name and the meter rather than over them. The column is reserved on EVERY row while
  any track in the project uses fixed lanes, so the meters keep one
  width, the same rule the icon column follows.

  Where each lane is: REAPER keeps an item's lane position in
  F_FREEMODE_Y / F_FREEMODE_H (fractions of the track's height) in fixed
  lane mode too, so where a lane has an item that's the answer; lanes
  with none share the height evenly, which is how REAPER lays them out.
--]]

local C  = require("TS_CV_Config")
local U  = require("TS_CV_Util")
local W  = require("TS_CV_Widgets")
local AC = require("TS_CV_Actions")

local LN = {}
local ImGui

function LN.attach(imgui) ImGui = imgui end

-- ---------------------------------------------------------------------
-- pure
-- ---------------------------------------------------------------------

-- Each lane's { y, h } as fractions of the track height. `known` maps a
-- 0-based lane index to a { y, h } read off an item; the rest are even.
function LN.fractions(n, known)
  local out = {}
  for i = 0, n - 1 do
    local k = known and known[i]
    if k and k.h and k.h > 0 then
      out[i] = { y = k.y, h = k.h }
    else
      out[i] = { y = i / n, h = 1 / n }
    end
  end
  return out
end

-- What a click on a lane's play button asks for. `cur` is its current
-- C_LANEPLAYS (0 off, 1 alone, 2 along with others). Plain click: alone,
-- or off if it already was. Ctrl: along with the others, or off.
function LN.next_play(cur, additive)
  if additive then return (cur == 2) and 0 or 2 end
  return (cur == 1) and 0 or 1
end

-- ---------------------------------------------------------------------
-- REAPER side
-- ---------------------------------------------------------------------

local function num(track, key, d) return reaper.GetMediaTrackInfo_Value(track, key) or d end

function LN.is_fixed(track)  return track ~= nil and num(track, "I_FREEMODE", 0) == 2 end
function LN.count(track)     return math.floor(num(track, "I_NUMFIXEDLANES", 0)) end
function LN.collapsed(track) return num(track, "C_LANESCOLLAPSED", 0) > 0 end
function LN.plays(track, i)  return math.floor(num(track, "C_LANEPLAYS:" .. i, 0)) end

function LN.name(track, i)
  local ok, nm = reaper.GetSetMediaTrackInfo_String(track, "P_LANENAME:" .. i, "", false)
  if ok and nm and nm ~= "" then return nm end
  return nil
end

local function refresh()
  reaper.UpdateTimeline()
  reaper.TrackList_AdjustWindows(false)
  reaper.UpdateArrange()
end

function LN.set_play(track, i, v)
  reaper.Undo_BeginBlock()
  if v == 1 then
    -- Alone means alone: the others go off first, whatever REAPER would
    -- have done with them on its own.
    for j = 0, LN.count(track) - 1 do
      if j ~= i and LN.plays(track, j) ~= 0 then
        reaper.SetMediaTrackInfo_Value(track, "C_LANEPLAYS:" .. j, 0)
      end
    end
  end
  reaper.SetMediaTrackInfo_Value(track, "C_LANEPLAYS:" .. i, v)
  reaper.Undo_EndBlock("ChannelView TCP: lane play", -1)
  refresh()
end

function LN.rename(track, i, name)
  reaper.Undo_BeginBlock()
  reaper.GetSetMediaTrackInfo_String(track, "P_LANENAME:" .. i, name or "", true)
  reaper.Undo_EndBlock("ChannelView TCP: rename lane", -1)
  refresh()
end

function LN.set_collapsed(track, on)
  reaper.Undo_BeginBlock()
  reaper.SetMediaTrackInfo_Value(track, "C_LANESCOLLAPSED", on and 1 or 0)
  reaper.Undo_EndBlock(on and "ChannelView TCP: collapse lanes"
                           or "ChannelView TCP: expand lanes", -1)
  refresh()
end

-- Fixed lanes on or off, for every track in `tracks`.
function LN.set_fixed(tracks, on)
  reaper.Undo_BeginBlock()
  for _, tr in ipairs(tracks) do
    reaper.SetMediaTrackInfo_Value(tr, "I_FREEMODE", on and 2 or 0)
  end
  reaper.Undo_EndBlock(on and "ChannelView: fixed item lanes on"
                           or "ChannelView: fixed item lanes off", -1)
  refresh()
end

-- Whether any track in the project uses fixed lanes: the TCP reserves
-- the lane column on every row while one does.
function LN.any()
  for i = 0, reaper.CountTracks(0) - 1 do
    if LN.is_fixed(reaper.GetTrack(0, i)) then return true end
  end
  return false
end

-- Lane positions, from items where there are some. Cached per track
-- against the project's change count: walking items isn't something to
-- do sixty times a second on a track with hundreds of them.
local geo = {}

function LN.layout(track, n)
  local cc = reaper.GetProjectStateChangeCount(0)
  local k = tostring(track)
  local c = geo[k]
  if c and c.cc == cc and c.n == n then return c.fr end
  local known, found = {}, 0
  local m = reaper.CountTrackMediaItems(track)
  for i = 0, math.min(m, 400) - 1 do
    local it = reaper.GetTrackMediaItem(track, i)
    local lane = math.floor(reaper.GetMediaItemInfo_Value(it, "I_FIXEDLANE") or -1)
    if lane >= 0 and lane < n and not known[lane] then
      known[lane] = { y = reaper.GetMediaItemInfo_Value(it, "F_FREEMODE_Y") or 0,
                      h = reaper.GetMediaItemInfo_Value(it, "F_FREEMODE_H") or 0 }
      found = found + 1
      if found >= n then break end
    end
  end
  local fr = LN.fractions(n, known)
  geo[k] = { cc = cc, n = n, fr = fr }
  return fr
end

-- REAPER's own lane actions, by their exact names (with the command ids
-- as the fallback). All of these work on the selected tracks, so each is
-- run on the one track through AC.run_on_track.
LN.ACT = {
  add_bottom  = { "Track lanes: Add empty lane at bottom of track", 42647 },
  add_top     = { "Track lanes: Insert empty lane at top of track", 42500 },
  del_empty   = { "Track lanes: Delete empty lanes with no media items", 42689 },
  del_silent  = { "Track lanes: Delete lanes (including media items) that are not playing", 42691 },
  play_all    = { "Track lanes: Play all lanes", 42799 },
  play_none   = { "Track lanes: Play no lanes", 42800 },
  comp_new    = { "Track lanes: Comp into new empty lane", 42797 },
  comp_off    = { "Track lanes: Turn off comping", 42692 },
  dup_playing = { "Track lanes: Duplicate items from playing lanes to new lanes", 42505 },
}

function LN.run(track, key, undo)
  local a = LN.ACT[key]
  return AC.run_on_track(track, a[1], a[2], "ChannelView TCP: " .. undo)
end

-- The play states that would leave ONLY lane `i` silent, from the
-- current ones -- for deleting one lane with REAPER's "delete lanes that
-- are not playing". Pure; `plays` is 0-based.
function LN.isolate_for_delete(plays, n, i)
  local out = {}
  for j = 0, n - 1 do
    if j == i then out[j] = 0
    elseif (plays[j] or 0) == 0 then out[j] = 2
    else out[j] = plays[j] end
  end
  return out
end

-- The play states to put back after lane `i` has gone: every lane after
-- it has moved up one.
function LN.after_delete(plays, n, i)
  local out = {}
  for j = 0, n - 1 do
    if j < i then out[j] = plays[j] or 0
    elseif j > i then out[j - 1] = plays[j] or 0 end
  end
  return out
end

-- Deletes lane `i` and its items. REAPER has no "delete lane N" action,
-- only "delete lane under mouse" and "delete lanes that are not
-- playing" -- so, in one undo point: every other lane is set playing,
-- lane i silent, the latter action run, and the play states put back.
function LN.delete_lane(track, i)
  local n = LN.count(track)
  if n < 1 or i < 0 or i >= n then return end
  local before = {}
  for j = 0, n - 1 do before[j] = LN.plays(track, j) end
  local tmp = LN.isolate_for_delete(before, n, i)
  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)
  for j = 0, n - 1 do reaper.SetMediaTrackInfo_Value(track, "C_LANEPLAYS:" .. j, tmp[j]) end
  local a = LN.ACT.del_silent
  local id = AC.find(a[1], a[2])
  if id then
    local sel = {}
    for k = 0, reaper.CountSelectedTracks2(0, true) - 1 do
      sel[#sel + 1] = reaper.GetSelectedTrack2(0, k, true)
    end
    reaper.SetOnlyTrackSelected(track)
    reaper.Main_OnCommand(id, 0)
    reaper.Main_OnCommand(40297, 0)
    for _, t in ipairs(sel) do
      if reaper.ValidatePtr2(0, t, "MediaTrack*") then reaper.SetTrackSelected(t, true) end
    end
  end
  -- Put the play states back, the lone lane last, since setting a lane
  -- to play alone can switch the others off.
  local after = LN.after_delete(before, n, i)
  local solo = nil
  for j = 0, n - 2 do
    if after[j] == 1 then solo = j
    else reaper.SetMediaTrackInfo_Value(track, "C_LANEPLAYS:" .. j, after[j] or 0) end
  end
  if solo then reaper.SetMediaTrackInfo_Value(track, "C_LANEPLAYS:" .. solo, 1) end
  reaper.PreventUIRefresh(-1)
  reaper.Undo_EndBlock("ChannelView TCP: delete lane", -1)
  refresh()
end

-- ---------------------------------------------------------------------
-- menus
-- ---------------------------------------------------------------------

local st = { menu_req = nil, menu = nil, ren_req = nil, ren = nil, buf = "", focus = false }

local function lane_label(track, i)
  return LN.name(track, i) or ("Lane " .. (i + 1))
end

local function lane_menu(ctx)
  if st.menu_req then
    st.menu, st.menu_req = st.menu_req, nil
    ImGui.OpenPopup(ctx, "tcp_lanemenu")
  end
  if not ImGui.BeginPopup(ctx, "tcp_lanemenu") then return end
  local m = st.menu
  if not m or not reaper.ValidatePtr2(0, m.track, "MediaTrack*") then
    ImGui.CloseCurrentPopup(ctx)
    ImGui.EndPopup(ctx)
    return
  end
  local tr, i = m.track, m.lane
  local p = LN.plays(tr, i)
  ImGui.TextDisabled(ctx, lane_label(tr, i))
  ImGui.Separator(ctx)
  if ImGui.MenuItem(ctx, "Play this lane alone", nil, p == 1) then LN.set_play(tr, i, 1) end
  if ImGui.MenuItem(ctx, "Play with the other lanes", nil, p == 2) then LN.set_play(tr, i, 2) end
  if ImGui.MenuItem(ctx, "Don't play", nil, p == 0) then LN.set_play(tr, i, 0) end
  ImGui.Separator(ctx)
  if ImGui.MenuItem(ctx, "Rename lane\u{2026}") then
    st.ren_req = { track = tr, lane = i }
  end
  if ImGui.MenuItem(ctx, "Play all lanes") then LN.run(tr, "play_all", "play all lanes") end
  if ImGui.MenuItem(ctx, "Play no lanes") then LN.run(tr, "play_none", "play no lanes") end
  ImGui.Separator(ctx)
  if ImGui.MenuItem(ctx, "Delete this lane (and its items)", nil, false, LN.count(tr) > 1) then
    LN.delete_lane(tr, i)
  end
  if ImGui.BeginMenu(ctx, "Lanes") then
    if ImGui.MenuItem(ctx, "Add a lane at the bottom") then LN.run(tr, "add_bottom", "add lane") end
    if ImGui.MenuItem(ctx, "Insert a lane at the top") then LN.run(tr, "add_top", "insert lane") end
    ImGui.Separator(ctx)
    if ImGui.MenuItem(ctx, "Delete empty lanes") then LN.run(tr, "del_empty", "delete empty lanes") end
    if ImGui.MenuItem(ctx, "Delete lanes that aren't playing") then
      LN.run(tr, "del_silent", "delete silent lanes")
    end
    ImGui.EndMenu(ctx)
  end
  if ImGui.BeginMenu(ctx, "Comping") then
    if ImGui.MenuItem(ctx, "Comp into a new lane") then LN.run(tr, "comp_new", "comp into new lane") end
    if ImGui.MenuItem(ctx, "Turn off comping") then LN.run(tr, "comp_off", "turn off comping") end
    ImGui.Separator(ctx)
    if ImGui.MenuItem(ctx, "Copy the playing lanes' items to new lanes") then
      LN.run(tr, "dup_playing", "duplicate playing lanes")
    end
    ImGui.EndMenu(ctx)
  end
  ImGui.Separator(ctx)
  if ImGui.MenuItem(ctx, "Collapse lanes") then LN.set_collapsed(tr, true) end
  if ImGui.MenuItem(ctx, "Fixed item lanes off") then LN.set_fixed({ tr }, false) end
  ImGui.EndPopup(ctx)
end

local function rename_popup(ctx)
  if st.ren_req then
    st.ren, st.ren_req = st.ren_req, nil
    st.buf = LN.name(st.ren.track, st.ren.lane) or ""
    st.focus = true
    ImGui.OpenPopup(ctx, "tcp_lanerename")
  end
  if not ImGui.BeginPopup(ctx, "tcp_lanerename") then return end
  local r = st.ren
  if not r or not reaper.ValidatePtr2(0, r.track, "MediaTrack*") then
    ImGui.CloseCurrentPopup(ctx)
    ImGui.EndPopup(ctx)
    return
  end
  ImGui.TextDisabled(ctx, "Rename " .. lane_label(r.track, r.lane))
  if st.focus then ImGui.SetKeyboardFocusHere(ctx); st.focus = false end
  ImGui.SetNextItemWidth(ctx, 200)
  local enter, v = ImGui.InputText(ctx, "##lanename", st.buf,
    ImGui.InputTextFlags_EnterReturnsTrue | ImGui.InputTextFlags_AutoSelectAll)
  st.buf = v
  ImGui.SameLine(ctx)
  if enter or ImGui.Button(ctx, "OK") then
    LN.rename(r.track, r.lane, U.trim(st.buf))
    ImGui.CloseCurrentPopup(ctx)
  elseif ImGui.IsKeyPressed(ctx, ImGui.Key_Escape) then
    ImGui.CloseCurrentPopup(ctx)
  end
  ImGui.EndPopup(ctx)
end

-- Call once a frame from the main window, outside any child.
function LN.draw_menus(ctx)
  lane_menu(ctx)
  rename_popup(ctx)
end

-- ---------------------------------------------------------------------
-- the column
-- ---------------------------------------------------------------------

-- Draws the lane controls for one row into the column x0..x1. `e` is the
-- row (its y and h in ImGui coordinates); `id` keeps the widgets apart.
function LN.draw(ctx, dl, track, e, x0, x1, id)
  local n = LN.count(track)
  if n < 1 then return end
  local _, th = ImGui.CalcTextSize(ctx, "Ag")
  local h = e.h - 1

  if LN.collapsed(track) then
    -- One chip at the top: how many lanes there are, and a way back.
    local ch = math.min(th + 4, h - 2)
    if ch < 8 then return end
    local label = tostring(n)            -- the column is one button wide
    local cy = e.y + math.min(C.TCP_PAD, (h - ch) * 0.5)
    if W.state_button(ctx, "lanesexp" .. id, label, x0, cy, x1 - x0, ch, false, nil,
        "Show lanes") then
      LN.set_collapsed(track, false)
    end
    return
  end

  local fr = LN.layout(track, n)
  for i = 0, n - 1 do
    local f  = fr[i]
    local ly = e.y + f.y * h
    local lh = f.h * h
    if lh >= 8 then
      if i > 0 then
        ImGui.DrawList_AddLine(dl, x0, ly + 0.5, x1, ly + 0.5, C.COL.panel_border, 1.0)
      end
      local p   = LN.plays(track, i)
      local bs  = math.min(C.TCP_CHIP + 1, lh - 3, x1 - x0)
      local bx  = x0 + (x1 - x0 - bs) * 0.5
      local by  = ly + math.min(3, (lh - bs) * 0.5)
      -- Play: an accent fill when it plays alone, the contrast colour when
      -- it plays along with others, plain when it doesn't. The lane's name
      -- is in the tooltip -- the column is only a button wide.
      local col = (p == 1) and C.COL.accent or ((p == 2) and C.COL.knob_fill_bi or nil)
      local bid = "lanep" .. id .. ":" .. i
      local hit = W.state_icon(ctx, bid, "play_tri", bx, by, bs, bs, p ~= 0, col,
        lane_label(track, i))
      if ImGui.IsItemClicked(ctx, ImGui.MouseButton_Right) then
        st.menu_req = { track = track, lane = i }
      elseif hit then
        local mods = ImGui.GetKeyMods(ctx)
        local add = (mods & ImGui.Mod_Ctrl) ~= 0 or (mods & ImGui.Mod_Super) ~= 0
        LN.set_play(track, i, LN.next_play(p, add))
      end
    end
  end
end

return LN
