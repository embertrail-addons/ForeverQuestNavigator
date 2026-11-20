local _, addon = ...
-- Game reads and persistence live here; the workspace model stays testable.
addon.PlanningRuntime = {}
function addon.PlanningRuntime.New(character, settings, actions)
    local function Position()
        local id = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
        local pos = id and C_Map.GetPlayerMapPosition and C_Map.GetPlayerMapPosition(id, "player")
        if not pos or (issecretvalue and issecretvalue(pos))
            or not addon.TemporaryDetour.IsOutdoor(C_Map, Enum and Enum.UIMapType, id) then return end
        local info = C_Map.GetMapInfo(id)
        return addon.TemporaryDetour.New(id, pos.x, pos.y, info and info.name or addon.L.ReturnPoint)
    end
    return addon.PlanningWorkspace.New({
        remember = function() return settings.rememberNavigation ~= false end,
        blocked = function() return addon.DemoMode and addon.DemoMode.IsActive() end,
        save = function(value) character.navigationPlan = value end,
        priority = actions.priority, read = actions.read, select = actions.select,
        destination = actions.destination, restore = actions.restore, map = actions.map,
        prepareStart = actions.prepareStart,
        validatePoint = function(point)
            return addon.TemporaryDetour.IsOutdoor(C_Map, Enum and Enum.UIMapType, point.mapID)
                and addon.TemporaryDetour.Measure(C_Map, point) ~= nil
        end,
        cancelReturn = actions.cancelReturn, changed = actions.changed, position = Position,
        metric = function(marker) return addon.QuestLocation.GetDistanceMetric(C_Map, marker) end,
    }, settings.rememberNavigation ~= false and character.navigationPlan or nil)
end
