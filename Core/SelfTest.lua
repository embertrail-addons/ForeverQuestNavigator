local _, addon = ...
-- /fqn selftest: checks in the real client that every game interface FQN uses
-- exists, so a missing API shows up as a clear line instead of a silent gap.
local SelfTest = {}
addon.SelfTest = SelfTest

local function Path(env, path)
    local value = env
    for part in path:gmatch("[^%.]+") do
        if type(value) ~= "table" then return nil end
        value = value[part]
    end
    return value
end

-- {label, path, required}: required interfaces break core navigation when missing.
SelfTest.interfaces = {
    {"Quest log", "C_QuestLog.GetInfo", true}, {"Quest log entries", "C_QuestLog.GetNumQuestLogEntries", true},
    {"Quest objectives", "C_QuestLog.GetQuestObjectives", true}, {"On quest", "C_QuestLog.IsOnQuest", true},
    {"Map of player", "C_Map.GetBestMapForUnit", true}, {"Player position", "C_Map.GetPlayerMapPosition", true},
    {"Map info", "C_Map.GetMapInfo", true}, {"World coordinates", "C_Map.GetWorldPosFromMapPos", false},
    {"Timers", "C_Timer.NewTicker", true}, {"Facing", "GetPlayerFacing", false},
    {"Taxi nodes", "C_TaxiMap.GetAllTaxiNodes", false}, {"Taxi map", "GetTaxiMapID", false}, {"On taxi", "UnitOnTaxi", false},
    {"Corpse position", "C_DeathInfo.GetCorpseMapPosition", false},
    {"Quest items", "GetQuestLogSpecialItemInfo", false}, {"Quest XP", "GetQuestLogRewardXP", false},
    {"Addon messages", "C_ChatInfo.SendAddonMessage", false}, {"Addon prefix", "C_ChatInfo.RegisterAddonMessagePrefix", false},
    {"Group", "IsInGroup", false}, {"Server time", "GetServerTime", false}, {"Zone name", "GetRealZoneText", false},
    {"Context menus", "MenuUtil.CreateContextMenu", false}, {"Settings panel", "Settings.RegisterAddOnSetting", false},
    {"World map", "WorldMapFrame", false}, {"Minimap", "Minimap", false},
}

-- env: global table (_G in game). state: optional runtime facts from the navigator.
function SelfTest.Run(env, state)
    local L, results, failures, warnings = addon.L, {}, 0, 0
    local function Add(ok, required, label, detail)
        local mark = ok and "OK" or required and "MISSING" or "missing (optional)"
        if not ok then if required then failures = failures + 1 else warnings = warnings + 1 end end
        results[#results + 1] = ("%s · %s%s"):format(mark, label, detail and (" · " .. detail) or "")
    end
    for _, entry in ipairs(SelfTest.interfaces) do
        local value = Path(env, entry[2])
        Add(value ~= nil, entry[3], entry[1], entry[2])
    end
    local map = Path(env, "WorldMapFrame")
    local canvas = type(map) == "table" and map.GetCanvas and map:GetCanvas() or nil
    Add(type(canvas) == "table" and canvas.CreateLine ~= nil, false, "Route line on map canvas")
    local loader = Path(env, "QuestieLoader")
    local questie = type(loader) == "table" and loader.ImportModule or nil
    Add(questie ~= nil, false, "Questie", questie and "loaded" or "not loaded")
    if questie then
        local ok, module = pcall(loader.ImportModule, loader, "QuestieMap")
        Add(ok and type(module) == "table" and module.questIdFrames ~= nil, false, "Questie map pins")
        local dbOk, db = pcall(loader.ImportModule, loader, "QuestieDB")
        Add(dbOk and type(db) == "table" and db.QueryQuestSingle ~= nil, false, "QuestieDB quest queries")
    end
    state = state or {}
    local lines = {L.SelfTestTitle, ("version=%s · client=%s · locale=%s"):format(tostring(state.version or "?"),
        tostring(state.build or "?"), tostring(state.locale or "?"))}
    if state.mapID ~= nil then lines[#lines + 1] = ("map=%s · position=%s · quests=%s"):format(tostring(state.mapID),
        tostring(state.position == true), tostring(state.quests or "?")) end
    lines[#lines + 1] = L.SelfTestSummary:format(#results - failures - warnings, failures, warnings)
    lines[#lines + 1] = ""
    for _, line in ipairs(results) do lines[#lines + 1] = line end
    if addon.ErrorLog then
        lines[#lines + 1] = ""
        for _, line in ipairs(addon.ErrorLog.Summary()) do lines[#lines + 1] = line end
    end
    return table.concat(lines, "\n"), failures, warnings
end
