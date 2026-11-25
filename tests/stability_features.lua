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
