local _, addon = ...
-- Optional group sync (setting groupSync, on by default). Shares only quest IDs,
-- objective progress counts and the current target quest with the own party/raid
-- via addon messages. Nothing is saved; data from a member is dropped when they
-- leave the group. Format (plain text): "1|<targetID>|<id>:<done>:<total>,..."
local Sync = {PREFIX = "FQN1", VERSION = "1", MAX_BYTES = 250, MAX_QUESTS = 40, INTERVAL = 3,
    peers = {}, lastSent = nil, dirty = false}
addon.GroupSync = Sync

local function Integer(text, minimum, maximum)
    local value = tonumber(text)
    if not value or value % 1 ~= 0 or value < minimum or value > maximum then return end
    return value
end

-- state = {target = questID or nil, quests = {{id, done, total}, ...}}
function Sync.Encode(state)
    local parts = {}
    local text = Sync.VERSION .. "|" .. tostring(state.target or 0) .. "|"
    for _, quest in ipairs(state.quests or {}) do
        if #parts >= Sync.MAX_QUESTS then break end
        local part = ("%d:%d:%d"):format(quest.id, quest.done or 0, quest.total or 0)
        local candidate = text .. table.concat(parts, ",") .. (#parts > 0 and "," or "") .. part
        if #candidate > Sync.MAX_BYTES then break end
        parts[#parts + 1] = part
    end
    return text .. table.concat(parts, ",")
end

-- Strict parser: anything unexpected rejects the whole message.
function Sync.Decode(message)
    if type(message) ~= "string" or #message > Sync.MAX_BYTES then return end
    local version, target, list = message:match("^(%d+)|(%d+)|([%d:,]*)$")
    if version ~= Sync.VERSION then return end
    local state = {target = Integer(target, 0, 10000000), quests = {}}
    if not state.target then return end
    if state.target == 0 then state.target = nil end
    if list ~= "" then
        for part in (list .. ","):gmatch("([^,]*),") do
            local id, done, total = part:match("^(%d+):(%d+):(%d+)$")
            id, done, total = Integer(id, 1, 10000000), Integer(done, 0, 99), Integer(total, 0, 99)
            if not (id and done and total) or done > total then return end
            if #state.quests >= Sync.MAX_QUESTS then return end
            state.quests[#state.quests + 1] = {id = id, done = done, total = total}
        end
    end
    return state
end

-- Own state from the quest log: objectives finished / total per quest.
function Sync.Collect(quests, questLog, target)
    local state = {target = target, quests = {}}
    for _, quest in ipairs(quests or {}) do
        local goals = questLog and questLog.GetQuestObjectives and questLog.GetQuestObjectives(quest.id)
        local done, total = 0, 0
        for _, goal in ipairs(type(goals) == "table" and goals or {}) do
            total = total + 1
            if goal.finished then done = done + 1 end
        end
        if quest.readyToTurnIn then done = total end
        state.quests[#state.quests + 1] = {id = quest.id, done = math.min(done, 99), total = math.min(total, 99)}
    end
    return state
end

function Sync.Receive(sender, message, members, now)
    if type(sender) ~= "string" or not members[sender] then return false end
    local state = Sync.Decode(message)
    if not state then return false end
    Sync.peers[sender] = {state = state, at = now}
    return true
end

function Sync.Prune(members)
    local changed = false
    for name in pairs(Sync.peers) do
        if not members[name] and not (Sync.testMode and name == Sync.TEST_NAME) then Sync.peers[name], changed = nil, true end
    end
    return changed
end

function Sync.Reset() Sync.peers, Sync.dirty, Sync.lastSent, Sync.testMode = {}, false, nil, false end

-- Local test mode: a simulated member shows how shared quests look without a group.
-- Nothing is sent; the simulated data goes through the same parser as real messages.
Sync.TEST_NAME = "FQN-Test"
function Sync.Showing(settings) return (settings and settings.groupSync) or Sync.testMode == true end

-- Builds the simulated member's state from the own quests: one step behind on each.
function Sync.TestState(quests, questLog)
    local chosen = {}
    for _, quest in ipairs(quests or {}) do
        if #chosen >= 3 then break end
        chosen[#chosen + 1] = quest
    end
    local state = Sync.Collect(chosen, questLog, chosen[1] and chosen[1].id)
    for _, quest in ipairs(state.quests) do
        if quest.total > 0 then quest.done = math.max(0, math.min(quest.done, quest.total - 1)) end
    end
    return state, chosen
end

function Sync.StartTest(quests, questLog, now)
    local state, chosen = Sync.TestState(quests, questLog)
    if #chosen == 0 then return false end
    Sync.testMode = true
    Sync.Receive(Sync.TEST_NAME, Sync.Encode(state), {[Sync.TEST_NAME] = true}, now)
    local stops = {}
    for _, quest in ipairs(chosen) do stops[#stops + 1] = {id = quest.id, stage = quest.readyToTurnIn and "turnIn" or "objective"} end
    return true, Sync.DecodeTour(Sync.EncodeTour(stops))
end

function Sync.StopTest()
    Sync.testMode = false
    Sync.peers[Sync.TEST_NAME] = nil
end

-- {[questID] = number of synced members who still work on it}
function Sync.Counts()
    local counts
    for _, peer in pairs(Sync.peers) do
        for _, quest in ipairs(peer.state.quests) do
            if quest.total == 0 or quest.done < quest.total then
                counts = counts or {}
                counts[quest.id] = (counts[quest.id] or 0) + 1
            end
        end
    end
    return counts
end

-- "Name 1/3, Other 2/3" for members on the same quest, sorted by name.
function Sync.Describe(questID)
    local entries = {}
    for name, peer in pairs(Sync.peers) do
        for _, quest in ipairs(peer.state.quests) do
            if quest.id == questID then
                entries[#entries + 1] = quest.total > 0 and ("%s %d/%d"):format(name, quest.done, quest.total) or name
            end
        end
    end
    table.sort(entries)
    return #entries > 0 and table.concat(entries, ", ") or nil
end

-- Tour sharing: only on an explicit click. Format "T1|<id>:<o|t>,..." (o = objective,
-- t = turn-in), at most 20 stops. The receiver confirms before anything changes.
Sync.TOUR_MAX = 20
function Sync.EncodeTour(stops)
    local parts = {}
    for _, stop in ipairs(stops or {}) do
        if #parts >= Sync.TOUR_MAX then break end
        if type(stop.id) == "number" and stop.id > 0 and stop.id % 1 == 0 then
            parts[#parts + 1] = ("%d:%s"):format(stop.id, stop.stage == "turnIn" and "t" or "o")
        end
    end
    local text = "T1|" .. table.concat(parts, ",")
    return #parts > 0 and #text <= Sync.MAX_BYTES and text or nil
end

function Sync.DecodeTour(message)
    if type(message) ~= "string" or #message > Sync.MAX_BYTES then return end
    local list = message:match("^T1|([%d:ot,]+)$")
    if not list then return end
    local stops, seen = {}, {}
    for part in (list .. ","):gmatch("([^,]*),") do
        local id, stage = part:match("^(%d+):([ot])$")
        id = Integer(id, 1, 10000000)
        if not id or #stops >= Sync.TOUR_MAX then return end
        if not seen[id] then
            seen[id] = true
            stops[#stops + 1] = {id = id, stage = stage == "t" and "turnIn" or "objective"}
        end
    end
    return #stops > 0 and stops or nil
end

function Sync.ShareTour(api, channel, stops)
    local text = Sync.EncodeTour(stops)
    if not (text and api and api.SendAddonMessage and channel) then return false end
    return pcall(api.SendAddonMessage, Sync.PREFIX, text, channel)
end

-- Throttled send: at most one message per INTERVAL seconds, never in combat.
function Sync.MarkDirty() Sync.dirty = true end
function Sync.ReadyToSend(now, inCombat)
    if not Sync.dirty or inCombat then return false end
    return not Sync.lastSent or now - Sync.lastSent >= Sync.INTERVAL
end
function Sync.Send(api, channel, state, now)
    if not (api and api.SendAddonMessage and channel) then return false end
    local ok = pcall(api.SendAddonMessage, Sync.PREFIX, Sync.Encode(state), channel)
    Sync.dirty, Sync.lastSent = false, now
    return ok
end
