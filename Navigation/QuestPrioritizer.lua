local _, addon = ...
local QuestPrioritizer = {}
addon.QuestPrioritizer = QuestPrioritizer

local DISTANCE_SWITCH_MARGIN = 20
local HIGH_LEVEL_GAP = 3

function QuestPrioritizer.GetLevel(quest)
    local level = quest.level
    if type(level) == "number" and level > 0 and level < math.huge then
        return level
    end
end

function QuestPrioritizer.GetDifficulty(quest, playerLevel)
    local level = QuestPrioritizer.GetLevel(quest)
    if not level or type(playerLevel) ~= "number" or not (playerLevel > 0 and playerLevel < math.huge) then return end
    local gap = level - playerLevel
    if gap >= HIGH_LEVEL_GAP then return "red" end
    if gap > 0 then return "orange" end
    if gap >= -1 then return "yellow" end

    local range = UnitQuestTrivialLevelRange and UnitQuestTrivialLevelRange("player")
    if type(range) ~= "number" or not (range >= 2 and range < math.huge) then
        range = playerLevel < 20 and 5 or (playerLevel < 40 and 6 or 7)
    end
    return -gap <= range and "green" or "gray"
end

local function GetPriorityTier(quest, difficulty)
    if quest.readyToTurnIn then return 1 end
    if difficulty == "gray" then return 2 end
    if difficulty == "red" then return 3 end
    return 1
end

function QuestPrioritizer.IsLowPriority(quest, playerLevel)
    return GetPriorityTier(quest, QuestPrioritizer.GetDifficulty(quest, playerLevel)) > 1
end

local function LevelPenalty(quest, playerLevel, difficulty)
    if quest.readyToTurnIn then return 0 end
    -- Express level fit in yards so close quests still matter at a zone border.
    if difficulty == "orange" then return 50 * (quest.level - playerLevel) end
    if difficulty == "green" then return 35 end
    if difficulty == "red" then return math.min(300, 50 * (quest.level - playerLevel)) end
    return 0
end

function QuestPrioritizer.GetLevelPenalty(quest, playerLevel)
    return LevelPenalty(quest, playerLevel, QuestPrioritizer.GetDifficulty(quest, playerLevel))
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
    local remaining, unknownQuests, levelOrder, scores, tiers = {}, {}, {}, {}, {}
    for index, quest in ipairs(levelRanked) do
        local difficulty = QuestPrioritizer.GetDifficulty(quest, playerLevel)
        tiers[quest.id] = GetPriorityTier(quest, difficulty)
        if measurements[quest.id] then
            remaining[#remaining + 1] = quest
            levelOrder[quest.id] = index
            scores[quest.id] = measurements[quest.id].yards + LevelPenalty(quest, playerLevel, difficulty)
        else
            unknownQuests[#unknownQuests + 1] = quest
        end
    end

    table.sort(remaining, function(left, right)
        if tiers[left.id] ~= tiers[right.id] then return tiers[left.id] < tiers[right.id] end
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
            if tiers[quest.id] ~= tiers[closest.id] or scores[quest.id] > limit then break end
            local previousPosition = previousPositions[quest.id] or math.huge
            if previousPosition < preferredPosition then
                choice, preferredPosition = index, previousPosition
            end
        end
        knownQuests[#knownQuests + 1] = table.remove(remaining, choice)
    end

    local ranked = {}
    for tier = 1, 3 do
        for _, quest in ipairs(knownQuests) do
            if tiers[quest.id] == tier then ranked[#ranked + 1] = quest end
        end
        for _, quest in ipairs(unknownQuests) do
            if tiers[quest.id] == tier then ranked[#ranked + 1] = quest end
        end
    end
    return ranked, knownQuests
end
