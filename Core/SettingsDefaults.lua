local _, addon = ...
-- Normalizes and migrates saved settings. Pure: no frames, no game state, so every
-- rule is unit-testable. Existing players keep their values; new keys get defaults.
local Defaults = {}
addon.SettingsDefaults = Defaults

local function Finite(value) return type(value) == "number" and math.abs(value) < math.huge end
local function On(value) return value ~= false end
local function Off(value) return value == true end

local function RowCount(value, default)
    if type(value) ~= "number" or not (value >= 2 and value <= 5) then return default end
    return math.floor(value)
end

-- limits: DEFAULT_OPACITY, DEFAULT_OFFER_RADIUS, MAX_OFFER_RADIUS.
-- isNew: true when no saved settings existed (fresh install).
function Defaults.Normalize(settings, limits, isNew)
    if settings.language ~= "deDE" and settings.language ~= "enUS" then settings.language = "auto" end
    settings.showUpdateNotes = On(settings.showUpdateNotes)
    settings.x = Finite(settings.x) and settings.x or 0
    settings.y = Finite(settings.y) and settings.y or 140
    if settings.displayMode ~= "full" and settings.displayMode ~= "arrow" and settings.displayMode ~= "off" then
        settings.displayMode = settings.hidden == true and "off" or "full"
    end
    addon.TrackerPresentation.MigrateNavigatorView(settings)
    settings.detailMode = settings.detailMode == "compact" and "compact" or "detailed"
    settings.highContrast = Off(settings.highContrast)
    settings.theme = ({graphite = true, parchment = true, midnight = true})[settings.theme] and settings.theme or "graphite"
    settings.reducedColors = Off(settings.reducedColors)
    settings.repeatablePolicy = addon.RepeatablePolicy.Mode(settings.repeatablePolicy)
    settings.navigatorLayout = settings.navigatorLayout == "lists" and "lists" or "guided"
    for _, key in ipairs({"showTravelPreparation", "quietNavigation", "showRouteMarkers", "showQuestRewards",
        "showRewardComparison", "showTravelTime", "adaptiveLayout", "showLevelHints", "useQuestieKillLocations",
        "showQuestieOffers", "showDirectionArrow", "showScreenArrow", "showQuestXP", "difficultyWords",
        "rememberNavigation", "showRouteLine", "iconLabels"}) do
        settings[key] = On(settings[key])
    end
    for _, key in ipairs({"areaOverviewExpanded", "allowTrackerResize", "lockTrackerPosition",
        "lockNavigationPosition", "groupSync"}) do
        settings[key] = Off(settings[key])
    end
    local font = settings.fontPercent
    settings.fontPercent = type(font) == "number" and font >= 80 and font <= 140 and font or 100
    settings.acceptedRows = RowCount(settings.acceptedRows, 2)
    settings.offerRows = RowCount(settings.offerRows, 3)
    settings.trackerMaxHeight = addon.TrackerPresentation.HeightLimit(settings.trackerMaxHeight)
    settings.includeElite, settings.currentZoneOnly, settings.showTurnInStar, settings.sortByDistance = nil, nil, nil, nil
    local radius = settings.questieOfferRadius
    settings.questieOfferRadius = type(radius) == "number" and radius >= 50
        and radius <= limits.MAX_OFFER_RADIUS and radius or limits.DEFAULT_OFFER_RADIUS
    if settings.displayMode == "arrow" and not settings.showDirectionArrow then settings.displayMode = "full" end
    settings.hidden = settings.displayMode ~= "full"
    if not (Finite(settings.screenArrowX) and Finite(settings.screenArrowY)) then
        settings.screenArrowX, settings.screenArrowY = nil, nil
    end
    local opacity = settings.opacityPercent
    settings.opacityPercent = type(opacity) == "number" and opacity >= 0 and opacity <= 100 and opacity or limits.DEFAULT_OPACITY
    -- Experience level: fresh installs start simple; existing players keep their choice.
    if settings.simpleNavigator == nil then settings.simpleNavigator = isNew == true end
    settings.simpleNavigator = settings.simpleNavigator == true
    if not (Finite(settings.hubX) and Finite(settings.hubY)) then settings.hubX, settings.hubY = nil, nil end
    return settings
end

local characterTables = {"questNotes", "targetCorrections", "laterQuests", "knownVendors", "hiddenOffers",
    "accessPoints", "confirmedFlightPoints", "flightRoutes"}

function Defaults.NormalizeCharacter(character)
    for _, key in ipairs(characterTables) do
        if type(character[key]) ~= "table" then character[key] = {} end
    end
    return character
end
