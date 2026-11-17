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
end

function Pin:OnAcquired(target, removeMarker)
    self.removeMarker = removeMarker
    self:UseFrameLevelType("PIN_FRAME_LEVEL_WAYPOINT_LOCATION")
    self:SetPosition(target.x, target.y)
end

function Pin:CheckMouseButtonPassthrough()
    self:SetPassThroughButtons("LeftButton")
end

function Pin:OnMouseEnter()
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(L.MapMarker)
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
    local point = addon.QuestLocation.ProjectMarker(C_Map, self.target, mapID)
    if point then map:AcquirePin(PIN_TEMPLATE, point, self.removeMarker) end
end

function addon.ShowQuestMapMarker(target, removeMarker)
    if not provider then
        local map = WorldMapFrame
        if not (target and map and map.AddDataProvider and MapCanvasDataProviderMixin and MapCanvasPinMixin) then
            return
        end
        provider = CreateFromMixins(MapCanvasDataProviderMixin, Provider)
        map:AddDataProvider(provider)
    end
    local previous = provider.target
    if target == previous or (target and previous
        and target.mapID == previous.mapID and target.x == previous.x and target.y == previous.y) then return end
    provider.target = target
    provider.removeMarker = removeMarker
    provider:RefreshAllData()
end
