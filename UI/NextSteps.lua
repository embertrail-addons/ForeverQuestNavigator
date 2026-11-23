local _, addon = ...
local L = addon.L

-- The board consumes the same decision model as planning and diagnostics.
-- It never changes priority; all ordinary clicks only open a destination.
function addon.CreateNextSteps(owner, parent, settings, actions)
    local board = CreateFrame("Frame", nil, parent)
    board.caption = addon.UI.CreateLabel(board, "GameFontNormalSmall")
    board.caption:SetPoint("TOPLEFT") board.caption:SetPoint("TOPRIGHT") board.caption:SetJustifyH("LEFT")
    board.caption:SetText(L.BriefNext)
    board.tour = addon.UI.MakeButton(board)
    board.tour:SetScript("OnClick", function()
        local area = board.model and board.model.area
        if area and addon.OpenExcursionFromArea then addon.OpenExcursionFromArea(area.entries[1].quest.id) end
    end)
    addon.UI.BindTooltip(board.tour, function()
        local area = board.model and board.model.area
        return L.TourPreview, area and (addon.PickupPlanning.AreaSummary(area) .. "\n" .. L.PickupAreaHelp) or L.PickupAreaHelp
    end)
    board.tourInfo = addon.UI.CreateLabel(board, "GameFontDisableSmall")
    board.tourInfo:SetJustifyH("LEFT") board.tourInfo:SetMaxLines(2)
    board.rows = {}
    for index = 1, 3 do
        local row = CreateFrame("Button", nil, board)
        addon.UI.AddRowHighlight(row)
        row.label = addon.UI.CreateLabel(row, "GameFontHighlightSmall")
        row.label:SetJustifyH("LEFT") row.label:SetMaxLines(2)
        row.detail = addon.UI.CreateLabel(row, "GameFontDisableSmall")
        row.detail:SetJustifyH("LEFT") row.detail:SetMaxLines(2)
        row.distance = addon.UI.CreateLabel(row, "GameFontDisableSmall")
        row.distance:SetJustifyH("RIGHT")
        row.map = addon.UI.MakeButton(row) row.map:SetText(L.Map)
        row.menu = addon.UI.MakeButton(row) row.menu:SetText("...")
        row.skip = addon.UI.MakeButton(row) row.skip:SetText(L.OfferSkip)
        row.skip:SetScript("OnClick", function()
            if row.step and addon.SkipCurrentOffer then addon.SkipCurrentOffer(row.step.quest.id) end
        end)
        row.map:SetScript("OnClick", function()
            local step = row.step
            if not step then return end
            if step.target and actions.openRouteStop then actions.openRouteStop(step)
            elseif step.offer then actions.openOfferMap(step.quest.id)
            else actions.openQuestMap(step.quest.id) end
        end)
        row:SetScript("OnClick", function() row.map:Click() end)
        row.menu:SetScript("OnClick", function(self)
            if row.step and actions.openQuestMenu then actions.openQuestMenu(self, row.step.quest.id, row.step.offer) end
        end)
        addon.UI.BindTooltip(row, function()
            if row.step then return row.step.quest.title, (row.step.detail or L.BriefNextHelp) .. "\n" .. L.BriefMapClick end
        end)
        addon.UI.BindTooltip(row.menu, function() return L.MoreActions, L.QuestMenuHint end)
        board.rows[index] = row
    end
    board.plan = addon.UI.MakeButton(board) board.plan:SetText(L.JourneyCompare)
    board.plan:SetScript("OnClick", function()
        if owner.openPickupPlanning then owner.openPickupPlanning()
        elseif addon.OpenAdventure then addon.OpenAdventure("compare")
        elseif addon.OpenPickupPlanning then addon.OpenPickupPlanning() end
    end)
    board.closing = addon.UI.MakeButton(board) board.closing:SetText(L.BriefClosing)
    board.closing:SetScript("OnClick", function()
        if owner.openDecisionPlanning then owner.openDecisionPlanning("closing")
        elseif addon.OpenDecisionPlanning then addon.OpenDecisionPlanning("closing") end
    end)
    board.environment = addon.UI.MakeButton(board)
    board.environment:SetScript("OnClick", function()
        if settings.simpleNavigator then if addon.OpenAdventure then addon.OpenAdventure() end return end
        owner.environmentExpanded = not owner.environmentExpanded
        settings.environmentExpanded = owner.environmentExpanded
        owner:UpdateNavigatorLayout()
    end)
    board.progress = addon.UI.CreateLabel(board, "GameFontDisableSmall")
    board.progress:SetJustifyH("LEFT") board.progress:SetMaxLines(2)
    board.review = addon.UI.MakeButton(board) board.review:SetText(L.RoundReview)
    board.review:SetScript("OnClick", function() if addon.OpenOutingReview then addon.OpenOutingReview() end end)
    board.assist = addon.UI.MakeButton(board)
    board.assist:SetScript("OnClick", function()
        local model = board.model or {}
        if model.acceptanceReview and addon.OpenOutingReview then addon.OpenOutingReview() return end
        if addon.OpenAdventure then addon.OpenAdventure(model.bagsWarning and "bags" or #(model.changes or {}) > 0 and "changes"
            or (model.laterCount or 0) > 0 and "later" or "departure") end
    end)
    board.undoOffer = addon.UI.MakeButton(board) board.undoOffer:SetText(L.OfferUndo)
    board.undoOffer:SetScript("OnClick", function() if addon.UndoLastChange then addon.UndoLastChange() end end)
    for _, link in ipairs({board.tour, board.plan, board.closing, board.assist, board.environment}) do addon.UI.StyleLink(link) end
    addon.UI.BindTooltip(board.plan, function() return L.BriefPlan, L.PickupPlanningHelp end)
    addon.UI.BindTooltip(board.closing, function() return L.BriefClosing, L.BriefClosingHelp end)
    addon.UI.BindTooltip(board.environment, function() return L.BriefEnvironment, L.BriefEnvironmentHelp end)
    function board:Render(model)
        self.model = model or {steps = {}, closing = {}}
        local ledger = self.model.ledger
        self.progress:SetText(ledger and L.BriefRoundProgress:format(ledger.completed, #ledger.steps)
            .. (ledger.changed > 0 and (" · " .. L.BriefRoundChanged:format(ledger.changed)) or "")
            .. (self.model.roundComplete and ("\n" .. L.BriefRoundDone) or "") or "")
    end
    function board:Layout(width, scale)
        local model, y = self.model or {steps = {}, closing = {}}, 0
        self.caption:SetText(L.BriefNext)
        self.caption:SetShown(#model.steps > 0)
        self.caption:SetHeight(math.max(18, self.caption:GetStringHeight()))
        y = #model.steps > 0 and self.caption:GetHeight() + 6 or 0
        for index, row in ipairs(self.rows) do
            local step = index == 1 and model.steps[index] or nil
            row.step = step row:SetShown(step ~= nil)
            row.skip:SetShown(step ~= nil and step.kind == "accept")
            if step then
                row:ClearAllPoints() row:SetPoint("TOPLEFT", 0, -y) row:SetPoint("TOPRIGHT", 0, -y)
                row.label:ClearAllPoints() row.label:SetPoint("TOPLEFT", 0, -2) row.label:SetPoint("TOPRIGHT", -8, -2)
                row.label:SetText(L["BriefAction_" .. step.kind]:format(
                    addon.UI.FormatQuestTitle(step.quest, true, model.playerLevel, step.kind == "turnIn")))
                local line = math.max(18 * scale, row.label:GetStringHeight())
                local buttonHeight = addon.UI.ButtonHeight(scale)
                row.menu:SetShown(actions.openQuestMenu ~= nil)
                row.menu:ClearAllPoints() row.menu:SetPoint("TOPRIGHT", 0, -line - 2)
                row.menu:SetSize(26 * scale, buttonHeight)
                row.map:ClearAllPoints()
                row.map:SetPoint("TOPRIGHT", row.menu:IsShown() and -(26 * scale + 4) or 0, -line - 2)
                row.map:SetSize(48 * scale, buttonHeight)
                row.map:SetEnabled(step.target ~= nil)
                row.distance:SetText(addon.UI.FormatDistance(step))
                row.distance:ClearAllPoints() row.distance:SetPoint("RIGHT", row.map, "LEFT", -8, 0)
                local reserved = 48 * scale + (row.menu:IsShown() and 26 * scale + 4 or 0) + row.distance:GetStringWidth() + 16
                row.detail:SetText(step.detail or "")
                row.detail:ClearAllPoints() row.detail:SetPoint("TOPLEFT", 0, -line - 4)
                row.detail:SetPoint("TOPRIGHT", -reserved, -line - 4)
                row:SetHeight(line + math.max(buttonHeight + 2, row.detail:GetStringHeight() + 6) + 6)
                if row.skip:IsShown() then
                    row.skip:ClearAllPoints() row.skip:SetPoint("BOTTOMLEFT", 0, 0)
                    row.skip:SetSize(120 * scale, 26 * scale) row:SetHeight(row:GetHeight() + 28 * scale)
                end
                y = y + row:GetHeight() + 6
            end
        end
        local area = model.area
        local simple = settings.simpleNavigator
        self.review:SetShown(model.review ~= nil and not simple)
        if self.review:IsShown() then
            addon.UI.LayoutActionRow(self.review, y, width, scale, 1)
            y = y + self.review:GetHeight() + 8
        end
        self.progress:SetShown(self.progress:GetText() ~= "" and not simple)
        if self.progress:IsShown() then
            self.progress:ClearAllPoints() self.progress:SetPoint("TOPLEFT", 0, -y) self.progress:SetPoint("TOPRIGHT", 0, -y)
            y = y + self.progress:GetStringHeight() + 8
        end
        self.undoOffer:SetShown(model.offerUndo == true)
        if self.undoOffer:IsShown() then addon.UI.LayoutActionRow(self.undoOffer, y, width, scale, 1) y = y + self.undoOffer:GetHeight() + 8 end
        -- Tour summary as a quiet info line; all further actions are one row of text links.
        self.tourInfo:SetShown(area ~= nil and not simple)
        if self.tourInfo:IsShown() then
            self.tourInfo:SetText(area.zone .. ": " .. addon.PickupPlanning.AreaSummary(area))
            self.tourInfo:ClearAllPoints() self.tourInfo:SetPoint("TOPLEFT", 0, -y) self.tourInfo:SetPoint("TOPRIGHT", 0, -y)
            y = y + self.tourInfo:GetStringHeight() + 4
        end
        self.tour:SetText(L.TourPreview)
        self.tour:SetShown(area ~= nil and not simple)
        self.plan:SetText(L.JourneyCompare)
        self.plan:SetShown(area ~= nil and not simple)
        self.closing:SetText(model.returnAdvice and L.ReturnToArea:format(model.returnAdvice.zone, #model.closing) or L.BriefClosing)
        self.closing:SetShown(#(model.closing or {}) > 0 and not simple)
        self.closing:SetEnabled(#(model.closing or {}) > 0)
        self.assist:SetText(model.acceptanceReview and L.MixedAcceptedReview or model.bagsWarning or #(model.changes or {}) > 0 and L.AdventureChangesCount:format(#model.changes)
            or (model.laterCount or 0) > 0 and L.JourneyLaterCount:format(model.laterCount)
            or (model.departureCount or 0) > 0 and L.AdventureDepartureCount:format(model.departureCount) or L.AdventureTitle)
        self.assist:SetShown(not simple or model.acceptanceReview or model.bagsWarning ~= nil or (model.laterCount or 0) > 0 or #(model.changes or {}) > 0)
        self.environment:SetText(simple and L.JourneyMore or (owner.environmentExpanded and "− " or "+ ") .. L.BriefEnvironment)
        self.environment:Show()
        y = addon.UI.FlowLinks({self.tour, self.plan, self.closing, self.assist, self.environment}, y, width, scale)
        self:SetHeight(y)
        return self:GetHeight()
    end
    return board
end
