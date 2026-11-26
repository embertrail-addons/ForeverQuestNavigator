local _, addon = ...
addon.NavigationController = {}

local function TurnInTour(input, eligibleQuests, measurements, feedback)
    local started = addon.Performance:Begin()
    local tour = addon.PlanningInsights.TurnIns(input.mapAPI, eligibleQuests, measurements, input.xpNeeded, feedback)
    addon.Performance:Finish("plan:turnins", started)
    return tour
end

function addon.NavigationController.Compute(input)
    local questMarkers = input.questMarkers
    local measurableQuestIDs = input.measurableQuestIDs
    local distanceMaps = input.distanceMaps
    local previousObjectives = input.previousObjectives
    local objectiveLock = input.objectiveLock
    local avoidedObjectives = input.avoidedObjectives
    local eligibleQuests = input.eligibleQuests
    local savedAccessPoints = input.savedAccessPoints
    local passedAccessPoints = input.passedAccessPoints
    local turnInLocations = input.turnInLocations
    local questTargetMaps = input.questTargetMaps
    questMarkers = addon.CampAlternatives.Filter(input.mapAPI, questMarkers, input.campAvoidance or {}, input.now or 0)
    if input.campAvoidance and next(input.campAvoidance) then
        local filteredAccess = {}
        for id, objectives in pairs(savedAccessPoints) do
            filteredAccess[id] = {}
            for index, entry in pairs(type(objectives) == "table" and objectives or {}) do
                local rejected
                for _, camp in ipairs(input.campAvoidance[id] or {}) do
                    if camp.point.objectiveIndex == index then
                        local target = type(entry) == "table" and entry.target
                        local metric = addon.TravelSupport.ValidPoint(target) and addon.QuestLocation.GetDistanceMetric(input.mapAPI, target)
                        local gap = metric and metric(target, camp.point)
                        if not gap or gap <= addon.CampAlternatives.radius then rejected = true break end
                    end
                end
                if not rejected then filteredAccess[id][index] = entry end
            end
        end
        savedAccessPoints = filteredAccess
    end
    local t_measure = addon.Performance:Begin()
    local measurements, objectiveDistances
    measurements, objectiveDistances = addon.QuestLocation.MeasureQuests(input.mapAPI, questMarkers, measurableQuestIDs,
        distanceMaps, previousObjectives, objectiveLock, avoidedObjectives)
    addon.Performance:Finish("plan:measure", t_measure)
    local t_camps = addon.Performance:Begin()
    local camps, previousCamps = {}, {}
    for _, quest in ipairs(eligibleQuests) do
        local previous = input.previousCamps and input.previousCamps[quest.id]
        local choices = addon.CampChoices.Build(input.mapAPI, quest, measurements[quest.id], questMarkers[quest.id],
            eligibleQuests, measurements, distanceMaps, previous, input.playerLevel, input.feedback)
        local selected = choices[1]
        if selected then
            local m = selected.measurement
            measurements[quest.id] = m
            objectiveDistances[quest.id][m.marker.objectiveIndex] = {marker = m.marker, squared = m.yards ^ 2, east = m.east, north = m.north}
            previousCamps[quest.id] = {mapID = m.marker.mapID, x = m.marker.x, y = m.marker.y,
                objectiveIndex = m.marker.objectiveIndex, manual = selected.previous and previous.manual or nil}
            if #choices > 1 then camps[quest.id] = choices end
        end
    end
    addon.Performance:Finish("plan:camps", t_camps)
    addon.TravelSupport.ApplyAccess(input.mapAPI, eligibleQuests, measurements, distanceMaps, savedAccessPoints, passedAccessPoints, input.onTaxi or input.detour)
    local t_presence = addon.Performance:Begin()
    local presence = {}
    for _, quest in ipairs(eligibleQuests) do
        if not quest.readyToTurnIn then
            presence[quest.id] = addon.ObjectivePresence.Area(input.mapAPI, questMarkers[quest.id], measurements[quest.id],
                input.previousPresence and input.previousPresence[quest.id], avoidedObjectives[quest.id],
                objectiveLock and objectiveLock.questID == quest.id and objectiveLock.index,
                input.previousCamps and input.previousCamps[quest.id])
        end
    end
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
    addon.Performance:Finish("plan:presence", t_presence)
    local t_journeys = addon.Performance:Begin()
    local journeys, knownJourney = {}, false
    for _, quest in ipairs(eligibleQuests) do
        local measured = measurements[quest.id]
        local origin = measured and (measured.objectiveMarker or measured.marker)
        if origin and not quest.readyToTurnIn and input.questieReady then
            -- The nearest turn-in NPC depends on where the objective is: cached per quest and
            -- rough objective position (about 1% of the map), so moving does not repeat Questie lookups.
            local area = ("%d:%d:%d"):format(origin.mapID or 0, math.floor((origin.x or 0) * 100), math.floor((origin.y or 0) * 100))
            local cached = turnInLocations[quest.id]
            if cached == nil or (cached and cached.fqnArea ~= area) then
                local finisher = addon.QuestieRoutes.GetOutdoorTurnInMarker(input.mapAPI, input.mapType,
                    questTargetMaps or {}, quest.id, origin)
                if finisher then finisher.fqnArea = area end
                turnInLocations[quest.id] = finisher or false
            end
            local objectives = input.questAPI.GetQuestObjectives and input.questAPI.GetQuestObjectives(quest.id)
            journeys[quest.id] = addon.TravelSupport.BuildJourney(input.mapAPI, quest, measured, objectives,
                objectiveDistances[quest.id], turnInLocations[quest.id])
            if journeys[quest.id] then knownJourney = true end
        end
    end
    addon.Performance:Finish("plan:journeys", t_journeys)
    local questJourneys = knownJourney and journeys or nil
    local capacity = addon.QuestCapacity.WithReserve(input.capacity, input.routeChains)
    local feedback, adjustments = {}, {}
    for _, quest in ipairs(eligibleQuests) do
        local entry, penalty = addon.RecommendationFeedback.Get(input.feedback, quest, measurements[quest.id], input.now or 0)
        feedback[quest.id], adjustments[quest.id] = entry, penalty
        if presence[quest.id] and not entry then adjustments[quest.id] = (adjustments[quest.id] or 0) - 60 end
        if capacity and (capacity.full or capacity.reserveNeeded) and quest.readyToTurnIn and not entry
            and measurements[quest.id] and measurements[quest.id].yards <= 500 then adjustments[quest.id] = -100 end
    end
    -- Quests that synced group members still work on rank a little earlier.
    for id, count in pairs(input.groupCounts or {}) do
        if measurements[id] and not feedback[id] then adjustments[id] = (adjustments[id] or 0) - math.min(80, 40 * count) end
    end
    local t_bundles = addon.Performance:Begin()
    local bundles = addon.PlanningInsights.Bundles(input.mapAPI, eligibleQuests, measurements, input.playerLevel, feedback)
    for _, bundle in ipairs(bundles) do
        local bonus = math.min(60, (#bundle.entries - 1) * 20)
        for _, entry in ipairs(bundle.entries) do adjustments[entry.quest.id] = (adjustments[entry.quest.id] or 0) - bonus end
    end
    addon.Performance:Finish("plan:bundles", t_bundles)
    local t_value = addon.Performance:Begin()
    -- Quest value: XP per minute, look-ahead, follow-ups, finishing the zone, learned preference.
    local factors
    if input.valueModel then
        local playerMap = input.mapAPI.GetBestMapForUnit and input.mapAPI.GetBestMapForUnit("player")
        local valueAdjustments
        valueAdjustments, factors = addon.QuestValue.Adjustments({
            quests = eligibleQuests, measurements = measurements, journeys = journeys, model = input.valueModel,
            xp = addon.QuestLog.GetTurnInXP, playerMap = playerMap, chains = input.routeChains, shared = input.sharedQuests,
            distance = function(a, b)
                local metric = a and addon.QuestLocation.GetDistanceMetric(input.mapAPI, a)
                return metric and metric(a, b)
            end,
        })
        for id, delta in pairs(valueAdjustments) do
            if not feedback[id] then adjustments[id] = (adjustments[id] or 0) + delta end
        end
    end
    addon.Performance:Finish("plan:value", t_value)
    local t_rank = addon.Performance:Begin()
    local ranked, distanceOrder
    local playerLevel = input.playerLevel
    ranked, distanceOrder = addon.QuestPrioritizer.RankByDistance(eligibleQuests, measurements, input.distanceOrder, playerLevel, questJourneys, nil, adjustments)
    local planningRanked = {}
    for _, quest in ipairs(ranked) do if not feedback[quest.id] then planningRanked[#planningRanked + 1] = quest end end
    addon.Performance:Finish("plan:rank", t_rank)
    local t_route = addon.Performance:Begin()
    local routeQuest, route, levelUpQuest, nextQuest
    if not input.flying then
        routeQuest, route = addon.QuestRoute.Recommend(input.mapAPI, planningRanked, measurements, input.routeChains, playerLevel)
        if not input.manual then
            levelUpQuest, nextQuest = addon.QuestRoute.RecommendLevelUp(input.mapAPI, planningRanked, measurements, playerLevel, input.xpNeeded)
        end
    end
    addon.Performance:Finish("plan:route", t_route)
    return {
        measurements = measurements, objectiveDistances = objectiveDistances,
        previousObjectives = previousObjectives, objectiveLock = objectiveLock,
        journeys = questJourneys, ranked = ranked, distanceOrder = distanceOrder,
        playerLevel = playerLevel, rankingInputOrder = input.distanceOrder,
        routeQuest = routeQuest, route = route, levelUpQuest = levelUpQuest, nextQuest = nextQuest,
        xpNeeded = input.xpNeeded,
        bundles = bundles, feedback = feedback, adjustments = adjustments, planningRanked = planningRanked, factors = factors,
        capacity = capacity,
        camps = camps, previousCamps = previousCamps, finishers = turnInLocations,
        presence = presence,
        turnInTour = TurnInTour(input, eligibleQuests, measurements, feedback),
    }
end
