local _, addon = ...

-- Transient hover state is shared by map pins and tracker rows, never selection.
local Hover = {listeners = {}, ids = {}}
addon.QuestHover = Hover
function Hover.Subscribe(callback) Hover.listeners[#Hover.listeners + 1] = callback end
function Hover.Refresh() for _, callback in ipairs(Hover.listeners) do callback(Hover.ids) end end
function Hover.Set(owner, ids) Hover.owner, Hover.ids = owner, ids or {} Hover.Refresh() end
function Hover.Clear(owner) if Hover.owner == owner then Hover.owner, Hover.ids = nil, {} Hover.Refresh() end end

local Time = {}
addon.TravelTime = Time
local function Number(value)
    return not (issecretvalue and issecretvalue(value)) and type(value) == "number"
        and value == value and value >= 0 and value < math.huge
end
function Time.Estimate(yards, mode, mounted, speed)
    if not Number(yards) then return end
    local pace = mode == "mount60" and 11.2 or mode == "mount100" and 14 or 7
    if (not mode or mode == "auto") and mounted and Number(speed) and speed >= 7 then pace = speed end
    return math.ceil(yards / pace / 5) * 5
end
function Time.Describe(yards, settings)
    if settings.showTravelTime == false then return end
    local mounted = IsMounted and IsMounted()
    local speed
    if GetUnitSpeed then local _, runSpeed = GetUnitSpeed("player") speed = runSpeed end
    local seconds = Time.Estimate(yards, "auto", mounted, speed)
    if not seconds then return end
    return addon.L.TravelTimeEstimate:format(math.floor(seconds / 60), seconds % 60)
end

-- An advisory uses distinct, suitable quests in a bounded nearby cluster.
-- It never changes the active quest or recommendation ordering.
addon.ZoneSuggestion = {}
function addon.ZoneSuggestion.Find(groups, currentID, blocked, currentYards)
    if blocked or not currentID or (currentYards and currentYards <= 500) then return end
    local current
    for _, group in ipairs(groups or {}) do if group.id == currentID then current = group break end end
    local best
    for _, group in ipairs(groups or {}) do
        local count = group.clusterSuitable or 0
        local yards = group.clusterYards or group.yards
        local currentDistance = current and (current.clusterYards or current.yards)
        if group.id and group.id ~= currentID and count >= 3 and yards and yards <= 3500
            and (not currentDistance or yards + 300 < currentDistance)
            and (not best or count > best.clusterSuitable or (count == best.clusterSuitable and yards < (best.clusterYards or best.yards))) then
            best = group
        end
    end
    return best
end

local Compare = {}
addon.RewardComparison = Compare
local slots = {INVTYPE_HEAD={1}, INVTYPE_NECK={2}, INVTYPE_SHOULDER={3}, INVTYPE_CHEST={5},
    INVTYPE_ROBE={5}, INVTYPE_WAIST={6}, INVTYPE_LEGS={7}, INVTYPE_FEET={8}, INVTYPE_WRIST={9},
    INVTYPE_HAND={10}, INVTYPE_FINGER={11,12}, INVTYPE_TRINKET={13,14}, INVTYPE_CLOAK={15},
    INVTYPE_SHIELD={17}, INVTYPE_HOLDABLE={17}, INVTYPE_RANGED={18}, INVTYPE_RANGEDRIGHT={18}, INVTYPE_THROWN={18}}
local stats = {"ITEM_MOD_STRENGTH_SHORT", "ITEM_MOD_AGILITY_SHORT", "ITEM_MOD_STAMINA_SHORT",
    "ITEM_MOD_INTELLECT_SHORT", "ITEM_MOD_SPIRIT_SHORT", "RESISTANCE0_NAME"}
function Compare.Read(item, api)
    if not item.itemID or type(api.info) ~= "function" or type(api.stats) ~= "function" or type(api.equipped) ~= "function" then return {} end
    local info = {pcall(api.info, item.itemID)}
    if not info[1] or not info[2] then return {}, true end
    local equip = info[10]
    if not slots[equip] then return {} end
    if type(info[3]) ~= "string" then return {}, true end
    local ok, reward = pcall(api.stats, info[3])
    if not ok or type(reward) ~= "table" then return {}, true end
    local result, pending = {}, false
    for _, slot in ipairs(slots[equip]) do
        local success, link = pcall(api.equipped, "player", slot)
        if success then
            local baseline, known = {}, true
            if link then
                local cached = {pcall(api.info, link)}
                local read, values = pcall(api.stats, link)
                known = cached[1] and cached[2] and read and type(values) == "table"
                baseline = values
            end
            if known then
                local deltas = {}
                for _, key in ipairs(stats) do
                    local a, b = reward[key] or 0, baseline[key] or 0
                    if Number(a) and Number(b) and a ~= b then deltas[#deltas + 1] = {key = key, value = a - b} end
                end
                result[#result + 1] = {slot = slot, deltas = deltas}
            else pending = true end
        end
    end
    return result, pending
end
function Compare.Describe(reward)
    local lines = {}
    local api = {info = GetItemInfo or (C_Item and C_Item.GetItemInfo),
        stats = GetItemStats or (C_Item and C_Item.GetItemStats), equipped = GetInventoryItemLink}
    for _, kind in ipairs({"fixed", "choices"}) do
        for index, item in ipairs(reward[kind] or {}) do
            if index > 6 then break end
            local comparisons, pending = Compare.Read(item, api)
            if pending then addon.QuestRewards.comparisonPending = true end
            for _, comparison in ipairs(comparisons) do
                local values = {}
                for _, delta in ipairs(comparison.deltas) do
                    values[#values + 1] = ("%+d %s"):format(delta.value, _G[delta.key] or delta.key)
                end
                lines[#lines + 1] = addon.L.RewardCompare:format(item.name or tostring(item.itemID), comparison.slot,
                    #values > 0 and table.concat(values, ", ") or addon.L.RewardCompareEqual)
            end
        end
    end
    if #lines > 0 then lines[#lines + 1] = addon.L.RewardCompareScope end
    return #lines > 0 and table.concat(lines, "\n") or nil
end
