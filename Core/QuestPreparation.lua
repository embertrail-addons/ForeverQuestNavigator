local _, addon = ...
local Prep = {}
addon.QuestPreparation = Prep
local function Read(db, field, id)
    if not (db and type(db[field]) == "function") then return nil, false end
    local ok, value = pcall(db[field], id)
    return ok and value or nil, ok
end
function Prep.Repeatable(db, api, id)
    local result
    local flags = Read(db, "specialFlags", id)
    if type(flags) == "number" and flags >= 0 and flags < math.huge and flags == math.floor(flags) then result = flags % 2 == 1 end
    if api and api.IsRepeatableQuest then
        local ok, value = pcall(api.IsRepeatableQuest, id)
        if ok and type(value) == "boolean" then result = value end
    end
    return result
end
function Prep.Read(db, api, id, inventory, itemName)
    local result = {items = {}, prerequisites = {}, known = false, repeatable = Prep.Repeatable(db, api, id)}
    local items, known = Read(db, "requiredSourceItems", id)
    result.known = known
    for _, itemID in ipairs(type(items) == "table" and items or {}) do
        if type(itemID) == "number" and itemID > 0 and itemID < math.huge then
            local ok, owned = false, nil
            if inventory then ok, owned = pcall(inventory, itemID, false) end
            local named, name = false, nil
            if itemName then named, name = pcall(itemName, itemID) end
            result.items[#result.items + 1] = {id = itemID, name = named and type(name) == "string" and name or addon.L.RewardItemID:format(itemID),
                owned = ok and type(owned) == "number" and owned >= 0 and owned < math.huge and owned or nil}
        end
    end
    for _, field in ipairs({"preQuestGroup", "preQuestSingle"}) do
        local ids, confirmed = Read(db, field, id)
        result.known = result.known and confirmed
        for _, questID in ipairs(type(ids) == "table" and ids or {}) do
            local ok, done = false, nil
            if api and api.IsQuestFlaggedCompleted then ok, done = pcall(api.IsQuestFlaggedCompleted, questID) end
            local title = Read(db, "name", questID)
            result.prerequisites[#result.prerequisites + 1] = {id = questID, title = type(title) == "string" and title or nil,
                alternative = field == "preQuestSingle", done = ok and done == true}
        end
    end
    for _, field in ipairs({"requiredSkill", "requiredMinRep", "requiredMaxRep", "requiredSpell", "requiredSpecialization"}) do
        local value = Read(db, field, id)
        if type(value) == "table" and next(value) or type(value) == "number" and value > 0 then result.additional = true end
    end
    return result
end
function Prep.Describe(preparation, group)
    local L, lines = addon.L, {}
    if group then lines[#lines + 1] = L.GroupQuest end
    if not preparation then return table.concat(lines, "\n") end
    if preparation.repeatable then lines[#lines + 1] = L.RepeatableQuest end
    for _, item in ipairs(preparation.items) do
        lines[#lines + 1] = L.PreparationItem:format(item.name,
            item.owned == nil and L.PreparationInventoryUnknown or item.owned == 0 and L.PreparationMissing or L.PreparationOwned)
    end
    for _, quest in ipairs(preparation.prerequisites) do
        lines[#lines + 1] = (quest.alternative and L.PreparationAlternative or L.PreparationPrerequisite):format(quest.title or L.QuestNumber:format(quest.id))
            .. " · " .. (quest.done and L.PreparationCompleted or L.PreparationNotConfirmed)
    end
    if preparation.additional then lines[#lines + 1] = L.PreparationAdditional end
    if not preparation.known then lines[#lines + 1] = L.PreparationUnknown end
    return table.concat(lines, "\n")
end

local Policy = {}
addon.RepeatablePolicy = Policy
function Policy.Mode(value) return (value == "level" or value == "hide") and value or "show" end
function Policy.Quests(quests, mode, explicitID)
    local result = {}
    for _, quest in ipairs(quests or {}) do
        if quest.repeatable ~= true or mode == "level" or (mode ~= "hide" and quest.id == explicitID) then result[#result + 1] = quest end
    end
    return result
end
function Policy.Offers(offers, mode)
    local result = {}
    for _, offer in ipairs(offers or {}) do
        offer.informational = offer.repeatable == true and mode ~= "level"
        if offer.levelLowPriority == nil then offer.levelLowPriority = offer.lowPriority == true end
        offer.lowPriority = offer.levelLowPriority or offer.informational
        if not (offer.repeatable and mode == "hide") then result[#result + 1] = offer end
    end
    return result
end
