local _, addon = ...
local Report = {}
addon.ProblemReport = Report
local function Number(value)
    return not (issecretvalue and issecretvalue(value)) and type(value) == "number" and value == value and math.abs(value) < math.huge
end
local function Value(value) return Number(value) and tostring(value) or "unknown" end
function Report.Build(state)
    local quest, marker = state.quest or {}, state.marker or {}
    local decision = ({ranking=true, outing=true, followUp=true, levelUp=true, tour=true, excursion=true})[state.decision] and state.decision or "unknown"
    local version = type(state.version) == "string" and state.version:match("^%d+%.%d+%.%d+$") or "unknown"
    local lines = {"FQN problem report", "version=" .. version, "questID=" .. Value(quest.id),
        "playerLevel=" .. Value(state.level), "manual=" .. tostring(state.manual == true), "decision=" .. decision,
        "targetMap=" .. Value(marker.mapID), "targetX=" .. Value(marker.x), "targetY=" .. Value(marker.y),
        "objective=" .. Value(marker.objectiveIndex), "distanceYards=" .. Value(state.yards),
        "questieLoaded=" .. tostring(state.questieLoaded == true), "questieReady=" .. tostring(state.questieReady == true),
        "markerCount=" .. Value(state.markerCount), "tourStops=" .. Value(state.tourStops)}
    for _, line in ipairs(type(state.errors) == "table" and state.errors or {}) do lines[#lines + 1] = tostring(line) end
    for _, line in ipairs({"", addon.L.ProblemReportPrivacy, "", addon.L.ProblemReportQuestions}) do lines[#lines + 1] = line end
    return table.concat(lines, "\n")
end
