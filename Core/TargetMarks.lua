local _, addon = ...
-- Who to target for the current quests: mobs to kill (skull) and NPCs to talk to for
-- accepting or turning in (star). Pure logic; the window in UI/TargetMarkWindow.lua
-- turns each entry into a secure "/targetexact" button.
local Marks = {}
addon.TargetMarks = Marks

Marks.SKULL, Marks.STAR = 8, 1
Marks.LIMIT = 12

-- Fallback without Questie: "Kobold Vermin slain: 3/10" -> "Kobold Vermin".
local KILL_WORDS = {" slain", " killed", " getötet", " besiegt", " erschlagen"}
function Marks.KillName(text)
    if type(text) ~= "string" then return end
    local name = text:gsub("%s*:?%s*%d+%s*/%s*%d+%s*$", "")
    local found
    for _, word in ipairs(KILL_WORDS) do
        if name:sub(-#word) == word then name, found = name:sub(1, -#word - 1), true break end
    end
    name = name:match("^%s*(.-)%s*$")
    if found and name ~= "" then return name end
end

-- Only the quest the navigator shows (shownID) is listed, so the window never mixes in
-- targets of other quests. input: quests, shownID, and lookups:
--   killers(questID) -> {name or {name=, item=}, ...} from Questie (may be nil); item marks
--     a mob that drops a quest item, so every possible dropper can be targeted
--   objectives(questID) -> C_QuestLog-style goals for the text fallback
--   finisher(questID) -> NPC name or nil
function Marks.Collect(input)
    local entries, seen = {}, {}
    local limit = input.limit or Marks.LIMIT
    local function Add(name, icon, kind, quest, item, progress)
        if type(name) ~= "string" or name == "" or #entries >= limit then return end
        local key = name .. "#" .. icon
        if seen[key] then return end
        seen[key] = true
        entries[#entries + 1] = {name = name, icon = icon, kind = kind, questID = quest.id, title = quest.title,
            item = item, progress = progress}
    end
    local quest
    for _, candidate in ipairs(input.quests or {}) do
        if candidate.id == input.shownID then quest = candidate break end
    end
    if not quest then return entries end
    if quest.readyToTurnIn then
        Add(input.finisher and input.finisher(quest.id), Marks.STAR, "turnIn", quest)
    elseif not (quest.disabled or quest.failed) then
        local names = input.killers and input.killers(quest.id)
        if names and #names > 0 then
            for _, source in ipairs(names) do
                if type(source) == "table" then
                    Add(source.name, Marks.SKULL, source.item and "loot" or "kill", quest, source.item, source.progress)
                else Add(source, Marks.SKULL, "kill", quest) end
            end
        else
            for _, goal in ipairs(input.objectives and input.objectives(quest.id) or {}) do
                if goal.type == "monster" and not goal.finished then
                    Add(Marks.KillName(goal.text), Marks.SKULL, "kill", quest, nil, Marks.Progress(goal))
                end
            end
        end
    end
    return entries
end

-- "3/8" from a quest objective, or nil when the numbers are missing.
function Marks.Progress(goal)
    local done, needed = goal and goal.numFulfilled, goal and goal.numRequired
    if type(done) == "number" and type(needed) == "number" and needed > 0 then return done .. "/" .. needed end
    local text = goal and type(goal.text) == "string" and goal.text:match("(%d+%s*/%s*%d+)%s*$")
    return text and text:gsub("%s", "") or nil
end

-- Mob names that drop an item for an open objective (for the loot reminder).
function Marks.LootNames(entries)
    local names = {}
    for _, entry in ipairs(entries or {}) do if entry.kind == "loot" then names[entry.name] = true end end
    return names
end

-- Raid marks change for everyone in the group: solo and in a party anyone may set them,
-- in a raid only the leader or an assistant.
function Marks.MayMark()
    if not (IsInRaid and IsInRaid()) then return true end
    return (UnitIsGroupLeader and UnitIsGroupLeader("player")) or (UnitIsGroupAssistant and UnitIsGroupAssistant("player")) or false
end

-- No marks in dungeons, raids, battlegrounds and arenas.
function Marks.Hidden()
    return IsInInstance and IsInInstance() == true
end

-- Stable text for "did anything change" checks, so secure buttons are only rebuilt when needed.
function Marks.Signature(entries)
    local parts = {}
    for index, entry in ipairs(entries) do
        parts[index] = entry.icon .. ":" .. entry.name .. ":" .. tostring(entry.questID) .. ":" .. tostring(entry.progress)
    end
    return table.concat(parts, "|")
end

function Marks.Macro(name)
    return "/targetexact " .. name
end
