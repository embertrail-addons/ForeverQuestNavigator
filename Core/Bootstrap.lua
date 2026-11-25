local addonName, addon = ...
local L = addon.L
local events = CreateFrame("Frame")
-- Navigator state shared with the extracted modules (see Core/NavigatorPlanning.lua).
-- One table keeps the main chunk far below Lua 5.1's 200-local limit.
local S = {
    skippedQuestIDs = {}, skipOrder = 0, refreshPending = false, questDestinations = {},
    previousObjectives = {}, avoidedObjectives = {}, turnInLocations = {},
    savedAccessPoints = {}, passedAccessPoints = {}, questNotes = {}, targetCorrections = {},
    temporaryFeedback = {}, campAvoidance = {},
    insights = {sharedItems = {}, laterQuests = {}, knownVendors = {}, hiddenOffers = {}, offerSuppressed = {}},
}
-- Functions shared with extracted modules; filled where they are defined.
local F = {}
local integration = addon.QuestieIntegration
local ScheduleRefresh
local SetDisplayMode
local GetQuestDestination
local UpdateQuestLogButton
local RefreshNearbyOffers
local AdoptTour
function addon.GetNavigationSnapshot() return S.navigationSnapshot end
function addon.UpdateRecovery(event)
    if not addon.CorpseNavigation then return end
    local previous = addon.RecoveryState
    local wasActive = previous and previous.active
    local state = addon.CorpseNavigation.Update(previous, C_Map, C_DeathInfo,
        {dead = UnitIsDead, ghost = UnitIsGhost, either = UnitIsDeadOrGhost}, GetTime and GetTime() or 0, event)
    addon.RecoveryState = state
    if state.active and not wasActive then addon.RecoveryQuestID = S.shownQuests and S.shownQuests[1] and S.shownQuests[1].id end
    if not state.active then addon.RecoveryQuestID = nil end
    if S.tracker and S.tracker.SetRecoveryState then S.tracker:SetRecoveryState(state.active and state or nil) end
    return state
end
-- Grouped state keeps the main chunk well below Lua 5.1's 200-local limit.
-- shown: last rendered navigator content (used to skip identical re-renders).
local shown = {zones = {}, rewards = {}, alternativeRoutes = {}}
local tickers = {} -- distance, direction, questie
local flight = {active = false} -- active, questID, confirmedPoints, routes, taxiMapOpen
local LIMITS = {MINIMUM_FLIGHT_HINT_DISTANCE = 1500, DEFAULT_OPACITY = 80,
    DEFAULT_OFFER_RADIUS = 350, MAX_OFFER_RADIUS = 1000}

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
    for _, entry in ipairs(addon.JourneyPlanning.Later(S.insights.laterQuests, context, C_QuestLog)) do
        if entry.due then snapshot.laterCount = snapshot.laterCount + 1 end
    end
    return addon.DecisionBrief.Build(snapshot, S.insights.roundLedger, C_Map, mapType)
end

-- A started outing shows up to six upcoming stops on the map (and the route line).
local function OutingMapRoute()
    local plan = S.insights.excursion
    if not (plan and plan.started and plan.stops) then return end
    local route = {}
    for index = plan.index or 1, #plan.stops do
        local stop = plan.stops[index]
        if stop.target and not stop.done then
            route[#route + 1] = {target = stop.target, quest = stop.quest, action = stop.action}
            if #route >= 6 then break end
        end
    end
    return #route > 1 and route or nil
end

local function CurrentMapRoute(id)
    if S.settings.showRouteMarkers ~= false and S.shownQuests and S.shownQuests[1].id == id then return OutingMapRoute() or shown.routePreview end
    local destination = GetQuestDestination and GetQuestDestination(id)
    if destination and destination.target then
        for _, quest in ipairs(S.eligibleQuests or {}) do
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
        return S.savedAccessPoints[id] and S.savedAccessPoints[id][index]
    end, function(value)
        if value then
            S.savedAccessPoints[id] = S.savedAccessPoints[id] or {}
            S.savedAccessPoints[id][index] = value
        else addon.TravelSupport.RemoveAccess(S.savedAccessPoints, id, index) end
        S.passedAccessPoints[id .. ":" .. index], S.outing = nil, nil
        addon.RefreshAccessManager() ScheduleRefresh()
    end, before, S.savedAccessPoints[id] and S.savedAccessPoints[id][index])
end

local function ClearTemporaryFeedback(id)
    local removed = {}
    for key, entry in pairs(S.temporaryFeedback) do
        if not id or key == id then removed[key] = addon.UndoHistory.Copy(entry) S.temporaryFeedback[key] = nil end
    end
    if next(removed) then addon.Undo:Push(L.UndoFeedback, function()
        local valid = {}
        for key, entry in pairs(removed) do
            if S.temporaryFeedback[key] then return false end
            if C_QuestLog.IsOnQuest(key) then
                local copy = {[key] = addon.UndoHistory.Copy(entry)}
                if addon.RecommendationFeedback.Get(copy, {id = key, readyToTurnIn = C_QuestLog.IsComplete(key)},
                    S.questMeasurements and S.questMeasurements[key], SessionTime()) then valid[key] = copy[key] end
            end
        end
        if not next(valid) then return false end
        for key, entry in pairs(valid) do S.temporaryFeedback[key] = entry end
        S.outing = nil ScheduleRefresh() return true
    end) end
    S.outing = nil ScheduleRefresh()
end

local function WallClock() return GetServerTime and GetServerTime() or nil end

local function CaptureSessionXP()
    if S.session and UnitXP and UnitXPMax and UnitLevel then
        S.session:CaptureXP(UnitLevel("player"), UnitXP("player"), UnitXPMax("player"))
        S.session:Save(SessionTime(), WallClock())
    end
end

-- Zone with the most nearby open quests, as a "next time" suggestion for the recap.
local function SuggestZone()
    if not S.eligibleQuests then return end
    local ok, zones = pcall(addon.BuildZoneOverview, C_Map, Enum and Enum.UIMapType, S.eligibleQuests, S.navigationSnapshot)
    local best
    for _, zone in ipairs(ok and zones or {}) do
        if zone.id and (not best or zone.quests > best.quests) then best = zone end
    end
    return best and best.name
end

-- Today's level goal: text for the session overview (nil when no goal is set).
local function GoalText()
    local character = ForeverQuestNavigatorCharacterDB
    local goal = character and addon.DailyGoal.Current(character, addon.DailyGoal.Today(WallClock()))
    if not goal then return nil end
    local data = S.session and S.session.data
    local average = data and data.completed > data.unknownRewards and data.questXP / (data.completed - data.unknownRewards) or nil
    local progress = UnitLevel and UnitXP and UnitXPMax and addon.DailyGoal.Progress(goal, UnitLevel("player"),
        UnitXP("player"), UnitXPMax("player"), average)
    return addon.DailyGoal.Describe(goal, progress), progress
end
F.GoalText = GoalText

local function ShowSession()
    if S.session then addon.ShowSessionDashboard(function() return S.session end, SessionTime, SuggestZone, GoalText) end
end

local function ClearMapMarker()
    S.markedQuestID = nil
    addon.ShowQuestMapMarker()
end
addon.ClearFQNMapMarkers = ClearMapMarker

local function UpdateMapMarker()
    if addon.DemoMode.IsActive() then return end
    if not S.markedQuestID then return end
    if not (C_QuestLog and C_QuestLog.IsOnQuest and C_QuestLog.IsOnQuest(S.markedQuestID)) then
        ClearMapMarker()
        return
    end
    local destination = GetQuestDestination(S.markedQuestID)
    addon.ShowQuestMapMarker(destination and destination.target, ClearMapMarker, CurrentMapRoute(S.markedQuestID))
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
        measurement = S.questMeasurements and S.questMeasurements[questID], minimum = LIMITS.MINIMUM_FLIGHT_HINT_DISTANCE,
        playerZoneID = S.playerZoneID, flightContext = flightContext, confirmedPoints = flight.confirmedPoints,
        faction = UnitFactionGroup and UnitFactionGroup("player"),
    }, FlightAPI())
end

local function DescribeDestination(quest, destination)
    local measured = S.questMeasurements and S.questMeasurements[quest.id]
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
    local measurement = S.questMeasurements and S.questMeasurements[quest.id]
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
        UnitLevel and UnitLevel("player"), S.routeChains and S.routeChains[quest.id])
    if S.settings and S.settings.showQuestXP and not addon.QuestLog.GetTurnInXP(quest) then
        text = text .. "\n" .. L.UnknownXP
    end
    if not quest.readyToTurnIn then
        local journey = S.questJourneys and S.questJourneys[quest.id]
        text = text .. "\n" .. (journey and L.JourneyEstimate:format(journey.totalYards, journey.returnYards) or L.JourneyUnknown)
        if journey then text = text .. "\n" .. L.JourneyEstimateHelp end
        if S.questJourneys then
            local format = journey and L.JourneyPriority or L.JourneyUncertainty
            text = text .. "\n" .. format:format(addon.TravelSupport.PlanningPenalty(quest, journey, true))
        end
    end
    if measurement and measurement.objectiveMarker then
        local marker = measurement.marker
        text = text .. "\n" .. L.AccessRoute:format(marker.accessName or L.SavedAccess, marker.x * 100, marker.y * 100, measurement.accessLeg)
    end
    local note = S.questNotes[quest.id]
    if not noRewards and type(note) == "table" and type(note.text) == "string" then text = text .. "\n" .. L.QuestNoteText:format(note.text) end
    text = text .. "\n" .. L.QuestMenuHint
    local progress = addon.QuestTools.ProgressHint(quest)
    if progress then text = text .. "\n" .. progress end
    if not noRewards and S.settings.showQuestRewards ~= false then text = text .. "\n" .. addon.QuestRewards.Describe(addon.QuestRewards.Client(quest.id)) end
    if not noRewards and S.settings.showQuestRewards ~= false and S.settings.showRewardComparison ~= false then
        local comparison = addon.RewardComparison.Describe(addon.QuestRewards.Client(quest.id))
        if comparison then text = text .. "\n" .. comparison end
    end
    for _, item in ipairs(S.insights.sharedItems) do
        for _, contribution in ipairs(item.quests) do
            if contribution.quest.id == quest.id then
                text = text .. "\n" .. item.name .. ": " .. L.SharedRequired:format(item.required, #item.quests)
                    .. " · " .. (item.remaining and L.SharedRemaining:format(item.remaining) or L.SharedInventoryUnknown)
            end
        end
    end
    local feedback = addon.RecommendationFeedback.Get(S.temporaryFeedback, quest, measurement, SessionTime())
    if feedback then
        local key = ({hard = "FeedbackHard", blocked = "FeedbackBlocked", inconvenient = "FeedbackInconvenient"})[feedback.kind]
        text = text .. "\n" .. L[key] .. "\n" .. L.FeedbackHelp
    end
    return text
end

local function BuildDiagnostics()
    local active = S.shownQuests and S.shownQuests[1]
    local version = C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(addonName, "Version")
    local report = addon.Recommendation.BuildReport({
        version = version, questie = addon.ReadQuestieStatus(C_AddOns),
        playerLevel = UnitLevel and UnitLevel("player"), mapID = S.playerZoneID,
        manual = S.manualQuestID ~= nil, objectiveLock = S.objectiveLock ~= nil, held = S.heldQuest ~= nil,
        activeID = active and active.id, quests = S.shownQuests or S.eligibleQuests,
        measurements = S.questMeasurements, reason = shown.reason, route = shown.routeDetails, journeys = S.questJourneys,
        adjustments = S.navigationSnapshot and S.navigationSnapshot.adjustments,
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
    local quest = S.shownQuests and S.shownQuests[1]
    local measurement = quest and S.questMeasurements and S.questMeasurements[quest.id]
    local loaded = C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Questie")
    local markers = addon.GetMapMarkerStatus()
    local report = addon.ProblemReport.Build({version = C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(addonName, "Version"),
        quest = quest, marker = measurement and measurement.marker, yards = measurement and measurement.yards,
        level = UnitLevel and UnitLevel("player"), manual = S.manualQuestID ~= nil,
        decision = S.navigationSnapshot and S.navigationSnapshot.decision, questieLoaded = loaded, questieReady = not not integration.IsReady(),
        markerCount = markers.count, tourStops = S.workspace and #S.workspace.plan.stops, errors = addon.ErrorLog.Summary()})
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
    return addon.TrackerPresentation.Targets(quest, objectives, S.objectiveDistances, S.questMeasurements, S.avoidedObjectives, S.objectiveLock)
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
    local measured = S.questMeasurements and S.questMeasurements[quest.id]
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
    return addon.QuestPrioritizer.RankByDistance(ranked, measurements, nil, playerLevel, S.questJourneys)
end

local function SameAdditionalQuests(alternatives, zones, routes, rewards)
    if not S.shownQuests or #S.shownQuests ~= #alternatives + 1 then return false end
    for index, quest in ipairs(alternatives) do
        if S.shownQuests[index + 1] ~= quest or shown.zones[index + 1] ~= zones[index + 1]
            or shown.alternativeRoutes[index] ~= routes[index] or shown.rewards[index + 1] ~= rewards[index + 1] then
            return false
        end
    end
    return true
end

local function BuildRoutePreview(quest, destination, forecast, nextQuest)
    local target = destination and destination.target
    if not target then return end
    local measurements = S.questMeasurements or {}
    local first = measurements[quest.id]
    local preview = { { quest = quest, target = target, action = target.accessPoint and "access" or quest.readyToTurnIn and "turnIn" or "objective",
        yards = first and first.yards, current = true } }
    local distance = addon.QuestLocation.GetDistanceMetric(C_Map, target)
    if S.workspace and S.workspace:Current() == quest.id then
        for index = 2, math.min(3, #S.workspace.plan.stops) do
            local stop = S.workspace.plan.stops[index]
            local nextDestination = GetQuestDestination(stop.id)
            local candidate
            for _, entry in ipairs(S.eligibleQuests or {}) do if entry.id == stop.id then candidate = entry break end end
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
    if not (S.manualQuestID or S.objectiveLock) and S.outing and S.outing.stops[1]
        and S.outing.stops[1].quest.id == quest.id then
        for index = 2, #S.outing.stops do
            local candidate = S.outing.stops[index].quest
            local measured = measurements[candidate.id]
            AddStop(candidate, measured and measured.marker, candidate.readyToTurnIn and "turnIn" or "objective")
        end
    elseif not (S.manualQuestID or S.objectiveLock) and forecast and S.routeChains and S.routeChains[quest.id] then
        local chain = S.routeChains[quest.id]
        if not quest.readyToTurnIn then AddStop(quest, chain.finisher, "turnIn") end
        for _, stop in ipairs(chain.stops) do
            if stop.depth <= forecast.depth then
                AddStop({ id = stop.questID, title = stop.title }, stop, stop.action)
            end
        end
    elseif nextQuest and not (S.manualQuestID or S.objectiveLock) then
        local measured = measurements[nextQuest.id]
        AddStop(nextQuest, measured and measured.marker, "objective")
    end
    local journey = S.questJourneys and S.questJourneys[quest.id]
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
    S.navigationSnapshot = S.navigationSnapshot or { measurements = S.questMeasurements or {},
        objectiveDistances = S.objectiveDistances or {}, ranked = ranked, playerLevel = playerLevel, capacity = S.questCapacity }
    S.navigationSnapshot.sharedItems = S.insights.sharedItems
    S.navigationSnapshot.pickupPlanning = S.insights.pickupPlanning
    S.navigationSnapshot.chains = addon.QuestInsights.Chains(C_Map, Enum and Enum.UIMapType, ranked, S.routeChains, S.questMeasurements)
    local quest = ranked[1]
    local tourID = S.workspace and S.workspace:Current()
    local excursionStop = addon.ExcursionPlan.Current(S.insights.excursion)
    local levelHold = S.insights.levelHold and SessionTime() <= S.insights.levelHold.untilTime and S.insights.levelHold.id
    local selectedQuestID = S.manualQuestID or (S.objectiveLock and S.objectiveLock.questID) or addon.RecoveryQuestID or flight.questID or S.combatQuestID
        or (excursionStop and excursionStop.action ~= "accept" and excursionStop.quest.id) or tourID or (S.temporaryDetour and S.temporaryDetour.questID) or levelHold
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
            if levelHold == selectedQuestID then S.insights.levelHold, levelHold = nil, nil end
            S.manualQuestID = nil
            S.heldQuest = nil
            S.objectiveLock = nil
            flight.questID = nil
            S.combatQuestID = nil
        end
    end
    if not (S.manualQuestID or S.objectiveLock or addon.RecoveryQuestID or flight.questID or S.combatQuestID or levelHold or excursionStop or tourID or (S.temporaryDetour and S.temporaryDetour.questID)) and routeQuest then
        quest = routeQuest
    else
        routeNote = S.manualQuestID and (S.heldQuest and L.HeldQuestReason or L.ManualSelection)
            or DescribeRecommendation(quest, playerLevel)
        routeDetails = nil
    end
    if tourID and quest.id == tourID and not S.manualQuestID then
        routeNote = L.TourRunning S.navigationSnapshot.decision = "tour"
    end
    if excursionStop then routeNote = L.ExcursionCurrent S.navigationSnapshot.decision = "excursion" end
    if addon.RecoveryState and addon.RecoveryState.active and not addon.RecoveryQuestID then addon.RecoveryQuestID = quest.id end
    if levelHold and quest.id == levelHold and not (S.manualQuestID or S.objectiveLock or excursionStop or tourID) then
        routeNote = L.AdventureLevelShort S.navigationSnapshot.decision, S.navigationSnapshot.decisionSaving = "levelReview", nil
    end
    local progressHint = addon.QuestTools.ProgressHint(quest)
    if progressHint then routeNote = routeNote and (routeNote .. " · " .. progressHint) or progressHint end
    local summaryImportant = not not (S.manualQuestID or tourID or routeQuest or quest.readyToTurnIn or progressHint
        or addon.QuestPrioritizer.GetDifficulty(quest, playerLevel) == "red")
    for _, bundle in ipairs(S.navigationSnapshot.decision == "ranking" and S.navigationSnapshot.bundles or {}) do
        for _, entry in ipairs(bundle.entries) do
            if entry.quest.id == quest.id then
                local hint = L.SharedStopCount:format(#bundle.entries)
                summaryImportant = true
                routeNote = routeNote and (routeNote .. " · " .. hint) or hint
                break
            end
        end
    end
    local feedback = S.navigationSnapshot.feedback and S.navigationSnapshot.feedback[quest.id]
    if feedback then routeNote = (routeNote and (routeNote .. " · ") or "") .. L.FeedbackActive summaryImportant = true end
    local mates = addon.GroupSync.Showing(S.settings) and addon.GroupSync.Describe(quest.id)
    if mates then routeNote = (routeNote and (routeNote .. " · ") or "") .. L.GroupSyncMates:format(mates) end
    if quest.readyToTurnIn and S.navigationSnapshot.capacity and (S.navigationSnapshot.capacity.full or S.navigationSnapshot.capacity.reserveNeeded) then
        routeNote = (routeNote and (routeNote .. " · ") or "") .. (S.navigationSnapshot.capacity.full and L.FreeQuestSlot or L.ReserveQuestSlot)
    end
    local destination = GetQuestDestination(quest.id)
    if S.manualQuestID then ranked = RankFromQuest(ranked, quest, destination, playerLevel) end
    local alternatives = {}
    for _, candidate in ipairs(ranked) do
        if candidate.id ~= quest.id then
            alternatives[#alternatives + 1] = candidate
        end
    end
    local rewardText, reward = DescribeQuestXP(quest, xpNeeded, playerLevel)
    local rewardDetails = S.settings.showQuestXP and xpNeeded and rewardText or nil
    if S.settings.showQuestRewards ~= false then
        local info = addon.QuestRewards.Client(quest.id)
        rewardDetails = (rewardDetails and (rewardDetails .. "\n") or "") .. addon.QuestRewards.Describe(info)
        local comparison = S.settings.showRewardComparison ~= false and addon.RewardComparison.Describe(info)
        if comparison then rewardDetails = rewardDetails .. "\n" .. comparison end
    end
    local rewards = {}
    if S.settings.showQuestXP and reward then
        rewards[1] = addon.TrackerPresentation.XPLine(reward, xpNeeded, playerLevel)
    end
    if reward and reward >= xpNeeded and type(playerLevel) == "number" and playerLevel > 0 and playerLevel < math.huge then
        if quest.readyToTurnIn and not S.manualQuestID and not (routeQuest and routeDetails) then
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
    if routeNote == L.LevelUpOnTurnIn and S.settings.showQuestXP and reward and reward >= xpNeeded then routeNote = nil end
    if xpNeeded and not (reward and reward >= xpNeeded) and type(playerLevel) == "number" and playerLevel > 0 then
        local levelPlan = addon.LevelForecast.FromQuests(S.eligibleQuests, S.questMeasurements, addon.QuestLog.GetTurnInXP, xpNeeded)
        if levelPlan then
            local text = L.LevelForecastRoute:format(playerLevel + 1, levelPlan.count, levelPlan.total)
            -- Pins Questie draws plus known follow-ups from the database, cached for 30 seconds.
            local cache = S.insights.soonCache
            if not cache or cache.level ~= playerLevel or SessionTime() - cache.at > 30 then
                local ids = {}
                for _, quest in ipairs(S.eligibleQuests or {}) do ids[#ids + 1] = quest.id end
                for _, entry in ipairs(S.session and S.session.data.recent or {}) do ids[#ids + 1] = entry.id end
                local set = integration.SoonSet and integration.SoonSet() or {}
                for id in pairs(integration.SoonFollowUps and integration.SoonFollowUps(ids, playerLevel, S.questTargetMaps) or {}) do set[id] = true end
                local count = 0
                for _ in pairs(set) do count = count + 1 end
                cache = {level = playerLevel, at = SessionTime(), count = count}
                S.insights.soonCache = cache
            end
            if cache.count > 0 then text = text .. " · " .. L.LevelForecastUnlocks:format(cache.count) end
            routeDetails = routeDetails and (routeDetails .. "\n" .. text) or text
        end
    end
    local nearbyStops = GetNearbyStops(quest, destination, ranked, playerLevel)
    local approachStops
    local flightContext = addon.QuestLocation.GetFlightContext(C_Map, S.distanceMaps, flight.routes)
    local zones, alternativeRoutes = {}, {}
    if destination then
        local nextStop = DescribeDestination(quest, destination)
        local measured = S.questMeasurements and S.questMeasurements[quest.id]
        if measured and measured.objectiveMarker then
            local marker = measured.marker
            nextStop = L.AccessRoute:format(marker.accessName or L.SavedAccess, marker.x * 100, marker.y * 100, measured.accessLeg)
                .. "\n" .. nextStop
        end
        local journey = S.questJourneys and S.questJourneys[quest.id]
        if journey then nextStop = nextStop .. "\n" .. L.JourneyEstimate:format(journey.totalYards, journey.returnYards) end
        routeDetails = routeDetails and (nextStop .. "\n" .. routeDetails) or nextStop
        if destination.zoneID ~= S.playerZoneID then zones[1] = destination.zoneName end
        local flightText = GetFlightHint(quest.id, destination, flightContext)
        if flightText then
            routeDetails = routeDetails .. "\n" .. flightText
        else
            approachStops = addon.QuestRoute.GetStopsOnApproach(C_Map, quest, ranked, S.questMeasurements, playerLevel)
        end
    end
    for index, alternative in ipairs(alternatives) do
        local fullReward, xp
        if S.settings.showQuestXP then
            fullReward, xp = DescribeQuestXP(alternative, xpNeeded, playerLevel)
            if xp then
                local format = xp >= xpNeeded and L.QuestXPCompactLevelUp or L.QuestXPReward
                rewards[index + 1] = format:format(xp)
            end
        end
        local other = GetQuestDestination(alternative.id)
        if other then
            local details = DescribeDestination(alternative, other)
            local measured = S.questMeasurements and S.questMeasurements[alternative.id]
            if measured and measured.objectiveMarker then
                local marker = measured.marker
                details = L.AccessRoute:format(marker.accessName or L.SavedAccess, marker.x * 100, marker.y * 100, measured.accessLeg)
                    .. "\n" .. details
            end
            local journey = S.questJourneys and S.questJourneys[alternative.id]
            if journey then details = details .. "\n" .. L.JourneyEstimate:format(journey.totalYards, journey.returnYards) end
            if other.zoneID ~= S.playerZoneID then zones[index + 1] = other.zoneName end
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
    if S.heldQuest then reasonLines[#reasonLines + 1] = S.heldQuest.policy == "turnIn" and L.PriorityUntilTurnIn
        or S.heldQuest.policy == "complete" and L.PriorityUntilComplete or L.HeldQuestReason end
    if S.manualQuestID then
        reasonLines[#reasonLines + 1] = L.ManualQuestReason
    elseif S.objectiveLock then
        reasonLines[#reasonLines + 1] = L.ManualObjectiveReason
    else
        reasonLines[#reasonLines + 1] = L.AutomaticQuestReason
    end
    reasonLines[#reasonLines + 1] = addon.DescribeQuest(quest, S.questMeasurements and S.questMeasurements[quest.id], true)
    local fit = DescribeRecommendation(quest, playerLevel)
    if fit then reasonLines[#reasonLines + 1] = fit end
    if routeNote and routeNote ~= fit then reasonLines[#reasonLines + 1] = routeNote end
    if forecast then
        if routeDetails then reasonLines[#reasonLines + 1] = routeDetails end
    end
    local preparation = addon.TravelPreparation.Describe(S.questMeasurements and S.questMeasurements[quest.id], S.settings, C_Container, GetInventoryItemDurability, NUM_BAG_SLOTS)
    if preparation then
        reasonLines[#reasonLines + 1] = preparation
        routeDetails = routeDetails and (routeDetails .. "\n" .. preparation) or preparation
    end
    table.insert(reasonLines, S.heldQuest and 4 or 3, addon.Recommendation.Short(S.navigationSnapshot, quest, S.manualQuestID or S.objectiveLock))
    local reason = table.concat(reasonLines, "\n")
    local explanation = addon.NavigationHints.Why(S.navigationSnapshot, quest, S.manualQuestID or S.objectiveLock)
    local quality = addon.NavigationHints.TargetText(S.questMeasurements and S.questMeasurements[quest.id] and S.questMeasurements[quest.id].marker)
    reason = reason .. "\n" .. explanation .. "\n" .. quality
    routeDetails = (routeDetails and routeDetails .. "\n" or "") .. quality
    local measured = S.questMeasurements and S.questMeasurements[quest.id]
    local travelTime = not flight.active and addon.TravelTime.Describe(measured and measured.yards, S.settings)
    if travelTime then routeDetails = routeDetails .. "\n" .. travelTime reason = reason .. "\n" .. travelTime end
    local overview = addon.BuildZoneOverview(C_Map, Enum and Enum.UIMapType, S.eligibleQuests, S.navigationSnapshot)
    local suggestion = addon.ZoneSuggestion.Find(overview, S.playerZoneID, S.manualQuestID or S.heldQuest
        or (S.settings.quietNavigation and (flight.active or (InCombatLockdown and InCombatLockdown()))), measured and measured.yards)
    if suggestion then
        local advisory = L.ZoneSuggestion:format(suggestion.name, suggestion.clusterSuitable, suggestion.clusterYards or suggestion.yards)
        routeDetails = routeDetails .. "\n" .. advisory reason = reason .. "\n" .. advisory
    end
    if not routeNote and not (S.settings.showQuestXP and reward and reward >= xpNeeded) then routeNote = explanation end
    local itemHint = addon.QuestItemHints.Read(C_QuestLog, quest.id, GetQuestLogSpecialItemInfo, GetItemCount)
    if itemHint then
        local hint = L.QuestItemHint:format(itemHint.name)
        routeDetails = routeDetails and (routeDetails .. "\n" .. hint) or hint
        reason = reason .. "\n" .. hint
    end
    local comparison = addon.PlanningInsights.Compare(S.navigationSnapshot, quest, S.manualQuestID or S.objectiveLock)
    reason = reason .. "\n" .. comparison
    S.navigationSnapshot.comparison = comparison
    local preview = BuildRoutePreview(quest, destination, forecast, nextQuest)
    local area = addon.BuildAreaOverview(C_Map, Enum and Enum.UIMapType, S.playerZoneID, S.eligibleQuests,
        S.questMarkers or {}, S.distanceMaps, S.avoidedObjectives)
    if S.navigationSnapshot then
        S.navigationSnapshot.changeContext = {accepted = S.insights.newlyAccepted, turnedIn = S.insights.turnInUntil and SessionTime() <= S.insights.turnInUntil and S.insights.lastTurnIn or nil}
        S.navigationSnapshot.noteRevision = S.insights.noteRevision or 0
        S.navigationSnapshot.activeQuestID = quest.id
        S.navigationSnapshot.activeMeasurement = S.questMeasurements and S.questMeasurements[quest.id]
        S.navigationSnapshot.preparation = preparation
        S.navigationSnapshot.view = { quest = quest, objectives = text, alternatives = alternatives,
            changeNotice = addon.NavigationHints.Change(S.shownQuests and S.shownQuests[1], quest, S.navigationSnapshot, S.manualQuestID or S.objectiveLock),
            manual = S.manualQuestID ~= nil or excursionStop ~= nil, routeNote = routeNote, routeDetails = routeDetails, summaryImportant = summaryImportant,
            reason = reason, zones = zones, alternativeRoutes = alternativeRoutes, preview = preview, rewardDetails = rewardDetails,
            noteText = addon.GetQuestNoteText(quest.id),
            nearbyStops = nearbyStops, rewards = rewards, targets = targets, hasMap = hasMap,
            approachStops = approachStops, area = area }
        S.navigationSnapshot.flying = flight.active
        S.navigationSnapshot.excursionStep = excursionStop
        S.navigationSnapshot.excursionPlan = S.insights.excursion
        if excursionStop and excursionStop.action == "accept" then
            local measuredPickup = addon.TemporaryDetour.Measure(C_Map, excursionStop.target)
            S.navigationSnapshot.excursionYards = measuredPickup and measuredPickup.yards
        end
        S.navigationSnapshot.arrived = S.arrivalState and S.arrivalState.arrived
        S.navigationSnapshot.brief = BuildDecisionBrief(S.navigationSnapshot, Enum and Enum.UIMapType)
        S.tracker:SetDecisionBrief(S.navigationSnapshot.brief)
    end
    if S.shownQuests and S.shownQuests[1] == quest and S.shownQuests[2] == alternatives[1]
        and S.shownQuests[3] == alternatives[2] and shown.routeNote == routeNote and shown.routeDetails == routeDetails
        and shown.objectives == text
        and SameAdditionalQuests(alternatives, zones, alternativeRoutes, rewards)
        and shown.reason == reason
        and (S.tracker.noteRevision or 0) == (S.insights.noteRevision or 0)
        and (rewardDetails or "") == (S.tracker.rewardDetails and S.tracker.rewardDetails:GetText() or "")
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
    S.shownQuests = { quest }
    for _, alternative in ipairs(alternatives) do S.shownQuests[#S.shownQuests + 1] = alternative end
    shown.routeNote, shown.routeDetails = routeNote, routeDetails
    shown.zones, shown.alternativeRoutes = zones, alternativeRoutes
    shown.nearbyStops = nearbyStops
    shown.approachStops = approachStops
    shown.rewards = rewards
    S.tracker:RenderSnapshot(S.navigationSnapshot, S.skippedQuestIDs)
end

local function DescribeRoute(quest, route)
    return addon.TrackerPresentation.Route(quest, route)
end

local function DescribeOuting(stops)
    return addon.TrackerPresentation.Outing(stops)
end

local function UpdateOuting(ranked, measurements, playerLevel, followUp)
    if S.manualQuestID or followUp or addon.ExcursionPlan.Current(S.insights.excursion) then
        S.outing = nil
        return
    end
    if S.outing then
        local byID = {}
        for _, quest in ipairs(ranked) do byID[quest.id] = quest end
        local remaining = {}
        for _, stop in ipairs(S.outing.stops) do
            local quest = byID[stop.quest.id]
            if quest and measurements[quest.id] and not (S.navigationSnapshot.feedback and S.navigationSnapshot.feedback[quest.id])
                and not addon.QuestPrioritizer.IsLowPriority(quest, playerLevel) then
                local objectives = stop.objectiveIndex and C_QuestLog.GetQuestObjectives
                    and C_QuestLog.GetQuestObjectives(quest.id)
                local plannedObjective = objectives and objectives[stop.objectiveIndex]
                if (quest.readyToTurnIn == true) == stop.turnIn
                    and not (plannedObjective and plannedObjective.finished) then
                    stop.quest = quest
                    remaining[#remaining + 1] = stop
                else
                    S.outing.inProgress = true
                end
            elseif not C_QuestLog.IsOnQuest(stop.quest.id) then
                S.outing.inProgress = true
            end
        end
        S.outing.stops = remaining
        if S.outing.inProgress and #remaining > 0 then return S.outing end
    end

    S.outing = nil
    local plan = addon.QuestRoute.PlanOuting(C_Map, ranked, measurements, playerLevel, S.questJourneys)
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
    S.outing = { stops = stops, saving = plan.saving }
    return S.outing
end

local function FlightStep(quest)
    return addon.FlightPoints.Step(quest, quest and S.questMeasurements and S.questMeasurements[quest.id], C_QuestLog)
end

local function UpdateFlightState()
    local recovery = addon.UpdateRecovery()
    if recovery and recovery.active then S.combatQuestID = nil S.tracker:SetCombatView(false) return end
    local onTaxi = UnitOnTaxi and UnitOnTaxi("player")
    local flying = onTaxi == true or onTaxi == 1
    if flying ~= flight.active then
        flight.active = flying
        flight.questID = flying and S.shownQuests and S.shownQuests[1] and S.shownQuests[1].id or nil
    end
    S.tracker:SetFlightView(flying, FlightStep(S.shownQuests and S.shownQuests[1]))
    local fighting = InCombatLockdown and InCombatLockdown() == true
    S.insights.engagement = nil
    if fighting then
        local matches = addon.ObjectivePresence.Engaged({guid = UnitGUID, canAttack = UnitCanAttack, dead = UnitIsDeadOrGhost,
            same = UnitIsUnit, threat = UnitThreatSituation}, S.insights.combatMarkers or S.questMarkers, S.eligibleQuests, C_QuestLog, S.avoidedObjectives, S.objectiveLock)
        local current = S.shownQuests and S.shownQuests[1] and S.shownQuests[1].id
        local selected = current and matches[current] and current or S.combatQuestID and matches[S.combatQuestID] and S.combatQuestID
        if not selected then for _, q in ipairs(S.eligibleQuests or {}) do if matches[q.id] then selected = q.id break end end end
        if selected then S.insights.engagement = matches[selected] end
        local explicit = S.manualQuestID or S.objectiveLock or addon.ExcursionPlan.Current(S.insights.excursion) or S.workspace and S.workspace:Current() or S.temporaryDetour
        if explicit then S.combatQuestID = nil
        elseif selected then
            S.combatQuestID = selected
        elseif not S.combatQuestID and S.settings.quietNavigation ~= false then S.combatQuestID = current end
    end
    if not fighting then S.combatQuestID = nil end
    S.tracker:SetCombatView(fighting == true and S.settings.quietNavigation ~= false)
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
        S.tracker:RenderRecovery(recovery, m, right, forward)
        S.tracker:RenderRowDirections(nil)
        addon.Performance:Finish("direction", performanceStart)
        return
    end
    local returnPoint = S.workspace and S.workspace:ReturnTarget()
    if returnPoint and not S.temporaryDetour and not S.manualQuestID and not S.combatQuestID and not flight.active
        and addon.TemporaryDetour.IsOutdoor(C_Map, Enum and Enum.UIMapType, returnPoint.mapID) then
        S.temporaryDetour = addon.TemporaryDetour.New(returnPoint.mapID, returnPoint.x, returnPoint.y, returnPoint.name)
        S.temporaryDetour.tourReturn = true
    end
    if S.temporaryDetour then
        S.detourMeasurement = addon.TemporaryDetour.Measure(C_Map, S.temporaryDetour)
        if S.detourMeasurement and S.detourMeasurement.yards <= 12 and not S.temporaryDetour.excursion and not flight.active and not (IsInInstance and IsInInstance()) then
            if S.temporaryDetour.tourReturn and S.workspace then S.workspace:Arrived() end
            S.temporaryDetour, S.detourMeasurement = nil, nil
            S.tracker:SetDetour(nil)
            print("FQN | " .. L.DetourReturned)
            ScheduleRefresh()
        else
            S.tracker:SetDetour(S.temporaryDetour, S.detourMeasurement)
        end
    end
    local facing
    local inInstance = IsInInstance and IsInInstance()
    if not inInstance and not flight.active and GetPlayerFacing then
        facing = GetPlayerFacing()
    end
    local right, forward = addon.QuestLocation.GetRelativeDirection(S.temporaryDetour and S.detourMeasurement or S.activeDirection, facing)
    local active = S.shownQuests and S.shownQuests[1]
    local measurement = active and S.questMeasurements and S.questMeasurements[active.id]
    local arrived
    S.arrivalState, arrived = addon.TrackerState.Arrival(S.arrivalState, active, measurement)
    local here = active and S.navigationSnapshot and S.navigationSnapshot.presence and S.navigationSnapshot.presence[active.id]
    local engaged = active and S.insights.engagement and S.insights.engagement.questID == active.id
    local working = here ~= nil or engaged
    local status
    if flight.active then
        status, arrived, S.arrivalState = FlightStep(active), false, nil
    elseif inInstance then
        status = L.NavigationInstance
    elseif engaged then status = L.QuestEnemyEngaged
    elseif not measurement then
        status = active and next(S.avoidedObjectives[active.id] or {}) and L.NavigationAvoided or L.NavigationUnknown
    elseif here then status = L.QuestSpawnNeighborhood
    elseif arrived then
        status = addon.NavigationHints.NextAction(active, measurement and measurement.marker, S.tracker:GetQuestItemHint())
    elseif not right then
        status = L.NavigationFacingUnavailable
    end
    if S.temporaryDetour then
        arrived = false
        status = flight.active and L.FlightGeneric or inInstance and L.NavigationInstance or not S.detourMeasurement and L.NavigationUnknown
            or S.temporaryDetour.tourReturn and L.ReturnJourney
            or S.temporaryDetour.excursion and (L.ExcursionCurrent .. ": " .. S.temporaryDetour.name) or L.DetourActive
    end
    if arrived or working or inInstance or flight.active then right, forward = nil, nil end
    if S.navigationSnapshot then S.navigationSnapshot.arrived, S.navigationSnapshot.flying = arrived or working, flight.active end
    S.tracker:SetJourneyPhase(flight.active and "flight" or active and active.readyToTurnIn and "turnIn" or (arrived or working) and "work" or "travel")
    S.tracker:RenderDirection(right, forward, status, arrived and not inInstance, working)
    addon.MinimapArrow.Update(S.settings, right, forward, facing)
    S.tracker:RenderRowDirections(facing)
    local report = S.insights.levelReport
    if report and not report.notified and #report.entries > 0 then
        if S.settings.showLevelHints == false or SessionTime() > report.deadline then report.notified = true
        elseif not flight.active and not (InCombatLockdown and InCombatLockdown())
            and (S.tracker:IsVisible() or S.settings.displayMode == "arrow") then
            report.notified = true
            addon.ShowLevelNotice(#report.entries, function() addon.OpenAdventure("level") end,
                S.tracker:IsVisible() and S.tracker or S.tracker.navigation)
        end
    end
    addon.Performance:Finish("direction", performanceStart)
end

local function TrackingVisible()
    return S.tracker:IsVisible() or S.settings.displayMode == "arrow"
end

local function UpdateDirectionTicker()
    if TrackingVisible() and (S.settings.showDirectionArrow or S.settings.minimapArrow or S.temporaryDetour or (S.workspace and S.workspace:ReturnTarget()) or addon.RecoveryState and addon.RecoveryState.active) then
        UpdateDirection()
        local canRotate = addon.RecoveryState and addon.RecoveryState.active or
            (((S.settings.showDirectionArrow or S.settings.minimapArrow) and GetPlayerFacing and (S.measurableQuestIDs or S.nearbyOffers) or S.temporaryDetour)
                and not flight.active and not (IsInInstance and IsInInstance()))
        if canRotate and not tickers.direction then
            tickers.direction = C_Timer.NewTicker(0.2, addon.ErrorLog.Wrap("direction", UpdateDirection))
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
    S.tracker:RenderDirection()
    addon.MinimapArrow.Update(S.settings)
    S.tracker:RenderRowDirections()
end

local function UpdateDistances(force)
    UpdateFlightState()
    if addon.RecoveryState and addon.RecoveryState.active then return end
    local origin = addon.MovementGate.Sample(C_Map)
    local phase = tostring(flight.active) .. ":" .. tostring(S.combatQuestID) .. ":" .. tostring(IsInInstance and IsInInstance())
    if S.insights.levelHold and SessionTime() >= S.insights.levelHold.untilTime then S.insights.levelHold = nil end
    local deadline = S.insights.levelHold and S.insights.levelHold.untilTime
    for _, entry in pairs(S.temporaryFeedback) do if not deadline or entry.untilTime < deadline then deadline = entry.untilTime end end
    for _, entries in pairs(S.campAvoidance) do
        for _, entry in ipairs(entries) do if not deadline or entry.untilTime < deadline then deadline = entry.untilTime end end
    end
    local current = S.navigationSnapshot and S.navigationSnapshot.activeMeasurement
    if force == false and not addon.MovementGate.ShouldUpdate(S.movementState, origin, phase,
        current and current.yards <= 50, deadline, SessionTime()) then
        if addon.Performance.enabled then addon.Performance.skipped = addon.Performance.skipped + 1 end
        return
    end
    if S.measurableQuestIDs and not S.refreshPending then
        S.movementState = {point = origin, phase = phase, deadline = deadline}
        local performanceStart = addon.Performance:Begin()
        local snapshot = addon.NavigationController.Compute({
            mapAPI = C_Map, mapType = Enum and Enum.UIMapType, questAPI = C_QuestLog,
            playerLevel = UnitLevel and UnitLevel("player"), questieReady = integration.IsReady(),
            distanceOrder = S.distanceOrder,
            flying = flight.active or S.combatQuestID ~= nil, manual = S.manualQuestID ~= nil or addon.ExcursionPlan.Current(S.insights.excursion) ~= nil, routeChains = S.routeChains,
            onTaxi = flight.active, detour = S.temporaryDetour ~= nil,
            feedback = S.temporaryFeedback, now = SessionTime(),
            groupCounts = addon.GroupSync.Showing(S.settings) and addon.GroupSync.Counts() or nil,
            campAvoidance = S.campAvoidance,
            previousCamps = S.insights.previousCamps,
            previousPresence = S.insights.presence,
            capacity = S.questCapacity,
            xpNeeded = addon.QuestLog.GetXPToNextLevel(),
            questMarkers = S.questMarkers,
            measurableQuestIDs = S.measurableQuestIDs,
            distanceMaps = S.distanceMaps,
            previousObjectives = S.previousObjectives,
            objectiveLock = S.objectiveLock,
            avoidedObjectives = S.avoidedObjectives,
            eligibleQuests = S.eligibleQuests,
            savedAccessPoints = S.savedAccessPoints,
            passedAccessPoints = S.passedAccessPoints,
            turnInLocations = S.turnInLocations,
            questTargetMaps = S.questTargetMaps,
        })
        addon.Performance:Finish("planning", performanceStart)
        S.navigationSnapshot = snapshot
        S.insights.previousCamps = snapshot.previousCamps
        S.insights.presence = snapshot.presence
        S.questMeasurements, S.objectiveDistances = snapshot.measurements, snapshot.objectiveDistances
        S.previousObjectives, S.objectiveLock = snapshot.previousObjectives, snapshot.objectiveLock
        S.questJourneys, S.distanceOrder = snapshot.journeys, snapshot.distanceOrder
        local measurements, ranked, playerLevel = snapshot.measurements, snapshot.ranked, snapshot.playerLevel
        if flight.active then
            local found
            for _, candidate in ipairs(ranked) do if candidate.id == flight.questID then found = true break end end
            if not found then flight.questID = ranked[1] and ranked[1].id end
        end
        local routeQuest, route = snapshot.routeQuest, snapshot.route
        local xpNeeded, levelUpQuest, nextQuest = snapshot.xpNeeded, snapshot.levelUpQuest, snapshot.nextQuest
        local note, details
        local trip = not (flight.active or S.combatQuestID) and UpdateOuting(snapshot.planningRanked, measurements, playerLevel, levelUpQuest or routeQuest or S.objectiveLock)
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
        S.tracker:SetFlightView(flight.active, FlightStep(S.shownQuests[1]))
        UpdateMapMarker()
        local activeMeasurement = snapshot.activeMeasurement
        S.activeDirection = activeMeasurement and activeMeasurement.east and activeMeasurement or nil
        S.tracker:RenderDistances(measurements)
        if RefreshNearbyOffers and (not S.insights.offersAt or SessionTime() - S.insights.offersAt >= 5) then
            RefreshNearbyOffers(S.distanceMaps, S.questTargetMaps, Enum and Enum.UIMapType)
        end
        UpdateDirectionTicker()
    end
end

local function UpdateDistanceTicker()
    UpdateFlightState()
    if TrackingVisible() and S.measurableQuestIDs then
        UpdateDistances()
        if not tickers.distance then
            tickers.distance = C_Timer.NewTicker(1, addon.ErrorLog.Wrap("distance", function() UpdateDistances(false) end))
        end
    else
        if tickers.distance then
            tickers.distance:Cancel()
            tickers.distance = nil
        end
        S.activeDirection = nil
        UpdateDirectionTicker()
    end
end

local function RenderEmpty(message)
    S.navigationSnapshot = nil
    S.insights.pickupPlanning = nil
    S.tracker:SetPickupPlanning(nil)
    S.tracker:SetDecisionBrief(nil)
    S.combatQuestID = nil
    S.eligibleQuests, S.shownQuests, S.distanceOrder, S.measurableQuestIDs = nil, nil, nil, nil
    S.outing = nil
    shown.reason, shown.routeDetails, S.questMeasurements = nil, nil, nil
    S.arrivalState = nil
    flight.questID = nil
    S.questJourneys = nil
    S.objectiveLock, S.previousObjectives = nil, {}
    UpdateMapMarker()
    S.tracker:Render(nil, message, S.skippedQuestIDs)
    UpdateDistanceTicker()
    addon.RefreshQuestNotepad()
end

local function UpdateQuestieTicker()
    if TrackingVisible() and integration.IsReady() and (S.settings.useQuestieKillLocations or S.settings.showQuestieOffers) then
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
            if not known and (quest.special or not S.questMarkers[quest.id] or #S.questMarkers[quest.id] == 0) then
                marker = addon.QuestLocation.GetOutdoorWaypoint(C_Map, C_QuestLog, mapType, targetMaps, quest.id)
            end
        end
        if marker then
            marker.outdoorTurnIn = true
            S.questMarkers[quest.id] = { marker }
        elseif quest.special then
            -- Keep completed special quests visible even without an outdoor pin.
            S.questMarkers[quest.id] = quest.readyToTurnIn and {} or nil
        end
    end
end

RefreshNearbyOffers = function(localMaps, targetMaps, mapType)
    S.insights.offersAt = SessionTime()
    local offers
    if S.settings.showQuestieOffers and S.tracker:IsVisible() and integration.IsReady() and UnitLevel then
        local level = UnitLevel("player")
        local active = S.shownQuests and GetQuestDestination(S.shownQuests[1].id)
        local offerAnchors = {}
        local plan = S.insights.excursion
        for index = plan and plan.index or 1, plan and #plan.stops or 0 do
            local stop = plan.stops[index]
            if stop.action == "accept" and not stop.done and #offerAnchors < 3 then offerAnchors[#offerAnchors + 1] = stop.target end
        end
        offers = integration.GetNearbyOffers(C_Map, C_QuestLog, localMaps, targetMaps, mapType,
            level, S.settings.questieOfferRadius, active and active.target, true, offerAnchors)
    end
    offers = offers and addon.MixedQuestPlan.Filter(offers, S.insights.hiddenOffers,
        S.insights.excursion and S.insights.excursion.excludedOffers, S.insights.offerSuppressed)
    offers = offers and addon.RepeatablePolicy.Offers(offers, S.settings.repeatablePolicy)
    S.nearbyOffers = offers and #offers > 0 and offers or nil
    if offers then
        addon.PlanningInsights.AnnotateOffers(C_Map, offers, S.eligibleQuests, S.questMeasurements or {}, S.shownQuests and S.shownQuests[1],
            S.questCapacity)
    end
    local pickupPlan = addon.PickupPlanning.Build(C_Map, offers, S.eligibleQuests, S.questMeasurements or {},
        S.shownQuests and S.shownQuests[1], S.navigationSnapshot and S.navigationSnapshot.capacity or S.questCapacity,
        S.navigationSnapshot and S.navigationSnapshot.playerLevel or (UnitLevel and UnitLevel("player")), S.navigationSnapshot and S.navigationSnapshot.feedback,
        S.navigationSnapshot and S.navigationSnapshot.chains, mapType, nil, S.navigationSnapshot and S.navigationSnapshot.finishers)
    if offers then
        local fresh
        S.seenRecommendedOffers, fresh = addon.TrackerState.NewOffers(S.seenRecommendedOffers, offers)
        S.tracker:SetNewOffers(fresh)
    end
    if S.navigationSnapshot then S.navigationSnapshot.pickupPlanning = pickupPlan end
    S.insights.pickupPlanning = pickupPlan
    if S.navigationSnapshot then
        S.navigationSnapshot.brief = BuildDecisionBrief(S.navigationSnapshot, Enum and Enum.UIMapType)
        S.tracker:SetDecisionBrief(S.navigationSnapshot.brief)
    else
        S.tracker:SetDecisionBrief(BuildDecisionBrief({pickupPlanning = pickupPlan, capacity = S.questCapacity}, mapType))
    end
    S.tracker:SetPickupPlanning(pickupPlan)
    S.tracker:RenderNearbyOffers(S.nearbyOffers, S.settings.showQuestXP)
    UpdateDirectionTicker()
end

function addon.PauseExcursion()
    if S.insights.excursion then S.insights.excursion.running = false end
    if S.temporaryDetour and S.temporaryDetour.excursion then
        S.temporaryDetour, S.detourMeasurement = nil, nil
        S.tracker:SetDetour(nil)
    end
end
function addon.SyncExcursion(quests)
    if addon.RecoveryState and addon.RecoveryState.active then return end
    local plan = S.insights.excursion
    if not (plan and plan.running) then return end
    addon.ExcursionPlan.Sync(plan, quests, C_QuestLog and C_QuestLog.GetQuestObjectives,
        C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted, S.skippedQuestIDs)
    local stop = addon.ExcursionPlan.Current(plan)
    if stop and stop.action == "accept" then
        if S.questCapacity and S.questCapacity.full then plan.status = L.QuestLogFull addon.PauseExcursion() return end
        S.temporaryDetour = addon.TemporaryDetour.New(stop.target.mapID, stop.target.x, stop.target.y, L.ExcursionAction_accept)
        if not S.temporaryDetour then plan.status = L.ExcursionStale addon.PauseExcursion() return end
        S.temporaryDetour.name = L.ExcursionAction_accept .. ": " .. (stop.quest.title or "")
        S.temporaryDetour.excursion, S.temporaryDetour.questID = true, stop.quest.id
    elseif S.temporaryDetour and S.temporaryDetour.excursion then
        S.temporaryDetour, S.detourMeasurement = nil, nil S.tracker:SetDetour(nil)
    end
end

-- Group sync helpers (opt-in). Names are normalized like CHAT_MSG_ADDON senders.
local function GroupMembers()
    local members, raid = {}, IsInRaid and IsInRaid()
    for index = 1, raid and 40 or 4 do
        local unit = (raid and "raid" or "party") .. index
        if UnitExists and UnitExists(unit) and not (UnitIsUnit and UnitIsUnit(unit, "player")) then
            local name, realm = UnitName(unit)
            if type(name) == "string" and not (issecretvalue and issecretvalue(name)) then
                members[realm and realm ~= "" and (name .. "-" .. realm) or name] = true
            end
        end
    end
    return members
end

local function SyncGroup()
    local Sync = addon.GroupSync
    if not (S.settings and S.settings.groupSync and C_ChatInfo) then return end
    local channel = IsInRaid and IsInRaid() and "RAID" or IsInGroup and IsInGroup() and "PARTY" or nil
    if not channel then Sync.dirty = false return end
    local now, fighting = SessionTime(), InCombatLockdown and InCombatLockdown()
    if Sync.ReadyToSend(now, fighting) then
        local target = S.shownQuests and S.shownQuests[1] and S.shownQuests[1].id
        Sync.Send(C_ChatInfo, channel, Sync.Collect(addon.QuestLog.Read(C_QuestLog), C_QuestLog, target), now)
    elseif Sync.dirty and not fighting and not S.insights.syncScheduled and C_Timer then
        S.insights.syncScheduled = true
        C_Timer.After(Sync.INTERVAL, function() S.insights.syncScheduled = nil SyncGroup() end)
    end
end
addon.SyncGroup = SyncGroup

-- Sends the own tour to the group (explicit action; requires group sync to be on).
local function ShareTour()
    if not (S.settings and S.settings.groupSync) then print("FQN | " .. L.TourShareNeedsSync) return false end
    local channel = IsInRaid and IsInRaid() and "RAID" or IsInGroup and IsInGroup() and "PARTY" or nil
    local stops = S.workspace and S.workspace.plan and S.workspace.plan.stops or {}
    if not channel then print("FQN | " .. L.TourShareNoGroup) return false end
    if #stops == 0 then print("FQN | " .. L.TourShareEmpty) return false end
    local ok = addon.GroupSync.ShareTour(C_ChatInfo, channel, stops)
    print("FQN | " .. (ok and L.TourShared:format(math.min(#stops, addon.GroupSync.TOUR_MAX)) or L.TourShareFailed))
    return ok
end
addon.ShareTour = ShareTour

-- Local group test: simulated member plus a shared-tour offer; nothing is sent.
local function GroupTest(enable)
    local Sync = addon.GroupSync
    if not enable then
        Sync.StopTest()
        print("FQN | " .. L.GroupTestStopped)
    else
        local ok, stops = Sync.StartTest(addon.QuestLog.Read(C_QuestLog), C_QuestLog, SessionTime())
        if not ok then print("FQN | " .. L.GroupTestNoQuests) return end
        print("FQN | " .. L.GroupTestStarted:format(Sync.TEST_NAME))
        if stops then addon.NoticeQueue.Push("tourOffer", 35, function() return addon.ShowTourOffer(Sync.TEST_NAME, stops, AdoptTour) end) end
    end
    S.insights.groupAdvice = nil
    if S.measurableQuestIDs and TrackingVisible() then UpdateDistances() end
    ScheduleRefresh()
end
F.GroupTest = GroupTest

-- Adds shared stops for quests in the own log to the end of the own tour; nothing is removed.
function AdoptTour(stops)
    local quests, byID = addon.QuestLog.Read(C_QuestLog) or {}, {}
    for _, quest in ipairs(quests) do byID[quest.id] = quest end
    local present = {}
    for _, stop in ipairs(S.workspace and S.workspace.plan.stops or {}) do present[stop.id] = true end
    local added, missing = 0, 0
    for _, stop in ipairs(stops) do
        local quest = byID[stop.id]
        if not quest then missing = missing + 1
        elseif not present[stop.id] and S.workspace then
            S.workspace:Action("add", {quest = quest})
            present[stop.id], added = true, added + 1
        end
    end
    print("FQN | " .. L.TourAdopted:format(added, missing))
    ScheduleRefresh()
    return added, missing
end

local function UpdateSharedItems()
    S.insights.sharedItems = addon.QuestInsights.SharedItems(S.eligibleQuests,
        function(id) return C_QuestLog.GetQuestObjectives and C_QuestLog.GetQuestObjectives(id) end,
        integration.GetObjectiveItemID, C_Item and C_Item.GetItemCount or GetItemCount, GetItemInfo)
end

local function Refresh()
    S.refreshPending = false
    addon.UpdateRecovery()
    S.movementState = nil
    addon.QuestRewards.Clear()
    S.navigationSnapshot = nil
    S.routeChains = nil
    S.turnInLocations, S.questJourneys = {}, nil
    S.questMeasurements = nil
    S.objectiveDistances = nil
    S.questDestinations = {}
    local quests, used = addon.QuestLog.Read(C_QuestLog)
    S.insights.combatMarkers = integration.GetCombatMarkers(quests, C_QuestLog)
    S.insights.newlyAccepted = {}
    if quests then
        local present = {}
        for _, quest in ipairs(quests) do
            present[quest.id] = true
            if S.insights.previousQuestIDs and not S.insights.previousQuestIDs[quest.id] then S.insights.newlyAccepted[quest.id] = true end
        end
        S.insights.previousQuestIDs = present
        for id in pairs(S.insights.previousCamps or {}) do if not present[id] then S.insights.previousCamps[id] = nil end end
    end
    addon.OutingLedger.Sync(S.insights.roundLedger, quests, C_QuestLog and C_QuestLog.GetQuestObjectives,
        C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted)
    if S.workspace then S.workspace:Sync(quests, S.skippedQuestIDs) end
    if not S.insights.lastLevel or S.insights.lastLevel <= 0 then
        local level = UnitLevel and UnitLevel("player")
        if type(level) == "number" and level > 0 then S.insights.lastLevel = level end
    end
    S.questCapacity = addon.QuestCapacity.FromCount(used, C_QuestLog, MAX_QUESTLOG_QUESTS)
    addon.SyncExcursion(quests)
    if quests and S.heldQuest and addon.TrackerState.HoldEnded(S.heldQuest, quests) then
        S.heldQuest, S.manualQuestID, S.objectiveLock, S.outing = nil, nil, nil, nil
        UpdateQuestLogButton()
    end
    S.tracker:SetProgress(addon.TrackerState.Progress(quests, C_QuestLog, S.skippedQuestIDs))
    if quests then
        local present = {}
        for _, quest in ipairs(quests) do
            present[quest.id] = true
            local avoided = S.avoidedObjectives[quest.id]
            if avoided then
                local goals = C_QuestLog.GetQuestObjectives and C_QuestLog.GetQuestObjectives(quest.id)
                for index in pairs(avoided) do
                    if quest.readyToTurnIn or (goals and (not goals[index] or goals[index].finished)) then avoided[index] = nil end
                end
            end
        end
        for id in pairs(S.avoidedObjectives) do if not present[id] then S.avoidedObjectives[id] = nil end end
    end
    if not quests then
        S.nearbyOffers = nil
        S.tracker:RenderNearbyOffers()
        RenderEmpty(L.QuestLogUnavailable)
        return
    end

    local _, localMaps, targetMaps
    local mapType = Enum and Enum.UIMapType
    S.questMarkers, _, localMaps, targetMaps, S.playerZoneID = addon.QuestLocation.GetLocalQuestMarkers(C_Map, C_QuestLog, mapType, true)
    S.questTargetMaps = targetMaps
    S.distanceMaps = localMaps
    if not S.questMarkers or (IsInInstance and IsInInstance()) then
        S.nearbyOffers = nil
        S.tracker:RenderNearbyOffers()
        RenderEmpty(L.OutdoorMapUnavailable)
        return
    end
    S.objectiveMarkers, S.killMarkers = nil, nil
    if localMaps and integration.IsReady() then
        S.objectiveMarkers, S.killMarkers = integration.GetObjectiveMarkers(quests, C_QuestLog, targetMaps,
            S.settings.useQuestieKillLocations)
        for id, markers in pairs(S.objectiveMarkers or {}) do
            S.questMarkers[id] = markers
        end
    end
    SetTurnInMarkers(quests, mapType, targetMaps)
    addon.AdventureSupport.ApplyCorrections(S.questMarkers, quests, S.targetCorrections, C_QuestLog.GetQuestObjectives)
    local explicitID = S.manualQuestID or (S.workspace and S.workspace:Current())
    if explicitID then
        for _, quest in ipairs(quests) do
            if quest.id == explicitID and (not quest.special or quest.readyToTurnIn) then
                S.questMarkers[quest.id] = S.questMarkers[quest.id] or {}
                break
            end
        end
    end
    S.eligibleQuests = addon.QuestPrioritizer.Rank(quests, S.skippedQuestIDs, S.questMarkers)
    local excursionStop = addon.ExcursionPlan.Current(S.insights.excursion)
    S.eligibleQuests = addon.RepeatablePolicy.Quests(S.eligibleQuests, S.settings.repeatablePolicy,
        S.manualQuestID or S.workspace and S.workspace:Current() or excursionStop and excursionStop.quest.id)
    UpdateSharedItems()
    if S.insights.pendingLevel then
        S.insights.levelReport = {entries = addon.QuestInsights.LevelChanges(S.eligibleQuests, S.insights.pendingLevel.before, S.insights.pendingLevel.after),
            deadline = SessionTime() + 60}
        S.insights.pendingLevel = nil
    end
    if #S.eligibleQuests == 0 then
        S.manualQuestID = nil
        S.heldQuest = nil
        RenderEmpty(L.NoMatchingQuests)
        RefreshNearbyOffers(localMaps, targetMaps, mapType)
        return
    end

    local measured = {}
    for _, quest in ipairs(S.eligibleQuests) do
        local markers = S.questMarkers and S.questMarkers[quest.id]
        if not quest.readyToTurnIn and not (S.objectiveMarkers and S.objectiveMarkers[quest.id]) then
            local destination = GetQuestDestination(quest.id)
            local target = destination and destination.questieTrigger
            if not target and (not markers or #markers == 0) then
                target = addon.QuestLocation.GetOutdoorWaypoint(C_Map, C_QuestLog, mapType, targetMaps, quest.id)
            end
            if target then
                target.objective = true
                markers = { target }
                S.questMarkers[quest.id] = markers
            end
        end
        if markers and #markers > 0 then
            measured[#measured + 1] = quest.id
        end
    end
    addon.AdventureSupport.ApplyCorrections(S.questMarkers, S.eligibleQuests, S.targetCorrections, C_QuestLog.GetQuestObjectives)
    local seenMeasurements = {}
    for _, id in ipairs(measured) do seenMeasurements[id] = true end
    for _, quest in ipairs(S.eligibleQuests) do
        if not seenMeasurements[quest.id] and S.questMarkers[quest.id] and #S.questMarkers[quest.id] > 0 then measured[#measured + 1] = quest.id end
    end
    if #S.eligibleQuests > 0 and integration.IsReady() then
        S.routeChains = addon.QuestieRoutes.GetChains(C_Map, C_QuestLog, S.eligibleQuests, S.questMarkers,
            S.killMarkers, S.skippedQuestIDs, targetMaps)
    end
    S.measurableQuestIDs = #measured > 0 and measured or nil
    if not S.measurableQuestIDs then S.objectiveLock = nil end
    if not S.measurableQuestIDs or not TrackingVisible() then
        local level = UnitLevel and UnitLevel("player")
        local ranked = addon.QuestPrioritizer.RankByDistance(S.eligibleQuests, {}, nil, level)
        RenderQuestList(ranked, nil, nil, nil, level, addon.QuestLog.GetXPToNextLevel())
        UpdateMapMarker()
    end
    UpdateDistanceTicker()
    RefreshNearbyOffers(localMaps, targetMaps, mapType)
    addon.RefreshQuestNotepad()
    if S.settings.groupSync then addon.GroupSync.MarkDirty() SyncGroup() end
end

ScheduleRefresh = function()
    if not S.refreshPending then
        S.refreshPending = true
        -- In combat, coalesce bursts of quest-log events into fewer full rebuilds.
        C_Timer.After(InCombatLockdown and InCombatLockdown() and 1 or 0.1, addon.ErrorLog.Wrap("refresh", Refresh))
    end
end

-- Light path for bag, gear and mount changes: quest log and markers are unchanged.
local function RefreshItems()
    if S.refreshPending then return end
    if not (S.eligibleQuests and S.measurableQuestIDs and TrackingVisible()) then return ScheduleRefresh() end
    UpdateSharedItems()
    UpdateDistances()
    if RefreshNearbyOffers then RefreshNearbyOffers(S.distanceMaps, S.questTargetMaps, Enum and Enum.UIMapType) end
end

local function CanPinQuest(id)
    return type(id) == "number" and id > 0 and C_QuestLog and C_QuestLog.IsOnQuest
        and C_QuestLog.IsOnQuest(id) and not S.skippedQuestIDs[id]
        and not (C_QuestLog.IsFailed and C_QuestLog.IsFailed(id))
        and not (C_QuestLog.IsQuestDisabledForSession and C_QuestLog.IsQuestDisabledForSession(id))
        and (not addon.QuestLog.IsSpecialQuest(C_QuestLog, id) or (S.questMarkers and S.questMarkers[id] ~= nil))
end

UpdateQuestLogButton = function()
    if not S.questLogButton then return end
    local id = S.questLogDetails.questID
    local selected = id ~= nil and id == S.manualQuestID
    S.questLogButton:SetText(selected and L.ClearActiveQuest or L.SetActiveQuest)
    S.questLogButton:SetShown(selected or CanPinQuest(id) == true)
end

local function ApplyQuestAction(action, value)
    if action == "prioritize" then addon.PauseExcursion() end
    local state = { held = S.heldQuest, manual = S.manualQuestID, lock = S.objectiveLock, outing = S.outing,
        flying = flight.active, flightID = flight.questID, quest = S.shownQuests and S.shownQuests[1],
        distances = S.objectiveDistances, avoided = S.avoidedObjectives, previous = S.previousObjectives,
        skipped = S.skippedQuestIDs, order = S.skipOrder }
    local effect = addon.QuestActions.Apply(state, action, value)
    S.heldQuest, S.manualQuestID, S.objectiveLock, S.outing = state.held, state.manual, state.lock, state.outing
    flight.questID, S.avoidedObjectives, S.skipOrder = state.flightID, state.avoided, state.order
    if S.workspace then
        if effect.selection then
            S.workspace.pending = nil
            if S.manualQuestID then
                S.workspace.plan.running = false
                S.workspace.context.cancelReturn()
            end
        end
        S.workspace:Save()
    end
    if effect.selection then UpdateQuestLogButton() end
    if effect.undo then S.tracker:ShowUndoSkip(effect.undo) end
    if effect.refresh then ScheduleRefresh() end
    if effect.measure then UpdateDistances() end
end

local function SelectQuest(questID)
    S.insights.levelHold = nil
    if questID or addon.ExcursionPlan.Current(S.insights.excursion) then addon.PauseExcursion() end
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
    if S.questLogButton or not (QuestMapFrame and QuestMapFrame.DetailsFrame and hooksecurefunc
        and QuestMapFrame_ShowQuestDetails) then return end
    S.questLogDetails = QuestMapFrame.DetailsFrame
    local back = S.questLogDetails.BackFrame and S.questLogDetails.BackFrame.BackButton
    S.questLogButton = CreateFrame("Button", nil, S.questLogDetails.BackFrame or S.questLogDetails, "UIPanelButtonTemplate")
    S.questLogButton:SetSize(165, 22)
    if back then
        S.questLogButton:SetPoint("LEFT", back, "RIGHT", 7, 0)
    else
        S.questLogButton:SetPoint("TOPRIGHT", -25, -14)
    end
    S.questLogButton:SetScript("OnClick", function()
        local id = S.questLogDetails.questID
        if id == S.manualQuestID then
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
        if id == S.manualQuestID then
            menu:CreateButton(L.ClearActiveQuest, function() SelectQuest(nil) end)
        elseif CanPinQuest(id) then
            menu:CreateButton(L.SetActiveQuest, function()
                if CanPinQuest(id) then SelectQuest(id) end
            end)
        end
    end)
end

local function AddQuestieTrackerMenu()
    if S.questieTrackerMenuHooked or not (integration.IsReady() and hooksecurefunc) then return end
    local ok, menu = pcall(QuestieLoader.ImportModule, QuestieLoader, "TrackerMenu")
    if not (ok and menu and type(menu.addShowInQuestLogOption) == "function") then return end
    hooksecurefunc(menu, "addShowInQuestLogOption", function(entries, quest)
        local id = quest and quest.Id
        if not CanPinQuest(id) then return end
        entries[#entries + 1] = {
            text = id == S.manualQuestID and L.ClearActiveQuest or L.SetActiveQuest,
            func = function()
                if id == S.manualQuestID then
                    SelectQuest(nil)
                elseif CanPinQuest(id) then
                    SelectQuest(id)
                end
            end,
        }
    end)
    S.questieTrackerMenuHooked = true
end

local function ConnectQuestie()
    AddQuestieTrackerMenu()
    local api = Questie and Questie.API
    if api and api.RegisterOnReady and not S.questieReadyRegistered then
        S.questieReadyRegistered = pcall(api.RegisterOnReady, function()
            AddQuestieTrackerMenu()
            UpdateQuestieTicker()
            ScheduleRefresh()
        end)
    end
end

GetQuestDestination = function(questID)
    local measurement = S.questMeasurements and S.questMeasurements[questID]
    local markers = S.questMarkers and S.questMarkers[questID]
    local marker = measurement and measurement.marker or markers and markers[1]
    if not measurement and S.avoidedObjectives[questID] then
        marker = nil
        for _, candidate in ipairs(markers or {}) do
            if not S.avoidedObjectives[questID][candidate.objectiveIndex] then marker = candidate break end
        end
        if not marker then return end
    end
    if not (C_Map and markers) then return end
    local cached = S.questDestinations[questID]
    if cached and cached.marker == marker then return cached end
    local mapType = Enum and Enum.UIMapType
    local ready = C_QuestLog and C_QuestLog.IsComplete and C_QuestLog.IsComplete(questID)
    local mapID, target, turnInName, questieTrigger
    if marker and ((S.objectiveMarkers and S.objectiveMarkers[questID]) or marker.objective or marker.outdoorTurnIn or marker.personalCorrection) then
        mapID = marker.mapID
        turnInName = marker.turnInName
    elseif integration.IsReady() then
        if ready and S.questTargetMaps and mapType then
            local turnIn, _, name = addon.QuestieRoutes.GetOutdoorTurnInMarker(C_Map, mapType, S.questTargetMaps, questID)
            mapID = turnIn and turnIn.mapID
            target = turnIn
            turnInName = name
        elseif not ready then
            local ambiguous, trigger
            mapID, ambiguous, trigger = addon.QuestieRoutes.GetObjectiveMap(C_Map, mapType, questID)
            if ambiguous and marker then mapID = marker.mapID end
            if trigger and addon.QuestLocation.IsOutdoorMap(C_Map, mapType, trigger.mapID, S.questTargetMaps) then
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
    S.questDestinations[questID] = destination
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
    S.markedQuestID = questID
    addon.ShowQuestMapMarker(target, ClearMapMarker, CurrentMapRoute(questID))
    if EventRegistry and EventRegistry.TriggerEvent then
        EventRegistry:TriggerEvent("MapCanvas.PingQuestID", questID)
    end
end

local function OpenOfferMap(id)
    local offer
    for _, candidate in ipairs(S.nearbyOffers or {}) do
        if candidate.id == id then offer = candidate break end
    end
    if not (offer and offer.marker and C_Map and C_Map.OpenWorldMap) then return end
    if InCombatLockdown and InCombatLockdown() then print(L.CombatMap) return end
    S.markedQuestID = nil
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
    S.markedQuestID = nil
    C_Map.OpenWorldMap(stop.target.mapID)
    addon.ShowQuestMapMarker(stop.target, ClearMapMarker)
end

local function ShowTargetReport(questID, isOffer)
    local measured = S.questMeasurements and S.questMeasurements[questID]
    if isOffer then
        for _, offer in ipairs(S.nearbyOffers or {}) do if offer.id == questID then measured = offer break end end
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
    for _, candidate in ipairs(S.eligibleQuests or {}) do if candidate.id == questID then quest = candidate break end end
    local current = quest and S.questMeasurements and S.questMeasurements[questID]
    local alternative = quest and addon.CampAlternatives.Switch(C_Map, quest, current, S.questMarkers[questID], S.campAvoidance, SessionTime())
    if not alternative then print(L.NoAlternativeCamp) return end
    local held = S.heldQuest
    SelectQuest(questID)
    if held and held.id == questID then S.heldQuest = held end
    S.objectiveLock = {questID = questID, index = alternative.objectiveIndex}
    S.previousObjectives[questID], S.outing = nil, nil
end

-- Quest context menu of the navigator and quest log (Core/NavigatorQuestMenu.lua).
for name, fn in pairs({
    ApplyQuestAction = ApplyQuestAction, CanPinQuest = CanPinQuest,
    ClearTemporaryFeedback = ClearTemporaryFeedback, OpenOfferMap = OpenOfferMap, OpenQuestMap = OpenQuestMap,
    OpenRouteStop = OpenRouteStop, RecordAccessChange = RecordAccessChange, ScheduleRefresh = ScheduleRefresh,
    SelectQuest = SelectQuest, SessionTime = SessionTime, ShowTargetReport = ShowTargetReport,
    SwitchCamp = SwitchCamp, ToggleQuestHold = ToggleQuestHold,
}) do F[name] = fn end
S.flight = flight
addon.NavigatorQuestMenu.Install(S, F)

-- Planning, outing, access point, notepad and skip actions of the navigator (Core/NavigatorPlanning.lua).
for name, fn in pairs({
    ApplyQuestAction = ApplyQuestAction, ClearTemporaryFeedback = ClearTemporaryFeedback,
    GetQuestDestination = GetQuestDestination, OpenRouteStop = OpenRouteStop,
    RecordAccessChange = RecordAccessChange, ScheduleRefresh = ScheduleRefresh, SelectQuest = SelectQuest,
    SessionTime = SessionTime, TrackingVisible = TrackingVisible, UpdateDirection = UpdateDirection,
    UpdateDirectionTicker = UpdateDirectionTicker, UpdateDistances = UpdateDistances,
}) do F[name] = fn end
addon.NavigatorPlanning.Install(S, F)

local function RegisterSettings()
    return addon.SettingsController.Register({
        getTracker = function() return S.tracker end,
        ShowZones = F.ShowZones, ShowFixture = F.ShowFixture,
        ShowPlanning = F.ShowPlanning,
        ShowFeedback = F.ShowFeedback, ShowProfiles = F.ShowProfiles, UpdateMapMarker = UpdateMapMarker,
        ShowHistory = function() addon.ShowUndoHistory(addon.Undo) end, ShowLevelChanges = F.ShowLevelChanges,
        settings = S.settings,
        ShowSession = ShowSession,
        ShowAccessManager = F.ShowAccessManager,
        ShowNotepad = F.ShowNotepad,
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
    local wasArrowOnly = S.settings.displayMode == "arrow"
    S.settings.displayMode = mode
    S.settings.hidden = mode ~= "full"
    local wasShown = S.tracker:IsShown()
    S.tracker:SetShown(mode == "full")
    if wasShown == S.tracker:IsShown() then
        UpdateDistanceTicker()
        UpdateQuestieTicker()
    end
    if mode == "full" and wasArrowOnly then ScheduleRefresh() end
end

local function CycleDisplayMode()
    if S.settings.displayMode == "full" then
        SetDisplayMode(S.settings.showDirectionArrow and "arrow" or "off")
    elseif S.settings.displayMode == "arrow" then
        SetDisplayMode("off")
    else
        SetDisplayMode("full")
    end
end

local function ToggleTracker()
    SetDisplayMode(S.tracker:IsShown() and "off" or "full")
end

local function OpenSettings()
    addon.ShowQuickSettings(addon.SettingsController.catalog, S.settings,
        function() Settings.OpenToCategory(S.settingsCategory:GetID()) end, F.ShowPlanning, F.ShowFeedback, F.ShowProfiles,
        function() addon.ShowUndoHistory(addon.Undo) end)
end

local function AddonVersion()
    return C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(addonName, "Version")
end

function addon.ConfigureUXHub()
    addon.UI.ToolHub.Configure({
        finder = function() addon.OpenWorkspace("finder") end, tour = function() addon.OpenWorkspace("tour") end,
        details = function() if S.tracker and S.tracker.OpenDetails then S.tracker:OpenDetails() end end,
        notes = F.ShowNotepad, feedback = F.ShowFeedback, automatic = F.ShowPlanning, zones = F.ShowZones,
        access = F.ShowAccessManager, detour = function() addon.OpenDetourTools() end,
        session = ShowSession, changes = function() addon.ShowUndoHistory(addon.Undo) end,
        settings = OpenSettings, profiles = F.ShowProfiles,
        share = function() addon.ShowDisplayTransfer(S.settings, addon.SettingsController.catalog) end,
        outing = function() addon.OpenExcursionFromArea(nil, S.insights.excursion ~= nil) end,
        adventure = function() addon.OpenAdventure() end,
        commands = function() addon.ShowCommandMenu(S.settings) end,
        whatsnew = function() addon.ShowReleaseNotes(S.settings, AddonVersion()) end,
        help = function() addon.ShowUXHelp({problem = addon.OpenProblemReport, diagnostic = ShowDiagnostics,
            guide = function() addon.ShowIntroduction(S.settings) end,
            updates = function() addon.ShowReleaseNotes(S.settings, AddonVersion()) end}) end,
    }, {simple = function() return S.settings and S.settings.simpleNavigator == true end, settings = S.settings})
end

local function InitializeWorkspace(character)
    S.workspace = addon.PlanningRuntime.New(character, S.settings, {
        priority = function() return S.manualQuestID, S.heldQuest end,
        read = function()
            return {quests = addon.QuestLog.Read(C_QuestLog), offers = S.nearbyOffers, skipped = S.skippedQuestIDs,
                measurements = S.questMeasurements, turnInTour = S.navigationSnapshot and S.navigationSnapshot.turnInTour,
                repeatablePolicy = S.settings.repeatablePolicy}
        end,
        select = function(id, policy)
            if id and not CanPinQuest(id) then return false end
            if policy == "complete" or policy == "turnIn" then ApplyQuestAction("prioritize", {id = id, turnIn = policy == "turnIn"})
            else SelectQuest(id) end
            return true
        end,
        destination = GetQuestDestination, restore = F.RestoreQuest, map = OpenRouteStop,
        changed = ScheduleRefresh,
        prepareStart = function() addon.PauseExcursion() S.temporaryDetour, S.detourMeasurement = nil, nil S.tracker:SetDetour(nil) end,
        cancelReturn = function()
            if S.temporaryDetour and S.temporaryDetour.tourReturn then S.temporaryDetour, S.detourMeasurement = nil, nil S.tracker:SetDetour(nil) end
        end,
    })
end

local function RunSelfTest()
    local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local position = mapID and C_Map.GetPlayerMapPosition and C_Map.GetPlayerMapPosition(mapID, "player")
    local quests = addon.QuestLog.Read(C_QuestLog)
    local text = addon.SelfTest.Run(getfenv and getfenv(1) or _G, {version = AddonVersion(),
        build = GetBuildInfo and select(1, GetBuildInfo()), locale = GetLocale and GetLocale(),
        mapID = mapID or "none", position = position ~= nil, quests = quests and #quests})
    addon.ShowTextWindow("selftest", text, L.SelfTestTitle, L.SelfTestHelp)
end
F.RunSelfTest = RunSelfTest

local function ShowSetup(done)
    return addon.ShowSetup(S.settings, {catalog = addon.SettingsController.catalog, done = done,
        questie = C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Questie") and true or false,
        setDisplayMode = SetDisplayMode})
end

-- Registration of all /fqn commands (Core/NavigatorCommands.lua).
for name, fn in pairs({
    AddonVersion = AddonVersion, CaptureSessionXP = CaptureSessionXP, OpenSettings = OpenSettings,
    ScheduleRefresh = ScheduleRefresh, SessionTime = SessionTime, ShowDiagnostics = ShowDiagnostics,
    ShowSession = ShowSession, ShowSetup = ShowSetup, ShowTargetReport = ShowTargetReport,
    ToggleTracker = ToggleTracker, UpdateMapMarker = UpdateMapMarker,
}) do F[name] = fn end
addon.NavigatorCommands.Install(S, F)

local function AddonLoaded(name)
    if name == addonName and not S.tracker then
        S.settings = ForeverQuestNavigatorDB
        S.insights.hadSettings = type(S.settings) == "table" and next(S.settings) ~= nil
        if type(S.settings) ~= "table" then
            S.settings = {}
            ForeverQuestNavigatorDB = S.settings
        end
        addon.SettingsDefaults.Normalize(S.settings, LIMITS, not S.insights.hadSettings)
        if type(S.settings.errorLog) ~= "table" then S.settings.errorLog = {} end
        addon.ErrorLog.Attach(S.settings.errorLog)
        addon.ErrorLog.version = AddonVersion()
        addon.UI.iconLabels = S.settings.iconLabels ~= false
        addon.CanvasMarkers.showLine = S.settings.showRouteLine ~= false
        if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
            pcall(C_ChatInfo.RegisterAddonMessagePrefix, addon.GroupSync.PREFIX)
        end
        addon.SetLanguage(S.settings.language)
        S.insights.lastLevel = UnitLevel and UnitLevel("player")
        addon.UI.Theme.Apply(S.settings.highContrast, S.settings.theme, S.settings.reducedColors)
        F.LoadSkippedQuests()
        local character = addon.SettingsDefaults.NormalizeCharacter(ForeverQuestNavigatorCharacterDB)
        InitializeWorkspace(character)
        S.questNotes, S.targetCorrections = character.questNotes, character.targetCorrections
        S.insights.laterQuests, S.insights.knownVendors = character.laterQuests, character.knownVendors
        S.insights.hiddenOffers, S.savedAccessPoints = character.hiddenOffers, character.accessPoints
        S.session = addon.Session.New(character.session, SessionTime())
        S.insights.offerRecap = S.session:ShouldOfferRecap(WallClock(), 1800)
        character.session = S.session.data
        flight.confirmedPoints, flight.routes = character.confirmedFlightPoints, character.flightRoutes

        S.settingsCategory = RegisterSettings()
        local version = C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(addonName, "Version")
        S.insights.updateVersion = addon.ReleaseNotes.Initialize(S.settings, version, S.insights.hadSettings)
        S.tracker = addon.CreateQuestTracker(S.settings, {
            skip = F.SkipQuest,
            resetSkips = F.ResetSkips,
            restore = F.RestoreQuest,
            resumeAutoSelect = function() SelectQuest(nil) end,
            toggleQuestHold = ToggleQuestHold,
            getQuestHold = function() return S.heldQuest ~= nil end,
            openSettings = OpenSettings,
            openFinder = function() addon.OpenWorkspace("finder") end,
            openQuestMap = OpenQuestMap,
            openQuestMenu = F.OpenQuestMenu,
            openOfferMap = OpenOfferMap,
            openRouteStop = OpenRouteStop,
            selectObjective = SelectObjective,
            avoidObjective = AvoidObjective,
            restoreAvoidedObjectives = RestoreAvoidedObjectives,
            hideTracker = function() SetDisplayMode("off") end,
            refreshMeasurements = UpdateDistances,
        }, version)
        S.tracker:UpdateListSettings()
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
                local quest = S.shownQuests and S.shownQuests[1]
                if quest then OpenQuestMap(quest.id) end
            elseif action == "hold" then ToggleQuestHold()
            elseif action == "plan" then F.ShowPlanning()
            elseif action == "feedback" then F.ShowFeedback()
            elseif action == "camp" then SwitchCamp(S.shownQuests and S.shownQuests[1] and S.shownQuests[1].id) end
        end
        AddQuestLogMenu()
        local function UpdateTrackers()
            UpdateDistanceTicker()
            UpdateQuestieTicker()
        end
        S.tracker:HookScript("OnShow", UpdateTrackers)
        S.tracker:HookScript("OnHide", UpdateTrackers)

        addon.EventController.RegisterRuntime(events)

        F.RegisterCommands()
        SLASH_FOREVERQUESTNAVIGATOR1 = "/fqn"
        SlashCmdList.FOREVERQUESTNAVIGATOR = function(message)
            addon.Commands.Dispatch(message, S.settings.simpleNavigator)
        end

        ConnectQuestie()
        addon.ConfigureUXHub()
        ScheduleRefresh()
    elseif S.tracker and name == "Questie" then
        ConnectQuestie()
    end
    if S.tracker then AddQuestLogButton() end
end

events:RegisterEvent("ADDON_LOADED")
addon.EventController.Bind(events, {
    recovery = addon.UpdateRecovery,
    captureXP = CaptureSessionXP,
    turnIn = function(arg, rewardXP)
        if S.insights.levelHold and S.insights.levelHold.id == arg then S.insights.levelHold = nil end
        S.insights.lastTurnIn, S.insights.turnInUntil = arg, SessionTime() + 10
        addon.ExcursionPlan.HandedIn(S.insights.excursion, arg, rewardXP)
        if not S.session then return end
        local title
        for _, quest in ipairs(S.eligibleQuests or {}) do if quest.id == arg then title = quest.title break end end
        S.session:TurnIn(arg, title, rewardXP, GetRealZoneText and GetRealZoneText() or nil, WallClock())
        S.session:Save(SessionTime(), WallClock())
    end,
    saveSession = function() if S.session then S.session:Save(SessionTime(), WallClock()) end if S.workspace then S.workspace:Save() end end,
    loaded = AddonLoaded,
    hasMeasurements = function() return S.measurableQuestIDs ~= nil end,
    visible = TrackingVisible,
    measure = UpdateDistances,
    levelUp = function(level)
        if S.shownQuests and S.shownQuests[1] then S.insights.levelHold = {id = S.shownQuests[1].id, untilTime = SessionTime() + 60} end
        S.outing, S.distanceOrder = nil, nil
        if type(level) == "number" and level > 0 then
            if S.insights.lastLevel and S.insights.lastLevel > 0 and level > S.insights.lastLevel then
                S.insights.pendingLevel = {before = S.insights.lastLevel, after = level}
            end
            if not S.insights.lastLevel or level > S.insights.lastLevel then S.insights.lastLevel = level end
        end
    end,
    enterWorld = function()
        if S.insights.offerRecap and S.session then
            S.insights.offerRecap = nil
            addon.NoticeQueue.Push("recap", 40, function()
                return addon.ShowSessionRecapNotice(S.session:Recap(SessionTime(), SuggestZone()), {
                    open = ShowSession,
                    reset = function() addon.Commands.Dispatch("session reset") end,
                })
            end)
        end
        AddQuestLogButton()
        if not S.minimapButton then
            S.minimapButton = addon.CreateMinimapButton(S.settings, CycleDisplayMode, OpenSettings)
        end
        if S.workspace and S.workspace.pending and not S.workspace.announced then
            S.workspace.announced = true print("FQN | " .. L.ResumeOffer)
        end
    end,
    introduction = function()
        -- Automatic windows go through the notice queue: one at a time, never in combat or on a taxi.
        local Queue = addon.NoticeQueue
        local function Introduction()
            Queue.Push("introduction", 20, function() return addon.ShowIntroduction(S.settings) end)
        end
        if S.settings and not S.settings.introSeen then
            if not S.insights.hadSettings and not S.settings.setupDone then
                Queue.Push("setup", 10, function() return ShowSetup(Introduction) end)
            else Introduction() end
        end
        if S.settings and S.settings.introSeen and S.insights.updateVersion and not addon.DemoMode.IsActive() then
            local version = S.insights.updateVersion
            S.insights.updateVersion = nil
            if S.settings.showUpdateNotes then
                Queue.Push("updateNotes", 30, function() return addon.ShowReleaseNotes(S.settings, version) end)
            else S.settings.lastSeenVersion = version end
        end
    end,
    taxi = function(event)
        addon.NoticeQueue.Pump()
        if event == "TAXIMAP_OPENED" then flight.taxiMapOpen = true end
        if event == "TAXIMAP_CLOSED" or event == "PLAYER_ENTERING_WORLD" then flight.taxiMapOpen = false end
        if flight.taxiMapOpen and (event == "TAXIMAP_OPENED" or event == "TAXI_NODE_STATUS_CHANGED") then
            ConfirmFlightPoints()
        end
    end,
    removeQuest = function(id)
        S.temporaryFeedback[id] = nil
        S.campAvoidance[id] = nil
        S.skippedQuestIDs[id] = nil
        if S.manualQuestID == id then S.manualQuestID, S.heldQuest = nil, nil end
    end,
    updateQuestLog = UpdateQuestLogButton,
    refresh = ScheduleRefresh,
    refreshItems = RefreshItems,
    refreshGroup = function()
        if addon.GroupSync.Prune(GroupMembers()) then S.insights.groupAdvice = nil end
        if S.settings and S.settings.groupSync then addon.GroupSync.MarkDirty() SyncGroup() end
        ScheduleRefresh()
    end,
    addonMessage = function(prefix, text, _, sender)
        if prefix ~= addon.GroupSync.PREFIX or not (S.settings and S.settings.groupSync) then return end
        local name = Ambiguate and type(sender) == "string" and Ambiguate(sender, "none") or sender
        if type(text) == "string" and text:sub(1, 3) == "T1|" then
            local stops = GroupMembers()[name] and addon.GroupSync.DecodeTour(text)
            if stops then addon.NoticeQueue.Push("tourOffer", 35, function() return addon.ShowTourOffer(name, stops, AdoptTour) end) end
            return
        end
        if addon.GroupSync.Receive(name, text, GroupMembers(), SessionTime()) then
            S.insights.groupAdvice = nil
            if S.measurableQuestIDs and TrackingVisible() then UpdateDistances() end
        end
    end,
    itemRewardsUpdated = function()
        if addon.QuestRewards.HasPending() then addon.QuestRewards.Clear() return true end
    end,
})
