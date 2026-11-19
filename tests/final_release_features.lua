return function(test, addon, equal, near)
    test("Hover linking is grouped and owner-aware without quest selection", function()
        local first, second, observed = {}, {}, nil
        addon.QuestHover.Subscribe(function(ids) observed = ids end)
        addon.QuestHover.Set(first, {[1] = true, [2] = true})
        equal(observed[1], true) equal(observed[2], true)
        addon.QuestHover.Set(second, {[3] = true})
        addon.QuestHover.Clear(first) equal(observed[3], true)
        addon.QuestHover.Clear(second) equal(next(observed), nil)
    end)
    test("Temporary priorities expire at the chosen completion or turn-in boundary", function()
        local state = {quest = {id = 1}, flying = true}
        local effects = addon.QuestActions.Apply(state, "prioritize", {id = 1})
        equal(state.manual, 1) equal(state.flightID, 1) equal(effects.refresh, true)
        equal(addon.TrackerState.HoldEnded(state.held, {{id = 1}}), false)
        equal(addon.TrackerState.HoldEnded(state.held, {{id = 1, readyToTurnIn = true}}), true)
        addon.QuestActions.Apply(state, "prioritize", {id = 1, turnIn = true})
        equal(addon.TrackerState.HoldEnded(state.held, {{id = 1, readyToTurnIn = true}}), false)
        equal(addon.TrackerState.HoldEnded(state.held, {}), true)
        equal(addon.TrackerState.HoldEnded(state.held, {{id = 1, failed = true}}), true)
        addon.QuestActions.Apply(state, "select", nil) equal(state.held, nil)
    end)
    test("Travel estimates round upwards and mounted speed does not affect walking", function()
        equal(addon.TravelTime.Estimate(700, "auto", false, 14), 100)
        equal(addon.TravelTime.Estimate(700, "auto", true, 14), 50)
        equal(addon.TravelTime.Estimate(701, "auto", true, 14), 55)
        equal(addon.TravelTime.Estimate(0), 0)
        equal(addon.TravelTime.Estimate(-1), nil)
        equal(addon.TravelTime.Estimate(0/0), nil)
        equal(addon.TravelTime.Estimate(math.huge), nil)
        equal(addon.TravelTime.Describe(700, {showTravelTime = false}), nil)
    end)
    test("Zone advisories require a substantial advantage and never interrupt nearby manual work", function()
        local groups = {{id = 10, yards = 2200}, {id = 20, yards = 1200, clusterSuitable = 3}}
        equal(addon.ZoneSuggestion.Find(groups, 10).id, 20)
        equal(addon.ZoneSuggestion.Find(groups, 10, true), nil)
        equal(addon.ZoneSuggestion.Find(groups, 10, false, 100), nil)
        groups[2].yards = 2000 equal(addon.ZoneSuggestion.Find(groups, 10), nil)
        groups[2].yards, groups[2].clusterSuitable = 1000, 2
        equal(addon.ZoneSuggestion.Find(groups, 10), nil)
        equal(addon.ZoneSuggestion.Find(groups, nil), nil)
    end)
    test("Zone clusters count distinct attainable quests rather than distant targets or red objectives", function()
        local api = {GetMapInfo = function(id) return {name = "Zone " .. id, mapType = 3} end,
            GetMapWorldSize = function() return 10000, 10000 end}
        local quests, snapshot = {}, {playerLevel = 30, measurements = {}}
        for id = 1, 5 do
            quests[id] = {id = id, level = id == 4 and 40 or 30}
            snapshot.measurements[id] = {yards = id * 100, marker = {mapID = 20, x = id == 5 and .8 or .1 + id * .01, y = .2}}
        end
        local groups = addon.BuildZoneOverview(api, {Zone = 3}, quests, snapshot)
        equal(groups[1].clusterSuitable, 3)
    end)
    local function EquipmentAPI(equip)
        return {info = function(id)
            if id == 1 then return "Reward", "item:1", nil, nil, nil, nil, nil, nil, equip end
            return "Equipped", id
        end, stats = function(link)
            assert(type(link) == "string", "GetItemStats requires an item link")
            return {ITEM_MOD_STAMINA_SHORT = link == "item:1" and 8 or 5, ITEM_MOD_INTELLECT_SHORT = link == "item:1" and 2 or 4}
        end, equipped = function(_, slot) return "item:" .. slot end}
    end
    test("Reward comparisons use cached item links and preserve positive and negative base-stat differences", function()
        local result, pending = addon.RewardComparison.Read({itemID = 1}, EquipmentAPI("INVTYPE_CHEST"))
        equal(pending, false) equal(result[1].slot, 5)
        equal(result[1].deltas[1].key, "ITEM_MOD_STAMINA_SHORT") equal(result[1].deltas[1].value, 3)
        equal(result[1].deltas[2].value, -2)
        result = addon.RewardComparison.Read({itemID = 1}, EquipmentAPI("INVTYPE_FINGER"))
        equal(#result, 2) equal(result[1].slot, 11) equal(result[2].slot, 12)
    end)
    test("Unknown equipment data never becomes a zero baseline; melee weapons are excluded", function()
        local api = EquipmentAPI("INVTYPE_CHEST")
        api.stats = function() return nil end
        local result, pending = addon.RewardComparison.Read({itemID = 1}, api)
        equal(#result, 0) equal(pending, true)
        api = EquipmentAPI("INVTYPE_CHEST")
        api.info = function(id) if id == 1 then return "Reward", "item:1", nil, nil, nil, nil, nil, nil, "INVTYPE_CHEST" end end
        result, pending = addon.RewardComparison.Read({itemID = 1}, api)
        equal(#result, 0) equal(pending, true)
        result = addon.RewardComparison.Read({itemID = 1}, EquipmentAPI("INVTYPE_2HWEAPON"))
        equal(#result, 0)
        result = addon.RewardComparison.Read({itemID = 1}, {}) equal(#result, 0)
    end)
end
