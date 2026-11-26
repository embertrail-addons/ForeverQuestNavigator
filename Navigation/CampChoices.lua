local _, addon = ...
local Choices = {}
addon.CampChoices = Choices
-- first marker -> {api, count, last, byObjective = {[index] = groups}}. Marker lists are
-- rebuilt on every quest-log update around the same marker objects, so the first marker (with
-- count and last marker as a check) identifies the set; weak keys drop replaced markers.
local cache = setmetatable({}, {__mode = "k"})
Choices.CELL, Choices.NEAREST = 100, 8

-- Camps: spawn points within 100 yards of a camp's first point join that camp (the earliest
-- such camp). With world positions a 100-yard grid limits each check to neighbouring cells,
-- so cities with thousands of spawn points stay fast; otherwise every camp is compared.
local function Group(api, markers, index, metric)
    Choices.groupings = (Choices.groupings or 0) + 1
    local groups, grid = {}, {}
    local cell = Choices.CELL
    for _, point in ipairs(markers or {}) do
        if point.objectiveIndex == index then
            local world = addon.QuestLocation.GetMarkerWorldPosition(api, point)
            local group
            if world then
                local cx, cy = math.floor(world.x / cell), math.floor(world.y / cell)
                for dx = -1, 1 do
                    for dy = -1, 1 do
                        for _, candidate in ipairs(grid[world.continent .. ":" .. (cx + dx) .. ":" .. (cy + dy)] or {}) do
                            if not group or candidate.order < group.order then
                                local gap = metric(point, candidate.anchor)
                                if gap and gap <= 100 then group = candidate end
                            end
                        end
                    end
                end
            else
                for _, candidate in ipairs(groups) do local gap = metric(point, candidate.anchor) if gap and gap <= 100 then group = candidate break end end
            end
            if not group then
                group = {anchor = point, points = {}, order = #groups + 1}
                groups[#groups + 1] = group
                if world then
                    local key = world.continent .. ":" .. math.floor(world.x / cell) .. ":" .. math.floor(world.y / cell)
                    grid[key] = grid[key] or {}
                    table.insert(grid[key], group)
                end
            end
            group.points[#group.points + 1] = point
        end
    end
    return groups
end

function Choices.Build(api, quest, measurement, markers, quests, measurements, maps, previous, level, blocked)
    local target = measurement and measurement.marker
    if not target or quest.readyToTurnIn or not target.objectiveIndex then return {} end
    local metric = addon.QuestLocation.GetDistanceMetric(api, target)
    if not metric then return {} end
    local first = markers and markers[1]
    local entry = first and cache[first]
    if not (entry and entry.api == api and entry.count == #markers and entry.last == markers[#markers]) then
        entry = {api = api, count = markers and #markers or 0, last = markers and markers[#markers], byObjective = {}}
        if first then cache[first] = entry end
    end
    local groups = entry.byObjective[target.objectiveIndex]
    if not groups then
        groups = Group(api, markers, target.objectiveIndex, metric)
        entry.byObjective[target.objectiveIndex] = groups
    end
    -- Only the nearest camps (and the previously chosen one) are measured on each pass.
    local candidates = groups
    if #groups > Choices.NEAREST then
        local ranked = {}
        for _, group in ipairs(groups) do
            local gap = metric(target, group.anchor)
            local kept = previous and previous.objectiveIndex == target.objectiveIndex and metric(previous, group.anchor)
            ranked[#ranked + 1] = {group = group, gap = (kept and kept <= 100) and -1 or gap or math.huge}
        end
        table.sort(ranked, function(a, b) if a.gap ~= b.gap then return a.gap < b.gap end return a.group.order < b.group.order end)
        candidates = {}
        for index = 1, Choices.NEAREST do candidates[index] = ranked[index].group end
        table.sort(candidates, function(a, b) return a.order < b.order end)
    end
    local ids, points = {}, {}
    for index, group in ipairs(candidates) do ids[index], points[index] = index, group.points end
    groups = candidates
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
