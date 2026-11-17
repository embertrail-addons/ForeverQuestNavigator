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
    data.lowerBound = data.lowerBound == true
    return setmetatable({ data = data, started = now or 0 }, Session)
end

function Session:Save(now)
    self.data.seconds = self.data.seconds + math.max(0, (now or self.started) - self.started)
    self.started = now or self.started
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

function Session:TurnIn(id, title, reward)
    if not Valid(id) or id == 0 then return end
    self.data.completed = self.data.completed + 1
    if Valid(reward) then self.data.questXP = self.data.questXP + reward
    else self.data.unknownRewards = self.data.unknownRewards + 1 end
    table.insert(self.data.recent, 1, { id = id, title = title, xp = Valid(reward) and reward or nil })
    while #self.data.recent > 20 do table.remove(self.data.recent) end
end

function Session:Describe(now)
    local L, data = addon.L, self.data
    local seconds = data.seconds + math.max(0, (now or self.started) - self.started)
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
