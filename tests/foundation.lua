return function(test, addon, equal, near)
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

    test("Session recap counts turn-ins per zone, XP per hour and offers itself after a break", function()
        local session = addon.Session.New({zones = {Broken = "x"}, lastActive = 1000}, 0)
        equal(next(session.data.zones), nil)
        session:CaptureXP(10, 100, 1000) session:CaptureXP(10, 700, 1000)
        session:TurnIn(1, "Wolves", 300, "Elwynn Forest", 1100)
        session:TurnIn(2, "Bears", nil, "Elwynn Forest", 1200)
        session:TurnIn(3, "Murlocs", 200, "Westfall", 1300)
        session:Save(1800, 1300)
        local summary = session:Summary(1800)
        equal(summary.quests, 3) equal(summary.xp, 600) equal(summary.xpPerHour, 1200)
        equal(summary.topZone, "Elwynn Forest") equal(summary.topZoneQuests, 2)
        equal(session.data.recent[1].zone, "Westfall") equal(session.data.recent[1].at, 1300)
        local recap = session:Recap(1800, "Redridge")
        assert(recap:find("Elwynn Forest", 1, true)) assert(recap:find("Redridge", 1, true)) assert(recap:find("1200", 1, true))
        equal(session:ShouldOfferRecap(1300 + 1799, 1800), false)
        equal(session:ShouldOfferRecap(1300 + 1800, 1800), true)
        local reloaded = addon.Session.New(session.data, 0)
        equal(reloaded.data.zones["Elwynn Forest"].quests, 2) equal(reloaded.data.lastActive, 1300)
        equal(addon.Session.New({}, 0):ShouldOfferRecap(99999), false)
        equal(addon.Session.New({}, 0):Summary(60).xpPerHour, nil)
    end)

    test("Level forecast sums the nearest ready turn-ins and skips single level-ups", function()
        local F = addon.LevelForecast
        local quests = {{id = 1, readyToTurnIn = true, xp = 300}, {id = 2, readyToTurnIn = true, xp = 500},
            {id = 3, xp = 9999}, {id = 4, readyToTurnIn = true, xp = 400}, {id = 5, readyToTurnIn = true}}
        local yards = {[1] = {yards = 900}, [2] = {yards = 100}, [4] = {yards = 200}}
        local function XP(quest) return quest.xp end
        local plan = F.FromQuests(quests, yards, XP, 850)
        equal(plan.count, 2) equal(plan.total, 900) equal(plan.ids[1], 2) equal(plan.ids[2], 4)
        equal(F.FromQuests(quests, yards, XP, 450), nil)
        equal(F.FromQuests(quests, yards, XP, 5000), nil)
        equal(F.FromQuests(quests, yards, XP, nil), nil)
        equal(F.FromQuests(quests, yards, XP, 1200).count, 3)
    end)

    test("Group sync encodes compactly, rejects malformed or foreign messages and forgets members who leave", function()
        local Sync = addon.GroupSync
        Sync.Reset()
        local state = {target = 12, quests = {{id = 12, done = 1, total = 3}, {id = 40, done = 2, total = 2}}}
        local text = Sync.Encode(state)
        equal(text, "1|12|12:1:3,40:2:2")
        local decoded = Sync.Decode(text)
        equal(decoded.target, 12) equal(#decoded.quests, 2) equal(decoded.quests[2].done, 2)
        equal(Sync.Decode("1|0|").target, nil)
        for _, bad in ipairs({"2|1|5:0:1", "1|x|5:0:1", "1|1|5:3:1", "1|1|5:0", "1|1|5:0:1;DROP", "1|1|0:0:1", ("1|1|" .. ("9"):rep(300))}) do
            equal(Sync.Decode(bad), nil)
        end
        local many = {quests = {}}
        for id = 1, 80 do many.quests[id] = {id = 100000 + id, done = 0, total = 5} end
        local long = Sync.Encode(many)
        assert(#long <= Sync.MAX_BYTES) assert(Sync.Decode(long))
        local members = {Alice = true, ["Bob-OtherRealm"] = true}
        equal(Sync.Receive("Mallory", text, members, 1), false)
        equal(Sync.Receive("Alice", "garbage", members, 1), false)
        equal(Sync.Receive("Alice", text, members, 1), true)
        equal(Sync.Receive("Bob-OtherRealm", "1|0|12:0:3", members, 1), true)
        equal(Sync.Counts()[12], 2) equal(Sync.Counts()[40], nil)
        equal(Sync.Describe(12), "Alice 1/3, Bob-OtherRealm 0/3")
        equal(Sync.Prune({Alice = true}), true) equal(Sync.Describe(12), "Alice 1/3")
        Sync.Prune({}) equal(Sync.Counts(), nil)
    end)

    test("Group sync collects objective counts and throttles sends outside combat", function()
        local Sync = addon.GroupSync
        Sync.Reset()
        local questLog = {GetQuestObjectives = function(id)
            if id == 1 then return {{finished = true}, {finished = false}} end
            return {{finished = false}}
        end}
        local state = Sync.Collect({{id = 1}, {id = 2, readyToTurnIn = true}}, questLog, 1)
        equal(state.quests[1].done, 1) equal(state.quests[1].total, 2) equal(state.quests[2].done, 1)
        local sent = {}
        local api = {SendAddonMessage = function(prefix, message, channel) sent[#sent + 1] = {prefix, message, channel} end}
        equal(Sync.ReadyToSend(10, false), false)
        Sync.MarkDirty()
        equal(Sync.ReadyToSend(10, true), false)
        equal(Sync.ReadyToSend(10, false), true)
        Sync.Send(api, "PARTY", state, 10)
        equal(sent[1][1], "FQN1") equal(sent[1][3], "PARTY") equal(sent[1][2], "1|1|1:1:2,2:1:1")
        Sync.MarkDirty()
        equal(Sync.ReadyToSend(12, false), false) equal(Sync.ReadyToSend(13, false), true)
        Sync.Reset()
    end)

    test("Distance progress measures the covered share of the current leg", function()
        local memory, P = {}, addon.UI.DistanceProgress
        equal(P(memory, "q1", 400), 0)
        near(P(memory, "q1", 100), .75)
        equal(P(memory, "q1", 500), 0)
        near(P(memory, "q1", 250), .5)
        equal(P(memory, "q2", 30), nil)
        equal(P(memory, "q3", 200), 0)
        equal(P(memory, nil, 100), nil) equal(memory.key, nil)
        equal(P(memory, "q3", 0 / 0), nil)
    end)

    test("Notice queue shows one window at a time in priority order and waits outside combat", function()
        local Q = addon.NoticeQueue
        Q.Reset()
        local env = getfenv(Q.Pump)
        local combat = true
        local savedCombat = rawget(env, "InCombatLockdown")
        env.InCombatLockdown = function() return combat end
        local shown, frames = {}, {}
        local function Frame(name)
            local frame = {shown = false, scripts = {}}
            function frame:IsShown() return self.shown end
            function frame:Show() self.shown = true end
            function frame:Hide() self.shown = false if self.scripts.OnHide then self.scripts.OnHide(self) end end
            function frame:HookScript(_, callback) local previous = self.scripts.OnHide
                self.scripts.OnHide = function(...) if previous then previous(...) end callback(...) end end
            frames[name] = frame
            return function() shown[#shown + 1] = name frame:Show() return frame end
        end
        Q.Push("recap", 40, Frame("recap"))
        Q.Push("notes", 30, Frame("notes"))
        Q.Push("notes", 30, Frame("duplicate"))
        equal(#shown, 0)
        combat = false Q.Pump()
        equal(shown[1], "notes") equal(#shown, 1)
        frames.notes:Hide() equal(shown[2], "recap")
        Q.Push("nothing", 10, function() return nil end)
        frames.recap:Hide() equal(#shown, 2) equal(Q.active, nil)
        env.InCombatLockdown = savedCombat
        Q.Reset()
    end)

    test("Error log records FQN errors with counts and still reports them to the game", function()
        local Log, store = addon.ErrorLog, {}
        Log.Attach(store) Log.version = "9.9.9"
        local env = getfenv(Log.Call)
        local reported = {}
        local savedHandler, savedStack = rawget(env, "geterrorhandler"), rawget(env, "debugstack")
        env.geterrorhandler = function() return function(message) reported[#reported + 1] = message end end
        env.debugstack = function() return "Interface/AddOns/ForeverQuestNavigator/Core/Bootstrap.lua:120: in function" end
        local value = Log.Call("refresh", function(a, b) return a + b end, 2, 3)
        equal(value, 5)
        for _ = 1, 3 do Log.Call("refresh", function() error("Interface/AddOns/ForeverQuestNavigator/Core/X.lua:5: boom\nsecond line") end) end
        Log.Call("event", function() error("other") end)
        local entries = store.entries
        equal(#entries, 2) equal(entries[2].count, 3) equal(entries[2].origin, "Core/Bootstrap.lua:120")
        assert(not entries[2].message:find("second line", 1, true)) equal(#reported, 4)
        local summary = table.concat(Log.Summary(), "\n")
        assert(summary:find("errors=2", 1, true)) assert(summary:find("refresh x3 [9.9.9]", 1, true))
        for index = 1, 15 do Log.Call("e" .. index, function() error("x") end) end
        equal(#store.entries, Log.MAX)
        env.geterrorhandler = nil
        local ok = pcall(Log.Call, "test", function() error("loud") end)
        equal(ok, false)
        env.geterrorhandler, env.debugstack = savedHandler, savedStack
        Log.Clear() equal(Log.Summary()[1], "errors=none")
    end)

    test("Self-test lists required and optional game interfaces", function()
        local fakeEnv = {C_QuestLog = {GetInfo = 1, GetNumQuestLogEntries = 1, GetQuestObjectives = 1, IsOnQuest = 1},
            C_Map = {GetBestMapForUnit = 1, GetPlayerMapPosition = 1, GetMapInfo = 1}, C_Timer = {NewTicker = 1},
            C_ChatInfo = {SendAddonMessage = 1}}
        local text, failures, warnings = addon.SelfTest.Run(fakeEnv, {version = "1.0.0", mapID = 1415, position = true, quests = 3})
        equal(failures, 0) assert(warnings > 0)
        assert(text:find("OK · Addon messages", 1, true)) assert(text:find("missing (optional) · Questie", 1, true))
        local _, missing = addon.SelfTest.Run({}, {})
        equal(missing, 8)
    end)

    test("Finished sessions are archived newest first and limited to ten", function()
        local Session, history = addon.Session, {}
        equal(Session.DescribeHistory(history), addon.L.HistoryEmpty)
        Session.Archive(history, Session.New({}, 0), 600, 1000)
        equal(#history, 0)
        for index = 1, 12 do
            local session = Session.New({}, 0)
            session:TurnIn(index, "Q", 100, "Zone " .. index, 10)
            session:CaptureXP(10, 0, 1000) session:CaptureXP(10, index * 100, 1000)
            Session.Archive(history, session, 3600, 86400 * index)
        end
        equal(#history, 10) equal(history[1].zone, "Zone 12") equal(history[1].xpPerHour, 1200)
        local text = Session.DescribeHistory(history)
        assert(text:find("Zone 12", 1, true)) assert(text:find(addon.L.HistoryRate:format(1200), 1, true))
        assert(not text:find("Zone 2 ", 1, true))
    end)

    test("Flight hints compare flying and walking time", function()
        local location = addon.QuestLocation
        local saved = location.GetFlightPlan
        location.GetFlightPlan = function() return {origin = {name = "A"}, landing = {name = "B"}, approach = 100, finish = 200,
            seconds = 250, walkSeconds = 900} end
        local text = addon.FlightPoints.Hint({target = {}}, {measurement = {yards = 5000}, minimum = 1500}, {})
        assert(text:find(addon.L.FlightCompare:format(4, 15), 1, true))
        assert(text:find("\n", 1, true))
        location.GetFlightPlan = saved
    end)

    test("Route order improvement untangles crossings and respects validity rules", function()
        local R = addon.RouteOrder
        local points = {a = {0, 0}, b = {10, 10}, c = {10, 0}, d = {0, 10}}
        local function Cost(stops)
            local total, previous = 0, {0, 0}
            for _, stop in ipairs(stops) do
                local p = points[stop]
                total = total + math.sqrt((p[1] - previous[1]) ^ 2 + (p[2] - previous[2]) ^ 2)
                previous = p
            end
            return total
        end
        local order, before, after = R.Improve({"a", "b", "c", "d"}, Cost)
        assert(after < before) near(after, 30)
        local blocked = R.Improve({"a", "b", "c", "d"}, Cost, function(stops) return stops[2] == "b" end)
        equal(blocked[2], "b")
        local unknown, first, last = R.Improve({"a", "b", "c"}, function() return nil end)
        equal(unknown[1], "a") equal(first, nil) equal(last, nil)
        equal(#order, 4)
    end)

    test("Tour preview reports the saving against the current order", function()
        local Tour = addon.TourPlan
        local plan = Tour.New()
        for _, id in ipairs({1, 2, 3}) do Tour.Add(plan, {id = id}) end
        local measurements = {[1] = {yards = 300, marker = {x = .3}}, [2] = {yards = 100, marker = {x = .1}},
            [3] = {yards = 200, marker = {x = .2}}}
        local preview = Tour.Preview(plan, measurements, function(a, b) return math.abs(a.x - b.x) * 1000 end)
        equal(preview.stops[1].id, 2) equal(preview.stops[3].id, 1) equal(preview.savedYards, 300)
        local ordered = Tour.New() for _, id in ipairs({2, 3, 1}) do Tour.Add(ordered, {id = id}) end
        equal(Tour.Preview(ordered, measurements, function(a, b) return math.abs(a.x - b.x) * 1000 end).savedYards, nil)
    end)

    test("Group test mode simulates a member one step behind and sends nothing", function()
        local Sync = addon.GroupSync
        Sync.Reset()
        local questLog = {GetQuestObjectives = function(id) return {{finished = true}, {finished = id == 2}} end}
        local quests = {{id = 1}, {id = 2, readyToTurnIn = true}, {id = 3}, {id = 4}}
        equal(Sync.Showing({groupSync = false}), false)
        local ok, stops = Sync.StartTest(quests, questLog, 5)
        equal(ok, true) equal(Sync.Showing({groupSync = false}), true)
        equal(Sync.Describe(1), "FQN-Test 1/2") equal(Sync.Describe(2), "FQN-Test 1/2") equal(Sync.Describe(4), nil)
        equal(#stops, 3) equal(stops[2].stage, "turnIn")
        Sync.Prune({}) equal(Sync.Describe(1), "FQN-Test 1/2")
        Sync.StopTest() equal(Sync.Describe(1), nil) equal(Sync.Showing({}), false)
        equal(Sync.StartTest({}, questLog, 5), false)
        Sync.Reset()
    end)

    test("Shared tours encode compactly and reject malformed messages", function()
        local Sync = addon.GroupSync
        local text = Sync.EncodeTour({{id = 12, stage = "objective"}, {id = 40, stage = "turnIn"}, {id = 0}})
        equal(text, "T1|12:o,40:t")
        local stops = Sync.DecodeTour(text)
        equal(#stops, 2) equal(stops[2].id, 40) equal(stops[2].stage, "turnIn")
        equal(#Sync.DecodeTour("T1|5:o,5:t"), 1)
        for _, bad in ipairs({"T2|5:o", "T1|", "T1|5:x", "T1|0:o", "T1|5:o;", "1|5|5:0:1"}) do equal(Sync.DecodeTour(bad), nil) end
        local many = {}
        for index = 1, 30 do many[index] = {id = 100000 + index} end
        equal(#Sync.DecodeTour(Sync.EncodeTour(many)), Sync.TOUR_MAX)
        equal(Sync.EncodeTour({}), nil)
        local sent
        equal(Sync.ShareTour({SendAddonMessage = function(prefix, message, channel) sent = {prefix, message, channel} end}, "PARTY", {{id = 7}}), true)
        equal(sent[2], "T1|7:o") equal(sent[3], "PARTY")
        equal(Sync.ShareTour({}, nil, {{id = 7}}), false)
    end)

    test("Follow-ups unlocking at the next level are found only when they start on shown maps", function()
        local I = addon.QuestieIntegration
        local env = getfenv(I.SoonFollowUps)
        local savedDB, savedLoader = rawget(env, "LibQuestieDB"), rawget(env, "QuestieLoader")
        local chain = {[1] = 11, [2] = 12, [3] = 13, [4] = 14}
        local required = {[11] = 21, [12] = 21, [13] = 22, [14] = 21}
        local starters = {[11] = {{101}}, [12] = {{102}}, [13] = {{101}}, [14] = {nil, {201}}}
        local spawns = {[101] = {[40] = {{50, 50}}}, [102] = {[99] = {{1, 1}}}, [201] = {[40] = {{2, 2}}}}
        env.LibQuestieDB = {Quest = {nextQuestInChain = function(id) return chain[id] end,
            requiredLevel = function(id) return required[id] end, startedBy = function(id) return starters[id] end},
            Npc = {spawns = function(id) return spawns[id] end}, Object = {spawns = function(id) return spawns[id] end}}
        env.QuestieLoader = {ImportModule = function() return {GetUiMapIdByAreaId = function(_, area) return area == 40 and 1429 or 9999 end} end}
        local found = I.SoonFollowUps({1, 2, 3, 4, 5}, 20, {[1429] = true})
        equal(found[11], true) equal(found[12], nil) equal(found[13], nil) equal(found[14], true)
        equal(next(I.SoonFollowUps({1}, 20, nil)), nil)
        env.LibQuestieDB = nil
        equal(next(I.SoonFollowUps({1}, 20, {[1429] = true})), nil)
        env.LibQuestieDB, env.QuestieLoader = savedDB, savedLoader
    end)

    test("Daily goal expires the next day and estimates remaining turn-ins", function()
        local G, store = addon.DailyGoal, {}
        equal(G.Set(store, "30", "2026-11-24", 30), false) equal(G.Set(store, "60", "2026-11-24", 30), false)
        equal(G.Set(store, "32", "2026-11-24", 30), true)
        local goal = G.Current(store, "2026-11-24")
        equal(goal.level, 32) equal(G.Current(store, "2026-11-25"), nil)
        local progress = G.Progress(goal, 31, 500, 1000, 250)
        near(progress.levelsLeft, 0.5) equal(progress.xpLeft, 500) equal(progress.turnIns, 2) near(progress.fraction, 0.75)
        local text = G.Describe(goal, progress)
        assert(text:find("32", 1, true)) assert(text:find(addon.L.GoalTurnIns:format(2), 1, true))
        equal(G.Progress(goal, 32, 0, 1000).done, true)
        equal(G.Progress(goal, 30, 0, 1000, nil).turnIns, nil)
        G.Clear(store) equal(G.Current(store, "2026-11-24"), nil)
    end)

    test("Minimap arrow points relative to facing on rotating maps and absolute on north-up maps", function()
        local Arrow = addon.MinimapArrow
        local angle, x, y = Arrow.Place(0, 1, 1.0, true)
        near(angle, 0) near(x, 0) near(y, 1)
        angle, x, y = Arrow.Place(1, 0, 0, false)
        near(angle, math.pi / 2) near(x, 1) near(y, 0)
        angle = Arrow.Place(0, 1, math.pi / 2, false)
        near(angle, -math.pi / 2)
        equal(Arrow.Place(nil, 1, 0, false), nil) equal(Arrow.Place(0, 0, 0, false), nil)
        equal(Arrow.Size(100), 26) near(Arrow.Size(160), 30.4) equal(Arrow.Size(400), 40)
        Arrow.Update({minimapArrow = false}, 0, 1, 0)
        equal(Arrow.frame, nil)
    end)

    test("Texture paths in the source use escaped backslashes", function()
        -- "Interface\AddOns" in Lua silently becomes "InterfaceAddOns"; it must be written "Interface\\AddOns".
        for line in io.lines("ForeverQuestNavigator.toc") do
            if line:match("%.lua$") then
                local path = line:gsub("\\", "/")
                local file = assert(io.open(path)) local source = file:read("*a") file:close()
                assert(not source:find('"Interface\\%a'), path .. " has an unescaped texture path")
            end
        end
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
