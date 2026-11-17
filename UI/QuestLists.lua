local _, addon = ...
local L = addon.L
local CreateDirectionArrow = addon.CreateDirectionArrow
local AddRowBackground = addon.UI.AddRowBackground
local CreateSkipCheckbox = addon.UI.CreateSkipCheckbox
local EnableTitleTooltip = addon.UI.EnableTitleTooltip
local ShowTextTooltip = addon.UI.ShowTextTooltip
local HideTextTooltip = addon.UI.HideTextTooltip

function addon.CreateAcceptedQuestRow(parent, actions, index)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(22)
    AddRowBackground(row, index)

    local highlight = row:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(1, 0.8, 0.25, 0.16)

    row.label = addon.UI.CreateLabel(row, "GameFontHighlightSmall")
    row.label:SetPoint("LEFT", 26, 0)
    row.label:SetPoint("RIGHT", -78, 0)
    row.label:SetJustifyH("LEFT")
    row.label:SetMaxLines(1)
    EnableTitleTooltip(row)
    row:SetScript("OnClick", function(self)
        actions.openQuestMap(self.questID)
    end)
    row.checkbox = CreateSkipCheckbox(row, actions.skip)
    row.checkbox:SetPoint("LEFT", -2, 0)
    row.distance = addon.UI.CreateLabel(row, "GameFontHighlightSmall")
    row.distance:SetPoint("RIGHT", 0, 0)
    row.zone = addon.UI.CreateLabel(row, "GameFontNormalSmall")
    row.zone:SetPoint("TOPRIGHT", 0, -22)
    row.zone:SetJustifyH("RIGHT")
    row.zone:SetMaxLines(1)
    row.zone:Hide()
    row:Hide()
    return row
end

function addon.CreateOfferQuestRow(parent, actions, settings, index)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(22)
    AddRowBackground(row, index)
    row.label = addon.UI.CreateLabel(row, "GameFontHighlightSmall")
    row.label:SetPoint("LEFT", 5, 0)
    row.label:SetPoint("RIGHT", -82, 0)
    row.label:SetJustifyH("LEFT")
    row.label:SetMaxLines(1)
    if row.EnableMouseMotion then
        row:EnableMouseMotion(true)
    else
        row:EnableMouse(true)
    end
    row:SetScript("OnClick", function(self)
        if self.measurement then actions.openOfferMap(self.measurement.id) end
    end)
    row:SetScript("OnEnter", function(self)
        local offer = self.measurement
        if not offer then return end
        local lines = {}
        if offer.recommended then
            lines[#lines + 1] = L.RecommendedOffer
            if offer.levelPenalty == 0 then lines[#lines + 1] = L.RecommendationLevelFit end
            if offer.recommendationReason == "nearTarget" then
                lines[#lines + 1] = L.RecommendationNearTarget
            elseif offer.recommendationReason == "shortRoute" then
                lines[#lines + 1] = L.RecommendationShortRoute
            end
            if offer.journeyYards then
                lines[#lines + 1] = L.RecommendationJourney:format(offer.journeyYards)
            end
        end
        local marker = offer.marker
        if marker then
            lines[#lines + 1] = L.OfferPickup:format(offer.pickupZone or L.UnknownZone, marker.x * 100, marker.y * 100)
        end
        if offer.objectiveZone then lines[#lines + 1] = L.OfferObjectiveZone:format(offer.objectiveZone) end
        lines[#lines + 1] = L.OfferPickupDistance:format(offer.yards)
        if offer.objectiveYards then
            lines[#lines + 1] = L.OfferObjectiveDistance:format(offer.objectiveYards)
        end
        if offer.group then lines[#lines + 1] = L.GroupQuest end
        if settings.showQuestXP and offer.xp then lines[#lines + 1] = L.QuestXPReward:format(offer.xp) end
        lines[#lines + 1] = L.OfferMapHint
        ShowTextTooltip(self, self.label:GetText(), table.concat(lines, "\n"))
    end)
    row:SetScript("OnLeave", HideTextTooltip)
    row:SetScript("OnHide", HideTextTooltip)
    row.distance = addon.UI.CreateLabel(row, "GameFontHighlightSmall")
    row.distance:SetPoint("RIGHT")
    row.arrow = CreateDirectionArrow(row, 15)
    row.arrow:SetPoint("RIGHT", -63, 0)
    row.details = addon.UI.CreateLabel(row, "GameFontHighlightSmall")
    row.details:SetJustifyH("LEFT")
    row.details:SetMaxLines(2)
    row.details:SetPoint("TOPLEFT", 5, -20)
    row.details:SetPoint("TOPRIGHT", -3, -20)
    row.recommendation = row:CreateTexture(nil, "ARTWORK")
    row.recommendation:SetPoint("TOPLEFT")
    row.recommendation:SetPoint("BOTTOMLEFT")
    row.recommendation:SetWidth(2)
    row.recommendation:SetColorTexture(1, 0.75, 0.28, 1)
    row:Hide()
    return row
end
