# Open OBD GUI

Native macOS-Diagnose für Ford-Fahrzeuge mit einem OBDLink EX. Adapter einstecken, auslesen, verstehen. Nur lesend.

Gebaut für einen Ford Mondeo IV (BA7, 2.0 TDCi) und einen Ford Focus IV (C519). Die App entdeckt Steuergeräte und Messwerte am Fahrzeug selbst und zeigt zu jedem Wert, woher er stammt und wie sicher seine Bedeutung ist.

## Was die App kann

- Vollständiger Scan: Fahrzeugdaten und VIN, alle Steuergeräte auf HS-CAN und MS-CAN, alle Fehlerspeicher, Bereitschaftstests, Freeze Frame, Messwerte.
- Fehlerspeicher mit Erklärung, Dringlichkeit und Begründung, gruppiert nach Steuergerät.
- Live-Daten mit Instrumenten und Verlauf.
- Steuergeräte mit Teilenummern, Software- und Hardwareständen.
- Werkstatt-Ansicht mit Rohanfragen und dem kompletten Adapterverkehr.
- Verlauf aller Scans, Export als JSON und Markdown.
- Simulator für Mondeo und Focus, damit alles auch ohne Auto funktioniert.

## Sicherheit

Open OBD GUI schreibt nie ins Fahrzeug. Jede Nachricht passiert unmittelbar vor der seriellen Schnittstelle eine Nur-Lese-Prüfung. Erlaubt sind nur lesende Dienste (OBD 01 02 03 06 07 09 0A, UDS 22, 19 Lesefunktionen, 3E, 10 01). Fehlerspeicher löschen, Codieren, Stellgliedtests und Security Access gibt es nicht.

Werte, deren Bedeutung nicht aus einer Norm stammt oder am Fahrzeug bestätigt wurde, zeigt die App als unbestätigt an.

## Installation

Voraussetzungen: macOS 26 oder neuer, Apple Silicon, Xcode mit Swift 6.

```bash
scripts/build-app.sh
```

```bash
open "dist/Open OBD GUI.app"
```

Ohne Fahrzeug startet die App im Simulator:

```bash
open "dist/Open OBD GUI.app" --args --demo mondeo-mk4
```

## Kommandozeile

```bash
scripts/install-cli.sh
```

```bash
openobd devices
openobd adapter
openobd scan --out bericht.json --markdown bericht.md
openobd scan --sim mondeo-mk4 --digest --json
openobd dtc --json
openobd live 0C 0D 05 --count 20
openobd explain dtc P0401-00
openobd capabilities --json
```

Jeder Befehl gibt mit `--json` genau ein Objekt nach dem Schema `openobd.cli/1` aus. Läuft die App, hält sie den Adapter. Dann führt `--via-app` den Befehl in der App aus, und die App zeigt mit, was gelesen wird.

## Aufbau

| Modul | Aufgabe |
| --- | --- |
| `OBDCore` | Normen als Code: ISO-TP, OBD-II nach SAE J1979, UDS nach ISO 14229, Fehlercodes, Nur-Lese-Prüfung |
| `AdapterKit` | Serielle Verbindung, Geräteerkennung, ELM327 und STN, Mitschnitt und Wiedergabe |
| `FordKnowledge` | Wissensbasis mit Quelle und Vertrauensstufe je Eintrag |
| `VehicleSim` | Virtueller OBDLink mit virtuellen Ford-Steuergeräten |
| `DiagnosticEngine` | Sitzung, Scan, Live-Daten, Bericht |
| `CLIKit`, `openobd` | Kommandozeile |
| `OpenOBDApp` | SwiftUI-App |

## Entwicklung

```bash
swift build
swift test
```
