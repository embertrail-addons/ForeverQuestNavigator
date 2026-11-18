local _, addon = ...
local L = addon.L
local dashboard, accessWindow, preview

local function Panel(width, height, title)
    local frame = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    frame:SetSize(width, height)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetBackdrop({ bgFile = "Interface/Buttons/WHITE8X8", edgeFile = "Interface/Buttons/WHITE8X8", edgeSize = 1 })
    addon.UI.Theme.WatchFrame(frame)
    frame.heading = addon.UI.CreateLabel(frame, "GameFontNormal")
    frame.heading:SetPoint("TOPLEFT", 16, -14)
    frame.heading:SetPoint("TOPRIGHT", -45, -14)
    frame.heading:SetJustifyH("LEFT")
    frame.heading:SetText(title)
    local close = addon.UI.MakeButton(frame)
    close:SetSize(25, 24)
    close:SetPoint("TOPRIGHT", -8, -8)
    close:SetText("X")
    close:SetScript("OnClick", function() frame:Hide() end)
    return frame
end

local function Button(parent, text, width, action)
    local button = addon.UI.MakeButton(parent)
    button:SetSize(width, 24)
    button:SetText(text)
    button:SetScript("OnClick", action)
    return button
end

function addon.ShowSessionDashboard(getSession, now)
    if not dashboard then
        dashboard = Panel(570, 480, L.SessionTitle)
        dashboard.cards, dashboard.rows = {}, {}
        local labels = { L.StatTime, L.StatXP, L.StatTurnIns, L.StatQuestXP, L.StatLevels, L.StatUnknownRewards }
        for index, text in ipairs(labels) do
            local x, y = 16 + ((index - 1) % 2) * 269, -48 - math.floor((index - 1) / 2) * 61
            local label = addon.UI.CreateLabel(dashboard, "GameFontNormalSmall")
            label:SetPoint("TOPLEFT", x, y)
            label:SetText(text)
            local value = addon.UI.CreateLabel(dashboard, "GameFontHighlight")
            value:SetPoint("TOPLEFT", x, y - 21)
            dashboard.cards[index] = value
        end
        local heading = addon.UI.CreateLabel(dashboard, "GameFontNormalSmall")
        heading:SetPoint("TOPLEFT", 16, -234)
        heading:SetText(L.SessionRecent)
        dashboard.offset = 0
        for index = 1, 5 do
            local row = CreateFrame("Button", nil, dashboard)
            row:SetPoint("TOPLEFT", 16, -255 - (index - 1) * 32)
            row:SetPoint("TOPRIGHT", -16, -255 - (index - 1) * 32)
            row:SetHeight(29)
            row.label = addon.UI.CreateLabel(row, "GameFontHighlightSmall")
            row.label:SetPoint("LEFT")
            row.label:SetPoint("RIGHT", -100, 0)
            row.label:SetMaxLines(1)
            row.label:SetJustifyH("LEFT")
            row.reward = addon.UI.CreateLabel(row, "GameFontHighlightSmall")
            row.reward:SetPoint("RIGHT")
            addon.UI.BindTooltip(row, function(self) return self.label:GetText(), self.reward:GetText() end)
            row:EnableMouseWheel(true)
            row:SetScript("OnMouseWheel", function(_, delta)
                dashboard.offset = math.max(0, dashboard.offset - delta)
                dashboard:Refresh()
            end)
            dashboard.rows[index] = row
        end
        dashboard.copy = Button(dashboard, L.CopySummary, 160, function()
            dashboard:Refresh()
            addon.ShowTextWindow("session-copy", dashboard.copyText, L.CopySummary, L.DebugCopyHint)
        end)
        dashboard.copy:SetPoint("BOTTOMLEFT", 16, 14)
        local hint = addon.UI.CreateLabel(dashboard, "GameFontDisableSmall")
        hint:SetPoint("BOTTOMRIGHT", -16, 18)
        hint:SetText(L.LiveSessionHint)
        function dashboard:Refresh()
            local session = self.getSession()
            local current = self.now()
            local data, seconds = session.data, session:Elapsed(current)
            local values = { ("%02d:%02d:%02d"):format(math.floor(seconds / 3600), math.floor(seconds / 60) % 60, seconds % 60),
                data.lowerBound and L.AtLeast:format(data.xp) or tostring(data.xp), tostring(data.completed),
                tostring(data.questXP), tostring(data.levels), tostring(data.unknownRewards) }
            for index, value in ipairs(values) do self.cards[index]:SetText(value) end
            self.copyText = session:Describe(current)
            self.offset = math.min(self.offset, math.max(0, #data.recent - 5))
            for index, row in ipairs(self.rows) do
                local entry = data.recent[index + self.offset]
                row:SetShown(type(entry) == "table")
                if type(entry) == "table" then
                    row.label:SetText(entry.title or L.QuestNumber:format(entry.id))
                    row.reward:SetText(entry.xp and L.SessionReward:format(entry.xp) or L.UnknownXP)
                end
            end
        end
        dashboard:SetScript("OnUpdate", function(self, elapsed)
            if not self:IsShown() then return end
            self.elapsed = (self.elapsed or 0) + elapsed
            if self.elapsed >= 1 then self.elapsed = 0 self:Refresh() end
        end)
    end
    dashboard.getSession, dashboard.now = getSession, now
    dashboard:Refresh()
    dashboard:Show()
end

function addon.ShowAccessManager(actions)
    if not accessWindow then
        accessWindow = Panel(650, 570, L.AccessManager)
        accessWindow.page, accessWindow.rows, accessWindow.filterMode = 0, {}, "all"
        accessWindow.empty = addon.UI.CreateLabel(accessWindow, "GameFontHighlightSmall")
        accessWindow.empty:SetPoint("TOPLEFT", 16, -105)
        accessWindow.empty:SetPoint("TOPRIGHT", -16, -105)
        accessWindow.empty:SetJustifyH("LEFT")
        accessWindow.empty:SetText(L.NoSavedAccess)
        for index = 1, 5 do
            local row = CreateFrame("Frame", nil, accessWindow)
            row:SetPoint("TOPLEFT", 16, -110 - (index - 1) * 76)
            row:SetPoint("TOPRIGHT", -16, -110 - (index - 1) * 76)
            row:SetHeight(72)
            row.label = addon.UI.CreateLabel(row, "GameFontHighlightSmall")
            row.label:SetPoint("TOPLEFT")
            row.label:SetPoint("TOPRIGHT", -175, 0)
            row.label:SetJustifyH("LEFT")
            row.label:SetMaxLines(1)
            row.position = addon.UI.CreateLabel(row, "GameFontDisableSmall")
            row.position:SetPoint("TOPLEFT", 0, -21)
            row.position:SetPoint("TOPRIGHT", -175, -21)
            row.position:SetJustifyH("LEFT")
            row.position:SetMaxLines(1)
            row:EnableMouse(true)
            addon.UI.BindTooltip(row, function(self)
                return self.label:GetText(), (self.position:GetText() or "") .. "\n" .. (self.edit:GetText() or "")
            end)
            row.edit = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
            row.edit:SetSize(275, 24)
            row.edit:SetPoint("BOTTOMLEFT", 5, 0)
            row.edit:SetAutoFocus(false)
            row.edit:SetMaxLetters(60)
            row.edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
            row.map = Button(row, L.Map, 76, function() accessWindow.actions.map(row.entry) end)
            row.map:SetPoint("TOPRIGHT")
            row.remove = Button(row, L.DeleteAccess, 76, function()
                accessWindow.actions.remove(row.entry)
                accessWindow:Refresh()
            end)
            row.remove:SetPoint("TOPRIGHT", -84, 0)
            local function Rename()
                if accessWindow.actions.rename(row.entry, row.edit:GetText()) then
                    row.edit:ClearFocus()
                    accessWindow:Refresh()
                end
            end
            row.save = Button(row, L.SaveShort, 90, Rename)
            row.save:SetPoint("BOTTOMRIGHT", -70, 0)
            row.route = Button(row, L.EditAccessRoute, 62, function() if accessWindow.actions.route then accessWindow.actions.route(row.entry) end end)
            row.route:SetPoint("BOTTOMRIGHT")
            row.edit:SetScript("OnEnterPressed", Rename)
            accessWindow.rows[index] = row
        end
        accessWindow.previous = Button(accessWindow, "<", 35, function()
            accessWindow.page = math.max(0, accessWindow.page - 1)
            accessWindow:Refresh()
        end)
        accessWindow.previous:SetPoint("BOTTOMLEFT", 16, 16)
        accessWindow.next = Button(accessWindow, ">", 35, function()
            accessWindow.page = accessWindow.page + 1
            accessWindow:Refresh()
        end)
        accessWindow.next:SetPoint("BOTTOMLEFT", 59, 16)
        accessWindow.count = addon.UI.CreateLabel(accessWindow, "GameFontHighlightSmall")
        accessWindow.count:SetPoint("BOTTOMRIGHT", -16, 20)
        function accessWindow:Refresh()
            local all = self.actions.list()
            local entries = self.actions.filter(all, self.search:GetText(), self.filterMode)
            self.page = math.min(self.page, math.max(0, math.ceil(#entries / 5) - 1))
            self.empty:SetShown(#entries == 0)
            self.empty:SetText(#all == 0 and L.NoSavedAccess or L.NoAccessMatches)
            self.previous:SetEnabled(self.page > 0)
            self.next:SetEnabled((self.page + 1) * 5 < #entries)
            self.count:SetText(L.AccessShowing:format(#entries, #all))
            for index, row in ipairs(self.rows) do
                local entry = entries[self.page * 5 + index]
                row.entry = entry
                row:SetShown(entry ~= nil)
                if entry then
                    row.label:SetText(entry.title)
                    row.position:SetText(entry.zone .. (" (%.1f, %.1f)"):format(entry.point.x * 100, entry.point.y * 100))
                    if (entry.stepCount or 1) > 1 then row.position:SetText(row.position:GetText() .. " · " .. L.AccessStepCount:format(entry.stepCount, 8)) end
                    row.edit:SetText(entry.name or L.SavedAccess)
                end
            end
        end
        local label = addon.UI.CreateLabel(accessWindow, "GameFontDisableSmall")
        label:SetPoint("TOPLEFT", 16, -40)
        label:SetText(L.SearchAccess)
        accessWindow.search = CreateFrame("EditBox", nil, accessWindow, "InputBoxTemplate")
        accessWindow.search:SetSize(400, 24)
        accessWindow.search:SetPoint("TOPLEFT", 24, -61)
        accessWindow.search:SetAutoFocus(false)
        accessWindow.search:SetMaxLetters(100)
        accessWindow.search:SetText("")
        accessWindow.search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        accessWindow.search:SetScript("OnTextChanged", function()
            if not accessWindow.actions then return end
            accessWindow.page = 0
            accessWindow:Refresh()
        end)
        accessWindow.filter = Button(accessWindow, L.FilterAll, 185, function()
            local modes = { "all", "current", "completed" }
            for index, mode in ipairs(modes) do
                if mode == accessWindow.filterMode then accessWindow.filterMode = modes[index % 3 + 1] break end
            end
            accessWindow.filter:SetText(({ all = L.FilterAll, current = L.FilterCurrent, completed = L.FilterCompleted })[accessWindow.filterMode])
            accessWindow.page = 0
            accessWindow:Refresh()
        end)
        accessWindow.filter:SetPoint("TOPRIGHT", -16, -61)
    end
    accessWindow.actions = actions
    accessWindow:Refresh()
    accessWindow:Show()
end

addon.UI.CreateUtilityPanel = Panel
addon.UI.CreateUtilityButton = Button
function addon.RefreshAccessManager()
    if accessWindow and accessWindow:IsShown() then accessWindow:Refresh() end
end

function addon.ShowAppearancePreview(settings)
    if not preview then
        preview = Panel(430, 200, L.AppearancePreview)
        local backdrop = preview:CreateTexture(nil, "BACKGROUND")
        backdrop:SetPoint("TOPLEFT", 16, -49)
        backdrop:SetPoint("BOTTOMRIGHT", -16, 16)
        preview.sampleBackdrop = backdrop
        preview.sample = addon.UI.CreateLabel(preview, "GameFontNormal")
        preview.sample:SetPoint("TOPLEFT", 28, -63)
        preview.sample:SetText(L.PreviewQuest)
        preview.detail = addon.UI.CreateLabel(preview, "GameFontHighlightSmall")
        preview.detail:SetPoint("TOPLEFT", preview.sample, "BOTTOMLEFT", 0, -12)
        preview.detail:SetText(L.PreviewProgress)
        preview.xp = addon.UI.CreateLabel(preview, "GameFontHighlightSmall")
        preview.xp:SetPoint("TOPLEFT", preview.detail, "BOTTOMLEFT", 0, -10)
        preview.xp:SetText(L.PreviewXP)
    end
    preview.settings = settings
    preview:Show()
    addon.RefreshAppearancePreview()
end

function addon.RefreshAppearancePreview()
    if not (preview and preview:IsShown()) then return end
    local settings = preview.settings
    preview.sampleBackdrop:SetColorTexture(0.35, 0.24, 0.1, settings.opacityPercent / 100)
    preview.sample:SetFontObject(addon.UI.GetFont("GameFontNormal"))
    preview.detail:SetFontObject(addon.UI.GetFont("GameFontHighlightSmall"))
    preview.xp:SetFontObject(addon.UI.GetFont("GameFontHighlightSmall"))
    preview.xp:SetShown(settings.detailMode ~= "compact" and settings.showQuestXP)
end
