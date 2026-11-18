local _, addon = ...
local L = addon.L
local ShowTextTooltip = addon.UI.ShowTextTooltip
local HideTextTooltip = addon.UI.HideTextTooltip

local labels = {}
local fonts = {}
local fontPercent = 100

-- Shared row geometry and colours keep accepted quests, offers and objectives
-- consistent without changing the user's background opacity or text opacity.
addon.UI.Style = {
    rowHeight = 22,
    detailGap = 2,
    highlight = { 0.74, 0.55, 0.28, 0.19 },
    stripe = { 0.66, 0.47, 0.23 },
}

function addon.UI.FormatDistance(measurement, compact)
    if compact and measurement and measurement.yards >= 1000 then return ("~%.1fk yd"):format(measurement.yards / 1000) end
    return measurement and ("~%.0f yd"):format(measurement.yards) or "—"
end

function addon.UI.GetRowLineHeight(row)
    return math.max(addon.UI.Style.rowHeight, row.label:GetStringHeight() + 6, row.distance:GetStringHeight() + 6)
end

function addon.UI.AlignNavigationRow(row, height, lineHeight, inset, arrowSpace)
    local offset = (height - lineHeight) / 2
    local distanceWidth = math.max(60, row.distance:GetStringWidth() + 5)
    row:SetHeight(height)
    row.label:ClearAllPoints()
    row.label:SetPoint("LEFT", inset, offset)
    row.label:SetPoint("RIGHT", -distanceWidth - arrowSpace, offset)
    row.distance:ClearAllPoints()
    row.distance:SetPoint("RIGHT", 0, offset)
    row.arrow:ClearAllPoints()
    row.arrow:SetPoint("RIGHT", -distanceWidth - 3, offset)
    if row.checkbox then
        row.checkbox:ClearAllPoints()
        row.checkbox:SetPoint("LEFT", -2, offset)
    end
end

function addon.UI.AddRowHighlight(row)
    local texture = row:CreateTexture(nil, "HIGHLIGHT")
    texture:SetAllPoints()
    addon.UI.Theme.Bind(texture, "highlight", addon.UI.Style.highlight[4])
    return texture
end

function addon.UI.BindTooltip(frame, content)
    frame:SetScript("OnEnter", function(self)
        local heading, detail = content(self)
        ShowTextTooltip(self, heading, detail)
    end)
    frame:SetScript("OnLeave", HideTextTooltip)
    frame:SetScript("OnHide", HideTextTooltip)
end

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
    addon.UI.Theme.Bind(label, font:find("Normal") and "heading" or (font:find("Disable") and "muted" or "text"), nil, "text")
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
    if quest.progress and quest.progress.nearly then result = result .. " |cff80cc80(" .. L.NearlyDone .. ")|r" end
    return result
end

local function EnableTitleTooltip(row)
    addon.UI.BindTooltip(row, function(self)
        local quest = self.checkbox and self.checkbox.quest
        local detail = quest and (addon.DescribeQuest and addon.DescribeQuest(quest, self.measurement)
            or addon.Recommendation.Describe(quest, self.measurement, UnitLevel and UnitLevel("player")))
        if self.compact then
            if self.routeDetails and self.routeDetails:GetText() then detail = (detail or "") .. "\n" .. self.routeDetails:GetText() end
            if self.reward and self.reward:GetText() then detail = (detail or "") .. "\n" .. self.reward:GetText() end
        end
        return self.label:GetText(), detail
    end)
end

local function MakeButton(parent)
    local button = CreateFrame("Button", nil, parent)
    local label = addon.UI.CreateLabel(button, "GameFontHighlightSmall")
    label:SetPoint("CENTER")
    button:SetFontString(label)
    button.textLabel = label
    button:SetNormalFontObject(addon.UI.GetFont("GameFontHighlightSmall"))
    button:SetDisabledFontObject(addon.UI.GetFont("GameFontDisableSmall"))
    local background = button:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    addon.UI.Theme.Bind(background, "button")
    addon.UI.AddRowHighlight(button)
    return button
end

local function AddRowBackground(row, index)
    local background = row:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    addon.UI.Theme.Bind(background, "stripe", index % 2 == 1 and 0.11 or 0.045)
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
