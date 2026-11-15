local addonName, addon = ...
local events = CreateFrame("Frame")
local tracker, dependencies, settings
local currentQuestID
local skippedQuestIDs = {}
local refreshPending = false

local function Refresh()
    refreshPending = false
    currentQuestID = nil
    local hasSkips = next(skippedQuestIDs) ~= nil
    local quests = addon.QuestLog.Read(C_QuestLog)
    if not quests then
        tracker:Render(nil, "Quest log API unavailable.", hasSkips)
        return
    end

    local quest = addon.QuestPrioritizer.Rank(quests, settings.includeElite, skippedQuestIDs)[1]
    if not quest then
        if hasSkips or not settings.includeElite then
            tracker:Render(nil, "No quests match your filters and skips.", hasSkips)
        else
            tracker:Render(nil, "No actionable quests in the log.", false)
        end
        return
    end

    currentQuestID = quest.id
    local text = "Ready to turn in"
    if not quest.readyToTurnIn then
        text = addon.QuestLog.GetObjectiveText(C_QuestLog, quest.id) or "See the quest log for details."
    end
    tracker:Render(quest, text, hasSkips)
end

local function ScheduleRefresh()
    if not refreshPending then
        refreshPending = true
        C_Timer.After(0.1, Refresh)
    end
end

local function SkipQuest()
    if currentQuestID then
        skippedQuestIDs[currentQuestID] = true
        currentQuestID = nil
        ScheduleRefresh()
    end
end

local function ResetSkips()
    skippedQuestIDs = {}
    ScheduleRefresh()
end

local function RegisterSettings()
    local category = Settings.RegisterVerticalLayoutCategory("Forever Quest Navigator")
    local includeElite = Settings.RegisterAddOnSetting(category, "FOREVERQUESTNAVIGATOR_INCLUDE_ELITE",
        "includeElite", settings, Settings.VarType.Boolean, "Include elite quests", true)
    includeElite:SetValueChangedCallback(ScheduleRefresh)
    Settings.CreateCheckbox(category, includeElite, "Include quests marked as elite in recommendations.")
    Settings.RegisterAddOnCategory(category)
    return category
end

local function AddonLoaded(name)
    if name == addonName and not tracker then
        settings = ForeverQuestNavigatorDB
        if type(settings) ~= "table" then
            settings = {}
            ForeverQuestNavigatorDB = settings
        end
        settings.x = type(settings.x) == "number" and math.abs(settings.x) < math.huge and settings.x or 0
        settings.y = type(settings.y) == "number" and math.abs(settings.y) < math.huge and settings.y or 140
        settings.hidden = settings.hidden == true
        settings.includeElite = settings.includeElite ~= false
        tracker = addon.CreateQuestTracker(settings, SkipQuest, ResetSkips)
        local settingsCategory = RegisterSettings()

        events:RegisterEvent("PLAYER_ENTERING_WORLD")
        events:RegisterEvent("QUEST_LOG_UPDATE")
        events:RegisterEvent("QUEST_LOG_CRITERIA_UPDATE")
        events:RegisterEvent("QUEST_WATCH_UPDATE")
        events:RegisterEvent("QUEST_DATA_LOAD_RESULT")
        events:RegisterEvent("QUEST_ACCEPTED")
        events:RegisterEvent("QUEST_REMOVED")
        events:RegisterEvent("QUEST_TURNED_IN")

        SLASH_FOREVERQUESTNAVIGATOR1 = "/fqn"
        SlashCmdList.FOREVERQUESTNAVIGATOR = function(message)
            local command = message:match("^%s*(.-)%s*$"):lower()
            if command == "status" then
                print("FQN | Questie: " .. dependencies.Questie .. " | TomTom: " .. dependencies.TomTom)
            elseif command == "settings" then
                Settings.OpenToCategory(settingsCategory:GetID())
            elseif command == "" then
                tracker:SetShown(not tracker:IsShown())
            else
                print("FQN | /fqn toggles the tracker. /fqn settings opens options. /fqn status shows optional addons.")
            end
        end

        dependencies = addon.ReadDependencyStatus(C_AddOns)
        ScheduleRefresh()
    elseif tracker and (name == "Questie" or name == "TomTom") then
        dependencies = addon.ReadDependencyStatus(C_AddOns)
    end
end

events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(_, event, arg)
    if event == "ADDON_LOADED" then
        AddonLoaded(arg)
    else
        if event == "QUEST_REMOVED" then
            skippedQuestIDs[arg] = nil
            if currentQuestID == arg then
                currentQuestID = nil
            end
        end
        ScheduleRefresh()
    end
end)
