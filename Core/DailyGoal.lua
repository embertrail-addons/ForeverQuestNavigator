local _, addon = ...
-- A personal level goal for today (per character). Pure helpers; the estimate of
-- remaining turn-ins uses this session's average known quest XP and is labelled "~".
local Goal = {}
addon.DailyGoal = Goal

function Goal.Today(clock)
    if type(clock) ~= "number" or not date then return nil end
    return date("%Y-%m-%d", clock)
end

-- Returns the stored goal for today, or nil (goals from earlier days expire).
function Goal.Current(store, today)
    local goal = type(store) == "table" and store.goal
    if type(goal) == "table" and type(goal.level) == "number" and goal.day == today then return goal end
end

function Goal.Set(store, level, today, currentLevel)
    level = tonumber(level)
    if not (level and level % 1 == 0 and type(currentLevel) == "number" and level > currentLevel and level <= currentLevel + 20) then
        return false
    end
    store.goal = {level = level, day = today, startLevel = currentLevel}
    return true
end

function Goal.Clear(store) store.goal = nil end

-- level, xp, xpMax: player now. averageXP: known XP per turn-in this session (or nil).
function Goal.Progress(goal, level, xp, xpMax, averageXP)
    if not (goal and type(level) == "number" and type(xp) == "number" and type(xpMax) == "number" and xpMax > 0) then return end
    if level >= goal.level then return {done = true, fraction = 1, levelsLeft = 0} end
    local levelsLeft = goal.level - level - xp / xpMax
    -- Later levels need more XP; the current level's requirement is a lower bound.
    local xpLeft = (xpMax - xp) + (goal.level - level - 1) * xpMax
    local span = math.max(1, goal.level - (goal.startLevel or level))
    local fraction = math.max(0, math.min(1, 1 - levelsLeft / span))
    local turnIns = type(averageXP) == "number" and averageXP > 0 and math.ceil(xpLeft / averageXP) or nil
    return {done = false, fraction = fraction, levelsLeft = levelsLeft, xpLeft = xpLeft, turnIns = turnIns}
end

function Goal.Describe(goal, progress)
    local L = addon.L
    if not goal then return L.GoalNone end
    if not progress then return L.GoalSet:format(goal.level) end
    if progress.done then return L.GoalReached:format(goal.level) end
    local text = L.GoalProgress:format(goal.level, progress.levelsLeft)
    if progress.turnIns then text = text .. " · " .. L.GoalTurnIns:format(progress.turnIns) end
    return text
end
