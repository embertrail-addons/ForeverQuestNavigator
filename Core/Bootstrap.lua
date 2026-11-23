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
local questMarkers, measurableQuestIDs, distanceMaps
local questMeasurements, questTargetMaps
local playerZoneID, questDestinations = nil, {}
local activeDirection
local eligibleQuests, shownQuests, distanceOrder
local objectiveDistances, objectiveLock
local previousObjectives = {}
local avoidedObjectives = {}
local integration = addon.QuestieIntegration
local objectiveMarkers, killMarkers, questieReadyRegistered
local questieTrackerMenuHooked
local nearbyOffers
local routeChains
local outing
local ScheduleRefresh
local SetDisplayMode
local GetQuestDestination
local UpdateQuestLogButton
local navigationSnapshot
function addon.GetNavigationSnapshot() return navigationSnapshot end
function addon.UpdateRecovery(event)
    if not addon.CorpseNavigation then return end
    local previous = addon.RecoveryState
    local wasActive = previous and previous.active
    local state = addon.CorpseNavigation.Update(previous, C_Map, C_DeathInfo,
        {dead = UnitIsDead, ghost = UnitIsGhost, either = UnitIsDeadOrGhost}, GetTime and GetTime() or 0, event)
    addon.RecoveryState = state
    if state.active and not wasActive then addon.RecoveryQuestID = shownQuests and shownQuests[1] and shownQuests[1].id end
    if not state.active then addon.RecoveryQuestID = nil end
    if tracker and tracker.SetRecoveryState then tracker:SetRecoveryState(state.active and state or nil) end
    return state
end
local markedQuestID
-- Grouped state keeps the main chunk well below Lua 5.1's 200-local limit.
-- shown: last rendered navigator content (used to skip identical re-renders).
local shown = {zones = {}, rewards = {}, alternativeRoutes = {}}
local tickers = {} -- distance, direction, questie
local flight = {active = false} -- active, questID, confirmedPoints, routes, taxiMapOpen
local LIMITS = {MINIMUM_FLIGHT_HINT_DISTANCE = 1500, DEFAULT_OPACITY = 80,
    DEFAULT_OFFER_RADIUS = 350, MAX_OFFER_RADIUS = 1000}
local questJourneys, turnInLocations = nil, {}
local savedAccessPoints, passedAccessPoints = {}, {}
local session
local questNotes = {}
local targetCorrections = {}
local combatQuestID, ShowPlanning, RefreshNearbyOffers
local temporaryFeedback = {}
local campAvoidance = {}
local questCapacity
local ShowFeedback, ShowProfiles
local temporaryDetour, detourMeasurement
local insights = {sharedItems = {}, laterQuests = {}, knownVendors = {}, hiddenOffers = {}, offerSuppressed = {}}
local movementState
local ShowLevelChanges
local workspace

local function BuildDecisionBrief(snapshot, mapType)
    snapshot = snapshot or {}
    snapshot.bags = addon.JourneyPlanning.Bags(C_Container, NUM_BAG_SLOTS)
    snapshot.collecting = false
    local quest = snapshot.view and snapshot.view.quest
    if quest and not quest.readyToTurnIn and C_QuestLog and C_QuestLog.GetQuestObjectives then
        local ok, goals = pcall(C_QuestLog.GetQuestObjectives, quest.id)
        if ok and type(goals) == "table" then for _, goal in ipairs(goals) do
            if goal.type == "item" and not goal.finished then snapshot.collecting = true break end
        end end
    end
    snapshot.laterCount = 0
    snapshot.offerUndo = addon.OfferUndoAvailable and addon.OfferUndoAvailable() or false
    local context = addon.GetLaterContext and addon.GetLaterContext() or {}
    for _, entry in ipairs(addon.JourneyPlanning.Later(insights.laterQuests, context, C_QuestLog)) do
        if entry.due then snapshot.laterCount = snapshot.laterCount + 1 end
    end
    return addon.DecisionBrief.Build(snapshot, insights.roundLedger, C_Map, mapType)
end

local function CurrentMapRoute(id)
    if settings.showRouteMarkers ~= false and shownQuests and shownQuests[1].id == id then return shown.routePreview end
    local destination = GetQuestDestination and GetQuestDestination(id)
    if destination and destination.target then
        for _, quest in ipairs(eligibleQuests or {}) do
            if quest.id == id then return {{target = destination.target, quest = quest, single = true}} end
        end
    end
end

local function SessionTime()
    return GetTime and GetTime() or 0
end

addon.Undo = addon.UndoHistory.New(20, function()
    addon.RefreshUndoHistory()
    addon.RefreshProfilePreview()
    addon.RefreshAccessRouteEditor()
    addon.RefreshFeedbackManager()
end)
function addon.UndoLastChange()
    local ok, label = addon.Undo:Undo()
    print("FQN | " .. (ok and (L.UndoDone .. ": " .. label) or label))
end

local function RecordAccessChange(id, index, before)
    addon.Undo:Capture(L.UndoAccess:format(id), function()
        return savedAccessPoints[id] and savedAccessPoints[id][index]
    end, function(value)
        if value then
            savedAccessPoints[id] = savedAccessPoints[id] or {}
            savedAccessPoints[id][index] = value
        else addon.TravelSupport.RemoveAccess(savedAccessPoints, id, index) end
        passedAccessPoints[id .. ":" .. index], outing = nil, nil
        addon.RefreshAccessManager() ScheduleRefresh()
    end, before, savedAccessPoints[id] and savedAccessPoints[id][index])
end

local function ClearTemporaryFeedback(id)
    local removed = {}
    for key, entry in pairs(temporaryFeedback) do
        if not id or key == id then removed[key] = addon.UndoHistory.Copy(entry) temporaryFeedback[key] = nil end
    end
    if next(removed) then addon.Undo:Push(L.UndoFeedback, function()
        local valid = {}
        for key, entry in pairs(removed) do
            if temporaryFeedback[key] then return false end
            if C_QuestLog.IsOnQuest(key) then
                local copy = {[key] = addon.UndoHistory.Copy(entry)}
                if addon.RecommendationFeedback.Get(copy, {id = key, readyToTurnIn = C_QuestLog.IsComplete(key)},
                    questMeasurements and questMeasurements[key], SessionTime()) then valid[key] = copy[key] end
            end
        end
        if not next(valid) then return false end
        for key, entry in pairs(valid) do temporaryFeedback[key] = entry end
        outing = nil ScheduleRefresh() return true
    end) end
    outing = nil ScheduleRefresh()
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
addon.ClearFQNMapMarkers = ClearMapMarker

local function UpdateMapMarker()
    if addon.DemoMode.IsActive() then return end
    if not markedQuestID then return end
    if not (C_QuestLog and C_QuestLog.IsOnQuest and C_QuestLog.IsOnQuest(markedQuestID)) then
        ClearMapMarker()
        return
    end
    local destination = GetQuestDestination(markedQuestID)
    addon.ShowQuestMapMarker(destination and destination.target, ClearMapMarker, CurrentMapRoute(markedQuestID))
end

local function FlightAPI()
    return {Enum = Enum, GetTaxiMapID = GetTaxiMapID, C_TaxiMap = C_TaxiMap, C_Map = C_Map,
        GetNumRoutes = GetNumRoutes, TaxiGetNodeSlot = TaxiGetNodeSlot}
end

local function ConfirmFlightPoints()
    addon.FlightPoints.Confirm(flight, FlightAPI())
end

local function GetFlightHint(questID, destination, flightContext)
    return addon.FlightPoints.Hint(destination, {
        measurement = questMeasurements and questMeasurements[questID], minimum = LIMITS.MINIMUM_FLIGHT_HINT_DISTANCE,
        playerZoneID = playerZoneID, flightContext = flightContext, confirmedPoints = flight.confirmedPoints,
        faction = UnitFactionGroup and UnitFactionGroup("player"),
    }, FlightAPI())
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

function addon.DescribeQuest(quest, measurement, noRewards)
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
    local note = questNotes[quest.id]
    if not noRewards and type(note) == "table" and type(note.text) == "string" then text = text .. "\n" .. L.QuestNoteText:format(note.text) end
    text = text .. "\n" .. L.QuestMenuHint
    local progress = addon.QuestTools.ProgressHint(quest)
    if progress then text = text .. "\n" .. progress end
    if not noRewards and settings.showQuestRewards ~= false then text = text .. "\n" .. addon.QuestRewards.Describe(addon.QuestRewards.Client(quest.id)) end
    if not noRewards and settings.showQuestRewards ~= false and settings.showRewardComparison ~= false then
        local comparison = addon.RewardComparison.Describe(addon.QuestRewards.Client(quest.id))
        if comparison then text = text .. "\n" .. comparison end
    end
    for _, item in ipairs(insights.sharedItems) do
        for _, contribution in ipairs(item.quests) do
            if contribution.quest.id == quest.id then
                text = text .. "\n" .. item.name .. ": " .. L.SharedRequired:format(item.required, #item.quests)
                    .. " · " .. (item.remaining and L.SharedRemaining:format(item.remaining) or L.SharedInventoryUnknown)
            end
        end
    end
    local feedback = addon.RecommendationFeedback.Get(temporaryFeedback, quest, measurement, SessionTime())
    if feedback then
        local key = ({hard = "FeedbackHard", blocked = "FeedbackBlocked", inconvenient = "FeedbackInconvenient"})[feedback.kind]
        text = text .. "\n" .. L[key] .. "\n" .. L.FeedbackHelp
    end
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
        measurements = questMeasurements, reason = shown.reason, route = shown.routeDetails, journeys = questJourneys,
        adjustments = navigationSnapshot and navigationSnapshot.adjustments,
    })
    local marker = addon.GetMapMarkerStatus()
    report = report .. ("\nmapMarkers: backend=%s count=%d target=%s"):format(marker.backend, marker.count, tostring(marker.hasTarget))
    report = report .. "\n" .. marker.detail
    return report
end

local function ShowDiagnostics()
    addon.ShowDiagnosticReport(BuildDiagnostics())
end

function addon.OpenProblemReport()
    local quest = shownQuests and shownQuests[1]
    local measurement = quest and questMeasurements and questMeasurements[quest.id]
    local loaded = C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Questie")
    local markers = addon.GetMapMarkerStatus()
    local report = addon.ProblemReport.Build({version = C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(addonName, "Version"),
        quest = quest, marker = measurement and measurement.marker, yards = measurement and measurement.yards,
        level = UnitLevel and UnitLevel("player"), manual = manualQuestID ~= nil,
        decision = navigationSnapshot and navigationSnapshot.decision, questieLoaded = loaded, questieReady = not not integration.IsReady(),
        markerCount = markers.count, tourStops = workspace and #workspace.plan.stops})
    addon.ShowTextWindow("problemReport", report, L.ProblemReportTitle, L.ProblemReportPrivacy)
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
    return addon.TrackerPresentation.Targets(quest, objectives, objectiveDistances, questMeasurements, avoidedObjectives, objectiveLock)
end

local SameObjectiveTargets = addon.TrackerPresentation.SameTargets

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
        if shownQuests[index + 1] ~= quest or shown.zones[index + 1] ~= zones[index + 1]
            or shown.alternativeRoutes[index] ~= routes[index] or shown.rewards[index + 1] ~= rewards[index + 1] then
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
    if workspace and workspace:Current() == quest.id then
        for index = 2, math.min(3, #workspace.plan.stops) do
            local stop = workspace.plan.stops[index]
            local nextDestination = GetQuestDestination(stop.id)
            local candidate
            for _, entry in ipairs(eligibleQuests or {}) do if entry.id == stop.id then candidate = entry break end end
            if not (candidate and nextDestination and nextDestination.target) then break end
            preview[#preview + 1] = {quest = candidate, target = nextDestination.target,
                action = candidate.readyToTurnIn and "turnIn" or "objective"}
        end
        return preview
    end
    local function AddStop(candidate, marker, action)
        if not marker or #preview == 3 then return end
        local previous = preview[#preview].target
        local yards = distance and distance(previous, marker)
        preview[#preview + 1] = { quest = candidate, target = marker, action = action, yards = yards }
    end
    if first and first.objectiveMarker then
        for index = 2, #(first.accessSteps or {}) do AddStop(quest, first.accessSteps[index], "access") end
        AddStop(quest, first.objectiveMarker, "objective")
    end
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
        if journey.exitSteps then
            for _, point in ipairs(journey.exitSteps) do AddStop(quest, point, "access") end
        elseif journey.exit then AddStop(quest, journey.exit, "access") end
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
    navigationSnapshot = navigationSnapshot or { measurements = questMeasurements or {},
        objectiveDistances = objectiveDistances or {}, ranked = ranked, playerLevel = playerLevel, capacity = questCapacity }
    navigationSnapshot.sharedItems = insights.sharedItems
    navigationSnapshot.pickupPlanning = insights.pickupPlanning
    navigationSnapshot.chains = addon.QuestInsights.Chains(C_Map, Enum and Enum.UIMapType, ranked, routeChains, questMeasurements)
    local quest = ranked[1]
    local tourID = workspace and workspace:Current()
    local excursionStop = addon.ExcursionPlan.Current(insights.excursion)
    local levelHold = insights.levelHold and SessionTime() <= insights.levelHold.untilTime and insights.levelHold.id
    local selectedQuestID = manualQuestID or (objectiveLock and objectiveLock.questID) or addon.RecoveryQuestID or flight.questID or combatQuestID
        or (excursionStop and excursionStop.action ~= "accept" and excursionStop.quest.id) or tourID or (temporaryDetour and temporaryDetour.questID) or levelHold
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
            if levelHold == selectedQuestID then insights.levelHold, levelHold = nil, nil end
            manualQuestID = nil
            heldQuest = nil
            objectiveLock = nil
            flight.questID = nil
            combatQuestID = nil
        end
    end
    if not (manualQuestID or objectiveLock or addon.RecoveryQuestID or flight.questID or combatQuestID or levelHold or excursionStop or tourID or (temporaryDetour and temporaryDetour.questID)) and routeQuest then
        quest = routeQuest
    else
        routeNote = manualQuestID and (heldQuest and L.HeldQuestReason or L.ManualSelection)
            or DescribeRecommendation(quest, playerLevel)
        routeDetails = nil
    end
    if tourID and quest.id == tourID and not manualQuestID then
        routeNote = L.TourRunning navigationSnapshot.decision = "tour"
    end
    if excursionStop then routeNote = L.ExcursionCurrent navigationSnapshot.decision = "excursion" end
    if addon.RecoveryState and addon.RecoveryState.active and not addon.RecoveryQuestID then addon.RecoveryQuestID = quest.id end
    if levelHold and quest.id == levelHold and not (manualQuestID or objectiveLock or excursionStop or tourID) then
        routeNote = L.AdventureLevelShort navigationSnapshot.decision, navigationSnapshot.decisionSaving = "levelReview", nil
    end
    local progressHint = addon.QuestTools.ProgressHint(quest)
    if progressHint then routeNote = routeNote and (routeNote .. " · " .. progressHint) or progressHint end
    local summaryImportant = not not (manualQuestID or tourID or routeQuest or quest.readyToTurnIn or progressHint
        or addon.QuestPrioritizer.GetDifficulty(quest, playerLevel) == "red")
    for _, bundle in ipairs(navigationSnapshot.decision == "ranking" and navigationSnapshot.bundles or {}) do
        for _, entry in ipairs(bundle.entries) do
            if entry.quest.id == quest.id then
                local hint = L.SharedStopCount:format(#bundle.entries)
                summaryImportant = true
                routeNote = routeNote and (routeNote .. " · " .. hint) or hint
                break
            end
        end
    end
    local feedback = navigationSnapshot.feedback and navigationSnapshot.feedback[quest.id]
    if feedback then routeNote = (routeNote and (routeNote .. " · ") or "") .. L.FeedbackActive summaryImportant = true end
    if quest.readyToTurnIn and navigationSnapshot.capacity and (navigationSnapshot.capacity.full or navigationSnapshot.capacity.reserveNeeded) then
        routeNote = (routeNote and (routeNote .. " · ") or "") .. (navigationSnapshot.capacity.full and L.FreeQuestSlot or L.ReserveQuestSlot)
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
    local rewardDetails = settings.showQuestXP and xpNeeded and rewardText or nil
    if settings.showQuestRewards ~= false then
        local info = addon.QuestRewards.Client(quest.id)
        rewardDetails = (rewardDetails and (rewardDetails .. "\n") or "") .. addon.QuestRewards.Describe(info)
        local comparison = settings.showRewardComparison ~= false and addon.RewardComparison.Describe(info)
        if comparison then rewardDetails = rewardDetails .. "\n" .. comparison end
    end
    local rewards = {}
    if settings.showQuestXP and reward then
        rewards[1] = addon.TrackerPresentation.XPLine(reward, xpNeeded, playerLevel)
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
    if routeNote == L.LevelUpOnTurnIn and settings.showQuestXP and reward and reward >= xpNeeded then routeNote = nil end
    local nearbyStops = GetNearbyStops(quest, destination, ranked, playerLevel)
    local approachStops
    local flightContext = addon.QuestLocation.GetFlightContext(C_Map, distanceMaps, flight.routes)
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
    if quest.special and quest.readyToTurnIn and not (destination and destination.target) then text = text .. "\n" .. L.SpecialTurnInUnknown end
    local reasonLines = { L.WhyThisQuest }
    if heldQuest then reasonLines[#reasonLines + 1] = heldQuest.policy == "turnIn" and L.PriorityUntilTurnIn
        or heldQuest.policy == "complete" and L.PriorityUntilComplete or L.HeldQuestReason end
    if manualQuestID then
        reasonLines[#reasonLines + 1] = L.ManualQuestReason
    elseif objectiveLock then
        reasonLines[#reasonLines + 1] = L.ManualObjectiveReason
    else
        reasonLines[#reasonLines + 1] = L.AutomaticQuestReason
    end
    reasonLines[#reasonLines + 1] = addon.DescribeQuest(quest, questMeasurements and questMeasurements[quest.id], true)
    local fit = DescribeRecommendation(quest, playerLevel)
    if fit then reasonLines[#reasonLines + 1] = fit end
    if routeNote and routeNote ~= fit then reasonLines[#reasonLines + 1] = routeNote end
    if forecast then
        if routeDetails then reasonLines[#reasonLines + 1] = routeDetails end
    end
    local preparation = addon.TravelPreparation.Describe(questMeasurements and questMeasurements[quest.id], settings, C_Container, GetInventoryItemDurability, NUM_BAG_SLOTS)
    if preparation then
        reasonLines[#reasonLines + 1] = preparation
        routeDetails = routeDetails and (routeDetails .. "\n" .. preparation) or preparation
    end
    table.insert(reasonLines, heldQuest and 4 or 3, addon.Recommendation.Short(navigationSnapshot, quest, manualQuestID or objectiveLock))
    local reason = table.concat(reasonLines, "\n")
    local explanation = addon.NavigationHints.Why(navigationSnapshot, quest, manualQuestID or objectiveLock)
    local quality = addon.NavigationHints.TargetText(questMeasurements and questMeasurements[quest.id] and questMeasurements[quest.id].marker)
    reason = reason .. "\n" .. explanation .. "\n" .. quality
    routeDetails = (routeDetails and routeDetails .. "\n" or "") .. quality
    local measured = questMeasurements and questMeasurements[quest.id]
    local travelTime = not flight.active and addon.TravelTime.Describe(measured and measured.yards, settings)
    if travelTime then routeDetails = routeDetails .. "\n" .. travelTime reason = reason .. "\n" .. travelTime end
    local overview = addon.BuildZoneOverview(C_Map, Enum and Enum.UIMapType, eligibleQuests, navigationSnapshot)
    local suggestion = addon.ZoneSuggestion.Find(overview, playerZoneID, manualQuestID or heldQuest
        or (settings.quietNavigation and (flight.active or (InCombatLockdown and InCombatLockdown()))), measured and measured.yards)
    if suggestion then
        local advisory = L.ZoneSuggestion:format(suggestion.name, suggestion.clusterSuitable, suggestion.clusterYards or suggestion.yards)
        routeDetails = routeDetails .. "\n" .. advisory reason = reason .. "\n" .. advisory
    end
    if not routeNote and not (settings.showQuestXP and reward and reward >= xpNeeded) then routeNote = explanation end
    local itemHint = addon.QuestItemHints.Read(C_QuestLog, quest.id, GetQuestLogSpecialItemInfo, GetItemCount)
    if itemHint then
        local hint = L.QuestItemHint:format(itemHint.name)
        routeDetails = routeDetails and (routeDetails .. "\n" .. hint) or hint
        reason = reason .. "\n" .. hint
    end
    local comparison = addon.PlanningInsights.Compare(navigationSnapshot, quest, manualQuestID or objectiveLock)
    reason = reason .. "\n" .. comparison
    navigationSnapshot.comparison = comparison
    local preview = BuildRoutePreview(quest, destination, forecast, nextQuest)
    local area = addon.BuildAreaOverview(C_Map, Enum and Enum.UIMapType, playerZoneID, eligibleQuests,
        questMarkers or {}, distanceMaps, avoidedObjectives)
    if navigationSnapshot then
        navigationSnapshot.changeContext = {accepted = insights.newlyAccepted, turnedIn = insights.turnInUntil and SessionTime() <= insights.turnInUntil and insights.lastTurnIn or nil}
        navigationSnapshot.noteRevision = insights.noteRevision or 0
        navigationSnapshot.activeQuestID = quest.id
        navigationSnapshot.activeMeasurement = questMeasurements and questMeasurements[quest.id]
        navigationSnapshot.preparation = preparation
        navigationSnapshot.view = { quest = quest, objectives = text, alternatives = alternatives,
            changeNotice = addon.NavigationHints.Change(shownQuests and shownQuests[1], quest, navigationSnapshot, manualQuestID or objectiveLock),
            manual = manualQuestID ~= nil or excursionStop ~= nil, routeNote = routeNote, routeDetails = routeDetails, summaryImportant = summaryImportant,
            reason = reason, zones = zones, alternativeRoutes = alternativeRoutes, preview = preview, rewardDetails = rewardDetails,
            noteText = addon.GetQuestNoteText(quest.id),
            nearbyStops = nearbyStops, rewards = rewards, targets = targets, hasMap = hasMap,
            approachStops = approachStops, area = area }
        navigationSnapshot.flying = flight.active
        navigationSnapshot.excursionStep = excursionStop
        navigationSnapshot.excursionPlan = insights.excursion
        if excursionStop and excursionStop.action == "accept" then
            local measuredPickup = addon.TemporaryDetour.Measure(C_Map, excursionStop.target)
            navigationSnapshot.excursionYards = measuredPickup and measuredPickup.yards
        end
        navigationSnapshot.arrived = arrivalState and arrivalState.arrived
        navigationSnapshot.brief = BuildDecisionBrief(navigationSnapshot, Enum and Enum.UIMapType)
        tracker:SetDecisionBrief(navigationSnapshot.brief)
    end
    if shownQuests and shownQuests[1] == quest and shownQuests[2] == alternatives[1]
        and shownQuests[3] == alternatives[2] and shown.routeNote == routeNote and shown.routeDetails == routeDetails
        and shown.objectives == text
        and SameAdditionalQuests(alternatives, zones, alternativeRoutes, rewards)
        and shown.reason == reason
        and (tracker.noteRevision or 0) == (insights.noteRevision or 0)
        and (rewardDetails or "") == (tracker.rewardDetails and tracker.rewardDetails:GetText() or "")
        and SameRoutePreview(shown.routePreview, preview)
        and SameAreaOverview(shown.areaOverview, area)
        and shown.mapAvailable == hasMap
        and SameObjectiveTargets(shown.objectiveTargets, targets)
        and zones[1] == shown.zones[1] and zones[2] == shown.zones[2] and zones[3] == shown.zones[3]
        and alternativeRoutes[1] == shown.alternativeRoutes[1] and alternativeRoutes[2] == shown.alternativeRoutes[2]
        and rewards[1] == shown.rewards[1] and rewards[2] == shown.rewards[2] and rewards[3] == shown.rewards[3]
        and SameNearbyStops(shown.nearbyStops, nearbyStops) and SameApproachStops(shown.approachStops, approachStops) then
        return
    end

    shown.objectives = text
    shown.reason = reason
    shown.routePreview = preview
    shown.areaOverview = area
    shown.mapAvailable = hasMap
    shown.objectiveTargets = targets
    shownQuests = { quest }
    for _, alternative in ipairs(alternatives) do shownQuests[#shownQuests + 1] = alternative end
    shown.routeNote, shown.routeDetails = routeNote, routeDetails
    shown.zones, shown.alternativeRoutes = zones, alternativeRoutes
    shown.nearbyStops = nearbyStops
    shown.approachStops = approachStops
    shown.rewards = rewards
    tracker:RenderSnapshot(navigationSnapshot, skippedQuestIDs)
end

local function DescribeRoute(quest, route)
    return addon.TrackerPresentation.Route(quest, route)
end

local function DescribeOuting(stops)
    return addon.TrackerPresentation.Outing(stops)
end

local function UpdateOuting(ranked, measurements, playerLevel, followUp)
    if manualQuestID or followUp or addon.ExcursionPlan.Current(insights.excursion) then
        outing = nil
        return
    end
    if outing then
        local byID = {}
        for _, quest in ipairs(ranked) do byID[quest.id] = quest end
        local remaining = {}
        for _, stop in ipairs(outing.stops) do
            local quest = byID[stop.quest.id]
            if quest and measurements[quest.id] and not (navigationSnapshot.feedback and navigationSnapshot.feedback[quest.id])
                and not addon.QuestPrioritizer.IsLowPriority(quest, playerLevel) then
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

local function FlightStep(quest)
    return addon.FlightPoints.Step(quest, quest and questMeasurements and questMeasurements[quest.id], C_QuestLog)
end

local function UpdateFlightState()
    local recovery = addon.UpdateRecovery()
    if recovery and recovery.active then combatQuestID = nil tracker:SetCombatView(false) return end
    local onTaxi = UnitOnTaxi and UnitOnTaxi("player")
    local flying = onTaxi == true or onTaxi == 1
    if flying ~= flight.active then
        flight.active = flying
        flight.questID = flying and shownQuests and shownQuests[1] and shownQuests[1].id or nil
    end
    tracker:SetFlightView(flying, FlightStep(shownQuests and shownQuests[1]))
    local fighting = InCombatLockdown and InCombatLockdown() == true
    insights.engagement = nil
    if fighting then
        local matches = addon.ObjectivePresence.Engaged({guid = UnitGUID, canAttack = UnitCanAttack, dead = UnitIsDeadOrGhost,
            same = UnitIsUnit, threat = UnitThreatSituation}, insights.combatMarkers or questMarkers, eligibleQuests, C_QuestLog, avoidedObjectives, objectiveLock)
        local current = shownQuests and shownQuests[1] and shownQuests[1].id
        local selected = current and matches[current] and current or combatQuestID and matches[combatQuestID] and combatQuestID
        if not selected then for _, q in ipairs(eligibleQuests or {}) do if matches[q.id] then selected = q.id break end end end
        if selected then insights.engagement = matches[selected] end
        local explicit = manualQuestID or objectiveLock or addon.ExcursionPlan.Current(insights.excursion) or workspace and workspace:Current() or temporaryDetour
        if explicit then combatQuestID = nil
        elseif selected then
            combatQuestID = selected
        elseif not combatQuestID and settings.quietNavigation ~= false then combatQuestID = current end
    end
    if not fighting then combatQuestID = nil end
    tracker:SetCombatView(fighting == true and settings.quietNavigation ~= false)
    if fighting or flying then addon.HideLevelNotice() end
end

local function UpdateDirection()
    if addon.DemoMode.IsActive() then return end
    local performanceStart = addon.Performance:Begin()
    UpdateFlightState()
    local recovery = addon.RecoveryState
    if recovery and recovery.active then
        local m = recovery.ghost and recovery.target and addon.TemporaryDetour.Measure(C_Map, recovery.target)
        if recovery.target and not m then recovery.target.world = nil end
        local facing = GetPlayerFacing and GetPlayerFacing()
        local right, forward = addon.QuestLocation.GetRelativeDirection(m, facing)
        tracker:RenderRecovery(recovery, m, right, forward)
        tracker:RenderRowDirections(nil)
        addon.Performance:Finish("direction", performanceStart)
        return
    end
    local returnPoint = workspace and workspace:ReturnTarget()
    if returnPoint and not temporaryDetour and not manualQuestID and not combatQuestID and not flight.active
        and addon.TemporaryDetour.IsOutdoor(C_Map, Enum and Enum.UIMapType, returnPoint.mapID) then
        temporaryDetour = addon.TemporaryDetour.New(returnPoint.mapID, returnPoint.x, returnPoint.y, returnPoint.name)
        temporaryDetour.tourReturn = true
    end
    if temporaryDetour then
        detourMeasurement = addon.TemporaryDetour.Measure(C_Map, temporaryDetour)
        if detourMeasurement and detourMeasurement.yards <= 12 and not temporaryDetour.excursion and not flight.active and not (IsInInstance and IsInInstance()) then
            if temporaryDetour.tourReturn and workspace then workspace:Arrived() end
            temporaryDetour, detourMeasurement = nil, nil
            tracker:SetDetour(nil)
            print("FQN | " .. L.DetourReturned)
            ScheduleRefresh()
        else
            tracker:SetDetour(temporaryDetour, detourMeasurement)
        end
    end
    local facing
    local inInstance = IsInInstance and IsInInstance()
    if not inInstance and not flight.active and GetPlayerFacing then
        facing = GetPlayerFacing()
    end
    local right, forward = addon.QuestLocation.GetRelativeDirection(temporaryDetour and detourMeasurement or activeDirection, facing)
    local active = shownQuests and shownQuests[1]
    local measurement = active and questMeasurements and questMeasurements[active.id]
    local arrived
    arrivalState, arrived = addon.TrackerState.Arrival(arrivalState, active, measurement)
    local here = active and navigationSnapshot and navigationSnapshot.presence and navigationSnapshot.presence[active.id]
    local engaged = active and insights.engagement and insights.engagement.questID == active.id
    local working = here ~= nil or engaged
    local status
    if flight.active then
        status, arrived, arrivalState = FlightStep(active), false, nil
    elseif inInstance then
        status = L.NavigationInstance
    elseif engaged then status = L.QuestEnemyEngaged
    elseif not measurement then
        status = active and next(avoidedObjectives[active.id] or {}) and L.NavigationAvoided or L.NavigationUnknown
    elseif here then status = L.QuestSpawnNeighborhood
    elseif arrived then
        status = addon.NavigationHints.NextAction(active, measurement and measurement.marker, tracker:GetQuestItemHint())
    elseif not right then
        status = L.NavigationFacingUnavailable
    end
    if temporaryDetour then
        arrived = false
        status = flight.active and L.FlightGeneric or inInstance and L.NavigationInstance or not detourMeasurement and L.NavigationUnknown
            or temporaryDetour.tourReturn and L.ReturnJourney
            or temporaryDetour.excursion and (L.ExcursionCurrent .. ": " .. temporaryDetour.name) or L.DetourActive
    end
    if arrived or working or inInstance or flight.active then right, forward = nil, nil end
    if navigationSnapshot then navigationSnapshot.arrived, navigationSnapshot.flying = arrived or working, flight.active end
    tracker:SetJourneyPhase(flight.active and "flight" or active and active.readyToTurnIn and "turnIn" or (arrived or working) and "work" or "travel")
    tracker:RenderDirection(right, forward, status, arrived and not inInstance, working)
    tracker:RenderRowDirections(facing)
    local report = insights.levelReport
    if report and not report.notified and #report.entries > 0 then
        if settings.showLevelHints == false or SessionTime() > report.deadline then report.notified = true
        elseif not flight.active and not (InCombatLockdown and InCombatLockdown())
            and (tracker:IsVisible() or settings.displayMode == "arrow") then
            report.notified = true
            addon.ShowLevelNotice(#report.entries, function() addon.OpenAdventure("level") end,
                tracker:IsVisible() and tracker or tracker.navigation)
        end
    end
    addon.Performance:Finish("direction", performanceStart)
end

local function TrackingVisible()
    return tracker:IsVisible() or settings.displayMode == "arrow"
end

local function UpdateDirectionTicker()
    if TrackingVisible() and (settings.showDirectionArrow or temporaryDetour or (workspace and workspace:ReturnTarget()) or addon.RecoveryState and addon.RecoveryState.active) then
        UpdateDirection()
        local canRotate = addon.RecoveryState and addon.RecoveryState.active or
            ((settings.showDirectionArrow and GetPlayerFacing and (measurableQuestIDs or nearbyOffers) or temporaryDetour)
                and not flight.active and not (IsInInstance and IsInInstance()))
        if canRotate and not tickers.direction then
            tickers.direction = C_Timer.NewTicker(0.2, UpdateDirection)
        elseif not canRotate and tickers.direction then
            tickers.direction:Cancel()
            tickers.direction = nil
        end
        return
    end

    if tickers.direction then
        tickers.direction:Cancel()
        tickers.direction = nil
    end
    tracker:RenderDirection()
    tracker:RenderRowDirections()
end

local function UpdateDistances(force)
    UpdateFlightState()
    if addon.RecoveryState and addon.RecoveryState.active then return end
    local origin = addon.MovementGate.Sample(C_Map)
    local phase = tostring(flight.active) .. ":" .. tostring(combatQuestID) .. ":" .. tostring(IsInInstance and IsInInstance())
    if insights.levelHold and SessionTime() >= insights.levelHold.untilTime then insights.levelHold = nil end
    local deadline = insights.levelHold and insights.levelHold.untilTime
    for _, entry in pairs(temporaryFeedback) do if not deadline or entry.untilTime < deadline then deadline = entry.untilTime end end
    for _, entries in pairs(campAvoidance) do
        for _, entry in ipairs(entries) do if not deadline or entry.untilTime < deadline then deadline = entry.untilTime end end
    end
    local current = navigationSnapshot and navigationSnapshot.activeMeasurement
    if force == false and not addon.MovementGate.ShouldUpdate(movementState, origin, phase,
        current and current.yards <= 50, deadline, SessionTime()) then
        if addon.Performance.enabled then addon.Performance.skipped = addon.Performance.skipped + 1 end
        return
    end
    if measurableQuestIDs and not refreshPending then
        movementState = {point = origin, phase = phase, deadline = deadline}
        local performanceStart = addon.Performance:Begin()
        local snapshot = addon.NavigationController.Compute({
            mapAPI = C_Map, mapType = Enum and Enum.UIMapType, questAPI = C_QuestLog,
            playerLevel = UnitLevel and UnitLevel("player"), questieReady = integration.IsReady(),
            distanceOrder = distanceOrder,
            flying = flight.active or combatQuestID ~= nil, manual = manualQuestID ~= nil or addon.ExcursionPlan.Current(insights.excursion) ~= nil, routeChains = routeChains,
            onTaxi = flight.active, detour = temporaryDetour ~= nil,
            feedback = temporaryFeedback, now = SessionTime(),
            campAvoidance = campAvoidance,
            previousCamps = insights.previousCamps,
            previousPresence = insights.presence,
            capacity = questCapacity,
            xpNeeded = addon.QuestLog.GetXPToNextLevel(),
            questMarkers = questMarkers,
            measurableQuestIDs = measurableQuestIDs,
            distanceMaps = distanceMaps,
            previousObjectives = previousObjectives,
            objectiveLock = objectiveLock,
            avoidedObjectives = avoidedObjectives,
            eligibleQuests = eligibleQuests,
            savedAccessPoints = savedAccessPoints,
            passedAccessPoints = passedAccessPoints,
            turnInLocations = turnInLocations,
            questTargetMaps = questTargetMaps,
        })
        addon.Performance:Finish("planning", performanceStart)
        navigationSnapshot = snapshot
        insights.previousCamps = snapshot.previousCamps
        insights.presence = snapshot.presence
        questMeasurements, objectiveDistances = snapshot.measurements, snapshot.objectiveDistances
        previousObjectives, objectiveLock = snapshot.previousObjectives, snapshot.objectiveLock
        questJourneys, distanceOrder = snapshot.journeys, snapshot.distanceOrder
        local measurements, ranked, playerLevel = snapshot.measurements, snapshot.ranked, snapshot.playerLevel
        if flight.active then
            local found
            for _, candidate in ipairs(ranked) do if candidate.id == flight.questID then found = true break end end
            if not found then flight.questID = ranked[1] and ranked[1].id end
        end
        local routeQuest, route = snapshot.routeQuest, snapshot.route
        local xpNeeded, levelUpQuest, nextQuest = snapshot.xpNeeded, snapshot.levelUpQuest, snapshot.nextQuest
        local note, details
        local trip = not (flight.active or combatQuestID) and UpdateOuting(snapshot.planningRanked, measurements, playerLevel, levelUpQuest or routeQuest or objectiveLock)
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
        snapshot.decision = levelUpQuest and "levelUp" or trip and "outing" or route and "followUp" or "ranking"
        snapshot.decisionSaving = not levelUpQuest and ((trip and trip.saving) or (route and route.saving)) or nil
        RenderQuestList(ranked, routeQuest, note, details, playerLevel, xpNeeded, nextQuest, forecast)
        tracker:SetFlightView(flight.active, FlightStep(shownQuests[1]))
        UpdateMapMarker()
        local activeMeasurement = snapshot.activeMeasurement
        activeDirection = activeMeasurement and activeMeasurement.east and activeMeasurement or nil
        tracker:RenderDistances(measurements)
        if RefreshNearbyOffers and (not insights.offersAt or SessionTime() - insights.offersAt >= 5) then
            RefreshNearbyOffers(distanceMaps, questTargetMaps, Enum and Enum.UIMapType)
        end
        UpdateDirectionTicker()
    end
end

local function UpdateDistanceTicker()
    UpdateFlightState()
    if TrackingVisible() and measurableQuestIDs then
        UpdateDistances()
        if not tickers.distance then
            tickers.distance = C_Timer.NewTicker(1, function() UpdateDistances(false) end)
        end
    else
        if tickers.distance then
            tickers.distance:Cancel()
            tickers.distance = nil
        end
        activeDirection = nil
        UpdateDirectionTicker()
    end
end

local function RenderEmpty(message)
    navigationSnapshot = nil
    insights.pickupPlanning = nil
    tracker:SetPickupPlanning(nil)
    tracker:SetDecisionBrief(nil)
    combatQuestID = nil
    eligibleQuests, shownQuests, distanceOrder, measurableQuestIDs = nil, nil, nil, nil
    outing = nil
    shown.reason, shown.routeDetails, questMeasurements = nil, nil, nil
    arrivalState = nil
    flight.questID = nil
    questJourneys = nil
    objectiveLock, previousObjectives = nil, {}
    UpdateMapMarker()
    tracker:Render(nil, message, skippedQuestIDs)
    UpdateDistanceTicker()
    addon.RefreshQuestNotepad()
end

local function UpdateQuestieTicker()
    if TrackingVisible() and integration.IsReady() and (settings.useQuestieKillLocations or settings.showQuestieOffers) then
        if not tickers.questie then
            tickers.questie = C_Timer.NewTicker(5, ScheduleRefresh)
            ScheduleRefresh()
        end
    elseif tickers.questie then
        tickers.questie:Cancel()
        tickers.questie = nil
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
            -- Keep completed special quests visible even without an outdoor pin.
            questMarkers[quest.id] = quest.readyToTurnIn and {} or nil
        end
    end
end

RefreshNearbyOffers = function(localMaps, targetMaps, mapType)
    insights.offersAt = SessionTime()
    local offers
    if settings.showQuestieOffers and tracker:IsVisible() and integration.IsReady() and UnitLevel then
        local level = UnitLevel("player")
        local active = shownQuests and GetQuestDestination(shownQuests[1].id)
        local offerAnchors = {}
        local plan = insights.excursion
        for index = plan and plan.index or 1, plan and #plan.stops or 0 do
            local stop = plan.stops[index]
            if stop.action == "accept" and not stop.done and #offerAnchors < 3 then offerAnchors[#offerAnchors + 1] = stop.target end
        end
        offers = integration.GetNearbyOffers(C_Map, C_QuestLog, localMaps, targetMaps, mapType,
            level, settings.questieOfferRadius, active and active.target, true, offerAnchors)
    end
    offers = offers and addon.MixedQuestPlan.Filter(offers, insights.hiddenOffers,
        insights.excursion and insights.excursion.excludedOffers, insights.offerSuppressed)
    offers = offers and addon.RepeatablePolicy.Offers(offers, settings.repeatablePolicy)
    nearbyOffers = offers and #offers > 0 and offers or nil
    if offers then
        addon.PlanningInsights.AnnotateOffers(C_Map, offers, eligibleQuests, questMeasurements or {}, shownQuests and shownQuests[1],
            questCapacity)
    end
    local pickupPlan = addon.PickupPlanning.Build(C_Map, offers, eligibleQuests, questMeasurements or {},
        shownQuests and shownQuests[1], navigationSnapshot and navigationSnapshot.capacity or questCapacity,
        navigationSnapshot and navigationSnapshot.playerLevel or (UnitLevel and UnitLevel("player")), navigationSnapshot and navigationSnapshot.feedback,
        navigationSnapshot and navigationSnapshot.chains, mapType, nil, navigationSnapshot and navigationSnapshot.finishers)
    if offers then
        local fresh
        seenRecommendedOffers, fresh = addon.TrackerState.NewOffers(seenRecommendedOffers, offers)
        tracker:SetNewOffers(fresh)
    end
    if navigationSnapshot then navigationSnapshot.pickupPlanning = pickupPlan end
    insights.pickupPlanning = pickupPlan
    if navigationSnapshot then
        navigationSnapshot.brief = BuildDecisionBrief(navigationSnapshot, Enum and Enum.UIMapType)
        tracker:SetDecisionBrief(navigationSnapshot.brief)
    else
        tracker:SetDecisionBrief(BuildDecisionBrief({pickupPlanning = pickupPlan, capacity = questCapacity}, mapType))
    end
    tracker:SetPickupPlanning(pickupPlan)
    tracker:RenderNearbyOffers(nearbyOffers, settings.showQuestXP)
    UpdateDirectionTicker()
end

function addon.PauseExcursion()
    if insights.excursion then insights.excursion.running = false end
    if temporaryDetour and temporaryDetour.excursion then
        temporaryDetour, detourMeasurement = nil, nil
        tracker:SetDetour(nil)
    end
end
function addon.SyncExcursion(quests)
    if addon.RecoveryState and addon.RecoveryState.active then return end
    local plan = insights.excursion
    if not (plan and plan.running) then return end
    addon.ExcursionPlan.Sync(plan, quests, C_QuestLog and C_QuestLog.GetQuestObjectives,
        C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted, skippedQuestIDs)
    local stop = addon.ExcursionPlan.Current(plan)
    if stop and stop.action == "accept" then
        if questCapacity and questCapacity.full then plan.status = L.QuestLogFull addon.PauseExcursion() return end
        temporaryDetour = addon.TemporaryDetour.New(stop.target.mapID, stop.target.x, stop.target.y, L.ExcursionAction_accept)
        if not temporaryDetour then plan.status = L.ExcursionStale addon.PauseExcursion() return end
        temporaryDetour.name = L.ExcursionAction_accept .. ": " .. (stop.quest.title or "")
        temporaryDetour.excursion, temporaryDetour.questID = true, stop.quest.id
    elseif temporaryDetour and temporaryDetour.excursion then
        temporaryDetour, detourMeasurement = nil, nil tracker:SetDetour(nil)
    end
end

local function UpdateSharedItems()
    insights.sharedItems = addon.QuestInsights.SharedItems(eligibleQuests,
        function(id) return C_QuestLog.GetQuestObjectives and C_QuestLog.GetQuestObjectives(id) end,
        integration.GetObjectiveItemID, C_Item and C_Item.GetItemCount or GetItemCount, GetItemInfo)
end

local function Refresh()
    refreshPending = false
    addon.UpdateRecovery()
    movementState = nil
    addon.QuestRewards.Clear()
    navigationSnapshot = nil
    routeChains = nil
    turnInLocations, questJourneys = {}, nil
    questMeasurements = nil
    objectiveDistances = nil
    questDestinations = {}
    local quests, used = addon.QuestLog.Read(C_QuestLog)
    insights.combatMarkers = integration.GetCombatMarkers(quests, C_QuestLog)
    insights.newlyAccepted = {}
    if quests then
        local present = {}
        for _, quest in ipairs(quests) do
            present[quest.id] = true
            if insights.previousQuestIDs and not insights.previousQuestIDs[quest.id] then insights.newlyAccepted[quest.id] = true end
        end
        insights.previousQuestIDs = present
        for id in pairs(insights.previousCamps or {}) do if not present[id] then insights.previousCamps[id] = nil end end
    end
    addon.OutingLedger.Sync(insights.roundLedger, quests, C_QuestLog and C_QuestLog.GetQuestObjectives,
        C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted)
    if workspace then workspace:Sync(quests, skippedQuestIDs) end
    if not insights.lastLevel or insights.lastLevel <= 0 then
        local level = UnitLevel and UnitLevel("player")
        if type(level) == "number" and level > 0 then insights.lastLevel = level end
    end
    questCapacity = addon.QuestCapacity.FromCount(used, C_QuestLog, MAX_QUESTLOG_QUESTS)
    addon.SyncExcursion(quests)
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
    addon.AdventureSupport.ApplyCorrections(questMarkers, quests, targetCorrections, C_QuestLog.GetQuestObjectives)
    local explicitID = manualQuestID or (workspace and workspace:Current())
    if explicitID then
        for _, quest in ipairs(quests) do
            if quest.id == explicitID and (not quest.special or quest.readyToTurnIn) then
                questMarkers[quest.id] = questMarkers[quest.id] or {}
                break
            end
        end
    end
    eligibleQuests = addon.QuestPrioritizer.Rank(quests, skippedQuestIDs, questMarkers)
    local excursionStop = addon.ExcursionPlan.Current(insights.excursion)
    eligibleQuests = addon.RepeatablePolicy.Quests(eligibleQuests, settings.repeatablePolicy,
        manualQuestID or workspace and workspace:Current() or excursionStop and excursionStop.quest.id)
    UpdateSharedItems()
    if insights.pendingLevel then
        insights.levelReport = {entries = addon.QuestInsights.LevelChanges(eligibleQuests, insights.pendingLevel.before, insights.pendingLevel.after),
            deadline = SessionTime() + 60}
        insights.pendingLevel = nil
    end
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
    addon.AdventureSupport.ApplyCorrections(questMarkers, eligibleQuests, targetCorrections, C_QuestLog.GetQuestObjectives)
    local seenMeasurements = {}
    for _, id in ipairs(measured) do seenMeasurements[id] = true end
    for _, quest in ipairs(eligibleQuests) do
        if not seenMeasurements[quest.id] and questMarkers[quest.id] and #questMarkers[quest.id] > 0 then measured[#measured + 1] = quest.id end
    end
    if #eligibleQuests > 0 and integration.IsReady() then
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
    addon.RefreshQuestNotepad()
end

ScheduleRefresh = function()
    if not refreshPending then
        refreshPending = true
        -- In combat, coalesce bursts of quest-log events into fewer full rebuilds.
        C_Timer.After(InCombatLockdown and InCombatLockdown() and 1 or 0.1, Refresh)
    end
end

-- Light path for bag, gear and mount changes: quest log and markers are unchanged.
local function RefreshItems()
    if refreshPending then return end
    if not (eligibleQuests and measurableQuestIDs and TrackingVisible()) then return ScheduleRefresh() end
    UpdateSharedItems()
    UpdateDistances()
    if RefreshNearbyOffers then RefreshNearbyOffers(distanceMaps, questTargetMaps, Enum and Enum.UIMapType) end
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

local function ApplyQuestAction(action, value)
    if action == "prioritize" then addon.PauseExcursion() end
    local state = { held = heldQuest, manual = manualQuestID, lock = objectiveLock, outing = outing,
        flying = flight.active, flightID = flight.questID, quest = shownQuests and shownQuests[1],
        distances = objectiveDistances, avoided = avoidedObjectives, previous = previousObjectives,
        skipped = skippedQuestIDs, order = skipOrder }
    local effect = addon.QuestActions.Apply(state, action, value)
    heldQuest, manualQuestID, objectiveLock, outing = state.held, state.manual, state.lock, state.outing
    flight.questID, avoidedObjectives, skipOrder = state.flightID, state.avoided, state.order
    if workspace then
        if effect.selection then
            workspace.pending = nil
            if manualQuestID then
                workspace.plan.running = false
                workspace.context.cancelReturn()
            end
        end
        workspace:Save()
    end
    if effect.selection then UpdateQuestLogButton() end
    if effect.undo then tracker:ShowUndoSkip(effect.undo) end
    if effect.refresh then ScheduleRefresh() end
    if effect.measure then UpdateDistances() end
end

local function SelectQuest(questID)
    insights.levelHold = nil
    if questID or addon.ExcursionPlan.Current(insights.excursion) then addon.PauseExcursion() end
    ApplyQuestAction("select", questID)
end

local function ToggleQuestHold()
    addon.PauseExcursion()
    ApplyQuestAction("hold")
end

local function SelectObjective(index)
    ApplyQuestAction("objective", index)
end

local function AvoidObjective(index)
    ApplyQuestAction("avoid", index)
end

local function RestoreAvoidedObjectives()
    ApplyQuestAction("restoreObjectives")
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
    if marker and ((objectiveMarkers and objectiveMarkers[questID]) or marker.objective or marker.outdoorTurnIn or marker.personalCorrection) then
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
    addon.ShowQuestMapMarker(target, ClearMapMarker, CurrentMapRoute(questID))
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
    addon.ShowQuestMapMarker(offer.marker, ClearMapMarker, {{target = offer.marker, quest = offer, single = true}})
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

local function SwitchCamp(questID)
    local quest
    for _, candidate in ipairs(eligibleQuests or {}) do if candidate.id == questID then quest = candidate break end end
    local current = quest and questMeasurements and questMeasurements[questID]
    local alternative = quest and addon.CampAlternatives.Switch(C_Map, quest, current, questMarkers[questID], campAvoidance, SessionTime())
    if not alternative then print(L.NoAlternativeCamp) return end
    local held = heldQuest
    SelectQuest(questID)
    if held and held.id == questID then heldQuest = held end
    objectiveLock = {questID = questID, index = alternative.objectiveIndex}
    previousObjectives[questID], outing = nil, nil
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
        local before = addon.UndoHistory.Copy(savedAccessPoints[questID] and savedAccessPoints[questID][key])
        if addon.TravelSupport.SaveAccess(savedAccessPoints, questID, target, point, name) then
            for _, quest in ipairs(eligibleQuests or {}) do
                if quest.id == questID then savedAccessPoints[questID][key].questTitle = quest.title break end
            end
            passedAccessPoints[questID .. ":" .. key] = nil
            RecordAccessChange(questID, key, before)
            outing = nil
            print(L.AccessSaved)
            ScheduleRefresh()
        end
    end
    local chosen
    for _, quest in ipairs((isOffer and nearbyOffers or eligibleQuests) or {}) do
        if quest.id == questID then chosen = quest break end
    end
    local function Submenu(menu, label)
        return menu:CreateButton(label) or menu
    end
    local function Feedback(kind)
        local before = addon.UndoHistory.Copy(temporaryFeedback)
        if kind == "area" then
            addon.RecommendationFeedback.SetArea(temporaryFeedback, C_Map, eligibleQuests, questMeasurements or {}, target, SessionTime())
        else
            addon.RecommendationFeedback.Set(temporaryFeedback, chosen, questMeasurements and questMeasurements[questID], kind, SessionTime())
        end
        if addon.Undo then addon.Undo:Capture(L.FeedbackSubmenu, function() return temporaryFeedback end, function(value)
            temporaryFeedback = value outing = nil ScheduleRefresh()
        end, before, temporaryFeedback) end
        outing = nil
        ScheduleRefresh()
    end
    MenuUtil.CreateContextMenu(owner, function(_, menu)
        menu:CreateTitle(L.QuestActionsMenu)
        menu:SetScrollMode(260)
        menu:CreateButton(L.OpenQuestMap, function() if isOffer then OpenOfferMap(questID) else OpenQuestMap(questID) end end)
        if isOffer and chosen then
            menu:CreateButton(L.OfferSkip, function() addon.SkipCurrentOffer(questID, "once") end)
            menu:CreateButton(L.OfferLater, function() addon.SkipCurrentOffer(questID, "later") end)
            menu:CreateButton(L.OfferHide, function() addon.SkipCurrentOffer(questID, "hide") end)
        end
        if not isOffer and CanPinQuest(questID) then
            menu:CreateButton(manualQuestID == questID and L.ClearActiveQuest or L.SetActiveQuest,
                function() if manualQuestID == questID then SelectQuest(nil) else SelectQuest(questID) end end)
            local priorityMenu = Submenu(menu, L.PriorityMenu)
            if chosen and not chosen.readyToTurnIn then
                priorityMenu:CreateButton(L.PriorityUntilComplete, function() ApplyQuestAction("prioritize", {id = questID}) end)
            end
            priorityMenu:CreateButton(L.PriorityUntilTurnIn, function() ApplyQuestAction("prioritize", {id = questID, turnIn = true}) end)
        end
        local more = Submenu(menu, L.MoreActions)
        if chosen then
            local later = Submenu(more, L.JourneyLaterMenu)
            for _, when in ipairs({"round", "visit", "group"}) do
                local trigger = when
                later:CreateButton(L["JourneyLater_" .. trigger], function()
                    if addon.DemoMode.IsActive() then return end
                    local point = isOffer and chosen.marker or target
                    local zone = point and addon.QuestLocation.GetZone(C_Map, Enum and Enum.UIMapType, point.mapID)
                    addon.JourneyPlanning.SetLater(insights.laterQuests, chosen, point, trigger, zone or point and point.mapID, addon.GetLaterContext())
                    ScheduleRefresh()
                end)
            end
            later:CreateButton(L.Adventure_later, function() addon.OpenAdventure("later") end)
        end
        more:CreateButton(L.EditQuestNote, function() addon.OpenQuestNote(questID, isOffer) end)
        if not isOffer and navigationSnapshot and navigationSnapshot.camps and navigationSnapshot.camps[questID] then
            more:CreateButton(L.CampChoices, function() addon.OpenCampChoices(questID) end)
        end
        if not isOffer and shownQuests and shownQuests[1] and shownQuests[1].id == questID then
            more:CreateButton(heldQuest and heldQuest.id == questID and L.ReleaseQuest or L.HoldQuest, ToggleQuestHold)
        end
        more:CreateButton(questNotes[questID] and L.UnmarkQuest or L.MarkQuest, function()
            local point = isOffer and chosen and chosen.marker or target
            addon.QuestTools.ToggleNote(questNotes, questID, chosen and chosen.title, point, isOffer)
            insights.noteRevision = (insights.noteRevision or 0) + 1 ScheduleRefresh()
            addon.RefreshQuestNotepad()
        end)
        if chosen and not isOffer and addon.CampAlternatives.Find(C_Map, chosen, measured, questMarkers[questID], campAvoidance, SessionTime()) then
            more:CreateButton(L.AnotherCamp, function() SwitchCamp(questID) end)
        end
        more:CreateButton(L.PlanningOverview, function() ShowPlanning() end)
        if chosen and not isOffer then
            menu:CreateButton(L.AdventureBlockedAction, function()
                Feedback("blocked") addon.PauseExcursion() addon.OpenAdventure("blocked", questID)
            end)
            local tourMenu = Submenu(menu, L.MyTour)
            tourMenu:CreateButton(L.AddToTour, function()
                if workspace then workspace:Action("add", {quest = chosen}) addon.OpenWorkspace("tour") end
            end)
            tourMenu:CreateButton(L.MyTour, function() addon.OpenWorkspace("tour") end)
        end
        local feedbackMenu = Submenu(more, L.FeedbackSubmenu)
        if chosen and not isOffer then
            feedbackMenu:CreateButton(L.FeedbackHard, function() Feedback("hard") end)
            feedbackMenu:CreateButton(L.FeedbackBlocked, function() Feedback("blocked") end)
            feedbackMenu:CreateButton(L.FeedbackInconvenient, function() Feedback("inconvenient") end)
            feedbackMenu:CreateButton(L.FeedbackNoMobs, function() Feedback("empty") end)
            feedbackMenu:CreateButton(L.FeedbackGroup, function() Feedback("group") end)
            feedbackMenu:CreateButton(L.FeedbackAccess, function() Feedback("access") end)
            feedbackMenu:CreateButton(L.FeedbackArea, function() Feedback("area") end)
            if temporaryFeedback[questID] then
                feedbackMenu:CreateButton(L.FeedbackClear, function() ClearTemporaryFeedback(questID) end)
            end
            if campAvoidance[questID] then
                feedbackMenu:CreateButton(L.RestoreCamps, function() campAvoidance[questID] = nil outing = nil ScheduleRefresh() end)
            end
        end
        feedbackMenu:CreateButton(L.FeedbackManager, function() ShowFeedback() end)
        if chosen and not isOffer then
            if chosen.readyToTurnIn or target and target.objectiveIndex then more:CreateButton(L.AdventureCorrectHere, function()
                if addon.DemoMode.IsActive() or IsInInstance and IsInInstance() then return end
                local mapID = C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
                local pos = mapID and C_Map.GetPlayerMapPosition and C_Map.GetPlayerMapPosition(mapID, "player")
                if pos and not (issecretvalue and issecretvalue(pos)) and addon.AdventureSupport.Correct(targetCorrections, chosen,
                    {mapID = mapID, x = pos.x, y = pos.y}, target and target.objectiveIndex) then
                    ScheduleRefresh()
                end
            end) end
            if targetCorrections[questID] then more:CreateButton(L.AdventureCorrections, function() addon.OpenAdventure("corrections") end) end
        end
        if not (isOffer or ready or not target) then
            local access = Submenu(more, L.AccessSubmenu)
            local saved = addon.TravelSupport.GetAccess(savedAccessPoints, questID, target, C_Map)
            local steps = saved and addon.TravelSupport.AccessSteps(saved)
            access:CreateButton(steps and #steps > 1 and L.ReplaceAccessHere or L.SaveAccessHere, function()
                if IsInInstance and IsInInstance() then print(L.AccessUnavailable) return end
                local mapID = C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
                local point = mapID and C_Map.GetPlayerMapPosition and C_Map.GetPlayerMapPosition(mapID, "player")
                Save(point and {mapID = mapID, x = point.x, y = point.y}, L.SavedAccess)
            end)
            if saved then
                if #steps < 8 then access:CreateButton(L.AppendAccessHere, function()
                    local before = addon.UndoHistory.Copy(savedAccessPoints[questID][key])
                    if IsInInstance and IsInInstance() then print(L.AccessUnavailable) return end
                    local mapID = C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
                    local position = mapID and C_Map.GetPlayerMapPosition and C_Map.GetPlayerMapPosition(mapID, "player")
                    local point = position and {mapID = mapID, x = position.x, y = position.y}
                    if not point or not addon.QuestLocation.IsOutdoorMap(C_Map, Enum and Enum.UIMapType, mapID, questTargetMaps)
                        or not addon.TravelSupport.AppendAccess(savedAccessPoints, questID, target, point, C_Map) then
                        print(L.AccessAppendUnavailable) return
                    end
                    local route = savedAccessPoints[questID][key]
                    if flight.active then passedAccessPoints[questID .. ":" .. key] = nil
                    else passedAccessPoints[questID .. ":" .. key] = {entry = route, revision = route.revision,
                        index = #addon.TravelSupport.AccessSteps(route) + 1} end
                    outing = nil
                    RecordAccessChange(questID, key, before)
                    addon.RefreshAccessManager() ScheduleRefresh()
                end) end
                access:CreateButton(L.ReuseAccess, function()
                    passedAccessPoints[questID .. ":" .. key] = nil outing = nil ScheduleRefresh()
                end)
                access:CreateButton(L.ClearAccess, function()
                    local before = addon.UndoHistory.Copy(savedAccessPoints[questID][key])
                    savedAccessPoints[questID][key] = nil
                    RecordAccessChange(questID, key, before)
                    passedAccessPoints[questID .. ":" .. key] = nil outing = nil ScheduleRefresh()
                end)
            end
            for _, hint in ipairs(addon.QuestieRoutes.GetAccessHints(C_Map, Enum and Enum.UIMapType, questTargetMaps or {}, questID, target)) do
                local point, text = hint.point, hint.text
                access:CreateButton(L.AccessHintMap:format(text), function() OpenRouteStop({target = point}) end)
                access:CreateButton(L.UseAccessHint:format(text), function() Save(point, text) end)
            end
        end
        local diagnostic = Submenu(more, L.SettingsDiagnostics)
        diagnostic:CreateButton(L.PositionReport, function() ShowTargetReport(questID, isOffer) end)
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
        filter = function(entries, query, mode) return addon.QuestTools.FilterAccess(entries, query, mode, C_QuestLog) end,
        map = function(entry) OpenRouteStop({ target = entry.point }) end,
        rename = function(entry, name)
            local changed = addon.TravelSupport.RenameAccess(savedAccessPoints, entry.questID, entry.index, name)
            if changed then Changed(entry) end
            return changed
        end,
        remove = function(entry)
            local before = addon.UndoHistory.Copy(savedAccessPoints[entry.questID] and savedAccessPoints[entry.questID][entry.index])
            addon.TravelSupport.RemoveAccess(savedAccessPoints, entry.questID, entry.index)
            RecordAccessChange(entry.questID, entry.index, before)
            Changed(entry)
        end,
        route = function(entry)
            addon.ShowAccessRouteEditor({
                list = function()
                    local objectives = savedAccessPoints[entry.questID]
                    return addon.TravelSupport.AccessSteps(objectives and objectives[entry.index]) or {}
                end,
                map = function(point) OpenRouteStop({target = point}) end,
                note = function(step, text)
                    local before = addon.UndoHistory.Copy(savedAccessPoints[entry.questID] and savedAccessPoints[entry.questID][entry.index])
                    if addon.TravelSupport.SetAccessNote(savedAccessPoints, entry.questID, entry.index, step, text) then
                        RecordAccessChange(entry.questID, entry.index, before) ScheduleRefresh()
                    end
                end,
                move = function(step, delta)
                    local before = addon.UndoHistory.Copy(savedAccessPoints[entry.questID] and savedAccessPoints[entry.questID][entry.index])
                    if addon.TravelSupport.MoveAccessStep(savedAccessPoints, entry.questID, entry.index, step, delta) then RecordAccessChange(entry.questID, entry.index, before) Changed(entry) addon.RefreshAccessManager() end
                end,
                remove = function(step)
                    local before = addon.UndoHistory.Copy(savedAccessPoints[entry.questID] and savedAccessPoints[entry.questID][entry.index])
                    if addon.TravelSupport.RemoveAccessStep(savedAccessPoints, entry.questID, entry.index, step) then RecordAccessChange(entry.questID, entry.index, before) Changed(entry) addon.RefreshAccessManager() end
                end,
            })
        end,
    })
end

local function ShowNotepad()
    addon.ShowQuestNotepad({
        list = function()
            return addon.QuestTools.Notes(questNotes, C_QuestLog, function(id)
                if C_QuestLog.IsOnQuest and C_QuestLog.IsOnQuest(id) then
                    local destination = GetQuestDestination(id)
                    return destination and destination.target
                end
            end)
        end,
        map = function(entry) if entry.point then OpenRouteStop({ target = entry.point }) end end,
        remove = function(id) questNotes[id] = nil insights.noteRevision = (insights.noteRevision or 0) + 1 ScheduleRefresh() end,
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
    ApplyQuestAction("skip", quest)
end

local function RestoreQuest(questID)
    ApplyQuestAction("restore", questID)
end

local function ResetSkips()
    ApplyQuestAction("resetSkips")
end

local function ShowZones()
    addon.ShowZoneOverview(function()
        if not TrackingVisible() and measurableQuestIDs and not refreshPending then UpdateDistances(false) end
        return addon.BuildZoneOverview(C_Map, Enum and Enum.UIMapType, eligibleQuests, navigationSnapshot)
    end, function(marker) OpenRouteStop({ target = marker }) end)
end

local function ShowFixture()
    local fixture = addon.RegressionFixture.Capture(eligibleQuests, navigationSnapshot)
    addon.ShowTextWindow("fixture", fixture and addon.RegressionFixture.Encode(fixture) or L.NoFixture,
        L.ExportFixture, L.FixtureHelp)
end

ShowPlanning = function()
    return addon.ShowPlanningOverview(function()
        if not TrackingVisible() and measurableQuestIDs and not refreshPending then UpdateDistances(false) end
        return navigationSnapshot or {pickupPlanning = insights.pickupPlanning, capacity = questCapacity,
            brief = addon.DecisionBrief.Build({pickupPlanning = insights.pickupPlanning, capacity = questCapacity}, insights.roundLedger)}
    end, OpenRouteStop)
end

function addon.OpenQuestNote(id, isOffer)
    if addon.DemoMode.IsActive() then print("FQN | " .. L.DemoReadOnly) return end
    local chosen
    for _, quest in ipairs((isOffer and nearbyOffers or addon.QuestLog.Read(C_QuestLog)) or {}) do if quest.id == id then chosen = quest break end end
    local m = isOffer and chosen or questMeasurements and questMeasurements[id]
    local point = m and m.marker
    return addon.ShowQuestNoteEditor(id, chosen and chosen.title, questNotes[id] and questNotes[id].text, function(text)
        local before = addon.UndoHistory.Copy(questNotes[id])
        addon.QuestTools.SetNoteText(questNotes, id, chosen and chosen.title, point, isOffer, text)
        insights.noteRevision = (insights.noteRevision or 0) + 1
        if addon.Undo then addon.Undo:Capture(L.EditQuestNote, function() return questNotes[id] end, function(value)
            questNotes[id] = value insights.noteRevision = (insights.noteRevision or 0) + 1 ScheduleRefresh() addon.RefreshQuestNotepad()
        end, before, questNotes[id]) end
        ScheduleRefresh() addon.RefreshQuestNotepad()
    end)
end
function addon.GetQuestNoteText(id)
    local note = questNotes[id]
    return type(note) == "table" and type(note.text) == "string" and note.text or nil
end
function addon.OpenCampChoices(id)
    if addon.DemoMode.IsActive() then return end
    addon.ShowCampChoices(function() return navigationSnapshot and navigationSnapshot.camps and navigationSnapshot.camps[id] end,
        OpenRouteStop, function(choice)
            insights.previousCamps = insights.previousCamps or {}
            insights.previousCamps[id] = {mapID = choice.target.mapID, x = choice.target.x, y = choice.target.y,
                objectiveIndex = choice.target.objectiveIndex, manual = true}
            ScheduleRefresh()
        end)
end
function addon.OpenExcursionFromArea(key, review, override, excluded)
    if addon.DemoMode.IsActive() then print("FQN | " .. L.DemoReadOnly) return end
    local planning = insights.pickupPlanning
    local area = planning and planning.destination
    if override then area = override end
    if key then
        area = nil
        for _, candidate in ipairs(planning and planning.areas or {}) do if candidate.entries[1].quest.id == key then area = candidate break end end
    end
    local options = {api = C_Map, level = UnitLevel and UnitLevel("player"), hidden = insights.hiddenOffers,
        feedback = navigationSnapshot and navigationSnapshot.feedback,
        excluded = excluded or override and insights.excursion and insights.excursion.excludedOffers,
        fromPlayer = function(point) local m = addon.TemporaryDetour.Measure(C_Map, point) return m and m.yards end}
    if not review then area = addon.MixedQuestPlan.Gather(area, eligibleQuests, questMeasurements, options) end
    local plan = review and insights.excursion or addon.ExcursionPlan.Build(area, questCapacity, function(quest, origin)
        local measured = quest.readyToTurnIn and navigationSnapshot and navigationSnapshot.measurements and navigationSnapshot.measurements[quest.id]
        if measured and not measured.objectiveMarker and addon.TravelSupport.ValidPoint(measured.marker) then return measured.marker end
        if not integration.IsReady() then return end
        return addon.QuestieRoutes.GetOutdoorTurnInMarker(C_Map, Enum and Enum.UIMapType, questTargetMaps or {}, quest.id, origin)
    end, function(quest, pickup)
        if pickup then return quest.xp end
        return addon.QuestLog.GetTurnInXP(quest)
    end, options)
    if review and plan and plan.needsReview then
        plan = addon.MixedQuestPlan.Refresh(plan, addon.QuestLog.Read(C_QuestLog), questMeasurements, navigationSnapshot and navigationSnapshot.finishers)
    end
    if not review then plan = addon.AdventureSupport.Budget(plan, insights.tourMinutes, C_Map) end
    return addon.ReviewPreparedOuting(plan, function(minutes, exclusions) insights.tourMinutes = minutes return addon.OpenExcursionFromArea(key, false, override, exclusions) end)
end

function addon.ReviewPreparedOuting(plan, budget)
    return addon.ShowExcursion(plan, {
        map = OpenRouteStop,
        start = function(candidate)
            local wasStarted = candidate.started
            local ok, reason = addon.ExcursionPlan.Start(candidate, addon.QuestLog.Read(C_QuestLog), nearbyOffers,
                C_QuestLog.IsQuestFlaggedCompleted, questCapacity)
            if not ok then return false, reason end
            if not wasStarted then insights.offerSuppressed = {} end
            local previous = insights.excursion
            if previous and previous.started and previous.index <= #previous.stops then candidate.journeyKey = previous.journeyKey end
            addon.PauseExcursion()
            candidate.running = true insights.excursion = candidate
            manualQuestID, heldQuest, objectiveLock, outing = nil, nil, nil, nil
            temporaryDetour, detourMeasurement = nil, nil
            if workspace then workspace.plan.running = false workspace:Save() end
            ScheduleRefresh() return true
        end,
        pause = function() addon.PauseExcursion() ScheduleRefresh() end,
        dismiss = function()
            if insights.excursion then
                insights.excursion.reviewDismissed = true
                if insights.excursion.index > #insights.excursion.stops then insights.excursion.excludedOffers, insights.offerSuppressed = {}, {} end
            end
            ScheduleRefresh()
        end,
        budget = budget,
        skip = function(id, mode) return addon.SkipOfferStep(plan, id, mode) end,
        undo = function() return addon.Undo:Undo() end,
        canUndo = function() return addon.OfferUndoAvailable(plan) end,
    })
end

function addon.OpenOutingReview()
    if insights.excursion then return addon.OpenExcursionFromArea(nil, true) end
end

function addon.OpenAdventure(mode, blockedID)
    if addon.DemoMode.IsActive() then print("FQN | " .. L.DemoReadOnly) return end
    if blockedID then insights.blockedQuestID = blockedID end
    return addon.ShowAdventure(function(section)
        local snapshot = navigationSnapshot or {}
        local result = {rows = {}}
        if section == "along" then
            result.rows = addon.JourneyPlanning.Along(snapshot, C_Map) result.summary = L.JourneyAlongHelp
        elseif section == "compare" then
            result.rows = addon.JourneyPlanning.Tours(insights.pickupPlanning, C_Map) result.summary = L.JourneyCompareHelp
        elseif section == "chains" then
            insights.expandedChains = insights.expandedChains or {}
            result.rows = addon.JourneyPlanning.ChainRows(snapshot.chains, insights.expandedChains) result.summary = L.JourneyChainHelp
        elseif section == "later" then
            result.rows = addon.JourneyPlanning.Later(insights.laterQuests, addon.GetLaterContext(), C_QuestLog) result.summary = L.JourneyLaterHelp
            for _, e in ipairs(result.rows) do if e.due then e.short = L.JourneyLaterDue .. " · " .. e.short end end
        elseif section == "hiddenOffers" then
            result.summary = L.OfferHiddenHelp
            for id, q in pairs(insights.hiddenOffers) do
                result.rows[#result.rows + 1] = {quest = q, short = L.OfferHide, detail = L.OfferHiddenHelp, hiddenOffer = true}
            end
            table.sort(result.rows, function(a, b) return a.quest.id < b.quest.id end)
        elseif section == "bags" then
            local bags = addon.JourneyPlanning.Bags(C_Container, NUM_BAG_SLOTS)
            result.summary = (bags.known and L.JourneyFreeBags:format(bags.free) or L.JourneyBagsUnknown) .. "\n" .. L.JourneyBagsHelp
            local best
            if bags.low then for index, vendor in ipairs(insights.knownVendors) do
                local m = type(vendor) == "table" and addon.TravelSupport.ValidPoint(vendor.point) and addon.TemporaryDetour.Measure(C_Map, vendor.point)
                if m and (not best or m.yards < best.yards) then best = {quest = {id = 0, title = vendor.name or L.JourneyVendor},
                    target = vendor.point, vendorIndex = index, yards = m.yards, detail = L.JourneyVendorHelp} end
            end end
            if best then result.rows[1] = best end
            result.canSaveVendor = MerchantFrame and MerchantFrame.IsShown and MerchantFrame:IsShown() or false
        elseif section == "departure" then
            result.rows = addon.AdventureSupport.Departure(insights.pickupPlanning, questCapacity)
            result.summary = L.AdventureDepartureHelp
        elseif section == "blocked" then
            result.rows = addon.AdventureSupport.Alternatives(snapshot, insights.blockedQuestID or shownQuests and shownQuests[1] and shownQuests[1].id)
            result.summary = L.AdventureBlockedHelp
        elseif section == "group" then
            result.enabled = settings.groupQuestHints == true result.summary = L.AdventureGroupHelp
            if result.enabled then
                local units = {}
                local raid = IsInRaid and IsInRaid()
                for index = 1, raid and 40 or 4 do
                    local unit = (raid and "raid" or "party") .. index
                    if UnitExists and UnitExists(unit) and not (UnitIsUnit and UnitIsUnit(unit, "player")) then units[#units + 1] = unit end
                end
                local cached = insights.groupAdvice
                if not cached or cached.quests ~= eligibleQuests or SessionTime() - cached.at >= 5 then
                    cached = {quests = eligibleQuests, at = SessionTime(), rows = addon.AdventureSupport.Group(eligibleQuests, units, C_QuestLog)} insights.groupAdvice = cached
                end
                for _, e in ipairs(cached.rows) do
                    local m = snapshot.measurements and snapshot.measurements[e.quest.id]
                    result.rows[#result.rows + 1] = {quest = e.quest, target = m and m.marker,
                        short = L.AdventureShared:format(e.count, e.unknown), detail = L.AdventureShared:format(e.count, e.unknown) .. "\n" .. L.AdventureGroupHelp}
                end
            end
        elseif section == "level" then
            result.summary = L.AdventureLevelHelp
            for _, e in ipairs(insights.levelReport and insights.levelReport.entries or {}) do
                local m = snapshot.measurements and snapshot.measurements[e.quest.id]
                result.rows[#result.rows + 1] = {quest = e.quest, target = m and m.marker,
                    short = L["Difficulty_" .. e.before] .. " -> " .. L["Difficulty_" .. e.after], detail = L.AdventureLevelHelp}
            end
        elseif section == "changes" then
            result.rows = addon.AdventureSupport.Changes(insights.excursion, snapshot, C_Map)
            result.summary = L.AdventureChangeHelp
        elseif section == "corrections" then
            result.summary = L.AdventureCorrectionHelp
            for id, points in pairs(targetCorrections) do
                for index, point in pairs(type(points) == "table" and points or {}) do
                    if addon.TravelSupport.ValidPoint(point) then
                        local quest = {id = id}
                        for _, q in ipairs(eligibleQuests or {}) do if q.id == id then quest = q break end end
                        local text = L.AdventureCorrectionPoint:format(point.mapID, point.x * 100, point.y * 100)
                        result.rows[#result.rows + 1] = {quest = quest, target = point, index = index, short = text, detail = text .. "\n" .. L.AdventureCorrectionHelp}
                    end
                end
            end
            table.sort(result.rows, function(a, b) if a.quest.id ~= b.quest.id then return a.quest.id < b.quest.id end return a.index < b.index end)
        end
        return result
    end, {
        map = OpenRouteStop,
        select = function(id) addon.PauseExcursion() insights.levelHold = nil SelectQuest(id) end,
        toggleGroup = function() settings.groupQuestHints = not settings.groupQuestHints insights.groupAdvice = nil end,
        releaseLevel = function() insights.levelHold = nil ScheduleRefresh() end,
        clearCorrection = function(e) targetCorrections[e.quest.id][e.index] = nil ScheduleRefresh() end,
        rowAction = function(e, section)
            if section == "along" then
                local q
                for _, candidate in ipairs(eligibleQuests or {}) do if candidate.id == e.quest.id and candidate.readyToTurnIn then q = candidate break end end
                if not q then return end
                e.quest, e.xp = q, addon.QuestLog.GetTurnInXP(q)
                local revised = addon.JourneyPlanning.InsertHandIn(insights.excursion, e, C_Map)
                if revised then addon.ReviewPreparedOuting(revised)
                elseif not insights.excursion or not insights.excursion.started then
                    addon.OpenExcursionFromArea(nil, false, {entries = {{quest = q, target = e.target, yards = e.yards}}})
                end
            elseif section == "compare" then addon.OpenExcursionFromArea(e.areaKey)
            elseif section == "chains" then insights.expandedChains[e.chainID] = not insights.expandedChains[e.chainID]
            elseif section == "later" then insights.laterQuests[e.quest.id] = nil ScheduleRefresh() end
            if section == "hiddenOffers" then
                insights.hiddenOffers[e.quest.id] = nil
                insights.offerSuppressed[e.quest.id] = nil
                if insights.excursion and insights.excursion.excludedOffers then insights.excursion.excludedOffers[e.quest.id] = nil end
                ScheduleRefresh()
            end
            if section == "bags" and e.vendorIndex then table.remove(insights.knownVendors, e.vendorIndex) end
        end,
        saveVendor = function()
            if not (MerchantFrame and MerchantFrame.IsShown and MerchantFrame:IsShown() and GetMerchantNumItems) then return end
            local ok, count = pcall(GetMerchantNumItems)
            if not ok or type(count) ~= "number" or count < 1 then return end
            local id = C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
            local pos = id and C_Map.GetPlayerMapPosition and C_Map.GetPlayerMapPosition(id, "player")
            if not pos or (issecretvalue and issecretvalue(pos)) then return end
            local point = {mapID = id, x = pos.x, y = pos.y}
            if not addon.TravelSupport.ValidPoint(point) then return end
            local name = UnitName and UnitName("npc")
            insights.knownVendors[#insights.knownVendors + 1] = {point = point, name = type(name) == "string" and name or L.JourneyVendor}
            while #insights.knownVendors > 20 do table.remove(insights.knownVendors, 1) end
        end,
        reviewChanges = function()
            local p, snapshot = insights.excursion, navigationSnapshot or {}
            if not p then return end
            local area, seen = {entries = {}}, {}
            for index = p.index, #p.stops do
                local stop = p.stops[index]
                if stop.action == "accept" and not seen[stop.quest.id] then
                    local accepted
                    for _, q in ipairs(eligibleQuests or {}) do if q.id == stop.quest.id then accepted = true break end end
                    if not accepted and stop.quest.objectiveMarker then
                        area.entries[#area.entries + 1] = {quest = stop.quest, target = stop.quest.objectiveMarker, yards = stop.quest.journeyYards, pickup = true}
                        seen[stop.quest.id] = true
                    end
                end
                if stop.action ~= "accept" and not seen[stop.quest.id] then
                    local q
                    for _, candidate in ipairs(eligibleQuests or {}) do if candidate.id == stop.quest.id then q = candidate break end end
                    if q then
                        local m = snapshot.measurements and snapshot.measurements[q.id]
                        area.entries[#area.entries + 1] = {quest = q, target = m and (m.objectiveMarker or m.marker) or stop.target, yards = m and m.yards}
                        seen[q.id] = true
                    end
                end
            end
            for _, e in ipairs(addon.AdventureSupport.Changes(p, snapshot, C_Map)) do
                if not seen[e.quest.id] then area.entries[#area.entries + 1] = {quest = e.quest, target = e.target, yards = e.yards} seen[e.quest.id] = true end
            end
            addon.OpenExcursionFromArea(nil, false, area)
        end,
    }, mode)
end

function addon.GetLaterContext()
    local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local zone = mapID and addon.QuestLocation.GetZone(C_Map, Enum and Enum.UIMapType, mapID)
    local plan, ledger = insights.excursion, insights.roundLedger
    local source = plan and plan.started and plan or ledger
    if source and not source.journeyKey then source.journeyKey = tostring(GetServerTime and GetServerTime() or 0) .. ":" .. tostring(source) end
    return {mapID = zone or mapID, grouped = IsInGroup and IsInGroup() == true,
        roundToken = source and source.journeyKey,
        roundFinished = plan and plan.started and plan.index > #plan.stops or ledger and #ledger.steps > 0 and ledger.completed == #ledger.steps}
end

function addon.HideOffer(quest)
    if addon.DemoMode.IsActive() or not quest then return end
    local id, before = quest.id, addon.UndoHistory.Copy(insights.hiddenOffers[quest.id])
    insights.hiddenOffers[id] = {id = id, title = quest.title, level = quest.level}
    addon.Undo:Capture(L.OfferHide, function() return insights.hiddenOffers[id] end,
        function(value) insights.hiddenOffers[id] = value ScheduleRefresh() end, before, insights.hiddenOffers[id])
    ScheduleRefresh()
end

function addon.SkipOfferStep(plan, id, mode)
    if addon.DemoMode.IsActive() or (mode ~= "once" and mode ~= "later" and mode ~= "hide") then return false, L.ExcursionUnavailable end
    local quests, present = addon.QuestLog.Read(C_QuestLog), {}
    if not quests then return false, L.QuestLogUnavailable end
    for _, q in ipairs(quests) do present[q.id] = true end
    if C_QuestLog.IsOnQuest then for _, stop in ipairs(plan and plan.stops or {}) do
        local ok, accepted = pcall(C_QuestLog.IsOnQuest, stop.quest.id)
        if not ok then return false, L.QuestLogUnavailable end
        if accepted == true then present[stop.quest.id] = true end
    end end
    local before, hiddenBefore, laterBefore = addon.UndoHistory.Copy(plan), addon.UndoHistory.Copy(insights.hiddenOffers[id]), addon.UndoHistory.Copy(insights.laterQuests[id])
    local wasActive = plan == insights.excursion
    local ok, quest = addon.MixedQuestPlan.Skip(plan, id, present)
    if not ok then return false, L.OfferAlreadyAccepted end
    if mode == "hide" then insights.hiddenOffers[id] = {id = id, title = quest.title, level = quest.level}
    elseif mode == "later" then
        addon.JourneyPlanning.SetLater(insights.laterQuests, quest, quest.marker, "round", nil, addon.GetLaterContext())
    end
    local revision, index, receipts = plan.revision, plan.index, addon.UndoHistory.Copy(plan.receipts)
    local hiddenAfter, laterAfter = addon.UndoHistory.Copy(insights.hiddenOffers[id]), addon.UndoHistory.Copy(insights.laterQuests[id])
    local function CanUndo()
        if plan.revision ~= revision or plan.index ~= index or not addon.UndoHistory.Same(plan.receipts, receipts)
            or not addon.UndoHistory.Same(insights.hiddenOffers[id], hiddenAfter) or not addon.UndoHistory.Same(insights.laterQuests[id], laterAfter)
            or wasActive and insights.excursion ~= plan or C_QuestLog.IsOnQuest and C_QuestLog.IsOnQuest(id) then return false end
        return true
    end
    addon.Undo:Push(L.OfferSkipped, function()
        if not CanUndo() then return false end
        for key in pairs(plan) do plan[key] = nil end
        for key, value in pairs(addon.UndoHistory.Copy(before)) do plan[key] = value end
        insights.hiddenOffers[id], insights.laterQuests[id] = hiddenBefore, laterBefore
        ScheduleRefresh() return true
    end)
    addon.Undo.entries[#addon.Undo.entries].offerPlan = plan
    addon.Undo.entries[#addon.Undo.entries].offerValid = CanUndo
    if tracker then tracker.noticeMessage, tracker.noticeRemaining = L.OfferSkipped, 4 tracker:RefreshNotice() end
    ScheduleRefresh()
    return true, L.OfferSkipped
end

function addon.SkipCurrentOffer(id, mode)
    mode = mode or "once"
    local plan = insights.excursion
    for index = plan and plan.index or 1, plan and #plan.stops or 0 do
        local step = plan.stops[index]
        if step.action == "accept" and step.quest.id == id and not step.done then return addon.SkipOfferStep(plan, id, mode) end
    end
    if addon.DemoMode.IsActive() or (mode ~= "once" and mode ~= "later" and mode ~= "hide") then return false end
    local quest
    for _, offer in ipairs(nearbyOffers or {}) do if offer.id == id then quest = offer break end end
    if not quest or C_QuestLog.IsOnQuest and C_QuestLog.IsOnQuest(id) then return false end
    local function Read() return {hidden = insights.hiddenOffers[id], suppressed = insights.offerSuppressed[id], later = insights.laterQuests[id]} end
    local before = addon.UndoHistory.Copy(Read())
    insights.offerSuppressed[id] = true
    if mode == "hide" then insights.hiddenOffers[id] = {id = id, title = quest.title, level = quest.level}
    elseif mode == "later" then addon.JourneyPlanning.SetLater(insights.laterQuests, quest, quest.marker, "round", nil, addon.GetLaterContext()) end
    local after = addon.UndoHistory.Copy(Read())
    local function CanUndo()
        if not addon.UndoHistory.Same(Read(), after) or C_QuestLog.IsOnQuest and C_QuestLog.IsOnQuest(id) then return false end
        return true
    end
    addon.Undo:Push(L.OfferSkipped, function()
        if not CanUndo() then return false end
        insights.hiddenOffers[id], insights.offerSuppressed[id], insights.laterQuests[id] = before.hidden, before.suppressed, before.later
        ScheduleRefresh() return true
    end)
    addon.Undo.entries[#addon.Undo.entries].offerChoice = true
    addon.Undo.entries[#addon.Undo.entries].offerValid = CanUndo
    if tracker then tracker.noticeMessage, tracker.noticeRemaining = L.OfferSkipped, 4 tracker:RefreshNotice() end
    ScheduleRefresh() return true, L.OfferSkipped
end

function addon.OfferUndoAvailable(plan)
    local entry = addon.Undo.entries[#addon.Undo.entries]
    if not entry or not (entry.offerPlan or entry.offerChoice) or plan and entry.offerPlan ~= plan then return false end
    if entry.offerValid then local ok, value = pcall(entry.offerValid) return ok and value == true end
    return true
end

function addon.OpenPickupPlanning()
    local window = ShowPlanning()
    window:SelectMode("areas")
end

function addon.OpenDecisionPlanning(mode)
    local window = ShowPlanning()
    window:SelectMode(mode or "comparison")
end
function addon.RememberAdvisoryRound()
    if addon.DemoMode.IsActive() then print("FQN | " .. L.DemoReadOnly) return end
    insights.roundLedger = addon.OutingLedger.Start(insights.pickupPlanning, C_QuestLog.IsQuestFlaggedCompleted)
    print("FQN | " .. (insights.roundLedger and L.BriefRoundSaved or L.BriefRoundNone))
    ScheduleRefresh()
end
function addon.ForgetAdvisoryRound()
    insights.roundLedger = nil ScheduleRefresh()
end
function addon.ExportDecisionExplanation()
    local snapshot = navigationSnapshot or {}
    addon.ShowTextWindow("decision", addon.DecisionBrief.Report(snapshot, addon.DecisionBrief.Build(snapshot, insights.roundLedger, C_Map, Enum and Enum.UIMapType)),
        L.BriefReport, L.BriefReportPrivacy)
end

function addon.OpenWorkspace(mode)
    if addon.DemoMode.IsActive() then print("FQN | " .. L.DemoReadOnly) return end
    if workspace then return addon.ShowQuestWorkbench(workspace, mode) end
end
function addon.GetPlanningWorkspace() return workspace end
function addon.ResumePlan()
    if addon.DemoMode.IsActive() then print("FQN | " .. L.DemoReadOnly) return end
    if workspace then workspace:Action("resume") addon.OpenWorkspace("tour") end
end
function addon.ForgetRememberedNavigation()
    if workspace then workspace.pending = nil workspace:Save() end
end

ShowFeedback = function()
    addon.ShowFeedbackManager({
        list = function()
            return addon.RecommendationFeedback.List(temporaryFeedback, addon.QuestLog.Read(C_QuestLog), questMeasurements, SessionTime())
        end,
        clear = ClearTemporaryFeedback,
        clearAll = function() ClearTemporaryFeedback() end,
    })
end

ShowProfiles = function() addon.ShowAppearanceProfiles(settings, addon.SettingsController.catalog) end
function addon.OpenDetourTools()
    addon.ShowDetourTools({
        current = function()
            if temporaryDetour then return temporaryDetour end
            local id = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
            local position = id and C_Map.GetPlayerMapPosition and C_Map.GetPlayerMapPosition(id, "player")
            if position and not (issecretvalue and issecretvalue(position)) then
                return addon.TemporaryDetour.New(id, position.x, position.y)
            end
        end,
        active = function() return temporaryDetour ~= nil end,
        start = function(point)
            if not addon.TemporaryDetour.IsOutdoor(C_Map, Enum and Enum.UIMapType, point.mapID)
                or not addon.TemporaryDetour.Measure(C_Map, point) then return false end
            addon.PauseExcursion()
            point.questID = shownQuests and shownQuests[1] and shownQuests[1].id
            if workspace then workspace.plan.running = false workspace:Save() end
            temporaryDetour = point
            ScheduleRefresh() UpdateDirectionTicker()
            return true
        end,
        cancel = function()
            if temporaryDetour and temporaryDetour.tourReturn and workspace then workspace.plan.running = false workspace:Save() end
            temporaryDetour, detourMeasurement = nil, nil
            tracker:SetDetour(nil) ScheduleRefresh() UpdateDirection()
        end,
        map = function() if temporaryDetour then OpenRouteStop({target = temporaryDetour}) end end,
    })
end
ShowLevelChanges = function()
    local lines = {}
    for _, entry in ipairs(insights.levelReport and insights.levelReport.entries or {}) do
        lines[#lines + 1] = addon.UI.FormatQuestTitle(entry.quest) .. "\n"
            .. L["Difficulty_" .. entry.before] .. " -> " .. L["Difficulty_" .. entry.after]
    end
    addon.ShowTextWindow("levelChanges", #lines > 0 and table.concat(lines, "\n\n") or L.NoLevelChanges, L.LevelChangesTitle, L.LevelBetterHelp)
end

local function RegisterSettings()
    return addon.SettingsController.Register({
        getTracker = function() return tracker end,
        ShowZones = ShowZones, ShowFixture = ShowFixture,
        ShowPlanning = ShowPlanning,
        ShowFeedback = ShowFeedback, ShowProfiles = ShowProfiles, UpdateMapMarker = UpdateMapMarker,
        ShowHistory = function() addon.ShowUndoHistory(addon.Undo) end, ShowLevelChanges = ShowLevelChanges,
        settings = settings,
        ShowSession = ShowSession,
        ShowAccessManager = ShowAccessManager,
        ShowNotepad = ShowNotepad,
        UpdateQuestieTicker = UpdateQuestieTicker,
        ScheduleRefresh = ScheduleRefresh,
        SetDisplayMode = SetDisplayMode,
        UpdateDirectionTicker = UpdateDirectionTicker,
        RestoreAvoidedObjectives = RestoreAvoidedObjectives,
        ShowDiagnostics = ShowDiagnostics,
        DEFAULT_OPACITY = LIMITS.DEFAULT_OPACITY,
        DEFAULT_OFFER_RADIUS = LIMITS.DEFAULT_OFFER_RADIUS,
        MAX_OFFER_RADIUS = LIMITS.MAX_OFFER_RADIUS,
    })
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
    addon.ShowQuickSettings(addon.SettingsController.catalog, settings,
        function() Settings.OpenToCategory(settingsCategory:GetID()) end, ShowPlanning, ShowFeedback, ShowProfiles,
        function() addon.ShowUndoHistory(addon.Undo) end)
end

local function AddonVersion()
    return C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(addonName, "Version")
end

function addon.ConfigureUXHub()
    addon.UI.ToolHub.Configure({
        finder = function() addon.OpenWorkspace("finder") end, tour = function() addon.OpenWorkspace("tour") end,
        details = function() if tracker and tracker.OpenDetails then tracker:OpenDetails() end end,
        notes = ShowNotepad, feedback = ShowFeedback, automatic = ShowPlanning, zones = ShowZones,
        access = ShowAccessManager, detour = function() addon.OpenDetourTools() end,
        session = ShowSession, changes = function() addon.ShowUndoHistory(addon.Undo) end,
        settings = OpenSettings, profiles = ShowProfiles,
        share = function() addon.ShowDisplayTransfer(settings, addon.SettingsController.catalog) end,
        outing = function() addon.OpenExcursionFromArea(nil, insights.excursion ~= nil) end,
        adventure = function() addon.OpenAdventure() end,
        commands = function() addon.ShowCommandMenu(settings) end,
        whatsnew = function() addon.ShowReleaseNotes(settings, AddonVersion()) end,
        help = function() addon.ShowUXHelp({problem = addon.OpenProblemReport, diagnostic = ShowDiagnostics,
            guide = function() addon.ShowIntroduction(settings) end,
            updates = function() addon.ShowReleaseNotes(settings, AddonVersion()) end}) end,
    }, {simple = function() return settings and settings.simpleNavigator == true end, settings = settings})
end

local function InitializeWorkspace(character)
    workspace = addon.PlanningRuntime.New(character, settings, {
        priority = function() return manualQuestID, heldQuest end,
        read = function()
            return {quests = addon.QuestLog.Read(C_QuestLog), offers = nearbyOffers, skipped = skippedQuestIDs,
                measurements = questMeasurements, turnInTour = navigationSnapshot and navigationSnapshot.turnInTour,
                repeatablePolicy = settings.repeatablePolicy}
        end,
        select = function(id, policy)
            if id and not CanPinQuest(id) then return false end
            if policy == "complete" or policy == "turnIn" then ApplyQuestAction("prioritize", {id = id, turnIn = policy == "turnIn"})
            else SelectQuest(id) end
            return true
        end,
        destination = GetQuestDestination, restore = RestoreQuest, map = OpenRouteStop,
        changed = ScheduleRefresh,
        prepareStart = function() addon.PauseExcursion() temporaryDetour, detourMeasurement = nil, nil tracker:SetDetour(nil) end,
        cancelReturn = function()
            if temporaryDetour and temporaryDetour.tourReturn then temporaryDetour, detourMeasurement = nil, nil tracker:SetDetour(nil) end
        end,
    })
end

local function RegisterCommands()
    local C = addon.Commands
    C.Reset()
    local function Add(key, group, label, run, options)
        local entry = {key = key, group = group, label = label, run = run}
        for name, value in pairs(options or {}) do entry[name] = value end
        C.Register(entry)
    end
    local function Print(text) print("FQN | " .. text) end
    Add("", "navigation", nil, function() ToggleTracker() end, {hidden = true})
    Add("settings", "settings", "CmdSettings", function() OpenSettings() end)
    Add("arrange", "settings", "CmdArrange", function() tracker:ArrangeUI() end)
    Add("tools", "navigation", "CmdTools", function() addon.UI.ToolHub.Open(addon.UI.ToolHub.key or "finder") end)
    Add("menu", "navigation", "CmdMenu", function() addon.ShowCommandMenu(settings) end)
    Add("find", "quests", "CmdFind", function(text)
        local panel = addon.OpenWorkspace("finder")
        if panel then panel.search:SetText(text or "") end
    end, {args = true})
    Add("tour", "quests", "CmdTour", function() addon.OpenWorkspace("tour") end, {advanced = true})
    Add("resume", "quests", "CmdResume", function() addon.ResumePlan() end, {advanced = true})
    Add("plan", "quests", "CmdPlan", function() ShowPlanning() end, {advanced = true})
    Add("assist", "quests", "CmdAssist", function() addon.OpenAdventure() end, {advanced = true})
    Add("zones", "quests", "CmdZones", function() ShowZones() end)
    Add("notes", "quests", "CmdNotes", function() ShowNotepad() end)
    Add("detour", "quests", "CmdDetour", function() addon.OpenDetourTools() end, {advanced = true})
    Add("report", "quests", "CmdReport", function()
        local quest = shownQuests and shownQuests[1]
        if quest then ShowTargetReport(quest.id) end
    end, {advanced = true})
    Add("session", "history", "CmdSession", function() ShowSession() end)
    Add("session reset", "history", "CmdSessionReset", function()
        session = addon.Session.New(nil, SessionTime())
        ForeverQuestNavigatorCharacterDB.session = session.data
        CaptureSessionXP()
        ShowSession()
    end, {advanced = true})
    Add("undo", "history", "CmdUndo", function() addon.UndoLastChange() end)
    Add("history", "history", "CmdHistory", function() addon.ShowUndoHistory(addon.Undo) end, {advanced = true})
    Add("levels", "history", "CmdLevels", function() ShowLevelChanges() end, {advanced = true})
    Add("feedback", "history", "CmdFeedback", function() ShowFeedback() end, {advanced = true})
    Add("profiles", "settings", "CmdProfiles", function() ShowProfiles() end)
    Add("share", "settings", "CmdShare", function()
        addon.ShowDisplayTransfer(settings, addon.SettingsController.catalog)
    end, {advanced = true})
    Add("access", "settings", "CmdAccess", function() ShowAccessManager() end, {advanced = true})
    Add("help", "help", "CmdHelp", function() addon.ShowIntroduction(settings) end)
    Add("whatsnew", "help", "CmdWhatsNew", function() addon.ShowReleaseNotes(settings, AddonVersion()) end)
    Add("demo", "help", "CmdDemo", function(text)
        addon.DemoMode.Command((text or ""):lower(), settings, tracker, function() UpdateMapMarker() ScheduleRefresh() end)
    end, {args = true})
    Add("status", "debug", "CmdStatus", function() Print("Questie: " .. addon.ReadQuestieStatus(C_AddOns)) end, {advanced = true})
    Add("debug", "debug", "CmdDebug", function() ShowDiagnostics() end, {advanced = true})
    Add("problem", "debug", "CmdProblem", function() addon.OpenProblemReport() end)
    Add("fixture", "debug", "CmdFixture", function() ShowFixture() end, {advanced = true})
    Add("markers", "debug", "CmdMarkers", function()
        local marker = addon.GetMapMarkerStatus()
        Print(("mapMarkers: backend=%s count=%d target=%s"):format(marker.backend, marker.count, tostring(marker.hasTarget)))
        Print(marker.detail)
    end, {advanced = true})
    Add("activity", "debug", "CmdActivity", function()
        local active = shownQuests and shownQuests[1]
        local area = active and navigationSnapshot and navigationSnapshot.presence and navigationSnapshot.presence[active.id]
        local fight, body = insights.engagement, addon.RecoveryState
        Print(("activity: combatMatch=%s objective=%s area=%s recovery=%s corpse=%s"):format(
            tostring(fight and fight.questID or "none"), tostring(fight and fight.objectiveIndex or "none"),
            tostring(area and area.objectiveIndex or "none"), tostring(body and body.active == true),
            body and body.active and (body.exact and "native" or body.target and "last-death-position" or "unknown") or "none"))
    end, {advanced = true})
    Add("perf", "debug", "CmdPerf", function()
        addon.ShowTextWindow("performance", addon.Performance:Report(), L.PerformanceTitle, L.PerformanceHelp)
    end, {advanced = true})
    Add("perf on", "debug", "CmdPerfOn", function()
        Print(addon.Performance:Start() and L.PerformanceEnabled or L.PerformanceUnavailable)
    end, {advanced = true, menu = false})
    Add("perf off", "debug", "CmdPerfOff", function()
        addon.Performance.enabled = false Print(L.PerformanceDisabled)
    end, {advanced = true, menu = false})
end

local function AddonLoaded(name)
    if name == addonName and not tracker then
        settings = ForeverQuestNavigatorDB
        insights.hadSettings = type(settings) == "table" and next(settings) ~= nil
        if type(settings) ~= "table" then
            settings = {}
            ForeverQuestNavigatorDB = settings
        end
        addon.SettingsDefaults.Normalize(settings, LIMITS, not insights.hadSettings)
        addon.SetLanguage(settings.language)
        insights.lastLevel = UnitLevel and UnitLevel("player")
        addon.UI.Theme.Apply(settings.highContrast, settings.theme, settings.reducedColors)
        LoadSkippedQuests()
        local character = addon.SettingsDefaults.NormalizeCharacter(ForeverQuestNavigatorCharacterDB)
        InitializeWorkspace(character)
        questNotes, targetCorrections = character.questNotes, character.targetCorrections
        insights.laterQuests, insights.knownVendors = character.laterQuests, character.knownVendors
        insights.hiddenOffers, savedAccessPoints = character.hiddenOffers, character.accessPoints
        session = addon.Session.New(character.session, SessionTime())
        character.session = session.data
        flight.confirmedPoints, flight.routes = character.confirmedFlightPoints, character.flightRoutes

        settingsCategory = RegisterSettings()
        local version = C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(addonName, "Version")
        insights.updateVersion = addon.ReleaseNotes.Initialize(settings, version, insights.hadSettings)
        tracker = addon.CreateQuestTracker(settings, {
            skip = SkipQuest,
            resetSkips = ResetSkips,
            restore = RestoreQuest,
            resumeAutoSelect = function() SelectQuest(nil) end,
            toggleQuestHold = ToggleQuestHold,
            getQuestHold = function() return heldQuest ~= nil end,
            openSettings = OpenSettings,
            openFinder = function() addon.OpenWorkspace("finder") end,
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
        BINDING_HEADER_FOREVERQUESTNAVIGATOR = "Forever Quest Navigator"
        BINDING_NAME_FOREVERQUESTNAVIGATOR_TOGGLE = L.BindingToggle
        BINDING_NAME_FOREVERQUESTNAVIGATOR_MAP = L.BindingMap
        BINDING_NAME_FOREVERQUESTNAVIGATOR_HOLD = L.BindingHold
        BINDING_NAME_FOREVERQUESTNAVIGATOR_PLAN = L.BindingPlan
        BINDING_NAME_FOREVERQUESTNAVIGATOR_CAMP = L.BindingCamp
        BINDING_NAME_FOREVERQUESTNAVIGATOR_FEEDBACK = L.BindingFeedback
        ForeverQuestNavigator_HandleBinding = function(action)
            if action == "toggle" then ToggleTracker()
            elseif action == "map" then
                local quest = shownQuests and shownQuests[1]
                if quest then OpenQuestMap(quest.id) end
            elseif action == "hold" then ToggleQuestHold()
            elseif action == "plan" then ShowPlanning()
            elseif action == "feedback" then ShowFeedback()
            elseif action == "camp" then SwitchCamp(shownQuests and shownQuests[1] and shownQuests[1].id) end
        end
        AddQuestLogMenu()
        local function UpdateTrackers()
            UpdateDistanceTicker()
            UpdateQuestieTicker()
        end
        tracker:HookScript("OnShow", UpdateTrackers)
        tracker:HookScript("OnHide", UpdateTrackers)

        addon.EventController.RegisterRuntime(events)

        RegisterCommands()
        SLASH_FOREVERQUESTNAVIGATOR1 = "/fqn"
        SlashCmdList.FOREVERQUESTNAVIGATOR = function(message)
            addon.Commands.Dispatch(message, settings.simpleNavigator)
        end

        ConnectQuestie()
        addon.ConfigureUXHub()
        ScheduleRefresh()
    elseif tracker and name == "Questie" then
        ConnectQuestie()
    end
    if tracker then AddQuestLogButton() end
end

events:RegisterEvent("ADDON_LOADED")
addon.EventController.Bind(events, {
    recovery = addon.UpdateRecovery,
    captureXP = CaptureSessionXP,
    turnIn = function(arg, rewardXP)
        if insights.levelHold and insights.levelHold.id == arg then insights.levelHold = nil end
        insights.lastTurnIn, insights.turnInUntil = arg, SessionTime() + 10
        addon.ExcursionPlan.HandedIn(insights.excursion, arg, rewardXP)
        if not session then return end
        local title
        for _, quest in ipairs(eligibleQuests or {}) do if quest.id == arg then title = quest.title break end end
        session:TurnIn(arg, title, rewardXP)
        session:Save(SessionTime())
    end,
    saveSession = function() if session then session:Save(SessionTime()) end if workspace then workspace:Save() end end,
    loaded = AddonLoaded,
    hasMeasurements = function() return measurableQuestIDs ~= nil end,
    visible = TrackingVisible,
    measure = UpdateDistances,
    levelUp = function(level)
        if shownQuests and shownQuests[1] then insights.levelHold = {id = shownQuests[1].id, untilTime = SessionTime() + 60} end
        outing, distanceOrder = nil, nil
        if type(level) == "number" and level > 0 then
            if insights.lastLevel and insights.lastLevel > 0 and level > insights.lastLevel then
                insights.pendingLevel = {before = insights.lastLevel, after = level}
            end
            if not insights.lastLevel or level > insights.lastLevel then insights.lastLevel = level end
        end
    end,
    enterWorld = function()
        AddQuestLogButton()
        if not minimapButton then
            minimapButton = addon.CreateMinimapButton(settings, CycleDisplayMode, OpenSettings)
        end
        if workspace and workspace.pending and not workspace.announced then
            workspace.announced = true print("FQN | " .. L.ResumeOffer)
        end
    end,
    introduction = function()
        if settings and not settings.introSeen
            and not (InCombatLockdown and InCombatLockdown()) then addon.ShowIntroduction(settings) end
        if settings and settings.introSeen and insights.updateVersion and not (InCombatLockdown and InCombatLockdown())
            and not (UnitOnTaxi and UnitOnTaxi("player")) and not addon.DemoMode.IsActive() then
            if settings.showUpdateNotes then addon.ShowReleaseNotes(settings, insights.updateVersion)
            else settings.lastSeenVersion = insights.updateVersion end
            insights.updateVersion = nil
        end
    end,
    taxi = function(event)
        if event == "TAXIMAP_OPENED" then flight.taxiMapOpen = true end
        if event == "TAXIMAP_CLOSED" or event == "PLAYER_ENTERING_WORLD" then flight.taxiMapOpen = false end
        if flight.taxiMapOpen and (event == "TAXIMAP_OPENED" or event == "TAXI_NODE_STATUS_CHANGED") then
            ConfirmFlightPoints()
        end
    end,
    removeQuest = function(id)
        temporaryFeedback[id] = nil
        campAvoidance[id] = nil
        skippedQuestIDs[id] = nil
        if manualQuestID == id then manualQuestID, heldQuest = nil, nil end
    end,
    updateQuestLog = UpdateQuestLogButton,
    refresh = ScheduleRefresh,
    refreshItems = RefreshItems,
    itemRewardsUpdated = function()
        if addon.QuestRewards.HasPending() then addon.QuestRewards.Clear() return true end
    end,
})
