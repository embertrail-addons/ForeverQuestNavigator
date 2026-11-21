local _, addon = ...
local Choices = {}
addon.CampChoices = Choices
local cache = setmetatable({}, {__mode = "k"})

function Choices.Build(api, quest, measurement, markers, quests, measurements, maps, previous, level, blocked)
    local target = measurement and measurement.marker
    if not target or quest.readyToTurnIn or not target.objectiveIndex then return {} end
    local metric = addon.QuestLocation.GetDistanceMetric(api, target)
    if not metric then return {} end
    local cached = markers and cache[markers]
    local groups, ids, points = {}, {}, {}
    if cached and cached.api == api and cached.objectiveIndex == target.objectiveIndex then groups = cached.groups
    else
    for _, point in ipairs(markers or {}) do
        if point.objectiveIndex == target.objectiveIndex then
            local group
            for _, candidate in ipairs(groups) do local gap = metric(point, candidate.anchor) if gap and gap <= 100 then group = candidate break end end
            if not group then group = {anchor = point, points = {}} groups[#groups + 1] = group end
            group.points[#group.points + 1] = point
        end
    end
    if markers then cache[markers] = {api = api, objectiveIndex = target.objectiveIndex, groups = groups} end
    end
    for index, group in ipairs(groups) do ids[index], points[index] = index, group.points end
    local measured = addon.QuestLocation.MeasureQuests(api, points, ids, maps)
    local result = {}
    for index, group in ipairs(groups) do
        local candidate = measured[index]
        if candidate then
            local shared = 0
            for _, other in ipairs(quests or {}) do
                local m = measurements[other.id]
                local gap = m and not m.objectiveMarker and metric(candidate.marker, m.marker)
                if other.id ~= quest.id and not other.readyToTurnIn and not (blocked and blocked[other.id])
                    and not addon.QuestPrioritizer.IsLowPriority(other, level) and gap and gap <= 100 then shared = shared + 1 end
            end
            local gap = previous and previous.objectiveIndex == target.objectiveIndex and metric(previous, candidate.marker)
            result[#result + 1] = {quest = quest, target = candidate.marker, measurement = candidate,
                yards = candidate.yards, shared = shared, score = candidate.yards - math.min(80, shared * 40), previous = gap and gap <= 100}
        end
    end
    table.sort(result, function(a, b)
        if a.score ~= b.score then return a.score < b.score end
        if a.target.mapID ~= b.target.mapID then return a.target.mapID < b.target.mapID end
        if a.target.x ~= b.target.x then return a.target.x < b.target.x end
        return a.target.y < b.target.y
    end)
    if result[1] then
        for index, candidate in ipairs(result) do
            if candidate.previous and (previous.manual or candidate.score <= result[1].score + math.max(100, result[1].yards * .15)) then
                table.remove(result, index) table.insert(result, 1, candidate) break
            end
        end
    end
    for index, candidate in ipairs(result) do
        candidate.reason = candidate.shared > 0 and addon.L.CampReasonCombined:format(candidate.shared) or addon.L.CampReasonDistance
        if index == 1 and candidate.previous then candidate.reason = previous.manual and addon.L.CampReasonManual or addon.L.CampReasonStable end
    end
    return result
end
