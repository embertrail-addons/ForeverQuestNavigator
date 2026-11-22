return function(test, addon, equal)
    local function Point(x) return {mapID = 1, x = x, y = .2, objectiveIndex = 1} end
    local function Quest(id, ready) return {id = id, title = "Quest " .. id, level = 30, readyToTurnIn = ready} end
    local api = {GetMapWorldSize = function() return 10000, 10000 end}
    test("Return advice clusters actual finishers, including dungeon hand-ins, rather than whole zones", function()
        local a, b, c = Quest(1, true), Quest(2, true), Quest(3, true) b.special = true
        local m = {[1] = {marker = Point(.1), yards = 900}, [2] = {marker = Point(.12), yards = 1100}, [3] = {marker = Point(.9), yards = 1500}}
        local brief = addon.DecisionBrief.Build({ranked = {a, b, c}, measurements = m, playerLevel = 30,
            knownRewards = {[1] = 100, [2] = 200}, chains = {{quest = a, known = true}}}, nil, api)
        equal(#brief.returnAdvice.stops, 2) equal(brief.xp, 300) equal(brief.unknownXP, 0)
        equal(brief.returnAdvice.followUps, 1) equal(brief.returnAdvice.stops[2].quest.id, 2)
    end)
    test("No invented return cluster when coordinates or a distance transform are missing", function()
        local a, b = Quest(1, true), Quest(2, true)
        local brief = addon.DecisionBrief.Build({ranked = {a, b}, measurements = {[1] = {marker = Point(.1), yards = 100}},
            feedback = {[2] = {kind = "later"}}}, nil, {})
        equal(brief.returnAdvice, nil) equal(#brief.closing, 1)
        equal(addon.DecisionBrief.Build({ranked = {a, b}}, nil, api).returnAdvice, nil)
    end)
    test("Tour cards count known returns independently from potential XP", function()
        local a = Quest(1)
        local p = addon.PickupPlanning.Build(api, {}, {a}, {[1] = {marker = Point(.1), yards = 500}}, a,
            {free = 4}, 30, nil, nil, nil, function() return nil end, {[1] = Point(.8)})
        equal(p.areas[1].handIns, 1) equal(p.areas[1].unknownXP, 1) equal(p.areas[1].missingReturns, 0)
        local q = addon.PickupPlanning.Build(api, {}, {a}, {[1] = {marker = Point(.1), yards = 500}}, a, nil, 30)
        equal(q.areas[1].handIns, 0) equal(q.areas[1].missingReturns, 1)
    end)
    test("An attractive nearby pickup with a large detour loses its strong highlight", function()
        local a = Quest(1)
        local offer = Quest(2) offer.marker = Point(.5) offer.objectiveMarker = Point(.1)
        offer.yards, offer.journeyYards, offer.objectiveYards, offer.score = 500, 4500, 4000, 500
        offer.recommended = true
        addon.PickupPlanning.Build(api, {offer}, {a}, {[1] = {marker = Point(.1), yards = 1000}}, a, {free = 5}, 30)
        equal(offer.planClass, "detour") assert(not offer.recommended)
    end)
    test("Recaps use actual deduplicated hand-in rewards, including zero, and never arrival XP", function()
        local a, b = Quest(1, true), Quest(2, true)
        local plan = {stops = {{quest = a, target = Point(.1), action = "turnIn"}, {quest = b, target = Point(.2), action = "turnIn"}},
            index = 1, running = false}
        equal(addon.ExcursionPlan.Review(plan), nil)
        addon.ExcursionPlan.HandedIn(plan, 1, 999) equal(plan.receipts, nil)
        assert(addon.ExcursionPlan.Start(plan, {a, b}))
        addon.ExcursionPlan.Sync(plan, {a, b}) equal(addon.ExcursionPlan.Review(plan).completed, 0)
        addon.ExcursionPlan.HandedIn(plan, 1, 0) addon.ExcursionPlan.HandedIn(plan, 1, 999)
        addon.ExcursionPlan.HandedIn(plan, 55, 999) addon.ExcursionPlan.Sync(plan, {b})
        local review = addon.ExcursionPlan.Review(plan)
        equal(review.completed, 1) equal(review.xp, 0) equal(review.remaining, 1) equal(review.unknownXP, 0)
        addon.ExcursionPlan.HandedIn(plan, 2) addon.ExcursionPlan.Sync(plan, {})
        review = addon.ExcursionPlan.Review(plan)
        equal(review.completed, 2) equal(review.unknownXP, 1) equal(review.finished, true) equal(review.remaining, 0)
        plan.reviewDismissed = true equal(addon.ExcursionPlan.Review(plan), nil)
    end)
    test("Small distance fluctuations keep recommendations stable and a clear advantage changes them", function()
        local a, b = Quest(1), Quest(2)
        local previous = {a, b}
        for offset = 1, 10 do
            local ranked = addon.QuestPrioritizer.RankByDistance({a, b}, {[1] = {yards = 100}, [2] = {yards = 100 - offset}}, previous, 30)
            equal(ranked[1].id, 1) previous = ranked
        end
        equal(addon.QuestPrioritizer.RankByDistance({a, b}, {[1] = {yards = 100}, [2] = {yards = 40}}, previous, 30)[1].id, 2)
    end)
    test("Closer alternatives get an explicit caveat without invented savings", function()
        local a, b = Quest(1), Quest(2)
        local text = addon.DecisionBrief.Compare({playerLevel = 30, measurements = {[1] = {yards = 300}, [2] = {yards = 100}}}, a, b)
        assert(text:find(addon.L.BriefCloserAlternative, 1, true))
        assert(addon.Recommendation.Short({playerLevel = 30}, a):find(addon.L.Difficulty_yellow, 1, true))
    end)
end
