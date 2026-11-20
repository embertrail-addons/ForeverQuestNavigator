local addonName, addon = ...
local L = addon.L
local Mode = {}
addon.DemoMode = Mode
local current
local function Label(parent, text)
    local label = addon.UI.CreateLabel(parent, "GameFontNormalSmall")
    label:SetText(text) label:SetJustifyH("LEFT")
    return label
end
function Mode.IsActive() return current ~= nil end
function Mode.Stop()
    local demo = current
    if not demo then return end
    current = nil
    demo.tracker:Hide() demo.tracker.navigation:Hide() demo.controls:Hide()
    if demo.planning then demo.planning:Hide() end
    if demo.mapNotice then demo.mapNotice:Hide() end
    if demo.mapOpened then addon.ShowQuestMapMarker() end
    addon.UI.SetFontSize(demo.liveSettings.fontPercent or 100)
    if demo.wasVisible then demo.live:Show() end
    if demo.onStop then demo.onStop() end
    print("FQN | " .. L.DemoStopped)
end
local function ReadOnly() print("FQN | " .. L.DemoReadOnly) end
local function OpenMap(demo, stop)
    if InCombatLockdown and InCombatLockdown() then print(L.CombatMap) return end
    if not (stop and stop.target and C_Map and C_Map.OpenWorldMap) then return end
    demo.mapOpened = true
    demo.mapTarget = stop.target
    C_Map.OpenWorldMap(stop.target.mapID)
    local preview = demo.model.view.preview
    local first = preview and preview[1] and preview[1].target
    local route = first and first.mapID == stop.target.mapID and first.x == stop.target.x and first.y == stop.target.y and preview or nil
    addon.ShowQuestMapMarker(stop.target, function() demo.mapOpened, demo.mapTarget = nil, nil addon.ShowQuestMapMarker() end, route)
    if not demo.mapNotice then
        demo.mapNotice = CreateFrame("Frame", nil, UIParent)
        demo.mapNotice:SetSize(620, 28) demo.mapNotice:SetPoint("TOP", UIParent, "TOP", 0, -34)
        demo.mapNotice:SetFrameStrata("TOOLTIP")
        local text = Label(demo.mapNotice, L.DemoBadge)
        text:SetPoint("CENTER")
        if WorldMapFrame and WorldMapFrame.HookScript then
            WorldMapFrame:HookScript("OnHide", function() demo.mapNotice:Hide() end)
        end
    end
    demo.mapNotice:Show()
end
local function MapQuest(demo, id)
    for _, offer in ipairs(demo.model.offers) do
        if offer.id == id then OpenMap(demo, {target = offer.marker}) return end
    end
    local measured = demo.model.measurements[id]
    if measured then OpenMap(demo, {target = measured.marker}) end
end
local function Render(demo)
    local model = addon.DemoData.Build(demo.data, demo.scene)
    if not model then print("FQN | " .. L.DemoDataMissing) return false end
    demo.model = model
    demo.settings.detailMode = demo.scene == "compact" and "compact" or "detailed"
    demo.tracker:RenderSnapshot(model, {})
    demo.tracker:RenderNearbyOffers(model.offers, true)
    demo.tracker:RenderDistances(model.measurements)
    local right, forward = addon.QuestLocation.GetRelativeDirection(model.activeMeasurement, .7)
    demo.tracker:RenderDirection(right, forward)
    demo.tracker:RenderRowDirections(.7)
    -- Suppress transition notifications: screenshots are static until changed.
    if demo.tracker.navigation.notice then
        demo.tracker.navigation.notice:Hide()
        demo.tracker.navigation.noticeSeconds = nil
        demo.tracker.navigation:UpdateLayout()
    end
    demo.tracker:Show()
    demo.controls.info:SetText(model.zone .. " · " .. L.DemoCharacter:format(model.playerLevel)
        .. "\n" .. L["DemoScene_" .. demo.scene])
    demo.badge:SetText(L.DemoBadge .. " · " .. L.DemoCharacter:format(model.playerLevel))
    if demo.mapOpened then
        local target = model.activeMeasurement.marker
        demo.mapTarget = target
        addon.ShowQuestMapMarker(target, function() demo.mapOpened, demo.mapTarget = nil, nil addon.ShowQuestMapMarker() end, model.view.preview)
    end
    return true
end
function Mode.Open(settings, live, onStop, requested)
    if current then current.controls:Show() return true end
    local data, message, presetIndex
    for index, preset in ipairs(addon.DemoData.presets) do
        if not requested or requested == preset.key then
            data, message = addon.DemoData.Load(preset)
            if data then presetIndex = index break end
        end
    end
    if not data then print("FQN | " .. (message or L.DemoDataMissing)) return false end
    local demo = {data = data, preset = presetIndex, scene = "objectives", live = live,
        liveSettings = settings, wasVisible = live:IsShown(), onStop = onStop}
    demo.settings = addon.UndoHistory.Copy(settings)
    local copy = demo.settings
    copy.hidden, copy.displayMode, copy.collapsed = false, "full", false
    copy.x, copy.y, copy.trackerTopAnchored, copy.trackerWidth = -80, 210, true, 480
    copy.detailMode, copy.acceptedRows, copy.offerRows, copy.opacityPercent = "detailed", 3, 3, 95
    copy.alternativesCollapsed, copy.offersCollapsed = false, false
    copy.showScreenArrow, copy.showDirectionArrow, copy.showQuestXP = true, true, true
    copy.screenArrowX, copy.screenArrowY = nil, nil
    copy.lockTrackerPosition, copy.lockNavigationPosition, copy.allowTrackerResize = false, false, true
    local actions = setmetatable({
        hideTracker = Mode.Stop,
        openSettings = function() demo.controls:Show() end,
        openQuestMap = function(id) MapQuest(demo, id) end,
        openOfferMap = function(id) MapQuest(demo, id) end,
        openRouteStop = function(stop) OpenMap(demo, stop) end,
        getQuestHold = function() return false end,
        refreshMeasurements = function() if demo.model then Render(demo) end end,
    }, {__index = function() return ReadOnly end})
    local version = C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(addonName, "Version")
    demo.tracker = addon.CreateQuestTracker(copy, actions, version)
    demo.badge = Label(demo.tracker, L.DemoBadge)
    demo.badge:SetPoint("BOTTOMLEFT", demo.tracker, "TOPLEFT", 4, 5)
    demo.badge:SetPoint("BOTTOMRIGHT", demo.tracker, "TOPRIGHT", -4, 5)
    demo.badge:SetMaxLines(2)
    demo.controls = addon.UI.CreateUtilityPanel(420, 310, L.DemoTitle)
    demo.controls:ClearAllPoints() demo.controls:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -30, -110)
    local help = Label(demo.controls, L.DemoExplanation)
    help:SetPoint("TOPLEFT", 18, -46) help:SetPoint("TOPRIGHT", -18, -46) help:SetMaxLines(4)
    demo.controls.info = Label(demo.controls, "")
    demo.controls.info:SetPoint("TOPLEFT", 18, -120) demo.controls.info:SetMaxLines(3)
    local function Button(text, x, y, callback)
        local button = addon.UI.CreateUtilityButton(demo.controls, text, 184, callback)
        button:SetPoint("BOTTOMLEFT", x, y)
        return button
    end
    demo.controls.scene = Button(L.DemoNextScene, 18, 100, function()
        demo.scene = demo.scene == "objectives" and "turnins" or demo.scene == "turnins" and "compact" or "objectives"
        Render(demo)
    end)
    demo.controls.zone = Button(L.DemoNextZone, 218, 100, function()
        local nextIndex = demo.preset % #addon.DemoData.presets + 1
        local nextData, errorMessage = addon.DemoData.Load(addon.DemoData.presets[nextIndex])
        if not nextData then print("FQN | " .. errorMessage) return end
        demo.data, demo.preset = nextData, nextIndex Render(demo)
    end)
    demo.controls.plan = Button(L.PlanningOverview, 18, 60, function()
        demo.planning = addon.ShowPlanningOverview(function() return demo.model end,
            function(stop) OpenMap(demo, stop) end, "demo")
        if not demo.planning.demoBadge then
            demo.planning.demoBadge = Label(demo.planning, L.DemoBadge)
            demo.planning.demoBadge:SetPoint("BOTTOMLEFT", demo.planning, "TOPLEFT", 0, 5)
        end
    end)
    demo.controls.map = Button(L.Map, 218, 60, function() MapQuest(demo, demo.model.activeQuestID) end)
    demo.controls.shot = Button(L.DemoScreenshot, 18, 20, function() demo.controls:Hide() if GameTooltip then GameTooltip:Hide() end end)
    demo.controls.stop = Button(L.DemoStop, 218, 20, Mode.Stop)
    current = demo
    if addon.UI.ToolHub then addon.UI.ToolHub.Hide() end
    live:Hide() live.navigation:Hide()
    local ok, rendered = pcall(Render, demo)
    if not ok or not rendered then
        Mode.Stop()
        print("FQN | " .. L.DemoDataMissing)
        return false
    end
    demo.controls:Show()
    print("FQN | " .. L.DemoHelp)
    return true
end
function Mode.Command(command, settings, live, onStop)
    if command == "off" then Mode.Stop()
    elseif command == "shot" and current then current.controls.shot:Click()
    elseif command == "map" and current then current.controls.map:Click()
    elseif command == "plan" and current then current.controls.plan:Click()
    elseif command == "next" and current then current.controls.scene:Click()
    elseif command == "" or command == "on" or command == "barrens" or command == "elwynn" then
        Mode.Open(settings, live, onStop, (command == "barrens" or command == "elwynn") and command or nil)
    else print("FQN | " .. L.DemoHelp) end
end
