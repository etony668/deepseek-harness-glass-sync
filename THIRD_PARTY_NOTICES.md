# Third-Party Notices

DeepSeek Harness Glass bundles or derives from the following third-party works.
All of them are distributed under permissive licenses; the full license texts
are available at the linked sources.

## Original DeepSeek Harness Glass project

- Project: <https://github.com/qniequn-boop/deepseek-harness-glass>
- License: MIT
- Usage: this project began as a derivative of that native Swift Liquid Glass
  shell. Its attribution is retained while this repository adds official-source
  synchronization, embedded pnpm/plugin management, and reliability work.

## DeepSeek Harness

- Project: <https://github.com/deepseek-ai/deepseek-harness>
- License: MIT
- Usage: the complete `@deepseek-ai/dsh` runtime is built from the pinned
  official source submodule and deployed unchanged into the app, including its
  web frontend and shipped profile bundles. The whale favicon in
  `build/icon.icns` is derived from the dsh repository's
  `apps/web/public/favicon.svg`.

## Node.js

- Project: <https://nodejs.org/>
- License: MIT (with bundled dependencies under their own permissive licenses)
- Usage: the official Node.js v24 darwin-arm64 binary is bundled to run the
  dsh backend. A fixed pnpm package is also bundled and launched through that
  Node binary for official `dsh plugin --profile web` management, so end users
  do not need a system Node.js or pnpm installation.

## pnpm

- Project: <https://pnpm.io/>
- License: MIT
- Usage: the fixed pnpm release declared in `glass/runtime/versions.env` is
  bundled only to run the official Harness profile-plugin manager.

## Apple platform APIs

- The Liquid Glass window uses public SwiftUI/AppKit APIs
  (`glassEffect`, `NSVisualEffectView`, transparency and full-size-content
  window options) available on macOS 26 and later. No private APIs are used.

## Fonts

- The user interface uses fonts shipped with the dsh web frontend and macOS
  system fonts.
