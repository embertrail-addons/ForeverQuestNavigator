return function(test, addon, equal, near)
    test("Multi-step access visits points in order and counts every remaining leg", function()
        local x, y = .1, .1
        local api = {GetMapWorldSize = function() return 1000, 1000 end,
            GetPlayerMapPosition = function() return {x = x, y = y} end}
        local target = {mapID = 10, x = .5, y = .4, objectiveIndex = 1}
        local first, second = {mapID = 10, x = .2, y = .1}, {mapID = 10, x = .2, y = .4}
        local saved, passed = {}, {}
        assert(addon.TravelSupport.SaveAccess(saved, 1, target, first, "Bridge"))
        assert(addon.TravelSupport.AppendAccess(saved, 1, target, second, api))
        local function Measure()
            local measurements = addon.QuestLocation.MeasureQuests(api, {[1] = {target}}, {1})
            addon.TravelSupport.ApplyAccess(api, {{id = 1}}, measurements, {[10] = true}, saved, passed)
            return measurements[1]
        end
        local measured = Measure()
        equal(measured.marker.accessStep, 1) near(measured.accessLeg, 600) near(measured.travelYards, 700)
        equal(#measured.accessSteps, 2)
        x, y = .2, .1
        measured = Measure()
        equal(measured.marker.accessStep, 2) near(measured.travelYards, 600)
        x, y = .2, .4
        measured = Measure()
        equal(measured.objectiveMarker, nil) equal(measured.marker, target)
        equal(passed["1:1"].index, 3)
        local journey = addon.TravelSupport.BuildJourney(api, {id = 1}, measured, {{text = "Work"}},
            {[1] = {marker = target}}, {mapID = 10, x = .1, y = .1})
        near(journey.totalYards, 1000) near(journey.returnYards, 700)
        equal(#journey.exitSteps, 2)
    end)

    test("Access route edits retain old single-point data and reject bad additions without mutation", function()
        local api = {GetMapWorldSize = function() return 1000, 1000 end}
        local target, a, b = {mapID = 10, x = .5, y = .5, objectiveIndex = 1},
            {mapID = 10, x = .1, y = .5}, {mapID = 10, x = .2, y = .5}
        local saved = {[1] = {[1] = {target = target, point = a, name = "Gate"}}}
        equal(#addon.TravelSupport.AccessSteps(saved[1][1]), 1)
        assert(not addon.TravelSupport.AppendAccess(saved, 1, target, a, api))
        equal(saved[1][1].points, nil)
        assert(addon.TravelSupport.AppendAccess(saved, 1, target, b, api))
        assert(addon.TravelSupport.MoveAccessStep(saved, 1, 1, 2, -1))
        near(saved[1][1].point.x, .2)
        assert(addon.TravelSupport.RemoveAccessStep(saved, 1, 1, 1))
        near(saved[1][1].point.x, .1)
        assert(addon.TravelSupport.RemoveAccessStep(saved, 1, 1, 1)) equal(saved[1], nil)
        assert(addon.TravelSupport.SaveAccess(saved, 1, target, a, "Gate"))
        for index = 2, 8 do assert(addon.TravelSupport.AppendAccess(saved, 1, target, {mapID = 10, x = index / 10, y = .5}, api)) end
        assert(not addon.TravelSupport.AppendAccess(saved, 1, target, {mapID = 10, x = .9, y = .5}, api))
        equal(#saved[1][1].points, 8)
    end)

    test("Taxi flight does not mark access waypoints as visited", function()
        local api = {GetMapWorldSize = function() return 1000, 1000 end,
            GetPlayerMapPosition = function() return {x = .2, y = .5} end}
        local target = {mapID = 10, x = .5, y = .5, objectiveIndex = 1}
        local saved, passed = {}, {}
        addon.TravelSupport.SaveAccess(saved, 1, target, {mapID = 10, x = .2, y = .5}, "Gate")
        local measured = {[1] = {marker = target, yards = 300}}
        addon.TravelSupport.ApplyAccess(api, {{id = 1}}, measured, {[10] = true}, saved, passed, true)
        equal(passed["1:1"].index, 1) equal(measured[1].marker.accessPoint, true)
    end)

    test("A new saved entrance for an alternate camp is usable while the old camp stays avoided", function()
        local api = {GetMapWorldSize = function() return 1000, 1000 end,
            GetPlayerMapPosition = function() return {x = .1, y = .5} end}
        local old = {mapID = 10, x = .2, y = .5, objectiveIndex = 1}
        local new = {mapID = 10, x = .5, y = .5, objectiveIndex = 1}
        local quest, camps, saved = {id = 1, level = 30}, {}, {}
        addon.CampAlternatives.Switch(api, quest, {marker = old}, {old, new}, camps, 0)
        addon.TravelSupport.SaveAccess(saved, 1, new, {mapID = 10, x = .4, y = .5}, "New gate")
        local snapshot = addon.NavigationController.Compute({mapAPI = api, questAPI = {}, playerLevel = 30,
            questMarkers = {[1] = {old, new}}, measurableQuestIDs = {1}, eligibleQuests = {quest}, previousObjectives = {},
            avoidedObjectives = {}, savedAccessPoints = saved, passedAccessPoints = {}, turnInLocations = {},
            campAvoidance = camps, now = 1})
        near(snapshot.measurements[1].marker.x, .4)
        near(snapshot.measurements[1].objectiveMarker.x, .5)
        equal(snapshot.measurements[1].marker.accessPoint, true)
    end)

    test("Rewards read the explicit quest ID and separate guaranteed from choose-one items", function()
        local function ID(id) equal(id, 7) end
        local reward = addon.QuestRewards.Read({money = function(id) ID(id) return 12345 end,
            fixedCount = function(id) ID(id) return 1 end, choicesCount = function(id) ID(id) return 2 end,
            fixed = function(index, id) ID(id) equal(index, 1) return "Potion", nil, 3, 1, true, 10 end,
            choices = function(index, id) ID(id) return index == 1 and "Sword" or "Staff", nil, 1, 2, true, 20 + index end}, 7)
        equal(reward.money, 12345) equal(#reward.fixed, 1) equal(#reward.choices, 2)
        local description = addon.QuestRewards.Describe(reward)
        assert(description:find("1g 23s 45c", 1, true))
        assert(description:find("Potion x3", 1, true)) assert(description:find("Choose one reward:", 1, true))
        assert(description:find("Sword x1", 1, true)) assert(description:find("Staff x1", 1, true))
    end)

    test("Partial reward data stays unknown and distinguishes zero rewards from missing APIs", function()
        local pending = addon.QuestRewards.Read({fixedCount = function() return 1 end, fixed = function() return nil, nil, nil, nil, nil, 99 end}, 7)
        equal(pending.pending, true) equal(pending.fixed[1].itemID, 99)
        local text = addon.QuestRewards.Describe(pending)
        assert(text:find("Item #99", 1, true)) assert(text:find("quantity unknown", 1, true))
        assert(text:find("unavailable", 1, true))
        equal(addon.QuestRewards.Describe(addon.QuestRewards.Read({}, 7)), addon.L.RewardsUnavailable)
        local empty = addon.QuestRewards.Read({money = function() return 0 end, fixedCount = function() return 0 end,
            choicesCount = function() return 0 end}, 7)
        equal(addon.QuestRewards.Describe(empty), addon.L.NoExtraRewards)
        local broken = addon.QuestRewards.Read({money = function() error("unavailable") end,
            fixedCount = function() return math.huge end, choicesCount = function() return -1 end}, 7)
        equal(broken.fixedCount, nil) equal(broken.money, nil)
    end)
end
