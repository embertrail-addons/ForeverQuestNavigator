return function(test, addon, equal, near)
    test("Travel preparation ignores short trips, missing data and specialized bags", function()
        local containers = { GetContainerNumFreeSlots = function(bag) return bag == 0 and 2 or 20, bag == 0 and 0 or 32 end }
        local durability = function(slot) if slot == 5 then return 25, 100 end end
        equal(addon.TravelPreparation.Describe({yards = 1499}, {}, containers, durability, 4), nil)
        equal(addon.TravelPreparation.Describe({yards = 1500}, {showTravelPreparation = false}, containers, durability, 4), nil)
        equal(addon.TravelPreparation.Describe({yards = 2000}, {}, nil, nil), nil)
        local text = addon.TravelPreparation.Describe({yards = 1500}, {}, containers, durability, 4)
        assert(text:find("2 general bag slots", 1, true))
        assert(text:find("25%", 1, true))
        containers.GetContainerNumFreeSlots = function() return 4, 0 end
        equal(addon.TravelPreparation.Describe({yards = 1500}, {}, containers, function() return 26, 100 end, 4), nil)
    end)

    test("Quest actions share selection semantics and reject unavailable objectives", function()
        local state = { quest = {id = 7}, manual = 9, flying = true, avoided = {}, previous = {}, skipped = {}, order = 0,
            distances = {[7] = {[1] = {yards = 10}}} }
        addon.QuestActions.Apply(state, "hold")
        equal(state.manual, 7) equal(state.flightID, 7) equal(state.held.id, 7)
        addon.QuestActions.Apply(state, "objective", 2)
        equal(state.lock, nil)
        addon.QuestActions.Apply(state, "objective", 1)
        equal(state.lock.index, 1)
        addon.QuestActions.Apply(state, "avoid", 1)
        equal(state.lock, nil) equal(state.avoided[7][1], true)
        addon.QuestActions.Apply(state, "restoreObjectives")
        equal(next(state.avoided), nil)
        local effect = addon.QuestActions.Apply(state, "skip", state.quest)
        equal(effect.undo.id, 7) equal(state.manual, nil) equal(state.order, 1)
        addon.QuestActions.Apply(state, "skip", state.quest)
        equal(state.order, 1)
        addon.QuestActions.Apply(state, "restore", 7)
        equal(state.skipped[7], nil)
    end)

    test("Navigation snapshot keeps nearest usable objective and clears stale locks", function()
        local input = { mapAPI = {
            GetPlayerMapPosition = function() return {x = .25, y = .25} end,
            GetMapWorldSize = function() return 1000, 1000 end,
        }, questAPI = {}, questieReady = false, playerLevel = 30,
            eligibleQuests = {{id = 7, level = 30}, {id = 8, level = 30}},
            questMarkers = {[7] = {{mapID = 10, x = .75, y = .25, objectiveIndex = 1},
                {mapID = 10, x = .35, y = .25, objectiveIndex = 2}}},
            measurableQuestIDs = {7, 8}, previousObjectives = {}, objectiveLock = {questID = 7, index = 99},
            avoidedObjectives = {}, savedAccessPoints = {}, passedAccessPoints = {}, turnInLocations = {} }
        local snapshot = addon.NavigationController.Compute(input)
        near(snapshot.measurements[7].yards, 100)
        equal(snapshot.measurements[7].marker.objectiveIndex, 2)
        equal(snapshot.previousObjectives[7], 2) equal(snapshot.objectiveLock, nil)
        equal(snapshot.measurements[8], nil) equal(snapshot.ranked[1].id, 7)
        equal(snapshot.ranked[2].id, 8)
    end)

    test("Zone overview uses actual targets across borders and retains unknown quests", function()
        local mapType = {Zone = 3}
        local api = {GetMapInfo = function(id) return {name = "Zone " .. id, mapType = 3} end}
        local quests = {{id = 1, level = 30}, {id = 2, level = 36, readyToTurnIn = true},
            {id = 3, level = 40}, {id = 4, level = 10}}
        local snapshot = {playerLevel = 30, measurements = {
            [1] = {yards = 200, marker = {mapID = 10}, objectiveMarker = {mapID = 20}},
            [2] = {yards = 300, marker = {mapID = 20}},
            [3] = {yards = 700, marker = {mapID = 10}},
        }, objectiveDistances = {[1] = {[1] = {}, [2] = {}}}}
        local zones = addon.BuildZoneOverview(api, mapType, quests, snapshot)
        equal(#zones, 3) equal(zones[1].id, 20) equal(zones[1].quests, 2)
        equal(zones[1].objectives, 2) equal(zones[1].turnIns, 1)
        equal(zones[1].suitable, 1) equal(zones[1].difficult, 1)
        equal(zones[2].id, 10) equal(zones[3].id, nil)
        equal(zones[3].objectives, 0)
    end)

    test("Regression export excludes names and faithfully replays return and unknown ranking", function()
        local quests = {{id = 1, title = "PRIVATE TITLE", level = 30, note = "PRIVATE NOTE"},
            {id = 2, level = 30}, {id = 3, level = 30}}
        local measurements = {[1] = {yards = 100}, [2] = {yards = 200}}
        local journeys = {[1] = {totalYards = 2100, extraYards = 2000}}
        local ranked = addon.QuestPrioritizer.RankByDistance(quests, measurements, nil, 30, journeys)
        local snapshot = {playerLevel = 30, measurements = measurements, journeys = journeys, ranked = ranked}
        local fixture = addon.RegressionFixture.Capture(quests, snapshot)
        equal(fixture.expected[1], 2)
        local encoded = addon.RegressionFixture.Encode(fixture)
        assert(not encoded:find("PRIVATE", 1, true))
        equal(addon.RegressionFixture.Replay(fixture), true)
        fixture.expected[1] = 1
        equal(pcall(addon.RegressionFixture.Replay, fixture), false)
    end)

    test("Event controller avoids full refresh for XP and stops on logout", function()
        local calls = {}
        local context = setmetatable({hasMeasurements = function() return true end, visible = function() return true end},
            {__index = function(_, key) return function() calls[#calls + 1] = key end end})
        addon.EventController.Handle(context, "PLAYER_XP_UPDATE")
        equal(table.concat(calls, ","), "captureXP,measure")
        calls = {}
        addon.EventController.Handle(context, "PLAYER_LOGOUT")
        equal(table.concat(calls, ","), "saveSession")
        calls = {}
        addon.EventController.Handle(context, "BAG_UPDATE_DELAYED")
        equal(table.concat(calls, ","), "taxi,updateQuestLog,refresh")
    end)

    test("Theme toggles preserve texture alpha and opaque text", function()
        local texture, label = {}, {}
        function texture:SetColorTexture(r, g, b, a) self.r, self.g, self.b, self.alpha = r, g, b, a end
        function label:SetTextColor(r, g, b) self.r, self.g, self.b = r, g, b end
        addon.UI.Theme.Bind(texture, "stripe", .11)
        addon.UI.Theme.Bind(label, "heading", nil, "text")
        addon.UI.Theme.Apply(true)
        near(texture.alpha, .11) near(label.g, .94)
        addon.UI.Theme.Apply(false)
        near(texture.alpha, .11) near(label.g, .82)
    end)
end
