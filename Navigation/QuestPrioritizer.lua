local _, addon = ...
local QuestPrioritizer = {}
addon.QuestPrioritizer = QuestPrioritizer

function QuestPrioritizer.GetLevel(quest)
    local level = quest.level
    if type(level) == "number" and level > 0 and level < math.huge then
        return level
    end
end

function QuestPrioritizer.Rank(quests, includeElite, skippedQuestIDs)
    local ranked = {}
    for _, quest in ipairs(quests) do
        local skipped = skippedQuestIDs and skippedQuestIDs[quest.id]
        local excludedElite = includeElite == false and quest.elite
        if not (quest.failed or quest.disabled or skipped or excludedElite) then
            ranked[#ranked + 1] = quest
        end
    end

    table.sort(ranked, function(left, right)
        local leftLevel = QuestPrioritizer.GetLevel(left) or math.huge
        local rightLevel = QuestPrioritizer.GetLevel(right) or math.huge
        if leftLevel ~= rightLevel then
            return leftLevel < rightLevel
        end
        return left.id < right.id
    end)
    return ranked
end
