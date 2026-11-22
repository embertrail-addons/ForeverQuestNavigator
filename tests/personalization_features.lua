return function(test, addon, equal, near)
    local mapAPI = {GetMapWorldSize = function() return 1000, 1000 end,
        GetPlayerMapPosition = function() return {x = .1, y = .1} end}
    local function Point(x, index) return {mapID = 10, x = x, y = .1, objectiveIndex = index or 1} end
    test("Camp alternatives stay on the same goal, reject an area temporarily and do not skip goals", function()
        local quest, store = {id = 1, level = 30}, {}
        local current = {marker = Point(.2)}
        local markers = {Point(.2), Point(.25), Point(.5), Point(.6, 2)}
        local nextPoint = addon.CampAlternatives.Switch(mapAPI, quest, current, markers, store, 10)
        near(nextPoint.x, .5) equal(nextPoint.objectiveIndex, 1)
        local filtered = addon.CampAlternatives.Filter(mapAPI, {[1] = markers}, store, 11)
        equal(#filtered[1], 2) near(filtered[1][1].x, .5) equal(filtered[1][2].objectiveIndex, 2)
        equal(#markers, 4)
        local unknown = addon.CampAlternatives.Filter(mapAPI, {[1] = {{mapID = 10, x = .2, y = .1}}}, store, 11)
        equal(#unknown[1], 0)
        current.marker = Point(.5)
        equal(addon.CampAlternatives.Switch(mapAPI, quest, current, markers, store, 12), nil)
        equal(#store[1], 1)
        filtered = addon.CampAlternatives.Filter(mapAPI, {[1] = markers}, store, 610)
        equal(#filtered[1], 4) equal(store[1], nil)
        quest.readyToTurnIn = true
        equal(addon.CampAlternatives.Find(mapAPI, quest, current, markers, store, 611), nil)
    end)

    test("Alternative navigation keeps an objective lock and bypasses its old saved access without deleting it", function()
        local quest, current, camps = {id = 1, level = 30}, {marker = Point(.2)}, {}
        local markers = {Point(.2), Point(.5), Point(.11, 2)}
        addon.CampAlternatives.Switch(mapAPI, quest, current, markers, camps, 0)
        local saved = {}
        addon.TravelSupport.SaveAccess(saved, 1, Point(.2), Point(.15), "Gate")
        local snapshot = addon.NavigationController.Compute({mapAPI = mapAPI, questAPI = {}, playerLevel = 30,
            questMarkers = {[1] = markers}, measurableQuestIDs = {1}, eligibleQuests = {quest}, previousObjectives = {},
            avoidedObjectives = {}, objectiveLock = {questID = 1, index = 1}, savedAccessPoints = saved,
            passedAccessPoints = {}, turnInLocations = {}, campAvoidance = camps, now = 1})
        equal(snapshot.objectiveLock.index, 1)
        near(snapshot.measurements[1].marker.x, .5)
        equal(snapshot.measurements[1].objectiveMarker, nil)
        assert(saved[1][1]) equal(quest.failed, nil)
    end)

    test("Capacity uses authoritative quest counts and never guesses missing or inconsistent capacity", function()
        local api = {GetNumQuestLogEntries = function() return 40, 25 end, GetMaxNumQuestsCanAccept = function() return 25 end}
        local capacity = addon.QuestCapacity.Read(api)
        equal(capacity.full, true) equal(capacity.free, 0) equal(capacity.used, 25)
        api.GetNumQuestLogEntries = function() return 40, 23 end
        equal(addon.QuestCapacity.Read(api).free, 2)
        api.GetMaxNumQuestsCanAccept = nil
        equal(addon.QuestCapacity.Read(api), nil)
        equal(addon.QuestCapacity.Read(api, 25).full, false)
        api.GetNumQuestLogEntries = function() return 40 end
        equal(addon.QuestCapacity.Read(api, 25), nil)
        equal(addon.QuestCapacity.FromCount(26, nil, 25), nil)
    end)

    test("Full logs suppress offer highlights without hiding offers or inventing target positions", function()
        local offers = {{id = 8, level = 30, levelPenalty = 0, yards = 10, marker = Point(.11),
            objectiveMarker = Point(.2), objectiveYards = 90, journeyYards = 100}}
        addon.PlanningInsights.AnnotateOffers(mapAPI, offers, {}, {}, nil, {full = true})
        equal(#offers, 1) equal(offers[1].capacityFull, true) assert(not offers[1].recommended)
        addon.PlanningInsights.AnnotateOffers(mapAPI, offers, {}, {}, nil, {full = false})
        assert(not offers[1].recommended) -- A close pickup alone is not a useful combination.
    end)

    test("A full log gently favors a nearby unblocked turn-in and exports that allowance", function()
        local quests = {{id = 1, level = 30}, {id = 2, level = 30, readyToTurnIn = true}}
        local snapshot = addon.NavigationController.Compute({mapAPI = mapAPI, questAPI = {}, playerLevel = 30,
            questMarkers = {[1] = {Point(.2)}, [2] = {Point(.25)}}, measurableQuestIDs = {1, 2}, eligibleQuests = quests,
            previousObjectives = {}, avoidedObjectives = {}, savedAccessPoints = {}, passedAccessPoints = {},
            turnInLocations = {}, capacity = {full = true}, now = 1})
        equal(snapshot.ranked[1].id, 2) equal(snapshot.adjustments[2], -100)
        equal(addon.RegressionFixture.Replay(addon.RegressionFixture.Capture(quests, snapshot)), true)
    end)

    test("Profile previews are side-effect free and applying uses controls for display keys only", function()
        local settings = {detailMode = "detailed", opacityPercent = 35, showQuestXP = true, language = "deDE",
            manualQuestID = 9, questieOfferRadius = 700, x = 30, skippedQuests = {[5] = true}}
        local calls, catalog = 0, {}
        for _, key in ipairs({"detailMode", "opacityPercent", "showQuestXP", "language", "questieOfferRadius"}) do
            local captured = key
            catalog[#catalog + 1] = {key = key, name = key, control = {SetValue = function(_, value) settings[captured] = value calls = calls + 1 end}}
        end
        local changes = addon.AppearanceProfiles.Changes("minimal", settings, catalog)
        equal(#changes, 3) equal(settings.opacityPercent, 35) equal(calls, 0)
        equal(addon.AppearanceProfiles.Apply("minimal", settings, catalog), 3)
        equal(settings.detailMode, "compact") equal(settings.opacityPercent, 80) equal(settings.showQuestXP, false)
        equal(settings.language, "deDE") equal(settings.manualQuestID, 9) equal(settings.questieOfferRadius, 700)
        equal(settings.x, 30) equal(settings.skippedQuests[5], true) equal(calls, 3)
        equal(addon.AppearanceProfiles.Apply("not a profile", settings, catalog), 0)
    end)

    test("Feedback management lists remaining lifetime, drops expired/removed entries and leaves skips alone", function()
        local quests = {{id = 1}, {id = 2}}
        local store, skips = {}, {[1] = true}
        addon.RecommendationFeedback.Set(store, quests[1], nil, "hard", 0)
        addon.RecommendationFeedback.Set(store, quests[2], nil, "blocked", 100)
        local entries = addon.RecommendationFeedback.List(store, quests, {}, 599)
        equal(#entries, 2) equal(entries[1].id, 1) equal(entries[1].seconds, 1)
        entries = addon.RecommendationFeedback.List(store, quests, {}, 601)
        equal(#entries, 1) equal(entries[1].kind, "blocked") equal(skips[1], true)
        equal(#addon.RecommendationFeedback.List(store, nil, {}, 602), 0) assert(store[2])
        equal(#addon.RecommendationFeedback.List(store, {}, {}, 602), 0) equal(next(store), nil)
    end)
end
