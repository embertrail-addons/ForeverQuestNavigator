local _, addon = ...

local function FullTextIfTruncated(label)
    if label:IsTruncated() then return label:GetText() end
end

local function ShowTextTooltip(owner, heading, detail)
    if not (heading or detail) then return end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(heading or detail, 1, 1, 1, true)
    if heading and detail then GameTooltip:AddLine(detail, 1, 1, 1, true) end
    GameTooltip:Show()
end

local function HideTextTooltip(owner)
    if GameTooltip:IsOwned(owner) then GameTooltip:Hide() end
end

addon.UI = {
    FullTextIfTruncated = FullTextIfTruncated,
    ShowTextTooltip = ShowTextTooltip,
    HideTextTooltip = HideTextTooltip,
}

function addon.CreateDirectionArrow(parent, size)
    local arrow = CreateFrame("Frame", nil, parent)
    arrow:SetSize(size, size)
    arrow:Hide()
    local lines = {}
    for index = 1, 3 do
        local line = arrow:CreateLine(nil, "ARTWORK")
        addon.UI.Theme.Bind(line, "heading", 1)
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

function addon.CreateNavigationDisplay(settings)
    local navigation = CreateFrame("Frame", nil, UIParent)
    navigation:SetSize(260, 44)
    local function AnchorNavigation()
        navigation:ClearAllPoints()
        if settings.screenArrowX and settings.screenArrowY then
            navigation:SetPoint("CENTER", UIParent, "CENTER", settings.screenArrowX, settings.screenArrowY)
        else
            navigation:SetPoint("TOP", UIParent, "TOP", 0, -80)
        end
    end
    AnchorNavigation()
    navigation:SetClampedToScreen(true)
    navigation:SetMovable(true)
    navigation:EnableMouse(true)
    navigation:RegisterForDrag("LeftButton")
    local movingNavigation
    navigation:SetScript("OnDragStart", function(self)
        if settings.lockNavigationPosition then return end
        movingNavigation = true
        addon.UI.HideTextTooltip(self)
        self:StartMoving()
    end)
    local function StopNavigationDrag(self)
        if not movingNavigation then return end
        movingNavigation = false
        self:StopMovingOrSizing()
        local x, y = self:GetCenter()
        local centerX, centerY = UIParent:GetCenter()
        if x and y then settings.screenArrowX, settings.screenArrowY = x - centerX, y - centerY end
        AnchorNavigation()
    end
    navigation:SetScript("OnDragStop", StopNavigationDrag)
    navigation:SetScript("OnEnter", function(self)
        local titleText = addon.UI.FullTextIfTruncated(self.title)
        local goalText = FullTextIfTruncated(self.goal)
        if titleText or goalText then
            addon.UI.ShowTextTooltip(self, self.title:GetText(), self.goal:GetText() ~= "" and self.goal:GetText() or nil)
        end
    end)
    navigation:SetScript("OnLeave", HideTextTooltip)
    navigation:SetScript("OnHide", function(self)
        HideTextTooltip(self)
        StopNavigationDrag(self)
    end)
    local navigationBackground = navigation:CreateTexture(nil, "BACKGROUND")
    navigationBackground:SetAllPoints()
    navigation.arrow = addon.CreateDirectionArrow(navigation, 32)
    navigation.arrow:SetPoint("TOPLEFT", 8, -6)
    navigation.title = addon.UI.CreateLabel(navigation, "GameFontNormal")
    navigation.title:SetPoint("TOPLEFT", 47, -6)
    navigation.title:SetPoint("TOPRIGHT", -9, -6)
    navigation.title:SetJustifyH("LEFT")
    navigation.title:SetMaxLines(1)
    navigation.distance = addon.UI.CreateLabel(navigation, "GameFontHighlightSmall")
    navigation.distance:SetPoint("TOPRIGHT", navigation.title, "BOTTOMRIGHT", 0, -3)
    navigation.goal = addon.UI.CreateLabel(navigation, "GameFontHighlightSmall")
    navigation.goal:SetPoint("TOPLEFT", navigation.title, "BOTTOMLEFT", 0, -3)
    navigation.goal:SetPoint("TOPRIGHT", navigation.distance, "TOPLEFT", -7, 0)
    navigation.goal:SetMaxLines(1)
    navigation.goal:SetJustifyH("LEFT")
    navigation.status = addon.UI.CreateLabel(navigation, "GameFontHighlightSmall")
    navigation.status:SetPoint("TOPLEFT", 47, -43)
    navigation.status:SetPoint("TOPRIGHT", -9, -43)
    navigation.status:SetJustifyH("LEFT")
    navigation.status:SetMaxLines(2)
    navigation.status:Hide()
    navigation.notice = addon.UI.CreateLabel(navigation, "GameFontNormalSmall")
    navigation.notice:SetJustifyH("LEFT")
    navigation.notice:SetMaxLines(2)
    navigation.notice:Hide()
    function navigation:UpdateLayout()
        if self.noticeDeadline and GetTime and GetTime() >= self.noticeDeadline then
            self.noticeDeadline, self.noticeSeconds = nil, nil
            self.notice:Hide()
        end
        local bottom = 10 + self.title:GetStringHeight()
            + math.max(self.goal:GetStringHeight(), self.distance:GetStringHeight())
        self.status:ClearAllPoints()
        self.status:SetPoint("TOPLEFT", 47, -math.max(43, bottom + 4))
        self.status:SetPoint("TOPRIGHT", -9, -math.max(43, bottom + 4))
        local height = math.max(44, bottom + 8)
        if self.status:IsShown() then height = math.max(43, bottom + 4) + self.status:GetStringHeight() + 6 end
        if self.notice:IsShown() then
            self.notice:ClearAllPoints()
            self.notice:SetPoint("TOPLEFT", 47, -height)
            self.notice:SetPoint("TOPRIGHT", -9, -height)
            height = height + self.notice:GetStringHeight() + 7
        end
        self:SetHeight(height)
    end
    function navigation:Notify(message)
        if self.quiet then return end
        self.notice:SetText(message)
        self.notice:Show()
        self.noticeSeconds = 4
        self.noticeDeadline = GetTime and GetTime() + 4
        self:UpdateLayout()
    end
    navigation:SetScript("OnUpdate", function(self, elapsed)
        if not self.noticeSeconds then return end
        self.noticeSeconds = self.noticeSeconds - elapsed
        if self.noticeSeconds <= 0 then
            self.noticeSeconds = nil
            self.notice:Hide()
            self:UpdateLayout()
        end
    end)
    function navigation:SetStatus(status)
        self.status:SetText(status or "")
        self.status:SetShown(status ~= nil)
        self:UpdateLayout()
    end
    navigation:Hide()
    function navigation:UpdateOpacity()
        local r, g, b = addon.UI.Theme.Color("background")
        navigationBackground:SetColorTexture(r, g, b, settings.opacityPercent / 100)
    end

    function navigation:ResetPosition()
        StopNavigationDrag(self)
        settings.screenArrowX, settings.screenArrowY = nil, nil
        AnchorNavigation()
    end

    return navigation
end
