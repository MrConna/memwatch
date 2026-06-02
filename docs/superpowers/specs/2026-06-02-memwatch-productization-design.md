# MemWatch Productization Design

## Goal

Upgrade MemWatch from a working menu bar prototype into a clearer, more trustworthy macOS utility. The work is organized from four perspectives:

- PM: remove first-use confusion and make the value obvious within 10 seconds.
- Project leader: keep scope incremental, reviewable, and shippable task by task.
- Developer: preserve testable core logic and avoid UI code leaking into monitoring logic.
- User: make it obvious where to click, what is wrong, which process is risky, and what action is safe.

## Task List

1. Installation and launch feedback.
2. Professional menu bar UI.
3. Chrome and high-memory process diagnosis.
4. Abnormal event and trend visibility.
5. Settings and threshold UX.
6. Install and login-item workflow.
7. Development quality and release workflow.

## Review Standard

Each task must include:

- a concrete user problem,
- a focused implementation,
- tests or a verifiable command,
- a short release note,
- no unrelated refactor.

## UI Direction

`ui-pro-max` is not available in this session, so V1 uses the same target quality manually:

- compact macOS utility layout,
- clear hierarchy,
- semantic status colors,
- no decorative clutter,
- cards only for repeated or genuinely framed content,
- visible actions for install, refresh, settings, and quit,
- process rows that pair diagnosis with safe next steps.

## Product Requirements

### 1. Installation And Launch Feedback

Double-clicking the app should produce a visible explanation even though the main interaction lives in the menu bar. First launch shows a small welcome window that points to the menu bar item and offers install/setup actions.

### 2. Professional Menu Bar UI

The popover should show a status summary, memory progress, key metrics, diagnosis, top processes, recent events, and controls. It should be scannable at a small width.

### 3. Process Diagnosis

The app should classify process rows into main app, renderer, GPU, helper, or unknown where possible. Chrome renderer rows should recommend using Chrome Task Manager or closing the related tab instead of killing Chrome itself.

### 4. Events And Trends

The app should show when abnormal pressure started, when it recovered, and the latest abnormal events. Event messages should include used memory, swap, and top process context.

### 5. Settings UX

Settings should expose simple sensitivity presets first: Relaxed, Balanced, and Sensitive. Advanced numeric thresholds remain available for power users.

### 6. Install And Login Workflow

The project should provide a script that builds, copies the app to `/Applications`, opens it, and prints login-item instructions. The app should also link users to Login Items settings.

### 7. Release Workflow

The repository should include a release checklist that runs tests, one-shot sampling, build, app packaging, and install verification.

## Out Of Scope

- Notarized DMG packaging.
- Killing processes from inside the app.
- Browser tab URL inspection.
- Privileged helpers.
