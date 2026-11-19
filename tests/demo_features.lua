return function(test, addon, equal, near)
    local function Fixture()
        local row = {name = {}, questLevel = {}, requiredLevel = {}, startedBy = {}, finishedBy = {}, objectives = {}, objectivesText = {}}
        local npc = {name = {}, spawns = {}}
        for id = 1, 7 do
            row.name[id], row.questLevel[id], row.requiredLevel[id] = "DB Quest " .. id, 14, 10
            row.startedBy[id], row.finishedBy[id] = {{100}}, {{100}}
            row.objectives[id], row.objectivesText[id] = {{{id}, {id + 10}}}, {"Real DB objective " .. id}
            npc.name[id], npc.name[id + 10] = "DB mob " .. id, "DB second mob " .. id
            npc.spawns[id], npc.spawns[id + 10] = {[1] = {{40 + id, 50}}}, {[1] = {{42 + id, 52}}}
        end
        npc.spawns[100] = {[1] = {{50, 50}}}
        local function Entity(fields)
            local entity = {}
            for key, values in pairs(fields) do local data = values entity[key] = function(id) return data[id] end end
            return entity
        end
        local db = {Quest = Entity(row), Npc = Entity(npc), Object = {}, Item = {}}
        local zones = {GetUiMapIdByAreaId = function() return 10 end}
        local maps = {GetMapWorldSize = function() return 10000, 6000 end, GetMapInfo = function() return {name = "DB zone"} end}
        local preset = {key = "fixture", level = 14, ids = {1, 2, 3, 4, 5, 6, 7}}
        local xp = {[1] = {14, 1000}, [2] = {14, 900}, [3] = {14, 800}, [4] = {14, 700}}
        return db, zones, maps, preset, xp, row, npc
    end
    test("Demo uses database names, positions and base XP without mutating source tables", function()
        local db, zones, maps, preset, xp, row, npc = Fixture()
        local before = addon.UndoHistory.Copy({row, npc, xp})
        local data = addon.DemoData.Read(db, zones, nil, maps, preset, xp)
        equal(#data.records, 7) equal(data.records[1].title, "DB Quest 1")
        equal(#data.records[1].goals, 2) near(data.records[1].markers[1].x, .41)
        equal(data.records[1].xp, 1000)
        local model = addon.DemoData.Build(data, "objectives")
        equal(#model.view.alternatives, 3) equal(#model.offers, 3) equal(#model.view.targets, 2)
        equal(model.view.quest.readyToTurnIn, false)
        local repeated = addon.DemoData.Build(data, "objectives")
        equal(model.activeQuestID, repeated.activeQuestID)
        near(model.activeMeasurement.yards, repeated.activeMeasurement.yards)
        assert(addon.UndoHistory.Same(before, {row, npc, xp}))
    end)
    test("Demo turn-in scenes never use real-character reward APIs", function()
        local db, zones, maps, preset, xp = Fixture()
        local data = addon.DemoData.Read(db, zones, nil, maps, preset, xp)
        local native = addon.QuestLog.GetTurnInXP
        addon.QuestLog.GetTurnInXP = function() error("Live reward API must not be used") end
        local model = addon.DemoData.Build(data, "turnins")
        addon.QuestLog.GetTurnInXP = native
        equal(#model.turnInTour.stops, 4)
        equal(model.turnInTour.xp, 3400) equal(model.turnInTour.levelUpAt, 1)
        equal(model.view.quest.readyToTurnIn, true)
        equal(model.view.targets, nil)
    end)
    test("Demo rejects insufficient data instead of inventing quests or positions", function()
        local db, zones, maps, preset, xp = Fixture()
        db.Npc.spawns = function() return nil end
        equal(addon.DemoData.Read(db, zones, nil, maps, preset, xp), nil)
        equal(addon.DemoData.Read(nil, zones, nil, maps, preset, xp), nil)
        equal(addon.DemoData.Build({}, "invalid"), nil)
    end)
end
