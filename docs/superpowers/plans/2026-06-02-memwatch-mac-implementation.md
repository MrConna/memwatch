# MemWatch Mac Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a runnable native macOS menu bar app that monitors memory pressure, identifies high-memory processes, and alerts after sustained abnormal memory conditions.

**Architecture:** Use a Swift Package with a `MemWatchCore` library for parsing, sampling, analysis, events, settings, and notifications, plus a `MemWatch` executable for the SwiftUI/AppKit menu bar UI. Keep command parsing isolated so tests can validate behavior with fixed command output.

**Tech Stack:** Swift 5.10, Swift Package Manager, SwiftUI, AppKit, UserNotifications, XCTest.

---

## File Structure

- `Package.swift`: Swift package manifest with `MemWatchCore`, `MemWatch`, and `MemWatchCoreTests`.
- `Sources/MemWatchCore/Models.swift`: shared data models.
- `Sources/MemWatchCore/CommandRunner.swift`: shell command abstraction.
- `Sources/MemWatchCore/MemorySampler.swift`: parses `vm_stat`, `sysctl`, swap usage, and `ps` output.
- `Sources/MemWatchCore/MemoryAnalyzer.swift`: applies thresholds and repeated-sample alert rules.
- `Sources/MemWatchCore/Stores.swift`: settings and recent event persistence.
- `Sources/MemWatchCore/MemoryMonitor.swift`: timer-driven coordinator.
- `Sources/MemWatchCore/NotificationService.swift`: macOS notification integration.
- `Sources/MemWatch/main.swift`: SwiftUI menu bar app entry point.
- `Tests/MemWatchCoreTests/MemorySamplerTests.swift`: parser tests.
- `Tests/MemWatchCoreTests/MemoryAnalyzerTests.swift`: classification and alert suppression tests.
- `README.md`: run and test instructions.

## Tasks

### Task 1: Package and Parser Tests

**Files:**
- Create: `Package.swift`
- Create: `Tests/MemWatchCoreTests/MemorySamplerTests.swift`

- [ ] Write a Swift package manifest with a core library, executable, and test target.
- [ ] Write failing tests proving `vm_stat`, `sysctl`, swap usage, and `ps` parsing behavior.
- [ ] Run `swift test --filter MemorySamplerTests` and verify failure is due to missing implementation.

### Task 2: Parser Implementation

**Files:**
- Create: `Sources/MemWatchCore/Models.swift`
- Create: `Sources/MemWatchCore/CommandRunner.swift`
- Create: `Sources/MemWatchCore/MemorySampler.swift`

- [ ] Implement data models for memory snapshots, process usage, and pressure levels.
- [ ] Implement command running with `/bin/sh -c`.
- [ ] Implement parser methods for each macOS command output.
- [ ] Run `swift test --filter MemorySamplerTests` and verify parser tests pass.

### Task 3: Analyzer Tests and Implementation

**Files:**
- Create: `Tests/MemWatchCoreTests/MemoryAnalyzerTests.swift`
- Create: `Sources/MemWatchCore/MemoryAnalyzer.swift`

- [ ] Write failing tests for warning, critical, ignored processes, and sustained alert behavior.
- [ ] Run `swift test --filter MemoryAnalyzerTests` and verify failure is due to missing analyzer implementation.
- [ ] Implement thresholds and repeated abnormal sample tracking.
- [ ] Run `swift test --filter MemoryAnalyzerTests` and verify analyzer tests pass.

### Task 4: Stores, Monitor, and Notifications

**Files:**
- Create: `Sources/MemWatchCore/Stores.swift`
- Create: `Sources/MemWatchCore/MemoryMonitor.swift`
- Create: `Sources/MemWatchCore/NotificationService.swift`

- [ ] Implement settings defaults from the spec.
- [ ] Implement recent event persistence through `UserDefaults`.
- [ ] Implement `MemoryMonitor` as an observable coordinator that periodically samples, analyzes, records events, and requests notifications.
- [ ] Implement notification permission and alert delivery.
- [ ] Run `swift test` to ensure core behavior still passes.

### Task 5: Menu Bar App

**Files:**
- Create: `Sources/MemWatch/main.swift`

- [ ] Implement a SwiftUI `MenuBarExtra` with green, yellow, and red status labels.
- [ ] Implement a popover with memory metrics, latest event, top processes, errors, and controls.
- [ ] Implement settings controls for sampling interval, thresholds, notification toggle, and ignored process names.
- [ ] Run `swift build` and fix compile errors.

### Task 6: Documentation and Verification

**Files:**
- Create: `README.md`

- [ ] Document `swift run MemWatch`, `swift test`, thresholds, and limitations.
- [ ] Run `swift test`.
- [ ] Run `swift build`.
- [ ] Run `swift run MemWatch --once` to verify command-line sampling output without launching a persistent UI.
- [ ] Commit the implementation.

## Self-Review

- Spec coverage: tasks cover menu bar indicator, popover metrics, top processes, default thresholds, settings, sustained notifications, event logging, parser tests, build verification, and low-overhead native implementation.
- Scope check: DMG packaging, code signing, historical charts, and automatic process killing remain out of scope.
- Placeholder scan: no deferred behavior is required for V1.
