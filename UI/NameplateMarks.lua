local _, addon = ...
-- Skull/star above every visible mob of the active quest. Raid marks exist only once
-- each, so a pack of quest mobs is marked on their nameplates instead (no group rights
-- needed, nothing is sent). Requires nameplates to be shown (default key V).
local Marks = {}
addon.NameplateMarks = Marks

local ICON = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_%d"
local SIZE = 22

local icons = {}      -- name -> raid icon index
local badges = {}     -- nameplate frame -> badge frame
local units = {}      -- unit token -> nameplate frame
local driver

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
        badges[plate] = badge
    end
    return badge
end

-- Shows or hides the badge for one nameplate unit.
function Marks.Update(unit)
    local plate = units[unit] or Plate(unit)
    if not plate then return end
    units[unit] = plate
    local icon = Marks.enabled and not (UnitIsDead and UnitIsDead(unit)) and icons[UnitName(unit) or ""]
    if icon then
        local badge = Badge(plate)
        badge.icon:SetTexture(ICON:format(icon))
        badge:Show()
    elseif badges[plate] then
        badges[plate]:Hide()
    end
end

function Marks.UpdateAll()
    for unit in pairs(units) do Marks.Update(unit) end
end

-- entries from addon.TargetMarks.Collect; called whenever the active quest's targets change.
function Marks.Set(entries)
    local nextIcons = {}
    for _, entry in ipairs(entries or {}) do nextIcons[entry.name] = entry.icon end
    icons = nextIcons
    Marks.UpdateAll()
end

-- source() returns the current entries; refreshed once per second while enabled.
function Marks.Start(source, enabled)
    Marks.enabled = enabled ~= false
    if not driver then
        driver = CreateFrame("Frame")
        driver:RegisterEvent("NAME_PLATE_UNIT_ADDED")
        driver:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
        driver:RegisterEvent("UNIT_HEALTH")
        driver:SetScript("OnEvent", function(_, event, unit)
            if event == "NAME_PLATE_UNIT_REMOVED" then
                local plate = units[unit]
                if plate and badges[plate] then badges[plate]:Hide() end
                units[unit] = nil
            elseif event == "NAME_PLATE_UNIT_ADDED" or units[unit] then
                Marks.Update(unit)
            end
        end)
        driver.signature = nil
        addon.UI.RefreshWhileShown(driver, 1)
        Marks.driver = driver
    end
    function driver:Refresh()
        if not Marks.enabled then return end
        local entries = not addon.TargetMarks.Hidden() and source() or {}
        local signature = addon.TargetMarks.Signature(entries)
        if signature ~= self.signature then self.signature = signature Marks.Set(entries) end
    end
    driver:Refresh()
end

function Marks.SetEnabled(value)
    Marks.enabled = value ~= false
    if driver then driver.signature = nil end
    if not Marks.enabled then icons = {} end
    Marks.UpdateAll()
    if driver and Marks.enabled then driver:Refresh() end
end
