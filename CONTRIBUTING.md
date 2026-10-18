# Contributing

Thanks for helping. The most valuable contribution right now is data from real vehicles: which modules answer, which identifiers they report and how the adapter behaves.

## Reporting a vehicle

Open a [vehicle report](https://github.com/nicremo/open-obd-gui/issues/new?template=vehicle_report.yml) with model, year, engine, adapter and what the scan found. If you attach a report or a capture, replace your VIN first. Captures recorded with `--capture` contain it in plain text.

## Development

Requirements: macOS 26 or newer, Xcode 26 or newer (CI uses Swift 6.3).

```bash
swift build
swift test
scripts/build-app.sh debug
```

Ground rules:

- **Read only stays read only.** Pull requests that allow writing services (clearing codes, coding, actuator tests, security access, flashing) are not accepted.
- **No guessing.** Every new entry in the knowledge base needs a `source` and a `confidence`. Meanings that come from neither a standard nor a confirmation on a vehicle stay `community` or `unknown`.
- **Every formula needs a test** with at least two vectors from the standard or a public reference.
- **Tests use swift-testing** (`import Testing`). The suite must stay green and free of warnings under Swift 6 strict concurrency.
- **One responsibility per file**, files stay below 400 lines.
- Commit messages follow `feat|fix|refactor|docs|test: description`.

## Pull requests

Keep them focused, describe what changed and how you tested it, and run `swift test` before opening the pull request.
