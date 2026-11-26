return function(test, addon, equal, near)
    local function CanvasFixture()
        local canvas = {width = 1000, height = 500, scale = 1}
        function canvas:GetWidth() return self.width end
        function canvas:GetHeight() return self.height end
        function canvas:GetEffectiveScale() return self.scale end
        function canvas:GetFrameLevel() return 20 end
        function canvas:GetFrameStrata() return "BACKGROUND" end
        local map = {id = 10, shown = true}
        function map:GetCanvas() return canvas end
        function map:GetMapID() return self.id end
        function map:IsShown() return self.shown end
        function map:GetFrameStrata() return "HIGH" end
        function map:GetFrameLevel() return 100 end
        local created = {}
        local function Region()
            return setmetatable({shown = true, scripts = {}}, {__index = function(self, key)
                local methods = {
                    Hide = function(s) s.shown = false end, Show = function(s) s.shown = true end,
                    SetShown = function(s, value) s.shown = value end,
                    SetText = function(s, value) s.text = value end,
                    SetScript = function(s, name, value) s.scripts[name] = value end,
                    SetPoint = function(s, point, relative, other, x, y) s.x, s.y = x, y end,
                    SetScale = function(s, value) s.scale = value end,
                    SetSize = function(s, width, height) s.width, s.height = width, height end,
                    SetFrameStrata = function(s, value) s.strata = value end,
                    SetFrameLevel = function(s, value) s.level = value end,
                    SetAlpha = function(s, value) s.alpha = value end,
                    SetIgnoreParentAlpha = function(s, value) s.ignoreParentAlpha = value end,
                    CreateTexture = function() return Region() end,
                    CreateFontString = function() return Region() end,
                }
                return methods[key] or function() end
            end})
        end
        local function Create(kind) local frame = Region() frame.kind = kind created[#created + 1] = frame return frame end
        local api = {GetMapWorldSize = function() return 1000, 500 end}
        local renderer = addon.CanvasMarkers.New(map, api, Create)
        return renderer, map, canvas, created
    end
    test("Canvas markers attach to actual coordinates and recover after map changes and refreshes", function()
        local render, map, canvas = CanvasFixture()
        local target = {mapID = 10, x = .4, y = .6}
        render:Set(target)
        equal(render.count, 1) near(render.pins[1].x, 400) near(render.pins[1].y, -300)
        equal(render.pins[1].strata, "HIGH") assert(render.pins[1].level > map:GetFrameLevel())
        equal(render.pins[1].alpha, 1) equal(render.pins[1].ignoreParentAlpha, true)
        map.id = 20 render.watcher.scripts.OnUpdate(render.watcher, .2)
        equal(render.count, 0)
        map.id = 10 render.watcher.scripts.OnUpdate(render.watcher, .2)
        equal(render.count, 1)
        map.shown = false render:Refresh() equal(render.count, 0)
        map.shown = true render.watcher.scripts.OnShow() equal(render.count, 1)
        canvas.width = 2000 render.watcher.scripts.OnUpdate(render.watcher, .2)
        near(render.pins[1].x, 800)
        canvas.scale = 2 render.watcher.scripts.OnUpdate(render.watcher, .2)
        near(render.pins[1].scale, .5) near(render.pins[1].x, 1600)
    end)
    test("Co-located map stops keep real coordinates, group numbers and clear on right click", function()
        local render = CanvasFixture()
        local point = {mapID = 10, x = .4, y = .6}
        local removed = 0
        render:Set(point, function() removed = removed + 1 end,
            {{target = point, quest = {id = 1}}, {target = point, quest = {id = 2}}})
        equal(render.count, 1) equal(render.pins[1].number.text, "1/2")
        near(render.pins[1].x, 400) equal(#render.pins[1].stops, 2)
        render.pins[1].scripts.OnEnter(render.pins[1])
        equal(addon.QuestHover.ids[1], true) equal(addon.QuestHover.ids[2], true)
        render:Refresh() equal(addon.QuestHover.ids[1], true)
        render.pins[1].scripts.OnLeave(render.pins[1]) equal(next(addon.QuestHover.ids), nil)
        addon.QuestHover.Set({}, {[2] = true})
        equal(render.pins[1].width, 35)
        render.pins[1].scripts.OnEnter(render.pins[1])
        render.pins[1].scripts.OnClick(render.pins[1], "LeftButton") equal(removed, 0)
        render.pins[1].scripts.OnClick(render.pins[1], "RightButton")
        equal(removed, 1) equal(render.count, 0) equal(render.target, nil)
        equal(next(addon.QuestHover.ids), nil)
        equal(render.watcher.shown, false)
        render.watcher.scripts.OnShow() equal(render.count, 0)
    end)
    test("Route line connects consecutive numbered stops and can be switched off", function()
        local render, _, canvas = CanvasFixture()
        local lines = {}
        function canvas:CreateLine()
            local line = {shown = true}
            function line:SetStartPoint(_, _, x, y) self.x1, self.y1 = x, y end
            function line:SetEndPoint(_, _, x, y) self.x2, self.y2 = x, y end
            function line:SetThickness(value) self.thickness = value end
            function line:Show() self.shown = true end
            function line:Hide() self.shown = false end
            lines[#lines + 1] = line
            return line
        end
        local a, b, c = {mapID = 10, x = .1, y = .2}, {mapID = 10, x = .4, y = .6}, {mapID = 10, x = .8, y = .2}
        render:Set(a, nil, {{target = a, quest = {id = 1}}, {target = b, quest = {id = 2}}, {target = b, quest = {id = 3}},
            {target = c, quest = {id = 4}}})
        equal(render.lineCount, 2) near(lines[1].x1, 100) near(lines[1].y1, -100) near(lines[1].x2, 400) near(lines[2].x2, 800)
        assert(lines[1].thickness > lines[2].thickness, "the next leg is thicker, not only gold")
        render:Set(a, nil, {{target = a, quest = {id = 1}, single = true}})
        equal(render.lineCount, 0) equal(lines[1].shown, false)
        addon.CanvasMarkers.showLine = false
        render:Set(a, nil, {{target = a, quest = {id = 1}}, {target = c, quest = {id = 4}}})
        equal(render.lineCount, 0)
        addon.CanvasMarkers.showLine = true
        render:Refresh() equal(render.lineCount, 1)
    end)
    test("Canvas marker strata follows fullscreen maps instead of staying below them", function()
        local render, map = CanvasFixture()
        map.GetFrameStrata = function() return "FULLSCREEN" end
        render:Set({mapID = 10, x = .4, y = .6})
        equal(render.pins[1].strata, "FULLSCREEN")
        assert(render.pins[1].level > map:GetFrameLevel())
    end)
    test("Explicit map targets remain visible when preview stops are in another zone", function()
        local render = CanvasFixture()
        render:Set({mapID = 10, x = .2, y = .3}, nil,
            {{target = {mapID = 20, x = .4, y = .6}}})
        equal(render.count, 1) near(render.pins[1].x, 200)
    end)
    test("Map requests survive delayed map loading and clearing cancels pending requests", function()
        local watcher, renderer
        local env = setmetatable({}, {__index = getfenv()})
        env.WorldMapFrame, env.MapCanvasDataProviderMixin, env.MapCanvasPinMixin = false, false, false
        env.CreateFrame = function()
            watcher = {scripts = {}}
            function watcher:SetScript(key, value) self.scripts[key] = value end
            function watcher:Show() self.shown = true end
            function watcher:Hide() self.shown = false end
            return watcher
        end
        local isolated = {L = addon.L, CanvasMarkers = {New = function(map)
            if not (map and map.ready) then return end
            renderer = {count = 0}
            function renderer:Set(target, remove, route) self.target, self.remove, self.route = target, remove, route self.count = target and 1 or 0 end
            return renderer
        end}}
        setfenv(assert(loadfile("UI/QuestMap.lua")), env)("FQN", isolated)
        local target = {mapID = 10, x = .2, y = .3}
        isolated.ShowQuestMapMarker(target)
        equal(isolated.GetMapMarkerStatus().hasTarget, true) equal(watcher.shown, true)
        isolated.ShowQuestMapMarker()
        equal(watcher.shown, false) equal(isolated.GetMapMarkerStatus().hasTarget, false)
        isolated.ShowQuestMapMarker(target)
        env.WorldMapFrame = {ready = true, GetCanvas = function() return {} end}
        watcher.scripts.OnUpdate(watcher, .2)
        equal(isolated.GetMapMarkerStatus().backend, "canvas overlay")
        equal(renderer.target, target) equal(renderer.count, 1)
        isolated.ShowQuestMapMarker()
        equal(renderer.count, 0)
    end)
    test("Target hints distinguish exact givers, search areas and unknown locations", function()
        equal(addon.NavigationHints.TargetKind({outdoorTurnIn = true}), "giver")
        equal(addon.NavigationHints.TargetKind({targetKind = "area"}), "area")
        equal(addon.NavigationHints.TargetKind(nil), "unknown")
        equal(addon.NavigationHints.NextAction({readyToTurnIn = true}, {}), addon.L.ArrivalTurnIn)
        equal(addon.NavigationHints.NextAction({}, {targetKind = "area"}), addon.L.ArrivalArea)
        local snapshot = {decision = "followUp", decisionSaving = 250, ranked = {{id = 1}, {id = 2}}}
        equal(addon.NavigationHints.Why(snapshot, {id = 2}), addon.L.WhySaving:format(250))
        equal(addon.NavigationHints.Change({id = 2}, {id = 2}, snapshot), nil)
        equal(addon.NavigationHints.Change({id = 1}, {id = 2, readyToTurnIn = true}, snapshot), addon.L.ChangeTurnIn)
    end)
    test("Update notes are once per version, respect opt-out and do not surprise new installations", function()
        local settings = {}
        equal(addon.ReleaseNotes.Initialize(settings, "0.1.66", false), nil)
        equal(settings.lastSeenVersion, "0.1.66")
        equal(addon.ReleaseNotes.Initialize(settings, "0.1.66", true), nil)
        equal(addon.ReleaseNotes.Initialize(settings, "0.1.67", true), "0.1.67")
        settings.showUpdateNotes = false
        equal(addon.ReleaseNotes.Initialize(settings, "0.1.67", true), nil)
        equal(settings.lastSeenVersion, "0.1.67")
    end)
    test("Performance sampling is optional, bounded and independent of game CPU settings", function()
        local original = debugprofilestop
        local clock = 10
        debugprofilestop = function() return clock end
        local perf = addon.Performance
        equal(perf:Start(), true)
        for index = 1, 150 do local start = perf:Begin() clock = clock + 2 perf:Finish("planning", start) end
        equal(perf.sections.planning.count, 150) equal(#perf.sections.planning.samples, 128)
        near(perf.sections.planning.total, 300) near(perf.sections.planning.maximum, 2)
        assert(perf:Report():find("p95(last 128)=2.000 ms", 1, true))
        perf.enabled = false equal(perf:Begin(), nil)
        debugprofilestop = original
    end)
    test("Quest helpers: respawn, bags, turn-in collector, hearthstone, sounds and character profile", function()
        local L = addon.L
        -- Respawn: counts down from the oldest recent kill and forgets kills that are back.
        local Respawn = addon.Respawn
        local state = Respawn.New()
        equal(Respawn.Remaining(state, "Wolf", 0), nil)
        Respawn.Killed(state, "Wolf", 100) Respawn.Killed(state, "Wolf", 160)
        equal(Respawn.Remaining(state, "Wolf", 130), 270)
        equal(Respawn.Remaining(state, "Wolf", 410), 50)
        equal(Respawn.Remaining(state, "Wolf", 500), nil)
        -- Bags: free slots against non-turn-in stops, grey items as a suggestion.
        local bags = {[0] = {free = 0, items = {{quality = 0, link = "[Junk]"}, {quality = 2, link = "[Sword]"}}}, {free = 1, items = {}}}
        local api = {free = function(bag) return bags[bag] and bags[bag].free or 0 end,
            slots = function(bag) return bags[bag] and #bags[bag].items or 0 end,
            item = function(bag, slot) return bags[bag].items[slot] end}
        local stops = {{action = "accept"}, {action = "objective"}, {action = "turnIn"}}
        equal(addon.BagCheck.Needed(stops), 4)
        local warning = addon.BagCheck.Check(api, stops, L)
        assert(warning:find("1", 1, true) and warning:find("[Junk]", 1, true) and not warning:find("[Sword]", 1, true))
        bags[1].free = 6 equal(addon.BagCheck.Check(api, stops, L), nil)
        -- Collector: three ready turn-ins close together, told once.
        local ranked = {{id = 1, readyToTurnIn = true}, {id = 2, readyToTurnIn = true}, {id = 3, readyToTurnIn = true}, {id = 4}}
        local measured = {[1] = {yards = 800, marker = {x = 0}}, [2] = {yards = 820, marker = {x = 100}}, [3] = {yards = 900, marker = {x = 200}}}
        local function Distance(a, b) return math.abs(a.x - b.x) end
        local collector = {}
        equal(addon.TurnInCollector.Check(collector, ranked, measured, Distance, L), L.TurnInCollector:format(3, 2))
        equal(addon.TurnInCollector.Check(collector, ranked, measured, Distance, L), nil)
        measured[3].marker.x = 900
        equal(addon.TurnInCollector.Check({}, ranked, measured, Distance, L), nil, "a spread-out set is not a cluster")
        -- Hearthstone: ready, far away and at least two turn-ins near the inn.
        local hearth = {x = 0, name = "Goldshire"}
        local turnIns = {{quest = {id = 1}, marker = {x = 50}}, {quest = {id = 2}, marker = {x = 120}}, {quest = {id = 3}, marker = {x = 2000}}}
        local hint = {}
        equal(addon.HearthHint.Suggest(hint, hearth, turnIns, 3000, true, Distance, L), L.HearthHint:format(2, "Goldshire"))
        equal(addon.HearthHint.Suggest(hint, hearth, turnIns, 3000, true, Distance, L), nil)
        equal(addon.HearthHint.Suggest({}, hearth, turnIns, 500, true, Distance, L), nil, "not when already close")
        equal(addon.HearthHint.Suggest({}, hearth, turnIns, 3000, false, Distance, L), nil, "not while on cooldown")
        -- Sounds: objective finished on the same quest, or an automatic change of quest.
        local sound = {}
        equal(addon.QuestSounds.Check(sound, 1, 0, false), nil)
        equal(addon.QuestSounds.Check(sound, 1, 1, false), "objective")
        equal(addon.QuestSounds.Check(sound, 1, 1, false), nil)
        equal(addon.QuestSounds.Check(sound, 2, 0, false), "change")
        equal(addon.QuestSounds.Check(sound, 3, 0, true), nil, "manual picks are silent")
        -- Profile: own values while playing, account values restored at logout.
        local settings, character = {theme = "graphite", fontPercent = 100}, {ownProfile = true, profile = {theme = "midnight", fontPercent = 120}}
        local account = addon.CharacterProfile.Apply(settings, character)
        equal(settings.theme, "midnight") equal(settings.fontPercent, 120)
        settings.fontPercent = 130
        addon.CharacterProfile.Store(settings, character, account)
        equal(settings.theme, "graphite") equal(settings.fontPercent, 100) equal(character.profile.fontPercent, 130)
        equal(addon.CharacterProfile.Apply(settings, {}), nil)
    end)
    test("Quest value ranks by XP per minute, look-ahead, follow-ups, zone and learned preference", function()
        local Value, Prioritizer, L = addon.QuestValue, addon.QuestPrioritizer, addon.L
        local model = Value.Model({})
        equal(model.speed, 420) equal(model.unitMinutes, .6)
        local function Point(x, map) return {mapID = map or 1, x = x, y = 0} end
        local function Distance(a, b) if a.mapID ~= b.mapID then return end return math.abs(a.x - b.x) end
        local function Rank(quests, measurements, context)
            context.quests, context.measurements, context.model = quests, measurements, context.model or model
            context.distance = context.distance or Distance
            local adjustments, factors = Value.Adjustments(context)
            local ranked = Prioritizer.RankByDistance(quests, measurements, nil, 20, nil, 5, adjustments)
            local ids = {}
            for index, quest in ipairs(ranked) do ids[index] = quest.id end
            return table.concat(ids, ","), factors, adjustments
        end
        local function Quest(id, kills, other) return {id = id, level = 20, progress = {remaining = kills + (other or 0), monsters = kills, items = 0, other = other or 0}} end
        -- XP per minute: the farther quest with far more XP wins; without XP data distance decides.
        local quests = {Quest(1, 2), Quest(2, 2)}
        local measured = {[1] = {yards = 150, marker = Point(150)}, [2] = {yards = 300, marker = Point(300)}}
        local xp = {[1] = 200, [2] = 1500}
        local order, factors = Rank(quests, measured, {xp = function(q) return xp[q.id] end})
        equal(order, "2,1") assert(factors[2].xpPerMinute > factors[1].xpPerMinute)
        equal(Rank(quests, measured, {}), "1,2")
        -- Way to the turn-in counts: a long return trip lowers the rate.
        local long = Value.Minutes(quests[1], measured[1], {totalYards = 1500}, model)
        local short = Value.Minutes(quests[1], measured[1], nil, model)
        assert(long > short)
        -- Follow-ups: a quest that unlocks a chain moves ahead of an equal one nearby.
        order = Rank({Quest(3, 2), Quest(4, 2)}, {[3] = {yards = 200, marker = Point(200)}, [4] = {yards = 230, marker = Point(230)}},
            {chains = {[4] = {followUps = {{id = 9}, {id = 10}}}}})
        equal(order, "4,3")
        -- Finish the zone: the last quest here beats a slightly closer one on another map.
        order = Rank({Quest(5, 2), Quest(6, 2), Quest(7, 2)},
            {[5] = {yards = 200, marker = Point(200, 2)}, [6] = {yards = 220, marker = Point(220, 1)}, [7] = {yards = 900, marker = Point(900, 2)}},
            {playerMap = 1})
        equal(order:sub(1, 1), "6")
        -- Look-ahead: the quest whose end lies next to another quest ranks earlier.
        local _, lookFactors, lookAdjust = Rank({Quest(11, 1), Quest(12, 1), Quest(13, 1)},
            {[11] = {yards = 100, marker = Point(100)}, [12] = {yards = 110, marker = Point(-110)}, [13] = {yards = 130, marker = Point(130)}}, {})
        assert(lookAdjust[11] < lookAdjust[12], "end next to another quest is better")
        equal(lookFactors[11].nextYards, 30)
        -- Learned preference: collect quests after choosing collect over kill.
        local learner = Value.Model({})
        local kill, collect = Quest(20, 5), {id = 21, level = 20, progress = {remaining = 5, monsters = 0, items = 5, other = 0}}
        equal(Value.Kind(kill), "kill") equal(Value.Kind(collect), "collect")
        for _ = 1, 3 do Value.LearnChoice(learner, collect, kill) end
        equal(learner.prefer.collect, 24) equal(learner.prefer.kill, -12)
        order = Rank({kill, collect}, {[20] = {yards = 200, marker = Point(200)}, [21] = {yards = 220, marker = Point(220)}}, {model = learner})
        equal(order, "21,20")
        for _ = 1, 20 do Value.LearnChoice(learner, collect, kill) end
        equal(learner.prefer.collect, Value.PREFERENCE_LIMIT, "bounded")
        Value.Reset(learner) equal(learner.prefer.collect, 0)
        -- Learning speed and work time from real play.
        local speedState = {}
        Value.ObserveSpeed(model, speedState, 1, 500, 0)
        local before = model.speed
        Value.ObserveSpeed(model, speedState, 1, 486, 1) -- 14 yd/s mounted
        assert(model.speed > before)
        Value.ObserveSpeed(model, speedState, 1, 486, 2) -- standing still is ignored
        Value.ObserveSpeed(model, speedState, 2, 100, 3) -- another target restarts sampling
        local effort, work = {}, Value.Model({})
        Value.ObserveEffort(work, effort, {Quest(30, 10)}, 0)
        Value.ObserveEffort(work, effort, {{id = 30, readyToTurnIn = true}}, 600) -- 10 kills in 10 minutes
        assert(work.unitMinutes > .6 and work.unitMinutes < 1)
        Value.ObserveEffort(work, effort, {Quest(31, 5)}, 0)
        local unit = work.unitMinutes
        Value.ObserveEffort(work, effort, {{id = 31, readyToTurnIn = true}}, 5000)
        equal(work.unitMinutes, unit, "quests left aside for a long time teach nothing")
        -- Explanation for the tooltip.
        equal(Value.Explain({xpPerMinute = 650, nextYards = 80, followUps = 2}, L),
            L.WhyXPPerMinute:format(650) .. " · " .. L.WhyNextClose .. " · " .. L.WhyFollowUps:format(2))
        equal(Value.Compare({xpPerMinute = 650, followUps = 1}, {xpPerMinute = 300}, "Wolves", L),
            L.CompareBefore:format("Wolves", L.CompareXP:format(650, 300) .. " · " .. L.CompareFollowUp))
        equal(Value.Compare({xpPerMinute = 310}, {xpPerMinute = 300}, "Wolves", L), nil, "small differences are not worth a line")
        local snapshot = {measurements = {[1] = {yards = 10}}, factors = {[1] = {xpPerMinute = 650}}}
        equal(addon.NavigationHints.Why(snapshot, {id = 1}), L.WhyLevelDistance .. " · " .. L.WhyXPPerMinute:format(650))
        equal(addon.NavigationHints.Why(snapshot, {id = 1}, true), L.WhyManual)
    end)
    test("One kill left at the camp beats a fresh quest elsewhere despite a far turn-in", function()
        -- Reported case: murlocs 8/8 + 7/8, camp cleared, turn-in far away; buzzards a few hundred yards off.
        local Value, Prioritizer = addon.QuestValue, addon.QuestPrioritizer
        local murlocs = {id = 1, title = "Murlocs", level = 20, progress = {remaining = 1, monsters = 1, items = 0, other = 0, nearly = true, bonus = 40}}
        local buzzards = {id = 2, title = "Buzzards", level = 20, progress = {remaining = 8, monsters = 8, items = 0, other = 0}}
        local quests = {murlocs, buzzards}
        local function Point(x) return {mapID = 1, x = x, y = 0} end
        local measured = {[1] = {yards = 60, marker = Point(60)}, [2] = {yards = 350, marker = Point(350)}}
        local journeys = {[1] = {totalYards = 2660, extraYards = 2600, returnYards = 2550, goals = 1}}
        equal(addon.TravelSupport.PlanningPenalty(murlocs, journeys[1], true), 50 * .35, "the unavoidable way back does not count")
        local adjustments = Value.Adjustments({quests = quests, measurements = measured, journeys = journeys, model = Value.Model({}),
            xp = function(q) return q.id == 2 and 1500 or 1000 end, distance = function(a, b) return math.abs(a.x - b.x) end})
        adjustments[1] = adjustments[1] - 60 -- standing in the murloc spawn area (presence)
        local ranked = Prioritizer.RankByDistance(quests, measured, nil, 20, journeys, 5, adjustments)
        equal(ranked[1].id, 1)
        -- Without "nearly done" the far turn-in still counts as before.
        local fresh = {id = 3, level = 20, progress = {remaining = 8, monsters = 8, items = 0, other = 0}}
        near(addon.TravelSupport.PlanningPenalty(fresh, journeys[1], true), 910)
        -- Unknown turn-ins are no longer cheaper in the XP-per-minute estimate.
        local model = Value.Model({})
        local known = Value.Minutes(buzzards, {yards = 350}, {totalYards = 700}, model)
        local unknown = Value.Minutes(buzzards, {yards = 350}, nil, model)
        near(known, unknown)
    end)
    test("Questie results are kept while only kill counts change", function()
        local Integration = addon.QuestieIntegration
        local goals = {[1] = {{finished = false, numFulfilled = 3}, {finished = true}}, [2] = {{finished = false}}}
        local api = {GetQuestObjectives = function(id) return goals[id] end}
        local quests = {{id = 1}, {id = 2}}
        local key = Integration.StateKey(quests, api, "maps")
        goals[1][1].numFulfilled = 4
        equal(Integration.StateKey(quests, api, "maps"), key, "a kill that finishes nothing keeps the key")
        goals[1][1].finished = true
        assert(Integration.StateKey(quests, api, "maps") ~= key, "a finished objective changes it")
        assert(Integration.StateKey({{id = 1}}, api, "maps") ~= key, "a quest leaving the log changes it")
        assert(Integration.StateKey(quests, api, "other maps") ~= key, "other maps change it")
        equal(Integration.MapKey({[20] = true, [3] = true}), "3,20")
    end)
    test("Mobs that count for two quests are recognized and explained", function()
        -- Reported case: kill murlocs and collect murloc eyes from the same mobs.
        local Marks = addon.TargetMarks
        local quests = {{id = 1, title = "Murlocs"}, {id = 3, title = "Murloc Eyes"}, {id = 4, title = "Buzzards"},
            {id = 5, title = "Done", readyToTurnIn = true}}
        local relations = {[1] = {{objectiveIndex = 1, npcID = 101}, {objectiveIndex = 2, npcID = 102}},
            [3] = {{objectiveIndex = 1, npcID = 102}}, [4] = {{objectiveIndex = 1, npcID = 200}}, [5] = {{objectiveIndex = 1, npcID = 101}}}
        local others, byNpc = Marks.SharedQuests(relations, 1, quests)
        equal(#others, 1) equal(others[1].id, 3) equal(byNpc[102][1], "Murloc Eyes") equal(byNpc[101], nil)
        local counts = Marks.SharedCounts(relations, quests)
        equal(counts[1], 1) equal(counts[3], 1) equal(counts[4], nil)
        local adjustments, factors = addon.QuestValue.Adjustments({quests = {{id = 1}, {id = 4}},
            measurements = {[1] = {yards = 100, marker = {mapID = 1, x = 0, y = 0}}, [4] = {yards = 100, marker = {mapID = 1, x = 0, y = 0}}},
            model = addon.QuestValue.Model({}), shared = counts})
        assert((adjustments[1] or 0) < (adjustments[4] or 0)) equal(factors[1].sharedMobs, 1)
        assert(addon.QuestValue.Explain(factors[1], addon.L):find(addon.L.WhySharedMobs, 1, true))
    end)
    test("Mark clicks cycle through living quest mobs instead of toggling one mark", function()
        local Marks = addon.TargetMarks
        local button = {attributes = {}}
        function button:SetAttribute(key, value) self.attributes[key] = value end
        function button:GetAttribute(key) return self.attributes[key] end
        local alive = {nameplate2 = true, nameplate5 = true, nameplate7 = true}
        local snippet = assert(loadstring("local self, button, down = ...\n" .. Marks.CYCLE_SNIPPET))
        setfenv(snippet, {UnitExists = function(unit) return alive[unit] ~= nil end,
            UnitIsDead = function(unit) return alive[unit] == false end})
        local function Click() snippet(button, "LeftButton", true) snippet(button, "LeftButton", false) return button.attributes.macrotext end
        Marks.SetCycle(button, "Kobold", 8, {"nameplate2", "nameplate5", "nameplate7"})
        equal(button.attributes.macrotext, Marks.Macro("Kobold", 8))
        equal(Click(), "/target nameplate2\n/tm [exists] 8")
        equal(Click(), "/target nameplate5\n/tm [exists] 8", "the press does not advance, only the release")
        alive.nameplate7 = false
        equal(Click(), "/target nameplate2\n/tm [exists] 8", "dead mobs are skipped")
        alive = {}
        equal(Click(), "/cleartarget\n/targetexact Kobold\n/tm [exists] 8", "without living candidates the name is used")
        -- Fewer candidates later: old unit attributes are cleared.
        Marks.SetCycle(button, "Kobold", 8, {"nameplate9"})
        equal(button.attributes["fqn-unit2"], nil) equal(button.attributes["fqn-count"], 1)
        -- Wrapping only where the client offers secure handlers.
        equal(Marks.WrapCycle(button, {}), false)
        local previous = SecureHandlerWrapScript
        local wrapped
        SecureHandlerWrapScript = function(frame, script, handler, body) wrapped = {frame, script, body} end
        equal(Marks.WrapCycle(button, {}), true) equal(wrapped[2], "OnClick") equal(wrapped[3], Marks.CYCLE_SNIPPET)
        SecureHandlerWrapScript = previous
    end)
    test("Questie lookups give NPC danger and group members' quest mobs", function()
        local previous = LibQuestieDB
        local names = {[1] = "Wolf", [2] = "Bear", [3] = "Ogre"}
        LibQuestieDB = {
            Npc = {name = function(id) return names[id] end, maxLevel = function(id) return id == 3 and 30 or 10 end,
                rank = function(id) return id == 3 and 1 or 0 end},
            Quest = {objectives = function() return {{{1, "Wolves"}}, nil, {{99, "Pelt"}}} end},
            Item = {npcDrops = function() return {2, 1} end},
        }
        local info = addon.QuestieIntegration.NpcInfo(3)
        equal(info.level, 30) equal(info.elite, true)
        equal(addon.QuestieIntegration.NpcInfo(1).elite, false)
        equal(table.concat(addon.QuestieIntegration.QuestMobNames(5), ","), "Wolf,Bear")
        LibQuestieDB = previous
        equal(#addon.QuestieIntegration.QuestMobNames(5), 0)
    end)
    test("Tooltip headings never pass wrapping as the numeric alpha argument", function()
        local previous = GameTooltip
        local observed
        GameTooltip = {
            SetOwner = function() end,
            SetText = function(_, text, r, g, b, alpha)
                assert(alpha == nil or type(alpha) == "number", "Tooltip alpha must be numeric") observed = text
            end,
            AddLine = function() end, Show = function() end,
        }
        addon.UI.ShowTextTooltip({}, "Heading", "Detail")
        equal(observed, "Heading")
        GameTooltip = previous
    end)
end
