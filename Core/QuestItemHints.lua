local _, addon = ...
addon.QuestItemHints = {}
-- Only the client's explicit quest-action association is authoritative here.
-- Collected objective items and Questie source items are not automatically usable.
function addon.QuestItemHints.Read(api, id, specialItem, itemCount)
    if not (api and api.GetLogIndexForQuestID and specialItem and itemCount) then return end
    local ok, index = pcall(api.GetLogIndexForQuestID, id)
    if not ok or type(index) ~= "number" or index < 1 then return end
    local readable, link, _, _, showComplete = pcall(specialItem, index)
    local itemID = readable and type(link) == "string" and tonumber(link:match("item:(%d+)"))
    if not itemID then return end
    if api.IsComplete and api.IsComplete(id) and not showComplete then return end
    local counted, count = pcall(itemCount, itemID)
    if not counted or type(count) ~= "number" or count < 1 then return end
    return {id = itemID, name = link:match("%[([^%]]+)%]") or tostring(itemID)}
end
