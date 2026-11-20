local _, addon = ...
local L = addon.L
addon.LayoutGeometry = {}
function addon.LayoutGeometry.Snap(x, y, width, height, screenWidth, screenHeight)
    local function Axis(value, size, screen)
        local edge = math.max(0, screen / 2 - size / 2 - 16)
        for _, anchor in ipairs({0, -edge, edge}) do if math.abs(value - anchor) <= 12 then return anchor end end
        return math.max(-edge, math.min(edge, value))
    end
    return Axis(x, width, screenWidth), Axis(y, height, screenHeight)
end
function addon.CreateLayoutEditor(tracker, navigation, settings)
    local editor = CreateFrame("Frame", "ForeverQuestNavigatorLayoutEditor", UIParent)
    if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "ForeverQuestNavigatorLayoutEditor") end
    editor:SetAllPoints() editor:SetFrameStrata("DIALOG") editor:Hide()
    local guides = {}
    for _, direction in ipairs({"vertical", "horizontal", "left", "right", "top", "bottom"}) do
        local line = editor:CreateTexture(nil, "BACKGROUND")
        addon.UI.Theme.Bind(line, "heading", .45)
        if direction == "vertical" then line:SetWidth(1) line:SetPoint("TOP", 0, 0) line:SetPoint("BOTTOM", 0, 0)
        elseif direction == "horizontal" then line:SetHeight(1) line:SetPoint("LEFT", 0, 0) line:SetPoint("RIGHT", 0, 0)
        elseif direction == "left" or direction == "right" then
            line:SetWidth(1) line:SetPoint("TOP" .. direction:upper(), direction == "left" and 16 or -16, -16)
            line:SetPoint("BOTTOM" .. direction:upper(), direction == "left" and 16 or -16, 16)
        else
            line:SetHeight(1) line:SetPoint(direction:upper() .. "LEFT", 16, direction == "top" and -16 or 16)
            line:SetPoint(direction:upper() .. "RIGHT", -16, direction == "top" and -16 or 16)
        end
        guides[#guides + 1] = line
    end
    local panel = CreateFrame("Frame", nil, editor, "BackdropTemplate")
    panel:SetSize(560, 144) panel:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 40)
    panel:SetBackdrop({bgFile = "Interface/Buttons/WHITE8X8", edgeFile = "Interface/Buttons/WHITE8X8", edgeSize = 1})
    addon.UI.Theme.WatchFrame(panel)
    local title = addon.UI.CreateLabel(panel, "GameFontNormal")
    title:SetPoint("TOPLEFT", 14, -12) title:SetText(L.ArrangeUI)
    local hint = addon.UI.CreateLabel(panel, "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", 14, -34) hint:SetPoint("TOPRIGHT", -14, -34)
    hint:SetMaxLines(2) hint:SetText(L.ArrangeHelp)
    editor.coordinates = addon.UI.CreateLabel(panel, "GameFontDisableSmall")
    editor.coordinates:SetPoint("TOPLEFT", 14, -72)
    local function RestoreVisibility(self)
        tracker.arranging, navigation.arranging = nil, nil
        tracker:SetShown(self.trackerShown) navigation:SetShown(self.navigationShown)
        if navigation.title:GetText() == L.ArrangeArrow then
            navigation.title:SetText("") navigation.goal:SetText("") navigation.arrow:SetDirection()
        end
    end
    function editor:Finish()
        if not self:IsShown() then return end
        settings.lockTrackerPosition, settings.lockNavigationPosition = true, true
        RestoreVisibility(self) self:Hide()
    end
    function editor:Cancel()
        if not self:IsShown() then return end
        for _, key in ipairs({"x", "y", "screenArrowX", "screenArrowY"}) do settings[key] = self.before[key] end
        tracker:Reanchor() navigation:Reanchor()
        RestoreVisibility(self) self:Hide()
    end
    editor:SetScript("OnHide", function(self)
        if not tracker.arranging then return end
        for _, key in ipairs({"x", "y", "screenArrowX", "screenArrowY"}) do settings[key] = self.before[key] end
        tracker:Reanchor() navigation:Reanchor() RestoreVisibility(self)
    end)
    editor.done = addon.UI.CreateUtilityButton(panel, L.ArrangeDone, 160, function() editor:Finish() end)
    editor.done:SetPoint("BOTTOMRIGHT", -14, 12)
    editor.cancel = addon.UI.CreateUtilityButton(panel, L.ArrangeCancel, 110, function() editor:Cancel() end)
    editor.cancel:SetPoint("BOTTOMLEFT", 14, 12)
    editor.center = addon.UI.CreateUtilityButton(panel, L.ArrangeCenterArrow, 220, function()
        settings.screenArrowX, settings.screenArrowY = 0, settings.screenArrowY or 150
        navigation:Reanchor()
    end)
    editor.center:SetPoint("BOTTOMLEFT", 132, 12)
    function editor:Start()
        if self:IsShown() then return end
        if addon.DemoMode and addon.DemoMode.IsActive() then return end
        self.before = {}
        for _, key in ipairs({"x", "y", "screenArrowX", "screenArrowY"}) do self.before[key] = settings[key] end
        self.trackerShown, self.navigationShown = tracker:IsShown(), navigation:IsShown()
        tracker.arranging, navigation.arranging = true, true
        if navigation.title:GetText() == "" then
            navigation.title:SetText(L.ArrangeArrow) navigation.goal:SetText(L.ArrangeDrag)
            navigation.arrow:SetDirection(0, 1) navigation:UpdateLayout()
        end
        local width = UIParent.GetWidth and UIParent:GetWidth()
        if width and width > 100 then panel:SetScale(math.min(1, (width - 32) / 560)) end
        tracker:Show() navigation:Show() self:Show()
    end
    editor:SetScript("OnUpdate", function(self)
        self.coordinates:SetText(L.ArrangeCoordinates:format(settings.x or 0, settings.y or 0,
            settings.screenArrowX or 0, settings.screenArrowY or 0))
    end)
    return editor
end
