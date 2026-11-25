local _, addon = ...
-- Dungeon quests on entering an instance, and the next turn-in after leaving it.
-- Classic quest logs group dungeon quests under the dungeon's name, which is also
-- what GetInstanceInfo() returns.
local Instance = {}
addon.InstanceQuests = Instance

local function Normalize(text) return type(text) == "string" and text:lower():gsub("^%s+", ""):gsub("%s+$", "") or nil end

-- Open quests whose quest-log header is the instance name.
function Instance.QuestsFor(quests, instanceName)
    local wanted, result = Normalize(instanceName), {}
    if not wanted or wanted == "" then return result end
    for _, quest in ipairs(quests or {}) do
        if Normalize(quest.header) == wanted and not quest.readyToTurnIn then result[#result + 1] = quest end
    end
    return result
end

function Instance.Summary(quests, instanceName, L, limit)
    local found = Instance.QuestsFor(quests, instanceName)
    if #found == 0 then return end
    local titles = {}
    for index, quest in ipairs(found) do
        if index > (limit or 4) then titles[#titles + 1] = "…" break end
        titles[index] = quest.title
    end
    return L.InstanceQuests:format(instanceName, #found, table.concat(titles, ", "))
end

-- First ready turn-in among the ranked quests, with its measured distance if known.
function Instance.NextTurnIn(ranked, measurements, L)
    for _, quest in ipairs(ranked or {}) do
        if quest.readyToTurnIn then
            local measured = measurements and measurements[quest.id]
            local yards = measured and measured.yards
            if yards then return L.InstanceLeftTurnIn:format(quest.title, math.floor(yards + .5)) end
            return L.InstanceLeftTurnInNear:format(quest.title)
        end
    end
end

-- enter/leave tracking: returns "enter", "leave" or nil and updates state.
function Instance.Transition(state, inside, name)
    if inside and state.name ~= name then state.name = name return "enter" end
    if not inside and state.name then state.name = nil return "leave" end
end
