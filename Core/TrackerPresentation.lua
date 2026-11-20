local _, addon = ...
local Presentation = {}
addon.TrackerPresentation = Presentation
function Presentation.XPLine(reward, needed, level)
    if type(reward) ~= "number" or reward ~= reward or reward < 0 or reward == math.huge then return end
    if type(needed) ~= "number" or needed ~= needed or needed <= 0 or needed == math.huge
        or type(level) ~= "number" or level ~= level or level <= 0 or level == math.huge then
        return addon.L.QuestXPReward:format(reward)
    end
    if reward >= needed then return addon.L.NavigatorXPLevel:format(reward, level + 1) end
    return addon.L.NavigatorXPRemaining:format(reward, needed - reward, level + 1)
end
function Presentation.Information(zone, reward, notice)
    local parts, seen = {}, {}
    for _, value in ipairs({zone or "", reward or "", notice or ""}) do
        value = value:gsub("\n+", " · ")
        if value ~= "" and not seen[value] then parts[#parts + 1], seen[value] = value, true end
    end
    return table.concat(parts, " · ")
end
function Presentation.Summary(text, limit)
    local parts = {}
    for line in (text or ""):gmatch("[^\n]+") do
        parts[#parts + 1] = line
        if #parts >= (limit or 3) then break end
    end
    return table.concat(parts, "\n")
end
function Presentation.HeightLimit(value)
    if type(value) ~= "number" or value ~= value then return 600 end
    return math.floor(math.max(360, math.min(1000, value)))
end
function Presentation.ViewportHeight(pinned, natural, footer, limit, screen)
    local maximum = Presentation.HeightLimit(limit)
    if screen and screen > 100 then maximum = math.min(maximum, screen - 40) end
    local visible = math.max(1, math.min(natural, maximum - pinned - footer))
    return pinned + visible + footer, visible, math.max(0, natural - visible)
end
-- Freeze only the visible ordering during interaction. Ranking and navigation
-- keep using the live snapshot; removed quests never leave stale clickable rows.
function Presentation.VisualOrder(previous, entries, interacting)
    local order, indices, used = {}, {}, {}
    for index, entry in ipairs(entries or {}) do indices[entry.id or entry] = index end
    if interacting then
        for _, id in ipairs(previous or {}) do
            if indices[id] then order[#order + 1], used[id] = indices[id], true end
        end
    end
    for index, entry in ipairs(entries or {}) do
        if not used[entry.id or entry] then order[#order + 1] = index end
    end
    local ids = {}
    for _, index in ipairs(order) do ids[#ids + 1] = entries[index].id or entries[index] end
    return order, ids
end

function Presentation.DetailPlacement(left, right, screenWidth, panelWidth)
    if right and screenWidth and screenWidth - right >= panelWidth + 12 then return "right" end
    if left and left >= panelWidth + 12 then return "left" end
    return "tools"
end
function Presentation.ObjectiveProgress(goal)
    local text = goal.text or ""
    local description, parsedDone, parsedTotal = text:match("^(.-)%s*:%s*(%d+)%s*/%s*(%d+)%s*$")
    local done, total = goal.numFulfilled or goal.done or tonumber(parsedDone), goal.numRequired or goal.total or tonumber(parsedTotal)
    if type(done) ~= "number" or type(total) ~= "number" or total <= 0 or done < 0
        or done ~= done or total ~= total or total == math.huge or done == math.huge
        or done % 1 ~= 0 or total % 1 ~= 0 then return text end
    return description or text, ("%d/%d"):format(done, total), math.min(1, done / total)
end
function Presentation.QuestStatus(quest, manual)
    local L = addon.L
    local parts = {manual and L.NavigatorManual or L.NavigatorAutomatic}
    if quest and quest.readyToTurnIn then parts[#parts + 1] = L.NavigatorTurnIn end
    if quest and (quest.elite or quest.group) then parts[#parts + 1] = L.GroupQuest end
    return table.concat(parts, " · ")
end
function Presentation.Targets(quest, objectives, distances, measured, avoided, lock)
    if not objectives then return end
    local targets = not quest.readyToTurnIn and distances and distances[quest.id]
    local measurement = measured and measured[quest.id]
    local selected = targets and measurement and measurement.marker.objectiveIndex or nil
    local exclusions = avoided[quest.id] or {}
    local details = {index = selected, locked = lock and lock.questID == quest.id, avoidedCount = 0}
    for index, goal in ipairs(objectives) do
        if goal.text and goal.text ~= "" then
            details[#details + 1] = {index = index, text = goal.text, finished = goal.finished == true,
                numFulfilled = goal.numFulfilled, numRequired = goal.numRequired,
                selectable = not goal.finished and targets and targets[index] ~= nil or false, avoided = exclusions[index] == true}
            if exclusions[index] then details.avoidedCount = details.avoidedCount + 1 end
        end
    end
    if #details > 0 then return details end
end
function Presentation.SameTargets(a, b)
    if not a or not b then return a == b end
    if a.index ~= b.index or a.locked ~= b.locked or a.avoidedCount ~= b.avoidedCount or #a ~= #b then return false end
    for index, goal in ipairs(a) do
        local other = b[index]
        if goal.index ~= other.index or goal.text ~= other.text or goal.finished ~= other.finished
            or goal.numFulfilled ~= other.numFulfilled or goal.numRequired ~= other.numRequired
            or goal.selectable ~= other.selectable or goal.avoided ~= other.avoided then return false end
    end
    return true
end
function Presentation.Route(quest, route)
    local L = addon.L
    local first = quest.readyToTurnIn and L.TurnIn or L.FinishAndTurnIn
    local lines = {("%s %s"):format(first, quest.title or L.QuestNumber:format(quest.id))}
    for index, title in ipairs(route.followUps) do
        lines[#lines + 1] = L.FollowUp:format(index, title)
        if index == route.depth then lines[#lines + 1] = L.SameVisit:format(route.original.title or L.QuestNumber:format(route.original.id)) end
    end
    return table.concat(lines, "\n")
end
function Presentation.Outing(stops)
    local L, lines = addon.L, {addon.L.OutingOrder}
    for index, stop in ipairs(stops) do
        local quest = stop.quest
        lines[#lines + 1] = ("%d. %s %s"):format(index, quest.readyToTurnIn and L.TurnIn or L.WorkOn, quest.title or L.QuestNumber:format(quest.id))
    end
    return table.concat(lines, "\n")
end
