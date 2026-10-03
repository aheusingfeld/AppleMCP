# LocalMCP: Apple-Skills-Qualitätsprüfung

Stand: 3. Oktober 2026. Quelle: die mit Xcode 27.0 (27A266a) exportierten Apple-Skills. Der Export erfolgte mit `xcrun agent skills export --output-dir /tmp/localmcp-apple-skills-20261003`. Vorhandene persönliche Skills wurden nicht überschrieben.

## Bereits umgesetzt: gezielte SwiftUI-Aktualisierung

`AppModel` verwendet nun `@MainActor @Observable`. Die App besitzt das Modell über `@State`; Ansichten verwenden `@Bindable`. Ansichten beobachten dadurch die tatsächlich gelesenen Eigenschaften, statt bei jeder Änderung einer beliebigen `@Published`-Eigenschaft neu ausgewertet zu werden. Interne Task-, Server- und Ablaufzustände sind mit `@ObservationIgnored` vom UI-Tracking ausgenommen. Der Token bleibt beobachtbar, damit die Verbindungsansicht auf Start und Stop reagiert.

Zwei Verhaltenstests prüfen, dass eine Zustimmung die zustimmungsabhängige Ansicht aktualisiert und die Ansicht des unveränderten Serverstatus nicht invalidiert. Die bestehenden Zustimmungs-, Berechtigungs-, Abbruch- und Servertests werden zusätzlich ausgeführt. Das ist ein Nachweis der Beobachtungsgranularität, keine gemessene Aussage über Bildrate oder CPU-Verbrauch.

## Sicherheitsstand

Die ausgewerteten Release-Build-Einstellungen von `LocalMCP` bestätigen `ENABLE_HARDENED_RUNTIME = YES`, `ENABLE_APP_SANDBOX = YES`, `ARCHS = arm64 x86_64`, `SWIFT_OPTIMIZATION_LEVEL = -O` und `ENABLE_ENHANCED_SECURITY = NO`. Pointer Authentication und Security Compiler Warnings stehen ebenfalls auf NO. Ausgewertete Standardwerte sind keine absichtlichen Opt-outs: Die XcodeGen-Quelldatei setzt diese NO-Werte nicht ausdrücklich.

Die App und ihre Bridge deklarieren noch keine `com.apple.security.hardened-process`-Entitlements. Sandbox und Hardened Runtime sind eigene Schutzmechanismen und ersetzen Enhanced Security nicht. Das Projekt besteht in den untersuchten App/Core/Bridge-Quellen aus Swift; C/C++-Warnungen sind daher kein Ersatz für Swift-Concurrency-Prüfungen.

Der untersuchte Transport enthält bereits begrenzte offene und aktive Verbindungen, Größenlimits, monotone Lese-/Schreibfristen, Token- und Peer-Prüfung sowie Abbruchbehandlung. Das Aktivitätsprotokoll begrenzt Einträge auf 100 und Ein-/Ausgabedarstellungen auf jeweils 8.000 Zeichen. Die Prüfung dieser Kontrollen ist kein vollständiger Penetrationstest.

## Freigegeben am 3. Oktober 2026: Enhanced Security

- [x] In der maßgeblichen XcodeGen-Datei `xcode/project.yml` projektweit `ENABLE_ENHANCED_SECURITY = YES` aktivieren und das Projekt neu generieren. Danach tatsächlich ausgewertete Einstellungen aller betroffenen Targets prüfen.
- [x] Für LocalMCP und M3MCPBridge die erforderlichen v2-Entitlements und die standardmäßig aktiven Optionen ergänzen: `hardened-process`, `enhanced-security-version-string = 2`, `hardened-heap`, `dyld-ro`, `platform-restrictions-string = 2`.
- [x] Den SandboxTransportProbe entsprechend härten, damit der reale App-/Bridge-Transport unter denselben Schutzmechanismen getestet werden kann.
- [x] M3MCPCore als statische Bibliothek ohne eigene Prozess-Entitlements behandeln; die durch Enhanced Security erzeugten Architekturen und das Zusammenspiel von App und Bridge überprüfen.
- [x] Keine iOS/watchOS-spezifische Checked-Pointer-Arithmetic-Slice und kein Hardware Memory Tagging für diese macOS-App aktivieren.
- [ ] Universal-Release-Build, vollständige Tests und ThreadSanitizer ausführen. Anschließend signierten nativen Sandbox-Transport, Keychain-Start/Neustart, Verbindungsprüfung, Datenquellen und Apple Events auf realem Mac überprüfen. Keine realen Tokens löschen, ACLs lockern oder Datenschutzfreigaben zurücksetzen.
- [ ] Nur nach diesen Laufzeitprüfungen einen neuen Release-Build und eine App-Store-Einreichung vorbereiten. Compilererfolg allein bestätigt diese Runtime-Schutzmechanismen nicht.

## Weiterer messbarer Performance-Fokus

Die JSON-Serialisierung des Aktivitätsprotokolls erfolgt aktuell auf dem MainActor, bevor die Darstellung gekürzt wird. Bei großen zulässigen Antworten kann das UI-Arbeit verursachen. Vor einer weiteren Änderung mit Instruments/Signposts messen; danach gegebenenfalls eine begrenzte Darstellung außerhalb des MainActors erstellen. Kein nachgewiesener UI-Hänger und keine Performance-Zahl werden daraus abgeleitet.

## Grenzen

Verifiziert: vollständige Swift-Suite mit 408 Tests, vier ausdrücklich opt-in erforderlichen Kalendertests übersprungen, keine Fehler; Universal-Release-Build erfolgreich; Dokumentationsprüfung und 321 DE/EN-Lokalisierungseinträge vollständig. Native UI-Interaktionen und ein Instruments-Profil der geänderten App wurden in dieser Sitzung noch nicht ausgeführt.

Der Release-Build meldet in `CapabilityToken.swift` die veraltete Konstante `kSecUseAuthenticationUIFail`; Apple empfiehlt `LAContext.interactionNotAllowed`. Der jetzige Code setzt bewusst nichtinteraktiven Keychain-Zugriff um. Eine Migration benötigt eigene native Keychain-Regressionstests für nichtinteraktiven Start und bewusst bestätigten Start und ist nicht Bestandteil der Observation-Änderung. Weitere Meldungen betreffen ein überflüssiges `await` der Bridge und nicht benötigte App-Intents-Metadatenextraktion.

In dieser Sitzung sind keine Xcode-MCP-Projektwerkzeuge verfügbar; das Einstellungs-Audit verwendet deshalb `xcodebuild -showBuildSettings` und die XcodeGen-Quellen. Export und CLI funktionieren; die erste Exportmeldung über ein beschädigtes Xcode wurde durch den erfolgreichen erneuten Export widerlegt. Die bestehenden persönlichen Skill-Dateien stimmen mit den frisch exportierten beiden angewendeten Skills überein.

Die App-Store-Einreichung und ihre manuelle Veröffentlichung werden durch diese lokale Qualitätsprüfung nicht verändert. Ein TestFlight-Upload oder Apple-Approval wird nicht aus lokalen Tests abgeleitet.

## Ergebnis der Umsetzung

Enhanced Security ist projektweit in der XcodeGen-Quelle aktiviert. App, Bridge und SandboxTransportProbe tragen die fünf freigegebenen v2-Entitlements. Die signierten Entwicklungsprofile wurden durch Xcode aktualisiert. Die tatsächlichen Einstellungen von LocalMCP, M3MCPBridge und M3MCPCore bestätigen Enhanced Security, Pointer Authentication und Security Compiler Warnings. `lipo` bestätigt arm64, x86_64 und arm64e für die Release-App und die Core-Bibliothek. Keine expliziten bisherigen Opt-outs wurden überschrieben.

408 Tests unter ThreadSanitizer: vier opt-in-Kalendertests übersprungen, keine Fehler und keine gemeldeten Datenrennen. Universal-Release-Build, signierte Release-App, signierter SandboxTransportProbe und strenge tiefe Signaturprüfung erfolgreich. Dokumentations- und DE/EN-Lokalisierungsprüfungen erfolgreich.

Auf dem realen Mac bestätigt der signierte SandboxTransportProbe: eingebettete Bridge mit korrektem synthetischem Token akzeptiert; dieselbe Bridge mit falschem Token abgewiesen; fremder Prozess trotz korrektem Token abgewiesen; Socket 0600 und Elternordner 0700. Der erste Testaufruf mit einer Bridge außerhalb des Pakets scheiterte am Sandbox-Dateizugriff; der korrekte Aufruf mit der eingebetteten Bridge besteht.

Die signierte Haupt-App startet und verbindet sich auch nach Prozessneustart erfolgreich mit ihrer echten eingebetteten Bridge. Der Test verwendet ein synthetisches Token, einen eigenen Socket-Unterordner sowie nur prozesslokale Setup-Argumente. Er bestätigt weder reale Keychain-Kontinuität noch persönliche Datenquellen oder Apple Events. macOS schützt die Test-Diagnosedateien im App-Group-Container vor dem externen Python-Treiber; kleine isolierte Test-Unterordner bleiben deshalb erhalten. Keine realen Tokens oder Freigaben wurden geändert.

Ausstehendes Veröffentlichungstor: native Prüfung der realen Keychain-Zugriffe, Datenquellen und Apple Events; bisherige Zustimmung zu anderen Builds ersetzt diese Prüfung nicht. Die Store-Einreichung bleibt davon unabhängig.
