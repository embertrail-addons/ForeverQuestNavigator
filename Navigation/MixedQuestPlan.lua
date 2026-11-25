local _, addon = ...
local Mixed = {}
addon.MixedQuestPlan = Mixed
local L = addon.L

local function Gap(api, a, b)
    local metric = a and b and addon.QuestLocation.GetDistanceMetric(api, a)
    return metric and metric(a, b)
end

function Mixed.Filter(offers, hidden, excluded, pending)
    local result = {}
    for _, offer in ipairs(offers or {}) do
        if not (hidden and hidden[offer.id] or excluded and excluded[offer.id] or pending and pending[offer.id]) then result[#result + 1] = offer end
    end
    return result
end

function Mixed.Gather(area, quests, measurements, options)
    if not area then return end
    local result, seen = {entries = {}}, {}
    for key, value in pairs(area) do if key ~= "entries" then result[key] = value end end
    for _, entry in ipairs(area.entries or {}) do result.entries[#result.entries + 1] = entry seen[entry.quest.id] = true end
    local direct = options.fromPlayer and options.fromPlayer(area.target)
    if direct then for _, quest in ipairs(quests or {}) do
        local m = measurements and measurements[quest.id]
        local leg = m and m.marker and Gap(options.api, m.marker, area.target)
        if not seen[quest.id] and quest.readyToTurnIn and m and m.yards and leg
            and not (options.feedback and options.feedback[quest.id]) and m.yards + leg - direct <= 400 then
            result.entries[#result.entries + 1] = {quest = quest, target = m.marker, yards = m.yards}
            seen[quest.id] = true
        end
    end end
    return result
end

local function State(plan, capacity)
    local state = {accepted = {}, worked = {}, returned = {}, slots = capacity and capacity.free,
        reserve = capacity and capacity.reserve or 0, done = {}}
    if capacity and capacity.full then state.slots = 0 end
    for _, stop in ipairs(plan.stops) do
        if stop.action == "accept" then state.accepted[stop.quest.id] = false
        elseif state.accepted[stop.quest.id] == nil then state.accepted[stop.quest.id] = true end
        if stop.quest.readyToTurnIn then state.worked[stop.quest.id] = true end
    end
    return state
end
local function Eligible(stop, state)
    local id = stop.quest.id
    for _, dependency in ipairs(stop.dependsOn or {}) do if not state.accepted[dependency] then return false end end
    if stop.action == "accept" then return not state.accepted[id] and (state.slots == nil or state.slots > state.reserve) end
    if not state.accepted[id] then return false end
    return stop.action == "objective" and not state.worked[id] or stop.action == "turnIn" and state.worked[id] and not state.returned[id]
end
local function Apply(stop, state)
    local id = stop.quest.id
    if stop.action == "accept" then state.accepted[id] = true if state.slots then state.slots = state.slots - 1 end
    elseif stop.action == "objective" then state.worked[id] = true
    else state.returned[id] = true if state.slots then state.slots = state.slots + 1 end end
end

-- Bounded two-stop lookahead with precedence and simulated log capacity.
-- It compares coordinate journeys, not verified terrain or quest completion time.
function Mixed.Order(plan, options)
    local initial, anchors, pickups = State(plan, options.capacity), {}, {}
    for _, stop in ipairs(plan.stops) do
        if stop.action == "accept" then pickups[#pickups + 1] = stop
        elseif initial.accepted[stop.quest.id] then anchors[#anchors + 1] = stop.target end
    end
    for _, pickup in ipairs(pickups) do
        local best, approach = nil, options.fromPlayer and options.fromPlayer(pickup.target)
        for _, target in ipairs(anchors) do
            local direct = options.fromPlayer and options.fromPlayer(target)
            local leg = Gap(options.api, pickup.target, target)
            if direct and approach and leg then best = math.min(best or math.huge, math.max(0, approach + leg - direct)) end
            for _, other in ipairs(anchors) do
                local first, second, baseline = Gap(options.api, target, pickup.target), Gap(options.api, pickup.target, other), Gap(options.api, target, other)
                if first and second and baseline then best = math.min(best or math.huge, math.max(0, first + second - baseline)) end
            end
        end
        if best and best > (options.maxPickupDetour or 400) then
            Mixed.Skip(plan, pickup.quest.id, initial.accepted)
            plan.excludedOffers[pickup.quest.id] = nil
            plan.omittedPickups = (plan.omittedPickups or 0) + 1
        end
    end
    local state, ordered, remaining, current, total = State(plan, options.capacity), {}, {}, nil, 0
    for index, stop in ipairs(plan.stops) do remaining[index] = stop end
    while #remaining > 0 do
        local best, bestScore, bestLeg
        for index, stop in ipairs(remaining) do
            if Eligible(stop, state) then
                local leg = current and Gap(options.api, current, stop.target) or not current and options.fromPlayer and options.fromPlayer(stop.target)
                if type(leg) == "number" and leg >= 0 and leg < math.huge then
                    local nextState = addon.UndoHistory.Copy(state) Apply(stop, nextState)
                    local nextLeg
                    for otherIndex, other in ipairs(remaining) do
                        if index ~= otherIndex and Eligible(other, nextState) then
                            local distance = Gap(options.api, stop.target, other.target)
                            if distance and (not nextLeg or distance < nextLeg) then nextLeg = distance end
                        end
                    end
                    local downstream, known = 0, not (plan.missingByQuest and plan.missingByQuest[stop.quest.id])
                    if stop.action == "accept" then
                        local point = stop.target
                        for _, action in ipairs({"objective", "turnIn"}) do for _, other in ipairs(remaining) do
                            if other.quest.id == stop.quest.id and other.action == action then
                                local distance = Gap(options.api, point, other.target)
                                if distance then downstream = downstream + distance else known = false end
                                point = other.target break
                            end
                        end end
                    end
                    local level = addon.QuestPrioritizer.GetLevelPenalty(stop.quest, options.level)
                    local xp = plan.rewards and plan.rewards[stop.quest.id]
                    local bonus = stop.action == "accept" and ((stop.quest.planClass == "route" or stop.quest.planClass == "combination") and 50 or 0)
                        + (xp and math.min(60, xp / 50) or 0) or 0
                    local score = leg + (nextLeg or 0) * .35 + downstream * .2 + level - bonus + (not known and 300 or 0)
                    if not bestScore or score < bestScore or score == bestScore and stop.quest.id < remaining[best].quest.id then
                        best, bestScore, bestLeg = index, score, leg
                    end
                end
            end
        end
        if not best then plan.orderKnown = false return plan end
        local stop = table.remove(remaining, best)
        ordered[#ordered + 1] = stop total = total + bestLeg current = stop.target Apply(stop, state)
    end
    -- Shorten the greedy order with local moves that keep precedence and log capacity.
    local function Cost(stops)
        local sum, point = 0, nil
        for _, stop in ipairs(stops) do
            local leg = point and Gap(options.api, point, stop.target) or not point and options.fromPlayer and options.fromPlayer(stop.target)
            if type(leg) ~= "number" or leg < 0 or leg >= math.huge then return end
            sum, point = sum + leg, stop.target
        end
        return sum
    end
    local function Valid(stops)
        local check = State(plan, options.capacity)
        for _, stop in ipairs(stops) do
            if not Eligible(stop, check) then return false end
            Apply(stop, check)
        end
        return true
    end
    local improved, _, improvedTotal = addon.RouteOrder.Improve(ordered, Cost, Valid, 6)
    if improvedTotal and improvedTotal + 1 < total then ordered, total = improved, improvedTotal end
    plan.stops, plan.orderKnown, plan.coordinateYards, plan.mixed = ordered, true, total, true
    return plan
end

function Mixed.Skip(plan, id, accepted)
    if not plan or accepted and accepted[id] then return false end
    local root
    for index = plan.index or 1, #plan.stops do
        local stop = plan.stops[index]
        if stop.quest.id == id and stop.action == "accept" and not stop.done then root = stop break end
    end
    if not root then return false end
    local removed, changed = {[id] = true}, true
    while changed do
        changed = false
        for _, stop in ipairs(plan.stops) do for _, dependency in ipairs(stop.dependsOn or {}) do
            if removed[dependency] and not removed[stop.quest.id] and not (accepted and accepted[stop.quest.id]) then removed[stop.quest.id], changed = true, true end
        end end
    end
    local stops, before = {}, 0
    for index, stop in ipairs(plan.stops) do
        if removed[stop.quest.id] and not stop.done then if index < (plan.index or 1) then before = before + 1 end
        else stops[#stops + 1] = stop end
    end
    plan.stops, plan.index = stops, math.max(1, (plan.index or 1) - before)
    plan.excludedOffers = plan.excludedOffers or {}
    for questID in pairs(removed) do plan.excludedOffers[questID] = true end
    plan.xp, plan.unknownXP, plan.missing = 0, 0, 0
    local counted = {}
    for _, stop in ipairs(stops) do
        if not counted[stop.quest.id] then
            counted[stop.quest.id] = true local xp = plan.rewards and plan.rewards[stop.quest.id]
            if xp then plan.xp = plan.xp + xp else plan.unknownXP = plan.unknownXP + 1 end
            plan.missing = plan.missing + (plan.missingByQuest and plan.missingByQuest[stop.quest.id] or 0)
        end
    end
    plan.coordinateYards, plan.orderKnown = nil, nil
    plan.revision = (plan.revision or 0) + 1
    if plan.index > #stops then plan.running, plan.status = false, L.ExcursionFinished end
    return true, root.quest, removed
end

function Mixed.Refresh(plan, quests, measurements, finishers)
    local copy, present = addon.UndoHistory.Copy(plan), {}
    if not quests then copy.running, copy.unverified, copy.status = false, true, L.MixedNeedsCoordinates return copy end
    for _, quest in ipairs(quests or {}) do present[quest.id] = quest end
    copy.running, copy.needsReview, copy.unverified = false, false, false
    local accepted = {}
    for _, stop in ipairs(copy.stops) do if stop.action == "accept" and stop.done then accepted[stop.quest.id] = true end end
    for index = copy.index or 1, #copy.stops do
        local stop = copy.stops[index]
        local quest, m = present[stop.quest.id], measurements and measurements[stop.quest.id]
        if quest then
            stop.quest = quest
            if stop.action == "objective" and not quest.readyToTurnIn then
                local target = m and (m.objectiveMarker or m.marker)
                if addon.TravelSupport.ValidPoint(target) then stop.target, stop.yards = target, m.yards else copy.unverified = true end
            elseif stop.action == "turnIn" then
                local target = quest.readyToTurnIn and m and m.marker or finishers and finishers[quest.id]
                if addon.TravelSupport.ValidPoint(target) then stop.target = target end
            end
        elseif stop.seen or accepted[stop.quest.id] then copy.unverified = true
        end
    end
    if copy.unverified then copy.status = L.MixedNeedsCoordinates else copy.status = L.MixedReviewHelp end
    return copy
end
