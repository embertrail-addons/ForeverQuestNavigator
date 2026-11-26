local _, addon = ...
local L = addon.L
local integration = addon.QuestieIntegration
-- Registration of all /fqn commands.
-- Installed by Core/Bootstrap.lua with the shared navigator state S and functions F.
addon.NavigatorCommands = {}

function addon.NavigatorCommands.Install(S, F)
    function F.RegisterCommands()
        local C = addon.Commands
        C.Reset()
        local function Add(key, group, label, run, options)
            local entry = {key = key, group = group, label = label, run = run}
            for name, value in pairs(options or {}) do entry[name] = value end
            C.Register(entry)
        end
        local function Print(text) print("FQN | " .. text) end
        Add("", "navigation", nil, function() F.ToggleTracker() end, {hidden = true})
        Add("settings", "settings", "CmdSettings", function() F.OpenSettings() end)
        Add("arrange", "settings", "CmdArrange", function() S.tracker:ArrangeUI() end)
        Add("tools", "navigation", "CmdTools", function() addon.UI.ToolHub.Open(addon.UI.ToolHub.key or "finder") end)
        Add("menu", "navigation", "CmdMenu", function() addon.ShowCommandMenu(S.settings) end)
        Add("find", "quests", "CmdFind", function(text)
            local panel = addon.OpenWorkspace("finder")
            if panel then panel.search:SetText(text or "") end
        end, {args = true})
        Add("tour", "quests", "CmdTour", function() addon.OpenWorkspace("tour") end, {advanced = true})
        Add("resume", "quests", "CmdResume", function() addon.ResumePlan() end, {advanced = true})
        Add("plan", "quests", "CmdPlan", function() F.ShowPlanning() end, {advanced = true})
        Add("assist", "quests", "CmdAssist", function() addon.OpenAdventure() end, {advanced = true})
        Add("zones", "quests", "CmdZones", function() F.ShowZones() end)
        Add("notes", "quests", "CmdNotes", function() F.ShowNotepad() end)
        Add("detour", "quests", "CmdDetour", function() addon.OpenDetourTools() end, {advanced = true})
        Add("report", "quests", "CmdReport", function()
            local quest = S.shownQuests and S.shownQuests[1]
            if quest then F.ShowTargetReport(quest.id) end
        end, {advanced = true})
        Add("session", "history", "CmdSession", function() F.ShowSession() end)
        Add("session reset", "history", "CmdSessionReset", function()
            local character = ForeverQuestNavigatorCharacterDB
            if character then
                character.sessionHistory = type(character.sessionHistory) == "table" and character.sessionHistory or {}
                addon.Session.Archive(character.sessionHistory, S.session, F.SessionTime(), GetServerTime and GetServerTime())
            end
            S.session = addon.Session.New(nil, F.SessionTime())
            ForeverQuestNavigatorCharacterDB.session = S.session.data
            F.CaptureSessionXP()
            F.ShowSession()
        end, {advanced = true})
        Add("session history", "history", "CmdSessionHistory", function()
            local character = ForeverQuestNavigatorCharacterDB
            addon.ShowTextWindow("sessionHistory", addon.Session.DescribeHistory(character and character.sessionHistory),
                addon.L.HistoryTitle, addon.L.HistoryHelp)
        end)
        Add("undo", "history", "CmdUndo", function() addon.UndoLastChange() end)
        Add("history", "history", "CmdHistory", function() addon.ShowUndoHistory(addon.Undo) end, {advanced = true})
        Add("levels", "history", "CmdLevels", function() F.ShowLevelChanges() end, {advanced = true})
        Add("feedback", "history", "CmdFeedback", function() F.ShowFeedback() end, {advanced = true})
        Add("profiles", "settings", "CmdProfiles", function() F.ShowProfiles() end)
        Add("share", "settings", "CmdShare", function()
            addon.ShowDisplayTransfer(S.settings, addon.SettingsController.catalog)
        end, {advanced = true})
        Add("access", "settings", "CmdAccess", function() F.ShowAccessManager() end, {advanced = true})
        Add("help", "help", "CmdHelp", function() addon.ShowIntroduction(S.settings) end)
        Add("setup", "help", "CmdSetup", function() F.ShowSetup() end)
        Add("whatsnew", "help", "CmdWhatsNew", function() addon.ShowReleaseNotes(S.settings, F.AddonVersion()) end)
        Add("demo", "help", "CmdDemo", function(text)
            addon.DemoMode.Command((text or ""):lower(), S.settings, S.tracker, function() F.UpdateMapMarker() F.ScheduleRefresh() end)
        end, {args = true})
        Add("status", "debug", "CmdStatus", function() Print("Questie: " .. addon.ReadQuestieStatus(C_AddOns)) end, {advanced = true})
        Add("debug", "debug", "CmdDebug", function() F.ShowDiagnostics() end, {advanced = true})
        Add("problem", "debug", "CmdProblem", function() addon.OpenProblemReport() end)
        Add("selftest", "debug", "CmdSelfTest", function() F.RunSelfTest() end)
        Add("selftest group", "debug", "CmdGroupTest", function() F.GroupTest(true) end, {advanced = true})
        Add("selftest group off", "debug", "CmdGroupTestOff", function() F.GroupTest(false) end, {advanced = true, menu = false})
        Add("tour share", "quests", "CmdTourShare", function() addon.ShareTour() end, {advanced = true})
        Add("tour chat", "quests", "CmdTourChat", function() addon.ShowTourChatPreview() end, {advanced = true})
        Add("marks", "quests", "CmdTargetMarks", function() addon.ToggleTargetMarks() end)
        Add("time", "quests", "CmdTimeTour", function(text) F.TimeTour(text) end, {args = true})
        Add("learn", "settings", "CmdLearn", function(text) F.Learned(text) end, {args = true, advanced = true})
        Add("profile", "settings", "CmdProfile", function() F.ToggleProfile() end, {advanced = true})
        Add("goal", "history", "CmdGoal", function(text)
            local character = ForeverQuestNavigatorCharacterDB
            if not character then return end
            local Goal = addon.DailyGoal
            local today = Goal.Today(GetServerTime and GetServerTime())
            if text == "" then print("FQN | " .. (F.GoalText() or addon.L.GoalNone)) return end
            if text == "off" or text == "aus" then Goal.Clear(character) print("FQN | " .. addon.L.GoalCleared) return end
            if Goal.Set(character, text, today, UnitLevel and UnitLevel("player")) then print("FQN | " .. (F.GoalText() or ""))
            else print("FQN | " .. addon.L.GoalInvalid) end
        end, {args = true})
        Add("fixture", "debug", "CmdFixture", function() F.ShowFixture() end, {advanced = true})
        Add("markers", "debug", "CmdMarkers", function()
            local marker = addon.GetMapMarkerStatus()
            Print(("mapMarkers: backend=%s count=%d target=%s"):format(marker.backend, marker.count, tostring(marker.hasTarget)))
            Print(marker.detail)
        end, {advanced = true})
        Add("activity", "debug", "CmdActivity", function()
            local active = S.shownQuests and S.shownQuests[1]
            local area = active and S.navigationSnapshot and S.navigationSnapshot.presence and S.navigationSnapshot.presence[active.id]
            local fight, body = S.insights.engagement, addon.RecoveryState
            Print(("activity: combatMatch=%s objective=%s area=%s recovery=%s corpse=%s"):format(
                tostring(fight and fight.questID or "none"), tostring(fight and fight.objectiveIndex or "none"),
                tostring(area and area.objectiveIndex or "none"), tostring(body and body.active == true),
                body and body.active and (body.exact and "native" or body.target and "last-death-position" or "unknown") or "none"))
        end, {advanced = true})
        Add("perf", "debug", "CmdPerf", function()
            addon.ShowTextWindow("performance", addon.Performance:Report(), L.PerformanceTitle, L.PerformanceHelp)
        end, {advanced = true})
        Add("perf on", "debug", "CmdPerfOn", function()
            Print(addon.Performance:Start() and L.PerformanceEnabled or L.PerformanceUnavailable)
        end, {advanced = true, menu = false})
        Add("perf off", "debug", "CmdPerfOff", function()
            addon.Performance.enabled = false Print(L.PerformanceDisabled)
        end, {advanced = true, menu = false})
    end
end
