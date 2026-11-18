local _, addon = ...
local L = addon.L
local window
local function Fold(text)
    return (text:gsub("[A-Z]", function(letter) return string.char(letter:byte() + 32) end)
        :gsub("Ä", "ä"):gsub("Ö", "ö"):gsub("Ü", "ü"):gsub("ẞ", "ß"))
end

function addon.FilterSettings(entries, query, advanced)
    local result = {}
    query = Fold(query or "")
    for _, entry in ipairs(entries) do
        local text = Fold(entry.name .. " " .. (entry.help or "") .. " " .. entry.key)
        if (query ~= "" and text:find(query, 1, true)) or (query == "" and (advanced or entry.basic)) then result[#result + 1] = entry end
    end
    return result
end

function addon.ShowQuickSettings(catalog, settings, advancedAction, planningAction, feedbackAction, profilesAction, historyAction)
    if not window then
        window = addon.UI.CreateUtilityPanel(570, 575, L.QuickSettings)
        window.search = CreateFrame("EditBox", nil, window, "InputBoxTemplate")
        window.search:SetSize(310, 24)
        window.search:SetPoint("TOPLEFT", 23, -52)
        window.search:SetAutoFocus(false)
        window.search:SetMaxLetters(80)
        window.search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        addon.UI.BindTooltip(window.search, function() return L.SearchSettings, L.SearchSettingsHelp end)
        window.search:SetScript("OnTextChanged", function() window.page = 1 if window.catalog then window:Refresh() end end)
        window.advanced = addon.UI.CreateUtilityButton(window, L.AdvancedSettings, 185, function()
            window.showAdvanced = not window.showAdvanced window.page = 1 window:Refresh()
        end)
        window.advanced:SetPoint("TOPRIGHT", -18, -52)
        window.searchHint = addon.UI.CreateLabel(window, "GameFontDisableSmall")
        window.searchHint:SetPoint("TOPLEFT", 18, -85)
        window.searchHint:SetText(L.SearchSettings)
        window.rows = {}
        for index = 1, 5 do
            local row = addon.UI.CreateUtilityButton(window, "", 475, function() end)
            row:SetHeight(45)
            row:SetPoint("TOPLEFT", 18, -112 - (index - 1) * 52)
            row.textLabel:ClearAllPoints()
            row.textLabel:SetPoint("LEFT", 8, 0)
            row.textLabel:SetPoint("RIGHT", -8, 0)
            row.textLabel:SetJustifyH("LEFT")
            row.textLabel:SetMaxLines(2)
            row.minus = addon.UI.CreateUtilityButton(window, "-", 32, function() window:Change(row.entry, -1) end)
            row.minus:SetPoint("LEFT", row, "RIGHT", 5, 0)
            row:SetScript("OnClick", function(self) window:Change(self.entry, 1) end)
            addon.UI.BindTooltip(row, function(self) return self.entry and self.entry.name, self.entry and self.entry.help end)
            window.rows[index] = row
        end
        window.previous = addon.UI.CreateUtilityButton(window, "<", 30, function() window.page = math.max(1, window.page - 1) window:Refresh() end)
        window.previous:SetPoint("BOTTOMLEFT", 18, 165)
        window.next = addon.UI.CreateUtilityButton(window, ">", 30, function() window.page = window.page + 1 window:Refresh() end)
        window.next:SetPoint("BOTTOMRIGHT", -18, 165)
        window.pageLabel = addon.UI.CreateLabel(window, "GameFontHighlightSmall")
        window.pageLabel:SetPoint("BOTTOM", 0, 171)
        window.undo = addon.UI.CreateUtilityButton(window, L.ChangeHistory, 245, function() window:Hide() window.historyAction() end)
        window.undo:SetPoint("BOTTOMLEFT", 18, 110)
        window.detour = addon.UI.CreateUtilityButton(window, L.TemporaryDetour, 245, function() window:Hide() addon.OpenDetourTools() end)
        window.detour:SetPoint("BOTTOMRIGHT", -18, 110)
        window.feedback = addon.UI.CreateUtilityButton(window, L.FeedbackManager, 245, function() window:Hide() window.feedbackAction() end)
        window.feedback:SetPoint("BOTTOMRIGHT", -18, 65)
        window.profiles = addon.UI.CreateUtilityButton(window, L.AppearanceProfiles, 245, function() window:Hide() window.profilesAction() end)
        window.profiles:SetPoint("BOTTOMLEFT", 18, 65)
        window.native = addon.UI.CreateUtilityButton(window, L.AllSettings, 245, function() window:Hide() window.advancedAction() end)
        window.native:SetPoint("BOTTOMLEFT", 18, 20)
        window.planning = addon.UI.CreateUtilityButton(window, L.PlanningOverview, 245, function() window:Hide() window.planningAction() end)
        window.planning:SetPoint("BOTTOMRIGHT", -18, 20)
        function window:Change(entry, delta)
            if not entry then return end
            local value = self.settings[entry.key]
            if entry.kind == "boolean" then value = not value
            elseif entry.choices then
                local current = 1
                for index, choice in ipairs(entry.choices) do if choice == value then current = index break end end
                value = entry.choices[(current - 1 + delta) % #entry.choices + 1]
            elseif entry.minimum then value = math.max(entry.minimum, math.min(entry.maximum, value + delta * entry.step))
            else return end
            entry.control:SetValue(value)
            self:Refresh()
        end
        function window:Refresh()
            local entries = addon.FilterSettings(self.catalog, self.search:GetText(), self.showAdvanced)
            local pages = math.max(1, math.ceil(#entries / 5))
            self.page = math.min(self.page, pages)
            self.advanced:SetText((self.showAdvanced and "[-] " or "[+] ") .. L.AdvancedSettings)
            for index, row in ipairs(self.rows) do
                local entry = entries[(self.page - 1) * 5 + index]
                row.entry = entry
                row:SetShown(entry ~= nil)
                row.minus:SetShown(entry ~= nil and entry.minimum ~= nil)
                if entry then
                    local value = self.settings[entry.key]
                    if type(value) == "boolean" then value = value and L.SettingOn or L.SettingOff
                    elseif entry.key == "detailMode" then value = value == "compact" and L.DetailCompact or L.DetailDetailed
                    elseif entry.key == "language" then value = value == "auto" and L.LanguageAutomatic or value end
                    if entry.key == "opacityPercent" or entry.key == "fontPercent" then value = tostring(value) .. "%" end
                    if entry.key == "questieOfferRadius" then value = tostring(value) .. " yd" end
                    if entry.minimum then value = tostring(value) .. " [+]" end
                    row:SetText(entry.name .. "\n" .. tostring(value))
                end
            end
            self.previous:SetEnabled(self.page > 1)
            self.next:SetEnabled(self.page < pages)
            self.pageLabel:SetText(#entries > 0 and (self.page .. " / " .. pages) or L.NoSettingsMatch)
        end
    end
    window.catalog, window.settings, window.advancedAction, window.planningAction = catalog, settings, advancedAction, planningAction
    window.feedbackAction, window.profilesAction = feedbackAction, profilesAction
    window.historyAction = historyAction
    window.page, window.showAdvanced = 1, false
    window.search:SetText("")
    window:Refresh()
    window:Show()
end
