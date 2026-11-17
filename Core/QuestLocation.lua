local _, addon = ...
local QuestLocation = {}
addon.QuestLocation = QuestLocation

local function IsReadableNumber(value)
    return not (issecretvalue and issecretvalue(value)) and type(value) == "number"
end

local function IsMapPosition(x, y)
    return IsReadableNumber(x) and IsReadableNumber(y)
        and x >= 0 and x <= 1 and y >= 0 and y <= 1 and (x ~= 0 or y ~= 0)
end

function QuestLocation.IsOutdoorMap(mapAPI, mapType, mapID, maps)
    local visited = {}
    while mapID and not visited[mapID] do
        visited[mapID] = true
        local info = mapAPI.GetMapInfo(mapID)
        if not info then return false end
        if info.mapType == mapType.Zone then return maps[mapID] == true end
        if info.mapType ~= mapType.Micro then return false end
        mapID = info.parentMapID
    end
    return false
end

function QuestLocation.GetOutdoorWaypoint(mapAPI, questAPI, mapType, maps, questID)
    if not questAPI.GetNextWaypoint then return end
    local mapID, x, y = questAPI.GetNextWaypoint(questID)
    if IsReadableNumber(mapID) and mapID > 0 and IsMapPosition(x, y)
        and QuestLocation.IsOutdoorMap(mapAPI, mapType, mapID, maps) then
        return { mapID = mapID, x = x, y = y }
    end
end

local function FindParentMap(mapAPI, parentID, wantedType)
    local visited = {}
    while parentID and parentID > 0 and not visited[parentID] do
        visited[parentID] = true
        local parent = mapAPI.GetMapInfo(parentID)
        if not parent then break end
        if parent.mapType == wantedType then return parentID end
        parentID = parent.parentMapID
    end
end

local function GetTargetMaps(mapAPI, mapType, mapInfo, localMaps, acrossZones)
    if not (acrossZones and mapInfo.mapType == mapType.Zone and mapAPI.GetMapChildrenInfo
        and mapAPI.GetWorldPosFromMapPos and CreateVector2D) then return localMaps end
    local continentID = FindParentMap(mapAPI, mapInfo.parentMapID, mapType.Continent)
    if not continentID then return localMaps end
    local maps = {}
    for id in pairs(localMaps) do maps[id] = true end
    for _, zone in ipairs(mapAPI.GetMapChildrenInfo(continentID, mapType.Zone, true) or {}) do
        if zone.mapID then maps[zone.mapID] = true end
    end
    return maps
end

function QuestLocation.GetLocalQuestMarkers(mapAPI, questAPI, mapType, acrossZones)
    if not (mapAPI and mapAPI.GetBestMapForUnit and mapAPI.GetMapInfo and questAPI and questAPI.GetQuestsOnMap and mapType) then
        return nil
    end

    local mapID = mapAPI.GetBestMapForUnit("player")
    local mapInfo = mapID and mapID > 0 and mapAPI.GetMapInfo(mapID)
    local localMaps = {}
    while mapInfo and mapInfo.mapType == mapType.Micro and not localMaps[mapID] do
        localMaps[mapID] = true
        mapID = mapInfo.parentMapID
        mapInfo = mapID and mapID > 0 and mapAPI.GetMapInfo(mapID)
    end

    if not mapInfo or (mapInfo.mapType ~= mapType.Zone and mapInfo.mapType ~= mapType.Dungeon) then
        return nil
    end
    localMaps[mapID] = true
    local targetMaps = GetTargetMaps(mapAPI, mapType, mapInfo, localMaps, acrossZones)

    local markersByQuest = {}
    for targetMapID in pairs(targetMaps) do
        for _, pin in ipairs(questAPI.GetQuestsOnMap(targetMapID) or {}) do
            if pin.questID and pin.questID > 0 and not pin.isMapIndicatorQuest then
                local markers = markersByQuest[pin.questID] or {}
                markersByQuest[pin.questID] = markers
                if not markers.mapID or (localMaps[targetMapID] and not localMaps[markers.mapID]) then
                    markers.mapID = targetMapID
                end
                if IsMapPosition(pin.x, pin.y) then
                    markers[#markers + 1] = { mapID = targetMapID, x = pin.x, y = pin.y }
                end
            end
        end
    end
    return markersByQuest, mapInfo.name, localMaps, targetMaps, mapID
end

local function PlayerMapPosition(mapAPI, mapID)
    local pos = mapAPI.GetPlayerMapPosition(mapID, "player")
    if pos and not (issecretvalue and issecretvalue(pos)) and IsMapPosition(pos.x, pos.y) then return pos end
end

local function GetPlayerMapGeometry(mapAPI, mapID)
    local position = PlayerMapPosition(mapAPI, mapID)
    if not position then return false end

    local width, height = mapAPI.GetMapWorldSize(mapID)
    if not (IsReadableNumber(width) and width > 0 and width < math.huge
        and IsReadableNumber(height) and height > 0 and height < math.huge) then
        return false
    end
    return { x = position.x, y = position.y, width = width, height = height }
end

local function WorldPosition(mapAPI, mapID, position)
    local continent, point = mapAPI.GetWorldPosFromMapPos(mapID, position)
    if (issecretvalue and issecretvalue(point)) or not point or not IsReadableNumber(continent) then return end
    if IsReadableNumber(point.x) and math.abs(point.x) < math.huge
        and IsReadableNumber(point.y) and math.abs(point.y) < math.huge then
        return { continent = continent, x = point.x, y = point.y }
    end
end

function QuestLocation.GetMarkerWorldPosition(mapAPI, marker)
    if marker.world == nil and mapAPI.GetWorldPosFromMapPos and CreateVector2D then
        marker.world = WorldPosition(mapAPI, marker.mapID, CreateVector2D(marker.x, marker.y)) or false
    end
    return marker.world
end

local function IsDestinationMap(mapAPI, mapType, id)
    if not (mapType and mapAPI.GetMapInfo and IsReadableNumber(id) and id > 0) then return false end
    local info = mapAPI.GetMapInfo(id)
    return info and (info.mapType == mapType.Zone or info.mapType == mapType.Micro)
end

function QuestLocation.GetZone(mapAPI, mapType, mapID)
    local visited = {}
    while mapType and mapID and not visited[mapID] do
        visited[mapID] = true
        local info = mapAPI.GetMapInfo(mapID)
        if not info then return end
        if info.mapType == mapType.Zone or info.mapType == mapType.Dungeon then return mapID, info.name end
        if info.mapType ~= mapType.Micro then return end
        mapID = info.parentMapID
    end
end

function QuestLocation.GetDestinationMap(mapAPI, mapType, questID, marker)
    -- The same world point can appear on overlapping zone maps. Prefer the quest's
    -- destination, with travel waypoints ignored, before resolving the point itself.
    local destination = GetQuestUiMapID and GetQuestUiMapID(questID, true)
    if IsDestinationMap(mapAPI, mapType, destination) then return destination end
    local world = marker and mapAPI.GetMapPosFromWorldPos and QuestLocation.GetMarkerWorldPosition(mapAPI, marker)
    if world then
        local mapID, point = mapAPI.GetMapPosFromWorldPos(world.continent, CreateVector2D(world.x, world.y))
        if point and not (issecretvalue and issecretvalue(point))
            and IsMapPosition(point.x, point.y) and IsDestinationMap(mapAPI, mapType, mapID) then
            return mapID
        end
    end
end

function QuestLocation.ProjectMarker(mapAPI, marker, mapID)
    if marker.mapID == mapID then return marker end
    local world = mapAPI.GetMapPosFromWorldPos and QuestLocation.GetMarkerWorldPosition(mapAPI, marker)
    if not world then return end
    local id, point = mapAPI.GetMapPosFromWorldPos(world.continent, CreateVector2D(world.x, world.y), mapID)
    if id == mapID and point and not (issecretvalue and issecretvalue(point)) and IsMapPosition(point.x, point.y) then
        return { mapID = mapID, x = point.x, y = point.y, world = world }
    end
end

function QuestLocation.GetDistanceMetric(mapAPI, reference)
    local world = QuestLocation.GetMarkerWorldPosition(mapAPI, reference)
    if world then
        return function(a, b)
            local from = QuestLocation.GetMarkerWorldPosition(mapAPI, a)
            local to = QuestLocation.GetMarkerWorldPosition(mapAPI, b)
            if from and to and from.continent == world.continent and to.continent == world.continent then
                return math.sqrt((from.x - to.x) ^ 2 + (from.y - to.y) ^ 2)
            end
        end
    end
    local width, height = mapAPI.GetMapWorldSize(reference.mapID)
    if not (IsReadableNumber(width) and width > 0 and width < math.huge
        and IsReadableNumber(height) and height > 0 and height < math.huge) then return end
    return function(a, b)
        if a.mapID == reference.mapID and b.mapID == reference.mapID then
            return math.sqrt(((a.x - b.x) * width) ^ 2 + ((a.y - b.y) * height) ^ 2)
        end
    end
end

function QuestLocation.GetNearbyFlightPoint(mapAPI, taxiAPI, mapType, factions, playerFaction, zoneID, target, confirmed)
    if not (taxiAPI and taxiAPI.GetTaxiNodesForMap and factions and target and confirmed and next(confirmed)) then return end
    local distance = QuestLocation.GetDistanceMetric(mapAPI, target)
    if not distance then return end
    local closest, yards
    local faction = factions[playerFaction]
    local function CheckMap(mapID)
        local ok, nodes = pcall(taxiAPI.GetTaxiNodesForMap, mapID)
        if not ok then return end
        for _, node in ipairs(nodes or {}) do
            local pos = node.position
            if confirmed[node.nodeID] == true and node.isUndiscovered == false
                and (node.faction == factions.Neutral or (faction and node.faction == faction))
                and type(node.name) == "string" and node.name ~= "" and pos and IsMapPosition(pos.x, pos.y) then
                local range = distance(target, { mapID = mapID, x = pos.x, y = pos.y })
                if range and range <= 1000 and (not yards or range < yards) then
                    closest, yards = node.name, range
                end
            end
        end
    end
    CheckMap(zoneID)
    local zone = mapAPI.GetMapInfo and mapAPI.GetMapInfo(zoneID)
    local continentID = zone and mapType and FindParentMap(mapAPI, zone.parentMapID, mapType.Continent)
    if continentID then CheckMap(continentID) end
    return closest, yards
end

local function PlayerWorldPosition(mapAPI, localMaps)
    if not (localMaps and mapAPI.GetWorldPosFromMapPos and mapAPI.GetBestMapForUnit and CreateVector2D) then return end
    local mapID = mapAPI.GetBestMapForUnit("player")
    if not localMaps[mapID] then return end
    local position = PlayerMapPosition(mapAPI, mapID)
    local player = position and WorldPosition(mapAPI, mapID, position)
    if player then return player end
    for id in pairs(localMaps) do
        if id ~= mapID then
            position = PlayerMapPosition(mapAPI, id)
            player = position and WorldPosition(mapAPI, id, position)
            if player then return player end
        end
    end
end

function QuestLocation.GetFlightMarker(mapID, node)
    local position = node.position
    if type(node.name) == "string" and node.name ~= "" and position
        and not (issecretvalue and issecretvalue(position)) and IsMapPosition(position.x, position.y) then
        return { id = node.nodeID, name = node.name, mapID = mapID, x = position.x, y = position.y }
    end
end

local function FlightWorldPosition(mapAPI, marker, player)
    if type(marker) ~= "table" or not IsReadableNumber(marker.mapID) or marker.mapID <= 0
        or type(marker.name) ~= "string" or not IsMapPosition(marker.x, marker.y) then return end
    local world = QuestLocation.GetMarkerWorldPosition(mapAPI, marker)
    if world and world.continent == player.continent then return world end
end

local function WorldDistance(from, to)
    return math.sqrt((from.x - to.x) ^ 2 + (from.y - to.y) ^ 2)
end

function QuestLocation.GetFlightContext(mapAPI, localMaps, routes)
    if not routes or not next(routes) then return end
    local player = PlayerWorldPosition(mapAPI, localMaps)
    if not player then return end
    local departures = {}
    for _, route in pairs(routes) do
        if type(route) == "table" and type(route.stops) == "table" and #route.stops > 0 then
            local world = FlightWorldPosition(mapAPI, route.origin, player)
            local approach = world and WorldDistance(player, world)
            if approach and approach <= 1000 then
                departures[#departures + 1] = { route = route, approach = approach }
            end
        end
    end
    if #departures > 0 then return { player = player, departures = departures } end
end

function QuestLocation.GetFlightPlan(mapAPI, target, context)
    if not (target and context) then return end
    local player = context.player
    local goal = QuestLocation.GetMarkerWorldPosition(mapAPI, target)
    if not goal or goal.continent ~= player.continent then return end
    local footSpeed, flightSpeed = 7, 28
    local walkSeconds = WorldDistance(player, goal) / footSpeed
    local best
    for _, departure in ipairs(context.departures) do
        for _, landing in ipairs(departure.route.stops) do
            local world = FlightWorldPosition(mapAPI, landing, player)
            local finish = world and WorldDistance(world, goal)
            if finish and finish <= 1000 and IsReadableNumber(landing.flightYards)
                and landing.flightYards > 0 and landing.flightYards < math.huge then
                -- Allow for curves along each flight leg and boarding.
                local flightSeconds = 2 * landing.flightYards / flightSpeed + 20
                local seconds = (departure.approach + finish) / footSpeed + flightSeconds
                if seconds + 60 <= walkSeconds and (not best or seconds < best.seconds
                    or (seconds == best.seconds and departure.route.origin.id < best.origin.id)) then
                    best = { origin = departure.route.origin, landing = landing, approach = departure.approach,
                        finish = finish, seconds = seconds }
                end
            end
        end
    end
    return best
end

local OBJECTIVE_SWITCH_MARGIN = 25

local function BuildMeasurement(target)
    local distance = math.sqrt(target.squared)
    local measurement = { yards = distance, marker = target.marker }
    if distance > 3 then
        measurement.east, measurement.north = target.east / distance, target.north / distance
    end
    return measurement
end

function QuestLocation.MeasureQuests(mapAPI, markersByQuest, questIDs, localMaps, previousObjectives, objectiveLock, avoidedObjectives)
    local measurements, objectiveDistances = {}, {}
    if not (mapAPI and mapAPI.GetPlayerMapPosition and mapAPI.GetMapWorldSize) then
        return measurements, objectiveDistances
    end

    local player = PlayerWorldPosition(mapAPI, localMaps)
    local geometryByMap = {}
    for _, questID in ipairs(questIDs) do
        local closest, objectives = nil, {}
        local avoided = avoidedObjectives and avoidedObjectives[questID] or {}
        for _, marker in ipairs(markersByQuest[questID] or {}) do
            local east, north
            if player then
                local world = QuestLocation.GetMarkerWorldPosition(mapAPI, marker)
                if world and world.continent == player.continent then
                    -- Blizzard world X increases north and world Y increases west.
                    east, north = player.y - world.y, world.x - player.x
                end
            end
            if not east and (not localMaps or localMaps[marker.mapID]) then
                local geometry = geometryByMap[marker.mapID]
                if geometry == nil then
                    geometry = GetPlayerMapGeometry(mapAPI, marker.mapID)
                    geometryByMap[marker.mapID] = geometry
                end
                if geometry then
                    east = (marker.x - geometry.x) * geometry.width
                    north = (geometry.y - marker.y) * geometry.height
                end
            end
            if east then
                local squared = east * east + north * north
                if squared < math.huge then
                    local index = marker.objectiveIndex
                    local bestForObjective = index and objectives[index]
                    local closer = not avoided[index] and (not closest or squared < closest.squared)
                    if closer or (index and (not bestForObjective or squared < bestForObjective.squared)) then
                        local target = { squared = squared, east = east, north = north, marker = marker }
                        if closer then closest = target end
                        if index then objectives[index] = target end
                    end
                end
            end
        end
        objectiveDistances[questID] = objectives
        if closest then
            local previousIndex = previousObjectives and previousObjectives[questID]
            local previous = not avoided[previousIndex] and objectives[previousIndex]
            local locked = objectiveLock and objectiveLock.questID == questID and not avoided[objectiveLock.index]
                and objectives[objectiveLock.index]
            if locked then
                closest = locked
            elseif previous and math.sqrt(previous.squared) <= math.sqrt(closest.squared) + OBJECTIVE_SWITCH_MARGIN then
                closest = previous
            end
            measurements[questID] = BuildMeasurement(closest)
        end
    end
    return measurements, objectiveDistances
end

function QuestLocation.GetRelativeDirection(direction, facing)
    if not (direction and IsReadableNumber(facing) and math.abs(facing) < math.huge) then
        return nil
    end
    -- WoW measures facing counterclockwise from map north.
    local sine, cosine = math.sin(facing), math.cos(facing)
    local right = direction.east * cosine + direction.north * sine
    local forward = direction.north * cosine - direction.east * sine
    return right, forward
end
