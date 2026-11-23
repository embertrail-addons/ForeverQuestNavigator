local _, addon = ...
local L = addon.L
local window
local ROWS = 8

-- Searchable list of every /fqn command; clicking a row runs it.
function addon.ShowCommandMenu(settings)
    if not window then
        window = addon.UI.CreateUtilityPanel(570, 470, L.CommandMenuTitle)
        window.hubPage = "commands"
        window.search = CreateFrame("EditBox", nil, window, "InputBoxTemplate")
        window.search:SetSize(380, 24) window.search:SetPoint("TOPLEFT", 23, -52)
        window.search:SetAutoFocus(false) window.search:SetMaxLetters(60)
        window.search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        window.search:SetScript("OnEnterPressed", function(self)
            self:ClearFocus()
            local first = window.matches and window.matches[1]
            if first then first.run("") end
        end)
        window.search:SetScript("OnTextChanged", function() window.page = 1 window:Refresh() end)
        addon.UI.BindTooltip(window.search, function() return L.CommandSearch, L.CommandSearchHelp end)
        window.clear = addon.UI.CreateUtilityButton(window, "×", 18, function() window.search:SetText("") end)
        window.clear:SetPoint("TOPLEFT", 405, -52)
        window.hint = addon.UI.CreateLabel(window, "GameFontDisableSmall")
        window.hint:SetPoint("TOPLEFT", 18, -84) window.hint:SetPoint("TOPRIGHT", -18, -84)
        window.hint:SetJustifyH("LEFT") window.hint:SetMaxLines(2)
        window.rows = {}
        for index = 1, ROWS do
            local row = addon.UI.CreateUtilityButton(window, "", 534, function(self)
                if self.entry then self.entry.run("") end
            end)
            row:SetHeight(32) row:SetPoint("TOPLEFT", 18, -112 - (index - 1) * 36)
            if row.textLabel then
                row.textLabel:ClearAllPoints() row.textLabel:SetPoint("LEFT", 10, 0) row.textLabel:SetPoint("RIGHT", -10, 0)
                row.textLabel:SetJustifyH("LEFT")
            end
            window.rows[index] = row
        end
        window.previous = addon.UI.CreateUtilityButton(window, "<", 40, function() window.page = window.page - 1 window:Refresh() end)
        window.previous:SetPoint("BOTTOMLEFT", 18, 16)
        window.next = addon.UI.CreateUtilityButton(window, ">", 40, function() window.page = window.page + 1 window:Refresh() end)
        window.next:SetPoint("BOTTOMRIGHT", -18, 16)
        window.pageLabel = addon.UI.CreateLabel(window, "GameFontHighlightSmall")
        window.pageLabel:SetPoint("BOTTOM", 0, 22)
        function window:Refresh()
            local simple = self.settings and self.settings.simpleNavigator == true
            local matches = {}
            for _, entry in ipairs(addon.Commands.Filter(self.search:GetText() or "", simple)) do
                if entry.menu ~= false then matches[#matches + 1] = entry end
            end
            self.matches = matches
            local pages = math.max(1, math.ceil(#matches / ROWS))
            self.page = math.max(1, math.min(self.page or 1, pages))
            for index, row in ipairs(self.rows) do
                local entry = matches[(self.page - 1) * ROWS + index]
                row.entry = entry
                row:SetShown(entry ~= nil)
                if entry then
                    row:SetText(("%s  |cff9d9d9d/fqn %s|r"):format(addon.Commands.Label(entry), entry.key))
                end
            end
            self.hint:SetText(#matches == 0 and L.CommandNoMatch or (simple and L.CommandSimpleHint or L.CommandHint))
            self.previous:SetEnabled(self.page > 1) self.next:SetEnabled(self.page < pages)
            self.pageLabel:SetText(("%d / %d"):format(self.page, pages))
        end
    end
    window.settings = settings
    window:Refresh()
    addon.UI.ShowUtilityPanel(window, "commands")
    return window
end

-- Minimap right-click: the most useful commands grouped, plus the full menu.
function addon.ShowCommandContextMenu(owner, settings, fallback)
    if not (MenuUtil and MenuUtil.CreateContextMenu) then return fallback and fallback() end
    local simple = settings and settings.simpleNavigator == true
    MenuUtil.CreateContextMenu(owner, function(_, menu)
        menu:CreateTitle("Forever Quest Navigator")
        local group
        for _, entry in ipairs(addon.Commands.Visible(simple)) do
            if entry.menu ~= false and not entry.args and entry.group ~= "debug" then
                if group and group ~= entry.group and menu.CreateDivider then menu:CreateDivider() end
                group = entry.group
                menu:CreateButton(addon.Commands.Label(entry), function() entry.run("") end)
            end
        end
        if menu.CreateDivider then menu:CreateDivider() end
        menu:CreateButton(L.CommandMenuTitle .. " …", function() addon.ShowCommandMenu(settings) end)
    end)
end
