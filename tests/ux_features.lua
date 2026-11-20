return function(test, addon, equal, near)
    local function Fixture()
        local methods = {}
        local function Region(width, height)
            return setmetatable({width = width or 600, height = height or 500, shown = false, scripts = {}}, {__index = methods})
        end
        function methods:SetScript(key, value) self.scripts[key] = value end
        function methods:HookScript(key, value)
            local previous = self.scripts[key]
            self.scripts[key] = function(...) if previous then previous(...) end value(...) end
        end
        function methods:SetShown(value)
            if self.shown == value then return end
            local wasVisible = self:IsVisible()
            self.shown = value
            local visible = self:IsVisible()
            if wasVisible == visible then return end
            local callback = self.scripts[visible and "OnShow" or "OnHide"]
            if callback then callback(self) end
        end
        function methods:Show() self:SetShown(true) end
        function methods:Hide() self:SetShown(false) end
        function methods:IsShown() return self.shown end
        function methods:IsVisible() return self.shown and (not self.parent or self.parent:IsVisible()) end
        function methods:SetEnabled(value) self.enabled = value end
        function methods:Click() assert(self.enabled ~= false) if self.scripts.OnClick then self.scripts.OnClick(self) end end
        function methods:SetSize(width, height) self.width, self.height = width, height end
        function methods:SetWidth(value) self.width = value end
        function methods:SetHeight(value) self.height = value end
        function methods:GetWidth() return self.width end
        function methods:GetHeight() return self.height end
        function methods:SetScale(value) self.scale = value end
        function methods:SetParent(value) self.parent = value end
        function methods:SetText(value) self.text = value end
        function methods:SetPoint(...) self.point = {...} end
        function methods:CreateTexture() return Region() end
        for _, key in ipairs({"SetFrameStrata", "SetClampedToScreen", "SetMovable", "EnableMouse", "RegisterForDrag",
            "StartMoving", "StopMovingOrSizing", "SetBackdrop", "SetJustifyH", "SetMaxLines", "SetTextColor", "ClearAllPoints"}) do methods[key] = function() end end
        local parent, demo, calls = Region(1000, 760), false, {}
        parent.shown = true
        local env = setmetatable({UIParent = parent, UISpecialFrames = {}, print = function() end}, {__index = getfenv()})
        env.CreateFrame = function(_, name, owner) local region = Region() region.parent = owner if name then env[name] = region end return region end
        local isolated = {L = addon.L, DemoMode = {IsActive = function() return demo end}, UI = {}}
        isolated.UI.CreateLabel = function() return Region() end
        isolated.UI.CreateUtilityButton = function(owner, label, width, callback)
            local button = Region(width, 24) button.parent, button.text, button.textLabel = owner, label, Region()
            button:SetScript("OnClick", callback) return button
        end
        isolated.UI.Theme = {WatchFrame = function() end, Color = function() return 1, 1, 1 end, Bind = function() end,
            Frame = function(frame) frame.backgroundAlpha = frame.embedded and 0 or 1 end}
        local chunk = assert(loadfile("UI/ToolHub.lua")) setfenv(chunk, env)("FQN", isolated)
        local hub = isolated.UI.ToolHub
        local shared, settings, automatic = Region(650, 575), Region(570, 430), Region(600, 600)
        hub.Attach(shared, addon.L.QuestWorkspace) hub.Attach(settings, addon.L.QuickSettings) hub.Attach(automatic, addon.L.PlanningOverview)
        hub.Configure({finder = function() calls[#calls + 1] = "finder" shared.mode = "finder" hub.Present(shared, "finder") end,
            tour = function() calls[#calls + 1] = "tour" shared.mode = "tour" hub.Present(shared, "tour") end,
            settings = function() calls[#calls + 1] = "settings" hub.Show(settings) end,
            automatic = function() calls[#calls + 1] = "automatic" hub.Show(automatic) end})
        return hub, shared, settings, automatic, parent, calls, env, function(value) demo = value end, Region
    end
    test("Tool navigation shows one panel at a time and keeps existing panel state", function()
        local hub, shared, settings = Fixture()
        hub.Open("finder") shared.query = "Retained search"
        assert(shared:IsShown()) equal(hub.key, "finder") equal(shared.embedded, true)
        hub.Open("settings") equal(shared:IsShown(), false) assert(settings:IsShown())
        hub.Open("finder") equal(settings:IsShown(), false) equal(shared.query, "Retained search")
        equal(shared.parent, hub.root) equal(shared.backgroundAlpha, 0)
        equal(#hub.root.tabs, 5)
    end)
    test("Back navigation restores the correct view when finder and tour share one frame", function()
        local hub, shared = Fixture()
        hub.Open("finder") hub.Open("tour")
        equal(shared.mode, "tour") hub.root.back:Click()
        equal(shared.mode, "finder") equal(hub.key, "finder") equal(#hub.history, 0)
    end)
    test("Tool categories remember their last page and Close hides the active child", function()
        local hub, shared, settings, automatic = Fixture()
        hub.Open("automatic") hub.Open("settings") hub.root.navigation.planning:Click()
        equal(hub.key, "automatic") assert(automatic:IsShown()) equal(settings:IsShown(), false)
        hub.root.close:Click() equal(hub.root:IsShown(), false) equal(automatic:IsShown(), false)
        hub.Open("tour") assert(hub.root:IsShown()) assert(shared:IsShown())
    end)
    test("The tool window fits a smaller UI parent without changing display preferences", function()
        local hub, _, _, _, parent, _, env = Fixture()
        parent.width, parent.height = 800, 600
        hub.Open("tour")
        assert(hub.root.width * hub.root.scale <= 768.0001)
        assert(hub.root.height * hub.root.scale <= 568.0001)
        equal(env.UISpecialFrames[1], "ForeverQuestNavigatorTools")
    end)
    test("Demo mode blocks tool navigation and standalone demo panels are not embedded", function()
        local hub, shared, settings, _, _, calls, _, setDemo, region = Fixture()
        hub.Open("finder") local before = #calls
        setDemo(true) hub.Open("settings") equal(#calls, before) equal(hub.key, "finder")
        setDemo(false)
        local demo = region() demo.hubStandalone = true hub.Attach(demo, addon.L.PlanningOverview) demo:Show()
        equal(hub.active, shared) equal(demo.embedded, nil)
    end)
    test("Changing tool size keeps the window header at its existing position", function()
        local hub = Fixture()
        hub.Open("tour")
        hub.root.GetLeft = function() return 100 end
        hub.root.GetTop = function() return 600 end
        hub.Open("settings")
        equal(hub.root.point[1], "TOPLEFT") near(hub.root.point[4], 100) near(hub.root.point[5], 600)
    end)
    test("Settings reopen after Close even when the tool parent is hidden", function()
        local hub, _, settings = Fixture()
        hub.Open("settings") assert(settings:IsVisible())
        hub.root.close:Click() equal(hub.root:IsShown(), false)
        hub.Open("settings")
        assert(hub.root:IsShown(), "Reopening settings must show its hidden parent")
        assert(settings:IsVisible())
    end)
    test("Repeated opens also recover a shown child beneath the hidden tool window", function()
        local hub, _, settings = Fixture()
        for _ = 1, 4 do
            hub.Open("settings") settings.query = "Keep this filter"
            hub.root:Hide()
            settings:Show() equal(settings:IsVisible(), false)
            hub.Open("settings")
            assert(settings:IsVisible()) equal(settings.query, "Keep this filter") equal(hub.switching, nil)
        end
    end)
    test("Other registered tools reopen through the same path after closing", function()
        local hub, _, settings, automatic = Fixture()
        hub.Open("settings") hub.root:Hide()
        hub.Open("automatic") assert(automatic:IsVisible()) equal(settings:IsVisible(), false)
        hub.root:Hide() hub.Open("automatic") assert(automatic:IsVisible())
        hub.root:Hide() hub.Open("settings") assert(settings:IsVisible())
    end)
end
