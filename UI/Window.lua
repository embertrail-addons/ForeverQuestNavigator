local _, addon = ...
-- Shared window chrome for every FQN panel: themed backdrop, title, close button,
-- dragging, ESC to close and (by default) embedding into the tools window.
local windowSerial = 0

-- options.hub = false keeps the window standalone (e.g. copy/text windows).
function addon.UI.CreateWindow(width, height, title, options)
    options = options or {}
    windowSerial = windowSerial + 1
    local name = "ForeverQuestNavigatorPanel" .. windowSerial
    local frame = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
    if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, name) end
    frame:SetSize(width, height)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetBackdrop({ bgFile = "Interface/Buttons/WHITE8X8", edgeFile = "Interface/Buttons/WHITE8X8", edgeSize = 1 })
    addon.UI.Theme.WatchFrame(frame)
    frame.heading = addon.UI.CreateLabel(frame, "GameFontNormal")
    frame.heading:SetPoint("TOPLEFT", 16, -14)
    frame.heading:SetPoint("TOPRIGHT", -45, -14)
    frame.heading:SetJustifyH("LEFT")
    frame.heading:SetText(title)
    local close = addon.UI.MakeButton(frame)
    close:SetSize(25, 24)
    close:SetPoint("TOPRIGHT", -8, -8)
    close:SetText("×")
    close:SetScript("OnClick", function() frame:Hide() end)
    addon.UI.ExpandHitArea(close, 3)
    frame.closeButton = close
    frame:Hide()
    if options.hub ~= false and addon.UI.ToolHub then addon.UI.ToolHub.Attach(frame, title) end
    return frame
end

function addon.UI.CreateWindowButton(parent, text, width, action)
    local button = addon.UI.MakeButton(parent)
    button:SetSize(width, 24)
    button:SetText(text)
    button:SetScript("OnClick", action)
    addon.UI.ExpandHitArea(button, 2)
    return button
end

-- Calls frame:Refresh() every `interval` seconds; OnUpdate only runs while shown.
function addon.UI.RefreshWhileShown(frame, interval)
    interval = interval or 1
    frame:SetScript("OnUpdate", function(self, elapsed)
        self.elapsed = (self.elapsed or 0) + elapsed
        if self.elapsed >= interval then self.elapsed = 0 self:Refresh() end
    end)
end

-- Compatibility names used across the UI files.
addon.UI.CreateUtilityPanel = addon.UI.CreateWindow
addon.UI.CreateUtilityButton = addon.UI.CreateWindowButton
