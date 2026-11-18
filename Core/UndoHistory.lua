local _, addon = ...
local History = {}
addon.UndoHistory = History
function History.Copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = History.Copy(item) end
    return result
end
function History.Same(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for key, value in pairs(a) do if not History.Same(value, b[key]) then return false end end
    for key in pairs(b) do if a[key] == nil then return false end end
    return true
end
function History.New(limit, changed)
    local self = {entries = {}, limit = limit or 20}
    function self:Push(label, restore)
        self.entries[#self.entries + 1] = {label = label, restore = restore}
        if #self.entries > self.limit then table.remove(self.entries, 1) end
        if changed then changed() end
    end
    function self:Capture(label, get, set, before, after)
        before, after = History.Copy(before), History.Copy(after)
        if History.Same(before, after) then return end
        self:Push(label, function()
            if not History.Same(get(), after) then return false end
            set(History.Copy(before))
            return true
        end)
    end
    function self:Undo()
        local entry = self.entries[#self.entries]
        if not entry then return false, addon.L.UndoEmpty end
        local ok, restored = pcall(entry.restore)
        if not ok or restored == false then return false, addon.L.UndoConflict end
        table.remove(self.entries)
        if changed then changed() end
        return true, entry.label
    end
    function self:Discard()
        table.remove(self.entries)
        if changed then changed() end
    end
    return self
end
