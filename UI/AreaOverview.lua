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

    function frame:Layout()
        if not data or settings.collapsed then self:Hide() return end
        self:Show()
        local expanded = settings.areaOverviewExpanded == true
        local objectives = (data.objectives == 1 and L.AreaObjectiveOne or L.AreaObjectiveMany):format(data.objectives)
        local turnIns = (data.turnIns == 1 and L.AreaTurnInOne or L.AreaTurnInMany):format(data.turnIns)
        header:SetText((expanded and "− " or "+ ") .. L.AreaSummary:format(objectives, turnIns))
        header:SetHeight(math.max(24, label:GetStringHeight() + 8))
        local y = header:GetHeight() + 3
        for index, row in ipairs(rows) do
            local entry = data.entries[index + offset]
            row:SetShown(expanded and entry ~= nil)
            row.entry = entry
            if row:IsShown() then
                local goals = (entry.objectives == 1 and L.AreaOpenObjectiveOne or L.AreaObjectives):format(entry.objectives)
                local detail = entry.action == "turnIn" and L.RouteTurnIn or goals
                row:SetText(addon.UI.FormatQuestTitle(entry.quest) .. "\n" .. detail .. (" · ~%d yd"):format(entry.yards))
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", 0, -y)
                row:SetPoint("TOPRIGHT", 0, -y)
                row:SetHeight(math.max(32, row:GetFontString():GetStringHeight() + 8))
                y = y + row:GetHeight() + 2
            end
        end
        self:SetHeight(y)
    end

    local function Scroll(_, delta)
        if not data then return end
        offset = math.max(0, math.min(offset - delta, #data.entries - 5))
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
        offset = math.min(offset, math.max(0, data and #data.entries - 5 or 0))
        for index = #rows + 1, math.min(5, data and #data.entries or 0) do
            local row = addon.UI.MakeButton(self)
            local text = row:GetFontString()
            text:ClearAllPoints()
            text:SetPoint("TOPLEFT", 6, -4)
            text:SetPoint("TOPRIGHT", -6, -4)
            text:SetJustifyH("LEFT")
            text:SetMaxLines(2)
            row:SetScript("OnClick", function(button) actions.openRouteStop(button.entry) end)
            row:SetScript("OnEnter", function(button)
                addon.UI.ShowTextTooltip(button, button:GetText(), L.ShowMapTarget)
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
