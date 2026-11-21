local _, addon = ...
local Ledger = {}
addon.OutingLedger = Ledger

function Ledger.Start(plan, completed)
    local ledger = {steps = {}, completed = 0, changed = 0}
    for _, stop in ipairs(plan and plan.outing or {}) do
        ledger.steps[#ledger.steps + 1] = {questID = stop.quest.id, title = stop.quest.title,
            action = stop.action, objectiveIndex = stop.target and stop.target.objectiveIndex,
            state = "pending", wasCompleted = completed and completed(stop.quest.id)}
    end
    return #ledger.steps > 0 and ledger or nil
end
function Ledger.Sync(ledger, quests, objectives, completed)
    if not ledger or not quests then return ledger end
    local byID = {}
    for _, quest in ipairs(quests) do byID[quest.id] = quest end
    ledger.completed, ledger.changed = 0, 0
    for _, step in ipairs(ledger.steps) do
        local quest = byID[step.questID]
        local done = not step.wasCompleted and completed and completed(step.questID)
        if step.state ~= "done" then
            if step.action == "accept" and (quest or done) then step.state = "done"
            elseif step.action == "turnIn" then
                if done then step.state = "done"
                elseif quest then step.seen = true step.state = "pending"
                elseif step.seen then step.state = "changed" end
            elseif step.action == "objective" then
                local goals = quest and objectives and objectives(step.questID)
                if done or (quest and quest.readyToTurnIn) or (goals and step.objectiveIndex and goals[step.objectiveIndex] and goals[step.objectiveIndex].finished) then
                    step.state = "done"
                elseif quest then step.seen = true step.state = "pending"
                elseif step.seen then step.state = "changed" end
            end
        end
        if step.state == "done" then ledger.completed = ledger.completed + 1 end
        if step.state == "changed" then ledger.changed = ledger.changed + 1 end
    end
    return ledger
end
