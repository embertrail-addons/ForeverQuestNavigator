local _, addon = ...
local L = addon.L
local CreateDirectionArrow = addon.CreateDirectionArrow
local AddRowBackground = addon.UI.AddRowBackground
local CreateSkipCheckbox = addon.UI.CreateSkipCheckbox
local EnableTitleTooltip = addon.UI.EnableTitleTooltip

function addon.CreateAcceptedQuestRow(parent, actions, index)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(addon.UI.Style.rowHeight)
    AddRowBackground(row, index)

    addon.UI.AddRowHighlight(row)

    row.label = addon.UI.CreateLabel(row, "GameFontHighlightSmall")
    row.label:SetPoint("LEFT", 26, 0)
    row.label:SetPoint("RIGHT", -78, 0)
    row.label:SetJustifyH("LEFT")
    row.label:SetMaxLines(1)
    EnableTitleTooltip(row)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:SetScript("OnClick", function(self, button)
        if button == "RightButton" and actions.openQuestMenu then actions.openQuestMenu(self, self.questID)
        else actions.openQuestMap(self.questID) end
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
    row:SetHeight(addon.UI.Style.rowHeight)
    AddRowBackground(row, index)
    addon.UI.AddRowHighlight(row)
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
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:SetScript("OnClick", function(self, button)
        if not self.measurement then return end
        if button == "RightButton" and actions.openQuestMenu then actions.openQuestMenu(self, self.measurement.id, true)
        else actions.openOfferMap(self.measurement.id) end
    end)
    addon.UI.BindTooltip(row, function(self)
        local offer = self.measurement
        if not offer then return end
        local lines = {}
        if offer.capacityFull then lines[#lines + 1] = L.QuestLogFull end
        local contextual = addon.PlanningInsights.OfferReason(offer)
        if contextual then lines[#lines + 1] = contextual end
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
        else
            lines[#lines + 1] = L.OfferTargetUnknown
        end
        if not addon.QuestPrioritizer.GetLevel(offer) then lines[#lines + 1] = L.UnknownLevel end
        if offer.group then lines[#lines + 1] = L.GroupQuest end
        if settings.showQuestXP and offer.xp then lines[#lines + 1] = L.QuestXPReward:format(offer.xp) end
        if settings.showQuestXP and not offer.xp then lines[#lines + 1] = L.UnknownXP end
        if settings.showQuestRewards ~= false then lines[#lines + 1] = addon.QuestRewards.Describe(addon.QuestRewards.Client(offer.id)) end
        lines[#lines + 1] = L.OfferMapHint
        lines[#lines + 1] = L.QuestMenuHint
        return self.label:GetText(), table.concat(lines, "\n")
    end)
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
    addon.UI.Theme.Bind(row.recommendation, "recommended", 1)
    row.discovery = row:CreateTexture(nil, "BACKGROUND")
    row.discovery:SetAllPoints()
    addon.UI.Theme.Bind(row.discovery, "recommended", 0.16)
    row.discovery:Hide()
    row:SetScript("OnUpdate", function(self, elapsed)
        if not self.noticeSeconds then return end
        self.noticeSeconds = self.noticeSeconds - elapsed
        if self.noticeSeconds <= 0 or (self.noticeDeadline and GetTime() >= self.noticeDeadline) then
            self.noticeSeconds, self.noticeDeadline = nil, nil
            self.discovery:Hide()
        end
    end)
    row:Hide()
    return row
end
