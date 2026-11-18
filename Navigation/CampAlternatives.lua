local _, addon = ...
local Camps = { radius = 100, duration = 600 }
addon.CampAlternatives = Camps

local function Rejected(mapAPI, marker, entries, now)
    if not entries or #entries == 0 then return false end
    if not marker.objectiveIndex then return true end
    local metric = addon.QuestLocation.GetDistanceMetric(mapAPI, marker)
    for _, entry in ipairs(entries or {}) do
        if now < entry.untilTime and entry.point.objectiveIndex == marker.objectiveIndex then
            local gap = metric and metric(marker, entry.point)
            if gap and gap <= Camps.radius then return true end
        end
    end
    return false
end

function Camps.Filter(mapAPI, markers, store, now)
    local result = {}
    for id, points in pairs(markers or {}) do
        local entries = store and store[id]
        if entries then
            for index = #entries, 1, -1 do if now >= entries[index].untilTime then table.remove(entries, index) end end
            if #entries == 0 then store[id], entries = nil, nil end
        end
        result[id] = {}
        for _, marker in ipairs(points) do
            if not Rejected(mapAPI, marker, entries, now) then result[id][#result[id] + 1] = marker end
        end
    end
    return result
end

function Camps.Find(mapAPI, quest, measurement, markers, store, now)
    local current = measurement and (measurement.objectiveMarker or measurement.marker)
    local index = current and current.objectiveIndex
    if type(index) ~= "number" or index < 1 or index >= math.huge or index ~= math.floor(index) or quest.readyToTurnIn then return end
    local metric = addon.QuestLocation.GetDistanceMetric(mapAPI, current)
    local best, nearest
    for _, point in ipairs(markers or {}) do
        if point.objectiveIndex == current.objectiveIndex then
            local gap = metric and metric(current, point)
            if gap and gap > Camps.radius and not Rejected(mapAPI, point, store[quest.id], now)
                and (not nearest or gap < nearest) then best, nearest = point, gap end
        end
    end
    return best
end

function Camps.Switch(mapAPI, quest, measurement, markers, store, now)
    local alternative = Camps.Find(mapAPI, quest, measurement, markers, store, now)
    if not alternative then return end
    local current = measurement.objectiveMarker or measurement.marker
    local entries = store[quest.id] or {}
    entries[#entries + 1] = {point = {mapID = current.mapID, x = current.x, y = current.y,
        objectiveIndex = current.objectiveIndex}, untilTime = now + Camps.duration}
    store[quest.id] = entries
    return alternative
end
