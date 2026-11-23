local _, addon = ...
local Notes = {}
addon.ReleaseNotes = Notes

-- Newest first. Only the latest few versions are shown; full history lives in release/.
Notes.history = {
    {version = "0.2.0",
        en = "• Setup on first start, Simple/Expert mode and one tool window with an On the road group.\n• /fqn menu and minimap right-click list all commands; quest symbols replace action words.\n• Route line on the world map, level forecast over several turn-ins and a session recap.\n• Optional group sync (off by default) shares quest progress with your party.",
        de = "• Einrichtung beim ersten Start, Einfach-/Expertenmodus und ein Werkzeugfenster mit der Gruppe Unterwegs.\n• /fqn menu und Rechtsklick auf den Minimap-Button zeigen alle Befehle; Questsymbole ersetzen Aktionswörter.\n• Routenlinie auf der Weltkarte, Stufenprognose über mehrere Abgaben und Sitzungsrückblick.\n• Optionaler Gruppenabgleich (standardmäßig aus) teilt Questfortschritt mit deiner Gruppe."},
    {version = "0.1.84",
        en = "• Recognize local Questie spawn neighborhoods and matching enemies you are fighting when their identity is public.\n• Death/ghost navigation prioritizes a stable corpse destination; unknown corpse data never falls back to quests.\n",
        de = "• Lokale Questie-Spawngebiete und passende Kampfgegner erkennen, soweit deren Identität öffentlich verfügbar ist.\n• Tot / als Geist hat ein stabiles Leichnam-Ziel Vorrang; unbekannte Leichnamdaten führen nicht zu Questpfeilen.\n"},
    {version = "0.1.83",
        en = "• Mixed rounds place pickups between objectives and hand-ins, with known coordinate detours and quest-log capacity.\n• Skip one pickup, remind later or hide per character; restore hidden pickups separately and undo unchanged plans.\n• Actual acceptance pauses for a target review before explicit resume.\n" .. "• Hand-ins on the way with explicit detour previews; contextual reminders and tour comparisons.\n• Bag/visited-merchant checks, clearer item actions and expandable chains.\n• Simpler navigation, grouped tools, explicit Details and content-sized panels.\n" .. "• Tour assistant: departure checks, alternatives, optional native group checks, level-up review and explicit tour revisions.\n• Optional timed previews, resettable personal targets, direct action text and difficulty words.\n" .. "• Review area tours directly; pickups must fit the round to earn a strong highlight.\n• One Next action, contextual return advice and a dismissible recap with actual quest XP.\n",
        de = "• Gemischte Runden ordnen Annahmen zwischen Zielen und Abgaben ein; bekannte Umwege und Questplätze zählen mit.\n• Annahme auslassen, später merken oder pro Charakter ausblenden; getrennt wieder aufnehmen und unveränderte Pläne rückgängig machen.\n• Nach tatsächlicher Annahme Ziele prüfen und ausdrücklich fortsetzen.\n" .. "• Abgaben unterwegs mit Umwegvorschau; passende Vormerkungen und Tourvergleiche.\n• Taschen- und Händlerprüfung, klarere Gegenstandsaktionen und aufklappbare Questketten.\n• Einfacher Navigator, gruppierte Werkzeuge, sichtbare Details und Fenster passend zum Inhalt.\n" .. "• Tourhelfer: Abreiseprüfung, Ausweichziele, freiwillige Gruppenprüfung, Aufstiegsübersicht und ausdrückliche Touränderungen.\n• Zeitlich begrenzte Vorschauen, zurücksetzbare eigene Ziele, klare Handlungstexte und Schwierigkeitswörter.\n" .. "• Gebietstouren direkt prüfen; starke Annahmeempfehlungen berücksichtigen die Runde.\n• Ein nächster Schritt, passende Rückkehrhinweise und schließbarer Rückblick mit tatsächlich erhaltenen Quest-EP.\n"},
    {version = "0.1.79",
        en = "• Reviewed outings: pickups, objectives and known hand-ins; explicit start/pause/resume.\n• Compare stable spawn areas; known access lengths influence ranking.\n• Repeatable filters, starter requirements, personal notes, map legend and clearer settings.\n",
        de = "• Geprüfte Ausflüge mit Annahmen, Zielen und bekannten Abgaben; ausdrücklich starten, pausieren und fortsetzen.\n• Stabile Spawngebiete vergleichen; bekannte Zugangswege zählen bei der Bewertung.\n• Wiederholungsfilter, Annahmevoraussetzungen, persönliche Notizen, Kartenlegende und klarere Einstellungen.\n"},
}
Notes.shown = 3

function Notes.Initialize(settings, version, existing)
    settings.showUpdateNotes = settings.showUpdateNotes ~= false
    local previous = settings.lastSeenVersion
    local pending = existing and previous ~= version and settings.showUpdateNotes
    if not existing or not settings.showUpdateNotes then settings.lastSeenVersion = version end
    return pending and version or nil
end

function Notes.Text(version, language)
    language = language or addon.L.LanguageCode
    local parts = {"Forever Quest Navigator " .. tostring(version or "")}
    for index = 1, math.min(Notes.shown, #Notes.history) do
        local entry = Notes.history[index]
        parts[#parts + 1] = entry.version .. "\n" .. (language == "de" and entry.de or entry.en)
    end
    return table.concat(parts, "\n\n")
end
