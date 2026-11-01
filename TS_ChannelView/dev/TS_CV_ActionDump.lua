-- @noindex  (a development tool, not a package: never installed or released)
-- Writes REAPER's whole action list to TS_CV_actions.txt in the resource
-- folder: section, command id, named id (scripts, extensions), name. One
-- run; for matching ChannelView's icons to actions by name.
local SECTIONS = { { 0, "main" }, { 32060, "midi" }, { 32061, "midi_list" }, { 32062, "midi_inline" }, { 32063, "media_explorer" } }
local out, n = {}, 0
for _, s in ipairs(SECTIONS) do
  local sec = reaper.SectionFromUniqueID and reaper.SectionFromUniqueID(s[1])
  if sec and reaper.kbd_enumerateActions then
    local i = 0
    while true do
      local id, name = reaper.kbd_enumerateActions(sec, i)
      if not id or id <= 0 then break end
      local named = reaper.ReverseNamedCommandLookup(id) or ""
      out[#out + 1] = table.concat({ s[2], tostring(id), named, (name or ""):gsub("[\t\r\n]", " ") }, "\t")
      n, i = n + 1, i + 1
    end
  end
end
local path = reaper.GetResourcePath() .. package.config:sub(1, 1) .. "TS_CV_actions.txt"
local fh = io.open(path, "w")
if fh then fh:write(table.concat(out, "\n"), "\n"); fh:close() end
reaper.MB(("Wrote %d actions to\n%s"):format(n, path), "ChannelView", 0)
