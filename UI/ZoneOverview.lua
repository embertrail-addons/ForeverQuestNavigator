local _, addon = ...
local L = addon.L
local window
function addon.ShowZoneOverview(getGroups, openMap)
    if not window then
        window = addon.UI.CreateUtilityPanel(520, 410, L.ZoneOverview)
        window.rows = {}
        for index = 1, 5 do
            local row = addon.UI.CreateUtilityButton(window, "", 480, function() end)
            row:SetHeight(54)
            row.textLabel:ClearAllPoints()
            row.textLabel:SetPoint("LEFT", 10, 0)
            row.textLabel:SetPoint("RIGHT", -10, 0)
            row.textLabel:SetJustifyH("LEFT")
            row:SetPoint("TOPLEFT", 20, -48 - (index - 1) * 61)
            row:SetScript("OnClick", function(self) if self.group and self.group.marker then window.openMap(self.group.marker) end end)
            window.rows[index] = row
        end
        window.previous = addon.UI.CreateUtilityButton(window, "<", 35, function() window.page = math.max(1, window.page - 1) window:Refresh() end)
        window.previous:SetPoint("BOTTOMLEFT", 20, 14)
        window.next = addon.UI.CreateUtilityButton(window, ">", 35, function() window.page = window.page + 1 window:Refresh() end)
        window.next:SetPoint("BOTTOMRIGHT", -20, 14)
        window.pageLabel = addon.UI.CreateLabel(window, "GameFontHighlightSmall")
        window.pageLabel:SetPoint("BOTTOM", 0, 20)
        function window:Refresh()
            local groups = self.getGroups()
            local pages = math.max(1, math.ceil(#groups / 5))
            self.page = math.min(self.page, pages)
            for index, row in ipairs(self.rows) do
                local group = groups[(self.page - 1) * 5 + index]
                row.group = group
                row:SetShown(group ~= nil)
                if group then
                    row:SetText(group.name .. " · " .. addon.UI.FormatDistance(group) .. "\n"
                        .. L.ZoneCounts:format(group.quests, group.objectives, group.turnIns) .. "\n"
                        .. L.ZoneFit:format(group.suitable, group.difficult, group.low))
                end
            end
            self.previous:SetEnabled(self.page > 1)
            self.next:SetEnabled(self.page < pages)
            self.pageLabel:SetText(#groups > 0 and (self.page .. " / " .. pages) or L.NoZoneQuests)
        end
        window:SetScript("OnUpdate", function(self, elapsed)
            self.elapsed = (self.elapsed or 0) + elapsed
            if self.elapsed >= 1 then self.elapsed = 0 self:Refresh() end
        end)
    end
    window.getGroups, window.openMap, window.page = getGroups, openMap, 1
    window:Refresh()
    window:Show()
end
