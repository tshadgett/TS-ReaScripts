-- @noindex
-- Not a package of its own: installed by TS_ChannelView.lua's @provides.
--[[
  TS_CV_Carry.lua -- a track's per-instance settings, carried with it.

  What ChannelView keeps for one plugin instance (TS_CV_State: folded,
  the layout variant, a virtual control's setting, the page, the trace)
  is kept in the project against the plugin's GUID. REAPER gives the
  plugins of a duplicated or pasted track, or of a track template, new
  GUIDs, so those settings would stay behind.

  So each track carries them too, in P_EXT:TS_CV_INST: a line for each
  setting, by the plugin's place in the chain (and its name). A plugin in
  that place, of that name, that isn't the one they were written for and
  has no settings of its own yet, takes them up (CR.adopt).

  A line: path TAB name TAB guid TAB key TAB rest-of-key TAB value, where
  the project key was <key>:<guid><rest-of-key> ("virt:{..}:Drive").
--]]

local CR = {}
local NS = "TS_ChannelView"
CR.KEY = "P_EXT:TS_CV_INST"

-- Every slot of the chain, containers too: { path ("2.1"), name, guid },
-- from T.collect's tree (`full`, or read now).
local function slots(track, full)
  full = full or require("TS_CV_FXTree").collect(track)
  local out = {}
  local function walk(nodes)
    for _, n in ipairs(nodes or {}) do
      if n.guid and n.guid ~= "" and n.path then
        out[#out + 1] = { path = table.concat(n.path, "."), name = n.name or "", guid = n.guid }
      end
      if n.children then walk(n.children) end
    end
  end
  walk(full.tree)
  return out
end
CR.slots = slots

-- The project's per-instance settings: guid -> { { key, rest, value }, ... }
local function by_guid()
  local out = {}
  if not reaper.EnumProjExtState then return out end
  local i = 0
  while true do
    local ok, k, v = reaper.EnumProjExtState(0, NS, i)
    if not ok or not k then break end
    if v and v ~= "" then
      local pre, g, rest = k:match("^([%w_]+):(%b{})(.*)$")
      if pre then
        local t = out[g]
        if not t then t = {}; out[g] = t end
        t[#t + 1] = { pre, rest, v }
      end
    end
    i = i + 1
  end
  return out
end

-- What the track carries now: its plugins' settings, as lines.
function CR.record(track, full)
  local have = by_guid()
  local lines = {}
  for _, s in ipairs(slots(track, full)) do
    for _, e in ipairs(have[s.guid] or {}) do
      local v = tostring(e[3]):gsub("[\t\n]", " ")
      lines[#lines + 1] = table.concat({ s.path, s.name, s.guid, e[1], e[2], v }, "\t")
    end
  end
  table.sort(lines)
  return table.concat(lines, "\n")
end

-- Writes it on the track, only when it's changed. True when written.
function CR.write(track, full)
  if not track then return false end
  local s = CR.record(track, full)
  local _, cur = reaper.GetSetMediaTrackInfo_String(track, CR.KEY, "", false)
  if (cur or "") == s then return false end
  reaper.GetSetMediaTrackInfo_String(track, CR.KEY, s, true)
  return true
end

-- Takes up what the track carries, for plugins that are new copies (not
-- the instance a line was written for) with no settings of their own.
-- True when anything was taken up; the caller clears TS_CV_State's cache.
function CR.adopt(track, full)
  if not track then return false end
  local _, rec = reaper.GetSetMediaTrackInfo_String(track, CR.KEY, "", false)
  if not rec or rec == "" then return false end
  local have = by_guid()
  local at = {}
  for _, s in ipairs(slots(track, full)) do at[s.path] = s end
  local took, done = {}, false
  for line in rec:gmatch("[^\n]+") do
    local path, name, old, pre, rest, val = line:match("^([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t(.*)$")
    local s = path and at[path]
    if s and s.name == name and s.guid ~= old and (took[s.guid] or not have[s.guid]) then
      took[s.guid] = true
      reaper.SetProjExtState(0, NS, pre .. ":" .. s.guid .. rest, val)
      done = true
    end
  end
  if done then CR.write(track, full) end
  return done
end

return CR
