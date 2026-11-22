return function(test, addon, equal)
    local J = addon.JourneyPlanning
    local function Q(id, ready) return {id = id, title = "Quest " .. id, level = 30, readyToTurnIn = ready} end
    local function P(x, map) return {mapID = map or 1, x = x, y = .2, objectiveIndex = 1} end
    local api = {GetMapWorldSize = function() return 1000, 1000 end}
    test("Along-route hand-ins disclose detours, exclude blocked quests and don't invent cross-zone transforms", function()
        local a, b, c = Q(1), Q(2, true), Q(3, true)
        local s = {view = {quest = a}, ranked = {a, b, c}, measurements = {
            [1] = {marker = P(.8), yards = 800}, [2] = {marker = P(.4), yards = 400}, [3] = {marker = P(.4, 2), yards = 400}}}
        local rows = J.Along(s, api) equal(#rows, 1) equal(rows[1].quest.id, 2) equal(rows[1].detour, 0)
        s.feedback = {[2] = {}} equal(#J.Along(s, api), 0)
        s.feedback = nil s.measurements[2].yards = 1000 equal(#J.Along(s, api), 0)
        equal(#J.Along(s, {}), 0)
    end)
    test("Adding a hand-in creates an independent reviewed plan and repeatable history cannot auto-complete it", function()
        local a, b = Q(1), Q(2, true)
        local p = {started = true, running = true, index = 1, xp = 100, rewards = {[1] = 100}, receipts = {},
            stops = {{quest = a, action = "objective", target = P(.8)}}}
        local candidate = J.InsertHandIn(p, {quest = b, target = P(.4), xp = 200, yards = 400}, api)
        equal(#p.stops, 1) equal(p.running, true) equal(#candidate.stops, 2) equal(candidate.running, false)
        candidate.stops[2].done = true equal(p.stops[1].done, nil)
        assert(addon.ExcursionPlan.Start(candidate, {a, b}, nil, function() return true end))
        addon.ExcursionPlan.Sync(candidate, {a, b}, nil, function() return true end) equal(candidate.index, 1)
        addon.ExcursionPlan.HandedIn(candidate, 2, 200) addon.ExcursionPlan.Sync(candidate, {a}, nil, function() return true end)
        equal(candidate.index, 3) equal(addon.ExcursionPlan.Review(candidate).xp, 200)
        equal(next(p.receipts), nil) equal(J.InsertHandIn(candidate, {quest = a, target = P(.8)}, api), nil)
    end)
    test("Bag checks exclude specialized slots and partial/error reads stay unknown", function()
        local state = J.Bags({GetContainerNumFreeSlots = function(bag) return bag == 0 and 2 or 20, bag == 0 and 0 or 8 end}, 4)
        equal(state.free, 2) equal(state.low, true)
        equal(J.Bags(nil).known, false)
        equal(J.Bags({GetContainerNumFreeSlots = function(bag) if bag > 0 then error("unavailable") end return 2, 0 end}).known, false)
        equal(J.Bags({GetContainerNumFreeSlots = function() return 4, 0 end}, 0).low, false)
    end)
    test("Later reminders survive plain saved tables and become relevant only in their contexts", function()
        local saved = {}
        assert(J.SetLater(saved, Q(1), P(.2), "round", 1)) assert(J.SetLater(saved, Q(2), P(.3), "visit", 2))
        assert(J.SetLater(saved, Q(3), nil, "group")) equal(J.SetLater(saved, Q(4), nil, "invalid"), false)
        equal(J.Later(saved, {mapID = 1})[1].due, false)
        local rows = J.Later(saved, {mapID = 2, grouped = true}) equal(rows[1].quest.id, 2) equal(rows[2].quest.id, 3)
        equal(J.Later(saved, {roundFinished = true})[1].quest.id, 1)
        local done = J.Later(saved, {roundFinished = true}, {IsQuestFlaggedCompleted = function() return true end})
        equal(done[1].due, false) equal(done[1].completed, true)
        local repeated = J.Later(saved, {grouped = true}, {IsQuestFlaggedCompleted = function() return true end, IsOnQuest = function(id) return id == 3 end})
        equal(repeated[1].quest.id, 3) equal(repeated[1].due, true)
    end)
    test("Tour comparison presents a distinct alternative even when the nearest area already has most quests", function()
        local a = {zone = "A", entries = {{quest = Q(1)}, {quest = Q(2)}}, active = 2, pickups = 0, handIns = 1, yards = 100, xp = 100}
        local b = {zone = "B", entries = {{quest = Q(3)}}, active = 1, pickups = 0, handIns = 0, yards = 300, xp = 0, unknownXP = 1}
        local rows = J.Tours({areas = {a, b}}, api) equal(#rows, 2) equal(rows[1].areaKey, 1) equal(rows[2].areaKey, 3)
        assert(rows[2].quest.title:find(addon.L.JourneyTourAlternative, 1, true))
        assert(rows[2].short:find(addon.L.UnknownXP, 1, true)) equal(#J.Tours({areas = {a}}, api), 1)
    end)
    test("Chain expansion exposes known destinations while unknown prerequisites remain explicit", function()
        local chains = {{quest = Q(1), known = true, summary = "Next", detail = "Known facts", targets = {{quest = Q(2), target = P(.5)}}},
            {quest = Q(3), known = false, detail = addon.L.UnknownFollowUps}}
        equal(#J.ChainRows(chains, {}), 2)
        local rows = J.ChainRows(chains, {[1] = true, [3] = true}) equal(#rows, 4) equal(rows[2].target.x, .5)
        assert(rows[2].detail:find(addon.L.JourneyChainHelp, 1, true))
    end)
    test("Scenario: pickup, collection with full bags, real hand-in and after-round reminder", function()
        local q = Q(1) q.marker, q.objectiveMarker, q.yards = P(.1), P(.4), 100
        local plan = addon.ExcursionPlan.Build({entries = {{quest = q, pickup = true, target = q.objectiveMarker, yards = 400}}},
            {free = 1}, function() return P(.6) end, function() return 250 end)
        local reminders = {} J.SetLater(reminders, Q(2), P(.6), "round")
        assert(addon.ExcursionPlan.Start(plan, {}, {q}, function() return false end, {free = 1}))
        addon.ExcursionPlan.Sync(plan, {}, nil, function() return false end) equal(plan.index, 1)
        addon.ExcursionPlan.Sync(plan, {q}) equal(plan.index, 2)
        local brief = addon.DecisionBrief.Build({view = {quest = q}, collecting = true, bags = {known = true, low = true, free = 0}})
        equal(brief.bagsWarning, addon.L.JourneyCollectBags:format(0))
        q.readyToTurnIn = true addon.ExcursionPlan.Sync(plan, {q}) equal(plan.index, 3)
        addon.ExcursionPlan.HandedIn(plan, 1, 250) addon.ExcursionPlan.Sync(plan, {})
        equal(addon.ExcursionPlan.Review(plan).xp, 250)
        equal(J.Later(reminders, {roundFinished = plan.index > #plan.stops})[1].due, true)
    end)
    test("Quest-item instructions distinguish unknown range, cooldown and readiness", function()
        local item = {name = "Flare", count = 2}
        assert(addon.QuestItemHints.Describe(item, 0):find(addon.L.JourneyItemRangeUnknown, 1, true))
        item.inRange = true assert(addon.QuestItemHints.Describe(item, 0):find(addon.L.JourneyItemReady, 1, true))
        assert(addon.QuestItemHints.Describe(item, 3):find("3s", 1, true))
    end)
    test("After-round reminders track the selected round and ignore an already-finished round", function()
        local saved = {}
        J.SetLater(saved, Q(1), nil, "round", nil, {roundToken = "A", roundFinished = false})
        equal(J.Later(saved, {roundToken = "B", roundFinished = true})[1].due, false)
        equal(J.Later(saved, {roundToken = "A", roundFinished = true})[1].due, true)
        J.SetLater(saved, Q(1), nil, "round", nil, {roundToken = "A", roundFinished = true})
        equal(J.Later(saved, {roundToken = "A", roundFinished = true})[1].due, false)
        equal(J.Later(saved, {roundToken = "B", roundFinished = true})[1].due, true)
    end)
end
