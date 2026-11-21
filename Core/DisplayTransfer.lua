local _, addon = ...
local Transfer = {}
addon.DisplayTransfer = Transfer
-- A deliberately small data format. Never evaluate imported text as Lua.
local schema = {
    theme = {graphite = true, parchment = true, midnight = true}, reducedColors = "boolean",
    navigatorLayout = {guided = true, lists = true},
    detailMode = {compact = true, detailed = true},
    acceptedRows = {2, 5}, offerRows = {2, 5}, fontPercent = {80, 140}, opacityPercent = {0, 100},
    navigatorView = {goal = true, quest = true, all = true}, trackerMaxHeight = {360, 1000}, trackerWidth = {330, 640},
    showScreenArrow = "boolean", showDirectionArrow = "boolean", showQuestXP = "boolean",
    showQuestRewards = "boolean", highContrast = "boolean", adaptiveLayout = "boolean",
}
function Transfer.Export(settings)
    local keys, lines = {}, {"FQN-DISPLAY-1"}
    for key in pairs(schema) do keys[#keys + 1] = key end
    table.sort(keys)
    for _, key in ipairs(keys) do
        if key ~= "navigatorLayout" and settings[key] ~= nil then
            local value = key == "navigatorView" and addon.TrackerPresentation.NavigatorView(settings[key]) or settings[key]
            lines[#lines + 1] = key .. "=" .. tostring(value)
        end
    end
    return table.concat(lines, "\n")
end
function Transfer.Parse(text)
    if type(text) ~= "string" or #text > 4096 then return nil end
    text = text:gsub("\r\n", "\n"):match("^%s*(.-)%s*$")
    local header, body = text:match("^([^\n]+)\n(.*)$")
    if header ~= "FQN-DISPLAY-1" then return nil end
    local values, count = {}, 0
    for line in (body .. "\n"):gmatch("([^\n]*)\n") do
        if line ~= "" then
            local key, raw = line:match("^([%a]+)=([%w]+)$")
            local rule = key and schema[key]
            if not rule or values[key] ~= nil then return nil end
            local value
            if rule == "boolean" then
                if raw ~= "true" and raw ~= "false" then return nil end
                value = raw == "true"
            elseif rule[1] then
                value = tonumber(raw)
                if not value or value ~= math.floor(value) or value < rule[1] or value > rule[2] then return nil end
            else
                if not rule[raw] then return nil end
                value = raw
            end
            values[key], count = value, count + 1
        end
    end
    if values.navigatorView then values.navigatorView = addon.TrackerPresentation.NavigatorView(values.navigatorView)
    elseif values.navigatorLayout then values.navigatorView = "all" end
    values.navigatorLayout = nil
    return count > 0 and values or nil
end
function Transfer.Changes(values, settings, catalog)
    local changes = {}
    for _, entry in ipairs(catalog) do
        if schema[entry.key] and values[entry.key] ~= nil and values[entry.key] ~= settings[entry.key] then
            changes[#changes + 1] = {key = entry.key, name = entry.name, before = settings[entry.key],
                after = values[entry.key], control = entry.control}
        end
    end
    return changes
end
function Transfer.Apply(changes, settings, history)
    for _, change in ipairs(changes) do if settings[change.key] ~= change.before then return false end end
    for _, change in ipairs(changes) do change.control:SetValue(change.after) end
    if history and #changes > 0 then
        history:Push(addon.L.DisplayTransfer, function()
            for _, change in ipairs(changes) do if settings[change.key] ~= change.after then return false end end
            for _, change in ipairs(changes) do change.control:SetValue(change.before) end
            return true
        end)
    end
    return true
end
