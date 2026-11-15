local _, addon = ...
local QuestLog = {}
addon.QuestLog = QuestLog

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
                elite = api.IsEliteQuest and api.IsEliteQuest(questID),
                readyToTurnIn = api.IsComplete(questID),
                failed = api.IsFailed and api.IsFailed(questID),
                disabled = api.IsQuestDisabledForSession and api.IsQuestDisabledForSession(questID),
            }
        end
    end
    return quests
end

function QuestLog.GetObjectiveText(api, questID)
    local objectives = api.GetQuestObjectives and api.GetQuestObjectives(questID)
    for _, objective in ipairs(objectives or {}) do
        if not objective.finished and objective.text and objective.text ~= "" then
            return objective.text
        end
    end
end
