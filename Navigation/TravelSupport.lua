local _, addon = ...
local Travel = {}
addon.TravelSupport = Travel

local function Number(value)
    return not (issecretvalue and issecretvalue(value)) and type(value) == "number"
        and value == value and math.abs(value) < math.huge
end

function Travel.ValidPoint(point)
    return type(point) == "table" and Number(point.mapID) and point.mapID > 0
        and Number(point.x) and Number(point.y) and point.x >= 0 and point.x <= 1
        and point.y >= 0 and point.y <= 1 and (point.x > 0 or point.y > 0)
end

local function Key(marker)
    return marker.objectiveIndex or 0
end

function Travel.SaveAccess(saved, questID, target, point, name)
    if not (Travel.ValidPoint(target) and Travel.ValidPoint(point)) then return false end
    saved[questID] = saved[questID] or {}
    saved[questID][Key(target)] = {
        target = { mapID = target.mapID, x = target.x, y = target.y },
        point = { mapID = point.mapID, x = point.x, y = point.y },
        name = name,
    }
    return true
end

function Travel.GetAccess(saved, questID, marker, mapAPI)
    if not Travel.ValidPoint(marker) then return end
    local entries = type(saved[questID]) == "table" and saved[questID]
    local entry = entries and entries[Key(marker)]
    if type(entry) ~= "table" or not (Travel.ValidPoint(entry.point) and Travel.ValidPoint(entry.target)) then return end
    local distance = addon.QuestLocation.GetDistanceMetric(mapAPI, marker)
    local drift = distance and distance(marker, entry.target)
    -- A saved access point must not be reused for a different distant spawn.
    if drift and drift <= 300 then return entry end
end

function Travel.ApplyAccess(mapAPI, quests, measurements, maps, saved, passed)
    for _, quest in ipairs(quests or {}) do
        local measured = measurements[quest.id]
        local target = measured and measured.marker
        local entry = target and not quest.readyToTurnIn and Travel.GetAccess(saved, quest.id, target, mapAPI)
        if entry then
            local key = quest.id .. ":" .. Key(target)
            local point = { mapID = entry.point.mapID, x = entry.point.x, y = entry.point.y,
                objectiveIndex = target.objectiveIndex, objective = true, accessPoint = true, accessName = entry.name }
            local points = addon.QuestLocation.MeasureQuests(mapAPI, { [quest.id] = { point } }, { quest.id }, maps)
            local access = points[quest.id]
            if access and access.yards <= 12 then passed[key] = true end
            measured.accessExit = point
            if access and not passed[key] then
                access.objectiveMarker, access.objectiveYards = target, measured.yards
                local distance = addon.QuestLocation.GetDistanceMetric(mapAPI, target)
                local leg = distance and distance(point, target)
                if leg then
                    access.accessLeg = leg
                    access.accessExit = point
                    access.travelYards = access.yards + leg
                    measurements[quest.id] = access
                end
            end
        end
    end
end

-- This is a straight-line estimate through known unfinished goals and the
-- finisher. It is deliberately not a terrain or combat-time estimate.
function Travel.BuildJourney(mapAPI, quest, measured, objectives, distances, finisher)
    if quest.readyToTurnIn or not (measured and Travel.ValidPoint(finisher)) then return end
    local first = measured.objectiveMarker or measured.marker
    if not Travel.ValidPoint(first) then return end
    local distance = addon.QuestLocation.GetDistanceMetric(mapAPI, first)
    if not distance then return end
    local open, pending = 0, {}
    for index, objective in ipairs(objectives or {}) do
        if not objective.finished and objective.text and objective.text ~= "" then
            open = open + 1
            local candidate = distances and distances[index]
            if candidate and Travel.ValidPoint(candidate.marker) then
                if index ~= first.objectiveIndex then pending[#pending + 1] = candidate.marker end
            elseif open > 1 or first.objectiveIndex then
                return
            end
        end
    end
    if open == 0 or open > 10 then return end
    -- An unindexed POI can represent one goal, never an entire multi-goal quest.
    if not first.objectiveIndex and open > 1 then return end
    if not first.objectiveIndex then pending = {} end
    local legTotal, previous, exitYards = 0, first, 0
    if Travel.ValidPoint(measured.accessExit) then
        exitYards = distance(first, measured.accessExit)
        if not exitYards then return end
        legTotal, previous = exitYards, measured.accessExit
    end
    while #pending > 0 do
        local best, nearest
        for index, marker in ipairs(pending) do
            local yards = distance(previous, marker)
            if not yards then return end
            if not nearest or yards < nearest then best, nearest = index, yards end
        end
        legTotal = legTotal + nearest
        previous = table.remove(pending, best)
    end
    local returnYards = distance(previous, finisher)
    if not returnYards then return end
    local approach = measured.travelYards or measured.yards
    return { totalYards = approach + legTotal + returnYards,
        extraYards = (measured.accessLeg or 0) + legTotal + returnYards,
        returnYards = returnYards + (open == 1 and exitYards or 0), finisher = finisher,
        exit = measured.accessExit, goals = open }
end

function Travel.PlanningPenalty(quest, journey, enabled)
    if quest.readyToTurnIn or not enabled then return 0 end
    -- A bounded travel preference keeps distance, difficulty and follow-up
    -- planning relevant; unknown return routes receive an uncertainty allowance.
    if not journey then return 200 end
    return math.min(1000, journey.extraYards * 0.35)
end
