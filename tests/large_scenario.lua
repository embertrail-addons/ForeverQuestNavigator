-- Full quest log (25 quests in 5 zones): behaviour and time budgets for the hot paths.
-- Budgets are generous averages so CI machines do not fail by chance.
return function(test, addon, equal)
    local function FullLog()
        local quests, measurements = {}, {}
        for index = 1, 25 do
            local zone = (index - 1) % 5 + 1
            quests[index] = {id = 1000 + index, title = "Quest " .. index, level = 28 + index % 8,
                readyToTurnIn = index % 4 == 0, xp = 900 + index * 40}
            if index % 6 ~= 0 then
                measurements[quests[index].id] = {yards = 80 * index + zone * 13, marker = {mapID = 1400 + zone, x = .1 * zone, y = .02 * index}}
            end
        end
        return quests, measurements
    end
    local function Average(runs, fn)
        local started = os.clock()
        for _ = 1, runs do fn() end
        return (os.clock() - started) * 1000 / runs
    end

    test("A full quest log keeps every quest and orders measured ones consistently", function()
        local quests, measurements = FullLog()
        local ranked, known = addon.QuestPrioritizer.RankByDistance(quests, measurements, nil, 32)
        equal(#ranked, 25)
        local measured = 0
        for _ in pairs(measurements) do measured = measured + 1 end
        equal(#known, measured)
        -- Within the full ranking, measured quests keep the order of the distance ranking.
        local position = {}
        for index, quest in ipairs(ranked) do position[quest.id] = index end
        for index = 2, #known do
            local a, b = known[index - 1], known[index]
            if position[a.id] > position[b.id] then
                -- only allowed across priority tiers, where the tier order wins
                assert(addon.QuestPrioritizer.IsLowPriority(a, 32) ~= addon.QuestPrioritizer.IsLowPriority(b, 32) or a.readyToTurnIn ~= b.readyToTurnIn)
            end
        end
    end)

    test("Hot paths stay within time budgets for a full quest log", function()
        local quests, measurements = FullLog()
        local previous = addon.QuestPrioritizer.RankByDistance(quests, measurements, nil, 32)
        local rank = Average(200, function() addon.QuestPrioritizer.RankByDistance(quests, measurements, previous, 32) end)
        assert(rank < 5, ("Ranking took %.2f ms"):format(rank))
        local api = {GetMapInfo = function(id) return {name = "Zone " .. id, mapType = 3} end}
        local snapshot = {playerLevel = 32, measurements = measurements, objectiveDistances = {}}
        local zones
        local overview = Average(100, function() zones = addon.BuildZoneOverview(api, {Zone = 3}, quests, snapshot) end)
        assert(#zones >= 5) assert(overview < 10, ("Zone overview took %.2f ms"):format(overview))
        local forecast = Average(500, function()
            addon.LevelForecast.FromQuests(quests, measurements, function(q) return q.xp end, 4000)
        end)
        assert(forecast < 2, ("Level forecast took %.2f ms"):format(forecast))
        local Sync = addon.GroupSync
        local encode = Average(500, function()
            Sync.Decode(Sync.Encode(Sync.Collect(quests, {GetQuestObjectives = function() return {{finished = true}, {}} end}, 1001)))
        end)
        assert(encode < 2, ("Group sync encoding took %.2f ms"):format(encode))
    end)
    test("Camp choice stays fast with city-sized spawn sets and matches the plain grouping", function()
        -- Reported: Undercity spent up to 300 ms per planning pass choosing camps.
        local player = {x = .5, y = .5}
        local api = {GetMapWorldSize = function() return 1000, 1000 end, GetPlayerMapPosition = function() return player end}
        local function Points(count, withWorld)
            local points, seed = {}, 7
            for index = 1, count do
                seed = (seed * 1103515245 + 12345) % 2147483648
                local x = (seed % 10000) / 10000
                seed = (seed * 1103515245 + 12345) % 2147483648
                local y = (seed % 10000) / 10000
                local point = {mapID = 10, x = x, y = y, objectiveIndex = index % 2 + 1}
                -- World position as the client would report it (yards); without it the plain path runs.
                point.world = withWorld and {x = x * 1000, y = y * 1000, continent = 1} or false
                points[index] = point
            end
            return points
        end
        local quest = {id = 1, level = 30}
        local function Build(points)
            local target = points[1]
            return addon.CampChoices.Build(api, quest, {marker = target, yards = 50}, points, {quest}, {}, nil, nil, 30)
        end
        -- Same camps with and without the grid (small set).
        local gridded, plain = Build(Points(400, true)), Build(Points(400, false))
        equal(#gridded, #plain)
        for index = 1, #plain do equal(gridded[index].target.x, plain[index].target.x) end
        assert(#gridded <= addon.CampChoices.NEAREST, "only the nearest camps are measured")
        -- City-sized set: first pass groups, later passes reuse the camps.
        local city = Points(4000, true)
        local first = Average(1, function() Build(city) end)
        local later = Average(20, function() Build(city) end)
        assert(first < 400, ("Grouping 4000 spawn points took %.1f ms"):format(first))
        assert(later < 40, ("A later camp choice took %.1f ms"):format(later))
        -- A quest-log update rebuilds the list around the same markers: no regrouping.
        local groupings = addon.CampChoices.groupings
        local copy = {}
        for index, point in ipairs(city) do copy[index] = point end
        Build(copy)
        equal(addon.CampChoices.groupings, groupings, "same markers in a new list reuse the camps")
        copy[#copy + 1] = {mapID = 10, x = .5, y = .5, objectiveIndex = 1, world = {x = 500, y = 500, continent = 1}}
        Build(copy)
        assert(addon.CampChoices.groupings > groupings, "a changed marker set is grouped again")
    end)
    test("Reloaded markers at the same places reuse their world positions", function()
        local previous = CreateVector2D
        CreateVector2D = function(x, y) return {x = x, y = y} end
        local calls = 0
        local api = {GetWorldPosFromMapPos = function(_, position) calls = calls + 1 return 1, {x = position.x * 1000, y = position.y * 1000} end}
        addon.QuestLocation.ClearWorldCache()
        local first = addon.QuestLocation.GetMarkerWorldPosition(api, {mapID = 10, x = .25, y = .5})
        local again = addon.QuestLocation.GetMarkerWorldPosition(api, {mapID = 10, x = .25, y = .5})
        equal(calls, 1, "a new marker object at the same place is not converted again")
        equal(again.x, first.x)
        addon.QuestLocation.GetMarkerWorldPosition(api, {mapID = 11, x = .25, y = .5})
        equal(calls, 2, "another map is converted")
        addon.QuestLocation.ClearWorldCache()
        CreateVector2D = previous
    end)
    test("Quest value on a full log is cheap and repeats no distance work while targets stay the same", function()
        local quests, measurements = FullLog()
        for _, quest in ipairs(quests) do quest.progress = {remaining = 4, monsters = 2, items = 2, other = 0} end
        local calls = 0
        local function Distance(a, b) calls = calls + 1 return math.abs(a.x - b.x) * 1000 + math.abs(a.y - b.y) * 1000 end
        local context = {quests = quests, measurements = measurements, model = addon.QuestValue.Model({}), distance = Distance,
            xp = function(q) return q.xp end, playerMap = 1401}
        addon.QuestValue.Adjustments(context)
        assert(calls > 0 and calls <= 56, ("look-ahead needs at most 8 x 7 distances, took %d"):format(calls))
        calls = 0
        local value = Average(200, function() addon.QuestValue.Adjustments(context) end)
        equal(calls, 0, "unchanged markers reuse their distances")
        assert(value < 3, ("Quest value took %.2f ms"):format(value))
        local relations = {}
        for index, quest in ipairs(quests) do relations[quest.id] = {{objectiveIndex = 1, npcID = index % 7}, {objectiveIndex = 2, npcID = 50 + index}} end
        local shared = Average(200, function() addon.TargetMarks.SharedCounts(relations, quests) end)
        assert(shared < 3, ("Shared mob counts took %.2f ms"):format(shared))
    end)
end
