local _, addon = ...
-- Remembers quest mobs that drop a quest item and were killed but not looted yet.
-- Kills come from the combat log (PARTY_KILL), loot from LOOT_OPENED. Corpses are
-- forgotten after a few minutes, roughly when they would despawn.
local Loot = {}
addon.LootReminder = Loot

Loot.KEEP_SECONDS = 180

function Loot.New() return {kills = {}} end

-- names: set of mob names that drop an open quest item.
function Loot.Killed(state, guid, name, names, now)
    if type(guid) == "string" and names and names[name] then state.kills[guid] = {name = name, at = now} end
end

function Loot.Looted(state, guid)
    if type(guid) == "string" then state.kills[guid] = nil end
end

-- Number of unlooted corpses still relevant: recent and still needed by an open objective.
function Loot.Count(state, names, now)
    local count = 0
    for guid, kill in pairs(state.kills) do
        if now - kill.at > Loot.KEEP_SECONDS or not (names and names[kill.name]) then state.kills[guid] = nil
        else count = count + 1 end
    end
    return count
end
