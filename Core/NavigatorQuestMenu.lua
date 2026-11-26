local _, addon = ...
local L = addon.L
local integration = addon.QuestieIntegration
-- Quest context menu of the navigator and quest log.
-- Installed by Core/Bootstrap.lua with the shared navigator state S and functions F.
addon.NavigatorQuestMenu = {}

function addon.NavigatorQuestMenu.Install(S, F)
    function F.OpenQuestMenu(owner, questID, isOffer)
        if not (questID and MenuUtil and MenuUtil.CreateContextMenu) then return end
        local measured = S.questMeasurements and S.questMeasurements[questID]
        local target = measured and (measured.objectiveMarker or measured.marker)
        local ready = C_QuestLog.IsComplete and C_QuestLog.IsComplete(questID)
        local key = target and (target.objectiveIndex or 0)
        local function Save(point, name)
            local metric = target and addon.QuestLocation.GetDistanceMetric(C_Map, target)
            if not (addon.TravelSupport.ValidPoint(point) and metric and metric(target, point)
                and addon.QuestLocation.IsOutdoorMap(C_Map, Enum and Enum.UIMapType, point.mapID, S.questTargetMaps)) then
                print(L.AccessUnavailable) return
            end
            local before = addon.UndoHistory.Copy(S.savedAccessPoints[questID] and S.savedAccessPoints[questID][key])
            if addon.TravelSupport.SaveAccess(S.savedAccessPoints, questID, target, point, name) then
                for _, quest in ipairs(S.eligibleQuests or {}) do
                    if quest.id == questID then S.savedAccessPoints[questID][key].questTitle = quest.title break end
                end
                S.passedAccessPoints[questID .. ":" .. key] = nil
                F.RecordAccessChange(questID, key, before)
                S.outing = nil
                print(L.AccessSaved)
                F.ScheduleRefresh()
            end
        end
        local chosen
        for _, quest in ipairs((isOffer and S.nearbyOffers or S.eligibleQuests) or {}) do
            if quest.id == questID then chosen = quest break end
        end
        local function Submenu(menu, label)
            return menu:CreateButton(label) or menu
        end
        local function Feedback(kind)
            local before = addon.UndoHistory.Copy(S.temporaryFeedback)
            if kind == "area" then
                addon.RecommendationFeedback.SetArea(S.temporaryFeedback, C_Map, S.eligibleQuests, S.questMeasurements or {}, target, F.SessionTime())
            else
                addon.RecommendationFeedback.Set(S.temporaryFeedback, chosen, S.questMeasurements and S.questMeasurements[questID], kind, F.SessionTime())
            end
            if addon.Undo then addon.Undo:Capture(L.FeedbackSubmenu, function() return S.temporaryFeedback end, function(value)
                S.temporaryFeedback = value S.outing = nil F.ScheduleRefresh()
            end, before, S.temporaryFeedback) end
            S.outing = nil
            F.ScheduleRefresh()
        end
        MenuUtil.CreateContextMenu(owner, function(_, menu)
            menu:CreateTitle(L.QuestActionsMenu)
            menu:SetScrollMode(260)
            menu:CreateButton(L.OpenQuestMap, function() if isOffer then F.OpenOfferMap(questID) else F.OpenQuestMap(questID) end end)
            if isOffer and chosen then
                menu:CreateButton(L.OfferSkip, function() addon.SkipCurrentOffer(questID, "once") end)
                menu:CreateButton(L.OfferLater, function() addon.SkipCurrentOffer(questID, "later") end)
                menu:CreateButton(L.OfferHide, function() addon.SkipCurrentOffer(questID, "hide") end)
            end
            if not isOffer and F.CanPinQuest(questID) then
                menu:CreateButton(S.manualQuestID == questID and L.ClearActiveQuest or L.SetActiveQuest,
                    function() if S.manualQuestID == questID then F.SelectQuest(nil) else F.SelectQuest(questID) end end)
                local priorityMenu = Submenu(menu, L.PriorityMenu)
                if chosen and not chosen.readyToTurnIn then
                    priorityMenu:CreateButton(L.PriorityUntilComplete, function() F.ApplyQuestAction("prioritize", {id = questID}) end)
                end
                priorityMenu:CreateButton(L.PriorityUntilTurnIn, function() F.ApplyQuestAction("prioritize", {id = questID, turnIn = true}) end)
            end
            -- Skipping an accepted quest is a top-level action, not hidden in the details panel.
            if not isOffer and chosen then
                menu:CreateButton(L.SkipQuest, function() F.SkipQuest(chosen) end)
            end
            local more = Submenu(menu, L.MoreActions)
            if chosen then
                local later = Submenu(more, L.JourneyLaterMenu)
                for _, when in ipairs({"round", "visit", "group"}) do
                    local trigger = when
                    later:CreateButton(L["JourneyLater_" .. trigger], function()
                        if addon.DemoMode.IsActive() then return end
                        local point = isOffer and chosen.marker or target
                        local zone = point and addon.QuestLocation.GetZone(C_Map, Enum and Enum.UIMapType, point.mapID)
                        addon.JourneyPlanning.SetLater(S.insights.laterQuests, chosen, point, trigger, zone or point and point.mapID, addon.GetLaterContext())
                        F.ScheduleRefresh()
                    end)
                end
                later:CreateButton(L.Adventure_later, function() addon.OpenAdventure("later") end)
            end
            more:CreateButton(L.EditQuestNote, function() addon.OpenQuestNote(questID, isOffer) end)
            if not isOffer and S.navigationSnapshot and S.navigationSnapshot.camps and S.navigationSnapshot.camps[questID] then
                more:CreateButton(L.CampChoices, function() addon.OpenCampChoices(questID) end)
            end
            if not isOffer and S.shownQuests and S.shownQuests[1] and S.shownQuests[1].id == questID then
                more:CreateButton(S.heldQuest and S.heldQuest.id == questID and L.ReleaseQuest or L.HoldQuest, F.ToggleQuestHold)
            end
            more:CreateButton(S.questNotes[questID] and L.UnmarkQuest or L.MarkQuest, function()
                local point = isOffer and chosen and chosen.marker or target
                addon.QuestTools.ToggleNote(S.questNotes, questID, chosen and chosen.title, point, isOffer)
                S.insights.noteRevision = (S.insights.noteRevision or 0) + 1 F.ScheduleRefresh()
                addon.RefreshQuestNotepad()
            end)
            if chosen and not isOffer and addon.CampAlternatives.Find(C_Map, chosen, measured, S.questMarkers[questID], S.campAvoidance, F.SessionTime()) then
                more:CreateButton(L.AnotherCamp, function() F.SwitchCamp(questID) end)
            end
            more:CreateButton(L.PlanningOverview, function() F.ShowPlanning() end)
            if chosen and not isOffer then
                menu:CreateButton(L.AdventureBlockedAction, function()
                    Feedback("blocked") addon.PauseExcursion() addon.OpenAdventure("blocked", questID)
                end)
                local tourMenu = Submenu(menu, L.MyTour)
                tourMenu:CreateButton(L.AddToTour, function()
                    if S.workspace then S.workspace:Action("add", {quest = chosen}) addon.OpenWorkspace("tour") end
                end)
                tourMenu:CreateButton(L.MyTour, function() addon.OpenWorkspace("tour") end)
            end
            local feedbackMenu = Submenu(more, L.FeedbackSubmenu)
            if chosen and not isOffer then
                feedbackMenu:CreateButton(L.FeedbackHard, function() Feedback("hard") end)
                feedbackMenu:CreateButton(L.FeedbackBlocked, function() Feedback("blocked") end)
                feedbackMenu:CreateButton(L.FeedbackInconvenient, function() Feedback("inconvenient") end)
                feedbackMenu:CreateButton(L.FeedbackNoMobs, function() Feedback("empty") end)
                feedbackMenu:CreateButton(L.FeedbackGroup, function() Feedback("group") end)
                feedbackMenu:CreateButton(L.FeedbackAccess, function() Feedback("access") end)
                feedbackMenu:CreateButton(L.FeedbackArea, function() Feedback("area") end)
                if S.temporaryFeedback[questID] then
                    feedbackMenu:CreateButton(L.FeedbackClear, function() F.ClearTemporaryFeedback(questID) end)
                end
                if S.campAvoidance[questID] then
                    feedbackMenu:CreateButton(L.RestoreCamps, function() S.campAvoidance[questID] = nil S.outing = nil F.ScheduleRefresh() end)
                end
            end
            feedbackMenu:CreateButton(L.FeedbackManager, function() F.ShowFeedback() end)
            if chosen and not isOffer then
                if chosen.readyToTurnIn or target and target.objectiveIndex then more:CreateButton(L.AdventureCorrectHere, function()
                    if addon.DemoMode.IsActive() or IsInInstance and IsInInstance() then return end
                    local mapID = C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
                    local pos = mapID and C_Map.GetPlayerMapPosition and C_Map.GetPlayerMapPosition(mapID, "player")
                    if pos and not (issecretvalue and issecretvalue(pos)) and addon.AdventureSupport.Correct(S.targetCorrections, chosen,
                        {mapID = mapID, x = pos.x, y = pos.y}, target and target.objectiveIndex) then
                        F.ScheduleRefresh()
                    end
                end) end
                if S.targetCorrections[questID] then more:CreateButton(L.AdventureCorrections, function() addon.OpenAdventure("corrections") end) end
            end
            if not (isOffer or ready or not target) then
                local access = Submenu(more, L.AccessSubmenu)
                local saved = addon.TravelSupport.GetAccess(S.savedAccessPoints, questID, target, C_Map)
                local steps = saved and addon.TravelSupport.AccessSteps(saved)
                access:CreateButton(steps and #steps > 1 and L.ReplaceAccessHere or L.SaveAccessHere, function()
                    if IsInInstance and IsInInstance() then print(L.AccessUnavailable) return end
                    local mapID = C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
                    local point = mapID and C_Map.GetPlayerMapPosition and C_Map.GetPlayerMapPosition(mapID, "player")
                    Save(point and {mapID = mapID, x = point.x, y = point.y}, L.SavedAccess)
                end)
                if saved then
                    if #steps < 8 then access:CreateButton(L.AppendAccessHere, function()
                        local before = addon.UndoHistory.Copy(S.savedAccessPoints[questID][key])
                        if IsInInstance and IsInInstance() then print(L.AccessUnavailable) return end
                        local mapID = C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
                        local position = mapID and C_Map.GetPlayerMapPosition and C_Map.GetPlayerMapPosition(mapID, "player")
                        local point = position and {mapID = mapID, x = position.x, y = position.y}
                        if not point or not addon.QuestLocation.IsOutdoorMap(C_Map, Enum and Enum.UIMapType, mapID, S.questTargetMaps)
                            or not addon.TravelSupport.AppendAccess(S.savedAccessPoints, questID, target, point, C_Map) then
                            print(L.AccessAppendUnavailable) return
                        end
                        local route = S.savedAccessPoints[questID][key]
                        if S.flight.active then S.passedAccessPoints[questID .. ":" .. key] = nil
                        else S.passedAccessPoints[questID .. ":" .. key] = {entry = route, revision = route.revision,
                            index = #addon.TravelSupport.AccessSteps(route) + 1} end
                        S.outing = nil
                        F.RecordAccessChange(questID, key, before)
                        addon.RefreshAccessManager() F.ScheduleRefresh()
                    end) end
                    access:CreateButton(L.ReuseAccess, function()
                        S.passedAccessPoints[questID .. ":" .. key] = nil S.outing = nil F.ScheduleRefresh()
                    end)
                    access:CreateButton(L.ClearAccess, function()
                        local before = addon.UndoHistory.Copy(S.savedAccessPoints[questID][key])
                        S.savedAccessPoints[questID][key] = nil
                        F.RecordAccessChange(questID, key, before)
                        S.passedAccessPoints[questID .. ":" .. key] = nil S.outing = nil F.ScheduleRefresh()
                    end)
                end
                for _, hint in ipairs(addon.QuestieRoutes.GetAccessHints(C_Map, Enum and Enum.UIMapType, S.questTargetMaps or {}, questID, target)) do
                    local point, text = hint.point, hint.text
                    access:CreateButton(L.AccessHintMap:format(text), function() F.OpenRouteStop({target = point}) end)
                    access:CreateButton(L.UseAccessHint:format(text), function() Save(point, text) end)
                end
            end
            local diagnostic = Submenu(more, L.SettingsDiagnostics)
            diagnostic:CreateButton(L.PositionReport, function() F.ShowTargetReport(questID, isOffer) end)
        end)
    end
end
