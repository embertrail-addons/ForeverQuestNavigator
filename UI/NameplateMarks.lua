local _, addon = ...
-- Quest marks in the world for the active quest:
--  * real raid target icons (the ones from the right-click menu): when you target a quest
--    mob it gets the skull, the turn-in NPC the star (setting autoRaidMarks). Each icon
--    exists only once, so the skull moves to the mob you target next.
--  * nameplate badges with progress ("3/8") above every other visible quest mob, so a
--    whole pack is visible at once (setting nameplateMarks; needs nameplates, key V).
--  * loot reminder: killed quest-item droppers that were not looted yet.
local Marks = {}
addon.NameplateMarks = Marks

local ICON = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_%d"
local SIZE = 22

local byName = {}     -- name -> entry from TargetMarks.Collect
local lootNames = {}  -- names of mobs that drop an open quest item
local badges = {}     -- nameplate frame -> badge frame
local units = {}      -- unit token -> nameplate frame
local loot = addon.LootReminder.New()
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
    local entry = Marks.enabled and Alive(unit) and byName[UnitName(unit) or ""]
    local raidIcon = GetRaidTargetIndex and GetRaidTargetIndex(unit)
    if entry and not raidIcon then
        local badge = Badge(plate)
        badge.icon:SetTexture(ICON:format(entry.icon))
        badge.progress:SetText(entry.progress or "")
        badge:Show()
    elseif badges[plate] then
        badges[plate]:Hide()
    end
end

function Marks.UpdateAll()
    for unit in pairs(units) do Marks.Update(unit) end
end

-- Sets the real raid icon on a quest unit (target), never over another player's mark.
function Marks.MarkUnit(unit)
    if not (settings and settings.autoRaidMarks ~= false) or addon.TargetMarks.Hidden() then return end
    if not (UnitExists and UnitExists(unit)) or not Alive(unit) then return end
    local entry = byName[UnitName(unit) or ""]
    if not entry or not addon.TargetMarks.MayMark() then return end
    local current = GetRaidTargetIndex and GetRaidTargetIndex(unit)
    if current == nil and SetRaidTarget then SetRaidTarget(unit, entry.icon) return true end
end

-- entries from addon.TargetMarks.Collect; called whenever the active quest's targets change.
function Marks.Set(entries)
    local nextByName = {}
    for _, entry in ipairs(entries or {}) do nextByName[entry.name] = entry end
    byName, lootNames = nextByName, addon.TargetMarks.LootNames(entries)
    Marks.UpdateAll()
end

function Marks.LootCount()
    return addon.LootReminder.Count(loot, lootNames, Now())
end

local function OnCombatLog()
    if not CombatLogGetCurrentEventInfo then return end
    local _, subevent, _, _, _, _, _, guid, name = CombatLogGetCurrentEventInfo()
    if subevent == "PARTY_KILL" then addon.LootReminder.Killed(loot, guid, name, lootNames, Now()) end
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
            "RAID_TARGET_UPDATE", "PLAYER_TARGET_CHANGED", "COMBAT_LOG_EVENT_UNFILTERED", "LOOT_OPENED"}) do
            driver:RegisterEvent(event)
        end
        driver:SetScript("OnEvent", function(_, event, unit)
            if event == "COMBAT_LOG_EVENT_UNFILTERED" then OnCombatLog()
            elseif event == "LOOT_OPENED" then OnLoot()
            elseif event == "PLAYER_TARGET_CHANGED" then Marks.MarkUnit("target")
            elseif event == "RAID_TARGET_UPDATE" then Marks.UpdateAll()
            elseif event == "NAME_PLATE_UNIT_REMOVED" then
                local plate = units[unit]
                if plate and badges[plate] then badges[plate]:Hide() end
                units[unit] = nil
            elseif event == "NAME_PLATE_UNIT_ADDED" or units[unit] then
                Marks.Update(unit)
            end
        end)
        addon.UI.RefreshWhileShown(driver, 1)
        Marks.driver = driver
    end
    function driver:Refresh()
        local entries = not addon.TargetMarks.Hidden() and source() or {}
        local signature = addon.TargetMarks.Signature(entries)
        if signature ~= self.signature then self.signature = signature Marks.Set(entries) end
    end
    driver.signature = nil
    driver:Refresh()
end

function Marks.SetEnabled(value)
    Marks.enabled = value ~= false
    Marks.UpdateAll()
end
