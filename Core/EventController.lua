local _, addon = ...
addon.EventController = {}
local runtimeEvents = {
    "PLAYER_DEAD",
    "PLAYER_ALIVE",
    "PLAYER_UNGHOST",
    "PLAYER_TARGET_CHANGED",
    "UNIT_THREAT_LIST_UPDATE",
    "UNIT_TARGET",
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
    "CHAT_MSG_ADDON",
    "HEARTHSTONE_BOUND",
    "ADDON_ACTION_BLOCKED",
    "ADDON_ACTION_FORBIDDEN",
}

-- Events that only change bags, gear or mount state: the quest log and markers are
-- unchanged, so a light refresh (items, preparation, distances) is enough.
local itemEvents = {
    BAG_UPDATE_DELAYED = true,
    UPDATE_INVENTORY_DURABILITY = true,
    PLAYER_EQUIPMENT_CHANGED = true,
    PLAYER_MOUNT_DISPLAY_CHANGED = true,
}
addon.EventController.itemEvents = itemEvents

function addon.EventController.RegisterRuntime(frame)
    for _, event in ipairs(runtimeEvents) do frame:RegisterEvent(event) end
end

function addon.EventController.Handle(context, event, payload, rewardXP, ...)
    -- Not named "arg": Lua 5.1 adds an implicit local "arg" to vararg functions.
    if event == "CHAT_MSG_ADDON" then
        -- prefix, text, channel, sender: only group sync reads these; never a refresh by itself.
        if context.addonMessage then context.addonMessage(payload, rewardXP, ...) end
        return
    end
    if event == "PLAYER_TARGET_CHANGED" or event == "UNIT_THREAT_LIST_UPDATE" or event == "UNIT_TARGET" then
        if issecretvalue and issecretvalue(payload) then return end
        if event == "PLAYER_TARGET_CHANGED" or payload == "target" or payload == "player" or payload == "pet" then
            if context.visible() then context.measure() end
        end
        return
    end
    if event == "PLAYER_DEAD" or event == "PLAYER_ALIVE" or event == "PLAYER_UNGHOST" or event == "PLAYER_ENTERING_WORLD" then
        if context.recovery then context.recovery(event) end
    end
    if event == "GET_ITEM_INFO_RECEIVED" then
        if context.itemRewardsUpdated and context.itemRewardsUpdated() then context.refresh() end
        return
    end
    if event == "PLAYER_XP_UPDATE" or event == "PLAYER_ENTERING_WORLD" or event == "QUEST_TURNED_IN" then context.captureXP() end
    if event == "QUEST_TURNED_IN" then context.turnIn(payload, rewardXP) end
    if event == "PLAYER_LOGOUT" then context.saveSession() return end
    if (event == "QUEST_TURNED_IN" or event == "QUEST_ACCEPTED" or event == "QUEST_REMOVED" or event == "QUEST_DATA_LOAD_RESULT")
        and context.questDataChanged then context.questDataChanged() end
    if event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
        if context.actionBlocked then context.actionBlocked(event, payload, rewardXP) end
        return
    end
    if event == "HEARTHSTONE_BOUND" then if context.hearthBound then context.hearthBound() end return end
    if event == "ADDON_LOADED" then context.loaded(payload) return end
    if itemEvents[event] and context.refreshItems then context.refreshItems() return end
    if event == "GROUP_ROSTER_UPDATE" and context.refreshGroup then context.refreshGroup() return end
    if event == "PLAYER_XP_UPDATE" and context.hasMeasurements() then
        if context.visible() then context.measure() end
        return
    end
    if event == "PLAYER_LEVEL_UP" then context.levelUp(payload) end
    if event == "PLAYER_ENTERING_WORLD" then context.enterWorld() end
    if event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_REGEN_ENABLED" then context.introduction() end
    context.taxi(event)
    if event == "QUEST_REMOVED" then context.removeQuest(payload) end
    context.updateQuestLog()
    context.refresh()
end

function addon.EventController.Bind(frame, context)
    frame:SetScript("OnEvent", function(_, event, ...)
        if addon.ErrorLog then addon.ErrorLog.Call(event, addon.EventController.Handle, context, event, ...)
        else addon.EventController.Handle(context, event, ...) end
    end)
end
