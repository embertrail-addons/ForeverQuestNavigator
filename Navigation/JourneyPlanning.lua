local _, addon = ...
local Journey = {}
addon.JourneyPlanning = Journey
local L = addon.L

function Journey.Along(snapshot, api)
    local active = snapshot.view and snapshot.view.quest
    local measured = active and snapshot.measurements and snapshot.measurements[active.id]
    local destination = measured and (measured.objectiveMarker or measured.marker)
    local metric = destination and addon.QuestLocation.GetDistanceMetric(api, destination)
    local rows = {}
    if not (metric and measured.yards) then return rows end
    local included = {}
    for _, stop in ipairs(snapshot.excursionPlan and snapshot.excursionPlan.stops or {}) do
        if stop.action == "turnIn" and not stop.done then included[stop.quest.id] = true end
    end
    for _, quest in ipairs(snapshot.ranked or {}) do
        local m = snapshot.measurements[quest.id]
        if quest.id ~= active.id and not included[quest.id] and quest.readyToTurnIn and m and m.marker and m.yards
            and not (snapshot.feedback and snapshot.feedback[quest.id]) then
            local remaining = metric(m.marker, destination)
            local detour = remaining and math.max(0, m.yards + remaining - measured.yards)
            if detour and detour <= 400 then
                rows[#rows + 1] = {quest = quest, target = m.marker, yards = m.yards, action = "turnIn", detour = detour,
                    short = L.JourneyDetour:format(detour), detail = L.JourneyDetour:format(detour) .. "\n" .. L.JourneyAlongHelp}
            end
        end
    end
    table.sort(rows, function(a, b) if a.detour ~= b.detour then return a.detour < b.detour end return a.quest.id < b.quest.id end)
    return rows
end

function Journey.InsertHandIn(plan, entry, api)
    if not (plan and plan.started and entry and entry.quest.readyToTurnIn and addon.TravelSupport.ValidPoint(entry.target)) then return end
    local stops = {}
    for _, stop in ipairs(plan.stops) do
        if stop.quest.id == entry.quest.id and stop.action == "turnIn" and not stop.done then return end
        stops[#stops + 1] = stop
    end
    table.insert(stops, plan.index, {quest = entry.quest, action = "turnIn", target = entry.target, yards = entry.yards, history = true})
    -- A separate preview: don't share mutable step progress with the running plan.
    local result = {stops = {}, index = plan.index, running = false, started = true, xp = plan.xp or 0,
        unknownXP = plan.unknownXP or 0, missing = plan.missing or 0, rewards = {}, receipts = {}, journeyKey = plan.journeyKey,
        mixed = plan.mixed, excludedOffers = addon.UndoHistory.Copy(plan.excludedOffers or {}), missingByQuest = plan.missingByQuest}
    for id, value in pairs(plan.rewards or {}) do result.rewards[id] = value end
    for id, receipt in pairs(plan.receipts or {}) do result.receipts[id] = {xp = receipt.xp} end
    if result.rewards[entry.quest.id] == nil then
        result.rewards[entry.quest.id] = entry.xp
        if entry.xp then result.xp = result.xp + entry.xp else result.unknownXP = result.unknownXP + 1 end
    end
    for _, stop in ipairs(stops) do local copy = {} for key, value in pairs(stop) do copy[key] = value end result.stops[#result.stops + 1] = copy end
    return result
end

function Journey.Bags(containers, slots)
    if not (containers and containers.GetContainerNumFreeSlots) then return {known = false} end
    local free = 0
    for bag = 0, slots or 4 do
        local ok, count, family = pcall(containers.GetContainerNumFreeSlots, bag)
        if not ok or type(count) ~= "number" or count < 0 or count ~= count then return {known = false} end
        if family == 0 then free = free + count elseif type(family) ~= "number" then return {known = false} end
    end
    return {known = true, free = free, low = free <= 3}
end

function Journey.SetLater(store, quest, point, when, area, context)
    if not (quest and quest.id and (when == "round" or when == "visit" or when == "group")) then return false end
    store[quest.id] = {id = quest.id, title = quest.title, level = quest.level, when = when, mapID = area,
        point = addon.TravelSupport.ValidPoint(point) and {mapID = point.mapID, x = point.x, y = point.y} or nil}
    if when == "round" and context then
        if context.roundFinished then store[quest.id].excludeToken = context.roundToken
        else store[quest.id].roundToken = context.roundToken end
    end
    return true
end

function Journey.Later(store, context, api)
    local rows = {}
    for id, saved in pairs(store or {}) do
        if type(saved) == "table" and saved.id == id and (saved.when == "round" or saved.when == "visit" or saved.when == "group") then
            local completed = false
            if api and api.IsQuestFlaggedCompleted then local ok, value = pcall(api.IsQuestFlaggedCompleted, id) completed = ok and value == true end
            if completed and api and api.IsOnQuest then local ok, value = pcall(api.IsOnQuest, id) if ok and value == true then completed = false end end
            local roundMatches = saved.roundToken and saved.roundToken == context.roundToken
                or not saved.roundToken and (not saved.excludeToken or saved.excludeToken ~= context.roundToken)
            local due = not completed and (saved.when == "round" and context.roundFinished and roundMatches
                or saved.when == "visit" and saved.mapID and saved.mapID == context.mapID
                or saved.when == "group" and context.grouped)
            rows[#rows + 1] = {quest = {id = id, title = saved.title, level = saved.level}, target = saved.point,
                due = due == true, completed = completed, later = true, short = L["JourneyLater_" .. saved.when],
                detail = L["JourneyLater_" .. saved.when] .. "\n" .. (completed and L.NoteCompleted or due and L.JourneyLaterDue or L.JourneyLaterHelp)}
        end
    end
    table.sort(rows, function(a, b) if a.due ~= b.due then return a.due end return a.quest.id < b.quest.id end)
    return rows
end

function Journey.Tours(planning, api)
    local choices = {}
    for _, area in ipairs(planning and planning.areas or {}) do
        local count = (area.active or 0) + (area.pickups or 0)
        if count > 0 then choices[#choices + 1] = area end
    end
    local nearest, richest
    for _, area in ipairs(choices) do
        if not nearest or area.yards < nearest.yards then nearest = area end
    end
    for _, area in ipairs(choices) do
        if area ~= nearest and (not richest or #area.entries > #richest.entries or #area.entries == #richest.entries and area.yards < richest.yards) then richest = area end
    end
    local rows = {}
    for index, area in ipairs({nearest or false, richest or false}) do
        if area and (index == 1 or area ~= nearest) then
            local summary = addon.PickupPlanning.AreaSummary(area)
            local label = index == 1 and L.JourneyTourNear or #area.entries > #nearest.entries and L.JourneyTourMore or L.JourneyTourAlternative
            rows[#rows + 1] = {quest = {id = area.entries[1].quest.id, title = label .. ": " .. area.zone},
                areaKey = area.entries[1].quest.id, target = area.target, short = summary,
                detail = summary .. "\n" .. L.ReasonDistance:format(area.yards) .. "\n" .. L.JourneyCompareHelp}
        end
    end
    return rows
end

function Journey.ChainRows(chains, expanded)
    local rows = {}
    for _, chain in ipairs(chains or {}) do
        rows[#rows + 1] = {quest = chain.quest, chainID = chain.quest.id, target = chain.stop and chain.stop.target,
            short = chain.known and (chain.summary ~= "" and chain.summary or L.UnknownFollowUps) or L.UnknownFollowUps,
            detail = (chain.detail or L.UnknownFollowUps) .. "\n" .. L.JourneyChainHelp}
        if expanded[chain.quest.id] then
            for index, stop in ipairs(chain.targets or {}) do
                rows[#rows + 1] = {quest = stop.quest, target = stop.target, short = L.FollowUp:format(index, stop.quest.title or ""),
                    detail = chain.detail .. "\n" .. L.JourneyChainHelp}
            end
            if #(chain.targets or {}) == 0 then rows[#rows + 1] = {quest = chain.quest, short = L.UnknownCoordinates, detail = L.JourneyChainHelp} end
        end
    end
    return rows
end
