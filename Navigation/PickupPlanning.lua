local _, addon = ...
local Planning = {}
addon.PickupPlanning = Planning

local function Gap(api, a, b)
    local metric = a and b and addon.QuestLocation.GetDistanceMetric(api, a)
    return metric and metric(a, b)
end

local function Eligible(quest, level, feedback)
    return not quest.readyToTurnIn and not quest.special and not quest.informational and not (feedback and feedback[quest.id])
        and addon.QuestPrioritizer.GetLevel(quest)
        and not addon.QuestPrioritizer.IsLowPriority(quest, level)
end

local function Avoided(api, target, feedback)
    for _, entry in pairs(feedback or {}) do
        local gap = entry.kind == "area" and entry.point and target and Gap(api, entry.point, target)
        if gap and gap <= 400 then return true end
    end
end

-- Advice only: these stops never accept, abandon or change the active quest.
-- Distances describe coordinate proximity, not a verified walkable path.
function Planning.Build(api, offers, quests, measurements, active, capacity, level, feedback, chains, mapType, getXP, finishers)
    getXP = getXP or addon.QuestLog.GetTurnInXP
    local result = {areas = {}, pickups = {}, outing = {}, unknown = 0, capacity = capacity}
    local measured = active and measurements[active.id]
    local anchor = measured and not measured.objectiveMarker and measured.marker
    local entries, activeEntries, offerAreas = {}, {}, {}
    for _, quest in ipairs(quests or {}) do
        local m = measurements[quest.id]
        if Eligible(quest, level, feedback) and m and m.marker and m.yards and not m.objectiveMarker then
            local _, zone = addon.QuestLocation.GetZone(api, mapType, m.marker.mapID)
            local entry = {quest = quest, target = m.marker, yards = m.yards, zone = zone or m.marker.zoneName}
            entries[#entries + 1], activeEntries[#activeEntries + 1] = entry, entry
        end
    end
    for _, offer in ipairs(offers or {}) do
        offer.beforeDeparture, offer.slotLimited = false, false
        offer.planClass, offer.planReason = "unknown", nil
        local target = offer.objectiveMarker
        if target and offer.marker and offer.journeyYards and Eligible(offer, level, feedback) and not Avoided(api, target, feedback) then
            local shared = 0
            for _, entry in ipairs(activeEntries) do
                local gap = Gap(api, target, entry.target)
                if gap and gap <= 400 then shared = shared + 1 end
            end
            local leg = Gap(api, offer.marker, anchor)
            local goalGap = Gap(api, target, anchor)
            local extra = leg and measured.yards and offer.yards and offer.yards + leg - measured.yards
            offer.planClass = shared > 0 and "combination" or "independent"
            offer.planReason = shared > 0 and addon.L.PickupSharedArea:format(shared) or nil
            if extra and goalGap and extra <= 100 and goalGap <= 400 then
                offer.planClass, offer.planReason = "route", addon.L.PickupOnRoute
            elseif extra and extra > 300 then
                offer.planClass, offer.planReason = "detour", addon.L.PickupDetourHelp
                offer.recommended = nil
            end
            entries[#entries + 1] = {quest = offer, target = target, yards = offer.journeyYards,
                zone = offer.objectiveZone, pickup = true}
        else
            offer.recommended = nil
            result.unknown = result.unknown + 1
            if offer.informational then offer.planClass = "repeatable"
            elseif Avoided(api, target, feedback) then offer.planClass = "avoided"
            elseif offer.special then offer.planClass = "special"
            elseif addon.QuestPrioritizer.IsLowPriority(offer, level) then offer.planClass = "difficulty" end
        end
    end
    table.sort(entries, function(a, b)
        if a.yards ~= b.yards then return a.yards < b.yards end
        return a.quest.id < b.quest.id
    end)
    -- Bounded anchor clusters: a chain of adjacent points cannot join distant camps.
    for _, entry in ipairs(entries) do
        local area
        for _, candidate in ipairs(result.areas) do
            local gap = Gap(api, entry.target, candidate.target)
            if gap and gap <= 400 then area = candidate break end
        end
        if not area then
            area = {target = entry.target, zone = entry.zone or addon.L.UnknownZone, entries = {},
                active = 0, pickups = 0, xp = 0, unknownXP = 0, yards = entry.yards}
            result.areas[#result.areas + 1] = area
        end
        area.entries[#area.entries + 1] = entry
        area[entry.pickup and "pickups" or "active"] = area[entry.pickup and "pickups" or "active"] + 1
        local xp
        if entry.pickup then xp = entry.quest.xp else xp = getXP(entry.quest) end
        if xp then area.xp = area.xp + xp else area.unknownXP = area.unknownXP + 1 end
        entry.area = area
        if entry.pickup then offerAreas[entry.quest.id] = area end
    end
    for _, area in ipairs(result.areas) do
        area.followUps = {}
        for _, chain in ipairs(chains or {}) do
            if chain.known then
                for _, stop in ipairs(chain.targets or {chain.stop}) do
                    local gap = Gap(api, area.target, stop.target)
                    if gap and gap <= 400 then area.followUps[#area.followUps + 1] = chain break end
                end
            end
        end
        area.score = area.yards / (1 + area.active * .4 + area.pickups * .3 + #area.followUps * .2)
            - math.min(75, area.xp / 100)
        for _, entry in ipairs(area.entries) do
            local offer = entry.quest
            if entry.pickup and offer.planClass == "independent" and #area.entries > 1 then
                offer.planClass, offer.planReason = "combination", addon.L.PickupCombinedArea
            end
        end
        area.handIns, area.missingReturns = 0, 0
        local counted = {}
        for _, entry in ipairs(area.entries) do
            if not counted[entry.quest.id] then
                counted[entry.quest.id] = true
                if finishers and addon.TravelSupport.ValidPoint(finishers[entry.quest.id]) then
                    area.handIns = area.handIns + 1
                else area.missingReturns = area.missingReturns + 1 end
            end
        end
    end
    table.sort(result.areas, function(a, b)
        if a.score ~= b.score then return a.score < b.score end
        return a.entries[1].quest.id < b.entries[1].quest.id
    end)
    -- Existing route/level/XP ranking is retained. Highlight only what fits now;
    -- reserve a sequential follow-up slot and never assume a missing capacity.
    local budget = capacity and capacity.free and math.max(0, capacity.free - (capacity.reserve or 0))
    if capacity and capacity.full then budget = 0 end
    result.budget = budget
    local candidates = {}
    for _, offer in ipairs(offers or {}) do
        if offer.yards and offer.yards <= 750 and (offer.planClass == "route" or offer.planClass == "combination") then
            candidates[#candidates + 1] = offer
        end
    end
    table.sort(candidates, function(a, b)
        if (a.planClass == "route") ~= (b.planClass == "route") then return a.planClass == "route" end
        if offerAreas[a.id].score ~= offerAreas[b.id].score then return offerAreas[a.id].score < offerAreas[b.id].score end
        if a.score ~= b.score then return a.score < b.score end
        return a.id < b.id
    end)
    local destination = candidates[1] and offerAreas[candidates[1].id] or result.areas[1]
    for _, offer in ipairs(candidates) do
        if offerAreas[offer.id] == destination and #result.pickups < math.min(3, budget or 3) then
            offer.beforeDeparture, offer.recommended = true, true
            result.pickups[#result.pickups + 1] = offer
        else offer.slotLimited = budget ~= nil and #result.pickups >= budget end
    end
    local remaining = math.max(0, (budget or 3) - #result.pickups)
    for _, offer in ipairs(offers or {}) do
        if not offer.beforeDeparture and offer.recommended then
            if remaining > 0 then remaining = remaining - 1 else offer.recommended, offer.slotLimited = false, true end
        end
    end
    result.destination = destination
    -- The advisory round only includes pickups belonging to its chosen camp.
    local selected = {}
    for _, offer in ipairs(result.pickups) do
        if destination then for _, entry in ipairs(destination.entries) do
            if entry.quest == offer then selected[#selected + 1] = offer break end
        end end
    end
    table.sort(selected, function(a, b) if a.yards ~= b.yards then return a.yards < b.yards end return a.id < b.id end)
    if budget == 0 then
        for _, quest in ipairs(quests or {}) do
            local m = measurements[quest.id]
            if quest.readyToTurnIn and m and m.marker and m.yards <= 500 and not (feedback and feedback[quest.id])
                and (not result.turnIn or m.yards < result.turnIn.leg) then
                result.turnIn = {quest = quest, target = m.marker, action = "turnIn", leg = m.yards}
            end
        end
        if result.turnIn then result.outing[#result.outing + 1] = result.turnIn end
    end
    for _, offer in ipairs(selected) do
        result.outing[#result.outing + 1] = {quest = offer, target = offer.marker, action = "accept", offer = true}
    end
    if destination then
        for _, entry in ipairs(destination.entries) do
            if not entry.pickup then
                result.outing[#result.outing + 1] = {quest = entry.quest, target = entry.target, action = "objective"}
            end
        end
        for _, offer in ipairs(selected) do
            result.outing[#result.outing + 1] = {quest = offer, target = offer.objectiveMarker, action = "objective", offer = true}
        end
    end
    result.followUps = {}
    for _, chain in ipairs(chains or {}) do
        for _, stop in ipairs(result.outing) do
            if chain.quest and chain.quest.id == stop.quest.id then result.followUps[#result.followUps + 1] = chain break end
        end
    end
    result.roundXP, result.roundUnknownXP = 0, 0
    local counted = {}
    for _, stop in ipairs(result.outing) do
        if stop.action ~= "accept" and not counted[stop.quest.id] then
            counted[stop.quest.id] = true
            local xp
            if stop.offer then xp = stop.quest.xp else xp = getXP(stop.quest) end
            if xp then result.roundXP = result.roundXP + xp else result.roundUnknownXP = result.roundUnknownXP + 1 end
        end
    end
    return result
end

function Planning.AreaSummary(area)
    local xp = (area.unknownXP or 0) > 0 and (area.xp or 0) == 0 and addon.L.UnknownXP
        or addon.L.QuestXPReward:format(area.xp or 0) .. ((area.unknownXP or 0) > 0 and " + ?" or "")
    return addon.L.TourCard:format(area.active or 0, area.pickups or 0, area.handIns or 0, xp)
end

function Planning.ClassLabel(offer)
    return addon.L["PickupClass_" .. (offer.planClass or "unknown")]
end
