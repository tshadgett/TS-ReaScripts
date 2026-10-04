-- @noindex
-- Not a package of its own: installed by TS_ChannelView.lua's @provides.
--[[
  TS_CV_FXTree.lua -- container-aware enumeration of a track's FX chain.

  Ported from an internal, unreleased FX-tree library shared with other
  projects, so ChannelView stands on its own and can evolve independently
  of them. No third-party code is involved here.

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

-- A named config value, or nil when it's empty or REAPER doesn't know it.
local function safe_named(track, addr, k)
  local pok, ok, v = pcall(reaper.TrackFX_GetNamedConfigParm, track, addr, k)
  if pok and ok and v and v ~= "" then return v end
  return nil
end

-- REAPER lets you rename an FX instance in its chain ("Rename FX
-- instance"), and TrackFX_GetFXName then answers with your name. The
-- layout is filed under the PLUGIN, so `name` stays the plugin's own
-- (renamed_name tells whether it was renamed, fx_name what it was) and
-- your name for the instance is kept beside it as `alias`.
local function names_of(track, addr)
  local alias = safe_named(track, addr, "renamed_name")
  local name = safe_fx_name(track, addr)
  if alias then name = safe_named(track, addr, "fx_name") or name end
  return name, alias
end
T.names_of = names_of

-- Renames an instance the way REAPER's FX chain does. The named config
-- value is the proper way; where it doesn't take (the read-back differs),
-- the name is written into the instance's header line in the track chunk
-- instead -- the field REAPER keeps it in: a VST's fourth, a CLAP's third,
-- a JS's second. Empty goes back to the plugin's own name.
local CHUNK_RENAME_FIELD = { VST = 4, CLAP = 3, JS = 2 }
local CHUNK_FX_TAG = { VST = true, CLAP = true, JS = true, AU = true, DX = true, LV2 = true,
                       VIDEO_EFFECT = true, CONTAINER = true }

-- the tokens of a chunk line, each kept as written (quotes and all)
local function chunk_tokens(s)
  local out, i = {}, 1
  while i <= #s do
    local c = s:sub(i, i)
    if c:match("%s") then i = i + 1
    elseif c == '"' or c == "'" or c == "`" then
      local j = s:find(c, i + 1, true) or #s
      out[#out + 1] = s:sub(i, j); i = j + 1
    else
      local j = s:find("%s", i) or (#s + 1)
      out[#out + 1] = s:sub(i, j - 1); i = j
    end
  end
  return out
end

local function chunk_quote(s)
  for _, q in ipairs({ '"', "'", "`" }) do
    if not s:find(q, 1, true) then return q .. s .. q end
  end
  return '"' .. s:gsub('"', "'") .. '"'
end

local function rename_in_chunk(track, guid, name)
  if not guid or guid == "" then return false end
  local ok, chunk = reaper.GetTrackStateChunk(track, "", false)
  if not ok then return false end
  local lines, header = {}, nil
  for l in (chunk .. "\n"):gmatch("(.-)\r?\n") do lines[#lines + 1] = l end
  local done = false
  for i, l in ipairs(lines) do
    local tag = l:match("^%s*<([%u_]+)%s")
    if tag and CHUNK_FX_TAG[tag] then header = { i = i, tag = tag }
    elseif l:match("^%s*FXID%s") then
      if header and l:find(guid, 1, true) then
        if not CHUNK_RENAME_FIELD[header.tag] then break end
        local h = lines[header.i]
        local ind, rest = h:match("^(%s*<%u+)%s+(.*)$")
        local tok = chunk_tokens(rest or "")
        local k = CHUNK_RENAME_FIELD[header.tag]
        if #tok >= k then
          tok[k] = chunk_quote(name)
          lines[header.i] = ind .. " " .. table.concat(tok, " ")
          done = true
        end
        break
      end
      header = nil
    end
  end
  if not done then return false end
  reaper.Undo_BeginBlock()
  local set = reaper.SetTrackStateChunk(track, table.concat(lines, "\n"), false)
  reaper.Undo_EndBlock("ChannelView: rename plugin", -1)
  return set
end
T.chunk_tokens = chunk_tokens   -- for TS_CV_Test.lua

function T.rename(track, addr, guid, name)
  name = name or ""
  reaper.TrackFX_SetNamedConfigParm(track, addr, "renamed_name", name)
  local ok, now = reaper.TrackFX_GetNamedConfigParm(track, addr, "renamed_name")
  if ok and (now or "") == name then return true end
  return rename_in_chunk(track, guid, name)
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
        local name, alias = names_of(track, addr)
        out[#out + 1] = {
          addr         = addr,
          name         = name or ("FX " .. tostring(addr)),
          alias        = alias,      -- REAPER's own instance name, if renamed
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

-- The whole track's FX chain can be bypassed at once (I_FXEN), independent
-- of any single plugin's own enabled state -- see TS_ChannelView.lua's
-- fx_bypass_button for the control that flips it, and TS_CV_Panel.lua's
-- draw_header for where a panel's own header reflects it.
function T.chain_bypassed(track)
  local pok, val = pcall(reaper.GetMediaTrackInfo_Value, track, "I_FXEN")
  if pok and val then return val < 0.5 end
  return false
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
  -- A bypassed plugin keeps reporting whatever it last measured -- it has
  -- stopped processing, not stopped answering -- so without this check the
  -- meter would show a frozen, stale reading rather than the true current
  -- state. Bypassed means no reduction.
  if not T.get_enabled(track, addr) then return 0 end

  local pok, ok, str = pcall(reaper.TrackFX_GetNamedConfigParm,
                             track, addr, "GainReduction_dB")
  local v = (pok and ok) and tonumber(str) or nil
  if v then return math.abs(v) end
  -- Not reported: measured instead, when a tap is on it (TS_CV_Taps).
  return require("TS_CV_Taps").reading(track, T.guid_at(track, addr))
end

-- Whether this plugin's reading is MEASURED by a probe tap rather than
-- reported by the plugin -- an estimate, and drawn as one.
function T.gr_estimated(track, addr, guid)
  guid = (guid ~= nil and guid ~= "") and guid or T.guid_at(track, addr)
  return require("TS_CV_Taps").is_tapped(track, guid)
end

-- Whether this plugin reports GR at all. Static for a given plugin, so
-- it's worth caching rather than asking every frame.
local gr_cache = {}
function T.clear_gr_cache() gr_cache = {} end

-- The plugin's own answer, cached; a tap is checked each time instead,
-- since it comes and goes as routing is laid and lifted.
function T.reports_gr_natively(track, addr, guid)
  local key = (guid ~= nil and guid ~= "") and guid or tostring(addr)
  local v = gr_cache[key]
  if v ~= nil then return v end
  local pok, ok = pcall(reaper.TrackFX_GetNamedConfigParm, track, addr, "GainReduction_dB")
  v = (pok and ok) and true or false
  gr_cache[key] = v
  return v
end

function T.reports_gr(track, addr, guid)
  if T.reports_gr_natively(track, addr, guid) then return true end
  return T.gr_estimated(track, addr, guid)
end

return T
