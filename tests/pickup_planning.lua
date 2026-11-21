return function(test, addon, equal, near)
    local api = {GetMapWorldSize = function() return 10000, 10000 end}
    local function Point(x) return {mapID = 10, x = x / 10000, y = .1} end
    local function Offer(id, pickup, target)
        return {id = id, title = "Offer " .. id, level = 30, levelPenalty = 0, yards = pickup,
            marker = Point(pickup), objectiveMarker = target and Point(target),
            objectiveYards = target and math.abs(target - pickup), journeyYards = target and pickup + math.abs(target - pickup),
            score = pickup, objectiveZone = "Destination", pickupZone = "Town", xp = 100}
    end
    test("Pickup advice separates pickup and objective and budgets highlights after a follow-up reserve", function()
        local active = {id = 1, level = 30}
        local measured = {[1] = {marker = Point(1000), yards = 1000}}
        local offers = {Offer(2, 50, 1000), Offer(3, 60, 1100), Offer(4, 70, 1050)}
        local plan = addon.PickupPlanning.Build(api, offers, {active}, measured, active,
            {free = 2, reserve = 1}, 30)
        equal(plan.budget, 1) equal(#plan.pickups, 1) equal(offers[1].beforeDeparture, true)
        equal(offers[2].slotLimited, true) assert(not offers[2].recommended)
        equal(offers[1].marker.x, .005) equal(offers[1].objectiveMarker.x, .1)
        equal(plan.outing[1].action, "accept") equal(plan.outing[2].action, "objective")
        equal(plan.outing[1].target, offers[1].marker)
        equal(plan.outing[3].target, offers[1].objectiveMarker)
    end)
    test("Full logs keep offers visible and suggest only a nearby unblocked ready hand-in", function()
        local quests = {{id = 1, level = 30}, {id = 2, readyToTurnIn = true}, {id = 3, readyToTurnIn = true}}
        local measured = {[1] = {marker = Point(1000), yards = 1000},
            [2] = {marker = Point(300), yards = 300}, [3] = {marker = Point(100), yards = 100}}
        local offers = {Offer(4, 50, 1000)}
        offers[1].recommended = true
        local plan = addon.PickupPlanning.Build(api, offers, quests, measured, quests[1],
            {full = true, free = 0}, 30, {[3] = {}})
        equal(#offers, 1) equal(#plan.pickups, 0) assert(not offers[1].recommended)
        equal(plan.outing[1].action, "turnIn") equal(plan.outing[1].quest.id, 2)
        equal(plan.areas[1].active, 1)
        measured[2].yards = 501
        equal(addon.PickupPlanning.Build(api, offers, quests, measured, quests[1], {free = 0}, 30, {[3] = {}}).turnIn, nil)
    end)
    test("Unknown coordinates, red quests and access legs cannot create strong pickup advice", function()
        local active = {id = 1, level = 30}
        local measured = {[1] = {marker = Point(50), objectiveMarker = Point(1000), yards = 50}}
        local offers = {Offer(2, 10), Offer(3, 20, 1000), Offer(4, 30, 1100)}
        offers[2].level = 33
        offers[3].level = nil
        local plan = addon.PickupPlanning.Build(api, offers, {active}, measured, active, nil, 30)
        equal(#plan.pickups, 0) equal(#plan.areas, 0) equal(plan.unknown, 3)
        for _, offer in ipairs(offers) do assert(not offer.recommended) assert(not offer.beforeDeparture) end
    end)
    test("Destination clusters do not chain camps and show incomplete XP as incomplete", function()
        local offers = {Offer(2, 10, 1000), Offer(3, 20, 1300), Offer(4, 30, 1600)}
        offers[2].xp = nil
        local plan = addon.PickupPlanning.Build(api, offers, {}, {}, nil, {free = 5}, 30)
        equal(#plan.areas, 2) equal(plan.areas[1].pickups, 2)
        equal(plan.areas[1].xp, 100) equal(plan.areas[1].unknownXP, 1)
        equal(offers[1].planClass, "combination") equal(offers[3].planClass, "independent")
        local rows = addon.PickupPlanView.Rows(plan, "areas", 2)
        equal(rows[1].back, true) equal(rows[2].stop.action, "accept")
        assert(rows[2].detail:find("Then to the objective", 1, true))
    end)
    test("Detours stay separate and unknown capacity does not become a numeric promise", function()
        local active = {id = 1, level = 30}
        local measured = {[1] = {marker = Point(100), yards = 100}}
        local offers = {Offer(2, 600, 2000)}
        local plan = addon.PickupPlanning.Build(api, offers, {active}, measured, active, nil, 30)
        equal(offers[1].planClass, "detour") equal(#plan.pickups, 0) equal(plan.budget, nil)
        local _, summary = addon.PickupPlanView.Rows(plan, "outing")
        assert(summary:find(addon.L.PickupCapacityUnknown, 1, true))
    end)
    test("Known follow-ups influence destination grouping without becoming available pickups", function()
        local active = {id = 1, level = 30}
        local chains = {{quest = active, known = true, stop = {target = Point(3000)},
            targets = {{target = Point(3000)}, {target = Point(1000)}}, summary = "Future", detail = "Forecast"}}
        local offers = {Offer(2, 50, 1000)}
        local measured = {[1] = {marker = Point(1050), yards = 1050}}
        local plan = addon.PickupPlanning.Build(api, offers, {active}, measured, active, {free = 3}, 30, nil, chains)
        equal(#plan.destination.followUps, 1) equal(#plan.followUps, 1)
        equal(#plan.pickups, 1) equal(#plan.outing, 3)
        local rows = addon.PickupPlanView.Rows(plan, "outing")
        equal(#rows, 4) equal(rows[4].detail, "Forecast")
    end)
    test("Before-departure highlights belong to one round, not unrelated camps", function()
        local offers = {Offer(2, 20, 1000), Offer(3, 30, 1100), Offer(4, 40, 3000), Offer(5, 50, 3100)}
        local plan = addon.PickupPlanning.Build(api, offers, {}, {}, nil, {free = 5}, 30)
        equal(#plan.pickups, 2) equal(plan.pickups[1].id, 2) equal(plan.pickups[2].id, 3)
        equal(offers[3].beforeDeparture, false) equal(#plan.outing, 4)
        offers[1].special = true
        plan = addon.PickupPlanning.Build(api, offers, {}, {}, nil, {free = 5}, 30)
        equal(offers[1].planClass, "special") assert(not offers[1].recommended)
    end)
end
