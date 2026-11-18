-- @noindex
--[[
  TS_DrumToolbox_Detect.lua -- set up the kit, detect, discount bleed,
  without opening the window.
  1. Kit roles: every track gets a role (drum, second mic, bleed source,
     reference, ignore). Tracks without one are given the role their name
     suggests; the kit is printed. Roles set by hand win.
  2. Detect: the drums and bleed sources among the selected tracks (a
     selected folder counts as everything in it), or the whole kit if no
     track is selected. Runs in the background with a progress window, so
     REAPER stays usable; close the window to stop.
  3. Kit check: bleed between every detected track and the rest of the
     kit is discounted.
  Prints a report to the console. One undo point, at the end.

  Profiles are written on first run to
  <resource>/Data/TS_DrumToolbox/detect/ -- edit them there and run again.
]]

local r = reaper
local dir = debug.getinfo(1, "S").source:match("^@?(.*[\\/])") or ""
package.path = dir .. "?.lua;" .. package.path
local DT = require("TS_DrumToolbox_core")

local function say(fmt, ...) r.ShowConsoleMsg(string.format(fmt, ...)) end

DT.install_builtins()
r.ClearConsole()
say("TS DrumToolbox %s -- detect\nprofiles: %s\n\n", DT.VERSION, DT.profile_dir("detect"))

-- 1. roles ---------------------------------------------------------------
local stored = DT.store_suggested_roles()
local kit = DT.kit_roles()
say("kit%s:\n", stored > 0 and string.format(" (%d roles suggested from names and stored)", stored) or "")
for _, e in ipairs(kit) do
  if e.role ~= "ignore" then
    local extra = ""
    if e.role == "second" then extra = "of " .. (e.of and select(2, r.GetTrackName(e.of)) or "?")
    elseif e.profile then extra = "profile " .. e.profile end
    local depth, p = 0, e.parent
    while p do depth = depth + 1; p = r.GetParentTrack(p) end
    say("  %-22s %-13s %s%s\n", string.rep("  ", depth) .. e.name, DT.ROLE_LABEL[e.role] or e.role, extra,
      e.user and "  (set by hand)" or "")
  end
end

-- what to detect
local _, sel = DT.expand_selection()
local any_sel = next(sel) ~= nil
local todo = {}
for _, e in ipairs(kit) do
  if (e.role == "drum" or e.role == "bleed") and (not any_sel or sel[e.track]) then todo[#todo + 1] = e end
end
local what = any_sel and "the selected kit tracks" or "the whole kit"
if any_sel and #todo == 0 then
  for _, e in ipairs(kit) do
    if e.role == "drum" or e.role == "bleed" then todo[#todo + 1] = e end
  end
  what = "the whole kit (no drums or bleed sources were selected)"
end
if #todo == 0 then
  say("\nno drums or bleed sources in this project.\n")
  return
end
say("\ndetecting %s:\n", what)

-- 3. kit check (runs once detection is done) --------------------------------
local done = {}
local function finish(cancelled)
  if #done > 0 then
    local kt = DT.kit_tracks()
    local names = {}
    for _, k in ipairs(kt) do names[#names + 1] = k.name end
    say("\nbleed check across: %s\n", table.concat(names, ", "))
    local total = 0
    r.PreventUIRefresh(1)
    for _, d in ipairs(done) do
      local ok, k = pcall(DT.kit_check, d.track, { profile = d.profile, kit = kt })
      local hits = DT.track_hits(d.track)
      local review, low = 0, 0
      for _, h in ipairs(hits) do
        if (h.c or 1) < DT.C_HI then review = review + 1 end
        if (h.c or 1) < DT.C_MID then low = low + 1 end
      end
      total = total + #hits
      if ok then
        local from = {}
        for nm, c in pairs(k.from) do from[#from + 1] = string.format("%d from %s", c, nm) end
        table.sort(from)
        say("  %-20s %4d hits  bleed discounted %d%s  rescued %d  odd %d  to review %d (%d red)\n",
          d.name, #hits, k.discounted, #from > 0 and (" (" .. table.concat(from, ", ") .. ")") or "",
          k.kept_by_tilt, k.odd, review, low)
        if k.own_tilt then
          say("  %-20s      tone: own %+.1f dB%s%s\n", "", k.own_tilt,
            k.bleed_tilt and string.format(", bleed %+.1f dB", k.bleed_tilt) or "",
            (k.bleed_tilt and not k.tone_tells) and string.format("  -> too alike, level decides (own %.1f dB)", k.own_db or 0) or "")
        end
      else
        say("  %-20s kit check ERROR: %s\n", d.name, tostring(k))
      end
    end
    r.PreventUIRefresh(-1)
    say("\n%d hits. Green = confident, amber = check, red = likely bleed, white = locked.\n", total)
  end
  if cancelled then say("\nstopped -- tracks not reached keep their previous hit map.\n") end
  r.UpdateArrange()
  r.Undo_OnStateChange2(0, "TS DrumToolbox: detect kit")
end

-- 2. detect, in the background ----------------------------------------------
local W, H = 420, 96
gfx.init("TS DrumToolbox -- detecting", W, H, 0)
gfx.setfont(1, "Arial", 15)

local ji, job, jt0 = 0, nil, 0
local t_start = r.time_precise()

local function bar(x, y, w, h, f, col)
  gfx.set(0.17, 0.19, 0.24, 1); gfx.rect(x, y, w, h, 1)
  gfx.set(col[1], col[2], col[3], 1); gfx.rect(x, y, math.floor(w * math.max(0, math.min(1, f)) + 0.5), h, 1)
end

local function draw()
  gfx.set(0.067, 0.075, 0.10, 1); gfx.rect(0, 0, gfx.w, gfx.h, 1)
  local e = todo[ji]
  local f = job and job.progress or 0
  gfx.set(0.84, 0.85, 0.89, 1); gfx.x, gfx.y = 12, 10
  gfx.drawstr(string.format("%s  (%d of %d)  %s", e and e.name or "", ji, #todo, job and job.label or ""))
  bar(12, 34, W - 24, 10, f, { 0.29, 0.62, 0.85 })
  bar(12, 52, W - 24, 6, ((ji - 1) + f) / #todo, { 0.30, 0.79, 0.65 })
  gfx.set(0.46, 0.50, 0.56, 1); gfx.x, gfx.y = 12, 68
  gfx.drawstr(string.format("%.0f s  -  close this window to stop", r.time_precise() - t_start))
  gfx.update()
end

local function step()
  if gfx.getchar() < 0 then                       -- window closed: stop
    if job then job:cancel() end
    gfx.quit()
    finish(true)
    return
  end
  if not job then
    ji = ji + 1
    local e = todo[ji]
    if not e then
      gfx.quit()
      finish(false)
      return
    end
    job = DT.detect_job(e.track, { profile = e.profile, mode = "replace" })
    jt0 = r.time_precise()
  end
  local fin = job:step(0.06)
  if fin then
    local e = todo[ji]
    if job.error then
      say("  %-20s ERROR: %s\n", e.name, job.error)
    else
      local rep = job.report
      done[#done + 1] = e
      say("  %-20s %-12s %4d hits  (%d kept locked)  %.1fs\n", e.name, rep.profile, rep.hits, rep.kept, r.time_precise() - jt0)
    end
    job = nil
  end
  draw()
  r.defer(step)
end

r.defer(step)
