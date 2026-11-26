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

function Travel.AccessSteps(entry)
    if type(entry) ~= "table" then return end
    local points = entry.points or {entry.point}
    if type(points) ~= "table" or #points < 1 or #points > 8 then return end
    for index = 1, #points do if not Travel.ValidPoint(points[index]) then return end end
    return points
end

local function Touch(entry, points)
    entry.points, entry.point = points, points[1]
    entry.revision = (Number(entry.revision) and entry.revision or 0) + 1
end

function Travel.SaveAccess(saved, questID, target, point, name)
    if not (Travel.ValidPoint(target) and Travel.ValidPoint(point)) then return false end
    saved[questID] = type(saved[questID]) == "table" and saved[questID] or {}
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
    if type(entry) ~= "table" or not (Travel.AccessSteps(entry) and Travel.ValidPoint(entry.target)) then return end
    local distance = addon.QuestLocation.GetDistanceMetric(mapAPI, marker)
    local drift = distance and distance(marker, entry.target)
    -- A saved access point must not be reused for a different distant spawn.
    if drift and drift <= 300 then return entry end
end

function Travel.AppendAccess(saved, questID, target, point, mapAPI)
    if not Travel.ValidPoint(point) then return false end
    local entry = Travel.GetAccess(saved, questID, target, mapAPI)
    local points = entry and Travel.AccessSteps(entry)
    if not points or #points >= 8 then return false end
    local metric = addon.QuestLocation.GetDistanceMetric(mapAPI, target)
    local gap = metric and metric(points[#points], point)
    if not gap or gap < 5 or not metric(point, target) then return false end
    local copy = {}
    for _, existing in ipairs(points) do copy[#copy + 1] = existing end
    copy[#copy + 1] = {mapID = point.mapID, x = point.x, y = point.y}
    Touch(entry, copy)
    return true
end

function Travel.MoveAccessStep(saved, questID, index, step, delta)
    local entry = type(saved[questID]) == "table" and saved[questID][index]
    local points = Travel.AccessSteps(entry)
    if not points or (delta ~= -1 and delta ~= 1) or not points[step] or not points[step + delta] then return false end
    points[step], points[step + delta] = points[step + delta], points[step]
    Touch(entry, points)
    return true
end

function Travel.SetAccessNote(saved, questID, index, step, note)
    local entry = type(saved[questID]) == "table" and saved[questID][index]
    local points = Travel.AccessSteps(entry)
    if not points or not points[step] or type(note) ~= "string" then return false end
    note = note:gsub("[%c|]", ""):match("^%s*(.-)%s*$")
    if #note > 240 then return false end
    points[step].note = note ~= "" and note or nil
    -- Notes do not reset the visited-step progress.
    return true
end

function Travel.RemoveAccessStep(saved, questID, index, step)
    local entry = type(saved[questID]) == "table" and saved[questID][index]
    local points = Travel.AccessSteps(entry)
    if not points or not points[step] then return false end
    table.remove(points, step)
    if #points == 0 then Travel.RemoveAccess(saved, questID, index) else Touch(entry, points) end
    return true
end

function Travel.ApplyAccess(mapAPI, quests, measurements, maps, saved, passed, pauseProgress)
    for _, quest in ipairs(quests or {}) do
        local measured = measurements[quest.id]
        local target = measured and measured.marker
        local entry = target and not quest.readyToTurnIn and Travel.GetAccess(saved, quest.id, target, mapAPI)
        if entry then
            local key = quest.id .. ":" .. Key(target)
            local steps = Travel.AccessSteps(entry)
            local progress = passed[key]
            if type(progress) ~= "table" or progress.entry ~= entry or progress.revision ~= entry.revision then
                progress = {entry = entry, revision = entry.revision, index = (#steps == 1 and progress == true) and 2 or 1}
            end
            local function Marker(index)
                local value = steps[index]
                return {mapID = value.mapID, x = value.x, y = value.y, objectiveIndex = target.objectiveIndex,
                    objective = true, accessPoint = true, accessStep = index, accessTotal = #steps,
                    accessNote = value.note,
                    accessName = (entry.name or addon.L.SavedAccess) .. (#steps > 1 and (" (" .. index .. "/" .. #steps .. ")") or "")}
            end
            local point, access
            while progress.index <= #steps do
                point = Marker(progress.index)
                access = addon.QuestLocation.MeasureQuests(mapAPI, {[quest.id] = {point}}, {quest.id}, maps)[quest.id]
                if not access or access.yards > 12 or pauseProgress then break end
                progress.index = progress.index + 1
                access = nil
            end
            passed[key] = #steps == 1 and progress.index > 1 and true or progress
            local exitSteps = {}
            for index = #steps, 1, -1 do exitSteps[#exitSteps + 1] = Marker(index) end
            measured.accessExit, measured.accessExitSteps = exitSteps[1], exitSteps
            if access and progress.index <= #steps then
                access.objectiveMarker, access.objectiveYards = target, measured.yards
                local distance = addon.QuestLocation.GetDistanceMetric(mapAPI, target)
                local remaining = {}
                for index = progress.index, #steps do remaining[#remaining + 1] = Marker(index) end
                local leg, previous = 0, point
                for index = 2, #remaining do
                    local gap = distance and distance(previous, remaining[index])
                    if not gap then leg = nil break end
                    leg, previous = leg + gap, remaining[index]
                end
                local final = leg and distance and distance(previous, target)
                leg = final and (leg + final) or nil
                if leg then
                    access.accessLeg = leg
                    access.accessExit, access.accessExitSteps, access.accessSteps = exitSteps[1], exitSteps, remaining
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
        for _, exit in ipairs(measured.accessExitSteps or {measured.accessExit}) do
            local leg = distance(previous, exit)
            if not leg then return end
            exitYards, previous = exitYards + leg, exit
        end
        legTotal = exitYards
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
        exit = measured.accessExit, exitSteps = measured.accessExitSteps, goals = open }
end

function Travel.PlanningPenalty(quest, journey, enabled, countedAccess)
    if quest.readyToTurnIn or not enabled then return 0 end
    -- A bounded travel preference keeps distance, difficulty and follow-up
    -- planning relevant; unknown return routes receive an uncertainty allowance.
    if not journey then return 200 end
    -- A nearly finished quest has to be handed in anyway: its return trip does not count
    -- against it (otherwise a far turn-in pushes "one more kill here" behind other quests).
    local extra = journey.extraYards
    if quest.progress and quest.progress.nearly then extra = extra - (journey.returnYards or 0) end
    return math.min(1000, math.max(0, extra - math.max(0, countedAccess or 0)) * 0.35)
end

function Travel.ListAccess(saved, mapAPI, titleForQuest)
    local entries = {}
    for id, objectives in pairs(saved) do
        if type(id) == "number" and id > 0 and type(objectives) == "table" then
            for index, entry in pairs(objectives) do
                if type(index) == "number" and index >= 0 and type(entry) == "table" and Travel.ValidPoint(entry.point) then
                    local map = mapAPI.GetMapInfo and mapAPI.GetMapInfo(entry.point.mapID)
                    entries[#entries + 1] = { questID = id, index = index, name = entry.name, point = entry.point,
                        stepCount = #(Travel.AccessSteps(entry) or {}),
                        title = titleForQuest(id, entry.questTitle) .. (index > 0 and addon.L.AccessObjective:format(index) or ""),
                        zone = map and map.name or addon.L.UnknownZone }
                end
            end
        end
    end
    table.sort(entries, function(a, b)
        if a.questID ~= b.questID then return a.questID < b.questID end
        return a.index < b.index
    end)
    return entries
end

function Travel.RenameAccess(saved, id, index, name)
    local entry = type(saved[id]) == "table" and saved[id][index]
    if type(entry) ~= "table" or type(name) ~= "string" then return false end
    name = name:gsub("[%c]", ""):match("^%s*(.-)%s*$")
    if #name > 240 then return false end
    entry.name = name ~= "" and name or addon.L.SavedAccess
    return true
end

function Travel.RemoveAccess(saved, id, index)
    if type(saved[id]) ~= "table" then return end
    saved[id][index] = nil
    if not next(saved[id]) then saved[id] = nil end
end
