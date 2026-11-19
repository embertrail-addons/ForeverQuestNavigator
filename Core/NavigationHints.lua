local _, addon = ...
local Hints = {}
addon.NavigationHints = Hints
function Hints.TargetKind(marker)
    if not marker then return "unknown" end
    if marker.accessPoint then return "access" end
    if marker.outdoorTurnIn or marker.turnInName then return "giver" end
    if marker.targetKind == "area" then return "area" end
    if marker.targetKind == "object" then return "object" end
    return "approximate"
end
function Hints.TargetText(marker) return addon.L["TargetQuality_" .. Hints.TargetKind(marker)] end
function Hints.NextAction(quest, marker)
    if quest and quest.readyToTurnIn then return addon.L.ArrivalTurnIn end
    local kind = Hints.TargetKind(marker)
    return kind == "access" and addon.L.ArrivalAccess or kind == "area" and addon.L.ArrivalArea or addon.L.ArrivalObjective
end
function Hints.Why(snapshot, quest, manual)
    if manual then return addon.L.WhyManual end
    if snapshot.decision == "levelUp" then return addon.L.WhyLevelUp end
    if (snapshot.decision == "followUp" or snapshot.decision == "outing") and (snapshot.decisionSaving or 0) > 0 then
        return addon.L.WhySaving:format(math.floor(snapshot.decisionSaving + .5))
    end
    for _, bundle in ipairs(snapshot.bundles or {}) do
        for _, entry in ipairs(bundle.entries) do if entry.quest.id == quest.id then return addon.L.WhyShared:format(#bundle.entries) end end
    end
    if quest.readyToTurnIn then return addon.L.WhyTurnIn end
    if not (snapshot.measurements and snapshot.measurements[quest.id]) then return addon.L.WhyUnknown end
    return addon.L.WhyLevelDistance
end
function Hints.Change(previous, quest, snapshot, manual)
    if not previous or previous.id == quest.id then return end
    if manual then return addon.L.WhyManual end
    if quest.readyToTurnIn then return addon.L.ChangeTurnIn end
    local previousPresent
    for _, candidate in ipairs(snapshot.ranked or {}) do if candidate.id == previous.id then previousPresent = true break end end
    if not previousPresent then return addon.L.ChangePreviousGone end
    return addon.L.ChangeRecommendation .. ": " .. Hints.Why(snapshot, quest)
end
