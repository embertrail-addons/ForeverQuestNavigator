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
    local entryCount, totalQuests = api.GetNumQuestLogEntries()
    for index = 1, entryCount do
        local info = api.GetInfo(index)
        if info and not (info.isHeader or info.isHidden or info.isInternalOnly or info.isTask)
            and info.questID and info.questID > 0 and api.IsOnQuest(info.questID) then
            local questID = info.questID
            local tag = api.GetQuestTagInfo and api.GetQuestTagInfo(questID)
            local group = tag and tag.tagID == 1 or addon.QuestieIntegration.GetQuestTagID(questID) == 1
            local ready = api.IsComplete(questID)
            quests[#quests + 1] = {
                id = questID,
                title = info.title,
                level = info.level,
                elite = api.IsEliteQuest and api.IsEliteQuest(questID) == true,
                group = group,
                special = QuestLog.IsSpecialQuest(api, questID),
                readyToTurnIn = ready,
                failed = api.IsFailed and api.IsFailed(questID),
                disabled = api.IsQuestDisabledForSession and api.IsQuestDisabledForSession(questID),
                progress = not ready and addon.QuestTools.Progress(api, questID) or nil,
            }
        end
    end
    return quests, totalQuests
end

function QuestLog.GetNextObjective(api, questID)
    local objectives = api.GetQuestObjectives and api.GetQuestObjectives(questID)
    for index, objective in ipairs(objectives or {}) do
        if not objective.finished and objective.text and objective.text ~= "" then
            return objective, index
        end
    end
end

local function IsPublicNumber(value)
    return not (issecretvalue and issecretvalue(value)) and type(value) == "number"
end

function QuestLog.GetXPToNextLevel()
    if not (UnitXP and UnitXPMax) or (IsXPUserDisabled and IsXPUserDisabled())
        or (IsPlayerAtEffectiveMaxLevel and IsPlayerAtEffectiveMaxLevel()) then return end
    local current, maximum = UnitXP("player"), UnitXPMax("player")
    if IsPublicNumber(current) and IsPublicNumber(maximum) and current >= 0
        and maximum > current and maximum < math.huge then
        return maximum - current
    end
end

function QuestLog.GetTurnInXP(quest)
    if not GetQuestLogRewardXP then return end
    local ok, xp = pcall(GetQuestLogRewardXP, quest.id)
    if ok and IsPublicNumber(xp) and xp > 0 and xp < math.huge then return xp end
end
