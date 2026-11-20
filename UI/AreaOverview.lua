local _, addon = ...
local L = addon.L

function addon.CreateAreaOverview(parent, settings, actions)
    local frame = CreateFrame("Frame", nil, parent)
    local header = addon.UI.MakeButton(frame)
    header:SetPoint("TOPLEFT")
    header:SetPoint("TOPRIGHT")
    local label = header:GetFontString()
    label:ClearAllPoints()
    label:SetPoint("TOPLEFT", 6, -4)
    label:SetPoint("TOPRIGHT", -6, -4)
    label:SetJustifyH("LEFT")
    label:SetMaxLines(2)
    local rows, data, offset = {}, nil, 0
    settings.targetGroupsExpanded = type(settings.targetGroupsExpanded) == "table" and settings.targetGroupsExpanded or {}

    local function VisibleEntries()
        local entries = {}
        for _, group in ipairs(data and data.groups or {}) do
            if #group.entries == 1 then
                entries[#entries + 1] = { entry = group.entries[1] }
            else
                entries[#entries + 1] = { group = group }
                if settings.targetGroupsExpanded[group.key] then
                    for _, entry in ipairs(group.entries) do entries[#entries + 1] = { entry = entry } end
                end
            end
        end
        return entries
    end

    function frame:Layout()
        if not data or settings.collapsed or ((data.objectives or 0) == 0 and (data.turnIns or 0) == 0) then
            self:Hide() return
        end
        self:Show()
        local expanded = settings.areaOverviewExpanded == true
        local objectives = (data.objectives == 1 and L.AreaObjectiveOne or L.AreaObjectiveMany):format(data.objectives)
        local turnIns = (data.turnIns == 1 and L.AreaTurnInOne or L.AreaTurnInMany):format(data.turnIns)
        header:SetText((expanded and "− " or "+ ") .. L.AreaSummary:format(objectives, turnIns))
        header:SetHeight(math.max(24, label:GetStringHeight() + 8))
        local y = header:GetHeight() + 3
        local visible = VisibleEntries()
        offset = math.min(offset, math.max(0, #visible - 5))
        for index, row in ipairs(rows) do
            local item = visible[index + offset]
            row:SetShown(expanded and item ~= nil)
            row.entry, row.group = item and item.entry, item and item.group
            if row:IsShown() then
                local entry, group = row.entry, row.group
                if group then
                    local prefix = settings.targetGroupsExpanded[group.key] and "− " or "+ "
                    row:SetText(prefix .. L.TargetGroup:format(#group.entries, group.place))
                else
                    local goals = (entry.objectives == 1 and L.AreaOpenObjectiveOne or L.AreaObjectives):format(entry.objectives)
                    local detail = entry.action == "turnIn" and L.RouteTurnIn or goals
                    row:SetText("  " .. addon.UI.FormatQuestTitle(entry.quest) .. "\n" .. detail .. (" · ~%d yd"):format(entry.yards))
                end
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", 0, -y)
                row:SetPoint("TOPRIGHT", 0, -y)
                row:SetHeight(math.max(row.group and 24 or 32, row:GetFontString():GetStringHeight() + 8))
                y = y + row:GetHeight() + 2
            end
        end
        self:SetHeight(y)
    end

    local function Scroll(_, delta)
        if not data then return end
        offset = math.max(0, math.min(offset - delta, #VisibleEntries() - 5))
        frame:Layout()
        actions.onLayout()
    end
    header:EnableMouseWheel(true)
    header:SetScript("OnMouseWheel", Scroll)
    header:SetScript("OnClick", function()
        settings.areaOverviewExpanded = not settings.areaOverviewExpanded
        frame:Layout()
        actions.onLayout()
    end)
    header:SetScript("OnEnter", function(self)
        addon.UI.ShowTextTooltip(self, data and data.zoneName or L.AreaOverview, L.AreaOverviewHelp)
    end)
    header:SetScript("OnLeave", addon.UI.HideTextTooltip)
    header:SetScript("OnHide", addon.UI.HideTextTooltip)

    function frame:SetData(value)
        data = value
        offset = math.min(offset, math.max(0, #VisibleEntries() - 5))
        for index = #rows + 1, 5 do
            local row = addon.UI.MakeButton(self)
            local text = row:GetFontString()
            text:ClearAllPoints()
            text:SetPoint("TOPLEFT", 6, -4)
            text:SetPoint("TOPRIGHT", -6, -4)
            text:SetJustifyH("LEFT")
            text:SetMaxLines(2)
            row:SetScript("OnClick", function(button)
                if button.group then
                    local key = button.group.key
                    settings.targetGroupsExpanded[key] = not settings.targetGroupsExpanded[key]
                    frame:Layout()
                    actions.onLayout()
                elseif button.entry then
                    actions.openRouteStop(button.entry)
                end
            end)
            row:SetScript("OnEnter", function(button)
                addon.UI.ShowTextTooltip(button, button:GetText(), button.group and L.TargetGroupHelp or L.ShowMapTarget)
            end)
            row:SetScript("OnLeave", addon.UI.HideTextTooltip)
            row:SetScript("OnHide", addon.UI.HideTextTooltip)
            row:EnableMouseWheel(true)
            row:SetScript("OnMouseWheel", Scroll)
            rows[index] = row
        end
        self:Layout()
    end

    frame:Hide()
    return frame
end
