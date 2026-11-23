local _, addon = ...
local dialogs = {}

function addon.ShowTextWindow(key, text, title, hintText)
    local dialog = dialogs[key]
    if not dialog then
        dialog = addon.UI.CreateWindow(570, 420, title, {hub = false})
        local heading = dialog.heading
        local hint = addon.UI.CreateLabel(dialog, "GameFontHighlightSmall")
        hint:SetPoint("TOPLEFT", 16, -40)
        hint:SetPoint("TOPRIGHT", -16, -40)
        hint:SetJustifyH("LEFT")
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
    if dialog.Raise then dialog:Raise() end
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
