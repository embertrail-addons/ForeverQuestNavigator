local _, addon = ...
local Brief = {}
addon.DecisionBrief = Brief
local L = addon.L
local function XP(snapshot, quest)
    if snapshot.knownRewards then return snapshot.knownRewards[quest.id] end
    return quest.xp or addon.QuestLog.GetTurnInXP(quest)
end
function Brief.Status(quest, manual, phase)
    local parts = {phase or L.BriefPhase_travel}
    if manual then parts[#parts + 1] = L.NavigatorManual end
    if quest and (quest.group or quest.elite) then parts[#parts + 1] = L.GroupQuest end
    return table.concat(parts, " · ")
end

function Brief.ObjectiveText(view)
    local lines = {}
    if view.quest and (view.quest.group or view.quest.elite) then lines[#lines + 1] = L.GroupQuest end
    for _, goal in ipairs(view.targets or {}) do
        local text, counter = addon.TrackerPresentation.ObjectiveProgress(goal)
        lines[#lines + 1] = text .. (counter and (" · " .. counter) or "")
    end
    if #lines == 0 then lines[1] = view.objectives or L.SeeQuestLog end
    if type(view.noteText) == "string" and view.noteText ~= "" then lines[#lines + 1] = L.QuestNoteText:format(view.noteText) end
    return table.concat(lines, "\n")
end

function Brief.Evidence(quest, measurement, level)
    local hasLevel = addon.QuestPrioritizer.GetDifficulty(quest, level) ~= nil
    local quality = addon.NavigationHints.TargetKind(measurement and measurement.marker)
    if not measurement or not addon.TravelSupport.ValidPoint(measurement.marker) or not hasLevel then return "limited", L.EvidenceLimited end
    if quality == "approximate" or quality == "access" then return "approximate", L.EvidenceApproximate end
    return "known", L.EvidenceKnown
end

function Brief.Compare(snapshot, selected, alternative)
    if not selected then return L.ComparisonUnavailable end
    local lines = {L.BriefSelected:format(selected.title or L.QuestNumber:format(selected.id))}
    if alternative then lines[#lines + 1] = L.BriefAlternative:format(alternative.title or L.QuestNumber:format(alternative.id)) end
    local function Facts(quest)
        local measured = snapshot.measurements and snapshot.measurements[quest.id]
        local _, evidence = Brief.Evidence(quest, measured, snapshot.playerLevel)
        local difficulty = addon.QuestPrioritizer.GetDifficulty(quest, snapshot.playerLevel)
        local xp = XP(snapshot, quest)
        return (quest.title or L.QuestNumber:format(quest.id)) .. ": "
            .. (measured and type(measured.yards) == "number" and L.ReasonDistance:format(measured.yards) or L.UnknownCoordinates) .. " · "
            .. (difficulty and L["Difficulty_" .. difficulty] or L.UnknownLevel) .. "\n"
            .. (xp and L.QuestXPReward:format(xp) or L.UnknownXP) .. " · " .. evidence
    end
    lines[#lines + 1] = Facts(selected)
    if alternative then lines[#lines + 1] = Facts(alternative) end
    lines[#lines + 1] = addon.Recommendation.Short(snapshot, selected, snapshot.view and snapshot.view.manual)
    if alternative then
        local a, b = snapshot.measurements and snapshot.measurements[selected.id], snapshot.measurements and snapshot.measurements[alternative.id]
        if a and b and a.yards and b.yards and b.yards < a.yards then lines[#lines + 1] = L.BriefCloserAlternative end
    end
    lines[#lines + 1] = snapshot.comparison or L.ComparisonFactors
    lines[#lines + 1] = L.BriefNoScore
    return table.concat(lines, "\n")
end

function Brief.Build(snapshot, ledger, mapAPI, mapType)
    snapshot = snapshot or {}
    local view, measurements = snapshot.view or {}, snapshot.measurements or {}
    local active = view.quest
    local result = {steps = {}, closing = {}, handInAreas = {}, sharedItems = snapshot.sharedItems or {}, ledger = ledger,
        playerLevel = snapshot.playerLevel}
    local seen = {}
    local function Add(quest, kind, target, yards, detail, offer)
        if not quest or seen[quest.id] or (active and quest.id == active.id) then return end
        seen[quest.id] = true
        if quest.elite or quest.group then detail = L.GroupQuest .. (detail and (" · " .. detail) or "") end
        result.steps[#result.steps + 1] = {quest = quest, kind = kind, target = target, yards = yards,
            detail = detail, offer = offer, action = kind == "accept" and "accept" or kind == "turnIn" and "turnIn" or "objective"}
    end
    local plan = snapshot.pickupPlanning or {}
    local currentStep = snapshot.excursionStep
    if currentStep and currentStep.action == "accept" then
        Add(currentStep.quest, "accept", currentStep.target, snapshot.excursionYards, L.ExcursionHelp, true)
    end
    result.roundComplete = ledger and #ledger.steps > 0 and ledger.completed == #ledger.steps
    if result.roundComplete then
        for _, quest in ipairs(snapshot.ranked or {}) do
            local measured = measurements[quest.id]
            if quest.readyToTurnIn and measured and not (snapshot.feedback and snapshot.feedback[quest.id]) then
                Add(quest, "turnIn", measured.marker, measured.yards, L.BriefRoundDone)
            end
        end
    end
    if plan.turnIn then Add(plan.turnIn.quest, "turnIn", plan.turnIn.target, plan.turnIn.leg, L.BriefMakeRoom) end
    for _, offer in ipairs(plan.pickups or {}) do Add(offer, "accept", offer.marker, offer.yards, offer.planReason, true) end
    for _, stop in ipairs(view.approachStops or {}) do
        local measured = measurements[stop.quest.id]
        Add(stop.quest, stop.quest.readyToTurnIn and "turnIn" or "along", stop.target or measured and measured.marker,
            stop.yards, L.BriefAlongHelp)
    end
    for _, quest in ipairs(view.alternatives or snapshot.ranked or {}) do
        local measured = measurements[quest.id]
        if measured and not (snapshot.feedback and snapshot.feedback[quest.id])
            and not addon.QuestPrioritizer.IsLowPriority(quest, snapshot.playerLevel) then
            Add(quest, quest.readyToTurnIn and "turnIn" or "objective", measured.marker, measured.yards, L.BriefNextHelp)
        end
    end
    result.area = plan.destination
    result.capacity = snapshot.capacity or plan.capacity
    result.xp, result.unknownXP = 0, 0
    local tour = snapshot.turnInTour or {stops = {}}
    local byMap, stops, added = {}, {}, {}
    result.unknownHandIns = 0
    for _, stop in ipairs(tour.stops or {}) do stops[#stops + 1] = stop added[stop.quest.id] = true end
    for _, quest in ipairs(snapshot.ranked or {}) do
        if quest.readyToTurnIn and not added[quest.id] and not (snapshot.feedback and snapshot.feedback[quest.id]) then
            local measured = measurements[quest.id]
            if measured and measured.marker then
                stops[#stops + 1] = {quest = quest, target = measured.marker, action = "turnIn", xp = XP(snapshot, quest)}
            else result.unknownHandIns = result.unknownHandIns + 1 end
        end
    end
    for _, stop in ipairs(stops) do
        local mapID = stop.target.mapID
        local group = byMap[mapID]
        if not group then
            local _, zone = addon.QuestLocation.GetZone(mapAPI, mapAPI and mapType, mapID)
            group = {target = stop.target, entries = {}, xp = 0, unknownXP = 0,
                zone = zone or stop.target.zoneName or L.BriefMap:format(mapID)}
            byMap[mapID], result.handInAreas[#result.handInAreas + 1] = group, group
        end
        group.entries[#group.entries + 1] = stop
        if stop.xp then group.xp = group.xp + stop.xp else group.unknownXP = group.unknownXP + 1 end
        local measured = measurements[stop.quest.id]
        if measured and measured.yards and measured.yards <= 1500 then result.closing[#result.closing + 1] = stop end
    end
    for _, stop in ipairs(result.closing) do
        if stop.xp then result.xp = result.xp + stop.xp else result.unknownXP = result.unknownXP + 1 end
    end
    -- A map can contain several distant towns. Recommend a bounded hand-in
    -- cluster, never every finisher merely sharing a map ID.
    local best
    for _, anchor in ipairs(stops) do
        local measured = measurements[anchor.quest.id]
        local metric = mapAPI and addon.QuestLocation.GetDistanceMetric(mapAPI, anchor.target)
        if metric and measured and measured.yards and measured.yards <= 2500 then
            local group = {stops = {}, xp = 0, unknownXP = 0, followUps = 0, target = anchor.target, yards = measured.yards}
            local ids = {}
            for _, stop in ipairs(stops) do
                local gap = metric(anchor.target, stop.target)
                if gap and gap <= 600 and not ids[stop.quest.id] then
                    ids[stop.quest.id] = true group.stops[#group.stops + 1] = stop
                    if stop.xp then group.xp = group.xp + stop.xp else group.unknownXP = group.unknownXP + 1 end
                end
            end
            for _, chain in ipairs(snapshot.chains or {}) do
                if chain.known and chain.quest and ids[chain.quest.id] then group.followUps = group.followUps + 1 end
            end
            if #group.stops >= 2 and (not best or #group.stops > #best.stops or #group.stops == #best.stops and group.yards < best.yards) then best = group end
        end
    end
    if best then
        local _, zone = addon.QuestLocation.GetZone(mapAPI, mapType, best.target.mapID)
        best.zone = zone or best.target.zoneName or L.UnknownZone
        result.returnAdvice = best
        result.closing, result.xp, result.unknownXP = best.stops, best.xp, best.unknownXP
    end
    if active then
        result.why = addon.Recommendation.Short(snapshot, active, view.manual)
        result.evidence, result.evidenceText = Brief.Evidence(active, measurements[active.id], snapshot.playerLevel)
        local alternative
        for _, quest in ipairs(snapshot.ranked or {}) do
            if quest.id ~= active.id and not (snapshot.feedback and snapshot.feedback[quest.id]) then
                local m, old = measurements[quest.id], alternative and measurements[alternative.id]
                if not alternative or m and m.yards and (not old or not old.yards or m.yards < old.yards) then alternative = quest end
            end
        end
        result.comparison = Brief.Compare(snapshot, active, alternative)
        result.group = active.group or active.elite
    end
    result.phase = snapshot.flying and "flight" or active and active.readyToTurnIn and "turnIn"
        or snapshot.arrived and "work" or "travel"
    result.phaseText = L["BriefPhase_" .. result.phase]
    result.review = addon.ExcursionPlan and addon.ExcursionPlan.Review(snapshot.excursionPlan)
    result.acceptanceReview = snapshot.excursionPlan and snapshot.excursionPlan.needsReview
    result.offerUndo = snapshot.offerUndo
    result.departureCount = #(plan.pickups or {})
    result.laterCount = snapshot.laterCount or 0
    result.bagsWarning = snapshot.collecting and snapshot.bags and snapshot.bags.low and L.JourneyCollectBags:format(snapshot.bags.free) or nil
    result.changes = addon.AdventureSupport and addon.AdventureSupport.Changes(snapshot.excursionPlan, snapshot, mapAPI) or {}
    return result
end

function Brief.Report(snapshot, brief)
    local knownChains = 0
    for _, chain in ipairs(snapshot.chains or {}) do if chain.known and chain.stop then knownChains = knownChains + 1 end end
    local lines = {L.BriefReport, brief.comparison or L.ComparisonUnavailable,
        "", L.BriefFactors, "phase=" .. tostring(brief.phase), "evidence=" .. tostring(brief.evidence or "limited"),
        "pickupSlots=" .. tostring(snapshot.pickupPlanning and snapshot.pickupPlanning.budget or "unknown"),
        "followUpRoutes=" .. tostring(knownChains)}
    for _, step in ipairs(brief.steps) do
        lines[#lines + 1] = ("quest=%d action=%s yards=%s"):format(step.quest.id, step.kind, tostring(step.yards or "unknown"))
    end
    lines[#lines + 1] = L.BriefReportPrivacy
    return table.concat(lines, "\n")
end
