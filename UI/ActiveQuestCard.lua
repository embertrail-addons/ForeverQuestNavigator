local _, addon = ...
local L = addon.L
local ShowTextTooltip = addon.UI.ShowTextTooltip
local HideTextTooltip = addon.UI.HideTextTooltip
local FullTextIfTruncated = addon.UI.FullTextIfTruncated

function addon.CreateActiveQuestCard(parent)
    local activeBackdrop = parent:CreateTexture(nil, "BACKGROUND")
    activeBackdrop:SetPoint("TOPLEFT", 8, -29)
    addon.UI.Theme.Bind(activeBackdrop, "active", 0.55)
    local accent = parent:CreateTexture(nil, "ARTWORK")
    accent:SetPoint("TOPLEFT", activeBackdrop, "TOPLEFT", 0, 0)
    accent:SetPoint("BOTTOMLEFT", activeBackdrop, "BOTTOMLEFT", 0, 0)
    accent:SetWidth(2)
    addon.UI.Theme.Bind(accent, "heading", .8)
    local title = addon.UI.CreateLabel(parent, "GameFontNormal")
    title:SetPoint("TOPLEFT", 14, -35)
    title:SetPoint("TOPRIGHT", -104, -35)
    title:SetJustifyH("LEFT")
    title:SetMaxLines(2)

    local objective = addon.UI.CreateLabel(parent, "GameFontHighlightSmall")
    objective:SetPoint("TOPLEFT", title, "BOTTOMLEFT", -42, -5)
    objective:SetPoint("TOPRIGHT", title, "BOTTOMRIGHT", 90, -5)
    objective:SetJustifyH("LEFT")

    local activeDistance = addon.UI.CreateLabel(parent, "GameFontHighlightSmall")
    activeDistance:SetPoint("TOPRIGHT", -14, -36)
    return { backdrop = activeBackdrop, accent = accent, title = title, objective = objective, distance = activeDistance }
end

function addon.CreateObjectiveRow(parent, actions)
    local row = CreateFrame("Button", nil, parent)
    row.indicator = addon.UI.CreateLabel(row, "GameFontNormalSmall")
    row.indicator:SetPoint("TOPLEFT", 1, -1)
    row.label = addon.UI.CreateLabel(row, "GameFontHighlightSmall")
    row.label:SetPoint("TOPLEFT", 13, -1)
    row.label:SetPoint("TOPRIGHT", -2, -1)
    row.label:SetJustifyH("LEFT")
    row.label:SetMaxLines(2)
    local highlight = addon.UI.AddRowHighlight(row)
    row.goalHighlight = highlight
    row.activeMark = row:CreateTexture(nil, "BACKGROUND")
    row.activeMark:SetAllPoints()
    addon.UI.Theme.Bind(row.activeMark, "highlight", .12)
    row.activeMark:Hide()
    row.accent = row:CreateTexture(nil, "ARTWORK")
    row.accent:SetPoint("TOPLEFT") row.accent:SetPoint("BOTTOMLEFT") row.accent:SetWidth(2)
    addon.UI.Theme.Bind(row.accent, "heading", .8)
    row.caption = addon.UI.CreateLabel(row, "GameFontNormalSmall")
    row.caption:SetPoint("TOPLEFT", 8, -2)
    row.caption:SetMaxLines(2)
    row.caption:SetJustifyH("LEFT")
    row.counter = addon.UI.CreateLabel(row, "GameFontHighlightSmall")
    row.counter:SetJustifyH("RIGHT")
    row.barBackground = row:CreateTexture(nil, "BACKGROUND")
    row.barBackground:SetPoint("BOTTOMLEFT", 8, 0) row.barBackground:SetPoint("BOTTOMRIGHT", -4, 0)
    row.barBackground:SetHeight(2) addon.UI.Theme.Bind(row.barBackground, "muted", .15)
    row.bar = row:CreateTexture(nil, "ARTWORK")
    row.bar:SetPoint("BOTTOMLEFT", 8, 0) row.bar:SetHeight(2)
    addon.UI.Theme.Bind(row.bar, "heading", .45)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:SetScript("OnClick", function(self, button)
        if not (self.goal and self.goal.selectable) then return end
        if button == "RightButton" then
            actions.avoidObjective(self.goal.index)
        else
            actions.selectObjective(self.goal.index)
        end
    end)
    row:SetScript("OnEnter", function(self)
        local detail = self.goal.selectable and (self.locked and L.ResumeAutomaticObjective or L.NavigateToObjective)
        if self.goal.selectable then
            detail = detail .. "\n" .. (self.goal.avoided and L.RestoreObjectiveHint or L.AvoidObjectiveHint)
        end
        ShowTextTooltip(self, self.goal.text, detail)
    end)
    row:SetScript("OnLeave", HideTextTooltip)
    row:SetScript("OnHide", HideTextTooltip)
    return row
end
