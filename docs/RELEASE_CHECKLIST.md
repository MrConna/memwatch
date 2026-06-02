# Release Checklist

Run these commands from the repository root before shipping a MemWatch build.

```bash
swift test
swift run MemWatch --self-test
swift run MemWatch --once
swift build
scripts/build-app.sh
lipo -archs dist/MemWatch.app/Contents/MacOS/MemWatch
scripts/install.sh
lipo -archs /Applications/MemWatch.app/Contents/MacOS/MemWatch
```

Manual checks:

- `/Applications/MemWatch.app` starts.
- The menu bar shows `MEM xx%`.
- Clicking the menu bar item opens the popover.
- First launch shows a welcome window or the menu bar item is already visible.
- Settings open and presets can be applied.
- Login Items settings link opens macOS settings.
- Top process rows include process kind and safe recommendation text.
- Universal binary output includes `x86_64 arm64`.

Release notes should mention:

- user-facing changes,
- verification commands,
- known limitations,
- whether notarized packaging is still out of scope.
