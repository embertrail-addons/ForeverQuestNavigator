local _, addon = ...
-- Own canvas children survive native pin-pool refreshes by other map providers.
-- Parenting and anchoring to the canvas preserves the map's pan/zoom transform.
local Canvas = {showLine = true}
addon.CanvasMarkers = Canvas
function Canvas.New(map, api, create)
    if not (map and map.GetCanvas and map.GetMapID and map.IsShown) then return end
    local canvas = map:GetCanvas()
    if not canvas or not canvas.GetWidth or not canvas.GetHeight then return end
    local self = {map = map, api = api, pins = {}, lines = {}, revision = 0, count = 0, lineCount = 0}
    self.watcher = create("Frame", nil, map)
    self.watcher:Hide()
    local function Remove()
        local callback = self.remove
        if GameTooltip then GameTooltip:Hide() end
        self:Set(nil)
        if callback then callback() end
    end
    local function NewPin()
        local pin = create("Button", nil, canvas)
        pin:SetSize(24, 24) pin:RegisterForClicks("RightButtonUp")
        pin:SetAlpha(1)
        if pin.SetIgnoreParentAlpha then pin:SetIgnoreParentAlpha(true) end
        if pin.SetPassThroughButtons then pin:SetPassThroughButtons("LeftButton") end
        pin.icon = pin:CreateTexture(nil, "ARTWORK") pin.icon:SetAllPoints()
        pin.icon:SetAtlas("Waypoint-MapPin-Untracked")
        pin.number = pin:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall") pin.number:SetPoint("CENTER")
        pin.number:SetTextColor(1, 1, 1, 1)
        pin.number:SetShadowColor(0, 0, 0, 1) pin.number:SetShadowOffset(1, -1)
        pin:SetScript("OnClick", function(_, button) if button == "RightButton" then Remove() end end)
        pin:SetScript("OnEnter", function(owner)
            local ids = {}
            for _, stop in ipairs(owner.stops or {}) do if stop.quest then ids[stop.quest.id] = true end end
            addon.QuestHover.Set(owner, ids)
            if not GameTooltip then return end
            GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
            GameTooltip:SetText(addon.L.MapMarker)
            for _, stop in ipairs(owner.stops) do
                GameTooltip:AddLine((stop.ordinal and stop.ordinal .. ". " or "")
                    .. (stop.quest and addon.UI.FormatQuestTitle(stop.quest) or addon.L.RouteCurrent), 1, 1, 1, true)
            end
            GameTooltip:AddLine(addon.L.RemoveMarker) GameTooltip:Show()
        end)
        pin:SetScript("OnLeave", function(owner)
            if not self.refreshing then addon.QuestHover.Clear(owner) end
            if GameTooltip then GameTooltip:Hide() end
        end)
        pin:SetScript("OnHide", function(owner) if not self.refreshing then addon.QuestHover.Clear(owner) end end)
        return pin
    end
    -- Connects consecutive numbered route stops on the canvas. Line coordinates are
    -- canvas units; thickness is corrected so it stays constant on screen.
    function self:DrawRoute(mapID, width, height, scale)
        self.lineCount = 0
        if not (Canvas.showLine and canvas.CreateLine and self.route) then return end
        local points = {}
        for _, stop in ipairs(self.route) do
            if stop.target and not stop.single then
                local projected = addon.QuestLocation.ProjectMarker(self.api, stop.target, mapID)
                local last = points[#points]
                if projected and not (last and math.abs(last.x - projected.x) < .000001 and math.abs(last.y - projected.y) < .000001) then
                    points[#points + 1] = projected
                end
            end
        end
        for index = 2, #points do
            local from, to = points[index - 1], points[index]
            local line = self.lines[index - 1]
            if not line then
                line = canvas:CreateLine(nil, "OVERLAY", nil, 7)
                self.lines[index - 1] = line
            end
            -- The next leg is thicker as well as gold, so it stands out without colour vision.
            if line.SetThickness then line:SetThickness((index == 2 and 6 or 3) * scale) end
            if line.SetColorTexture then
                if index == 2 then line:SetColorTexture(1, .82, .34, .9) else line:SetColorTexture(.55, .8, 1, .75) end
            end
            line:SetStartPoint("TOPLEFT", canvas, width * from.x, -height * from.y)
            line:SetEndPoint("TOPLEFT", canvas, width * to.x, -height * to.y)
            line:Show()
            self.lineCount = self.lineCount + 1
        end
    end
    function self:Refresh()
        local started = addon.Performance:Begin()
        self.refreshing = true
        for _, pin in ipairs(self.pins) do pin:Hide() end
        for _, line in ipairs(self.lines) do line:Hide() end
        self.lineCount = 0
        self.refreshing = false
        self.count = 0
        if not self.target or not self.map:IsShown() then
            for _, pin in ipairs(self.pins) do addon.QuestHover.Clear(pin) end
            return
        end
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
                Add(stop.target, stop.quest, not stop.single and index or nil)
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
        self:DrawRoute(mapID, width, height, scale)
        for index, group in ipairs(groups) do
            local pin = self.pins[index]
            if not pin then pin = NewPin() self.pins[index] = pin end
            pin.stops = group.stops
            local labels, active = {}, false
            for _, stop in ipairs(group.stops) do
                if stop.ordinal then labels[#labels + 1] = tostring(stop.ordinal) end
                if not stop.ordinal or stop.ordinal == 1 then active = true end
            end
            local size = (active and 24 or 20) + (#group.stops > 1 and 6 or 0)
            pin:SetSize(size, size)
            pin.icon:SetVertexColor(active and 1 or .55, active and .82 or .8, active and .34 or 1)
            pin.active, pin.baseSize = active, size
            pin.number:SetText(table.concat(labels, "/")) pin.number:SetShown(#labels > 0)
            pin:SetScale(scale)
            pin:SetFrameStrata(strata)
            pin:SetFrameLevel(level + 100 + (active and 1 or 0))
            pin:ClearAllPoints()
            pin:SetPoint("CENTER", canvas, "TOPLEFT", width * group.point.x / scale, -height * group.point.y / scale)
            pin:Show() self.count = self.count + 1
        end
        addon.Performance:Finish("map", started)
        for index, pin in ipairs(self.pins) do
            if addon.QuestHover.owner == pin then
                if index > self.count then addon.QuestHover.Clear(pin)
                else
                    local ids = {}
                    for _, stop in ipairs(pin.stops or {}) do if stop.quest then ids[stop.quest.id] = true end end
                    addon.QuestHover.Set(pin, ids)
                end
            end
        end
        self:Highlight(addon.QuestHover.ids)
    end
    function self:Highlight(ids)
        for _, pin in ipairs(self.pins) do
            local highlighted = false
            for _, stop in ipairs(pin.stops or {}) do if stop.quest and ids[stop.quest.id] then highlighted = true end end
            local size = (pin.baseSize or 20) + (highlighted and 5 or 0)
            pin:SetSize(size, size)
            if highlighted then pin.icon:SetVertexColor(.3, 1, 1)
            else pin.icon:SetVertexColor(pin.active and 1 or .55, pin.active and .82 or .8, pin.active and .34 or 1) end
        end
    end
    addon.QuestHover.Subscribe(function(ids) self:Highlight(ids) end)
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
        return ("renderer=canvas-v3 map=%s targetMap=%s visible=%d canvas=%.1fx%.1f center=%s,%s alpha=%s strata=%s level=%s scale=%s"):format(
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
