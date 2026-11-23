local _, addon = ...
local L = addon.L
local window
function addon.ShowZoneOverview(getGroups, openMap)
    if not window then
        window = addon.UI.CreateUtilityPanel(520, 48 + 7 * 54 + 50, L.ZoneOverview)
        window.rows = {}
        for index = 1, 7 do
            local row = addon.UI.CreateUtilityButton(window, "", 480, function() end)
            row:SetHeight(50)
            row.textLabel:ClearAllPoints()
            row.textLabel:SetPoint("LEFT", 10, 0)
            row.textLabel:SetPoint("RIGHT", -10, 0)
            row.textLabel:SetJustifyH("LEFT")
            row:SetPoint("TOPLEFT", 20, -48 - (index - 1) * 54)
            row:SetScript("OnClick", function(self) if self.group and self.group.marker then window.openMap(self.group.marker) end end)
            window.rows[index] = row
        end
        window.pageLabel = addon.UI.CreateLabel(window, "GameFontHighlightSmall")
        window.pageLabel:SetPoint("BOTTOMLEFT", 20, 20)
        local scroller = addon.UI.AttachScroller(window, window.rows, function() window:Refresh() end)
        function window:Refresh()
            local groups = self.getGroups()
            local offset = scroller:Clamp(#groups)
            for index, row in ipairs(self.rows) do
                local group = groups[offset + index]
                row.group = group
                row:SetShown(group ~= nil)
                if group then
                    local function Count(value, one, many) return (value == 1 and one or many):format(value) end
                    row:SetText(group.name .. " · " .. addon.UI.FormatDistance(group) .. "\n"
                        .. Count(group.quests, L.ZoneQuestOne, L.ZoneQuestMany) .. " · "
                        .. Count(group.objectives, L.ZoneObjectiveOne, L.ZoneObjectiveMany) .. " · "
                        .. Count(group.turnIns, L.ZoneTurnInOne, L.ZoneTurnInMany) .. "\n"
                        .. L.ZoneFit:format(group.suitable, group.difficult, group.low))
                end
            end
            scroller:Update(#groups)
            self.pageLabel:SetText(#groups == 0 and L.NoZoneQuests or "")
        end
        addon.UI.RefreshWhileShown(window, 1)
    end
    window.getGroups, window.openMap, window.offset = getGroups, openMap, 0
    window:Refresh()
    addon.UI.ShowUtilityPanel(window)
    return window
end
