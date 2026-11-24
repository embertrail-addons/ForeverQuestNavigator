local _, addon = ...
local L = addon.L
local window
function addon.ShowAccessRouteEditor(actions)
    if not window then
        window = addon.UI.CreateUtilityPanel(650, 480, L.AccessRouteEditor)
        window.help = addon.UI.CreateLabel(window, "GameFontHighlightSmall")
        window.help:SetPoint("TOPLEFT", 18, -44) window.help:SetPoint("TOPRIGHT", -18, -44)
        window.help:SetJustifyH("LEFT") window.help:SetMaxLines(3) window.help:SetText(L.AccessRouteHelp)
        window.rows = {}
        for index = 1, 5 do
            local row = CreateFrame("Frame", nil, window)
            row:SetPoint("TOPLEFT", 18, -115 - (index - 1) * 57)
            row:SetPoint("TOPRIGHT", -18, -115 - (index - 1) * 57)
            row:SetHeight(50)
            row.label = addon.UI.CreateLabel(row, "GameFontHighlightSmall")
            row.label:SetPoint("TOPLEFT") row.label:SetPoint("TOPRIGHT", -240, 0)
            row.label:SetJustifyH("LEFT") row.label:SetMaxLines(2)
            row:EnableMouse(true)
            addon.UI.BindTooltip(row, function(self) return self.label:GetText(), L.AccessRouteHelp end)
            row.up = addon.UI.CreateUtilityButton(row, "^", 28, function() window.actions.move(row.step, -1) window:Refresh() end)
            row.up:SetPoint("RIGHT", -202, 0)
            row.down = addon.UI.CreateUtilityButton(row, "v", 28, function() window.actions.move(row.step, 1) window:Refresh() end)
            row.down:SetPoint("RIGHT", -170, 0)
            row.map = addon.UI.CreateUtilityButton(row, L.Map, 70, function() window.actions.map(row.point) end)
            row.map:SetPoint("RIGHT", -88, 0)
            row.remove = addon.UI.CreateUtilityButton(row, L.DeleteAccess, 80, function() window.actions.remove(row.step) window:Refresh() end)
            row.remove:SetPoint("RIGHT")
            row.note = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
            row.note:SetSize(320, 20) row.note:SetPoint("BOTTOMLEFT", 5, 0)
            row.note:SetAutoFocus(false) row.note:SetMaxLetters(240)
            row.note:SetScript("OnEnterPressed", function(self)
                if window.actions.note then window.actions.note(row.step, self:GetText()) end
                self:ClearFocus() window:Refresh()
            end)
            row.note:SetScript("OnEscapePressed", function(self) self:ClearFocus() window:Refresh() end)
            addon.UI.BindTooltip(row.note, function() return L.AccessNoteHelp end)
            addon.UI.BindTooltip(row.up, function() return L.MoveAccessEarlier end)
            addon.UI.BindTooltip(row.down, function() return L.MoveAccessLater end)
            window.rows[index] = row
        end
        window.previous = addon.UI.CreateUtilityButton(window, "^", 32, function() end)
        window.previous:SetPoint("BOTTOMLEFT", 18, 14)
        window.next = addon.UI.CreateUtilityButton(window, "v", 32, function() end)
        window.next:SetPoint("BOTTOMRIGHT", -18, 14)
        window.count = addon.UI.CreateLabel(window, "GameFontHighlightSmall")
        window.count:SetPoint("BOTTOM", 0, 48)
        window.undo = addon.UI.CreateUtilityButton(window, L.UndoLatest, 240, function() addon.UndoLastChange() window:Refresh() end)
        window.undo:SetPoint("BOTTOM", 0, 14)
        local paging = addon.UI.ScrollPaging(window, window.rows, function() window:Refresh() end)
        function window:Refresh()
            local points = self.actions.list()
            local offset = paging:Clamp(#points)
            for index, row in ipairs(self.rows) do
                local step = offset + index
                row.step, row.point = step, points[step]
                row:SetShown(row.point ~= nil)
                if row.point then
                    row.note:SetText(row.point.note or "")
                    local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(row.point.mapID)
                    row.label:SetText(step .. ". " .. (info and info.name or L.UnknownZone) .. (" (%.1f, %.1f)"):format(row.point.x * 100, row.point.y * 100))
                    row.up:SetEnabled(step > 1) row.down:SetEnabled(step < #points)
                end
            end
            local count = paging:Update(#points)
            self.count:SetText(L.AccessStepCount:format(#points, 8) .. (count and (" · " .. count) or ""))
            self.undo:SetEnabled(addon.Undo ~= nil and #addon.Undo.entries > 0)
        end
    end
    window.actions, window.offset = actions, 0
    window:Refresh() addon.UI.ShowUtilityPanel(window)
end
function addon.RefreshAccessRouteEditor() if window and window:IsShown() then window:Refresh() end end
