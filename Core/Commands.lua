local _, addon = ...
-- Single registry for /fqn commands: slash dispatch, generated help, the command
-- menu and the minimap context menu all read the same entries.
local Commands = {list = {}, byKey = {}}
addon.Commands = Commands

Commands.groups = {"navigation", "quests", "history", "settings", "help", "debug"}

-- entry = {key, group, run(args, raw), label = locale key, args = true when the
-- command accepts text after its key, advanced = hidden in simple mode,
-- hidden = never listed (e.g. the bare /fqn toggle), menu = false to keep it out of menus}
function Commands.Register(entry)
    assert(type(entry.key) == "string" and type(entry.run) == "function", "invalid command")
    local existing = Commands.byKey[entry.key]
    if existing then
        for index, item in ipairs(Commands.list) do
            if item == existing then table.remove(Commands.list, index) break end
        end
    end
    Commands.byKey[entry.key] = entry
    Commands.list[#Commands.list + 1] = entry
    return entry
end

function Commands.Reset()
    Commands.list, Commands.byKey = {}, {}
end

local function Trim(text)
    return (tostring(text or ""):match("^%s*(.-)%s*$"))
end

-- Returns the matching entry and its argument text (original case preserved).
function Commands.Parse(message)
    local raw = Trim(message)
    local command = raw:lower()
    local exact = Commands.byKey[command]
    if exact then return exact, "" end
    local word, rest = command:match("^(%S+)%s+(.+)$")
    local entry = word and Commands.byKey[word]
    if entry and entry.args then
        return entry, Trim(raw:match("^%S+%s+(.-)$"))
    end
end

function Commands.Label(entry)
    local L = addon.L
    return entry.label and L[entry.label] or entry.key
end

function Commands.Visible(simple)
    local visible = {}
    for _, entry in ipairs(Commands.list) do
        if not entry.hidden and not (simple and entry.advanced) then visible[#visible + 1] = entry end
    end
    local order = {}
    for index, group in ipairs(Commands.groups) do order[group] = index end
    local position = {}
    for index, entry in ipairs(Commands.list) do position[entry] = index end
    table.sort(visible, function(a, b)
        local ga, gb = order[a.group] or 99, order[b.group] or 99
        if ga ~= gb then return ga < gb end
        return position[a] < position[b]
    end)
    return visible
end

function Commands.Filter(query, simple)
    local needle = Trim(query):lower()
    local result = {}
    for _, entry in ipairs(Commands.Visible(simple)) do
        local haystack = (entry.key .. " " .. Commands.Label(entry)):lower()
        if needle == "" or haystack:find(needle, 1, true) then result[#result + 1] = entry end
    end
    return result
end

function Commands.Help(simple)
    local L = addon.L
    local lines = {L.SlashHelpHeader}
    for _, entry in ipairs(Commands.Visible(simple)) do
        lines[#lines + 1] = ("/fqn %s%s – %s"):format(entry.key, entry.args and " …" or "", Commands.Label(entry))
    end
    if simple then lines[#lines + 1] = L.SlashHelpAdvanced end
    return table.concat(lines, "\n")
end

function Commands.Dispatch(message, simple)
    local entry, args = Commands.Parse(message)
    if entry then
        entry.run(args, message)
        return true
    end
    print(Commands.Help(simple))
    return false
end
