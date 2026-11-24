local _, addon = ...
local window
function addon.ShowReleaseNotes(settings, version)
    if not window then
        window = addon.UI.CreateUtilityPanel(590, 370, addon.L.WhatsNew)
        window.text = addon.UI.CreateLabel(window, "GameFontHighlightSmall")
        window.text:SetPoint("TOPLEFT", 18, -50) window.text:SetPoint("TOPRIGHT", -18, -50)
        window.text:SetJustifyH("LEFT") window.text:SetMaxLines(30)
        window.toggle = addon.UI.CreateUtilityButton(window, "", 550, function()
            local value, control = not window.settings.showUpdateNotes, nil
            for _, entry in ipairs(addon.SettingsController.catalog or {}) do if entry.key == "showUpdateNotes" then control = entry.control break end end
            if control then control:SetValue(value) else window.settings.showUpdateNotes = value end
            window:RefreshToggle()
        end)
        window.toggle:SetPoint("BOTTOM", 0, 20)
        function window:RefreshToggle()
            self.toggle:SetText(addon.L.ShowUpdateNotes .. ": " .. (self.settings.showUpdateNotes and addon.L.SettingOn or addon.L.SettingOff))
        end
    end
    window.settings = settings
    window.text:SetText(addon.ReleaseNotes.Text(version)) window:RefreshToggle()
    window:SetHeight(math.max(370, window.text:GetStringHeight() + 116))
    settings.lastSeenVersion = version
    addon.UI.ShowUtilityPanel(window, "whatsnew")
    return window
end
