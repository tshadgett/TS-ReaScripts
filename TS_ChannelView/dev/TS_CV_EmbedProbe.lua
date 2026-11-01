-- @noindex
-- dev tool, not released. Read-only: can ChannelView show REAPER's
-- embedded FX UIs (Show embedded UI in TCP / MCP)? Writes dev/embedprobe.txt
-- and, where it can, a picture of each TCP / mixer window to
-- dev/embed_<n>.png. Changes nothing in the project.
--
-- Before running: open the mixer, and on the selected track show at least
-- one plugin's embedded UI in the mixer (and/or TCP) -- right-click the FX
-- in the mixer strip > Show embedded UI.

local here = debug.getinfo(1, "S").source:match("@?(.*[\\/])") or ""
local out = {}
local function say(...) local t = {} for i = 1, select("#", ...) do t[#t + 1] = tostring(select(i, ...)) end out[#out + 1] = table.concat(t, "  ") end

say("REAPER " .. reaper.GetAppVersion(), "OS " .. reaper.GetOS())

-- 1) what the APIs offer
local names = {}
for k in pairs(reaper) do
  local lk = k:lower()
  if lk:find("embed") or lk:find("lice") and lk:find("imgui") or lk:find("ui_rect") then names[#names + 1] = k end
end
table.sort(names)
say("API names with embed / ImGui+LICE:", #names > 0 and table.concat(names, ", ") or "(none)")
for _, f in ipairs({ "ImGui_CreateImageFromLICE", "ImGui_CreateImage", "ImGui_CreateImageFromMem", "ImGui_GetVersion",
                     "JS_Window_Find", "JS_Window_ArrayAllTop", "JS_Window_ArrayAllChild", "JS_Window_GetClassName",
                     "JS_Window_GetRect", "JS_Window_GetClientRect", "JS_GDI_GetWindowDC", "JS_GDI_Blit",
                     "JS_LICE_CreateBitmap", "JS_LICE_GetDC", "JS_LICE_WritePNG", "JS_LICE_DestroyBitmap",
                     "JS_GDI_ReleaseDC", "JS_WindowMessage_Post", "JS_ReaScriptAPI_Version" }) do
  say(("  %-28s %s"):format(f, reaper[f] and "yes" or "no"))
end
if reaper.ImGui_GetVersion then say("ReaImGui", reaper.ImGui_GetVersion()) end

-- 2) the selected track: its FX, embed flags in the chunk, strip rects
local tr = reaper.GetSelectedTrack(0, 0)
if not tr then say("No track selected.") else
  local _, tn = reaper.GetTrackName(tr)
  say("Track: " .. tn)
  for _, k in ipairs({ "I_MCPX", "I_MCPY", "I_MCPW", "I_MCPH", "I_TCPY", "I_TCPH", "I_WNDH" }) do
    local ok, v = pcall(reaper.GetMediaTrackInfo_Value, tr, k)
    say(("  %-7s %s"):format(k, ok and tostring(v) or "error"))
  end
  for _, el in ipairs({ "tcp.size", "mcp.size", "tcp.fxembed", "mcp.fxembed", "tcp.fxembedheader", "mcp.fxembedheader",
                        "tcp.fxparm", "mcp.fxparm", "tcp.fx", "mcp.fx", "mcp.fxlist", "tcp.fxlist" }) do
    local ok, got, v = pcall(reaper.GetSetMediaTrackInfo_String, tr, "P_UI_RECT:" .. el, "", false)
    say(("  P_UI_RECT:%-18s %s %s"):format(el, ok and tostring(got) or "error", ok and tostring(v) or tostring(got)))
  end
  local ok, chunk = reaper.GetTrackStateChunk(tr, "", false)
  if ok then
    local n = 0
    for line in chunk:gmatch("[^\r\n]+") do
      local s = line:match("^%s*(.-)%s*$")
      if s:match("^<VST") or s:match("^<JS") or s:match("^<CLAP") or s:match("^<AU") or s:match("^<DX") or s:match("^<LV2") then
        n = n + 1
        say(("  fx %d: %s"):format(n, s:sub(1, 90)))
      elseif s:match("^WAK ") or s:match("^FXID") or s:match("^SHOW ") or s:match("^FLOAT") or s:match("^BYPASS") then
        say("      " .. s)
      end
    end
  end
  for i = 0, reaper.TrackFX_GetCount(tr) - 1 do
    local _, nm = reaper.TrackFX_GetFXName(tr, i, "")
    local line = ("  FX %d %s"):format(i, nm)
    for _, key in ipairs({ "embed", "ui_embed", "embedded_ui", "fx_embed", "tcp_embed", "mcp_embed" }) do
      local okk, has, val = pcall(reaper.TrackFX_GetNamedConfigParm, tr, i, key)
      if okk and has then line = line .. ("  %s=%s"):format(key, tostring(val)) end
    end
    say(line)
  end
end

-- 3) the TCP and mixer windows: class names, and a picture of each
local wins = {}
if reaper.JS_Window_ArrayAllTop and reaper.JS_Window_ArrayAllChild then
  local function collect(list_fn, parent)
    local arr = reaper.new_array({}, 2048)
    local n = parent and list_fn(parent, arr) or list_fn(arr)
    local t = arr.table()
    local found = {}
    for i = 1, #t do
      local h = reaper.JS_Window_HandleFromAddress(t[i])
      if h then found[#found + 1] = h end
    end
    return found
  end
  local tops = collect(reaper.JS_Window_ArrayAllTop)
  for _, top in ipairs(tops) do
    local kids = collect(reaper.JS_Window_ArrayAllChild, top)
    kids[#kids + 1] = top
    for _, h in ipairs(kids) do
      local cls = reaper.JS_Window_GetClassName(h) or ""
      if cls:find("TCP") or cls:find("MCP") or cls:find("Mixer") then
        local _, l, t, r, b = reaper.JS_Window_GetRect(h)
        local vis = reaper.JS_Window_IsVisible and reaper.JS_Window_IsVisible(h)
        wins[#wins + 1] = { h = h, cls = cls, l = l, t = t, r = r, b = b }
        say(("  window %-24s %s  rect %d,%d .. %d,%d  visible %s"):format(cls, reaper.JS_Window_GetTitle(h) or "", l, t, r, b, tostring(vis)))
      end
    end
  end
else
  say("js_ReaScriptAPI missing: no window list")
end

if reaper.JS_GDI_GetWindowDC and reaper.JS_LICE_CreateBitmap and reaper.JS_LICE_WritePNG then
  for i, w in ipairs(wins) do
    local _, cl, ct, cr, cb = reaper.JS_Window_GetClientRect(w.h)
    local cw, ch = math.abs(cr - cl), math.abs(cb - ct)
    if cw > 10 and ch > 10 and cw < 8000 and ch < 8000 then
      local bmp = reaper.JS_LICE_CreateBitmap(true, cw, ch)
      local src = reaper.JS_GDI_GetWindowDC(w.h)
      reaper.JS_GDI_Blit(reaper.JS_LICE_GetDC(bmp), 0, 0, src, 0, 0, cw, ch)
      reaper.JS_GDI_ReleaseDC(w.h, src)
      local path = here .. ("embed_%d.png"):format(i)
      local ok = reaper.JS_LICE_WritePNG(path, bmp, false)
      reaper.JS_LICE_DestroyBitmap(bmp)
      say(("  picture %d (%s, %dx%d): %s"):format(i, w.cls, cw, ch, ok and path or "failed"))
    end
  end
end

local f = io.open(here .. "embedprobe.txt", "w")
if f then f:write(table.concat(out, "\n") .. "\n"); f:close() end
reaper.ShowConsoleMsg("EmbedProbe: wrote " .. here .. "embedprobe.txt\n")
