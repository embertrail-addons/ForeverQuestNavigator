local _, addon = ...
local L = addon.L
local wizard

-- Three-step first-run setup. Choices are applied only on Finish; Skip keeps defaults.
-- options: catalog, questie (bool), setDisplayMode(mode), done() (called after closing).
local function Steps(questie)
    return {
        {key = "display", title = L.SetupDisplayTitle, text = L.SetupDisplayText,
            choices = {{"full", L.SetupDisplayFull}, {"arrow", L.SetupDisplayArrow}}},
        {key = "questie", title = L.SetupQuestieTitle, text = questie and L.SetupQuestieText or L.SetupQuestieMissing,
            choices = questie and {{true, L.SetupQuestieOn}, {false, L.SetupQuestieOff}} or {}},
        {key = "level", title = L.SetupLevelTitle, text = L.SetupLevelText,
            choices = {{"simple", L.SetupLevelSimple}, {"standard", L.SetupLevelStandard}, {"expert", L.SetupLevelExpert}}},
    }
end

local function SetValue(settings, catalog, key, value)
    for _, entry in ipairs(catalog or {}) do
        if entry.key == key then
            if settings[key] ~= value then entry.control:SetValue(value) end
            return
        end
    end
    settings[key] = value
end

-- Pure: applies the chosen answers. Exposed for tests.
function addon.ApplySetupChoices(choices, settings, options)
    local catalog = options.catalog
    if choices.display and options.setDisplayMode then options.setDisplayMode(choices.display) end
    if choices.questie ~= nil then
        SetValue(settings, catalog, "showQuestieOffers", choices.questie)
        SetValue(settings, catalog, "useQuestieKillLocations", choices.questie)
    end
    local level = choices.level
    if level then
        SetValue(settings, catalog, "simpleNavigator", level == "simple")
        local profile = ({simple = "minimal", standard = "standard", expert = "detailed"})[level]
        if profile and addon.AppearanceProfiles and catalog then addon.AppearanceProfiles.Apply(profile, settings, catalog) end
    end
end

function addon.ShowSetup(settings, options)
    if not wizard then
        wizard = addon.UI.CreateUtilityPanel(500, 330, L.SetupTitle, {hub = false})
        wizard.stepTitle = addon.UI.CreateLabel(wizard, "GameFontNormal")
        wizard.stepTitle:SetPoint("TOPLEFT", 20, -48) wizard.stepTitle:SetPoint("TOPRIGHT", -20, -48)
        wizard.stepTitle:SetJustifyH("LEFT")
        wizard.body = addon.UI.CreateLabel(wizard, "GameFontHighlightSmall")
        wizard.body:SetPoint("TOPLEFT", 20, -72) wizard.body:SetPoint("TOPRIGHT", -20, -72)
        wizard.body:SetJustifyH("LEFT") wizard.body:SetMaxLines(4)
        wizard.choiceButtons = {}
        for index = 1, 3 do
            local button = addon.UI.CreateUtilityButton(wizard, "", 460, function(self)
                wizard.choices[wizard.steps[wizard.step].key] = self.value
                wizard:Refresh()
            end)
            button:SetPoint("TOPLEFT", 20, -140 - (index - 1) * 34)
            wizard.choiceButtons[index] = button
        end
        wizard.counter = addon.UI.CreateLabel(wizard, "GameFontDisableSmall")
        wizard.counter:SetPoint("BOTTOM", 0, 26)
        wizard.skip = addon.UI.CreateUtilityButton(wizard, L.SetupSkip, 150, function()
            wizard.choices = {} wizard:Hide()
        end)
        wizard.skip:SetPoint("BOTTOMLEFT", 20, 20)
        wizard.next = addon.UI.CreateUtilityButton(wizard, L.NextIntro, 150, function()
            if wizard.step < #wizard.steps then wizard.step = wizard.step + 1 wizard:Refresh()
            else wizard.finished = true wizard:Hide() end
        end)
        wizard.next:SetPoint("BOTTOMRIGHT", -20, 20)
        wizard.back = addon.UI.CreateUtilityButton(wizard, "<", 40, function()
            wizard.step = math.max(1, wizard.step - 1) wizard:Refresh()
        end)
        wizard.back:SetPoint("RIGHT", wizard.next, "LEFT", -8, 0)
        function wizard:Refresh()
            local step = self.steps[self.step]
            self.stepTitle:SetText(step.title)
            self.body:SetText(step.text)
            local selected = self.choices[step.key]
            if selected == nil then selected = self.current[step.key] end
            for index, button in ipairs(self.choiceButtons) do
                local choice = step.choices[index]
                button:SetShown(choice ~= nil)
                if choice then
                    button.value = choice[1]
                    button:SetText((selected == choice[1] and "> " or "") .. choice[2])
                end
            end
            self.counter:SetText(("%d / %d"):format(self.step, #self.steps))
            self.back:SetEnabled(self.step > 1)
            self.next:SetText(self.step == #self.steps and L.SetupFinish or L.NextIntro)
        end
        wizard:HookScript("OnHide", function(self)
            self.settings.setupDone = true
            if self.finished then addon.ApplySetupChoices(self.choices, self.settings, self.options) end
            local done = self.options.done
            self.finished = nil
            if done then done() end
        end)
    end
    wizard.settings, wizard.options = settings, options or {}
    wizard.steps, wizard.step, wizard.finished = Steps(wizard.options.questie == true), 1, nil
    -- current only marks today's state; only clicked choices are applied on Finish.
    wizard.choices = {}
    wizard.current = {display = settings.displayMode == "arrow" and "arrow" or "full",
        questie = settings.showQuestieOffers ~= false, level = settings.simpleNavigator and "simple" or nil}
    wizard:Refresh()
    wizard:Show()
    return wizard
end
