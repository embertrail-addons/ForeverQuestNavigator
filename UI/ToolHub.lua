local _, addon = ...
local L = addon.L
local Hub = {actions = {}, history = {}, pages = {}, groups = {}}
addon.UI.ToolHub = Hub

local function Demo() return addon.DemoMode and addon.DemoMode.IsActive() end
-- advanced pages are hidden in simple mode unless they are the page being shown.
local function Definition(key, label, title, advanced) return {key = key, label = label, title = title, advanced = advanced} end
-- options.simple(): true while the simple experience is active; options.settings stores the window position.
function Hub.Configure(actions, options)
    Hub.actions = actions
    Hub.options = options or {}
    Hub.groups = {
        {key = "quests", label = L.HubQuests, pages = {
            Definition("finder", L.HubFind, L.QuestWorkspace), Definition("notes", L.HubNotes, L.QuestNotepad),
            Definition("details", L.DetailsShort, L.NavigatorDetails),
            Definition("feedback", L.HubFeedback, L.FeedbackManager, true)}},
        {key = "planning", label = L.HubPlanning, pages = {
            Definition("zones", L.HubZones, L.ZoneOverview), Definition("tour", L.HubTour, L.QuestWorkspace, true),
            Definition("automatic", L.HubAutomatic, L.PlanningOverview, true)}},
        {key = "outing", label = L.HubOuting, pages = {
            Definition("outing", L.HubOutingPage, L.ExcursionTitle, true), Definition("adventure", L.HubAdventure, L.AdventureTitle, true),
            Definition("detour", L.HubDetour, L.TemporaryDetour, true), Definition("access", L.HubAccess, L.AccessManager, true)}},
        {key = "history", label = L.HubHistory, pages = {
            Definition("session", L.HubSession, L.SessionTitle), Definition("changes", L.HubChanges, L.ChangeHistory, true)}},
        {key = "settings", label = L.Settings, pages = {
            Definition("settings", L.HubOptions, L.QuickSettings), Definition("profiles", L.HubProfiles, L.AppearanceProfiles),
            Definition("share", L.HubShare, L.DisplayTransfer, true)}},
        {key = "help", label = L.HubHelp, pages = {Definition("help", L.HubOverview, L.HubHelpTitle),
            Definition("commands", L.HubCommands, L.CommandMenuTitle), Definition("whatsnew", L.HubWhatsNew, L.WhatsNew)}},
    }
    for _, group in ipairs(Hub.groups) do for _, page in ipairs(group.pages) do page.group = group Hub.pages[page.key] = page end end
    Hub.ready = true
end
local function Simple() return Hub.options and Hub.options.simple and Hub.options.simple() == true end
-- Pages listed in the current mode; the active page always stays reachable.
function Hub.VisiblePages(group, activeKey)
    local pages, simple = {}, Simple()
    for _, page in ipairs(group.pages) do
        if not (simple and page.advanced) or page.key == activeKey then pages[#pages + 1] = page end
    end
    return pages
end
function Hub.LayoutNavigation(activeKey)
    if not Hub.root then return end
    local row = 0
    for _, group in ipairs(Hub.groups) do
        local button = Hub.root.navigation[group.key]
        local visible = #Hub.VisiblePages(group, activeKey) > 0
        button:SetShown(visible)
        if visible then
            button:ClearAllPoints() button:SetPoint("TOPLEFT", 18, -95 - row * 39)
            row = row + 1
        end
    end
end
local function FindPage(frame)
    if frame.hubPage then return frame.hubPage end
    if frame.hubTitle == L.AccessRouteEditor then return "access" end
    for _, group in ipairs(Hub.groups) do
        for _, page in ipairs(group.pages) do if frame.hubTitle == page.title then return page.key end end
    end
end
function Hub.Resize()
    local frame, root = Hub.active, Hub.root
    if not (frame and root) then return end
    local left, top, ratio
    if root:IsShown() and root.GetLeft and root.GetTop then
        left, top = root:GetLeft(), root:GetTop()
        local parentScale = UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or 1
        ratio = (root.GetEffectiveScale and root:GetEffectiveScale() or 1) / parentScale
        if left and top then left, top = left * ratio, top * ratio end
    end
    local width, height = frame:GetWidth() + 190, math.max(430, frame:GetHeight() + 70)
    root:SetSize(width, height)
    local availableWidth = UIParent and UIParent.GetWidth and UIParent:GetWidth() or 1024
    local availableHeight = UIParent and UIParent.GetHeight and UIParent:GetHeight() or 768
    if availableWidth > 0 and availableHeight > 0 and root.SetScale then
        root:SetScale(math.max(.4, math.min(1, (availableWidth - 32) / width, (availableHeight - 32) / height)))
    end
    if left and top then
        local parentScale = UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or 1
        local nextRatio = (root.GetEffectiveScale and root:GetEffectiveScale() or 1) / parentScale
        root:ClearAllPoints() root:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left / nextRatio, top / nextRatio)
    end
end
function Hub.PaintNavigation()
    if not Hub.root or not Hub.pages[Hub.key] then return end
    local selectedGroup = Hub.pages[Hub.key].group.key
    for key, button in pairs(Hub.root.navigation) do
        button.textLabel:SetTextColor(addon.UI.Theme.Color(key == selectedGroup and "heading" or "text"))
    end
end
local function EnsureRoot()
    if Hub.root then return end
    local root = CreateFrame("Frame", "ForeverQuestNavigatorTools", UIParent, "BackdropTemplate")
    Hub.root = root root:Hide()
    root:SetPoint("CENTER") root:SetFrameStrata("DIALOG") root:SetClampedToScreen(true)
    root:SetMovable(true) root:EnableMouse(true) root:RegisterForDrag("LeftButton")
    root:SetScript("OnDragStart", root.StartMoving)
    root:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local store = Hub.options and Hub.options.settings
        if store and self.GetLeft and self.GetTop then store.hubX, store.hubY = self:GetLeft(), self:GetTop() end
    end)
    local store = Hub.options and Hub.options.settings
    if store and store.hubX and store.hubY then
        root:ClearAllPoints() root:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", store.hubX, store.hubY)
    end
    root:SetBackdrop({bgFile = "Interface/Buttons/WHITE8X8", edgeFile = "Interface/Buttons/WHITE8X8", edgeSize = 1})
    addon.UI.Theme.WatchFrame(root)
    root.heading = addon.UI.CreateLabel(root, "GameFontNormal")
    root.heading:SetPoint("TOPLEFT", 18, -16) root.heading:SetText("Forever Quest Navigator")
    root.close = addon.UI.CreateUtilityButton(root, "×", 28, function() root:Hide() end)
    root.close:SetPoint("TOPRIGHT", -10, -10)
    root.back = addon.UI.CreateUtilityButton(root, L.HubBack, 140, function()
        local entry = table.remove(Hub.history)
        if entry then
            Hub.restoring = true
            if entry.frame.hubTitle == L.QuestWorkspace then Hub.Open(entry.key)
            else Hub.Present(entry.frame, entry.key) if entry.frame.Refresh then entry.frame:Refresh() end end
            Hub.restoring = nil
        end
    end)
    root.back:SetPoint("TOPLEFT", 14, -42) root.back:SetSize(90, 20)
    -- Back is navigation history, not a section: show it as a quiet link.
    if addon.UI.StyleLink then addon.UI.StyleLink(root.back) end
    root.navigation = {}
    for index, group in ipairs(Hub.groups) do
        local key = group.key
        local button = addon.UI.CreateUtilityButton(root, group.label, 140, function()
            local visible = Hub.VisiblePages(group)
            local target = Hub.lastPages and Hub.lastPages[key]
            local allowed = false
            for _, page in ipairs(visible) do if page.key == target then allowed = true end end
            Hub.Open(allowed and target or (visible[1] or group.pages[1]).key)
        end)
        button:SetPoint("TOPLEFT", 18, -95 - (index - 1) * 39)
        button.selection = button:CreateTexture(nil, "ARTWORK")
        button.selection:SetPoint("TOPLEFT") button.selection:SetPoint("BOTTOMLEFT") button.selection:SetWidth(3)
        addon.UI.Theme.Bind(button.selection, "heading", 1)
        root.navigation[key] = button
    end
    root.tabs = {}
    for index = 1, 5 do
        local button = addon.UI.CreateUtilityButton(root, "", 100, function() end)
        button.selection = button:CreateTexture(nil, "ARTWORK")
        button.selection:SetPoint("BOTTOMLEFT") button.selection:SetPoint("BOTTOMRIGHT") button.selection:SetHeight(2)
        addon.UI.Theme.Bind(button.selection, "heading", 1)
        root.tabs[index] = button
    end
    root.hint = addon.UI.CreateLabel(root, "GameFontDisableSmall")
    root.hint:SetPoint("BOTTOMLEFT", 18, 18) root.hint:SetWidth(140) root.hint:SetJustifyH("LEFT")
    root.hint:SetMaxLines(5) root.hint:SetText(L.HubNavigationHelp)
    root:SetScript("OnHide", function()
        if Hub.switching then return end
        Hub.switching = true if Hub.active then Hub.active:Hide() end Hub.switching = nil
    end)
    if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "ForeverQuestNavigatorTools") end
end
function Hub.Open(key)
    if Demo() then print("FQN | " .. L.DemoReadOnly) return end
    local action = Hub.actions[key]
    if action then action() end
end
-- OnShow does not fire when a panel's parent is hidden. Explicit opens must
-- reveal the tool window first, including panels whose own shown flag is set.
function Hub.Show(frame, key)
    key = key or FindPage(frame)
    if Hub.ready and not frame.hubStandalone and Hub.pages[key] then
        Hub.Present(frame, key)
    else frame:Show() end
end
addon.UI.ShowUtilityPanel = Hub.Show
function Hub.Present(frame, key)
    if not Hub.ready or Hub.switching or frame.hubStandalone then return end
    key = key or FindPage(frame)
    local page = Hub.pages[key]
    if not page then return end
    if Demo() then frame:Hide() print("FQN | " .. L.DemoReadOnly) return end
    EnsureRoot()
    Hub.switching = true
    local previous = Hub.active
    if previous and (previous ~= frame or Hub.key ~= key) and not Hub.restoring then
        Hub.history[#Hub.history + 1] = {frame = previous, key = Hub.key}
        if #Hub.history > 12 then table.remove(Hub.history, 1) end
    end
    if previous and previous ~= frame then previous:Hide() end
    Hub.active, Hub.key = frame, key
    Hub.lastPages = Hub.lastPages or {} Hub.lastPages[page.group.key] = key
    frame.hubPage, frame.embedded = key, true
    frame:SetParent(Hub.root) frame:ClearAllPoints() frame:SetPoint("TOPLEFT", 174, -56)
    if frame.closeButton then frame.closeButton:Hide() end
    -- The tab already names the page; the panel's own heading would repeat it.
    if frame.heading then frame.heading:Hide() end
    frame:SetScript("OnDragStart", function() Hub.root:StartMoving() end)
    frame:SetScript("OnDragStop", function() Hub.root:StopMovingOrSizing() end)
    addon.UI.Theme.Frame(frame, 0)
    if frame.OnEmbedded then frame:OnEmbedded() end
    Hub.Resize()
    for groupKey, button in pairs(Hub.root.navigation) do
        local selected = groupKey == page.group.key button.selection:SetShown(selected)
    end
    Hub.LayoutNavigation(key)
    Hub.PaintNavigation()
    local pages = Hub.VisiblePages(page.group, key)
    local count = #pages
    local width = (frame:GetWidth() - 20 - (count - 1) * 6) / count
    for index, button in ipairs(Hub.root.tabs) do
        local entry = pages[index]
        button:SetShown(entry ~= nil and count > 1)
        if entry then
            button:SetWidth(width) button:ClearAllPoints() button:SetPoint("TOPLEFT", 184 + (index - 1) * (width + 6), -38)
            button:SetText(entry.label) button.selection:SetShown(entry.key == key)
            button:SetScript("OnClick", function() Hub.Open(entry.key) end)
        end
    end
    Hub.root.back:SetEnabled(#Hub.history > 0)
    Hub.root:Show() frame:Show()
    Hub.switching = nil
end
function Hub.Attach(frame, title)
    frame.hubTitle = title
    frame:HookScript("OnShow", function(self) Hub.Present(self) end)
    frame:HookScript("OnHide", function(self)
        if Hub.active == self and not Hub.switching and Hub.root then Hub.root:Hide() end
    end)
    frame:HookScript("OnSizeChanged", function(self) if Hub.active == self and not Hub.switching then Hub.Resize() end end)
end
function Hub.Hide() if Hub.root then Hub.root:Hide() end end

local help
function addon.ShowUXHelp(actions)
    if not help then
        help = addon.UI.CreateUtilityPanel(600, 390, L.HubHelpTitle)
        help.body = addon.UI.CreateLabel(help, "GameFontHighlightSmall")
        help.body:SetPoint("TOPLEFT", 18, -50) help.body:SetPoint("TOPRIGHT", -18, -50)
        help.body:SetJustifyH("LEFT") help.body:SetMaxLines(30) help.body:SetText(L.HubHelpBody)
        help.report = addon.UI.CreateUtilityButton(help, L.ProblemReportTitle, 270, function() help.actions.problem() end)
        help.report:SetPoint("BOTTOMLEFT", 18, 64)
        help.diagnostic = addon.UI.CreateUtilityButton(help, L.DebugTitle, 270, function() help.actions.diagnostic() end)
        help.diagnostic:SetPoint("BOTTOMRIGHT", -18, 64)
        help.guide = addon.UI.CreateUtilityButton(help, L.Introduction, 270, function() help.actions.guide() end)
        help.guide:SetPoint("BOTTOMLEFT", 18, 22)
        help.updates = addon.UI.CreateUtilityButton(help, L.WhatsNew, 270, function() help.actions.updates() end)
        help.updates:SetPoint("BOTTOMRIGHT", -18, 22)
    end
    help.actions = actions help:SetHeight(math.max(390, help.body:GetStringHeight() + 160)) Hub.Show(help)
end
