local _, addon = ...
local L = addon.L
local feedbackWindow, profilesWindow
function addon.RefreshFeedbackManager()
    if feedbackWindow and feedbackWindow:IsShown() then feedbackWindow:Refresh() end
end

function addon.ShowFeedbackManager(actions)
    if not feedbackWindow then
        local frame = addon.UI.CreateUtilityPanel(590, 430, L.FeedbackManager)
        feedbackWindow = frame
        frame.rows = {}
        for index = 1, 5 do
            local row = CreateFrame("Frame", nil, frame)
            row:SetPoint("TOPLEFT", 18, -50 - (index - 1) * 62)
            row:SetPoint("TOPRIGHT", -18, -50 - (index - 1) * 62)
            row:SetHeight(54)
            row:EnableMouse(true)
            row.label = addon.UI.CreateLabel(row, "GameFontHighlightSmall")
            row.label:SetPoint("TOPLEFT")
            row.label:SetPoint("TOPRIGHT", -105, 0)
            row.label:SetJustifyH("LEFT")
            row.label:SetMaxLines(3)
            addon.UI.BindTooltip(row, function(self) return self.label:GetText(), L.FeedbackHelp end)
            row.clear = addon.UI.CreateUtilityButton(row, L.FeedbackClearShort, 96, function()
                frame.actions.clear(row.entry.id) frame:Refresh()
            end)
            row.clear:SetPoint("RIGHT")
            frame.rows[index] = row
        end
        frame.all = addon.UI.CreateUtilityButton(frame, L.FeedbackClearAll, 240, function() frame.actions.clearAll() frame:Refresh() end)
        frame.all:SetPoint("BOTTOM", 0, 16)
        frame.previous = addon.UI.CreateUtilityButton(frame, "<", 32, function() frame.page = math.max(1, frame.page - 1) frame:Refresh() end)
        frame.previous:SetPoint("BOTTOMLEFT", 18, 16)
        frame.next = addon.UI.CreateUtilityButton(frame, ">", 32, function() frame.page = frame.page + 1 frame:Refresh() end)
        frame.next:SetPoint("BOTTOMRIGHT", -18, 16)
        frame.status = addon.UI.CreateLabel(frame, "GameFontDisableSmall")
        frame.status:SetPoint("BOTTOM", 0, 55)
        function frame:Refresh()
            local entries = self.actions.list()
            local pages = math.max(1, math.ceil(#entries / 5))
            self.page = math.min(self.page, pages)
            for index, row in ipairs(self.rows) do
                row.entry = entries[(self.page - 1) * 5 + index]
                row:SetShown(row.entry ~= nil)
                if row.entry then
                    row.label:SetText(addon.UI.FormatQuestTitle(row.entry.quest) .. "\n"
                        .. L["FeedbackReason_" .. row.entry.kind] .. " · " .. L.FeedbackRemaining:format(math.ceil(row.entry.seconds)))
                end
            end
            self.previous:SetEnabled(self.page > 1) self.next:SetEnabled(self.page < pages)
            self.all:SetEnabled(#entries > 0)
            self.status:SetText(#entries == 0 and L.NoFeedback or (self.page .. " / " .. pages))
        end
        frame:SetScript("OnUpdate", function(self, elapsed)
            self.elapsed = (self.elapsed or 0) + elapsed
            if self.elapsed >= 1 then self.elapsed = 0 self:Refresh() end
        end)
    end
    feedbackWindow.actions, feedbackWindow.page = actions, 1
    feedbackWindow:Refresh() feedbackWindow:Show()
end

local function Value(value)
    if type(value) == "boolean" then return value and L.SettingOn or L.SettingOff end
    if value == "compact" then return L.DetailCompact end
    if value == "detailed" then return L.DetailDetailed end
    return tostring(value)
end
function addon.ShowAppearanceProfiles(settings, catalog)
    if not profilesWindow then
        local frame = addon.UI.CreateUtilityPanel(590, 440, L.AppearanceProfiles)
        profilesWindow = frame
        frame.description = addon.UI.CreateLabel(frame, "GameFontHighlightSmall")
        frame.description:SetPoint("TOPLEFT", 18, -48)
        frame.description:SetPoint("TOPRIGHT", -18, -48)
        frame.description:SetJustifyH("LEFT") frame.description:SetMaxLines(3)
        frame.description:SetText(L.ProfilesHelp)
        frame.buttons = {}
        for index, id in ipairs(addon.AppearanceProfiles.order) do
            local button = addon.UI.CreateUtilityButton(frame, L["Profile_" .. id], 170, function() frame.selected = id frame:Refresh() end)
            button:SetPoint("TOPLEFT", 18 + (index - 1) * 185, -108)
            frame.buttons[index] = button
        end
        frame.preview = addon.UI.CreateLabel(frame, "GameFontHighlightSmall")
        frame.preview:SetPoint("TOPLEFT", 18, -152)
        frame.preview:SetPoint("TOPRIGHT", -18, -152)
        frame.preview:SetJustifyH("LEFT")
        frame.preview:SetMaxLines(12)
        frame.apply = addon.UI.CreateUtilityButton(frame, L.ApplyProfile, 250, function()
            addon.AppearanceProfiles.Apply(frame.selected, frame.settings, frame.catalog, addon.Undo) frame:Refresh()
        end)
        frame.apply:SetPoint("BOTTOMLEFT", 18, 18)
        frame.undo = addon.UI.CreateUtilityButton(frame, L.UndoLatest, 250, function()
            addon.UndoLastChange() frame:Refresh()
        end)
        frame.undo:SetPoint("BOTTOMRIGHT", -18, 18)
        frame.transfer = addon.UI.CreateUtilityButton(frame, L.DisplayTransfer, 350, function()
            addon.ShowDisplayTransfer(frame.settings, frame.catalog)
        end)
        frame.transfer:SetPoint("BOTTOM", 0, 60)
        function frame:Refresh()
            local changes = addon.AppearanceProfiles.Changes(self.selected, self.settings, self.catalog)
            self.undo:SetEnabled(addon.Undo ~= nil and #addon.Undo.entries > 0)
            local lines = {L.ProfilePreview .. ": " .. L["Profile_" .. self.selected]}
            for _, change in ipairs(changes) do
                lines[#lines + 1] = change.name .. ": " .. Value(change.before) .. " -> " .. Value(change.after)
            end
            if #changes == 0 then lines[#lines + 1] = L.NoProfileChanges end
            self.preview:SetText(table.concat(lines, "\n")) self.apply:SetEnabled(#changes > 0)
            for index, id in ipairs(addon.AppearanceProfiles.order) do self.buttons[index]:SetText((id == self.selected and "> " or "") .. L["Profile_" .. id]) end
        end
    end
    profilesWindow.settings, profilesWindow.catalog, profilesWindow.selected = settings, catalog, "standard"
    profilesWindow:Refresh() profilesWindow:Show()
end
function addon.RefreshProfilePreview()
    if profilesWindow and profilesWindow:IsShown() then profilesWindow:Refresh() end
end
