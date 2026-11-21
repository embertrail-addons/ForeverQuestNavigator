local _, addon = ...
local Theme = { entries = {}, contrast = false, design = "graphite" }
addon.UI.Theme = Theme
local palettes = {
    graphite = { background = { .045, .052, .065 }, border = { .26, .29, .34 },
        heading = { .91, .76, .43 }, text = { .93, .94, .96 }, muted = { .66, .70, .76 },
        button = { .105, .12, .15 }, highlight = { .43, .52, .65 }, stripe = { .50, .55, .64 },
        active = { .13, .15, .19 }, recommended = { .91, .76, .43 } },
    parchment = { background = { .075, .060, .043 }, border = { .44, .34, .22 },
        heading = { .92, .76, .48 }, text = { .97, .92, .82 }, muted = { .72, .66, .56 },
        button = { .17, .13, .09 }, highlight = { .65, .49, .29 }, stripe = { .57, .43, .29 },
        active = { .22, .16, .09 }, recommended = { .92, .76, .48 } },
    midnight = { background = { .025, .055, .075 }, border = { .16, .34, .40 },
        heading = { .38, .84, .82 }, text = { .90, .96, .98 }, muted = { .60, .74, .79 },
        button = { .055, .13, .17 }, highlight = { .20, .65, .68 }, stripe = { .22, .49, .57 },
        active = { .045, .18, .22 }, recommended = { .38, .84, .82 } },
    contrast = { background = { .015, .015, .015 }, border = { 1, 1, 1 },
        heading = { 1, .94, .6 }, text = { 1, 1, 1 }, muted = { .87, .87, .87 },
        button = { .12, .12, .12 }, highlight = { .35, .7, 1 }, stripe = { .65, .8, 1 },
        active = { .08, .16, .24 }, recommended = { .5, .85, 1 } },
}
local semantic = { success = {.40, .87, .59}, xp = {.47, .77, 1}, warning = {1, .68, .30},
        difficulty_red = {1, .37, .37}, difficulty_orange = {1, .65, .28}, difficulty_yellow = {.96, .83, .48},
        difficulty_green = {.48, .82, .54}, difficulty_gray = {.65, .68, .72} }
local backgroundRoles = {background=true, border=true, button=true, highlight=true, stripe=true, active=true}
function Theme.Color(role)
    local palette = palettes[Theme.contrast and "contrast" or Theme.design] or palettes.graphite
    if semantic[role] then
        if Theme.reducedColors or Theme.contrast then return unpack(palette.text) end
        return unpack(semantic[role])
    end
    return unpack(palette[role] or palette.text)
end
local function Paint(entry)
    local r, g, b = Theme.Color(entry.role)
    if entry.kind == "text" then entry.region:SetTextColor(r, g, b)
    else
        local background = backgroundRoles[entry.role]
        entry.region:SetColorTexture(r, g, b, (entry.alpha or 1) * (background and (Theme.opacity or 1) or 1))
    end
end
function Theme.SetOpacity(opacity)
    Theme.opacity = opacity
    for _, entry in ipairs(Theme.entries) do if entry.kind ~= "text" then Paint(entry) end end
end
function Theme.Bind(region, role, alpha, kind)
    local entry = { region = region, role = role, alpha = alpha, kind = kind }
    Theme.entries[#Theme.entries + 1] = entry
    Paint(entry)
end
function Theme.Frame(frame, opacity)
    if frame.embedded then frame:SetBackdropColor(0, 0, 0, 0) frame:SetBackdropBorderColor(0, 0, 0, 0) return end
    -- Utility dialogs are opaque. Navigator surfaces opt into their saved
    -- opacity explicitly; inheriting the global value made a newly opened
    -- tools window stay transparent until a palette change repainted it.
    local r, g, b = Theme.Color("background")
    frame:SetBackdropColor(r, g, b, opacity or 1)
    r, g, b = Theme.Color("border")
    frame:SetBackdropBorderColor(r, g, b, opacity or 1)
end
function Theme.Text(role, text)
    if not text or Theme.reducedColors then return text end
    local r, g, b = Theme.Color(role)
    return ("|cff%02x%02x%02x%s|r"):format(math.floor(r * 255), math.floor(g * 255), math.floor(b * 255), text)
end
function Theme.Apply(contrast, design, reducedColors)
    Theme.contrast = contrast == true
    if design ~= nil then Theme.design = palettes[design] and design or "graphite" end
    if reducedColors ~= nil then Theme.reducedColors = reducedColors == true end
    for _, entry in ipairs(Theme.entries) do Paint(entry) end
    for _, entry in ipairs(Theme.frames or {}) do Theme.Frame(entry.frame, entry.opacity and entry.opacity()) end
    if addon.UI.ToolHub and addon.UI.ToolHub.PaintNavigation then addon.UI.ToolHub.PaintNavigation() end
    for _, refresh in ipairs(Theme.listeners or {}) do refresh() end
end
function Theme.Subscribe(refresh)
    Theme.listeners = Theme.listeners or {}
    Theme.listeners[#Theme.listeners + 1] = refresh
end
function Theme.WatchFrame(frame, opacity)
    Theme.frames = Theme.frames or {}
    Theme.frames[#Theme.frames + 1] = { frame = frame, opacity = opacity }
    Theme.Frame(frame, opacity and opacity())
end
