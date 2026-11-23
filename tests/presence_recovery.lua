return function(test, addon, equal)
    local Presence, Recovery = addon.ObjectivePresence, addon.CorpseNavigation
    local function Point(x, y, map) return {mapID = map or 1, x = x, y = y or .5, objectiveIndex = 1, targetKind = "area", spawnKey = "m_123", npcID = 123} end
    local player = {x = .5, y = .5}
    local api = {GetBestMapForUnit = function() return 1 end, GetPlayerMapPosition = function() return player end,
        GetMapWorldSize = function() return 1000, 1000 end}
    test("Spawn neighborhoods recognize between nearby spawns without filling holes between distant camps", function()
        local a, b = Point(.39), Point(.61)
        local here = Presence.Area(api, {a, b}, {marker = a})
        equal(here.objectiveIndex, 1) assert(here.yardsToArea < 1)
        equal(Presence.Area(api, {Point(.1), Point(.9)}, {marker = a}), nil)
        b.spawnKey = "m_999" equal(Presence.Area(api, {a, b}, {marker = a}), nil)
        b.spawnKey = a.spawnKey b.mapID = 2 equal(Presence.Area(api, {a, b}, {marker = a}), nil)
    end)
    test("Area recognition has exit hysteresis and respects explicit objectives, camps and personal targets", function()
        local point = Point(.41)
        equal(Presence.Area(api, {point}, {marker = point}), nil)
        assert(Presence.Area(api, {point}, {marker = point}, {objectiveIndex = 1}))
        equal(Presence.Area(api, {point}, {marker = point}, nil, nil, 2), nil)
        equal(Presence.Area(api, {point}, {marker = point}, {objectiveIndex = 1}, {[1] = true}), nil)
        local near = Point(.51)
        equal(Presence.Area(api, {near}, {marker = near}, nil, nil, nil, {mapID = 1, x = .9, y = .5, manual = true}), nil)
        near.personalCorrection = true equal(Presence.Area(api, {near}, {marker = near}), nil)
        near.personalCorrection, near.notCombatSource = nil, true equal(Presence.Area(api, {near}, {marker = near}), nil)
    end)
    test("Combat recognition requires a public creature ID, own engagement and a matching open objective", function()
        local q = {id = 1}
        local units = {guid = function() return "Creature-0-1-2-3-123-0001" end, canAttack = function() return true end,
            dead = function() return false end, threat = function() return 1 end}
        local quests = {GetQuestObjectives = function() return {{finished = false}} end}
        equal(Presence.Engaged(units, {[1] = {Point(.1)}}, {q}, quests)[1].npcID, 123)
        units.threat = function() return 0 end equal(next(Presence.Engaged(units, {[1] = {Point(.1)}}, {q}, quests)), nil)
        units.same = function(_, other) return other == "pet" end assert(Presence.Engaged(units, {[1] = {Point(.1)}}, {q}, quests)[1])
        quests.GetQuestObjectives = function() return {{finished = true}} end equal(next(Presence.Engaged(units, {[1] = {Point(.1)}}, {q}, quests)), nil)
        equal(Presence.CreatureID("Player-1-123"), nil) equal(Presence.CreatureID("GameObject-0-1-2-3-123-0"), nil)
    end)
    test("Unavailable or restricted unit identities never become a quest match", function()
        local units = {guid = function() error("restricted") end, canAttack = function() return true end, threat = function() return 2 end}
        equal(next(Presence.Engaged(units, {[1] = {Point(.1)}}, {{id = 1}}, {GetQuestObjectives = function() return {{}} end})), nil)
        equal(Presence.CreatureID(nil), nil) equal(Presence.CreatureID("Creature-malformed"), nil)
    end)
    test("Death freezes recovery, corpse coordinates stay pinned across map/target changes, resurrection clears it", function()
        local dead, ghost, map = true, false, 1
        local units = {dead = function() return dead end, ghost = function() return ghost end, either = function() return dead or ghost end}
        local maps = {GetBestMapForUnit = function() return map end, GetPlayerMapPosition = function() return {x = .2, y = .3} end}
        local state = Recovery.Update(nil, maps, {}, units, 0, "PLAYER_DEAD")
        equal(state.active, true) equal(state.deathPoint.x, .2)
        dead, ghost = false, true
        state = Recovery.Update(state, maps, {GetCorpseMapPosition = function() return {x = .7, y = .8} end}, units, 1)
        equal(state.exact, true) equal(state.target.x, .7)
        local fixed = state.target map = 2
        state = Recovery.Update(state, maps, {GetCorpseMapPosition = function() return {x = .1, y = .1} end}, units, 2)
        equal(state.target, fixed) equal(state.target.mapID, 1)
        ghost = false state = Recovery.Update(state, maps, {}, units, 3, "PLAYER_UNGHOST")
        equal(state.active, false) equal(state.target, nil) equal(state.deathPoint, nil)
    end)
    test("Missing corpse coordinates use only the recorded death position, and unknown on-login corpses stay unknown", function()
        local ghost = false
        local units = {dead = function() return not ghost end, ghost = function() return ghost end}
        local state = Recovery.Update(nil, api, {}, units, 0, "PLAYER_DEAD")
        ghost = true state = Recovery.Update(state, api, {}, units, 1)
        equal(state.exact, false) equal(state.target.x, .5)
        local fresh = Recovery.Update(nil, api, {GetCorpseMapPosition = function() return {x = 0, y = 0} end}, units, 1)
        equal(fresh.active, true) equal(fresh.target, nil)
        local unknown = Recovery.Update(fresh, api, {}, {}, 2) equal(unknown.active, true)
    end)
    test("Corpse lookup checks parent maps but bounds loops and accepts an exact point after fallback", function()
        local maps = {GetBestMapForUnit = function() return 2 end, GetPlayerMapPosition = api.GetPlayerMapPosition,
            GetMapInfo = function(id) return {parentMapID = id == 2 and 1 or 2} end}
        local units = {ghost = function() return true end}
        local state = Recovery.Update(nil, maps, {GetCorpseMapPosition = function(id) if id == 1 then return {x = .1, y = .2} end end}, units, 1)
        equal(state.target.mapID, 1) equal(state.exact, true)
        local calls = 0
        state = Recovery.Update(nil, maps, {GetCorpseMapPosition = function() calls = calls + 1 return nil end}, units, 1)
        assert(calls <= 2) equal(state.target, nil)
    end)
    test("Questie combat relations keep creature and object ID spaces separate and work without kill-location arrows", function()
        local goals = {{type = "monster"}, {type = "item"}, {type = "object"}}
        local function Spawn(key, hostile) return {TooltipKey = key, Hostile = hostile, Spawns = {[1] = {{50, 50}}}, Icon = "slay"} end
        local data = {ObjectiveData = {{Type = "monster", Id = 123}, {Type = "item", Id = 9}, {Type = "object", Id = 123}},
            Objectives = {{Type = "monster", Id = 123, spawnList = {[123] = Spawn("m_123", true)}},
                {Type = "item", Id = 9, spawnList = {npc = Spawn("m_456", true), object = Spawn("o_456"), vendor = Spawn("m_789", false)}},
                {Type = "object", Id = 123, spawnList = {[123] = Spawn("o_123")}}}}
        local modules = {ActiveQuests = {Get = function() return {quest = data} end},
            ZoneDB = {GetUiMapIdByAreaId = function() return 1 end}, Phasing = {IsSpawnVisible = function() return true end}}
        local env = setmetatable({Questie = {API = {isReady = true}, ICON_TYPE_SLAY = "slay"},
            QuestieLoader = {ImportModule = function(_, name) return modules[name] end}}, {__index = getfenv()})
        local helper, chunk = {}, assert(loadfile("Core/QuestieIntegration.lua"))
        setfenv(chunk, env)("FQN", helper)
        local apiQ = {GetQuestObjectives = function() return goals end}
        local relations = helper.QuestieIntegration.GetCombatMarkers({{id = 1}}, apiQ)
        local ids = {} for _, relation in ipairs(relations[1]) do ids[relation.npcID] = true end
        equal(ids[123], true) equal(ids[456], true) equal(ids[789], nil)
        local markers = helper.QuestieIntegration.GetObjectiveMarkers({{id = 1}}, apiQ, {[1] = true}, false)
        for _, point in ipairs(markers[1]) do assert(point.objectiveIndex ~= 1) end
        goals[1].finished, goals[2].finished = true, true
        equal(next(helper.QuestieIntegration.GetCombatMarkers({{id = 1}}, apiQ)), nil)
    end)
    test("Synthetic secret values are rejected before GUID parsing or threat comparisons", function()
        local secret, reads = {}, 0
        local env = setmetatable({issecretvalue = function(value) return value == secret end}, {__index = getfenv()})
        local helper, chunk = {}, assert(loadfile("Navigation/ObjectivePresence.lua"))
        setfenv(chunk, env)("FQN", helper)
        equal(helper.ObjectivePresence.CreatureID(secret), nil)
        local units = {canAttack = function() return true end, threat = function() return secret end,
            guid = function() reads = reads + 1 return secret end}
        equal(next(helper.ObjectivePresence.Engaged(units, {[1] = {Point(.1)}}, {{id = 1}}, {})), nil)
        equal(reads, 0)
    end)
end
