local _, addon = ...
local L = addon.L
local historyWindow, levelNotice
function addon.ShowUndoHistory(history)
    if not historyWindow then
        local frame = addon.UI.CreateUtilityPanel(570, 360, L.ChangeHistory)
        historyWindow = frame
        frame.help = addon.UI.CreateLabel(frame, "GameFontHighlightSmall")
        frame.help:SetPoint("TOPLEFT", 18, -48) frame.help:SetPoint("TOPRIGHT", -18, -48)
        frame.help:SetJustifyH("LEFT") frame.help:SetMaxLines(3) frame.help:SetText(L.UndoScope)
        frame.list = addon.UI.CreateLabel(frame, "GameFontHighlightSmall")
        frame.list:SetPoint("TOPLEFT", 18, -110) frame.list:SetPoint("TOPRIGHT", -18, -110)
        frame.list:SetJustifyH("LEFT") frame.list:SetMaxLines(8)
        frame.status = addon.UI.CreateLabel(frame, "GameFontDisableSmall")
        frame.status:SetPoint("BOTTOMLEFT", 18, 64) frame.status:SetPoint("BOTTOMRIGHT", -18, 64)
        frame.status:SetJustifyH("LEFT") frame.status:SetMaxLines(2)
        frame.undo = addon.UI.CreateUtilityButton(frame, L.UndoLatest, 250, function()
            local ok, label = frame.history:Undo()
            frame.status:SetText(ok and (L.UndoDone .. ": " .. label) or label) frame:Refresh()
        end)
        frame.undo:SetPoint("BOTTOMLEFT", 18, 18)
        frame.discard = addon.UI.CreateUtilityButton(frame, L.DiscardUndo, 250, function() frame.history:Discard() frame:Refresh() end)
        frame.discard:SetPoint("BOTTOMRIGHT", -18, 18)
        function frame:Refresh()
            local lines = {}
            for index = #self.history.entries, math.max(1, #self.history.entries - 6), -1 do
                lines[#lines + 1] = (#lines + 1) .. ". " .. self.history.entries[index].label
            end
            self.list:SetText(#lines > 0 and table.concat(lines, "\n") or L.UndoEmpty)
            self.undo:SetEnabled(#lines > 0) self.discard:SetEnabled(#lines > 0)
        end
    end
    historyWindow.history = history historyWindow:Refresh() historyWindow:Show()
end
function addon.RefreshUndoHistory()
    if historyWindow and historyWindow:IsShown() then historyWindow:Refresh() end
end
function addon.ShowLevelNotice(count, open, anchor)
    if not levelNotice then
        levelNotice = addon.UI.MakeButton(UIParent)
        levelNotice:SetHeight(26) levelNotice:SetClampedToScreen(true) levelNotice:SetFrameStrata("DIALOG")
        levelNotice:SetScript("OnUpdate", function(self, elapsed)
            self.remaining = self.remaining - elapsed
            if self.remaining <= 0 then self:Hide() end
        end)
        levelNotice:SetScript("OnClick", function(self) self:Hide() self.open() end)
        addon.UI.BindTooltip(levelNotice, function() return L.LevelBetterHelp end)
    end
    levelNotice.open, levelNotice.remaining = open, 15
    levelNotice:SetWidth(math.max(300, anchor:GetWidth())) levelNotice:ClearAllPoints()
    levelNotice:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -4)
    levelNotice:SetText(count == 1 and L.LevelBetterOne or L.LevelBetterCount:format(count)) levelNotice:Show()
end
function addon.HideLevelNotice() if levelNotice then levelNotice:Hide() end end
