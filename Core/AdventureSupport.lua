local _, addon = ...
local Support = {}
addon.AdventureSupport = Support
local L = addon.L

function Support.Departure(plan, capacity)
    local rows = {}
    for _, offer in ipairs(plan and plan.pickups or {}) do
        local pickup = addon.TravelSupport.ValidPoint(offer.marker) and L.OfferPickup:format(offer.pickupZone or L.UnknownZone, offer.marker.x * 100, offer.marker.y * 100) or L.UnknownCoordinates
        rows[#rows + 1] = {quest = offer, target = offer.marker, action = "accept", offer = true,
            short = pickup,
            detail = pickup .. "\n" .. (offer.planReason or L.PickupBeforeDeparture) .. "\n"
                .. addon.QuestPreparation.Describe(offer.preparation, offer.group)
                .. "\n" .. (capacity and capacity.full and L.QuestLogFull or capacity and capacity.free and L.PickupCapacity:format(math.max(0, capacity.free - (capacity.reserve or 0))) or L.PickupCapacityUnknown)
                .. "\n" .. L.AdventureAcceptManual}
    end
    return rows
end

function Support.Alternatives(snapshot, blockedID)
    local rows = {}
    for _, quest in ipairs(snapshot.ranked or {}) do
        local m = snapshot.measurements and snapshot.measurements[quest.id]
        if quest.id ~= blockedID and m and m.marker and not (snapshot.feedback and snapshot.feedback[quest.id])
            and not addon.QuestPrioritizer.IsLowPriority(quest, snapshot.playerLevel) then
            rows[#rows + 1] = {quest = quest, target = m.marker, yards = m.yards,
                action = quest.readyToTurnIn and "turnIn" or "objective",
                detail = addon.Recommendation.Short(snapshot, quest)}
        end
        if #rows >= 5 then break end
    end
    return rows
end

-- No addon messages or names are sent or persisted. A failed/unsupported query
-- remains unknown, never evidence that someone lacks the quest.
function Support.Group(quests, units, api)
    local rows = {}
    for _, quest in ipairs(quests or {}) do
        local count, unknown = 0, 0
        for _, unit in ipairs(units or {}) do
            local ok, value = false, nil
            if api and api.IsUnitOnQuest then ok, value = pcall(api.IsUnitOnQuest, unit, quest.id) end
            if not ok or (issecretvalue and issecretvalue(value)) or type(value) ~= "boolean" then unknown = unknown + 1
            elseif value == true then count = count + 1 end
        end
        rows[#rows + 1] = {quest = quest, count = count, unknown = unknown}
    end
    table.sort(rows, function(a, b) if a.count ~= b.count then return a.count > b.count end return a.quest.id < b.quest.id end)
    return rows
end

function Support.Correct(store, quest, point, index)
    if not (quest and addon.TravelSupport.ValidPoint(point)) then return false end
    local key = quest.readyToTurnIn and 0 or index
    if type(key) ~= "number" or key < (quest.readyToTurnIn and 0 or 1) or key % 1 ~= 0 then return false end
    store[quest.id] = type(store[quest.id]) == "table" and store[quest.id] or {}
    store[quest.id][key] = {mapID = point.mapID, x = point.x, y = point.y,
        objectiveIndex = key > 0 and key or nil, outdoorTurnIn = key == 0 or nil,
        personalCorrection = true, targetKind = key == 0 and "giver" or "area"}
    return true
end

function Support.ApplyCorrections(markers, quests, store, objectives)
    for _, quest in ipairs(quests or {}) do
        local saved = store and store[quest.id]
        local list, replaced = {}, {}
        local goals
        if objectives then local ok, value = pcall(objectives, quest.id) if ok and type(value) == "table" then goals = value end end
        local keys = {}
        for key in pairs(type(saved) == "table" and saved or {}) do if type(key) == "number" then keys[#keys + 1] = key end end
        table.sort(keys)
        for _, key in ipairs(keys) do
            local point = saved[key]
            if type(key) == "number" and addon.TravelSupport.ValidPoint(point)
                and ((quest.readyToTurnIn and key == 0) or (not quest.readyToTurnIn and key > 0 and goals and goals[key] and not goals[key].finished)) then
                list[#list + 1] = point replaced[key] = true
            end
        end
        if #list > 0 then
            for _, point in ipairs(markers[quest.id] or {}) do
                if not replaced[quest.readyToTurnIn and 0 or point.objectiveIndex or -1] then list[#list + 1] = point end
            end
            markers[quest.id] = list
        end
    end
end

-- Heuristic, deliberately explicit: coordinate travel / walking speed plus
-- 4–12 minutes per unfinished quest, 2 per pickup, 1 per hand-in.
-- Never budgets a quest without a known hand-in or a measurable route.
function Support.Budget(plan, minutes, api)
    if not minutes or minutes == 0 then return plan end
    local candidates, order = {}, {}
    for _, stop in ipairs(plan.stops) do
        local id = stop.quest.id
        if not candidates[id] then candidates[id] = {stops = {}, quest = stop.quest} order[#order + 1] = id end
        local c = candidates[id] c.stops[#c.stops + 1] = stop
        c.accept = c.accept or stop.action == "accept"
        c.work = c.work or stop.action == "objective" and not stop.quest.readyToTurnIn
        c.handIn = c.handIn or stop.action == "turnIn"
    end
    local selected, upper, lower, omitted = {}, 0, 0, 0
    for _, id in ipairs(order) do
        local c, travel, previous, known = candidates[id], 0, nil, true
        for _, stop in ipairs(candidates[id].stops) do
            local metric = addon.QuestLocation.GetDistanceMetric(api, stop.target)
            local leg = previous and metric and metric(previous, stop.target) or not previous and c.quest.yards
            -- Active quests usually carry their distance in the plan, not quest.
            if not previous and not leg then leg = stop.yards end
            if type(leg) ~= "number" or leg < 0 then known = false else travel = travel + leg end
            previous = stop.target
        end
        local overhead = (c.accept and 2 or 0) + (c.handIn and 1 or 0)
        local cost = travel / 180 + (c.work and 12 or 0) + overhead
        if known and c.handIn and upper + cost <= minutes then
            selected[id] = true upper = upper + cost lower = lower + travel / 420 + (c.work and 4 or 0) + overhead
        else omitted = omitted + 1 end
    end
    local result = {stops = {}, index = 1, running = false, missing = 0, xp = 0, unknownXP = 0,
        budget = minutes, lowerMinutes = math.ceil(lower), upperMinutes = math.ceil(upper), omitted = omitted, rewards = plan.rewards,
        mixed = plan.mixed, excludedOffers = addon.UndoHistory.Copy(plan.excludedOffers or {}), missingByQuest = plan.missingByQuest}
    for _, stop in ipairs(plan.stops) do if selected[stop.quest.id] then result.stops[#result.stops + 1] = stop end end
    for id in pairs(selected) do
        local xp = plan.rewards and plan.rewards[id]
        if xp then result.xp = result.xp + xp else result.unknownXP = result.unknownXP + 1 end
    end
    return result
end

function Support.Changes(plan, snapshot, api)
    local result = {}
    if not (plan and plan.started and plan.index <= #plan.stops) then return result end
    local included, anchors = {}, {}
    for _, stop in ipairs(plan.stops) do
        included[stop.quest.id] = true
        if stop.action == "objective" and not stop.done then anchors[#anchors + 1] = stop.target end
    end
    for _, quest in ipairs(snapshot.ranked or {}) do
        local m = snapshot.measurements and snapshot.measurements[quest.id]
        if not included[quest.id] and not quest.readyToTurnIn and not quest.special and not addon.QuestPrioritizer.IsLowPriority(quest, snapshot.playerLevel)
            and not (snapshot.feedback and snapshot.feedback[quest.id]) and m and m.marker and not m.objectiveMarker then
            for _, point in ipairs(anchors) do
                local metric = addon.QuestLocation.GetDistanceMetric(api, point)
                local gap = metric and metric(point, m.marker)
                if gap and gap <= 400 then
                    result[#result + 1] = {quest = quest, target = m.marker, yards = m.yards, action = "objective", detail = L.AdventureChangeHelp} break
                end
            end
        end
    end
    return result
end
