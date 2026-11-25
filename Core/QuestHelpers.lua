local _, addon = ...
-- Small pure helpers for the quest-help features: respawn estimate, bag check,
-- turn-in collector, hearthstone suggestion, sounds and per-character profiles.
-- Game APIs are passed in, so everything here is testable without the client.

---------------------------------------------------------------------------------------
-- Respawn: open-world mobs in Classic come back after roughly five minutes. Without a
-- visible living mob of that name, the oldest recent kill gives the next respawn.
local Respawn = {SECONDS = 300}
addon.Respawn = Respawn

function Respawn.New() return {kills = {}} end

function Respawn.Killed(state, name, now)
    if type(name) ~= "string" then return end
    local list = state.kills[name] or {}
    list[#list + 1] = now
    while #list > 20 do table.remove(list, 1) end
    state.kills[name] = list
end

-- Seconds until the next expected respawn, or nil (no kills, or all old kills are back).
function Respawn.Remaining(state, name, now)
    local list = state.kills[name]
    if not list then return end
    while list[1] and now - list[1] >= Respawn.SECONDS do table.remove(list, 1) end
    if not list[1] then state.kills[name] = nil return end
    return Respawn.SECONDS - (now - list[1])
end

---------------------------------------------------------------------------------------
-- Bag check before a tour: free slots against what the tour may bring in.
local Bags = {}
addon.BagCheck = Bags

-- api: {free(bag) -> count, slots(bag) -> count, item(bag, slot) -> {quality, link}}
function Bags.Free(api)
    local free = 0
    for bag = 0, 4 do free = free + (api.free(bag) or 0) end
    return free
end

function Bags.Junk(api, limit)
    local junk = {}
    for bag = 0, 4 do
        for slot = 1, api.slots(bag) or 0 do
            local info = api.item(bag, slot)
            if info and info.quality == 0 and info.link then
                junk[#junk + 1] = info.link
                if #junk >= (limit or 5) then return junk end
            end
        end
    end
    return junk
end

-- Every non-turn-in stop can add an item stack; a small reserve covers rewards.
function Bags.Needed(stops)
    local needed = 2
    for _, stop in ipairs(stops or {}) do if stop.action ~= "turnIn" then needed = needed + 1 end end
    return math.min(needed, 12)
end

function Bags.Check(api, stops, L)
    local free, needed = Bags.Free(api), Bags.Needed(stops)
    if free >= needed then return end
    local junk = Bags.Junk(api, 5)
    local text = L.BagCheckLow:format(free, needed)
    if #junk > 0 then text = text .. " " .. L.BagCheckJunk:format(table.concat(junk, " ")) end
    return text
end

---------------------------------------------------------------------------------------
-- Turn-in collector: tells once when enough ready turn-ins wait close together.
local Collector = {THRESHOLD = 3, RADIUS = 250, MIN_DISTANCE = 150, YARDS_PER_MINUTE = 420}
addon.TurnInCollector = Collector

-- ranked: quests; measurements[id] = {yards, marker}; distance(a, b) -> yards or nil.
function Collector.Check(state, ranked, measurements, distance, L)
    local ready = {}
    for _, quest in ipairs(ranked or {}) do
        local measured = quest.readyToTurnIn and measurements and measurements[quest.id]
        if measured and measured.yards and measured.marker then ready[#ready + 1] = {quest = quest, measured = measured} end
    end
    table.sort(ready, function(a, b) return a.measured.yards < b.measured.yards end)
    local nearest = ready[1]
    if not nearest then state.key = nil return end
    local cluster, ids = {}, {}
    for _, entry in ipairs(ready) do
        local gap = entry == nearest and 0 or distance(nearest.measured.marker, entry.measured.marker)
        if gap and gap <= Collector.RADIUS then cluster[#cluster + 1] = entry ids[#ids + 1] = entry.quest.id end
    end
    if #cluster < Collector.THRESHOLD or nearest.measured.yards < Collector.MIN_DISTANCE then return end
    table.sort(ids)
    local key = table.concat(ids, ",")
    if state.key == key then return end
    state.key = key
    local minutes = math.max(1, math.ceil(nearest.measured.yards / Collector.YARDS_PER_MINUTE))
    return L.TurnInCollector:format(#cluster, minutes)
end

---------------------------------------------------------------------------------------
-- Hearthstone: worth it when several ready turn-ins wait near the inn and the player is far away.
local Hearth = {ITEM = 6948, NEAR = 300, FAR = 1500, MINIMUM = 2}
addon.HearthHint = Hearth

-- turnIns: list of {quest, marker}; distance(a, b) -> yards or nil (nil = other continent).
function Hearth.Suggest(state, hearth, turnIns, playerDistance, ready, distance, L)
    if not (hearth and ready) then state.key = nil return end
    if playerDistance and playerDistance < Hearth.FAR then return end
    local near = {}
    for _, entry in ipairs(turnIns or {}) do
        local gap = distance(hearth, entry.marker)
        if gap and gap <= Hearth.NEAR then near[#near + 1] = entry.quest.id end
    end
    if #near < Hearth.MINIMUM then return end
    table.sort(near)
    local key = table.concat(near, ",")
    if state.key == key then return end
    state.key = key
    return L.HearthHint:format(#near, hearth.name or L.HearthInn)
end

---------------------------------------------------------------------------------------
-- Sounds: an objective of the shown quest finished, or the recommendation changed by itself.
local Sounds = {}
addon.QuestSounds = Sounds

function Sounds.Check(state, questID, finished, manual)
    local previous, before = state.questID, state.finished
    state.questID, state.finished = questID, finished
    if not previous or not questID then return end
    if previous == questID then
        if finished and before and finished > before then return "objective" end
    elseif not manual then
        return "change"
    end
end

---------------------------------------------------------------------------------------
-- Per-character profile: these appearance keys can differ between characters.
local Profile = {KEYS = {"simpleNavigator", "displayMode", "hidden", "detailMode", "navigatorView", "navigatorLayout",
    "theme", "fontPercent", "trackerWidth", "trackerMaxHeight", "opacityPercent", "highContrast", "reducedColors",
    "collapsed", "compactBar", "showScreenArrow", "showDirectionArrow"}}
addon.CharacterProfile = Profile

local function Copy(settings)
    local copy = {}
    for _, key in ipairs(Profile.KEYS) do copy[key] = settings[key] end
    return copy
end

-- Load: remember the account values, then use the character's own ones.
function Profile.Apply(settings, character)
    if not (character and character.ownProfile) then return end
    character.profile = character.profile or Copy(settings)
    local account = Copy(settings)
    for _, key in ipairs(Profile.KEYS) do settings[key] = character.profile[key] end
    return account
end

-- Logout: store the character's values and put the account values back for other characters.
function Profile.Store(settings, character, account)
    if not (character and character.ownProfile and account) then return end
    character.profile = Copy(settings)
    for _, key in ipairs(Profile.KEYS) do settings[key] = account[key] end
end
