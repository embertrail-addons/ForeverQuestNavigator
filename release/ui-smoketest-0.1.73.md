# Lokaler UI-Test: 0.1.73

Noch im Spiel zu prüfen. Die automatisierten Tests prüfen Zustände und Grenzen; sie rendern keine echte WoW-Oberfläche.

1. WoW vollständig neu starten. Bei langer deutscher Questbezeichnung Schriftgröße 140 %, Breite 330 und maximale Höhe 360 einstellen. Questtitel und Priorität sollen sichtbar bleiben; weitere Ziele und Empfehlungen müssen erreichbar sein. Den Detailbereich öffnen, scrollen und wieder schließen.
2. Auf Schriftgröße 80 % und Breite 640 wechseln. Die Darstellungsvorschau ausprobieren und die vorherigen Werte wiederherstellen. Neue Werte nur mit Absicht beibehalten.
3. Eine Quest ohne bekannte Zielkoordinaten ansehen: Die Anzeige darf keine genaue Richtung erfinden. Karte und Questtext müssen weiter erreichbar sein.
4. Einen Questgeber, ein Questgebiet und einen gespeicherten Zugang ansteuern. Die Kurzbezeichnungen müssen die Art des Ziels unterscheiden. Bei Ankunft muss der nächste Schritt auch im Navigator erscheinen, wenn der separate Pfeil aktiv ist.
5. Eine Quest mit einem vom Spiel zugeordneten benutzbaren Questgegenstand aktivieren. Symbol, Anzahl und Abklingzeit prüfen. Außerhalb des Kampfes bewusst klicken; ohne Klick darf keine Benutzung erfolgen. Bei bestätigter Reichweite darf die Ankunft zum Benutzen auffordern.
6. Im Kampf muss die Gegenstandsaktion verborgen sein. Nach Kampfende prüfen, dass ein verbrauchter oder gewechselter Gegenstand nicht weiter als alte Aktion angeboten wird. Den Navigator scrollen und ausblenden: Eine unsichtbare Gegenstandsaktion darf keine Klicks abfangen.
7. `/fqn arrange` eingeben. Navigator und Richtungspfeil ziehen, Mitte und Rand prüfen, abbrechen und alte Positionen vergleichen. Erneut öffnen, mit „Fertig und sperren“ abschließen und prüfen, dass beide Positionen gesperrt sind. Escape soll wie Abbrechen wirken.
8. Einstellungen, Einklappen, Schließen und Details jeweils mehrfach bedienen. Nahe benachbarte Klicks dürfen keine andere Aktion auslösen. Anordnung und normale Einstellungen erneut öffnen.

Diese Schritte sind nicht automatisch als bestanden markiert. Es wurde kein Bildschirmzugriff durchgeführt.
