-- @noindex
-- Not a package of its own: installed by TS_ChannelView.lua's @provides.
--[[
  TS_CV_Icons.lua -- track icons.

  A track's icon is whatever REAPER shows in its track panel (P_ICON):
  a file path, either absolute or relative to REAPER's resource folder
  (usually Data/track_icons). Each file is loaded once, the first time a
  track using it is drawn, and kept for the life of the window; a path
  that can't be found or loaded is remembered as missing, so it isn't
  retried every frame.
--]]

local IC = {}
local ImGui

function IC.attach(imgui) ImGui = imgui end

local cache = {}   -- resolved path -> image, or false when it won't load
local where = {}   -- P_ICON value -> resolved path, or false

local function exists(p)
  local fh = io.open(p, "rb")
  if fh then fh:close() return true end
  return false
end

-- P_ICON as stored -> a path that exists, or nil.
function IC.resolve(raw)
  if not raw or raw == "" then return nil end
  local r = where[raw]
  if r ~= nil then return r or nil end
  local root = reaper.GetResourcePath()
  local sep = root:find("\\", 1, true) and "\\" or "/"
  local tries = { raw,
                  root .. sep .. "Data" .. sep .. raw,
                  root .. sep .. "Data" .. sep .. "track_icons" .. sep .. raw,
                  root .. sep .. raw }
  for _, p in ipairs(tries) do
    if exists(p) then where[raw] = p return p end
  end
  where[raw] = false
  return nil
end

-- The track's icon path as REAPER stores it, or nil.
function IC.path_of(track)
  if not track then return nil end
  local ok, p = reaper.GetSetMediaTrackInfo_String(track, "P_ICON", "", false)
  if ok and p and p ~= "" then return p end
  return nil
end

-- The loaded image for a stored P_ICON value, or nil.
local function image(ctx, raw)
  local path = IC.resolve(raw)
  if not path then return nil end
  local img = cache[path]
  if img == nil then
    local ok, res = pcall(ImGui.CreateImage, path)
    if ok and res then
      -- Attached, so it survives frames where no track happens to use it.
      pcall(ImGui.Attach, ctx, res)
      img = res
    else
      img = false
    end
    cache[path] = img
  end
  return img or nil
end

-- Draws the icon for a stored P_ICON value, fitted (aspect kept) and
-- centred in the box x, y, w, h. Returns true when something was drawn.
function IC.draw(ctx, dl, raw, x, y, w, h)
  local img = raw and image(ctx, raw)
  if not img then return false end
  local iw, ih = ImGui.Image_GetSize(img)
  if not iw or iw <= 0 or not ih or ih <= 0 then return false end
  local s = math.min(w / iw, h / ih)
  local dw, dh = iw * s, ih * s
  local x0, y0 = x + (w - dw) * 0.5, y + (h - dh) * 0.5
  ImGui.DrawList_AddImage(dl, img, x0, y0, x0 + dw, y0 + dh)
  return true
end

return IC
