--[[
  TS_CV_FXTree.lua -- container-aware enumeration of a track's FX chain.

  Ported from RackLib.lua -- my own, shared by Plugin Rack.lua and
  Docked Plugin Display.lua, neither of them released -- so ChannelView
  stands on its own and the projects can evolve separately. No third-party
  code is involved here.

  The container-addressing math is a community reverse-engineering of
  REAPER 7's FX Containers, not documented API, so every call into it is
  wrapped defensively: a bad address is skipped, not raised.
--]]

local T = {}

local CONTAINER_FLAG      = 0x2000000
local MAX_CONTAINER_DEPTH = 6

local function safe_container_count(track, addr)
  local pok, ok, cc = pcall(reaper.TrackFX_GetNamedConfigParm, track, addr, "container_count")
  if pok and ok then return tonumber(cc) end
  return nil
end

local function safe_fx_name(track, addr)
  local pok, ok, name = pcall(reaper.TrackFX_GetFXName, track, addr, "")
  if pok and ok then return name end
  return nil
end

local function safe_fx_guid(track, addr)
  local pok, guid = pcall(reaper.TrackFX_GetFXGUID, track, addr)
  if pok and guid and guid ~= "" then return guid end
  return ""
end

local function container_addr(track, path)
  if #path == 1 then return path[1] end
  local pok, top_count = pcall(reaper.TrackFX_GetCount, track)
  if not pok then return nil end
  local sc = top_count + 1
  local rv = CONTAINER_FLAG + path[1] + 1
  for i = 2, #path do
    local cc = safe_container_count(track, rv)
    if not cc then return nil end
    rv = rv + sc * (path[i] + 1)
    sc = sc * (cc + 1)
  end
  return rv
end

local function container_probe_addr(track, path)
  if #path == 1 then return CONTAINER_FLAG + path[1] + 1 end
  return container_addr(track, path)
end

local function walk_level(track, path, count, depth, out)
  if depth > MAX_CONTAINER_DEPTH then return end
  for j = 0, count - 1 do
    local this = {}
    for _, v in ipairs(path) do this[#this + 1] = v end
    this[#this + 1] = j

    local addr = container_addr(track, this)
    if addr then
      local probe = container_probe_addr(track, this)
      local cc = probe and safe_container_count(track, probe)
      if cc and cc > 0 then
        walk_level(track, this, cc, depth + 1, out)
      else
        out[#out + 1] = {
          addr         = addr,
          name         = safe_fx_name(track, addr) or ("FX " .. tostring(addr)),
          path         = table.concat(this, "."),
          depth        = #this - 1,
          guid         = safe_fx_guid(track, addr),
          top_index    = this[1],
          is_top_level = (#this == 1),
        }
      end
    end
  end
end

-- Ordered list of every LEAF FX on `track`, recursing into containers.
-- A container slot itself gets no entry -- only its contents -- except an
-- empty container, which stands in for itself.
function T.collect(track)
  local out = {}
  if not track then return out end
  local pok, count = pcall(reaper.TrackFX_GetCount, track)
  if not pok then return out end
  walk_level(track, {}, count, 0, out)
  return out
end

-- A cheap fingerprint of a chain's shape, for deciding whether a rescan
-- actually changed anything worth rebuilding panels for.
function T.hash(list)
  local parts = {}
  for i, e in ipairs(list) do
    parts[i] = e.guid ~= "" and e.guid or (e.path .. ":" .. e.name)
  end
  return table.concat(parts, "|")
end

-- ---------------------------------------------------------------------
-- per-FX actions
-- ---------------------------------------------------------------------

function T.is_floating(track, addr)
  local pok, hwnd = pcall(reaper.TrackFX_GetFloatingWindow, track, addr)
  return pok and hwnd ~= nil
end

function T.toggle_float(track, addr)
  if T.is_floating(track, addr) then
    reaper.TrackFX_Show(track, addr, 2)   -- hide floating window
  else
    reaper.TrackFX_Show(track, addr, 3)   -- show floating window
  end
end

function T.get_enabled(track, addr)
  local pok, on = pcall(reaper.TrackFX_GetEnabled, track, addr)
  if pok then return on end
  return true
end

function T.set_enabled(track, addr, on)
  pcall(reaper.TrackFX_SetEnabled, track, addr, on)
end

-- The GUID of whatever currently sits at `addr`. An FX address is a
-- POSITION, so it stops meaning the same plugin the moment anything is
-- moved or deleted -- in this window or in REAPER's own FX chain. This is
-- how a cached chain is checked against reality before it is used.
function T.guid_at(track, addr)
  local pok, guid = pcall(reaper.TrackFX_GetFXGUID, track, addr)
  if pok and guid then return guid end
  return nil
end

-- ---------------------------------------------------------------------
-- gain reduction
-- ---------------------------------------------------------------------

-- REAPER asks the plugin for the gain reduction it has already computed,
-- so this costs one call and touches no audio. Plugins that don't report
-- it simply don't answer -- there is no level equivalent in the API, which
-- is why this module meters gain reduction and nothing else.
-- Returns a POSITIVE number of dB of reduction, or nil.
function T.gain_reduction(track, addr)
  -- A BYPASSED plugin keeps reporting whatever it last measured -- it has
  -- stopped processing, not stopped answering -- so the meter sat frozen
  -- at the reduction it was doing when you switched it off, which is a
  -- reading that is not true of anything. Bypassed means no reduction.
  if not T.get_enabled(track, addr) then return 0 end

  local pok, ok, str = pcall(reaper.TrackFX_GetNamedConfigParm,
                             track, addr, "GainReduction_dB")
  if not pok or not ok then return nil end
  local v = tonumber(str)
  if not v then return nil end
  return math.abs(v)
end

-- Whether this plugin reports GR at all. Static for a given plugin, so
-- it's worth caching rather than asking every frame.
local gr_cache = {}
function T.clear_gr_cache() gr_cache = {} end

function T.reports_gr(track, addr, guid)
  local key = (guid ~= nil and guid ~= "") and guid or tostring(addr)
  local v = gr_cache[key]
  if v ~= nil then return v end
  v = T.gain_reduction(track, addr) ~= nil
  gr_cache[key] = v
  return v
end

return T
