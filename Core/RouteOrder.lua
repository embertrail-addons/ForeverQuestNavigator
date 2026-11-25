local _, addon = ...
-- Improves a stop order by repeated local moves: reversing a section (2-opt) and
-- moving one stop elsewhere (or-opt). Coordinate distances only; it never claims a
-- terrain route or a globally optimal order. Unknown legs leave the order unchanged.
local RouteOrder = {}
addon.RouteOrder = RouteOrder

-- cost(stops) -> total yards or nil when a leg is unknown.
-- valid(stops) -> false when an order breaks precedence or capacity (optional).
-- Returns the improved list, the starting cost and the final cost.
function RouteOrder.Improve(stops, cost, valid, maxPasses)
    local order = {}
    for index, stop in ipairs(stops) do order[index] = stop end
    local best = cost(order)
    if not best or #order < 2 then return order, best, best end
    local start = best
    local function Try(candidate)
        if valid and not valid(candidate) then return false end
        local value = cost(candidate)
        if value and value + 1 < best then order, best = candidate, value return true end
        return false
    end
    for _ = 1, maxPasses or 12 do
        local improved = false
        for first = 1, #order - 1 do
            for last = first + 1, #order do
                local candidate = {}
                for index, stop in ipairs(order) do candidate[index] = stop end
                for index = first, last do candidate[index] = order[last - (index - first)] end
                if Try(candidate) then improved = true end
            end
        end
        for from = 1, #order do
            for to = 1, #order do
                if from ~= to then
                    local candidate = {}
                    for index, stop in ipairs(order) do candidate[index] = stop end
                    local moved = table.remove(candidate, from)
                    table.insert(candidate, to, moved)
                    if Try(candidate) then improved = true end
                end
            end
        end
        if not improved then break end
    end
    return order, start, best
end
