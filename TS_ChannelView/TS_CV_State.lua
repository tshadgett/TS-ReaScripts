-- @noindex
-- Not a package of its own: installed by TS_ChannelView.lua's @provides.
--[[
  TS_CV_State.lua -- per-FX-instance view state.

  Deliberately separate from TS_CV_Mappings. A layout says what a PLUGIN
  looks like and is shared by every instance of it; whether one particular
  instance on one particular track is collapsed is not that -- you'd
  collapse the reverb on the drum bus without wanting it collapsed on the
  vocal. So this is keyed by FX GUID and lives in the project file, which
  also means it survives a save/reopen.
--]]

local NS = "TS_ChannelView"

local S = {}

local cache = {}   -- guid -> bool, so a frame doesn't hit ProjExtState per panel

local gr_open = {} -- guid -> bool: the gain-reduction meter opened out into its trace

local pages = {}   -- guid -> page a paged panel is open at (S.page, below)

local variants = {} -- guid -> layout variant an instance shows ("" for the plugin's own)

-- Two of these are shared with another script: ChannelView's window and
-- the web bridge each keep their own copy of this module, and both lay
-- the probe taps (TS_CV_Taps) from whether a trace is open and which
-- layout an instance shows. A copy cached for good goes stale the moment
-- the other script changes it, and then the two lay the taps differently
-- in turn, every second -- the trace flashes. So those two are read from
-- the project again after SHARED_TTL; this script's own writes land at once.
local SHARED_TTL = 1.0
local gr_at, var_at = {}, {}   -- guid -> when it was last read

function S.clear_cache() cache = {}; gr_open = {}; pages = {}; variants = {}; gr_at = {}; var_at = {}; S.clear_virt() end

-- `default` is what an instance nobody has touched shows as -- false
-- (expanded) unless a caller says otherwise. Only a departure from the
-- default is written to the project.
function S.is_collapsed(guid, default)
  default = default or false
  if guid == nil or guid == "" then return false end
  local v = cache[guid]
  if v ~= nil then return v end
  local _, str = reaper.GetProjExtState(0, NS, "collapsed:" .. guid)
  if str == "1" then v = true
  elseif str == "0" then v = false
  else v = default end
  cache[guid] = v
  return v
end

function S.set_collapsed(guid, on, default)
  default = default or false
  if guid == nil or guid == "" then return end
  on = on and true or false
  cache[guid] = on
  local val = (on == default) and "" or (on and "1" or "0")
  reaper.SetProjExtState(0, NS, "collapsed:" .. guid, val)
end

-- Whether this instance has a collapsed state of its own in the project
-- (one written by set_collapsed), rather than just showing the default.
function S.has_collapsed(guid)
  if guid == nil or guid == "" then return false end
  local _, str = reaper.GetProjExtState(0, NS, "collapsed:" .. guid)
  return str == "1" or str == "0"
end

-- The way you last left a PLUGIN (by its layout key), for the next
-- instance of it that's inserted: true collapsed, false expanded, nil
-- never touched. Kept for every project, like the layouts.
function S.last_fold(key)
  local v = reaper.GetExtState(NS, "fold:" .. tostring(key))
  if v == "1" then return true elseif v == "0" then return false end
  return nil
end

function S.remember_fold(key, on)
  if not key or key == "" then return end
  reaper.SetExtState(NS, "fold:" .. key, on and "1" or "0", true)
end

function S.toggle_collapsed(guid, default)
  default = default or false
  S.set_collapsed(guid, not S.is_collapsed(guid, default), default)
end

-- Whether this instance's gain-reduction meter is opened out into its
-- trace (TS_CV_Panel). Per instance, like collapsed: you want to watch the
-- vocal's compressor, not every copy of that compressor in the project.
function S.is_gr_open(guid)
  if guid == nil or guid == "" then return false end
  local v = gr_open[guid]
  local now = reaper.time_precise()
  if v ~= nil and now - (gr_at[guid] or 0) < SHARED_TTL then return v end
  local _, str = reaper.GetProjExtState(0, NS, "grview:" .. guid)
  v = (str == "1")
  gr_open[guid], gr_at[guid] = v, now
  return v
end

function S.set_gr_open(guid, on)
  if guid == nil or guid == "" then return end
  on = on and true or false
  gr_open[guid], gr_at[guid] = on, reaper.time_precise()
  reaper.SetProjExtState(0, NS, "grview:" .. guid, on and "1" or "")
end

function S.toggle_gr_open(guid)
  S.set_gr_open(guid, not S.is_gr_open(guid))
end

-- The page a paged panel is open at (TS_CV_Panel's page breaks), per
-- instance, saved with the project. 1 when never set.
function S.page(guid)
  if guid == nil or guid == "" then return 1 end
  local v = pages[guid]
  if v then return v end
  local _, str = reaper.GetProjExtState(0, NS, "page:" .. guid)
  v = math.max(1, math.floor(tonumber(str) or 1))
  pages[guid] = v
  return v
end
function S.set_page(guid, n)
  if guid == nil or guid == "" then return end
  n = math.max(1, math.floor(n or 1))
  pages[guid] = n
  reaper.SetProjExtState(0, NS, "page:" .. guid, (n > 1) and tostring(n) or "")
end

-- The layout variant an instance shows (TS_CV_Mappings, "<plugin> ::
-- <name>"), per instance, saved with the project. nil for the plugin's
-- own layout.
function S.variant(guid)
  if guid == nil or guid == "" then return nil end
  local v = variants[guid]
  local now = reaper.time_precise()
  if v == nil or now - (var_at[guid] or 0) >= SHARED_TTL then
    local _, str = reaper.GetProjExtState(0, NS, "variant:" .. guid)
    v = str or ""
    variants[guid], var_at[guid] = v, now
  end
  return v ~= "" and v or nil
end
function S.set_variant(guid, name)
  if guid == nil or guid == "" then return end
  variants[guid], var_at[guid] = name or "", reaper.time_precise()
  reaper.SetProjExtState(0, NS, "variant:" .. guid, name or "")
end

-- A virtual control's setting on an instance (TS_CV_Mappings Virt<n>),
-- 0..1, by its name; nil when it's never been set (it's at its start).
-- Shared with the web bridge like the variant, so re-read after VIRT_TTL.
local vvals, vv_at = {}, {}
local VIRT_TTL = 0.25
function S.clear_virt() vvals, vv_at = {}, {} end
function S.vget(guid, name)
  if guid == nil or guid == "" or not name then return nil end
  local k = guid .. ":" .. name
  local now = reaper.time_precise()
  local v = vvals[k]
  if v == nil or now - (vv_at[k] or 0) >= VIRT_TTL then
    local _, str = reaper.GetProjExtState(0, NS, "virt:" .. k)
    v = tonumber(str or "") or false
    vvals[k], vv_at[k] = v, now
  end
  return v or nil
end
function S.vset(guid, name, v)
  if guid == nil or guid == "" or not name then return end
  local k = guid .. ":" .. name
  v = math.max(0, math.min(1, v or 0))
  vvals[k], vv_at[k] = v, reaper.time_precise()
  reaper.SetProjExtState(0, NS, "virt:" .. k, ("%g"):format(math.floor(v * 10000 + 0.5) / 10000))
end
-- Its setting, or where it starts (the control's own in `controls`, else
-- the plugin's first layout with one of that name)
function S.vvalue(guid, name, base, controls)
  local v = S.vget(guid, name)
  if v ~= nil then return v end
  local M = require("TS_CV_Mappings")
  return (M.vstart(base, name, controls))
end

-- The rule (its number) that put up the layout an instance shows, or nil
-- (TS_CV_Mappings Switch<n>). Each script works it out for itself.
local rule_on = {}
function S.switch_rule(guid) return guid and rule_on[guid] or nil end
-- a range rule that's on stays on until its value is this far back
S.SWITCH_SLACK = 0.02

-- The library key an instance's layout lives under: its variant's when
-- it has one the library still holds, else the plugin's own.
-- An instance never set to one follows the plugin's default layout
-- (TS_CV_Mappings M.default_variant); S.OWN pins it to the plugin's own.
-- Given its track and address, the plugin's layout switching comes first:
-- the first of its rules its values match puts up that rule's layout.
S.OWN = "*"
function S.layout_key(fx_name, guid, track, addr)
  local U = require("TS_CV_Util")
  local M = require("TS_CV_Mappings")
  local base = U.plugin_key(fx_name)
  if track and addr and guid then
    local rules = M.switch_rules and M.switch_rules(base)
    local was = rule_on[guid]
    rule_on[guid] = nil
    for i, r in ipairs(rules or {}) do
      local v
      if r.vname then v = S.vvalue(guid, r.vname, base, nil)
      else v = reaper.TrackFX_GetParamNormalized(track, addr, r.param) end
      if v and M.show_match(v, r, (was == i) and S.SWITCH_SLACK or 0) then
        local k = M.variant_key(base, r.layout)
        if k == base or M.has(k) then rule_on[guid] = i; return k end
      end
    end
  end
  local v = S.variant(guid)
  if v == S.OWN then return base end
  v = v or (M.default_variant and M.default_variant(base))
  if v then
    local k = M.variant_key(base, v)
    if M.has(k) then return k end
  end
  return base
end
-- The layout the instance would show with no rule in charge (its own pick)
function S.chosen_key(fx_name, guid) return S.layout_key(fx_name, guid, nil, nil) end

return S
