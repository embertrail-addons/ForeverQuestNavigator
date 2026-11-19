local _, addon = ...
local L = addon.L
local PIN_TEMPLATE = "ForeverQuestNavigatorTargetPinTemplate"
local provider
local canvasMarkers
local pending, pendingWatch
local status = {backend = "not initialized", count = 0}
function addon.GetMapMarkerStatus()
    return {backend = status.backend, count = canvasMarkers and canvasMarkers.count or status.count,
        hasTarget = canvasMarkers and canvasMarkers.target ~= nil or provider and provider.target ~= nil or pending ~= nil,
        detail = canvasMarkers and canvasMarkers.Describe and canvasMarkers:Describe() or "renderer=provider"}
end
local function WaitForMap(target, removeMarker, route)
    pending = {target = target, removeMarker = removeMarker, route = route}
    if not pendingWatch then
        pendingWatch = CreateFrame("Frame")
        pendingWatch:SetScript("OnUpdate", function(self, elapsed)
            self.remaining = self.remaining - elapsed
            self.elapsed = self.elapsed + elapsed
            if self.elapsed < .1 then return end
            self.elapsed = 0
            local map = WorldMapFrame
            local ready = map and ((map.GetCanvas and map:GetCanvas())
                or (map.AddDataProvider and MapCanvasDataProviderMixin and MapCanvasPinMixin))
            if ready and pending then
                local request = pending pending = nil self:Hide()
                addon.ShowQuestMapMarker(request.target, request.removeMarker, request.route)
            elseif not pending or self.remaining <= 0 then self:Hide() end
        end)
    end
    pendingWatch.remaining, pendingWatch.elapsed = 5, 0
    pendingWatch:Show()
end
local Pin = {}

function addon.OpenQuestDetails(questID, mapID)
    local details = QuestMapFrame and QuestMapFrame.DetailsFrame
    local map = WorldMapFrame
    if not (QuestMapFrame_OpenToQuestDetails and details and map and map.GetMapID and map.SetMapID) then return false end
    local ok = pcall(QuestMapFrame_OpenToQuestDetails, questID)
    if not (ok and details.questID == questID and details:IsVisible()) then return false end
    if map:GetMapID() ~= mapID then return pcall(map.SetMapID, map, mapID) end
    return true
end

function Pin:OnLoad()
    self:SetSize(30, 30)
    self:SetScalingLimits(1, 1.0, 1.2)
    local icon = self:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    icon:SetAtlas("Waypoint-MapPin-Untracked")
    icon:SetVertexColor(1, 0.82, 0.34)
    self.icon = icon
    self.number = self:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    self.number:SetPoint("CENTER", 0, 1)
end

function Pin:OnAcquired(target, removeMarker, stop, ordinal)
    if stop and stop.single then ordinal = nil end
    self.removeMarker = removeMarker
    self.stop, self.ordinal = stop, ordinal
    self.number:SetText(ordinal and tostring(ordinal) or "")
    self.number:SetShown(ordinal ~= nil)
    local active = not ordinal or ordinal == 1
    self:SetSize(active and 34 or 28, active and 34 or 28)
    self.icon:SetVertexColor(active and 1 or .55, active and .82 or .8, active and .34 or 1)
    if not self.hoverSubscribed then
        self.hoverSubscribed = true
        addon.QuestHover.Subscribe(function(ids)
            if not self.stop then return end
            local highlight = self.stop.quest and ids[self.stop.quest.id]
            local current = not self.ordinal or self.ordinal == 1
            local size = (current and 34 or 28) + (highlight and 5 or 0)
            self:SetSize(size, size)
            if highlight then self.icon:SetVertexColor(.3, 1, 1)
            else self.icon:SetVertexColor(current and 1 or .55, current and .82 or .8, current and .34 or 1) end
        end)
    end
    self:UseFrameLevelType("PIN_FRAME_LEVEL_WAYPOINT_LOCATION")
    self:SetPosition(target.x, target.y)
end

function Pin:CheckMouseButtonPassthrough()
    self:SetPassThroughButtons("LeftButton")
end

function Pin:OnMouseEnter()
    local quest = self.stop and self.stop.quest
    if quest then addon.QuestHover.Set(self, {[quest.id] = true}) end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    local title = self.stop and self.stop.quest and addon.UI.FormatQuestTitle(self.stop.quest) or L.MapMarker
    GameTooltip:SetText(self.ordinal and (self.ordinal .. ". " .. title) or title)
    if self.ordinal == 1 then GameTooltip:AddLine(L.RouteCurrent) end
    GameTooltip:AddLine(L.RemoveMarker)
    GameTooltip:Show()
end

function Pin:OnMouseLeave()
    addon.QuestHover.Clear(self)
    GameTooltip:Hide()
end

function Pin:OnClick(button)
    if button == "RightButton" and self.removeMarker then
        GameTooltip:Hide()
        self.removeMarker()
    end
end

function Pin:OnReleased()
    addon.QuestHover.Clear(self)
    if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
    self.removeMarker = nil
    self.stop, self.ordinal = nil, nil
    self.number:Hide()
    MapCanvasPinMixin.OnReleased(self)
end

-- The virtual template is instantiated after Blizzard's map canvas has loaded.
function ForeverQuestNavigator_InitializeTargetPin(frame)
    Mixin(frame, MapCanvasPinMixin, Pin)
end

local Provider = {}

function Provider:RemoveAllData()
    self:GetMap():RemoveAllPinsByTemplate(PIN_TEMPLATE)
end

function Provider:RefreshAllData()
    self:RemoveAllData()
    local map = self:GetMap()
    local mapID = map:GetMapID()
    status.count = 0
    if not (map:IsShown() and mapID and self.target) then return end
    if self.route and #self.route > 0 then
        for ordinal, stop in ipairs(self.route) do
            local point = stop.target and addon.QuestLocation.ProjectMarker(C_Map, stop.target, mapID)
            if point then map:AcquirePin(PIN_TEMPLATE, point, self.removeMarker, stop, ordinal) status.count = status.count + 1 end
        end
    else
        local point = addon.QuestLocation.ProjectMarker(C_Map, self.target, mapID)
        if point then map:AcquirePin(PIN_TEMPLATE, point, self.removeMarker) status.count = status.count + 1 end
    end
end

local function SameRoute(a, b)
    if not a or not b then return a == b end
    if #a ~= #b then return false end
    for index, stop in ipairs(a) do
        local other = b[index]
        if stop.target.mapID ~= other.target.mapID or stop.target.x ~= other.target.x or stop.target.y ~= other.target.y
            or (stop.quest and stop.quest.id) ~= (other.quest and other.quest.id) then return false end
    end
    return true
end

function addon.ShowQuestMapMarker(target, removeMarker, route)
    pending = nil
    if pendingWatch then pendingWatch:Hide() end
    if not canvasMarkers and target then canvasMarkers = addon.CanvasMarkers.New(WorldMapFrame, C_Map, CreateFrame) end
    if canvasMarkers then
        if provider then provider.target, provider.route = nil, nil provider:RemoveAllData() end
        status.backend = "canvas overlay"
        canvasMarkers:Set(target, removeMarker, route)
        return
    end
    if not provider then
        local map = WorldMapFrame
        if not (target and map and map.AddDataProvider and MapCanvasDataProviderMixin and MapCanvasPinMixin) then
            status.backend = "map not ready"
            if target then WaitForMap(target, removeMarker, route) end
            return
        end
        provider = CreateFromMixins(MapCanvasDataProviderMixin, Provider)
        map:AddDataProvider(provider)
        status.backend = "map data provider"
    end
    local previous = provider.target
    if (target == previous or (target and previous
        and target.mapID == previous.mapID and target.x == previous.x and target.y == previous.y))
        and SameRoute(provider.route, route) and provider.removeMarker == removeMarker then return end
    provider.target = target
    provider.route = target and route or nil
    provider.removeMarker = removeMarker
    provider:RefreshAllData()
end
