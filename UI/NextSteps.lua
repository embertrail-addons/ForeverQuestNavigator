local _, addon = ...
local L = addon.L

-- The board consumes the same decision model as planning and diagnostics.
-- It never changes priority; all ordinary clicks only open a destination.
function addon.CreateNextSteps(owner, parent, settings, actions)
    local board = CreateFrame("Frame", nil, parent)
    board.caption = addon.UI.CreateLabel(board, "GameFontNormalSmall")
    board.caption:SetPoint("TOPLEFT") board.caption:SetPoint("TOPRIGHT") board.caption:SetJustifyH("LEFT")
    board.caption:SetText(L.BriefNext)
    board.rows = {}
    for index = 1, 3 do
        local row = CreateFrame("Button", nil, board)
        addon.UI.AddRowHighlight(row)
        row.label = addon.UI.CreateLabel(row, "GameFontHighlightSmall")
        row.label:SetJustifyH("LEFT") row.label:SetMaxLines(2)
        row.detail = addon.UI.CreateLabel(row, "GameFontDisableSmall")
        row.detail:SetJustifyH("LEFT") row.detail:SetMaxLines(1)
        row.distance = addon.UI.CreateLabel(row, "GameFontDisableSmall")
        row.distance:SetJustifyH("RIGHT")
        row.map = addon.UI.MakeButton(row) row.map:SetText(L.Map)
        row.menu = addon.UI.MakeButton(row) row.menu:SetText("...")
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
    board.plan = addon.UI.MakeButton(board) board.plan:SetText(L.BriefPlan)
    board.plan:SetScript("OnClick", function()
        if owner.openPickupPlanning then owner.openPickupPlanning()
        elseif addon.OpenPickupPlanning then addon.OpenPickupPlanning() end
    end)
    board.closing = addon.UI.MakeButton(board) board.closing:SetText(L.BriefClosing)
    board.closing:SetScript("OnClick", function()
        if owner.openDecisionPlanning then owner.openDecisionPlanning("closing")
        elseif addon.OpenDecisionPlanning then addon.OpenDecisionPlanning("closing") end
    end)
    board.environment = addon.UI.MakeButton(board)
    board.environment:SetScript("OnClick", function()
        owner.environmentExpanded = not owner.environmentExpanded
        settings.environmentExpanded = owner.environmentExpanded
        owner:UpdateNavigatorLayout()
    end)
    board.progress = addon.UI.CreateLabel(board, "GameFontDisableSmall")
    board.progress:SetJustifyH("LEFT") board.progress:SetMaxLines(2)
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
        self.caption:SetText(#model.steps == 0 and L.BriefNoNext or L.BriefNext)
        self.caption:SetHeight(math.max(18, self.caption:GetStringHeight()))
        y = self.caption:GetHeight() + 6
        for index, row in ipairs(self.rows) do
            local step = model.steps[index]
            row.step = step row:SetShown(step ~= nil)
            if step then
                row:ClearAllPoints() row:SetPoint("TOPLEFT", 0, -y) row:SetPoint("TOPRIGHT", 0, -y)
                row.label:ClearAllPoints() row.label:SetPoint("TOPLEFT", 0, -2) row.label:SetPoint("TOPRIGHT", -8, -2)
                row.label:SetText(L["BriefAction_" .. step.kind]:format(addon.UI.FormatQuestTitle(step.quest, true, model.playerLevel)))
                local line = math.max(18 * scale, row.label:GetStringHeight())
                row.detail:ClearAllPoints() row.detail:SetPoint("TOPLEFT", 0, -line - 4)
                row.detail:SetText(step.detail or "")
                row.distance:ClearAllPoints() row.distance:SetPoint("TOPRIGHT", -86 * scale, -line - 4)
                row.distance:SetText(addon.UI.FormatDistance(step))
                row.detail:SetPoint("TOPRIGHT", -86 * scale - row.distance:GetStringWidth() - 8, -line - 4)
                row.map:ClearAllPoints() row.map:SetPoint("TOPRIGHT", -27 * scale, -line)
                row.map:SetSize(48 * scale, math.max(24, 24 * scale))
                row.map:SetEnabled(step.target ~= nil)
                row.menu:ClearAllPoints() row.menu:SetPoint("TOPRIGHT", 0, -line)
                row.menu:SetSize(24 * scale, math.max(24, 24 * scale))
                row.menu:SetShown(actions.openQuestMenu ~= nil)
                row:SetHeight(line + math.max(24, row.detail:GetStringHeight() + 6, 24 * scale) + 10)
                y = y + row:GetHeight() + 6
            end
        end
        self.progress:SetShown(self.progress:GetText() ~= "")
        if self.progress:IsShown() then
            self.progress:ClearAllPoints() self.progress:SetPoint("TOPLEFT", 0, -y) self.progress:SetPoint("TOPRIGHT", 0, -y)
            y = y + self.progress:GetStringHeight() + 8
        end
        local half, height = math.max(90, (width - 8) / 2), math.max(26, 26 * scale)
        self.plan:ClearAllPoints() self.plan:SetPoint("TOPLEFT", 0, -y) self.plan:SetSize(half, height)
        self.closing:ClearAllPoints() self.closing:SetPoint("TOPRIGHT", 0, -y) self.closing:SetSize(half, height)
        for _, button in ipairs({self.plan, self.closing}) do
            button.textLabel:ClearAllPoints() button.textLabel:SetPoint("LEFT", 5, 0) button.textLabel:SetPoint("RIGHT", -5, 0)
            button.textLabel:SetJustifyH("CENTER") button.textLabel:SetMaxLines(2)
            height = math.max(height, button.textLabel:GetStringHeight() + 8)
        end
        self.plan:SetHeight(height) self.closing:SetHeight(height)
        self.closing:SetEnabled(#(model.closing or {}) > 0)
        y = y + height + 8
        self.environment:ClearAllPoints() self.environment:SetPoint("TOPLEFT", 0, -y) self.environment:SetPoint("TOPRIGHT", 0, -y)
        self.environment:SetText((owner.environmentExpanded and "− " or "+ ") .. L.BriefEnvironment)
        self.environment.textLabel:ClearAllPoints() self.environment.textLabel:SetPoint("LEFT", 5, 0)
        self.environment.textLabel:SetPoint("RIGHT", -5, 0) self.environment.textLabel:SetMaxLines(2)
        self.environment:SetHeight(math.max(height, self.environment:GetFontString():GetStringHeight() + 8))
        self:SetHeight(y + self.environment:GetHeight())
        return self:GetHeight()
    end
    return board
end
