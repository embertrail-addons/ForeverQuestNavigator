return function(test, addon, equal, near)
    local mapAPI = { GetMapWorldSize = function() return 1000, 1000 end,
        GetPlayerMapPosition = function() return {x = .1, y = .1} end }
    local function Target(x, y) return {mapID = 10, x = x, y = y or .1, objectiveIndex = 1} end
    test("Shared stops group attainable nearby quests without chaining or counting turn-ins", function()
        local quests = {{id = 1, level = 30}, {id = 2, level = 30}, {id = 3, level = 30},
            {id = 4, level = 35}, {id = 5, level = 30, readyToTurnIn = true}, {id = 6, level = 30}}
        local measurements = {}
        for index, quest in ipairs(quests) do measurements[quest.id] = {yards = index * 20, marker = Target(.1 + (index - 1) * .06)} end
        measurements[4].marker, measurements[5].marker, measurements[6].marker = Target(.11), Target(.12), Target(.13)
        local groups = addon.PlanningInsights.Bundles(mapAPI, quests, measurements, 30, {[6] = {kind = "hard"}})
        equal(#groups, 1) equal(#groups[1].entries, 2)
        equal(groups[1].entries[1].quest.id, 1) equal(groups[1].entries[2].quest.id, 2)
    end)

    test("Turn-in rounds visit each known finisher once and forecast only known XP", function()
        local original = addon.QuestLog.GetTurnInXP
        addon.QuestLog.GetTurnInXP = function(quest) return quest.reward end
        local quests = {{id = 1, readyToTurnIn = true, reward = 300}, {id = 2, readyToTurnIn = true, reward = 400},
            {id = 3, readyToTurnIn = true}, {id = 4, readyToTurnIn = true}, {id = 5, readyToTurnIn = false}}
        local measurements = {[1] = {yards = 100, marker = Target(.2)}, [2] = {yards = 200, marker = Target(.3)},
            [3] = {yards = 300, marker = Target(.4)}}
        local tour = addon.PlanningInsights.TurnIns(mapAPI, quests, measurements, 650)
        addon.QuestLog.GetTurnInXP = original
        equal(#tour.stops, 3) near(tour.total, 300)
        equal(tour.unknown, 1) equal(tour.xp, 700) equal(tour.unknownXP, 1) equal(tour.levelUpAt, 2)
        near(tour.stops[1].leg, 100) near(tour.stops[2].leg, 100)
        local seen = {}
        for _, stop in ipairs(tour.stops) do assert(not seen[stop.quest.id]) seen[stop.quest.id] = true end
    end)

    test("Turn-in rounds bound work and exclude temporarily blocked finishers", function()
        local quests, measurements = {}, {}
        for id = 1, 12 do
            quests[id] = {id = id, readyToTurnIn = true}
            measurements[id] = {yards = id * 10, marker = Target(.1 + id * .01)}
        end
        local tour = addon.PlanningInsights.TurnIns(mapAPI, quests, measurements, nil, {[1] = {}})
        equal(#tour.stops, 8) equal(tour.omitted, 3)
        for _, stop in ipairs(tour.stops) do assert(stop.quest.id ~= 1) end
        local unknown = addon.PlanningInsights.TurnIns({}, quests, {}, nil)
        equal(#unknown.stops, 0) equal(unknown.unknown, 12)
    end)

    test("Temporary feedback expires and releases on objective or turn-in stage changes", function()
        local store, quest = {}, {id = 1, level = 30}
        local measured = {marker = Target(.2)}
        addon.RecommendationFeedback.Set(store, quest, measured, "blocked", 10)
        local entry, penalty = addon.RecommendationFeedback.Get(store, quest, measured, 609)
        equal(entry.kind, "blocked") equal(penalty, 1200)
        equal(addon.RecommendationFeedback.Get(store, quest, nil, 609).kind, "blocked")
        equal(addon.RecommendationFeedback.Get(store, quest, measured, 610), nil)
        addon.RecommendationFeedback.Set(store, quest, measured, "hard", 20)
        quest.readyToTurnIn = true
        equal(addon.RecommendationFeedback.Get(store, quest, measured, 21), nil)
        quest.readyToTurnIn = false
        addon.RecommendationFeedback.Set(store, quest, measured, "blocked", 30)
        measured.marker.objectiveIndex = 2
        equal(addon.RecommendationFeedback.Get(store, quest, measured, 31), nil)
        equal(next(store), nil)
    end)

    test("Feedback changes automatic ranking and remains reproducible offline", function()
        local quests = {{id = 1, level = 30}, {id = 2, level = 30}}
        local store = {}
        addon.RecommendationFeedback.Set(store, quests[1], {marker = Target(.2)}, "blocked", 0)
        local input = {mapAPI = mapAPI, questAPI = {}, eligibleQuests = quests, playerLevel = 30,
            questMarkers = {[1] = {Target(.2)}, [2] = {Target(.6)}}, measurableQuestIDs = {1, 2},
            previousObjectives = {}, avoidedObjectives = {}, savedAccessPoints = {}, passedAccessPoints = {},
            turnInLocations = {}, feedback = store, now = 1}
        local snapshot = addon.NavigationController.Compute(input)
        equal(snapshot.ranked[1].id, 2) equal(snapshot.feedback[1].kind, "blocked")
        equal(addon.RegressionFixture.Replay(addon.RegressionFixture.Capture(quests, snapshot)), true)
        input.now = 601
        snapshot = addon.NavigationController.Compute(input)
        equal(snapshot.ranked[1].id, 1) equal(snapshot.feedback[1], nil)
    end)

    test("Offer context counts distinct active quests and requires a known target for recommendations", function()
        local quests = {{id = 1}, {id = 2}}
        local measurements = {[1] = {yards = 300, marker = Target(.4)}, [2] = {yards = 350, marker = Target(.45)}}
        local offers = {{id = 8, level = 30, levelPenalty = 0, yards = 100, marker = Target(.2),
            objectiveMarker = Target(.42), objectiveYards = 220, journeyYards = 320},
            {id = 9, level = 30, levelPenalty = 0, yards = 10, marker = Target(.11)}}
        addon.PlanningInsights.AnnotateOffers(mapAPI, offers, quests, measurements, quests[1])
        equal(offers[1].id, 8) equal(offers[1].overlapCount, 2)
        equal(offers[1].onApproach, true) equal(offers[1].recommended, true)
        equal(addon.PlanningInsights.OfferReason(offers[1]), "Target fits 2 active quests")
        assert(not offers[2].recommended) equal(offers[2].overlapCount, 0)
        measurements[1].objectiveMarker = Target(.4)
        addon.PlanningInsights.AnnotateOffers(mapAPI, offers, quests, measurements, quests[1])
        equal(offers[1].onApproach, false)
    end)

    test("Route comparison only claims an actual positive saving for a different selected route", function()
        local selected, other = {id = 1, title = "B"}, {id = 2, title = "A"}
        local snapshot = {ranked = {other}, decisionSaving = 200, decision = "followUp"}
        local text = addon.PlanningInsights.Compare(snapshot, selected)
        assert(text:find("200 yd", 1, true)) assert(text:find("same known stops", 1, true))
        snapshot.decisionSaving = nil
        assert(not addon.PlanningInsights.Compare(snapshot, selected):find("saves", 1, true))
        equal(addon.PlanningInsights.Compare(snapshot, selected, true), addon.L.ComparisonManual)
    end)

    test("Settings search reaches advanced options and treats search characters literally", function()
        local entries = {{key = "opacity", name = "Opacity", help = "Background", basic = true},
            {key = "lock", name = "Größe [Fenster]", help = "Lock", basic = false}}
        equal(#addon.FilterSettings(entries, "", false), 1)
        equal(#addon.FilterSettings(entries, "", true), 2)
        equal(addon.FilterSettings(entries, "GRÖẞE", false)[1].key, "lock")
        equal(#addon.FilterSettings(entries, "[", false), 1)
        equal(#addon.FilterSettings(entries, ".*", true), 0)
    end)
end
