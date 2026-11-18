return function(test, addon, equal, near)
    test("Display codes roundtrip only allowlisted appearance values", function()
        local source = {opacityPercent = 80, detailMode = "compact", showQuestXP = false,
            language = "deDE", screenArrowX = 123, skippedQuests = {[1] = true}, notes = "private"}
        local code = addon.DisplayTransfer.Export(source)
        assert(not code:find("private") and not code:find("language") and not code:find("screenArrow"))
        local values = addon.DisplayTransfer.Parse(code)
        equal(values.opacityPercent, 80) equal(values.showQuestXP, false) equal(values.detailMode, "compact")
        for _, bad in ipairs({"FQN-DISPLAY-1\nopacityPercent=101", "FQN-DISPLAY-1\nopacityPercent=-1",
            "FQN-DISPLAY-1\nopacityPercent=10\nopacityPercent=20", "FQN-DISPLAY-1\nlanguage=enUS",
            "FQN-DISPLAY-1\nshowQuestXP=1", "FQN-DISPLAY-1\ndetailMode=other",
            "FQN-DISPLAY-1\nshowQuestXP=loadstring()", string.rep("x", 4097)}) do
            equal(addon.DisplayTransfer.Parse(bad), nil)
        end
    end)
    test("Import previews do not mutate settings and reject stale changes", function()
        local settings, catalog = {opacityPercent = 80, showQuestXP = true}, {}
        for _, key in ipairs({"opacityPercent", "showQuestXP"}) do
            local name = key
            catalog[#catalog + 1] = {key = name, name = name, control = {SetValue = function(_, v) settings[name] = v end}}
        end
        local changes = addon.DisplayTransfer.Changes({opacityPercent = 20, showQuestXP = false}, settings, catalog)
        equal(settings.opacityPercent, 80)
        settings.opacityPercent = 30
        equal(addon.DisplayTransfer.Apply(changes, settings), false) equal(settings.showQuestXP, true)
        settings.opacityPercent = 80
        local undo = addon.UndoHistory.New()
        equal(addon.DisplayTransfer.Apply(changes, settings, undo), true)
        equal(settings.opacityPercent, 20) equal(settings.showQuestXP, false)
        equal(undo:Undo(), true) equal(settings.opacityPercent, 80) equal(settings.showQuestXP, true)
    end)
    test("Quest action hints require a native association and an owned item", function()
        local api = {GetLogIndexForQuestID = function(id) equal(id, 5) return 3 end, IsComplete = function() return false end}
        local function special(index) equal(index, 3) return "|Hitem:123:0|h[Signal]|h", nil, nil, false end
        local hint = addon.QuestItemHints.Read(api, 5, special, function() return 1 end)
        equal(hint.id, 123) equal(hint.name, "Signal")
        equal(addon.QuestItemHints.Read(api, 5, special, function() return 0 end), nil)
        equal(addon.QuestItemHints.Read(api, 5, nil, function() return 1 end), nil)
        api.IsComplete = function() return true end
        equal(addon.QuestItemHints.Read(api, 5, special, function() return 1 end), nil)
    end)
    test("Follow-up reserve uses one sequential slot and preserves unknown capacity", function()
        local chains = {[1] = {stops = {{action = "accept"}, {action = "accept"}}}}
        local capacity = {used = 24, maximum = 25, free = 1, full = false}
        local result = addon.QuestCapacity.WithReserve(capacity, chains)
        equal(result.reserve, 1) equal(result.reserveNeeded, true) equal(capacity.reserve, nil)
        equal(addon.QuestCapacity.WithReserve(capacity, {}).reserveNeeded, false)
        equal(addon.QuestCapacity.WithReserve(nil, chains), nil)
        capacity.free = 2
        equal(addon.QuestCapacity.WithReserve(capacity, chains).reserveNeeded, false)
    end)
    test("Access notes follow reordered points and do not reset progress", function()
        local first, second = {mapID = 10, x = .2, y = .1}, {mapID = 10, x = .3, y = .1}
        local entry = {points = {first, second}, point = first, revision = 4}
        local saved = {[1] = {[1] = entry}}
        equal(addon.TravelSupport.SetAccessNote(saved, 1, 1, 2, "  Bridge  "), true)
        equal(second.note, "Bridge") equal(entry.revision, 4)
        addon.TravelSupport.MoveAccessStep(saved, 1, 1, 2, -1)
        equal(entry.points[1].note, "Bridge")
        equal(addon.TravelSupport.SetAccessNote(saved, 1, 1, 3, "invalid"), false)
        equal(addon.TravelSupport.SetAccessNote(saved, 1, 1, 1, string.rep("x", 241)), false)
    end)
    test("Temporary stops validate coordinates and measure without changing saved routes", function()
        local map = {GetMapWorldSize = function() return 1000, 1000 end,
            GetPlayerMapPosition = function() return {x = .1, y = .1} end}
        local point = addon.TemporaryDetour.New(10, .2, .1, " Vendor ")
        equal(point.name, "Vendor") near(addon.TemporaryDetour.Measure(map, point).yards, 100)
        equal(addon.TemporaryDetour.New(10, 1.2, .1), nil)
        equal(addon.TemporaryDetour.New(10.5, .2, .1), nil)
        equal(addon.TemporaryDetour.New(10, 0/0, .1), nil)
        equal(addon.TemporaryDetour.Measure(map, nil), nil)
    end)
end
