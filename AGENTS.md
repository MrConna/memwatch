# Agent Guide

This repository contains MemWatch, a native macOS menu bar app for detecting memory pressure and explaining likely causes.

## Project Shape

- `Sources/MemWatch`: SwiftUI app, menu bar UI, popover, settings, and first-launch window.
- `Sources/MemWatchCore`: memory sampling, process parsing, diagnosis, settings store, notification service, and formatting helpers.
- `Tests/MemWatchCoreTests`: behavior and parser tests.
- `scripts/build-app.sh`: creates a universal `arm64 x86_64` app bundle.
- `scripts/install.sh`: installs the current app bundle to `/Applications`.

## Agent Workflow

1. Read the relevant source and tests before editing.
2. Keep changes scoped to the requested behavior.
3. Use tests for parser, analyzer, formatting, and compatibility behavior.
4. Run verification before reporting completion.
5. Do not revert unrelated local changes.

## Verification Commands

Run these from the repository root:

```bash
swift test
swift run MemWatch --self-test
swift run MemWatch --once
swift build
scripts/build-app.sh
lipo -archs dist/MemWatch.app/Contents/MacOS/MemWatch
```

For install verification:

```bash
scripts/install.sh
lipo -archs /Applications/MemWatch.app/Contents/MacOS/MemWatch
```

The universal build should include:

```bash
x86_64 arm64
```

## Guardrails

- Do not introduce automatic process killing.
- Do not add telemetry, cloud upload, or network calls.
- Do not add privileged helpers without an explicit security review.
- Do not use `memory_pressure` as a sampling command; it can be disruptive.
- Keep user-facing recommendations conservative and save-work-first.

## Documentation

When shipping user-facing or packaging changes, update:

- `README.md`
- `docs/ROADMAP.md` if the future plan changes
- `docs/RELEASE_CHECKLIST.md`
- `CONTRIBUTING.md` for workflow changes
