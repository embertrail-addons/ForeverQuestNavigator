local addonName = "ForeverQuestNavigator"
local testsPassed = 0

local function equal(actual, expected)
    assert(actual == expected, ("Expected %s, got %s"):format(tostring(expected), tostring(actual)))
end

local function near(actual, expected)
    assert(math.abs(actual - expected) < 0.000001, ("Expected about %s, got %s"):format(expected, actual))
end

local function test(name, run)
    run()
    testsPassed = testsPassed + 1
    print("PASS " .. name)
end

local function loadAddon(env, includeBootstrap)
    local addon = {}
    local interface
    for line in io.lines(addonName .. ".toc") do
        interface = interface or line:match("^## Interface: (%d+)$")
        if line:match("%.lua$") then
            local path = line:gsub("\\", "/")
            local chunk = assert(loadfile(path))
            if path ~= "Core/Bootstrap.lua" or includeBootstrap then
                setfenv(chunk, env)(addonName, addon)
            end
        end
    end
    equal(interface, "16001")
    return addon
end

local addon = loadAddon(getfenv(), false)

test("Outing order keeps the usual recommendation when savings are small or a closer quest is too high", function()
    local map = { GetMapWorldSize = function() return 1000, 1000 end }
    local ranked = { { id = 1, level = 10 }, { id = 2, level = 13 } }
    local measurements = {
        [1] = { yards = 600, marker = { mapID = 10, x = 0.8, y = 0.5 } },
        [2] = { yards = 570, marker = { mapID = 10, x = 0.77, y = 0.5 } },
    }
    local plan = addon.QuestRoute.PlanOuting(map, ranked, measurements, 10)
    equal(plan.stops[1].id, 1)
    equal(plan.saving, 0)
    ranked[2].level = 14
    equal(addon.QuestRoute.PlanOuting(map, ranked, measurements, 10), nil)
end)

test("Quest log reads accepted player-facing quests and quest state", function()
    local entries = {
        { questID = 0, isHeader = true, isCollapsed = true },
        { questID = 10, title = "Collect supplies", level = 8 },
        { questID = 11, isHidden = true },
        { questID = 12, isInternalOnly = true },
        { questID = 13, isTask = true },
        { questID = 14 },
        [8] = { questID = 15 },
        [9] = { questID = 16 },
    }
    local quests = addon.QuestLog.Read({
        GetNumQuestLogEntries = function() return 9, 7 end,
        GetInfo = function(index) return entries[index] end,
        IsOnQuest = function(id) return id ~= 14 end,
        IsComplete = function(id) return id == 10 end,
        IsFailed = function(id) return id == 15 end,
        IsQuestDisabledForSession = function(id) return id == 16 end,
    })
    equal(#quests, 3)
    equal(quests[1].id, 10)
    equal(quests[1].title, "Collect supplies")
    equal(quests[1].level, 8)
    equal(quests[1].readyToTurnIn, true)
    equal(quests[2].failed, true)
    equal(quests[3].disabled, true)
    equal(addon.QuestLog.Read({}), nil)
end)

test("Ranking uses level then quest ID and excludes failed and disabled quests", function()
    local quests = {
        { id = 1, level = 0 },
        { id = 20, level = 19 },
        { id = 30, level = 18 },
        { id = 4, level = 18, readyToTurnIn = true },
        { id = 5, level = 2, failed = true },
        { id = 6, level = 2, disabled = true },
        { id = 7 },
    }
    local ranked = addon.QuestPrioritizer.Rank(quests)
    equal(#ranked, 5)
    equal(ranked[1].id, 4)
    equal(ranked[2].id, 30)
    equal(ranked[3].id, 20)
    equal(ranked[4].id, 1)
    equal(ranked[5].id, 7)
    equal(quests[1].id, 1)
end)

test("Ranking includes elite quests and respects skips", function()
    local quests = {
        { id = 1, level = 5, elite = true, readyToTurnIn = true },
        { id = 2, level = 6 },
        { id = 3, level = 7, elite = true },
        { id = 4, level = 8, elite = false },
    }
    equal(addon.QuestPrioritizer.Rank(quests)[1].id, 1)
    local ranked = addon.QuestPrioritizer.Rank(quests, { [1] = true, [2] = true })
    equal(#ranked, 2)
    equal(ranked[1].id, 3)
end)

local mapType = { Continent = 2, Zone = 3, Dungeon = 4, Micro = 5 }

test("Local quest markers cover the current subzone and its zone, without continent markers", function()
    local playerMapID = 11
    local maps = {
        [1] = { mapType = mapType.Continent },
        [10] = { mapType = mapType.Zone, name = "Westfall", parentMapID = 1 },
        [11] = { mapType = mapType.Micro, parentMapID = 10 },
        [12] = { mapType = mapType.Dungeon, name = "Deadmines", parentMapID = 10 },
        [13] = { mapType = mapType.Micro, parentMapID = 13 },
    }
    local mapAPI = {
        GetBestMapForUnit = function(unit)
            equal(unit, "player")
            return playerMapID
        end,
        GetMapInfo = function(id) return maps[id] end,
    }
    local questAPI = { GetQuestsOnMap = function(id)
        assert(id ~= 1, "Continent markers do not imply a local quest")
        return ({
            [10] = { { questID = 5, x = 0.3, y = 0.4 }, { questID = 6, isMapIndicatorQuest = true } },
            [11] = { { questID = 7 } },
        })[id]
    end }

    local localQuests, name = addon.QuestLocation.GetLocalQuestMarkers(mapAPI, questAPI, mapType)
    equal(name, "Westfall")
    equal(localQuests[5][1].mapID, 10)
    equal(localQuests[5][1].x, 0.3)
    equal(localQuests[6], nil)
    equal(#localQuests[7], 0)

    playerMapID = 12
    local dungeonQuests = addon.QuestLocation.GetLocalQuestMarkers(mapAPI, questAPI, mapType)
    equal(next(dungeonQuests), nil)
    for _, id in ipairs({ 0, 1, 13 }) do
        playerMapID = id
        equal(addon.QuestLocation.GetLocalQuestMarkers(mapAPI, questAPI, mapType), nil)
    end
    equal(addon.QuestLocation.GetLocalQuestMarkers(mapAPI, nil, mapType), nil)
end)

test("Distances use the closest marker and scale each axis in yards", function()
    local lookups = {}
    local api = {
        GetPlayerMapPosition = function(id, unit)
            equal(unit, "player")
            lookups[id] = (lookups[id] or 0) + 1
            if id == 99 then return { x = 0, y = 0 } end
            return { x = 0.25, y = 0.25 }
        end,
        GetMapWorldSize = function(id)
            if id == 77 then return 1000, 0 end
            return 1000, 500
        end,
    }
    local markers = {
        [1] = { { mapID = 10, x = 0.75, y = 0.75 }, { mapID = 10, x = 0.55, y = 0.65 } },
        [2] = { { mapID = 10, x = 0.25, y = 0.25 } },
        [3] = { { mapID = 99, x = 0.25, y = 0.25 } },
        [4] = { { mapID = 77, x = 0.25, y = 0.25 } },
    }
    local measurements = addon.QuestLocation.MeasureQuests(api, markers, { 1, 2, 3, 4, 5 })
    equal(math.floor(measurements[1].yards + 0.5), 361)
    equal(measurements[2].yards, 0)
    equal(measurements[3], nil)
    equal(measurements[4], nil)
    equal(measurements[5], nil)
    equal(lookups[10], 1)
    near(measurements[1].east, 300 / measurements[1].yards)
    near(measurements[1].north, -200 / measurements[1].yards)
    equal(measurements[2].east, nil)
end)

test("Direction rotates with the character and handles unavailable facing", function()
    local east = { east = 1, north = 0 }
    local right, forward = addon.QuestLocation.GetRelativeDirection(east, 0)
    near(right, 1)
    near(forward, 0)
    right, forward = addon.QuestLocation.GetRelativeDirection(east, math.pi / 2)
    near(right, 0)
    near(forward, -1)
    right, forward = addon.QuestLocation.GetRelativeDirection(east, 3 * math.pi / 2)
    near(right, 0)
    near(forward, 1)
    equal(addon.QuestLocation.GetRelativeDirection(east, nil), nil)
    equal(addon.QuestLocation.GetRelativeDirection(east, math.huge), nil)
    equal(addon.QuestLocation.GetRelativeDirection(nil, 0), nil)
end)

test("Ranking with a zone excludes remote and unmapped quests regardless of level", function()
    local quests = { { id = 1, level = 3 }, { id = 2, level = 5 }, { id = 3, level = 9 } }
    local ranked = addon.QuestPrioritizer.Rank(quests, nil, { [3] = true, [99] = true })
    equal(#ranked, 1)
    equal(ranked[1].id, 3)
    equal(#addon.QuestPrioritizer.Rank(quests, nil, {}), 0)
    equal(addon.QuestPrioritizer.Rank(quests)[1].id, 1)
end)

test("Distance sorting keeps unknown quests last and uses a margin to switch", function()
    local quests = { { id = 1 }, { id = 2 }, { id = 3 }, { id = 4 } }
    local measurements = { [2] = { yards = 120 }, [3] = { yards = 100 } }
    local ranked, previous = addon.QuestPrioritizer.RankByDistance(quests, measurements)
    equal(ranked[1].id, 3)
    equal(ranked[2].id, 2)
    equal(ranked[3].id, 1)
    equal(ranked[4].id, 4)

    measurements[2].yards = 90
    ranked, previous = addon.QuestPrioritizer.RankByDistance(quests, measurements, previous)
    equal(ranked[1].id, 3)
    measurements[2].yards = 75
    ranked, previous = addon.QuestPrioritizer.RankByDistance(quests, measurements, previous)
    equal(ranked[1].id, 2)

    measurements[2] = nil
    ranked, previous = addon.QuestPrioritizer.RankByDistance(quests, measurements, previous)
    equal(ranked[1].id, 3)
    equal(ranked[2].id, 1)
    equal(ranked[3].id, 2)
    equal(#previous, 1)

    local grouped = { [1] = { yards = 100 }, [2] = { yards = 88 }, [3] = { yards = 76 } }
    ranked = addon.QuestPrioritizer.RankByDistance(quests, grouped, quests)
    equal(ranked[1].id, 2)
end)

test("High-level quests rank behind attainable quests despite a shorter distance", function()
    equal(addon.QuestPrioritizer.IsHighLevel({ level = 37 }, 34), false)
    equal(addon.QuestPrioritizer.IsHighLevel({ level = 38 }, 34), true)
    local crown = { id = 1, level = 39 }
    local goldir = { id = 2, level = 36 }
    local hammer = { id = 3, level = 32 }
    local quests = { hammer, goldir, crown }
    local distances = { [1] = { yards = 386 }, [2] = { yards = 786 }, [3] = { yards = 2146 } }
    local ranked = addon.QuestPrioritizer.RankByDistance(quests, distances, { crown, goldir, hammer }, 34)
    equal(ranked[1], goldir)
    equal(ranked[2], hammer)
    equal(ranked[3], crown)
    crown.readyToTurnIn = true
    ranked = addon.QuestPrioritizer.RankByDistance(quests, distances, nil, 34)
    equal(ranked[1], crown)
end)

test("Objective text skips finished and blank objectives and handles missing data", function()
    local api = {
        GetQuestObjectives = function(id)
            equal(id, 10)
            return {
                { text = "Wolves slain: 8/8", finished = true },
                { text = "", finished = false },
                { text = "Supplies collected: 2/6", finished = false },
            }
        end,
    }
    equal(addon.QuestLog.GetObjectiveText(api, 10), "Supplies collected: 2/6")
    equal(addon.QuestLog.GetObjectiveText({ GetQuestObjectives = function() end }, 10), nil)
    equal(addon.QuestLog.GetObjectiveText({}, 10), nil)
end)

test("Questie status reports missing, unloaded and loaded states", function()
    local missing = addon.ReadQuestieStatus({
        IsAddOnLoaded = function() return false, false end,
        DoesAddOnExist = function() return false end,
    })
    equal(missing, "Not installed")

    local loaded = false
    local api = {
        IsAddOnLoaded = function(name) equal(name, "Questie"); return true, loaded end,
        DoesAddOnExist = function(name) equal(name, "Questie"); return true end,
    }
    equal(addon.ReadQuestieStatus(api), "Not loaded")
    loaded = true
    equal(addon.ReadQuestieStatus(api), "Loaded")
    equal(addon.ReadQuestieStatus(nil), "Unknown")
end)

local function noOp() end

local function mockUI()
    local frames = {}
    local methods = {}
    for _, method in ipairs({
        "SetSize", "SetPoint", "SetClampedToScreen", "SetMovable", "SetBackdrop", "SetBackdropColor",
        "EnableMouse", "RegisterForDrag", "StartMoving", "StopMovingOrSizing",
        "ClearAllPoints", "SetJustifyH", "SetMaxLines", "SetAllPoints", "SetColorTexture", "SetBackdropBorderColor",
        "SetFontString", "SetNormalFontObject", "SetDisabledFontObject",
        "SetFrameStrata", "SetTexture", "SetTexCoord", "SetTextColor",
        "RegisterForClicks",
        "SetStartPoint", "SetThickness",
    }) do
        methods[method] = noOp
    end

    function methods:RegisterEvent(event) self.events[event] = true end
    function methods:SetScript(script, callback) self.scripts[script] = callback end
    function methods:HookScript(script, callback)
        local previous = self.scripts[script]
        self.scripts[script] = function(...)
            if previous then previous(...) end
            callback(...)
        end
    end
    function methods:GetCenter() return 500, 400 end
    function methods:IsShown() return self.shown end
    methods.IsVisible = methods.IsShown
    function methods:Hide() self:SetShown(false) end
    function methods:Show() self:SetShown(true) end
    function methods:SetEnabled(enabled) self.enabled = enabled end
    function methods:SetChecked(checked) self.checked = checked end
    function methods:SetAlpha(alpha) self.alpha = alpha end
    function methods:SetHeight(height) self.height = height end
    function methods:GetHeight() return self.height end
    function methods:SetPoint(...) self.point = { ... } end
    function methods:GetFrameLevel() return 1 end
    function methods:SetFrameLevel() end

    function methods:Click(mouseButton)
        assert(self.shown and self.enabled ~= false, "Cannot click a hidden or disabled control")
        self.scripts.OnClick(self, mouseButton or "LeftButton")
    end

    function methods:CreateTexture()
        return setmetatable({}, { __index = methods })
    end

    function methods:CreateLine()
        local line = setmetatable({}, { __index = methods })
        self.lines[#self.lines + 1] = line
        return line
    end

    function methods:SetEndPoint(_, _, x, y)
        self.tipX, self.tipY = x, y
    end

    function methods:CreateFontString()
        local fontString = setmetatable({ shown = true }, { __index = methods })
        self.labels[#self.labels + 1] = fontString
        return fontString
    end

    function methods:SetText(value) self.text = value end
    function methods:GetStringHeight()
        if not self.text or self.text == "" then return 0 end
        local _, lineBreaks = self.text:gsub("\n", "")
        return 12 * (1 + lineBreaks)
    end

    function methods:SetShown(shown)
        if self.shown ~= shown then
            self.shown = shown
            local callback = self.scripts and self.scripts[shown and "OnShow" or "OnHide"]
            if callback then callback(self) end
        end
    end

    local function createFrame()
        local frame = setmetatable({ events = {}, scripts = {}, labels = {}, lines = {}, shown = true }, { __index = methods })
        frames[#frames + 1] = frame
        return frame
    end
    return frames, createFrame
end

test("German UI uses the client locale and preserves quest text", function()
    local frames, createFrame = mockUI()
    local env = setmetatable({
        CreateFrame = createFrame,
        UIParent = {},
        GetLocale = function() return "deDE" end,
    }, { __index = _G })
    local localized = loadAddon(env, false)
    equal(localized.L.QuestNumber:format(42), "Quest 42")
    equal(localized.L.LevelAboveOne:format(1), "1 Stufe über dir")
    equal(localized.L.LevelAboveMany:format(2), "2 Stufen über dir")
    local tracker = localized.CreateQuestTracker({ x = 0, y = 0, opacityPercent = 100 }, {}, "0.1.31")
    tracker:Render({ id = 42, title = "Test der Lehre", level = 30 }, "Räuber getötet: 0/8", {},
        {}, false, nil, "Questziel")
    tracker:RenderNearbyOffers({ { title = "Frostrache", yards = 60 } })
    equal(tracker.labels[1].text, "[30] Test der Lehre")
    equal(tracker.labels[2].text, "Räuber getötet: 0/8")
    equal(tracker.labels[5].text, "Quests in der Nähe")
    equal(frames[3].text, "Einstellungen")
    equal(tracker.routeMap.text, "Karte")
    env.GetLocale = function() return "frFR" end
    equal(loadAddon(env, false).L.Settings, "Settings")
    localized.SetLanguage("deDE")
    equal(localized.L.Settings, "Einstellungen")
    localized.SetLanguage("auto")
    equal(localized.L.Settings, "Settings")
end)

test("TOC startup and quest events update the tracker with or without optional addons", function()
    local frames, createFrame = mockUI()
    local timers, messages = {}, {}
    local distanceTicker, directionTicker, questieTicker
    local quests, objectives, complete, loaded = {}, {}, {}, {}
    local elite, settingsByKey = {}, {}
    local currentMapID, pinsByMap = 10, nil
    local playerX = 0.25
    local facing, inInstance = 0, false
    local historyMenu
    local category = { GetID = function() return 101 end }
    local openedCategory, openedMap, selectedQuest, pingedQuest
    local reads = 0
    local api = {
        GetNumQuestLogEntries = function()
            reads = reads + 1
            return #quests, #quests
        end,
        GetInfo = function(index) return quests[index] end,
        SetSelectedQuest = function(id) selectedQuest = id end,
        IsOnQuest = function() return true end,
        IsComplete = function(id) return complete[id] == true end,
        IsEliteQuest = function(id) return elite[id] == true end,
        GetQuestObjectives = function(id) return objectives[id] end,
        GetQuestsOnMap = function(id)
            if pinsByMap then return pinsByMap[id] end
            local pins = {}
            for _, quest in ipairs(quests) do
                pins[#pins + 1] = { questID = quest.questID }
            end
            return pins
        end,
    }
    local env = setmetatable({
        CreateFrame = createFrame,
        UIParent = { GetCenter = function() return 400, 300 end },
        C_QuestLog = api,
        C_Map = {
            OpenWorldMap = function(id) openedMap = id end,
            GetBestMapForUnit = function() return currentMapID end,
            GetMapInfo = function(id)
                return { mapType = mapType.Zone, name = id == 10 and "Westfall" or "Elwynn Forest" }
            end,
            GetPlayerMapPosition = function() return { x = playerX, y = 0.5 } end,
            GetMapWorldSize = function() return 1000, 500 end,
        },
        Enum = { UIMapType = mapType },
        WorldMapFrame = {
            ShowQuests = function() error("Game quest panel is unavailable") end,
            SetMapID = function() error("Map changes must use the public API") end,
        },
        QuestMapFrame_ShowQuestDetails = function() error("Game quest details are unavailable") end,
        EventRegistry = { TriggerEvent = function(_, event, id)
            equal(event, "MapCanvas.PingQuestID")
            pingedQuest = id
        end },
        IsInInstance = function() return inInstance end,
        GetPlayerFacing = function()
            assert(not inInstance, "Do not read facing inside an instance")
            return facing
        end,
        MenuUtil = {
            CreateContextMenu = function(owner, populate)
                historyMenu = { entries = {} }
                function historyMenu:CreateTitle(title) self.title = title end
                function historyMenu:SetScrollMode() end
                function historyMenu:CreateDivider() end
                function historyMenu:CreateButton(label, select, id)
                    self.entries[#self.entries + 1] = { label = label, restore = function() select(id) end }
                end
                populate(owner, historyMenu)
            end,
        },
        C_AddOns = {
            IsAddOnLoaded = function(name) return loaded[name] == true, loaded[name] == true end,
            DoesAddOnExist = function(name) return loaded[name] == true end,
            GetAddOnMetadata = function(name, key)
                equal(name, addonName)
                equal(key, "Version")
                return "0.1.31"
            end,
        },
        C_Timer = {
            After = function(_, callback) timers[#timers + 1] = callback end,
            NewTicker = function(seconds, callback)
                local ticker = { tick = callback }
                function ticker:Cancel() self.cancelled = true end
                if seconds == 1 then
                    distanceTicker = ticker
                elseif seconds == 5 then
                    questieTicker = ticker
                else
                    equal(seconds, 0.2)
                    directionTicker = ticker
                end
                return ticker
            end,
        },
        ForeverQuestNavigatorDB = { x = "invalid offset", hidden = true, includeElite = false,
            sortByDistance = false, currentZoneOnly = true },
        MinimalSliderWithSteppersMixin = { Label = { Right = 3 } },
        Settings = {
            VarType = { Boolean = "boolean", Number = "number", String = "string" },
            RegisterVerticalLayoutCategory = function(name)
                equal(name, "Forever Quest Navigator")
                return category
            end,
            RegisterAddOnSetting = function(owner, variable, key, db, variableType, name, defaultValue)
                equal(owner, category)
                equal(variable, ({
                    language = "FOREVERQUESTNAVIGATOR_LANGUAGE",
                    showDirectionArrow = "FOREVERQUESTNAVIGATOR_SHOW_DIRECTION_ARROW",
                    useQuestieKillLocations = "FOREVERQUESTNAVIGATOR_QUESTIE_KILL_LOCATIONS",
                    showQuestieOffers = "FOREVERQUESTNAVIGATOR_QUESTIE_NEARBY_OFFERS",
                    questieOfferRadius = "FOREVERQUESTNAVIGATOR_QUESTIE_OFFER_RADIUS",
                    opacityPercent = "FOREVERQUESTNAVIGATOR_TRACKER_OPACITY",
                })[key])
                local expectedType = ({ opacityPercent = "number", questieOfferRadius = "number", language = "string" })[key]
                equal(variableType, expectedType or "boolean")
                equal(name, ({
                    language = "Language",
                    opacityPercent = "Tracker opacity",
                    showDirectionArrow = "Show direction arrow",
                    useQuestieKillLocations = "Questie kill locations",
                    showQuestieOffers = "Questie nearby offers",
                    questieOfferRadius = "Questie offer radius",
                })[key])
                local expectedDefault = key ~= "showQuestieOffers"
                if key == "opacityPercent" then expectedDefault = 100 end
                if key == "questieOfferRadius" then expectedDefault = 200 end
                if key == "language" then expectedDefault = "auto" end
                equal(defaultValue, expectedDefault)
                local setting = { key = key }
                function setting:SetValue(value)
                    db[key] = value
                    self.callback(self, value)
                end
                function setting:SetValueChangedCallback(callback) self.callback = callback end
                settingsByKey[key] = setting
                return setting
            end,
            CreateControlTextContainer = function()
                local options = {}
                return {
                    Add = function(_, value, label) options[#options + 1] = { value = value, label = label } end,
                    GetData = function() return options end,
                }
            end,
            CreateDropdown = function(owner, setting, options)
                equal(owner, category)
                equal(setting, settingsByKey.language)
                equal(#options, 3)
                equal(options[1].value, "auto")
                equal(options[2].value, "deDE")
                equal(options[3].value, "enUS")
            end,
            CreateCheckbox = function(owner, registeredSetting)
                equal(owner, category)
                equal(registeredSetting, settingsByKey[registeredSetting.key])
            end,
            CreateSliderOptions = function(minimum, maximum, step)
                if minimum == 50 then
                    equal(maximum, 500)
                    equal(step, 50)
                    return { SetLabelFormatter = function(_, label, formatValue)
                        equal(label, 3)
                        equal(formatValue(200), "200 yd")
                    end }
                end
                equal(minimum, 30)
                equal(maximum, 100)
                equal(step, 5)
                return { SetLabelFormatter = function(_, label, formatValue)
                    equal(label, 3)
                    equal(formatValue(65), "65%")
                end }
            end,
            CreateSlider = function(owner, registeredSetting)
                equal(owner, category)
                equal(registeredSetting, settingsByKey[registeredSetting.key])
            end,
            RegisterAddOnCategory = function(owner) equal(owner, category) end,
            OpenToCategory = function(id) openedCategory = id end,
        },
        SlashCmdList = {},
        print = function(message) messages[#messages + 1] = message end,
    }, { __index = getfenv() })

    loadAddon(env, true)
    local eventFrame = frames[1]
    local function fire(event, ...)
        assert(eventFrame.events[event], "Unregistered event " .. event)
        eventFrame.scripts.OnEvent(eventFrame, event, ...)
    end
    local function flush()
        equal(#timers, 1)
        table.remove(timers, 1)()
    end

    fire("ADDON_LOADED", "UnrelatedAddon")
    equal(#frames, 1)
    fire("ADDON_LOADED", addonName)
    env.Minimap = createFrame()
    function env.Minimap:GetSize() return 198, 198 end
    function env.Minimap:GetEffectiveScale() return 0.5 end
    env.GetCursorPosition = function() return 250, 250 end
    env.GameTooltip = { SetOwner = noOp, SetText = noOp, AddLine = noOp, Show = noOp, Hide = noOp }
    local minimapButtonIndex = #frames + 1
    fire("PLAYER_ENTERING_WORLD")
    local minimapButton = frames[minimapButtonIndex]
    local frameCount = #frames
    fire("PLAYER_ENTERING_WORLD")
    equal(#frames, frameCount)
    fire("QUEST_LOG_UPDATE")
    flush()
    local tracker, header, openSettings, close = frames[2], frames[3], frames[4], frames[5]
    local history, skip = frames[6], frames[8]
    local title, objective = tracker.labels[1], tracker.labels[2]
    equal(reads, 1)
    equal(header.labels[2].text, "v0.1.31")
    equal(tracker.alpha, 1)
    equal(tracker:IsShown(), false)
    equal(env.ForeverQuestNavigatorDB.x, 0)
    equal(env.ForeverQuestNavigatorDB.includeElite, nil)
    equal(settingsByKey.includeElite, nil)
    equal(env.ForeverQuestNavigatorDB.currentZoneOnly, nil)
    equal(env.ForeverQuestNavigatorDB.sortByDistance, nil)
    equal(title.text, "No matching outdoor quests on the available maps.")
    equal(skip:IsShown(), false)
    equal(history.enabled, false)

    local slash = env.SlashCmdList.FOREVERQUESTNAVIGATOR
    equal(minimapButton.point[2], env.Minimap)
    equal(minimapButton.labels[1].text, "FQN")
    minimapButton:Click()
    equal(tracker:IsShown(), true)
    equal(env.ForeverQuestNavigatorDB.hidden, false)
    minimapButton:Click()
    equal(tracker:IsShown(), false)
    equal(env.ForeverQuestNavigatorDB.hidden, true)
    equal(minimapButton:IsShown(), true)
    minimapButton.scripts.OnMouseDown(minimapButton, "LeftButton")
    minimapButton.scripts.OnDragStart(minimapButton)
    minimapButton.scripts.OnUpdate(minimapButton)
    minimapButton.scripts.OnDragStop(minimapButton)
    near(minimapButton.point[4], 0)
    near(minimapButton.point[5], 104)
    near(env.ForeverQuestNavigatorDB.minimapAngle, math.pi / 2)
    equal(minimapButton.scripts.OnUpdate, nil)
    minimapButton:Click()
    equal(tracker:IsShown(), false)
    minimapButton:Click("RightButton")
    equal(openedCategory, category:GetID())
    equal(tracker:IsShown(), false)
    minimapButton.scripts.OnMouseDown(minimapButton, "LeftButton")
    minimapButton:Click()
    equal(tracker:IsShown(), true)
    openSettings:Click()
    equal(openedCategory, category:GetID())
    settingsByKey.opacityPercent:SetValue(65)
    equal(tracker.alpha, 0.65)
    header.scripts.OnDragStop()
    equal(env.ForeverQuestNavigatorDB.x, 100)
    equal(env.ForeverQuestNavigatorDB.y, 100)
    close:Click()
    equal(env.ForeverQuestNavigatorDB.hidden, true)

    slash("status")
    equal(messages[1], "FQN | Questie: Not installed")
    loaded.Questie = true
    fire("ADDON_LOADED", "Questie")
    slash(" Status ")
    equal(messages[2], "FQN | Questie: Loaded")
    slash("settings")
    equal(openedCategory, category:GetID())
    equal(env.ForeverQuestNavigatorDB.language, "auto")
    settingsByKey.language:SetValue("enUS")
    equal(env.ForeverQuestNavigatorDB.language, "enUS")
    equal(messages[3], "FQN | Language saved. Type /reload to apply the change.")

    quests[1] = { questID = 1, level = 9, title = "Supplies" }
    quests[2] = { questID = 2, level = 8, title = "Wolves" }
    objectives[2] = { { text = "Wolves slain: 0/8" } }
    fire("QUEST_ACCEPTED", 2)
    fire("QUEST_LOG_UPDATE")
    flush()
    equal(reads, 2)
    equal(title.text, "[8] Wolves")
    equal(objective.text, "Wolves slain: 0/8")

    objectives[2][1].text = "Wolves slain: 3/8"
    fire("QUEST_LOG_CRITERIA_UPDATE", 2)
    flush()
    equal(objective.text, "Wolves slain: 3/8")

    complete[2] = true
    fire("QUEST_WATCH_UPDATE", 2)
    flush()
    equal(objective.text, "Ready to turn in")

    quests[2] = nil
    fire("QUEST_TURNED_IN", 2)
    fire("QUEST_REMOVED", 2)
    flush()
    equal(title.text, "[9] Supplies")
    equal(objective.text, "See the quest log for details.")

    quests[2] = { questID = 3, level = 7, title = "Elite wolves" }
    elite[3] = true
    fire("QUEST_ACCEPTED", 3)
    flush()
    equal(title.text, "[7] Elite wolves")
    equal(skip:IsShown(), true)
    equal(history.enabled, false)

    skip:Click()
    flush()
    equal(title.text, "[9] Supplies")
    equal(history.enabled, true)
    fire("QUEST_LOG_UPDATE")
    flush()
    equal(title.text, "[9] Supplies")

    skip:Click()
    flush()
    equal(title.text, "No matching outdoor quests on the available maps.")
    equal(env.ForeverQuestNavigatorCharacterDB.skippedQuests[1].quest.title, "Supplies")
    equal(skip:IsShown(), false)
    equal(history.enabled, true)
    history:Click()
    equal(historyMenu.entries[1].label, "Restore all")
    historyMenu.entries[1].restore()
    flush()
    equal(title.text, "[7] Elite wolves")
    equal(history.enabled, false)

    skip:Click()
    flush()
    quests[2] = nil
    fire("QUEST_REMOVED", 3)
    flush()
    equal(history.enabled, false)
    quests[2] = { questID = 3, level = 7, title = "Elite wolves" }
    fire("QUEST_ACCEPTED", 3)
    flush()
    equal(title.text, "[7] Elite wolves")

    pinsByMap = { [10] = { { questID = 1 } }, [20] = { { questID = 3 } } }
    fire("QUEST_POI_UPDATE")
    flush()
    equal(title.text, "[9] Supplies")
    currentMapID = 20
    fire("ZONE_CHANGED_NEW_AREA")
    flush()
    equal(title.text, "[7] Elite wolves")
    currentMapID = 30
    fire("PLAYER_MAP_CHANGED", 20, 30)
    flush()
    equal(title.text, "No matching outdoor quests on the available maps.")
    currentMapID = nil
    fire("PLAYER_MAP_CHANGED", 30, 0)
    flush()
    equal(title.text, "Outdoor quest map unavailable.")

    env.C_QuestLog = nil
    fire("QUEST_LOG_UPDATE")
    flush()
    equal(title.text, "Quest log API unavailable.")
    equal(objective.text, "")

    env.C_QuestLog = api
    currentMapID = 10
    fire("QUEST_LOG_UPDATE")
    flush()
    skip:Click()
    flush()
    equal(title.text, "No matching outdoor quests on the available maps.")

    local firstNewFrame = #frames + 1
    env.GetLocale = function() return "deDE" end
    loadAddon(env, true)
    eventFrame = frames[firstNewFrame]
    fire("ADDON_LOADED", addonName)
    local reloadedButtonIndex = #frames + 1
    fire("PLAYER_ENTERING_WORLD")
    near(frames[reloadedButtonIndex].point[4], 0)
    near(frames[reloadedButtonIndex].point[5], 104)
    flush()
    equal(env.ForeverQuestNavigatorDB.includeElite, nil)
    equal(frames[firstNewFrame + 1].labels[1].text, "No matching outdoor quests on the available maps.")
    equal(frames[firstNewFrame + 5].enabled, true)

    local updatedTracker = frames[firstNewFrame + 1]
    equal(updatedTracker.alpha, 0.65)
    local history = frames[firstNewFrame + 5]
    env.SlashCmdList.FOREVERQUESTNAVIGATOR("")
    history:Click()
    equal(historyMenu.entries[2].label, "[9] Supplies")
    historyMenu.entries[2].restore()
    flush()
    equal(updatedTracker.labels[1].text, "[9] Supplies")
    equal(env.ForeverQuestNavigatorCharacterDB.skippedQuests[1], nil)
    env.SlashCmdList.FOREVERQUESTNAVIGATOR("")
    local auto = frames[firstNewFrame + 6]
    local activeCheckbox = frames[firstNewFrame + 7]
    local rowOne = frames[firstNewFrame + 8]
    local rowTwo = frames[firstNewFrame + 10]
    local arrow = frames[firstNewFrame + 12]
    local activeDistance = updatedTracker.labels[3]
    title, objective = updatedTracker.labels[1], updatedTracker.labels[2]
    currentMapID = 10
    quests[3] = { questID = 4, level = 5, title = "Local patrol" }
    quests[4] = { questID = 5, level = 11, title = "Local courier" }
    quests[5] = { questID = 6, level = 12, title = "Local harvest" }
    pinsByMap[10] = { { questID = 1 }, { questID = 4, x = 0.5, y = 0.5 },
        { questID = 5, x = 0.55, y = 0.75 }, { questID = 6 } }
    fire("QUEST_LOG_UPDATE")
    flush()
    equal(title.text, "[5] Local patrol")
    equal(rowOne.label.text, "[9] Supplies")
    equal(rowTwo.label.text, "[11] Local courier")
    equal(auto.enabled, false)
    equal(auto:IsShown(), false)
    equal(distanceTicker, nil)
    env.SlashCmdList.FOREVERQUESTNAVIGATOR("")
    equal(activeDistance.text, "~250 yd")
    equal(rowOne.distance.text, "~325 yd")
    equal(rowTwo.distance.text, "—")
    local readsBeforeTick = reads
    equal(arrow:IsShown(), true)
    near(arrow.lines[1].tipX, 8)
    near(arrow.lines[1].tipY, 0)
    facing = 3 * math.pi / 2
    directionTicker.tick()
    near(arrow.lines[1].tipX, 0)
    near(arrow.lines[1].tipY, 8)

    settingsByKey.showDirectionArrow:SetValue(false)
    equal(arrow:IsShown(), false)
    equal(directionTicker.cancelled, true)
    equal(distanceTicker.cancelled, nil)
    settingsByKey.showDirectionArrow:SetValue(true)
    equal(arrow:IsShown(), true)

    inInstance = true
    directionTicker.tick()
    equal(arrow:IsShown(), false)
    distanceTicker.tick()
    equal(directionTicker.cancelled, true)
    inInstance = false
    playerX = 0.375
    distanceTicker.tick()
    equal(activeDistance.text, "~125 yd")
    equal(arrow:IsShown(), true)
    equal(reads, readsBeforeTick)
    env.SlashCmdList.FOREVERQUESTNAVIGATOR("")
    equal(distanceTicker.cancelled, true)
    equal(directionTicker.cancelled, true)

    env.SlashCmdList.FOREVERQUESTNAVIGATOR("")
    rowOne:Click()
    equal(openedMap, 10)
    equal(selectedQuest, 5)
    flush()
    equal(title.text, "[11] Local courier")
    equal(rowOne.label.text, "[5] Local patrol")
    equal(auto.enabled, true)
    equal(auto:IsShown(), true)
    objectives[5] = { { text = "Letters delivered: 1/2" } }
    fire("QUEST_LOG_UPDATE")
    flush()
    equal(title.text, "[11] Local courier")
    equal(objective.text, "Letters delivered: 1/2")

    rowOne.checkbox:Click()
    flush()
    equal(title.text, "[11] Local courier")
    equal(rowOne.label.text, "[9] Supplies")
    equal(rowTwo.label.text, "[12] Local harvest")
    equal(history.text, "Skipped (1)")
    activeCheckbox:Click()
    flush()
    equal(title.text, "[9] Supplies")
    equal(rowOne.label.text, "[12] Local harvest")
    equal(rowTwo:IsShown(), false)
    equal(auto.enabled, false)

    history:Click()
    equal(historyMenu.title, "Skipped quests")
    equal(historyMenu.entries[1].label, "Restore all")
    equal(historyMenu.entries[2].label, "[11] Local courier")
    equal(historyMenu.entries[3].label, "[5] Local patrol")
    historyMenu.entries[3].restore()
    flush()
    equal(title.text, "[5] Local patrol")
    equal(history.text, "Skipped (1)")

    rowOne:Click()
    flush()
    equal(title.text, "[9] Supplies")
    auto:Click()
    flush()
    equal(title.text, "[5] Local patrol")
    rowOne:Click()
    flush()
    currentMapID = 20
    fire("PLAYER_MAP_CHANGED", 10, 20)
    flush()
    equal(title.text, "[7] Elite wolves")
    equal(rowOne:IsShown(), false)
    equal(auto.enabled, false)
    currentMapID = 10
    fire("PLAYER_MAP_CHANGED", 20, 10)
    flush()
    equal(title.text, "[5] Local patrol")

    playerX = 0.35
    pinsByMap[10][4] = { questID = 6, x = 0.25, y = 0.5 }
    fire("QUEST_POI_UPDATE")
    flush()
    equal(title.text, "[12] Local harvest")
    equal(activeDistance.text, "~100 yd")
    equal(rowOne.label.text, "[5] Local patrol")
    equal(rowTwo.label.text, "[9] Supplies")

    readsBeforeTick = reads
    playerX = 0.38
    distanceTicker.tick()
    equal(title.text, "[12] Local harvest")
    playerX = 0.42
    distanceTicker.tick()
    equal(title.text, "[5] Local patrol")
    equal(activeDistance.text, "~80 yd")
    equal(reads, readsBeforeTick)

    rowOne:Click()
    flush()
    equal(title.text, "[12] Local harvest")
    playerX = 0.48
    distanceTicker.tick()
    equal(title.text, "[12] Local harvest")
    auto:Click()
    flush()
    equal(title.text, "[5] Local patrol")

    -- Questie provides a local location for an accepted quest with no native pin.
    local ready
    equal(updatedTracker:IsVisible(), true)
    env._G = env
    env.UnitLevel = function() return 10 end
    env.Questie = { ICON_TYPE_SLAY = 1, API = { RegisterOnReady = function(callback) ready = callback end } }
    api.IsOnQuest = function(id) return id == 7 end
    api.IsQuestFlaggedCompleted = function(id) return id == 91 end
    quests = { { questID = 7, level = 9, title = "Boars" } }
    pinsByMap[10] = {}
    objectives[7] = {
        { finished = true, type = "monster", text = "Wolves slain: 8/8" },
        { type = "monster", text = "Boars slain: 0/8" },
    }
    playerX = 0.5
    facing = 0
    local spawn = { Icon = 1, Spawns = {
        [100] = { { 60, 50 }, { 55, 50 }, { 51, 50, 3 }, { -1, -1 } },
        [200] = { { 50.1, 50 } },
    } }
    local kill = { Type = "monster", Id = 3 }
    local cachedKill = { Type = "monster", Id = 3, spawnList = { [3] = spawn } }
    local activeQuest = { ObjectiveData = { [2] = kill }, Objectives = { [2] = cachedKill } }
    local framesByID = {}
    local modules = {
        ActiveQuests = { Get = function(id) return id == 7 and { quest = activeQuest } end },
        ZoneDB = { GetUiMapIdByAreaId = function(_, id) return id / 10 end },
        Phasing = { IsSpawnVisible = function(phase) return phase ~= 3 end },
        QuestieMap = { questIdFrames = framesByID },
    }
    env.QuestieLoader = { ImportModule = function(_, name) return assert(modules[name]) end }
    local function AddOffer(id, name, x, requiredLevel, starterType, questLevel)
        local frameName = "QuestieTestFrame" .. id
        framesByID[id] = { [frameName] = frameName }
        env[frameName] = { UiMapID = 10, x = x, y = 50, miniMapIcon = false, data = {
            Type = "available", Id = id, StarterType = starterType,
            QuestData = { name = name, requiredLevel = requiredLevel, level = questLevel },
        } }
    end
    AddOffer(7, "Already accepted", 50, 1)
    AddOffer(91, "Completed", 51, 1)
    AddOffer(92, "Level locked", 51, 11)
    AddOffer(93, "Item start", 52, 1, "itemFromMonster")
    AddOffer(94, "Near quest", 55, 1, nil, 8)
    AddOffer(95, "Distant quest", 90, 1)
    AddOffer(96, "Other nearby quest", 56, 1)

    fire("ADDON_LOADED", "Questie")
    env.Questie.API.isReady = true
    ready()
    flush()
    equal(title.text, "[9] Boars")
    equal(objective.text, "Boars slain: 0/8")
    equal(activeDistance.text, "~50 yd")
    equal(arrow:IsShown(), true)
    near(arrow.lines[1].tipX, 8)
    objectives[7][2].finished = true
    objectives[7][3] = { type = "item", text = "Supplies collected: 0/3" }
    activeQuest.ObjectiveData[3] = { Type = "item", Id = 8 }
    activeQuest.Objectives[3] = { Type = "item", Id = 8,
        spawnList = { [51] = { Spawns = { [100] = { { 35, 50 } } } } } }
    fire("QUEST_LOG_CRITERIA_UPDATE", 7)
    flush()
    equal(objective.text, "Supplies collected: 0/3")
    equal(activeDistance.text, "~150 yd")
    near(arrow.lines[1].tipX, -8)

    quests[2] = { questID = 8, level = 10, title = "Companion quest" }
    api.IsOnQuest = function(id) return id == 7 or id == 8 end
    pinsByMap[10] = { { questID = 8, x = 0.2, y = 0.5 } }
    fire("QUEST_LOG_UPDATE")
    flush()
    local nearby = updatedTracker.nearbyStopsButton
    equal(nearby.text, "1 other target nearby")
    nearby:Click()
    equal(historyMenu.entries[1].label, "[10] Companion quest · ~150 yd")
    local offersHeading = updatedTracker.labels[5]
    updatedTracker:RenderNearbyOffers({ { title = "New quest", yards = 70 } })
    rowOne.routeButton:Click()
    local headingTop = updatedTracker.height - offersHeading.point[3] - offersHeading:GetStringHeight()
    local rowBottom = -rowOne.point[3] + rowOne:GetHeight()
    assert(headingTop - rowBottom >= 8)
    updatedTracker:RenderNearbyOffers()
    rowOne.checkbox:Click()
    flush()
    equal(nearby:IsShown(), false)
    quests[2], objectives[7][3], objectives[7][2].finished = nil, nil, nil
    api.IsOnQuest = function(id) return id == 7 end
    pinsByMap[10] = {}
    fire("QUEST_REMOVED", 8)
    settingsByKey.useQuestieKillLocations:SetValue(false)
    flush()
    equal(title.text, "No matching outdoor quests on the available maps.")
    settingsByKey.useQuestieKillLocations:SetValue(true)
    flush()
    equal(title.text, "[9] Boars")
    local offer = updatedTracker.labels[5]
    equal(offer:IsShown(), false)
    settingsByKey.showQuestieOffers:SetValue(true)
    flush()
    equal(offer.text, "Nearby quests")
    equal(offer:IsShown(), true)
    local firstOffer = frames[firstNewFrame + 15]
    local secondOffer = frames[firstNewFrame + 17]
    equal(firstOffer.label.text, "[8] Near quest")
    equal(secondOffer.label.text, "Other nearby quest")
    equal(firstOffer.distance.text, "~50 yd")
    equal(firstOffer.checkbox, nil)
    near(firstOffer.arrow.lines[1].tipX, 6)
    settingsByKey.questieOfferRadius:SetValue(500)
    flush()
    equal(frames[firstNewFrame + 19].label.text, "Distant quest")
    settingsByKey.questieOfferRadius:SetValue(200)
    flush()

    playerX = 0.25
    questieTicker.tick()
    flush()
    equal(offer:IsShown(), false)
    complete[7] = true
    pinsByMap[10] = { { questID = 7, x = 0.1, y = 0.5 } }
    fire("QUEST_LOG_UPDATE")
    flush()
    equal(objective.text, "Ready to turn in")
    equal(activeDistance.text, "~150 yd")
    near(arrow.lines[1].tipX, -8)

    -- A is closer, but B's second follow-up returns to A.
    env.bit = { band = function() return 0 end }
    env.UnitRace = function() return "Human", "Human", 1 end
    env.UnitClass = function() return "Mage", "MAGE", 8 end
    local records = {
        [72] = { finishedBy = { { 2 } }, childQuests = { 73 } },
        [73] = { name = "Middle stop", startedBy = { { 2 } }, finishedBy = { { 3 } }, preQuestSingle = { 72 }, nextQuestInChain = 74 },
        [74] = { name = "Back to A", startedBy = { { 3 } }, finishedBy = { { 4 } }, preQuestGroup = { 73, 72 }, childQuests = { 75 } },
        [75] = { startedBy = { { 4 } }, finishedBy = { { 3 } }, preQuestSingle = { 74 } },
    }
    local questDB = setmetatable({ Get = function(id, field) return (records[id] or {})[field] end }, {
        __index = function(_, key)
            return function(id)
                local value = (records[id] or {})[key]
                if key == "requiredLevel" then return 5 end
                if key == "objectives" then return {} end
                return value
            end
        end,
    })
    local npcX = { [2] = 30, [3] = 41, [4] = 60 }
    env.LibQuestieDB = { Quest = questDB, Npc = { spawns = function(id) return { [100] = { { npcX[id], 50 } } } end } }
    playerX = 0.5
    api.IsOnQuest = function(id) return id == 71 or id == 72 end
    complete[71], complete[72] = true, true
    quests = { { questID = 71, level = 9, title = "Stop A" }, { questID = 72, level = 10, title = "Stop B" } }
    pinsByMap[10] = { { questID = 71, x = 0.6, y = 0.5 }, { questID = 72, x = 0.3, y = 0.5 } }
    fire("QUEST_LOG_UPDATE")
    flush()
    local routeNote = updatedTracker.labels[6]
    equal(title.text, "[10] Stop B")
    equal(rowOne.label.text, "[9] Stop A")
    equal(routeNote.text, "Follow-up 2 saves ~200 yd")
    local heightWithRoute = updatedTracker.height
    local routeToggle, routeDetails = frames[firstNewFrame + 21], updatedTracker.labels[7]
    equal(routeDetails:IsShown(), false)
    routeToggle:Click()
    equal(routeDetails:IsShown(), true)
    assert(routeDetails.text:find("Turn in Stop B\nFollow-up 1: Middle stop\nFollow-up 2: Back to A\nSame visit: Stop A", 1, true))
    assert(not routeDetails.text:find("Estimated:", 1, true))
    assert(updatedTracker.height > heightWithRoute)
    routeToggle:Click()
    equal(updatedTracker.height, heightWithRoute)
    near(arrow.lines[1].tipX, -8)
    rowOne:Click()
    flush()
    equal(title.text, "[9] Stop A")
    equal(routeNote:IsShown(), false)
    equal(routeToggle:IsShown(), true)
    auto:Click()
    flush()
    equal(title.text, "[10] Stop B")
    records[74].preQuestGroup = { 73, 999 }
    fire("QUEST_TURNED_IN", 999)
    flush()
    equal(title.text, "[9] Stop A")
    equal(routeNote.text, "Nearby target · Turn-in")

    local combat = false
    env.InCombatLockdown = function() return combat end

    -- Player is close to the next zone. Quest distance uses shared world
    -- coordinates even when the player has no position on that zone's map.
    env.LibQuestieDB = nil
    env.CreateVector2D = function(x, y) return { x = x, y = y } end
    env.C_Map.GetMapInfo = function(id)
        if id == 1 then return { mapType = mapType.Continent } end
        local names = { [10] = "Current zone", [20] = "Neighbor zone", [1416] = "Alteracgebirge", [1422] = "Westliche Pestländer" }
        return { mapType = mapType.Zone, parentMapID = 1, name = names[id] }
    end
    env.C_Map.GetMapChildrenInfo = function(id, mapKind, all)
        equal(id, 1)
        equal(mapKind, mapType.Zone)
        equal(all, true)
        return { { mapID = 10 }, { mapID = 20 }, { mapID = 30 } }
    end
    env.C_Map.GetWorldPosFromMapPos = function(id, position)
        return id == 30 and 2 or 1, {
            x = -position.y * 500,
            y = (id == 20 and -1000 or 0) - position.x * 1000,
        }
    end
    env.C_Map.GetPlayerMapPosition = function(id)
        if id == 10 then return { x = playerX, y = 0.5 } end
    end
    api.IsOnQuest = function() return true end
    complete[71], complete[72] = false, false
    quests = {
        { questID = 71, level = 10, title = "Same zone" },
        { questID = 72, level = 11, title = "Over the border" },
        { questID = 76, level = 9, title = "Different world" },
    }
    playerX = 0.98
    pinsByMap = {
        [10] = { { questID = 71, x = 0.70, y = 0.5 } },
        [20] = { { questID = 72, x = 0.03, y = 0.5 } },
        [30] = { { questID = 76, x = 0.98, y = 0.5 } },
    }
    fire("QUEST_POI_UPDATE")
    flush()
    equal(title.text, "[11] Over the border")
    local activeZone = updatedTracker.labels[8]
    equal(activeZone.text, "Neighbor zone")
    equal(activeDistance.text, "~50 yd")
    equal(rowTwo.distance.text, "—")
    near(arrow.lines[1].tipX, 8)
    quests[2].level = 17
    fire("QUEST_LOG_UPDATE")
    flush()
    equal(title.text, "[10] Same zone")
    complete[72] = true
    fire("QUEST_LOG_UPDATE")
    flush()
    equal(title.text, "[17] Over the border")
    local questMapButton = frames[firstNewFrame + 22]
    questMapButton:Click()
    equal(openedMap, 20)
    equal(selectedQuest, 72)
    equal(pingedQuest, 72)

    records[74].preQuestGroup = { 73, 72 }
    api.IsOnQuest = function(id) return id == 71 or id == 72 end
    env.LibQuestieDB = { Quest = questDB, Npc = { spawns = function(id)
        if id == 4 then return { [200] = { { 3, 50 } } } end
        return { [100] = { { id == 2 and 80 or 88, 50 } } }
    end } }
    quests = { { questID = 71, level = 10, title = "A in the next zone" },
        { questID = 72, level = 10, title = "B in this zone" } }
    complete[71] = true
    pinsByMap = {
        [10] = { { questID = 72, x = 0.80, y = 0.5 } },
        [20] = { { questID = 71, x = 0.03, y = 0.5 } },
    }
    fire("QUEST_LOG_UPDATE")
    flush()
    equal(title.text, "[10] B in this zone")
    equal(rowOne.label.text, "[10] A in the next zone")
    equal(rowOne.zone.text, "Neighbor zone")
    equal(activeZone:IsShown(), false)
    equal(rowOne.distance.text, "~50 yd")
    equal(routeNote.text, "Follow-up 2 saves ~100 yd")
    near(arrow.lines[1].tipX, -8)

    api.GetQuestTagInfo = function(id)
        if id == 74 then return { tagID = 41 } end
    end
    fire("QUEST_DATA_LOAD_RESULT", 74)
    flush()
    equal(title.text, "[10] A in the next zone")
    assert(routeNote.text:find("Nearby target", 1, true))

    env.LibQuestieDB = nil
    quests = {
        { questID = 80, level = 10, title = "Outdoor elite" },
        { questID = 81, level = 10, title = "Dungeon objective" },
        { questID = 82, level = 10, title = "Raid objective" },
        { questID = 83, level = 10, title = "PvP objective" },
        { questID = 84, level = 10, title = "Heroic objective" },
        { questID = 85, level = 10, title = "Outdoor dungeon turn-in" },
        { questID = 86, level = 10, title = "Indoor raid turn-in" },
    }
    local questTags = { [80] = 1, [81] = 81, [82] = 88, [83] = 41, [85] = 81, [86] = 62 }
    api.GetQuestTagInfo = function(id) return questTags[id] and { tagID = questTags[id] } end
    modules.QuestieDB = { GetQuestTagInfo = function(id) return id == 84 and 85 or nil end }
    api.IsOnQuest = function(id) return id >= 80 and id <= 86 end
    api.GetNextWaypoint = function(id)
        if id == 85 then return 20, 0.04, 0.5 end
        if id == 86 then return 99, 0.4, 0.5 end
    end
    complete[85], complete[86] = true, true
    local getMapInfo = env.C_Map.GetMapInfo
    env.C_Map.GetMapInfo = function(id)
        if id == 99 then return { mapType = mapType.Dungeon, parentMapID = 10 } end
        return getMapInfo(id)
    end
    pinsByMap = { [10] = { { questID = 80, x = 0.88, y = 0.5 } } }
    for id = 81, 86 do
        pinsByMap[10][#pinsByMap[10] + 1] = { questID = id, x = 0.97, y = 0.5 }
    end
    fire("QUEST_LOG_UPDATE")
    flush()
    equal(title.text, "[10] Outdoor dungeon turn-in")
    equal(objective.text, "Ready to turn in")
    equal(rowOne.label.text, "[10] Outdoor elite")
    equal(rowTwo:IsShown(), false)
    questMapButton:Click()
    equal(openedMap, 20)
    equal(selectedQuest, 85)
    equal(pingedQuest, 85)
    openedMap = nil
    combat = true
    questMapButton:Click()
    equal(openedMap, nil)
    equal(messages[#messages], "FQN | Open the quest map outside combat.")
    combat = false

    -- Gol'dir's discovery trigger, key drop, and hand-in all belong to Alterac.
    env.C_Map.GetMapChildrenInfo = function()
        return { { mapID = 10 }, { mapID = 1416 }, { mapID = 1422 } }
    end
    modules.ZoneDB.GetUiMapIdByAreaId = function(_, id)
        if id == 36 then return 1416 end
    end
    local alteracSpawns = { [36] = { { 60, 43.7 } } }
    env.LibQuestieDB = {
        Quest = {
            triggerEnd = function(id)
                equal(id, 503)
                return { "Find Gol'dir", alteracSpawns }
            end,
            objectives = function() return { { { 2316 } }, nil, { { 3704 } } } end,
            finishedBy = function() return { { 2316 } } end,
        },
        Npc = { spawns = function(id)
            assert(id == 2316 or id == 2431)
            return alteracSpawns
        end },
        Item = {
            npcDrops = function(id) equal(id, 3704) return { 2431 } end,
            objectDrops = function() return {} end,
        },
    }
    env.GetQuestUiMapID = function(id, ignoreWaypoints)
        equal(id, 503)
        equal(ignoreWaypoints, true)
        return 1422
    end
    api.IsOnQuest = function(id) return id == 503 end
    quests = { { questID = 503, level = 36, title = "Gol'dir" } }
    pinsByMap = { [1422] = { { questID = 503, x = 0.5, y = 0.5 } } }
    playerX = 0.88
    local playerMapOffset = 0
    local worldPosition = env.C_Map.GetWorldPosFromMapPos
    env.C_Map.GetWorldPosFromMapPos = function(id, position)
        local continent, point = worldPosition(id, position)
        if id == 10 then point.y = point.y - playerMapOffset end
        return continent, point
    end
    env.Enum.FlightPathFaction = { Neutral = 0, Horde = 1, Alliance = 2 }
    env.Enum.FlightPathState = { Current = 0, Reachable = 1, Unreachable = 2 }
    env.UnitFactionGroup = function() return "Horde" end
    env.GetTaxiMapID = function() return 1 end
    local taxiNodes = {
        { nodeID = 1, state = 1 }, { nodeID = 2, state = 2 }, { nodeID = 3, state = 0 },
    }
    local discoveredFlight = { nodeID = 1, name = "Test flight point", faction = 1,
        position = { x = 0.7, y = 0.437 }, isUndiscovered = false }
    local borderFlights = {}
    env.C_TaxiMap = { GetAllTaxiNodes = function(id)
        equal(id, 1)
        return taxiNodes
    end, GetTaxiNodesForMap = function(id)
        if id == 1 then return borderFlights end
        equal(id, 1416)
        return { discoveredFlight,
            { nodeID = 2, name = "Locked despite map flag", faction = 1,
                position = { x = 0.61, y = 0.437 }, isUndiscovered = false },
            { nodeID = 3, name = "Other faction", faction = 2,
                position = { x = 0.62, y = 0.437 }, isUndiscovered = false },
        }
    end }
    fire("QUEST_LOG_UPDATE")
    flush()
    equal(activeZone.text, "Alteracgebirge")
    equal(activeDistance.text, "~282 yd")
    equal(routeToggle:IsShown(), true)
    assert(routeNote.text:find("Nearby target", 1, true))
    routeToggle:Click()
    assert(routeDetails.text:find("Quest objective: Alteracgebirge", 1, true))
    assert(not routeDetails.text:find("Unlocked flight point", 1, true))
    equal(updatedTracker.routeMap.text, "Map")
    local canvas = createFrame()
    function canvas:GetSize() return 1000, 500 end
    env.WorldMapFrame = {
        GetCanvas = function() return canvas end,
        GetMapID = function() return openedMap end,
        OnMapChanged = noOp,
    }
    env.hooksecurefunc = function(frame, method, callback)
        local original = frame[method]
        frame[method] = function(...) original(...); callback(...) end
    end
    updatedTracker.routeMap:Click()
    equal(openedMap, 1416)
    local marker = frames[#frames]
    equal(marker:IsShown(), true)
    equal(marker.point[2], canvas)
    near(marker.point[4], 600)
    near(marker.point[5], -218.5)
    openedMap = 1422
    env.WorldMapFrame:OnMapChanged()
    equal(marker:IsShown(), false)
    openedMap = 1416
    env.WorldMapFrame:OnMapChanged()
    equal(marker:IsShown(), true)
    function canvas:GetSize() return 500, 250 end
    canvas.scripts.OnSizeChanged(canvas)
    near(marker.point[4], 300)
    near(marker.point[5], -109.25)
    marker:Click("RightButton")
    equal(marker:IsShown(), false)
    distanceTicker.tick()
    equal(marker:IsShown(), false)
    updatedTracker.routeMap:Click()
    equal(marker:IsShown(), true)
    routeToggle:Click()
    playerMapOffset = 2200
    distanceTicker.tick()
    assert(routeNote.text:find("Travel distance", 1, true))
    fire("TAXIMAP_OPENED")
    flush()
    equal(env.ForeverQuestNavigatorCharacterDB.confirmedFlightPoints[1], true)
    equal(env.ForeverQuestNavigatorCharacterDB.confirmedFlightPoints[2], nil)
    assert(routeNote.text:find("Travel distance", 1, true))
    routeToggle:Click()
    assert(routeDetails.text:find("Unlocked flight point: Test flight point (~100 yd from target)", 1, true))
    playerMapOffset = 0
    distanceTicker.tick()
    equal(routeDetails:IsShown(), true)
    assert(not routeDetails.text:find("Unlocked flight point", 1, true))
    playerMapOffset = 2200
    distanceTicker.tick()
    questMapButton:Click()
    equal(openedMap, 1416)
    discoveredFlight.isUndiscovered = true
    fire("TAXI_NODE_STATUS_CHANGED")
    flush()
    assert(routeNote.text:find("Travel distance", 1, true))
    assert(not routeDetails.text:find("Unlocked flight point", 1, true))
    borderFlights[1] = { nodeID = 4, name = "Neighbor flight point", faction = 0,
        position = { x = 0.65, y = 0.437 }, isUndiscovered = false }
    taxiNodes[4] = { nodeID = 4, state = 1 }
    fire("TAXI_NODE_STATUS_CHANGED")
    flush()
    assert(routeDetails.text:find("Unlocked flight point: Neighbor flight point (~50 yd from target)", 1, true))
    fire("TAXIMAP_CLOSED")
    flush()

    playerMapOffset = 1420
    quests[2] = { questID = 501, level = 10, title = "Local task" }
    api.IsOnQuest = function(id) return id == 501 or id == 503 end
    pinsByMap[10] = { { questID = 501, x = 0.85, y = 0.5 } }
    env.GetQuestUiMapID = function(id) return id == 503 and 1422 or 10 end
    fire("QUEST_LOG_UPDATE")
    flush()
    equal(title.text, "[10] Local task")
    equal(rowOne.label.text, "[36] Gol'dir")
    equal(rowOne.distance.text, "~1700 yd")
    equal(rowOne.routeButton:IsShown(), true)
    equal(routeToggle:IsShown(), true)
    openedMap = nil
    rowOne.routeButton:Click()
    equal(rowOne.routeDetails:IsShown(), true)
    assert(rowOne.routeDetails.text:find("Unlocked flight point: Neighbor flight point (~50 yd from target)", 1, true))
    equal(title.text, "[10] Local task")
    equal(openedMap, nil)
    rowOne.routeMap:Click()
    equal(openedMap, 1416)
    equal(title.text, "[10] Local task")
    playerMapOffset = 0
    distanceTicker.tick()
    equal(rowOne.routeButton:IsShown(), true)
    equal(rowOne.routeDetails:IsShown(), true)
    assert(not rowOne.routeDetails.text:find("Unlocked flight point", 1, true))

    playerMapOffset = 2200
    quests[2], pinsByMap[10] = nil, nil
    complete[503] = true
    fire("QUEST_LOG_UPDATE")
    flush()
    questMapButton:Click()
    equal(openedMap, 1416)
    equal(selectedQuest, 503)

    playerMapOffset = 2200
    local mapProjection = env.C_Map.GetWorldPosFromMapPos
    env.C_Map.GetWorldPosFromMapPos = function(id, position)
        if id == 1 then return 1, { x = -position.y * 500, y = -position.x * 5000 } end
        return mapProjection(id, position)
    end
    taxiNodes[1] = { nodeID = 1, state = 0, slotIndex = 1, name = "Departure",
        position = { x = 0.61, y = 0.5 } }
    taxiNodes[2] = { nodeID = 2, state = 1, slotIndex = 2, name = "Arrival",
        position = { x = 0.13, y = 0.437 } }
    taxiNodes[3] = { nodeID = 3, state = 2, slotIndex = 3, name = "Intermediate stop",
        position = { x = 0.37, y = 0.5 } }
    taxiNodes[4] = nil
    env.GetNumRoutes = function(slot) equal(slot, 2); return 2 end
    env.TaxiGetNodeSlot = function(slot, index, source)
        equal(slot, 2)
        if index == 1 then return source and 1 or 3 end
        equal(index, 2)
        return source and 3 or 2
    end
    fire("TAXIMAP_OPENED")
    flush()
    assert(routeDetails.text:find("Fly: Departure to Arrival", 1, true))
    assert(routeDetails.text:find("~30 yd to departure · ~50 yd after landing", 1, true))
    assert(not routeDetails.text:find("Estimated:", 1, true))
    taxiNodes[3].position.x = 0.99
    fire("TAXI_NODE_STATUS_CHANGED")
    flush()
    assert(not routeDetails.text:find("Fly:", 1, true))
    taxiNodes[3].position.x = 0.37
    fire("TAXI_NODE_STATUS_CHANGED")
    flush()
    assert(routeDetails.text:find("Fly: Departure to Arrival", 1, true))
    playerMapOffset = 1300
    distanceTicker.tick()
    assert(not routeDetails.text:find("Fly:", 1, true))
    playerMapOffset = 2200
    taxiNodes[2].state = 2
    fire("TAXI_NODE_STATUS_CHANGED")
    flush()
    assert(not routeDetails.text:find("Fly:", 1, true))
    fire("TAXIMAP_CLOSED")
    flush()
    env.C_Map.GetWorldPosFromMapPos = mapProjection

    env.LibQuestieDB, env.GetQuestUiMapID = nil, nil
    env.C_Map.GetMapPosFromWorldPos = function(_, position)
        near(position.y, -500)
        return 1416, { x = 0.6, y = 0.437 }
    end
    fire("QUEST_LOG_UPDATE")
    flush()
    questMapButton:Click()
    equal(openedMap, 1416)

    -- A reachable quest on the approach saves backtracking across three stops.
    env.C_Map.GetMapPosFromWorldPos = nil
    playerMapOffset, playerX = 0, 0.2
    quests = {
        { questID = 601, level = 10, title = "Main objective" },
        { questID = 602, level = 13, title = "On the approach" },
        { questID = 603, level = 10, title = "Outdoor hand-in" },
    }
    api.IsOnQuest = function(id) return id >= 601 and id <= 603 end
    complete[603] = true
    objectives[602] = { { text = "First objective" }, { text = "Second objective" } }
    pinsByMap = { [10] = {
        { questID = 601, x = 0.8, y = 0.5 },
        { questID = 602, x = 0.72, y = 0.5 },
        { questID = 603, x = 0.9, y = 0.5 },
    } }
    fire("QUEST_LOG_UPDATE")
    flush()
    equal(title.text, "[13] On the approach")
    equal(routeNote.text, "Outing saves ~160 yd")
    assert(routeDetails.text:find("1. Work on On the approach\n2. Work on Main objective\n3. Turn in Outdoor hand-in", 1, true))
    env.GetQuestUiMapID = function(id) if id == 602 then return 1422 end end
    fire("QUEST_POI_UPDATE")
    flush()
    questMapButton:Click()
    equal(openedMap, 10)
    equal(marker:IsShown(), true)
    near(marker.point[4], 360)
    near(marker.point[5], -125)
    pinsByMap[10][2].x = 0.73
    fire("QUEST_POI_UPDATE")
    flush()
    near(marker.point[4], 365)
    objectives[602][1].finished = true
    fire("QUEST_LOG_CRITERIA_UPDATE", 602)
    flush()
    equal(title.text, "[10] Main objective")
    equal(routeNote.text, "Next stop on your outing")
    assert(routeDetails.text:find("1. Work on Main objective\n2. Turn in Outdoor hand-in", 1, true))
    complete[601] = true
    fire("QUEST_LOG_UPDATE")
    flush()
    equal(title.text, "[10] Outdoor hand-in")
    equal(routeNote.text, "Next stop on your outing")

    updatedTracker:Hide()
    equal(questieTicker.cancelled, true)
end)

print(("%d tests passed (%s)."):format(testsPassed, _VERSION))
