local _, addon = ...
local Tour, Finder = addon.TourPlan, addon.QuestFinder
local Workspace = {}
addon.PlanningWorkspace = Workspace
function Workspace.New(context, saved)
    local self = {context = context, plan = Tour.New(type(saved) == "table" and saved.plan), pending = type(saved) == "table" and saved or nil}
    if #self.plan.stops == 0 and not (self.pending and (self.pending.priority or self.pending.returnPending)) then self.pending = nil end
    function self:Save()
        if self.context.remember() then
            local id, held = self.context.priority()
            local priority = Tour.Priority(id, held) or (self.pending and self.pending.priority)
            self.context.save((#self.plan.stops > 0 or self.plan.returnPoint or priority) and {
                plan = Tour.Export(self.plan), priority = priority,
                returnPending = (self.plan.running and #self.plan.stops == 0 and self.plan.returnPoint ~= nil)
                    or (self.pending and self.pending.returnPending == true) or false} or nil)
        else self.context.save(nil) self.pending = nil end
    end
    function self:Sync(quests, skipped)
        if not self.pending then Tour.Sync(self.plan, quests, skipped) end
        self:Save()
    end
    function self:Resume()
        if self.context.blocked and self.context.blocked() then return false end
        local data = self.context.read()
        if not data.quests then return false end
        local candidate = Tour.New(self.plan)
        Tour.Sync(candidate, data.quests, data.skipped)
        local priority = Tour.ValidPriority(self.pending and self.pending.priority, data.quests, data.skipped)
        local targetID = priority and priority.id or candidate.stops[1] and candidate.stops[1].id
        local measured = targetID and data.measurements and data.measurements[targetID]
        -- A remembered priority needs a known current target before resuming.
        if targetID and not (measured and measured.marker) then return false end
        if not targetID and not candidate.returnPoint then return false end
        if not targetID and self.context.validatePoint and not self.context.validatePoint(candidate.returnPoint) then return false end
        if priority and self.context.select(priority.id, priority.policy) == false then return false end
        if self.context.prepareStart then self.context.prepareStart() end
        self.plan.stops, self.plan.revision = candidate.stops, self.plan.revision + 1
        self.pending = nil
        if not priority then self.context.select(nil) self.plan.running = #self.plan.stops > 0 or self.plan.returnPoint ~= nil end
        self:Save() self.context.changed() return priority ~= nil or self.plan.running
    end
    function self:Model(query, kind)
        local data = self.context.read()
        local byID = {}
        for _, quest in ipairs(data.quests or {}) do byID[quest.id] = quest end
        local entries = {}
        for index, stop in ipairs(self.preview and self.preview.stops or self.plan.stops) do
            local quest = byID[stop.id] or {id = stop.id}
            local destination = self.context.destination(stop.id)
            entries[#entries + 1] = {quest = quest, index = index, stage = stop.stage,
                target = destination and destination.target, zone = destination and destination.zoneName}
        end
        local all = Finder.Build(data.quests, data.offers, data.skipped, self.context.destination)
        local counts, inTour = {all = #all, active = 0, offer = 0, skipped = 0}, {}
        for _, entry in ipairs(all) do counts[entry.kind] = counts[entry.kind] + 1 end
        for _, stop in ipairs(self.plan.stops) do inTour[stop.id] = true end
        local manualID = self.context.priority()
        return {tour = entries, running = self.plan.running, returnPoint = self.plan.returnPoint,
            pending = self.pending ~= nil, preview = self.preview ~= nil,
            counts = counts, inTour = inTour, manualID = manualID, missingData = data.quests == nil,
            closingCount = data.turnInTour and #data.turnInTour.stops or 0,
            entries = Finder.Filter(all, query, kind)}
    end
    function self:Action(action, value)
        if self.context.blocked and self.context.blocked() then self.status = addon.L.DemoReadOnly return end
        local data = self.context.read()
        self.status = nil
        if (action == "start" or action == "closing") and not data.quests then self.status = addon.L.ResumeUnavailable return end
        if action == "resume" then
            if not self:Resume() then self.status = addon.L.ResumeUnavailable end
            return
        elseif action == "map" then self.context.map(value) return
        elseif action == "priority" then
            if self.context.select(value.quest.id) == false then self.status = addon.L.ResumeUnavailable return end
            self.pending = nil self.plan.running = false
        elseif action == "restore" then self.context.restore(value.quest.id)
        elseif action == "clearPriority" then self.pending = nil self.context.select(nil)
        elseif action == "cancelPreview" then self.preview = nil return
        elseif action == "add" then
            if not Tour.Add(self.plan, value.quest) then self.status = addon.L.TourAddFailed end
        elseif action == "up" then Tour.Move(self.plan, value, -1)
        elseif action == "down" then Tour.Move(self.plan, value, 1)
        elseif action == "remove" then Tour.Remove(self.plan, value)
        elseif action == "preview" then
            local first
            for _, stop in ipairs(self.plan.stops) do
                local measurement = data.measurements and data.measurements[stop.id]
                if measurement and measurement.marker then first = measurement.marker break end
            end
            self.preview = Tour.Preview(self.plan, data.measurements, first and self.context.metric(first)) return
        elseif action == "apply" then
            local applied = Tour.ApplyPreview(self.plan, self.preview)
            if not applied then self.status = addon.L.TourPreviewStale end
            if applied and self.preview.closing then self.plan.running = false self.context.cancelReturn() end
            self.preview = nil
        elseif action == "start" then
            Tour.Sync(self.plan, data.quests, data.skipped)
            if #self.plan.stops == 0 and self.plan.returnPoint and self.context.validatePoint
                and not self.context.validatePoint(self.plan.returnPoint) then self.status = addon.L.ReturnPointUnavailable return end
            if self.context.prepareStart then self.context.prepareStart() end
            self.pending = nil self.context.select(nil)
            self.plan.running = #self.plan.stops > 0 or self.plan.returnPoint ~= nil
        elseif action == "pause" then self.plan.running = false self.context.cancelReturn()
        elseif action == "dismiss" then self.pending = nil self.plan = Tour.New() self.context.cancelReturn()
        elseif action == "returnHere" then
            local point = self.context.position()
            if point then self.plan.returnPoint = point self.context.cancelReturn() else self.status = addon.L.ReturnPointUnavailable end
        elseif action == "clearReturn" then self.plan.returnPoint = nil self.context.cancelReturn()
        elseif action == "closing" then
            local proposed = Tour.New({returnPoint = self.plan.returnPoint})
            for _, stop in ipairs(data.turnInTour and data.turnInTour.stops or {}) do Tour.Add(proposed, stop.quest) end
            local first = proposed.stops[1] and data.measurements and data.measurements[proposed.stops[1].id]
            self.preview = Tour.Preview(proposed, data.measurements, first and first.marker and self.context.metric(first.marker))
            self.preview.revision, self.preview.closing = self.plan.revision, true
            return
        end
        if #self.plan.stops > 0 then self.context.cancelReturn() end
        if action ~= "preview" then self.preview = nil end
        self:Save() self.context.changed()
    end
    function self:ReturnTarget()
        if self.plan.running and #self.plan.stops == 0 then return self.plan.returnPoint end
    end
    function self:Arrived()
        self.plan.running = false self:Save()
    end
    function self:Current() return Tour.Current(self.plan) end
    return self
end
