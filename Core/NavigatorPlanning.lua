local _, addon = ...
local L = addon.L
local integration = addon.QuestieIntegration
-- Planning, outing, access point, notepad and skip actions of the navigator.
-- Installed by Core/Bootstrap.lua with the shared navigator state S and functions F.
addon.NavigatorPlanning = {}

function addon.NavigatorPlanning.Install(S, F)
    function F.ShowAccessManager()
        local function Title(id, stored)
            for _, quest in ipairs(S.eligibleQuests or {}) do if quest.id == id and quest.title then return quest.title end end
            local lookup = C_QuestLog and C_QuestLog.GetTitleForQuestID
            if type(lookup) ~= "function" then lookup = LibQuestieDB and LibQuestieDB.Quest and LibQuestieDB.Quest.name end
            if type(lookup) == "function" then
                local ok, name = pcall(lookup, id)
                if ok and type(name) == "string" and name ~= "" then return name end
            end
            return type(stored) == "string" and stored or L.QuestNumber:format(id)
        end
        local function Changed(entry)
            S.passedAccessPoints[entry.questID .. ":" .. entry.index] = nil
            S.outing = nil
            F.ScheduleRefresh()
        end
        addon.ShowAccessManager({
            list = function() return addon.TravelSupport.ListAccess(S.savedAccessPoints, C_Map, Title) end,
            filter = function(entries, query, mode) return addon.QuestTools.FilterAccess(entries, query, mode, C_QuestLog) end,
            map = function(entry) F.OpenRouteStop({ target = entry.point }) end,
            rename = function(entry, name)
                local changed = addon.TravelSupport.RenameAccess(S.savedAccessPoints, entry.questID, entry.index, name)
                if changed then Changed(entry) end
                return changed
            end,
            remove = function(entry)
                local before = addon.UndoHistory.Copy(S.savedAccessPoints[entry.questID] and S.savedAccessPoints[entry.questID][entry.index])
                addon.TravelSupport.RemoveAccess(S.savedAccessPoints, entry.questID, entry.index)
                F.RecordAccessChange(entry.questID, entry.index, before)
                Changed(entry)
            end,
            route = function(entry)
                addon.ShowAccessRouteEditor({
                    list = function()
                        local objectives = S.savedAccessPoints[entry.questID]
                        return addon.TravelSupport.AccessSteps(objectives and objectives[entry.index]) or {}
                    end,
                    map = function(point) F.OpenRouteStop({target = point}) end,
                    note = function(step, text)
                        local before = addon.UndoHistory.Copy(S.savedAccessPoints[entry.questID] and S.savedAccessPoints[entry.questID][entry.index])
                        if addon.TravelSupport.SetAccessNote(S.savedAccessPoints, entry.questID, entry.index, step, text) then
                            F.RecordAccessChange(entry.questID, entry.index, before) F.ScheduleRefresh()
                        end
                    end,
                    move = function(step, delta)
                        local before = addon.UndoHistory.Copy(S.savedAccessPoints[entry.questID] and S.savedAccessPoints[entry.questID][entry.index])
                        if addon.TravelSupport.MoveAccessStep(S.savedAccessPoints, entry.questID, entry.index, step, delta) then F.RecordAccessChange(entry.questID, entry.index, before) Changed(entry) addon.RefreshAccessManager() end
                    end,
                    remove = function(step)
                        local before = addon.UndoHistory.Copy(S.savedAccessPoints[entry.questID] and S.savedAccessPoints[entry.questID][entry.index])
                        if addon.TravelSupport.RemoveAccessStep(S.savedAccessPoints, entry.questID, entry.index, step) then F.RecordAccessChange(entry.questID, entry.index, before) Changed(entry) addon.RefreshAccessManager() end
                    end,
                })
            end,
        })
    end

    function F.ShowNotepad()
        addon.ShowQuestNotepad({
            list = function()
                return addon.QuestTools.Notes(S.questNotes, C_QuestLog, function(id)
                    if C_QuestLog.IsOnQuest and C_QuestLog.IsOnQuest(id) then
                        local destination = F.GetQuestDestination(id)
                        return destination and destination.target
                    end
                end)
            end,
            map = function(entry) if entry.point then F.OpenRouteStop({ target = entry.point }) end end,
            remove = function(id) S.questNotes[id] = nil S.insights.noteRevision = (S.insights.noteRevision or 0) + 1 F.ScheduleRefresh() end,
        })
    end

    function F.LoadSkippedQuests()
        if type(ForeverQuestNavigatorCharacterDB) ~= "table" then
            ForeverQuestNavigatorCharacterDB = {}
        end
        local stored = ForeverQuestNavigatorCharacterDB.skippedQuests
        if type(stored) ~= "table" then stored = {} end
        ForeverQuestNavigatorCharacterDB.skippedQuests = stored
        S.skippedQuestIDs = stored
        for id, entry in pairs(stored) do
            if type(id) ~= "number" or id <= 0 or type(entry) ~= "table" or type(entry.quest) ~= "table"
                or entry.quest.id ~= id or type(entry.order) ~= "number" or not (entry.order >= 1 and entry.order < math.huge) then
                stored[id] = nil
            else
                S.skipOrder = math.max(S.skipOrder, entry.order)
            end
        end
    end

    function F.SkipQuest(quest)
        F.ApplyQuestAction("skip", quest)
    end

    function F.RestoreQuest(questID)
        F.ApplyQuestAction("restore", questID)
    end

    function F.ResetSkips()
        F.ApplyQuestAction("resetSkips")
    end

    function F.ShowZones()
        addon.ShowZoneOverview(function()
            if not F.TrackingVisible() and S.measurableQuestIDs and not S.refreshPending then F.UpdateDistances(false) end
            return addon.BuildZoneOverview(C_Map, Enum and Enum.UIMapType, S.eligibleQuests, S.navigationSnapshot)
        end, function(marker) F.OpenRouteStop({ target = marker }) end)
    end

    function F.ShowFixture()
        local fixture = addon.RegressionFixture.Capture(S.eligibleQuests, S.navigationSnapshot)
        addon.ShowTextWindow("fixture", fixture and addon.RegressionFixture.Encode(fixture) or L.NoFixture,
            L.ExportFixture, L.FixtureHelp)
    end

    F.ShowPlanning = function()
        return addon.ShowPlanningOverview(function()
            if not F.TrackingVisible() and S.measurableQuestIDs and not S.refreshPending then F.UpdateDistances(false) end
            return S.navigationSnapshot or {pickupPlanning = S.insights.pickupPlanning, capacity = S.questCapacity,
                brief = addon.DecisionBrief.Build({pickupPlanning = S.insights.pickupPlanning, capacity = S.questCapacity}, S.insights.roundLedger)}
        end, F.OpenRouteStop)
    end

    function addon.OpenQuestNote(id, isOffer)
        if addon.DemoMode.IsActive() then print("FQN | " .. L.DemoReadOnly) return end
        local chosen
        for _, quest in ipairs((isOffer and S.nearbyOffers or addon.QuestLog.Read(C_QuestLog)) or {}) do if quest.id == id then chosen = quest break end end
        local m = isOffer and chosen or S.questMeasurements and S.questMeasurements[id]
        local point = m and m.marker
        return addon.ShowQuestNoteEditor(id, chosen and chosen.title, S.questNotes[id] and S.questNotes[id].text, function(text)
            local before = addon.UndoHistory.Copy(S.questNotes[id])
            addon.QuestTools.SetNoteText(S.questNotes, id, chosen and chosen.title, point, isOffer, text)
            S.insights.noteRevision = (S.insights.noteRevision or 0) + 1
            if addon.Undo then addon.Undo:Capture(L.EditQuestNote, function() return S.questNotes[id] end, function(value)
                S.questNotes[id] = value S.insights.noteRevision = (S.insights.noteRevision or 0) + 1 F.ScheduleRefresh() addon.RefreshQuestNotepad()
            end, before, S.questNotes[id]) end
            F.ScheduleRefresh() addon.RefreshQuestNotepad()
        end)
    end
    function addon.GetQuestNoteText(id)
        local note = S.questNotes[id]
        return type(note) == "table" and type(note.text) == "string" and note.text or nil
    end
    function addon.OpenCampChoices(id)
        if addon.DemoMode.IsActive() then return end
        addon.ShowCampChoices(function() return S.navigationSnapshot and S.navigationSnapshot.camps and S.navigationSnapshot.camps[id] end,
            F.OpenRouteStop, function(choice)
                S.insights.previousCamps = S.insights.previousCamps or {}
                S.insights.previousCamps[id] = {mapID = choice.target.mapID, x = choice.target.x, y = choice.target.y,
                    objectiveIndex = choice.target.objectiveIndex, manual = true}
                F.ScheduleRefresh()
            end)
    end
    function addon.OpenExcursionFromArea(key, review, override, excluded)
        if addon.DemoMode.IsActive() then print("FQN | " .. L.DemoReadOnly) return end
        local planning = S.insights.pickupPlanning
        local area = planning and planning.destination
        if override then area = override end
        if key then
            area = nil
            for _, candidate in ipairs(planning and planning.areas or {}) do if candidate.entries[1].quest.id == key then area = candidate break end end
        end
        local options = {api = C_Map, level = UnitLevel and UnitLevel("player"), hidden = S.insights.hiddenOffers,
            feedback = S.navigationSnapshot and S.navigationSnapshot.feedback,
            excluded = excluded or override and S.insights.excursion and S.insights.excursion.excludedOffers,
            fromPlayer = function(point) local m = addon.TemporaryDetour.Measure(C_Map, point) return m and m.yards end}
        if not review then area = addon.MixedQuestPlan.Gather(area, S.eligibleQuests, S.questMeasurements, options) end
        local plan = review and S.insights.excursion or addon.ExcursionPlan.Build(area, S.questCapacity, function(quest, origin)
            local measured = quest.readyToTurnIn and S.navigationSnapshot and S.navigationSnapshot.measurements and S.navigationSnapshot.measurements[quest.id]
            if measured and not measured.objectiveMarker and addon.TravelSupport.ValidPoint(measured.marker) then return measured.marker end
            if not integration.IsReady() then return end
            return addon.QuestieRoutes.GetOutdoorTurnInMarker(C_Map, Enum and Enum.UIMapType, S.questTargetMaps or {}, quest.id, origin)
        end, function(quest, pickup)
            if pickup then return quest.xp end
            return addon.QuestLog.GetTurnInXP(quest)
        end, options)
        if review and plan and plan.needsReview then
            plan = addon.MixedQuestPlan.Refresh(plan, addon.QuestLog.Read(C_QuestLog), S.questMeasurements, S.navigationSnapshot and S.navigationSnapshot.finishers)
        end
        if not review then plan = addon.AdventureSupport.Budget(plan, S.insights.tourMinutes, C_Map) end
        return addon.ReviewPreparedOuting(plan, function(minutes, exclusions) S.insights.tourMinutes = minutes return addon.OpenExcursionFromArea(key, false, override, exclusions) end)
    end

    function addon.ReviewPreparedOuting(plan, budget)
        return addon.ShowExcursion(plan, {
            map = F.OpenRouteStop,
            start = function(candidate)
                local wasStarted = candidate.started
                local ok, reason = addon.ExcursionPlan.Start(candidate, addon.QuestLog.Read(C_QuestLog), S.nearbyOffers,
                    C_QuestLog.IsQuestFlaggedCompleted, S.questCapacity)
                if not ok then return false, reason end
                if not wasStarted then S.insights.offerSuppressed = {} end
                local previous = S.insights.excursion
                if previous and previous.started and previous.index <= #previous.stops then candidate.journeyKey = previous.journeyKey end
                addon.PauseExcursion()
                candidate.running = true S.insights.excursion = candidate
                S.manualQuestID, S.heldQuest, S.objectiveLock, S.outing = nil, nil, nil, nil
                S.temporaryDetour, S.detourMeasurement = nil, nil
                if S.workspace then S.workspace.plan.running = false S.workspace:Save() end
                F.ScheduleRefresh() return true
            end,
            pause = function() addon.PauseExcursion() F.ScheduleRefresh() end,
            dismiss = function()
                if S.insights.excursion then
                    S.insights.excursion.reviewDismissed = true
                    if S.insights.excursion.index > #S.insights.excursion.stops then S.insights.excursion.excludedOffers, S.insights.offerSuppressed = {}, {} end
                end
                F.ScheduleRefresh()
            end,
            budget = budget,
            skip = function(id, mode) return addon.SkipOfferStep(plan, id, mode) end,
            undo = function() return addon.Undo:Undo() end,
            canUndo = function() return addon.OfferUndoAvailable(plan) end,
        })
    end

    function addon.OpenOutingReview()
        if S.insights.excursion then return addon.OpenExcursionFromArea(nil, true) end
    end

    function addon.OpenAdventure(mode, blockedID)
        if addon.DemoMode.IsActive() then print("FQN | " .. L.DemoReadOnly) return end
        if blockedID then S.insights.blockedQuestID = blockedID end
        return addon.ShowAdventure(function(section)
            local snapshot = S.navigationSnapshot or {}
            local result = {rows = {}}
            if section == "along" then
                result.rows = addon.JourneyPlanning.Along(snapshot, C_Map) result.summary = L.JourneyAlongHelp
            elseif section == "compare" then
                result.rows = addon.JourneyPlanning.Tours(S.insights.pickupPlanning, C_Map) result.summary = L.JourneyCompareHelp
            elseif section == "chains" then
                S.insights.expandedChains = S.insights.expandedChains or {}
                result.rows = addon.JourneyPlanning.ChainRows(snapshot.chains, S.insights.expandedChains) result.summary = L.JourneyChainHelp
            elseif section == "later" then
                result.rows = addon.JourneyPlanning.Later(S.insights.laterQuests, addon.GetLaterContext(), C_QuestLog) result.summary = L.JourneyLaterHelp
                for _, e in ipairs(result.rows) do if e.due then e.short = L.JourneyLaterDue .. " · " .. e.short end end
            elseif section == "hiddenOffers" then
                result.summary = L.OfferHiddenHelp
                for id, q in pairs(S.insights.hiddenOffers) do
                    result.rows[#result.rows + 1] = {quest = q, short = L.OfferHide, detail = L.OfferHiddenHelp, hiddenOffer = true}
                end
                table.sort(result.rows, function(a, b) return a.quest.id < b.quest.id end)
            elseif section == "bags" then
                local bags = addon.JourneyPlanning.Bags(C_Container, NUM_BAG_SLOTS)
                result.summary = (bags.known and L.JourneyFreeBags:format(bags.free) or L.JourneyBagsUnknown) .. "\n" .. L.JourneyBagsHelp
                local best
                if bags.low then for index, vendor in ipairs(S.insights.knownVendors) do
                    local m = type(vendor) == "table" and addon.TravelSupport.ValidPoint(vendor.point) and addon.TemporaryDetour.Measure(C_Map, vendor.point)
                    if m and (not best or m.yards < best.yards) then best = {quest = {id = 0, title = vendor.name or L.JourneyVendor},
                        target = vendor.point, vendorIndex = index, yards = m.yards, detail = L.JourneyVendorHelp} end
                end end
                if best then result.rows[1] = best end
                result.canSaveVendor = MerchantFrame and MerchantFrame.IsShown and MerchantFrame:IsShown() or false
            elseif section == "departure" then
                result.rows = addon.AdventureSupport.Departure(S.insights.pickupPlanning, S.questCapacity)
                result.summary = L.AdventureDepartureHelp
            elseif section == "blocked" then
                result.rows = addon.AdventureSupport.Alternatives(snapshot, S.insights.blockedQuestID or S.shownQuests and S.shownQuests[1] and S.shownQuests[1].id)
                result.summary = L.AdventureBlockedHelp
            elseif section == "group" then
                result.enabled = S.settings.groupQuestHints == true result.summary = L.AdventureGroupHelp
                if result.enabled then
                    local units = {}
                    local raid = IsInRaid and IsInRaid()
                    for index = 1, raid and 40 or 4 do
                        local unit = (raid and "raid" or "party") .. index
                        if UnitExists and UnitExists(unit) and not (UnitIsUnit and UnitIsUnit(unit, "player")) then units[#units + 1] = unit end
                    end
                    local cached = S.insights.groupAdvice
                    if not cached or cached.quests ~= S.eligibleQuests or F.SessionTime() - cached.at >= 5 then
                        cached = {quests = S.eligibleQuests, at = F.SessionTime(), rows = addon.AdventureSupport.Group(S.eligibleQuests, units, C_QuestLog)} S.insights.groupAdvice = cached
                    end
                    for _, e in ipairs(cached.rows) do
                        local m = snapshot.measurements and snapshot.measurements[e.quest.id]
                        local short = L.AdventureShared:format(e.count, e.unknown)
                        local mates = addon.GroupSync.Showing(S.settings) and addon.GroupSync.Describe(e.quest.id)
                        if mates then short = short .. " · " .. L.GroupSyncMates:format(mates) end
                        result.rows[#result.rows + 1] = {quest = e.quest, target = m and m.marker,
                            short = short, detail = short .. "\n" .. L.AdventureGroupHelp}
                    end
                end
            elseif section == "level" then
                result.summary = L.AdventureLevelHelp
                for _, e in ipairs(S.insights.levelReport and S.insights.levelReport.entries or {}) do
                    local m = snapshot.measurements and snapshot.measurements[e.quest.id]
                    result.rows[#result.rows + 1] = {quest = e.quest, target = m and m.marker,
                        short = L["Difficulty_" .. e.before] .. " -> " .. L["Difficulty_" .. e.after], detail = L.AdventureLevelHelp}
                end
            elseif section == "changes" then
                result.rows = addon.AdventureSupport.Changes(S.insights.excursion, snapshot, C_Map)
                result.summary = L.AdventureChangeHelp
            elseif section == "corrections" then
                result.summary = L.AdventureCorrectionHelp
                for id, points in pairs(S.targetCorrections) do
                    for index, point in pairs(type(points) == "table" and points or {}) do
                        if addon.TravelSupport.ValidPoint(point) then
                            local quest = {id = id}
                            for _, q in ipairs(S.eligibleQuests or {}) do if q.id == id then quest = q break end end
                            local text = L.AdventureCorrectionPoint:format(point.mapID, point.x * 100, point.y * 100)
                            result.rows[#result.rows + 1] = {quest = quest, target = point, index = index, short = text, detail = text .. "\n" .. L.AdventureCorrectionHelp}
                        end
                    end
                end
                table.sort(result.rows, function(a, b) if a.quest.id ~= b.quest.id then return a.quest.id < b.quest.id end return a.index < b.index end)
            end
            return result
        end, {
            map = F.OpenRouteStop,
            select = function(id) addon.PauseExcursion() S.insights.levelHold = nil F.SelectQuest(id) end,
            toggleGroup = function() S.settings.groupQuestHints = not S.settings.groupQuestHints S.insights.groupAdvice = nil end,
            releaseLevel = function() S.insights.levelHold = nil F.ScheduleRefresh() end,
            clearCorrection = function(e) S.targetCorrections[e.quest.id][e.index] = nil F.ScheduleRefresh() end,
            rowAction = function(e, section)
                if section == "along" then
                    local q
                    for _, candidate in ipairs(S.eligibleQuests or {}) do if candidate.id == e.quest.id and candidate.readyToTurnIn then q = candidate break end end
                    if not q then return end
                    e.quest, e.xp = q, addon.QuestLog.GetTurnInXP(q)
                    local revised = addon.JourneyPlanning.InsertHandIn(S.insights.excursion, e, C_Map)
                    if revised then addon.ReviewPreparedOuting(revised)
                    elseif not S.insights.excursion or not S.insights.excursion.started then
                        addon.OpenExcursionFromArea(nil, false, {entries = {{quest = q, target = e.target, yards = e.yards}}})
                    end
                elseif section == "compare" then addon.OpenExcursionFromArea(e.areaKey)
                elseif section == "chains" then S.insights.expandedChains[e.chainID] = not S.insights.expandedChains[e.chainID]
                elseif section == "later" then S.insights.laterQuests[e.quest.id] = nil F.ScheduleRefresh() end
                if section == "hiddenOffers" then
                    S.insights.hiddenOffers[e.quest.id] = nil
                    S.insights.offerSuppressed[e.quest.id] = nil
                    if S.insights.excursion and S.insights.excursion.excludedOffers then S.insights.excursion.excludedOffers[e.quest.id] = nil end
                    F.ScheduleRefresh()
                end
                if section == "bags" and e.vendorIndex then table.remove(S.insights.knownVendors, e.vendorIndex) end
            end,
            saveVendor = function()
                if not (MerchantFrame and MerchantFrame.IsShown and MerchantFrame:IsShown() and GetMerchantNumItems) then return end
                local ok, count = pcall(GetMerchantNumItems)
                if not ok or type(count) ~= "number" or count < 1 then return end
                local id = C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
                local pos = id and C_Map.GetPlayerMapPosition and C_Map.GetPlayerMapPosition(id, "player")
                if not pos or (issecretvalue and issecretvalue(pos)) then return end
                local point = {mapID = id, x = pos.x, y = pos.y}
                if not addon.TravelSupport.ValidPoint(point) then return end
                local name = UnitName and UnitName("npc")
                S.insights.knownVendors[#S.insights.knownVendors + 1] = {point = point, name = type(name) == "string" and name or L.JourneyVendor}
                while #S.insights.knownVendors > 20 do table.remove(S.insights.knownVendors, 1) end
            end,
            reviewChanges = function()
                local p, snapshot = S.insights.excursion, S.navigationSnapshot or {}
                if not p then return end
                local area, seen = {entries = {}}, {}
                for index = p.index, #p.stops do
                    local stop = p.stops[index]
                    if stop.action == "accept" and not seen[stop.quest.id] then
                        local accepted
                        for _, q in ipairs(S.eligibleQuests or {}) do if q.id == stop.quest.id then accepted = true break end end
                        if not accepted and stop.quest.objectiveMarker then
                            area.entries[#area.entries + 1] = {quest = stop.quest, target = stop.quest.objectiveMarker, yards = stop.quest.journeyYards, pickup = true}
                            seen[stop.quest.id] = true
                        end
                    end
                    if stop.action ~= "accept" and not seen[stop.quest.id] then
                        local q
                        for _, candidate in ipairs(S.eligibleQuests or {}) do if candidate.id == stop.quest.id then q = candidate break end end
                        if q then
                            local m = snapshot.measurements and snapshot.measurements[q.id]
                            area.entries[#area.entries + 1] = {quest = q, target = m and (m.objectiveMarker or m.marker) or stop.target, yards = m and m.yards}
                            seen[q.id] = true
                        end
                    end
                end
                for _, e in ipairs(addon.AdventureSupport.Changes(p, snapshot, C_Map)) do
                    if not seen[e.quest.id] then area.entries[#area.entries + 1] = {quest = e.quest, target = e.target, yards = e.yards} seen[e.quest.id] = true end
                end
                addon.OpenExcursionFromArea(nil, false, area)
            end,
        }, mode)
    end

    function addon.GetLaterContext()
        local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
        local zone = mapID and addon.QuestLocation.GetZone(C_Map, Enum and Enum.UIMapType, mapID)
        local plan, ledger = S.insights.excursion, S.insights.roundLedger
        local source = plan and plan.started and plan or ledger
        if source and not source.journeyKey then source.journeyKey = tostring(GetServerTime and GetServerTime() or 0) .. ":" .. tostring(source) end
        return {mapID = zone or mapID, grouped = IsInGroup and IsInGroup() == true,
            roundToken = source and source.journeyKey,
            roundFinished = plan and plan.started and plan.index > #plan.stops or ledger and #ledger.steps > 0 and ledger.completed == #ledger.steps}
    end

    function addon.HideOffer(quest)
        if addon.DemoMode.IsActive() or not quest then return end
        local id, before = quest.id, addon.UndoHistory.Copy(S.insights.hiddenOffers[quest.id])
        S.insights.hiddenOffers[id] = {id = id, title = quest.title, level = quest.level}
        addon.Undo:Capture(L.OfferHide, function() return S.insights.hiddenOffers[id] end,
            function(value) S.insights.hiddenOffers[id] = value F.ScheduleRefresh() end, before, S.insights.hiddenOffers[id])
        F.ScheduleRefresh()
    end

    function addon.SkipOfferStep(plan, id, mode)
        if addon.DemoMode.IsActive() or (mode ~= "once" and mode ~= "later" and mode ~= "hide") then return false, L.ExcursionUnavailable end
        local quests, present = addon.QuestLog.Read(C_QuestLog), {}
        if not quests then return false, L.QuestLogUnavailable end
        for _, q in ipairs(quests) do present[q.id] = true end
        if C_QuestLog.IsOnQuest then for _, stop in ipairs(plan and plan.stops or {}) do
            local ok, accepted = pcall(C_QuestLog.IsOnQuest, stop.quest.id)
            if not ok then return false, L.QuestLogUnavailable end
            if accepted == true then present[stop.quest.id] = true end
        end end
        local before, hiddenBefore, laterBefore = addon.UndoHistory.Copy(plan), addon.UndoHistory.Copy(S.insights.hiddenOffers[id]), addon.UndoHistory.Copy(S.insights.laterQuests[id])
        local wasActive = plan == S.insights.excursion
        local ok, quest = addon.MixedQuestPlan.Skip(plan, id, present)
        if not ok then return false, L.OfferAlreadyAccepted end
        if mode == "hide" then S.insights.hiddenOffers[id] = {id = id, title = quest.title, level = quest.level}
        elseif mode == "later" then
            addon.JourneyPlanning.SetLater(S.insights.laterQuests, quest, quest.marker, "round", nil, addon.GetLaterContext())
        end
        local revision, index, receipts = plan.revision, plan.index, addon.UndoHistory.Copy(plan.receipts)
        local hiddenAfter, laterAfter = addon.UndoHistory.Copy(S.insights.hiddenOffers[id]), addon.UndoHistory.Copy(S.insights.laterQuests[id])
        local function CanUndo()
            if plan.revision ~= revision or plan.index ~= index or not addon.UndoHistory.Same(plan.receipts, receipts)
                or not addon.UndoHistory.Same(S.insights.hiddenOffers[id], hiddenAfter) or not addon.UndoHistory.Same(S.insights.laterQuests[id], laterAfter)
                or wasActive and S.insights.excursion ~= plan or C_QuestLog.IsOnQuest and C_QuestLog.IsOnQuest(id) then return false end
            return true
        end
        addon.Undo:Push(L.OfferSkipped, function()
            if not CanUndo() then return false end
            for key in pairs(plan) do plan[key] = nil end
            for key, value in pairs(addon.UndoHistory.Copy(before)) do plan[key] = value end
            S.insights.hiddenOffers[id], S.insights.laterQuests[id] = hiddenBefore, laterBefore
            F.ScheduleRefresh() return true
        end)
        addon.Undo.entries[#addon.Undo.entries].offerPlan = plan
        addon.Undo.entries[#addon.Undo.entries].offerValid = CanUndo
        if S.tracker then S.tracker.noticeMessage, S.tracker.noticeRemaining = L.OfferSkipped, 4 S.tracker:RefreshNotice() end
        F.ScheduleRefresh()
        return true, L.OfferSkipped
    end

    function addon.SkipCurrentOffer(id, mode)
        mode = mode or "once"
        local plan = S.insights.excursion
        for index = plan and plan.index or 1, plan and #plan.stops or 0 do
            local step = plan.stops[index]
            if step.action == "accept" and step.quest.id == id and not step.done then return addon.SkipOfferStep(plan, id, mode) end
        end
        if addon.DemoMode.IsActive() or (mode ~= "once" and mode ~= "later" and mode ~= "hide") then return false end
        local quest
        for _, offer in ipairs(S.nearbyOffers or {}) do if offer.id == id then quest = offer break end end
        if not quest or C_QuestLog.IsOnQuest and C_QuestLog.IsOnQuest(id) then return false end
        local function Read() return {hidden = S.insights.hiddenOffers[id], suppressed = S.insights.offerSuppressed[id], later = S.insights.laterQuests[id]} end
        local before = addon.UndoHistory.Copy(Read())
        S.insights.offerSuppressed[id] = true
        if mode == "hide" then S.insights.hiddenOffers[id] = {id = id, title = quest.title, level = quest.level}
        elseif mode == "later" then addon.JourneyPlanning.SetLater(S.insights.laterQuests, quest, quest.marker, "round", nil, addon.GetLaterContext()) end
        local after = addon.UndoHistory.Copy(Read())
        local function CanUndo()
            if not addon.UndoHistory.Same(Read(), after) or C_QuestLog.IsOnQuest and C_QuestLog.IsOnQuest(id) then return false end
            return true
        end
        addon.Undo:Push(L.OfferSkipped, function()
            if not CanUndo() then return false end
            S.insights.hiddenOffers[id], S.insights.offerSuppressed[id], S.insights.laterQuests[id] = before.hidden, before.suppressed, before.later
            F.ScheduleRefresh() return true
        end)
        addon.Undo.entries[#addon.Undo.entries].offerChoice = true
        addon.Undo.entries[#addon.Undo.entries].offerValid = CanUndo
        if S.tracker then S.tracker.noticeMessage, S.tracker.noticeRemaining = L.OfferSkipped, 4 S.tracker:RefreshNotice() end
        F.ScheduleRefresh() return true, L.OfferSkipped
    end

    function addon.OfferUndoAvailable(plan)
        local entry = addon.Undo.entries[#addon.Undo.entries]
        if not entry or not (entry.offerPlan or entry.offerChoice) or plan and entry.offerPlan ~= plan then return false end
        if entry.offerValid then local ok, value = pcall(entry.offerValid) return ok and value == true end
        return true
    end

    function addon.OpenPickupPlanning()
        local window = F.ShowPlanning()
        window:SelectMode("areas")
    end

    function addon.OpenDecisionPlanning(mode)
        local window = F.ShowPlanning()
        window:SelectMode(mode or "comparison")
    end
    function addon.RememberAdvisoryRound()
        if addon.DemoMode.IsActive() then print("FQN | " .. L.DemoReadOnly) return end
        S.insights.roundLedger = addon.OutingLedger.Start(S.insights.pickupPlanning, C_QuestLog.IsQuestFlaggedCompleted)
        print("FQN | " .. (S.insights.roundLedger and L.BriefRoundSaved or L.BriefRoundNone))
        F.ScheduleRefresh()
    end
    function addon.ForgetAdvisoryRound()
        S.insights.roundLedger = nil F.ScheduleRefresh()
    end
    function addon.ExportDecisionExplanation()
        local snapshot = S.navigationSnapshot or {}
        addon.ShowTextWindow("decision", addon.DecisionBrief.Report(snapshot, addon.DecisionBrief.Build(snapshot, S.insights.roundLedger, C_Map, Enum and Enum.UIMapType)),
            L.BriefReport, L.BriefReportPrivacy)
    end

    function addon.OpenWorkspace(mode)
        if addon.DemoMode.IsActive() then print("FQN | " .. L.DemoReadOnly) return end
        if S.workspace then return addon.ShowQuestWorkbench(S.workspace, mode) end
    end
    function addon.GetPlanningWorkspace() return S.workspace end
    function addon.ResumePlan()
        if addon.DemoMode.IsActive() then print("FQN | " .. L.DemoReadOnly) return end
        if S.workspace then S.workspace:Action("resume") addon.OpenWorkspace("tour") end
    end
    function addon.ForgetRememberedNavigation()
        if S.workspace then S.workspace.pending = nil S.workspace:Save() end
    end

    F.ShowFeedback = function()
        addon.ShowFeedbackManager({
            list = function()
                return addon.RecommendationFeedback.List(S.temporaryFeedback, addon.QuestLog.Read(C_QuestLog), S.questMeasurements, F.SessionTime())
            end,
            clear = F.ClearTemporaryFeedback,
            clearAll = function() F.ClearTemporaryFeedback() end,
        })
    end

    F.ShowProfiles = function() addon.ShowAppearanceProfiles(S.settings, addon.SettingsController.catalog) end
    function addon.OpenDetourTools()
        addon.ShowDetourTools({
            current = function()
                if S.temporaryDetour then return S.temporaryDetour end
                local id = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
                local position = id and C_Map.GetPlayerMapPosition and C_Map.GetPlayerMapPosition(id, "player")
                if position and not (issecretvalue and issecretvalue(position)) then
                    return addon.TemporaryDetour.New(id, position.x, position.y)
                end
            end,
            active = function() return S.temporaryDetour ~= nil end,
            start = function(point)
                if not addon.TemporaryDetour.IsOutdoor(C_Map, Enum and Enum.UIMapType, point.mapID)
                    or not addon.TemporaryDetour.Measure(C_Map, point) then return false end
                addon.PauseExcursion()
                point.questID = S.shownQuests and S.shownQuests[1] and S.shownQuests[1].id
                if S.workspace then S.workspace.plan.running = false S.workspace:Save() end
                S.temporaryDetour = point
                F.ScheduleRefresh() F.UpdateDirectionTicker()
                return true
            end,
            cancel = function()
                if S.temporaryDetour and S.temporaryDetour.tourReturn and S.workspace then S.workspace.plan.running = false S.workspace:Save() end
                S.temporaryDetour, S.detourMeasurement = nil, nil
                S.tracker:SetDetour(nil) F.ScheduleRefresh() F.UpdateDirection()
            end,
            map = function() if S.temporaryDetour then F.OpenRouteStop({target = S.temporaryDetour}) end end,
        })
    end
    F.ShowLevelChanges = function()
        local lines = {}
        for _, entry in ipairs(S.insights.levelReport and S.insights.levelReport.entries or {}) do
            lines[#lines + 1] = addon.UI.FormatQuestTitle(entry.quest) .. "\n"
                .. L["Difficulty_" .. entry.before] .. " -> " .. L["Difficulty_" .. entry.after]
        end
        addon.ShowTextWindow("levelChanges", #lines > 0 and table.concat(lines, "\n\n") or L.NoLevelChanges, L.LevelChangesTitle, L.LevelBetterHelp)
    end
end
