local _, addon = ...
local Insights = {}
addon.QuestInsights = Insights
local function Count(value)
    return not (issecretvalue and issecretvalue(value)) and type(value) == "number"
        and value >= 0 and value < math.huge and value == math.floor(value)
end
function Insights.SharedItems(quests, objectives, lookup, inventory, nameFor)
    local byItem, seenQuests = {}, {}
    for _, quest in ipairs(quests or {}) do
        if not seenQuests[quest.id] then
            seenQuests[quest.id] = true
            local seen = {}
            for index, goal in ipairs(objectives(quest.id) or {}) do
                if goal.type == "item" and Count(goal.numRequired) and goal.numRequired > 0 then
                    local id = lookup(quest.id, index)
                    if Count(id) and id > 0 then
                        local item = byItem[id] or {id = id, required = 0, quests = {}}
                        byItem[id] = item
                        if seen[id] then item.ambiguous = true end
                        seen[id] = true
                        item.required = item.required + goal.numRequired
                        item.quests[#item.quests + 1] = {quest = quest, required = goal.numRequired}
                    end
                end
            end
        end
    end
    local result = {}
    for _, item in pairs(byItem) do
        if not item.ambiguous and #item.quests >= 2 then
            local ok, owned = false, nil
            if inventory then ok, owned = pcall(inventory, item.id, false) end
            if ok and Count(owned) then item.owned, item.remaining = owned, math.max(0, item.required - owned) end
            local named, name = false, nil
            if nameFor then named, name = pcall(nameFor, item.id) end
            item.name = named and type(name) == "string" and name or addon.L.RewardItemID:format(item.id)
            result[#result + 1] = item
        end
    end
    table.sort(result, function(a, b) return a.id < b.id end)
    return result
end

function Insights.Chains(mapAPI, mapType, quests, chains, measurements)
    local result = {}
    for _, quest in ipairs(quests or {}) do
        local chain = chains and chains[quest.id]
        local entry = {quest = quest, known = chain ~= nil, targets = {}, detail = {quest.title or addon.L.QuestNumber:format(quest.id)}}
        if chain then
            local names, lastZone, sharedZone = {}, nil, nil
            for depth, title in ipairs(chain.followUps or {}) do
                names[#names + 1] = "-> " .. title
                entry.detail[#entry.detail + 1] = "-> " .. title
                for _, stop in ipairs(chain.stops or {}) do
                    if stop.depth == depth and stop.action == "objective" then
                        local target = {quest = {id = stop.questID, title = stop.title}, target = stop, action = "objective"}
                        entry.targets[#entry.targets + 1] = target
                        if not entry.stop then entry.stop = target end
                        local _, zone = addon.QuestLocation.GetZone(mapAPI, mapType, stop.mapID)
                        lastZone = zone or addon.L.UnknownZone
                        entry.detail[#entry.detail + 1] = addon.L.ChainGoal:format(zone or addon.L.UnknownZone)
                        local metric = addon.QuestLocation.GetDistanceMetric(mapAPI, stop)
                        for _, other in ipairs(quests) do
                            local measured = measurements and measurements[other.id]
                            local target = measured and (measured.objectiveMarker or measured.marker)
                            local gap = metric and target and metric(stop, target)
                            if other.id ~= quest.id and gap and gap <= 40 then
                                sharedZone = lastZone
                                entry.detail[#entry.detail + 1] = addon.L.ChainShared:format(other.title or addon.L.QuestNumber:format(other.id))
                            end
                        end
                    end
                end
            end
            if sharedZone then names[#names + 1] = addon.L.ChainCommonArea:format(sharedZone)
            elseif lastZone then names[#names + 1] = "-> " .. lastZone end
            entry.summary = table.concat(names, " ")
            entry.detail[#entry.detail + 1] = addon.L.ChainForecast
        else entry.detail[#entry.detail + 1] = addon.L.UnknownFollowUps end
        entry.detail = table.concat(entry.detail, "\n")
        result[#result + 1] = entry
    end
    return result
end

function Insights.LevelChanges(quests, before, after)
    local result = {}
    if type(before) ~= "number" or type(after) ~= "number" or after <= before then return result end
    local fit = {red = 1, orange = 2, yellow = 3, green = 2, gray = 0}
    for _, quest in ipairs(quests or {}) do
        if not quest.readyToTurnIn then
            local old = addon.QuestPrioritizer.GetDifficulty(quest, before)
            local new = addon.QuestPrioritizer.GetDifficulty(quest, after)
            if old and new and fit[new] > fit[old] then result[#result + 1] = {quest = quest, before = old, after = new} end
        end
    end
    return result
end
