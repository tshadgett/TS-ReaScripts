-- @description TS_DrumToolbox - offline drum detection, bleed control, replacement, gate and noise for the whole kit
-- @author Tim Shadgett
-- @version 1.0.2
-- @changelog
--   Align: room mics are left where they are by default; Put back returns
--   every track Align moved exactly as it was, and an undo of Apply is
--   recognised.
--   Quantise: slices of edited tracks (comps, crossfades, hairline gaps)
--   are joined and crossfaded too, so no holes; any gap that's left is
--   reported, with Next gap to find each; Undo quantise.
--   Level: says what it does (evens the hits, doesn't add level).
-- @provides
--   [nomain] TS_DrumToolbox_core.lua
--   [nomain] TS_DT_Edition.lua
--   [main] TS_DrumToolbox_Detect.lua
--   [main] TS_DrumToolbox_Clear.lua
-- @about
--   Drum detection, alignment, quantising, levelling, gating and
--   reinforcement for a whole multitrack kit, done with REAPER's own tools:
--   take markers, items, envelopes, ReaGate, ReaEQ and RS5K.
--[[
  TS_DrumToolbox.lua -- the window.

  The workflow, as tabs across the top:
    Setup      every track's role in the kit (drum, second mic, bleed
               source, reference, ignore), suggested from names and
               folders; a role set by hand always wins.
    Detect     every hit on the kit's drums, in the background, then the
               bleed check across the kit; the hits in lanes to review.
    Align      second mics to their drum and the rest to the reference,
               measured on the hits; moves the items or the audio in them.
    Quantise   the whole kit cut at the same points and moved to the grid,
               crossfaded, phase kept.
  With DrumToolbox Pro:
    Level      each hit evened out (clip gain or a pre-FX envelope).
    Gate       ReaGate opened by the hit map; Duck, Clean, Debleed.
    Tone       the drum's partials as ReaEQ bands, always or per hit.
    Reinforce  noise, samples (RS5K) and kit instruments under every hit.

  Needs ReaImGui (ReaPack: ReaTeam Extensions).
]]

-- With Pro: this script runs with Pro's parts put back in (TS_DT_Edition)
do
  local own = debug.getinfo(1, "S").source:match("^@?(.*)$")
  package.path = (own:match("^(.*[\\/])") or "") .. "?.lua;" .. package.path
  local fn = require("TS_DT_Edition").self(own)
  if fn then return fn(...) end
end

local r = reaper
local dir = debug.getinfo(1, "S").source:match("^@?(.*[\\/])") or ""
package.path = dir .. "?.lua;" .. package.path
local DT = require("TS_DrumToolbox_core")

if not r.ImGui_GetBuiltinPath then
  r.MB("TS DrumToolbox needs ReaImGui.\n\nInstall it with ReaPack: Extensions > ReaPack > Browse packages > ReaImGui.",
    "TS DrumToolbox", 0)
  return
end
package.path = r.ImGui_GetBuiltinPath() .. "/?.lua;" .. package.path
local ok_imgui, imgui_loader = pcall(require, "imgui")
local ImGui
if ok_imgui then
  for _, v in ipairs({ "0.10", "0.9" }) do
    local ok, m = pcall(imgui_loader, v)
    if ok and m then ImGui = m; break end
  end
end
if not ImGui then
  r.MB("TS DrumToolbox needs a newer ReaImGui (0.9 or later).", "TS DrumToolbox", 0)
  return
end

-- A name that may not exist in this ReaImGui version (it raises an error
-- for unknown names rather than giving nil). Several names: the first that
-- exists.
local function K(...)
  for _, name in ipairs({ ... }) do
    local ok, v = pcall(function() return ImGui[name] end)
    if ok and v ~= nil then return v end
  end
  return nil
end
local CHILD_BORDER = K("ChildFlags_Borders", "ChildFlags_Border") or 1
local UI = {}   -- shared panel helpers (the main chunk is at Lua's 200-local limit)
local NSYNC = { state = nil }   -- notes/keys/bands follow the hit map: when the kit was last checked

local TITLE = "TS DrumToolbox"
local ctx = ImGui.CreateContext(TITLE)
local ALIGN_CMD = 43466            -- Item edit: Phase alignment... (REAPER 7.40+)

-- ---------------------------------------------------------------------
-- look: ChannelView's default palette
-- ---------------------------------------------------------------------
local COL = {
  win = 0x11131aff, panel = 0x1b1e26ff, border = 0x2c313dff, head = 0x232833ff,
  text = 0xd6dae4ff, dim = 0x76808fff, label = 0x9aa4b4ff, accent = 0x4a9edaff,
  chip = 0x292c32ff, chip_hov = 0x30343bff, chip_on = 0x393d46ff, edge = 0x4b4f58ff, field = 0x22242bff,
  hi = 0x4cc9a6ff, mid = 0xd8a24aff, lo = 0xd8724aff, second = 0xbf84cdff, ref = 0x76808fff,
}
local ROLE_COL = { drum = 0x4a9edaff, second = COL.second, bleed = COL.mid, reference = COL.ref, ignore = COL.border }

-- each workflow tab has its colour; the controls (main buttons, choices,
-- sliders, ticks, the tab's bar) follow the open tab's. Hits keep their
-- own colours (confidence) everywhere.
local TAB_COL = {
  kit = 0x8fa3c0ff,        -- Setup: slate
  detect = 0x4a9edaff,     -- blue
  align = 0x3fb8afff,      -- teal
  quant = 0x6cc06aff,      -- green
  level = 0xe3b341ff,      -- amber
  gate = 0xe8894aff,       -- orange
  enhance = 0xb784e0ff,    -- violet
  reinforce = 0xe0607aff,  -- coral
}
local function mix(c, to, f)
  local function ch(x, sh) return (x >> sh) & 0xff end
  local out = 0
  for _, sh in ipairs({ 24, 16, 8 }) do
    local v = math.floor(ch(c, sh) + (ch(to, sh) - ch(c, sh)) * f + 0.5)
    out = out | (v << sh)
  end
  return out | (c & 0xff)
end
local function set_accent(tab)
  local c = TAB_COL[tab] or TAB_COL.detect
  COL.accent = c
  COL.accent_hi = mix(c, 0xffffffff, 0.22)
  COL.accent_lo = mix(c, 0x000000ff, 0.18)
end
set_accent("detect")

local STYLE = {
  { "Col_WindowBg", COL.win }, { "Col_ChildBg", COL.panel }, { "Col_PopupBg", COL.panel },
  { "Col_Text", COL.text }, { "Col_TextDisabled", COL.dim }, { "Col_Border", COL.border },
  { "Col_FrameBg", COL.field }, { "Col_FrameBgHovered", COL.chip }, { "Col_FrameBgActive", COL.chip_hov },
  { "Col_Button", COL.chip }, { "Col_ButtonHovered", COL.chip_hov }, { "Col_ButtonActive", COL.chip_on },

  { "Col_TitleBg", COL.win }, { "Col_TitleBgActive", COL.head },
  { "Col_Tab", COL.chip }, { "Col_TabHovered", COL.chip_on }, { { "Col_TabSelected", "Col_TabActive" }, COL.chip_on },
  { "Col_TableHeaderBg", COL.head }, { "Col_TableRowBg", 0x00000000 }, { "Col_TableRowBgAlt", 0xffffff06 },
  { "Col_TableBorderLight", COL.border }, { "Col_TableBorderStrong", COL.border },
  { "Col_Separator", COL.border },
}
local VARS = { { "StyleVar_FrameRounding", 4 }, { "StyleVar_WindowPadding", { 12, 10 } }, { "StyleVar_ItemSpacing", { 8, 6 } } }

local pushed_c, pushed_v = 0, 0
local function push_style()
  pushed_c, pushed_v = 0, 0
  local a = COL.accent & 0xffffff00
  local dyn = {
    { "Col_Header", a | 0x48 }, { "Col_HeaderHovered", a | 0x30 }, { "Col_HeaderActive", a | 0x60 },
    { "Col_PlotHistogram", COL.accent }, { "Col_CheckMark", COL.accent },
    { "Col_SliderGrab", COL.accent }, { "Col_SliderGrabActive", COL.accent_hi },
  }
  for _, list in ipairs({ STYLE, dyn }) do
    for _, e in ipairs(list) do
      local k = type(e[1]) == "table" and K(table.unpack(e[1])) or K(e[1])
      if k then ImGui.PushStyleColor(ctx, k, e[2]); pushed_c = pushed_c + 1 end
    end
  end
  for _, e in ipairs(VARS) do
    local k = K(e[1])
    if k then
      if type(e[2]) == "table" then ImGui.PushStyleVar(ctx, k, e[2][1], e[2][2]) else ImGui.PushStyleVar(ctx, k, e[2]) end
      pushed_v = pushed_v + 1
    end
  end
end
local function pop_style()
  if pushed_v > 0 then ImGui.PopStyleVar(ctx, pushed_v) end
  if pushed_c > 0 then ImGui.PopStyleColor(ctx, pushed_c) end
end

local function caption(text) ImGui.TextColored(ctx, COL.label, text) end
local function tip(text) if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, text) end end

-- ---------------------------------------------------------------------
-- icons: line drawings on a 24 unit grid (as ChannelView's are), drawn at
-- any size in the button's ink. Every button is an icon with a tooltip.
-- ---------------------------------------------------------------------
local function arc(cx, cy, rad, a0, a1, n)
  local pts = {}
  n = n or 14
  for i = 0, n do
    local a = math.rad(a0 + (a1 - a0) * i / n)
    pts[#pts + 1] = { cx + rad * math.cos(a), cy + rad * math.sin(a) }
  end
  return pts
end
local function wave(x0, x1, y, amp, cycles, n)
  local pts = {}
  n = n or 24
  for i = 0, n do
    local t = i / n
    pts[#pts + 1] = { x0 + (x1 - x0) * t, y - amp * math.sin(t * cycles * 2 * math.pi) }
  end
  return pts
end

-- each icon: { strokes = { {pts...}, ... }, fills = { {x0,y0,x1,y1}, ... } }
local ICONS = {
  -- back to the suggestion: a circular arrow
  reset = { strokes = { arc(12, 12, 7, -150, 160), { { 4.5, 4.5 }, { 5.6, 9.2 }, { 10.2, 8.4 } } } },
  -- every role back: the circular arrow round a list
  reset_all = { strokes = { arc(12, 12, 9, -150, 160), { { 2.8, 3.2 }, { 4, 8.6 }, { 9.4, 7.6 } },
                            { { 9, 10 }, { 15, 10 } }, { { 9, 13 }, { 15, 13 } }, { { 9, 16 }, { 13, 16 } } } },
  -- phase alignment: two waves, lined up on a guide
  align = { strokes = { wave(2.5, 21.5, 7.5, 3.5, 1), wave(2.5, 21.5, 17, 3.5, 1), { { 7.25, 2 }, { 7.25, 4.2 } },
                        { { 7.25, 9.5 }, { 7.25, 12 } }, { { 7.25, 19.5 }, { 7.25, 22 } } } },
  -- done
  check = { strokes = { { { 4.5, 12.5 }, { 9.5, 17.5 }, { 19.5, 6.5 } } } },
  -- detect: a waveform with hit flags
  detect = { strokes = { { { 2, 15 }, { 5, 15 }, { 6, 7 }, { 7.5, 20 }, { 9, 13 }, { 11, 15 }, { 13, 15 }, { 14, 9 },
                           { 15.5, 19 }, { 17, 14 }, { 22, 15 } },
                         { { 6, 3 }, { 6, 7 } }, { { 14, 3 }, { 14, 9 } } },
             fills = { { 6, 2.5, 9.5, 5 }, { 14, 2.5, 17.5, 5 } } },
  -- detect the selected tracks: the same, in a selection bracket
  detect_sel = { strokes = { { { 5, 16 }, { 7, 16 }, { 8, 9 }, { 9.5, 20 }, { 11, 14 }, { 13, 16 }, { 19, 16 } },
                             { { 8, 5 }, { 8, 9 } },
                             { { 4, 2.5 }, { 2.5, 2.5 }, { 2.5, 21.5 }, { 4, 21.5 } }, { { 20, 2.5 }, { 21.5, 2.5 }, { 21.5, 21.5 }, { 20, 21.5 } } },
                 fills = { { 8, 4.5, 11.5, 7 } } },
  stop = { fills = { { 6, 6, 18, 18 } } },
  -- tick every track / untick every track
  tick_all = { strokes = { { { 3, 4 }, { 9, 4 }, { 9, 10 }, { 3, 10 }, { 3, 4 } }, { { 4.5, 7 }, { 6, 8.5 }, { 8, 5 } },
                           { { 3, 14 }, { 9, 14 }, { 9, 20 }, { 3, 20 }, { 3, 14 } }, { { 4.5, 17 }, { 6, 18.5 }, { 8, 15 } },
                           { { 12, 7 }, { 21, 7 } }, { { 12, 17 }, { 21, 17 } } } },
  tick_none = { strokes = { { { 3, 4 }, { 9, 4 }, { 9, 10 }, { 3, 10 }, { 3, 4 } },
                            { { 3, 14 }, { 9, 14 }, { 9, 20 }, { 3, 20 }, { 3, 14 } },
                            { { 12, 7 }, { 21, 7 } }, { { 12, 17 }, { 21, 17 } } } },
  -- measure the offsets: two strikes and the gap between them
  measure = { strokes = { { { 2, 9 }, { 5, 9 }, { 6, 3 }, { 7, 13 }, { 8, 9 }, { 22, 9 } },
                          { { 2, 17 }, { 10, 17 }, { 11, 11 }, { 12, 21 }, { 13, 17 }, { 22, 17 } },
                          { { 6, 13 }, { 11, 13 } }, { { 7.5, 11.5 }, { 6, 13 }, { 7.5, 14.5 } }, { { 9.5, 11.5 }, { 11, 13 }, { 9.5, 14.5 } } } },
  -- move the items: a block and an arrow
  items = { strokes = { { { 3, 8 }, { 14, 8 }, { 14, 16 }, { 3, 16 }, { 3, 8 } }, { { 14, 12 }, { 21, 12 } }, { { 18, 9 }, { 21, 12 }, { 18, 15 } } },
            fills = { { 4, 9, 13, 15 } } },
  -- move the contents: the block stays, the wave inside moves
  contents = { strokes = { { { 2, 6 }, { 22, 6 }, { 22, 18 }, { 2, 18 }, { 2, 6 } },
                           { { 4, 12 }, { 7, 12 }, { 8, 9 }, { 9, 15 }, { 10, 12 }, { 12, 12 } },
                           { { 13, 12 }, { 19, 12 } }, { { 16.5, 9.5 }, { 19, 12 }, { 16.5, 14.5 } } } },
  -- polarity
  polarity = { strokes = { arc(12, 12, 8, 0, 360, 28), { { 5, 19 }, { 19, 5 } } } },
  -- keep & lock: a padlock
  lock = { strokes = { { { 6, 11 }, { 18, 11 }, { 18, 21 }, { 6, 21 }, { 6, 11 } }, arc(12, 8.5, 4, 180, 360, 12),
                       { { 8, 8.5 }, { 8, 11 } }, { { 16, 8.5 }, { 16, 11 } }, { { 12, 14.5 }, { 12, 17.5 } } } },
  -- bleed from another drum: a hit leaking in from the next lane
  bleed = { strokes = { { { 2, 7 }, { 22, 7 } }, { { 2, 17 }, { 22, 17 } }, { { 8, 3 }, { 8, 7 } },
                        { { 8, 8.5 }, { 8, 10 } }, { { 8, 11.5 }, { 8, 13 } }, { { 8, 14.5 }, { 8, 16 } },
                        arc(15, 17, 3.2, 0, 360, 16) },
            fills = { { 7, 2, 9, 7 } } },
  prev = { strokes = { { { 15, 5 }, { 8, 12 }, { 15, 19 } }, { { 5, 5 }, { 5, 19 } } } },
  next = { strokes = { { { 9, 5 }, { 16, 12 }, { 9, 19 } }, { { 19, 5 }, { 19, 19 } } } },
  play = { strokes = { { { 7, 4 }, { 19, 12 }, { 7, 20 }, { 7, 4 } }, { { 9, 8 }, { 15, 12 }, { 9, 16 }, { 9, 8 } }, { { 11, 11 }, { 11, 13 } } } },
  loop = { strokes = { arc(12, 12, 7.5, -60, 230, 20), { { 18.5, 3.5 }, { 16, 7.6 }, { 20.5, 9 } } } },
  -- listen to: the drum alone / the kit / the mix
  solo = { strokes = { { { 2, 12 }, { 7, 12 }, { 8.5, 5 }, { 10, 19 }, { 11.5, 12 }, { 22, 12 } } } },
  kit = { strokes = { { { 2, 5 }, { 22, 5 } }, { { 2, 12 }, { 22, 12 } }, { { 2, 19 }, { 22, 19 } },
                      { { 7, 2.5 }, { 7, 7.5 } }, { { 12, 9.5 }, { 12, 14.5 } }, { { 17, 16.5 }, { 17, 21.5 } } } },
  mix = { strokes = { { { 6, 3 }, { 6, 21 } }, { { 12, 3 }, { 12, 21 } }, { { 18, 3 }, { 18, 21 } } },
          fills = { { 4, 13, 8, 16 }, { 10, 6, 14, 9 }, { 16, 10, 20, 13 } } },
  -- transport
  to_start = { strokes = { { { 5, 5 }, { 5, 19 } }, { { 19, 5 }, { 9, 12 }, { 19, 19 }, { 19, 5 } } } },
  pause = { fills = { { 6, 5, 10, 19 }, { 14, 5, 18, 19 } } },
  -- the lanes follow the playhead: a line with an arrow beside it
  follow = { strokes = { { { 9, 3 }, { 9, 21 } }, { { 12, 12 }, { 21, 12 } }, { { 17.5, 8.5 }, { 21, 12 }, { 17.5, 15.5 } } } },
  -- add a missed hit: a plus on a lane
  add = { strokes = { { { 2, 19 }, { 22, 19 } }, { { 12, 4 }, { 12, 16 } }, { { 6, 10 }, { 18, 10 } } } },
  -- clear the hit map: a bin
  clear = { strokes = { { { 4, 6.5 }, { 20, 6.5 } }, { { 9, 6.5 }, { 9.5, 3.5 }, { 14.5, 3.5 }, { 15, 6.5 } },
                        { { 6, 6.5 }, { 7, 20.5 }, { 17, 20.5 }, { 18, 6.5 } }, { { 10, 10 }, { 10, 17 } }, { { 14, 10 }, { 14, 17 } } } },
}

local function draw_icon(dl, name, x, y, size, col)
  local ic = ICONS[name]
  if not ic then return end
  local k = size / 24
  local th = math.max(1.2, size / 14)
  for _, f in ipairs(ic.fills or {}) do
    ImGui.DrawList_AddRectFilled(dl, x + f[1] * k, y + f[2] * k, x + f[3] * k, y + f[4] * k, col, 1)
  end
  for _, st in ipairs(ic.strokes or {}) do
    for i = 2, #st do
      ImGui.DrawList_AddLine(dl, x + st[i - 1][1] * k, y + st[i - 1][2] * k, x + st[i][1] * k, y + st[i][2] * k, col, th)
    end
  end
end

-- An icon button. kind: nil (grey chip), "main" (the step's action, in the
-- accent), "armed" (asking to be clicked again), "flat" (no chip, for
-- small inline buttons). Gives true when clicked.
local function icon_button(id, name, tooltip, kind, size, col)
  size = size or 28
  local x, y = ImGui.GetCursorScreenPos(ctx)
  local clicked = ImGui.InvisibleButton(ctx, id, size, size)
  local hov = ImGui.IsItemHovered(ctx)
  local active = ImGui.IsItemActive(ctx)
  local disabled = false
  local dl = ImGui.GetWindowDrawList(ctx)
  local bg, ink
  if kind == "main" or kind == "armed" then
    local base = col or COL.accent
    local b_hi = col and mix(col, 0xffffffff, 0.22) or COL.accent_hi
    local b_lo = col and mix(col, 0x000000ff, 0.18) or COL.accent_lo
    bg = kind == "armed" and COL.mid or (active and b_lo or (hov and b_hi or base))
    ink = 0x0e1015ff
  elseif kind == "flat" then
    bg = hov and COL.chip_hov or nil
    ink = hov and COL.text or COL.label
  else
    bg = active and COL.chip_on or (hov and COL.chip_hov or COL.chip)
    ink = hov and COL.text or COL.label
  end
  if bg then
    ImGui.DrawList_AddRectFilled(dl, x, y, x + size, y + size, bg, 4)
    if kind ~= "main" and kind ~= "armed" and kind ~= "flat" then
      ImGui.DrawList_AddRect(dl, x + 0.5, y + 0.5, x + size - 0.5, y + size - 0.5, COL.edge, 4)
    end
  end
  local pad = size * 0.16
  draw_icon(dl, name, x + pad, y + pad, size - 2 * pad, ink)
  if hov and tooltip then ImGui.SetTooltip(ctx, tooltip) end
  return clicked
end


-- ---------------------------------------------------------------------
-- the kit, cached until the project changes
-- ---------------------------------------------------------------------
local cache = { state = -1 }
local function depth_of(t)
  local d, p = 0, r.GetParentTrack(t)
  while p do d = d + 1; p = r.GetParentTrack(p) end
  return d
end
local function kit_now()
  local sc = r.GetProjectStateChangeCount(0)
  if sc ~= cache.state then
    cache.state = sc
    cache.kit = DT.kit_roles()
    cache.drums = {}
    cache.review = {}
    cache.dens = nil
    for _, e in ipairs(cache.kit) do
      e.depth = depth_of(e.track)
      if e.role == "drum" then cache.drums[#cache.drums + 1] = e end
      if (e.role == "drum" or e.role == "bleed") and DT.is_source(e.track) then
        local hits = DT.track_hits(e.track)
        local review, red = 0, 0
        local tilts = {}
        for _, h in ipairs(hits) do
          h.lane = e
          if DT.needs_review(h) then
            review = review + 1
            if (h.c or 1) < DT.C_MID then red = red + 1 end
            cache.review[#cache.review + 1] = h
          end
          if h.tilt then tilts[#tilts + 1] = h.tilt end
        end
        e.hitlist, e.bleedlist = hits, DT.track_bleed(e.track)
        e.hits, e.review, e.red, e.bleed = #hits, review, red, #e.bleedlist
        table.sort(tilts)
        e.tilt_med = #tilts > 0 and tilts[(#tilts + 1) // 2] or nil
      else
        e.hitlist, e.bleedlist = nil, nil
      end
    end
    table.sort(cache.review, function(a, b) return a.proj < b.proj end)
    cache.span0, cache.span1 = DT.kit_span(cache.kit)
  end
  return cache.kit, cache.drums
end
local function invalidate() cache.state = -1 end

-- A fingerprint of some tracks' hit maps (count, times, confidence, locks),
-- worked out once per project change: what the gate and Clean follow
-- (not the project's change count, which our own writes move too)
local HSIG = { state = nil, by = {} }
local function hit_sig(tracks)
  if HSIG.state ~= cache.state then HSIG.state, HSIG.by = cache.state, {} end
  local parts = {}
  for _, t in ipairs(tracks) do
    local v = HSIG.by[t]
    if not v then
      local hl
      for _, e in ipairs(cache.kit or {}) do if e.track == t then hl = e.hitlist end end
      hl = hl or DT.track_hits(t)
      local sum, c = 0, 0
      for _, h in ipairs(hl) do sum = sum + h.proj; c = c + (h.c or 1) + (h.locked and 1 or 0) end
      v = string.format("%d:%.4f:%.3f", #hl, sum, c)
      HSIG.by[t] = v
    end
    parts[#parts + 1] = v
  end
  return table.concat(parts, ";")   -- (no "|": it's stored in a "|" list)
end

local profiles = DT.list_profiles("detect")

-- ---------------------------------------------------------------------
-- state
-- ---------------------------------------------------------------------
local S = {
  tab = "kit",
  align = nil,          -- REAPER's aligner open: { snap = {...}, seen_on = bool, t0 }
  meas = nil,           -- our aligner measuring: { job, plan, t0 }
  outcome = nil,        -- what measuring found: { plan, list, when, applied }
  align_result = nil,   -- { when, moved = { {name, ms, flipped} }, checked = bool }
  det = nil,            -- running detection
  det_result = nil,     -- { lines = {...}, when }
  confirm_reset = false,
  follow = r.GetExtState("TS_DrumToolbox", "follow") ~= "0",
  preroll = ({ none = 1, beats2 = 1, bar1 = 1, bar2 = 1 })[r.GetExtState("TS_DrumToolbox", "preroll")] and r.GetExtState("TS_DrumToolbox", "preroll") or "none",
  listen = ({ solo = 1, kit = 1, mix = 1 })[r.GetExtState("TS_DrumToolbox", "listen")] and r.GetExtState("TS_DrumToolbox", "listen") or "kit",
}

local jump_review     -- (the lanes) go to a track's first hit to review

local function reaper_version()
  local v = r.GetAppVersion():match("^(%d+%.%d+)")
  return tonumber(v) or 0
end
local CAN_ALIGN = reaper_version() >= 7.40

-- ---------------------------------------------------------------------
-- roles
-- ---------------------------------------------------------------------
local function set_role(e, role, profile, of)
  r.Undo_BeginBlock2(0)
  DT.set_role(e.track, role, profile, of, true)
  r.Undo_EndBlock2(0, "TS DrumToolbox: set kit role", -1)
  invalidate()
end

local function reset_role(e)
  r.Undo_BeginBlock2(0)
  DT.set_role(e.track, nil)
  DT.store_suggested_roles()
  r.Undo_EndBlock2(0, "TS DrumToolbox: role back to suggestion", -1)
  invalidate()
end

local function reset_all_roles(kit)
  r.Undo_BeginBlock2(0)
  for _, e in ipairs(kit) do if e.user then DT.set_role(e.track, nil) end end
  DT.store_suggested_roles()
  r.Undo_EndBlock2(0, "TS DrumToolbox: roles back to suggestions", -1)
  invalidate()
end

-- ---------------------------------------------------------------------
-- align (REAPER's Phase alignment)
-- ---------------------------------------------------------------------
local function snapshot(kit)
  local snap = {}
  for _, e in ipairs(kit) do
    if e.role ~= "ignore" then
      for i = 0, r.CountTrackMediaItems(e.track) - 1 do
        local it = r.GetTrackMediaItem(e.track, i)
        local tk = r.GetActiveTake(it)
        snap[#snap + 1] = {
          item = it, name = e.name, role = e.role,
          pos = r.GetMediaItemInfo_Value(it, "D_POSITION"),
          offs = tk and r.GetMediaItemTakeInfo_Value(tk, "D_STARTOFFS") or 0,
          rate = tk and r.GetMediaItemTakeInfo_Value(tk, "D_PLAYRATE") or 1,
          pol = tk and r.GetMediaItemTakeInfo_Value(tk, "B_PHASE") or 0,
        }
      end
    end
  end
  return snap
end

local function start_align(kit)
  local prev = {}
  for i = 0, r.CountSelectedMediaItems(0) - 1 do prev[#prev + 1] = r.GetSelectedMediaItem(0, i) end
  local snap = snapshot(kit)
  r.Main_OnCommand(40289, 0)                -- Item: Unselect all items
  for _, s in ipairs(snap) do r.SetMediaItemSelected(s.item, true) end
  r.UpdateArrange()
  S.align = { phase = "open", snap = snap, prev = prev, seen_on = false, t0 = r.time_precise() }
  r.Main_OnCommand(ALIGN_CMD, 0)
end

local function finish_align()
  local a = S.align
  S.align = nil
  local moved, by_name = {}, {}
  for _, s in ipairs(a.snap) do
    if r.ValidatePtr(s.item, "MediaItem*") then
      local tk = r.GetActiveTake(s.item)
      local pos = r.GetMediaItemInfo_Value(s.item, "D_POSITION")
      local offs = tk and r.GetMediaItemTakeInfo_Value(tk, "D_STARTOFFS") or 0
      local pol = tk and r.GetMediaItemTakeInfo_Value(tk, "B_PHASE") or 0
      -- where the audio now sits vs before: a move of the item, less a
      -- move of the start offset (Adjust: offset)
      local shift = (pos - s.pos) - (offs - s.offs) / (s.rate ~= 0 and s.rate or 1)
      local flipped = pol ~= s.pol
      if math.abs(shift) > 0.000005 or flipped then
        local m = by_name[s.name]
        if not m then m = { name = s.name, ms = shift * 1000, flipped = flipped }; by_name[s.name] = m; moved[#moved + 1] = m
        else m.flipped = m.flipped or flipped end
      end
    end
  end
  table.sort(moved, function(x, y) return math.abs(x.ms) > math.abs(y.ms) end)
  -- put the item selection back
  r.Main_OnCommand(40289, 0)
  for _, it in ipairs(a.prev) do if r.ValidatePtr(it, "MediaItem*") then r.SetMediaItemSelected(it, true) end end
  r.UpdateArrange()
  -- hit maps moved with their items; the kit check compares tracks, so
  -- re-run it where there are maps
  local checked = false
  if #moved > 0 then
    local kt = DT.kit_tracks()
    if #kt > 1 then
      r.PreventUIRefresh(1)
      for _, k in ipairs(kt) do pcall(DT.kit_check, k.track, { profile = DT.track_profile(k.track), kit = kt }) end
      r.PreventUIRefresh(-1)
      r.Undo_OnStateChange2(0, "TS DrumToolbox: re-check bleed after alignment")
      checked = true
    end
  end
  S.align_result = { when = os.date("%H:%M"), moved = moved, checked = checked }
  invalidate()
end

local function poll_align()
  local a = S.align
  if not a then return end
  local st = r.GetToggleCommandState(ALIGN_CMD)
  if st == 1 then a.seen_on = true end
  if a.seen_on and st == 0 then finish_align() end
end

-- ---------------------------------------------------------------------
-- align (DrumToolbox's own, on the hits)
-- ---------------------------------------------------------------------
local AOPT = { max_ms = 50, polarity = true, how = "items" }
do
  local _, v = r.GetProjExtState(0, "TS_DrumToolbox", "align_opts")
  local m, pol, how = (v or ""):match("^([%d%.]+)|(%d)|(%a+)$")
  if m then AOPT.max_ms, AOPT.polarity, AOPT.how = tonumber(m), pol == "1", how end
end
local function save_aopt()
  r.SetProjExtState(0, "TS_DrumToolbox", "align_opts",
    string.format("%g|%d|%s", AOPT.max_ms, AOPT.polarity and 1 or 0, AOPT.how))
end

-- What Align measured (and whether it was applied), kept in the project.
-- Tracks as their GUIDs.
function UI.save_outcome()
  local oc = S.outcome
  if not oc or not oc.list then r.SetProjExtState(0, "TS_DrumToolbox", "align_outcome", ""); return end
  local list = {}
  for _, o in ipairs(oc.list) do
    local rr = o.result
    list[#list + 1] = { guid = r.ValidatePtr(o.track, "MediaTrack*") and r.GetTrackGUID(o.track) or "", name = o.name, mode = o.mode,
      shift_ms = o.shift_ms, flip = o.flip, weak = o.weak, why = o.why, applied = o.applied,
      result = rr and { r = rr.r, n = rr.n, from = rr.from, keep = rr.keep, refined = rr.refined, ms = rr.ms, gain = rr.gain,
                        flip = rr.flip, weak = rr.weak, why = rr.why } or nil }
  end
  r.SetProjExtState(0, "TS_DrumToolbox", "align_outcome", DT.serialize({ list = list, when = oc.when, secs = oc.secs, applied = oc.applied }))
end
function UI.load_outcome()
  local _, v = r.GetProjExtState(0, "TS_DrumToolbox", "align_outcome")
  local t = DT.deserialize(v)
  if not t or not t.list then return nil end
  local out = { list = {}, when = t.when, secs = t.secs, applied = t.applied, loaded = true }
  for _, o in ipairs(t.list) do
    o.track = DT.track_by_guid(o.guid)
    if o.track then out.list[#out.list + 1] = o end
  end
  return #out.list > 0 and out or nil
end

local function start_measure()
  local kit = kit_now()
  local plan = DT.align_plan(kit)
  S.meas = { job = DT.align_job(plan, { max_ms = AOPT.max_ms, polarity = AOPT.polarity }), plan = plan, t0 = r.time_precise() }
  S.outcome = nil
end

local function run_measure()
  local m = S.meas
  if not m then return end
  if m.job:step(0.025) then
    S.meas = nil
    if m.job.error then
      S.outcome = { error = m.job.error }
    else
      S.outcome = { plan = m.plan, list = DT.align_outcome(m.plan, m.job.results), when = os.date("%H:%M"),
                    secs = r.time_precise() - m.t0 }
      UI.save_outcome()
    end
  end
end

local function apply_outcome()
  local oc = S.outcome
  if not oc or not oc.list then return end
  r.Undo_BeginBlock2(0)
  r.PreventUIRefresh(1)
  local done = DT.align_apply(oc.list, AOPT.how)
  -- hit maps moved with the audio; the bleed check compares tracks
  local kt = DT.kit_tracks()
  if #done > 0 and #kt > 1 then
    for _, k in ipairs(kt) do pcall(DT.kit_check, k.track, { profile = DT.track_profile(k.track), kit = kt }) end
  end
  r.PreventUIRefresh(-1)
  r.Undo_EndBlock2(0, "TS DrumToolbox: align the kit", -1)
  for _, o in ipairs(done) do o.applied = true end
  oc.applied = { n = #done, how = AOPT.how, when = os.date("%H:%M") }
  UI.al_msg, UI.al_n, UI.al_was = nil, nil, nil
  UI.save_outcome()
  invalidate()
end

-- ---------------------------------------------------------------------
-- detect (in the background)
-- ---------------------------------------------------------------------
-- which kit tracks Detect works on: all, less the ones unticked (kept in
-- the project as their GUIDs)
local untick = {}
do
  local _, v = r.GetProjExtState(0, "TS_DrumToolbox", "detect_off")
  for g in (v or ""):gmatch("[^;]+") do untick[g] = true end
end
local function ticked(e) return not untick[r.GetTrackGUID(e.track)] end
local function set_tick(e, on)
  untick[r.GetTrackGUID(e.track)] = (not on) or nil
  local out = {}
  for g in pairs(untick) do out[#out + 1] = g end
  r.SetProjExtState(0, "TS_DrumToolbox", "detect_off", table.concat(out, ";"))
end

local function start_detect(kit)
  local todo = {}
  for _, e in ipairs(kit) do
    if (e.role == "drum" or e.role == "bleed") and ticked(e) then todo[#todo + 1] = e end
  end
  if #todo == 0 then return end
  DT.store_suggested_roles()
  S.det = { todo = todo, i = 0, job = nil, done = {}, errors = {}, t0 = r.time_precise() }
  S.det_result = nil
end

local function finish_detect(cancelled)
  local d = S.det
  S.det = nil
  local lines = {}
  if #d.done > 0 then
    local kt = DT.kit_tracks()
    r.PreventUIRefresh(1)
    for _, e in ipairs(d.done) do
      local ok, k = pcall(DT.kit_check, e.track, { profile = e.profile, kit = kt })
      local hits = DT.track_hits(e.track)
      local review, red = 0, 0
      for _, h in ipairs(hits) do
        if (h.c or 1) < DT.C_HI then review = review + 1 end
        if (h.c or 1) < DT.C_MID then red = red + 1 end
      end
      local from = {}
      if ok then for nm, c in pairs(k.from) do from[#from + 1] = string.format("%d %s", c, nm) end end
      table.sort(from)
      lines[#lines + 1] = { name = e.name, detected = e.detected, hits = #hits, bleed = ok and k.discounted or 0,
                            from = table.concat(from, ", "), review = review, red = red, err = (not ok) and tostring(k) or nil }
    end
    r.PreventUIRefresh(-1)
  end
  r.UpdateArrange()
  r.Undo_OnStateChange2(0, "TS DrumToolbox: detect kit")
  S.det_result = { lines = lines, errors = d.errors, cancelled = cancelled, secs = r.time_precise() - d.t0, when = os.date("%H:%M") }
  pcall(function()   -- kept in the project for after a restart (plain values only)
    local keep = DT.deserialize(DT.serialize({ lines = lines, errors = d.errors, cancelled = cancelled, secs = S.det_result.secs, when = os.date("%d %b %H:%M") }))
    r.SetProjExtState(0, "TS_DrumToolbox", "det_result", DT.serialize(keep or {}))
  end)
  invalidate()
end

local function run_detect()
  local d = S.det
  if not d then return end
  if not d.job then
    d.i = d.i + 1
    local e = d.todo[d.i]
    if not e then finish_detect(false); return end
    d.job = DT.detect_job(e.track, { profile = e.profile, mode = "replace" })
  end
  if d.job:step(0.025) then
    local e = d.todo[d.i]
    if d.job.error then d.errors[#d.errors + 1] = e.name .. ": " .. d.job.error
    else e.detected = d.job.report.hits; d.done[#d.done + 1] = e end
    d.job = nil
  end
end

local function stop_detect()
  local d = S.det
  if d and d.job then d.job:cancel() end
  finish_detect(true)
end

-- ---------------------------------------------------------------------
-- drawing
-- ---------------------------------------------------------------------
local ROLE_ORDER = { "drum", "second", "bleed", "reference", "ignore" }

local function role_cell(e)
  local col = ROLE_COL[e.role] or COL.border
  ImGui.SetNextItemWidth(ctx, -1)
  ImGui.PushStyleColor(ctx, ImGui.Col_Text, e.role == "ignore" and COL.dim or COL.text)
  if ImGui.BeginCombo(ctx, "##role", DT.ROLE_LABEL[e.role] or e.role) then
    for _, ro in ipairs(ROLE_ORDER) do
      if ImGui.Selectable(ctx, DT.ROLE_LABEL[ro], ro == e.role) and ro ~= e.role then
        local prof, of = e.profile, nil
        if ro == "drum" or ro == "bleed" then prof = prof or DT.suggest_detect(e.track) end
        if ro == "second" then
          -- the drum in the same folder, else the first drum
          local _, drums = kit_now()
          for _, d in ipairs(drums) do if d.track ~= e.track and d.parent == e.parent then of = d.track; break end end
          if not of then for _, d in ipairs(drums) do if d.track ~= e.track then of = d.track; break end end end
        end
        set_role(e, ro, prof, of)
      end
    end
    ImGui.EndCombo(ctx)
  end
  ImGui.PopStyleColor(ctx)
  return col
end

local function of_cell(e, drums)
  if e.role ~= "second" then ImGui.TextDisabled(ctx, "-"); return end
  local cur = e.of and select(2, r.GetTrackName(e.of)) or "(choose)"
  ImGui.SetNextItemWidth(ctx, -1)
  if ImGui.BeginCombo(ctx, "##of", cur) then
    for _, d in ipairs(drums) do
      if d.track ~= e.track and ImGui.Selectable(ctx, d.name, d.track == e.of) then set_role(e, "second", nil, d.track) end
    end
    ImGui.EndCombo(ctx)
  end
end

local function profile_cell(e)
  if e.role ~= "drum" and e.role ~= "bleed" then ImGui.TextDisabled(ctx, "-"); return end
  ImGui.SetNextItemWidth(ctx, -1)
  if ImGui.BeginCombo(ctx, "##prof", e.profile or "Generic") then
    for _, p in ipairs(profiles) do
      if ImGui.Selectable(ctx, p, p == e.profile) then set_role(e, e.role, p, nil) end
    end
    ImGui.EndCombo(ctx)
  end
end

local function hitmap_cell(e)
  if e.role == "second" then
    ImGui.TextDisabled(ctx, "uses " .. (e.of and select(2, r.GetTrackName(e.of)) or "?"))
  elseif e.hits then
    ImGui.Text(ctx, string.format("%d hits", e.hits))
    if e.review > 0 then ImGui.SameLine(ctx); ImGui.TextColored(ctx, COL.mid, string.format("%d to review", e.review)) end
  elseif e.role == "drum" or e.role == "bleed" then
    ImGui.TextDisabled(ctx, "not detected")
  else
    ImGui.TextDisabled(ctx, "")
  end
end

local function align_cell(e)
  local res = S.align_result
  if not res or e.role == "ignore" then return end
  for _, m in ipairs(res.moved) do
    if m.name == e.name then
      ImGui.Text(ctx, string.format("%+.2f ms", m.ms))
      if m.flipped then ImGui.SameLine(ctx); ImGui.TextColored(ctx, COL.mid, "flipped") end
      return
    end
  end
  ImGui.TextDisabled(ctx, "unchanged")
end

-- column widths from their content (tables: content-sized columns, the
-- last one takes the rest)
local function tw(str) return (ImGui.CalcTextSize(ctx, str)) end
local function widest(list, f, extra)
  local w = 0
  for _, e in ipairs(list) do local v = tw(f(e)) + (extra and extra(e) or 0); if v > w then w = v end end
  return w
end
local function combo_w(text_w) return text_w + ImGui.GetFrameHeight(ctx) + 18 end
local FIXED = ImGui.TableColumnFlags_WidthFixed
local STRETCH = ImGui.TableColumnFlags_WidthStretch

local function draw_roles(kit, drums)
  UI.head("roles", "Roles", { help = "Suggested from the track names and folders.\nA role you set stays (its arrow puts the suggestion back).",
    menu = function()
      if ImGui.Selectable(ctx, "Every role back to the suggestion##resetall") then reset_all_roles(kit) end
    end })

  local show_ignored = S.show_ignored
  local flags = ImGui.TableFlags_RowBg | ImGui.TableFlags_BordersInnerH
  if ImGui.BeginTable(ctx, "roles", 6, flags) then
    local lh = ImGui.GetTextLineHeight(ctx)
    local names = widest(kit, function(e) return e.name end, function(e) return 8 + e.depth * 14 + (e.user and lh + 12 or 0) end)
    ImGui.TableSetupColumn(ctx, "Track", FIXED, math.max(tw("Track"), names) + 12)
    ImGui.TableSetupColumn(ctx, "Role", FIXED, combo_w(math.max(tw("Bleed source"), tw("Reference"))))
    ImGui.TableSetupColumn(ctx, "Second mic of", FIXED, combo_w(math.max(tw("Second mic of") - 30, widest(drums, function(e) return e.name end))))
    ImGui.TableSetupColumn(ctx, "Detection profile", FIXED, combo_w(math.max(tw("Detection profile") - 30, tw("Snare Bottom"), widest(kit, function(e) return e.profile or "" end))))
    ImGui.TableSetupColumn(ctx, "Hit map", FIXED, tw("9999 hits  99 to review") + 16)
    ImGui.TableSetupColumn(ctx, "Last alignment", STRETCH, 1)
    ImGui.TableHeadersRow(ctx)
    for i, e in ipairs(kit) do
      if e.role ~= "ignore" or show_ignored or e.user then
        ImGui.PushID(ctx, i)
        ImGui.TableNextRow(ctx)
        ImGui.TableNextColumn(ctx)
        -- name, with the folder depth and a role-coloured bar
        local x, y = ImGui.GetCursorScreenPos(ctx)
        local dl = ImGui.GetWindowDrawList(ctx)
        ImGui.DrawList_AddRectFilled(dl, x, y + 2, x + 3, y + ImGui.GetTextLineHeight(ctx) + 2, ROLE_COL[e.role] or COL.border, 1)
        ImGui.SetCursorScreenPos(ctx, x + 8 + e.depth * 14, y)
        if e.role == "ignore" then ImGui.TextDisabled(ctx, e.name) else ImGui.Text(ctx, e.name) end
        if e.user then
          ImGui.SameLine(ctx)
          if icon_button("##reset", "reset", "Set by hand - back to the suggestion", "flat", ImGui.GetTextLineHeight(ctx) + 2) then reset_role(e) end
        end
        ImGui.TableNextColumn(ctx); role_cell(e)
        ImGui.TableNextColumn(ctx); of_cell(e, drums)
        ImGui.TableNextColumn(ctx); profile_cell(e)
        ImGui.TableNextColumn(ctx); hitmap_cell(e)
        ImGui.TableNextColumn(ctx); align_cell(e)
        ImGui.PopID(ctx)
      end
    end
    ImGui.EndTable(ctx)
  end
  local rv, v = ImGui.Checkbox(ctx, "Show tracks that aren't part of the kit", S.show_ignored or false)
  if rv then S.show_ignored = v end
end

local MODE_LABEL = { leave = "Leave", ref = "Reference", to = "Align to", with = "Move with" }

local function plan_cell(p, kit)
  if p.mode == "ref" then ImGui.TextColored(ctx, COL.accent, "Reference"); return end
  local cur = p.mode == "leave" and "Leave" or (MODE_LABEL[p.mode] .. " " .. (p.target and select(2, r.GetTrackName(p.target)) or "?"))
  ImGui.SetNextItemWidth(ctx, -1)
  if ImGui.BeginCombo(ctx, "##plan", cur) then
    if ImGui.Selectable(ctx, "Leave", p.mode == "leave") then DT.set_align_entry(p.track, "leave", nil); S.outcome = nil end
    ImGui.Separator(ctx)
    for _, e in ipairs(kit) do
      if e.track ~= p.track and e.role ~= "ignore" then
        if ImGui.Selectable(ctx, "Align to " .. e.name, p.mode == "to" and p.target == e.track) then
          DT.set_align_entry(p.track, "to", e.track); S.outcome = nil
        end
      end
    end
    ImGui.Separator(ctx)
    for _, e in ipairs(kit) do
      if e.track ~= p.track and e.role ~= "ignore" then
        if ImGui.Selectable(ctx, "Move with " .. e.name, p.mode == "with" and p.target == e.track) then
          DT.set_align_entry(p.track, "with", e.track); S.outcome = nil
        end
      end
    end
    ImGui.EndCombo(ctx)
  end
end

local function toggle_icon(id, name, tooltip, on)
  return icon_button(id, name, tooltip, on and "main" or nil, 24)
end

-- Align's last Apply against the project as it is now: "after" (as
-- applied), "before" (undone, or put back), "edited" (moved since), or nil
-- (nothing applied). Checked when the project changes; an undo clears the
-- applied marks, a redo puts them back.
function UI.align_sync()
  local n = r.GetProjectStateChangeCount(0)
  if UI.al_n == n then return UI.al_state end
  UI.al_n = n
  local u = DT.align_undo_get()
  UI.al_u, UI.al_state = u, nil
  if not u then return nil end
  local sa, ta = DT.align_matches(u.after)
  local sb, tb = DT.align_matches(u.before)
  if tb > 0 and sb == tb and sa < ta then UI.al_state = "before"
  elseif ta > 0 and sa == ta and sb < tb then UI.al_state = "after"
  elseif ta > 0 then UI.al_state = "edited" end
  local oc = S.outcome
  if oc and oc.list then
    if UI.al_state == "before" and oc.applied then
      UI.al_was = oc.applied
      oc.applied = nil
      for _, o in ipairs(oc.list) do UI.al_was[o] = o.applied; o.applied = nil end
      UI.save_outcome()
    elseif UI.al_state == "after" and not oc.applied and UI.al_was then
      oc.applied = UI.al_was
      for _, o in ipairs(oc.list) do o.applied = UI.al_was[o] end
      UI.al_was = nil
      UI.save_outcome()
    end
  end
  return UI.al_state
end

-- Put back: every item Apply moved, exactly as it was before
function UI.align_put_back(kit)
  local u = DT.align_undo_get()
  if not u then return end
  r.Undo_BeginBlock2(0)
  r.PreventUIRefresh(1)
  local n, miss = DT.align_restore(u.before)
  local kt = DT.kit_tracks()
  if #kt > 1 then
    for _, k in ipairs(kt) do pcall(DT.kit_check, k.track, { profile = DT.track_profile(k.track), kit = kt }) end
  end
  r.PreventUIRefresh(-1)
  r.Undo_EndBlock2(0, "TS DrumToolbox: put the kit back as it was before Align", -1)
  UI.al_msg = string.format("Put back at %s: %d items as they were%s", os.date("%H:%M"), n,
    miss > 0 and string.format(" (%d since cut or deleted, left as they are)", miss) or "")
  UI.al_n = nil
  invalidate()
end

local function draw_align(kit)
  UI.head("align", "Align", { help = "Measured on the hits each pair of mics shares:\nsecond mics to their drum, overheads and the rest to the reference.\n"
    .. "Room mics are left where they are (their distance is their sound): set one to move in its Plan if you want it to." })
  local al_state = UI.align_sync()
  -- reference and options
  local ref = DT.align_reference(kit)
  ImGui.AlignTextToFramePadding(ctx); ImGui.Text(ctx, "Reference"); ImGui.SameLine(ctx)
  ImGui.SetNextItemWidth(ctx, 160)
  if ImGui.BeginCombo(ctx, "##ref", ref and select(2, r.GetTrackName(ref)) or "(none)") then
    for _, e in ipairs(kit) do
      if e.role == "drum" and ImGui.Selectable(ctx, e.name, e.track == ref) then DT.set_align_reference(e.track); S.outcome = nil end
    end
    ImGui.EndCombo(ctx)
  end
  ImGui.SameLine(ctx, 0, 20); ImGui.Text(ctx, "Max"); ImGui.SameLine(ctx)
  ImGui.SetNextItemWidth(ctx, 120)
  local ch, v = ImGui.SliderDouble(ctx, "##max", AOPT.max_ms, 1, 100, "%.0f ms")
  if UI.dbl() then ch, v = true, 50 end
  if ch then AOPT.max_ms = v; save_aopt(); S.outcome = nil end
  ImGui.SameLine(ctx, 0, 20)
  if toggle_icon("##pol", "polarity", AOPT.polarity and "Polarity flips allowed (click: never flip)" or "Polarity never flipped (click: allow)", AOPT.polarity) then
    AOPT.polarity = not AOPT.polarity; save_aopt(); S.outcome = nil
  end
  ImGui.SameLine(ctx, 0, 12)
  if toggle_icon("##items", "items", "Move the items", AOPT.how == "items") then AOPT.how = "items"; save_aopt() end
  ImGui.SameLine(ctx, 0, 4)
  if toggle_icon("##contents", "contents", "Move the audio inside the items (start offset); the items stay put", AOPT.how == "contents") then AOPT.how = "contents"; save_aopt() end

  -- the plan, and what measuring found
  local plan = DT.align_plan(kit)
  local oc = S.outcome
  local by = {}
  if oc and oc.list then for _, o in ipairs(oc.list) do by[o.track] = o end end
  local flags = ImGui.TableFlags_RowBg | ImGui.TableFlags_BordersInnerH
  if ImGui.BeginTable(ctx, "aplan", 5, flags) then
    local names = widest(plan, function(p) return p.name end)
    ImGui.TableSetupColumn(ctx, "Track", FIXED, math.max(tw("Track"), names) + 16)
    ImGui.TableSetupColumn(ctx, "Plan", FIXED, combo_w(tw("Move with ") + names))
    ImGui.TableSetupColumn(ctx, "Offset", FIXED, tw("+00.00 ms") + 16)
    ImGui.TableSetupColumn(ctx, "Polarity", FIXED, tw("Polarity") + 16)
    ImGui.TableSetupColumn(ctx, "Agreement", STRETCH, 1)
    ImGui.TableHeadersRow(ctx)
    for i, p in ipairs(plan) do
      ImGui.PushID(ctx, i)
      ImGui.TableNextRow(ctx)
      ImGui.TableNextColumn(ctx); ImGui.Text(ctx, p.name)
      ImGui.TableNextColumn(ctx); plan_cell(p, kit)
      local o = by[p.track]
      ImGui.TableNextColumn(ctx)
      if o and p.mode ~= "leave" and p.mode ~= "ref" then
        if o.weak then ImGui.TextDisabled(ctx, "-") else ImGui.Text(ctx, string.format("%+.2f ms", o.shift_ms)) end
      end
      ImGui.TableNextColumn(ctx)
      if o and o.flip and not o.weak then ImGui.TextColored(ctx, COL.mid, "flip") end
      ImGui.TableNextColumn(ctx)
      local rr = o and o.result
      if oc and oc.applied and o and p.mode ~= "leave" and p.mode ~= "ref" then
        -- after Apply: what was done
        if o.applied then
          ImGui.TextColored(ctx, COL.accent, string.format("applied: moved %+.2f ms as %s%s", o.shift_ms,
            oc.applied.how == "items" and "items" or "contents", o.flip and ", polarity flipped" or ""))
        elseif o.weak then
          ImGui.TextColored(ctx, COL.lo, "not moved: " .. (o.why or "weak"))
        else
          ImGui.TextDisabled(ctx, "not moved: already aligned")
        end
      elseif o and o.weak then
        ImGui.TextColored(ctx, COL.lo, o.why or "weak")
      elseif rr and rr.r then
        if rr.keep then
          ImGui.TextDisabled(ctx, string.format("already aligned%s · %.2f · %d hits of %s",
            rr.refined and math.abs(rr.ms or 0) >= 0.005 and " (fine-tuned)" or "", rr.r or 0, rr.n, rr.from or "?"))
        else
          local gain = (rr.gain or 0) > 9.99 and "doesn't sum where it is now"
            or string.format("sums %d%% better", math.floor((rr.gain or 0) * 100 + 0.5))
          if rr.tie then gain = gain .. string.format(" · close call with %+.1f ms: the smaller move", rr.alt_ms or 0) end
          ImGui.TextDisabled(ctx, string.format("%.2f · %s · %d hits of %s%s", rr.r or 0, gain, rr.n, rr.from or "?",
            (rr.alt_ms and not rr.tie) and string.format(" · also %+.1f ms", rr.alt_ms) or ""))
        end
      elseif o and p.mode == "with" then
        ImGui.TextDisabled(ctx, "same as " .. (p.target and select(2, r.GetTrackName(p.target)) or "?"))
      end
      ImGui.PopID(ctx)
    end
    ImGui.EndTable(ctx)
  end

  -- actions
  ImGui.Spacing(ctx)
  if S.meas then
    local j = S.meas.job
    ImGui.Text(ctx, "Measuring " .. (j.label or ""))
    ImGui.ProgressBar(ctx, j.progress or 0, -1, 0, string.format("%.0f%%", (j.progress or 0) * 100))
    if icon_button("##mstop", "stop", "Stop measuring") then S.meas.job:cancel(); S.meas = nil end
  else
    local has_hits = false
    for _, e in ipairs(kit) do if e.hits and e.hits > 0 then has_hits = true end end
    ImGui.BeginDisabled(ctx, not has_hits or S.det ~= nil)
    if icon_button("##measure", "measure", has_hits and "Measure the offsets" or "Detect the kit first: alignment is measured on its hits",
        oc and "" or "main") then start_measure() end
    ImGui.EndDisabled(ctx)
    ImGui.SameLine(ctx)
    local movers = 0
    for _, o in ipairs(oc and oc.list or {}) do
      if not o.weak and (math.abs(o.shift_ms or 0) >= DT.ALIGN_MIN_MS or o.flip) then movers = movers + 1 end
    end
    ImGui.BeginDisabled(ctx, not (oc and oc.list) or (oc and oc.applied ~= nil) or movers == 0)
    if icon_button("##apply", "check", AOPT.how == "items" and "Apply: move the items" or "Apply: move the audio inside the items",
        (oc and oc.list and not oc.applied and movers > 0) and "main" or nil) then apply_outcome() end
    ImGui.EndDisabled(ctx)
    ImGui.SameLine(ctx, 0, 24)
    ImGui.BeginDisabled(ctx, not CAN_ALIGN or S.det ~= nil)
    if icon_button("##reaper", "align", "Open REAPER's own Phase alignment instead (kit items selected)") then start_align(kit) end
    ImGui.EndDisabled(ctx)
    if oc and oc.error then ImGui.TextColored(ctx, COL.lo, oc.error) end
    -- after Apply: straight back, whenever (also Ctrl+Z while it's the last thing done)
    if al_state == "after" or al_state == "edited" then
      ImGui.SameLine(ctx, 0, 24)
      if ImGui.Button(ctx, "Put back##al_back") then UI.align_put_back(kit) end
      if ImGui.IsItemHovered(ctx) then
        ImGui.SetTooltip(ctx, "Every track Align moved, back exactly as it was before Apply (" .. (UI.al_u and UI.al_u.when or "") .. ")."
          .. (al_state == "edited" and "\nSome of them have been moved or edited since: those edits are undone too." or ""))
      end
    end
    if UI.al_msg and al_state ~= "after" then ImGui.TextColored(ctx, COL.label, UI.al_msg) end
    if oc and oc.applied then
      ImGui.TextColored(ctx, COL.accent, string.format("Applied at %s: %d tracks moved (%s) · hit maps moved with them · bleed re-checked",
        oc.applied.when, oc.applied.n, oc.applied.how == "items" and "items" or "contents"))
    elseif oc and oc.list and movers == 0 then
      UI.badge("al_none", "ok", "nothing to move", "Every track is already aligned, or marked in red")
    elseif oc and oc.list then
      UI.badge("al_n", "stale", string.format("%d to move", movers), string.format("Measured: %d track%s to move. Tracks marked in red aren't moved. Apply is one undo step.",
        movers, movers == 1 and "" or "s"))
    end
  end
  if S.align then
    ImGui.TextColored(ctx, COL.accent, string.format("REAPER's Phase alignment is open (%.0f s) - close it when done.", r.time_precise() - S.align.t0))
    if icon_button("##aligned", "check", "Done - REAPER's window is closed (if DrumToolbox didn't notice)") then finish_align() end
  end
  local res = S.align_result
  if res then
    if #res.moved == 0 then ImGui.TextDisabled(ctx, "REAPER's alignment (" .. res.when .. "): nothing moved.")
    else
      local parts = {}
      for i, m in ipairs(res.moved) do
        if i <= 6 then parts[#parts + 1] = string.format("%s %+.2f ms%s", m.name, m.ms, m.flipped and " flipped" or "") end
      end
      ImGui.TextWrapped(ctx, "REAPER's alignment (" .. res.when .. "): " .. table.concat(parts, " · "))
    end
  end
end

local function draw_detect(kit)
  local res0 = S.det_result
  UI.head("det", "Detect", { help = "Finds every hit on the ticked tracks, then discounts bleed across the kit.\nRuns in the background.",
    badges = { res0 and { #res0.errors > 0 and "warn" or (res0.cancelled and "off" or "ok"), res0.when,
      string.format("Last detection %s · %.0f s%s", res0.when, res0.secs, res0.cancelled and " · stopped" or "") } or nil }, nbadges = 1 })

  local rows, n_on = {}, 0
  for _, e in ipairs(kit) do
    if e.role == "drum" or e.role == "bleed" then
      rows[#rows + 1] = e
      if ticked(e) then n_on = n_on + 1 end
    end
  end
  local d = S.det
  local busy = d ~= nil or S.meas ~= nil
  -- last detection's per-track notes (bleed sources)
  local last = {}
  if S.det_result then for _, l in ipairs(S.det_result.lines) do last[l.name] = l end end

  -- actions
  if d then
    if icon_button("##stop", "stop", "Stop (tracks not reached keep their hit maps)") then stop_detect() end
  else
    ImGui.BeginDisabled(ctx, n_on == 0 or busy)
    if icon_button("##detect_kit", "detect", string.format("Detect the %d ticked track%s", n_on, n_on == 1 and "" or "s"), "main") then
      start_detect(kit)
    end
    ImGui.EndDisabled(ctx)
  end
  ImGui.SameLine(ctx, 0, 16)
  ImGui.BeginDisabled(ctx, busy)
  if icon_button("##tick_all", "tick_all", "Tick every track", nil, 24) then for _, e in ipairs(rows) do set_tick(e, true) end end
  ImGui.SameLine(ctx, 0, 4)
  if icon_button("##tick_none", "tick_none", "Untick every track", nil, 24) then for _, e in ipairs(rows) do set_tick(e, false) end end
  ImGui.EndDisabled(ctx)
  if d then
    local e = d.todo[d.i]
    local f = d.job and d.job.progress or 0
    ImGui.SameLine(ctx, 0, 16)
    ImGui.BeginGroup(ctx)
    ImGui.Text(ctx, string.format("%s  (%d of %d)  %.0f s", e and e.name or "", d.i, #d.todo, r.time_precise() - d.t0))
    ImGui.ProgressBar(ctx, ((d.i - 1) + f) / #d.todo, -1, 6, "")
    ImGui.EndGroup(ctx)
  end

  -- the kit's detected tracks
  local flags = ImGui.TableFlags_RowBg | ImGui.TableFlags_BordersInnerH
  if ImGui.BeginTable(ctx, "detect_tbl", 7, flags) then
    ImGui.TableSetupColumn(ctx, "", FIXED, 26)
    ImGui.TableSetupColumn(ctx, "Track", FIXED, math.max(tw("Track"),
      widest(rows, function(e) return e.name end, function(e) return 8 + (e.role == "bleed" and tw(" bleed source") + 8 or 0) end)) + 16)
    ImGui.TableSetupColumn(ctx, "Profile", FIXED, math.max(tw("Profile"), widest(rows, function(e) return e.profile or "" end)) + 16)
    ImGui.TableSetupColumn(ctx, "Hits", FIXED, tw("99999") + 24)
    ImGui.TableSetupColumn(ctx, "To review", FIXED, tw("999 (99 red)") + 16)
    ImGui.TableSetupColumn(ctx, "Bleed discounted", STRETCH, 1)
    ImGui.TableSetupColumn(ctx, "", FIXED, 26)
    ImGui.TableHeadersRow(ctx)
    for i, e in ipairs(rows) do
      ImGui.PushID(ctx, i)
      ImGui.TableNextRow(ctx)
      local running = d and d.todo[d.i] == e
      ImGui.TableNextColumn(ctx)
      ImGui.BeginDisabled(ctx, busy)
      local ch, v = ImGui.Checkbox(ctx, "##tick", ticked(e))
      if ch then set_tick(e, v) end
      ImGui.EndDisabled(ctx)
      ImGui.TableNextColumn(ctx)
      local x, y = ImGui.GetCursorScreenPos(ctx)
      local dl = ImGui.GetWindowDrawList(ctx)
      ImGui.DrawList_AddRectFilled(dl, x, y + 2, x + 3, y + ImGui.GetTextLineHeight(ctx) + 2, ROLE_COL[e.role] or COL.border, 1)
      ImGui.SetCursorScreenPos(ctx, x + 8, y)
      if ticked(e) then ImGui.Text(ctx, e.name) else ImGui.TextDisabled(ctx, e.name) end
      if e.role == "bleed" then ImGui.SameLine(ctx); ImGui.TextDisabled(ctx, "bleed source") end
      ImGui.TableNextColumn(ctx); ImGui.TextDisabled(ctx, e.profile or "")
      ImGui.TableNextColumn(ctx)
      if running then
        ImGui.ProgressBar(ctx, d.job and d.job.progress or 0, -1, 0, "")
      elseif e.hits then ImGui.Text(ctx, tostring(e.hits))
      else ImGui.TextDisabled(ctx, "-") end
      ImGui.TableNextColumn(ctx)
      if e.review and e.review > 0 then
        ImGui.TextColored(ctx, e.red > 0 and COL.lo or COL.mid, e.red > 0 and string.format("%d (%d red)", e.review, e.red) or tostring(e.review))
        if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "Go to the first one") end
        if ImGui.IsItemClicked(ctx) then jump_review(e) end
      elseif e.hits then ImGui.TextDisabled(ctx, "0") end
      ImGui.TableNextColumn(ctx)
      if e.bleed and e.bleed > 0 then
        local l = last[e.name]
        ImGui.Text(ctx, tostring(e.bleed))
        if l and l.from ~= "" then ImGui.SameLine(ctx); ImGui.TextDisabled(ctx, "(" .. l.from .. ")") end
      elseif e.hits then ImGui.TextDisabled(ctx, "0") end
      ImGui.TableNextColumn(ctx)
      if e.hits and not busy then
        if icon_button("##clear", "clear", "Clear this track's hit map", "flat", ImGui.GetTextLineHeight(ctx) + 4) then
          r.Undo_BeginBlock2(0); DT.clear_track(e.track); r.Undo_EndBlock2(0, "TS DrumToolbox: clear hit map", -1)
          invalidate()
        end
      end
      ImGui.PopID(ctx)
    end
    ImGui.EndTable(ctx)
  end
  if #rows == 0 then ImGui.TextDisabled(ctx, "No drums or bleed sources yet - give tracks their roles in the Kit tab.") end

  local res = S.det_result
  if res then
    for _, er in ipairs(res.errors) do ImGui.TextColored(ctx, COL.lo, er) end
  end
end


-- ---------------------------------------------------------------------
-- transport: a bar at the top, and REAPER's usual keys passed on (an
-- ImGui window keeps the keyboard while it has focus)
-- ---------------------------------------------------------------------
local ACT = { start = 40042, ["end"] = 40043, playstop = 40044, play = 1007, pause = 1008, stop = 1016,
              rep = 1068, undo = 40029, redo = 40030, save = 40026 }
local function act(id) r.Main_OnCommand(id, 0) end

UI.Q_UNDO = "TS DrumToolbox: quantise the kit"

local function draw_transport()
  local ps = r.GetPlayState()
  local playing, paused = ps & 1 == 1, ps & 2 == 2
  local sz = 24
  if icon_button("##t_start", "to_start", "Go to the start (Home)", nil, sz) then act(ACT.start) end
  ImGui.SameLine(ctx, 0, 4)
  -- the transport keeps its own colours, whatever the tab
  local T_PLAY, T_ON = 0x4cc9a6ff, 0x4a9edaff
  if icon_button("##t_play", playing and "pause" or "play", playing and "Pause" or "Play (Space: play / stop)", playing and "main" or nil, sz, T_PLAY) then
    act(playing and ACT.pause or ACT.play)
  end
  ImGui.SameLine(ctx, 0, 4)
  if icon_button("##t_stop", "stop", "Stop", nil, sz) then act(ACT.stop) end
  ImGui.SameLine(ctx, 0, 4)
  local rep_on = r.GetToggleCommandState(ACT.rep) == 1
  if icon_button("##t_rep", "loop", "Repeat (R)", rep_on and "main" or nil, sz, T_ON) then act(ACT.rep) end
  ImGui.SameLine(ctx, 0, 4)
  if icon_button("##t_follow", "follow", "The lanes follow the playhead", S.follow and "main" or nil, sz, T_ON) then
    S.follow = not S.follow
    r.SetExtState("TS_DrumToolbox", "follow", S.follow and "1" or "0", true)
  end
  ImGui.SameLine(ctx, 0, 14)
  local pos = (playing or paused) and r.GetPlayPosition() or r.GetCursorPosition()
  ImGui.AlignTextToFramePadding(ctx)
  ImGui.Text(ctx, r.format_timestr_pos(pos, "", 2))
  ImGui.SameLine(ctx, 0, 10)
  ImGui.TextDisabled(ctx, r.format_timestr_pos(pos, "", 0))
  if paused then ImGui.SameLine(ctx, 0, 10); ImGui.TextColored(ctx, COL.mid, "paused") end
end

-- REAPER's usual keys, when this window has the keyboard and nothing in
-- it is being typed into. (N, P, K, B, A, L, Enter, Del, Esc are the
-- lanes' own.)
local function pass_keys()
  if not ImGui.IsWindowFocused(ctx, K("FocusedFlags_RootAndChildWindows") or 3) then return end
  if ImGui.IsAnyItemActive(ctx) then return end
  local mods = ImGui.GetKeyMods and ImGui.GetKeyMods(ctx) or 0
  local ctrl = mods & (K("Mod_Ctrl", "Key_ModCtrl") or 0) ~= 0
  local shift = mods & (K("Mod_Shift", "Key_ModShift") or 0) ~= 0
  local function key(name) local k = K(name); return k and ImGui.IsKeyPressed(ctx, k, false) end
  if key("Key_Space") then act(ACT.playstop) end
  if ctrl and key("Key_Z") then act(shift and ACT.redo or ACT.undo) end
  if ctrl and key("Key_Y") then act(ACT.redo) end
  if ctrl and key("Key_S") then act(ACT.save) end
  if not ctrl and key("Key_R") then act(ACT.rep) end
  if key("Key_Home") then act(ACT.start) end
  if key("Key_End") then act(ACT["end"]) end
end

--@pro TS_DT_Pro_Window.lua:1

-- ---------------------------------------------------------------------
-- the lanes: one timeline, a lane per drum - the window's centre in every
-- tab; the tabs change what the lanes show and the
-- panel below them
-- ---------------------------------------------------------------------
local LANE = { head_w = 236, over_h = 18, ruler_h = 18, thin_h = 24, tall_min = 34, tall_max = 76 }
local HIT_COL = { hi = COL.hi, mid = COL.mid, lo = COL.lo }
local LOCK_COL = 0xe8ecf4ff
local WAVE_COL = 0x7f8899ff
local GRID_BEAT, GRID_BAR = 0x232833ff, 0x323846ff
local V = {}                 -- the view: t0, t1 (project time)
local PEAKS = {}             -- [track] = { key, hi, lo }
local KEY_MOD_SHIFT = K("Mod_Shift", "Key_ModShift") or 0
local KEY_MOD_CTRL = K("Mod_Ctrl", "Key_ModCtrl") or 0
local CHILD_NOSCROLL = (K("WindowFlags_NoScrollbar") or 0) | (K("WindowFlags_NoScrollWithMouse") or 0)
local BTN_LM = (K("ButtonFlags_MouseButtonLeft") or 1) | (K("ButtonFlags_MouseButtonMiddle") or 4)

local function clampv(x, a, b) if x < a then return a elseif x > b then return b end return x end

local function hit_col(h)
  if h.locked and not h.manual then return LOCK_COL end
  return HIT_COL[DT.conf_class(h.c)] or COL.mid
end

local function letter(name) return (name or "?"):match("%a") and (name:match("%a")):upper() or "?" end

-- hits within w seconds of t in a sorted list (binary search)
local function near(list, t, w)
  local out = {}
  if not list then return out end
  local lo, hi = 1, #list
  while lo <= hi do
    local mid = (lo + hi) // 2
    if list[mid].proj < t - w then lo = mid + 1 else hi = mid - 1 end
  end
  for i = lo, #list do
    local h = list[i]
    if h.proj > t + w then break end
    out[#out + 1] = h
  end
  return out
end

local function view()
  local a, b = cache.span0, cache.span1
  if not a then a, b = 0, 10 end
  if not V.t0 then V.t0, V.t1 = a, math.min(b, a + 10) end
  local span = clampv(V.t1 - V.t0, 0.05, math.max(0.05, b - a + 2))
  V.t0 = clampv(V.t0, a - 1, math.max(a - 1, b + 1 - span))
  V.t1 = V.t0 + span
  return V.t0, V.t1
end

local function zoom_at(t, f)
  view()
  V.t0 = t - (t - V.t0) * f
  V.t1 = t + (V.t1 - t) * f
end

local function pan(dt) V.t0 = V.t0 + dt; V.t1 = V.t1 + dt end

-- bring t into view (centred if it's off screen)
local function reveal(t)
  view()
  local span = V.t1 - V.t0
  if t < V.t0 + span * 0.05 or t > V.t1 - span * 0.05 then V.t0 = t - span / 2; V.t1 = V.t0 + span end
end

local function lane_peaks(track, t0, t1, n)
  local key = string.format("%.6f|%.6f|%d|%d", t0, t1, n, cache.state)
  local p = PEAKS[track]
  if not p or p.key ~= key then
    local hi, lo = DT.track_peaks(track, t0, t1, n)
    p = { key = key, hi = hi, lo = lo }
    PEAKS[track] = p
  end
  return p
end

-- the selected hit, found again after the cache is rebuilt
local function sel_hit()
  local s = S.sel
  if not s then return nil end
  if s.state == cache.state and s.hit then return s.hit end
  for _, e in ipairs(cache.kit or {}) do
    if e.track == s.track and e.hitlist then
      for _, h in ipairs(near(e.hitlist, s.proj, 0.002)) do
        s.hit, s.state, s.proj = h, cache.state, h.proj
        return h
      end
    end
  end
  s.hit = nil
  return nil
end

local function select_hit(h, show)
  if not h then S.sel = nil; return end
  S.sel = { track = h.lane.track, proj = h.proj, hit = h, state = cache.state }
  S.cur = h.lane.track
  S.bleed_from = nil
  if show then reveal(h.proj) end
end

-- the next / previous hit to review after the selection (or the cursor)
local function step_review(dir)
  local list = cache.review or {}
  if S.focus then
    local f = {}
    for _, x in ipairs(list) do if x.lane.track == S.focus then f[#f + 1] = x end end
    list = f
  end
  if #list == 0 then return end
  local h = sel_hit()
  local t = h and h.proj or r.GetCursorPosition()
  local pick
  if dir > 0 then
    for _, x in ipairs(list) do if x.proj > t + 1e-6 then pick = x; break end end
    pick = pick or list[1]
  else
    for i = #list, 1, -1 do if list[i].proj < t - 1e-6 then pick = list[i]; break end end
    pick = pick or list[#list]
  end
  select_hit(pick, true)
end

-- a track's first hit to review (from its header or the Detect table):
-- the lane comes into focus
jump_review = function(e)
  for _, h in ipairs(e.hitlist or {}) do
    if DT.needs_review(h) then S.focus = e.track; select_hit(h, true); return end
  end
end

-- what a hit coincides with on the other drums, strongest first
local function coincident(kit, h)
  local best
  for _, e in ipairs(kit) do
    if e.hitlist and e ~= h.lane then
      for _, x in ipairs(near(e.hitlist, h.proj, 0.005)) do
        if not best or (x.db or -99) > (best.hit.db or -99) then best = { lane = e, hit = x, dt = x.proj - h.proj } end
      end
    end
  end
  return best
end

-- why a hit is up for review, in a sentence or two
local function why(kit, h)
  local parts = {}
  local co = coincident(kit, h)
  if co then
    parts[#parts + 1] = string.format("Coincides with %s (%.1f dB, %+.1f ms).", co.lane.name, co.hit.db or 0, co.dt * 1000)
  end
  local own = h.lane.tilt_med
  if h.tilt and own then
    local other = co and co.lane.tilt_med
    if other and math.abs(h.tilt - other) < math.abs(h.tilt - own) then
      parts[#parts + 1] = string.format("Its tone is closer to %s's than to %s's own.", co.lane.name, h.lane.name)
    elseif math.abs(h.tilt - own) > 6 then
      parts[#parts + 1] = string.format("Its tone is %+.0f dB off %s's usual.", h.tilt - own, h.lane.name)
    end
  end
  if #parts == 0 then
    if h.manual then parts[1] = "Placed or moved by hand."
    elseif DT.needs_review(h) then parts[1] = "A softer or less clear strike than this drum's usual."
    else parts[1] = h.locked and "Kept and locked." or "A clear hit." end
  end
  return table.concat(parts, " "), co
end

-- ---- deciding --------------------------------------------------------
local function decided(label, fn, h)
  local t = h.proj
  r.Undo_BeginBlock2(0)
  fn()
  r.Undo_EndBlock2(0, "TS DrumToolbox: " .. label, -1)
  r.UpdateArrange()
  invalidate()
  kit_now()
  -- on to the next one to review
  S.sel = nil
  local list = {}
  for _, x in ipairs(cache.review or {}) do if not S.focus or x.lane.track == S.focus then list[#list + 1] = x end end
  for _, x in ipairs(list) do if x.proj > t + 1e-6 then select_hit(x, true); return end end
  if list[1] then select_hit(list[1], true) end
end

-- a missed hit, added by hand on a lane near time t
local function add_hit_at(lane, t)
  r.Undo_BeginBlock2(0)
  local at, err = DT.add_hit(lane.track, t)
  r.Undo_EndBlock2(0, "TS DrumToolbox: add hit", -1)
  r.UpdateArrange()
  invalidate()
  kit_now()
  if at then
    S.sel = { track = lane.track, proj = at, state = -1 }
    S.msg = nil
  else
    S.msg = "Couldn't add a hit: " .. (err or "?")
  end
end

local function keep_hit(h) decided("keep hit", function() DT.lock_hit(h) end, h) end
local function bleed_hit(h, from) decided("hit is bleed from " .. from, function() DT.discount_hit(h, from) end, h) end
local function delete_hit(h) decided("delete hit", function() DT.delete_hit(h) end, h) end

-- ---- listening -------------------------------------------------------
-- S.listen: "solo" (the drum and its second mics), "kit" (every kit mic),
-- "mix" (as it is). Solos are put back when playback stops.
local function solo_for(kit, lane)
  local set = {}
  if S.listen == "solo" then
    set[lane.track] = true
    for _, e in ipairs(kit) do if e.role == "second" and e.of == lane.track then set[e.track] = true end end
  elseif S.listen == "kit" then
    for _, e in ipairs(kit) do if e.role ~= "ignore" then set[e.track] = true end end
  end
  return set
end

local function aud_restore()
  local a = S.aud
  if not a then return end
  S.aud = nil
  if r.GetPlayState() & 1 == 1 then r.OnStopButton() end
  r.PreventUIRefresh(1)
  for t, v in pairs(a.solos or {}) do if r.ValidatePtr(t, "MediaTrack*") then r.SetMediaTrackInfo_Value(t, "I_SOLO", v) end end
  if a.loop then
    r.GetSet_LoopTimeRange2(0, true, true, a.loop[1], a.loop[2], false)
    r.GetSetRepeat(a.repeat_was)
  end
  if a.cur then r.SetEditCurPos(a.cur, false, false) end
  r.PreventUIRefresh(-1)
end

-- the solos for what's being heard, applied (again) while it plays: a
-- change of Solo / Kit / Full Mix takes effect at once, looping or not;
-- every solo touched is remembered once, to be put back
local function apply_solo(kit)
  local a = S.aud
  if not a then return end
  local set = solo_for(kit, a.lane)
  local any = next(set) ~= nil
  r.PreventUIRefresh(1)
  for i = 0, r.CountTracks(0) - 1 do
    local t = r.GetTrack(0, i)
    local cur = r.GetMediaTrackInfo_Value(t, "I_SOLO")
    local orig = a.solos[t]
    if orig == nil then orig = cur end
    local want = any and (set[t] and 2 or 0) or orig
    if cur ~= want then
      if a.solos[t] == nil then a.solos[t] = cur end
      r.SetMediaTrackInfo_Value(t, "I_SOLO", want)
    end
  end
  r.PreventUIRefresh(-1)
end

local function set_listen(kit, mode)
  S.listen = mode
  r.SetExtState("TS_DrumToolbox", "listen", mode, true)
  apply_solo(kit)
end

-- pre-roll before a hit (S.preroll): "none" (0.3 s), "beats2", "bar1",
-- "bar2" - in musical time, from the tempo map
local PREROLL = { { "none", "None" }, { "beats2", "2 beats" }, { "bar1", "1 bar" }, { "bar2", "2 bars" } }
local function preroll_start(t)
  local pr = S.preroll or "none"
  if pr == "none" then return t - 0.3 end
  local qn = r.TimeMap2_timeToQN(0, t)
  local _, meas = r.TimeMap2_timeToBeats(0, t)
  local _, q0, q1, num, den = r.TimeMap_GetMeasureInfo(0, meas)
  local lead
  if pr == "beats2" then lead = 2 * 4 / math.max(1, den or 4)
  else lead = (pr == "bar2" and 2 or 1) * (q1 - q0) end
  return r.TimeMap2_QNToTime(0, qn - lead)
end

local function audition(kit, h, loop)
  aud_restore()
  local a = { cur = r.GetCursorPosition(), t_start = r.time_precise(), lane = h.lane, solos = {} }
  S.aud = a
  apply_solo(kit)
  local start
  if loop then
    -- the hit's bar, and the pre-roll's bars before it
    local _, meas = r.TimeMap2_timeToBeats(0, h.proj)
    local _, m0 = r.TimeMap2_timeToBeats(0, preroll_start(h.proj) + 1e-6)
    if (S.preroll or "none") == "none" then m0 = meas end
    local b0 = r.TimeMap_GetMeasureInfo(0, math.min(m0, meas))
    local b1 = r.TimeMap_GetMeasureInfo(0, meas + 1)
    local l0, l1 = r.GetSet_LoopTimeRange2(0, false, true, 0, 0, false)
    a.loop = { l0, l1 }
    a.repeat_was = r.GetSetRepeat(-1)
    r.GetSet_LoopTimeRange2(0, true, true, b0, b1, false)
    r.GetSetRepeat(1)
    start = b0
  else
    start = preroll_start(h.proj)
    a.stop_at = a.t_start + (h.proj - start) + math.max(1.5, (h.dec or 0) / 1000 + 0.5)
  end
  r.SetEditCurPos(start, false, false)
  r.OnPlayButton()
end

local function poll_audition()
  local a = S.aud
  if not a then return end
  local now = r.time_precise()
  local playing = r.GetPlayState() & 1 == 1
  if (a.stop_at and now >= a.stop_at) or (not playing and now - a.t_start > 0.3) then aud_restore() end
end

-- ---- drawing ---------------------------------------------------------
local function draw_grid_and_ruler(dl, x0, x1, ry, rh, ly0, ly1, t2x)
  local t0, t1 = V.t0, V.t1
  local _, m0 = r.TimeMap2_timeToBeats(0, t0)
  local _, m1 = r.TimeMap2_timeToBeats(0, t1)
  local bars = {}
  for m = m0, math.min(m1 + 1, m0 + 4000) do
    local tm, q0, q1, num = r.TimeMap_GetMeasureInfo(0, m)
    bars[#bars + 1] = { m = m, t = tm, q0 = q0, q1 = q1, num = num }
  end
  if #bars == 0 then return end
  local barpx = (#bars > 1) and (t2x(bars[2].t) - t2x(bars[1].t)) or (x1 - x0)
  local beats = bars[1].num > 0 and barpx / bars[1].num >= 46
  local every = math.max(1, math.ceil(50 / math.max(1, barpx)))
  for _, b in ipairs(bars) do
    local x = t2x(b.t)
    if x >= x0 and x <= x1 then
      ImGui.DrawList_AddLine(dl, x, ly0, x, ly1, GRID_BAR, 1)
      if b.m % every == 0 then
        ImGui.DrawList_AddLine(dl, x, ry + rh - 6, x, ry + rh, COL.dim, 1)
        ImGui.DrawList_AddText(dl, x + 3, ry + 2, COL.label, string.format("%.0f", b.m + 1) .. (beats and ".1" or ""))
      end
    end
    if barpx / math.max(1, b.num) >= 12 then
      for k = 1, b.num - 1 do
        local q = b.q0 + (b.q1 - b.q0) * k / b.num
        local xb = t2x(r.TimeMap2_QNToTime(0, q))
        if xb >= x0 and xb <= x1 then
          ImGui.DrawList_AddLine(dl, xb, ly0, xb, ly1, GRID_BEAT, 1)
          ImGui.DrawList_AddLine(dl, xb, ry + rh - 3, xb, ry + rh, COL.border, 1)
          if beats then ImGui.DrawList_AddText(dl, xb + 3, ry + 2, COL.dim, string.format("%.0f.%.0f", b.m + 1, k + 1)) end
        end
      end
    end
  end
end

-- the overview: hit density over the whole kit, and the view's box
local function draw_overview(dl, x0, x1, y, h)
  local a, b = cache.span0, cache.span1
  if not a then return end
  local w = x1 - x0
  local n = math.max(1, math.floor(w / 3))
  if not cache.dens or cache.dens_n ~= n then
    local d, mx = {}, 1
    for i = 1, n do d[i] = 0 end
    for _, e in ipairs(cache.kit) do
      for _, hh in ipairs(e.hitlist or {}) do
        local i = math.floor((hh.proj - a) / (b - a) * n) + 1
        if i >= 1 and i <= n then d[i] = d[i] + 1; if d[i] > mx then mx = d[i] end end
      end
    end
    cache.dens, cache.dens_n, cache.dens_mx = d, n, mx
  end
  ImGui.DrawList_AddRectFilled(dl, x0, y, x1, y + h, COL.win)
  for i = 1, n do
    local v = cache.dens[i] / cache.dens_mx
    if v > 0 then
      local bx = x0 + (i - 1) * w / n
      ImGui.DrawList_AddRectFilled(dl, bx, y + h - 2 - v * (h - 4), bx + math.max(1, w / n - 1), y + h - 2, 0x4a5466ff)
    end
  end
  local vx0 = x0 + (V.t0 - a) / (b - a) * w
  local vx1 = x0 + (V.t1 - a) / (b - a) * w
  vx0, vx1 = clampv(vx0, x0, x1), clampv(vx1, x0, x1)
  if vx1 - vx0 < 3 then vx1 = vx0 + 3 end
  ImGui.DrawList_AddRectFilled(dl, vx0, y + 1, vx1, y + h - 1, (COL.accent & 0xffffff00) | 0x22)
  ImGui.DrawList_AddRect(dl, vx0, y + 1, vx1, y + h - 1, COL.accent, 2, 0, 1.5)
end

-- a lane's header: role bar, name, fader, solo and mute
local SM_TABS = setmetatable({}, { __index = function() return true end })
local SM_W = 40 + 58 + 6     -- solo, mute, a 58 px fader

local function lane_header(dl, e, x, y, w, h, tall, mini, focused)
  local wr = SM_TABS[S.tab] and (w - SM_W) or w   -- right edge for text
  ImGui.DrawList_AddRectFilled(dl, x, y, x + w, y + h - 1, focused and COL.chip_on or COL.head)
  ImGui.DrawList_AddRectFilled(dl, x, y + 3, x + 3, y + h - 4, ROLE_COL[e.role] or COL.border)
  -- the current drum (Level / Gate / Enhance / Reinforce follow it)
  if e.track == S.cur and (S.tab == "level" or S.tab == "gate" or S.tab == "enhance" or S.tab == "reinforce") then
    ImGui.DrawList_AddRect(dl, x + 0.5, y + 0.5, x + w - 0.5, y + h - 1.5, COL.accent, 2, 0, 1.5)
  end
  local lh = ImGui.GetTextLineHeight(ctx)
  local ty = (tall and not mini) and y + 6 or y + (h - lh) / 2 - 1
  -- the name, cut short (…) before whatever sits right of it on its line
  local tag = (not tall and not mini) and (e.role == "second" and "second" or (e.role == "reference" and "reference" or e.role)) or nil
  local room = wr - 18 - (tag and (ImGui.CalcTextSize(ctx, tag)) + 8 or 0)
  local name = e.name
  if (ImGui.CalcTextSize(ctx, name)) > room then
    while #name > 1 and (ImGui.CalcTextSize(ctx, name .. "…")) > room do name = name:sub(1, -2) end
    name = name .. "…"
  end
  ImGui.DrawList_AddText(dl, x + 10, ty, tall and COL.text or COL.label, name)
  if name ~= e.name and ImGui.IsMouseHoveringRect(ctx, x, y, x + wr, y + lh + 8) then ImGui.SetTooltip(ctx, e.name) end
  if mini then
    if (e.review or 0) > 0 then
      local s2 = tostring(e.review)
      local tw2 = (ImGui.CalcTextSize(ctx, s2))
      local rx = x + wr - tw2 - 8
      ImGui.DrawList_AddText(dl, rx, ty, e.red > 0 and COL.lo or COL.mid, s2)
      return { rx - 2, ty - 1, rx + tw2 + 2, ty + lh + 1 }
    end
    return
  end
  if not tall then
    local tw2 = (ImGui.CalcTextSize(ctx, tag))
    ImGui.DrawList_AddText(dl, x + wr - tw2 - 8, ty, COL.dim, tag)
    return
  end
  local y2 = ty + lh + 3
  -- what's on the drum: a line of its own under the rest, right-aligned
  -- (left out when the lane is too short for it)
  if e.role == "drum" and e.hitlist and S.tab ~= "kit" then
    local y3 = y2 + lh + 4
    if y3 + lh <= y + h - 2 then UI.stage_icons(dl, e, x + w - 8, y3 + 1, lh - 2) end
  end
  if S.tab == "align" and S.outcome and S.outcome.list then
    for _, o in ipairs(S.outcome.list) do
      if o.track == e.track then
        local txt = o.weak and (o.why or "not moved") or string.format("%+.2f ms%s", o.shift_ms, o.flip and "  flip" or "")
        ImGui.DrawList_AddText(dl, x + 10, y2, o.weak and COL.lo or COL.accent, txt)
        return
      end
    end
  end
  if S.tab == "kit" then
    ImGui.DrawList_AddText(dl, x + 10, y2, COL.dim, (e.profile or "") .. "  ·  " .. e.role)
    return
  end
--@pro TS_DT_Pro_Window.lua:2
  local s1 = string.format("%d hits", e.hits or 0)
  ImGui.DrawList_AddText(dl, x + 10, y2, COL.dim, s1)
  local cx = x + 10 + (ImGui.CalcTextSize(ctx, s1)) + 8
  local rev
  if (e.review or 0) > 0 then
    local s2 = string.format("%d review", e.review)
    local tw2 = (ImGui.CalcTextSize(ctx, s2))
    ImGui.DrawList_AddText(dl, cx, y2, e.red > 0 and COL.lo or COL.mid, s2)
    ImGui.DrawList_AddLine(dl, cx, y2 + lh, cx + tw2, y2 + lh, (e.red > 0 and COL.lo or COL.mid) & 0xffffff66, 1)
    rev = { cx - 2, y2 - 1, cx + tw2 + 2, y2 + lh + 1 }
    cx = cx + tw2 + 8
  end
  if (e.bleed or 0) > 0 then ImGui.DrawList_AddText(dl, cx, y2, COL.dim, string.format("%d bleed", e.bleed)) end
  return rev
end

local function draw_hits(dl, e, x0, x1, y, h, t2x, selected, compact)
  local lh = ImGui.GetTextLineHeight(ctx)
  -- bleed: dotted line, and the source's letter at the bottom
  for _, b in ipairs(compact and {} or near(e.bleedlist, (V.t0 + V.t1) / 2, (V.t1 - V.t0) / 2 + 0.01)) do
    local x = t2x(b.proj)
    for yy = y + 4, y + h - 16, 5 do ImGui.DrawList_AddLine(dl, x, yy, x, yy + 2, 0x76808f99, 1) end
    local cy = y + h - 9
    local bs = S.sel_bleed and S.sel_bleed.take == b.take and math.abs(S.sel_bleed.srcpos - b.srcpos) < 1e-6
    ImGui.DrawList_AddCircleFilled(dl, x, cy, 6.5, bs and COL.chip_on or COL.win)
    ImGui.DrawList_AddCircle(dl, x, cy, bs and 8 or 6.5, bs and COL.text or COL.dim, 16, bs and 2 or 1)
    local l = letter(b.from)
    local lw = (ImGui.CalcTextSize(ctx, l))
    ImGui.DrawList_AddText(dl, x - lw / 2, cy - lh / 2, COL.label, l)
  end
  -- hits: a line in the confidence colour, the level on a chip
  local last_lx = -1e9
  for _, hh in ipairs(near(e.hitlist, (V.t0 + V.t1) / 2, (V.t1 - V.t0) / 2 + 0.01)) do
    local x = t2x(hh.proj)
    local col = hit_col(hh)
    if S.tab == "level" or S.tab == "gate" then col = COL.dim end
    local sel = hh == selected
    ImGui.DrawList_AddLine(dl, x, y + 2, x, y + h - 2, sel and COL.text or ((col & 0xffffff00) | 0xcc), sel and 2.5 or 1.5)
    local txt = hh.db and string.format("%.1f", hh.db) or "DT"
    local lp = S.tab == "level" and S.lplans and S.lplans[e.track]
    local lkey = string.format("%.6f", hh.proj)
    local lx = lp and lp.by[lkey]
    if lx then
      -- the hit's gain: a bar up (boost) or down (cut) from the middle;
      -- set by hand (dragged): purple
      local dragging = S.ldrag and S.ldrag.track == e.track and S.ldrag.key == lkey
      local g = dragging and S.ldrag.gain or lx.gain
      local hand = lx.hand or dragging
      local mid, half = y + h / 2, h / 2 - 4
      local gh = clampv(g / 12, -1, 1) * half
      if lx.ghost and not hand then
        ImGui.DrawList_AddCircle(dl, x, mid, 3, COL.dim, 10, 1)
        txt, col = "ghost", COL.dim
      elseif math.abs(g) >= 0.05 or hand then
        local bc = hand and COL.second or (g > 0 and COL.accent or COL.lo)
        ImGui.DrawList_AddRectFilled(dl, x - 2, math.min(mid, mid - gh), x + 2, math.max(mid, mid - gh) + 1, bc, 1)
        txt, col = string.format("%+.1f", g), bc
      else
        txt = "0.0"
      end
    end
    local tw2 = (ImGui.CalcTextSize(ctx, txt)) + 6
    if not compact and (x - last_lx > tw2 + 2 or sel) then
      ImGui.DrawList_AddRectFilled(dl, x, y + 2, x + tw2, y + 2 + lh, col, 2)
      ImGui.DrawList_AddText(dl, x + 3, y + 2, 0x11131aff, txt)
      if sel then ImGui.DrawList_AddRect(dl, x - 1, y + 1, x + tw2 + 1, y + 3 + lh, COL.text, 2, 0, 1.5) end
      last_lx = x
    end
  end
end

local function draw_lanes(kit)
  local X, Y = ImGui.GetCursorScreenPos(ctx)
  local W, H = ImGui.GetContentRegionAvail(ctx)
  local dl = ImGui.GetWindowDrawList(ctx)
  local HW = LANE.head_w
  local x0, x1 = X + HW, X + W
  if x1 - x0 < 50 then return end
  local t0, t1 = view()
  local function t2x(t) return x0 + (t - t0) / (t1 - t0) * (x1 - x0) end
  local function x2t(x) return t0 + (x - x0) / (x1 - x0) * (t1 - t0) end

  -- lanes and their heights
  local lanes, ntall, nthin = {}, 0, 0
  for _, e in ipairs(kit) do
    if e.role ~= "ignore" then
      local tall = e.hitlist ~= nil
      lanes[#lanes + 1] = { e = e, tall = tall }
      if tall then ntall = ntall + 1 else nthin = nthin + 1 end
    end
  end
  local oy, ry = Y, Y + LANE.over_h + 2
  local ly0 = ry + LANE.ruler_h + 2
  local room = Y + H - ly0
  -- a focused lane (its header clicked) takes the room; the other drums
  -- shrink to a strip with their hits
  local focus
  for _, l in ipairs(lanes) do if l.tall and l.e.track == S.focus then focus = l end end
  if S.focus and not focus then S.focus = nil end
  local MINI = 28
  local tall_h = ntall > 0 and clampv((room - nthin * LANE.thin_h) / ntall, LANE.tall_min, LANE.tall_max) or 0
  local focus_h = focus and math.max(LANE.tall_min * 2, room - nthin * LANE.thin_h - (ntall - 1) * MINI) or 0
  local ly1 = ly0
  for _, l in ipairs(lanes) do
    l.y = ly1
    if not l.tall then l.h = LANE.thin_h
    elseif focus then l.mini = l ~= focus; l.h = l.mini and MINI or focus_h
    else l.h = tall_h end
    ly1 = ly1 + l.h
  end
  ly1 = math.min(ly1, Y + H)

  -- backgrounds
  ImGui.DrawList_AddRectFilled(dl, X, Y, X + W, Y + H, COL.win)
  ImGui.DrawList_AddText(dl, X + 8, oy + 2, COL.dim, "WHOLE SONG")
  draw_overview(dl, x0, x1, oy, LANE.over_h)
  ImGui.DrawList_AddRectFilled(dl, x0, ry, x1, ry + LANE.ruler_h, COL.panel)
  if #lanes == 0 then
    ImGui.DrawList_AddText(dl, x0 + 10, ly0 + 10, COL.dim, "No kit yet - give tracks their roles in the Kit tab.")
  end

  ImGui.DrawList_PushClipRect(dl, x0, ry, x1, Y + H, true)
  draw_grid_and_ruler(dl, x0, x1, ry, LANE.ruler_h, ly0, ly1, t2x)
  ImGui.DrawList_PopClipRect(dl)

  local selected = sel_hit()
  for i, l in ipairs(lanes) do
    local e = l.e
    if l.y < Y + H then
      local bottom = math.min(l.y + l.h, Y + H)
      l.rev = lane_header(dl, e, X, l.y, HW - 4, l.h, l.tall, l.mini, l == focus)
      ImGui.DrawList_PushClipRect(dl, x0, l.y, x1, bottom, true)
      if i % 2 == 0 then ImGui.DrawList_AddRectFilled(dl, x0, l.y, x1, l.y + l.h, 0xffffff04) end
      -- waveform (sqrt-scaled so bleed shows)
      local n = math.floor(x1 - x0)
      local pk = lane_peaks(e.track, t0, t1, n)
      local mid, half = l.y + l.h / 2, l.h / 2 - 3
      -- Gate tab: the drum's (or its drum's) gate over the view
      local gpl, gi, go
--@pro TS_DT_Pro_Window.lua:3
      for c = 1, n do
        local a, b = pk.hi[c], -pk.lo[c]
        if a > 0.0005 or b > 0.0005 then
          local xc = x0 + c - 0.5
          if gi then
            -- what's removed, faint; what gets through (by the drum band's
            -- gain), drawn normally
            ImGui.DrawList_AddLine(dl, xc, mid - math.sqrt(a) * half, xc, mid + math.sqrt(b) * half + 1, 0x7f889940, 1)
            local g = math.sqrt(gi[c])
            ImGui.DrawList_AddLine(dl, xc, mid - math.sqrt(a) * half * g, xc, mid + math.sqrt(b) * half * g + 1, WAVE_COL, 1)
          else
            ImGui.DrawList_AddLine(dl, xc, mid - math.sqrt(a) * half, xc, mid + math.sqrt(b) * half + 1, WAVE_COL, 1)
          end
        end
      end
      if gi then
        -- the gate's lines: drum band (solid) and everything else (faint),
        -- from the floor (-60 dB, the lane's foot) to open (its top)
        local function gy(g) return l.y + 2 + clampv(-20 * math.log(math.max(g, 1e-6), 10) / 60, 0, 1) * (l.h - 4) end
        local pxi, pyi, pyo
        for c = 1, n, 2 do
          local xc = x0 + c - 0.5
          local yi, yo = gy(gi[c]), gy(go[c])
          if pxi then
            ImGui.DrawList_AddLine(dl, pxi, pyo, xc, yo, (COL.accent & 0xffffff00) | 0x77, 1)
            ImGui.DrawList_AddLine(dl, pxi, pyi, xc, yi, COL.accent, 1.5)
          end
          pxi, pyi, pyo = xc, yi, yo
        end
        -- hits that won't open it
        if l.tall and gpl then
          for _, x in ipairs(gpl.hits) do
            if not x.open and x.proj >= t0 and x.proj <= t1 then
              local xx = t2x(x.proj)
              ImGui.DrawList_AddLine(dl, xx - 4, l.y + l.h - 10, xx + 4, l.y + l.h - 2, COL.mid, 1.5)
              ImGui.DrawList_AddLine(dl, xx + 4, l.y + l.h - 10, xx - 4, l.y + l.h - 2, COL.mid, 1.5)
            end
          end
        end
      end
      -- Quantise with a time selection: outside it is dimmed (nothing there
      -- is cut, moved or grabbable)
      if S.tab == "quant" then
        local q0, q1 = r.GetSet_LoopTimeRange(false, false, 0, 0, false)
        if q1 > q0 then
          local a, b = t2x(q0), t2x(q1)
          if a > x0 then ImGui.DrawList_AddRectFilled(dl, x0, l.y, math.min(a, x1), l.y + l.h, 0x0b0d12b0) end
          if b < x1 then ImGui.DrawList_AddRectFilled(dl, math.max(b, x0), l.y, x1, l.y + l.h, 0x0b0d12b0) end
        end
      end
      -- Quantise: the grid across the lanes; where a dragged hit will land
      if S.tab == "quant" then
        local qo = UI.qo or DT.quant_opts()
        local step = DT.quant_step(qo)
        local q0 = r.TimeMap2_timeToQN(0, t0)
        local q1 = r.TimeMap2_timeToQN(0, t1)
        if (q1 - q0) / step < (x1 - x0) / 4 then
          local g = math.ceil(q0 / step) * step
          while g <= q1 do
            local gx = t2x(r.TimeMap2_QNToTime(0, g))
            ImGui.DrawList_AddLine(dl, gx, l.y, gx, l.y + l.h, 0x6cc06a22, 1)
            g = g + step
          end
        end
        if UI.qgrab and UI.qgrab.target then
          local gx = t2x(UI.qgrab.target)
          ImGui.DrawList_AddLine(dl, gx, l.y, gx, l.y + l.h, COL.accent_hi, 2)
          local hx = t2x(UI.qgrab.hit)
          ImGui.DrawList_AddLine(dl, hx, l.y, hx, l.y + l.h, 0xffffff40, 1)
        end
      end
      if l.tall then draw_hits(dl, e, x0, x1, l.y, l.h, t2x, selected, l.mini)
      elseif S.tab == "level" and S.lplans then
        -- a second mic: its own gains, or (dim) its drum's that it follows
        local pl = S.lplans[e.track]
        local follows = not pl and e.of and S.lplans[e.of]
        pl = pl or follows
        if pl then
          local mid2, half2 = l.y + l.h / 2, l.h / 2 - 2
          for _, x in ipairs(pl.hits) do
            if x.proj >= t0 and x.proj <= t1 and not x.ghost and math.abs(x.gain) >= 0.05 then
              local xx = t2x(x.proj)
              local gh = clampv(x.gain / 12, -1, 1) * half2
              local c = x.gain > 0 and COL.accent or COL.lo
              if follows then c = (c & 0xffffff00) | 0x66 end
              ImGui.DrawList_AddRectFilled(dl, xx - 1.5, math.min(mid2, mid2 - gh), xx + 1.5, math.max(mid2, mid2 - gh) + 1, c)
            end
          end
        end
      end
      ImGui.DrawList_AddLine(dl, x0, l.y + l.h - 0.5, x1, l.y + l.h - 0.5, COL.border, 1)
      ImGui.DrawList_PopClipRect(dl)
    end
  end

  -- the edit / play cursor (Follow: the view pages along with playback)
  local playing = r.GetPlayState() & 1 == 1
  local pc = playing and r.GetPlayPosition() or r.GetCursorPosition()
  if playing and S.follow and not S.aud and (pc < t0 or pc > t1 - (t1 - t0) * 0.05) then
    local span = t1 - t0
    V.t0, V.t1 = pc - span * 0.05, pc + span * 0.95
  end
  if pc >= t0 and pc <= t1 then
    local px = t2x(pc)
    ImGui.DrawList_AddLine(dl, px, ry, px, ly1, playing and 0xffffffcc or COL.accent, 1)
  end

  -- ---- mouse ----
  local wheel_v, wheel_h = ImGui.GetMouseWheel(ctx)
  local mods = ImGui.GetKeyMods and ImGui.GetKeyMods(ctx) or 0
  local mx, my = ImGui.GetMousePos(ctx)
  local function wheel(hovered)
    if not hovered then return end
    if (wheel_h or 0) ~= 0 then pan(-(wheel_h) * (t1 - t0) * 0.1) end
    if (wheel_v or 0) ~= 0 then
      if mods & KEY_MOD_SHIFT ~= 0 then pan(-wheel_v * (t1 - t0) * 0.1)
      else zoom_at(x2t(mx), 0.82 ^ wheel_v) end
    end
  end
  -- overview: click or drag to move the view there
  ImGui.SetCursorScreenPos(ctx, x0, oy)
  ImGui.InvisibleButton(ctx, "##over", x1 - x0, LANE.over_h)
  if ImGui.IsItemActive(ctx) and cache.span0 then
    local tc = cache.span0 + (mx - x0) / (x1 - x0) * (cache.span1 - cache.span0)
    local span = t1 - t0
    V.t0, V.t1 = tc - span / 2, tc + span / 2
  end
  if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "The whole song: click or drag to move the view") end
  wheel(ImGui.IsItemHovered(ctx))
  -- ruler: drag to scroll, click to place the edit cursor
  ImGui.SetCursorScreenPos(ctx, x0, ry)
  if ImGui.InvisibleButton(ctx, "##ruler", x1 - x0, LANE.ruler_h) then r.SetEditCurPos(x2t(mx), false, false) end
  if ImGui.IsItemActive(ctx) then
    local dx = ImGui.GetMouseDelta(ctx)
    if dx ~= 0 then pan(-dx / (x1 - x0) * (t1 - t0)) end
  end
  wheel(ImGui.IsItemHovered(ctx))
  -- lanes: hover a hit for its details, click to select it, double-click
  -- to hear it; click elsewhere to place the edit cursor; middle-drag to
  -- scroll; wheel zooms (Shift: scrolls)
  local lh_total = math.max(1, ly1 - ly0)
  ImGui.SetCursorScreenPos(ctx, x0, ly0)
  local clicked = ImGui.InvisibleButton(ctx, "##lanes", x1 - x0, lh_total, BTN_LM)
  local hov = ImGui.IsItemHovered(ctx)
  local hover_hit
  UI.hover_bleed = nil
  if hov then
    for _, l in ipairs(lanes) do
      if l.tall and my >= l.y and my < l.y + l.h then
        local best, bd
        for _, hh in ipairs(near(l.e.hitlist, x2t(mx), 6 / (x1 - x0) * (t1 - t0))) do
          local d = math.abs(t2x(hh.proj) - mx)
          if not bd or d < bd then best, bd = hh, d end
        end
        hover_hit = best
        if not best and not l.mini then
          for _, b in ipairs(near(l.e.bleedlist or {}, x2t(mx), 7 / (x1 - x0) * (t1 - t0))) do
            if math.abs(t2x(b.proj) - mx) <= 7 then UI.hover_bleed = { b = b, e = l.e } end
          end
        end
      end
    end
    if hover_hit and S.tab == "level" and not S.ldrag then
      local lp = S.lplans and S.lplans[hover_hit.lane.track]
      local lx = lp and lp.by[string.format("%.6f", hover_hit.proj)]
      if lx then
        ImGui.SetTooltip(ctx, string.format("%s  %.1f dB  ·  gain %+.1f dB%s\ndrag up / down to set it by hand (Shift: fine)%s",
          hover_hit.lane.name, hover_hit.db or 0, lx.gain, lx.hand and " (by hand)" or (lx.ghost and " (ghost note)" or ""),
          lx.hand and "\nright-click: back to the leveller" or ""))
      end
    elseif not hover_hit and UI.hover_bleed then
      local b = UI.hover_bleed.b
      ImGui.SetTooltip(ctx, string.format("Bleed in %s from %s  %.1f dB\nclick to select it: make it a hit, or blame another drum", UI.hover_bleed.e.name, b.from or "?", b.db or 0))
    elseif hover_hit then
      ImGui.SetTooltip(ctx, string.format("%s  %.1f dB\nconfidence %.2f%s%s", hover_hit.lane.name, hover_hit.db or 0,
        hover_hit.c or 1, hover_hit.dec and string.format("  ·  decay %.0f ms", hover_hit.dec) or "",
        hover_hit.locked and "  ·  locked" or ""))
    end
  end
--@pro TS_DT_Pro_Window.lua:4
  -- Quantise: grab a hit of the selected drum in its lane and drag it
  -- (snaps to the grid unless Snap is off; Shift: free); on release the
  -- whole kit is cut around it and crossfaded - one undo step
  if S.tab == "quant" then
    UI.qgrab_hover = nil
    if hov and not UI.qgrab then
      for _, l in ipairs(lanes) do
        if l.e.track == S.cur and l.tall and my >= l.y and my < l.y + l.h and l.e.hitlist then
          local best, bd
          for _, hh in ipairs(near(l.e.hitlist, x2t(mx), 6 / (x1 - x0) * (t1 - t0))) do
            local dd = math.abs(t2x(hh.proj) - mx)
            if dd <= 6 and (not bd or dd < bd) then best, bd = hh, dd end
          end
          if best then UI.qgrab_hover = { hit = best.proj, e = l.e } end
        end
      end
    end
    local gh = UI.qgrab_hover
    if (gh or UI.qgrab) and ImGui.SetMouseCursor then ImGui.SetMouseCursor(ctx, K("MouseCursor_ResizeEW") or 4) end
    if gh then
      hover_hit = nil; UI.hover_bleed = nil
      if ImGui.IsMouseClicked(ctx, 0) then UI.qgrab = { hit = gh.hit, e = gh.e }; UI.q_ate = true
      else ImGui.SetTooltip(ctx, gh.e.name .. " hit: drag it to move it (the whole kit is cut and crossfaded around it)") end
    end
    if UI.qgrab then
      if ImGui.IsMouseDown(ctx, 0) then
        local qo = UI.qo or DT.quant_opts()
        local t = x2t(mx)
        if qo.snap and (mods & KEY_MOD_SHIFT) == 0 then
          local step = DT.quant_step(qo)
          t = r.TimeMap2_QNToTime(0, math.floor(r.TimeMap2_timeToQN(0, t) / step + 0.5) * step)
        end
        UI.qgrab.target = t
        ImGui.SetTooltip(ctx, string.format("%+.1f ms%s", (t - UI.qgrab.hit) * 1000, (qo.snap and (mods & KEY_MOD_SHIFT) == 0) and " (on the grid; Shift: free)" or ""))
      else
        local g = UI.qgrab
        UI.qgrab = nil
        if g.target and math.abs(g.target - g.hit) > 0.0001 then
          r.Undo_BeginBlock2(0)
          r.PreventUIRefresh(1)
          local moved, gaps, gat = DT.quant_move_one(kit, UI.qo or DT.quant_opts(), g.hit, g.target)
          UI.qgaps, UI.qgap_i = gat or {}, 0
          r.PreventUIRefresh(-1)
          r.Undo_EndBlock2(0, "TS DrumToolbox: move a " .. g.e.name .. " hit", -1)
          UI.qmsg = { gaps > 0 and "warn" or "ok", string.format("%+.1f ms", (g.target - g.hit) * 1000),
            string.format("Moved a %s hit %+.1f ms: %d slices%s. Undo: Ctrl+Z.", g.e.name, (g.target - g.hit) * 1000, moved,
            gaps > 0 and string.format(", %d gaps left where there was no earlier audio to fill them", gaps) or "") }
          invalidate(); UI.qkey = nil; NSYNC.state = nil
        end
      end
    end
  end
  if not ImGui.IsMouseDown(ctx, 0) and not clicked then UI.q_ate = nil end
  if ImGui.IsItemActive(ctx) and ImGui.IsMouseDown(ctx, 2) then
    local dx = ImGui.GetMouseDelta(ctx)
    if dx ~= 0 then pan(-dx / (x1 - x0) * (t1 - t0)) end
  end
  if clicked and UI.q_ate then UI.q_ate = nil
  elseif clicked and not ImGui.IsMouseDown(ctx, 2) then
    if hover_hit then select_hit(hover_hit); S.sel_bleed = nil
    elseif UI.hover_bleed then
      local b = UI.hover_bleed.b
      S.sel_bleed = { take = b.take, srcpos = b.srcpos, proj = b.proj, from = b.from, db = b.db, lane = UI.hover_bleed.e }
      S.sel = nil; S.cur = UI.hover_bleed.e.track
      if S.tab ~= "detect" then S.tab = "detect" end
    else r.SetEditCurPos(x2t(mx), false, false) end
  end
  if hov and ImGui.IsMouseDoubleClicked(ctx, 0) and not (S.tab == "quant" and UI.qhover) then
    if hover_hit then audition(kit, hover_hit, false)
    else
      for _, l in ipairs(lanes) do
        if l.tall and my >= l.y and my < l.y + l.h then add_hit_at(l.e, x2t(mx)) end
      end
    end
  end
  wheel(hov)
  -- Quantise: if the view is all outside the time selection, say so
  if S.tab == "quant" then
    local q0, q1 = r.GetSet_LoopTimeRange(false, false, 0, 0, false)
    if q1 > q0 and (q1 < t0 or q0 > t1) then
      local msg = string.format("Outside the time selection (%s - %s): nothing is quantised here. Clear the selection to do the whole song.",
        r.format_timestr_pos(q0, "", 2), r.format_timestr_pos(q1, "", 2))
      local tw = ImGui.CalcTextSize(ctx, msg)
      local mxp, myp = x0 + (x1 - x0 - tw) / 2, ly0 + 8
      ImGui.DrawList_AddRectFilled(dl, mxp - 8, myp - 4, mxp + tw + 8, myp + 18, 0x1d2027f0, 4)
      ImGui.DrawList_AddText(dl, mxp, myp, COL.accent, msg)
    end
  end
  -- headers: click a drum's header to select it in REAPER
  for _, l in ipairs(lanes) do
    if l.y < Y + H then
      ImGui.SetCursorScreenPos(ctx, X, l.y)
      local hit_rev = l.rev and mx >= l.rev[1] and mx <= l.rev[3] and my >= l.rev[2] and my <= l.rev[4]
      local sm = SM_TABS[S.tab]
      if ImGui.InvisibleButton(ctx, "##head" .. tostring(l.e.track), HW - 4 - (sm and SM_W or 0), math.max(1, math.min(l.h, Y + H - l.y))) then
        if hit_rev then jump_review(l.e)
        else
          r.SetOnlyTrackSelected(l.e.track)
          S.cur = l.e.track
          if l.tall then S.focus = (S.focus ~= l.e.track) and l.e.track or nil end
        end
      end
      if ImGui.IsItemHovered(ctx) then
        if hit_rev then ImGui.SetTooltip(ctx, "Go to " .. l.e.name .. "'s first hit to review")
        elseif l.tall then ImGui.SetTooltip(ctx, (S.focus == l.e.track and "Back to every lane" or ("Enlarge " .. l.e.name)) .. " (and select it in REAPER)")
        else ImGui.SetTooltip(ctx, "Select " .. l.e.name .. " in REAPER") end
      end
      -- solo / mute: the track's own (REAPER's), on the header's right
      if sm and l.y + 4 < Y + H then
        local bs = math.min(16, l.h - 6)
        local by = l.tall and not l.mini and l.y + 5 or l.y + (l.h - bs) / 2
        local bx = X + HW - 4 - SM_W + 3
        local tr = l.e.track
        -- the fader: REAPER's own curve, drag; double-click 0 dB
        do
          local vol = r.GetMediaTrackInfo_Value(tr, "D_VOL")
          local db = vol > 0 and 20 * math.log(vol, 10) or -150
          local function d2p(d) if r.DB2SLIDER then return clampv(r.DB2SLIDER(d) / 1000, 0, 1) end return clampv((d + 60) / 72, 0, 1) end
          local function p2d(p) if r.SLIDER2DB then return r.SLIDER2DB(p * 1000) end return p * 72 - 60 end
          ImGui.SetCursorScreenPos(ctx, bx, by)
          ImGui.InvisibleButton(ctx, "##vol" .. tostring(tr), 58, bs)
          local hv, act_ = ImGui.IsItemHovered(ctx), ImGui.IsItemActive(ctx)
          local p = d2p(db)
          if hv and ImGui.IsMouseDoubleClicked(ctx, 0) then
            r.SetMediaTrackInfo_Value(tr, "D_VOL", 1); p = d2p(0); db = 0
          elseif act_ then
            local dx = ImGui.GetMouseDelta(ctx)
            if dx ~= 0 then
              local fine = (ImGui.GetKeyMods(ctx) & (K("Mod_Shift") or 0)) ~= 0 and 0.15 or 1
              p = clampv(p + dx / 58 * fine, 0, 1)
              db = p2d(p)
              r.SetMediaTrackInfo_Value(tr, "D_VOL", db <= -149 and 0 or 10 ^ (db / 20))
            end
          end
          if hv or act_ then ImGui.SetTooltip(ctx, string.format("%s: %s dB\n(drag; Shift: fine; double-click: 0 dB)", l.e.name, db <= -149 and "-inf" or string.format("%+.1f", db))) end
          local cy = by + bs / 2
          ImGui.DrawList_AddRectFilled(dl, bx, cy - 2, bx + 58, cy + 2, COL.chip, 2)
          ImGui.DrawList_AddRectFilled(dl, bx, cy - 2, bx + 58 * p, cy + 2, (hv or act_) and COL.accent_hi or COL.accent, 2)
          local u = bx + 58 * d2p(0)
          ImGui.DrawList_AddLine(dl, u, cy - 4, u, cy + 4, COL.dim, 1)        -- 0 dB
          local kx = bx + 58 * p
          ImGui.DrawList_AddRectFilled(dl, kx - 2, by + 1, kx + 2, by + bs - 1, COL.text, 1)
          bx = bx + 58 + 6
        end
        local function smb(id, label, on, on_col, tip_, fn)
          ImGui.SetCursorScreenPos(ctx, bx, by)
          if ImGui.InvisibleButton(ctx, id .. tostring(tr), bs, bs) then fn() end
          local hv = ImGui.IsItemHovered(ctx)
          if hv then ImGui.SetTooltip(ctx, tip_) end
          ImGui.DrawList_AddRectFilled(dl, bx, by, bx + bs, by + bs, on and on_col or (hv and COL.chip_hov or COL.chip), 3)
          ImGui.DrawList_AddRect(dl, bx + 0.5, by + 0.5, bx + bs - 0.5, by + bs - 0.5, COL.edge, 3)
          local lw = (ImGui.CalcTextSize(ctx, label))
          ImGui.DrawList_AddText(dl, bx + (bs - lw) / 2, by + (bs - ImGui.GetTextLineHeight(ctx)) / 2, on and 0x11131aff or COL.label, label)
          bx = bx + bs + 3
        end
        local soloed = r.GetMediaTrackInfo_Value(tr, "I_SOLO") ~= 0
        local muted = r.GetMediaTrackInfo_Value(tr, "B_MUTE") ~= 0
        -- a drum's S and M take its second mics, noise and samples with it
        local group = DT.support_tracks and DT.support_tracks(tr) or {}
        local nsec = 0
        if l.e.role ~= "second" then
          for _, k in ipairs(kit) do
            if k.role == "second" and k.of == tr then group[#group + 1] = k.track; nsec = nsec + 1 end
          end
        end
        local with = #group > 1 and (nsec > 0 and " (with its second mic, noise and samples)" or " (with its noise and samples)") or ""
        smb("##solo", "S", soloed, 0xe3c341ff, (soloed and "Unsolo " or "Solo ") .. l.e.name .. with, function()
          for _, t in ipairs(group) do r.CSurf_OnSoloChange(t, soloed and 0 or 1) end
        end)
        smb("##mute", "M", muted, COL.lo, (muted and "Unmute " or "Mute ") .. l.e.name .. with, function()
          for _, t in ipairs(group) do r.CSurf_OnMuteChange(t, muted and 0 or 1) end
        end)
      end
    end
  end
end

-- where A / the add button puts a hit: the focused lane, else the
-- selected hit's
local function add_lane()
  for _, e in ipairs(cache.kit or {}) do if S.focus and e.track == S.focus and e.hitlist then return e end end
  local h = sel_hit()
  return h and h.lane
end

-- ---- keys (anywhere in the window) -----------------------------------
local function lane_keys(kit)
  if not ImGui.IsWindowFocused(ctx, K("FocusedFlags_RootAndChildWindows") or 3) then return end
  if ImGui.IsAnyItemActive(ctx) then return end
  local function key(name) local k = K(name); return k and ImGui.IsKeyPressed(ctx, k, false) end
  if key("Key_N") then step_review(1) end
  if key("Key_P") then step_review(-1) end
  if key("Key_Escape") then S.focus = nil end
  local h = sel_hit()
  if S.tab == "detect" and key("Key_A") then
    local lane = add_lane()
    if lane then add_hit_at(lane, r.GetCursorPosition()) end
  end
  if not h then return end
  if key("Key_Enter") then audition(kit, h, false) end
  if key("Key_L") then if S.aud then aud_restore() else audition(kit, h, true) end end
  if S.tab == "detect" then
    if key("Key_K") then keep_hit(h) end
    if key("Key_Delete") then delete_hit(h) end
    if key("Key_B") then
      local _, co = why(kit, h)
      local from = S.bleed_from or (co and co.lane.name)
      if from then bleed_hit(h, from) end
    end
  end
end

-- ---- the Detect tab's selected-hit strip ------------------------------
-- a word button for a choice (Solo / Kit / Full Mix): accent when on
local function choice(label, on, tooltip)
  if on then
    ImGui.PushStyleColor(ctx, K("Col_Button"), COL.accent)
    ImGui.PushStyleColor(ctx, K("Col_ButtonHovered"), COL.accent_hi)
    ImGui.PushStyleColor(ctx, K("Col_Text"), 0x0e1015ff)
  end
  local c = ImGui.Button(ctx, label)
  if on then ImGui.PopStyleColor(ctx, 3) end
  if tooltip and ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, tooltip) end
  return c
end

-- a bleed mark picked in the lanes: make it a hit, blame another drum, or
-- drop it
function UI.draw_bleed(kit)
  local sb = S.sel_bleed
  UI.head("sb", "Bleed mark", { help = "A hit discounted as bleed from another drum.\nMake it a hit, blame another drum, or forget it." })
  ImGui.Text(ctx, string.format("in %s  ·  bar %s  ·  %.3f s", sb.lane.name, r.format_timestr_pos(sb.proj, "", 2), sb.proj))
  ImGui.TextDisabled(ctx, string.format("level %.1f dB · put down to %s", sb.db or 0, sb.from or "?"))
  local function done(label, fn)
    r.Undo_BeginBlock2(0); fn(); r.Undo_EndBlock2(0, "TS DrumToolbox: " .. label, -1)
    S.sel_bleed = nil; invalidate()
  end
  if ImGui.Button(ctx, "It's a hit##bl_hit") then
    done("bleed mark is a hit", function() DT.restore_bleed(sb.lane.track, { sb }) end)
    return
  end
  if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, sb.lane.name .. " played here: back on its hit map, locked") end
  ImGui.SameLine(ctx, 0, 8)
  ImGui.TextDisabled(ctx, "Bleed from"); ImGui.SameLine(ctx, 0, 6)
  ImGui.SetNextItemWidth(ctx, 150)
  if ImGui.BeginCombo(ctx, "##bl_from", sb.from or "?") then
    for _, e in ipairs(kit) do
      if e.track ~= sb.lane.track and (e.role == "drum" or e.role == "bleed") then
        if ImGui.Selectable(ctx, e.name, e.name == sb.from) and e.name ~= sb.from then
          local nm = e.name
          done("bleed mark from " .. nm, function() DT.set_bleed(sb, nm) end)
        end
      end
    end
    ImGui.EndCombo(ctx)
  end
  ImGui.SameLine(ctx, 0, 8)
  if ImGui.Button(ctx, "Forget it##bl_drop") then done("forget a bleed mark", function() DT.set_bleed(sb, false) end) end
  if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "Drop the record (a later detection may find it again)") end
  ImGui.SameLine(ctx, 0, 8)
  if ImGui.SmallButton(ctx, "Back to hits##bl_back") then S.sel_bleed = nil end
end

local function draw_selected(kit)
  if S.sel_bleed then UI.draw_bleed(kit) return end
  local h = sel_hit()
  local nrev = #(cache.review or {})
  UI.head("sh", "Hit", { help = "Click a hit in the lanes, or N for the next to review.\nDouble-click a lane to add a missed hit.",
    badges = { nrev > 0 and { "stale", tostring(nrev), string.format("%d hits to review: N for the next, P for the previous", nrev), function() step_review(1) end } or nil }, nbadges = 1 })
  local reason, co
  if h then
    local where = r.format_timestr_pos(h.proj, "", 2)
    ImGui.Text(ctx, string.format("%s  ·  bar %s  ·  %.3f s", h.lane.name, where, h.proj))
    reason, co = why(kit, h)
    local tone = (h.tilt and h.lane.tilt_med) and string.format("%+.1f dB", h.tilt - h.lane.tilt_med) or "-"
    ImGui.TextDisabled(ctx, "level"); ImGui.SameLine(ctx); ImGui.Text(ctx, h.db and string.format("%.1f dB", h.db) or "-")
    ImGui.SameLine(ctx, 0, 18); ImGui.TextDisabled(ctx, "tone"); ImGui.SameLine(ctx); ImGui.Text(ctx, tone)
    ImGui.SameLine(ctx, 0, 18); ImGui.TextDisabled(ctx, "decay"); ImGui.SameLine(ctx); ImGui.Text(ctx, h.dec and string.format("%.0f ms", h.dec) or "-")
    ImGui.SameLine(ctx, 0, 18); ImGui.TextDisabled(ctx, "confidence"); ImGui.SameLine(ctx)
    ImGui.TextColored(ctx, hit_col(h), string.format("%.2f%s", h.c or 1, h.locked and "  locked" or ""))
    ImGui.TextDisabled(ctx, reason)
  else
    ImGui.TextDisabled(ctx, "-")
  end
  if S.msg then ImGui.TextColored(ctx, COL.lo, S.msg) end

  -- decide
  UI.sub("Decide"); ImGui.SameLine(ctx, 0, 10)
  ImGui.BeginDisabled(ctx, not h)
  if icon_button("##keep", "lock", "Keep & lock (K)", "main", 26) and h then keep_hit(h) end
  ImGui.SameLine(ctx)
  local from = S.bleed_from or (co and co.lane.name)
  if icon_button("##bleed", "bleed", from and ("Bleed from " .. from .. " (B)") or "Bleed - pick where from", nil, 26) and h and from then
    bleed_hit(h, from)
  end
  ImGui.SameLine(ctx, 0, 4)
  ImGui.SetNextItemWidth(ctx, 120)
  if ImGui.BeginCombo(ctx, "##from", from or "from...") then
    for _, e in ipairs(kit) do
      if e.role == "drum" and (not h or e ~= h.lane) then
        if ImGui.Selectable(ctx, e.name, from == e.name) then S.bleed_from = e.name end
      end
    end
    ImGui.EndCombo(ctx)
  end
  ImGui.SameLine(ctx)
  if icon_button("##del", "clear", "Delete the hit (Del)", nil, 26) and h then delete_hit(h) end
  ImGui.EndDisabled(ctx)
  ImGui.SameLine(ctx, 0, 14)
  if icon_button("##prev", "prev", "Previous to review (P)" .. (S.focus and " on this lane" or ""), nil, 26) then step_review(-1) end
  ImGui.SameLine(ctx)
  if icon_button("##next", "next", "Next to review (N)" .. (S.focus and " on this lane" or ""), nil, 26) then step_review(1) end
  ImGui.SameLine(ctx, 0, 14)
  local al = add_lane()
  ImGui.BeginDisabled(ctx, not al)
  if icon_button("##add", "add", al and ("Add a missed hit on " .. al.name .. " at the edit cursor (A) - or double-click the lane")
      or "Add a missed hit: double-click the lane where it is (or focus a lane, then A)", nil, 26) and al then
    add_hit_at(al, r.GetCursorPosition())
  end
  ImGui.EndDisabled(ctx)

  -- listen
  ImGui.SameLine(ctx, 0, 24); UI.sub("Listen"); ImGui.SameLine(ctx, 0, 10)
  ImGui.BeginDisabled(ctx, not h and not S.aud)
  if icon_button("##hear", "play", "Hear the hit (Enter, or double-click it)", S.aud and not S.aud.loop and "main" or nil, 26) then
    if S.aud then aud_restore() elseif h then audition(kit, h, false) end
  end
  ImGui.SameLine(ctx)
  if icon_button("##loop", "loop", "Loop its bar (L) - again to stop", S.aud and S.aud.loop and "main" or nil, 26) then
    if S.aud then aud_restore() elseif h then audition(kit, h, true) end
  end
  ImGui.EndDisabled(ctx)
  ImGui.SameLine(ctx, 0, 12)
  local LM = { "solo", "kit", "mix" }
  local lp = UI.seg("listen", { "Solo", "Kit", "Full mix" }, S.listen == "kit" and 2 or S.listen == "mix" and 3 or (S.listen == "solo" and 1 or nil),
    { "The drum alone, with its second mics", "Every kit mic", "The mix as it is" })
  if lp then set_listen(kit, LM[lp]) end
  ImGui.SameLine(ctx, 0, 16)
  ImGui.TextDisabled(ctx, "Pre-roll"); ImGui.SameLine(ctx, 0, 6)
  local pl_lab, pl_tip, pl_cur = {}, {}, 1
  for i, pr in ipairs(PREROLL) do
    pl_lab[i] = pr[2]
    pl_tip[i] = pr[1] == "none" and "Start just before the hit" or ("Start " .. pr[2] .. " before the hit")
    if (S.preroll or "none") == pr[1] then pl_cur = i end
  end
  local pp = UI.seg("preroll", pl_lab, pl_cur, pl_tip)
  if pp then
    S.preroll = PREROLL[pp][1]
    r.SetExtState("TS_DrumToolbox", "preroll", PREROLL[pp][1], true)
  end
end

--@pro TS_DT_Pro_Window.lua:5

-- a handle that does nothing in this mode: a grey x where it would be
function UI.dead_handle(dl, x, y)
  ImGui.DrawList_AddLine(dl, x - 3.5, y - 3.5, x + 3.5, y + 3.5, COL.dim, 1.6)
  ImGui.DrawList_AddLine(dl, x - 3.5, y + 3.5, x + 3.5, y - 3.5, COL.dim, 1.6)
end

-- ---- Quantise -----------------------------------------------------------
-- How far the cut points sit from the grid (as a share of half a step),
-- drawn: before (grey) and after (accent); the window - which ones move -
-- shaded, its edges dragged. Gives true when the window changed.
function UI.quant_graph(pts, o, w, h)
  local x, y = ImGui.GetCursorScreenPos(ctx)
  local dl = ImGui.GetWindowDrawList(ctx)
  ImGui.InvisibleButton(ctx, "##qgraph", w, h)
  local hv, act_ = ImGui.IsItemHovered(ctx), ImGui.IsItemActive(ctx)
  local function fx(f) return x + w / 2 + clampv(f, -1, 1) * (w / 2 - 8) end
  local mx = ImGui.GetMousePos(ctx)
  local changed = false
  if act_ then
    local f = math.abs((mx - x - w / 2) / (w / 2 - 8))
    o.window = math.floor(clampv(f, 0.02, 1) * 100 + 0.5)
    changed = true
  end
  ImGui.DrawList_AddRectFilled(dl, x, y, x + w, y + h, COL.field, 4)
  local wl, wr = fx(-o.window / 100), fx(o.window / 100)
  ImGui.DrawList_AddRectFilled(dl, wl, y + 2, wr, y + h - 14, (COL.accent & 0xffffff00) | 0x1c)
  ImGui.DrawList_AddLine(dl, wl, y + 2, wl, y + h - 14, (hv or act_) and COL.accent_hi or COL.accent, (hv or act_) and 2 or 1)
  ImGui.DrawList_AddLine(dl, wr, y + 2, wr, y + h - 14, (hv or act_) and COL.accent_hi or COL.accent, (hv or act_) and 2 or 1)
  ImGui.DrawList_AddLine(dl, fx(0), y + 2, fx(0), y + h - 14, COL.dim, 1)
  -- the bins: signed share of half a step, before and after
  local NB = 40
  local before, after = {}, {}
  for i = 1, NB do before[i], after[i] = 0, 0 end
  local step_s = nil
  for _, p in ipairs(pts) do
    if p.other then goto skip end
    local sgn = p.dev >= 0 and 1 or -1
    local fb = sgn * p.frac
    local fa = p.moves and fb * (1 - o.strength / 100) or fb
    local ib = clampv(math.floor((fb + 1) / 2 * NB) + 1, 1, NB)
    local ia = clampv(math.floor((fa + 1) / 2 * NB) + 1, 1, NB)
    before[ib] = before[ib] + 1; after[ia] = after[ia] + 1
    ::skip::
  end
  local top = 1
  for i = 1, NB do top = math.max(top, before[i], after[i]) end
  local bw = (w - 16) / NB
  for i = 1, NB do
    local bx = x + 8 + (i - 1) * bw
    local hb = before[i] / top * (h - 20)
    local ha = after[i] / top * (h - 20)
    if hb > 0 then ImGui.DrawList_AddRectFilled(dl, bx + 1, y + h - 14 - hb, bx + bw - 1, y + h - 14, 0x8a93a060) end
    if ha > 0 then ImGui.DrawList_AddRectFilled(dl, bx + bw * 0.3, y + h - 14 - ha, bx + bw * 0.7, y + h - 14, COL.accent) end
  end
  ImGui.DrawList_AddText(dl, x + 6, y + h - 13, COL.dim, "early")
  ImGui.DrawList_AddText(dl, fx(0) - 10, y + h - 13, COL.dim, "grid")
  ImGui.DrawList_AddText(dl, x + w - 36, y + h - 13, COL.dim, "late")
  if hv or act_ then
    ImGui.SetTooltip(ctx, string.format("Grey: where the cut points sit against the grid (to half a step either side).\n"
      .. "Accent: where they'll be. Shaded: the window - hits within %d%% of half a step move;\nthe rest (pushes, fills) stay put. Drag its edges.", o.window))
  end
  return changed
end

-- The cut before a hit, drawn: the slice before fading out, the moved
-- slice (its transient at 0) fading in, the cut `pre_ms` before the hit,
-- the crossfade `xfade_ms` long, the flam window `merge_ms` after it. Drag
-- the cut, the crossfade's end or the flam bracket. Gives changed, released.
function UI.join_view(o, w, h)
  local x, y = ImGui.GetCursorScreenPos(ctx)
  ImGui.InvisibleButton(ctx, "##q_join", w, h)
  local hv, act_ = ImGui.IsItemHovered(ctx), ImGui.IsItemActive(ctx)
  if hv or act_ then UI.cursor("ew") end
  local done = ImGui.IsItemDeactivated(ctx)
  local dl = ImGui.GetWindowDrawList(ctx)
  -- ms to x: -24 .. 0 over the left 55%, 0 .. 90 over the rest
  local xz = x + w * 0.55
  local function X(ms) if ms <= 0 then return xz + ms / 24 * (xz - x - 6) end return xz + ms / 90 * (x + w - 6 - xz) end
  local function MS(px) if px <= xz then return (px - xz) / (xz - x - 6) * 24 end return (px - xz) / (x + w - 6 - xz) * 90 end
  local mx, my = ImGui.GetMousePos(ctx)
  local cut, xe, mg = X(-o.pre_ms), X(-o.pre_ms + o.xfade_ms), X(o.merge_ms)
  local top, bot = y + 6, y + h - 16
  local mid = (top + bot) / 2
  UI.jv = UI.jv or {}
  if ImGui.IsItemActivated(ctx) then
    local best, bd = nil, 1e9
    for k, px in pairs({ pre = cut, xf = xe, merge = mg }) do
      local d = math.abs(mx - px)
      if d < bd then best, bd = k, d end
    end
    UI.jv.what = best
  end
  local changed = false
  if act_ and UI.jv.what then
    local ms = MS(mx)
    if UI.jv.what == "pre" then
      local v = math.floor(clampv(-ms, 1, 20) * 10 + 0.5) / 10
      if v ~= o.pre_ms then o.pre_ms = v; o.xfade_ms = math.min(o.xfade_ms, v - 0.5); changed = true end
    elseif UI.jv.what == "xf" then
      local v = math.floor(clampv(ms + o.pre_ms, 0.5, math.min(10, o.pre_ms - 0.5)) * 10 + 0.5) / 10
      if v ~= o.xfade_ms then o.xfade_ms = v; changed = true end
    else
      local v = math.floor(clampv(ms, 5, 80) + 0.5)
      if v ~= o.merge_ms then o.merge_ms = v; changed = true end
    end
    cut, xe, mg = X(-o.pre_ms), X(-o.pre_ms + o.xfade_ms), X(o.merge_ms)
  end
  ImGui.DrawList_AddRectFilled(dl, x, y, x + w, y + h, COL.field, 4)
  -- the earlier slice's tail (grey), the moved slice (accent) from the cut
  local px, py
  for i = 0, 40 do
    local ms = -24 + i * (o.xfade_ms - o.pre_ms + 24) / 40
    local a = 0.25 + 0.15 * math.sin(i * 1.7)
    local fade = ms > -o.pre_ms and math.cos((ms + o.pre_ms) / o.xfade_ms * math.pi / 2) or 1
    local nx, ny = X(ms), mid - (bot - top) / 2 * a * fade
    if px then ImGui.DrawList_AddLine(dl, px, py, nx, ny, 0x8a93a0cc, 1.2) end
    px, py = nx, ny
  end
  px = nil
  for i = 0, 80 do
    local ms = -o.pre_ms + i * (90 + o.pre_ms) / 80
    local a = ms < 0 and 0.08 or (0.95 * math.exp(-ms / 25) * (0.6 + 0.4 * math.abs(math.sin(i * 1.3))))
    local fade = ms < -o.pre_ms + o.xfade_ms and math.sin((ms + o.pre_ms) / o.xfade_ms * math.pi / 2) or 1
    local nx, ny = X(ms), mid - (bot - top) / 2 * a * fade
    if px then ImGui.DrawList_AddLine(dl, px, py, nx, ny, COL.accent, 1.3) end
    px, py = nx, ny
  end
  -- the crossfade X, the hit, the flam window
  ImGui.DrawList_AddLine(dl, cut, top, xe, bot, 0xd6dae488, 1)
  ImGui.DrawList_AddLine(dl, cut, bot, xe, top, 0xd6dae488, 1)
  for yy = top, bot, 5 do ImGui.DrawList_AddLine(dl, X(0), yy, X(0), yy + 2, COL.accent, 1) end
  ImGui.DrawList_AddRectFilled(dl, X(0), bot + 3, mg, bot + 6, (COL.accent & 0xffffff00) | 0x55, 1)
  local hot = (act_ and UI.jv.what) or nil
  local function knob(k, hx, hy, sq)
    local c = hot == k and COL.text or COL.label
    if sq then ImGui.DrawList_AddRectFilled(dl, hx - 4, hy - 4, hx + 4, hy + 4, c, 1)
    else ImGui.DrawList_AddCircleFilled(dl, hx, hy, hot == k and 5 or 4, c) end
  end
  ImGui.DrawList_AddLine(dl, cut, top - 2, cut, bot + 2, COL.text, 1.5)
  knob("pre", cut, top, false)
  knob("xf", xe, bot, true)
  knob("merge", mg, bot + 4.5, false)
  ImGui.DrawList_AddText(dl, x + 4, y + h - 14, COL.dim, string.format("cut %.1f · fade %.1f · flams %.0f ms", o.pre_ms, o.xfade_ms, o.merge_ms))
  if hv or act_ then
    local w_ = hot or (function()
      local best, bd = nil, 1e9
      for k, p in pairs({ pre = cut, xf = xe, merge = mg }) do local d = math.abs(mx - p); if d < bd then best, bd = k, d end end
      return best end)()
    ImGui.SetTooltip(ctx, w_ == "pre" and string.format("Cut %.1f ms before each hit, so the transient stays whole in its slice", o.pre_ms)
      or w_ == "xf" and string.format("Crossfade %.1f ms at every join, ending before the transient", o.xfade_ms)
      or string.format("Flams: hits closer than %.0f ms are one cut (the first)", o.merge_ms))
  end
  return changed, done
end

function UI.draw_quant(kit)
  UI.qo = UI.qo or DT.quant_opts()
  local o = UI.qo
  local function save() DT.quant_set_opts(o); UI.qkey = nil end
  local ts0, ts1 = r.GetSet_LoopTimeRange(false, false, 0, 0, false)
  local scoped = ts1 > ts0
  local key = tostring(cache.state) .. DT.serialize(o) .. (scoped and string.format("%.3f-%.3f", ts0, ts1) or "")
  UI.qover = UI.qover or DT.quant_over()
  if UI.qkey ~= key then
    UI.qpts = DT.quant_points(kit, o, scoped and ts0 or nil, scoped and ts1 or nil)   -- by hand: in the lanes
    UI.qkey = key
  end
  local pts = UI.qpts
  local tracks = DT.quant_tracks(kit)
  local sp = UI.seg("q_scope", { "Time selection", "Whole song" }, scoped and 1 or 2, {
    scoped and string.format("%s - %s", r.format_timestr_pos(ts0, "", 2), r.format_timestr_pos(ts1, "", 2)) or "Make a time selection in REAPER to quantise part of the song",
    "Clear the time selection: quantise the whole song" })
  if sp == 2 and scoped then r.GetSet_LoopTimeRange(true, false, 0, 0, false); UI.qkey = nil end
  ImGui.SameLine(ctx, 0, 8)
  UI.info("q_kit_i", string.format("The whole kit together: %d tracks cut at the same points, so Align's phase stays.\n"
    .. "By hand: click a drum's lane and drag one of its hits.", #tracks))
  ImGui.Dummy(ctx, 0, 2)
  local avail = ImGui.GetContentRegionAvail(ctx)
  local cw = math.floor((avail - 8) * 0.58)
  if UI.section_begin("q_grid", cw, 0) then
    UI.head("qg", "Grid & feel")
    ImGui.TextDisabled(ctx, "Grid"); ImGui.SameLine(ctx, 90)
    local DIVS = { 1, 0.5, 0.25, 0.125 }
    local di
    for i, d in ipairs(DIVS) do if o.div == d then di = i end end
    local dp = UI.seg("qdiv", { "1/4", "1/8", "1/16", "1/32" }, di)
    if dp then o.div = DIVS[dp]; save() end
    ImGui.SameLine(ctx, 0, 8)
    if choice("Triplet##qtrip", o.triplet, "Triplet grid") then o.triplet = not o.triplet; save() end
    ImGui.TextDisabled(ctx, "Cuts from"); ImGui.SameLine(ctx, 90)
    local kinds = {}
    for _, e in ipairs(kit) do if e.role == "drum" and e.hitlist then kinds[DT.quant_kind(e)] = true end end
    local first = true
    for _, k in ipairs({ { "kick", "Kick" }, { "snare", "Snare" }, { "toms", "Toms" }, { "hat", "Hat" }, { "other", "Other" } }) do
      if kinds[k[1]] then
        if not first then ImGui.SameLine(ctx, 0, 2) end
        first = false
        if choice(k[2] .. "##qfrom" .. k[1], o.from[k[1]] == true, "Cut (and line up to the grid) at " .. k[2]:lower() .. " hits;\nthe rest of the kit moves with whichever slice it's in") then
          o.from[k[1]] = not o.from[k[1]] or nil; save()
        end
      end
    end
    ImGui.TextDisabled(ctx, "Snap"); ImGui.SameLine(ctx, 90)
    local snp = UI.seg("qsnap", { "Grid", "Off" }, o.snap and 1 or 2,
      { "Dragging a hit in its lane lands it on the grid (Shift: free)", "Dragging a hit places it anywhere" })
    if snp then o.snap = snp == 1; save() end
    ImGui.TextDisabled(ctx, "Move"); ImGui.SameLine(ctx, 90)
    local smp = UI.seg("qsmart", { "Hits on the grid", "All in the window" }, o.smart and 1 or 2, {
      "Each hit is matched to the line it's playing - the nearest straight 16th or 8th triplet -\n"
        .. "and moves only if that line is on the grid: at 1/4, a 16th offbeat stays a 16th offbeat",
      "Any hit within the window moves to its nearest grid line" })
    if smp then o.smart = smp == 1; save() end
    ImGui.TextDisabled(ctx, "Strength"); ImGui.SameLine(ctx, 90)
    local ch, v, sdone = UI.pull("##qstr", o.strength, 240, "How far each hit moves towards the grid: 100% on it, less keeps some of the feel\nDouble-click: 100%", 100)
    if ch then o.strength = v; UI.qkey = nil end
    if sdone then save() end
    if UI.quant_graph(pts, o, math.min(560, ImGui.GetContentRegionAvail(ctx)), 110) then UI.qkey = nil end
    if ImGui.IsItemDeactivated(ctx) then save() end
    UI.section_end()
  end
  ImGui.SameLine(ctx, 0, 8)
  if UI.section_begin("q_cuts", 0, 0) then
    local nm, maxm, b, a, nother = 0, 0, 0, 0, 0
    for _, p in ipairs(pts) do
      if p.other then nother = nother + 1 end
      if p.moves then nm = nm + 1; maxm = math.max(maxm, math.abs(p.move)) end
      b = b + math.abs(p.dev); a = a + math.abs(p.dev + p.move)
    end
    local qb = { nm > 0 and "ok" or "off", string.format("%d of %d move", nm, #pts),
      string.format("%d cuts · %d move · %d stay put", #pts, nm, #pts - nm)
      .. (nother > 0 and string.format("\n%d of them play another subdivision: a 16th or a triplet off the grid", nother) or "")
      .. (#pts > 0 and string.format("\noff the grid on average %.1f ms → %.1f ms; the biggest move %.1f ms", b / #pts * 1000, a / #pts * 1000, maxm * 1000) or "") }
    UI.head("qc", "Cuts", { badges = { qb }, nbadges = 1 })
    local jch, jdone = UI.join_view(o, math.min(360, ImGui.GetContentRegionAvail(ctx)), 84)
    if jch then UI.qkey = nil end
    if jdone then save() end
    ImGui.Dummy(ctx, 0, 4)
    ImGui.BeginDisabled(ctx, nm == 0)
    if ImGui.Button(ctx, string.format("Quantise %d tracks##q_go", #tracks)) then
      r.Undo_BeginBlock2(0)
      r.PreventUIRefresh(1)
      local moved, gaps, gat = DT.quant_apply(tracks, pts, o)
      r.PreventUIRefresh(-1)
      r.Undo_EndBlock2(0, UI.Q_UNDO, -1)
      UI.qgaps, UI.qgap_i = gat or {}, 0
      UI.qover = {}; DT.quant_set_over(UI.qover)    -- the hits have moved: the manual choices are done
      UI.qmsg = { gaps > 0 and "warn" or "ok", os.date("%H:%M"), string.format("Quantised at %s: %d slices moved%s. One undo step.", os.date("%H:%M"), moved,
        gaps > 0 and string.format(", %d gaps left where there was no earlier audio to fill them (Next gap shows each)", gaps) or "") }
      invalidate(); UI.qkey = nil; NSYNC.state = nil
    end
    ImGui.EndDisabled(ctx)
    if ImGui.IsItemHovered(ctx, K("HoveredFlags_AllowWhenDisabled") or 0) then
      ImGui.SetTooltip(ctx, "Cut every kit track at the same points and move the slices (no stretching), crossfaded.\nOne undo step. The hit maps move with them; notes, gate keys and bands follow.")
    end
    if UI.qmsg then ImGui.SameLine(ctx, 0, 8); UI.badge("q_done", UI.qmsg[1], UI.qmsg[2], UI.qmsg[3]) end
    -- straight back, while it's the last thing done
    local last = r.Undo_CanUndo2 and r.Undo_CanUndo2(0)
    if last == UI.Q_UNDO then
      ImGui.SameLine(ctx, 0, 8)
      if ImGui.Button(ctx, "Undo quantise##q_undo") then
        r.Main_OnCommand(40029, 0)                -- Edit: Undo
        UI.qmsg, UI.qgaps = nil, nil
        invalidate(); UI.qkey = nil; NSYNC.state = nil
      end
      if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "Put every track back as it was before quantising (the same as Ctrl+Z)") end
    end
    -- any gaps left: one at a time, the edit cursor taken to it
    if UI.qgaps and #UI.qgaps > 0 then
      ImGui.SameLine(ctx, 0, 8)
      if ImGui.Button(ctx, string.format("Next gap (%d)##q_gap", #UI.qgaps)) then
        UI.qgap_i = UI.qgap_i % #UI.qgaps + 1
        local gp = UI.qgaps[UI.qgap_i]
        r.SetEditCurPos(gp.t, true, false)
        if r.ValidatePtr(gp.track, "MediaTrack*") then r.SetOnlyTrackSelected(gp.track) end
      end
      if ImGui.IsItemHovered(ctx) then
        local gp = UI.qgaps[UI.qgap_i % #UI.qgaps + 1]
        local tn = "?"
        if r.ValidatePtr(gp.track, "MediaTrack*") then tn = select(2, r.GetTrackName(gp.track)) end
        ImGui.SetTooltip(ctx, string.format("A slice moved later where there was no earlier audio to fill behind it.\nNext: %s at %s (%.1f ms)",
          tn, r.format_timestr_pos(gp.t, "", -1), gp.len * 1000))
      end
    end
    UI.section_end()
  end
end

--@pro TS_DT_Pro_Window.lua:6

-- the workflow, left to right: the tabs pick what the lanes show and the
-- panel below them
local TABS = {
  { "kit", "Setup" }, { "detect", "Detect" }, { "align", "Align" }, { "quant", "Quantise" }, { "level", "Level" },
  { "gate", "Gate" }, { "enhance", "Tone" }, { "reinforce", "Reinforce" },
}

-- the workflow's tab row: plain words; the open tab takes the panel's
-- colour with an accent bar under it, the others are dim text
HIDDEN_TAB = {}   -- tabs not shown

-- a dot on a tab: what's on the current drum there (the tab's colour; grey
-- if off), or hits waiting for review (Detect, amber)
function UI.tab_dot(tab)
  if tab == "detect" then return (#(cache.review or {}) > 0) and COL.mid or nil end
  if not S.cur or not r.ValidatePtr(S.cur, "MediaTrack*") then return nil end
  local a = UI.applied(S.cur, UI.cur_profile)
  local on, any = false, false
  for k, tb in pairs(UI.STAGE_TAB) do
    if tb == tab and a[k] then any = true; if a[k] ~= 0 then on = true end end
  end
  if not any then return nil end
  return on and TAB_COL[tab] or COL.dim
end
function UI.tab_tip(tab)
  if tab == "detect" and #(cache.review or {}) > 0 then return string.format("%d hits to review", #cache.review) end
  local dot = UI.tab_dot(tab)
  if dot and tab ~= "detect" then
    local _, n = r.GetTrackName(S.cur)
    return dot == COL.dim and ("Switched off on " .. n) or ("In use on " .. n)
  end
end

-- Pro's tabs; in Standard they show, greyed, with what Pro would give
UI.PRO_TAB = { level = true, gate = true, enhance = true, reinforce = true }
UI.PRO_WHAT = {
  level = "Every hit of a drum evened out to the same level - written as clip gain or a pre-FX envelope, each hit adjustable by hand.",
  gate = "ReaGate opened by the hit map: it never misses a quiet hit and spill never opens it. Duck under another drum's hits, Clean and Debleed.",
  enhance = "The frequencies a drum rings on, found from its own hits, as EQ bands that act all the time, through each hit's attack or only after it.",
  reinforce = "Noise, samples and a kit instrument under every hit, lined up with the drum to a fraction of a sample; the drum's panel in ChannelView Pro.",
}
function UI.pro_card(tab)
  local w = math.min(460, ImGui.GetContentRegionAvail(ctx) - 20)
  local x0, y0 = ImGui.GetCursorScreenPos(ctx)
  local avail_w = ImGui.GetContentRegionAvail(ctx)
  local x, y = x0 + math.max(0, (avail_w - w) / 2), y0 + 24
  local dl = ImGui.GetWindowDrawList(ctx)
  local lh = ImGui.GetTextLineHeight(ctx)
  local h = lh * 7 + 40
  ImGui.DrawList_AddRectFilled(dl, x, y, x + w, y + h, 0x0b0d12ff, 8)
  ImGui.DrawList_AddRect(dl, x, y, x + w, y + h, COL.border, 8, 0, 1)
  -- a padlock
  local lx, ly = x + 20, y + 18
  ImGui.DrawList_AddRect(dl, lx, ly + 8, lx + 14, ly + 19, COL.label, 2, 0, 1.5)
  ImGui.DrawList_PathArcTo(dl, lx + 7, ly + 8, 4.5, math.pi, 2 * math.pi, 10)
  ImGui.DrawList_PathStroke(dl, COL.label, 0, 1.5)
  ImGui.SetCursorScreenPos(ctx, lx + 24, ly + 3)
  ImGui.Text(ctx, "DrumToolbox Pro")
  ImGui.SetCursorScreenPos(ctx, x + 20, ly + 30)
  ImGui.PushTextWrapPos(ctx, x + w - 20)
  ImGui.TextColored(ctx, COL.label, UI.PRO_WHAT[tab] or "")
  if DT.ED.mismatch then
    ImGui.TextColored(ctx, COL.warn or COL.mid, string.format("DrumToolbox Pro %s is installed, but this is DrumToolbox %s: "
      .. "they have to be the same. Extensions > ReaPack > Synchronize packages.", DT.ED.mismatch, DT.ED.RELEASE))
  end
  ImGui.PopTextWrapPos(ctx)
  ImGui.Dummy(ctx, 0, 4)
  ImGui.SetCursorScreenPos(ctx, x + 20, select(2, ImGui.GetCursorScreenPos(ctx)))
  if ImGui.Button(ctx, "How to get Pro##pro_get") then
    if r.CF_ShellExecute then r.CF_ShellExecute(DT.ED.PRO_URL)
    else r.MB("DrumToolbox Pro:\n\n" .. DT.ED.PRO_URL, "TS DrumToolbox", 0) end
  end
  ImGui.SetCursorScreenPos(ctx, x0, y + h + 10)
  ImGui.Dummy(ctx, 0, 0)
end

local function draw_tab_row()
  if HIDDEN_TAB[S.tab] then S.tab = "level" end
  local x, y = ImGui.GetCursorScreenPos(ctx)
  local w = ImGui.GetContentRegionAvail(ctx)
  local lh = ImGui.GetTextLineHeight(ctx)
  local h = lh + 18
  local dl = ImGui.GetWindowDrawList(ctx)
  ImGui.DrawList_AddRectFilled(dl, x, y, x + w, y + h, COL.win)
  ImGui.DrawList_AddLine(dl, x, y + 0.5, x + w, y + 0.5, COL.border, 1)
  local tx = x + 8
  for _, t in ipairs(TABS) do
    if HIDDEN_TAB[t[1]] then goto next_tab end
    do
    local tw2 = (ImGui.CalcTextSize(ctx, t[2]))
    local locked = UI.PRO_TAB[t[1]] and not DT.ED.PRO
    local pw = locked and (ImGui.CalcTextSize(ctx, "PRO")) + 10 or 0
    local bw = tw2 + 28 + (locked and pw + 6 or 0)
    ImGui.SetCursorScreenPos(ctx, tx, y)
    if ImGui.InvisibleButton(ctx, "##tab_" .. t[1], bw, h) then S.tab = t[1] end
    local hov, on = ImGui.IsItemHovered(ctx), S.tab == t[1]
    if on then
      ImGui.DrawList_AddRectFilled(dl, tx, y + 1, tx + bw, y + h, COL.panel)
      ImGui.DrawList_AddRectFilled(dl, tx, y + h - 2, tx + bw, y + h, COL.accent)
    elseif hov then
      ImGui.DrawList_AddRectFilled(dl, tx, y + 1, tx + bw, y + h, 0xffffff08)
    end
    ImGui.DrawList_AddText(dl, tx + 14, y + (h - lh) / 2, locked and COL.dim or ((on or hov) and COL.text or COL.label), t[2])
    if locked then
      local px, py = tx + 14 + tw2 + 6, y + (h - lh) / 2 - 1
      ImGui.DrawList_AddRect(dl, px, py, px + pw, py + lh + 2, COL.dim, (lh + 2) / 2, 0, 1)
      ImGui.DrawList_AddText(dl, px + 5, py + 1, COL.dim, "PRO")
    end
    local dot = UI.tab_dot(t[1])
    if dot then ImGui.DrawList_AddCircleFilled(dl, tx + bw - 7, y + (h - lh) / 2 + 3, 2.5, dot) end
    if hov then
      local tp = locked and (t[2] .. " is part of DrumToolbox Pro") or UI.tab_tip(t[1])
      if tp then ImGui.SetTooltip(ctx, tp) end
    end
    tx = tx + bw + 2
    end
    ::next_tab::
  end
  -- the panel starts right at the row's foot, so the open tab joins it
  ImGui.SetCursorScreenPos(ctx, x, y + h)
end

--@pro TS_DT_Pro_Window.lua:7

-- the drum the panel works on: picked in the lanes (no second list down
-- here); the first that qualifies if the current one doesn't
function UI.current_of(list)
  for _, e in ipairs(list) do if e.track == S.cur then UI.cur_profile = e.profile; return e end end
  if list[1] then S.cur = list[1].track; UI.cur_profile = list[1].profile end
  return list[1]
end

-- the current drum, big and clear, at the top of a panel
function UI.drum_banner(cur, what)
  ImGui.TextColored(ctx, COL.accent, cur.name)
  if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, (what and (what .. "\n") or "") .. "Pick another drum in the lanes above") end
end

-- a bordered box with its own heading: the panel's parts kept apart
UI.SECTION_BG = 0x1d2027ff
function UI.section_begin(id, w, h, auto)
  ImGui.PushStyleColor(ctx, K("Col_ChildBg"), UI.SECTION_BG)
  ImGui.PushStyleVar(ctx, K("StyleVar_ChildRounding"), 4)
  ImGui.PushStyleVar(ctx, K("StyleVar_WindowPadding"), 10, 8)
  local ok = ImGui.BeginChild(ctx, id, w or 0, h or 0, CHILD_BORDER | (K("ChildFlags_AlwaysUseWindowPadding") or 0)
    | (auto and (K("ChildFlags_AutoResizeY") or 0) or 0))
  ImGui.PopStyleVar(ctx, 2)
  ImGui.PopStyleColor(ctx)
  return ok
end
function UI.section_end() ImGui.EndChild(ctx) end

-- ---- section headings, status badges, switches --------------------------
-- small drawn glyphs in a box of size s at x, y
function UI.glyph(dl, kind, x, y, s, col)
  local cx, cy = x + s / 2, y + s / 2
  if kind == "check" then
    ImGui.DrawList_AddLine(dl, x + s * 0.2, y + s * 0.55, x + s * 0.42, y + s * 0.76, col, 1.6)
    ImGui.DrawList_AddLine(dl, x + s * 0.42, y + s * 0.76, x + s * 0.8, y + s * 0.26, col, 1.6)
  elseif kind == "sync" then
    ImGui.DrawList_PathArcTo(dl, cx, cy, s * 0.32, math.rad(200), math.rad(470), 14)
    ImGui.DrawList_PathStroke(dl, col, 0, 1.5)
    local a = math.rad(470)
    local hx, hy = cx + s * 0.32 * math.cos(a), cy + s * 0.32 * math.sin(a)
    ImGui.DrawList_AddTriangleFilled(dl, hx + s * 0.16, hy, hx - s * 0.1, hy - s * 0.14, hx - s * 0.1, hy + s * 0.14, col)
  elseif kind == "warn" then
    ImGui.DrawList_AddTriangle(dl, cx, y + s * 0.12, x + s * 0.9, y + s * 0.86, x + s * 0.1, y + s * 0.86, col, 1.3)
    ImGui.DrawList_AddLine(dl, cx, y + s * 0.4, cx, y + s * 0.62, col, 1.5)
    ImGui.DrawList_AddCircleFilled(dl, cx, y + s * 0.74, 1.1, col)
  elseif kind == "info" then
    ImGui.DrawList_AddCircle(dl, cx, cy, s * 0.46, col, 16, 1)
    ImGui.DrawList_AddLine(dl, cx, y + s * 0.44, cx, y + s * 0.76, col, 1.2)
    ImGui.DrawList_AddCircleFilled(dl, cx, y + s * 0.27, 0.9, col)
  elseif kind == "more" then
    for i = -1, 1 do ImGui.DrawList_AddCircleFilled(dl, cx + i * s * 0.3, cy, 1.7, col) end
  elseif kind == "busy" then
    local a0 = (r.time_precise() * 6) % (2 * math.pi)
    ImGui.DrawList_PathArcTo(dl, cx, cy, s * 0.32, a0, a0 + 4.2, 14)
    ImGui.DrawList_PathStroke(dl, col, 0, 1.6)
  else
    ImGui.DrawList_AddCircleFilled(dl, cx, cy, s * 0.22, col)
  end
end

-- A status pill: kind "ok" (green tick), "stale" (amber: out of date),
-- "warn" (red-orange: a problem), "busy" (working), "off" (grey). Short
-- text, a tooltip. Gives true if clicked.
UI.BADGE = { ok = { 0x4cc9a6ff, "check" }, stale = { 0xd8a24aff, "sync" }, warn = { 0xd8724aff, "warn" },
  busy = { 0x8fa3c0ff, "busy" }, off = { 0x76808fff, "dot" } }
-- the mouse cursor over something you can act on: "hand" (click), "ew" /
-- "ns" (drag sideways / up and down)
function UI.cursor(kind)
  if not ImGui.SetMouseCursor then return end
  local c = kind == "ew" and K("MouseCursor_ResizeEW") or kind == "ns" and K("MouseCursor_ResizeNS")
    or kind == "all" and K("MouseCursor_ResizeAll") or K("MouseCursor_Hand")
  if c then ImGui.SetMouseCursor(ctx, c) end
end

-- clickable: only then does it light up under the mouse
function UI.badge(id, kind, text, tipx, clickable)
  local b = UI.BADGE[kind] or UI.BADGE.off
  local col = b[1]
  local th = ImGui.GetTextLineHeight(ctx)
  local tw = (text and text ~= "") and ImGui.CalcTextSize(ctx, text) or 0
  local h = th + 4
  local w = h + (tw > 0 and tw + 6 or 0)
  local x, y = ImGui.GetCursorScreenPos(ctx)
  local c = ImGui.InvisibleButton(ctx, id, w, h)
  local hv = ImGui.IsItemHovered(ctx)
  local lit = hv and clickable
  if lit then UI.cursor("hand") end
  local dl = ImGui.GetWindowDrawList(ctx)
  ImGui.DrawList_AddRectFilled(dl, x, y, x + w, y + h, (col & 0xffffff00) | (lit and 0x44 or 0x26), h / 2)
  UI.glyph(dl, b[2], x + 3, y + 2, h - 4, col)
  if tw > 0 then ImGui.DrawList_AddText(dl, x + h, y + 2, col, text) end
  if tipx and hv then ImGui.SetTooltip(ctx, tipx) end
  return clickable and c
end

-- ⓘ: the help for what's beside it, on hover
function UI.info(id, text)
  local th = ImGui.GetTextLineHeight(ctx)
  local s = math.floor(th * 0.68 + 0.5)
  local x, y = ImGui.GetCursorScreenPos(ctx)
  ImGui.InvisibleButton(ctx, id, s, th)
  local hv = ImGui.IsItemHovered(ctx)
  UI.glyph(ImGui.GetWindowDrawList(ctx), "info", x, y + (th - s) / 2, s, COL.dim)
  if hv then ImGui.SetTooltip(ctx, text) end
end

-- an On / Off switch; gives true if clicked
function UI.toggle(id, on, tipx, col)
  local h = ImGui.GetTextLineHeight(ctx)
  local w = math.floor(h * 1.9)
  local x, y = ImGui.GetCursorScreenPos(ctx)
  local c = ImGui.InvisibleButton(ctx, id, w, h)
  if c then UI.APP = {} end
  if ImGui.IsItemHovered(ctx) then UI.cursor("hand") end
  local dl = ImGui.GetWindowDrawList(ctx)
  ImGui.DrawList_AddRectFilled(dl, x, y, x + w, y + h, on and (col or COL.accent) or COL.chip_on, h / 2)
  ImGui.DrawList_AddCircleFilled(dl, on and (x + w - h / 2) or (x + h / 2), y + h / 2, h / 2 - 2, on and 0x11131aff or COL.label)
  if tipx and ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, tipx) end
  return c
end

-- A section's heading: a bar in the tab's colour, the title, ⓘ (o.help),
-- status badges (o.badges: { kind, text, tip, on_click } each, nils
-- skipped), and at the right an On / Off switch (o.on ~= nil) and a ⋯ menu
-- (o.menu: draws its items with ImGui.Selectable). Gives "toggle" when the
-- switch is clicked.
function UI.head(id, title, o)
  o = o or {}
  local dl = ImGui.GetWindowDrawList(ctx)
  local x, y = ImGui.GetCursorScreenPos(ctx)
  local th = ImGui.GetTextLineHeight(ctx)
  local avail = ImGui.GetContentRegionAvail(ctx)
  ImGui.DrawList_AddRectFilled(dl, x, y + 1, x + 3, y + th - 1, COL.accent, 1)
  ImGui.SetCursorScreenPos(ctx, x + 9, y)
  ImGui.Text(ctx, title)
  if o.help then ImGui.SameLine(ctx, 0, 6); UI.info(id .. "_i", o.help) end
  local bs = o.badges or {}
  for i = 1, (o.nbadges or #bs) do
    local b = bs[i]
    if b then
      ImGui.SameLine(ctx, 0, 8)
      if UI.badge(id .. "_b" .. i, b[1], b[2], b[3], b[4] ~= nil) then b[4]() end
    end
  end
  local ev
  local rw = (o.on ~= nil and math.floor(th * 1.9) + 8 or 0) + (o.menu and th + 4 or 0)
  if rw > 0 then
    ImGui.SameLine(ctx, 0, 8)
    local cx = ImGui.GetCursorScreenPos(ctx)
    if x + avail - rw > cx then ImGui.SetCursorScreenPos(ctx, x + avail - rw, y) end
    if o.on ~= nil then
      if UI.toggle(id .. "_on", o.on, o.on_tip) then ev = "toggle" end
      if o.menu then ImGui.SameLine(ctx, 0, 8) end
    end
    if o.menu then UI.more(id .. "_m", o.menu) end
  end
  local _, y2 = ImGui.GetCursorScreenPos(ctx)
  ImGui.DrawList_AddLine(dl, x, y2 + 1, x + avail, y2 + 1, COL.border, 1)
  ImGui.Dummy(ctx, 0, 3)
  return ev
end

-- ⋯: a menu of the rarer actions (fn draws its items)
function UI.more(id, fn, tipx)
  local th = ImGui.GetTextLineHeight(ctx)
  local mx, my = ImGui.GetCursorScreenPos(ctx)
  if ImGui.InvisibleButton(ctx, id, th + 4, th) then ImGui.OpenPopup(ctx, id .. "_menu") end
  local hv = ImGui.IsItemHovered(ctx)
  if hv then UI.cursor("hand") end
  UI.glyph(ImGui.GetWindowDrawList(ctx), "more", mx + 2, my, th, hv and COL.text or COL.label)
  if hv and tipx then ImGui.SetTooltip(ctx, tipx) end
  if ImGui.BeginPopup(ctx, id .. "_menu") then fn(); ImGui.EndPopup(ctx) end
end


-- ---- drawn controls -------------------------------------------------------
-- small line icons for what's on a drum: gate, tone, noise, sample, keys, level
function UI.stage_icon(dl, kind, x, y, s, col)
  local function L(a, b, c, d) ImGui.DrawList_AddLine(dl, x + a * s, y + b * s, x + c * s, y + d * s, col, 1.3) end
  if kind == "gate" then L(.05, .8, .3, .8); L(.3, .8, .3, .2); L(.3, .2, .7, .2); L(.7, .2, .7, .8); L(.7, .8, .95, .8)
  elseif kind == "tone" then
    local px, py
    for i = 0, 10 do
      local u = i / 10
      local nx, ny = u, .8 - .6 * math.exp(-((u - .5) * 5) ^ 2)
      if px then L(px, py, nx, ny) end
      px, py = nx, ny
    end
  elseif kind == "noise" then
    local ys = { .5, .2, .75, .3, .85, .15, .65, .35, .5 }
    for i = 1, #ys - 1 do L((i - 1) / 8, ys[i], i / 8, ys[i + 1]) end
  elseif kind == "sample" then L(.05, .85, .25, .15); L(.25, .15, .5, .6); L(.5, .6, .95, .8)
  elseif kind == "keys" then
    ImGui.DrawList_AddRect(dl, x + .1 * s, y + .2 * s, x + .9 * s, y + .8 * s, col, 1, 0, 1.2)
    L(.37, .2, .37, .8); L(.63, .2, .63, .8)
  elseif kind == "level" then L(.1, .5, .9, .5); L(.25, .25, .25, .75); L(.5, .15, .5, .85); L(.75, .3, .75, .7)
  end
end

-- What's on a drum (cached for half a second): { gate, tone, noise, inst =
-- 1 on / 0 off, samp = count, level = 1 }
UI.APP = {}
function UI.applied(track, profile)
  local now = r.time_precise()
  local a = UI.APP[track]
  if a and now - a.t < 0.5 then return a end
  a = { t = now }
--@pro TS_DT_Pro_Window.lua:8
  UI.APP[track] = a
  return a
end
UI.STAGE_TAB = { gate = "gate", tone = "enhance", noise = "reinforce", samp = "reinforce", inst = "reinforce", level = "level" }
UI.STAGE_ICON = { gate = "gate", tone = "tone", noise = "noise", samp = "sample", inst = "keys", level = "level" }

-- the stages on a drum as a row of icons ending at xr; gives its left edge
function UI.stage_icons(dl, e, xr, y, s)
  local a = UI.applied(e.track, e.profile)
  local x = xr
  for _, k in ipairs({ "inst", "samp", "noise", "tone", "gate" }) do
    local v = a[k]
    if v then
      local col = v == 0 and COL.dim or TAB_COL[UI.STAGE_TAB[k]]
      if k == "samp" and v > 1 then
        local n = tostring(v)
        local nw = (ImGui.CalcTextSize(ctx, n))
        x = x - nw
        ImGui.DrawList_AddText(dl, x, y + (s - ImGui.GetTextLineHeight(ctx)) / 2, col, n)
        x = x - 1
      end
      x = x - s
      UI.stage_icon(dl, UI.STAGE_ICON[k], x, y, s, col)
      x = x - 5
    end
  end
  return x
end

-- a vertical strip for a level in dB (lo .. hi): drag, double-click 0 dB.
-- Gives changed, value, released.
function UI.vstrip(id, v, lo, hi, w, h, tipx)
  local x, y = ImGui.GetCursorScreenPos(ctx)
  ImGui.InvisibleButton(ctx, id, w, h)
  local hv, act_ = ImGui.IsItemHovered(ctx), ImGui.IsItemActive(ctx)
  if hv or act_ then UI.cursor("ns") end
  local done = ImGui.IsItemDeactivated(ctx)
  local nv = v
  if act_ then
    local _, my = ImGui.GetMousePos(ctx)
    nv = math.floor((lo + clampv((y + h - 4 - my) / (h - 8), 0, 1) * (hi - lo)) * 10 + 0.5) / 10
  end
  if hv and ImGui.IsMouseDoubleClicked(ctx, 0) then nv = 0 end
  local dl = ImGui.GetWindowDrawList(ctx)
  local function py(d) return y + h - 4 - clampv((d - lo) / (hi - lo), 0, 1) * (h - 8) end
  local cx = x + w / 2
  ImGui.DrawList_AddRectFilled(dl, cx - 2, y + 4, cx + 2, y + h - 4, COL.chip_on, 2)
  ImGui.DrawList_AddRectFilled(dl, cx - 2, py(nv), cx + 2, y + h - 4, COL.accent, 2)
  ImGui.DrawList_AddLine(dl, x + 1, py(0), x + w - 1, py(0), COL.dim, 1)
  ImGui.DrawList_AddRectFilled(dl, x + 1, py(nv) - 3, x + w - 1, py(nv) + 3, (hv or act_) and COL.text or COL.label, 2)
  if hv or act_ then ImGui.SetTooltip(ctx, string.format("%+.1f dB", nv) .. (tipx and ("\n" .. tipx) or "")) end
  return nv ~= v, nv, done
end

-- the velocity range (dB, 0 .. 60) as a ramp: how much quieter the softest
-- hit plays; drag sideways. Gives changed, value, released.
function UI.vel_ramp(id, vdb, w, tipx)
  local h = 16
  local x, y = ImGui.GetCursorScreenPos(ctx)
  ImGui.InvisibleButton(ctx, id, w, h)
  local hv, act_ = ImGui.IsItemHovered(ctx), ImGui.IsItemActive(ctx)
  if hv or act_ then UI.cursor("ew") end
  local done = ImGui.IsItemDeactivated(ctx)
  UI.vr = UI.vr or {}
  local mx = ImGui.GetMousePos(ctx)
  if ImGui.IsItemActivated(ctx) then UI.vr[id] = { mx, vdb } end
  if hv and ImGui.IsMouseDoubleClicked(ctx, 0) then UI.vr[id] = { mx, 40 } end   -- back to 40 dB
  local nv = vdb
  if act_ and UI.vr[id] then nv = math.floor(clampv(UI.vr[id][2] + (mx - UI.vr[id][1]) * 60 / w, 0, 60) + 0.5) end
  local dl = ImGui.GetWindowDrawList(ctx)
  ImGui.DrawList_AddRectFilled(dl, x, y, x + w, y + h, COL.field, 3)
  local ly = y + h - 2 - (h - 4) * (1 - nv / 60)
  ImGui.DrawList_AddQuadFilled(dl, x + 3, ly, x + w - 3, y + 2, x + w - 3, y + h - 2, x + 3, y + h - 2, (COL.accent & 0xffffff00) | 0x66)
  ImGui.DrawList_AddCircleFilled(dl, x + 6, ly, (hv or act_) and 4.5 or 3.5, (hv or act_) and COL.text or COL.accent)
  local s = string.format("vel %.0f dB", nv)
  local tw2 = (ImGui.CalcTextSize(ctx, s))
  ImGui.DrawList_AddText(dl, x + w - tw2 - 6, y + (h - ImGui.GetTextLineHeight(ctx)) / 2, COL.text, s)
  if (hv or act_) and tipx then ImGui.SetTooltip(ctx, tipx) end
  return nv ~= vdb, nv, done
end

-- a dashed card with one "+" action in it, for something not added yet;
-- gives true if clicked
function UI.empty(id, label, w, h, tipx)
  local x, y = ImGui.GetCursorScreenPos(ctx)
  w = w or ImGui.GetContentRegionAvail(ctx)
  local dl = ImGui.GetWindowDrawList(ctx)
  local c = ImGui.InvisibleButton(ctx, id, w, h)
  local hv = ImGui.IsItemHovered(ctx)
  if hv then UI.cursor("hand") end
  local col = hv and COL.accent or COL.border
  local function dash(x1, y1, x2, y2)
    local len = math.sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2)
    for d = 0, len, 9 do
      local e = math.min(len, d + 5)
      ImGui.DrawList_AddLine(dl, x1 + (x2 - x1) * d / len, y1 + (y2 - y1) * d / len, x1 + (x2 - x1) * e / len, y1 + (y2 - y1) * e / len, col, 1)
    end
  end
  dash(x, y, x + w, y); dash(x + w, y, x + w, y + h); dash(x + w, y + h, x, y + h); dash(x, y + h, x, y)
  local s = "+  " .. label
  local tw2 = (ImGui.CalcTextSize(ctx, s))
  local lh = ImGui.GetTextLineHeight(ctx)
  ImGui.DrawList_AddRectFilled(dl, x + (w - tw2) / 2 - 12, y + (h - lh) / 2 - 6, x + (w + tw2) / 2 + 12, y + (h + lh) / 2 + 6,
    hv and COL.accent_hi or COL.accent, 5)
  ImGui.DrawList_AddText(dl, x + (w - tw2) / 2, y + (h - lh) / 2, 0x0e1015ff, s)
  if hv and tipx then ImGui.SetTooltip(ctx, tipx) end
  return c
end

-- Hits by confidence (time across, confidence up) and the line under which
-- they don't count: drag it. Gives changed, value, released.
function UI.conf_strip(id, hits, thr, w, h, tipx)
  local x, y = ImGui.GetCursorScreenPos(ctx)
  ImGui.InvisibleButton(ctx, id, w, h)
  local hv, act_ = ImGui.IsItemHovered(ctx), ImGui.IsItemActive(ctx)
  if hv or act_ then UI.cursor("ns") end
  local done = ImGui.IsItemDeactivated(ctx)
  local nv = thr
  local function cy(c) return y + h - 4 - clampv(c, 0, 1) * (h - 8) end
  if act_ then
    local _, my = ImGui.GetMousePos(ctx)
    nv = math.floor(clampv((y + h - 4 - my) / (h - 8), 0, 1) * 100 + 0.5) / 100
  end
  local dl = ImGui.GetWindowDrawList(ctx)
  ImGui.DrawList_AddRectFilled(dl, x, y, x + w, y + h, COL.field, 3)
  local n = #hits
  local step = n > 1 and (w - 12) / (n - 1) or 0
  local skip = 0
  for i, hh in ipairs(hits) do
    local c = hh.locked and 1 or (hh.c or 1)
    local on = c >= nv
    if not on then skip = skip + 1 end
    ImGui.DrawList_AddCircleFilled(dl, x + 6 + (i - 1) * step, cy(c), n > 300 and 1.5 or 2.5, on and COL.accent or COL.chip_on)
  end
  local ty = cy(nv)
  for xx = x + 2, x + w - 2, 6 do ImGui.DrawList_AddLine(dl, xx, ty, math.min(xx + 3, x + w - 2), ty, COL.text, 1) end
  ImGui.DrawList_AddCircleFilled(dl, x + w - 8, ty, (hv or act_) and 5 or 4, (hv or act_) and COL.text or COL.label)
  local s = string.format("≥ %.2f", nv)
  ImGui.DrawList_AddText(dl, x + w - 16 - (ImGui.CalcTextSize(ctx, s)), ty - ImGui.GetTextLineHeight(ctx) - 1, COL.label, s)
  if hv or act_ then
    ImGui.SetTooltip(ctx, string.format("Hits under the line don't open it: %d of %d", skip, n) .. (tipx and ("\n" .. tipx) or ""))
  end
  return nv ~= thr, nv, done
end

-- a switch's state for UI.head: nil (no switch) unless `has`, then true / false
function UI.opt(has, v)
  if not has then return nil end
  return v and true or false
end

-- How far a hit is pulled from where it was played (left, hollow) to the
-- grid line (right): drag the arrow's head. Gives changed, percent, released.
function UI.pull(id, pct, w, tipx, def)
  local h = ImGui.GetFrameHeight(ctx)
  local x, y = ImGui.GetCursorScreenPos(ctx)
  ImGui.InvisibleButton(ctx, id, w, h)
  local hv, act_ = ImGui.IsItemHovered(ctx), ImGui.IsItemActive(ctx)
  if hv or act_ then UI.cursor("ew") end
  local done = ImGui.IsItemDeactivated(ctx)
  local x0, x1 = x + 10, x + w - 34
  local nv = pct
  UI.pull_def = UI.pull_def or {}
  if def and hv and ImGui.IsMouseDoubleClicked(ctx, 0) then UI.pull_def[id] = true end
  if act_ then
    local mx = ImGui.GetMousePos(ctx)
    nv = UI.pull_def[id] and def or math.floor(clampv((mx - x0) / (x1 - x0), 0, 1) * 100 + 0.5)
  end
  if not act_ then UI.pull_def[id] = nil end
  local dl = ImGui.GetWindowDrawList(ctx)
  local cy = y + h / 2
  ImGui.DrawList_AddRectFilled(dl, x, y, x + w, y + h, COL.field, 4)
  ImGui.DrawList_AddLine(dl, x1, y + 3, x1, y + h - 3, COL.label, 1.5)
  ImGui.DrawList_AddCircle(dl, x0, cy, 4, COL.label, 12, 1.3)
  local hx = x0 + (x1 - x0) * nv / 100
  ImGui.DrawList_AddLine(dl, x0 + 4, cy, hx, cy, COL.accent, 2)
  ImGui.DrawList_AddTriangleFilled(dl, hx + 1, cy, hx - 6, cy - 4, hx - 6, cy + 4, COL.accent)
  ImGui.DrawList_AddCircleFilled(dl, hx, cy, (hv or act_) and 5 or 4, (hv or act_) and COL.text or COL.accent)
  local s = string.format("%d%%", nv)
  ImGui.DrawList_AddText(dl, x + w - 4 - (ImGui.CalcTextSize(ctx, s)), cy - ImGui.GetTextLineHeight(ctx) / 2, COL.text, s)
  if (hv or act_) and tipx then ImGui.SetTooltip(ctx, tipx) end
  return nv ~= pct, nv, done
end

-- a number in its box: drag up / down (Shift: fine), double-click: back to
-- def (when it has one; else to type), Ctrl+click to type;
-- a small upright slider at the right shows where it sits in its range,
-- value and slider in the control's own colour c; gives changed, v, done
UI.nb = {}
function UI.numbox(id, v, lo, hi, fmt, w, c, tipx, def)
  local nb = UI.nb
  c = c or COL.text
  local h = ImGui.GetFrameHeight(ctx)
  local logr = lo > 0 and hi / lo >= 20
  local function frac(val)
    val = clampv(val, lo, hi)
    if logr then return math.log(val / lo) / math.log(hi / lo) end
    return (val - lo) / (hi - lo)
  end
  local function unfrac(f) if logr then return lo * (hi / lo) ^ f end return lo + f * (hi - lo) end
  if nb.edit == id then
    ImGui.SetNextItemWidth(ctx, w)
    if nb.focus then ImGui.SetKeyboardFocusHere(ctx); nb.focus = false end
    -- typed: taken when the field is left (Enter, Tab or a click away)
    local ch, nv = ImGui.InputDouble(ctx, id .. "_in", nb.val or v, 0, 0, "%.3f")
    if ch and nv then nb.val = nv end
    if ImGui.IsItemDeactivated(ctx) then
      local val = nb.val
      nb.edit, nb.val = nil, nil
      if val then return true, clampv(val, lo, hi), true end
    end
    return false, v, false
  end
  local x, y = ImGui.GetCursorScreenPos(ctx)
  ImGui.InvisibleButton(ctx, id, w, h)
  local hv, act_ = ImGui.IsItemHovered(ctx), ImGui.IsItemActive(ctx)
  local _, my = ImGui.GetMousePos(ctx)
  local ctrl = (ImGui.GetKeyMods(ctx) & (K("Mod_Ctrl") or 0)) ~= 0
  if ImGui.IsItemActivated(ctx) then nb[id] = { y0 = my, f0 = frac(v) } end
  if (hv and ImGui.IsMouseDoubleClicked(ctx, 0) and def == nil) or (ImGui.IsItemActivated(ctx) and ctrl) then nb.edit = id; nb.focus = true; nb.val = nil end
  local nv = v
  if hv and def ~= nil and ImGui.IsMouseDoubleClicked(ctx, 0) then
    nv = clampv(def, lo, hi); nb[id] = { y0 = my, f0 = frac(nv) }
  end
  if act_ and nb[id] and nv == v then
    local fine = (ImGui.GetKeyMods(ctx) & KEY_MOD_SHIFT) ~= 0
    nv = unfrac(clampv(nb[id].f0 + (nb[id].y0 - my) / 160 * (fine and 0.2 or 1), 0, 1))
  end
  local done = ImGui.IsItemDeactivated(ctx) and nb[id] ~= nil
  if not act_ then nb[id] = nil end
  local dl = ImGui.GetWindowDrawList(ctx)
  ImGui.DrawList_AddRectFilled(dl, x, y, x + w, y + h, COL.field, 3)
  if hv or act_ then ImGui.DrawList_AddRect(dl, x, y, x + w, y + h, (c & 0xffffff00) | 0x90, 3, 0, 1) end
  local sx, t0, t1 = x + w - 7, y + 3, y + h - 3
  local fy = t1 - frac(nv) * (t1 - t0)
  ImGui.DrawList_AddRectFilled(dl, sx, t0, sx + 3, t1, COL.chip_on, 1.5)
  ImGui.DrawList_AddRectFilled(dl, sx, fy, sx + 3, t1, (c & 0xffffff00) | 0xb0, 1.5)
  ImGui.DrawList_AddRectFilled(dl, sx - 1.5, fy - 1, sx + 4.5, fy + 1, (hv or act_) and COL.text or c)
  local s = string.format(fmt, nv)
  local tw = (ImGui.CalcTextSize(ctx, s))
  ImGui.DrawList_AddText(dl, x + math.max(4, (w - 10 - tw) / 2), y + (h - ImGui.GetTextLineHeight(ctx)) / 2, c, s)
  if hv or act_ then
    UI.cursor("ns")
    if tipx then ImGui.SetTooltip(ctx, tipx .. (def ~= nil and "\nDrag up / down (Shift: fine), double-click: back to " .. string.format(fmt, def) .. ", Ctrl+click: type"
      or "\nDrag up / down (Shift: fine), double-click to type")) end
  end
  return nv ~= v, nv, done
end

-- after a slider: double-clicked, so back to its default
function UI.dbl() return ImGui.IsItemHovered(ctx) and ImGui.IsMouseDoubleClicked(ctx, 0) end

-- a smaller heading inside a section
function UI.sub(title, col)
  ImGui.TextColored(ctx, col or COL.label, title)
end

-- a segmented switch: the labels side by side, the current one lit; gives
-- the index picked, or nil
function UI.seg(id, labels, cur, tips)
  local pick
  for i, l in ipairs(labels) do
    if i > 1 then ImGui.SameLine(ctx, 0, 1) end
    if choice(l .. "##" .. id .. i, i == cur, tips and tips[i]) then pick = i end
  end
  return pick
end

--@pro TS_DT_Pro_Window.lua:9

local function draw_panel(kit, drums)
  local t = S.tab
  if t == "kit" then draw_roles(kit, drums)
  elseif t == "detect" then
    if UI.section_begin("det_sel", 0, 0, true) then draw_selected(kit); UI.section_end() end
    ImGui.Dummy(ctx, 0, 2)
    if UI.section_begin("det_run", 0, 0) then draw_detect(kit); UI.section_end() end
  elseif t == "align" then draw_align(kit)
  elseif t == "quant" then UI.draw_quant(kit)
--@pro TS_DT_Pro_Window.lua:10
  elseif UI.PRO_TAB[t] then UI.pro_card(t) end
end

-- the lanes on top; the workflow tabs head the panel below them
local function draw_tabs()
  local kit, drums = kit_now()
--@pro TS_DT_Pro_Window.lua:11
  draw_transport()
  local _, avail = ImGui.GetContentRegionAvail(ctx)
  if not S.lanes_h then S.lanes_h = tonumber(r.GetExtState("TS_DrumToolbox", "lanes_h")) or avail * 0.55 end
  S.lanes_h = clampv(S.lanes_h, 120, math.max(120, avail - 140))
  if ImGui.BeginChild(ctx, "lanes", 0, S.lanes_h, 0, CHILD_NOSCROLL) then
    draw_lanes(kit)
    ImGui.EndChild(ctx)
  end
  -- the bar between lanes and panel: drag to share the height
  local sx, sy = ImGui.GetCursorScreenPos(ctx)
  local sw = ImGui.GetContentRegionAvail(ctx)
  ImGui.InvisibleButton(ctx, "##split", math.max(1, sw), 7)
  local act, hovs = ImGui.IsItemActive(ctx), ImGui.IsItemHovered(ctx)
  if act then
    local _, dy = ImGui.GetMouseDelta(ctx)
    S.lanes_h = S.lanes_h + dy
  end
  if ImGui.IsItemDeactivated(ctx) then r.SetExtState("TS_DrumToolbox", "lanes_h", string.format("%.0f", S.lanes_h), true) end
  if hovs or act then ImGui.SetMouseCursor(ctx, K("MouseCursor_ResizeNS") or 0) end
  local dlw = ImGui.GetWindowDrawList(ctx)
  ImGui.DrawList_AddLine(dlw, sx + sw / 2 - 20, sy + 3, sx + sw / 2 + 20, sy + 3, (hovs or act) and COL.accent or COL.edge, 2)
  draw_tab_row()
  if ImGui.BeginChild(ctx, "panel", 0, 0) then
    draw_panel(kit, drums)
    ImGui.EndChild(ctx)
  end
--@pro TS_DT_Pro_Window.lua:12
  lane_keys(kit)
  pass_keys()
end

-- ---------------------------------------------------------------------
-- loop
-- ---------------------------------------------------------------------
DT.install_builtins()
local first = true

-- ChannelView's panel asks for a drum (and a tab): "GUID|tab"
UI.FOCUS_TAB = { gate = "gate", tone = "enhance", enhance = "enhance", noise = "reinforce", samp = "reinforce", inst = "reinforce", reinforce = "reinforce" }
function UI.take_focus()
  local f = r.GetExtState("TS_DrumToolbox", "focus")
  if f == "" then return end
  r.DeleteExtState("TS_DrumToolbox", "focus", false)
  local g, tab = f:match("^([^|]+)|?(.*)$")
  for i = 0, r.CountTracks(0) - 1 do
    local t = r.GetTrack(0, i)
    if r.GetTrackGUID(t) == g then S.cur = t end
  end
  if UI.FOCUS_TAB[tab or ""] then S.tab = UI.FOCUS_TAB[tab] end
end
r.SetExtState("TS_DrumToolbox", "running", "1", false)
r.atexit(function() r.SetExtState("TS_DrumToolbox", "running", "0", false) end)

local function loop()
  UI.take_focus()
  poll_align()
  run_detect()
  run_measure()
--@pro TS_DT_Pro_Window.lua:13
  poll_audition()

  set_accent(S.tab)
  push_style()
  if first then
    ImGui.SetNextWindowSize(ctx, 980, 680, ImGui.Cond_FirstUseEver); first = false
    S.outcome = S.outcome or UI.load_outcome()        -- what Align found last time
    if not S.det_result then
      local _, v = r.GetProjExtState(0, "TS_DrumToolbox", "det_result")
      local t = DT.deserialize(v)
      if t and t.lines then S.det_result = t end
    end
  end
  local visible, open = ImGui.Begin(ctx, TITLE .. " " .. DT.VERSION .. "###TS_DrumToolbox", true)
  if visible then
    draw_tabs()
    ImGui.End(ctx)
  end
  pop_style()

  if open then
    r.defer(loop)
  else
    if S.det then stop_detect() end
    if S.meas then S.meas.job:cancel() end
    aud_restore()
  end
end

r.defer(loop)
