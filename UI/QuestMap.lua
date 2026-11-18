local _, addon = ...
local L = addon.L
local PIN_TEMPLATE = "ForeverQuestNavigatorTargetPinTemplate"
local provider
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
    self.removeMarker = removeMarker
    self.stop, self.ordinal = stop, ordinal
    self.number:SetText(ordinal and tostring(ordinal) or "")
    self.number:SetShown(ordinal ~= nil)
    local active = not ordinal or ordinal == 1
    self:SetSize(active and 34 or 28, active and 34 or 28)
    self.icon:SetVertexColor(active and 1 or .55, active and .82 or .8, active and .34 or 1)
    self:UseFrameLevelType("PIN_FRAME_LEVEL_WAYPOINT_LOCATION")
    self:SetPosition(target.x, target.y)
end

function Pin:CheckMouseButtonPassthrough()
    self:SetPassThroughButtons("LeftButton")
end

function Pin:OnMouseEnter()
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    local title = self.stop and self.stop.quest and addon.UI.FormatQuestTitle(self.stop.quest) or L.MapMarker
    GameTooltip:SetText(self.ordinal and (self.ordinal .. ". " .. title) or title)
    if self.ordinal == 1 then GameTooltip:AddLine(L.RouteCurrent) end
    GameTooltip:AddLine(L.RemoveMarker)
    GameTooltip:Show()
end

function Pin:OnMouseLeave()
    GameTooltip:Hide()
end

function Pin:OnClick(button)
    if button == "RightButton" and self.removeMarker then
        GameTooltip:Hide()
        self.removeMarker()
    end
end

function Pin:OnReleased()
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
    if not (map:IsShown() and mapID and self.target) then return end
    if self.route and #self.route > 0 then
        for ordinal, stop in ipairs(self.route) do
            local point = stop.target and addon.QuestLocation.ProjectMarker(C_Map, stop.target, mapID)
            if point then map:AcquirePin(PIN_TEMPLATE, point, self.removeMarker, stop, ordinal) end
        end
    else
        local point = addon.QuestLocation.ProjectMarker(C_Map, self.target, mapID)
        if point then map:AcquirePin(PIN_TEMPLATE, point, self.removeMarker) end
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
    if not provider then
        local map = WorldMapFrame
        if not (target and map and map.AddDataProvider and MapCanvasDataProviderMixin and MapCanvasPinMixin) then
            return
        end
        provider = CreateFromMixins(MapCanvasDataProviderMixin, Provider)
        map:AddDataProvider(provider)
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
