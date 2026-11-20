local _, addon = ...
local L = addon.L
local transferWindow, detourWindow
local function Edit(parent, width, height, multiline)
    local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    box:SetSize(width, height) box:SetAutoFocus(false) box:SetMultiLine(multiline == true)
    box:SetFontObject("GameFontHighlightSmall")
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    return box
end
function addon.ShowDisplayTransfer(settings, catalog)
    if not transferWindow then
        local frame = addon.UI.CreateUtilityPanel(630, 600, L.DisplayTransfer)
        transferWindow = frame
        frame.help = addon.UI.CreateLabel(frame, "GameFontHighlightSmall")
        frame.help:SetPoint("TOPLEFT", 18, -44) frame.help:SetPoint("TOPRIGHT", -18, -44)
        frame.help:SetJustifyH("LEFT") frame.help:SetMaxLines(3) frame.help:SetText(L.TransferHelp)
        local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 22, -110) scroll:SetSize(565, 205)
        frame.input = Edit(scroll, 550, 205, true) scroll:SetScrollChild(frame.input)
        frame.input:SetMaxLetters(4096)
        frame.input:SetScript("OnTextChanged", function() frame.changes = nil frame.apply:SetEnabled(false) end)
        frame.preview = addon.UI.CreateLabel(frame, "GameFontHighlightSmall")
        frame.preview:SetPoint("TOPLEFT", 18, -330) frame.preview:SetPoint("TOPRIGHT", -18, -330)
        frame.preview:SetJustifyH("LEFT") frame.preview:SetMaxLines(13)
        frame.export = addon.UI.CreateUtilityButton(frame, L.ExportDisplay, 180, function()
            frame.input:SetText(addon.DisplayTransfer.Export(frame.settings))
            frame.input:SetFocus() frame.input:HighlightText() frame.preview:SetText(L.TransferExported)
        end)
        frame.export:SetPoint("BOTTOMLEFT", 18, 18)
        frame.inspect = addon.UI.CreateUtilityButton(frame, L.PreviewImport, 180, function()
            local values = addon.DisplayTransfer.Parse(frame.input:GetText())
            frame.changes = values and addon.DisplayTransfer.Changes(values, frame.settings, frame.catalog)
            local lines = {}
            for _, change in ipairs(frame.changes or {}) do
                lines[#lines + 1] = change.name .. ": " .. tostring(change.before) .. " -> " .. tostring(change.after)
            end
            frame.preview:SetText(not values and L.TransferInvalid or #lines == 0 and L.NoProfileChanges or table.concat(lines, "\n"))
            frame.apply:SetEnabled(frame.changes ~= nil and #frame.changes > 0)
        end)
        frame.inspect:SetPoint("BOTTOM", 0, 18)
        frame.apply = addon.UI.CreateUtilityButton(frame, L.ApplyProfile, 200, function()
            local ok = frame.changes and addon.DisplayTransfer.Apply(frame.changes, frame.settings, addon.Undo)
            frame.changes = nil frame.apply:SetEnabled(false)
            frame.preview:SetText(ok and L.TransferApplied or L.TransferStale)
        end)
        frame.apply:SetPoint("BOTTOMRIGHT", -18, 18)
    end
    transferWindow.settings, transferWindow.catalog = settings, catalog
    transferWindow.changes = nil transferWindow.apply:SetEnabled(false)
    transferWindow.input:SetText(addon.DisplayTransfer.Export(settings))
    transferWindow.preview:SetText("") addon.UI.ShowUtilityPanel(transferWindow)
end

function addon.ShowDetourTools(actions)
    if not detourWindow then
        local frame = addon.UI.CreateUtilityPanel(590, 340, L.TemporaryDetour)
        detourWindow = frame
        local help = addon.UI.CreateLabel(frame, "GameFontHighlightSmall")
        help:SetPoint("TOPLEFT", 18, -48) help:SetPoint("TOPRIGHT", -18, -48)
        help:SetJustifyH("LEFT") help:SetMaxLines(4) help:SetText(L.DetourHelp)
        frame.inputs = {}
        for index, label in ipairs({L.DetourMapID, "X (%)", "Y (%)", L.DetourName}) do
            local text = addon.UI.CreateLabel(frame, "GameFontHighlightSmall")
            text:SetPoint("TOPLEFT", 20, -125 - (index - 1) * 30) text:SetText(label)
            local box = Edit(frame, 340, 24)
            box:SetPoint("TOPLEFT", 200, -120 - (index - 1) * 30)
            box:SetMaxLetters(index == 4 and 120 or 12)
            frame.inputs[index] = box
        end
        frame.status = addon.UI.CreateLabel(frame, "GameFontHighlightSmall")
        frame.status:SetPoint("BOTTOMLEFT", 18, 62) frame.status:SetPoint("BOTTOMRIGHT", -18, 62)
        frame.status:SetJustifyH("LEFT") frame.status:SetMaxLines(2)
        frame.start = addon.UI.CreateUtilityButton(frame, L.DetourStart, 175, function()
            local point = addon.TemporaryDetour.New(frame.inputs[1]:GetText(),
                (tonumber(frame.inputs[2]:GetText()) or -100) / 100,
                (tonumber(frame.inputs[3]:GetText()) or -100) / 100, frame.inputs[4]:GetText())
            local ok = point and frame.actions.start(point)
            frame.status:SetText(ok and L.DetourActive or L.DetourInvalid)
        end)
        frame.start:SetPoint("BOTTOMLEFT", 18, 18)
        frame.map = addon.UI.CreateUtilityButton(frame, L.Map, 130, function() frame.actions.map() end)
        frame.map:SetPoint("BOTTOM", 0, 18)
        frame.cancel = addon.UI.CreateUtilityButton(frame, L.DetourCancel, 200, function()
            frame.actions.cancel() frame.status:SetText(L.DetourReturned)
        end)
        frame.cancel:SetPoint("BOTTOMRIGHT", -18, 18)
    end
    detourWindow.actions = actions
    local point = actions.current()
    if point then
        detourWindow.inputs[1]:SetText(tostring(point.mapID))
        detourWindow.inputs[2]:SetText(("%.2f"):format(point.x * 100))
        detourWindow.inputs[3]:SetText(("%.2f"):format(point.y * 100))
        detourWindow.inputs[4]:SetText(point.name or "")
    end
    detourWindow.status:SetText(actions.active() and L.DetourActive or "") addon.UI.ShowUtilityPanel(detourWindow)
end
