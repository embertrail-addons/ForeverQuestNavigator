local _, addon = ...
addon.QuestState = {}
function addon.QuestState.Read(quest, offer, manual)
    local L = addon.L
    if manual then return "*", L.StatePriority end
    if offer then return "!", L.StateAccept end
    if quest and quest.readyToTurnIn then return "?", L.StateTurnIn end
    return ">", L.StateObjective
end
