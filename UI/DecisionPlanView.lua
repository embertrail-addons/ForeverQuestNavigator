local _, addon = ...
local L = addon.L
local View = {}
addon.DecisionPlanView = View

local function Reward(xp) return xp and L.QuestXPReward:format(xp) or L.UnknownXP end
function View.Rows(model, mode, mapID)
    local brief = model.brief or addon.DecisionBrief.Build(model)
    local rows, summary = {}, L.BriefFactors
    if mode == "closing" then
        summary = L.BriefClosingSummary:format(#brief.closing, brief.xp) .. "\n" .. L.BriefXPHelp
        if brief.returnAdvice then
            summary = L.ReturnToArea:format(brief.returnAdvice.zone, #brief.closing) .. "\n"
                .. L.ReturnFollowUps:format(brief.returnAdvice.followUps) .. " · " .. summary
        end
        if brief.unknownXP > 0 then summary = summary .. "\n" .. L.PickupUnknownXP:format(brief.unknownXP) end
        if (brief.unknownHandIns or 0) > 0 then summary = summary .. "\n" .. L.BriefMissingTargets:format(brief.unknownHandIns) end
        for _, stop in ipairs(brief.closing) do
            local measured = model.measurements and model.measurements[stop.quest.id]
            rows[#rows + 1] = {text = addon.UI.FormatQuestTitle(stop.quest) .. "\n" .. Reward(stop.xp), stop = stop,
                detail = L.BriefClosingHelp .. "\n" .. addon.UI.FormatDistance(measured)}
        end
    elseif mode == "handIns" then
        summary = L.BriefHandInAreas .. "\n" .. L.BriefXPHelp
        if (brief.unknownHandIns or 0) > 0 then summary = summary .. "\n" .. L.BriefMissingTargets:format(brief.unknownHandIns) end
        for _, group in ipairs(brief.handInAreas) do
            if not mapID then
                local detail = L.BriefHandInCount:format(#group.entries, group.xp)
                if group.unknownXP > 0 then detail = detail .. "\n" .. L.PickupUnknownXP:format(group.unknownXP) end
                rows[#rows + 1] = {text = group.zone .. "\n" .. detail, detail = detail, handInKey = group.target.mapID}
            elseif group.target.mapID == mapID then
                rows[#rows + 1] = {text = L.PickupAreaBack, handInBack = true}
                for _, stop in ipairs(group.entries) do
                    rows[#rows + 1] = {text = addon.UI.FormatQuestTitle(stop.quest) .. "\n" .. Reward(stop.xp), stop = stop,
                        detail = L.BriefXPHelp}
                end
            end
        end
    elseif mode == "progress" then
        local ledger = brief.ledger
        summary = L.BriefRoundHelp
        if ledger then
            summary = L.BriefRoundProgress:format(ledger.completed, #ledger.steps) .. "\n" .. summary
            for _, step in ipairs(ledger.steps) do
                rows[#rows + 1] = {text = (step.title or L.QuestNumber:format(step.questID)) .. "\n" .. L["BriefRoundState_" .. step.state],
                    detail = L.BriefRoundHelp .. "\n" .. L["BriefRoundState_" .. step.state]}
            end
        end
    elseif mode == "comparison" then
        summary = brief.evidenceText or L.EvidenceLimited
        rows[#rows + 1] = {text = L.BriefComparison .. "\n" .. summary, detail = brief.comparison or L.ComparisonUnavailable, inspect = true}
        rows[#rows + 1] = {text = L.BriefFactors, detail = brief.comparison or L.ComparisonUnavailable}
    end
    return rows, summary
end
