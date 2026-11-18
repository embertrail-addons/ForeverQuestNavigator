local _, addon = ...
local dialogs = {}

function addon.ShowTextWindow(key, text, title, hintText)
    local dialog = dialogs[key]
    if not dialog then
        dialog = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
        dialog:SetSize(570, 420)
        dialog:SetPoint("CENTER")
        dialog:SetFrameStrata("DIALOG")
        dialog:SetClampedToScreen(true)
        dialog:SetMovable(true)
        dialog:EnableMouse(true)
        dialog:RegisterForDrag("LeftButton")
        dialog:SetScript("OnDragStart", dialog.StartMoving)
        dialog:SetScript("OnDragStop", dialog.StopMovingOrSizing)
        dialog:SetBackdrop({ bgFile = "Interface/Buttons/WHITE8X8", edgeFile = "Interface/Buttons/WHITE8X8", edgeSize = 1 })
        addon.UI.Theme.WatchFrame(dialog)
        local heading = addon.UI.CreateLabel(dialog, "GameFontNormal")
        heading:SetPoint("TOPLEFT", 16, -14)
        heading:SetPoint("TOPRIGHT", -45, -14)
        heading:SetJustifyH("LEFT")
        local hint = addon.UI.CreateLabel(dialog, "GameFontHighlightSmall")
        hint:SetPoint("TOPLEFT", 16, -40)
        hint:SetPoint("TOPRIGHT", -16, -40)
        hint:SetJustifyH("LEFT")
        local close = addon.UI.MakeButton(dialog)
        close:SetSize(25, 24)
        close:SetPoint("TOPRIGHT", -8, -8)
        close:SetText("X")
        close:SetScript("OnClick", function() dialog:Hide() end)
        local scroll = CreateFrame("ScrollFrame", nil, dialog, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", 0, -12)
        scroll:SetPoint("BOTTOMRIGHT", -36, 16)
        local edit = CreateFrame("EditBox", nil, scroll)
        edit:SetMultiLine(true)
        edit:SetAutoFocus(false)
        edit:SetFontObject("ChatFontNormal")
        edit:SetWidth(510)
        edit:SetScript("OnEscapePressed", function() dialog:Hide() end)
        scroll:SetScrollChild(edit)
        dialog.edit, dialog.scroll, dialog.heading, dialog.hint = edit, scroll, heading, hint
        dialogs[key] = dialog
    end
    dialog.heading:SetText(title)
    dialog.hint:SetText(hintText)
    dialog:Show()
    dialog.edit:SetText(text)
    dialog.edit:SetFocus()
    dialog.edit:HighlightText()
    dialog.scroll:SetVerticalScroll(0)
end

function addon.ShowDiagnosticReport(text)
    addon.ShowTextWindow("diagnostic", text, addon.L.DebugTitle, addon.L.DebugCopyHint)
end

function addon.ShowPositionReport(text)
    addon.ShowTextWindow("position", text, addon.L.PositionReportTitle, addon.L.PositionReportHint)
end
