# MemWatch Productization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Productize MemWatch through seven reviewable upgrades covering launch feedback, UI, diagnosis, trends, settings, install workflow, and release quality.

**Architecture:** Keep domain logic in `MemWatchCore` and UI composition in `Sources/MemWatch`. Add process classification and event enrichment to the core, then render those signals in a compact SwiftUI menu bar interface.

**Tech Stack:** Swift 5.10, SwiftUI, AppKit, XCTest, shell packaging scripts.

---

## Tasks

### Task 1: Installation And Launch Feedback

- [ ] Add first-launch welcome window from `AppDelegate`.
- [ ] Add install and Login Items actions.
- [ ] Verify app process starts from `/Applications/MemWatch.app`.

### Task 2: Professional Menu Bar UI

- [ ] Rework popover into summary, progress, metric, diagnosis, process, event, and control sections.
- [ ] Keep layout compact at 420 px width.
- [ ] Verify `swift build`.

### Task 3: Chrome And Process Diagnosis

- [ ] Add process category and recommendation fields.
- [ ] Add tests for Chrome renderer, GPU, main app, and helper classification.
- [ ] Render recommendations in process rows.

### Task 4: Event And Trend Visibility

- [ ] Track abnormal start and recovery times.
- [ ] Enrich event messages with metrics.
- [ ] Render recent event list and current trend line.

### Task 5: Settings UX

- [ ] Add sensitivity preset model.
- [ ] Render presets before advanced thresholds.
- [ ] Add tests for preset thresholds.

### Task 6: Install And Login Workflow

- [ ] Add `scripts/install.sh`.
- [ ] Update README with install and troubleshooting steps.
- [ ] Verify install script copies app to `/Applications`.

### Task 7: Release Quality

- [ ] Add `docs/RELEASE_CHECKLIST.md`.
- [ ] Run `swift test`, `swift run MemWatch --self-test`, `swift run MemWatch --once`, `swift build`, and packaging.
- [ ] Commit final productization changes.

## Review Notes

- `ui-pro-max` is unavailable; UI improvements are implemented manually against the productization design standard.
- Automatic process killing remains intentionally out of scope.
