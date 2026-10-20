-- @noindex
-- Not a package of its own: installed by TS_ChannelView.lua's @provides.
--[[
  TS_CV_Steps.lua -- a disk cache of stepped parameters' choices.

  Learning what a plugin calls position 3 means setting it and reading the
  formatted value back; there is no read-only enumeration in the API. That
  sweep is cheap but not free, and it briefly moves a real parameter, so it
  is worth doing exactly once per plugin rather than once per session.

  This is a CACHE, not settings: delete the file and nothing is lost but a
  few milliseconds. It is kept separate from the layout library for that
  reason -- one is your work, the other is derived data.

      [Pro-Q 3]
      P12=Off|12 dB/oct|24 dB/oct|48 dB/oct

  A stale entry (the plugin updated and renamed something) is corrected by
  "Rescan choices" on the control, which drops it and sweeps again.
--]]

local U = require("TS_CV_Util")

local S = {}

local FILE = "TS_ChannelView_Steps.ini"

local dir, data, order, dirty = nil, {}, {}, false
-- ChannelView and its Rack view each keep a copy: what this one changed
-- since it last read the file ([key][P<param>] = the line, or false when
-- forgotten), so a save merges into the other's rather than over it, and a
-- revision in ExtState that moves with every save (as TS_CV_Mappings).
local changed, my_rev = {}, nil
local REV_SECT, REV_KEY = "TS_ChannelView", "steps_rev"

local function note(key, pk, v)
  changed[key] = changed[key] or {}
  changed[key][pk] = v
  dirty = true
end

function S.init(script_dir)
  dir = script_dir
  data, order = U.read_ini(dir .. FILE)
  dirty = false
  changed = {}
  if reaper and reaper.GetExtState then my_rev = reaper.GetExtState(REV_SECT, REV_KEY) end
end

-- The other window saved: read the file again, this one's unsaved changes
-- on top. True when anything was read.
function S.sync()
  if not (reaper and reaper.GetExtState and dir) then return false end
  local rev = reaper.GetExtState(REV_SECT, REV_KEY)
  if rev == my_rev then return false end
  my_rev = rev
  local nd, no = U.read_ini(dir .. FILE)
  for key, ps in pairs(changed) do
    if not nd[key] then nd[key] = {}; no[#no + 1] = key end
    for pk, v in pairs(ps) do nd[key][pk] = v or nil end
  end
  data, order = nd, no
  return true
end

-- list -> { {norm=, text=}, ... }
local function encode(list)
  local out = {}
  for _, s in ipairs(list) do
    out[#out + 1] = (s.text:gsub("[|\r\n]", " "))
  end
  return table.concat(out, "|")
end

local function decode(str, step)
  local out = {}
  for text in str:gmatch("[^|]+") do
    out[#out + 1] = { norm = 0, text = text }
  end
  -- Positions are regenerated from the step size rather than stored: the
  -- labels are what cost a sweep, the maths is free and can't go stale.
  for i, s in ipairs(out) do
    s.norm = math.max(0, math.min(1, (i - 1) * step))
  end
  return out
end

function S.get(key, param, step)
  local sect = data[key]
  local raw = sect and sect["P" .. param]
  if not raw or raw == "" or not step or step <= 0 then return nil end
  local list = decode(raw, step)
  return (#list >= 2) and list or nil
end

function S.set(key, param, list)
  if not key or key == "" or not list or #list < 2 then return end
  if not data[key] then
    data[key] = {}
    order[#order + 1] = key
  end
  data[key]["P" .. param] = encode(list)
  note(key, "P" .. param, data[key]["P" .. param])
end

function S.forget(key, param)
  if data[key] then
    data[key]["P" .. param] = nil
    note(key, "P" .. param, false)
  end
end

function S.save()
  if not dirty or not dir then return end
  S.sync()
  local ok = U.write_ini(dir .. FILE, data, order,
    "; ChannelView -- cached choices for stepped parameters.\n" ..
    "; Derived data, safe to delete; it is rebuilt by scanning.\n" ..
    "; P<param>=<label>|<label>|...")
  if ok then
    dirty = false
    changed = {}
    if reaper and reaper.SetExtState then
      my_rev = tostring(reaper.time_precise and reaper.time_precise() or os.clock()) .. ":" .. tostring(math.random(1e6))
      reaper.SetExtState(REV_SECT, REV_KEY, my_rev, false)
    end
  end
  return ok
end

return S
