-- @noindex
-- Not a package of its own: installed by TS_ChannelView.lua's @provides.
--[[
  TS_CV_Containers.lua -- a container's own panel: the parameters it
  exposes (REAPER's container parameter mapping) as knobs.

  A container's parameters are the ones mapped from the plugins inside it
  (container_map), then its own Bypass, Wet and Delta. The mapped ones are
  saved with the project and go with the container into an FX chain or a
  track template, so a container with knobs on it travels as a device.

  Not every mapped parameter is meant to be seen. A link from a macro or
  modulator to a plugin inside a container is made on the outermost
  container's parameter (TS_CV_Mod), so the parameters on the way carry
  the link. Those are left off the panel unless they were put there; any
  other mapping (one made here, or in REAPER's container window) is shown
  unless it was taken off. Both choices are kept per container, by the
  slot inside it and the parameter, in the project:
  cpanel:{container guid}#slot:param = "S" (shown) or "H" (hidden).

  A container can also be folded to its panel (cfold:{guid}): the plugins
  inside drop out of the row and the panel stands for them.
--]]

local CT = {}
local NS = "TS_ChannelView"

local function get(track, addr, k)
  local pok, ok, v = pcall(reaper.TrackFX_GetNamedConfigParm, track, addr, k)
  if pok and ok and v and v ~= "" then return v end
  return nil
end
local function getn(track, addr, k) return tonumber(get(track, addr, k) or "") end

local function key_of(cguid, slot, param) return ("cpanel:%s#%d:%d"):format(cguid, slot, param) end
local function mark_of(cguid, slot, param)
  local _, v = reaper.GetProjExtState(0, NS, key_of(cguid, slot, param))
  return (v == "S" or v == "H") and v or nil
end
local function set_mark(cguid, slot, param, v)
  reaper.SetProjExtState(0, NS, key_of(cguid, slot, param), v or "")
end

-- Container parameter `i`'s source: the slot inside and its parameter.
function CT.source(track, caddr, i)
  local slot = getn(track, caddr, ("param.%d.container_map.fx_index"):format(i))
  local p = getn(track, caddr, ("param.%d.container_map.fx_parm"):format(i))
  if slot and p then return slot, p end
  return nil
end

-- How many mapped parameters a container has (its own three aside).
function CT.mapped(track, caddr)
  local n = reaper.TrackFX_GetNumParams(track, caddr) or 0
  local m = 0
  for i = 0, n - 1 do
    if CT.source(track, caddr, i) then m = m + 1 end
  end
  return m
end

-- Does parameter `i` of the container at `cpath` carry something else: a
-- link on it, or a mapping up into the container above?
local function carries(track, caddr, cpath, i)
  if get(track, caddr, ("param.%d.plink.active"):format(i)) == "1" then return true end
  if #cpath < 2 then return false end
  local parent = {}
  for d = 1, #cpath - 1 do parent[d] = cpath[d] end
  local paddr = require("TS_CV_FXTree").addr_of(track, parent)
  if not paddr then return false end
  local n = reaper.TrackFX_GetNumParams(track, paddr) or 0
  local slot = cpath[#cpath]
  for j = 0, n - 1 do
    local s, p = CT.source(track, paddr, j)
    if s == slot and p == i then return true end
  end
  return false
end

-- (for the menu: taking it off only hides it)
function CT.carries(track, caddr, cpath, i) return carries(track, caddr, cpath, i) end

-- The container's parameters on its panel, in order.
function CT.visible(track, caddr, cguid, cpath)
  local out = {}
  local n = reaper.TrackFX_GetNumParams(track, caddr) or 0
  for i = 0, n - 1 do
    local slot, p = CT.source(track, caddr, i)
    if slot then
      local m = mark_of(cguid, slot, p)
      if m == "S" or (m == nil and not carries(track, caddr, cpath, i)) then out[#out + 1] = i end
    end
  end
  return out
end

-- A signature of what's on the panel, for noticing when it changes.
function CT.sig(track, caddr, cguid, cpath)
  return table.concat(CT.visible(track, caddr, cguid, cpath), ",")
end

-- What the last rescan found on each container's panel: guid -> list.
CT.shown = {}

-- The panel's layout when none was saved: a knob (or switch) per shown
-- parameter. (Its key is "Container {guid}".)
function CT.default_layout(track, caddr, cguid)
  local M = require("TS_CV_Mappings")
  local U = require("TS_CV_Util")
  local controls = {}
  for _, p in ipairs(CT.shown[cguid] or CT.visible(track, caddr, cguid, {})) do
    local _, nm = reaper.TrackFX_GetParamName(track, caddr, p, "")
    controls[#controls + 1] = M.apply_default_look({
      param = p, type = U.guess_control_type(track, caddr, p),
      bipolar = U.guess_bipolar(nm, track, caddr, p), label = "",
    })
  end
  return { controls = controls, aliases = {} }
end

-- Puts parameter `param` of the plugin at `path` on the container `up`
-- levels above it (1: the one it's in), mapping it up through each
-- container on the way. Returns the container's parameter, or nil.
function CT.put(track, path, param, up)
  local T = require("TS_CV_FXTree")
  local MD = require("TS_CV_Mod")
  local p = param
  local cpath, slot
  for k = 1, up do
    local depth = #path - k + 1
    if depth < 2 then return nil end
    cpath = {}
    for d = 1, depth - 1 do cpath[d] = path[d] end
    slot = path[depth]
    local caddr = T.addr_of(track, cpath)
    if not caddr then return nil end
    p = MD.expose(track, caddr, slot, p)
    if not p or p < 0 then return nil end
  end
  local caddr = T.addr_of(track, cpath)
  local cguid = reaper.TrackFX_GetFXGUID(track, caddr) or ""
  local s, sp = CT.source(track, caddr, p)
  if s then set_mark(cguid, s, sp, "S") end
  return p, cguid
end

-- Is parameter `param` of the plugin at `path` on the panel of the
-- container `up` levels above? (Found, not made.)
function CT.is_on(track, path, param, up)
  local T = require("TS_CV_FXTree")
  local MD = require("TS_CV_Mod")
  local p = param
  local cpath
  for k = 1, up do
    local depth = #path - k + 1
    if depth < 2 then return false end
    cpath = {}
    for d = 1, depth - 1 do cpath[d] = path[d] end
    local caddr = T.addr_of(track, cpath)
    if not caddr then return false end
    p = MD.expose(track, caddr, path[depth], p, true)
    if not p then return false end
  end
  local caddr = T.addr_of(track, cpath)
  local cguid = reaper.TrackFX_GetFXGUID(track, caddr) or ""
  for _, v in ipairs(CT.visible(track, caddr, cguid, cpath)) do
    if v == p then return true end
  end
  return false
end

-- Takes container parameter `i` off its panel: the mapping goes when
-- nothing else uses it, else it's only hidden.
function CT.take_off(track, caddr, cguid, cpath, i)
  local slot, p = CT.source(track, caddr, i)
  if not slot then return end
  if not carries(track, caddr, cpath, i) then
    local n0 = reaper.TrackFX_GetNumParams(track, caddr)
    -- REAPER removes a mapping when this value is READ, not set
    pcall(reaper.TrackFX_GetNamedConfigParm, track, caddr, ("param.%d.container_map.delete"):format(i))
    if reaper.TrackFX_GetNumParams(track, caddr) < n0 then
      set_mark(cguid, slot, p, nil)
      return "deleted"
    end
  end
  set_mark(cguid, slot, p, "H")
  return "hidden"
end

-- A container panel's saved layout after its parameter `i` went: the
-- controls on it gone, the ones after it one down when it was deleted
-- (REAPER renumbers the container's parameters).
function CT.fix_layout(cguid, i, deleted)
  local M = require("TS_CV_Mappings")
  local key = "Container " .. cguid
  local l = M.get(key)
  if not l then return end
  l = M.copy(l)
  local keep = {}
  for _, c in ipairs(l.controls or {}) do
    if c.param ~= i then
      if deleted and c.param and c.param > i then c.param = c.param - 1 end
      if deleted and c.param2 and c.param2 > i then c.param2 = c.param2 - 1 end
      keep[#keep + 1] = c
    end
  end
  for k, v in pairs(l.controls or {}) do if type(k) ~= "number" then keep[k] = v end end
  l.controls = keep
  M.set(key, l); M.save()
end

-- Folded to its panel?
function CT.folded(cguid)
  local _, v = reaper.GetProjExtState(0, NS, "cfold:" .. cguid)
  return v == "1"
end
function CT.set_folded(cguid, on)
  reaper.SetProjExtState(0, NS, "cfold:" .. cguid, on and "1" or "")
end

-- Which plugin parameters are on a container's panel, for the corner the
-- plugin's own panel shows on them: fx guid .. ":" .. param -> true. Set
-- by the window after a rescan (CT.note).
CT.on = {}
function CT.note(track, list)
  CT.on, CT.shown = {}, {}
  local T = require("TS_CV_FXTree")
  -- a container's parameter as the plugin parameter it is underneath (a
  -- control put on an outer container passes through the inner one)
  local alias = {}
  for _, e in ipairs(list or {}) do
    if e.container_panel and e.visible then
      CT.shown[e.guid] = e.visible
      for _, i in ipairs(e.visible) do
        local slot, p = CT.source(track, e.addr, i)
        if slot then
          -- on the panel once, it stays there (a link made on it later
          -- doesn't take it off)
          if not mark_of(e.guid, slot, p) then set_mark(e.guid, slot, p, "S") end
          local path = {}
          for d, v in ipairs(e.path_t) do path[d] = v end
          path[#path + 1] = slot
          local a = T.addr_of(track, path)
          for _ = 1, 8 do
            local s2, p2 = a and CT.source(track, a, p)
            if not s2 then break end
            path[#path + 1] = s2
            a, p = T.addr_of(track, path), p2
          end
          local g = a and reaper.TrackFX_GetFXGUID(track, a)
          if g then
            CT.on[g .. ":" .. p] = true
            alias[e.guid .. ":" .. i] = g .. ":" .. p
          end
        end
      end
    end
  end
  -- macro and modulator links show on the container's knob as on the
  -- plugin's (TS_CV_Mod MD.link_of)
  require("TS_CV_Mod").aliases = alias
end

return CT
