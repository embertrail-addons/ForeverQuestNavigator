return function(test, addon, equal, near)
    local Tour = addon.TourPlan
    test("Tours sanitize saves, deduplicate IDs and never auto-start after load", function()
        local saved = {running = true, stops = {{id = 1, stage = "objective"}, {id = 1, stage = "turnIn"},
            {id = -1, stage = "objective"}, {id = 2, stage = "invalid"}, {id = 3, stage = "turnIn"}},
            returnPoint = {mapID = 10, x = .4, y = .5, name = "Home"}}
        local plan = Tour.New(saved)
        equal(#plan.stops, 2) equal(plan.running, false) equal(plan.returnPoint.name, "Home")
        plan.stops[1].id = 8 equal(saved.stops[1].id, 1)
        local exported = Tour.Export(plan) equal(exported.running, nil) equal(exported.stops[1].id, 8)
    end)
    test("Tours bound size and distinguish unfinished dungeons from completed dungeon hand-ins", function()
        local plan = Tour.New()
        equal(Tour.Add(plan, {id = 1, special = true}), false)
        equal(Tour.Add(plan, {id = 1, special = true, readyToTurnIn = true}), true)
        equal(plan.stops[1].stage, "turnIn")
        equal(Tour.Add(plan, {id = 1}), false)
        for id = 2, 20 do assert(Tour.Add(plan, {id = id})) end
        equal(Tour.Add(plan, {id = 21}), false)
        equal(Tour.Move(plan, 1, -1), false) equal(Tour.Move(plan, 1, 1), true)
        equal(plan.stops[1].id, 2) equal(Tour.Remove(plan, 2), true)
    end)
    test("Tour stops finish on quest progress, never merely reaching coordinates", function()
        local plan = Tour.New({stops = {{id = 1, stage = "objective"}, {id = 2, stage = "turnIn"}}})
        plan.running = true
        Tour.Sync(plan, nil) equal(#plan.stops, 2)
        Tour.Sync(plan, {{id = 1}, {id = 2, readyToTurnIn = true}}) equal(Tour.Current(plan), 1)
        Tour.Sync(plan, {{id = 1, readyToTurnIn = true}, {id = 2, readyToTurnIn = true}}) equal(Tour.Current(plan), 2)
        Tour.Sync(plan, {{id = 1, readyToTurnIn = true}}) equal(#plan.stops, 0) equal(plan.running, false)
    end)
    test("Failed, skipped and vanished tour entries are removed and return points remain", function()
        local plan = Tour.New({stops = {{id = 1, stage = "objective"}, {id = 2, stage = "objective"}, {id = 3, stage = "turnIn"}},
            returnPoint = {mapID = 10, x = .4, y = .5}})
        plan.running = true
        Tour.Sync(plan, {{id = 1, failed = true}, {id = 2}}, {[2] = true})
        equal(#plan.stops, 0) equal(plan.running, true) assert(plan.returnPoint)
    end)
    test("Tour optimization previews do not mutate the plan and stale revisions are rejected", function()
        local plan = Tour.New({stops = {{id = 1, stage = "objective"}, {id = 2, stage = "objective"}, {id = 3, stage = "objective"}}})
        local measurements = {[1] = {yards = 300, marker = {x = 300}}, [2] = {yards = 100, marker = {x = 100}}}
        local preview = Tour.Preview(plan, measurements, function(a, b) return math.abs(a.x - b.x) end)
        equal(preview.stops[1].id, 2) equal(preview.stops[3].id, 3) equal(plan.stops[1].id, 1)
        Tour.Move(plan, 1, 1) equal(Tour.ApplyPreview(plan, preview), false)
        preview = Tour.Preview(plan, measurements, function(a, b) return math.abs(a.x - b.x) end)
        equal(Tour.ApplyPreview(plan, preview), true) equal(plan.stops[1].id, 2)
    end)
    test("Finder combines current, offered and skipped quests with literal localized search", function()
        local entries = addon.QuestFinder.Build({{id = 1, title = "Ärger [a]"}, {id = 2, title = "Skipped"}},
            {{id = 3, title = "Offer", pickupZone = "Hügelland"}, {id = 1}}, {[2] = {quest = {id = 2}}, [4] = {quest = {id = 4, title = "Old skip"}}},
            function() return {zoneName = "Alterac"} end)
        equal(#entries, 4)
        equal(#addon.QuestFinder.Filter(entries, "[a]", "active"), 1)
        equal(#addon.QuestFinder.Filter(entries, "ärger"), 1)
        equal(#addon.QuestFinder.Filter(entries, "HÜGELLAND", "offer"), 1)
        equal(#addon.QuestFinder.Filter(entries, "", "skipped"), 2)
        equal(#addon.QuestFinder.Filter(entries, "%"), 0)
    end)
    test("Tour order suggestions account for a known final return leg", function()
        local plan = Tour.New({stops = {{id = 1, stage = "objective"}, {id = 2, stage = "objective"}},
            returnPoint = {mapID = 10, x = 0, y = .1}})
        local measurements = {[1] = {yards = 100, marker = {x = .1}}, [2] = {yards = 200, marker = {x = .4}}}
        local preview = Tour.Preview(plan, measurements, function(a, b) return math.abs(a.x - b.x) * 1000 end)
        equal(preview.stops[1].id, 2) equal(plan.stops[1].id, 1)
    end)
    local function Fixture(saved)
        local data = {quests = {{id = 1, title = "First"}, {id = 2, title = "Second", readyToTurnIn = true}}, skipped = {},
            measurements = {[1] = {yards = 100, marker = {mapID = 10, x = .1, y = .1}}, [2] = {yards = 50, marker = {mapID = 10, x = .2, y = .1}}}}
        data.turnInTour = {stops = {{quest = data.quests[2]}}}
        local state = {remember = true, changed = 0, selected = nil}
        local workspace = addon.PlanningWorkspace.New({read = function() return data end, remember = function() return state.remember end,
            priority = function() return state.selected end, save = function(value) state.saved = value end,
            select = function(id, policy) state.selected, state.policy = id, policy return true end,
            restore = function(id) data.skipped[id] = nil end, changed = function() state.changed = state.changed + 1 end,
            cancelReturn = function() state.cancelled = true end, map = function(entry) state.map = entry end,
            metric = function() return function(a, b) return math.abs(a.x - b.x) * 1000 end end,
            destination = function(id) return data.measurements[id] and {target = data.measurements[id].marker, zoneName = "Zone"} end,
            position = function() return {mapID = 10, x = .4, y = .5, name = "Home"} end}, saved)
        return workspace, data, state
    end
    test("Workspace keeps navigation unchanged while editing and starts only explicitly", function()
        local work, data, state = Fixture()
        work:Action("add", {quest = data.quests[1]}) equal(work:Current(), nil) equal(state.selected, nil)
        work:Action("returnHere") equal(work.plan.returnPoint.name, "Home")
        work:Action("start") equal(work:Current(), 1)
        data.quests[1].readyToTurnIn = true work:Sync(data.quests, {})
        equal(work:Current(), nil) equal(work:ReturnTarget().name, "Home")
        work:Arrived() equal(work:ReturnTarget(), nil)
        local reloaded = Fixture(state.saved)
        equal(reloaded.pending, nil) assert(reloaded.plan.returnPoint)
    end)
    test("Closing rounds are reviewed before replacing a custom tour", function()
        local work, data = Fixture()
        work:Action("add", {quest = data.quests[1]}) work:Action("returnHere")
        work:Action("closing") equal(work.plan.stops[1].id, 1) equal(work:Model().tour[1].quest.id, 2)
        work:Action("apply") equal(work.plan.stops[1].id, 2) equal(work.plan.running, false)
        equal(work.plan.returnPoint.name, "Home")
    end)
    test("A saved plan is offered after reload without replacing automatic selection", function()
        local work, data, state = Fixture({plan = {stops = {{id = 1, stage = "objective"}}}, priority = {id = 1, policy = "turnIn"}})
        equal(work.plan.running, false) equal(state.selected, nil) assert(work:Model().pending)
        work:Sync(nil, {}) equal(#work.plan.stops, 1)
        equal(work:Resume(), true) equal(state.selected, 1) equal(state.policy, "turnIn") equal(work.pending, nil)
    end)
    test("Resume rejects unknown targets without erasing the pending plan and supports dismiss/opt-out", function()
        local work, data, state = Fixture({plan = {stops = {{id = 1, stage = "objective"}}}, priority = {id = 1, policy = "manual"}})
        data.measurements = {}
        equal(work:Resume(), false) assert(work.pending) equal(#work.plan.stops, 1)
        work:Action("dismiss") equal(work.pending, nil) equal(#work.plan.stops, 0) equal(state.saved, nil)
        work:Action("add", {quest = data.quests[1]}) assert(state.saved)
        state.remember = false work:Save() equal(state.saved, nil) equal(#work.plan.stops, 1)
    end)
    test("Problem reports use an allowlist and never copy names, notes or access labels", function()
        local report = addon.ProblemReport.Build({version = "0.1.67", level = 30, manual = true, questieLoaded = true,
            quest = {id = 1, title = "PRIVATE QUEST", note = "PRIVATE NOTE"},
            marker = {mapID = 10, x = .4, y = .5, accessName = "PRIVATE ROUTE"},
            character = "PRIVATE CHARACTER", decision = "PRIVATE DECISION", markerCount = 2})
        assert(report:find("questID=1", 1, true)) assert(report:find("targetMap=10", 1, true))
        assert(not report:find("PRIVATE", 1, true))
        equal(addon.QuestState.Read({}, true), "!") equal(addon.QuestState.Read({readyToTurnIn = true}), "?")
        equal(addon.QuestState.Read({}, false, true), "*") equal(addon.QuestState.Read({}), ">")
    end)
    test("Pending returns survive reload but completed returns do not produce resume prompts", function()
        local work, _, state = Fixture()
        work:Action("returnHere") work:Action("start")
        equal(state.saved.returnPending, true)
        local reloaded, _, reloadedState = Fixture(state.saved)
        assert(reloaded.pending) reloaded:Save() equal(reloadedState.saved.returnPending, true)
        equal(reloaded:Resume(), true) assert(reloaded:ReturnTarget())
        reloaded:Arrived()
        local done = Fixture(reloadedState.saved) equal(done.pending, nil)
    end)
    test("Demo guards block workspace actions without touching navigation or saves", function()
        local work, data, state = Fixture()
        work.context.blocked = function() return true end
        work:Action("add", {quest = data.quests[1]}) work:Action("start") work:Action("returnHere")
        equal(#work.plan.stops, 0) equal(work.plan.running, false) equal(state.saved, nil)
        equal(work.status, addon.L.DemoReadOnly)
    end)
    test("Stale closing previews do not stop a currently running tour", function()
        local work, data = Fixture()
        work:Action("add", {quest = data.quests[1]}) work:Action("start") work:Action("closing")
        work.plan.revision = work.plan.revision + 1
        work:Action("apply") equal(work.plan.running, true) equal(work.plan.stops[1].id, 1)
        equal(work.status, addon.L.TourPreviewStale)
    end)
    test("The finder can clear a priority without retaining a pending saved override", function()
        local work, _, state = Fixture({priority = {id = 1, policy = "manual"}})
        state.selected = 1
        work:Action("clearPriority")
        equal(state.selected, nil) equal(work.pending, nil) equal(state.saved, nil)
    end)
end
