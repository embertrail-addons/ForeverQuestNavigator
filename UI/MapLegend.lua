local _, addon = ...
function addon.UpdateMapLegend(map, target)
    if not map or not map.HookScript or not map.GetWidth then return end
    local legend = map.FQNLegend
    if not legend and target then
        legend = CreateFrame("Frame", nil, map)
        map.FQNLegend = legend legend:SetSize(500, 28)
        if map.GetFrameLevel then legend:SetFrameLevel(map:GetFrameLevel() + 30) end
        legend:SetPoint("BOTTOMLEFT", 18, 38)
        legend.explain = addon.UI.CreateUtilityButton(legend, addon.L.MapLegend, 160, function()
            addon.ShowTextWindow("mapLegend", addon.L.MapLegendHelp, addon.L.MapLegend, addon.L.MapLegendHelp)
        end)
        legend.explain:SetPoint("LEFT")
        legend.clear = addon.UI.CreateUtilityButton(legend, addon.L.ClearFQNMarkers, 172, function()
            if addon.ClearFQNMapMarkers then addon.ClearFQNMapMarkers() else addon.ShowQuestMapMarker() end
        end)
        legend.clear:SetPoint("RIGHT")
        legend.line = addon.UI.CreateUtilityButton(legend, addon.L.RouteLineShort, 150, function()
            if addon.ToggleRouteLine then addon.ToggleRouteLine() end
        end)
        legend.line:SetPoint("LEFT", legend.explain, "RIGHT", 8, 0)
        addon.UI.BindTooltip(legend.line, function() return addon.L.RouteLine, addon.L.RouteLineHelp end)
        addon.UI.BindTooltip(legend.explain, function() return addon.L.MapLegend, addon.L.MapLegendHelp end)
    end
    if legend then legend:SetShown(target ~= nil) end
end
