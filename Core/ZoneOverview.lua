local _, addon = ...

-- All eligible accepted quests, grouped by their current actual objective.
-- Access waypoints must not move a quest into a different zone.
function addon.BuildZoneOverview(mapAPI, mapType, quests, snapshot)
    local groups = {}
    for _, quest in ipairs(quests or {}) do
        local measurement = snapshot and snapshot.measurements[quest.id]
        local marker = measurement and (measurement.objectiveMarker or measurement.marker)
        local id, name
        if marker then id, name = addon.QuestLocation.GetZone(mapAPI, mapType, marker.mapID) end
        local key = id or 0
        local group = groups[key]
        if not group then
            group = { id = id, name = name or addon.L.UnknownCoordinates, quests = 0, objectives = 0,
                turnIns = 0, suitable = 0, difficult = 0, low = 0, marker = marker }
            groups[key] = group
        end
        group.quests = group.quests + 1
        if quest.readyToTurnIn then group.turnIns = group.turnIns + 1
        else
            local targets, count = snapshot and snapshot.objectiveDistances[quest.id], 0
            for _ in pairs(targets or {}) do count = count + 1 end
            group.objectives = group.objectives + count
        end
        local difficulty = addon.QuestPrioritizer.GetDifficulty(quest, snapshot and snapshot.playerLevel)
        if difficulty == "red" then group.difficult = group.difficult + 1
        elseif difficulty == "gray" then group.low = group.low + 1
        elseif difficulty then group.suitable = group.suitable + 1 end
        if measurement and (not group.yards or measurement.yards < group.yards) then
            group.yards, group.marker = measurement.yards, marker
        end
    end
    local result = {}
    for _, group in pairs(groups) do result[#result + 1] = group end
    table.sort(result, function(a, b)
        if a.yards ~= b.yards then return (a.yards or math.huge) < (b.yards or math.huge) end
        return (a.id or 0) < (b.id or 0)
    end)
    return result
end
