local _, addon = ...
local L = addon.L
local window
function addon.ShowExcursion(plan, actions)
    if not window then
        window = addon.UI.CreateUtilityPanel(610, 555, L.ExcursionTitle)
        window.hubStandalone = true
        window.summary = addon.UI.CreateLabel(window, "GameFontHighlightSmall")
        window.summary:SetPoint("TOPLEFT", 18, -48) window.summary:SetPoint("TOPRIGHT", -18, -48)
        window.summary:SetJustifyH("LEFT") window.summary:SetMaxLines(3)
        window.rows = {}
        for index = 1, 6 do
            local row = addon.UI.CreateUtilityButton(window, "", 574, function() end)
            row:SetPoint("TOPLEFT", 18, -120 - (index - 1) * 50) row:SetHeight(44)
            row.textLabel:ClearAllPoints() row.textLabel:SetPoint("LEFT", 8, 0) row.textLabel:SetPoint("RIGHT", -8, 0)
            row.textLabel:SetJustifyH("LEFT") row.textLabel:SetMaxLines(2)
            row:SetScript("OnClick", function(self) if self.stop then window.actions.map(self.stop) end end)
            addon.UI.BindTooltip(row, function(self)
                local prep = self.stop and addon.QuestPreparation.Describe(self.stop.quest.preparation, self.stop.quest.group)
                return self:GetText(), (prep and prep ~= "" and (prep .. "\n") or "") .. L.ExcursionHelp
            end)
            window.rows[index] = row
        end
        window.previous = addon.UI.CreateUtilityButton(window, "<", 32, function() window.page = math.max(1, window.page - 1) window:Refresh() end)
        window.previous:SetPoint("BOTTOMLEFT", 18, 87)
        window.next = addon.UI.CreateUtilityButton(window, ">", 32, function() window.page = window.page + 1 window:Refresh() end)
        window.next:SetPoint("BOTTOMRIGHT", -18, 87)
        window.start = addon.UI.CreateUtilityButton(window, L.ExcursionStart, 280, function()
            local ok, message = window.actions.start(window.plan)
            window.status = message window:Refresh()
        end)
        window.start:SetPoint("BOTTOMLEFT", 18, 16)
        window.pause = addon.UI.CreateUtilityButton(window, L.ExcursionPause, 280, function()
            window.actions.pause() window:Refresh()
        end)
        window.pause:SetPoint("BOTTOMRIGHT", -18, 16)
        window.info = addon.UI.CreateLabel(window, "GameFontDisableSmall")
        window.info:SetPoint("BOTTOMLEFT", 18, 50) window.info:SetPoint("BOTTOMRIGHT", -18, 50)
        window.info:SetMaxLines(2) window.info:SetJustifyH("LEFT")
        function window:Refresh()
            local p = self.plan
            local pages = math.max(1, math.ceil(#p.stops / 6)) self.page = math.min(self.page, pages)
            self.summary:SetText(L.ExcursionSummary:format(#p.stops, p.xp, p.unknownXP, p.missing))
            self.info:SetText(self.status or p.status or L.ExcursionHelp)
            for index, row in ipairs(self.rows) do
                local stop = p.stops[(self.page - 1) * 6 + index]
                row.stop = stop row:SetShown(stop ~= nil)
                if stop then row:SetText((stop.done and "[x] " or "") .. L["ExcursionAction_" .. stop.action] .. ": " .. addon.UI.FormatQuestTitle(stop.quest)
                    .. (p.running and (self.page - 1) * 6 + index == p.index and ("\n" .. L.ExcursionCurrent) or "")) end
            end
            self.previous:SetEnabled(self.page > 1) self.next:SetEnabled(self.page < pages)
            self.start:SetEnabled(#p.stops > 0 and p.index <= #p.stops and not p.running) self.pause:SetEnabled(p.running)
        end
        window:SetScript("OnUpdate", function(self, elapsed)
            self.elapsed = (self.elapsed or 0) + elapsed
            if self.elapsed >= 1 then self.elapsed = 0 self:Refresh() end
        end)
    end
    window.plan, window.actions, window.page, window.status = plan, actions, 1, nil
    window:Refresh() window:Show()
    return window
end
