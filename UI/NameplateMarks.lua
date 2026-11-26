local _, addon = ...
-- Quest marks in the world for the active quest:
--  * real raid target icons are set only by a click or key (/tm in a secure macro, see
--    TargetMarks): addon code calling SetRaidTarget is forbidden on WoW Forever clients.
--  * nameplate badges with progress ("3/8") above every other visible quest mob, so a
--    whole pack is visible at once (setting nameplateMarks; needs nameplates, key V).
--  * loot reminder and respawn estimate: quest mobs seen dying on a nameplate or as the
--    target. The combat log is not used: registering it is forbidden for addons on newer
--    clients and makes WoW block FQN ("Frame:RegisterEvent()").
local Marks = {}
addon.NameplateMarks = Marks

local ICON = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_%d"
local SIZE = 22

local L = addon.L
local byName = {}     -- name -> entry from TargetMarks.Collect
local sharedBy = {}   -- name -> group member whose current quest needs this mob
local lootNames = {}  -- names of mobs that drop an open quest item
local badges = {}     -- nameplate frame -> badge frame
local units = {}      -- unit token -> nameplate frame
local loot = addon.LootReminder.New()
local respawn = addon.Respawn.New()
local driver, settings

local function Now() return GetTime and GetTime() or 0 end

local function Plate(unit)
    return C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit(unit)
end

local function Badge(plate)
    local badge = badges[plate]
    if not badge then
        badge = CreateFrame("Frame", nil, plate)
        badge:SetSize(SIZE, SIZE)
        badge:SetPoint("BOTTOM", plate, "TOP", 0, 2)
        badge.icon = badge:CreateTexture(nil, "OVERLAY")
        badge.icon:SetAllPoints()
        badge.progress = addon.UI.CreateLabel(badge, "GameFontHighlightSmall")
        badge.progress:SetPoint("LEFT", badge, "RIGHT", 2, 0)
        badges[plate] = badge
    end
    return badge
end

local function Alive(unit) return not (UnitIsDead and UnitIsDead(unit)) end

-- Shows or hides the badge for one nameplate unit. A unit carrying a real raid icon needs
-- no badge: Blizzard already draws that icon on its nameplate.
function Marks.Update(unit)
    local plate = units[unit] or Plate(unit)
    if not plate then return end
    units[unit] = plate
    local name = UnitName(unit) or ""
    local entry = Marks.enabled and Alive(unit) and byName[name]
    -- A group member's quest mob: faded skull with the member's name.
    local member = Marks.enabled and not entry and Alive(unit) and sharedBy[name]
    local raidIcon = GetRaidTargetIndex and GetRaidTargetIndex(unit)
    if (entry or member) and not raidIcon then
        local badge = Badge(plate)
        badge.icon:SetTexture(ICON:format(entry and entry.icon or addon.TargetMarks.SKULL))
        badge.icon:SetAlpha(entry and 1 or .55)
        badge.progress:SetText(entry and entry.progress or member or "")
        badge:Show()
    elseif badges[plate] then
        badges[plate]:Hide()
    end
end

function Marks.UpdateAll()
    for unit in pairs(units) do Marks.Update(unit) end
end

-- entries from addon.TargetMarks.Collect; called whenever the active quest's targets change.
function Marks.Set(entries, shared)
    local nextByName = {}
    for _, entry in ipairs(entries or {}) do nextByName[entry.name] = entry end
    byName, lootNames, sharedBy = nextByName, addon.TargetMarks.LootNames(entries), shared or {}
    Marks.UpdateAll()
end

-- Living mobs of that name on visible nameplates.
-- Living nameplate units with one of these names, sorted for a stable cycling order.
function Marks.UnitsFor(names)
    local result = {}
    for unit in pairs(units) do
        local name = UnitName(unit)
        if name and names[name] and Alive(unit) then result[#result + 1] = unit end
    end
    table.sort(result)
    return result
end

function Marks.VisibleAlive(name)
    local count = 0
    for unit in pairs(units) do if UnitName(unit) == name and Alive(unit) then count = count + 1 end end
    return count
end

-- "Respawn ~2 min" while no living mob of that name is in sight after recent kills.
function Marks.RespawnText(name)
    if Marks.VisibleAlive(name) > 0 then return end
    local remaining = addon.Respawn.Remaining(respawn, name, Now())
    if remaining then return L.RespawnIn:format(math.max(1, math.ceil(remaining / 60))) end
end

function Marks.LootCount()
    return addon.LootReminder.Count(loot, lootNames, Now())
end

-- A quest mob died in sight: dead now, not tagged by someone else (so it is ours or the
-- group's), each one counted once.
local seenDead, seenCount = {}, 0
local function Public(value) return value ~= nil and not (issecretvalue and issecretvalue(value)) end
local function NoteDeath(unit)
    if not (UnitIsDead and UnitIsDead(unit)) then return end
    local guid, name = UnitGUID and UnitGUID(unit), UnitName(unit)
    if not (Public(guid) and Public(name)) or seenDead[guid] then return end
    if not (byName[name] or lootNames[name]) then return end
    if UnitIsTapDenied and UnitIsTapDenied(unit) then return end
    seenDead[guid], seenCount = true, seenCount + 1
    if seenCount > 200 then seenDead, seenCount = {[guid] = true}, 1 end
    addon.LootReminder.Killed(loot, guid, name, lootNames, Now())
    if byName[name] then addon.Respawn.Killed(respawn, name, Now()) end
end

local function OnLoot()
    if GetNumLootItems and GetLootSourceInfo then
        for slot = 1, GetNumLootItems() do
            local guid = GetLootSourceInfo(slot)
            addon.LootReminder.Looted(loot, guid)
        end
    end
    if UnitGUID and UnitExists and UnitExists("target") and not Alive("target") then
        addon.LootReminder.Looted(loot, UnitGUID("target"))
    end
end

-- source() returns the current entries; refreshed once per second.
function Marks.Start(source, settingsTable)
    settings = settingsTable or {}
    Marks.enabled = settings.nameplateMarks ~= false
    if not driver then
        driver = CreateFrame("Frame")
        for _, event in ipairs({"NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "UNIT_HEALTH",
            "RAID_TARGET_UPDATE", "LOOT_OPENED", "PLAYER_REGEN_ENABLED"}) do
            driver:RegisterEvent(event)
        end
        driver:SetScript("OnEvent", function(_, event, unit)
            if event == "PLAYER_REGEN_ENABLED" then driver.signature = nil
            elseif event == "LOOT_OPENED" then OnLoot()
            elseif event == "RAID_TARGET_UPDATE" then Marks.UpdateAll()
            elseif event == "NAME_PLATE_UNIT_REMOVED" then
                NoteDeath(unit) -- the plate of a dying mob may go away before its last health update
                local plate = units[unit]
                if plate and badges[plate] then badges[plate]:Hide() end
                units[unit] = nil
            elseif event == "UNIT_HEALTH" and unit == "target" then
                NoteDeath(unit)
            elseif event == "NAME_PLATE_UNIT_ADDED" or units[unit] then
                if event == "UNIT_HEALTH" then NoteDeath(unit) end
                Marks.Update(unit)
            end
        end)
        addon.UI.RefreshWhileShown(driver, 1)
        Marks.driver = driver
    end
    function driver:Refresh()
        local entries, extra
        if not addon.TargetMarks.Hidden() then entries, extra = source() end
        entries = entries or {}
        local shared = extra and extra.shared or {}
        local names = {}
        for name in pairs(shared) do names[#names + 1] = name end
        table.sort(names)
        local signature = addon.TargetMarks.Signature(entries) .. "|shared:" .. table.concat(names, ",")
        if signature ~= self.signature then
            -- Key buttons are secure: their macros change only out of combat (retried afterwards).
            if not (InCombatLockdown and InCombatLockdown()) then Marks.UpdateKeys(entries) self.signature = signature end
            Marks.Set(entries, shared)
        end
    end
    driver.signature = nil
    driver:Refresh()
end

-- Two secure buttons for key bindings: target and mark the first quest mob, or the
-- turn-in NPC, by exact name with /tm (works where SetRaidTarget is restricted).
local keys = {}
local function KeyButton(name)
    if keys[name] or not CreateFrame then return keys[name] end
    local button = CreateFrame("Button", name, UIParent, "SecureActionButtonTemplate")
    button:RegisterForClicks("AnyUp", "AnyDown")
    button:SetAttribute("useOnKeyDown", false)
    button:SetAttribute("type", "macro")
    button:SetAttribute("macrotext", "")
    Marks.cycleHandler = Marks.cycleHandler or CreateFrame("Frame", nil, UIParent, "SecureHandlerBaseTemplate")
    addon.TargetMarks.WrapCycle(button, Marks.cycleHandler)
    button:Hide()
    keys[name] = button
    return button
end
Marks.KEY_NEXT, Marks.KEY_TURN_IN = "ForeverQuestNavigatorMarkNext", "ForeverQuestNavigatorMarkTurnIn"

function Marks.UpdateKeys(entries)
    local mob, turnIn
    for _, entry in ipairs(entries or {}) do
        if entry.kind == "turnIn" then turnIn = turnIn or entry else mob = mob or entry end
    end
    local next, finisher = KeyButton(Marks.KEY_NEXT), KeyButton(Marks.KEY_TURN_IN)
    -- The quest-mob key cycles through every living mob of the active quest's kill and drop targets.
    local mobNames = {}
    for _, entry in ipairs(entries or {}) do if entry.kind ~= "turnIn" then mobNames[entry.name] = true end end
    if next then addon.TargetMarks.SetCycle(next, mob and mob.name, mob and mob.icon, mob and Marks.UnitsFor(mobNames)) end
    if finisher then finisher:SetAttribute("macrotext", turnIn and addon.TargetMarks.Macro(turnIn.name, turnIn.icon) or "") end
    Marks.keys = keys
end

function Marks.SetEnabled(value)
    Marks.enabled = value ~= false
    Marks.UpdateAll()
end
