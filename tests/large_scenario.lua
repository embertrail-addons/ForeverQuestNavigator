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
end
