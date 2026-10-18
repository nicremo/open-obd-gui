# Changelog

All notable changes to this project are documented in this file. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses [Semantic Versioning](https://semver.org/).

## [0.1.0] - 2026-10-18

First public preview. Tested against the built-in simulator, validation on real vehicles is in progress.

### Added

- Native SwiftUI app for macOS 26 with cockpit, trouble codes, live data, modules, vehicle, history and workshop.
- Cockpit with a top view track map of the car, modules at their location, HS-CAN and MS-CAN buses and urgency shown as racing flags.
- Full scan in three depths: OBD-II data, readiness, freeze frame, VIN from every source, Ford module discovery on HS-CAN and MS-CAN, identification, UDS fault memories, trouble code details and configuration blocks.
- Trouble codes grouped by module with explanation, urgency, reasons, status bits and every reporting source.
- Live data with gauges, chart, time window, polling interval and min, max and mean.
- Technical inspector with raw bytes, formula, provenance, statistics and JSON for every value.
- Report history in Application Support and export as JSON and Markdown.
- Read-only policy for vehicle services and adapter commands, enforced right before the serial port.
- Command line tool `openobd` with stable JSON output, simulator, capture and replay, and `--via-app` to run inside the running app.
- Built-in simulator for a Ford Mondeo IV and a Ford Focus IV.

[0.1.0]: https://github.com/nicremo/open-obd-gui/releases/tag/v0.1.0
