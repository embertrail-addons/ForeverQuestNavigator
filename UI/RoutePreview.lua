local _, addon = ...
local L = addon.L

function addon.CreateRoutePreview(parent, actions)
    local frame = CreateFrame("Frame", nil, parent)
    local heading = addon.UI.CreateLabel(frame, "GameFontNormalSmall")
    heading:SetPoint("TOPLEFT")
    heading:SetText(L.RoutePreview)
    local rows = {}
    local count = 0

    function frame:Layout()
        local y = heading:GetStringHeight() + 5
        for index, row in ipairs(rows) do
            row:SetShown(index <= count)
            if row:IsShown() then
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", 0, -y)
                row:SetPoint("TOPRIGHT", 0, -y)
                row:SetHeight(math.max(22, row.label:GetStringHeight() + 8))
                y = y + row:GetHeight() + 2
            end
        end
        self:SetHeight(y)
    end

    function frame:Render(stops)
        count = math.min(stops and #stops or 0, 3)
        for index = 1, count do
            local row = rows[index]
            if not row then
                row = addon.UI.MakeButton(self)
                row.label = row:GetFontString()
                row.label:ClearAllPoints()
                row.label:SetPoint("TOPLEFT", 6, -4)
                row.label:SetPoint("TOPRIGHT", -6, -4)
                row.label:SetJustifyH("LEFT")
                row.label:SetMaxLines(2)
                row:SetScript("OnClick", function(button) actions.openRouteStop(button.stop) end)
                row:SetScript("OnEnter", function(button)
                    local origin = button.stop.current and L.RouteFromPlayer or L.RouteFromPrevious
                    local detail = origin .. "\n" .. L.ShowMapTarget
                    if button.stop.current then detail = L.RouteCurrent .. "\n" .. detail end
                    addon.UI.ShowTextTooltip(button, button:GetText(), detail)
                end)
                row:SetScript("OnLeave", addon.UI.HideTextTooltip)
                row:SetScript("OnHide", addon.UI.HideTextTooltip)
                rows[index] = row
            end
            local stop = stops[index]
            row.stop = stop
            local action = ({ accept = L.RouteAccept, objective = L.RouteObjective, turnIn = L.RouteTurnIn, access = L.SavedAccess })[stop.action]
            local text = (stop.current and "> " or "") .. (action or L.RouteObjective)
                .. " · " .. addon.UI.FormatQuestTitle(stop.quest)
            if stop.yards then text = text .. (" · ~%.0f yd"):format(stop.yards) end
            row:SetText(text)
            row.label:SetTextColor(1, stop.current and 0.82 or 1, stop.current and 0.34 or 1)
        end
        self:Layout()
    end

    function frame:SetExpanded(expanded)
        self:SetShown(expanded and count > 0)
    end

    frame:Hide()
    return frame
end
