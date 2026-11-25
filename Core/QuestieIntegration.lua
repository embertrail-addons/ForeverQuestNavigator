local _, addon = ...
local Integration = {}
addon.QuestieIntegration = Integration

function Integration.IsReady()
    return Questie and Questie.API and Questie.API.isReady and QuestieLoader and QuestieLoader.ImportModule
end

local function GetCorrectedTagID(id)
    local db = QuestieLoader:ImportModule("QuestieDB")
    return db.GetQuestTagInfo(id)
end

function Integration.GetQuestTagID(id)
    if not Integration.IsReady() then return end
    local ok, tagID = pcall(GetCorrectedTagID, id)
    if ok then return tagID end
end
function Integration.GetPreparation(api, id)
    local db = LibQuestieDB and LibQuestieDB.Quest
    return addon.QuestPreparation.Read(db, api, id, GetItemCount or C_Item and C_Item.GetItemCount, GetItemInfo)
end
function Integration.GetRepeatable(api, id)
    return addon.QuestPreparation.Repeatable(LibQuestieDB and LibQuestieDB.Quest, api, id)
end

function Integration.GetObjectiveItemID(id, index)
    if not Integration.IsReady() then return end
    local ok, itemID = pcall(function()
        local active = QuestieLoader:ImportModule("ActiveQuests").Get(id)
        local quest = active and active.quest
        local data = quest and quest.ObjectiveData and quest.ObjectiveData[index]
        local cached = quest and quest.Objectives and quest.Objectives[index]
        if data and data.Type == "item" and cached and cached.Type == "item" and cached.Id == data.Id then return data.Id end
    end)
    if ok then return itemID end
end

function Integration.GetCombatMarkers(quests, api)
    if not Integration.IsReady() then return {} end
    local ok, result = pcall(function()
        local active, relations = QuestieLoader:ImportModule("ActiveQuests"), {}
        for _, quest in ipairs(quests or {}) do
            local accepted = not quest.readyToTurnIn and active.Get(quest.id)
            local data = accepted and accepted.quest
            local goals = data and api.GetQuestObjectives and api.GetQuestObjectives(quest.id)
            for index, goal in ipairs(goals or {}) do
                local source = data.ObjectiveData and data.ObjectiveData[index]
                local cached = data.Objectives and data.Objectives[index]
                if not goal.finished and source and cached and type(source.Id) == "number" and source.Id > 0
                    and source.Type == goal.type and cached.Type == source.Type and cached.Id == source.Id then
                    local ids = {}
                    if source.Type == "monster" then ids[source.Id] = true
                    elseif source.Type == "item" then for _, spawn in pairs(cached.spawnList or {}) do
                        local id = type(spawn.TooltipKey) == "string" and tonumber(spawn.TooltipKey:match("^m_(%d+)$"))
                        if id and spawn.Hostile ~= false then ids[id] = true end
                    end end
                    for id in pairs(ids) do
                        relations[quest.id] = relations[quest.id] or {}
                        relations[quest.id][#relations[quest.id] + 1] = {objectiveIndex = index, npcID = id}
                    end
                end
            end
        end
        return relations
    end)
    return ok and result or {}
end

local function LocalMarker(localMaps, mapID, x, y)
    if localMaps[mapID] and type(x) == "number" and type(y) == "number"
        and x >= 0 and x <= 100 and y >= 0 and y <= 100 and (x > 0 or y > 0) then
        return { mapID = mapID, x = x / 100, y = y / 100 }
    end
end

local function CollectObjectiveMarkers(quests, questAPI, localMaps, useKillLocations)
    local active = QuestieLoader:ImportModule("ActiveQuests")
    local zones = QuestieLoader:ImportModule("ZoneDB")
    local phasing = QuestieLoader:ImportModule("Phasing")
    local markersByQuest, killMarkers = {}, {}
    local mapsByArea = {}
    for _, quest in ipairs(quests) do
        local acceptance = not (quest.readyToTurnIn or quest.disabled or quest.failed) and active.Get(quest.id)
        local questData = acceptance and acceptance.quest
        local objectives = questData and questAPI.GetQuestObjectives and questAPI.GetQuestObjectives(quest.id)
        local markers = {}
        for index, objective in ipairs(objectives or {}) do
            local data = not objective.finished and questData.ObjectiveData and questData.ObjectiveData[index]
            local cached = data and questData.Objectives and questData.Objectives[index]
            local kind = data and data.Type
            local validType = kind == "item" or kind == "object" or kind == "event" or kind == "monster"
            local spawns = validType and objective.type == kind and cached and cached.Type == kind and cached.Id == data.Id
                and cached.spawnList
            if spawns and (kind ~= "monster" or useKillLocations) then
                local markerCount = #markers
                for sourceID, spawn in pairs(spawns) do
                    if kind ~= "monster" or (sourceID == data.Id and spawn.Icon == Questie.ICON_TYPE_SLAY) then
                        for areaID, points in pairs(spawn.Spawns or {}) do
                            if mapsByArea[areaID] == nil then
                                mapsByArea[areaID] = zones:GetUiMapIdByAreaId(areaID) or false
                            end
                            local mapID = mapsByArea[areaID]
                            if localMaps[mapID] then
                                for _, point in ipairs(points) do
                                    local marker = LocalMarker(localMaps, mapID, point[1], point[2])
                                    if marker and phasing.IsSpawnVisible(point[3]) then
                                        marker.objectiveIndex = index
                                        marker.targetKind = kind == "object" and "object" or "area"
                                        marker.notCombatSource = kind == "item" and spawn.Hostile == false or nil
                                        marker.spawnKey = type(spawn.TooltipKey) == "string" and spawn.TooltipKey or kind .. ":" .. tostring(sourceID)
                                        local npcID = kind == "monster" and data.Id
                                            or type(spawn.TooltipKey) == "string" and tonumber(spawn.TooltipKey:match("^m_(%d+)$"))
                                        if type(npcID) == "number" and spawn.Hostile ~= false and kind ~= "object" then marker.npcID = npcID end
                                        markers[#markers + 1] = marker
                                    end
                                end
                            end
                        end
                    end
                end
                if kind == "monster" and #markers > markerCount then
                    killMarkers[quest.id] = markers
                end
            end
        end
        if #markers > 0 then markersByQuest[quest.id] = markers end
    end
    return markersByQuest, killMarkers
end

-- Read the NPC starter pins Questie has already generated, including its own
-- prerequisite and faction filtering. Never ask Questie to redraw its map.
local function GetOfferXP(id)
    local xp = QuestieLoader:ImportModule("QuestXP")
    return xp and xp:GetQuestLogRewardXP(id, false)
end

local function FindNearbyOffers(mapAPI, questAPI, localMaps, targetMaps, mapType, playerLevel, radius, anchor, includeRoute, routeAnchors)
    local questieMap = QuestieLoader:ImportModule("QuestieMap")
    local markersByQuest, offersByID, ids, soon = {}, {}, {}, {}
    for id, frames in pairs(questieMap.questIdFrames) do
        for name in pairs(frames) do
            local pin = _G[name]
            local data = pin and pin.miniMapIcon == false and targetMaps[pin.UiMapID] and pin.data
            local quest = data and data.Type == "available" and data.StarterType == nil and data.Id == id and data.QuestData
            if quest and type(id) == "number" and type(quest.requiredLevel) == "number" and quest.requiredLevel == playerLevel + 1 then
                soon[id] = true
            end
            if quest and type(id) == "number" and id > 0 and type(quest.name) == "string" and quest.name ~= ""
                and type(quest.requiredLevel) == "number" and quest.requiredLevel <= playerLevel then
                local marker = LocalMarker(targetMaps, pin.UiMapID, pin.x, pin.y)
                if marker then
                    if not markersByQuest[id] then
                        ids[#ids + 1] = id
                        offersByID[id] = { title = quest.name, level = quest.level }
                        markersByQuest[id] = {}
                    end
                    local markers = markersByQuest[id]
                    markers[#markers + 1] = marker
                end
            end
        end
    end

    local soonCount = 0
    for _ in pairs(soon) do soonCount = soonCount + 1 end
    Integration.soonAvailable, Integration.soonSet = soonCount, soon
    local offers = {}
    local priority = addon.QuestPrioritizer
    local anchorDistance = anchor and addon.QuestLocation.GetDistanceMetric(mapAPI, anchor)
    local routeMetrics = {}
    for index, point in ipairs(routeAnchors or {}) do
        if index > 3 then break end
        local metric = addon.QuestLocation.GetDistanceMetric(mapAPI, point)
        if metric then routeMetrics[#routeMetrics + 1] = {point = point, metric = metric} end
    end
    local canEarnXP = addon.QuestLog.GetXPToNextLevel() ~= nil
    for id, measurement in pairs(addon.QuestLocation.MeasureQuests(mapAPI, markersByQuest, ids, localMaps)) do
        local distance = measurement.yards
        local pickupGap = includeRoute and anchorDistance and anchorDistance(anchor, measurement.marker)
        if includeRoute then for _, entry in ipairs(routeMetrics) do
            local gap = entry.metric(entry.point, measurement.marker)
            if gap and (not pickupGap or gap < pickupGap) then pickupGap = gap end
        end end
        local nearby = distance <= radius or pickupGap and pickupGap <= radius
        local preparation = nearby and Integration.GetPreparation(questAPI, id) or {}
        if nearby
            and not questAPI.IsOnQuest(id)
            and (preparation.repeatable or not (questAPI.IsQuestFlaggedCompleted and questAPI.IsQuestFlaggedCompleted(id)))
            and not (questAPI.IsQuestDisabledForSession and questAPI.IsQuestDisabledForSession(id)) then
            local offer = offersByID[id]
            measurement.id, measurement.title, measurement.level = id, offer.title, offer.level
            measurement.routePickup = distance > radius and true or nil
            measurement.group = Integration.GetQuestTagID(id) == 1
            measurement.special = addon.QuestLog.IsSpecialQuest(questAPI, id)
            measurement.preparation = preparation
            measurement.repeatable = measurement.preparation.repeatable
            local mapID, objective, travel = addon.QuestieRoutes.GetOfferTarget(
                mapAPI, mapType, targetMaps, id, measurement.marker)
            local _, zoneName = addon.QuestLocation.GetZone(mapAPI, mapType, mapID)
            local _, pickupZone = addon.QuestLocation.GetZone(mapAPI, mapType, measurement.marker.mapID)
            local gap = anchorDistance and objective and anchorDistance(anchor, objective)
            measurement.objectiveZone = zoneName
            measurement.objectiveMarker = objective
            measurement.pickupZone = pickupZone
            measurement.levelPenalty = priority.GetLevelPenalty(measurement, playerLevel)
            measurement.nearActiveTarget = gap and gap <= 500
            measurement.anchorGap = gap
            measurement.journeyYards = travel and distance + travel
            measurement.objectiveYards = travel
            if canEarnXP then
                local xp = addon.QuestLog.GetTurnInXP(measurement)
                if not xp then
                    local ok, estimate = pcall(GetOfferXP, id)
                    if ok and type(estimate) == "number" and estimate > 0 and estimate < math.huge then xp = estimate end
                end
                measurement.xp = xp
            end
            measurement.lowPriority = priority.IsLowPriority(measurement, playerLevel)
            measurement.score = addon.Recommendation.ScoreOffer(measurement)
            offers[#offers + 1] = measurement
        end
    end
    table.sort(offers, function(a, b)
        if a.lowPriority ~= b.lowPriority then return not a.lowPriority end
        if a.score ~= b.score then return a.score < b.score end
        if a.yards ~= b.yards then return a.yards < b.yards end
        return a.id < b.id
    end)
    local best, second = offers[1], offers[2]
    if best and not best.lowPriority and best.journeyYards and priority.GetLevel(best) then
        best.recommended = (best.nearActiveTarget and best.journeyYards <= 750)
            or (best.journeyYards <= 500 and second and (second.lowPriority or second.score - best.score >= 75))
        if best.recommended then
            best.recommendationReason = best.nearActiveTarget and best.journeyYards <= 750 and "nearTarget" or "shortRoute"
        end
    end
    return offers
end

function Integration.GetObjectiveMarkers(quests, questAPI, localMaps, useKillLocations)
    local ok, markers, kills = pcall(CollectObjectiveMarkers, quests, questAPI, localMaps, useKillLocations)
    if ok then return markers, kills end
end

-- Quest givers on the shown maps that unlock at the next level (only when Questie draws them).
function Integration.SoonAvailable() return Integration.soonAvailable end
function Integration.SoonSet()
    local copy = {}
    for id in pairs(Integration.soonSet or {}) do copy[id] = true end
    return copy
end

local function StarterOnMaps(db, id, maps, zones)
    local ok, givers = pcall(db.Quest.startedBy, id)
    if not ok or type(givers) ~= "table" then return false end
    for kind, entity in ipairs({db.Npc, db.Object}) do
        for _, giver in ipairs(givers[kind] or {}) do
            local spawnsOk, spawns = pcall(entity.spawns, giver)
            for area in pairs(spawnsOk and type(spawns) == "table" and spawns or {}) do
                local mapID = zones and zones.GetUiMapIdByAreaId and zones:GetUiMapIdByAreaId(area)
                if mapID and maps[mapID] then return true end
            end
        end
    end
    return false
end

-- Follow-up quests of the given quests that unlock exactly at the next level and start
-- on one of the shown maps. Uses only QuestieDB fields FQN already relies on.
function Integration.SoonFollowUps(ids, playerLevel, maps)
    local found = {}
    local db = LibQuestieDB
    if not (db and db.Quest and db.Quest.nextQuestInChain and db.Quest.requiredLevel and db.Quest.startedBy
        and db.Npc and db.Object and type(playerLevel) == "number" and type(maps) == "table") then return found end
    local zones = QuestieLoader and QuestieLoader.ImportModule and QuestieLoader:ImportModule("ZoneDB")
    for _, id in ipairs(ids or {}) do
        local ok, nextID = pcall(db.Quest.nextQuestInChain, id)
        if ok and type(nextID) == "number" and nextID > 0 and not found[nextID] then
            local levelOk, required = pcall(db.Quest.requiredLevel, nextID)
            if levelOk and required == playerLevel + 1 and StarterOnMaps(db, nextID, maps, zones) then found[nextID] = true end
        end
    end
    return found
end

function Integration.GetNearbyOffers(...)
    local ok, offers = pcall(FindNearbyOffers, ...)
    return ok and offers or nil
end

-- NPC names for the target-mark window. Only NPCs (not objects) can be targeted.
function Integration.NpcName(id)
    local db = LibQuestieDB and LibQuestieDB.Npc
    if type(id) ~= "number" or not (db and type(db.name) == "function") then return end
    local ok, name = pcall(db.name, id)
    if ok and type(name) == "string" and name ~= "" then return name end
end

-- field: "startedBy" (accept) or "finishedBy" (turn-in); first NPC giver only.
function Integration.QuestNpcName(id, field)
    local db = LibQuestieDB and LibQuestieDB.Quest
    if not (db and type(db[field]) == "function") then return end
    local ok, givers = pcall(db[field], id)
    local npcs = ok and type(givers) == "table" and givers[1]
    for _, npc in ipairs(type(npcs) == "table" and npcs or {}) do
        local name = Integration.NpcName(npc)
        if name then return name end
    end
end
