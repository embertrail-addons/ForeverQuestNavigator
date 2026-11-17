local _, addon = ...
local QuestRoute = {}
addon.QuestRoute = QuestRoute

local SHARED_STOP_RADIUS = 40
local MINIMUM_SAVING = 40
local OUTING_RADIUS = 500
local MAX_APPROACH_DETOUR = 100
local MINIMUM_OUTING_SAVING = 120

function QuestRoute.GetStopsOnApproach(mapAPI, quest, ranked, measurements, playerLevel)
    local main = measurements and measurements[quest.id]
    local distance = main and addon.QuestLocation.GetDistanceMetric(mapAPI, main.marker)
    if not distance then return end
    local stops = {}
    for _, candidate in ipairs(ranked) do
        local target = measurements[candidate.id]
        if candidate.id ~= quest.id and target and target.yards < main.yards
            and not addon.QuestPrioritizer.IsLowPriority(candidate, playerLevel) then
            local gap = distance(main.marker, target.marker)
            if gap and target.yards + gap - main.yards <= MAX_APPROACH_DETOUR then
                stops[#stops + 1] = { quest = candidate, yards = target.yards }
            end
        end
    end
    table.sort(stops, function(a, b)
        if a.yards ~= b.yards then return a.yards < b.yards end
        return a.quest.id < b.quest.id
    end)
    return stops
end

function QuestRoute.RecommendLevelUp(mapAPI, ranked, measurements, playerLevel, xpNeeded)
    if not xpNeeded or type(playerLevel) ~= "number" or not (playerLevel > 0 and playerLevel < math.huge) then return end
    local main = ranked[1] and measurements[ranked[1].id]
    if not main then return end
    local nextStops = {}
    for _, quest in ipairs(ranked) do
        local level = addon.QuestPrioritizer.GetLevel(quest)
        local gap = level and level - playerLevel
        if (gap == 3 or gap == 1) and not quest.readyToTurnIn and measurements[quest.id] then
            nextStops[#nextStops + 1] = quest
        end
    end
    if #nextStops == 0 then return end
    for _, quest in ipairs(ranked) do
        local stop = measurements[quest.id]
        if quest.readyToTurnIn and stop and stop.yards <= main.yards + MAX_APPROACH_DETOUR then
            local reward = addon.QuestLog.GetTurnInXP(quest)
            if reward and reward >= xpNeeded then
                local distance = addon.QuestLocation.GetDistanceMetric(mapAPI, stop.marker)
                local nextQuest, nearest
                for _, candidate in ipairs(nextStops) do
                    local range = distance and distance(stop.marker, measurements[candidate.id].marker)
                    if range and range <= OUTING_RADIUS and (not nearest or range < nearest) then
                        nextQuest, nearest = candidate, range
                    end
                end
                if nextQuest then return quest, nextQuest end
            end
        end
    end
end

-- Compare orders that visit the same targets, with no assumed return destination.
function QuestRoute.PlanOuting(mapAPI, ranked, measurements, playerLevel)
    local anchor = ranked[1]
    local main = anchor and measurements[anchor.id]
    if not main or addon.QuestPrioritizer.IsLowPriority(anchor, playerLevel) then return end
    local distance = addon.QuestLocation.GetDistanceMetric(mapAPI, main.marker)
    if not distance then return end

    local candidates = {}
    for index = 2, #ranked do
        local quest = ranked[index]
        local target = measurements[quest.id]
        if target and not addon.QuestPrioritizer.IsLowPriority(quest, playerLevel) then
            local gap = distance(main.marker, target.marker)
            if gap then
                local detour = math.max(0, target.yards + gap - main.yards)
                local onApproach = target.yards < main.yards and detour <= MAX_APPROACH_DETOUR
                if onApproach or gap <= OUTING_RADIUS then
                    candidates[#candidates + 1] = { quest = quest, score = onApproach and detour or gap }
                end
            end
        end
    end
    if #candidates == 0 then return end
    table.sort(candidates, function(a, b)
        if a.score ~= b.score then return a.score < b.score end
        return a.quest.id < b.quest.id
    end)

    local stops = { anchor, candidates[1].quest, candidates[2] and candidates[2].quest }
    local function Length(first, second, third)
        local a, b = measurements[stops[first].id], measurements[stops[second].id]
        local leg = distance(a.marker, b.marker)
        if not leg then return math.huge end
        if third then
            local tail = distance(b.marker, measurements[stops[third].id].marker)
            if not tail then return math.huge end
            leg = leg + tail
        end
        return a.yards + leg
    end
    local orders = #stops == 2 and { {1, 2}, {2, 1} }
        or { {1, 2, 3}, {1, 3, 2}, {2, 1, 3}, {2, 3, 1}, {3, 1, 2}, {3, 2, 1} }
    local bestOrder, bestLength, baseline, bestGain
    for _, order in ipairs(orders) do
        local first = stops[order[1]]
        local length = Length(unpack(order))
        if first == anchor then
            if not baseline or length < baseline then
                bestOrder, bestLength, baseline, bestGain = order, length, length, MINIMUM_OUTING_SAVING
            end
        elseif measurements[first.id].yards < main.yards then
            local gain = baseline - length
            if gain > bestGain then bestOrder, bestLength, bestGain = order, length, gain end
        end
    end
    if bestLength == math.huge then return end
    local ordered = {}
    for index, position in ipairs(bestOrder) do ordered[index] = stops[position] end
    return { stops = ordered, saving = baseline - bestLength }
end

local function MeasureChain(distance, a, b, chain)
    local firstLeg = distance(a, b)
    local toFinisher = distance(b, chain.finisher)
    if not (firstLeg and toFinisher) or (chain.ready and toFinisher > SHARED_STOP_RADIUS) then return end
    local legs, shared = {}, {}
    local previous = chain.finisher
    for index, stop in ipairs(chain.stops) do
        local leg, gap = distance(previous, stop), distance(a, stop)
        if not (leg and gap) then return end
        legs[index], shared[index] = leg, gap
        previous = stop
    end
    return firstLeg, legs, shared
end

-- Both orders visit the same chain stops. Compare inserting A before B
-- with inserting A at a later stop that is near A.
function QuestRoute.Recommend(mapAPI, ranked, measurements, chains, playerLevel)
    local original = ranked[1]
    local a = original and measurements[original.id]
    if not (a and a.marker and chains) or addon.QuestPrioritizer.IsLowPriority(original, playerLevel) then return end

    local distance = addon.QuestLocation.GetDistanceMetric(mapAPI, a.marker)
    if not distance then return end

    local best, saving, sharedDepth
    local bestGain = MINIMUM_SAVING
    local originalPenalty = addon.QuestPrioritizer.GetLevelPenalty(original, playerLevel)
    for index = 2, #ranked do
        local candidate = ranked[index]
        local b, chain = measurements[candidate.id], chains[candidate.id]
        local firstLeg, legs, shared
        if b and b.marker and chain and not addon.QuestPrioritizer.IsLowPriority(candidate, playerLevel) then
            firstLeg, legs, shared = MeasureChain(distance, a.marker, b.marker, chain)
        end
        if firstLeg then
            local savingsBeforeInsertion = a.yards + firstLeg - b.yards
            local penalty = addon.QuestPrioritizer.GetLevelPenalty(candidate, playerLevel)
            local extraDifficulty = math.max(0, penalty - originalPenalty)
            if savingsBeforeInsertion - extraDifficulty >= bestGain then
                for stopIndex, stop in ipairs(chain.stops) do
                    local sharedDistance = shared[stopIndex]
                    if sharedDistance <= SHARED_STOP_RADIUS then
                        local nextIndex = stopIndex + 1
                        local insertionCost = sharedDistance
                        if shared[nextIndex] then
                            insertionCost = insertionCost + shared[nextIndex] - legs[nextIndex]
                        end
                        local gain = savingsBeforeInsertion - insertionCost
                        if gain - extraDifficulty > bestGain then
                            best, saving, sharedDepth = candidate, gain, stop.depth
                            bestGain = gain - extraDifficulty
                        end
                    end
                end
            end
        end
    end
    if not best then return end
    local chain = chains[best.id]
    return best, {
        saving = saving, depth = sharedDepth,
        original = original, followUps = chain.followUps,
    }
end
