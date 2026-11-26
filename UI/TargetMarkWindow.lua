local _, addon = ...
local L = addon.L
-- Compact movable window: one secure button per NPC of the active quest. A click targets
-- the NPC by exact name ("/targetexact") and marks it with "/tm" in the same secure macro, so it
-- also works in combat and on clients that restrict SetRaidTarget: skull for mobs to kill or
-- that drop a quest item, star for the turn-in NPC.
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

-- The macro has already marked; this only checks whether the NPC was found (for the status line).
local function TryMark(window)
    local pending = window.pending
    if not pending or Now() - pending.at > PENDING_SECONDS then return end
    if UnitExists and UnitExists("target") and UnitName("target") == pending.name then
        window.pending = nil
        SetStatus(window, nil)
        return true
    end
end

-- PostClick runs for the press and the release; the secure macro runs on one of them.
-- If the target arrives later, PLAYER_TARGET_CHANGED clears the "not in range" note.
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
    if entry.danger then GameTooltip:AddLine(L.DangerTooltip:format(entry.danger), 1, .35, .35, true) end
    if entry.respawn then GameTooltip:AddLine(entry.respawn, .8, .8, .8, true) end
    if entry.alsoFor then GameTooltip:AddLine(L.AlsoCountsFor:format(entry.alsoFor), .4, .8, 1, true) end
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
    -- Same background opacity as the navigator (setting opacityPercent).
    local function Opacity() return (settings.opacityPercent or 80) / 100 end
    addon.UI.Theme.WatchFrame(frame, Opacity)
    function frame:UpdateOpacity() addon.UI.Theme.Frame(self, Opacity()) end
    addon.UI.TargetMarkWindow = frame

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


    -- Usable quest item of the active quest, as a secure item button on top of the list.
    local item = CreateFrame("Button", nil, frame, "SecureActionButtonTemplate")
    item:SetHeight(ROW_HEIGHT)
    item:RegisterForClicks("LeftButtonUp")
    item:SetAttribute("useOnKeyDown", false)
    item.icon = item:CreateTexture(nil, "ARTWORK")
    item.icon:SetSize(14, 14)
    item.icon:SetPoint("LEFT", 2, 0)
    item.label = addon.UI.CreateLabel(item, "GameFontNormalSmall")
    item.label:SetPoint("LEFT", item.icon, "RIGHT", 4, 0)
    item.label:SetPoint("RIGHT", -2, 0)
    item.label:SetJustifyH("LEFT")
    item.label:SetMaxLines(1)
    local itemHighlight = item:CreateTexture(nil, "HIGHLIGHT")
    itemHighlight:SetAllPoints()
    itemHighlight:SetColorTexture(1, 1, 1, .08)
    item:SetScript("OnEnter", function(self)
        if not (self.hint and GameTooltip) then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if GameTooltip.SetHyperlink and self.hint.link then GameTooltip:SetHyperlink(self.hint.link)
        else GameTooltip:SetText(self.hint.name or L.QuestItemAction) end
        GameTooltip:AddLine(L.QuestItemClick, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    item:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    item:Hide()
    frame.itemButton = item

    -- Loot reminder: killed quest-item droppers that were not looted yet.
    frame.loot = addon.UI.CreateLabel(frame, "GameFontNormalSmall")
    frame.loot:SetJustifyH("LEFT")
    frame.loot:SetMaxLines(1)
    frame.loot:Hide()

    frame.rows = {}
    for index = 1, addon.TargetMarks.LIMIT do
        local row = CreateFrame("Button", nil, frame, "SecureActionButtonTemplate")
        row.window = frame
        row:SetHeight(ROW_HEIGHT)
        row:RegisterForClicks("AnyUp", "AnyDown")
        row:SetAttribute("useOnKeyDown", false)
        row:SetAttribute("type", "macro")
        -- Each click moves on to the next living mob of that name (see TargetMarks.CYCLE_SNIPPET).
        frame.cycleHandler = frame.cycleHandler or CreateFrame("Frame", nil, frame, "SecureHandlerBaseTemplate")
        row.cycles = addon.TargetMarks.WrapCycle(row, frame.cycleHandler)
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
        local entries, extra
        local cycleUnits = {}
        -- Hidden with everything else when the minimap icon switches all windows off.
        if self.enabled and settings.displayMode ~= "off" and not addon.TargetMarks.Hidden() then entries, extra = source() end
        entries, extra = entries or {}, extra or {}
        local hint, lootCount = extra.item, extra.loot or 0
        -- Only there while the active quest has targets or an item; secure frames change only out of combat.
        self:SetShown(#entries > 0 or hint ~= nil)
        -- Candidate units per mob row (living nameplates with that name) for click cycling.
        local unitKey = {}
        for index, entry in ipairs(entries) do
            if entry.kind ~= "turnIn" and addon.NameplateMarks and addon.NameplateMarks.UnitsFor then
                cycleUnits[index] = addon.NameplateMarks.UnitsFor({[entry.name] = true})
                unitKey[#unitKey + 1] = table.concat(cycleUnits[index], ",")
            end
        end
        local signature = addon.TargetMarks.Signature(entries) .. "|units:" .. table.concat(unitKey, ";") .. "|item:" .. tostring(hint and hint.id)
            .. ":" .. tostring(hint and hint.count) .. "|loot:" .. lootCount
        if signature == self.signature then return end
        self.signature, self.entries = signature, entries
        local top = HEADER
        item.hint = hint
        if hint then
            if item.assigned ~= hint.id then item:SetAttribute("type", "item") item:SetAttribute("item", "item:" .. hint.id) item.assigned = hint.id end
            item.icon:SetTexture(hint.texture or "Interface\\Icons\\INV_Misc_QuestionMark")
            item.label:SetText((hint.name or L.QuestItemAction) .. ((hint.count or 0) > 1 and (" ×" .. hint.count) or ""))
            item:ClearAllPoints()
            item:SetPoint("TOPLEFT", 3, -top) item:SetPoint("TOPRIGHT", -3, -top)
            top = top + ROW_HEIGHT + 2
        elseif item.assigned then
            item:SetAttribute("type", nil) item:SetAttribute("item", nil) item.assigned = nil
        end
        item:SetShown(hint ~= nil)
        for index, row in ipairs(self.rows) do
            local entry = entries[index]
            row.entry = entry
            if entry then
                addon.TargetMarks.SetCycle(row, entry.name, entry.icon, cycleUnits[index])
                row.icon:SetTexture(ICON:format(entry.icon))
                -- Progress, danger and respawn at a glance; the dropped item is in the tooltip.
                local text = entry.danger and ("|cffff5555" .. entry.name .. "|r") or entry.name
                if entry.progress then text = text .. " |cff9d9d9d" .. entry.progress .. "|r" end
                if entry.danger then text = text .. " |cffff5555" .. entry.danger .. "|r" end
                if entry.respawn then text = text .. " |cff9d9d9d" .. entry.respawn .. "|r" end
                if entry.alsoFor then text = text .. " |cff66ccff+1|r" end
                row.label:SetText(text)
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", 3, -top) row:SetPoint("TOPRIGHT", -3, -top)
                top = top + ROW_HEIGHT
            end
            row:SetShown(entry ~= nil)
        end
        self.loot:SetShown(lootCount > 0)
        if lootCount > 0 then
            self.loot:SetText(L.LootReminder:format(lootCount))
            self.loot:ClearAllPoints()
            self.loot:SetPoint("TOPLEFT", 6, -top - 2) self.loot:SetPoint("TOPRIGHT", -6, -top - 2)
            top = top + ROW_HEIGHT
        end
        self:SetHeight(top + 4)
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
