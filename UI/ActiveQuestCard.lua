local _, addon = ...
local L = addon.L
local ShowTextTooltip = addon.UI.ShowTextTooltip
local HideTextTooltip = addon.UI.HideTextTooltip
local FullTextIfTruncated = addon.UI.FullTextIfTruncated

function addon.CreateActiveQuestCard(parent)
    local activeBackdrop = parent:CreateTexture(nil, "BACKGROUND")
    activeBackdrop:SetPoint("TOPLEFT", 8, -29)
    addon.UI.Theme.Bind(activeBackdrop, "active", 0.55)
    local title = addon.UI.CreateLabel(parent, "GameFontNormal")
    title:SetPoint("TOPLEFT", 40, -35)
    title:SetPoint("TOPRIGHT", -104, -35)
    title:SetJustifyH("LEFT")
    title:SetMaxLines(2)

    local objective = addon.UI.CreateLabel(parent, "GameFontHighlightSmall")
    objective:SetPoint("TOPLEFT", title, "BOTTOMLEFT", -26, -5)
    objective:SetPoint("TOPRIGHT", title, "BOTTOMRIGHT", 90, -5)
    objective:SetJustifyH("LEFT")

    local activeDistance = addon.UI.CreateLabel(parent, "GameFontHighlightSmall")
    activeDistance:SetPoint("TOPRIGHT", -14, -36)
    return { backdrop = activeBackdrop, title = title, objective = objective, distance = activeDistance }
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
        ShowTextTooltip(self, FullTextIfTruncated(self.label), detail)
    end)
    row:SetScript("OnLeave", HideTextTooltip)
    row:SetScript("OnHide", HideTextTooltip)
    return row
end
