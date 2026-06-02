# MemWatch Mac

MemWatch is a lightweight native macOS menu bar app for spotting memory pressure before macOS shows an out-of-memory warning.

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

The app bundle is ad-hoc signed for local use. Full notarized DMG packaging is out of scope for V1.

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

## Productized UI

- First launch explains where to click in the menu bar.
- The popover shows status, memory progress, metrics, diagnosis, top processes, and recent events.
- Chrome renderer processes include a safe recommendation to use Chrome Task Manager or close the related tab.
- Settings include Relaxed, Balanced, and Sensitive presets plus advanced thresholds.

## Notes

This version uses macOS built-in commands: `vm_stat`, `sysctl hw.memsize`, `sysctl vm.swapusage`, and `ps`. It does not kill processes automatically and does not install privileged helpers.
