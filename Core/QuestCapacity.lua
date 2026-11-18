local _, addon = ...
addon.QuestCapacity = {}
local function Count(value)
    return not (issecretvalue and issecretvalue(value)) and type(value) == "number"
        and value >= 0 and value < math.huge and value == math.floor(value)
end
function addon.QuestCapacity.FromCount(used, api, maximumFallback)
    local maximum = maximumFallback
    if api and api.GetMaxNumQuestsCanAccept then
        local readable, value = pcall(api.GetMaxNumQuestsCanAccept)
        if readable then maximum = value end
    end
    if not Count(used) or not Count(maximum) or maximum < 1 or used > maximum then return end
    return { used = used, maximum = maximum, free = maximum - used, full = used == maximum }
end
function addon.QuestCapacity.Read(api, maximumFallback)
    if not (api and api.GetNumQuestLogEntries) then return end
    local ok, _, used = pcall(api.GetNumQuestLogEntries)
    if ok then return addon.QuestCapacity.FromCount(used, api, maximumFallback) end
end

-- Follow-ups are sequential: a turn-in frees a slot before its successor.
-- Reserve one slot for the next known accept, never one per forecasted step.
function addon.QuestCapacity.WithReserve(capacity, chains)
    if not capacity then return end
    local result = {}
    for key, value in pairs(capacity) do result[key] = value end
    local known
    for _, chain in pairs(chains or {}) do
        for _, stop in ipairs(chain.stops or {}) do
            if stop.action == "accept" then known = true break end
        end
        if known then break end
    end
    result.reserve = known and 1 or 0
    result.reserveNeeded = known and capacity.free <= 1 or false
    return result
end
