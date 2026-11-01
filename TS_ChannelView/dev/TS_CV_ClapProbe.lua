-- @noindex
-- A development probe, not part of ChannelView: run it once from the action
-- list with a track selected, copy the console into the chat, delete it.
--
-- TS_CV_ClapProbe.lua -- how does REAPER save a CLAP plugin's presets?
--
-- For every plugin on the selected track (CLAP ones especially) it prints:
--   * the plugin's type, ident and user preset file;
--   * its block in the track chunk -- every line, long base64 shortened --
--     including any blocks nested inside it (a CLAP block keeps its state
--     in one);
--   * the [PresetN] section REAPER wrote for the preset the plugin is on now;
--   * which way of rebuilding the state from the chunk matches that
--     preset's Data byte for byte, if any, and where they part if none does;
--   * reaper-defpresets.ini, to see how a CLAP default is keyed.
-- Then, if one way matched, it writes a test preset, asks REAPER to load it
-- by name, and puts the preset file back exactly as it was.
--
-- Before running: on a CLAP plugin, use REAPER's preset menu (the + by the
-- preset box in the plugin window) to SAVE A PRESET and leave the plugin on
-- it, and set a default preset for it too.

local function msg(...)
  local t = {}
  for i = 1, select("#", ...) do t[#t + 1] = tostring((select(i, ...))) end
  reaper.ShowConsoleMsg(table.concat(t, " ") .. "\n")
end

local B = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local DEC = {}
for i = 1, 64 do DEC[B:byte(i)] = i - 1 end
local function b64dec(s)
  local out, bits, nb = {}, 0, 0
  for i = 1, #s do
    local v = DEC[s:byte(i)]
    if v then
      bits = (bits << 6) | v; nb = nb + 6
      if nb >= 8 then
        nb = nb - 8
        out[#out + 1] = string.char((bits >> nb) & 0xff)
      end
    end
  end
  return table.concat(out)
end
local function hex(s) return (s:gsub(".", function(c) return string.format("%02X", c:byte()) end)) end
local function is_b64(l) return #l >= 8 and l:match("^[A-Za-z0-9+/=]+$") ~= nil end

local function read(p)
  local f = p and io.open(p, "rb"); if not f then return nil end
  local s = f:read("a"); f:close(); return s
end
local function write(p, s)
  local f = io.open(p, "wb"); if not f then return false end
  f:write(s); f:close(); return true
end

-- The state in 16384-byte pieces, each followed by its check byte (the
-- piece's bytes summed, mod 256), in hex, as Data=, Data_1= ...
local function data_lines(blob)
  local out, n = {}, 0
  for i = 1, #blob, 16384 do
    local part = blob:sub(i, i + 16383)
    local sum = 0
    for k = 1, #part do sum = sum + part:byte(k) end
    out[#out + 1] = ((n == 0) and "Data=" or ("Data_" .. n .. "=")) .. hex(part) .. string.format("%02X", sum % 256)
    n = n + 1
  end
  return table.concat(out, "\n")
end

-- The raw hex of a preset's Data lines, check bytes and all, joined.
local function data_hex(data)
  local t = {}
  for v in data:gmatch("Data[_%d]*=([^\n]*)") do t[#t + 1] = v end
  return table.concat(t)
end

-- An FX's block, by its FXID: { head, lines = {...}, nested = { {tag, lines}, ... } }.
local FXTAG = { VST = true, JS = true, CLAP = true, AU = true, DX = true, LV2 = true }
local function fx_block(chunk, guid)
  local lines = {}
  for l in chunk:gmatch("[^\r\n]+") do lines[#lines + 1] = l:match("^%s*(.-)%s*$") end
  local i, pending = 1, nil
  while i <= #lines do
    local t = lines[i]
    local tag = t:match("^<(%u+)%s") or t:match("^<(%u+)$")
    if tag and FXTAG[tag] then
      local blk = { head = t, body = {}, all = {}, nested = {} }
      local depth, cur = 1, nil
      i = i + 1
      while i <= #lines and depth > 0 do
        local u = lines[i]
        if u:sub(1, 1) == "<" then
          depth = depth + 1
          if depth == 2 then cur = { tag = u, lines = {} }; blk.nested[#blk.nested + 1] = cur end
          blk.all[#blk.all + 1] = u
        elseif u == ">" then
          depth = depth - 1
          if depth == 1 then cur = nil end
          if depth > 0 then blk.all[#blk.all + 1] = u end
        else
          blk.all[#blk.all + 1] = u
          if depth == 1 then blk.body[#blk.body + 1] = u
          elseif depth == 2 and cur then cur.lines[#cur.lines + 1] = u end
        end
        i = i + 1
      end
      pending = blk
    else
      local g = t:match("^FXID%s+(%b{})")
      if g then
        if g == guid and pending then return pending end
        pending = nil
      end
      i = i + 1
    end
  end
end

local function presets_of(text)
  local out = {}
  for sect in (text or ""):gmatch("%[Preset%d+%]([^%[]*)") do
    local d = {}
    for line in sect:gmatch("Data[_%d]*=[^\r\n]*") do d[#d + 1] = line end
    out[#out + 1] = { name = sect:match("Name=([^\r\n]*)"), len = tonumber(sect:match("Len=(%d+)")),
                      data = table.concat(d, "\n"), raw = sect }
  end
  return out
end

local function b64_of(lines)
  local parts = {}
  for _, l in ipairs(lines) do if is_b64(l) then parts[#parts + 1] = b64dec(l) end end
  return table.concat(parts)
end

local tr = reaper.GetSelectedTrack(0, 0)
if not tr then reaper.MB("Select a track first.", "CLAP probe", 0); return end
local _, chunk = reaper.GetTrackStateChunk(tr, "", false)
reaper.ClearConsole()
msg("TS_CV_ClapProbe -- REAPER " .. reaper.GetAppVersion())
msg("reaper-defpresets.ini:\n" .. (read(reaper.GetResourcePath() .. "/reaper-defpresets.ini") or "(none)"))

for fx = 0, reaper.TrackFX_GetCount(tr) - 1 do
  local _, name = reaper.TrackFX_GetFXName(tr, fx, "")
  local guid = reaper.TrackFX_GetFXGUID(tr, fx)
  local _, cur = reaper.TrackFX_GetPreset(tr, fx, "")
  local idx, n = reaper.TrackFX_GetPresetIndex(tr, fx)
  local pfile = reaper.TrackFX_GetUserPresetFilename(tr, fx, "")
  if type(pfile) ~= "string" then pfile = select(2, reaper.TrackFX_GetUserPresetFilename(tr, fx, "")) end
  local _, ftype = reaper.TrackFX_GetNamedConfigParm(tr, fx, "fx_type")
  local _, ident = reaper.TrackFX_GetNamedConfigParm(tr, fx, "fx_ident")
  msg(("\n==== #%d %s"):format(fx + 1, name))
  msg("  type:", ftype, "  ident:", ident)
  msg("  preset now:", cur, "  index", idx, "of", n)
  msg("  preset file:", pfile)

  local blk = fx_block(chunk, guid)
  if not blk then
    msg("  (block not found in the chunk)")
  else
    msg("  chunk block:")
    msg("    " .. blk.head)
    for _, l in ipairs(blk.all) do
      msg("    " .. ((#l > 90) and (l:sub(1, 90) .. ("... (%d chars)"):format(#l)) or l))
    end

    local list = presets_of(read(pfile))
    local match
    for _, p in ipairs(list) do if p.name == cur then match = p end end
    if not match then
      msg("  (no user preset named '" .. tostring(cur) .. "' in the file -- save one and leave the plugin on it)")
    else
      local dh = data_hex(match.data)
      local dlines = select(2, match.data:gsub("Data", ""))
      msg(("  preset section: Len=%s, %d Data line(s), %d hex chars"):format(tostring(match.len), dlines, #dh))
      msg("  its other keys:")
      for line in match.raw:gmatch("[^\r\n]+") do
        if not line:match("^Data") then msg("    " .. line) end
      end
      msg("  Data starts: " .. dh:sub(1, 120))

      -- the ways the state could be rebuilt from the chunk
      local cands = {}
      cands[#cands + 1] = { "top-level base64 lines", b64_of(blk.body) }
      for k, nb in ipairs(blk.nested) do
        cands[#cands + 1] = { ("nested %d %s"):format(k, nb.tag), b64_of(nb.lines) }
      end
      cands[#cands + 1] = { "every base64 line", b64_of(blk.all) }
      if blk.body[1] then cands[#cands + 1] = { "first body line as text", blk.body[1] } end

      local winner
      for _, c in ipairs(cands) do
        local label, blob = c[1], c[2]
        if #blob > 0 then
          local ok = (data_lines(blob) == match.data)
          msg(("  candidate [%s]: %d bytes, same data: %s"):format(label, #blob, tostring(ok)))
          if ok then winner = winner or c
          else
            local bh = hex(blob)
            local at = dh:find(bh:sub(1, math.min(#bh, 64)), 1, true)
            msg("     starts: " .. bh:sub(1, 120))
            if at then msg(("     -> found inside the preset Data at hex char %d"):format(at)) end
          end
        end
      end

      -- write a test preset with the winner, load it by name, put the file back
      if winner and pfile and pfile ~= "" then
        local orig = read(pfile)
        if orig then
          local blob = winner[2]
          local nb = tonumber(orig:match("NbPresets=(%d+)")) or #list
          local test = "zz ChannelView probe"
          local add = ("\n[Preset%d]\n%s\nLen=%d\nName=%s\n"):format(nb, data_lines(blob), #blob, test)
          write(pfile, orig:gsub("NbPresets=%d+", "NbPresets=" .. (nb + 1), 1) .. add)
          local _, n2 = reaper.TrackFX_GetPresetIndex(tr, fx)
          local ok = reaper.TrackFX_SetPreset(tr, fx, test)
          local _, now = reaper.TrackFX_GetPreset(tr, fx, "")
          msg(("  wrote a test preset with [%s]: count %d -> %d, load by name %s, now on '%s'")
            :format(winner[1], n, n2, tostring(ok), tostring(now)))
          write(pfile, orig)
          reaper.TrackFX_SetPreset(tr, fx, cur)
          local _, n3 = reaper.TrackFX_GetPresetIndex(tr, fx)
          msg("  file restored, back on '" .. tostring(cur) .. "'; count now", n3)
        end
      end
    end
  end
end
msg("\nDone. Copy everything above into the chat.")
