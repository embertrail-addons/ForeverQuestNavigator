local _, addon = ...
local L = addon.L
local window
local groups = {
    {key = "plan", modes = {"departure", "compare", "chains"}},
    {key = "travel", modes = {"along", "blocked", "bags", "group"}},
    {key = "manage", modes = {"later", "hiddenOffers", "changes", "level", "corrections"}},
}
function addon.ShowAdventure(getModel, actions, mode)
    if not window then
        window = addon.UI.CreateUtilityPanel(600, 610, L.AdventureTitle)
        window.hubPage = "adventure"
        window.tabs = {}
        function window:SelectMode(key)
            self.pages[self.mode or "departure"] = self.page or 1
            for _, group in ipairs(groups) do for _, modeKey in ipairs(group.modes) do
                if modeKey == key then self.group = group self.lastMode[group.key] = key end
            end end
            self.mode, self.page = key, self.pages[key] or 1 self:Refresh()
        end
        window.lastMode = {}
        for index, group in ipairs(groups) do
            local tab = addon.UI.CreateUtilityButton(window, L["JourneyGroup_" .. group.key], 180, function()
                window:SelectMode(window.lastMode[group.key] or group.modes[1])
            end)
            tab:SetPoint("TOPLEFT", 18 + (index - 1) * 188, -48)
            tab:SetHeight(32) tab.textLabel:SetMaxLines(2)
            window.tabs[group.key] = tab
        end
        window.selector = addon.UI.CreateUtilityButton(window, "", 480, function()
            local group = window.group or groups[1]
            if MenuUtil and MenuUtil.CreateContextMenu then MenuUtil.CreateContextMenu(window.selector, function(_, menu)
                menu:CreateTitle(L["JourneyGroup_" .. group.key])
                for _, key in ipairs(group.modes) do local modeKey = key
                    menu:CreateButton((key == window.mode and "[x] " or "") .. L["Adventure_" .. key], function() window:SelectMode(modeKey) end)
                end
            end)
            else
                for i, key in ipairs(group.modes) do if key == window.mode then window:SelectMode(group.modes[i % #group.modes + 1]) break end end
            end
        end)
        window.selector:SetPoint("TOPLEFT", 18, -90)
        window.help = addon.UI.CreateUtilityButton(window, L.DetailsShort, 76, function()
            addon.ShowTextWindow("adventureHelp", window.fullSummary or "", L["Adventure_" .. window.mode], L.AdventureReadOnly)
        end)
        window.help:SetPoint("TOPRIGHT", -18, -90)
        window.summary = addon.UI.CreateLabel(window, "GameFontHighlightSmall")
        window.summary:SetPoint("TOPLEFT", 18, -132) window.summary:SetPoint("TOPRIGHT", -18, -132)
        window.summary:SetJustifyH("LEFT") window.summary:SetMaxLines(3)
        window.empty = addon.UI.CreateLabel(window, "GameFontDisableSmall")
        window.empty:SetPoint("TOPLEFT", 24, -250) window.empty:SetPoint("TOPRIGHT", -24, -250)
        window.empty:SetJustifyH("LEFT") window.empty:SetMaxLines(3) window.empty:SetText(L.JourneyEmpty)
        window.rows = {}
        for index = 1, 4 do
            local row = addon.UI.CreateUtilityButton(window, "", 564, function() end)
            row:SetPoint("TOPLEFT", 18, -245 - (index - 1) * 65) row:SetHeight(60)
            row.textLabel:ClearAllPoints() row.textLabel:SetPoint("LEFT", 8, 0) row.textLabel:SetPoint("RIGHT", -166, 0)
            row.textLabel:SetJustifyH("LEFT") row.textLabel:SetMaxLines(2)
            row:SetScript("OnClick", function(self)
                local e = self.entry
                if e then addon.ShowTextWindow("adventureDetail", e.detail or L.AdventureReadOnly, addon.UI.FormatQuestTitle(e.quest), L.AdventureReadOnly) end
            end)
            row.map = addon.UI.CreateUtilityButton(row, L.Map, 55, function()
                if row.entry then window.actions.map(row.entry) end
            end)
            row.map:SetPoint("RIGHT", -5, 0)
            row.choose = addon.UI.CreateUtilityButton(row, L.ChooseCamp, 90, function()
                if row.entry then
                    if window.mode == "corrections" then window.actions.clearCorrection(row.entry) window:Refresh()
                    elseif window.mode == "along" or window.mode == "compare" or window.mode == "chains" or window.mode == "later" or window.mode == "bags" or window.mode == "hiddenOffers" then
                        window.actions.rowAction(row.entry, window.mode) window:Refresh()
                    else window.actions.select(row.entry.quest.id) end
                end
            end)
            row.choose:SetPoint("RIGHT", -66, 0)
            row.details = addon.UI.CreateUtilityButton(row, L.DetailsShort, 90, function() row:Click() end)
            row.details:SetPoint("RIGHT", -66, 0)
            window.rows[index] = row
        end
        window.primary = addon.UI.CreateUtilityButton(window, "", 564, function()
            if window.mode == "group" then window.actions.toggleGroup()
            elseif window.mode == "changes" then window.actions.reviewChanges()
            elseif window.mode == "level" then window.actions.releaseLevel() end
            if window.mode == "bags" and window.actions.saveVendor then window.actions.saveVendor() end
            window:Refresh()
        end)
        window.primary:SetPoint("BOTTOMLEFT", 18, 60)
        window.previous = addon.UI.CreateUtilityButton(window, "<", 45, function()
            window.page = math.max(1, window.page - 1) window:Refresh()
        end)
        window.previous:SetPoint("BOTTOMLEFT", 18, 16)
        window.next = addon.UI.CreateUtilityButton(window, ">", 45, function() window.page = window.page + 1 window:Refresh() end)
        window.next:SetPoint("BOTTOMRIGHT", -18, 16)
        window.pageText = addon.UI.CreateLabel(window, "GameFontDisableSmall") window.pageText:SetPoint("BOTTOM", 0, 24)
        window.pages = {}
        function window:Refresh()
            local model = self.getModel(self.mode) or {}
            local entries = model.rows or {}
            self.page = math.min(self.page, math.max(1, math.ceil(#entries / 4))) self.pages[self.mode] = self.page
            self.summary:SetText(addon.TrackerPresentation.Summary(model.summary or L.AdventureReadOnly, 2))
            self.fullSummary = model.summary or L.AdventureReadOnly
            local groupHeight = 32
            for key, tab in pairs(self.tabs) do
                tab:SetText((self.group and key == self.group.key and "[x] " or "") .. L["JourneyGroup_" .. key])
                groupHeight = math.max(groupHeight, tab.textLabel:GetStringHeight() + 8)
            end
            for _, tab in pairs(self.tabs) do tab:SetHeight(groupHeight) end
            local selectY = 48 + groupHeight + 8
            self.selector:ClearAllPoints() self.selector:SetPoint("TOPLEFT", 18, -selectY)
            self.help:ClearAllPoints() self.help:SetPoint("TOPRIGHT", -18, -selectY)
            self.selector:SetText(L["Adventure_" .. self.mode] .. " (" .. #entries .. ")  ...")
            self.selector.textLabel:SetMaxLines(2)
            local selectHeight = math.max(28, self.selector.textLabel:GetStringHeight() + 8)
            self.selector:SetHeight(selectHeight) self.help:SetHeight(selectHeight)
            self.summary:ClearAllPoints() self.summary:SetPoint("TOPLEFT", 18, -selectY - selectHeight - 12)
            self.summary:SetPoint("TOPRIGHT", -18, -selectY - selectHeight - 12)
            local rowY = selectY + selectHeight + 24 + self.summary:GetStringHeight()
            self.empty:SetShown(#entries == 0)
            self.empty:ClearAllPoints() self.empty:SetPoint("TOPLEFT", 24, -rowY) self.empty:SetPoint("TOPRIGHT", -24, -rowY)
            local rowHeight = 60
            for index, row in ipairs(self.rows) do
                local e = entries[(self.page - 1) * 4 + index]
                row.entry = e row:SetShown(e ~= nil)
                if e then
                    row:SetText(addon.UI.FormatQuestTitle(e.quest) .. "\n" .. (e.short or addon.UI.FormatDistance(e)))
                    row.map:SetEnabled(e.target ~= nil)
                    row.choose:SetText(self.mode == "hiddenOffers" and L.OfferRestore or self.mode == "corrections" and L.AdventureReset or (self.mode == "later" or self.mode == "bags") and L.JourneyRemove
                        or self.mode == "along" and L.JourneyAdd or self.mode == "compare" and L.TourPreview or self.mode == "chains" and L.JourneyExpand or L.ChooseCamp)
                    row.choose:SetShown(self.mode == "blocked" or self.mode == "level" or self.mode == "corrections"
                        or self.mode == "along" or self.mode == "compare" or self.mode == "later" or self.mode == "hiddenOffers" or self.mode == "bags" and e.vendorIndex ~= nil or self.mode == "chains" and e.chainID ~= nil)
                    row.details:SetShown(not row.choose:IsShown())
                    row.choose.textLabel:SetMaxLines(2) row.details.textLabel:SetMaxLines(2)
                    rowHeight = math.max(rowHeight, row.textLabel:GetStringHeight() + 16)
                end
            end
            for index, row in ipairs(self.rows) do
                row:ClearAllPoints() row:SetPoint("TOPLEFT", 18, -rowY - (index - 1) * (rowHeight + 6)) row:SetHeight(rowHeight)
            end
            self:SetHeight(math.max(420, rowY + math.min(4, math.max(1, #entries)) * (rowHeight + 6) + 110))
            local label = self.mode == "group" and (model.enabled and L.AdventureGroupOff or L.AdventureGroupOn)
                or self.mode == "changes" and L.AdventureReviewChange or self.mode == "level" and L.AdventureRecalculate
                or self.mode == "bags" and model.canSaveVendor and L.JourneySaveVendor
            self.primary:SetText(label or "") self.primary:SetShown(label ~= nil)
            self.primary:SetEnabled(self.mode ~= "changes" or #entries > 0)
            self.previous:SetEnabled(self.page > 1) self.next:SetEnabled(self.page * 4 < #entries)
            self.previous:SetShown(#entries > 4) self.next:SetShown(#entries > 4)
            self.pageText:SetText(#entries == 0 and L.NoPlanningStops or self.page .. " / " .. math.ceil(#entries / 4))
        end
        addon.UI.RefreshWhileShown(window, 1)
    end
    window.getModel, window.actions = getModel, actions
    window:SelectMode(mode or window.mode or "departure") addon.UI.ShowUtilityPanel(window, "adventure")
    return window
end
