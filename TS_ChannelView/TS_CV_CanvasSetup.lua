-- @noindex
-- Not a package of its own: installed by TS_ChannelView.lua's @provides.
--[[
  TS_CV_CanvasSetup.lua -- setting up an EQ or Compressor layout for any
  plugin.

  EQ: up to 8 bands, each naming the plugin's controls for it (frequency,
  gain, Q, a shape switch, an On switch -- any can be left out). Its shape
  isn't chosen here: Learn measures a hidden copy of the plugin
  (TS_CV_Learn). Done is only offered once every band is learned for its
  mapping as it is; leaving before that keeps the layout, and its panel
  offers to finish it. Changing a band's mapping means learning it again.

  Compressor: each role (Threshold, Ratio, Knee, Attack, Hold, Release,
  Make-up, Mix) names a control, or none. No learning: the canvas takes
  the plugin's own values. A "Compression" control is a threshold the
  other way round: tick Reversed. So can an attack, hold or release that
  doesn't read in time (a 1176's 1 to 7, fastest at 7).

  Every change is saved as it's made. The window is modal while it's
  open; closing it during learning cancels the learning.
--]]

local C  = require("TS_CV_Config")
local U  = require("TS_CV_Util")
local M  = require("TS_CV_Mappings")
local ME = require("TS_CV_MapEQ")
local LN = require("TS_CV_Learn")

local CS = {}
local ImGui

function CS.attach(imgui) ImGui = imgui end

local dlg = nil
local TITLE = "Set up layout###tscvcanvas"

local function names_of(track, addr)
  local out = {}
  for p = 0, (reaper.TrackFX_GetNumParams(track, addr) or 0) - 1 do
    local _, nm = reaper.TrackFX_GetParamName(track, addr, p, "")
    out[p + 1] = nm or ("Param " .. (p + 1))
  end
  return out
end

-- ---------------------------------------------------------------------
-- guesses
-- ---------------------------------------------------------------------

local COMP_WORDS = {
  Threshold = { "thresh", "compression", "peak reduction", "squeeze" },
  Input     = { "input", "drive" },
  Ratio     = { "ratio" },
  Knee      = { "knee" },
  Attack    = { "attack", "atk" },
  Hold      = { "hold" },
  Release   = { "release", "rel" },
  Makeup    = { "makeup", "make up", "make-up", "gain out", "output gain" },
  Mix       = { "mix", "blend", "dry/wet", "parallel" },
}

-- A first go at a canvas from the parameters' names.
function CS.guess(names, kind)
  if kind == "eq" then
    local bands = ME.guess(names)
    local all_on
    for p0, nm in ipairs(names) do
      local l = (nm or ""):lower()
      if l:match("eq in") or l:match("eq on") or l:match("^eq bypass") then all_on = p0 - 1 break end
    end
    return { kind = "eq", bands = bands, all_on = all_on }
  end
  local roles, rev = {}, {}
  for _, r in ipairs(M.COMP_ROLES) do
    for p0, nm in ipairs(names) do
      local l = " " .. (nm or ""):lower() .. " "
      local taken = false
      for _, v in pairs(roles) do if v == p0 - 1 then taken = true end end
      if not taken and not roles[r] then
        for _, w in ipairs(COMP_WORDS[r]) do
          if l:find(w, 1, true) and not (r == "Release" and l:match("auto"))
             and not (r == "Input" and roles.Threshold) then
            roles[r] = p0 - 1
            if r == "Threshold" and (l:match("compression") or l:match("peak reduction") or l:match("squeeze")) then
              rev[r] = true
            end
            break
          end
        end
      end
    end
  end
  return { kind = "comp", roles = roles, rev = rev }
end

-- ---------------------------------------------------------------------
-- opening
-- ---------------------------------------------------------------------

function CS.open(track, fx, key)
  local layout = M.get(key)
  if not (layout and layout.canvas) then return end
  if dlg and dlg.job then LN.cancel(dlg.job) end
  dlg = { track = track, fx = fx, addr = fx.addr, guid = fx.guid, key = key,
          names = names_of(track, fx.addr), filter = "", open = true }
end

function CS.is_open() return dlg ~= nil end

local function save()
  local l = M.get(dlg.key)
  if l then
    -- a control the canvas now takes leaves the side columns
    M.drop_placed(l)
    M.set(dlg.key, l); M.save()
  end
end

-- the plugin instance may have moved in the chain since it was opened
local function addr_now()
  if not reaper.ValidatePtr2(0, dlg.track, "MediaTrack*") then return nil end
  local n = reaper.TrackFX_GetCount(dlg.track)
  if dlg.addr and dlg.addr < n and reaper.TrackFX_GetFXGUID(dlg.track, dlg.addr) == dlg.guid then
    return dlg.addr
  end
  local T = require("TS_CV_FXTree")
  for _, f in ipairs(T.collect(dlg.track)) do
    if f.guid == dlg.guid then dlg.addr = f.addr return f.addr end
  end
  return nil
end

-- a parameter picker: a combo with a filter at its top
local function picker(ctx, id, cur, width, allow_none)
  local nm = cur and ((cur + 1) .. ": " .. (dlg.names[cur + 1] or "?")) or "\u{2014}"
  ImGui.SetNextItemWidth(ctx, width)
  local changed, out = false, cur
  if ImGui.BeginCombo(ctx, "##" .. id, nm) then
    if ImGui.IsWindowAppearing(ctx) then dlg.filter = ""; ImGui.SetKeyboardFocusHere(ctx) end
    ImGui.SetNextItemWidth(ctx, 220)
    local _, f = ImGui.InputTextWithHint(ctx, "##flt" .. id, "filter\u{2026}", dlg.filter)
    dlg.filter = f
    if allow_none ~= false and ImGui.Selectable(ctx, "\u{2014} (none)##none" .. id, cur == nil) then
      changed, out = true, nil
    end
    local fl = f:lower()
    for p0, name in ipairs(dlg.names) do
      if fl == "" or name:lower():find(fl, 1, true) then
        if ImGui.Selectable(ctx, ("%d: %s##%s%d"):format(p0, name, id, p0), cur == p0 - 1) then
          changed, out = true, p0 - 1
        end
      end
    end
    ImGui.EndCombo(ctx)
  end
  return changed, out
end

-- ---------------------------------------------------------------------
-- the EQ page
-- ---------------------------------------------------------------------

local FIELDS = { { "freq", "Freq" }, { "gain", "Gain" }, { "q", "Q" }, { "shape", "Shape switch" }, { "on", "On" } }

local function learned_text(b)
  if not (b.freq or b.gain) then return "needs a frequency or gain", C.COL.warn end
  if not M.band_learned(b) then
    return b.learn and "mapping changed: learn again" or "not learned", C.COL.warn
  end
  local L = ME.decode(b.learn)
  if not L then return "not learned", C.COL.warn end
  local e = L.shapes[1]
  if not e then for _, v in pairs(L.shapes) do e = v break end end
  local t = ME.TYPES[e.type] or e.type
  if e.order and (e.type == "hp" or e.type == "lp") then t = t .. (" %d dB/oct"):format(e.order * 6) end
  local n = 0
  for _ in pairs(L.shapes) do n = n + 1 end
  if n > 1 then t = t .. (" (+%d more shapes)"):format(n - 1) end
  if L.D then t = t .. " \u{00B7} its own values"
  elseif e.Q and #e.Q > 1 then
    t = t .. (" \u{00B7} Q %.1f\u{2192}%.1f"):format(e.Q[1][2], e.Q[#e.Q][2])
  elseif e.Q and e.Q[1] then t = t .. (" \u{00B7} Q %.2f"):format(e.Q[1][2]) end
  return t, C.COL.accent
end

local function eq_page(ctx, layout, cv, busy)
  local EQP = require("TS_CV_EQPanel")
  local changed = false
  ImGui.BeginDisabled(ctx, busy)
  local flags = ImGui.TableFlags_RowBg | ImGui.TableFlags_BordersInnerH
  if ImGui.BeginTable(ctx, "##mpbands", 8, flags) then
    ImGui.TableSetupColumn(ctx, "Band", ImGui.TableColumnFlags_WidthFixed, 110)
    for _, f in ipairs(FIELDS) do ImGui.TableSetupColumn(ctx, f[2], ImGui.TableColumnFlags_WidthFixed, 120) end
    ImGui.TableSetupColumn(ctx, "Learned", ImGui.TableColumnFlags_WidthFixed, 230)
    ImGui.TableSetupColumn(ctx, "", ImGui.TableColumnFlags_WidthFixed, 22)
    ImGui.TableHeadersRow(ctx)
    local remove
    for k, b in ipairs(cv.bands) do
      ImGui.TableNextRow(ctx)
      ImGui.TableNextColumn(ctx)
      local col = EQP.util.band_colour(k)
      local x, y = ImGui.GetCursorScreenPos(ctx)
      local dl = ImGui.GetWindowDrawList(ctx)
      ImGui.DrawList_AddRectFilled(dl, x, y + 5, x + 9, y + 14, col, 2.0)
      ImGui.SetCursorScreenPos(ctx, x + 14, y)
      ImGui.SetNextItemWidth(ctx, 92)
      local ch, nm = ImGui.InputText(ctx, "##bn" .. k, b.name or "")
      if ch then b.name = nm; changed = true end
      for _, f in ipairs(FIELDS) do
        ImGui.TableNextColumn(ctx)
        local c2, v = picker(ctx, "b" .. k .. f[1], b[f[1]], 116)
        if c2 then b[f[1]] = v; changed = true end
      end
      ImGui.TableNextColumn(ctx)
      local t, tc = learned_text(b)
      ImGui.TextColored(ctx, tc, t)
      ImGui.TableNextColumn(ctx)
      if ImGui.SmallButton(ctx, "\u{00D7}##rm" .. k) then remove = k end
      if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "Remove this band") end
    end
    ImGui.EndTable(ctx)
    if remove then table.remove(cv.bands, remove); changed = true end
  end
  if #cv.bands < M.MAX_BANDS then
    if ImGui.Button(ctx, "+ Band") then
      cv.bands[#cv.bands + 1] = { name = "Band " .. (#cv.bands + 1) }
      changed = true
    end
    ImGui.SameLine(ctx)
  end
  if ImGui.Button(ctx, "Guess from names") then
    local g = CS.guess(dlg.names, "eq")
    if #g.bands > 0 then
      cv.bands = g.bands
      cv.all_on = cv.all_on or g.all_on
      changed = true
    end
  end
  if ImGui.IsItemHovered(ctx) then
    ImGui.SetTooltip(ctx, "Fill the bands in from the plugin's parameter names.\nReplaces the bands above.")
  end
  ImGui.SameLine(ctx)
  ImGui.Text(ctx, "  All bands On:")
  ImGui.SameLine(ctx)
  local ca, va = picker(ctx, "allon", cv.all_on, 160)
  if ca then cv.all_on = va; changed = true end
  if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "A single EQ In / EQ On switch for the whole EQ, if it has one") end
  ImGui.EndDisabled(ctx)
  return changed
end

-- ---------------------------------------------------------------------
-- the compressor page
-- ---------------------------------------------------------------------

local ROLE_NAMES = { Makeup = "Make-up" }
-- the roles that can run the other way, and what that means for each
local REV_TIPS = {
  Threshold = "A \"Compression\" or \"Peak reduction\" control: more of it\n" ..
              "is a lower threshold",
  Attack = "Turning it up makes the attack faster (a 1176's 1 to 7).\n" ..
           "Only matters when it doesn't read in ms.",
  Hold = "Turning it up makes the hold shorter.\nOnly matters when it doesn't read in ms.",
  Release = "Turning it up makes the release faster (a 1176's 1 to 7).\n" ..
            "Only matters when it doesn't read in ms or seconds.",
}

local function comp_page(ctx, cv)
  local changed = false
  cv.roles = cv.roles or {}
  cv.rev = cv.rev or {}
  local flags = ImGui.TableFlags_RowBg | ImGui.TableFlags_BordersInnerH
  if ImGui.BeginTable(ctx, "##mproles", 3, flags) then
    ImGui.TableSetupColumn(ctx, "Role", ImGui.TableColumnFlags_WidthFixed, 150)
    ImGui.TableSetupColumn(ctx, "Parameter", ImGui.TableColumnFlags_WidthFixed, 230)
    ImGui.TableSetupColumn(ctx, "Reads as", ImGui.TableColumnFlags_WidthFixed, 230)
    ImGui.TableHeadersRow(ctx)
    local addr = addr_now()
    for _, r in ipairs(M.COMP_ROLES) do
      ImGui.TableNextRow(ctx)
      ImGui.TableNextColumn(ctx)
      ImGui.Text(ctx, ROLE_NAMES[r] or r)
      if r == "Input" and ImGui.IsItemHovered(ctx) then
        ImGui.SetTooltip(ctx, "For a compressor with no threshold control (1176-style):\n" ..
          "its input drives the signal into a fixed threshold, so the\n" ..
          "canvas draws the threshold moving down as the input goes up.\n" ..
          "Ignored when Threshold is mapped. Map its Output as Make-up.")
      end
      if REV_TIPS[r] then
        ImGui.SameLine(ctx)
        local ch, v = ImGui.Checkbox(ctx, "Reversed##rev" .. r, cv.rev[r] == true)
        if ch then cv.rev[r] = v or nil; changed = true end
        if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, REV_TIPS[r]) end
      end
      ImGui.TableNextColumn(ctx)
      local ch, v = picker(ctx, "r" .. r, cv.roles[r], 224)
      if ch then cv.roles[r] = v; changed = true end
      ImGui.TableNextColumn(ctx)
      if cv.roles[r] and addr then
        local _, t = reaper.TrackFX_GetFormattedParamValue(dlg.track, addr, cv.roles[r], "")
        local UN = require("TS_CV_Units")
        local _, unit = UN.parse(t)
        local want = ({ Threshold = "db", Input = "db", Knee = "db", Makeup = "db", Attack = "ms", Hold = "ms",
                        Release = "ms", Ratio = "ratio", Mix = "pct" })[r]
        local note = (t or "")
        if want and unit ~= want and not (r == "Threshold" and cv.rev.Threshold) then
          note = note .. "   (not " .. want .. ": along its range)"
        end
        ImGui.TextDisabled(ctx, note)
      end
    end
    ImGui.EndTable(ctx)
  end
  if ImGui.Button(ctx, "Guess from names") then
    local g = CS.guess(dlg.names, "comp")
    cv.roles, cv.rev = g.roles, g.rev
    changed = true
  end
  return changed
end

-- ---------------------------------------------------------------------
-- the window
-- ---------------------------------------------------------------------

local function draw_body(ctx, layout, cv, job, busy)
  local base, var = M.split_variant(dlg.key)
  ImGui.Text(ctx, ("%s  \u{00B7}  %s layout \"%s\""):format(base, cv.kind == "eq" and "EQ" or "Compressor", var or "Default"))
  ImGui.Spacing(ctx)
  local changed
  if cv.kind == "eq" then
    ImGui.TextWrapped(ctx, "Name each band's controls. Its shape isn't set here: Learn measures a hidden copy " ..
      "of the plugin and works it out. A band that shows its frequency in Hz, its gain in dB and has a Q " ..
      "control is learned in a moment; the others take longer.")
    ImGui.Spacing(ctx)
    changed = eq_page(ctx, layout, cv, busy)
  else
    ImGui.TextWrapped(ctx, "Name the plugin's control for each role, or leave it out. The canvas takes the " ..
      "plugin's own values; a control that doesn't read in its unit moves along its range.")
    ImGui.Spacing(ctx)
    changed = comp_page(ctx, cv)
  end
  if changed then save() end

  ImGui.Separator(ctx)
  if cv.kind == "eq" then
    local addr = addr_now()
    local any_mapped = #cv.bands > 0
    for _, b in ipairs(cv.bands) do if not (b.freq or b.gain) then any_mapped = false end end
    local todo = M.canvas_todo(cv)
    if busy then
      ImGui.ProgressBar(ctx, job.progress or 0, 360, 0, ("%d%%"):format(math.floor((job.progress or 0) * 100)))
      ImGui.SameLine(ctx)
      ImGui.Text(ctx, job.msg or "")
      ImGui.SameLine(ctx)
      if ImGui.Button(ctx, "Cancel##learn") then LN.cancel(job) end
    else
      ImGui.BeginDisabled(ctx, not (any_mapped and addr))
      local label = todo and "Learn" or "Learn again"
      if ImGui.Button(ctx, label .. "##learn") then
        local play = reaper.GetPlayState() & 1 == 1
        if play and reaper.MB("Learning works best with the transport stopped. Learn anyway?",
            "ChannelView", 4) ~= 6 then
          -- not now
        else
          local which = nil
          if not todo then
            which = {}
            for k in ipairs(cv.bands) do which[#which + 1] = k end
          end
          dlg.job = LN.start(dlg.track, addr, dlg.key, layout, which)
        end
      end
      ImGui.EndDisabled(ctx)
      if ImGui.IsItemHovered(ctx, ImGui.HoveredFlags_AllowWhenDisabled) then
        ImGui.SetTooltip(ctx, any_mapped and
          "Measure a hidden copy of the plugin and work out each band's shape.\n" ..
          "Your track isn't touched. Takes up to a minute."
          or "Every band needs a frequency or gain control first.")
      end
      if job and job.msg and job.state ~= "measuring" then
        ImGui.SameLine(ctx)
        ImGui.TextColored(ctx, job.state == "done" and C.COL.accent or C.COL.warn, job.msg)
      end
    end
    ImGui.Spacing(ctx)
    ImGui.BeginDisabled(ctx, todo ~= nil or busy)
    if ImGui.Button(ctx, "Done", 90, 0) then dlg = nil; ImGui.CloseCurrentPopup(ctx) end
    ImGui.EndDisabled(ctx)
    if todo and ImGui.IsItemHovered(ctx, ImGui.HoveredFlags_AllowWhenDisabled) then
      ImGui.SetTooltip(ctx, "Every band has to be learned first.")
    end
    ImGui.SameLine(ctx)
    if not busy and todo and ImGui.Button(ctx, "Leave for now") then
      dlg = nil; ImGui.CloseCurrentPopup(ctx)
    end
  else
    if ImGui.Button(ctx, "Done", 90, 0) then dlg = nil; ImGui.CloseCurrentPopup(ctx) end
  end
end

-- Call once a frame, outside any panel.
function CS.draw(ctx)
  if not dlg then return end
  local layout = M.get(dlg.key)
  if not (layout and layout.canvas) then dlg = nil return end
  local cv = layout.canvas
  local job = dlg.job
  if job then LN.step(job) end
  local busy = job ~= nil and (job.state == "starting" or job.state == "measuring")

  if dlg.open then ImGui.OpenPopup(ctx, TITLE); dlg.open = false end
  ImGui.SetNextWindowSize(ctx, cv.kind == "eq" and 1060 or 640, 0, ImGui.Cond_Appearing)
  local visible, open = ImGui.BeginPopupModal(ctx, TITLE, true, ImGui.WindowFlags_AlwaysAutoResize)
  if visible then
    draw_body(ctx, layout, cv, job, busy)
    ImGui.EndPopup(ctx)
  elseif not open then
    if job then LN.cancel(job) end
    dlg = nil
  end
end

-- A new EQ or Compressor layout for this instance, named `name`, guessed
-- from the plugin's parameter names, then opened for setting up.
-- Returns its variant name, or nil when the name won't do.
function CS.create(track, fx, base, name, kind, from)
  local k, nm = M.new_variant(base, name, from, false)
  if not k then return nil end
  local l = M.get(k)
  l.canvas = CS.guess(names_of(track, fx.addr), kind)
  -- the layout it was made from comes across: its faceplate, and the
  -- controls the canvas doesn't take, with their looks
  M.drop_placed(l)
  M.set(k, l)
  M.save()
  CS.open(track, fx, k)
  return nm, k
end

return CS
