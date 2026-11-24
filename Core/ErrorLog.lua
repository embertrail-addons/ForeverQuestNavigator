local _, addon = ...
-- Remembers Lua errors raised inside FQN's own entry points (events, refresh,
-- tickers) so /fqn problem can include them without BugSack. Errors are still
-- passed to the game's error handler; FQN keeps running.
local Log = {MAX = 10}
addon.ErrorLog = Log

function Log.Attach(store) Log.store = store end

local function Entries()
    if type(Log.store) ~= "table" then Log.store = {} end
    Log.store.entries = type(Log.store.entries) == "table" and Log.store.entries or {}
    return Log.store.entries
end

-- Keeps only the first line and the first FQN file:line of the stack; no player data.
local function Clean(message)
    message = tostring(message or "unknown error"):match("^[^\n]*") or "unknown error"
    message = message:gsub("Interface[/\\]AddOns[/\\]", "")
    return message:sub(1, 240)
end

function Log.Record(where, message, stack, version, clock)
    local entries, text = Entries(), Clean(message)
    for _, entry in ipairs(entries) do
        if entry.message == text and entry.where == where then
            entry.count, entry.last = entry.count + 1, clock or entry.last
            return entry
        end
    end
    local origin = type(stack) == "string" and stack:match("ForeverQuestNavigator[/\\]([%w/\\_]+%.lua:%d+)") or nil
    local entry = {where = tostring(where), message = text, origin = origin, count = 1, version = version,
        first = clock, last = clock}
    table.insert(entries, 1, entry)
    while #entries > Log.MAX do table.remove(entries) end
    return entry
end

-- Runs fn(...) and records an error instead of breaking the caller.
function Log.Call(where, fn, ...)
    local args, count = {...}, select("#", ...)
    local stack
    local ok, result = xpcall(function() return fn(unpack(args, 1, count)) end, function(err)
        stack = debugstack and debugstack(2) or nil
        return err
    end)
    if ok then return result end
    Log.Record(where, result, stack, Log.version, GetServerTime and GetServerTime() or nil)
    local handler = geterrorhandler and geterrorhandler()
    -- Outside the game (tests) there is no error handler: keep failing loudly.
    if not handler then error(result, 0) end
    pcall(handler, result)
end

function Log.Wrap(where, fn)
    return function(...) return Log.Call(where, fn, ...) end
end

function Log.Summary()
    local entries = Entries()
    if #entries == 0 then return {"errors=none"} end
    local lines = {("errors=%d"):format(#entries)}
    for _, entry in ipairs(entries) do
        lines[#lines + 1] = ("- %s x%d [%s]%s %s"):format(entry.where, entry.count, entry.version or "?",
            entry.origin and (" " .. entry.origin) or "", entry.message)
    end
    return lines
end

function Log.Clear() Entries() Log.store.entries = {} end
