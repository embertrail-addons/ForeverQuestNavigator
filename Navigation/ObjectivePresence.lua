local _, addon = ...
local Presence = {}
addon.ObjectivePresence = Presence
local function Public(value) return not (issecretvalue and issecretvalue(value)) end
local function Call(fn, ...)
    if type(fn) ~= "function" then return end
    local ok, value = pcall(fn, ...)
    if ok and Public(value) then return value end
end

function Presence.CreatureID(guid)
    if not Public(guid) or type(guid) ~= "string" then return end
    local kind = guid:match("^([^-]+)%-")
    if kind ~= "Creature" and kind ~= "Vehicle" then return end
    return tonumber(guid:match("^[^-]+%-[^-]+%-[^-]+%-[^-]+%-[^-]+%-(%d+)%-"))
end

function Presence.Engaged(units, markers, quests, questAPI, avoided, lock)
    local ids = {}
    for _, token in ipairs({"target", "pettarget"}) do
        if Call(units.canAttack, "player", token) == true and Call(units.dead, token) ~= true then
            local threat = Call(units.threat, "player", token)
            local own = type(threat) == "number" and threat > 0
                or Call(units.same, token .. "target", "player") == true or Call(units.same, token .. "target", "pet") == true
            if own then local id = Presence.CreatureID(Call(units.guid, token)) if id then ids[id] = true end end
        end
    end
    local result = {}
    for _, quest in ipairs(quests or {}) do
        if not (quest.readyToTurnIn or quest.failed or quest.disabled) then
            local goals = Call(questAPI and questAPI.GetQuestObjectives, quest.id)
            for _, point in ipairs(markers and markers[quest.id] or {}) do
                local index = point.objectiveIndex
                local lockedOut = lock and lock.questID == quest.id and lock.index ~= index
                if point.npcID and ids[point.npcID] and not lockedOut and not (avoided and avoided[quest.id] and avoided[quest.id][index])
                    and type(goals) == "table" and goals[index] and Public(goals[index].finished) and not goals[index].finished then
                    result[quest.id] = {questID = quest.id, objectiveIndex = index, npcID = point.npcID} break
                end
            end
        end
    end
    return result
end

-- Local spawn neighborhoods, not the bounding box of a whole zone. Short
-- segments connect only nearby points belonging to the same source/objective.
function Presence.Area(api, points, measurement, previous, avoided, lock, camp)
    if not measurement or not measurement.marker then return end
    local reference = measurement.marker
    local map = Call(api and api.GetBestMapForUnit, "player") or reference.mapID
    local pos = Call(api and api.GetPlayerMapPosition, map, "player")
    if type(pos) ~= "table" or not Public(pos.x) or not Public(pos.y) then return end
    local player = {mapID = map, x = pos.x, y = pos.y}
    if not addon.TravelSupport.ValidPoint(player) then return end
    local metric = addon.QuestLocation.GetDistanceMetric(api, player)
    if not metric then return end
    local candidates, best, bestDistance = {}, nil, nil
    local enter = 80
    for _, point in ipairs(points or {}) do
        local index = point.objectiveIndex
        local manualGap = camp and camp.manual and metric(camp, point)
        if point.targetKind == "area" and not point.notCombatSource and not point.personalCorrection and index and not (avoided and avoided[index])
            and (not lock or lock == index) and (not (camp and camp.manual) or manualGap and manualGap <= 100) then
            local yards = metric(player, point)
            if yards then
                local radius = previous and previous.objectiveIndex == index and 110 or enter
                if yards <= radius and (not bestDistance or yards < bestDistance) then best, bestDistance = point, yards end
                if yards <= 260 then candidates[#candidates + 1] = {point = point, yards = yards} end
            end
        end
    end
    -- Bound pair work even for large Questie spawn sets. Nearest 40 points
    -- suffice for the short local corridor; far camps cannot join across gaps.
    table.sort(candidates, function(a, b) return a.yards < b.yards end)
    for i = 1, math.min(40, #candidates) do
        local a = candidates[i]
        for j = i + 1, math.min(40, #candidates) do
            local b = candidates[j]
            if a.point.objectiveIndex == b.point.objectiveIndex and a.point.spawnKey and a.point.spawnKey == b.point.spawnKey
                and a.point.mapID == b.point.mapID then
                local length = metric(a.point, b.point)
                if length and length > 0 and length <= 240 then
                    local t = (a.yards ^ 2 - b.yards ^ 2 + length ^ 2) / (2 * length ^ 2)
                    if t >= 0 and t <= 1 then
                        local distance = math.sqrt(math.max(0, a.yards ^ 2 - (t * length) ^ 2))
                        local radius = previous and previous.objectiveIndex == a.point.objectiveIndex and 80 or 60
                        if distance <= radius and (not bestDistance or distance < bestDistance) then best, bestDistance = a.point, distance end
                    end
                end
            end
        end
    end
    if best then return {objectiveIndex = best.objectiveIndex, marker = best, yardsToArea = bestDistance, kind = "area"} end
end
