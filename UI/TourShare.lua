local _, addon = ...
local L = addon.L
local offer

local chatWindow
-- Preview of the tour as chat text. Sending happens only on the explicit button; the
-- text can also be copied.
function addon.ShowTourChat(messages, send)
    if not chatWindow then
        chatWindow = addon.UI.CreateUtilityPanel(520, 300, L.TourChatTitle, {hub = false})
        chatWindow.help = addon.UI.CreateLabel(chatWindow, "GameFontDisableSmall")
        chatWindow.help:SetPoint("TOPLEFT", 16, -40) chatWindow.help:SetPoint("TOPRIGHT", -16, -40)
        chatWindow.help:SetJustifyH("LEFT") chatWindow.help:SetMaxLines(2) chatWindow.help:SetText(L.TourChatHelp)
        chatWindow.body = addon.UI.CreateLabel(chatWindow, "GameFontHighlightSmall")
        chatWindow.body:SetPoint("TOPLEFT", 16, -72) chatWindow.body:SetPoint("TOPRIGHT", -16, -72)
        chatWindow.body:SetJustifyH("LEFT") chatWindow.body:SetMaxLines(9)
        chatWindow.send = addon.UI.CreateUtilityButton(chatWindow, L.TourChatSend, 230, function()
            local action, list = chatWindow.action, chatWindow.messages
            chatWindow:Hide()
            if action then action(list) end
        end)
        chatWindow.send:SetPoint("BOTTOMLEFT", 16, 14)
        chatWindow.copy = addon.UI.CreateUtilityButton(chatWindow, L.TourChatCopy, 230, function()
            addon.ShowTextWindow("tourChat", table.concat(chatWindow.messages or {}, "\n"), L.TourChatTitle, L.DebugCopyHint)
        end)
        chatWindow.copy:SetPoint("BOTTOMRIGHT", -16, 14)
    end
    chatWindow.messages, chatWindow.action = messages, send
    chatWindow.body:SetText(table.concat(messages, "\n\n"))
    chatWindow.send:SetEnabled(send ~= nil and #messages > 0)
    chatWindow:Show()
    return chatWindow
end

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
