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

local function FindNearbyOffers(mapAPI, questAPI, localMaps, targetMaps, mapType, playerLevel, radius, anchor)
    local questieMap = QuestieLoader:ImportModule("QuestieMap")
    local markersByQuest, offersByID, ids = {}, {}, {}
    for id, frames in pairs(questieMap.questIdFrames) do
        for name in pairs(frames) do
            local pin = _G[name]
            local data = pin and pin.miniMapIcon == false and targetMaps[pin.UiMapID] and pin.data
            local quest = data and data.Type == "available" and data.StarterType == nil and data.Id == id and data.QuestData
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

    local offers = {}
    local priority = addon.QuestPrioritizer
    local anchorDistance = anchor and addon.QuestLocation.GetDistanceMetric(mapAPI, anchor)
    local canEarnXP = addon.QuestLog.GetXPToNextLevel() ~= nil
    for id, measurement in pairs(addon.QuestLocation.MeasureQuests(mapAPI, markersByQuest, ids, localMaps)) do
        local distance = measurement.yards
        if distance <= radius
            and not questAPI.IsOnQuest(id)
            and not (questAPI.IsQuestFlaggedCompleted and questAPI.IsQuestFlaggedCompleted(id))
            and not (questAPI.IsQuestDisabledForSession and questAPI.IsQuestDisabledForSession(id)) then
            local offer = offersByID[id]
            measurement.id, measurement.title, measurement.level = id, offer.title, offer.level
            measurement.group = Integration.GetQuestTagID(id) == 1
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

function Integration.GetNearbyOffers(...)
    local ok, offers = pcall(FindNearbyOffers, ...)
    return ok and offers or nil
end
