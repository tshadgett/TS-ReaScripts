-- @noindex
-- Not a package of its own: installed by TS_ChannelView.lua's @provides.
--[[
  TS_CV_Arrange.lua -- where REAPER's arrange view is, and where each
  track sits in it.

  The TCP window draws its own track panel, and it is only worth anything
  if every row lands exactly beside its track's lane in the arrange view:
  same top, same height, scrolling with it. None of that is copied or
  kept in step by hand. REAPER already knows, per track:

    I_TCPY   the track's top, in pixels, relative to the top of the
             arrange view -- scroll already applied, so it goes negative
             as a track scrolls off the top
    I_TCPH   its height, not counting envelope lanes
    I_WNDH   its height with them

  and js_ReaScriptAPI tells us where the arrange view is on screen. Put
  those together and each row's position is simply read off every frame,
  which means REAPER's own vertical zoom, a height changed in its own TCP,
  a folder collapsing, a spacer -- all of it comes through without this
  file knowing any of them exist.

  Two coordinate spaces meet here. Window rects come back in the
  platform's own units (upside down on macOS; physical pixels on a
  scaled Windows display), ImGui draws in its own. ImGui.PointConvertNative
  converts a point, and converting both corners of the arrange rect gives
  the scale between the two for free -- which is what the track heights,
  which are in REAPER's units, have to be multiplied by.

  The pure part -- turning a list of tracks and a rect into rows -- takes
  no REAPER calls at all, so the offline tests can check it.
--]]

local TO = require("TS_CV_TrackOps")

local AR = {}

local ARRANGE_ID = 1000   -- the arrange view's child id in REAPER's main window

-- ---------------------------------------------------------------------
-- pure: placement
-- ---------------------------------------------------------------------

-- `list`: entries with tcpy, tcph, wndh in REAPER units.
-- `g`: { top, bottom, scale } -- the arrange view in ImGui coordinates.
-- Adds y, h, env (envelope lanes' height) and `visible` to each entry,
-- in ImGui coordinates, and returns the list. A track REAPER isn't
-- drawing (hidden in the TCP, or inside a hidden folder) has no height
-- and is never visible.
function AR.place(list, g)
  local s = g.scale or 1
  for _, e in ipairs(list) do
    e.y   = g.top + (e.tcpy or 0) * s
    e.h   = math.max(0, (e.tcph or 0) * s)
    e.env = math.max(0, ((e.wndh or 0) - (e.tcph or 0)) * s)
    e.visible = e.h > 0
                and (e.y + e.h + e.env) > g.top
                and e.y < g.bottom
  end
  return list
end

-- Which gap a drop at `my` would land in, for reordering: returns the
-- 0-based position to move BEFORE (the track count for "after the
-- last"), and the y to draw the marker at. Only real tracks with a
-- height take part -- the master can't be moved and has no gap. `count`
-- is the project's track count.
function AR.drop_gap(list, my, count)
  local last = nil
  for _, e in ipairs(list) do
    if not e.master and e.h > 0 then
      if my < e.y + (e.h + e.env) * 0.5 then
        return e.num - 1, e.y
      end
      last = e
    end
  end
  if last then return count, last.y + last.h + last.env end
  return nil
end

-- Where a drop at `my` would land, reordering or nesting: over the top
-- or bottom quarter of a row it's the gap on that side (as AR.drop_gap:
-- returns the 0-based position to move before, and the marker's y); over
-- the middle half it's INTO that track, as its children (returns nil,
-- nil, and the row's entry). Envelope lanes count as the gap below. A gap
-- after a row is the one before the next row that's actually drawn, so a
-- drop under a folder whose children are hidden lands after them, not
-- inside it.
function AR.drop_target(list, my, count)
  local rows = {}
  for _, e in ipairs(list) do
    if not e.master and e.h > 0 then rows[#rows + 1] = e end
  end
  for i, e in ipairs(rows) do
    local full = e.h + e.env
    if my < e.y + full then
      local zone = TO.drop_zone((my - e.y) / math.max(1, e.h))
      if my >= e.y + e.h then zone = "after" end
      if zone == "before" then return e.num - 1, e.y end
      if zone == "into" then return nil, nil, e end
      local nx = rows[i + 1]
      return nx and (nx.num - 1) or count, e.y + full
    end
  end
  local last = rows[#rows]
  if last then return count, last.y + last.h + last.env end
  return nil
end

-- The tracks from one row to another, inclusive, in panel order -- for a
-- shift-click. Rows REAPER isn't drawing are left out: the range is what
-- you can see, the same rule the mixer uses. nil when either end has
-- gone.
function AR.range(list, guid_a, guid_b)
  local a, b
  for i, e in ipairs(list) do
    if e.guid == guid_a then a = i end
    if e.guid == guid_b then b = i end
  end
  if not a or not b then return nil end
  if a > b then a, b = b, a end
  local out = {}
  for i = a, b do
    local e = list[i]
    if not e.master and e.h > 0 then out[#out + 1] = e.track end
  end
  return out
end

-- A native rect's two corners, already converted, to top/bottom/scale.
-- Kept apart from the conversion itself so it can be checked offline:
-- on macOS the native y axis runs upward, so either corner can be the
-- top once converted and neither can be assumed.
function AR.rect(l, t, r, b, native_h)
  local top, bottom = math.min(t, b), math.max(t, b)
  local left, right = math.min(l, r), math.max(l, r)
  local s = 1
  if native_h and native_h > 0 then s = (bottom - top) / native_h end
  return { left = left, right = right, top = top, bottom = bottom, scale = s }
end

-- ---------------------------------------------------------------------
-- REAPER side
-- ---------------------------------------------------------------------

function AR.available()
  return reaper.JS_Window_FindChildByID ~= nil
     and reaper.JS_Window_GetClientRect ~= nil
end

local hwnd = nil
function AR.hwnd()
  if not AR.available() then return nil end
  if hwnd and reaper.JS_Window_IsWindow and reaper.JS_Window_IsWindow(hwnd) then
    return hwnd
  end
  hwnd = reaper.JS_Window_FindChildByID(reaper.GetMainHwnd(), ARRANGE_ID)
  return hwnd
end

-- The arrange view's client area -- the lanes, without the scrollbars --
-- in ImGui coordinates, plus the ImGui-per-REAPER-pixel scale. nil when
-- js_ReaScriptAPI is missing or the window can't be found.
function AR.geometry(ctx, ImGui)
  local h = AR.hwnd()
  if not h then return nil end
  local ok, l, t, r, b = reaper.JS_Window_GetClientRect(h)
  if not ok or not (l and t and r and b) then return nil end
  local native_h = math.abs(b - t)
  if native_h <= 0 then return nil end
  local x0, y0, x1, y1 = l, t, r, b
  if ImGui.PointConvertNative then
    x0, y0 = ImGui.PointConvertNative(ctx, l, t, false)
    x1, y1 = ImGui.PointConvertNative(ctx, r, b, false)
  end
  return AR.rect(x0, y0, x1, y1, native_h)
end

-- Every track REAPER's TCP would show, in its order, master first when
-- it's visible there. Folder depth is worked out on the way down, since
-- REAPER stores each track's CHANGE in depth, not the depth itself.
function AR.collect()
  local out = {}
  local master = reaper.GetMasterTrack(0)
  if master and (reaper.GetMasterTrackVisibility() & 1) == 1 then
    out[#out + 1] = {
      track = master, master = true, num = 0, guid = "master", depth = 0,
      tcpy = reaper.GetMediaTrackInfo_Value(master, "I_TCPY") or 0,
      tcph = reaper.GetMediaTrackInfo_Value(master, "I_TCPH") or 0,
      wndh = reaper.GetMediaTrackInfo_Value(master, "I_WNDH") or 0,
    }
  end
  local depth = 0
  for i = 0, reaper.CountTracks(0) - 1 do
    local tr = reaper.GetTrack(0, i)
    local fd = math.floor(reaper.GetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH") or 0)
    local shown = (reaper.GetMediaTrackInfo_Value(tr, "B_SHOWINTCP") or 1) > 0.5
    out[#out + 1] = {
      track  = tr,
      num    = i + 1,
      guid   = reaper.GetTrackGUID(tr) or ("t" .. i),
      depth  = depth,
      folder = fd > 0,
      tcpy   = reaper.GetMediaTrackInfo_Value(tr, "I_TCPY") or 0,
      tcph   = shown and (reaper.GetMediaTrackInfo_Value(tr, "I_TCPH") or 0) or 0,
      wndh   = shown and (reaper.GetMediaTrackInfo_Value(tr, "I_WNDH") or 0) or 0,
    }
    depth = math.max(0, depth + fd)
  end
  return out
end

-- Scrolls the arrange view by `px` of REAPER's pixels, positive down.
--
-- The scrollbar is set directly when js_ReaScriptAPI can do it, which is
-- exact; otherwise REAPER's control-surface scroll, which moves in steps
-- of its own choosing but at least moves.
function AR.scroll(px)
  local h = AR.hwnd()
  if h and reaper.JS_Window_GetScrollInfo and reaper.JS_Window_SetScrollPos then
    local ok, pos, page, mn, mx = reaper.JS_Window_GetScrollInfo(h, "v")
    if ok then
      local hi = math.max(mn, mx - page + 1)
      local np = math.max(mn, math.min(hi, pos + px))
      if np ~= pos then reaper.JS_Window_SetScrollPos(h, "v", math.floor(np + 0.5)) end
      return true
    end
  end
  reaper.CSurf_OnScroll(0, px > 0 and 1 or -1)
  return true
end

-- Sets a height, in REAPER pixels, on each of `tracks`. 0 hands the
-- track back to REAPER's own default height.
function AR.set_height(tracks, h)
  h = math.max(0, math.floor(h + 0.5))
  reaper.PreventUIRefresh(1)
  for _, tr in ipairs(tracks) do
    reaper.SetMediaTrackInfo_Value(tr, "I_HEIGHTOVERRIDE", h)
  end
  reaper.PreventUIRefresh(-1)
  reaper.TrackList_AdjustWindows(false)
end

return AR
