local _, addon = ...
local Detour = {}
addon.TemporaryDetour = Detour
function Detour.New(mapID, x, y, name)
    local point = {mapID = tonumber(mapID), x = tonumber(x), y = tonumber(y)}
    if not addon.TravelSupport.ValidPoint(point) or point.mapID ~= math.floor(point.mapID) then return end
    name = type(name) == "string" and name:gsub("[%c|]", ""):match("^%s*(.-)%s*$") or ""
    if #name > 120 then return end
    point.name = name ~= "" and name or addon.L.TemporaryDetour
    return point
end
function Detour.Measure(mapAPI, point)
    if not point then return end
    local current = mapAPI and mapAPI.GetBestMapForUnit and mapAPI.GetBestMapForUnit("player")
    return addon.QuestLocation.MeasureQuests(mapAPI, {[1] = {point}}, {1}, current and {[current] = true} or nil)[1]
end
function Detour.IsOutdoor(mapAPI, mapType, mapID)
    if not (mapAPI and mapAPI.GetMapInfo and mapType) then return false end
    local visited = {}
    while mapID and not visited[mapID] do
        visited[mapID] = true
        local info = mapAPI.GetMapInfo(mapID)
        if not info then return false end
        if info.mapType == mapType.Zone then return true end
        if info.mapType ~= mapType.Micro then return false end
        mapID = info.parentMapID
    end
    return false
end
