local _, addon = ...

function addon.ReadDependencyStatus(api)
    if not (api and api.IsAddOnLoaded) then
        return { Questie = "Unknown", TomTom = "Unknown" }
    end

    local status = {}
    for _, name in ipairs({ "Questie", "TomTom" }) do
        if api.DoesAddOnExist and not api.DoesAddOnExist(name) then
            status[name] = "Not installed"
        else
            local _, loaded = api.IsAddOnLoaded(name)
            status[name] = loaded and "Loaded" or "Not loaded"
        end
    end
    return status
end
