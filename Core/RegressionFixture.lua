local _, addon = ...
local Fixture = {}
addon.RegressionFixture = Fixture

local function Pick(source, keys)
    local result = {}
    for _, key in ipairs(keys) do
        local value = source and source[key]
        if type(value) == "boolean" or (type(value) == "number" and value == value and math.abs(value) < math.huge) then result[key] = value end
    end
    return result
end

function Fixture.Capture(quests, snapshot)
    if not snapshot then return end
    local result = { schema = 1, playerLevel = snapshot.playerLevel, quests = {}, previous = {}, expected = {},
        trivialRange = UnitQuestTrivialLevelRange and UnitQuestTrivialLevelRange("player") }
    for _, quest in ipairs(quests or {}) do
        local entry = Pick(quest, { "id", "level", "readyToTurnIn", "elite", "group" })
        entry.progress = Pick(quest.progress, { "nearly", "bonus" })
        entry.measurement = Pick(snapshot.measurements[quest.id], { "yards", "travelYards" })
        entry.adjustment = snapshot.adjustments and snapshot.adjustments[quest.id]
        entry.journey = Pick(snapshot.journeys and snapshot.journeys[quest.id], { "totalYards", "returnYards", "extraYards" })
        result.quests[#result.quests + 1] = entry
    end
    result.hasJourneys = snapshot.journeys ~= nil
    for _, quest in ipairs(snapshot.rankingInputOrder or {}) do result.previous[#result.previous + 1] = quest.id end
    for _, quest in ipairs(snapshot.ranked) do result.expected[#result.expected + 1] = quest.id end
    return result
end

-- This format contains only allowlisted numeric/boolean facts and quest IDs.
-- No character/account names, quest titles, notes, chat or Lua code is exported.
local function JSON(value)
    local kind = type(value)
    if kind == "number" or kind == "boolean" then return tostring(value) end
    if kind ~= "table" then return "null" end
    local entries = {}
    if #value > 0 then
        for _, item in ipairs(value) do entries[#entries + 1] = JSON(item) end
        return "[" .. table.concat(entries, ",") .. "]"
    end
    local keys = {}
    for key in pairs(value) do keys[#keys + 1] = key end
    table.sort(keys)
    for _, key in ipairs(keys) do entries[#entries + 1] = '"' .. key .. '":' .. JSON(value[key]) end
    return "{" .. table.concat(entries, ",") .. "}"
end
Fixture.Encode = JSON

function Fixture.Replay(fixture)
    assert(fixture.schema == 1, "Unsupported fixture version")
    local quests, measurements, journeys, previous, adjustments = {}, {}, {}, {}, {}
    for _, entry in ipairs(fixture.quests) do
        quests[#quests + 1] = entry
        if entry.measurement and entry.measurement.yards then measurements[entry.id] = entry.measurement end
        if entry.journey and entry.journey.totalYards then journeys[entry.id] = entry.journey end
        adjustments[entry.id] = entry.adjustment
    end
    for _, id in ipairs(fixture.previous) do previous[#previous + 1] = { id = id } end
    local ranked = addon.QuestPrioritizer.RankByDistance(quests, measurements, previous, fixture.playerLevel,
        fixture.hasJourneys and journeys or nil, fixture.trivialRange, adjustments)
    assert(#ranked == #fixture.expected, "Quest count changed")
    for index, quest in ipairs(ranked) do
        assert(quest.id == fixture.expected[index], "Ranking changed at position " .. index)
    end
    return true
end
