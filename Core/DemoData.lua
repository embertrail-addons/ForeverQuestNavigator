local _, addon = ...
local Demo = {}
addon.DemoData = Demo
-- Only IDs are curated here. Names, levels, goals, XP and positions come from
-- the user's installed Questie data; no database content is bundled with FQN.
Demo.presets = {
    {key = "barrens", level = 14, ids = {871, 844, 845, 869, 903, 867, 870, 848, 850, 5041}},
    {key = "elwynn", level = 9, ids = {52, 83, 88, 112, 86, 6, 7, 18, 33}},
}
local function Read(entity, field, id)
    if not (entity and type(entity[field]) == "function") then return end
    local ok, value = pcall(entity[field], id)
    if ok then return value end
end
local function SortedKeys(values)
    local keys = {}
    for key in pairs(values or {}) do if type(key) == "number" then keys[#keys + 1] = key end end
    table.sort(keys)
    return keys
end
local function Spawns(spawns, zones, phase, mapID)
    local result = {}
    for _, area in ipairs(SortedKeys(spawns)) do
        local map = zones:GetUiMapIdByAreaId(area)
        if map and (not mapID or mapID == map) then
            local points = {}
            for _, coordinate in ipairs(spawns[area]) do
                local visible = not phase or phase.IsSpawnVisible(coordinate[3])
                local point = {mapID = map, x = type(coordinate[1]) == "number" and coordinate[1] / 100,
                    y = type(coordinate[2]) == "number" and coordinate[2] / 100}
                if visible and addon.TravelSupport.ValidPoint(point) then points[#points + 1] = point end
            end
            table.sort(points, function(a, b) if a.x ~= b.x then return a.x < b.x end return a.y < b.y end)
            for _, point in ipairs(points) do
                result[#result + 1] = point
                if #result >= 128 then return result end
            end
        end
    end
    return result
end
local function Giver(db, givers, zones, phase, mapID)
    for kind, entity in ipairs({db.Npc, db.Object}) do
        for _, id in ipairs(givers and givers[kind] or {}) do
            local points = Spawns(Read(entity, "spawns", id), zones, phase, mapID)
            if points[1] then return points[1] end
        end
    end
end
local function Goals(db, id, zones, phase, mapID)
    local goals, markers = {}, {}
    local objectives = Read(db.Quest, "objectives", id) or {}
    for kind, entity in ipairs({db.Npc, db.Object, db.Item}) do
        for _, tuple in ipairs(objectives[kind] or {}) do
            local text = tuple[2] or Read(entity, "name", tuple[1])
            if type(text) == "string" and text ~= "" then
                local index = #goals + 1
                goals[index] = {text = text, index = index, finished = false}
                local positions = {}
                if kind ~= 3 then positions = Spawns(Read(entity, "spawns", tuple[1]), zones, phase, mapID)
                else
                    for sourceKind, sourceEntity in ipairs({db.Npc, db.Object}) do
                        local field = sourceKind == 1 and "npcDrops" or "objectDrops"
                        for _, source in ipairs(Read(db.Item, field, tuple[1]) or {}) do
                            for _, point in ipairs(Spawns(Read(sourceEntity, "spawns", source), zones, phase, mapID)) do
                                positions[#positions + 1] = point
                                if #positions >= 128 then break end
                            end
                            if #positions >= 128 then break end
                        end
                    end
                end
                for _, point in ipairs(positions) do
                    point.objectiveIndex, point.objective = index, true
                    point.targetKind = kind == 2 and "object" or "area"
                    markers[#markers + 1] = point
                end
            end
        end
    end
    return goals, markers
end
function Demo.Read(db, zones, phase, mapAPI, preset, xp)
    if not (db and db.Quest and db.Npc and db.Object and zones and mapAPI and mapAPI.GetMapWorldSize) then return end
    local records, mapID = {}, nil
    for _, id in ipairs(preset.ids) do
        local title, level = Read(db.Quest, "name", id), Read(db.Quest, "questLevel", id)
        local minimum = Read(db.Quest, "requiredLevel", id)
        local starter = Giver(db, Read(db.Quest, "startedBy", id), zones, phase, mapID)
        local map = starter and starter.mapID
        if type(title) == "string" and title ~= "" and type(level) == "number" and level > 0
            and level <= preset.level + 2 and type(minimum) == "number" and minimum <= preset.level and map then
            local finisher = Giver(db, Read(db.Quest, "finishedBy", id), zones, phase, map)
            local goals, markers = Goals(db, id, zones, phase, map)
            if finisher and #goals > 0 and #markers > 0 then
                mapID = mapID or map
                local value = xp and xp[id]
                -- Base XP only: no real-character level, buffs or inventory reads.
                local reward = type(value) == "table" and value[2]
                if type(reward) ~= "number" or reward <= 0 or reward >= math.huge or level < preset.level - 5 then reward = nil end
                records[#records + 1] = {id = id, title = title, level = level, goals = goals,
                    markers = markers, starter = starter, finisher = finisher, xp = reward,
                    description = Read(db.Quest, "objectivesText", id)}
            end
        end
    end
    if #records < 3 then return end
    local width, height = mapAPI.GetMapWorldSize(mapID)
    if type(width) ~= "number" or type(height) ~= "number" or width <= 0 or height <= 0 then return end
    return {records = records, mapID = mapID, level = preset.level, width = width, height = height,
        zone = mapAPI.GetMapInfo and mapAPI.GetMapInfo(mapID), key = preset.key}
end
function Demo.Build(data, scene)
    if scene ~= "objectives" and scene ~= "turnins" and scene ~= "compact" then return end
    local ready = scene == "turnins"
    local source = ready and data.records[1].finisher or data.records[1].markers[1]
    local origin = {mapID = data.mapID, x = math.min(.99, source.x + .012), y = math.min(.99, source.y + .008)}
    local api = {
        GetPlayerMapPosition = function() return {x = origin.x, y = origin.y} end,
        GetMapWorldSize = function() return data.width, data.height end,
    }
    local quests, markers, ids, rewards, records = {}, {}, {}, {}, {}
    local count = math.min(4, #data.records - 1)
    for index = 1, count do
        local record = data.records[index]
        local quest = {id = record.id, title = record.title, level = record.level, readyToTurnIn = ready,
            demoDetails = addon.L.DemoBadge}
        quests[index], ids[index], rewards[quest.id], records[quest.id] = quest, quest.id, record.xp, record
        markers[quest.id] = ready and {record.finisher} or record.markers
    end
    local measured, objectives = addon.QuestLocation.MeasureQuests(api, markers, ids)
    local ranked = addon.QuestPrioritizer.RankByDistance(addon.QuestPrioritizer.Rank(quests, {}), measured, nil, data.level, nil, 5)
    local active = ranked[1]
    if not active or not measured[active.id] then return end
    local record, targets = records[active.id], nil
    local alternatives, zones, rewardLines, alternativeRoutes, preview = {}, {}, {}, {}, {}
    local zone = data.zone and data.zone.name or addon.L.UnknownZone
    local xpNeeded = ready and rewards[active.id] and math.max(1, math.floor(rewards[active.id] * .75)) or 1800
    for index, quest in ipairs(ranked) do
        if index > 1 then alternatives[#alternatives + 1] = quest end
        zones[index] = zone
        local reward = rewards[quest.id]
        rewardLines[index] = reward and (reward >= xpNeeded and addon.L.QuestXPLevelUpShort or addon.L.QuestXPReward:format(reward)) or addon.L.UnknownXP
        local position = measured[quest.id].marker
        local route = ("%s (%.1f, %.1f)"):format(zone, position.x * 100, position.y * 100)
        if index > 1 then alternativeRoutes[index - 1] = route end
        if index <= 3 then preview[#preview + 1] = {quest = quest, target = position, action = ready and "turnIn" or "objective"} end
    end
    if not ready then
        targets = {index = measured[active.id].marker.objectiveIndex, avoidedCount = 0}
        for _, goal in ipairs(record.goals) do
            targets[#targets + 1] = {index = goal.index, text = goal.text, finished = false,
                selectable = objectives[active.id][goal.index] ~= nil}
        end
    end
    local offers = {}
    for index = count + 1, math.min(#data.records, count + 3) do
        local offer = data.records[index]
        local pickup = addon.QuestLocation.MeasureQuests(api, {[offer.id] = {offer.starter}}, {offer.id})[offer.id]
        local target = addon.QuestLocation.MeasureQuests(api, {[offer.id] = offer.markers}, {offer.id})[offer.id]
        if pickup and target then
            offers[#offers + 1] = {id = offer.id, title = offer.title, level = offer.level, marker = offer.starter,
                yards = pickup.yards, east = pickup.east, north = pickup.north, objectiveMarker = target.marker,
                objectiveYards = target.yards, objectiveZone = zone, pickupZone = zone, xp = offer.xp,
                levelPenalty = addon.QuestPrioritizer.GetLevelPenalty(offer, data.level),
                lowPriority = addon.QuestPrioritizer.IsLowPriority(offer, data.level, 5)}
        end
    end
    addon.PlanningInsights.AnnotateOffers(api, offers, quests, measured, active)
    local description = type(record.description) == "table" and table.concat(record.description, "\n") or ""
    local note = ready and rewards[active.id] and rewards[active.id] >= xpNeeded and addon.L.LevelUpOnTurnIn or addon.L.DemoFrozen
    local reason = addon.L.DemoBadge .. "\n" .. description
    local model = {ranked = ranked, measurements = measured, activeQuestID = active.id, activeMeasurement = measured[active.id],
        playerLevel = data.level, xpNeeded = xpNeeded, comparison = addon.L.DemoExplanation,
        bundles = addon.PlanningInsights.Bundles(api, quests, measured, data.level),
        turnInTour = addon.PlanningInsights.TurnIns(api, quests, measured, xpNeeded, nil, function(q) return rewards[q.id] end),
        offers = offers, origin = origin, scene = scene, zone = zone,
        view = {quest = active, objectives = ready and addon.L.ReadyToTurnIn or addon.L.DemoObjectives,
            alternatives = alternatives, routeNote = note, routeDetails = reason,
            zones = zones, alternativeRoutes = alternativeRoutes, rewards = rewardLines, targets = targets,
            hasMap = true, reason = reason, preview = preview}}
    return model
end
function Demo.Load(preset)
    if not addon.QuestieIntegration.IsReady() then return nil, addon.L.DemoNeedsQuestie end
    local ok, result = pcall(function()
        local xp = QuestieLoader:ImportModule("QuestXP")
        return Demo.Read(LibQuestieDB, QuestieLoader:ImportModule("ZoneDB"), QuestieLoader:ImportModule("Phasing"),
            C_Map, preset, xp and xp.db)
    end)
    if ok and result then return result end
    return nil, addon.L.DemoDataMissing
end
