local _, addon = ...
local Feedback = { duration = 600, penalties = { hard = 600, blocked = 1200, inconvenient = 800,
    empty = 1000, group = 1400, access = 1200, area = 1200 } }
addon.RecommendationFeedback = Feedback

local function ObjectiveIndex(measurement)
    local marker = measurement and (measurement.objectiveMarker or measurement.marker)
    return marker and marker.objectiveIndex
end

function Feedback.Set(store, quest, measurement, kind, now)
    if not quest or not Feedback.penalties[kind] then return end
    store[quest.id] = { kind = kind, untilTime = now + Feedback.duration,
        ready = quest.readyToTurnIn == true, objectiveIndex = ObjectiveIndex(measurement) }
end

function Feedback.SetArea(store, api, quests, measurements, point, now)
    local metric = point and addon.QuestLocation.GetDistanceMetric(api, point)
    local count = 0
    if not metric then return count end
    for _, quest in ipairs(quests or {}) do
        local measured = measurements[quest.id]
        local target = measured and (measured.objectiveMarker or measured.marker)
        local gap = target and metric(point, target)
        if not quest.readyToTurnIn and gap and gap <= 400 then
            Feedback.Set(store, quest, measured, "area", now)
            store[quest.id].point = {mapID = point.mapID, x = point.x, y = point.y}
            count = count + 1
        end
    end
    return count
end

function Feedback.Get(store, quest, measurement, now)
    local entry = store and store[quest.id]
    if not entry then return end
    local index = ObjectiveIndex(measurement)
    local changedObjective = index and entry.objectiveIndex and index ~= entry.objectiveIndex
    if now >= entry.untilTime or entry.ready ~= (quest.readyToTurnIn == true) or changedObjective then store[quest.id] = nil return end
    if entry.kind == "hard" and quest.readyToTurnIn then return end
    return entry, Feedback.penalties[entry.kind]
end

function Feedback.List(store, quests, measurements, now)
    if not quests then return {} end
    local entries, present = {}, {}
    for _, quest in ipairs(quests or {}) do
        present[quest.id] = true
        local entry = Feedback.Get(store, quest, measurements and measurements[quest.id], now)
        if entry then entries[#entries + 1] = {id = quest.id, quest = quest, kind = entry.kind, seconds = entry.untilTime - now} end
    end
    for id in pairs(store) do if not present[id] then store[id] = nil end end
    table.sort(entries, function(a, b) if a.seconds ~= b.seconds then return a.seconds < b.seconds end return a.id < b.id end)
    return entries
end
