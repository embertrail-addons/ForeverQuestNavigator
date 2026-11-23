return function(test, equal, near, mockUI, loadAddon)
    local function Fixture(locale)
        local frames, createFrame, createFont = mockUI()
        local parent = createFrame()
        parent:SetSize(1920, 1080)
        local time, maps, skipped = 0, {}, {}
        local env = setmetatable({CreateFrame = createFrame, CreateFont = createFont, UIParent = parent,
            UISpecialFrames = {}, GetLocale = function() return locale or "enUS" end, GetTime = function() return time end,
            print = function() end}, {__index = getfenv()})
        env.GameTooltip = {IsOwned = function() return false end, Hide = function() end,
            SetOwner = function() end, SetText = function() end, AddLine = function() end, Show = function() end}
        local addon = loadAddon(env, false)
        local settings = {x = 0, y = 0, opacityPercent = 80, fontPercent = 100, showQuestRewards = false,
            showScreenArrow = true, acceptedRows = 2, offerRows = 3, environmentExpanded = true}
        local actions = {openQuestMap = function(id) maps[#maps + 1] = id end,
            openOfferMap = function(id) maps[#maps + 1] = id end,
            skip = function(quest) skipped[#skipped + 1] = quest.id end,
            resumeAutoSelect = function() maps[#maps + 1] = "resume" end,
            openFinder = function() maps[#maps + 1] = "finder" end,
            hideTracker = function() end, openSettings = function() end,
            restore = function() end, resetSkips = function() end}
        local tracker = addon.CreateQuestTracker(settings, actions, "test")
        function tracker:GetLeft() return 600 end
        function tracker:GetRight() return 952 end
        function tracker:GetEffectiveScale() return 1 end
        function parent:GetEffectiveScale() return 1 end
        local a = {id = 1, title = "Active quest", level = 10}
        local b = {id = 2, title = "Other quest", level = 10}
        local c = {id = 3, title = "Third quest", level = 10}
        local function Render(alternatives, manual, targets)
            alternatives = alternatives or {b, c}
            local zones, routes, rewards = {}, {}, {"~100 XP"}
            for index, quest in ipairs(alternatives) do
                zones[index + 1], routes[index], rewards[index + 1] = "Zone " .. quest.id, "Route " .. quest.id, "XP " .. quest.id
            end
            tracker:Render(a, "Defeat enemies: 2/8", {}, alternatives, manual == true, nil,
                "Main route details", zones, routes, nil, rewards, targets or {index = 1,
                    {index = 1, text = "Defeat enemies: 2/8", selectable = true},
                    {index = 2, text = "Collect supplies: 0/3", selectable = true}}, true)
        end
        Render()
        return addon, tracker, settings, maps, skipped, Render, b, c, parent, env, frames
    end
    test("Navigator details open beside the tracker without moving the list and close persistently", function()
        local _, tracker, _, maps, _, render = Fixture()
        local height = tracker:GetHeight()
        tracker.routeToggle:Click()
        local pane = tracker.detailPanel
        equal(pane.placement, "right") assert(pane:IsShown())
        equal(tracker.routeDetails.parent, pane.body)
        equal(tracker:GetHeight(), height)
        pane.map:Click() equal(maps[1], 1)
        pane.closeButton:Click() render()
        equal(pane:IsShown(), false)
        tracker.routeToggle:Click() assert(pane:IsShown())
        equal(tracker:GetHeight(), height)
    end)
    test("All quest details share one pane and keep the correct map action", function()
        local _, tracker, _, maps = Fixture()
        tracker.routeToggle:Click()
        local row = tracker.acceptedRows[1]
        local height = row:GetHeight()
        row.detailButton:Click()
        equal(tracker.routeDetails:IsShown(), false)
        equal(row.routeDetails.parent, tracker.detailPanel.body)
        equal(row:GetHeight(), height)
        tracker.detailPanel.map:Click() equal(maps[1], 2)
        tracker:RenderNearbyOffers({{id = 10, title = "Offer", level = 10, yards = 25, xp = 100,
            pickupZone = "Here", objectiveZone = "Elsewhere", objectiveYards = 300, recommended = true}}, true)
        local offer = tracker.offerRows[1]
        assert(offer.details.text:find("Elsewhere", 1, true))
        offer.detailButton:Click()
        equal(row.routeDetails:IsShown(), false)
        equal(offer.detailText.parent, tracker.detailPanel.body)
        assert(offer.detailText.text:find("300 yd", 1, true))
        tracker.detailPanel.map:Click() equal(maps[2], 10)
        equal(offer.checkbox, nil)
        equal(tracker.detailPanel.skip:IsShown(), false)
    end)
    test("Narrow navigator details reopen through the tool hub and compact view retains access", function()
        local addon, tracker, settings, _, _, render, _, _, parent = Fixture()
        parent:SetWidth(700)
        addon.UI.ToolHub.Configure({details = function() tracker:OpenDetails() end})
        function tracker:GetLeft() return 150 end
        function tracker:GetRight() return 502 end
        settings.detailMode = "compact" render()
        tracker.routeToggle:Click()
        equal(tracker.detailPanel.placement, "tools")
        equal(addon.UI.ToolHub.key, "details")
        assert(addon.UI.ToolHub.root:IsShown())
        addon.UI.ToolHub.root.close:Click() render()
        equal(tracker.detailPanel:IsShown(), false)
        tracker.routeToggle:Click()
        assert(addon.UI.ToolHub.root:IsShown()) assert(tracker.detailPanel:IsShown())
    end)
    test("Quest rows stay under the cursor without changing live ranking or keeping removed quests", function()
        local addon, tracker, _, _, _, render, b, c = Fixture()
        function tracker:IsMouseOver() return true end
        render({c, b})
        equal(tracker.acceptedRows[1].questID, b.id)
        equal(tracker.acceptedRows[2].questID, c.id)
        equal(tracker.acceptedRows[1].routeDetails.text, "Route 2")
        equal(tracker.acceptedRows[1].reward.text, "XP 2 · Zone 2")
        render({c}) equal(tracker.acceptedRows[1].questID, c.id)
        function tracker:IsMouseOver() return false end
        render({b, c}) equal(tracker.acceptedRows[1].questID, b.id)
        local order = addon.TrackerPresentation.VisualOrder({2, 3}, {c, b}, false)
        equal(order[1], 1)
    end)
    test("Skip is an explicit reversible action and opening details preserves the active quest", function()
        local _, tracker, _, _, skipped = Fixture()
        equal(tracker.acceptedRows[1].checkbox:IsShown(), false)
        tracker.acceptedRows[1].detailButton:Click() tracker.detailPanel.skip:Click()
        equal(skipped[1], 2)
        tracker.acceptedRows[2].detailButton:Click()
        equal(tracker.navigation.title.text, "[10] Active quest")
        tracker.detailPanel.skip:Click()
        equal(skipped[2], 3) equal(tracker.detailPanel:IsShown(), false)
    end)
    test("The screen arrow emphasizes the goal and reveals the quest on hover without fading text", function()
        local _, tracker, settings = Fixture()
        local nav = tracker.navigation
        nav:UpdateLayout()
        equal(nav.title:IsShown(), false)
        equal(nav.goal.text, "Defeat enemies: 2/8")
        nav.scripts.OnEnter(nav)
        equal(nav.title:IsShown(), true)
        nav.scripts.OnLeave(nav) equal(nav.title:IsShown(), false)
        settings.opacityPercent = 0 nav:UpdateOpacity()
        equal(nav.textures[1].colorAlpha, 0) equal(nav.alpha, nil)
        equal(nav.goal.alpha, nil)
        nav:SetQuestState({readyToTurnIn = true}) equal(nav.state.text, "?")
    end)
    test("Detail placement chooses the free side before falling back to tools", function()
        local addon = Fixture()
        equal(addon.TrackerPresentation.DetailPlacement(100, 500, 1000, 340), "right")
        equal(addon.TrackerPresentation.DetailPlacement(600, 950, 1000, 340), "left")
        equal(addon.TrackerPresentation.DetailPlacement(100, 500, 700, 340), "tools")
    end)
    test("Removing an inspected quest closes its details before a row can point at another quest", function()
        local _, tracker, _, _, _, render, _, c = Fixture()
        tracker.acceptedRows[1].detailButton:Click()
        render({c})
        equal(tracker.detailPanel:IsShown(), false)
        equal(tracker.acceptedRows[1].questID, c.id)
        tracker:RenderNearbyOffers({{id = 10, title = "Offer", yards = 25}}, false)
        tracker.offerRows[1].detailButton:Click()
        tracker:RenderNearbyOffers({}, false)
        equal(tracker.detailPanel:IsShown(), false)
    end)
    test("Current objectives use words and an accent instead of repeated direction symbols", function()
        local _, tracker = Fixture()
        local row = tracker.goalRows[1]
        equal(row.indicator:IsShown(), false) equal(row.indicator.text, "")
        equal(row.caption.text, "Current objective · Target unknown") assert(row.accent:IsShown())
        equal(row.label.text, "Defeat enemies") equal(row.counter.text, "2/8")
        near(row.fraction, .25) assert(row.bar:IsShown())
        equal(tracker.acceptedRows[1].stateGlyph:IsShown(), false)
        equal(tracker.navigation.state:IsShown(), false)
        equal(tracker.statusLine.text, "Automatic recommendation")
    end)
    test("Compact and collapsed views disclose additional objectives without losing the current one", function()
        local _, tracker, settings, _, _, render = Fixture()
        settings.detailMode = "compact" render()
        assert(tracker.goalRows[1]:IsShown()) equal(tracker.goalRows[2]:IsShown(), false)
        equal(tracker.moreGoals.text, "1 more objective")
        tracker.moreGoals:Click() assert(tracker.goalRows[2]:IsShown())
        tracker.moreGoals:Click() equal(tracker.goalRows[2]:IsShown(), false)
        settings.detailMode, settings.collapsed = "detailed", true render()
        assert(tracker.moreGoals:IsShown()) equal(tracker.goalRows[2]:IsShown(), false)
        equal(tracker.navigation.goal.text, "Defeat enemies: 2/8")
    end)
    test("Objective counters require usable numbers and leave unknown or narrative text intact", function()
        local addon = Fixture()
        local progress = addon.TrackerPresentation.ObjectiveProgress
        equal(progress({text = "Find the 3 missing pages"}), "Find the 3 missing pages")
        local label, counter, fraction = progress({text = "Supplies: 3/12"})
        equal(label, "Supplies") equal(counter, "3/12") near(fraction, .25)
        label, counter, fraction = progress({text = "Speak to the guard", numFulfilled = 1, numRequired = 1})
        equal(label, "Speak to the guard") equal(counter, "1/1") equal(fraction, 1)
        equal(select(2, progress({text = "Unknown", numFulfilled = 0, numRequired = 0})), nil)
        equal(select(2, progress({text = "Unknown", numFulfilled = 0/0, numRequired = 5})), nil)
    end)
    test("Priority status puts Resume beside the explanation instead of the footer", function()
        local _, tracker, _, maps, _, render = Fixture()
        render(nil, true)
        equal(tracker.statusLine.text, "Manually prioritized") assert(tracker.resumeAuto:IsShown())
        equal(tracker.resumeAuto.text, "Resume automatic")
        tracker.resumeAuto:Click() equal(maps[1], "resume")
        render() equal(tracker.resumeAuto:IsShown(), false)
    end)
    test("Completed objectives can still be opened independently in compact view", function()
        local _, tracker, settings, _, _, render = Fixture()
        settings.detailMode = "compact"
        render(nil, false, {index = 1, {index = 1, text = "Current: 2/8", selectable = true},
            {index = 2, text = "Completed: 3/3", finished = true}})
        equal(tracker.goalRows[2]:IsShown(), false)
        assert(tracker.finishedToggle:IsShown())
        tracker.finishedToggle:Click() assert(tracker.goalRows[2]:IsShown())
        tracker.finishedToggle:Click() equal(tracker.goalRows[2]:IsShown(), false)
    end)
    test("Numeric objective changes invalidate a snapshot even when its text is unchanged", function()
        local addon = Fixture()
        equal(addon.TrackerPresentation.SameTargets({{index = 1, text = "Supplies", numFulfilled = 1, numRequired = 3}},
            {{index = 1, text = "Supplies", numFulfilled = 2, numRequired = 3}}), false)
        equal(addon.TrackerPresentation.QuestStatus({readyToTurnIn = true, group = true}, true),
            "Manually prioritized · Turn in · Elite or group quest")
    end)
    test("Opened details mark their quest and clear the mark immediately when closed", function()
        local addon, tracker = Fixture()
        addon.DescribeQuest = function() return "Full reward and objective information" end
        local first, second = tracker.acceptedRows[1], tracker.acceptedRows[2]
        first.detailButton:Click()
        assert(first.detailSelection:IsShown()) equal(first.routeLabel.text, "x")
        equal(first.detailExplanation.text, "Full reward and objective information")
        second.detailButton:Click()
        equal(first.detailSelection:IsShown(), false) assert(second.detailSelection:IsShown())
        tracker.detailPanel.closeButton:Click()
        equal(second.detailSelection:IsShown(), false) equal(second.routeLabel.text, "i")
        tracker.routeToggle:Click()
        assert(tracker.questMap.detailSelection:IsShown())
        tracker.detailPanel.closeButton:Click()
        equal(tracker.questMap.detailSelection:IsShown(), false)
    end)
    test("Height limits pin the quest heading and retain scrolling across refreshes", function()
        local _, tracker, settings, _, _, render = Fixture()
        settings.trackerMaxHeight = 360
        local targets = {index = 1}
        for index = 1, 30 do targets[index] = {index = index, text = "Objective " .. index .. ": 2/8", selectable = true} end
        render(nil, false, targets)
        assert(tracker:GetHeight() <= 360) assert(tracker.viewport.maximum > 0)
        assert(tracker.questTitle.parent ~= tracker.scrollBody)
        equal(tracker.goalRows[1].parent, tracker.scrollBody)
        tracker.viewport:ScrollBy(90) equal(tracker.viewport.offset, 90)
        render(nil, false, targets) equal(tracker.viewport.offset, 90)
        tracker:RenderDistances({}) equal(tracker.viewport.offset, 90)
        tracker.viewport:ScrollBy(10000) equal(tracker.viewport.offset, tracker.viewport.maximum)
        tracker.viewport:ScrollBy(-10000) equal(tracker.viewport.offset, 0)
    end)
    test("Title menu changes presentation without changing the active quest", function()
        local _, tracker, settings, _, _, _, _, _, _, env = Fixture()
        local choices = {}
        env.MenuUtil = {CreateContextMenu = function(_, build)
            build(nil, {CreateTitle = function() end, CreateRadio = function(_, label, checked, action)
                choices[#choices + 1] = {label = label, checked = checked, action = action}
            end})
        end}
        tracker.header.scripts.OnMouseUp(tracker.header, "RightButton")
        equal(#choices, 2) choices[1].action()
        equal(settings.navigatorView, "goal") equal(tracker.acceptedRows[1]:IsShown(), false)
        equal(tracker.navigation.title.text, "[10] Active quest")
        choices[2].action() equal(settings.navigatorView, "all") assert(tracker.goalRows[2]:IsShown())
        assert(tracker.acceptedRows[1]:IsShown()) equal(settings.collapsed, false)
    end)
    test("Empty and unmapped states explain a useful action without claiming a route", function()
        local _, tracker, _, maps = Fixture()
        tracker:Render(nil, "No matching quests", {}, {}, false)
        assert(tracker.emptyMessage:IsShown()) assert(tracker.emptyMessage.text:find("No suitable quests", 1, true))
        tracker.emptyAction:Click() equal(maps[1], "finder")
        tracker:Render({id = 99, title = "Unknown target"}, "Find the objective", {}, {}, false,
            nil, nil, nil, nil, nil, nil, nil, false)
        assert(tracker.emptyMessage.text:find("No coordinates", 1, true))
        tracker.emptyAction:Click() equal(maps[2], 99)
    end)
    test("Information lines distinguish offer destinations even inside the player's current zone", function()
        local addon, tracker, _, _, _, _, _, _, _, env = Fixture()
        equal(addon.TrackerPresentation.Information("Elsewhere", "~100 XP", "Recommended"), "Elsewhere · ~100 XP · Recommended")
        equal(addon.TrackerPresentation.Information(nil, "~100 XP", nil), "~100 XP")
        env.GetRealZoneText = function() return "Here" end
        tracker:RenderNearbyOffers({{id = 10, title = "Offer", yards = 25, pickupZone = "Elsewhere", objectiveZone = "Here", xp = 100}}, true)
        equal(tracker.offerRows[1].details.text, "Target: Here · ~100 XP")
        equal(tracker.offerRows[1].distance.text, "Pickup ~25 yd")
        equal(addon.TrackerPresentation.Summary("One\nTwo\nThree\nFour", 2), "One\nTwo")
        assert(tracker.offerRows[1].fullDetails:find("Target: Here", 1, true))
    end)
    test("Appearance preview can adjust font width and opacity then restore its opening snapshot", function()
        local addon, tracker, settings, _, _, _, _, _, _, _, frames = Fixture()
        local catalog = {}
        for _, key in ipairs({"fontPercent", "trackerWidth", "opacityPercent"}) do
            local field = key
            catalog[#catalog + 1] = {key = field, control = {SetValue = function(_, value)
                settings[field] = value
                if field == "trackerWidth" then tracker:SetWidth(value) tracker:UpdateListSettings()
                elseif field == "fontPercent" then tracker:UpdateFontSize()
                else tracker:UpdateOpacity() end
            end}}
        end
        settings.questieOfferRadius = 450
        addon.ShowAppearancePreview(settings, catalog)
        local preview
        for _, frame in ipairs(frames) do if frame.sampleBackdrop then preview = frame end end
        assert(preview)
        preview.controls[1].plus:Click() equal(settings.fontPercent, 110)
        preview.controls[2].plus:Click() equal(settings.trackerWidth, 362)
        preview.controls[3].minus:Click() equal(settings.opacityPercent, 75)
        preview.restore:Click()
        equal(settings.fontPercent, 100) equal(settings.trackerWidth, 352) equal(settings.opacityPercent, 80)
        equal(settings.questieOfferRadius, 450)
        preview.controls[1].plus:Click() preview.keep:Click()
        addon.ShowAppearancePreview(settings, catalog)
        preview.controls[1].plus:Click() preview.restore:Click() equal(settings.fontPercent, 110)
    end)
    test("Scrolling never replaces rows at the boundary; Show more appends entries", function()
        local _, tracker, settings, _, _, render, b, c = Fixture()
        settings.trackerMaxHeight = 360
        local targets = {index = 1}
        for index = 1, 30 do targets[index] = {index = index, text = "Objective " .. index .. ": 0/8"} end
        render({b, c, {id = 4, title = "Fourth"}}, false, targets)
        tracker.viewport:ScrollBy(10000)
        local row = tracker.acceptedRows[1]
        row.scripts.OnMouseWheel(row, -1)
        equal(row.questID, b.id)
        tracker.moreEntries.accepted:Click()
        equal(row.questID, b.id) equal(tracker.acceptedRows[3].questID, 4)
    end)
    test("Viewport limits are finite and fit a smaller screen without changing preferences", function()
        local addon = Fixture()
        equal(addon.TrackerPresentation.HeightLimit(0/0), 600)
        equal(addon.TrackerPresentation.HeightLimit(-100), 360)
        local height, visible, maximum = addon.TrackerPresentation.ViewportHeight(100, 800, 12, 600, 400)
        equal(height, 360) equal(visible, 248) equal(maximum, 552)
    end)
    test("Quest items update counts and cooldowns but never mutate their protected action in combat", function()
        local _, tracker, _, _, _, render, _, _, _, env = Fixture()
        local combat, count, item, assignments = false, 2, 123, 0
        env.InCombatLockdown = function() return combat end
        env.GetTime = function() return 100 end
        env.C_QuestLog = {GetLogIndexForQuestID = function() return 3 end, IsComplete = function() return false end}
        env.GetQuestLogSpecialItemInfo = function() return "|Hitem:" .. item .. "|h[Signal]|h", 1234, nil, false end
        env.GetItemCount = function() return count end
        env.IsQuestLogSpecialItemInRange = function() return 1 end
        env.GetQuestLogSpecialItemCooldown = function() return 95, 10 end
        env.UseItemByName = function() error("An item was used without a player click") end
        env.RegisterStateDriver = function(button, state, condition)
            assert(not combat) equal(state, "visibility") button.driver = condition
        end
        render()
        local controller = tracker.questItem
        local button = controller.button
        assert(button) equal(button.template, "SecureActionButtonTemplate")
        equal(button.attributes.type, "item") equal(button.attributes.item, "item:123")
        equal(button.attributes.useOnKeyDown, false)
        equal(controller.host.count.text, "2") equal(controller.host.cooldown.cooldownDuration, 10)
        assert(controller.host.label.text:find("5s", 1, true))
        local write = button.SetAttribute
        button.SetAttribute = function(self, key, value) assert(not combat) assignments = assignments + 1 write(self, key, value) end
        local shown, point = button.SetShown, button.SetPoint
        button.SetShown = function(self, value) assert(not combat) shown(self, value) end
        button.SetPoint = function(self, ...) assert(not combat) point(self, ...) end
        combat, item = true, 456
        controller:Refresh()
        equal(assignments, 0) equal(button.attributes.item, "item:123")
        assert(controller.host.label.text:find("after combat", 1, true))
        combat = false controller.scripts.OnEvent(controller, "PLAYER_REGEN_ENABLED")
        equal(button.attributes.item, "item:456") assert(assignments > 0)
        count = 0 controller:Refresh()
        equal(controller.hint, nil) equal(button.attributes.item, nil) equal(button:IsShown(), false)
    end)
    test("Quest item polling stops while hidden and folds cooldown bursts into one refresh", function()
        local _, tracker, _, _, _, render, _, _, _, env = Fixture()
        env.InCombatLockdown = function() return false end
        env.C_QuestLog = {GetLogIndexForQuestID = function() return 3 end, IsComplete = function() return false end}
        env.GetQuestLogSpecialItemInfo = function() return "|Hitem:123|h[Signal]|h", 1234, nil, false end
        env.GetItemCount = function() return 1 end
        env.IsQuestLogSpecialItemInRange = function() return 1 end
        env.GetQuestLogSpecialItemCooldown = function() return 0, 0 end
        env.RegisterStateDriver = function() end
        render()
        local controller = tracker.questItem
        assert(controller.hint) equal(controller:IsShown(), true)
        local refreshes, refresh = 0, controller.Refresh
        controller.Refresh = function(self) refreshes = refreshes + 1 return refresh(self) end
        for _ = 1, 20 do controller.scripts.OnEvent(controller, "SPELL_UPDATE_COOLDOWN") end
        equal(refreshes, 0)
        controller.scripts.OnUpdate(controller, .05) equal(refreshes, 1)
        tracker:Hide()
        equal(controller:IsShown(), false)
        refreshes = 0
        for _ = 1, 5 do controller.scripts.OnEvent(controller, "SPELL_UPDATE_COOLDOWN") end
        equal(refreshes, 0)
        controller.scripts.OnEvent(controller, "PLAYER_REGEN_ENABLED") equal(refreshes, 1)
        tracker:Show()
        equal(controller:IsShown(), true)
    end)
    test("Arrival instructions require evidence for item use and preserve entrance and turn-in actions", function()
        local addon = Fixture()
        local hints = addon.NavigationHints
        equal(hints.NextAction({}, {targetKind = "area"}, {name = "Signal"}), addon.L.ArrivalArea)
        equal(hints.NextAction({}, {targetKind = "area"}, {name = "Signal", inRange = true}), "Use quest item: Signal")
        equal(hints.NextAction({}, {accessPoint = true}, {name = "Signal", inRange = true}), addon.L.ArrivalAccess)
        equal(hints.NextAction({readyToTurnIn = true}, {}, {name = "Signal", inRange = true}), addon.L.ArrivalTurnIn)
        equal(hints.Short(nil), "Target unknown") equal(hints.Short({targetKind = "area"}), "Quest area")
        equal(hints.Short({turnInName = "NPC"}), "Quest giver")
        equal(select(3, addon.QuestItemHints.Cooldown({logIndex = 1}, function() return 0/0, 5 end, 10)), 0)
    end)
    test("Layout editing snaps positions, cancels without changing locks and locks both windows on Done", function()
        local _, tracker, settings = Fixture()
        settings.x, settings.y, settings.screenArrowX, settings.screenArrowY = 90, 150, -70, 200
        settings.lockTrackerPosition, settings.lockNavigationPosition = true, true
        local editor = tracker.layoutEditor
        tracker:ArrangeUI() assert(editor:IsShown()) assert(tracker.arranging)
        local moving = tracker.startedMoving or 0
        tracker.header.scripts.OnDragStart(tracker.header) equal(tracker.startedMoving, moving + 1)
        tracker.header.scripts.OnDragStop(tracker.header) equal(settings.x, 0)
        editor.cancel:Click()
        equal(settings.x, 90) equal(settings.y, 150) equal(settings.screenArrowX, -70)
        equal(settings.lockTrackerPosition, true) equal(tracker.arranging, nil)
        tracker:ArrangeUI() settings.x = 10 editor:Hide() equal(settings.x, 90)
        settings.lockTrackerPosition, settings.lockNavigationPosition = false, false
        tracker:ArrangeUI() editor.done:Click()
        equal(settings.lockTrackerPosition, true) equal(settings.lockNavigationPosition, true)
    end)
    test("Layout snapping respects center lines and a sixteen pixel edge margin", function()
        local addon = Fixture()
        local x, y = addon.LayoutGeometry.Snap(7, -8, 300, 200, 1000, 800)
        equal(x, 0) equal(y, 0)
        x, y = addon.LayoutGeometry.Snap(330, 280, 300, 200, 1000, 800)
        equal(x, 334) equal(y, 284)
        x, y = addon.LayoutGeometry.Snap(10000, -10000, 300, 200, 1000, 800)
        equal(x, 334) equal(y, -284)
    end)
    test("Expanded header hit areas remain separated from adjacent actions", function()
        local _, tracker, _, _, _, _, _, _, _, _, frames = Fixture()
        local positions = {}
        for _, frame in ipairs(frames) do
            if frame.parent == tracker and frame.hitInsets and frame.point and frame.point[1] == "TOPRIGHT" then
                positions[#positions + 1] = frame.point[2]
                equal(frame.hitInsets[1], -4)
            end
        end
        table.sort(positions)
        equal(#positions, 3)
        assert(positions[2] - positions[1] >= 28) assert(positions[3] - positions[2] >= 28)
    end)
    test("Navigator stress matrix retains bounds and full details for long texts and many objectives", function()
        for _, locale in ipairs({"enUS", "deDE"}) do
            for _, size in ipairs({80, 140}) do
                for _, width in ipairs({330, 640}) do
                    for _, limit in ipairs({360, 600}) do
                        local addon, tracker, settings, _, _, _, _, _, _, env = Fixture(locale)
                        settings.fontPercent, settings.trackerMaxHeight = size, limit
                        tracker:SetWidth(width) tracker:UpdateFontSize()
                        tracker:SetNavigatorView("quest")
                        local title = "Ein außergewöhnlich langer Questtitel für die Prüfung der Navigatoranzeige"
                        local targets = {index = 1}
                        for index = 1, 24 do targets[index] = {index = index, text = "Eine lange Zielbeschreibung\nmit zusätzlichem Fortschritt: 2/12", selectable = true} end
                        tracker:Render({id = 1, title = title, level = 34}, "", {}, {}, false, nil,
                            "Full route details", nil, nil, nil, nil, targets, true)
                        tracker.moreGoals:Click()
                        assert(tracker:GetHeight() <= limit) assert(tracker.viewport.maximum > 0)
                        assert(tracker.scrollBody:GetWidth() <= width)
                        equal(tracker.questTitle.text, "[34] " .. title)
                        local height = tracker:GetHeight()
                        tracker:OpenDetails() equal(tracker:GetHeight(), height)
                        tracker.detailPanel.closeButton:Click()
                        tracker:SetNavigatorView("goal") assert(tracker.goalRows[1]:IsShown())
                        tracker:SetNavigatorView("all") equal(tracker.navigation.title.text, "[34] " .. title)
                    end
                end
            end
        end
    end)
    test("Section headings and quest rows share the scroll coordinate space and clipping", function()
        local _, tracker = Fixture("deDE")
        tracker:RenderNearbyOffers({{id = 10, title = "Vorschlag", yards = 25}}, false)
        for index, header in ipairs(tracker.sectionHeaders) do
            assert(header.toggle.parent == tracker.scrollBody, "A section heading is outside the scroll body")
            assert(header.label.parent == header.toggle, "A heading label must move with its clickable header")
            local row = index == 1 and tracker.acceptedRows[1] or tracker.offerRows[1]
            equal(row.parent, tracker.scrollBody)
            local bottom = -header.toggle.point[3] + header.toggle:GetHeight()
            assert(-row.point[3] >= bottom + 4, "Quest content overlaps a heading")
        end
    end)
    test("Wrapped section headings reserve their measured height before the next row", function()
        local _, tracker = Fixture("deDE")
        local header = tracker.sectionHeaders[1]
        header.label.GetStringHeight = function() return 40 end
        tracker:UpdateNavigatorLayout()
        assert(header.toggle:GetHeight() >= 44, "Wrapped heading is taller than its clickable area")
        local bottom = -header.toggle.point[3] + header.toggle:GetHeight()
        assert(-tracker.acceptedRows[1].point[3] >= bottom + 4)
    end)
    test("Show more preserves the visible prefix and map identity across both lists", function()
        local _, tracker, _, maps, _, render = Fixture()
        local quests = {}
        for index = 1, 8 do quests[index] = {id = 100 + index, title = "Quest " .. index} end
        render(quests)
        local first = tracker.acceptedRows[1].questID
        tracker.moreEntries.accepted:Click()
        equal(tracker.acceptedRows[1].questID, first)
        equal(tracker.acceptedRows[4].questID, 104)
        tracker.acceptedRows[4]:Click() equal(maps[1], 104)
        local offers = {}
        for index = 1, 7 do offers[index] = {id = 200 + index, title = "Offer " .. index, yards = 25} end
        tracker:RenderNearbyOffers(offers, false)
        tracker.moreEntries.offers:Click() equal(tracker.offerRows[1].measurement.id, 201)
        tracker.moreEntries.offers:Click() equal(tracker.moreEntries.offers:IsShown(), false)
        equal(tracker.offerRows[7].measurement.id, 207)
    end)
    test("Transient notices occupy a fixed footer without shifting quest rows or window height", function()
        local _, tracker = Fixture()
        local height, maximum = tracker:GetHeight(), tracker.viewport.maximum
        local top = tracker.acceptedRows[1].point[3]
        tracker.statusMessage = "Arrival: a longer instruction\nwith another line"
        tracker:RefreshNotice() tracker:UpdateNavigatorLayout()
        equal(tracker:GetHeight(), height) equal(tracker.acceptedRows[1].point[3], top)
        equal(tracker.viewport.maximum, maximum)
        equal(tracker.noticeLabel.parent, tracker.noticeSlot)
        tracker.statusMessage, tracker.noticeMessage, tracker.noticeRemaining = "", "Recommendation changed", 4
        tracker:RefreshNotice() tracker.scripts.OnUpdate(tracker, 5)
        equal(tracker.noticeLabel:IsShown(), false) equal(tracker:GetHeight(), height)
        equal(tracker.acceptedRows[1].point[3], top)
    end)
    test("Target quality is part of the objective caption instead of a second navigator label", function()
        local _, tracker = Fixture()
        tracker:RenderDistances({[1] = {yards = 50, marker = {targetKind = "area"}}})
        tracker:RenderDirection(0, 1)
        equal(tracker.goalRows[1].caption.text, "Current objective · Quest area")
        equal(tracker.noticeLabel.text, "")
        equal(tracker.navigation.progress, 0)
        tracker:RenderDistances({[1] = {yards = 25, marker = {targetKind = "area"}}})
        tracker:RenderDirection(0, 1)
        near(tracker.navigation.progress, .5)
        tracker:RenderDirection(0, 1, nil, true)
        equal(tracker.navigation.progress, nil)
    end)
    test("Turn-in badges leave separate space for XP and keep the correct clipping parent", function()
        local _, tracker, _, _, _, render, b, c = Fixture()
        b.readyToTurnIn = true render({b, c})
        local row = tracker.acceptedRows[1]
        assert(row.actionBadge:IsShown()) equal(row.actionBadge.text, "Turn in")
        assert(not row.reward.text:find("Turn in", 1, true))
        equal(row.actionBadge.parent, row) equal(row.badgeBackground.parent, row)
        local badge = row.actionBadge.points.TOPLEFT
        local reward = row.reward.points.TOPLEFT
        assert(reward[2] >= badge[2] + row.actionBadge:GetStringWidth() + 6)
        equal(reward[3], badge[3])
        assert(-reward[3] + row.reward:GetStringHeight() <= row:GetHeight())
    end)
    test("XP summaries keep numeric rewards and level forecasts while rejecting unknown values", function()
        local addon = Fixture()
        equal(addon.TrackerPresentation.XPLine(2800, 4000, 36), "~2800 XP · ~1200 to level 37")
        equal(addon.TrackerPresentation.XPLine(2800, 2000, 36), "~2800 XP · level 37 possible")
        equal(addon.TrackerPresentation.XPLine(nil, 2000, 36), nil)
        equal(addon.TrackerPresentation.XPLine(0/0, 2000, 36), nil)
        equal(addon.TrackerPresentation.XPLine(2800, nil, 36), "~2800 XP")
    end)
    test("Empty area summaries are hidden and useful area data can restore the overview", function()
        local _, tracker = Fixture()
        local area = tracker.areaOverview
        area:SetData({objectives = 0, turnIns = 0, entries = {}, groups = {}})
        tracker:UpdateNavigatorLayout() equal(area:IsShown(), false)
        area:SetData({objectives = 1, turnIns = 0, entries = {}, groups = {}})
        tracker:UpdateNavigatorLayout() assert(area:IsShown())
        area:SetData({objectives = 0, turnIns = 0, entries = {}, groups = {}})
        tracker:UpdateNavigatorLayout() equal(area:IsShown(), false)
    end)
    test("Quest progress fills the reserved footer and notices replace it without changing geometry", function()
        local _, tracker = Fixture()
        tracker:SetProgress({open = 12, turnIns = 7, unknown = 0})
        equal(tracker.progressLine.parent, tracker.noticeSlot) assert(tracker.progressLine:IsShown())
        local height, top = tracker:GetHeight(), tracker.acceptedRows[1].point[3]
        tracker.statusMessage = "Arrival instruction" tracker:RefreshNotice()
        equal(tracker.progressLine:IsShown(), false) assert(tracker.noticeLabel:IsShown())
        tracker.statusMessage = "" tracker:RefreshNotice()
        assert(tracker.progressLine:IsShown()) equal(tracker.noticeLabel:IsShown(), false)
        equal(tracker:GetHeight(), height) equal(tracker.acceptedRows[1].point[3], top)
    end)
    test("The information line uses full width and actions reserve a separate row below it", function()
        local _, tracker = Fixture("deDE")
        local info = tracker.activeInfoLabel
        info.GetStringHeight = function() return 24 end
        tracker:UpdateNavigatorLayout()
        equal(info.points.TOPRIGHT[2], -14)
        local bottom = -info.points.TOPLEFT[3] + info:GetStringHeight()
        assert(-tracker.routeMap.point[3] >= bottom + 4, "Quest actions overlap the information text")
    end)
    test("Pickup planning stays in the scroll body, opens the right view and respects collapsed navigation", function()
        local addon, tracker, settings = Fixture("deDE")
        local opened = 0
        tracker.openPickupPlanning = function() opened = opened + 1 end
        tracker:SetPickupPlanning({areas = {{}}, pickups = {{id = 2}}, outing = {}})
        tracker:SetDecisionBrief({steps = {}, closing = {}, area = {zone = "Camp", entries = {{quest = {id = 2}}}}})
        local button = tracker.nextBoard.plan
        equal(tracker.nextBoard.parent, tracker.scrollBody) assert(tracker.nextBoard:IsShown())
        button:Click() equal(opened, 1)
        tracker:SetNavigatorView("goal") equal(tracker.nextBoard:IsShown(), false)
        settings.collapsed = false tracker:SetPickupPlanning({areas = {}, pickups = {}, outing = {}})
        tracker:SetNavigatorView("all") assert(tracker.nextBoard:IsShown())
        equal(tracker.departureButton, nil)
    end)
    test("Planning areas expand to quest actions and return without changing the active quest", function()
        local addon = Fixture()
        local quest = {id = 2, title = "Pickup", level = 10, yards = 50, pickupZone = "Town", objectiveZone = "Camp",
            marker = {mapID = 1, x = .1, y = .2}, objectiveYards = 500}
        local area = {target = {mapID = 1, x = .4, y = .2}, entries = {{quest = quest, pickup = true, target = {mapID = 1, x = .4, y = .2}}},
            zone = "Camp", active = 0, pickups = 1, xp = 100, unknownXP = 0, followUps = {}}
        local stops = {}
        local window = addon.ShowPlanningOverview(function() return {pickupPlanning = {areas = {area}, outing = {}, budget = 1}} end,
            function(stop) stops[#stops + 1] = stop end, "test")
        window:SelectMode("areas")
        window.rows[1]:Click() equal(window.areaKey, 2)
        window.rows[2]:Click() equal(stops[1].action, "accept") equal(stops[1].target, quest.marker)
        window.rows[1]:Click() equal(window.areaKey, nil)
        window:SelectMode("outing") equal(window.page, 1)
    end)
    test("Guided navigation discloses full lists without changing map clicks or quest priority", function()
        local addon, tracker, settings, maps, skipped, render, b = Fixture("deDE")
        settings.navigatorLayout = "guided"
        tracker.environmentExpanded = false
        tracker:SetDecisionBrief({steps = {{quest = b, kind = "objective", action = "objective", yards = 100,
            target = {mapID = 1, x = .2, y = .3}}}, closing = {}, phaseText = addon.L.BriefPhase_travel, playerLevel = 10})
        assert(tracker.nextBoard:IsShown()) equal(tracker.acceptedRows[1]:IsShown(), false)
        tracker.nextBoard.rows[1].map:Click() equal(maps[1], b.id) equal(#skipped, 0)
        tracker.nextBoard.environment:Click() assert(tracker.acceptedRows[1]:IsShown())
        tracker.nextBoard.environment:Click() equal(tracker.acceptedRows[1]:IsShown(), false)
        tracker:SetNavigatorView("goal") equal(tracker.nextBoard:IsShown(), false)
        tracker:SetNavigatorView("all") assert(tracker.nextBoard:IsShown())
        equal(tracker.acceptedRows[1]:IsShown(), false)
    end)
    test("Guided board respects collapse, focus, flight and combat without changing presentation preferences", function()
        local _, tracker, settings = Fixture()
        settings.navigatorLayout = "guided"
        tracker:SetDecisionBrief({steps = {}, closing = {}})
        assert(tracker.nextBoard:IsShown())
        settings.collapsed = true tracker:UpdateNavigatorLayout() equal(tracker.nextBoard:IsShown(), false)
        settings.collapsed = false tracker:SetFlightView(true, "Flying") equal(tracker.nextBoard:IsShown(), false)
        tracker:SetFlightView(false) assert(tracker.nextBoard:IsShown())
        tracker:SetCombatView(true) equal(tracker.nextBoard:IsShown(), false)
        tracker:SetCombatView(false) assert(tracker.nextBoard:IsShown())
        tracker:SetNavigatorView("goal") equal(tracker.nextBoard:IsShown(), false)
        equal(settings.navigatorLayout, "guided")
    end)
    test("Guided board stress matrix reserves distance and action space with long text", function()
        for _, locale in ipairs({"enUS", "deDE"}) do
            for _, width in ipairs({330, 440, 640}) do
                for _, size in ipairs({80, 140}) do
                    local addon, tracker, settings, _, _, _, b = Fixture(locale)
                    settings.navigatorLayout, settings.fontPercent = "guided", size
                    tracker:SetWidth(width) tracker:UpdateFontSize()
                    b.title = string.rep("Long quest title with words ", 8)
                    tracker:SetDecisionBrief({steps = {{quest = b, kind = "objective", yards = 12345, detail = string.rep("Reason ", 15)}}, closing = {}, playerLevel = 10})
                    local board, row = tracker.nextBoard, tracker.nextBoard.rows[1]
                    row.label.GetStringHeight = function() return 44 end
                    board.plan.textLabel.GetStringHeight = function() return 40 end
                    tracker:UpdateNavigatorLayout()
                    local scale = size / 100
                    assert(row:GetHeight() >= 44 + addon.UI.ButtonHeight(scale) + 6)
                    if board.plan:IsShown() then near(board.plan:GetHeight(), math.max(18, 18 * scale)) end
                    local menuWidth = row.menu:IsShown() and 26 * scale + 4 or 0
                    assert(-row.detail.points.TOPRIGHT[2] >= 48 * scale + menuWidth + row.distance:GetStringWidth() + 16)
                    equal(row.parent, board) equal(board.parent, tracker.scrollBody)
                    assert(tracker:GetHeight() <= (settings.trackerMaxHeight or 600))
                end
            end
        end
    end)
    test("Guided phase updates keep explicit priority and leave the next-step board unchanged", function()
        local addon, tracker, settings, _, _, render = Fixture()
        settings.navigatorLayout = "guided" render(nil, true)
        tracker:SetDecisionBrief({steps = {}, closing = {}, phase = "travel", phaseText = addon.L.BriefPhase_travel})
        tracker:SetJourneyPhase("work")
        assert(tracker.statusLine:GetText():find(addon.L.BriefPhase_work, 1, true))
        assert(tracker.resumeAuto:IsShown())
        tracker:SetJourneyPhase("flight")
        equal(tracker.decisionBrief.phase, "flight")
    end)
    test("Decision views use independent expansion and keep closing hand-in map identities", function()
        local addon = Fixture()
        local quest = {id = 2, title = "Ready", level = 10, readyToTurnIn = true}
        local target = {mapID = 8, x = .4, y = .2}
        local stop = {quest = quest, target = target, xp = 100, action = "turnIn"}
        local model = {measurements = {[2] = {yards = 100, marker = target}}, turnInTour = {stops = {stop}}}
        model.brief = addon.DecisionBrief.Build(model)
        local opened = {}
        local window = addon.ShowPlanningOverview(function() return model end, function(value) opened[#opened + 1] = value end, "test")
        window:SelectMode("handIns") window.rows[1]:Click() equal(window.handInMap, 8)
        window.rows[2]:Click() equal(opened[1].target, target)
        window.rows[1]:Click() equal(window.handInMap, nil)
        window:SelectMode("closing") window.rows[1]:Click() equal(opened[2].quest.id, 2)
        window:SelectMode("progress") equal(window.rows[1]:IsShown(), false)
    end)
    test("Quest details keep rewards in their own section and reopen without a priority change", function()
        local addon, tracker, settings, maps = Fixture()
        settings.navigatorLayout = "guided"
        local quest = {id = 1, title = "Main quest", level = 10}
        local snapshot = {playerLevel = 10, view = {quest = quest, objectives = "Collect supplies", alternatives = {},
            hasMap = true, reason = "Distance and level fit", routeDetails = "Walk to the camp", rewardDetails = "Quest sword", rewards = {"~100 XP"}}}
        snapshot.brief = addon.DecisionBrief.Build(snapshot)
        tracker:RenderSnapshot(snapshot, {}) tracker:OpenDetails()
        assert(tracker.rewardDetails:IsShown()) equal(tracker.rewardDetails:GetText(), "Quest sword")
        equal(tracker.rewardDetails.sectionTitle, addon.L.DetailReward)
        assert(not tracker.detailExplanation:GetText():find("Quest sword", 1, true))
        tracker.detailPanel:Hide() tracker:OpenDetails()
        assert(tracker.rewardDetails:IsShown()) tracker.detailPanel.map:Click()
        equal(maps[1], 1) equal(#maps, 1)
    end)
    test("Settings are opaque on first open even with an invisible navigator, before any palette switch", function()
        local addon, tracker, settings = Fixture()
        settings.opacityPercent = 0 tracker:UpdateOpacity()
        equal(tracker.backdropAlpha, 0)
        local panel
        addon.UI.ToolHub.Configure({settings = function()
            panel = addon.ShowQuickSettings({}, settings, function() end)
        end})
        local hub = addon.UI.ToolHub
        hub.Open("settings")
        assert(panel:IsShown()) equal(hub.root.backdropAlpha, 1)
        equal(panel.backdropAlpha, 0) -- Embedded pages use the opaque parent.
        addon.UI.Theme.Apply(false, "midnight", false)
        equal(hub.root.backdropAlpha, 1) equal(panel.backdropAlpha, 0)
        hub.root:Hide() settings.opacityPercent = 35 tracker:UpdateOpacity()
        hub.Open("settings") equal(hub.root.backdropAlpha, 1)
        near(tracker.backdropAlpha, .35)
    end)
    test("Collapse button and settings use the same two views while extra focused objectives remain accessible", function()
        local addon, tracker, settings, maps = Fixture()
        local calls = 0
        local control = {}
        function control:GetValue() return settings.navigatorView or "all" end
        function control:SetValue(value)
            calls = calls + 1 settings.navigatorView = value tracker:SetNavigatorView(value)
        end
        addon.SettingsController.settings = settings
        addon.SettingsController.catalog = {{key = "navigatorView", control = control}}
        tracker.collapseButton:Click()
        equal(settings.navigatorView, "goal") equal(settings.collapsed, true) equal(calls, 1)
        equal(tracker.goalRows[2]:IsShown(), false)
        tracker.moreGoals:Click() assert(tracker.goalRows[2]:IsShown())
        tracker.collapseButton:Click()
        equal(settings.navigatorView, "all") equal(settings.collapsed, false) equal(calls, 2)
        equal(#maps, 0)
    end)
    test("A separate demo tracker cannot change the live navigator view setting", function()
        local addon, tracker, settings = Fixture()
        local live = {navigatorView = "all"}
        addon.SettingsController.settings = live
        addon.SettingsController.catalog = {{key = "navigatorView", control = {
            GetValue = function() return live.navigatorView end,
            SetValue = function() error("Live settings must not be changed") end}}}
        tracker:SetNavigatorView("quest")
        equal(settings.navigatorView, "goal") equal(live.navigatorView, "all")
    end)
    test("The map legend clear action invokes FQN's marker removal callback", function()
        local addon, _, _, _, _, _, _, _, map = Fixture()
        local removed = 0
        addon.ClearFQNMapMarkers = function() removed = removed + 1 addon.UpdateMapLegend(map, nil) end
        addon.UpdateMapLegend(map, {mapID = 1, x = .2, y = .3})
        assert(map.FQNLegend:IsShown()) map.FQNLegend.clear:Click()
        equal(removed, 1) equal(map.FQNLegend:IsShown(), false)
    end)
    test("Personal note editing saves only on an explicit save or clear action", function()
        local addon = Fixture()
        local saved = {}
        local editor = addon.ShowQuestNoteEditor(1, "Quest", "North entrance", function(text) saved[#saved + 1] = text end)
        equal(#saved, 0) equal(editor.edit:GetText(), "North entrance")
        editor.edit:SetText("Use the northern entrance") editor.save:Click()
        equal(saved[1], "Use the northern entrance") equal(editor:IsShown(), false)
        addon.ShowQuestNoteEditor(1, "Quest", saved[1], function(text) saved[#saved + 1] = text end)
        editor.clear:Click() equal(saved[2], "")
    end)
    test("Camp map inspection and explicit selection are distinct actions", function()
        local addon = Fixture()
        local choice = {quest = {id = 1}, target = {mapID = 1, x = .2, y = .3}, yards = 100, shared = 2}
        local mapped, selected = 0, 0
        local window = addon.ShowCampChoices(function() return {choice} end,
            function(value) equal(value, choice) mapped = mapped + 1 end,
            function(value) equal(value, choice) selected = selected + 1 end)
        window.rows[1].map:Click() equal(mapped, 1) equal(selected, 0)
        window.rows[1].select:Click() equal(selected, 1)
    end)
    test("Outing review does not start navigation through map inspection", function()
        local addon = Fixture()
        local plan = addon.ExcursionPlan.Build({entries = {{quest = {id = 1, title = "Quest"}, target = {mapID = 1, x = .2, y = .3}}}})
        local mapped, started = 0, 0
        local window = addon.ShowExcursion(plan, {map = function() mapped = mapped + 1 end,
            start = function() started = started + 1 return true end, pause = function() end})
        equal(started, 0) window.rows[1]:Click() equal(mapped, 1) equal(started, 0)
        window.start:Click() equal(started, 1)
    end)
    test("Tour previews and recaps stay explicit and empty actions disappear across fonts and languages", function()
        for _, language in ipairs({"enUS", "deDE"}) do
            for _, font in ipairs({80, 140}) do
                local addon, tracker, settings, maps, skipped, render, quest = Fixture(language)
                settings.fontPercent = font settings.navigatorLayout = "guided"
                local area = {zone = "Camp", active = 1, pickups = 2, xp = 100, unknownXP = 1, entries = {{quest = quest}}}
                local preview, recap
                addon.OpenExcursionFromArea = function(key) preview = key end
                addon.OpenOutingReview = function() recap = true end
                tracker:SetDecisionBrief({steps = {{quest = quest, kind = "objective"}, {quest = quest, kind = "objective"}},
                    closing = {}, area = area, review = {completed = 1}, phaseText = addon.L.BriefPhase_travel})
                local board = tracker.nextBoard
                equal(board.rows[2]:IsShown(), false) equal(board.closing:IsShown(), false)
                board.tour:Click() equal(preview, quest.id) equal(#skipped, 0)
                board.review:Click() equal(recap, true)
                assert(board.tourInfo:IsShown()) assert(board.tourInfo:GetText():find("Camp", 1, true))
                assert(board.tourInfo:GetText():find(addon.L.TourCardPickupMany:format(2), 1, true))
                tracker:SetDecisionBrief({steps = {}, closing = {}})
                equal(board.tour:IsShown(), false) equal(board.plan:IsShown(), false)
                equal(board.caption:IsShown(), false) equal(board.review:IsShown(), false)
            end
        end
    end)
    test("A completed outing recap is dismissible and shows received rather than potential XP", function()
        local addon = Fixture()
        local dismissed
        local p = {stops = {}, index = 1, started = true, running = false, xp = 9999, unknownXP = 0, missing = 0,
            receipts = {[1] = {xp = 250}}}
        local window = addon.ShowExcursion(p, {dismiss = function() dismissed = true end})
        equal(window.summary:GetText(), addon.L.RoundSummary:format(1, 250, 0))
        window.dismiss:Click() equal(dismissed, true) equal(window:IsShown(), false)
    end)
    test("Adventure tabs preserve pages and require explicit selection, while maps only open destinations", function()
        for _, locale in ipairs({"enUS", "deDE"}) do
            local addon = Fixture(locale)
            local chosen, mapped, toggled, reviewed = 0, 0, 0, 0
            local rows = {}
            for i = 1, 6 do rows[i] = {quest = {id = i, title = "Quest " .. i}, target = {mapID = 1, x = .2, y = .2}, detail = "Known details"} end
            local actions = {map = function() mapped = mapped + 1 end, select = function() chosen = chosen + 1 end,
                toggleGroup = function() toggled = toggled + 1 end, releaseLevel = function() end,
                reviewChanges = function() reviewed = reviewed + 1 end, clearCorrection = function() end}
            local window = addon.ShowAdventure(function() return {rows = rows, summary = "Help"} end, actions, "departure")
            equal(chosen, 0) window.rows[1].map:Click() equal(mapped, 1) equal(chosen, 0)
            window.next:Click() equal(window.page, 2)
            window:SelectMode("blocked") equal(window.page, 1) window.rows[1].choose:Click() equal(chosen, 1)
            window:SelectMode("departure") equal(window.page, 2)
            window:SelectMode("group") window.primary:Click() equal(toggled, 1)
            window:SelectMode("changes") window.primary:Click() equal(reviewed, 1) equal(chosen, 1)
            window.closeButton:Click() equal(window:IsShown(), false)
            local again = addon.ShowAdventure(function() return {rows = rows} end, actions)
            equal(again, window) equal(window.mode, "changes")
        end
    end)
    test("Time budgeting only rebuilds an explicit preview and is hidden on a started outing", function()
        local addon = Fixture()
        local budget, starts = 0, 0
        local p = {stops = {}, index = 1, running = false, xp = 0, missing = 0, unknownXP = 0}
        local actions = {budget = function(value) budget = value end, start = function() starts = starts + 1 end}
        local window = addon.ShowExcursion(p, actions)
        window.budget:Click() equal(budget, 15) equal(starts, 0)
        p.started = true window:Refresh() equal(window.budget:IsShown(), false) equal(window.timeHelp:IsShown(), false)
    end)
    test("Difficulty words use compact text and survive color reduction", function()
        local addon = Fixture("deDE")
        addon.SettingsController.settings = {difficultyWords = true}
        local title = addon.UI.FormatQuestTitle({id = 1, title = "Test", level = 30}, true, 30)
        assert(title:find(addon.L.DifficultyShort_yellow, 1, true))
        assert(not title:find(addon.L.Difficulty_yellow, 1, true))
        addon.SettingsController.settings.difficultyWords = false
        assert(not addon.UI.FormatQuestTitle({id = 1, title = "Test", level = 30}, true, 30):find(addon.L.DifficultyShort_yellow, 1, true))
    end)
    test("Simple navigator reduces cards and lists while contextual warnings remain actionable", function()
        local addon, tracker, settings, maps, skipped, render, quest = Fixture("deDE")
        settings.simpleNavigator = true settings.navigatorLayout = "guided"
        local section
        addon.OpenAdventure = function(mode) section = mode or "tools" end
        tracker:SetDecisionBrief({steps = {{quest = quest, kind = "objective"}}, closing = {},
            area = {zone = "Camp", entries = {{quest = quest}}}, bagsWarning = "Low bags", laterCount = 2})
        equal(tracker.nextBoard.tour:IsShown(), false) equal(tracker.nextBoard.plan:IsShown(), false)
        equal(tracker.acceptedRows[1]:IsShown(), false)
        assert(tracker.nextBoard.assist:IsShown()) tracker.nextBoard.assist:Click() equal(section, "bags")
        tracker.nextBoard.environment:Click() equal(section, "tools") equal(#skipped, 0)
        settings.simpleNavigator = false tracker:UpdateNavigatorLayout() assert(tracker.nextBoard.tour:IsShown())
    end)
    test("Grouped adventure navigation separates descriptions from rows across fonts and themes", function()
        for _, locale in ipairs({"enUS", "deDE"}) do for _, font in ipairs({80, 140}) do
            local addon = Fixture(locale) addon.UI.SetFontSize(font)
            local entries = {}
            for i = 1, 6 do entries[i] = {quest = {id = i, title = "A longer quest title"}, target = {mapID = 1, x = .2, y = .3}, short = "Known destination"} end
            local actions = {map = function() end, select = function() end, rowAction = function() end,
                clearCorrection = function() end, toggleGroup = function() end, releaseLevel = function() end, reviewChanges = function() end}
            local window = addon.ShowAdventure(function() return {rows = entries, summary = "A description\nwith a second line\nand a third line"} end, actions)
            for _, theme in ipairs({"graphite", "parchment", "midnight"}) do
                addon.UI.Theme.Apply(false, theme, false)
                for _, mode in ipairs({"departure", "compare", "chains", "along", "blocked", "bags", "group", "later", "hiddenOffers", "changes", "level", "corrections"}) do
                    window:SelectMode(mode)
                    local rowTop = -window.rows[1].point[3]
                    local summaryBottom = -window.summary.points.TOPLEFT[3] + window.summary:GetStringHeight()
                    assert(rowTop >= summaryBottom + 10, "Description overlaps rows")
                    assert(-window.rows[4].point[3] + window.rows[4]:GetHeight() <= window:GetHeight() - 90, "Rows overlap footer")
                    local count = 0 for _ in pairs(window.tabs) do count = count + 1 end equal(count, 3)
                end
            end
        end end
    end)
    test("Along-route and comparison actions open explicit previews rather than selecting quests", function()
        local addon = Fixture()
        local selected, reviewed, opened = 0, 0, 0
        local entry = {quest = {id = 1, title = "Ready"}, target = {mapID = 1, x = .2, y = .2}}
        local window = addon.ShowAdventure(function() return {rows = {entry}} end, {
            map = function() opened = opened + 1 end, select = function() selected = selected + 1 end,
            rowAction = function(e, mode) equal(e, entry) assert(mode == "along" or mode == "compare") reviewed = reviewed + 1 end}, "along")
        window.rows[1].map:Click() equal(opened, 1) equal(reviewed, 0)
        window.rows[1].choose:Click() equal(reviewed, 1) equal(selected, 0)
        window:SelectMode("compare") window.rows[1].choose:Click() equal(reviewed, 2) equal(selected, 0)
    end)
    test("Pickup rows expose Skip and all three choices without turning map clicks into skip actions", function()
        local addon, tracker, settings, maps, skipped, render, quest, c, parent, env = Fixture("deDE")
        local choices, mapped, undid = {}, 0, false
        local p = {stops = {{quest = quest, target = {mapID = 1, x = .2, y = .2}, action = "accept"},
            {quest = c, target = {mapID = 1, x = .3, y = .3}, action = "objective"}}, index = 1, xp = 0, missing = 0, unknownXP = 0}
        local window = addon.ShowExcursion(p, {map = function() mapped = mapped + 1 end,
            skip = function(id, mode) equal(id, quest.id) choices[#choices + 1] = mode return true, addon.L.OfferSkipped end,
            canUndo = function() return true end, undo = function() undid = true return true end})
        window.rows[1]:Click() equal(mapped, 1) equal(#choices, 0)
        assert(window.rows[1].skip:IsShown()) equal(window.rows[2].skip:IsShown(), false)
        window.rows[1].skip:Click() equal(choices[1], "once")
        local choiceWindow = addon.UI.ShowOfferChoices(window.rows[1], function(mode) choices[#choices + 1] = mode end)
        choiceWindow.rows[2]:Click() equal(choices[2], "later")
        addon.UI.ShowOfferChoices(window.rows[1], function(mode) choices[#choices + 1] = mode end).rows[3]:Click()
        equal(choices[3], "hide") window.undo:Click() equal(undid, true)
    end)
    test("Current acceptance keeps Skip and review accessible in the simple navigator", function()
        local addon, tracker, settings, maps, skipped, render, quest = Fixture()
        local id, reviewed
        addon.SkipCurrentOffer = function(value) id = value end addon.OpenOutingReview = function() reviewed = true end
        settings.simpleNavigator = true
        tracker:SetDecisionBrief({steps = {{quest = quest, kind = "accept", offer = true}}, closing = {}})
        tracker.nextBoard.rows[1].skip:Click() equal(id, quest.id) equal(#skipped, 0)
        tracker:SetDecisionBrief({steps = {}, closing = {}, acceptanceReview = true})
        tracker.nextBoard.assist:Click() equal(reviewed, true)
    end)
    test("Corpse navigation overrides quest/detour arrows and unknown corpse data cannot fall back to quests", function()
        local addon, tracker, settings, maps, skipped, render, quest = Fixture("deDE")
        local originalView, detour = settings.navigatorView, {name = "Existing detour"}
        tracker:SetDetour(detour, {yards = 100}) settings.showScreenArrow = false
        tracker:RenderRecovery({active = true, ghost = true, exact = true, target = {mapID = 1, x = .2, y = .3}},
            {yards = 400, east = 1, north = 0}, 1, 0)
        equal(tracker.navigation.title:GetText(), addon.L.RecoveryTitle)
        equal(tracker.navigation.distance:GetText(), "~400 yd") assert(tracker.navigation:IsShown())
        tracker:RenderDirection(-1, 0, "Quest direction") equal(tracker.navigation.title:GetText(), addon.L.RecoveryTitle)
        tracker:RenderRecovery({active = true, ghost = true}, nil, nil, nil)
        equal(tracker.navigation.goal:GetText(), addon.L.RecoveryUnknown)
        equal(tracker.navigation.arrow:IsShown(), false) equal(tracker.detour, detour)
        tracker:SetRecoveryState(nil) equal(tracker.recoveryState, nil) equal(tracker.detour, detour)
        equal(settings.navigatorView, originalView) equal(#skipped, 0)
    end)
    test("Quick settings can filter recommendation controls and expose a separate example preview", function()
        local addon, _, settings = Fixture()
        local entries = {{key = "theme", name = "Theme", help = "Colors", basic = true, effect = "view", choices = {"graphite"}},
            {key = "repeatablePolicy", name = "Repeatable", help = "Ranking", basic = true, effect = "logic", choices = {"show"}}}
        settings.theme, settings.repeatablePolicy = "graphite", "show"
        local window = addon.ShowQuickSettings(entries, settings, function() end)
        window.filterScope = "logic" window:Refresh()
        equal(window.rows[1].entry.key, "repeatablePolicy") equal(window.rows[2]:IsShown(), false)
        assert(window.examples:IsShown())
    end)
    test("Settings list scrolls compact rows with help text instead of paging", function()
        local addon, _, settings = Fixture()
        local entries = {}
        for index = 1, 12 do
            entries[index] = {key = "k" .. index, name = "Setting " .. index, help = "Help " .. index, basic = true,
                effect = "view", kind = "boolean", control = {SetValue = function() end}}
        end
        local window = addon.ShowQuickSettings(entries, settings, function() end)
        equal(#window.rows, 8) equal(window.rows[1].help.text, "Help 1") equal(window.rows[8]:IsShown(), true)
        assert(window.placeholder:IsShown()) assert(window.pageLabel.text:find("12", 1, true))
        window.scripts.OnMouseWheel(window, -1)
        equal(window.rows[1].entry.key, "k2")
        window:Scroll(50) equal(window.rows[1].entry.key, "k5") equal(window.next.enabled, false)
        window.search:SetText("Setting 1") window.search.scripts.OnTextChanged(window.search)
        equal(window.offset, 0) equal(window.placeholder:IsShown(), false)
    end)
    test("Text links wrap into new lines and turn-in steps do not repeat the state word", function()
        local addon = Fixture()
        local links = {}
        for index = 1, 3 do
            local link = addon.UI.StyleLink(addon.UI.MakeButton(addon.UI.CreateWindow(100, 100, "x", {hub = false})))
            link:Show() link.textLabel.GetStringWidth = function() return 100 end
            links[index] = link
        end
        local y = addon.UI.FlowLinks(links, 0, 250, 1)
        equal(links[1].point[2], 0) equal(links[2].point[2], 120) equal(links[3].point[2], 0)
        equal(links[3].point[3], -22) equal(y, 22 + 18 + 6)
        links[2]:Hide()
        addon.UI.FlowLinks(links, 0, 250, 1) equal(links[3].point[2], 120)
        local summary = addon.PickupPlanning.AreaSummary({active = 1, pickups = 1, handIns = 2, xp = 10})
        assert(summary:find(addon.L.TourCardPickupOne:format(1), 1, true))
        assert(summary:find(addon.L.TourCardHandInMany:format(2), 1, true))
    end)
    test("Setup applies only clicked choices on Finish and Skip changes nothing", function()
        local addon = Fixture()
        local function Catalog(settings)
            local catalog = {}
            for _, key in ipairs({"showQuestieOffers", "useQuestieKillLocations", "simpleNavigator", "detailMode",
                "acceptedRows", "offerRows", "fontPercent", "opacityPercent", "showScreenArrow", "showQuestXP", "highContrast"}) do
                catalog[#catalog + 1] = {key = key, control = {SetValue = function(_, value) settings[key] = value end}}
            end
            return catalog
        end
        local settings, mode, finished = {displayMode = "full", simpleNavigator = true, showQuestieOffers = true}, nil, 0
        local options = {catalog = Catalog(settings), questie = true, setDisplayMode = function(value) mode = value end,
            done = function() finished = finished + 1 end}
        local wizard = addon.ShowSetup(settings, options)
        equal(wizard.step, 1) assert(wizard.choiceButtons[1].text:find("^> "))
        wizard.choiceButtons[2]:Click() wizard.next:Click()
        wizard.choiceButtons[2]:Click() wizard.next:Click()
        wizard.choiceButtons[3]:Click() wizard.next:Click()
        equal(wizard:IsShown(), false) equal(finished, 1) equal(settings.setupDone, true)
        equal(mode, "arrow") equal(settings.showQuestieOffers, false) equal(settings.useQuestieKillLocations, false)
        equal(settings.simpleNavigator, false) equal(settings.acceptedRows, 5)
        local untouched = {displayMode = "full", simpleNavigator = false, detailMode = "compact"}
        local quiet = {catalog = Catalog(untouched), setDisplayMode = function() error("skip must not change the display") end}
        wizard = addon.ShowSetup(untouched, quiet)
        equal(wizard.choiceButtons[1]:IsShown(), true)
        wizard.next:Click() equal(wizard.choiceButtons[1]:IsShown(), false)
        wizard.skip:Click()
        equal(untouched.simpleNavigator, false) equal(untouched.detailMode, "compact") equal(untouched.setupDone, true)
        wizard = addon.ShowSetup(untouched, quiet)
        wizard.next:Click() wizard.next:Click() wizard.next:Click()
        equal(untouched.detailMode, "compact")
    end)
end
