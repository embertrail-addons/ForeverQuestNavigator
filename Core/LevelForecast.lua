local _, addon = ...
-- How many ready turn-ins (nearest first) are needed for the next level.
local Forecast = {}
addon.LevelForecast = Forecast

-- quests: eligible quests; measurements: {[id] = {yards}}; getXP(quest) -> known XP or nil.
-- Returns {count, total, ids} when two or more turn-ins reach the next level, else nil
-- (a single level-up turn-in already has its own forecast line).
function Forecast.FromQuests(quests, measurements, getXP, xpNeeded)
    if type(xpNeeded) ~= "number" or xpNeeded <= 0 then return end
    local ready = {}
    for _, quest in ipairs(quests or {}) do
        if quest.readyToTurnIn then
            local xp = getXP(quest)
            if type(xp) == "number" and xp > 0 then
                local measured = measurements and measurements[quest.id]
                ready[#ready + 1] = {id = quest.id, xp = xp, yards = measured and measured.yards or math.huge}
            end
        end
    end
    table.sort(ready, function(a, b)
        if a.yards ~= b.yards then return a.yards < b.yards end
        return a.id < b.id
    end)
    local total, ids = 0, {}
    for index, entry in ipairs(ready) do
        total = total + entry.xp
        ids[index] = entry.id
        if total >= xpNeeded then
            if index < 2 then return end
            return {count = index, total = total, ids = ids}
        end
    end
end
