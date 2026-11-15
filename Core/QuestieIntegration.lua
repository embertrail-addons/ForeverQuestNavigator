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

local function LocalMarker(localMaps, mapID, x, y)
    if localMaps[mapID] and type(x) == "number" and type(y) == "number"
        and x >= 0 and x <= 100 and y >= 0 and y <= 100 and (x > 0 or y > 0) then
        return { mapID = mapID, x = x / 100, y = y / 100 }
    end
end

-- Use the same native objective index for the progress text and the target.
local function CollectObjectiveMarkers(quests, questAPI, localMaps, useKillLocations)
    local active = QuestieLoader:ImportModule("ActiveQuests")
    local zones = QuestieLoader:ImportModule("ZoneDB")
    local phasing = QuestieLoader:ImportModule("Phasing")
    local markersByQuest, killMarkers = {}, {}
    local mapsByArea = {}
    for _, quest in ipairs(quests) do
        local acceptance = not (quest.readyToTurnIn or quest.disabled or quest.failed) and active.Get(quest.id)
        local questData = acceptance and acceptance.quest
        if questData then
            local objective, index = addon.QuestLog.GetNextObjective(questAPI, quest.id)
            local data = objective and questData.ObjectiveData and questData.ObjectiveData[index]
            local cached = data and questData.Objectives and questData.Objectives[index]
            local kind = data and data.Type
            local validType = kind == "item" or kind == "object" or kind == "event" or kind == "monster"
            local spawns = validType and objective.type == kind and cached and cached.Type == kind and cached.Id == data.Id
                and cached.spawnList
            if spawns and (kind ~= "monster" or useKillLocations) then
                local markers = {}
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
                                        markers[#markers + 1] = marker
                                    end
                                end
                            end
                        end
                    end
                end
                if #markers > 0 then
                    markersByQuest[quest.id] = markers
                    if kind == "monster" then killMarkers[quest.id] = markers end
                end
            end
        end
    end
    return markersByQuest, killMarkers
end

-- Read the NPC starter pins Questie has already generated, including its own
-- prerequisite and faction filtering. Never ask Questie to redraw its map.
local function FindNearbyOffers(mapAPI, questAPI, localMaps, playerLevel, radius)
    local questieMap = QuestieLoader:ImportModule("QuestieMap")
    local markersByQuest, offersByID, ids = {}, {}, {}
    for id, frames in pairs(questieMap.questIdFrames) do
        for name in pairs(frames) do
            local pin = _G[name]
            local data = pin and pin.miniMapIcon == false and localMaps[pin.UiMapID] and pin.data
            local quest = data and data.Type == "available" and data.StarterType == nil and data.Id == id and data.QuestData
            if quest and type(id) == "number" and id > 0 and type(quest.name) == "string" and quest.name ~= ""
                and type(quest.requiredLevel) == "number" and quest.requiredLevel <= playerLevel then
                local marker = LocalMarker(localMaps, pin.UiMapID, pin.x, pin.y)
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
    for id, measurement in pairs(addon.QuestLocation.MeasureQuests(mapAPI, markersByQuest, ids)) do
        local distance = measurement.yards
        if distance <= radius
            and not questAPI.IsOnQuest(id)
            and not (questAPI.IsQuestFlaggedCompleted and questAPI.IsQuestFlaggedCompleted(id))
            and not (questAPI.IsQuestDisabledForSession and questAPI.IsQuestDisabledForSession(id)) then
            local offer = offersByID[id]
            measurement.id, measurement.title, measurement.level = id, offer.title, offer.level
            offers[#offers + 1] = measurement
        end
    end
    table.sort(offers, function(a, b)
        if a.yards ~= b.yards then return a.yards < b.yards end
        return a.id < b.id
    end)
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
