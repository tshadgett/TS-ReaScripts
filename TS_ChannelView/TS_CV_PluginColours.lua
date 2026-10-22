-- @noindex
-- Not a package of its own: installed by TS_ChannelView.lua's @provides.
--[[
  TS_CV_PluginColours.lua -- a plugin's own colours, read off its window.

  PC.start(track, addr, guid, done) floats the plugin's window (when it
  isn't already), brings it to the front, gives it a moment to paint,
  copies it off the screen and samples it; then closes the window again
  if it opened it, and calls done({ surfaces = {...}, accents = {...} })
  (each 0xRRGGBB, most used first), or done(nil, why). PC.tick() every
  frame runs it.

  Surfaces are the colours that cover the most of the GUI (its base, its
  raised panels); accents are the saturated, bright ones (arcs, LEDs),
  each the average of its bright core, not of its anti-aliased edges.
  Only the plugin's own GUI is sampled, not REAPER's bar above it.

  Windows only, with js_ReaScriptAPI: the screen is read with GDI.
--]]

local PC = {}

PC.OPEN_SECS = 1.5     -- a window opened here gets this long to paint
PC.FRONT_SECS = 0.4    -- one already open, this long once in front
PC.WAIT_SECS = 5.0     -- give up on a window that doesn't appear

local job = nil        -- { track, addr, guid, done, opened, t0, hwnd, stage }

function PC.supported()
  local os = (reaper.GetOS and reaper.GetOS()) or ""
  return os:match("^Win") ~= nil and reaper.JS_Window_GetRect ~= nil
     and reaper.JS_GDI_GetScreenDC ~= nil and reaper.JS_GDI_Blit ~= nil
     and reaper.JS_LICE_CreateBitmap ~= nil and reaper.JS_LICE_GetDC ~= nil
     and reaper.JS_LICE_GetPixel ~= nil
end

-- Whether a plugin's colours are being read now.
function PC.busy(guid) return job ~= nil and (guid == nil or job.guid == guid) end

-- The rectangle of the plugin's own GUI in its REAPER window: the largest
-- window inside it that starts below the top of the window's client area
-- (REAPER's preset bar and buttons sit along that top), or the client
-- area less REAPER's bar when there's none.
local BAR_PX = 45      -- REAPER's bar, when the GUI can't be found

local function gui_rect(hwnd)
  local ok, l, t, r, b
  if reaper.JS_Window_GetClientRect then ok, l, t, r, b = reaper.JS_Window_GetClientRect(hwnd) end
  if not ok then
    ok, l, t, r, b = reaper.JS_Window_GetRect(hwnd)
    if not ok then return nil end
    t = t + 31     -- the title bar
  end
  local best, area = nil, 0
  if reaper.JS_Window_ListAllChild and reaper.JS_Window_HandleFromAddress then
    local n, list = reaper.JS_Window_ListAllChild(hwnd)
    if n and n > 0 and list then
      for a in list:gmatch("[^,]+") do
        local h = reaper.JS_Window_HandleFromAddress(tonumber(a) or 0)
        local ok2, cl, ct, cr, cb
        if h then ok2, cl, ct, cr, cb = reaper.JS_Window_GetRect(h) end
        if ok2 and ct > t + 4 and (not reaper.JS_Window_IsVisible or reaper.JS_Window_IsVisible(h)) then
          local ar = (cr - cl) * (cb - ct)
          if ar > area then best, area = { cl, ct, cr, cb }, ar end
        end
      end
    end
  end
  -- a child much smaller than the window isn't the GUI
  if not best or area < 0.3 * (r - l) * (b - t) then
    best = { l, t + math.min(BAR_PX, (b - t) // 3), r, b }
  end
  -- only what's on the screen (the monitor the window is mostly on)
  if reaper.my_getViewport then
    local sl, st, sr, sb = reaper.my_getViewport(0, 0, 0, 0, best[1], best[2], best[3], best[4], false)
    if sr > sl and sb > st then
      best = { math.max(best[1], sl), math.max(best[2], st), math.min(best[3], sr), math.min(best[4], sb) }
    end
  end
  if best[3] - best[1] < 8 or best[4] - best[2] < 8 then return nil end
  return best
end

local function hsv(r, g, b)
  r, g, b = r / 255, g / 255, b / 255
  local mx, mn = math.max(r, g, b), math.min(r, g, b)
  local d = mx - mn
  local h = 0
  if d > 0 then
    if mx == r then h = ((g - b) / d) % 6
    elseif mx == g then h = (b - r) / d + 2
    else h = (r - g) / d + 4 end
    h = h / 6
  end
  return h, (mx > 0) and d / mx or 0, mx
end

local function dist(a, b)
  return math.abs(((a >> 16) & 0xff) - ((b >> 16) & 0xff)) + math.abs(((a >> 8) & 0xff) - ((b >> 8) & 0xff))
       + math.abs((a & 0xff) - (b & 0xff))
end

-- The most used of `list` ({ rgb, n }), leaving out any too near one
-- already in, and any under `min` samples.
local function pick(list, limit, near, min)
  table.sort(list, function(a, b) return a.n > b.n end)
  local out = {}
  for _, v in ipairs(list) do
    if #out >= limit or v.n < min then break end
    local dup = false
    for _, o in ipairs(out) do
      if dist(o, v.rgb) < near then dup = true break end
    end
    if not dup then out[#out + 1] = v.rgb end
  end
  return out
end

-- Samples the bitmap (w x h): about 160 x 160 points.
function PC.sample(get, w, h)
  local bins, hues, total = {}, {}, 0
  local sx, sy = math.max(1, w // 160), math.max(1, h // 160)
  for y = 0, h - 1, sy do
    for x = 0, w - 1, sx do
      local px = get(x, y)
      local r, g, b = (px >> 16) & 0xff, (px >> 8) & 0xff, px & 0xff
      total = total + 1
      local k = ((r >> 3) << 10) | ((g >> 3) << 5) | (b >> 3)
      local bn = bins[k]
      if not bn then bn = { n = 0, r = 0, g = 0, b = 0 }; bins[k] = bn end
      bn.n, bn.r, bn.g, bn.b = bn.n + 1, bn.r + r, bn.g + g, bn.b + b
      local hh, ss, vv = hsv(r, g, b)
      if ss > 0.5 and vv > 0.55 then
        local hk = math.floor(hh * 24)
        local hb = hues[hk]
        if not hb then hb = { n = 0, r = 0, g = 0, b = 0, cn = 0, cr = 0, cg = 0, cb = 0 }; hues[hk] = hb end
        hb.n = hb.n + 1
        if vv > 0.8 and ss > 0.6 then
          hb.cn, hb.cr, hb.cg, hb.cb = hb.cn + 1, hb.cr + r, hb.cg + g, hb.cb + b
        else
          hb.r, hb.g, hb.b = hb.r + r, hb.g + g, hb.b + b
        end
      end
    end
  end
  local sl, al = {}, {}
  for _, v in pairs(bins) do
    sl[#sl + 1] = { n = v.n, rgb = ((v.r // v.n) << 16) | ((v.g // v.n) << 8) | (v.b // v.n) }
  end
  for _, v in pairs(hues) do
    local n, r, g, b = v.cn, v.cr, v.cg, v.cb
    if n == 0 then n, r, g, b = v.n, v.r, v.g, v.b end
    al[#al + 1] = { n = v.n, rgb = ((r // n) << 16) | ((g // n) << 8) | (b // n) }
  end
  return { surfaces = pick(sl, 6, 30, math.max(2, total * 0.01)),
           accents  = pick(al, 4, 60, math.max(3, total * 0.001)) }
end

local function capture(hwnd)
  local rc = gui_rect(hwnd)
  if not rc then return nil, "its window isn't on the screen" end
  local w, h = rc[3] - rc[1], rc[4] - rc[2]
  local bmp = reaper.JS_LICE_CreateBitmap(true, w, h)
  if not bmp then return nil, "no bitmap" end
  local dst = reaper.JS_LICE_GetDC(bmp)
  local src = reaper.JS_GDI_GetScreenDC()
  reaper.JS_GDI_Blit(dst, 0, 0, src, rc[1], rc[2], w, h)
  if reaper.JS_GDI_ReleaseDC then pcall(reaper.JS_GDI_ReleaseDC, hwnd, src) end
  local pal = PC.sample(function(x, y) return reaper.JS_LICE_GetPixel(bmp, x, y) end, w, h)
  reaper.JS_LICE_DestroyBitmap(bmp)
  if #pal.surfaces == 0 then return nil, "nothing to sample" end
  return pal
end

-- Read the colours of plugin `addr` on `track` (fx `guid`); `done(pal)`
-- or `done(nil, why)` when it's over. One at a time.
function PC.start(track, addr, guid, done)
  if job then return false end
  if not PC.supported() then done(nil, "needs Windows and js_ReaScriptAPI") return false end
  local open = reaper.TrackFX_GetFloatingWindow(track, addr)
  job = { track = track, addr = addr, guid = guid, done = done, opened = (open == nil),
          t0 = reaper.time_precise(), stage = "wait" }
  if not open then reaper.TrackFX_Show(track, addr, 3) end
  return true
end

local function finish(pal, why)
  local j = job
  job = nil
  if j.opened and reaper.ValidatePtr(j.track, "MediaTrack*") then reaper.TrackFX_Show(j.track, j.addr, 2) end
  j.done(pal, why)
end

function PC.tick()
  if not job then return end
  local now = reaper.time_precise()
  if not reaper.ValidatePtr(job.track, "MediaTrack*") then return finish(nil, "the track is gone") end
  local hwnd = reaper.TrackFX_GetFloatingWindow(job.track, job.addr)
  if job.stage == "wait" then
    if hwnd then
      if reaper.JS_Window_SetForeground then reaper.JS_Window_SetForeground(hwnd) end
      job.hwnd, job.stage, job.t0 = hwnd, "paint", now
    elseif now - job.t0 > PC.WAIT_SECS then
      return finish(nil, "its window didn't open")
    end
  elseif job.stage == "paint" then
    if not hwnd then return finish(nil, "its window was closed") end
    if now - job.t0 >= (job.opened and PC.OPEN_SECS or PC.FRONT_SECS) then
      local ok, pal, why = pcall(capture, hwnd)
      if not ok then return finish(nil, tostring(pal)) end
      return finish(pal, why)
    end
  end
end

return PC
