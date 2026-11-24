local _, addon = ...
local L = addon.L
local Panel, Button = addon.UI.CreateUtilityPanel, addon.UI.CreateUtilityButton
local notes, guide

function addon.ShowQuestNotepad(actions)
    if not notes then
        notes = Panel(570, 410, L.QuestNotepad)
        notes.rows, notes.offset = {}, 0
        notes.empty = addon.UI.CreateLabel(notes, "GameFontHighlightSmall")
        notes.empty:SetPoint("TOPLEFT", 16, -50)
        notes.empty:SetPoint("TOPRIGHT", -16, -50)
        notes.empty:SetJustifyH("LEFT")
        notes.empty:SetText(L.EmptyNotepad)
        for index = 1, 5 do
            local row = CreateFrame("Frame", nil, notes)
            row:SetPoint("TOPLEFT", 16, -51 - (index - 1) * 58)
            row:SetPoint("TOPRIGHT", -16, -51 - (index - 1) * 58)
            row:SetHeight(54)
            row.label = addon.UI.CreateLabel(row, "GameFontHighlightSmall")
            row.label:SetPoint("TOPLEFT")
            row.label:SetPoint("TOPRIGHT", -150, 0)
            row.label:SetJustifyH("LEFT")
            row.label:SetMaxLines(2)
            row:EnableMouse(true)
            addon.UI.BindTooltip(row, function(self)
                return self.entry and self.entry.title, self.entry and self.entry.text or L.NotepadMapHelp
            end)
            row.map = Button(row, L.Map, 62, function() notes.actions.map(row.entry) end)
            row.map:SetPoint("TOPRIGHT")
            row.remove = Button(row, L.RemoveNote, 78, function()
                notes.actions.remove(row.entry.id)
                notes:Refresh()
            end)
            row.remove:SetPoint("TOPRIGHT", -70, 0)
            notes.rows[index] = row
        end
        notes.previous = Button(notes, "^", 35, function() end)
        notes.previous:SetPoint("BOTTOMLEFT", 16, 16)
        notes.next = Button(notes, "v", 35, function() end)
        notes.next:SetPoint("BOTTOMLEFT", 59, 16)
        local hint = addon.UI.CreateLabel(notes, "GameFontDisableSmall")
        hint:SetPoint("BOTTOMRIGHT", -16, 20)
        hint:SetText(L.NotepadIndependent)
        notes.count = addon.UI.CreateLabel(notes, "GameFontDisableSmall")
        notes.count:SetPoint("BOTTOMLEFT", 104, 20)
        local paging = addon.UI.ScrollPaging(notes, notes.rows, function() notes:Refresh() end)
        function notes:Refresh()
            local entries = self.actions.list()
            local offset = paging:Clamp(#entries)
            self.empty:SetShown(#entries == 0)
            self.count:SetText(paging:Update(#entries) or "")
            for index, row in ipairs(self.rows) do
                local entry = entries[offset + index]
                row.entry = entry
                row:SetShown(entry ~= nil)
                if entry then
                    row.label:SetText(entry.title .. "\n" .. (entry.text or entry.status))
                    row.map:SetEnabled(entry.point ~= nil)
                end
            end
        end
    end
    notes.actions = actions
    notes:Refresh()
    addon.UI.ShowUtilityPanel(notes)
    return notes
end

function addon.ShowIntroduction(settings)
    if not guide then
        guide = Panel(470, 270, L.Introduction)
        guide.body = addon.UI.CreateLabel(guide, "GameFontHighlight")
        guide.body:SetPoint("TOPLEFT", 20, -55)
        guide.body:SetPoint("TOPRIGHT", -20, -55)
        guide.body:SetJustifyH("LEFT")
        guide.body:SetMaxLines(8)
        guide.counter = addon.UI.CreateLabel(guide, "GameFontDisableSmall")
        guide.counter:SetPoint("BOTTOMLEFT", 20, 56)
        guide.skip = Button(guide, L.CloseIntro, 190, function() guide:Hide() end)
        guide.skip:SetPoint("BOTTOMLEFT", 20, 20)
        guide.next = Button(guide, L.NextIntro, 145, function()
            if guide.step == 3 then guide:Hide() else guide.step = guide.step + 1 guide:Refresh() end
        end)
        guide.next:SetPoint("BOTTOMRIGHT", -20, 20)
        function guide:Refresh()
            self.body:SetText(({ L.IntroArrow, L.IntroSkip, L.IntroMenu })[self.step])
            self.counter:SetText(("%d / 3"):format(self.step))
            self.next:SetText(self.step == 3 and L.FinishIntro or L.NextIntro)
        end
        guide:SetScript("OnHide", function(self) self.settings.introSeen = true end)
    end
    guide.settings, guide.step = settings, 1
    guide:Refresh()
    addon.UI.ShowUtilityPanel(guide)
    return guide
end

function addon.RefreshQuestNotepad()
    if notes and notes:IsShown() then notes:Refresh() end
end
