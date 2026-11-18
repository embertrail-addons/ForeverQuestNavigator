return function(test, addon, equal, near)
    test("Undo restores a copied value, protects newer edits and bounds history", function()
        local history, data = addon.UndoHistory.New(2), {points = {{x = 1}}}
        local before = addon.UndoHistory.Copy(data)
        data = {points = {{x = 2}}}
        history:Capture("points", function() return data end, function(value) data = value end, before, data)
        before.points[1].x = 999
        data.points[1].x = 3
        equal(history:Undo(), false) equal(data.points[1].x, 3)
        data.points[1].x = 2
        equal(history:Undo(), true) equal(data.points[1].x, 1)
        history:Push("one", function() return true end)
        history:Push("two", function() return true end)
        history:Push("three", function() return true end)
        equal(#history.entries, 2) equal(history.entries[1].label, "two")
        history:Discard() equal(#history.entries, 1)
    end)
    test("Undoing a profile restores only changed display values", function()
        local settings = {detailMode = "detailed", showQuestXP = true, language = "deDE"}
        local catalog, history = {}, addon.UndoHistory.New()
        for _, key in ipairs({"detailMode", "showQuestXP"}) do
            local name = key
            catalog[#catalog + 1] = {key = key, control = {SetValue = function(_, value) settings[name] = value end}}
        end
        addon.AppearanceProfiles.Apply("minimal", settings, catalog, history)
        equal(settings.detailMode, "compact") equal(#history.entries, 1)
        settings.language = "enUS"
        equal(history:Undo(), true) equal(settings.detailMode, "detailed") equal(settings.language, "enUS")
        addon.AppearanceProfiles.Apply("minimal", settings, catalog, history)
        settings.showQuestXP = true
        equal(history:Undo(), false) equal(settings.detailMode, "compact")
    end)
    test("Shared item requirements subtract bag inventory once across distinct quests", function()
        local quests = {{id = 1}, {id = 2}, {id = 1}}
        local result = addon.QuestInsights.SharedItems(quests, function(id)
            return {{type = "item", numRequired = id == 1 and 10 or 8, numFulfilled = 5}}
        end, function() return 77 end, function(id, bank) equal(id, 77) equal(bank, false) return 5 end,
            function() return "Shared supply" end)
        equal(#result, 1) equal(result[1].required, 18) equal(result[1].remaining, 13)
        equal(#result[1].quests, 2) equal(result[1].owned, 5)
    end)
    test("Ambiguous item objectives and unknown inventory do not produce confident remaining counts", function()
        local quests = {{id = 1}, {id = 2}}
        local result = addon.QuestInsights.SharedItems(quests, function() return {{type = "item", numRequired = 4}} end,
            function() return 77 end)
        equal(#result, 1) equal(result[1].remaining, nil) equal(result[1].required, 8)
        result = addon.QuestInsights.SharedItems(quests, function() return {{type = "item", numRequired = 4}, {type = "item", numRequired = 4}} end,
            function() return 77 end)
        equal(#result, 0)
        result = addon.QuestInsights.SharedItems(quests, function() return {{type = "item", numRequired = 4}} end,
            function() return nil end)
        equal(#result, 0)
    end)
    test("Quest chain explanation keeps unsupported continuations unknown and shows shared target locations", function()
        local api = {GetMapWorldSize = function() return 1000, 1000 end,
            GetMapInfo = function() return {name = "Zone", mapType = 3} end}
        local quests = {{id = 1, title = "Current"}, {id = 2, title = "Other"}}
        local chains = {[1] = {followUps = {"Follow-up"}, stops = {{mapID = 10, x = .5, y = .5,
            action = "objective", depth = 1, questID = 3, title = "Follow-up"}}}}
        local entries = addon.QuestInsights.Chains(api, {Zone = 3}, quests, chains,
            {[2] = {marker = {mapID = 10, x = .51, y = .5}}})
        equal(entries[1].known, true) equal(entries[1].stop.quest.id, 3)
        assert(entries[1].detail:find("-> Follow-up", 1, true))
        assert(entries[1].detail:find("Within 40 yd of: Other", 1, true))
        equal(entries[2].known, false) assert(entries[2].detail:find(addon.L.UnknownFollowUps, 1, true))
    end)
    test("Level-up hints report only known improvements, excluding turn-ins and fading XP quests", function()
        local entries = addon.QuestInsights.LevelChanges({{id = 1, level = 13}, {id = 2, level = 11},
            {id = 3, level = 10}, {id = 4, level = 13, readyToTurnIn = true}, {id = 5}}, 10, 11)
        equal(#entries, 2) equal(entries[1].quest.id, 1) equal(entries[1].before, "red") equal(entries[1].after, "orange")
        equal(entries[2].quest.id, 2) equal(entries[2].after, "yellow")
        equal(#addon.QuestInsights.LevelChanges({{id = 1}}, nil, 11), 0)
    end)
    test("Stationary navigation skips work but movement, phase, missing position and expiry force updates", function()
        local current = {mapID = 10, x = 100, y = 100, width = 1000, height = 1000}
        local previous = {point = addon.UndoHistory.Copy(current), phase = "walk"}
        equal(addon.MovementGate.ShouldUpdate(previous, current, "walk", false, nil, 0), false)
        current.x = 102
        equal(addon.MovementGate.ShouldUpdate(previous, current, "walk", false, nil, 0), false)
        equal(addon.MovementGate.ShouldUpdate(previous, current, "walk", true, nil, 0), true)
        current.x = 103
        equal(addon.MovementGate.ShouldUpdate(previous, current, "walk", false, nil, 0), true)
        current.x = 100
        equal(addon.MovementGate.ShouldUpdate(previous, current, "taxi", false, nil, 0), true)
        equal(addon.MovementGate.ShouldUpdate(previous, nil, "walk", false, nil, 0), true)
        previous.deadline = 10
        equal(addon.MovementGate.ShouldUpdate(previous, current, "walk", false, nil, 10), true)
    end)
    test("Compact distances retain the full value when compact mode is off", function()
        equal(addon.UI.FormatDistance({yards = 5209}, true), "~5.2k yd")
        equal(addon.UI.FormatDistance({yards = 5209}, false), "~5209 yd")
        equal(addon.UI.FormatDistance({yards = 45}, true), "~45 yd")
    end)
end
