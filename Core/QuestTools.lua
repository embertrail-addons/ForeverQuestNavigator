local _, addon = ...
local Tools = {}
addon.QuestTools = Tools

local function Count(value)
    return not (issecretvalue and issecretvalue(value)) and type(value) == "number"
        and value >= 0 and value < math.huge and value == math.floor(value)
end

function Tools.Progress(api, id)
    local objectives = api.GetQuestObjectives and api.GetQuestObjectives(id)
    local result = { remaining = 0, monsters = 0, items = 0, other = 0 }
    local fulfilled, required = 0, 0
    for _, goal in ipairs(objectives or {}) do
        if goal.text and goal.text ~= "" then
            local total, done = goal.numRequired, goal.numFulfilled
            if goal.finished then
                total = Count(total) and total > 0 and total or 1
                fulfilled, required = fulfilled + total, required + total
            else
                if not (Count(total) and total > 0 and Count(done) and done <= total) then return end
                local left = total - done
                fulfilled, required = fulfilled + done, required + total
                result.remaining = result.remaining + left
                local kind = goal.type == "monster" and "monsters" or goal.type == "item" and "items" or "other"
                result[kind] = result[kind] + left
            end
        end
    end
    if required == 0 then return end
    result.nearly = result.remaining > 0 and result.remaining <= 3 and fulfilled / required >= 0.75
    result.bonus = result.nearly and (50 - result.remaining * 10) or 0
    return result
end

function Tools.ProgressHint(quest)
    local p = quest.progress
    if not (p and p.nearly) then return end
    local L = addon.L
    local format = p.monsters == p.remaining and L.RemainingEnemies
        or p.items == p.remaining and L.RemainingItems or L.RemainingTasks
    if p.remaining == 1 then
        format = p.monsters == 1 and L.RemainingEnemyOne or p.items == 1 and L.RemainingItemOne or L.RemainingTaskOne
    end
    return L.NearlyDone .. " · " .. format:format(p.remaining)
end

local function Lower(text)
    return tostring(text):gsub("[A-Z]", function(char) return string.char(char:byte() + 32) end)
        :gsub("Ä", "ä"):gsub("Ö", "ö"):gsub("Ü", "ü"):gsub("ẞ", "ß")
end

function Tools.FilterAccess(entries, query, mode, api)
    local result = {}
    query = Lower(query or ""):match("^%s*(.-)%s*$")
    for _, entry in ipairs(entries) do
        local current = api.IsOnQuest and api.IsOnQuest(entry.questID)
        local completed = api.IsQuestFlaggedCompleted and api.IsQuestFlaggedCompleted(entry.questID)
        local include = mode == "all" or mode == "current" and current or mode == "completed" and completed
        local text = Lower(entry.title .. " " .. entry.zone .. " " .. (entry.name or "") .. " " .. entry.questID)
        if include and (query == "" or text:find(query, 1, true)) then result[#result + 1] = entry end
    end
    return result
end

function Tools.ToggleNote(notes, id, title, point, offer)
    if notes[id] then notes[id] = nil return false end
    local order = 0
    for _, note in pairs(notes) do if type(note) == "table" and Count(note.order) then order = math.max(order, note.order) end end
    notes[id] = { id = id, title = title, order = order + 1, offer = offer == true }
    if addon.TravelSupport.ValidPoint(point) then
        notes[id].point = { mapID = point.mapID, x = point.x, y = point.y }
    end
    return true
end

function Tools.Notes(notes, api, resolve)
    local result = {}
    for id, note in pairs(notes) do
        if Count(id) and id > 0 and type(note) == "table" and note.id == id then
            local point = resolve(id) or note.point
            result[#result + 1] = { id = id, title = type(note.title) == "string" and note.title or addon.L.QuestNumber:format(id),
                order = Count(note.order) and note.order or 0, point = addon.TravelSupport.ValidPoint(point) and point or nil,
                status = api.IsOnQuest and api.IsOnQuest(id) and addon.L.NoteAccepted
                    or api.IsQuestFlaggedCompleted and api.IsQuestFlaggedCompleted(id) and addon.L.NoteCompleted or addon.L.NoteLater }
        end
    end
    table.sort(result, function(a, b) if a.order ~= b.order then return a.order < b.order end return a.id < b.id end)
    return result
end
