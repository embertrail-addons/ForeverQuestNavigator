local _, addon = ...
local L = addon.L
addon.SettingsController = {}

function addon.SettingsController.Register(context)
    local settings = context.settings
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
    addon.SettingsController.catalog = catalog
    local basic = { language = true, detailMode = true, showScreenArrow = true, showQuestXP = true, opacityPercent = true }
    local ranges = { questieOfferRadius = {50, MAX_OFFER_RADIUS, 50}, opacityPercent = {0, 100, 5},
        fontPercent = {80, 140, 10}, acceptedRows = {2, 5, 1}, offerRows = {2, 5, 1} }
    local function RegisterSetting(owner, variable, key, db, kind, name, default)
        local control = Settings.RegisterAddOnSetting(owner, variable, key, db, kind, name, default)
        local entry = { key = key, name = name, control = control, basic = basic[key],
            kind = kind == Settings.VarType.Boolean and "boolean" or kind }
        if key == "language" then entry.choices = {"auto", "deDE", "enUS"} end
        if key == "detailMode" then entry.choices = {"detailed", "compact"} end
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
        Settings.RegisterInitializer(category, CreateSettingsListSectionHeaderInitializer(name))
    end
    Section(L.SettingsGeneral)
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
    local quiet = RegisterSetting(category, "FOREVERQUESTNAVIGATOR_QUIET_NAVIGATION",
        "quietNavigation", settings, Settings.VarType.Boolean, L.QuietNavigation, true)
    quiet:SetValueChangedCallback(function() UpdateDirectionTicker() ScheduleRefresh() end)
    Checkbox(category, quiet, L.QuietNavigationHelp)
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
        addon.UI.Theme.Apply(settings.highContrast)
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
    Settings.RegisterInitializer(category, CreateSettingsButtonInitializer(L.AppearancePreview, L.AppearancePreview,
        function() addon.ShowAppearancePreview(settings) end, L.AppearancePreviewHelp, true))
    local questXP = RegisterSetting(category, "FOREVERQUESTNAVIGATOR_SHOW_QUEST_XP",
        "showQuestXP", settings, Settings.VarType.Boolean, L.ShowQuestXP, true)
    questXP:SetValueChangedCallback(function() ScheduleRefresh() addon.RefreshAppearancePreview() end)
    Checkbox(category, questXP, L.ShowQuestXPHelp)

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
    local appearance = CreateSettingsButtonInitializer(L.ResetAppearance, L.ResetAppearance, function()
        detailMode:SetValue("detailed")
        contrast:SetValue(false)
        opacity:SetValue(DEFAULT_OPACITY)
        font:SetValue(100)
        acceptedRows:SetValue(2)
        offerRows:SetValue(3)
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
