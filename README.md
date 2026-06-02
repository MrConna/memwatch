# MemWatch Mac

MemWatch is a lightweight native macOS menu bar app for spotting memory pressure before macOS shows an out-of-memory warning.

It is designed for people who regularly see "your system has run out of application memory" and want an always-on, low-noise signal that explains what changed, which app is responsible, and what to do next.

## Status

- Native SwiftUI menu bar app.
- Supports Apple Silicon and Intel Macs through a universal `arm64 x86_64` build.
- Minimum macOS version: 13.0.
- Local-only. No analytics, network upload, privileged helper, or automatic process killing.

## Features

- Menu bar status such as `MEM 54%`, `MEM !!`, `SWAP 6G`, or `MEM UP`.
- Live memory sampling with used memory, available memory, swap, and pressure state.
- Diagnosis engine for sustained pressure, heavy swap, low available memory, and fast-growing processes.
- Top app aggregation, so Chrome/Lark/editor helper processes are grouped by owning app.
- Process-kind labeling for main app, renderer, GPU, helper, and unknown processes.
- Safer Chrome guidance: close the related tab or use Chrome Task Manager before force quitting helpers.
- Notification cooling, so repeated abnormal samples do not spam the user.
- Recovery state when memory pressure returns to normal.
- Settings window with sensitivity presets and advanced thresholds.
- First-launch welcome window explaining where to find the app.

## Project Docs

- [Roadmap](docs/ROADMAP.md)
- [Contributing](CONTRIBUTING.md)
- [Release checklist](docs/RELEASE_CHECKLIST.md)
- [Agent guide](AGENTS.md)
- Product specs and implementation plans live under `docs/superpowers/`.

## Requirements

- macOS 13.0 or later.
- Xcode with the macOS SDK installed.
- Swift Package Manager, included with Xcode.

## Run

```bash
swift run MemWatch
```

The app appears in the menu bar as `MEM <percent>`. Click it to see memory pressure, used memory, available memory, swap usage, recent abnormal events, and the top memory-consuming processes.

## One-Shot Check

```bash
swift run MemWatch --once
```

This prints a single memory sample without launching the menu bar UI.

## Self-Test

```bash
swift run MemWatch --self-test
```

This verifies the parser and analyzer behavior in environments where XCTest is unavailable.

## Build A `.app`

```bash
chmod +x scripts/build-app.sh
scripts/build-app.sh
open dist/MemWatch.app
```

The app bundle is built as a universal binary and ad-hoc signed for local use:

```bash
lipo -archs dist/MemWatch.app/Contents/MacOS/MemWatch
# x86_64 arm64
```

Full notarized DMG packaging is not implemented yet. See the roadmap.

## Install To Applications

```bash
chmod +x scripts/install.sh
scripts/install.sh
```

After installation, look for `MEM <percent>` in the menu bar. MemWatch is a menu bar app, so double-clicking the app starts it but does not open a normal document-style window.

To start it with macOS, open System Settings > General > Login Items and add `/Applications/MemWatch.app`.

## Defaults

- Samples every 15 seconds.
- Warning at 80% used memory.
- Critical at 90% used memory.
- Swap warning above 4 GB.
- Low available memory warning below 1 GB.
- Sends a notification after 2 consecutive abnormal samples.
- Repeats sustained abnormal notifications only after the cooldown window.

## Development

Run the full local verification before handing work to another developer:

```bash
swift test
swift run MemWatch --self-test
swift run MemWatch --once
swift build
scripts/build-app.sh
```

GitHub Actions runs the same core checks on pushes and pull requests to `main`, including universal binary verification.

Install the current build:

```bash
scripts/install.sh
```

## Architecture

- `Sources/MemWatch`: SwiftUI app entry point and menu bar UI.
- `Sources/MemWatchCore`: sampling, process parsing, analysis, settings, and notifications.
- `Tests/MemWatchCoreTests`: parser, analyzer, menu status, and compatibility tests.
- `scripts`: build and install helpers.

## Notes

This version uses macOS built-in commands: `vm_stat`, `sysctl hw.memsize`, `sysctl vm.swapusage`, and `ps`. It does not kill processes automatically and does not install privileged helpers.
