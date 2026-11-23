local _, addon = ...
local L = addon.L

-- One scrollable surface for all navigator details. Opening it never changes
-- the tracker geometry. Reuse the tool hub when neither side has enough room.
function addon.CreateNavigatorDetails(owner, settings)
    local panel = addon.UI.CreateUtilityPanel(340, 380, L.NavigatorDetails)
    panel.hubPage, panel.hubStandalone = "details", true
    panel.scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    panel.scroll:SetPoint("TOPLEFT", 14, -44)
    panel.scroll:SetPoint("BOTTOMRIGHT", -30, 48)
    panel.body = CreateFrame("Frame", nil, panel.scroll)
    panel.body:SetSize(292, 1)
    panel.scroll:SetScrollChild(panel.body)
    panel.map = addon.UI.CreateUtilityButton(panel, L.Map, 100, function()
        if panel.openMap then panel.openMap() end
    end)
    panel.map:SetPoint("BOTTOMRIGHT", -14, 12)
    panel.skip = addon.UI.CreateUtilityButton(panel, L.SkipQuest, 176, function()
        local skip = panel.skipQuest
        panel:Hide()
        if skip then skip() end
    end)
    panel.skip:SetPoint("BOTTOMLEFT", 14, 12)
    panel.skip:Hide()
    panel.widgets = {}
    panel.rows = {}
    function panel:RefreshSelection()
        for _, entry in ipairs(self.rows) do
            local selected = self:IsShown() and self.key == entry.key()
            entry.mark:SetShown(selected == true)
            if entry.label then entry.label:SetText(selected and "x" or "i") end
        end
    end
    function panel:RegisterRow(row, key, label)
        local mark = row:CreateTexture(nil, "BACKGROUND")
        mark:SetAllPoints() addon.UI.Theme.Bind(mark, "highlight", .16) mark:Hide()
        self.rows[#self.rows + 1] = {key = key, mark = mark, label = label}
        row.detailSelection = mark
    end
    function panel:Layout()
        self.body:SetWidth(math.max(180, self:GetWidth() - 48))
        for _, label in pairs(self.sectionLabels or {}) do label:Hide() end
        local y = 0
        for _, widget in ipairs(self.widgets) do
            if widget:IsShown() then
                if widget.sectionTitle then
                    self.sectionLabels = self.sectionLabels or {}
                    local label = self.sectionLabels[widget]
                    if not label then
                        label = addon.UI.CreateLabel(self.body, "GameFontNormalSmall")
                        self.sectionLabels[widget] = label
                        label:SetJustifyH("LEFT")
                    end
                    label:SetText(widget.sectionTitle) label:Show() label:ClearAllPoints()
                    label:SetPoint("TOPLEFT", 0, -y) label:SetPoint("TOPRIGHT", 0, -y)
                    y = y + math.max(18, label:GetStringHeight()) + 5
                end
                widget:ClearAllPoints()
                widget:SetPoint("TOPLEFT", self.body, "TOPLEFT", 0, -y)
                widget:SetPoint("TOPRIGHT", self.body, "TOPRIGHT", 0, -y)
                if widget.Layout then widget:Layout() end
                local height = widget.GetStringHeight and widget:GetStringHeight() or widget:GetHeight()
                y = y + math.max(18, height) + 10
            end
        end
        self.body:SetHeight(math.max(1, y))
    end
    function panel:UpdateOpacity()
        addon.UI.Theme.Frame(self, settings.opacityPercent / 100)
    end
    function panel:Position()
        self.positioning = true
        local width = UIParent.GetWidth and UIParent:GetWidth()
        local scale = owner.GetEffectiveScale and owner:GetEffectiveScale() or 1
        local parentScale = UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or 1
        local ratio = scale / parentScale
        local left = owner.GetLeft and owner:GetLeft()
        local right = owner.GetRight and owner:GetRight()
        local placement = addon.TrackerPresentation.DetailPlacement(left and left * ratio,
            right and right * ratio, width, 340)
        local hub = addon.UI.ToolHub
        local demo = addon.DemoMode and addon.DemoMode.IsActive()
        self.placement = placement
        if placement == "tools" and hub.ready and not demo then
            self.hubStandalone = false
            self:SetWidth(550)
            addon.UI.ShowUtilityPanel(self, "details")
        else
            if hub.active == self then
                hub.switching = true hub.Hide() hub.active, hub.key = nil, nil hub.switching = nil
            end
            self.hubStandalone, self.embedded = true, false
            if self.heading then self.heading:Show() end
            -- A drawer follows its owner. Free dragging here would be undone by
            -- the next snapshot; embedded mode gets the hub's drag handlers.
            self:SetScript("OnDragStart", function() end)
            self:SetScript("OnDragStop", function() end)
            self:SetWidth(340)
            self:SetParent(UIParent)
            self:ClearAllPoints()
            if placement == "right" then self:SetPoint("TOPLEFT", owner, "TOPRIGHT", 10, 0)
            elseif placement == "left" then self:SetPoint("TOPRIGHT", owner, "TOPLEFT", -10, 0)
            else self:SetPoint("CENTER", UIParent, "CENTER", 0, 0) end
            self.closeButton:Show()
            self:Show()
        end
        self:UpdateOpacity()
        self:Layout()
        self.positioning = nil
    end
    function panel:SetContent(key, title, widgets, openMap, skipQuest)
        if self.key ~= key then self.scroll:SetVerticalScroll(0) end
        for _, widget in ipairs(self.widgets) do widget:Hide() end
        self.key, self.widgets, self.openMap, self.skipQuest = key, widgets, openMap, skipQuest
        self.heading:SetText(title or L.NavigatorDetails)
        self.heading:SetMaxLines(1)
        for _, widget in ipairs(widgets) do widget:SetParent(self.body) widget:Show() end
        self.map:SetShown(openMap ~= nil)
        self.skip:SetShown(skipQuest ~= nil)
        self:Position()
        self:RefreshSelection()
    end
    panel:HookScript("OnHide", function(self)
        if self.positioning then return end
        for _, widget in ipairs(self.widgets) do widget:Hide() end
        if self.onClose then self.onClose() end
        self:RefreshSelection()
    end)
    owner:HookScript("OnHide", function() panel:Hide() end)
    owner:HookScript("OnDragStop", function() if panel:IsShown() then panel:Position() end end)
    owner:HookScript("OnSizeChanged", function() if panel:IsShown() then panel:Position() end end)
    return panel
end
