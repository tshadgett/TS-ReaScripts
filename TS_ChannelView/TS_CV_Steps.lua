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

function S.init(script_dir)
  dir = script_dir
  data, order = U.read_ini(dir .. FILE)
  dirty = false
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
  dirty = true
end

function S.forget(key, param)
  if data[key] then
    data[key]["P" .. param] = nil
    dirty = true
  end
end

function S.save()
  if not dirty or not dir then return end
  local ok = U.write_ini(dir .. FILE, data, order,
    "; ChannelView -- cached choices for stepped parameters.\n" ..
    "; Derived data, safe to delete; it is rebuilt by scanning.\n" ..
    "; P<param>=<label>|<label>|...")
  if ok then dirty = false end
  return ok
end

return S
