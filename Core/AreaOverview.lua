local _, addon = ...

function addon.BuildTargetGroups(mapAPI, entries, zoneName)
    local groups, metrics = {}, {}
    for _, entry in ipairs(entries or {}) do
        local selected
        for _, group in ipairs(groups) do
            local distance = metrics[group]
            local yards = distance and distance(group.target, entry.target)
            if yards and yards <= 80 then selected = group break end
        end
        if not selected then
            selected = { key = entry.quest.id, target = entry.target, entries = {}, yards = entry.yards,
                place = entry.target.turnInName or zoneName or addon.L.UnknownZone }
            groups[#groups + 1] = selected
            metrics[selected] = addon.QuestLocation.GetDistanceMetric(mapAPI, selected.target) or false
        end
        selected.entries[#selected.entries + 1] = entry
        selected.key = math.min(selected.key, entry.quest.id)
    end
    return groups
end

function addon.BuildAreaOverview(mapAPI, mapType, zoneID, quests, markers, localMaps, avoided)
    if not zoneID then return end
    local _, zoneName = addon.QuestLocation.GetZone(mapAPI, mapType, zoneID)
    local result = { zoneID = zoneID, zoneName = zoneName, objectives = 0, turnIns = 0, entries = {} }
    local localMarkers, ids, counts, zoneCache = {}, {}, {}, {}
    for _, quest in ipairs(quests or {}) do
        local goals = {}
        local excluded = avoided[quest.id] or {}
        for _, marker in ipairs(markers[quest.id] or {}) do
            if not excluded[marker.objectiveIndex] then
                local zone = zoneCache[marker.mapID]
                if zone == nil then
                    zone = addon.QuestLocation.GetZone(mapAPI, mapType, marker.mapID) or false
                    zoneCache[marker.mapID] = zone
                end
                if zone == zoneID then
                    if not localMarkers[quest.id] then
                        ids[#ids + 1] = quest.id
                        localMarkers[quest.id] = {}
                    end
                    local points = localMarkers[quest.id]
                    points[#points + 1] = marker
                    goals[marker.objectiveIndex or 0] = true
                end
            end
        end
        local count = 0
        for _ in pairs(goals) do count = count + 1 end
        counts[quest.id] = count
    end
    local measurements = addon.QuestLocation.MeasureQuests(mapAPI, localMarkers, ids, localMaps)
    for _, quest in ipairs(quests or {}) do
        local measured = measurements[quest.id]
        if measured then
            local count = counts[quest.id]
            local entry = { quest = quest, target = measured.marker, yards = math.floor(measured.yards + 0.5),
                objectives = quest.readyToTurnIn and 0 or count,
                action = quest.readyToTurnIn and "turnIn" or "objective" }
            result.entries[#result.entries + 1] = entry
            if quest.readyToTurnIn then result.turnIns = result.turnIns + 1 else result.objectives = result.objectives + count end
        end
    end
    table.sort(result.entries, function(a, b)
        if a.yards ~= b.yards then return a.yards < b.yards end
        return a.quest.id < b.quest.id
    end)
    result.groups = addon.BuildTargetGroups(mapAPI, result.entries, zoneName)
    return result
end
