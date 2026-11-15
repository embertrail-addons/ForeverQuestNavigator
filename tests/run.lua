local addonName = "ForeverQuestNavigator"
local testsPassed = 0

local function equal(actual, expected)
    assert(actual == expected, ("Expected %s, got %s"):format(tostring(expected), tostring(actual)))
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
        IsEliteQuest = function(id) return id == 10 end,
        IsFailed = function(id) return id == 15 end,
        IsQuestDisabledForSession = function(id) return id == 16 end,
    })
    equal(#quests, 3)
    equal(quests[1].id, 10)
    equal(quests[1].title, "Collect supplies")
    equal(quests[1].level, 8)
    equal(quests[1].readyToTurnIn, true)
    equal(quests[1].elite, true)
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

test("Ranking applies skips and the elite filter to regular quests and turn-ins", function()
    local quests = {
        { id = 1, level = 5, elite = true, readyToTurnIn = true },
        { id = 2, level = 6 },
        { id = 3, level = 7, elite = true },
        { id = 4, level = 8, elite = false },
    }
    equal(addon.QuestPrioritizer.Rank(quests, true)[1].id, 1)
    equal(addon.QuestPrioritizer.Rank(quests, false)[1].id, 2)
    local ranked = addon.QuestPrioritizer.Rank(quests, false, { [2] = true })
    equal(#ranked, 1)
    equal(ranked[1].id, 4)
    equal(#addon.QuestPrioritizer.Rank(quests, false, { [2] = true, [4] = true }), 0)
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

test("Dependency detection handles missing, loading and loaded addons", function()
    local missing = addon.ReadDependencyStatus({
        IsAddOnLoaded = function() return false, false end,
        DoesAddOnExist = function() return false end,
    })
    equal(missing.Questie, "Not installed")
    equal(missing.TomTom, "Not installed")

    local mixed = addon.ReadDependencyStatus({
        IsAddOnLoaded = function(name) return true, name == "TomTom" end,
        DoesAddOnExist = function() return true end,
    })
    equal(mixed.Questie, "Not loaded")
    equal(mixed.TomTom, "Loaded")
    equal(addon.ReadDependencyStatus(nil).TomTom, "Unknown")
end)

local function noOp() end

local function mockUI()
    local frames = {}
    local methods = {}
    for _, method in ipairs({
        "SetSize", "SetPoint", "SetClampedToScreen", "SetMovable", "SetBackdrop", "SetBackdropColor",
        "SetHeight", "EnableMouse", "RegisterForDrag", "StartMoving", "StopMovingOrSizing",
        "ClearAllPoints", "SetJustifyH", "SetMaxLines",
    }) do
        methods[method] = noOp
    end

    function methods:RegisterEvent(event) self.events[event] = true end
    function methods:SetScript(script, callback) self.scripts[script] = callback end
    function methods:GetCenter() return 500, 400 end
    function methods:IsShown() return self.shown end
    function methods:Hide() self:SetShown(false) end
    function methods:SetEnabled(enabled) self.enabled = enabled end

    function methods:CreateFontString()
        local fontString = setmetatable({}, { __index = methods })
        self.labels[#self.labels + 1] = fontString
        return fontString
    end

    function methods:SetText(value) self.text = value end

    function methods:SetShown(shown)
        if self.shown ~= shown then
            self.shown = shown
            local callback = self.scripts[shown and "OnShow" or "OnHide"]
            if callback then callback(self) end
        end
    end

    local function createFrame()
        local frame = setmetatable({ events = {}, scripts = {}, labels = {}, shown = true }, { __index = methods })
        frames[#frames + 1] = frame
        return frame
    end
    return frames, createFrame
end

test("TOC startup and quest events update the tracker with or without optional addons", function()
    local frames, createFrame = mockUI()
    local timers, messages = {}, {}
    local quests, objectives, complete, loaded = {}, {}, {}, {}
    local elite, setting = {}, {}
    local category = { GetID = function() return 101 end }
    local openedCategory
    local reads = 0
    local api = {
        GetNumQuestLogEntries = function()
            reads = reads + 1
            return #quests, #quests
        end,
        GetInfo = function(index) return quests[index] end,
        IsOnQuest = function() return true end,
        IsComplete = function(id) return complete[id] == true end,
        IsEliteQuest = function(id) return elite[id] == true end,
        GetQuestObjectives = function(id) return objectives[id] end,
    }
    local env = setmetatable({
        CreateFrame = createFrame,
        UIParent = { GetCenter = function() return 400, 300 end },
        C_QuestLog = api,
        C_AddOns = {
            IsAddOnLoaded = function(name) return loaded[name] == true, loaded[name] == true end,
            DoesAddOnExist = function(name) return loaded[name] == true end,
        },
        C_Timer = { After = function(_, callback) timers[#timers + 1] = callback end },
        ForeverQuestNavigatorDB = { x = "invalid offset", hidden = true },
        Settings = {
            VarType = { Boolean = "boolean" },
            RegisterVerticalLayoutCategory = function(name)
                equal(name, "Forever Quest Navigator")
                return category
            end,
            RegisterAddOnSetting = function(owner, variable, key, db, variableType, name, defaultValue)
                equal(owner, category)
                equal(variable, "FOREVERQUESTNAVIGATOR_INCLUDE_ELITE")
                equal(key, "includeElite")
                equal(variableType, "boolean")
                equal(name, "Include elite quests")
                equal(defaultValue, true)
                function setting:SetValue(value)
                    db[key] = value
                    self.callback(self, value)
                end
                function setting:SetValueChangedCallback(callback) self.callback = callback end
                return setting
            end,
            CreateCheckbox = function(owner, registeredSetting)
                equal(owner, category)
                equal(registeredSetting, setting)
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
    fire("PLAYER_ENTERING_WORLD")
    fire("QUEST_LOG_UPDATE")
    flush()
    local tracker, header, close, skip, reset = frames[2], frames[3], frames[4], frames[5], frames[6]
    local title, objective = tracker.labels[1], tracker.labels[2]
    equal(reads, 1)
    equal(tracker:IsShown(), false)
    equal(env.ForeverQuestNavigatorDB.x, 0)
    equal(env.ForeverQuestNavigatorDB.includeElite, true)
    equal(title.text, "No actionable quests in the log.")
    equal(skip.enabled, false)
    equal(reset.enabled, false)

    local slash = env.SlashCmdList.FOREVERQUESTNAVIGATOR
    slash("")
    equal(tracker:IsShown(), true)
    equal(env.ForeverQuestNavigatorDB.hidden, false)
    header.scripts.OnDragStop()
    equal(env.ForeverQuestNavigatorDB.x, 100)
    equal(env.ForeverQuestNavigatorDB.y, 100)
    close.scripts.OnClick()
    equal(env.ForeverQuestNavigatorDB.hidden, true)

    slash("status")
    equal(messages[1], "FQN | Questie: Not installed | TomTom: Not installed")
    loaded.Questie = true
    fire("ADDON_LOADED", "Questie")
    slash(" Status ")
    equal(messages[2], "FQN | Questie: Loaded | TomTom: Not installed")
    slash("settings")
    equal(openedCategory, category:GetID())

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
    equal(skip.enabled, true)
    equal(reset.enabled, false)

    skip.scripts.OnClick()
    flush()
    equal(title.text, "[9] Supplies")
    equal(reset.enabled, true)
    fire("QUEST_LOG_UPDATE")
    flush()
    equal(title.text, "[9] Supplies")

    skip.scripts.OnClick()
    flush()
    equal(title.text, "No quests match your filters and skips.")
    equal(skip.enabled, false)
    equal(reset.enabled, true)
    reset.scripts.OnClick()
    flush()
    equal(title.text, "[7] Elite wolves")
    equal(reset.enabled, false)

    setting:SetValue(false)
    flush()
    equal(title.text, "[9] Supplies")
    equal(env.ForeverQuestNavigatorDB.includeElite, false)
    setting:SetValue(true)
    flush()
    equal(title.text, "[7] Elite wolves")

    skip.scripts.OnClick()
    flush()
    quests[2] = nil
    fire("QUEST_REMOVED", 3)
    flush()
    equal(reset.enabled, false)
    quests[2] = { questID = 3, level = 7, title = "Elite wolves" }
    fire("QUEST_ACCEPTED", 3)
    flush()
    equal(title.text, "[7] Elite wolves")

    env.C_QuestLog = nil
    fire("QUEST_LOG_UPDATE")
    flush()
    equal(title.text, "Quest log API unavailable.")
    equal(objective.text, "")

    env.C_QuestLog = api
    setting:SetValue(false)
    flush()
    skip.scripts.OnClick()
    flush()
    equal(title.text, "No quests match your filters and skips.")

    local firstNewFrame = #frames + 1
    loadAddon(env, true)
    eventFrame = frames[firstNewFrame]
    fire("ADDON_LOADED", addonName)
    flush()
    equal(env.ForeverQuestNavigatorDB.includeElite, false)
    equal(frames[firstNewFrame + 1].labels[1].text, "[9] Supplies")
    equal(frames[firstNewFrame + 5].enabled, false)
end)

print(("%d tests passed (%s)."):format(testsPassed, _VERSION))
