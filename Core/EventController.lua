local _, addon = ...
addon.EventController = {}
local runtimeEvents = {
    "PLAYER_ENTERING_WORLD",
    "PLAYER_CONTROL_LOST",
    "PLAYER_CONTROL_GAINED",
    "PLAYER_REGEN_ENABLED",
    "PLAYER_REGEN_DISABLED",
    "PLAYER_LEVEL_UP",
    "PLAYER_XP_UPDATE",
    "PLAYER_LOGOUT",
    "QUEST_LOG_UPDATE",
    "QUEST_LOG_CRITERIA_UPDATE",
    "QUEST_WATCH_UPDATE",
    "QUEST_DATA_LOAD_RESULT",
    "QUEST_ACCEPTED",
    "QUEST_REMOVED",
    "QUEST_TURNED_IN",
    "QUEST_POI_UPDATE",
    "QUEST_WATCH_LIST_CHANGED",
    "GROUP_ROSTER_UPDATE",
    "PLAYER_MAP_CHANGED",
    "ZONE_CHANGED_NEW_AREA",
    "TAXI_NODE_STATUS_CHANGED",
    "TAXIMAP_OPENED",
    "TAXIMAP_CLOSED",
    "BAG_UPDATE_DELAYED",
    "UPDATE_INVENTORY_DURABILITY",
    "PLAYER_EQUIPMENT_CHANGED",
    "PLAYER_MOUNT_DISPLAY_CHANGED",
    "GET_ITEM_INFO_RECEIVED",
}

function addon.EventController.RegisterRuntime(frame)
    for _, event in ipairs(runtimeEvents) do frame:RegisterEvent(event) end
end

function addon.EventController.Handle(context, event, arg, rewardXP)
    if event == "GET_ITEM_INFO_RECEIVED" then
        if context.itemRewardsUpdated and context.itemRewardsUpdated() then context.refresh() end
        return
    end
    if event == "PLAYER_XP_UPDATE" or event == "PLAYER_ENTERING_WORLD" or event == "QUEST_TURNED_IN" then context.captureXP() end
    if event == "QUEST_TURNED_IN" then context.turnIn(arg, rewardXP) end
    if event == "PLAYER_LOGOUT" then context.saveSession() return end
    if event == "ADDON_LOADED" then context.loaded(arg) return end
    if event == "PLAYER_XP_UPDATE" and context.hasMeasurements() then
        if context.visible() then context.measure() end
        return
    end
    if event == "PLAYER_LEVEL_UP" then context.levelUp(arg) end
    if event == "PLAYER_ENTERING_WORLD" then context.enterWorld() end
    if event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_REGEN_ENABLED" then context.introduction() end
    context.taxi(event)
    if event == "QUEST_REMOVED" then context.removeQuest(arg) end
    context.updateQuestLog()
    context.refresh()
end

function addon.EventController.Bind(frame, context)
    frame:SetScript("OnEvent", function(_, event, ...)
        addon.EventController.Handle(context, event, ...)
    end)
end
