local _, addon = ...
-- Flight point discovery and flight hints. Pure helpers: all game APIs and
-- state are passed in, so the navigator controller only wires them up.
local FlightPoints = {}
addon.FlightPoints = FlightPoints

local function MeasurePath(api, points, origin, landing, slot, distance)
    local count = api.GetNumRoutes(slot)
    if type(count) ~= "number" or count < 1 or count > 50 then return end
    local length, previous = 0, origin
    for index = 1, count do
        local source = points[api.TaxiGetNodeSlot(slot, index, true)]
        local target = points[api.TaxiGetNodeSlot(slot, index, false)]
        local yards = source == previous and target and distance(source, target)
        if not yards or yards <= 0 then return end
        length, previous = length + yards, target
    end
    if previous == landing then return length end
end
FlightPoints.MeasurePath = MeasurePath

-- Records reachable taxi nodes in flight.confirmedPoints and measured routes from
-- the current node in flight.routes. api: Enum, GetTaxiMapID, C_TaxiMap, C_Map,
-- GetNumRoutes, TaxiGetNodeSlot.
function FlightPoints.Confirm(flight, api)
    local states = api.Enum and api.Enum.FlightPathState
    if not (flight.confirmedPoints and states and api.GetTaxiMapID and api.C_TaxiMap and api.C_TaxiMap.GetAllTaxiNodes) then return end
    local mapID = api.GetTaxiMapID()
    if type(mapID) ~= "number" or mapID <= 0 then return end
    local ok, nodes = pcall(api.C_TaxiMap.GetAllTaxiNodes, mapID)
    if not ok then return end
    local origin, points, reachable = nil, {}, {}
    for _, node in ipairs(nodes or {}) do
        if type(node.nodeID) == "number" and node.nodeID > 0 and not node.isMapLayerTransition then
            if node.state == states.Current or node.state == states.Reachable then
                flight.confirmedPoints[node.nodeID] = true
            end
            local slot = node.slotIndex
            if type(slot) == "number" and slot > 0 then
                local point = addon.QuestLocation.GetFlightMarker(mapID, node)
                points[slot] = point
                if node.state == states.Current then origin = point end
                if point and node.state == states.Reachable then reachable[#reachable + 1] = slot end
            end
        end
    end
    if not origin then return end
    local stops = {}
    local distance = api.GetNumRoutes and api.TaxiGetNodeSlot and addon.QuestLocation.GetDistanceMetric(api.C_Map, origin)
    if distance then
        for _, slot in ipairs(reachable) do
            local landing = points[slot]
            local measured, length = pcall(MeasurePath, api, points, origin, landing, slot, distance)
            if measured and length then
                landing.flightYards = length
                stops[#stops + 1] = landing
            end
        end
    end
    if flight.routes then flight.routes[origin.id] = { origin = origin, stops = stops } end
end

-- Text hint for flying towards a distant destination, or nil.
-- context: measurement, playerZoneID, minimum, flightContext, confirmedPoints, faction.
function FlightPoints.Hint(destination, context, api)
    local L = addon.L
    local measurement = context.measurement
    if not measurement or measurement.yards < context.minimum then return end
    local plan = addon.QuestLocation.GetFlightPlan(api.C_Map, destination.target, context.flightContext)
    if plan then
        local text = L.FlightRoute:format(plan.origin.name, plan.landing.name, plan.approach, plan.finish)
        -- Same assumptions as the plan: walking pace and a flight allowance incl. boarding.
        if type(plan.seconds) == "number" and type(plan.walkSeconds) == "number" then
            text = text .. "\n" .. L.FlightCompare:format(math.max(1, math.floor(plan.seconds / 60 + .5)),
                math.max(1, math.floor(plan.walkSeconds / 60 + .5)))
        end
        return text
    end
    if not destination.zoneID or destination.zoneID == context.playerZoneID then return end
    if not destination.flightChecked then
        destination.flightChecked = true
        destination.flight, destination.flightDistance = addon.QuestLocation.GetNearbyFlightPoint(
            api.C_Map, api.C_TaxiMap, api.Enum and api.Enum.UIMapType, api.Enum and api.Enum.FlightPathFaction,
            context.faction, destination.zoneID, destination.target, context.confirmedPoints)
    end
    if destination.flight then
        return L.UnlockedFlightPoint:format(destination.flight, destination.flightDistance)
    end
end

-- Short instruction shown while on a taxi.
function FlightPoints.Step(quest, measured, questLog)
    local L = addon.L
    if not quest then return L.FlightGeneric end
    if quest.readyToTurnIn then return L.FlightTurnIn end
    local goals = questLog.GetQuestObjectives and questLog.GetQuestObjectives(quest.id)
    local selected = measured and measured.marker and measured.marker.objectiveIndex
    local goal = selected and goals and goals[selected]
    if not goal then goal = addon.QuestLog.GetNextObjective(questLog, quest.id) end
    return goal and L.FlightObjective:format(goal.text) or L.FlightGeneric
end
