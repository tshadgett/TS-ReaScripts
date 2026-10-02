--========================================================
-- @title TS_Theme
-- @author Tim Shadgett (with Claude) -- fork of JKK_Visualizer by Junki Kim
-- Chrome recoloured to match the Track Analyser panel: a blue-cast near
-- black, a mid blue for anything active, and the gold reserved for peaks.
-- @noindex
--========================================================

function ApplyTheme(ctx)
    local vars_pushed, cols_pushed = 0, 0

    local function pushVar(name, ...)
        local getter = reaper[name]
        if getter then
            reaper.ImGui_PushStyleVar(ctx, getter(), ...)
            vars_pushed = vars_pushed + 1
        end
    end

    local function pushCol(name, value)
        local getter = reaper[name]
        if getter then
            reaper.ImGui_PushStyleColor(ctx, getter(), value)
            cols_pushed = cols_pushed + 1
        end
    end

    pushVar("ImGui_StyleVar_Alpha", 1)
    pushVar("ImGui_StyleVar_DisabledAlpha", 0.6)
    pushVar("ImGui_StyleVar_WindowPadding", 8, 8)
    pushVar("ImGui_StyleVar_WindowRounding", 8)
    pushVar("ImGui_StyleVar_WindowBorderSize", 1)
    pushVar("ImGui_StyleVar_WindowMinSize", 32, 32)
    pushVar("ImGui_StyleVar_WindowTitleAlign", 0, 0.5)
    pushVar("ImGui_StyleVar_ChildRounding", 12)
    pushVar("ImGui_StyleVar_ChildBorderSize", 1)
    pushVar("ImGui_StyleVar_PopupRounding", 8)
    pushVar("ImGui_StyleVar_PopupBorderSize", 1)
    pushVar("ImGui_StyleVar_FramePadding", 4, 3)
    pushVar("ImGui_StyleVar_FrameRounding", 12)
    pushVar("ImGui_StyleVar_FrameBorderSize", 0)
    pushVar("ImGui_StyleVar_ItemSpacing", 8, 4)
    pushVar("ImGui_StyleVar_ItemInnerSpacing", 4, 4)
    pushVar("ImGui_StyleVar_IndentSpacing", 22)
    pushVar("ImGui_StyleVar_CellPadding", 0, 2)
    pushVar("ImGui_StyleVar_ScrollbarSize", 14)
    pushVar("ImGui_StyleVar_ScrollbarRounding", 12)
    pushVar("ImGui_StyleVar_GrabMinSize", 15)
    pushVar("ImGui_StyleVar_GrabRounding", 12)
    pushVar("ImGui_StyleVar_ImageBorderSize", 0)
    pushVar("ImGui_StyleVar_TabRounding", 6)
    pushVar("ImGui_StyleVar_TabBorderSize", 0)
    pushVar("ImGui_StyleVar_TabBarBorderSize", 1)
    pushVar("ImGui_StyleVar_TabBarOverlineSize", 1)
    pushVar("ImGui_StyleVar_TableAngledHeadersAngle", 0.610865)
    pushVar("ImGui_StyleVar_TableAngledHeadersTextAlign", 0.5, 0)
    pushVar("ImGui_StyleVar_TreeLinesSize", 1)
    pushVar("ImGui_StyleVar_TreeLinesRounding", 12)
    pushVar("ImGui_StyleVar_ButtonTextAlign", 0.5, 0.5)
    pushVar("ImGui_StyleVar_SelectableTextAlign", 0, 0)
    pushVar("ImGui_StyleVar_SeparatorTextBorderSize", 2)
    pushVar("ImGui_StyleVar_SeparatorTextAlign", 0, 0.5)
    pushVar("ImGui_StyleVar_SeparatorTextPadding", 20, 3)

    pushCol("ImGui_Col_Text", 0xC6CDD4FF)
    pushCol("ImGui_Col_TextDisabled", 0x5C646CFF)
    pushCol("ImGui_Col_WindowBg", 0x1A1E22FF)
    pushCol("ImGui_Col_ChildBg", 0x00000000)
    pushCol("ImGui_Col_PopupBg", 0x14171AF0)
    pushCol("ImGui_Col_Border", 0x2E353CFF)
    pushCol("ImGui_Col_BorderShadow", 0x00000000)
    pushCol("ImGui_Col_FrameBg", 0x232A31FF)
    pushCol("ImGui_Col_FrameBgHovered", 0x2C343CFF)
    pushCol("ImGui_Col_FrameBgActive", 0x354049FF)
    pushCol("ImGui_Col_TitleBg", 0x1A1E22FF)
    pushCol("ImGui_Col_TitleBgActive", 0x14171AFF)
    pushCol("ImGui_Col_TitleBgCollapsed", 0x00000082)
    pushCol("ImGui_Col_MenuBarBg", 0x1A1E22FF)
    pushCol("ImGui_Col_ScrollbarBg", 0x00000000)
    pushCol("ImGui_Col_ScrollbarGrab", 0x2E6E96FF)
    pushCol("ImGui_Col_ScrollbarGrabHovered", 0x4E9AC8FF)
    pushCol("ImGui_Col_ScrollbarGrabActive", 0x1F4E6BFF)
    pushCol("ImGui_Col_CheckMark", 0x4E9AC8FF)
    pushCol("ImGui_Col_SliderGrab", 0x2E6E96FF)
    pushCol("ImGui_Col_SliderGrabActive", 0x4E9AC8FF)
    pushCol("ImGui_Col_Button", 0x232A31FF)
    pushCol("ImGui_Col_ButtonHovered", 0x2C343CFF)
    pushCol("ImGui_Col_ButtonActive", 0x354049FF)
    pushCol("ImGui_Col_Header", 0x1A1E22FF)
    pushCol("ImGui_Col_HeaderHovered", 0x272F36FF)
    pushCol("ImGui_Col_HeaderActive", 0x303941FF)
    pushCol("ImGui_Col_Separator", 0x262B31FF)
    pushCol("ImGui_Col_SeparatorHovered", 0x333A42FF)
    pushCol("ImGui_Col_SeparatorActive", 0x4A535DFF)
    pushCol("ImGui_Col_ResizeGrip", 0x2E6E96F1)
    pushCol("ImGui_Col_ResizeGripHovered", 0x4E9AC8FF)
    pushCol("ImGui_Col_ResizeGripActive", 0x4E9AC8FF)
    pushCol("ImGui_Col_InputTextCursor", 0xE8C25AFF)
    pushCol("ImGui_Col_TabHovered", 0x354049FF)
    pushCol("ImGui_Col_Tab", 0x232A31FF)
    pushCol("ImGui_Col_TabSelected", 0x2E6E96FF)
    pushCol("ImGui_Col_TabSelectedOverline", 0x4E9AC8FF)
    pushCol("ImGui_Col_TabDimmed", 0x1A1E22F8)
    pushCol("ImGui_Col_TabDimmedSelected", 0x24404FFF)
    pushCol("ImGui_Col_TabDimmedSelectedOverline", 0x80808000)
    pushCol("ImGui_Col_DockingPreview", 0x2E6E96B3)
    pushCol("ImGui_Col_DockingEmptyBg", 0x14171AFF)
    pushCol("ImGui_Col_PlotLines", 0x8A939CFF)
    pushCol("ImGui_Col_PlotLinesHovered", 0x4E9AC8FF)
    pushCol("ImGui_Col_PlotHistogram", 0xE8C25AFF)
    pushCol("ImGui_Col_PlotHistogramHovered", 0x4E9AC8FF)
    pushCol("ImGui_Col_TableHeaderBg", 0x1A1E22FF)
    pushCol("ImGui_Col_TableBorderStrong", 0x333A42FF)
    pushCol("ImGui_Col_TableBorderLight", 0x262B31FF)
    pushCol("ImGui_Col_TableRowBg", 0x00000000)
    pushCol("ImGui_Col_TableRowBgAlt", 0xFFFFFF0F)
    pushCol("ImGui_Col_TextLink", 0x7FB3FFFF)
    pushCol("ImGui_Col_TextSelectedBg", 0x2E6E9659)
    pushCol("ImGui_Col_TreeLines", 0x6E6E8080)
    pushCol("ImGui_Col_DragDropTarget", 0xE8C25AFF)
    pushCol("ImGui_Col_NavCursor", 0x2E6E96FF)
    pushCol("ImGui_Col_NavWindowingHighlight", 0xFFFFFFB3)
    pushCol("ImGui_Col_NavWindowingDimBg", 0xCCCCCC33)
    pushCol("ImGui_Col_ModalWindowDimBg", 0xCCCCCC59)

    return vars_pushed, cols_pushed
end


return { ApplyTheme = ApplyTheme }


