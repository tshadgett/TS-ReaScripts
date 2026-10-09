-- @noindex
-- Not a package of its own: installed by TS_ChannelView.lua's @provides.
--[[
  TS_CV_FXTree.lua -- container-aware enumeration of a track's FX chain.

  Ported from an internal, unreleased FX-tree library shared with other
  projects, so ChannelView stands on its own and can evolve independently
  of them. No third-party code is involved here.

  Containers are addressed the way REAPER 7's API documents it: an FX
  inside a container is 0x2000000 + (its container's slot + 1) + (the
  slot count of the level above + 1) * (its own slot + 1), nesting on
  from there. Every call is still wrapped defensively, so a bad address
  is skipped, not raised.

  Besides the flat list of panels, collect() also returns the chain's
  SHAPE: which panels sit in which container, and which run in parallel
  with the one before (REAPER 7's "Run selected FX in parallel with
  previous FX"). T.groups turns that into the brackets drawn above the
  panel row.
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

-- REAPER's "parallel" setting for one FX: 0 runs after the one before it,
-- 1 alongside it, 2 alongside it with the MIDI merged as well.
local function parallel_of(track, addr)
  local v = tonumber(safe_named(track, addr, "parallel") or "")
  if v == 1 or v == 2 then return v end
  return 0
end
T.parallel_of = parallel_of

local function copy_path(path, extra)
  local out = {}
  for i, v in ipairs(path) do out[i] = v end
  if extra ~= nil then out[#out + 1] = extra end
  return out
end

-- One level of the chain. Leaves go into `out` (the panels, in order);
-- every slot, leaf or container, becomes a node in `nodes`, so the shape
-- of the chain -- containers and parallel runs -- is kept alongside the
-- flat list. `ancestors` is the containers above this level, outermost
-- first.
local function walk_level(track, path, count, depth, out, nodes, ancestors)
  if depth > MAX_CONTAINER_DEPTH then return end
  for j = 0, count - 1 do
    local this = copy_path(path, j)
    local addr = container_addr(track, this)
    if addr then
      local probe = container_probe_addr(track, this)
      local cc = probe and safe_container_count(track, probe)
      local name, alias = names_of(track, addr)
      local node = {
        path      = this,
        addr      = addr,
        index     = j,              -- slot within its own level
        count     = count,          -- how many slots that level has
        parallel  = parallel_of(track, addr),
        guid      = safe_fx_guid(track, addr),
        name      = name or ("FX " .. tostring(addr)),
        alias     = alias,
        depth     = #this - 1,
        first     = #out + 1,
      }
      if cc and cc > 0 then
        node.kind, node.children = "container", {}
        local inner = copy_path(ancestors, node)
        walk_level(track, this, cc, depth + 1, out, node.children, inner)
      else
        -- An empty container has no panels inside it, so it stands in for
        -- itself: a panel of its own, still a container to the brackets.
        node.kind = (cc == 0) and "container" or "fx"
        if node.kind == "container" then node.children = {} end
        out[#out + 1] = {
          addr         = addr,
          name         = node.name,
          alias        = alias,      -- REAPER's own instance name, if renamed
          path         = table.concat(this, "."),
          path_t       = this,
          parent_path  = path,       -- the level it sits in ({} = the chain itself)
          index        = j,          -- its slot in that level
          siblings     = count,
          depth        = #this - 1,
          guid         = node.guid,
          top_index    = this[1],
          is_top_level = (#this == 1),
          parallel     = node.parallel,
          is_container = node.kind == "container",
          ancestors    = ancestors,  -- container nodes above it, outermost first
        }
      end
      node.last = #out
      nodes[#nodes + 1] = node
    end
  end
end

-- Ordered list of every LEAF FX on `track`, recursing into containers.
-- A container slot itself gets no entry -- only its contents -- except an
-- empty container, which stands in for itself. The list's `tree` field is
-- the top level's nodes (see walk_level), for T.groups.
function T.collect(track)
  local out = { tree = {} }
  if not track then return out end
  local pok, count = pcall(reaper.TrackFX_GetCount, track)
  if not pok then return out end
  walk_level(track, {}, count, 0, out, out.tree, {})
  return out
end

-- ---------------------------------------------------------------------
-- brackets: containers and parallel runs, for the strip above the panels
-- ---------------------------------------------------------------------

-- How many bracket rows the strip draws at most. Deeper nesting than this
-- folds into the top row; the tooltips still name every level.
T.MAX_BRACKET_ROWS = 3

-- The parallel runs in one level: consecutive nodes where every one after
-- the first is flagged parallel. A flag on a level's first slot means
-- nothing (there's nothing before it to run beside) and is ignored.
local function runs_of(nodes)
  local runs, i = {}, 1
  while i <= #nodes do
    local j = i
    while j < #nodes and nodes[j + 1].parallel ~= 0 do j = j + 1 end
    runs[#runs + 1] = { a = i, b = j }
    i = j + 1
  end
  return runs
end

-- Every bracket for a chain collected by T.collect, each
--   { kind = "container" | "parallel", first, last (panel indices),
--     row (0 = nearest the panels), node (a container's), members (a
--     parallel run's nodes), merge (any member merging MIDI) }
-- and how many rows they need (0 when the chain has neither). A bracket
-- sits one row above everything it contains.
function T.groups(list)
  local out = {}
  local cap = T.MAX_BRACKET_ROWS
  local level   -- forward
  local function height(node)
    if node.kind ~= "container" then return 0 end
    local h = 1 + level(node.children)
    out[#out + 1] = { kind = "container", first = node.first, last = node.last,
                      row = math.min(h, cap) - 1, node = node, h = h }
    return h
  end
  function level(nodes)
    local top = 0
    for _, r in ipairs(runs_of(nodes)) do
      local h = 0
      for k = r.a, r.b do h = math.max(h, height(nodes[k])) end
      if r.b > r.a then
        local members, merge = {}, false
        for k = r.a, r.b do
          members[#members + 1] = nodes[k]
          if k > r.a and nodes[k].parallel == 2 then merge = true end
        end
        h = h + 1
        out[#out + 1] = { kind = "parallel", first = nodes[r.a].first,
                          last = nodes[r.b].last, row = math.min(h, cap) - 1,
                          members = members, merge = merge, h = h }
      end
      top = math.max(top, h)
    end
    return top
  end
  local rows = level((list and list.tree) or {})
  -- a bracket over no panels (an empty level) has nothing to draw over
  local kept = {}
  for _, b in ipairs(out) do
    if b.last >= b.first then kept[#kept + 1] = b end
  end
  -- Rows count from the OUTSIDE in: the outermost brackets on row 0, at the
  -- top of the strip, each one inside another a row lower. So a bracket's
  -- line stays straight however deep the brackets under it go here and
  -- there, and a panel only drops as far as the brackets actually over
  -- it: the first plugin in a container sits higher than two in parallel
  -- beside it. `out` is built inside-out (a bracket after everything in
  -- it), so what encloses a bracket comes after it, over its whole span.
  for i, b in ipairs(kept) do
    local depth = 1
    for j = i + 1, #kept do
      local o = kept[j]
      if o.first <= b.first and b.last <= o.last then depth = depth + 1 end
    end
    b.row = math.min(depth, cap) - 1
  end
  return kept, math.min(rows, cap)
end

-- The container node a panel sits in (nil at the top level), and a
-- readable "A \u{25B8} B" for where it is.
function T.where(fx)
  local a = fx and fx.ancestors
  if not a or #a == 0 then return nil, nil end
  local names = {}
  for i, n in ipairs(a) do names[i] = n.alias or require("TS_CV_Util").fx_label(n) end
  return a[#a], table.concat(names, " \u{25B8} ")
end

-- A cheap fingerprint of a chain's shape, for deciding whether a rescan
-- actually changed anything worth rebuilding panels for.
function T.hash(list)
  local parts = {}
  for i, e in ipairs(list) do
    parts[i] = (e.guid ~= "" and e.guid or (e.path .. ":" .. e.name))
               .. "@" .. e.path .. "/" .. (e.parallel or 0)
  end
  -- containers and their own parallel setting, which no panel carries
  local function walk(nodes)
    for _, n in ipairs(nodes or {}) do
      if n.kind == "container" then
        parts[#parts + 1] = "C" .. n.guid .. "/" .. n.parallel .. "/" .. (n.alias or "")
        walk(n.children)
      end
    end
  end
  walk(list.tree)
  return table.concat(parts, "|")
end

-- ---------------------------------------------------------------------
-- editing the chain's shape: moves, containers, parallel
-- ---------------------------------------------------------------------
-- Every edit here is addressed by PATH (slot numbers from the top level
-- down, as collect() gives them) and turned into an address only at the
-- moment it's used, from the chain as it stands then. REAPER reads a
-- move's destination against the chain as it is BEFORE the move, and
-- puts the FX at that slot of the destination level -- within one level
-- that's its final slot, with the source already lifted out.

T.CONTAINER_FLAG = CONTAINER_FLAG

-- The address of the slot at `path`: a top-level slot is its index; one
-- inside a container is the 0x2000000 form. A path one past a level's
-- last slot addresses its end, which is where a move appends.
function T.addr_of(track, path)
  if #path == 0 then return nil end
  return container_addr(track, path)
end

local function same_path(a, b)
  if #a ~= #b then return false end
  for i = 1, #a do if a[i] ~= b[i] then return false end end
  return true
end

local function parent_of(path)
  local out = {}
  for i = 1, #path - 1 do out[i] = path[i] end
  return out, path[#path]
end
T.parent_of = parent_of

-- Whether `inner` is `outer` or somewhere inside it.
local function within(inner, outer)
  if #inner < #outer then return false end
  for i = 1, #outer do if inner[i] ~= outer[i] then return false end end
  return true
end

-- Where a move lands, without making it: the destination address and the
-- slot the FX ends up in, or nil when it would go nowhere (back where it
-- is) or somewhere it can't (a container into itself). `gap` counts the
-- insertion points of the destination level as it is now: 0 = before its
-- first slot, its count = after its last.
function T.plan_move(track, src_path, dest_parent, gap)
  if not src_path or #src_path == 0 or gap == nil or gap < 0 then return nil end
  if within(dest_parent, src_path) then return nil end
  local sp, si = parent_of(src_path)
  local final = gap
  if same_path(sp, dest_parent) then
    if gap == si or gap == si + 1 then return nil end
    if gap > si then final = gap - 1 end
  end
  local dest
  if #dest_parent == 0 then dest = final
  else dest = container_addr(track, copy_path(dest_parent, final)) end
  if not dest then return nil end
  return dest, final
end

-- Moves the FX (or container) at `src_path` to insertion point `gap` of
-- the level `dest_parent`. No undo block of its own: callers group a
-- whole edit into one. Returns the slot it ended up in, or nil.
function T.move(track, src_path, dest_parent, gap)
  local src = T.addr_of(track, src_path)
  local dest, final = T.plan_move(track, src_path, dest_parent, gap)
  if not (src and dest) then return nil end
  local ok = pcall(reaper.TrackFX_CopyToTrack, track, src, track, dest, true)
  if not ok then return nil end
  return final
end

-- Copies the FX (or container, and everything in it) at `path` into the
-- slot right after it, at the same level. No undo block of its own.
-- Returns the copy's slot, or nil.
function T.duplicate(track, path)
  local src = T.addr_of(track, path)
  if not src then return nil end
  local parent, i = parent_of(path)
  local dest
  if #parent == 0 then dest = i + 1
  else dest = container_addr(track, copy_path(parent, i + 1)) end
  if not dest then return nil end
  local ok = pcall(reaper.TrackFX_CopyToTrack, track, src, track, dest, false)
  if not ok then return nil end
  return i + 1
end

-- REAPER's "parallel" setting (see parallel_of): 0, 1 or 2.
function T.set_parallel(track, addr, v)
  pcall(reaper.TrackFX_SetNamedConfigParm, track, addr, "parallel", tostring(v or 0))
end

-- ---------------------------------------------------------------------
-- oversampling
-- ---------------------------------------------------------------------
-- REAPER's own oversampling, as its FX chain window sets it. The setting
-- is a CEILING, not a factor: 0 off, 1 "oversample up to 88.2k/96k",
-- 2 up to 176.4k/192k, 3 up to 352.8k/384k, 4 up to 705.6k/768k -- the
-- 44.1k family when REAPER runs at a multiple of 44.1k, else the 48k one.
-- So at 48k, 1 is 2x; at 96k, 1 does nothing and 2 is 2x.
--   * every plugin, and every container, has its own
--     ("instance_oversample_shift"; NEXT_FX_OVERSAMPLE in the chunk), and
--     a container's oversamples everything in it
--   * the track's chain has one for the whole chain
--     ("chain_oversample_shift", read and set through any plugin at the
--     top level; FX_OVERSAMPLE in the chunk). Asked of a plugin inside a
--     container it answers for the container's own inner chain, which
--     REAPER's container window sets -- ChannelView leaves that one alone
--     and offers the container's own setting instead.
--   * they don't stack: REAPER's menu says a plugin on an oversampled
--     chain runs at the higher of the two. Containers are taken the same
--     way: a plugin runs at the highest ceiling around it.
--   * a change takes effect when playback next starts.
-- Read every frame for every panel's foot, so cached briefly per address.
T.OS_CHOICES = { 0, 1, 2, 3, 4 }

local os_cache, os_at = {}, -10

local function os_read(track, addr, key)
  local now = reaper.time_precise()
  if now - os_at > 0.25 then os_cache, os_at = {}, now end
  local k = tostring(track) .. ":" .. tostring(addr) .. ":" .. key
  local v = os_cache[k]
  if v == nil then
    v = math.floor(tonumber(safe_named(track, addr, key) or "") or 0)
    os_cache[k] = v
  end
  return v
end

-- "96 kHz", "88.2 kHz"
function T.khz(hz)
  if not hz then return nil end
  local k = hz / 1000
  return (math.abs(k - math.floor(k + 0.5)) < 0.01) and ("%d kHz"):format(math.floor(k + 0.5))
         or ("%.1f kHz"):format(k)
end

-- The rate a setting reaches up to, at `rate` (nil for off).
function T.os_cap(n, rate)
  if (n or 0) <= 0 then return nil end
  local fam = (rate and rate % 11025 == 0) and 44100 or 48000
  return fam * (1 << n)
end

-- A setting as REAPER's menu names it: "Off", "Up to 192 kHz".
function T.os_label(n, rate)
  if (n or 0) <= 0 then return "Off" end
  return "Up to " .. T.khz(T.os_cap(n, rate))
end

-- How many times `rate` something running at `hz` is: 1, 2, 4...
function T.os_factor(hz, rate)
  if not (hz and rate and rate > 0) then return 1 end
  return math.max(1, math.floor(hz / rate + 0.5))
end

-- One plugin's (or container's) own setting.
function T.os_shift(track, addr)
  if not (track and addr) then return 0 end
  return os_read(track, addr, "instance_oversample_shift")
end

function T.set_os_shift(track, addr, n, what)
  reaper.Undo_BeginBlock()
  pcall(reaper.TrackFX_SetNamedConfigParm, track, addr, "instance_oversample_shift", tostring(n or 0))
  reaper.Undo_EndBlock(("ChannelView: oversample %s %s"):format(what or "plugin",
    (n or 0) > 0 and T.os_label(n, T.run_rate()):lower() or "off"), -1)
  os_at = -10
end

-- The whole chain's setting (0 when the chain is empty: nothing to ask).
function T.chain_os(track)
  if not track then return 0 end
  local pok, n = pcall(reaper.TrackFX_GetCount, track)
  if not pok or (n or 0) == 0 then return 0 end
  return os_read(track, 0, "chain_oversample_shift")
end

function T.set_chain_os(track, n)
  local pok, cnt = pcall(reaper.TrackFX_GetCount, track)
  if not pok or (cnt or 0) == 0 then return false end
  reaper.Undo_BeginBlock()
  pcall(reaper.TrackFX_SetNamedConfigParm, track, 0, "chain_oversample_shift", tostring(n or 0))
  reaper.Undo_EndBlock(("ChannelView: oversample the whole chain %s"):format(
    (n or 0) > 0 and T.os_label(n, T.run_rate()):lower() or "off"), -1)
  os_at = -10
  return true
end

-- The rate REAPER is running at: the project's own when it's set to use
-- one, else the audio device's. nil when neither says.
function T.run_rate()
  local use = reaper.GetSetProjectInfo(0, "PROJECT_SRATE_USE", 0, false)
  if use and use > 0 then
    local r = reaper.GetSetProjectInfo(0, "PROJECT_SRATE", 0, false)
    if r and r > 0 then return r end
  end
  local ok, s = reaper.GetAudioDeviceInfo("SRATE", "")
  local r = ok and tonumber(s)
  if r and r > 0 then return r end
  return nil
end

-- What oversamples something from outside it: the whole chain, and each
-- container it sits in, outermost first, as { { what, n, hz } ... } --
-- only those that actually raise the rate -- and the highest rate they
-- reach (the running rate when none does).
function T.os_outer(track, fx)
  local out, rate = {}, T.run_rate()
  local top = rate or 0
  local function add(what, n)
    local hz = T.os_cap(n, rate)
    if hz and hz > (rate or 0) then
      out[#out + 1] = { what = what, n = n, hz = hz }
      if hz > top then top = hz end
    end
  end
  add("the whole chain", T.chain_os(track))
  for _, a in ipairs((fx and fx.ancestors) or {}) do add("its container", T.os_shift(track, a.addr)) end
  return out, top
end

-- Everything a switch needs about one plugin or container (`fx` with its
-- `addr` and `ancestors`):
--   n      its own setting
--   lit    the factor it runs at, when its own setting is what raises it
--          (at least as high as anything around it); nil otherwise
--   faint  true when it isn't lit but runs oversampled anyway (something
--          around it), or its own setting does nothing at this rate
--   rate, outer, top   as T.run_rate and T.os_outer
function T.os_state(track, fx)
  local rate = T.run_rate()
  local n = T.os_shift(track, fx.addr)
  local outer, top = T.os_outer(track, fx)
  local own = T.os_cap(n, rate)
  local st = { n = n, rate = rate, outer = outer, top = top }
  if own and own > (rate or 0) and own >= top then
    st.lit = T.os_factor(own, rate)
  else
    st.faint = (#outer > 0) or n > 0
  end
  return st
end

-- The whole chain's switch: its setting, and the factor it runs at (nil
-- when off, or when the setting does nothing at this rate).
function T.chain_state(track)
  local rate = T.run_rate()
  local n = T.chain_os(track)
  local hz = T.os_cap(n, rate)
  return { n = n, rate = rate, lit = (hz and hz > (rate or 0)) and T.os_factor(hz, rate) or nil,
           faint = n > 0 and not (hz and hz > (rate or 0)) }
end

-- How many slots a container has (nil for something that isn't one).
function T.count_in(track, path)
  if #path == 0 then
    local pok, n = pcall(reaper.TrackFX_GetCount, track)
    return pok and n or nil
  end
  return safe_container_count(track, container_probe_addr(track, path))
end

-- A plugin added straight into a container, at insertion point `gap` of
-- the level `parent` ({} = the chain itself). REAPER only adds at the top
-- level, so it goes in at the end of the chain and is moved from there.
-- Returns true when it's in place.
function T.add_into(track, ident, parent, gap)
  if #parent == 0 then
    local idx = reaper.TrackFX_AddByName(track, ident, false, -1000 - gap)
    return idx ~= nil and idx >= 0
  end
  local idx = reaper.TrackFX_AddByName(track, ident, false, -1)
  if not idx or idx < 0 then return false end
  if T.move(track, { idx }, parent, gap) then return true end
  pcall(reaper.TrackFX_Delete, track, idx)     -- don't leave it stranded at the end
  return false
end

-- Puts the FX at `path` into a new container of its own, in its place.
-- The container takes over its parallel setting, so the chain still runs
-- the way it did. Returns true on success.
function T.wrap(track, path)
  local parent, si = parent_of(path)
  local src_par = parallel_of(track, T.addr_of(track, path))
  local idx = reaper.TrackFX_AddByName(track, "Container", false, -1)
  if not idx or idx < 0 then return false end
  -- the new container, from the end of the chain to the FX's slot...
  if not (idx == si and #parent == 0) then
    if not T.move(track, { idx }, parent, si) then
      pcall(reaper.TrackFX_Delete, track, idx)
      return false
    end
  end
  local cpath = copy_path(parent, si)
  local spath = copy_path(parent, si + 1)
  T.set_parallel(track, T.addr_of(track, cpath), src_par)
  T.set_parallel(track, T.addr_of(track, spath), 0)
  -- ...and the FX, now just after it, into it
  return T.move(track, spath, cpath, 0) ~= nil
end

-- Lifts everything out of the container at `path` into its place, in
-- order, and deletes the empty container. The first one out takes the
-- container's parallel setting. Returns true on success.
function T.unpack(track, path)
  local parent, ci = parent_of(path)
  local n = T.count_in(track, path) or 0
  local cpar = parallel_of(track, T.addr_of(track, path))
  for m = 0, n - 1 do
    local slot = T.move(track, copy_path(path, 0), parent, ci + 1 + m)
    if not slot then return false end
    if m == 0 then T.set_parallel(track, T.addr_of(track, copy_path(parent, slot)), cpar) end
  end
  local ok = pcall(reaper.TrackFX_Delete, track, T.addr_of(track, path))
  return ok
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

-- SIDECHAIN INTO A CONTAINER. A sidechain arrives on the track's 3/4 (the
-- Receives panel sends it there), and a plugin with sidechain inputs reads
-- 3/4 by default -- but a container passes only what its input pins carry,
-- two channels unless it's been widened, so a compressor in one never hears
-- its key. T.sidechain_gap lists the containers around a plugin that don't
-- pass 3/4 in (outermost first); T.pass_sidechain widens them: two more
-- input pins, each carrying its own channel, and room for them inside.
local function pin_has(track, addr, pin, ch)
  local pok, lo = pcall(reaper.TrackFX_GetPinMappings, track, addr, 0, pin)
  lo = pok and math.floor(lo or 0) or 0
  return (lo >> (ch - 1)) & 1 == 1
end

function T.has_sidechain_in(track, addr)
  local pok, _, nin = pcall(reaper.TrackFX_GetIOSize, track, addr)
  return pok and (nin or 0) >= 4
end

function T.sidechain_gap(track, fx)
  local out = {}
  if not (fx and fx.ancestors and #fx.ancestors > 0) then return out end
  if not T.has_sidechain_in(track, fx.addr) then return out end
  for _, a in ipairs(fx.ancestors) do
    local nin = tonumber(safe_named(track, a.addr, "container_nch_in") or "") or 2
    if nin < 4 or not (pin_has(track, a.addr, 2, 3) and pin_has(track, a.addr, 3, 4)) then
      out[#out + 1] = a
    end
  end
  return out
end

function T.pass_sidechain(track, fx)
  local gap = T.sidechain_gap(track, fx)
  if #gap == 0 then return false end
  reaper.Undo_BeginBlock()
  for _, a in ipairs(gap) do
    local nch = tonumber(safe_named(track, a.addr, "container_nch") or "") or 2
    if nch < 4 then pcall(reaper.TrackFX_SetNamedConfigParm, track, a.addr, "container_nch", "4") end
    local nin = tonumber(safe_named(track, a.addr, "container_nch_in") or "") or 2
    if nin < 4 then pcall(reaper.TrackFX_SetNamedConfigParm, track, a.addr, "container_nch_in", "4") end
    for pin = 2, 3 do
      local pok, lo, hi = pcall(reaper.TrackFX_GetPinMappings, track, a.addr, 0, pin)
      lo, hi = pok and math.floor(lo or 0) or 0, pok and math.floor(hi or 0) or 0
      -- a pin just created carries nothing else; one that existed keeps
      -- what it had, plus its own channel
      if nin <= pin then lo, hi = 0, 0 end
      pcall(reaper.TrackFX_SetPinMappings, track, a.addr, 0, pin, (lo | (1 << pin)) & 0xFFFFFFFF, hi)
    end
  end
  reaper.Undo_EndBlock("ChannelView: pass the sidechain into its container", -1)
  return true
end

-- Offline: unloaded (REAPER's "Set FX offline"), which frees its CPU and
-- memory -- not just bypassed. An offline plugin has no parameters to show.
function T.get_offline(track, addr)
  local pok, off = pcall(reaper.TrackFX_GetOffline, track, addr)
  return pok and off == true
end

function T.set_offline(track, addr, off, label)
  reaper.Undo_BeginBlock()
  pcall(reaper.TrackFX_SetOffline, track, addr, off and true or false)
  reaper.Undo_EndBlock(("ChannelView: %s %s"):format(off and "set offline" or "bring online",
    label or "plugin"), -1)
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
