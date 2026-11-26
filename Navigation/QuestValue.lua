local _, addon = ...
-- What a quest is worth, not only how far away it is. Adds bounded adjustments (in
-- yards, like every other ranking input) on top of distance and level fit:
--   * XP per minute: travel, remaining work and the way to the turn-in become an
--     estimated time; quests with a better rate than the others rank earlier.
--   * look-ahead: a quest whose end point lies close to the next quest ranks earlier.
--   * follow-ups: quests with known follow-up quests ranks a little earlier.
--   * finish the zone: the last few quests on the current map rank a little earlier.
--   * learned preference: kill / collect / other, from the player's manual choices.
-- The model (travel speed, minutes per kill or item, preferences) is learned per
-- character from real play and stays bounded; /fqn learn reset clears it.
local Value = {}
addon.QuestValue = Value

Value.DEFAULT_SPEED = 420        -- yards per minute (about running speed)
Value.DEFAULT_UNIT_MINUTES = .6  -- minutes per remaining kill or item
Value.OTHER_MINUTES = 1.5        -- minutes per remaining other objective
Value.UNKNOWN_WORK = 3           -- minutes when progress is unknown
Value.PREFERENCE_LIMIT = 60

-- finish marker -> other marker -> yards; weak keys let replaced markers be collected.
local pairCache = setmetatable({}, {__mode = "k"})
local function CachedDistance(distance, from, to)
    local row = pairCache[from]
    if not row then row = setmetatable({}, {__mode = "k"}) pairCache[from] = row end
    local value = row[to]
    if value == nil then value = distance(from, to) or false row[to] = value end
    return value or nil
end

local function Clamp(value, low, high) return math.max(low, math.min(high, value)) end

local function Median(values)
    if #values == 0 then return end
    table.sort(values)
    local middle = math.floor((#values + 1) / 2)
    return #values % 2 == 1 and values[middle] or (values[middle] + values[middle + 1]) / 2
end

-- saved: the character's stored model table (created if missing).
function Value.Model(saved)
    saved = saved or {}
    saved.speed = type(saved.speed) == "number" and Clamp(saved.speed, 150, 2400) or Value.DEFAULT_SPEED
    saved.unitMinutes = type(saved.unitMinutes) == "number" and Clamp(saved.unitMinutes, .2, 3) or Value.DEFAULT_UNIT_MINUTES
    saved.prefer = type(saved.prefer) == "table" and saved.prefer or {}
    for _, kind in ipairs({"kill", "collect", "other"}) do
        local value = saved.prefer[kind]
        saved.prefer[kind] = type(value) == "number" and Clamp(value, -Value.PREFERENCE_LIMIT, Value.PREFERENCE_LIMIT) or 0
    end
    return saved
end

function Value.Reset(saved)
    for key in pairs(saved) do saved[key] = nil end
    return Value.Model(saved)
end

-- Main kind of remaining work, from QuestTools.Progress.
function Value.Kind(quest)
    local p = quest and quest.progress
    if not p then return "other" end
    local monsters, items, other = p.monsters or 0, p.items or 0, p.other or 0
    if monsters > 0 and monsters >= items and monsters >= other then return "kill" end
    if items > 0 and items >= other then return "collect" end
    return "other"
end

-- Estimated minutes to finish and hand in: travel (with the way to the turn-in when known) plus work.
function Value.Minutes(quest, measured, journey, model)
    -- Without a known turn-in the way back is assumed as long as the way there, so quests
    -- with and without known turn-ins are compared on equal terms.
    local approach = addon.QuestPrioritizer.TravelDistance(measured)
    local yards = journey and journey.totalYards or (type(approach) == "number" and approach * 2)
    if type(yards) ~= "number" then return end
    local p, work = quest.progress, Value.UNKNOWN_WORK
    if p then work = ((p.monsters or 0) + (p.items or 0)) * model.unitMinutes + (p.other or 0) * Value.OTHER_MINUTES end
    return yards / model.speed + work
end

-- context: quests, measurements, journeys, model, xp(quest), distance(a, b), playerMap, chains
-- returns adjustments[id] (negative = earlier) and factors[id] for explanations.
function Value.Adjustments(context)
    local adjustments, factors = {}, {}
    local model, measurements, journeys = context.model, context.measurements or {}, context.journeys or {}
    local function Add(id, delta, key, value)
        adjustments[id] = (adjustments[id] or 0) + delta
        factors[id] = factors[id] or {}
        if key then factors[id][key] = value end
    end
    local open = {}
    for _, quest in ipairs(context.quests or {}) do
        if not quest.readyToTurnIn and measurements[quest.id] then open[#open + 1] = quest end
    end
    -- XP per minute relative to the median of the other open quests.
    local rates, values = {}, {}
    for _, quest in ipairs(open) do
        local xp = context.xp and context.xp(quest)
        local minutes = xp and Value.Minutes(quest, measurements[quest.id], journeys[quest.id], model)
        if minutes and minutes > 0 then
            rates[quest.id] = xp / minutes
            values[#values + 1] = rates[quest.id]
        end
    end
    local median = #values >= 2 and Median(values)
    for _, quest in ipairs(open) do
        local rate = rates[quest.id]
        if rate then
            -- Log scale: twice the median rate is worth about 120 yards, half of it costs as much.
            local delta = median and median > 0 and rate > 0 and -Clamp(math.log(rate / median) / math.log(2) * 120, -150, 200) or 0
            Add(quest.id, delta, "xpPerMinute", math.floor(rate + .5))
        end
    end
    -- Look-ahead: distance from this quest's end point (turn-in when known) to the nearest other quest.
    if context.distance and #open >= 3 then
        local nearest = {}
        for _, quest in ipairs(open) do nearest[#nearest + 1] = quest end
        table.sort(nearest, function(a, b) return measurements[a.id].yards < measurements[b.id].yards end)
        local next, nextValues = {}, {}
        local limit = math.min(8, #nearest)
        for index = 1, limit do
            local quest = nearest[index]
            local journey = journeys[quest.id]
            local finish = journey and journey.finisher or measurements[quest.id].marker
            local best
            for otherIndex = 1, limit do
                local other = nearest[otherIndex]
                if other ~= quest then
                    local yards = CachedDistance(context.distance, finish, measurements[other.id].marker)
                    if yards and (not best or yards < best) then best = yards end
                end
            end
            if best then next[quest.id] = best nextValues[#nextValues + 1] = best end
        end
        local middle = Median(nextValues)
        for id, yards in pairs(next) do Add(id, Clamp((yards - middle) * .2, -50, 50), "nextYards", math.floor(yards + .5)) end
    end
    -- Known follow-up quests.
    for _, quest in ipairs(open) do
        local chain = context.chains and context.chains[quest.id]
        local count = chain and chain.followUps and #chain.followUps or 0
        if count > 0 then Add(quest.id, -math.min(60, 30 * count), "followUps", count) end
    end
    -- Finish the zone: the last one to three open quests on the current map, when others wait elsewhere.
    if context.playerMap then
        local here, elsewhere = {}, false
        for _, quest in ipairs(open) do
            local marker = measurements[quest.id].marker
            if marker and marker.mapID == context.playerMap then here[#here + 1] = quest
            elseif marker and marker.mapID then elsewhere = true end
        end
        if elsewhere and #here >= 1 and #here <= 3 then
            for _, quest in ipairs(here) do Add(quest.id, -40, "finishZone", #here) end
        end
    end
    -- Finish what is nearly done: the last one to three kills or items of a quest.
    for _, quest in ipairs(open) do
        local p = quest.progress
        if p and p.nearly then Add(quest.id, -120, "finishNearly", p.remaining) end
    end
    -- Mobs that count for several open quests at once (kill one, progress two).
    for _, quest in ipairs(open) do
        local count = context.shared and context.shared[quest.id]
        if count and count > 0 then Add(quest.id, -math.min(60, 30 * count), "sharedMobs", count) end
    end
    -- Learned preference for the kind of work.
    for _, quest in ipairs(open) do
        local preference = model.prefer[Value.Kind(quest)] or 0
        if preference ~= 0 then Add(quest.id, -preference, "learned", preference) end
    end
    return adjustments, factors
end

---------------------------------------------------------------------------------------
-- Learning from real play (all bounded, slow moving averages).

-- Travel speed: how fast the distance to the target shrinks while approaching it.
function Value.ObserveSpeed(model, state, questID, yards, now)
    local last = state.lastSample
    state.lastSample = {id = questID, yards = yards, at = now}
    if not (last and last.id == questID and type(yards) == "number" and type(last.yards) == "number") then return end
    local seconds = now - last.at
    if seconds < .5 or seconds > 5 then return end
    local perSecond = (last.yards - yards) / seconds
    if perSecond < 3 or perSecond > 40 then return end
    model.speed = Clamp(model.speed * .98 + perSecond * 60 * .02, 150, 2400)
    return model.speed
end

-- Work speed: minutes per kill or item from quests that went from open to finished.
-- state.tracked[id] = {at, units} when first seen open; samples older than 45 minutes are ignored.
function Value.ObserveEffort(model, state, quests, now)
    state.tracked = state.tracked or {}
    local present = {}
    for _, quest in ipairs(quests or {}) do
        present[quest.id] = true
        local p = quest.progress
        local units = p and ((p.monsters or 0) + (p.items or 0)) or 0
        local tracked = state.tracked[quest.id]
        if quest.readyToTurnIn then
            if tracked and tracked.units > 0 then
                local minutes = (now - tracked.at) / 60
                if minutes > 0 and minutes <= 45 then
                    local sample = Clamp(minutes / tracked.units, .2, 3)
                    model.unitMinutes = Clamp(model.unitMinutes * .8 + sample * .2, .2, 3)
                end
            end
            state.tracked[quest.id] = nil
        elseif not tracked and units > 0 then
            state.tracked[quest.id] = {at = now, units = units}
        end
    end
    for id in pairs(state.tracked) do if not present[id] then state.tracked[id] = nil end end
end

-- Manual choice against the recommendation: the chosen kind gains, the skipped kind loses a little.
function Value.LearnChoice(model, chosen, recommended)
    if not (chosen and recommended) or chosen.id == recommended.id or chosen.readyToTurnIn or recommended.readyToTurnIn then return end
    local picked, skipped = Value.Kind(chosen), Value.Kind(recommended)
    if picked == skipped then return end
    for kind, value in pairs(model.prefer) do
        if kind ~= picked and kind ~= skipped and value ~= 0 then model.prefer[kind] = value - (value > 0 and 1 or -1) end
    end
    model.prefer[picked] = Clamp((model.prefer[picked] or 0) + 8, -Value.PREFERENCE_LIMIT, Value.PREFERENCE_LIMIT)
    model.prefer[skipped] = Clamp((model.prefer[skipped] or 0) - 4, -Value.PREFERENCE_LIMIT, Value.PREFERENCE_LIMIT)
    return picked, skipped
end

---------------------------------------------------------------------------------------
-- Explanation: "~650 XP/min · next step close · 2 follow-ups" for the tooltip.
function Value.Explain(factors, L)
    if not factors then return end
    local parts = {}
    if factors.xpPerMinute then parts[#parts + 1] = L.WhyXPPerMinute:format(factors.xpPerMinute) end
    if factors.nextYards and factors.nextYards <= 150 then parts[#parts + 1] = L.WhyNextClose end
    if factors.followUps then parts[#parts + 1] = (factors.followUps == 1 and L.WhyFollowUp or L.WhyFollowUps:format(factors.followUps)) end
    if factors.finishZone then parts[#parts + 1] = L.WhyFinishZone end
    if factors.finishNearly then parts[#parts + 1] = L.WhyFinishNearly end
    if factors.sharedMobs then parts[#parts + 1] = L.WhySharedMobs end
    if factors.learned and factors.learned > 0 then parts[#parts + 1] = L.WhyLearned end
    return #parts > 0 and table.concat(parts, " · ") or nil
end

-- Why the shown quest beats the runner-up: "Before 'Wolves': 650 vs 300 XP/min · next step closer".
function Value.Compare(mine, other, otherTitle, L)
    if not (mine and other and otherTitle) then return end
    local parts = {}
    if mine.xpPerMinute and other.xpPerMinute and mine.xpPerMinute >= other.xpPerMinute * 1.2 then
        parts[#parts + 1] = L.CompareXP:format(mine.xpPerMinute, other.xpPerMinute)
    end
    if mine.nextYards and other.nextYards and mine.nextYards + 50 <= other.nextYards then parts[#parts + 1] = L.CompareNext end
    if (mine.followUps or 0) > (other.followUps or 0) then parts[#parts + 1] = L.CompareFollowUp end
    if mine.finishZone and not other.finishZone then parts[#parts + 1] = L.WhyFinishZone end
    if #parts == 0 then return end
    return L.CompareBefore:format(otherTitle, table.concat(parts, " · "))
end
