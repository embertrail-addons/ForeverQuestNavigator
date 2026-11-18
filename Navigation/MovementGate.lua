local _, addon = ...
local Gate = {}
addon.MovementGate = Gate
local function Number(value)
    return not (issecretvalue and issecretvalue(value)) and type(value) == "number" and value == value and math.abs(value) < math.huge
end
function Gate.Sample(api)
    if not (api and api.GetBestMapForUnit and api.GetPlayerMapPosition and api.GetMapWorldSize) then return end
    local mapID = api.GetBestMapForUnit("player")
    local point = mapID and api.GetPlayerMapPosition(mapID, "player")
    if not point or (issecretvalue and issecretvalue(point)) then return end
    local marker = {mapID = mapID, x = point.x, y = point.y}
    if not addon.TravelSupport.ValidPoint(marker) then return end
    local world = addon.QuestLocation.GetMarkerWorldPosition(api, marker)
    if world then return {mapID = mapID, space = world.continent, x = world.x, y = world.y, world = true} end
    local width, height = api.GetMapWorldSize(mapID)
    if Number(width) and width > 0 and Number(height) and height > 0 then
        return {mapID = mapID, x = point.x * width, y = point.y * height, width = width, height = height}
    end
end
function Gate.ShouldUpdate(previous, current, phase, near, deadline, now)
    if not previous or not current or not previous.point or previous.phase ~= phase or (deadline and now >= deadline)
        or (previous.deadline and now >= previous.deadline) then return true end
    local old = previous.point
    if old.mapID ~= current.mapID or old.space ~= current.space or old.world ~= current.world
        or old.width ~= current.width or old.height ~= current.height then return true end
    local threshold = near and 1 or 3
    return (old.x - current.x)^2 + (old.y - current.y)^2 >= threshold^2
end
