--========================================================
-- @title TS_Visualizer Editor
-- @description TS_Visualizer Editor
-- @author Tim Shadgett (with Claude) -- fork of JKK_Visualizer by Junki Kim
-- @noindex
-- Not a package of its own: installed by TS_Visualizer.lua's @provides.
--========================================================

local ctx = reaper.ImGui_CreateContext('TS_Visualizer Editor')
local font_11 = reaper.ImGui_CreateFont('Arial', 11)
local font_12 = reaper.ImGui_CreateFont('Arial', 12)
local font_13 = reaper.ImGui_CreateFont('Arial', 13)
reaper.ImGui_Attach(ctx, font_11)
reaper.ImGui_Attach(ctx, font_12)
reaper.ImGui_Attach(ctx, font_13)

-- Assets sit beside this script. Derived from the script's own path rather
-- than spelled out under GetResourcePath(), so renaming or moving the
-- folder does not leave the editor with a stock theme.
local here       = debug.getinfo(1, "S").source:match("@?(.*[\\/])") or ""
local theme_path = here .. "TS_Theme.lua"
local ApplyTheme = (reaper.file_exists(theme_path) and dofile(theme_path).ApplyTheme) 
                   or function(ctx) return 0, 0 end

-- Memory Address 
    options = reaper.gmem_attach('TS_Visualizer_Mem')
    local MEM_GAIN_GONIO    = 2
    local MEM_GAIN_SYMBIOTE = 6
    local MEM_GAIN_SCOPE    = 7
    local MEM_GAIN_SPECTRUM = 8
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
    local ROLE_NAMES = { "bg", "grid", "text", "zero", "mid", "peak", "frez" }
    local MEM_SPECTRUM_SLOPE = 1400
    local MEM_SPECTRUM_TILT = 1410
    local MEM_ORIENTATION = 1450
    local MEM_PAIR_GONIO_SYMBIOTE = 1460
    local MEM_PAIR_LUFS_DYN = 1465
    local MEM_MOD_SIZE = 1500
    local MEM_LOUDNESS_TARGET = 25 -- JSFX slider6 (project-persistent via FX chain)
    local MEM_GENRE_TARGET    = 26 -- JSFX slider7 (project-persistent via FX chain)
    local ui_order  = {1, 2, 3, 4, 5, 6, 7}
    local ui_active = {true, true, true, true, true, true, true}

    -- Folder Spectrum Overlay's picker (which tracks feed the Spectrum
    -- panel's dominant-colour overlay) used to live here as a checkbox
    -- list. It moved to the main window itself -- a strip of colour
    -- swatches down its right edge, hover for the name, click to toggle
    -- -- so picking tracks doesn't need this settings window open. See
    -- draw_track_sidebar in TS_Visualizer.lua. This window never held any
    -- state for it beyond the project ExtState CSV both scripts read/
    -- write, so nothing else here needed to change.

----------------------------------------------------------
-- UI Info Description
----------------------------------------------------------
    local widget_descriptions = {
        ["GAIN"]    = { "Signal Gain",      "Adjusts the visual sensitivity of the visualizer." },
        ["GAIN_GONIO"]    = { "Gonio Gain",    "Adjusts the visual sensitivity of the Goniometer." },
        ["GAIN_SYMBIOTE"] = { "Symbiote Gain", "Adjusts the visual sensitivity of the Symbiote." },
        ["GAIN_SCOPE"]    = { "Scope Gain",    "Adjusts the visual sensitivity of the Scope." },
        ["GAIN_SPECTRUM"] = { "Spectrum Gain", "Adjusts the visual sensitivity of the Spectrum." },
        ["FONT"]    = { "Font Scale",       "Adjusts the size of all text at the same ratio." },
        ["ATTACK"]  = { "Response Speed (Attack)", "Adjusts how quickly the visualizer reacts to signals." },
        ["RELEASE"] = { "Decay Speed (Release)", "Adjusts how quickly the visualizer fades out." },
        ["ORDER"]   = { "Module Order",     "Drag and drop items to change the display order of the visualizer modules." },
        ["BG"]      = { "Background",       "Follows the Hue/Tint palette below by default. Untick \"Follow\" to hand-pick it instead." },
        ["LINE"]    = { "Grid & Lines",     "Follows the Hue/Tint palette below by default. Untick \"Follow\" to hand-pick it instead." },
        ["TEXT"]    = { "Text & Labels",    "Follows the Hue/Tint palette below by default. Untick \"Follow\" to hand-pick it instead." },
        ["ZERO"]    = { "Weak Signal",      "Follows the Hue/Tint palette below by default. Untick \"Follow\" to hand-pick it instead." },
        ["MID"]     = { "Normal Signal",    "Follows the Hue/Tint palette below by default. Untick \"Follow\" to hand-pick it instead." },
        ["PEAK"]    = { "Strong Signal",    "Follows the Hue/Tint palette below by default. Untick \"Follow\" to hand-pick it instead." },
        ["FREZ"]    = { "Peak Line",        "Follows the Hue/Tint palette below by default. Untick \"Follow\" to hand-pick it instead." },
        ["RESET"]   = { "Reset",            "Resets the color settings to default." },
        ["BASE_HUE"] = { "Hue", "The base hue (0-359\xc2\xb0) that every swatch still following the palette is generated from - the same knob ChannelView and TrackAnalyser use. 219\xc2\xb0 is the shared default." },
        ["TINT"]     = { "Tint", "How far the furniture swatches (background, grid, text, weak signal, peak line) lean toward the base hue. 1.0 is the designed default; 0 is true grey. The two accent colours (Normal/Strong Signal) ignore Tint and stay fully saturated." },
        ["HUE_SAT_RESET"] = { "Reset Hue/Tint", "Sets Hue back to 219\xc2\xb0 and Tint back to 1.0." },
        ["SYNC_CV"] = { "Sync Colour with ChannelView", "When on, Hue and Tint are driven live from the shared TS_Palette (whichever TS_ tool last set it, ChannelView included) instead of the sliders below, and stay matched automatically as that colour changes. Turn off to set Hue/Tint independently again." },
        ["FOLLOW"]  = { "Follow Hue/Tint", "When on, this swatch is generated from the Hue/Tint palette above (or from the shared palette, when synced) and its colour picker is disabled. Untick to hand-pick this one colour and leave the rest of the palette alone." },
        ["SLOPE"]   = { "Spectrum Slope Guide", "Overlays a reference dB/octave slope line on the Spectrum panel, pivoting through your cursor, while hovering." },
        ["TILT"]    = { "Spectrum Tilt", "Shifts the displayed spectrum by a constant dB/octave amount (about 1kHz). Broadband material with a matching natural rolloff will read flat instead of sloping down to the right." },
        ["ORIENTATION"] = { "Layout Orientation", "Switches the panel layout between side-by-side (Horizontal) and stacked (Vertical). Drag the dividers between panels in the main visualizer to resize them." },
        ["PAIR_GS"] = { "Pair Gonio + Symbiote", "In Vertical layout, draws the Gonio and Symbiote modules side by side in one shared row instead of each taking a full-width row. Only takes effect if they're next to each other in the module order below." },
        ["PAIR_LD"] = { "Pair LUFS + Dynamics", "In Vertical layout, draws the LUFS and Dynamics modules side by side in one shared row instead of each taking a full-width row, and stacks LUFS's Momentary/Short-term readouts vertically to fit the narrower space. Only takes effect if they're next to each other in the module order below; drag LUFS above or below Dynamics there to choose which side it sits on." },
        ["RESET_SIZES"] = { "Reset Panel Sizes", "Restores all panels to their default proportions." },
        ["RUN_STARTUP"] = { "Run at REAPER Startup", "Adds TS_Visualizer to REAPER's Scripts/__startup.lua so it launches automatically every time REAPER opens. Only ever adds or removes its own clearly-marked block, and backs up __startup.lua first. If it's already set to run at startup some other way, that's reported here and left alone rather than duplicated." },
        ["LOUD_TARGET"] = { "Loudness Target", "Sets a reference loudness target shown as a band on the Dynamics panel (target +/- 2.5 LUFS). Saved with the project, so it travels with the song, and also remembered as your default for new projects." },
        ["GENRE_TARGET"] = { "Genre/Dynamics Target", "Sets an illustrative genre dynamics-range band shown on the Dynamics panel. Saved with the project, so it travels with the song, and also remembered as your default for new projects." },
        ["FOLDER_OVERLAY"] = { "Track Spectrum Overlay", "Picked from the swatch strip on the right edge of the Spectrum panel now, not here. Colours the Spectrum panel's own peaks by whichever watched track is loudest at that frequency. A track becomes watchable by ticking 'Include in Visualizer Spectrum' on its TS_TrackProbe." },
    }
    local shared_info = { hovered_id = nil }

----------------------------------------------------------
-- Loudness/Genre Target persistence
----------------------------------------------------------
    -- Two tiers, same idea as every other setting below (SaveAllSettings/
    -- LoadAllSettings) except those only ever need the global one. The
    -- project ExtState copy travels with the song and wins whenever it's
    -- present (survives project save/load and transport start/stop,
    -- independent of any JSFX instance or its @slider timing); the plain
    -- global ExtState copy (reaper.ini, written alongside it below) is
    -- what a brand-new project falls back to, so the target you last set
    -- doesn't reset to "Off" just because this particular song never had
    -- one saved yet. gmem is just the live channel to the display script;
    -- neither of these persists by itself just from writing to gmem.
    -- SECTION isn't in scope yet this far up the file (declared with the
    -- rest of Save/LoadAllSettings below), so the literal is used here
    -- too, same as the ProjExtState call already did.
    local function SaveTargetToProject(key, value)
        reaper.SetProjExtState(0, "TS_Visualizer", key, tostring(value))
        reaper.SetExtState("TS_Visualizer", key, tostring(value), true)
    end

    local function SyncTargetsFromProject()
        local ok_l, val_l = reaper.GetProjExtState(0, "TS_Visualizer", "LoudnessTarget")
        if ok_l == 0 or val_l == "" then
            val_l = reaper.HasExtState("TS_Visualizer", "LoudnessTarget")
                and reaper.GetExtState("TS_Visualizer", "LoudnessTarget") or nil
        end
        if val_l then
            local n = tonumber(val_l)
            if n then reaper.gmem_write(MEM_LOUDNESS_TARGET, n) end
        end
        local ok_g, val_g = reaper.GetProjExtState(0, "TS_Visualizer", "GenreTarget")
        if ok_g == 0 or val_g == "" then
            val_g = reaper.HasExtState("TS_Visualizer", "GenreTarget")
                and reaper.GetExtState("TS_Visualizer", "GenreTarget") or nil
        end
        if val_g then
            local n = tonumber(val_g)
            if n then reaper.gmem_write(MEM_GENRE_TARGET, n) end
        end
    end

----------------------------------------------------------
-- Save & Load Values
----------------------------------------------------------
    local SECTION = "TS_Visualizer"

    local function SaveAllSettings()
        for i = 1000, 1140 do
            local val = reaper.gmem_read(i)
            reaper.SetExtState(SECTION, "MEM_"..i, tostring(val), true)
        end
        reaper.SetExtState(SECTION, "FontScale", tostring(reaper.gmem_read(1300)), true)
        reaper.SetExtState(SECTION, "SpectrumSlope", tostring(reaper.gmem_read(MEM_SPECTRUM_SLOPE)), true)
        reaper.SetExtState(SECTION, "SpectrumTilt", tostring(reaper.gmem_read(MEM_SPECTRUM_TILT)), true)
        reaper.SetExtState(SECTION, "Orientation", tostring(reaper.gmem_read(MEM_ORIENTATION)), true)
        reaper.SetExtState(SECTION, "PairGonioSymbiote", tostring(reaper.gmem_read(MEM_PAIR_GONIO_SYMBIOTE)), true)
        reaper.SetExtState(SECTION, "PairLufsDynamics", tostring(reaper.gmem_read(MEM_PAIR_LUFS_DYN)), true)
        reaper.SetExtState(SECTION, "BaseHue", tostring(reaper.gmem_read(MEM_BASE_HUE)), true)
        reaper.SetExtState(SECTION, "Tint", tostring(reaper.gmem_read(MEM_TINT)), true)
        reaper.SetExtState(SECTION, "SyncChannelView", tostring(reaper.gmem_read(MEM_SYNC_CV)), true)
        for i = 1, 7 do
            reaper.SetExtState(SECTION, "FollowHue_"..ROLE_NAMES[i], tostring(reaper.gmem_read(FOLLOW_HUE_BASE + i)), true)
        end
        for i = 1, 7 do
            reaper.SetExtState(SECTION, "ModSize_"..i, tostring(reaper.gmem_read(MEM_MOD_SIZE + i)), true)
        end

        local order_str = ""
        for i = 1, 7 do order_str = order_str .. ui_order[i] .. (i < 7 and "," or "") end
        reaper.SetExtState(SECTION, "ModuleOrder", order_str, true)

        local active_str = ""
        for i = 1, 7 do active_str = active_str .. (ui_active[i] and "1" or "0") .. (i < 7 and "," or "") end
        reaper.SetExtState(SECTION, "ModuleActive", active_str, true)
    end

    local function LoadAllSettings()
        for i = 1000, 1140 do
            if reaper.HasExtState(SECTION, "MEM_"..i) then
                reaper.gmem_write(i, tonumber(reaper.GetExtState(SECTION, "MEM_"..i)))
            end
        end
        if reaper.HasExtState(SECTION, "FontScale") then
            reaper.gmem_write(1300, tonumber(reaper.GetExtState(SECTION, "FontScale")))
        end
        if reaper.HasExtState(SECTION, "SpectrumSlope") then
            reaper.gmem_write(MEM_SPECTRUM_SLOPE, tonumber(reaper.GetExtState(SECTION, "SpectrumSlope")))
        end
        if reaper.HasExtState(SECTION, "SpectrumTilt") then
            reaper.gmem_write(MEM_SPECTRUM_TILT, tonumber(reaper.GetExtState(SECTION, "SpectrumTilt")))
        end
        if reaper.HasExtState(SECTION, "Orientation") then
            reaper.gmem_write(MEM_ORIENTATION, tonumber(reaper.GetExtState(SECTION, "Orientation")))
        end
        if reaper.HasExtState(SECTION, "PairLufsDynamics") then
            reaper.gmem_write(MEM_PAIR_LUFS_DYN, tonumber(reaper.GetExtState(SECTION, "PairLufsDynamics")))
        end
        if reaper.HasExtState(SECTION, "PairGonioSymbiote") then
            reaper.gmem_write(MEM_PAIR_GONIO_SYMBIOTE, tonumber(reaper.GetExtState(SECTION, "PairGonioSymbiote")))
        end
        if reaper.HasExtState(SECTION, "BaseHue") then
            reaper.gmem_write(MEM_BASE_HUE, tonumber(reaper.GetExtState(SECTION, "BaseHue")))
        end
        if reaper.HasExtState(SECTION, "Tint") then
            reaper.gmem_write(MEM_TINT, tonumber(reaper.GetExtState(SECTION, "Tint")))
        end
        for i = 1, 7 do
            if reaper.HasExtState(SECTION, "FollowHue_"..ROLE_NAMES[i]) then
                reaper.gmem_write(FOLLOW_HUE_BASE + i, tonumber(reaper.GetExtState(SECTION, "FollowHue_"..ROLE_NAMES[i])))
            end
        end
        if reaper.HasExtState(SECTION, "SyncChannelView") then
            reaper.gmem_write(MEM_SYNC_CV, tonumber(reaper.GetExtState(SECTION, "SyncChannelView")))
        end
        for i = 1, 7 do
            if reaper.HasExtState(SECTION, "ModSize_"..i) then
                reaper.gmem_write(MEM_MOD_SIZE + i, tonumber(reaper.GetExtState(SECTION, "ModSize_"..i)))
            end
        end
        if reaper.HasExtState(SECTION, "ModuleOrder") then
            local order_str = reaper.GetExtState(SECTION, "ModuleOrder")
            local idx = 1
            for val in string.gmatch(order_str, '([^,]+)') do
                ui_order[idx] = tonumber(val)
                reaper.gmem_write(1100 + idx, ui_order[idx])
                idx = idx + 1
            end
        end
        if reaper.HasExtState(SECTION, "ModuleActive") then
            local active_str = reaper.GetExtState(SECTION, "ModuleActive")
            local idx = 1
            for val in string.gmatch(active_str, '([^,]+)') do
                ui_active[idx] = (val == "1")
                reaper.gmem_write(1150 + idx, ui_active[idx] and 1 or 0)
                idx = idx + 1
            end
        else
            for i = 1, 7 do reaper.gmem_write(1150 + i, 1) end
        end
    end
    LoadAllSettings()

----------------------------------------------------------
-- Run at Startup (REAPER's native Scripts/__startup.lua)
--
-- Ported from Track Analyser's own copy of this feature (TA_Panel.lua),
-- which already has to solve the same problem: __startup.lua is shared
-- with every other auto-launched tool (Adaptive Grid, Gridbox, Track
-- Analyser, ChannelView, ...), so a bad edit here can silently break all
-- of them, not just this one. Same three rules apply:
--
--   1  BACKUP FIRST, every time, to __startup.lua.bak.
--   2  THE RESULT IS COMPILED BEFORE IT IS SAVED. load() on the new text
--      catches a mangled edit while it's still a string in memory - a
--      startup file that doesn't parse is never written.
--   3  LINES THIS EDITOR DID NOT WRITE ARE NOT TOUCHED. Its own block is
--      fenced with markers and only that is ever removed. If the command
--      id turns up outside the fence (this project already has one such
--      entry, added some other way), it's reported and left alone rather
--      than edited or duplicated.
--
-- One difference from Track Analyser: TA_Panel.lua IS the script that
-- gets auto-started, so it can ask get_action_context() for its own
-- command id. This Editor is a separate script from TS_Visualizer.lua
-- (the one that actually needs to run at startup), so it has to resolve
-- that script's id from its path instead - the same AddRemoveReaScript
-- call TS_Visualizer.lua already uses on itself to launch this Editor.
----------------------------------------------------------
    local START_BEGIN = "-- >>> TS_Visualizer (added by TS_Visualizer Editor)"
    local START_END   = "-- <<< TS_Visualizer"

    -- The markers contain Lua pattern metacharacters (- ( ) > .), so they
    -- can't be used as patterns raw - matching them unescaped is exactly
    -- how a block this script just wrote would get reported as somebody
    -- else's hand-edit.
    local function esc(str) return (str:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")) end
    local BEGIN_PAT, END_PAT = esc(START_BEGIN), esc(START_END)

    local function startupPath()
        return reaper.GetResourcePath() .. "/Scripts/__startup.lua"
    end

    local function readAll(path)
        local f = io.open(path, "rb")
        if not f then return nil end
        local t = f:read("*a")
        f:close()
        return t
    end

    -- Registers (or harmlessly re-registers) TS_Visualizer.lua as an
    -- action and returns its persistent command id string, e.g.
    -- "_RS29282ada...". Uses `here` (this script's own folder, derived
    -- up top) rather than a spelled-out path, so this survives the
    -- folder being renamed or moved the same way the gear icon's path
    -- now does.
    local function get_visualizer_cmd_name()
        local script_path = here .. "TS_Visualizer.lua"
        local cmd_id = reaper.AddRemoveReaScript(true, 0, script_path, true)
        if not cmd_id or cmd_id == 0 then return nil end
        return "_" .. reaper.ReverseNamedCommandLookup(cmd_id)
    end

    -- "none" | "ours" | "manual" | "nocmd"
    local startup = { state = "none", checked = false, note = nil, cmd_name = nil }

    local function startupScan()
        startup.checked = true
        startup.note = nil
        startup.cmd_name = get_visualizer_cmd_name()
        if not startup.cmd_name then
            startup.state = "nocmd"
            startup.note = "REAPER hasn't given this script an action id yet - open the visualizer once and this works."
            return
        end
        local txt = readAll(startupPath())
        if not txt then startup.state = "none" ; return end
        local fenced = txt:match(BEGIN_PAT .. "(.-)" .. END_PAT)
        if fenced and fenced:find(startup.cmd_name, 1, true) then
            startup.state = "ours"
        elseif txt:find(startup.cmd_name, 1, true) then
            startup.state = "manual"
            startup.note = "already in __startup.lua, on a line this Editor didn't write - remove it by hand if you want it gone."
        else
            startup.state = "none"
        end
    end

    -- Writes `txt` only if it compiles. Returns true, or false plus why.
    local function startupWrite(txt)
        local chunk, err = load(txt, "__startup.lua")
        if not chunk then
            return false, "the result would not compile: " .. tostring(err)
        end
        local path = startupPath()
        local cur = readAll(path)
        if cur then
            local bf = io.open(path .. ".bak", "wb")
            if bf then
                bf:write(cur)
                bf:close()
            else
                return false, "could not write the backup, so nothing was changed"
            end
        end
        local f = io.open(path, "wb")
        if not f then return false, "could not open __startup.lua for writing" end
        f:write(txt)
        f:close()
        return true
    end

    local function startupAdd()
        startupScan()
        if not startup.cmd_name then return false, "no action id for this script" end
        -- Never twice - two Main_OnCommand calls for the same script would
        -- start two copies of the visualizer fighting over the same gmem.
        if startup.state == "ours" or startup.state == "manual" then return true end
        local txt = readAll(startupPath()) or "-- REAPER startup script\n"
        if not txt:match("\n$") then txt = txt .. "\n" end
        txt = txt .. ("\n%s\nlocal ts_visualizer_startup_cmd = '%s'\n" ..
                      "reaper.Main_OnCommand(reaper.NamedCommandLookup(ts_visualizer_startup_cmd), 0)\n%s\n")
            :format(START_BEGIN, startup.cmd_name, START_END)
        local ok, why = startupWrite(txt)
        startupScan()
        return ok, why
    end

    local function startupRemove()
        local txt = readAll(startupPath())
        if not txt then startupScan() ; return true end
        -- Only the fenced block, and only when it's ours. Anything else
        -- in that file belongs to something else.
        local out = txt:gsub("\n*" .. BEGIN_PAT .. ".-" .. END_PAT .. "\n*", "\n")
        out = out:gsub("%s*$", "\n")
        local ok, why = startupWrite(out)
        startupScan()
        return ok, why
    end

----------------------------------------------------------
-- Color Editor
--
-- Every swatch here follows the Hue/Tint palette below by default (see
-- the "Follow" checkbox each one draws) - the actual colour is computed
-- by TS_Visualizer.lua's own build_palette(), the same live colour engine
-- ChannelView and TrackAnalyser use, and just read back here for display.
-- Unticking "Follow" hands that one swatch back to a plain colour picker,
-- same as TrackAnalyser's per-colour auto-follow toggles.
----------------------------------------------------------
    function ColorEdit(ctx, label, mem_idx, desc_id, follow_idx)
        if follow_idx then
            local fval = reaper.gmem_read(FOLLOW_HUE_BASE + follow_idx)
            local fchanged, fnew = reaper.ImGui_Checkbox(ctx, "##follow_"..follow_idx, fval ~= 0)
            if fchanged then
                reaper.gmem_write(FOLLOW_HUE_BASE + follow_idx, fnew and 1 or 0)
                SaveAllSettings()
                fval = fnew and 1 or 0
            end
            if reaper.ImGui_IsItemHovered(ctx) then shared_info.hovered_id = "FOLLOW" end
            reaper.ImGui_SameLine(ctx)
            if fval ~= 0 then reaper.ImGui_BeginDisabled(ctx) end
        end

        local r = reaper.gmem_read(mem_idx)
        local g = reaper.gmem_read(mem_idx + 1)
        local b = reaper.gmem_read(mem_idx + 2)
        local a = reaper.gmem_read(mem_idx + 3)

        local packed_col = reaper.ImGui_ColorConvertDouble4ToU32(r, g, b, a)

        local flags = reaper.ImGui_ColorEditFlags_NoInputs() |
                      reaper.ImGui_ColorEditFlags_AlphaPreviewHalf() |
                      reaper.ImGui_ColorEditFlags_AlphaBar()

        reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FramePadding(), 6, 6)
        reaper.ImGui_SetNextItemWidth(ctx, 30)

        local retval, new_packed_col = reaper.ImGui_ColorEdit4(ctx, label, packed_col, flags)
        reaper.ImGui_PopStyleVar(ctx)

        -- gmem is written every frame the picker reports a change, so the
        -- swatch and the live visualizer both track the drag smoothly.
        -- SaveAllSettings() is NOT called here on purpose: it writes on
        -- the order of 150+ ExtState keys, and doing that on every single
        -- frame while a picker is being dragged is exactly what was
        -- freezing the Editor on colour changes (a pre-existing pattern,
        -- not something this rewrite introduced - it just touched this
        -- code again). IsItemDeactivatedAfterEdit() below fires once,
        -- when the picker is released/closed, which is the only point
        -- anything actually needs to hit disk.
        if retval then
            local nr, ng, nb, na = reaper.ImGui_ColorConvertU32ToDouble4(new_packed_col)
            reaper.gmem_write(mem_idx, nr)
            reaper.gmem_write(mem_idx + 1, ng)
            reaper.gmem_write(mem_idx + 2, nb)
            reaper.gmem_write(mem_idx + 3, na)
        end
        if reaper.ImGui_IsItemDeactivatedAfterEdit(ctx) then
            SaveAllSettings()
        end
        if desc_id and reaper.ImGui_IsItemHovered(ctx) then
            shared_info.hovered_id = desc_id
        end

        if follow_idx and reaper.gmem_read(FOLLOW_HUE_BASE + follow_idx) ~= 0 then
            reaper.ImGui_EndDisabled(ctx)
        end
    end

----------------------------------------------------------
-- Apply Default Values
----------------------------------------------------------
    function ApplyDefaults()
        -- Resets to Hue 219 / Tint 1.0 with every swatch following - the
        -- palette's own defaults. TS_Visualizer.lua's build_palette()
        -- picks this up and writes the actual RGB on its next frame, the
        -- same lag any other setting change here already has.
        reaper.gmem_write(MEM_BASE_HUE, 219); SaveAllSettings()
        reaper.gmem_write(MEM_TINT, 1.0); SaveAllSettings()
        for i = 1, 7 do
            reaper.gmem_write(FOLLOW_HUE_BASE + i, 1); SaveAllSettings()
        end
    end

    function init_order_from_gmem()
        local has_data = false
        for i = 1, 7 do
            local val = reaper.gmem_read(1100 + i)
            if val > 0 then
                ui_order[i] = val
                has_data = true
            end
        end
        if not has_data then
            for i = 1, 7 do reaper.gmem_write(1100 + i, ui_order[i]) end
            SaveAllSettings()
        end
    end

    init_order_from_gmem()

----------------------------------------------------------
-- UI Loop
----------------------------------------------------------
    function loop()
        SyncTargetsFromProject()
        local textcol_title = 0xE3DB8EFF
        local textcol_gray = 0x808080FF
        local pushed_vars, pushed_cols = ApplyTheme(ctx)
        reaper.ImGui_PushFont(ctx, font_12, 12)
        reaper.ImGui_SetNextWindowSize(ctx, 530, 640, reaper.ImGui_Cond_Once())

        local visible, open = reaper.ImGui_Begin(ctx, 'TS_Visualizer Editor v2.1', true,
            reaper.ImGui_WindowFlags_NoCollapse())
        reaper.ImGui_PopFont(ctx)
        if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Escape()) then
            open = false
        end    
        reaper.ImGui_PushFont(ctx, font_13, 13)
        if visible then
            -- Hover descriptions used to be drawn inline, right-aligned
            -- in a row reserved above "Visual Size" -- first sized for
            -- the old logo, then (once the logo was gone) reserving a
            -- fixed height whether or not anything was actually hovered,
            -- which left a dead gap at the top most of the time. Making
            -- that reservation track hover state instead just moved the
            -- problem: with 30-odd controls below each setting
            -- shared_info.hovered_id on its own hover, the reserved row
            -- was appearing and disappearing, and everything below it
            -- jumping by its height, on nearly every mouse move over the
            -- window. A floating ImGui tooltip near the cursor doesn't
            -- occupy a slot in the window's own layout at all, so
            -- nothing below it moves, hovered or not. hovered_id itself
            -- is unchanged -- every slider/checkbox below still sets it
            -- on its own IsItemHovered() check -- only reset up here, at
            -- the start of the frame, instead of after a now-deleted
            -- inline render; the tooltip itself is drawn once, from
            -- whatever's current by the end of this same frame, right
            -- before the window closes below.
            shared_info.hovered_id = nil
            -- Visual Size
                reaper.ImGui_SeparatorText(ctx, 'Visual Size')
                -- Every slider below writes gmem on every frame it changes
                -- (for a live-tracking drag) but only calls SaveAllSettings()
                -- - which writes 150+ ExtState keys - once, when the drag
                -- is released. Doing that write on every frame of a drag is
                -- what makes the Editor stutter/freeze while adjusting
                -- anything; this was already the pattern throughout this
                -- file before the colour rewrite touched it again.
                -- 1. Gonio Gain
                local g_gain = reaper.gmem_read(MEM_GAIN_GONIO)
                local g_changed, g_new = reaper.ImGui_SliderDouble(ctx, "Gonio Gain", g_gain, 0.0, 1.0, "%.3f")
                if g_changed then reaper.gmem_write(MEM_GAIN_GONIO, g_new) end
                if reaper.ImGui_IsItemDeactivatedAfterEdit(ctx) then SaveAllSettings() end
                if reaper.ImGui_IsItemHovered(ctx) then shared_info.hovered_id = "GAIN_GONIO" end

                -- 2. Symbiote Gain
                local sym_gain = reaper.gmem_read(MEM_GAIN_SYMBIOTE)
                local s_changed, s_new = reaper.ImGui_SliderDouble(ctx, "Symbiote Gain", sym_gain, 0.0, 1.0, "%.3f")
                if s_changed then reaper.gmem_write(MEM_GAIN_SYMBIOTE, s_new) end
                if reaper.ImGui_IsItemDeactivatedAfterEdit(ctx) then SaveAllSettings() end
                if reaper.ImGui_IsItemHovered(ctx) then shared_info.hovered_id = "GAIN_SYMBIOTE" end

                -- 3. Scope Gain
                local scp_gain = reaper.gmem_read(MEM_GAIN_SCOPE)
                local scp_changed, scp_new = reaper.ImGui_SliderDouble(ctx, "Scope Gain", scp_gain, 0.0, 1.0, "%.3f")
                if scp_changed then reaper.gmem_write(MEM_GAIN_SCOPE, scp_new) end
                if reaper.ImGui_IsItemDeactivatedAfterEdit(ctx) then SaveAllSettings() end
                if reaper.ImGui_IsItemHovered(ctx) then shared_info.hovered_id = "GAIN_SCOPE" end

                -- 4. Spectrum Gain
                local spec_gain = reaper.gmem_read(MEM_GAIN_SPECTRUM)
                local sp_changed, sp_new = reaper.ImGui_SliderDouble(ctx, "Spectrum Gain", spec_gain, 0.0, 1.0, "%.3f")
                if sp_changed then reaper.gmem_write(MEM_GAIN_SPECTRUM, sp_new) end
                if reaper.ImGui_IsItemDeactivatedAfterEdit(ctx) then SaveAllSettings() end
                if reaper.ImGui_IsItemHovered(ctx) then shared_info.hovered_id = "GAIN_SPECTRUM" end

                -- Spectrum Slope Guide
                local SLOPE_VALUES = {-1, 3.0, 4.5, 6.0}
                local SLOPE_LABELS = {"Off", "3 dB/oct", "4.5 dB/oct", "6 dB/oct"}
                local slope_val = reaper.gmem_read(MEM_SPECTRUM_SLOPE)
                if slope_val == 0 then slope_val = 4.5 end
                local slope_idx = 3
                for i = 1, 4 do
                    if slope_val == SLOPE_VALUES[i] then slope_idx = i end
                end
                local slope_changed, new_idx = reaper.ImGui_SliderInt(ctx, "Slope Guide", slope_idx, 1, 4, SLOPE_LABELS[slope_idx])
                if slope_changed then
                    reaper.gmem_write(MEM_SPECTRUM_SLOPE, SLOPE_VALUES[new_idx])
                end
                if reaper.ImGui_IsItemDeactivatedAfterEdit(ctx) then SaveAllSettings() end
                if reaper.ImGui_IsItemHovered(ctx) then shared_info.hovered_id = "SLOPE" end

                -- Spectrum Tilt (shifts the displayed curve itself, rather
                -- than just overlaying a reference line)
                local TILT_VALUES = {0, 3.0, 4.5, 6.0}
                local TILT_LABELS = {"Off", "3 dB/oct", "4.5 dB/oct", "6 dB/oct"}
                local tilt_val = reaper.gmem_read(MEM_SPECTRUM_TILT)
                local tilt_idx = 1
                for i = 1, 4 do
                    if tilt_val == TILT_VALUES[i] then tilt_idx = i end
                end
                local tilt_changed, tilt_new_idx = reaper.ImGui_SliderInt(ctx, "Spectrum Tilt", tilt_idx, 1, 4, TILT_LABELS[tilt_idx])
                if tilt_changed then
                    reaper.gmem_write(MEM_SPECTRUM_TILT, TILT_VALUES[tilt_new_idx])
                end
                if reaper.ImGui_IsItemDeactivatedAfterEdit(ctx) then SaveAllSettings() end
                if reaper.ImGui_IsItemHovered(ctx) then shared_info.hovered_id = "TILT" end

                reaper.ImGui_Spacing(ctx)

                -- Folder Spectrum Overlay's track picker used to be a
                -- checkbox list here. It's the swatch sidebar down the
                -- right edge of the main window now -- see
                -- draw_track_sidebar in TS_Visualizer.lua.

                reaper.ImGui_Spacing(ctx)
                local font_scale = reaper.gmem_read(1300)
                    if font_scale <= 0 then font_scale = 1.0 end
                    local changed, new_scale = reaper.ImGui_SliderDouble(ctx, "Font Scale", font_scale, 0.5, 2.0, "%.2fx")
                    if changed then
                        reaper.gmem_write(1300, new_scale)
                    end
                    if reaper.ImGui_IsItemDeactivatedAfterEdit(ctx) then SaveAllSettings() end
                    if reaper.ImGui_IsItemHovered(ctx) then shared_info.hovered_id = "FONT" end
                    reaper.ImGui_Spacing(ctx)
            -- Signal Speed
                -- Attack Slider
                    local current_att = reaper.gmem_read(4)
                    if current_att <= 0 then current_att = 1.0 end
                    local changed_att, new_att = reaper.ImGui_SliderDouble(ctx, "Response Speed", current_att, 0.1, 1.0, "%.2fx")
                    -- Right-click reset is its own single event, not part of
                    -- a drag, so it still saves immediately rather than
                    -- waiting on IsItemDeactivatedAfterEdit (which a
                    -- right-click doesn't reliably trigger).
                    local reset_att = reaper.ImGui_IsItemClicked(ctx, 1)
                    if reset_att then
                        new_att = 1.0
                        changed_att = true
                    end
                    if changed_att then
                        reaper.gmem_write(4, new_att)
                    end
                    if reset_att or reaper.ImGui_IsItemDeactivatedAfterEdit(ctx) then
                        SaveAllSettings()
                    end
                    if reaper.ImGui_IsItemHovered(ctx) then shared_info.hovered_id = "ATTACK" end

                -- Release Slider
                    local current_rel = reaper.gmem_read(5)
                    if current_rel <= 0 then current_rel = 1.0 end
                    local changed_rel, new_rel = reaper.ImGui_SliderDouble(ctx, "Decay Speed", current_rel, 0.1, 1.0, "%.2fx")
                    local reset_rel = reaper.ImGui_IsItemClicked(ctx, 1)
                    if reset_rel then
                        new_rel = 1.0
                        changed_rel = true
                    end
                    if changed_rel then
                        reaper.gmem_write(5, new_rel)
                    end
                    if reset_rel or reaper.ImGui_IsItemDeactivatedAfterEdit(ctx) then
                        SaveAllSettings()
                    end
                    if reaper.ImGui_IsItemHovered(ctx) then shared_info.hovered_id = "RELEASE" end
                    reaper.ImGui_Spacing(ctx)

                -- Layout Orientation
                local orient_val = reaper.gmem_read(MEM_ORIENTATION)
                local is_vert = (orient_val == 1)
                local orient_changed, orient_new = reaper.ImGui_Checkbox(ctx, "Vertical Layout", is_vert)
                if orient_changed then
                    reaper.gmem_write(MEM_ORIENTATION, orient_new and 1 or 0)
                    SaveAllSettings()
                end
                if reaper.ImGui_IsItemHovered(ctx) then shared_info.hovered_id = "ORIENTATION" end
                reaper.ImGui_SameLine(ctx)
                if reaper.ImGui_Button(ctx, "Reset Panel Sizes") then
                    for i = 1, 7 do
                        reaper.gmem_write(MEM_MOD_SIZE + i, 0)
                        reaper.DeleteExtState(SECTION, "ModSize_"..i, true)
                    end
                    SaveAllSettings()
                end
                if reaper.ImGui_IsItemHovered(ctx) then shared_info.hovered_id = "RESET_SIZES" end

                local pair_val = reaper.gmem_read(MEM_PAIR_GONIO_SYMBIOTE)
                local pair_changed, pair_new = reaper.ImGui_Checkbox(ctx, "Pair Gonio + Symbiote (Vertical layout)", pair_val == 1)
                if pair_changed then
                    reaper.gmem_write(MEM_PAIR_GONIO_SYMBIOTE, pair_new and 1 or 0)
                    SaveAllSettings()
                end
                if reaper.ImGui_IsItemHovered(ctx) then shared_info.hovered_id = "PAIR_GS" end

                if pair_val == 1 then
                    -- Pairing only takes effect when Gonio(2) and Symbiote(3)
                    -- are next to each other in the module order below. Flag
                    -- it here instead of leaving the checkbox silently doing
                    -- nothing - drag-reordering the modules can separate
                    -- them without any other indication that pairing has
                    -- stopped applying.
                    local adjacent = false
                    for i = 1, 6 do
                        local a, b = ui_order[i], ui_order[i + 1]
                        if (a == 2 and b == 3) or (a == 3 and b == 2) then adjacent = true; break end
                    end
                    if not adjacent then
                        reaper.ImGui_TextColored(ctx, 0xE8C25AFF, "Gonio and Symbiote aren't next to each other in the module order below, so they aren't currently paired.")
                    end
                end

                local pair_ld_val = reaper.gmem_read(MEM_PAIR_LUFS_DYN)
                local pair_ld_changed, pair_ld_new = reaper.ImGui_Checkbox(ctx, "Pair LUFS + Dynamics (Vertical layout)", pair_ld_val == 1)
                if pair_ld_changed then
                    reaper.gmem_write(MEM_PAIR_LUFS_DYN, pair_ld_new and 1 or 0)
                    SaveAllSettings()
                end
                if reaper.ImGui_IsItemHovered(ctx) then shared_info.hovered_id = "PAIR_LD" end

                if pair_ld_val == 1 then
                    -- Same adjacency requirement and same reason to flag it
                    -- as Pair Gonio + Symbiote above. Drag order also
                    -- decides which side LUFS lands on: whichever of the
                    -- two comes first in the list below sits on the left
                    -- (or on top, in a Horizontal layout's own left/right
                    -- module columns).
                    local ld_adjacent = false
                    for i = 1, 6 do
                        local a, b = ui_order[i], ui_order[i + 1]
                        if (a == 1 and b == 7) or (a == 7 and b == 1) then ld_adjacent = true; break end
                    end
                    if not ld_adjacent then
                        reaper.ImGui_TextColored(ctx, 0xE8C25AFF, "LUFS and Dynamics aren't next to each other in the module order below, so they aren't currently paired.")
                    end
                end
                reaper.ImGui_Spacing(ctx)

                -- Run at Startup
                -- Scanned on first draw rather than held in ExtState: the
                -- file is the truth, and a remembered boolean is just
                -- something that can disagree with it.
                if not startup.checked then startupScan() end
                do
                    local on = (startup.state == "ours" or startup.state == "manual")
                    local run_changed, run_new = reaper.ImGui_Checkbox(ctx, "Run at REAPER Startup", on)
                    if run_changed then
                        local ok, why
                        if run_new then ok, why = startupAdd() else ok, why = startupRemove() end
                        if not ok then
                            reaper.ShowMessageBox("__startup.lua was NOT changed.\n\n" .. tostring(why), "TS_Visualizer", 0)
                        end
                    end
                    if reaper.ImGui_IsItemHovered(ctx) then shared_info.hovered_id = "RUN_STARTUP" end
                    reaper.ImGui_SameLine(ctx)
                    if startup.note then
                        reaper.ImGui_TextColored(ctx, 0xE8C25AFF, startup.note)
                    elseif startup.state == "ours" then
                        reaper.ImGui_TextColored(ctx, 0x5C646CFF, "in __startup.lua - takes effect next time REAPER starts")
                    else
                        reaper.ImGui_TextColored(ctx, 0x5C646CFF, "edits Scripts/__startup.lua, backing it up first")
                    end
                end
                reaper.ImGui_Spacing(ctx)

            -- Dynamics Panel (targets are stored in project ExtState -> saved with the project)
                reaper.ImGui_SeparatorText(ctx, 'Dynamics Panel')
                local LOUD_LABELS = {
                    "Off", "-6 LUFS (Loud/Rock)", "-7 LUFS", "-8 LUFS", "-9 LUFS",
                    "-10 LUFS", "-11 LUFS", "-12 LUFS", "-13 LUFS", "-14 LUFS (Streaming)",
                    "-15 LUFS", "-16 LUFS", "-17 LUFS", "-18 LUFS", "-19 LUFS",
                    "-20 LUFS", "-21 LUFS", "-22 LUFS", "-23 LUFS", "-24 LUFS (Broadcast)",
                }
                local loud_val = reaper.gmem_read(MEM_LOUDNESS_TARGET)
                local loud_idx = math.floor(loud_val + 0.5)
                if loud_idx < 0 or loud_idx > 19 then loud_idx = 0 end
                local loud_changed, loud_new = reaper.ImGui_SliderInt(ctx, "Loudness Target", loud_idx, 0, 19, LOUD_LABELS[loud_idx + 1])
                if loud_changed then
                    reaper.gmem_write(MEM_LOUDNESS_TARGET, loud_new)
                    SaveTargetToProject("LoudnessTarget", loud_new)
                end
                if reaper.ImGui_IsItemHovered(ctx) then shared_info.hovered_id = "LOUD_TARGET" end

                local GENRE_LABELS = {
                    "Off", "Universal", "Acoustic", "Classical", "Country", "EDM", "Funk",
                    "Hip Hop", "Jazz", "Metal", "Pop", "R&B", "Rock", "Speech"
                }
                local genre_val = reaper.gmem_read(MEM_GENRE_TARGET)
                local genre_idx = math.floor(genre_val + 0.5)
                if genre_idx < 0 or genre_idx > 13 then genre_idx = 0 end
                local genre_changed, genre_new = reaper.ImGui_SliderInt(ctx, "Genre/Dynamics Target", genre_idx, 0, 13, GENRE_LABELS[genre_idx + 1])
                if genre_changed then
                    reaper.gmem_write(MEM_GENRE_TARGET, genre_new)
                    SaveTargetToProject("GenreTarget", genre_new)
                end
                if reaper.ImGui_IsItemHovered(ctx) then shared_info.hovered_id = "GENRE_TARGET" end
                reaper.ImGui_Spacing(ctx)

            -- Order (adding the Waterfall module)
                local module_names = {
                    [1]="   ▩ LUFS", [2]="   ▩ Gonio", [3]="   ▩ Symbiote",
                    [4]="   ▩ Scope", [5]="   ▩ Spectrum", [6]="   ▩ Spectrogram", [7]="   ▩ Dynamics"
                }

                reaper.ImGui_SeparatorText(ctx, "Module Order (Drag to Reorder)")

                for i, module_id in ipairs(ui_order) do
                    local is_active = ui_active[module_id]
                    local rv, new_val = reaper.ImGui_Checkbox(ctx, "##act_"..i, is_active)
                    if rv then
                        ui_active[module_id] = new_val
                        reaper.gmem_write(1150 + module_id, new_val and 1 or 0)
                        SaveAllSettings()
                    end
                    reaper.ImGui_SameLine(ctx)
                    if reaper.ImGui_IsItemHovered(ctx) then shared_info.hovered_id = "ORDER" end
                    
                    reaper.ImGui_PushID(ctx, i)
                    if not ui_active[module_id] then reaper.ImGui_BeginDisabled(ctx) end
                    reaper.ImGui_Selectable(ctx, module_names[module_id], false)
                    if not ui_active[module_id] then reaper.ImGui_EndDisabled(ctx) end
                    reaper.ImGui_PopID(ctx)

                    if reaper.ImGui_BeginDragDropSource(ctx, reaper.ImGui_DragDropFlags_None()) then
                        reaper.ImGui_SetDragDropPayload(ctx, "DND_ORDER", tostring(i))
                        reaper.ImGui_Text(ctx, module_names[module_id])
                        reaper.ImGui_EndDragDropSource(ctx)
                    end

                    if reaper.ImGui_BeginDragDropTarget(ctx) then
                        local retval, payload = reaper.ImGui_AcceptDragDropPayload(ctx, "DND_ORDER")
                        if retval then
                            local source_idx = tonumber(payload)
                            local target_idx = i
                            local item_to_move = table.remove(ui_order, source_idx)
                            table.insert(ui_order, target_idx, item_to_move)
                            for k=1, 7 do reaper.gmem_write(1100 + k, ui_order[k]) end
                            SaveAllSettings() 
                        end
                        reaper.ImGui_EndDragDropTarget(ctx)
                    end
                end
                reaper.ImGui_Spacing(ctx)
            -- Color Theme
                --
                -- Same colour engine as ChannelView and TrackAnalyser: one
                -- Hue + one Tint generate every swatch below by default.
                -- Untick a swatch's "Follow" box to hand-pick that one
                -- colour instead; the rest keep following the palette.
                reaper.ImGui_SeparatorText(ctx, 'Global Theme')
                ColorEdit(ctx, "Background", MEM_BG, "BG", 1)
                ColorEdit(ctx, "Grid & Lines", MEM_LINE, "LINE", 2)
                ColorEdit(ctx, "Text & Labels", MEM_TEXT, "TEXT", 3)

                reaper.ImGui_Spacing(ctx)
                reaper.ImGui_SeparatorText(ctx, 'Signal Colors')
                ColorEdit(ctx, "Weak (Zero)", MEM_ZERO, "ZERO", 4)
                ColorEdit(ctx, "Normal (Mid)", MEM_MID, "MID", 5)
                ColorEdit(ctx, "Strong (Peak)", MEM_PEAK, "PEAK", 6)
                ColorEdit(ctx, "Spec Frez Line", MEM_FREZ, "FREZ", 7)

                reaper.ImGui_Spacing(ctx)
                reaper.ImGui_SeparatorText(ctx, 'Hue / Tint')

                -- Live sync with the shared palette: when on, Hue/Tint
                -- below are driven every frame from TS_Palette (read via
                -- ExtState in TS_Visualizer.lua's own loop, with a
                -- fallback to ChannelView's own section for an install
                -- that hasn't moved yet, so this stays correct even if
                -- the Editor isn't open) rather than from the sliders.
                -- Disable the sliders while synced so it's clear they
                -- aren't the live source.
                local sync_val = reaper.gmem_read(MEM_SYNC_CV)
                local sync_changed, sync_new = reaper.ImGui_Checkbox(ctx, "Sync Colour with ChannelView", sync_val ~= 0)
                if sync_changed then
                    reaper.gmem_write(MEM_SYNC_CV, sync_new and 1 or 0)
                    SaveAllSettings()
                end
                if reaper.ImGui_IsItemHovered(ctx) then shared_info.hovered_id = "SYNC_CV" end

                local cv_synced = sync_val ~= 0
                if cv_synced then
                    -- The shared TS_Palette section, with the old
                    -- ChannelView location read as a fallback so an
                    -- existing setting still shows as followed.
                    if reaper.HasExtState("TS_Palette", "base_hue")
                       or reaper.HasExtState("TS_ChannelView", "base_hue") then
                        reaper.ImGui_TextColored(ctx, 0x9AAAB8FF, "Following the shared TS Hue/Tint live. Untick to set these manually.")
                    else
                        reaper.ImGui_TextColored(ctx, 0xE8C25AFF, "No shared colour has been set yet, so this is using the sliders below for now.")
                    end
                end

                if cv_synced then reaper.ImGui_BeginDisabled(ctx) end
                -- The same Hue/Tint knobs ChannelView and TrackAnalyser
                -- use: Hue is an absolute 0-359 base colour, Tint scales
                -- how far the furniture swatches (bg/grid/text/zero/frez)
                -- lean toward it. The two accent colours (Normal/Strong
                -- Signal) follow Hue but ignore Tint, staying fully
                -- saturated - same as those tools' "solid" role. Only
                -- swatches with "Follow" ticked above actually move.
                -- Same fix as the colour pickers above: gmem is written
                -- every frame so the drag tracks live, but SaveAllSettings()
                -- (150+ ExtState keys) only fires once, on release - not on
                -- every one of the dozens of frames a drag touches.
                local hue_val = reaper.gmem_read(MEM_BASE_HUE)
                local hue_changed, hue_new = reaper.ImGui_SliderInt(ctx, "Hue", math.floor(hue_val), 0, 359, "%d\xc2\xb0")
                if hue_changed then
                    reaper.gmem_write(MEM_BASE_HUE, hue_new)
                end
                if reaper.ImGui_IsItemDeactivatedAfterEdit(ctx) then
                    SaveAllSettings()
                end
                if reaper.ImGui_IsItemHovered(ctx) then shared_info.hovered_id = "BASE_HUE" end

                local tint_val = reaper.gmem_read(MEM_TINT)
                local tint_changed, tint_new = reaper.ImGui_SliderDouble(ctx, "Tint", tint_val, 0.0, 2.0, "%.2f")
                if tint_changed then
                    reaper.gmem_write(MEM_TINT, tint_new)
                end
                if reaper.ImGui_IsItemDeactivatedAfterEdit(ctx) then
                    SaveAllSettings()
                end
                if reaper.ImGui_IsItemHovered(ctx) then shared_info.hovered_id = "TINT" end
                if cv_synced then reaper.ImGui_EndDisabled(ctx) end

                -- Resets only the manual Hue/Tint values (and puts every
                -- swatch back to following), independent of the sync
                -- toggle above - it stays usable (not wrapped in
                -- BeginDisabled) so it's ready the moment sync is turned
                -- back off.
                if reaper.ImGui_Button(ctx, "Reset Hue/Tint", -1, 24) then
                    ApplyDefaults()
                end
                if reaper.ImGui_IsItemHovered(ctx) then shared_info.hovered_id = "HUE_SAT_RESET" end

                reaper.ImGui_Spacing(ctx)
                reaper.ImGui_Spacing(ctx)
            -- Reset
                if reaper.ImGui_Button(ctx, "Reset to Defualts", -1, 27) then
                    ApplyDefaults()
                end
                if reaper.ImGui_IsItemHovered(ctx) then shared_info.hovered_id = "RESET" end

                -- Quiet, permanent credit line for Junki Kim, whose
                -- JKK_Visualizer this was forked from -- a plain-text
                -- footer rather than the old hover-only logo credit
                -- (removed earlier, along with LOGO.png, at Tim's
                -- request), since a static line can't go missing behind
                -- another panel's tooltip the way the hover version
                -- could and doesn't need the image asset back.
                reaper.ImGui_Spacing(ctx)
                reaper.ImGui_PushFont(ctx, font_11, 11)
                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), textcol_gray)
                local credit_text = "Fork of JKK_Visualizer by Junki Kim  -  junkikim.sound@gmail.com"
                local credit_w = reaper.ImGui_CalcTextSize(ctx, credit_text)
                reaper.ImGui_SetCursorPosX(ctx, (reaper.ImGui_GetWindowWidth(ctx) - credit_w) * 0.5)
                reaper.ImGui_Text(ctx, credit_text)
                reaper.ImGui_PopStyleColor(ctx, 1)
                reaper.ImGui_PopFont(ctx)

                -- The hover description itself: a floating tooltip near
                -- the cursor, not a row in the window's own layout (see
                -- the note up by shared_info.hovered_id's reset). Drawn
                -- last so it reflects whichever control, if any, got
                -- hovered anywhere in this same frame.
                if shared_info.hovered_id and widget_descriptions[shared_info.hovered_id] then
                    local desc_text = widget_descriptions[shared_info.hovered_id]
                    if type(desc_text) == "table" then
                        reaper.ImGui_BeginTooltip(ctx)
                        local title, body = desc_text[1], desc_text[2]
                        reaper.ImGui_PushFont(ctx, font_13, 13)
                        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), textcol_title)
                        reaper.ImGui_Text(ctx, title)
                        reaper.ImGui_PopStyleColor(ctx, 1)
                        reaper.ImGui_PopFont(ctx)
                        if body then
                            reaper.ImGui_PushFont(ctx, font_11, 11)
                            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), textcol_gray)
                            for line in body:gmatch("([^\n]+)") do
                                reaper.ImGui_Text(ctx, line)
                            end
                            reaper.ImGui_PopStyleColor(ctx, 1)
                            reaper.ImGui_PopFont(ctx)
                        end
                        reaper.ImGui_EndTooltip(ctx)
                    end
                end

            if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Space()) then
                reaper.Main_OnCommand(40044, 0)
            end
            reaper.ImGui_End(ctx)
        end
        reaper.ImGui_PopFont(ctx)

        if pushed_vars > 0 then reaper.ImGui_PopStyleVar(ctx, pushed_vars) end
        if pushed_cols > 0 then reaper.ImGui_PopStyleColor(ctx, pushed_cols) end

        if open then
            reaper.defer(loop)
        end
    end

loop()