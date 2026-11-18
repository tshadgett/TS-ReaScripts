-- @noindex
-- Not a package of its own: installed by TS_DrumToolbox.lua's @provides.
--[[
  TS_DrumToolbox_core.lua -- everything DrumToolbox knows and does that
  isn't drawing: the hit map, profiles, finding a track's items, detection,
  and turning a hit's level into a velocity. The window, the ChannelView
  panel and the actions all use this; none of it touches ImGui.

  THE HIT MAP lives on the source takes as take markers, one per hit, so it
  moves, trims and splits with the audio. A marker shows only the hit's
  level ("-14.3") and is coloured by confidence (green, amber, red; white
  when locked). The rest of each hit is kept on the take, in
  P_EXT:TS_DT_hits, matched to its marker by position:

    c    confidence, 0-1: how sure detection is that this is a real hit
    dec  decay in ms: how long the hit takes to fall DEC_DROP dB
    po   phase offset in ms, written at generate time (per target)
    L    locked: re-detection never moves or removes it

  By hand: rename a marker to another number to overrule its level (it
  locks); move one and it is re-measured and locked; add a marker named
  "DT" for a missed hit, measured and locked the next time anything needs
  it. Numbers are read as levels only on takes that have a hit map, and
  other markers are left alone. (Markers from 0.1.x, "DT|db=...|c=...",
  are read and rewritten in this form.)

  A TRACK is a DrumToolbox source once it has a hit map: P_EXT:TS_DT_source
  on the track says so (ChannelView reads that to show its panel). Each
  take keeps the settings it was detected with in P_EXT:TS_DT_detect.

  DETECTION runs as a job (DT.detect_job) that does a slice of work per
  step, so a window can show progress and stay responsive; DT.detect runs
  one to the end. (Not a coroutine: REAPER's audio accessor reads silence
  from inside one.) Two passes per take:
    1. stream the take through the detection filter (band-pass, never
       heard) and a peak-hold envelope; a candidate is where the envelope
       is over the threshold, has risen rise_db within RISE_MS (a strike
       does; ring and shell beating don't), and the retrigger time has
       passed since the last;
    2. for each candidate, read a short window of the unfiltered audio:
       refine the onset, measure level and decay, and score confidence.

  Times: a take accessor reads in item time (0 = the item's start, after
  the start offset and playrate). Take markers are in source time.
]]

-- With Pro: this script runs with Pro's parts put back in (TS_DT_Edition)
do
  local own = select(2, ...) or debug.getinfo(1, "S").source:match("^@?(.*)$")   -- require gives the path
  package.path = (own:match("^(.*[\\/])") or "") .. "?.lua;" .. package.path
  local fn = require("TS_DT_Edition").self(own)
  if fn then return fn(...) end
end

local r = reaper
local DT = {}

DT.VERSION   = "1.0.0"
DT.ED = require("TS_DT_Edition")   -- Standard, or with Pro (DT.ED.PRO)
DT.NS        = "TS_DrumToolbox"
DT.PREFIX    = "DT"
DT.KEY_TRACK = "P_EXT:TS_DT_source"
DT.KEY_TAKE  = "P_EXT:TS_DT_detect"
DT.KEY_HITS  = "P_EXT:TS_DT_hits"      -- each hit's data, beside its marker
DT.KEY_BLEED = "P_EXT:TS_DT_bleed"     -- hits discounted as bleed (kept for the window)
DT.KEY_LINK  = "P_EXT:TS_DT_link"      -- on generated tracks (later)
DT.MATCH_TOL = 0.003    -- s (source time): a marker this close to a stored hit is that hit

-- The envelope's timing follows the detection filter's low edge, so a
-- low drum's ring reads as a smooth decay rather than ripple:
--   hold    ~1 cycle of the low edge   (5-30 ms)
--   release ~1.5 cycles                (10-60 ms)
--   rise    the window a strike's rise is measured over, ~1/3 cycle (5-12 ms)
DT.DEC_DROP  = 20.0     -- dB fall that counts as a hit's decay
DT.DEC_MAX   = 1.5      -- s, longest decay measured
DT.PRE       = 0.020    -- s of audio read before a candidate (onset search):
                        -- a quiet hit, or one landing in a ring, is found late
DT.ONSET_HP  = 1500     -- Hz: the strike's click, searched for the onset
DT.TILT_MS   = 30       -- the window a hit's tilt is measured over
DT.TILT_LO   = { 60, 300 }   -- Hz: the body band
DT.TILT_HI   = 2000          -- Hz: the crack band (and above)
DT.CLICK_DB  = 12       -- the click must stand this far over what came before
DT.BLOCK     = 65536    -- samples per channel read at a time in pass 1
DT.SCAN_SR   = 48000    -- pass 1 reads at most this rate (REAPER resamples); finding
                        -- candidates doesn't need more, measuring uses the full rate

-- confidence colours (take marker colours, native)
DT.COL = { hi = { 0x4c, 0xc9, 0xa6 }, mid = { 0xf0, 0xa9, 0x3b }, lo = { 0xff, 0x6b, 0x6b },
           lock = { 0xe4, 0xe6, 0xea } }
DT.C_HI, DT.C_MID = 0.80, 0.45

-- ---------------------------------------------------------------------
-- small helpers
-- ---------------------------------------------------------------------
local function clamp(x, a, b) if x < a then return a elseif x > b then return b end return x end
DT.clamp = clamp

local function db(x) if x <= 1e-12 then return -240 end return 20 * math.log(x, 10) end
local function undb(d) return 10 ^ (d / 20) end
DT.db, DT.undb = db, undb

local function round(x, n)
  local m = 10 ^ (n or 0)
  return math.floor(x * m + 0.5) / m
end

-- A plain Lua table as text, and back. Only numbers, strings, booleans
-- and tables; keys sorted so files diff cleanly.
local function ser(v, ind)
  ind = ind or ""
  local t = type(v)
  if t == "number" then
    if v == math.floor(v) and math.abs(v) < 2^53 then return string.format("%d", v) end
    return string.format("%.6g", v)
  elseif t == "string" then return string.format("%q", v)
  elseif t == "boolean" then return tostring(v)
  elseif t ~= "table" then return "nil" end
  local keys, n = {}, #v
  for k in pairs(v) do
    if not (type(k) == "number" and k >= 1 and k <= n and k == math.floor(k)) then keys[#keys + 1] = k end
  end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  local inner, out = ind .. "  ", {}
  for i = 1, n do out[#out + 1] = inner .. ser(v[i], inner) end
  for _, k in ipairs(keys) do
    local ks = (type(k) == "string" and k:match("^[%a_][%w_]*$")) and k or ("[" .. ser(k) .. "]")
    out[#out + 1] = inner .. ks .. " = " .. ser(v[k], inner)
  end
  if #out == 0 then return "{}" end
  return "{\n" .. table.concat(out, ",\n") .. "\n" .. ind .. "}"
end
DT.serialize = ser

function DT.deserialize(s)
  if type(s) ~= "string" or s == "" then return nil end
  local body = s:match("^%s*return") and s or ("return " .. s)
  local f = load(body, "=TS_DrumToolbox data", "t", {})
  if not f then return nil end
  local ok, v = pcall(f)
  if ok and type(v) == "table" then return v end
  return nil
end

local function copy(t)
  if type(t) ~= "table" then return t end
  local o = {}
  for k, v in pairs(t) do o[k] = copy(v) end
  return o
end
DT.copy = copy

-- fill what `t` lacks from `defaults` (deep, in place); returns t
local function fill(t, defaults)
  for k, v in pairs(defaults) do
    if t[k] == nil then t[k] = copy(v)
    elseif type(v) == "table" and type(t[k]) == "table" and #v == 0 then fill(t[k], v) end
  end
  return t
end

-- ---------------------------------------------------------------------
-- markers: the hit codec
-- ---------------------------------------------------------------------
-- What a marker's name says: { db = n } for a level, { manual = true }
-- for a bare "DT", the full hit for a 0.1.x "DT|db=..." name (legacy),
-- nil otherwise. Whether a level is ours depends on the take (take_hits).
function DT.decode(name)
  if type(name) ~= "string" then return nil end
  if name == DT.PREFIX then return { manual = true, locked = true } end
  if name:sub(1, #DT.PREFIX + 1) == DT.PREFIX .. "|" then
    local hit = { legacy = true }
    for field in name:sub(#DT.PREFIX + 2):gmatch("[^|]+") do
      local k, v = field:match("^(%a+)=(.*)$")
      if k then
        local n = tonumber(v)
        if k == "db" then hit.db = n
        elseif k == "c" then hit.c = n
        elseif k == "dec" then hit.dec = n
        elseif k == "po" then hit.po = n
        end
      elseif field == "L" then hit.locked = true
      end
    end
    if hit.db == nil then hit.manual = true; hit.locked = true end
    return hit
  end
  local n = name:match("^%s*([%+%-]?%d+%.?%d*)%s*$")
  if n then return { db = tonumber(n), level_only = true } end
  return nil
end

-- the marker's name: the level, or "DT" when there is none yet
function DT.encode(hit)
  if hit.db then return string.format("%.1f", hit.db) end
  return DT.PREFIX
end

-- the hit's data as kept on the take: "srcpos,db,c,dec,po,flags,tilt,from;"
-- per hit (`from`: for a hit discounted as bleed, the track it came from)
local function side_encode(entries)
  local out = {}
  for _, e in ipairs(entries) do
    local h = e.hit
    local function f(v, fmt) return v and string.format(fmt, v) or "" end
    out[#out + 1] = string.format("%.6f,%s,%s,%s,%s,%s,%s,%s", e.srcpos, f(h.db, "%.1f"), f(h.c, "%.2f"),
      f(h.dec, "%.0f"), f(h.po, "%.3f"), (h.locked and "L" or "") .. (h.manual and "M" or ""),
      f(h.tilt, "%.1f"), ((h.from or ""):gsub("[,;]", " ")))
  end
  return table.concat(out, ";")
end

local function side_decode(s)
  if not s or s == "" then return nil end
  local list = {}
  for rec in s:gmatch("[^;]+") do
    local f = {}
    for v in (rec .. ","):gmatch("([^,]*),") do f[#f + 1] = v end
    local sp = tonumber(f[1])
    if sp then
      list[#list + 1] = { s = sp, db = tonumber(f[2]), c = tonumber(f[3]), dec = tonumber(f[4]), po = tonumber(f[5]),
                          L = (f[6] or ""):find("L", 1, true) ~= nil, M = (f[6] or ""):find("M", 1, true) ~= nil,
                          tilt = tonumber(f[7] or ""), from = (f[8] and f[8] ~= "") and f[8] or nil }
    end
  end
  table.sort(list, function(a, b) return a.s < b.s end)
  return list
end
DT._side_encode, DT._side_decode = side_encode, side_decode

-- the stored hit nearest `sp` within MATCH_TOL (binary search), or nil
local function side_match(list, sp)
  local lo, hi = 1, #list
  while lo <= hi do
    local mid = (lo + hi) // 2
    if list[mid].s < sp then lo = mid + 1 else hi = mid - 1 end
  end
  local best, bd
  for i = math.max(1, hi), math.min(#list, lo) do
    local d = math.abs(list[i].s - sp)
    if d <= DT.MATCH_TOL and (not bd or d < bd) then best, bd = list[i], d end
  end
  return best
end

function DT.conf_class(c)
  if c == nil then return "mid" end
  if c >= DT.C_HI then return "hi" elseif c >= DT.C_MID then return "mid" end
  return "lo"
end

function DT.colour(hit)
  local rgb = hit.locked and not hit.manual and DT.COL.lock or DT.COL[DT.conf_class(hit.c)]
  return r.ColorToNative(rgb[1], rgb[2], rgb[3]) | 0x1000000
end

-- ---------------------------------------------------------------------
-- profiles
-- ---------------------------------------------------------------------
-- Two kinds: "detect" (how to find hits on one kind of source) and
-- "target" (what a hit plays: samples or an instrument). Built-in ones
-- are written to <resource>/Data/TS_DrumToolbox/<kind>/ the first time,
-- so they can be edited there like any other.

DT.DETECT_DEFAULT = {
  name = "Generic",
  hp_hz = 60, lp_hz = 10000,    -- detection filter only, never the output
  thresh_db = -30,
  retrigger_ms = 30,            -- flam / roll floor
  measure = "peak",             -- "peak" | "rms"
  measure_win_ms = 6,
  onset_refine = "first_peak",  -- "none" | "first_peak" | "zero_cross"
  rise_db = 6,                  -- a hit climbs at least this far within RISE_MS
                                -- (ring and shell beating rise slower)
  bleed_floor_db = -42,         -- hits near this score low confidence
  kit_check = true,             -- discount bleed from the kit's other tracks (DT.kit_check)
  kit_window_ms = 5,            -- a hit this close to one on another track is the same strike
  kit_split_db = 0,             -- quieter than this vs the other mic: that track's strike
  kit_tilt_db = 6,              -- ...unless its tilt is this close to this drum's own (when
                                -- there's too little bleed to learn its tilt from)
  kit_level_db = 6,             -- where tone can't tell own from bleed: a hit within this
                                -- of the drum's own median level is its own
  band_ref_db = -15,            -- detection band this far under the raw peak: no band score
}

DT.DETECT_BUILTIN = {
  ["Kick In"]   = { hp_hz = 30,  lp_hz = 250,  thresh_db = -26, retrigger_ms = 45, rise_db = 4, bleed_floor_db = -36 },
  ["Kick Out"]  = { hp_hz = 30,  lp_hz = 200,  thresh_db = -28, retrigger_ms = 50, rise_db = 4, bleed_floor_db = -38 },
  ["Snare Top"] = { hp_hz = 150, lp_hz = 8000, thresh_db = -28, retrigger_ms = 35, bleed_floor_db = -38 },
  ["Snare Bottom"] = { hp_hz = 2000, lp_hz = 12000, thresh_db = -30, retrigger_ms = 35, bleed_floor_db = -40 },
  ["Rack Tom"]  = { hp_hz = 80,  lp_hz = 5000, thresh_db = -26, retrigger_ms = 40, bleed_floor_db = -34 },
  ["Floor Tom"] = { hp_hz = 50,  lp_hz = 4000, thresh_db = -26, retrigger_ms = 45, bleed_floor_db = -34 },
  ["Hi-Hat"]    = { hp_hz = 4000, lp_hz = 16000, thresh_db = -32, retrigger_ms = 25, rise_db = 6, bleed_floor_db = -42 },
  ["Generic"]   = {},
}

-- which built-in a track's name suggests
-- (%f[%w]...%f[%W] = a whole word: "ft" in "Floor FT", not in "Left")
DT.NAME_HINTS = {
  { "hi%-?%s*hat", "Hi-Hat" }, { "%f[%w]hh%f[%W]", "Hi-Hat" }, { "%f[%w]hats?%f[%W]", "Hi-Hat" },
  { "kick%s*out", "Kick Out" }, { "kick", "Kick In" }, { "%f[%w]bd%f[%W]", "Kick In" },
  { "snare%s*b", "Snare Bottom" }, { "snr%s*b", "Snare Bottom" }, { "snare", "Snare Top" }, { "snr", "Snare Top" },
  { "floor", "Floor Tom" }, { "%f[%w]ft%f[%W]", "Floor Tom" }, { "rack", "Rack Tom" }, { "tom", "Rack Tom" },
}

DT.TARGET_DEFAULT = {
  name = "Untitled",
  type = "samples",             -- "samples" | "vsti"
  range_db = { -40, -6 },       -- maps onto vel_range
  vel_range = { 20, 127 },
  curve = 1.0,                  -- >1 gives more of the range to quiet hits
  dest = "child",               -- "child" | "lane"
  -- samples
  layers = {},                  -- { { max = 127, files = { path, ... } }, ... } low to high
  rr_mode = "random_no_repeat", -- "random_no_repeat" | "cycle"
  gain_from_vel = 0.5,          -- 0 = layers only, 1 = full gain scaling
  phase_align = { on = true, search_ms = 1.5, window_ms = 4, allow_flip = true },
  humanize = { gain_db = 0 },
  -- vsti
  note = 38,
  note_len = "to_next",         -- "to_next" | ms number
  calib = nil,                  -- { offset_ms, polarity, measured }
}

local function sanitize(name)
  return (tostring(name or ""):gsub("[\\/:%*%?\"<>|]", "_"))
end

function DT.profile_dir(kind)
  local sep = package.config:sub(1, 1)
  return r.GetResourcePath() .. sep .. "Data" .. sep .. DT.NS .. sep .. kind
end

local function profile_path(kind, name)
  local sep = package.config:sub(1, 1)
  return DT.profile_dir(kind) .. sep .. sanitize(name) .. ".lua"
end

local function read_file(p)
  local f = io.open(p, "rb")
  if not f then return nil end
  local s = f:read("*a"); f:close()
  return s
end

local function write_file(p, s)
  local f = io.open(p, "wb")
  if not f then return false end
  f:write(s); f:close()
  return true
end

function DT.save_profile(kind, prof)
  r.RecursiveCreateDirectory(DT.profile_dir(kind), 0)
  local head = "-- TS_DrumToolbox " .. kind .. " profile. Edit freely; unknown keys are kept.\n"
  return write_file(profile_path(kind, prof.name), head .. "return " .. ser(prof) .. "\n")
end

local function builtin(kind, name)
  if kind == "detect" then
    local b = DT.DETECT_BUILTIN[name]
    if not b then return nil end
    local p = copy(b); p.name = name
    return fill(p, DT.DETECT_DEFAULT)
  end
  return nil
end

-- Writes the built-ins that aren't on disk yet. Safe to call every run.
function DT.install_builtins()
  for name in pairs(DT.DETECT_BUILTIN) do
    if not read_file(profile_path("detect", name)) then DT.save_profile("detect", builtin("detect", name)) end
  end
end

function DT.load_profile(kind, name)
  local p = DT.deserialize(read_file(profile_path(kind, name)) or "") or builtin(kind, name)
  if not p then return nil end
  p.name = p.name or name
  return fill(p, kind == "detect" and DT.DETECT_DEFAULT or DT.TARGET_DEFAULT)
end

function DT.list_profiles(kind)
  local names, seen, i = {}, {}, 0
  local dir = DT.profile_dir(kind)
  while true do
    local f = r.EnumerateFiles(dir, i)
    if not f then break end
    local n = f:match("^(.*)%.lua$")
    if n and not seen[n] then names[#names + 1] = n; seen[n] = true end
    i = i + 1
  end
  if kind == "detect" then
    for n in pairs(DT.DETECT_BUILTIN) do if not seen[n] then names[#names + 1] = n end end
  end
  table.sort(names)
  return names
end

-- the detection profile a track's name suggests (a name, always)
function DT.suggest_detect(track)
  local _, nm = r.GetTrackName(track)
  nm = (nm or ""):lower()
  for _, h in ipairs(DT.NAME_HINTS) do
    if nm:find(h[1]) then return h[2] end
  end
  return "Generic"
end

-- ---------------------------------------------------------------------
-- kit roles
-- ---------------------------------------------------------------------
-- Each track in the kit has a role:
--   drum       detected; Replace / Gate / Noise
--   second     a second mic of a drum (Kick Sub, Snare Bottom): uses that
--              drum's hit map; not detected; left out of the bleed check
--   bleed      detected only so its strikes can be discounted elsewhere
--              (Hi Hat); nothing generated
--   reference  context (overheads, room); alignment reference
--   ignore     not part of the kit
-- Stored in P_EXT:TS_DT_role as "role|profile|drum GUID". A track with no
-- role is suggested one from its name (DT.suggest_role); a track with a
-- hit map and no role counts as a drum.
DT.ROLES = { "drum", "second", "bleed", "reference", "ignore" }
DT.ROLE_LABEL = { drum = "Drum", second = "Second mic", bleed = "Bleed source", reference = "Reference", ignore = "Ignore" }
DT.KEY_ROLE = "P_EXT:TS_DT_role"

-- names that make a track a second mic / reference (checked before the
-- drum hints); `of` = the detection profile of the drum it belongs to
DT.ROLE_HINTS = {
  -- busses, groups and effect returns are never kit mics
  { "%f[%w]bus", "ignore" }, { "%f[%w]grp%f[%W]", "ignore" }, { "group", "ignore" },
  { "verb", "ignore" }, { "parallel", "ignore" }, { "%f[%w]fx%f[%W]", "ignore" }, { "%f[%w]print", "ignore" },
  { "kick%s*sub", "second", "Kick In" }, { "sub%s*kick", "second", "Kick In" },
  { "kick%s*out", "second", "Kick In" },
  { "snare%s*bot", "second", "Snare Top" }, { "snare%s*btm", "second", "Snare Top" }, { "snare%s*under", "second", "Snare Top" },
  { "snare%s*b%f[%W]", "second", "Snare Top" }, { "snr%s*b%f[%W]", "second", "Snare Top" }, { "snr%s*bot", "second", "Snare Top" },
  { "over%s*head", "reference" }, { "%f[%w]ohs?%f[%W]", "reference" }, { "%f[%w]ovh", "reference" },
  { "room", "reference" }, { "%f[%w]amb", "reference" },
}

local function track_by_guid(guid)
  if not guid or guid == "" then return nil end
  for i = 0, r.CountTracks(0) - 1 do
    local t = r.GetTrack(0, i)
    if r.GetTrackGUID(t) == guid then return t end
  end
  return nil
end
DT.track_by_guid = track_by_guid

local function track_name(t) local _, n = r.GetTrackName(t); return n or "" end

-- The role stored on a track: { role, profile, of = drum track, user }
-- or nil. `user`: set by hand (always wins); otherwise suggested, and
-- re-suggested whenever the rules change. No flag counts as suggested.
function DT.get_role(track)
  local ok, v = r.GetSetMediaTrackInfo_String(track, DT.KEY_ROLE, "", false)
  if not ok or v == "" then return nil end
  local f = {}
  for x in (v .. "|"):gmatch("([^|]*)|") do f[#f + 1] = x end
  if not f[1] or f[1] == "" then return nil end
  return { role = f[1], profile = (f[2] or "") ~= "" and f[2] or nil, of = track_by_guid(f[3]), user = f[4] == "u" }
end

-- Stores a track's role. user = true for a choice made by hand.
function DT.set_role(track, role, profile, of_track, user)
  local v = ""
  if role then
    v = role .. "|" .. (profile or "") .. "|" .. (of_track and r.GetTrackGUID(of_track) or "") .. "|" .. (user and "u" or "a")
  end
  r.GetSetMediaTrackInfo_String(track, DT.KEY_ROLE, v, true)
end

-- A folder parent with nothing on it of its own: a container (the "Kick"
-- folder holding Kick In and Kick Sub), never a mic.
local function is_container(t)
  return r.GetMediaTrackInfo_Value(t, "I_FOLDERDEPTH") == 1 and r.CountTrackMediaItems(t) == 0
end

-- What a track's name suggests: { role, profile, of_profile } (of_profile:
-- the profile of the drum a second mic belongs to). Unrecognised names,
-- tracks with no items (folders, effect returns such as a "Drum Room"
-- reverb, busses) and DrumToolbox's own tracks: { role = "ignore" }.
function DT.suggest_role(track)
  local okl, lk = r.GetSetMediaTrackInfo_String(track, DT.KEY_LINK, "", false)
  if okl and lk ~= "" then return { role = "ignore" } end      -- one DrumToolbox made
  if is_container(track) then return { role = "ignore", container = true } end
  -- no audio of its own (an effect return, a bus): not a mic, whatever its name
  if r.CountTrackMediaItems(track) == 0 then return { role = "ignore", no_audio = true } end
  local nm = track_name(track):lower()
  for _, h in ipairs(DT.ROLE_HINTS) do
    if nm:find(h[1]) then return { role = h[2], of_profile = h[3] } end
  end
  for _, h in ipairs(DT.NAME_HINTS) do
    if nm:find(h[1]) then
      return { role = h[2] == "Hi-Hat" and "bleed" or "drum", profile = h[2] }
    end
  end
  return { role = "ignore" }
end

-- A track DrumToolbox Pro made for a drum (noise, a sample, the kit
-- instrument, a gate key): not part of the kit
function DT.is_support(t)
  for _, k in ipairs({ "is_noise_track", "is_sampler_track", "is_kit_inst", "is_gate_key" }) do
    if DT[k] and DT[k](t) then return true end
  end
  return false
end

-- Every track in the project with its role: { track, name, role, profile,
-- of (drum track), user (set by hand), stored }. Roles set by hand are
-- used as they are; the rest are suggested from names. A second mic
-- belongs to a drum with the profile it names (Kick In for a kick sub),
-- in the same folder if there is one there, else anywhere; with no such
-- drum, the second mic is the drum (Kick Sub alone -> Kick Out profile).
function DT.kit_roles()
  local list, drums = {}, {}
  for i = 0, r.CountTracks(0) - 1 do
    local t = r.GetTrack(0, i)
    if not DT.is_support(t) then
    local st = DT.get_role(t)
    local e = { track = t, name = track_name(t), parent = r.GetParentTrack(t), stored = st ~= nil }
    if st and st.user then
      e.role, e.profile, e.of, e.user = st.role, st.profile, st.of, true
    else
      local sg = DT.suggest_role(t)
      e.role, e.profile, e.of_profile = sg.role, sg.profile, sg.of_profile
      if DT.is_source(t) and e.role ~= "bleed" and not sg.container then e.role = "drum" end
    end
    if e.role == "drum" or e.role == "bleed" then
      e.profile = e.profile or DT.suggest_detect(t)
      if e.role == "drum" then drums[#drums + 1] = e end
    end
    list[#list + 1] = e
    end
  end
  for _, e in ipairs(list) do
    if e.role == "second" and not e.of then
      local same, any
      for _, d in ipairs(drums) do
        if d.profile == e.of_profile then
          any = any or d.track
          if d.parent == e.parent then same = same or d.track end
        end
      end
      e.of = same or any
      if not e.of then
        -- no such drum in the kit: this mic is the drum
        e.role = "drum"
        e.profile = e.profile or DT.suggest_detect(e.track)
        if e.profile == "Kick In" and track_name(e.track):lower():find("sub") then e.profile = "Kick Out" end
      end
    end
    e.of_profile = nil
  end
  return list
end

-- Stores the suggested roles: on kit tracks that have none, and over
-- suggestions stored before (so better rules fix them). Roles set by hand
-- are left alone, and nothing is written to tracks that aren't part of
-- the kit (a stale suggestion on one is cleared). Gives how many changed.
function DT.store_suggested_roles()
  local n = 0
  for _, e in ipairs(DT.kit_roles()) do
    if not e.user then
      local want = e.role ~= "ignore" and (e.role .. "|" .. (e.profile or "") .. "|" .. (e.of and r.GetTrackGUID(e.of) or "") .. "|a") or ""
      local _, have = r.GetSetMediaTrackInfo_String(e.track, DT.KEY_ROLE, "", false)
      if (have or "") ~= want then
        r.GetSetMediaTrackInfo_String(e.track, DT.KEY_ROLE, want, true)
        n = n + 1
      end
    end
  end
  return n
end

-- The tracks a selection means: selected tracks, and everything inside a
-- selected folder.
function DT.expand_selection()
  local set, out = {}, {}
  local n = r.CountTracks(0)
  for i = 0, n - 1 do
    local t = r.GetTrack(0, i)
    local sel = r.IsTrackSelected(t)
    if not sel then
      local p = r.GetParentTrack(t)
      while p do
        if r.IsTrackSelected(p) then sel = true; break end
        p = r.GetParentTrack(p)
      end
    end
    if sel and not set[t] then set[t] = true; out[#out + 1] = t end
  end
  return out, set
end

-- the detection profile for a track: its role's, else its name's
function DT.track_profile(track)
  local st = DT.get_role(track)
  return (st and st.profile) or DT.suggest_detect(track)
end

-- The source a track belongs to: itself if it's a drum or bleed source
-- with a hit map; its drum if it's a second mic; its source if it's a
-- generated track (P_EXT:TS_DT_link). Else nil. (What ChannelView asks.)
local source_cache = {}
function DT.source_of(track)
  if not track then return nil end
  local st = DT.get_role(track)
  if is_container(track) then return nil end
  if st and st.role == "second" then return st.of end
  if st and (st.role == "reference" or st.role == "ignore") then return nil end
  if DT.is_source(track) then return track end
  local ok, g = r.GetSetMediaTrackInfo_String(track, DT.KEY_LINK, "", false)
  if ok and g ~= "" then
    local c = source_cache[g]
    if c and r.ValidatePtr(c, "MediaTrack*") then return c end
    c = track_by_guid(g); source_cache[g] = c
    return c
  end
  return nil
end

-- ---------------------------------------------------------------------
-- tracks, items, takes
-- ---------------------------------------------------------------------
-- The audio takes on a track, in time order. opts.selected: only
-- selected items.
function DT.track_takes(track, opts)
  opts = opts or {}
  local out = {}
  for i = 0, r.CountTrackMediaItems(track) - 1 do
    local item = r.GetTrackMediaItem(track, i)
    if not opts.selected or r.IsMediaItemSelected(item) then
      local take = r.GetActiveTake(item)
      if take and not r.TakeIsMIDI(take) then
        out[#out + 1] = {
          item = item, take = take, index = #out + 1,
          pos = r.GetMediaItemInfo_Value(item, "D_POSITION"),
          len = r.GetMediaItemInfo_Value(item, "D_LENGTH"),
          offs = r.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS"),
          rate = r.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE"),
        }
      end
    end
  end
  table.sort(out, function(a, b) return a.pos < b.pos end)
  for i, t in ipairs(out) do t.index = i end
  return out
end

local function src_to_item(tk, srcpos) return (srcpos - tk.offs) / tk.rate end
local function item_to_src(tk, t) return tk.offs + t * tk.rate end

-- Our hits on a take, as { idx = marker index, srcpos, hit }, sorted by
-- position. Each hit: db (from the marker's name), c, dec, po, locked,
-- manual (needs measuring: a bare "DT", or a level with no stored hit --
-- moved or added by hand), edited (its level was renamed by hand).
local function take_hits(take)
  local ok, sv = r.GetSetMediaItemTakeInfo_String(take, DT.KEY_HITS, "", false)
  local side = ok and side_decode(sv) or nil
  local out = {}
  for m = 0, r.GetNumTakeMarkers(take) - 1 do
    local srcpos, name = r.GetTakeMarker(take, m)
    local h = DT.decode(name)
    if h and h.level_only then
      if not side then
        h = nil                                   -- someone else's number
      else
        h.level_only = nil
        local e = side_match(side, srcpos)
        if e then
          h.c, h.dec, h.po, h.locked, h.manual, h.tilt = e.c, e.dec, e.po, e.L or nil, e.M or nil, e.tilt
          if e.db and math.abs(e.db - h.db) > 0.05 then h.edited = true; h.locked = true end
        else
          h.manual, h.locked, h.moved = true, true, true
        end
      end
    end
    if h then out[#out + 1] = { idx = m, srcpos = srcpos, hit = h } end
  end
  table.sort(out, function(a, b) return a.srcpos < b.srcpos end)
  return out
end

-- Rewrites a take's hits from `entries` ({ srcpos, hit }): every one of
-- our markers goes and these come back, named and coloured, with their
-- data stored beside them. Other markers are left alone.
local function rewrite_take(take, entries)
  local del = {}
  for _, e in ipairs(take_hits(take)) do del[#del + 1] = e.idx end
  table.sort(del, function(a, b) return a > b end)
  for _, idx in ipairs(del) do r.DeleteTakeMarker(take, idx) end
  table.sort(entries, function(a, b) return a.srcpos < b.srcpos end)
  for _, e in ipairs(entries) do
    e.hit.legacy, e.hit.edited, e.hit.moved = nil, nil, nil
    r.SetTakeMarker(take, -1, DT.encode(e.hit), e.srcpos, DT.colour(e.hit))
  end
  r.GetSetMediaItemTakeInfo_String(take, DT.KEY_HITS, #entries > 0 and side_encode(entries) or "", true)
end

-- Every hit on a track, in time order, gathered across its items:
-- { proj = time, item = n, take = take, mk = marker index, srcpos,
--   db, c, dec, po, locked, manual, edited }. Markers outside the item's
-- visible part are skipped (they come back if the item is extended).
function DT.track_hits(track, opts)
  local hits = {}
  for _, tk in ipairs(DT.track_takes(track, opts)) do
    for _, e in ipairs(take_hits(tk.take)) do
      local h = e.hit
      local t = src_to_item(tk, e.srcpos)
      if t >= 0 and t <= tk.len then
        h.proj, h.item, h.take, h.mk, h.srcpos = tk.pos + t, tk.index, tk.take, e.idx, e.srcpos
        hits[#hits + 1] = h
      end
    end
  end
  table.sort(hits, function(a, b) return a.proj < b.proj end)
  return hits
end

-- a fingerprint of a hit list: count, positions, levels (what's written
-- from it - notes, envelopes - is rewritten when it changes)
function DT.hits_sig(hits)
  local sp, sd = 0, 0
  for _, h in ipairs(hits) do sp = sp + h.proj; sd = sd + (h.db or 0) end
  return string.format("%d:%.4f:%.2f", #hits, sp, sd)
end

function DT.is_source(track)
  local ok, v = r.GetSetMediaTrackInfo_String(track, DT.KEY_TRACK, "", false)
  return ok and v ~= ""
end

local function mark_source(track, on)
  r.GetSetMediaTrackInfo_String(track, DT.KEY_TRACK, on and "1" or "", true)
end

-- the settings a take was detected with, or nil
function DT.take_settings(take)
  local ok, s = r.GetSetMediaItemTakeInfo_String(take, DT.KEY_TAKE, "", false)
  return ok and DT.deserialize(s) or nil
end

-- ---------------------------------------------------------------------
-- level -> velocity
-- ---------------------------------------------------------------------
function DT.velocity(level_db, target)
  local lo, hi = target.range_db[1], target.range_db[2]
  local n = clamp((level_db - lo) / (hi - lo), 0, 1)
  local v0, v1 = target.vel_range[1], target.vel_range[2]
  return clamp(math.floor(v0 + (v1 - v0) * n ^ (target.curve or 1) + 0.5), 1, 127)
end

-- ---------------------------------------------------------------------
-- DSP: biquads (RBJ cookbook), mono mix-down
-- ---------------------------------------------------------------------
local function biquad(kind, f, sr, q)
  q = q or 0.7071
  f = clamp(f, 10, sr * 0.45)
  local w = 2 * math.pi * f / sr
  local cw, sw = math.cos(w), math.sin(w)
  local a = sw / (2 * q)
  local b0, b1, b2
  if kind == "hp" then b0, b1, b2 = (1 + cw) / 2, -(1 + cw), (1 + cw) / 2
  else b0, b1, b2 = (1 - cw) / 2, 1 - cw, (1 - cw) / 2 end
  local a0 = 1 + a
  return { b0 / a0, b1 / a0, b2 / a0, (-2 * cw) / a0, (1 - a) / a0, 0, 0, 0, 0 }
end
-- state lives in [6..9] (x1, x2, y1, y2)

-- The detection filter: 24 dB/oct HP and LP (two biquads each). A
-- frequency at the end of its range switches that side off.
local function make_filter(p, sr)
  local st = {}
  if p.hp_hz and p.hp_hz > 15 then st[#st + 1] = biquad("hp", p.hp_hz, sr); st[#st + 1] = biquad("hp", p.hp_hz, sr) end
  if p.lp_hz and p.lp_hz < sr * 0.45 then st[#st + 1] = biquad("lp", p.lp_hz, sr); st[#st + 1] = biquad("lp", p.lp_hz, sr) end
  return st
end

local function run_filter(st, x)
  for i = 1, #st do
    local c = st[i]
    local y = c[1] * x + c[2] * c[6] + c[3] * c[7] - c[4] * c[8] - c[5] * c[9]
    c[7], c[6] = c[6], x
    c[9], c[8] = c[8], y
    x = y
  end
  return x
end
DT._make_filter, DT._run_filter = make_filter, run_filter

-- source facts for a take: sample rate and channels to read
local function take_format(take)
  local src = r.GetMediaItemTake_Source(take)
  local sr = src and r.GetMediaSourceSampleRate(src) or 0
  if not sr or sr <= 0 then sr = 48000 end
  local nch = src and r.GetMediaSourceNumChannels(src) or 1
  nch = clamp(math.floor(nch or 1), 1, 2)
  return sr, nch
end

-- Reads `n` mono samples from `t` (item time) into a Lua array (1-based).
-- Before the take's start or after its end reads as silence.
-- `buf` is { arr = reaper.array, size = n } and is reused between calls.
local function read_mono(acc, sr, nch, t, n, buf)
  local need = n * nch
  if not buf or buf.size < need then buf = { arr = r.new_array(need), size = need } end
  local arr = buf.arr
  arr.clear()
  r.GetAudioAccessorSamples(acc, sr, nch, t, n, arr)
  local raw = arr.table(1, need)
  if nch == 1 then return raw, buf end
  local out = {}
  for i = 1, n do out[i] = (raw[2 * i - 1] + raw[2 * i]) * 0.5 end
  return out, buf
end

-- ---------------------------------------------------------------------
-- detection, pass 1: candidates
-- ---------------------------------------------------------------------
-- A scanner over one take's audio, a block per scan_block() call, so a
-- caller can spread the work over many defer cycles. (Not a coroutine:
-- REAPER's audio accessor reads silence from inside one.) Collects
-- candidate times (item time) and the filtered envelope's peak (dB)
-- shortly after each.
local function new_scanner(acc, sr, nch, t0, t1, p)
  local lo = math.max(20, p.hp_hz or 60)
  local retrig = math.max(1, math.floor((p.retrigger_ms or 30) / 1000 * sr))
  return {
    acc = acc, sr = sr, nch = nch, t0 = t0, p = p,
    filt = make_filter(p, sr),
    thr_lin = undb(p.thresh_db),
    retrig = retrig,
    rel = math.exp(-1 / (clamp(1.5 / lo, 0.010, 0.060) * sr)),
    hold = math.floor(clamp(1 / lo, 0.005, 0.030) * sr),
    rise = undb(p.rise_db or 6),
    hold_to = 0,
    -- the envelope one rise window ago, as a ring
    dl = math.max(1, math.floor(clamp(0.33 / lo, 0.005, 0.012) * sr)), ring = {}, rp = 0,
    peak_win = math.max(1, math.floor(0.012 * sr)),       -- peak read 12 ms after onset
    env = 0, last = -retrig,
    total = math.max(1, math.floor((t1 - t0) * sr)), idx = 0,
    out = {}, cur = nil, buf = nil,
  }
end

-- Scans the next block. Gives true when the take is done.
local function scan_block(sc)
  if sc.idx >= sc.total then return true end
  local n = math.min(DT.BLOCK, sc.total - sc.idx)
  local x
  x, sc.buf = read_mono(sc.acc, sc.sr, sc.nch, sc.t0 + sc.idx / sc.sr, n, sc.buf)
  local filt, rel, thr_lin, retrig, pw = sc.filt, sc.rel, sc.thr_lin, sc.retrig, sc.peak_win
  local env, last, cur, out = sc.env, sc.last, sc.cur, sc.out
  local hold, rise, hold_to = sc.hold, sc.rise, sc.hold_to
  local ring, rp, dl = sc.ring, sc.rp, sc.dl
  local base = sc.idx
  for i = 1, n do
    local y = run_filter(filt, x[i])
    if y < 0 then y = -y end
    local s = base + i
    if y >= env then env = y; hold_to = s + hold
    elseif s > hold_to then env = env * rel end
    rp = rp + 1; if rp > dl then rp = 1 end
    local before = ring[rp] or 0
    ring[rp] = env
    if cur then
      if env > cur.pk then cur.pk = env end
      if s - cur.s >= pw then cur.fdb = db(cur.pk); out[#out + 1] = cur; cur = nil end
    end
    -- a hit: over the threshold, risen fast, and past the retrigger time
    if env >= thr_lin and env >= before * rise and s - last >= retrig then
      last = s
      if cur then cur.fdb = db(cur.pk); out[#out + 1] = cur end
      -- where the rise began: the lowest envelope in the look-back
      local kmin, vmin = 0, env
      for k = 0, dl - 1 do
        local ix = rp - k; if ix < 1 then ix = ix + dl end
        local v = ring[ix]
        if v and v < vmin then vmin, kmin = v, k end
      end
      cur = { s = s, t = sc.t0 + s / sc.sr, pk = env, rise_t = sc.t0 + (s - kmin) / sc.sr }
    end
  end
  sc.env, sc.last, sc.cur, sc.hold_to, sc.rp = env, last, cur, hold_to, rp
  sc.idx = sc.idx + n
  if sc.idx >= sc.total then
    if sc.cur then sc.cur.fdb = db(sc.cur.pk); out[#out + 1] = sc.cur; sc.cur = nil end
    return true
  end
  return false
end

-- all at once (tests)
local function candidates(acc, sr, nch, t0, t1, p)
  local sc = new_scanner(acc, sr, nch, t0, t1, p)
  while not scan_block(sc) do end
  return sc.out
end

-- ---------------------------------------------------------------------
-- detection, pass 2: one hit
-- ---------------------------------------------------------------------
-- From a window of unfiltered audio around a candidate: the onset
-- (item time), level, decay and confidence. `nxt`: the next candidate's
-- time, which bounds the decay.
local function measure(acc, sr, nch, cand_t, fdb, nxt, p, buf, prv, rise_t)
  local pre = math.floor(DT.PRE * sr)
  -- never search back into the hit before
  if prv then pre = math.max(0, math.min(pre, math.floor((cand_t - prv) * 0.5 * sr))) end
  -- where the fallback search (no clear click) starts: 5 ms before the
  -- rise detection saw, so a ring before it isn't taken for the onset
  local fb_from = 1
  if rise_t and rise_t <= cand_t then
    fb_from = math.max(1, pre - math.floor((cand_t - rise_t) * sr) - math.floor(0.005 * sr))
  end
  local win = math.max(1, math.floor((p.measure_win_ms or 6) / 1000 * sr))
  local dec_max = DT.DEC_MAX
  if nxt then dec_max = math.min(dec_max, math.max(0.005, nxt - cand_t)) end
  local n = pre + math.floor(math.max(dec_max + 0.02, DT.TILT_MS / 1000 + 0.005) * sr)
  local x
  x, buf = read_mono(acc, sr, nch, cand_t - pre / sr, n, buf)

  -- the local peak, from a little before the candidate to the end of the
  -- measure window after it
  local pk = 0
  for i = 1, math.min(n, pre + win * 2) do
    local a = x[i]; if a < 0 then a = -a end
    if a > pk then pk = a end
  end
  if pk <= 0 then return nil, buf end

  -- onset. First, the strike's click: high-passed, the ring of the hit
  -- before (or this one's body) drops out, and the click's start is
  -- sharp. Used when the click stands CLICK_DB over the high-passed level
  -- in the first half of the lead-in. Otherwise the first sample at a
  -- quarter of the local peak. Then (zero_cross) back to the sign change
  -- before it.
  local on = pre + 1
  local mode = p.onset_refine or "first_peak"
  if mode ~= "none" then
    local found
    -- (the filter starts cold on a window that may open mid-ring: its
    -- first 2 ms are its own start-up, not the audio)
    local settle = math.floor(0.002 * sr)
    local lim_i = math.min(n, pre + win * 2)
    if lim_i > settle + 16 then
      local hp = { biquad("hp", DT.ONSET_HP, sr), biquad("hp", DT.ONSET_HP, sr) }
      local h, hpk, k = {}, 0, nil
      for i = 1, lim_i do
        local v = run_filter(hp, x[i]); if v < 0 then v = -v end
        h[i] = v
        if i > settle and v > hpk then hpk, k = v, i end
      end
      if k then
        -- the click's start: back from its peak to where it was under a
        -- quarter of it; the level before that is what it stands over
        local lim = hpk * 0.25
        local st = k
        while st > settle + 1 and h[st - 1] >= lim do st = st - 1 end
        local floor_ = 0
        for i = settle + 1, st - math.floor(0.001 * sr) do if h[i] > floor_ then floor_ = h[i] end end
        -- then further back, to where it first left the floor: a tenth of
        -- its peak or twice the floor, over the click's own zero
        -- crossings (1 ms at most)
        local lim2 = math.max(hpk * 0.1, floor_ * 2)
        local back = math.floor(0.001 * sr)
        local j = st
        for i = st - 1, math.max(settle + 1, st - back), -1 do
          if h[i] >= lim2 then j = i end
        end
        st = j
        if hpk >= floor_ * undb(DT.CLICK_DB) then found = st end
      end
    end
    if not found then
      local lim = pk * 0.25
      for i = fb_from, n do
        local a = x[i]; if a < 0 then a = -a end
        if a >= lim then found = i; break end
      end
    end
    on = found or on
    if mode == "zero_cross" then
      local floor_i = math.max(1, on - math.floor(0.002 * sr))
      for i = on, floor_i + 1, -1 do
        if (x[i] >= 0) ~= (x[i - 1] >= 0) then on = i; break end
      end
    end
  end

  -- level over the measure window from the onset
  local lvl
  if p.measure == "rms" then
    local s, c = 0, 0
    for i = on, math.min(n, on + win - 1) do s = s + x[i] * x[i]; c = c + 1 end
    lvl = db(math.sqrt(s / math.max(1, c)))
  else
    local m = 0
    for i = on, math.min(n, on + win - 1) do local a = x[i]; if a < 0 then a = -a end; if a > m then m = a end end
    lvl = db(m)
  end
  local raw_pk = db(pk)

  -- decay: 5 ms RMS steps from the onset until DEC_DROP under the first
  -- (loudest early) step
  local step = math.max(1, math.floor(0.005 * sr))
  local first, dec_s
  local i = on
  local k = 0
  while i + step - 1 <= n do
    local s = 0
    for j = i, i + step - 1 do s = s + x[j] * x[j] end
    local d = db(math.sqrt(s / step))
    if not first or (k < 3 and d > first) then first = d end
    if first and d <= first - DT.DEC_DROP then dec_s = (i - on) / sr; break end
    i = i + step; k = k + 1
  end
  dec_s = dec_s or ((n - on) / sr)

  -- confidence: how far over the bleed floor the hit stands in the
  -- detection band, and how much of the hit is in that band at all
  -- (bleed from another drum is loud in the raw mic but weak in the band)
  local floor_db, thr = p.bleed_floor_db, p.thresh_db
  local level_score = clamp((fdb - floor_db) / ((thr + 12) - floor_db), 0, 1)
  local band_score = clamp(((fdb - raw_pk) - (p.band_ref_db or -15)) / (-(p.band_ref_db or -15) - 3), 0, 1)
  local c = 0.6 * level_score + 0.4 * band_score

  -- tilt: the low band (a drum's body) over the high band (crack, click,
  -- cymbals) in the first TILT_MS from the onset. What tells a tom from
  -- the snare bleeding into its mic (see DT.kit_check).
  local tilt
  do
    local lo_f, hi_f = make_filter({ hp_hz = DT.TILT_LO[1], lp_hz = DT.TILT_LO[2] }, sr), make_filter({ hp_hz = DT.TILT_HI, lp_hz = sr }, sr)
    local sl, sh, k = 0, 0, 0
    for i = on, math.min(n, on + math.floor(DT.TILT_MS / 1000 * sr) - 1) do
      local a, b = run_filter(lo_f, x[i]), run_filter(hi_f, x[i])
      sl, sh, k = sl + a * a, sh + b * b, k + 1
    end
    if k > 0 then tilt = round(db(math.sqrt(sl / k)) - db(math.sqrt(sh / k)), 1) end
  end

  return {
    tilt = tilt,
    t = cand_t + (on - 1 - pre) / sr,
    db = round(lvl, 1),
    dec = dec_s * 1000,
    c = round(c, 2),
    fdb = fdb,
  }, buf
end

-- ---------------------------------------------------------------------
-- writing the map
-- ---------------------------------------------------------------------
-- Puts detected hits on a take.
--   mode "replace": unlocked hits go; locked ones stay, and a new hit
--                   within the retrigger time of a locked one is dropped.
--   mode "add":     every existing hit stays; only hits not within the
--                   retrigger time of one are added (deleted hits stay
--                   deleted).
-- Gives the counts { added, kept, removed }.
function DT.write_hits(tk, found, p, mode)
  mode = mode or "replace"
  local final, removed = {}, 0
  for _, e in ipairs(take_hits(tk.take)) do
    if mode == "add" or e.hit.locked then final[#final + 1] = e else removed = removed + 1 end
  end
  local kept = #final
  local win = (p.retrigger_ms or 30) / 1000 * tk.rate
  local added = 0
  for _, h in ipairs(found) do
    local sp = item_to_src(tk, h.t)
    local clash = false
    for i = 1, kept do if math.abs(final[i].srcpos - sp) < win then clash = true; break end end
    if not clash then
      final[#final + 1] = { srcpos = sp, hit = { db = h.db, c = h.c, dec = h.dec, tilt = h.tilt } }
      added = added + 1
    end
  end
  rewrite_take(tk.take, final)
  return { added = added, kept = kept, removed = removed }
end

-- Writes one hit back after an edit (lock, level...). `hit` as
-- track_hits gives it.
function DT.update_hit(hit)
  local entries = take_hits(hit.take)
  for _, e in ipairs(entries) do
    if e.idx == hit.mk then
      e.hit = { db = hit.db, c = hit.c, dec = hit.dec, po = hit.po, tilt = hit.tilt, locked = hit.locked, manual = hit.manual }
    end
  end
  rewrite_take(hit.take, entries)
end

-- Removes every DrumToolbox marker from a track's takes, their stored
-- data and the track's flag. Other markers stay.
function DT.clear_track(track, opts)
  for _, tk in ipairs(DT.track_takes(track, opts)) do
    rewrite_take(tk.take, {})
    r.GetSetMediaItemTakeInfo_String(tk.take, DT.KEY_TAKE, "", true)
    r.GetSetMediaItemTakeInfo_String(tk.take, DT.KEY_BLEED, "", true)
  end
  if #DT.track_hits(track) == 0 then mark_source(track, false) end
end

-- ---------------------------------------------------------------------
-- detection, the whole of it
-- ---------------------------------------------------------------------
-- A detection job: call job:step(budget) repeatedly (from a defer loop,
-- say) until it gives true; each call works for about `budget` seconds.
-- job.progress (0-1) and job.label say how far it is; job.report, once
-- done:
--   { takes = n, hits = n, added = n, kept = n, removed = n,
--     review = n (under C_HI: amber and red), low = n (under C_MID: red),
--     per_take = { ... }, diag = { ... } }
-- job.error is set (and step gives true) if something failed.
-- opts: profile (table, or name; default from the track's name),
--       mode ("replace" | "add"), selected (only selected items).
-- Changes the project only as each take finishes; wrap the stepping in
-- an undo block if it runs to the end in one go, or call DT.detect.
function DT.detect_job(track, opts)
  opts = opts or {}
  local p = opts.profile
  if type(p) ~= "table" then p = DT.load_profile("detect", p or DT.track_profile(track)) end
  local job = {
    track = track, opts = opts, p = p,
    takes = DT.track_takes(track, opts), ti = 0, phase = "next",
    progress = 0, label = "",
    report = { takes = 0, hits = 0, added = 0, kept = 0, removed = 0, low = 0, review = 0, per_take = {}, profile = p.name,
               diag = { cands = 0, no_measure = 0, out_of_range = 0 } },
  }
  job.report.takes = #job.takes

  local function finish_take(j)
    local tk, rep = j.takes[j.ti], j.report
    if j.acc then r.DestroyAudioAccessor(j.acc); j.acc = nil end
    local res = DT.write_hits(tk, j.found, j.p, j.opts.mode)
    if j.opts.mode ~= "add" then r.GetSetMediaItemTakeInfo_String(tk.take, DT.KEY_BLEED, "", true) end
    r.GetSetMediaItemTakeInfo_String(tk.take, DT.KEY_TAKE, ser({ profile = j.p.name, settings = j.p, version = DT.VERSION }), true)
    for _, h in ipairs(j.found) do
      if h.c < DT.C_HI then rep.review = rep.review + 1 end
      if h.c < DT.C_MID then rep.low = rep.low + 1 end
    end
    rep.hits = rep.hits + #j.found
    rep.added, rep.kept, rep.removed = rep.added + res.added, rep.kept + res.kept, rep.removed + res.removed
    rep.per_take[j.ti] = { found = #j.found, added = res.added, kept = res.kept, removed = res.removed }
  end

  local function run(j, budget)
    local stop = r.time_precise() + (budget or 0.02)
    local nt = math.max(1, #j.takes)
    repeat
      if j.phase == "next" then
        j.ti = j.ti + 1
        local tk = j.takes[j.ti]
        if not tk then
          if #DT.track_hits(j.track) > 0 then mark_source(j.track, true) end
          r.UpdateArrange()
          j.progress, j.phase, j.label = 1, "done", "done"
          return true
        end
        j.acc = r.CreateTakeAudioAccessor(tk.take)
        j.sr, j.nch = take_format(tk.take)
        local t0 = math.max(0, r.GetAudioAccessorStartTime(j.acc))
        local t1 = math.min(tk.len, r.GetAudioAccessorEndTime(j.acc))
        j.sc = new_scanner(j.acc, math.min(j.sr, DT.SCAN_SR), j.nch, t0, t1, j.p)
        j.found, j.ci, j.mbuf = {}, 0, nil
        j.phase = "scan"
        j.report.diag.span = string.format("%.3f-%.3f @%d/%dch", t0, t1, j.sr, j.nch)
      elseif j.phase == "scan" then
        if scan_block(j.sc) then
          j.cands = j.sc.out
          j.report.diag.cands = j.report.diag.cands + #j.cands
          j.phase = "measure"
        end
        j.progress = ((j.ti - 1) + 0.8 * j.sc.idx / j.sc.total) / nt
      elseif j.phase == "measure" then
        local tk, d = j.takes[j.ti], j.report.diag
        for _ = 1, 32 do
          j.ci = j.ci + 1
          local cd = j.cands[j.ci]
          if not cd then break end
          local nxt = j.cands[j.ci + 1] and j.cands[j.ci + 1].t or nil
          local prv = j.cands[j.ci - 1] and j.cands[j.ci - 1].t or nil
          local h
          h, j.mbuf = measure(j.acc, j.sr, j.nch, cd.t, cd.fdb, nxt, j.p, j.mbuf, prv, cd.rise_t)
          if not h then d.no_measure = d.no_measure + 1
          elseif h.t < 0 or h.t > tk.len then d.out_of_range = d.out_of_range + 1
          else j.found[#j.found + 1] = h end
        end
        if j.ci >= #j.cands then
          finish_take(j)
          j.phase = "next"
        end
        j.progress = ((j.ti - 1) + 0.8 + 0.2 * math.min(1, j.ci / math.max(1, #j.cands))) / nt
      else
        return true
      end
      j.label = string.format("item %d of %d", math.min(j.ti, #j.takes), #j.takes)
    until r.time_precise() >= stop
    return false
  end

  function job:step(budget)
    if self.phase == "done" or self.error then return true end
    local ok, done = pcall(run, self, budget)
    if not ok then
      self.error = tostring(done)
      if self.acc then r.DestroyAudioAccessor(self.acc); self.acc = nil end
      return true
    end
    return done
  end

  -- stop early: nothing more is written; takes already finished keep
  -- their new markers
  function job:cancel()
    if self.acc then r.DestroyAudioAccessor(self.acc); self.acc = nil end
    self.phase = "done"
  end

  return job
end

-- Runs detection to the end in one go. Same arguments; gives the report
-- (raises the job's error, if any).
function DT.detect(track, opts)
  local job = DT.detect_job(track, opts)
  while not job:step(math.huge) do end
  if job.error then error(job.error, 0) end
  return job.report
end

-- Measures the hits that need it -- added by hand ("DT"), or moved by
-- hand (a level with no stored hit) -- and locks them. A level set by
-- hand is kept; decay and confidence are measured. Also stores edits
-- (renamed levels) as locked. Gives how many were measured.
function DT.measure_manual(track, profile)
  local p = profile
  if type(p) ~= "table" then p = DT.load_profile("detect", p or DT.track_profile(track)) end
  local done = 0
  for _, tk in ipairs(DT.track_takes(track)) do
    local entries = take_hits(tk.take)
    local need, dirty = {}, false
    for _, e in ipairs(entries) do
      if e.hit.manual then need[#need + 1] = e end
      if e.hit.edited or e.hit.legacy then dirty = true end
    end
    if #need > 0 then
      local acc = r.CreateTakeAudioAccessor(tk.take)
      local sr, nch = take_format(tk.take)
      local buf
      for _, e in ipairs(need) do
        local h
        h, buf = measure(acc, sr, nch, src_to_item(tk, e.srcpos), p.thresh_db + 12, nil, p, buf)
        if h then
          e.hit = { db = e.hit.db or h.db, c = 1.0, dec = h.dec, tilt = h.tilt, locked = true }
          done = done + 1
        end
      end
      r.DestroyAudioAccessor(acc)
    end
    if #need > 0 or dirty then rewrite_take(tk.take, entries) end
  end
  if done > 0 then mark_source(track, true) end
  return done
end


-- ---------------------------------------------------------------------
-- the kit: bleed between its tracks
-- ---------------------------------------------------------------------
-- The kit's detected tracks (drums and bleed sources with a hit map),
-- as { track, name, role }. Second mics and references are left out:
-- a second mic hears its own drum louder than anything, and isn't
-- detected anyway.
function DT.kit_tracks()
  local out = {}
  for _, e in ipairs(DT.kit_roles()) do
    if (e.role == "drum" or e.role == "bleed") and DT.is_source(e.track) then
      out[#out + 1] = { track = e.track, name = e.name, role = e.role }
    end
  end
  return out
end

local function median(list)
  if #list == 0 then return nil end
  local c = {}
  for i, v in ipairs(list) do c[i] = v end
  table.sort(c)
  local m = (#c + 1) / 2
  return (c[math.floor(m)] + c[math.ceil(m)]) / 2
end

-- the hit on a sorted list nearest time t within w, or nil
local function coincident(list, t, w)
  local lo, hi = 1, #list
  while lo <= hi do
    local mid = (lo + hi) // 2
    if list[mid].proj < t then lo = mid + 1 else hi = mid - 1 end
  end
  local best, bd
  for i = math.max(1, hi), math.min(#list, lo) do
    local d = math.abs(list[i].proj - t)
    if d <= w and (not bd or d < bd) then best, bd = list[i], d end
  end
  return best
end

-- Discounts bleed on one track against the rest of the kit. A hit that
-- lands within kit_window_ms of a hit on another DrumToolbox track is
-- the same strike heard in two mics; it belongs to the track that hears
-- it louder (by more than kit_split_db), unless its tilt says otherwise:
-- if it sounds like this drum's own hits (their median tilt, learned
-- from the hits the level rule keeps) more than like the bleed
-- (the median tilt of the hits the level rule gives away; with too few
-- of those, within kit_tilt_db of its own), it stays -- a tom played
-- with the snare, say. Locked hits always stay.
-- Discounted hits leave the arrange view; they're kept in
-- P_EXT:TS_DT_bleed with the track they came from (DT.track_bleed).
-- Kept hits whose tilt is more than twice kit_tilt_db from this drum's
-- own turn amber (confidence under C_HI): they sound like something else.
-- opts: profile (as DT.detect), kit (list from DT.kit_tracks; default
-- every source). Gives { checked, discounted, from = { name = n },
-- kept_by_tilt, odd, own_tilt, bleed_tilt }.
function DT.kit_check(track, opts)
  opts = opts or {}
  local p = opts.profile
  if type(p) ~= "table" then p = DT.load_profile("detect", p or DT.track_profile(track)) end
  local rep = { checked = 0, discounted = 0, from = {}, kept_by_tilt = 0 }
  if p.kit_check == false then return rep end
  local w = (p.kit_window_ms or 3) / 1000
  local split = p.kit_split_db or 0

  local others = {}
  for _, k in ipairs(opts.kit or DT.kit_tracks()) do
    if k.track ~= track then others[#others + 1] = { name = k.name, hits = DT.track_hits(k.track) } end
  end
  local hits = DT.track_hits(track)
  rep.checked = #hits
  if #others == 0 or #hits == 0 then return rep end

  -- each hit's strongest coincidence, and the level verdict
  local own_t, bleed_t, own_db = {}, {}, {}
  for _, h in ipairs(hits) do
    local best
    for _, o in ipairs(others) do
      local c = coincident(o.hits, h.proj, w)
      if c and c.db and h.db and (not best or c.db > best.hit.db) then best = { hit = c, name = o.name } end
    end
    h._co = best
    if best then
      h._ratio = h.db - best.hit.db
      h._bleed = h._ratio < split
    end
    if h.tilt then
      if h._bleed then bleed_t[#bleed_t + 1] = h.tilt else own_t[#own_t + 1] = h.tilt end
    end
    if not h._bleed and h.db then own_db[#own_db + 1] = h.db end
  end
  -- tilt signatures (need a few of each to mean anything)
  local own_m = #own_t >= 3 and median(own_t) or nil
  local bleed_m = #bleed_t >= 3 and median(bleed_t) or nil
  rep.own_tilt, rep.bleed_tilt = own_m, bleed_m
  -- tone only tells them apart if the two sound different (a kick's
  -- bleed from a snare hit played with it can still sound like a kick);
  -- otherwise level does: a hit about as loud as this drum's own hits is
  -- one of them, real bleed is well under
  local tone_tells = own_m and bleed_m and math.abs(own_m - bleed_m) >= (p.kit_tilt_db or 6)
  local own_lvl = #own_db >= 3 and median(own_db) or nil
  rep.own_db, rep.tone_tells = own_lvl, tone_tells and true or false

  local by_take = {}
  for _, h in ipairs(hits) do
    if h._bleed and not h.locked then
      local own_like = false
      if own_m and bleed_m and not tone_tells then
        own_like = own_lvl ~= nil and h.db >= own_lvl - (p.kit_level_db or 6)
      elseif own_m and h.tilt then
        if bleed_m then own_like = math.abs(h.tilt - own_m) < math.abs(h.tilt - bleed_m)
        else own_like = math.abs(h.tilt - own_m) <= (p.kit_tilt_db or 6) end
      end
      if own_like then
        rep.kept_by_tilt = rep.kept_by_tilt + 1
      else
        local list = by_take[h.take] or {}
        by_take[h.take] = list
        list[#list + 1] = h
        rep.discounted = rep.discounted + 1
        rep.from[h._co.name] = (rep.from[h._co.name] or 0) + 1
      end
    end
  end

  -- kept hits that sound nothing like this drum: amber, for review
  local odd = {}
  if own_m then
    for _, h in ipairs(hits) do
      if not h.locked and h.tilt and math.abs(h.tilt - own_m) > 2 * (p.kit_tilt_db or 6) and (h.c or 1) >= DT.C_HI then
        local disc = false
        for _, g in ipairs(by_take[h.take] or {}) do if g == h then disc = true; break end end
        if not disc then odd[h] = true; rep.odd = (rep.odd or 0) + 1 end
      end
    end
  end
  for h in pairs(odd) do
    if not by_take[h.take] then by_take[h.take] = {} end
  end

  for take, list in pairs(by_take) do
    local gone = {}
    for _, h in ipairs(list) do gone[h.mk] = h end
    local oddmk = {}
    for h in pairs(odd) do if h.take == take then oddmk[h.mk] = true end end
    local keep, rec = {}, {}
    local ok, sv = r.GetSetMediaItemTakeInfo_String(take, DT.KEY_BLEED, "", false)
    for _, e in ipairs(ok and side_decode(sv) or {}) do
      rec[#rec + 1] = { srcpos = e.s, hit = { db = e.db, c = e.c, dec = e.dec, tilt = e.tilt, from = e.from } }
    end
    for _, e in ipairs(take_hits(take)) do
      local g = gone[e.idx]
      if g then
        rec[#rec + 1] = { srcpos = e.srcpos, hit = { db = g.db, c = g.c, dec = g.dec, tilt = g.tilt, from = g._co.name } }
      else
        if oddmk[e.idx] then e.hit.c = math.min(e.hit.c or 1, DT.C_HI - 0.05) end
        keep[#keep + 1] = e
      end
    end
    rewrite_take(take, keep)
    if #rec > 0 then
      table.sort(rec, function(a, b) return a.srcpos < b.srcpos end)
      r.GetSetMediaItemTakeInfo_String(take, DT.KEY_BLEED, side_encode(rec), true)
    end
  end
  if rep.discounted > 0 or rep.odd then r.UpdateArrange() end
  rep.odd = rep.odd or 0
  return rep
end

-- The hits discounted as bleed on a track, in time order:
-- { proj, take, srcpos, db, c, dec, tilt, from }.
function DT.track_bleed(track, opts)
  local out = {}
  for _, tk in ipairs(DT.track_takes(track, opts)) do
    local ok, sv = r.GetSetMediaItemTakeInfo_String(tk.take, DT.KEY_BLEED, "", false)
    for _, e in ipairs(ok and side_decode(sv) or {}) do
      local t = src_to_item(tk, e.s)
      if t >= 0 and t <= tk.len then
        out[#out + 1] = { proj = tk.pos + t, take = tk.take, srcpos = e.s, db = e.db, c = e.c, dec = e.dec, tilt = e.tilt, from = e.from }
      end
    end
  end
  table.sort(out, function(a, b) return a.proj < b.proj end)
  return out
end

-- Puts discounted hits back on the arrange view (all of a track's, or
-- those in `list` from DT.track_bleed), locked so the next check keeps
-- them. Gives how many came back.
function DT.restore_bleed(track, list)
  list = list or DT.track_bleed(track)
  local want = {}
  for _, b in ipairs(list) do
    want[b.take] = want[b.take] or {}
    want[b.take][string.format("%.6f", b.srcpos)] = b
  end
  local n = 0
  for take, set in pairs(want) do
    local ok, sv = r.GetSetMediaItemTakeInfo_String(take, DT.KEY_BLEED, "", false)
    local left = {}
    local entries = take_hits(take)
    for _, e in ipairs(ok and side_decode(sv) or {}) do
      local b = set[string.format("%.6f", e.s)]
      if b then
        entries[#entries + 1] = { srcpos = e.s, hit = { db = e.db, c = e.c, dec = e.dec, tilt = e.tilt, locked = true } }
        n = n + 1
      else
        left[#left + 1] = { srcpos = e.s, hit = { db = e.db, c = e.c, dec = e.dec, tilt = e.tilt, from = e.from } }
      end
    end
    rewrite_take(take, entries)
    r.GetSetMediaItemTakeInfo_String(take, DT.KEY_BLEED, #left > 0 and side_encode(left) or "", true)
  end
  return n
end

-- A bleed mark changed by hand: blamed on another drum (from = its name),
-- or dropped altogether (from = false: the record goes). Gives true if the
-- mark was found.
function DT.set_bleed(b, from)
  local ok, sv = r.GetSetMediaItemTakeInfo_String(b.take, DT.KEY_BLEED, "", false)
  local rec, found = {}, false
  for _, e in ipairs(ok and side_decode(sv) or {}) do
    if math.abs(e.s - b.srcpos) < 1e-6 then
      found = true
      if from then rec[#rec + 1] = { srcpos = e.s, hit = { db = e.db, c = e.c, dec = e.dec, tilt = e.tilt, from = from } } end
    else
      rec[#rec + 1] = { srcpos = e.s, hit = { db = e.db, c = e.c, dec = e.dec, tilt = e.tilt, from = e.from } }
    end
  end
  if found then r.GetSetMediaItemTakeInfo_String(b.take, DT.KEY_BLEED, #rec > 0 and side_encode(rec) or "", true) end
  return found
end

-- ---------------------------------------------------------------------
-- review: deciding on single hits (the lanes)
-- ---------------------------------------------------------------------
-- A hit needs review when its confidence is under C_HI and nobody has
-- locked it yet.
function DT.needs_review(h) return (h.c or 1) < DT.C_HI and not h.locked end

-- Keep & lock: the hit stays, as it is, and every later detection or kit
-- check keeps it.
function DT.lock_hit(hit)
  hit.locked = true
  DT.update_hit(hit)
end

-- Bleed from `from` (a track name): the marker goes, and the hit is
-- recorded with the track's discounted hits (restorable, like the kit
-- check's).
function DT.discount_hit(hit, from)
  local entries, gone = {}, nil
  for _, e in ipairs(take_hits(hit.take)) do
    if e.idx == hit.mk then gone = e else entries[#entries + 1] = e end
  end
  if not gone then return false end
  rewrite_take(hit.take, entries)
  local ok, sv = r.GetSetMediaItemTakeInfo_String(hit.take, DT.KEY_BLEED, "", false)
  local rec = {}
  for _, e in ipairs(ok and side_decode(sv) or {}) do
    rec[#rec + 1] = { srcpos = e.s, hit = { db = e.db, c = e.c, dec = e.dec, tilt = e.tilt, from = e.from } }
  end
  local g = gone.hit
  rec[#rec + 1] = { srcpos = gone.srcpos, hit = { db = g.db, c = g.c, dec = g.dec, tilt = g.tilt, from = from or "hand" } }
  table.sort(rec, function(a, b) return a.srcpos < b.srcpos end)
  r.GetSetMediaItemTakeInfo_String(hit.take, DT.KEY_BLEED, side_encode(rec), true)
  return true
end

-- Delete: the marker and its data go (a re-detection may find it again;
-- "Bleed from" keeps a record instead).
function DT.delete_hit(hit)
  local entries, found = {}, false
  for _, e in ipairs(take_hits(hit.take)) do
    if e.idx == hit.mk then found = true else entries[#entries + 1] = e end
  end
  if found then rewrite_take(hit.take, entries) end
  return found
end

-- Adds a hit by hand near project time `proj` on a track: the strike is
-- looked for within 35 ms either side (the strongest rise in the drum's
-- detection band, 15 dB under its threshold), then its onset and level
-- are measured as detection would. It's locked (a hand decision); a
-- bleed record at the same spot goes. Gives the hit's project time, or
-- nil and why.
function DT.add_hit(track, proj)
  for _, tk in ipairs(DT.track_takes(track)) do
    if proj >= tk.pos and proj < tk.pos + tk.len then
      local p = DT.load_profile("detect", DT.track_profile(track))
      local q = copy(p)
      q.thresh_db = (p.thresh_db or -40) - 15
      q.rise_db = math.max(2, (p.rise_db or 6) - 3)
      local acc = r.CreateTakeAudioAccessor(tk.take)
      local sr, nch = take_format(tk.take)
      local t = proj - tk.pos
      local best
      for _, c in ipairs(candidates(acc, sr, nch, math.max(0, t - 0.06), math.min(tk.len, t + 0.04), q)) do
        if math.abs(c.t - t) <= 0.035 and (not best or c.fdb > best.fdb) then best = c end
      end
      local h = measure(acc, sr, nch, best and best.t or t, q.thresh_db + 12, nil, p, nil, nil, best and best.rise_t)
      r.DestroyAudioAccessor(acc)
      local at = h and h.t or t
      local sp = item_to_src(tk, at)
      local entries = take_hits(tk.take)
      for _, e in ipairs(entries) do
        if math.abs(e.srcpos - sp) < 0.003 * tk.rate then return nil, "there's a hit there already" end
      end
      entries[#entries + 1] = { srcpos = sp, hit = { db = h and h.db, c = 1.0, dec = h and h.dec, tilt = h and h.tilt,
                                                     locked = true, manual = (not h) or nil } }
      rewrite_take(tk.take, entries)
      -- a bleed record at this spot goes
      local ok, sv = r.GetSetMediaItemTakeInfo_String(tk.take, DT.KEY_BLEED, "", false)
      local left, dropped = {}, false
      for _, e in ipairs(ok and side_decode(sv) or {}) do
        if math.abs(e.s - sp) < 0.003 * tk.rate then dropped = true
        else left[#left + 1] = { srcpos = e.s, hit = { db = e.db, c = e.c, dec = e.dec, tilt = e.tilt, from = e.from } } end
      end
      if dropped then r.GetSetMediaItemTakeInfo_String(tk.take, DT.KEY_BLEED, #left > 0 and side_encode(left) or "", true) end
      mark_source(track, true)
      return tk.pos + src_to_item(tk, sp)
    end
  end
  return nil, "no item there"
end

-- The waveform of a track between project times t0 and t1 at n columns:
-- hi[i], lo[i] (the peak over the column, every item and channel), from
-- REAPER's peak files. Columns outside every item are 0.
function DT.track_peaks(track, t0, t1, n)
  local hi, lo = {}, {}
  for i = 1, n do hi[i] = 0; lo[i] = 0 end
  if n < 1 or t1 <= t0 then return hi, lo end
  local dt = (t1 - t0) / n
  for i = 0, r.CountTrackMediaItems(track) - 1 do
    local it = r.GetTrackMediaItem(track, i)
    local pos = r.GetMediaItemInfo_Value(it, "D_POSITION")
    local len = r.GetMediaItemInfo_Value(it, "D_LENGTH")
    local tk = r.GetActiveTake(it)
    if tk and not r.TakeIsMIDI(tk) and pos < t1 and pos + len > t0 then
      local a = math.max(0, math.floor((pos - t0) / dt))
      local b = math.min(n, math.ceil((pos + len - t0) / dt))
      local cols = b - a
      if cols > 0 then
        local src = r.GetMediaItemTake_Source(tk)
        local nch = math.max(1, math.min(2, src and r.GetMediaSourceNumChannels(src) or 1))
        -- start time is project time; the minimums start at the count asked
        -- for, whatever comes back (REAPER leaves the gap unwritten)
        local buf = r.new_array(cols * nch * 2)
        buf.clear()
        local ret = r.GetMediaItemTake_Peaks(tk, 1 / dt, t0 + a * dt, nch, cols, 0, buf)
        local got = math.min(cols, math.floor(ret or 0) & 0xfffff)
        if got > 0 then
          local v = buf.table()
          local vol = 1
          for k = 0, got - 1 do
            local mx, mn = 0, 0
            for ch = 1, nch do
              local x1 = v[k * nch + ch] or 0
              local x2 = v[cols * nch + k * nch + ch] or 0
              if x1 > mx then mx = x1 end
              if x2 < mn then mn = x2 end
            end
            local col = a + k + 1
            if mx * vol > hi[col] then hi[col] = mx * vol end
            if mn * vol < lo[col] then lo[col] = mn * vol end
          end
        end
      end
    end
  end
  return hi, lo
end

-- The span the kit's items cover: t0, t1 (project time), or nil.
function DT.kit_span(kit)
  local t0, t1
  for _, e in ipairs(kit or DT.kit_roles()) do
    if e.role ~= "ignore" then
      for i = 0, r.CountTrackMediaItems(e.track) - 1 do
        local it = r.GetTrackMediaItem(e.track, i)
        local pos = r.GetMediaItemInfo_Value(it, "D_POSITION")
        local len = r.GetMediaItemInfo_Value(it, "D_LENGTH")
        if not t0 or pos < t0 then t0 = pos end
        if not t1 or pos + len > t1 then t1 = pos + len end
      end
    end
  end
  return t0, t1
end

--@pro TS_DT_Pro_Core.lua:1

--@pro TS_DT_Pro_Core.lua:2

-- ---------------------------------------------------------------------
-- alignment: the kit's mics, lined up on the strikes they share
-- ---------------------------------------------------------------------
-- DrumToolbox knows where every hit is, so it measures each mic against
-- its target only around those hits: short windows from just before each
-- strike, cross-correlated, the per-hit answers combined. That's the time
-- offset and polarity on the moments that matter, not averaged over long
-- stretches of bleed and silence.
--
-- The plan (DT.align_plan): one entry per kit track -
--   to    align to a target track, measured on the target drum's hits
--         (a second mic to its drum: Snare Bottom -> Snare Top, on snare
--         hits; overheads and room to the reference, on its hits)
--   with  move by the same amount as another track (the second overhead
--         moves with the first, so the pair's stereo image is untouched)
--   leave don't move
--   ref   the reference itself (default: Snare Top)
-- The plan is kept in the project (ExtState) once edited.
--
-- DT.align_job measures (in steps, like detection); DT.align_apply moves
-- either the items or their contents (start offset) and flips polarity
-- (take polarity). Take markers are in source time, so the hit map moves
-- with the audio either way.

-- the smallest move worth making: just over a sample at 48 kHz (anything
-- less is already aligned - and moving it would never settle)
DT.ALIGN_MIN_MS = 0.025

DT.ALIGN_DEFAULT = {
  max_ms = 50,          -- largest offset looked for (REAPER's own default)
  polarity = true,      -- allow flipping polarity
  pre_ms = 1,           -- window: from just before the strike
  win_ms = 15,          --   ... to this far after (waveforms)
  env_win_ms = 30,      -- envelopes, and the low band, look this far after
  low_hz = 250,         -- low band: mics that share only the low end (sub kick)
  max_hits = 48,        -- loudest confident hits used per track
  env_ms = 1,           -- envelope smoothing for the first (coarse) search
  min_r = 0.3,          -- per-hit correlation that counts
  weak_r = 0.2,         -- summed correlation under this, or
  keep_gain = 0.15,     -- moving must sum this much better than where it is now
  tie = 0.95,           -- a second offset this close to the best: ambiguous
  sum_pre_ms = 5,       -- summing windows: from this before each hit ...
  sum_win_ms = 60,      --   ... to this after
  weak_agree = 0.5,     -- fewer of the hits than this support the offset, or
  weak_n = 5,           -- fewer hits than this: flagged, not applied
}
local EXT = "TS_DrumToolbox"

-- the reference track: stored, else the drum using the Snare Top profile,
-- else the first drum
function DT.align_reference(kit)
  kit = kit or DT.kit_roles()
  local _, g = r.GetProjExtState(0, EXT, "align_ref")
  local t = track_by_guid(g)
  if t then return t end
  local first
  for _, e in ipairs(kit) do
    if e.role == "drum" then
      first = first or e.track
      if e.profile == "Snare Top" then return e.track end
    end
  end
  return first
end

function DT.set_align_reference(t)
  r.SetProjExtState(0, EXT, "align_ref", t and r.GetTrackGUID(t) or "")
end

local function is_overhead(name)
  local n = name:lower()
  return n:find("over%s*head") or n:find("%f[%w]ohs?%f[%W]") or n:find("%f[%w]oh%d") or n:find("%f[%w]ovh")
end

-- The default plan for a kit: { track, name, role, mode, target }.
function DT.align_defaults(kit)
  kit = kit or DT.kit_roles()
  local ref = DT.align_reference(kit)
  local plan, first_oh = {}, nil
  for _, e in ipairs(kit) do
    if e.role ~= "ignore" then
      local p = { track = e.track, name = e.name, role = e.role, mode = "leave" }
      if e.track == ref then p.mode = "ref"
      elseif e.role == "second" and e.of then p.mode, p.target = "to", e.of
      elseif e.role == "reference" then
        if is_overhead(e.name) then
          if first_oh then p.mode, p.target = "with", first_oh
          else first_oh = e.track; p.mode, p.target = "to", ref end
        else
          p.mode, p.target = "to", ref
        end
      end
      if p.mode == "to" and not p.target then p.mode = "leave" end
      plan[#plan + 1] = p
    end
  end
  return plan
end

-- The plan in use: the defaults, with any entries edited by hand (kept
-- in the project as "GUID=mode:targetGUID;...").
function DT.align_plan(kit)
  local plan = DT.align_defaults(kit)
  local _, sv = r.GetProjExtState(0, EXT, "align_plan")
  local saved = {}
  for g, m, tg in (sv or ""):gmatch("([^=;]+)=(%a+):([^;]*)") do saved[g] = { mode = m, target = track_by_guid(tg) } end
  for _, p in ipairs(plan) do
    local sv1 = saved[r.GetTrackGUID(p.track)]
    if sv1 and p.mode ~= "ref" then
      p.mode, p.target, p.user = sv1.mode, sv1.target, true
      if (p.mode == "to" or p.mode == "with") and not p.target then p.mode = "leave" end
    end
  end
  return plan
end

-- Sets one entry by hand (mode, target) and keeps it in the project.
function DT.set_align_entry(track, mode, target)
  local _, sv = r.GetProjExtState(0, EXT, "align_plan")
  local g = r.GetTrackGUID(track)
  local out = {}
  for e in (sv or ""):gmatch("[^;]+") do
    if e:sub(1, #g + 1) ~= g .. "=" then out[#out + 1] = e end
  end
  if mode then out[#out + 1] = g .. "=" .. mode .. ":" .. (target and r.GetTrackGUID(target) or "") end
  r.SetProjExtState(0, EXT, "align_plan", table.concat(out, ";"))
end

-- Reads n samples of a track (all its items, mono, before its FX) from
-- project time t at sample rate sr.
local function track_read(acc, sr, t, n, buf)
  local need = n
  if not buf or buf.size < need * 2 then buf = { arr = r.new_array(need * 2), size = need * 2 } end
  buf.arr.clear()
  r.GetAudioAccessorSamples(acc, sr, 2, t, n, buf.arr)
  local raw = buf.arr.table(1, need * 2)
  local out = {}
  for i = 1, n do out[i] = (raw[2 * i - 1] + raw[2 * i]) * 0.5 end
  return out, buf
end

-- The best lag (in samples, a shifted later by +lag) between a reference
-- window `x` (length nx) and a longer window `y` read `m` samples before
-- it, over lags -m..m (or lo..hi). Gives lag, signed normalised r.
local function xcorr(x, y, m, lo, hi, signed)
  local nx = #x
  local ex = 0
  for i = 1, nx do ex = ex + x[i] * x[i] end
  if ex <= 0 then return nil end
  local best, br, bl = -math.huge, 0, 0
  local rs = {}
  for lag = lo or -m, hi or m do
    local s, ey = 0, 0
    local off = m + lag
    for i = 1, nx do
      local v = y[i + off]
      if v then s = s + x[i] * v; ey = ey + v * v end
    end
    local rr = (ey > 0) and s / math.sqrt(ex * ey) or 0
    rs[lag] = rr
    local q = signed and rr or math.abs(rr)
    if q > best then best, br, bl = q, rr, lag end
  end
  -- sub-sample: a parabola through the peak and its neighbours
  local a, b, c = rs[bl - 1], rs[bl], rs[bl + 1]
  local frac = 0
  if a and c then
    if not signed then a, b, c = math.abs(a), math.abs(b), math.abs(c) end
    local d = a - 2 * b + c
    if d < 0 then frac = clamp(0.5 * (a - c) / d, -0.5, 0.5) end
  end
  return bl + frac, br
end
DT._xcorr = xcorr

local function weighted_median(vals, wts)
  local idx = {}
  for i = 1, #vals do idx[i] = i end
  table.sort(idx, function(a, b) return vals[a] < vals[b] end)
  local tot = 0
  for i = 1, #wts do tot = tot + wts[i] end
  local acc = 0
  for _, i in ipairs(idx) do
    acc = acc + wts[i]
    if acc >= tot / 2 then return vals[i] end
  end
  return vals[idx[#idx]]
end

local function envelope(v, dec, sm)
  local e = {}
  local nb = math.floor(#v / dec)
  for i = 1, nb do
    local s0 = 0
    for k = (i - 1) * dec + 1, i * dec do local a = v[k]; s0 = s0 + (a < 0 and -a or a) end
    e[i] = s0 / dec
  end
  local out, h = {}, math.floor(sm / 2)
  for i = 1, nb do
    local lo2, hi2 = math.max(1, i - h), math.min(nb, i + h)
    local s1 = 0
    for k = lo2, hi2 do s1 = s1 + e[k] end
    out[i] = s1 / (hi2 - lo2 + 1)
  end
  return out
end

local function demean(v)
  local m0 = 0
  for i = 1, #v do m0 = m0 + v[i] end
  m0 = m0 / math.max(1, #v)
  local out = {}
  for i = 1, #v do out[i] = v[i] - m0 end
  return out
end

-- two one-pole low-passes, forwards then backwards (no phase shift)
local function lowpass(v, fc, sr)
  local a = 1 - math.exp(-2 * math.pi * fc / sr)
  local out, z1, z2 = {}, v[1] or 0, v[1] or 0
  for i = 1, #v do z1 = z1 + a * (v[i] - z1); z2 = z2 + a * (z1 - z2); out[i] = z2 end
  z1, z2 = out[#out] or 0, out[#out] or 0
  for i = #out, 1, -1 do z1 = z1 + a * (out[i] - z1); z2 = z2 + a * (z1 - z2); out[i] = z2 end
  return out
end
DT._lowpass = lowpass

-- Envelope match: Pearson correlation at every lag (each lag's y window
-- demeaned on its own, via running sums), highest positive wins. x is
-- already demeaned. Returns lag (with sub-step), r.
local function env_xcorr(x, y, m)
  local nx = #x
  local ex = 0
  for i = 1, nx do ex = ex + x[i] * x[i] end
  if ex <= 0 then return nil end
  local cs, cq = { [0] = 0 }, { [0] = 0 }
  for i = 1, #y do cs[i] = cs[i - 1] + y[i]; cq[i] = cq[i - 1] + y[i] * y[i] end
  local best, bl, rs = -math.huge, 0, {}
  for lag = -m, m do
    local off = m + lag
    if off + nx <= #y then
      local sxy = 0
      for i = 1, nx do sxy = sxy + x[i] * y[i + off] end
      local sy, sq = cs[off + nx] - cs[off], cq[off + nx] - cq[off]
      local vy = sq - sy * sy / nx
      local rr = vy > 1e-20 and sxy / math.sqrt(ex * vy) or 0
      rs[lag] = rr
      if rr > best then best, bl = rr, lag end
    end
  end
  local a, b, c = rs[bl - 1], rs[bl], rs[bl + 1]
  local frac = 0
  if a and c then
    local d = a - 2 * b + c
    if d < 0 then frac = clamp(0.5 * (a - c) / d, -0.5, 0.5) end
  end
  return bl + frac, best
end

-- One hit, at 48 kHz. The target's window starts pre_ms before the
-- strike; the aligned track's is max_ms wider each side.
-- 1. coarse: loudness envelopes over env_win_ms, matched over +-max_ms on
--    the highest POSITIVE correlation (an envelope matching inverted is
--    not a match; a drum's body repeats, its envelope doesn't);
-- 2. fine: waveforms over win_ms, within a fraction of a ms of that, for
--    the exact offset and polarity; if they agree too little, both are
--    low-passed (low_hz) and compared over env_win_ms instead - mics that
--    share only the low end (a sub kick and a kick in).
-- Returns ms (aligned track later by), r (signed), coarse_ms, r1, band
-- ("full" / "low"), or nil.
function DT._align_hit(acc_t, acc_a, proj, o, bufs)
  local sr = 48000
  local m = o.max_ms / 1000
  local dec = o.max_ms > 20 and 8 or 4
  local pre = o.pre_ms / 1000
  local ewl = math.max(o.win_ms, o.env_win_ms or o.win_ms) / 1000
  local nx = math.floor((pre + ewl) * sr / dec) * dec
  local mm = math.floor(m * sr / dec) * dec
  local x; x, bufs.t = track_read(acc_t, sr, proj - pre, nx, bufs.t)
  local y; y, bufs.a = track_read(acc_a, sr, proj - pre - m, nx + 2 * mm, bufs.a)
  local sm = math.max(1, math.floor((o.env_ms or 1) / 1000 * sr / dec))
  local ex = demean(envelope(x, dec, sm))
  local lag1, r1 = env_xcorr(ex, envelope(y, dec, sm), mm // dec)
  if not lag1 or r1 < o.min_r then return nil end
  local centre = math.floor(lag1 * dec + 0.5)
  local span = math.floor(1.5 * dec + 0.00025 * sr)
  local lo, hi = math.max(-mm, centre - span), math.min(mm, centre + span)
  local nf = math.floor((o.pre_ms + o.win_ms) / 1000 * sr)
  local xf = {}
  for i = 1, math.min(nf, #x) do xf[i] = x[i] end
  local lag2, r2 = xcorr(xf, y, mm, lo, hi)
  local band = "full"
  if not lag2 or math.abs(r2) < (o.weak_r or 0.3) then
    local lag3, r3 = xcorr(lowpass(x, o.low_hz or 250, sr), lowpass(y, o.low_hz or 250, sr), mm, lo, hi)
    if lag3 and (not lag2 or math.abs(r3) > math.abs(r2)) then lag2, r2, band = lag3, r3, "low" end
  end
  if not lag2 or math.abs(r2) < o.min_r then return nil end
  return lag2 / sr * 1000, r2, lag1 * dec / sr * 1000, r1, band
end

-- ---------------------------------------------------------------------
-- Measuring one pair of mics on many hits (DT._align_pair).
--
-- Matching each hit's loudness shape finds several offsets per pair (a
-- snare's wires or a tom's ring peak later than the stick); the true
-- arrival is the earliest cluster. So:
--   1. coarse: the ATTACKS are matched (the rise of the envelope, not its
--      shape) - on the top end (> 1 kHz: stick, beater, where a drum's
--      body can't ripple the envelope), or for mics without one (a sub
--      kick) on a smoother full-band envelope - and the match curves of
--      every hit are ADDED before
--      choosing - one answer from all the evidence, not a vote; of the
--      peaks within 60% of the strongest, the EARLIEST wins;
--   2. fine: the waveforms, a fraction of a ms around it, again summed
--      over the hits, which gives the polarity too; if they agree too
--      little, the low end alone (mics sharing only that: a sub kick);
--   3. a mic can't hear a drum before that drum's own close mic: against
--      a close mic, lags earlier than -1 ms aren't looked at.
-- Usage: local P = DT._align_pair(o, close_mic); P:add(acc_t, acc_a,
-- proj) per hit (reads audio); P:solve() -> result table.

local ASR, ADEC = 48000, 8          -- 48 kHz; envelopes at 6 kHz
local A_PRE = 0.003                 -- windows start 3 ms before the strike
local A_ONSET = 0.008               -- attack: matched over 3 + 8 ms

-- the rising part of the envelope (positive slope over `k` steps)
local function attack(v, sm, k)
  local e = envelope(v, ADEC, sm)
  local d = {}
  for i = 1, #e do
    local q = e[i] - (e[i - k] or e[1])
    d[i] = q > 0 and q or 0
  end
  return d
end

local function highpass(v, fc)
  local l = DT._lowpass(v, fc, ASR)
  local out = {}
  for i = 1, #v do out[i] = v[i] - l[i] end
  return out
end
local A_HP = 1000                   -- top-end attacks: above this
local A_TOP_R = 0.25                -- top end used if its summed match beats this
local A_LOW_MIC = 0.01              -- under 1% of the energy above 1 kHz: a low-end mic

-- Pearson r of x (demeaned, length nx) against y[base + lag + i], for
-- every lag lo..hi; each lag's y window demeaned on its own.
local function pearson_curve(x, y, base, lo, hi, out)
  local nx = #x
  local ex = 0
  for i = 1, nx do ex = ex + x[i] * x[i] end
  if ex <= 0 then return nil end
  local cs, cq = { [0] = 0 }, { [0] = 0 }
  for i = 1, #y do cs[i] = cs[i - 1] + y[i]; cq[i] = cq[i - 1] + y[i] * y[i] end
  local bl, bv = nil, -math.huge
  for lag = lo, hi do
    local off = base + lag
    local rr = 0
    if off >= 0 and off + nx <= #y then
      local sxy = 0
      for i = 1, nx do sxy = sxy + x[i] * y[i + off] end
      local sy, sq = cs[off + nx] - cs[off], cq[off + nx] - cq[off]
      local vy = sq - sy * sy / nx
      rr = vy > 1e-20 and sxy / math.sqrt(ex * vy) or 0
    end
    out[lag] = (out[lag] or 0) + rr
    if rr > bv then bl, bv = lag, rr end
  end
  return bl, bv
end

-- normalised (signed) correlation of x[xo+1 .. xo+nx] with y shifted by
-- lag (y[base + xo + i + lag]), lags lo..hi, added into out
local function wave_curve(x, xo, nx, y, base, lo, hi, out)
  local ex = 0
  for i = 1, nx do local v = x[xo + i] or 0; ex = ex + v * v end
  if ex <= 0 then return nil end
  local bl, bv, br = nil, -1, 0
  for lag = lo, hi do
    local s, ey = 0, 0
    local off = base + xo + lag
    for i = 1, nx do
      local v = y[off + i]
      if v then s = s + (x[xo + i] or 0) * v; ey = ey + v * v end
    end
    local rr = ey > 0 and s / math.sqrt(ex * ey) or 0
    out[lag] = (out[lag] or 0) + rr
    if math.abs(rr) > bv then bl, bv, br = lag, math.abs(rr), rr end
  end
  return bl, br
end

-- peak of a summed curve (by value, or by |value| when absolute), with a
-- parabola for the sub-step
local function curve_peak(c, lo, hi, absolute)
  local bl, bv = nil, -math.huge
  for lag = lo, hi do
    local v = c[lag] or 0
    if absolute then v = math.abs(v) end
    if v > bv then bl, bv = lag, v end
  end
  if not bl then return nil end
  local function g(l) local v = c[l]; if v and absolute then v = math.abs(v) end; return v end
  local a, b, cc = g(bl - 1), g(bl), g(bl + 1)
  local frac = 0
  if a and cc then
    local d = a - 2 * b + cc
    if d < 0 then frac = clamp(0.5 * (a - cc) / d, -0.5, 0.5) end
  end
  return bl + frac, c[bl], bl
end

function DT._align_pair(o, close_mic)
  local P = { o = o, wins = {}, S1 = {}, S1f = {}, e_all = 0, e_top = 0 }
  local m = o.max_ms / 1000
  P.mm = math.floor(m * ASR / ADEC) * ADEC                  -- max lag, samples
  P.lo1 = -(P.mm // ADEC)
  if close_mic then P.lo1 = math.max(P.lo1, -math.ceil(0.001 * ASR / ADEC)) end
  P.hi1 = P.mm // ADEC
  P.ewl = math.max(o.win_ms, o.env_win_ms or o.win_ms) / 1000
  P.sm = math.max(1, math.floor(0.5 / 1000 * ASR / ADEC))   -- 0.5 ms smoothing

  -- pass 1, per hit: read both windows, add this hit's attack match
  function P:add(acc_t, acc_a, proj, bufs)
    bufs = bufs or {}
    local nx = math.floor((A_PRE + self.ewl) * ASR / ADEC) * ADEC
    local x; x, bufs.t = track_read(acc_t, ASR, proj - A_PRE, nx, bufs.t)
    local y; y, bufs.a = track_read(acc_a, ASR, proj - A_PRE - m, nx + 2 * self.mm, bufs.a)
    local na = math.floor((A_PRE + A_ONSET) * ASR / ADEC)
    local function head(a)
      local t = {}
      for i = 1, math.min(na, #a) do t[i] = a[i] end
      return demean(t)
    end
    local w = { x = x, y = y, curve = {}, curve_f = {} }
    -- top end: 0.5 ms smoothing, 0.33 ms slope
    local yh = highpass(y, A_HP)
    for i = 1, #y do self.e_all = self.e_all + y[i] * y[i]; self.e_top = self.e_top + yh[i] * yh[i] end
    w.peak = pearson_curve(head(attack(highpass(x, A_HP), self.sm, 2)),
      attack(yh, self.sm, 2), self.mm // ADEC, self.lo1, self.hi1, w.curve)
    -- full band: 3 ms smoothing (a 55 Hz kick's ripple), 1 ms slope
    local sf = math.max(1, math.floor(0.003 * ASR / ADEC))
    local kf = math.max(1, math.floor(0.001 * ASR / ADEC))
    w.peak_f = pearson_curve(head(attack(x, sf, kf)), attack(y, sf, kf), self.mm // ADEC, self.lo1, self.hi1, w.curve_f)
    if not w.peak and not w.peak_f then return false end
    for l, v in pairs(w.curve) do self.S1[l] = (self.S1[l] or 0) + v end
    for l, v in pairs(w.curve_f) do self.S1f[l] = (self.S1f[l] or 0) + v end
    self.wins[#self.wins + 1] = w
    return true
  end

  -- the coarse lag (in 6 kHz steps): the earliest summed peak within 60%
  -- of the strongest; also the strongest other peak, for the report
  function P:coarse()
    local lo, hi = self.lo1, self.hi1
    local function top(S)
      local b = -math.huge
      for l = lo, hi do if (S[l] or 0) > b then b = S[l] or 0 end end
      return b
    end
    local S, best = self.S1, top(self.S1)
    self.full = false
    -- a mic with next to no top end (a sub kick): its top-end attacks are
    -- only leakage and noise
    self.low_mic = self.e_all > 0 and self.e_top / self.e_all < A_LOW_MIC
    if self.low_mic then
      S, best, self.full = self.S1f, top(self.S1f), true
    elseif best / math.max(1, #self.wins) < A_TOP_R then
      local bf = top(self.S1f)
      if bf > best then S, best, self.full = self.S1f, bf, true end
    end
    if best <= 0 then return nil end
    local pk = {}
    for l = lo, hi do
      local v = S[l] or 0
      if v >= 0.6 * best and v >= (S[l - 1] or -math.huge) and v >= (S[l + 1] or -math.huge) then pk[#pk + 1] = l end
    end
    local L = pk[1]
    local alt, av = nil, -math.huge
    for l = lo, hi do
      local v = S[l] or 0
      if math.abs(l - L) * ADEC / ASR > 0.0015 and v > av and v >= (S[l - 1] or -math.huge) and v >= (S[l + 1] or -math.huge) then alt, av = l, v end
    end
    return L, best, alt, av
  end

  function P:solve()
    local o2, n = self.o, #self.wins
    local res = { n = n }
    if n == 0 then res.weak, res.why = true, "no clear match"; return res end
    local L, best, alt, av = self:coarse()
    if not L then res.weak, res.why = true, "no clear match"; return res end
    -- hits that support it: their own match there is at least half their best
    local agree = 0
    for _, w in ipairs(self.wins) do
      local c, pk = w.curve, w.peak
      if self.full then c, pk = w.curve_f, w.peak_f end
      local v, top = c[L] or 0, pk and c[pk] or 0
      if top > 0 and v >= 0.5 * top then agree = agree + 1 end
    end
    res.agree = agree / n
    res.coarse_ms = L * ADEC / ASR * 1000
    res.coarse_r = best / n
    res.coarse_full = self.full
    if alt and av > 0.6 * best then res.alt_ms = alt * ADEC / ASR * 1000 end
    -- fine: waveforms around the coarse lag, summed
    local centre = L * ADEC
    local span = math.floor(1.5 * ADEC + 0.00025 * ASR)
    -- a smooth (full-band) attack is only rough: a slow low end rises late
    if self.full then span = math.floor(0.004 * ASR) end
    local lo, hi = math.max(-self.mm, centre - span), math.min(self.mm, centre + span)
    if self.lo1 > -(self.mm // ADEC) then lo = math.max(lo, self.lo1 * ADEC) end
    local xo = math.floor((A_PRE - o2.pre_ms / 1000) * ASR)
    local nf = math.floor((o2.pre_ms + o2.win_ms) / 1000 * ASR)
    local nl = math.floor((o2.pre_ms / 1000 + self.ewl) * ASR)
    local S2, S3, lags2, lags3 = {}, {}, {}, {}
    for _, w in ipairs(self.wins) do
      local l2 = wave_curve(w.x, xo, nf, w.y, self.mm, lo, hi, S2)
      if l2 then lags2[#lags2 + 1] = l2 end
      local xl, yl = DT._lowpass(w.x, o2.low_hz or 250, ASR), DT._lowpass(w.y, o2.low_hz or 250, ASR)
      local l3 = wave_curve(xl, xo, nl, yl, self.mm, lo, hi, S3)
      if l3 then lags3[#lags3 + 1] = l3 end
    end
    local f2, v2 = curve_peak(S2, lo, hi, true)
    local f3, v3 = curve_peak(S3, lo, hi, true)
    local lag, v, lags = f2, v2, lags2
    if f3 and (self.low_mic or ((not f2 or math.abs(v2) / n < (o2.weak_r or 0.3)) and math.abs(v3) > math.abs(v2 or 0))) then
      lag, v, lags, res.low = f3, v3, lags3, true
    end
    if not lag then res.weak, res.why = true, "no clear match"; return res end
    res.ms = lag / ASR * 1000
    res.r = math.abs(v) / n
    res.flip = o2.polarity and v < 0 or false
    local dev = {}
    for i, l in ipairs(lags) do dev[i] = math.abs(l / ASR * 1000 - res.ms) end
    table.sort(dev)
    res.mad_ms = dev[math.floor((#dev + 1) / 2)] or 0
    if n < o2.weak_n then res.weak, res.why = true, "too few hits matched"
    elseif res.agree < (o2.weak_agree or 0.5) then res.weak, res.why = true, "the hits disagree on the offset"
    elseif res.r < o2.weak_r then res.weak, res.why = true, "the mics agree too little" end
    return res
  end

  return P
end

-- ---------------------------------------------------------------------
-- Summing match (DT._align_sum): what REAPER's own phase alignment does -
-- the offset (and polarity) at which the two tracks sum best - but only
-- over windows around the drum's hits (no cymbal wash or silence in the
-- vote). Each hit's window (sum_pre_ms before to sum_win_ms after) is
-- cross-correlated with the other track by FFT; the cross-spectra of all
-- hits are added and turned back once; the peak of |r| within +-max is
-- the answer, its sign the polarity.

local function fft(re, im, n, inv)
  local j = 1
  for i = 1, n do
    if i < j then re[i], re[j] = re[j], re[i]; im[i], im[j] = im[j], im[i] end
    local m = n >> 1
    while m >= 1 and j > m do j = j - m; m = m >> 1 end
    j = j + m
  end
  local len = 2
  while len <= n do
    local ang = (inv and 2 or -2) * math.pi / len
    local wr, wi = math.cos(ang), math.sin(ang)
    local half = len >> 1
    for s = 1, n, len do
      local cr, ci = 1, 0
      for k = 0, half - 1 do
        local a, b = s + k, s + k + half
        local tr = re[b] * cr - im[b] * ci
        local ti = re[b] * ci + im[b] * cr
        re[b], im[b] = re[a] - tr, im[a] - ti
        re[a], im[a] = re[a] + tr, im[a] + ti
        cr, ci = cr * wr - ci * wi, cr * wi + ci * wr
      end
    end
    len = len << 1
  end
  if inv then for i = 1, n do re[i] = re[i] / n; im[i] = im[i] / n end end
end
DT._fft = fft

function DT._align_sum(o, close_mic)
  local S = { o = o, n = 0, ex = 0, ey = 0 }
  local sr = 48000
  local pre = (o.sum_pre_ms or 5) / 1000
  local win = (o.sum_win_ms or 60) / 1000
  S.mm = math.floor(o.max_ms / 1000 * sr)
  S.nx = math.floor((pre + win) * sr)
  S.ny = S.nx + 2 * S.mm
  local N = 1
  while N < S.nx + S.ny do N = N << 1 end
  S.N = N
  S.cr, S.ci = {}, {}
  for i = 1, N do S.cr[i] = 0; S.ci[i] = 0 end
  S.lo = close_mic and math.max(-S.mm, -math.floor(0.001 * sr)) or -S.mm

  function S:add(acc_t, acc_a, proj, bufs)
    bufs = bufs or {}
    local x; x, bufs.t = track_read(acc_t, sr, proj - pre, self.nx, bufs.t)
    local y; y, bufs.a = track_read(acc_a, sr, proj - pre - o.max_ms / 1000, self.ny, bufs.a)
    local xr, xi, yr, yi = {}, {}, {}, {}
    local ex, ey = 0, 0
    for i = 1, self.N do
      local a, b = x[i] or 0, y[i] or 0
      xr[i], xi[i], yr[i], yi[i] = a, 0, b, 0
      ex = ex + a * a
    end
    for i = self.mm + 1, self.mm + self.nx do local b = y[i] or 0; ey = ey + b * b end
    if ex <= 0 or ey <= 0 then return false end
    fft(xr, xi, self.N); fft(yr, yi, self.N)
    -- each hit weighted equally: normalised by its own energies
    local g = 1 / math.sqrt(ex * ey)
    for i = 1, self.N do
      -- conj(X) * Y
      self.cr[i] = self.cr[i] + g * (xr[i] * yr[i] + xi[i] * yi[i])
      self.ci[i] = self.ci[i] + g * (xr[i] * yi[i] - xi[i] * yr[i])
    end
    self.n = self.n + 1
    return true
  end

  -- -> { ms, r, flip, n, alt_ms }
  function S:solve()
    local res = { n = self.n }
    if self.n == 0 then res.weak, res.why = true, "no clear match"; return res end
    local re, im = {}, {}
    for i = 1, self.N do re[i], im[i] = self.cr[i], self.ci[i] end
    fft(re, im, self.N, true)
    -- re[k + 1] = sum x[i] y[i + k]; lag L (y later by L) is k = mm + L
    local c = {}
    for L = self.lo, self.mm do c[L] = re[self.mm + L + 1] / self.n end
    local bl, bv = nil, -1
    for L = self.lo, self.mm do local v = math.abs(c[L]); if v > bv then bl, bv = L, v end end
    local a, b, cc = c[bl - 1] and math.abs(c[bl - 1]), bv, c[bl + 1] and math.abs(c[bl + 1])
    local frac = 0
    if a and cc then local d = a - 2 * b + cc; if d < 0 then frac = clamp(0.5 * (a - cc) / d, -0.5, 0.5) end end
    res.ms = (bl + frac) / sr * 1000
    res.r = bv
    res.flip = o.polarity and c[bl] < 0 or false
    -- the best other candidate (a different peak, more than 1 ms away)
    local al, av = nil, -1
    for L = self.lo + 1, self.mm - 1 do
      local v = math.abs(c[L])
      if math.abs(L - bl) > 0.001 * sr and v > av and v >= math.abs(c[L - 1]) and v >= math.abs(c[L + 1]) then al, av = L, v end
    end
    if al and av > 0.8 * bv then res.alt_ms = al / sr * 1000; res.alt_r = av; res.alt_flip = o.polarity and c[al] < 0 or false end
    -- where it is now: the positive peak within +-0.5 ms of 0 (REAPER's
    -- "Already maximized" when nothing beats it clearly)
    local h = math.floor(0.0005 * sr)
    local kl, kv = nil, 0
    for L = math.max(self.lo, -h), math.min(self.mm, h) do if c[L] > kv then kl, kv = L, c[L] end end
    res.now_r = kv
    res.now_ms = kl and kl / sr * 1000 or nil
    res.gain = kv > 0 and bv / kv - 1 or math.huge
    if kl and res.gain < (o.keep_gain or 0.15) then res.keep = true end
    res.curve = c
    return res
  end
  return S
end


--@pro TS_DT_Pro_Core.lua:3

-- the hits a measurement uses: the target drum's own (or the
-- reference's), confident, loudest first
local function align_hits(track, opts)
  local src = DT.source_of(track)
  local hits = src and DT.track_hits(src) or {}
  local list = {}
  for _, h in ipairs(hits) do if (h.c or 1) >= DT.C_HI and h.db then list[#list + 1] = h end end
  table.sort(list, function(a, b) return a.db > b.db end)
  local out = {}
  for i = 1, math.min(#list, opts.max_hits) do out[i] = list[i] end
  table.sort(out, function(a, b) return a.proj < b.proj end)
  return out, src
end

-- A measuring job over a plan: job:step(budget) until true; job.results
-- = { [track] = { ms, flip, r, n, mad_ms, weak, why, from (hits' track) } }
-- for every "to" entry; "with" entries are resolved at apply time.
function DT.align_job(plan, opts)
  local o = copy(DT.ALIGN_DEFAULT)
  for k, v in pairs(opts or {}) do o[k] = v end
  local todo = {}
  for _, p in ipairs(plan) do if p.mode == "to" and p.target then todo[#todo + 1] = p end end
  local job = { plan = plan, o = o, todo = todo, i = 0, results = {}, progress = 0, label = "" }

  local function begin(j)
    local p = j.todo[j.i]
    -- the hits it's measured on: the target drum's (Snare Bottom -> Snare
    -- Top: the snare); if the target isn't a drum's mic (an overhead), the
    -- aligned track's own drum's (Rack Tom -> Overhead L: the tom); else
    -- the reference's
    local hits, src = align_hits(p.target, o)
    if not src then hits, src = align_hits(p.track, o) end
    if not src then hits, src = align_hits(DT.align_reference(), o) end
    j.cur = { p = p, hits = hits, src = src, k = 0, bufs = {},
              -- no "can't arrive before the close mic" floor here: tracks
              -- may already have been moved (e.g. by REAPER's aligner)
              S = DT._align_sum(o, false),
              acc_a = r.CreateTrackAudioAccessor(p.track), acc_t = r.CreateTrackAudioAccessor(p.target) }
    local _, sn = r.GetTrackName(src or p.target)
    j.cur.src_name = sn
  end

  -- the summing match (REAPER's criterion, on the drum's hits); kept
  -- where it is unless moving clearly sums better; two offsets that fit
  -- about equally are not chosen between
  local function close(j)
    local c = j.cur
    if c.acc_a then r.DestroyAudioAccessor(c.acc_a) end
    if c.acc_t then r.DestroyAudioAccessor(c.acc_t) end
    local s0 = c.S:solve()
    local res = { n = s0.n, from = c.src_name, r = s0.r, gain = s0.gain, best_ms = s0.ms, best_flip = s0.flip }
    if #c.hits == 0 then res.weak, res.why = true, "no hits to measure on"
    elseif not s0.ms then res.weak, res.why = true, "no clear match"
    elseif s0.n < o.weak_n then res.weak, res.why = true, "too few hits matched"
    elseif s0.keep and not (not s0.flip and math.abs(s0.ms) <= 1) then
      -- a different peak that doesn't sum clearly better: stay
      res.ms, res.flip, res.keep, res.r = 0, false, true, s0.now_r
    elseif s0.keep then
      -- the same peak, just refined (if it's worth moving at all)
      local fine = math.abs(s0.ms) >= DT.ALIGN_MIN_MS
      res.ms, res.flip, res.keep, res.refined = fine and s0.ms or 0, false, true, fine
    elseif s0.r < o.weak_r then res.weak, res.why = true, "the mics agree too little"
    elseif s0.alt_r and s0.alt_r >= (o.tie or 0.95) * s0.r then
      -- two offsets fit about equally: the smaller move
      local a_ms, a_flip = s0.ms, s0.flip
      if math.abs(s0.alt_ms) < math.abs(s0.ms) then a_ms, a_flip = s0.alt_ms, s0.alt_flip end
      res.ms, res.flip, res.tie = a_ms, a_flip, true
      res.alt_ms = (a_ms == s0.ms) and s0.alt_ms or s0.ms
    else
      res.ms, res.flip = s0.ms, s0.flip
      if s0.alt_r and s0.alt_r > 0.8 * s0.r then res.alt_ms = s0.alt_ms end
    end
    j.results[c.p.track] = res
    j.cur = nil
  end

  local function one(j, h)
    local c = j.cur
    c.S:add(c.acc_t, c.acc_a, h.proj, c.bufs)
  end

  local function run(j, budget)
    local stop = r.time_precise() + (budget or 0.02)
    repeat
      if not j.cur then
        j.i = j.i + 1
        if not j.todo[j.i] then j.progress, j.label = 1, "done"; return true end
        begin(j)
      end
      local c = j.cur
      c.k = c.k + 1
      local h = c.hits[c.k]
      if h then one(j, h) else close(j) end
      local nt = math.max(1, #j.todo)
      j.progress = ((j.i - 1) + (c and #c.hits > 0 and math.min(1, c.k / #c.hits) or 1)) / nt
      j.label = j.todo[j.i] and j.todo[j.i].name or ""
    until r.time_precise() >= stop
    return false
  end

  function job:step(budget)
    if self.progress >= 1 and not self.cur and self.i > #self.todo then return true end
    local ok, done = pcall(run, self, budget)
    if not ok then
      self.error = tostring(done)
      if self.cur then
        if self.cur.acc_a then r.DestroyAudioAccessor(self.cur.acc_a) end
        if self.cur.acc_t then r.DestroyAudioAccessor(self.cur.acc_t) end
        self.cur = nil
      end
      return true
    end
    return done
  end

  function job:cancel()
    if self.cur then
      if self.cur.acc_a then r.DestroyAudioAccessor(self.cur.acc_a) end
      if self.cur.acc_t then r.DestroyAudioAccessor(self.cur.acc_t) end
      self.cur = nil
    end
    self.i = #self.todo + 1
  end

  return job
end

-- What applying would do, per track: { track, name, shift_ms, flip, weak,
-- why, via } - "to" entries from their measurement (a shift that undoes
-- the measured lag), "with" entries copy their partner's (chains are
-- followed). The measured lag is relative to where the target is now;
-- when a target is itself moved, its shift is added (so a second mic of
-- a drum that moves comes along).
function DT.align_outcome(plan, results)
  local by = {}
  for _, p in ipairs(plan) do by[p.track] = p end
  local memo, out = {}, {}
  local function shift_of(track, depth)
    if memo[track] then return memo[track] end
    depth = depth or 0
    local p = by[track]
    local o = { shift_ms = 0, flip = false }
    if p and depth < 8 then
      if p.mode == "to" then
        local res = results[track]
        if res and res.ms and not res.weak then
          local tgt = shift_of(p.target, depth + 1)
          o.shift_ms = -res.ms + tgt.shift_ms
          o.flip = res.flip ~= tgt.flip
        elseif res then
          o.weak, o.why = true, res.why
        end
      elseif p.mode == "with" then
        local tgt = shift_of(p.target, depth + 1)
        o.shift_ms, o.flip, o.weak, o.why = tgt.shift_ms, tgt.flip, tgt.weak, tgt.why
      end
    end
    memo[track] = o
    return o
  end
  for _, p in ipairs(plan) do
    local o = shift_of(p.track)
    out[#out + 1] = { track = p.track, name = p.name, mode = p.mode, shift_ms = o.shift_ms, flip = o.flip,
                      weak = o.weak, why = o.why, result = results[p.track] }
  end
  return out
end

-- Applies an outcome. how = "items" (move the items) or "contents" (move
-- the audio inside them: start offset). An item that would move before
-- the project start stays at 0 and its audio moves inside it instead. Weak entries and zero moves are
-- skipped. Gives the list actually applied. Wrap in an undo block.
function DT.align_apply(outcome, how)
  local done = {}
  for _, o in ipairs(outcome) do
    local s = (o.shift_ms or 0) / 1000
    local move = math.abs(o.shift_ms or 0) >= DT.ALIGN_MIN_MS
    if not o.weak and (move or o.flip) then
      for i = 0, r.CountTrackMediaItems(o.track) - 1 do
        local it = r.GetTrackMediaItem(o.track, i)
        if move then
          if how == "contents" then
            for ti = 0, r.CountTakes(it) - 1 do
              local tk = r.GetTake(it, ti)
              if tk then
                local rate = r.GetMediaItemTakeInfo_Value(tk, "D_PLAYRATE")
                r.SetMediaItemTakeInfo_Value(tk, "D_STARTOFFS", r.GetMediaItemTakeInfo_Value(tk, "D_STARTOFFS") - s * rate)
              end
            end
          else
            local np = r.GetMediaItemInfo_Value(it, "D_POSITION") + s
            if np < 0 then
              -- can't go before the project start: the item stays at 0
              -- and its audio moves inside it by the rest
              for ti = 0, r.CountTakes(it) - 1 do
                local tk = r.GetTake(it, ti)
                if tk then
                  local rate = r.GetMediaItemTakeInfo_Value(tk, "D_PLAYRATE")
                  r.SetMediaItemTakeInfo_Value(tk, "D_STARTOFFS", r.GetMediaItemTakeInfo_Value(tk, "D_STARTOFFS") - np * rate)
                end
              end
              r.SetMediaItemInfo_Value(it, "D_LENGTH", math.max(0.001, r.GetMediaItemInfo_Value(it, "D_LENGTH") + np))
              np = 0
            end
            r.SetMediaItemInfo_Value(it, "D_POSITION", np)
          end
        end
        if o.flip then
          for ti = 0, r.CountTakes(it) - 1 do
            local tk = r.GetTake(it, ti)
            if tk then r.SetMediaItemTakeInfo_Value(tk, "B_PHASE", 1 - r.GetMediaItemTakeInfo_Value(tk, "B_PHASE")) end
          end
        end
      end
      done[#done + 1] = o
    end
  end
  r.UpdateArrange()
  return done
end

--@pro TS_DT_Pro_Core.lua:4

-- ---- Quantise: slice and move, the whole kit together ------------------
-- Slice and move (no stretching), the cuts from the chosen drums.
-- Every kit track is cut at the same points (pre_ms before each hit, so the
-- transient sits whole in its slice) and each slice moves by its hit's
-- move: phase between the mics stays as Align left it. A slice that moves
-- later than the one before leaves a gap: the one before is lengthened to
-- meet it; one that moves earlier overlaps it: the one before is shortened.
-- Every join gets a crossfade of xfade_ms (ending pre_ms - xfade_ms before
-- the transient). Hits further than `window` (% of half a grid step) from
-- the grid are cut but not moved: a deliberate push or a fill stays put.
DT.QUANT_DEFAULT = { v = 2, snap = true, div = 0.25, triplet = false, strength = 100, window = 100, pre_ms = 5, xfade_ms = 3, merge_ms = 30, smart = true,
                     from = { kick = true, snare = true } }

function DT.quant_opts()
  local _, v = r.GetProjExtState(0, "TS_DrumToolbox", "quant")
  local o = DT.deserialize(v) or {}
  -- options v1 -> v2: the window defaults to 100% (line matching keeps
  -- other subdivisions out)
  if (o.v or 1) < 2 then o.window = nil; o.v = 2 end
  for k, d in pairs(DT.QUANT_DEFAULT) do
    if o[k] == nil then
      if type(d) == "table" then o[k] = {}; for a, b in pairs(d) do o[k][a] = b end else o[k] = d end
    end
  end
  return o
end
function DT.quant_set_opts(o) r.SetProjExtState(0, "TS_DrumToolbox", "quant", ser(o)) end

-- which kind of drum a kit entry is, for "from"
function DT.quant_kind(e)
  local p = (e.profile or e.name or ""):lower()
  return p:find("kick") and "kick" or p:find("snare") and "snare" or p:find("tom") and "toms" or p:find("hat") and "hat" or "other"
end

-- the grid step in quarter notes
function DT.quant_step(o) return o.triplet and o.div * 2 / 3 or o.div end

-- Which line is a hit playing? The nearest
-- of the straight 16ths, the 8th triplets (and the chosen grid itself, if
-- it's finer). It's quantised only if that line is on the chosen grid: a
-- 16th offbeat stays a 16th offbeat when the grid is 1/4.
function DT.quant_line(q, step)
  local best, bd
  local function try(unit)
    local l = math.floor(q / unit + 0.5) * unit
    local d = math.abs(q - l)
    if not bd or d < bd - 1e-9 then best, bd = l, d end
  end
  try(step)                       -- first: a tie goes to the grid
  try(0.25); try(1 / 3)
  if step < 0.25 then try(step) end
  local k = best / step
  return best, math.abs(k - math.floor(k + 0.5)) < 1e-6
end

-- The cut points: { hit, cut, target, move, dev (s), frac (of half a
-- step), moves } from the chosen drums' hits (confident or locked), merged
-- within merge_ms (a flam: the first), within [from, to] if given.
-- a cut point's key for manual choices: its hit's time
function DT.quant_key(t) return string.format("%.4f", t) end

-- Manual choices, kept in the
-- project until the next Quantise: { [key] = { target = t } | { stay = true } }
function DT.quant_over()
  local _, v = r.GetProjExtState(0, "TS_DrumToolbox", "quant_over")
  return DT.deserialize(v) or {}
end
function DT.quant_set_over(over) r.SetProjExtState(0, "TS_DrumToolbox", "quant_over", next(over) and ser(over) or "") end

function DT.quant_points(kit, o, from, to, over)
  local hits = {}
  for _, e in ipairs(kit) do
    if e.role == "drum" and e.hitlist and o.from[DT.quant_kind(e)] then
      for _, h in ipairs(e.hitlist) do
        if (h.locked or (h.c or 1) >= 0.6) and (not from or (h.proj >= from and h.proj <= to)) then
          hits[#hits + 1] = { proj = h.proj, name = e.name }
        end
      end
    end
  end
  table.sort(hits, function(a, b) return a.proj < b.proj end)
  local step = DT.quant_step(o)
  local pts, last = {}, nil
  for _, h in ipairs(hits) do
    if not last or h.proj - last > o.merge_ms / 1000 then
      local q = r.TimeMap2_timeToQN(0, h.proj)
      local g = math.floor(q / step + 0.5) * step
      local gt = r.TimeMap2_QNToTime(0, g)
      local frac = math.abs(q - g) / (step / 2)
      local other = false
      if o.smart then local _, on = DT.quant_line(q, step); other = not on end
      local moves = not other and frac <= o.window / 100
      local move = moves and (gt - h.proj) * o.strength / 100 or 0
      local ov = over and over[DT.quant_key(h.proj)]
      local manual = false
      if ov then
        manual = true
        if ov.stay then moves, move = false, 0
        elseif ov.target then moves, move = true, ov.target - h.proj end
      end
      pts[#pts + 1] = { hit = h.proj, cut = h.proj - o.pre_ms / 1000, target = h.proj + move, move = move,
                        dev = h.proj - gt, frac = frac, moves = moves, other = other, manual = manual, name = h.name }
      last = h.proj
    end
  end
  return pts
end

-- the tracks that move: every track in the kit but the ignored
function DT.quant_tracks(kit)
  local out = {}
  for _, e in ipairs(kit) do if e.role ~= "ignore" then out[#out + 1] = e.track end end
  return out
end

-- One hit moved by hand: the kit is
-- cut before it and before the next cut point (the next hit of the drums
-- quantise cuts from, or any drum if none), the slice between moves, the
-- joins either side crossfade. Gives slices moved, gaps.
function DT.quant_move_one(kit, o, hit, target)
  local from_kinds = o.from or {}
  local nxt
  for pass = 1, 2 do
    for _, e in ipairs(kit) do
      if e.role == "drum" and e.hitlist and (pass == 2 or from_kinds[DT.quant_kind(e)]) then
        for _, h in ipairs(e.hitlist) do
          if h.proj > hit + o.merge_ms / 1000 and (not nxt or h.proj < nxt) then nxt = h.proj end
        end
      end
    end
    if nxt then break end
  end
  local pts = { { hit = hit, cut = hit - o.pre_ms / 1000, move = target - hit, moves = true } }
  if nxt then pts[2] = { hit = nxt, cut = nxt - o.pre_ms / 1000, move = 0, moves = false } end
  return DT.quant_apply(DT.quant_tracks(kit), pts, o)
end

-- Cut and move. Gives the number of slices moved and of gaps left (only
-- where a moved slice had no earlier audio to reach back into).
function DT.quant_apply(tracks, pts, o)
  if #pts == 0 then return 0 end
  local xf = o.xfade_ms / 1000
  local cuts = {}
  for i, p in ipairs(pts) do cuts[i] = p.cut end
  local function slice_of(t)               -- which cut a slice starting at t follows
    local lo, hi, k = 1, #cuts, 0
    while lo <= hi do
      local m = (lo + hi) // 2
      if cuts[m] <= t + 1e-7 then k = m; lo = m + 1 else hi = m - 1 end
    end
    return k
  end
  local moved, gaps = 0, 0
  for _, tr in ipairs(tracks) do
    -- cut, right to left
    for ci = #cuts, 1, -1 do
      local c = cuts[ci]
      for ii = r.CountTrackMediaItems(tr) - 1, 0, -1 do
        local it = r.GetTrackMediaItem(tr, ii)
        local pos = r.GetMediaItemInfo_Value(it, "D_POSITION")
        local len = r.GetMediaItemInfo_Value(it, "D_LENGTH")
        if c > pos + 1e-6 and c < pos + len - 1e-6 then r.SplitMediaItem(it, c) end
      end
    end
    -- the slices, in order, each with its move
    local sl = {}
    for ii = 0, r.CountTrackMediaItems(tr) - 1 do
      local it = r.GetTrackMediaItem(tr, ii)
      local pos = r.GetMediaItemInfo_Value(it, "D_POSITION")
      local len = r.GetMediaItemInfo_Value(it, "D_LENGTH")
      local k = slice_of(pos)
      sl[#sl + 1] = { it = it, pos = pos, len = len, k = k, move = k > 0 and pts[k].move or 0 }
    end
    table.sort(sl, function(a, b) return a.pos < b.pos end)
    for _, x in ipairs(sl) do
      if x.move ~= 0 then r.SetMediaItemInfo_Value(x.it, "D_POSITION", x.pos + x.move); moved = moved + 1 end
    end
    -- joins: where two slices met at a cut, the earlier one now reaches
    -- xfade past the later one's new start; both fade over it
    for i = 2, #sl do
      local a, b = sl[i - 1], sl[i]
      if b.k > 0 and math.abs(a.pos + a.len - b.pos) < 1e-6 and math.abs(b.pos - cuts[b.k]) < 1e-6 then
        -- where they are now (a may have reached back already)
        local a_new = r.GetMediaItemInfo_Value(a.it, "D_POSITION")
        local b_new = r.GetMediaItemInfo_Value(b.it, "D_POSITION")
        -- what's past a's end in the recording is b's lead-in, then b's
        -- transient: a reaches at most 1 ms short of it (else it plays
        -- twice); a gap past that stays, just before a hit (masked by it)
        local cap = r.GetMediaItemInfo_Value(a.it, "D_LENGTH") + math.max(0, o.pre_ms - 1) / 1000
        local want = b_new + xf - a_new
        local newlen = math.max(0.001, math.min(want, cap))
        r.SetMediaItemInfo_Value(a.it, "D_LENGTH", newlen)
        r.SetMediaItemInfo_Value(a.it, "D_FADEOUTLEN", math.min(xf, newlen))
        r.SetMediaItemInfo_Value(b.it, "D_FADEINLEN", xf)
        if want > cap then
          -- b moved later than a can follow: b reaches back into its own
          -- earlier audio (the tail before its hit - no transient there)
          -- to meet a, rather than leave a hole
          local s0 = a_new + newlen - xf
          local back = b_new - s0
          local tk = r.GetActiveTake(b.it)
          local offs = tk and r.GetMediaItemTakeInfo_Value(tk, "D_STARTOFFS") or 0
          if tk and back > 0 and offs - back >= 0 then
            r.SetMediaItemTakeInfo_Value(tk, "D_STARTOFFS", offs - back)
            r.SetMediaItemInfo_Value(b.it, "D_POSITION", s0)
            r.SetMediaItemInfo_Value(b.it, "D_LENGTH", r.GetMediaItemInfo_Value(b.it, "D_LENGTH") + back)
          else
            gaps = gaps + 1
          end
        end
        r.SetMediaItemInfo_Value(a.it, "C_FADEOUTSHAPE", 1)   -- equal power
        r.SetMediaItemInfo_Value(b.it, "C_FADEINSHAPE", 1)
      end
    end
  end
  r.UpdateArrange()
  return moved, gaps
end

-- exposed for tests
DT._candidates, DT._measure, DT._take_hits = candidates, measure, take_hits

return DT
