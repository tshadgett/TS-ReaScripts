-- @noindex
-- Not a package of its own: installed by TS_ChannelView.lua's @provides.
--[[
  TS_CV_Presets.lua -- REAPER's own plugin presets: list, load, save,
  save as default, rename, delete. Nothing in here draws; the panel's preset
  bar (TS_CV_PresetUI) and the web bridge both use it.

  REAPER's API loads presets (TrackFX_SetPreset, _NavigatePresets,
  _SetPresetByIndex) but has no call to save, rename or delete one. So this
  edits the same files REAPER does, in the same format -- checked byte for
  byte against REAPER's own saves (dev/TS_CV_PresetProbe.lua) for VST2,
  VST3 and JS, and REAPER picks the change up straight away:

    presets/<plugin>.ini        a plugin's user presets, the file REAPER
                                names (TrackFX_GetUserPresetFilename):
                                  [General]  NbPresets=N
                                  [PresetN]  Data=, Data_1= ... Len= Name=
                                Data is the plugin's saved state -- exactly
                                what the project keeps in its <VST>/<JS>
                                block -- in pieces of 16384 bytes, each in
                                hex with a check byte after it (the piece's
                                bytes summed, mod 256). Len is the state's
                                length without the check bytes.
    presets/<plugin>-builtin.ini  REAPER's list of the plugin's own
                                (factory) preset names.
    reaper-defpresets.ini       which user preset is each plugin's default:
                                  vst-reacomp=Name, vst-x.vst3=Name,
                                  js-guitar/flanger=Name

  Saving is offered for VST2/VST3 and JS, the formats that were checked;
  other formats list and load presets but don't save. Rename and delete only
  touch names and sections, so they work for any plugin with a preset file.
--]]

local PR = {}

local NL = (package.config:sub(1, 1) == "\\") and "\r\n" or "\n"

-- ---------------------------------------------------------------------
-- files
-- ---------------------------------------------------------------------
local function read(p)
  local f = p and io.open(p, "rb")
  if not f then return nil end
  local s = f:read("a"); f:close()
  return s
end

local function write(p, s)
  local f = io.open(p, "wb")
  if not f then return false end
  f:write(s); f:close()
  return true
end

local function hex(s)
  return (s:gsub(".", function(c) return string.format("%02X", c:byte()) end))
end

-- base64, one chunk line at a time (REAPER encodes each line separately)
local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local DEC = {}
for i = 1, 64 do DEC[B64:byte(i)] = i - 1 end
local function b64dec(s)
  local out, bits, nb = {}, 0, 0
  for i = 1, #s do
    local v = DEC[s:byte(i)]
    if v then
      bits = ((bits << 6) | v) & 0xffffff
      nb = nb + 6
      if nb >= 8 then
        nb = nb - 8
        out[#out + 1] = string.char((bits >> nb) & 0xff)
      end
    end
  end
  return table.concat(out)
end

-- A preset's Data lines: 16384-byte pieces, each in hex plus its check byte.
function PR.data_lines(blob)
  local out, n = {}, 0
  for i = 1, math.max(1, #blob), 16384 do
    local part = blob:sub(i, i + 16383)
    local sum = 0
    for k = 1, #part do sum = sum + part:byte(k) end
    out[#out + 1] = ((n == 0) and "Data=" or ("Data_" .. n .. "="))
      .. hex(part) .. string.format("%02X", sum % 256)
    n = n + 1
  end
  return out
end

-- A preset file, parsed: { general = { lines }, presets = { {name, len,
-- data = { lines }} } }, in file order.
function PR.parse(text)
  local doc = { general = {}, presets = {} }
  local cur = nil
  for line in ((text or "") .. "\n"):gmatch("([^\r\n]*)\r?\n") do
    local sect = line:match("^%[(.-)%]$")
    if sect then
      if sect:match("^Preset%d+$") then
        cur = { data = {}, n = tonumber(sect:match("%d+")) }
        doc.presets[#doc.presets + 1] = cur
      else
        cur = "general"
      end
    elseif line ~= "" then
      if cur == "general" then
        if not line:match("^NbPresets=") then doc.general[#doc.general + 1] = line end
      elseif cur then
        if line:match("^Data[_%d]*=") then cur.data[#cur.data + 1] = line
        elseif line:match("^Len=") then cur.len = tonumber(line:match("=(%d+)"))
        elseif line:match("^Name=") then cur.name = line:sub(6)
        else cur.extra = cur.extra or {}; cur.extra[#cur.extra + 1] = line end
      end
    end
  end
  -- REAPER writes the sections in text order (Preset0, Preset1, Preset10 ...);
  -- keep them in number order, which is what the numbers mean
  table.sort(doc.presets, function(a, b) return (a.n or 0) < (b.n or 0) end)
  return doc
end

function PR.serialise(doc)
  local o = { "[General]" }
  for _, l in ipairs(doc.general) do o[#o + 1] = l end
  o[#o + 1] = "NbPresets=" .. #doc.presets
  o[#o + 1] = ""
  for i, p in ipairs(doc.presets) do
    o[#o + 1] = ("[Preset%d]"):format(i - 1)
    for _, l in ipairs(p.data) do o[#o + 1] = l end
    o[#o + 1] = "Len=" .. tostring(p.len or 0)
    o[#o + 1] = "Name=" .. (p.name or "")
    for _, l in ipairs(p.extra or {}) do o[#o + 1] = l end
    o[#o + 1] = ""
  end
  return table.concat(o, NL) .. NL
end

-- ---------------------------------------------------------------------
-- a plugin's identity
-- ---------------------------------------------------------------------
local function preset_file(track, fx)
  local a, b = reaper.TrackFX_GetUserPresetFilename(track, fx, "")
  local p = (type(a) == "string") and a or b
  if type(p) ~= "string" or p == "" then return nil end
  return p
end
PR.file = preset_file

local function ident(track, fx)
  local ok, id = reaper.TrackFX_GetNamedConfigParm(track, fx, "fx_ident")
  return ok and id or ""
end

-- "vst", "js", or nil for the formats saving isn't offered for. REAPER
-- names the type itself (fx_type); the identifier is the fallback.
local TYPES = { VST = "vst", VST3 = "vst", VSTi = "vst", VST3i = "vst", JS = "js" }
function PR.kind(track, fx)
  local okt, ty = reaper.TrackFX_GetNamedConfigParm(track, fx, "fx_type")
  if okt and ty and ty ~= "" then return TYPES[ty] end
  local id = ident(track, fx)
  if id == "" then return nil end
  local file = id:match("^(.-)<") or id
  local low = file:lower()
  if low:match("%.clap$") then return nil end
  if low:match("%.dll$") or low:match("%.vst3$") or low:match("%.vst$")
     or low:match("%.so$") or low:match("%.dylib$") then return "vst" end
  if not id:find("<", 1, true) and not file:match("^%a:[\\/]") and not file:match("^/") then
    return "js"
  end
  return nil
end

-- The plugin's key in reaper-defpresets.ini: vst-reacomp,
-- vst-uaudio_api_2500.vst3, js-guitar/flanger.
function PR.default_key(track, fx)
  local id = ident(track, fx)
  local kind = PR.kind(track, fx)
  if kind == "js" then return "js-" .. id end
  if kind == "vst" then
    local file = (id:match("^(.-)<") or id):match("([^\\/]+)$") or ""
    if file:lower():match("%.vst3$") then return "vst-" .. file end
    return "vst-" .. file:gsub("%.[^.]+$", "")
  end
  return nil
end

local function defaults_path() return reaper.GetResourcePath() .. "/reaper-defpresets.ini" end

local function default_of(key)
  if not key then return nil end
  for line in (read(defaults_path()) or ""):gmatch("[^\r\n]+") do
    local k, v = line:match("^(.-)=(.*)$")
    if k == key then return v end
  end
  return nil
end

-- Point the default at `name`, or clear it (nil).
local function set_default_entry(key, name)
  local text = read(defaults_path()) or "[defaultpresets]" .. NL
  local out, done, saw_sect = {}, false, false
  for line in text:gmatch("[^\r\n]+") do
    local k = line:match("^(.-)=")
    if line == "[defaultpresets]" then saw_sect = true end
    if k == key then
      if name and not done then out[#out + 1] = key .. "=" .. name end
      done = true
    else
      out[#out + 1] = line
    end
  end
  if not saw_sect then table.insert(out, 1, "[defaultpresets]") end
  if name and not done then out[#out + 1] = key .. "=" .. name end
  return write(defaults_path(), table.concat(out, NL) .. NL)
end

-- ---------------------------------------------------------------------
-- the plugin's state, from the track's chunk
-- ---------------------------------------------------------------------
local FXTAG = { VST = true, JS = true, CLAP = true, AU = true, DX = true, LV2 = true }

-- The header and body lines of the FX block whose FXID is `guid` (an FX's
-- own block, not <JS_PINMAP or anything else beside it).
local function fx_block(chunk, guid)
  local lines = {}
  for l in chunk:gmatch("[^\r\n]+") do lines[#lines + 1] = l:match("^%s*(.-)%s*$") end
  local i, ph, pb = 1, nil, nil
  while i <= #lines do
    local t = lines[i]
    local tag = t:match("^<(%u+)%s") or t:match("^<(%u+)$")
    if tag and FXTAG[tag] then
      local head, body, depth = t, {}, 1
      i = i + 1
      while i <= #lines and depth > 0 do
        local u = lines[i]
        if u:sub(1, 1) == "<" then depth = depth + 1
        elseif u == ">" then depth = depth - 1
        elseif depth == 1 then body[#body + 1] = u end
        i = i + 1
      end
      ph, pb = head, body
    else
      local g = t:match("^FXID%s+(%b{})")
      if g then
        if g == guid and ph then return ph, pb end
        ph, pb = nil, nil
      end
      i = i + 1
    end
  end
end

-- The plugin's saved state as a preset holds it, or nil and why.
function PR.state(track, fx)
  local guid = reaper.TrackFX_GetFXGUID(track, fx)
  local ok, chunk = reaper.GetTrackStateChunk(track, "", false)
  if not ok or not guid then return nil, "couldn't read the track" end
  local head, body = fx_block(chunk, guid)
  if not head then return nil, "couldn't find the plugin in the track" end
  if head:match("^<JS[%s]") or head == "<JS" then
    return body[1] or ""
  elseif head:match("^<VST[%s]") then
    local parts = {}
    for _, l in ipairs(body) do parts[#parts + 1] = b64dec(l) end
    return table.concat(parts)
  end
  return nil, "saving presets isn't supported for this plugin format yet"
end

-- ---------------------------------------------------------------------
-- listing
-- ---------------------------------------------------------------------
local function sorted(names)
  table.sort(names, function(a, b)
    local la, lb = a:lower(), b:lower()
    if la ~= lb then return la < lb end
    return a < b
  end)
  return names
end

local function factory_names(file)
  if not file then return {} end
  local text = read((file:gsub("%.ini$", "-builtin.ini")))
  local out = {}
  for _, name in (text or ""):gmatch("(%d%d%d%d%d)=([^\r\n]*)") do out[#out + 1] = name end
  return out
end

-- { user = sorted names, factory = names, default = name|nil,
--   can_save = bool, file = path } -- cached per instance until REAPER's
-- preset count for it moves or this module writes.
local cache = {}
function PR.forget(guid) if guid then cache[guid] = nil else cache = {} end end

function PR.list(track, fx)
  local guid = reaper.TrackFX_GetFXGUID(track, fx) or ""
  local _, count = reaper.TrackFX_GetPresetIndex(track, fx)
  local c = cache[guid]
  if c and c.count == count then return c.info end
  local file = preset_file(track, fx)
  local user = {}
  for _, p in ipairs(PR.parse(read(file)).presets) do
    if p.name and p.name ~= "" then user[#user + 1] = p.name end
  end
  local info = {
    user = sorted(user), factory = factory_names(file),
    default = default_of(PR.default_key(track, fx)),
    can_save = file ~= nil and PR.kind(track, fx) ~= nil,
    can_default = PR.default_key(track, fx) ~= nil,
    file = file,
  }
  cache[guid] = { count = count, info = info }
  return info
end

-- The preset the plugin is on, and whether it still matches it (false once
-- a parameter has moved).
function PR.current(track, fx)
  local same, name = reaper.TrackFX_GetPreset(track, fx, "")
  return name or "", same and true or false
end

function PR.is_user(track, fx, name)
  for _, n in ipairs(PR.list(track, fx).user) do if n == name then return true end end
  return false
end

-- ---------------------------------------------------------------------
-- changing them
-- ---------------------------------------------------------------------
local function load_doc(track, fx)
  local file = preset_file(track, fx)
  if not file then return nil, nil, "this plugin has no preset file" end
  return PR.parse(read(file)), file
end

local function done(track, fx, file, doc)
  if not write(file, PR.serialise(doc)) then return false, "couldn't write " .. file end
  PR.forget(reaper.TrackFX_GetFXGUID(track, fx))
  reaper.TrackFX_GetPresetIndex(track, fx)          -- REAPER rereads the file
  return true
end

-- Save the plugin's current state as user preset `name`, replacing one of
-- that name. Leaves the plugin on it.
function PR.save(track, fx, name)
  name = (name or ""):gsub("[\r\n]", " "):match("^%s*(.-)%s*$")
  if name == "" then return false, "the preset needs a name" end
  if not PR.kind(track, fx) then return false, "saving presets isn't supported for this plugin format yet" end
  local blob, why = PR.state(track, fx)
  if not blob then return false, why end
  local doc, file, err = load_doc(track, fx)
  if not doc then return false, err end
  local entry = { name = name, len = #blob, data = PR.data_lines(blob) }
  local replaced = false
  for i, p in ipairs(doc.presets) do
    if p.name == name then entry.extra = p.extra; doc.presets[i] = entry; replaced = true; break end
  end
  if not replaced then doc.presets[#doc.presets + 1] = entry end
  local ok, e = done(track, fx, file, doc)
  if not ok then return false, e end
  reaper.TrackFX_SetPreset(track, fx, name)         -- the same state: just names it
  return true
end

-- Save as `name` and make it the plugin's default preset.
function PR.save_default(track, fx, name)
  local key = PR.default_key(track, fx)
  if not key then return false, "default presets aren't supported for this plugin format yet" end
  local ok, e = PR.save(track, fx, name)
  if not ok then return false, e end
  if not set_default_entry(key, (name:gsub("[\r\n]", " "):match("^%s*(.-)%s*$"))) then
    return false, "couldn't write reaper-defpresets.ini"
  end
  PR.forget(reaper.TrackFX_GetFXGUID(track, fx))
  return true
end

function PR.rename(track, fx, old, new)
  new = (new or ""):gsub("[\r\n]", " "):match("^%s*(.-)%s*$")
  if new == "" then return false, "the preset needs a name" end
  local doc, file, err = load_doc(track, fx)
  if not doc then return false, err end
  local hit
  for _, p in ipairs(doc.presets) do
    if p.name == new and new ~= old then return false, "there's already a preset called " .. new end
    if p.name == old then hit = p end
  end
  if not hit then return false, "there's no user preset called " .. tostring(old) end
  hit.name = new
  local ok, e = done(track, fx, file, doc)
  if not ok then return false, e end
  local key = PR.default_key(track, fx)
  if key and default_of(key) == old then set_default_entry(key, new) end
  return true
end

function PR.delete(track, fx, name)
  local doc, file, err = load_doc(track, fx)
  if not doc then return false, err end
  local keep, found = {}, false
  for _, p in ipairs(doc.presets) do
    if p.name == name then found = true else keep[#keep + 1] = p end
  end
  if not found then return false, "there's no user preset called " .. tostring(name) end
  doc.presets = keep
  local ok, e = done(track, fx, file, doc)
  if not ok then return false, e end
  local key = PR.default_key(track, fx)
  if key and default_of(key) == name then set_default_entry(key, nil) end
  return true
end

-- Load by name (user or factory), the default, or step.
function PR.load(track, fx, name) return reaper.TrackFX_SetPreset(track, fx, name) end
function PR.load_default(track, fx) return reaper.TrackFX_SetPresetByIndex(track, fx, -1) end
function PR.step(track, fx, dir) return reaper.TrackFX_NavigatePresets(track, fx, dir) end

return PR
