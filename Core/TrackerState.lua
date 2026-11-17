local _, addon = ...
local State = {}
addon.TrackerState = State

function State.Arrival(previous, quest, measurement)
    local marker = measurement and measurement.marker
    if not (quest and marker) then return nil, false end
    local key = table.concat({ quest.id, marker.mapID, marker.objectiveIndex or 0,
        marker.x, marker.y, quest.readyToTurnIn and "turnIn" or "objective" }, ":")
    local wasHere = previous and previous.key == key and previous.arrived
    local arrived = measurement.yards <= (wasHere and 20 or 12)
    return { key = key, arrived = arrived }, arrived
end

function State.Progress(quests, api, skipped)
    local result = { open = 0, turnIns = 0, unknown = 0 }
    for _, quest in ipairs(quests or {}) do
        if not (quest.failed or quest.disabled or (skipped and skipped[quest.id])
            or (quest.special and not quest.readyToTurnIn)) then
            if quest.readyToTurnIn then
                result.turnIns = result.turnIns + 1
            else
                local objectives = api.GetQuestObjectives and api.GetQuestObjectives(quest.id)
                if not objectives or #objectives == 0 then result.unknown = result.unknown + 1 end
                for _, objective in ipairs(objectives or {}) do
                    if not objective.finished and objective.text and objective.text ~= "" then
                        result.open = result.open + 1
                    end
                end
            end
        end
    end
    return result
end

function State.HoldEnded(hold, quests)
    for _, quest in ipairs(quests or {}) do
        if quest.id == hold.id then
            return quest.failed or quest.disabled or (not hold.turnIn and quest.readyToTurnIn == true)
        end
    end
    return true
end

-- Remember recommendations for this session so crossing the radius boundary
-- or refreshing Questie cannot repeatedly announce the same offer.
function State.NewOffers(seen, offers)
    local fresh = {}
    local initial = seen == nil
    seen = seen or {}
    for _, offer in ipairs(offers or {}) do
        if offer.recommended and offer.id then
            if not initial and not seen[offer.id] then fresh[offer.id] = true end
            seen[offer.id] = true
        end
    end
    return seen, fresh
end
