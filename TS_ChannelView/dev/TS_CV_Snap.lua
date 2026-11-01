-- @noindex
--[[
  TS_CV_Snap.lua -- dev tool: a screenshot of the monitor REAPER's main
  window is on, for forum posts. Waits SNAP_DELAY seconds first (so a
  hover preview or a menu can be brought up), then writes
  Downloads/cv_snaps/snap_<date>_<time>.png. Windows only
  (js_ReaScriptAPI). Run it from the Action list or a shortcut.
--]]
local SNAP_DELAY = 8

local function out_dir()
  local home = os.getenv("USERPROFILE") or ""
  local d = home .. "\\Downloads\\cv_snaps\\"
  reaper.RecursiveCreateDirectory(d, 0)
  return d
end

local function shoot()
  local main = reaper.GetMainHwnd()
  local _, l, t, r, b = reaper.JS_Window_GetRect(main)
  local ml, mt, mr, mb = reaper.my_getViewport(0, 0, 0, 0, l, t, r, b, false)
  local w, h = mr - ml, mb - mt
  local bmp = reaper.JS_LICE_CreateBitmap(true, w, h)
  local src = reaper.JS_GDI_GetScreenDC()
  reaper.JS_GDI_Blit(reaper.JS_LICE_GetDC(bmp), 0, 0, src, ml, mt, w, h)
  pcall(reaper.JS_GDI_ReleaseDC, nil, src)
  local path = out_dir() .. os.date("snap_%Y%m%d_%H%M%S") .. ".png"
  reaper.JS_LICE_WritePNG(path, bmp, false)
  reaper.JS_LICE_DestroyBitmap(bmp)
end

if not (reaper.JS_GDI_GetScreenDC and reaper.JS_LICE_WritePNG) then
  reaper.MB("Needs js_ReaScriptAPI.", "Snap", 0)
  return
end
local t0 = reaper.time_precise()
local function wait()
  if reaper.time_precise() - t0 >= SNAP_DELAY then shoot() return end
  reaper.defer(wait)
end
wait()
