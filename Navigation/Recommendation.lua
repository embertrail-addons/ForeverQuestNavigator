local _, addon = ...
local Recommendation = {}
addon.Recommendation = Recommendation

-- The same facts power tooltips and the diagnostic report. Missing data never
-- counts as a zero-length journey or as proof that a quest has no follow-up.
function Recommendation.Describe(quest, measurement, playerLevel, chain)
    local L = addon.L
    local lines = {}
    if quest.readyToTurnIn then lines[#lines + 1] = L.ReadyToTurnIn end
    if measurement then
        lines[#lines + 1] = L.ReasonDistance:format(measurement.yards)
    else
        lines[#lines + 1] = L.UnknownCoordinates
    end
    local difficulty = addon.QuestPrioritizer.GetDifficulty(quest, playerLevel)
    lines[#lines + 1] = difficulty and L["Difficulty_" .. difficulty] or L.UnknownLevel
    if chain then
        lines[#lines + 1] = L.KnownFollowUps:format(#(chain.followUps or {}))
    else
        lines[#lines + 1] = L.UnknownFollowUps
    end
    if quest.elite or quest.group then lines[#lines + 1] = L.GroupQuest end
    return table.concat(lines, "\n")
end

function Recommendation.ScoreOffer(offer)
    local objective = offer.objectiveYards or 1000
    local bonus = offer.nearActiveTarget and (160 - (offer.anchorGap or 0) * 0.2) or 0
    local xpBonus = offer.xp and math.min(75, offer.xp / 50) or 0
    local shared = offer.objectiveMarker and math.min(100, (offer.overlapCount or 0) * 35) or 0
    local approach = offer.objectiveMarker and offer.onApproach and 40 or 0
    return offer.yards + objective + offer.levelPenalty - bonus - xpBonus - shared - approach
end

local function Number(value)
    return type(value) == "number" and value == value and math.abs(value) < math.huge
        and ("%.1f"):format(value) or "unknown"
end

function Recommendation.BuildReport(state)
    local lines = {
        "FQN diagnostic report",
        "version=" .. tostring(state.version or "unknown"),
        "questie=" .. tostring(state.questie or "unknown"),
        "playerLevel=" .. Number(state.playerLevel),
        "playerMap=" .. tostring(state.mapID or "unknown"),
        "mode=" .. (state.held and "held quest" or state.manual and "manual quest" or state.objectiveLock and "manual objective" or "automatic"),
        "activeQuest=" .. tostring(state.activeID or "none"),
    }
    for _, quest in ipairs(state.quests or {}) do
        local measured = state.measurements and state.measurements[quest.id]
        local marker = measured and measured.marker
        local difficulty = addon.QuestPrioritizer.GetDifficulty(quest, state.playerLevel)
        local penalty = addon.QuestPrioritizer.GetLevelPenalty(quest, state.playerLevel)
        local journey = state.journeys and state.journeys[quest.id]
        local distance = addon.QuestPrioritizer.TravelDistance(measured)
        local travel = addon.TravelSupport.PlanningPenalty(quest, journey, state.journeys ~= nil, measured and distance - measured.yards)
        local progress = addon.QuestPrioritizer.GetProgressBonus(quest, state.playerLevel)
        local adjustment = state.adjustments and state.adjustments[quest.id] or 0
        lines[#lines + 1] = ("quest=%s level=%s difficulty=%s turnIn=%s yards=%s levelPenalty=%s distanceScore=%s map=%s x=%s y=%s objective=%s xp=%s returnAllowance=%s journeyTotal=%s progressBonus=%s"):format(
            tostring(quest.id), Number(quest.level), difficulty or "unknown", tostring(quest.readyToTurnIn == true),
            Number(measured and measured.yards), Number(penalty), Number(measured and distance + penalty + travel - progress + adjustment),
            tostring(marker and marker.mapID or "unknown"), Number(marker and marker.x), Number(marker and marker.y),
            tostring(marker and marker.objectiveIndex or "unknown"), Number(addon.QuestLog.GetTurnInXP(quest)),
            Number(travel), Number(journey and journey.totalYards), Number(progress))
        lines[#lines + 1] = "planningAdjustment=" .. Number(adjustment)
    end
    lines[#lines + 1] = "selectionReasons:"
    lines[#lines + 1] = state.reason or "none"
    lines[#lines + 1] = "routeDetails:"
    lines[#lines + 1] = state.route or "none"
    return table.concat(lines, "\n")
end
