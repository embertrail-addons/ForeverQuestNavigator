local _, addon = ...
function addon.CreateNavigatorViewport(owner, settings)
    local scroll = CreateFrame("ScrollFrame", nil, owner, "UIPanelScrollFrameTemplate")
    scroll.body = CreateFrame("Frame", nil, scroll)
    scroll.body:SetSize(owner:GetWidth(), 1)
    scroll:SetScrollChild(scroll.body)
    scroll.offset, scroll.maximum = 0, 0
    function scroll:ScrollBy(delta)
        self.offset = math.max(0, math.min(self.maximum, self.offset + delta))
        self:SetVerticalScroll(self.offset)
    end
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta) self:ScrollBy(-delta * 36) end)
    scroll:HookScript("OnVerticalScroll", function(self, offset)
        self.offset = math.max(0, math.min(self.maximum, offset or 0))
    end)
    function scroll:Layout(pinned, natural, footer)
        local retainedOffset = self.offset
        local previousWidth = self.body:GetWidth()
        local screen = UIParent.GetHeight and UIParent:GetHeight()
        local height, visible, maximum = addon.TrackerPresentation.ViewportHeight(pinned, natural, footer,
            settings.trackerMaxHeight, screen)
        self.maximum = maximum
        self:ClearAllPoints()
        self:SetPoint("TOPLEFT", owner, "TOPLEFT", 0, -pinned)
        self:SetPoint("TOPRIGHT", owner, "TOPRIGHT", maximum > 0 and -22 or 0, -pinned)
        self:SetHeight(visible)
        self.body:SetWidth(math.max(100, owner:GetWidth() - (maximum > 0 and 22 or 0)))
        self.body:SetHeight(math.max(1, natural))
        self.offset = retainedOffset
        self:ScrollBy(0)
        self.reflow = previousWidth ~= self.body:GetWidth()
        if self.ScrollBar then self.ScrollBar:SetShown(maximum > 0) end
        return height
    end
    return scroll
end
