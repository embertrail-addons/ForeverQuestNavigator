local _, addon = ...

function addon.CreateQuestTracker(settings, skipQuest, resetSkips)
    local frame = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    frame:SetSize(352, 158)
    frame:SetPoint("CENTER", UIParent, "CENTER", settings.x, settings.y)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    frame:SetBackdropColor(0.06, 0.05, 0.04, 0.94)

    local header = CreateFrame("Frame", nil, frame)
    header:SetPoint("TOPLEFT", 8, -5)
    header:SetPoint("TOPRIGHT", -32, -5)
    header:SetHeight(24)
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function() frame:StartMoving() end)
    header:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        local x, y = frame:GetCenter()
        local centerX, centerY = UIParent:GetCenter()
        settings.x, settings.y = x - centerX, y - centerY
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", UIParent, "CENTER", settings.x, settings.y)
    end)

    local heading = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    heading:SetPoint("LEFT", 6, 0)
    heading:SetText("Forever Quest Navigator")

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButtonNoScripts")
    close:SetPoint("TOPRIGHT", -3, -2)
    close:SetScript("OnClick", function() frame:Hide() end)
    frame:SetScript("OnShow", function() settings.hidden = false end)
    frame:SetScript("OnHide", function() settings.hidden = not frame:IsShown() end)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("TOPLEFT", 14, -35)
    title:SetPoint("TOPRIGHT", -14, -35)
    title:SetJustifyH("LEFT")
    title:SetMaxLines(2)

    local objective = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    objective:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    objective:SetPoint("TOPRIGHT", title, "BOTTOMRIGHT", 0, -8)
    objective:SetJustifyH("LEFT")
    objective:SetMaxLines(3)

    local skip = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    skip:SetSize(76, 22)
    skip:SetPoint("BOTTOMLEFT", 14, 12)
    skip:SetText("Skip quest")
    skip:SetScript("OnClick", skipQuest)
    skip:SetEnabled(false)

    local reset = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    reset:SetSize(82, 22)
    reset:SetPoint("LEFT", skip, "RIGHT", 6, 0)
    reset:SetText("Reset skips")
    reset:SetScript("OnClick", resetSkips)
    reset:SetEnabled(false)

    title:SetText("Reading quest log...")
    frame:SetShown(not settings.hidden)

    function frame:Render(quest, objectiveText, hasSkips)
        skip:SetEnabled(quest ~= nil)
        reset:SetEnabled(hasSkips)
        if not quest then
            title:SetText(objectiveText)
            objective:SetText("")
            return
        end

        local questTitle = quest.title
        if not questTitle or questTitle == "" then
            questTitle = "Quest " .. quest.id
        end
        local level = addon.QuestPrioritizer.GetLevel(quest)
        title:SetText(level and ("[%d] %s"):format(level, questTitle) or questTitle)
        objective:SetText(objectiveText)
    end

    return frame
end
