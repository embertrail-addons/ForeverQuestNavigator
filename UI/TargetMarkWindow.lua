local _, addon = ...
local L = addon.L
-- Small movable window: one secure button per quest NPC. A click targets the NPC by exact
-- name ("/targetexact", a secure action, so it also works in combat) and then marks it:
-- skull for mobs to kill, star for NPCs to accept from or turn in to.
-- Secure buttons cannot be changed in combat, so the list only updates out of combat.

local ICON = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_%d"
local ROW_HEIGHT = 22

local function InCombat() return InCombatLockdown and InCombatLockdown() == true end

local function MarkTarget(button)
    local entry = button.entry
    if not entry then return end
    if UnitExists and UnitExists("target") and UnitName("target") == entry.name then
        if GetRaidTargetIndex("target") ~= entry.icon then SetRaidTarget("target", entry.icon) end
        button.window.status:SetText("")
    else
        button.window.status:SetText(L.TargetMarkMissing:format(entry.name))
    end
end

local function ShowRowTooltip(button)
    local entry = button.entry
    if not (entry and GameTooltip) then return end
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    GameTooltip:SetText(entry.name)
    GameTooltip:AddLine(L["TargetMark_" .. entry.kind], 1, 1, 1, true)
    if entry.title then GameTooltip:AddLine(entry.title, .8, .8, .8, true) end
    GameTooltip:AddLine(L.TargetMarkClick, .6, .8, 1, true)
    GameTooltip:Show()
end

-- source() returns the entries from addon.TargetMarks.Collect.
function addon.CreateTargetMarkWindow(settings, source)
    local frame = CreateFrame("Frame", "ForeverQuestNavigatorTargetMarks", UIParent, "BackdropTemplate")
    frame:SetSize(230, 60)
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        if not InCombat() then self:StartMoving() end
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        if self.GetLeft and self:GetLeft() and self:GetTop() then
            settings.targetMarksX, settings.targetMarksY = self:GetLeft(), self:GetTop()
        end
    end)
    if type(settings.targetMarksX) == "number" and type(settings.targetMarksY) == "number" then
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", settings.targetMarksX, settings.targetMarksY)
    else
        frame:SetPoint("RIGHT", UIParent, "RIGHT", -260, 80)
    end
    frame:SetBackdrop({ bgFile = "Interface/Buttons/WHITE8X8", edgeFile = "Interface/Buttons/WHITE8X8", edgeSize = 1 })
    addon.UI.Theme.WatchFrame(frame)

    frame.heading = addon.UI.CreateLabel(frame, "GameFontNormalSmall")
    frame.heading:SetPoint("TOPLEFT", 10, -8)
    frame.heading:SetPoint("TOPRIGHT", -30, -8)
    frame.heading:SetJustifyH("LEFT")
    frame.heading:SetText(L.TargetMarkTitle)
    local close = addon.UI.MakeButton(frame)
    close:SetSize(20, 18)
    close:SetPoint("TOPRIGHT", -5, -4)
    close:SetText("×")
    close:SetScript("OnClick", function() addon.ToggleTargetMarks(false) end)
    frame.closeButton = close

    frame.empty = addon.UI.CreateLabel(frame, "GameFontDisableSmall")
    frame.empty:SetPoint("TOPLEFT", 10, -28)
    frame.empty:SetPoint("TOPRIGHT", -10, -28)
    frame.empty:SetJustifyH("LEFT")
    frame.empty:SetText(L.TargetMarkEmpty)
    frame.status = addon.UI.CreateLabel(frame, "GameFontRedSmall")
    frame.status:SetPoint("BOTTOMLEFT", 10, 6)
    frame.status:SetPoint("BOTTOMRIGHT", -10, 6)
    frame.status:SetJustifyH("LEFT")

    frame.rows = {}
    for index = 1, addon.TargetMarks.LIMIT do
        local row = CreateFrame("Button", nil, frame, "SecureActionButtonTemplate")
        row.window = frame
        row:SetHeight(ROW_HEIGHT)
        row:SetPoint("TOPLEFT", 8, -24 - (index - 1) * ROW_HEIGHT)
        row:SetPoint("TOPRIGHT", -8, -24 - (index - 1) * ROW_HEIGHT)
        row:RegisterForClicks("AnyUp", "AnyDown")
        row:SetAttribute("type", "macro")
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(16, 16)
        row.icon:SetPoint("LEFT", 2, 0)
        row.label = addon.UI.CreateLabel(row, "GameFontHighlightSmall")
        row.label:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
        row.label:SetPoint("RIGHT", -2, 0)
        row.label:SetJustifyH("LEFT")
        row.label:SetMaxLines(1)
        local highlight = row:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints()
        highlight:SetColorTexture(1, 1, 1, .08)
        row:SetScript("PostClick", MarkTarget)
        row:SetScript("OnEnter", ShowRowTooltip)
        row:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        row:Hide()
        frame.rows[index] = row
    end

    function frame:Refresh()
        if InCombat() then return end
        local entries = source() or {}
        local signature = addon.TargetMarks.Signature(entries)
        if signature == self.signature then return end
        self.signature, self.entries = signature, entries
        for index, row in ipairs(self.rows) do
            local entry = entries[index]
            row.entry = entry
            if entry then
                row:SetAttribute("macrotext", addon.TargetMarks.Macro(entry.name))
                row.icon:SetTexture(ICON:format(entry.icon))
                row.label:SetText(entry.name)
            end
            row:SetShown(entry ~= nil)
        end
        self.empty:SetShown(#entries == 0)
        self:SetHeight(24 + math.max(1, #entries) * ROW_HEIGHT + 22)
    end
    addon.UI.RefreshWhileShown(frame, 1)
    frame:SetScript("OnShow", function(self) self.signature = nil self:Refresh() end)
    frame:Hide()
    return frame
end
