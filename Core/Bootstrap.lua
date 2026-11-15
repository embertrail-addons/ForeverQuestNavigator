local addonName, addon = ...
local L = addon.L
local events = CreateFrame("Frame")
local tracker, settings, settingsCategory
local minimapButton
local manualQuestID
local skippedQuestIDs = {}
local skipOrder = 0
local refreshPending = false
local questMarkers, measurableQuestIDs, distanceTicker, distanceMaps
local questMeasurements, questTargetMaps
local playerZoneID, questDestinations, shownZones = nil, {}, {}
local activeDirection, directionTicker
local eligibleQuests, shownQuests, distanceOrder
local integration = addon.QuestieIntegration
local objectiveMarkers, killMarkers, questieTicker, questieReadyRegistered
local nearbyOffers
local routeChains, shownRouteNote, shownRouteDetails
local outing
local ScheduleRefresh
local GetQuestDestination
local markedQuestID
local MINIMUM_FLIGHT_HINT_DISTANCE = 1500
local shownAlternativeRoutes = {}
local shownNearbyStops
local confirmedFlightPoints, flightRoutes, taxiMapOpen

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
    local map = C_Map.GetMapInfo(destination.target and destination.target.mapID or destination.mapID)
    local place = map and map.name or destination.zoneName
    local target = destination.target
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
        if distance then return distance .. " · " .. L.TurnInStatus end
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

local function GetNearbyStops(quest, destination, ranked, playerLevel)
    if not (destination and destination.zoneID and destination.target) then return end
    local distance = addon.QuestLocation.GetDistanceMetric(C_Map, destination.target)
    if not distance then return end
    local stops
    for _, candidate in ipairs(ranked) do
        if candidate.id ~= quest.id and not addon.QuestPrioritizer.IsHighLevel(candidate, playerLevel) then
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

local function RenderQuestList(ranked, routeQuest, routeNote, routeDetails, playerLevel)
    local quest = ranked[1]
    if manualQuestID then
        local manualQuest
        for _, candidate in ipairs(ranked) do
            if candidate.id == manualQuestID then
                manualQuest = candidate
                break
            end
        end
        if manualQuest then
            quest = manualQuest
        else
            manualQuestID = nil
        end
    end
    if not manualQuestID and routeQuest then
        quest = routeQuest
    else
        routeNote = not manualQuestID and DescribeRecommendation(quest, playerLevel) or nil
        routeDetails = nil
    end
    local alternatives = {}
    for _, candidate in ipairs(ranked) do
        if candidate.id ~= quest.id then
            alternatives[#alternatives + 1] = candidate
            if #alternatives == 2 then break end
        end
    end
    local destination = GetQuestDestination(quest.id)
    local nearbyStops = GetNearbyStops(quest, destination, ranked, playerLevel)
    local flightContext = addon.QuestLocation.GetFlightContext(C_Map, distanceMaps, flightRoutes)
    local zones, alternativeRoutes = {}, {}
    if destination then
        local nextStop = DescribeDestination(quest, destination)
        routeDetails = routeDetails and (nextStop .. "\n" .. routeDetails) or nextStop
        if destination.zoneID ~= playerZoneID then zones[1] = destination.zoneName end
        local flightText = GetFlightHint(quest.id, destination, flightContext)
        if flightText then routeDetails = routeDetails .. "\n" .. flightText end
    end
    for index, alternative in ipairs(alternatives) do
        local other = GetQuestDestination(alternative.id)
        if other then
            local details = DescribeDestination(alternative, other)
            if other.zoneID ~= playerZoneID then zones[index + 1] = other.zoneName end
            local flight = GetFlightHint(alternative.id, other, flightContext)
            if flight then details = details .. "\n" .. flight end
            alternativeRoutes[index] = details
        end
    end
    if shownQuests and shownQuests[1] == quest and shownQuests[2] == alternatives[1]
        and shownQuests[3] == alternatives[2] and shownRouteNote == routeNote and shownRouteDetails == routeDetails
        and zones[1] == shownZones[1] and zones[2] == shownZones[2] and zones[3] == shownZones[3]
        and alternativeRoutes[1] == shownAlternativeRoutes[1] and alternativeRoutes[2] == shownAlternativeRoutes[2]
        and SameNearbyStops(shownNearbyStops, nearbyStops) then
        return
    end

    local text = L.ReadyToTurnIn
    if not quest.readyToTurnIn then
        text = addon.QuestLog.GetObjectiveText(C_QuestLog, quest.id) or L.SeeQuestLog
    end
    shownQuests = { quest, alternatives[1], alternatives[2] }
    shownRouteNote, shownRouteDetails = routeNote, routeDetails
    shownZones, shownAlternativeRoutes = zones, alternativeRoutes
    shownNearbyStops = nearbyStops
    tracker:Render(quest, text, skippedQuestIDs, alternatives, manualQuestID ~= nil,
        routeNote, routeDetails, zones, alternativeRoutes, nearbyStops)
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
            if quest and measurements[quest.id] and not addon.QuestPrioritizer.IsHighLevel(quest, playerLevel) then
                local _, objectiveIndex = addon.QuestLog.GetNextObjective(C_QuestLog, quest.id)
                if (quest.readyToTurnIn == true) == stop.turnIn
                    and (not objectiveIndex or not stop.objectiveIndex or objectiveIndex == stop.objectiveIndex) then
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
    local plan = addon.QuestRoute.PlanOuting(C_Map, ranked, measurements, playerLevel)
    if not plan then return end
    local stops = {}
    for index, quest in ipairs(plan.stops) do
        local _, objectiveIndex = addon.QuestLog.GetNextObjective(C_QuestLog, quest.id)
        stops[index] = { quest = quest, objectiveIndex = objectiveIndex, turnIn = quest.readyToTurnIn == true }
    end
    outing = { stops = stops, saving = plan.saving }
    return outing
end

local function UpdateDirection()
    local facing
    if not (IsInInstance and IsInInstance()) then
        facing = GetPlayerFacing()
    end
    tracker:RenderDirection(addon.QuestLocation.GetRelativeDirection(activeDirection, facing))
    tracker:RenderRowDirections(facing)
end

local function UpdateDirectionTicker()
    if tracker:IsVisible() and settings.showDirectionArrow and (measurableQuestIDs or nearbyOffers) and GetPlayerFacing
        and not (IsInInstance and IsInInstance()) then
        UpdateDirection()
        if not directionTicker then
            directionTicker = C_Timer.NewTicker(0.2, UpdateDirection)
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
        local measurements = addon.QuestLocation.MeasureQuests(C_Map, questMarkers, measurableQuestIDs, distanceMaps)
        questMeasurements = measurements
        local ranked
        local playerLevel = UnitLevel and UnitLevel("player")
        ranked, distanceOrder = addon.QuestPrioritizer.RankByDistance(eligibleQuests, measurements, distanceOrder, playerLevel)
        local routeQuest, route = addon.QuestRoute.Recommend(C_Map, ranked, measurements, routeChains, playerLevel)
        local note, details
        local trip = UpdateOuting(ranked, measurements, playerLevel, routeQuest)
        if trip then
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
        RenderQuestList(ranked, routeQuest, note, details, playerLevel)
        UpdateMapMarker()
        local activeMeasurement = measurements[shownQuests[1].id]
        activeDirection = activeMeasurement and activeMeasurement.east and activeMeasurement or nil
        tracker:RenderDistances(measurements)
        UpdateDirectionTicker()
    end
end

local function UpdateDistanceTicker()
    if tracker:IsVisible() and measurableQuestIDs then
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
    UpdateMapMarker()
    tracker:Render(nil, message, skippedQuestIDs)
    UpdateDistanceTicker()
end

local function UpdateQuestieTicker()
    if tracker:IsVisible() and integration.IsReady() and (settings.useQuestieKillLocations or settings.showQuestieOffers) then
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

local function Refresh()
    refreshPending = false
    routeChains = nil
    questMeasurements = nil
    questDestinations = {}
    local quests = addon.QuestLog.Read(C_QuestLog)
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
    local offers
    objectiveMarkers, killMarkers = nil, nil
    if localMaps and integration.IsReady() then
        if settings.showQuestieOffers and tracker:IsVisible() and UnitLevel then
            offers = integration.GetNearbyOffers(C_Map, C_QuestLog, localMaps,
                UnitLevel("player"), settings.questieOfferRadius)
        end
        objectiveMarkers, killMarkers = integration.GetObjectiveMarkers(quests, C_QuestLog, targetMaps,
            settings.useQuestieKillLocations)
        for id, markers in pairs(objectiveMarkers or {}) do
            questMarkers[id] = markers
        end
    end
    nearbyOffers = offers and #offers > 0 and offers or nil
    tracker:RenderNearbyOffers(nearbyOffers)
    SetTurnInMarkers(quests, mapType, targetMaps)
    eligibleQuests = addon.QuestPrioritizer.Rank(quests, skippedQuestIDs, questMarkers)
    if #eligibleQuests == 0 then
        manualQuestID = nil
        RenderEmpty(L.NoMatchingQuests)
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
    if not measurableQuestIDs or not tracker:IsVisible() then
        RenderQuestList(eligibleQuests, nil, nil, nil, UnitLevel and UnitLevel("player"))
        UpdateMapMarker()
    end
    UpdateDistanceTicker()
end

ScheduleRefresh = function()
    if not refreshPending then
        refreshPending = true
        C_Timer.After(0.1, Refresh)
    end
end

local function ConnectQuestie()
    local api = Questie and Questie.API
    if api and api.RegisterOnReady and not questieReadyRegistered then
        questieReadyRegistered = pcall(api.RegisterOnReady, function()
            UpdateQuestieTicker()
            ScheduleRefresh()
        end)
    end
end

local function SelectQuest(questID)
    manualQuestID = questID
    outing = nil
    ScheduleRefresh()
end

GetQuestDestination = function(questID)
    local measurement = questMeasurements and questMeasurements[questID]
    local markers = questMarkers and questMarkers[questID]
    local marker = measurement and measurement.marker or markers and markers[1]
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
    if C_QuestLog and C_QuestLog.SetSelectedQuest and C_QuestLog.IsOnQuest and C_QuestLog.IsOnQuest(questID) then
        C_QuestLog.SetSelectedQuest(questID)
    end
    local target = destination.target
    C_Map.OpenWorldMap(target and target.mapID or destination.mapID)
    if EventRegistry and EventRegistry.TriggerEvent then
        EventRegistry:TriggerEvent("MapCanvas.PingQuestID", questID)
    end
    markedQuestID = questID
    addon.ShowQuestMapMarker(target, ClearMapMarker)
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
        quest = { id = quest.id, title = quest.title, level = quest.level }, order = skipOrder,
    }
    if manualQuestID == quest.id then
        manualQuestID = nil
    end
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
    local language = Settings.RegisterAddOnSetting(category, "FOREVERQUESTNAVIGATOR_LANGUAGE",
        "language", settings, Settings.VarType.String, L.Language, "auto")
    local languageOptions = Settings.CreateControlTextContainer()
    languageOptions:Add("auto", L.LanguageAutomatic)
    languageOptions:Add("deDE", "Deutsch")
    languageOptions:Add("enUS", "English")
    language:SetValueChangedCallback(function() print(L.LanguageReload) end)
    Settings.CreateDropdown(category, language, languageOptions:GetData(), L.LanguageHelp)
    local function RefreshQuestieSettings()
        UpdateQuestieTicker()
        ScheduleRefresh()
    end
    local killLocations = Settings.RegisterAddOnSetting(category, "FOREVERQUESTNAVIGATOR_QUESTIE_KILL_LOCATIONS",
        "useQuestieKillLocations", settings, Settings.VarType.Boolean, L.KillLocations, true)
    killLocations:SetValueChangedCallback(RefreshQuestieSettings)
    Settings.CreateCheckbox(category, killLocations,
        L.KillLocationsHelp)

    local nearbyOffers = Settings.RegisterAddOnSetting(category, "FOREVERQUESTNAVIGATOR_QUESTIE_NEARBY_OFFERS",
        "showQuestieOffers", settings, Settings.VarType.Boolean, L.Offers, false)
    nearbyOffers:SetValueChangedCallback(RefreshQuestieSettings)
    Settings.CreateCheckbox(category, nearbyOffers,
        L.OffersHelp)

    local radius = Settings.RegisterAddOnSetting(category, "FOREVERQUESTNAVIGATOR_QUESTIE_OFFER_RADIUS",
        "questieOfferRadius", settings, Settings.VarType.Number, L.OfferRadius, 200)
    local radiusOptions = Settings.CreateSliderOptions(50, 500, 50)
    radiusOptions:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(value)
        return ("%.0f yd"):format(value)
    end)
    radius:SetValueChangedCallback(ScheduleRefresh)
    Settings.CreateSlider(category, radius, radiusOptions, L.OfferRadiusHelp)

    local direction = Settings.RegisterAddOnSetting(category, "FOREVERQUESTNAVIGATOR_SHOW_DIRECTION_ARROW",
        "showDirectionArrow", settings, Settings.VarType.Boolean, L.DirectionArrow, true)
    direction:SetValueChangedCallback(UpdateDirectionTicker)
    Settings.CreateCheckbox(category, direction, L.DirectionArrowHelp)

    local opacity = Settings.RegisterAddOnSetting(category, "FOREVERQUESTNAVIGATOR_TRACKER_OPACITY",
        "opacityPercent", settings, Settings.VarType.Number, L.Opacity, 100)
    local opacityOptions = Settings.CreateSliderOptions(30, 100, 5)
    opacityOptions:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(value)
        return ("%.0f%%"):format(value)
    end)
    opacity:SetValueChangedCallback(function() tracker:SetAlpha(settings.opacityPercent / 100) end)
    Settings.CreateSlider(category, opacity, opacityOptions, L.OpacityHelp)
    Settings.RegisterAddOnCategory(category)
    return category
end

local function ToggleTracker()
    tracker:SetShown(not tracker:IsShown())
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
        settings.hidden = settings.hidden == true
        settings.includeElite = nil
        settings.currentZoneOnly = nil
        settings.useQuestieKillLocations = settings.useQuestieKillLocations ~= false
        settings.showQuestieOffers = settings.showQuestieOffers == true
        settings.showTurnInStar = nil
        local radius = settings.questieOfferRadius
        settings.questieOfferRadius = type(radius) == "number" and radius >= 50 and radius <= 500 and radius or 200
        settings.showDirectionArrow = settings.showDirectionArrow ~= false
        settings.sortByDistance = nil
        local opacity = settings.opacityPercent
        settings.opacityPercent = type(opacity) == "number" and opacity >= 30 and opacity <= 100 and opacity or 100
        LoadSkippedQuests()
        local character = ForeverQuestNavigatorCharacterDB
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
            select = SelectQuest,
            openSettings = OpenSettings,
            openQuestMap = OpenQuestMap,
        }, version)
        local function UpdateTrackers()
            UpdateDistanceTicker()
            UpdateQuestieTicker()
        end
        tracker:HookScript("OnShow", UpdateTrackers)
        tracker:HookScript("OnHide", UpdateTrackers)

        events:RegisterEvent("PLAYER_ENTERING_WORLD")
        events:RegisterEvent("PLAYER_LEVEL_UP")
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
end

events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(_, event, arg)
    if event == "ADDON_LOADED" then
        AddonLoaded(arg)
    else
        if event == "PLAYER_ENTERING_WORLD" and not minimapButton and tracker then
            minimapButton = addon.CreateMinimapButton(tracker, settings, ToggleTracker, OpenSettings)
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
            end
        end
        ScheduleRefresh()
    end
end)
