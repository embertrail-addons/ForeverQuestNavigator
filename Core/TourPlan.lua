local _, addon = ...
local Tour = {}
addon.TourPlan = Tour
local function ID(id) return type(id) == "number" and id > 0 and id < 1000000000 and id == math.floor(id) end
local function CopyStop(stop) return {id = stop.id, stage = stop.stage} end
function Tour.New(saved)
    local plan = {stops = {}, revision = 0, running = false}
    local seen = {}
    for index, stop in ipairs(type(saved) == "table" and type(saved.stops) == "table" and saved.stops or {}) do
        if index > 20 then break end
        if type(stop) == "table" and ID(stop.id) and not seen[stop.id]
            and (stop.stage == "objective" or stop.stage == "turnIn") then
            plan.stops[#plan.stops + 1] = CopyStop(stop) seen[stop.id] = true
        end
    end
    local point = type(saved) == "table" and saved.returnPoint
    if type(point) == "table" then plan.returnPoint = addon.TemporaryDetour.New(point.mapID, point.x, point.y, point.name) end
    return plan
end
function Tour.Export(plan)
    local copy = Tour.New(plan)
    return {stops = copy.stops, returnPoint = copy.returnPoint}
end
function Tour.Add(plan, quest)
    if not (quest and ID(quest.id)) or quest.failed or quest.disabled or (quest.special and not quest.readyToTurnIn) or #plan.stops >= 20 then return false end
    for _, stop in ipairs(plan.stops) do if stop.id == quest.id then return false end end
    plan.stops[#plan.stops + 1] = {id = quest.id, stage = quest.readyToTurnIn and "turnIn" or "objective"}
    plan.revision = plan.revision + 1
    return true
end
function Tour.Move(plan, index, delta)
    local target = index + delta
    if not plan.stops[index] or target < 1 or target > #plan.stops then return false end
    plan.stops[index], plan.stops[target] = plan.stops[target], plan.stops[index]
    plan.revision = plan.revision + 1 return true
end
function Tour.Remove(plan, index)
    if not plan.stops[index] then return false end
    table.remove(plan.stops, index) plan.revision = plan.revision + 1 return true
end
function Tour.Sync(plan, quests, skipped)
    if not quests then return end -- Unavailable quest data never erases a saved plan.
    local present, changed = {}, false
    for _, quest in ipairs(quests) do present[quest.id] = quest end
    for index = #plan.stops, 1, -1 do
        local stop = plan.stops[index]
        local quest = present[stop.id]
        if not quest or quest.failed or quest.disabled or (quest.special and not quest.readyToTurnIn) or (skipped and skipped[stop.id])
            or (stop.stage == "objective" and quest.readyToTurnIn) then
            table.remove(plan.stops, index) changed = true
        end
    end
    if #plan.stops == 0 and not plan.returnPoint then plan.running = false end
    if changed then plan.revision = plan.revision + 1 end
end
function Tour.Current(plan)
    return plan.running and plan.stops[1] and plan.stops[1].id or nil
end
-- Greedy order is only a preview. Unknown positions stay at the end, in order.
function Tour.Preview(plan, measurements, distance)
    local remaining, ordered, previous = {}, {}, nil
    for _, stop in ipairs(plan.stops) do remaining[#remaining + 1] = CopyStop(stop) end
    while #remaining > 0 do
        local best, cost
        for index, stop in ipairs(remaining) do
            local measured = measurements and measurements[stop.id]
            local yards = measured and measured.marker and (previous and distance and distance(previous, measured.marker) or not previous and measured.yards)
            if yards and (not cost or yards < cost) then best, cost = index, yards end
        end
        if not best then for _, stop in ipairs(remaining) do ordered[#ordered + 1] = stop end break end
        local stop = table.remove(remaining, best)
        ordered[#ordered + 1] = stop previous = measurements[stop.id].marker
    end
    local function Cost(stops)
        local total, previousPoint = 0, nil
        for _, stop in ipairs(stops) do
            local measured = measurements and measurements[stop.id]
            if not (measured and measured.marker) then return end
            local leg = previousPoint and distance and distance(previousPoint, measured.marker) or not previousPoint and measured.yards
            if not leg then return end
            total, previousPoint = total + leg, measured.marker
        end
        if plan.returnPoint and previousPoint then
            local leg = distance and distance(previousPoint, plan.returnPoint)
            if not leg then return end
            total = total + leg
        end
        return total
    end
    -- Repeated local moves (section reversal and single-stop relocation) can shorten the
    -- tour and its return leg without claiming a terrain route or a global optimum.
    -- Unknown legs disable it.
    local improved = addon.RouteOrder.Improve(ordered, Cost)
    ordered = improved
    local before, after = Cost(plan.stops), Cost(ordered)
    local saved = before and after and before - after > 1 and math.floor(before - after + .5) or nil
    return {stops = ordered, revision = plan.revision, savedYards = saved}
end
function Tour.ApplyPreview(plan, preview)
    if not preview or preview.revision ~= plan.revision then return false end
    plan.stops = Tour.New(preview).stops plan.revision = plan.revision + 1 return true
end

-- Explicit priorities are remembered as IDs/policies, never live frames or locks.
function Tour.Priority(id, held)
    if not ID(id) then return end
    return {id = id, policy = held and (held.turnIn and "turnIn" or "complete") or "manual"}
end
function Tour.ValidPriority(priority, quests, skipped)
    if type(priority) ~= "table" or not ID(priority.id) then return end
    if priority.policy ~= "manual" and priority.policy ~= "complete" and priority.policy ~= "turnIn" then return end
    for _, quest in ipairs(quests or {}) do
        if quest.id == priority.id and not (quest.failed or quest.disabled or (quest.special and not quest.readyToTurnIn) or (skipped and skipped[quest.id]))
            and not (priority.policy == "complete" and quest.readyToTurnIn) then return priority end
    end
end
