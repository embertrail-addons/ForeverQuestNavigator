local _, addon = ...
local L = addon.L

local mapMarker, markedTarget, updateMapMarker

function addon.ShowQuestMapMarker(target, removeMarker)
    if target == markedTarget and mapMarker then return end
    markedTarget = target
    if not target then
        if mapMarker then mapMarker:Hide() end
        return
    end
    if not mapMarker then
        local map = WorldMapFrame
        if not (map and map.GetCanvas and map.GetMapID and map.OnMapChanged and hooksecurefunc) then return end
        local canvas = map:GetCanvas()
        if not canvas then return end
        mapMarker = CreateFrame("Button", nil, canvas)
        mapMarker:SetSize(20, 20)
        mapMarker:SetFrameLevel(canvas:GetFrameLevel() + 50)
        mapMarker:RegisterForClicks("RightButtonUp")
        if mapMarker.SetPassThroughButtons then mapMarker:SetPassThroughButtons("LeftButton") end
        mapMarker:SetScript("OnClick", function(_, button)
            if button == "RightButton" then
                GameTooltip:Hide()
                removeMarker()
            end
        end)
        mapMarker:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(L.MapMarker)
            GameTooltip:AddLine(L.RemoveMarker)
            GameTooltip:Show()
        end)
        mapMarker:SetScript("OnLeave", function() GameTooltip:Hide() end)
        local corners = { { 0, 10 }, { 10, 0 }, { 0, -10 }, { -10, 0 } }
        for _, layer in ipairs({ "ARTWORK", "OVERLAY" }) do
            for index, corner in ipairs(corners) do
                local nextCorner = corners[index % #corners + 1]
                local line = mapMarker:CreateLine(nil, layer)
                if layer == "ARTWORK" then
                    line:SetColorTexture(0.1, 0.06, 0.02, 1)
                    line:SetThickness(5)
                else
                    line:SetColorTexture(1, 0.82, 0.34, 1)
                    line:SetThickness(2)
                end
                line:SetStartPoint("CENTER", mapMarker, corner[1], corner[2])
                line:SetEndPoint("CENTER", mapMarker, nextCorner[1], nextCorner[2])
            end
        end
        updateMapMarker = function()
            local visible = markedTarget and markedTarget.mapID == map:GetMapID()
            if visible then
                local width, height = canvas:GetSize()
                mapMarker:ClearAllPoints()
                mapMarker:SetPoint("CENTER", canvas, "TOPLEFT", width * markedTarget.x, -height * markedTarget.y)
            end
            mapMarker:SetShown(visible == true)
        end
        hooksecurefunc(map, "OnMapChanged", updateMapMarker)
        canvas:HookScript("OnSizeChanged", updateMapMarker)
    end
    updateMapMarker()
end

local function FormatQuestTitle(quest)
    local title = quest.title
    if not title or title == "" then
        title = L.QuestNumber:format(quest.id)
    end
    local level = addon.QuestPrioritizer.GetLevel(quest)
    return level and ("[%d] %s"):format(level, title) or title
end

local function FormatDistance(measurement)
    return measurement and ("~%.0f yd"):format(measurement.yards) or "—"
end

local function MakeButton(parent)
    local button = CreateFrame("Button", nil, parent)
    local label = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("CENTER")
    button:SetFontString(label)
    button:SetNormalFontObject(GameFontHighlightSmall)
    button:SetDisabledFontObject(GameFontDisableSmall)
    local background = button:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(0.18, 0.15, 0.11, 1)
    local highlight = button:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(0.74, 0.55, 0.28, 0.19)
    return button
end

local function AddRowBackground(row, index)
    local background = row:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(0.66, 0.47, 0.23, index % 2 == 1 and 0.11 or 0.045)
end

local function CreateDirectionArrow(parent, size)
    local arrow = CreateFrame("Frame", nil, parent)
    arrow:SetSize(size, size)
    arrow:Hide()
    local lines = {}
    for index = 1, 3 do
        local line = arrow:CreateLine(nil, "ARTWORK")
        line:SetColorTexture(1, 0.82, 0.34, 1)
        line:SetThickness(2)
        lines[index] = line
    end
    local lastRight, lastForward
    function arrow:SetDirection(right, forward)
        if right == lastRight and forward == lastForward then return end
        lastRight, lastForward = right, forward
        if not right then
            self:Hide()
            return
        end
        local scale = size / 20
        local tipX, tipY = 8 * scale * right, 8 * scale * forward
        lines[1]:SetStartPoint("CENTER", self, -7 * scale * right, -7 * scale * forward)
        lines[2]:SetStartPoint("CENTER", self, scale * (2 * right - 4 * forward), scale * (2 * forward + 4 * right))
        lines[3]:SetStartPoint("CENTER", self, scale * (2 * right + 4 * forward), scale * (2 * forward - 4 * right))
        for _, line in ipairs(lines) do line:SetEndPoint("CENTER", self, tipX, tipY) end
        self:Show()
    end
    return arrow
end

function addon.CreateMinimapButton(tracker, settings, toggleTracker, openSettings)
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
        GameTooltip:AddLine(tracker:IsShown() and L.HideTracker or L.ShowTracker)
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
            toggleTracker()
            ShowTooltip(self)
        end
    end)
    return button
end

local function CreateSkipCheckbox(parent, skipQuest)
    local checkbox = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    checkbox:SetSize(22, 22)
    checkbox:SetScript("OnClick", function(self)
        self:SetChecked(false)
        skipQuest(self.quest)
    end)
    checkbox:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L.SkipQuest)
        GameTooltip:Show()
    end)
    checkbox:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return checkbox
end

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

function addon.CreateQuestTracker(settings, actions, version)
    local frame = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    frame:SetSize(352, 170)
    frame:SetPoint("CENTER", UIParent, "CENTER", settings.x, settings.y)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    frame:SetBackdropColor(0.07, 0.06, 0.045, 1)
    frame:SetBackdropBorderColor(0.64, 0.46, 0.22, 1)
    frame:SetAlpha(settings.opacityPercent / 100)

    local header = CreateFrame("Frame", nil, frame)
    header:SetPoint("TOPLEFT", 8, -5)
    header:SetPoint("TOPRIGHT", -102, -5)
    header:SetHeight(24)
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function()
        frame:StartMoving()
    end)
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

    if version then
        local versionLabel = header:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        versionLabel:SetPoint("LEFT", heading, "RIGHT", 8, 0)
        versionLabel:SetText("v" .. version)
    end

    local settingsButton = MakeButton(frame)
    settingsButton:SetSize(88, 22)
    settingsButton:SetPoint("TOPRIGHT", -31, -5)
    settingsButton:SetText(L.Settings)
    settingsButton:SetScript("OnClick", actions.openSettings)

    local close = MakeButton(frame)
    close:SetSize(20, 20)
    close:SetPoint("TOPRIGHT", -8, -6)
    close:SetText("×")
    close:SetScript("OnClick", function() frame:Hide() end)
    frame:SetScript("OnShow", function() settings.hidden = false end)
    frame:SetScript("OnHide", function() settings.hidden = not frame:IsShown() end)

    local activeBackdrop = frame:CreateTexture(nil, "BACKGROUND")
    activeBackdrop:SetPoint("TOPLEFT", 8, -29)
    activeBackdrop:SetColorTexture(0.26, 0.19, 0.10, 0.55)
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 40, -35)
    title:SetPoint("TOPRIGHT", -104, -35)
    title:SetJustifyH("LEFT")
    title:SetMaxLines(2)

    local objective = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    objective:SetPoint("TOPLEFT", title, "BOTTOMLEFT", -26, -5)
    objective:SetPoint("TOPRIGHT", title, "BOTTOMRIGHT", 90, -5)
    objective:SetJustifyH("LEFT")
    objective:SetMaxLines(3)

    local activeDistance = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    activeDistance:SetPoint("TOPRIGHT", -14, -36)

    local history = MakeButton(frame)
    history:SetSize(116, 22)
    history:SetPoint("BOTTOMLEFT", 14, 12)
    history:SetText(L.SkippedCount:format(0))
    history:SetScript("OnClick", function(self) ShowSkippedQuests(self, actions.restore, actions.resetSkips) end)
    history:SetEnabled(false)

    local auto = MakeButton(frame)
    auto:SetSize(90, 22)
    auto:SetPoint("BOTTOMRIGHT", -14, 12)
    auto:SetText(L.AutoSelect)
    auto:SetScript("OnClick", function() actions.select(nil) end)
    auto:SetEnabled(false)
    auto:Hide()

    local activeCheckbox = CreateSkipCheckbox(frame, actions.skip)
    activeCheckbox:SetPoint("TOPLEFT", 12, -31)
    activeCheckbox:Hide()

    local alternativesLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    alternativesLabel:SetText(L.Alternatives)
    alternativesLabel:Hide()

    local rows = {}
    for index = 1, 2 do
        local row = CreateFrame("Button", nil, frame)
        row:SetHeight(22)
        AddRowBackground(row, index)

        local highlight = row:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints()
        highlight:SetColorTexture(1, 0.8, 0.25, 0.16)

        row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.label:SetPoint("LEFT", 26, 0)
        row.label:SetPoint("RIGHT", -78, 0)
        row.label:SetJustifyH("LEFT")
        row.label:SetMaxLines(1)
        row:SetScript("OnClick", function(self)
            actions.select(self.questID)
            actions.openQuestMap(self.questID)
        end)
        row.checkbox = CreateSkipCheckbox(row, actions.skip)
        row.checkbox:SetPoint("LEFT", -2, 0)
        row.distance = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.distance:SetPoint("RIGHT", 0, 0)
        row.zone = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.zone:SetPoint("TOPRIGHT", 0, -22)
        row.zone:SetJustifyH("RIGHT")
        row.zone:SetMaxLines(1)
        row.zone:Hide()
        row:Hide()
        rows[index] = row
    end

    local arrow = CreateDirectionArrow(frame, 20)
    arrow:SetPoint("TOPRIGHT", -76, -31)

    for _, row in ipairs(rows) do
        row.arrow = CreateDirectionArrow(row, 15)
        row.arrow:SetPoint("RIGHT", -63, 0)
    end
    local offersLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    offersLabel:SetText(L.NearbyQuests)
    offersLabel:Hide()
    local routeNote = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    routeNote:SetJustifyH("LEFT")
    routeNote:SetMaxLines(1)
    routeNote:Hide()
    local offerRows = {}
    for index = 1, 3 do
        local row = CreateFrame("Frame", nil, frame)
        row:SetHeight(22)
        AddRowBackground(row, index)
        row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.label:SetPoint("LEFT", 5, 0)
        row.label:SetPoint("RIGHT", -82, 0)
        row.label:SetJustifyH("LEFT")
        row.label:SetMaxLines(1)
        row.distance = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.distance:SetPoint("RIGHT")
        row.arrow = CreateDirectionArrow(row, 15)
        row.arrow:SetPoint("RIGHT", -63, 0)
        row:Hide()
        offerRows[index] = row
    end
    local routeToggle = CreateFrame("Button", nil, frame)
    routeToggle:SetSize(96, 18)
    routeToggle:Hide()
    local disclosure = routeToggle:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    disclosure:SetPoint("RIGHT")
    local routeDetails = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    routeDetails:SetJustifyH("LEFT")
    routeDetails:SetMaxLines(14)
    routeDetails:Hide()
    local routeExpanded, routeQuestID
    local otherCount, offerCount = 0, 0
    local questMap = CreateFrame("Button", nil, frame)
    questMap:SetAllPoints(title)
    questMap:SetScript("OnClick", function(self) actions.openQuestMap(self.questID) end)
    questMap:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L.OpenQuestMap)
        GameTooltip:Show()
    end)
    questMap:SetScript("OnLeave", function() GameTooltip:Hide() end)
    questMap:Hide()
    local activeZone = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    activeZone:SetPoint("TOPLEFT", title, "BOTTOMLEFT", -26, -5)
    activeZone:SetPoint("TOPRIGHT", title, "BOTTOMRIGHT", 90, -5)
    activeZone:SetJustifyH("LEFT")
    activeZone:SetMaxLines(1)
    activeZone:Hide()
    local routeMap, nearbyStopsButton

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
        row.routeDetails:SetShown(row.routeExpanded == true)
        row.routeMap:SetShown(row.routeExpanded == true)
        row.routeLabel:SetText(row.routeExpanded and L.HideRoute or L.RouteDetails)
        local detailHeight = row.routeExpanded and math.max(16, row.routeDetails:GetStringHeight()) + 8 or 0
        local height = (row.zone:IsShown() or row.routeButton:IsShown()) and (34 + detailHeight) or 22
        local offset = (height - 22) / 2
        row:SetHeight(height)
        row.label:ClearAllPoints()
        row.label:SetPoint("LEFT", 26, offset)
        row.label:SetPoint("RIGHT", -78, offset)
        row.distance:ClearAllPoints()
        row.distance:SetPoint("RIGHT", 0, offset)
        row.arrow:ClearAllPoints()
        row.arrow:SetPoint("RIGHT", -63, offset)
        row.zone:SetPoint("TOPLEFT", row.routeButton:IsShown() and 130 or 26, -22)
    end

    local function UpdateHeight()
        local detailsBottom = 40 + title:GetStringHeight() + objective:GetStringHeight()
        if activeZone:IsShown() then detailsBottom = detailsBottom + activeZone:GetStringHeight() + 5 end
        local previewHeight = routeDetails:IsShown() and math.max(16, routeDetails:GetStringHeight()) + 8 or 0
        local activeBottom = math.max(68, detailsBottom +
            ((routeToggle:IsShown() or routeNote:IsShown()) and 23 or 8) + previewHeight)
        if nearbyStopsButton:IsShown() then
            nearbyStopsButton:ClearAllPoints()
            nearbyStopsButton:SetPoint("TOPLEFT", 14, -activeBottom)
            activeBottom = activeBottom + 24
        end
        activeBackdrop:ClearAllPoints()
        activeBackdrop:SetPoint("TOPLEFT", 8, -29)
        activeBackdrop:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", -8, -activeBottom)
        routeNote:ClearAllPoints()
        routeNote:SetPoint("TOPLEFT", 14, -detailsBottom - 6)
        routeNote:SetPoint("TOPRIGHT", routeToggle:IsShown() and -112 or -14, -detailsBottom - 6)
        routeToggle:ClearAllPoints()
        disclosure:ClearAllPoints()
        if routeNote:IsShown() then
            routeToggle:SetPoint("TOPRIGHT", -14, -detailsBottom - 3)
            disclosure:SetPoint("RIGHT")
        else
            routeToggle:SetPoint("TOPLEFT", 14, -detailsBottom - 3)
            disclosure:SetPoint("LEFT")
        end
        routeDetails:ClearAllPoints()
        routeDetails:SetPoint("TOPLEFT", 14, -detailsBottom - 24)
        routeDetails:SetPoint("TOPRIGHT", -64, -detailsBottom - 24)

        alternativesLabel:ClearAllPoints()
        alternativesLabel:SetPoint("TOPLEFT", 14, -activeBottom - 12)
        local y, rowBlockHeight = -activeBottom - 30, 0
        for _, row in ipairs(rows) do
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 14, y)
            row:SetPoint("TOPRIGHT", -14, y)
            if row:IsShown() then
                local height = row:GetHeight() + 1
                y, rowBlockHeight = y - height, rowBlockHeight + height
            end
        end
        local offersHeight = offerCount > 0 and 21 + 22 * offerCount or 0
        local sectionGap = (otherCount > 0 and offerCount > 0) and 12 or 0
        local footerGap = (otherCount > 0 or offerCount > 0) and 10 or 0
        frame:SetHeight(activeBottom + (otherCount > 0 and 61 + rowBlockHeight or 45)
            + offersHeight + sectionGap + footerGap)
        offersLabel:ClearAllPoints()
        offersLabel:SetPoint("BOTTOMLEFT", 14, 43 + 22 * offerCount + footerGap)
        for index, row in ipairs(offerRows) do
            local y = 36 + 22 * (offerCount - index) + footerGap
            row:ClearAllPoints()
            row:SetPoint("BOTTOMLEFT", 14, y)
            row:SetPoint("BOTTOMRIGHT", -14, y)
        end
    end

    local function ShowRouteDetails(show)
        routeDetails:SetShown(show)
        routeMap:SetShown(show)
        disclosure:SetText(show and L.HideRoute or L.RouteDetails)
    end

    routeToggle:SetScript("OnClick", function()
        routeExpanded = not routeExpanded
        ShowRouteDetails(routeExpanded)
        UpdateHeight()
    end)

    for _, row in ipairs(rows) do
        row.routeButton = CreateFrame("Button", nil, row)
        row.routeButton:SetSize(96, 15)
        row.routeButton:SetPoint("TOPLEFT", 26, -20)
        row.routeLabel = row.routeButton:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.routeLabel:SetPoint("LEFT")
        row.routeDetails = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.routeDetails:SetPoint("TOPLEFT", 26, -37)
        row.routeDetails:SetPoint("TOPRIGHT", -54, -37)
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
    routeMap = CreateRouteMap(frame, routeDetails, function() return routeQuestID end)
    frame.routeMap = routeMap
    for _, row in ipairs(rows) do
        row.routeMap = CreateRouteMap(row, row.routeDetails, function() return row.questID end)
    end
    nearbyStopsButton = MakeButton(frame)
    nearbyStopsButton:SetSize(196, 18)
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

    title:SetText(L.ReadingQuestLog)
    UpdateHeight()
    frame:SetShown(not settings.hidden)

    function frame:RenderNearbyOffers(offers)
        local count = 0
        for index, row in ipairs(offerRows) do
            local offer = offers and offers[index]
            row.measurement = offer
            if offer then
                count = count + 1
                row.label:SetText(FormatQuestTitle(offer))
                row.distance:SetText(FormatDistance(offer))
            end
            row:SetShown(offer ~= nil)
        end
        offersLabel:SetShown(count > 0)
        if count == offerCount then return end
        offerCount = count
        UpdateHeight()
    end

    function frame:Render(quest, objectiveText, skippedQuests, alternatives, manualSelection, routeText, routePreview, zones, routes, nearbyStops)
        activeCheckbox.quest = quest
        activeCheckbox:SetShown(quest ~= nil)
        questMap.questID = quest and quest.id
        questMap:SetShown(quest ~= nil)
        activeDistance:SetText(quest and FormatDistance() or "")
        local zone = zones and zones[1]
        activeZone:SetText(zone or "")
        activeZone:SetShown(zone ~= nil)
        local aboveObjective = zone and activeZone or title
        objective:ClearAllPoints()
        objective:SetPoint("TOPLEFT", aboveObjective, "BOTTOMLEFT", zone and 0 or -26, -5)
        objective:SetPoint("TOPRIGHT", aboveObjective, "BOTTOMRIGHT", zone and 0 or 90, -5)
        local skippedCount = 0
        for _ in pairs(skippedQuests) do skippedCount = skippedCount + 1 end
        history.skippedQuests = skippedQuests
        history:SetText(L.SkippedCount:format(skippedCount))
        history:SetEnabled(skippedCount > 0)
        auto:SetEnabled(manualSelection == true)
        auto:SetShown(manualSelection == true)
        local count = alternatives and #alternatives or 0
        otherCount = count
        routeNote:SetText(routeText or "")
        routeNote:SetShown(routeText ~= nil)
        routeToggle:SetShown(routePreview ~= nil)
        local questID = quest and quest.id
        if routeQuestID ~= questID or not routePreview then routeExpanded = false end
        routeQuestID = questID
        routeDetails:SetText(routePreview or "")
        ShowRouteDetails(routeExpanded == true)
        nearbyStopsButton.stops = nearbyStops
        nearbyStopsButton:SetShown(nearbyStops ~= nil)
        if nearbyStops then
            local count = #nearbyStops
            nearbyStopsButton:SetText(count == 1 and L.NearbyStopOne or L.NearbyStopMany:format(count))
        end
        alternativesLabel:SetShown(count > 0)
        for index, row in ipairs(rows) do
            local alternative = alternatives and alternatives[index]
            local id = alternative and alternative.id
            local details = routes and routes[index]
            if row.questID ~= id or not details then row.routeExpanded = false end
            row.questID = id
            row.measurement = nil
            row.checkbox.quest = alternative
            if alternative then
                local alternativeZone = zones and zones[index + 1]
                row.zone:SetText(alternativeZone or "")
                row.zone:SetShown(alternativeZone ~= nil)
                row.routeButton:SetShown(details ~= nil)
                row.routeDetails:SetText(details or "")
                UpdateAlternativeLayout(row)
                row.label:SetText(FormatQuestTitle(alternative))
                row.distance:SetText(FormatDistance())
            end
            row:SetShown(alternative ~= nil)
        end
        if not quest then
            title:SetText(objectiveText)
            objective:SetText("")
            UpdateHeight()
            return
        end

        title:SetText(FormatQuestTitle(quest))
        objective:SetText(objectiveText)
        UpdateHeight()
    end

    function frame:RenderDistances(measurements)
        if activeCheckbox.quest then
            activeDistance:SetText(FormatDistance(measurements[activeCheckbox.quest.id]))
        end
        for _, row in ipairs(rows) do
            if row.questID then
                row.measurement = measurements[row.questID]
                row.distance:SetText(FormatDistance(row.measurement))
            end
        end
    end

    function frame:RenderDirection(right, forward)
        arrow:SetDirection(right, forward)
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

    return frame
end
