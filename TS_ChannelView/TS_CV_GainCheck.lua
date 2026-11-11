-- @noindex
-- Not a package of its own: installed by TS_ChannelView.lua's @provides.
--[[
  TS_CV_GainCheck.lua -- checking a plugin's gain knobs.

  A plugin whose gain reduction the probes measure (a compressor, limiter,
  gate, de-esser, multiband) needs its own gains taken out of what they
  measure: its input, make-up and output knobs (TS_CV_Taps, MAKE-UP GAIN,
  FOLLOWED). Those are found by name (TS_CV_Taps TP.gain_candidates) and
  shown here for the user to say what each is (TS_CV_Mappings GainRole<p>,
  GainCheck), then measured on a hidden copy (TS_CV_Learn LN.start_gain)
  in a window of their own that holds nothing else up: which knob, how far,
  Cancel, and what each came to.

  Offered on a measured plugin's panel, while stopped, until checked
  (GC.offer); from the panel menu any time; and after a compressor's
  canvas is learned (TS_CV_CanvasSetup).
--]]

local C  = require("TS_CV_Config")
local U  = require("TS_CV_Util")
local M  = require("TS_CV_Mappings")

local GC = {}
local ImGui
function GC.attach(imgui) ImGui = imgui end

local function names_of(track, addr)
  local out = {}
  for p = 0, (reaper.TrackFX_GetNumParams(track, addr) or 0) - 1 do
    local _, nm = reaper.TrackFX_GetParamName(track, addr, p, "")
    out[p + 1] = nm or ("Param " .. (p + 1))
  end
  return out
end

local gd = nil
local GTITLE = "Gain knobs###tscvgain"
local GROLES = { { "in", "Input gain" }, { "mu", "Make-up gain" }, { "out", "Output gain" }, { "no", "Not a gain" } }
local GROLE_NAME = {}
for _, r in ipairs(GROLES) do GROLE_NAME[r[1]] = r[2] end
local GAIN_S = 12                 -- s, about, to measure a knob
local SAID_S = 2.5                -- s a success stays up before the window closes

local function TPm() return require("TS_CV_Taps") end

local function gain_addr()
  local T = require("TS_CV_FXTree")
  for _, f in ipairs(T.collect(gd.track)) do
    if f.guid == gd.guid then return f.addr end
  end
  return nil
end

local function gain_new(track, fx, key, stage)
  return { track = track, guid = fx.guid, name = U.clean_fx_name(fx.name or ""), key = key,
           names = names_of(track, fx.addr), filter = "", stage = stage, open = true }
end

-- The check, for a plugin: what it found, for correcting.
function GC.open(track, fx, key)
  local l = M.get(key) or M.get_or_default(key, track, fx.addr, fx.guid)
  gd = gain_new(track, fx, key, "check")
  gd.rows = {}
  for _, c in ipairs(TPm().gain_candidates(track, fx.addr, l)) do gd.rows[#gd.rows + 1] = { p = c[1], role = c[2] } end
end

-- The roles kept, and what's a gain measured.
local function gain_go(addr)
  local TP = TPm()
  local l = M.get(gd.key)
  if not l then
    M.set(gd.key, M.copy(M.get_or_default(gd.key, gd.track, addr, gd.guid)))
    l = M.get(gd.key)
  end
  l.gainrole, l.gaincheck = {}, true
  local ps, seen = {}, {}
  for _, r in ipairs(gd.rows) do
    if r.p and not seen[r.p] then
      seen[r.p] = true
      l.gainrole[r.p] = r.role
      if r.role == "no" then
        if l.gainlaw then l.gainlaw[r.p] = nil end
      else
        ps[#ps + 1] = r.p
      end
    end
  end
  if not next(l.gainrole) then l.gainrole = nil end
  M.set(gd.key, l)
  M.share_gain(gd.key)
  M.save()
  TP.makeup_changed()
  if #ps == 0 then gd = nil return end
  table.sort(ps)
  if TP.measure_gain(gd.track, addr, gd.key, M.get(gd.key), ps) then
    gd.stage = "measure"
  else
    gd.err = "Another plugin's gain knobs are being measured."
  end
end

local function knob_name(p) return gd.names[p + 1] or ("Parameter " .. (p + 1)) end

local function gain_picker(ctx, i, cur)
  local changed, out = false, cur
  ImGui.SetNextItemWidth(ctx, 200)
  if ImGui.BeginCombo(ctx, "##gknob" .. i, cur and knob_name(cur) or "\u{2014}", ImGui.ComboFlags_HeightLargest) then
    if ImGui.IsWindowAppearing(ctx) then gd.filter = ""; ImGui.SetKeyboardFocusHere(ctx) end
    ImGui.SetNextItemWidth(ctx, 200)
    local _, f = ImGui.InputTextWithHint(ctx, "##gflt" .. i, "filter\u{2026}", gd.filter)
    gd.filter = f
    local fl = f:lower()
    for p0, name in ipairs(gd.names) do
      if fl == "" or name:lower():find(fl, 1, true) then
        if ImGui.Selectable(ctx, ("%s##gk%d_%d"):format(name, i, p0), cur == p0 - 1) then changed, out = true, p0 - 1 end
      end
    end
    ImGui.EndCombo(ctx)
  end
  return changed, out
end

local function gain_check(ctx, addr)
  local playing = ((reaper.GetPlayState() or 0) & 1) == 1
  if #gd.rows == 0 then
    ImGui.TextDisabled(ctx, "No gain knobs found by name.")
  elseif ImGui.BeginTable(ctx, "##gtab", 4, ImGui.TableFlags_SizingFixedFit) then
    ImGui.TableSetupColumn(ctx, "Knob")
    ImGui.TableSetupColumn(ctx, "Is")
    ImGui.TableSetupColumn(ctx, "Reads now")
    ImGui.TableSetupColumn(ctx, "")
    ImGui.TableHeadersRow(ctx)
    local drop
    for i, r in ipairs(gd.rows) do
      ImGui.TableNextRow(ctx)
      ImGui.TableNextColumn(ctx)
      local ch, np = gain_picker(ctx, i, r.p)
      if ch then r.p = np end
      ImGui.TableNextColumn(ctx)
      ImGui.SetNextItemWidth(ctx, 130)
      if ImGui.BeginCombo(ctx, "##grole" .. i, GROLE_NAME[r.role] or "") then
        for _, ro in ipairs(GROLES) do
          if ImGui.Selectable(ctx, ro[2] .. "##gr" .. i .. ro[1], r.role == ro[1]) then r.role = ro[1] end
        end
        ImGui.EndCombo(ctx)
      end
      ImGui.TableNextColumn(ctx)
      local _, fv = "", ""
      if r.p and addr then _, fv = reaper.TrackFX_GetFormattedParamValue(gd.track, addr, r.p, "") end
      ImGui.AlignTextToFramePadding(ctx)
      ImGui.Text(ctx, fv or "")
      ImGui.TableNextColumn(ctx)
      if r.added and ImGui.SmallButton(ctx, "\u{2715}##gdel" .. i) then drop = i end
    end
    ImGui.EndTable(ctx)
    if drop then table.remove(gd.rows, drop) end
  end
  if ImGui.Button(ctx, "+ Add a knob") then
    local used = {}
    for _, r in ipairs(gd.rows) do if r.p then used[r.p] = true end end
    local p = 0
    while used[p] and p < #gd.names - 1 do p = p + 1 end
    gd.rows[#gd.rows + 1] = { p = p, role = "mu", added = true }
  end
  ImGui.Separator(ctx)
  local n = 0
  for _, r in ipairs(gd.rows) do if r.p and r.role ~= "no" then n = n + 1 end end
  if gd.err then ImGui.TextColored(ctx, C.COL.warn, gd.err) end
  ImGui.TextDisabled(ctx, n > 0 and ("Measured on a hidden copy, while stopped. About %d s."):format(n * GAIN_S)
    or "Nothing to measure.")
  if ImGui.Button(ctx, "Cancel") then gd = nil return end
  ImGui.SameLine(ctx)
  local block = playing and n > 0
  if block then ImGui.BeginDisabled(ctx, true) end
  ImGui.PushStyleColor(ctx, ImGui.Col_Button, C.COL.accent)
  ImGui.PushStyleColor(ctx, ImGui.Col_Text, C.COL.icon_on)
  local go = ImGui.Button(ctx, n > 0 and "Measure" or "Save")
  ImGui.PopStyleColor(ctx, 2)
  if block then ImGui.EndDisabled(ctx) end
  if block and ImGui.IsItemHovered(ctx, ImGui.HoveredFlags_AllowWhenDisabled) then
    ImGui.SetTooltip(ctx, "Stop playback first.")
  end
  if go and addr then gain_go(addr) end
end

local function gain_measuring(ctx)
  local j = TPm().gain_job()
  if not (j and j.guid == gd.guid) then return end
  ImGui.Text(ctx, ("Measuring %s"):format(knob_name(j.p or 0)))
  if #j.ps > 1 then ImGui.SameLine(ctx); ImGui.TextDisabled(ctx, ("(%d of %d)"):format(j.i, #j.ps)) end
  ImGui.ProgressBar(ctx, j.progress or 0, 320, 0, ("%d%%"):format(math.floor((j.progress or 0) * 100)))
  ImGui.TextDisabled(ctx, j.left and ("About %d s left"):format(math.max(1, math.floor(j.left + 0.5))) or " ")
  ImGui.SameLine(ctx, 0, 40)
  if ImGui.Button(ctx, "Cancel") then TPm().gain_cancel() end
end

local function gain_outcome(ctx)
  local r = gd.res
  local ok = r and not r.cancelled and r.ok
  if not r then
    ImGui.TextDisabled(ctx, "Finished.")
  elseif r.cancelled then
    ImGui.Text(ctx, "Cancelled: nothing changed.")
  else
    for _, k in ipairs(r.results or {}) do
      local nm = (k.name and k.name ~= "") and k.name or knob_name(k.p)
      if k.ok then
        ImGui.TextColored(ctx, C.COL.accent, "\u{2713}")
        ImGui.SameLine(ctx)
        ImGui.Text(ctx, nm .. (k.readout and ": its readout is right" or ": measured, followed as measured"))
      else
        ImGui.TextColored(ctx, C.COL.warn, "\u{2715}")
        ImGui.SameLine(ctx)
        ImGui.Text(ctx, nm .. ": " .. (k.why or "not measured"))
      end
    end
    if (#(r.results or {}) == 0) and r.why then ImGui.TextColored(ctx, C.COL.warn, r.why) end
  end
  if not ok and ImGui.Button(ctx, "Close") then gd = nil end
end

local function gain_window(ctx)
  if not gd then return end
  if not reaper.ValidatePtr(gd.track, "MediaTrack*") then gd = nil return end
  local addr = gain_addr()
  if not addr and gd.stage == "check" then gd = nil return end
  -- measuring: on to the outcome when it ends
  if gd.stage == "measure" then
    local j = TPm().gain_job()
    if not (j and j.guid == gd.guid) then
      gd.stage, gd.res, gd.done_at = "done", TPm().gain_result(gd.guid), reaper.time_precise()
      TPm().gain_forget(gd.guid)
    end
  end
  -- cancelled: gone; all measured: said for a moment, then gone
  if gd.stage == "done" and gd.res and (gd.res.cancelled
      or (gd.res.ok and reaper.time_precise() - gd.done_at > SAID_S)) then
    gd = nil
    return
  end
  if gd.open then
    local vp = ImGui.GetMainViewport(ctx)
    local cx, cy = ImGui.Viewport_GetCenter(vp)
    ImGui.SetNextWindowPos(ctx, cx, cy, ImGui.Cond_Appearing, 0.5, 0.5)
    gd.open = false
  end
  local visible, open = ImGui.Begin(ctx, GTITLE, true,
    ImGui.WindowFlags_NoCollapse | ImGui.WindowFlags_AlwaysAutoResize | ImGui.WindowFlags_NoDocking)
  if visible then
    ImGui.Text(ctx, gd.name)
    ImGui.Spacing(ctx)
    if gd.stage == "check" then gain_check(ctx, addr)
    elseif gd.stage == "measure" then gain_measuring(ctx)
    else gain_outcome(ctx) end
    ImGui.End(ctx)
  end
  -- (closed while measuring: it goes on; the panel's header shows it)
  if not open then gd = nil end
end
GC.draw = gain_window

-- The note on a measured plugin's panel: "Check its gain knobs?". Over
-- the top of its controls, at x, y, w wide; its buttons submitted before
-- them, so they take the clicks. Once per plugin, while stopped.
local gain_later = {}
local gnever_list = nil
local function gnever()
  if not gnever_list then
    gnever_list = {}
    for _, b in ipairs(U.ext_split(reaper.GetExtState(C.EXT_SECT, "gain_never"))) do gnever_list[b] = true end
  end
  return gnever_list
end
local function set_gnever(base)
  local t = gnever()
  t[base] = true
  local out = {}
  for b in pairs(t) do out[#out + 1] = b end
  table.sort(out)
  reaper.SetExtState(C.EXT_SECT, "gain_never", U.ext_join(out), true)
end

function GC.due(track, fx, key)
  if gd or fx.is_container then return false end
  if ((reaper.GetPlayState() or 0) & 1) == 1 then return false end
  local TP = TPm()
  if TP.gain_job() then return false end
  local base = M.split_variant(key)
  if gain_later[base] or gnever()[base] then return false end
  -- checked in another of its layouts: kept alike, so this one too
  local ck = M.gain_checked(key)
  if ck then
    if ck ~= key and M.get(key) then M.share_gain(ck); M.save() end
    return false
  end
  if not TP.is_tapped(track, fx.guid) then return false end
  local cs = TP.cal_status(track, fx.guid)
  return cs ~= nil and cs ~= 0
end

function GC.offer(ctx, dl, track, fx, key, x, y, w)
  if w < 120 or not GC.due(track, fx, key) then return end
  local id = "##cvgain" .. fx.guid
  local _, lh = ImGui.CalcTextSize(ctx, "X")
  local fp_x, fp_y, pad, gap = 6, 2, 6, 4
  local bh = lh + fp_y * 2
  local items = { { "Check\u{2026}", "check" }, { "Not now", "later" }, { "\u{2715}", "never" } }
  local bw, tot = {}, 0
  for i, it in ipairs(items) do bw[i] = ImGui.CalcTextSize(ctx, it[1]) + fp_x * 2; tot = tot + bw[i] + gap end
  local h = bh + pad
  local x0, x1 = x + 2, x + w - 2
  ImGui.DrawList_AddRectFilled(dl, x0, y, x1, y + h, U.with_alpha(C.COL.win_bg, 0xf4), 3.0)
  ImGui.DrawList_AddLine(dl, x0, y + h - 0.5, x1, y + h - 0.5, C.COL.accent, 1.2)
  local text = "Check its gain knobs?"
  local tw = ImGui.CalcTextSize(ctx, text)
  if tw + tot + pad * 3 > x1 - x0 then text = "Gain knobs?"; tw = ImGui.CalcTextSize(ctx, text) end
  if tw + tot + pad * 3 <= x1 - x0 then
    ImGui.DrawList_AddText(dl, x0 + pad, y + (h - lh) * 0.5, C.COL.header_text, text)
  end
  local TIP = { check = "Check which knobs are its input, make-up and output gains,\nthen measure them.",
                later = "Ask again next time ChannelView starts", never = "Don't ask for this plugin" }
  local pick
  local bx = x1 - pad - tot + gap
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_FramePadding, fp_x, fp_y)
  for i, it in ipairs(items) do
    ImGui.SetCursorScreenPos(ctx, bx, y + (h - bh) * 0.5)
    local hot = it[2] == "check"
    if hot then
      ImGui.PushStyleColor(ctx, ImGui.Col_Button, C.COL.accent)
      ImGui.PushStyleColor(ctx, ImGui.Col_Text, C.COL.icon_on)
    end
    if ImGui.Button(ctx, it[1] .. id .. it[2], bw[i], bh) then pick = it[2] end
    if hot then ImGui.PopStyleColor(ctx, 2) end
    if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, TIP[it[2]]) end
    bx = bx + bw[i] + gap
  end
  ImGui.PopStyleVar(ctx)
  local base = M.split_variant(key)
  if pick == "check" then GC.open(track, fx, key)
  elseif pick == "later" then gain_later[base] = true
  elseif pick == "never" then set_gnever(base) end
end

return GC
