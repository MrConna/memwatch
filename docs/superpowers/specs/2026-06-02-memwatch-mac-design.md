# MemWatch Mac Design

## Goal

Build a lightweight macOS menu bar app that detects memory pressure before the system shows "out of memory" warnings. The app should help the user quickly answer two questions:

- Is memory pressure becoming abnormal?
- Which processes are most likely responsible?

## Product Shape

MemWatch is a native SwiftUI menu bar app. It normally stays out of the way and shows a compact memory status indicator in the macOS menu bar. When memory pressure remains high for multiple samples, it sends a macOS notification and records an event.

The first version focuses on practical detection and diagnosis, not charts or dashboards.

## Core Features

- Menu bar indicator with green, yellow, and red states.
- Popover showing:
  - memory pressure state,
  - used memory,
  - available memory,
  - swap usage,
  - latest abnormal event,
  - top memory-consuming processes.
- Periodic sampling, defaulting to every 15 seconds.
- Notification when abnormal memory conditions persist for 2 or more samples.
- Event log for recent abnormal memory incidents.
- Settings window with:
  - sampling interval,
  - warning threshold,
  - critical threshold,
  - notification toggle,
  - ignored process names.

## Detection Rules

Each sample collects system memory and process data. A sample is abnormal when at least one rule matches:

- macOS reports elevated memory pressure.
- used memory ratio exceeds the configured warning threshold.
- swap usage exceeds the configured swap threshold.
- available memory falls below the configured minimum.
- one process is both high-memory and rising across recent samples.

V1 defaults are:

- warning at 80% used memory,
- critical at 90% used memory,
- swap warning above 4 GB,
- low available memory below 1 GB,
- notification after 2 consecutive abnormal samples.

To avoid noisy alerts, notifications require repeated abnormal samples. The app should show the current state immediately in the menu bar, but only notify after a sustained problem.

## Data Sources

The app uses macOS-native command line data sources available without special privileges:

- `vm_stat` for page and memory counters.
- `sysctl hw.memsize` for total physical memory.
- `sysctl vm.swapusage` for swap usage.
- `ps -axo pid,comm,rss` for process memory usage.

All command parsing is isolated behind a monitoring service so the UI can be tested with synthetic snapshots.

## Architecture

- `MemWatchApp`: SwiftUI app entry point and menu bar scene.
- `MemoryMonitor`: timer-driven coordinator that samples memory and publishes current state.
- `MemorySampler`: runs macOS commands and converts raw output into structured snapshots.
- `MemoryAnalyzer`: applies thresholds and classifies normal, warning, and critical states.
- `ProcessSampler`: collects top process memory usage.
- `EventStore`: keeps recent abnormal events in app storage.
- `SettingsStore`: persists user-configurable thresholds and ignore lists.
- `NotificationService`: requests notification permission and sends alerts.

## Error Handling

If a command fails or returns unexpected output, the app keeps running and displays a degraded state with a short error message in the popover. Sampling failures are recorded but should not trigger memory alerts by themselves.

## Testing

Unit tests cover:

- parsing `vm_stat`, `sysctl`, `memory_pressure`, and `ps` output,
- threshold classification,
- repeated-sample alert suppression,
- ignored process filtering,
- event creation.

Manual verification covers:

- app launches as a menu bar item,
- popover opens and updates,
- settings persist,
- notifications fire only after sustained pressure,
- the app remains low overhead while sampling.

## Out Of Scope For V1

- DMG packaging and code signing.
- Historical charts.
- Automatic process killing.
- Kernel extensions or privileged helpers.
- Cloud sync or telemetry.
