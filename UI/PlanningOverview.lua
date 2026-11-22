local _, addon = ...
local L = addon.L
local windows = {}
function addon.ShowPlanningOverview(getModel, openStop, slot)
    slot = slot or "live"
    local window = windows[slot]
    if not window then
        window = addon.UI.CreateUtilityPanel(600, 564, L.PlanningOverview)
        window.hubStandalone = slot ~= "live"
        windows[slot] = window
        window.comparison = addon.UI.CreateLabel(window, "GameFontHighlightSmall")
        window.comparison:SetPoint("TOPLEFT", 18, -48)
        window.comparison:SetPoint("TOPRIGHT", -18, -48)
        window.comparison:SetJustifyH("LEFT")
        window.comparison:SetMaxLines(5)
        addon.UI.BindTooltip(window, function()
            return L.PlanningView, (window.model and window.model.comparison or L.ComparisonUnavailable)
                .. "\n" .. (window.summary and window.summary:GetText() or "")
        end)
        function window:SelectMode(mode)
            self.modePages = self.modePages or {}
            if self.mode then self.modePages[self.mode] = self.page end
            self.mode, self.page = mode, self.modePages[mode] or 1 self:Refresh()
        end
        window.modeSelector = addon.UI.CreateUtilityButton(window, "", 564, function()
            if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
            MenuUtil.CreateContextMenu(window.modeSelector, function(_, menu)
                menu:CreateTitle(L.PlanningView)
                menu:SetScrollMode(260)
                for _, entry in ipairs({{"outing", L.PickupRound}, {"areas", L.PickupAreas}, {"bundles", L.SharedQuestStops}, {"turnIns", L.TurnInTour}, {"items", L.SharedItems}, {"chains", L.QuestChains},
                    {"closing", L.BriefClosing}, {"handIns", L.BriefHandInAreas}, {"comparison", L.BriefComparison}, {"progress", L.BriefProgressTitle}}) do
                    local mode = entry[1]
                    menu:CreateButton((window.mode == mode and "[x] " or "") .. entry[2], function() window:SelectMode(mode) end)
                end
            end)
        end)
        window.modeSelector:SetPoint("TOPLEFT", 18, -145)
        addon.UI.BindTooltip(window.modeSelector, function() return L.PlanningView, L.PlanningViewHelp end)
        window.summary = addon.UI.CreateLabel(window, "GameFontHighlightSmall")
        window.summary:SetPoint("TOPLEFT", 18, -178)
        window.summary:SetPoint("TOPRIGHT", -18, -178)
        window.summary:SetJustifyH("LEFT")
        window.summary:SetMaxLines(3)
        window.rows = {}
        for index = 1, 4 do
            local row = addon.UI.CreateUtilityButton(window, "", 564, function() end)
            row:SetHeight(54)
            row:SetPoint("TOPLEFT", 18, -252 - (index - 1) * 60)
            row.textLabel:ClearAllPoints()
            row.textLabel:SetPoint("LEFT", 8, 0)
            row.textLabel:SetPoint("RIGHT", -8, 0)
            row.textLabel:SetJustifyH("LEFT")
            row.textLabel:SetMaxLines(2)
            row:SetScript("OnClick", function(self)
                if self.areaKey or self.back then
                    window.areaKey, window.page = self.areaKey, 1
                    window:Refresh()
                elseif self.handInKey or self.handInBack then
                    window.handInMap, window.page = self.handInKey, 1 window:Refresh()
                elseif self.inspect then
                    addon.ShowTextWindow("comparison", self.detail, L.BriefComparison, L.BriefNoScore)
                elseif self.stop then window.openStop(self.stop) end
            end)
            row.map = addon.UI.CreateUtilityButton(row, L.Map, 48, function()
                if row.stop then window.openStop(row.stop) end
            end)
            row.map:SetPoint("RIGHT", -6, 0)
            row.info = addon.UI.CreateUtilityButton(row, L.DetailsShort, 60, function()
                addon.ShowTextWindow("planningDetail", row.detail or L.BriefXPHelp, L.PlanningOverview, L.AdventureReadOnly)
            end)
            row.info:SetPoint("RIGHT", -60, 0)
            row.textLabel:SetPoint("RIGHT", -128, 0)
            addon.UI.BindTooltip(row, function(self) return self:GetText(), self.detail end)
            window.rows[index] = row
        end
        window.previous = addon.UI.CreateUtilityButton(window, "<", 35, function() window.page = math.max(1, window.page - 1) window:Refresh() end)
        window.previous:SetPoint("BOTTOMLEFT", 18, 16)
        window.next = addon.UI.CreateUtilityButton(window, ">", 35, function() window.page = window.page + 1 window:Refresh() end)
        window.next:SetPoint("BOTTOMRIGHT", -18, 16)
        window.pageLabel = addon.UI.CreateLabel(window, "GameFontHighlightSmall")
        window.pageLabel:SetPoint("BOTTOM", 0, 21)
        window.remember = addon.UI.CreateUtilityButton(window, L.BriefRemember, 270, function()
            if addon.RememberAdvisoryRound then addon.RememberAdvisoryRound() end
        end)
        window.remember:SetPoint("BOTTOMLEFT", 18, 52)
        window.forget = addon.UI.CreateUtilityButton(window, L.BriefForget, 270, function()
            if addon.ForgetAdvisoryRound then addon.ForgetAdvisoryRound() end
        end)
        window.forget:SetPoint("BOTTOMRIGHT", -18, 52)
        window.export = addon.UI.CreateUtilityButton(window, L.BriefReportAction, 564, function()
            if addon.ExportDecisionExplanation then addon.ExportDecisionExplanation() end
        end)
        window.export:SetPoint("BOTTOMLEFT", 18, 52)
        window.buildOuting = addon.UI.CreateUtilityButton(window, L.ExcursionBuild, 564, function()
            if addon.OpenExcursionFromArea then addon.OpenExcursionFromArea(window.mode == "areas" and window.areaKey or nil) end
        end)
        window.buildOuting:SetPoint("BOTTOMLEFT", 18, 52)
        addon.UI.BindTooltip(window.buildOuting, function() return L.ExcursionBuild, L.ExcursionHelp end)
        addon.UI.BindTooltip(window.remember, function() return L.BriefRemember, L.BriefRoundHelp end)
        function window:Refresh()
            local model = self.getModel() or {}
            self.model = model
            self.comparison:SetText(model.comparison or L.ComparisonUnavailable)
            local tour = model.turnInTour or {stops = {}}
            local entries = self.mode == "bundles" and (model.bundles or {}) or tour.stops
            if self.mode == "items" then entries = model.sharedItems or {} end
            if self.mode == "chains" then entries = model.chains or {} end
            local pickupRows, pickupSummary
            if self.mode == "areas" or self.mode == "outing" then
                pickupRows, pickupSummary = addon.PickupPlanView.Rows(model.pickupPlanning, self.mode, self.areaKey)
                entries = pickupRows
            end
            if self.mode == "closing" or self.mode == "handIns" or self.mode == "comparison" or self.mode == "progress" then
                pickupRows, pickupSummary = addon.DecisionPlanView.Rows(model, self.mode, self.handInMap)
                entries = pickupRows
            end
            local names = {bundles = L.SharedQuestStops, turnIns = L.TurnInTour, items = L.SharedItems, chains = L.QuestChains,
                areas = L.PickupAreas, outing = L.PickupRound, closing = L.BriefClosing, handIns = L.BriefHandInAreas,
                comparison = L.BriefComparison, progress = L.BriefProgressTitle}
            self.modeSelector:SetText(L.PlanningView .. ": " .. (names[self.mode] or L.SharedQuestStops) .. " (" .. #entries .. ") v")
            local pages = math.max(1, math.ceil(#entries / 4))
            self.page = math.min(self.page, pages)
            local summary = self.mode == "bundles" and L.SharedStopsHelp or L.TourSummary:format(#entries, tour.total or 0, tour.xp or 0)
            if self.mode == "turnIns" then
                if tour.levelUpAt then summary = summary .. "\n" .. L.TourLevelUp:format(tour.levelUpAt) end
                if (tour.unknown or 0) + (tour.omitted or 0) > 0 then summary = summary .. "\n" .. L.TourOmitted:format((tour.unknown or 0) + (tour.omitted or 0)) end
                if (tour.unknownXP or 0) > 0 then summary = summary .. " · " .. L.TourUnknownXP:format(tour.unknownXP) end
            end
            if self.mode == "items" then summary = L.SharedItemsHelp end
            if self.mode == "chains" then summary = L.ChainForecast end
            if pickupSummary then summary = pickupSummary end
            self.summary:SetText(summary)
            if model.capacity and model.capacity.full then self.summary:SetText(L.QuestLogFull .. "\n" .. summary) end
            if model.capacity and model.capacity.reserveNeeded and not model.capacity.full then
                self.summary:SetText(L.ReserveQuestSlot .. "\n" .. summary)
            end
            self.remember:SetShown(slot == "live" and self.mode == "progress")
            self.forget:SetShown(slot == "live" and self.mode == "progress")
            self.export:SetShown(slot == "live" and self.mode == "comparison")
            self.buildOuting:SetShown(slot == "live" and (self.mode == "outing" or self.mode == "areas" and self.areaKey ~= nil))
            self.buildOuting:SetEnabled(model.pickupPlanning and #(model.pickupPlanning.areas or {}) > 0 or false)
            self.remember:SetEnabled(model.pickupPlanning and #(model.pickupPlanning.outing or {}) > 0 or false)
            for index, row in ipairs(self.rows) do
                local entry = entries[(self.page - 1) * 4 + index]
                row:SetShown(entry ~= nil)
                row.stop, row.detail, row.areaKey, row.back, row.handInKey, row.handInBack = nil, nil, nil, nil, nil, nil
                row.inspect = nil
                if entry and pickupRows then
                    row.stop, row.detail, row.areaKey, row.back = entry.stop, entry.detail, entry.areaKey, entry.back
                    row.handInKey, row.handInBack = entry.handInKey, entry.handInBack
                    row.inspect = entry.inspect
                    row:SetText(entry.text)
                elseif entry and self.mode == "bundles" then
                    local names = {}
                    for _, item in ipairs(entry.entries) do names[#names + 1] = addon.UI.FormatQuestTitle(item.quest) end
                    row.stop = {quest = entry.entries[1].quest, target = entry.target, action = "objective"}
                    row:SetText(L.SharedStopCount:format(#entry.entries) .. " · " .. addon.UI.FormatDistance(entry) .. "\n" .. table.concat(names, ", "))
                    row.detail = table.concat(names, "\n") .. "\n" .. L.SharedStopsHelp
                elseif entry and self.mode == "items" then
                    local amount = entry.remaining and L.SharedRemaining:format(entry.remaining) or L.SharedInventoryUnknown
                    row:SetText(entry.name .. "\n" .. L.SharedRequired:format(entry.required, #entry.quests) .. " · " .. amount)
                    local lines = {L.SharedItemsHelp}
                    for _, contribution in ipairs(entry.quests) do lines[#lines + 1] = (contribution.quest.title or L.QuestNumber:format(contribution.quest.id)) .. ": " .. contribution.required end
                    if entry.owned then lines[#lines + 1] = L.SharedOwned:format(entry.owned) end
                    row.detail = table.concat(lines, "\n")
                elseif entry and self.mode == "chains" then
                    row.stop, row.detail = entry.stop, entry.detail
                    row:SetText(addon.UI.FormatQuestTitle(entry.quest) .. "\n" .. (entry.known and entry.summary or L.UnknownFollowUps))
                elseif entry then
                    row.stop = entry
                    row:SetText(((self.page - 1) * 4 + index) .. ". " .. addon.UI.FormatQuestTitle(entry.quest) .. "\n"
                        .. L.TourLeg:format(entry.leg or 0) .. " · " .. (entry.xp and L.QuestXPReward:format(entry.xp) or L.UnknownXP))
                end
                row.map:SetShown(entry ~= nil and row.stop ~= nil and row.stop.target ~= nil)
            end
            self.previous:SetEnabled(self.page > 1)
            self.next:SetEnabled(self.page < pages)
            self.previous:SetShown(pages > 1) self.next:SetShown(pages > 1)
            self.pageLabel:SetText(#entries > 0 and (self.page .. " / " .. pages) or L.NoPlanningStops)
        end
        window:SetScript("OnUpdate", function(self, elapsed)
            self.elapsed = (self.elapsed or 0) + elapsed
            if self.elapsed >= 1 then self.elapsed = 0 self:Refresh() end
        end)
    end
    window.getModel, window.openStop = getModel, openStop
    window.mode, window.page = window.mode or "bundles", window.page or 1
    window:Refresh()
    if not window.hasOpened and #(window.model.bundles or {}) == 0 and window.model.turnInTour and #window.model.turnInTour.stops > 1 then
        window.mode = "turnIns"
        window:Refresh()
    end
    window.hasOpened = true
    addon.UI.ShowUtilityPanel(window)
    return window
end
