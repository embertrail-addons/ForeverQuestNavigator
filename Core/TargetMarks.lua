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
    local function Add(name, icon, kind, quest, item)
        if type(name) ~= "string" or name == "" or #entries >= limit then return end
        local key = name .. "#" .. icon
        if seen[key] then return end
        seen[key] = true
        entries[#entries + 1] = {name = name, icon = icon, kind = kind, questID = quest.id, title = quest.title, item = item}
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
                    Add(source.name, Marks.SKULL, source.item and "loot" or "kill", quest, source.item)
                else Add(source, Marks.SKULL, "kill", quest) end
            end
        else
            for _, goal in ipairs(input.objectives and input.objectives(quest.id) or {}) do
                if goal.type == "monster" and not goal.finished then Add(Marks.KillName(goal.text), Marks.SKULL, "kill", quest) end
            end
        end
    end
    return entries
end

-- No marks in dungeons, raids, battlegrounds and arenas.
function Marks.Hidden()
    return IsInInstance and IsInInstance() == true
end

-- Stable text for "did anything change" checks, so secure buttons are only rebuilt when needed.
function Marks.Signature(entries)
    local parts = {}
    for index, entry in ipairs(entries) do parts[index] = entry.icon .. ":" .. entry.name .. ":" .. tostring(entry.questID) end
    return table.concat(parts, "|")
end

function Marks.Macro(name)
    return "/targetexact " .. name
end
