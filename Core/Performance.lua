local _, addon = ...
local Performance = {enabled = false, sections = {}, skipped = 0}
addon.Performance = Performance
function Performance:Start()
    self.sections, self.skipped = {}, 0
    self.enabled = type(debugprofilestop) == "function"
    return self.enabled
end
function Performance:Begin()
    if self.enabled then return debugprofilestop() end
end
function Performance:Finish(name, started)
    if not started or not self.enabled then return end
    local elapsed = debugprofilestop() - started
    if elapsed < 0 or elapsed >= math.huge then return end
    local section = self.sections[name] or {count = 0, total = 0, maximum = 0, samples = {}, cursor = 0}
    self.sections[name] = section
    section.count, section.total = section.count + 1, section.total + elapsed
    section.maximum = math.max(section.maximum, elapsed)
    section.cursor = section.cursor % 128 + 1 section.samples[section.cursor] = elapsed
end
function Performance:Report()
    local lines = {addon.L.PerformanceTitle, self.enabled and addon.L.PerformanceEnabled or addon.L.PerformanceDisabled,
        addon.L.PerformanceHelp, addon.L.PerformanceSkipped:format(self.skipped)}
    -- Main sections first, then the planning steps and the quest-log refresh.
    local names = {"planning", "direction", "map", "refresh"}
    local extra = {}
    for name in pairs(self.sections) do if name:find("^plan:") then extra[#extra + 1] = name end end
    table.sort(extra)
    for _, name in ipairs(extra) do names[#names + 1] = name end
    for _, name in ipairs(names) do
        local section = self.sections[name]
        if section then
            local samples = {}
            for _, value in ipairs(section.samples) do samples[#samples + 1] = value end
            table.sort(samples)
            lines[#lines + 1] = ("%s: n=%d, mean=%.3f ms, p95(last %d)=%.3f ms, max=%.3f ms"):format(
                name, section.count, section.total / section.count, #samples, samples[math.ceil(#samples * .95)], section.maximum)
        end
    end
    return table.concat(lines, "\n")
end
