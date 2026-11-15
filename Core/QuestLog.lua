local _, addon = ...
local QuestLog = {}
addon.QuestLog = QuestLog

-- QuestTag IDs from the Forever client. Group/elite quests use tag 1.
local specialTags = {
    [41] = true, -- PvP
    [62] = true, -- Raid
    [81] = true, -- Dungeon
    [85] = true, -- Heroic
    [88] = true, -- Raid10
    [89] = true, -- Raid25
    [294] = true, -- Celestial dungeon (Questie)
}

function QuestLog.IsSpecialQuest(api, id)
    local tag = api.GetQuestTagInfo and api.GetQuestTagInfo(id)
    if tag and specialTags[tag.tagID] then return true end
    local integration = addon.QuestieIntegration
    return integration and specialTags[integration.GetQuestTagID(id)] == true
end

function QuestLog.Read(api)
    if not (api and api.GetNumQuestLogEntries and api.GetInfo and api.IsOnQuest and api.IsComplete) then
        return nil
    end

    local quests = {}
    local entryCount = api.GetNumQuestLogEntries()
    for index = 1, entryCount do
        local info = api.GetInfo(index)
        if info and not (info.isHeader or info.isHidden or info.isInternalOnly or info.isTask)
            and info.questID and info.questID > 0 and api.IsOnQuest(info.questID) then
            local questID = info.questID
            quests[#quests + 1] = {
                id = questID,
                title = info.title,
                level = info.level,
                special = QuestLog.IsSpecialQuest(api, questID),
                readyToTurnIn = api.IsComplete(questID),
                failed = api.IsFailed and api.IsFailed(questID),
                disabled = api.IsQuestDisabledForSession and api.IsQuestDisabledForSession(questID),
            }
        end
    end
    return quests
end

function QuestLog.GetNextObjective(api, questID)
    local objectives = api.GetQuestObjectives and api.GetQuestObjectives(questID)
    for index, objective in ipairs(objectives or {}) do
        if not objective.finished and objective.text and objective.text ~= "" then
            return objective, index
        end
    end
end

function QuestLog.GetObjectiveText(api, questID)
    local objective = QuestLog.GetNextObjective(api, questID)
    return objective and objective.text
end
