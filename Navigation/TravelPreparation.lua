local _, addon = ...
addon.TravelPreparation = {}

function addon.TravelPreparation.Describe(measurement, settings, containers, durability, bagSlots)
    if settings.showTravelPreparation == false or not measurement or not measurement.yards
        or measurement.yards < 1500 then return end
    local lines, free, known = {}, 0, false
    if containers and containers.GetContainerNumFreeSlots then
        for bag = 0, bagSlots or 4 do
            local slots, family = containers.GetContainerNumFreeSlots(bag)
            if type(slots) == "number" and family == 0 then free, known = free + slots, true end
        end
    end
    if known and free <= 3 then lines[#lines + 1] = addon.L.PrepareBags:format(free) end
    if durability then
        for slot = 1, 19 do
            local current, maximum = durability(slot)
            if type(current) == "number" and type(maximum) == "number" and maximum > 0 and current / maximum <= 0.25 then
                lines[#lines + 1] = addon.L.PrepareRepair
                break
            end
        end
    end
    if #lines > 0 then return table.concat(lines, "\n") end
end
