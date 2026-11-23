local _, addon = ...
local Session = {}
Session.__index = Session
addon.Session = Session

local function Valid(value)
    return not (issecretvalue and issecretvalue(value)) and type(value) == "number"
        and value >= 0 and value < math.huge
end

function Session.New(data, now)
    data = type(data) == "table" and data or {}
    for _, key in ipairs({ "seconds", "xp", "questXP", "completed", "levels", "unknownRewards" }) do
        data[key] = Valid(data[key]) and data[key] or 0
    end
    data.recent = type(data.recent) == "table" and data.recent or {}
    local recent = {}
    for _, entry in ipairs(data.recent) do
        if type(entry) == "table" and Valid(entry.id) and entry.id > 0 then
            recent[#recent + 1] = { id = entry.id, title = type(entry.title) == "string" and entry.title or nil,
                xp = Valid(entry.xp) and entry.xp or nil, zone = type(entry.zone) == "string" and entry.zone or nil,
                at = Valid(entry.at) and entry.at or nil }
            if #recent == 20 then break end
        end
    end
    data.recent = recent
    data.lowerBound = data.lowerBound == true
    -- Turn-ins per zone for the recap: {[zone] = {quests = n, xp = n}}.
    local zones = {}
    for zone, entry in pairs(type(data.zones) == "table" and data.zones or {}) do
        if type(zone) == "string" and type(entry) == "table" and Valid(entry.quests) then
            zones[zone] = {quests = entry.quests, xp = Valid(entry.xp) and entry.xp or 0}
        end
    end
    data.zones = zones
    data.lastActive = Valid(data.lastActive) and data.lastActive or nil
    return setmetatable({ data = data, started = now or 0 }, Session)
end

-- clock: wall-clock seconds (GetServerTime), remembered to detect a returning player.
function Session:Save(now, clock)
    self.data.seconds = self.data.seconds + math.max(0, (now or self.started) - self.started)
    self.started = now or self.started
    if Valid(clock) then self.data.lastActive = clock end
end

function Session:CaptureXP(level, xp, maximum)
    if not (Valid(level) and Valid(xp) and Valid(maximum)) then return end
    local previous = self.last
    if previous then
        -- XP can roll over before UnitLevel reflects the new level. Retain
        -- the old baseline until the level change arrives instead of losing XP.
        if level == previous.level and xp < previous.xp then return end
        local delta
        if level == previous.level and xp >= previous.xp then delta = xp - previous.xp end
        if level > previous.level and previous.maximum >= previous.xp then
            delta = previous.maximum - previous.xp + xp
            self.data.levels = self.data.levels + level - previous.level
            if level > previous.level + 1 then self.data.lowerBound = true end
        end
        if delta then self.data.xp = self.data.xp + delta end
    end
    self.last = { level = level, xp = xp, maximum = maximum }
end

function Session:TurnIn(id, title, reward, zone, clock)
    if not Valid(id) or id == 0 then return end
    self.data.completed = self.data.completed + 1
    if Valid(reward) then self.data.questXP = self.data.questXP + reward
    else self.data.unknownRewards = self.data.unknownRewards + 1 end
    zone = type(zone) == "string" and zone ~= "" and zone or nil
    if zone then
        local entry = self.data.zones[zone] or {quests = 0, xp = 0}
        entry.quests, entry.xp = entry.quests + 1, entry.xp + (Valid(reward) and reward or 0)
        self.data.zones[zone] = entry
    end
    table.insert(self.data.recent, 1, { id = id, title = title, xp = Valid(reward) and reward or nil, zone = zone,
        at = Valid(clock) and clock or nil })
    while #self.data.recent > 20 do table.remove(self.data.recent) end
end

function Session:Describe(now)
    local L, data = addon.L, self.data
    local seconds = self:Elapsed(now)
    local xp = data.lowerBound and L.SessionXPLowerBound or L.SessionXP
    local lines = { L.SessionTime:format(math.floor(seconds / 3600), math.floor(seconds / 60) % 60),
        L.SessionQuests:format(data.completed), xp:format(data.xp), L.SessionQuestXP:format(data.questXP),
        L.SessionLevels:format(data.levels) }
    if data.unknownRewards > 0 then lines[#lines + 1] = L.SessionUnknownRewards:format(data.unknownRewards) end
    if #data.recent > 0 then lines[#lines + 1] = "\n" .. L.SessionRecent end
    for _, entry in ipairs(data.recent) do
        if type(entry) == "table" and Valid(entry.id) then
            local title = type(entry.title) == "string" and entry.title or L.QuestNumber:format(entry.id)
            lines[#lines + 1] = title .. " · " .. (Valid(entry.xp) and L.SessionReward:format(entry.xp) or L.UnknownXP)
        end
    end
    return table.concat(lines, "\n")
end

-- Numbers for the recap. XP per hour needs at least five minutes of play time.
function Session:Summary(now)
    local data, seconds = self.data, self:Elapsed(now)
    local topZone, topCount
    for zone, entry in pairs(data.zones) do
        if not topCount or entry.quests > topCount or (entry.quests == topCount and zone < topZone) then
            topZone, topCount = zone, entry.quests
        end
    end
    return {seconds = seconds, quests = data.completed, xp = data.xp, questXP = data.questXP, levels = data.levels,
        xpPerHour = seconds >= 300 and math.floor(data.xp * 3600 / seconds + .5) or nil,
        topZone = topZone, topZoneQuests = topCount}
end

function Session:Recap(now, suggestion)
    local L, summary = addon.L, self:Summary(now)
    local lines = {L.RecapHeadline:format(summary.quests, summary.xp, math.floor(summary.seconds / 3600),
        math.floor(summary.seconds / 60) % 60)}
    if summary.xpPerHour then lines[#lines + 1] = L.RecapRate:format(summary.xpPerHour) end
    if summary.levels > 0 then lines[#lines + 1] = L.RecapLevels:format(summary.levels) end
    if summary.topZone then lines[#lines + 1] = L.RecapZone:format(summary.topZone, summary.topZoneQuests) end
    if suggestion then lines[#lines + 1] = L.RecapNext:format(suggestion) end
    return table.concat(lines, "\n")
end

-- A returning player (inactive for `gap` seconds) with progress gets a short recap.
function Session:ShouldOfferRecap(clock, gap)
    local last = self.data.lastActive
    return Valid(clock) and last ~= nil and clock - last >= (gap or 1800) and self.data.completed > 0
end

function Session:Elapsed(now)
    return math.floor(self.data.seconds + math.max(0, (now or self.started) - self.started))
end
