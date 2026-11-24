local _, addon = ...
-- Shows automatically opened windows (setup, introduction, update notes, recap)
-- one after another, never in combat or on a taxi. Explicit commands bypass it.
local Queue = {items = {}, active = nil}
addon.NoticeQueue = Queue

-- Lower priority numbers come first; a key is queued at most once.
-- show() opens the window and returns its frame (or nil when nothing was shown).
function Queue.Push(key, priority, show)
    if Queue.active and Queue.active.key == key then return end
    for _, item in ipairs(Queue.items) do if item.key == key then return end end
    Queue.items[#Queue.items + 1] = {key = key, priority = priority or 50, show = show}
    table.sort(Queue.items, function(a, b) return a.priority < b.priority end)
    Queue.Pump()
end

function Queue.Blocked()
    return (InCombatLockdown and InCombatLockdown()) or (UnitOnTaxi and UnitOnTaxi("player")) or false
end

local function Next()
    Queue.active = nil
    Queue.Pump()
end

function Queue.Pump()
    if Queue.active or #Queue.items == 0 then return end
    -- Blocked windows wait; the next game event (combat end, landing) pumps again.
    if Queue.Blocked() then return end
    local item = table.remove(Queue.items, 1)
    local frame = item.show()
    if not (frame and frame.IsShown and frame:IsShown()) then return Queue.Pump() end
    Queue.active = item
    frame.fqnQueueItem = item
    if not frame.fqnQueueHooked then
        frame.fqnQueueHooked = true
        frame:HookScript("OnHide", function(self)
            if Queue.active and Queue.active == self.fqnQueueItem then self.fqnQueueItem = nil Next() end
        end)
    end
end

function Queue.Reset() Queue.items, Queue.active = {}, nil end
