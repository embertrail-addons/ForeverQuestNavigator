local _, addon = ...
local Finder = {}
addon.QuestFinder = Finder
function Finder.Fold(text)
    return (tostring(text or ""):gsub("[A-Z]", function(letter) return string.char(letter:byte() + 32) end)
        :gsub("Ä", "ä"):gsub("Ö", "ö"):gsub("Ü", "ü"):gsub("ẞ", "ß"))
end
function Finder.Build(quests, offers, skipped, destination)
    local entries, seen = {}, {}
    local function Add(quest, kind, marker, zone)
        if not (quest and quest.id) or seen[quest.id] then return end
        seen[quest.id] = true
        local location = destination and destination(quest.id)
        entries[#entries + 1] = {quest = quest, kind = kind, target = marker or (location and location.target),
            zone = zone or (location and location.zoneName), objectiveZone = quest.objectiveZone}
    end
    for _, quest in ipairs(quests or {}) do Add(quest, skipped and skipped[quest.id] and "skipped" or "active") end
    for _, offer in ipairs(offers or {}) do Add(offer, "offer", offer.marker, offer.pickupZone) end
    for id, entry in pairs(skipped or {}) do
        if not seen[id] then Add(entry.quest or {id = id}, "skipped") end
    end
    table.sort(entries, function(a, b)
        local x, y = Finder.Fold(a.quest.title), Finder.Fold(b.quest.title)
        if x == y then return a.quest.id < b.quest.id end return x < y
    end)
    return entries
end
function Finder.Filter(entries, query, kind)
    local result, text = {}, Finder.Fold(query):sub(1, 160)
    for _, entry in ipairs(entries or {}) do
        local haystack = Finder.Fold((entry.quest.title or "") .. " " .. (entry.zone or "") .. " " .. (entry.objectiveZone or "") .. " " .. entry.quest.id)
        if (not kind or kind == "all" or entry.kind == kind) and haystack:find(text, 1, true) then result[#result + 1] = entry end
    end
    return result
end
