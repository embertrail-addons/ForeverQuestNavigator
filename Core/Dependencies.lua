local _, addon = ...
local L = addon.L

function addon.ReadQuestieStatus(api)
    if not (api and api.IsAddOnLoaded) then
        return L.DependencyUnknown
    end
    if api.DoesAddOnExist and not api.DoesAddOnExist("Questie") then
        return L.DependencyMissing
    end
    local _, loaded = api.IsAddOnLoaded("Questie")
    return loaded and L.DependencyLoaded or L.DependencyUnloaded
end
