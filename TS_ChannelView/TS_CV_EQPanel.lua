-- @noindex
-- Not a package of its own: installed by TS_ChannelView.lua's @provides.
--[[
  TS_CV_EQPanel.lua -- the draggable-node curve canvas that replaces a
  panel's ordinary knob grid whenever that panel's plugin is ReaEQ. All
  the ReaEQ-reading, -writing and curve math lives in TS_CV_ReaEQ.lua;
  this file is ImGui only -- geometry, drawing, hit-testing.

  INTERACTION, per the spec this was built against:
    double-click empty canvas  -- add a node. Which of the five types it
      becomes follows only from WHERE you clicked (RQ.infer_type) --
      extremes are a pass filter, a little in from there is a shelf, the
      broad middle is a bell.
    drag a node                -- left button: moves it (x = freq, log
      scale; y = gain, linear -- ignored for a pass filter, which has none).
    mouse wheel over a node    -- Q.
    right-click a node         -- change its type, or remove it. Neither
      has a real API to lean on (see TS_CV_ReaEQ.lua's header) -- both
      disable the old band and, for a type change, add a fresh one in its
      place, which is a real seam: the old band stays behind, disabled, in
      ReaEQ's own list rather than vanishing.
    hovering empty canvas       -- a faint one-band preview of what a
      double-click right there would add, so the shape is known before
      you commit to it.

  Per-band colour, a gradient fill toward the 0dB line, and (opportunistically)
  a spectrum backdrop lifted from TS_TrackAnalyser's probe JSFX if one is
  live on this track, are all here too -- see the section comments below.
--]]

local C  = require("TS_CV_Config")
local U  = require("TS_CV_Util")
local W  = require("TS_CV_Widgets")
local RQ = require("TS_CV_ReaEQ")

local EQP = {}
local ImGui

function EQP.attach(imgui) ImGui = imgui end

-- ---------------------------------------------------------------------
-- per-panel interaction state, keyed by fx.guid so two ReaEQ panels open
-- at once (two instances, or one on each of two tracks in turn) don't
-- share a drag or a context menu.
-- ---------------------------------------------------------------------
local state = {}
local function panel_state(guid)
  local s = state[guid]
  if not s then s = {}; state[guid] = s end
  return s
end

-- ---------------------------------------------------------------------
-- batched polyline strokes -- lifted from the exact pattern TS_TrackAnalyser
-- already proved out for this: AddPolyline over a packed reaper.array is
-- one call instead of one per segment, with a per-segment AddLine fallback
-- if the installed ReaImGui doesn't have the packed call or the first
-- attempt errors. Fills stay a rect per span rather than one concave
-- polygon -- a concave fill self-intersects where two curves cross, which
-- is the documented reason TrackAnalyser's own spectrum fill is quads, not
-- one polygon.
-- ---------------------------------------------------------------------
local polyOK = (type(ImGui) == "table") -- refined properly once attached
local PTBUF = {}
local function ptbuf(npoints)
  local need = npoints * 2
  local a = PTBUF[need]
  if not a then a = reaper.new_array(need); PTBUF[need] = a end
  return a
end

local function polyline(dl, xs, ys, n, col, thick)
  if n < 2 then return end
  if polyOK and type(ImGui.DrawList_AddPolyline) == "function"
     and type(reaper.new_array) == "function" then
    local ok = pcall(function()
      local a = ptbuf(n)
      local j = 0
      for i = 1, n do a[j + 1] = xs[i]; a[j + 2] = ys[i]; j = j + 2 end
      ImGui.DrawList_AddPolyline(dl, a, col, 0, thick or 1.3)
    end)
    if ok then return end
    polyOK = false
  end
  for i = 1, n - 1 do
    ImGui.DrawList_AddLine(dl, xs[i], ys[i], xs[i + 1], ys[i + 1], col, thick or 1.3)
  end
end

-- A faded version of `polyline`, for a trace that should read as a hint
-- rather than a second real curve -- currently just the hover preview.
-- AddPolyline can't vary colour/alpha along its own length, so this goes
-- segment by segment instead, each one's alpha scaled by how far it sits
-- from the 0dB line (`y_zero`): full strength at a peak, fading away to
-- nothing wherever the curve is already flat against the baseline.
-- `half_h` is the pixel distance from that baseline to either edge of the
-- canvas, i.e. what "fully faded in" (frac 1) is measured against.
local function fading_polyline(dl, xs, ys, n, y_zero, half_h, col, max_alpha)
  if n < 2 or half_h <= 0 then return end
  for i = 1, n - 1 do
    local dist = (math.abs(ys[i] - y_zero) + math.abs(ys[i + 1] - y_zero)) * 0.5
    local a = math.floor(max_alpha * math.min(1, dist / half_h) + 0.5)
    if a > 2 then
      ImGui.DrawList_AddLine(dl, xs[i], ys[i], xs[i + 1], ys[i + 1],
        U.with_alpha(col, a), 1.0)
    end
  end
end

-- A vertical gradient fill from the curve down (or up) to the 0dB line,
-- fading OUT toward that line -- strongest right at the curve. One call
-- per column when AddRectFilledMultiColor exists; a flat, lower-alpha fill
-- if it doesn't, rather than erroring on an older ReaImGui.
local gradOK = true
local function fill_to_zero(dl, x0, x1, y_curve, y_zero, col, alpha)
  local top, bot = math.min(y_curve, y_zero), math.max(y_curve, y_zero)
  if bot - top < 0.5 then return end
  local at_curve = U.with_alpha(col, alpha)
  local at_zero  = U.with_alpha(col, 0)
  local c_top, c_bot
  if y_curve < y_zero then c_top, c_bot = at_curve, at_zero
  else                     c_top, c_bot = at_zero,  at_curve end
  if gradOK and type(ImGui.DrawList_AddRectFilledMultiColor) == "function" then
    local ok = pcall(ImGui.DrawList_AddRectFilledMultiColor, dl, x0, top, x1, bot,
      c_top, c_top, c_bot, c_bot)
    if ok then return end
    gradOK = false
  end
  ImGui.DrawList_AddRectFilled(dl, x0, top, x1, bot, U.with_alpha(col, alpha * 0.55))
end

-- ---------------------------------------------------------------------
-- spectrum backdrop -- TS_TrackAnalyser's probe JSFX, read-only, opt-in.
-- See TS_TA_Chain.lua's own gmem map, which this mirrors rather than
-- requires: ChannelView has no dependency on TrackAnalyser being
-- installed at all, so this reads gmem directly and simply draws nothing
-- if the namespace never gets attached to or the data goes stale.
-- ---------------------------------------------------------------------
local TA_NAMESPACE = "TS_TA_Mem"
local TA_POST_BASE  = 0x20000
local TA_H_SEQ, TA_H_ROLE  = 0, 11
local TA_H_BANDN, TA_H_BANDLO, TA_H_BANDHI = 16, 17, 18
local TA_OFF_BAND, TA_STRIDE = 16384, 4

local ta_attached          = false
local ta_last_seq, ta_seq_t = nil, 0

-- True only if something is actively publishing a POST spectrum right
-- now (its sequence counter has advanced inside the last second) --
-- never true just because the namespace exists, which it always will
-- once any script has ever attached to it.
local function spectrum_live()
  if not ta_attached then
    local ok = pcall(reaper.gmem_attach, TA_NAMESPACE)
    if not ok then return false end
    ta_attached = true
  end
  local ok, role = pcall(reaper.gmem_read, TA_POST_BASE + TA_H_ROLE)
  if not ok or role ~= 1 then return false end
  local seq = reaper.gmem_read(TA_POST_BASE + TA_H_SEQ)
  local now = reaper.time_precise()
  if seq ~= ta_last_seq then ta_last_seq, ta_seq_t = seq, now end
  return (now - ta_seq_t) < 1.0
end

-- Drawn first, under everything else. The probe's own band grid is log
-- 20Hz-20kHz across 256 points -- the same span the EQ canvas already
-- uses for its x-axis, so this maps straight across with no rescaling.
local SPEC_FLOOR_DB = -80
local function draw_spectrum(dl, gx0, gy0, gw, gh)
  if not spectrum_live() then return end
  local nb = reaper.gmem_read(TA_POST_BASE + TA_H_BANDN)
  if not nb or nb < 2 then return end
  local lo = reaper.gmem_read(TA_POST_BASE + TA_H_BANDLO) or C.EQ_FREQ_LO
  local hi = reaper.gmem_read(TA_POST_BASE + TA_H_BANDHI) or C.EQ_FREQ_HI

  local xs, ys = {}, {}
  local n = math.floor(nb)
  for i = 0, n - 1 do
    local db = reaper.gmem_read(TA_POST_BASE + TA_OFF_BAND + i * TA_STRIDE) or SPEC_FLOOR_DB
    local frac_f = (i + 0.5) / n
    local freq = lo * (hi / lo) ^ frac_f
    local level = math.max(0, math.min(1, (db - SPEC_FLOOR_DB) / -SPEC_FLOOR_DB))
    xs[#xs + 1] = gx0 + RQ.freq_to_frac(freq, C.EQ_FREQ_LO, C.EQ_FREQ_HI) * gw
    ys[#ys + 1] = gy0 + gh - level * gh
  end

  -- Filled to the bottom of the canvas, not to 0dB -- it's a level
  -- backdrop, not a gain curve, and sharing the 0dB baseline with the
  -- EQ curves would read as if it were one.
  for i = 1, #xs - 1 do
    fill_to_zero(dl, xs[i], xs[i + 1], ys[i], gy0 + gh, C.COL.eq_spectrum, 0x30)
  end
  polyline(dl, xs, ys, #xs, U.with_alpha(C.COL.eq_spectrum, 0x90), 1.0)
end

-- ---------------------------------------------------------------------
-- geometry
-- ---------------------------------------------------------------------
local function x_of(freq, gx0, gw)  return gx0 + RQ.freq_to_frac(freq, C.EQ_FREQ_LO, C.EQ_FREQ_HI) * gw end
local function y_of(db, gy0, gh)    return gy0 + RQ.gain_to_frac(db, C.EQ_GAIN_RANGE) * gh end
local function freq_of_x(px, gx0, gw) return RQ.frac_to_freq((px - gx0) / gw, C.EQ_FREQ_LO, C.EQ_FREQ_HI) end
local function gain_of_y(py, gy0, gh) return RQ.frac_to_gain((py - gy0) / gh, C.EQ_GAIN_RANGE) end

local FREQ_TICKS = { 50, 100, 200, 500, 1000, 2000, 5000, 10000, 20000 }
local FREQ_LABEL = { [100] = "100", [1000] = "1k", [10000] = "10k" }
local GAIN_STEP = 6

local function draw_grid(ctx, dl, gx0, gy0, gw, gh)
  for _, f in ipairs(FREQ_TICKS) do
    local x = x_of(f, gx0, gw)
    ImGui.DrawList_AddLine(dl, x, gy0, x, gy0 + gh, C.COL.eq_grid, 1.0)
    local lbl = FREQ_LABEL[f]
    if lbl then
      ImGui.DrawList_AddText(dl, x + 2, gy0 + gh - 12, C.COL.header_dim, lbl)
    end
  end
  local db = -math.floor(C.EQ_GAIN_RANGE / GAIN_STEP) * GAIN_STEP
  while db <= C.EQ_GAIN_RANGE do
    local y = y_of(db, gy0, gh)
    local col = (db == 0) and C.COL.eq_grid_0db or C.COL.eq_grid
    ImGui.DrawList_AddLine(dl, gx0, y, gx0 + gw, y, col, (db == 0) and 1.3 or 1.0)
    db = db + GAIN_STEP
  end
end

-- ---------------------------------------------------------------------
-- band colour -- stable per band across frames via its position in
-- RQ.read's list (which is itself stable as long as nothing is added or
-- removed), spaced by the golden angle so neighbours never land close.
-- ---------------------------------------------------------------------
local function band_colour(index)
  local hue = (C.EQ_HUE_START + (index - 1) * C.EQ_HUE_STEP) % 360
  return C.hsl(hue, 0.62, 0.58, 0xff)
end

-- ---------------------------------------------------------------------
-- curve sampling -- shared x grid (log freq), one y array per trace.
-- ---------------------------------------------------------------------
local function sample_xs(gx0, gw, n)
  local xs = {}
  for i = 1, n do
    xs[i] = gx0 + gw * (i - 1) / (n - 1)
  end
  return xs
end

local function sample_curve(fn, xs, gx0, gw, gy0, gh, n)
  local ys = {}
  for i = 1, n do
    local freq = freq_of_x(xs[i], gx0, gw)
    local db = math.max(-C.EQ_GAIN_RANGE * 1.5, math.min(C.EQ_GAIN_RANGE * 1.5, fn(freq)))
    ys[i] = y_of(db, gy0, gh)
  end
  return ys
end

-- ---------------------------------------------------------------------
-- the context menu -- right-click a node: change its type, or remove it.
--
-- `ps.menu_band` holds only (bandtype, bandidx) -- an identity, not a
-- snapshot -- and the actual band is looked up fresh in THIS frame's
-- `bands` every time the menu is drawn, the same way the plugin-panel
-- editor's own right-click menu re-fetches its layout fresh each frame
-- (see control_menu in TS_ChannelView.lua) rather than trusting whatever
-- it captured at the moment of the click, which the popup can still be
-- open several frames after.
-- ---------------------------------------------------------------------
local function find_band(bands, bandtype, bandidx)
  for _, b in ipairs(bands) do
    if b.bandtype == bandtype and b.bandidx == bandidx then return b end
  end
  return nil
end

-- The small per-gesture state RQ.set_gain/RQ.set_q's secant tracker needs
-- (see their own header) -- kept on `ps` so it survives across frames of
-- the SAME drag/wheel gesture, keyed by which band it's for so dragging
-- band A, releasing, then dragging band B doesn't hand B's first step a
-- slope estimated from A's curve. Switching back to a band already has a
-- state for reuses it rather than resetting -- if nothing else moved that
-- band's value in between, the old slope is still a fair local estimate.
local function drag_state(ps, field, key)
  local st = ps[field]
  if not st or st.key ~= key then
    st = { key = key }
    ps[field] = st
  end
  return st
end

-- ---------------------------------------------------------------------
-- deferred, cross-frame binary-search correction for a just-created
-- band's gain and Q.
--
-- RQ.add_band's own real-value writes for gain and Q both land wrong
-- (see its header): a positive gain overshoots, a negative gain always
-- pins to exactly 0dB (not "wrong", the same fixed value every time),
-- and Q comes out inverted. A whole half of the range collapsing to one
-- fixed value is a clamp signature, not a scale or sign error -- the
-- working theory is that SetEQParam's "real" value (isnorm=false) for
-- gain/Q on this native effect is silently treated AS IF it were
-- normalized (0..1), unlike freq, which genuinely takes real Hz. So
-- rather than guess further at what the real-value write actually means
-- (two wrong guesses already: a linear correction at gain alone, and
-- freq's own earlier one), this measures its way there: write a
-- candidate value IN THE [0,1] BRACKET (see the job-scheduling site in
-- EQP.draw -- that's where `lo`/`hi` are set, not here), read back what
-- it actually produced (RQ.read -- trusted; see its header, and
-- confirmed live down to the pixel for both freq and gain), and narrow
-- in via RQ.eq_search_narrow until the read-back value is within
-- tolerance of the target. job.target itself stays in real dB/Q units
-- throughout -- only the written-value bracket is [0,1]. This doesn't
-- assume which way increasing the written value moves the reading --
-- the first two steps probe the search bounds to establish that
-- (RQ.eq_search_direction), whichever way it goes.
--
-- One step per real UI frame, against `bands` -- the read EQP.draw
-- already does every frame regardless, so this adds nothing beyond the
-- correction writes themselves, and keeps every read well clear of the
-- same-script-tick lag that sank an earlier version of this fix (see
-- RQ.add_band's header): freq already reads back correctly starting the
-- frame after creation, not the same frame, and by the time this is
-- running at all, at least one frame has already passed.
--
-- `ps.eq_fix` is a small queue (a fresh band schedules up to two jobs --
-- gain and Q). Every job in it advances one step EVERY frame, not just
-- the front one -- they write different paramtypes (or different bands
-- entirely, if a second double-click lands while the first is still
-- converging) so there's no reason for one to wait on another, and doing
-- gain and Q at the same time instead of back to back was the other half
-- of "creation takes up to 2 seconds to settle" (the SETTLE_FRAMES cut
-- above was the first half). A job that's still waiting on a band that
-- hasn't shown up yet (see the `not b` branch just below) simply doesn't
-- block whichever other job in the queue already can run.
-- ---------------------------------------------------------------------

-- Advances one job by one step. Returns true once the job is finished
-- (converged, or given up on) so the caller can drop it from the queue.
local function advance_eq_fix_job(track, addr, bands, job)
  local b = find_band(bands, job.bandtype, job.bandidx)
  if not b then
    job.tries = (job.tries or 0) + 1
    return job.tries > 180   -- a few seconds, give up
  end

  -- WHICH WRITE FUNCTION, round three, and this one's conclusive rather
  -- than inferred. The SETTLE_FRAMES trace (see chat) ruled out timing
  -- entirely: gain sat at the EXACT same -inf for over 90 straight frames
  -- no matter what was written -- including written=1, held for dozens of
  -- frames -- and Q sat at the EXACT same 1.0 just as long. Not "slow to
  -- update" -- reaper.TrackFX_SetParamNormalized simply never changed
  -- anything this read path could see, at any point in that trace. What
  -- both traces actually show is add_band's own leftover value from
  -- BEFORE eq_fix_step ever touched either parameter, frozen, because
  -- nothing after it landed.
  --
  -- SetEQParam's isnorm=false write, by contrast, demonstrably DOES
  -- change real state (that's how the -inf-floor / 0dB-ceiling shape of
  -- its range got mapped out at all) -- it just only reaches the cut side
  -- of it. The one combination never actually tried until now is that
  -- same function with isnorm=TRUE: a real, intentional normalized write
  -- through the call already confirmed to update immediately, rather
  -- than either a coerced isnorm=false or a generic paramidx call this
  -- native effect ignores outright.
  local function write(norm)
    reaper.TrackFX_SetEQParam(track, addr, job.bandtype, job.bandidx, job.paramtype, norm, true)
  end

  local value = (job.paramtype == 1) and (b.gain or 0) or (b.q or 1.0)

  -- SETTLING TIME. One frame -- confirmed via live debug tracing (now
  -- pulled; see git history if it's ever needed again) that a
  -- TrackFX_SetEQParam(isnorm=true) write is reliably visible on the very
  -- next read, for both gain and Q. The previous margin of 2 frames per
  -- step, times ~13 steps per job (two probes plus up to 11 search
  -- iterations to close a 60dB/20Q range to tolerance), times two jobs
  -- run back to back for a fresh band, was the whole of the "creation
  -- takes up to 2 seconds to settle" complaint -- this alone cuts that
  -- roughly in half, and the per-frame ShowConsoleMsg that used to run
  -- alongside it (now pulled) was adding real overhead on top of that.
  local SETTLE_FRAMES = 1

  local function settled()
    job.settle = (job.settle or 0) + 1
    return job.settle >= SETTLE_FRAMES
  end

  if job.stage == "start" then
    write(job.lo)
    job.stage, job.settle = "probed_lo", 0
  elseif job.stage == "probed_lo" then
    if not settled() then return false end
    job.lo_read = value
    write(job.hi)
    job.stage, job.settle = "probed_hi", 0
  elseif job.stage == "probed_hi" then
    if not settled() then return false end
    job.hi_read = value
    job.direction = RQ.eq_search_direction(job.lo, job.lo_read, job.hi, job.hi_read)
    local mid = (job.lo + job.hi) / 2
    write(mid)
    job.last_written, job.stage, job.iter, job.settle = mid, "search", 0, 0
  elseif job.stage == "search" then
    if not settled() then return false end
    if math.abs(value - job.target) <= job.tol then return true end
    job.iter = job.iter + 1
    if job.iter > 24 then return true end   -- give up, best effort stands
    job.lo, job.hi = RQ.eq_search_narrow(job.lo, job.hi, job.direction, job.last_written, value, job.target)
    local mid = (job.lo + job.hi) / 2
    write(mid)
    job.last_written, job.settle = mid, 0
  end
  return false
end

-- Runs every queued job forward by one step, dropping any that finished.
-- Iterating with an explicit index (rather than ipairs) is what makes it
-- safe to remove a finished job mid-pass without skipping the one that
-- shifts into its slot.
local function eq_fix_step(track, addr, ps, bands)
  if not ps.eq_fix then return end
  local i = 1
  while i <= #ps.eq_fix do
    if advance_eq_fix_job(track, addr, bands, ps.eq_fix[i]) then
      table.remove(ps.eq_fix, i)
    else
      i = i + 1
    end
  end
end

local function draw_context_menu(ctx, track, addr, ps, bands)
  if not ImGui.BeginPopup(ctx, "eqctx") then return end
  local tgt = ps.menu_band
  local band = tgt and find_band(bands, tgt.bandtype, tgt.bandidx)
  if not band then ImGui.EndPopup(ctx); return end

  ImGui.TextDisabled(ctx, RQ.TYPE_NAME[band.bandtype] or "Band")
  ImGui.Separator(ctx)
  if ImGui.BeginMenu(ctx, "Change type") then
    for _, bt in ipairs(RQ.MENU_TYPES) do
      local sel = (bt == band.bandtype)
      if ImGui.MenuItem(ctx, RQ.TYPE_NAME[bt], nil, sel) and not sel then
        RQ.replace_band(track, addr, band, bt)
        ps.menu_band = nil
      end
    end
    ImGui.EndMenu(ctx)
  end
  ImGui.Separator(ctx)
  if ImGui.MenuItem(ctx, "Remove") then
    -- No true delete in the API -- see TS_CV_ReaEQ.lua. This disables the
    -- band, which is the closest thing scripting has to removing it.
    RQ.replace_band(track, addr, band, nil)
    ps.menu_band = nil
  end
  ImGui.EndPopup(ctx)
end

-- ---------------------------------------------------------------------
-- public
-- ---------------------------------------------------------------------

-- Draws the canvas filling (x, y, w, h) -- the same rect draw_controls
-- would otherwise occupy, below the header P.draw already drew. `req` is
-- P.draw's own request table; nothing here adds a new field to it.
function EQP.draw(ctx, dl, x, y, w, h, track, fx, req)
  local addr = fx.addr
  local ps = panel_state(fx.guid)
  local pad = C.PANEL_PAD
  local gx0, gy0 = x + pad, y + pad
  local gw, gh = w - pad * 2, h - pad * 2
  if gw < 20 or gh < 20 then return end

  local sr = reaper.GetSetProjectInfo(0, "PROJECT_SRATE", 0, false)
  if not sr or sr < 1000 then sr = 48000 end

  local bands, master = RQ.read(track, addr)
  eq_fix_step(track, addr, ps, bands)

  ImGui.DrawList_PushClipRect(dl, gx0, gy0, gx0 + gw, gy0 + gh, true)

  draw_spectrum(dl, gx0, gy0, gw, gh)
  draw_grid(ctx, dl, gx0, gy0, gw, gh)

  local n = C.EQ_CURVE_SEGS
  local xs = sample_xs(gx0, gw, n)
  local y0db = y_of(0, gy0, gh)

  -- Per-band gradient fill + its own trace, stacked before the combined
  -- curve so the combined line reads as sitting on top of them.
  for bi, b in ipairs(bands) do
    if b.enabled then
      local col = band_colour(bi)
      local ys = sample_curve(function(f) return RQ.band_db(b, f, sr) end,
        xs, gx0, gw, gy0, gh, n)
      local stride = math.max(1, C.EQ_FILL_STRIDE)
      for i = 1, n - stride, stride do
        fill_to_zero(dl, xs[i], xs[math.min(n, i + stride)], ys[i], y0db, col, 0x38)
      end
      polyline(dl, xs, ys, n, U.with_alpha(col, 0xb0), 1.1)
    end
  end

  -- The combined response -- every band and the master gain together --
  -- is the one thing on the canvas that reads as "what's actually
  -- happening", so it gets the accent colour and the thickest stroke.
  local total_ys = sample_curve(function(f) return RQ.total_db(bands, master, f, sr) end,
    xs, gx0, gw, gy0, gh, n)
  polyline(dl, xs, total_ys, n, C.COL.eq_curve, 2.0)

  -- The whole canvas is a big invisible button FIRST, so double-click-to-
  -- add and the hover preview see every pixel that isn't already claimed
  -- by a node's own smaller button drawn afterward (later items win
  -- hover in ReaImGui's immediate-mode hit-testing, the same as anywhere
  -- else in this codebase that layers a button under more specific ones).
  --
  -- That "later wins" behaviour isn't the default, though -- it only
  -- applies once the EARLIER, larger item has explicitly said it's fine
  -- for something else to claim the same pixels. Without this, the
  -- background button owns every pixel of the canvas for itself and the
  -- node buttons drawn afterward never see a click or a drag at all,
  -- which is exactly the bug this fixes. W.knob and friends all do the
  -- same thing for exactly this reason -- see W.allow_overlap.
  W.allow_overlap(ctx)
  ImGui.SetCursorScreenPos(ctx, gx0, gy0)
  ImGui.InvisibleButton(ctx, "eqbg##" .. fx.guid, gw, gh,
    ImGui.ButtonFlags_MouseButtonLeft | ImGui.ButtonFlags_MouseButtonRight)
  local bg_hovered = ImGui.IsItemHovered(ctx)

  if bg_hovered then
    local mx, my = ImGui.GetMousePos(ctx)
    local freq = freq_of_x(mx, gx0, gw)
    local gain = gain_of_y(my, gy0, gh)
    local bandtype = RQ.infer_type(freq)
    local is_pass = (bandtype == RQ.BAND_TYPE.HIPASS or bandtype == RQ.BAND_TYPE.LOPASS)
    local preview_gain = is_pass and 0 or gain

    if ImGui.IsMouseDoubleClicked(ctx, ImGui.MouseButton_Left) then
      local ok, abt, abi = RQ.add_band(track, addr, bandtype, freq, preview_gain,
        RQ.DEFAULT_Q[bandtype])
      if not ok then
        ps.add_failed_t = reaper.time_precise()
      else
        -- Both the band's own gain and Q writes are known wrong -- see
        -- eq_fix_step. The search brackets below are [0,1], not the real
        -- dB/Q range: on this native effect, TrackFX_SetEQParam's
        -- "real value" (isnorm=false) for gain/Q appears to be silently
        -- treated AS IF it were normalized (0..1) -- unlike freq, which
        -- genuinely takes real Hz. That explains every symptom seen:
        -- positive gain worked by coincidence (real dB range overlaps
        -- [0,1] on the boost side), negative gain always pinned to the
        -- exact same value (the floor of a clamped range, not "wrong
        -- scale"), and Q reading "reversed" (a search almost entirely
        -- outside the one sliver of input space that's actually live).
        -- So: search [0,1] as the WRITTEN-value bracket; job.target
        -- stays in real dB/Q units throughout, compared against the
        -- trusted real-unit read-back -- eq_fix_step itself needs no
        -- change, only where each job starts its search.
        -- Gain is skipped when it's already 0: there's nothing a
        -- clamp bug could do to a value that's already 0. Q always
        -- gets queued -- every band gets a real target Q
        -- (RQ.DEFAULT_Q), never "leave it wherever".
        ps.eq_fix = ps.eq_fix or {}
        if preview_gain ~= 0 then
          ps.eq_fix[#ps.eq_fix + 1] = { bandtype = abt, bandidx = abi, paramtype = 1,
            target = preview_gain, tol = 0.05, lo = 0, hi = 1,
            stage = "start" }
        end
        local target_q = RQ.DEFAULT_Q[bandtype]
        if target_q then
          ps.eq_fix[#ps.eq_fix + 1] = { bandtype = abt, bandidx = abi, paramtype = 2,
            target = target_q, tol = math.max(0.02, target_q * 0.02),
            lo = 0, hi = 1, stage = "start" }
        end
      end
    else
      -- The faint live preview -- one hypothetical band, not summed with
      -- anything real, so it never has to be undone if you move on
      -- without clicking. Faded toward the 0dB line so it reads as a
      -- hint rather than a second curve competing with the real ones.
      local ghost = { bandtype = bandtype, freq = freq, gain = preview_gain,
                      q = RQ.DEFAULT_Q[bandtype], enabled = true }
      local pys = sample_curve(function(f) return RQ.band_db(ghost, f, sr) end,
        xs, gx0, gw, gy0, gh, n)
      fading_polyline(dl, xs, pys, n, y0db, gh * 0.5, C.COL.eq_preview, 0xd0)
      local nx, ny = x_of(freq, gx0, gw), y_of(preview_gain, gy0, gh)
      ImGui.DrawList_AddCircle(dl, nx, ny, C.EQ_NODE_R, C.COL.eq_preview, 0, 1.0)
    end
  end

  if ps.add_failed_t and reaper.time_precise() - ps.add_failed_t < 2.0 then
    local msg = "couldn't add band \u{2014} see the panel menu"
    local tw = ImGui.CalcTextSize(ctx, msg)
    ImGui.DrawList_AddText(dl, gx0 + gw * 0.5 - tw * 0.5, gy0 + 4, C.COL.warn, msg)
  end

  -- Nodes, drawn (and hit-tested) after the background so they take
  -- priority over it for their own small area.
  for bi, b in ipairs(bands) do
    if b.enabled then
      local col = band_colour(bi)

      -- A pass filter (hipass/lopass), notch or bandpass has no gain of
      -- its own in the curve this canvas draws -- ReaEQ's API still
      -- reports a gain param for every band type uniformly, but writing
      -- it for one of these would change something the drawn curve can't
      -- show moving, which is worse than a drag axis that simply does
      -- nothing. Only freq moves for those; bell and shelf get both.
      local has_gain = b.bandtype == RQ.BAND_TYPE.BAND
        or b.bandtype == RQ.BAND_TYPE.LOSHELF or b.bandtype == RQ.BAND_TYPE.HISHELF

      -- b.gain can be a real infinity (ReaEQ's own "-inf dB" at the
      -- floor -- see RQ.read's header) -- clamp before it reaches pixel
      -- math, same clamp the curve trace already applies per sample in
      -- sample_curve, so a fully-cut band's node pins at the canvas edge
      -- instead of handing ImGui a non-finite coordinate. For a band type
      -- with no gain axis of its own, ReaEQ's reported "gain" for it isn't
      -- meaningful curve-wise, and trusting it here was pinning the node
      -- off at whatever that value happened to clamp to -- often flush
      -- against the very top or bottom edge, where it read as no handle
      -- at all rather than just a node sitting at an odd height. Those
      -- band types pin to the 0dB centre line instead, matching that they
      -- don't move on the gain axis in the drag handler below either.
      local node_db = has_gain
        and math.max(-C.EQ_GAIN_RANGE * 1.5, math.min(C.EQ_GAIN_RANGE * 1.5, b.gain or 0))
        or 0
      local nx, ny = x_of(b.freq, gx0, gw), y_of(node_db, gy0, gh)
      local id = ("eqn##%s:%d:%d"):format(fx.guid, b.bandtype, b.bandidx)
      local r = C.EQ_NODE_R + 3   -- a bit more than the drawn radius to grab
      -- Two nodes can land close enough to overlap each other, not just
      -- the background -- same reasoning as the allow_overlap call above.
      W.allow_overlap(ctx)
      ImGui.SetCursorScreenPos(ctx, nx - r, ny - r)
      ImGui.InvisibleButton(ctx, id, r * 2, r * 2,
        ImGui.ButtonFlags_MouseButtonLeft | ImGui.ButtonFlags_MouseButtonRight)
      local hovered = ImGui.IsItemHovered(ctx)
      local active  = ImGui.IsItemActive(ctx)

      if active and ImGui.IsMouseDown(ctx, ImGui.MouseButton_Left) then
        local dx, dy = ImGui.GetMouseDelta(ctx)
        if dx ~= 0 then
          local frac = RQ.freq_to_frac(b.freq, C.EQ_FREQ_LO, C.EQ_FREQ_HI) + dx / gw
          RQ.set_freq(track, addr, b, RQ.frac_to_freq(frac, C.EQ_FREQ_LO, C.EQ_FREQ_HI))
        end
        if dy ~= 0 and has_gain then
          -- b.gain can be a real infinity at the floor/ceiling -- clamp
          -- before it drives this canvas's own linear frac math, same as
          -- the node-drawing and curve-sampling clamps elsewhere.
          local cur_db = math.max(-C.EQ_GAIN_RANGE * 1.5, math.min(C.EQ_GAIN_RANGE * 1.5, b.gain or 0))
          local frac = RQ.gain_to_frac(cur_db, C.EQ_GAIN_RANGE) + dy / gh
          local st = drag_state(ps, "gain_drag", id)
          RQ.set_gain(track, addr, b, RQ.frac_to_gain(frac, C.EQ_GAIN_RANGE), st)
        end
        ImGui.SetMouseCursor(ctx, ImGui.MouseCursor_ResizeAll)
      elseif hovered then
        local wheel = ImGui.GetMouseWheel(ctx)
        if wheel ~= 0 and b.q then
          local mods = ImGui.GetKeyMods(ctx)
          local mult = (mods & ImGui.Mod_Shift) ~= 0 and C.FINE_MULT or 1.0
          local st = drag_state(ps, "q_drag", id)
          RQ.set_q(track, addr, b, b.q * (1 + wheel * 0.12 * mult), st)
          W.take_wheel()
        end
      end

      if ImGui.IsItemClicked(ctx, ImGui.MouseButton_Right) then
        ps.menu_band = { bandtype = b.bandtype, bandidx = b.bandidx }
        ImGui.OpenPopup(ctx, "eqctx")
      end

      if hovered or active then
        local tip = ("%s\n%s   %s dB   Q %s"):format(
          RQ.TYPE_NAME[b.bandtype] or "Band",
          U.fmt_value(track, addr, b.freq_pidx),
          b.gain_pidx and U.fmt_value(track, addr, b.gain_pidx) or "\u{2014}",
          b.q_pidx and U.fmt_value(track, addr, b.q_pidx) or "\u{2014}")
        W.tip(ctx, id, tip, hovered, active)
      end

      local ring = (hovered or active) and C.COL.header_text or col
      ImGui.DrawList_AddCircleFilled(dl, nx, ny, C.EQ_NODE_R, col)
      ImGui.DrawList_AddCircle(dl, nx, ny, C.EQ_NODE_R, ring, 0, 1.5)
    end
  end

  draw_context_menu(ctx, track, addr, ps, bands)

  ImGui.DrawList_PopClipRect(dl)
end

return EQP
