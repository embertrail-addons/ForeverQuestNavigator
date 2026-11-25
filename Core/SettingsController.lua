local _, addon = ...
local L = addon.L
addon.SettingsController = {}

function addon.SettingsController.Register(context)
    local settings = context.settings
    addon.SettingsController.settings = settings
    local ShowSession = context.ShowSession
    local ShowAccessManager = context.ShowAccessManager
    local ShowNotepad = context.ShowNotepad
    local UpdateQuestieTicker = context.UpdateQuestieTicker
    local ScheduleRefresh = context.ScheduleRefresh
    local SetDisplayMode = context.SetDisplayMode
    local UpdateDirectionTicker = context.UpdateDirectionTicker
    local RestoreAvoidedObjectives = context.RestoreAvoidedObjectives
    local ShowDiagnostics = context.ShowDiagnostics
    local DEFAULT_OPACITY = context.DEFAULT_OPACITY
    local DEFAULT_OFFER_RADIUS = context.DEFAULT_OFFER_RADIUS
    local MAX_OFFER_RADIUS = context.MAX_OFFER_RADIUS
    local catalog, byControl = {}, {}
    local currentSection
    addon.SettingsController.catalog = catalog
    local basic = { language = true, detailMode = true, showScreenArrow = true, showQuestXP = true, opacityPercent = true,
        theme = true, navigatorView = true, repeatablePolicy = true, simpleNavigator = true, fontPercent = true,
        showQuestieOffers = true, iconLabels = true, difficultyWords = true, allGoals = true, showTargetMarks = true, nameplateMarks = true }
    local logicKeys = {repeatablePolicy=true, showQuestieOffers=true, questieOfferRadius=true, useQuestieKillLocations=true,
        rememberNavigation=true}
    local ranges = { questieOfferRadius = {50, MAX_OFFER_RADIUS, 50}, opacityPercent = {0, 100, 5},
        fontPercent = {80, 140, 10}, acceptedRows = {2, 5, 1}, offerRows = {2, 5, 1},
        trackerMaxHeight = {360, 1000, 20}, trackerWidth = {330, 640, 10} }
    local function RegisterSetting(owner, variable, key, db, kind, name, default)
        local control = Settings.RegisterAddOnSetting(owner, variable, key, db, kind, name, default)
        local entry = { key = key, name = name, control = control, basic = basic[key], section = currentSection,
            effect = logicKeys[key] and "logic" or "view",
            kind = kind == Settings.VarType.Boolean and "boolean" or kind }
        if key == "language" then entry.choices = {"auto", "deDE", "enUS"} end
        if key == "detailMode" then entry.choices = {"detailed", "compact"} end
        if key == "navigatorView" then entry.choices = {"goal", "all"} end
        if key == "theme" then entry.choices = {"graphite", "parchment", "midnight"} end
        if key == "repeatablePolicy" then entry.choices = {"level", "show", "hide"} end
        local range = ranges[key]
        if range then entry.minimum, entry.maximum, entry.step = unpack(range) end
        catalog[#catalog + 1], byControl[control] = entry, entry
        return control
    end
    local function Checkbox(owner, control, help)
        byControl[control].help = help
        return Settings.CreateCheckbox(owner, control, help)
    end
    local function Slider(owner, control, options, help)
        byControl[control].help = help
        return Settings.CreateSlider(owner, control, options, help)
    end
    local function Dropdown(owner, control, options, help)
        byControl[control].help = help
        return Settings.CreateDropdown(owner, control, options, help)
    end
    local category = Settings.RegisterVerticalLayoutCategory("Forever Quest Navigator")
    local function Section(name)
        currentSection = name
        Settings.RegisterInitializer(category, CreateSettingsListSectionHeaderInitializer(name))
    end
    Section(L.SettingsGeneral)
    local simple = RegisterSetting(category, "FOREVERQUESTNAVIGATOR_SIMPLE", "simpleNavigator", settings,
        Settings.VarType.Boolean, L.JourneySimple, false)
    simple:SetValueChangedCallback(ScheduleRefresh)
    Checkbox(category, simple, L.JourneySimpleHelp)
    local groupHints = RegisterSetting(category, "FOREVERQUESTNAVIGATOR_GROUP_HINTS", "groupQuestHints", settings,
        Settings.VarType.Boolean, L.AdventureGroupOn, false)
    groupHints:SetValueChangedCallback(ScheduleRefresh)
    Checkbox(category, groupHints, L.AdventureGroupHelp)
    local groupSync = RegisterSetting(category, "FOREVERQUESTNAVIGATOR_GROUP_SYNC", "groupSync", settings,
        Settings.VarType.Boolean, L.GroupSync, false)
    groupSync:SetValueChangedCallback(function(_, value)
        if not value then addon.GroupSync.Reset() else addon.GroupSync.MarkDirty() if addon.SyncGroup then addon.SyncGroup() end end
        ScheduleRefresh()
    end)
    Checkbox(category, groupSync, L.GroupSyncHelp)
    local difficultyWords = RegisterSetting(category, "FOREVERQUESTNAVIGATOR_DIFFICULTY_WORDS", "difficultyWords", settings,
        Settings.VarType.Boolean, L.AdventureDifficultyWords, true)
    difficultyWords:SetValueChangedCallback(ScheduleRefresh)
    Checkbox(category, difficultyWords, L.AdventureDifficultyHelp)
    local repeatables = RegisterSetting(category, "FOREVERQUESTNAVIGATOR_REPEATABLES", "repeatablePolicy", settings,
        Settings.VarType.String, L.RepeatablePolicy, "show")
    local repeatOptions = Settings.CreateControlTextContainer()
    for _, key in ipairs({"level", "show", "hide"}) do repeatOptions:Add(key, L["RepeatablePolicy_" .. key]) end
    repeatables:SetValueChangedCallback(ScheduleRefresh)
    Dropdown(category, repeatables, function() return repeatOptions:GetData() end, L.RepeatablePolicyHelp)
    Settings.RegisterInitializer(category, CreateSettingsButtonInitializer(L.QuestFinder, L.QuestFinder,
        function() addon.OpenWorkspace("finder") end, L.FinderHelp, true))
    Settings.RegisterInitializer(category, CreateSettingsButtonInitializer(L.MyTour, L.MyTour,
        function() addon.OpenWorkspace("tour") end, L.TourEditorHelp, true))
    Settings.RegisterInitializer(category, CreateSettingsButtonInitializer(L.ProblemReportTitle, L.ProblemReportTitle,
        function() addon.OpenProblemReport() end, L.ProblemReportPrivacy, true))
    local remember = RegisterSetting(category, "FOREVERQUESTNAVIGATOR_REMEMBER_NAVIGATION", "rememberNavigation", settings,
        Settings.VarType.Boolean, L.RememberNavigation, true)
    remember:SetValueChangedCallback(function() addon.ForgetRememberedNavigation() end)
    Checkbox(category, remember, L.RememberNavigationHelp)
    Settings.RegisterInitializer(category, CreateSettingsButtonInitializer(L.ChangeHistory, L.ChangeHistory,
        context.ShowHistory, L.UndoScope, true))
    Settings.RegisterInitializer(category, CreateSettingsButtonInitializer(L.LevelChangesTitle, L.LevelChangesTitle,
        context.ShowLevelChanges, L.LevelBetterHelp, true))
    Settings.RegisterInitializer(category, CreateSettingsButtonInitializer(L.FeedbackManager, L.FeedbackManager,
        context.ShowFeedback, L.FeedbackHelp, true))
    Settings.RegisterInitializer(category, CreateSettingsButtonInitializer(L.PlanningOverview, L.PlanningOverview,
        context.ShowPlanning, L.PlanningHelp, true))
    Settings.RegisterInitializer(category, CreateSettingsButtonInitializer(L.ZoneOverview, L.ZoneOverview,
        context.ShowZones, L.ZoneOverviewHelp, true))
    local language = RegisterSetting(category, "FOREVERQUESTNAVIGATOR_LANGUAGE",
        "language", settings, Settings.VarType.String, L.Language, "auto")
    local languageOptions = Settings.CreateControlTextContainer()
    languageOptions:Add("auto", L.LanguageAutomatic)
    languageOptions:Add("deDE", "Deutsch")
    languageOptions:Add("enUS", "English")
    language:SetValueChangedCallback(function() print(L.LanguageReload) end)
    Dropdown(category, language, function() return languageOptions:GetData() end, L.LanguageHelp)
    Settings.RegisterInitializer(category, CreateSettingsButtonInitializer(L.OpenSession, L.OpenSession,
        ShowSession, L.OpenSessionHelp, true))
    Settings.RegisterInitializer(category, CreateSettingsButtonInitializer(L.AccessManager, L.AccessManager,
        ShowAccessManager, L.AccessManagerHelp, true))
    Settings.RegisterInitializer(category, CreateSettingsButtonInitializer(L.QuestNotepad, L.QuestNotepad,
        ShowNotepad, L.NotepadIndependent, true))
    Settings.RegisterInitializer(category, CreateSettingsButtonInitializer(L.Introduction, L.Introduction,
        function() addon.ShowIntroduction(settings) end, L.IntroductionHelp, true))
    local updates = RegisterSetting(category, "FOREVERQUESTNAVIGATOR_UPDATE_NOTES", "showUpdateNotes", settings,
        Settings.VarType.Boolean, L.ShowUpdateNotes, true)
    Checkbox(category, updates, L.ShowUpdateNotesHelp)
    local function RefreshQuestieSettings()
        UpdateQuestieTicker()
        ScheduleRefresh()
    end
    Section(L.SettingsRecommendations)
    local levelHints = RegisterSetting(category, "FOREVERQUESTNAVIGATOR_LEVEL_HINTS", "showLevelHints", settings,
        Settings.VarType.Boolean, L.ShowLevelHints, true)
    levelHints:SetValueChangedCallback(function() if not settings.showLevelHints then addon.HideLevelNotice() end ScheduleRefresh() end)
    Checkbox(category, levelHints, L.LevelBetterHelp)
    local killLocations = RegisterSetting(category, "FOREVERQUESTNAVIGATOR_QUESTIE_KILL_LOCATIONS",
        "useQuestieKillLocations", settings, Settings.VarType.Boolean, L.KillLocations, true)
    killLocations:SetValueChangedCallback(RefreshQuestieSettings)
    Checkbox(category, killLocations,
        L.KillLocationsHelp)

    local nearbyOffers = RegisterSetting(category, "FOREVERQUESTNAVIGATOR_QUESTIE_NEARBY_OFFERS",
        "showQuestieOffers", settings, Settings.VarType.Boolean, L.Offers, true)
    nearbyOffers:SetValueChangedCallback(RefreshQuestieSettings)
    Checkbox(category, nearbyOffers,
        L.OffersHelp)

    local radius = RegisterSetting(category, "FOREVERQUESTNAVIGATOR_QUESTIE_OFFER_RADIUS",
        "questieOfferRadius", settings, Settings.VarType.Number, L.OfferRadius, DEFAULT_OFFER_RADIUS)
    local radiusOptions = Settings.CreateSliderOptions(50, MAX_OFFER_RADIUS, 50)
    radiusOptions:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(value)
        return ("%.0f yd"):format(value)
    end)
    radius:SetValueChangedCallback(ScheduleRefresh)
    Slider(category, radius, radiusOptions, L.OfferRadiusHelp)

    Section(L.SettingsNavigation)
    local travelTime = RegisterSetting(category, "FOREVERQUESTNAVIGATOR_TRAVEL_TIME", "showTravelTime", settings,
        Settings.VarType.Boolean, L.ShowTravelTime, true)
    travelTime:SetValueChangedCallback(ScheduleRefresh)
    Checkbox(category, travelTime, L.ShowTravelTimeHelp)
    local routeMarkers = RegisterSetting(category, "FOREVERQUESTNAVIGATOR_ROUTE_MARKERS",
        "showRouteMarkers", settings, Settings.VarType.Boolean, L.RouteMarkers, true)
    routeMarkers:SetValueChangedCallback(context.UpdateMapMarker)
    Checkbox(category, routeMarkers, L.RouteMarkersHelp)
    local minimapArrow = RegisterSetting(category, "FOREVERQUESTNAVIGATOR_MINIMAP_ARROW",
        "minimapArrow", settings, Settings.VarType.Boolean, L.MinimapArrow, false)
    minimapArrow:SetValueChangedCallback(function() context.UpdateDirectionTicker() end)
    Checkbox(category, minimapArrow, L.MinimapArrowHelp)
    local routeLine = RegisterSetting(category, "FOREVERQUESTNAVIGATOR_ROUTE_LINE",
        "showRouteLine", settings, Settings.VarType.Boolean, L.RouteLine, true)
    routeLine:SetValueChangedCallback(function(_, value)
        addon.CanvasMarkers.showLine = value ~= false
        context.UpdateMapMarker()
    end)
    Checkbox(category, routeLine, L.RouteLineHelp)
    function addon.ToggleRouteLine() routeLine:SetValue(not (settings.showRouteLine ~= false)) end
    local quiet = RegisterSetting(category, "FOREVERQUESTNAVIGATOR_QUIET_NAVIGATION",
        "quietNavigation", settings, Settings.VarType.Boolean, L.QuietNavigation, true)
    quiet:SetValueChangedCallback(function() UpdateDirectionTicker() ScheduleRefresh() end)
    Checkbox(category, quiet, L.QuietNavigationHelp)
    local quietInstances = RegisterSetting(category, "FOREVERQUESTNAVIGATOR_QUIET_INSTANCES",
        "quietInstances", settings, Settings.VarType.Boolean, L.QuietInstances, true)
    quietInstances:SetValueChangedCallback(function() ScheduleRefresh() end)
    Checkbox(category, quietInstances, L.QuietInstancesHelp)
    local preparation = RegisterSetting(category, "FOREVERQUESTNAVIGATOR_TRAVEL_PREPARATION",
        "showTravelPreparation", settings, Settings.VarType.Boolean, L.TravelPreparation, true)
    preparation:SetValueChangedCallback(ScheduleRefresh)
    Checkbox(category, preparation, L.TravelPreparationHelp)
    local direction = RegisterSetting(category, "FOREVERQUESTNAVIGATOR_SHOW_DIRECTION_ARROW",
        "showDirectionArrow", settings, Settings.VarType.Boolean, L.DirectionArrow, true)
    direction:SetValueChangedCallback(function()
        if not settings.showDirectionArrow and settings.displayMode == "arrow" then
            SetDisplayMode("full")
        else
            UpdateDirectionTicker()
        end
    end)
    Checkbox(category, direction, L.DirectionArrowHelp)

    local screenArrow = RegisterSetting(category, "FOREVERQUESTNAVIGATOR_SHOW_SCREEN_ARROW",
        "showScreenArrow", settings, Settings.VarType.Boolean, L.ScreenArrow, true)
    screenArrow:SetValueChangedCallback(UpdateDirectionTicker)
    Checkbox(category, screenArrow, L.ScreenArrowHelp)
    local lockNavigation = RegisterSetting(category, "FOREVERQUESTNAVIGATOR_LOCK_NAVIGATION_POSITION",
        "lockNavigationPosition", settings, Settings.VarType.Boolean, L.LockNavigationPosition, false)
    Checkbox(category, lockNavigation, L.LockNavigationPositionHelp)
    local restoreObjectives = CreateSettingsButtonInitializer(L.RestoreAvoidedObjectives, L.RestoreAvoidedObjectives,
        RestoreAvoidedObjectives, L.RestoreAvoidedObjectivesHelp, true)
    Settings.RegisterInitializer(category, restoreObjectives)

    Section(L.SettingsAppearance)
    local function AppearanceChanged()
        addon.UI.Theme.Apply(settings.highContrast, settings.theme, settings.reducedColors)
        context.getTracker():UpdateOpacity()
        context.getTracker():UpdateListSettings()
        addon.RefreshAppearancePreview()
        ScheduleRefresh()
    end
    local theme = RegisterSetting(category, "FOREVERQUESTNAVIGATOR_THEME", "theme", settings,
        Settings.VarType.String, L.Design, "graphite")
    local themeOptions = Settings.CreateControlTextContainer()
    for _, key in ipairs({"graphite", "parchment", "midnight"}) do themeOptions:Add(key, L["Design_" .. key]) end
    theme:SetValueChangedCallback(AppearanceChanged)
    Dropdown(category, theme, function() return themeOptions:GetData() end, L.DesignHelp)
    local reduced = RegisterSetting(category, "FOREVERQUESTNAVIGATOR_REDUCED_COLORS", "reducedColors", settings,
        Settings.VarType.Boolean, L.ReducedColors, false)
    reduced:SetValueChangedCallback(AppearanceChanged)
    Checkbox(category, reduced, L.ReducedColorsHelp)
    local adaptive = RegisterSetting(category, "FOREVERQUESTNAVIGATOR_ADAPTIVE_LAYOUT", "adaptiveLayout", settings,
        Settings.VarType.Boolean, L.AdaptiveLayout, true)
    adaptive:SetValueChangedCallback(function() context.getTracker():UpdateListSettings() ScheduleRefresh() end)
    Checkbox(category, adaptive, L.AdaptiveLayoutHelp)
    local rewards = RegisterSetting(category, "FOREVERQUESTNAVIGATOR_QUEST_REWARDS",
        "showQuestRewards", settings, Settings.VarType.Boolean, L.ShowQuestRewards, true)
    rewards:SetValueChangedCallback(ScheduleRefresh)
    Checkbox(category, rewards, L.ShowQuestRewardsHelp)
    local comparison = RegisterSetting(category, "FOREVERQUESTNAVIGATOR_REWARD_COMPARISON", "showRewardComparison", settings,
        Settings.VarType.Boolean, L.ShowRewardComparison, true)
    comparison:SetValueChangedCallback(ScheduleRefresh)
    Checkbox(category, comparison, L.ShowRewardComparisonHelp)
    Settings.RegisterInitializer(category, CreateSettingsButtonInitializer(L.AppearanceProfiles, L.AppearanceProfiles,
        context.ShowProfiles, L.ProfilesHelp, true))
    local contrast = RegisterSetting(category, "FOREVERQUESTNAVIGATOR_HIGH_CONTRAST",
        "highContrast", settings, Settings.VarType.Boolean, L.HighContrast, false)
    contrast:SetValueChangedCallback(function()
        addon.UI.Theme.Apply(settings.highContrast, settings.theme, settings.reducedColors)
        context.getTracker():UpdateOpacity()
        context.getTracker():UpdateListSettings()
        addon.RefreshAppearancePreview()
        ScheduleRefresh()
    end)
    Checkbox(category, contrast, L.HighContrastHelp)
    local detailMode = RegisterSetting(category, "FOREVERQUESTNAVIGATOR_DETAIL_MODE",
        "detailMode", settings, Settings.VarType.String, L.DetailMode, "detailed")
    local detailOptions = Settings.CreateControlTextContainer()
    detailOptions:Add("detailed", L.DetailDetailed)
    detailOptions:Add("compact", L.DetailCompact)
    detailMode:SetValueChangedCallback(function()
        context.getTracker():UpdateListSettings()
        addon.RefreshAppearancePreview()
    end)
    Dropdown(category, detailMode, function() return detailOptions:GetData() end, L.DetailModeHelp)
    local view = RegisterSetting(category, "FOREVERQUESTNAVIGATOR_NAVIGATOR_VIEW", "navigatorView", settings,
        Settings.VarType.String, L.NavigatorView, "all")
    local viewOptions = Settings.CreateControlTextContainer()
    for _, key in ipairs({"goal", "all"}) do viewOptions:Add(key, L["NavigatorView_" .. key]) end
    view:SetValueChangedCallback(function() context.getTracker():SetNavigatorView(settings.navigatorView) end)
    Dropdown(category, view, function() return viewOptions:GetData() end, L.NavigatorViewHint)
    local maximum = RegisterSetting(category, "FOREVERQUESTNAVIGATOR_MAX_HEIGHT", "trackerMaxHeight", settings,
        Settings.VarType.Number, L.NavigatorMaxHeight, 600)
    maximum:SetValueChangedCallback(function() context.getTracker():UpdateNavigatorLayout() end)
    Slider(category, maximum, Settings.CreateSliderOptions(360, 1000, 20), L.NavigatorMaxHeightHelp)
    local width = RegisterSetting(category, "FOREVERQUESTNAVIGATOR_WIDTH", "trackerWidth", settings,
        Settings.VarType.Number, L.NavigatorWidth, 352)
    width:SetValueChangedCallback(function()
        context.getTracker():SetWidth(settings.trackerWidth)
        context.getTracker():UpdateListSettings() addon.RefreshAppearancePreview()
    end)
    Slider(category, width, Settings.CreateSliderOptions(330, 640, 10), L.NavigatorWidthHelp)
    Settings.RegisterInitializer(category, CreateSettingsButtonInitializer(L.AppearancePreview, L.AppearancePreview,
        function() addon.ShowAppearancePreview(settings, catalog) end, L.AppearancePreviewHelp, true))
    local questXP = RegisterSetting(category, "FOREVERQUESTNAVIGATOR_SHOW_QUEST_XP",
        "showQuestXP", settings, Settings.VarType.Boolean, L.ShowQuestXP, true)
    questXP:SetValueChangedCallback(function() ScheduleRefresh() addon.RefreshAppearancePreview() end)
    Checkbox(category, questXP, L.ShowQuestXPHelp)
    local iconLabels = RegisterSetting(category, "FOREVERQUESTNAVIGATOR_ICON_LABELS",
        "iconLabels", settings, Settings.VarType.Boolean, L.IconLabels, true)
    iconLabels:SetValueChangedCallback(function(_, value) addon.UI.iconLabels = value ~= false ScheduleRefresh() end)
    Checkbox(category, iconLabels, L.IconLabelsHelp)
    local allGoals = RegisterSetting(category, "FOREVERQUESTNAVIGATOR_ALL_GOALS",
        "allGoals", settings, Settings.VarType.Boolean, L.AllGoals, true)
    allGoals:SetValueChangedCallback(ScheduleRefresh)
    Checkbox(category, allGoals, L.AllGoalsHelp)
    local targetMarks = RegisterSetting(category, "FOREVERQUESTNAVIGATOR_TARGET_MARKS",
        "showTargetMarks", settings, Settings.VarType.Boolean, L.TargetMarkTitle, false)
    targetMarks:SetValueChangedCallback(function(_, value) addon.ToggleTargetMarks(value == true) end)
    Checkbox(category, targetMarks, L.TargetMarkHelp)
    local nameplateMarks = RegisterSetting(category, "FOREVERQUESTNAVIGATOR_NAMEPLATE_MARKS",
        "nameplateMarks", settings, Settings.VarType.Boolean, L.NameplateMarks, true)
    nameplateMarks:SetValueChangedCallback(function(_, value) addon.NameplateMarks.SetEnabled(value) end)
    Checkbox(category, nameplateMarks, L.NameplateMarksHelp)

    local opacity = RegisterSetting(category, "FOREVERQUESTNAVIGATOR_TRACKER_OPACITY",
        "opacityPercent", settings, Settings.VarType.Number, L.Opacity, DEFAULT_OPACITY)
    local opacityOptions = Settings.CreateSliderOptions(0, 100, 5)
    opacityOptions:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(value)
        return ("%.0f%%"):format(value)
    end)
    opacity:SetValueChangedCallback(function() context.getTracker():UpdateOpacity() addon.RefreshAppearancePreview() end)
    Slider(category, opacity, opacityOptions, L.OpacityHelp)
    local resize = RegisterSetting(category, "FOREVERQUESTNAVIGATOR_ALLOW_TRACKER_RESIZE",
        "allowTrackerResize", settings, Settings.VarType.Boolean, L.AllowTrackerResize, false)
    resize:SetValueChangedCallback(function() context.getTracker():UpdateResizeGrip() end)
    Checkbox(category, resize, L.AllowTrackerResizeHelp)
    local lockTracker = RegisterSetting(category, "FOREVERQUESTNAVIGATOR_LOCK_TRACKER_POSITION",
        "lockTrackerPosition", settings, Settings.VarType.Boolean, L.LockTrackerPosition, false)
    Checkbox(category, lockTracker, L.LockTrackerPositionHelp)
    local font = RegisterSetting(category, "FOREVERQUESTNAVIGATOR_FONT_PERCENT",
        "fontPercent", settings, Settings.VarType.Number, L.FontSize, 100)
    font:SetValueChangedCallback(function() context.getTracker():UpdateFontSize() addon.RefreshAppearancePreview() end)
    local fontOptions = Settings.CreateSliderOptions(80, 140, 10)
    fontOptions:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(value)
        return ("%.0f%%"):format(value)
    end)
    Slider(category, font, fontOptions, L.FontSizeHelp)
    local function RegisterRowCount(key, variable, name, defaultValue)
        local count = RegisterSetting(category, variable, key, settings, Settings.VarType.Number, name, defaultValue)
        count:SetValueChangedCallback(function() context.getTracker():UpdateListSettings() end)
        local options = Settings.CreateSliderOptions(2, 5, 1)
        options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(value) return tostring(value) end)
        Slider(category, count, options, L.ListRowsHelp)
        return count
    end
    local acceptedRows = RegisterRowCount("acceptedRows", "FOREVERQUESTNAVIGATOR_ACCEPTED_ROWS", L.AcceptedRows, 2)
    local offerRows = RegisterRowCount("offerRows", "FOREVERQUESTNAVIGATOR_OFFER_ROWS", L.OfferRows, 3)
    local reset = CreateSettingsButtonInitializer(L.ResetPositions, L.ResetPositions, function()
        context.getTracker():ResetPositions()
    end, L.ResetPositionsHelp, true)
    Settings.RegisterInitializer(category, reset)
    Settings.RegisterInitializer(category, CreateSettingsButtonInitializer(L.ArrangeUI, L.ArrangeUI,
        function() context.getTracker():ArrangeUI() end, L.ArrangeHelp, true))
    local appearance = CreateSettingsButtonInitializer(L.ResetAppearance, L.ResetAppearance, function()
        detailMode:SetValue("detailed")
        contrast:SetValue(false)
        opacity:SetValue(DEFAULT_OPACITY)
        font:SetValue(100)
        acceptedRows:SetValue(2)
        offerRows:SetValue(3)
        maximum:SetValue(600) view:SetValue("all") width:SetValue(352)
        resize:SetValue(false)
        lockTracker:SetValue(false)
        lockNavigation:SetValue(false)
        context.getTracker():ResetAppearance()
        ScheduleRefresh()
    end, L.ResetAppearanceHelp, true)
    Settings.RegisterInitializer(category, appearance)
    Section(L.SettingsDiagnostics)
    Settings.RegisterInitializer(category, CreateSettingsButtonInitializer(L.ExportFixture, L.ExportFixture,
        context.ShowFixture, L.FixtureHelp, true))
    Settings.RegisterInitializer(category, CreateSettingsButtonInitializer(L.OpenDiagnostics, L.OpenDiagnostics,
        ShowDiagnostics, L.OpenDiagnosticsHelp, true))
    Settings.RegisterAddOnCategory(category)
    return category
end
