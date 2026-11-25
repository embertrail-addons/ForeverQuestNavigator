local _, addon = ...
-- Shared sizing for compact multi-line actions in planning/navigation panels.
-- Reset anchors before reuse so theme and font changes cannot accumulate them.
function addon.UI.LayoutActionRow(button, y, width, scale, lines)
    button:ClearAllPoints() button:SetPoint("TOPLEFT", 0, -y) button:SetWidth(width)
    local label = button.textLabel or button:GetFontString()
    label:ClearAllPoints() label:SetPoint("LEFT", 7, 0) label:SetPoint("RIGHT", -7, 0)
    label:SetMaxLines(lines or 2) label:SetJustifyH("LEFT")
    button:SetHeight(math.max(26 * scale, label:GetStringHeight() + 10))
end
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
function addon.UI.ExpandHitArea(button, padding, vertical)
    vertical = vertical or padding
    if button.SetHitRectInsets then button:SetHitRectInsets(-padding, -padding, -vertical, -vertical) end
end

function addon.UI.FormatDistance(measurement, compact)
    if not measurement or type(measurement.yards) ~= "number" or measurement.yards ~= measurement.yards
        or measurement.yards < 0 or measurement.yards == math.huge then return "—" end
    if compact and measurement and measurement.yards >= 1000 then return ("~%.1fk yd"):format(measurement.yards / 1000) end
    return measurement and ("~%.0f yd"):format(measurement.yards) or "—"
end

function addon.UI.GetRowLineHeight(row)
    return math.max(addon.UI.Style.rowHeight, row.label:GetStringHeight() + 6, row.distance:GetStringHeight() + 6)
end

function addon.UI.AlignNavigationRow(row, height, lineHeight, inset, arrowSpace)
    local offset = (height - lineHeight) / 2
    local distanceWidth = math.max(76 * fontPercent / 100, row.distance:GetStringWidth() + 5)
    local actionWidth = row.detailButton and 22 * fontPercent / 100 or 0
    row:SetHeight(height)
    row.label:ClearAllPoints()
    row.label:SetPoint("LEFT", inset + (row.stateGlyph and row.stateGlyph:IsShown() and 16 or 0), offset)
    if row.stateGlyph then row.stateGlyph:ClearAllPoints() row.stateGlyph:SetPoint("LEFT", inset, offset) end
    row.label:SetPoint("RIGHT", -distanceWidth - arrowSpace - actionWidth, offset)
    row.distance:ClearAllPoints()
    row.distance:SetPoint("RIGHT", -actionWidth, offset)
    row.arrow:ClearAllPoints()
    row.arrow:SetPoint("RIGHT", -distanceWidth - 3 - actionWidth, offset)
    if row.detailButton then
        row.detailButton:SetSize(20 * fontPercent / 100, lineHeight)
        row.detailButton:ClearAllPoints()
        row.detailButton:SetPoint("RIGHT", 0, offset)
    end
    if row.checkbox then
        row.checkbox:ClearAllPoints()
        row.checkbox:SetPoint("LEFT", -2, offset)
    end
end

function addon.UI.CreateStateGlyph(parent)
    local glyph = addon.UI.CreateLabel(parent, "GameFontNormalSmall")
    glyph:SetWidth(13) glyph:SetJustifyH("CENTER")
    addon.UI.Theme.Bind(glyph, "muted", 1, "text")
    return glyph
end

function addon.UI.AddRowHighlight(row)
    local texture = row:CreateTexture(nil, "HIGHLIGHT")
    texture:SetAllPoints()
    addon.UI.Theme.Bind(texture, "highlight", addon.UI.Style.highlight[4])
    return texture
end

function addon.UI.LinkQuestHover(frame, getID, region)
    local texture = frame:CreateTexture(nil, "ARTWORK")
    texture:SetAllPoints(region or frame)
    texture:SetColorTexture(.2, .8, 1, .2)
    texture:Hide()
    local function Update(ids)
        local id = getID(frame)
        if addon.QuestHover.owner == frame and frame:IsShown() and id and not ids[id] then
            addon.QuestHover.Set(frame, {[id] = true}) return
        end
        texture:SetShown(frame:IsShown() and id ~= nil and ids[id] == true)
    end
    addon.QuestHover.Subscribe(Update)
    frame:HookScript("OnEnter", function(self)
        local id = getID(self)
        if id then addon.QuestHover.Set(self, {[id] = true}) end
    end)
    frame:HookScript("OnLeave", function(self) addon.QuestHover.Clear(self) end)
    frame:HookScript("OnHide", function(self) addon.QuestHover.Clear(self) texture:Hide() end)
    frame:HookScript("OnShow", function() Update(addon.QuestHover.ids) end)
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

-- omitState: leave out the trailing state word when the caller already names it (e.g. "Turn in: ...").
local function FormatQuestTitle(quest, colored, playerLevel, omitState)
    local title = quest.title
    if not title or title == "" then
        title = L.QuestNumber:format(quest.id)
    end
    local level = addon.QuestPrioritizer.GetLevel(quest)
    local result = level and ("[%d] %s"):format(level, title) or title
    local settings = addon.SettingsController and addon.SettingsController.settings
    local difficulty = addon.QuestPrioritizer.GetDifficulty(quest, playerLevel or (UnitLevel and UnitLevel("player")))
    if colored and level then
        local difficulty = addon.QuestPrioritizer.GetDifficulty(quest, playerLevel or (UnitLevel and UnitLevel("player")))
        local r, g, b = addon.UI.Theme.Color("difficulty_" .. (difficulty or "gray"))
        result = ("|cff%02x%02x%02x[%d]|r %s"):format(math.floor(r * 255), math.floor(g * 255), math.floor(b * 255), level, title)
    end
    -- Elite/group is marked by a symbol in every variant, not by colour alone.
    if quest.elite or quest.group then result = result .. " |cffffc447+|r" end
    if settings and settings.difficultyWords and difficulty and not (omitState and quest.readyToTurnIn) then
        result = result .. " · " .. (quest.readyToTurnIn and L.TurnInAction or L["DifficultyShort_" .. difficulty])
    end
    if quest.progress and quest.progress.nearly then result = result .. " (" .. L.NearlyDone .. ")" end
    return result
end

local function EnableTitleTooltip(row)
    addon.UI.BindTooltip(row, function(self)
        local quest = self.checkbox and self.checkbox.quest
        local detail = quest and (quest.demoDetails or addon.DescribeQuest and addon.DescribeQuest(quest, self.measurement)
            or addon.Recommendation.Describe(quest, self.measurement, UnitLevel and UnitLevel("player")))
        if quest then local _, state = addon.QuestState.Read(quest) detail = state .. "\n" .. (detail or "") end
        if self.compact then
            if self.routeDetails and self.routeDetails:GetText() then detail = (detail or "") .. "\n" .. self.routeDetails:GetText() end
            if self.reward and self.reward:GetText() then detail = (detail or "") .. "\n" .. self.reward:GetText() end
        end
        return self.label:GetText(), addon.TrackerPresentation.Summary(detail, 3) .. "\n" .. L.NavigatorDetailsHint
    end)
end

local function MakeButton(parent)
    local button = CreateFrame("Button", nil, parent)
    addon.UI.ExpandHitArea(button, 2)
    local label = addon.UI.CreateLabel(button, "GameFontHighlightSmall")
    label:SetPoint("CENTER")
    button:SetFontString(label)
    button.textLabel = label
    button:SetNormalFontObject(addon.UI.GetFont("GameFontHighlightSmall"))
    button:SetDisabledFontObject(addon.UI.GetFont("GameFontDisableSmall"))
    local background = button:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    addon.UI.Theme.Bind(background, "button")
    button.background = background
    addon.UI.AddRowHighlight(button)
    return button
end

-- Keeps a label on one line (cut with "…") so its box never grows taller than set.
function addon.UI.SingleLine(label)
    if label.SetWordWrap then label:SetWordWrap(false) end
    if label.SetNonSpaceWrap then label:SetNonSpaceWrap(false) end
    if label.SetJustifyV then label:SetJustifyV("TOP") end
    return label
end

-- One height for small action buttons (Map, ..., Why) so a row never mixes sizes.
function addon.UI.ButtonHeight(scale) return math.max(22, 20 * (scale or 1)) end

-- Text link: no button background, theme accent colour, sized to its text.
function addon.UI.StyleLink(button)
    if button.background then button.background:Hide() end
    button.isLink = true
    button:SetNormalFontObject(addon.UI.GetFont("GameFontNormalSmall"))
    addon.UI.Theme.Bind(button.textLabel, "heading", nil, "text")
    return button
end

-- Lays out shown link buttons left to right, wrapping into new lines. Returns the new y.
function addon.UI.FlowLinks(links, y, width, scale)
    local x, lineHeight, any = 0, math.max(18, 18 * (scale or 1)), false
    for _, button in ipairs(links) do
        if button:IsShown() then
            local label = button.textLabel
            label:ClearAllPoints() label:SetPoint("LEFT", 0, 0) label:SetMaxLines(1) label:SetJustifyH("LEFT")
            local linkWidth = math.min(width, (label:GetStringWidth() or 0) + 4)
            if x > 0 and x + linkWidth > width then x, y = 0, y + lineHeight + 2 end
            button:ClearAllPoints() button:SetPoint("TOPLEFT", x, -y) button:SetSize(linkWidth, lineHeight)
            x, any = x + linkWidth + 16, true
        end
    end
    return any and (y + lineHeight + 6) or y
end

local function AddRowBackground(row, index)
    local background = row:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    addon.UI.Theme.Bind(background, "stripe", index % 2 == 1 and 0.055 or 0.025)
end

local function CreateSkipCheckbox(parent, skipQuest)
    -- Keep the existing field name for callers; this is an action, not progress.
    local checkbox = MakeButton(parent)
    checkbox:SetSize(22, 22)
    checkbox:SetText("-")
    checkbox.textLabel:SetTextColor(addon.UI.Theme.Color("muted"))
    checkbox:SetScript("OnClick", function(self)
        if self.quest then skipQuest(self.quest) end
    end)
    checkbox:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L.SkipQuest)
        GameTooltip:AddLine(L.NavigatorSkipHint, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    checkbox:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return checkbox
end
addon.UI.FormatQuestTitle = FormatQuestTitle

-- Quest step symbols (Blizzard textures available in the classic client).
local actionIcons = {
    accept = "Interface\\GossipFrame\\AvailableQuestIcon",
    turnIn = "Interface\\GossipFrame\\ActiveQuestIcon",
    objective = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8",
    access = "Interface\\Icons\\INV_Misc_Map_01",
}
addon.UI.iconLabels = true

-- Share of the way to the current target already covered, measured from the
-- distance when this target was first shown. Moving away raises the start.
-- memory keeps {key, start}; returns nil when unknown or the leg is very short.
function addon.UI.DistanceProgress(memory, key, yards)
    if not key or type(yards) ~= "number" or yards ~= yards or yards < 0 then memory.key, memory.start = nil, nil return end
    if memory.key ~= key or yards > memory.start then memory.key, memory.start = key, yards end
    if memory.start < 40 then return end
    return math.max(0, math.min(1, 1 - yards / memory.start))
end
function addon.UI.ActionIcon(action, size)
    local texture = actionIcons[action] or actionIcons.objective
    return ("|T%s:%d|t"):format(texture, size or 14)
end
-- With symbols on, the icon replaces the action word; the word stays for tooltips.
function addon.UI.ActionText(action, word)
    if addon.UI.iconLabels then return addon.UI.ActionIcon(action) end
    return word
end
addon.UI.MakeButton = MakeButton
addon.UI.CreateSkipCheckbox = CreateSkipCheckbox
addon.UI.AddRowBackground = AddRowBackground
addon.UI.EnableTitleTooltip = EnableTitleTooltip
