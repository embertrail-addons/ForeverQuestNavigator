local _, addon = ...
local QuestPrioritizer = {}
addon.QuestPrioritizer = QuestPrioritizer

local DISTANCE_SWITCH_MARGIN = 20
local HIGH_LEVEL_GAP = 4

function QuestPrioritizer.GetLevel(quest)
    local level = quest.level
    if type(level) == "number" and level > 0 and level < math.huge then
        return level
    end
end

function QuestPrioritizer.IsHighLevel(quest, playerLevel)
    local level = QuestPrioritizer.GetLevel(quest)
    return not quest.readyToTurnIn and level and type(playerLevel) == "number"
        and playerLevel > 0 and level - playerLevel >= HIGH_LEVEL_GAP
end

function QuestPrioritizer.GetLevelPenalty(quest, playerLevel)
    local level = QuestPrioritizer.GetLevel(quest)
    if quest.readyToTurnIn or not level or type(playerLevel) ~= "number" or playerLevel <= 0 then return 0 end
    -- Express level fit in yards so close quests still matter at a zone border.
    local difference = level - playerLevel
    local above = math.max(0, difference - 1) * 50
    local below = math.max(0, -difference - 4) * 20
    return math.min(300, above + below)
end

function QuestPrioritizer.Rank(quests, skippedQuestIDs, localQuestIDs)
    local ranked = {}
    for _, quest in ipairs(quests) do
        local skipped = skippedQuestIDs and skippedQuestIDs[quest.id]
        local outsideLocalMap = localQuestIDs and not localQuestIDs[quest.id]
        if not (quest.failed or quest.disabled or skipped or outsideLocalMap) then
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

function QuestPrioritizer.RankByDistance(levelRanked, measurements, previousOrder, playerLevel)
    local remaining, unknownQuests, levelOrder, scores, highLevel = {}, {}, {}, {}, {}
    for index, quest in ipairs(levelRanked) do
        highLevel[quest.id] = QuestPrioritizer.IsHighLevel(quest, playerLevel) == true
        if measurements[quest.id] then
            remaining[#remaining + 1] = quest
            levelOrder[quest.id] = index
            scores[quest.id] = measurements[quest.id].yards + QuestPrioritizer.GetLevelPenalty(quest, playerLevel)
        else
            unknownQuests[#unknownQuests + 1] = quest
        end
    end

    table.sort(remaining, function(left, right)
        if highLevel[left.id] ~= highLevel[right.id] then return not highLevel[left.id] end
        if scores[left.id] ~= scores[right.id] then
            return scores[left.id] < scores[right.id]
        end
        return levelOrder[left.id] < levelOrder[right.id]
    end)

    local previousPositions = {}
    for index, quest in ipairs(previousOrder or {}) do
        previousPositions[quest.id] = index
    end

    -- Give the existing order preference only within the margin of the best remaining score.
    local knownQuests = {}
    while #remaining > 0 do
        local choice = 1
        local closest = remaining[1]
        local limit = scores[closest.id] + DISTANCE_SWITCH_MARGIN
        local preferredPosition = previousPositions[closest.id] or math.huge
        for index = 2, #remaining do
            local quest = remaining[index]
            if highLevel[quest.id] ~= highLevel[closest.id] or scores[quest.id] > limit then break end
            local previousPosition = previousPositions[quest.id] or math.huge
            if previousPosition < preferredPosition then
                choice, preferredPosition = index, previousPosition
            end
        end
        knownQuests[#knownQuests + 1] = table.remove(remaining, choice)
    end

    local ranked = {}
    for _, isHigh in ipairs({ false, true }) do
        for _, quest in ipairs(knownQuests) do
            if highLevel[quest.id] == isHigh then ranked[#ranked + 1] = quest end
        end
        for _, quest in ipairs(unknownQuests) do
            if highLevel[quest.id] == isHigh then ranked[#ranked + 1] = quest end
        end
    end
    return ranked, knownQuests
end
