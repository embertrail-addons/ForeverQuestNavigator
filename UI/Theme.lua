local _, addon = ...
local Theme = { entries = {}, contrast = false }
addon.UI.Theme = Theme
local palettes = {
    normal = { background = { .07, .06, .045 }, border = { .64, .46, .22 },
        heading = { 1, .82, .34 }, text = { 1, 1, 1 }, muted = { .67, .67, .67 },
        button = { .18, .15, .11 }, highlight = { .74, .55, .28 }, stripe = { .66, .47, .23 },
        active = { .26, .19, .10 }, recommended = { 1, .75, .28 } },
    contrast = { background = { .015, .015, .015 }, border = { 1, 1, 1 },
        heading = { 1, .94, .6 }, text = { 1, 1, 1 }, muted = { .87, .87, .87 },
        button = { .12, .12, .12 }, highlight = { .35, .7, 1 }, stripe = { .65, .8, 1 },
        active = { .08, .16, .24 }, recommended = { .5, .85, 1 } },
}
function Theme.Color(role)
    return unpack(palettes[Theme.contrast and "contrast" or "normal"][role])
end
local function Paint(entry)
    local r, g, b = Theme.Color(entry.role)
    if entry.kind == "text" then entry.region:SetTextColor(r, g, b)
    else entry.region:SetColorTexture(r, g, b, entry.alpha or 1) end
end
function Theme.Bind(region, role, alpha, kind)
    local entry = { region = region, role = role, alpha = alpha, kind = kind }
    Theme.entries[#Theme.entries + 1] = entry
    Paint(entry)
end
function Theme.Frame(frame, opacity)
    if frame.embedded then frame:SetBackdropColor(0, 0, 0, 0) frame:SetBackdropBorderColor(0, 0, 0, 0) return end
    local r, g, b = Theme.Color("background")
    frame:SetBackdropColor(r, g, b, opacity or 1)
    r, g, b = Theme.Color("border")
    frame:SetBackdropBorderColor(r, g, b, opacity or 1)
end
function Theme.Apply(contrast)
    Theme.contrast = contrast == true
    for _, entry in ipairs(Theme.entries) do Paint(entry) end
    for _, entry in ipairs(Theme.frames or {}) do Theme.Frame(entry.frame, entry.opacity and entry.opacity()) end
    if addon.UI.ToolHub and addon.UI.ToolHub.PaintNavigation then addon.UI.ToolHub.PaintNavigation() end
end
function Theme.WatchFrame(frame, opacity)
    Theme.frames = Theme.frames or {}
    Theme.frames[#Theme.frames + 1] = { frame = frame, opacity = opacity }
    Theme.Frame(frame, opacity and opacity())
end
