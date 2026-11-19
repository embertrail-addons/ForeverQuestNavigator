local _, addon = ...
-- Own canvas children survive native pin-pool refreshes by other map providers.
-- Parenting and anchoring to the canvas preserves the map's pan/zoom transform.
local Canvas = {}
addon.CanvasMarkers = Canvas
function Canvas.New(map, api, create)
    if not (map and map.GetCanvas and map.GetMapID and map.IsShown) then return end
    local canvas = map:GetCanvas()
    if not canvas or not canvas.GetWidth or not canvas.GetHeight then return end
    local self = {map = map, api = api, pins = {}, revision = 0, count = 0}
    self.watcher = create("Frame", nil, map)
    self.watcher:Hide()
    local function Remove()
        local callback = self.remove
        if GameTooltip then GameTooltip:Hide() end
        self:Set(nil)
        if callback then callback() end
    end
    local function NewPin()
        local pin = create("Button", nil, canvas, "BackdropTemplate")
        pin:SetSize(34, 34) pin:RegisterForClicks("RightButtonUp")
        pin:SetBackdrop({bgFile = "Interface/Buttons/WHITE8X8", edgeFile = "Interface/Buttons/WHITE8X8", edgeSize = 2})
        pin:SetBackdropColor(.08, .06, .02, 1)
        pin:SetBackdropBorderColor(1, .82, .34, 1)
        pin:SetAlpha(1)
        if pin.SetIgnoreParentAlpha then pin:SetIgnoreParentAlpha(true) end
        if pin.SetPassThroughButtons then pin:SetPassThroughButtons("LeftButton") end
        pin.icon = pin:CreateTexture(nil, "ARTWORK") pin.icon:SetAllPoints()
        pin.icon:SetAtlas("Waypoint-MapPin-Untracked")
        pin.number = pin:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall") pin.number:SetPoint("CENTER")
        pin:SetScript("OnClick", function(_, button) if button == "RightButton" then Remove() end end)
        pin:SetScript("OnEnter", function(owner)
            if not GameTooltip then return end
            GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
            GameTooltip:SetText(addon.L.MapMarker)
            for _, stop in ipairs(owner.stops) do
                GameTooltip:AddLine((stop.ordinal and stop.ordinal .. ". " or "")
                    .. (stop.quest and addon.UI.FormatQuestTitle(stop.quest) or addon.L.RouteCurrent), 1, 1, 1, true)
            end
            GameTooltip:AddLine(addon.L.RemoveMarker) GameTooltip:Show()
        end)
        pin:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        return pin
    end
    function self:Refresh()
        local started = addon.Performance:Begin()
        for _, pin in ipairs(self.pins) do pin:Hide() end
        self.count = 0
        if not self.target or not self.map:IsShown() then return end
        local mapID, groups = self.map:GetMapID(), {}
        local function Add(point, quest, ordinal)
            local projected = addon.QuestLocation.ProjectMarker(self.api, point, mapID)
            if not projected then return end
            for _, group in ipairs(groups) do
                if math.abs(group.point.x - projected.x) < .000001 and math.abs(group.point.y - projected.y) < .000001 then
                    group.stops[#group.stops + 1] = {quest = quest, ordinal = ordinal} return
                end
            end
            groups[#groups + 1] = {point = projected, stops = {{quest = quest, ordinal = ordinal}}}
        end
        local hasTarget
        for index, stop in ipairs(self.route or {}) do
            if stop.target then
                Add(stop.target, stop.quest, index)
                if stop.target.mapID == self.target.mapID and stop.target.x == self.target.x and stop.target.y == self.target.y then hasTarget = true end
            end
        end
        if not hasTarget then Add(self.target) end
        local width, height = canvas:GetWidth(), canvas:GetHeight()
        local canvasScale = canvas.GetEffectiveScale and canvas:GetEffectiveScale() or 1
        local uiScale = UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or 1
        local scale = uiScale / canvasScale
        if not (width > 0 and height > 0 and scale > 0 and scale < math.huge) then return end
        local strataOrder = {BACKGROUND = 0, LOW = 1, MEDIUM = 2, HIGH = 3, DIALOG = 4, FULLSCREEN = 5, FULLSCREEN_DIALOG = 6, TOOLTIP = 7}
        local strata, level = "HIGH", 0
        for _, surface in ipairs({map, canvas, map.ScrollContainer}) do
            if surface then
                local value = surface.GetFrameStrata and surface:GetFrameStrata()
                if value and (strataOrder[value] or 0) > strataOrder[strata] then strata = value end
                level = math.max(level, surface.GetFrameLevel and surface:GetFrameLevel() or 0)
            end
        end
        for index, group in ipairs(groups) do
            local pin = self.pins[index]
            if not pin then pin = NewPin() self.pins[index] = pin end
            pin.stops = group.stops
            local labels, active = {}, false
            for _, stop in ipairs(group.stops) do
                if stop.ordinal then labels[#labels + 1] = tostring(stop.ordinal) end
                if not stop.ordinal or stop.ordinal == 1 then active = true end
            end
            pin:SetSize(active and 36 or 30, active and 36 or 30)
            pin.icon:SetVertexColor(active and 1 or .55, active and .82 or .8, active and .34 or 1)
            pin.number:SetText(table.concat(labels, "/")) pin.number:SetShown(#labels > 0)
            pin:SetScale(scale)
            pin:SetFrameStrata(strata)
            pin:SetFrameLevel(level + 100 + (active and 1 or 0))
            pin:ClearAllPoints()
            pin:SetPoint("CENTER", canvas, "TOPLEFT", width * group.point.x / scale, -height * group.point.y / scale)
            pin:Show() self.count = self.count + 1
        end
        addon.Performance:Finish("map", started)
    end
    function self:Set(target, remove, route)
        self.target, self.remove, self.route = target, remove, target and route or nil
        self.revision = self.revision + 1
        self:Refresh() self.watcher:SetShown(target ~= nil)
    end
    function self:Describe()
        local visible = 0
        for _, pin in ipairs(self.pins) do if pin.IsVisible and pin:IsVisible() then visible = visible + 1 end end
        local first = self.pins[1]
        local x, y
        if first and first.GetCenter then x, y = first:GetCenter() end
        return ("renderer=canvas-v2 map=%s targetMap=%s visible=%d canvas=%.1fx%.1f center=%s,%s alpha=%s strata=%s level=%s scale=%s"):format(
            tostring(map:GetMapID()), tostring(self.target and self.target.mapID), visible, canvas:GetWidth(), canvas:GetHeight(),
            tostring(x), tostring(y), tostring(first and first.GetEffectiveAlpha and first:GetEffectiveAlpha()),
            tostring(first and first.GetFrameStrata and first:GetFrameStrata()),
            tostring(first and first.GetFrameLevel and first:GetFrameLevel()),
            tostring(first and first.GetScale and first:GetScale()))
    end
    self.watcher:SetScript("OnUpdate", function(_, elapsed)
        self.elapsed = (self.elapsed or 0) + elapsed
        if self.elapsed < .1 then return end
        self.elapsed = 0
        local signature = tostring(map:GetMapID()) .. ":" .. canvas:GetWidth() .. ":" .. canvas:GetHeight()
            .. ":" .. tostring(canvas.GetEffectiveScale and canvas:GetEffectiveScale() or 1) .. ":" .. self.revision
        if signature ~= self.signature then self.signature = signature self:Refresh() end
    end)
    self.watcher:SetScript("OnShow", function() self.signature = nil self:Refresh() end)
    return self
end
