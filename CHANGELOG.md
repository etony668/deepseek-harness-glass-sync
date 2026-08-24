# Changelog

All notable changes to this project are documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.5.8] - 2026-08-24

### Changed

- Windows release CI now treats full MSI install/uninstall as a bounded,
  best-effort diagnostic for the large self-contained official runtime. The
  MSI is still built and validated before release, while a slow Windows
  Installer run no longer prevents the ZIP and MSI assets from being
  published; logs are retained when available.

## [0.5.7] - 2026-08-24

### Fixed

- Restored the bundled Node.js directory to the process `PATH` used during
  macOS and Windows official Harness synchronization, so pnpm lifecycle
  scripts do not fail on machines without a system Node.js installation.
- Repaired missing user plugin profile fallbacks before the macOS and Windows
  backend starts. A user-installed plugin can no longer make the official
  `web` profile exit because its profile `node_modules` link was lost.
- Hardened the Windows MSI build and validation flow for the complete official
  runtime, including compressed cabinets, a short WiX staging path, and
  normalized native-file language metadata.

## [0.5.6] - 2026-08-24

### Added

- WiX-based Windows MSI installer built on GitHub Actions. The installer
  places the complete self-contained Windows app under Program Files, adds a
  Start Menu shortcut, supports major-version upgrades, and leaves the user's
  `%LOCALAPPDATA%` / `~/.dsh` data untouched on uninstall.

## [0.5.5] - 2026-08-24

### Fixed

- Restored execution of the macOS Glass WebView theme and branding overrides
  after removing a backtick that broke the injected JavaScript template.

### Changed

- Replaced the single homepage screenshot in both bilingual READMEs with
  separate light-mode and dark-mode previews.

### Added

- Native Windows host built with WinUI 3 and WebView2. The outer window uses
  Windows 11 Mica, while its native start/sync surface uses Acrylic with a
  system solid-color fallback.
- Windows x64 and ARM64 build scripts that download the fixed Node.js/pnpm
  toolchain, build and smoke-test the complete official Harness runtime, then
  publish a portable self-contained app folder.
- Windows native menu actions for official runtime sync, backend restart,
  browser launch, `DSH_HOME`, logs, and official
  `dsh plugin --profile web` package add/remove commands.

### Fixed

- Restored the macOS Liquid Glass translucency in both Harness themes. The
  readability fix now keeps solid foreground tokens while leaving page
  backgrounds transparent enough for the native `.glassEffect` material to
  refract and blur the desktop again.
- Tuned the native WebView shell surfaces separately: Settings now uses a
  90%-opaque theme-colored panel in both modes, while dark-mode home surfaces
  keep only a small amount of transparency for steadier contrast.
- Kept the light-mode home canvas on its own lower-opacity glass token set so
  the 90%-opaque Settings panel cannot flatten the main page's translucency.
- Fixed the Glass WebView injection template: a backtick inside the CSS
  comment terminated the generated JavaScript template literal, so none of the
  brand, theme, or transparency overrides were running.

## [0.5.0] - 2026-08-21

### Added

- The official DeepSeek Harness source is now pinned as the
  `upstream/deepseek-harness` Git submodule, initially at
  `dsh-v0.1.1-rc.1`.
- `scripts/sync-upstream.sh` advances that source baseline to the official
  `master`; `scripts/build-runtime.sh` builds it, deploys the official
  `@deepseek-ai/dsh` runtime closure, and smoke-tests its `web` profile.
- Fixed embedded pnpm alongside Node.js. The Swift menu and tray expose
  official `dsh plugin --profile web add/remove` operations, so Profile Bundle
  installation does not depend on a system pnpm.

### Changed

- App releases now package the full official Harness runtime built from source,
  rather than independently pinned npm payload packages.
- The shell starts the official `dsh web --no-open` profile and leaves Cordis
  profile bundles, user patch layers, client modules, and dynamic plugins to
  the official runtime.

## [0.4.0] - 2026-08-15

### Added

- Port reuse: if a dsh instance is already serving on 127.0.0.1:3080, the
  app attaches to it instead of spawning a second backend.
- Crash recovery: the embedded backend is restarted once automatically
  (0.6 s delay); a second consecutive failure shows a retry page with the
  log path.
- Menu-bar tray with show / open-in-browser / restart-backend / open-home /
  open-log / quit actions; closing the window hides it instead of quitting.
- Harness menu: restart backend and open-in-browser entries.

### Changed

- The shell only terminates a backend it spawned itself; an externally
  reused instance is never killed on quit.
## [0.3.0] - 2026-08-15

### Added

- Native SwiftUI shell with a real Liquid Glass window
  (public `glassEffect` API, macOS 26+).
- Full-window glass: `fullSizeContentView` plus a zero-safe-area hosting view,
  so the glass reaches the window's top edge.
- Dynamic text contrast: the shell samples the desktop wallpaper's average
  luminance once at launch (and on wallpaper change) and flips text between a
  light and a dark palette with 0.45/0.55 hysteresis. Window movement never
  triggers a flip.
- Layered frosting: elevated surfaces (composer, popovers, menus, hover cards)
  get per-layer translucent tints plus a `backdrop-filter` sweep.
- Self-contained distribution: bundled Node.js v24 binary and a pinned,
  npm-installed dsh backend payload; no runtime downloads.
- `repair-backend.sh` — one-shot backend payload reinstall with a smoke test.
- DMG installer with an Applications shortcut and Chinese install notes.

### Fixed

- Missing backend packages after relocating the payload (24 `@deepseek-ai`
  packages): payload installation now goes through `npm` with exact pins.
- DMG creation losing symlinks and invalidating the ad-hoc signature:
  `assemble.sh` now dereferences symlinks (`cp -RL`) before signing.
- Inline-code and citation chips rendering as solid color blocks in the wrong
  theme (they are background tokens, not text tokens).
- Text tokens leaking backdrop color at glyph edges: a 0.5% white underlay
  plus `-webkit-font-smoothing: antialiased`.

### Removed

- Electron-based prototype (private-API glass bridge) and its build pipeline.

## [0.2.0] - 2026-08-15

### Added

- Electron shell prototype (superseded by 0.3.0).

[0.4.0]: https://github.com/qniequn-boop/deepseek-harness-glass/releases/tag/v0.4.0
[0.5.0]: https://github.com/qniequn-boop/deepseek-harness-glass/releases/tag/v0.5.0
[0.3.0]: https://github.com/qniequn-boop/deepseek-harness-glass/releases/tag/v0.3.0
