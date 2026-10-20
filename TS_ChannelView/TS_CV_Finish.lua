-- @noindex
-- Not a package of its own: installed by TS_ChannelView.lua's @provides.
--[[
  TS_CV_Finish.lua -- surface finishes (C.FINISHES) drawn over faceplates,
  sections and control backgrounds.

  A finish is a texture of light and shade with no colour of its own: each
  tile in textures/ holds, per pixel, white or black and how strongly, so
  it lies over whatever colour the surface already is. The tiles repeat
  seamlessly and are laid from an origin the caller gives (the panel's or
  the grid's), so neighbouring areas line up. Bright and Satin are one
  image stretched across the surface: the room's reflection, with no
  repeat. A finish's `under` is a tile drawn beneath it (Satin's grain).

  Images are made per ImGui context and attached to it; one ReaImGui has
  freed is made again. Without image support (an old ReaImGui) a finish is
  simply not drawn and the surface stays plain.
--]]

local C = require("TS_CV_Config")

local FN = {}
local ImGui

FN.DIR = nil                 -- the textures folder, set by FN.init
local imgs = {}              -- [ctx][key] = image | false

function FN.attach(imgui) ImGui = imgui end

-- `script_dir`: ChannelView's folder; the tiles are in textures/ under it.
function FN.init(script_dir)
  FN.DIR = (script_dir or "") .. "textures/"
end

function FN.file(key) return (FN.DIR or "") .. "TS_CV_finish_" .. key .. ".png" end

-- The finish's image for this context, made on first use.
local function image(ctx, key)
  if not (ImGui and ImGui.CreateImage) then return nil end
  local per = imgs[ctx or 0]
  if not per then per = {}; imgs[ctx or 0] = per end
  local img = per[key]
  if img == false then return nil end
  -- checked once a frame, not on every strip of every surface
  local frame = ImGui.GetFrameCount and ImGui.GetFrameCount(ctx) or 0
  if img and per[key .. "@"] ~= frame then
    if ImGui.ValidatePtr and not ImGui.ValidatePtr(img, "ImGui_Image*") then img = nil
    else per[key .. "@"] = frame end
  end
  if not img then
    local ok, made = pcall(ImGui.CreateImage, FN.file(key))
    if not ok or not made then per[key] = false; return nil end
    if ImGui.Attach then pcall(ImGui.Attach, ctx, made) end
    img = made
    per[key] = img
  end
  return img
end
FN.image = image

-- Whether `key` is a finish that draws anything.
function FN.draws(key)
  local f = key and C.FINISH[key]
  return f ~= nil and (f.tile ~= nil or f.stretch == true)
end

-- The finish `key` over x1..x2, y1..y2. A tiled one is laid from ox, oy;
-- Bright and Satin are stretched over the box bx1..by2 (default: the area
-- itself), so the pieces of one shape show one reflection.
function FN.rect(ctx, dl, key, x1, y1, x2, y2, ox, oy, box)
  if x2 <= x1 or y2 <= y1 or not FN.draws(key) then return end
  local img = image(ctx, key)
  if not img then return end
  local f = C.FINISH[key]
  local function tiles(im, t)
    local ty = oy + math.floor((y1 - oy) / t) * t
    while ty < y2 do
      local tx = ox + math.floor((x1 - ox) / t) * t
      while tx < x2 do
        ImGui.DrawList_AddImage(dl, im, tx, ty, tx + t, ty + t)
        tx = tx + t
      end
      ty = ty + t
    end
  end
  ImGui.DrawList_PushClipRect(dl, x1, y1, x2, y2, true)
  local under = f.under and image(ctx, f.under)
  if under then tiles(under, 256) end
  if f.stretch then
    local b = box or { x1, y1, x2, y2 }
    ImGui.DrawList_AddImage(dl, img, b[1], b[2], b[3], b[4])
  else
    tiles(img, f.tile)
  end
  ImGui.DrawList_PopClipRect(dl)
end

-- Forget every image (a context closed, or the tiles changed on disk).
function FN.clear(ctx)
  if ctx then imgs[ctx] = nil else imgs = {} end
end

return FN
