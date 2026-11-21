return function(test, addon, equal, near)
    local function Point(x) return {mapID = 1, x = x or .2, y = .3, objectiveIndex = 1} end
    local function Quest(id) return {id = id, title = "Quest " .. id, level = 30} end
    test("Next actions unify pickups, approach stops and alternatives without duplicates or priority changes", function()
        local active, pickup, along, alternative = Quest(1), Quest(2), Quest(3), Quest(4)
        local snapshot = {playerLevel = 30, ranked = {active, alternative},
            measurements = {[1] = {yards = 100, marker = Point()}, [3] = {yards = 50, marker = Point()},
                [4] = {yards = 200, marker = Point()}},
            pickupPlanning = {pickups = {{id = 2, title = pickup.title, marker = Point(), yards = 20}}},
            view = {quest = active, alternatives = {along, alternative}, approachStops = {{quest = along, yards = 50}}}}
        local brief = addon.DecisionBrief.Build(snapshot)
        equal(#brief.steps, 3) equal(brief.steps[1].kind, "accept") equal(brief.steps[2].kind, "along")
        equal(brief.steps[2].target, snapshot.measurements[3].marker)
        equal(brief.steps[3].quest.id, 4) equal(snapshot.ranked[1].id, 1)
    end)
    test("Closing advice uses player distances rather than a short leg between distant hand-ins", function()
        local a, b = Quest(1), Quest(2)
        local brief = addon.DecisionBrief.Build({measurements = {[1] = {yards = 3000}, [2] = {yards = 200}},
            turnInTour = {stops = {{quest = a, target = Point(), leg = 10, xp = 400},
                {quest = b, target = Point(), leg = 2800}}}})
        equal(#brief.closing, 1) equal(brief.closing[1].quest.id, 2)
        equal(brief.xp, 0) equal(brief.unknownXP, 1)
        equal(#brief.handInAreas, 1) equal(brief.handInAreas[1].xp, 400)
    end)
    test("Evidence never confuses a spawn or entrance estimate with a verified walking route", function()
        equal(addon.DecisionBrief.Evidence(Quest(1), nil, 30), "limited")
        equal(addon.DecisionBrief.Evidence(Quest(1), {yards = 100}, 30), "limited")
        equal(addon.DecisionBrief.Evidence(Quest(1), {marker = Point()}, 30), "approximate")
        local point = Point() point.targetKind = "object"
        local kind, text = addon.DecisionBrief.Evidence(Quest(1), {marker = point}, 30)
        equal(kind, "known") assert(text:find("path not verified", 1, true))
    end)
    test("Comparison remains available when pickups precede the next active quest", function()
        local active, other = Quest(1), Quest(2)
        local brief = addon.DecisionBrief.Build({playerLevel = 30, ranked = {active, other},
            view = {quest = active}, pickupPlanning = {pickups = {{id = 3, marker = Point(), yards = 20}}}})
        assert(brief.comparison:find("Alternative: Quest 2", 1, true))
        assert(brief.comparison:find(addon.L.UnknownXP, 1, true))
        assert(not brief.comparison:find("saves", 1, true))
    end)
    test("Remembered rounds distinguish completed goals from removed or abandoned quests", function()
        local quest = Quest(1)
        local ledger = addon.OutingLedger.Start({outing = {{quest = quest, target = Point(), action = "objective"},
            {quest = quest, action = "turnIn"}}})
        addon.OutingLedger.Sync(ledger, {quest}, function() return {{finished = false}} end)
        addon.OutingLedger.Sync(ledger, {}, nil, function() return false end)
        equal(ledger.completed, 0) equal(ledger.changed, 2)
        addon.OutingLedger.Sync(ledger, {}, nil, function() return true end)
        equal(ledger.completed, 2) equal(ledger.changed, 0)
    end)
    test("A remembered pickup completes only after acceptance; repeatable history is not a new turn-in", function()
        local quest = Quest(1)
        local ledger = addon.OutingLedger.Start({outing = {{quest = quest, action = "accept"},
            {quest = quest, action = "turnIn"}}}, function() return true end)
        addon.OutingLedger.Sync(ledger, {}, nil, function() return true end)
        equal(ledger.completed, 0)
        addon.OutingLedger.Sync(ledger, {quest}, nil, function() return true end)
        equal(ledger.completed, 1)
        addon.OutingLedger.Sync(ledger, {}, nil, function() return true end)
        equal(ledger.completed, 1) equal(ledger.changed, 1)
    end)
    test("Remembered objective progress follows the chosen objective index rather than any finished goal", function()
        local quest = Quest(1)
        local point = Point() point.objectiveIndex = 2
        local ledger = addon.OutingLedger.Start({outing = {{quest = quest, target = point, action = "objective"}}})
        addon.OutingLedger.Sync(ledger, {quest}, function() return {{finished = true}, {finished = false}} end)
        equal(ledger.completed, 0)
        addon.OutingLedger.Sync(ledger, {quest}, function() return {{finished = false}, {finished = true}} end)
        equal(ledger.completed, 1)
    end)
    test("Expanded feedback reasons expire and release on readiness", function()
        for _, kind in ipairs({"empty", "group", "access"}) do
            local store, quest = {}, Quest(1)
            addon.RecommendationFeedback.Set(store, quest, {marker = Point()}, kind, 10)
            local entry, penalty = addon.RecommendationFeedback.Get(store, quest, {marker = Point()}, 20)
            equal(entry.kind, kind) assert(penalty > 0)
            quest.readyToTurnIn = true
            equal(addon.RecommendationFeedback.Get(store, quest, {marker = Point()}, 21), nil)
            quest.readyToTurnIn = false addon.RecommendationFeedback.Set(store, quest, nil, kind, 10)
            equal(addon.RecommendationFeedback.Get(store, quest, nil, 610), nil)
        end
    end)
    test("All palette choices preserve readable text when the background is invisible", function()
        local theme = addon.UI.Theme
        local texture, label = {}, {}
        function texture:SetColorTexture(r, g, b, a) self.alpha = a end
        function label:SetTextColor(r, g, b) self.r, self.g, self.b = r, g, b end
        theme.Bind(texture, "button", .8) theme.Bind(label, "text", nil, "text")
        for _, design in ipairs({"graphite", "parchment", "midnight"}) do
            theme.Apply(false, design, false) theme.SetOpacity(0)
            equal(texture.alpha, 0) assert(label.r > .8 and label.g > .8)
        end
        theme.Apply(false, "graphite", true)
        equal(theme.Text("warning", "Caution"), "Caution")
        theme.SetOpacity(1) theme.Apply(false, "graphite", false)
    end)
    test("Appearance sharing and rollback include theme, layout and reduced-color preferences", function()
        local settings = {theme = "midnight", navigatorLayout = "guided", reducedColors = true}
        local parsed = addon.DisplayTransfer.Parse(addon.DisplayTransfer.Export(settings))
        equal(parsed.theme, "midnight") equal(parsed.reducedColors, true)
        local saved = addon.AppearanceProfiles.Snapshot(settings)
        settings.theme = "parchment"
        addon.AppearanceProfiles.Restore(saved, settings, {{key = "theme", control = {SetValue = function(_, value) settings.theme = value end}}})
        equal(settings.theme, "midnight")
    end)
    test("Decision exports contain quest facts and uncertainties without account or player fields", function()
        local quest = Quest(1)
        local snapshot = {playerLevel = 30, view = {quest = quest}, ranked = {quest}}
        local report = addon.DecisionBrief.Report(snapshot, addon.DecisionBrief.Build(snapshot))
        assert(report:find(addon.L.EvidenceLimited, 1, true))
        assert(not report:find("playerName=", 1, true)) assert(not report:find("account=", 1, true))
    end)
    test("Area avoidance is bounded, leaves ready hand-ins alone and suppresses nearby pickup highlights", function()
        local api = {GetMapWorldSize = function() return 10000, 10000 end}
        local a, b, c = Quest(1), Quest(2), Quest(3)
        c.readyToTurnIn = true
        local measured = {[1] = {yards = 100, marker = Point(.2)}, [2] = {yards = 1000, marker = Point(.3)},
            [3] = {yards = 110, marker = Point(.21)}}
        local store = {}
        equal(addon.RecommendationFeedback.SetArea(store, api, {a, b, c}, measured, Point(.2), 0), 1)
        equal(store[1].kind, "area") equal(store[2], nil) equal(store[3], nil)
        local offers = {{id = 8, level = 30, yards = 50, marker = Point(.19), objectiveMarker = Point(.2),
            journeyYards = 150, objectiveYards = 100, score = 100}}
        local plan = addon.PickupPlanning.Build(api, offers, {a, b}, measured, a, {free = 5}, 30, store)
        equal(#plan.pickups, 0) equal(offers[1].planClass, "avoided")
        equal(addon.RecommendationFeedback.Get(store, a, measured[1], 600), nil)
    end)
    test("Hand-in information includes ready quests beyond the bounded eight-stop tour", function()
        local quests, measurements = {}, {}
        for id = 1, 12 do
            quests[id] = Quest(id) quests[id].readyToTurnIn = true
            measurements[id] = {yards = 100, marker = Point()}
        end
        measurements[12] = nil
        local brief = addon.DecisionBrief.Build({ranked = quests, measurements = measurements, knownRewards = {}})
        equal(#brief.handInAreas[1].entries, 11) equal(#brief.closing, 11)
        equal(brief.unknownHandIns, 1) equal(brief.unknownXP, 11)
    end)
    test("Legacy navigator choices and collapsed state migrate into Focus or Overview", function()
        for _, previous in ipairs({"goal", "quest", "focus"}) do
            local settings = {navigatorView = previous}
            addon.TrackerPresentation.MigrateNavigatorView(settings)
            equal(settings.navigatorView, "goal") equal(settings.collapsed, true)
        end
        local settings = {navigatorView = "all", navigatorLayout = "lists"}
        addon.TrackerPresentation.MigrateNavigatorView(settings)
        equal(settings.navigatorView, "all") equal(settings.collapsed, false) equal(settings.environmentExpanded, true)
        settings.environmentExpanded = false
        addon.TrackerPresentation.MigrateNavigatorView(settings)
        equal(settings.environmentExpanded, false)
        settings.collapsed = true
        addon.TrackerPresentation.MigrateNavigatorView(settings)
        equal(settings.navigatorView, "goal")
    end)
    test("Old imported layouts become supported views and new exports omit the obsolete layout option", function()
        local imported = addon.DisplayTransfer.Parse("FQN-DISPLAY-1\nnavigatorLayout=lists\nnavigatorView=quest")
        equal(imported.navigatorView, "goal") equal(imported.navigatorLayout, nil)
        equal(addon.DisplayTransfer.Parse("FQN-DISPLAY-1\nnavigatorLayout=lists").navigatorView, "all")
        local text = addon.DisplayTransfer.Export({navigatorView = "quest", navigatorLayout = "lists"})
        assert(text:find("navigatorView=goal", 1, true)) assert(not text:find("navigatorLayout", 1, true))
    end)
end
