local _, addon = ...
addon.QuestItemHints = {}
-- Only the client's explicit quest-action association is authoritative here.
-- Collected objective items and Questie source items are not automatically usable.
function addon.QuestItemHints.Read(api, id, specialItem, itemCount, range)
    if not (api and api.GetLogIndexForQuestID and specialItem and itemCount) then return end
    local ok, index = pcall(api.GetLogIndexForQuestID, id)
    if not ok or type(index) ~= "number" or index < 1 then return end
    local readable, link, texture, _, showComplete = pcall(specialItem, index)
    local itemID = readable and type(link) == "string" and tonumber(link:match("item:(%d+)"))
    if not itemID then return end
    if api.IsComplete and api.IsComplete(id) and not showComplete then return end
    local counted, count = pcall(itemCount, itemID)
    if not counted or type(count) ~= "number" or count < 1 or count ~= count or count == math.huge then return end
    local inRange
    if range then
        local success, value = pcall(range, index)
        if success and (value == true or value == 1) then inRange = true
        elseif success and (value == false or value == 0) then inRange = false end
    end
    return {id = itemID, name = link:match("%[([^%]]+)%]") or tostring(itemID), link = link,
        texture = texture, count = count, logIndex = index, questID = id, inRange = inRange}
end
function addon.QuestItemHints.Cooldown(hint, read, now)
    if not (hint and read) then return 0, 0, 0 end
    local ok, start, duration = pcall(read, hint.logIndex)
    if not ok or type(start) ~= "number" or type(duration) ~= "number" or start ~= start or duration ~= duration
        or start < 0 or duration < 0 or start == math.huge or duration == math.huge then return 0, 0, 0 end
    return start, duration, math.max(0, start + duration - (now or 0))
end

function addon.QuestItemHints.Describe(hint, remaining)
    if not hint then return end
    local L = addon.L
    return L.JourneyUseItem:format(hint.name, hint.count) .. " · "
        .. ((remaining or 0) > 0 and L.JourneyItemCooldown:format(math.ceil(remaining))
            or hint.inRange == true and L.JourneyItemReady or hint.inRange == false and L.QuestItemOutOfRange or L.JourneyItemRangeUnknown)
end
