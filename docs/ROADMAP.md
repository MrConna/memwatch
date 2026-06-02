# Roadmap

MemWatch is currently a local-first macOS menu bar app for detecting memory pressure and explaining likely causes. This roadmap keeps future work grouped by product value so contributors can pick focused tasks.

## Now

- Keep the app lightweight, native, and safe.
- Improve signal quality before adding aggressive actions.
- Make installation and collaboration easy across Apple Silicon and Intel Macs.

## Milestone 1: Better Diagnosis

- Add per-app memory history over the last 5, 15, and 60 minutes.
- Detect repeated growth patterns across app restarts.
- Highlight "new since pressure started" apps.
- Add confidence labels for each diagnosis.
- Improve app-name extraction for non-`.app` command-line tools.

## Milestone 2: Actionable User Flows

- Add "Open Activity Monitor" and "Open Chrome Task Manager" actions where appropriate.
- Add ignore rules by app name, process kind, and memory threshold.
- Add a one-click "copy diagnostic report" action for sharing with developers.
- Add a guided safe-quit flow that reminds users to save work first.

## Milestone 3: Packaging And Distribution

- Create a signed and notarized release build.
- Package a DMG with a standard Applications shortcut.
- Add release versioning and changelog automation.
- Add GitHub Actions for tests and universal build verification.

## Milestone 4: UI Polish

- Add a compact and expanded popover mode.
- Add a short history chart using accessible colors and labels.
- Improve VoiceOver labels and keyboard navigation through the popover.
- Add screenshots or a short GIF to the README.

## Milestone 5: Advanced Monitoring

- Add optional background launch-agent installation for users who want stronger startup behavior.
- Add optional local-only diagnostic exports.
- Add anomaly detection based on each user's normal baseline.
- Add support for monitoring memory pressure while specific heavy apps are running.

## Non-Goals For Now

- No automatic process killing.
- No privileged helper.
- No telemetry or cloud upload.
- No cross-device sync.
- No replacement for Activity Monitor's full process table.
