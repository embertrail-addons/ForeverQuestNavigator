local _, addon = ...
addon.QuestActions = {}

-- State transitions have no frame, map or timer dependencies. Bootstrap applies
-- the returned effects once, keeping UI callbacks and key bindings consistent.
function addon.QuestActions.Apply(state, action, value)
    local effect = {}
    local function Select(id)
        state.held, state.manual, state.lock, state.outing = nil, id, nil, nil
        if state.flying then state.flightID = id end
        effect.selection, effect.refresh = true, true
    end
    local quest = state.quest
    if action == "select" then Select(value)
    elseif action == "prioritize" then
        if type(value) ~= "table" or not value.id then return effect end
        Select(value.id)
        state.held = {id = value.id, turnIn = value.turnIn == true, policy = value.turnIn and "turnIn" or "complete"}
    elseif action == "hold" then
        if state.held then Select(nil)
        elseif quest then Select(quest.id) state.held = { id = quest.id, turnIn = quest.readyToTurnIn == true } end
    elseif action == "objective" or action == "avoid" then
        local targets = quest and state.distances and state.distances[quest.id]
        if value and not (targets and targets[value]) then return effect end
        if action == "avoid" then
            if not value then return effect end
            local avoided = state.avoided[quest.id] or {}
            avoided[value] = not avoided[value] or nil
            state.avoided[quest.id] = avoided
            if state.lock and state.lock.questID == quest.id and state.lock.index == value then state.lock = nil end
            state.previous[quest.id], state.outing = nil, nil
        else
            if value and state.avoided[quest.id] then state.avoided[quest.id][value] = nil end
            if not value or (state.lock and state.lock.questID == quest.id and state.lock.index == value) then state.lock = nil
            else state.lock = { questID = quest.id, index = value } end
        end
        effect.measure = true
    elseif action == "restoreObjectives" then
        state.avoided, state.outing = {}, nil
        effect.measure = true
    elseif action == "skip" then
        if not value or state.skipped[value.id] then return effect end
        state.order = state.order + 1
        state.skipped[value.id] = { quest = { id = value.id, title = value.title, level = value.level,
            elite = value.elite, group = value.group }, order = state.order }
        if state.manual == value.id then state.manual, state.held = nil, nil end
        effect.undo, effect.refresh = value, true
    elseif action == "restore" then state.skipped[value] = nil effect.refresh = true
    elseif action == "resetSkips" then
        for id in pairs(state.skipped) do state.skipped[id] = nil end
        state.order, effect.refresh = 0, true
    end
    return effect
end
