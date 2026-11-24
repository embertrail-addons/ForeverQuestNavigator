local _, addon = ...
-- Optional small arrow on the minimap edge pointing to the current target.
local Arrow = {}
addon.MinimapArrow = Arrow

-- right/forward: target direction relative to the player's facing (forward = ahead).
-- facing: GetPlayerFacing() radians, counter-clockwise from north.
-- Returns the angle clockwise from the top of the minimap and the unit offset.
function Arrow.Place(right, forward, facing, rotating)
    if type(right) ~= "number" or type(forward) ~= "number" or (right == 0 and forward == 0) then return end
    local relative = math.atan2(right, forward)
    local angle = rotating and relative or (relative - (facing or 0))
    return angle, math.sin(angle), math.cos(angle)
end

local function Ensure()
    if Arrow.frame or not (Minimap and CreateFrame) then return Arrow.frame end
    local frame = CreateFrame("Frame", nil, Minimap)
    frame:SetSize(18, 18)
    if frame.SetFrameLevel and Minimap.GetFrameLevel then frame:SetFrameLevel(Minimap:GetFrameLevel() + 8) end
    frame.icon = frame:CreateTexture(nil, "OVERLAY")
    frame.icon:SetAllPoints()
    frame.icon:SetTexture("Interface\\Minimap\\MiniMap-QuestArrow")
    frame:Hide()
    Arrow.frame = frame
    return frame
end

function Arrow.Update(settings, right, forward, facing)
    local show = settings and settings.minimapArrow == true and facing ~= nil
    local angle, x, y
    if show then angle, x, y = Arrow.Place(right, forward, facing, GetCVar and GetCVar("rotateMinimap") == "1") end
    if not angle then
        if Arrow.frame then Arrow.frame:Hide() end
        return
    end
    local frame = Ensure()
    if not frame then return end
    local radius = (Minimap.GetWidth and Minimap:GetWidth() or 140) / 2 - 8
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", Minimap, "CENTER", x * radius, y * radius)
    if frame.icon.SetRotation then frame.icon:SetRotation(-angle) end
    frame:Show()
    Arrow.angle = angle
end
