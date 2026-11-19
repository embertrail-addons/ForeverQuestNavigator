local _, addon = ...
local Notes = {}
addon.ReleaseNotes = Notes
function Notes.Initialize(settings, version, existing)
    settings.showUpdateNotes = settings.showUpdateNotes ~= false
    local previous = settings.lastSeenVersion
    local pending = existing and previous ~= version and settings.showUpdateNotes
    if not existing or not settings.showUpdateNotes then settings.lastSeenVersion = version end
    return pending and version or nil
end
function Notes.Text(version)
    return "Forever Quest Navigator " .. tostring(version or "") .. "\n\n" .. addon.L.UpdateNotesText
end
