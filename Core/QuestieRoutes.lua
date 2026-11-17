local _, addon = ...
local L = addon.L
local QuestieRoutes = {}
addon.QuestieRoutes = QuestieRoutes

local function HasEntries(value)
    return type(value) == "table" and next(value) ~= nil
end

local function SingleNpc(givers)
    local npcs = givers and givers[1]
    if npcs and #npcs == 1 and not (HasEntries(givers[2]) or HasEntries(givers[3])) then return npcs[1] end
end

local additionalRequirements = {
    "requiredSkill", "requiredMinRep", "requiredMaxRep", "requiredSourceItems", "requiredSpell",
    "requiredSpecialization", "requiredRanks", "parentQuest", "exclusiveTo",
    "availableUntilCompleted", "availableStartingWith", "disabledByQuest",
}

local function Restricted(mask, playerID)
    return mask and mask ~= 0 and mask ~= -1 and mask ~= 4294967295
        and (not playerID or playerID > 32 or bit.band(mask, 2 ^ (playerID - 1)) == 0)
end

-- Check the requirements that can be simulated without modifying Questie's
-- persistent or active quest state. A later quest remains a forecast.
local function IsNextQuest(db, api, id, previous, planned, player, skipped)
    if not id or id <= 0 or planned[id] or skipped[id] or api.IsOnQuest(id) or api.IsQuestFlaggedCompleted(id)
        or addon.QuestLog.IsSpecialQuest(api, id)
        or (api.IsQuestDisabledForSession and api.IsQuestDisabledForSession(id)) then return false end
    local requiredLevel = db.requiredLevel(id)
    local maximumLevel = db.requiredMaxLevel(id)
    if not requiredLevel or requiredLevel > player.level
        or (maximumLevel and maximumLevel > 0 and player.level > maximumLevel)
        or addon.QuestPrioritizer.IsLowPriority({ level = db.questLevel(id) }, player.level)
        or bit.band(db.specialFlags(id) or 0, 2) ~= 0
        or Restricted(db.requiredRaces(id), player.race) or Restricted(db.requiredClasses(id), player.class) then
        return false
    end
    for _, field in ipairs(additionalRequirements) do
        local value = db.Get(id, field)
        if HasEntries(value) or (type(value) == "number" and value ~= 0) then return false end
    end

    local prerequisites = db.preQuestSingle(id)
    if HasEntries(prerequisites) then
        local follows
        for _, prerequisite in ipairs(prerequisites) do
            if prerequisite == previous then follows = true end
            if prerequisite <= 0 or (prerequisite ~= previous
                and (planned[prerequisite] or api.IsQuestFlaggedCompleted(prerequisite))) then return false end
        end
        return follows
    end

    local follows
    for _, prerequisite in ipairs(db.preQuestGroup(id) or {}) do
        if prerequisite <= 0 or not (planned[prerequisite] or api.IsQuestFlaggedCompleted(prerequisite)) then
            return false
        end
        if prerequisite == previous then follows = true end
    end
    return follows
end

local function NextQuest(db, api, previous, planned, player, skipped)
    local ids = {}
    for _, id in ipairs(db.childQuests(previous) or {}) do ids[id] = true end
    local nextID = db.nextQuestInChain(previous)
    if nextID and nextID > 0 then ids[nextID] = true end
    local result
    for id in pairs(ids) do
        if IsNextQuest(db, api, id, previous, planned, player, skipped) then
            if result then return end
            result = id
        end
    end
    return result
end

local function SpawnPoint(spawns, maps, zones, phasing, distance)
    local result, best
    for areaID, points in pairs(spawns or {}) do
        local mapID = zones:GetUiMapIdByAreaId(areaID)
        if maps[mapID] then
            for _, point in ipairs(points) do
                local x, y = point[1] / 100, point[2] / 100
                if x >= 0 and x <= 1 and y >= 0 and y <= 1 and (x > 0 or y > 0)
                    and phasing.IsSpawnVisible(point[3]) then
                    local position = { mapID = mapID, x = x, y = y }
                    if distance then
                        local cost = distance(position)
                        if cost and (not best or cost < best) then
                            result, best = position, cost
                        end
                    elseif result and (result.mapID ~= mapID or result.x ~= x or result.y ~= y) then
                        return nil
                    else
                        result = position
                    end
                end
            end
        end
    end
    return result
end

local function FollowUpStops(db, npc, id, maps, zones, phasing, distance)
    local starter, finisher = SingleNpc(db.startedBy(id)), SingleNpc(db.finishedBy(id))
    local objectives = db.objectives(id)
    if not (starter and finisher and objectives) or db.triggerEnd(id) or HasEntries(db.extraObjectives(id)) then return end
    for index = 2, 6 do
        if HasEntries(objectives[index]) then return end
    end
    local start = SpawnPoint(npc.spawns(starter), maps, zones, phasing)
    local finish = SpawnPoint(npc.spawns(finisher), maps, zones, phasing)
    if not (start and finish and distance(start, finish)) then return end
    local creatures = objectives[1]
    start.action, finish.action = "accept", "turnIn"
    local function WithQuest(stops)
        for _, stop in ipairs(stops) do
            stop.questID, stop.title = id, db.name(id)
        end
        return stops
    end
    if not HasEntries(creatures) then return WithQuest({ start, finish }) end
    local target = creatures[1]
    if #creatures ~= 1 or not target[1] or (target[3] and target[3] ~= 0 and target[3] ~= Questie.ICON_TYPE_SLAY) then
        return
    end
    local kill = SpawnPoint(npc.spawns(target[1]), maps, zones, phasing, function(marker)
        local first, last = distance(start, marker), distance(marker, finish)
        if first and last then return first + last end
    end)
    if kill then
        kill.action = "objective"
        return WithQuest({ start, kill, finish })
    end
end

local function FindTurnIn(mapAPI, mapType, maps, id, origin)
    local db = LibQuestieDB
    local givers = db.Quest.finishedBy(id)
    if not givers then return end
    local zones = QuestieLoader:ImportModule("ZoneDB")
    local phasing = QuestieLoader:ImportModule("Phasing")
    local known, bestPoint, bestName, bestYards
    local metric = origin and addon.QuestLocation.GetDistanceMetric(mapAPI, origin)
    local cost = metric and function(point) return metric(origin, point) end
    for kind, entity in ipairs({ db.Npc, db.Object }) do
        for _, giver in ipairs(givers[kind] or {}) do
            local spawns = entity.spawns(giver)
            if HasEntries(spawns) then
                known = true
                local point = SpawnPoint(spawns, maps, zones, phasing, cost)
                if point and addon.QuestLocation.IsOutdoorMap(mapAPI, mapType, point.mapID, maps) then
                    local named, name
                    if type(entity.name) == "function" then named, name = pcall(entity.name, giver) end
                    local giverName = named and type(name) == "string" and name or nil
                    if not origin then return point, true, giverName end
                    local yards = cost and cost(point)
                    if yards and (not bestYards or yards < bestYards) then
                        bestPoint, bestName, bestYards = point, giverName, yards
                    end
                end
            end
        end
    end
    return bestPoint, known, bestName
end

function QuestieRoutes.GetOutdoorTurnInMarker(mapAPI, mapType, maps, id, origin)
    if not LibQuestieDB then return end
    local ok, marker, known, name = pcall(FindTurnIn, mapAPI, mapType, maps, id, origin)
    if ok then return marker, known, name end
end

local function CollectAccessHints(mapAPI, mapType, maps, id, target)
    local db = LibQuestieDB
    if not (db and db.Quest.extraObjectives and target) then return {} end
    local zones = QuestieLoader:ImportModule("ZoneDB")
    local phasing = QuestieLoader:ImportModule("Phasing")
    local metric = addon.QuestLocation.GetDistanceMetric(mapAPI, target)
    local hints = {}
    local function AddSpawns(spawns, text)
        for area, points in pairs(spawns or {}) do
            local mapID = zones:GetUiMapIdByAreaId(area)
            if maps[mapID] and addon.QuestLocation.IsOutdoorMap(mapAPI, mapType, mapID, maps) then
                for _, point in ipairs(points) do
                    local marker = { mapID = mapID, x = point[1] / 100, y = point[2] / 100 }
                    if addon.TravelSupport.ValidPoint(marker) and phasing.IsSpawnVisible(point[3]) then
                        local yards = metric and metric(target, marker)
                        if yards then hints[#hints + 1] = { point = marker, text = text, yards = yards } end
                    end
                end
            end
        end
    end
    for _, extra in ipairs(db.Quest.extraObjectives(id) or {}) do
        local index, text = extra[4], extra[3]
        if type(text) == "string" and text ~= "" and (not index or index == 0 or index == target.objectiveIndex) then
            AddSpawns(extra[1], text)
            for _, reference in ipairs(extra[5] or {}) do
                local entity = reference[1] == "monster" and db.Npc or reference[1] == "object" and db.Object
                if entity and entity.spawns then AddSpawns(entity.spawns(reference[2]), text) end
            end
        end
    end
    table.sort(hints, function(a, b)
        if a.yards ~= b.yards then return a.yards < b.yards end
        if a.point.mapID ~= b.point.mapID then return a.point.mapID < b.point.mapID end
        if a.point.x ~= b.point.x then return a.point.x < b.point.x end
        return a.point.y < b.point.y
    end)
    while #hints > 5 do table.remove(hints) end
    return hints
end

function QuestieRoutes.GetAccessHints(...)
    local ok, hints = pcall(CollectAccessHints, ...)
    return ok and hints or {}
end

local function FindObjectiveMap(mapAPI, mapType, id, starter, maps)
    local db = LibQuestieDB
    local zones = QuestieLoader:ImportModule("ZoneDB")
    local phasing = QuestieLoader:ImportModule("Phasing")
    local found, ambiguous, triggerPoint, multipleTriggerPoints
    local distance = starter and addon.QuestLocation.GetDistanceMetric(mapAPI, starter)
    local nearest, nearestYards
    local function AddSpawns(spawns, isTrigger)
        for areaID, points in pairs(spawns or {}) do
            local mapID = zones:GetUiMapIdByAreaId(areaID)
            local info = mapID and mapAPI.GetMapInfo(mapID)
            if info and (info.mapType == mapType.Zone or info.mapType == mapType.Micro) then
                for _, point in ipairs(points) do
                    local x, y = point[1], point[2]
                    if x >= 0 and x <= 100 and y >= 0 and y <= 100 and (x > 0 or y > 0)
                        and phasing.IsSpawnVisible(point[3]) then
                        if found and found ~= mapID then ambiguous = true end
                        found = mapID
                        if not isTrigger and not distance then break end
                        local marker = { mapID = mapID, x = x / 100, y = y / 100 }
                        if isTrigger then
                            if triggerPoint then multipleTriggerPoints = true end
                            triggerPoint = marker
                        end
                        if distance and maps[mapID] then
                            local yards = distance(starter, marker)
                            if yards and (not nearestYards or yards < nearestYards) then
                                nearest, nearestYards = marker, yards
                            end
                        end
                    end
                end
            end
        end
    end

    local trigger = db.Quest.triggerEnd(id)
    if trigger then AddSpawns(trigger[2], true) end
    local objectives = db.Quest.objectives(id) or {}
    for index = 4, 6 do
        if HasEntries(objectives[index]) then return end
    end
    for _, objective in ipairs(objectives[1] or {}) do AddSpawns(db.Npc.spawns(objective[1])) end
    for _, objective in ipairs(objectives[2] or {}) do AddSpawns(db.Object.spawns(objective[1])) end
    for _, objective in ipairs(objectives[3] or {}) do
        for _, npcID in ipairs(db.Item.npcDrops(objective[1]) or {}) do AddSpawns(db.Npc.spawns(npcID)) end
        for _, objectID in ipairs(db.Item.objectDrops(objective[1]) or {}) do AddSpawns(db.Object.spawns(objectID)) end
    end
    if starter then
        if nearest then return nearest.mapID, nearest, nearestYards end
        if found and not ambiguous then return found end
        if not (trigger or HasEntries(objectives[1]) or HasEntries(objectives[2]) or HasEntries(objectives[3])
            or (db.Quest.extraObjectives and HasEntries(db.Quest.extraObjectives(id)))) then
            local finisher = FindTurnIn(mapAPI, mapType, maps, id)
            if finisher then return finisher.mapID, finisher, distance and distance(starter, finisher) end
        end
        return
    end
    if ambiguous then return nil, true end
    return found, nil, not multipleTriggerPoints and triggerPoint or nil
end

function QuestieRoutes.GetOfferTarget(mapAPI, mapType, maps, id, starter)
    if not (LibQuestieDB and mapType) then return end
    local ok, mapID, point, yards = pcall(FindObjectiveMap, mapAPI, mapType, id, starter, maps)
    if ok then return mapID, point, yards end
end

function QuestieRoutes.GetObjectiveMap(mapAPI, mapType, id)
    if not (LibQuestieDB and mapType) then return end
    local ok, mapID, ambiguous, triggerPoint = pcall(FindObjectiveMap, mapAPI, mapType, id)
    if ok then return mapID, ambiguous, triggerPoint end
end

local function BuildChains(mapAPI, api, quests, markers, killMarkers, skipped, maps)
    local db, npc = LibQuestieDB.Quest, LibQuestieDB.Npc
    local zones = QuestieLoader:ImportModule("ZoneDB")
    local phasing = QuestieLoader:ImportModule("Phasing")
    local _, _, race = UnitRace("player")
    local _, _, class = UnitClass("player")
    local player = { level = UnitLevel("player"), race = race, class = class }
    local chains = {}
    for _, quest in ipairs(quests) do
        local marker = markers[quest.id] and markers[quest.id][1]
        local objectives = not quest.readyToTurnIn and killMarkers and killMarkers[quest.id]
            and api.GetQuestObjectives(quest.id)
        if not quest.special and marker and (quest.readyToTurnIn or (objectives and #objectives == 1)) then
            local finisherID = SingleNpc(db.finishedBy(quest.id))
            local finisher = finisherID and SpawnPoint(npc.spawns(finisherID), maps, zones, phasing)
            local distance = finisher and addon.QuestLocation.GetDistanceMetric(mapAPI, finisher)
            if distance then
                local chain = { finisher = finisher, stops = {}, followUps = {}, ready = quest.readyToTurnIn }
                local planned, previous = { [quest.id] = true }, quest.id
                for depth = 1, 2 do
                    local id = NextQuest(db, api, previous, planned, player, skipped)
                    local stops = id and FollowUpStops(db, npc, id, maps, zones, phasing, distance)
                    if not stops then break end
                    chain.followUps[depth] = db.name(id) or L.QuestNumber:format(id)
                    for _, stop in ipairs(stops) do
                        stop.depth = depth
                        chain.stops[#chain.stops + 1] = stop
                    end
                    planned[id], previous = true, id
                end
                if #chain.followUps > 0 then chains[quest.id] = chain end
            end
        end
    end
    return chains
end

function QuestieRoutes.GetChains(mapAPI, api, quests, markers, killMarkers, skipped, maps)
    if not (LibQuestieDB and api.IsQuestFlaggedCompleted and UnitRace and UnitClass and UnitLevel) then return end
    local ok, chains = pcall(BuildChains, mapAPI, api, quests, markers, killMarkers, skipped, maps)
    return ok and chains or nil
end
