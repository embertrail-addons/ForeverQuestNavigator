local _, addon = ...
local L = addon.L
local offer

-- Confirmation for a tour shared by a group member. Nothing changes until Adopt.
function addon.ShowTourOffer(sender, stops, adopt)
    if not offer then
        offer = addon.UI.CreateUtilityPanel(440, 210, L.TourOfferTitle, {hub = false})
        offer.body = addon.UI.CreateLabel(offer, "GameFontHighlightSmall")
        offer.body:SetPoint("TOPLEFT", 16, -44) offer.body:SetPoint("TOPRIGHT", -16, -44)
        offer.body:SetJustifyH("LEFT") offer.body:SetMaxLines(6)
        offer.adopt = addon.UI.CreateUtilityButton(offer, L.TourOfferAdopt, 196, function()
            local stopsToAdd, action = offer.stops, offer.action
            offer:Hide()
            if action then action(stopsToAdd) end
        end)
        offer.adopt:SetPoint("BOTTOMLEFT", 16, 14)
        offer.decline = addon.UI.CreateUtilityButton(offer, L.TourOfferDecline, 196, function() offer:Hide() end)
        offer.decline:SetPoint("BOTTOMRIGHT", -16, 14)
    end
    local inLog, quests = 0, addon.QuestLog.Read(C_QuestLog) or {}
    local present = {}
    for _, quest in ipairs(quests) do present[quest.id] = true end
    for _, stop in ipairs(stops) do if present[stop.id] then inLog = inLog + 1 end end
    offer.stops, offer.action = stops, adopt
    offer.body:SetText(L.TourOfferText:format(tostring(sender), #stops, inLog))
    offer.adopt:SetEnabled(inLog > 0)
    offer:Show()
    return offer
end
