local addonName, addon = ...
local L = addon.L
local events = CreateFrame("Frame")
local tracker, settings, settingsCategory
local minimapButton
local manualQuestID
local heldQuest, arrivalState, seenRecommendedOffers
local questLogButton, questLogDetails
local skippedQuestIDs = {}
local skipOrder = 0
local refreshPending = false
local questMarkers, measurableQuestIDs, distanceTicker, distanceMaps
local questMeasurements, questTargetMaps
local playerZoneID, questDestinations, shownZones = nil, {}, {}
local activeDirection, directionTicker
local eligibleQuests, shownQuests, distanceOrder
local shownObjectives, shownReason
local shownObjectiveTargets
local objectiveDistances, objectiveLock
local previousObjectives = {}
local avoidedObjectives = {}
local integration = addon.QuestieIntegration
local objectiveMarkers, killMarkers, questieTicker, questieReadyRegistered
local questieTrackerMenuHooked
local nearbyOffers
local routeChains, shownRouteNote, shownRouteDetails, shownMapAvailable
local shownRewards = {}
local outing
local ScheduleRefresh
local SetDisplayMode
local GetQuestDestination
local UpdateQuestLogButton
local markedQuestID
local MINIMUM_FLIGHT_HINT_DISTANCE = 1500
local DEFAULT_OPACITY = 80
local DEFAULT_OFFER_RADIUS = 350
local MAX_OFFER_RADIUS = 1000
local shownAlternativeRoutes = {}
local shownNearbyStops
local shownApproachStops
local shownRoutePreview
local shownAreaOverview
local confirmedFlightPoints, flightRoutes, taxiMapOpen
local questJourneys, turnInLocations = nil, {}
local savedAccessPoints, passedAccessPoints = {}, {}
local session

local function SessionTime()
    return GetTime and GetTime() or 0
end

local function CaptureSessionXP()
    if session and UnitXP and UnitXPMax and UnitLevel then
        session:CaptureXP(UnitLevel("player"), UnitXP("player"), UnitXPMax("player"))
        session:Save(SessionTime())
    end
end

local function ShowSession()
    if session then addon.ShowSessionDashboard(function() return session end, SessionTime) end
end

local function ClearMapMarker()
    markedQuestID = nil
    addon.ShowQuestMapMarker()
end

local function UpdateMapMarker()
    if not markedQuestID then return end
    if not (C_QuestLog and C_QuestLog.IsOnQuest and C_QuestLog.IsOnQuest(markedQuestID)) then
        ClearMapMarker()
        return
    end
    local destination = GetQuestDestination(markedQuestID)
    addon.ShowQuestMapMarker(destination and destination.target, ClearMapMarker)
end

local function MeasureFlightPath(points, origin, landing, slot, distance)
    local count = GetNumRoutes(slot)
    if type(count) ~= "number" or count < 1 or count > 50 then return end
    local length, previous = 0, origin
    for index = 1, count do
        local source = points[TaxiGetNodeSlot(slot, index, true)]
        local target = points[TaxiGetNodeSlot(slot, index, false)]
        local yards = source == previous and target and distance(source, target)
        if not yards or yards <= 0 then return end
        length, previous = length + yards, target
    end
    if previous == landing then return length end
end

local function ConfirmFlightPoints()
    local states = Enum and Enum.FlightPathState
    if not (confirmedFlightPoints and states and GetTaxiMapID and C_TaxiMap and C_TaxiMap.GetAllTaxiNodes) then return end
    local mapID = GetTaxiMapID()
    if type(mapID) ~= "number" or mapID <= 0 then return end
    local ok, nodes = pcall(C_TaxiMap.GetAllTaxiNodes, mapID)
    if not ok then return end
    local origin, points, reachable = nil, {}, {}
    for _, node in ipairs(nodes or {}) do
        if type(node.nodeID) == "number" and node.nodeID > 0 and not node.isMapLayerTransition then
            if node.state == states.Current or node.state == states.Reachable then
                confirmedFlightPoints[node.nodeID] = true
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
    local distance = GetNumRoutes and TaxiGetNodeSlot and addon.QuestLocation.GetDistanceMetric(C_Map, origin)
    if distance then
        for _, slot in ipairs(reachable) do
            local landing = points[slot]
            local ok, length = pcall(MeasureFlightPath, points, origin, landing, slot, distance)
            if ok and length then
                landing.flightYards = length
                stops[#stops + 1] = landing
            end
        end
    end
    flightRoutes[origin.id] = { origin = origin, stops = stops }
end

local function GetFlightHint(questID, destination, flightContext)
    local measurement = questMeasurements and questMeasurements[questID]
    if not measurement or measurement.yards < MINIMUM_FLIGHT_HINT_DISTANCE then return end

    local plan = addon.QuestLocation.GetFlightPlan(C_Map, destination.target, flightContext)
    if plan then
        return L.FlightRoute:format(
            plan.origin.name, plan.landing.name, plan.approach, plan.finish)
    end
    if not destination.zoneID or destination.zoneID == playerZoneID then return end
    if not destination.flightChecked then
        destination.flightChecked = true
        local faction = UnitFactionGroup and UnitFactionGroup("player")
        destination.flight, destination.flightDistance = addon.QuestLocation.GetNearbyFlightPoint(
            C_Map, C_TaxiMap, Enum and Enum.UIMapType, Enum and Enum.FlightPathFaction,
            faction, destination.zoneID, destination.target, confirmedFlightPoints)
    end
    if destination.flight then
        return L.UnlockedFlightPoint:format(
            destination.flight, destination.flightDistance)
    end
end

local function DescribeDestination(quest, destination)
    local measured = questMeasurements and questMeasurements[quest.id]
    local target = measured and measured.objectiveMarker or destination.target
    local map = C_Map.GetMapInfo(target and target.mapID or destination.mapID)
    local place = map and map.name or destination.zoneName
    if target and place then
        place = ("%s (%.1f, %.1f)"):format(place, target.x * 100, target.y * 100)
    end
    local nextStop = quest.readyToTurnIn and L.TurnIn or L.QuestObjective
    if destination.turnInName then nextStop = L.TurnInTo:format(destination.turnInName) end
    return place and (nextStop .. ": " .. place) or nextStop
end

local function DescribeRecommendation(quest, playerLevel)
    local measurement = questMeasurements and questMeasurements[quest.id]
    local distance = measurement and (measurement.yards <= 500 and L.NearbyTarget or L.TravelDistance)
    local level = addon.QuestPrioritizer.GetLevel(quest)
    local fit
    if quest.readyToTurnIn then
        return
    elseif level and type(playerLevel) == "number" and playerLevel > 0 then
        local gap = level - playerLevel
        if gap == 0 then
            fit = L.YourLevel
        elseif gap > 0 then
            fit = (gap == 1 and L.LevelAboveOne or L.LevelAboveMany):format(gap)
        else
            fit = (gap == -1 and L.LevelBelowOne or L.LevelBelowMany):format(-gap)
        end
    end
    if distance and fit then return distance .. " · " .. fit end
    return distance or fit
end

function addon.DescribeQuest(quest, measurement)
    local text = addon.Recommendation.Describe(quest, measurement,
        UnitLevel and UnitLevel("player"), routeChains and routeChains[quest.id])
    if settings and settings.showQuestXP and not addon.QuestLog.GetTurnInXP(quest) then
        text = text .. "\n" .. L.UnknownXP
    end
    if not quest.readyToTurnIn then
        local journey = questJourneys and questJourneys[quest.id]
        text = text .. "\n" .. (journey and L.JourneyEstimate:format(journey.totalYards, journey.returnYards) or L.JourneyUnknown)
        if journey then text = text .. "\n" .. L.JourneyEstimateHelp end
        if questJourneys then
            local format = journey and L.JourneyPriority or L.JourneyUncertainty
            text = text .. "\n" .. format:format(addon.TravelSupport.PlanningPenalty(quest, journey, true))
        end
    end
    if measurement and measurement.objectiveMarker then
        local marker = measurement.marker
        text = text .. "\n" .. L.AccessRoute:format(marker.accessName or L.SavedAccess, marker.x * 100, marker.y * 100, measurement.accessLeg)
    end
    text = text .. "\n" .. L.QuestMenuHint
    return text
end

local function BuildDiagnostics()
    local active = shownQuests and shownQuests[1]
    local version = C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(addonName, "Version")
    local report = addon.Recommendation.BuildReport({
        version = version, questie = addon.ReadQuestieStatus(C_AddOns),
        playerLevel = UnitLevel and UnitLevel("player"), mapID = playerZoneID,
        manual = manualQuestID ~= nil, objectiveLock = objectiveLock ~= nil, held = heldQuest ~= nil,
        activeID = active and active.id, quests = shownQuests or eligibleQuests,
        measurements = questMeasurements, reason = shownReason, route = shownRouteDetails, journeys = questJourneys,
    })
    return report
end

local function ShowDiagnostics()
    addon.ShowDiagnosticReport(BuildDiagnostics())
end

local function GetNearbyStops(quest, destination, ranked, playerLevel)
    if not (destination and destination.zoneID and destination.target) then return end
    local distance = addon.QuestLocation.GetDistanceMetric(C_Map, destination.target)
    if not distance then return end
    local stops
    for _, candidate in ipairs(ranked) do
        if candidate.id ~= quest.id and not addon.QuestPrioritizer.IsLowPriority(candidate, playerLevel) then
            local other = GetQuestDestination(candidate.id)
            if other and other.target and other.zoneID == destination.zoneID then
                local range = distance(destination.target, other.target)
                if range and range <= 500 then
                    stops = stops or {}
                    stops[#stops + 1] = { quest = candidate, yards = math.floor(range + 0.5) }
                end
            end
        end
    end
    if stops then
        table.sort(stops, function(a, b)
            if a.yards ~= b.yards then return a.yards < b.yards end
            return a.quest.id < b.quest.id
        end)
    end
    return stops
end

local function SameNearbyStops(previous, current)
    if not previous or not current then return previous == current end
    if #previous ~= #current then return false end
    for index, stop in ipairs(current) do
        if previous[index].quest ~= stop.quest or previous[index].yards ~= stop.yards then return false end
    end
    return true
end

local function GetObjectiveTargets(quest, objectives)
    if not objectives then return end
    local targets = not quest.readyToTurnIn and objectiveDistances and objectiveDistances[quest.id]
    local measurement = questMeasurements and questMeasurements[quest.id]
    local selected = targets and measurement and measurement.marker.objectiveIndex or nil
    local avoided = avoidedObjectives[quest.id] or {}
    local details = { index = selected, locked = objectiveLock and objectiveLock.questID == quest.id, avoidedCount = 0 }
    for index, goal in ipairs(objectives) do
        if goal.text and goal.text ~= "" then
            details[#details + 1] = {
                index = index, text = goal.text, finished = goal.finished == true,
                selectable = not goal.finished and targets and targets[index] ~= nil or false,
                avoided = avoided[index] == true,
            }
            if avoided[index] then details.avoidedCount = details.avoidedCount + 1 end
        end
    end
    if #details > 0 then return details end
end

local function SameObjectiveTargets(a, b)
    if not a or not b then return a == b end
    if a.index ~= b.index or a.locked ~= b.locked or a.avoidedCount ~= b.avoidedCount or #a ~= #b then return false end
    for index, goal in ipairs(a) do
        local other = b[index]
        if goal.index ~= other.index or goal.text ~= other.text or goal.finished ~= other.finished
            or goal.selectable ~= other.selectable or goal.avoided ~= other.avoided then return false end
    end
    return true
end

local function SameApproachStops(a, b)
    if not a or not b then return a == b end
    if #a ~= #b then return false end
    for index, stop in ipairs(a) do
        if stop.quest ~= b[index].quest then return false end
    end
    return true
end

local function DescribeQuestXP(quest, xpNeeded, playerLevel)
    local reward = xpNeeded and addon.QuestLog.GetTurnInXP(quest)
    if not reward then return end
    if reward < xpNeeded then return L.QuestXPRemaining:format(reward, xpNeeded - reward), reward end
    if type(playerLevel) == "number" and playerLevel > 0 and playerLevel < math.huge then
        return L.QuestXPLevelUp:format(reward, playerLevel + 1), reward
    end
    return L.QuestXPReward:format(reward), reward
end

local function RankFromQuest(ranked, quest, destination, playerLevel)
    local measured = questMeasurements and questMeasurements[quest.id]
    local origin = measured and measured.objectiveMarker or destination and destination.target
    local distance = origin and addon.QuestLocation.GetDistanceMetric(C_Map, origin)
    if not distance then return ranked end
    local measurements = {}
    for _, candidate in ipairs(ranked) do
        if candidate.id ~= quest.id then
            local other = GetQuestDestination(candidate.id)
            local yards = other and other.target and distance(origin, other.target)
            if yards then measurements[candidate.id] = { yards = yards } end
        end
    end
    return addon.QuestPrioritizer.RankByDistance(ranked, measurements, nil, playerLevel, questJourneys)
end

local function SameAdditionalQuests(alternatives, zones, routes, rewards)
    if not shownQuests or #shownQuests ~= #alternatives + 1 then return false end
    for index, quest in ipairs(alternatives) do
        if shownQuests[index + 1] ~= quest or shownZones[index + 1] ~= zones[index + 1]
            or shownAlternativeRoutes[index] ~= routes[index] or shownRewards[index + 1] ~= rewards[index + 1] then
            return false
        end
    end
    return true
end

local function BuildRoutePreview(quest, destination, forecast, nextQuest)
    local target = destination and destination.target
    if not target then return end
    local measurements = questMeasurements or {}
    local first = measurements[quest.id]
    local preview = { { quest = quest, target = target, action = target.accessPoint and "access" or quest.readyToTurnIn and "turnIn" or "objective",
        yards = first and first.yards, current = true } }
    local distance = addon.QuestLocation.GetDistanceMetric(C_Map, target)
    local function AddStop(candidate, marker, action)
        if not marker or #preview == 3 then return end
        local previous = preview[#preview].target
        local yards = distance and distance(previous, marker)
        preview[#preview + 1] = { quest = candidate, target = marker, action = action, yards = yards }
    end
    if first and first.objectiveMarker then AddStop(quest, first.objectiveMarker, "objective") end
    if not (manualQuestID or objectiveLock) and outing and outing.stops[1]
        and outing.stops[1].quest.id == quest.id then
        for index = 2, #outing.stops do
            local candidate = outing.stops[index].quest
            local measured = measurements[candidate.id]
            AddStop(candidate, measured and measured.marker, candidate.readyToTurnIn and "turnIn" or "objective")
        end
    elseif not (manualQuestID or objectiveLock) and forecast and routeChains and routeChains[quest.id] then
        local chain = routeChains[quest.id]
        if not quest.readyToTurnIn then AddStop(quest, chain.finisher, "turnIn") end
        for _, stop in ipairs(chain.stops) do
            if stop.depth <= forecast.depth then
                AddStop({ id = stop.questID, title = stop.title }, stop, stop.action)
            end
        end
    elseif nextQuest and not (manualQuestID or objectiveLock) then
        local measured = measurements[nextQuest.id]
        AddStop(nextQuest, measured and measured.marker, "objective")
    end
    local journey = questJourneys and questJourneys[quest.id]
    if journey and journey.goals == 1 then
        if journey.exit then AddStop(quest, journey.exit, "access") end
        AddStop(quest, journey.finisher, "turnIn")
    end
    return preview
end

local function SameRoutePreview(a, b)
    if not a or not b then return a == b end
    if #a ~= #b then return false end
    for index, stop in ipairs(a) do
        local other = b[index]
        if stop.quest.id ~= other.quest.id or stop.quest.title ~= other.quest.title or stop.action ~= other.action
            or stop.target.mapID ~= other.target.mapID or stop.target.x ~= other.target.x or stop.target.y ~= other.target.y
            or math.floor(stop.yards or -1) ~= math.floor(other.yards or -1) then return false end
    end
    return true
end

local function SameAreaOverview(a, b)
    if not a or not b then return a == b end
    if a.zoneID ~= b.zoneID or a.objectives ~= b.objectives or a.turnIns ~= b.turnIns or #a.entries ~= #b.entries then
        return false
    end
    for index, entry in ipairs(a.entries) do
        local other = b.entries[index]
        if entry.quest ~= other.quest or entry.yards ~= other.yards or entry.objectives ~= other.objectives
            or entry.target.mapID ~= other.target.mapID or entry.target.x ~= other.target.x or entry.target.y ~= other.target.y then
            return false
        end
    end
    return true
end

local function RenderQuestList(ranked, routeQuest, routeNote, routeDetails, playerLevel, xpNeeded, nextQuest, forecast)
    local quest = ranked[1]
    local selectedQuestID = manualQuestID or (objectiveLock and objectiveLock.questID)
    if selectedQuestID then
        local manualQuest
        for _, candidate in ipairs(ranked) do
            if candidate.id == selectedQuestID then
                manualQuest = candidate
                break
            end
        end
        if manualQuest then
            quest = manualQuest
        else
            manualQuestID = nil
            heldQuest = nil
            objectiveLock = nil
        end
    end
    if not (manualQuestID or objectiveLock) and routeQuest then
        quest = routeQuest
    else
        routeNote = manualQuestID and (heldQuest and L.HeldQuestReason or L.ManualSelection)
            or DescribeRecommendation(quest, playerLevel)
        routeDetails = nil
    end
    local destination = GetQuestDestination(quest.id)
    if manualQuestID then ranked = RankFromQuest(ranked, quest, destination, playerLevel) end
    local alternatives = {}
    for _, candidate in ipairs(ranked) do
        if candidate.id ~= quest.id then
            alternatives[#alternatives + 1] = candidate
        end
    end
    local rewardText, reward = DescribeQuestXP(quest, xpNeeded, playerLevel)
    local rewards = {}
    if settings.showQuestXP and reward then
        rewards[1] = reward >= xpNeeded and L.QuestXPLevelUpShort or L.QuestXPReward:format(reward)
    end
    if reward and reward >= xpNeeded and type(playerLevel) == "number" and playerLevel > 0 and playerLevel < math.huge then
        if quest.readyToTurnIn and not manualQuestID and not (routeQuest and routeDetails) then
            routeNote = L.LevelUpOnTurnIn
        end
        local forecast = L.LevelUpForecast:format(reward, xpNeeded, playerLevel + 1)
        if nextQuest and quest == routeQuest then
            local title = nextQuest.title or L.QuestNumber:format(nextQuest.id)
            forecast = forecast .. "\n" .. L.LevelUpNextQuest:format(title)
        end
        routeDetails = routeDetails and (routeDetails .. "\n" .. forecast) or forecast
    elseif rewards[1] then
        routeDetails = routeDetails and (routeDetails .. "\n" .. rewardText) or rewardText
    end
    if routeNote == L.LevelUpOnTurnIn and rewards[1] == L.QuestXPLevelUpShort then routeNote = nil end
    local nearbyStops = GetNearbyStops(quest, destination, ranked, playerLevel)
    local approachStops
    local flightContext = addon.QuestLocation.GetFlightContext(C_Map, distanceMaps, flightRoutes)
    local zones, alternativeRoutes = {}, {}
    if destination then
        local nextStop = DescribeDestination(quest, destination)
        local measured = questMeasurements and questMeasurements[quest.id]
        if measured and measured.objectiveMarker then
            local marker = measured.marker
            nextStop = L.AccessRoute:format(marker.accessName or L.SavedAccess, marker.x * 100, marker.y * 100, measured.accessLeg)
                .. "\n" .. nextStop
        end
        local journey = questJourneys and questJourneys[quest.id]
        if journey then nextStop = nextStop .. "\n" .. L.JourneyEstimate:format(journey.totalYards, journey.returnYards) end
        routeDetails = routeDetails and (nextStop .. "\n" .. routeDetails) or nextStop
        if destination.zoneID ~= playerZoneID then zones[1] = destination.zoneName end
        local flightText = GetFlightHint(quest.id, destination, flightContext)
        if flightText then
            routeDetails = routeDetails .. "\n" .. flightText
        else
            approachStops = addon.QuestRoute.GetStopsOnApproach(C_Map, quest, ranked, questMeasurements, playerLevel)
        end
    end
    for index, alternative in ipairs(alternatives) do
        local fullReward, xp
        if settings.showQuestXP then
            fullReward, xp = DescribeQuestXP(alternative, xpNeeded, playerLevel)
            if xp then
                local format = xp >= xpNeeded and L.QuestXPCompactLevelUp or L.QuestXPReward
                rewards[index + 1] = format:format(xp)
            end
        end
        local other = GetQuestDestination(alternative.id)
        if other then
            local details = DescribeDestination(alternative, other)
            local measured = questMeasurements and questMeasurements[alternative.id]
            if measured and measured.objectiveMarker then
                local marker = measured.marker
                details = L.AccessRoute:format(marker.accessName or L.SavedAccess, marker.x * 100, marker.y * 100, measured.accessLeg)
                    .. "\n" .. details
            end
            local journey = questJourneys and questJourneys[alternative.id]
            if journey then details = details .. "\n" .. L.JourneyEstimate:format(journey.totalYards, journey.returnYards) end
            if other.zoneID ~= playerZoneID then zones[index + 1] = other.zoneName end
            local flight = GetFlightHint(alternative.id, other, flightContext)
            if flight then details = details .. "\n" .. flight end
            if fullReward and fullReward ~= rewards[index + 1] then details = details .. "\n" .. fullReward end
            alternativeRoutes[index] = details
        end
    end
    local rawObjectives = C_QuestLog.GetQuestObjectives and C_QuestLog.GetQuestObjectives(quest.id)
    local targets = GetObjectiveTargets(quest, rawObjectives)
    local hasMap = destination ~= nil
    local text = quest.readyToTurnIn and L.ReadyToTurnIn or (not targets and L.SeeQuestLog or "")
    local reasonLines = { L.WhyThisQuest }
    if heldQuest then reasonLines[#reasonLines + 1] = L.HeldQuestReason end
    if manualQuestID then
        reasonLines[#reasonLines + 1] = L.ManualQuestReason
    elseif objectiveLock then
        reasonLines[#reasonLines + 1] = L.ManualObjectiveReason
    else
        reasonLines[#reasonLines + 1] = L.AutomaticQuestReason
    end
    reasonLines[#reasonLines + 1] = addon.DescribeQuest(quest, questMeasurements and questMeasurements[quest.id])
    local fit = DescribeRecommendation(quest, playerLevel)
    if fit then reasonLines[#reasonLines + 1] = fit end
    if routeNote and routeNote ~= fit then reasonLines[#reasonLines + 1] = routeNote end
    if forecast then
        if routeDetails then reasonLines[#reasonLines + 1] = routeDetails end
    end
    local reason = table.concat(reasonLines, "\n")
    local preview = BuildRoutePreview(quest, destination, forecast, nextQuest)
    local area = addon.BuildAreaOverview(C_Map, Enum and Enum.UIMapType, playerZoneID, eligibleQuests,
        questMarkers or {}, distanceMaps, avoidedObjectives)
    if shownQuests and shownQuests[1] == quest and shownQuests[2] == alternatives[1]
        and shownQuests[3] == alternatives[2] and shownRouteNote == routeNote and shownRouteDetails == routeDetails
        and shownObjectives == text
        and SameAdditionalQuests(alternatives, zones, alternativeRoutes, rewards)
        and shownReason == reason
        and SameRoutePreview(shownRoutePreview, preview)
        and SameAreaOverview(shownAreaOverview, area)
        and shownMapAvailable == hasMap
        and SameObjectiveTargets(shownObjectiveTargets, targets)
        and zones[1] == shownZones[1] and zones[2] == shownZones[2] and zones[3] == shownZones[3]
        and alternativeRoutes[1] == shownAlternativeRoutes[1] and alternativeRoutes[2] == shownAlternativeRoutes[2]
        and rewards[1] == shownRewards[1] and rewards[2] == shownRewards[2] and rewards[3] == shownRewards[3]
        and SameNearbyStops(shownNearbyStops, nearbyStops) and SameApproachStops(shownApproachStops, approachStops) then
        return
    end

    shownObjectives = text
    shownReason = reason
    shownRoutePreview = preview
    shownAreaOverview = area
    shownMapAvailable = hasMap
    shownObjectiveTargets = targets
    shownQuests = { quest }
    for _, alternative in ipairs(alternatives) do shownQuests[#shownQuests + 1] = alternative end
    shownRouteNote, shownRouteDetails = routeNote, routeDetails
    shownZones, shownAlternativeRoutes = zones, alternativeRoutes
    shownNearbyStops = nearbyStops
    shownApproachStops = approachStops
    shownRewards = rewards
    tracker:Render(quest, text, skippedQuestIDs, alternatives, manualQuestID ~= nil,
        routeNote, routeDetails, zones, alternativeRoutes, nearbyStops, rewards, targets, hasMap, approachStops, reason, preview, area)
end

local function DescribeRoute(quest, route)
    local first = quest.readyToTurnIn and L.TurnIn or L.FinishAndTurnIn
    local lines = { ("%s %s"):format(first, quest.title or L.QuestNumber:format(quest.id)) }
    for index, title in ipairs(route.followUps) do
        lines[#lines + 1] = L.FollowUp:format(index, title)
        if index == route.depth then
            lines[#lines + 1] = L.SameVisit:format(route.original.title or L.QuestNumber:format(route.original.id))
        end
    end
    return table.concat(lines, "\n")
end

local function DescribeOuting(stops)
    local lines = { L.OutingOrder }
    for index, stop in ipairs(stops) do
        local quest = stop.quest
        local title = quest.title or L.QuestNumber:format(quest.id)
        lines[#lines + 1] = ("%d. %s %s"):format(index, quest.readyToTurnIn and L.TurnIn or L.WorkOn, title)
    end
    return table.concat(lines, "\n")
end

local function UpdateOuting(ranked, measurements, playerLevel, followUp)
    if manualQuestID or followUp then
        outing = nil
        return
    end
    if outing then
        local byID = {}
        for _, quest in ipairs(ranked) do byID[quest.id] = quest end
        local remaining = {}
        for _, stop in ipairs(outing.stops) do
            local quest = byID[stop.quest.id]
            if quest and measurements[quest.id] and not addon.QuestPrioritizer.IsLowPriority(quest, playerLevel) then
                local objectives = stop.objectiveIndex and C_QuestLog.GetQuestObjectives
                    and C_QuestLog.GetQuestObjectives(quest.id)
                local plannedObjective = objectives and objectives[stop.objectiveIndex]
                if (quest.readyToTurnIn == true) == stop.turnIn
                    and not (plannedObjective and plannedObjective.finished) then
                    stop.quest = quest
                    remaining[#remaining + 1] = stop
                else
                    outing.inProgress = true
                end
            elseif not C_QuestLog.IsOnQuest(stop.quest.id) then
                outing.inProgress = true
            end
        end
        outing.stops = remaining
        if outing.inProgress and #remaining > 0 then return outing end
    end

    outing = nil
    local plan = addon.QuestRoute.PlanOuting(C_Map, ranked, measurements, playerLevel, questJourneys)
    if not plan then return end
    local stops = {}
    for index, quest in ipairs(plan.stops) do
        local objectiveIndex
        if not quest.readyToTurnIn then
            local marker = measurements[quest.id].marker
            objectiveIndex = marker and marker.objectiveIndex
            if not objectiveIndex then
                local _, nextIndex = addon.QuestLog.GetNextObjective(C_QuestLog, quest.id)
                objectiveIndex = nextIndex
            end
        end
        stops[index] = { quest = quest, objectiveIndex = objectiveIndex, turnIn = quest.readyToTurnIn == true }
    end
    outing = { stops = stops, saving = plan.saving }
    return outing
end

local function UpdateDirection()
    local facing
    local inInstance = IsInInstance and IsInInstance()
    if not inInstance and GetPlayerFacing then
        facing = GetPlayerFacing()
    end
    local right, forward = addon.QuestLocation.GetRelativeDirection(activeDirection, facing)
    local active = shownQuests and shownQuests[1]
    local measurement = active and questMeasurements and questMeasurements[active.id]
    local arrived
    arrivalState, arrived = addon.TrackerState.Arrival(arrivalState, active, measurement)
    local status
    if inInstance then
        status = L.NavigationInstance
    elseif not measurement then
        status = active and next(avoidedObjectives[active.id] or {}) and L.NavigationAvoided or L.NavigationUnknown
    elseif arrived then
        status = active.readyToTurnIn and L.TurnInAction or L.NavigationArrived
    elseif not right then
        status = L.NavigationFacingUnavailable
    end
    if arrived or inInstance then right, forward = nil, nil end
    tracker:RenderDirection(right, forward, status, arrived and not inInstance)
    tracker:RenderRowDirections(facing)
end

local function TrackingVisible()
    return tracker:IsVisible() or settings.displayMode == "arrow"
end

local function UpdateDirectionTicker()
    if TrackingVisible() and settings.showDirectionArrow then
        UpdateDirection()
        local canRotate = GetPlayerFacing and (measurableQuestIDs or nearbyOffers)
            and not (IsInInstance and IsInInstance())
        if canRotate and not directionTicker then
            directionTicker = C_Timer.NewTicker(0.2, UpdateDirection)
        elseif not canRotate and directionTicker then
            directionTicker:Cancel()
            directionTicker = nil
        end
        return
    end

    if directionTicker then
        directionTicker:Cancel()
        directionTicker = nil
    end
    tracker:RenderDirection()
    tracker:RenderRowDirections()
end

local function UpdateDistances()
    if measurableQuestIDs and not refreshPending then
        local measurements
        measurements, objectiveDistances = addon.QuestLocation.MeasureQuests(C_Map, questMarkers, measurableQuestIDs,
            distanceMaps, previousObjectives, objectiveLock, avoidedObjectives)
        addon.TravelSupport.ApplyAccess(C_Map, eligibleQuests, measurements, distanceMaps, savedAccessPoints, passedAccessPoints)
        if objectiveLock then
            local targets = objectiveDistances[objectiveLock.questID]
            if not (targets and targets[objectiveLock.index]) then objectiveLock = nil end
        end
        previousObjectives = {}
        for id, measurement in pairs(measurements) do
            if not objectiveLock or objectiveLock.questID ~= id then
                previousObjectives[id] = measurement.marker.objectiveIndex
            end
        end
        questMeasurements = measurements
        local journeys, knownJourney = {}, false
        for _, quest in ipairs(eligibleQuests) do
            local measured = measurements[quest.id]
            local origin = measured and (measured.objectiveMarker or measured.marker)
            if origin and not quest.readyToTurnIn and integration.IsReady() then
                if turnInLocations[quest.id] == nil then
                    local finisher = addon.QuestieRoutes.GetOutdoorTurnInMarker(C_Map, Enum and Enum.UIMapType,
                        questTargetMaps or {}, quest.id, origin)
                    turnInLocations[quest.id] = finisher or false
                end
                local objectives = C_QuestLog.GetQuestObjectives and C_QuestLog.GetQuestObjectives(quest.id)
                journeys[quest.id] = addon.TravelSupport.BuildJourney(C_Map, quest, measured, objectives,
                    objectiveDistances[quest.id], turnInLocations[quest.id])
                if journeys[quest.id] then knownJourney = true end
            end
        end
        questJourneys = knownJourney and journeys or nil
        local ranked
        local playerLevel = UnitLevel and UnitLevel("player")
        ranked, distanceOrder = addon.QuestPrioritizer.RankByDistance(eligibleQuests, measurements, distanceOrder, playerLevel, questJourneys)
        local routeQuest, route = addon.QuestRoute.Recommend(C_Map, ranked, measurements, routeChains, playerLevel)
        local xpNeeded = addon.QuestLog.GetXPToNextLevel()
        local levelUpQuest, nextQuest
        if not manualQuestID then
            levelUpQuest, nextQuest = addon.QuestRoute.RecommendLevelUp(C_Map, ranked, measurements, playerLevel, xpNeeded)
        end
        local note, details
        local trip = UpdateOuting(ranked, measurements, playerLevel, levelUpQuest or routeQuest or objectiveLock)
        if levelUpQuest then
            routeQuest, note = levelUpQuest, L.LevelUpOnTurnIn
        elseif trip then
            routeQuest = trip.stops[1].quest
            local rounded = math.floor((trip.saving + 5) / 10) * 10
            if trip.inProgress then
                note = L.NextOutingStop
            elseif rounded > 0 then
                note = L.OutingSaving:format(rounded)
            else
                note = DescribeRecommendation(routeQuest, playerLevel)
            end
            details = DescribeOuting(trip.stops)
        elseif routeQuest then
            local rounded = math.floor((route.saving + 5) / 10) * 10
            note = L.FollowUpSaving:format(route.depth, rounded)
            details = DescribeRoute(routeQuest, route)
        end
        local forecast = not (trip or levelUpQuest) and route
        RenderQuestList(ranked, routeQuest, note, details, playerLevel, xpNeeded, nextQuest, forecast)
        UpdateMapMarker()
        local activeMeasurement = measurements[shownQuests[1].id]
        activeDirection = activeMeasurement and activeMeasurement.east and activeMeasurement or nil
        tracker:RenderDistances(measurements)
        UpdateDirectionTicker()
    end
end

local function UpdateDistanceTicker()
    if TrackingVisible() and measurableQuestIDs then
        UpdateDistances()
        if not distanceTicker then
            distanceTicker = C_Timer.NewTicker(1, UpdateDistances)
        end
    else
        if distanceTicker then
            distanceTicker:Cancel()
            distanceTicker = nil
        end
        activeDirection = nil
        UpdateDirectionTicker()
    end
end

local function RenderEmpty(message)
    eligibleQuests, shownQuests, distanceOrder, measurableQuestIDs = nil, nil, nil, nil
    outing = nil
    shownReason, shownRouteDetails, questMeasurements = nil, nil, nil
    arrivalState = nil
    questJourneys = nil
    objectiveLock, previousObjectives = nil, {}
    UpdateMapMarker()
    tracker:Render(nil, message, skippedQuestIDs)
    UpdateDistanceTicker()
end

local function UpdateQuestieTicker()
    if TrackingVisible() and integration.IsReady() and (settings.useQuestieKillLocations or settings.showQuestieOffers) then
        if not questieTicker then
            questieTicker = C_Timer.NewTicker(5, ScheduleRefresh)
            ScheduleRefresh()
        end
    elseif questieTicker then
        questieTicker:Cancel()
        questieTicker = nil
    end
end

local function SetTurnInMarkers(quests, mapType, targetMaps)
    for _, quest in ipairs(quests) do
        local marker, known
        if quest.readyToTurnIn then
            if integration.IsReady() then
                local name
                marker, known, name = addon.QuestieRoutes.GetOutdoorTurnInMarker(C_Map, mapType, targetMaps, quest.id)
                if marker then marker.turnInName = name end
            end
            if not known and (quest.special or not questMarkers[quest.id] or #questMarkers[quest.id] == 0) then
                marker = addon.QuestLocation.GetOutdoorWaypoint(C_Map, C_QuestLog, mapType, targetMaps, quest.id)
            end
        end
        if marker then
            marker.outdoorTurnIn = true
            questMarkers[quest.id] = { marker }
        elseif quest.special then
            questMarkers[quest.id] = nil
        end
    end
end

local function RefreshNearbyOffers(localMaps, targetMaps, mapType)
    local offers
    if settings.showQuestieOffers and tracker:IsVisible() and integration.IsReady() and UnitLevel then
        local level = UnitLevel("player")
        local active = shownQuests and GetQuestDestination(shownQuests[1].id)
        offers = integration.GetNearbyOffers(C_Map, C_QuestLog, localMaps, targetMaps, mapType,
            level, settings.questieOfferRadius, active and active.target)
    end
    nearbyOffers = offers and #offers > 0 and offers or nil
    if offers then
        local fresh
        seenRecommendedOffers, fresh = addon.TrackerState.NewOffers(seenRecommendedOffers, offers)
        tracker:SetNewOffers(fresh)
    end
    tracker:RenderNearbyOffers(nearbyOffers, settings.showQuestXP)
    UpdateDirectionTicker()
end

local function Refresh()
    refreshPending = false
    routeChains = nil
    turnInLocations, questJourneys = {}, nil
    questMeasurements = nil
    objectiveDistances = nil
    questDestinations = {}
    local quests = addon.QuestLog.Read(C_QuestLog)
    if quests and heldQuest and addon.TrackerState.HoldEnded(heldQuest, quests) then
        heldQuest, manualQuestID, objectiveLock, outing = nil, nil, nil, nil
        UpdateQuestLogButton()
    end
    tracker:SetProgress(addon.TrackerState.Progress(quests, C_QuestLog, skippedQuestIDs))
    if quests then
        local present = {}
        for _, quest in ipairs(quests) do
            present[quest.id] = true
            local avoided = avoidedObjectives[quest.id]
            if avoided then
                local goals = C_QuestLog.GetQuestObjectives and C_QuestLog.GetQuestObjectives(quest.id)
                for index in pairs(avoided) do
                    if quest.readyToTurnIn or (goals and (not goals[index] or goals[index].finished)) then avoided[index] = nil end
                end
            end
        end
        for id in pairs(avoidedObjectives) do if not present[id] then avoidedObjectives[id] = nil end end
    end
    if not quests then
        nearbyOffers = nil
        tracker:RenderNearbyOffers()
        RenderEmpty(L.QuestLogUnavailable)
        return
    end

    local _, localMaps, targetMaps
    local mapType = Enum and Enum.UIMapType
    questMarkers, _, localMaps, targetMaps, playerZoneID = addon.QuestLocation.GetLocalQuestMarkers(C_Map, C_QuestLog, mapType, true)
    questTargetMaps = targetMaps
    distanceMaps = localMaps
    if not questMarkers or (IsInInstance and IsInInstance()) then
        nearbyOffers = nil
        tracker:RenderNearbyOffers()
        RenderEmpty(L.OutdoorMapUnavailable)
        return
    end
    objectiveMarkers, killMarkers = nil, nil
    if localMaps and integration.IsReady() then
        objectiveMarkers, killMarkers = integration.GetObjectiveMarkers(quests, C_QuestLog, targetMaps,
            settings.useQuestieKillLocations)
        for id, markers in pairs(objectiveMarkers or {}) do
            questMarkers[id] = markers
        end
    end
    SetTurnInMarkers(quests, mapType, targetMaps)
    if manualQuestID then
        for _, quest in ipairs(quests) do
            if quest.id == manualQuestID and not quest.special then
                questMarkers[quest.id] = questMarkers[quest.id] or {}
                break
            end
        end
    end
    eligibleQuests = addon.QuestPrioritizer.Rank(quests, skippedQuestIDs, questMarkers)
    if #eligibleQuests == 0 then
        manualQuestID = nil
        heldQuest = nil
        RenderEmpty(L.NoMatchingQuests)
        RefreshNearbyOffers(localMaps, targetMaps, mapType)
        return
    end

    local measured = {}
    for _, quest in ipairs(eligibleQuests) do
        local markers = questMarkers and questMarkers[quest.id]
        if not quest.readyToTurnIn and not (objectiveMarkers and objectiveMarkers[quest.id]) then
            local destination = GetQuestDestination(quest.id)
            local target = destination and destination.questieTrigger
            if not target and (not markers or #markers == 0) then
                target = addon.QuestLocation.GetOutdoorWaypoint(C_Map, C_QuestLog, mapType, targetMaps, quest.id)
            end
            if target then
                target.objective = true
                markers = { target }
                questMarkers[quest.id] = markers
            end
        end
        if markers and #markers > 0 then
            measured[#measured + 1] = quest.id
        end
    end
    if #eligibleQuests > 1 and integration.IsReady() then
        routeChains = addon.QuestieRoutes.GetChains(C_Map, C_QuestLog, eligibleQuests, questMarkers,
            killMarkers, skippedQuestIDs, targetMaps)
    end
    measurableQuestIDs = #measured > 0 and measured or nil
    if not measurableQuestIDs then objectiveLock = nil end
    if not measurableQuestIDs or not TrackingVisible() then
        local level = UnitLevel and UnitLevel("player")
        local ranked = addon.QuestPrioritizer.RankByDistance(eligibleQuests, {}, nil, level)
        RenderQuestList(ranked, nil, nil, nil, level, addon.QuestLog.GetXPToNextLevel())
        UpdateMapMarker()
    end
    UpdateDistanceTicker()
    RefreshNearbyOffers(localMaps, targetMaps, mapType)
end

ScheduleRefresh = function()
    if not refreshPending then
        refreshPending = true
        C_Timer.After(0.1, Refresh)
    end
end

local function CanPinQuest(id)
    return type(id) == "number" and id > 0 and C_QuestLog and C_QuestLog.IsOnQuest
        and C_QuestLog.IsOnQuest(id) and not skippedQuestIDs[id]
        and not (C_QuestLog.IsFailed and C_QuestLog.IsFailed(id))
        and not (C_QuestLog.IsQuestDisabledForSession and C_QuestLog.IsQuestDisabledForSession(id))
        and (not addon.QuestLog.IsSpecialQuest(C_QuestLog, id) or (questMarkers and questMarkers[id] ~= nil))
end

UpdateQuestLogButton = function()
    if not questLogButton then return end
    local id = questLogDetails.questID
    local selected = id ~= nil and id == manualQuestID
    questLogButton:SetText(selected and L.ClearActiveQuest or L.SetActiveQuest)
    questLogButton:SetShown(selected or CanPinQuest(id) == true)
end

local function SelectQuest(questID)
    heldQuest = nil
    manualQuestID = questID
    objectiveLock = nil
    outing = nil
    UpdateQuestLogButton()
    ScheduleRefresh()
end

local function ToggleQuestHold()
    if heldQuest then SelectQuest(nil) return end
    local quest = shownQuests and shownQuests[1]
    if not quest then return end
    SelectQuest(quest.id)
    heldQuest = { id = quest.id, turnIn = quest.readyToTurnIn == true }
end

local function SelectObjective(index)
    local quest = shownQuests and shownQuests[1]
    local targets = quest and objectiveDistances and objectiveDistances[quest.id]
    if index and not (targets and targets[index]) then return end
    if index and avoidedObjectives[quest.id] then avoidedObjectives[quest.id][index] = nil end
    if not index or (objectiveLock and objectiveLock.questID == quest.id and objectiveLock.index == index) then
        objectiveLock = nil
    else
        objectiveLock = { questID = quest.id, index = index }
    end
    UpdateDistances()
end

local function AvoidObjective(index)
    local quest = shownQuests and shownQuests[1]
    local targets = quest and objectiveDistances and objectiveDistances[quest.id]
    if not (targets and targets[index]) then return end
    local avoided = avoidedObjectives[quest.id] or {}
    avoided[index] = not avoided[index] or nil
    avoidedObjectives[quest.id] = avoided
    if objectiveLock and objectiveLock.questID == quest.id and objectiveLock.index == index then objectiveLock = nil end
    previousObjectives[quest.id], outing = nil, nil
    UpdateDistances()
end

local function RestoreAvoidedObjectives()
    avoidedObjectives = {}
    outing = nil
    UpdateDistances()
end

local function AddQuestLogButton()
    if questLogButton or not (QuestMapFrame and QuestMapFrame.DetailsFrame and hooksecurefunc
        and QuestMapFrame_ShowQuestDetails) then return end
    questLogDetails = QuestMapFrame.DetailsFrame
    local back = questLogDetails.BackFrame and questLogDetails.BackFrame.BackButton
    questLogButton = CreateFrame("Button", nil, questLogDetails.BackFrame or questLogDetails, "UIPanelButtonTemplate")
    questLogButton:SetSize(165, 22)
    if back then
        questLogButton:SetPoint("LEFT", back, "RIGHT", 7, 0)
    else
        questLogButton:SetPoint("TOPRIGHT", -25, -14)
    end
    questLogButton:SetScript("OnClick", function()
        local id = questLogDetails.questID
        if id == manualQuestID then
            SelectQuest(nil)
        elseif CanPinQuest(id) then
            SelectQuest(id)
        end
    end)
    hooksecurefunc("QuestMapFrame_ShowQuestDetails", UpdateQuestLogButton)
    UpdateQuestLogButton()
end

local function AddQuestLogMenu()
    if not (Menu and Menu.ModifyMenu) then return end
    Menu.ModifyMenu("MENU_QUEST_MAP_LOG_TITLE", function(owner, menu)
        local id = owner and owner.questID
        if type(id) ~= "number" or id <= 0 or not (C_QuestLog and C_QuestLog.IsOnQuest
            and C_QuestLog.IsOnQuest(id)) then return end
        if id == manualQuestID then
            menu:CreateButton(L.ClearActiveQuest, function() SelectQuest(nil) end)
        elseif CanPinQuest(id) then
            menu:CreateButton(L.SetActiveQuest, function()
                if CanPinQuest(id) then SelectQuest(id) end
            end)
        end
    end)
end

local function AddQuestieTrackerMenu()
    if questieTrackerMenuHooked or not (integration.IsReady() and hooksecurefunc) then return end
    local ok, menu = pcall(QuestieLoader.ImportModule, QuestieLoader, "TrackerMenu")
    if not (ok and menu and type(menu.addShowInQuestLogOption) == "function") then return end
    hooksecurefunc(menu, "addShowInQuestLogOption", function(entries, quest)
        local id = quest and quest.Id
        if not CanPinQuest(id) then return end
        entries[#entries + 1] = {
            text = id == manualQuestID and L.ClearActiveQuest or L.SetActiveQuest,
            func = function()
                if id == manualQuestID then
                    SelectQuest(nil)
                elseif CanPinQuest(id) then
                    SelectQuest(id)
                end
            end,
        }
    end)
    questieTrackerMenuHooked = true
end

local function ConnectQuestie()
    AddQuestieTrackerMenu()
    local api = Questie and Questie.API
    if api and api.RegisterOnReady and not questieReadyRegistered then
        questieReadyRegistered = pcall(api.RegisterOnReady, function()
            AddQuestieTrackerMenu()
            UpdateQuestieTicker()
            ScheduleRefresh()
        end)
    end
end

GetQuestDestination = function(questID)
    local measurement = questMeasurements and questMeasurements[questID]
    local markers = questMarkers and questMarkers[questID]
    local marker = measurement and measurement.marker or markers and markers[1]
    if not measurement and avoidedObjectives[questID] then
        marker = nil
        for _, candidate in ipairs(markers or {}) do
            if not avoidedObjectives[questID][candidate.objectiveIndex] then marker = candidate break end
        end
        if not marker then return end
    end
    if not (C_Map and markers) then return end
    local cached = questDestinations[questID]
    if cached and cached.marker == marker then return cached end
    local mapType = Enum and Enum.UIMapType
    local ready = C_QuestLog and C_QuestLog.IsComplete and C_QuestLog.IsComplete(questID)
    local mapID, target, turnInName, questieTrigger
    if marker and ((objectiveMarkers and objectiveMarkers[questID]) or marker.objective or marker.outdoorTurnIn) then
        mapID = marker.mapID
        turnInName = marker.turnInName
    elseif integration.IsReady() then
        if ready and questTargetMaps and mapType then
            local turnIn, _, name = addon.QuestieRoutes.GetOutdoorTurnInMarker(C_Map, mapType, questTargetMaps, questID)
            mapID = turnIn and turnIn.mapID
            target = turnIn
            turnInName = name
        elseif not ready then
            local ambiguous, trigger
            mapID, ambiguous, trigger = addon.QuestieRoutes.GetObjectiveMap(C_Map, mapType, questID)
            if ambiguous and marker then mapID = marker.mapID end
            if trigger and addon.QuestLocation.IsOutdoorMap(C_Map, mapType, trigger.mapID, questTargetMaps) then
                local objective = addon.QuestLog.GetNextObjective(C_QuestLog, questID)
                if not objective or objective.type == "event" then questieTrigger = trigger end
            end
        end
    end
    mapID = mapID or addon.QuestLocation.GetDestinationMap(C_Map, mapType, questID, marker)
        or (marker and marker.mapID) or markers.mapID
    if not mapID then return end
    if marker then target = addon.QuestLocation.ProjectMarker(C_Map, marker, mapID) or marker end
    local zoneID, zoneName = addon.QuestLocation.GetZone(C_Map, mapType, target and target.mapID or mapID)
    local destination = {
        mapID = mapID, zoneID = zoneID, zoneName = zoneName, marker = marker, target = target,
        turnInName = turnInName, questieTrigger = questieTrigger,
    }
    questDestinations[questID] = destination
    return destination
end

local function OpenQuestMap(questID)
    if not (C_Map and C_Map.OpenWorldMap) then return end
    if InCombatLockdown and InCombatLockdown() then
        print(L.CombatMap)
        return
    end
    local destination = GetQuestDestination(questID)
    if not destination then return end
    local target = destination.target
    local mapID = target and target.mapID or destination.mapID
    local accepted = C_QuestLog and C_QuestLog.IsOnQuest and C_QuestLog.IsOnQuest(questID)
    local mapOpened = accepted and not (QuestMapFrame and QuestMapFrame.DetailsFrame)
    if mapOpened then C_Map.OpenWorldMap(mapID) end
    if not (accepted and addon.OpenQuestDetails(questID, mapID)) then
        if accepted and C_QuestLog.SetSelectedQuest then C_QuestLog.SetSelectedQuest(questID) end
        if not mapOpened then C_Map.OpenWorldMap(mapID) end
    end
    markedQuestID = questID
    addon.ShowQuestMapMarker(target, ClearMapMarker)
    if EventRegistry and EventRegistry.TriggerEvent then
        EventRegistry:TriggerEvent("MapCanvas.PingQuestID", questID)
    end
end

local function OpenOfferMap(id)
    local offer
    for _, candidate in ipairs(nearbyOffers or {}) do
        if candidate.id == id then offer = candidate break end
    end
    if not (offer and offer.marker and C_Map and C_Map.OpenWorldMap) then return end
    if InCombatLockdown and InCombatLockdown() then print(L.CombatMap) return end
    markedQuestID = nil
    C_Map.OpenWorldMap(offer.marker.mapID)
    addon.ShowQuestMapMarker(offer.marker, ClearMapMarker)
end

local function OpenRouteStop(stop)
    if not stop or not stop.target then return end
    if stop.quest and C_QuestLog.IsOnQuest(stop.quest.id) and stop.action ~= "accept" then
        local destination = GetQuestDestination(stop.quest.id)
        local target = destination and destination.target
        if target and target.mapID == stop.target.mapID and target.x == stop.target.x and target.y == stop.target.y then
            OpenQuestMap(stop.quest.id)
            return
        end
    end
    if InCombatLockdown and InCombatLockdown() then print(L.CombatMap) return end
    if not (C_Map and C_Map.OpenWorldMap) then return end
    markedQuestID = nil
    C_Map.OpenWorldMap(stop.target.mapID)
    addon.ShowQuestMapMarker(stop.target, ClearMapMarker)
end

local function ShowTargetReport(questID, isOffer)
    local measured = questMeasurements and questMeasurements[questID]
    if isOffer then
        for _, offer in ipairs(nearbyOffers or {}) do if offer.id == questID then measured = offer break end end
    end
    local function Point(point)
        if not addon.TravelSupport.ValidPoint(point) then return "unknown" end
        return ("map=%d x=%.6f y=%.6f objective=%s access=%s"):format(point.mapID, point.x, point.y,
            tostring(point.objectiveIndex or "unknown"), tostring(point.accessPoint == true))
    end
    local playerMap = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local position = playerMap and C_Map.GetPlayerMapPosition and C_Map.GetPlayerMapPosition(playerMap, "player")
    local player = position and { mapID = playerMap, x = position.x, y = position.y }
    local text = table.concat({ "FQN target position feedback", "reportedQuest=" .. tostring(questID),
        "kind=" .. (isOffer and "quest offer" or "accepted quest"),
        "navigationTarget: " .. Point(measured and measured.marker),
        "objectiveTarget: " .. Point(measured and (measured.objectiveMarker or measured.marker)),
        "playerPosition: " .. Point(player), "", L.ReportDescription, "", BuildDiagnostics() }, "\n")
    addon.ShowPositionReport(text)
end

local function OpenQuestMenu(owner, questID, isOffer)
    if not (questID and MenuUtil and MenuUtil.CreateContextMenu) then return end
    local measured = questMeasurements and questMeasurements[questID]
    local target = measured and (measured.objectiveMarker or measured.marker)
    local ready = C_QuestLog.IsComplete and C_QuestLog.IsComplete(questID)
    local key = target and (target.objectiveIndex or 0)
    local function Save(point, name)
        local metric = target and addon.QuestLocation.GetDistanceMetric(C_Map, target)
        if not (addon.TravelSupport.ValidPoint(point) and metric and metric(target, point)
            and addon.QuestLocation.IsOutdoorMap(C_Map, Enum and Enum.UIMapType, point.mapID, questTargetMaps)) then
            print(L.AccessUnavailable) return
        end
        if addon.TravelSupport.SaveAccess(savedAccessPoints, questID, target, point, name) then
            for _, quest in ipairs(eligibleQuests or {}) do
                if quest.id == questID then savedAccessPoints[questID][key].questTitle = quest.title break end
            end
            passedAccessPoints[questID .. ":" .. key] = nil
            outing = nil
            print(L.AccessSaved)
            ScheduleRefresh()
        end
    end
    MenuUtil.CreateContextMenu(owner, function(_, menu)
        menu:CreateTitle(L.AccessMenu)
        menu:SetScrollMode(260)
        menu:CreateButton(L.PositionReport, function() ShowTargetReport(questID, isOffer) end)
        if isOffer or ready or not target then return end
        menu:CreateButton(L.SaveAccessHere, function()
            if IsInInstance and IsInInstance() then print(L.AccessUnavailable) return end
            local mapID = C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
            local point = mapID and C_Map.GetPlayerMapPosition and C_Map.GetPlayerMapPosition(mapID, "player")
            Save(point and { mapID = mapID, x = point.x, y = point.y }, L.SavedAccess)
        end)
        local saved = addon.TravelSupport.GetAccess(savedAccessPoints, questID, target, C_Map)
        if saved then
            menu:CreateButton(L.ReuseAccess, function()
                passedAccessPoints[questID .. ":" .. key] = nil
                outing = nil
                ScheduleRefresh()
            end)
            menu:CreateButton(L.ClearAccess, function()
                savedAccessPoints[questID][key] = nil
                passedAccessPoints[questID .. ":" .. key] = nil
                outing = nil
                ScheduleRefresh()
            end)
        end
        local hints = addon.QuestieRoutes.GetAccessHints(C_Map, Enum and Enum.UIMapType, questTargetMaps or {}, questID, target)
        for _, hint in ipairs(hints) do
            local point, text = hint.point, hint.text
            menu:CreateButton(L.AccessHintMap:format(text), function() OpenRouteStop({ target = point }) end)
            menu:CreateButton(L.UseAccessHint:format(text), function() Save(point, text) end)
        end
    end)
end

local function ShowAccessManager()
    local function Title(id, stored)
        for _, quest in ipairs(eligibleQuests or {}) do if quest.id == id and quest.title then return quest.title end end
        local lookup = C_QuestLog and C_QuestLog.GetTitleForQuestID
        if type(lookup) ~= "function" then lookup = LibQuestieDB and LibQuestieDB.Quest and LibQuestieDB.Quest.name end
        if type(lookup) == "function" then
            local ok, name = pcall(lookup, id)
            if ok and type(name) == "string" and name ~= "" then return name end
        end
        return type(stored) == "string" and stored or L.QuestNumber:format(id)
    end
    local function Changed(entry)
        passedAccessPoints[entry.questID .. ":" .. entry.index] = nil
        outing = nil
        ScheduleRefresh()
    end
    addon.ShowAccessManager({
        list = function() return addon.TravelSupport.ListAccess(savedAccessPoints, C_Map, Title) end,
        map = function(entry) OpenRouteStop({ target = entry.point }) end,
        rename = function(entry, name)
            local changed = addon.TravelSupport.RenameAccess(savedAccessPoints, entry.questID, entry.index, name)
            if changed then Changed(entry) end
            return changed
        end,
        remove = function(entry)
            addon.TravelSupport.RemoveAccess(savedAccessPoints, entry.questID, entry.index)
            Changed(entry)
        end,
    })
end

local function LoadSkippedQuests()
    if type(ForeverQuestNavigatorCharacterDB) ~= "table" then
        ForeverQuestNavigatorCharacterDB = {}
    end
    local stored = ForeverQuestNavigatorCharacterDB.skippedQuests
    if type(stored) ~= "table" then stored = {} end
    ForeverQuestNavigatorCharacterDB.skippedQuests = stored
    skippedQuestIDs = stored
    for id, entry in pairs(stored) do
        if type(id) ~= "number" or id <= 0 or type(entry) ~= "table" or type(entry.quest) ~= "table"
            or entry.quest.id ~= id or type(entry.order) ~= "number" or not (entry.order >= 1 and entry.order < math.huge) then
            stored[id] = nil
        else
            skipOrder = math.max(skipOrder, entry.order)
        end
    end
end

local function SkipQuest(quest)
    if not quest or skippedQuestIDs[quest.id] then
        return
    end

    skipOrder = skipOrder + 1
    skippedQuestIDs[quest.id] = {
        quest = { id = quest.id, title = quest.title, level = quest.level, elite = quest.elite, group = quest.group },
        order = skipOrder,
    }
    if manualQuestID == quest.id then
        manualQuestID = nil
        heldQuest = nil
    end
    tracker:ShowUndoSkip(quest)
    ScheduleRefresh()
end

local function RestoreQuest(questID)
    skippedQuestIDs[questID] = nil
    ScheduleRefresh()
end

local function ResetSkips()
    for id in pairs(skippedQuestIDs) do skippedQuestIDs[id] = nil end
    skipOrder = 0
    ScheduleRefresh()
end

local function RegisterSettings()
    local category = Settings.RegisterVerticalLayoutCategory("Forever Quest Navigator")
    local function Section(name)
        Settings.RegisterInitializer(category, CreateSettingsListSectionHeaderInitializer(name))
    end
    Section(L.SettingsGeneral)
    local language = Settings.RegisterAddOnSetting(category, "FOREVERQUESTNAVIGATOR_LANGUAGE",
        "language", settings, Settings.VarType.String, L.Language, "auto")
    local languageOptions = Settings.CreateControlTextContainer()
    languageOptions:Add("auto", L.LanguageAutomatic)
    languageOptions:Add("deDE", "Deutsch")
    languageOptions:Add("enUS", "English")
    language:SetValueChangedCallback(function() print(L.LanguageReload) end)
    Settings.CreateDropdown(category, language, function() return languageOptions:GetData() end, L.LanguageHelp)
    Settings.RegisterInitializer(category, CreateSettingsButtonInitializer(L.OpenSession, L.OpenSession,
        ShowSession, L.OpenSessionHelp, true))
    Settings.RegisterInitializer(category, CreateSettingsButtonInitializer(L.AccessManager, L.AccessManager,
        ShowAccessManager, L.AccessManagerHelp, true))
    local function RefreshQuestieSettings()
        UpdateQuestieTicker()
        ScheduleRefresh()
    end
    Section(L.SettingsRecommendations)
    local killLocations = Settings.RegisterAddOnSetting(category, "FOREVERQUESTNAVIGATOR_QUESTIE_KILL_LOCATIONS",
        "useQuestieKillLocations", settings, Settings.VarType.Boolean, L.KillLocations, true)
    killLocations:SetValueChangedCallback(RefreshQuestieSettings)
    Settings.CreateCheckbox(category, killLocations,
        L.KillLocationsHelp)

    local nearbyOffers = Settings.RegisterAddOnSetting(category, "FOREVERQUESTNAVIGATOR_QUESTIE_NEARBY_OFFERS",
        "showQuestieOffers", settings, Settings.VarType.Boolean, L.Offers, true)
    nearbyOffers:SetValueChangedCallback(RefreshQuestieSettings)
    Settings.CreateCheckbox(category, nearbyOffers,
        L.OffersHelp)

    local radius = Settings.RegisterAddOnSetting(category, "FOREVERQUESTNAVIGATOR_QUESTIE_OFFER_RADIUS",
        "questieOfferRadius", settings, Settings.VarType.Number, L.OfferRadius, DEFAULT_OFFER_RADIUS)
    local radiusOptions = Settings.CreateSliderOptions(50, MAX_OFFER_RADIUS, 50)
    radiusOptions:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(value)
        return ("%.0f yd"):format(value)
    end)
    radius:SetValueChangedCallback(ScheduleRefresh)
    Settings.CreateSlider(category, radius, radiusOptions, L.OfferRadiusHelp)

    Section(L.SettingsNavigation)
    local direction = Settings.RegisterAddOnSetting(category, "FOREVERQUESTNAVIGATOR_SHOW_DIRECTION_ARROW",
        "showDirectionArrow", settings, Settings.VarType.Boolean, L.DirectionArrow, true)
    direction:SetValueChangedCallback(function()
        if not settings.showDirectionArrow and settings.displayMode == "arrow" then
            SetDisplayMode("full")
        else
            UpdateDirectionTicker()
        end
    end)
    Settings.CreateCheckbox(category, direction, L.DirectionArrowHelp)

    local screenArrow = Settings.RegisterAddOnSetting(category, "FOREVERQUESTNAVIGATOR_SHOW_SCREEN_ARROW",
        "showScreenArrow", settings, Settings.VarType.Boolean, L.ScreenArrow, true)
    screenArrow:SetValueChangedCallback(UpdateDirectionTicker)
    Settings.CreateCheckbox(category, screenArrow, L.ScreenArrowHelp)
    local lockNavigation = Settings.RegisterAddOnSetting(category, "FOREVERQUESTNAVIGATOR_LOCK_NAVIGATION_POSITION",
        "lockNavigationPosition", settings, Settings.VarType.Boolean, L.LockNavigationPosition, false)
    Settings.CreateCheckbox(category, lockNavigation, L.LockNavigationPositionHelp)
    local restoreObjectives = CreateSettingsButtonInitializer(L.RestoreAvoidedObjectives, L.RestoreAvoidedObjectives,
        RestoreAvoidedObjectives, L.RestoreAvoidedObjectivesHelp, true)
    Settings.RegisterInitializer(category, restoreObjectives)

    Section(L.SettingsAppearance)
    local detailMode = Settings.RegisterAddOnSetting(category, "FOREVERQUESTNAVIGATOR_DETAIL_MODE",
        "detailMode", settings, Settings.VarType.String, L.DetailMode, "detailed")
    local detailOptions = Settings.CreateControlTextContainer()
    detailOptions:Add("detailed", L.DetailDetailed)
    detailOptions:Add("compact", L.DetailCompact)
    detailMode:SetValueChangedCallback(function()
        tracker:UpdateListSettings()
        addon.RefreshAppearancePreview()
    end)
    Settings.CreateDropdown(category, detailMode, function() return detailOptions:GetData() end, L.DetailModeHelp)
    Settings.RegisterInitializer(category, CreateSettingsButtonInitializer(L.AppearancePreview, L.AppearancePreview,
        function() addon.ShowAppearancePreview(settings) end, L.AppearancePreviewHelp, true))
    local questXP = Settings.RegisterAddOnSetting(category, "FOREVERQUESTNAVIGATOR_SHOW_QUEST_XP",
        "showQuestXP", settings, Settings.VarType.Boolean, L.ShowQuestXP, true)
    questXP:SetValueChangedCallback(function() ScheduleRefresh() addon.RefreshAppearancePreview() end)
    Settings.CreateCheckbox(category, questXP, L.ShowQuestXPHelp)

    local opacity = Settings.RegisterAddOnSetting(category, "FOREVERQUESTNAVIGATOR_TRACKER_OPACITY",
        "opacityPercent", settings, Settings.VarType.Number, L.Opacity, DEFAULT_OPACITY)
    local opacityOptions = Settings.CreateSliderOptions(0, 100, 5)
    opacityOptions:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(value)
        return ("%.0f%%"):format(value)
    end)
    opacity:SetValueChangedCallback(function() tracker:UpdateOpacity() addon.RefreshAppearancePreview() end)
    Settings.CreateSlider(category, opacity, opacityOptions, L.OpacityHelp)
    local resize = Settings.RegisterAddOnSetting(category, "FOREVERQUESTNAVIGATOR_ALLOW_TRACKER_RESIZE",
        "allowTrackerResize", settings, Settings.VarType.Boolean, L.AllowTrackerResize, false)
    resize:SetValueChangedCallback(function() tracker:UpdateResizeGrip() end)
    Settings.CreateCheckbox(category, resize, L.AllowTrackerResizeHelp)
    local lockTracker = Settings.RegisterAddOnSetting(category, "FOREVERQUESTNAVIGATOR_LOCK_TRACKER_POSITION",
        "lockTrackerPosition", settings, Settings.VarType.Boolean, L.LockTrackerPosition, false)
    Settings.CreateCheckbox(category, lockTracker, L.LockTrackerPositionHelp)
    local font = Settings.RegisterAddOnSetting(category, "FOREVERQUESTNAVIGATOR_FONT_PERCENT",
        "fontPercent", settings, Settings.VarType.Number, L.FontSize, 100)
    font:SetValueChangedCallback(function() tracker:UpdateFontSize() addon.RefreshAppearancePreview() end)
    local fontOptions = Settings.CreateSliderOptions(80, 140, 10)
    fontOptions:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(value)
        return ("%.0f%%"):format(value)
    end)
    Settings.CreateSlider(category, font, fontOptions, L.FontSizeHelp)
    local function RegisterRowCount(key, variable, name, defaultValue)
        local count = Settings.RegisterAddOnSetting(category, variable, key, settings, Settings.VarType.Number, name, defaultValue)
        count:SetValueChangedCallback(function() tracker:UpdateListSettings() end)
        local options = Settings.CreateSliderOptions(2, 5, 1)
        options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(value) return tostring(value) end)
        Settings.CreateSlider(category, count, options, L.ListRowsHelp)
        return count
    end
    local acceptedRows = RegisterRowCount("acceptedRows", "FOREVERQUESTNAVIGATOR_ACCEPTED_ROWS", L.AcceptedRows, 2)
    local offerRows = RegisterRowCount("offerRows", "FOREVERQUESTNAVIGATOR_OFFER_ROWS", L.OfferRows, 3)
    local reset = CreateSettingsButtonInitializer(L.ResetPositions, L.ResetPositions, function()
        tracker:ResetPositions()
    end, L.ResetPositionsHelp, true)
    Settings.RegisterInitializer(category, reset)
    local appearance = CreateSettingsButtonInitializer(L.ResetAppearance, L.ResetAppearance, function()
        detailMode:SetValue("detailed")
        opacity:SetValue(DEFAULT_OPACITY)
        font:SetValue(100)
        acceptedRows:SetValue(2)
        offerRows:SetValue(3)
        resize:SetValue(false)
        lockTracker:SetValue(false)
        lockNavigation:SetValue(false)
        tracker:ResetAppearance()
        ScheduleRefresh()
    end, L.ResetAppearanceHelp, true)
    Settings.RegisterInitializer(category, appearance)
    Section(L.SettingsDiagnostics)
    Settings.RegisterInitializer(category, CreateSettingsButtonInitializer(L.OpenDiagnostics, L.OpenDiagnostics,
        ShowDiagnostics, L.OpenDiagnosticsHelp, true))
    Settings.RegisterAddOnCategory(category)
    return category
end

SetDisplayMode = function(mode)
    local wasArrowOnly = settings.displayMode == "arrow"
    settings.displayMode = mode
    settings.hidden = mode ~= "full"
    local wasShown = tracker:IsShown()
    tracker:SetShown(mode == "full")
    if wasShown == tracker:IsShown() then
        UpdateDistanceTicker()
        UpdateQuestieTicker()
    end
    if mode == "full" and wasArrowOnly then ScheduleRefresh() end
end

local function CycleDisplayMode()
    if settings.displayMode == "full" then
        SetDisplayMode(settings.showDirectionArrow and "arrow" or "off")
    elseif settings.displayMode == "arrow" then
        SetDisplayMode("off")
    else
        SetDisplayMode("full")
    end
end

local function ToggleTracker()
    SetDisplayMode(tracker:IsShown() and "off" or "full")
end

local function OpenSettings()
    Settings.OpenToCategory(settingsCategory:GetID())
end

local function AddonLoaded(name)
    if name == addonName and not tracker then
        settings = ForeverQuestNavigatorDB
        if type(settings) ~= "table" then
            settings = {}
            ForeverQuestNavigatorDB = settings
        end
        if settings.language ~= "deDE" and settings.language ~= "enUS" then settings.language = "auto" end
        addon.SetLanguage(settings.language)
        settings.x = type(settings.x) == "number" and math.abs(settings.x) < math.huge and settings.x or 0
        settings.y = type(settings.y) == "number" and math.abs(settings.y) < math.huge and settings.y or 140
        if settings.displayMode ~= "full" and settings.displayMode ~= "arrow" and settings.displayMode ~= "off" then
            settings.displayMode = settings.hidden == true and "off" or "full"
        end
        settings.collapsed = settings.collapsed == true
        settings.detailMode = settings.detailMode == "compact" and "compact" or "detailed"
        settings.areaOverviewExpanded = settings.areaOverviewExpanded == true
        settings.allowTrackerResize = settings.allowTrackerResize == true
        settings.lockTrackerPosition = settings.lockTrackerPosition == true
        settings.lockNavigationPosition = settings.lockNavigationPosition == true
        local font = settings.fontPercent
        settings.fontPercent = type(font) == "number" and font >= 80 and font <= 140 and font or 100
        local function RowCount(value, default)
            if type(value) ~= "number" or not (value >= 2 and value <= 5) then return default end
            return math.floor(value)
        end
        settings.acceptedRows = RowCount(settings.acceptedRows, 2)
        settings.offerRows = RowCount(settings.offerRows, 3)
        settings.includeElite = nil
        settings.currentZoneOnly = nil
        settings.useQuestieKillLocations = settings.useQuestieKillLocations ~= false
        settings.showQuestieOffers = settings.showQuestieOffers ~= false
        settings.showTurnInStar = nil
        local radius = settings.questieOfferRadius
        settings.questieOfferRadius = type(radius) == "number" and radius >= 50
            and radius <= MAX_OFFER_RADIUS and radius or DEFAULT_OFFER_RADIUS
        settings.showDirectionArrow = settings.showDirectionArrow ~= false
        if settings.displayMode == "arrow" and not settings.showDirectionArrow then settings.displayMode = "full" end
        settings.hidden = settings.displayMode ~= "full"
        settings.showScreenArrow = settings.showScreenArrow ~= false
        local arrowX, arrowY = settings.screenArrowX, settings.screenArrowY
        if type(arrowX) ~= "number" or not (math.abs(arrowX) < math.huge)
            or type(arrowY) ~= "number" or not (math.abs(arrowY) < math.huge) then
            settings.screenArrowX, settings.screenArrowY = nil, nil
        end
        settings.showQuestXP = settings.showQuestXP ~= false
        settings.sortByDistance = nil
        local opacity = settings.opacityPercent
        settings.opacityPercent = type(opacity) == "number" and opacity >= 0 and opacity <= 100 and opacity or DEFAULT_OPACITY
        LoadSkippedQuests()
        local character = ForeverQuestNavigatorCharacterDB
        savedAccessPoints = type(character.accessPoints) == "table" and character.accessPoints or {}
        character.accessPoints = savedAccessPoints
        session = addon.Session.New(character.session, SessionTime())
        character.session = session.data
        if type(character.confirmedFlightPoints) ~= "table" then character.confirmedFlightPoints = {} end
        confirmedFlightPoints = character.confirmedFlightPoints
        if type(character.flightRoutes) ~= "table" then character.flightRoutes = {} end
        flightRoutes = character.flightRoutes

        settingsCategory = RegisterSettings()
        local version = C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(addonName, "Version")
        tracker = addon.CreateQuestTracker(settings, {
            skip = SkipQuest,
            resetSkips = ResetSkips,
            restore = RestoreQuest,
            resumeAutoSelect = function() SelectQuest(nil) end,
            toggleQuestHold = ToggleQuestHold,
            getQuestHold = function() return heldQuest ~= nil end,
            openSettings = OpenSettings,
            openQuestMap = OpenQuestMap,
            openQuestMenu = OpenQuestMenu,
            openOfferMap = OpenOfferMap,
            openRouteStop = OpenRouteStop,
            selectObjective = SelectObjective,
            avoidObjective = AvoidObjective,
            restoreAvoidedObjectives = RestoreAvoidedObjectives,
            hideTracker = function() SetDisplayMode("off") end,
            refreshMeasurements = UpdateDistances,
        }, version)
        tracker:UpdateListSettings()
        AddQuestLogMenu()
        local function UpdateTrackers()
            UpdateDistanceTicker()
            UpdateQuestieTicker()
        end
        tracker:HookScript("OnShow", UpdateTrackers)
        tracker:HookScript("OnHide", UpdateTrackers)

        events:RegisterEvent("PLAYER_ENTERING_WORLD")
        events:RegisterEvent("PLAYER_LEVEL_UP")
        events:RegisterEvent("PLAYER_XP_UPDATE")
        events:RegisterEvent("PLAYER_LOGOUT")
        events:RegisterEvent("QUEST_LOG_UPDATE")
        events:RegisterEvent("QUEST_LOG_CRITERIA_UPDATE")
        events:RegisterEvent("QUEST_WATCH_UPDATE")
        events:RegisterEvent("QUEST_DATA_LOAD_RESULT")
        events:RegisterEvent("QUEST_ACCEPTED")
        events:RegisterEvent("QUEST_REMOVED")
        events:RegisterEvent("QUEST_TURNED_IN")
        events:RegisterEvent("QUEST_POI_UPDATE")
        events:RegisterEvent("QUEST_WATCH_LIST_CHANGED")
        events:RegisterEvent("PLAYER_MAP_CHANGED")
        events:RegisterEvent("ZONE_CHANGED_NEW_AREA")
        events:RegisterEvent("TAXI_NODE_STATUS_CHANGED")
        events:RegisterEvent("TAXIMAP_OPENED")
        events:RegisterEvent("TAXIMAP_CLOSED")

        SLASH_FOREVERQUESTNAVIGATOR1 = "/fqn"
        SlashCmdList.FOREVERQUESTNAVIGATOR = function(message)
            local command = message:match("^%s*(.-)%s*$"):lower()
            if command == "status" then
                print("FQN | Questie: " .. addon.ReadQuestieStatus(C_AddOns))
            elseif command == "debug" then
                ShowDiagnostics()
            elseif command == "session" then
                ShowSession()
            elseif command == "access" then
                ShowAccessManager()
            elseif command == "session reset" then
                session = addon.Session.New(nil, SessionTime())
                ForeverQuestNavigatorCharacterDB.session = session.data
                CaptureSessionXP()
                ShowSession()
            elseif command == "report" then
                local quest = shownQuests and shownQuests[1]
                if quest then ShowTargetReport(quest.id) end
            elseif command == "settings" then
                OpenSettings()
            elseif command == "" then
                ToggleTracker()
            else
                print(L.SlashHelp)
            end
        end

        ConnectQuestie()
        ScheduleRefresh()
    elseif tracker and name == "Questie" then
        ConnectQuestie()
    end
    if tracker then AddQuestLogButton() end
end

events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(_, event, arg, rewardXP)
    if session and (event == "PLAYER_XP_UPDATE" or event == "PLAYER_ENTERING_WORLD" or event == "QUEST_TURNED_IN") then
        CaptureSessionXP()
    end
    if session and event == "QUEST_TURNED_IN" then
        local title
        for _, quest in ipairs(eligibleQuests or {}) do if quest.id == arg then title = quest.title break end end
        session:TurnIn(arg, title, rewardXP)
        session:Save(SessionTime())
    end
    if session and event == "PLAYER_LOGOUT" then session:Save(SessionTime()) return end
    if event == "ADDON_LOADED" then
        AddonLoaded(arg)
    elseif event == "PLAYER_XP_UPDATE" and measurableQuestIDs then
        if TrackingVisible() then UpdateDistances() end
    else
        if event == "PLAYER_LEVEL_UP" then
            outing, distanceOrder = nil, nil
        end
        if event == "PLAYER_ENTERING_WORLD" then
            AddQuestLogButton()
            if not minimapButton then
                minimapButton = addon.CreateMinimapButton(settings, CycleDisplayMode, OpenSettings)
            end
        end
        if event == "TAXIMAP_OPENED" then taxiMapOpen = true end
        if event == "TAXIMAP_CLOSED" or event == "PLAYER_ENTERING_WORLD" then taxiMapOpen = false end
        if taxiMapOpen and (event == "TAXIMAP_OPENED" or event == "TAXI_NODE_STATUS_CHANGED") then
            ConfirmFlightPoints()
        end
        if event == "QUEST_REMOVED" then
            skippedQuestIDs[arg] = nil
            if manualQuestID == arg then
                manualQuestID = nil
                heldQuest = nil
            end
        end
        UpdateQuestLogButton()
        ScheduleRefresh()
    end
end)
