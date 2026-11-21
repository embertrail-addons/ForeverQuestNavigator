local _, addon = ...
local Insights = {}
addon.PlanningInsights = Insights

function Insights.Bundles(mapAPI, quests, measurements, playerLevel, feedback)
    local entries = {}
    for _, quest in ipairs(quests or {}) do
        local measured = measurements[quest.id]
        if measured and not measured.objectiveMarker and not quest.readyToTurnIn and not (feedback and feedback[quest.id])
            and not addon.QuestPrioritizer.IsLowPriority(quest, playerLevel) then
            entries[#entries + 1] = { quest = quest, target = measured.marker, yards = measured.yards }
        end
    end
    table.sort(entries, function(a, b) if a.yards ~= b.yards then return a.yards < b.yards end return a.quest.id < b.quest.id end)
    local result = {}
    for _, group in ipairs(addon.BuildTargetGroups(mapAPI, entries)) do
        if #group.entries >= 2 then result[#result + 1] = group end
    end
    return result
end

-- Greedy order plus bounded pair swaps; every compared order visits exactly
-- the same known finishers. Unknown/unreachable points never imply zero travel.
function Insights.TurnIns(mapAPI, quests, measurements, xpNeeded, feedback, getXP)
    local candidates, unknown = {}, 0
    for _, quest in ipairs(quests or {}) do
        if quest.readyToTurnIn and not (feedback and feedback[quest.id]) then
            local measured = measurements[quest.id]
            if measured and measured.marker then candidates[#candidates + 1] = {quest = quest, target = measured.marker, yards = measured.yards}
            else unknown = unknown + 1 end
        end
    end
    table.sort(candidates, function(a, b) if a.yards ~= b.yards then return a.yards < b.yards end return a.quest.id < b.quest.id end)
    local ordered, distance = {}, candidates[1] and addon.QuestLocation.GetDistanceMetric(mapAPI, candidates[1].target)
    if not distance then return { stops = {}, unknown = unknown + #candidates } end
    local remaining = {}
    for index = 1, math.min(8, #candidates) do remaining[index] = candidates[index] end
    local omitted = math.max(0, #candidates - #remaining)
    ordered[1] = table.remove(remaining, 1)
    while #remaining > 0 do
        local best, nearest
        for index, candidate in ipairs(remaining) do
            local leg = distance(ordered[#ordered].target, candidate.target)
            if leg and (not nearest or leg < nearest) then best, nearest = index, leg end
        end
        if not best then unknown = unknown + #remaining break end
        ordered[#ordered + 1] = table.remove(remaining, best)
    end
    local function Length(stops)
        local total = stops[1] and stops[1].yards or 0
        for index = 2, #stops do
            local leg = distance(stops[index - 1].target, stops[index].target)
            if not leg then return math.huge end
            total = total + leg
        end
        return total
    end
    local baseline = Length(ordered)
    for _ = 1, 3 do
        local improved = false
        for a = 1, #ordered - 1 do
            for b = a + 1, #ordered do
                local before = Length(ordered)
                ordered[a], ordered[b] = ordered[b], ordered[a]
                if Length(ordered) + 1 < before then improved = true else ordered[a], ordered[b] = ordered[b], ordered[a] end
            end
        end
        if not improved then break end
    end
    local xp, unknownXP, levelUpAt = 0, 0
    for index, stop in ipairs(ordered) do
        stop.action = "turnIn"
        stop.leg = index == 1 and stop.yards or distance(ordered[index - 1].target, stop.target)
        stop.xp = (getXP or addon.QuestLog.GetTurnInXP)(stop.quest)
        if stop.xp then xp = xp + stop.xp else unknownXP = unknownXP + 1 end
        if not levelUpAt and xpNeeded and xp >= xpNeeded then levelUpAt = index end
    end
    return { stops = ordered, total = Length(ordered), saving = baseline - Length(ordered),
        xp = xp, unknownXP = unknownXP, levelUpAt = levelUpAt, unknown = unknown, omitted = omitted }
end

function Insights.AnnotateOffers(mapAPI, offers, quests, measurements, active, capacity)
    local activeMeasurement = active and measurements[active.id]
    local activeTarget = activeMeasurement and (activeMeasurement.objectiveMarker or activeMeasurement.marker)
    for _, offer in ipairs(offers or {}) do
        offer.overlapCount, offer.onApproach, offer.recommended = 0, false, nil
        offer.capacityFull = capacity and capacity.full or false
        local objective, pickup = offer.objectiveMarker, offer.marker
        local metric = objective and addon.QuestLocation.GetDistanceMetric(mapAPI, objective)
        if metric then
            for _, quest in ipairs(quests or {}) do
                local measured = measurements[quest.id]
                local target = measured and (measured.objectiveMarker or measured.marker)
                local gap = target and metric(objective, target)
                if not quest.readyToTurnIn and measured and not measured.objectiveMarker and gap and gap <= 100 then
                    offer.overlapCount = offer.overlapCount + 1
                end
            end
            local pickupGap = pickup and activeTarget and metric(pickup, activeTarget)
            local goalGap = activeTarget and metric(objective, activeTarget)
            offer.onApproach = not (activeMeasurement and activeMeasurement.objectiveMarker)
                and pickupGap ~= nil and goalGap ~= nil and goalGap <= 500
                and offer.yards < activeMeasurement.yards and offer.yards + pickupGap - activeMeasurement.yards <= 100
        end
        offer.score = addon.Recommendation.ScoreOffer(offer)
    end
    table.sort(offers or {}, function(a, b)
        if a.lowPriority ~= b.lowPriority then return not a.lowPriority end
        if a.score ~= b.score then return a.score < b.score end
        return a.id < b.id
    end)
    for _, offer in ipairs(offers or {}) do
        if not offer.capacityFull and not offer.lowPriority and addon.QuestPrioritizer.GetLevel(offer) and offer.objectiveMarker and offer.journeyYards then
            offer.recommended = (offer.overlapCount >= 2 and offer.journeyYards <= 1000)
                or (offer.onApproach and offer.journeyYards <= 750)
                or (offer == offers[1] and offer.journeyYards <= 500)
        end
    end
end

function Insights.OfferReason(offer)
    if offer.overlapCount == 1 then return addon.L.OfferOverlapOne end
    if (offer.overlapCount or 0) > 1 then return addon.L.OfferOverlap:format(offer.overlapCount) end
    if offer.onApproach then return addon.L.OfferOnApproach end
end

function Insights.Compare(snapshot, selected, manual)
    if not snapshot or not selected then return addon.L.ComparisonUnavailable end
    if manual then return addon.L.ComparisonManual end
    local baseline = snapshot.ranked[1]
    local lines = { addon.L.ComparisonSelected:format(selected.title or addon.L.QuestNumber:format(selected.id)) }
    if baseline and baseline.id ~= selected.id then
        lines[#lines + 1] = addon.L.ComparisonAlternative:format(baseline.title or addon.L.QuestNumber:format(baseline.id))
    end
    if snapshot.decisionSaving and snapshot.decisionSaving > 0 and baseline and baseline.id ~= selected.id then
        lines[#lines + 1] = addon.L.ComparisonSaving:format(snapshot.decisionSaving)
    elseif snapshot.decision == "levelUp" then lines[#lines + 1] = addon.L.LevelUpOnTurnIn
    else lines[#lines + 1] = addon.L.ComparisonFactors end
    return table.concat(lines, "\n")
end
