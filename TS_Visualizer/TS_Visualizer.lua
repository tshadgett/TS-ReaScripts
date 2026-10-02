--========================================================
-- @title TS_Visualizer
-- @description TS_Visualizer
-- @author Tim Shadgett (with Claude) -- fork of JKK_Visualizer by Junki Kim
-- @version 2.1.0
-- @changelog
--  First release in TS-ReaScripts. A fork of JKK_Visualizer by Junki Kim:
--  LUFS, goniometer, Symbiote, scope, spectrum and spectrogram as before,
--  plus a Dynamics module (short-term LUFS against PSR) with loudness and
--  genre targets, a per-track spectrum overlay from TS_TrackProbe, and a
--  Hue/Tint colour system shared with ChannelView and Track Analyser.
-- @license MIT
-- @provides
--     [main] TS_Visualizer_Editor.lua
--     [nomain] TS_Theme.lua
--     [effect] TS_Visualizer.jsfx
--========================================================
options = reaper.gmem_attach('TS_Visualizer_Mem') 

local win_w, win_h = 800, 150
local saved_dock = tonumber(reaper.GetExtState("TS_Visualizer", "DockState")) or 0
gfx.init("TS_Visualizer", win_w, win_h, saved_dock)

local function load_layout_settings()
    local saved_orientation = tonumber(reaper.GetExtState("TS_Visualizer", "Orientation"))
    if saved_orientation then reaper.gmem_write(1450, saved_orientation) end
    local saved_pair = tonumber(reaper.GetExtState("TS_Visualizer", "PairGonioSymbiote"))
    if saved_pair then reaper.gmem_write(1460, saved_pair) end
    local saved_pair_lufs = tonumber(reaper.GetExtState("TS_Visualizer", "PairLufsDynamics"))
    if saved_pair_lufs then reaper.gmem_write(1465, saved_pair_lufs) end
    for i = 1, 7 do
        local saved_size = tonumber(reaper.GetExtState("TS_Visualizer", "ModSize_"..i))
        if saved_size then reaper.gmem_write(1500 + i, saved_size) end
    end

    -- Colour palette: Hue/Tint and each swatch's own Follow flag (same
    -- gmem addresses as MEM_BASE_HUE/MEM_TINT/FOLLOW_HUE_BASE further
    -- down -- raw here, like everything else in this function, since
    -- those locals aren't in scope yet this early in the file). Without
    -- this, a session where this script is the only thing that ever runs
    -- (e.g. launched via Run at REAPER Startup, Settings never opened)
    -- left every one of these at gmem's cold-start 0 -- and
    -- build_palette() only ever touches a swatch whose Follow flag is
    -- non-zero, so every themed colour just stayed at whatever raw value
    -- had last been saved, including grid's old, pre-fix alpha. The
    -- render loop's own init_default_colors() looks like it should have
    -- covered this, but it's gated behind "nothing saved for bg alpha
    -- yet", which stops being true forever the first time any colour is
    -- ever saved -- so in practice it never ran again once a palette
    -- existed. Loading these here, unconditionally, the same place this
    -- file already proves out doing exactly this for layout, closes that
    -- gap: opening Settings "fixing" it was only ever a side effect of
    -- the Editor's own LoadAllSettings() reaching these same keys.
    local saved_hue = tonumber(reaper.GetExtState("TS_Visualizer", "BaseHue"))
    reaper.gmem_write(1470, saved_hue or 219)
    local saved_tint = tonumber(reaper.GetExtState("TS_Visualizer", "Tint"))
    reaper.gmem_write(1480, saved_tint or 1.0)
    local saved_sync = tonumber(reaper.GetExtState("TS_Visualizer", "SyncChannelView"))
    if saved_sync then reaper.gmem_write(1490, saved_sync) end
    local follow_role_names = { "bg", "grid", "text", "zero", "mid", "peak", "frez" }
    for i = 1, 7 do
        local saved_follow = tonumber(reaper.GetExtState("TS_Visualizer", "FollowHue_"..follow_role_names[i]))
        reaper.gmem_write(1510 + i, saved_follow or 1)
    end

    -- Hand-picked (non-hue-following) role colours. build_palette() only
    -- ever writes gmem for a role whose own Follow flag is on -- by
    -- design, so it never clobbers a colour someone picked by hand. But
    -- that means nothing else loads a hand-picked role's raw RGBA out of
    -- ExtState before the first frame either: the render loop's own
    -- LoadSettingsFromExtState() (below) only runs while gmem's MEM_BG
    -- alpha is still 0, and by the time the first frame can even check
    -- that, Initialize_System() has already set it non-zero building the
    -- hue-driven roles (bg included, almost always on) -- so that gate
    -- is shut before it's ever read. Same bug class as Base Hue/Tint
    -- above, one layer further in: any role flagged "don't follow the
    -- hue" read gmem's cold-start 0,0,0,0 (fully transparent) until
    -- Settings was opened and its own unconditional MEM_* load fixed it
    -- as a side effect. Loading the same range here, unconditionally,
    -- closes that gap too.
    for i = 1000, 1100 do
        local saved_val = tonumber(reaper.GetExtState("TS_Visualizer", "MEM_"..i))
        if saved_val then reaper.gmem_write(i, saved_val) end
    end
end
load_layout_settings()

-- User setting ranges
local g_gain_min, g_gain_max            = 0.0,  2.0
local s_zoom_min, s_zoom_max            = 0.0,  2.5
local spec_ceil_min, spec_ceil_max      = 100,  20
local spec_floor_min, spec_floor_max    = -45, -45
local spec_offset = 0
local g_signal_attack = 0.00001
local g_signal_release = 0.00001

-- Data buffer info
local buf_len = 100000
local fft_size = 4096
local fft_bins = 2048
local ui_order = {1, 2, 3, 4, 6, 5, 7}

----------------------------------------------------------
-- UI Values Setting
----------------------------------------------------------
    -- Global settings
    local base_title_size = 20
    local g_font_scale = 1
    -- Track Analyser palette: a near-black with a blue cast rather than a
    -- neutral grey, so the blue of the signal and the gold of the peaks both
    -- sit on it without fighting it.
    local bg_r, bg_g, bg_b, bg_a = 020/255, 023/255, 026/255, 1.0
    local line_r, line_g, line_b, line_a = 138/255, 147/255, 156/255, 1.0
    local text_r, text_g, text_b, text_a = 138/255, 147/255, 156/255, 1.0
    local midpoint = 0.5
    local steepness = 1.2

    -- Gonio Color
    local dot1_r, dot1_g, dot1_b, dot1_a = 046/255, 110/255, 150/255, 0.10
    local dot2_r, dot2_g, dot2_b, dot2_a = 078/255, 154/255, 200/255, 0.80
    local dot3_r, dot3_g, dot3_b, dot3_a = 232/255, 194/255, 090/255, 1.00
    local gr_peak, gg_peak, gb_peak = 255/255, 000/255, 000/255      
        local gonio_peak_hold_time = 2.0  
        local gonio_max_peak_dots = 150   
        local gonio_peaks = {} 
        local phase_smooth = 0

    -- Symbiote Color
    local sym1_r, sym1_g, sym1_b, sym1_a = 046/255, 110/255, 150/255, 0.10
    local sym2_r, sym2_g, sym2_b, sym2_a = 078/255, 154/255, 200/255, 0.80
    local sym3_r, sym3_g, sym3_b, sym3_a = 232/255, 194/255, 090/255, 1.00
        local sym_points = 150       
        local sym_noise_speed = 5.0  
        local sym_size_ratio = 0.3   
        local sym_min_scale = 0.1    
        local sym_max_scale = 1.0    
        local sym_layers = 25        
        local sym_time_accum = 0     
        local s_bass_smooth = 0      
        local s_width_smooth = 0     
        local sym_spikiness = 0      

    -- Scope Color
    local scp1_r, scp1_g, scp1_b, scp1_a = 046/255, 110/255, 150/255, 0.10
    local scp2_r, scp2_g, scp2_b, scp2_a = 078/255, 154/255, 200/255, 0.80
    local scp3_r, scp3_g, scp3_b, scp3_a = 232/255, 194/255, 090/255, 1.00
    local scope_speed = 0.1 

    -- Spectrum & Waterfall Color
    local sptr1_r, sptr1_g, sptr1_b, sptr1_a = 046/255, 110/255, 150/255, 0.10
    local sptr2_r, sptr2_g, sptr2_b, sptr2_a = 078/255, 154/255, 200/255, 0.80
    local sptr3_r, sptr3_g, sptr3_b, sptr3_a = 232/255, 194/255, 090/255, 1.00
    local peak_r, peak_g, peak_b, peak_a     = 106/255, 115/255, 124/255, 1.00
        local peak_hold_time = 0.5  
        local spec_smooth_vals = {}
        local spec_peaks = {} 
        local spec_peak_times = {}
        for i = 1, 4096 do 
            spec_smooth_vals[i] = -144
            spec_peaks[i] = -144 
            spec_peak_times[i] = 0
        end
        
        -- Waterfall-only variables
        local waterfall_canvas_id = 1
        local w_cursor_idx = 0
        local w_last_w, w_last_h = 0, 0
        local w_last_col_data = {}
        local w_scan_speed = 12

----------------------------------------------------------
-- Functions: Features (LUFS, Gonio, Symbiote, Scope, Spectrum, Waterfall)
----------------------------------------------------------
    -- The settings gear is drawn last, fixed at the window's own
    -- top-left corner in every orientation (see its own note near where
    -- it's drawn) -- so whichever module lands at (0, 0) this frame
    -- (the first one in module order, in both horizontal and vertical
    -- layout) is the one whose own corner title would otherwise sit
    -- right under it. LUFS has no corner title to begin with; every
    -- other module's title starts from this instead of a bare "x + 5",
    -- so only that one module's title moves, and only on the frames
    -- it's actually first.
    local GEAR_TITLE_CLEARANCE = 26
    local function title_x(x, y)
        if x == 0 and y == 0 then return x + 5 + GEAR_TITLE_CLEARANCE end
        return x + 5
    end

    function draw_lufs(x, y, w, h, stack_horizontal)
        local mom_val = reaper.gmem_read(20)
        local short_val = reaper.gmem_read(21)
        local mom_peak = reaper.gmem_read(22)

        local base_label_size = 15 
        local base_val_size = 35   
        local base_peak_size = 20  

        gfx.set(bg_r, bg_g, bg_b, bg_a)
        gfx.rect(x, y, w, h, 1)
        
        local unit_w, unit_h
        if stack_horizontal then
            unit_w, unit_h = w / 2, h
        else
            unit_w, unit_h = w, h / 2
        end
        gfx.setfont(1, "Arial", base_label_size * g_font_scale)

        -- MOMENTARY
        local m_px, m_py = x, y
        local cx1 = m_px + unit_w * 0.5
        gfx.set(text_r, text_g, text_b, text_a)
        local m_lab = "MOMENTARY"
        local lw, lh = gfx.measurestr(m_lab)
        gfx.x, gfx.y = cx1 - lw * 0.5, m_py + unit_h * 0.15
        gfx.drawstr(m_lab)

        local m_str = (mom_val <= -100) and "- Inf" or string.format("%.1f", mom_val)
        gfx.setfont(2, "Arial", base_val_size * g_font_scale, "b")
        gfx.set(scp2_r, scp2_g, scp2_b, scp2_a)
        local sw, sh = gfx.measurestr(m_str)
        gfx.x, gfx.y = cx1 - sw * 0.5, m_py + unit_h * 0.35
        gfx.drawstr(m_str)

        gfx.setfont(1, "Arial", base_peak_size * g_font_scale, "b")
        gfx.set(scp3_r, scp3_g, scp3_b, scp3_a )
        local p_str = (mom_peak <= -100) and "- Inf" or string.format("%.1f", mom_peak)
        local pw, ph = gfx.measurestr(p_str)
        gfx.x, gfx.y = cx1 - pw * 0.5, m_py + unit_h * 0.80
        gfx.drawstr(p_str)

        -- Divider between the two meters
        local s_px, s_py
        gfx.set(line_r, line_g, line_b, line_a)
        if stack_horizontal then
            s_px, s_py = x + unit_w, y
            gfx.line(s_px, y + 8, s_px, y + h - 8)
        else
            s_px, s_py = x, y + unit_h
            gfx.line(x + 10, s_py + 8, x + w - 10, s_py + 8) 
        end

        -- SHORT-TERM
        local cx2 = s_px + unit_w * 0.5
        gfx.setfont(1, "Arial", base_label_size * g_font_scale) 
        gfx.set(text_r, text_g, text_b, text_a)
        local s_lab = "SHORT-TERM"
        local slw, slh = gfx.measurestr(s_lab)
        gfx.x, gfx.y = cx2 - slw * 0.5, s_py + unit_h * 0.25
        gfx.drawstr(s_lab)

        local s_str = (short_val <= -100) and "- Inf" or string.format("%.1f", short_val)
        gfx.setfont(2, "Arial", base_val_size * g_font_scale, "b")
        gfx.set(scp2_r, scp2_g, scp2_b, scp2_a)
        local ssw, ssh = gfx.measurestr(s_str)
        gfx.x, gfx.y = cx2 - ssw * 0.5, s_py + unit_h * 0.45
        gfx.drawstr(s_str)
    
        gfx.setfont(1, "Arial", base_title_size * g_font_scale)

        if gfx.mouse_cap == 1 then
            if gfx.mouse_x >= x and gfx.mouse_x <= x + w and 
               gfx.mouse_y >= y and gfx.mouse_y <= y + h then
                reaper.gmem_write(30, 1) 
                gfx.set(1, 1, 1, 0.15)
                gfx.rect(x, y, w, h, 1)
            end
        end
    end

    function draw_gonio(x, y, w, h, gain)
        local srate = reaper.gmem_read(1)
        if srate <= 0 then srate = 44100 end
        
        local base_trail = 2000 * (srate / 44100) 
        local trail_len = math.floor(base_trail / (g_signal_release / 2))

        local is_hover = (gfx.mouse_x >= x and gfx.mouse_x <= x + w and
                          gfx.mouse_y >= y and gfx.mouse_y <= y + h)
        if is_hover then
            trail_len = trail_len * 3
        end

        local cx, cy = x + w * 0.5, y + h * 0.45
        local dim_limit = math.min(w, h)
        local guide_size = dim_limit * 0.37
        local dot_size = dim_limit * 0.25 * gain 
        local now = reaper.time_precise()            

        local true_zero_limit = 1.0 
        local visual_limit = guide_size / (2 * dot_size)

        -- line_a is opaque now (matching TrackAnalyser's own grid role --
        -- see the ROLE_PALETTE note above), so this "boosted" 1.5x guide
        -- crosshair would otherwise ask gfx.set for an alpha above 1;
        -- clamped rather than assuming gfx quietly does that itself.
        gfx.set(line_r, line_g, line_b, math.min(1.0, line_a * 3 / 2))
        gfx.line(cx - guide_size, cy - guide_size, cx + guide_size, cy + guide_size)
        gfx.line(cx + guide_size, cy - guide_size, cx - guide_size, cy + guide_size)            

        local write_idx = reaper.gmem_read(0)            

        for i = 0, trail_len, 2 do
            local idx = (write_idx - i - 1) % buf_len
            local l, r = reaper.gmem_read(10000 + idx), reaper.gmem_read(110000 + idx)

            local exp = 0.8
            local l_scaled = (l >= 0 and 1 or -1) * (math.abs(l) ^ exp)
            local r_scaled = (r >= 0 and 1 or -1) * (math.abs(r) ^ exp)

            local peak_intensity = math.max(math.abs(l), math.abs(r))
            
            if peak_intensity >= true_zero_limit and #gonio_peaks < gonio_max_peak_dots then
                local l_p_scaled = (l >= 0 and 1 or -1) * (math.abs(l) ^ exp)
                local r_p_scaled = (r >= 0 and 1 or -1) * (math.abs(r) ^ exp)

                local cl = math.max(-visual_limit, math.min(visual_limit, l_p_scaled))
                local cr = math.max(-visual_limit, math.min(visual_limit, r_p_scaled))
                local px, py = cx + (cr - cl) * dot_size, cy - (cr + cl) * dot_size
                table.insert(gonio_peaks, {px = px, py = py, time = now})
            end

            local t = math.min(1.0, peak_intensity / visual_limit)
            local gonio_r, gonio_g, gonio_b, gonio_a

            if t < midpoint then
                local local_t = t / midpoint 
                local curve = local_t ^ steepness                    
                gonio_r = dot1_r + (dot2_r - dot1_r) * curve
                gonio_g = dot1_g + (dot2_g - dot1_g) * curve
                gonio_b = dot1_b + (dot2_b - dot1_b) * curve
                gonio_a = dot1_a + (dot2_a - dot1_a) * curve
            else
                local local_t = (t - midpoint) / (1 - midpoint)
                local curve = local_t ^ steepness                    
                gonio_r = dot2_r + (dot3_r - dot2_r) * curve
                gonio_g = dot2_g + (dot3_g - dot2_g) * curve
                gonio_b = dot2_b + (dot3_b - dot2_b) * curve
                gonio_a = dot2_a + (dot3_a - dot2_a) * curve
            end

            local cl = math.max(-visual_limit, math.min(visual_limit, l_scaled))
            local cr = math.max(-visual_limit, math.min(visual_limit, r_scaled))
            local px, py = cx + (cr - cl) * dot_size, cy - (cr + cl) * dot_size

            gfx.set(gonio_r, gonio_g, gonio_b, (1 - (i / trail_len)))
            gfx.x, gfx.y = px, py
            gfx.setpixel(gonio_r, gonio_g, gonio_b)
        end            

        for i = #gonio_peaks, 1, -1 do
            local p = gonio_peaks[i]
            if (now - p.time) > gonio_peak_hold_time then
                table.remove(gonio_peaks, i)
            else
                gfx.set(gr_peak, gg_peak, gb_peak, 1.0)
                gfx.rect(p.px - 1, p.py - 1, 2, 2) 
            end
        end

        local idx = (write_idx - 1) % buf_len
        local l = reaper.gmem_read(10000 + idx)
        local r = reaper.gmem_read(110000 + idx)

        local dot_product = l * r
        local mag_l = l * l
        local mag_r = r * r
        local denom = math.sqrt(mag_l * mag_r)            

        local current_phase = 0
        if denom > 0.000001 then current_phase = dot_product / denom end

        phase_smooth = phase_smooth + (current_phase - phase_smooth) * 0.1            

        local bar_h = 4
        local bar_w = w * 0.6
        local bar_x = x + (w - bar_w) * 0.5
        local bar_y = y + h - 15 

        gfx.set(line_r, line_g, line_b, line_a)
        gfx.rect(bar_x, bar_y, bar_w, bar_h, 0)
        gfx.line(bar_x + bar_w * 0.5, bar_y - 2, bar_x + bar_w * 0.5, bar_y + bar_h + 2)            

        local indicator_x = bar_x + (bar_w * 0.5) + (phase_smooth * (bar_w * 0.5))

        if phase_smooth >= 0 then
            gfx.set(dot2_r, dot2_g, dot2_b, 0.8) 
        else
            gfx.set(1, 0, 0, 0.8) 
        end            

        gfx.rect(indicator_x - 1, bar_y - 2, 3, bar_h + 4, 1)

        gfx.setfont(1, "Arial", (base_title_size - 4) * g_font_scale) 
        local label_padding = 5 

        local tw_minus, th_minus = gfx.measurestr("-1")
        gfx.x = bar_x - tw_minus - label_padding
        gfx.y = bar_y + (bar_h * 1) - (th_minus * 0.5)
        gfx.drawstr("-1")

        local tw_plus, th_plus = gfx.measurestr("+1")
        gfx.x = bar_x + bar_w + label_padding
        gfx.y = bar_y + (bar_h * 1) - (th_plus * 0.5)
        gfx.drawstr("+1")

        gfx.set(line_r, line_g, line_b, line_a)
        gfx.setfont(1, "Arial", base_title_size * g_font_scale)
        gfx.x, gfx.y = title_x(x, y), y + 5
        gfx.drawstr("Gonio")
    end

    function draw_symbiote(x, y, w, h, gain)
        local base_attack = 0.3
        local base_release = 0.3

        local sym_base_radius = math.min(w, h) * 0.45 * sym_size_ratio
        local fixed_cx, fixed_cy = x + w * 0.5, y + h * 0.5
        
        local time = reaper.time_precise()
        local drift_radius = 10.0 
        local drift_speed = 0.7   
        
        local drift_x = math.sin(time * drift_speed) * drift_radius 
                      + math.cos(time * drift_speed * 1.3) * (drift_radius * 0.5)
        local drift_y = math.cos(time * drift_speed * 0.8) * drift_radius 
                      + math.sin(time * drift_speed * 1.7) * (drift_radius * 0.5)

        local cx, cy = fixed_cx + drift_x, fixed_cy + drift_y
        
        local write_idx = reaper.gmem_read(0)
        local idx = (write_idx - 1) % buf_len
        local l = reaper.gmem_read(10000 + idx)
        local r = reaper.gmem_read(110000 + idx)
        
        local target_vol = (math.abs(l) + math.abs(r)) * 0.5 * gain
        local target_width = math.abs(l - r) * gain
        s_width_smooth = s_width_smooth + (target_width - s_width_smooth) * 0.1

        local bass_sum = 0
        for k = 2, 16 do 
            bass_sum = bass_sum + reaper.gmem_read(300000 + k)
        end
        local current_bass = (bass_sum / 16) * gain * 0.032
        local size_attack = base_attack * g_signal_attack
        local size_release = base_release * g_signal_release
        
        local smoothing = (current_bass > s_bass_smooth) and size_attack or size_release
        s_bass_smooth = s_bass_smooth + (current_bass - s_bass_smooth) * smoothing
        
        local spike_raw = 0
        if current_bass > 1.7 then spike_raw = (current_bass - 0.25) * 2 end
        spike_raw = math.min(0.5, spike_raw)

        local spike_attack = size_attack * 1.5 
        local spike_release = size_release * 1.0

        local spike_smoothing = (spike_raw > sym_spikiness) and spike_attack or spike_release
        sym_spikiness = sym_spikiness + (spike_raw - sym_spikiness) * math.min(1.0, spike_smoothing)

        local cur_time = reaper.time_precise()
        if not last_time then last_time = cur_time end
        sym_time_accum = sym_time_accum + (cur_time - last_time) * (0.3 + target_vol * 12.0)
        last_time = cur_time

        local max_allowed_r = (math.min(w, h) * 0.5) - 5
        local raw_r_dyn = sym_base_radius * (1 + s_bass_smooth * 0.5)
        local clamped_r = math.min(max_allowed_r * 0.8, raw_r_dyn)
        clamped_r = math.max(sym_base_radius * sym_min_scale, clamped_r)

        local shape_points = {}
        local stretch = 1.0 + (s_width_smooth * 2.0)

        for i = 0, sym_points do
            local angle = (i / sym_points) * 2 * math.pi
            local n1 = math.sin(angle * 3 + sym_time_accum * sym_noise_speed)
            local n2 = math.cos(angle * 5 - sym_time_accum * (sym_noise_speed * 0.2))
            local wobble = (n1 + n2) * 0.12
            local spike = math.sin(angle * 8 + sym_time_accum) * sym_spikiness * 0.3
            local r_final = raw_r_dyn * (1 + wobble + spike)
            
            local dx = math.cos(angle) * r_final * stretch
            local dy = math.sin(angle) * r_final * stretch
            
            local abs_dx = dx + drift_x
            local abs_dy = dy + drift_y
            local dist_from_fixed = math.sqrt(abs_dx*abs_dx + abs_dy*abs_dy)

            if dist_from_fixed > max_allowed_r then
                local scale = max_allowed_r / dist_from_fixed
                local constrained_abs_dx = abs_dx * scale
                local constrained_abs_dy = abs_dy * scale
                dx = constrained_abs_dx - drift_x
                dy = constrained_abs_dy - drift_y
            end
            shape_points[i] = { dx = dx, dy = dy }
        end
        
        local t_col = math.min(1.0, clamped_r / (max_allowed_r * 0.8))

        for j = sym_layers, 1, -1 do
            local layer_t = j / sym_layers
            local cur_r, cur_g, cur_b, cur_a
            if layer_t < midpoint then
                local local_t = (layer_t / midpoint) ^ steepness
                cur_r = sym1_r + (sym2_r - sym1_r) * local_t
                cur_g = sym1_g + (sym2_g - sym1_g) * local_t
                cur_b = sym1_b + (sym2_b - sym1_b) * local_t
                cur_a = sym1_a + (sym2_a - sym1_a) * local_t
            else
                local local_t = ((layer_t - midpoint) / (1 - midpoint)) ^ steepness
                cur_r = sym2_r + (sym3_r - sym2_r) * local_t
                cur_g = sym2_g + (sym3_g - sym2_g) * local_t
                cur_b = sym2_b + (sym3_b - sym2_b) * local_t
                cur_a = sym2_a + (sym3_a - sym2_a) * local_t
            end
            gfx.set(cur_r, cur_g, cur_b, cur_a)
            local first_x, first_y, prev_x, prev_y
            for i = 0, sym_points do
                local p = shape_points[i]
                local px, py = cx + p.dx * layer_t, cy + p.dy * layer_t
                if i==0 then first_x,first_y=px,py; prev_x,prev_y=px,py else gfx.triangle(cx,cy,prev_x,prev_y,px,py); prev_x,prev_y=px,py end
            end
            gfx.triangle(cx, cy, prev_x, prev_y, first_x, first_y)
        end
        
        gfx.set(sym3_r, sym3_g, sym3_b, 1.0)
        local pp = shape_points[0]
        for i = 1, sym_points do
            local cp = shape_points[i]
            gfx.line(cx+pp.dx, cy+pp.dy, cx+cp.dx, cy+cp.dy)
            gfx.line(cx+pp.dx, cy+pp.dy+1, cx+cp.dx, cy+cp.dy+1)
            pp = cp
        end
        gfx.line(cx+pp.dx, cy+pp.dy, cx+shape_points[0].dx, cy+shape_points[0].dy)

        gfx.set(line_r, line_g, line_b, line_a)
        gfx.x, gfx.y = title_x(x, y), y + 5
        gfx.drawstr("Symbiote")
    end

    function draw_scope(x, y, w, h, zoom)
        local cy = y + h * 0.5
        
        local is_hover = (gfx.mouse_x >= x and gfx.mouse_x <= x + w and 
                          gfx.mouse_y >= y and gfx.mouse_y <= y + h)
        local is_user_frozen = is_hover and (gfx.mouse_cap & 1 == 1)
        local is_frozen = is_user_frozen or g_is_standby

        if not scope_last_idx then scope_last_idx = reaper.gmem_read(0) end
        local write_idx = is_frozen and scope_last_idx or reaper.gmem_read(0)
        if not is_frozen then scope_last_idx = write_idx end
        
        local srate = reaper.gmem_read(1)
        if srate <= 0 then srate = 44100 end
        local scope_speed_scaled = scope_speed * (srate / 44100)
        local step = (buf_len / w) * scope_speed_scaled

        if is_hover then
            step = (buf_len / w) * 0.3 * (srate / 44100)
        end
        local scan_stride = 2 

        for m = 0, w - 1 do
            local start_pos = (write_idx - (w - m) * step)
            
            local max_v = -100 
            local min_v = 100  
            local abs_peak = 0 
            
            for s = 0, step - 1, scan_stride do
                local read_ptr = math.floor(start_pos + s) % buf_len
                local raw_val = reaper.gmem_read(10000 + read_ptr) 
                
                if raw_val > max_v then max_v = raw_val end
                if raw_val < min_v then min_v = raw_val end
                
                local abs_v = math.abs(raw_val)
                if abs_v > abs_peak then abs_peak = abs_v end
            end
            
            local draw_max = max_v * zoom * 0.5
            local draw_min = min_v * zoom * 0.5
            
            local y_top = cy - (draw_max * h)
            local y_bottom = cy - (draw_min * h)
            
            y_top = math.max(y, math.min(y + h, y_top))
            y_bottom = math.max(y, math.min(y + h, y_bottom))
            
            local t = math.min(1.0, abs_peak * zoom)
            local local_t = t ^ steepness
            local scp_r, scp_g, scp_b, scp_a

            if t < midpoint then
                local local_t = t / midpoint
                local curve = local_t ^ steepness
                scp_r = scp1_r + (scp2_r - scp1_r) * curve
                scp_g = scp1_g + (scp2_g - scp1_g) * curve
                scp_b = scp1_b + (scp2_b - scp1_b) * curve
                scp_a = scp1_a + (scp2_a - scp1_a) * curve
            else
                local local_t = (t - midpoint) / (1 - midpoint)
                local curve = local_t ^ steepness
                scp_r = scp2_r + (scp3_r - scp2_r) * curve
                scp_g = scp2_g + (scp3_g - scp2_g) * curve
                scp_b = scp2_b + (scp3_b - scp2_b) * curve
                scp_a = scp2_a + (scp3_a - scp2_a) * curve
            end
            
            gfx.set(scp_r, scp_g, scp_b, scp_a)

            if math.abs(y_bottom - y_top) < 1 then
                gfx.rect(x + m, y_top, 1, 1)
            else
                gfx.line(x + m, y_top, x + m, y_bottom)
            end
        end
        
        gfx.set(line_r, line_g, line_b, line_a)
        gfx.x, gfx.y = title_x(x, y), y + 5
        gfx.drawstr("Scope")

        if is_user_frozen then
            gfx.set(227/255, 219/255, 142/255, 1.0)
            local fw, fh = gfx.measurestr("FREEZE")
            gfx.x, gfx.y = x + w - fw - 5, y + 5
            gfx.drawstr("FREEZE")
        end
    end

    ----------------------------------------------------------
    -- Track Spectrum Overlay
    --
    -- Colours the main Spectrum trace's own peak by whichever watched
    -- track is loudest at that frequency -- so a peak in the mix can be
    -- matched by eye to the track making it ("that's the guitar, that
    -- one's the bass").
    --
    -- FED BY TS_TrackProbe ITSELF. TS_TrackProbe (Track Analyser's plugin,
    -- baked into every track template) normally publishes to one of three
    -- FIXED gmem addresses, chosen by its Position slider -- built for one
    -- track (plus one comparison track) at a time, which can't show
    -- several tracks at once. Its "Include in Visualizer Spectrum"
    -- checkbox is a second, independent path: once ticked, this script can
    -- also hand that instance a SLOT (0..15) via its vis_slot parameter,
    -- and it publishes its already-computed log-band spectrum there
    -- instead of (or as well as) its fixed role address, so any number of
    -- tracks can be live at once. See TS_TrackProbe.jsfx's own header
    -- comment for the full reasoning.
    --
    -- An earlier version of this used a dedicated companion plugin,
    -- TS_SpectrumProbe.jsfx, before TS_TrackProbe grew its own checkbox --
    -- retired once every track already carrying TS_TrackProbe (which is to
    -- say, nearly every track) no longer needed a second plugin just to
    -- become selectable here.
    ----------------------------------------------------------

    local TA_NAMESPACE = "TS_TA_Mem"      -- shared with TS_TrackProbe
    local TA_CTRL_FFT  = 65               -- same slot TS_TrackProbe reads
    local SLOT_BASE, SLOT_STRIDE, MAX_SLOTS = 0x40000, 2048, 16
    local SLOT_H_BANDN, SLOT_H_BANDLO, SLOT_H_BANDHI = 1, 2, 3
    local SLOT_OFF_BAND, SLOT_BANDS = 16, 256

    -- Every reaper.gmem_read/write call anywhere in this script implicitly
    -- targets whichever block was last attach()ed, and this script
    -- attaches TS_Visualizer_Mem once at the very top and assumes that
    -- for its entire life. TS_TA_Mem (the probes' block) has to be
    -- visited and left again, atomically, or every gmem call after a
    -- forgotten switch-back would silently start reading or writing the
    -- wrong plugin's memory -- including this file's own colours. This
    -- is the only place that ever attaches anything other than
    -- TS_Visualizer_Mem, and it always restores that before returning,
    -- including when fn errors, which is what the pcall is for.
    function with_ta_mem(fn)
        reaper.gmem_attach(TA_NAMESPACE)
        local ok, a, b, c = pcall(fn)
        reaper.gmem_attach('TS_Visualizer_Mem')
        if not ok then return nil end
        return a, b, c
    end

    -- A track becomes watchable by ticking TS_TrackProbe's own "Include in
    -- Visualizer Spectrum" checkbox. That checkbox is the opt-in; without
    -- it every track in the project would qualify, since the plugin is
    -- everywhere. See TS_TrackProbe.jsfx's own note on vis_include/
    -- vis_slot for the full design -- param indices below are slider4 and
    -- slider5 there (0-based param index = slider number - 1).
    local TRACKPROBE_NAME = "TS_TrackProbe"
    local TRACKPROBE_VIS_INCLUDE_PARAM = 3
    local TRACKPROBE_VIS_SLOT_PARAM    = 4
    local function find_probe_fx(tr)
        local n = reaper.TrackFX_GetCount(tr)
        for i = 0, n - 1 do
            local ok, nm = reaper.TrackFX_GetFXName(tr, i, "")
            if ok and nm and nm:find(TRACKPROBE_NAME, 1, true) then
                local incl = reaper.TrackFX_GetParam(tr, i, TRACKPROBE_VIS_INCLUDE_PARAM)
                if incl and incl >= 0.5 then return i end
            end
        end
        return nil
    end

    local function set_probe_param(tr, fx_idx, param, value)
        if not reaper.ValidatePtr2(0, tr, "MediaTrack*") then return end
        pcall(reaper.TrackFX_SetParam, tr, fx_idx, param, value)
    end

    -- vis_slot is the whole of what this side owns -- TrackProbe's own
    -- Publish switch is Track Analyser's arm control and is never touched
    -- from here (see TS_TrackProbe.jsfx's own note on why the two are
    -- independent).
    local function arm_probe(e)
        set_probe_param(e.track, e.fx_idx, TRACKPROBE_VIS_SLOT_PARAM, e.slot)
    end

    local function disarm_probe(e)
        set_probe_param(e.track, e.fx_idx, TRACKPROBE_VIS_SLOT_PARAM, -1)
    end

    -- The track picker itself lives in the Spectrum panel now (a strip of
    -- swatches down its right edge -- see draw_track_swatches, called from
    -- draw_spectrum); it used to be a checkbox list in the Editor, then a
    -- whole-window sidebar. Wherever it lives, this file only ever needed
    -- the current selection, resolved below -- the Editor never shared
    -- Lua state with this script, only gmem and ExtState, so moving the
    -- picker changed nothing here.

    -- armed: guid -> { track, fx_idx, slot, r, g, b }. Project-scoped (a
    -- track GUID only means anything inside one project), so the WANTED
    -- side of this lives in project ExtState, not the user-global
    -- SECTION everything else in this file uses. The key is still called
    -- "FolderOverlayGUIDs" and the table "folder_overlay" -- this started
    -- folder-only and is now any track, but renaming every reference
    -- project-wide (including the saved ExtState key, which would orphan
    -- anyone's existing selection) wasn't worth doing in the same pass as
    -- actually generalising the behaviour.
    folder_overlay = { armed = {} }

    -- How far above the panel's own floor (in normalised 0..1 units, same
    -- scale as the t/ta/tp values draw_spectrum already works in) the
    -- loudest armed folder has to be, at a given frequency, before
    -- draw_spectrum will paint the master peak line in that folder's
    -- colour there. This is NOT a comparison against the master's own
    -- level -- a single folder is routinely far quieter than the summed
    -- master even when it's clearly the dominant contributor at that
    -- frequency, so gating on that basis meant the peak line almost never
    -- recoloured. This only exists to stop two silent folders (both
    -- sitting at the floor) from "winning" against each other on
    -- floating-point noise.
    FOLDER_DOMINANT_MIN_T = 0.03

    local function claim_free_slot()
        local used = {}
        for _, e in pairs(folder_overlay.armed) do used[e.slot] = true end
        for s = 0, MAX_SLOTS - 1 do
            if not used[s] then return s end
        end
        return nil -- every slot taken; MAX_SLOTS is generous enough that
                    -- hitting this in practice would mean something else
                    -- is already wrong, not that 16 folders were selected
    end

    function disarm_folder_overlay()
        if next(folder_overlay.armed) then
            with_ta_mem(function()
                for _, e in pairs(folder_overlay.armed) do
                    disarm_probe(e)
                end
            end)
        end
        folder_overlay.armed = {}
    end

    -- Throttled the same way ChannelView/TrackAnalyser poll the shared
    -- palette: this is a project scan, not something worth doing every
    -- one of 45 frames a second when nothing has changed.
    local folder_poll = -1
    function poll_folder_overlay()
        local now = reaper.time_precise()
        if now - folder_poll < 0.5 then return end
        folder_poll = now

        local _, csv = reaper.GetProjExtState(0, "TS_Visualizer", "FolderOverlayGUIDs")
        local wanted = {}
        for g in csv:gmatch("[^,]+") do wanted[g] = true end

        -- Drop anything armed that's no longer wanted, or whose track has
        -- gone away -- freeing its slot for whatever's picked next.
        local to_drop = {}
        for guid, e in pairs(folder_overlay.armed) do
            if not (wanted[guid] and reaper.ValidatePtr2(0, e.track, "MediaTrack*")) then
                to_drop[#to_drop + 1] = guid
            end
        end
        if #to_drop > 0 then
            with_ta_mem(function()
                for _, guid in ipairs(to_drop) do
                    disarm_probe(folder_overlay.armed[guid])
                end
            end)
            for _, guid in ipairs(to_drop) do folder_overlay.armed[guid] = nil end
        end

        -- Anything still wanted that isn't armed yet: one project-track
        -- walk covers every newly wanted guid in the same pass, rather
        -- than a separate walk per guid.
        local pending = {}
        local pending_n = 0
        for guid in pairs(wanted) do
            if not folder_overlay.armed[guid] then pending[guid] = true; pending_n = pending_n + 1 end
        end
        if pending_n > 0 then
            local newly_armed = {}
            local count = reaper.CountTracks(0)
            for i = 0, count - 1 do
                local tr = reaper.GetTrack(0, i)
                local _, guid = reaper.GetSetMediaTrackInfo_String(tr, "GUID", "", false)
                if pending[guid] then
                    local fx_idx = find_probe_fx(tr)
                    local slot = fx_idx and claim_free_slot()
                    if fx_idx and slot then
                        local r, g, b = 1, 1, 1
                        local native = reaper.GetTrackColor(tr)
                        if native ~= 0 then
                            local rr, gg, bb = reaper.ColorFromNative(native)
                            r, g, b = rr / 255, gg / 255, bb / 255
                        end
                        folder_overlay.armed[guid] = { track = tr, fx_idx = fx_idx, slot = slot, r = r, g = g, b = b }
                        newly_armed[#newly_armed + 1] = folder_overlay.armed[guid]
                    end
                end
            end
            if #newly_armed > 0 then
                with_ta_mem(function()
                    -- Only nudge the shared FFT size if it doesn't
                    -- already say what these probes want. If Track
                    -- Analyser's panel is open and has already set it,
                    -- leave it alone rather than restarting every probe
                    -- (its own included) over a difference that isn't
                    -- worth a restart either way. 4096, matching the
                    -- master Spectrum trace's own FFT size, not 2048 --
                    -- the finer the native bin resolution, the less often
                    -- a 256-band split ends up narrower than a bin at the
                    -- low end, which is where peaks were reading soft.
                    if reaper.gmem_read(TA_CTRL_FFT) ~= 4096 then
                        reaper.gmem_write(TA_CTRL_FFT, 4096)
                    end
                    for _, e in ipairs(newly_armed) do
                        arm_probe(e)
                    end
                end)
            end
        end
    end

    -- Every armed folder's 256-band log summary, read in one attach/
    -- detach cycle rather than one per folder. Returns nil when nothing
    -- is armed; otherwise a list of { r, g, b, bands = {{hz, db}, ...} },
    -- skipping any slot that hasn't published a frame yet.
    function read_folder_overlay_bands()
        if not next(folder_overlay.armed) then return nil end
        return with_ta_mem(function()
            local out = {}
            for _, e in pairs(folder_overlay.armed) do
                local base = SLOT_BASE + e.slot * SLOT_STRIDE
                local nb = reaper.gmem_read(base + SLOT_H_BANDN)
                if nb and nb > 0 then
                    local lo = reaper.gmem_read(base + SLOT_H_BANDLO)
                    local hi = reaper.gmem_read(base + SLOT_H_BANDHI)
                    if lo and lo > 0 and hi and hi > lo then
                        local ratio = math.log(hi / lo)
                        local bands = {}
                        for i = 0, nb - 1 do
                            local db = reaper.gmem_read(base + SLOT_OFF_BAND + i)
                            bands[#bands + 1] = { hz = lo * math.exp(ratio * (i + 0.5) / nb), db = db }
                        end
                        -- nb/lo/hi/ratio are kept alongside the expanded
                        -- band list so a caller that already knows a
                        -- frequency (draw_spectrum's dominant-folder
                        -- lookup, below) can index straight to the right
                        -- band instead of scanning the list.
                        out[#out + 1] = { r = e.r, g = e.g, b = e.b, bands = bands,
                                           nb = nb, lo = lo, hi = hi, ratio = ratio }
                    end
                end
            end
            return out
        end)
    end

    local function freq_to_note(freq)
        if freq <= 0 then return "N/A" end
        local n = 12 * (math.log(freq / 440, 2)) + 69
        local midi_int = math.floor(n + 0.5)
        local names = {"C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"}
        local note_idx = (midi_int % 12) + 1
        local octave = math.floor(midi_int / 12) - 1
        return names[note_idx] .. octave
    end

    function draw_spectrum(x, y, w, h, ceil, floor)
        local base_area_decay = 2.0 
        local base_peak_decay = 1.0 
        local area_decay_rate = base_area_decay * g_signal_release
        local peak_decay_rate = base_peak_decay * g_signal_release
        
        local is_hover = (gfx.mouse_x >= x and gfx.mouse_x <= x + w and 
                      gfx.mouse_y >= y and gfx.mouse_y <= y + h)
        local is_user_frozen = is_hover and (gfx.mouse_cap & 1 == 1)
        local is_frozen = is_user_frozen or g_is_standby
        if is_hover and not is_frozen then
            area_decay_rate = 1.0 * g_signal_release
        end

        local range = ceil - floor
        local srate = reaper.gmem_read(1)
        if srate == 0 then srate = 48000 end
        local now = reaper.time_precise()
        local target_max_hz = 48000
        local max_k = target_max_hz * fft_size / srate
        local k_max_log = math.log(max_k)

        -- Spectrum Tilt: an optional constant dB/octave shift (about 1kHz)
        -- applied to the displayed curve itself, so broadband material with
        -- a matching natural rolloff (e.g. pink-ish mix energy) reads flat
        -- instead of sloping down to the right.
        local tilt_db_oct = reaper.gmem_read(1410)
        local k_1khz = 1000 * fft_size / srate
        local log2_const = math.log(2)

        gfx.set(line_r, line_g, line_b, line_a)

        -- One entry per analysis step: where it lands, how high the smoothed
        -- level is and how high the peak hold is, all 0..1 of the panel.
        local pts_x, pts_t, pts_p, np = {}, {}, {}, 0
        local vis_t_smooth = nil -- light frequency-axis smoothing across adjacent bins
        local k = 1
        while k <= max_k do
            local k_int = math.floor(k)
            local k_frac = k - k_int
            
            local k_idx = math.floor(k * 10)
            
            local mag1 = reaper.gmem_read(300000 + k_int)
            local mag2 = reaper.gmem_read(300000 + k_int + 1)
            local mag = mag1 + (mag2 - mag1) * k_frac

            local pure_db = 20 * math.log(mag + 0.0000001, 10)
            local raw_db = pure_db - spec_offset
            if pure_db < -120 then
                raw_db = floor - 10
            elseif tilt_db_oct ~= 0 then
                local octaves_from_1k = math.log(k / k_1khz) / log2_const
                raw_db = raw_db + tilt_db_oct * octaves_from_1k
            end

            local db = raw_db

            local smooth_db = spec_smooth_vals[k_idx] or (floor - 10)
            
            if not is_frozen then 
                if raw_db >= smooth_db then
                    local attack_coef = math.min(1.0, 0.65 * g_signal_attack)
                    smooth_db = smooth_db + (raw_db - smooth_db) * attack_coef
                else
                    smooth_db = smooth_db - area_decay_rate
                end
                spec_smooth_vals[k_idx] = smooth_db
            end

            local current_peak = spec_peaks[k_idx] or -144
            local last_time = spec_peak_times[k_idx] or 0
            
            if not is_frozen then 
                if db >= current_peak then
                    spec_peaks[k_idx] = db
                    spec_peak_times[k_idx] = now
                else
                    if (now - last_time) > peak_hold_time then
                        spec_peaks[k_idx] = current_peak - peak_decay_rate
                    end
                end
            end
            local peak_db = spec_peaks[k_idx]

            local t_raw = (smooth_db - floor) / range
            t_raw = math.max(0, math.min(1, t_raw))
            local t = t_raw -- linear dB-to-pixel mapping (no power curve)

            -- Light smoothing across neighboring bins (frequency axis), on
            -- top of the existing per-bin time-domain smoothing, to soften
            -- bin-to-bin jaggedness a touch.
            if vis_t_smooth then
                vis_t_smooth = vis_t_smooth + (t - vis_t_smooth) * 0.6
            else
                vis_t_smooth = t
            end
            t = vis_t_smooth

            local dy = y + h - (t * h)
            
            local pt_raw = (peak_db - floor) / range
            local pt = math.max(0, math.min(1, pt_raw))
            local pdy = y + h - (pt * h)

            local x_norm = math.log(k) / k_max_log
            local dx = x + (x_norm * w)
            
            -- Nothing is drawn in here any more; the shape is collected
            -- and rasterised by pixel column below. See the note there.
            np = np + 1
            pts_x[np] = dx ; pts_t[np] = t ; pts_p[np] = pt

            local step = 1
            if k <= 200 then
                step = 0.2
            else
                step = k * 0.005
            end
            k = k + step
        end

        ------------------------------------------------------------------
        -- FILL BY PIXEL COLUMN, NOT BY ANALYSIS STEP
        --
        -- The fill used to be one alpha-blended quad per step. Two adjacent
        -- quads overlap along their shared edge by a fraction of a pixel,
        -- and that sliver gets blended twice -- so every seam drew a
        -- brighter vertical line. Above a couple of hundred hertz the steps
        -- are narrower than a pixel and the seams smear into one another;
        -- below it they are several pixels apart, which is exactly where
        -- the striping showed.
        --
        -- One vertical line per column, anti-aliasing off, cannot overlap
        -- itself, so the artefact cannot happen. Columns between two steps
        -- are interpolated, so the low end stays continuous rather than
        -- turning into a picket fence the other way.
        ------------------------------------------------------------------
        -- Read every armed folder's bands once per frame (not once per
        -- pixel, and not a second time down in the curve-overlay block
        -- below -- both uses share this same table now).
        local folder_groups = next(folder_overlay.armed) and read_folder_overlay_bands() or nil

        if np > 1 then
            local pxA, pxB = math.floor(x), math.floor(x + w)
            local j, prevX, prevY, prevP = 1, nil, nil, nil
            for px = pxA, pxB do
                while j < np - 1 and pts_x[j + 1] < px do j = j + 1 end
                local ta, tp
                if px <= pts_x[1] then
                    ta, tp = pts_t[1], pts_p[1]
                elseif px >= pts_x[np] then
                    ta, tp = pts_t[np], pts_p[np]
                else
                    local xa, xb = pts_x[j], pts_x[j + 1]
                    local f = (xb > xa) and (px - xa) / (xb - xa) or 0
                    f = math.max(0, math.min(1, f))
                    ta = pts_t[j] + (pts_t[j + 1] - pts_t[j]) * f
                    tp = pts_p[j] + (pts_p[j + 1] - pts_p[j]) * f
                end

                -- Which armed folder, if any, is loudest at this column's
                -- Hz, relative to the OTHER armed folders -- not relative
                -- to the master. A single folder is one of several things
                -- summed into the master, so on a real mix it is routinely
                -- 10-20dB or more under the master even when it's clearly
                -- the dominant contributor at that frequency; gating
                -- against the master's own level (an earlier version of
                -- this did) meant the gate almost never opened. The only
                -- gate that still matters is FOLDER_DOMINANT_MIN_T: the
                -- winning folder has to be above the noise floor by a
                -- small margin, or two folders both sitting at -180dB
                -- would "win" on floating-point noise alone. Used below to
                -- override the "Strong (Peak)" fill-gradient stop, not the
                -- separate "Spec Freq Line" peak-hold stroke, which stays
                -- its own plain colour regardless.
                local dom_r, dom_g, dom_b = nil, nil, nil
                if folder_groups then
                    local x_norm_px = (px - x) / w
                    if x_norm_px >= 0 and x_norm_px <= 1 then
                        local k_val = math.exp(x_norm_px * k_max_log)
                        local hz = k_val * srate / fft_size
                        local best_t, best_grp = nil, nil
                        for _, grp in ipairs(folder_groups) do
                            if grp.nb and hz >= grp.lo and hz <= grp.hi then
                                local idx = math.floor(grp.nb * math.log(hz / grp.lo) / grp.ratio)
                                if idx < 0 then idx = 0 elseif idx >= grp.nb then idx = grp.nb - 1 end
                                local bnd = grp.bands[idx + 1]
                                if bnd then
                                    local tg = (bnd.db - floor) / range
                                    tg = math.max(0, math.min(1, tg))
                                    if not best_t or tg > best_t then
                                        best_t, best_grp = tg, grp
                                    end
                                end
                            end
                        end
                        if best_grp and best_t >= FOLDER_DOMINANT_MIN_T then
                            dom_r, dom_g, dom_b = best_grp.r, best_grp.g, best_grp.b
                        end
                    end
                end

                if ta < midpoint then
                    local curve = (ta / midpoint) ^ steepness
                    sptr_r = sptr1_r + (sptr2_r - sptr1_r) * curve
                    sptr_g = sptr1_g + (sptr2_g - sptr1_g) * curve
                    sptr_b = sptr1_b + (sptr2_b - sptr1_b) * curve
                    sptr_a = sptr1_a + (sptr2_a - sptr1_a) * curve
                else
                    -- Above the midpoint the fill blends toward the
                    -- "Strong (Peak)" stop (sptr3) as the level approaches
                    -- 1. Swapping that stop's colour for the dominant
                    -- folder's, only here, means a tall peak fades UP into
                    -- whichever folder owns it while staying the normal
                    -- fill colour lower down -- the override rides the
                    -- fill's own existing gradient instead of adding a
                    -- separate line or area on top of it.
                    local curve = ((ta - midpoint) / (1 - midpoint)) ^ steepness
                    local strong_r, strong_g, strong_b = sptr3_r, sptr3_g, sptr3_b
                    if dom_r then strong_r, strong_g, strong_b = dom_r, dom_g, dom_b end
                    sptr_r = sptr2_r + (strong_r - sptr2_r) * curve
                    sptr_g = sptr2_g + (strong_g - sptr2_g) * curve
                    sptr_b = sptr2_b + (strong_b - sptr2_b) * curve
                    sptr_a = sptr2_a + (sptr3_a - sptr2_a) * curve
                end

                local dy = y + h - (ta * h)
                gfx.set(sptr_r, sptr_g, sptr_b, sptr_a)
                gfx.line(px, y + h, px, dy, 0)

                -- The graded fill is faintest exactly where the shape
                -- matters, along its own top edge, so the edge gets a thin
                -- line in the fill's colour lifted toward white. That is
                -- what gives the Track Analyser spectrum its definition.
                if prevX then
                    gfx.set(sptr_r + (1 - sptr_r) * 0.30,
                            sptr_g + (1 - sptr_g) * 0.30,
                            sptr_b + (1 - sptr_b) * 0.30,
                            math.min(1.0, sptr_a + 0.35))
                    gfx.line(prevX, prevY, px, dy, 1)
                end

                -- "Spec Freq Line": the plain peak-hold stroke, its own
                -- fixed colour always -- the dominant-folder override
                -- lives in the fill's "Strong (Peak)" stop above, not here.
                local pdy = y + h - (tp * h)
                if prevP then
                    gfx.set(peak_r, peak_g, peak_b, peak_a)
                    gfx.line(px - 1, prevP, px, pdy, 1)
                end

                prevX, prevY, prevP = px, dy, pdy
            end
        end

        -- The separate per-folder "baseline" curve (each armed folder's
        -- own absolute-level trace, drawn low against the panel since a
        -- single folder is routinely far quieter than the summed master)
        -- used to be drawn here. Removed now that the "Strong (Peak)"
        -- fill-gradient override above does the actual job -- showing
        -- which folder owns a peak by colouring the peak itself, not by a
        -- second, separately-scaled curve that needed reading alongside
        -- the master trace. folder_groups is still fetched above and
        -- still drives that override; only this extra curve is gone.

        gfx.set(line_r, line_g, line_b, line_a)
        local freqs = {100, 1000, 10000}
        local labels = {"100", "1k", "10k"}
        for i, freq in ipairs(freqs) do
            local k = freq * (fft_size) / srate
            if k > 0 then
                local x_norm = math.log(k) / k_max_log
                if x_norm > 0 and x_norm < 1 then
                    local gx = x + x_norm * w
                    gfx.line(gx, y, gx, y + h)
                    gfx.x, gfx.y = gx + 2, y + h - 22
                    gfx.drawstr(labels[i])
                end
            end
        end

        draw_track_swatches(x, y, w, h)
        
        if gfx.mouse_x >= x and gfx.mouse_x <= x + w and gfx.mouse_y >= y and gfx.mouse_y <= y + h then
            local x_norm = (gfx.mouse_x - x) / w
            local k_val = math.exp(x_norm * k_max_log)
            local hz = k_val * srate / fft_size

            -- Slope Guide Line (pivots through the cursor position). Traced
            -- per pixel through the same (now linear) dB-to-pixel mapping
            -- the spectrum itself uses, so a constant dB/octave slope comes
            -- out as a true straight line. Net slope is (guide - tilt): the
            -- guide represents a slope value in the material's own terms,
            -- and Spectrum Tilt has already flattened that much of it out of
            -- the display, so a guide set to the same dB/oct as the tilt
            -- reads as horizontal - matching a signal that follows exactly
            -- that rolloff and is therefore already flat on screen.
            local slope_db_oct = reaper.gmem_read(1400)
            if slope_db_oct == 0 then slope_db_oct = 4.5 end

            if slope_db_oct ~= -1 then
                local pivot_t_raw = (y + h - gfx.mouse_y) / h
                pivot_t_raw = math.max(0, math.min(1, pivot_t_raw))
                local pivot_db = floor + pivot_t_raw * range
                local pivot_k = k_val
                local log2 = math.log(2)
                local net_slope_db_oct = slope_db_oct - tilt_db_oct

                gfx.set(line_r, line_g, line_b, 0.3)
                local guide_px, guide_py = nil, nil
                local w_int = math.floor(w)
                for px = 0, w_int do
                    local g_x_norm = px / w
                    local g_k = math.exp(g_x_norm * k_max_log)
                    local octaves = math.log(g_k / pivot_k) / log2
                    local g_db = pivot_db - net_slope_db_oct * octaves
                    local g_t = math.max(0, math.min(1, (g_db - floor) / range))
                    local g_dy = y + h - (g_t * h)
                    local g_dx = x + px
                    if guide_px then
                        gfx.line(guide_px, guide_py, g_dx, g_dy)
                    end
                    guide_px, guide_py = g_dx, g_dy
                end
            end

            local note = freq_to_note(hz)
            local info_text = string.format("%.0f Hz (%s)", hz, note)
            
            gfx.setfont(1, "Arial", (base_title_size) * g_font_scale)
            local tw, th = gfx.measurestr(info_text)
            local tx, ty = gfx.mouse_x + 10, gfx.mouse_y - 20
            
            if tx + tw > gfx.w then tx = gfx.mouse_x - tw - 10 end
            if ty < 0 then ty = gfx.mouse_y + 20 end
            
            gfx.set(bg_r, bg_g, bg_b, 0.9) 
            gfx.rect(tx - 4, ty - 2, tw + 8, th + 4, 1)
            
            gfx.set(line_r, line_g, line_b, 0.5)
            gfx.rect(tx - 4, ty - 2, tw + 8, th + 4, 0)

            gfx.set(1, 1, 1, 1) 
            gfx.x, gfx.y = tx, ty
            gfx.drawstr(info_text)
            
            gfx.set(line_r, line_g, line_b, 0.3)
            gfx.line(gfx.mouse_x, y, gfx.mouse_x, y + h)
            
            gfx.setfont(1, "Arial", base_title_size * g_font_scale)
        end

        gfx.set(line_r, line_g, line_b, line_a)
        gfx.x, gfx.y = title_x(x, y), y + 5
        gfx.drawstr("Spectrum")

        if is_user_frozen then
            gfx.set(227/255, 219/255, 142/255, 1.0)
            local fw, fh = gfx.measurestr("FREEZE")
            gfx.x, gfx.y = x + w - fw - 5, y + 5
            gfx.drawstr("FREEZE")
        end
    end

    function draw_spectrogram(x, y, w, h, gain, floor_db)
        local is_hover = (gfx.mouse_x >= x and gfx.mouse_x <= x + w and 
                          gfx.mouse_y >= y and gfx.mouse_y <= y + h)
        local is_user_frozen = is_hover and (gfx.mouse_cap & 1 == 1)
        local is_frozen = is_user_frozen or g_is_standby

        local current_scan_speed = w_scan_speed
        if is_hover and not is_frozen then
            current_scan_speed = math.max(1, math.floor(w_scan_speed * 0.25)) 
        end

        if w ~= w_last_w or h ~= w_last_h then
            gfx.dest = waterfall_canvas_id
            gfx.setimgdim(waterfall_canvas_id, -1, -1)
            gfx.setimgdim(waterfall_canvas_id, w, h)
            gfx.set(bg_r, bg_g, bg_b, 1) 
            gfx.rect(0, 0, w, h, 1)
            w_last_w, w_last_h = w, h
            w_last_col_data = {}
            w_cursor_idx = 0
        end

        local RES_W = math.floor(w) * 2
        local RES_H = math.floor(h)
        if RES_H < 10 then RES_H = 10 end
        local block_w = w / RES_W
        local block_h = h / RES_H
        local scale_exponent = 3.0 

        local srate = reaper.gmem_read(1)
        if srate <= 0 then srate = 48000 end
        local min_hz = 50
        local min_bin = min_hz * fft_size / srate
        local num_bins = fft_size / 2
        local bin_range = num_bins - min_bin

        local val_threshold = 1.0
        local val_gain = 0.25
        local thresh_db = -100 + (val_threshold * 80)
        local gain_boost = val_gain * 60

        if not is_frozen then
            local col_data = {}
            for y_px = 0, RES_H - 1 do
                local norm_y = (RES_H - 1 - y_px) / RES_H
                local idx_float = min_bin + (bin_range * (norm_y ^ scale_exponent))
                local i1 = math.floor(idx_float)
                local t = idx_float - i1
                local i2 = math.min(num_bins - 1, i1 + 1)
                
                local p1 = reaper.gmem_read(300000 + i1)
                local p2 = reaper.gmem_read(300000 + i2)
                
                local raw = p1 + (p2 - p1) * t
                if raw < 1e-10 then raw = 1e-10 end
                col_data[y_px] = 20 * math.log(raw, 10)
            end

            if w_last_col_data[0] == nil then 
                w_last_col_data = col_data 
            end

            gfx.dest = waterfall_canvas_id
            for s = 0, current_scan_speed - 1 do
                local current_idx = (w_cursor_idx + s) % RES_W
                local screen_x = current_idx * block_w
                local horiz_t = s / current_scan_speed
                
                gfx.set(bg_r, bg_g, bg_b, 1)
                gfx.rect(screen_x, 0, block_w + 1, h, 1)

                for y_px = 0, RES_H - 1 do
                    local prev_db = w_last_col_data[y_px] or col_data[y_px]
                    local interp_db = prev_db * (1 - horiz_t) + col_data[y_px] * horiz_t
                    
                    if interp_db >= thresh_db then
                        local effective_db = (interp_db - thresh_db) + gain_boost
                        local intensity = effective_db / 60.0
                        if intensity > 0.05 then
                            if intensity > 1 then intensity = 1 end
                            local c_r, c_g, c_b, c_a
                            local w_sptr2_a = sptr2_a * 0.7
                            if intensity < 0.5 then
                                local t_c = intensity * 2.0
                                c_r = sptr1_r + (sptr2_r - sptr1_r) * t_c
                                c_g = sptr1_g + (sptr2_g - sptr1_g) * t_c
                                c_b = sptr1_b + (sptr2_b - sptr1_b) * t_c
                                c_a = sptr1_a + (w_sptr2_a - sptr1_a) * t_c
                            else
                                local t_c = (intensity - 0.5) * 2.0
                                c_r = sptr2_r + (sptr3_r - sptr2_r) * t_c
                                c_g = sptr2_g + (sptr3_g - sptr2_g) * t_c
                                c_b = sptr2_b + (sptr3_b - sptr2_b) * t_c
                                c_a = w_sptr2_a + (sptr3_a - w_sptr2_a) * t_c
                            end
                            gfx.set(c_r, c_g, c_b, c_a)
                            gfx.rect(screen_x, y_px * block_h, block_w + 0.5, block_h + 0.1, 1)
                        end
                    end
                end
            end
            w_last_col_data = col_data
        end

        gfx.dest = -1
        gfx.set(1, 1, 1, 1)
        
        local advance = is_frozen and 0 or current_scan_speed
        local split_x = (w_cursor_idx + advance) * block_w
        
        gfx.blit(waterfall_canvas_id, 1, 0, split_x, 0, w - split_x, h, x, y, w - split_x, h)
        gfx.blit(waterfall_canvas_id, 1, 0, 0, 0, split_x, h, x + w - split_x, y, split_x, h)

        local function draw_freq_line(hz_val, label_text)
            local target_bin = hz_val * fft_size / srate
            if target_bin < min_bin then return end
            local norm_y = ((target_bin - min_bin) / bin_range) ^ (1 / scale_exponent)
            local line_y = y + (1 - norm_y) * h
            
            gfx.set(line_r, line_g, line_b, line_a / 2) 
            gfx.line(x, line_y, x + w, line_y)
            
            gfx.set(text_r, text_g, text_b, text_a / 3)
            gfx.x = x + 5; gfx.y = line_y - 12
            gfx.drawstr(label_text)
        end
        
        draw_freq_line(10000, "10k")
        draw_freq_line(1000, "1k")
        draw_freq_line(100, "100")

        if is_hover then
            local norm_y = 1 - ((gfx.mouse_y - y) / h)
            local idx_float = min_bin + (bin_range * (norm_y ^ scale_exponent))
            local hz = idx_float * srate / fft_size
            local note = freq_to_note(hz)
            local info_text = string.format("%.0f Hz (%s)", hz, note)
            
            gfx.setfont(1, "Arial", base_title_size * g_font_scale)
            local tw, th = gfx.measurestr(info_text)
            local tx, ty = gfx.mouse_x + 10, gfx.mouse_y - 20
            if tx + tw > gfx.w then tx = gfx.mouse_x - tw - 10 end
            if ty < 0 then ty = gfx.mouse_y + 20 end
            
            gfx.set(bg_r, bg_g, bg_b, 0.9) 
            gfx.rect(tx - 4, ty - 2, tw + 8, th + 4, 1)
            gfx.set(line_r, line_g, line_b, 0.5)
            gfx.rect(tx - 4, ty - 2, tw + 8, th + 4, 0)

            gfx.set(text_r, text_g, text_b, text_a)
            gfx.x, gfx.y = tx, ty
            gfx.drawstr(info_text)
            
            gfx.set(line_r, line_g, line_b, 0.3)
            gfx.line(x, gfx.mouse_y, x + w, gfx.mouse_y)
        end

        gfx.set(line_r, line_g, line_b, line_a)
        gfx.x, gfx.y = title_x(x, y), y + 5
        gfx.drawstr("Spectrogram")

        if is_user_frozen then
            gfx.set(227/255, 219/255, 142/255, 1.0)
            local fw, fh = gfx.measurestr("FREEZE")
            gfx.x, gfx.y = x + w - fw - 5, y + 5
            gfx.drawstr("FREEZE")
        elseif not is_frozen then
            w_cursor_idx = (w_cursor_idx + current_scan_speed) % RES_W
        end
    end

    ----------------------------------------------------------
    -- Dynamics Panel (live loudness vs PSR/Crest-Factor trail)
    ----------------------------------------------------------
    local dyn_trail = {}
    local dyn_cloud = {}
    local DYN_CLOUD_MAX = 20000
    local dyn_last_sample_time = 0
    local dyn_cloud_last_time = 0
    local dyn_was_playing = false
    local DYN_TRAIL_INTERVAL = 0.05   -- fast: keeps the comet smooth
    local DYN_CLOUD_INTERVAL = 0.25   -- slow: lets the cloud span a whole song before the cap hits
    local DYN_TRAIL_FADE_SEC = 3.0    -- trail points older than this are dropped
    local DYN_CLOUD_R, DYN_CLOUD_G, DYN_CLOUD_B = 006/255, 143/255, 195/255 -- fixed teal, independent of theme

    local DYN_Y_MIN, DYN_Y_MAX = -40, 0   -- Short-term LUFS axis
    local DYN_X_MIN, DYN_X_MAX = 0, 28    -- PSR axis (dB)

    -- Loudness Target ladder, whole-number LUFS from -6 (loudest) to -24
    -- (matches JSFX slider6 / gmem[25])
    local LOUDNESS_TARGETS = {
        [1]  = { name = "-6 LUFS (Loud/Rock)",  lufs = -6  },
        [2]  = { name = "-7 LUFS",              lufs = -7  },
        [3]  = { name = "-8 LUFS",              lufs = -8  },
        [4]  = { name = "-9 LUFS",              lufs = -9  },
        [5]  = { name = "-10 LUFS",             lufs = -10 },
        [6]  = { name = "-11 LUFS",             lufs = -11 },
        [7]  = { name = "-12 LUFS",             lufs = -12 },
        [8]  = { name = "-13 LUFS",             lufs = -13 },
        [9]  = { name = "-14 LUFS (Streaming)", lufs = -14 },
        [10] = { name = "-15 LUFS",             lufs = -15 },
        [11] = { name = "-16 LUFS",             lufs = -16 },
        [12] = { name = "-17 LUFS",             lufs = -17 },
        [13] = { name = "-18 LUFS",             lufs = -18 },
        [14] = { name = "-19 LUFS",             lufs = -19 },
        [15] = { name = "-20 LUFS",             lufs = -20 },
        [16] = { name = "-21 LUFS",             lufs = -21 },
        [17] = { name = "-22 LUFS",             lufs = -22 },
        [18] = { name = "-23 LUFS",             lufs = -23 },
        [19] = { name = "-24 LUFS (Broadcast)", lufs = -24 },
    }

    -- Genre PSR target bands (center +/- tolerance), pulled directly from
    -- true:level's own reference zones - same PSR metric family we compute.
    -- Bands widened ~0.5dB on each side beyond the raw true:level +/- tolerance,
    -- for a bit more visual breathing room.
    local GENRE_TARGETS = {
        [1]  = { name = "Universal", dyn_lo = 9.4,  dyn_hi = 14.4 },
        [2]  = { name = "Acoustic",  dyn_lo = 10.5, dyn_hi = 14.5 },
        [3]  = { name = "Classical", dyn_lo = 12.4, dyn_hi = 15.4 },
        [4]  = { name = "Country",   dyn_lo = 12.2, dyn_hi = 15.2 },
        [5]  = { name = "EDM",       dyn_lo = 8.3,  dyn_hi = 12.3 },
        [6]  = { name = "Funk",      dyn_lo = 11.8, dyn_hi = 16.8 },
        [7]  = { name = "Hip Hop",   dyn_lo = 9.9,  dyn_hi = 13.9 },
        [8]  = { name = "Jazz",      dyn_lo = 12.7, dyn_hi = 15.7 },
        [9]  = { name = "Metal",     dyn_lo = 8.9,  dyn_hi = 12.9 },
        [10] = { name = "Pop",       dyn_lo = 9.1,  dyn_hi = 13.1 },
        [11] = { name = "R&B",       dyn_lo = 10.2, dyn_hi = 15.2 },
        [12] = { name = "Rock",      dyn_lo = 10.0, dyn_hi = 13.0 },
        [13] = { name = "Speech",    dyn_lo = 12.1, dyn_hi = 20.1 },
    }

    function draw_dynamics(x, y, w, h)
        gfx.set(bg_r, bg_g, bg_b, bg_a)
        gfx.rect(x, y, w, h, 1)

        local short_lufs = reaper.gmem_read(21)
        local peak_db = reaper.gmem_read(23)
        local has_signal = (short_lufs > -100) and (peak_db > -100)

        -- PSR (Peak to Short-term Loudness Ratio) - the same metric family
        -- true:level uses, so it matches the genre target bands.
        local metric_label = "PSR"
        local metric_val = 0
        if short_lufs > -100 then metric_val = peak_db - short_lufs end

        local is_hover = (gfx.mouse_x >= x and gfx.mouse_x <= x + w and
                          gfx.mouse_y >= y and gfx.mouse_y <= y + h)

        local plot_x, plot_y = x + 8, y + 20
        local plot_w, plot_h = math.max(10, w - 16), math.max(10, h - 40)

        local function to_px(mx, my)
            local tx = (mx - DYN_X_MIN) / (DYN_X_MAX - DYN_X_MIN)
            local ty = (my - DYN_Y_MIN) / (DYN_Y_MAX - DYN_Y_MIN)
            tx = math.max(0, math.min(1, tx))
            ty = math.max(0, math.min(1, ty))
            return plot_x + tx * plot_w, plot_y + plot_h - ty * plot_h
        end

        -- Cloud resets when the transport stops (persists for the length of a
        -- playback pass, not the whole script session)
        local play_state = reaper.GetPlayState()
        local is_playing = (play_state & 1) == 1
        if dyn_was_playing and not is_playing then
            dyn_cloud = {}
        end
        dyn_was_playing = is_playing

        -- Accumulate trail (fast, for a smooth comet) / cloud (slow, so it can
        -- span a whole song's worth of playback before the cap is reached)
        local now = reaper.time_precise()
        if has_signal and (now - dyn_last_sample_time) > DYN_TRAIL_INTERVAL then
            dyn_last_sample_time = now
            table.insert(dyn_trail, { mx = metric_val, my = short_lufs, t = now })
        end
        while #dyn_trail > 0 and (now - dyn_trail[1].t) > DYN_TRAIL_FADE_SEC do
            table.remove(dyn_trail, 1)
        end
        if has_signal and (now - dyn_cloud_last_time) > DYN_CLOUD_INTERVAL then
            dyn_cloud_last_time = now
            table.insert(dyn_cloud, { mx = metric_val, my = short_lufs })
            if #dyn_cloud > DYN_CLOUD_MAX then table.remove(dyn_cloud, 1) end
        end

        -- Minimal scale: axis-extent labels only, no grid
        gfx.setfont(1, "Arial", (base_title_size - 8) * g_font_scale)
        gfx.set(text_r, text_g, text_b, text_a * 0.4)
        gfx.x, gfx.y = plot_x, plot_y - 1
        gfx.drawstr(string.format("%d", DYN_Y_MAX))
        local ymin_str = string.format("%d LUFS", DYN_Y_MIN)
        local _, ymin_h = gfx.measurestr(ymin_str)
        gfx.x, gfx.y = plot_x, plot_y + plot_h - ymin_h
        gfx.drawstr(ymin_str)
        gfx.x, gfx.y = plot_x, plot_y + plot_h + 3
        gfx.drawstr(string.format("%d", DYN_X_MIN))
        local xmax_str = string.format("%d dB", DYN_X_MAX)
        local xmax_w = gfx.measurestr(xmax_str)
        gfx.x, gfx.y = plot_x + plot_w - xmax_w, plot_y + plot_h + 3
        gfx.drawstr(xmax_str)

        -- Genre/Dynamics target band (vertical dynamic-range guide) - grey, low opacity
        local genre_idx = reaper.gmem_read(26)
        local genre_tgt = GENRE_TARGETS[genre_idx]
        if genre_tgt then
            local lo_x = to_px(genre_tgt.dyn_lo, DYN_Y_MIN)
            local hi_x = to_px(genre_tgt.dyn_hi, DYN_Y_MIN)
            gfx.set(line_r, line_g, line_b, 0.12)
            gfx.rect(lo_x, plot_y, math.max(1, hi_x - lo_x), plot_h, 1)
        end

        -- Loudness target band (target +/- 2.5 LUFS) - grey, low opacity
        local loud_idx = reaper.gmem_read(25)
        local loud_tgt = LOUDNESS_TARGETS[loud_idx]
        if loud_tgt then
            local _, y_hi = to_px(DYN_X_MIN, loud_tgt.lufs + 2.5)
            local _, y_lo = to_px(DYN_X_MIN, loud_tgt.lufs - 2.5)
            local top = math.min(y_hi, y_lo)
            local band_h = math.abs(y_lo - y_hi)
            gfx.set(line_r, line_g, line_b, 0.12)
            gfx.rect(plot_x, top, plot_w, math.max(1, band_h), 1)
        end

        -- Session cloud (teal, persists until the transport stops)
        gfx.set(DYN_CLOUD_R, DYN_CLOUD_G, DYN_CLOUD_B, 0.30)
        for i = 1, #dyn_cloud do
            local p = dyn_cloud[i]
            local px, py = to_px(p.mx, p.my)
            gfx.rect(px - 0.5, py - 0.5, 2, 2, 1)
        end

        -- Fading comet trail (fades out over DYN_TRAIL_FADE_SEC seconds)
        local n = #dyn_trail
        for i = 1, n do
            local p = dyn_trail[i]
            local age = now - p.t
            local t = math.max(0, 1 - age / DYN_TRAIL_FADE_SEC)
            local cr = sptr2_r + (sptr3_r - sptr2_r) * t
            local cg = sptr2_g + (sptr3_g - sptr2_g) * t
            local cb = sptr2_b + (sptr3_b - sptr2_b) * t
            gfx.set(cr, cg, cb, 0.10 + t * 0.75)
            local px, py = to_px(p.mx, p.my)
            local r = (1 + t * 2.5) * 0.5
            gfx.circle(px, py, r, 1, 1)
        end

        -- Live head (always on) + readout (hover only)
        if has_signal then
            local px, py = to_px(metric_val, short_lufs)
            gfx.set(1, 1, 1, 1)
            gfx.circle(px, py, 4, 1, 1)

            if is_hover then
                local info_text = string.format("%.1f LUFS   %s %.1f dB", short_lufs, metric_label, metric_val)
                gfx.setfont(1, "Arial", (base_title_size - 4) * g_font_scale)
                local tw, th = gfx.measurestr(info_text)
                local tx, ty = px + 8, py - th - 8
                if tx + tw > x + w then tx = px - tw - 8 end
                if ty < y then ty = py + 8 end

                gfx.set(bg_r, bg_g, bg_b, 0.9)
                gfx.rect(tx - 4, ty - 2, tw + 8, th + 4, 1)
                gfx.set(line_r, line_g, line_b, 0.5)
                gfx.rect(tx - 4, ty - 2, tw + 8, th + 4, 0)
                gfx.set(1, 1, 1, 1)
                gfx.x, gfx.y = tx, ty
                gfx.drawstr(info_text)
            end
        end

        gfx.setfont(1, "Arial", base_title_size * g_font_scale)
        gfx.set(line_r, line_g, line_b, line_a)
        gfx.x, gfx.y = title_x(x, y), y + 5
        gfx.drawstr("Dynamics")

        if loud_tgt or genre_tgt then
            gfx.setfont(1, "Arial", (base_title_size - 6) * g_font_scale)
            gfx.set(text_r, text_g, text_b, text_a * 0.7)
            local tag = (loud_tgt and loud_tgt.name or "") .. ((loud_tgt and genre_tgt) and " / " or "") .. (genre_tgt and genre_tgt.name or "")
            local tw = gfx.measurestr(tag)
            gfx.x, gfx.y = x + w - tw - 6, y + 5
            gfx.drawstr(tag)
            gfx.setfont(1, "Arial", base_title_size * g_font_scale)
        end
    end

----------------------------------------------------------
-- Functions: Color Setting
----------------------------------------------------------
    local MEM_BG    = 1000
    local MEM_LINE  = 1010
    local MEM_TEXT  = 1020
    local MEM_ZERO  = 1030
    local MEM_MID   = 1040
    local MEM_PEAK  = 1050
    local MEM_FREZ  = 1060
    local MEM_BASE_HUE = 1470
    local MEM_TINT = 1480
    local MEM_SYNC_CV = 1490
    local FOLLOW_HUE_BASE = 1510

    local SECTION = "TS_Visualizer"
    -- The shared palette. Hue and tint belong to the TS_ family rather
    -- than to any one tool, so they live in their own section; the old
    -- ChannelView-only location is still read when the new one is empty,
    -- so an existing setting survives. The Sync flag still decides
    -- whether Visualizer follows it at all -- this is only about WHERE
    -- the setting lives, not whether Visualizer is allowed to ignore it.
    local PAL_SECTION = "TS_Palette"
    local CV_SECTION = "TS_ChannelView"
    local function pal_read(k)
        local v = reaper.GetExtState(PAL_SECTION, k)
        if v == "" then v = reaper.GetExtState(CV_SECTION, k) end
        return v ~= "" and v or nil
    end

    ----------------------------------------------------------
    -- Colour engine
    --
    -- Same architecture as TS_ChannelView and TS_TrackAnalyser: every
    -- themed swatch is generated live from one absolute Hue (0-359) and
    -- one Tint (0.0-2.0), via role-based HSL offsets, instead of being
    -- individually hand-picked. "tint" roles are the furniture (bg, grid,
    -- text, the faint base of the signal fill) - greys that lean toward
    -- the base hue, scaled by Tint. "solid" roles are the two headline
    -- accent colours (the main signal colour and the peak/hold colour) -
    -- they follow the hue but stay at full saturation regardless of Tint,
    -- the same split TrackAnalyser draws between its furniture and its
    -- data colours.
    --
    -- Each swatch also has its own FOLLOW_HUE_BASE+n flag (set up in
    -- Initialize_System below) so any one of them can be unhooked from the
    -- palette and hand-picked again via its ColorEdit4 picker in the
    -- Editor - the same per-colour auto-follow idea as TrackAnalyser.
    -- build_palette() only ever touches a swatch whose flag is on.
    --
    -- The offset/saturation/lightness below reproduce TS_Visualizer's own
    -- previous default colours at Hue 219 / Tint 1.0 (and for bg, text,
    -- zero, mid, peak and frez, they exactly match the equivalent role
    -- already proven in TS_TrackAnalyser's own palette), so nothing looks
    -- different at the defaults. "grid" had accidentally been given the
    -- exact same colour as "text" (just less opaque) instead of its own
    -- role, so this gives it TrackAnalyser's real, distinct hue/sat/lum --
    -- but TrackAnalyser's grid role is always fully opaque (its own
    -- buildPalette() bakes every UI-role swatch, grid included, at alpha
    -- 0xff and gets its subtlety purely from a low lightness against the
    -- dark background, never from transparency); alpha 0.20 survived here
    -- from the "text, just less opaque" original, and against this dark a
    -- background that is faint enough to read as invisible -- worse, grid
    -- lines aren't the only thing drawn in this colour: every module
    -- title and axis label (Gonio/Symbiote/Scope/Spectrum/Spectrogram/
    -- Dynamics, the Gonio "-1"/"+1", the Spectrum's "100/1k/10k") is drawn
    -- with gfx.set(line_r, line_g, line_b, line_a) too, so the same faint
    -- alpha was quietly taking the grid's own text down with it. Matching
    -- TrackAnalyser's opaque grid fixes both at once.
    ----------------------------------------------------------
    local ROLE_NAMES = { "bg", "grid", "text", "zero", "mid", "peak", "frez" }
    local ROLE_PALETTE = {
        { mem = MEM_BG,   role = "tint",  dh =   -9.0, sat = 0.130, lum = 0.090, alpha = 1.00 },
        { mem = MEM_LINE, role = "tint",  dh =   -6.3, sat = 0.126, lum = 0.171, alpha = 1.00 },
        { mem = MEM_TEXT, role = "tint",  dh =   -9.0, sat = 0.083, lum = 0.576, alpha = 1.00 },
        { mem = MEM_ZERO, role = "tint",  dh =  -15.9, sat = 0.531, lum = 0.384, alpha = 0.10 },
        { mem = MEM_MID,  role = "solid", dh =  -16.4, sat = 0.526, lum = 0.545, alpha = 0.80 },
        { mem = MEM_PEAK, role = "solid", dh = -175.1, sat = 0.755, lum = 0.631, alpha = 1.00 },
        { mem = MEM_FREZ, role = "tint",  dh =   -9.0, sat = 0.078, lum = 0.451, alpha = 1.00 },
    }

    local function hsl_to_rgb(h, s, l)
        h = (h % 360) / 360
        s = math.max(0, math.min(1, s))
        l = math.max(0, math.min(1, l))
        local function hue2(p, q, t)
            if t < 0 then t = t + 1 elseif t > 1 then t = t - 1 end
            if t < 1/6 then return p + (q - p) * 6 * t end
            if t < 1/2 then return q end
            if t < 2/3 then return p + (q - p) * (2/3 - t) * 6 end
            return p
        end
        if s == 0 then return l, l, l end
        local q = (l < 0.5) and (l * (1 + s)) or (l + s - l * s)
        local p = 2 * l - q
        return hue2(p, q, h + 1/3), hue2(p, q, h), hue2(p, q, h - 1/3)
    end

    local function build_palette(base_hue, tint)
        for i, e in ipairs(ROLE_PALETTE) do
            if reaper.gmem_read(FOLLOW_HUE_BASE + i) ~= 0 then
                local sat = (e.role == "tint") and (e.sat * tint) or e.sat
                local r, g, b = hsl_to_rgb(base_hue + e.dh, sat, e.lum)
                reaper.gmem_write(e.mem,     r)
                reaper.gmem_write(e.mem + 1, g)
                reaper.gmem_write(e.mem + 2, b)
                reaper.gmem_write(e.mem + 3, e.alpha)
            end
        end
    end

    local function sync_and_build_palette()
        local base_hue, tint
        -- Live sync with the shared palette: read Hue/Tint straight out
        -- of ExtState every frame via pal_read() (TS_Palette, falling
        -- back to ChannelView's own section for an install that hasn't
        -- moved yet). It's already the same absolute 0-359 value used
        -- here, so no conversion is needed. Falls back to the manual
        -- Base Hue/Tint below if sync is off, or if nothing has written
        -- the shared palette yet.
        if reaper.gmem_read(MEM_SYNC_CV) ~= 0 and pal_read("base_hue") then
            base_hue = tonumber(pal_read("base_hue")) or reaper.gmem_read(MEM_BASE_HUE)
            tint     = tonumber(pal_read("tint")) or reaper.gmem_read(MEM_TINT)
            -- Mirror the resolved value back into the same slots the
            -- manual sliders read from. Without this the (disabled)
            -- Hue/Tint sliders in the Editor keep showing whatever the
            -- last manual value was instead of what's actually driving
            -- the palette, and turning Sync back off would resume
            -- editing from that stale value instead of the one you were
            -- just looking at.
            reaper.gmem_write(MEM_BASE_HUE, base_hue)
            reaper.gmem_write(MEM_TINT, tint)
        else
            base_hue = reaper.gmem_read(MEM_BASE_HUE)
            tint     = reaper.gmem_read(MEM_TINT)
        end
        -- No change-cache here on purpose: a follow-hue flag can flip in
        -- the Editor with base_hue/tint themselves unchanged, and that
        -- swatch still needs to be rebuilt on the very next frame. Seven
        -- cheap HSL conversions a frame is not worth the bug.
        build_palette(base_hue, tint)
    end

    function LoadSettingsFromExtState()
        for i = 1000, 1100 do
            local key = "MEM_" .. i
            if reaper.HasExtState(SECTION, key) then
                local val = tonumber(reaper.GetExtState(SECTION, key))
                reaper.gmem_write(i, val)
            end
        end

        if reaper.HasExtState(SECTION, "FontScale") then
            local val = tonumber(reaper.GetExtState(SECTION, "FontScale"))
            reaper.gmem_write(1300, val)
        end
        
        if reaper.HasExtState(SECTION, "ModuleOrder") then
            local order_str = reaper.GetExtState(SECTION, "ModuleOrder")
            local idx = 1
            for val in string.gmatch(order_str, '([^,]+)') do
                local n = tonumber(val)
                if n then
                    ui_order[idx] = n
                    reaper.gmem_write(1100 + idx, n)
                    idx = idx + 1
                end
            end
        end
    end

    function init_default_colors()
        -- Fresh-install bootstrap: nothing in gmem or ExtState yet, so the
        -- follow-hue flags haven't been written either. Force every
        -- swatch to follow just for this one call, so there's something
        -- to render before Initialize_System sets the real flags a
        -- moment later.
        for i = 1, 7 do reaper.gmem_write(FOLLOW_HUE_BASE + i, 1) end
        build_palette(219, 1.0)

        reaper.gmem_write(2, 0.5)
        reaper.gmem_write(6, 0.5) 
        reaper.gmem_write(7, 0.5) 
        reaper.gmem_write(8, 0.5) 
        reaper.gmem_write(9, 0.5) -- Waterfall Default
        reaper.gmem_write(1300, 1.0) 
        reaper.gmem_write(4, 1.0) 
        reaper.gmem_write(5, 1.0)
        
        for i=1, 7 do reaper.gmem_write(1100 + i, i) end
    end

    function update_settings_from_gmem()
        if reaper.gmem_read(1003) == 0 then
            LoadSettingsFromExtState()
            if reaper.gmem_read(1003) == 0 then
                init_default_colors()
            end
        end
            local att = reaper.gmem_read(4)
            local rel = reaper.gmem_read(5)
            if att > 0 then g_signal_attack = att else g_signal_attack = 1.0 end
            if rel > 0 then g_signal_release = rel else g_signal_release = 1.0 end

        if reaper.gmem_read(1100) > 0 then
            reaper.gmem_write(1100, 0)
        end
        if reaper.gmem_read(1000 + 3) == 0 then return end

            -- Colours for bg/grid/text/zero/mid/peak/frez are generated
            -- live from one Hue + one Tint (see the colour engine above),
            -- the same architecture as ChannelView and TrackAnalyser, so
            -- moving a slider (or syncing to the shared palette) re-themes
            -- everything in one shot. sync_and_build_palette() decides the
            -- effective hue/tint (the shared palette's live values when
            -- synced, the manual ones otherwise) and rebuilds every frame.
            sync_and_build_palette()

            bg_r = reaper.gmem_read(1000); bg_g = reaper.gmem_read(1001); bg_b = reaper.gmem_read(1002); bg_a = reaper.gmem_read(1003)
            line_r = reaper.gmem_read(1010); line_g = reaper.gmem_read(1011); line_b = reaper.gmem_read(1012); line_a = reaper.gmem_read(1013)
            text_r = reaper.gmem_read(1020); text_g = reaper.gmem_read(1021); text_b = reaper.gmem_read(1022); text_a = reaper.gmem_read(1023)

            local c1_r = reaper.gmem_read(1030); local c1_g = reaper.gmem_read(1031); local c1_b = reaper.gmem_read(1032); local c1_a = reaper.gmem_read(1033)
            local c2_r = reaper.gmem_read(1040); local c2_g = reaper.gmem_read(1041); local c2_b = reaper.gmem_read(1042); local c2_a = reaper.gmem_read(1043)
            local c3_r = reaper.gmem_read(1050); local c3_g = reaper.gmem_read(1051); local c3_b = reaper.gmem_read(1052); local c3_a = reaper.gmem_read(1053)
            local c4_r = reaper.gmem_read(1060); local c4_g = reaper.gmem_read(1061); local c4_b = reaper.gmem_read(1062); local c4_a = reaper.gmem_read(1063)

            dot1_r, dot1_g, dot1_b, dot1_a = c1_r, c1_g, c1_b, c1_a
            dot2_r, dot2_g, dot2_b, dot2_a = c2_r, c2_g, c2_b, c2_a
            dot3_r, dot3_g, dot3_b, dot3_a = c3_r, c3_g, c3_b, c3_a
            gr_peak, gg_peak, gb_peak      = c3_r, c3_g, c3_b 

            sym1_r, sym1_g, sym1_b, sym1_a = c1_r, c1_g, c1_b, c1_a
            sym2_r, sym2_g, sym2_b, sym2_a = c2_r, c2_g, c2_b, c2_a
            sym3_r, sym3_g, sym3_b, sym3_a = c3_r, c3_g, c3_b, c3_a

            scp1_r, scp1_g, scp1_b, scp1_a = c1_r, c1_g, c1_b, c1_a
            scp2_r, scp2_g, scp2_b, scp2_a = c2_r, c2_g, c2_b, c2_a
            scp3_r, scp3_g, scp3_b, scp3_a = c3_r, c3_g, c3_b, c3_a

            sptr1_r, sptr1_g, sptr1_b, sptr1_a = c1_r, c1_g, c1_b, c1_a
            sptr2_r, sptr2_g, sptr2_b, sptr2_a = c2_r, c2_g, c2_b, c2_a
            sptr3_r, sptr3_g, sptr3_b, sptr3_a = c3_r, c3_g, c3_b, c3_a
            peak_r, peak_g, peak_b, peak_a = c4_r, c4_g, c4_b, c4_a

            for i=1, 7 do
                local order_val = reaper.gmem_read(1100 + i)
                if order_val > 0 then ui_order[i] = order_val end
            end

            local scale_val = reaper.gmem_read(1300)
            if scale_val > 0 then 
                g_font_scale = scale_val 
            else
                g_font_scale = 1.0
            end
    end

    local function Initialize_System()
        local function load_color(mem_idx, ext_key)
            if reaper.HasExtState(SECTION, "MEM_"..mem_idx) then
                reaper.gmem_write(mem_idx, tonumber(reaper.GetExtState(SECTION, "MEM_"..mem_idx)))
                return true
            end
            return false
        end

        local loaded = load_color(1000, "MEM_1000")
        if reaper.gmem_read(1003) == 0 then
            reaper.gmem_write(2, 0.5)
            reaper.gmem_write(4, 1.0)
            reaper.gmem_write(5, 1.0)
            reaper.gmem_write(1300, 1.0)
        end

        -- Follow-hue flags: which of the 7 swatches are generated by
        -- build_palette() (from Base Hue/Tint, or the shared-palette
        -- sync) versus left alone as a hand-picked override. Same "load
        -- here too" rule as everything else on this list - default ON,
        -- stored per swatch, loaded before the display script can render
        -- rather than only in the Editor.
        for i = 1, 7 do
            local key = "FollowHue_" .. ROLE_NAMES[i]
            if reaper.HasExtState(SECTION, key) then
                reaper.gmem_write(FOLLOW_HUE_BASE + i, tonumber(reaper.GetExtState(SECTION, key)))
            else
                reaper.gmem_write(FOLLOW_HUE_BASE + i, 1)
            end
        end

        -- Base Hue / Tint: absolute values (0-359 / 0.0-2.0), the same
        -- convention ChannelView itself uses. Defaults to ChannelView's
        -- own default (219 / 1.0) so a fresh install lines up with it
        -- immediately, sync or no sync.
        if reaper.HasExtState(SECTION, "BaseHue") then
            reaper.gmem_write(MEM_BASE_HUE, tonumber(reaper.GetExtState(SECTION, "BaseHue")))
        else
            reaper.gmem_write(MEM_BASE_HUE, 219)
        end
        if reaper.HasExtState(SECTION, "Tint") then
            reaper.gmem_write(MEM_TINT, tonumber(reaper.GetExtState(SECTION, "Tint")))
        else
            reaper.gmem_write(MEM_TINT, 1.0)
        end

        -- Sync with the shared palette defaults ON (that's what was asked
        -- for), and - same class of bug as Base Hue/Tint just above - has
        -- to be loaded here too, not just in the Editor's LoadAllSettings,
        -- or a plain restart without the Editor open would silently drop
        -- back to manual/off.
        if reaper.HasExtState(SECTION, "SyncChannelView") then
            reaper.gmem_write(MEM_SYNC_CV, tonumber(reaper.GetExtState(SECTION, "SyncChannelView")))
        else
            reaper.gmem_write(MEM_SYNC_CV, 1)
        end

        if reaper.HasExtState(SECTION, "ModuleOrder") then
            local order_str = reaper.GetExtState(SECTION, "ModuleOrder")
            local idx = 1
            for val in string.gmatch(order_str, '([^,]+)') do
                reaper.gmem_write(1100 + idx, tonumber(val))
                idx = idx + 1
            end
        else
            for i=1, 7 do reaper.gmem_write(1100 + i, i) end
        end

        if reaper.HasExtState(SECTION, "ModuleActive") then
            local active_str = reaper.GetExtState(SECTION, "ModuleActive")
            local idx = 1
            for val in string.gmatch(active_str, '([^,]+)') do
                reaper.gmem_write(1150 + idx, (val == "1" and 1 or 0))
                idx = idx + 1
            end
        else
            for i=1, 7 do reaper.gmem_write(1150 + i, 1) end
        end

        -- Slope Guide / Spectrum Tilt: same class of bug as Pair Gonio +
        -- Symbiote above - the Editor only writes these into gmem while it's
        -- open, so a plain project/REAPER restart (with only this display
        -- script running) silently dropped them back to "Off".
        if reaper.HasExtState(SECTION, "SpectrumSlope") then
            reaper.gmem_write(1400, tonumber(reaper.GetExtState(SECTION, "SpectrumSlope")))
        end
        if reaper.HasExtState(SECTION, "SpectrumTilt") then
            reaper.gmem_write(1410, tonumber(reaper.GetExtState(SECTION, "SpectrumTilt")))
        end

        -- Build the palette once immediately, so the very first frame
        -- renders with the right colours instead of whatever was left in
        -- gmem from a previous run, before the main loop's own per-frame
        -- sync_and_build_palette() call takes over.
        sync_and_build_palette()
    end
    Initialize_System()

----------------------------------------------------------
-- UI Loops
----------------------------------------------------------
    local divider_drag = {
        active = false, mod_a = nil, mod_b = nil,
        axis_size = 0, total_ratio = 1, start_mouse = 0,
        start_a = 0, start_b = 0
    }
    local gear_was_down = false

    local function draw_settings_gear(cx, cy, r, alpha)
        local teeth = 8
        gfx.set(line_r, line_g, line_b, alpha)
        for i = 0, teeth - 1 do
            local a1 = (i / teeth) * 2 * math.pi
            local a2 = a1 + (math.pi / teeth) * 0.55
            local x1, y1 = cx + math.cos(a1) * r,       cy + math.sin(a1) * r
            local x2, y2 = cx + math.cos(a1) * r * 1.5, cy + math.sin(a1) * r * 1.5
            local x3, y3 = cx + math.cos(a2) * r * 1.5, cy + math.sin(a2) * r * 1.5
            local x4, y4 = cx + math.cos(a2) * r,       cy + math.sin(a2) * r
            gfx.triangle(x1, y1, x2, y2, x3, y3, x4, y4)
        end
        gfx.circle(cx, cy, r, 1, 1)
        gfx.set(bg_r, bg_g, bg_b, 1)
        gfx.circle(cx, cy, r * 0.42, 1, 1)
    end

    local function launch_editor_script()
        -- Derived from this script's own path rather than spelled out
        -- under GetResourcePath(), so renaming or moving the folder
        -- doesn't leave the gear icon pointing at a file that no longer
        -- exists. (This is exactly what broke it: the Editor was renamed
        -- to TS_Visualizer_Editor.lua and this path wasn't updated to
        -- match, so AddRemoveReaScript silently failed to find it.)
        local here = debug.getinfo(1, "S").source:match("@?(.*[\\/])") or ""
        local editor_path = here .. "TS_Visualizer_Editor.lua"
        local cmd_id = reaper.AddRemoveReaScript(true, 0, editor_path, true)
        if cmd_id and cmd_id ~= 0 then
            reaper.Main_OnCommand(cmd_id, 0)
        end
    end

    ----------------------------------------------------------
    -- Track swatches -- picking which tracks feed the Spectrum panel's
    -- dominant-colour overlay used to mean opening the Editor, then (for
    -- one session) a strip down the right edge of the whole window. It
    -- draws inside the Spectrum panel itself now, since that is the only
    -- place this selection actually does anything: a strip of colour
    -- swatches on the panel's own right edge, one per eligible track (any
    -- TS_TrackProbe with "Include in Visualizer Spectrum" ticked -- see
    -- find_probe_fx above), the stack centred vertically in the panel's
    -- height rather than pinned to its top. Click a swatch to toggle it
    -- in or out. Selection itself is unchanged: the same project ExtState
    -- CSV poll_folder_overlay already reads.
    --
    -- Each track's name is drawn beside its own swatch full-time, not as
    -- a hover-only tooltip: with one swatch per eligible track this reads
    -- as a small legend rather than clutter, and it was the simpler fix
    -- for a real problem the tooltip version had -- the Spectrum panel's
    -- own cursor-following frequency tooltip lands in roughly the same
    -- spot while hovering the strip (it flips to the left of the cursor
    -- whenever it would run off the window's right edge, which is exactly
    -- what happens here), and would cover a tooltip but not a label that's
    -- already sitting there before the cursor arrives.
    ----------------------------------------------------------
    local SWATCH_STRIP_W = 20
    local SWATCH_SIZE = 14
    local SWATCH_GAP = 5
    local SWATCH_RIGHT_MARGIN = 8 -- clears the panel's own right edge
    local SWATCH_LABEL_GAP = 6 -- between a swatch and its name

    local function get_selected_track_guids()
        local _, csv = reaper.GetProjExtState(0, "TS_Visualizer", "FolderOverlayGUIDs")
        local set, ordered = {}, {}
        for g in csv:gmatch("[^,]+") do
            if not set[g] then set[g] = true; ordered[#ordered + 1] = g end
        end
        return set, ordered
    end

    local function set_selected_track_guids(ordered)
        reaper.SetProjExtState(0, "TS_Visualizer", "FolderOverlayGUIDs", table.concat(ordered, ","))
    end

    -- Walking every track's FX chain to check for a probe is a project
    -- scan, same reasoning as poll_folder_overlay's own throttle -- not
    -- something worth doing every one of 45 frames a second.
    local swatch_tracks, swatch_tracks_polled = {}, -1
    local function refresh_swatch_tracks()
        local now = reaper.time_precise()
        if now - swatch_tracks_polled < 1.0 then return end
        swatch_tracks_polled = now
        swatch_tracks = {}
        local count = reaper.CountTracks(0)
        for i = 0, count - 1 do
            local tr = reaper.GetTrack(0, i)
            local fx_idx = find_probe_fx(tr)
            if fx_idx then
                local _, name = reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", "", false)
                if not name or name == "" then name = ("Track %d"):format(i + 1) end
                local _, guid = reaper.GetSetMediaTrackInfo_String(tr, "GUID", "", false)
                local r, g, b = 0.55, 0.55, 0.55
                local native = reaper.GetTrackColor(tr)
                if native ~= 0 then
                    local rr, gg, bb = reaper.ColorFromNative(native)
                    r, g, b = rr / 255, gg / 255, bb / 255
                end
                swatch_tracks[#swatch_tracks + 1] = { name = name, guid = guid, r = r, g = g, b = b }
            end
        end
    end

    -- Called from draw_spectrum with that panel's own (x, y, w, h): draws
    -- into a strip on its right edge rather than reserving space from the
    -- module grid, so it overlays the trace the same way the grid lines
    -- and peak line already do.
    -- Global, not local: draw_spectrum (itself a plain global, defined
    -- earlier in the file, not in dependency order -- see the note on
    -- that pattern near folder_overlay above) calls this by name, and a
    -- local declared this far down the file would not be a visible
    -- upvalue there.
    local swatch_mouse_was_down = false
    function draw_track_swatches(x, y, w, h)
        refresh_swatch_tracks()
        if #swatch_tracks == 0 then return end

        local sx = x + w - SWATCH_STRIP_W - SWATCH_RIGHT_MARGIN

        local selected_set, selected_ordered = get_selected_track_guids()

        local mouse_down = (gfx.mouse_cap & 1 == 1)
        local click_edge = mouse_down and not swatch_mouse_was_down
        swatch_mouse_was_down = mouse_down

        -- Centred as a block within the panel's height, not pinned to the
        -- top -- if there isn't room to centre (more tracks than the
        -- panel is tall), fall back to starting at the top rather than
        -- running off it in both directions.
        local stack_h = #swatch_tracks * SWATCH_SIZE + (#swatch_tracks - 1) * SWATCH_GAP
        local yy = y + math.max(4, math.floor((h - stack_h) / 2))

        gfx.setfont(1, "Arial", 13 * g_font_scale)

        for _, t in ipairs(swatch_tracks) do
            if yy + SWATCH_SIZE > y + h - 4 then break end -- out of room; simplest overflow for now
            local qx = sx + math.floor((SWATCH_STRIP_W - SWATCH_SIZE) / 2)
            local qy = yy
            local hovered = gfx.mouse_x >= qx and gfx.mouse_x <= qx + SWATCH_SIZE and
                             gfx.mouse_y >= qy and gfx.mouse_y <= qy + SWATCH_SIZE
            local is_sel = selected_set[t.guid] == true

            if is_sel or hovered then
                gfx.set(1, 1, 1, is_sel and 0.9 or 0.45)
                gfx.rect(qx - 2, qy - 2, SWATCH_SIZE + 4, SWATCH_SIZE + 4)
            end
            gfx.set(t.r, t.g, t.b, is_sel and 1.0 or 0.55)
            gfx.rect(qx, qy, SWATCH_SIZE, SWATCH_SIZE)

            -- Full-time label, right-aligned against its own swatch so
            -- names of different lengths don't shift the swatch column.
            local tw, th = gfx.measurestr(t.name)
            local tx = qx - SWATCH_LABEL_GAP - tw
            local ty = qy + math.floor((SWATCH_SIZE - th) / 2)
            gfx.set(1, 1, 1, is_sel and 0.95 or 0.6)
            gfx.x, gfx.y = tx, ty
            gfx.drawstr(t.name)

            if hovered and click_edge then
                if is_sel then
                    for j = #selected_ordered, 1, -1 do
                        if selected_ordered[j] == t.guid then table.remove(selected_ordered, j) end
                    end
                else
                    selected_ordered[#selected_ordered + 1] = t.guid
                end
                set_selected_track_guids(selected_ordered)
            end

            yy = yy + SWATCH_SIZE + SWATCH_GAP
        end
    end

    -- Loudness/Genre Target: two-tier persistence, same idea as every
    -- other Visualizer setting (colours, font, module order...) except
    -- those only ever need the one global tier. A per-project value in
    -- project ExtState (set from the Editor's sliders, travels with the
    -- song) wins when present; otherwise this falls back to the plain
    -- global ExtState default (reaper.ini) the Editor also writes on every
    -- change, so a brand-new project starts from the target you last used
    -- instead of always resetting to "Off". Re-asserted into gmem every
    -- frame so nothing can stomp it back to a stale value.
    local function sync_targets_from_project()
        local ok_l, val_l = reaper.GetProjExtState(0, "TS_Visualizer", "LoudnessTarget")
        if ok_l == 0 or val_l == "" then
            val_l = reaper.HasExtState("TS_Visualizer", "LoudnessTarget")
                and reaper.GetExtState("TS_Visualizer", "LoudnessTarget") or nil
        end
        if val_l then
            local n = tonumber(val_l)
            if n then reaper.gmem_write(25, n) end
        end
        local ok_g, val_g = reaper.GetProjExtState(0, "TS_Visualizer", "GenreTarget")
        if ok_g == 0 or val_g == "" then
            val_g = reaper.HasExtState("TS_Visualizer", "GenreTarget")
                and reaper.GetExtState("TS_Visualizer", "GenreTarget") or nil
        end
        if val_g then
            local n = tonumber(val_g)
            if n then reaper.gmem_write(26, n) end
        end
        poll_folder_overlay()
    end
    local last_signal_time = reaper.time_precise()
    local g_is_standby = false
    local target_fps = 45
    local frame_interval = 1.0 / target_fps
    local last_frame_time = reaper.time_precise()

    function run()
        local char = gfx.getchar()
        if char == 27 then return end 
        if char == 32 then
            reaper.Main_OnCommand(40044, 0) 
        end

        local current_time = reaper.time_precise()
        if (current_time - last_frame_time) < frame_interval then
            reaper.defer(run)
            return
        end
        last_frame_time = current_time

        sync_targets_from_project()

        update_settings_from_gmem()

        if gfx.mouse_cap == 2 then 
            gfx.x, gfx.y = gfx.mouse_x, gfx.mouse_y
            
            local current_dock_state = gfx.dock(-1) 
            local is_docked = current_dock_state > 0
            local is_vertical_menu = (reaper.gmem_read(1450) == 1)
            
            local menu_str = (is_docked and "!" or "") .. "Dock to Docker|"
            menu_str = menu_str .. (is_vertical_menu and "!" or "") .. "Vertical Layout|"
            menu_str = menu_str .. "Reset Panel Sizes|"
            menu_str = menu_str .. "Open Settings...|"
            menu_str = menu_str .. "#For editing theme, run 'TS_Visualizer Editor' from Action List"

            local selection = gfx.showmenu(menu_str)

            if selection == 1 then
                if is_docked then gfx.dock(0) else gfx.dock(513) end
            elseif selection == 2 then
                local new_orientation = is_vertical_menu and 0 or 1
                reaper.gmem_write(1450, new_orientation)
                reaper.SetExtState("TS_Visualizer", "Orientation", tostring(new_orientation), true)
            elseif selection == 3 then
                for i = 1, 7 do
                    reaper.gmem_write(1500 + i, 0)
                    reaper.DeleteExtState("TS_Visualizer", "ModSize_"..i, true)
                end
            elseif selection == 4 then
                launch_editor_script()
            end
        end

        local wheel_val = gfx.mouse_wheel
        gfx.mouse_wheel = 0

        if wheel_val ~= 0 and gfx.mouse_y < 30 then
            local sensitivity = 0.02
            local change = (wheel_val / 120) * sensitivity 
            if math.abs(change) < 0.01 then change = (wheel_val > 0) and 0.02 or -0.02 end
            
            local target_gmems = {2, 6, 7, 8, 9}
            for _, mem in ipairs(target_gmems) do
                local current_gain = reaper.gmem_read(mem)
                current_gain = math.max(0.0, math.min(1.0, current_gain + change))
                reaper.gmem_write(mem, current_gain)
            end
        end

        local current_time = reaper.time_precise()
        local mom_val = reaper.gmem_read(20)
        local is_mouse_in = (gfx.mouse_x >= 0 and gfx.mouse_x <= gfx.w and gfx.mouse_y >= 0 and gfx.mouse_y <= gfx.h)
        
        if mom_val > -100 or is_mouse_in then
            last_signal_time = current_time
        end
        
        g_is_standby = (current_time - last_signal_time) > 2.0

        gfx.set(bg_r, bg_g, bg_b, bg_a)
        gfx.rect(0, 0, gfx.w, gfx.h)

        -- Default ratio for the 7 modules (Horizontal: width ratio / Vertical: height ratio)
        local module_widths = {
            [1] = 0.10, [2] = 0.12, [3] = 0.12, [4] = 0.12, [5] = 0.39, [6] = 0.15, [7] = 0.20
        }

        local orientation = reaper.gmem_read(1450)
        local is_vertical = (orientation == 1)

        -- Pairs of modules that share one row side by side, instead of each
        -- getting its own full-width row. Only meaningful in Vertical layout
        -- (in Horizontal layout modules already sit side by side), and only
        -- takes effect when the two are adjacent in the module order - flip
        -- their order in the Editor's Module Order list to swap which one
        -- lands on the left vs the right.
        local active_pairs = {}
        if is_vertical then
            if reaper.gmem_read(1460) == 1 then active_pairs[#active_pairs + 1] = { 2, 3 } end -- Gonio + Symbiote
            if reaper.gmem_read(1465) == 1 then active_pairs[#active_pairs + 1] = { 1, 7 } end -- LUFS + Dynamics
        end
        local function find_pair(mod_id)
            for _, p in ipairs(active_pairs) do
                if p[1] == mod_id or p[2] == mod_id then return p end
            end
            return nil
        end

        local module_sizes = {}
        for i = 1, 7 do
            local custom_size = reaper.gmem_read(1500 + i)
            module_sizes[i] = (custom_size > 0) and custom_size or module_widths[i]
        end

        -- Build the draw sequence: normally one group per active module, but
        -- when a pairing applies, the two modules are merged into a single
        -- group that shares one row (split side by side when drawn).
        local groups = {}
        do
            local i = 1
            while i <= 7 do
                local mod_id = ui_order[i]
                local is_active = (reaper.gmem_read(1150 + mod_id) == 1)
                if not is_active then
                    i = i + 1
                else
                    local paired = false
                    if i < 7 then
                        local pair = find_pair(mod_id)
                        if pair then
                            local other_id = (pair[1] == mod_id) and pair[2] or pair[1]
                            local next_id = ui_order[i + 1]
                            local next_active = (reaper.gmem_read(1150 + next_id) == 1)
                            if next_id == other_id and next_active then
                                groups[#groups + 1] = { mod_id, next_id }
                                i = i + 2
                                paired = true
                            end
                        end
                    end
                    if not paired then
                        groups[#groups + 1] = { mod_id }
                        i = i + 1
                    end
                end
            end
        end
        local group_count = #groups

        local total_active_ratio = 0
        for gi = 1, group_count do
            total_active_ratio = total_active_ratio + module_sizes[groups[gi][1]]
        end
        if total_active_ratio == 0 then total_active_ratio = 1 end

        local axis_total = is_vertical and gfx.h or gfx.w
        local DIVIDER_HIT = 4
        local mouse_down = (gfx.mouse_cap & 1 == 1)

        local current_x, current_y = 0, 0
        local prev_group = nil
        local s2 = reaper.gmem_read(3)

        -- Dividers are drawn in a separate pass AFTER every module's own
        -- content below, not inline here as each group is laid out.
        -- Several modules (the Spectrogram's waterfall blit, the Dynamics
        -- panel's own background, LUFS's) paint a solid rect starting
        -- right at their own edge -- which is exactly where a divider
        -- drawn inline, before that content, would sit, so that content
        -- was silently painting over its own top/left divider every
        -- frame. Collecting the lines here and drawing them all after
        -- the loop guarantees they're the topmost thing on screen
        -- regardless of what any one module fills.
        local pending_dividers = {}

        for gi = 1, group_count do
            local group_ids = groups[gi]
            local primary_id = group_ids[1]

            local ratio = module_sizes[primary_id] / total_active_ratio
            local w, h, draw_x, draw_y

            if is_vertical then
                w = gfx.w
                h = math.floor(gfx.h * ratio)
                if gi == group_count then h = gfx.h - current_y end
                draw_x, draw_y = 0, current_y
            else
                w = math.floor(gfx.w * ratio)
                if gi == group_count then w = gfx.w - current_x end
                h = gfx.h
                draw_x, draw_y = current_x, 0
            end

            -- Divider (only exists between this group and the previous one)
            if prev_group then
                local prev_primary = prev_group[1]
                local boundary_pos = is_vertical and draw_y or draw_x
                local near_boundary
                if is_vertical then
                    near_boundary = (gfx.mouse_y >= boundary_pos - DIVIDER_HIT and gfx.mouse_y <= boundary_pos + DIVIDER_HIT
                                     and gfx.mouse_x >= 0 and gfx.mouse_x <= gfx.w)
                else
                    near_boundary = (gfx.mouse_x >= boundary_pos - DIVIDER_HIT and gfx.mouse_x <= boundary_pos + DIVIDER_HIT
                                     and gfx.mouse_y >= 0 and gfx.mouse_y <= gfx.h)
                end

                if not divider_drag.active and near_boundary and mouse_down then
                    divider_drag.active = true
                    divider_drag.mod_a = prev_primary
                    divider_drag.mod_b = primary_id
                    divider_drag.axis_size = axis_total
                    divider_drag.total_ratio = total_active_ratio
                    divider_drag.start_mouse = is_vertical and gfx.mouse_y or gfx.mouse_x
                    divider_drag.start_a = module_sizes[prev_primary]
                    divider_drag.start_b = module_sizes[primary_id]
                end

                local is_this_divider_active = divider_drag.active and divider_drag.mod_a == prev_primary and divider_drag.mod_b == primary_id
                local dr, dg, db, da
                if near_boundary or is_this_divider_active then
                    dr, dg, db, da = sptr2_r, sptr2_g, sptr2_b, 0.6
                else
                    -- Text colour, not grid: grid's own low lightness (by
                    -- design, for subtlety against a near-black panel
                    -- background) all but disappears against a bright,
                    -- saturated panel fill like the Spectrum's -- which is
                    -- exactly the boundary most likely to need a visible
                    -- divider. Text is lit enough to read against either.
                    dr, dg, db, da = text_r, text_g, text_b, 0.35
                end
                if is_vertical then
                    pending_dividers[#pending_dividers + 1] =
                        { r = dr, g = dg, b = db, a = da, x1 = draw_x, y1 = draw_y, x2 = draw_x + w, y2 = draw_y }
                else
                    pending_dividers[#pending_dividers + 1] =
                        { r = dr, g = dg, b = db, a = da, x1 = draw_x, y1 = draw_y, x2 = draw_x, y2 = draw_y + h }
                end
            end

            -- A single-module group draws full-rect as before; a paired
            -- group splits its rect side by side (50/50).
            local sub_rects
            if #group_ids == 1 then
                sub_rects = { { id = group_ids[1], x = draw_x, y = draw_y, w = w, h = h } }
            else
                local half = math.floor(w / 2)
                sub_rects = {
                    { id = group_ids[1], x = draw_x, y = draw_y, w = half, h = h },
                    { id = group_ids[2], x = draw_x + half, y = draw_y, w = w - half, h = h },
                }
            end

            for si = 1, #sub_rects do
                local sub = sub_rects[si]
                local mod_id = sub.id
                local sx, sy, sw, sh = sub.x, sub.y, sub.w, sub.h

                if #sub_rects == 2 and si == 2 then
                    -- Internal split line between the two paired modules --
                    -- queued like the inter-group dividers above, for the
                    -- same reason: whichever of the two modules draws
                    -- second (si == 2, drawn below) would otherwise paint
                    -- its own background right over a line drawn here now.
                    pending_dividers[#pending_dividers + 1] =
                        { r = text_r, g = text_g, b = text_b, a = 0.35, x1 = sx, y1 = sy, x2 = sx, y2 = sy + sh }
                end

                if wheel_val ~= 0 and gfx.mouse_y >= 30 and gfx.mouse_x >= sx and gfx.mouse_x <= sx + sw and gfx.mouse_y >= sy and gfx.mouse_y <= sy + sh then
                    local target_gmem = nil
                    if mod_id == 2 then target_gmem = 2
                    elseif mod_id == 3 then target_gmem = 6
                    elseif mod_id == 4 then target_gmem = 7
                    elseif mod_id == 5 then target_gmem = 8
                    elseif mod_id == 6 then target_gmem = 9
                    end

                    if target_gmem then
                        local current_gain = reaper.gmem_read(target_gmem)
                        local sensitivity = 0.02
                        local change = (wheel_val / 120) * sensitivity
                        if math.abs(change) < 0.01 then change = (wheel_val > 0) and 0.02 or -0.02 end

                        current_gain = math.max(0.0, math.min(1.0, current_gain + change))
                        reaper.gmem_write(target_gmem, current_gain)
                    end
                end

                local mod_raw_gain = 0.5
                if mod_id == 2 then mod_raw_gain = reaper.gmem_read(2)
                elseif mod_id == 3 then mod_raw_gain = reaper.gmem_read(6)
                elseif mod_id == 4 then mod_raw_gain = reaper.gmem_read(7)
                elseif mod_id == 5 then mod_raw_gain = reaper.gmem_read(8)
                elseif mod_id == 6 then mod_raw_gain = reaper.gmem_read(9)
                end

                local specific_gain = g_gain_min + (g_gain_max - g_gain_min) * mod_raw_gain
                local specific_zoom = s_zoom_min + (s_zoom_max - s_zoom_min) * mod_raw_gain
                local specific_ceil = spec_ceil_min + (spec_ceil_max - spec_ceil_min) * mod_raw_gain
                local floor = spec_floor_min + (spec_floor_max - spec_floor_min) * s2

                if mod_id == 1 then
                    -- Momentary/Short-term normally sit side by side when
                    -- LUFS has a full-width row (Vertical layout) and
                    -- stacked when it has a narrow column (Horizontal
                    -- layout, or paired with Dynamics sharing a half-width
                    -- row in Vertical layout - same shape, same fix).
                    local lufs_stack_horizontal = is_vertical and #sub_rects == 1
                    draw_lufs(sx, sy, sw, sh, lufs_stack_horizontal)
                elseif mod_id == 2 then draw_gonio(sx, sy, sw, sh, specific_gain)
                elseif mod_id == 3 then draw_symbiote(sx, sy, sw, sh, specific_gain)
                elseif mod_id == 4 then draw_scope(sx, sy, sw, sh, specific_zoom)
                elseif mod_id == 5 then draw_spectrum(sx, sy, sw, sh, specific_ceil, floor)
                elseif mod_id == 6 then draw_spectrogram(sx, sy, sw, sh, mod_raw_gain, floor)
                elseif mod_id == 7 then draw_dynamics(sx, sy, sw, sh)
                end
            end

            if is_vertical then current_y = current_y + h else current_x = current_x + w end
            prev_group = group_ids
        end

        -- Drawn last, on top of every module's own content -- see the
        -- note by pending_dividers' declaration above.
        for _, d in ipairs(pending_dividers) do
            gfx.set(d.r, d.g, d.b, d.a)
            gfx.line(d.x1, d.y1, d.x2, d.y2)
        end

        -- Apply / persist divider drag
        if divider_drag.active then
            if mouse_down then
                local cur_mouse = is_vertical and gfx.mouse_y or gfx.mouse_x
                local delta_px = cur_mouse - divider_drag.start_mouse
                local delta_ratio = delta_px * divider_drag.total_ratio / divider_drag.axis_size
                local MIN_RATIO = 0.03
                local pair_sum = divider_drag.start_a + divider_drag.start_b
                local new_a = divider_drag.start_a + delta_ratio
                new_a = math.max(MIN_RATIO, math.min(pair_sum - MIN_RATIO, new_a))
                local new_b = pair_sum - new_a
                reaper.gmem_write(1500 + divider_drag.mod_a, new_a)
                reaper.gmem_write(1500 + divider_drag.mod_b, new_b)
            else
                local final_a = reaper.gmem_read(1500 + divider_drag.mod_a)
                local final_b = reaper.gmem_read(1500 + divider_drag.mod_b)
                reaper.SetExtState("TS_Visualizer", "ModSize_"..divider_drag.mod_a, tostring(final_a), true)
                reaper.SetExtState("TS_Visualizer", "ModSize_"..divider_drag.mod_b, tostring(final_b), true)
                divider_drag.active = false
            end
        end

        -- Settings gear icon (top-left corner, in both orientations) -> opens the Editor script
        local gear_r = 8
        local gear_cx, gear_cy = gear_r + 10, gear_r + 10
        local gear_hover = (gfx.mouse_x >= gear_cx - gear_r * 1.6 and gfx.mouse_x <= gear_cx + gear_r * 1.6 and
                             gfx.mouse_y >= gear_cy - gear_r * 1.6 and gfx.mouse_y <= gear_cy + gear_r * 1.6)
        draw_settings_gear(gear_cx, gear_cy, gear_r, gear_hover and 0.9 or 0.35)

        local gear_mouse_down = (gfx.mouse_cap & 1 == 1)
        if gear_hover and gear_mouse_down and not gear_was_down then
            launch_editor_script()
        end
        gear_was_down = gear_mouse_down

        gfx.update()
        reaper.defer(run)
    end

    local function exit_cleanup()
        local current_dock = gfx.dock(-1)
        reaper.SetExtState("TS_Visualizer", "DockState", tostring(current_dock), true)
        -- Don't leave a probe armed and publishing after the panel that
        -- was reading it has gone -- the selection itself (the ExtState
        -- key) survives, so it's back next time this reopens.
        disarm_folder_overlay()
    end

reaper.atexit(exit_cleanup)
run()
