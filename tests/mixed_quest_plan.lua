return function(test, addon, equal)
    local M = addon.MixedQuestPlan
    local function P(x) return {mapID = 1, x = x, y = .2, objectiveIndex = 1} end
    local function Q(id, ready) return {id = id, title = "Quest " .. id, level = 30, readyToTurnIn = ready} end
    local api = {GetMapWorldSize = function() return 1000, 1000 end}
    local function Options(free) return {api = api, level = 30, fromPlayer = function(p) return p.x * 1000 end, capacity = {free = free or 3}} end
    local function Plan()
        local a, b = Q(1), Q(2) b.marker, b.yards, b.planClass = P(.5), 500, "combination"
        local area = {target = P(.6), entries = {{quest = a, target = P(.1), yards = 100}, {quest = b, pickup = true, target = P(.6), yards = 600}}}
        return addon.ExcursionPlan.Build(area, {free = 3}, function() return P(.95) end, function() return 100 end, Options()), a, b
    end
    test("Mixed tours place a pickup between existing work and hand-ins instead of forcing all pickups first", function()
        local p = Plan()
        equal(p.orderKnown, true) equal(p.stops[1].quest.id, 1) equal(p.stops[1].action, "objective")
        equal(p.stops[2].quest.id, 2) equal(p.stops[2].action, "accept") equal(p.stops[3].action, "objective")
        equal(p.stops[4].action, "turnIn") equal(p.stops[5].action, "turnIn")
    end)
    test("A real hand-in can make room for a later pickup, while reserve and future capacity are enforced", function()
        local a, b = Q(1, true), Q(2) b.marker, b.yards = P(.2), 200
        local area = {target = P(.3), entries = {{quest = a, target = P(.1), yards = 100}, {quest = b, pickup = true, target = P(.3), yards = 300}}}
        local p = addon.ExcursionPlan.Build(area, {free = 0, full = true}, function(q) return q.id == 1 and P(.1) or P(.4) end, function() return 100 end, Options())
        equal(p.stops[1].action, "turnIn") equal(p.stops[2].action, "accept")
        assert(addon.ExcursionPlan.Start(p, {a}, {b}, function() return false end, {free = 0, full = true}))
        addon.ExcursionPlan.Sync(p, {a}, nil, function() return false end) equal(p.index, 1)
        addon.ExcursionPlan.HandedIn(p, 1, 100) addon.ExcursionPlan.Sync(p, {}) equal(p.index, 2)
        addon.ExcursionPlan.Sync(p, {b}) equal(p.running, false) equal(p.needsReview, true) equal(p.index, 3)
        local revised = M.Refresh(p, {b}, {[2] = {marker = P(.31), yards = 310}}, {[2] = P(.4)})
        equal(revised.stops[3].target.x, .31) equal(p.stops[3].target.x, .3)
        assert(addon.ExcursionPlan.Start(revised, {b}, {}, function() return false end, {free = 0}))
        local reserved = addon.ExcursionPlan.Build(area, {free = 0, reserve = 1}, function() return P(.1) end, nil, Options())
        equal(#reserved.stops, 1)
    end)
    test("Actual acceptance requires a review and unknown new coordinates cannot silently resume", function()
        local p, a, b = Plan()
        assert(addon.ExcursionPlan.Start(p, {a}, {b}, nil, {free = 3}))
        a.readyToTurnIn = true addon.ExcursionPlan.Sync(p, {a, b})
        equal(p.needsReview, true) equal(p.running, false)
        equal(addon.ExcursionPlan.Start(p, {a, b}), false)
        local missing = M.Refresh(p, {a, b}, {}, {}) equal(missing.unverified, true)
        equal(addon.ExcursionPlan.Start(missing, {a, b}), false)
    end)
    test("Skipping an unaccepted root removes its work, hand-in and transitive dependants while preserving active quests", function()
        local p, a, b = Plan()
        local c, d = Q(3), Q(4)
        p.stops[#p.stops + 1] = {quest = c, action = "accept", target = P(.7), dependsOn = {2}}
        p.stops[#p.stops + 1] = {quest = d, action = "objective", target = P(.8), dependsOn = {3}}
        p.rewards[3], p.rewards[4] = 200, 300
        local ok, root, removed = M.Skip(p, 2, {[1] = true, [4] = true})
        assert(ok) equal(root.id, b.id) equal(removed[2], true) equal(removed[3], true) equal(removed[4], nil)
        equal(#p.stops, 3) equal(p.xp, 400) equal(p.excludedOffers[2], true)
        for _, stop in ipairs(p.stops) do assert(stop.quest.id ~= 2 and stop.quest.id ~= 3) end
    end)
    test("Already accepted quests cannot be removed by a stale pickup-skip click", function()
        local p = Plan() local count = #p.stops
        equal(M.Skip(p, 2, {[2] = true}), false) equal(#p.stops, count)
    end)
    test("Permanent and round-only pickup filters never touch accepted quest ranking", function()
        local offers = {Q(1), Q(2), Q(3), Q(4)}
        local filtered = M.Filter(offers, {[1] = {id = 1}}, {[2] = true}, {[3] = true})
        equal(#filtered, 1) equal(filtered[1].id, 4) equal(#offers, 4)
        equal(#addon.QuestPrioritizer.Rank({Q(1)}, {}, nil), 1)
    end)
    test("Gathering adds only known ready hand-ins with a bounded detour and leaves the area unchanged", function()
        local area = {target = P(.6), entries = {{quest = Q(1), target = P(.6)}}}
        local a, b = Q(2, true), Q(3, true)
        local result = M.Gather(area, {a, b}, {[2] = {marker = P(.3), yards = 300}, [3] = {marker = P(.9), yards = 900}}, Options())
        equal(#result.entries, 2) equal(result.entries[2].quest.id, 2) equal(#area.entries, 1)
    end)
    test("Unavailable transforms retain a provisional order and full-log pickups are never falsely started", function()
        local p, a, b = Plan()
        p.orderKnown = nil
        M.Order(p, {api = {}, capacity = {free = 0}, fromPlayer = function() return 1 end})
        equal(p.orderKnown, false)
        equal(addon.ExcursionPlan.Start(p, {a}, {b}, nil, {free = 0}), false)
    end)
    test("Known pickup detours beyond the insertion limit are omitted rather than highlighted", function()
        local a, b = Q(1), Q(2) b.marker, b.yards = P(.95), 950
        local area = {entries = {{quest = a, target = P(.1), yards = 100}, {quest = b, target = P(.11), pickup = true, yards = 1000}}}
        local p = addon.ExcursionPlan.Build(area, {free = 3}, function() return P(.2) end, function() return 100 end, Options())
        equal(p.omittedPickups, 1) equal(#p.stops, 2) equal(p.xp, 100)
        equal(p.excludedOffers[2], nil)
        equal(M.Refresh(p, nil).unverified, true)
    end)
end
