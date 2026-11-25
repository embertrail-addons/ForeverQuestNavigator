local _, addon = ...
local L = addon.L
local window
function addon.ShowQuestWorkbench(controller, mode)
    if not window then
        local frame = addon.UI.CreateUtilityPanel(650, 650, L.QuestWorkspace)
        window = frame
        local function Button(parent, text, width, x, y, action)
            local button = addon.UI.CreateUtilityButton(parent, text, width, action)
            button:SetPoint("TOPLEFT", x, y) return button
        end
        frame.tour = Button(frame, L.MyTour, 170, 18, -48, function() frame:SelectMode("tour") end)
        frame.finder = Button(frame, L.QuestFinder, 170, 196, -48, function() frame:SelectMode("finder") end)
        frame.resume = Button(frame, L.ResumeNavigation, 150, 380, -48, function() frame.controller:Action("resume") frame:Refresh() end)
        frame.dismiss = Button(frame, L.DiscardSavedPlan, 92, 538, -48, function() frame.controller:Action("dismiss") frame:Refresh() end)
        frame.help = addon.UI.CreateLabel(frame, "GameFontHighlightSmall")
        frame.help:SetPoint("TOPLEFT", 18, -88) frame.help:SetPoint("TOPRIGHT", -18, -88)
        frame.help:SetJustifyH("LEFT") frame.help:SetMaxLines(3)
        frame.search = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
        frame.search:SetSize(600, 24) frame.search:SetPoint("TOPLEFT", 23, -136)
        frame.search:SetAutoFocus(false) frame.search:SetMaxLetters(120)
        frame.search:SetScript("OnTextChanged", function() frame.offset = 0 if frame.controller then frame:Refresh() end end)
        frame.search:SetScript("OnEditFocusGained", function() frame.placeholder:Hide() end)
        frame.search:SetScript("OnEditFocusLost", function() if frame.controller then frame:Refresh() end end)
        frame.placeholder = addon.UI.CreateLabel(frame.search, "GameFontDisableSmall")
        frame.placeholder:SetPoint("LEFT", 6, 0) frame.placeholder:SetText(L.FinderSearchPlaceholder)
        frame:EnableMouseWheel(true)
        frame:SetScript("OnMouseWheel", function(_, delta) frame:Scroll(-delta) end)
        function frame:Scroll(delta) self.offset = (self.offset or 0) + delta self:Refresh() end
        frame.search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        addon.UI.BindTooltip(frame.search, function() return L.QuestFinder, L.FinderHelp end)
        frame.filters = {}
        for index, entry in ipairs({{"all", L.FinderAll}, {"active", L.FinderActive}, {"offer", L.FinderOffers}, {"skipped", L.FinderSkipped}}) do
            local kind = entry[1]
            frame.filters[index] = Button(frame, entry[2], 148, 18 + (index - 1) * 155, -185,
                function() frame.kind, frame.offset = kind, 0 frame:Refresh() end)
            frame.filters[index].filterKind, frame.filters[index].filterLabel = kind, entry[2]
            frame.filters[index].selected = frame.filters[index]:CreateTexture(nil, "ARTWORK")
            frame.filters[index].selected:SetPoint("BOTTOMLEFT") frame.filters[index].selected:SetPoint("BOTTOMRIGHT")
            frame.filters[index].selected:SetHeight(2) addon.UI.Theme.Bind(frame.filters[index].selected, "heading", 1)
        end
        frame.rows = {}
        for index = 1, 5 do
            local row = Button(frame, "", 614, 18, -225 - (index - 1) * 52, function() end)
            row:SetHeight(46)
            row.textLabel:ClearAllPoints() row.textLabel:SetPoint("LEFT", 6, 0) row.textLabel:SetPoint("RIGHT", -220, 0)
            row.textLabel:SetJustifyH("LEFT") row.textLabel:SetMaxLines(2)
            row:SetScript("OnClick", function(self) if self.entry then frame.controller:Action("map", self.entry) end end)
            row:EnableMouseWheel(true)
            row:SetScript("OnMouseWheel", function(_, delta) frame:Scroll(-delta) end)
            local function RowAction(action)
                return function() if row.entry then frame.controller:Action(action, frame.mode == "tour" and row.entry.index or row.entry) frame:Refresh() end end
            end
            row.up = Button(row, "^", 28, 430, -10, RowAction("up"))
            row.down = Button(row, "v", 28, 464, -10, RowAction("down"))
            addon.UI.BindTooltip(row.up, function() return L.MoveTourUp end)
            addon.UI.BindTooltip(row.down, function() return L.MoveTourDown end)
            row.remove = Button(row, L.RemoveTourStop, 104, 502, -10, RowAction("remove"))
            row.primary = Button(row, L.PrioritizeShort, 100, 398, -10, function()
                if row.entry then
                    local action = row.entry.kind == "skipped" and "restore"
                        or row.entry.quest.id == frame.model.manualID and "clearPriority" or "priority"
                    frame.controller:Action(action, row.entry) frame:Refresh()
                end
            end)
            row.add = Button(row, L.AddToTour, 104, 502, -10, RowAction("add"))
            addon.UI.BindTooltip(row, function(self)
                local entry = self.entry
                if not entry then return end
                local _, state = addon.QuestState.Read(entry.quest, entry.kind == "offer", frame.model and entry.quest.id == frame.model.manualID)
                if entry.quest.special and not entry.quest.readyToTurnIn then state = state .. "\n" .. L.FinderSpecialHint end
                if entry.quest.failed then state = L.FinderFailed end
                if entry.quest.disabled then state = L.FinderDisabled end
                return addon.UI.FormatQuestTitle(entry.quest), state .. "\n" .. (entry.zone or L.UnknownZone) .. "\n" .. L.WorkspaceMapHelp
            end)
            addon.UI.LinkQuestHover(row, function(self) return self.entry and self.entry.quest.id end)
            frame.rows[index] = row
        end
        frame.previous = Button(frame, "^", 26, 564, -471, function() frame:Scroll(-4) end)
        frame.next = Button(frame, "v", 26, 596, -471, function() frame:Scroll(4) end)
        frame.pageLabel = addon.UI.CreateLabel(frame, "GameFontDisableSmall") frame.pageLabel:SetPoint("TOPRIGHT", -80, -477)
        frame.start = Button(frame, L.StartTour, 148, 18, -539, function()
            frame.controller:Action(frame.model.running and "pause" or "start") frame:Refresh()
        end)
        frame.optimize = Button(frame, L.PreviewTourOrder, 148, 173, -539, function() frame.controller:Action("preview") frame:Refresh() end)
        frame.apply = Button(frame, L.ApplyTourOrder, 148, 328, -539, function() frame.controller:Action("apply") frame:Refresh() end)
        frame.cancelPreview = Button(frame, L.CancelPreview, 148, 483, -539, function() frame.controller:Action("cancelPreview") frame:Refresh() end)
        frame.closing = Button(frame, L.PlanClosingRound, 148, 483, -539, function() frame.controller:Action("closing") frame.offset = 0 frame:Refresh() end)
        frame.share = Button(frame, L.TourShareButton, 148, 18, -539, function() if addon.ShareTour then addon.ShareTour() end end)
        addon.UI.BindTooltip(frame.share, function() return L.TourShareButton, L.TourShareHelp end)
        frame.returnHere = Button(frame, L.ReturnHere, 200, 18, -578, function() frame.controller:Action("returnHere") frame:Refresh() end)
        frame.returnMap = Button(frame, L.ShowReturnPoint, 200, 225, -578, function()
            if frame.model.returnPoint then frame.controller:Action("map", {target = frame.model.returnPoint}) end
        end)
        frame.clearReturn = Button(frame, L.ClearReturnPoint, 200, 432, -578, function() frame.controller:Action("clearReturn") frame:Refresh() end)
        frame.returnActions = Button(frame, "...", 32, 432, -578, function()
            if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
            MenuUtil.CreateContextMenu(frame.returnMap, function(_, menu)
                menu:CreateTitle(L.ReturnPoint)
                menu:CreateButton(L.ShowReturnPoint, function() frame.controller:Action("map", {target = frame.model.returnPoint}) end)
                menu:CreateButton(L.ReturnHere, function() frame.controller:Action("returnHere") frame:Refresh() end)
                menu:CreateButton(L.ClearReturnPoint, function() frame.controller:Action("clearReturn") frame:Refresh() end)
            end)
        end)
        addon.UI.BindTooltip(frame.returnActions, function() return L.MoreActions end)
        addon.UI.BindTooltip(frame.returnHere, function() return L.ReturnHere, L.ReturnHereHelp end)
        addon.UI.BindTooltip(frame.closing, function() return L.PlanClosingRound, L.ClosingRoundHelp end)
        frame.status = addon.UI.CreateLabel(frame, "GameFontHighlightSmall")
        frame.status:SetPoint("BOTTOMLEFT", 18, 14) frame.status:SetPoint("BOTTOMRIGHT", -18, 14) frame.status:SetJustifyH("LEFT")
        frame.status:SetMaxLines(2) frame.status:SetHeight(28)
        if frame.status.SetJustifyV then frame.status:SetJustifyV("BOTTOM") end
        frame.empty = addon.UI.CreateLabel(frame, "GameFontHighlightSmall")
        frame.empty:SetPoint("TOPLEFT", 35, -245) frame.empty:SetPoint("TOPRIGHT", -35, -245)
        frame.empty:SetJustifyH("CENTER") frame.empty:SetMaxLines(4)
        frame.emptyAction = Button(frame, L.QuestFinder, 230, 210, -330, function()
            if frame.mode == "tour" and frame.model.preview then frame.controller:Action("cancelPreview") frame:Refresh()
            elseif frame.mode == "tour" then frame:SelectMode("finder")
            elseif frame.model.missingData then frame.controller.context.changed() frame:Refresh()
            else frame.search:SetText("") frame.kind, frame.offset = "all", 0 frame:Refresh() end
        end)
        function frame:SelectMode(mode)
            self.pages = self.pages or {}
            if self.mode then self.pages[self.mode] = self.offset end
            self.mode, self.offset = mode, self.pages[mode] or 0
            self.hubPage = mode == "finder" and "finder" or "tour"
            self:Refresh()
            if self.embedded and addon.UI.ToolHub then addon.UI.ToolHub.Present(self, self.hubPage) end
        end
        function frame:OnEmbedded()
            self.tour:Hide() self.finder:Hide()
            self.layoutMode = nil self:Refresh()
        end
        function frame:Refresh()
            local model = self.controller:Model(self.search:GetText(), self.kind)
            self.model = model
            local tour = self.mode == "tour"
            local compactHeader = self.embedded and not model.pending and 40 or 0
            local layoutKey = self.mode .. ":" .. compactHeader
            if self.layoutMode ~= layoutKey then
                self.layoutMode = layoutKey self:SetHeight((tour and 575 or 610) - compactHeader)
                self.help:ClearAllPoints() self.help:SetPoint("TOPLEFT", 18, -88 + compactHeader) self.help:SetPoint("TOPRIGHT", -18, -88 + compactHeader)
                self.search:ClearAllPoints() self.search:SetPoint("TOPLEFT", 23, -136 + compactHeader)
                for index, button in ipairs(self.filters) do button:ClearAllPoints() button:SetPoint("TOPLEFT", 18 + (index - 1) * 155, -169 + compactHeader) end
                for index, row in ipairs(self.rows) do row:ClearAllPoints() row:SetPoint("TOPLEFT", 18, -(tour and 150 or 209) + compactHeader - (index - 1) * 52) end
                self.previous:ClearAllPoints() self.previous:SetPoint("TOPLEFT", 564, (tour and -414 or -471) + compactHeader)
                self.next:ClearAllPoints() self.next:SetPoint("TOPLEFT", 596, (tour and -414 or -471) + compactHeader)
                self.pageLabel:ClearAllPoints() self.pageLabel:SetPoint("TOPRIGHT", -80, (tour and -420 or -477) + compactHeader)
                self.returnHere:ClearAllPoints() self.returnHere:SetPoint("TOPLEFT", 18, (tour and -503 or -578) + compactHeader)
                self.returnMap:ClearAllPoints() self.returnMap:SetPoint("TOPLEFT", 18, (tour and -503 or -578) + compactHeader)
                self.returnMap:SetWidth(480)
                self.returnActions:ClearAllPoints() self.returnActions:SetPoint("TOPLEFT", 505, (tour and -503 or -578) + compactHeader)
                self.resume:ClearAllPoints() self.resume:SetPoint("TOPLEFT", self.embedded and 18 or 380, -48)
                self.dismiss:ClearAllPoints() self.dismiss:SetPoint("TOPLEFT", self.embedded and 176 or 538, -48)
            end
            self.help:SetText(tour and (L.TourEditorHelp .. (model.returnPoint and ("\n" .. L.ReturnPointSaved:format(model.returnPoint.name)) or "")) or L.FinderHelp)
            self.search:SetShown(not tour)
            self.placeholder:SetShown(not tour and (self.search:GetText() or "") == "" and not (self.search.HasFocus and self.search:HasFocus()))
            for _, button in ipairs(self.filters) do
                button:SetShown(not tour) button.selected:SetShown(self.kind == button.filterKind)
                button:SetText(button.filterLabel .. " (" .. model.counts[button.filterKind] .. ")")
            end
            self.resume:SetShown(model.pending)
            self.dismiss:SetShown(model.pending)
            local entries = tour and model.tour or model.entries
            self.offset = math.max(0, math.min(self.offset or 0, #entries - #self.rows))
            for index, row in ipairs(self.rows) do
                local entry = entries[self.offset + index]
                row.entry = entry row:SetShown(entry ~= nil)
                if entry then
                    local symbol, state = addon.QuestState.Read(entry.quest, entry.kind == "offer", entry.quest.id == model.manualID)
                    local prefix = tour and (entry.index .. ". ") or entry.kind == "skipped" and "- " or (symbol .. " ")
                    if not tour and entry.kind ~= "skipped" and addon.UI.iconLabels then
                        prefix = addon.UI.ActionIcon(entry.kind == "offer" and "accept" or entry.quest.readyToTurnIn and "turnIn" or "objective") .. " "
                    end
                    local stage = tour and (entry.stage == "turnIn" and L.StateTurnIn or L.StateObjective) or entry.kind == "skipped" and L.FinderSkipped or state
                    if not tour and entry.kind ~= "skipped" then
                        stage = entry.quest.failed and L.FinderFailed or entry.quest.disabled and L.FinderDisabled
                            or entry.quest.special and not entry.quest.readyToTurnIn and L.FinderSpecial or stage
                    end
                    if addon.UI.iconLabels then stage = stage:gsub("^[>?!*] ", "") end
                    row:SetText(prefix .. addon.UI.FormatQuestTitle(entry.quest, nil, nil, true) .. "\n" .. stage .. " · " .. (entry.zone or L.UnknownZone))
                    row.up:SetShown(tour) row.down:SetShown(tour) row.remove:SetShown(tour)
                    row.up:SetEnabled(tour and not model.preview and entry.index > 1)
                    row.down:SetEnabled(tour and not model.preview and entry.index < #entries)
                    row.remove:SetEnabled(not model.preview)
                    row.primary:SetShown(not tour and entry.kind ~= "offer")
                    row.primary:SetText(entry.kind == "skipped" and L.RestoreFinderQuest or entry.quest.id == model.manualID and L.UnpinShort or L.PrioritizeShort)
                    local usable = entry.kind == "skipped" or not (entry.quest.failed or entry.quest.disabled or (entry.quest.special and not entry.quest.readyToTurnIn))
                    row.primary:SetEnabled(usable) row.add:SetEnabled(usable)
                    row.add:SetShown(not tour and entry.kind == "active")
                    row.add:SetText(model.inTour[entry.quest.id] and L.InTourShort or L.AddToTour)
                    row.add:SetEnabled(usable and not model.inTour[entry.quest.id])
                end
            end
            local scrolls = #entries > #self.rows
            self.previous:SetEnabled(self.offset > 0) self.next:SetEnabled(self.offset + #self.rows < #entries)
            self.previous:SetShown(scrolls) self.next:SetShown(scrolls)
            self.pageLabel:SetText(scrolls and L.ListCount:format(self.offset + 1, math.min(#entries, self.offset + #self.rows), #entries) or "")
            self.start:SetShown(tour and not model.preview and (#model.tour > 0 or model.returnPoint ~= nil))
            self.optimize:SetShown(tour and #model.tour > 1 and not model.running and not model.preview)
            self.apply:SetShown(tour and model.preview) self.cancelPreview:SetShown(tour and model.preview)
            self.closing:SetShown(tour and model.closingCount > 0 and not model.running and not model.preview)
            self.share:SetShown(tour and #model.tour > 0 and not model.preview and addon.ShareTour ~= nil)
            self.returnHere:SetShown(tour and not model.returnPoint)
            self.returnMap:SetShown(tour and model.returnPoint ~= nil)
            self.returnActions:SetShown(tour and model.returnPoint ~= nil)
            self.clearReturn:Hide()
            if model.returnPoint then self.returnMap:SetText(L.ReturnPointSaved:format(model.returnPoint.name)) end
            self.start:SetText(model.running and L.PauseTour or #model.tour == 0 and L.ReturnNow or L.StartTour)
            self.start:SetEnabled(not model.preview and (#model.tour > 0 or model.returnPoint ~= nil))
            self.optimize:SetEnabled(#model.tour > 1 and not model.running)
            self.apply:SetEnabled(model.preview)
            self.returnMap:SetEnabled(model.returnPoint ~= nil) self.clearReturn:SetEnabled(model.returnPoint ~= nil)
            local buttons = {}
            for _, button in ipairs({self.start, self.optimize, self.apply, self.cancelPreview, self.closing, self.share}) do if button:IsShown() then buttons[#buttons + 1] = button end end
            local buttonWidth = math.min(196, (614 - (#buttons - 1) * 7) / math.max(1, #buttons))
            for index, button in ipairs(buttons) do button:SetWidth(buttonWidth) button:ClearAllPoints() button:SetPoint("TOPLEFT", 18 + (index - 1) * (buttonWidth + 7), (tour and -464 or -539) + compactHeader) end
            self.empty:SetShown(#entries == 0) self.emptyAction:SetShown(#entries == 0)
            self.empty:SetText(tour and (model.preview and L.EmptyPreviewHelp or L.EmptyTourHelp) or model.missingData and L.QuestLogUnavailable or L.EmptyFinderHelp)
            self.emptyAction:SetText(tour and (model.preview and L.CancelPreview or L.QuestFinder) or model.missingData and L.RetryData or L.ClearSearch)
            local previewText = model.preview and (model.previewSaved and (L.TourPreviewSaved:format(model.previewSaved) .. " " .. L.TourPreviewHelp)
                or L.TourPreviewHelp)
            self.status:SetText(self.controller.status or previewText or model.running and L.TourRunning or "")
            addon.QuestHover.Refresh()
        end
        addon.UI.RefreshWhileShown(frame, 1)
    end
    local changed = window.controller ~= controller
    window.controller = controller
    if changed then window.pages, window.kind = {}, "all" window.mode, window.offset = mode or "tour", 0 window.search:SetText("") end
    window:SelectMode(mode or window.mode or "tour")
    addon.UI.ShowUtilityPanel(window, window.hubPage) return window
end
