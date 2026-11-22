return function(test, addon, equal)
    local S = addon.AdventureSupport
    local function P(x, index) return {mapID = 1, x = x or .2, y = .2, objectiveIndex = index or 1} end
    local function Q(id) return {id = id, title = "Quest " .. id, level = 30} end
    local api = {GetMapWorldSize = function() return 1000, 1000 end}
    test("Departure checks show known giver coordinates, missing capacity and manual acceptance", function()
        local q = Q(1) q.marker, q.pickupZone = P(.1), "Town"
        local row = S.Departure({pickups = {q}})[1]
        assert(row.detail:find(addon.L.PickupCapacityUnknown, 1, true))
        assert(row.detail:find(addon.L.AdventureAcceptManual, 1, true)) equal(row.target, q.marker)
        assert(S.Departure({pickups = {q}}, {full = true})[1].detail:find(addon.L.QuestLogFull, 1, true))
    end)
    test("Group checks distinguish positive, negative, unavailable and throwing native calls", function()
        local q = Q(1)
        local rows = S.Group({q}, {"party1", "party2", "party3", "party4"}, {IsUnitOnQuest = function(unit, id)
            equal(id, 1) if unit == "party1" then return true elseif unit == "party2" then return false elseif unit == "party3" then error("unavailable") end
        end})
        equal(rows[1].count, 1) equal(rows[1].unknown, 2)
        equal(S.Group({q}, {"party1"}, {})[1].unknown, 1) equal(S.Group({q}, {}, {})[1].count, 0)
    end)
    test("Personal corrections affect only the selected unfinished objective and can be reset", function()
        local q, store = Q(1), {}
        assert(S.Correct(store, q, P(.8), 2)) equal(S.Correct(store, q, P(), 0), false)
        local first, second = P(.1, 1), P(.2, 2)
        local markers = {[1] = {first, second}}
        S.ApplyCorrections(markers, {q}, store, function() return {{finished = false}, {finished = false}} end)
        equal(#markers[1], 2) equal(markers[1][1].x, .8) equal(markers[1][2], first)
        equal(second.x, .2) assert(addon.NavigationHints.TargetText(markers[1][1]):find(addon.L.AdventurePersonalTarget, 1, true))
        markers[1] = {first, second}
        S.ApplyCorrections(markers, {q}, store, function() return {{finished = false}, {finished = true}} end)
        equal(markers[1][2], second)
        store[1][2] = nil markers[1] = {first, second}
        S.ApplyCorrections(markers, {q}, store, function() error("unavailable") end) equal(markers[1][2], second)
    end)
    test("Hand-in corrections survive plain saved tables without replacing unrelated objectives", function()
        local q, store = Q(1), {} q.readyToTurnIn = true
        assert(S.Correct(store, q, P(.7)))
        local markers = {[1] = {P(.1)}} S.ApplyCorrections(markers, {q}, store)
        equal(#markers[1], 1) equal(markers[1][1].x, .7) equal(markers[1][1].outdoorTurnIn, true)
        q.readyToTurnIn = false markers[1] = {P(.1)}
        S.ApplyCorrections(markers, {q}, store, function() return {{finished = false}} end)
        equal(markers[1][1].x, .1)
    end)
    test("Timed tours keep whole quests with measurable returns and leave the source plan untouched", function()
        local a, b = Q(1), Q(2)
        local area = {entries = {{quest = a, target = P(.2), yards = 100}, {quest = b, target = P(.3), yards = 200}}}
        local p = addon.ExcursionPlan.Build(area, nil, function() return P(.4) end, function() return 100 end)
        equal(#p.stops, 4)
        local small = S.Budget(p, 15, api)
        equal(#small.stops, 2) equal(small.stops[1].quest.id, small.stops[2].quest.id)
        equal(small.stops[2].action, "turnIn") equal(small.xp, 100) equal(small.omitted, 1)
        assert(small.upperMinutes <= 15) equal(#p.stops, 4) equal(p.running, false)
        equal(S.Budget(p, 0, api), p) equal(#S.Budget(p, 15, {}).stops, 0)
        local noReturn = addon.ExcursionPlan.Build(area)
        equal(#S.Budget(noReturn, 60, api).stops, 0)
    end)
    test("Change proposals add only suitable nearby objectives without mutating a running plan", function()
        local a, b, c, d = Q(1), Q(2), Q(3), Q(4) d.special = true c.level = 40
        local p = {started = true, running = true, index = 1, stops = {{quest = a, action = "objective", target = P(.2)}}}
        local snapshot = {playerLevel = 30, ranked = {a, b, c, d}, measurements = {
            [2] = {marker = P(.25)}, [3] = {marker = P(.25)}, [4] = {marker = P(.25)}}}
        local rows = S.Changes(p, snapshot, api)
        equal(#rows, 1) equal(rows[1].quest.id, 2) equal(#p.stops, 1) equal(p.running, true)
        snapshot.feedback = {[2] = {}} equal(#S.Changes(p, snapshot, api), 0)
    end)
    test("Blocked suggestions exclude the blocked quest and active feedback while leaving priority alone", function()
        local a, b, c = Q(1), Q(2), Q(3)
        local snapshot = {ranked = {a, b, c}, playerLevel = 30, feedback = {[3] = {}}, measurements = {
            [1] = {marker = P()}, [2] = {marker = P()}, [3] = {marker = P()}}}
        local rows = S.Alternatives(snapshot, 1) equal(#rows, 1) equal(rows[1].quest.id, 2) equal(snapshot.ranked[1].id, 1)
    end)
    test("Next-step instructions use real giver/access names and retain literal objective text", function()
        local q = Q(1) q.readyToTurnIn = true
        equal(addon.NavigationHints.Instruction(q, {turnInName = "Doctor"}), addon.L.AdventureTalkTo:format("Doctor"))
        q.readyToTurnIn = false
        equal(addon.NavigationHints.Instruction(q, {accessPoint = true, accessName = "Gate"}), addon.L.AccessGoal:format("Gate"))
        equal(addon.NavigationHints.Instruction(q, P(), {text = "Collect silk 0/12"}), "Collect silk 0/12")
    end)
end
