local _, addon = ...
local Profiles = {}
addon.AppearanceProfiles = Profiles
Profiles.order = {"minimal", "standard", "detailed"}
Profiles.presets = {
    minimal = {detailMode = "compact", acceptedRows = 2, offerRows = 2, fontPercent = 100,
        opacityPercent = 80, showScreenArrow = true, showQuestXP = false, highContrast = false},
    standard = {detailMode = "detailed", acceptedRows = 2, offerRows = 3, fontPercent = 100,
        opacityPercent = 80, showScreenArrow = true, showQuestXP = true, highContrast = false},
    detailed = {detailMode = "detailed", acceptedRows = 5, offerRows = 5, fontPercent = 110,
        opacityPercent = 80, showScreenArrow = true, showQuestXP = true, highContrast = false},
}
function Profiles.Changes(profile, settings, catalog)
    local values, changes = Profiles.presets[profile], {}
    if not values then return changes end
    for _, entry in ipairs(catalog) do
        if values[entry.key] ~= nil and settings[entry.key] ~= values[entry.key] then
            changes[#changes + 1] = {key = entry.key, name = entry.name, before = settings[entry.key],
                after = values[entry.key], control = entry.control}
        end
    end
    return changes
end
function Profiles.Apply(profile, settings, catalog, history)
    local changes = Profiles.Changes(profile, settings, catalog)
    for _, change in ipairs(changes) do change.control:SetValue(change.after) end
    if history and #changes > 0 then
        history:Push(addon.L.UndoProfile, function()
            for _, change in ipairs(changes) do if settings[change.key] ~= change.after then return false end end
            for _, change in ipairs(changes) do change.control:SetValue(change.before) end
            return true
        end)
    end
    return #changes
end
