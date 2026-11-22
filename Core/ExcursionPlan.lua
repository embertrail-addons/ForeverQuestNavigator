local _, addon = ...
local Excursion = {}
addon.ExcursionPlan = Excursion
local function Point(point)
    if not addon.TravelSupport.ValidPoint(point) then return end
    return {mapID = point.mapID, x = point.x, y = point.y, objectiveIndex = point.objectiveIndex}
end
function Excursion.Build(area, capacity, finisher, reward, options)
    local plan = {stops = {}, index = 1, running = false, missing = 0, xp = 0, unknownXP = 0, rewards = {}, missingByQuest = {},
        excludedOffers = options and addon.UndoHistory.Copy(options.excluded or {}) or {}}
    if not area then return plan end
    local pickups, goals, returns = {}, {}, {}
    local budget = capacity and capacity.free and math.max(0, capacity.free - (capacity.reserve or 0)) or 3
    if options then
        options.capacity = capacity
        local gains = 0
        for _, entry in ipairs(area.entries or {}) do if entry.quest.readyToTurnIn then gains = gains + 1 end end
        if capacity and capacity.free then budget = math.max(0, capacity.free + gains - (capacity.reserve or 0)) end
    end
    for _, entry in ipairs(area.entries or {}) do
        local quest = entry.quest
        local excluded = entry.pickup and options and (options.hidden and options.hidden[quest.id] or plan.excludedOffers[quest.id])
        local needed = (entry.pickup and 1 or 0) + (quest.readyToTurnIn and 0 or 1) + 1
        local fits = not options or #pickups + #goals + #returns + needed <= 20
        if fits and not excluded and (not entry.pickup or (#pickups < math.min(3, budget) and not quest.informational)) then
            if entry.pickup then pickups[#pickups + 1] = {quest = quest, action = "accept", target = Point(quest.marker)} end
            if not quest.readyToTurnIn then goals[#goals + 1] = {quest = quest, action = "objective", target = Point(entry.target), seen = not entry.pickup, yards = entry.yards} end
            local target = finisher and finisher(quest, entry.target)
            if Point(target) then returns[#returns + 1] = {quest = quest, action = "turnIn", target = Point(target), yards = quest.readyToTurnIn and entry.yards or nil}
            else plan.missing = plan.missing + 1 plan.missingByQuest[quest.id] = 1 end
            local xp = reward and reward(quest, entry.pickup)
            plan.rewards[quest.id] = xp
            if xp then plan.xp = plan.xp + xp else plan.unknownXP = plan.unknownXP + 1 end
        end
    end
    table.sort(pickups, function(a, b) if a.quest.yards ~= b.quest.yards then return a.quest.yards < b.quest.yards end return a.quest.id < b.quest.id end)
    for _, list in ipairs({pickups, goals, returns}) do
        for _, stop in ipairs(list) do
            if stop.target and #plan.stops < 20 then plan.stops[#plan.stops + 1] = stop else plan.missing = plan.missing + 1 end
        end
    end
    if options then plan.mixed = true addon.MixedQuestPlan.Order(plan, options) end
    return plan
end
function Excursion.Start(plan, quests, available, completed, capacity)
    if not plan or #plan.stops == 0 or not quests then return false, addon.L.ExcursionUnavailable end
    if plan.unverified or plan.needsReview then return false, addon.L.MixedNeedsCoordinates end
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
    if plan.mixed and capacity and capacity.free then
        local free, reserved, accepted = capacity.free, capacity.reserve or 0, {}
        for id in pairs(present) do accepted[id] = true end
        for index = plan.started and plan.index or 1, #plan.stops do
            local stop = plan.stops[index]
            if stop.action == "accept" and not accepted[stop.quest.id] then
                if free <= reserved then return false, addon.L.QuestLogFull end
                free, accepted[stop.quest.id] = free - 1, true
            elseif stop.action == "turnIn" and accepted[stop.quest.id] then free, accepted[stop.quest.id] = free + 1, nil end
        end
    end
    if not plan.started then
        for _, stop in ipairs(plan.stops) do
            stop.history = completed and completed(stop.quest.id) == true
            stop.seen = present[stop.quest.id] ~= nil
            stop.done = false
        end
        plan.index = 1
    end
    plan.started, plan.running, plan.status = true, true, nil
    plan.reviewDismissed = nil
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
        plan.revision = (plan.revision or 0) + 1
        if plan.mixed and stop.action == "accept" and quest then
            plan.needsReview, plan.running, plan.status = true, false, addon.L.MixedAcceptedReview return
        end
    end
    plan.running, plan.status = false, addon.L.ExcursionFinished
end
function Excursion.HandedIn(plan, id, rewardXP)
    if not (plan and plan.started) then return end
    local included
    for _, stop in ipairs(plan.stops or {}) do
        if stop.quest.id == id and not stop.confirmed then stop.confirmed = true included = true end
    end
    if included then
        plan.receipts = plan.receipts or {}
        if not plan.receipts[id] then
            local known = type(rewardXP) == "number" and rewardXP >= 0 and rewardXP < math.huge
            plan.receipts[id] = {xp = known and rewardXP or nil}
        end
    end
end
function Excursion.Current(plan) return plan and plan.running and plan.stops[plan.index] end

function Excursion.Review(plan)
    if not (plan and plan.started) or plan.reviewDismissed then return end
    local result = {completed = 0, xp = 0, unknownXP = 0, remaining = 0, rows = {}, finished = plan.index > #plan.stops}
    for _, receipt in pairs(plan.receipts or {}) do
        result.completed = result.completed + 1
        if receipt.xp then result.xp = result.xp + receipt.xp else result.unknownXP = result.unknownXP + 1 end
    end
    local seen = {}
    for _, stop in ipairs(plan.stops) do
        if not stop.done and not seen[stop.quest.id] then result.remaining = result.remaining + 1 seen[stop.quest.id] = true end
        result.rows[#result.rows + 1] = {quest = stop.quest, action = stop.action, done = stop.done}
    end
    return result
end
