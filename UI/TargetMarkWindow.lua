local _, addon = ...
local L = addon.L
-- Compact movable window: one secure button per NPC of the active quest. A click targets
-- the NPC by exact name ("/targetexact", a secure action, so it also works in combat) and
-- then marks it: skull for mobs to kill or that drop a quest item, star for the turn-in NPC.
-- Secure buttons cannot be changed in combat, so the list only updates out of combat.

local ICON = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_%d"
local ROW_HEIGHT, HEADER, WIDTH = 16, 18, 168
local PENDING_SECONDS = 2

local function InCombat() return InCombatLockdown and InCombatLockdown() == true end
local function Now() return GetTime and GetTime() or 0 end

local function SetStatus(window, text)
    window.status:SetText(text or "")
    window.status:SetShown(text ~= nil)
    window.heading:SetShown(text == nil)
end

-- Marks the current target if it is the requested NPC. Returns true when it matched.
local function TryMark(window)
    local pending = window.pending
    if not pending or Now() - pending.at > PENDING_SECONDS then return end
    if UnitExists and UnitExists("target") and UnitName("target") == pending.name then
        if GetRaidTargetIndex("target") ~= pending.icon then SetRaidTarget("target", pending.icon) end
        window.pending = nil
        SetStatus(window, nil)
        return true
    end
end

-- PostClick runs for the press and the release; the secure targeting happens on one of them.
-- If the target arrives later, PLAYER_TARGET_CHANGED finishes the mark.
local function MarkTarget(button)
    local entry, window = button.entry, button.window
    if not entry then return end
    window.pending = {name = entry.name, icon = entry.icon, at = Now()}
    if not TryMark(window) then SetStatus(window, L.TargetMarkMissing:format(entry.name)) end
end

local function ShowRowTooltip(button)
    local entry = button.entry
    if not (entry and GameTooltip) then return end
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    GameTooltip:SetText(entry.name)
    GameTooltip:AddLine(entry.item and L.TargetMark_loot:format(entry.item) or L["TargetMark_" .. entry.kind], 1, 1, 1, true)
    if entry.title then GameTooltip:AddLine(entry.title, .8, .8, .8, true) end
    GameTooltip:AddLine(L.TargetMarkClick, .6, .8, 1, true)
    GameTooltip:Show()
end

-- source() returns the entries from addon.TargetMarks.Collect.
function addon.CreateTargetMarkWindow(settings, source)
    local frame = CreateFrame("Frame", "ForeverQuestNavigatorTargetMarks", UIParent, "BackdropTemplate")
    frame:SetSize(WIDTH, HEADER + ROW_HEIGHT + 4)
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
    frame.heading:SetPoint("TOPLEFT", 6, -4)
    frame.heading:SetPoint("TOPRIGHT", -6, -4)
    frame.heading:SetJustifyH("LEFT")
    frame.heading:SetMaxLines(1)
    frame.heading:SetText(L.TargetMarkTitle)
    -- Status shares the title line, so the window does not grow for it.
    frame.status = addon.UI.CreateLabel(frame, "GameFontRedSmall")
    frame.status:SetPoint("TOPLEFT", 6, -4)
    frame.status:SetPoint("TOPRIGHT", -6, -4)
    frame.status:SetJustifyH("LEFT")
    frame.status:SetMaxLines(1)
    frame.status:Hide()
    -- No close button: the window hides itself when nothing is relevant and is switched
    -- off in the settings (or with /fqn marks / the key binding).
    frame:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(L.TargetMarkTitle)
        GameTooltip:AddLine(L.TargetMarkHideHint, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)


    frame.rows = {}
    for index = 1, addon.TargetMarks.LIMIT do
        local row = CreateFrame("Button", nil, frame, "SecureActionButtonTemplate")
        row.window = frame
        row:SetHeight(ROW_HEIGHT)
        row:SetPoint("TOPLEFT", 3, -HEADER - (index - 1) * ROW_HEIGHT)
        row:SetPoint("TOPRIGHT", -3, -HEADER - (index - 1) * ROW_HEIGHT)
        row:RegisterForClicks("AnyUp", "AnyDown")
        row:SetAttribute("type", "macro")
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(13, 13)
        row.icon:SetPoint("LEFT", 2, 0)
        row.label = addon.UI.CreateLabel(row, "GameFontHighlightSmall")
        row.label:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
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
        -- An unanswered click ends after a moment; its "not in range" note goes with it.
        if self.pending and Now() - self.pending.at > PENDING_SECONDS + 1 then self.pending = nil SetStatus(self, nil) end
        if InCombat() then return end
        local entries = (self.enabled and not addon.TargetMarks.Hidden()) and source() or {}
        -- Only there while the active quest has targets; secure frames change only out of combat.
        self:SetShown(#entries > 0)
        local signature = addon.TargetMarks.Signature(entries)
        if signature == self.signature then return end
        self.signature, self.entries = signature, entries
        for index, row in ipairs(self.rows) do
            local entry = entries[index]
            row.entry = entry
            if entry then
                row:SetAttribute("macrotext", addon.TargetMarks.Macro(entry.name))
                row.icon:SetTexture(ICON:format(entry.icon))
                row.label:SetText(entry.name) -- the dropped item is in the tooltip
            end
            row:SetShown(entry ~= nil)
        end
        self:SetHeight(HEADER + math.max(1, #entries) * ROW_HEIGHT + 4)
    end
    -- A separate ticker keeps checking while the window itself is hidden.
    frame.ticker = CreateFrame("Frame")
    frame.ticker.Refresh = function() frame:Refresh() end
    addon.UI.RefreshWhileShown(frame.ticker, 1)
    frame:RegisterEvent("PLAYER_TARGET_CHANGED")
    frame:SetScript("OnEvent", function(self) TryMark(self) end)
    function frame:SetEnabled(value)
        self.enabled = value == true
        self.ticker:SetShown(self.enabled)
        self.signature = nil
        self:Refresh()
    end
    frame:Hide()
    return frame
end
