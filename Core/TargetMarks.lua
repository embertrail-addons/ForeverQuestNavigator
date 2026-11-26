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
    local function Add(name, icon, kind, quest, item, progress, npcID)
        if type(name) ~= "string" or name == "" or #entries >= limit then return end
        local key = name .. "#" .. icon
        if seen[key] then return end
        seen[key] = true
        entries[#entries + 1] = {name = name, icon = icon, kind = kind, questID = quest.id, title = quest.title,
            item = item, progress = progress, npcID = npcID}
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
                    Add(source.name, Marks.SKULL, source.item and "loot" or "kill", quest, source.item, source.progress, source.npcID)
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
            .. ":" .. tostring(entry.respawn) .. ":" .. tostring(entry.danger)
    end
    return table.concat(parts, "|")
end

-- Targets by exact name, then marks with /tm inside the same secure click. /tm works on
-- clients where calling SetRaidTarget from addon code is restricted (retail 12.0 and later).
-- The target is cleared first and /tm only runs with a target ([exists]): when the NPC is
-- not nearby, nothing is marked (no "can't do that" error, no wrong mark on an old target).
Marks.NAME_PREFIX = "/cleartarget\n/targetexact "
function Marks.MarkLine(icon) return "\n/tm [exists] " .. icon end
function Marks.Macro(name, icon)
    local text = Marks.NAME_PREFIX .. name
    if icon then text = text .. Marks.MarkLine(icon) end
    return text
end

-- Secure click snippet (runs in WoW's restricted environment, also in combat): each click
-- moves on to the next living candidate unit (nameplate tokens with the quest mob's name,
-- set out of combat) and marks it with /tm; without candidates it targets by exact name.
-- Attributes: fqn-name, fqn-icon, fqn-count, fqn-unit1..n, fqn-index.
Marks.CYCLE_SNIPPET = [[
if down then return end
local name, icon = self:GetAttribute("fqn-name"), self:GetAttribute("fqn-icon")
if not name then return end
local text = "/cleartarget\n/targetexact " .. name
local count = self:GetAttribute("fqn-count") or 0
local index = self:GetAttribute("fqn-index") or 0
for step = 1, count do
    index = index % count + 1
    local unit = self:GetAttribute("fqn-unit" .. index)
    if unit and UnitExists(unit) and not (UnitIsDead and UnitIsDead(unit)) then text = "/target " .. unit break end
end
self:SetAttribute("fqn-index", index)
if icon then text = text .. "\n/tm [exists] " .. icon end
self:SetAttribute("macrotext", text)
]]

-- Out of combat: store name, icon and candidate units on a cycling button.
function Marks.SetCycle(button, name, icon, units)
    button:SetAttribute("fqn-name", name)
    button:SetAttribute("fqn-icon", icon)
    local previous = button.fqnCount or 0
    units = units or {}
    for index, unit in ipairs(units) do button:SetAttribute("fqn-unit" .. index, unit) end
    for index = #units + 1, previous do button:SetAttribute("fqn-unit" .. index, nil) end
    button.fqnCount = #units
    button:SetAttribute("fqn-count", #units)
    button:SetAttribute("macrotext", name and Marks.Macro(name, icon) or "")
end

-- Wraps the button's click with the cycling snippet when the client offers secure handlers.
function Marks.WrapCycle(button, handler)
    if not (SecureHandlerWrapScript and handler) then return false end
    SecureHandlerWrapScript(button, "OnClick", handler, Marks.CYCLE_SNIPPET)
    return true
end

-- Marking from addon code (without a click) is only used where the client allows it:
-- not on clients with secret values (12.0+), and never again once WoW reported it blocked.
function Marks.ScriptMarkAllowed()
    if Marks.scriptBlocked then return false end
    return issecretvalue == nil and SetRaidTarget ~= nil
end

-- ADDON_ACTION_BLOCKED / ADDON_ACTION_FORBIDDEN for our own SetRaidTarget call.
function Marks.NoteBlocked(addonName, action, ownName)
    if addonName == ownName and type(action) == "string" and action:find("SetRaidTarget", 1, true) then
        local first = not Marks.scriptBlocked
        Marks.scriptBlocked = true
        return first
    end
end
