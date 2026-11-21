local _, addon = ...
local Excursion = {}
addon.ExcursionPlan = Excursion
local function Point(point)
    if not addon.TravelSupport.ValidPoint(point) then return end
    return {mapID = point.mapID, x = point.x, y = point.y, objectiveIndex = point.objectiveIndex}
end
function Excursion.Build(area, capacity, finisher, reward)
    local plan = {stops = {}, index = 1, running = false, missing = 0, xp = 0, unknownXP = 0}
    if not area then return plan end
    local pickups, goals, returns = {}, {}, {}
    local budget = capacity and capacity.free and math.max(0, capacity.free - (capacity.reserve or 0)) or 3
    for _, entry in ipairs(area.entries or {}) do
        local quest = entry.quest
        if not entry.pickup or (#pickups < math.min(3, budget) and not quest.informational) then
            if entry.pickup then pickups[#pickups + 1] = {quest = quest, action = "accept", target = Point(quest.marker)} end
            goals[#goals + 1] = {quest = quest, action = "objective", target = Point(entry.target), seen = not entry.pickup}
            local target = finisher and finisher(quest, entry.target)
            if Point(target) then returns[#returns + 1] = {quest = quest, action = "turnIn", target = Point(target)} else plan.missing = plan.missing + 1 end
            local xp = reward and reward(quest, entry.pickup)
            if xp then plan.xp = plan.xp + xp else plan.unknownXP = plan.unknownXP + 1 end
        end
    end
    table.sort(pickups, function(a, b) if a.quest.yards ~= b.quest.yards then return a.quest.yards < b.quest.yards end return a.quest.id < b.quest.id end)
    for _, list in ipairs({pickups, goals, returns}) do
        for _, stop in ipairs(list) do
            if stop.target and #plan.stops < 20 then plan.stops[#plan.stops + 1] = stop else plan.missing = plan.missing + 1 end
        end
    end
    return plan
end
function Excursion.Start(plan, quests, available, completed, capacity)
    if not plan or #plan.stops == 0 or not quests then return false, addon.L.ExcursionUnavailable end
    local present, offered = {}, {}
    for _, quest in ipairs(quests) do present[quest.id] = quest end
    for _, quest in ipairs(available or {}) do offered[quest.id] = true end
    if plan.index > #plan.stops then return false, addon.L.ExcursionFinished end
    for index = plan.started and plan.index or 1, #plan.stops do
        local stop = plan.stops[index]
        if not Point(stop.target) or not (present[stop.quest.id] or offered[stop.quest.id]) then return false, addon.L.ExcursionStale end
    end
    local first = plan.stops[plan.started and plan.index or 1]
    if capacity and capacity.full and first.action == "accept" and not present[first.quest.id] then return false, addon.L.QuestLogFull end
    if not plan.started then
        for _, stop in ipairs(plan.stops) do
            stop.history = completed and completed(stop.quest.id) == true
            stop.seen = present[stop.quest.id] ~= nil
            stop.done = false
        end
        plan.index = 1
    end
    plan.started, plan.running, plan.status = true, true, nil
    return true
end
function Excursion.Sync(plan, quests, objectives, completed, skipped)
    if not (plan and plan.running and quests) then return end
    local present = {}
    for _, quest in ipairs(quests) do present[quest.id] = quest end
    while plan.stops[plan.index] do
        local stop = plan.stops[plan.index]
        local quest = present[stop.quest.id]
        if (skipped and skipped[stop.quest.id]) or quest and (quest.failed or quest.disabled) then
            plan.running, plan.status = false, addon.L.ExcursionQuestMissing return
        end
        local handedIn = stop.confirmed or not stop.history and completed and completed(stop.quest.id) == true
        if quest then stop.seen = true end
        local done = false
        if stop.action == "accept" then done = quest ~= nil or handedIn
        elseif stop.action == "turnIn" then done = handedIn
        elseif stop.action == "objective" then
            done = handedIn or quest and quest.readyToTurnIn
        end
        if not done then
            if stop.action ~= "accept" and not quest then plan.running, plan.status = false, addon.L.ExcursionQuestMissing end
            return stop
        end
        stop.done, plan.index = true, plan.index + 1
    end
    plan.running, plan.status = false, addon.L.ExcursionFinished
end
function Excursion.HandedIn(plan, id)
    for _, stop in ipairs(plan and plan.stops or {}) do if stop.quest.id == id then stop.confirmed = true end end
end
function Excursion.Current(plan) return plan and plan.running and plan.stops[plan.index] end
