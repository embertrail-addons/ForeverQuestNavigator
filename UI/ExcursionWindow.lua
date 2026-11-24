local _, addon = ...
local L = addon.L
local window
local choicesWindow
function addon.UI.ShowOfferChoices(owner, choose)
    local choices = {{"once", L.OfferSkip}, {"later", L.OfferLater}, {"hide", L.OfferHide}}
    if MenuUtil and MenuUtil.CreateContextMenu then
        MenuUtil.CreateContextMenu(owner, function(_, menu)
            menu:CreateTitle(L.OfferChoices)
            for _, entry in ipairs(choices) do local mode = entry[1] menu:CreateButton(entry[2], function() choose(mode) end) end
        end)
    else
        if not choicesWindow then
            choicesWindow = addon.UI.CreateUtilityPanel(390, 210, L.OfferChoices)
            choicesWindow.hubStandalone = true choicesWindow.rows = {}
            for index, entry in ipairs(choices) do local mode = entry[1]
                local button = addon.UI.CreateUtilityButton(choicesWindow, entry[2], 354, function()
                    choicesWindow.choose(mode) choicesWindow:Hide()
                end)
                button:SetPoint("TOPLEFT", 18, -50 - (index - 1) * 46) button:SetHeight(38)
                button.textLabel:SetMaxLines(2) choicesWindow.rows[index] = button
            end
        end
        choicesWindow.choose = choose addon.UI.ShowUtilityPanel(choicesWindow)
        return choicesWindow
    end
end
function addon.ShowExcursion(plan, actions)
    if not window then
        window = addon.UI.CreateUtilityPanel(610, 555, L.ExcursionTitle)
        window.hubPage = "outing"
        window.summary = addon.UI.CreateLabel(window, "GameFontHighlightSmall")
        window.summary:SetPoint("TOPLEFT", 18, -48) window.summary:SetPoint("TOPRIGHT", -18, -48)
        window.summary:SetJustifyH("LEFT") window.summary:SetMaxLines(3)
        window.rows = {}
        for index = 1, 6 do
            local row = addon.UI.CreateUtilityButton(window, "", 574, function() end)
            row:SetPoint("TOPLEFT", 18, -120 - (index - 1) * 50) row:SetHeight(44)
            row.textLabel:ClearAllPoints() row.textLabel:SetPoint("LEFT", 8, 0) row.textLabel:SetPoint("RIGHT", -8, 0)
            row.textLabel:SetJustifyH("LEFT") row.textLabel:SetMaxLines(2)
            row:SetScript("OnClick", function(self) if self.stop then window.actions.map(self.stop) end end)
            row.skip = addon.UI.CreateUtilityButton(row, L.OfferSkip, 92, function()
                if row.stop then local ok, message = window.actions.skip(row.stop.quest.id, "once") window.status = message window:Refresh() end
            end)
            row.skip:SetPoint("RIGHT", -35, 0) row.skip.textLabel:SetMaxLines(2)
            row.choices = addon.UI.CreateUtilityButton(row, "...", 26, function(self)
                if not row.stop then return end
                local id, perform = row.stop.quest.id, window.actions.skip
                addon.UI.ShowOfferChoices(self, function(mode) local ok, message = perform(id, mode) window.status = message window:Refresh() end)
            end)
            row.choices:SetPoint("RIGHT", -4, 0)
            addon.UI.BindTooltip(row, function(self)
                local prep = self.stop and addon.QuestPreparation.Describe(self.stop.quest.preparation, self.stop.quest.group)
                return self:GetText(), (prep and prep ~= "" and (prep .. "\n") or "") .. L.ExcursionHelp
            end)
            window.rows[index] = row
        end
        window.previous = addon.UI.CreateUtilityButton(window, "^", 32, function() end)
        window.previous:SetPoint("BOTTOMRIGHT", -60, 120)
        window.next = addon.UI.CreateUtilityButton(window, "v", 32, function() end)
        window.next:SetPoint("BOTTOMRIGHT", -18, 120)
        window.dismiss = addon.UI.CreateUtilityButton(window, L.RoundDismiss, 280, function()
            if window.actions.dismiss then window.actions.dismiss() end
            window:Hide()
        end)
        window.dismiss:SetPoint("BOTTOMLEFT", 18, 120)
        window.budget = addon.UI.CreateUtilityButton(window, "", 280, function()
            local current = window.plan.budget or 0
            local value = current == 0 and 15 or current == 15 and 30 or current == 30 and 60 or 0
            if window.actions.budget then window.actions.budget(value, window.plan.excludedOffers) end
        end)
        window.budget:SetPoint("BOTTOMLEFT", 18, 120)
        window.timeHelp = addon.UI.CreateUtilityButton(window, L.DetailsShort, 75, function()
            addon.ShowTextWindow("timeBudget", L.AdventureTimeHelp, L.AdventureTimeTitle, L.AdventureReadOnly)
        end)
        window.timeHelp:SetPoint("LEFT", window.budget, "RIGHT", 8, 0)
        window.start = addon.UI.CreateUtilityButton(window, L.ExcursionStart, 280, function()
            local ok, message = window.actions.start(window.plan)
            window.status = message window:Refresh()
        end)
        window.start:SetPoint("BOTTOMLEFT", 18, 16)
        window.pause = addon.UI.CreateUtilityButton(window, L.ExcursionPause, 280, function()
            window.actions.pause() window:Refresh()
        end)
        window.pause:SetPoint("BOTTOMRIGHT", -18, 16)
        window.info = addon.UI.CreateLabel(window, "GameFontDisableSmall")
        window.info:SetPoint("BOTTOMLEFT", 18, 50) window.info:SetPoint("BOTTOMRIGHT", -18, 50)
        window.info:SetMaxLines(4) window.info:SetJustifyH("LEFT")
        window.undo = addon.UI.CreateUtilityButton(window, L.OfferUndoShort, 120, function()
            local ok, message = window.actions.undo()
            window.status = ok and L.UndoDone or message window:Refresh()
        end)
        window.undo:SetPoint("BOTTOMRIGHT", -18, 50)
        window.paging = addon.UI.ScrollPaging(window, window.rows, function() window:Refresh() end)
        function window:Refresh()
            local p = self.plan
            local offset = self.paging:Clamp(#p.stops)
            -- Only name what matters: zero counts are left out.
            local parts = {(#p.stops == 1 and L.ExcursionStopOne or L.ExcursionStopMany):format(#p.stops), L.ExcursionKnownXP:format(p.xp or 0)}
            if (p.unknownXP or 0) > 0 then parts[#parts + 1] = L.ExcursionUnknownRewards:format(p.unknownXP) end
            if (p.missing or 0) > 0 then parts[#parts + 1] = L.ExcursionUnplanned:format(p.missing) end
            self.summary:SetText(table.concat(parts, " · "))
            if (p.omittedPickups or 0) > 0 then self.summary:SetText(self.summary:GetText() .. "\n" .. L.MixedDetourOmitted:format(p.omittedPickups)) end
            if p.budget then self.summary:SetText(L.AdventureTimeRange:format(p.lowerMinutes, p.upperMinutes, p.budget, p.omitted)
                .. "\n" .. self.summary:GetText()) end
            self.budget:SetText(L.AdventureBudget:format(p.budget or 0))
            self.budget:SetShown(not p.started and self.actions.budget ~= nil)
            self.timeHelp:SetShown(not p.started and self.actions.budget ~= nil)
            local review = addon.ExcursionPlan.Review(p)
            if review then
                self.summary:SetText(L.RoundSummary:format(review.completed, review.xp, review.remaining)
                    .. (review.unknownXP > 0 and ("\n" .. L.RoundUnknownXP:format(review.unknownXP)) or ""))
            end
            self.dismiss:SetShown(review ~= nil and not p.running)
            self.info:SetText(self.status or p.status or L.ExcursionHelp)
            if p.mixed and not p.started and not self.status then self.info:SetText(p.orderKnown and L.MixedRouteHelp or L.MixedUnknownRoute) end
            self.undo:SetShown(self.actions.canUndo and self.actions.canUndo() or false)
            self.info:SetPoint("BOTTOMRIGHT", self.undo:IsShown() and -150 or -18, 50)
            local top, rowHeight = math.max(76, self.summary:GetStringHeight() + 60), 30
            for index, row in ipairs(self.rows) do
                local stop = p.stops[offset + index]
                row.stop = stop row:SetShown(stop ~= nil)
                local skippable = stop and stop.action == "accept" and not stop.done and self.actions.skip ~= nil
                row.skip:SetShown(skippable == true) row.choices:SetShown(skippable == true)
                row.skip:SetHeight(math.max(24, row.skip.textLabel:GetStringHeight() + 8))
                row.textLabel:SetPoint("RIGHT", skippable and -135 or -8, 0)
                local icon = stop and addon.UI.iconLabels and (addon.UI.ActionIcon(stop.action) .. " ") or ""
                if stop then row:SetText((stop.done and "[x] " or "") .. icon .. L["ExcursionAction_" .. stop.action] .. ": "
                    .. addon.UI.FormatQuestTitle(stop.quest, nil, nil, stop.action == "turnIn")
                    .. (p.running and offset + index == p.index and ("\n" .. L.ExcursionCurrent) or ""))
                    rowHeight = math.max(rowHeight, row.textLabel:GetStringHeight() + 12)
                    if skippable then rowHeight = math.max(rowHeight, row.skip:GetHeight() + 8) end
                end
            end
            local visible = math.min(6, math.max(1, #p.stops - offset))
            for index, row in ipairs(self.rows) do
                row:ClearAllPoints() row:SetPoint("TOPLEFT", 18, -top - (index - 1) * (rowHeight + 6)) row:SetHeight(rowHeight)
            end
            self:SetHeight(math.max(330, top + visible * (rowHeight + 6) + 160))
            self.paging:Update(#p.stops)
            self.start:SetEnabled(#p.stops > 0 and p.index <= #p.stops and not p.running and not p.needsReview and not p.unverified) self.pause:SetEnabled(p.running)
        end
        addon.UI.RefreshWhileShown(window, 1)
    end
    window.plan, window.actions, window.status = plan, actions, nil
    window.offset = window.offset or 0
    window:Refresh() addon.UI.ShowUtilityPanel(window, "outing")
    return window
end
