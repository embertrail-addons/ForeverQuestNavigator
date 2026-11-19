local addonName = "ForeverQuestNavigator"
local testsPassed = 0

local function equal(actual, expected)
    assert(actual == expected, ("Expected %s, got %s"):format(tostring(expected), tostring(actual)))
end

local function near(actual, expected)
    assert(math.abs(actual - expected) < 0.000001, ("Expected about %s, got %s"):format(expected, actual))
end

local function test(name, run)
    run()
    testsPassed = testsPassed + 1
    print("PASS " .. name)
end

local function loadAddon(env, includeBootstrap)
    local addon = {}
    local interface
    for line in io.lines(addonName .. ".toc") do
        interface = interface or line:match("^## Interface: (%d+)$")
        if line:match("%.lua$") then
            local path = line:gsub("\\", "/")
            local chunk = assert(loadfile(path))
            if path ~= "Core/Bootstrap.lua" or includeBootstrap then
                setfenv(chunk, env)(addonName, addon)
            end
        end
    end
    equal(interface, "16001")
    return addon
end

local addon = loadAddon(getfenv(), false)

test("Nearly complete hints require known counters and only give attainable quests a small bonus", function()
    local goals = { { text = "Enemies", type = "monster", numFulfilled = 8, numRequired = 10 } }
    local api = { GetQuestObjectives = function() return goals end }
    local progress = addon.QuestTools.Progress(api, 1)
    equal(progress.nearly, true)
    equal(progress.remaining, 2)
    local quest = { id = 1, level = 10, progress = progress }
    equal(addon.QuestTools.ProgressHint(quest), "Almost done · 2 enemies left")
    equal(addon.QuestPrioritizer.GetProgressBonus(quest, 10), 30)
    local other = { id = 2, level = 10 }
    local ranked = addon.QuestPrioritizer.RankByDistance({other, quest}, {[1] = {yards = 105}, [2] = {yards = 100}}, {other, quest}, 10)
    equal(ranked[1].id, 1)
    quest.level = 14
    equal(addon.QuestPrioritizer.GetProgressBonus(quest, 10), 0)
    goals[1].numFulfilled = nil
    equal(addon.QuestTools.Progress(api, 1), nil)
    goals[1].numFulfilled, goals[1].numRequired = 0, 1
    equal(addon.QuestTools.Progress(api, 1).nearly, false)
end)

test("Access search is literal, matches German names and distinguishes active from turned-in quests", function()
    local entries = {
        {questID = 1, title = "Ältere Quest", zone = "Hillsbrad", name = "Cave [north]"},
        {questID = 2, title = "Other quest", zone = "Alterac", name = "Entrance"},
    }
    local api = { IsOnQuest = function(id) return id == 1 end, IsQuestFlaggedCompleted = function(id) return id == 2 end }
    equal(#addon.QuestTools.FilterAccess(entries, "ältere", "all", api), 1)
    equal(#addon.QuestTools.FilterAccess(entries, "[north]", "all", api), 1)
    equal(addon.QuestTools.FilterAccess(entries, "", "current", api)[1].questID, 1)
    equal(addon.QuestTools.FilterAccess(entries, "", "completed", api)[1].questID, 2)
    equal(#addon.QuestTools.FilterAccess(entries, "Hillsbrad", "completed", api), 0)
end)

test("Quest notes retain saved positions and have no selection side effects", function()
    local saved = {}
    local point = {mapID = 10, x = 0.2, y = 0.3}
    equal(addon.QuestTools.ToggleNote(saved, 1, "Later", point, true), true)
    point.x = 0.8
    local api = { IsOnQuest = function() return false end }
    local notes = addon.QuestTools.Notes(saved, api, function() end)
    near(notes[1].point.x, 0.2)
    equal(notes[1].status, "Remembered for later")
    equal(addon.QuestTools.ToggleNote(saved, 1), false)
    equal(next(saved), nil)
end)

test("Access management distinguishes objectives and retains unrelated records", function()
    local point = { mapID = 10, x = 0.3, y = 0.4 }
    local saved = { [1] = { [0] = { point = point, name = "A" }, [2] = { point = point, name = "B" } },
        [2] = { [1] = { point = point, name = "C" } }, bad = "ignore" }
    local entries = addon.TravelSupport.ListAccess(saved, { GetMapInfo = function() return { name = "Zone" } end },
        function(id) return "Quest " .. id end)
    equal(#entries, 3)
    equal(entries[2].index, 2)
    assert(addon.TravelSupport.RenameAccess(saved, 1, 2, "  New name  "))
    equal(saved[1][2].name, "New name")
    equal(saved[1][0].name, "A")
    addon.TravelSupport.RemoveAccess(saved, 1, 2)
    equal(saved[1][2], nil)
    equal(saved[2][1].name, "C")
    addon.TravelSupport.RemoveAccess(saved, 1, 0)
    equal(saved[1], nil)
end)

test("Known return travel can outweigh proximity without overriding difficulty tiers", function()
    local quests = { { id = 1, level = 10 }, { id = 2, level = 10 } }
    local measurements = { [1] = { yards = 100 }, [2] = { yards = 200 } }
    local journeys = { [1] = { extraYards = 2000 }, [2] = { extraYards = 100 } }
    equal(addon.QuestPrioritizer.RankByDistance(quests, measurements, nil, 10)[1].id, 1)
    equal(addon.QuestPrioritizer.RankByDistance(quests, measurements, nil, 10, journeys)[1].id, 2)
    quests[2].level = 14
    equal(addon.QuestPrioritizer.RankByDistance(quests, measurements, nil, 10, journeys)[1].id, 1)
    equal(addon.TravelSupport.PlanningPenalty({ readyToTurnIn = true }, nil, true), 0)
    equal(addon.TravelSupport.PlanningPenalty({}, nil, true), 200)
end)

test("Journey estimates require known unfinished goals and include a saved access exit", function()
    local map = { GetMapWorldSize = function() return 1000, 1000 end }
    local first = { mapID = 10, x = 0.2, y = 0.5, objectiveIndex = 1 }
    local second = { mapID = 10, x = 0.4, y = 0.5, objectiveIndex = 2 }
    local finish = { mapID = 10, x = 0.1, y = 0.5 }
    local objectives = { { text = "A" }, { text = "B" } }
    local distances = { { marker = first }, { marker = second } }
    local journey = addon.TravelSupport.BuildJourney(map, {}, { yards = 100, marker = first }, objectives, distances, finish)
    near(journey.totalYards, 600)
    near(journey.returnYards, 300)
    distances[2] = nil
    equal(addon.TravelSupport.BuildJourney(map, {}, { yards = 100, marker = first }, objectives, distances, finish), nil)
    objectives[2].finished = true
    local measured = { yards = 50, travelYards = 150, marker = finish, objectiveMarker = first, accessLeg = 100, accessExit = finish }
    journey = addon.TravelSupport.BuildJourney(map, {}, measured, objectives, distances, { mapID = 10, x = 0, y = 0.5 })
    near(journey.totalYards, 350)
    near(journey.returnYards, 200)
    equal(journey.goals, 1)
end)

test("Saved access navigation switches to the objective at the gate and rejects a distant replacement spawn", function()
    local playerX = 0
    local map = { GetMapWorldSize = function() return 1000, 1000 end,
        GetPlayerMapPosition = function() return { x = playerX, y = 0.5 } end }
    local target = { mapID = 10, x = 0.4, y = 0.5, objectiveIndex = 1 }
    local saved, passed = {}, {}
    assert(addon.TravelSupport.SaveAccess(saved, 1, target, { mapID = 10, x = 0.2, y = 0.5 }, "Gate"))
    local measured = { [1] = { yards = 400, marker = target } }
    addon.TravelSupport.ApplyAccess(map, { { id = 1 } }, measured, { [10] = true }, saved, passed)
    equal(measured[1].marker.accessPoint, true)
    near(measured[1].marker.x, 0.2)
    equal(measured[1].objectiveMarker, target)
    near(measured[1].travelYards, 400)
    playerX, measured[1] = 0.2, { yards = 200, marker = target }
    addon.TravelSupport.ApplyAccess(map, { { id = 1 } }, measured, { [10] = true }, saved, passed)
    equal(measured[1].marker, target)
    equal(passed["1:1"], true)
    local other = { mapID = 10, x = 0.9, y = 0.5, objectiveIndex = 1 }
    equal(addon.TravelSupport.GetAccess(saved, 1, other, map), nil)
end)

test("Session XP crosses a level boundary once and played time resumes without counting offline time", function()
    local session = addon.Session.New(nil, 100)
    session:CaptureXP(34, 900, 1000)
    session:CaptureXP(34, 200, 1200)
    equal(session.data.xp, 0)
    session:CaptureXP(35, 200, 1200)
    session:CaptureXP(35, 200, 1200)
    equal(session.data.xp, 300)
    equal(session.data.levels, 1)
    session:TurnIn(1, "Repeatable", 300)
    session:TurnIn(1, "Repeatable", 0)
    session:TurnIn(2, nil, nil)
    equal(session.data.completed, 3)
    equal(session.data.questXP, 300)
    equal(session.data.unknownRewards, 1)
    session:Save(160)
    local resumed = addon.Session.New(session.data, 1000)
    resumed:CaptureXP(35, 200, 1200)
    resumed:CaptureXP(35, 250, 1200)
    equal(resumed.data.xp, 350)
    assert(resumed:Describe(1060):find("0 h 2 min", 1, true))
    resumed:CaptureXP(38, 100, 1600)
    equal(resumed.data.lowerBound, true)
    for id = 3, 25 do resumed:TurnIn(id, nil, 10) end
    equal(#resumed.data.recent, 20)
end)

test("Questie access hints respect phase and objective association, and route finishers use the nearest known spawn", function()
    local extras = {
        { { [100] = { {45, 50}, {50, 50, 3} } }, 3, "Cave entrance", 2 },
        { { [100] = { {49, 50} } }, 3, "Other objective", 1 },
        { nil, 3, "Path helper", 2, { { "monster", 7 } } },
    }
    local modules = {
        ZoneDB = { GetUiMapIdByAreaId = function(_, area) return area / 10 end },
        Phasing = { IsSpawnVisible = function(phase) return phase ~= 3 end },
    }
    local env = setmetatable({
        QuestieLoader = { ImportModule = function(_, name) return modules[name] end },
        LibQuestieDB = {
            Quest = { extraObjectives = function() return extras end, finishedBy = function() return { {7} } end },
            Npc = { spawns = function() return { [100] = { {30, 50}, {90, 50} } } end, name = function() return "Finisher" end },
            Object = {},
        },
    }, { __index = _G })
    local routes = loadAddon(env, false).QuestieRoutes
    local map = { GetMapWorldSize = function() return 1000, 1000 end,
        GetMapInfo = function() return { mapType = 3 } end }
    local target = { mapID = 10, x = 0.5, y = 0.5, objectiveIndex = 2 }
    local hints = routes.GetAccessHints(map, {Zone = 3}, {[10] = true}, 1, target)
    equal(#hints, 3)
    equal(hints[1].text, "Cave entrance")
    near(hints[1].point.x, 0.45)
    local finisher, known, name = routes.GetOutdoorTurnInMarker(map, {Zone = 3}, {[10] = true}, 1, target)
    equal(known, true)
    near(finisher.x, 0.3)
    equal(name, "Finisher")
    equal(extras[1][1][100][1][1], 45)
end)

test("Arrival has a departure margin and resets for a new objective or missing coordinates", function()
    local quest = { id = 1 }
    local measured = { yards = 11, marker = { mapID = 10, x = 0.5, y = 0.5, objectiveIndex = 1 } }
    local state, arrived = addon.TrackerState.Arrival(nil, quest, measured)
    equal(arrived, true)
    measured.yards = 18
    state, arrived = addon.TrackerState.Arrival(state, quest, measured)
    equal(arrived, true)
    measured.marker.objectiveIndex = 2
    state, arrived = addon.TrackerState.Arrival(state, quest, measured)
    equal(arrived, false)
    measured.yards = 10
    state, arrived = addon.TrackerState.Arrival(state, quest, measured)
    equal(arrived, true)
    measured.yards = 21
    state, arrived = addon.TrackerState.Arrival(state, quest, measured)
    equal(arrived, false)
    state, arrived = addon.TrackerState.Arrival(state, quest, nil)
    equal(state, nil)
    equal(arrived, false)
end)

test("Progress counts unfinished goals and ready quests, excluding skipped and special objectives", function()
    local quests = { { id = 1 }, { id = 2, readyToTurnIn = true }, { id = 3 },
        { id = 4, special = true }, { id = 5 }, { id = 6, failed = true } }
    local summary = addon.TrackerState.Progress(quests, { GetQuestObjectives = function(id)
        if id == 1 then return { { text = "A" }, { text = "B", finished = true }, { text = "C" } } end
    end }, { [5] = true })
    equal(summary.open, 2)
    equal(summary.turnIns, 1)
    equal(summary.unknown, 1)
end)

test("A held quest releases on completion, removal or failure; a held turn-in waits for removal", function()
    local hold = { id = 1, turnIn = false }
    assert(not addon.TrackerState.HoldEnded(hold, { { id = 1 } }))
    equal(addon.TrackerState.HoldEnded(hold, { { id = 1, readyToTurnIn = true } }), true)
    equal(addon.TrackerState.HoldEnded(hold, { { id = 1, failed = true } }), true)
    equal(addon.TrackerState.HoldEnded(hold, {}), true)
    hold.turnIn = true
    assert(not addon.TrackerState.HoldEnded(hold, { { id = 1, readyToTurnIn = true } }))
end)

test("Offer announcements are silent on initial scan and do not repeat on refresh or reentry", function()
    local seen, fresh = addon.TrackerState.NewOffers(nil, { { id = 1, recommended = true } })
    equal(next(fresh), nil)
    seen, fresh = addon.TrackerState.NewOffers(seen, { { id = 2, recommended = true } })
    equal(fresh[2], true)
    seen, fresh = addon.TrackerState.NewOffers(seen, {})
    seen, fresh = addon.TrackerState.NewOffers(seen, { { id = 2, recommended = true } })
    equal(next(fresh), nil)
end)

test("Target groups use an 80-yard anchor radius without chaining distant targets together", function()
    local map = { GetMapWorldSize = function() return 1000, 1000 end }
    local function entry(id, x, mapID)
        return { quest = { id = id }, target = { mapID = mapID or 10, x = x, y = 0.5 }, yards = id * 10 }
    end
    local groups = addon.BuildTargetGroups(map, { entry(1, 0.1), entry(2, 0.16), entry(3, 0.22), entry(4, 0.1, 20) }, "Test zone")
    equal(#groups, 3)
    equal(#groups[1].entries, 2)
    equal(groups[1].place, "Test zone")
    equal(groups[2].entries[1].quest.id, 3)
    equal(groups[3].entries[1].quest.id, 4)
end)

test("Long-distance navigation holds small improvements but switches for clear gains or lost targets", function()
    local quests = { { id = 1, level = 10 }, { id = 2, level = 10 } }
    local measured = { [1] = { yards = 1000 }, [2] = { yards = 950 } }
    local ranked = addon.QuestPrioritizer.RankByDistance(quests, measured, quests, 10)
    equal(ranked[1].id, 1)
    measured[2].yards = 850
    ranked = addon.QuestPrioritizer.RankByDistance(quests, measured, ranked, 10)
    equal(ranked[1].id, 2)
    measured[2] = nil
    ranked = addon.QuestPrioritizer.RankByDistance(quests, measured, ranked, 10)
    equal(ranked[1].id, 1)
    quests[1].level = 13
    measured[2] = { yards = 1050 }
    ranked = addon.QuestPrioritizer.RankByDistance(quests, measured, ranked, 10)
    equal(ranked[1].id, 2)
end)

test("Unknown objective, XP and level data do not improve offer scores", function()
    local offer = { level = 10, yards = 60, objectiveYards = 400, levelPenalty = 0, xp = 1000 }
    local known = addon.Recommendation.ScoreOffer(offer)
    offer.xp = nil
    assert(addon.Recommendation.ScoreOffer(offer) > known)
    known = addon.Recommendation.ScoreOffer(offer)
    offer.objectiveYards = nil
    assert(addon.Recommendation.ScoreOffer(offer) > known)
    known = addon.Recommendation.ScoreOffer(offer)
    offer.level = nil
    offer.levelPenalty = addon.QuestPrioritizer.GetLevelPenalty(offer, 10)
    assert(addon.Recommendation.ScoreOffer(offer) > known)
    local reason = addon.Recommendation.Describe({ id = 1 }, nil, 10)
    assert(reason:find("coordinates unknown", 1, true))
    assert(reason:find("level unknown", 1, true))
    assert(reason:find("route unknown", 1, true))
end)

test("Diagnostic report records the selected objective and distinguishes distance score from route reasons", function()
    local report = addon.Recommendation.BuildReport({
        version = "0.1.55", playerLevel = 34, mapID = 10, activeID = 36, manual = true,
        quests = { { id = 36, level = 36 }, { id = 37 } },
        measurements = { [36] = { yards = 200, marker = { mapID = 20, x = 0.4, y = 0.5, objectiveIndex = 2 } } },
        reason = "Manual selection", route = "Follow-up route",
    })
    assert(report:find("version=0.1.55", 1, true))
    assert(report:find("mode=manual quest", 1, true))
    assert(report:find("activeQuest=36", 1, true))
    assert(report:find("distanceScore=300.0 map=20 x=0.4 y=0.5 objective=2", 1, true))
    assert(report:find("quest=37 level=unknown", 1, true))
    assert(report:find("selectionReasons:\nManual selection", 1, true))
    assert(report:find("routeDetails:\nFollow-up route", 1, true))
    assert(not report:find("playerName", 1, true))
    local empty = addon.Recommendation.BuildReport({})
    assert(empty:find("activeQuest=none", 1, true))
end)

test("Outing order keeps the usual recommendation when savings are small or a closer quest is too high", function()
    local map = { GetMapWorldSize = function() return 1000, 1000 end }
    local ranked = { { id = 1, level = 10 }, { id = 2, level = 12 } }
    local measurements = {
        [1] = { yards = 600, marker = { mapID = 10, x = 0.8, y = 0.5 } },
        [2] = { yards = 570, marker = { mapID = 10, x = 0.77, y = 0.5 } },
    }
    local plan = addon.QuestRoute.PlanOuting(map, ranked, measurements, 10)
    equal(plan.stops[1].id, 1)
    equal(plan.saving, 0)
    ranked[2].level = 13
    equal(addon.QuestRoute.PlanOuting(map, ranked, measurements, 10), nil)
end)

test("Stops along the way include reachable objectives and turn-ins with a small detour", function()
    local map = { GetMapWorldSize = function() return 1000, 1000 end }
    local ranked = { { id = 1, level = 10 }, { id = 2, level = 11 },
        { id = 3, level = 13, readyToTurnIn = true }, { id = 4, level = 10 } }
    local measurements = {
        [1] = { yards = 600, marker = { mapID = 10, x = 0.8, y = 0.5 } },
        [2] = { yards = 400, marker = { mapID = 10, x = 0.6, y = 0.5 } },
        [3] = { yards = 200, marker = { mapID = 10, x = 0.4, y = 0.5 } },
        [4] = { yards = 500, marker = { mapID = 10, x = 0.2, y = 1 } },
    }
    local stops = addon.QuestRoute.GetStopsOnApproach(map, ranked[1], ranked, measurements, 10)
    equal(#stops, 2)
    equal(stops[1].quest.id, 3)
    equal(stops[2].quest.id, 2)
end)

test("Quest log reads accepted player-facing quests and quest state", function()
    local entries = {
        { questID = 0, isHeader = true, isCollapsed = true },
        { questID = 10, title = "Collect supplies", level = 8 },
        { questID = 11, isHidden = true },
        { questID = 12, isInternalOnly = true },
        { questID = 13, isTask = true },
        { questID = 14 },
        [8] = { questID = 15 },
        [9] = { questID = 16 },
    }
    local quests = addon.QuestLog.Read({
        GetNumQuestLogEntries = function() return 9, 7 end,
        GetInfo = function(index) return entries[index] end,
        IsOnQuest = function(id) return id ~= 14 end,
        IsComplete = function(id) return id == 10 end,
        IsFailed = function(id) return id == 15 end,
        IsQuestDisabledForSession = function(id) return id == 16 end,
    })
    equal(#quests, 3)
    equal(quests[1].id, 10)
    equal(quests[1].title, "Collect supplies")
    equal(quests[1].level, 8)
    equal(quests[1].readyToTurnIn, true)
    equal(quests[2].failed, true)
    equal(quests[3].disabled, true)
    equal(addon.QuestLog.Read({}), nil)
end)

test("Ranking uses level then quest ID and excludes failed and disabled quests", function()
    local quests = {
        { id = 1, level = 0 },
        { id = 20, level = 19 },
        { id = 30, level = 18 },
        { id = 4, level = 18, readyToTurnIn = true },
        { id = 5, level = 2, failed = true },
        { id = 6, level = 2, disabled = true },
        { id = 7 },
    }
    local ranked = addon.QuestPrioritizer.Rank(quests)
    equal(#ranked, 5)
    equal(ranked[1].id, 4)
    equal(ranked[2].id, 30)
    equal(ranked[3].id, 20)
    equal(ranked[4].id, 1)
    equal(ranked[5].id, 7)
    equal(quests[1].id, 1)
end)

test("Ranking includes elite quests and respects skips", function()
    local quests = {
        { id = 1, level = 5, elite = true, readyToTurnIn = true },
        { id = 2, level = 6 },
        { id = 3, level = 7, elite = true },
        { id = 4, level = 8, elite = false },
    }
    equal(addon.QuestPrioritizer.Rank(quests)[1].id, 1)
    local ranked = addon.QuestPrioritizer.Rank(quests, { [1] = true, [2] = true })
    equal(#ranked, 2)
    equal(ranked[1].id, 3)
end)

local mapType = { Continent = 2, Zone = 3, Dungeon = 4, Micro = 5 }

test("Local quest markers cover the current subzone and its zone, without continent markers", function()
    local playerMapID = 11
    local maps = {
        [1] = { mapType = mapType.Continent },
        [10] = { mapType = mapType.Zone, name = "Westfall", parentMapID = 1 },
        [11] = { mapType = mapType.Micro, parentMapID = 10 },
        [12] = { mapType = mapType.Dungeon, name = "Deadmines", parentMapID = 10 },
        [13] = { mapType = mapType.Micro, parentMapID = 13 },
    }
    local mapAPI = {
        GetBestMapForUnit = function(unit)
            equal(unit, "player")
            return playerMapID
        end,
        GetMapInfo = function(id) return maps[id] end,
    }
    local questAPI = { GetQuestsOnMap = function(id)
        assert(id ~= 1, "Continent markers do not imply a local quest")
        return ({
            [10] = { { questID = 5, x = 0.3, y = 0.4 }, { questID = 6, isMapIndicatorQuest = true } },
            [11] = { { questID = 7 } },
        })[id]
    end }

    local localQuests, name = addon.QuestLocation.GetLocalQuestMarkers(mapAPI, questAPI, mapType)
    equal(name, "Westfall")
    equal(localQuests[5][1].mapID, 10)
    equal(localQuests[5][1].x, 0.3)
    equal(localQuests[6], nil)
    equal(#localQuests[7], 0)

    playerMapID = 12
    local dungeonQuests = addon.QuestLocation.GetLocalQuestMarkers(mapAPI, questAPI, mapType)
    equal(next(dungeonQuests), nil)
    for _, id in ipairs({ 0, 1, 13 }) do
        playerMapID = id
        equal(addon.QuestLocation.GetLocalQuestMarkers(mapAPI, questAPI, mapType), nil)
    end
    equal(addon.QuestLocation.GetLocalQuestMarkers(mapAPI, nil, mapType), nil)
end)

test("Distances use the closest marker and scale each axis in yards", function()
    local lookups = {}
    local api = {
        GetPlayerMapPosition = function(id, unit)
            equal(unit, "player")
            lookups[id] = (lookups[id] or 0) + 1
            if id == 99 then return { x = 0, y = 0 } end
            return { x = 0.25, y = 0.25 }
        end,
        GetMapWorldSize = function(id)
            if id == 77 then return 1000, 0 end
            return 1000, 500
        end,
    }
    local markers = {
        [1] = { { mapID = 10, x = 0.75, y = 0.75 }, { mapID = 10, x = 0.55, y = 0.65 } },
        [2] = { { mapID = 10, x = 0.25, y = 0.25 } },
        [3] = { { mapID = 99, x = 0.25, y = 0.25 } },
        [4] = { { mapID = 77, x = 0.25, y = 0.25 } },
    }
    local measurements = addon.QuestLocation.MeasureQuests(api, markers, { 1, 2, 3, 4, 5 })
    equal(math.floor(measurements[1].yards + 0.5), 361)
    equal(measurements[2].yards, 0)
    equal(measurements[3], nil)
    equal(measurements[4], nil)
    equal(measurements[5], nil)
    equal(lookups[10], 1)
    near(measurements[1].east, 300 / measurements[1].yards)
    near(measurements[1].north, -200 / measurements[1].yards)
    equal(measurements[2].east, nil)
end)

test("Direction rotates with the character and handles unavailable facing", function()
    local east = { east = 1, north = 0 }
    local right, forward = addon.QuestLocation.GetRelativeDirection(east, 0)
    near(right, 1)
    near(forward, 0)
    right, forward = addon.QuestLocation.GetRelativeDirection(east, math.pi / 2)
    near(right, 0)
    near(forward, -1)
    right, forward = addon.QuestLocation.GetRelativeDirection(east, 3 * math.pi / 2)
    near(right, 0)
    near(forward, 1)
    equal(addon.QuestLocation.GetRelativeDirection(east, nil), nil)
    equal(addon.QuestLocation.GetRelativeDirection(east, math.huge), nil)
    equal(addon.QuestLocation.GetRelativeDirection(nil, 0), nil)
end)

test("Area overview counts distinct local goals and excludes avoided goals and neighboring zones", function()
    local api = {
        GetMapInfo = function(id) return { mapType = mapType.Zone, name = "Zone " .. id } end,
        GetMapWorldSize = function() return 1000, 1000 end,
        GetPlayerMapPosition = function() return { x = 0.5, y = 0.5 } end,
    }
    local quests = { { id = 1 }, { id = 2, readyToTurnIn = true }, { id = 3 } }
    local markers = {
        [1] = {
            { mapID = 10, x = 0.6, y = 0.5, objectiveIndex = 1 },
            { mapID = 10, x = 0.7, y = 0.5, objectiveIndex = 1 },
            { mapID = 20, x = 0.6, y = 0.5, objectiveIndex = 2 },
            { mapID = 10, x = 0.8, y = 0.5, objectiveIndex = 3 },
        },
        [2] = { { mapID = 10, x = 0.9, y = 0.5 } },
        [3] = { { mapID = 20, x = 0.55, y = 0.5 } },
    }
    local overview = addon.BuildAreaOverview(api, mapType, 10, quests, markers,
        { [10] = true, [20] = true }, { [1] = { [3] = true } })
    equal(overview.objectives, 1)
    equal(overview.turnIns, 1)
    equal(#overview.entries, 2)
    equal(overview.entries[1].quest.id, 1)
    equal(overview.entries[2].quest.id, 2)
    equal(overview.entries[2].action, "turnIn")
end)

test("Ranking with a zone excludes remote and unmapped quests regardless of level", function()
    local quests = { { id = 1, level = 3 }, { id = 2, level = 5 }, { id = 3, level = 9 } }
    local ranked = addon.QuestPrioritizer.Rank(quests, nil, { [3] = true, [99] = true })
    equal(#ranked, 1)
    equal(ranked[1].id, 3)
    equal(#addon.QuestPrioritizer.Rank(quests, nil, {}), 0)
    equal(addon.QuestPrioritizer.Rank(quests)[1].id, 1)
end)

test("Distance sorting keeps unknown quests last and uses a margin to switch", function()
    local quests = { { id = 1 }, { id = 2 }, { id = 3 }, { id = 4 } }
    local measurements = { [2] = { yards = 120 }, [3] = { yards = 100 } }
    local ranked, previous = addon.QuestPrioritizer.RankByDistance(quests, measurements)
    equal(ranked[1].id, 3)
    equal(ranked[2].id, 2)
    equal(ranked[3].id, 1)
    equal(ranked[4].id, 4)

    measurements[2].yards = 90
    ranked, previous = addon.QuestPrioritizer.RankByDistance(quests, measurements, previous)
    equal(ranked[1].id, 3)
    measurements[2].yards = 75
    ranked, previous = addon.QuestPrioritizer.RankByDistance(quests, measurements, previous)
    equal(ranked[1].id, 2)

    measurements[2] = nil
    ranked, previous = addon.QuestPrioritizer.RankByDistance(quests, measurements, previous)
    equal(ranked[1].id, 3)
    equal(ranked[2].id, 1)
    equal(ranked[3].id, 2)
    equal(#previous, 1)

    local grouped = { [1] = { yards = 100 }, [2] = { yards = 88 }, [3] = { yards = 76 } }
    ranked = addon.QuestPrioritizer.RankByDistance(quests, grouped, quests)
    equal(ranked[1].id, 2)
end)

test("Difficulty tiers favor attainable quests while keeping turn-ins ranked by distance", function()
    local env = setmetatable({ UnitQuestTrivialLevelRange = function() return 6 end }, { __index = _G })
    local priority = loadAddon(env, false).QuestPrioritizer
    equal(priority.GetDifficulty({ level = 37 }, 34), "red")
    equal(priority.GetDifficulty({ level = 36 }, 34), "orange")
    equal(priority.GetDifficulty({ level = 35 }, 34), "orange")
    equal(priority.GetDifficulty({ level = 34 }, 34), "yellow")
    equal(priority.GetDifficulty({ level = 33 }, 34), "yellow")
    equal(priority.GetDifficulty({ level = 32 }, 34), "green")
    equal(priority.GetDifficulty({ level = 28 }, 34), "green")
    equal(priority.GetDifficulty({ level = 27 }, 34), "gray")
    local crown = { id = 1, level = 39 }
    local goldir = { id = 2, level = 36 }
    local hammer = { id = 3, level = 32 }
    local trivial = { id = 4, level = 27 }
    local quests = { trivial, hammer, goldir, crown }
    local distances = { [1] = { yards = 386 }, [2] = { yards = 786 }, [3] = { yards = 2146 }, [4] = { yards = 10 } }
    local ranked = priority.RankByDistance(quests, distances, { crown, goldir, hammer }, 34)
    equal(ranked[1], goldir)
    equal(ranked[2], hammer)
    equal(ranked[3], trivial)
    equal(ranked[4], crown)
    crown.readyToTurnIn = true
    ranked = priority.RankByDistance(quests, distances, nil, 34)
    equal(ranked[1], crown)
    ranked = priority.RankByDistance(quests, {}, nil, 34)
    equal(ranked[1], hammer)
end)

test("Navigation skips finished and blank goals and handles missing data", function()
    local api = {
        GetQuestObjectives = function(id)
            equal(id, 10)
            return {
                { text = "Wolves slain: 8/8", finished = true },
                { text = "", finished = false },
                { text = "Supplies collected: 2/6", finished = false },
            }
        end,
    }
    local nextObjective, index = addon.QuestLog.GetNextObjective(api, 10)
    equal(nextObjective.text, "Supplies collected: 2/6")
    equal(index, 3)
    equal(addon.QuestLog.GetNextObjective({ GetQuestObjectives = function() end }, 10), nil)
    equal(addon.QuestLog.GetNextObjective({}, 10), nil)
end)

test("Questie status reports missing, unloaded and loaded states", function()
    local missing = addon.ReadQuestieStatus({
        IsAddOnLoaded = function() return false, false end,
        DoesAddOnExist = function() return false end,
    })
    equal(missing, "Not installed")

    local loaded = false
    local api = {
        IsAddOnLoaded = function(name) equal(name, "Questie"); return true, loaded end,
        DoesAddOnExist = function(name) equal(name, "Questie"); return true end,
    }
    equal(addon.ReadQuestieStatus(api), "Not loaded")
    loaded = true
    equal(addon.ReadQuestieStatus(api), "Loaded")
    equal(addon.ReadQuestieStatus(nil), "Unknown")
end)

local function noOp() end

local function mockUI()
    local frames = {}
    local methods = {}
    for _, method in ipairs({
        "SetPoint", "SetClampedToScreen", "SetMovable", "SetBackdrop", "SetBackdropColor",
        "EnableMouse", "RegisterForDrag", "StartMoving", "StopMovingOrSizing",
        "ClearAllPoints", "SetJustifyH", "SetMaxLines", "SetAllPoints", "SetColorTexture", "SetBackdropBorderColor",
        "SetFontString", "SetFontObject", "SetNormalFontObject", "SetDisabledFontObject",
        "SetFrameStrata", "SetTexture", "SetTexCoord", "SetTextColor", "SetAtlas", "SetVertexColor",
        "SetHighlightFontObject",
        "RegisterForClicks", "EnableMouseWheel",
        "SetStartPoint", "SetThickness",
        "SetHighlightTexture",
        "SetMultiLine", "SetAutoFocus", "SetFocus", "HighlightText", "SetVerticalScroll",
        "SetMaxLetters", "ClearFocus",
    }) do
        methods[method] = noOp
    end

    function methods:RegisterEvent(event) self.events[event] = true end
    function methods:SetScript(script, callback) self.scripts[script] = callback end
    function methods:HookScript(script, callback)
        local previous = self.scripts[script]
        self.scripts[script] = function(...)
            if previous then previous(...) end
            callback(...)
        end
    end
    function methods:GetCenter() return 500, 400 end
    function methods:IsShown() return self.shown end
    methods.IsVisible = methods.IsShown
    function methods:Hide() self:SetShown(false) end
    function methods:Show() self:SetShown(true) end
    function methods:SetEnabled(enabled) self.enabled = enabled end
    function methods:SetChecked(checked) self.checked = checked end
    function methods:SetAlpha(alpha) self.alpha = alpha end
    function methods:SetFontString(label) self.fontString = label end
    function methods:GetFontString() return self.fontString end
    function methods:GetText() return self.text end
    function methods:GetFont() return "Fonts/FRIZQT__.TTF", 12, "" end
    function methods:SetFont(_, size) self.fontSize = size end
    function methods:IsTruncated() return self.truncated == true end
    function methods:StartMoving() self.startedMoving = (self.startedMoving or 0) + 1 end
    function methods:SetBackdropColor(_, _, _, alpha) self.backdropAlpha = alpha end
    function methods:SetColorTexture(_, _, _, alpha) self.colorAlpha = alpha end
    function methods:SetBackdropBorderColor(_, _, _, alpha) self.borderAlpha = alpha end
    function methods:IsMouseOver() return false end
    function methods:SetHeight(height) self.height = height end
    function methods:GetHeight() return self.height end
    function methods:SetSize(width, height) self.width, self.height = width, height end
    function methods:SetWidth(width) self.width = width end
    function methods:GetWidth() return self.width end
    function methods:GetEffectiveScale() return 0.5 end
    function methods:SetPoint(...) self.point = { ... } end
    function methods:GetFrameLevel() return 1 end
    function methods:SetFrameLevel() end

    function methods:Click(mouseButton)
        assert(self.shown and self.enabled ~= false, "Cannot click a hidden or disabled control")
        self.scripts.OnClick(self, mouseButton or "LeftButton")
    end

    function methods:CreateTexture()
        local texture = setmetatable({}, { __index = methods })
        self.textures = self.textures or {}
        self.textures[#self.textures + 1] = texture
        return texture
    end

    function methods:CreateLine()
        local line = setmetatable({}, { __index = methods })
        self.lines[#self.lines + 1] = line
        return line
    end

    function methods:SetEndPoint(_, _, x, y)
        self.tipX, self.tipY = x, y
    end

    function methods:CreateFontString()
        local fontString = setmetatable({ shown = true }, { __index = methods })
        self.labels[#self.labels + 1] = fontString
        return fontString
    end

    function methods:SetText(value) self.text = value end
    function methods:SetScrollChild(child) self.child = child end
    function methods:GetStringHeight()
        if not self.text or self.text == "" then return 0 end
        local _, lineBreaks = self.text:gsub("\n", "")
        return (self.fontSize or 12) * (1 + lineBreaks)
    end
    function methods:GetStringWidth()
        return #(self.text or "") * (self.fontSize or 12) * 0.5
    end

    function methods:SetShown(shown)
        if self.shown ~= shown then
            self.shown = shown
            local callback = self.scripts and self.scripts[shown and "OnShow" or "OnHide"]
            if callback then callback(self) end
        end
    end

    local function createFrame(_, _, parent)
        local frame = setmetatable({ events = {}, scripts = {}, labels = {}, lines = {}, shown = true }, { __index = methods })
        frame.parent = parent
        frames[#frames + 1] = frame
        return frame
    end
    local function createFont()
        return setmetatable({}, { __index = methods })
    end
    return frames, createFrame, createFont
end

test("Area groups expand into individual quests while single targets remain directly clickable", function()
    local frames, createFrame, createFont = mockUI()
    local env = setmetatable({ CreateFrame = createFrame, CreateFont = createFont,
        GetLocale = function() return "enUS" end, GameTooltip = { IsOwned = function() return false end } }, { __index = _G })
    local ui = loadAddon(env, false)
    local selected
    local settings = {}
    local area = ui.CreateAreaOverview({}, settings, { onLayout = noOp, openRouteStop = function(entry) selected = entry.quest.id end })
    local function entry(id) return { quest = { id = id, title = "Quest " .. id }, objectives = 1, yards = id * 10 } end
    area:SetData({ objectives = 3, turnIns = 0, entries = {}, groups = {
        { key = 1, place = "Camp", entries = { entry(1), entry(2) } },
        { key = 3, place = "Road", entries = { entry(3) } },
    } })
    frames[2]:Click()
    local group, single
    for _, frame in ipairs(frames) do
        if frame.group then group = frame end
        if frame.entry and frame.entry.quest.id == 3 then single = frame end
    end
    assert(group and group.text:find("2 quest targets", 1, true))
    single:Click()
    equal(selected, 3)
    group:Click()
    equal(settings.targetGroupsExpanded[1], true)
    local child
    for _, frame in ipairs(frames) do
        if frame.entry and frame.entry.quest.id == 2 then child = frame end
    end
    assert(child and child:IsShown())
    child:Click()
    equal(selected, 2)
end)

test("German UI uses the client locale and preserves quest text", function()
    local frames, createFrame, createFont = mockUI()
    local env = setmetatable({
        CreateFrame = createFrame,
        CreateFont = createFont,
        UIParent = {},
        GetLocale = function() return "deDE" end,
    }, { __index = _G })
    local localized = loadAddon(env, false)
    equal(localized.L.QuestNumber:format(42), "Quest 42")
    equal(localized.L.LevelAboveOne:format(1), "1 Stufe über dir")
    equal(localized.L.LevelAboveMany:format(2), "2 Stufen über dir")
    local tooltipText
    env.GameTooltip = {
        SetOwner = noOp,
        SetText = function(_, text) tooltipText = text end,
        Show = noOp,
        IsOwned = function() return false end,
    }
    local tracker = localized.CreateQuestTracker({ x = 0, y = 0, opacityPercent = 80 }, {}, "0.1.54")
    local content = frames[5]
    tracker:Render({ id = 42, title = "Test der Lehre", level = 30 }, "Räuber getötet: 0/8", {},
        {}, false, nil, "Questziel", nil, nil, nil, { localized.L.QuestXPLevelUp:format(250, 31) })
    tracker:RenderNearbyOffers({ { title = "Frostrache", yards = 60 } })
    equal(content.labels[1].text, "[30] Test der Lehre")
    equal(content.labels[2].text, "Räuber getötet: 0/8")
    equal(content.labels[5].text, "−  Zum Annehmen (1)")
    equal(content.labels[9].text, "~250 EP · Stufe 31 bei Abgabe möglich")
    equal(frames[3].width, 20)
    frames[3].scripts.OnEnter(frames[3])
    equal(tooltipText, "Einstellungen")
    equal(tracker.routeMap.text, "Karte")
    env.GetLocale = function() return "frFR" end
    equal(loadAddon(env, false).L.Settings, "Settings")
    localized.SetLanguage("deDE")
    equal(localized.L.Settings, "Einstellungen")
    localized.SetLanguage("auto")
    equal(localized.L.Settings, "Settings")
end)

test("TOC startup and quest events update the tracker with or without optional addons", function()
    local frames, createFrame, createFont = mockUI()
    local timers, messages = {}, {}
    local distanceTicker, directionTicker, questieTicker
    local quests, objectives, complete, loaded = {}, {}, {}, {}
    local elite, settingsByKey = {}, {}
    local currentMapID, pinsByMap = 10, nil
    local playerX = 0.25
    local facing, inInstance = 0, false
    local historyMenu
    local category = { GetID = function() return 101 end }
    local openedCategory, openedMap, selectedQuest, pingedQuest
    local reads = 0
    local api = {
        GetNumQuestLogEntries = function()
            reads = reads + 1
            return #quests, #quests
        end,
        GetInfo = function(index) return quests[index] end,
        SetSelectedQuest = function(id) selectedQuest = id end,
        IsOnQuest = function() return true end,
        IsComplete = function(id) return complete[id] == true end,
        IsEliteQuest = function(id) return elite[id] == true end,
        GetQuestObjectives = function(id) return objectives[id] end,
        GetQuestsOnMap = function(id)
            if pinsByMap then return pinsByMap[id] end
            local pins = {}
            for _, quest in ipairs(quests) do
                pins[#pins + 1] = { questID = quest.questID }
            end
            return pins
        end,
    }
    local questMenu
    local env = setmetatable({
        CreateFrame = createFrame,
        CreateFont = createFont,
        UIParent = { GetCenter = function() return 400, 300 end },
        C_QuestLog = api,
        C_Map = {
            OpenWorldMap = function(id) openedMap = id end,
            GetBestMapForUnit = function() return currentMapID end,
            GetMapInfo = function(id)
                return { mapType = mapType.Zone, name = id == 10 and "Westfall" or "Elwynn Forest" }
            end,
            GetPlayerMapPosition = function() return { x = playerX, y = 0.5 } end,
            GetMapWorldSize = function() return 1000, 500 end,
        },
        Enum = { UIMapType = mapType },
        WorldMapFrame = {
            ShowQuests = function() error("Game quest panel is unavailable") end,
            SetMapID = function() error("Map changes must use the public API") end,
        },
        QuestMapFrame_ShowQuestDetails = function() error("Game quest details are unavailable") end,
        EventRegistry = { TriggerEvent = function(_, event, id)
            equal(event, "MapCanvas.PingQuestID")
            pingedQuest = id
        end },
        IsInInstance = function() return inInstance end,
        GetPlayerFacing = function()
            assert(not inInstance, "Do not read facing inside an instance")
            return facing
        end,
        MenuUtil = {
            CreateContextMenu = function(owner, populate)
                historyMenu = { entries = {} }
                function historyMenu:CreateTitle(title) self.title = title end
                function historyMenu:SetScrollMode() end
                function historyMenu:CreateDivider() end
                function historyMenu:CreateButton(label, select, id)
                    local child = { label = label, entries = {}, restore = select and function() select(id) end,
                        CreateButton = self.CreateButton, CreateTitle = self.CreateTitle, SetScrollMode = self.SetScrollMode }
                    self.entries[#self.entries + 1] = child
                    return child
                end
                populate(owner, historyMenu)
            end,
        },
        Menu = {
            ModifyMenu = function(tag, modifier)
                equal(tag, "MENU_QUEST_MAP_LOG_TITLE")
                questMenu = modifier
            end,
        },
        C_AddOns = {
            IsAddOnLoaded = function(name) return loaded[name] == true, loaded[name] == true end,
            DoesAddOnExist = function(name) return loaded[name] == true end,
            GetAddOnMetadata = function(name, key)
                equal(name, addonName)
                equal(key, "Version")
                return "0.1.54"
            end,
        },
        C_Timer = {
            After = function(_, callback) timers[#timers + 1] = callback end,
            NewTicker = function(seconds, callback)
                local ticker = { tick = callback }
                function ticker:Cancel() self.cancelled = true end
                if seconds == 1 then
                    distanceTicker = ticker
                elseif seconds == 5 then
                    questieTicker = ticker
                else
                    equal(seconds, 0.2)
                    directionTicker = ticker
                end
                return ticker
            end,
        },
        ForeverQuestNavigatorDB = { x = "invalid offset", hidden = true, includeElite = false, introSeen = true,
            sortByDistance = false, currentZoneOnly = true },
        MinimalSliderWithSteppersMixin = { Label = { Right = 3 } },
        Settings = {
            VarType = { Boolean = "boolean", Number = "number", String = "string" },
            RegisterVerticalLayoutCategory = function(name)
                equal(name, "Forever Quest Navigator")
                return category
            end,
            RegisterAddOnSetting = function(owner, variable, key, db, variableType, name, defaultValue)
                equal(owner, category)
                equal(variable, ({
                    language = "FOREVERQUESTNAVIGATOR_LANGUAGE",
                    detailMode = "FOREVERQUESTNAVIGATOR_DETAIL_MODE",
                    highContrast = "FOREVERQUESTNAVIGATOR_HIGH_CONTRAST",
                    showTravelPreparation = "FOREVERQUESTNAVIGATOR_TRAVEL_PREPARATION",
                    quietNavigation = "FOREVERQUESTNAVIGATOR_QUIET_NAVIGATION",
                    showRouteMarkers = "FOREVERQUESTNAVIGATOR_ROUTE_MARKERS",
                    showQuestRewards = "FOREVERQUESTNAVIGATOR_QUEST_REWARDS",
                    adaptiveLayout = "FOREVERQUESTNAVIGATOR_ADAPTIVE_LAYOUT",
                    showLevelHints = "FOREVERQUESTNAVIGATOR_LEVEL_HINTS",
                    showUpdateNotes = "FOREVERQUESTNAVIGATOR_UPDATE_NOTES",
                    showDirectionArrow = "FOREVERQUESTNAVIGATOR_SHOW_DIRECTION_ARROW",
                    showScreenArrow = "FOREVERQUESTNAVIGATOR_SHOW_SCREEN_ARROW",
                    showQuestXP = "FOREVERQUESTNAVIGATOR_SHOW_QUEST_XP",
                    useQuestieKillLocations = "FOREVERQUESTNAVIGATOR_QUESTIE_KILL_LOCATIONS",
                    showQuestieOffers = "FOREVERQUESTNAVIGATOR_QUESTIE_NEARBY_OFFERS",
                    questieOfferRadius = "FOREVERQUESTNAVIGATOR_QUESTIE_OFFER_RADIUS",
                    opacityPercent = "FOREVERQUESTNAVIGATOR_TRACKER_OPACITY",
                    allowTrackerResize = "FOREVERQUESTNAVIGATOR_ALLOW_TRACKER_RESIZE",
                    lockTrackerPosition = "FOREVERQUESTNAVIGATOR_LOCK_TRACKER_POSITION",
                    lockNavigationPosition = "FOREVERQUESTNAVIGATOR_LOCK_NAVIGATION_POSITION",
                    fontPercent = "FOREVERQUESTNAVIGATOR_FONT_PERCENT",
                    acceptedRows = "FOREVERQUESTNAVIGATOR_ACCEPTED_ROWS",
                    offerRows = "FOREVERQUESTNAVIGATOR_OFFER_ROWS",
                })[key])
                local expectedType = ({ opacityPercent = "number", questieOfferRadius = "number", language = "string",
                    fontPercent = "number", acceptedRows = "number", offerRows = "number", detailMode = "string" })[key]
                equal(variableType, expectedType or "boolean")
                equal(name, ({
                    language = "Language",
                    detailMode = "Tracker detail",
                    highContrast = "High contrast",
                    showTravelPreparation = "Show travel preparation hints",
                    quietNavigation = "Quiet navigation during combat",
                    showRouteMarkers = "Number the next stops on the map",
                    showQuestRewards = "Show gold and item rewards in tooltips",
                    adaptiveLayout = "Adapt details to narrow windows",
                    showLevelHints = "Show a hint when quests improve after levelling",
                    showUpdateNotes = "Show update notes",
                    opacityPercent = "Tracker opacity",
                    allowTrackerResize = "Allow changing window width",
                    lockTrackerPosition = "Lock tracker position",
                    lockNavigationPosition = "Lock navigation position",
                    fontPercent = "Text size",
                    acceptedRows = "Visible accepted quests",
                    offerRows = "Visible nearby offers",
                    showDirectionArrow = "Show direction arrow",
                    showScreenArrow = "Show navigation at top of screen",
                    showQuestXP = "Show quest XP in the tracker",
                    useQuestieKillLocations = "Use known enemy locations",
                    showQuestieOffers = "Show nearby quest offers",
                    questieOfferRadius = "Quest offer search radius",
                })[key])
                local expectedDefault = true
                if key == "opacityPercent" then expectedDefault = 80 end
                if key == "questieOfferRadius" then expectedDefault = 350 end
                if key == "language" then expectedDefault = "auto" end
                if key == "detailMode" then expectedDefault = "detailed" end
                if key == "highContrast" then expectedDefault = false end
                if key == "allowTrackerResize" then expectedDefault = false end
                if key == "lockTrackerPosition" or key == "lockNavigationPosition" then expectedDefault = false end
                if key == "fontPercent" then expectedDefault = 100 end
                if key == "acceptedRows" then expectedDefault = 2 end
                if key == "offerRows" then expectedDefault = 3 end
                equal(defaultValue, expectedDefault)
                local setting = { key = key }
                function setting:SetValue(value)
                    db[key] = value
                    if self.callback then self.callback(self, value) end
                end
                function setting:SetValueChangedCallback(callback) self.callback = callback end
                settingsByKey[key] = setting
                return setting
            end,
            CreateControlTextContainer = function()
                local options = {}
                return {
                    Add = function(_, value, label) options[#options + 1] = { value = value, label = label } end,
                    GetData = function() return options end,
                }
            end,
            CreateDropdown = function(owner, setting, getOptions)
                equal(owner, category)
                local options = getOptions()
                if setting == settingsByKey.detailMode then
                    equal(#options, 2)
                    equal(options[1].value, "detailed")
                    equal(options[2].value, "compact")
                    return
                end
                equal(setting, settingsByKey.language)
                equal(#options, 3)
                equal(options[1].value, "auto")
                equal(options[2].value, "deDE")
                equal(options[3].value, "enUS")
            end,
            CreateCheckbox = function(owner, registeredSetting)
                equal(owner, category)
                equal(registeredSetting, settingsByKey[registeredSetting.key])
            end,
            RegisterInitializer = function(owner, initializer)
                equal(owner, category)
                if initializer.callback then
                    if initializer.name == "Restore avoided objectives" then
                        settingsByKey.restoreObjectives = initializer
                    elseif initializer.name == "Reset appearance and positions" then
                        settingsByKey.resetAppearance = initializer
                    elseif initializer.name == "Open session overview" then
                        settingsByKey.openSession = initializer
                    elseif initializer.name == "Saved access points" then
                        settingsByKey.accessManager = initializer
                    elseif initializer.name == "Appearance preview" then
                        settingsByKey.preview = initializer
                    elseif initializer.name == "Open diagnostic report" then
                        settingsByKey.diagnostics = initializer
                    elseif initializer.name == "Quest notepad" then
                        settingsByKey.notepad = initializer
                    elseif initializer.name == "Quick introduction" then
                        settingsByKey.introduction = initializer
                    elseif initializer.name == "Zone overview" then
                        settingsByKey.zones = initializer
                    elseif initializer.name == "Export regression case" then
                        settingsByKey.fixture = initializer
                    elseif initializer.name == "Quest planning" then
                        settingsByKey.planning = initializer
                    elseif initializer.name == "Temporary feedback" then
                        settingsByKey.feedback = initializer
                    elseif initializer.name == "Appearance profiles" then
                        settingsByKey.profiles = initializer
                    elseif initializer.name == "Changes and undo" then
                        settingsByKey.history = initializer
                    elseif initializer.name == "Quests after your level-up" then
                        settingsByKey.levelChanges = initializer
                    else
                        settingsByKey.resetPositions = initializer
                    end
                end
            end,
            CreateSliderOptions = function(minimum, maximum, step)
                if minimum == 80 then
                    equal(maximum, 140)
                    equal(step, 10)
                    return { SetLabelFormatter = noOp }
                end
                if minimum == 2 then
                    equal(maximum, 5)
                    equal(step, 1)
                    return { SetLabelFormatter = noOp }
                end
                if minimum == 50 then
                    equal(maximum, 1000)
                    equal(step, 50)
                    return { SetLabelFormatter = function(_, label, formatValue)
                        equal(label, 3)
                        equal(formatValue(200), "200 yd")
                    end }
                end
                equal(minimum, 0)
                equal(maximum, 100)
                equal(step, 5)
                return { SetLabelFormatter = function(_, label, formatValue)
                    equal(label, 3)
                    equal(formatValue(65), "65%")
                end }
            end,
            CreateSlider = function(owner, registeredSetting)
                equal(owner, category)
                equal(registeredSetting, settingsByKey[registeredSetting.key])
            end,
            RegisterAddOnCategory = function(owner) equal(owner, category) end,
            OpenToCategory = function(id) openedCategory = id end,
        },
        SlashCmdList = {},
        print = function(message) messages[#messages + 1] = message end,
    }, { __index = getfenv() })

    loadAddon(env, true)
    local eventFrame = frames[1]
    local function fire(event, ...)
        assert(eventFrame.events[event], "Unregistered event " .. event)
        eventFrame.scripts.OnEvent(eventFrame, event, ...)
    end
    local function flush()
        equal(#timers, 1)
        table.remove(timers, 1)()
    end

    local function QuestLogMenuEntry(questID)
        local label, action
        questMenu({ questID = questID }, {
            CreateButton = function(_, text, callback) label, action = text, callback end,
        })
        return label, action
    end

    local function PinQuest(questID)
        local label, action = QuestLogMenuEntry(questID)
        equal(label, "Set as active in FQN")
        action()
    end

    fire("ADDON_LOADED", "UnrelatedAddon")
    equal(#frames, 1)
    env.CreateSettingsButtonInitializer = function(name, buttonText, callback, help, searchable)
        assert(name == "Reset window positions" or name == "Restore avoided objectives" or name == "Reset appearance and positions"
            or name == "Open session overview" or name == "Saved access points" or name == "Appearance preview" or name == "Open diagnostic report"
            or name == "Quest notepad" or name == "Quick introduction" or name == "Zone overview" or name == "Export regression case" or name == "Quest planning"
            or name == "Temporary feedback" or name == "Appearance profiles" or name == "Changes and undo" or name == "Quests after your level-up")
        equal(buttonText, name)
        equal(searchable, true)
        return { name = name, callback = callback }
    end
    local sections = {}
    env.CreateSettingsListSectionHeaderInitializer = function(name)
        sections[#sections + 1] = name
        return { section = name }
    end
    local tooltip = { AddLine = noOp, Show = noOp }
    function tooltip:SetOwner(owner) self.owner = owner end
    function tooltip:IsOwned(owner) return self.owner == owner end
    function tooltip:SetText(text) self.text, self.lines = text, {} end
    function tooltip:AddLine(text) self.lines[#self.lines + 1] = text end
    function tooltip:Hide() self.owner, self.text = nil, nil end
    env.GameTooltip = tooltip
    fire("ADDON_LOADED", addonName)
    env.Minimap = createFrame()
    function env.Minimap:GetSize() return 198, 198 end
    function env.Minimap:GetEffectiveScale() return 0.5 end
    env.GetCursorPosition = function() return 250, 250 end
    local minimapButtonIndex = #frames + 1
    fire("PLAYER_ENTERING_WORLD")
    local minimapButton = frames[minimapButtonIndex]
    local frameCount = #frames
    fire("PLAYER_ENTERING_WORLD")
    equal(#frames, frameCount)
    fire("QUEST_LOG_UPDATE")
    flush()
    local tracker, header, openSettings, close = frames[2], frames[3], frames[4], frames[5]
    local history, skip = frames[7], frames[9]
    local content = frames[6]
    local title, objective = content.labels[1], content.labels[2]
    equal(reads, 1)
    equal(header.labels[2].text, "v0.1.54")
    equal(table.concat(sections, ", "), "General, Recommendations, Navigation, Appearance, Diagnostics")
    equal(tracker.backdropAlpha, 0.8)
    equal(env.ForeverQuestNavigatorDB.questieOfferRadius, 350)
    for _, key in ipairs({ "useQuestieKillLocations", "showQuestieOffers", "showDirectionArrow", "showQuestXP" }) do
        equal(env.ForeverQuestNavigatorDB[key], true)
    end
    equal(tracker:IsShown(), false)
    equal(env.ForeverQuestNavigatorDB.x, 0)
    equal(env.ForeverQuestNavigatorDB.includeElite, nil)
    equal(settingsByKey.includeElite, nil)
    equal(env.ForeverQuestNavigatorDB.currentZoneOnly, nil)
    equal(env.ForeverQuestNavigatorDB.sortByDistance, nil)
    equal(title.text, "No matching outdoor quests on the available maps.")
    equal(skip:IsShown(), false)
    equal(history.enabled, false)
    equal(history:IsShown(), false)

    local slash = env.SlashCmdList.FOREVERQUESTNAVIGATOR
    equal(minimapButton.point[2], env.Minimap)
    equal(minimapButton.labels[1].text, "FQN")
    minimapButton:Click()
    equal(tracker:IsShown(), true)
    equal(env.ForeverQuestNavigatorDB.hidden, false)
    local resizeGrip
    for _, frame in ipairs(frames) do
        if frame.parent == content and frame.scripts.OnDragStart and frame.scripts.OnHide then
            resizeGrip = frame
        end
    end
    assert(resizeGrip)
    equal(resizeGrip:IsShown(), false)
    equal(tracker:GetWidth(), 352)
    local initialHeight = tracker:GetHeight()
    settingsByKey.allowTrackerResize:SetValue(true)
    equal(resizeGrip:IsShown(), true)
    resizeGrip.scripts.OnDragStart(resizeGrip)
    env.GetCursorPosition = function() return 50, 250 end
    resizeGrip.scripts.OnUpdate()
    equal(tracker:GetWidth(), 330)
    env.GetCursorPosition = function() return 500, 250 end
    resizeGrip.scripts.OnUpdate()
    equal(tracker:GetWidth(), 640)
    env.GetCursorPosition = function() return 274, 250 end
    resizeGrip.scripts.OnUpdate()
    equal(tracker:GetWidth(), 400)
    equal(env.ForeverQuestNavigatorDB.trackerWidth, 400)
    settingsByKey.allowTrackerResize:SetValue(false)
    equal(resizeGrip:IsShown(), false)
    equal(resizeGrip.scripts.OnUpdate, nil)
    equal(tracker:GetHeight(), initialHeight)
    env.GetCursorPosition = function() return 250, 250 end
    minimapButton:Click()
    equal(tracker:IsShown(), false)
    equal(env.ForeverQuestNavigatorDB.hidden, true)
    equal(env.ForeverQuestNavigatorDB.displayMode, "arrow")
    minimapButton:Click()
    equal(env.ForeverQuestNavigatorDB.displayMode, "off")
    equal(minimapButton:IsShown(), true)
    minimapButton.scripts.OnMouseDown(minimapButton, "LeftButton")
    minimapButton.scripts.OnDragStart(minimapButton)
    minimapButton.scripts.OnUpdate(minimapButton)
    minimapButton.scripts.OnDragStop(minimapButton)
    near(minimapButton.point[4], 0)
    near(minimapButton.point[5], 104)
    near(env.ForeverQuestNavigatorDB.minimapAngle, math.pi / 2)
    equal(minimapButton.scripts.OnUpdate, nil)
    minimapButton:Click()
    equal(tracker:IsShown(), false)
    minimapButton:Click("RightButton")
    local quickSettings
    for _, frame in ipairs(frames) do if frame.heading and frame.heading.text == "FQN settings" then quickSettings = frame end end
    assert(quickSettings and quickSettings:IsShown())
    quickSettings.native:Click()
    equal(openedCategory, category:GetID())
    equal(tracker:IsShown(), false)
    minimapButton.scripts.OnMouseDown(minimapButton, "LeftButton")
    minimapButton:Click()
    equal(tracker:IsShown(), true)
    openSettings:Click()
    equal(openedCategory, category:GetID())
    settingsByKey.opacityPercent:SetValue(65)
    equal(tracker.backdropAlpha, 0.65)
    equal(tracker.borderAlpha, 0.65)
    equal(tracker.alpha, nil)
    settingsByKey.opacityPercent:SetValue(100)
    equal(tracker.backdropAlpha, 1)
    settingsByKey.opacityPercent:SetValue(0)
    equal(tracker.backdropAlpha, 0)
    equal(tracker.borderAlpha, 0)
    header.scripts.OnDragStop()
    equal(env.ForeverQuestNavigatorDB.x, 100)
    equal(env.ForeverQuestNavigatorDB.y, 100 + tracker:GetHeight() / 2)
    close:Click()
    equal(env.ForeverQuestNavigatorDB.hidden, true)

    slash("status")
    equal(messages[1], "FQN | Questie: Not installed")
    loaded.Questie = true
    fire("ADDON_LOADED", "Questie")
    slash(" Status ")
    equal(messages[2], "FQN | Questie: Loaded")
    slash("settings")
    equal(openedCategory, category:GetID())
    equal(env.ForeverQuestNavigatorDB.language, "auto")
    settingsByKey.language:SetValue("enUS")
    equal(env.ForeverQuestNavigatorDB.language, "enUS")
    equal(messages[3], "FQN | Language saved. Type /reload to apply the change.")

    quests[1] = { questID = 1, level = 9, title = "Supplies" }
    quests[2] = { questID = 2, level = 8, title = "Wolves" }
    objectives[2] = { { text = "Wolves slain: 0/8" } }
    fire("QUEST_ACCEPTED", 2)
    fire("QUEST_LOG_UPDATE")
    flush()
    equal(reads, 2)
    equal(title.text, "[8] Wolves")
    local function FindGoal(owner, index)
        for _, candidate in ipairs(frames) do
            if candidate.parent == owner and candidate.goal and candidate.goal.index == index then return candidate end
        end
        error("Goal missing: " .. index)
    end
    equal(FindGoal(content, 1).label.text, "Wolves slain: 0/8")

    objectives[2][1].text = "Wolves slain: 3/8"
    fire("QUEST_LOG_CRITERIA_UPDATE", 2)
    flush()
    equal(FindGoal(content, 1).label.text, "Wolves slain: 3/8")

    complete[2] = true
    fire("QUEST_WATCH_UPDATE", 2)
    flush()
    equal(objective.text, "Ready to turn in")

    quests[2] = nil
    fire("QUEST_TURNED_IN", 2)
    fire("QUEST_REMOVED", 2)
    flush()
    equal(title.text, "[9] Supplies")
    equal(objective.text, "See the quest log for details.")

    quests[2] = { questID = 3, level = 7, title = "Elite wolves" }
    elite[3] = true
    fire("QUEST_ACCEPTED", 3)
    flush()
    equal(title.text, "[7] Elite wolves |cffffc447+|r")
    equal(skip:IsShown(), true)
    equal(history.enabled, false)

    skip:Click()
    flush()
    equal(title.text, "[9] Supplies")
    equal(history.enabled, true)
    fire("QUEST_LOG_UPDATE")
    flush()
    equal(title.text, "[9] Supplies")

    skip:Click()
    flush()
    equal(title.text, "No matching outdoor quests on the available maps.")
    equal(env.ForeverQuestNavigatorCharacterDB.skippedQuests[1].quest.title, "Supplies")
    equal(skip:IsShown(), false)
    equal(history.enabled, true)
    history:Click()
    equal(historyMenu.entries[1].label, "Restore all")
    historyMenu.entries[1].restore()
    flush()
    equal(title.text, "[7] Elite wolves |cffffc447+|r")
    equal(history.enabled, false)

    skip:Click()
    flush()
    quests[2] = nil
    fire("QUEST_REMOVED", 3)
    flush()
    equal(history.enabled, false)
    quests[2] = { questID = 3, level = 7, title = "Elite wolves" }
    fire("QUEST_ACCEPTED", 3)
    flush()
    equal(title.text, "[7] Elite wolves |cffffc447+|r")

    pinsByMap = { [10] = { { questID = 1 } }, [20] = { { questID = 3 } } }
    fire("QUEST_POI_UPDATE")
    flush()
    equal(title.text, "[9] Supplies")
    currentMapID = 20
    fire("ZONE_CHANGED_NEW_AREA")
    flush()
    equal(title.text, "[7] Elite wolves |cffffc447+|r")
    currentMapID = 30
    fire("PLAYER_MAP_CHANGED", 20, 30)
    flush()
    equal(title.text, "No matching outdoor quests on the available maps.")
    currentMapID = nil
    fire("PLAYER_MAP_CHANGED", 30, 0)
    flush()
    equal(title.text, "Outdoor quest map unavailable.")

    env.C_QuestLog = nil
    fire("QUEST_LOG_UPDATE")
    flush()
    equal(title.text, "Quest log API unavailable.")
    equal(objective.text, "")

    env.C_QuestLog = api
    currentMapID = 10
    fire("QUEST_LOG_UPDATE")
    flush()
    skip:Click()
    flush()
    equal(title.text, "No matching outdoor quests on the available maps.")

    settingsByKey.showQuestieOffers:SetValue(false)
    flush()
    local function FindTrackerButton(parent, text)
        for _, frame in ipairs(frames) do
            if frame.parent == parent and frame.text == text then return frame end
        end
        error("Tracker button missing: " .. text)
    end
    local collapse = FindTrackerButton(tracker, "−")
    if not tracker:IsShown() then env.SlashCmdList.FOREVERQUESTNAVIGATOR("") end
    local expandedHeight = tracker:GetHeight()
    equal(collapse.text, "−")
    collapse:Click()
    equal(collapse.text, "+")
    equal(tracker:IsShown(), true)
    equal(content:IsShown(), true)
    equal(history:IsShown(), false)
    equal(tracker.point[1], "TOP")
    local collapsedHeight = tracker:GetHeight()
    assert(collapsedHeight < expandedHeight)
    equal(env.ForeverQuestNavigatorDB.collapsed, true)
    env.SlashCmdList.FOREVERQUESTNAVIGATOR("")

    local firstNewFrame = #frames + 1
    env.GetLocale = function() return "deDE" end
    local reloadedAddon = loadAddon(env, true)
    eventFrame = frames[firstNewFrame]
    fire("ADDON_LOADED", addonName)
    local reloadedButtonIndex = #frames + 1
    fire("PLAYER_ENTERING_WORLD")
    near(frames[reloadedButtonIndex].point[4], 0)
    near(frames[reloadedButtonIndex].point[5], 104)
    flush()
    equal(env.ForeverQuestNavigatorDB.includeElite, nil)
    equal(frames[firstNewFrame + 5].labels[1].text, "No matching outdoor quests on the available maps.")
    equal(frames[firstNewFrame + 6].enabled, true)

    local updatedTracker = frames[firstNewFrame + 1]
    local updatedContent = frames[firstNewFrame + 5]
    local reloadedCollapse = FindTrackerButton(updatedTracker, "+")
    equal(reloadedCollapse.text, "+")
    equal(updatedContent:IsShown(), true)
    assert(updatedTracker:GetHeight() <= collapsedHeight)
    equal(updatedTracker:GetWidth(), 400)
    equal(env.ForeverQuestNavigatorDB.allowTrackerResize, false)
    equal(updatedTracker.backdropAlpha, 0)
    equal(env.ForeverQuestNavigatorDB.showQuestieOffers, false)
    local history = frames[firstNewFrame + 6]
    updatedTracker:Show()
    reloadedCollapse:Click()
    equal(reloadedCollapse.text, "−")
    equal(updatedContent:IsShown(), true)
    equal(updatedTracker.point[1], "TOP")
    assert(updatedTracker:GetHeight() <= expandedHeight)
    equal(env.ForeverQuestNavigatorDB.collapsed, false)
    updatedTracker:Hide()
    env.SlashCmdList.FOREVERQUESTNAVIGATOR("")
    history:Click()
    equal(historyMenu.entries[2].label, "[9] Supplies")
    historyMenu.entries[2].restore()
    flush()
    equal(updatedContent.labels[1].text, "[9] Supplies")
    equal(env.ForeverQuestNavigatorCharacterDB.skippedQuests[1], nil)
    env.SlashCmdList.FOREVERQUESTNAVIGATOR("")
    local auto = frames[firstNewFrame + 7]
    local activeCheckbox = frames[firstNewFrame + 8]
    local rowOne = frames[firstNewFrame + 9]
    local rowTwo = frames[firstNewFrame + 11]
    local arrow = frames[firstNewFrame + 13]
    local activeDistance = updatedContent.labels[3]
    title, objective = updatedContent.labels[1], updatedContent.labels[2]
    currentMapID = 10
    quests[3] = { questID = 4, level = 5, title = "Local patrol" }
    quests[4] = { questID = 5, level = 11, title = "Local courier" }
    quests[5] = { questID = 6, level = 12, title = "Local harvest" }
    pinsByMap[10] = { { questID = 1 }, { questID = 4, x = 0.5, y = 0.5 },
        { questID = 5, x = 0.55, y = 0.75 }, { questID = 6 } }
    fire("QUEST_LOG_UPDATE")
    flush()
    equal(title.text, "[5] Local patrol")
    equal(rowOne.label.text, "[9] Supplies")
    equal(rowTwo.label.text, "[11] Local courier")
    equal(auto.enabled, false)
    equal(auto:IsShown(), false)
    equal(distanceTicker, nil)
    env.SlashCmdList.FOREVERQUESTNAVIGATOR("")
    equal(activeDistance.text, "~250 yd")
    equal(rowOne.distance.text, "~325 yd")
    equal(rowTwo.distance.text, "—")
    local readsBeforeTick = reads
    local navigation
    for _, frame in ipairs(frames) do
        if frame.parent == env.UIParent and frame.point and frame.point[1] == "TOP"
            and frame.point[2] == env.UIParent and frame.point[3] == "TOP" then
            navigation = frame
        end
    end
    assert(navigation)
    equal(env.ForeverQuestNavigatorDB.showScreenArrow, true)
    equal(navigation:IsShown(), true)
    equal(navigation.title.text, "[5] Local patrol")
    navigation.title.truncated = true
    navigation.scripts.OnEnter(navigation)
    equal(tooltip.text, "[5] Local patrol")
    navigation.scripts.OnLeave(navigation)
    navigation.title.truncated = false
    rowOne.scripts.OnEnter(rowOne)
    equal(tooltip.text, rowOne.label.text)
    assert(tooltip.lines[1]:find("Known target", 1, true))
    rowOne.label.truncated = true
    rowOne.scripts.OnEnter(rowOne)
    equal(tooltip.text, rowOne.label.text)
    rowOne.scripts.OnLeave(rowOne)
    rowOne.label.truncated = false
    equal(navigation.distance.text, "~250 yd")
    near(navigation.arrow.lines[1].tipX, 12.8)
    equal(arrow:IsShown(), false)
    equal(navigation.textures[1].colorAlpha, 0)
    settingsByKey.opacityPercent:SetValue(65)
    equal(navigation.textures[1].colorAlpha, 0.65)
    equal(navigation.alpha, nil)
    navigation.scripts.OnDragStart(navigation)
    function navigation:GetCenter() return 480, 360 end
    navigation.scripts.OnDragStop(navigation)
    equal(navigation.point[1], "CENTER")
    equal(navigation.point[4], 80)
    equal(navigation.point[5], 60)
    equal(env.ForeverQuestNavigatorDB.screenArrowX, 80)
    equal(env.ForeverQuestNavigatorDB.screenArrowY, 60)
    local moveCount = navigation.startedMoving
    settingsByKey.lockNavigationPosition:SetValue(true)
    navigation.scripts.OnDragStart(navigation)
    equal(navigation.startedMoving, moveCount)
    settingsByKey.lockNavigationPosition:SetValue(false)
    settingsByKey.lockTrackerPosition:SetValue(true)
    local reloadedHeader = frames[firstNewFrame + 2]
    local trackerMoves = updatedTracker.startedMoving
    reloadedHeader.scripts.OnDragStart()
    equal(updatedTracker.startedMoving, trackerMoves)
    settingsByKey.lockTrackerPosition:SetValue(false)
    settingsByKey.resetPositions.callback()
    equal(env.ForeverQuestNavigatorDB.x, 0)
    equal(env.ForeverQuestNavigatorDB.screenArrowX, nil)
    equal(navigation.point[1], "TOP")
    equal(navigation.point[5], -80)

    settingsByKey.showScreenArrow:SetValue(false)
    equal(navigation:IsShown(), false)
    equal(arrow:IsShown(), true)
    near(arrow.lines[1].tipX, 8)
    near(arrow.lines[1].tipY, 0)
    facing = 3 * math.pi / 2
    directionTicker.tick()
    near(arrow.lines[1].tipX, 0)
    near(arrow.lines[1].tipY, 8)
    settingsByKey.showScreenArrow:SetValue(true)
    equal(arrow:IsShown(), false)
    near(navigation.arrow.lines[1].tipY, 12.8)

    settingsByKey.showDirectionArrow:SetValue(false)
    equal(arrow:IsShown(), false)
    equal(navigation:IsShown(), false)
    equal(directionTicker.cancelled, true)
    equal(distanceTicker.cancelled, nil)
    settingsByKey.showDirectionArrow:SetValue(true)
    equal(arrow:IsShown(), false)
    equal(navigation:IsShown(), true)

    inInstance = true
    directionTicker.tick()
    equal(arrow:IsShown(), false)
    distanceTicker.tick()
    equal(directionTicker.cancelled, true)
    inInstance = false
    playerX = 0.375
    distanceTicker.tick()
    equal(activeDistance.text, "~125 yd")
    equal(navigation.distance.text, "~125 yd")
    equal(navigation:IsShown(), true)
    equal(arrow:IsShown(), false)
    equal(reads, readsBeforeTick)
    local reloadedMinimap = frames[reloadedButtonIndex]
    settingsByKey.showScreenArrow:SetValue(false)
    reloadedMinimap:Click()
    equal(updatedTracker:IsShown(), false)
    equal(env.ForeverQuestNavigatorDB.displayMode, "arrow")
    equal(navigation:IsShown(), true)
    equal(distanceTicker.cancelled, nil)
    equal(directionTicker.cancelled, nil)
    reloadedMinimap:Click()
    equal(env.ForeverQuestNavigatorDB.displayMode, "off")
    equal(navigation:IsShown(), false)
    reloadedMinimap:Click()
    equal(updatedTracker:IsShown(), true)
    env.SlashCmdList.FOREVERQUESTNAVIGATOR("")
    equal(navigation:IsShown(), false)
    equal(distanceTicker.cancelled, true)
    equal(directionTicker.cancelled, true)

    settingsByKey.showScreenArrow:SetValue(false)
    env.SlashCmdList.FOREVERQUESTNAVIGATOR("")
    rowOne:Click()
    equal(openedMap, 10)
    equal(selectedQuest, 5)
    equal(title.text, "[5] Local patrol")
    equal(auto:IsShown(), false)
    PinQuest(5)
    flush()
    equal(title.text, "[11] Local courier")
    equal(rowOne.label.text, "[5] Local patrol")
    equal(auto.enabled, true)
    equal(auto:IsShown(), true)
    objectives[5] = { { text = "Letters delivered: 1/2" } }
    fire("QUEST_LOG_UPDATE")
    flush()
    equal(title.text, "[11] Local courier")
    equal(FindGoal(updatedContent, 1).label.text, "Letters delivered: 1/2")

    rowOne.checkbox:Click()
    flush()
    equal(title.text, "[11] Local courier")
    equal(rowOne.label.text, "[9] Supplies")
    equal(rowTwo.label.text, "[12] Local harvest")
    equal(history.text, "Skipped (1)")
    activeCheckbox:Click()
    flush()
    equal(title.text, "[9] Supplies")
    equal(rowOne.label.text, "[12] Local harvest")
    equal(rowTwo:IsShown(), false)
    equal(auto.enabled, false)

    history:Click()
    equal(historyMenu.title, "Skipped quests")
    equal(historyMenu.entries[1].label, "Restore all")
    equal(historyMenu.entries[2].label, "[11] Local courier")
    equal(historyMenu.entries[3].label, "[5] Local patrol")
    historyMenu.entries[3].restore()
    flush()
    equal(title.text, "[5] Local patrol")
    equal(history.text, "Skipped (1)")

    PinQuest(1)
    flush()
    equal(title.text, "[9] Supplies")
    auto:Click()
    flush()
    equal(title.text, "[5] Local patrol")
    PinQuest(1)
    flush()
    currentMapID = 20
    fire("PLAYER_MAP_CHANGED", 10, 20)
    flush()
    equal(title.text, "[9] Supplies")
    equal(rowOne.label.text, "[7] Elite wolves |cffffc447+|r")
    local clearLabel, clearPin = QuestLogMenuEntry(1)
    equal(clearLabel, "Resume FQN auto select")
    clearPin()
    flush()
    equal(title.text, "[7] Elite wolves |cffffc447+|r")
    currentMapID = 10
    fire("PLAYER_MAP_CHANGED", 20, 10)
    flush()
    equal(title.text, "[5] Local patrol")

    playerX = 0.35
    pinsByMap[10][4] = { questID = 6, x = 0.25, y = 0.5 }
    fire("QUEST_POI_UPDATE")
    flush()
    equal(title.text, "[12] Local harvest")
    equal(activeDistance.text, "~100 yd")
    equal(rowOne.label.text, "[5] Local patrol")
    equal(rowTwo.label.text, "[9] Supplies")

    readsBeforeTick = reads
    playerX = 0.38
    distanceTicker.tick()
    equal(title.text, "[12] Local harvest")
    playerX = 0.42
    distanceTicker.tick()
    equal(title.text, "[5] Local patrol")
    equal(activeDistance.text, "~80 yd")
    equal(reads, readsBeforeTick)

    PinQuest(6)
    flush()
    equal(title.text, "[12] Local harvest")
    settingsByKey.showScreenArrow:SetValue(true)
    pinsByMap[10][4] = { questID = 6 }
    fire("QUEST_POI_UPDATE")
    flush()
    equal(navigation:IsShown(), true)
    equal(navigation.status.text, "Target position unknown")
    equal(navigation.arrow:IsShown(), false)
    pinsByMap[10][4] = { questID = 6, x = 0.25, y = 0.5 }
    playerX = 0.25
    fire("QUEST_POI_UPDATE")
    flush()
    equal(navigation.status.text, "Destination reached; check the quest log for the next action")
    equal(navigation.arrow:IsShown(), false)
    settingsByKey.showScreenArrow:SetValue(false)
    playerX = 0.48
    distanceTicker.tick()
    equal(title.text, "[12] Local harvest")
    auto:Click()
    flush()
    equal(title.text, "[5] Local patrol")

    -- Questie provides a local location for an accepted quest with no native pin.
    local ready
    equal(updatedTracker:IsVisible(), true)
    env._G = env
    env.UnitLevel = function() return 10 end
    env.Questie = { ICON_TYPE_SLAY = 1, API = { RegisterOnReady = function(callback) ready = callback end } }
    api.IsOnQuest = function(id) return id == 7 end
    api.IsQuestFlaggedCompleted = function(id) return id == 91 end
    quests = { { questID = 7, level = 9, title = "Boars" } }
    pinsByMap[10] = {}
    objectives[7] = {
        { finished = true, type = "monster", text = "Wolves slain: 8/8" },
        { type = "monster", text = "Boars slain: 0/8" },
    }
    playerX = 0.5
    facing = 0
    local spawn = { Icon = 1, Spawns = {
        [100] = { { 60, 50 }, { 55, 50 }, { 51, 50, 3 }, { -1, -1 } },
        [200] = { { 50.1, 50 } },
    } }
    local kill = { Type = "monster", Id = 3 }
    local cachedKill = { Type = "monster", Id = 3, spawnList = { [3] = spawn } }
    local activeQuest = { ObjectiveData = { [2] = kill }, Objectives = { [2] = cachedKill } }
    local framesByID = {}
    local modules = {
        ActiveQuests = { Get = function(id) return id == 7 and { quest = activeQuest } end },
        ZoneDB = { GetUiMapIdByAreaId = function(_, id) return id / 10 end },
        Phasing = { IsSpawnVisible = function(phase) return phase ~= 3 end },
        QuestieMap = { questIdFrames = framesByID },
    }
    env.QuestieLoader = { ImportModule = function(_, name) return assert(modules[name]) end }
    local function AddOffer(id, name, x, requiredLevel, starterType, questLevel)
        local frameName = "QuestieTestFrame" .. id
        framesByID[id] = { [frameName] = frameName }
        env[frameName] = { UiMapID = 10, x = x, y = 50, miniMapIcon = false, data = {
            Type = "available", Id = id, StarterType = starterType,
            QuestData = { name = name, requiredLevel = requiredLevel, level = questLevel },
        } }
    end
    AddOffer(7, "Already accepted", 50, 1)
    AddOffer(91, "Completed", 51, 1)
    AddOffer(92, "Level locked", 51, 11)
    AddOffer(93, "Item start", 52, 1, "itemFromMonster")
    AddOffer(94, "Near quest", 55, 1, nil, 8)
    AddOffer(95, "Distant quest", 90, 1)
    AddOffer(96, "Other nearby quest", 56, 1, nil, 10)

    fire("ADDON_LOADED", "Questie")
    env.Questie.API.isReady = true
    ready()
    flush()
    equal(title.text, "[9] Boars")
    local function Goal(index)
        return FindGoal(updatedContent, index)
    end
    equal(Goal(1).label.text, "Wolves slain: 8/8")
    equal(Goal(1).goal.selectable, false)
    equal(Goal(1):IsShown(), false)
    local finished = FindTrackerButton(updatedContent, "+  1 completed objective")
    finished:Click()
    equal(Goal(1):IsShown(), true)
    equal(finished.text, "−  1 completed objective")
    Goal(1).label.truncated = true
    Goal(1).scripts.OnEnter(Goal(1))
    equal(tooltip.text, "Wolves slain: 8/8")
    finished:Click()
    equal(Goal(1):IsShown(), false)
    equal(tooltip.text, nil)
    equal(Goal(2).label.text, "Boars slain: 0/8")
    equal(Goal(2).indicator.text, ">")
    equal(activeDistance.point[2], Goal(2))
    equal(navigation.goal.text, "Boars slain: 0/8")
    equal(activeDistance.text, "~50 yd")
    local areaFrame
    for _, frame in ipairs(frames) do
        if frame.parent == updatedContent and frame.SetData then areaFrame = frame end
    end
    assert(areaFrame)
    local areaHeader
    for _, frame in ipairs(frames) do
        if frame.parent == areaFrame and frame.text and frame.text:find("Here:", 1, true) then areaHeader = frame end
    end
    assert(areaHeader)
    equal(areaHeader.text, "+ Here: 1 objective · 0 turn-ins")
    equal(arrow:IsShown(), true)
    near(arrow.lines[1].tipX, 8)
    objectives[7][3] = { type = "item", text = "Supplies collected: 0/3" }
    activeQuest.ObjectiveData[3] = { Type = "item", Id = 8 }
    activeQuest.Objectives[3] = { Type = "item", Id = 8,
        spawnList = { [51] = { Spawns = { [100] = { { 35, 50 } } } } } }
    fire("QUEST_LOG_CRITERIA_UPDATE", 7)
    flush()
    equal(activeDistance.text, "~50 yd")
    equal(areaHeader.text, "+ Here: 2 objectives · 0 turn-ins")
    areaHeader:Click()
    equal(env.ForeverQuestNavigatorDB.areaOverviewExpanded, true)
    local groupRow
    for _, frame in ipairs(frames) do
        if frame.parent == areaFrame and frame.group then groupRow = frame break end
    end
    if groupRow then groupRow:Click() end
    local areaRow
    for _, frame in ipairs(frames) do
        if frame.parent == areaFrame and frame.entry then areaRow = frame end
    end
    equal(areaRow.entry.quest.id, 7)
    equal(areaRow.entry.objectives, 2)
    areaRow:Click()
    equal(selectedQuest, 7)
    equal(title.text, "[9] Boars")
    areaHeader:Click()
    Goal(2):Click("RightButton")
    equal(activeDistance.text, "~150 yd")
    equal(Goal(2).goal.avoided, true)
    equal(Goal(3).indicator.text, ">")
    equal(navigation.notice.text, "New navigation target")
    equal(areaHeader.text, "+ Here: 1 objective · 0 turn-ins")
    Goal(3):Click("RightButton")
    equal(activeDistance.text, "—")
    equal(navigation.status.text, "All known objectives are temporarily avoided")
    equal(areaHeader.text, "+ Here: 0 objectives · 0 turn-ins")
    settingsByKey.restoreObjectives.callback()
    equal(activeDistance.text, "~50 yd")
    equal(Goal(2).goal.avoided, false)
    equal(areaHeader.text, "+ Here: 2 objectives · 0 turn-ins")
    navigation.scripts.OnUpdate(navigation, 5)
    equal(navigation.notice:IsShown(), false)
    Goal(3):Click()
    equal(activeDistance.text, "~150 yd")
    equal(navigation.goal.text, "Supplies collected: 0/3")
    equal(Goal(3).indicator.text, "•")
    equal(activeDistance.point[2], Goal(3))
    local resetObjective = FindTrackerButton(updatedContent, "Back to automatic")
    equal(resetObjective:IsShown(), true)
    resetObjective:Click()
    equal(resetObjective:IsShown(), false)
    equal(activeDistance.text, "~50 yd")
    playerX = 0.44
    distanceTicker.tick()
    equal(Goal(2).indicator.text, ">")
    equal(activeDistance.text, "~110 yd")
    playerX = 0.37
    distanceTicker.tick()
    equal(activeDistance.text, "~20 yd")
    near(arrow.lines[1].tipX, -8)
    playerX = 0.5
    distanceTicker.tick()
    equal(activeDistance.text, "~50 yd")
    near(arrow.lines[1].tipX, 8)
    Goal(2):Click()
    equal(Goal(2).indicator.text, "•")
    objectives[7][2].finished = true
    fire("QUEST_LOG_CRITERIA_UPDATE", 7)
    flush()
    equal(Goal(2).goal.selectable, false)
    equal(Goal(2):IsShown(), false)
    equal(finished.text, "+  2 completed objectives")
    equal(Goal(3).indicator.text, ">")
    equal(resetObjective:IsShown(), false)
    equal(activeDistance.text, "~150 yd")
    near(arrow.lines[1].tipX, -8)

    quests[2] = { questID = 8, level = 10, title = "Companion quest" }
    api.IsOnQuest = function(id) return id == 7 or id == 8 end
    pinsByMap[10] = { { questID = 8, x = 0.2, y = 0.5 } }
    fire("QUEST_LOG_UPDATE")
    flush()
    local nearby = updatedTracker.nearbyStopsButton
    equal(nearby.text, "1 other target nearby")
    nearby:Click()
    equal(historyMenu.entries[1].label, "[10] Companion quest · ~150 yd")
    local offersHeading = updatedContent.labels[5]
    updatedTracker:RenderNearbyOffers({ { title = "New quest", yards = 70 } })
    rowOne.routeButton:Click()
    local headingTop = -offersHeading.point[2].point[3]
    local rowBottom = -rowOne.point[3] + rowOne:GetHeight()
    assert(headingTop - rowBottom >= 8)
    updatedTracker:RenderNearbyOffers()
    rowOne.checkbox:Click()
    flush()
    equal(nearby:IsShown(), false)
    quests[2], objectives[7][3], objectives[7][2].finished = nil, nil, nil
    api.IsOnQuest = function(id) return id == 7 end
    pinsByMap[10] = {}
    fire("QUEST_REMOVED", 8)
    settingsByKey.useQuestieKillLocations:SetValue(false)
    flush()
    equal(title.text, "No matching outdoor quests on the available maps.")
    settingsByKey.useQuestieKillLocations:SetValue(true)
    flush()
    equal(title.text, "[9] Boars")
    local offer = updatedContent.labels[5]
    equal(offer:IsShown(), false)
    settingsByKey.showQuestieOffers:SetValue(true)
    flush()
    equal(offer.text, "−  Available nearby (2)")
    equal(offer:IsShown(), true)
    local firstOffer = frames[firstNewFrame + 16]
    local secondOffer = frames[firstNewFrame + 18]
    equal(firstOffer.label.text, "[10] Other nearby quest")
    equal(secondOffer.label.text, "[8] Near quest")
    equal(firstOffer.distance.text, "Accept ~60 yd")
    equal(firstOffer.checkbox, nil)
    equal(firstOffer.recommendation:IsShown(), false)
    local offersToggle = offer.point[2]
    offersToggle:Click()
    equal(offer.text, "+  Available nearby (2)")
    equal(firstOffer:IsShown(), false)
    equal(env.ForeverQuestNavigatorDB.offersCollapsed, true)
    offersToggle:Click()
    equal(firstOffer:IsShown(), true)
    near(firstOffer.arrow.lines[1].tipX, 6)
    local offerSpawns = { [94] = 90, [95] = 54, [96] = 55, [98] = 52 }
    env.LibQuestieDB = {
        Quest = {
            triggerEnd = function(id)
                local x = offerSpawns[id]
                if x then return { "Target", { [100] = { { x, 50 } } } } end
            end,
            objectives = function() return {} end,
        },
    }
    env.UnitXP, env.UnitXPMax = function() return 1000 end, function() return 4000 end
    modules.QuestXP = { GetQuestLogRewardXP = function(_, id) if id == 96 then return 2400 end end }
    AddOffer(98, "Too high nearby", 51, 1, nil, 13)
    settingsByKey.questieOfferRadius:SetValue(1000)
    flush()
    equal(firstOffer.label.text, "[10] Other nearby quest")
    equal(firstOffer.details.text, "|cffffc447Recommended|r · ~2400 XP · Objective: Westfall · ~10 yd after accepting · Target fits one active quest")
    equal(firstOffer.recommendation:IsShown(), true)
    firstOffer.scripts.OnEnter(firstOffer)
    equal(tooltip.text, "[10] Other nearby quest")
    equal(firstOffer.measurement.recommendationReason, "nearTarget")
    near(firstOffer.measurement.journeyYards, 70)
    env.QuestieTestFrame96.data.QuestData.level = nil
    fire("QUEST_LOG_UPDATE")
    flush()
    equal(firstOffer.measurement.id, 96)
    equal(firstOffer.measurement.recommended, nil)
    assert(firstOffer.details.text:find("~10 yd after accepting", 1, true))
    env.QuestieTestFrame96.data.QuestData.level = 10
    fire("QUEST_LOG_UPDATE")
    flush()
    equal(firstOffer.measurement.recommended, true)
    local originalMarker = reloadedAddon.ShowQuestMapMarker
    local offerMarker
    reloadedAddon.ShowQuestMapMarker = function(target) offerMarker = target end
    local beforeOfferTitle = title.text
    local beforeSelected = selectedQuest
    firstOffer:Click()
    equal(openedMap, 10)
    near(offerMarker.x, 0.56)
    equal(selectedQuest, beforeSelected)
    equal(title.text, beforeOfferTitle)
    reloadedAddon.ShowQuestMapMarker = originalMarker
    equal(secondOffer.recommendation:IsShown(), false)
    equal(firstOffer.distance.text, "Accept ~60 yd")
    equal(frames[firstNewFrame + 20].label.text, "Distant quest")
    reloadedCollapse:Click()
    equal(firstOffer:IsShown(), false)
    equal(secondOffer:IsShown(), false)
    equal(title:IsShown(), true)
    equal(objective:IsShown(), true)
    equal(updatedContent:IsShown(), true)
    reloadedCollapse:Click()
    equal(firstOffer:IsShown(), true)
    equal(secondOffer:IsShown(), true)
    env.LibQuestieDB, env.UnitXP, env.UnitXPMax, framesByID[98] = nil, nil, nil, nil
    settingsByKey.questieOfferRadius:SetValue(200)
    flush()

    playerX = 0.25
    questieTicker.tick()
    flush()
    equal(offer:IsShown(), false)
    complete[7] = true
    pinsByMap[10] = { { questID = 7, x = 0.1, y = 0.5 } }
    fire("QUEST_LOG_UPDATE")
    flush()
    equal(objective.text, "Ready to turn in")
    equal(finished.text, "+  1 completed objective")
    equal(navigation.notice.text, "Quest ready to turn in")
    equal(activeDistance.text, "~150 yd")
    near(arrow.lines[1].tipX, -8)

    -- A is closer, but B's second follow-up returns to A.
    env.bit = { band = function() return 0 end }
    env.UnitRace = function() return "Human", "Human", 1 end
    env.UnitClass = function() return "Mage", "MAGE", 8 end
    local records = {
        [72] = { finishedBy = { { 2 } }, childQuests = { 73 } },
        [73] = { name = "Middle stop", startedBy = { { 2 } }, finishedBy = { { 3 } }, preQuestSingle = { 72 }, nextQuestInChain = 74 },
        [74] = { name = "Back to A", startedBy = { { 3 } }, finishedBy = { { 4 } }, preQuestGroup = { 73, 72 }, childQuests = { 75 } },
        [75] = { startedBy = { { 4 } }, finishedBy = { { 3 } }, preQuestSingle = { 74 } },
    }
    local questDB = setmetatable({ Get = function(id, field) return (records[id] or {})[field] end }, {
        __index = function(_, key)
            return function(id)
                local value = (records[id] or {})[key]
                if key == "requiredLevel" then return 5 end
                if key == "objectives" then return {} end
                return value
            end
        end,
    })
    local npcX = { [2] = 30, [3] = 41, [4] = 60 }
    env.LibQuestieDB = { Quest = questDB, Npc = { spawns = function(id) return { [100] = { { npcX[id], 50 } } } end } }
    playerX = 0.5
    api.IsOnQuest = function(id) return id == 71 or id == 72 end
    complete[71], complete[72] = true, true
    quests = { { questID = 71, level = 9, title = "Stop A" }, { questID = 72, level = 10, title = "Stop B" } }
    pinsByMap[10] = { { questID = 71, x = 0.6, y = 0.5 }, { questID = 72, x = 0.3, y = 0.5 } }
    fire("QUEST_LOG_UPDATE")
    flush()
    local routeNote = updatedContent.labels[6]
    equal(title.text, "[10] Stop B")
    equal(rowOne.label.text, "[9] Stop A")
    equal(routeNote.text, "Follow-up 2 saves ~200 yd")
    local heightWithRoute = updatedTracker.height
    local topWithRoute = updatedTracker.point[5]
    local routeToggle, routeDetails = frames[firstNewFrame + 22], updatedContent.labels[7]
    equal(routeDetails:IsShown(), false)
    equal(updatedTracker.routeMap:IsShown(), true)
    local alternativesHeading = updatedContent.labels[4]
    equal(alternativesHeading.text, "−  Also in your quest log (1)")
    local alternativesToggle = alternativesHeading.point[2]
    alternativesToggle:Click()
    equal(alternativesHeading.text, "+  Also in your quest log (1)")
    equal(rowOne:IsShown(), false)
    equal(env.ForeverQuestNavigatorDB.alternativesCollapsed, true)
    alternativesToggle:Click()
    equal(rowOne:IsShown(), true)
    routeToggle:Click()
    equal(routeDetails:IsShown(), true)
    assert(routeDetails.text:find("Turn in Stop B\nFollow-up 1: Middle stop\nFollow-up 2: Back to A\nSame visit: Stop A", 1, true))
    assert(not routeDetails.text:find("Estimated:", 1, true))
    assert(updatedTracker.height > heightWithRoute)
    equal(updatedTracker.point[5], topWithRoute)
    routeToggle:Click()
    equal(updatedTracker.height, heightWithRoute)
    near(arrow.lines[1].tipX, -8)
    PinQuest(71)
    flush()
    equal(title.text, "[9] Stop A")
    equal(routeNote:IsShown(), true)
    equal(routeNote.text, "Manually selected · automatic choice paused")
    equal(routeToggle:IsShown(), true)
    auto:Click()
    flush()
    equal(title.text, "[10] Stop B")
    records[74].preQuestGroup = { 73, 999 }
    fire("QUEST_TURNED_IN", 999)
    flush()
    equal(title.text, "[9] Stop A")
    equal(routeNote:IsShown(), true)
    equal(routeNote.text, "Ready to turn in")

    local combat = false
    env.InCombatLockdown = function() return combat end

    -- Player is close to the next zone. Quest distance uses shared world
    -- coordinates even when the player has no position on that zone's map.
    env.LibQuestieDB = nil
    env.CreateVector2D = function(x, y) return { x = x, y = y } end
    env.C_Map.GetMapInfo = function(id)
        if id == 1 then return { mapType = mapType.Continent } end
        local names = { [10] = "Current zone", [20] = "Neighbor zone", [1416] = "Alteracgebirge", [1422] = "Westliche Pestländer" }
        return { mapType = mapType.Zone, parentMapID = 1, name = names[id] }
    end
    env.C_Map.GetMapChildrenInfo = function(id, mapKind, all)
        equal(id, 1)
        equal(mapKind, mapType.Zone)
        equal(all, true)
        return { { mapID = 10 }, { mapID = 20 }, { mapID = 30 } }
    end
    env.C_Map.GetWorldPosFromMapPos = function(id, position)
        return id == 30 and 2 or 1, {
            x = -position.y * 500,
            y = (id == 20 and -1000 or 0) - position.x * 1000,
        }
    end
    env.C_Map.GetPlayerMapPosition = function(id)
        if id == 10 then return { x = playerX, y = 0.5 } end
    end
    api.IsOnQuest = function() return true end
    complete[71], complete[72] = false, false
    quests = {
        { questID = 71, level = 10, title = "Same zone" },
        { questID = 72, level = 11, title = "Over the border" },
        { questID = 76, level = 9, title = "Different world" },
    }
    playerX = 0.98
    pinsByMap = {
        [10] = { { questID = 71, x = 0.70, y = 0.5 } },
        [20] = { { questID = 72, x = 0.03, y = 0.5 } },
        [30] = { { questID = 76, x = 0.98, y = 0.5 } },
    }
    fire("QUEST_POI_UPDATE")
    flush()
    equal(title.text, "[11] Over the border")
    local activeZone = updatedContent.labels[8]
    equal(activeZone.text, "Neighbor zone")
    equal(activeDistance.text, "~50 yd")
    equal(rowTwo.distance.text, "—")
    near(arrow.lines[1].tipX, 8)
    quests[2].level = 17
    fire("QUEST_LOG_UPDATE")
    flush()
    equal(title.text, "[10] Same zone")
    complete[72] = true
    fire("QUEST_LOG_UPDATE")
    flush()
    equal(title.text, "[17] Over the border")
    local questMapButton = frames[firstNewFrame + 23]
    questMapButton:Click()
    equal(openedMap, 20)
    equal(selectedQuest, 72)
    equal(pingedQuest, 72)

    records[74].preQuestGroup = { 73, 72 }
    api.IsOnQuest = function(id) return id == 71 or id == 72 end
    env.LibQuestieDB = { Quest = questDB, Npc = { spawns = function(id)
        if id == 4 then return { [200] = { { 3, 50 } } } end
        return { [100] = { { id == 2 and 80 or 88, 50 } } }
    end } }
    quests = { { questID = 71, level = 10, title = "A in the next zone" },
        { questID = 72, level = 10, title = "B in this zone" } }
    complete[71] = true
    pinsByMap = {
        [10] = { { questID = 72, x = 0.80, y = 0.5 } },
        [20] = { { questID = 71, x = 0.03, y = 0.5 } },
    }
    fire("QUEST_LOG_UPDATE")
    flush()
    equal(title.text, "[10] B in this zone")
    equal(rowOne.label.text, "[10] A in the next zone")
    equal(rowOne.zone.text, "Neighbor zone")
    equal(activeZone:IsShown(), false)
    equal(rowOne.distance.text, "~50 yd")
    equal(routeNote.text, "Follow-up 2 saves ~100 yd")
    near(arrow.lines[1].tipX, -8)

    api.GetQuestTagInfo = function(id)
        if id == 74 then return { tagID = 41 } end
    end
    fire("QUEST_DATA_LOAD_RESULT", 74)
    flush()
    equal(title.text, "[10] A in the next zone")
    equal(routeNote:IsShown(), true)
    equal(routeNote.text, "Ready to turn in")

    env.LibQuestieDB = nil
    quests = {
        { questID = 80, level = 10, title = "Outdoor elite" },
        { questID = 81, level = 10, title = "Dungeon objective" },
        { questID = 82, level = 10, title = "Raid objective" },
        { questID = 83, level = 10, title = "PvP objective" },
        { questID = 84, level = 10, title = "Heroic objective" },
        { questID = 85, level = 10, title = "Outdoor dungeon turn-in" },
        { questID = 86, level = 10, title = "Indoor raid turn-in" },
    }
    local questTags = { [80] = 1, [81] = 81, [82] = 88, [83] = 41, [85] = 81, [86] = 62 }
    api.GetQuestTagInfo = function(id) return questTags[id] and { tagID = questTags[id] } end
    modules.QuestieDB = { GetQuestTagInfo = function(id) return id == 84 and 85 or nil end }
    api.IsOnQuest = function(id) return id >= 80 and id <= 86 end
    api.GetNextWaypoint = function(id)
        if id == 85 then return 20, 0.04, 0.5 end
        if id == 86 then return 99, 0.4, 0.5 end
    end
    complete[85], complete[86] = true, true
    local getMapInfo = env.C_Map.GetMapInfo
    env.C_Map.GetMapInfo = function(id)
        if id == 99 then return { mapType = mapType.Dungeon, parentMapID = 10 } end
        return getMapInfo(id)
    end
    pinsByMap = { [10] = { { questID = 80, x = 0.88, y = 0.5 } } }
    for id = 81, 86 do
        pinsByMap[10][#pinsByMap[10] + 1] = { questID = id, x = 0.97, y = 0.5 }
    end
    fire("QUEST_LOG_UPDATE")
    flush()
    equal(title.text, "[10] Outdoor dungeon turn-in")
    equal(objective.text, "Ready to turn in")
    equal(rowOne.label.text, "[10] Outdoor elite |cffffc447+|r")
    equal(rowTwo:IsShown(), false)
    questMapButton:Click()
    equal(openedMap, 20)
    equal(selectedQuest, 85)
    equal(pingedQuest, 85)
    openedMap = nil
    combat = true
    questMapButton:Click()
    equal(openedMap, nil)
    equal(messages[#messages], "FQN | Open the quest map outside combat.")
    combat = false

    -- Gol'dir's discovery trigger, key drop, and hand-in all belong to Alterac.
    env.C_Map.GetMapChildrenInfo = function()
        return { { mapID = 10 }, { mapID = 1416 }, { mapID = 1422 } }
    end
    modules.ZoneDB.GetUiMapIdByAreaId = function(_, id)
        if id == 36 then return 1416 end
    end
    local alteracSpawns = { [36] = { { 60, 43.7 } } }
    env.LibQuestieDB = {
        Quest = {
            triggerEnd = function(id)
                equal(id, 503)
                return { "Find Gol'dir", alteracSpawns }
            end,
            objectives = function() return { { { 2316 } }, nil, { { 3704 } } } end,
            finishedBy = function() return { { 2316 } } end,
        },
        Npc = { spawns = function(id)
            assert(id == 2316 or id == 2431)
            return alteracSpawns
        end },
        Item = {
            npcDrops = function(id) equal(id, 3704) return { 2431 } end,
            objectDrops = function() return {} end,
        },
    }
    env.GetQuestUiMapID = function(id, ignoreWaypoints)
        equal(id, 503)
        equal(ignoreWaypoints, true)
        return 1422
    end
    api.IsOnQuest = function(id) return id == 503 end
    quests = { { questID = 503, level = 36, title = "Gol'dir" } }
    pinsByMap = { [1422] = { { questID = 503, x = 0.5, y = 0.5 } } }
    playerX = 0.88
    local playerMapOffset = 0
    local worldPosition = env.C_Map.GetWorldPosFromMapPos
    env.C_Map.GetWorldPosFromMapPos = function(id, position)
        local continent, point = worldPosition(id, position)
        if id == 10 then point.y = point.y - playerMapOffset end
        return continent, point
    end
    env.Enum.FlightPathFaction = { Neutral = 0, Horde = 1, Alliance = 2 }
    env.Enum.FlightPathState = { Current = 0, Reachable = 1, Unreachable = 2 }
    env.UnitFactionGroup = function() return "Horde" end
    env.GetTaxiMapID = function() return 1 end
    local taxiNodes = {
        { nodeID = 1, state = 1 }, { nodeID = 2, state = 2 }, { nodeID = 3, state = 0 },
    }
    local discoveredFlight = { nodeID = 1, name = "Test flight point", faction = 1,
        position = { x = 0.7, y = 0.437 }, isUndiscovered = false }
    local borderFlights = {}
    env.C_TaxiMap = { GetAllTaxiNodes = function(id)
        equal(id, 1)
        return taxiNodes
    end, GetTaxiNodesForMap = function(id)
        if id == 1 then return borderFlights end
        equal(id, 1416)
        return { discoveredFlight,
            { nodeID = 2, name = "Locked despite map flag", faction = 1,
                position = { x = 0.61, y = 0.437 }, isUndiscovered = false },
            { nodeID = 3, name = "Other faction", faction = 2,
                position = { x = 0.62, y = 0.437 }, isUndiscovered = false },
        }
    end }
    fire("QUEST_LOG_UPDATE")
    flush()
    equal(activeZone.text, "Alteracgebirge")
    equal(activeDistance.text, "~282 yd")
    equal(routeToggle:IsShown(), true)
    assert(routeNote.text:find("Nearby target", 1, true))
    routeToggle:Click()
    assert(routeDetails.text:find("Quest objective: Alteracgebirge", 1, true))
    assert(not routeDetails.text:find("Unlocked flight point", 1, true))
    equal(updatedTracker.routeMap.text, "Map")
    local marker, mapShown = nil, false
    env.Mixin = function(object, ...)
        for index = 1, select("#", ...) do
            for key, value in pairs(select(index, ...)) do object[key] = value end
        end
        return object
    end
    env.CreateFromMixins = function(...) return env.Mixin({}, ...) end
    env.GameTooltip.IsOwned = function() return false end
    env.MapCanvasDataProviderMixin = { GetMap = function(self) return self.map end }
    env.MapCanvasPinMixin = {
        SetPosition = function(self, x, y) self.x, self.y = x, y end,
        SetScalingLimits = noOp,
        UseFrameLevelType = function(self, layer) self.layer = layer end,
        SetPassThroughButtons = function(self, button) self.passThrough = button end,
        OnReleased = noOp,
    }
    local pinPool = {}
    env.WorldMapFrame = {
        GetMapID = function() return openedMap end,
        IsShown = function() return mapShown end,
        AddDataProvider = function(self, provider) self.provider, provider.map = provider, self end,
        OnMapChanged = function(self) self.provider:RefreshAllData() end,
        RemoveAllPinsByTemplate = function(_, template)
            equal(template, "ForeverQuestNavigatorTargetPinTemplate")
            for _, pin in ipairs(pinPool) do if pin:IsShown() then pin:Hide(); pin:OnReleased() end end
            env.WorldMapFrame.activePinCount = 0
        end,
        AcquirePin = function(_, template, ...)
            equal(template, "ForeverQuestNavigatorTargetPinTemplate")
            local index = (env.WorldMapFrame.activePinCount or 0) + 1
            env.WorldMapFrame.activePinCount = index
            local pin = pinPool[index]
            if not pin then
                pin = createFrame()
                env.ForeverQuestNavigator_InitializeTargetPin(pin)
                pin:OnLoad()
                pinPool[index] = pin
            end
            if index == 1 then marker = pin end
            pin:Show()
            pin:OnAcquired(...)
            pin:CheckMouseButtonPassthrough("RightButton")
            return pin
        end,
    }
    updatedTracker.routeMap:Click()
    equal(openedMap, 1416)
    equal(marker, nil)
    mapShown = true
    env.WorldMapFrame:OnMapChanged()
    equal(marker:IsShown(), true)
    equal(marker.layer, "PIN_FRAME_LEVEL_WAYPOINT_LOCATION")
    equal(marker.passThrough, "LeftButton")
    near(marker.x, 0.6)
    near(marker.y, 0.437)
    openedMap = 1422
    env.WorldMapFrame:OnMapChanged()
    equal(marker:IsShown(), false)
    openedMap = 1416
    env.WorldMapFrame:OnMapChanged()
    equal(marker:IsShown(), true)
    marker:OnClick("RightButton")
    equal(marker:IsShown(), false)
    distanceTicker.tick()
    equal(marker:IsShown(), false)
    updatedTracker.routeMap:Click()
    equal(marker:IsShown(), true)
    routeToggle:Click()
    playerMapOffset = 2200
    distanceTicker.tick()
    assert(routeNote.text:find("Travel distance", 1, true))
    fire("TAXIMAP_OPENED")
    flush()
    equal(env.ForeverQuestNavigatorCharacterDB.confirmedFlightPoints[1], true)
    equal(env.ForeverQuestNavigatorCharacterDB.confirmedFlightPoints[2], nil)
    assert(routeNote.text:find("Travel distance", 1, true))
    routeToggle:Click()
    assert(routeDetails.text:find("Unlocked flight point: Test flight point (~100 yd from target)", 1, true))
    playerMapOffset = 0
    distanceTicker.tick()
    equal(routeDetails:IsShown(), true)
    assert(not routeDetails.text:find("Unlocked flight point", 1, true))
    playerMapOffset = 2200
    distanceTicker.tick()
    questMapButton:Click()
    equal(openedMap, 1416)
    discoveredFlight.isUndiscovered = true
    fire("TAXI_NODE_STATUS_CHANGED")
    flush()
    assert(routeNote.text:find("Travel distance", 1, true))
    assert(not routeDetails.text:find("Unlocked flight point", 1, true))
    borderFlights[1] = { nodeID = 4, name = "Neighbor flight point", faction = 0,
        position = { x = 0.65, y = 0.437 }, isUndiscovered = false }
    taxiNodes[4] = { nodeID = 4, state = 1 }
    fire("TAXI_NODE_STATUS_CHANGED")
    flush()
    assert(routeDetails.text:find("Unlocked flight point: Neighbor flight point (~50 yd from target)", 1, true))
    fire("TAXIMAP_CLOSED")
    flush()

    playerMapOffset = 1420
    quests[2] = { questID = 501, level = 10, title = "Local task" }
    api.IsOnQuest = function(id) return id == 501 or id == 503 end
    pinsByMap[10] = { { questID = 501, x = 0.85, y = 0.5 } }
    env.GetQuestUiMapID = function(id) return id == 503 and 1422 or 10 end
    fire("QUEST_LOG_UPDATE")
    flush()
    equal(title.text, "[10] Local task")
    equal(rowOne.label.text, "[36] Gol'dir")
    equal(rowOne.distance.text, "~1700 yd")
    equal(rowOne.routeButton:IsShown(), true)
    equal(routeToggle:IsShown(), true)
    openedMap = nil
    rowOne.routeButton:Click()
    equal(rowOne.routeDetails:IsShown(), true)
    assert(rowOne.routeDetails.text:find("Unlocked flight point: Neighbor flight point (~50 yd from target)", 1, true))
    equal(title.text, "[10] Local task")
    equal(openedMap, nil)
    rowOne.routeMap:Click()
    equal(openedMap, 1416)
    equal(title.text, "[10] Local task")
    playerMapOffset = 0
    distanceTicker.tick()
    equal(rowOne.routeButton:IsShown(), true)
    equal(rowOne.routeDetails:IsShown(), true)
    assert(not rowOne.routeDetails.text:find("Unlocked flight point", 1, true))

    playerMapOffset = 2200
    quests[2], pinsByMap[10] = nil, nil
    complete[503] = true
    fire("QUEST_LOG_UPDATE")
    flush()
    questMapButton:Click()
    equal(openedMap, 1416)
    equal(selectedQuest, 503)

    playerMapOffset = 2200
    local mapProjection = env.C_Map.GetWorldPosFromMapPos
    env.C_Map.GetWorldPosFromMapPos = function(id, position)
        if id == 1 then return 1, { x = -position.y * 500, y = -position.x * 5000 } end
        return mapProjection(id, position)
    end
    taxiNodes[1] = { nodeID = 1, state = 0, slotIndex = 1, name = "Departure",
        position = { x = 0.61, y = 0.5 } }
    taxiNodes[2] = { nodeID = 2, state = 1, slotIndex = 2, name = "Arrival",
        position = { x = 0.13, y = 0.437 } }
    taxiNodes[3] = { nodeID = 3, state = 2, slotIndex = 3, name = "Intermediate stop",
        position = { x = 0.37, y = 0.5 } }
    taxiNodes[4] = nil
    env.GetNumRoutes = function(slot) equal(slot, 2); return 2 end
    env.TaxiGetNodeSlot = function(slot, index, source)
        equal(slot, 2)
        if index == 1 then return source and 1 or 3 end
        equal(index, 2)
        return source and 3 or 2
    end
    fire("TAXIMAP_OPENED")
    flush()
    assert(routeDetails.text:find("Fly: Departure to Arrival", 1, true))
    assert(routeDetails.text:find("~30 yd to departure · ~50 yd after landing", 1, true))
    assert(not routeDetails.text:find("Estimated:", 1, true))
    taxiNodes[3].position.x = 0.99
    fire("TAXI_NODE_STATUS_CHANGED")
    flush()
    assert(not routeDetails.text:find("Fly:", 1, true))
    taxiNodes[3].position.x = 0.37
    fire("TAXI_NODE_STATUS_CHANGED")
    flush()
    assert(routeDetails.text:find("Fly: Departure to Arrival", 1, true))
    playerMapOffset = 1300
    distanceTicker.tick()
    assert(not routeDetails.text:find("Fly:", 1, true))
    playerMapOffset = 2200
    taxiNodes[2].state = 2
    fire("TAXI_NODE_STATUS_CHANGED")
    flush()
    assert(not routeDetails.text:find("Fly:", 1, true))
    fire("TAXIMAP_CLOSED")
    flush()
    env.C_Map.GetWorldPosFromMapPos = mapProjection

    env.LibQuestieDB, env.GetQuestUiMapID = nil, nil
    env.C_Map.GetMapPosFromWorldPos = function(_, position)
        near(position.y, -500)
        return 1416, { x = 0.6, y = 0.437 }
    end
    fire("QUEST_LOG_UPDATE")
    flush()
    questMapButton:Click()
    equal(openedMap, 1416)

    -- A reachable quest on the approach saves backtracking across three stops.
    env.C_Map.GetMapPosFromWorldPos = nil
    playerMapOffset, playerX = 0, 0.2
    quests = {
        { questID = 601, level = 10, title = "Main objective" },
        { questID = 602, level = 12, title = "On the approach" },
        { questID = 603, level = 10, title = "Outdoor hand-in" },
    }
    api.IsOnQuest = function(id) return id >= 601 and id <= 603 end
    complete[603] = true
    objectives[602] = { { text = "First objective" }, { text = "Second objective" } }
    pinsByMap = { [10] = {
        { questID = 601, x = 0.8, y = 0.5 },
        { questID = 602, x = 0.72, y = 0.5 },
        { questID = 603, x = 0.9, y = 0.5 },
    } }
    fire("QUEST_LOG_UPDATE")
    flush()
    equal(title.text, "[12] On the approach")
    equal(routeNote.text, "Outing saves ~160 yd")
    assert(routeDetails.text:find("1. Work on On the approach\n2. Work on Main objective\n3. Turn in Outdoor hand-in", 1, true))
    local preview
    for _, frame in ipairs(frames) do
        if frame.parent == updatedContent and frame.labels[1] and frame.labels[1].text == "Next stops" then
            preview = frame
        end
    end
    assert(preview)
    equal(preview:IsShown(), false)
    routeToggle:Click()
    equal(preview:IsShown(), true)
    local previewRows = {}
    for _, frame in ipairs(frames) do
        if frame.parent == preview and frame.stop then previewRows[#previewRows + 1] = frame end
    end
    equal(#previewRows, 3)
    equal(previewRows[1].stop.quest.id, 602)
    equal(previewRows[1].stop.current, true)
    near(previewRows[1].stop.yards, 520)
    equal(previewRows[2].stop.quest.id, 601)
    near(previewRows[2].stop.yards, 80)
    equal(previewRows[3].stop.quest.id, 603)
    equal(previewRows[3].stop.action, "turnIn")
    near(previewRows[3].stop.yards, 100)
    previewRows[2]:Click()
    equal(selectedQuest, 601)
    equal(title.text, "[12] On the approach")
    routeToggle:Click()
    equal(preview:IsShown(), false)
    env.GetQuestUiMapID = function(id) if id == 602 then return 1422 end end
    fire("QUEST_POI_UPDATE")
    flush()
    questMapButton:Click()
    equal(openedMap, 10)
    equal(marker:IsShown(), true)
    near(marker.x, 0.72)
    near(marker.y, 0.5)
    pinsByMap[10][2].x = 0.73
    fire("QUEST_POI_UPDATE")
    flush()
    near(marker.x, 0.73)
    objectives[602][1].finished = true
    fire("QUEST_LOG_CRITERIA_UPDATE", 602)
    flush()
    equal(title.text, "[10] Main objective")
    equal(routeNote.text, "Next stop on your outing")
    equal(previewRows[1].stop.quest.id, 601)
    assert(routeDetails.text:find("1. Work on Main objective\n2. Turn in Outdoor hand-in", 1, true))
    local stop = FindTrackerButton(updatedContent, "Objective: [12] On the approach")
    equal(stop:IsShown(), false)
    routeToggle:Click()
    equal(stop:IsShown(), true)
    stop:Click()
    equal(selectedQuest, 602)
    near(marker.x, 0.73)
    equal(title.text, "[10] Main objective")
    routeToggle:Click()
    equal(stop:IsShown(), false)
    complete[601] = true
    fire("QUEST_LOG_UPDATE")
    flush()
    equal(title.text, "[10] Outdoor hand-in")
    equal(routeNote.text, "Next stop on your outing")

    local playerLevel, playerXP = 10, 700
    env.UnitLevel = function() return playerLevel end
    env.UnitXP = function(unit) equal(unit, "player"); return playerXP end
    env.UnitXPMax = function() return 1000 end
    env.GetQuestLogRewardXP = function(id)
        if id == 701 then return 175 end
        if id == 702 then return 250 end
    end
    quests = {
        { questID = 701, level = 10, title = "Regular objective" },
        { questID = 702, level = 10, title = "Ready reward" },
        { questID = 703, level = 13, title = "Hard quest" },
    }
    api.IsOnQuest = function(id) return id >= 701 and id <= 703 end
    complete[702] = true
    pinsByMap[10] = {
        { questID = 701, x = 0.50, y = 0.5 },
        { questID = 702, x = 0.58, y = 0.5 },
        { questID = 703, x = 0.365, y = 0.5 },
    }
    fire("QUEST_LOG_UPDATE")
    flush()
    equal(title.text, "[10] Regular objective")
    local xpLabel = updatedContent.labels[9]
    equal(xpLabel.text, "~175 XP")
    assert(routeDetails.text:find("125 XP still needed afterward", 1, true))
    equal(rowOne.reward.text, "~250 XP")
    equal(rowOne:GetHeight(), 36)
    equal(rowOne.reward.point[3], -20)
    equal(rowOne.routeButton.point[1], "TOPRIGHT")
    assert(rowOne.routeDetails.text:find("50 XP still needed afterward", 1, true))
    settingsByKey.showQuestXP:SetValue(false)
    flush()
    equal(xpLabel:IsShown(), false)
    equal(rowOne.reward:IsShown(), false)
    equal(env.ForeverQuestNavigatorDB.showQuestXP, false)
    settingsByKey.showQuestXP:SetValue(true)
    flush()
    equal(xpLabel:IsShown(), true)
    equal(rowOne.reward:IsShown(), true)
    playerXP = 710
    fire("PLAYER_XP_UPDATE", "player")
    equal(title.text, "[10] Regular objective")
    equal(xpLabel.text, "~175 XP")
    assert(routeDetails.text:find("115 XP still needed afterward", 1, true))
    equal(rowOne.reward.text, "~250 XP")
    assert(rowOne.routeDetails.text:find("40 XP still needed afterward", 1, true))
    playerXP = 750
    fire("PLAYER_XP_UPDATE", "player")
    equal(title.text, "[10] Ready reward")
    equal(xpLabel.text, "Level-up possible")
    equal(routeDetails:IsShown(), false)
    equal(routeNote:IsShown(), false)
    assert(routeDetails.text:find("250 XP · 250 XP to level 11", 1, true))
    assert(routeDetails.text:find("Easier after leveling: Hard quest", 1, true))
    PinQuest(701)
    flush()
    equal(rowOne.reward.text, "~250 XP · Level-up possible")
    equal(rowOne:GetHeight(), 36)
    auto:Click()
    flush()
    equal(title.text, "[10] Ready reward")
    settingsByKey.showQuestXP:SetValue(false)
    flush()
    equal(xpLabel:IsShown(), false)
    equal(title.text, "[10] Ready reward")
    assert(routeDetails.text:find("Easier after leveling: Hard quest", 1, true))
    env.IsXPUserDisabled = function() return true end
    fire("PLAYER_XP_UPDATE", "player")
    assert(not routeDetails.text:find("XP to level", 1, true))
    equal(xpLabel:IsShown(), false)
    env.IsXPUserDisabled = nil
    playerLevel, playerXP = 11, 0
    table.remove(quests, 2)
    table.remove(pinsByMap[10], 2)
    api.IsOnQuest = function(id) return id == 701 or id == 703 end
    fire("PLAYER_LEVEL_UP", 11)
    fire("QUEST_TURNED_IN", 702)
    flush()
    equal(title.text, "[13] Hard quest")
    assert(not routeDetails.text:find("XP to level", 1, true))

    quests = {
        { questID = 801, level = 11, title = "Near the player" },
        { questID = 802, level = 11, title = "Pinned objective" },
        { questID = 803, level = 11, title = "Near the pinned target" },
    }
    api.IsOnQuest = function(id) return id >= 801 and id <= 803 end
    pinsByMap[10] = {
        { questID = 801, x = 0.25, y = 0.5 },
        { questID = 802, x = 0.8, y = 0.5 },
        { questID = 803, x = 0.75, y = 0.5 },
    }
    fire("QUEST_LOG_UPDATE")
    flush()
    equal(title.text, "[11] Near the player")
    PinQuest(802)
    flush()
    equal(title.text, "[11] Pinned objective")
    equal(rowOne.label.text, "[11] Near the pinned target")
    equal(rowOne.distance.text, "~550 yd")
    equal(rowTwo.label.text, "[11] Near the player")
    rowOne:Click()
    equal(selectedQuest, 803)
    equal(title.text, "[11] Pinned objective")
    equal(QuestLogMenuEntry(nil), nil)
    table.remove(quests, 2)
    table.remove(pinsByMap[10], 2)
    fire("QUEST_REMOVED", 802)
    flush()
    equal(title.text, "[11] Near the player")
    equal(auto:IsShown(), false)

    local detailsPanel, backButton = createFrame(), createFrame()
    detailsPanel.BackFrame = { BackButton = backButton }
    env.QuestMapFrame = { DetailsFrame = detailsPanel }
    env.QuestMapFrame_ShowQuestDetails = function(id)
        detailsPanel.questID = id
        detailsPanel:Show()
    end
    env.QuestMapFrame_OpenToQuestDetails = function(id)
        selectedQuest = id
        openedMap = 1422
        env.QuestMapFrame_ShowQuestDetails(id)
    end
    env.WorldMapFrame.SetMapID = function(map, id) openedMap = id; map:OnMapChanged() end
    env.hooksecurefunc = function(owner, name, callback)
        if type(owner) == "string" then owner, name, callback = env, owner, name end
        local original = owner[name]
        owner[name] = function(...) original(...); callback(...) end
    end
    fire("ADDON_LOADED", "Blizzard_WorldMap")
    local pinButton = frames[#frames]
    equal(pinButton:IsShown(), false)
    rowOne:Click()
    equal(detailsPanel.questID, 803)
    equal(openedMap, 10)
    equal(marker:IsShown(), true)
    near(marker.x, 0.75)
    equal(title.text, "[11] Near the player")
    equal(pinButton.point[2], backButton)
    equal(pinButton.text, "Set as active in FQN")
    pinButton:Click()
    flush()
    equal(title.text, "[11] Near the pinned target")
    equal(pinButton.text, "Resume FQN auto select")
    pinButton:Click()
    flush()
    equal(title.text, "[11] Near the player")

    modules.TrackerMenu = { addShowInQuestLogOption = function(menu)
        menu[#menu + 1] = { text = "Show in Quest Log" }
    end }
    fire("ADDON_LOADED", "Questie")
    local trackerMenu = {}
    modules.TrackerMenu.addShowInQuestLogOption(trackerMenu, { Id = 803 })
    equal(trackerMenu[1].text, "Show in Quest Log")
    equal(trackerMenu[2].text, "Set as active in FQN")
    trackerMenu[2].func()
    flush()
    equal(title.text, "[11] Near the pinned target")
    trackerMenu = {}
    modules.TrackerMenu.addShowInQuestLogOption(trackerMenu, { Id = 803 })
    equal(trackerMenu[2].text, "Resume FQN auto select")
    trackerMenu[2].func()
    flush()
    equal(title.text, "[11] Near the player")
    env.QuestMapFrame_OpenToQuestDetails = function() error("Quest details are unavailable") end
    openedMap = nil
    rowOne:Click()
    equal(openedMap, 10)
    equal(marker:IsShown(), true)
    equal(title.text, "[11] Near the player")

    quests, pinsByMap[10] = {}, {}
    api.IsOnQuest = function(id) return id >= 901 and id <= 908 end
    env.UnitLevel = function() return 11 end
    for index = 1, 8 do
        local id = 900 + index
        quests[index] = { questID = id, level = 11, title = "Scrollable quest " .. index }
        pinsByMap[10][index] = { questID = id, x = 0.2 + index * 0.08, y = 0.5 }
    end
    fire("QUEST_LOG_UPDATE")
    flush()
    PinQuest(901)
    flush()
    local heading = updatedContent.labels[4]
    local acceptedToggle = heading.point[2]
    assert(heading.text:find("1–2/7", 1, true))
    local firstID = rowOne.questID
    acceptedToggle.scripts.OnMouseWheel(acceptedToggle, -1)
    assert(rowOne.questID ~= firstID)
    settingsByKey.acceptedRows:SetValue(5)
    local function VisibleAcceptedRows()
        local count = 0
        for _, frame in ipairs(frames) do
            if frame.parent == updatedContent and frame.checkbox and frame.questID and frame:IsShown() then
                count = count + 1
            end
        end
        return count
    end
    equal(VisibleAcceptedRows(), 5)
    settingsByKey.acceptedRows:SetValue(2)
    equal(VisibleAcceptedRows(), 2)
    settingsByKey.fontPercent:SetValue(140)
    near(title.fontSize, 16.8)
    near(navigation.title.fontSize, 16.8)
    assert(rowOne:GetHeight() <= 36)
    equal(rowOne.reward:IsShown(), false)
    equal(env.ForeverQuestNavigatorDB.detailMode, "detailed")
    settingsByKey.fontPercent:SetValue(100)
    near(title.fontSize, 12)
    local offerSamples = {}
    for index = 1, 6 do offerSamples[index] = { id = index, title = "Offer " .. index, yards = index * 10 } end
    updatedTracker:RenderNearbyOffers(offerSamples)
    settingsByKey.offerRows:SetValue(5)
    local offerHeading = updatedContent.labels[5]
    assert(offerHeading.text:find("1–5/6", 1, true))
    offerHeading.point[2].scripts.OnMouseWheel(offerHeading.point[2], -1)
    equal(firstOffer.label.text, "Offer 2")
    settingsByKey.offerRows:SetValue(3)
    local mainMapButton = frames[firstNewFrame + 23]
    mainMapButton.scripts.OnEnter(mainMapButton)
    assert(tooltip.text:find("Scrollable quest 1", 1, true))
    assert(tooltip.lines[1]:find("Why this quest?", 1, true))
    assert(tooltip.lines[1]:find("You selected this quest", 1, true))
    activeCheckbox:Click()
    flush()
    equal(env.ForeverQuestNavigatorCharacterDB.skippedQuests[901].quest.id, 901)
    local undo = FindTrackerButton(updatedContent, "Quest skipped · Undo")
    equal(undo:IsShown(), true)
    undo:Click()
    flush()
    equal(env.ForeverQuestNavigatorCharacterDB.skippedQuests[901], nil)
    equal(undo:IsShown(), false)
    local nextSkipped = activeCheckbox.quest.id
    activeCheckbox:Click()
    flush()
    undo.scripts.OnUpdate(undo, 9)
    equal(undo:IsShown(), false)
    assert(env.ForeverQuestNavigatorCharacterDB.skippedQuests[nextSkipped])

    -- Exercise the real button/event flow, not just the hold state helper.
    env.LibQuestieDB = nil
    api.GetNextWaypoint = nil
    api.IsOnQuest = function(id) return id == 1001 or id == 1002 end
    quests = { { questID = 1001, title = "Held patrol", level = 11 }, { questID = 1002, title = "Other patrol", level = 11 } }
    pinsByMap[10] = { { questID = 1001, x = 0.51, y = 0.5 }, { questID = 1002, x = 0.7, y = 0.5 } }
    objectives[1001], objectives[1002] = { { text = "Patrol A" } }, { { text = "Patrol B" } }
    complete[1001], complete[1002], playerX = nil, nil, 0.5
    settingsByKey.showScreenArrow:SetValue(true)
    fire("QUEST_LOG_UPDATE")
    flush()
    equal(title.text, "[11] Held patrol")
    equal(activeDistance.text, "Arrived")
    equal(navigation.arrow:IsShown(), false)
    equal(updatedTracker.progressLine.text, "2 objectives open · 0 ready to turn in")
    updatedTracker.holdButton:Click()
    flush()
    equal(routeNote.text, "Following this quest until completed")
    playerX = 0.69
    distanceTicker.tick()
    equal(title.text, "[11] Held patrol")
    complete[1001] = true
    fire("QUEST_LOG_UPDATE")
    flush()
    equal(title.text, "[11] Other patrol")
    equal(updatedTracker.progressLine.text, "1 objective open · 1 ready to turn in")
    updatedTracker.holdButton.scripts.OnEnter(updatedTracker.holdButton)
    equal(tooltip.text, "Follow until completed")
    updatedTracker.holdButton:Click()
    flush()
    updatedTracker.holdButton:Click()
    flush()
    equal(routeNote.text, "Nearby target · Your level")

    updatedTracker:SetNewOffers({ [777] = true })
    local sample = { { id = 777, title = "New offer", level = 11, yards = 40, recommended = true } }
    updatedTracker:RenderNearbyOffers(sample)
    equal(firstOffer.discovery:IsShown(), true)
    firstOffer.scripts.OnUpdate(firstOffer, 5)
    equal(firstOffer.discovery:IsShown(), false)
    updatedTracker:RenderNearbyOffers(sample)
    equal(firstOffer.discovery:IsShown(), false)

    local skips = env.ForeverQuestNavigatorCharacterDB.skippedQuests
    local radius, language = env.ForeverQuestNavigatorDB.questieOfferRadius, env.ForeverQuestNavigatorDB.language
    settingsByKey.opacityPercent:SetValue(35)
    settingsByKey.fontPercent:SetValue(120)
    settingsByKey.acceptedRows:SetValue(5)
    settingsByKey.offerRows:SetValue(4)
    settingsByKey.allowTrackerResize:SetValue(true)
    env.ForeverQuestNavigatorDB.collapsed = true
    env.ForeverQuestNavigatorDB.targetGroupsExpanded = { [1001] = true }
    settingsByKey.resetAppearance.callback()
    flush()
    equal(env.ForeverQuestNavigatorDB.opacityPercent, 80)
    equal(env.ForeverQuestNavigatorDB.fontPercent, 100)
    equal(env.ForeverQuestNavigatorDB.acceptedRows, 2)
    equal(env.ForeverQuestNavigatorDB.offerRows, 3)
    equal(env.ForeverQuestNavigatorDB.allowTrackerResize, false)
    equal(env.ForeverQuestNavigatorDB.collapsed, false)
    equal(next(env.ForeverQuestNavigatorDB.targetGroupsExpanded), nil)
    equal(updatedTracker:GetWidth(), 352)
    equal(env.ForeverQuestNavigatorCharacterDB.skippedQuests, skips)
    assert(skips[nextSkipped])
    equal(env.ForeverQuestNavigatorDB.language, language)
    equal(env.ForeverQuestNavigatorDB.questieOfferRadius, radius)

    -- Known completion routes, access-point menus and focused copyable reports.
    modules.ZoneDB.GetUiMapIdByAreaId = function(_, area) return area / 10 end
    env.LibQuestieDB = {
        Quest = {
            finishedBy = function(id) if id == 1002 then return { {9001} } end end,
            extraObjectives = function(id)
                if id == 1002 then return { { { [100] = { {60, 50} } }, 3, "Cave entrance", 0 } } end
            end,
        },
        Npc = { spawns = function() return { [100] = { {20, 50} } } end }, Object = {},
    }
    PinQuest(1002)
    flush()
    assert(routeDetails.text:find("Known goals and turn-in:", 1, true))
    local function MenuAction(label)
        local function Find(entries)
            for _, entry in ipairs(entries) do
                if entry.label == label and entry.restore then return entry.restore end
                local action = Find(entry.entries or {})
                if action then return action end
            end
        end
        local action = Find(historyMenu.entries)
        if action then action() return end
        error("Missing menu entry: " .. label)
    end
    mainMapButton:Click("RightButton")
    MenuAction("Save my position as this objective's access point")
    flush()
    near(env.ForeverQuestNavigatorCharacterDB.accessPoints[1002][0].point.x, 0.69)
    playerX = 0.4
    mainMapButton:Click("RightButton")
    MenuAction("Navigate via access point again")
    flush()
    assert(routeDetails.text:find("Via access:", 1, true))
    equal(navigation.goal.text, "Access: Saved access point")
    mainMapButton:Click()
    near(marker.x, 0.69)
    mainMapButton:Click("RightButton")
    MenuAction("Report an unsuitable target position")
    local function Window(title)
        for _, frame in ipairs(frames) do
            if frame.heading and frame.heading.text == title then return frame end
        end
        error("Missing window: " .. title)
    end
    local reportWindow = Window("FQN target position report")
    assert(reportWindow.edit.text:find("reportedQuest=1002", 1, true))
    assert(reportWindow.edit.text:find("navigationTarget: map=10 x=0.690000", 1, true))
    assert(reportWindow.edit.text:find("objectiveTarget: map=10 x=0.700000", 1, true))
    mainMapButton:Click("RightButton")
    MenuAction("Show hint on map: Cave entrance")
    near(marker.x, 0.6)
    mainMapButton:Click("RightButton")
    MenuAction("Use hint as access: Cave entrance")
    flush()
    mainMapButton:Click()
    near(marker.x, 0.6)
    playerX = 0.6
    distanceTicker.tick()
    mainMapButton:Click()
    near(marker.x, 0.7)
    mainMapButton:Click("RightButton")
    MenuAction("Remove this objective's access point")
    flush()
    equal(env.ForeverQuestNavigatorCharacterDB.accessPoints[1002][0], nil)
    local activeTitle = title.text
    rowOne:Click("RightButton")
    MenuAction("Report an unsuitable target position")
    assert(reportWindow.edit.text:find("reportedQuest=1001", 1, true))
    equal(title.text, activeTitle)
    if firstOffer:IsShown() and firstOffer.measurement then
        local id = firstOffer.measurement.id
        firstOffer:Click("RightButton")
        MenuAction("Report an unsuitable target position")
        assert(reportWindow.edit.text:find("reportedQuest=" .. id, 1, true))
        assert(reportWindow.edit.text:find("kind=quest offer", 1, true))
        equal(title.text, activeTitle)
    end

    local sessionNow, currentXP = 100, 100
    env.GetTime = function() return sessionNow end
    env.UnitXP = function() return currentXP end
    env.UnitXPMax = function() return 1000 end
    env.SlashCmdList.FOREVERQUESTNAVIGATOR("session reset")
    currentXP, sessionNow = 250, 160
    fire("PLAYER_XP_UPDATE", "player")
    fire("QUEST_TURNED_IN", 1001, 150)
    flush()
    settingsByKey.openSession.callback()
    local sessionWindow = Window("FQN session overview")
    assert(sessionWindow.copyText:find("Played time: 0 h 1 min", 1, true))
    assert(sessionWindow.copyText:find("Observed XP gained: 150", 1, true))
    assert(sessionWindow.copyText:find("Known XP from quest turn-ins: 150", 1, true))
    assert(sessionWindow.copyText:find("Quests turned in: 1", 1, true))
    equal(env.ForeverQuestNavigatorCharacterDB.skippedQuests, skips)

    env.GetQuestLogRewardXP = function(id) return id == 1002 and 750 or 250 end
    settingsByKey.showQuestXP:SetValue(true)
    fire("QUEST_LOG_UPDATE")
    flush()
    if not routeDetails:IsShown() then routeToggle:Click() end
    local detailedHeight = updatedTracker:GetHeight()
    local selectedTitle = title.text
    settingsByKey.detailMode:SetValue("compact")
    equal(routeDetails:IsShown(), false)
    equal(rowOne.reward:IsShown(), false)
    equal(rowOne.routeButton:IsShown(), false)
    assert(updatedTracker:GetHeight() < detailedHeight)
    equal(title.text, selectedTitle)
    mainMapButton.scripts.OnEnter(mainMapButton)
    assert(tooltip.lines[1]:find("Known goals and turn-in", 1, true))
    assert(tooltip.lines[1]:find("750 XP", 1, true))
    settingsByKey.detailMode:SetValue("detailed")
    equal(routeDetails:IsShown(), true)
    equal(rowOne.reward:IsShown(), true)
    settingsByKey.preview.callback()
    local appearance = Window("Appearance preview")
    settingsByKey.opacityPercent:SetValue(0)
    near(appearance.sampleBackdrop.colorAlpha, 0)
    equal(appearance.sample.alpha, nil)
    settingsByKey.fontPercent:SetValue(120)
    near(appearance.sample.fontSize, 14.4)
    settingsByKey.detailMode:SetValue("compact")
    equal(appearance.xp:IsShown(), false)
    settingsByKey.detailMode:SetValue("detailed")
    equal(appearance.xp:IsShown(), true)
    settingsByKey.resetAppearance.callback()
    flush()

    mainMapButton:Click("RightButton")
    MenuAction("Save my position as this objective's access point")
    flush()
    for id = 99991, 99996 do
        env.ForeverQuestNavigatorCharacterDB.accessPoints[id] = {
            [1] = { name = "Old access", questTitle = "Completed quest", point = { mapID = 10, x = 0.3, y = 0.5 } },
        }
    end
    settingsByKey.accessManager.callback()
    local manager = Window("Saved access points")
    equal(manager.rows[1].entry.questID, 1002)
    manager.rows[1].edit:SetText("Back entrance")
    manager.rows[1].save:Click()
    flush()
    equal(env.ForeverQuestNavigatorCharacterDB.accessPoints[1002][0].name, "Back entrance")
    manager.rows[1].map:Click()
    near(marker.x, 0.6)
    manager.rows[1].remove:Click()
    flush()
    equal(env.ForeverQuestNavigatorCharacterDB.accessPoints[1002], nil)
    manager.next:Click()
    equal(manager.page, 1)
    equal(manager.rows[1].entry.questID, 99996)
    assert(manager.rows[1].label.text:find("Completed quest", 1, true))
    manager.rows[1].remove:Click()
    flush()
    equal(manager.page, 0)
    equal(manager.previous.enabled, false)

    sessionWindow.scripts.OnUpdate(sessionWindow, 1)
    equal(sessionWindow.cards[2].text, "150")
    sessionWindow.copy:Click()
    local copy = Window("Copy session summary")
    local snapshot = copy.edit.text

    -- Search and status filters apply before pagination, including completed quests.
    mainMapButton:Click("RightButton")
    MenuAction("Save my position as this objective's access point")
    flush()
    local oldCompleted = api.IsQuestFlaggedCompleted
    api.IsQuestFlaggedCompleted = function(id) return id >= 99991 or oldCompleted and oldCompleted(id) end
    settingsByKey.accessManager.callback()
    manager.search:SetText("99991")
    manager.search.scripts.OnTextChanged()
    equal(manager.rows[1].entry.questID, 99991)
    equal(manager.rows[2]:IsShown(), false)
    manager.search:SetText("")
    manager.search.scripts.OnTextChanged()
    manager.filter:Click()
    equal(manager.filterMode, "current")
    equal(manager.rows[1].entry.questID, 1002)
    equal(manager.rows[2]:IsShown(), false)
    manager.filter:Click()
    equal(manager.filterMode, "completed")
    equal(manager.rows[1].entry.questID, 99991)
    manager.filter:Click()
    manager.rows[1].remove:Click()
    flush()
    api.IsQuestFlaggedCompleted = oldCompleted

    -- The actual taxi state freezes the current target, then restores normal UI/ranking.
    env.LibQuestieDB.Npc.spawns = function() return { [100] = { {68, 50} } } end
    env.ForeverQuestNavigator_HandleBinding("hold")
    flush()
    env.ForeverQuestNavigator_HandleBinding("hold")
    flush()
    playerX = 0.5
    fire("QUEST_LOG_UPDATE")
    flush()
    equal(activeCheckbox.quest.id, 1001)
    local onTaxi = false
    env.UnitOnTaxi = function() return onTaxi end
    onTaxi = true
    fire("PLAYER_CONTROL_LOST")
    flush()
    equal(rowOne:IsShown(), false)
    equal(navigation.arrow:IsShown(), false)
    equal(navigation.status.text, "After landing: turn in the selected quest")
    settingsByKey.showDirectionArrow:SetValue(false)
    equal(navigation:IsShown(), false)
    local flightSummaryShown
    for _, label in ipairs(updatedContent.labels) do
        if label.text == "After landing: turn in the selected quest" and label:IsShown() then flightSummaryShown = true end
    end
    equal(flightSummaryShown, true)
    equal(env.ForeverQuestNavigatorDB.detailMode, "detailed")
    playerX = 0.7
    distanceTicker.tick()
    equal(activeCheckbox.quest.id, 1001)
    onTaxi = false
    fire("PLAYER_CONTROL_GAINED")
    flush()
    equal(activeCheckbox.quest.id, 1002)
    equal(rowOne:IsShown(), true)
    settingsByKey.showDirectionArrow:SetValue(true)
    fire("PLAYER_CONTROL_LOST")
    flush()
    equal(rowOne:IsShown(), true)

    objectives[1002] = { {text = "Patrol enemies: 8/10", type = "monster", numFulfilled = 8, numRequired = 10} }
    fire("QUEST_LOG_CRITERIA_UPDATE", 1002)
    flush()
    assert(title.text:find("Almost done", 1, true))
    assert(routeNote.text:find("2 enemies left", 1, true))
    local beforeNotes = title.text
    mainMapButton:Click("RightButton")
    MenuAction("Remember for later")
    equal(title.text, beforeNotes)
    assert(env.ForeverQuestNavigatorCharacterDB.questNotes[1002])
    settingsByKey.notepad.callback()
    local notepad = Window("Quest notepad")
    equal(notepad.rows[1].entry.id, 1002)
    notepad.rows[1].map:Click()
    equal(title.text, beforeNotes)
    notepad.rows[1].remove:Click()
    equal(env.ForeverQuestNavigatorCharacterDB.questNotes[1002], nil)
    equal(notepad.empty:IsShown(), true)

    equal(env.BINDING_NAME_FOREVERQUESTNAVIGATOR_MAP, "Open active FQN quest map")
    env.ForeverQuestNavigator_HandleBinding("map")
    equal(selectedQuest, 1002)
    env.ForeverQuestNavigator_HandleBinding("toggle")
    equal(updatedTracker:IsShown(), false)
    env.ForeverQuestNavigator_HandleBinding("toggle")
    equal(updatedTracker:IsShown(), true)

    env.ForeverQuestNavigatorDB.introSeen = nil
    fire("PLAYER_ENTERING_WORLD")
    flush()
    local introduction = Window("Quick introduction")
    equal(introduction:IsShown(), true)
    introduction.next:Click()
    equal(introduction.step, 2)
    introduction.skip:Click()
    equal(env.ForeverQuestNavigatorDB.introSeen, true)
    fire("PLAYER_ENTERING_WORLD")
    flush()
    equal(introduction:IsShown(), false)
    settingsByKey.introduction.callback()
    equal(introduction.step, 1)
    introduction.next:Click()
    introduction.next:Click()
    introduction.next:Click()
    equal(introduction:IsShown(), false)
    env.ForeverQuestNavigatorDB.introSeen = nil
    local previousCombat = env.InCombatLockdown
    env.InCombatLockdown = function() return true end
    fire("PLAYER_ENTERING_WORLD")
    flush()
    equal(introduction:IsShown(), false)
    env.InCombatLockdown = function() return false end
    fire("PLAYER_REGEN_ENABLED")
    flush()
    equal(introduction:IsShown(), true)
    introduction.skip:Click()
    env.InCombatLockdown = previousCombat
    updatedTracker:Hide()
    equal(questieTicker.cancelled, true)
    currentXP, sessionNow = 300, 190
    fire("PLAYER_XP_UPDATE", "player")
    sessionWindow.scripts.OnUpdate(sessionWindow, 1)
    equal(sessionWindow.cards[2].text, "200")
    equal(copy.edit.text, snapshot)
    env.SlashCmdList.FOREVERQUESTNAVIGATOR("session")
    assert(sessionWindow.copyText:find("Observed XP gained: 200", 1, true))
    fire("PLAYER_LOGOUT")
    near(env.ForeverQuestNavigatorCharacterDB.session.seconds, 90)
    env.SlashCmdList.FOREVERQUESTNAVIGATOR("debug")
    local diagnostic
    for _, frame in ipairs(frames) do if frame.edit then diagnostic = frame end end
    assert(diagnostic and diagnostic:IsShown())
    assert(diagnostic.edit.text:find("FQN diagnostic report", 1, true))
    diagnostic.edit.scripts.OnEscapePressed()
    equal(diagnostic:IsShown(), false)
    env.SlashCmdList.FOREVERQUESTNAVIGATOR("debug")
    equal(diagnostic:IsShown(), true)
    env.SlashCmdList.FOREVERQUESTNAVIGATOR("zones")
    local zoneWindow
    for _, frame in ipairs(frames) do
        if frame.heading and frame.heading.text == "Zone overview" then zoneWindow = frame end
    end
    assert(zoneWindow and zoneWindow:IsShown())
    zoneWindow.scripts.OnUpdate(zoneWindow, 1)
    equal(zoneWindow.rows[1]:IsShown(), true)
    local snapshot = reloadedAddon.GetNavigationSnapshot()
    assert(snapshot and snapshot.view and snapshot.activeQuestID == snapshot.view.quest.id)
    env.SlashCmdList.FOREVERQUESTNAVIGATOR("fixture")
    local fixtureDialog
    for _, frame in ipairs(frames) do
        if frame.edit and frame.edit.text and frame.edit.text:find('"schema":1', 1, true) then fixtureDialog = frame end
    end
    assert(fixtureDialog and fixtureDialog:IsShown())
    settingsByKey.highContrast:SetValue(true)
    flush()
    equal(reloadedAddon.UI.Theme.contrast, true)
    settingsByKey.highContrast:SetValue(false)
    flush()
    equal(reloadedAddon.UI.Theme.contrast, false)
    env.SlashCmdList.FOREVERQUESTNAVIGATOR("settings")
    local quick
    for _, frame in ipairs(frames) do if frame.heading and frame.heading.text == "FQN settings" then quick = frame end end
    assert(quick and quick:IsShown())
    equal(quick.rows[5]:IsShown(), true)
    quick.search:SetText("Quiet navigation")
    quick.search.scripts.OnTextChanged()
    equal(quick.rows[1].entry.key, "quietNavigation")
    equal(quick.rows[2]:IsShown(), false)
    quick.rows[1]:Click()
    equal(env.ForeverQuestNavigatorDB.quietNavigation, false)
    flush()
    quick.rows[1]:Click()
    equal(env.ForeverQuestNavigatorDB.quietNavigation, true)
    flush()
    quick.search:SetText("Tracker opacity")
    quick.search.scripts.OnTextChanged()
    local originalOpacity = env.ForeverQuestNavigatorDB.opacityPercent
    quick.rows[1].minus:Click()
    equal(env.ForeverQuestNavigatorDB.opacityPercent, math.max(0, originalOpacity - 5))
    settingsByKey.opacityPercent:SetValue(originalOpacity)
    quick.search:SetText("")
    quick.search.scripts.OnTextChanged()
    quick.advanced:Click()
    assert(quick.next.enabled)
    quick.planning:Click()
    local planning
    for _, frame in ipairs(frames) do if frame.heading and frame.heading.text == "Quest planning" then planning = frame end end
    assert(planning and planning:IsShown())
    planning.turnIns:Click()
    planning.scripts.OnUpdate(planning, 1)
    assert(planning.summary.text:find("turn-ins", 1, true))
    env.SlashCmdList.FOREVERQUESTNAVIGATOR("plan")
    equal(planning:IsShown(), true)
    local previousCombat = env.InCombatLockdown
    updatedTracker:Show()
    if #timers > 0 then flush() end
    local selectedBeforeCombat = reloadedAddon.GetNavigationSnapshot().activeQuestID
    env.InCombatLockdown = function() return true end
    fire("PLAYER_REGEN_DISABLED")
    flush()
    equal(reloadedAddon.GetNavigationSnapshot().activeQuestID, selectedBeforeCombat)
    equal(navigation.quiet, true)
    playerX = 0.5
    distanceTicker.tick()
    equal(reloadedAddon.GetNavigationSnapshot().activeQuestID, selectedBeforeCombat)
    local detailBeforeCombat = env.ForeverQuestNavigatorDB.detailMode
    env.InCombatLockdown = function() return false end
    fire("PLAYER_REGEN_ENABLED")
    flush()
    equal(navigation.quiet, false)
    equal(reloadedAddon.GetNavigationSnapshot().activeQuestID, 1001)
    equal(env.ForeverQuestNavigatorDB.detailMode, detailBeforeCombat)
    mainMapButton:Click("RightButton")
    MenuAction("Target unreachable — lower priority for 10 min")
    flush()
    equal(reloadedAddon.GetNavigationSnapshot().feedback[1001].kind, "blocked")
    equal(reloadedAddon.GetNavigationSnapshot().activeQuestID, 1002)
    equal(env.ForeverQuestNavigatorCharacterDB.skippedQuests[1001], nil)
    env.SlashCmdList.FOREVERQUESTNAVIGATOR("feedback")
    local feedbackManager = Window("Temporary feedback")
    equal(feedbackManager.rows[1].entry.id, 1001)
    assert(feedbackManager.rows[1].label.text:find("Target unreachable", 1, true))
    feedbackManager.rows[1].clear:Click()
    flush()
    equal(reloadedAddon.GetNavigationSnapshot().feedback[1001], nil)
    feedbackManager.scripts.OnUpdate(feedbackManager, 1)
    equal(feedbackManager.rows[1]:IsShown(), false)
    local beforeProfiles, beforeOpacity = env.ForeverQuestNavigatorCharacterDB.skippedQuests, env.ForeverQuestNavigatorDB.opacityPercent
    env.SlashCmdList.FOREVERQUESTNAVIGATOR("profiles")
    local profiles = Window("Appearance profiles")
    profiles.buttons[1]:Click()
    equal(env.ForeverQuestNavigatorDB.detailMode, detailBeforeCombat)
    equal(env.ForeverQuestNavigatorDB.opacityPercent, beforeOpacity)
    assert(profiles.preview.text:find("Changes before applying", 1, true))
    profiles.apply:Click()
    if #timers > 0 then flush() end
    equal(env.ForeverQuestNavigatorDB.detailMode, "compact")
    equal(env.ForeverQuestNavigatorCharacterDB.skippedQuests, beforeProfiles)
    profiles.buttons[2]:Click()
    profiles.apply:Click()
    if #timers > 0 then flush() end
    equal(env.ForeverQuestNavigatorDB.detailMode, "detailed")
    mainMapButton:Click()
    assert(env.WorldMapFrame.activePinCount >= 2)
    equal(marker.ordinal, 1) equal(marker.number.text, "1")
    equal(pinPool[2].ordinal, 2) equal(pinPool[2].number.text, "2")
    assert(marker.width > pinPool[2].width)
    settingsByKey.showRouteMarkers:SetValue(false)
    equal(env.WorldMapFrame.activePinCount, 1) equal(marker.ordinal, nil)
    settingsByKey.showRouteMarkers:SetValue(true)
    assert(env.WorldMapFrame.activePinCount >= 2)
    pinPool[2]:OnClick("RightButton")
    equal(env.WorldMapFrame.activePinCount, 0)
    mainMapButton:Click("RightButton")
    local feedbackGroup, diagnosticGroup
    for _, entry in ipairs(historyMenu.entries) do
        assert(entry.label ~= "Report an unsuitable target position")
        if entry.label == "Recommendation feedback" then feedbackGroup = entry end
        if entry.label == "Diagnostics" then diagnosticGroup = entry end
    end
    assert(feedbackGroup and #feedbackGroup.entries >= 4)
    assert(diagnosticGroup and #diagnosticGroup.entries == 1)
    local originalObjectives = reloadedAddon.QuestieIntegration.GetObjectiveMarkers
    reloadedAddon.QuestieIntegration.GetObjectiveMarkers = function()
        return {[1002] = {{mapID = 10, x = .68, y = .5, objectiveIndex = 1}, {mapID = 10, x = .95, y = .5, objectiveIndex = 1}}}
    end
    fire("QUEST_LOG_UPDATE") flush()
    rowOne:Click("RightButton")
    MenuAction("Try another known area for this objective")
    flush()
    local switched = reloadedAddon.GetNavigationSnapshot()
    equal(switched.activeQuestID, 1002) equal(switched.objectiveLock.index, 1)
    near(switched.measurements[1002].marker.x, .95)
    equal(env.ForeverQuestNavigatorCharacterDB.skippedQuests[1002], nil)
    mainMapButton:Click("RightButton")
    MenuAction("Allow avoided objective areas again")
    flush()
    near(reloadedAddon.GetNavigationSnapshot().measurements[1002].marker.x, .68)
    mainMapButton:Click("RightButton")
    MenuAction(reloadedAddon.L.ClearActiveQuest)
    flush()
    equal(reloadedAddon.GetNavigationSnapshot().view.manual, false)
    do (function()
        local function Window(title)
            for _, frame in ipairs(frames) do if frame.heading and frame.heading.text == title then return frame end end
            error("Missing window " .. title)
        end
        env.SlashCmdList.FOREVERQUESTNAVIGATOR("share")
        local transfer = Window("Export / import appearance")
        local opacity = env.ForeverQuestNavigatorDB.opacityPercent
        transfer.input:SetText("FQN-DISPLAY-1\nopacityPercent=15")
        transfer.inspect:Click()
        equal(env.ForeverQuestNavigatorDB.opacityPercent, opacity)
        equal(transfer.apply.enabled, true)
        transfer.apply:Click()
        equal(env.ForeverQuestNavigatorDB.opacityPercent, 15)
        reloadedAddon.UndoLastChange()
        equal(env.ForeverQuestNavigatorDB.opacityPercent, opacity)
        env.SlashCmdList.FOREVERQUESTNAVIGATOR("detour")
        local detour = Window("Temporary stop")
        local selected = reloadedAddon.GetNavigationSnapshot().activeQuestID
        local px = playerX
        detour.inputs[1]:SetText(tostring(currentMapID))
        detour.inputs[2]:SetText(tostring((px + .1) * 100))
        detour.inputs[3]:SetText("50")
        detour.inputs[4]:SetText("Bridge stop")
        detour.start:Click()
        equal(detour.status.text, "Temporary stop active") flush()
        equal(reloadedAddon.GetNavigationSnapshot().activeQuestID, selected)
        detour.start:Click() flush()
        playerX = px + .1
        distanceTicker.tick()
        equal(detour.actions.active(), false) flush()
        playerX = px
        detour.map:Click()
        detour.cancel:Click() flush()
        equal(detour.status.text, "Quest navigation resumed.")
        equal(reloadedAddon.GetNavigationSnapshot().activeQuestID, selected)
    end)() end
    reloadedAddon.QuestieIntegration.GetObjectiveMarkers = originalObjectives
    local originalEntries, originalCapacity = api.GetNumQuestLogEntries, api.GetMaxNumQuestsCanAccept
    api.GetNumQuestLogEntries = function() return originalEntries(), 2 end
    api.GetMaxNumQuestsCanAccept = function() return 2 end
    fire("QUEST_LOG_UPDATE") flush()
    equal(reloadedAddon.GetNavigationSnapshot().capacity.full, true)
    assert(routeNote.text:find("Frees a quest-log slot", 1, true))
    mainMapButton:Click("RightButton")
    MenuAction("Inconvenient now — lower priority for 10 min")
    flush()
    env.SlashCmdList.FOREVERQUESTNAVIGATOR("feedback")
    assert(feedbackManager.rows[1]:IsShown())
    feedbackManager.all:Click()
    flush()
    feedbackManager.scripts.OnUpdate(feedbackManager, 1)
    equal(feedbackManager.all.enabled, false)
    equal(env.ForeverQuestNavigatorCharacterDB.skippedQuests, beforeProfiles)
    api.GetNumQuestLogEntries, api.GetMaxNumQuestsCanAccept = originalEntries, originalCapacity
    -- Lua 5.1 limits locals per function; keep the extra workflow in its own scope.
    do (function()
    planning:Hide()
    env.ForeverQuestNavigator_HandleBinding("plan")
    equal(planning:IsShown(), true)
    feedbackManager:Hide()
    env.ForeverQuestNavigator_HandleBinding("feedback")
    equal(feedbackManager:IsShown(), true)
    equal(env.BINDING_NAME_FOREVERQUESTNAVIGATOR_PLAN, "Open quest planning")
    equal(env.BINDING_NAME_FOREVERQUESTNAVIGATOR_CAMP, "Navigate to another known area for the active objective")
    reloadedAddon.QuestieIntegration.GetObjectiveMarkers = function()
        return {[1002] = {{mapID = 10, x = .68, y = .5, objectiveIndex = 1}, {mapID = 10, x = .95, y = .5, objectiveIndex = 1}}}
    end
    PinQuest(1002) flush()
    mainMapButton:Click("RightButton")
    MenuAction("Save my position as this objective's access point")
    flush()
    playerX = .58
    mainMapButton:Click("RightButton")
    MenuAction("Append my position as the next access waypoint")
    flush()
    local accessData = env.ForeverQuestNavigatorCharacterDB.accessPoints[1002][1]
    equal(#accessData.points, 2)
    mainMapButton:Click("RightButton")
    MenuAction("Navigate via access point again")
    flush()
    equal(reloadedAddon.GetNavigationSnapshot().measurements[1002].marker.accessStep, 1)
    settingsByKey.accessManager.callback()
    manager.search:SetText("Other patrol") manager.search.scripts.OnTextChanged()
    local routeRow
    for _, row in ipairs(manager.rows) do if row.entry and row.entry.questID == 1002 and row.entry.index == 1 then routeRow = row end end
    assert(routeRow) routeRow.route:Click()
    local routeEditor = Window("Access route waypoints")
    equal(routeEditor.rows[2]:IsShown(), true)
    routeEditor.rows[2].up:Click()
    near(routeEditor.rows[1].point.x, .58)
    flush()
    routeEditor.rows[2].remove:Click()
    equal(#accessData.points, 1)
    flush()
    mainMapButton:Click("RightButton")
    MenuAction("Remove this objective's access point")
    flush()
    env.ForeverQuestNavigator_HandleBinding("camp")
    flush()
    near(reloadedAddon.GetNavigationSnapshot().measurements[1002].marker.x, .95)
    equal(env.ForeverQuestNavigatorCharacterDB.skippedQuests[1002], nil)

    local oldCanShow = api.ShouldShowQuestRewards
    api.ShouldShowQuestRewards = function(id) return id == 1002 end
    local rewardCalls, rewardSelection = 0, selectedQuest
    env.GetQuestLogRewardMoney = function(id) equal(id, 1002) rewardCalls = rewardCalls + 1 return 12345 end
    env.GetNumQuestLogRewards = function(id) equal(id, 1002) return 1 end
    env.GetNumQuestLogChoices = function(id) equal(id, 1002) return 2 end
    env.GetQuestLogRewardInfo = function(index, id) equal(id, 1002) return "Quest potion", nil, 3, 1, true, 10 end
    env.GetQuestLogChoiceInfo = function(index, id) equal(id, 1002) return index == 2 and "Quest staff" or nil, nil, 1, 2, true, 10 + index end
    fire("QUEST_LOG_UPDATE") flush()
    mainMapButton.scripts.OnEnter(mainMapButton)
    assert(tooltip.lines[1]:find("1g 23s 45c", 1, true))
    assert(tooltip.lines[1]:find("Guaranteed items:", 1, true))
    assert(tooltip.lines[1]:find("Choose one reward:", 1, true))
    equal(selectedQuest, rewardSelection)
    equal(reloadedAddon.QuestRewards.HasPending(), true)
    local callsBefore = rewardCalls
    distanceTicker.tick()
    equal(rewardCalls, callsBefore)
    settingsByKey.showQuestRewards:SetValue(false) flush()
    equal(rewardCalls, callsBefore)
    settingsByKey.showQuestRewards:SetValue(true) flush()
    env.GetItemInfo = function(id) if id == 11 then return "Quest sword" end end
    fire("GET_ITEM_INFO_RECEIVED", 11, true) flush()
    equal(reloadedAddon.QuestRewards.HasPending(), false)
    mainMapButton.scripts.OnEnter(mainMapButton)
    assert(tooltip.lines[1]:find("Quest sword x1", 1, true))
    fire("GET_ITEM_INFO_RECEIVED", 15, true)
    equal(#timers, 0)
    equal(selectedQuest, rewardSelection)
    api.ShouldShowQuestRewards = oldCanShow
    do (function()
        local savedDetail = env.ForeverQuestNavigatorDB.detailMode
        profiles.buttons[1]:Click() profiles.apply:Click()
        if #timers > 0 then flush() end
        equal(env.ForeverQuestNavigatorDB.detailMode, "compact")
        env.SlashCmdList.FOREVERQUESTNAVIGATOR("undo")
        if #timers > 0 then flush() end
        equal(env.ForeverQuestNavigatorDB.detailMode, savedDetail)
        equal(env.ForeverQuestNavigatorCharacterDB.skippedQuests, beforeProfiles)

        mainMapButton:Click("RightButton") MenuAction("Save my position as this objective's access point") flush()
        playerX = .66
        mainMapButton:Click("RightButton") MenuAction("Append my position as the next access waypoint") flush()
        routeEditor:Refresh()
        equal(#env.ForeverQuestNavigatorCharacterDB.accessPoints[1002][1].points, 2)
        routeEditor.rows[2].remove:Click() flush()
        equal(#env.ForeverQuestNavigatorCharacterDB.accessPoints[1002][1].points, 1)
        env.SlashCmdList.FOREVERQUESTNAVIGATOR("undo") flush()
        equal(#env.ForeverQuestNavigatorCharacterDB.accessPoints[1002][1].points, 2)
        equal(routeEditor.rows[2]:IsShown(), true)

        mainMapButton:Click("RightButton") MenuAction("Too difficult — lower priority for 10 min") flush()
        env.SlashCmdList.FOREVERQUESTNAVIGATOR("feedback")
        feedbackManager.rows[1].clear:Click() flush()
        equal(reloadedAddon.GetNavigationSnapshot().feedback[1002], nil)
        env.SlashCmdList.FOREVERQUESTNAVIGATOR("undo") flush()
        equal(reloadedAddon.GetNavigationSnapshot().feedback[1002].kind, "hard")
        feedbackManager.rows[1].clear:Click() flush()
        local clockBefore = env.GetTime
        local now = clockBefore()
        env.GetTime = function() return now + 700 end
        equal(reloadedAddon.Undo:Undo(), false)
        equal(reloadedAddon.GetNavigationSnapshot().feedback[1002], nil)
        env.GetTime = clockBefore
        env.SlashCmdList.FOREVERQUESTNAVIGATOR("history")
        local history = Window("Changes and undo")
        assert(history:IsShown()) history.discard:Click()

        local oldLookup, oldCount, oldItemName, oldChains = reloadedAddon.QuestieIntegration.GetObjectiveItemID,
            env.GetItemCount, env.GetItemInfo, reloadedAddon.QuestieRoutes.GetChains
        reloadedAddon.QuestieIntegration.GetObjectiveItemID = function(id, index) if index == 1 then return 77 end end
        env.GetItemCount = function(id, bank) equal(id, 77) equal(bank, false) return 5 end
        env.GetItemInfo = function(id) if id == 77 then return "Shared supply" elseif id == 11 then return "Quest sword" end end
        objectives[1001] = {{text = "Supply A", type = "item", numRequired = 10, numFulfilled = 5}}
        objectives[1002] = {{text = "Supply B", type = "item", numRequired = 8, numFulfilled = 5}}
        reloadedAddon.QuestieRoutes.GetChains = function()
            return {[1002] = {finisher = {mapID = 10, x = .5, y = .5}, followUps = {"Next patrol"},
                stops = {{mapID = 10, x = .51, y = .5, action = "objective", depth = 1, questID = 2100, title = "Next patrol"}}}}
        end
        fire("QUEST_LOG_UPDATE") flush()
        local shared = reloadedAddon.GetNavigationSnapshot().sharedItems
        equal(#shared, 1) equal(shared[1].required, 18) equal(shared[1].remaining, 13)
        env.SlashCmdList.FOREVERQUESTNAVIGATOR("plan") planning.items:Click()
        assert(planning.rows[1]:GetText():find("Shared supply", 1, true))
        assert(planning.rows[1]:GetText():find("13", 1, true))
        planning.chains:Click()
        assert(planning.rows[2].detail:find("Next patrol", 1, true))
        assert(planning.rows[1].detail:find(reloadedAddon.L.UnknownFollowUps, 1, true))

        local oldLevel = env.UnitLevel
        quests[2].level = 14
        env.UnitLevel = function() return 12 end
        fire("PLAYER_LEVEL_UP", 12) flush()
        local levelButton
        for _, button in ipairs(frames) do if button.text == "One quest now fits your level better — click" then levelButton = button end end
        env.SlashCmdList.FOREVERQUESTNAVIGATOR("levels")
        assert(levelButton and levelButton:IsShown(), Window("Quests after your level-up").edit.text)
        levelButton:Click()
        local levelReport = Window("Quests after your level-up")
        assert(levelReport.edit.text:find("Other patrol", 1, true))

        local compute, computations = reloadedAddon.NavigationController.Compute, 0
        reloadedAddon.NavigationController.Compute = function(input) computations = computations + 1 return compute(input) end
        fire("QUEST_LOG_UPDATE") flush()
        local beforeIdle = computations
        distanceTicker.tick() distanceTicker.tick()
        equal(computations, beforeIdle)
        playerX = playerX + .0001 distanceTicker.tick()
        equal(computations, beforeIdle)
        playerX = playerX + .01 distanceTicker.tick()
        assert(computations > beforeIdle)
        local beforeProgress = computations
        objectives[1002][1].numFulfilled = 6
        fire("QUEST_LOG_CRITERIA_UPDATE", 1002) flush()
        assert(computations > beforeProgress)
        mainMapButton:Click("RightButton") MenuAction("Too difficult — lower priority for 10 min") flush()
        local beforeExpiry = computations
        local beforeClock, beforeNow = env.GetTime, env.GetTime()
        env.GetTime = function() return beforeNow + 700 end
        distanceTicker.tick()
        assert(computations > beforeExpiry)
        equal(reloadedAddon.GetNavigationSnapshot().feedback[1002], nil)
        env.GetTime = beforeClock
        reloadedAddon.NavigationController.Compute = compute
        settingsByKey.fontPercent:SetValue(140)
        equal(rowOne.reward:IsShown(), false)
        settingsByKey.adaptiveLayout:SetValue(false) flush()
        assert(rowOne:GetHeight() > 36)
        equal(env.ForeverQuestNavigatorDB.detailMode, "detailed")
        settingsByKey.fontPercent:SetValue(100)
        settingsByKey.adaptiveLayout:SetValue(true) flush()
        env.UnitLevel, env.GetItemCount, env.GetItemInfo = oldLevel, oldCount, oldItemName
        reloadedAddon.QuestieIntegration.GetObjectiveItemID, reloadedAddon.QuestieRoutes.GetChains = oldLookup, oldChains
    end)() end
    do (function()
        local function Window(name)
            for index = #frames, 1, -1 do
                local frame = frames[index]
                if frame.heading and frame.heading.text == name then return frame end
            end
            error("Missing demo window " .. name)
        end
        local beforeSettings = reloadedAddon.UndoHistory.Copy(env.ForeverQuestNavigatorDB)
        local beforeCharacter = reloadedAddon.UndoHistory.Copy(env.ForeverQuestNavigatorCharacterDB)
        local data = {mapID = 10, level = 14, width = 1000, height = 500, zone = {name = "Demo DB zone"}, records = {}}
        for id = 1, 7 do
            data.records[id] = {id = id, title = "DB Demo Quest " .. id, level = 14, xp = 900,
                starter = {mapID = 10, x = .4, y = .4}, finisher = {mapID = 10, x = .4, y = .4},
                goals = {{index = 1, text = "DB objective " .. id}},
                markers = {{mapID = 10, x = .4 + id * .01, y = .4, objectiveIndex = 1, objective = true}}}
        end
        local loader = reloadedAddon.DemoData.Load
        reloadedAddon.DemoData.Load = function() return data end
        env.SlashCmdList.FOREVERQUESTNAVIGATOR("demo")
        equal(reloadedAddon.DemoMode.IsActive(), true) equal(updatedTracker:IsShown(), false)
        local controls = Window("Screenshot demo")
        equal(controls:IsShown(), true)
        controls.plan:Click()
        local planningDemo = Window("Quest planning")
        assert(planningDemo.demoBadge and planningDemo:IsShown())
        controls.scene:Click()
        equal(planningDemo.getModel().scene, "turnins")
        controls.map:Click()
        equal(openedMap, 10)
        controls.shot:Click()
        equal(controls:IsShown(), false)
        env.SlashCmdList.FOREVERQUESTNAVIGATOR("demo")
        equal(controls:IsShown(), true)
        fire("QUEST_LOG_UPDATE") flush()
        equal(updatedTracker:IsShown(), false)
        env.SlashCmdList.FOREVERQUESTNAVIGATOR("demo off") flush()
        equal(reloadedAddon.DemoMode.IsActive(), false) equal(updatedTracker:IsShown(), true)
        equal(planningDemo:IsShown(), false)
        assert(reloadedAddon.UndoHistory.Same(beforeSettings, env.ForeverQuestNavigatorDB))
        assert(reloadedAddon.UndoHistory.Same(beforeCharacter, env.ForeverQuestNavigatorCharacterDB))
        reloadedAddon.DemoData.Load = function() return nil, "Missing demo data" end
        env.SlashCmdList.FOREVERQUESTNAVIGATOR("demo")
        equal(reloadedAddon.DemoMode.IsActive(), false) equal(updatedTracker:IsShown(), true)
        reloadedAddon.DemoData.Load = loader
    end)() end
    reloadedAddon.QuestieIntegration.GetObjectiveMarkers = originalObjectives
    end)() end
    env.InCombatLockdown = previousCombat
end)

assert(loadfile("tests/new_features.lua"))()(test, addon, equal, near)
assert(loadfile("tests/planning_features.lua"))()(test, addon, equal, near)
assert(loadfile("tests/personalization_features.lua"))()(test, addon, equal, near)
assert(loadfile("tests/routes_rewards.lua"))()(test, addon, equal, near)
assert(loadfile("tests/usability_insights.lua"))()(test, addon, equal, near)
assert(loadfile("tests/release_features.lua"))()(test, addon, equal, near)
assert(loadfile("tests/demo_features.lua"))()(test, addon, equal, near)
assert(loadfile("tests/stability_features.lua"))()(test, addon, equal, near)
print(("%d tests passed (%s)."):format(testsPassed, _VERSION))
