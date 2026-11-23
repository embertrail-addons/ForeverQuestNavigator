return function(test, addon, equal)
    local limits = {DEFAULT_OPACITY = 80, DEFAULT_OFFER_RADIUS = 350, MAX_OFFER_RADIUS = 1000}

    test("Settings normalization starts new installs simple and keeps existing players' choices", function()
        local fresh = addon.SettingsDefaults.Normalize({}, limits, true)
        equal(fresh.simpleNavigator, true) equal(fresh.displayMode, "full") equal(fresh.opacityPercent, 80)
        equal(fresh.showRouteLine, true) equal(fresh.iconLabels, true) equal(fresh.groupSync, false)
        local existing = addon.SettingsDefaults.Normalize({displayMode = "arrow", fontPercent = 300, acceptedRows = 4.6,
            questieOfferRadius = 5000, screenArrowX = 1 / 0, screenArrowY = 3, sortByDistance = true, hubX = 0 / 0}, limits, false)
        equal(existing.simpleNavigator, false) equal(existing.displayMode, "arrow") equal(existing.fontPercent, 100)
        equal(existing.acceptedRows, 4) equal(existing.questieOfferRadius, 350) equal(existing.screenArrowX, nil)
        equal(existing.sortByDistance, nil) equal(existing.hubX, nil)
        local kept = addon.SettingsDefaults.Normalize({simpleNavigator = true, showDirectionArrow = false, displayMode = "arrow"}, limits, false)
        equal(kept.simpleNavigator, true) equal(kept.displayMode, "full") equal(kept.hidden, false)
        local character = addon.SettingsDefaults.NormalizeCharacter({questNotes = "broken", accessPoints = {a = 1}})
        equal(type(character.questNotes), "table") equal(character.accessPoints.a, 1) equal(type(character.flightRoutes), "table")
    end)

    test("Command registry parses arguments, generates help and hides advanced commands in simple mode", function()
        local C = addon.Commands
        local saved, savedKeys = C.list, C.byKey
        C.Reset()
        local seen = {}
        C.Register({key = "", group = "navigation", hidden = true, run = function() seen.toggle = true end})
        C.Register({key = "find", group = "quests", label = "CmdFind", args = true, run = function(text) seen.find = text end})
        C.Register({key = "perf on", group = "debug", label = "CmdPerfOn", advanced = true, run = function() seen.perf = true end})
        C.Register({key = "notes", group = "quests", label = "CmdNotes", run = function() seen.notes = true end})
        equal(C.Dispatch("  "), true) equal(seen.toggle, true)
        equal(C.Dispatch(" FIND Hogger Bounty "), true) equal(seen.find, "Hogger Bounty")
        equal(C.Dispatch("Perf On"), true) equal(seen.perf, true)
        local printed
        local env = getfenv(C.Dispatch)
        local previous = rawget(env, "print")
        env.print = function(text) printed = text end
        equal(C.Dispatch("nonsense"), false)
        env.print = previous
        assert(printed:find("/fqn notes", 1, true)) assert(printed:find("/fqn perf on", 1, true))
        local simple = C.Help(true)
        assert(simple:find("/fqn find …", 1, true)) assert(not simple:find("perf on", 1, true))
        equal(#C.Visible(true), 2) equal(#C.Visible(false), 3)
        equal(#C.Filter("zzz-no-match", false), 0)
        equal(C.Filter("NOTES", false)[1].key, "notes")
        C.list, C.byKey = saved, savedKeys
    end)

    test("Bag, gear and mount events take the light refresh path; quest log events still rebuild", function()
        local calls = {}
        local function count(name) return function() calls[name] = (calls[name] or 0) + 1 end end
        local context = {refresh = count("refresh"), refreshItems = count("items"), updateQuestLog = count("log"),
            taxi = function() end, captureXP = function() end, visible = function() return false end}
        for event in pairs(addon.EventController.itemEvents) do addon.EventController.Handle(context, event) end
        equal(calls.items, 4) equal(calls.refresh, nil) equal(calls.log, nil)
        addon.EventController.Handle(context, "QUEST_LOG_UPDATE")
        equal(calls.refresh, 1) equal(calls.log, 1)
        addon.EventController.Handle(context, "GROUP_ROSTER_UPDATE")
        equal(calls.refresh, 2)
        context.refreshGroup = count("group")
        addon.EventController.Handle(context, "GROUP_ROSTER_UPDATE")
        equal(calls.group, 1) equal(calls.refresh, 2)
    end)

    test("Update notes show only the newest versions in the chosen language", function()
        local notes = addon.ReleaseNotes
        local english, german = notes.Text("9.9.9", "en"), notes.Text("9.9.9", "de")
        assert(english:find("Forever Quest Navigator 9.9.9", 1, true))
        assert(english:find(notes.history[1].version, 1, true)) assert(english:find(notes.history[1].en, 1, true))
        assert(german:find(notes.history[1].de, 1, true))
        local saved = notes.history
        notes.history = {{version = "4", en = "d", de = "d"}, {version = "3", en = "c", de = "c"},
            {version = "2", en = "b", de = "b"}, {version = "1", en = "OLDEST", de = "OLDEST"}}
        assert(not notes.Text("4", "en"):find("OLDEST", 1, true))
        notes.history = saved
    end)

    test("Action symbols replace words only while symbols are enabled", function()
        local saved = addon.UI.iconLabels
        addon.UI.iconLabels = true
        assert(addon.UI.ActionText("turnIn", "Turn in"):find("ActiveQuestIcon", 1, true))
        assert(addon.UI.ActionIcon("unknown"):find("RaidTargetingIcon", 1, true))
        addon.UI.iconLabels = false
        equal(addon.UI.ActionText("accept", "Accept"), "Accept")
        addon.UI.iconLabels = saved
    end)

    test("Flight hints use measured distance and the step text follows the selected objective", function()
        local FP = addon.FlightPoints
        equal(FP.Hint({}, {measurement = {yards = 100}, minimum = 1500}, {}), nil)
        equal(FP.Step(nil, nil, {}), addon.L.FlightGeneric)
        equal(FP.Step({id = 1, readyToTurnIn = true}, nil, {}), addon.L.FlightTurnIn)
        local api = {GetQuestObjectives = function() return {{text = "Wolves 1/8"}, {text = "Bears 0/4"}} end}
        equal(FP.Step({id = 1}, {marker = {objectiveIndex = 2}}, api), addon.L.FlightObjective:format("Bears 0/4"))
    end)
end
