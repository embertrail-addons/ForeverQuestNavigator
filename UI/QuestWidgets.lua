local _, addon = ...
local L = addon.L
local ShowTextTooltip = addon.UI.ShowTextTooltip
local HideTextTooltip = addon.UI.HideTextTooltip
local FullTextIfTruncated = addon.UI.FullTextIfTruncated

local labels = {}
local fonts = {}
local fontPercent = 100

function addon.UI.GetFont(name)
    local entry = fonts[name]
    if not entry then
        local font = CreateFont("ForeverQuestNavigator_" .. name)
        font:SetFontObject(name)
        local path, size, flags = font:GetFont()
        entry = { font = font, path = path, size = size, flags = flags }
        fonts[name] = entry
        font:SetFont(path, size * fontPercent / 100, flags)
    end
    return entry.font
end

function addon.UI.CreateLabel(parent, font)
    local label = parent:CreateFontString(nil, "OVERLAY", font)
    label:SetFontObject(addon.UI.GetFont(font))
    local entry = fonts[font]
    local path, size, flags = entry.path, entry.size, entry.flags
    labels[#labels + 1] = { label = label, path = path, size = size, flags = flags }
    label:SetFont(path, size * fontPercent / 100, flags)
    return label
end

function addon.UI.SetFontSize(percent)
    fontPercent = percent
    for _, entry in pairs(fonts) do
        entry.font:SetFont(entry.path, entry.size * percent / 100, entry.flags)
    end
    for _, entry in ipairs(labels) do
        entry.label:SetFont(entry.path, entry.size * percent / 100, entry.flags)
    end
end

local function FormatQuestTitle(quest)
    local title = quest.title
    if not title or title == "" then
        title = L.QuestNumber:format(quest.id)
    end
    local level = addon.QuestPrioritizer.GetLevel(quest)
    local result = level and ("[%d] %s"):format(level, title) or title
    if quest.elite or quest.group then result = result .. " |cffffc447+|r" end
    return result
end

local function EnableTitleTooltip(row)
    row:SetScript("OnEnter", function(self)
        local quest = self.checkbox and self.checkbox.quest
        local group = quest and (quest.elite or quest.group) and L.GroupQuest or nil
        ShowTextTooltip(self, group and self.label:GetText() or FullTextIfTruncated(self.label), group)
    end)
    row:SetScript("OnLeave", HideTextTooltip)
    row:SetScript("OnHide", HideTextTooltip)
end

local function MakeButton(parent)
    local button = CreateFrame("Button", nil, parent)
    local label = addon.UI.CreateLabel(button, "GameFontHighlightSmall")
    label:SetPoint("CENTER")
    button:SetFontString(label)
    button:SetNormalFontObject(addon.UI.GetFont("GameFontHighlightSmall"))
    button:SetDisabledFontObject(addon.UI.GetFont("GameFontDisableSmall"))
    local background = button:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(0.18, 0.15, 0.11, 1)
    local highlight = button:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(0.74, 0.55, 0.28, 0.19)
    return button
end

local function AddRowBackground(row, index)
    local background = row:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(0.66, 0.47, 0.23, index % 2 == 1 and 0.11 or 0.045)
end

local function CreateSkipCheckbox(parent, skipQuest)
    local checkbox = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    checkbox:SetSize(22, 22)
    checkbox:SetScript("OnClick", function(self)
        self:SetChecked(false)
        skipQuest(self.quest)
    end)
    checkbox:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L.SkipQuest)
        GameTooltip:Show()
    end)
    checkbox:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return checkbox
end
addon.UI.FormatQuestTitle = FormatQuestTitle
addon.UI.MakeButton = MakeButton
addon.UI.CreateSkipCheckbox = CreateSkipCheckbox
addon.UI.AddRowBackground = AddRowBackground
addon.UI.EnableTitleTooltip = EnableTitleTooltip
