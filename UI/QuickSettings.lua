local _, addon = ...
local L = addon.L
local window
local ROWS, ROW_HEIGHT, ROW_GAP, ROWS_TOP = 8, 38, 4, 112
local function Fold(text)
    return (text:gsub("[A-Z]", function(letter) return string.char(letter:byte() + 32) end)
        :gsub("Ä", "ä"):gsub("Ö", "ö"):gsub("Ü", "ü"):gsub("ẞ", "ß"))
end
function addon.FilterSettings(entries, query, advanced, scope)
    local result = {}
    query = Fold(query or "")
    for _, entry in ipairs(entries) do
        local text = Fold(entry.name .. " " .. (entry.help or "") .. " " .. entry.key .. " " .. (entry.section or ""))
        if ((query ~= "" and text:find(query, 1, true)) or (query == "" and (advanced or entry.basic)))
            and (not scope or scope == "all" or entry.effect == scope) then result[#result + 1] = entry end
    end
    return result
end
local function Display(entry, value)
    if entry.key == "repeatablePolicy" then return L["RepeatableShort_" .. value] end
    if entry.key == "theme" then return L["Design_" .. value] end
    if entry.key == "language" then return value == "auto" and L.AutoShort or value == "deDE" and "Deutsch" or "English" end
    if entry.key == "detailMode" then return value == "compact" and L.DetailCompact or L.DetailDetailed end
    if entry.key == "navigatorView" then return L["NavigatorView_" .. value] end
    if entry.key == "opacityPercent" or entry.key == "fontPercent" then return tostring(value) .. "%" end
    if entry.key == "questieOfferRadius" then return tostring(value) .. " yd" end
    return tostring(value)
end
function addon.ShowQuickSettings(catalog, settings, advancedAction)
    if not window then
        window = addon.UI.CreateUtilityPanel(570, ROWS_TOP + ROWS * (ROW_HEIGHT + ROW_GAP) + 64, L.QuickSettings)
        window.search = CreateFrame("EditBox", nil, window, "InputBoxTemplate")
        window.search:SetSize(340, 24) window.search:SetPoint("TOPLEFT", 23, -52)
        window.search:SetAutoFocus(false) window.search:SetMaxLetters(80)
        window.search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        addon.UI.BindTooltip(window.search, function() return L.SearchSettings, L.SearchSettingsHelp end)
        window.search:SetScript("OnTextChanged", function() window.offset = 0 if window.catalog then window:Refresh() end end)
        window.search:SetScript("OnEditFocusGained", function() window.placeholder:Hide() end)
        window.search:SetScript("OnEditFocusLost", function() window:Refresh() end)
        window.placeholder = addon.UI.CreateLabel(window.search, "GameFontDisableSmall")
        window.placeholder:SetPoint("LEFT", 6, 0) window.placeholder:SetText(L.SearchSettings)
        window.search:SetText("")
        window.clearQuery = addon.UI.CreateUtilityButton(window, "×", 18, function() window.search:SetText("") window.offset = 0 window:Refresh() end)
        window.clearQuery:SetPoint("TOPLEFT", 365, -52)
        addon.UI.BindTooltip(window.clearQuery, function() return L.ClearSearch end)
        window.advanced = addon.UI.CreateUtilityButton(window, L.AdvancedSettings, 165, function()
            window.showAdvanced = not window.showAdvanced window.offset = 0 window:Refresh()
        end)
        window.advanced:SetPoint("TOPRIGHT", -18, -52)
        window.searchHint = addon.UI.CreateLabel(window, "GameFontDisableSmall")
        window.searchHint:SetPoint("TOPLEFT", 18, -85) window.searchHint:SetPoint("TOPRIGHT", -18, -85)
        window.searchHint:SetMaxLines(1) window.searchHint:SetText(L.SettingsEssentialHelp)
        window.searchHint:Hide()
        window.scope = addon.UI.CreateUtilityButton(window, L.SettingsScope_all, 250, function()
            if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
            MenuUtil.CreateContextMenu(window.scope, function(_, menu)
                menu:CreateTitle(L.SettingsScope)
                for _, key in ipairs({"all", "view", "logic"}) do
                    local scope = key
                    menu:CreateButton(L["SettingsScope_" .. key], function() window.filterScope, window.offset = scope, 0 window:Refresh() end)
                end
            end)
        end)
        window.scope:SetPoint("TOPLEFT", 18, -80)
        window.examples = addon.UI.CreateUtilityButton(window, L.SettingsExamples, 276, function()
            addon.ShowAppearancePreview(window.settings, window.catalog)
        end)
        window.examples:SetPoint("TOPRIGHT", -18, -80)
        window.rows = {}
        for index = 1, ROWS do
            local row = addon.UI.CreateUtilityButton(window, "", 534, function() end)
            row:SetHeight(ROW_HEIGHT) row:SetPoint("TOPLEFT", 18, -ROWS_TOP - (index - 1) * (ROW_HEIGHT + ROW_GAP))
            row.textLabel:ClearAllPoints() row.textLabel:SetPoint("TOPLEFT", 8, -5) row.textLabel:SetPoint("TOPRIGHT", -168, -5)
            row.textLabel:SetJustifyH("LEFT") row.textLabel:SetMaxLines(1)
            -- Short help under the name, so the meaning is visible without hovering.
            row.help = addon.UI.CreateLabel(row, "GameFontDisableSmall")
            row.help:SetPoint("BOTTOMLEFT", 8, 5) row.help:SetPoint("BOTTOMRIGHT", -168, 5)
            row.help:SetJustifyH("LEFT") row.help:SetMaxLines(1)
            row:EnableMouseWheel(true)
            row:SetScript("OnMouseWheel", function(_, delta) window:Scroll(-delta) end)
            row.value = addon.UI.CreateLabel(row, "GameFontNormalSmall")
            row.value:SetPoint("RIGHT", -40, 0) row.value:SetWidth(66) row.value:SetJustifyH("CENTER")
            row.minus = addon.UI.CreateUtilityButton(row, "-", 28, function() window:Change(row.entry, -1) end)
            row.minus:SetPoint("RIGHT", -112, 0)
            row.plus = addon.UI.CreateUtilityButton(row, "+", 28, function() window:Change(row.entry, 1) end)
            row.plus:SetPoint("RIGHT", -6, 0)
            row.toggle = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
            row.toggle:SetSize(26, 26) row.toggle:SetPoint("RIGHT", -10, 0)
            row.toggle:SetScript("OnClick", function() window:Change(row.entry, 1) end)
            row.choose = addon.UI.CreateUtilityButton(row, "", 150, function() window:Choose(row.entry) end)
            row.choose:SetPoint("RIGHT", -6, 0)
            row.choose.textLabel:ClearAllPoints() row.choose.textLabel:SetPoint("LEFT", 5, 0) row.choose.textLabel:SetPoint("RIGHT", -5, 0)
            row.choose.textLabel:SetJustifyH("CENTER") row.choose.textLabel:SetMaxLines(2)
            row:SetScript("OnClick", function(self)
                if self.entry and self.entry.choices then window:Choose(self.entry)
                elseif self.entry and self.entry.kind == "boolean" then window:Change(self.entry, 1) end
            end)
            for _, owner in ipairs({row, row.toggle, row.choose}) do
                addon.UI.BindTooltip(owner, function()
                    return row.entry and row.entry.name, row.entry and (row.entry.help or "") .. "\n" .. L["SettingEffect_" .. (row.entry.effect or "view")]
                end)
            end
            window.rows[index] = row
        end
        window:EnableMouseWheel(true)
        window:SetScript("OnMouseWheel", function(_, delta) window:Scroll(-delta) end)
        window.previous = addon.UI.CreateUtilityButton(window, "^", 26, function() window:Scroll(-ROWS + 1) end)
        window.previous:SetPoint("BOTTOMRIGHT", -50, 18)
        window.next = addon.UI.CreateUtilityButton(window, "v", 26, function() window:Scroll(ROWS - 1) end)
        window.next:SetPoint("BOTTOMRIGHT", -18, 18)
        window.pageLabel = addon.UI.CreateLabel(window, "GameFontDisableSmall")
        window.pageLabel:SetPoint("RIGHT", window.previous, "LEFT", -10, 0)
        function window:Scroll(delta)
            self.offset = (self.offset or 0) + delta
            self:Refresh()
        end
        window.native = addon.UI.CreateUtilityButton(window, L.AllSettings, 250, function() window:Hide() window.advancedAction() end)
        window.native:SetPoint("BOTTOMLEFT", 18, 14)
        window.empty = addon.UI.CreateLabel(window, "GameFontHighlightSmall")
        window.empty:SetPoint("TOPLEFT", 24, -130) window.empty:SetPoint("TOPRIGHT", -24, -130)
        window.empty:SetJustifyH("CENTER") window.empty:SetText(L.NoSettingsMatch)
        window.clear = addon.UI.CreateUtilityButton(window, L.ClearSearch, 220, function() window.search:SetText("") window.offset = 0 window:Refresh() end)
        window.clear:SetPoint("TOP", 0, -175)
        function window:Choose(entry)
            if not entry or not entry.choices then return end
            if not (MenuUtil and MenuUtil.CreateContextMenu) then self:Change(entry, 1) return end
            MenuUtil.CreateContextMenu(self, function(_, menu)
                menu:CreateTitle(entry.name)
                for _, choice in ipairs(entry.choices) do
                    local value = choice
                    local prefix = self.settings[entry.key] == value and "[x] " or ""
                    menu:CreateButton(prefix .. Display(entry, value), function() entry.control:SetValue(value) self:Refresh() end)
                end
            end)
        end
        function window:Change(entry, delta)
            if not entry then return end
            local value = self.settings[entry.key]
            if entry.kind == "boolean" then value = not value
            elseif entry.minimum then value = math.max(entry.minimum, math.min(entry.maximum, (tonumber(value) or entry.minimum) + delta * entry.step))
            else return end
            entry.control:SetValue(value) self:Refresh()
        end
        function window:Refresh()
            local entries = addon.FilterSettings(self.catalog, self.search:GetText(), self.showAdvanced, self.filterScope)
            self.scope:SetText(L.SettingsScopeLabel:format(L["SettingsScope_" .. (self.filterScope or "all")]))
            self.offset = math.max(0, math.min(self.offset or 0, #entries - ROWS))
            self.advanced:SetText(self.showAdvanced and L.SettingsShowEssential or L.SettingsShowAll)
            local query = self.search:GetText() or ""
            self.placeholder:SetShown(query == "" and not (self.search.HasFocus and self.search:HasFocus()))
            for index, row in ipairs(self.rows) do
                local entry = entries[self.offset + index]
                row.entry = entry row:SetShown(entry ~= nil)
                if entry then
                    local value = self.settings[entry.key]
                    row:SetText(entry.name)
                    row.help:SetText(entry.help or "")
                    row.toggle:SetShown(entry.kind == "boolean") row.toggle:SetChecked(value == true)
                    row.choose:SetShown(entry.choices ~= nil)
                    row.choose:SetText(Display(entry, value) .. " v")
                    row.value:SetText(Display(entry, value)) row.value:SetShown(entry.minimum ~= nil)
                    row.minus:SetShown(entry.minimum ~= nil) row.plus:SetShown(entry.minimum ~= nil)
                    if entry.minimum then row.minus:SetEnabled(value > entry.minimum) row.plus:SetEnabled(value < entry.maximum) end
                end
            end
            local scrolls = #entries > ROWS
            self.previous:SetEnabled(self.offset > 0) self.next:SetEnabled(self.offset + ROWS < #entries)
            self.clearQuery:SetShown(query ~= "")
            self.previous:SetShown(scrolls) self.next:SetShown(scrolls)
            self.empty:SetShown(#entries == 0) self.clear:SetShown(#entries == 0)
            self.pageLabel:SetText(scrolls and L.SettingsCount:format(self.offset + 1, math.min(#entries, self.offset + ROWS), #entries) or "")
        end
    end
    window.catalog, window.settings, window.advancedAction = catalog, settings, advancedAction
    window.offset = window.offset or 0
    window:Refresh() addon.UI.ShowUtilityPanel(window)
    return window
end
