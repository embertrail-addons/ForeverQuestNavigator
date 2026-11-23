local _, addon = ...
local L = addon.L
local function Combat() return InCombatLockdown and InCombatLockdown() end

-- Keep the protected click surface independent of the movable/scrolled tracker.
-- Attributes, visibility drivers and absolute positioning change only out of combat.
function addon.CreateQuestItemButton(owner, parent)
    local controller = CreateFrame("Frame", nil, UIParent)
    local host = CreateFrame("Frame", nil, parent)
    host:SetSize(200, 36) host:Hide()
    controller.host = host
    host.icon = host:CreateTexture(nil, "ARTWORK")
    host.icon:SetSize(24, 24) host.icon:SetPoint("LEFT", 4, 0)
    host.count = addon.UI.CreateLabel(host, "GameFontHighlightSmall")
    host.count:SetPoint("BOTTOMRIGHT", host.icon, "BOTTOMRIGHT", 2, -2)
    host.label = addon.UI.CreateLabel(host, "GameFontHighlightSmall")
    host.label:SetPoint("TOPLEFT", 40, -3) host.label:SetPoint("TOPRIGHT", -4, -3)
    host.label:SetMaxLines(2) host.label:SetJustifyH("LEFT")
    host.cooldown = CreateFrame("Cooldown", nil, host, "CooldownFrameTemplate")
    host.cooldown:SetAllPoints(host.icon)
    function controller:Read()
        if not self.quest or self.quest.readyToTurnIn or owner.detour or owner.recoveryState then return end
        if addon.DemoMode and addon.DemoMode.IsActive() then return end
        return addon.QuestItemHints.Read(C_QuestLog, self.quest.id, GetQuestLogSpecialItemInfo, GetItemCount, IsQuestLogSpecialItemInRange)
    end
    function controller:CreateClick()
        if self.button or Combat() or not RegisterStateDriver then return end
        local button = CreateFrame("Button", nil, UIParent, "SecureActionButtonTemplate")
        self.button = button
        button:SetSize(32, 32) button:RegisterForClicks("LeftButtonUp")
        button:SetAttribute("useOnKeyDown", false)
        button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
        button:SetFrameStrata("MEDIUM") button:SetFrameLevel(owner:GetFrameLevel() + 8)
        button:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if GameTooltip.SetHyperlink and controller.hint then GameTooltip:SetHyperlink(controller.hint.link)
            else GameTooltip:SetText(controller.hint and controller.hint.name or L.QuestItemAction) end
            GameTooltip:AddLine(L.QuestItemClick, 1, 1, 1, true) GameTooltip:Show()
        end)
        button:SetScript("OnLeave", function() GameTooltip:Hide() end)
        button:Hide()
    end
    function controller:Refresh()
        local previous = self.hint and self.hint.id
        local previousHeight = host:GetHeight()
        self.hint = self:Read()
        local hint = self.hint
        host:SetShown(hint ~= nil)
        if hint then
            host.icon:SetTexture(hint.texture or "Interface/Icons/INV_Misc_QuestionMark")
            host.count:SetText(hint.count > 1 and tostring(hint.count) or "")
            local start, duration, remaining = addon.QuestItemHints.Cooldown(hint, GetQuestLogSpecialItemCooldown, GetTime and GetTime() or 0)
            if host.cooldown.SetCooldown then host.cooldown:SetCooldown(start, duration) end
            host.label:SetText(addon.QuestItemHints.Describe(hint, remaining) .. (Combat() and (" · " .. L.QuestItemCombat) or ""))
            host:SetHeight(math.max(36, host.label:GetStringHeight() + 6))
        end
        if not Combat() then
            if hint then self:CreateClick() end
            local button = self.button
            if button then
                local x, y = host:GetCenter()
                local visible = hint ~= nil and host:IsVisible() and owner:IsVisible() and x ~= nil and y ~= nil
                local viewport = owner.viewport
                if visible and viewport and viewport.GetTop and viewport.GetBottom then
                    local top, bottom = viewport:GetTop(), viewport:GetBottom()
                    if top and bottom then visible = y + 16 <= top and y - 16 >= bottom end
                end
                if hint and self.assigned ~= hint.id then
                    button:SetAttribute("type", "item") button:SetAttribute("item", "item:" .. hint.id)
                    self.assigned = hint.id
                elseif not hint and self.assigned then
                    button:SetAttribute("type", nil) button:SetAttribute("item", nil) self.assigned = nil
                end
                if visible then
                    local scale = host:GetEffectiveScale() / UIParent:GetEffectiveScale()
                    button:ClearAllPoints()
                    button:SetPoint("CENTER", UIParent, "BOTTOMLEFT", (x - host:GetWidth() / 2 + 16) * scale, y * scale)
                end
                if self.visibility ~= visible then
                    RegisterStateDriver(button, "visibility", visible and "[combat] hide; show" or "hide")
                    self.visibility = visible
                end
                button:SetShown(visible == true)
            end
        end
        if (previous ~= (hint and hint.id) or previousHeight ~= host:GetHeight()) and owner.UpdateNavigatorLayout then owner:UpdateNavigatorLayout() end
    end
    -- Position polling only runs while a quest is shown in a visible navigator;
    -- a hidden controller still receives events, so combat cleanup keeps working.
    function controller:UpdatePolling()
        self:SetShown(self.quest ~= nil and owner:IsVisible())
    end
    function controller:SetQuest(quest) self.quest = quest self:Refresh() self:UpdatePolling() end
    controller:RegisterEvent("PLAYER_REGEN_ENABLED")
    controller:RegisterEvent("BAG_UPDATE_DELAYED")
    controller:RegisterEvent("SPELL_UPDATE_COOLDOWN")
    controller:SetScript("OnEvent", function(self, event)
        if event == "SPELL_UPDATE_COOLDOWN" then
            -- Fires very often in combat: only matters with an item shown, and is
            -- folded into the next polling tick instead of a refresh per event.
            if self.hint and self:IsShown() then self.elapsed = math.max(self.elapsed or 0, .2) end
            return
        end
        self:Refresh()
    end)
    controller:SetScript("OnUpdate", function(self, elapsed)
        self.elapsed = (self.elapsed or 0) + elapsed
        if self.elapsed < .25 then return end
        self.elapsed = 0 self:Refresh()
    end)
    owner:HookScript("OnHide", function() controller:Refresh() controller:UpdatePolling() end)
    owner:HookScript("OnShow", function() controller:UpdatePolling() controller:Refresh() end)
    controller:Hide()
    return controller
end
