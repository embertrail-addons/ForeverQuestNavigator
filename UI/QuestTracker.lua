local _, addon = ...
local L = addon.L

local FormatQuestTitle = addon.UI.FormatQuestTitle

local FormatDistance = addon.UI.FormatDistance

local ShowTextTooltip = addon.UI.ShowTextTooltip
local HideTextTooltip = addon.UI.HideTextTooltip


local MakeButton = addon.UI.MakeButton

local CreateDirectionArrow = addon.CreateDirectionArrow

function addon.CreateMinimapButton(settings, cycleDisplayMode, openSettings)
    local minimap = Minimap
    if not minimap then return end
    local button = CreateFrame("Button", nil, minimap)
    button:SetSize(28, 28)
    button:SetFrameLevel(minimap:GetFrameLevel() + 8)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")

    local background = button:CreateTexture(nil, "BACKGROUND")
    background:SetSize(24, 24)
    background:SetPoint("CENTER")
    background:SetTexture(136467) -- Minimap background
    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetPoint("CENTER", 10, -10)
    border:SetTexture(136430) -- Minimap tracking border
    local label = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("CENTER")
    label:SetTextColor(1, 0.82, 0.34)
    label:SetText("FQN")

    local angle = settings.minimapAngle
    if type(angle) ~= "number" or not (math.abs(angle) < math.huge) then angle = math.rad(225) end
    local function PositionButton()
        local width, height = minimap:GetSize()
        local x, y = (width / 2 + 5) * math.cos(angle), (height / 2 + 5) * math.sin(angle)
        button:ClearAllPoints()
        button:SetPoint("CENTER", minimap, "CENTER", x, y)
    end
    PositionButton()
    minimap:HookScript("OnSizeChanged", PositionButton)

    local function ShowTooltip(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Forever Quest Navigator")
        local mode = settings.displayMode
        local hint = mode == "off" and L.ShowTracker or L.HideAll
        if mode == "full" and settings.showDirectionArrow then hint = L.OnlyArrow end
        GameTooltip:AddLine(hint)
        GameTooltip:AddLine(L.MoveButton)
        GameTooltip:AddLine(L.OpenSettingsHint)
        GameTooltip:Show()
    end
    button:SetScript("OnEnter", ShowTooltip)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    local dragging, dragged
    local function FollowCursor()
        local x, y = GetCursorPosition()
        local centerX, centerY = minimap:GetCenter()
        if not (centerX and centerY) then return end
        local scale = minimap:GetEffectiveScale()
        local dx, dy = x / scale - centerX, y / scale - centerY
        if dx == 0 and dy == 0 then return end
        angle = math.atan2(dy, dx)
        PositionButton()
    end
    local function StopDragging(self)
        if not dragging then return end
        self:SetScript("OnUpdate", nil)
        settings.minimapAngle = angle
        dragging = false
    end
    button:SetScript("OnMouseDown", function(_, mouseButton)
        if mouseButton == "LeftButton" and not dragging then dragged = false end
    end)
    button:SetScript("OnDragStart", function(self)
        dragging, dragged = true, true
        GameTooltip:Hide()
        FollowCursor()
        self:SetScript("OnUpdate", FollowCursor)
    end)
    button:SetScript("OnDragStop", StopDragging)
    button:SetScript("OnHide", StopDragging)
    button:SetScript("OnClick", function(self, mouseButton)
        if mouseButton == "RightButton" then
            GameTooltip:Hide()
            openSettings()
        elseif not dragged then
            cycleDisplayMode()
            ShowTooltip(self)
        end
    end)
    return button
end

local CreateSkipCheckbox = addon.UI.CreateSkipCheckbox

local function ShowSkippedQuests(button, restoreQuest, restoreAll)
    local entries = {}
    for _, entry in pairs(button.skippedQuests) do
        entries[#entries + 1] = entry
    end
    table.sort(entries, function(left, right) return left.order > right.order end)

    MenuUtil.CreateContextMenu(button, function(_, menu)
        menu:CreateTitle(L.SkippedQuests)
        menu:SetScrollMode(220)
        menu:CreateButton(L.RestoreAll, restoreAll)
        if menu.CreateDivider then menu:CreateDivider() end
        for _, entry in ipairs(entries) do
            menu:CreateButton(FormatQuestTitle(entry.quest), restoreQuest, entry.quest.id)
        end
    end)
end

local DEFAULT_TRACKER_WIDTH = 352
local MIN_TRACKER_WIDTH = 330
local MAX_TRACKER_WIDTH = 640

local function ClampTrackerWidth(width)
    if type(width) ~= "number" or width ~= width then return DEFAULT_TRACKER_WIDTH end
    return math.min(MAX_TRACKER_WIDTH, math.max(MIN_TRACKER_WIDTH, width))
end

function addon.CreateQuestTracker(settings, actions, version)
    addon.UI.SetFontSize(settings.fontPercent or 100)
    local frame = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    settings.trackerWidth = ClampTrackerWidth(settings.trackerWidth)
    frame:SetSize(settings.trackerWidth, 170)
    local navigation, navigationStatus, undoSkip, routeStopPreview, restoreAvoided, areaOverview
    local progressLine, progressData, holdButton, holdIcon, latestMeasurements
    local newOfferIDs = {}
    local lastQuestID, lastGoalIndex, lastReady
    local recommendationReason
    local compactTooltip
    local function AnchorTracker()
        frame:ClearAllPoints()
        frame:SetPoint("TOP", UIParent, "CENTER", settings.x, settings.y)
    end
    local function MigrateTrackerAnchor()
        if settings.trackerTopAnchored then return end
        if not settings.collapsed then settings.y = settings.y + frame:GetHeight() / 2 end
        settings.trackerTopAnchored = true
        AnchorTracker()
    end
    AnchorTracker()
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    function frame:UpdateOpacity()
        local opacity = settings.opacityPercent / 100
        self:SetBackdropColor(0.07, 0.06, 0.045, opacity)
        self:SetBackdropBorderColor(0.64, 0.46, 0.22, opacity)
        navigation:UpdateOpacity()
    end

    local header = CreateFrame("Frame", nil, frame)
    header:SetPoint("TOPLEFT", 8, -5)
    header:SetPoint("TOPRIGHT", -74, -5)
    header:SetHeight(24)
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function()
        if settings.lockTrackerPosition then return end
        frame:StartMoving()
    end)
    header:SetScript("OnDragStop", function()
        if settings.lockTrackerPosition then return end
        frame:StopMovingOrSizing()
        local x, y = frame:GetCenter()
        local centerX, centerY = UIParent:GetCenter()
        settings.x, settings.y = x - centerX, y - centerY + frame:GetHeight() / 2
        settings.trackerTopAnchored = true
        AnchorTracker()
    end)

    local heading = addon.UI.CreateLabel(header, "GameFontNormal")
    heading:SetPoint("LEFT", 6, 0)
    heading:SetJustifyH("LEFT")
    heading:SetMaxLines(1)
    heading:SetText("Forever Quest Navigator")

    if version then
        local versionLabel = addon.UI.CreateLabel(header, "GameFontDisableSmall")
        versionLabel:SetPoint("RIGHT", -4, 0)
        heading:SetPoint("RIGHT", versionLabel, "LEFT", -8, 0)
        versionLabel:SetText("v" .. version)
    end

    local settingsButton = MakeButton(frame)
    settingsButton:SetSize(20, 20)
    settingsButton:SetPoint("TOPRIGHT", -52, -6)
    local settingsIcon = settingsButton:CreateTexture(nil, "ARTWORK")
    settingsIcon:SetSize(16, 16)
    settingsIcon:SetPoint("CENTER")
    if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("OptionsIcon-Brown") then
        settingsIcon:SetAtlas("OptionsIcon-Brown")
    else
        settingsIcon:SetTexture("Interface\\Icons\\Trade_Engineering")
        settingsIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
    settingsButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(L.Settings)
        GameTooltip:Show()
    end)
    settingsButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
    settingsButton:SetScript("OnClick", actions.openSettings)

    local close = MakeButton(frame)
    close:SetSize(20, 20)
    close:SetPoint("TOPRIGHT", -8, -6)
    close:SetText("×")
    close:SetScript("OnClick", actions.hideTracker)

    local content = CreateFrame("Frame", nil, frame)
    content:SetAllPoints()

    local card = addon.CreateActiveQuestCard(content)
    local activeBackdrop, title, objective, activeDistance = card.backdrop, card.title, card.objective, card.distance
    local goalRows = {}
    local finishedToggle, finishedExpanded
    local finishedCount, firstFinishedRow = 0, nil
    local resetObjective, alternativesToggle, offersToggle

    local history = MakeButton(content)
    history:SetSize(116, 22)
    history:SetPoint("BOTTOMLEFT", 14, 12)
    history:SetText(L.SkippedCount:format(0))
    history:SetScript("OnClick", function(self) ShowSkippedQuests(self, actions.restore, actions.resetSkips) end)
    history:SetEnabled(false)
    history:Hide()

    local auto = MakeButton(content)
    auto:SetSize(90, 22)
    auto:SetPoint("BOTTOMRIGHT", -14, 12)
    auto:SetText(L.AutoSelect)
    auto:SetScript("OnClick", actions.resumeAutoSelect)
    auto:SetEnabled(false)
    auto:Hide()

    local activeCheckbox = CreateSkipCheckbox(content, actions.skip)
    activeCheckbox:SetPoint("TOPLEFT", 12, -31)
    activeCheckbox:Hide()

    local alternativesLabel = addon.UI.CreateLabel(content, "GameFontNormalSmall")
    alternativesLabel:SetText(L.Alternatives)
    alternativesLabel:Hide()

    local rows = {}
    for index = 1, 2 do
        local row = addon.CreateAcceptedQuestRow(content, actions, index)
        rows[index] = row
    end

    local arrow = CreateDirectionArrow(content, 20)
    arrow:SetPoint("TOPRIGHT", -76, -31)

    for _, row in ipairs(rows) do
        row.arrow = CreateDirectionArrow(row, 15)
        row.arrow:SetPoint("RIGHT", -63, 0)
    end
    local offersLabel = addon.UI.CreateLabel(content, "GameFontNormalSmall")
    offersLabel:SetText(L.NearbyQuests)
    offersLabel:Hide()
    local routeNote = addon.UI.CreateLabel(content, "GameFontNormalSmall")
    routeNote:SetJustifyH("LEFT")
    routeNote:SetMaxLines(1)
    routeNote:Hide()
    local offerRows = {}
    for index = 1, 3 do
        local row = addon.CreateOfferQuestRow(content, actions, settings, index)
        offerRows[index] = row
    end
    local routeToggle = CreateFrame("Button", nil, content)
    routeToggle:SetSize(60, 18)
    routeToggle:Hide()
    local disclosure = addon.UI.CreateLabel(routeToggle, "GameFontNormalSmall")
    disclosure:SetPoint("CENTER")
    local routeDetails = addon.UI.CreateLabel(content, "GameFontHighlightSmall")
    routeDetails:SetJustifyH("LEFT")
    routeDetails:Hide()
    local approachLabel, approachRows = nil, {}
    local routeExpanded, routeQuestID
    local otherCount = 0
    local offerCount = 0
    local alternativeOffset, offerOffset = 0, 0
    local lastRender, lastOffers, lastOfferXP
    local skippedCount = 0
    local manualSelection = false
    local questMap = CreateFrame("Button", nil, content)
    questMap:SetAllPoints(title)
    questMap:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    questMap:SetScript("OnClick", function(self, button)
        if button == "RightButton" and actions.openQuestMenu then actions.openQuestMenu(self, self.questID)
        else actions.openQuestMap(self.questID) end
    end)
    questMap:SetScript("OnEnter", function(self)
        local detail = (recommendationReason or "") .. "\n" .. L.OpenQuestMap
        if settings.detailMode == "compact" and compactTooltip then detail = detail .. "\n" .. compactTooltip end
        ShowTextTooltip(self, title:GetText(), detail)
    end)
    questMap:SetScript("OnLeave", HideTextTooltip)
    questMap:SetScript("OnHide", HideTextTooltip)
    questMap:Hide()
    local activeZone = addon.UI.CreateLabel(content, "GameFontNormalSmall")
    activeZone:SetPoint("TOPLEFT", title, "BOTTOMLEFT", -26, -5)
    activeZone:SetPoint("TOPRIGHT", title, "BOTTOMRIGHT", 90, -5)
    activeZone:SetJustifyH("LEFT")
    activeZone:SetMaxLines(1)
    activeZone:Hide()
    local routeMap, nearbyStopsButton, activeReward

    local function CreateRewardLabel(parent)
        local label = addon.UI.CreateLabel(parent, "GameFontHighlightSmall")
        label:SetJustifyH("LEFT")
        label:SetTextColor(0.68, 0.86, 1)
        label:SetMaxLines(2)
        label:Hide()
        return label
    end

    local function CreateRouteMap(parent, details, getQuestID)
        local button = MakeButton(parent)
        button:SetSize(42, 16)
        button:SetPoint("TOPLEFT", details, "TOPRIGHT", 8, 1)
        button:SetText(L.Map)
        button:SetScript("OnClick", function() actions.openQuestMap(getQuestID()) end)
        button:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(L.ShowMapTarget)
            GameTooltip:Show()
        end)
        button:SetScript("OnLeave", function() GameTooltip:Hide() end)
        button:Hide()
        return button
    end

    local function UpdateAlternativeLayout(row)
        local compact = settings.detailMode == "compact"
        row.compact = compact
        if compact then
            row.reward:Hide()
            row.zone:Hide()
            row.routeButton:Hide()
        end
        row.routeDetails:SetShown(row.routeExpanded == true and not compact)
        row.routeMap:SetShown(row.routeExpanded == true and not compact)
        row.routeLabel:SetText(row.routeExpanded and L.HideRoute or L.RouteDetails)
        local lineHeight = addon.UI.GetRowLineHeight(row)
        local secondaryHeight = math.max(14, row.reward:GetStringHeight() + 2, row.zone:GetStringHeight() + 2,
            row.routeLabel:GetStringHeight() + 2)
        local height = lineHeight
        if row.zone:IsShown() or row.routeButton:IsShown() or row.reward:IsShown() then
            height = height + secondaryHeight
        end
        local labelRight = row.routeButton:IsShown() and -102 or -4
        row.reward:ClearAllPoints()
        row.reward:SetPoint("TOPLEFT", 26, -lineHeight + 2)
        row.reward:SetPoint("TOPRIGHT", labelRight, -lineHeight + 2)
        row.zone:ClearAllPoints()
        row.zone:SetPoint("TOPLEFT", 26, -lineHeight + 2)
        row.zone:SetPoint("TOPRIGHT", labelRight, -lineHeight + 2)
        row.routeButton:SetPoint("TOPRIGHT", 0, -lineHeight + 4)
        row.routeButton:SetHeight(secondaryHeight)
        row.routeDetails:ClearAllPoints()
        row.routeDetails:SetPoint("TOPLEFT", 26, -height - 3)
        row.routeDetails:SetPoint("TOPRIGHT", -54, -height - 3)
        if row.routeExpanded and not compact then height = height + math.max(16, row.routeDetails:GetStringHeight()) + 8 end
        addon.UI.AlignNavigationRow(row, height, lineHeight, 26, 18)
    end

    local function LayoutSection(toggle, label, caption, collapsed, list, count, y)
        local shown = not settings.collapsed and count > 0
        local expanded = shown and not collapsed
        toggle:SetShown(shown)
        label:SetShown(shown)
        if shown then
            toggle:ClearAllPoints()
            toggle:SetPoint("TOPLEFT", 14, -y - 8)
            toggle:SetPoint("TOPRIGHT", -14, -y - 8)
            local offset = list == rows and alternativeOffset or offerOffset
            local limit = list == rows and (settings.acceptedRows or 2) or (settings.offerRows or 3)
            local countText = tostring(count)
            if count > limit and expanded then
                countText = ("%d–%d/%d"):format(offset + 1, math.min(offset + limit, count), count)
            end
            label:SetText(("%s  %s (%s)"):format(expanded and "−" or "+", caption, countText))
            y = y + 27
        end
        for index, row in ipairs(list) do
            local offset = list == rows and alternativeOffset or offerOffset
            local limit = list == rows and (settings.acceptedRows or 2) or (settings.offerRows or 3)
            row:SetShown(expanded and index <= math.min(limit, count - offset))
            if row:IsShown() then
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", 14, -y)
                row:SetPoint("TOPRIGHT", -14, -y)
                y = y + row:GetHeight() + 1
            end
        end
        return y
    end

    local function UpdateHeight()
        local scale = (settings.fontPercent or 100) / 100
        resetObjective:SetSize(134 * scale, math.max(16, 16 * scale))
        routeMap:SetSize(42 * scale, math.max(16, 16 * scale))
        routeToggle:SetSize(60 * scale, math.max(18, 18 * scale))
        undoSkip:SetHeight(math.max(22, undoSkip:GetFontString():GetStringHeight() + 6))
        history:SetSize(116 * scale, math.max(22, 22 * scale))
        auto:SetSize(90 * scale, math.max(22, 22 * scale))
        local targeted = goalRows[1] and goalRows[1].goal and goalRows[1].active
        local distanceWidth = math.max(60, activeDistance:GetStringWidth() + 5)
        activeDistance:ClearAllPoints()
        arrow:ClearAllPoints()
        if targeted then
            activeDistance:SetPoint("TOPRIGHT", goalRows[1], "TOPRIGHT", 0, -1)
            arrow:SetPoint("TOPRIGHT", goalRows[1], "TOPRIGHT", -distanceWidth - 1, 4)
        else
            activeDistance:SetPoint("TOPRIGHT", -14, -36)
            arrow:SetPoint("TOPRIGHT", -distanceWidth - 16, -31)
        end
        title:SetPoint("TOPRIGHT", targeted and -14 or -distanceWidth - 44, -35)
        local detailsBottom = 40 + title:GetStringHeight() + objective:GetStringHeight()
        finishedToggle:SetShown(finishedCount > 0)
        if finishedCount > 0 then
            local label = finishedCount == 1 and L.FinishedObjective or L.FinishedObjectives
            finishedToggle:SetText((finishedExpanded and "−  " or "+  ") .. label:format(finishedCount))
        end
        for index, row in ipairs(goalRows) do
            if index == firstFinishedRow then
                finishedToggle:ClearAllPoints()
                finishedToggle:SetPoint("TOPLEFT", 14, -detailsBottom)
                finishedToggle:SetPoint("TOPRIGHT", -14, -detailsBottom)
                finishedToggle:SetHeight(math.max(17, finishedToggle:GetFontString():GetStringHeight() + 5))
                detailsBottom = detailsBottom + finishedToggle:GetHeight() + 1
            end
            row:SetShown(row.goal ~= nil and (not row.goal.finished or finishedExpanded == true))
            if row:IsShown() then
                row.label:SetPoint("TOPRIGHT", row.active and -distanceWidth - 28 or -2, -1)
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", 14, -detailsBottom)
                row:SetPoint("TOPRIGHT", -14, -detailsBottom)
                local height = math.max(15, row.label:GetStringHeight() + 2)
                row:SetHeight(height)
                detailsBottom = detailsBottom + height
                if row.locked then
                    resetObjective:ClearAllPoints()
                    resetObjective:SetPoint("TOPLEFT", 27, -detailsBottom - 1)
                    detailsBottom = detailsBottom + resetObjective:GetHeight() + 3
                end
            end
        end
        if activeZone:IsShown() then
            activeZone:ClearAllPoints()
            activeZone:SetPoint("TOPLEFT", 14, -detailsBottom - 2)
            activeZone:SetPoint("TOPRIGHT", -14, -detailsBottom - 2)
            detailsBottom = detailsBottom + activeZone:GetStringHeight() + 4
        end
        if restoreAvoided and restoreAvoided:IsShown() then
            restoreAvoided:ClearAllPoints()
            restoreAvoided:SetPoint("TOPLEFT", 14, -detailsBottom - 2)
            restoreAvoided:SetPoint("TOPRIGHT", -14, -detailsBottom - 2)
            restoreAvoided:SetHeight(math.max(20, restoreAvoided:GetFontString():GetStringHeight() + 6))
            detailsBottom = detailsBottom + restoreAvoided:GetHeight() + 4
        end
        if navigationStatus and navigationStatus:IsShown() then
            navigationStatus:ClearAllPoints()
            navigationStatus:SetPoint("TOPLEFT", 14, -detailsBottom - 2)
            navigationStatus:SetPoint("TOPRIGHT", -14, -detailsBottom - 2)
            detailsBottom = detailsBottom + navigationStatus:GetStringHeight() + 4
        end
        local metaY = detailsBottom + 4
        local pinWidth = holdButton and holdButton:IsShown() and 23 * scale or 0
        local actionsWidth = (routeMap:IsShown() and 47 * scale or 0) + (routeToggle:IsShown() and 62 * scale or 0) + pinWidth
        local noteSharesRow = routeNote:IsShown() and not activeReward:IsShown()
        routeNote:ClearAllPoints()
        routeNote:SetPoint("TOPLEFT", 14, -metaY)
        routeNote:SetPoint("TOPRIGHT", -14 - (noteSharesRow and actionsWidth or 0), -metaY)
        if routeNote:IsShown() and activeReward:IsShown() then
            metaY = metaY + routeNote:GetStringHeight() + 3
        end
        local metaHeight = (actionsWidth > 0 or routeNote:IsShown()) and math.max(16, 18 * scale) or 0
        if routeNote:IsShown() then metaHeight = math.max(metaHeight, routeNote:GetStringHeight()) end
        if activeReward:IsShown() then
            activeReward:ClearAllPoints()
            activeReward:SetPoint("TOPLEFT", 14, -metaY)
            activeReward:SetPoint("TOPRIGHT", -14 - actionsWidth, -metaY)
            metaHeight = math.max(metaHeight, activeReward:GetStringHeight())
        end
        routeToggle:ClearAllPoints()
        routeToggle:SetPoint("TOPRIGHT", routeMap:IsShown() and -14 - 47 * scale or -14, -metaY + 2)
        if holdButton then
            holdButton:SetSize(20 * scale, 18 * scale)
            holdButton:ClearAllPoints()
            holdButton:SetPoint("TOPRIGHT", -14 - actionsWidth + pinWidth, -metaY + 2)
        end
        routeMap:ClearAllPoints()
        routeMap:SetPoint("TOPRIGHT", -14, -metaY + 1)
        local previewY = metaY + metaHeight + 2
        routeDetails:ClearAllPoints()
        routeDetails:SetPoint("TOPLEFT", 14, -previewY)
        routeDetails:SetPoint("TOPRIGHT", -14, -previewY)
        local previewHeight = routeDetails:IsShown() and math.max(16, routeDetails:GetStringHeight()) + 8 or 0
        local activeBottom = math.max(68, previewY + previewHeight + 2)
        if routeStopPreview and routeStopPreview:IsShown() then
            routeStopPreview:ClearAllPoints()
            routeStopPreview:SetPoint("TOPLEFT", 14, -activeBottom)
            routeStopPreview:SetPoint("TOPRIGHT", -14, -activeBottom)
            routeStopPreview:Layout()
            activeBottom = activeBottom + routeStopPreview:GetHeight() + 5
        end
        local showApproach = routeDetails:IsShown() and approachRows[1] and approachRows[1].questID ~= nil
        approachLabel:SetShown(showApproach == true)
        if showApproach then
            approachLabel:ClearAllPoints()
            approachLabel:SetPoint("TOPLEFT", 14, -activeBottom)
            activeBottom = activeBottom + 16
        end
        for _, row in ipairs(approachRows) do
            row:SetShown(showApproach == true and row.questID ~= nil)
            if row:IsShown() then
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", 14, -activeBottom)
                row:SetPoint("TOPRIGHT", -14, -activeBottom)
                activeBottom = activeBottom + row:GetHeight() + 2
            end
        end
        if nearbyStopsButton:IsShown() then
            nearbyStopsButton:ClearAllPoints()
            nearbyStopsButton:SetPoint("TOPLEFT", 14, -activeBottom)
            activeBottom = activeBottom + 17
        end
        if undoSkip and undoSkip:IsShown() then
            undoSkip:ClearAllPoints()
            undoSkip:SetPoint("TOPLEFT", 14, -activeBottom - 2)
            undoSkip:SetPoint("TOPRIGHT", -14, -activeBottom - 2)
            activeBottom = activeBottom + undoSkip:GetHeight() + 4
        end
        activeBackdrop:ClearAllPoints()
        activeBackdrop:SetPoint("TOPLEFT", 8, -29)
        activeBackdrop:SetPoint("BOTTOMRIGHT", content, "TOPRIGHT", -8, -activeBottom)
        local showLists = not settings.collapsed
        history:SetShown(showLists and skippedCount > 0)
        auto:SetShown(showLists and manualSelection)
        local listTop = activeBottom
        if progressLine then
            progressLine:SetShown(showLists and activeCheckbox.quest ~= nil and progressData ~= nil)
            if progressLine:IsShown() then
                progressLine:ClearAllPoints()
                progressLine:SetPoint("TOPLEFT", 14, -listTop - 8)
                progressLine:SetPoint("TOPRIGHT", -14, -listTop - 8)
                progressLine:SetHeight(math.max(18, progressLine:GetFontString():GetStringHeight()))
                listTop = listTop + progressLine:GetFontString():GetStringHeight() + 12
            end
        end
        local y = LayoutSection(alternativesToggle, alternativesLabel, L.Alternatives,
            settings.alternativesCollapsed, rows, otherCount, listTop)
        y = LayoutSection(offersToggle, offersLabel, L.NearbyQuests,
            settings.offersCollapsed, offerRows, offerCount, y)
        if areaOverview then areaOverview:Layout() end
        if areaOverview and areaOverview:IsShown() then
            areaOverview:ClearAllPoints()
            areaOverview:SetPoint("TOPLEFT", 14, -y - 9)
            areaOverview:SetPoint("TOPRIGHT", -14, -y - 9)
            areaOverview:Layout()
            y = y + areaOverview:GetHeight() + 9
        end
        local bottomPadding = settings.allowTrackerResize and 16 or 9
        frame:SetHeight(y + ((history:IsShown() or auto:IsShown()) and 22 + math.max(22, 22 * scale) or bottomPadding))
    end

    local function ShowRouteDetails(show)
        local visible = show and settings.detailMode ~= "compact"
        routeDetails:SetShown(visible)
        if routeStopPreview then routeStopPreview:SetExpanded(visible) end
        disclosure:SetText((show and "− " or "+ ") .. L.Route)
    end

    routeToggle:SetScript("OnClick", function()
        routeExpanded = not routeExpanded
        ShowRouteDetails(routeExpanded)
        UpdateHeight()
    end)

    local function InitializeAcceptedRow(row)
        row.routeButton = CreateFrame("Button", nil, row)
        row.routeButton:SetSize(96, 15)
        row.routeButton:SetPoint("TOPRIGHT", 0, -18)
        row.routeLabel = addon.UI.CreateLabel(row.routeButton, "GameFontNormalSmall")
        row.routeLabel:SetPoint("RIGHT")
        row.routeDetails = addon.UI.CreateLabel(row, "GameFontHighlightSmall")
        row.routeDetails:SetJustifyH("LEFT")
        row.routeDetails:SetMaxLines(7)
        row.routeButton:Hide()
        row.routeDetails:Hide()
        row.routeButton:SetScript("OnClick", function()
            row.routeExpanded = not row.routeExpanded
            UpdateAlternativeLayout(row)
            UpdateHeight()
        end)
    end
    for _, row in ipairs(rows) do InitializeAcceptedRow(row) end
    routeMap = CreateRouteMap(content, routeDetails, function() return routeQuestID end)
    frame.routeMap = routeMap
    for _, row in ipairs(rows) do
        row.routeMap = CreateRouteMap(row, row.routeDetails, function() return row.questID end)
    end
    nearbyStopsButton = CreateFrame("Button", nil, content)
    nearbyStopsButton:SetSize(196, 15)
    local nearbyLabel = addon.UI.CreateLabel(nearbyStopsButton, "GameFontNormalSmall")
    nearbyLabel:SetPoint("LEFT")
    nearbyStopsButton:SetFontString(nearbyLabel)
    nearbyStopsButton:SetNormalFontObject(addon.UI.GetFont("GameFontNormalSmall"))
    nearbyStopsButton:SetHighlightFontObject(addon.UI.GetFont("GameFontHighlightSmall"))
    nearbyStopsButton:Hide()
    frame.nearbyStopsButton = nearbyStopsButton
    nearbyStopsButton:SetScript("OnClick", function(button)
        MenuUtil.CreateContextMenu(button, function(_, menu)
            menu:CreateTitle(L.NearbyStops)
            menu:SetScrollMode(220)
            for _, stop in ipairs(button.stops) do
                local action = stop.quest.readyToTurnIn and (" · " .. L.TurnInStatus) or ""
                local label = ("%s · ~%d yd%s"):format(FormatQuestTitle(stop.quest), stop.yards, action)
                menu:CreateButton(label, actions.openQuestMap, stop.quest.id)
            end
        end)
    end)
    activeReward = CreateRewardLabel(content)
    for _, row in ipairs(rows) do
        row.reward = CreateRewardLabel(row)
        row.reward:SetMaxLines(1)
    end

    resetObjective = MakeButton(content)
    resetObjective:SetSize(134, 16)
    resetObjective:SetText(L.AutomaticObjective)
    resetObjective:SetScript("OnClick", function() actions.selectObjective() end)
    resetObjective:Hide()

    local function CreateSectionToggle(label, setting)
        local toggle = CreateFrame("Button", nil, content)
        toggle:SetHeight(20)
        label:ClearAllPoints()
        label:SetPoint("LEFT", toggle, "LEFT", 0, 0)
        label:SetPoint("RIGHT", toggle, "RIGHT", 0, 0)
        label:SetJustifyH("LEFT")
        local highlight = toggle:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints()
        highlight:SetColorTexture(0.74, 0.55, 0.28, 0.19)
        toggle:SetScript("OnClick", function()
            settings[setting] = not settings[setting]
            UpdateHeight()
        end)
        return toggle
    end
    alternativesToggle = CreateSectionToggle(alternativesLabel, "alternativesCollapsed")
    offersToggle = CreateSectionToggle(offersLabel, "offersCollapsed")

    finishedToggle = MakeButton(content)
    finishedToggle:SetHeight(17)
    local finishedLabel = finishedToggle:GetFontString()
    finishedLabel:ClearAllPoints()
    finishedLabel:SetPoint("LEFT", 6, 0)
    finishedLabel:SetPoint("RIGHT", -6, 0)
    finishedLabel:SetJustifyH("LEFT")
    finishedToggle:SetScript("OnClick", function()
        finishedExpanded = not finishedExpanded
        UpdateHeight()
    end)
    finishedToggle:Hide()

    approachLabel = addon.UI.CreateLabel(content, "GameFontNormalSmall")
    approachLabel:SetText(L.OnTheWay)
    approachLabel:Hide()

    undoSkip = MakeButton(content)
    undoSkip:SetHeight(22)
    undoSkip:Hide()
    undoSkip:SetScript("OnClick", function(self)
        local id = self.questID
        self:Hide()
        self.questID = nil
        UpdateHeight()
        if id then actions.restore(id) end
    end)
    undoSkip:SetScript("OnUpdate", function(self, elapsed)
        self.remaining = self.remaining - elapsed
        if self.remaining <= 0 then
            self:Hide()
            self.questID = nil
            UpdateHeight()
        end
    end)
    undoSkip:SetScript("OnEnter", function(self) ShowTextTooltip(self, self.questTitle, L.UndoSkip) end)
    undoSkip:SetScript("OnLeave", HideTextTooltip)
    undoSkip:SetScript("OnHide", HideTextTooltip)
    function frame:ShowUndoSkip(quest)
        undoSkip.questID, undoSkip.questTitle, undoSkip.remaining = quest.id, quest.title, 8
        undoSkip:SetText(L.UndoSkip)
        undoSkip:Show()
        UpdateHeight()
    end

    title:SetText(L.ReadingQuestLog)
    UpdateHeight()
    frame:SetShown(not settings.hidden)

    function frame:RenderNearbyOffers(offers, showXP)
        lastOffers, lastOfferXP = offers, showXP
        offerCount = offers and #offers or 0
        offerOffset = math.min(offerOffset, math.max(0, offerCount - (settings.offerRows or 3)))
        for index, row in ipairs(offerRows) do
            local offer = offers and offers[index + offerOffset]
            row.measurement = offer
            if offer then
                if newOfferIDs[offer.id] then
                    row.noticeSeconds, row.noticeQuestID = 4, offer.id
                    row.noticeDeadline = GetTime and GetTime() + 4
                    newOfferIDs[offer.id] = nil
                end
                row.discovery:SetShown(row.noticeQuestID == offer.id and (row.noticeSeconds or 0) > 0
                    and (not row.noticeDeadline or GetTime() < row.noticeDeadline))
                row.label:SetText(FormatQuestTitle(offer))
                row.distance:SetText(L.PickupDistanceCompact:format(offer.yards))
                local notes = {}
                row.recommendation:SetShown(offer.recommended == true)
                if offer.recommended then
                    notes[#notes + 1] = "|cffffc447" .. L.RecommendedOffer .. "|r"
                end
                if showXP and offer.xp then notes[#notes + 1] = L.QuestXPReward:format(offer.xp) end
                if showXP and not offer.xp then notes[#notes + 1] = L.UnknownXP end
                if offer.objectiveYards then
                    notes[#notes + 1] = L.OfferTargetSummary:format(offer.objectiveZone or L.UnknownZone, offer.objectiveYards)
                else
                    notes[#notes + 1] = offer.objectiveZone
                        and (L.OfferObjectiveZone:format(offer.objectiveZone) .. " · " .. L.OfferTargetUnknown)
                        or L.OfferTargetUnknown
                end
                if offer.nearActiveTarget then notes[#notes + 1] = L.OfferNearActiveTarget end
                row.details:SetText(table.concat(notes, " · "))
                local hasDetails = #notes > 0 and settings.detailMode ~= "compact"
                row.details:SetShown(hasDetails)
                local lineHeight = addon.UI.GetRowLineHeight(row)
                row.details:SetPoint("TOPLEFT", 5, -lineHeight + addon.UI.Style.detailGap)
                row.details:SetPoint("TOPRIGHT", -3, -lineHeight + addon.UI.Style.detailGap)
                local height = hasDetails and math.max(34, lineHeight + 1 + row.details:GetStringHeight()) or lineHeight
                addon.UI.AlignNavigationRow(row, height, lineHeight, 5, 22)
            end
        end
        UpdateHeight()
    end


    local function RenderObjectiveTargets(targets)
        navigation.goal:SetText("")
        restoreAvoided:SetShown(targets ~= nil and (targets.avoidedCount or 0) > 0)
        resetObjective:SetShown(targets ~= nil and targets.locked == true)
        finishedCount, firstFinishedRow = 0, nil
        local ordered = {}
        if targets then
            for _, goal in ipairs(targets) do ordered[#ordered + 1] = goal end
            table.sort(ordered, function(a, b)
                if a.index == targets.index then return b.index ~= targets.index end
                if b.index == targets.index then return false end
                if a.finished ~= b.finished then return not a.finished end
                return a.index < b.index
            end)
        end
        for position, goal in ipairs(ordered) do
            local row = goalRows[position] or addon.CreateObjectiveRow(content, actions)
            goalRows[position] = row
            local active = goal.index == targets.index
            row.goal = goal
            row.active = active
            row.locked = active and targets.locked
            row.goalHighlight:SetShown(goal.selectable)
            row.indicator:SetText(goal.avoided and "×" or (active and (row.locked and "•" or ">") or ""))
            if goal.finished or goal.avoided then
                firstFinishedRow = firstFinishedRow or position
                finishedCount = finishedCount + 1
                row.label:SetTextColor(0.67, 0.67, 0.67)
            elseif active then
                row.label:SetTextColor(1, 0.82, 0.34)
                navigation.goal:SetText(goal.text)
            else
                row.label:SetTextColor(1, 1, 1)
            end
            row.label:SetText(goal.text)
            row.label:ClearAllPoints()
            row.label:SetPoint("TOPLEFT", 13, -1)
            row.label:SetPoint("TOPRIGHT", active and -88 or -2, -1)
        end
        for position = #ordered + 1, #goalRows do
            goalRows[position].goal = nil
        end
    end

    local function RenderApproachStops(stops)
        local count = stops and math.min(#stops, 3) or 0
        for index = 1, count do
            local quest = stops[index].quest
            local row = approachRows[index]
            if not row then
                row = MakeButton(content)
                row:SetHeight(20)
                local label = row:GetFontString()
                label:ClearAllPoints()
                label:SetPoint("LEFT", 6, 0)
                label:SetPoint("RIGHT", -6, 0)
                label:SetJustifyH("LEFT")
                label:SetMaxLines(1)
                row:SetScript("OnClick", function(self) actions.openQuestMap(self.questID) end)
                row:SetScript("OnEnter", function(self)
                    ShowTextTooltip(self, self:GetText(), L.ShowMapTarget)
                end)
                row:SetScript("OnLeave", HideTextTooltip)
                row:SetScript("OnHide", HideTextTooltip)
                approachRows[index] = row
            end
            row.questID = quest.id
            local format = quest.readyToTurnIn and L.OnTheWayTurnIn or L.OnTheWayObjective
            row:SetText(format:format(FormatQuestTitle(quest)))
        end
        for index = count + 1, #approachRows do approachRows[index].questID = nil end
    end

    function frame:Render(quest, objectiveText, skippedQuests, alternatives, hasManualSelection, routeText, routePreview,
        zones, routes, nearbyStops, rewards, targets, hasMap, approachStops, reason, previewStops, area)
        lastRender = { quest, objectiveText, skippedQuests, alternatives, hasManualSelection, routeText, routePreview,
            zones, routes, nearbyStops, rewards, targets, hasMap, approachStops, reason, previewStops, area }
        areaOverview:SetData(area)
        recommendationReason = reason
        compactTooltip = (routePreview or "") .. "\n" .. (rewards and rewards[1] or "")
        if undoSkip.questID and not skippedQuests[undoSkip.questID] then undoSkip:Hide() end
        activeCheckbox.quest = quest
        if holdButton then
            holdButton:SetShown(quest ~= nil)
            local held = actions.getQuestHold and actions.getQuestHold()
            holdIcon:SetVertexColor(held and 1 or 0.55, held and 0.78 or 0.55, held and 0.2 or 0.55)
        end
        local goalIndex = targets and targets.index
        if quest and lastQuestID then
            if quest.id == lastQuestID and quest.readyToTurnIn and not lastReady then
                navigation:Notify(L.QuestNowReady)
            elseif quest.id ~= lastQuestID then
                navigation:Notify(L.ActiveQuestChanged)
            elseif goalIndex and goalIndex ~= lastGoalIndex then
                navigation:Notify(L.NavigationGoalChanged)
            end
        end
        lastQuestID, lastGoalIndex, lastReady = quest and quest.id, goalIndex, quest and quest.readyToTurnIn
        if routeQuestID ~= (quest and quest.id) then finishedExpanded = false end
        navigation.title:SetText(quest and FormatQuestTitle(quest) or "")
        RenderObjectiveTargets(targets)
        activeCheckbox:SetShown(quest ~= nil)
        questMap.questID = quest and quest.id
        questMap:SetShown(quest ~= nil)
        activeDistance:SetText(quest and FormatDistance() or "")
        local reward = rewards and rewards[1]
        activeReward:SetText(reward or "")
        activeReward:SetShown(reward ~= nil and settings.detailMode ~= "compact")
        local zone = zones and zones[1]
        activeZone:SetText(zone or "")
        activeZone:SetShown(zone ~= nil and settings.detailMode ~= "compact")
        skippedCount = 0
        for _ in pairs(skippedQuests) do skippedCount = skippedCount + 1 end
        history.skippedQuests = skippedQuests
        history:SetText(L.SkippedCount:format(skippedCount))
        history:SetEnabled(skippedCount > 0)
        manualSelection = hasManualSelection == true
        auto:SetEnabled(manualSelection)
        local count = alternatives and #alternatives or 0
        otherCount = count
        alternativeOffset = math.min(alternativeOffset, math.max(0, count - (settings.acceptedRows or 2)))
        routeNote:SetText(routeText or "")
        routeNote:SetShown(routeText ~= nil and (settings.detailMode ~= "compact" or hasManualSelection))
        routeToggle:SetShown(routePreview ~= nil and settings.detailMode ~= "compact")
        local questID = quest and quest.id
        if routeQuestID ~= questID or not routePreview then routeExpanded = false end
        routeQuestID = questID
        routeMap:SetShown(hasMap == true)
        routeDetails:SetText(routePreview or "")
        routeStopPreview:Render(previewStops)
        RenderApproachStops(approachStops)
        ShowRouteDetails(routeExpanded == true)
        nearbyStopsButton.stops = nearbyStops
        nearbyStopsButton:SetShown(nearbyStops ~= nil and settings.detailMode ~= "compact")
        if nearbyStops then
            local count = #nearbyStops
            nearbyStopsButton:SetText(count == 1 and L.NearbyStopOne or L.NearbyStopMany:format(count))
        end
        for index, row in ipairs(rows) do
            local dataIndex = index + alternativeOffset
            local alternative = alternatives and alternatives[dataIndex]
            local id = alternative and alternative.id
            local details = routes and routes[dataIndex]
            if row.questID ~= id or not details then row.routeExpanded = false end
            row.questID = id
            row.measurement = nil
            row.checkbox.quest = alternative
            if alternative then
                local alternativeReward = rewards and rewards[dataIndex + 1]
                row.reward:SetText(alternativeReward or "")
                row.reward:SetShown(alternativeReward ~= nil)
                local alternativeZone = zones and zones[dataIndex + 1]
                row.zone:SetText(alternativeZone or "")
                row.zone:SetShown(alternativeZone ~= nil and not alternativeReward)
                row.routeButton:SetShown(details ~= nil)
                row.routeDetails:SetText(details or "")
                UpdateAlternativeLayout(row)
                row.label:SetText(FormatQuestTitle(alternative))
                row.distance:SetText(FormatDistance())
            end
        end
        if not quest then
            title:SetText(objectiveText)
            objective:SetText("")
        else
            title:SetText(FormatQuestTitle(quest))
            objective:SetText(objectiveText)
        end
        UpdateHeight()
        MigrateTrackerAnchor()
    end

    function frame:RenderDistances(measurements)
        latestMeasurements = measurements
        if activeCheckbox.quest then
            local distance = FormatDistance(measurements[activeCheckbox.quest.id])
            activeDistance:SetText(distance)
            navigation.distance:SetText(distance)
        end
        for _, row in ipairs(rows) do
            if row.questID then
                row.measurement = measurements[row.questID]
                row.distance:SetText(FormatDistance(row.measurement))
                UpdateAlternativeLayout(row)
            end
        end
        UpdateHeight()
    end

    function frame:RenderDirection(right, forward, status, arrived)
        local quest = activeCheckbox.quest
        if quest and latestMeasurements then
            local measured = latestMeasurements[quest.id]
            if measured and measured.marker.accessPoint then
                navigation.goal:SetText(L.AccessGoal:format(measured.marker.accessName or L.SavedAccess))
            else
                for _, row in ipairs(goalRows) do
                    if row.active and row.goal then navigation.goal:SetText(row.goal.text) break end
                end
            end
            local distance = arrived and (quest.readyToTurnIn and L.TurnInAction or L.ArrivedShort)
                or FormatDistance(latestMeasurements[quest.id])
            if activeDistance:GetText() ~= distance then
                activeDistance:SetText(distance)
                UpdateHeight()
            end
            navigation.distance:SetText(distance)
        end
        if settings.showScreenArrow then
            arrow:SetDirection()
        else
            arrow:SetDirection(right, forward)
        end
        local separate = settings.displayMode == "arrow" or (frame:IsVisible() and settings.showScreenArrow)
        local hasQuest = activeCheckbox.quest ~= nil
        local showNavigation = separate and hasQuest and (right ~= nil or status ~= nil)
        navigation.arrow:SetDirection(right, forward)
        navigation:SetStatus(status)
        navigation:SetShown(showNavigation == true)
        local localStatus = not separate and hasQuest and status or ""
        if navigationStatus:GetText() ~= localStatus then
            navigationStatus:SetText(localStatus)
            navigationStatus:SetShown(localStatus ~= "")
            UpdateHeight()
        end
    end

    local function RenderRowDirections(list, facing)
        for _, row in ipairs(list) do
            local direction = row.measurement
            row.arrow:SetDirection(addon.QuestLocation.GetRelativeDirection(direction and direction.east and direction, facing))
        end
    end

    function frame:RenderRowDirections(facing)
        RenderRowDirections(rows, facing)
        RenderRowDirections(offerRows, facing)
    end

    local resizeGrip = CreateFrame("Button", nil, content)
    resizeGrip:SetSize(15, 15)
    resizeGrip:SetPoint("BOTTOMRIGHT", -4, 4)
    resizeGrip:RegisterForDrag("LeftButton")
    local gripTexture = resizeGrip:CreateTexture(nil, "ARTWORK")
    gripTexture:SetAllPoints()
    gripTexture:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    resizeGrip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    resizeGrip:SetScript("OnDragStart", function(self)
        if settings.lockTrackerPosition then return end
        local scale = frame:GetEffectiveScale()
        local startCursorX = GetCursorPosition()
        local startWidth = frame:GetWidth()
        local x, y = frame:GetCenter()
        local top = y + frame:GetHeight() / 2
        local centerX, centerY = UIParent:GetCenter()
        self:SetScript("OnUpdate", function()
            local cursorX = GetCursorPosition()
            local width = ClampTrackerWidth(math.floor(startWidth + (cursorX - startCursorX) / scale + 0.5))
            if width == settings.trackerWidth then return end
            settings.trackerWidth = width
            settings.x, settings.y = x - centerX + (width - startWidth) / 2, top - centerY
            settings.trackerTopAnchored = true
            frame:SetWidth(width)
            AnchorTracker()
            for _, row in ipairs(rows) do
                if row.questID and row.routeExpanded then UpdateAlternativeLayout(row) end
            end
            UpdateHeight()
        end)
    end)
    local function StopResizing(self)
        self:SetScript("OnUpdate", nil)
    end
    resizeGrip:SetScript("OnDragStop", StopResizing)
    resizeGrip:SetScript("OnHide", StopResizing)
    resizeGrip:SetShown(settings.allowTrackerResize == true)

    function frame:UpdateResizeGrip()
        resizeGrip:SetShown(settings.allowTrackerResize == true)
        UpdateHeight()
    end

    local collapse = MakeButton(frame)
    collapse:SetSize(20, 20)
    collapse:SetPoint("TOPRIGHT", -30, -6)
    local function UpdateCollapseButton()
        collapse:SetText(settings.collapsed and "+" or "−")
    end
    local function ShowCollapseTooltip(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(settings.collapsed and L.ExpandTracker or L.CollapseTracker)
        GameTooltip:Show()
    end
    collapse:SetScript("OnEnter", ShowCollapseTooltip)
    collapse:SetScript("OnLeave", function() GameTooltip:Hide() end)
    collapse:SetScript("OnClick", function(self)
        settings.collapsed = not settings.collapsed
        UpdateHeight()
        UpdateCollapseButton()
        if self:IsMouseOver() then ShowCollapseTooltip(self) end
    end)
    UpdateCollapseButton()

    navigation = addon.CreateNavigationDisplay(settings)
    routeStopPreview = addon.CreateRoutePreview(content, actions)
    restoreAvoided = MakeButton(content)
    restoreAvoided:SetText(L.RestoreAvoidedObjectives)
    restoreAvoided:SetScript("OnClick", actions.restoreAvoidedObjectives)
    restoreAvoided:Hide()
    areaOverview = addon.CreateAreaOverview(content, settings, { openRouteStop = actions.openRouteStop, onLayout = UpdateHeight })
    navigationStatus = addon.UI.CreateLabel(content, "GameFontHighlightSmall")
    navigationStatus:SetJustifyH("LEFT")
    navigationStatus:SetMaxLines(2)
    navigationStatus:SetText("")
    navigationStatus:Hide()
    function frame:ResetPositions()
        frame:StopMovingOrSizing()
        resizeGrip:SetScript("OnUpdate", nil)
        settings.x, settings.y = 0, 140 + frame:GetHeight() / 2
        settings.trackerTopAnchored = true
        AnchorTracker()
        navigation:ResetPosition()
    end
    local function SetScrollHandler(owner, kind)
        owner:EnableMouseWheel(true)
        if owner == alternativesToggle or owner == offersToggle then
            owner:SetScript("OnEnter", function(self)
                local caption = kind == "accepted" and L.Alternatives or L.NearbyQuests
                ShowTextTooltip(self, caption, L.ListRowsHelp)
            end)
            owner:SetScript("OnLeave", HideTextTooltip)
            owner:SetScript("OnHide", HideTextTooltip)
        end
        owner:SetScript("OnMouseWheel", function(_, delta)
            if kind == "accepted" then
                alternativeOffset = math.max(0, math.min(alternativeOffset - delta,
                    otherCount - (settings.acceptedRows or 2)))
                if lastRender then frame:Render(unpack(lastRender, 1, 17)) end
            else
                offerOffset = math.max(0, math.min(offerOffset - delta, offerCount - (settings.offerRows or 3)))
                frame:RenderNearbyOffers(lastOffers, lastOfferXP)
            end
            if actions.refreshMeasurements then actions.refreshMeasurements() end
        end)
    end
    SetScrollHandler(alternativesToggle, "accepted")
    SetScrollHandler(offersToggle, "offers")
    for _, row in ipairs(rows) do SetScrollHandler(row, "accepted") end
    for _, row in ipairs(offerRows) do SetScrollHandler(row, "offers") end
    function frame:UpdateListSettings()
        for index = #rows + 1, settings.acceptedRows or 2 do
            local row = addon.CreateAcceptedQuestRow(content, actions, index)
            row.arrow = CreateDirectionArrow(row, 15)
            InitializeAcceptedRow(row)
            row.routeMap = CreateRouteMap(row, row.routeDetails, function() return row.questID end)
            row.reward = CreateRewardLabel(row)
            row.reward:SetMaxLines(1)
            SetScrollHandler(row, "accepted")
            rows[index] = row
        end
        for index = #offerRows + 1, settings.offerRows or 3 do
            local row = addon.CreateOfferQuestRow(content, actions, settings, index)
            SetScrollHandler(row, "offers")
            offerRows[index] = row
        end
        if lastRender then self:Render(unpack(lastRender, 1, 17)) end
        self:RenderNearbyOffers(lastOffers, lastOfferXP)
        if actions.refreshMeasurements then actions.refreshMeasurements() end
    end
    function frame:UpdateFontSize()
        addon.UI.SetFontSize(settings.fontPercent)
        for _, row in ipairs(rows) do
            if row.questID then UpdateAlternativeLayout(row) end
        end
        if lastRender then self:Render(unpack(lastRender, 1, 17)) end
        self:RenderNearbyOffers(lastOffers, lastOfferXP)
        navigation:UpdateLayout()
        if actions.refreshMeasurements then actions.refreshMeasurements() end
    end
    function frame:SetProgress(value)
        progressData = value
        progressLine:SetText((value.open == 1 and L.QuestProgressOne or L.QuestProgress):format(value.open, value.turnIns))
        UpdateHeight()
    end
    function frame:ResetAppearance()
        settings.trackerWidth = 352
        settings.collapsed, settings.alternativesCollapsed, settings.offersCollapsed = false, false, false
        settings.areaOverviewExpanded, settings.targetGroupsExpanded = false, {}
        alternativeOffset, offerOffset = 0, 0
        finishedExpanded, routeExpanded = false, false
        ShowRouteDetails(false)
        frame:SetWidth(352)
        self:UpdateListSettings()
        self:UpdateFontSize()
        self:UpdateOpacity()
        self:UpdateResizeGrip()
        self:ResetPositions()
        UpdateCollapseButton()
    end
    function frame:SetNewOffers(ids)
        newOfferIDs = {}
        local found
        for id in pairs(ids) do newOfferIDs[id], found = true, true end
        if found then navigation:Notify(L.NewRecommendedOffer) end
    end
    progressLine = CreateFrame("Button", nil, content)
    progressLine:SetFontString(addon.UI.CreateLabel(progressLine, "GameFontDisableSmall"))
    progressLine:GetFontString():ClearAllPoints()
    progressLine:GetFontString():SetPoint("TOPLEFT")
    progressLine:GetFontString():SetPoint("TOPRIGHT")
    progressLine:GetFontString():SetJustifyH("LEFT")
    progressLine:SetHeight(18)
    progressLine:Hide()
    addon.UI.BindTooltip(progressLine, function()
        local detail = L.QuestProgressHelp
        if progressData and progressData.unknown > 0 then
            local text = progressData.unknown == 1 and L.QuestProgressUnknownOne or L.QuestProgressUnknown
            detail = detail .. "\n" .. text:format(progressData.unknown)
        end
        return progressLine:GetText(), detail
    end)
    holdButton = MakeButton(content)
    holdIcon = holdButton:CreateTexture(nil, "ARTWORK")
    holdIcon:SetSize(16, 16)
    holdIcon:SetPoint("CENTER")
    holdIcon:SetAtlas("Waypoint-MapPin-Untracked")
    holdButton:SetScript("OnClick", actions.toggleQuestHold)
    addon.UI.BindTooltip(holdButton, function()
        return actions.getQuestHold and actions.getQuestHold() and L.ReleaseQuest or L.HoldQuest, L.HoldQuestHelp
    end)
    holdButton:Hide()
    frame.holdButton, frame.progressLine = holdButton, progressLine
    frame:UpdateOpacity()

    return frame
end
