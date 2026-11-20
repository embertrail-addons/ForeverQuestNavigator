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
    local progressLine, progressData, holdButton, holdIcon, latestMeasurements, detailPanel, changeNotice
    local acceptedIDs, offerIDs = {}, {}
    local newOfferIDs = {}
    local lastQuestID, lastGoalIndex, lastReady
    local recommendationReason
    local flightMode, flightStatus = false, nil
    local combatMode = false
    local function IsQuiet() return flightMode or combatMode end
    local function IsNarrow() return settings.adaptiveLayout ~= false and frame:GetWidth() / ((settings.fontPercent or 100) / 100) < 340 end
    local function IsCompact() return settings.detailMode == "compact" or IsQuiet() or IsNarrow() end
    local function FormatDistance(value) return addon.UI.FormatDistance(value, IsNarrow()) end
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
        addon.UI.Theme.Frame(self, opacity)
        navigation:UpdateOpacity()
        if detailPanel then detailPanel:UpdateOpacity() end
    end

    local header = CreateFrame("Frame", nil, frame)
    header:SetPoint("TOPLEFT", 8, -5)
    header:SetPoint("TOPRIGHT", -94, -5)
    header:SetHeight(24)
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function()
        if settings.lockTrackerPosition and not frame.arranging then return end
        frame:StartMoving()
    end)
    header:SetScript("OnDragStop", function()
        if settings.lockTrackerPosition and not frame.arranging then return end
        frame:StopMovingOrSizing()
        local x, y = frame:GetCenter()
        local centerX, centerY = UIParent:GetCenter()
        x, y = x - centerX, y - centerY
        if frame.arranging then x, y = addon.LayoutGeometry.Snap(x, y, frame:GetWidth(), frame:GetHeight(), UIParent:GetWidth(), UIParent:GetHeight()) end
        settings.x, settings.y = x, y + frame:GetHeight() / 2
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
    settingsButton:SetPoint("TOPRIGHT", -72, -6)
    addon.UI.ExpandHitArea(settingsButton, 4)
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
    addon.UI.ExpandHitArea(close, 4)
    close:SetText("×")
    close:SetScript("OnClick", actions.hideTracker)

    local content = CreateFrame("Frame", nil, frame)
    content:SetAllPoints()
    local body, viewport, pinnedBackdrop, detailExplanation = content
    local function CurrentZone()
        local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
        if mapID and C_Map.GetMapInfo then
            local _, zone = addon.QuestLocation.GetZone(C_Map, Enum and Enum.UIMapType, mapID)
            if zone then return zone end
        end
        local info = mapID and C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
        return info and info.name or (GetRealZoneText and GetRealZoneText())
    end

    local card = addon.CreateActiveQuestCard(content)
    local activeBackdrop, title, objective, activeDistance = card.backdrop, card.title, card.objective, card.distance
    local goalRows = {}
    local statusLine, moreGoals, expandedGoals, emptyMessage, emptyAction
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
    auto:SetText(L.NavigatorResume)
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
    local listLimits = {accepted = settings.acceptedRows or 2, offers = settings.offerRows or 3}
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
        local _, state = addon.QuestState.Read(activeCheckbox.quest, false, manualSelection)
        local detail = state .. "\n" .. addon.TrackerPresentation.Summary(recommendationReason, 2)
        local summary = lastRender and addon.TrackerPresentation.Information(lastRender[8] and lastRender[8][1],
            lastRender[11] and lastRender[11][1])
        if summary and summary ~= "" then detail = detail .. "\n" .. summary end
        detail = detail .. "\n" .. L.OpenQuestMap .. "\n" .. L.NavigatorDetailsHint
        ShowTextTooltip(self, title:GetText(), detail)
    end)
    questMap:SetScript("OnLeave", HideTextTooltip)
    questMap:SetScript("OnHide", HideTextTooltip)
    addon.UI.LinkQuestHover(questMap, function(self) return self.questID end)
    questMap:Hide()
    local activeZone = addon.UI.CreateLabel(content, "GameFontNormalSmall")
    activeZone:SetPoint("TOPLEFT", title, "BOTTOMLEFT", -42, -5)
    activeZone:SetPoint("TOPRIGHT", title, "BOTTOMRIGHT", 90, -5)
    activeZone:SetJustifyH("LEFT")
    activeZone:SetMaxLines(1)
    activeZone:Hide()
    local routeMap, nearbyStopsButton, activeReward

    local function CreateRewardLabel(parent)
        local label = addon.UI.CreateLabel(parent, "GameFontHighlightSmall")
        label:SetJustifyH("LEFT")
        addon.UI.Theme.Bind(label, "muted", nil, "text")
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
        local compact = IsCompact()
        row.compact = compact
        if compact then
            row.reward:Hide()
            row.zone:Hide()
            if row.specialStatus then row.reward:SetText(row.specialStatus) row.reward:Show() end
        end
        -- Details live in their own pane; a row never grows when opened.
        row.routeMap:Hide()
        row.routeLabel:SetText("i")
        local lineHeight = addon.UI.GetRowLineHeight(row)
        local secondaryHeight = math.max(14, row.reward:GetStringHeight() + 2, row.zone:GetStringHeight() + 2,
            row.routeLabel:GetStringHeight() + 2, row.actionBadge:IsShown() and row.actionBadge:GetStringHeight() + 4 or 0)
        local height = lineHeight
        if row.zone:IsShown() or row.reward:IsShown() or row.actionBadge:IsShown() then
            height = height + secondaryHeight
        end
        local badgeWidth = row.actionBadge:IsShown() and row.actionBadge:GetStringWidth() + 12 or 0
        row.actionBadge:ClearAllPoints() row.actionBadge:SetPoint("TOPLEFT", 8, -lineHeight - 2)
        row.badgeBackground:SetShown(row.actionBadge:IsShown())
        local labelRight = -4
        row.reward:ClearAllPoints()
        row.reward:SetPoint("TOPLEFT", 5 + badgeWidth, -lineHeight - 2)
        row.reward:SetPoint("TOPRIGHT", labelRight, -lineHeight - 2)
        row.zone:ClearAllPoints()
        row.zone:SetPoint("TOPLEFT", 5 + badgeWidth, -lineHeight - 2)
        row.zone:SetPoint("TOPRIGHT", labelRight, -lineHeight - 2)
        addon.UI.AlignNavigationRow(row, height, lineHeight, 5, 18)
    end

    local function LayoutSection(toggle, label, caption, collapsed, list, count, y)
        local shown = not settings.collapsed and not IsQuiet() and (settings.navigatorView or "all") == "all" and count > 0
        local expanded = shown and not collapsed
        toggle:SetShown(shown)
        label:SetShown(shown)
        if shown then
            toggle:ClearAllPoints()
            toggle:SetPoint("TOPLEFT", 14, -y - 8)
            toggle:SetPoint("TOPRIGHT", -14, -y - 8)
            local limit = list == rows and listLimits.accepted or listLimits.offers
            local countText = tostring(count)
            if count > limit and expanded then
                countText = ("%d/%d"):format(math.min(limit, count), count)
            end
            label:SetText(("%s  %s (%s)"):format(expanded and "−" or "+", caption, countText))
            local headerHeight = math.max(18, label:GetStringHeight() + 4)
            toggle:SetHeight(headerHeight)
            y = y + 8 + headerHeight + 4
        end
        for index, row in ipairs(list) do
            local limit = list == rows and listLimits.accepted or listLimits.offers
            row:SetShown(expanded and index <= math.min(limit, count))
            if row:IsShown() then
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", 14, -y)
                row:SetPoint("TOPRIGHT", -14, -y)
                y = y + row:GetHeight() + 1
            end
        end
        local more = frame.moreEntries and frame.moreEntries[list == rows and "accepted" or "offers"]
        if more then
            local limit = list == rows and listLimits.accepted or listLimits.offers
            more:SetShown(expanded and count > limit)
            if more:IsShown() then
                more:SetText(L.NavigatorMoreEntries:format(math.min(count - limit, list == rows and (settings.acceptedRows or 2) or (settings.offerRows or 3))))
                more:ClearAllPoints() more:SetPoint("TOPLEFT", 14, -y - 4)
                more:SetPoint("TOPRIGHT", -14, -y - 4)
                more:SetHeight(math.max(22, more:GetFontString():GetStringHeight() + 6))
                y = y + more:GetHeight() + 8
            end
        end
        return y
    end

    local function UpdateHeight()
        local scale = (settings.fontPercent or 100) / 100
        if activeReward and lastRender then
            local rewards, zones = lastRender[11], lastRender[8]
            activeReward:SetText(addon.TrackerPresentation.Information(zones and zones[1], rewards and rewards[1]))
            activeReward:SetShown(activeReward:GetText() ~= "" and not IsCompact() and not settings.collapsed and settings.navigatorView ~= "goal")
            activeZone:Hide()
            routeNote:Hide()
        end
        resetObjective:SetSize(134 * scale, math.max(16, 16 * scale))
        routeMap:SetSize(42 * scale, math.max(16, 16 * scale))
        routeToggle:SetSize(60 * scale, math.max(18, 18 * scale))
        undoSkip:SetHeight(math.max(22, undoSkip:GetFontString():GetStringHeight() + 6))
        history:SetSize(116 * scale, math.max(22, 22 * scale))
        auto:SetSize(144 * scale, math.max(20, 20 * scale))
        local targeted = goalRows[1] and goalRows[1].goal and goalRows[1].active
        local distanceWidth = math.max(76 * scale, activeDistance:GetStringWidth() + 5)
        activeDistance:ClearAllPoints()
        arrow:ClearAllPoints()
        if targeted then
            activeDistance:SetParent(body) arrow:SetParent(body)
            activeDistance:SetPoint("TOPRIGHT", goalRows[1], "TOPRIGHT", 0, -1)
            arrow:SetPoint("TOPRIGHT", goalRows[1], "TOPRIGHT", -distanceWidth - 1, 4)
        else
            activeDistance:SetParent(content) arrow:SetParent(content)
            activeDistance:SetPoint("TOPRIGHT", -14, -36)
            arrow:SetPoint("TOPRIGHT", -distanceWidth - 16, -31)
        end
        title:SetPoint("TOPRIGHT", targeted and -14 or -distanceWidth - 44, -35)
        local detailsBottom = 40 + title:GetStringHeight()
        if statusLine and statusLine:IsShown() then
            statusLine:ClearAllPoints()
            statusLine:SetPoint("TOPLEFT", 14, -detailsBottom)
            statusLine:SetPoint("TOPRIGHT", manualSelection and -164 * scale or -14, -detailsBottom)
            auto:ClearAllPoints() auto:SetPoint("TOPRIGHT", -14, -detailsBottom + 2)
            detailsBottom = detailsBottom + math.max(statusLine:GetStringHeight(), manualSelection and auto:GetHeight() or 0) + 6
        end
        local pinnedHeight = detailsBottom
        if viewport then detailsBottom = 0 end
        local hasGoals = goalRows[1] and goalRows[1].goal ~= nil
        objective:SetShown(not hasGoals and not (activeCheckbox.quest and activeCheckbox.quest.readyToTurnIn))
        if objective:IsShown() then
            objective:ClearAllPoints() objective:SetPoint("TOPLEFT", 14, -detailsBottom)
            objective:SetPoint("TOPRIGHT", -14, -detailsBottom)
            detailsBottom = detailsBottom + objective:GetStringHeight() + 3
        end
        local compactGoals = (settings.navigatorView ~= "quest" and IsCompact()) or settings.collapsed or settings.navigatorView == "goal"
        local hiddenGoals = 0
        finishedToggle:SetShown(finishedCount > 0 and not IsQuiet())
        if finishedCount > 0 then
            local label = finishedCount == 1 and L.FinishedObjective or L.FinishedObjectives
            finishedToggle:SetText((finishedExpanded and "−  " or "+  ") .. label:format(finishedCount))
        end
        for index, row in ipairs(goalRows) do
            if index == firstFinishedRow and not IsQuiet() then
                finishedToggle:ClearAllPoints()
                finishedToggle:SetPoint("TOPLEFT", 14, -detailsBottom)
                finishedToggle:SetPoint("TOPRIGHT", -14, -detailsBottom)
                finishedToggle:SetHeight(math.max(17, finishedToggle:GetFontString():GetStringHeight() + 5))
                detailsBottom = detailsBottom + finishedToggle:GetHeight() + 1
            end
            local focus = row.active or (not targeted and index == 1)
            local unfinished = row.goal and not row.goal.finished and not row.goal.avoided
            if compactGoals and not focus and unfinished then hiddenGoals = hiddenGoals + 1 end
            row:SetShown((row.goal ~= nil and (not row.goal.finished and not row.goal.avoided or finishedExpanded == true)
                and (not compactGoals or focus or expandedGoals or ((row.goal.finished or row.goal.avoided) and finishedExpanded))
                and (not IsQuiet() or focus)) == true)
            if row:IsShown() then
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", 14, -detailsBottom)
                row:SetPoint("TOPRIGHT", -14, -detailsBottom)
                row.caption:SetPoint("TOPRIGHT", -distanceWidth - 28, -2)
                local captionHeight = row.active and row.caption:GetStringHeight() + 5 or 0
                row.label:ClearAllPoints() row.label:SetPoint("TOPLEFT", 8, -captionHeight - 2)
                row.label:SetPoint("TOPRIGHT", row.counter:IsShown() and -row.counter:GetStringWidth() - 12 or -4, -captionHeight - 2)
                row.counter:ClearAllPoints() row.counter:SetPoint("TOPRIGHT", -4, -captionHeight - 2)
                local height = captionHeight + math.max(15, row.label:GetStringHeight(), row.counter:GetStringHeight()) + (row.fraction and 7 or 4)
                if row.fraction then row.bar:SetWidth(math.max(0.1, (body:GetWidth() - 40) * row.fraction)) end
                row:SetHeight(height)
                detailsBottom = detailsBottom + height
                if row.locked then
                    resetObjective:ClearAllPoints()
                    resetObjective:SetPoint("TOPLEFT", 27, -detailsBottom - 1)
                    detailsBottom = detailsBottom + resetObjective:GetHeight() + 3
                end
            end
        end
        if moreGoals then
            moreGoals:SetShown(compactGoals and hiddenGoals > 0 and not IsQuiet())
            if moreGoals:IsShown() then
                moreGoals:SetText(expandedGoals and L.NavigatorLessGoals or (hiddenGoals == 1 and L.NavigatorMoreGoal or L.NavigatorMoreGoals:format(hiddenGoals)))
                moreGoals:ClearAllPoints() moreGoals:SetPoint("TOPLEFT", 14, -detailsBottom - 2)
                moreGoals:SetPoint("TOPRIGHT", -14, -detailsBottom - 2)
                moreGoals:SetHeight(math.max(22, moreGoals:GetFontString():GetStringHeight() + 6))
                detailsBottom = detailsBottom + moreGoals:GetHeight() + 5
            end
        end
        if emptyMessage and emptyMessage:IsShown() then
            emptyMessage:ClearAllPoints() emptyMessage:SetPoint("TOPLEFT", 14, -detailsBottom - 3)
            emptyMessage:SetPoint("TOPRIGHT", -14, -detailsBottom - 3)
            detailsBottom = detailsBottom + emptyMessage:GetStringHeight() + 8
            if emptyAction:IsShown() then
                emptyAction:ClearAllPoints() emptyAction:SetPoint("TOPLEFT", 14, -detailsBottom)
                detailsBottom = detailsBottom + emptyAction:GetHeight() + 5
            end
        end
        if frame.questItem and frame.questItem.hint then
            local host = frame.questItem.host
            host:ClearAllPoints() host:SetPoint("TOPLEFT", 14, -detailsBottom - 2)
            host:SetPoint("TOPRIGHT", -14, -detailsBottom - 2)
            host:SetHeight(math.max(36, host.label:GetStringHeight() + 6))
            detailsBottom = detailsBottom + host:GetHeight() + 6
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
        if navigationStatus then navigationStatus:Hide() end
        local metaY = detailsBottom + 4
        local pinWidth = holdButton and holdButton:IsShown() and 23 * scale or 0
        local actionsWidth = (routeMap:IsShown() and 47 * scale or 0) + (routeToggle:IsShown() and 62 * scale or 0) + pinWidth
        routeNote:ClearAllPoints()
        routeNote:SetPoint("TOPLEFT", 14, -metaY)
        routeNote:SetPoint("TOPRIGHT", -14, -metaY)
        if activeReward:IsShown() then
            activeReward:ClearAllPoints()
            activeReward:SetPoint("TOPLEFT", 14, -metaY)
            activeReward:SetPoint("TOPRIGHT", -14, -metaY)
            metaY = metaY + activeReward:GetStringHeight() + 6
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
        local previewY = metaY + (actionsWidth > 0 and math.max(16, 18 * scale) or 0) + 2
        local activeBottom = math.max(viewport and 0 or 68, previewY + 2)
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
        activeBackdrop:SetPoint("TOPLEFT", 8, viewport and 0 or -29)
        activeBackdrop:SetPoint("BOTTOMRIGHT", body, "TOPRIGHT", -8, -activeBottom)
        local showLists = not settings.collapsed and not IsQuiet() and (settings.navigatorView or "all") == "all"
        history:SetShown(showLists and skippedCount > 0)
        auto:SetShown(activeCheckbox.quest ~= nil and manualSelection and not IsQuiet())
        local listTop = activeBottom
        local y = LayoutSection(alternativesToggle, alternativesLabel, L.Alternatives,
            settings.alternativesCollapsed, rows, otherCount, listTop)
        y = LayoutSection(offersToggle, offersLabel, L.NearbyQuests,
            settings.offersCollapsed, offerRows, offerCount, y)
        if areaOverview then areaOverview:Layout() end
        if areaOverview and not showLists then areaOverview:Hide() end
        if areaOverview and areaOverview:IsShown() then
            areaOverview:ClearAllPoints()
            areaOverview:SetPoint("TOPLEFT", 14, -y - 9)
            areaOverview:SetPoint("TOPRIGHT", -14, -y - 9)
            areaOverview:Layout()
            y = y + areaOverview:GetHeight() + 9
        end
        local bottomPadding = settings.allowTrackerResize and 16 or 9
        local footer = history:IsShown() and 22 + math.max(22, 22 * scale) or bottomPadding
        if frame.noticeSlot then
            local hasContext = activeCheckbox.quest ~= nil or frame.detour ~= nil
            frame.noticeSlot:SetShown(hasContext)
            if hasContext then
                local slotHeight = math.max(20, 18 * scale + 4)
                frame.noticeSlot:ClearAllPoints()
                frame.noticeSlot:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", 14, footer)
                frame.noticeSlot:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -14, footer)
                frame.noticeSlot:SetHeight(slotHeight)
                footer = footer + slotHeight + 6
            end
        end
        if viewport then
            pinnedBackdrop:ClearAllPoints() pinnedBackdrop:SetPoint("TOPLEFT", 8, -29)
            pinnedBackdrop:SetPoint("BOTTOMRIGHT", content, "TOPRIGHT", -8, -pinnedHeight)
            frame:SetHeight(viewport:Layout(pinnedHeight, y, footer))
            if viewport.reflow and not frame.reflowing then
                frame.reflowing = true UpdateHeight() frame.reflowing = nil
            end
        else frame:SetHeight(y + footer) end
        if detailPanel then
            if detailPanel:IsShown() then detailPanel:Layout() end
            detailPanel:RefreshSelection()
            disclosure:SetText(detailPanel:IsShown() and detailPanel.key == "active:" .. tostring(routeQuestID) and L.NavigatorCloseDetails or L.DetailsShort)
        end
        if frame.RefreshNotice then frame:RefreshNotice() end
    end

    local function ShowRouteDetails(show)
        local visible = show and not IsQuiet()
        disclosure:SetText(L.DetailsShort)
        if not detailPanel then return end
        if visible then
            local widgets = {routeDetails}
            if detailExplanation and detailExplanation:GetText() ~= "" then widgets[#widgets + 1] = detailExplanation end
            if routeStopPreview and routeStopPreview.hasStops then widgets[#widgets + 1] = routeStopPreview end
            if approachRows[1] and approachRows[1].questID then
                widgets[#widgets + 1] = approachLabel
                for _, row in ipairs(approachRows) do if row.questID then widgets[#widgets + 1] = row end end
            end
            detailPanel:SetContent("active:" .. tostring(routeQuestID), title:GetText(), widgets,
                routeMap:IsShown() and function() actions.openQuestMap(routeQuestID) end or nil,
                function() if activeCheckbox.quest then actions.skip(activeCheckbox.quest) end end)
        elseif detailPanel.key == "active:" .. tostring(routeQuestID) then detailPanel:Hide() end
    end

    routeToggle:SetScript("OnClick", function()
        routeExpanded = not (routeExpanded and detailPanel:IsShown() and detailPanel.key == "active:" .. tostring(routeQuestID))
        ShowRouteDetails(routeExpanded)
        UpdateHeight()
    end)

    local function InitializeAcceptedRow(row)
        row.routeButton = CreateFrame("Button", nil, row)
        addon.UI.ExpandHitArea(row.routeButton, 3, 1)
        row.routeButton:SetSize(20, 22)
        row.detailButton = row.routeButton
        row.routeButton:SetPoint("TOPRIGHT", 0, -18)
        row.routeLabel = addon.UI.CreateLabel(row.routeButton, "GameFontNormalSmall")
        row.routeLabel:SetPoint("CENTER")
        addon.UI.Theme.Bind(row.routeLabel, "muted", nil, "text")
        row.routeDetails = addon.UI.CreateLabel(row, "GameFontHighlightSmall")
        row.routeDetails:SetJustifyH("LEFT")
        row.routeButton:Hide()
        row.routeDetails:Hide()
        row.actionBadge = addon.UI.CreateLabel(row, "GameFontNormalSmall")
        row.actionBadge:SetText(L.NavigatorTurnIn) row.actionBadge:Hide()
        row.badgeBackground = row:CreateTexture(nil, "BACKGROUND")
        row.badgeBackground:SetPoint("TOPLEFT", row.actionBadge, "TOPLEFT", -3, 2)
        row.badgeBackground:SetPoint("BOTTOMRIGHT", row.actionBadge, "BOTTOMRIGHT", 3, -2)
        addon.UI.Theme.Bind(row.badgeBackground, "highlight", .2) row.badgeBackground:Hide()
        row.detailExplanation = addon.UI.CreateLabel(row, "GameFontHighlightSmall")
        row.detailExplanation:SetJustifyH("LEFT") row.detailExplanation:Hide()
        row.routeButton:SetScript("OnClick", function()
            local key = "accepted:" .. tostring(row.questID)
            if detailPanel:IsShown() and detailPanel.key == key then detailPanel:Hide() return end
            routeExpanded = false
            local quest = row.checkbox.quest
            row.detailExplanation:SetText(quest and (quest.demoDetails or addon.DescribeQuest and addon.DescribeQuest(quest, row.measurement)) or "")
            detailPanel:SetContent(key, row.label:GetText(), {row.routeDetails, row.detailExplanation}, function() actions.openQuestMap(row.questID) end,
                function() if row.checkbox.quest then actions.skip(row.checkbox.quest) end end)
        end)
        addon.UI.BindTooltip(row.routeButton, function() return L.NavigatorDetails end)
    end
    for _, row in ipairs(rows) do InitializeAcceptedRow(row) end
    routeMap = CreateRouteMap(content, routeDetails, function() return routeQuestID end)
    frame.routeMap = routeMap
    frame.routeToggle, frame.routeDetails = routeToggle, routeDetails
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
    frame.activeInfoLabel = activeReward
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
        addon.UI.ExpandHitArea(toggle, 2)
        toggle:SetHeight(20)
        label:SetParent(toggle)
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
    frame.sectionHeaders = {{toggle = alternativesToggle, label = alternativesLabel}, {toggle = offersToggle, label = offersLabel}}

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
    frame.finishedToggle = finishedToggle

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
        local playerZone = CurrentZone()
        local order
        order, offerIDs = addon.TrackerPresentation.VisualOrder(offerIDs, offers,
            frame:IsMouseOver() or (detailPanel and detailPanel:IsShown()) or (viewport and viewport.offset > 0))
        offerCount = offers and #offers or 0
        for index, row in ipairs(offerRows) do
            local offer = offers and offers[order[index]]
            if detailPanel and detailPanel.key == "offer:" .. tostring(row.measurement and row.measurement.id)
                and row.measurement and (not offer or row.measurement.id ~= offer.id) then detailPanel:Hide() end
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
                row.stateGlyph:SetText("") row.stateGlyph:Hide()
                row.distance:SetText(FormatDistance(offer))
                row.recommendation:SetShown(offer.recommended == true)
                row.fullDetails = select(2, row:Describe())
                if row.detailText then row.detailText:SetText(row.fullDetails or "") end
                row.details:SetText(addon.TrackerPresentation.Information(
                    offer.objectiveZone ~= (playerZone or offer.pickupZone) and offer.objectiveZone or nil,
                    showXP and (offer.xp and L.QuestXPReward:format(offer.xp) or L.UnknownXP) or nil,
                    offer.capacityFull and L.QuestLogFull or offer.recommended and L.RecommendedOffer or nil))
                local hasDetails = row.details:GetText() ~= "" and not IsCompact()
                row.details:SetShown(hasDetails)
                local lineHeight = addon.UI.GetRowLineHeight(row)
                row.details:SetMaxLines(1)
                row.details:SetPoint("TOPLEFT", 5, -lineHeight - addon.UI.Style.detailGap)
                row.details:SetPoint("TOPRIGHT", -24, -lineHeight - addon.UI.Style.detailGap)
                local height = hasDetails and math.max(34, lineHeight + 4 + row.details:GetStringHeight()) or lineHeight
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
            local row = goalRows[position] or addon.CreateObjectiveRow(body, actions)
            goalRows[position] = row
            local active = goal.index == targets.index
            row.goal = goal
            row.active = active
            row.locked = active and targets.locked
            row.activeMark:SetShown(active and not goal.finished)
            row.accent:SetShown(active and not goal.finished)
            row.caption:SetText(row.locked and L.NavigatorLockedGoal or L.NavigatorCurrentGoal)
            row.caption:SetShown(active and not goal.finished)
            row.goalHighlight:SetShown(goal.selectable)
            row.indicator:SetText("") row.indicator:Hide()
            if goal.finished or goal.avoided then
                firstFinishedRow = firstFinishedRow or position
                finishedCount = finishedCount + 1
                row.label:SetTextColor(addon.UI.Theme.Color("muted"))
            elseif active then
                row.label:SetTextColor(addon.UI.Theme.Color("heading"))
                navigation.goal:SetText(goal.text)
            else
                row.label:SetTextColor(addon.UI.Theme.Color("text"))
            end
            local description, counter, fraction = addon.TrackerPresentation.ObjectiveProgress(goal)
            row.label:SetText(description)
            row.counter:SetText(counter or "") row.counter:SetShown(counter ~= nil)
            row.counter:SetTextColor(addon.UI.Theme.Color((goal.finished or goal.avoided) and "muted" or (active and "heading" or "text")))
            row.fraction = fraction
            row.bar:SetShown(fraction ~= nil and fraction > 0 and not goal.finished and not goal.avoided)
            row.barBackground:SetShown(fraction ~= nil and not goal.finished and not goal.avoided)
            row.label:ClearAllPoints()
            row.label:SetPoint("TOPLEFT", 13, -1)
            row.label:SetPoint("TOPRIGHT", active and -88 or -2, -1)
        end
        for position = #ordered + 1, #goalRows do
            goalRows[position].goal = nil
        end
    end

    local function RenderApproachStops(stops)
        approachLabel:Hide()
        for _, row in ipairs(approachRows) do row:Hide() end
        local count = stops and math.min(#stops, 3) or 0
        for index = 1, count do
            local quest = stops[index].quest
            local row = approachRows[index]
            if not row then
                row = MakeButton(body)
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
                row:Hide()
            end
            row.questID = quest.id
            local format = quest.readyToTurnIn and L.OnTheWayTurnIn or L.OnTheWayObjective
            row:SetText(format:format(FormatQuestTitle(quest)))
        end
        for index = count + 1, #approachRows do approachRows[index].questID = nil end
    end

    function frame:RenderSnapshot(snapshot, skippedQuests)
        local view = snapshot.view
        self.changeNotice = view.changeNotice
        self.summaryImportant = view.summaryImportant
        self:Render(view.quest, view.objectives, skippedQuests, view.alternatives, view.manual,
            view.routeNote, view.routeDetails, view.zones, view.alternativeRoutes, view.nearbyStops,
            view.rewards, view.targets, view.hasMap, view.approachStops, view.reason, view.preview, view.area)
        addon.QuestHover.Refresh()
    end

    function frame:Render(quest, objectiveText, skippedQuests, alternatives, hasManualSelection, routeText, routePreview,
        zones, routes, nearbyStops, rewards, targets, hasMap, approachStops, reason, previewStops, area)
        local emptyMessage, emptyAction, statusLine = self.emptyMessage, self.emptyAction, self.statusLine
        local viewport, detailExplanation, detailPanel = self.viewport, self.detailExplanation, self.detailPanel
        heading:SetText(IsNarrow() and "FQN" or "Forever Quest Navigator")
        lastRender = { quest, objectiveText, skippedQuests, alternatives, hasManualSelection, routeText, routePreview,
            zones, routes, nearbyStops, rewards, targets, hasMap, approachStops, reason, previewStops, area }
        areaOverview:SetData(area)
        recommendationReason = reason
        if detailExplanation then detailExplanation:SetText(reason or "") end
        if undoSkip.questID and not skippedQuests[undoSkip.questID] then undoSkip:Hide() end
        if detailPanel and routeQuestID ~= (quest and quest.id) and detailPanel.key
            and detailPanel.key:find("active:", 1, true) == 1 then detailPanel:Hide() end
        activeCheckbox.quest = quest
        if routeQuestID ~= (quest and quest.id) then self.statusMessage = "" end
        if not quest then self.noticeMessage, self.noticeRemaining = nil, nil self:RefreshNotice() end
        if self.questItem then self.questItem:SetQuest(quest) end
        if emptyMessage then
            local missing = quest ~= nil and hasMap == false
            emptyMessage:SetText(not quest and L.NavigatorEmptyQuests or missing and L.NavigatorMissingCoordinates or "")
            emptyMessage:SetShown(not quest or missing)
            emptyAction:SetText(quest and L.Map or L.QuestFinder)
            emptyAction:SetShown((missing and actions.openQuestMap ~= nil) or (not quest and actions.openFinder ~= nil))
            emptyAction.questID = quest and quest.id
        end
        card.stateGlyph:Hide()
        if statusLine then
            statusLine:SetText(addon.TrackerPresentation.QuestStatus(quest, hasManualSelection))
            statusLine:SetShown(quest ~= nil)
        end
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
                local message = self.changeNotice or (reason and addon.TrackerPresentation.Summary(reason, 2)) or L.ActiveQuestChanged
                navigation:Notify(message)
                self.noticeMessage, self.noticeRemaining = message, 4
                self:RefreshNotice()
            elseif goalIndex and goalIndex ~= lastGoalIndex then
                navigation:Notify(L.NavigationGoalChanged)
            end
        end
        lastQuestID, lastGoalIndex, lastReady = quest and quest.id, goalIndex, quest and quest.readyToTurnIn
        if routeQuestID ~= (quest and quest.id) then finishedExpanded, expandedGoals = false, false end
        if viewport and routeQuestID ~= (quest and quest.id) then viewport:ScrollBy(-viewport.offset) end
        navigation.title:SetText(quest and FormatQuestTitle(quest) or "")
        navigation:SetQuestState(quest, hasManualSelection)
        RenderObjectiveTargets(targets)
        self:UpdateTargetLabel()
        if quest and navigation.goal:GetText() == "" then
            navigation.goal:SetText(quest.readyToTurnIn and L.TurnInAction or objectiveText or "")
        end
        activeCheckbox:Hide()
        questMap.questID = quest and quest.id
        questMap:SetShown(quest ~= nil)
        activeDistance:SetText(quest and FormatDistance() or "")
        local reward = rewards and rewards[1]
        activeReward:SetText(reward or "")
        activeReward:SetShown(reward ~= nil and not IsCompact())
        local zone = zones and zones[1]
        activeZone:SetText(zone or "")
        activeZone:SetShown(zone ~= nil and not IsCompact())
        skippedCount = 0
        for _ in pairs(skippedQuests) do skippedCount = skippedCount + 1 end
        history.skippedQuests = skippedQuests
        history:SetText(L.SkippedCount:format(skippedCount))
        history:SetEnabled(skippedCount > 0)
        manualSelection = hasManualSelection == true
        auto:SetEnabled(manualSelection)
        local count = alternatives and #alternatives or 0
        otherCount = count
        local order
        order, acceptedIDs = addon.TrackerPresentation.VisualOrder(acceptedIDs, alternatives,
            frame:IsMouseOver() or (detailPanel and detailPanel:IsShown()) or (viewport and viewport.offset > 0))
        routeNote:SetText(routeText or "")
        routeNote:SetShown(routeText ~= nil and self.summaryImportant ~= false and (not IsCompact() or hasManualSelection))
        routeToggle:SetShown(routePreview ~= nil or reason ~= nil)
        local questID = quest and quest.id
        if routeQuestID ~= questID or not routePreview then routeExpanded = false end
        routeQuestID = questID
        routeMap:SetShown(hasMap == true)
        routeDetails:SetText(routePreview or "")
        routeStopPreview:Render(previewStops)
        RenderApproachStops(approachStops)
        nearbyStopsButton.stops = nearbyStops
        nearbyStopsButton:SetShown(nearbyStops ~= nil and not IsCompact())
        if nearbyStops then
            local count = #nearbyStops
            nearbyStopsButton:SetText(count == 1 and L.NearbyStopOne or L.NearbyStopMany:format(count))
        end
        for index, row in ipairs(rows) do
            local dataIndex = order[index]
            local alternative = alternatives and alternatives[dataIndex]
            local id = alternative and alternative.id
            local details = routes and routes[dataIndex]
            if row.questID ~= id or not details then row.routeExpanded = false end
            if detailPanel and row.questID ~= id and detailPanel.key == "accepted:" .. tostring(row.questID) then detailPanel:Hide() end
            row.questID = id
            row.measurement = nil
            row.checkbox.quest = alternative
            if alternative then
                local alternativeReward = rewards and rewards[dataIndex + 1]
                row.specialStatus = nil
                row.actionBadge:SetShown(alternative.readyToTurnIn == true)
                if alternative.elite or alternative.group then
                    row.specialStatus = row.specialStatus and (row.specialStatus .. " · " .. L.GroupQuest) or L.GroupQuest
                end
                if row.specialStatus then alternativeReward = row.specialStatus .. (alternativeReward and (" · " .. alternativeReward) or "") end
                row.reward:SetText(alternativeReward or "")
                row.reward:SetShown(alternativeReward ~= nil)
                local alternativeZone = zones and zones[dataIndex + 1]
                if alternativeReward and alternativeZone then row.reward:SetText(alternativeReward .. " · " .. alternativeZone) end
                row.zone:SetText(alternativeZone or "")
                row.zone:SetShown(alternativeZone ~= nil and not alternativeReward)
                row.routeButton:SetShown(details ~= nil)
                row.routeDetails:SetText(details or "")
                UpdateAlternativeLayout(row)
                row.label:SetText(FormatQuestTitle(alternative))
                row.stateGlyph:SetText("") row.stateGlyph:Hide()
                row.distance:SetText(FormatDistance())
                if detailPanel and detailPanel:IsShown() and detailPanel.key == "accepted:" .. tostring(id) then
                    row.detailExplanation:SetText(alternative.demoDetails or addon.DescribeQuest and addon.DescribeQuest(alternative, row.measurement) or "")
                    detailPanel:SetContent(detailPanel.key, row.label:GetText(), {row.routeDetails, row.detailExplanation}, function() actions.openQuestMap(row.questID) end,
                        function() if row.checkbox.quest then actions.skip(row.checkbox.quest) end end)
                end
            end
        end
        if not quest then
            title:SetText(objectiveText)
            objective:SetText("")
        else
            title:SetText(FormatQuestTitle(quest))
            objective:SetText(objectiveText)
        end
        ShowRouteDetails(routeExpanded == true)
        UpdateHeight()
        MigrateTrackerAnchor()
    end

    function frame:RenderDistances(measurements)
        latestMeasurements = measurements
        self:UpdateTargetLabel()
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

    function frame:SetDetour(point, measured)
        local changed = (self.detour ~= nil) ~= (point ~= nil)
        self.detour, self.detourMeasurement = point, measured
        if changed then UpdateHeight() end
    end
    function frame:RenderDirection(right, forward, status, arrived)
        if flightMode then status, arrived = flightStatus or L.FlightGeneric, false end
        local quest = activeCheckbox.quest
        local target = quest and latestMeasurements and latestMeasurements[quest.id]
        local quality = addon.NavigationHints.Short(target and target.marker)
        if not status and quest and not self.detour then status = quality end
        if quest and latestMeasurements then
            local measured = latestMeasurements[quest.id]
            if measured and measured.marker.accessPoint then
                navigation.goal:SetText(L.AccessGoal:format(measured.marker.accessName or L.SavedAccess)
                    .. (measured.marker.accessNote and (" · " .. measured.marker.accessNote) or ""))
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
        local separate = settings.showDirectionArrow ~= false and (settings.displayMode == "arrow" or (frame:IsVisible() and settings.showScreenArrow))
        local hasQuest = activeCheckbox.quest ~= nil or self.detour ~= nil
        if self.detour then
            navigation.title:SetText(self.detour.tourReturn and L.ReturnPoint or L.TemporaryDetour)
            navigation.goal:SetText(self.detour.name)
            navigation.distance:SetText(FormatDistance(self.detourMeasurement))
        elseif quest then navigation.title:SetText(FormatQuestTitle(quest))
        else navigation.title:SetText("") navigation.goal:SetText("") navigation.distance:SetText("") end
        local showNavigation = separate and hasQuest and (right ~= nil or status ~= nil)
        navigation.arrow:SetDirection(right, forward)
        if self.arranging then
            showNavigation = true
            if not hasQuest then
                navigation.title:SetText(L.ArrangeArrow) navigation.goal:SetText(L.ArrangeDrag)
                navigation.arrow:SetDirection(0, 1)
            end
        end
        navigation:SetStatus(status)
        local measured = quest and latestMeasurements and latestMeasurements[quest.id]
        local close = not IsQuiet() and measured and measured.yards <= 35
        navigation.goal:SetMaxLines(close and 2 or 1)
        navigation.distance:SetFontObject(addon.UI.GetFont(close and "GameFontNormal" or "GameFontHighlightSmall"))
        navigation.distance:SetTextColor(addon.UI.Theme.Color(close and "heading" or "text"))
        navigation:UpdateLayout()
        navigation:SetShown(showNavigation == true)
        local localStatus = hasQuest and status ~= quality and status or ""
        if self.detour then localStatus = self.detour.name .. " · " .. FormatDistance(self.detourMeasurement) end
        self.statusMessage = localStatus
        self:RefreshNotice()
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
            local wasNarrow = IsNarrow()
            settings.trackerWidth = width
            settings.x, settings.y = x - centerX + (width - startWidth) / 2, top - centerY
            settings.trackerTopAnchored = true
            frame:SetWidth(width)
            AnchorTracker()
            if wasNarrow ~= IsNarrow() then
                if lastRender then frame:Render(unpack(lastRender, 1, 17)) end
                frame:RenderNearbyOffers(lastOffers, lastOfferXP)
                if latestMeasurements then frame:RenderDistances(latestMeasurements) end
            end
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
    collapse:SetPoint("TOPRIGHT", -40, -6)
    addon.UI.ExpandHitArea(collapse, 4)
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
    frame.routeStopPreview = routeStopPreview
    restoreAvoided = MakeButton(content)
    restoreAvoided:SetText(L.RestoreAvoidedObjectives)
    restoreAvoided:SetScript("OnClick", actions.restoreAvoidedObjectives)
    restoreAvoided:Hide()
    areaOverview = addon.CreateAreaOverview(content, settings, { openRouteStop = actions.openRouteStop, onLayout = UpdateHeight })
    frame.areaOverview = areaOverview
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
            if viewport then viewport:ScrollBy(-delta * 36) end
        end)
    end
    SetScrollHandler(alternativesToggle, "accepted")
    SetScrollHandler(offersToggle, "offers")
    for _, row in ipairs(rows) do SetScrollHandler(row, "accepted") end
    for _, row in ipairs(offerRows) do SetScrollHandler(row, "offers") end
    function frame:EnsureListRows()
        for index = #rows + 1, listLimits.accepted do
            local row = addon.CreateAcceptedQuestRow(body, actions, index)
            row.arrow = CreateDirectionArrow(row, 15)
            InitializeAcceptedRow(row)
            row.routeMap = CreateRouteMap(row, row.routeDetails, function() return row.questID end)
            row.reward = CreateRewardLabel(row)
            row.reward:SetMaxLines(1)
            if self.RegisterAcceptedDetails then self.RegisterAcceptedDetails(row) end
            SetScrollHandler(row, "accepted")
            rows[index] = row
        end
        for index = #offerRows + 1, listLimits.offers do
            local row = addon.CreateOfferQuestRow(body, actions, settings, index)
            if self.InitializeOfferDetails then self.InitializeOfferDetails(row) end
            SetScrollHandler(row, "offers")
            offerRows[index] = row
        end
    end
    function frame:UpdateListSettings()
        listLimits.accepted, listLimits.offers = settings.acceptedRows or 2, settings.offerRows or 3
        self:EnsureListRows()
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
    function frame:SetFlightView(flying, status)
        flightStatus = status
        if flightMode == flying then return end
        flightMode = flying
        if lastRender then self:Render(unpack(lastRender, 1, 17)) end
        self:RenderNearbyOffers(lastOffers, lastOfferXP)
    end
    function frame:SetCombatView(fighting)
        navigation.quiet = fighting or flightMode
        if combatMode == fighting then return end
        combatMode = fighting
        if lastRender then self:Render(unpack(lastRender, 1, 17)) end
        self:RenderNearbyOffers(lastOffers, lastOfferXP)
    end
    function frame:ResetAppearance()
        settings.trackerWidth = 352
        settings.collapsed, settings.alternativesCollapsed, settings.offersCollapsed = false, false, false
        settings.areaOverviewExpanded, settings.targetGroupsExpanded = false, {}
        listLimits.accepted, listLimits.offers = settings.acceptedRows or 2, settings.offerRows or 3
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
    progressLine:GetFontString():SetMaxLines(1)
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
    frame.navigation = navigation
    emptyMessage = addon.UI.CreateLabel(content, "GameFontDisableSmall")
    emptyMessage:SetJustifyH("LEFT") emptyMessage:SetMaxLines(3) emptyMessage:Hide()
    emptyAction = MakeButton(content) emptyAction:SetSize(190, 22) emptyAction:Hide()
    emptyAction:SetScript("OnClick", function(self)
        if self.questID then actions.openQuestMap(self.questID)
        elseif actions.openFinder then actions.openFinder() end
    end)
    frame.emptyMessage, frame.emptyAction = emptyMessage, emptyAction
    statusLine = addon.UI.CreateLabel(content, "GameFontDisableSmall")
    statusLine:SetJustifyH("LEFT") statusLine:SetMaxLines(2) statusLine:Hide()
    moreGoals = MakeButton(content)
    moreGoals:SetScript("OnClick", function() expandedGoals = not expandedGoals UpdateHeight() end)
    moreGoals:Hide()
    frame.statusLine, frame.moreGoals, frame.goalRows, frame.resumeAuto = statusLine, moreGoals, goalRows, auto
    changeNotice = addon.UI.CreateLabel(content, "GameFontDisableSmall")
    changeNotice:SetJustifyH("LEFT") changeNotice:SetMaxLines(1) changeNotice:Hide()
    frame.noticeSlot = CreateFrame("Frame", nil, content)
    frame.noticeSlot:EnableMouse(true)
    changeNotice:SetParent(frame.noticeSlot)
    changeNotice:SetPoint("TOPLEFT", 0, -2) changeNotice:SetPoint("TOPRIGHT", 0, -2)
    progressLine:SetParent(frame.noticeSlot)
    progressLine:ClearAllPoints() progressLine:SetPoint("TOPLEFT", 0, -2) progressLine:SetPoint("TOPRIGHT", 0, -2)
    progressLine:SetHeight(20)
    function frame:RefreshNotice()
        local message = self.statusMessage ~= "" and self.statusMessage or nil
        message = message or self.noticeMessage or ""
        changeNotice:SetText(message) changeNotice:SetShown(message ~= "")
        progressLine:SetShown(message == "" and progressData ~= nil and activeCheckbox.quest ~= nil
            and not IsQuiet() and not settings.collapsed and (settings.navigatorView or "all") == "all")
        changeNotice:SetTextColor(addon.UI.Theme.Color(self.statusMessage and self.statusMessage ~= "" and "heading" or "muted"))
    end
    addon.UI.BindTooltip(frame.noticeSlot, function() if changeNotice:GetText() ~= "" then return changeNotice:GetText() end end)
    frame.noticeLabel = changeNotice
    frame:HookScript("OnUpdate", function(self, elapsed)
        if not self.noticeRemaining then return end
        self.noticeRemaining = self.noticeRemaining - elapsed
        if self.noticeRemaining <= 0 then
            self.noticeRemaining, self.noticeMessage = nil, nil self:RefreshNotice()
        end
    end)
    detailPanel = addon.CreateNavigatorDetails(frame, settings)
    detailExplanation = addon.UI.CreateLabel(detailPanel.body, "GameFontHighlightSmall")
    detailExplanation:SetJustifyH("LEFT") detailExplanation:Hide()
    frame.detailExplanation = detailExplanation
    detailPanel.onClose = function() routeExpanded = false disclosure:SetText(L.DetailsShort) end
    frame.detailPanel = detailPanel
    function frame:OpenDetails()
        if not activeCheckbox.quest then return end
        routeExpanded = true
        ShowRouteDetails(true)
    end
    local function InitializeOfferDetails(row)
        row.detailButton = MakeButton(row)
        row.detailButton:SetText("i")
        addon.UI.Theme.Bind(row.detailButton.textLabel, "muted", nil, "text")
        row.detailText = addon.UI.CreateLabel(detailPanel.body, "GameFontHighlightSmall")
        row.detailText:SetJustifyH("LEFT")
        row.detailText:Hide()
        row.detailButton:SetScript("OnClick", function()
            if not row.measurement then return end
            local key = "offer:" .. tostring(row.measurement.id)
            if detailPanel:IsShown() and detailPanel.key == key then detailPanel:Hide() return end
            routeExpanded = false
            row.detailText:SetText(row.fullDetails or "")
            detailPanel:SetContent(key, row.label:GetText(), {row.detailText}, function() actions.openOfferMap(row.measurement.id) end)
        end)
        addon.UI.BindTooltip(row.detailButton, function() return L.NavigatorOfferHint end)
        detailPanel:RegisterRow(row, function() return "offer:" .. tostring(row.measurement and row.measurement.id) end, row.detailButton.textLabel)
    end
    frame.InitializeOfferDetails = InitializeOfferDetails
    for _, row in ipairs(offerRows) do InitializeOfferDetails(row) end
    local function RegisterAcceptedDetails(row)
        detailPanel:RegisterRow(row, function() return "accepted:" .. tostring(row.questID) end, row.routeLabel)
    end
    frame.RegisterAcceptedDetails = RegisterAcceptedDetails
    for _, row in ipairs(rows) do RegisterAcceptedDetails(row) end
    detailPanel:RegisterRow(questMap, function() return "active:" .. tostring(routeQuestID) end)
    frame.acceptedRows, frame.offerRows = rows, offerRows
    viewport = addon.CreateNavigatorViewport(frame, settings)
    body = viewport.body
    frame.viewport, frame.scrollBody = viewport, body
    frame.questTitle, frame.header, frame.questMap = title, header, questMap
    content.scrollBody = body
    pinnedBackdrop = content:CreateTexture(nil, "BACKGROUND")
    addon.UI.Theme.Bind(pinnedBackdrop, "active", .55)
    for _, widget in ipairs({activeBackdrop, card.accent, objective, alternativesToggle, offersToggle, routeNote,
        routeToggle, activeZone, activeReward, routeMap, nearbyStopsButton, resetObjective, finishedToggle,
        approachLabel, undoSkip, restoreAvoided, areaOverview, navigationStatus, holdButton, moreGoals,
        emptyMessage, emptyAction}) do
        widget:SetParent(body)
    end
    for _, row in ipairs(rows) do row:SetParent(body) end
    for _, row in ipairs(offerRows) do row:SetParent(body) end
    frame.moreEntries = {}
    for _, key in ipairs({"accepted", "offers"}) do
        local kind = key
        local button = MakeButton(body)
        button:Hide() frame.moreEntries[kind] = button
        button:SetScript("OnClick", function()
            local total = kind == "accepted" and otherCount or offerCount
            local step = kind == "accepted" and (settings.acceptedRows or 2) or (settings.offerRows or 3)
            listLimits[kind] = math.min(total, listLimits[kind] + step)
            frame:EnsureListRows()
            if lastRender then frame:Render(unpack(lastRender, 1, 17)) end
            frame:RenderNearbyOffers(lastOffers, lastOfferXP)
            if actions.refreshMeasurements then actions.refreshMeasurements() end
        end)
    end
    function frame:UpdateTargetLabel()
        local quest = activeCheckbox.quest
        local measurement = quest and latestMeasurements and latestMeasurements[quest.id]
        local quality = addon.NavigationHints.Short(measurement and measurement.marker)
        for _, row in ipairs(goalRows) do
            if row.active then row.caption:SetText((row.locked and L.NavigatorLockedGoal or L.NavigatorCurrentGoal) .. " · " .. quality) end
        end
    end
    function frame:SetNavigatorView(view)
        if view ~= "goal" and view ~= "quest" and view ~= "all" then return end
        settings.navigatorView, settings.collapsed, expandedGoals = view, false, false
        UpdateCollapseButton() UpdateHeight()
    end
    frame.UpdateNavigatorLayout = UpdateHeight
    frame.Reanchor = AnchorTracker
    frame.questItem = addon.CreateQuestItemButton(frame, body)
    function frame:GetQuestItemHint() return self.questItem.hint end
    frame.layoutEditor = addon.CreateLayoutEditor(frame, navigation, settings)
    function frame:ArrangeUI() self.layoutEditor:Start() end
    header:SetScript("OnMouseUp", function(self, button)
        if button ~= "RightButton" or not (MenuUtil and MenuUtil.CreateContextMenu) then return end
        MenuUtil.CreateContextMenu(self, function(_, menu)
            menu:CreateTitle(L.NavigatorView)
            for _, value in ipairs({"goal", "quest", "all"}) do
                local key = value
                menu:CreateRadio(L["NavigatorView_" .. key], function() return (settings.navigatorView or "all") == key end,
                    function() frame:SetNavigatorView(key) end)
            end
        end)
    end)
    addon.UI.BindTooltip(header, function() return L.NavigatorView, L.NavigatorViewHint end)
    UpdateHeight()
    card.stateGlyph = addon.UI.CreateStateGlyph(content)
    card.stateGlyph:SetPoint("TOPLEFT", 40, -37)
    addon.UI.Theme.Bind(card.stateGlyph, "heading", nil, "text")
    frame:UpdateOpacity()

    return frame
end
