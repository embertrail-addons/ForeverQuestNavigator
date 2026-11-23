local _, addon = ...
local Recovery = {}
addon.CorpseNavigation = Recovery
local function Public(value) return not (issecretvalue and issecretvalue(value)) end
local function Read(fn, ...)
    if type(fn) ~= "function" then return end
    local ok, value = pcall(fn, ...)
    if ok and Public(value) then return value end
end
local function Player(api)
    local id = Read(api and api.GetBestMapForUnit, "player")
    local point = id and Read(api.GetPlayerMapPosition, id, "player")
    if type(point) == "table" and Public(point.x) and Public(point.y) then
        local copy = {mapID = id, x = point.x, y = point.y}
        if addon.TravelSupport.ValidPoint(copy) then return copy end
    end
end
function Recovery.Update(previous, api, deathAPI, units, now, event)
    local state = previous or {}
    if event == "PLAYER_DEAD" then state.deathPoint = Player(api) state.target, state.exact = nil, nil end
    local dead, ghost, either = Read(units.dead, "player"), Read(units.ghost, "player"), Read(units.either, "player")
    local active = dead == true or ghost == true or either == true
    if event == "PLAYER_UNGHOST" and not active then return {active = false} end
    local alive = either == false or dead == false and ghost == false
    if not active and not alive then active = state.active == true end
    if not active then return {active = false} end
    state.active, state.ghost = true, ghost == true or ghost == nil and state.ghost == true and dead ~= true
    if state.ghost and (not state.exact) and (not state.retry or now >= state.retry) then
        state.retry = now + 1
        local current, visited, queue = Read(api and api.GetBestMapForUnit, "player"), {}, {}
        if current then queue[#queue + 1] = current end
        if state.deathPoint then queue[#queue + 1] = state.deathPoint.mapID end
        local nextIndex = 1
        while queue[nextIndex] and nextIndex <= 8 do
            local id = queue[nextIndex] nextIndex = nextIndex + 1
            if not visited[id] then
                visited[id] = true
                local pos = Read(deathAPI and deathAPI.GetCorpseMapPosition, id)
                if type(pos) == "table" and Public(pos.x) and Public(pos.y) then
                    local point = {mapID = id, x = pos.x, y = pos.y}
                    if addon.TravelSupport.ValidPoint(point) then state.target, state.exact = point, true break end
                end
                local info = Read(api and api.GetMapInfo, id)
                if type(info) == "table" and Public(info.parentMapID) and type(info.parentMapID) == "number" and info.parentMapID > 0 then
                    queue[#queue + 1] = info.parentMapID
                end
            end
        end
        if not state.target and state.deathPoint then state.target, state.exact = state.deathPoint, false end
    end
    return state
end
