local _, addon = ...
local L = addon.L
local View = {}
addon.PickupPlanView = View

local function AreaDetail(area)
    local lines = {addon.PickupPlanning.AreaSummary(area)}
    if (area.missingReturns or 0) > 0 then lines[#lines + 1] = L.TourMissingReturns:format(area.missingReturns) end
    if area.unknownXP > 0 then lines[#lines + 1] = L.PickupUnknownXP:format(area.unknownXP) end
    if #area.followUps > 0 then lines[#lines + 1] = L.PickupFollowUpCount:format(#area.followUps) end
    for _, chain in ipairs(area.followUps) do lines[#lines + 1] = chain.detail end
    lines[#lines + 1] = L.PickupAreaHelp
    return table.concat(lines, "\n")
end

function View.Rows(plan, mode, areaKey)
    plan = plan or {areas = {}, outing = {}, pickups = {}}
    local rows, area = {}, nil
    for _, candidate in ipairs(plan.areas) do
        if candidate.entries[1].quest.id == areaKey then area = candidate break end
    end
    if mode == "areas" and area then
        rows[#rows + 1] = {text = L.PickupAreaBack, back = true, detail = AreaDetail(area)}
        for _, entry in ipairs(area.entries) do
            local quest = entry.quest
            local title = addon.UI.FormatQuestTitle(quest)
            local text = entry.pickup and L.PickupAcceptStep:format(title) or L.PickupObjectiveStep:format(title)
            local detail = {area.zone, AreaDetail(area)}
            if entry.pickup then
                text = text .. "\n" .. L.OfferPickupDistance:format(quest.yards)
                detail[#detail + 1] = L.OfferPickup:format(quest.pickupZone or L.UnknownZone, quest.marker.x * 100, quest.marker.y * 100)
                detail[#detail + 1] = L.OfferObjectiveZone:format(quest.objectiveZone or L.UnknownZone)
                detail[#detail + 1] = quest.objectiveYards and L.OfferObjectiveDistance:format(quest.objectiveYards) or L.OfferTargetUnknown
                detail[#detail + 1] = addon.PickupPlanning.ClassLabel(quest)
                if quest.slotLimited then detail[#detail + 1] = L.PickupSlotLimited end
            end
            rows[#rows + 1] = {text = text, detail = table.concat(detail, "\n"),
                stop = {quest = quest, target = entry.pickup and quest.marker or entry.target, action = entry.pickup and "accept" or "objective"}}
        end
    elseif mode == "areas" then
        for _, candidate in ipairs(plan.areas) do
            local comparison = AreaDetail(candidate)
            if plan.destination then
                comparison = comparison .. "\n" .. (candidate == plan.destination and L.BriefAreaSelected or L.BriefAreaAlternative)
                    .. "\n" .. L.BriefAreaDistance:format(candidate.yards, plan.destination.yards)
            end
            rows[#rows + 1] = {text = L.PickupAreaTitle:format(candidate.zone, candidate.target.x * 100, candidate.target.y * 100)
                .. "\n" .. addon.PickupPlanning.AreaSummary(candidate),
                detail = comparison, areaKey = candidate.entries[1].quest.id}
        end
    else
        for index, stop in ipairs(plan.outing) do
            local title = addon.UI.FormatQuestTitle(stop.quest)
            local text = stop.action == "accept" and L.PickupAcceptStep:format(title)
                or stop.action == "turnIn" and (L.ReadyToTurnIn .. ": " .. title) or L.PickupObjectiveStep:format(title)
            local icon = addon.UI.iconLabels and (addon.UI.ActionIcon(stop.action) .. " ") or ""
            rows[#rows + 1] = {text = index .. ". " .. icon .. text, stop = stop, detail = L.PickupRoundHelp}
        end
        for _, chain in ipairs(plan.followUps or {}) do
            rows[#rows + 1] = {text = addon.UI.FormatQuestTitle(chain.quest) .. "\n" .. (chain.summary or L.UnknownFollowUps),
                detail = chain.detail, stop = chain.stop}
        end
    end
    local summary = mode == "areas" and L.PickupAreaHelp or L.PickupRoundHelp
    if mode == "outing" then
        summary = L.BriefRoundXP:format(plan.roundXP or 0, plan.roundUnknownXP or 0) .. "\n" .. summary
    end
    local space = plan.budget ~= nil and L.PickupCapacity:format(plan.budget) or L.PickupCapacityUnknown
    if (plan.unknown or 0) > 0 then space = space .. " · " .. L.PickupUnknownCount:format(plan.unknown) end
    return rows, space .. "\n" .. summary
end
