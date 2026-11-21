local _, addon = ...
local L = addon.L
local editor, camps
function addon.ShowQuestNoteEditor(id, title, text, save)
    if not editor then
        editor = addon.UI.CreateUtilityPanel(520, 300, L.QuestNoteEditor)
        editor.hubStandalone = true
        editor.quest = addon.UI.CreateLabel(editor, "GameFontHighlightSmall")
        editor.quest:SetPoint("TOPLEFT", 20, -48) editor.quest:SetPoint("TOPRIGHT", -20, -48) editor.quest:SetMaxLines(2)
        editor.scroll = CreateFrame("ScrollFrame", nil, editor, "UIPanelScrollFrameTemplate")
        editor.scroll:SetPoint("TOPLEFT", 24, -100) editor.scroll:SetSize(450, 105)
        editor.measure = addon.UI.CreateLabel(editor, "GameFontHighlightSmall")
        editor.measure:SetWidth(440) editor.measure:Hide()
        editor.edit = CreateFrame("EditBox", nil, editor.scroll, "InputBoxTemplate")
        editor.edit:SetSize(440, 105) editor.scroll:SetScrollChild(editor.edit)
        editor.edit:SetMultiLine(true) editor.edit:SetAutoFocus(false) editor.edit:SetMaxLetters(240)
        editor.edit:SetFontObject(addon.UI.GetFont("GameFontHighlightSmall"))
        editor.edit:SetScript("OnTextChanged", function(self)
            editor.measure:SetText(self:GetText() or "") self:SetHeight(math.max(105, editor.measure:GetStringHeight() + 12))
            if editor.scroll.UpdateScrollChildRect then editor.scroll:UpdateScrollChildRect() end
        end)
        editor.edit:SetScript("OnCursorChanged", function(self, x, y, width, height)
            if ScrollingEdit_OnCursorChanged then ScrollingEdit_OnCursorChanged(self, x, y, width, height) end
        end)
        editor.edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        editor.save = addon.UI.CreateUtilityButton(editor, L.SaveQuestNote, 230, function()
            editor.saveNote(editor.edit:GetText()) editor:Hide()
        end)
        editor.save:SetPoint("BOTTOMLEFT", 20, 20)
        editor.clear = addon.UI.CreateUtilityButton(editor, L.ClearQuestNote, 230, function()
            editor.saveNote("") editor:Hide()
        end)
        editor.clear:SetPoint("BOTTOMRIGHT", -20, 20)
    end
    editor.quest:SetText(title or L.QuestNumber:format(id)) editor.saveNote = save
    editor.edit:SetText(text or "") editor.scroll:SetVerticalScroll(0) editor:Show()
    return editor
end
function addon.ShowCampChoices(getModel, map, select)
    if not camps then
        camps = addon.UI.CreateUtilityPanel(610, 440, L.CampChoices)
        camps.hubStandalone = true
        camps.help = addon.UI.CreateLabel(camps, "GameFontHighlightSmall")
        camps.help:SetPoint("TOPLEFT", 18, -48) camps.help:SetPoint("TOPRIGHT", -18, -48)
        camps.help:SetJustifyH("LEFT") camps.help:SetMaxLines(3) camps.help:SetText(L.CampChoicesHelp)
        camps.rows = {}
        for index = 1, 4 do
            local row = CreateFrame("Frame", nil, camps)
            row:SetPoint("TOPLEFT", 18, -127 - (index - 1) * 64) row:SetSize(574, 58)
            row.label = addon.UI.CreateLabel(row, "GameFontHighlightSmall")
            row.label:SetPoint("TOPLEFT") row.label:SetPoint("TOPRIGHT", -180, 0) row.label:SetJustifyH("LEFT") row.label:SetMaxLines(3)
            row:EnableMouse(true)
            addon.UI.BindTooltip(row, function(self) return self.label:GetText(), (self.choice and self.choice.reason or "") .. "\n" .. L.CampChoicesHelp end)
            row.map = addon.UI.CreateUtilityButton(row, L.Map, 64, function() if row.choice then camps.map(row.choice) end end)
            row.map:SetPoint("RIGHT", -100, 0)
            row.select = addon.UI.CreateUtilityButton(row, L.ChooseCamp, 94, function()
                if row.choice then camps.select(row.choice) camps:Refresh() end
            end)
            row.select:SetPoint("RIGHT") camps.rows[index] = row
        end
        camps.previous = addon.UI.CreateUtilityButton(camps, "<", 32, function() camps.page = math.max(1, camps.page - 1) camps:Refresh() end)
        camps.previous:SetPoint("BOTTOMLEFT", 18, 18)
        camps.next = addon.UI.CreateUtilityButton(camps, ">", 32, function() camps.page = camps.page + 1 camps:Refresh() end)
        camps.next:SetPoint("BOTTOMRIGHT", -18, 18)
        function camps:Refresh()
            local choices = self.getModel() or {}
            local pages = math.max(1, math.ceil(#choices / 4)) self.page = math.min(self.page, pages)
            for index, row in ipairs(self.rows) do
                local ordinal = (self.page - 1) * 4 + index
                row.choice = choices[ordinal] row:SetShown(row.choice ~= nil)
                if row.choice then row.label:SetText(L.CampChoice:format(ordinal, row.choice.yards, row.choice.shared)
                    .. (ordinal == 1 and ("\n" .. L.CampCurrent) or "")) end
            end
            self.previous:SetEnabled(self.page > 1) self.next:SetEnabled(self.page < pages)
        end
    end
    camps.getModel, camps.map, camps.select, camps.page = getModel, map, select, 1
    camps:Refresh() camps:Show()
    return camps
end
