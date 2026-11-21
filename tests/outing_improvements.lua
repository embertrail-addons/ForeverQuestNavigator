return function(test, addon, equal, near)
    local function Point(x, y) return {mapID = 10, x = x or .2, y = y or .1, objectiveIndex = 1} end
    local function Quest(id) return {id = id, title = "Quest " .. id, level = 30} end
    test("Preparation distinguishes required starter items from granted items and keeps missing inventory unknown", function()
        local db = {specialFlags = function() return 1 end, requiredSourceItems = function() return {7, 8} end,
            sourceItemId = function() return 99 end, preQuestGroup = function() return {3} end, preQuestSingle = function() return {4, 5} end}
        local prep = addon.QuestPreparation.Read(db, {IsQuestFlaggedCompleted = function(id) return id == 3 end}, 1,
            function(id) if id == 7 then return 0 end end, function(id) return "Item " .. id end)
        equal(prep.repeatable, true) equal(#prep.items, 2) equal(prep.items[1].owned, 0) equal(prep.items[2].owned, nil)
        equal(#prep.prerequisites, 3) equal(prep.prerequisites[1].done, true) equal(prep.prerequisites[2].alternative, true)
        local text = addon.QuestPreparation.Describe(prep, true)
        assert(text:find(addon.L.PreparationMissing, 1, true)) assert(text:find(addon.L.PreparationInventoryUnknown, 1, true))
        assert(not text:find("99", 1, true))
    end)
    test("Repeatable metadata handles unavailable integrations and native overrides without guessing", function()
        equal(addon.QuestPreparation.Repeatable(nil, {}, 1), nil)
        equal(addon.QuestPreparation.Repeatable({specialFlags = function() return 1 end}, {IsRepeatableQuest = function() return false end}, 1), false)
        equal(addon.QuestPreparation.Repeatable({specialFlags = function() return 1 end}, {IsRepeatableQuest = function() error("Unavailable") end}, 1), true)
        equal(addon.QuestPreparation.Read(nil, {}, 1).known, false)
    end)
    test("Repeatable modes separate ranking, information and hiding while preserving explicit priority", function()
        local ordinary, repeated = Quest(1), Quest(2) repeated.repeatable = true
        equal(#addon.RepeatablePolicy.Quests({ordinary, repeated}, "level"), 2)
        equal(#addon.RepeatablePolicy.Quests({ordinary, repeated}, "show"), 1)
        equal(#addon.RepeatablePolicy.Quests({ordinary, repeated}, "show", 2), 2)
        equal(#addon.RepeatablePolicy.Quests({ordinary, repeated}, "hide", 2), 1)
        local offers = addon.RepeatablePolicy.Offers({repeated}, "show") equal(offers[1].informational, true)
        equal(offers[1].lowPriority, true)
        addon.RepeatablePolicy.Offers({repeated}, "level") equal(repeated.lowPriority, false)
        equal(#addon.RepeatablePolicy.Offers({repeated}, "hide"), 0)
        equal(#addon.QuestFinder.Build({ordinary, repeated}, nil, nil, nil, "hide"), 1)
        equal(#addon.QuestFinder.Build({ordinary, repeated}, nil, {[2] = {quest = {id = 2}}}, nil, "hide"), 1)
        equal(#addon.QuestFinder.Build({ordinary, repeated}, nil, nil, nil, "show"), 2)
    end)
    test("Information-only repeatable offers never gain strong pickup recommendations", function()
        local offer = {id = 2, title = "Repeat", level = 30, marker = Point(), objectiveMarker = Point(.3),
            yards = 50, objectiveYards = 100, journeyYards = 150, levelPenalty = 0, repeatable = true}
        local api = {GetMapWorldSize = function() return 1000, 1000 end}
        local offers = addon.RepeatablePolicy.Offers({offer}, "show")
        addon.PlanningInsights.AnnotateOffers(api, offers, {}, {}, nil)
        addon.PickupPlanning.Build(api, offers, {}, {}, nil, {free = 10}, 30)
        assert(not offer.recommended) equal(offer.planClass, "repeatable")
    end)
    test("Camp comparison favors useful combinations initially but holds a reasonable area during travel", function()
        local player = {x = .1, y = .1}
        local api = {GetMapWorldSize = function() return 1000, 1000 end, GetPlayerMapPosition = function() return player end}
        local a, b, c = Quest(1), Quest(2), Quest(3)
        local old, combined = Point(.2, .1), Point(.1, .24)
        local m = {[1] = {marker = old, yards = 100}, [2] = {marker = Point(.11, .24)}, [3] = {marker = Point(.12, .24)}}
        local choices = addon.CampChoices.Build(api, a, m[1], {old, combined}, {a, b, c}, m, nil, nil, 30)
        equal(choices[1].target, combined) equal(choices[1].shared, 2)
        choices = addon.CampChoices.Build(api, a, m[1], {old, combined}, {a, b, c}, m, nil, old, 30)
        equal(choices[1].target, old)
        player.y = .23
        choices = addon.CampChoices.Build(api, a, m[1], {old, combined}, {a, b, c}, m, nil, old, 30)
        equal(choices[1].target, combined)
    end)
    test("An explicit camp selection survives distance advantages until its objective or availability changes", function()
        local api = {GetMapWorldSize = function() return 1000, 1000 end, GetPlayerMapPosition = function() return {x = .2, y = .1} end}
        local quest, nearPoint, farPoint = Quest(1), Point(.21), Point(.8)
        local selected = Point(.8) selected.manual = true
        local result = addon.CampChoices.Build(api, quest, {marker = nearPoint, yards = 10}, {nearPoint, farPoint}, {quest}, {}, nil, selected, 30)
        equal(result[1].target, farPoint)
        selected.objectiveIndex = 2
        result = addon.CampChoices.Build(api, quest, {marker = nearPoint, yards = 10}, {nearPoint, farPoint}, {quest}, {}, nil, selected, 30)
        equal(result[1].target, nearPoint)
    end)
    test("Known long access paths outweigh a nearby entrance without counting the access leg twice", function()
        local quests = {Quest(1), Quest(2)}
        local measurements = {[1] = {yards = 10, travelYards = 1010}, [2] = {yards = 500}}
        local ranked = addon.QuestPrioritizer.RankByDistance(quests, measurements, nil, 30)
        equal(ranked[1].id, 2)
        near(addon.TravelSupport.PlanningPenalty(quests[1], {extraYards = 1200}, true, 1000), 70)
        local fixture = addon.RegressionFixture.Capture(quests, {measurements = measurements, ranked = ranked, playerLevel = 30})
        equal(fixture.quests[1].measurement.travelYards, 1010) equal(addon.RegressionFixture.Replay(fixture), true)
    end)
    test("Recommendation changes explain observed turn-ins, new quests and completed objectives separately", function()
        local old, new = Quest(1), Quest(2)
        equal(addon.NavigationHints.Change(old, new, {changeContext = {turnedIn = 1}}), addon.L.ChangePreviousTurnedIn)
        equal(addon.NavigationHints.Change(old, new, {changeContext = {accepted = {[2] = true}}}), addon.L.ChangeNewQuest)
        local ready = Quest(1) ready.readyToTurnIn = true
        equal(addon.NavigationHints.Change(old, new, {ranked = {ready, new}}), addon.L.ChangePreviousFinished)
        new.readyToTurnIn = true
        equal(addon.NavigationHints.Change(old, new, {ranked = {old, new}, measurements = {[1] = {yards = 500}, [2] = {yards = 100}}}), addon.L.ChangeTurnInCloser)
        equal(addon.NavigationHints.Change(old, old, {}), nil)
    end)
    local function Outing()
        local active, offer = Quest(1), Quest(2) offer.marker, offer.yards = Point(.1), 10
        local area = {entries = {{quest = active, target = Point(.2)}, {quest = offer, target = Point(.3), pickup = true}}}
        local plan = addon.ExcursionPlan.Build(area, {free = 2}, function(q) return Point(.4 + q.id * .1) end,
            function(q) if q.id == 1 then return 100 end end)
        return plan, active, offer
    end
    test("Outing previews contain pickups before objectives and hand-ins with incomplete XP explicit", function()
        local plan = Outing()
        equal(#plan.stops, 5) equal(plan.stops[1].action, "accept") equal(plan.stops[2].action, "objective")
        equal(plan.stops[4].action, "turnIn") equal(plan.xp, 100) equal(plan.unknownXP, 1) equal(plan.running, false)
    end)
    test("An outing advances only after actual acceptance, all objectives and confirmed hand-in", function()
        local plan, active, offer = Outing()
        assert(addon.ExcursionPlan.Start(plan, {active}, {offer}, function() return true end, {free = 2}))
        addon.ExcursionPlan.Sync(plan, {active}, nil, function() return true end) equal(plan.index, 1)
        addon.ExcursionPlan.Sync(plan, {active, offer}, function() return {{finished = true}} end, function() return true end)
        equal(plan.index, 2) -- A finished goal does not finish a multi-goal quest.
        active.readyToTurnIn = true
        addon.ExcursionPlan.Sync(plan, {active, offer}) equal(plan.index, 3)
        offer.readyToTurnIn = true
        addon.ExcursionPlan.Sync(plan, {active, offer}) equal(plan.index, 4)
        addon.ExcursionPlan.HandedIn(plan, active.id)
        addon.ExcursionPlan.Sync(plan, {offer}) equal(plan.index, 5)
        addon.ExcursionPlan.HandedIn(plan, offer.id)
        addon.ExcursionPlan.Sync(plan, {}) equal(plan.running, false) equal(plan.status, addon.L.ExcursionFinished)
    end)
    test("Outings refuse stale data and full-log pickups without starting navigation", function()
        local plan, active, offer = Outing()
        local ok, reason = addon.ExcursionPlan.Start(plan, {active}, {offer}, nil, {full = true})
        equal(ok, false) equal(reason, addon.L.QuestLogFull) equal(plan.running, false)
        ok, reason = addon.ExcursionPlan.Start(plan, {active}, {}, nil, {free = 2})
        equal(ok, false) equal(reason, addon.L.ExcursionStale)
    end)
    test("Pausing and resuming an outing preserves completed steps and missing quests pause rather than complete", function()
        local plan, active, offer = Outing()
        assert(addon.ExcursionPlan.Start(plan, {active}, {offer}))
        addon.ExcursionPlan.Sync(plan, {active, offer}) equal(plan.index, 2)
        plan.running = false
        assert(addon.ExcursionPlan.Start(plan, {active, offer}, {})) equal(plan.index, 2) assert(plan.stops[1].done)
        addon.ExcursionPlan.Sync(plan, {}) equal(plan.running, false) equal(plan.index, 2)
        equal(plan.status, addon.L.ExcursionQuestMissing)
    end)
    test("Skipped quests stop a started outing and unavailable quest data cannot advance it", function()
        local plan, active, offer = Outing()
        assert(addon.ExcursionPlan.Start(plan, {active}, {offer}))
        addon.ExcursionPlan.Sync(plan, nil) equal(plan.index, 1)
        addon.ExcursionPlan.Sync(plan, {active, offer}, nil, nil, {[1] = true})
        equal(plan.running, false) equal(plan.index, 2)
    end)
    test("Personal notes retain Unicode, position and bookmark data while clearing only text", function()
        local notes = {}
        assert(addon.QuestTools.SetNoteText(notes, 1, "Quest", Point(), false, string.rep("ä", 241)))
        equal(notes[1].text, string.rep("ä", 240)) equal(notes[1].point.mapID, 10)
        addon.QuestTools.SetNoteText(notes, 1, "Quest", nil, false, "")
        equal(notes[1].text, nil) equal(notes[1].point.mapID, 10)
        equal(addon.QuestTools.SetNoteText(notes, nil, nil, nil, false, "text"), false)
    end)
    test("Settings categories separate presentation from recommendation changes without hiding searched advanced options", function()
        local entries = {{key = "theme", name = "Theme", basic = true, effect = "view"},
            {key = "policy", name = "Repeatable policy", basic = false, effect = "logic"}}
        equal(#addon.FilterSettings(entries, "", false, "logic"), 0)
        equal(#addon.FilterSettings(entries, "", true, "logic"), 1)
        equal(#addon.FilterSettings(entries, "policy", false, "logic"), 1)
        equal(#addon.FilterSettings(entries, "policy", true, "view"), 0)
    end)
    test("Arrival without a direction vector is a valid waiting state", function()
        equal(addon.QuestLocation.GetRelativeDirection({yards = 0}, 0), nil)
        equal(addon.QuestLocation.GetRelativeDirection({yards = 2, east = 1}, 0), nil)
    end)
end
