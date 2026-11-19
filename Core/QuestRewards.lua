local _, addon = ...
local Rewards = { cache = {} }
addon.QuestRewards = Rewards
local function Integer(value, minimum, maximum)
    return not (issecretvalue and issecretvalue(value)) and type(value) == "number" and value == math.floor(value)
        and value >= minimum and value <= maximum
end
local function Query(fn, ...)
    if type(fn) ~= "function" then return end
    local ok, a, b, c, d, e, f = pcall(fn, ...)
    if ok then return a, b, c, d, e, f end
end

-- All queries use the requested quest ID. Never select a quest or choose a reward.
function Rewards.Read(api, id)
    local result = {fixed = {}, choices = {}}
    local money = Query(api.money, id)
    if Integer(money, 0, 1000000000000) then result.money = money end
    for _, kind in ipairs({"fixed", "choices"}) do
        local count = Query(api[kind .. "Count"], id)
        if Integer(count, 0, 1000) then
            result[kind .. "Count"] = count
            for index = 1, math.min(16, count) do
                local name, _, quantity, _, _, itemID = Query(api[kind], index, id)
                if not Integer(itemID, 1, 1000000000) then itemID = nil end
                if type(name) ~= "string" or name == "" then name = itemID and Query(api.itemName, itemID) or nil end
                if type(name) ~= "string" or name == "" then
                    name = nil
                    if itemID then result.pending = true end
                end
                result[kind][index] = {name = name, itemID = itemID, quantity = Integer(quantity, 1, 1000000) and quantity or nil}
            end
        end
    end
    return result
end

function Rewards.Client(id)
    if not Rewards.cache[id] then
        local canShow = C_QuestLog and C_QuestLog.ShouldShowQuestRewards
        if canShow and Query(canShow, id) ~= true then return {fixed = {}, choices = {}} end
        Rewards.cache[id] = Rewards.Read({money = GetQuestLogRewardMoney, fixedCount = GetNumQuestLogRewards,
            choicesCount = GetNumQuestLogChoices, fixed = GetQuestLogRewardInfo, choices = GetQuestLogChoiceInfo,
            itemName = GetItemInfo}, id)
    end
    return Rewards.cache[id]
end

function Rewards.Clear() Rewards.cache = {} Rewards.comparisonPending = nil end
function Rewards.HasPending()
    if Rewards.comparisonPending then return true end
    for _, reward in pairs(Rewards.cache) do if reward.pending then return true end end
    return false
end
function Rewards.Describe(reward)
    local L, lines = addon.L, {}
    if reward.money and reward.money > 0 then
        local gold, silver, copper = math.floor(reward.money / 10000), math.floor(reward.money / 100) % 100, reward.money % 100
        lines[#lines + 1] = L.RewardMoney .. ": " .. L.MoneyAmount:format(gold, silver, copper)
    end
    for _, kind in ipairs({"fixed", "choices"}) do
        local count = reward[kind .. "Count"]
        if count and count > 0 then
            lines[#lines + 1] = kind == "fixed" and L.RewardGuaranteed or L.RewardChooseOne
            for index = 1, math.min(6, count) do
                local item = reward[kind][index]
                local name = item.name or (item.itemID and L.RewardItemID:format(item.itemID)) or L.RewardItemPending
                local amount = item.quantity and (" x" .. item.quantity) or (" · " .. L.RewardCountUnknown)
                lines[#lines + 1] = name .. amount
            end
            if count > 6 then lines[#lines + 1] = L.MoreRewardItems:format(count - 6) end
        end
    end
    if reward.pending then lines[#lines + 1] = L.RewardItemPending end
    if #lines == 0 then
        if reward.money == 0 and reward.fixedCount == 0 and reward.choicesCount == 0 then return L.NoExtraRewards end
        return L.RewardsUnavailable
    end
    if reward.money == nil or reward.fixedCount == nil or reward.choicesCount == nil then lines[#lines + 1] = L.RewardsPartial end
    return table.concat(lines, "\n")
end
