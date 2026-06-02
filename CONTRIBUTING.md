# Contributing

Thanks for helping improve MemWatch. The project is intentionally small: a native macOS menu bar app, a core library, tests, and packaging scripts.

## Setup

Install Xcode, then from the repository root run:

```bash
swift test
swift run MemWatch --once
```

Run the app:

```bash
swift run MemWatch
```

Build the `.app` bundle:

```bash
scripts/build-app.sh
open dist/MemWatch.app
```

## Verification

Before submitting a change, run:

```bash
swift test
swift run MemWatch --self-test
swift run MemWatch --once
swift build
scripts/build-app.sh
```

For packaging changes, also verify:

```bash
lipo -archs dist/MemWatch.app/Contents/MacOS/MemWatch
```

Expected output includes both:

```bash
x86_64 arm64
```

## Coding Guidelines

- Keep sampling and analysis logic in `Sources/MemWatchCore`.
- Keep UI-specific behavior in `Sources/MemWatch`.
- Prefer pure functions for formatting and diagnosis decisions so they can be tested.
- Add regression tests for behavior changes.
- Do not add automatic process killing.
- Do not add network upload or analytics without an explicit product decision.
- Avoid privileged helpers unless the roadmap changes and the security model is reviewed.

## Product Principles

- The app should reduce anxiety, not create alert fatigue.
- Recommendations should be safe for non-technical users.
- Activity Monitor remains the deep inspection tool; MemWatch should be the early warning and explanation layer.
- UI should stay compact, scannable, and native to macOS.

## Useful Files

- `README.md`: project overview and local run instructions.
- `docs/ROADMAP.md`: future work.
- `docs/RELEASE_CHECKLIST.md`: release verification.
- `AGENTS.md`: instructions for AI coding agents working in this repo.
